"""Tests for the designed (not yet wired) MediaPipe VIDEO timestamp clock."""

from vision.hands_timestamp import VideoTimestampClock


def test_first_frame_at_origin_is_zero():
    clock = VideoTimestampClock()
    assert clock.next_ms(1000.0) == 0
    assert clock.last_timestamp_ms == 0
    assert clock.origin_monotonic == 1000.0


def test_actual_frame_dt_is_preserved_in_milliseconds():
    clock = VideoTimestampClock()
    assert clock.next_ms(10.000) == 0
    assert clock.next_ms(10.090) == 90
    assert clock.next_ms(10.180) == 180


def test_rounding_collision_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(1.0)
    # 0.4 ms rounds to 0, then collides with the origin timestamp.
    second = clock.next_ms(1.0004)
    assert first == 0
    assert second == 1


def test_sub_millisecond_frames_do_not_collide():
    clock = VideoTimestampClock()
    first = clock.next_ms(5.0)
    second = clock.next_ms(5.0004)
    third = clock.next_ms(5.0004)
    assert first == 0
    assert second == 1
    assert third == 2
    assert second > first
    assert third > second


def test_duplicate_capture_timestamp_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(3.5)
    second = clock.next_ms(3.5)
    assert second == first + 1


def test_backward_monotonic_jump_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(20.0)
    second = clock.next_ms(19.5)
    assert second == first + 1


def test_reset_matches_detector_recreation():
    clock = VideoTimestampClock()
    clock.next_ms(1.0)
    clock.next_ms(1.2)
    clock.reset()
    assert clock.origin_monotonic is None
    assert clock.last_timestamp_ms is None
    assert clock.next_ms(50.0) == 0
