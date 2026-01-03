"""Pro Controller haptic feedback control."""
import ctypes
import logging
import time

from cc_controller.haptics.base import BaseHaptics

log = logging.getLogger(__name__)

# HD Rumble neutral state (no vibration)
RUMBLE_NEUTRAL = bytes([0x00, 0x01, 0x40, 0x40])


class ProControllerHaptics(BaseHaptics):
    """Haptic feedback controller for Nintendo Switch Pro Controller."""

    def __init__(self, hidapi_lib: ctypes.CDLL, device_handle):
        self._hidapi = hidapi_lib
        self._handle = device_handle
        self._packet_counter = 0
        self._enable_vibration()

    def _enable_vibration(self) -> None:
        """Enable vibration via subcommand 0x48."""
        # Output report 0x01 with subcommand
        # Format: [0x01, counter, rumble_l(4), rumble_r(4), subcommand, ...]
        report = bytearray(49)
        report[0] = 0x01  # Output report with subcommand
        report[1] = self._next_counter()
        # Neutral rumble data
        report[2:6] = RUMBLE_NEUTRAL
        report[6:10] = RUMBLE_NEUTRAL
        # Subcommand 0x48: Enable vibration
        report[10] = 0x48
        report[11] = 0x01  # Enable

        result = self._hidapi.hid_write(self._handle, bytes(report), len(report))
        if result > 0:
            log.debug("Pro Controller vibration enabled")
        else:
            log.debug("Failed to enable vibration")

    def _next_counter(self) -> int:
        """Get next packet counter (0-15)."""
        counter = self._packet_counter
        self._packet_counter = (self._packet_counter + 1) & 0x0F
        return counter

    def trigger(self, pattern: str) -> None:
        """Trigger a predefined haptic pattern."""
        if not self._handle:
            return

        try:
            if pattern == "confirm":
                self._rumble(120, 160)
                time.sleep(0.08)
                self._rumble(0, 0)
            elif pattern == "error":
                for _ in range(2):
                    self._rumble(200, 255)
                    time.sleep(0.1)
                    self._rumble(0, 0)
                    time.sleep(0.05)
            elif pattern == "connect":
                self._rumble(80, 100)
                time.sleep(0.2)
                self._rumble(0, 0)
        except Exception as e:
            log.debug(f"Haptic error: {e}")

    def rumble(self, left: int, right: int, duration_ms: int = 60) -> None:
        """Send custom rumble with specified motor intensities (0-255)."""
        if not self._handle:
            return

        try:
            self._rumble(left, right)
            time.sleep(duration_ms / 1000.0)
            self._rumble(0, 0)
        except Exception as e:
            log.debug(f"Rumble error: {e}")

    def _rumble(self, left: int, right: int) -> None:
        """Send rumble command using report 0x10."""
        left_data = self._encode_rumble(left)
        right_data = self._encode_rumble(right)

        # Report 0x10: Rumble only (no subcommand)
        report = bytes([0x10, self._next_counter()]) + left_data + right_data
        self._hidapi.hid_write(self._handle, report, len(report))

    def _encode_rumble(self, amplitude: int) -> bytes:
        """Encode amplitude (0-255) to HD rumble format."""
        if amplitude == 0:
            return RUMBLE_NEUTRAL

        # HD Rumble encoding (simplified):
        # Bytes: [HF, HA, LF, LA] where:
        # - HF: High frequency (0x00-0xFC, higher = higher freq)
        # - HA: High amplitude (0x00-0xC8)
        # - LF: Low frequency (0x01-0x7F, lower = lower freq)
        # - LA: Low amplitude (0x40-0x72 range, 0x40 = off)

        # Scale amplitude to usable range
        amp = min(amplitude, 255)

        # High frequency motor (feels like buzz)
        hf = 0x74  # Mid-high frequency
        ha = (amp * 0xC8) // 255  # Scale to max amplitude

        # Low frequency motor (feels like rumble)
        lf = 0x40  # Mid-low frequency
        la = 0x40 + ((amp * 0x32) // 255)  # Scale within LA range

        return bytes([hf, ha, lf, la])
