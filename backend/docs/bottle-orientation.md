# Marked bottle orientation for custom movements

The normal YOLO `best.pt`/`best.onnx` detector remains authoritative for bottle detection and track identity. During custom bottle recording and rotation assessment, a current confirmed bottle box authorizes a small ROI. OpenCV extracts **orange tape at the top/neck** and **yellow tape at the base/bottom** inside that ROI. Their centroids become directed `BottleOrientation` top and base points. The existing temporal rotation trace and scoring then consume that observation. Color alone never declares a bottle.

Both markers must be visible and unambiguous in the same frame. Missing, blurred, tiny, oversized, or ambiguous color components yield no orientation. Orange and yellow are semantic ends: inverted and horizontal bottles remain directed correctly. A separately trained orientation dataset and ONNX asset are **not required** for this marked-bottle path. Non-rotation custom movements can still record without the markers; requiring rotation needs three references with sufficient reliable rotation evidence.

Thresholds are centralized in `backend/config.py` and can be overridden with `MARKER_ORANGE_HUE`, `MARKER_YELLOW_HUE` (comma-separated OpenCV HSV hue endpoints, 0..179), `MARKER_MIN_SATURATION`, `MARKER_MIN_VALUE`, `MARKER_MIN_BLOB_AREA_RATIO`, `MARKER_MAX_BLOB_AREA_RATIO`, and `MARKER_MIN_SEPARATION_RATIO`. The hue ranges must remain disjoint. Tune them against the actual tape and deployment lighting; defaults are a starting point, not a claim of live validation.

The reported `orientation_provider` is `color_markers`; `orientation_inference_ms_mean`, orientation coverage, effective processing FPS and rotation trace coverage help diagnose live behavior. The camera observes only a projected 2D directed axis. Longitudinal roll, depth turns, and complete occlusion cannot be measured. Extremely fast projected turns can alias when adjacent observations exceed the existing angular step limit; the pipeline rejects those pairs rather than inventing turns.

## Optional future learned detector

`vision/bottle_orientation_detector.py` and `scripts/train_bottle_orientation.py` retain the separately validated two-keypoint YOLO pose implementation for future experiments. The current custom session uses the color marker detector. Adding a learned source to runtime later requires explicit source selection and validation; conflicting sources must not be averaged. The ordinary prop detector remains authoritative either way.
