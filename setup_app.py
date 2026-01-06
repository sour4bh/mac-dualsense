"""py2app setup for CC Controller."""

from setuptools import setup

APP = ["cc_controller/ui/__main__.py"]
DATA_FILES = [("config", ["config/mappings.yaml"])]
OPTIONS = {
    "argv_emulation": False,
    "plist": {
        "CFBundleName": "CC Controller",
        "CFBundleDisplayName": "CC Controller",
        "CFBundleIdentifier": "com.sour4bh.cc-controller",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "NSHighResolutionCapable": True,
    },
    "packages": ["cc_controller"],
    "includes": [
        "Quartz",
        "AppKit",
        "Foundation",
        "objc",
    ],
}

setup(
    app=APP,
    name="CC Controller",
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
