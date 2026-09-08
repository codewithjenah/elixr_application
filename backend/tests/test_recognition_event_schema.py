from schemas.recognition import RecognitionEventMessage


def test_recognition_event_strips_locked_identity():
    message = RecognitionEventMessage(
        session_id="s1",
        event_id="s1:1",
        kind="advanced_technique",
        display_label="Bartender's Grip",
        identity_revealed=False,
        movement="Bartender's Grip",
        quality="great",
        prop_type="bottle",
    )
    dumped = message.model_dump()
    assert dumped["movement"] is None
    assert dumped["display_label"] == "Advanced technique detected"
    assert dumped["identity_revealed"] is False


def test_flip_event_has_no_catalog_movement_name():
    message = RecognitionEventMessage(
        session_id="s1",
        event_id="s1:2",
        kind="flip",
        display_label="Flip",
        identity_revealed=True,
        movement="Basic Toss",
        quality="perfect",
        prop_type="shaker",
    )
    assert message.movement is None
    assert message.display_label == "Flip"
