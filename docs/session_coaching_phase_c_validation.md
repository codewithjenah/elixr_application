# Session Coaching Phase C — Manual Camera Validation Matrix

**Automated tests do not replace physical camera validation.**

This checklist is for human validation on a Windows desktop with a real webcam, the local FastAPI backend, and the Flutter client. Do not mark any checkbox as passed from CI or unit tests alone.

**Authority for enabled movements:** Flutter `lib/core/constants/movements.dart` (`enabled: true`), mirrored by `test/fixtures/enabled_scored_movements.json`.

**Phase C automated coverage:** cross-layer consistency gate, rule-path coding, Flutter coaching aggregation/recommendation, summary layout widget tests, and legacy protocol parsing. Physical camera behavior remains **Not verified** until rows below are completed manually.

---

## Per-movement smoke checklist

For each enabled movement, complete one scored-practice session and check every row.

| Movement | Difficulty | Prop | Session starts | Prop selection | Technique failure | Positive success | Confirmed hold | Unconfirmed hold | Strength wording | Improvement wording | Same-movement recommendation | Numeric hold target | Buttons work | No overflow |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Normal Grip | Easy | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Bartender's Grip | Easy | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Reverse Grip | Easy | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Claw Grip | Easy | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Hand Stall | Medium | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| One Finger Stall | Medium | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Forearm Stall | Medium | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Elbow Stall | Medium | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Reverse Forearm Stall | Hard | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Shoulder Stall | Hard | Bottle | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Double Hand Stall | Hard | Two bottles | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Bottle in a tin | Hard | Bottle + Cocktail Shaker | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |

**How to interpret columns**

- **Technique failure:** trigger at least one expected technique warning (not only visibility/environment).
- **Positive success:** observe the movement’s locked-in positive feedback.
- **Confirmed / Unconfirmed hold:** one session that reaches `hold_confirmed`, and one that stops before confirmation.
- **Strength / Improvement wording:** sample-honest; no “N mistakes”; no “hold broke” claims.
- **Same-movement recommendation:** Recommended Next Session names the same movement only.
- **Numeric hold target:** recommendation target shows backend `hold_target_ms` seconds when available.
- **Buttons:** Save & Continue, Try Again, and Discard remain reachable and behave correctly.
- **No overflow:** summary sheet has no yellow/black Flutter overflow stripes at the tested window size.

---

## Deeper scenario matrix

| Scenario | Movement / setup | Pass |
| --- | --- | --- |
| One Easy movement (deeper) | e.g. Normal Grip — mixed technique warnings + confirmed hold | [ ] |
| One Medium movement (deeper) | e.g. Hand Stall — form + hold progression | [ ] |
| One Hard movement (deeper) | e.g. Shoulder Stall or Bottle in a tin | [ ] |
| Bottle-only movement | Normal Grip (or Claw / Reverse) | [ ] |
| Bottle + Cocktail Shaker movement | Bottle in a tin | [ ] |
| Hand Stall with Cocktail Shaker | Hand Stall prop = Cocktail Shaker; wording uses shaker, codes stay prop-neutral | [ ] |
| Double Hand Stall | Two bottles, both palms | [ ] |
| Confirmed session | Any enabled movement with sticky hold confirmation | [ ] |
| Unconfirmed session | Stop before confirmation; partial progress/duration wording if eligible | [ ] |
| Prop leaving the frame | Environment/visibility feedback; excluded from technique coaching | [ ] |
| Hand/body visibility interruption | Hands or pose leave frame mid-session | [ ] |
| 1366×768 display | Dense strengths + improvements + recommendation; actions pinned | [ ] |
| Narrow supported display | e.g. ~900×600; scrollable coaching body; actions reachable | [ ] |
| Save success | Save & Continue persists session; coaching remains in-memory only | [ ] |
| Save failure / retry | Force offline/unavailable; error shown; retry succeeds | [ ] |
| Try Again | Returns to practice without fabricating coaching | [ ] |
| Discard | Discards without save; no crash | [ ] |

---

## Notes for validators

1. Free Practice must remain unaffected (no scored coaching summary path).
2. Do not persist the full coaching summary in Phase C (tips/history stay as before).
3. If a movement cannot produce a technique failure under studio lighting, record that honestly in notes — do not skip the row silently.
4. Cursor / CI cannot complete this matrix. Leave all boxes unchecked until a human with a camera marks them.

**Status:** Prepared for manual camera testing. Physical-camera scenarios: **Not verified**.
