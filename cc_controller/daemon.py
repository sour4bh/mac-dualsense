"""Main daemon entry point."""

import logging
import signal
import sys
import threading
from collections.abc import Callable
from pathlib import Path

from cc_controller.config import load_config
from cc_controller.controllers.base import BaseController
from cc_controller.detector import detect_controller
from cc_controller.app_focus import AppFocus
from cc_controller.mapper import Mapper
from cc_controller.keyboard import (
    check_accessibility,
    release_all_modifiers,
    send_keystroke,
    set_modifier,
    trigger_wispr,
)

log = logging.getLogger(__name__)


def configure_logging(level: int = logging.INFO) -> Path:
    """Configure logging to ~/Library/Logs/cc-controller.log (idempotent)."""
    log_dir = Path.home() / "Library" / "Logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "cc-controller.log"

    root = logging.getLogger()
    root.setLevel(level)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")

    has_file = any(
        isinstance(h, logging.FileHandler)
        and getattr(h, "baseFilename", None) == str(log_file)
        for h in root.handlers
    )
    if not has_file:
        fh = logging.FileHandler(log_file)
        fh.setFormatter(formatter)
        root.addHandler(fh)

    has_stream = any(isinstance(h, logging.StreamHandler) for h in root.handlers)
    if not has_stream:
        sh = logging.StreamHandler()
        sh.setFormatter(formatter)
        root.addHandler(sh)

    return log_file


class CCControllerDaemon:
    """Main daemon coordinating controller input to keyboard actions."""

    def __init__(
        self,
        config_path: Path | None = None,
        event_callback: Callable[[dict], None] | None = None,
    ):
        self._config = load_config(config_path)
        settings = self._config.get("settings", {})
        cache_ttl = settings.get("app_focus_cache_ttl_ms", 100)
        wispr_settings = settings.get("wispr", {})
        self._wispr_mode = wispr_settings.get("mode", "cmd_right")
        self._wispr_hold_ms = wispr_settings.get("hold_ms", 450)

        controller_settings = settings.get("controller", {})
        preferred = (
            controller_settings.get("preferred", "auto")
            if isinstance(controller_settings, dict)
            else "auto"
        )

        self._event_callback = event_callback
        self._controller = detect_controller(preferred=preferred)
        if not self._controller:
            raise RuntimeError("No supported controller found")

        self._app_focus = AppFocus(cache_ttl_ms=cache_ttl)
        self._mapper = Mapper(self._config, self._app_focus)
        self._running = False

    @property
    def controller(self) -> BaseController:
        return self._controller

    def _emit_event(self, payload: dict) -> None:
        if not self._event_callback:
            return
        try:
            self._event_callback(payload)
        except Exception:
            pass

    def _wispr_hold_modifier(self) -> str | None:
        mode_norm = str(self._wispr_mode).strip().lower()
        if mode_norm in ("lcmd_hold", "hold_lcmd"):
            return "lcmd"
        if mode_norm in ("rcmd_hold", "hold_rcmd"):
            return "rcmd"
        if mode_norm in ("fn_hold", "hold_fn"):
            return "fn"
        return None

    def start(self, install_signal_handlers: bool = True) -> None:
        """Start the daemon main loop."""
        log.info("cc-controller daemon starting")

        if not check_accessibility():
            raise PermissionError("Grant accessibility permission and restart")

        self._emit_event({"type": "daemon_started"})
        self._running = True
        if (
            install_signal_handlers
            and threading.current_thread() is threading.main_thread()
        ):
            signal.signal(signal.SIGTERM, self._handle_shutdown)
            signal.signal(signal.SIGINT, self._handle_shutdown)

        try:
            self._controller.poll_loop(
                self._on_button_press,
                lambda: self._running,
                on_release=self._on_button_release,
                on_connect=self._on_controller_connect,
                on_disconnect=self._on_controller_disconnect,
            )
        finally:
            # Avoid disconnecting inside the signal handler (can race with reads).
            self._running = False
            try:
                release_all_modifiers()
            except Exception:
                pass
            try:
                self._emit_event({"type": "controller_disconnected"})
                self._controller.disconnect()
            except Exception:
                pass
            finally:
                self._emit_event({"type": "daemon_stopped"})

    def stop(self) -> None:
        """Request a graceful stop."""
        self._running = False

    def _on_button_press(self, button: str) -> None:
        """Handle button press event."""
        action = self._mapper.resolve(button)
        log.info(f"Button: {button} -> {action.type}:{action.key}")
        self._emit_event(
            {
                "type": "button",
                "state": "pressed",
                "button": button,
                "action": {
                    "type": action.type,
                    "key": action.key,
                    "modifiers": action.modifiers,
                },
            }
        )

        if action.type == "keystroke" and action.key:
            if send_keystroke(action.key, action.modifiers):
                self._controller.trigger_haptic("confirm")
            else:
                self._controller.trigger_haptic("error")
        elif action.type == "wispr":
            hold_mod = self._wispr_hold_modifier()
            ok = (
                set_modifier(hold_mod, down=True)
                if hold_mod
                else trigger_wispr(mode=self._wispr_mode, hold_ms=self._wispr_hold_ms)
            )

            if ok:
                self._controller.trigger_haptic("confirm")
            else:
                self._controller.trigger_haptic("error")

    def _on_button_release(self, button: str) -> None:
        """Handle button release event."""
        action = self._mapper.resolve(button)
        self._emit_event({"type": "button", "state": "released", "button": button})
        if action.type != "wispr":
            return

        hold_mod = self._wispr_hold_modifier()
        if hold_mod:
            set_modifier(hold_mod, down=False)

    def _on_controller_connect(self, controller: BaseController) -> None:
        self._emit_event(
            {
                "type": "controller_connected",
                "name": controller.name,
                "connection": controller.connection_type,
            }
        )

    def _on_controller_disconnect(self, controller: BaseController) -> None:
        self._emit_event(
            {
                "type": "controller_disconnected",
                "name": controller.name,
            }
        )

    def _handle_shutdown(self, signum: int, frame) -> None:
        """Handle SIGTERM/SIGINT for graceful shutdown."""
        log.info(f"Received signal {signum}, shutting down")
        self._running = False


def main() -> None:
    """Entry point for cc-controller daemon."""
    log_file = configure_logging()
    log.info(f"Logging to {log_file}")
    try:
        daemon = CCControllerDaemon()
        daemon.start(install_signal_handlers=True)
    except Exception as exc:
        log.exception(str(exc))
        sys.exit(1)


if __name__ == "__main__":
    main()
