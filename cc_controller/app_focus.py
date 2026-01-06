"""Frontmost app detection for context-aware mappings."""
import time
from AppKit import NSWorkspace

# Bundle ID to context name mapping
APP_CONTEXTS = {
    # Warp terminal
    "dev.warp.Warp-Stable": "warp",
    "dev.warp.Warp": "warp",
    # Arc browser
    "company.thebrowser.Browser": "arc",
    # Chrome
    "com.google.Chrome": "chrome",
    # Slack
    "com.tinyspeck.slackmacgap": "slack",
    # ChatGPT
    "com.openai.chat": "chatgpt",
    # Claude desktop
    "com.anthropic.claudefordesktop": "claude",
}

TERMINAL_BUNDLE_IDS = {
    "dev.warp.Warp-Stable",
    "dev.warp.Warp",
    "com.apple.Terminal",
    "com.googlecode.iterm2",
}


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

    def is_terminal_focused(self) -> bool:
        """Check if any terminal app is frontmost."""
        return self.get_frontmost_app() in TERMINAL_BUNDLE_IDS

    def get_context(self) -> str:
        """Return context name for mapping resolution."""
        bundle = self.get_frontmost_app()
        return APP_CONTEXTS.get(bundle, "default")
