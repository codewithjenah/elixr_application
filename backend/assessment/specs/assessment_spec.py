"""Strict AssessmentSpec v1 for the Phase 7 Wrist Stall vertical slice.

Unknown fields are forbidden. This model never accepts teacher thresholds,
formulas, or executable expressions.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict


class AssessmentSpec(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: Literal[1]
    template_id: Literal["balance_stall.wrist_v1"]
    prop: Literal["bottle"]
    target: Literal["wrist"]
    laterality: Literal["either", "left", "right"]
