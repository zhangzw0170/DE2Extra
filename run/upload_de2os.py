#!/usr/bin/env python3
"""Upload neorv32_exe.bin to NEORV32 bootloader via UART.

Usage:  python upload_de2os.py [COM_PORT] [BIN_FILE] [--wait]

  --wait : wait for KEY0 reset + bootloader banner (use when board already running)
  default: assume bootloader just started after JTAG config, upload immediately

Defaults: COM10, ../sw/app/de2os/neorv32_exe.bin
Environment:
  NEORV32_BOOT_BAUD / DE2OS_BOOT_BAUD : override bootloader baud (default 115200)
  NEORV32_APP_BAUD  / DE2OS_APP_BAUD  : override app baud        (default 115200)
"""
import os
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else 'COM10'
BINFILE = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('-') else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'sw', 'app', 'de2os', 'neorv32_exe.bin')
WAIT = '--wait' in sys.argv

BAUD_BOOT = int(os.getenv('DE2OS_BOOT_BAUD', os.getenv('NEORV32_BOOT_BAUD', '115200')))
BAUD_APP = int(os.getenv('DE2OS_APP_BAUD', os.getenv('NEORV32_APP_BAUD', '115200')))
LEGACY_BOOT_BAUD = 19200
PROMPT = b'CMD:> '


def log(msg):
    print(msg, flush=True)


def write_out(data):
    if data:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def drain(ser, timeout=0.5):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        n = ser.in_waiting
        if n:
            buf.extend(ser.read(n))
            end = time.time() + timeout
        else:
            time.sleep(0.02)
    return bytes(buf)


def read_until(ser, patterns, timeout, echo=True):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        n = ser.in_waiting
        if n:
            chunk = ser.read(n)
            buf.extend(chunk)
            if echo:
                write_out(chunk)
            for pattern in patterns:
                if pattern in buf:
                    return bytes(buf), pattern
        else:
            time.sleep(0.02)
    return bytes(buf), None


def open_serial(port, baud):
    return serial.Serial(port, baud, timeout=0.05, write_timeout=2)


def wait_for_prompt(ser, initial_timeout, prompt_timeout):
    _, matched = read_until(ser, (PROMPT, b'Auto-boot'), initial_timeout)
    if matched != PROMPT:
        ser.write(b' ')
        ser.flush()
        _, matched = read_until(ser, (PROMPT,), prompt_timeout)
    return matched == PROMPT


def connect_bootloader(port, wait_mode):
    tried = []
    for baud in (BAUD_BOOT, LEGACY_BOOT_BAUD):
        if baud in tried:
            continue
        tried.append(baud)

        ser = open_serial(port, baud)
        try:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            if wait_mode:
                log(f'Waiting for bootloader on {port} @ {baud}...')
                log('Press KEY0 now.')
                ready = wait_for_prompt(ser, initial_timeout=20.0, prompt_timeout=2.5)
            else:
                log(f'Connecting to {port} @ {baud}...')
                time.sleep(0.25)
                ready = wait_for_prompt(ser, initial_timeout=1.5, prompt_timeout=2.5)

            if ready:
                return ser, baud
        except serial.SerialException:
            ser.close()
            raise

        ser.close()

    raise RuntimeError(
        f'Bootloader prompt not detected on {port}. Tried {", ".join(str(b) for b in tried)} baud.')


def upload_bytes(ser, data, baud):
    # Keep writes below the Windows serial driver's buffering threshold.
    chunk_size = 1024 if baud >= 115200 else 256
    for i in range(0, len(data), chunk_size):
        chunk = data[i:i + chunk_size]
        ser.write(chunk)
        ser.flush()
        if baud < 115200:
            time.sleep(len(chunk) * 10 / baud * 0.05)


ser, active_boot_baud = connect_bootloader(PORT, WAIT)

try:
    ser.write(b'u')
    ser.flush()
    _, matched = read_until(ser, (b'Awaiting',), timeout=3.0)
    if matched != b'Awaiting':
        raise RuntimeError('Bootloader did not enter upload mode.')

    with open(BINFILE, 'rb') as f:
        data = f.read()
    log(f'Uploading {len(data)} bytes @ {active_boot_baud}...')
    upload_bytes(ser, data, active_boot_baud)

    resp, _ = read_until(ser, (b'OK', b'ERROR', PROMPT), timeout=max(3.0, len(data) * 10 / active_boot_baud + 2.0))
    if not resp:
        resp = drain(ser, 1.0)
        write_out(resp)

    if b'OK' in resp:
        log('Upload OK!')
    else:
        log('Upload status unclear...')
        raise RuntimeError('Upload failed: bootloader did not respond with OK')

    ser.write(b'e')
    ser.flush()
    time.sleep(0.2)
    write_out(drain(ser, 0.8))

    if ser.baudrate != BAUD_APP:
        ser.baudrate = BAUD_APP
    log(f'\n--- @ {BAUD_APP} ---')
    time.sleep(0.5)
    buf = drain(ser, 2.0)
    if buf:
        write_out(buf)
    else:
        log('(no output)')

    for _ in range(60):
        if ser.in_waiting:
            write_out(ser.read(ser.in_waiting))
        time.sleep(0.1)
finally:
    ser.close()

log('\n--- End ---')
