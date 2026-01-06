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

CONTROLLER_KEYS: dict[str, type[BaseController]] = {
    "dualsense": DualSenseController,
    "pro_controller": ProController,
}


def detect_controller(preferred: str | None = None) -> BaseController | None:
    """Try to connect to any supported controller.

    Returns the first controller that successfully connects,
    or None if no supported controller is found.
    """
    preferred_key = str(preferred or "").strip().lower()
    controller_classes = list(CONTROLLER_CLASSES)
    if preferred_key and preferred_key != "auto":
        preferred_cls = CONTROLLER_KEYS.get(preferred_key)
        if preferred_cls:
            controller_classes = [preferred_cls] + [
                c for c in controller_classes if c != preferred_cls
            ]
        else:
            log.warning(
                f"Unknown controller preference: {preferred!r} (falling back to auto)"
            )

    for controller_cls in controller_classes:
        controller = controller_cls()
        if controller.connect():
            log.info(f"Detected: {controller.name}")
            return controller
        log.debug(f"{controller_cls.__name__} not found")

    log.warning("No supported controller detected")
    return None
