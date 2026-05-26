#!/usr/bin/env python3
"""Capture VGA text snapshots from de2shell_rtos over UART."""

from __future__ import annotations

import argparse
import os
import re
import sys
import time

import serial


DEFAULT_PORT = os.getenv("DE2OS_COM", "COM10")
DEFAULT_BAUD = int(os.getenv("DE2OS_APP_BAUD", os.getenv("NEORV32_APP_BAUD", "115200")))
CSI_RE = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC_RE = re.compile(rb"\x1b\][^\x07]*(?:\x07|\x1b\\)")
START_MARK = b"[VGA SNAPSHOT "
END_MARK = b"[END VGA SNAPSHOT]"


def strip_ansi(data: bytes) -> bytes:
    data = OSC_RE.sub(b"", data)
    data = CSI_RE.sub(b"", data)
    return data.replace(b"\r", b"")


def read_snapshot_blocks(ser: serial.Serial, count: int, timeout: float) -> list[str]:
    blocks: list[str] = []
    buf = bytearray()
    deadline = time.time() + timeout

    while time.time() < deadline and len(blocks) < count:
        n = ser.in_waiting
        if n:
            buf.extend(strip_ansi(ser.read(n)))
            deadline = time.time() + timeout
            while True:
                start = buf.find(START_MARK)
                if start < 0:
                    break
                end = buf.find(END_MARK, start)
                if end < 0:
                    break
                end = buf.find(b"\n", end)
                if end < 0:
                    break
                block = bytes(buf[start:end + 1]).decode("utf-8", errors="replace")
                blocks.append(block)
                del buf[:end + 1]
                if len(blocks) >= count:
                    break
        else:
            time.sleep(0.05)

    return blocks


def main() -> int:
    ap = argparse.ArgumentParser(description="Capture VGA text snapshots from de2shell_rtos.")
    ap.add_argument("port", nargs="?", default=DEFAULT_PORT, help=f"serial port (default: {DEFAULT_PORT})")
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"serial baud (default: {DEFAULT_BAUD})")
    ap.add_argument("--period", type=int, default=2, help="seconds for vgamon mode (default: 2)")
    ap.add_argument("--count", type=int, default=1, help="number of snapshots to capture (default: 1)")
    ap.add_argument("--timeout", type=float, default=4.0, help="idle timeout per snapshot window in seconds")
    args = ap.parse_args()

    if args.count < 1:
        ap.error("--count must be >= 1")
    if not 1 <= args.period <= 60:
        ap.error("--period must be in 1..60")

    ser = serial.Serial(args.port, args.baud, timeout=0.05, write_timeout=1)
    try:
        time.sleep(0.2)
        if ser.in_waiting:
            ser.read(ser.in_waiting)

        if args.count == 1:
            ser.write(b"vgadump\r")
        elif args.period == 2:
            ser.write(b"vgamon\r")
        else:
            ser.write(f"vgamon {args.period}\r".encode("ascii"))
        ser.flush()

        blocks = read_snapshot_blocks(
            ser,
            count=args.count,
            timeout=max(args.timeout, float(args.period) + 2.0),
        )

        if args.count > 1:
            ser.write(b"vgamon off\r")
            ser.flush()

        if not blocks:
            print("No VGA snapshot received.", file=sys.stderr)
            return 1

        for i, block in enumerate(blocks):
            if i:
                print()
            sys.stdout.write(block)
        return 0
    finally:
        ser.close()


if __name__ == "__main__":
    raise SystemExit(main())
