"""Button-to-action mapping engine."""
import logging
from dataclasses import dataclass

from cc_controller.app_focus import AppFocus

log = logging.getLogger(__name__)


@dataclass
class Action:
    """Resolved action from button press."""
    type: str  # "keystroke", "wispr", "noop"
    key: str | None = None
    modifiers: list[str] | None = None


class Mapper:
    """Resolve controller buttons to actions based on context."""

    def __init__(self, config: dict, app_focus: AppFocus):
        self._config = config
        self._app_focus = app_focus

    def _mappings(self) -> dict:
        """Return the active profile's mappings (with legacy fallback)."""
        profiles = self._config.get("profiles")
        if isinstance(profiles, dict):
            active = profiles.get("active")
            items = profiles.get("items")
            if isinstance(active, str) and isinstance(items, dict):
                profile = items.get(active)
                if isinstance(profile, dict):
                    mappings = profile.get("mappings")
                    if isinstance(mappings, dict):
                        return mappings

        legacy = self._config.get("mappings")
        return legacy if isinstance(legacy, dict) else {}

    def resolve(self, button: str) -> Action:
        """Resolve button to action based on current app context."""
        context = self._app_focus.get_context()
        mappings = self._mappings()

        # Check context-specific mapping first
        action_def = None
        if context in mappings and button in mappings[context]:
            action_def = mappings[context][button]
        elif "default" in mappings and button in mappings["default"]:
            action_def = mappings["default"][button]

        if not action_def:
            return Action(type="noop")

        return self._parse_action(action_def)

    def _parse_action(self, action_def: dict) -> Action:
        """Parse action definition from config."""
        action_type = action_def.get("type", "noop")

        if action_type == "keystroke":
            return Action(
                type="keystroke",
                key=action_def.get("key"),
                modifiers=action_def.get("modifiers"),
            )
        elif action_type == "wispr":
            return Action(type="wispr")

        return Action(type="noop")
