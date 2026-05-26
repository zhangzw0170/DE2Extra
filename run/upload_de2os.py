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
FOLLOW_AFTER_BOOT = int(os.getenv('DE2OS_UPLOAD_FOLLOW', '0')) != 0
LEGACY_BOOT_BAUD = 19200
PROMPT = b'CMD:> '
SOFT_BOOT_REQ = b'\x00BOOT\x00'


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
    buf, matched = read_until(ser, (PROMPT, b'Auto-boot'), initial_timeout)
    if matched != PROMPT:
        ser.write(b' ')
        ser.flush()
        more, matched = read_until(ser, (PROMPT,), prompt_timeout)
        buf += more
    return matched == PROMPT, buf


def wait_for_prompt_with_abort(ser, initial_timeout, prompt_timeout):
    captured = bytearray()
    end = time.time() + initial_timeout
    while time.time() < end:
        ser.write(b' ')
        ser.flush()
        buf, matched = read_until(ser, (PROMPT, b'Auto-boot'), timeout=0.20)
        captured.extend(buf)
        if matched == PROMPT:
            return True, bytes(captured)
        if matched == b'Auto-boot':
            ser.write(b' ')
            ser.flush()
            more, matched = read_until(ser, (PROMPT,), prompt_timeout)
            captured.extend(more)
            return matched == PROMPT, bytes(captured)
        time.sleep(0.03)
    return False, bytes(captured)


def try_soft_bootloader(port):
    tried = []
    for baud in (BAUD_APP, BAUD_BOOT, LEGACY_BOOT_BAUD):
        if baud in tried:
            continue
        tried.append(baud)
        ser = open_serial(port, baud)
        try:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            log(f'Trying soft reboot via UART on {port} @ {baud}...')
            ser.write(SOFT_BOOT_REQ)
            ser.flush()
            ready, _ = wait_for_prompt(ser, initial_timeout=5.0, prompt_timeout=3.0)
            if ready:
                return ser, baud
        except serial.SerialException:
            ser.close()
            raise
        ser.close()
    return None, None


def connect_bootloader(port, wait_mode):
    if wait_mode:
        ser, baud = try_soft_bootloader(port)
        if ser is not None:
            return ser, baud

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
                log('Soft reboot did not reach bootloader, falling back to KEY0.')
                log(f'Waiting for bootloader on {port} @ {baud}...')
                log('Press KEY0 now.')
                ready, banner = wait_for_prompt(ser, initial_timeout=25.0, prompt_timeout=3.0)
            else:
                log(f'Connecting to {port} @ {baud}...')
                time.sleep(0.25)
                ready, banner = wait_for_prompt_with_abort(ser, initial_timeout=12.0, prompt_timeout=3.0)

            if ready:
                if banner:
                    log('\n[bootloader ready]\n')
                time.sleep(0.10)
                extra = drain(ser, 0.20)
                if extra:
                    write_out(extra)
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
    log('Boot command sent.')

    if FOLLOW_AFTER_BOOT:
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
