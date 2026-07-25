# Flutter Client Instructions

These instructions apply to `lib/**` and supplement the repository root `AGENTS.md`.

## Current client stack

- Flutter Windows desktop.
- `fluent_ui` for visual components.
- `provider` and `ChangeNotifier` for shared state.
- `go_router` for navigation and auth redirects.
- Firebase Authentication and Cloud Firestore.
- `web_socket_channel` for the local vision backend.
- `audioplayers` for practice music.

Do not replace these technologies or introduce a second state-management, routing, camera, or persistence approach without a concrete requirement and migration plan.

## Architecture guidance

- Keep feature-specific presentation in `lib/features/<feature>/`.
- Put reusable visual primitives in `lib/core/widgets/` only after genuine reuse is established.
- Put app-wide runtime state and orchestration in focused services.
- Put Firebase and persistence operations behind repositories or the existing Firestore adapter.
- Keep data parsing and serialization in models or explicit adapters, not scattered through widgets.
- Existing screens sometimes instantiate repositories directly. Improve locally when it clarifies testability, but do not launch a repository-wide architecture rewrite during an unrelated task.

## UI and state

- Use Fluent UI components and the existing theme/constants before inventing new styling systems.
- Preserve loading, empty, disconnected, error, active-session, and completed-session states.
- Guard `setState` after async gaps with `mounted`.
- Capture router/services before long async teardown when widget deactivation is possible.
- Dispose every controller, timer, subscription, listener, service, animation, and audio resource the widget owns.
- Do not notify listeners after a service has begun disposal.
- Avoid expensive computation, repository calls, or JSON decoding in `build`.
- Keep layouts usable at the widths already handled by the application; do not optimize only for one monitor size.

## WebSocket client

The contract is shared with the Python backend.

When changing a message field or action:

1. Update `PracticeFeedback.fromJson` or the relevant Dart model.
2. Update `WebSocketService` send/receive behavior.
3. Update the Pydantic schema and backend producer.
4. Define defaults and malformed-message behavior.
5. Add or update tests where practical.
6. Document compatibility implications.

Do not silently ignore malformed frames without considering observability. The current client intentionally ignores malformed frames; any change should preserve app stability while making debugging possible when appropriate.

## Firebase and models

- Keep Firestore field names snake_case to match existing documents.
- Treat `FieldValue.serverTimestamp()` as eventually nullable on immediate reads.
- Preserve Firebase UID as the user document ID.
- Do not store raw passwords or authentication tokens.
- Do not make profile/session data globally readable in security rules.
- Coordinate model changes with repository mappings, Firestore rules, indexes, and existing documents.

## Camera and media

- Flutter displays backend-supplied JPEG bytes; it does not own the webcam.
- Do not add `camera`, DirectShow capture, or another camera process to Flutter.
- Preserve deterministic audio stop/dispose behavior, especially around Windows navigation and teardown.
- Do not persist frames unless the task explicitly introduces a reviewed privacy and storage design.

## Dart style

- Follow `flutter_lints` and existing naming conventions.
- Prefer immutable data and `const` constructors when practical.
- Use explicit, descriptive state names instead of generic flags.
- Keep methods focused; extract complex state transitions before extracting decorative widgets.
- Avoid force unwraps unless the invariant is immediately proven.
- Do not catch `Exception` or `_` merely to hide a bug; intentional best-effort behavior must be documented.

## Verification

At minimum for Dart changes:

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

Also run `flutter build windows` for changes involving startup, assets, packages, generated Firebase configuration, Windows lifecycle, or native integration.
