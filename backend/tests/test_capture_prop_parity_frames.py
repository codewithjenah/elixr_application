"""Capture-helper tests. Camera hardware is always mocked."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from vision.prop_parity import (
    PARITY_CAPTURE_GUIDANCE,
    capture_parity_frames,
    capture_parity_frames_interactive,
    next_parity_frame_index,
    write_parity_frame,
)


def test_write_parity_frame_saves_jpeg(tmp_path: Path):
    frame = np.zeros((16, 20, 3), dtype=np.uint8)
    path = write_parity_frame(tmp_path, 3, frame)
    assert path == tmp_path / "003.jpg"
    assert path.is_file()
    assert path.stat().st_size > 0


def test_capture_parity_frames_uses_injected_reader(tmp_path: Path):
    frames = [np.full((8, 8, 3), value, dtype=np.uint8) for value in (10, 20, 30)]
    iterator = iter(frames)
    saved = capture_parity_frames(
        read_frame=lambda: next(iterator),
        output_dir=tmp_path,
        count=3,
    )
    assert [path.name for path in saved] == ["001.jpg", "002.jpg", "003.jpg"]
    assert all(path.is_file() for path in saved)


def test_capture_parity_frames_stops_when_reader_returns_none(tmp_path: Path):
    with pytest.raises(RuntimeError, match="camera"):
        capture_parity_frames(
            read_frame=lambda: None,
            output_dir=tmp_path,
            count=2,
        )


def test_capture_script_list_only_uses_injected_discovery(monkeypatch, capsys):
    import importlib.util
    from pathlib import Path

    script = Path(__file__).resolve().parents[1] / "scripts" / "capture_prop_parity_frames.py"
    spec = importlib.util.spec_from_file_location("capture_prop_parity_frames", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    monkeypatch.setattr(
        module,
        "discover_cameras",
        lambda: {
            "cameras": [
                {
                    "device_id": "opencv:0",
                    "display_name": "Camera 0",
                    "runtime_index": 0,
                    "identity_stable": False,
                    "is_active": False,
                }
            ]
        },
    )

    assert module.main(["--list-only"]) == 0
    output = capsys.readouterr().out
    assert "opencv:0" in output
    assert "Camera 0" in output


def test_write_parity_frame_does_not_overwrite_existing(tmp_path: Path):
    first = np.full((8, 8, 3), 11, dtype=np.uint8)
    second = np.full((8, 8, 3), 99, dtype=np.uint8)
    path = write_parity_frame(tmp_path, 1, first)
    original = path.read_bytes()
    with pytest.raises(FileExistsError, match="001.jpg"):
        write_parity_frame(tmp_path, 1, second)
    assert path.read_bytes() == original


def test_next_parity_frame_index_appends_after_existing_files(tmp_path: Path):
    for index in range(1, 21):
        (tmp_path / f"{index:03d}.jpg").write_bytes(b"x")
    assert next_parity_frame_index(tmp_path) == 21


def test_next_parity_frame_index_uses_max_plus_one_not_gap_fill(tmp_path: Path):
    (tmp_path / "001.jpg").write_bytes(b"x")
    (tmp_path / "003.jpg").write_bytes(b"x")
    assert next_parity_frame_index(tmp_path) == 4


def test_next_parity_frame_index_empty_directory_starts_at_one(tmp_path: Path):
    assert next_parity_frame_index(tmp_path) == 1


def test_capture_parity_frames_appends_without_overwriting(tmp_path: Path):
    original_frame = np.full((8, 8, 3), 3, dtype=np.uint8)
    write_parity_frame(tmp_path, 1, original_frame)
    original_bytes = (tmp_path / "001.jpg").read_bytes()
    saved = capture_parity_frames(
        read_frame=lambda: np.full((8, 8, 3), 10, dtype=np.uint8),
        output_dir=tmp_path,
        count=1,
    )
    assert [path.name for path in saved] == ["002.jpg"]
    assert (tmp_path / "001.jpg").read_bytes() == original_bytes
    assert (tmp_path / "002.jpg").is_file()


def test_interactive_capture_exits_cleanly_on_q(tmp_path: Path):
    peeked: list[object] = []

    def peek(_newer_than):
        peeked.append(1)
        return SimpleNamespace(frame=np.zeros((8, 8, 3), dtype=np.uint8), sequence=1)

    printed: list[str] = []
    saved = capture_parity_frames_interactive(
        peek_frame=peek,
        output_dir=tmp_path,
        input_fn=lambda _prompt: "q",
        print_fn=printed.append,
    )
    assert saved == []
    assert peeked == []
    assert list(tmp_path.iterdir()) == []
    text = "\n".join(printed)
    assert "Press ENTER to capture frame" in text
    assert "Type q + ENTER to finish" in text


def test_interactive_capture_prints_collection_guidance(tmp_path: Path):
    printed: list[str] = []
    capture_parity_frames_interactive(
        peek_frame=lambda _newer_than: None,
        output_dir=tmp_path,
        input_fn=lambda _prompt: "q",
        print_fn=printed.append,
    )
    text = "\n".join(printed)
    for snippet in (
        "bottle only",
        "shaker only",
        "bottle + shaker",
        "near/far",
        "left/right/center",
        "partial visibility",
        "different rotations",
        "different backgrounds/lighting",
    ):
        assert snippet in text
    assert "parity images" in text.lower() or "not a new YOLO" in text
    assert PARITY_CAPTURE_GUIDANCE in text


def test_interactive_capture_saves_one_new_frame_per_enter(tmp_path: Path):
    state = {"seq": 0, "newer_than": []}

    def peek(newer_than):
        state["newer_than"].append(newer_than)
        state["seq"] += 1
        return SimpleNamespace(
            frame=np.full((8, 8, 3), state["seq"], dtype=np.uint8),
            sequence=state["seq"],
        )

    commands = iter(["", "", "q"])
    printed: list[str] = []
    saved = capture_parity_frames_interactive(
        peek_frame=peek,
        output_dir=tmp_path,
        input_fn=lambda _prompt: next(commands),
        print_fn=printed.append,
    )
    assert [path.name for path in saved] == ["001.jpg", "002.jpg"]
    assert state["newer_than"] == [None, 1]
    joined = "\n".join(printed)
    assert f"Saved {tmp_path.name}/001.jpg" in joined
    assert f"Saved {tmp_path.name}/002.jpg" in joined


def test_interactive_capture_does_not_save_repeated_sequence(tmp_path: Path):
    def peek(_newer_than):
        return SimpleNamespace(
            frame=np.full((8, 8, 3), 7, dtype=np.uint8),
            sequence=5,
        )

    commands = iter(["", "", "q"])
    printed: list[str] = []
    saved = capture_parity_frames_interactive(
        peek_frame=peek,
        output_dir=tmp_path,
        input_fn=lambda _prompt: next(commands),
        print_fn=printed.append,
    )
    assert len(saved) == 1
    assert saved[0].name == "001.jpg"
    assert (tmp_path / "002.jpg").exists() is False
    assert any("not saved" in line.lower() for line in printed)


def test_interactive_capture_appends_after_existing_files(tmp_path: Path):
    write_parity_frame(tmp_path, 20, np.zeros((8, 8, 3), dtype=np.uint8))
    original = (tmp_path / "020.jpg").read_bytes()

    def peek(_newer_than):
        return SimpleNamespace(
            frame=np.full((8, 8, 3), 4, dtype=np.uint8),
            sequence=9,
        )

    commands = iter(["", "q"])
    saved = capture_parity_frames_interactive(
        peek_frame=peek,
        output_dir=tmp_path,
        input_fn=lambda _prompt: next(commands),
        print_fn=lambda _line: None,
    )
    assert [path.name for path in saved] == ["021.jpg"]
    assert (tmp_path / "020.jpg").read_bytes() == original


def _load_capture_module():
    import importlib.util

    script = Path(__file__).resolve().parents[1] / "scripts" / "capture_prop_parity_frames.py"
    spec = importlib.util.spec_from_file_location("capture_prop_parity_frames_cli", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _FakeCamera:
    def __init__(self, camera_device_id=None):
        self.camera_device_id = camera_device_id
        self.opened = False
        self.released = False
        self.seq = 0
        self.peek_calls: list[int | None] = []

    def open(self) -> bool:
        self.opened = True
        return True

    def release(self) -> None:
        self.released = True

    def peek_latest(self, *, newer_than=None, timeout=None):
        self.peek_calls.append(newer_than)
        self.seq += 1
        return SimpleNamespace(
            frame=np.full((8, 8, 3), self.seq, dtype=np.uint8),
            sequence=self.seq,
        )

    def read(self):
        raise AssertionError("interactive capture must not use CameraCapture.read")


def test_capture_script_interactive_exits_cleanly_without_webcam(tmp_path: Path, monkeypatch):
    module = _load_capture_module()
    camera = _FakeCamera()
    monkeypatch.setattr(module, "discover_cameras", lambda: {"cameras": []})
    monkeypatch.setattr(module, "CameraCapture", lambda **_kwargs: camera)
    monkeypatch.setattr(module, "_prompt_capture", lambda _prompt="": "q")
    code = module.main(["--output", str(tmp_path)])
    assert code == 0
    assert camera.opened is True
    assert camera.released is True
    assert camera.peek_calls == []
    assert list(tmp_path.glob("*.jpg")) == []
