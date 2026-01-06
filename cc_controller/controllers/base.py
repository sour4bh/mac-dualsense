"""Abstract base class for game controllers."""

from abc import ABC, abstractmethod
from typing import Callable


class BaseController(ABC):
    """Abstract base class for game controller implementations."""

    @abstractmethod
    def connect(self) -> bool:
        """Attempt to connect to controller. Returns True on success."""
        ...

    @abstractmethod
    def disconnect(self) -> None:
        """Disconnect from controller."""
        ...

    @property
    @abstractmethod
    def connected(self) -> bool:
        """Check if controller is connected."""
        ...

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable controller name."""
        ...

    @property
    def connection_type(self) -> str | None:
        """Best-effort connection type (e.g., USB/Bluetooth), if known."""
        return None

    @abstractmethod
    def get_pressed(self) -> list[str]:
        """Get list of buttons just pressed (edge detection). Returns canonical names."""
        ...

    def get_events(self) -> tuple[list[str], list[str]]:
        """Get (pressed, released) button events.

        Default implementation only reports presses for older controllers.
        """
        return (self.get_pressed(), [])

    @abstractmethod
    def trigger_haptic(self, pattern: str) -> None:
        """Trigger haptic feedback pattern (confirm, error, connect)."""
        ...

    def poll_loop(
        self,
        on_press: Callable[[str], None],
        running: Callable[[], bool],
        on_release: Callable[[str], None] | None = None,
        on_connect: Callable[["BaseController"], None] | None = None,
        on_disconnect: Callable[["BaseController"], None] | None = None,
    ) -> None:
        """Main polling loop with auto-reconnect."""
        import time

        reconnect_delay = 2.0
        notified_connected = False

        while running():
            if self.connected and not notified_connected:
                notified_connected = True
                if on_connect:
                    try:
                        on_connect(self)
                    except Exception:
                        pass
            elif not self.connected and notified_connected:
                notified_connected = False
                if on_disconnect:
                    try:
                        on_disconnect(self)
                    except Exception:
                        pass

            if not self.connected:
                if self.connect():
                    self.trigger_haptic("connect")
                    notified_connected = True
                    if on_connect:
                        try:
                            on_connect(self)
                        except Exception:
                            pass
                else:
                    time.sleep(reconnect_delay)
                    continue

            try:
                pressed, released = self.get_events()
                for btn in pressed:
                    on_press(btn)
                if on_release:
                    for btn in released:
                        on_release(btn)
                time.sleep(0.01)  # 10ms poll interval
            except Exception:
                pass
