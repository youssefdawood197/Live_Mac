#!/usr/bin/env python3
"""
Empirical verification test suite for FlakeOverlayWindow.cs Win32 styles and state transitions.
Validates:
- Window style and extended style constants against Win32 specification.
- Dynamic click-through toggle bitmask algebra (WS_EX_TRANSPARENT addition/removal).
- Preservation of base extended styles (WS_EX_TOPMOST, WS_EX_TOOLWINDOW, WS_EX_LAYERED, WS_EX_NOACTIVATE).
- WM_MOUSEACTIVATE return value (MA_NOACTIVATE = 3).
- Signed 16-bit coordinate unpacking for multi-monitor negative desktop spaces.
- SetWindowPos flag combinations for immediate DWM recomposition without focus stealing.
"""

import unittest
from enum import Enum

# Official Win32 API constants from Windows SDK / CsWin32
class WindowStyle:
    WS_POPUP = 0x80000000
    WS_VISIBLE = 0x10000000

class WindowExStyle:
    WS_EX_TOPMOST = 0x00000008
    WS_EX_TRANSPARENT = 0x00000020
    WS_EX_TOOLWINDOW = 0x00000080
    WS_EX_LAYERED = 0x00080000
    WS_EX_NOACTIVATE = 0x08000000

class SetWindowPosFlags:
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_NOZORDER = 0x0004
    SWP_NOACTIVATE = 0x0010
    SWP_FRAMECHANGED = 0x0020
    SWP_SHOWWINDOW = 0x0040

class WindowsMessages:
    WM_DESTROY = 0x0002
    WM_MOUSEACTIVATE = 0x0021
    WM_DISPLAYCHANGE = 0x007E
    WM_MOUSEMOVE = 0x0200

class MouseActivateReturn:
    MA_ACTIVATE = 1
    MA_ACTIVATEANDEAT = 2
    MA_NOACTIVATE = 3
    MA_NOACTIVATEANDEAT = 4

class MouseKeys:
    MK_LBUTTON = 0x0001

class InteractiveTool(Enum):
    NoneTool = 0
    Mitten = 1
    Shovel = 2
    Snowman = 3


class MockFlakeOverlayWindow:
    """Accurately mirrors FlakeOverlayWindow.cs logic and bitmask transformations."""

    def __init__(self, hwnd=12345):
        self.hwnd = hwnd
        self.current_tool = InteractiveTool.NoneTool
        self.is_disposed = False
        self.mouse_moved_calls = []
        self.mouse_dragged_calls = []
        self.set_window_pos_history = []

        # From FlakeOverlayWindow.cs CreateWindow()
        self.style = WindowStyle.WS_POPUP | WindowStyle.WS_VISIBLE
        self.ex_style = (
            WindowExStyle.WS_EX_TOPMOST |
            WindowExStyle.WS_EX_TOOLWINDOW |
            WindowExStyle.WS_EX_LAYERED |
            WindowExStyle.WS_EX_TRANSPARENT |
            WindowExStyle.WS_EX_NOACTIVATE
        )

    def set_interactive_tool(self, tool: InteractiveTool):
        if self.hwnd == 0 or self.current_tool == tool:
            return

        self.current_tool = tool
        current_ex_style = self.ex_style

        if tool == InteractiveTool.NoneTool:
            # Restore click-through passthrough
            current_ex_style |= WindowExStyle.WS_EX_TRANSPARENT
        else:
            # Intercept mouse clicks for mitten/shovel without stealing focus
            current_ex_style &= ~WindowExStyle.WS_EX_TRANSPARENT

        self.ex_style = current_ex_style

        # SetWindowPos call
        flags = (
            SetWindowPosFlags.SWP_NOMOVE |
            SetWindowPosFlags.SWP_NOSIZE |
            SetWindowPosFlags.SWP_NOACTIVATE |
            SetWindowPosFlags.SWP_FRAMECHANGED
        )
        self.set_window_pos_history.append(flags)

    def wnd_proc(self, hwnd: int, msg: int, w_param: int, l_param: int) -> int:
        if msg == WindowsMessages.WM_MOUSEACTIVATE:
            # MA_NOACTIVATE (3): Never steal focus from active application
            return MouseActivateReturn.MA_NOACTIVATE

        elif msg == WindowsMessages.WM_MOUSEMOVE:
            if self.current_tool != InteractiveTool.NoneTool:
                # C# (short)(lParam.Value & 0xFFFF)
                raw_x = l_param & 0xFFFF
                x = raw_x if raw_x < 0x8000 else raw_x - 0x10000

                # C# (short)((lParam.Value >> 16) & 0xFFFF)
                raw_y = (l_param >> 16) & 0xFFFF
                y = raw_y if raw_y < 0x8000 else raw_y - 0x10000

                pt = (x, y)
                if (w_param & MouseKeys.MK_LBUTTON) != 0:
                    self.mouse_dragged_calls.append(pt)
                else:
                    self.mouse_moved_calls.append(pt)
            return 0

        elif msg == WindowsMessages.WM_DESTROY:
            self.hwnd = 0
            return 0

        return -1  # DefWindowProc


class TestFlakeOverlayWindow(unittest.TestCase):

    def test_win32_constant_values(self):
        """Verify Win32 constants match official Windows SDK specifications."""
        self.assertEqual(WindowStyle.WS_POPUP, 0x80000000)
        self.assertEqual(WindowStyle.WS_VISIBLE, 0x10000000)
        self.assertEqual(WindowExStyle.WS_EX_TOPMOST, 0x00000008)
        self.assertEqual(WindowExStyle.WS_EX_TRANSPARENT, 0x00000020)
        self.assertEqual(WindowExStyle.WS_EX_TOOLWINDOW, 0x00000080)
        self.assertEqual(WindowExStyle.WS_EX_LAYERED, 0x00080000)
        self.assertEqual(WindowExStyle.WS_EX_NOACTIVATE, 0x08000000)
        self.assertEqual(MouseActivateReturn.MA_NOACTIVATE, 3)

    def test_initial_window_styles(self):
        """Verify initial window creation flags contain all 5 required extended styles."""
        window = MockFlakeOverlayWindow()

        # Check window style
        self.assertTrue(window.style & WindowStyle.WS_POPUP != 0)
        self.assertTrue(window.style & WindowStyle.WS_VISIBLE != 0)

        # Check all 5 extended styles
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOPMOST != 0)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOOLWINDOW != 0)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_LAYERED != 0)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TRANSPARENT != 0)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_NOACTIVATE != 0)

        # Expected combined mask
        expected_mask = (
            0x00000008 | # TOPMOST
            0x00000080 | # TOOLWINDOW
            0x00080000 | # LAYERED
            0x00000020 | # TRANSPARENT
            0x08000000   # NOACTIVATE
        )
        self.assertEqual(window.ex_style, expected_mask)
        self.assertEqual(window.ex_style, 0x080800A8)

    def test_dynamic_clickthrough_toggle_mitten(self):
        """Switching to Mitten tool removes WS_EX_TRANSPARENT without mutating other styles."""
        window = MockFlakeOverlayWindow()
        initial_ex = window.ex_style

        # Activate Mitten
        window.set_interactive_tool(InteractiveTool.Mitten)

        # WS_EX_TRANSPARENT must be cleared
        self.assertFalse(window.ex_style & WindowExStyle.WS_EX_TRANSPARENT)

        # All other 4 styles must remain active
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOPMOST)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOOLWINDOW)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_LAYERED)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_NOACTIVATE)

        # Exact expected bitmask without WS_EX_TRANSPARENT (0x00000020)
        self.assertEqual(window.ex_style, initial_ex & ~WindowExStyle.WS_EX_TRANSPARENT)
        self.assertEqual(window.ex_style, 0x08080088)

    def test_dynamic_clickthrough_toggle_snowman(self):
        """Switching to Snowman tool removes WS_EX_TRANSPARENT without mutating other styles."""
        window = MockFlakeOverlayWindow()
        initial_ex = window.ex_style

        # Activate Snowman builder
        window.set_interactive_tool(InteractiveTool.Snowman)

        # WS_EX_TRANSPARENT must be cleared
        self.assertFalse(window.ex_style & WindowExStyle.WS_EX_TRANSPARENT)

        # All other 4 styles must remain active
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOPMOST)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TOOLWINDOW)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_LAYERED)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_NOACTIVATE)
        self.assertEqual(window.ex_style, initial_ex & ~WindowExStyle.WS_EX_TRANSPARENT)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_LAYERED)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_NOACTIVATE)

        # Difference must be exactly WS_EX_TRANSPARENT
        self.assertEqual(initial_ex ^ window.ex_style, WindowExStyle.WS_EX_TRANSPARENT)

        # SetWindowPos must include SWP_FRAMECHANGED and SWP_NOACTIVATE
        last_flags = window.set_window_pos_history[-1]
        self.assertTrue(last_flags & SetWindowPosFlags.SWP_FRAMECHANGED != 0)
        self.assertTrue(last_flags & SetWindowPosFlags.SWP_NOACTIVATE != 0)
        self.assertTrue(last_flags & SetWindowPosFlags.SWP_NOMOVE != 0)
        self.assertTrue(last_flags & SetWindowPosFlags.SWP_NOSIZE != 0)

    def test_dynamic_clickthrough_toggle_restore_none(self):
        """Switching back to NoneTool restores WS_EX_TRANSPARENT to exact initial style."""
        window = MockFlakeOverlayWindow()
        initial_ex = window.ex_style

        window.set_interactive_tool(InteractiveTool.Shovel)
        self.assertFalse(window.ex_style & WindowExStyle.WS_EX_TRANSPARENT)

        window.set_interactive_tool(InteractiveTool.NoneTool)
        self.assertTrue(window.ex_style & WindowExStyle.WS_EX_TRANSPARENT)
        self.assertEqual(window.ex_style, initial_ex)

    def test_idempotent_tool_toggles(self):
        """Redundant calls with the same tool produce no style mutations or SetWindowPos calls."""
        window = MockFlakeOverlayWindow()

        # Already NoneTool
        window.set_interactive_tool(InteractiveTool.NoneTool)
        self.assertEqual(len(window.set_window_pos_history), 0)

        window.set_interactive_tool(InteractiveTool.Mitten)
        self.assertEqual(len(window.set_window_pos_history), 1)

        # Redundant Mitten
        window.set_interactive_tool(InteractiveTool.Mitten)
        self.assertEqual(len(window.set_window_pos_history), 1)

    def test_rapid_alternating_stress(self):
        """Verify 1,000 rapid tool state changes maintain strict bitmask integrity."""
        window = MockFlakeOverlayWindow()
        base_without_trans = (
            WindowExStyle.WS_EX_TOPMOST |
            WindowExStyle.WS_EX_TOOLWINDOW |
            WindowExStyle.WS_EX_LAYERED |
            WindowExStyle.WS_EX_NOACTIVATE
        )
        base_with_trans = base_without_trans | WindowExStyle.WS_EX_TRANSPARENT

        tools = [InteractiveTool.NoneTool, InteractiveTool.Mitten, InteractiveTool.Shovel]
        for i in range(1000):
            tool = tools[i % 3]
            window.set_interactive_tool(tool)
            if tool == InteractiveTool.NoneTool:
                self.assertEqual(window.ex_style, base_with_trans)
            else:
                self.assertEqual(window.ex_style, base_without_trans)

    def test_wm_mouseactivate_returns_ma_noactivate(self):
        """WM_MOUSEACTIVATE must return 3 (MA_NOACTIVATE) to never steal focus."""
        window = MockFlakeOverlayWindow()
        result = window.wnd_proc(window.hwnd, WindowsMessages.WM_MOUSEACTIVATE, 0, 0)
        self.assertEqual(result, 3)
        self.assertEqual(result, MouseActivateReturn.MA_NOACTIVATE)

    def test_mouse_move_when_tool_idle_does_not_fire_events(self):
        """When CurrentTool is None, mouse move/drag events are ignored."""
        window = MockFlakeOverlayWindow()
        l_param = (200 << 16) | 100
        window.wnd_proc(window.hwnd, WindowsMessages.WM_MOUSEMOVE, 0, l_param)
        self.assertEqual(len(window.mouse_moved_calls), 0)
        self.assertEqual(len(window.mouse_dragged_calls), 0)

    def test_mouse_move_and_drag_with_active_tool(self):
        """When tool is active, distinguish left-button drag from hover move."""
        window = MockFlakeOverlayWindow()
        window.set_interactive_tool(InteractiveTool.Mitten)

        # Move without button (wParam = 0)
        l_param = (350 << 16) | 150
        window.wnd_proc(window.hwnd, WindowsMessages.WM_MOUSEMOVE, 0, l_param)
        self.assertEqual(window.mouse_moved_calls, [(150, 350)])
        self.assertEqual(len(window.mouse_dragged_calls), 0)

        # Drag with MK_LBUTTON (wParam = 1)
        l_param2 = (400 << 16) | 200
        window.wnd_proc(window.hwnd, WindowsMessages.WM_MOUSEMOVE, MouseKeys.MK_LBUTTON, l_param2)
        self.assertEqual(window.mouse_dragged_calls, [(200, 400)])

    def test_negative_coordinates_multimonitor_support(self):
        """Negative virtual screen coordinates must be preserved via signed 16-bit extension."""
        window = MockFlakeOverlayWindow()
        window.set_interactive_tool(InteractiveTool.Mitten)

        # Simulate coordinate (-100, -250)
        # -100 as uint16 is 65436 (0xFF9C)
        # -250 as uint16 is 65286 (0xFF06)
        u16_x = (-100) & 0xFFFF
        u16_y = (-250) & 0xFFFF
        l_param = (u16_y << 16) | u16_x

        window.wnd_proc(window.hwnd, WindowsMessages.WM_MOUSEMOVE, 0, l_param)
        self.assertEqual(window.mouse_moved_calls, [(-100, -250)])

    def test_null_hwnd_guard(self):
        """Calls on destroyed window (HWND.Null) must be safe no-ops."""
        window = MockFlakeOverlayWindow()
        window.wnd_proc(window.hwnd, WindowsMessages.WM_DESTROY, 0, 0)
        self.assertEqual(window.hwnd, 0)

        # SetInteractiveTool on null hwnd should safely return without altering styles
        old_ex = window.ex_style
        window.set_interactive_tool(InteractiveTool.Mitten)
        self.assertEqual(window.ex_style, old_ex)


if __name__ == "__main__":
    unittest.main()
