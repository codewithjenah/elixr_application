from __future__ import annotations

from pathlib import Path

import runtime_paths


def test_source_resource_root_is_backend_directory() -> None:
    assert runtime_paths.resource_root() == Path(runtime_paths.__file__).resolve().parent
    assert runtime_paths.model_dir() == runtime_paths.resource_root() / "models"


def test_writable_data_root_uses_local_app_data(monkeypatch) -> None:
    monkeypatch.setenv("LOCALAPPDATA", r"C:\Users\Pilot\AppData\Local")
    monkeypatch.delenv("APPDATA", raising=False)

    assert runtime_paths.writable_data_root() == Path(
        r"C:\Users\Pilot\AppData\Local\ELIXR"
    )


def test_frozen_resource_root_uses_executable_directory(monkeypatch, tmp_path: Path) -> None:
    executable = tmp_path / "elixr_backend.exe"
    monkeypatch.setattr(runtime_paths.sys, "frozen", True, raising=False)
    monkeypatch.setattr(runtime_paths.sys, "executable", str(executable))
    monkeypatch.delattr(runtime_paths.sys, "_MEIPASS", raising=False)

    assert runtime_paths.is_frozen() is True
    assert runtime_paths.resource_root() == tmp_path


def test_frozen_resource_root_uses_pyinstaller_contents_directory(
    monkeypatch, tmp_path: Path
) -> None:
    internal = tmp_path / "_internal"
    monkeypatch.setattr(runtime_paths.sys, "frozen", True, raising=False)
    monkeypatch.setattr(runtime_paths.sys, "_MEIPASS", str(internal), raising=False)

    assert runtime_paths.resource_root() == internal
