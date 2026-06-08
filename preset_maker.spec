# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_data_files, collect_submodules


APP_NAME = "Passport creator"

datas = collect_data_files("cv2") + collect_data_files("reportlab")
hiddenimports = collect_submodules("openpyxl") + collect_submodules("PIL") + collect_submodules("reportlab")
datas += [
    (
        "ios_app/GrandMA2Passport/GrandMA2Passport/Assets.xcassets/Logo.imageset/logoPC.png",
        "ios_app/GrandMA2Passport/GrandMA2Passport/Assets.xcassets/Logo.imageset",
    )
]


a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=APP_NAME,
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
    name=APP_NAME,
)
app = BUNDLE(
    coll,
    name=f"{APP_NAME}.app",
    icon=None,
    bundle_identifier="com.buha.passport-creator",
    info_plist={
        "NSCameraUsageDescription": "Нужен доступ к камере для фотографирования света приборов.",
        "NSHighResolutionCapable": True,
    },
)
