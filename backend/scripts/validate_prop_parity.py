"""Compare PyTorch best.pt vs ONNX best.onnx on the same frames.

Run from backend/:
    python scripts/validate_prop_parity.py
"""

from __future__ import annotations

import argparse
import sys
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
from vision.prop_inference import OnnxPropBackend, PyTorchPropBackend
from vision.prop_parity import compare_raw_detections, summarize_parity


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=8)
    args = parser.parse_args()

    if not YOLO_MODEL_PATH.is_file():
        print(f"Missing PyTorch model: {YOLO_MODEL_PATH}")
        return 2
    if not YOLO_ONNX_MODEL_PATH.is_file():
        print(f"Missing ONNX model: {YOLO_ONNX_MODEL_PATH}")
        return 2

    pytorch = PyTorchPropBackend(
        YOLO_MODEL_PATH,
        inference_conf=min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
        imgsz=YOLO_IMGSZ,
    )
    onnx = OnnxPropBackend(
        YOLO_ONNX_MODEL_PATH,
        runtime_name="onnx_cpu",
        providers=["CPUExecutionProvider"],
        imgsz=YOLO_IMGSZ,
        intra_op_threads=YOLO_ONNX_INTRA_OP_THREADS,
        inference_conf=min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
        iou=YOLO_IOU,
        max_det=MAX_BOTTLES * 2,
    )
    pytorch.load()
    onnx.load()
    print(
        f"Parity: pytorch names={pytorch.names} onnx names={onnx.names} "
        f"imgsz={YOLO_IMGSZ}"
    )
    if pytorch.names != onnx.names:
        print("FAIL: class mapping differs")
        return 1

    from ultralytics.data.augment import LetterBox
    import torch

    letterbox = LetterBox((YOLO_IMGSZ, YOLO_IMGSZ), auto=False, stride=32)
    pt_core = getattr(pytorch._model, "model", None)
    if pt_core is None:
        print("FAIL: PyTorch model core is unavailable for logit comparison")
        return 1
    pt_core.eval()

    frames = representative_frames(args.frames)
    kwargs = _kwargs()
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
        report = compare_raw_detections(
            left,
            right,
            bottle_conf=YOLO_BOTTLE_CONFIDENCE,
            shaker_conf=YOLO_SHAKER_CONFIDENCE,
        )
        reports.append(report)
        total_left += report.count_left
        total_right += report.count_right
        print(f"frame={index} detections={report.count_left}/{report.count_right} {summarize_parity(report)}")

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
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
