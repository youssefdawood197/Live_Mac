#!/usr/bin/env python3
"""
Milestone 4 Windows Architecture & Scaffolding Challenger Test Runner.
Executes all verification suites across:
1. FlakeOverlayWindow (Win32 window styles, WS_EX_TRANSPARENT toggle, WM_MOUSEACTIVATE = 3, coordinate handling)
2. WorkerWInjector (Progman 0x052C handshake, 1000ms timeout, Explorer crash / TaskbarCreated recovery)
3. PauseReasons (Powers of two, 32-permutation decomposition, additive independence, 10,000-state Monte Carlo)
4. LivelyInfo (JSON schema, polymorphic types, case insensitivity, path resolution, legacy aliases)
"""

import sys
import unittest
import time

import test_flake_overlay_window
import test_workerw_injector
import test_pause_reasons
import test_lively_info

def main():
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    suite.addTests(loader.loadTestsFromModule(test_flake_overlay_window))
    suite.addTests(loader.loadTestsFromModule(test_workerw_injector))
    suite.addTests(loader.loadTestsFromModule(test_pause_reasons))
    suite.addTests(loader.loadTestsFromModule(test_lively_info))

    print("=" * 70)
    print("M4 Windows Architecture & Scaffolding: Challenger Test Runner")
    print("=" * 70)

    start_time = time.perf_counter()
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    elapsed = time.perf_counter() - start_time

    print("\n" + "=" * 70)
    print(f"Summary: Ran {result.testsRun} tests in {elapsed:.3f}s")
    print(f"Errors: {len(result.errors)}, Failures: {len(result.failures)}")
    print("=" * 70)

    if result.wasSuccessful():
        print("ALL CHALLENGER VERIFICATION TESTS PASSED SUCCESSFULLY.")
        sys.exit(0)
    else:
        print("CHALLENGER VERIFICATION FAILED.")
        sys.exit(1)

if __name__ == "__main__":
    main()
