"""macOS keystroke injection via Quartz."""
import ctypes
import logging
import sys
import time
from pathlib import Path

import Quartz

log = logging.getLogger(__name__)

# Load ApplicationServices for accessibility check
_appserv = ctypes.cdll.LoadLibrary(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
)
_appserv.AXIsProcessTrusted.restype = ctypes.c_bool


def check_accessibility() -> bool:
    """Check if accessibility permissions are granted."""
    trusted = _appserv.AXIsProcessTrusted()
    if not trusted:
        app = Path(sys.argv[0]).name or "this app"
        log.error(
            "Accessibility permission required! Enable %s in: System Settings → Privacy & Security → Accessibility",
            app,
        )
    return trusted

KEY_CODES = {
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
    "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
    "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
    "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
    "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19,
    "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
    "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
    "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
    ".": 0x2F, "`": 0x32, " ": 0x31,
    "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33,
    "escape": 0x35, "backspace": 0x33,
    "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
    "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    # Navigation / editing (extended keys)
    "help": 0x72,
    "home": 0x73,
    "pageup": 0x74, "page_up": 0x74,
    "forward_delete": 0x75, "delete_forward": 0x75, "forwarddelete": 0x75,
    "end": 0x77,
    "pagedown": 0x79, "page_down": 0x79,
    # Modifier-like key (not reliably meaningful on its own)
    "fn": 0x3F,
}

MODIFIERS = {
    "cmd": Quartz.kCGEventFlagMaskCommand,
    "ctrl": Quartz.kCGEventFlagMaskControl,
    "shift": Quartz.kCGEventFlagMaskShift,
    "alt": Quartz.kCGEventFlagMaskAlternate,
    "option": Quartz.kCGEventFlagMaskAlternate,
    "fn": Quartz.kCGEventFlagMaskSecondaryFn,
}

MODIFIER_KEYCODES = {
    "lcmd": 0x37,
    "rcmd": 0x36,
    "lshift": 0x38,
    "rshift": 0x3C,
    "lctrl": 0x3B,
    "rctrl": 0x3E,
    "lalt": 0x3A,
    "ralt": 0x3D,
    "loption": 0x3A,
    "roption": 0x3D,
    "fn": 0x3F,
}

_HELD_MODIFIERS: set[str] = set()


def send_keystroke(key: str, modifiers: list[str] | None = None) -> bool:
    """Send a single keystroke with optional modifiers."""
    key_lower = key.lower()
    if key_lower not in KEY_CODES:
        log.warning(f"Unknown key: {key}")
        return False

    keycode = KEY_CODES[key_lower]
    flags = 0
    for mod in (modifiers or []):
        mod_lower = mod.lower()
        if mod_lower in MODIFIERS:
            flags |= MODIFIERS[mod_lower]

    key_down = Quartz.CGEventCreateKeyboardEvent(None, keycode, True)
    key_up = Quartz.CGEventCreateKeyboardEvent(None, keycode, False)

    if flags:
        Quartz.CGEventSetFlags(key_down, flags)
        Quartz.CGEventSetFlags(key_up, flags)

    Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_down)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_up)

    log.debug(f"Sent keystroke: {key} modifiers={modifiers}")
    return True


def _modifier_flags(modifier: str) -> int:
    mod = modifier.lower()
    if mod in ("cmd", "command", "lcmd", "rcmd"):
        return Quartz.kCGEventFlagMaskCommand
    if mod in ("shift", "lshift", "rshift"):
        return Quartz.kCGEventFlagMaskShift
    if mod in ("ctrl", "control", "lctrl", "rctrl"):
        return Quartz.kCGEventFlagMaskControl
    if mod in ("alt", "option", "lalt", "ralt", "loption", "roption"):
        return Quartz.kCGEventFlagMaskAlternate
    if mod in ("fn",):
        return Quartz.kCGEventFlagMaskSecondaryFn
    return 0


def set_modifier(modifier: str, down: bool) -> bool:
    """Press or release a modifier key (e.g., lcmd/rcmd)."""
    mod = modifier.lower()
    keycode = MODIFIER_KEYCODES.get(mod)
    if keycode is None:
        log.warning(f"Unknown modifier key: {modifier}")
        return False

    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, down)
    if not event:
        return False

    flags = _modifier_flags(mod) if down else 0
    if flags:
        Quartz.CGEventSetFlags(event, flags)

    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    if down:
        _HELD_MODIFIERS.add(mod)
    else:
        _HELD_MODIFIERS.discard(mod)
    return True


def toggle_modifier(modifier: str) -> bool:
    """Toggle a modifier key on/off (useful for modifier-only hotkeys)."""
    mod = modifier.lower()
    return set_modifier(mod, down=mod not in _HELD_MODIFIERS)


def release_all_modifiers() -> None:
    """Best-effort cleanup for any modifiers held by this process."""
    for mod in list(_HELD_MODIFIERS):
        set_modifier(mod, down=False)


def hold_modifier(modifier: str, hold_ms: int = 450) -> bool:
    """Hold a modifier for a fixed duration, then release."""
    if not set_modifier(modifier, down=True):
        return False
    time.sleep(max(0, hold_ms) / 1000.0)
    set_modifier(modifier, down=False)
    return True


def send_text(text: str) -> None:
    """Type a string of characters."""
    for char in text:
        send_keystroke(char)


def trigger_wispr(mode: str = "cmd_right", hold_ms: int = 450) -> bool:
    """Trigger Wispr using the configured activation mode.

    Modes:
    - cmd_right: send Cmd+Right Arrow (default)
    - lcmd_pulse: hold left command for hold_ms (then release)
    - lcmd_toggle: toggle left command down/up
    - lcmd_hold: hold left command while the controller button is held (handled via press/release events)
    - rcmd_pulse: hold right command for hold_ms (then release)
    - rcmd_toggle: toggle right command down/up
    - rcmd_hold: hold right command while the controller button is held (handled via press/release events)
    """
    mode_norm = mode.strip().lower()
    if mode_norm in ("cmd_right", "cmd+right", "cmd-right"):
        return send_keystroke("right", modifiers=["cmd"])
    if mode_norm in ("lcmd_pulse", "pulse_lcmd", "lcmd_hold", "hold_lcmd"):
        return hold_modifier("lcmd", hold_ms=hold_ms)
    if mode_norm in ("lcmd_toggle", "toggle_lcmd"):
        return toggle_modifier("lcmd")
    if mode_norm in ("rcmd_pulse", "pulse_rcmd", "rcmd_hold", "hold_rcmd"):
        return hold_modifier("rcmd", hold_ms=hold_ms)
    if mode_norm in ("rcmd_toggle", "toggle_rcmd"):
        return toggle_modifier("rcmd")

    log.warning(f"Unknown wispr mode: {mode}, falling back to cmd_right")
    return send_keystroke("right", modifiers=["cmd"])
