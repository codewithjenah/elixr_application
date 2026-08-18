"""YOLO runtime selection, ONNX session reuse, and detector wiring."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

import vision.prop_detector as prop_detector_mod
from vision.prop_detector import CombinedPropDetector, ModelLoadError, PropDetector
from vision.prop_inference import (
    OnnxPropBackend,
    PropInferenceBackend,
    PyTorchPropBackend,
    RawDetection,
    RuntimeSelection,
    _postprocess_yolo_onnx,
    parse_onnx_class_names,
    parse_onnx_static_input_hw,
    select_prop_runtime,
    split_raw_detections,
    yolo_runtime_info,
    yolo_runtime_threads,
)
from vision.types import PropDetection


def _pt(path: Path) -> Path:
    path.write_bytes(b"weights")
    return path


def _onnx(path: Path) -> Path:
    path.write_bytes(b"onnx")
    return path


def test_auto_prefers_pytorch_even_when_onnx_is_available(tmp_path: Path):
    choice = select_prop_runtime(
        "auto",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=True,
        dml_available=True,
    )
    assert choice == RuntimeSelection(
        runtime="pytorch",
        provider="cpu",
        reason="auto_pytorch",
        fallback_from=None,
    )


def test_auto_uses_onnx_cpu_when_pytorch_weights_are_missing(tmp_path: Path):
    choice = select_prop_runtime(
        "auto",
        pytorch_path=tmp_path / "best.pt",
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=True,
        dml_available=False,
    )
    assert choice.runtime == "onnx_cpu"
    assert choice.reason == "auto_onnx_cpu_pytorch_missing"


def test_auto_does_not_select_directml_even_when_available(tmp_path: Path):
    choice = select_prop_runtime(
        "auto",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=True,
        dml_available=True,
    )
    assert choice.runtime == "pytorch"
    assert choice.provider == "cpu"


def test_missing_onnx_falls_back_to_pytorch(tmp_path: Path):
    choice = select_prop_runtime(
        "onnx_cpu",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=tmp_path / "missing.onnx",
        onnxruntime_available=True,
        dml_available=False,
    )
    assert choice.runtime == "pytorch"
    assert choice.fallback_from == "onnx_cpu"
    assert choice.reason == "fallback_missing_onnx"


def test_onnx_cpu_falls_back_when_onnxruntime_missing(tmp_path: Path):
    choice = select_prop_runtime(
        "onnx_cpu",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=False,
        dml_available=False,
    )
    assert choice.runtime == "pytorch"
    assert choice.fallback_from == "onnx_cpu"
    assert choice.reason == "fallback_onnxruntime_unavailable"


def test_onnx_dml_falls_back_to_onnx_cpu_when_provider_missing(tmp_path: Path):
    choice = select_prop_runtime(
        "onnx_dml",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=True,
        dml_available=False,
    )
    assert choice.runtime == "onnx_cpu"
    assert choice.provider == "CPUExecutionProvider"
    assert choice.fallback_from == "onnx_dml"


def test_onnx_dml_selected_when_provider_available(tmp_path: Path):
    choice = select_prop_runtime(
        "onnx_dml",
        pytorch_path=_pt(tmp_path / "best.pt"),
        onnx_path=_onnx(tmp_path / "best.onnx"),
        onnxruntime_available=True,
        dml_available=True,
    )
    assert choice.runtime == "onnx_dml"
    assert choice.provider == "DmlExecutionProvider"


def test_invalid_runtime_raises():
    with pytest.raises(ModelLoadError, match="YOLO_RUNTIME"):
        select_prop_runtime(
            "tensorrt",
            pytorch_path=Path("best.pt"),
            onnx_path=Path("best.onnx"),
            onnxruntime_available=True,
            dml_available=False,
        )


def test_pytorch_missing_weights_raises(tmp_path: Path):
    with pytest.raises(ModelLoadError, match="missing"):
        select_prop_runtime(
            "pytorch",
            pytorch_path=tmp_path / "missing.pt",
            onnx_path=tmp_path / "best.onnx",
            onnxruntime_available=True,
            dml_available=False,
        )


def test_parse_onnx_class_names_from_ultralytics_metadata():
    names = parse_onnx_class_names(
        {"names": "{0: 'flair_bottle', 1: 'shaker_bottle'}"}
    )
    assert names == {0: "flair_bottle", 1: "shaker_bottle"}


def test_parse_onnx_class_names_rejects_missing_metadata():
    with pytest.raises(ModelLoadError, match="class names"):
        parse_onnx_class_names({})


def test_split_raw_detections_preserves_thresholds_and_sort_order():
    bottles, shakers = split_raw_detections(
        [
            RawDetection(1, 0.41, 2, 3, 12, 20),
            RawDetection(0, 0.99, 1, 1, 10, 10),
            RawDetection(0, 0.50, 8, 8, 18, 18),
            RawDetection(1, 0.39, 4, 4, 9, 9),
        ],
        bottle_class_id=0,
        shaker_class_id=1,
        bottle_conf=0.50,
        shaker_conf=0.40,
    )
    assert [box.confidence for box in bottles] == [0.99, 0.50]
    assert [box.x1 for box in bottles] == [1, 8]
    assert len(shakers) == 1
    assert shakers[0].x1 == 2
    assert shakers[0].confidence == pytest.approx(0.41)


def test_split_raw_detections_converts_to_int_prop_boxes():
    bottles, shakers = split_raw_detections(
        [RawDetection(0, 0.91, 1.9, 2.2, 10.8, 20.1)],
        bottle_class_id=0,
        shaker_class_id=1,
        bottle_conf=0.4,
        shaker_conf=0.4,
    )
    assert shakers == []
    assert bottles == [
        PropDetection(x1=1, y1=2, x2=10, y2=20, confidence=0.91),
    ]


class _StubBackend(PropInferenceBackend):
    def __init__(self, detections: list[RawDetection], names=None):
        self._detections = detections
        self._names = names or {0: "flair_bottle", 1: "shaker_bottle"}
        self.load_calls = 0
        self.infer_calls = 0
        self.runtime_name = "stub"
        self.provider = "stub_provider"
        self.model_path = Path("stub")
        self.intra_op_threads = 0

    @property
    def names(self):
        return dict(self._names)

    def load(self) -> None:
        self.load_calls += 1

    def infer(self, frame: np.ndarray, **kwargs) -> list[RawDetection]:
        self.infer_calls += 1
        assert frame.shape == (32, 32, 3)
        return list(self._detections)


def test_combined_detector_converts_backend_output_and_updates_trackers(tmp_path: Path):
    backend = _StubBackend(
        [
            RawDetection(0, 0.95, 20, 10, 100, 90),
            RawDetection(1, 0.91, 2, 3, 12, 20),
        ]
    )
    detector = CombinedPropDetector(
        model_path=tmp_path / "best.pt",
        inference_backend=backend,
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert backend.load_calls == 1
    assert backend.infer_calls == 1
    assert len(first.bottles) == 1
    assert len(first.shakers) == 1
    assert first.bottles[0].track_id == 1
    assert first.shakers[0].track_id == 1
    assert first.bottles[0].yolo_confirmed is True

    backend._detections = []
    missed = detector.detect_all(frame)
    assert backend.load_calls == 1
    assert backend.infer_calls == 2
    assert missed.bottles[0].track_id == 1
    assert missed.bottles[0].yolo_confirmed is False


def test_injected_backend_skips_file_backed_runtime_selection(tmp_path: Path):
    backend = _StubBackend([])
    detector = CombinedPropDetector(
        model_path=tmp_path / "missing.pt",
        inference_backend=backend,
    )
    detector.ensure_ready()
    assert backend.load_calls == 1
    assert detector.yolo_runtime == "stub"
    assert detector.yolo_provider == "stub_provider"


def test_model_loader_forces_pytorch_path(tmp_path: Path):
    model_path = _pt(tmp_path / "best.pt")
    loaded: list[str] = []

    class _FakeModel:
        names = {0: "flair_bottle", 1: "shaker_bottle"}

        def __call__(self, frame, **kwargs):
            return [SimpleNamespace(boxes=[])]

    def loader(path: str):
        loaded.append(path)
        return _FakeModel()

    detector = CombinedPropDetector(
        model_path=model_path,
        model_loader=loader,
        runtime="onnx_cpu",
    )
    detector.ensure_ready()
    assert loaded == [str(model_path.resolve())]
    assert detector.yolo_runtime == "pytorch"


def test_yolo_runtime_info_reads_prop_and_dual_wrappers(tmp_path: Path):
    backend = _StubBackend([])
    combined = CombinedPropDetector(
        model_path=tmp_path / "best.pt",
        inference_backend=backend,
    )
    combined.ensure_ready()
    prop = PropDetector("bottle", combined_detector=combined)
    assert yolo_runtime_info(prop) == ("stub", "stub_provider")
    assert yolo_runtime_info(combined) == ("stub", "stub_provider")
    assert yolo_runtime_info(object()) == ("", "")
    assert yolo_runtime_threads(prop) == 0
    assert yolo_runtime_threads(combined) == 0


class _FakeOrtSession:
    def __init__(
        self,
        output: np.ndarray | None = None,
        *,
        shape: list[object] | None = None,
        inputs: list[SimpleNamespace] | None = None,
    ):
        self.run_calls = 0
        self.last_feed = None
        self._shape = shape if shape is not None else [1, 3, 640, 640]
        self._inputs = inputs
        self._output = (
            output
            if output is not None
            else np.zeros((1, 6, 8400), dtype=np.float32)
        )

    def get_inputs(self):
        if self._inputs is not None:
            return self._inputs
        return [
            SimpleNamespace(
                name="images",
                shape=self._shape,
                type="tensor(float)",
            )
        ]

    def get_outputs(self):
        return [SimpleNamespace(name="output0")]

    def get_modelmeta(self):
        return SimpleNamespace(
            custom_metadata_map={"names": "{0: 'flair_bottle', 1: 'shaker_bottle'}"}
        )

    def run(self, output_names, feeds):
        self.run_calls += 1
        self.last_feed = feeds
        return [self._output]


def test_onnx_backend_reuses_one_session_across_frames(tmp_path: Path):
    onnx_path = _onnx(tmp_path / "best.onnx")
    created: list[_FakeOrtSession] = []

    def factory(path, sess_options, providers):
        assert path == onnx_path
        assert providers == ["CPUExecutionProvider"]
        session = _FakeOrtSession()
        created.append(session)
        return session

    backend = OnnxPropBackend(
        model_path=onnx_path,
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        session_factory=factory,
        session_options_factory=object,
    )
    frame = np.zeros((48, 64, 3), dtype=np.uint8)
    backend.load()
    backend.infer(frame)
    backend.infer(frame)

    assert len(created) == 1
    assert created[0].run_calls == 2
    assert backend.provider == "CPUExecutionProvider"
    assert backend.names == {0: "flair_bottle", 1: "shaker_bottle"}
    feed = created[0].last_feed["images"]
    assert feed.shape == (1, 3, 640, 640)
    assert feed.dtype == np.float32
    assert feed.max() <= 1.0


def test_onnx_backend_does_not_recreate_session_on_second_load(tmp_path: Path):
    onnx_path = _onnx(tmp_path / "best.onnx")
    created: list[_FakeOrtSession] = []

    def factory(path, sess_options, providers):
        session = _FakeOrtSession()
        created.append(session)
        return session

    backend = OnnxPropBackend(
        model_path=onnx_path,
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        session_factory=factory,
        session_options_factory=object,
    )
    backend.load()
    backend.load()
    assert len(created) == 1


def test_pytorch_backend_passes_elixr_thresholds(tmp_path: Path):
    model_path = _pt(tmp_path / "best.pt")
    calls: list[dict] = []

    class _FakeModel:
        names = {0: "flair_bottle", 1: "shaker_bottle"}

        def __call__(self, frame, **kwargs):
            calls.append(kwargs)
            box = SimpleNamespace(
                cls=np.array([0]),
                conf=np.array([0.88]),
                xyxy=np.array([[1.0, 2.0, 10.0, 20.0]]),
            )
            return [SimpleNamespace(boxes=[box])]

    backend = PyTorchPropBackend(
        model_path=model_path,
        model_loader=lambda _: _FakeModel(),
        inference_conf=0.35,
        iou=0.45,
        max_det=4,
        imgsz=640,
    )
    backend.load()
    detections = backend.infer(np.zeros((32, 32, 3), dtype=np.uint8))
    assert calls[0]["conf"] == pytest.approx(0.35)
    assert calls[0]["iou"] == pytest.approx(0.45)
    assert calls[0]["max_det"] == 4
    assert calls[0]["imgsz"] == 640
    assert detections == [RawDetection(0, 0.88, 1.0, 2.0, 10.0, 20.0)]


def test_onnx_dml_session_uses_device_id(tmp_path: Path):
    onnx_path = _onnx(tmp_path / "best.onnx")
    seen: list[object] = []

    def factory(path, sess_options, providers):
        seen.append(providers)
        return _FakeOrtSession()

    backend = OnnxPropBackend(
        model_path=onnx_path,
        runtime_name="onnx_dml",
        providers=[("DmlExecutionProvider", {"device_id": 1}), "CPUExecutionProvider"],
        session_factory=factory,
        session_options_factory=object,
    )
    backend.load()
    assert seen == [
        [("DmlExecutionProvider", {"device_id": 1}), "CPUExecutionProvider"]
    ]
    assert backend.provider == "DmlExecutionProvider"


def test_gap_confidence_still_applies_after_backend_split(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(prop_detector_mod, "YOLO_BOTTLE_CONFIDENCE", 0.50)
    monkeypatch.setattr(prop_detector_mod, "YOLO_SHAKER_CONFIDENCE", 0.35)
    backend = _StubBackend(
        [
            RawDetection(0, 0.40, 1, 1, 10, 10),
            RawDetection(1, 0.40, 2, 3, 12, 20),
        ]
    )
    detector = CombinedPropDetector(
        model_path=tmp_path / "best.pt",
        inference_backend=backend,
    )
    result = detector.detect_all(np.zeros((32, 32, 3), dtype=np.uint8))
    assert result.bottles == []
    assert len(result.shakers) == 1
    assert result.shakers[0].x1 == 2


class _FailingOnnxBackend(_StubBackend):
    def __init__(self):
        super().__init__([])
        self.runtime_name = "onnx_cpu"
        self.provider = "CPUExecutionProvider"
        self.intra_op_threads = 8

    def load(self) -> None:
        self.load_calls += 1
        raise ModelLoadError("provider creation failed")


def test_onnx_init_failure_falls_back_to_pytorch_once(tmp_path: Path, monkeypatch):
    pytorch_path = _pt(tmp_path / "best.pt")
    onnx_path = _onnx(tmp_path / "best.onnx")
    pytorch_backend = _StubBackend(
        [RawDetection(0, 0.95, 1, 1, 10, 10)],
        names={0: "flair_bottle", 1: "shaker_bottle"},
    )
    pytorch_backend.runtime_name = "pytorch"
    pytorch_backend.provider = "cpu"
    failing = _FailingOnnxBackend()
    created: list[str] = []

    def fake_select(*_args, **_kwargs):
        return RuntimeSelection(
            runtime="onnx_cpu",
            provider="CPUExecutionProvider",
            reason="explicit_onnx_cpu",
            fallback_from=None,
        )

    def fake_create(selection, **_kwargs):
        created.append(selection.runtime)
        if selection.runtime == "onnx_cpu":
            return failing
        return pytorch_backend

    monkeypatch.setattr(prop_detector_mod, "select_prop_runtime", fake_select)
    monkeypatch.setattr(prop_detector_mod, "create_prop_backend", fake_create)

    detector = CombinedPropDetector(
        model_path=pytorch_path,
        onnx_model_path=onnx_path,
        runtime="onnx_cpu",
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)
    first = detector.detect_all(frame)
    second = detector.detect_all(frame)

    assert created == ["onnx_cpu", "pytorch"]
    assert failing.load_calls == 1
    assert pytorch_backend.load_calls == 1
    assert pytorch_backend.infer_calls == 2
    assert detector.yolo_runtime == "pytorch"
    assert detector.load_failed is False
    assert len(first.bottles) == 1
    assert len(second.bottles) == 1


def test_invalid_onnx_class_metadata_falls_back_to_pytorch(tmp_path: Path, monkeypatch):
    pytorch_path = _pt(tmp_path / "best.pt")
    onnx_path = _onnx(tmp_path / "best.onnx")

    class _InvalidNamesBackend(_StubBackend):
        def __init__(self):
            super().__init__([])
            self._names = {0: "not_a_prop"}
            self.runtime_name = "onnx_cpu"

    pytorch_backend = _StubBackend([])
    pytorch_backend.runtime_name = "pytorch"

    def fake_select(*_args, **_kwargs):
        return RuntimeSelection(
            runtime="onnx_cpu",
            provider="CPUExecutionProvider",
            reason="explicit_onnx_cpu",
        )

    def fake_create(selection, **_kwargs):
        if selection.runtime == "onnx_cpu":
            return _InvalidNamesBackend()
        return pytorch_backend

    monkeypatch.setattr(prop_detector_mod, "select_prop_runtime", fake_select)
    monkeypatch.setattr(prop_detector_mod, "create_prop_backend", fake_create)

    detector = CombinedPropDetector(
        model_path=pytorch_path,
        onnx_model_path=onnx_path,
        runtime="onnx_cpu",
    )
    detector.ensure_ready()
    assert detector.yolo_runtime == "pytorch"
    assert pytorch_backend.load_calls == 1


def test_onnx_backend_exposes_intra_op_threads(tmp_path: Path):
    backend = OnnxPropBackend(
        model_path=_onnx(tmp_path / "best.onnx"),
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        intra_op_threads=8,
        session_factory=lambda *_args: _FakeOrtSession(),
        session_options_factory=object,
    )
    backend.load()
    assert backend.intra_op_threads == 8
    detector = CombinedPropDetector(
        model_path=tmp_path / "best.pt",
        inference_backend=backend,
    )
    detector.ensure_ready()
    assert detector.yolo_threads == 8
    assert yolo_runtime_threads(detector) == 8


def test_parse_static_480x640_onnx_input_is_letterbox_target():
    assert parse_onnx_static_input_hw([1, 3, 480, 640]) == (480, 640)


def test_parse_static_640x640_onnx_input_remains_supported():
    assert parse_onnx_static_input_hw([1, 3, 640, 640]) == (640, 640)


@pytest.mark.parametrize(
    "shape",
    [
        None,
        [],
        [1, 3, 480],
        [1, 3, 480, 640, 1],
        [None, 3, 480, 640],
        [1, None, 480, 640],
        [1, 3, None, 640],
        [1, 3, 480, None],
        ["batch", 3, 480, 640],
        [1, 3, "height", "width"],
        [2, 3, 480, 640],
        [1, 1, 480, 640],
        [1, 3, 481, 640],
        [1, 3, 0, 640],
        [-1, 3, 480, 640],
    ],
)
def test_parse_onnx_input_rejects_unsupported_or_ambiguous_shapes(shape):
    with pytest.raises(ModelLoadError, match="ONNX"):
        parse_onnx_static_input_hw(shape)


def test_onnx_backend_letterbox_uses_model_480x640_not_yolo_imgsz(tmp_path: Path):
    session = _FakeOrtSession(shape=[1, 3, 480, 640])
    backend = OnnxPropBackend(
        model_path=_onnx(tmp_path / "best.onnx"),
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        imgsz=640,
        session_factory=lambda *_args: session,
        session_options_factory=object,
    )
    backend.load()
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    backend.infer(frame)
    feed = session.last_feed["images"]
    assert backend.input_height == 480
    assert backend.input_width == 640
    assert feed.shape == (1, 3, 480, 640)
    assert feed.dtype == np.float32
    assert feed.max() <= 1.0


def test_onnx_backend_still_letterboxes_static_640x640(tmp_path: Path):
    session = _FakeOrtSession(shape=[1, 3, 640, 640])
    backend = OnnxPropBackend(
        model_path=_onnx(tmp_path / "best.onnx"),
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        imgsz=480,
        session_factory=lambda *_args: session,
        session_options_factory=object,
    )
    backend.load()
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    backend.infer(frame)
    feed = session.last_feed["images"]
    assert backend.input_height == 640
    assert backend.input_width == 640
    assert feed.shape == (1, 3, 640, 640)


def test_onnx_backend_load_fails_on_dynamic_input_shape(tmp_path: Path):
    backend = OnnxPropBackend(
        model_path=_onnx(tmp_path / "best.onnx"),
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        session_factory=lambda *_args: _FakeOrtSession(shape=[None, 3, None, None]),
        session_options_factory=object,
    )
    with pytest.raises(ModelLoadError, match="ONNX"):
        backend.load()


def test_onnx_backend_load_fails_when_input_shape_is_missing(tmp_path: Path):
    backend = OnnxPropBackend(
        model_path=_onnx(tmp_path / "best.onnx"),
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        session_factory=lambda *_args: _FakeOrtSession(inputs=[]),
        session_options_factory=object,
    )
    with pytest.raises(ModelLoadError, match="ONNX"):
        backend.load()


def test_postprocess_scales_rectangular_letterbox_boxes_to_640x480_source():
    prediction = np.zeros((1, 6, 1), dtype=np.float32)
    prediction[0, 0, 0] = 320.0
    prediction[0, 1, 0] = 240.0
    prediction[0, 2, 0] = 200.0
    prediction[0, 3, 0] = 160.0
    prediction[0, 4, 0] = 0.10
    prediction[0, 5, 0] = 0.92
    detections = _postprocess_yolo_onnx(
        prediction,
        letterboxed_hw=(480, 640),
        orig_shape=(480, 640, 3),
        conf=0.40,
        iou=0.45,
        max_det=4,
        num_classes=2,
    )
    assert len(detections) == 1
    assert detections[0].class_id == 1
    assert detections[0].confidence == pytest.approx(0.92, abs=1e-5)
    assert detections[0].x1 == pytest.approx(220.0, abs=1.0)
    assert detections[0].y1 == pytest.approx(160.0, abs=1.0)
    assert detections[0].x2 == pytest.approx(420.0, abs=1.0)
    assert detections[0].y2 == pytest.approx(320.0, abs=1.0)


def test_pytorch_backend_still_passes_constructor_imgsz_unchanged(tmp_path: Path):
    calls: list[dict] = []

    class _FakeModel:
        names = {0: "flair_bottle", 1: "shaker_bottle"}

        def __call__(self, frame, **kwargs):
            calls.append(kwargs)
            return [SimpleNamespace(boxes=[])]

    backend = PyTorchPropBackend(
        model_path=_pt(tmp_path / "best.pt"),
        model_loader=lambda _: _FakeModel(),
        imgsz=640,
    )
    backend.load()
    backend.infer(np.zeros((480, 640, 3), dtype=np.uint8))
    assert calls[0]["imgsz"] == 640
    assert not hasattr(backend, "input_height")
