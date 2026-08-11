"""Root logger file + console configuration for persistent backend logs."""

from __future__ import annotations

import logging
from pathlib import Path

from logging_config import configure_logging, reset_logging_for_tests


def test_configure_logging_writes_to_rotating_file(tmp_path: Path) -> None:
    reset_logging_for_tests()
    log_dir = tmp_path / "logs"
    configure_logging(log_dir=log_dir, max_bytes=1024, backup_count=2)

    logger = logging.getLogger("elixr.test.logging")
    logger.info("hello persistent log")

    log_file = log_dir / "backend.log"
    assert log_file.is_file()
    contents = log_file.read_text(encoding="utf-8")
    assert "hello persistent log" in contents


def test_configure_logging_is_idempotent(tmp_path: Path) -> None:
    reset_logging_for_tests()
    configure_logging(log_dir=tmp_path / "logs")
    root = logging.getLogger()
    handler_count = len(root.handlers)

    configure_logging(log_dir=tmp_path / "logs")
    assert len(root.handlers) == handler_count
