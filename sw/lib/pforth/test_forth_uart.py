#!/usr/bin/env python3
"""Test pForth on DE2-115 via UART serial mirror.

Usage: python test_forth_uart.py [COM_PORT]

Expects pForth already running on the board (send 'pforth' first).
Results are unreliable when status bar escape sequences corrupt output lines.
"""

import sys, serial, time, re

PORT = sys.argv[1] if len(sys.argv) > 1 else 'COM10'
BAUD = 115200

def drain(s):
    time.sleep(0.3)
    while s.in_waiting: s.read(s.in_waiting)

def send_read(s, cmd, wait=3):
    drain(s)
    s.write((cmd + '\r').encode())
    time.sleep(wait)
    raw = b''
    while s.in_waiting:
        raw += s.read(min(s.in_waiting, 4096))
        time.sleep(0.2)
    text = raw.decode('latin-1', errors='replace')
    clean = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
    lines = [l.strip() for l in clean.split('\n') if l.strip() and 'DE2Extra' not in l]
    output = []
    for l in lines:
        if l == cmd or l.startswith(cmd): continue
        if l.startswith('OK') or l.startswith('ERR'): continue
        if l.startswith('>'): continue
        output.append(l)
    return ' '.join(output)

TESTS = {
    'Arithmetic': [
        ('1 2 + .',              '3'),
        ('10 3 - .',             '7'),
        ('6 7 * .',              '42'),
        ('20 4 / .',             '5'),
        ('17 5 MOD .',           '2'),
        ('17 5 /MOD . .',        '3 2'),
        ('-7 ABS .',             '7'),
        ('5 NEGATE .',           '-5'),
    ],
    'Compare': [
        ('1 1 = .',              '-1'),
        ('1 0 = .',              '0'),
        ('1 2 < .',              '-1'),
        ('2 1 > .',              '-1'),
        ('0 0= .',               '-1'),
        ('-3 0< .',              '-1'),
    ],
    'Logic': [
        ('-1 -1 AND .',          '-1'),
        ('0 -1 AND .',           '0'),
        ('-1 0 OR .',            '-1'),
        ('0 NOT .',              '-1'),
    ],
    'Stack': [
        ('1 DUP . .',            '1 1'),
        ('1 2 DROP .',           '1'),
        ('1 2 SWAP . .',         '1 2'),
        ('1 2 3 ROT . . . .',   '1 3 2 3'),
        ('1 2 3 OVER . . . .',  '2 3 2 1'),
    ],
    'Control': [
        ('1 IF 99 ELSE 88 THEN .',         '99'),
        ('0 IF 99 ELSE 88 THEN .',         '88'),
        ('5 0 DO I . LOOP',                '0 1 2 3 4'),
        ('0 5 1 -DO I . LOOP',             '4 3 2 1 0'),
        ('5 0 DO I 3 + LOOP',              '3 4 5 6 7'),
        ('10 BEGIN DUP 1 > WHILE DUP . 1 - REPEAT', '10 9 8 7 6 5 4 3 2'),
    ],
    'Define': [
        (': square dup * ;',       ''),
        ('10 square .',            '100'),
        (': max 2DUP > IF DROP ELSE DROP THEN ;', ''),
        ('3 7 max .',              '7'),
        (': abs DUP 0< IF NEGATE THEN ;', ''),
        ('-5 abs .',               '5'),
    ],
    'Memory': [
        ('VARIABLE X',             ''),
        ('42 X !',                 ''),
        ('X @ .',                  '42'),
        ('CREATE Y 99 ,',         ''),
        ('Y @ .',                  '99'),
        ('1 CELLS .',              '4'),
    ],
    'Output': [
        ('72 EMIT',                'H'),
        ('.( Hello)',              'Hello'),
        ('S\" World\" TYPE',       'World'),
        ('CR',                     ''),
        ('3 SPACES 1 .',           '1'),
        ('.S 1 2 3 .S',           '1 2 3'),
    ],
}

def main():
    s = serial.Serial(PORT, BAUD, timeout=2)
    drain(s)

    total_p = total_f = 0
    for category, tests in TESTS.items():
        print(f'\n=== {category} ===')
        p = f = 0
        for cmd, expected in tests:
            result = send_read(s, cmd).strip()
            ok = result == expected
            if ok: p += 1
            else:  f += 1
            tag = 'PASS' if ok else 'FAIL'
            extra = '' if ok else f' => [{result}] expected [{expected}]'
            print(f'  {tag}: {cmd}{extra}')
        total_p += p
        total_f += f

    print(f'\n=== Total: {total_p}/{total_p + total_f} passed ===')
    s.close()

if __name__ == '__main__':
    main()
