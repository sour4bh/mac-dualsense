"""YAML configuration loader."""
from pathlib import Path
import yaml

DEFAULT_CONFIG_PATH = Path(__file__).parent.parent / "config" / "mappings.yaml"


def load_config(path: Path | None = None) -> dict:
    """Load configuration from YAML file."""
    config_path = path or DEFAULT_CONFIG_PATH
    return yaml.safe_load(config_path.read_text())
