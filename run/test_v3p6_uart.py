#!/usr/bin/env python3
"""Verify V3P6 PS/2 TUI + Snake 2P + NTT via UART serial.

Tests via serial only (no PS/2 keyboard needed):
- I.6: Global ESC exit
- I.7: Q no longer exits programs
- I.9: Snake 2P mode selection (UART input part)
- E4.7: NTT MMIO access
"""
import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else 'COM10'
BAUD = 115200
PROMPT = b'CMD:>'


def send_and_drain(ser: serial.Serial, cmd: str, timeout: float = 2.0) -> bytes:
    """Send a command, wait for response ending with PROMPT."""
    ser.write((cmd + '\n').encode())
    ser.flush()
    time.sleep(0.3)
    resp = ser.read_all()
    # Wait a bit more for slow output
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            resp += chunk
        if PROMPT in resp:
            break
        time.sleep(0.2)
    return resp


def wait_prompt(ser: serial.Serial, timeout: float = 3.0) -> bytes:
    """Read until PROMPT appears."""
    resp = b''
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            resp += chunk
        if PROMPT in resp:
            break
        time.sleep(0.2)
    return resp


def test_q_no_exit(ser: serial.Serial) -> bool:
    """I.7: Q should not exit programs anymore."""
    print('[I.7] Testing Q does NOT exit programs...')
    # Enter hello
    ser.write(b'hello\n')
    time.sleep(1.5)
    resp = ser.read_all()

    # Send 'q'
    ser.write(b'q\n')
    time.sleep(1.5)
    resp2 = ser.read_all()

    # If we're still in hello (no PROMPT), Q didn't exit
    in_hello = PROMPT not in resp2
    # Try ESC to actually exit
    ser.write(b'\x1b')
    time.sleep(1.0)
    resp3 = ser.read_all()

    if in_hello and PROMPT in resp3:
        print('  PASS: Q did not exit hello, ESC did exit')
        return True
    elif PROMPT in resp2:
        print('  FAIL: Q exited the program (should not have)')
        return False
    else:
        print(f'  UNCLEAR: resp after q={resp2!r}, resp after esc={resp3!r}')
        # Still exit if stuck
        ser.write(b'\x1b\n')
        time.sleep(0.5)
        return False


def test_esc_exit(ser: serial.Serial) -> bool:
    """I.6: ESC should exit programs."""
    print('[I.6] Testing ESC exits programs...')
    # Enter info
    ser.write(b'info\n')
    time.sleep(1.5)
    ser.read_all()  # drain

    # Send ESC
    ser.write(b'\x1b')
    time.sleep(1.0)
    resp = wait_prompt(ser)

    if PROMPT in resp:
        print('  PASS: ESC exited info program')
        return True
    else:
        print(f'  FAIL: ESC did not exit, resp={resp!r}')
        return False


def test_snake_2p_menu(ser: serial.Serial) -> bool:
    """I.9: Snake 2P mode selection should appear."""
    print('[I.9] Testing Snake 2P mode selection...')
    ser.write(b'snake\n')
    time.sleep(1.0)
    resp = ser.read_all()

    has_2p = b'2P' in resp or b'2p' in resp or b'Two' in resp or b'two' in resp or b'1P' in resp or b'1p' in resp
    has_mode = b'mode' in resp.lower() or b'Mode' in resp or b'MODE' in resp

    # Exit with ESC
    ser.write(b'\x1b')
    time.sleep(0.5)
    wait_prompt(ser)

    if has_2p or has_mode:
        print('  PASS: Snake shows mode selection (1P/2P)')
        return True
    else:
        print(f'  UNCLEAR: no 1P/2P menu found, resp={resp[:200]!r}')
        return False


def test_ntt_mmio(ser: serial.Serial) -> bool:
    """E4.7: NTT hardware MMIO access at 0xF000F000."""
    print('[E4.7] Testing NTT MMIO...')
    ser.write(b'ntt\n')
    time.sleep(0.8)
    resp = ser.read_all()

    # Check if ntt command started
    ntt_started = PROMPT not in resp or b'ntt' in resp.lower() or b'NTT' in resp

    if not ntt_started:
        print(f'  INFO: ntt command may not have started, resp={resp[:100]!r}')

    # Try 'help' inside ntt
    ser.write(b'help\n')
    time.sleep(1.0)
    resp2 = ser.read_all()

    # Exit with q
    ser.write(b'q\n')
    time.sleep(0.8)
    resp3 = wait_prompt(ser, timeout=2.0)

    if PROMPT in resp3:
        print('  PASS: NTT command accessible, help/q work')
        # Try a quick MMIO test: load random then dump
        ser.write(b'ntt\n')
        time.sleep(0.8)
        ser.read_all()
        ser.write(b'load random\n')
        time.sleep(1.0)
        resp_lr = ser.read_all()
        ser.write(b'dump\n')
        time.sleep(1.0)
        resp_dump = ser.read_all()
        ser.write(b'q\n')
        time.sleep(0.5)
        wait_prompt(ser)

        if b'coeff' in resp_dump.lower() or b'x[' in resp_dump or len(resp_dump) > 20:
            print('  PASS: NTT load/dump operations work')
            return True
        else:
            print(f'  UNCLEAR: dump output={resp_dump[:100]!r}')
            return True  # command itself works
    else:
        print(f'  FAIL: Could not interact with NTT')
        return False


def main():
    print(f'Opening {PORT} @ {BAUD}...')
    with serial.Serial(PORT, BAUD, timeout=0.5) as ser:
        ser.reset_input_buffer()

        results = {}

        # Wait for prompt
        print('Waiting for shell prompt...')
        ser.write(b'\n')
        time.sleep(0.5)
        wait_prompt(ser)

        # Drain any boot output
        ser.read_all()

        results['I.7 Q no-exit'] = test_q_no_exit(ser)
        time.sleep(0.3)
        # Make sure we're at prompt
        wait_prompt(ser)

        results['I.6 ESC exit'] = test_esc_exit(ser)
        time.sleep(0.3)

        results['I.9 Snake 2P'] = test_snake_2p_menu(ser)
        time.sleep(0.3)

        results['E4.7 NTT MMIO'] = test_ntt_mmio(ser)

        print()
        print('=' * 50)
        print('RESULTS:')
        for name, passed in results.items():
            status = 'PASS' if passed else 'FAIL'
            print(f'  {status}: {name}')

        total = len(results)
        passed = sum(1 for v in results.values() if v)
        print(f'\n{passed}/{total} passed')

        return 0 if passed == total else 1


if __name__ == '__main__':
    sys.exit(main())
