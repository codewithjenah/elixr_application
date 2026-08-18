"""Compare PyTorch best.pt vs ONNX best.onnx on the same frames.

Run from backend/:

    python scripts/validate_prop_parity.py
    python scripts/validate_prop_parity.py --images path\\to\\images

Synthetic frames remain available for a smoke check. They are not the
production semantic-parity gate. Use --images with real bottle/shaker photos.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
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
from vision.prop_inference import OnnxPropBackend, PyTorchPropBackend
from vision.prop_parity import (
    STATUS_INSUFFICIENT_COVERAGE,
    STATUS_SEMANTIC_MISMATCH,
    aggregate_directory_parity,
    classify_shaker_parity_diagnosis,
    compare_raw_detections,
    discover_parity_images,
    format_production_decision_line,
    format_raw_detection_line,
    production_keep_drop,
    semantic_class_for,
    summarize_directory_parity,
    summarize_parity,
)


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
    pair = np.full((height, width, 3), 35, dtype=np.uint8)
    pair[90:360, 120:190] = (22, 50, 200)
    pair[200:270, 300:460] = (40, 40, 40)
    frames.append(pair)
    remaining = max(0, count - len(frames))
    for _ in range(remaining):
        frames.append(rng.integers(0, 256, size=(height, width, 3), dtype=np.uint8))
    return frames[:count]


def _kwargs() -> dict[str, float | int]:
    return {
        "conf": min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        "iou": YOLO_IOU,
        "max_det": MAX_BOTTLES * 2,
        "imgsz": YOLO_IMGSZ,
    }


def _diagnostic_kwargs(diagnostic_conf: float) -> dict[str, float | int]:
    kwargs = dict(_kwargs())
    kwargs["conf"] = diagnostic_conf
    return kwargs


def _count_kept(detections, names) -> tuple[int, int]:
    bottles = 0
    shakers = 0
    for item in detections:
        if (
            production_keep_drop(
                item,
                names=names,
                bottle_conf=YOLO_BOTTLE_CONFIDENCE,
                shaker_conf=YOLO_SHAKER_CONFIDENCE,
            )
            != "PASS"
        ):
            continue
        if semantic_class_for(item.class_id, names) == "shaker":
            shakers += 1
        else:
            bottles += 1
    return bottles, shakers


def _print_detection_block(runtime: str, detections, names) -> None:
    ordered = sorted(detections, key=lambda item: float(item.confidence), reverse=True)
    if not ordered:
        print(f"runtime={runtime} (no detections)")
        return
    for item in ordered:
        print(format_raw_detection_line(runtime, item, names=names))


def _print_keep_drop_block(runtime: str, detections, names) -> None:
    ordered = sorted(detections, key=lambda item: float(item.confidence), reverse=True)
    if not ordered:
        print(f"runtime={runtime} (no detections)")
        return
    for item in ordered:
        print(
            format_production_decision_line(
                runtime,
                item,
                names=names,
                bottle_conf=YOLO_BOTTLE_CONFIDENCE,
                shaker_conf=YOLO_SHAKER_CONFIDENCE,
            )
        )


def _format_shaker_box(detection) -> str:
    if detection is None:
        return "none"
    return (
        f"confidence={detection.confidence:.4f} "
        f"xyxy=({detection.x1:.1f}, {detection.y1:.1f}, "
        f"{detection.x2:.1f}, {detection.y2:.1f})"
    )


def _run_diagnose(
    image_path: Path,
    pytorch: PyTorchPropBackend,
    onnx: OnnxPropBackend,
    *,
    diagnostic_conf: float,
) -> int:
    if diagnostic_conf <= 0:
        print("diagnostic confidence must be > 0")
        return 2
    try:
        frame = _load_bgr_image(image_path)
    except FileNotFoundError as exc:
        print(exc)
        return 2

    names = pytorch.names
    print(
        f"DIAGNOSTIC ONLY: image={image_path} "
        f"inference_conf={diagnostic_conf:.2f} "
        f"production bottle_conf={YOLO_BOTTLE_CONFIDENCE:.2f} "
        f"shaker_conf={YOLO_SHAKER_CONFIDENCE:.2f} "
        f"iou={YOLO_IOU} max_det={MAX_BOTTLES * 2} imgsz={YOLO_IMGSZ}"
    )
    print("This path does not change YOLO_RUNTIME, production thresholds, or the parity gate.")
    if pytorch.names != onnx.names:
        print("FAIL: class mapping differs")
        return 1

    production_kwargs = _kwargs()
    diagnostic_kwargs = _diagnostic_kwargs(diagnostic_conf)
    prenms_kwargs = dict(diagnostic_kwargs)
    prenms_kwargs["iou"] = 1.0
    prenms_kwargs["max_det"] = 300

    pytorch_raw = pytorch.infer(frame, **diagnostic_kwargs)
    onnx_raw = onnx.infer(frame, **diagnostic_kwargs)
    pytorch_prenms = pytorch.infer(frame, **prenms_kwargs)
    onnx_prenms = onnx.infer(frame, **prenms_kwargs)
    pytorch_prod = pytorch.infer(frame, **production_kwargs)
    onnx_prod = onnx.infer(frame, **production_kwargs)

    pt_bottles, pt_shakers = _count_kept(pytorch_prod, names)
    onnx_bottles, onnx_shakers = _count_kept(onnx_prod, names)
    print(
        "Production-conf kept counts "
        f"(inference conf={production_kwargs['conf']:.2f}): "
        f"pytorch bottle={pt_bottles} shaker={pt_shakers} | "
        f"onnx bottle={onnx_bottles} shaker={onnx_shakers}"
    )

    print("")
    print(
        f"=== RAW DETECTIONS (inference conf={diagnostic_conf:.2f}, "
        "before ELIXR 0.40 keep/drop) ==="
    )
    _print_detection_block("pytorch", pytorch_raw, names)
    _print_detection_block("onnx", onnx_raw, names)

    print("")
    print(
        "=== PRODUCTION KEEP/DROP "
        f"(flair_bottle>={YOLO_BOTTLE_CONFIDENCE:.2f}, "
        f"shaker_bottle>={YOLO_SHAKER_CONFIDENCE:.2f}) ==="
    )
    _print_keep_drop_block("pytorch", pytorch_raw, names)
    _print_keep_drop_block("onnx", onnx_raw, names)

    print("")
    print(
        f"=== PRE-NMS CANDIDATES (inference conf={diagnostic_conf:.2f}, "
        "iou=1.0, max_det=300) ==="
    )
    _print_detection_block("pytorch", pytorch_prenms, names)
    _print_detection_block("onnx", onnx_prenms, names)

    diagnosis = classify_shaker_parity_diagnosis(
        pytorch_raw,
        onnx_raw,
        names=names,
        bottle_conf=YOLO_BOTTLE_CONFIDENCE,
        shaker_conf=YOLO_SHAKER_CONFIDENCE,
        onnx_without_nms=onnx_prenms,
    )
    iou_text = "none" if diagnosis.shaker_iou is None else f"{diagnosis.shaker_iou:.4f}"
    print("")
    print("=== SHAKER MATCH ===")
    print(f"pytorch_shaker {_format_shaker_box(diagnosis.pytorch_shaker)}")
    print(f"onnx_shaker {_format_shaker_box(diagnosis.onnx_shaker)}")
    print(f"shaker_box_iou={iou_text}")
    print("")
    print(f"DIAGNOSIS={diagnosis.label}")
    print(diagnosis.detail)
    return 0


def _load_backends(
    onnx_path: Path | None = None,
) -> tuple[PyTorchPropBackend, OnnxPropBackend]:
    onnx_model = Path(onnx_path) if onnx_path is not None else YOLO_ONNX_MODEL_PATH
    if not YOLO_MODEL_PATH.is_file():
        raise FileNotFoundError(f"Missing PyTorch model: {YOLO_MODEL_PATH}")
    if not onnx_model.is_file():
        raise FileNotFoundError(f"Missing ONNX model: {onnx_model}")

    inference_conf = min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE)
    pytorch = PyTorchPropBackend(
        YOLO_MODEL_PATH,
        inference_conf=inference_conf,
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
        imgsz=YOLO_IMGSZ,
    )
    onnx = OnnxPropBackend(
        onnx_model,
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        imgsz=YOLO_IMGSZ,
        intra_op_threads=YOLO_ONNX_INTRA_OP_THREADS,
        inference_conf=inference_conf,
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
    )
    pytorch.load()
    onnx.load()
    return pytorch, onnx


def _load_bgr_image(path: Path) -> np.ndarray:
    frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if frame is None:
        raise FileNotFoundError(f"Failed to read image: {path}")
    return frame


def _compare_pair(left, right, names):
    return compare_raw_detections(
        left,
        right,
        bottle_conf=YOLO_BOTTLE_CONFIDENCE,
        shaker_conf=YOLO_SHAKER_CONFIDENCE,
        names=names,
    )


def _run_image_directory(
    images_dir: Path,
    pytorch: PyTorchPropBackend,
    onnx: OnnxPropBackend,
) -> int:
    try:
        paths = discover_parity_images(images_dir)
    except FileNotFoundError as exc:
        print(exc)
        return 2

    kwargs = _kwargs()
    names = pytorch.names
    onnx_name = Path(getattr(onnx, "model_path", Path("onnx"))).name
    onnx_hw = (
        f"{getattr(onnx, 'input_height', '?')}x{getattr(onnx, 'input_width', '?')}"
    )
    print(
        f"Parity images: dir={images_dir} count={len(paths)} "
        f"pytorch names={pytorch.names} onnx names={onnx.names} "
        f"imgsz={YOLO_IMGSZ} bottle_conf={YOLO_BOTTLE_CONFIDENCE} "
        f"shaker_conf={YOLO_SHAKER_CONFIDENCE} iou={YOLO_IOU} "
        f"onnx={onnx_name} onnx_input={onnx_hw}"
    )
    if pytorch.names != onnx.names:
        print("FAIL: class mapping differs")
        return 1

    rows = []
    for path in paths:
        frame = _load_bgr_image(path)
        left = pytorch.infer(frame, **kwargs)
        right = onnx.infer(frame, **kwargs)
        report = _compare_pair(left, right, names)
        rows.append((path.name, report))
        if report.status == STATUS_SEMANTIC_MISMATCH or not report.passed:
            print(
                f"FAIL image={path.name} bottles={report.bottle_count_left}/"
                f"{report.bottle_count_right} shakers={report.shaker_count_left}/"
                f"{report.shaker_count_right} {summarize_parity(report)}"
            )

    summary = aggregate_directory_parity(rows)
    print(summarize_directory_parity(summary))
    if summary.status == STATUS_SEMANTIC_MISMATCH:
        print("FAIL: real-image semantic parity mismatch")
        return 1
    if summary.status == STATUS_INSUFFICIENT_COVERAGE:
        print(
            "INSUFFICIENT_COVERAGE: need at least one accepted flair_bottle "
            "and one accepted shaker_bottle detection"
        )
        return 3
    print("PASS")
    return 0


def _run_synthetic(
    frame_count: int,
    pytorch: PyTorchPropBackend,
    onnx: OnnxPropBackend,
) -> int:
    print(
        f"Parity synthetic: pytorch names={pytorch.names} onnx names={onnx.names} "
        f"imgsz={YOLO_IMGSZ}"
    )
    print(
        "NOTE: synthetic frames are a smoke check, not the production "
        "real-image parity gate."
    )
    if pytorch.names != onnx.names:
        print("FAIL: class mapping differs")
        return 1

    from ultralytics.data.augment import LetterBox
    import torch

    letterbox = LetterBox(
        (onnx.input_height, onnx.input_width),
        auto=False,
        stride=32,
    )
    pt_core = getattr(pytorch._model, "model", None)
    if pt_core is None:
        print("FAIL: PyTorch model core is unavailable for logit comparison")
        return 1
    pt_core.eval()

    frames = representative_frames(frame_count)
    kwargs = _kwargs()
    names = pytorch.names
    reports = []
    total_left = 0
    total_right = 0
    max_logit_delta = 0.0
    for index, frame in enumerate(frames):
        img = letterbox(image=frame)
        blob = np.ascontiguousarray(
            img[:, :, ::-1].transpose(2, 0, 1),
            dtype=np.float32,
        )[None, ...] / 255.0
        with torch.inference_mode():
            pt_out = pt_core(torch.from_numpy(blob))
            if isinstance(pt_out, (list, tuple)):
                pt_out = pt_out[0]
            pt_np = pt_out.detach().cpu().numpy()
        onnx_np = onnx._session.run(onnx._output_names, {onnx._input_name: blob})[0]
        max_logit_delta = max(
            max_logit_delta,
            float(np.max(np.abs(pt_np - onnx_np))),
        )
        left = pytorch.infer(frame, **kwargs)
        right = onnx.infer(frame, **kwargs)
        report = _compare_pair(left, right, names)
        reports.append(report)
        total_left += report.count_left
        total_right += report.count_right
        if report.status == STATUS_SEMANTIC_MISMATCH or not report.passed:
            print(
                f"FAIL frame={index} detections={report.count_left}/"
                f"{report.count_right} {summarize_parity(report)}"
            )

    failed = [report for report in reports if not report.passed]
    mean_iou = (
        float(np.mean([report.mean_iou for report in reports])) if reports else 1.0
    )
    max_conf = max((report.max_confidence_delta for report in reports), default=0.0)
    print(
        f"summary frames={len(reports)} failed={len(failed)} "
        f"detections={total_left}/{total_right} mean_iou={mean_iou:.4f} "
        f"max_conf_delta={max_conf:.4f} max_logit_abs_delta={max_logit_delta:.6f}"
    )
    if max_logit_delta > 0.05:
        print("FAIL: raw ONNX logits diverge from PyTorch")
        return 1
    if failed:
        print("FAIL: semantic or geometric parity mismatch")
        return 1
    if total_left == 0 and total_right == 0:
        print(
            "PASS (synthetic smoke only; zero detections are not production evidence)"
        )
        return 0
    print("PASS (synthetic smoke only)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument(
        "--images",
        type=Path,
        default=None,
        help="Directory of real .jpg/.jpeg/.png images (production parity gate).",
    )
    parser.add_argument(
        "--diagnose",
        type=Path,
        default=None,
        help=(
            "Diagnostic-only: run one image at a lowered inference confidence. "
            "Does not change production thresholds or the --images parity gate."
        ),
    )
    parser.add_argument(
        "--diagnostic-conf",
        type=float,
        default=0.10,
        help="Inference confidence used only by --diagnose (default 0.10).",
    )
    parser.add_argument(
        "--onnx",
        type=Path,
        default=None,
        help="ONNX artifact to compare (default backend/models/best.onnx).",
    )
    args = parser.parse_args(argv)

    try:
        pytorch, onnx = _load_backends(args.onnx)
    except FileNotFoundError as exc:
        print(exc)
        return 2

    if args.diagnose is not None:
        return _run_diagnose(
            args.diagnose,
            pytorch,
            onnx,
            diagnostic_conf=args.diagnostic_conf,
        )
    if args.images is not None:
        return _run_image_directory(args.images, pytorch, onnx)
    return _run_synthetic(args.frames, pytorch, onnx)


if __name__ == "__main__":
    raise SystemExit(main())
