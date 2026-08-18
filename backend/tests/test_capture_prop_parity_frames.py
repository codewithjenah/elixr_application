"""Capture-helper tests. Camera hardware is always mocked."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from vision.prop_parity import capture_parity_frames, write_parity_frame


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
