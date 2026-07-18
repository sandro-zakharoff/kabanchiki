# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path
import sys

geoservices = Path(sys.prefix) / 'Lib' / 'site-packages' / 'PySide6' / 'plugins' / 'geoservices'
datas = [
    ('src\\kabanchiki_admin\\qml', 'kabanchiki_admin\\qml'),
    ('src\\kabanchiki_admin\\i18n', 'kabanchiki_admin\\i18n'),
    ('assets', 'assets'),
    ('config.example.json', '.'),
]
if geoservices.exists():
    datas.append((str(geoservices), 'PySide6\\plugins\\geoservices'))


a = Analysis(
    ['src\\main.py'],
    pathex=['src'],
    binaries=[],
    datas=datas,
    hiddenimports=[],
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
    name='Kabanchiki',
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
    icon=['assets\\app.ico'],
    version='version_info.txt',
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Kabanchiki',
)
