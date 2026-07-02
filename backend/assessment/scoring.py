from collections import deque

from config import SCORE_BASE, SCORE_ERROR, SCORE_POSITIVE, SCORE_WARNING, SCORE_WINDOW


class SessionScorer:
    def __init__(self, window: int = SCORE_WINDOW, base: int = SCORE_BASE):
        self._window = window
        self._base = base
        self._events: deque[int] = deque(maxlen=window)

    def record(self, feedback_type: str) -> None:
        if feedback_type == "positive":
            self._events.append(SCORE_POSITIVE)
        elif feedback_type == "warning":
            self._events.append(SCORE_WARNING)
        else:
            self._events.append(SCORE_ERROR)

    @property
    def score(self) -> int:
        if not self._events:
            return self._base
        total = self._base + sum(self._events)
        return max(0, min(100, total))

    def reset(self) -> None:
        self._events.clear()
