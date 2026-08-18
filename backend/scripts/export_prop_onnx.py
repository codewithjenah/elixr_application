"""Export backend/models/best.pt to a static FP32 ONNX artifact.

Run from backend/:
    python scripts/export_prop_onnx.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import YOLO_IMGSZ, YOLO_MODEL_PATH, YOLO_ONNX_MODEL_PATH


EXPORT_OPSET = 17
EXPORT_BATCH = 1


def export_onnx(
    *,
    pt_path: Path = YOLO_MODEL_PATH,
    onnx_path: Path = YOLO_ONNX_MODEL_PATH,
    imgsz: int = YOLO_IMGSZ,
    opset: int = EXPORT_OPSET,
) -> Path:
    from ultralytics import YOLO

    if not pt_path.is_file():
        raise FileNotFoundError(f"PyTorch weights are missing: {pt_path}")

    model = YOLO(str(pt_path))
    exported = Path(
        model.export(
            format="onnx",
            imgsz=imgsz,
            batch=EXPORT_BATCH,
            dynamic=False,
            simplify=True,
            opset=opset,
            half=False,
            nms=False,
            device="cpu",
        )
    )
    exported = exported.resolve()
    onnx_path = onnx_path.resolve()
    if exported != onnx_path:
        onnx_path.parent.mkdir(parents=True, exist_ok=True)
        if onnx_path.exists():
            onnx_path.unlink()
        exported.replace(onnx_path)
    return onnx_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pt", type=Path, default=YOLO_MODEL_PATH)
    parser.add_argument("--onnx", type=Path, default=YOLO_ONNX_MODEL_PATH)
    parser.add_argument("--imgsz", type=int, default=YOLO_IMGSZ)
    parser.add_argument("--opset", type=int, default=EXPORT_OPSET)
    args = parser.parse_args()
    path = export_onnx(
        pt_path=args.pt,
        onnx_path=args.onnx,
        imgsz=args.imgsz,
        opset=args.opset,
    )
    print(
        "Exported ONNX: "
        f"path={path} imgsz={args.imgsz} batch={EXPORT_BATCH} "
        f"dynamic=False opset={args.opset} dtype=fp32 nms=False"
    )


if __name__ == "__main__":
    main()
