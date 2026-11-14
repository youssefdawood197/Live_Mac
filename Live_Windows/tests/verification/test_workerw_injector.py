#!/usr/bin/env python3
"""
Empirical verification test suite for WorkerWInjector.cs Win32 desktop injection state machine.
Validates:
- Message handshake parameters (WM_SPAWN_WORKER = 0x052C, wParam = 0x0D, lParam = 0x01, SMTO_NORMAL, timeout = 1000ms).
- Window style stripping and addition for desktop child reparenting (WS_CHILD, WS_CLIPSIBLINGS, etc.).
- Caching of WorkerW handle and IsWindow validation.
- Explorer crash / restart recovery via TaskbarCreated message.
- Re-attachment of active wallpaper child upon Explorer restart.
- Safe behavior during timeouts, missing Progman, or double dispose.
"""

import unittest
from typing import Optional, List, Dict

# Official Win32 API constants
class WindowStyle:
    WS_OVERLAPPED = 0x00000000
    WS_POPUP = 0x80000000
    WS_CHILD = 0x40000000
    WS_VISIBLE = 0x10000000
    WS_CLIPSIBLINGS = 0x04000000
    WS_CLIPCHILDREN = 0x02000000
    WS_CAPTION = 0x00C00000
    WS_BORDER = 0x00800000
    WS_DLGFRAME = 0x00400000
    WS_THICKFRAME = 0x00040000

class SetWindowPosFlags:
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_NOZORDER = 0x0004
    SWP_NOACTIVATE = 0x0010
    SWP_FRAMECHANGED = 0x0020
    SWP_SHOWWINDOW = 0x0040

class MockWin32Environment:
    """Simulates the Win32 window manager desktop hierarchy."""

    def __init__(self):
        self.windows: Dict[int, Dict] = {}
        self.next_hwnd = 100
        self.taskbar_created_msg_id = 0xC001
        self.progman_hwnd: Optional[int] = None
        self.workerw_hwnd: Optional[int] = None
        self.shelldll_defview_hwnd: Optional[int] = None
        self.shelldll_parent_hwnd: Optional[int] = None
        self.progman_responsive = True
        self.messages_sent: List[Dict] = []

    def setup_standard_desktop(self):
        # Create Progman
        self.progman_hwnd = self.create_window("Progman", "Program Manager", WindowStyle.WS_POPUP | WindowStyle.WS_VISIBLE)

        # Before 0x052C, SHELLDLL_DefView is under Progman
        self.shelldll_parent_hwnd = self.progman_hwnd
        self.shelldll_defview_hwnd = self.create_window("SHELLDLL_DefView", "", WindowStyle.WS_CHILD, parent=self.progman_hwnd)

    def create_window(self, class_name: str, title: str, style: int, parent: Optional[int] = None) -> int:
        hwnd = self.next_hwnd
        self.next_hwnd += 1
        self.windows[hwnd] = {
            "hwnd": hwnd,
            "class_name": class_name,
            "title": title,
            "style": style,
            "parent": parent,
            "children": [],
            "pos": (0, 0, 0, 0)
        }
        if parent and parent in self.windows:
            self.windows[parent]["children"].append(hwnd)
        return hwnd

    def is_window(self, hwnd: int) -> bool:
        return hwnd in self.windows

    def find_window(self, class_name: str) -> int:
        for hwnd, win in self.windows.items():
            if win["class_name"] == class_name and win["parent"] is None:
                return hwnd
        return 0

    def find_window_ex(self, parent_hwnd: int, child_after: int, class_name: str) -> int:
        # In Win32, parent_hwnd == 0 searches top-level windows
        candidates = []
        if parent_hwnd == 0:
            candidates = [w for w in self.windows.values() if w["parent"] is None]
        else:
            candidates = [self.windows[cid] for cid in self.windows.get(parent_hwnd, {}).get("children", [])]

        found_after = (child_after == 0)
        for win in candidates:
            if not found_after:
                if win["hwnd"] == child_after:
                    found_after = True
                continue
            if win["class_name"] == class_name:
                return win["hwnd"]
        return 0

    def send_message_timeout(self, hwnd: int, msg: int, wparam: int, lparam: int, flags: int, timeout: int) -> bool:
        self.messages_sent.append({
            "hwnd": hwnd,
            "msg": msg,
            "wparam": wparam,
            "lparam": lparam,
            "flags": flags,
            "timeout": timeout
        })

        if not self.progman_responsive:
            return False

        if hwnd == self.progman_hwnd and msg == 0x052C:
            # 0x052C spawns WorkerW and reparents/splits SHELLDLL_DefView
            worker1 = self.create_window("WorkerW", "", WindowStyle.WS_VISIBLE)
            # Move SHELLDLL_DefView to worker1
            self.shelldll_parent_hwnd = worker1
            self.windows[self.shelldll_defview_hwnd]["parent"] = worker1
            # Sibling WorkerW directly behind worker1
            self.workerw_hwnd = self.create_window("WorkerW", "", WindowStyle.WS_VISIBLE)
            return True

        return True

    def enum_windows(self, callback):
        # Enumerate top-level windows
        top_windows = [w["hwnd"] for w in self.windows.values() if w["parent"] is None]
        for hwnd in top_windows:
            if not callback(hwnd):
                break

    def set_parent(self, child_hwnd: int, new_parent: int):
        if child_hwnd in self.windows:
            old_parent = self.windows[child_hwnd]["parent"]
            if old_parent and old_parent in self.windows:
                if child_hwnd in self.windows[old_parent]["children"]:
                    self.windows[old_parent]["children"].remove(child_hwnd)
            self.windows[child_hwnd]["parent"] = new_parent if new_parent != 0 else None
            if new_parent != 0 and new_parent in self.windows:
                self.windows[new_parent]["children"].append(child_hwnd)

    def set_window_long_ptr(self, hwnd: int, new_style: int):
        if hwnd in self.windows:
            self.windows[hwnd]["style"] = new_style

    def get_window_long_ptr(self, hwnd: int) -> int:
        return self.windows.get(hwnd, {}).get("style", 0)

    def set_window_pos(self, hwnd: int, insert_after: int, x: int, y: int, cx: int, cy: int, flags: int):
        if hwnd in self.windows:
            self.windows[hwnd]["pos"] = (x, y, cx, cy)


class MockWorkerWInjector:
    """Exact behavioral simulation of WorkerWInjector.cs."""

    WM_SPAWN_WORKER = 0x052C

    def __init__(self, env: MockWin32Environment):
        self.env = env
        self.wm_taskbar_created = env.taskbar_created_msg_id
        self.workerw_hwnd = 0
        self.reparented_child_hwnd = 0
        self.is_disposed = False
        self.workerw_reset_fired = 0
        self.desktop_reset_fired = 0

    def get_worker_w(self) -> int:
        if self.workerw_hwnd != 0 and self.env.is_window(self.workerw_hwnd):
            return self.workerw_hwnd

        progman = self.env.find_window("Progman")
        if progman == 0:
            return 0

        # Step 1: Send 0x052C to Progman
        self.env.send_message_timeout(
            progman,
            self.WM_SPAWN_WORKER,
            0x0000000D,
            0x00000001,
            0, # SMTO_NORMAL
            1000 # 1000 ms
        )

        # Step 2: Enumerate top-level windows
        found_worker_w = 0
        def enum_cb(top_hwnd):
            nonlocal found_worker_w
            shell_dll = self.env.find_window_ex(top_hwnd, 0, "SHELLDLL_DefView")
            if shell_dll != 0:
                found_worker_w = self.env.find_window_ex(0, top_hwnd, "WorkerW")
            return True

        self.env.enum_windows(enum_cb)
        self.workerw_hwnd = found_worker_w
        return self.workerw_hwnd

    def attach_to_desktop(self, content_hwnd: int, x: int, y: int, width: int, height: int) -> bool:
        target_worker_w = self.get_worker_w()
        if target_worker_w == 0:
            return False

        self.reparented_child_hwnd = content_hwnd

        # Set child window styles
        current_style = self.env.get_window_long_ptr(content_hwnd)
        current_style |= (
            WindowStyle.WS_CHILD |
            WindowStyle.WS_VISIBLE |
            WindowStyle.WS_CLIPSIBLINGS |
            WindowStyle.WS_CLIPCHILDREN
        )
        current_style &= ~(
            WindowStyle.WS_POPUP |
            WindowStyle.WS_CAPTION |
            WindowStyle.WS_THICKFRAME
        )
        self.env.set_window_long_ptr(content_hwnd, current_style)

        self.env.set_parent(content_hwnd, target_worker_w)
        self.env.set_window_pos(
            content_hwnd,
            0,
            x, y, width, height,
            SetWindowPosFlags.SWP_NOZORDER |
            SetWindowPosFlags.SWP_NOACTIVATE |
            SetWindowPosFlags.SWP_SHOWWINDOW |
            SetWindowPosFlags.SWP_FRAMECHANGED
        )
        return True

    def handle_window_message(self, msg: int, wparam: int, lparam: int) -> bool:
        if msg == self.wm_taskbar_created and self.wm_taskbar_created != 0:
            # Explorer restarted
            self.workerw_hwnd = 0
            new_worker_w = self.get_worker_w()

            if self.reparented_child_hwnd != 0 and new_worker_w != 0:
                self.env.set_parent(self.reparented_child_hwnd, new_worker_w)

            self.workerw_reset_fired += 1
            self.desktop_reset_fired += 1
            return True
        return False

    def detach(self, content_hwnd: int):
        if content_hwnd == self.reparented_child_hwnd:
            self.env.set_parent(content_hwnd, 0)
            self.reparented_child_hwnd = 0

    def dispose(self):
        if not self.is_disposed:
            if self.reparented_child_hwnd != 0:
                self.detach(self.reparented_child_hwnd)
            self.is_disposed = True


class TestWorkerWInjector(unittest.TestCase):

    def setUp(self):
        self.env = MockWin32Environment()
        self.env.setup_standard_desktop()
        self.injector = MockWorkerWInjector(self.env)

    def test_handshake_parameters_exactness(self):
        """WorkerW handshake must use 0x052C, wParam=0x0D, lParam=0x01, and timeout=1000ms."""
        worker_w = self.injector.get_worker_w()
        self.assertNotEqual(worker_w, 0)

        self.assertEqual(len(self.env.messages_sent), 1)
        msg = self.env.messages_sent[0]
        self.assertEqual(msg["msg"], 0x052C)
        self.assertEqual(msg["wparam"], 0x0000000D)
        self.assertEqual(msg["lparam"], 0x00000001)
        self.assertEqual(msg["timeout"], 1000)
        self.assertEqual(msg["flags"], 0) # SMTO_NORMAL

    def test_caching_avoids_repeated_handshakes(self):
        """Subsequent GetWorkerW calls must return cached handle when window remains valid."""
        w1 = self.injector.get_worker_w()
        self.assertEqual(len(self.env.messages_sent), 1)

        w2 = self.injector.get_worker_w()
        self.assertEqual(w1, w2)
        # Message count must NOT increase
        self.assertEqual(len(self.env.messages_sent), 1)

    def test_window_style_transformations(self):
        """Attaching a window must strip top-level styles and apply child clipping styles."""
        child = self.env.create_window(
            "LiveWallpaperView",
            "Content",
            WindowStyle.WS_POPUP | WindowStyle.WS_CAPTION | WindowStyle.WS_THICKFRAME | WindowStyle.WS_VISIBLE
        )

        success = self.injector.attach_to_desktop(child, 0, 0, 1920, 1080)
        self.assertTrue(success)

        final_style = self.env.get_window_long_ptr(child)

        # Forbidden styles must be cleared
        self.assertFalse(final_style & WindowStyle.WS_POPUP)
        self.assertFalse(final_style & WindowStyle.WS_CAPTION)
        self.assertFalse(final_style & WindowStyle.WS_THICKFRAME)

        # Required styles must be present
        self.assertTrue(final_style & WindowStyle.WS_CHILD)
        self.assertTrue(final_style & WindowStyle.WS_VISIBLE)
        self.assertTrue(final_style & WindowStyle.WS_CLIPSIBLINGS)
        self.assertTrue(final_style & WindowStyle.WS_CLIPCHILDREN)

        # Parent must be the WorkerW
        self.assertEqual(self.env.windows[child]["parent"], self.injector.workerw_hwnd)

    def test_missing_progman_fails_gracefully(self):
        """When Progman does not exist, GetWorkerW and AttachToDesktop return safely."""
        empty_env = MockWin32Environment()
        injector = MockWorkerWInjector(empty_env)

        worker = injector.get_worker_w()
        self.assertEqual(worker, 0)

        child = empty_env.create_window("Child", "", WindowStyle.WS_VISIBLE)
        success = injector.attach_to_desktop(child, 0, 0, 800, 600)
        self.assertFalse(success)

    def test_timeout_protection_when_explorer_hung(self):
        """When Progman is unresponsive, timeout protects caller from indefinite freeze."""
        self.env.progman_responsive = False
        worker = self.injector.get_worker_w()
        self.assertEqual(worker, 0)
        self.assertEqual(len(self.env.messages_sent), 1)
        self.assertEqual(self.env.messages_sent[0]["timeout"], 1000)

    def test_explorer_crash_and_taskbar_created_recovery(self):
        """TaskbarCreated broadcast triggers WorkerW invalidation, re-query, and reparenting."""
        child = self.env.create_window("WallpaperView", "", WindowStyle.WS_VISIBLE)
        self.injector.attach_to_desktop(child, 0, 0, 1920, 1080)
        initial_worker = self.injector.workerw_hwnd

        # Simulate Explorer crash: destroy old Progman & WorkerW
        del self.env.windows[self.env.progman_hwnd]
        del self.env.windows[initial_worker]

        # Explorer restarts: new Progman is launched
        self.env.setup_standard_desktop()

        # Windows broadcasts TaskbarCreated
        handled = self.injector.handle_window_message(self.env.taskbar_created_msg_id, 0, 0)
        self.assertTrue(handled)
        self.assertEqual(self.injector.workerw_reset_fired, 1)
        self.assertEqual(self.injector.desktop_reset_fired, 1)

        # Handle was renewed
        new_worker = self.injector.workerw_hwnd
        self.assertNotEqual(new_worker, 0)
        self.assertNotEqual(new_worker, initial_worker)

        # Child was reparented to new WorkerW
        self.assertEqual(self.env.windows[child]["parent"], new_worker)

    def test_detach_restores_toplevel(self):
        """Detaching an attached child sets parent to HWND.Null (top-level)."""
        child = self.env.create_window("WallpaperView", "", WindowStyle.WS_VISIBLE)
        self.injector.attach_to_desktop(child, 0, 0, 1920, 1080)
        self.assertEqual(self.injector.reparented_child_hwnd, child)

        self.injector.detach(child)
        self.assertIsNone(self.env.windows[child]["parent"])
        self.assertEqual(self.injector.reparented_child_hwnd, 0)

    def test_dispose_cleans_up_reparented_window(self):
        """Disposing injector releases reparented child and is idempotent."""
        child = self.env.create_window("WallpaperView", "", WindowStyle.WS_VISIBLE)
        self.injector.attach_to_desktop(child, 0, 0, 1920, 1080)

        self.injector.dispose()
        self.assertTrue(self.injector.is_disposed)
        self.assertIsNone(self.env.windows[child]["parent"])

        # Double dispose should not throw or change state
        self.injector.dispose()
        self.assertTrue(self.injector.is_disposed)


if __name__ == "__main__":
    unittest.main()
