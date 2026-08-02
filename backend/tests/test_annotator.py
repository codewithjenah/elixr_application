import cv2
import numpy as np
import pytest

from vision.annotator import CYAN, GREEN, YELLOW, annotate_frame
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection


def test_annotate_frame_keeps_geometry_without_rasterized_prop_label(monkeypatch):
    def fail_put_text(*args, **kwargs):
        pytest.fail("prop labels must not be rasterized into camera frames")

    monkeypatch.setattr(cv2, "putText", fail_put_text)

    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    prop = PropDetection(
        x1=20,
        y1=30,
        x2=40,
        y2=70,
        confidence=0.95,
    )
    hands = HandsResult(
        hands=[
            HandLandmarks(
                points={8: Point2D(0.8, 0.8)},
            )
        ]
    )
    pose = PoseLandmarks(
        points={
            11: Point2D(0.1, 0.1),
            12: Point2D(0.2, 0.1),
        },
        visibility={11: 1.0, 12: 1.0},
    )

    annotated = annotate_frame(
        frame,
        [prop],
        hands,
        "Good",
        "positive",
        "Hand Stall",
        80,
        pose=pose,
        prop_label="Cocktail Shaker",
    )

    assert np.array_equal(annotated[30, 20], np.array(GREEN, dtype=np.uint8))
    assert np.array_equal(annotated[50, 30], np.array(GREEN, dtype=np.uint8))
    assert np.array_equal(annotated[10, 15], np.array(CYAN, dtype=np.uint8))
    assert np.array_equal(annotated[80, 80], np.array(YELLOW, dtype=np.uint8))
