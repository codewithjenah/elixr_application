"""Phase C cross-layer consistency gate for enabled scored-practice movements.

Authority: Flutter ``movementCatalog`` (enabled:true) is the product source of
truth. The shared manifest at ``test/fixtures/enabled_scored_movements.json``
must match that catalog and is verified here against backend rule mappings and
positive success codes. Free Practice and legacy aliases are intentionally
excluded from the enabled set.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from assessment.feedback_codes import FeedbackCategory, category_for, is_registered
from assessment.rule_engine import _RULES, evaluate_movement
from config import MOVEMENT_CONFIG

_REPO_ROOT = Path(__file__).resolve().parents[2]
_MANIFEST_PATH = _REPO_ROOT / "test" / "fixtures" / "enabled_scored_movements.json"

# Catalog movements that are scored via special-case dispatch (not in _RULES).
_SPECIAL_CASE_MOVEMENTS = {"Bottle in a tin", "Double Hand Stall"}

# Legacy aliases retained for historical sessions — not part of the enabled set.
_LEGACY_ALIASES = {"Arm Stall", "Upper Forearm Stall"}


def _load_manifest() -> dict:
    assert _MANIFEST_PATH.is_file(), f"missing shared manifest: {_MANIFEST_PATH}"
    return json.loads(_MANIFEST_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def manifest() -> dict:
    return _load_manifest()


@pytest.fixture(scope="module")
def enabled_names(manifest: dict) -> list[str]:
    return [entry["name"] for entry in manifest["movements"]]


def test_manifest_authority_documented(manifest: dict):
    assert isinstance(manifest.get("authority"), str)
    assert "movementCatalog" in manifest["authority"]


def test_every_manifest_movement_is_in_movement_config(enabled_names: list[str]):
    for name in enabled_names:
        assert name in MOVEMENT_CONFIG, name
        assert not MOVEMENT_CONFIG[name].get("internal", False), name
        assert not MOVEMENT_CONFIG[name].get("prop_detection_only", False), name


def test_every_manifest_movement_has_rule_dispatch(enabled_names: list[str]):
    for name in enabled_names:
        if name in _SPECIAL_CASE_MOVEMENTS:
            continue
        assert name in _RULES, f"missing rule mapping for {name}"


def test_special_case_movements_are_dispatchable(enabled_names: list[str]):
    for name in _SPECIAL_CASE_MOVEMENTS:
        assert name in enabled_names
        # Smoke: evaluate without detections still returns a coded RuleResult.
        result, _, _ = evaluate_movement(name, None, None, None, None)
        assert result.feedback_code
        assert is_registered(result.feedback_code)


def test_manifest_positive_codes_are_registered(manifest: dict):
    seen: set[str] = set()
    for entry in manifest["movements"]:
        code = entry["positive_code"]
        assert code, entry["name"]
        assert is_registered(code), code
        assert category_for(code) == FeedbackCategory.TECHNIQUE
        assert code not in seen, f"duplicate positive code {code}"
        seen.add(code)


def test_manifest_rule_modules_exist(manifest: dict):
    rules_dir = _REPO_ROOT / "backend" / "assessment" / "rules"
    for entry in manifest["movements"]:
        module = entry["rule_module"]
        path = rules_dir / module
        assert path.is_file(), f"missing rule module {module} for {entry['name']}"


def test_no_enabled_catalog_movement_missing_from_manifest(enabled_names: list[str]):
    # Backend cannot import Dart; this asserts the shared manifest names are a
    # closed set that every backend consumer must honor. Flutter tests prove
    # equality against movementCatalog.
    assert len(enabled_names) == 12
    assert "Free Practice" not in enabled_names
    for alias in _LEGACY_ALIASES:
        assert alias not in enabled_names


def test_legacy_aliases_remain_mapped_but_excluded_from_enabled_set():
    for alias in _LEGACY_ALIASES:
        assert alias in _RULES
        assert alias in MOVEMENT_CONFIG
