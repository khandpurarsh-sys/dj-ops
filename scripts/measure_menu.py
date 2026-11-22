#!/usr/bin/env python3
"""Menu orientation proof: is the sheet full-bleed sideways, and is the dock centred? Usage: measure_menu.py DIR"""
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
                x0 = min(x0, px); x1 = max(x1, px); y0 = min(y0, y); y1 = max(y1, y1 if False else y)
    return (x0, y0, x1, y1) if x1 >= 0 else None

def is_page(r, g, b):  # the loud red page colour (0.80,0.22,0.17) = 204,56,43
    return abs(r-204) < 18 and abs(g-56) < 18 and abs(b-43) < 18

d = sys.argv[1]; out = []; bad = False
for o in ['portrait', 'landR', 'landL']:
    try:
        w, h, bpp, A = read_png(f'{d}/menu-{o}-dock.png')
        _, _, _, B = read_png(f'{d}/menu-{o}-nodock.png')
    except Exception as e:
        out.append(f'{o}: could not read ({e})'); bad = True; continue
    def px(x, y): i = x*bpp; return A[y][i], A[y][i+1], A[y][i+2]
    edges = {'top': [(x, 3) for x in range(0, w, 7)], 'bottom': [(x, h-4) for x in range(0, w, 7)],
             'left': [(3, y) for y in range(0, h, 7)], 'right': [(w-4, y) for y in range(0, h, 7)]}
    cnt = {k: sum(1 for (x, y) in v if is_page(*px(x, y))) for k, v in edges.items()}
    cap = bbox(A, B, bpp)
    mid = (w - 1) / 2.0
    capc = (cap[0] + cap[2]) / 2.0 if cap else None
    land = w > h
    line = f'{o}: screenshot {w}x{h} ({"landscape" if land else "portrait"}). red page pixels along edges: {cnt}. '
    line += f'dock capsule x {cap[0]}..{cap[2]} centre {capc:.1f} vs screen {mid:.1f} offset {capc-mid:+.1f}px' if cap else 'dock not found'
    out.append(line)
    if land and sum(cnt.values()) > 0: bad = True; out.append(f'  FAIL {o}: sheet leaves page showing at an edge')
    if not cap or abs(capc - mid) > 1.5: bad = True; out.append(f'  FAIL {o}: dock not centred')
    if not land and cnt['top'] == 0: out.append('  note: portrait top edge fully covered (sheet normally 82% tall)')
open(f'{d}/menu-measure.txt', 'w').write('\n'.join(out) + '\n'); print('\n'.join(out))
sys.exit(1 if bad else 0)
