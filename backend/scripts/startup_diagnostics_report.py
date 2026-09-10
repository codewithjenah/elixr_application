"""Aggregate local ELX-010 startup diagnostic JSONL samples.

Usage (from backend/):

    python scripts/startup_diagnostics_report.py
    python scripts/startup_diagnostics_report.py --dir logs/startup_diagnostics

Reads backend ``samples.jsonl`` and Flutter ``client_samples.jsonl``, joins
already-computed durations by ``session_id``, and prints p50/p95 with sample
counts. Never reads or writes camera frames.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from vision.startup_diagnostics import (  # noqa: E402
    START_CLASS_COLD,
    START_CLASS_WARM_CAMERA,
    aggregate_records,
    default_diagnostics_dir,
    load_jsonl,
    merge_backend_and_client,
    record_contains_image_payload,
)


def _discover_files(directories: list[Path]) -> list[Path]:
    files: list[Path] = []
    for directory in directories:
        if not directory.is_dir():
            continue
        files.extend(sorted(directory.glob("*.jsonl")))
        files.extend(sorted(directory.glob("*.json")))
    return files


def _load_all(paths: list[Path]) -> list[dict]:
    records: list[dict] = []
    for path in paths:
        if path.suffix == ".jsonl":
            records.extend(load_jsonl(path))
        else:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                records.append(payload)
            elif isinstance(payload, list):
                records.extend(item for item in payload if isinstance(item, dict))
    return records


def _merge_pairs(records: list[dict]) -> list[dict]:
    by_session: dict[str, dict[str, dict]] = defaultdict(dict)
    unmatched: list[dict] = []
    for record in records:
        session_id = record.get("session_id")
        observer = record.get("observer")
        if not session_id or observer not in {"backend", "client"}:
            unmatched.append(record)
            continue
        by_session[str(session_id)][str(observer)] = record

    merged: list[dict] = []
    for session_id, sides in by_session.items():
        merged.append(
            merge_backend_and_client(sides.get("backend"), sides.get("client"))
        )
    merged.extend(unmatched)
    return merged


def _format_metric(name: str, stats: dict) -> str:
    count = stats.get("n", 0)
    if not count:
        return f"{name}: n=0 p50=null p95=null"
    p50 = stats.get("p50")
    p95 = stats.get("p95")
    minimum = stats.get("min")
    maximum = stats.get("max")
    return (
        f"{name}: n={count} p50={p50:.0f}ms p95={p95:.0f}ms "
        f"min={minimum:.0f}ms max={maximum:.0f}ms"
    )


def _render_report(aggregate: dict, *, sample_count: int, image_violations: int) -> str:
    lines = [
        "# ELX-010 startup diagnostics summary",
        "",
        f"Samples merged: {sample_count}",
        f"Percentile definition: {aggregate['percentile_definition']}",
        "",
        "Cold/warm definition:",
        f"- cold: {aggregate['cold_warm_definition']['cold']}",
        f"- warm_camera: {aggregate['cold_warm_definition']['warm_camera']}",
        f"- warm_model: {aggregate['cold_warm_definition']['warm_model']}",
        "",
        "No camera images, JPEG bytes, or Base64 preview payloads are persisted.",
        f"Image-payload violations in input: {image_violations}",
        "",
    ]
    if not aggregate["groups"]:
        lines.append("No samples found. Run a practice session with diagnostics enabled.")
        lines.append("")
        lines.append("Pilot device matrix: this machine only until two more Windows devices collect real samples.")
        return "\n".join(lines)

    for group in aggregate["groups"]:
        lines.append(
            f"## device={group['pilot_device_id']} start_class={group['start_class']} "
            f"session_mode={group.get('session_mode', 'unknown-mode')} "
            f"samples={group['sample_count']}"
        )
        metrics = group["metrics"]
        for name, stats in metrics.items():
            lines.append(f"- {_format_metric(name, stats)}")
        lines.append("")

    devices = {group["pilot_device_id"] for group in aggregate["groups"]}
    classes = {group["start_class"] for group in aggregate["groups"]}
    lines.append("## Three-device matrix")
    if len(devices) < 3:
        lines.append(
            f"Pending: collected {len(devices)} device(s). "
            "ELX-010 is not benchmark-complete until cold and warm_camera "
            "samples exist for at least three real pilot Windows devices."
        )
    elif START_CLASS_COLD not in classes or START_CLASS_WARM_CAMERA not in classes:
        lines.append(
            "Pending: both cold and warm_camera classes are required on each device."
        )
    else:
        lines.append("Collected device ids: " + ", ".join(sorted(devices)))
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dir",
        action="append",
        dest="directories",
        default=[],
        help="Directory containing JSONL samples. Repeatable.",
    )
    parser.add_argument(
        "--write-summary",
        action="store_true",
        help="Write summary.md next to the first diagnostics directory.",
    )
    args = parser.parse_args()

    directories = [Path(item) for item in args.directories]
    if not directories:
        directories = [
            default_diagnostics_dir(),
            Path.cwd() / "logs" / "startup_diagnostics",
            BACKEND_ROOT.parent / "logs" / "startup_diagnostics",
        ]

    files = _discover_files(directories)
    records = _load_all(files)
    image_violations = sum(1 for record in records if record_contains_image_payload(record))
    if image_violations:
        print(
            f"WARNING: {image_violations} record(s) contained image-like keys; "
            "they are still excluded from interpretation.",
            file=sys.stderr,
        )
    merged = _merge_pairs(records)
    aggregate = aggregate_records(merged)
    report = _render_report(
        aggregate,
        sample_count=len(merged),
        image_violations=image_violations,
    )
    print(report)
    if args.write_summary and directories:
        target = directories[0]
        target.mkdir(parents=True, exist_ok=True)
        (target / "summary.md").write_text(report, encoding="utf-8")
        print(f"Wrote {target / 'summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
