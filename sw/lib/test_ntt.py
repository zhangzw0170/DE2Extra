#!/usr/bin/env python3
"""test_ntt.py — NTT command test suite via serial

Usage: python test_ntt.py [--port COM10] [--baud 115200]

Runs all NTT CLI commands, captures serial output, validates expected patterns.
"""

import serial, sys, time, argparse, re

PORT = "COM10"
BAUD = 115200
TIMEOUT = 10  # seconds per command group


def send(ser, cmd, wait=1.0):
    """Send a command, drain old output, wait for response."""
    time.sleep(0.1)
    ser.read(ser.in_waiting or 4096)  # drain
    ser.write((cmd + "\n").encode())
    time.sleep(wait)
    n = ser.in_waiting or 1
    return ser.read(n).decode("utf-8", errors="replace")


def enter_ntt(ser):
    """Start the ntt program from shell, wait for prompt."""
    resp = send(ser, "ntt", wait=2)
    if "ntt >" not in resp:
        print(f"FATAL: Cannot enter ntt program. Got: {repr(resp)}")
        sys.exit(1)
    return resp


def quit_ntt(ser):
    send(ser, "quit", wait=1)


def expect(resp, pattern, label=""):
    """Check that response contains expected pattern."""
    m = re.search(pattern, resp, re.MULTILINE)
    if m:
        print(f"  PASS  {label}")
        return True
    else:
        print(f"  FAIL  {label}")
        print(f"        got: {resp.strip()[:200]}")
        return False


def run_tests(port, baud):
    passed = 0
    failed = 0

    ser = serial.Serial(port, baud, timeout=TIMEOUT)
    time.sleep(0.3)
    ser.read(ser.in_waiting or 4096)

    try:
        print("=== Entering NTT program ===")
        enter_ntt(ser)
        passed += 1

        # ---- help ----
        print("\n--- help ---")
        resp = send(ser, "help", wait=1)
        if expect(resp, "roundtrip|NTT.*number", "shows help text"):
            passed += 1
        else:
            failed += 1

        # ---- load delta ----
        print("\n--- load delta ---")
        resp = send(ser, "load delta", wait=1)
        if expect(resp, "delta.*1.*0.*0", "loads delta input"):
            passed += 1
        else:
            failed += 1

        # ---- dump (should show 0001 at position 0) ----
        print("\n--- dump ---")
        resp = send(ser, "dump", wait=1)
        if expect(resp, "0001 ", "dump shows data"):
            passed += 1
        else:
            failed += 1

        # ---- diag ----
        print("\n--- diag ---")
        resp = send(ser, "diag", wait=5)
        diag_pass = True
        if not expect(resp, "data\[0\].*OK", "data[0] write/readback"):
            diag_pass = False; failed += 1
        if not expect(resp, "Engine done", "engine completes"):
            diag_pass = False; failed += 1
        if diag_pass:
            passed += 1  # count as one test
        else:
            failed += 1

        # ---- ntt (forward NTT) ----
        print("\n--- ntt (forward) ---")
        resp = send(ser, "ntt", wait=3)
        if expect(resp, "HW NTT done", "NTT completes"):
            passed += 1
        else:
            failed += 1

        # ---- dump after ntt ----
        print("\n--- dump after ntt ---")
        resp = send(ser, "dump", wait=1)
        if expect(resp, "HW data.*first 32", "dump shows data"):
            passed += 1
        else:
            failed += 1

        # ---- intt (inverse NTT) ----
        print("\n--- intt ---")
        # Reload delta first since ntt mutated the buffer
        send(ser, "load delta", wait=1)
        resp = send(ser, "intt", wait=3)
        if expect(resp, "HW INTT done", "INTT completes"):
            passed += 1
        else:
            failed += 1

        # ---- roundtrip ----
        print("\n--- roundtrip ---")
        send(ser, "load delta", wait=1)
        resp = send(ser, "roundtrip", wait=6)
        if expect(resp, "PASS", "roundtrip passes"):
            passed += 1
        else:
            failed += 1

        # ---- bfly (VHDL butterfly sim, if available) ----
        print("\n--- bfly (butterfly sim) ---")
        send(ser, "load delta", wait=1)
        resp = send(ser, "bfly", wait=5)
        bfly_pass = True
        if not expect(resp, "Result:", "bfly produces result"):
            bfly_pass = False; failed += 1
        if bfly_pass and "PASS" in resp:
            passed += 1
        elif bfly_pass and "MATCH" in resp:
            passed += 1
        else:
            failed += 1

        # ---- quit ----
        print("\n--- quit ---")
        resp = send(ser, "quit", wait=1)
        if expect(resp, "returned to shell", "exits to shell"):
            passed += 1
        else:
            failed += 1

    finally:
        ser.close()

    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed, {passed + failed} total")
    print(f"{'='*50}")
    return failed == 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="NTT command test suite")
    ap.add_argument("--port", default=PORT)
    ap.add_argument("--baud", type=int, default=BAUD)
    args = ap.parse_args()
    ok = run_tests(args.port, args.baud)
    sys.exit(0 if ok else 1)
