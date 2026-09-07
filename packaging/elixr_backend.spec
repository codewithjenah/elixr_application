# PyInstaller one-folder build for the local ELIXR FastAPI/CV sidecar.

from pathlib import Path

from PyInstaller.utils.hooks import (
    collect_data_files,
    collect_dynamic_libs,
    collect_submodules,
)


# SPECPATH is packaging\; its parent is the repository root.
ROOT = Path(SPECPATH).resolve().parent
BACKEND_ROOT = ROOT / "backend"

datas = [(str(BACKEND_ROOT / "models"), "models")]
binaries = []
hiddenimports = []

# MediaPipe's task API depends on native extensions and generated protobuf
# modules. Collect only its runtime task/data surface; collect_all() would also
# pull in the package's examples and tests.
datas.extend(
    collect_data_files(
        "mediapipe",
        includes=["**/*.binarypb", "**/*.tflite", "**/*.json", "**/*.pbtxt"],
        excludes=["**/*test*", "**/testdata/**", "**/examples/**"],
    )
)
binaries.extend(collect_dynamic_libs("mediapipe"))
hiddenimports.extend(
    collect_submodules(
        "mediapipe.tasks.python",
        filter=lambda name: ".test" not in name and not name.endswith("_test"),
    )
)
hiddenimports.extend(
    collect_submodules(
        "mediapipe.tasks.cc",
        filter=lambda name: ".test" not in name and not name.endswith("_test"),
    )
)

# ONNX Runtime's hook supplies its provider DLLs. The application only imports
# the runtime API, so collecting its quantization/conversion tools would add
# development-only modules and the optional onnx package.
binaries.extend(collect_dynamic_libs("onnxruntime"))

# cv2, ultralytics, and torch have maintained PyInstaller hooks that supply
# their native/runtime pieces. The Torch hook is intentionally retained because
# the backend can fall back to PyTorch when ONNX is unavailable.

hiddenimports.extend(
    [
        "comtypes",
        "comtypes.client",
        "comtypes.automation",
        "comtypes.persist",
        "comtypes.gen",
    ]
)
hiddenimports.extend(collect_submodules("uvicorn"))

a = Analysis(
    [str(BACKEND_ROOT / "packaged_server.py")],
    pathex=[str(BACKEND_ROOT)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "pytest",
        "IPython",
        "jupyter",
        "notebook",
        "tensorboard",
        "torch.utils.tensorboard",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="elixr_backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="elixr_backend",
)
