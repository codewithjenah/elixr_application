"""Export backend/models/best.pt to a static FP32 ONNX artifact.

ELIXR production camera frames are 640x480 (W x H). The production ONNX
contract is therefore a static rectangular input:

    [1, 3, 480, 640]

Do not export a square 640x640 graph for production. That letterboxes 80 px
of padding onto 480x640 frames and breaks PyTorch parity.

Run from backend/:
    python scripts/export_prop_onnx.py
    python scripts/export_prop_onnx.py --onnx models/best_480x640_candidate.onnx
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import FRAME_HEIGHT, FRAME_WIDTH, YOLO_MODEL_PATH, YOLO_ONNX_MODEL_PATH


EXPORT_OPSET = 17
EXPORT_BATCH = 1
# Ultralytics imgsz is (height, width). Matches FRAME_HEIGHT x FRAME_WIDTH.
EXPORT_IMGSZ = (FRAME_HEIGHT, FRAME_WIDTH)


def export_onnx(
    *,
    pt_path: Path = YOLO_MODEL_PATH,
    onnx_path: Path = YOLO_ONNX_MODEL_PATH,
    imgsz: int | tuple[int, int] = EXPORT_IMGSZ,
    opset: int = EXPORT_OPSET,
) -> Path:
    from ultralytics import YOLO

    if not pt_path.is_file():
        raise FileNotFoundError(f"PyTorch weights are missing: {pt_path}")

    pt_path = pt_path.resolve()
    onnx_path = onnx_path.resolve()
    onnx_path.parent.mkdir(parents=True, exist_ok=True)

    # Ultralytics writes {pt_stem}.onnx next to the .pt file. Exporting from a
    # temp copy keeps backend/models/best.onnx intact when targeting a
    # candidate filename.
    with tempfile.TemporaryDirectory(prefix="elixr_onnx_export_") as tmp:
        tmp_pt = Path(tmp) / f"{onnx_path.stem}.pt"
        shutil.copy2(pt_path, tmp_pt)
        model = YOLO(str(tmp_pt))
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
        ).resolve()
        if onnx_path.exists():
            onnx_path.unlink()
        shutil.copy2(exported, onnx_path)
    return onnx_path


def _parse_imgsz(values: list[int]) -> int | tuple[int, int]:
    if len(values) == 1:
        return values[0]
    if len(values) == 2:
        return (values[0], values[1])
    raise argparse.ArgumentTypeError(
        "imgsz must be one integer or HEIGHT WIDTH (example: 480 640)"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pt", type=Path, default=YOLO_MODEL_PATH)
    parser.add_argument("--onnx", type=Path, default=YOLO_ONNX_MODEL_PATH)
    parser.add_argument(
        "--imgsz",
        type=int,
        nargs="+",
        default=list(EXPORT_IMGSZ),
        help="Export size: HEIGHT [WIDTH]. Default 480 640 for ELIXR cameras.",
    )
    parser.add_argument("--opset", type=int, default=EXPORT_OPSET)
    args = parser.parse_args()
    imgsz = _parse_imgsz(args.imgsz)
    path = export_onnx(
        pt_path=args.pt,
        onnx_path=args.onnx,
        imgsz=imgsz,
        opset=args.opset,
    )
    print(
        "Exported ONNX: "
        f"path={path} imgsz={imgsz} batch={EXPORT_BATCH} "
        f"dynamic=False opset={args.opset} dtype=fp32 nms=False "
        f"imgsz_hw={imgsz if isinstance(imgsz, tuple) else (imgsz, imgsz)}"
    )


if __name__ == "__main__":
    main()
