"""YAML configuration loader and user-scoped config management."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

import yaml

APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "cc-controller"
USER_CONFIG_PATH = APP_SUPPORT_DIR / "mappings.yaml"


def get_user_config_path() -> Path:
    """Return the user-scoped config path."""
    return USER_CONFIG_PATH


def _bundle_resource_dir() -> Path | None:
    """Best-effort lookup for a macOS app bundle Resources directory."""
    try:
        from Foundation import NSBundle  # type: ignore[import-not-found]

        resource_path = NSBundle.mainBundle().resourcePath()
        return Path(resource_path) if resource_path else None
    except Exception:
        return None


def _default_seed_paths() -> list[Path]:
    """Candidate seed config locations (dev checkout, app bundle, etc.)."""
    repo_seed = Path(__file__).resolve().parent.parent / "config" / "mappings.yaml"
    paths = [repo_seed]

    bundle_dir = _bundle_resource_dir()
    if bundle_dir:
        paths.append(bundle_dir / "config" / "mappings.yaml")

    return paths


def _seed_config_file(dest: Path) -> None:
    """Create an initial config file at dest."""
    dest.parent.mkdir(parents=True, exist_ok=True)

    for seed in _default_seed_paths():
        if seed.exists():
            shutil.copyfile(seed, dest)
            return

    # Last-resort minimal config (keeps the daemon functional).
    minimal = {
        "version": 2,
        "settings": {},
        "profiles": {"active": "default", "items": {"default": {"mappings": {"default": {}}}}},
        "haptics": {"enabled": True, "patterns": {}},
    }
    dest.write_text(yaml.safe_dump(minimal, sort_keys=False), encoding="utf-8")


def _normalize_config(raw: dict) -> dict:
    """Normalize config to the canonical (profile-aware) schema."""
    if not isinstance(raw, dict):
        raw = {}

    settings = raw.get("settings") if isinstance(raw.get("settings"), dict) else {}
    haptics = raw.get("haptics") if isinstance(raw.get("haptics"), dict) else {}

    # Support legacy schema: top-level "mappings".
    legacy_mappings = raw.get("mappings") if isinstance(raw.get("mappings"), dict) else None

    profiles = raw.get("profiles") if isinstance(raw.get("profiles"), dict) else {}
    items = profiles.get("items") if isinstance(profiles.get("items"), dict) else {}
    active = profiles.get("active") if isinstance(profiles.get("active"), str) else None

    if legacy_mappings is not None and not items:
        items = {"default": {"mappings": legacy_mappings}}
        active = active or "default"

    if not items:
        items = {"default": {"mappings": {"default": {}}}}
        active = active or "default"

    if active not in items:
        active = next(iter(items.keys()))

    return {
        "version": int(raw.get("version", 2) or 2),
        "settings": settings,
        "profiles": {"active": active, "items": items},
        "haptics": haptics,
    }


def load_config(path: Path | None = None) -> dict:
    """Load configuration from YAML file.

    If path is omitted, uses the user-scoped config in
    ~/Library/Application Support/cc-controller/mappings.yaml (creating it on
    first run by copying the bundled default config).
    """
    env_path = os.environ.get("CC_CONTROLLER_CONFIG_PATH")
    config_path = Path(env_path).expanduser() if env_path else None
    config_path = path or config_path or USER_CONFIG_PATH

    if not config_path.exists():
        _seed_config_file(config_path)

    raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    config = _normalize_config(raw)
    config["_meta"] = {"path": str(config_path)}
    return config


def save_config(config: dict, path: Path | None = None) -> Path:
    """Atomically save configuration to YAML. Returns the written path."""
    config_path = path or Path(config.get("_meta", {}).get("path") or USER_CONFIG_PATH)
    config_path = config_path.expanduser()
    config_path.parent.mkdir(parents=True, exist_ok=True)

    # Do not persist internal metadata.
    to_write = {k: v for k, v in config.items() if k != "_meta"}
    payload = yaml.safe_dump(to_write, sort_keys=False)

    with tempfile.NamedTemporaryFile("w", delete=False, dir=str(config_path.parent), encoding="utf-8") as tmp:
        tmp.write(payload)
        tmp_path = Path(tmp.name)

    tmp_path.replace(config_path)
    return config_path
