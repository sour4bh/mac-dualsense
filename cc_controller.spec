# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_submodules

hiddenimports = (
    collect_submodules("Quartz")
    + collect_submodules("AppKit")
    + collect_submodules("Foundation")
)

a = Analysis(
    ["cc_controller/ui/__main__.py"],
    pathex=[],
    binaries=[],
    datas=[("config/mappings.yaml", "config")],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="CC Controller",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="CC Controller",
)

app = BUNDLE(
    coll,
    name="CC Controller.app",
    icon=None,
    bundle_identifier="com.sour4bh.cc-controller",
    info_plist={
        "CFBundleName": "CC Controller",
        "CFBundleDisplayName": "CC Controller",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "NSHighResolutionCapable": True,
    },
)
