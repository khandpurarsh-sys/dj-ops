#!/usr/bin/env python3
"""Pixel proof: diff screenshots to find the dock capsule and Menu word, then measure their
centres against the screen centre line. Usage: measure_dock.py DIR  (expects <mode>-dock.png,
<mode>-nodock.png, <mode>-nomenu.png for each mode). Exit 1 if any offset > 1.5 px."""
import sys, zlib, struct, os

def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8; idat = b''; w = h = bd = ct = 0
    while pos < len(d):
        ln, = struct.unpack('>I', d[pos:pos+4]); typ = d[pos+4:pos+8]; body = d[pos+8:pos+8+ln]; pos += 12 + ln
        if typ == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', body[:10])[:4]
        elif typ == b'IDAT': idat += body
    bpp = {2: 3, 6: 4}[ct]; assert bd == 8
    raw = zlib.decompress(idat); stride = w * bpp; rows = []; prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+stride]); p += 1 + stride
        if f == 1:
            for i in range(bpp, stride): line[i] = (line[i] + line[i-bpp]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride): line[i] = (line[i] + (((line[i-bpp] if i >= bpp else 0) + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-bpp] if i >= bpp else 0; b = prev[i]; c = prev[i-bpp] if i >= bpp else 0
                pa = abs(b - c); pb = abs(a - c); pc = abs(a + b - 2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line); prev = line
    return w, h, bpp, rows

def bbox(a, b, bpp, thr=6):
    x0 = y0 = 10**9; x1 = y1 = -1
    for y, (ra, rb) in enumerate(zip(a, b)):
        if ra == rb: continue
        for x in range(0, len(ra), bpp):
            if max(abs(ra[x]-rb[x]), abs(ra[x+1]-rb[x+1]), abs(ra[x+2]-rb[x+2])) > thr:
                px = x // bpp
                x0 = min(x0, px); x1 = max(x1, px); y0 = min(y0, y); y1 = max(y1, y)
    return (x0, y0, x1, y1) if x1 >= 0 else None

def lum(r, g, b):
    f = lambda c: (c/255/12.92) if c/255 <= 0.03928 else (((c/255)+0.055)/1.055) ** 2.4
    return 0.2126*f(r) + 0.7152*f(g) + 0.0722*f(b)

d = sys.argv[1]; out = []; bad = False
for mode in ['light', 'dark', 'light-mini']:
    try:
        w, h, bpp, A = read_png(f'{d}/{mode}-dock.png')
        _, _, _, B = read_png(f'{d}/{mode}-nodock.png')
        _, _, _, C = read_png(f'{d}/{mode}-nomenu.png')
    except Exception as e:
        out.append(f'{mode}: could not read ({e})'); bad = True; continue
    cap = bbox(A, B, bpp); word = bbox(A, C, bpp, 40)
    mid = (w - 1) / 2.0
    if not cap or not word:
        out.append(f'{mode}: nothing found cap={cap} word={word}'); bad = True; continue
    capc = (cap[0] + cap[2]) / 2.0; wordc = (word[0] + word[2]) / 2.0
    # contrast: darkest vs lightest pixel in the word box of the real screenshot
    ls = []
    for y in range(word[1], word[3] + 1):
        for x in range(word[0], word[2] + 1):
            i = x * bpp; ls.append(lum(A[y][i], A[y][i+1], A[y][i+2]))
    hi, lo = max(ls), min(ls); cr = (hi + 0.05) / (lo + 0.05)
    do, wo = capc - mid, wordc - mid
    out.append(f'{mode}: screen {w}px wide, centre x={mid:.1f}. capsule x {cap[0]}..{cap[2]} centre {capc:.1f} offset {do:+.1f}px ({do/3:+.2f}pt@3x); '
               f'Menu word x {word[0]}..{word[2]} centre {wordc:.1f} offset {wo:+.1f}px ({wo/3:+.2f}pt); word contrast {cr:.1f}:1')
    if abs(do) > 1.5 or abs(wo) > 1.5: bad = True
open(f'{d}/dock-measure.txt', 'w').write('\n'.join(out) + '\n'); print('\n'.join(out))
sys.exit(1 if bad else 0)
