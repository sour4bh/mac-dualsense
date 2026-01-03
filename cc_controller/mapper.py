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
        self._mappings = config.get("mappings", {})
        self._app_focus = app_focus

    def resolve(self, button: str) -> Action:
        """Resolve button to action based on current app context."""
        context = self._app_focus.get_context()

        # Check context-specific mapping first
        action_def = None
        if context in self._mappings and button in self._mappings[context]:
            action_def = self._mappings[context][button]
        elif "default" in self._mappings and button in self._mappings["default"]:
            action_def = self._mappings["default"][button]

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
