"""Benchmark PyTorch vs ONNX Runtime for the combined prop model.

Run from backend/:
    python scripts/benchmark_prop_runtime.py
"""

from __future__ import annotations

import argparse
import statistics
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import (
    MAX_BOTTLES,
    YOLO_BOTTLE_CONFIDENCE,
    YOLO_IMGSZ,
    YOLO_IOU,
    YOLO_MODEL_PATH,
    YOLO_ONNX_INTRA_OP_THREADS,
    YOLO_ONNX_MODEL_PATH,
    YOLO_SHAKER_CONFIDENCE,
)
from vision.prop_inference import (
    OnnxPropBackend,
    PropInferenceBackend,
    PyTorchPropBackend,
    dml_is_available,
)


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(round((pct / 100.0) * (len(ordered) - 1)))))
    return ordered[index]


def _stats(samples_s: list[float]) -> dict[str, float]:
    if not samples_s:
        return {
            "mean_ms": 0.0,
            "median_ms": 0.0,
            "p95_ms": 0.0,
            "fps": 0.0,
        }
    mean = statistics.fmean(samples_s)
    return {
        "mean_ms": mean * 1000.0,
        "median_ms": statistics.median(samples_s) * 1000.0,
        "p95_ms": _percentile(samples_s, 95) * 1000.0,
        "fps": (1.0 / mean) if mean > 0 else 0.0,
    }


def representative_frames(
    count: int,
    *,
    height: int = 480,
    width: int = 640,
    seed: int = 20260818,
) -> list[np.ndarray]:
    rng = np.random.default_rng(seed)
    frames: list[np.ndarray] = [np.zeros((height, width, 3), dtype=np.uint8)]
    tall = np.full((height, width, 3), 40, dtype=np.uint8)
    tall[70:410, 270:370] = (18, 48, 210)
    frames.append(tall)
    remaining = max(0, count - len(frames))
    for _ in range(remaining):
        frames.append(rng.integers(0, 256, size=(height, width, 3), dtype=np.uint8))
    return frames[:count]


def _inference_kwargs() -> dict[str, float | int]:
    return {
        "conf": min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        "iou": YOLO_IOU,
        "max_det": MAX_BOTTLES * 2,
        "imgsz": YOLO_IMGSZ,
    }


def _load_pytorch() -> PropInferenceBackend:
    backend = PyTorchPropBackend(
        YOLO_MODEL_PATH,
        inference_conf=min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
        imgsz=YOLO_IMGSZ,
    )
    backend.load()
    return backend


def _load_onnx(runtime_name: str, providers: list[object]) -> PropInferenceBackend:
    backend = OnnxPropBackend(
        YOLO_ONNX_MODEL_PATH,
        runtime_name=runtime_name,
        providers=providers,
        imgsz=YOLO_IMGSZ,
        intra_op_threads=YOLO_ONNX_INTRA_OP_THREADS,
        inference_conf=min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
    )
    backend.load()
    return backend


def benchmark_backend(
    backend: PropInferenceBackend,
    frames: list[np.ndarray],
    *,
    warmup: int,
    runs: int,
    load_s: float,
) -> dict[str, float | str | int]:
    kwargs = _inference_kwargs()
    warmup_start = time.perf_counter()
    for index in range(warmup):
        backend.infer(frames[index % len(frames)], **kwargs)
    warmup_s = time.perf_counter() - warmup_start

    samples: list[float] = []
    for index in range(runs):
        frame = frames[index % len(frames)]
        started = time.perf_counter()
        backend.infer(frame, **kwargs)
        samples.append(time.perf_counter() - started)
    stats = _stats(samples)
    return {
        "runtime": backend.runtime_name,
        "provider": backend.provider,
        "model": Path(backend.model_path).name,
        "load_ms": load_s * 1000.0,
        "warmup_ms": warmup_s * 1000.0,
        "runs": runs,
        "threads": YOLO_ONNX_INTRA_OP_THREADS,
        **stats,
    }


def _print_result(row: dict[str, float | str | int]) -> None:
    print(
        f"{row['runtime']:10} provider={row['provider']} model={row['model']} "
        f"load={row['load_ms']:.1f}ms warmup={row['warmup_ms']:.1f}ms "
        f"mean={row['mean_ms']:.2f}ms median={row['median_ms']:.2f}ms "
        f"p95={row['p95_ms']:.2f}ms fps={row['fps']:.2f} runs={row['runs']}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--runs", type=int, default=50)
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument("--include-dml", action="store_true")
    args = parser.parse_args()
    frames = representative_frames(args.frames)
    print(
        f"Benchmark frames={len(frames)} size={frames[0].shape} "
        f"imgsz={YOLO_IMGSZ} conf={min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE)} "
        f"iou={YOLO_IOU} intra_op={YOLO_ONNX_INTRA_OP_THREADS}"
    )

    started = time.perf_counter()
    pytorch = _load_pytorch()
    pytorch_row = benchmark_backend(
        pytorch,
        frames,
        warmup=args.warmup,
        runs=args.runs,
        load_s=time.perf_counter() - started,
    )
    _print_result(pytorch_row)

    if not YOLO_ONNX_MODEL_PATH.is_file():
        print("ONNX skipped: best.onnx is missing. Run scripts/export_prop_onnx.py")
        return

    started = time.perf_counter()
    onnx_cpu = _load_onnx("onnx_cpu", ["CPUExecutionProvider"])
    onnx_row = benchmark_backend(
        onnx_cpu,
        frames,
        warmup=args.warmup,
        runs=args.runs,
        load_s=time.perf_counter() - started,
    )
    _print_result(onnx_row)

    if args.include_dml or dml_is_available():
        if not dml_is_available():
            print("DirectML skipped: DmlExecutionProvider is not available")
            return
        started = time.perf_counter()
        onnx_dml = _load_onnx(
            "onnx_dml",
            [("DmlExecutionProvider", {"device_id": 0}), "CPUExecutionProvider"],
        )
        dml_row = benchmark_backend(
            onnx_dml,
            frames,
            warmup=args.warmup,
            runs=args.runs,
            load_s=time.perf_counter() - started,
        )
        _print_result(dml_row)


if __name__ == "__main__":
    main()
