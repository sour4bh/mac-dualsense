"""macOS keystroke injection via Quartz."""
import logging
import Quartz

log = logging.getLogger(__name__)

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
}

MODIFIERS = {
    "cmd": Quartz.kCGEventFlagMaskCommand,
    "ctrl": Quartz.kCGEventFlagMaskControl,
    "shift": Quartz.kCGEventFlagMaskShift,
    "alt": Quartz.kCGEventFlagMaskAlternate,
    "option": Quartz.kCGEventFlagMaskAlternate,
}


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


def send_text(text: str) -> None:
    """Type a string of characters."""
    for char in text:
        send_keystroke(char)


def trigger_wispr() -> bool:
    """Activate Wispr dictation via Cmd+Right Arrow."""
    return send_keystroke("right", modifiers=["cmd"])
