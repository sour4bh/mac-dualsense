"""Abstract base class for haptic feedback."""
from abc import ABC, abstractmethod


class BaseHaptics(ABC):
    """Abstract base class for haptic feedback implementations."""

    @abstractmethod
    def trigger(self, pattern: str) -> None:
        """Trigger a predefined haptic pattern (confirm, error, connect)."""
        ...

    @abstractmethod
    def rumble(self, left: int, right: int, duration_ms: int = 60) -> None:
        """Send custom rumble with motor intensities 0-255."""
        ...
