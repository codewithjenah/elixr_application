# ELIXR Repository Instructions

## Mission

ELIXR is a Windows-first Flutter desktop application for bottle-flair training. The Flutter client handles presentation, authentication, persistence, and session UX. A local FastAPI backend owns the webcam and performs computer-vision inference and rule-based movement assessment.

Work as a careful senior engineer. AI assistance may accelerate implementation, but it does not lower the standard of evidence required for correctness.

## Source of truth

Use this priority order:

1. The user's explicit task and acceptance criteria.
2. The nearest applicable `AGENTS.md` and Cursor project rule.
3. Executable code, schemas, tests, configuration, and platform behavior.
4. The root `README.md`.
5. Comments and historical notes.

Do not infer current requirements from deleted, stale, or aspirational planning documents. When documentation conflicts with implementation, investigate the code and update the documentation in the same change when appropriate.

## System boundaries

### Flutter client

- `lib/features/`: feature UI and screen-level interaction.
- `lib/services/`: app state and runtime orchestration using `ChangeNotifier` or focused service objects.
- `lib/data/repositories/`: persistence and authentication access.
- `lib/data/database/firestore_helper.dart`: Firestore adapter and document mapping.
- `lib/data/models/`: Dart data and transport models.
- `lib/core/`: shared routing, theme, constants, transitions, and reusable widgets.

### Python backend

- `backend/api/`: FastAPI routes and WebSocket orchestration.
- `backend/vision/`: camera ownership, detectors, landmark extraction, types, and frame annotation.
- `backend/assessment/rules/`: movement-specific evaluation.
- `backend/assessment/rule_engine.py`: movement registry and dispatch.
- `backend/assessment/scoring.py`: rolling bounded score.
- `backend/schemas/`: outbound API/WebSocket contracts.

### External services

- Firebase Authentication owns user identity.
- Cloud Firestore stores user profiles, sessions, and feedback.
- The FastAPI WebSocket is local runtime communication, not persistent storage.

## Non-negotiable invariants

1. **Python owns the camera.** Do not add direct Flutter camera capture or a second webcam owner.
2. **Keep the WebSocket contract synchronized.** A field change must update every producer, parser, test, and relevant documentation.
3. **Do not block the asyncio event loop with CV inference.** Preserve the `asyncio.to_thread` or an equivalent bounded worker strategy.
4. **Release resources deterministically.** Cameras, model wrappers, MediaPipe detectors, WebSockets, stream subscriptions, timers, animation controllers, scroll controllers, and audio players must have clear cleanup paths.
5. **Do not weaken authentication or Firestore authorization.** UI checks are not security controls; Firestore rules remain authoritative.
6. **Do not silently change persisted field names.** Firestore documents use snake_case fields and require compatibility consideration.
7. **Scoring stays bounded from 0 to 100.** Changes to weights, windows, or feedback classification require tests.
8. **Movement names are cross-layer identifiers.** Keep Flutter's catalog, Python `MOVEMENT_CONFIG`, and rule registry aligned.
9. **Do not commit secrets.** Never add service-account keys, tokens, passwords, personal Firebase credentials, or local environment files.
10. **Do not claim verification that was not performed.** Separate passed checks from unverified behavior.

## Controlled development protocol

### Before editing

For a non-trivial task:

1. Read the relevant files and their callers/callees.
2. Trace the runtime path across UI, service, repository, schema, backend, and storage as applicable.
3. State the current behavior, desired behavior, constraints, and acceptance criteria.
4. Identify contract participants and cleanup/error paths.
5. Choose the smallest coherent implementation plan.

Do not ask for permission merely because a correct change touches more than three files. Cross-layer contracts often require coordinated edits. Instead, avoid unrelated files and explain why each changed file is necessary.

### During implementation

- Prefer a small vertical slice that can be verified end to end.
- Follow an existing nearby pattern before introducing an abstraction.
- Do not perform opportunistic refactors, broad renames, dependency upgrades, or full-file formatting unless the task requires them.
- Do not add a dependency when the standard library or an existing dependency is sufficient.
- Keep public behavior backward compatible unless the task explicitly changes the contract.
- Preserve meaningful comments about Windows lifecycle, camera ownership, concurrency, and cross-language contracts.
- Convert repeated agent corrections into tests, static checks, scripts, or durable rules rather than longer prompts.

### Debugging

Use evidence-driven debugging:

1. Reproduce the failure.
2. List plausible hypotheses.
3. Identify evidence that distinguishes them.
4. Instrument the narrowest relevant path.
5. Find the root cause.
6. Apply the smallest targeted fix.
7. Add a regression test where practical.
8. Remove temporary instrumentation.

Do not mask symptoms with broad catches, arbitrary delays, forced rebuilds, or state resets unless the root cause supports that solution.

### Before finishing

Review the diff as untrusted code. Check for:

- Unrelated changes.
- Broken cross-language or Firestore contracts.
- Missing cleanup after async gaps or navigation.
- Authentication and authorization regressions.
- Tests that prove implementation details but not behavior.
- Swallowed exceptions or misleading fallbacks.
- New race conditions around camera/session teardown.
- Performance regressions in the frame loop.
- Hard-coded paths or configuration claims that do not match code.

Then run the smallest relevant verification set plus broader checks proportional to risk.

## Verification commands

### Flutter

From the repository root:

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

For startup, platform-channel, asset, dependency, or Windows lifecycle changes:

```powershell
flutter build windows
```

### Python backend

From the repository root:

```powershell
backend\.venv\Scripts\python.exe -m pytest -q backend\tests
backend\.venv\Scripts\python.exe -m compileall backend\api backend\assessment backend\schemas backend\vision backend\main.py backend\config.py
```

Run the backend from `backend/` when manually verifying model and camera paths:

```powershell
cd backend
.\run.ps1
```

### Firebase

For Firestore schema, query, rule, or index changes:

- Review `firestore.rules`.
- Review `firestore.indexes.json`.
- Verify repository queries and model mappings.
- Use emulator or test-project validation when available.
- Deploy only after human review:

```powershell
firebase deploy --only firestore
```

Do not deploy, publish, or modify production data unless the user explicitly requests it.

## Test strategy

- Assessment rules: synthetic `BottleDetection`, hand landmarks, pose landmarks, and movement state.
- Scoring: positive/warning/error windows, lower/upper bounds, reset behavior.
- WebSocket schema: required fields, defaults, malformed payload behavior, fatal error codes.
- Flutter services/models: parsing, state transitions, deduplication, cleanup, and error handling.
- Firestore: mapping compatibility, null timestamps, user ownership, query/index alignment.
- UI: loading, empty, error, disconnected, active-session, and disposal/navigation states.
- Camera/model: manual integration checks unless a deterministic test double is available.

Never make unit tests depend on a physical webcam, Firebase production data, or downloading a model.

## Completion report

Finish each substantial task with:

1. Behavior implemented or fixed.
2. Files changed and why.
3. Commands actually executed and their results.
4. Manual checks performed.
5. Assumptions made.
6. Known limitations or risks.
7. Anything requested but not completed.
8. Explicit `Not verified` items.

“Done” without evidence is not a completion report.
