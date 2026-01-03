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

    @abstractmethod
    def get_pressed(self) -> list[str]:
        """Get list of buttons just pressed (edge detection). Returns canonical names."""
        ...

    @abstractmethod
    def trigger_haptic(self, pattern: str) -> None:
        """Trigger haptic feedback pattern (confirm, error, connect)."""
        ...

    def poll_loop(self, on_press: Callable[[str], None], running: Callable[[], bool]) -> None:
        """Main polling loop with auto-reconnect."""
        import time
        reconnect_delay = 2.0

        while running():
            if not self.connected:
                if self.connect():
                    self.trigger_haptic("connect")
                else:
                    time.sleep(reconnect_delay)
                    continue

            try:
                pressed = self.get_pressed()
                for btn in pressed:
                    on_press(btn)
                time.sleep(0.01)  # 10ms poll interval
            except Exception:
                pass
