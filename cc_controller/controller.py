"""DualSense controller HID communication."""
import ctypes
import logging
import subprocess
import time
from typing import Callable

from cc_controller.haptics import DualSenseHaptics

log = logging.getLogger(__name__)

VENDOR_ID = 0x054c
PRODUCT_ID = 0x0ce6


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
    _hidapi_c.hid_read_timeout.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
    _hidapi_c.hid_read_timeout.restype = ctypes.c_int
    CTYPES_AVAILABLE = True
except Exception as e:
    log.warning(f"Could not load hidapi C library: {e}")
    CTYPES_AVAILABLE = False

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


class DualSenseController:
    """Direct HID communication with DualSense controller."""

    def __init__(self, poll_interval_ms: int = 10):
        self._device_handle = None
        self._connected = False
        self._is_bluetooth = False
        self._poll_interval = poll_interval_ms / 1000.0
        self._prev_buttons: set[str] = set()
        self._read_buffer = ctypes.create_string_buffer(78)
        self._haptics: DualSenseHaptics | None = None

    def connect(self) -> bool:
        """Attempt to connect to DualSense controller."""
        if not CTYPES_AVAILABLE:
            log.error("hidapi C library not available")
            return False

        try:
            self._device_handle = _hidapi_c.hid_open(VENDOR_ID, PRODUCT_ID, None)
            if not self._device_handle:
                log.debug("DualSense not found")
                return False

            # Detect USB vs Bluetooth via system_profiler (macOS abstracts BT as USB HID)
            self._is_bluetooth = _is_bluetooth_connected()
            conn_type = "Bluetooth" if self._is_bluetooth else "USB"
            log.info(f"DualSense connected via {conn_type}")
            self._connected = True
            self._haptics = DualSenseHaptics(_hidapi_c, self._device_handle, self._is_bluetooth)
            return True
        except Exception as e:
            log.debug(f"DualSense connection failed: {e}")
            self._device_handle = None
            self._connected = False
            return False

    def disconnect(self) -> None:
        """Disconnect from controller."""
        if self._device_handle and CTYPES_AVAILABLE:
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
        """Check if controller is connected."""
        return self._connected and self._device_handle is not None

    @property
    def haptics(self) -> DualSenseHaptics | None:
        """Get haptics controller."""
        return self._haptics

    def _parse_buttons(self, data: bytes) -> set[str]:
        """Parse button states from HID report."""
        buttons = set()

        # macOS presents Bluetooth DualSense with USB-style HID reports
        # Always use USB byte offsets for parsing
        if len(data) < 10:
            return buttons
        dpad_byte = 5
        face_byte = 5
        shoulder_byte = 6
        special_byte = 7

        # D-pad
        dpad = data[dpad_byte] & DPAD_MASK
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

        # Face buttons
        for mask, name in BUTTON_BYTE_FACE.items():
            if data[face_byte] & mask:
                buttons.add(name)

        # Shoulder buttons
        for mask, name in BUTTON_BYTE_SHOULDER.items():
            if data[shoulder_byte] & mask:
                buttons.add(name)

        # Special buttons
        for mask, name in BUTTON_BYTE_SPECIAL.items():
            if data[special_byte] & mask:
                buttons.add(name)

        return buttons

    def get_pressed(self) -> list[str]:
        """Get list of buttons that were just pressed (edge detection)."""
        if not self.connected or not CTYPES_AVAILABLE:
            return []

        try:
            bytes_read = _hidapi_c.hid_read_timeout(
                self._device_handle, self._read_buffer, 78, 10
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

    def poll_loop(self, on_press: Callable[[str], None], running: Callable[[], bool]) -> None:
        """Main polling loop with auto-reconnect."""
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
                time.sleep(self._poll_interval)
            except Exception as e:
                log.warning(f"Controller error: {e}")
                self._connected = False

    def trigger_haptic(self, pattern: str) -> None:
        """Trigger haptic feedback pattern."""
        if self._haptics:
            self._haptics.trigger(pattern)
