"""Auto-detect connected game controllers."""
import logging

from cc_controller.controllers.base import BaseController
from cc_controller.controllers.dualsense import DualSenseController
from cc_controller.controllers.pro_controller import ProController

log = logging.getLogger(__name__)

CONTROLLER_CLASSES: list[type[BaseController]] = [
    DualSenseController,
    ProController,
]


def detect_controller() -> BaseController | None:
    """Try to connect to any supported controller.

    Returns the first controller that successfully connects,
    or None if no supported controller is found.
    """
    for controller_cls in CONTROLLER_CLASSES:
        controller = controller_cls()
        if controller.connect():
            log.info(f"Detected: {controller.name}")
            return controller
        log.debug(f"{controller_cls.__name__} not found")

    log.warning("No supported controller detected")
    return None
