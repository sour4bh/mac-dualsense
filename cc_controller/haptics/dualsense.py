"""DualSense haptic feedback control."""
import binascii
import ctypes
import logging
import struct
import time

from cc_controller.haptics.base import BaseHaptics

log = logging.getLogger(__name__)


def _crc32_dualsense(data: bytes) -> int:
    """Calculate CRC32 for DualSense Bluetooth reports (seed 0xA2)."""
    return binascii.crc32(bytes([0xA2]) + data) & 0xFFFFFFFF


class DualSenseHaptics(BaseHaptics):
    """Haptic feedback controller for DualSense."""

    def __init__(self, hidapi_lib: ctypes.CDLL, device_handle, is_bluetooth: bool):
        self._hidapi = hidapi_lib
        self._handle = device_handle
        self._is_bluetooth = is_bluetooth

    def trigger(self, pattern: str) -> None:
        """Trigger a predefined haptic pattern."""
        if not self._handle:
            return

        try:
            if self._is_bluetooth:
                self._send_bt(pattern)
            else:
                self._send_usb(pattern)
        except Exception as e:
            log.debug(f"Haptic error: {e}")

    def rumble(self, left: int, right: int, duration_ms: int = 60) -> None:
        """Send custom rumble with specified motor intensities (0-255)."""
        if not self._handle:
            return

        try:
            if self._is_bluetooth:
                self._rumble_bt(right, left)
            else:
                self._rumble_usb(right, left)
            time.sleep(duration_ms / 1000.0)
            self._stop()
        except Exception as e:
            log.debug(f"Rumble error: {e}")

    def _stop(self) -> None:
        """Stop all rumble motors."""
        if self._is_bluetooth:
            self._rumble_bt(0, 0)
        else:
            self._rumble_usb(0, 0)

    def _rumble_usb(self, right: int, left: int) -> None:
        """Send USB rumble report."""
        report = bytes([0x02, 0xFF, 0xF7, 0x00, right, left]) + bytes(58)
        self._hidapi.hid_write(self._handle, report, 64)

    def _rumble_bt(self, right: int, left: int) -> None:
        """Send Bluetooth rumble report with CRC."""
        report = bytearray(78)
        report[0] = 0x31
        report[1] = 0x02
        report[2] = 0xFF
        report[3] = 0xF7
        report[4] = right
        report[5] = left
        crc = _crc32_dualsense(bytes(report[:-4]))
        report[-4:] = struct.pack("<I", crc)
        self._hidapi.hid_write(self._handle, bytes(report), 78)

    def _send_usb(self, pattern: str) -> None:
        """Execute USB haptic pattern."""
        if pattern == "confirm":
            self._rumble_usb(100, 150)
            time.sleep(0.06)
            self._rumble_usb(0, 0)
        elif pattern == "error":
            for _ in range(2):
                self._rumble_usb(200, 255)
                time.sleep(0.08)
                self._rumble_usb(0, 0)
                time.sleep(0.04)
        elif pattern == "connect":
            self._rumble_usb(50, 80)
            time.sleep(0.15)
            self._rumble_usb(0, 0)

    def _send_bt(self, pattern: str) -> None:
        """Execute Bluetooth haptic pattern."""
        if pattern == "confirm":
            self._rumble_bt(100, 150)
            time.sleep(0.06)
            self._rumble_bt(0, 0)
        elif pattern == "error":
            for _ in range(2):
                self._rumble_bt(200, 255)
                time.sleep(0.08)
                self._rumble_bt(0, 0)
                time.sleep(0.04)
        elif pattern == "connect":
            self._rumble_bt(50, 80)
            time.sleep(0.15)
            self._rumble_bt(0, 0)
