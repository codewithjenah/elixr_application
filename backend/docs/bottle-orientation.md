# Optional bottle orientation model

ELIXR's existing `best.pt`/`best.onnx` models detect bottle and shaker boxes. They do not observe orientation. Custom bottle rotation requires a separately trained YOLO pose model with **one bottle class** and **two directed keypoints in order: top/neck, base/bottom**. The detector associates its result with a current, confirmed bottle box; the keypoints alone do not replace prop tracking.

## Data and training

Use a real, consented, locally prepared YOLO pose dataset. Its YAML must declare `kpt_shape: [2, 3]`, `names: {0: bottle}`, `kpt_names: {0: [top, base]}`, and `train`/`val` splits. Each label row is `class cx cy width height top_x top_y top_visible base_x base_y base_visible`, with normalized coordinates. Annotate only visible, identifiable ends; mark an occluded end invisible. Include static bottles, translation-only tosses, clockwise/counter-clockwise turns, multiple turns, blur, partial occlusion, lighting and backgrounds. Keep performers/clips separated between training and validation.

With a locally obtained Ultralytics pose checkpoint and dataset, run from `backend/`:

```powershell
.\.venv\Scripts\python.exe scripts/train_bottle_orientation.py --data C:\path\dataset.yaml --pretrained C:\path\pose-checkpoint.pt --project C:\path\runs
```

The script trains, validates, and exports a **candidate** static FP32 ONNX at 480×640, batch 1, opset 17, with NMS outside the graph. It does not create model weights or claim live validation.

## Promotion gate

Test recorded and live clips for static bottle, plain toss, approximately one projected turn, multiple turns, and opposite direction. Measure the reported `orientation_inference_ms_mean`, effective processing FPS, angle coverage, and provider on the target Windows hardware. Require adjacent confident top/base observations fast enough that frame-to-frame turns stay below 0.85π; faster projected turns alias and must not be claimed as counted. A directed 2D axis cannot observe bottle roll about its own long axis, 3D depth, or turns during full occlusion.

Only after validating the model and live cadence, copy the candidate to `backend/models/bottle_orientation.onnx` and create `backend/models/bottle_orientation.validated.json`:

```json
{"validated": true, "task": "pose", "keypoints": ["top", "base"], "sha256": "<SHA-256 of the ONNX file>"}
```

The hash binds the validation decision to those exact weights. Keep the validation clips, metrics and model provenance with the release review. Without both matching files, reference capture remains translation/body/hand based and a rotation template cannot start assessment. The ordinary detection model and official movements remain unchanged.

Ultralytics `8.4.80` supports [pose dataset keypoint labels](https://docs.ultralytics.com/datasets/pose/) and [pose ONNX export](https://docs.ultralytics.com/tasks/pose/); the runtime decodes the no-NMS one-class/two-keypoint output with the installed Ultralytics NMS/coordinate helpers and uses ONNX Runtime DirectML when present, otherwise CPU. Test the actual ONNX metadata and provider on the deployment device.
