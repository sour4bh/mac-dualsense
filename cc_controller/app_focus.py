"""Frontmost app detection for context-aware mappings."""
import time
from AppKit import NSWorkspace

WARP_BUNDLE_IDS = {"dev.warp.Warp-Stable", "dev.warp.Warp"}
TERMINAL_BUNDLE_IDS = WARP_BUNDLE_IDS | {"com.apple.Terminal", "com.googlecode.iterm2"}


class AppFocus:
    """Detect frontmost application with caching."""

    def __init__(self, cache_ttl_ms: int = 100):
        self._workspace = NSWorkspace.sharedWorkspace()
        self._cache_ttl = cache_ttl_ms / 1000.0
        self._cached_bundle: str | None = None
        self._cache_time: float = 0

    def get_frontmost_app(self) -> str | None:
        """Return bundle identifier of frontmost app (cached)."""
        now = time.monotonic()
        if now - self._cache_time < self._cache_ttl and self._cached_bundle is not None:
            return self._cached_bundle

        app = self._workspace.frontmostApplication()
        self._cached_bundle = app.bundleIdentifier() if app else None
        self._cache_time = now
        return self._cached_bundle

    def is_warp_focused(self) -> bool:
        """Check if Warp terminal is the frontmost app."""
        return self.get_frontmost_app() in WARP_BUNDLE_IDS

    def is_terminal_focused(self) -> bool:
        """Check if any terminal app is frontmost."""
        return self.get_frontmost_app() in TERMINAL_BUNDLE_IDS

    def get_context(self) -> str:
        """Return context name for mapping resolution."""
        if self.is_warp_focused():
            return "warp"
        return "default"
