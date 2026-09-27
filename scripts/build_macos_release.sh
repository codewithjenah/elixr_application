#!/usr/bin/env bash
# Builds ELIXR for Apple Silicon: frozen arm64 backend + Flutter macOS app,
# assembled into ELIXR.app and packaged as build/macos-release/ELIXR-macOS-arm64.dmg.
#
# Run on an arm64 Mac from the repository root with Flutter, Xcode, and
# CPython 3.11 (arm64) available. The installed app needs none of these.
#
# Signing modes:
#   * Development (default): ad-hoc signature. Structurally valid for testing;
#     NOT notarized, Gatekeeper will warn on other Macs.
#   * Distribution: set MACOS_SIGN_IDENTITY="Developer ID Application: ..."
#     (certificate already in the keychain). Hardened Runtime is enabled.
#     Notarization additionally needs NOTARY_KEYCHAIN_PROFILE (a profile
#     stored with `xcrun notarytool store-credentials`).
#
# Environment:
#   PYTHON                  Python 3.11 arm64 interpreter (default: python3.11)
#   SKIP_BACKEND_TESTS=1    skip the targeted pre-freeze backend tests
#   SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY  optional build-time overrides
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/build/macos-release"
VENV="$OUT/venv"
BACKEND_DIST="$OUT/backend-dist"
BACKEND_WORK="$OUT/backend-work"
STAGE="$OUT/dmg-stage"
APP_NAME="ELIXR.app"
DMG="$OUT/ELIXR-macOS-arm64.dmg"
PYTHON="${PYTHON:-python3.11}"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
ENTITLEMENTS_APP="$REPO_ROOT/macos/Runner/Release.entitlements"
ENTITLEMENTS_BACKEND="$REPO_ROOT/packaging/macos/backend.entitlements"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Build the macOS package on macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "Use a native arm64 Mac (not Rosetta)."

rm -rf "$OUT"
mkdir -p "$OUT"

log "Creating arm64 Python build environment"
"$PYTHON" -c 'import platform, sys; assert sys.version_info[:2] == (3, 11), sys.version; assert platform.machine() == "arm64", platform.machine()' \
  || fail "PYTHON must be CPython 3.11 running natively on arm64."
"$PYTHON" -m venv "$VENV"
PY="$VENV/bin/python"
"$PY" -m pip install --upgrade pip
"$PY" -m pip install -r "$REPO_ROOT/backend/requirements-dev.txt" -r "$REPO_ROOT/packaging/requirements-build.txt"

log "Checking installed dependency metadata"
# mediapipe 0.10.9's macOS wheel is named universal2 but its WHEEL metadata
# declares only macosx_13_0_x86_64, so `pip check` reports it unsupported on
# arm64. That exact line alone is tolerated, and only after the verifier
# proves the wheel's arm64 slices and a real Hands/Pose inference. Any other
# `pip check` finding stays fatal.
MEDIAPIPE_TAG_COMPLAINT="mediapipe 0.10.9 is not supported on this platform"
set +e
PIP_CHECK_OUTPUT="$("$PY" -m pip check 2>&1)"
PIP_CHECK_STATUS=$?
set -e
printf '%s\n' "$PIP_CHECK_OUTPUT"
MEDIAPIPE_VERIFY_FLAGS=()
if [[ $PIP_CHECK_STATUS -ne 0 ]]; then
  OTHER_FINDINGS="$(printf '%s\n' "$PIP_CHECK_OUTPUT" | grep -vxF "$MEDIAPIPE_TAG_COMPLAINT" | grep -v '^[[:space:]]*$' || true)"
  if [[ -n "$OTHER_FINDINGS" ]] || ! grep -qxF "$MEDIAPIPE_TAG_COMPLAINT" <<<"$PIP_CHECK_OUTPUT"; then
    fail "pip check reported dependency problems."
  fi
  echo "Only the known mediapipe 0.10.9 wheel-tag complaint; verifying the real runtime."
  MEDIAPIPE_VERIFY_FLAGS+=(--mislabeled-wheel)
fi

log "Verifying MediaPipe arm64 runtime"
"$PY" "$REPO_ROOT/packaging/macos/verify_mediapipe_runtime.py" ${MEDIAPIPE_VERIFY_FLAGS[@]+"${MEDIAPIPE_VERIFY_FLAGS[@]}"} \
  || fail "MediaPipe is not usable on this arm64 host."
"$PY" - <<'PY'
import cv2, mediapipe, numpy, ultralytics, onnxruntime as ort
providers = ort.get_available_providers()
assert "CPUExecutionProvider" in providers, providers
try:
    import comtypes  # noqa: F401
except ImportError:
    pass
else:
    raise SystemExit("comtypes must not be installed on macOS")
print("cv2", cv2.__version__, "| onnxruntime", ort.__version__, providers)
PY

if [[ "${SKIP_BACKEND_TESTS:-0}" != "1" ]]; then
  log "Running targeted backend tests before freezing"
  (cd "$REPO_ROOT/backend" && "$PY" -m pytest -q \
    tests/test_macos_platform.py tests/test_camera_selection.py \
    tests/test_runtime_paths.py tests/test_prop_runtime.py)
fi

log "Freezing the backend with PyInstaller"
"$PY" -m PyInstaller --noconfirm --clean \
  --distpath "$BACKEND_DIST" --workpath "$BACKEND_WORK" \
  "$REPO_ROOT/packaging/elixr_backend.spec"
BACKEND_BUNDLE="$BACKEND_DIST/elixr_backend"
[[ -x "$BACKEND_BUNDLE/elixr_backend" ]] || fail "Frozen backend executable missing."

log "Verifying backend architecture"
lipo -archs "$BACKEND_BUNDLE/elixr_backend" | grep -qw arm64 || fail "Backend is not arm64."
non_arm=0
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    if ! lipo -archs "$f" 2>/dev/null | grep -qw arm64; then
      echo "Not arm64: $f"; non_arm=1
    fi
  fi
done < <(find "$BACKEND_BUNDLE" -type f -print0)
[[ $non_arm -eq 0 ]] || fail "Frozen backend contains Mach-O files without an arm64 slice."

log "Verifying frozen backend resources"
"$BACKEND_BUNDLE/elixr_backend" --verify-resources || fail "Frozen backend resource verification failed."

log "Building Flutter macOS release"
FLUTTER_DEFINES=()
[[ -n "${SUPABASE_URL:-}" ]] && FLUTTER_DEFINES+=("--dart-define=SUPABASE_URL=$SUPABASE_URL")
if [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  [[ "$SUPABASE_PUBLISHABLE_KEY" == sb_secret_* ]] && fail "Never build with a Supabase secret key."
  FLUTTER_DEFINES+=("--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY")
fi
(cd "$REPO_ROOT" && flutter build macos --release ${FLUTTER_DEFINES[@]+"${FLUTTER_DEFINES[@]}"})
BUILT_APP="$REPO_ROOT/build/macos/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT_APP" ]] || fail "Flutter did not produce $BUILT_APP"

log "Assembling $APP_NAME with its sidecar"
mkdir -p "$STAGE"
ditto "$BUILT_APP" "$STAGE/$APP_NAME"
APP="$STAGE/$APP_NAME"
# Must match BackendService.packagedBackendCandidates (macOS).
APP_BACKEND="$APP/Contents/Resources/backend"
mkdir -p "$APP_BACKEND"
ditto "$BACKEND_BUNDLE" "$APP_BACKEND"
chmod 755 "$APP_BACKEND/elixr_backend"

MODEL_DIR="$APP_BACKEND/_internal/models"
[[ -d "$MODEL_DIR" ]] || MODEL_DIR="$APP_BACKEND/models"
for model in best.onnx best.pt hand_landmarker.task pose_landmarker_lite.task; do
  [[ -f "$MODEL_DIR/$model" ]] || fail "Bundle is missing model: $model"
done
find "$APP_BACKEND" -path '*onnxruntime*' -name 'libonnxruntime*.dylib' | grep -q . \
  || fail "Bundle is missing the ONNX Runtime native library."
find "$APP_BACKEND" -path '*mediapipe*' -name '*.so' | grep -q . \
  || fail "Bundle is missing MediaPipe native extensions."
find "$APP_BACKEND" -path '*cv2*' -name '*.so' | grep -q . \
  || fail "Bundle is missing OpenCV native extensions."

log "Signing (identity: ${SIGN_IDENTITY})"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  # Hardened Runtime + secure timestamp are required for notarization.
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
# Inside-out: nested backend libraries first, then the backend executable
# (sandbox-inherit entitlements), then Flutter frameworks, then the app.
while IFS= read -r -d '' f; do
  if [[ "$f" != "$APP_BACKEND/elixr_backend" ]] && file -b "$f" | grep -q 'Mach-O'; then
    codesign "${SIGN_FLAGS[@]}" "$f"
  fi
done < <(find "$APP_BACKEND" -type f -print0)
codesign "${SIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS_BACKEND" "$APP_BACKEND/elixr_backend"
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0 |
    while IFS= read -r -d '' fw; do codesign "${SIGN_FLAGS[@]}" "$fw"; done
fi
codesign "${SIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS_APP" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

log "Verifying app architecture"
APP_EXE="$APP/Contents/MacOS/ELIXR"
file "$APP_EXE" "$APP_BACKEND/elixr_backend"
lipo -archs "$APP_EXE" | grep -qw arm64 || fail "ELIXR executable has no arm64 slice."
echo "ELIXR executable archs: $(lipo -archs "$APP_EXE")"
echo "Backend executable archs: $(lipo -archs "$APP_BACKEND/elixr_backend")"
plutil -extract NSCameraUsageDescription raw "$APP/Contents/Info.plist" >/dev/null \
  || fail "Info.plist is missing NSCameraUsageDescription."

log "Creating $(basename "$DMG")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ELIXR" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ "$SIGN_IDENTITY" != "-" && -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  log "Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  echo "SIGNING: Developer ID signed, notarized, and stapled."
elif [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "SIGNING: Developer ID signed; NOT notarized (NOTARY_KEYCHAIN_PROFILE unset)."
else
  echo "SIGNING: ad-hoc development build; NOT Developer ID signed or notarized."
fi

echo "DMG: $DMG"
