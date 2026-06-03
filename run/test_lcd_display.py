#!/usr/bin/env python3
"""LCD display test: cycle through all programs, 5s each.

Usage:  python run/test_lcd_display.py [COM_PORT]
Default: COM10
"""
import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else 'COM10'
BAUD = 115200
WAIT = 5
F10 = b'\x1b[21~'
PROMPT = b'RTOS > '

# (command, description, optional extra commands before the 5s wait)
TESTS = [
    ("hello",    "01 HELLO"),
    ("crypto",   "02 CRYPTO — idle"),
    ("crypto",   "02 CRYPTO — bench",  ["bench\r\n"]),
    ("ps2",      "03 KBD"),
    ("snake",    "04 SNAKE"),
    ("info",     "05 INFO"),
    ("riscvasm", "06 RISCV"),
    ("expdemo",  "07 EXP"),
    ("twm",      "08 TWM"),
    ("conway",   "09 CONWAY"),
    ("ntt",      "10 NTT"),
    ("ntt",      "10 NTT — roundtrip", ["roundtrip\r\n"]),
    ("synth",    "11 SYNTH"),
    ("pforth",   "12 PFORTH"),
]


def drain(ser, timeout=1.0):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        n = ser.in_waiting
        if n:
            buf.extend(ser.read(n))
            end = time.time() + timeout
        else:
            time.sleep(0.03)
    return bytes(buf)


def send(ser, data):
    if isinstance(data, str):
        data = data.encode()
    ser.write(data)
    ser.flush()


def wait_prompt(ser, timeout=5.0):
    buf, _ = _read_until(ser, [PROMPT], timeout)
    return PROMPT in buf


def _read_until(ser, patterns, timeout):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        n = ser.in_waiting
        if n:
            buf.extend(ser.read(n))
            for p in patterns:
                if p in buf:
                    return bytes(buf), p
        else:
            time.sleep(0.02)
    return bytes(buf), None


def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.5, dsrdtr=False, rtscts=False)
    time.sleep(0.3)
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # Ensure we're at shell prompt
    send(ser, '\r\n')
    drain(ser, 1.0)
    send(ser, '\r\n')
    if not wait_prompt(ser, 3.0):
        print("WARNING: shell prompt not detected, continuing anyway...\n")
    else:
        drain(ser, 0.3)

    print("=== LCD Display Test ===")
    print(f"Port: {PORT}  Baud: {BAUD}  Wait: {WAIT}s per program\n")

    for entry in TESTS:
        cmd = entry[0]
        desc = entry[1]
        extras = entry[2] if len(entry) > 2 else None

        print(f"[{desc}]  send: {cmd}")
        send(ser, cmd + '\r\n')
        drain(ser, 2.0)

        if extras:
            for ex in extras:
                time.sleep(0.5)
                print(f"  sub: {ex.strip()}")
                send(ser, ex)
                drain(ser, 1.0)

        print(f"  >> observe LCD for {WAIT}s...")
        time.sleep(WAIT)

        # Exit with F10
        print(f"  exit (F10)")
        send(ser, F10)
        drain(ser, 1.0)

        # Return to shell
        send(ser, '\r\n')
        if wait_prompt(ser, 3.0):
            print(f"  OK — back at shell\n")
        else:
            print(f"  WARN — prompt not seen, sending extra CR\n")
            send(ser, '\r\n')
            drain(ser, 1.0)

    # Final: show shell idle LCD
    print("[00 SHELL]  idle state")
    print(f"  >> observe LCD for {WAIT}s...")
    time.sleep(WAIT)

    print("=== Done ===")
    ser.close()


if __name__ == '__main__':
    main()
