"""Train and export a candidate two-keypoint bottle pose model.

Requires a real, locally annotated YOLO pose dataset and a local pose
checkpoint. This script never marks a candidate as validated for live use.

From backend/:
  python scripts/train_bottle_orientation.py --data PATH/dataset.yaml \
      --pretrained PATH/yolo-pose.pt --project PATH/runs
"""

from __future__ import annotations

import argparse
from pathlib import Path


def validate_data_config(path: Path) -> None:
    import yaml

    if not path.is_file():
        raise FileNotFoundError(path)
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict) or raw.get("kpt_shape") != [2, 3]:
        raise ValueError("Dataset must declare kpt_shape: [2, 3]")
    names = raw.get("names")
    if names not in ({0: "bottle"}, {"0": "bottle"}, ["bottle"]):
        raise ValueError("Dataset must contain one bottle class")
    kpt_names = raw.get("kpt_names")
    if kpt_names not in ({0: ["top", "base"]}, {"0": ["top", "base"]}):
        raise ValueError("Dataset keypoints must be ordered top, base")
    if not raw.get("train") or not raw.get("val"):
        raise ValueError("Dataset requires train and val splits")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--pretrained", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--epochs", type=int, default=100)
    args = parser.parse_args()
    validate_data_config(args.data)
    if not args.pretrained.is_file():
        raise FileNotFoundError(args.pretrained)
    if args.epochs < 1:
        raise ValueError("epochs must be positive")
    from ultralytics import YOLO

    model = YOLO(str(args.pretrained))
    if model.task != "pose":
        raise ValueError("pretrained checkpoint must be a pose model")
    model.train(
        data=str(args.data.resolve()),
        epochs=args.epochs,
        imgsz=640,
        project=str(args.project.resolve()),
        name="bottle_orientation",
    )
    best = args.project.resolve() / "bottle_orientation" / "weights" / "best.pt"
    trained = YOLO(str(best))
    trained.val(data=str(args.data.resolve()))
    exported = trained.export(
        format="onnx", imgsz=(480, 640), batch=1, dynamic=False,
        simplify=True, opset=17, half=False, nms=False, device="cpu",
    )
    print(f"Candidate ONNX: {exported}")
    print("Validate recorded static/toss/one-turn/multi-turn/opposite-direction clips and live FPS before promotion.")


if __name__ == "__main__":
    main()
