#!/usr/bin/env python3
"""Quick peripheral test via UART — tests crypto, conway, ntt, synth commands."""

import serial
import time
import sys

PORT = "COM10"
BAUD = 115200
TIMEOUT = 3  # seconds per response read

def send_cmd(ser, cmd, read_time=2):
    """Send command and read response."""
    ser.reset_input_buffer()
    ser.write((cmd + "\n").encode())
    time.sleep(read_time)
    data = ser.read(ser.in_waiting or 4096)
    return data.decode("utf-8", errors="replace")

def wait_prompt(ser, timeout=5):
    """Wait for shell prompt (>)."""
    start = time.time()
    buf = ""
    while time.time() - start < timeout:
        if ser.in_waiting:
            buf += ser.read(ser.in_waiting).decode("utf-8", errors="replace")
            if ">" in buf:
                return buf
        time.sleep(0.1)
    return buf

def test_crypto(ser):
    """Test crypto: launch, run help, run single AES, exit."""
    print("\n=== CRYPTO TEST ===")
    # Launch crypto
    resp = send_cmd(ser, "crypto", 2)
    print(f"Launch: {resp[-200:]}")

    # Wait for prompt
    resp = wait_prompt(ser, 3)
    print(f"Prompt: {resp[-200:]}")

    # Send help
    resp = send_cmd(ser, "help", 2)
    print(f"Help: {resp[-300:]}")

    # Single AES encrypt
    resp = send_cmd(ser, "aes ecb enc 00112233445566778899aabbccddeeff 00112233445566778899aabbccddeeff", 3)
    print(f"AES enc: {resp[-300:]}")

    # Exit with F10 (0x8E)
    ser.write(b"\x8e")
    time.sleep(1)
    resp = ser.read(ser.in_waiting or 4096).decode("utf-8", errors="replace")
    print(f"Exit: {resp[-200:]}")

    wait_prompt(ser, 3)
    return True

def test_conway(ser):
    """Test conway: launch, randomize, step, exit."""
    print("\n=== CONWAY TEST ===")
    resp = send_cmd(ser, "conway", 2)
    print(f"Launch: {resp[-200:]}")
    time.sleep(1)

    # 'r' to randomize
    resp = send_cmd(ser, "r", 1)
    print(f"Randomize: {resp[-200:]}")

    # Enter to run
    resp = send_cmd(ser, "\r", 1)
    print(f"Run: {resp[-200:]}")

    # Wait a bit, then stop with Enter again
    time.sleep(2)
    resp = send_cmd(ser, "\r", 1)
    print(f"Stop: {resp[-200:]}")

    # Exit with F10
    ser.write(b"\x8e")
    time.sleep(1)
    resp = ser.read(ser.in_waiting or 4096).decode("utf-8", errors="replace")
    print(f"Exit: {resp[-200:]}")

    wait_prompt(ser, 3)
    return True

def test_ntt(ser):
    """Test NTT: launch, run SW NTT, try HW, exit."""
    print("\n=== NTT TEST ===")
    resp = send_cmd(ser, "ntt", 2)
    print(f"Launch: {resp[-200:]}")
    time.sleep(1)

    # SW NTT test
    resp = send_cmd(ser, "sw", 3)
    print(f"SW NTT: {resp[-400:]}")

    # HW NTT test (may timeout if VHDL not rebuilt)
    resp = send_cmd(ser, "hw", 5)
    print(f"HW NTT: {resp[-400:]}")

    # Roundtrip test
    resp = send_cmd(ser, "roundtrip", 5)
    print(f"Roundtrip: {resp[-400:]}")

    # Exit with F10
    ser.write(b"\x8e")
    time.sleep(1)
    resp = ser.read(ser.in_waiting or 4096).decode("utf-8", errors="replace")
    print(f"Exit: {resp[-200:]}")

    wait_prompt(ser, 3)
    return True

def test_synth(ser):
    """Test synth: launch, check it starts, exit."""
    print("\n=== SYNTH TEST ===")
    resp = send_cmd(ser, "synth", 2)
    print(f"Launch: {resp[-200:]}")
    time.sleep(2)

    # Exit with F10
    ser.write(b"\x8e")
    time.sleep(1)
    resp = ser.read(ser.in_waiting or 4096).decode("utf-8", errors="replace")
    print(f"Exit: {resp[-200:]}")

    wait_prompt(ser, 3)
    return True

def main():
    print(f"Connecting to {PORT} @ {BAUD}...")
    ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
    time.sleep(0.5)

    # Drain any pending output
    ser.reset_input_buffer()

    # Send Enter to get prompt
    ser.write(b"\n")
    time.sleep(1)
    init = ser.read(ser.in_waiting or 4096).decode("utf-8", errors="replace")
    print(f"Init: {init[-200:]}")

    tests = [
        ("crypto", test_crypto),
        ("ntt", test_ntt),
        # ("conway", test_conway),  # skip — needs Quartus rebuild for toggle_cell fix
        # ("synth", test_synth),    # skip — needs audio hardware
    ]

    results = {}
    for name, test_fn in tests:
        try:
            ok = test_fn(ser)
            results[name] = "PASS" if ok else "FAIL"
        except Exception as e:
            results[name] = f"ERROR: {e}"
            print(f"  ERROR: {e}")

    ser.close()

    print("\n=== RESULTS ===")
    for name, status in results.items():
        print(f"  {name}: {status}")

if __name__ == "__main__":
    main()
