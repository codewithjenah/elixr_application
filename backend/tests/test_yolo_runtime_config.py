"""Startup validation for YOLO runtime selection and ONNX session settings."""

from __future__ import annotations

from pathlib import Path

import pytest

from config import (
    YOLO_DML_DEVICE_ID,
    YOLO_ONNX_MODEL_PATH,
    _load_yolo_dml_device_id,
    _load_yolo_onnx_intra_op_threads,
    _load_yolo_runtime,
)


def test_default_runtime_is_auto(monkeypatch):
    monkeypatch.delenv("YOLO_RUNTIME", raising=False)
    assert _load_yolo_runtime() == "auto"


@pytest.mark.parametrize("raw", ["pytorch", "onnx_cpu", "onnx_dml", "auto"])
def test_runtime_accepts_supported_values(monkeypatch, raw: str):
    monkeypatch.setenv("YOLO_RUNTIME", raw)
    assert _load_yolo_runtime() == raw


def test_runtime_is_case_insensitive(monkeypatch):
    monkeypatch.setenv("YOLO_RUNTIME", "ONNX_CPU")
    assert _load_yolo_runtime() == "onnx_cpu"


@pytest.mark.parametrize("raw", ["", "gpu", "tensorrt", "onnx", "ort", "cpu"])
def test_runtime_rejects_invalid_values(monkeypatch, raw: str):
    monkeypatch.setenv("YOLO_RUNTIME", raw)
    with pytest.raises(ValueError, match="YOLO_RUNTIME"):
        _load_yolo_runtime()


def test_default_onnx_model_path_is_backend_models_best_onnx():
    assert YOLO_ONNX_MODEL_PATH.is_absolute()
    assert YOLO_ONNX_MODEL_PATH.name == "best.onnx"
    assert YOLO_ONNX_MODEL_PATH.parent.name == "models"
    assert YOLO_ONNX_MODEL_PATH.parent == Path(__file__).resolve().parents[1] / "models"


def test_prop_onnx_export_default_imgsz_is_480x640():
    import importlib.util

    script = Path(__file__).resolve().parents[1] / "scripts" / "export_prop_onnx.py"
    spec = importlib.util.spec_from_file_location("export_prop_onnx", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.EXPORT_IMGSZ == (480, 640)
    assert module._parse_imgsz([480, 640]) == (480, 640)
    assert module._parse_imgsz([640]) == 640


def test_onnx_intra_op_threads_default_is_bounded(monkeypatch):
    monkeypatch.delenv("YOLO_ONNX_INTRA_OP_THREADS", raising=False)
    value = _load_yolo_onnx_intra_op_threads(cpu_count=16)
    assert value == 4


def test_onnx_intra_op_threads_does_not_exceed_cpu_count(monkeypatch):
    monkeypatch.delenv("YOLO_ONNX_INTRA_OP_THREADS", raising=False)
    assert _load_yolo_onnx_intra_op_threads(cpu_count=2) == 2


def test_onnx_intra_op_threads_reads_override(monkeypatch):
    monkeypatch.setenv("YOLO_ONNX_INTRA_OP_THREADS", "3")
    assert _load_yolo_onnx_intra_op_threads(cpu_count=16) == 3


def test_onnx_intra_op_threads_zero_means_runtime_default(monkeypatch):
    monkeypatch.setenv("YOLO_ONNX_INTRA_OP_THREADS", "0")
    assert _load_yolo_onnx_intra_op_threads(cpu_count=16) == 0


@pytest.mark.parametrize("raw", ["-1", "abc"])
def test_onnx_intra_op_threads_rejects_invalid(monkeypatch, raw: str):
    monkeypatch.setenv("YOLO_ONNX_INTRA_OP_THREADS", raw)
    with pytest.raises(ValueError, match="YOLO_ONNX_INTRA_OP_THREADS"):
        _load_yolo_onnx_intra_op_threads(cpu_count=8)


def test_default_dml_device_id_is_zero():
    assert YOLO_DML_DEVICE_ID == 0
    assert _load_yolo_dml_device_id() == 0


def test_dml_device_id_reads_override(monkeypatch):
    monkeypatch.setenv("YOLO_DML_DEVICE_ID", "1")
    assert _load_yolo_dml_device_id() == 1


def test_dml_device_id_rejects_negative(monkeypatch):
    monkeypatch.setenv("YOLO_DML_DEVICE_ID", "-1")
    with pytest.raises(ValueError, match="YOLO_DML_DEVICE_ID"):
        _load_yolo_dml_device_id()
