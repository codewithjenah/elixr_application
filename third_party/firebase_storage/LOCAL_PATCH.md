# Local Windows patch

This is the runtime source for `firebase_storage` 13.4.3 with two local Windows
changes in `windows/firebase_storage_plugin.cpp` and
`lib/src/firebase_storage.dart`. Firebase Storage calls its task listeners
from worker threads; those listeners now queue event-sink messages onto the
Windows platform thread and ignore events after stream cancellation. The Dart
wrapper also no longer blocks `useStorageEmulator` on Windows; the Windows
plugin delegates that call to the Firebase C++ Storage SDK.

The upstream Storage task-stream changes in 11.7.6 are already present in this
package, but the current upstream Windows implementation still calls the event
sink directly from Storage callbacks. Keep this override until an upstream
release provides platform-thread dispatch for task events. Compare the Windows
plugin source and remove the override when that fix is available.

The package's upstream `LICENSE`, `README.md`, and `CHANGELOG.md` are preserved.
The test and example directories are omitted from this runtime fork.
