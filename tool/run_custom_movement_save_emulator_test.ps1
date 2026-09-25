$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exitCode = 0

Push-Location -LiteralPath $repositoryRoot
try {
  firebase emulators:exec `
    --project elixr-app-2026 `
    --only auth,firestore,storage `
    'flutter test integration_test/custom_movement_save_emulator_test.dart -d windows'
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($exitCode -ne 0) {
  exit $exitCode
}
