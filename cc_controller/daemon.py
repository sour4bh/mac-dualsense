"""Main daemon entry point."""
import logging
import signal
import sys
from pathlib import Path

from cc_controller.config import load_config
from cc_controller.detector import detect_controller
from cc_controller.app_focus import AppFocus
from cc_controller.mapper import Mapper
from cc_controller.keyboard import send_keystroke, trigger_wispr

log = logging.getLogger(__name__)


class CCControllerDaemon:
    """Main daemon coordinating controller input to keyboard actions."""

    def __init__(self, config_path: Path | None = None):
        self._config = load_config(config_path)
        settings = self._config.get("settings", {})
        cache_ttl = settings.get("app_focus_cache_ttl_ms", 100)

        self._controller = detect_controller()
        if not self._controller:
            log.error("No supported controller found")
            sys.exit(1)

        self._app_focus = AppFocus(cache_ttl_ms=cache_ttl)
        self._mapper = Mapper(self._config, self._app_focus)
        self._running = False

    def start(self) -> None:
        """Start the daemon main loop."""
        log.info("cc-controller daemon starting")
        self._running = True

        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

        self._controller.poll_loop(self._on_button_press, lambda: self._running)

    def _on_button_press(self, button: str) -> None:
        """Handle button press event."""
        action = self._mapper.resolve(button)
        log.info(f"Button: {button} -> {action.type}:{action.key}")

        if action.type == "keystroke" and action.key:
            if send_keystroke(action.key, action.modifiers):
                self._controller.trigger_haptic("confirm")
            else:
                self._controller.trigger_haptic("error")
        elif action.type == "wispr":
            if trigger_wispr():
                self._controller.trigger_haptic("confirm")
            else:
                self._controller.trigger_haptic("error")

    def _handle_shutdown(self, signum: int, frame) -> None:
        """Handle SIGTERM/SIGINT for graceful shutdown."""
        log.info(f"Received signal {signum}, shutting down")
        self._running = False
        self._controller.disconnect()


def main() -> None:
    """Entry point for cc-controller daemon."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    daemon = CCControllerDaemon()
    daemon.start()


if __name__ == "__main__":
    main()
