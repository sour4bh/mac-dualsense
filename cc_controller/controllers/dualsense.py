"""DualSense controller HID communication.

Note: DualSense input reports are not DS4-compatible. In particular, the
button bytes are at offsets 8–10 (USB) and 9–11 (Bluetooth), because bytes
5–7 are trigger values + a counter.
"""

import ctypes
import logging
import subprocess

from cc_controller.controllers.base import BaseController
from cc_controller.haptics.dualsense import DualSenseHaptics

log = logging.getLogger(__name__)

VENDOR_ID = 0x054C
PRODUCT_ID = 0x0CE6


def _is_bluetooth_connected() -> bool:
    """Check if DualSense is connected via Bluetooth using system_profiler."""
    try:
        result = subprocess.run(
            ["system_profiler", "SPBluetoothDataType"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return "DualSense" in result.stdout and "0x0CE6" in result.stdout
    except Exception:
        return False


# Load hidapi C library
try:
    _hidapi_c = ctypes.CDLL("/opt/homebrew/lib/libhidapi.dylib")
    _hidapi_c.hid_open.argtypes = [ctypes.c_ushort, ctypes.c_ushort, ctypes.c_wchar_p]
    _hidapi_c.hid_open.restype = ctypes.c_void_p
    _hidapi_c.hid_write.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    _hidapi_c.hid_write.restype = ctypes.c_int
    _hidapi_c.hid_close.argtypes = [ctypes.c_void_p]
    _hidapi_c.hid_read_timeout.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_int,
    ]
    _hidapi_c.hid_read_timeout.restype = ctypes.c_int
    HIDAPI_AVAILABLE = True
except Exception as e:
    log.warning(f"Could not load hidapi C library: {e}")
    HIDAPI_AVAILABLE = False

DPAD_MASK = 0x0F
DPAD_MAP = {
    0: "dpad_up",
    1: "dpad_up_right",
    2: "dpad_right",
    3: "dpad_down_right",
    4: "dpad_down",
    5: "dpad_down_left",
    6: "dpad_left",
    7: "dpad_up_left",
    8: None,
}

BUTTON_BYTE_FACE = {
    0x10: "square",
    0x20: "cross",
    0x40: "circle",
    0x80: "triangle",
}

BUTTON_BYTE_SHOULDER = {
    0x01: "l1",
    0x02: "r1",
    0x04: "l2",
    0x08: "r2",
    0x10: "share",
    0x20: "options",
    0x40: "l3",
    0x80: "r3",
}

BUTTON_BYTE_SPECIAL = {
    0x01: "ps",
    0x02: "touchpad",
}


class DualSenseController(BaseController):
    """DualSense controller implementation."""

    def __init__(self):
        self._device_handle = None
        self._connected = False
        self._is_bluetooth = False
        self._prev_buttons: set[str] = set()
        # DualSense USB reports are 64 bytes; Bluetooth reports are 78 bytes.
        self._read_buffer = ctypes.create_string_buffer(78)
        self._haptics: DualSenseHaptics | None = None

    @property
    def name(self) -> str:
        return "DualSense"

    @property
    def connection_type(self) -> str | None:
        if not self.connected:
            return None
        return "Bluetooth" if self._is_bluetooth else "USB"

    def connect(self) -> bool:
        """Attempt to connect to DualSense controller."""
        if not HIDAPI_AVAILABLE:
            log.error("hidapi C library not available")
            return False

        try:
            self._device_handle = _hidapi_c.hid_open(VENDOR_ID, PRODUCT_ID, None)
            if not self._device_handle:
                log.debug("DualSense not found")
                return False

            # Prefer detecting by input report length (more reliable than system_profiler).
            probed_len = self._probe_report_length()
            if probed_len == 78:
                self._is_bluetooth = True
            elif probed_len == 64:
                self._is_bluetooth = False
            else:
                self._is_bluetooth = _is_bluetooth_connected()

            conn_type = "Bluetooth" if self._is_bluetooth else "USB"
            log.info(f"DualSense connected via {conn_type}")
            self._connected = True
            self._prev_buttons.clear()
            self._haptics = DualSenseHaptics(
                _hidapi_c, self._device_handle, self._is_bluetooth
            )
            return True
        except Exception as e:
            log.debug(f"DualSense connection failed: {e}")
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
        log.info("DualSense disconnected")

    @property
    def connected(self) -> bool:
        return self._connected and self._device_handle is not None

    def _probe_report_length(self) -> int | None:
        """Best-effort probe of current input report length (USB=64, BT=78)."""
        if not self._device_handle or not HIDAPI_AVAILABLE:
            return None

        # Try a few reads; if nothing arrives quickly, fall back to heuristic.
        for _ in range(10):
            try:
                bytes_read = _hidapi_c.hid_read_timeout(
                    self._device_handle, self._read_buffer, len(self._read_buffer), 50
                )
                if bytes_read > 0:
                    return int(bytes_read)
            except Exception:
                return None
        return None

    def _normalize_input_report(self, data: bytes) -> bytes:
        """Normalize USB/BT input reports to a common layout.

        Bluetooth reports have one extra leading byte; drop it so indices align.
        """
        if len(data) == 78:
            return data[1:]
        return data

    def _parse_buttons(self, data: bytes) -> set[str]:
        """Parse button states from HID report."""
        buttons = set()

        data = self._normalize_input_report(data)
        # DualSense button bytes live at indices 8–10 in the normalized report.
        if len(data) < 11:
            return buttons

        button_state = data[8]
        misc = data[9]
        misc2 = data[10]

        dpad = button_state & DPAD_MASK
        dpad_btn = DPAD_MAP.get(dpad)
        if dpad_btn:
            if "up" in dpad_btn:
                buttons.add("dpad_up")
            if "down" in dpad_btn:
                buttons.add("dpad_down")
            if "left" in dpad_btn:
                buttons.add("dpad_left")
            if "right" in dpad_btn:
                buttons.add("dpad_right")

        for mask, name in BUTTON_BYTE_FACE.items():
            if button_state & mask:
                buttons.add(name)

        for mask, name in BUTTON_BYTE_SHOULDER.items():
            if misc & mask:
                buttons.add(name)

        for mask, name in BUTTON_BYTE_SPECIAL.items():
            if misc2 & mask:
                buttons.add(name)

        return buttons

    def get_pressed(self) -> list[str]:
        """Get list of buttons just pressed (edge detection)."""
        pressed, _ = self.get_events()
        return pressed

    def get_events(self) -> tuple[list[str], list[str]]:
        """Get (pressed, released) button events (edge detection)."""
        if not self.connected or not HIDAPI_AVAILABLE:
            return ([], [])

        try:
            bytes_read = _hidapi_c.hid_read_timeout(
                self._device_handle, self._read_buffer, len(self._read_buffer), 10
            )
            if bytes_read <= 0:
                return ([], [])

            data = self._read_buffer.raw[:bytes_read]
            current = self._parse_buttons(data)
            pressed = list(current - self._prev_buttons)
            released = list(self._prev_buttons - current)
            self._prev_buttons = current
            return (pressed, released)
        except Exception as e:
            log.warning(f"Read error: {e}")
            self._connected = False
            return ([], [])

    def trigger_haptic(self, pattern: str) -> None:
        """Trigger haptic feedback pattern."""
        if self._haptics:
            self._haptics.trigger(pattern)
