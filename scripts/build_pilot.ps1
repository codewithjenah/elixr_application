param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pilotRoot = Join-Path $repoRoot "build\pilot"
$stageRoot = Join-Path $pilotRoot "staging"
$backendDist = Join-Path $pilotRoot "backend-dist"
$backendWork = Join-Path $pilotRoot "backend-work"
$backendPython = Join-Path $repoRoot "backend\.venv\Scripts\python.exe"
$backendSpec = Join-Path $repoRoot "packaging\elixr_backend.spec"
$buildRequirements = Join-Path $repoRoot "packaging\requirements-build.txt"
$installerScript = Join-Path $repoRoot "packaging\ELIXR.iss"
$expectedPyInstallerVersion = "6.22.2"

function Remove-SafeDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }
    $resolvedPath = (Resolve-Path -LiteralPath $path).Path.TrimEnd("\")
    $allowedRoot = $pilotRoot.TrimEnd("\")
    $isAllowed = $resolvedPath.Equals($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPath.StartsWith($allowedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $isAllowed) {
        throw "Refusing to remove an unexpected build path: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Find-InnoCompiler {
    $command = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles} "Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:LOCALAPPDATA} "Programs\Inno Setup 6\ISCC.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $backendPython)) {
    throw "Missing backend virtual environment: $backendPython. Create it and install backend\requirements-dev.txt first."
}
if (-not (Test-Path -LiteralPath $backendSpec)) {
    throw "Missing backend PyInstaller spec: $backendSpec"
}
if (-not (Test-Path -LiteralPath $buildRequirements)) {
    throw "Missing pinned build requirements: $buildRequirements"
}
if (-not (Test-Path -LiteralPath $installerScript)) {
    throw "Missing installer definition: $installerScript"
}

$flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
}
if (-not $flutterCommand) {
    throw "Flutter is required and was not found on PATH."
}

$pyinstallerVersion = (& $backendPython -c "import PyInstaller; print(PyInstaller.__version__)") 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller is required in backend\.venv. Install it with: $backendPython -m pip install -r packaging\requirements-build.txt"
}
if ($pyinstallerVersion.Trim() -ne $expectedPyInstallerVersion) {
    throw "PyInstaller $expectedPyInstallerVersion is required for reproducible builds; found $($pyinstallerVersion.Trim()). Install it with: $backendPython -m pip install -r packaging\requirements-build.txt"
}

$innoCompiler = Find-InnoCompiler
if (-not $SkipInstaller -and -not $innoCompiler) {
    throw "Inno Setup 6 is required to create ELIXR_Setup.exe. Install it separately, then rerun scripts\build_pilot.ps1."
}

$versionLine = Select-String -LiteralPath (Join-Path $repoRoot "pubspec.yaml") -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
if (-not $versionLine) {
    throw "Could not derive the application version from pubspec.yaml."
}
$appVersion = $versionLine.Matches[0].Groups[1].Value

Remove-SafeDirectory $pilotRoot
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $backendDist -Force | Out-Null
New-Item -ItemType Directory -Path $backendWork -Force | Out-Null

Write-Host "Building Flutter Windows release..."
& $flutterCommand.Path build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows release build failed."
}

Write-Host "Freezing the backend with PyInstaller..."
& $backendPython -m PyInstaller --noconfirm --clean `
    --distpath $backendDist `
    --workpath $backendWork `
    $backendSpec
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller backend build failed."
}

$flutterRelease = Join-Path $repoRoot "build\windows\x64\runner\Release"
$backendBundle = Join-Path $backendDist "elixr_backend"
$backendExecutable = Join-Path $backendBundle "elixr_backend.exe"
if (-not (Test-Path -LiteralPath $flutterRelease)) {
    throw "Flutter release bundle was not found at $flutterRelease"
}
if (-not (Test-Path -LiteralPath $backendExecutable)) {
    throw "Frozen backend executable was not found at $backendExecutable"
}

Write-Host "Staging the complete application bundle..."
Copy-Item -Path (Join-Path $flutterRelease "*") -Destination $stageRoot -Recurse -Force
$stageBackend = Join-Path $stageRoot "backend"
New-Item -ItemType Directory -Path $stageBackend -Force | Out-Null
Copy-Item -Path (Join-Path $backendBundle "*") -Destination $stageBackend -Recurse -Force

# The Flutter runner links the Microsoft C/C++ runtime dynamically. Copy the
# exact x64 runtime files already collected by PyInstaller into the app root
# so a pilot machine does not need Visual Studio or a separate runtime install.
$appRuntimeNames = @("MSVCP140.dll", "VCRUNTIME140.dll", "VCRUNTIME140_1.dll")
$backendRuntimeRoot = Join-Path $stageBackend "_internal"
foreach ($runtimeName in $appRuntimeNames) {
    $runtimeSource = Join-Path $backendRuntimeRoot $runtimeName
    if (-not (Test-Path -LiteralPath $runtimeSource)) {
        throw "Staged backend is missing the app-local runtime DLL: $runtimeSource"
    }
    Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $stageRoot $runtimeName) -Force
}

$requiredFiles = @(
    (Join-Path $stageRoot "elixr_application.exe"),
    (Join-Path $stageRoot "flutter_windows.dll"),
    (Join-Path $stageRoot "MSVCP140.dll"),
    (Join-Path $stageRoot "VCRUNTIME140.dll"),
    (Join-Path $stageRoot "VCRUNTIME140_1.dll"),
    (Join-Path $stageRoot "data\flutter_assets"),
    (Join-Path $stageBackend "elixr_backend.exe")
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Staged distribution is missing required content: $requiredFile"
    }
}
$modelRootCandidates = @(
    (Join-Path $stageBackend "_internal\models"),
    (Join-Path $stageBackend "models")
)
$stagedModelRoot = $modelRootCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $stagedModelRoot) {
    throw "Staged distribution is missing the frozen backend model directory."
}
foreach ($modelName in @("best.onnx", "hand_landmarker.task", "pose_landmarker_lite.task")) {
    $modelPath = Join-Path $stagedModelRoot $modelName
    if (-not (Test-Path -LiteralPath $modelPath)) {
        throw "Staged distribution is missing required model asset: $modelPath"
    }
}
Write-Host "Verifying frozen backend resources..."
& (Join-Path $stageBackend "elixr_backend.exe") --verify-resources
if ($LASTEXITCODE -ne 0) {
    throw "Frozen backend resource verification failed."
}

if ($SkipInstaller) {
    Write-Host "Staged distribution: $stageRoot"
    exit 0
}

Write-Host "Building ELIXR_Setup.exe with Inno Setup..."
& $innoCompiler "/DAppVersion=$appVersion" "/DSourceDir=$stageRoot" "/DOutputDir=$pilotRoot" $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}

$installerPath = Join-Path $pilotRoot "ELIXR_Setup.exe"
if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Inno Setup completed without producing $installerPath"
}
Write-Host "ELIXR installer: $installerPath"
