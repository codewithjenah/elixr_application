# Windows pilot build

ELIXR's pilot package is a per-user Windows 11 x64 installer. The installer
contains the complete Flutter release bundle and a console-free, one-folder
PyInstaller backend with the CV models and native runtime libraries. The
Flutter app-local Microsoft C/C++ runtime DLLs are included as well, so the
pilot machine does not need Visual Studio or a separate runtime installation.

## One-time developer prerequisites

- Flutter with Windows desktop support and the Visual Studio C++ desktop workload.
- Python 3.11 and a backend virtual environment at `backend\.venv`.
- Backend dependencies plus PyInstaller:

```powershell
backend\.venv\Scripts\python.exe -m pip install -r backend\requirements-dev.txt
backend\.venv\Scripts\python.exe -m pip install -r packaging\requirements-build.txt
```

- Inno Setup 6 installed separately so `ISCC.exe` is available on `PATH` (or
  in its normal installation directory). The build script does not download
  tools.

## Build

From the repository root on `main`:

```powershell
.\scripts\build_pilot.ps1
```

The reproducible output is:

```text
build\pilot\ELIXR_Setup.exe
```

The script derives the installer version from `pubspec.yaml`, builds
`flutter build windows --release`, freezes the backend, stages all Flutter
files and backend resources, validates required files, and invokes Inno Setup.
Generated staging, PyInstaller, and installer output stays under `build\pilot`
and is ignored by Git.

The backend freeze is pinned to PyInstaller 6.22.2. If the virtual environment
has another version, the build stops before changing the output.

## Pilot smoke test

On another Windows 11 x64 machine, run `ELIXR_Setup.exe`, launch ELIXR from the
Start menu or optional desktop shortcut, sign in, open camera settings, and
start a practice session. Confirm that no PowerShell, cmd, Python, or backend
console appears. Close and reopen ELIXR, then uninstall it from Windows Apps.
The installed application files should be removed while per-user ELIXR data
and logs remain outside the install directory.

Backend logs, when needed, are in `%LOCALAPPDATA%\ELIXR\logs\backend.log`;
startup/import failures are recorded in the adjacent
`backend_startup_error.log` file.
The packaged backend chooses a free loopback port for each ELIXR instance;
development still uses `127.0.0.1:8000` with `backend\run.ps1`. The packaged
backend also watches the owning ELIXR process as a force-close/crash cleanup
backstop, so it does not keep the camera after the desktop client disappears.

Pilot builds are unsigned. Windows Defender/SmartScreen may show an unknown
publisher warning; review the build provenance before choosing whether to run
it. Do not disable antivirus protections.
