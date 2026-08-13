# Elixr Teacher

Standalone Teacher companion app for the **elixr-app-2026** Firebase project.

This Android Flutter client sits alongside the Windows trainee app in the same repository. It has **no dependency on the Python computer-vision backend**.

Firebase packages are declared as dependencies, but the app does not call `Firebase.initializeApp()` yet. `firebase_options.dart` will be generated separately with the FlutterFire CLI.
