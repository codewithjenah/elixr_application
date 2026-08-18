"""User-triggered Bartender capture and quality gate. Benchmark-only."""

from __future__ import annotations

import ast
from pathlib import Path

import numpy as np
import pytest

from vision.hands_benchmark import (
    SCENE_TAGS,
    TimedCaptureFrame,
    apply_scene_tags,
    evaluate_capture_quality,
    parse_tag_range_args,
)
from vision.hands_capture import (
    CaptureCancelled,
    make_owned_camera_hooks,
    run_capture_countdown,
    run_user_triggered_bartender_capture,
    wait_for_capture_ready,
)
from vision.hands_roi_policies import n2_recommendation
from vision.types import BottleDetection


def _record(index: int, *, bottle=None, tag="", rel_ms=None):
    return TimedCaptureFrame(
        filename=f"{index:04d}.jpg",
        sequence=index,
        captured_at_monotonic=index * 0.04,
        relative_time_ms=int(rel_ms if rel_ms is not None else index * 40),
        movement_label="Bartender's Grip",
        scene_tag=tag,
        bottle=bottle,
    )


def _bottle_dict():
    return {
        "x1": 200.0,
        "y1": 100.0,
        "x2": 280.0,
        "y2": 300.0,
        "confidence": 0.9,
        "track_id": -1.0,
        "yolo_confirmed": 1.0,
    }


def test_double_hand_capture_prompt_waits_for_enter():
    printed = []

    def input_fn(prompt=""):
        printed.append("enter")
        return ""

    result = run_user_triggered_bartender_capture(
        count=1,
        timeout_s=1.0,
        input_fn=input_fn,
        sleep_fn=lambda _s: None,
        print_fn=lambda message="": printed.append(str(message)),
        open_camera_fn=lambda: True,
        capture_frames_fn=lambda **_k: (
            [np.zeros((8, 8, 3), dtype=np.uint8)],
            [_record(1)],
        ),
        release_fn=lambda: None,
        ready_prompt="Double Hand Stall Benchmark Capture",
    )
    assert result.cancelled is False
    assert "enter" in printed
    joined = "\n".join(printed)
    assert "Double Hand Stall Benchmark Capture" in joined
    assert joined.index("Double Hand Stall Benchmark Capture") < joined.index("enter")


def test_wait_for_enter_does_not_start_saving():
    calls = []

    def input_fn(prompt=""):
        calls.append(("input", prompt))
        return ""

    wait_for_capture_ready(input_fn=input_fn)
    assert calls and calls[0][0] == "input"
    assert "save" not in [item[0] for item in calls]


def test_countdown_occurs_after_enter_and_before_capture():
    order = []

    def input_fn(prompt=""):
        order.append("enter")
        return ""

    def sleep_fn(seconds):
        order.append(("sleep", seconds))

    def print_fn(message=""):
        order.append(("print", str(message)))

    def capture_fn(**kwargs):
        order.append("capture")
        return [np.zeros((8, 8, 3), dtype=np.uint8)], [_record(1)]

    def release_fn():
        order.append("release")

    result = run_user_triggered_bartender_capture(
        count=1,
        timeout_s=1.0,
        input_fn=input_fn,
        sleep_fn=sleep_fn,
        print_fn=print_fn,
        open_camera_fn=lambda: True,
        capture_frames_fn=capture_fn,
        release_fn=release_fn,
    )
    assert result.cancelled is False
    assert result.started_saving is True
    enter_at = order.index("enter")
    capture_at = order.index("capture")
    sleeps = [item for item in order if item[0] == "sleep"]
    assert enter_at < capture_at
    assert len(sleeps) == 3
    assert all(item[1] == 1.0 for item in sleeps)
    assert order.index(sleeps[0]) > enter_at
    assert order.index(sleeps[-1]) < capture_at
    printed = "\n".join(item[1] for item in order if item[0] == "print")
    assert "Starting capture in..." in printed
    assert "CAPTURING" in printed
    assert "Capture complete." in printed


def test_frames_are_only_saved_after_countdown():
    saved_before_countdown = []

    def input_fn(prompt=""):
        return ""

    countdown_done = {"value": False}

    def sleep_fn(seconds):
        countdown_done["value"] = True

    def capture_fn(**kwargs):
        assert countdown_done["value"] is True
        saved_before_countdown.append(False)
        return [np.zeros((8, 8, 3), dtype=np.uint8)], [_record(1)]

    run_user_triggered_bartender_capture(
        count=1,
        timeout_s=1.0,
        input_fn=input_fn,
        sleep_fn=sleep_fn,
        print_fn=lambda *_args, **_kwargs: None,
        open_camera_fn=lambda: True,
        capture_frames_fn=capture_fn,
        release_fn=lambda: None,
    )
    assert saved_before_countdown == [False]


def test_cancellation_before_capture_does_not_run_benchmark():
    released = {"camera": False}

    def input_fn(prompt=""):
        raise KeyboardInterrupt

    result = run_user_triggered_bartender_capture(
        count=180,
        timeout_s=10.0,
        input_fn=input_fn,
        sleep_fn=lambda _s: None,
        print_fn=lambda *_a, **_k: None,
        open_camera_fn=lambda: True,
        capture_frames_fn=lambda **_k: (_ for _ in ()).throw(AssertionError("capture")),
        release_fn=lambda: released.__setitem__("camera", True),
        close_detectors_fn=lambda: released.__setitem__("detectors", True),
    )
    assert result.cancelled is True
    assert result.run_benchmark is False
    assert result.started_saving is False
    assert released["camera"] is True
    assert released.get("detectors") is True
    assert "Capture cancelled. Benchmark was not run." in result.message


def test_cancellation_during_capture_releases_camera():
    released = {"camera": False}

    def capture_fn(**kwargs):
        raise KeyboardInterrupt

    result = run_user_triggered_bartender_capture(
        count=180,
        timeout_s=10.0,
        input_fn=lambda prompt="": "",
        sleep_fn=lambda _s: None,
        print_fn=lambda *_a, **_k: None,
        open_camera_fn=lambda: True,
        capture_frames_fn=capture_fn,
        release_fn=lambda: released.__setitem__("camera", True),
    )
    assert result.cancelled is True
    assert result.run_benchmark is False
    assert released["camera"] is True


def test_countdown_helper_prints_3_2_1():
    printed = []
    slept = []
    run_capture_countdown(sleep_fn=slept.append, print_fn=printed.append)
    assert printed[0] == "Starting capture in..."
    assert "3" in printed
    assert "2" in printed
    assert "1" in printed
    assert printed[-1] == "CAPTURING"
    assert slept == [1.0, 1.0, 1.0]


def test_tag_range_zero_start_is_inclusive_human_ranges():
    ranges = parse_tag_range_args(
        [
            "0:60=valid_hold",
            "61:85=partial_occlusion",
            "86:105=leaving_contact_zone",
            "106:125=entering_contact_zone",
            "126:180=valid_hold",
        ]
    )
    assert ranges[0] == ("valid_hold", 1, 60)
    assert ranges[1] == ("partial_occlusion", 61, 85)
    assert ranges[-1] == ("valid_hold", 126, 180)
    assert "no_hand" in SCENE_TAGS
    assert "no_bottle" in SCENE_TAGS


def test_completed_capture_quality_report_counts_coverage():
    bottles = []
    records = []
    hands = []
    for index in range(1, 181):
        present = index != 10
        bottle = _bottle_dict() if present else None
        bottles.append(
            None
            if bottle is None
            else BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.9)
        )
        tag = "valid_hold" if index <= 100 else "partial_occlusion"
        records.append(_record(index, bottle=bottle, tag=tag))
        hands.append(index != 12)
    report = evaluate_capture_quality(
        records,
        bottles,
        hands,
        tags_supplied=True,
    )
    assert report["total_captured_frames"] == 180
    assert report["bottle_present_frames"] == 179
    assert report["bottle_present_rate"] == pytest.approx(179 / 180)
    assert report["primary_hand_present_frames"] == 179
    assert report["tag_counts"]["valid_hold"] == 100
    assert report["tag_counts"]["partial_occlusion"] == 80
    assert report["longest_no_bottle_run"] == 1
    assert report["longest_no_hand_run"] == 1
    assert report["valid_for_production_decision"] is True


def test_invalid_quality_prevents_production_recommendation():
    records = [_record(index) for index in range(1, 21)]
    bottles = [None] * 20
    hands = [False] * 20
    quality = evaluate_capture_quality(
        records,
        bottles,
        hands,
        tags_supplied=False,
    )
    assert quality["valid_for_production_decision"] is False
    rec = n2_recommendation(
        {"attempts": 20, "hands_mean_ms": 40, "hands_p95_ms": 80, "usable_rate": 0.5, "longest_usable_miss_run": 2, "total_roi_time_ms": 200},
        {"attempts": 10, "hands_mean_ms": 20, "hands_p95_ms": 40, "usable_rate": 0.5, "longest_usable_miss_run": 2, "total_roi_time_ms": 80},
        {
            "lost_recoveries": 0,
            "mean_recovery_delay_frames": 1,
            "max_recovery_delay_frames": 1,
            "max_recovery_delay_ms": 40,
        },
        capture_valid=False,
        first_miss_lost=0,
        valid_hold_ok=True,
        partial_occlusion_ok=True,
    )
    assert rec["production_recommendation"] == "KEEP IMMEDIATE ROI"
    assert rec["use_n2"] is False
    assert "Human scene tags were not supplied." in quality["notes"]


def test_capture_cancelled_exception_is_distinct():
    with pytest.raises(CaptureCancelled):
        raise CaptureCancelled("Capture cancelled. Benchmark was not run.")


class _FakeCamera:
    def __init__(self, *, open_ok=True, fail_after_construct=False):
        self.open_ok = open_ok
        self.fail_after_construct = fail_after_construct
        self.opened = False
        self.release_calls = 0
        if fail_after_construct:
            raise RuntimeError("construct failed")

    def open(self):
        self.opened = True
        return self.open_ok

    def release(self):
        self.release_calls += 1

    def peek_latest(self, timeout=1.0):
        return None


def _frame_pair(count=1):
    frames = [np.zeros((8, 8, 3), dtype=np.uint8) for _ in range(count)]
    records = [_record(index) for index in range(1, count + 1)]
    return frames, records


def _run_session(**overrides):
    kwargs = dict(
        count=1,
        timeout_s=1.0,
        input_fn=lambda prompt="": "",
        sleep_fn=lambda _s: None,
        print_fn=lambda *_a, **_k: None,
        open_camera_fn=lambda: True,
        capture_frames_fn=lambda **_k: _frame_pair(1),
        release_fn=lambda: None,
    )
    kwargs.update(overrides)
    return run_user_triggered_bartender_capture(**kwargs)


def test_normal_completion_releases_resources_once():
    released = {"count": 0}

    result = _run_session(release_fn=lambda: released.__setitem__(
        "count", released["count"] + 1
    ))
    assert result.cancelled is False
    assert result.run_benchmark is True
    assert result.camera_released is True
    assert released["count"] == 1


def test_incomplete_capture_does_not_run_benchmark():
    released = {"count": 0}
    result = _run_session(
        count=3,
        capture_frames_fn=lambda **_k: _frame_pair(1),
        release_fn=lambda: released.__setitem__("count", released["count"] + 1),
    )
    assert result.cancelled is False
    assert result.run_benchmark is False
    assert result.started_saving is True
    assert released["count"] == 1
    assert "Benchmark was not run" in result.message


def test_open_failure_releases_initialized_resources_only():
    cameras = []

    def camera_factory():
        camera = _FakeCamera(open_ok=False)
        cameras.append(camera)
        return camera

    def after_open(_camera):
        raise AssertionError("must not peek after failed open")

    def capture_fn(**_kwargs):
        raise AssertionError("must not capture after failed open")

    open_fn, capture_wrapped, release_fn = make_owned_camera_hooks(
        camera_factory=camera_factory,
        capture_frames_fn=capture_fn,
        after_open=after_open,
    )
    detectors_closed = {"value": False}
    result = _run_session(
        open_camera_fn=open_fn,
        capture_frames_fn=capture_wrapped,
        release_fn=release_fn,
        close_detectors_fn=lambda: detectors_closed.__setitem__("value", True),
    )
    assert result.cancelled is True
    assert result.run_benchmark is False
    assert result.started_saving is False
    assert cameras[0].opened is True
    assert cameras[0].release_calls == 1
    assert detectors_closed["value"] is True


def test_construct_failure_does_not_release_uninitialized_camera():
    open_fn, capture_fn, release_fn = make_owned_camera_hooks(
        camera_factory=lambda: _FakeCamera(fail_after_construct=True),
        capture_frames_fn=lambda **_k: (_ for _ in ()).throw(
            AssertionError("capture")
        ),
    )
    with pytest.raises(RuntimeError, match="construct failed"):
        _run_session(
            open_camera_fn=open_fn,
            capture_frames_fn=capture_fn,
            release_fn=release_fn,
        )
    release_fn()


def test_owned_hooks_release_is_idempotent():
    camera = _FakeCamera()
    open_fn, capture_fn, release_fn = make_owned_camera_hooks(
        camera_factory=lambda: camera,
        capture_frames_fn=lambda **kwargs: _frame_pair(1),
    )
    assert open_fn() is True
    capture_fn(count=1, timeout_s=1.0)
    release_fn()
    release_fn()
    assert camera.release_calls == 1


def test_owned_hooks_are_defined_before_session_call():
    camera = _FakeCamera()
    open_fn, capture_fn, release_fn = make_owned_camera_hooks(
        camera_factory=lambda: camera,
        capture_frames_fn=lambda **kwargs: (
            _frame_pair(kwargs["count"])
        ),
    )
    assert callable(release_fn)
    result = _run_session(
        count=2,
        open_camera_fn=open_fn,
        capture_frames_fn=capture_fn,
        release_fn=release_fn,
    )
    assert result.run_benchmark is True
    assert camera.release_calls == 1


def test_exception_during_capture_releases_and_skips_benchmark():
    released = {"count": 0}

    def capture_fn(**_kwargs):
        raise RuntimeError("peek failed")

    with pytest.raises(RuntimeError, match="peek failed"):
        _run_session(
            capture_frames_fn=capture_fn,
            release_fn=lambda: released.__setitem__("count", released["count"] + 1),
        )
    assert released["count"] == 1


def test_cancellation_during_countdown_releases_without_capture():
    captured = {"count": 0}
    released = {"count": 0}

    def sleep_fn(_seconds):
        raise KeyboardInterrupt

    def capture_fn(**_kwargs):
        captured["count"] += 1
        return _frame_pair(1)

    with pytest.raises(KeyboardInterrupt):
        _run_session(
            sleep_fn=sleep_fn,
            capture_frames_fn=capture_fn,
            release_fn=lambda: released.__setitem__("count", released["count"] + 1),
        )
    assert captured["count"] == 0
    assert released["count"] == 1


def _bind_targets(target) -> set[str]:
    names: set[str] = set()
    if isinstance(target, ast.Name):
        names.add(target.id)
    elif isinstance(target, (ast.Tuple, ast.List)):
        for elt in target.elts:
            names |= _bind_targets(elt)
    elif isinstance(target, ast.Starred):
        names |= _bind_targets(target.value)
    return names


def _iter_calls(node):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
        return
    if isinstance(node, ast.Call):
        yield node
    for child in ast.iter_child_nodes(node):
        if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            continue
        yield from _iter_calls(child)


_COMPOUND = (ast.If, ast.Try, ast.With, ast.For, ast.While)


def _scan_release_fn_bindings(stmts, bound: set[str]) -> None:
    for node in stmts:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            bound.add(node.name)
            nested = {arg.arg for arg in (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs)}
            nested.update(bound)
            _scan_release_fn_bindings(node.body, nested)
            continue
        if not isinstance(node, _COMPOUND):
            for call in _iter_calls(node):
                for keyword in call.keywords:
                    if keyword.arg != "release_fn":
                        continue
                    if isinstance(keyword.value, ast.Name):
                        assert keyword.value.id in bound, (
                            f"release_fn={keyword.value.id} is not defined in this scope"
                        )
        if isinstance(node, ast.Assign):
            for target in node.targets:
                bound |= _bind_targets(target)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            bound.add(node.target.id)
        if isinstance(node, ast.If):
            _scan_release_fn_bindings(node.body, bound)
            _scan_release_fn_bindings(node.orelse, bound)
        elif isinstance(node, ast.Try):
            _scan_release_fn_bindings(node.body, bound)
            for handler in node.handlers:
                _scan_release_fn_bindings(handler.body, bound)
            _scan_release_fn_bindings(node.orelse, bound)
            _scan_release_fn_bindings(node.finalbody, bound)
        elif isinstance(node, ast.With):
            _scan_release_fn_bindings(node.body, bound)
        elif isinstance(node, ast.For):
            bound |= _bind_targets(node.target)
            _scan_release_fn_bindings(node.body, bound)
            _scan_release_fn_bindings(node.orelse, bound)
        elif isinstance(node, ast.While):
            _scan_release_fn_bindings(node.body, bound)
            _scan_release_fn_bindings(node.orelse, bound)


def test_benchmark_script_does_not_call_undefined_release_helper():
    script = Path(__file__).resolve().parents[1] / "scripts" / "benchmark_hands.py"
    tree = ast.parse(script.read_text(encoding="utf-8"))
    main = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "main"
    )
    bound = {arg.arg for arg in (*main.args.posonlyargs, *main.args.args, *main.args.kwonlyargs)}
    _scan_release_fn_bindings(main.body, bound)
