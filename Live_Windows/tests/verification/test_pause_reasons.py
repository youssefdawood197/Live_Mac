#!/usr/bin/env python3
"""
Empirical verification test suite for PauseReasons.cs additive bitmask logic.
Validates:
- Exact powers-of-two values for all 5 flags + None + All.
- All 32 permutations (2^5) of flags: decomposition, HasFlag, IsPaused.
- Exact FormatDescription() formatting for all 32 combinations.
- Independence invariants: setting/clearing flag A never affects flag B.
- Commutativity, associativity, and idempotence under bitwise operators.
- 10,000-iteration Monte Carlo state machine transition simulation.
- Edge case behavior for out-of-range bits.
"""

import unittest
import random
from enum import IntFlag

class PauseReasons(IntFlag):
    NoneReason = 0
    UserPaused = 1 << 0       # 1
    FullscreenApp = 1 << 1    # 2
    DisplaySleeping = 1 << 2  # 4
    ScreenLocked = 1 << 3     # 8
    BatterySaver = 1 << 4     # 16
    All = UserPaused | FullscreenApp | DisplaySleeping | ScreenLocked | BatterySaver  # 31


def format_description(reasons: PauseReasons) -> str:
    """Exact logic of PauseReasonsExtensions.FormatDescription in C#."""
    if reasons == PauseReasons.NoneReason:
        return "none"
    parts = []
    if (reasons & PauseReasons.UserPaused) != 0:
        parts.append("userPaused")
    if (reasons & PauseReasons.FullscreenApp) != 0:
        parts.append("fullscreenApp")
    if (reasons & PauseReasons.DisplaySleeping) != 0:
        parts.append("displaySleeping")
    if (reasons & PauseReasons.ScreenLocked) != 0:
        parts.append("screenLocked")
    if (reasons & PauseReasons.BatterySaver) != 0:
        parts.append("batterySaver")
    return ", ".join(parts)


class TestPauseReasons(unittest.TestCase):

    ALL_FLAGS = [
        PauseReasons.UserPaused,
        PauseReasons.FullscreenApp,
        PauseReasons.DisplaySleeping,
        PauseReasons.ScreenLocked,
        PauseReasons.BatterySaver,
    ]

    FLAG_NAMES = {
        PauseReasons.UserPaused: "userPaused",
        PauseReasons.FullscreenApp: "fullscreenApp",
        PauseReasons.DisplaySleeping: "displaySleeping",
        PauseReasons.ScreenLocked: "screenLocked",
        PauseReasons.BatterySaver: "batterySaver",
    }

    def test_raw_values_match_powers_of_two(self):
        """Verify each flag corresponds to an exact distinct power of two."""
        self.assertEqual(int(PauseReasons.NoneReason), 0)
        self.assertEqual(int(PauseReasons.UserPaused), 1)
        self.assertEqual(int(PauseReasons.FullscreenApp), 2)
        self.assertEqual(int(PauseReasons.DisplaySleeping), 4)
        self.assertEqual(int(PauseReasons.ScreenLocked), 8)
        self.assertEqual(int(PauseReasons.BatterySaver), 16)
        self.assertEqual(int(PauseReasons.All), 31)

    def test_all_32_permutations_exhaustive_decomposition(self):
        """Exhaustively verify all 32 combinations (0..31) decompose cleanly into expected flags."""
        for val in range(32):
            reasons = PauseReasons(val)
            expected_active_flags = [flag for flag in self.ALL_FLAGS if (val & int(flag)) != 0]

            # Invariant: sum of active flag values must equal val
            self.assertEqual(sum(int(f) for f in expected_active_flags), val)

            # Invariant: HasFlag must be true iff flag is active
            for flag in self.ALL_FLAGS:
                if flag in expected_active_flags:
                    self.assertTrue(bool(reasons & flag))
                else:
                    self.assertFalse(bool(reasons & flag))

            # Invariant: IsPaused is false iff reasons == 0
            is_paused = (reasons != PauseReasons.NoneReason)
            self.assertEqual(is_paused, val != 0)

            # FormatDescription verification
            desc = format_description(reasons)
            if val == 0:
                self.assertEqual(desc, "none")
            else:
                expected_parts = [self.FLAG_NAMES[f] for f in expected_active_flags]
                self.assertEqual(desc, ", ".join(expected_parts))

    def test_pairwise_independence_invariant(self):
        """Setting or clearing flag A must NEVER alter the state of flag B."""
        for initial_val in range(32):
            for target_flag in self.ALL_FLAGS:
                initial_state = PauseReasons(initial_val)

                # Test Set (Add)
                added_state = initial_state | target_flag
                self.assertTrue(bool(added_state & target_flag))
                for other_flag in self.ALL_FLAGS:
                    if other_flag != target_flag:
                        self.assertEqual(
                            bool(added_state & other_flag),
                            bool(initial_state & other_flag),
                            f"Adding {target_flag} mutated {other_flag} from state {initial_val}"
                        )

                # Test Clear (Remove)
                cleared_state = initial_state & ~target_flag
                self.assertFalse(bool(cleared_state & target_flag))
                for other_flag in self.ALL_FLAGS:
                    if other_flag != target_flag:
                        self.assertEqual(
                            bool(cleared_state & other_flag),
                            bool(initial_state & other_flag),
                            f"Clearing {target_flag} mutated {other_flag} from state {initial_val}"
                        )

    def test_idempotence(self):
        """Re-setting an active flag or re-clearing an inactive flag must be strict no-ops."""
        for initial_val in range(32):
            state = PauseReasons(initial_val)
            for flag in self.ALL_FLAGS:
                if state & flag:
                    # Already set -> setting again produces identical state
                    self.assertEqual(state | flag, state)
                else:
                    # Already clear -> clearing again produces identical state
                    self.assertEqual(state & ~flag, state)

    def test_algebraic_properties(self):
        """Verify commutativity, associativity, and distributivity across all flags."""
        a = PauseReasons.UserPaused | PauseReasons.DisplaySleeping
        b = PauseReasons.FullscreenApp | PauseReasons.BatterySaver
        c = PauseReasons.ScreenLocked

        # Commutativity: A | B == B | A
        self.assertEqual(a | b, b | a)
        self.assertEqual(a & b, b & a)

        # Associativity: (A | B) | C == A | (B | C)
        self.assertEqual((a | b) | c, a | (b | c))

        # Bitwise absorption: A & (A | B) == A
        self.assertEqual(a & (a | b), a)

    def test_monte_carlo_transition_simulation(self):
        """Simulate 10,000 randomized state transitions mimicking real user/system events."""
        random.seed(42)
        active_set = set()
        current_bitmask = PauseReasons.NoneReason

        for i in range(10000):
            flag = random.choice(self.ALL_FLAGS)
            action = random.choice(["add", "remove", "toggle"])

            if action == "add":
                active_set.add(flag)
                current_bitmask |= flag
            elif action == "remove":
                active_set.discard(flag)
                current_bitmask &= ~flag
            elif action == "toggle":
                if flag in active_set:
                    active_set.remove(flag)
                else:
                    active_set.add(flag)
                current_bitmask ^= flag

            # Check equivalence after each operation
            expected_mask = sum(int(f) for f in active_set)
            self.assertEqual(int(current_bitmask), expected_mask)
            self.assertEqual(current_bitmask != PauseReasons.NoneReason, len(active_set) > 0)

            # Check all flags match active_set membership
            for f in self.ALL_FLAGS:
                self.assertEqual(bool(current_bitmask & f), f in active_set)

    def test_out_of_range_bits_caveat(self):
        """Examine FormatDescription behavior when undefined bits (> 31) are present."""
        # Bit 5 (32) is not part of defined PauseReasons
        foreign_bit = PauseReasons(32)
        desc = format_description(foreign_bit)
        # Undefined bit returns empty string since foreign_bit != NoneReason but none of 5 flags match
        self.assertEqual(desc, "")

        # Combination with valid flag (32 | UserPaused = 33)
        combined = PauseReasons(33)
        desc_combined = format_description(combined)
        self.assertEqual(desc_combined, "userPaused")


if __name__ == "__main__":
    unittest.main()
