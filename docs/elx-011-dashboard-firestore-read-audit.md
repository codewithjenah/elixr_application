# ELX-011 trainee dashboard Firestore read audit

Measurement-first audit of trainee dashboard statistics/session loading as
practice history grows. Synthetic emulator users only (`elx011-synth-10`,
`elx011-synth-100`, `elx011-synth-1000`). No production PII, camera images, or
live trainee documents.

## Environment

| Item | Value |
| --- | --- |
| Captured | 2026-09-10 |
| Project | `demo-elixr-011` (Firebase demo/emulator project id) |
| Firestore | emulator `127.0.0.1:8080` |
| CLI | `firebase-tools@13.35.1` (`npx`; 15.x required JDK 21 on this machine) |
| JDK | OpenJDK 17.0.20 LTS |
| Rules | diagnostic-only open rules in `tool/dashboard_read_audit.rules` via `tool/firebase.dashboard-audit.json` |
| Auth | emulator Admin `Authorization: Bearer owner` |
| Cold/warm | Emulator JVM was already running. Sizes ran sequentially in one Dart test process (10, then 100, then 1000). No separate cold-start capture. |

Production `firestore.rules` were not used and were not deployed.

## How this was measured

Explicit harness, not production telemetry:

1. Start the emulator with the diagnostic config (do not deploy those rules).
2. `ELIXR_FIRESTORE_EMULATOR=1 flutter test test/diagnostics/dashboard_firestore_emulator_audit_test.dart`

The harness seeds synthetic sessions, then issues the **baseline** dashboard
query graph over the REST emulator API:

| Operation | Firestore call |
| --- | --- |
| `ProgressRepository.getStatsForUser.countSessionsForUser` | `runAggregationQuery` count where `user_id == uid` |
| `ProgressRepository.getStatsForUser.sessionAssessmentStatsForUser` | unbounded `runQuery` where `user_id == uid` (no order) |
| `ProgressRepository.getStatsForUser.sessionCountByMovement` | identical unbounded `runQuery` (second full get) |
| `ProgressRepository.getStatsForUser` | sum of the three rows above |
| `SessionRepository.getSessionsForUser` | unbounded `runQuery` where `user_id == uid` orderBy `created_at DESC` |
| `dashboard.dataLoad.total` | all four network calls |

`explainOptions.analyze: true` was requested. The emulator response did **not**
include `executionStats.readOperations` or index-entry debug stats, so those
columns are `n/a` (not fabricated).

**Payload bytes** are the UTF-8 length of the REST JSON response body (`payload source = network`).

**Estimated serialized bytes** are a deterministic JSON encoding of
client-mapped session maps (no images). Labeled `deterministic_serialized_estimate`
in the local plan; the emulator table still reports that estimate alongside the
measured network body.

## Baseline measurements (pre-change dashboard)

| dataset | operation | returned | billable reads | index entries scanned | payload bytes (network) | estimated serialized bytes | elapsed ms |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | `countSessionsForUser` | 1 | n/a | n/a | 117 | 12 | 27.5 |
| 10 | `sessionAssessmentStatsForUser` | 10 | n/a | n/a | 7,760 | 3,301 | 31.6 |
| 10 | `sessionCountByMovement` | 10 | n/a | n/a | 7,760 | 3,301 | 34.7 |
| 10 | `ProgressRepository.getStatsForUser` | 21 | n/a | n/a | 15,637 | 6,614 | 93.8 |
| 10 | `SessionRepository.getSessionsForUser` | 10 | n/a | n/a | 7,760 | 3,301 | 32.5 |
| 10 | `dashboard.dataLoad.total` | 31 | n/a | n/a | 23,397 | 9,915 | 126.3 |
| 100 | `countSessionsForUser` | 1 | n/a | n/a | 118 | 13 | 30.1 |
| 100 | `sessionAssessmentStatsForUser` | 100 | n/a | n/a | 78,677 | 33,783 | 87.3 |
| 100 | `sessionCountByMovement` | 100 | n/a | n/a | 78,677 | 33,783 | 80.5 |
| 100 | `ProgressRepository.getStatsForUser` | 201 | n/a | n/a | 157,472 | 67,579 | 197.9 |
| 100 | `SessionRepository.getSessionsForUser` | 100 | n/a | n/a | 78,677 | 33,783 | 75.6 |
| 100 | `dashboard.dataLoad.total` | 301 | n/a | n/a | 236,149 | 101,362 | 273.5 |
| 1000 | `countSessionsForUser` | 1 | n/a | n/a | 119 | 14 | 19.9 |
| 1000 | `sessionAssessmentStatsForUser` | 1000 | n/a | n/a | 789,873 | 340,938 | 166.0 |
| 1000 | `sessionCountByMovement` | 1000 | n/a | n/a | 789,873 | 340,938 | 130.6 |
| 1000 | `ProgressRepository.getStatsForUser` | 2001 | n/a | n/a | 1,579,865 | 681,890 | 316.6 |
| 1000 | `SessionRepository.getSessionsForUser` | 1000 | n/a | n/a | 789,873 | 340,938 | 126.2 |
| 1000 | `dashboard.dataLoad.total` | 3001 | n/a | n/a | 2,369,738 | 1,022,828 | 442.8 |

History-scaling operations (returned documents and network payload grow ~10× per 10× sessions): both unordered gets and the ordered history get. The count aggregation stays ~1 result and ~120 bytes.

## Redundant reads (evidence)

On one dashboard load the helper performed **three full session document gets** for the same `user_id`:

1. `sessionAssessmentStatsForUser` → `_sessionsForUser().get()` (unordered)
2. `sessionCountByMovement` → `_sessionsForUser().get()` (unordered, identical query)
3. `getSessionsForUser` → ordered `created_at DESC` get used for streak, week, best, recommendation

Plus `countSessionsForUser`, whose result equals the later list length on a consistent snapshot.

The dashboard UI then derived this-week / streak / weekly V2 comparison / best session / recommendation from `_sessions`, while totals / averages / most-practiced came from `getStatsForUser` over those duplicate scans.

## Data dependencies (why the history get was not bounded)

| Dashboard value | History needed |
| --- | --- |
| Sessions this week | Manila week window (recent) |
| Assessment V2 week-over-week | current 7 vs prior 7 Manila days; legacy % excluded |
| Current streak | enough history to reach the first missed Manila civil day (must not cap at 14) |
| Best session | all-time |
| Totals, V1/V2 averages, most-practiced | all-time |
| Training recommendation | all-time per movement (lifetime averages, last practiced, recent window of 5) |

Bounding or paginating the dashboard history list would change streak, best session, recommendation, or all-time totals. No summary collection was added.

## Conclusion

**Optimization was warranted.** At 1,000 sessions the baseline dashboard transferred 2,369,738 network bytes and returned 3,001 results because it fetched the history three times. The extra two unordered gets were redundant with the ordered list the dashboard already needed.

**Not warranted:** pagination, denormalized summary documents, Cloud Functions, or schema changes. Those would be needed only to avoid the remaining single unbounded get, which is still required for exact all-time semantics.

## What shipped

The trainee dashboard loads sessions **once** via `SessionRepository.getSessionsForUser`, then `ProgressStats.fromSessions` on that snapshot. Streak, week, V2 comparison, best session, and recommendation still use the full list.

Post-change dashboard cost matches the measured `SessionRepository.getSessionsForUser` row:

| dataset | returned | payload bytes (network) | estimated serialized bytes | elapsed ms |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 10 | 7,760 | 3,301 | 32.5 |
| 100 | 100 | 78,677 | 33,783 | 75.6 |
| 1000 | 1000 | 789,873 | 340,938 | 126.2 |

That is a 3× reduction in returned session documents and network body versus `dashboard.dataLoad.total` (count bytes are negligible). The Progress screen still uses `getStatsForUser` + `getSessionsForUser` and was left unchanged.

`getStatsForUser` remains the Progress-screen contract (count + two unordered scans). Dashboard no longer calls it.

Tie-only note: most-practiced uses the first maximum in snapshot order. The dashboard snapshot is `created_at DESC`. The Progress screen still uses the unordered helper get, so equal counts can pick different names there. Totals and V1/V2 partitions match on the same list.

## Inferred production billing (not measured)

Cloud Firestore Query Explain `readOperations` were **not** present on the emulator. Do not treat the following as measured billable reads:

- Each unbounded `get` of N session documents is expected to bill **N document reads** in production.
- Baseline dashboard: **3N document reads** plus **one count aggregation**.
- Current dashboard: **N document reads**.
- Index entries scanned: unknown on this emulator.

## Limitations

- Emulator timing is not production multi-region latency.
- REST JSON body size is larger than the Dart client’s mapped session list (see estimate column).
- Diagnostic rules are open; they are not production rules.
- Count aggregation billing vs document-read billing could not be confirmed via Explain.

## Re-run

```powershell
npx -y firebase-tools@13.35.1 emulators:start --only firestore --project demo-elixr-011 --config tool/firebase.dashboard-audit.json
$env:ELIXR_FIRESTORE_EMULATOR = '1'
flutter test test/diagnostics/dashboard_firestore_emulator_audit_test.dart
```

Local no-network plans (deterministic estimates, elapsed 0):

- `DashboardReadAuditHarness.measureLocalPlan()` — baseline four-call graph
- `DashboardReadAuditHarness.measureCurrentDashboardLocalPlan()` — one ordered get
