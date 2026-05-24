#!/usr/bin/env python3
"""Upload neorv32_exe.bin to NEORV32 bootloader via UART.

Usage:  python upload_de2os.py [COM_PORT] [BIN_FILE] [--wait]

  --wait : wait for KEY0 reset + bootloader banner (use when board already running)
  default: assume bootloader just started after JTAG config, upload immediately

Defaults: COM10, ../sw/app/de2os/neorv32_exe.bin
"""
import serial, time, sys, os

PORT    = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else 'COM10'
BINFILE = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('-') else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'sw', 'app', 'de2os', 'neorv32_exe.bin')
WAIT    = '--wait' in sys.argv

BAUD_BOOT = 19200
BAUD_APP  = 115200

def drain(ser, timeout=1):
    buf = b''
    end = time.time() + timeout
    while time.time() < end:
        n = ser.in_waiting
        if n:
            buf += ser.read(n)
        else:
            time.sleep(0.05)
    return buf

ser = serial.Serial(PORT, BAUD_BOOT, timeout=1)

if WAIT:
    # Wait for user to press KEY0
    print(f'Waiting for bootloader on {PORT} @ {BAUD_BOOT}...')
    print('Press KEY0 now.')
    banner = b''
    t0 = time.time()
    while time.time() - t0 < 20:
        n = ser.in_waiting
        if n:
            chunk = ser.read(n)
            banner += chunk
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if b'CMD' in banner:
                break
        time.sleep(0.05)
    # Abort auto-boot if needed
    if b'Auto-boot' in banner:
        time.sleep(0.2)
        ser.write(b' ')
        time.sleep(0.5)
        drain(ser, 1)
else:
    # JTAG just configured FPGA — bootloader is printing banner right now
    # Drain the banner, then send a space to stop auto-boot
    print(f'Connecting to {PORT} @ {BAUD_BOOT}...')
    time.sleep(1)  # let bootloader start printing
    banner = drain(ser, 3)
    if banner:
        sys.stdout.buffer.write(banner)
        sys.stdout.buffer.flush()

    # Stop auto-boot countdown
    ser.write(b' ')
    time.sleep(0.5)
    resp = drain(ser, 1)
    sys.stdout.buffer.write(resp)
    sys.stdout.buffer.flush()

# Send 'u' and wait for prompt
ser.write(b'u')
t0 = time.time()
while time.time() - t0 < 5:
    n = ser.in_waiting
    if n:
        chunk = ser.read(n)
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        if b'Awaiting' in chunk:
            break
    time.sleep(0.05)
time.sleep(0.2)

# Send binary in chunks
with open(BINFILE, 'rb') as f:
    data = f.read()
print(f'Uploading {len(data)} bytes...')
CHUNK = 256
for i in range(0, len(data), CHUNK):
    ser.write(data[i:i+CHUNK])
    time.sleep(CHUNK * 10 / BAUD_BOOT * 1.3)

resp = drain(ser, 3)
sys.stdout.buffer.write(resp)
sys.stdout.buffer.flush()

if b'OK' in resp:
    print('Upload OK!')
else:
    print('Upload status unclear...')

# Execute
ser.write(b'e')
time.sleep(1)
resp = drain(ser, 2)
sys.stdout.buffer.write(resp)
sys.stdout.buffer.flush()

# Read app output at 115200
ser.baudrate = BAUD_APP
print(f'\n--- @ {BAUD_APP} ---')
time.sleep(2)
buf = drain(ser, 5)
if buf:
    sys.stdout.buffer.write(buf)
    sys.stdout.buffer.flush()
else:
    print('(no output)')

for _ in range(60):
    if ser.in_waiting:
        sys.stdout.buffer.write(ser.read(ser.in_waiting))
        sys.stdout.buffer.flush()
    time.sleep(0.1)

ser.close()
print('\n--- End ---')
