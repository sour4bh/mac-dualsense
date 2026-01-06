"""Menu-bar UI + Preferences window (PyObjC/AppKit)."""

from __future__ import annotations

import copy
import logging
import threading
from collections import deque
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import objc
from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSApplicationActivationPolicyRegular,
    NSBackingStoreBuffered,
    NSBezelStyleRounded,
    NSBezelStyleTexturedRounded,
    NSButton,
    NSColor,
    NSFont,
    NSFontWeightRegular,
    NSFontWeightSemibold,
    NSImage,
    NSImageOnly,
    NSImageSymbolConfiguration,
    NSImageSymbolScaleSmall,
    NSImageView,
    NSMakeRect,
    NSMenu,
    NSMenuItem,
    NSNoBorder,
    NSOutlineView,
    NSPopUpButton,
    NSPopUpButtonCell,
    NSRunningApplication,
    NSScrollView,
    NSSplitView,
    NSSplitViewDividerStyleThin,
    NSStatusBar,
    NSTableCellView,
    NSTableColumn,
    NSTableViewSelectionHighlightStyleSourceList,
    NSTableViewRowSizeStyleMedium,
    NSTableViewStyleInset,
    NSTableViewStyleSourceList,
    NSTableView,
    NSTextField,
    NSImageScaleProportionallyDown,
    NSLineBreakByTruncatingTail,
    NSVariableStatusItemLength,
    NSVisualEffectBlendingModeBehindWindow,
    NSVisualEffectMaterialHeaderView,
    NSVisualEffectMaterialSidebar,
    NSVisualEffectMaterialContentBackground,
    NSVisualEffectMaterialUnderWindowBackground,
    NSVisualEffectStateFollowsWindowActiveState,
    NSVisualEffectView,
    NSView,
    NSViewHeightSizable,
    NSViewMaxYMargin,
    NSViewMinXMargin,
    NSViewMinYMargin,
    NSViewWidthSizable,
    NSWindow,
    NSWindowController,
    NSWindowTitleHidden,
    NSWindowToolbarStyleUnifiedCompact,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
    NSWindowWillCloseNotification,
    NSEventModifierFlagCommand,
    NSEventModifierFlagShift,
)
from Foundation import NSIndexSet, NSObject, NSNotificationCenter, NSTimer

from cc_controller.app_focus import APP_CONTEXTS
from cc_controller.config import load_config, save_config
from cc_controller.daemon import CCControllerDaemon, configure_logging
from cc_controller.keyboard import check_accessibility

log = logging.getLogger(__name__)


class DaemonManager:
    def __init__(self):
        self._daemon: CCControllerDaemon | None = None
        self._thread: threading.Thread | None = None
        self._event_lock = threading.Lock()
        self._events: deque[dict] = deque(maxlen=400)

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self) -> None:
        if self.running:
            return
        if not check_accessibility():
            raise PermissionError(
                "Enable CC Controller in System Settings → Privacy & Security → Accessibility, then try again."
            )

        self._daemon = CCControllerDaemon(event_callback=self._enqueue_event)
        self._thread = threading.Thread(
            target=self._run, name="cc-controller-daemon", daemon=True
        )
        self._thread.start()

    def _enqueue_event(self, event: dict) -> None:
        with self._event_lock:
            self._events.append(event)

    def drain_events(self, max_events: int = 100) -> list[dict]:
        drained: list[dict] = []
        with self._event_lock:
            while self._events and len(drained) < max_events:
                drained.append(self._events.popleft())
        return drained

    def controller_snapshot(self) -> dict | None:
        daemon = self._daemon
        if daemon is None:
            return None
        try:
            controller = daemon.controller
            return {
                "name": controller.name,
                "connection": controller.connection_type,
                "connected": bool(controller.connected),
            }
        except Exception:
            return None

    def _run(self) -> None:
        assert self._daemon is not None
        try:
            self._daemon.start(install_signal_handlers=False)
        except Exception:
            # Logging is handled by the daemon; keep UI responsive even on failures.
            pass

    def stop(self) -> None:
        if not self.running:
            self._daemon = None
            self._thread = None
            return

        assert self._thread is not None
        try:
            if self._daemon is not None:
                self._daemon.stop()
            self._thread.join(timeout=2)
        except Exception:
            pass
        finally:
            self._daemon = None
            self._thread = None

    def restart(self) -> None:
        was_running = self.running
        self.stop()
        if was_running:
            self.start()


class ConfigStore:
    def __init__(self):
        self._config: dict = load_config()

    def reload(self) -> None:
        self._config = load_config(Path(self.path))

    @property
    def path(self) -> str:
        return str(self._config.get("_meta", {}).get("path", ""))

    @property
    def active_profile(self) -> str:
        profiles = self._config.get("profiles", {})
        return profiles.get("active", "default")

    def controller_preference(self) -> str:
        settings = self._config.setdefault("settings", {})
        controller = (
            settings.get("controller", {}) if isinstance(settings, dict) else {}
        )
        preferred = (
            controller.get("preferred", "auto")
            if isinstance(controller, dict)
            else "auto"
        )
        preferred_norm = str(preferred).strip().lower() or "auto"
        if preferred_norm not in ("auto", "dualsense", "pro_controller"):
            return "auto"
        return preferred_norm

    def set_controller_preference(self, preferred: str) -> None:
        preferred_norm = str(preferred).strip().lower() or "auto"
        if preferred_norm not in ("auto", "dualsense", "pro_controller"):
            preferred_norm = "auto"
        settings = self._config.setdefault("settings", {})
        if not isinstance(settings, dict):
            settings = {}
            self._config["settings"] = settings
        controller = settings.setdefault("controller", {})
        if not isinstance(controller, dict):
            controller = {}
            settings["controller"] = controller
        controller["preferred"] = preferred_norm

    def set_active_profile(self, name: str) -> None:
        profiles = self._config.setdefault("profiles", {})
        profiles["active"] = name

    def profile_names(self) -> list[str]:
        profiles = self._config.get("profiles", {})
        items = profiles.get("items", {})
        return sorted(items.keys())

    def _profiles_items(self) -> dict:
        profiles = self._config.setdefault("profiles", {})
        items = profiles.setdefault("items", {})
        return items

    def add_profile(self, name: str, clone_from: str | None = None) -> None:
        name = name.strip()
        if not name:
            raise ValueError("Profile name cannot be empty")

        items = self._profiles_items()
        if name in items:
            raise ValueError("Profile already exists")

        source = clone_from or self.active_profile
        src_mappings = (
            items.get(source, {}).get("mappings", {})
            if isinstance(items.get(source), dict)
            else {}
        )
        items[name] = {"mappings": copy.deepcopy(src_mappings)}

    def delete_profile(self, name: str) -> None:
        items = self._profiles_items()
        if name not in items:
            return
        if len(items) <= 1:
            raise ValueError("Cannot delete the last profile")
        del items[name]
        if self.active_profile == name:
            self.set_active_profile(next(iter(items.keys())))

    def rename_profile(self, old: str, new: str) -> None:
        new = new.strip()
        if not new:
            raise ValueError("Profile name cannot be empty")
        items = self._profiles_items()
        if old not in items:
            raise ValueError("Profile not found")
        if new in items:
            raise ValueError("Profile already exists")
        items[new] = items.pop(old)
        if self.active_profile == old:
            self.set_active_profile(new)

    def context_names(self) -> list[str]:
        items = self._profiles_items()
        profile = items.get(self.active_profile, {})
        mappings = profile.get("mappings", {}) if isinstance(profile, dict) else {}
        contexts = set(mappings.keys()) if isinstance(mappings, dict) else set()
        contexts.add("default")
        contexts.update(APP_CONTEXTS.values())
        return ["default"] + sorted(c for c in contexts if c != "default")

    def get_context_mapping(self, context: str) -> dict:
        items = self._profiles_items()
        profile = items.setdefault(self.active_profile, {"mappings": {"default": {}}})
        mappings = profile.setdefault("mappings", {})
        ctx = mappings.setdefault(context, {})
        return ctx

    def set_action(self, context: str, button: str, action: dict) -> None:
        ctx = self.get_context_mapping(context)
        ctx[button] = action

    def delete_action(self, context: str, button: str) -> None:
        ctx = self.get_context_mapping(context)
        ctx.pop(button, None)

    def save(self) -> Path:
        return save_config(self._config)


@dataclass
class MappingRow:
    button: str
    type: str
    key: str
    modifiers: str


@dataclass
class InputEventRow:
    time: str
    state: str
    button: str
    action: str


def _action_to_row(button: str, action: dict) -> MappingRow:
    action_type = str(action.get("type", "noop"))
    key = "" if action_type != "keystroke" else str(action.get("key") or "")
    modifiers = action.get("modifiers") or []
    if isinstance(modifiers, list):
        mod_str = ", ".join(str(m) for m in modifiers)
    else:
        mod_str = ""
    return MappingRow(button=button, type=action_type, key=key, modifiers=mod_str)


def _parse_modifiers(text: str) -> list[str] | None:
    raw = text.strip()
    if not raw:
        return None
    parts = [p.strip() for p in raw.replace("[", "").replace("]", "").split(",")]
    parts = [p for p in parts if p]
    return parts or None


def _symbol_image(name: str, point_size: float = 14.0) -> NSImage | None:
    try:
        img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(name, None)
        if img is None:
            return None
        cfg = NSImageSymbolConfiguration.configurationWithPointSize_weight_scale_(
            point_size, NSFontWeightRegular, NSImageSymbolScaleSmall
        )
        return img.imageWithSymbolConfiguration_(cfg) if cfg else img
    except Exception:
        return None


def _label(text: str, frame, *, weight: float | None = None, color=None) -> NSTextField:
    field = NSTextField.alloc().initWithFrame_(frame)
    field.setStringValue_(text)
    field.setBezeled_(False)
    field.setDrawsBackground_(False)
    field.setEditable_(False)
    field.setSelectable_(False)
    if weight is not None:
        try:
            field.setFont_(
                NSFont.systemFontOfSize_weight_(field.font().pointSize(), weight)
            )
        except Exception:
            pass
    if color is not None:
        try:
            field.setTextColor_(color)
        except Exception:
            pass
    return field


@dataclass
class SidebarItem:
    kind: str  # "profiles", "group", "context"
    label: str
    icon: str | None = None
    context: str | None = None
    children: list["SidebarItem"] | None = None

    def expandable(self) -> bool:
        return bool(self.children)


class PreferencesWindowController(NSWindowController):
    def initWithStore_daemon_(self, store: ConfigStore, daemon: DaemonManager):
        self = objc.super(PreferencesWindowController, self).init()
        if self is None:
            return None

        self._store = store
        self._daemon = daemon
        self._current_section = "profiles"
        self._selected_context = "default"
        self._sidebar_root: list[SidebarItem] = []
        self._rows: list[MappingRow] = []
        self._input_events: list[InputEventRow] = []
        self._pressed_buttons: set[str] = set()
        self._active_controller_name: str | None = None
        self._active_controller_connection: str | None = None
        self._last_pressed_button: str | None = None
        self._event_timer: NSTimer | None = None
        # These are set during UI construction; keep placeholders so AppKit can
        # query delegates while views are still being built.
        self._profiles_table = None
        self._mapping_table = None
        self._controller_events_table = None

        frame = NSMakeRect(0, 0, 900, 600)
        style = (
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable
            | NSWindowStyleMaskResizable
        )
        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame, style, NSBackingStoreBuffered, False
        )
        window.setTitle_("CC Controller Preferences")
        window.setTitleVisibility_(NSWindowTitleHidden)
        window.setTitlebarAppearsTransparent_(True)
        window.setToolbarStyle_(NSWindowToolbarStyleUnifiedCompact)
        window.setMovableByWindowBackground_(True)
        window.center()
        self.setWindow_(window)

        NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
            self, "_onPrefsWindowWillClose:", NSWindowWillCloseNotification, window
        )

        self._build_ui()
        self._start_event_timer()
        self._reload_sidebar()
        self._select_sidebar_target(kind="profiles")
        return self

    def _build_ui(self) -> None:
        window = self.window()
        bounds = window.contentView().bounds()

        root = NSVisualEffectView.alloc().initWithFrame_(bounds)
        root.setMaterial_(NSVisualEffectMaterialUnderWindowBackground)
        root.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        root.setState_(NSVisualEffectStateFollowsWindowActiveState)
        root.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        window.setContentView_(root)
        content = root

        sidebar_width = 260
        split = NSSplitView.alloc().initWithFrame_(bounds)
        split.setVertical_(True)
        split.setDividerStyle_(NSSplitViewDividerStyleThin)
        split.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        content.addSubview_(split)
        self._split_view = split

        sidebar = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, 0, sidebar_width, bounds.size.height)
        )
        sidebar.setMaterial_(NSVisualEffectMaterialSidebar)
        sidebar.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        sidebar.setState_(NSVisualEffectStateFollowsWindowActiveState)
        sidebar.setEmphasized_(True)
        sidebar.setAutoresizingMask_(NSViewHeightSizable)
        split.addSubview_(sidebar)
        self._sidebar_view = sidebar

        detail = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(
                sidebar_width, 0, bounds.size.width - sidebar_width, bounds.size.height
            )
        )
        detail.setMaterial_(NSVisualEffectMaterialContentBackground)
        detail.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        detail.setState_(NSVisualEffectStateFollowsWindowActiveState)
        detail.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        split.addSubview_(detail)
        self._detail_view = detail

        # Sidebar (source list)
        sidebar_scroll = NSScrollView.alloc().initWithFrame_(sidebar.bounds())
        sidebar_scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        sidebar_scroll.setBorderType_(NSNoBorder)
        sidebar_scroll.setHasVerticalScroller_(True)
        sidebar_scroll.setAutohidesScrollers_(True)
        sidebar_scroll.setDrawsBackground_(False)

        outline = NSOutlineView.alloc().initWithFrame_(sidebar_scroll.bounds())
        self._sidebar_outline = outline
        col = NSTableColumn.alloc().initWithIdentifier_("sidebar")
        col.setWidth_(sidebar_width)
        outline.addTableColumn_(col)
        outline.setOutlineTableColumn_(col)
        outline.setHeaderView_(None)
        outline.setDataSource_(self)
        outline.setDelegate_(self)
        outline.setStyle_(NSTableViewStyleSourceList)
        outline.setSelectionHighlightStyle_(
            NSTableViewSelectionHighlightStyleSourceList
        )
        outline.setRowSizeStyle_(NSTableViewRowSizeStyleMedium)
        outline.setIndentationPerLevel_(14)
        outline.setFloatsGroupRows_(True)
        outline.setUsesAlternatingRowBackgroundColors_(False)
        outline.setBackgroundColor_(NSColor.clearColor())
        sidebar_scroll.setDocumentView_(outline)
        sidebar.addSubview_(sidebar_scroll)

        # Profiles view (detail)
        self._profiles_view = self._build_profiles_view(detail.bounds())
        self._profiles_view.setAutoresizingMask_(
            NSViewWidthSizable | NSViewHeightSizable
        )
        detail.addSubview_(self._profiles_view)

        # Controller view (detail)
        self._controller_view = self._build_controller_view(detail.bounds())
        self._controller_view.setAutoresizingMask_(
            NSViewWidthSizable | NSViewHeightSizable
        )
        self._controller_view.setHidden_(True)
        detail.addSubview_(self._controller_view)

        # Keybinds view (detail)
        self._keybinds_view = self._build_keybinds_view(detail.bounds())
        self._keybinds_view.setAutoresizingMask_(
            NSViewWidthSizable | NSViewHeightSizable
        )
        self._keybinds_view.setHidden_(True)
        detail.addSubview_(self._keybinds_view)

    def _build_profiles_view(self, frame) -> NSView:
        view = NSView.alloc().initWithFrame_(frame)

        header_h = 72
        footer_h = 52
        pad = 24

        header = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, frame.size.height - header_h, frame.size.width, header_h)
        )
        header.setMaterial_(NSVisualEffectMaterialHeaderView)
        header.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        header.setState_(NSVisualEffectStateFollowsWindowActiveState)
        header.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
        view.addSubview_(header)

        title = _label("Profiles", NSMakeRect(pad, header_h - 48, 300, 28))
        title.setFont_(NSFont.systemFontOfSize_weight_(24, NSFontWeightSemibold))
        header.addSubview_(title)

        save_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(frame.size.width - pad - 90, header_h - 52, 90, 30)
        )
        save_btn.setTitle_("Save")
        save_btn.setBezelStyle_(NSBezelStyleRounded)
        save_btn.setTarget_(self)
        save_btn.setAction_("saveConfig:")
        save_btn.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        header.addSubview_(save_btn)

        popup_w = 200
        popup_x = frame.size.width - pad - 90 - 12 - popup_w
        active_popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
            NSMakeRect(popup_x, header_h - 52, popup_w, 28), False
        )
        active_popup.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        active_popup.setTarget_(self)
        active_popup.setAction_("activeProfileChanged:")
        active_popup.setToolTip_("Active profile")
        header.addSubview_(active_popup)
        self._profiles_active_popup = active_popup

        scroll = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(
                pad,
                footer_h + 12,
                frame.size.width - 2 * pad,
                frame.size.height - header_h - footer_h - 24,
            )
        )
        scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        scroll.setBorderType_(NSNoBorder)
        scroll.setHasVerticalScroller_(True)
        scroll.setAutohidesScrollers_(True)
        scroll.setDrawsBackground_(False)

        self._profiles_table = NSTableView.alloc().initWithFrame_(scroll.bounds())
        self._profiles_table.setHeaderView_(None)
        self._profiles_table.setDataSource_(self)
        self._profiles_table.setDelegate_(self)
        self._profiles_table.setStyle_(NSTableViewStyleInset)
        self._profiles_table.setSelectionHighlightStyle_(
            NSTableViewSelectionHighlightStyleSourceList
        )
        self._profiles_table.setRowHeight_(30)
        self._profiles_table.setUsesAlternatingRowBackgroundColors_(False)
        self._profiles_table.setBackgroundColor_(NSColor.clearColor())
        self._profiles_table.setTarget_(self)
        self._profiles_table.setDoubleAction_("setActiveProfile:")

        col = NSTableColumn.alloc().initWithIdentifier_("profile")
        col.setWidth_(frame.size.width - 2 * pad)
        self._profiles_table.addTableColumn_(col)

        scroll.setDocumentView_(self._profiles_table)
        view.addSubview_(scroll)

        footer = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, 0, frame.size.width, footer_h)
        )
        footer.setMaterial_(NSVisualEffectMaterialUnderWindowBackground)
        footer.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        footer.setState_(NSVisualEffectStateFollowsWindowActiveState)
        footer.setAutoresizingMask_(NSViewWidthSizable | NSViewMaxYMargin)
        view.addSubview_(footer)

        btn_y = int((footer_h - 28) / 2)
        x = pad
        for symbol, tooltip, action in [
            ("plus", "Add profile…", "addProfile:"),
            ("doc.on.doc", "Duplicate profile…", "duplicateProfile:"),
            ("pencil", "Rename profile…", "renameProfile:"),
            ("trash", "Delete profile", "deleteProfile:"),
        ]:
            btn = NSButton.alloc().initWithFrame_(NSMakeRect(x, btn_y, 34, 28))
            btn.setBezelStyle_(NSBezelStyleTexturedRounded)
            img = _symbol_image(symbol, 13.0)
            if img is not None:
                btn.setImage_(img)
                btn.setImagePosition_(NSImageOnly)
                btn.setTitle_("")
            else:
                btn.setTitle_(tooltip)
            btn.setToolTip_(tooltip)
            btn.setTarget_(self)
            btn.setAction_(action)
            footer.addSubview_(btn)
            x += 40

        return view

    def _build_controller_view(self, frame) -> NSView:
        view = NSView.alloc().initWithFrame_(frame)

        header_h = 72
        pad = 24

        header = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, frame.size.height - header_h, frame.size.width, header_h)
        )
        header.setMaterial_(NSVisualEffectMaterialHeaderView)
        header.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        header.setState_(NSVisualEffectStateFollowsWindowActiveState)
        header.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
        view.addSubview_(header)

        title = _label("Controller", NSMakeRect(pad, header_h - 48, 300, 28))
        title.setFont_(NSFont.systemFontOfSize_weight_(24, NSFontWeightSemibold))
        header.addSubview_(title)

        save_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(frame.size.width - pad - 90, header_h - 52, 90, 30)
        )
        save_btn.setTitle_("Save")
        save_btn.setBezelStyle_(NSBezelStyleRounded)
        save_btn.setTarget_(self)
        save_btn.setAction_("saveConfig:")
        save_btn.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        header.addSubview_(save_btn)

        info_h = 168
        info_y = frame.size.height - header_h - pad - info_h
        info = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(pad, info_y, frame.size.width - 2 * pad, info_h)
        )
        info.setMaterial_(NSVisualEffectMaterialUnderWindowBackground)
        info.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        info.setState_(NSVisualEffectStateFollowsWindowActiveState)
        info.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
        view.addSubview_(info)

        left_w = 160
        right_w = 240
        inner_pad = 16
        row_h = 28
        row_gap = 8
        row1_y = info_h - inner_pad - row_h
        row2_y = row1_y - row_h - row_gap
        row3_y = row2_y - row_h - row_gap
        row4_y = row3_y - row_h - row_gap

        label_pref = _label(
            "Preferred controller",
            NSMakeRect(inner_pad, row1_y + 6, left_w, 18),
            color=NSColor.secondaryLabelColor(),
        )
        info.addSubview_(label_pref)

        pref_popup_x = info.bounds().size.width - inner_pad - right_w
        pref_popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
            NSMakeRect(pref_popup_x, row1_y, right_w, 28), False
        )
        pref_popup.setAutoresizingMask_(NSViewMinXMargin)
        for title_text, key in [
            ("Auto", "auto"),
            ("DualSense", "dualsense"),
            ("Pro Controller", "pro_controller"),
        ]:
            pref_popup.addItemWithTitle_(title_text)
            item = pref_popup.itemWithTitle_(title_text)
            if item is not None:
                item.setRepresentedObject_(key)
        pref_popup.setTarget_(self)
        pref_popup.setAction_("controllerPreferenceChanged:")
        info.addSubview_(pref_popup)
        self._controller_pref_popup = pref_popup

        label_daemon = _label(
            "Daemon",
            NSMakeRect(inner_pad, row2_y + 6, left_w, 18),
            color=NSColor.secondaryLabelColor(),
        )
        info.addSubview_(label_daemon)

        daemon_value = _label(
            "Stopped", NSMakeRect(inner_pad + left_w, row2_y + 6, 280, 18)
        )
        daemon_value.setAutoresizingMask_(NSViewWidthSizable)
        info.addSubview_(daemon_value)
        self._controller_daemon_value = daemon_value

        toggle_w = 90
        toggle_x = info.bounds().size.width - inner_pad - toggle_w
        toggle_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(toggle_x, row2_y - 1, toggle_w, 30)
        )
        toggle_btn.setTitle_("Start")
        toggle_btn.setBezelStyle_(NSBezelStyleRounded)
        toggle_btn.setTarget_(self)
        toggle_btn.setAction_("toggleDaemon:")
        toggle_btn.setAutoresizingMask_(NSViewMinXMargin)
        info.addSubview_(toggle_btn)
        self._controller_toggle_btn = toggle_btn

        label_active = _label(
            "Active controller",
            NSMakeRect(inner_pad, row3_y + 6, left_w, 18),
            color=NSColor.secondaryLabelColor(),
        )
        info.addSubview_(label_active)

        active_value = _label("—", NSMakeRect(inner_pad + left_w, row3_y + 6, 500, 18))
        active_value.setAutoresizingMask_(NSViewWidthSizable)
        info.addSubview_(active_value)
        self._controller_active_value = active_value

        label_input = _label(
            "Live input",
            NSMakeRect(inner_pad, row4_y + 6, left_w, 18),
            color=NSColor.secondaryLabelColor(),
        )
        info.addSubview_(label_input)

        input_value = _label("—", NSMakeRect(inner_pad + left_w, row4_y + 6, 500, 18))
        input_value.setAutoresizingMask_(NSViewWidthSizable)
        info.addSubview_(input_value)
        self._controller_input_value = input_value

        events_y = pad
        events_h = max(100, info_y - events_y - 16)
        events_scroll = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(pad, events_y, frame.size.width - 2 * pad, events_h)
        )
        events_scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        events_scroll.setBorderType_(NSNoBorder)
        events_scroll.setHasVerticalScroller_(True)
        events_scroll.setAutohidesScrollers_(True)
        events_scroll.setDrawsBackground_(False)

        events_table = NSTableView.alloc().initWithFrame_(events_scroll.bounds())
        events_table.setHeaderView_(None)
        events_table.setDataSource_(self)
        events_table.setDelegate_(self)
        events_table.setStyle_(NSTableViewStyleInset)
        events_table.setUsesAlternatingRowBackgroundColors_(False)
        events_table.setBackgroundColor_(NSColor.clearColor())
        events_table.setRowHeight_(26)

        for ident, width in [
            ("time", 90),
            ("state", 90),
            ("button", 160),
            ("action", 400),
        ]:
            col = NSTableColumn.alloc().initWithIdentifier_(ident)
            col.setWidth_(width)
            events_table.addTableColumn_(col)

        events_scroll.setDocumentView_(events_table)
        view.addSubview_(events_scroll)
        self._controller_events_table = events_table

        self._refresh_controller_view()
        return view

    def _build_keybinds_view(self, frame) -> NSView:
        view = NSView.alloc().initWithFrame_(frame)

        header_h = 72
        footer_h = 52
        pad = 24

        header = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, frame.size.height - header_h, frame.size.width, header_h)
        )
        header.setMaterial_(NSVisualEffectMaterialHeaderView)
        header.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        header.setState_(NSVisualEffectStateFollowsWindowActiveState)
        header.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
        view.addSubview_(header)

        title = _label("Keybinds", NSMakeRect(pad, header_h - 48, 300, 28))
        title.setFont_(NSFont.systemFontOfSize_weight_(24, NSFontWeightSemibold))
        header.addSubview_(title)

        self._keybinds_subtitle = _label(
            "",
            NSMakeRect(pad, header_h - 68, frame.size.width - 2 * pad, 18),
            color=NSColor.secondaryLabelColor(),
        )
        self._keybinds_subtitle.setAutoresizingMask_(
            NSViewWidthSizable | NSViewMinYMargin
        )
        header.addSubview_(self._keybinds_subtitle)

        save_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(frame.size.width - pad - 90, header_h - 52, 90, 30)
        )
        save_btn.setTitle_("Save")
        save_btn.setBezelStyle_(NSBezelStyleRounded)
        save_btn.setTarget_(self)
        save_btn.setAction_("saveConfig:")
        save_btn.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        header.addSubview_(save_btn)

        popup_w = 200
        popup_x = frame.size.width - pad - 90 - 12 - popup_w
        self._keybinds_profile_popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
            NSMakeRect(popup_x, header_h - 52, popup_w, 28), False
        )
        self._keybinds_profile_popup.setAutoresizingMask_(
            NSViewMinXMargin | NSViewMinYMargin
        )
        self._keybinds_profile_popup.setTarget_(self)
        self._keybinds_profile_popup.setAction_("activeProfileChanged:")
        self._keybinds_profile_popup.setToolTip_("Active profile")
        header.addSubview_(self._keybinds_profile_popup)

        scroll = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(
                pad,
                footer_h + 12,
                frame.size.width - 2 * pad,
                frame.size.height - header_h - footer_h - 24,
            )
        )
        scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        scroll.setBorderType_(NSNoBorder)
        scroll.setHasVerticalScroller_(True)
        scroll.setAutohidesScrollers_(True)
        scroll.setDrawsBackground_(False)

        self._mapping_table = NSTableView.alloc().initWithFrame_(scroll.bounds())
        self._mapping_table.setDataSource_(self)
        self._mapping_table.setDelegate_(self)
        self._mapping_table.setHeaderView_(None)
        self._mapping_table.setStyle_(NSTableViewStyleInset)
        self._mapping_table.setSelectionHighlightStyle_(
            NSTableViewSelectionHighlightStyleSourceList
        )
        self._mapping_table.setRowHeight_(30)
        self._mapping_table.setUsesAlternatingRowBackgroundColors_(False)
        self._mapping_table.setBackgroundColor_(NSColor.clearColor())

        col_button = NSTableColumn.alloc().initWithIdentifier_("button")
        col_button.setWidth_(160)
        col_button.setEditable_(False)
        self._mapping_table.addTableColumn_(col_button)

        type_cell = NSPopUpButtonCell.alloc().initTextCell_pullsDown_("", False)
        type_cell.addItemsWithTitles_(["Keystroke", "Wispr", "No action"])
        col_type = NSTableColumn.alloc().initWithIdentifier_("type")
        col_type.setWidth_(140)
        col_type.setDataCell_(type_cell)
        col_type.setEditable_(True)
        self._mapping_table.addTableColumn_(col_type)

        col_key = NSTableColumn.alloc().initWithIdentifier_("key")
        col_key.setWidth_(200)
        col_key.setEditable_(True)
        self._mapping_table.addTableColumn_(col_key)

        col_mod = NSTableColumn.alloc().initWithIdentifier_("modifiers")
        col_mod.setWidth_(220)
        col_mod.setEditable_(True)
        self._mapping_table.addTableColumn_(col_mod)

        scroll.setDocumentView_(self._mapping_table)
        view.addSubview_(scroll)

        footer = NSVisualEffectView.alloc().initWithFrame_(
            NSMakeRect(0, 0, frame.size.width, footer_h)
        )
        footer.setMaterial_(NSVisualEffectMaterialUnderWindowBackground)
        footer.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
        footer.setState_(NSVisualEffectStateFollowsWindowActiveState)
        footer.setAutoresizingMask_(NSViewWidthSizable | NSViewMaxYMargin)
        view.addSubview_(footer)

        btn_y = int((footer_h - 28) / 2)
        x = pad
        for symbol, tooltip, action in [
            ("plus", "Add mapping…", "addMapping:"),
            ("minus", "Remove mapping", "deleteMapping:"),
        ]:
            btn = NSButton.alloc().initWithFrame_(NSMakeRect(x, btn_y, 34, 28))
            btn.setBezelStyle_(NSBezelStyleTexturedRounded)
            img = _symbol_image(symbol, 13.0)
            if img is not None:
                btn.setImage_(img)
                btn.setImagePosition_(NSImageOnly)
                btn.setTitle_("")
            else:
                btn.setTitle_(tooltip)
            btn.setToolTip_(tooltip)
            btn.setTarget_(self)
            btn.setAction_(action)
            footer.addSubview_(btn)
            x += 40

        return view

    # Sidebar handling
    def _context_display_name(self, context: str) -> str:
        display = {
            "default": "Global",
            "chatgpt": "ChatGPT",
            "claude": "Claude",
        }
        return display.get(context, context.title())

    def _context_icon_name(self, context: str) -> str | None:
        icons = {
            "default": "globe",
            "warp": "terminal",
            "arc": "globe",
            "chrome": "globe",
            "slack": "bubble.left.and.bubble.right",
            "chatgpt": "message",
            "claude": "message",
        }
        return icons.get(context, "app")

    def _build_sidebar_model(self) -> list[SidebarItem]:
        contexts = self._store.context_names()
        children = [
            SidebarItem(
                kind="context",
                label=self._context_display_name(ctx),
                icon=self._context_icon_name(ctx),
                context=ctx,
            )
            for ctx in contexts
        ]
        return [
            SidebarItem(kind="profiles", label="Profiles", icon="person.crop.circle"),
            SidebarItem(kind="controller", label="Controller", icon="gamecontroller"),
            SidebarItem(kind="group", label="Keybinds", children=children),
        ]

    def _refresh_profile_popups(self) -> None:
        names = self._store.profile_names()
        active = self._store.active_profile
        for popup in [
            getattr(self, "_profiles_active_popup", None),
            getattr(self, "_keybinds_profile_popup", None),
        ]:
            if popup is None:
                continue
            popup.removeAllItems()
            popup.addItemsWithTitles_(names)
            if active in names:
                popup.selectItemWithTitle_(active)

    def _select_sidebar_target(self, kind: str, context: str | None = None) -> None:
        target = None
        for item in self._sidebar_root:
            if item.kind == kind and kind in ("profiles", "controller"):
                target = item
                break
            for child in item.children or []:
                if child.kind == kind and child.context == context:
                    target = child
                    break
            if target is not None:
                break

        if target is None:
            return

        row = self._sidebar_outline.rowForItem_(target)
        if row < 0:
            return
        self._sidebar_outline.selectRowIndexes_byExtendingSelection_(
            NSIndexSet.indexSetWithIndex_(row), False
        )
        self._sidebar_outline.scrollRowToVisible_(row)

    def _reload_sidebar(self) -> None:
        if self._current_section == "profiles":
            selecting = ("profiles", None)
        elif self._current_section == "controller":
            selecting = ("controller", None)
        else:
            selecting = ("context", self._selected_context)

        self._sidebar_root = self._build_sidebar_model()
        self._sidebar_outline.reloadData()

        for item in self._sidebar_root:
            if item.kind == "group":
                self._sidebar_outline.expandItem_expandChildren_(item, True)

        self._refresh_profile_popups()
        self._select_sidebar_target(kind=selecting[0], context=selecting[1])

        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is not None:
            profiles_table.reloadData()
        if self._current_section == "keybinds":
            self._reload_mapping_rows()
            self._update_keybinds_subtitle()
        if self._current_section == "controller":
            self._refresh_controller_view()

    def _show_profiles_view(self) -> None:
        self._current_section = "profiles"
        self._keybinds_view.setHidden_(True)
        self._controller_view.setHidden_(True)
        self._profiles_view.setHidden_(False)
        self._refresh_profile_popups()
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is not None:
            profiles_table.reloadData()

    def _show_controller_view(self) -> None:
        self._current_section = "controller"
        self._profiles_view.setHidden_(True)
        self._keybinds_view.setHidden_(True)
        self._controller_view.setHidden_(False)
        self._refresh_controller_view()

    def _show_keybinds_view(self, context: str) -> None:
        self._current_section = "keybinds"
        self._selected_context = context
        self._profiles_view.setHidden_(True)
        self._controller_view.setHidden_(True)
        self._keybinds_view.setHidden_(False)
        self._refresh_profile_popups()
        self._reload_mapping_rows()
        self._update_keybinds_subtitle()

    def _update_keybinds_subtitle(self) -> None:
        ctx = self._context_display_name(self._selected_context)
        self._keybinds_subtitle.setStringValue_(
            f"Profile: {self._store.active_profile}  •  Context: {ctx}"
        )

    def _reload_mapping_rows(self) -> None:
        ctx = self._store.get_context_mapping(self._selected_context)
        rows: list[MappingRow] = []
        for button, action in sorted(ctx.items(), key=lambda kv: kv[0]):
            if isinstance(action, dict):
                rows.append(_action_to_row(button, action))
        self._rows = rows
        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is not None:
            mapping_table.reloadData()

    def _start_event_timer(self) -> None:
        if self._event_timer is not None:
            return
        self._event_timer = (
            NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                0.05, self, "_pollDaemonEvents:", None, True
            )
        )

    def _onPrefsWindowWillClose_(self, notification):  # noqa: N802
        try:
            if self._event_timer is not None:
                self._event_timer.invalidate()
                self._event_timer = None
        except Exception:
            pass
        try:
            NSNotificationCenter.defaultCenter().removeObserver_(self)
        except Exception:
            pass

    def _pollDaemonEvents_(self, timer):  # noqa: N802
        updated = False
        for event in self._daemon.drain_events():
            event_type = str(event.get("type") or "")
            if event_type == "controller_connected":
                self._active_controller_name = str(event.get("name") or "") or None
                conn = event.get("connection")
                self._active_controller_connection = str(conn) if conn else None
                updated = True
                continue
            if event_type == "controller_disconnected":
                self._active_controller_name = None
                self._active_controller_connection = None
                self._pressed_buttons.clear()
                updated = True
                continue
            if event_type == "daemon_stopped":
                self._active_controller_name = None
                self._active_controller_connection = None
                self._pressed_buttons.clear()
                updated = True
                continue
            if event_type != "button":
                continue

            state = str(event.get("state") or "")
            button = str(event.get("button") or "").strip()
            if not button:
                continue

            if state == "pressed":
                self._pressed_buttons.add(button)
                self._last_pressed_button = button
            elif state == "released":
                self._pressed_buttons.discard(button)

            action_summary = "—"
            if state == "pressed":
                action_summary = self._format_action_summary(event.get("action"))

            self._input_events.append(
                InputEventRow(
                    time=datetime.now().strftime("%H:%M:%S"),
                    state="Pressed" if state == "pressed" else "Released",
                    button=button,
                    action=action_summary,
                )
            )
            if len(self._input_events) > 200:
                self._input_events = self._input_events[-200:]
            updated = True

        self._refresh_controller_view()
        if not updated:
            return

        table = getattr(self, "_controller_events_table", None)
        if table is None:
            return
        try:
            table.reloadData()
            last_row = len(self._input_events) - 1
            if last_row >= 0:
                table.scrollRowToVisible_(last_row)
        except Exception:
            pass

    def _format_action_summary(self, action) -> str:
        if not isinstance(action, dict):
            return "—"

        typ = str(action.get("type") or "noop").strip().lower()
        if typ == "wispr":
            return "Wispr"
        if typ == "noop":
            return "No action"
        if typ != "keystroke":
            return typ

        key = str(action.get("key") or "").strip()
        mods = (
            action.get("modifiers")
            if isinstance(action.get("modifiers"), list)
            else None
        )
        mods = [str(m).strip() for m in (mods or []) if str(m).strip()]
        if mods and key:
            return f"Keystroke: {'+'.join(mods)}+{key}"
        if key:
            return f"Keystroke: {key}"
        if mods:
            return f"Keystroke: {'+'.join(mods)}"
        return "Keystroke"

    def _refresh_controller_view(self) -> None:
        popup = getattr(self, "_controller_pref_popup", None)
        if popup is not None:
            pref = self._store.controller_preference()
            title = {
                "auto": "Auto",
                "dualsense": "DualSense",
                "pro_controller": "Pro Controller",
            }.get(pref, "Auto")
            try:
                popup.selectItemWithTitle_(title)
            except Exception:
                pass

        daemon_running = self._daemon.running
        daemon_value = getattr(self, "_controller_daemon_value", None)
        if daemon_value is not None:
            daemon_value.setStringValue_("Running" if daemon_running else "Stopped")

        toggle_btn = getattr(self, "_controller_toggle_btn", None)
        if toggle_btn is not None:
            toggle_btn.setTitle_("Stop" if daemon_running else "Start")

        active_value = getattr(self, "_controller_active_value", None)
        if active_value is not None:
            if not daemon_running:
                active_value.setStringValue_("—")
            elif self._active_controller_name:
                if self._active_controller_connection:
                    active_value.setStringValue_(
                        f"{self._active_controller_name} ({self._active_controller_connection})"
                    )
                else:
                    active_value.setStringValue_(self._active_controller_name)
            else:
                snapshot = self._daemon.controller_snapshot()
                if snapshot and snapshot.get("name"):
                    name = str(snapshot.get("name") or "").strip()
                    conn = snapshot.get("connection")
                    self._active_controller_name = name or None
                    self._active_controller_connection = str(conn) if conn else None

                    if not snapshot.get("connected", True):
                        active_value.setStringValue_(f"{name} (Disconnected)")
                    elif self._active_controller_connection:
                        active_value.setStringValue_(
                            f"{name} ({self._active_controller_connection})"
                        )
                    else:
                        active_value.setStringValue_(name)
                else:
                    active_value.setStringValue_("Connecting…")

        input_value = getattr(self, "_controller_input_value", None)
        if input_value is not None:
            if not daemon_running:
                input_value.setStringValue_("—")
            else:
                last = self._last_pressed_button or "—"
                down = (
                    ", ".join(sorted(self._pressed_buttons))
                    if self._pressed_buttons
                    else "—"
                )
                input_value.setStringValue_(f"Last: {last}  •  Down: {down}")

    # NSOutlineView data source / delegate (sidebar)
    def outlineView_numberOfChildrenOfItem_(self, outlineView, item):  # noqa: N802
        if outlineView != getattr(self, "_sidebar_outline", None):
            return 0
        if item is None:
            return len(self._sidebar_root)
        return len(item.children or [])

    def outlineView_child_ofItem_(self, outlineView, index, item):  # noqa: N802
        if outlineView != getattr(self, "_sidebar_outline", None):
            return None
        if item is None:
            return self._sidebar_root[index]
        return (item.children or [])[index]

    def outlineView_isItemExpandable_(self, outlineView, item):  # noqa: N802
        if outlineView != getattr(self, "_sidebar_outline", None):
            return False
        return bool(item and item.expandable())

    def outlineView_isGroupItem_(self, outlineView, item):  # noqa: N802
        return bool(
            outlineView == getattr(self, "_sidebar_outline", None)
            and item
            and item.kind == "group"
        )

    def outlineView_shouldSelectItem_(self, outlineView, item):  # noqa: N802
        return bool(
            outlineView == getattr(self, "_sidebar_outline", None)
            and item
            and item.kind != "group"
        )

    def outlineView_viewForTableColumn_item_(self, outlineView, tableColumn, item):  # noqa: N802
        if outlineView != getattr(self, "_sidebar_outline", None) or item is None:
            return None

        identifier = "SidebarGroupCell" if item.kind == "group" else "SidebarCell"
        cell = outlineView.makeViewWithIdentifier_owner_(identifier, self)
        if cell is None:
            cell = NSTableCellView.alloc().initWithFrame_(NSMakeRect(0, 0, 200, 24))
            cell.setIdentifier_(identifier)

            x = 10
            if item.kind != "group":
                icon = NSImageView.alloc().initWithFrame_(NSMakeRect(10, 6, 16, 16))
                icon.setImageScaling_(NSImageScaleProportionallyDown)
                cell.addSubview_(icon)
                cell.setImageView_(icon)
                x = 32

            text = NSTextField.alloc().initWithFrame_(NSMakeRect(x, 4, 220, 20))
            text.setBezeled_(False)
            text.setDrawsBackground_(False)
            text.setEditable_(False)
            text.setSelectable_(False)
            text.setLineBreakMode_(NSLineBreakByTruncatingTail)
            cell.addSubview_(text)
            cell.setTextField_(text)

        tf = cell.textField()
        if tf is not None:
            label = item.label.upper() if item.kind == "group" else item.label
            tf.setStringValue_(label)
            if item.kind == "group":
                tf.setFont_(NSFont.systemFontOfSize_weight_(11, NSFontWeightSemibold))
                tf.setTextColor_(NSColor.secondaryLabelColor())
            else:
                tf.setFont_(NSFont.systemFontOfSize_(13))
                tf.setTextColor_(NSColor.labelColor())

        iv = cell.imageView()
        if iv is not None:
            if item.kind == "group" or not item.icon:
                iv.setImage_(None)
            else:
                iv.setImage_(_symbol_image(item.icon, 14.0))

        return cell

    def outlineViewSelectionDidChange_(self, notification):  # noqa: N802
        outlineView = notification.object()
        if outlineView != getattr(self, "_sidebar_outline", None):
            return
        row = outlineView.selectedRow()
        if row < 0:
            return
        item = outlineView.itemAtRow_(row)
        if item is None:
            return
        if item.kind == "profiles":
            self._show_profiles_view()
        elif item.kind == "controller":
            self._show_controller_view()
        elif item.kind == "context" and item.context:
            self._show_keybinds_view(item.context)

    # NSTableView data source / delegate
    def numberOfRowsInTableView_(self, tableView) -> int:  # noqa: N802
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is not None and tableView == profiles_table:
            return len(self._store.profile_names())
        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is not None and tableView == mapping_table:
            return len(self._rows)
        events_table = getattr(self, "_controller_events_table", None)
        if events_table is not None and tableView == events_table:
            return len(self._input_events)
        return 0

    def tableView_objectValueForTableColumn_row_(self, tableView, tableColumn, row):  # noqa: N802
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is not None and tableView == profiles_table:
            name = self._store.profile_names()[row]
            prefix = "✓ " if name == self._store.active_profile else "  "
            return f"{prefix}{name}"

        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is not None and tableView == mapping_table:
            r = self._rows[row]
            ident = tableColumn.identifier()
            if ident == "button":
                return r.button
            if ident == "type":
                typ = r.type.strip().lower()
                return {
                    "keystroke": "Keystroke",
                    "wispr": "Wispr",
                    "noop": "No action",
                }.get(typ, "No action")
            if ident == "key":
                return r.key
            if ident == "modifiers":
                return r.modifiers
        if tableView == getattr(self, "_controller_events_table", None):
            r = self._input_events[row]
            ident = tableColumn.identifier()
            if ident == "time":
                return r.time
            if ident == "state":
                return r.state
            if ident == "button":
                return r.button
            if ident == "action":
                return r.action
        return ""

    def tableView_shouldEditTableColumn_row_(self, tableView, tableColumn, row):  # noqa: N802
        events_table = getattr(self, "_controller_events_table", None)
        if events_table is not None and tableView == events_table:
            return False

        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is None or tableView != mapping_table:
            return True

        ident = tableColumn.identifier()
        if ident not in ("key", "modifiers"):
            return True
        return self._rows[row].type.strip().lower() == "keystroke"

    def tableView_setObjectValue_forTableColumn_row_(
        self, tableView, value, tableColumn, row
    ):  # noqa: N802
        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is None or tableView != mapping_table:
            return

        ident = tableColumn.identifier()
        r = self._rows[row]
        new_value = str(value) if value is not None else ""

        if ident == "type":
            raw = new_value.strip().lower()
            action_type = {
                "keystroke": "keystroke",
                "wispr": "wispr",
                "noop": "noop",
            }.get(raw)
            if action_type is None:
                action_type = {
                    "no action": "noop",
                    "none": "noop",
                    "noaction": "noop",
                }.get(raw, "noop")
            r.type = action_type
            if action_type != "keystroke":
                r.key = ""
                r.modifiers = ""
        elif ident == "key":
            r.key = new_value.strip()
        elif ident == "modifiers":
            r.modifiers = new_value
        else:
            return

        # Persist row -> config.
        action_type = r.type.strip().lower()
        if action_type == "keystroke":
            action = {"type": "keystroke", "key": r.key}
            mods = _parse_modifiers(r.modifiers)
            if mods:
                action["modifiers"] = mods
        elif action_type == "wispr":
            action = {"type": "wispr"}
        else:
            action = {"type": "noop"}

        self._store.set_action(self._selected_context, r.button, action)

    def tableViewSelectionDidChange_(self, notification):  # noqa: N802
        # Keep this method present for NSTableView delegate compatibility.
        tableView = notification.object()
        profiles_table = getattr(self, "_profiles_table", None)
        mapping_table = getattr(self, "_mapping_table", None)
        events_table = getattr(self, "_controller_events_table", None)
        if tableView in (profiles_table, mapping_table, events_table):
            return

    # Actions
    def saveConfig_(self, sender):  # noqa: N802
        self._store.save()
        # Apply changes by restarting the daemon if it's running.
        if self._daemon.running:
            self._daemon.restart()
        self._reload_sidebar()

    def controllerPreferenceChanged_(self, sender):  # noqa: N802
        try:
            item = sender.selectedItem()
            key = item.representedObject() if item is not None else None
            self._store.set_controller_preference(str(key or "auto"))
        except Exception:
            return
        self._refresh_controller_view()

    def toggleDaemon_(self, sender):  # noqa: N802
        if self._daemon.running:
            self._daemon.stop()
            self._pressed_buttons.clear()
            self._active_controller_name = None
            self._active_controller_connection = None
            self._last_pressed_button = None
            self._refresh_controller_view()
            return

        try:
            # Ensure the daemon uses the latest preferences (incl. controller selection).
            self.saveConfig_(None)
            self._daemon.start()
        except Exception as exc:
            _show_alert("Could not start daemon", str(exc))
        self._refresh_controller_view()

    def activeProfileChanged_(self, sender):  # noqa: N802
        try:
            name = str(sender.titleOfSelectedItem())
        except Exception:
            return
        if not name:
            return
        self._store.set_active_profile(name)
        self._reload_sidebar()

    def setActiveProfile_(self, sender):  # noqa: N802
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is None:
            return
        idx = profiles_table.selectedRow()
        if idx is None or idx < 0:
            return
        name = self._store.profile_names()[idx]
        self._store.set_active_profile(name)
        self._reload_sidebar()

    def addProfile_(self, sender):  # noqa: N802
        name = _prompt_text(self.window(), "New Profile", "Profile name:")
        if not name:
            return
        try:
            self._store.add_profile(name, clone_from=self._store.active_profile)
        except Exception as exc:
            _show_alert("Could not add profile", str(exc))
            return
        self._reload_sidebar()

    def duplicateProfile_(self, sender):  # noqa: N802
        src = self._store.active_profile
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is not None:
            idx = profiles_table.selectedRow()
            if idx is not None and idx >= 0:
                src = self._store.profile_names()[idx]

        existing = set(self._store.profile_names())
        base = f"{src} copy"
        candidate = base
        n = 2
        while candidate in existing:
            candidate = f"{base} {n}"
            n += 1

        name = _prompt_text(
            self.window(), "Duplicate Profile", "New profile name:", default=candidate
        )
        if not name:
            return
        try:
            self._store.add_profile(name, clone_from=src)
        except Exception as exc:
            _show_alert("Could not duplicate profile", str(exc))
            return
        self._reload_sidebar()

    def renameProfile_(self, sender):  # noqa: N802
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is None:
            return
        idx = profiles_table.selectedRow()
        if idx is None or idx < 0:
            return
        old = self._store.profile_names()[idx]
        new = _prompt_text(self.window(), "Rename Profile", "New name:", default=old)
        if not new or new == old:
            return
        try:
            self._store.rename_profile(old, new)
        except Exception as exc:
            _show_alert("Could not rename profile", str(exc))
            return
        self._reload_sidebar()

    def deleteProfile_(self, sender):  # noqa: N802
        profiles_table = getattr(self, "_profiles_table", None)
        if profiles_table is None:
            return
        idx = profiles_table.selectedRow()
        if idx is None or idx < 0:
            return
        name = self._store.profile_names()[idx]
        try:
            self._store.delete_profile(name)
        except Exception as exc:
            _show_alert("Could not delete profile", str(exc))
            return
        self._reload_sidebar()

    def addMapping_(self, sender):  # noqa: N802
        button = _prompt_text(
            self.window(), "Add Mapping", "Button name (e.g., cross, dpad_up):"
        )
        if not button:
            return
        button = button.strip()
        if not button:
            return
        self._store.set_action(
            self._selected_context, button, {"type": "keystroke", "key": "return"}
        )
        self._reload_mapping_rows()

    def deleteMapping_(self, sender):  # noqa: N802
        mapping_table = getattr(self, "_mapping_table", None)
        if mapping_table is None:
            return
        idx = mapping_table.selectedRow()
        if idx is None or idx < 0:
            return
        btn = self._rows[idx].button
        self._store.delete_action(self._selected_context, btn)
        self._reload_mapping_rows()


def _prompt_text(
    window: NSWindow, title: str, label: str, default: str = ""
) -> str | None:
    from AppKit import NSAlert  # late import to keep module load light

    alert = NSAlert.alloc().init()
    alert.setMessageText_(title)
    alert.setInformativeText_(label)
    field = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 24))
    field.setStringValue_(default)
    alert.setAccessoryView_(field)
    alert.addButtonWithTitle_("OK")
    alert.addButtonWithTitle_("Cancel")
    resp = alert.runModal()
    # NSAlertFirstButtonReturn == 1000
    if int(resp) != 1000:
        return None
    return str(field.stringValue())


def _show_alert(title: str, message: str) -> None:
    from AppKit import NSAlert  # late import to keep module load light

    alert = NSAlert.alloc().init()
    alert.setMessageText_(title)
    alert.setInformativeText_(message)
    alert.addButtonWithTitle_("OK")
    alert.runModal()


def _install_main_menu(app: NSApplication, controller: NSObject) -> None:
    main = NSMenu.alloc().init()

    app_item = NSMenuItem.alloc().init()
    app_item.setTitle_("CC Controller")
    main.addItem_(app_item)

    app_menu = NSMenu.alloc().init()
    app_item.setSubmenu_(app_menu)

    about = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
        "About CC Controller", "orderFrontStandardAboutPanel:", ""
    )
    app_menu.addItem_(about)
    app_menu.addItem_(NSMenuItem.separatorItem())

    prefs = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
        "Preferences…", "openPreferences:", ","
    )
    prefs.setTarget_(controller)
    prefs.setKeyEquivalentModifierMask_(NSEventModifierFlagCommand)
    app_menu.addItem_(prefs)
    app_menu.addItem_(NSMenuItem.separatorItem())

    quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
        "Quit CC Controller", "quit:", "q"
    )
    quit_item.setTarget_(controller)
    quit_item.setKeyEquivalentModifierMask_(NSEventModifierFlagCommand)
    app_menu.addItem_(quit_item)

    edit_item = NSMenuItem.alloc().init()
    edit_item.setTitle_("Edit")
    main.addItem_(edit_item)

    edit = NSMenu.alloc().init()
    edit_item.setSubmenu_(edit)
    edit.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Undo", "undo:", "z")
    )
    redo = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Redo", "redo:", "z")
    redo.setKeyEquivalentModifierMask_(
        NSEventModifierFlagCommand | NSEventModifierFlagShift
    )
    edit.addItem_(redo)
    edit.addItem_(NSMenuItem.separatorItem())
    edit.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Cut", "cut:", "x")
    )
    edit.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Copy", "copy:", "c")
    )
    edit.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Paste", "paste:", "v")
    )
    edit.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Select All", "selectAll:", "a"
        )
    )

    window_item = NSMenuItem.alloc().init()
    window_item.setTitle_("Window")
    main.addItem_(window_item)

    window_menu = NSMenu.alloc().init()
    window_item.setSubmenu_(window_menu)
    window_menu.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Close", "performClose:", "w"
        )
    )
    window_menu.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Minimize", "performMiniaturize:", "m"
        )
    )
    window_menu.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Zoom", "performZoom:", ""
        )
    )
    window_menu.addItem_(NSMenuItem.separatorItem())
    window_menu.addItem_(
        NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Bring All to Front", "arrangeInFront:", ""
        )
    )

    app.setMainMenu_(main)
    try:
        app.setWindowsMenu_(window_menu)
    except Exception:
        pass


class StatusBarController(NSObject):
    def init(self):  # noqa: N802
        self = objc.super(StatusBarController, self).init()
        if self is None:
            return None

        self._store = ConfigStore()
        self._daemon = DaemonManager()
        self._prefs: PreferencesWindowController | None = None

        self._status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(
            NSVariableStatusItemLength
        )
        self._status_item.button().setTitle_("CC")
        self._menu = NSMenu.alloc().init()

        self._item_start = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Start", "startDaemon:", ""
        )
        self._item_start.setTarget_(self)
        self._menu.addItem_(self._item_start)

        self._item_stop = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Stop", "stopDaemon:", ""
        )
        self._item_stop.setTarget_(self)
        self._menu.addItem_(self._item_stop)

        self._menu.addItem_(NSMenuItem.separatorItem())

        item_prefs = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Preferences…", "openPreferences:", ","
        )
        item_prefs.setTarget_(self)
        self._menu.addItem_(item_prefs)

        item_open_config = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Open Config", "openConfig:", ""
        )
        item_open_config.setTarget_(self)
        self._menu.addItem_(item_open_config)

        item_open_logs = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Open Logs", "openLogs:", ""
        )
        item_open_logs.setTarget_(self)
        self._menu.addItem_(item_open_logs)

        self._menu.addItem_(NSMenuItem.separatorItem())

        item_quit = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Quit", "quit:", "q"
        )
        item_quit.setTarget_(self)
        self._menu.addItem_(item_quit)

        self._status_item.setMenu_(self._menu)
        self._refresh_menu_state()
        return self

    def _refresh_menu_state(self) -> None:
        self._item_start.setEnabled_(not self._daemon.running)
        self._item_stop.setEnabled_(self._daemon.running)

    def startDaemon_(self, sender):  # noqa: N802
        try:
            self._daemon.start()
        except Exception as exc:
            _show_alert("Could not start daemon", str(exc))
        self._refresh_menu_state()

    def stopDaemon_(self, sender):  # noqa: N802
        self._daemon.stop()
        self._refresh_menu_state()

    def openPreferences_(self, sender):  # noqa: N802
        try:
            if self._prefs is None or self._prefs.window() is None:
                self._prefs = PreferencesWindowController.alloc().initWithStore_daemon_(
                    self._store, self._daemon
                )
            if self._prefs is None:
                raise RuntimeError("Could not create Preferences window controller")

            # Bring the app to the foreground, then show the window.
            NSApp().setActivationPolicy_(NSApplicationActivationPolicyRegular)
            NSRunningApplication.currentApplication().activateWithOptions_(
                1 << 1
            )  # NSApplicationActivateIgnoringOtherApps
            self._prefs.showWindow_(None)

            window = self._prefs.window()
            if window is not None:
                window.setDelegate_(self)
                window.makeKeyAndOrderFront_(None)
        except Exception as exc:
            log.exception("Failed to open Preferences window")
            _show_alert("Preferences error", str(exc))

    def openConfig_(self, sender):  # noqa: N802
        from AppKit import NSWorkspace

        path = Path(self._store.path)
        NSWorkspace.sharedWorkspace().openFile_(str(path))

    def openLogs_(self, sender):  # noqa: N802
        from AppKit import NSWorkspace

        log_path = Path.home() / "Library" / "Logs" / "cc-controller.log"
        NSWorkspace.sharedWorkspace().openFile_(str(log_path))

    def quit_(self, sender):  # noqa: N802
        self._daemon.stop()
        NSApp().terminate_(None)

    def windowWillClose_(self, notification):  # noqa: N802
        try:
            prefs_window = None if self._prefs is None else self._prefs.window()
            if prefs_window is not None and notification.object() == prefs_window:
                NSApp().setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        except Exception:
            pass


def main() -> None:
    configure_logging()
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    controller = StatusBarController.alloc().init()
    _install_main_menu(app, controller)

    # Keep a strong ref; otherwise it may get GC'd.
    app.setDelegate_(controller)

    NSNotificationCenter.defaultCenter()
    app.run()
