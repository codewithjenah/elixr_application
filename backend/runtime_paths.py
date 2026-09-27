"""Runtime paths for source and PyInstaller-frozen backend execution."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

APP_DATA_DIR_NAME = "ELIXR"


def is_frozen() -> bool:
    """Return whether the backend is running from a frozen executable."""

    return bool(getattr(sys, "frozen", False))


def resource_root() -> Path:
    """Return the read-only directory containing bundled backend resources."""

    if is_frozen():
        # PyInstaller 6 uses an ``_internal`` contents directory for one-folder
        # builds and exposes it through ``_MEIPASS``. Older layouts fall back to
        # the executable directory.
        return Path(
            getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent)
        ).resolve()
    return Path(__file__).resolve().parent


def model_dir() -> Path:
    """Return the directory containing the bundled CV model assets."""

    return resource_root() / "models"


def writable_data_root() -> Path:
    """Return a per-user directory suitable for logs and runtime data."""

    if sys.platform == "darwin":
        # Inside the App Sandbox, HOME is the app's container, so this stays
        # writable and outside the read-only .app bundle.
        return Path.home() / "Library" / "Application Support" / APP_DATA_DIR_NAME
    local_app_data = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA")
    if local_app_data:
        return Path(local_app_data) / APP_DATA_DIR_NAME
    return Path(tempfile.gettempdir()) / APP_DATA_DIR_NAME
