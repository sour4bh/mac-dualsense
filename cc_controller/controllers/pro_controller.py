"""Nintendo Switch Pro Controller HID communication."""
import ctypes
import logging

from cc_controller.controllers.base import BaseController
from cc_controller.haptics.pro_controller import ProControllerHaptics

log = logging.getLogger(__name__)

VENDOR_ID = 0x057E
PRODUCT_ID = 0x2009

# Load hidapi C library
try:
    _hidapi_c = ctypes.CDLL("/opt/homebrew/lib/libhidapi.dylib")
    _hidapi_c.hid_open.argtypes = [ctypes.c_ushort, ctypes.c_ushort, ctypes.c_wchar_p]
    _hidapi_c.hid_open.restype = ctypes.c_void_p
    _hidapi_c.hid_write.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    _hidapi_c.hid_write.restype = ctypes.c_int
    _hidapi_c.hid_close.argtypes = [ctypes.c_void_p]
    _hidapi_c.hid_read_timeout.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
    _hidapi_c.hid_read_timeout.restype = ctypes.c_int
    HIDAPI_AVAILABLE = True
except Exception as e:
    log.warning(f"Could not load hidapi C library: {e}")
    HIDAPI_AVAILABLE = False

# Pro Controller button byte 3 (face buttons + shoulder)
# Maps HID button to canonical name (PlayStation-style by position)
BUTTON_BYTE_3 = {
    0x01: "square",    # Y button (left position)
    0x02: "triangle",  # X button (top position)
    0x04: "cross",     # B button (bottom position)
    0x08: "circle",    # A button (right position)
    0x40: "r1",        # R button
    0x80: "r2",        # ZR button
}

# Pro Controller button byte 4 (system buttons)
BUTTON_BYTE_4 = {
    0x01: "share",     # Minus button
    0x02: "options",   # Plus button
    0x04: "r3",        # RStick press
    0x08: "l3",        # LStick press
    0x10: "ps",        # Home button
    0x20: "touchpad",  # Capture button (mapped to touchpad for consistency)
}

# Pro Controller button byte 5 (dpad + L shoulder)
BUTTON_BYTE_5_DPAD = {
    0x01: "dpad_down",
    0x02: "dpad_up",
    0x04: "dpad_right",
    0x08: "dpad_left",
}

BUTTON_BYTE_5_SHOULDER = {
    0x40: "l1",        # L button
    0x80: "l2",        # ZL button
}


class ProController(BaseController):
    """Nintendo Switch Pro Controller implementation."""

    def __init__(self):
        self._device_handle = None
        self._connected = False
        self._prev_buttons: set[str] = set()
        self._read_buffer = ctypes.create_string_buffer(64)
        self._haptics: ProControllerHaptics | None = None

    @property
    def name(self) -> str:
        return "Pro Controller"

    def connect(self) -> bool:
        """Attempt to connect to Pro Controller."""
        if not HIDAPI_AVAILABLE:
            log.error("hidapi C library not available")
            return False

        try:
            self._device_handle = _hidapi_c.hid_open(VENDOR_ID, PRODUCT_ID, None)
            if not self._device_handle:
                log.debug("Pro Controller not found")
                return False

            log.info("Pro Controller connected")
            self._connected = True
            self._haptics = ProControllerHaptics(_hidapi_c, self._device_handle)
            return True
        except Exception as e:
            log.debug(f"Pro Controller connection failed: {e}")
            self._device_handle = None
            self._connected = False
            return False

    def disconnect(self) -> None:
        """Disconnect from controller."""
        if self._device_handle and HIDAPI_AVAILABLE:
            try:
                _hidapi_c.hid_close(self._device_handle)
            except Exception:
                pass
            self._device_handle = None
        self._connected = False
        self._haptics = None
        log.info("Pro Controller disconnected")

    @property
    def connected(self) -> bool:
        return self._connected and self._device_handle is not None

    def _parse_buttons(self, data: bytes) -> set[str]:
        """Parse button states from HID report."""
        buttons = set()

        if len(data) < 6:
            return buttons

        # Standard input report format
        # Byte 3: face buttons + R shoulder
        for mask, name in BUTTON_BYTE_3.items():
            if data[3] & mask:
                buttons.add(name)

        # Byte 4: system buttons
        for mask, name in BUTTON_BYTE_4.items():
            if data[4] & mask:
                buttons.add(name)

        # Byte 5: dpad + L shoulder
        for mask, name in BUTTON_BYTE_5_DPAD.items():
            if data[5] & mask:
                buttons.add(name)
        for mask, name in BUTTON_BYTE_5_SHOULDER.items():
            if data[5] & mask:
                buttons.add(name)

        return buttons

    def get_pressed(self) -> list[str]:
        """Get list of buttons just pressed (edge detection)."""
        if not self.connected or not HIDAPI_AVAILABLE:
            return []

        try:
            bytes_read = _hidapi_c.hid_read_timeout(
                self._device_handle, self._read_buffer, 64, 10
            )
            if bytes_read <= 0:
                return []

            data = self._read_buffer.raw[:bytes_read]
            current = self._parse_buttons(data)
            pressed = list(current - self._prev_buttons)
            self._prev_buttons = current
            return pressed
        except Exception as e:
            log.warning(f"Read error: {e}")
            self._connected = False
            return []

    def trigger_haptic(self, pattern: str) -> None:
        """Trigger haptic feedback pattern."""
        if self._haptics:
            self._haptics.trigger(pattern)
