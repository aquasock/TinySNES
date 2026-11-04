#!/usr/bin/env python3
"""Put a core image on the TinyTang SD card and load it, in two-wire mode.

    tools/tang_deploy.py build/DIR/tinysnes.bin /root/cores/console138k/tinysnes-dbg.bin

Sends the file with tangput (bare-CR terminated, see BRD-004), checks 4 KiB at
the head, middle and tail against the local file with tangget, then runs
tangload.  The console must be at the shell prompt on /dev/ttyACM0.
"""
import serial, sys, time, re
local, remote = sys.argv[1], sys.argv[2]
data = open(local, 'rb').read()
p = serial.Serial('/dev/ttyACM0', 115200, timeout=0.2)
def drain(t=0.5):
    end = time.time() + t; b = b''
    while time.time() < end: b += p.read(65536)
    return b
def until(pat, t):
    end = time.time() + t; b = b''
    while time.time() < end:
        b += p.read(65536)
        if re.search(pat, b): return b
    raise SystemExit(f'timeout waiting {pat!r}: {b[-300:]!r}')
p.write(b'\r'); drain()
p.write(f'tangput {len(data)} {remote}\r'.encode()); time.sleep(0.5); print(drain(0.3).decode(errors='replace').strip())
t = time.time()
for o in range(0, len(data), 4096): p.write(data[o:o+4096])
p.flush(); print(until(rb'# $', 60)[-300:].decode(errors='replace').strip(), f'({time.time()-t:.1f}s)')
def get(off, n):
    p.write(f'tangget {remote} {off} {n}\r'.encode())
    b = until(rb'tangget: \d+ bytes at \d+ of \d+\r?\n', 10)
    hdr = re.search(rb'tangget: (\d+) bytes at (\d+) of (\d+)\r?\n', b)
    rest = b[hdr.end():]
    while len(rest) < n: rest += p.read(65536)
    drain(0.5); return int(hdr.group(3)), rest[:n]
for off in (0, len(data)//2, len(data)-4096):
    total, chunk = get(off, 4096)
    ok = total == len(data) and chunk == data[off:off+4096]
    print(f'verify @{off}: total {total} {"OK" if ok else "MISMATCH"}')
    if not ok: sys.exit(1)
p.write(f'tangload {remote}\r'.encode()); print(until(rb'core loaded|answering|error|fail', 60).decode(errors='replace').strip()[-400:])
