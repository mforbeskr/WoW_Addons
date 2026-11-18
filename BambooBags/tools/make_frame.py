"""Generates BambooBags' bamboo frame atlas (frame.tga) and hemp cloth (hemp.tga).

Run from anywhere:  python make_frame.py
Writes uncompressed 32-bit TGA into ../textures (the 3.3.5 client loads it directly).
Changed textures need a full client restart, not just /reload.

frame.tga (256x64, 64 KB) is drawn in a clean illustrated style, in dark forest green: outlined
bamboo poles with nodes, cut ends, a rope X lashing and a flat leaf sprig. Shapes are rendered 4x4 supersampled so the
edges stay smooth when the game scales them. Atlas layout (x, y, w, h), used by BambooBags.lua:
  pole, horizontal   0, 0, 64, 16   one internode with a node at its left end; tiled
  cut end, right    64, 0,  8, 16   mirrored in game for the left end
  cut end, bottom   72, 0, 16,  8   flipped in game for the top end
  rope lashing      88, 0, 32, 32
  pole, vertical   120, 0, 16, 64
  leaf sprig       136, 0, 64, 16   lies flat along a pole, leaves pointing right

hemp.tga (128x128, 64 KB) is dark toasted hemp in a plain weave: uneven slubbed threads, mixed
fibre tones, stray light fibres and dark flecks. Shown 1:1 so the threads stay crisp.
"""
import math
import os
import random

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
SS = 4  # supersampling per axis


def clamp(v):
    return max(0, min(255, int(round(v))))


def save_tga(name, w, h, rows):
    """rows[y][x] = (r, g, b, a) in 0-255, top row first."""
    hdr = bytearray(18)
    hdr[2] = 2                      # uncompressed true-color
    hdr[12], hdr[13] = w & 255, w >> 8
    hdr[14], hdr[15] = h & 255, h >> 8
    hdr[16] = 32
    hdr[17] = 8                     # 8 alpha bits, bottom-left origin
    data = bytearray()
    for y in range(h - 1, -1, -1):
        for r, g, b, a in rows[y]:
            data += bytes((clamp(b), clamp(g), clamp(r), clamp(a)))
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(hdr + data)


def render(w, h, shader):
    """shader(x, y) -> (r, g, b, coverage 0-1) or None. Returns rows, supersampled."""
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            R = G = B = A = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    c = shader(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    if c:
                        r, g, b, a = c
                        R += r * a
                        G += g * a
                        B += b * a
                        A += a
            if A > 0:
                row.append((R / A, G / A, B / A, 255 * A / (SS * SS)))
            else:
                row.append((0, 0, 0, 0))
        rows.append(row)
    return rows


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def ramp(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(1, len(stops)):
        if t <= stops[i][0]:
            a, b = stops[i - 1], stops[i]
            return lerp(a[1], b[1], (t - a[0]) / (b[0] - a[0]))
    return stops[-1][1]


def gauss(x, c, w):
    return math.exp(-((x - c) / w) ** 2)


def scale(c, k):
    return tuple(v * k for v in c)


# ---------- bamboo ----------
OUTLINE = (12, 22, 6)
OUTLINE_W = 1.1
# Across a pole, lit side first: a cartoon cylinder with a bright highlight stripe
POLE_RAMP = [
    (0.0, (38, 62, 24)),
    (0.16, (62, 96, 38)),
    (0.3, (104, 140, 72)),
    (0.44, (58, 90, 34)),
    (0.75, (36, 60, 22)),
    (1.0, (20, 36, 12)),
]
CUT_FACE = (150, 146, 104)
PC, PR = 8.0, 6.6  # pole centre and radius inside its 16px strip


def node_bulge(u):
    if 0.3 < u < 3.4:
        return math.sin(math.pi * (u - 0.3) / 3.1)
    return 0.0


def pole_body(u, v, period=64.0):
    """Pole running along u; v across it. Returns colour and the distance to the outline."""
    r = PR + 0.7 * node_bulge(u)
    d = abs(v - PC)
    if d > r:
        return None, 0
    t = (v - (PC - r)) / (2 * r)
    col = ramp(POLE_RAMP, t)
    # Lengthwise fibre streaks and a gentle tone change along the internode
    k = 1 + 0.035 * math.sin(t * 57 + 1.3) + 0.02 * math.sin(t * 131) + 0.03 * math.sin(2 * math.pi * u / period * 2 + 0.6)
    # Node: two dark grooves with a lit ridge between them
    groove = gauss(u, 0.75, 0.42) + gauss(u, 2.95, 0.42)
    ridge = gauss(u, 1.85, 0.55)
    col = scale(col, k * (1 - 0.45 * groove))
    col = lerp(col, (120, 156, 84), 0.3 * ridge * (1 - t))
    return col, r - d


def hpole(u, v):
    col, edge = pole_body(u, v)
    if col is None:
        return None
    if edge < OUTLINE_W:
        col = OUTLINE
    return col + (1.0,)


def hend(u, v):
    """Pole coming in from the left, cut off at the right with a rounded, lighter rim."""
    end = 5.8
    d = abs(v - PC)
    if d > PR:
        return None
    lim = end - (1 - math.sqrt(max(0.0, 1 - (d / PR) ** 2))) * 2.2
    if u > lim:
        return None
    col, edge = pole_body(u + 20, v)  # +20: away from the node
    rim = lim - u
    if rim < 1.6:
        col = lerp(col, CUT_FACE, 0.75)
    if edge < OUTLINE_W or rim < OUTLINE_W * 0.9:
        col = OUTLINE
    return col + (1.0,)


# Rope lashing: two twisted hemp ropes crossing in an X, with a knot and a soft shadow
ROPE_DARK, ROPE_MID, ROPE_LIGHT = (56, 40, 22), (100, 78, 50), (138, 116, 82)
ROPE_OUTLINE = (24, 16, 6)


def rope(along, across, half):
    k = 0.72 + 0.34 * math.cos(min(abs(across) / half, 1) * math.pi / 2)
    s = (along * 0.62 + across * 0.45) % 1.0          # twisted strands
    strand = 0.7 + 0.3 * math.sin(math.pi * s)
    col = ramp([(0, ROPE_DARK), (0.6, ROPE_MID), (1, ROPE_LIGHT)], k * strand - 0.15 * (across / half))
    return col


def lashing(x, y):
    cx = cy = 16.0
    dx, dy = x - cx, y - cy
    half, reach = 2.7, 14.2
    # knot on top
    kd = math.hypot(dx + 0.3, dy + 0.3)
    if kd < 3.4:
        if 3.4 - kd < 0.9:
            return ROPE_OUTLINE + (1.0,)
        shade = 0.75 + 0.35 * (1 - kd / 3.4) + 0.2 * gauss(dx + dy, -2.2, 1.4)
        return ramp([(0, ROPE_DARK), (0.6, ROPE_MID), (1, ROPE_LIGHT)], shade - 0.25) + (1.0,)
    for sign in (1, -1):  # the "\" rope lies over the "/" rope
        along = (dx + sign * dy) / math.sqrt(2)
        across = (dx - sign * dy) / math.sqrt(2)
        if abs(across) < half and abs(along) < reach:
            if half - abs(across) < 0.8 or reach - abs(along) < 0.8:
                return ROPE_OUTLINE + (1.0,)
            return rope(along, across, half) + (1.0,)
    # shadow of the ropes on the poles (down-right)
    for sign in (1, -1):
        sx, sy = dx - 1.3, dy - 1.3
        along = (sx + sign * sy) / math.sqrt(2)
        across = (sx - sign * sy) / math.sqrt(2)
        if abs(across) < half and abs(along) < reach:
            return (20, 26, 4, 0.35)
    return None


# Leaf sprig lying flat along a pole: a thin stem with three slim leaves pointing the same way,
# kept inside the 16px pole strip so nothing pokes out of the frame
STEM = [(2.0, 9.5), (30.0, 7.0), (62.0, 8.5)]
LEAVES = [  # stem t, angle (degrees, screen space), length, half width
    (0.10, -7, 25, 3.3),
    (0.40, 8, 23, 3.1),
    (0.70, -5, 18, 2.7),
]
LEAF_DARK, LEAF_MID, LEAF_LIGHT = (26, 56, 16), (48, 90, 30), (84, 128, 54)
LEAF_OUTLINE = (10, 26, 6)


def bez(t):
    (x0, y0), (x1, y1), (x2, y2) = STEM
    a, b, c = (1 - t) ** 2, 2 * t * (1 - t), t * t
    return a * x0 + b * x1 + c * x2, a * y0 + b * y1 + c * y2


STEM_PTS = [bez(i / 60) for i in range(61)]
LEAF_GEOM = []
for t, ang, length, hw in LEAVES:
    bx, by = bez(t)
    a = math.radians(ang)
    LEAF_GEOM.append((bx, by, math.cos(a), math.sin(a), length, hw))


def leaf(x, y):
    for bx, by, ux, uy, length, hw in reversed(LEAF_GEOM):
        px, py = x - bx, y - by
        s = px * ux + py * uy
        d = -px * uy + py * ux
        if 0 < s < length:
            w = hw * math.sin(math.pi * s / length) ** 0.85 * (1 - 0.2 * s / length)
            if abs(d) < w:
                if w - abs(d) < 0.85:
                    return LEAF_OUTLINE + (1.0,)
                if abs(d) < 0.45 and s < 0.85 * length:
                    return LEAF_DARK + (1.0,)  # midrib
                side = 0.75 if d < 0 else 0.35  # one half catches the light
                col = ramp([(0, LEAF_DARK), (0.45, LEAF_MID), (1, LEAF_LIGHT)], side + 0.25 * s / length)
                return col + (1.0,)
    best = min(math.hypot(x - sx, y - sy) for sx, sy in STEM_PTS)
    if best < 1.1:
        return (LEAF_OUTLINE if best > 0.7 else (44, 78, 24)) + (1.0,)
    return None


def build_frame():
    W, H = 256, 64
    atlas = [[(0, 0, 0, 0)] * W for _ in range(H)]

    def paste(ox, oy, rows):
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                atlas[oy + y][ox + x] = c

    paste(0, 0, render(64, 16, hpole))
    paste(64, 0, render(8, 16, hend))
    paste(72, 0, render(16, 8, lambda x, y: hend(y, x)))     # transposed: cut end at the bottom
    paste(88, 0, render(32, 32, lashing))
    paste(120, 0, render(16, 64, lambda x, y: hpole(y, x)))  # transposed: lit side on the left
    paste(136, 0, render(64, 16, leaf))
    save_tga("frame", W, H, atlas)


# ---------- hemp cloth ----------
def build_hemp():
    rnd = random.Random(5)
    N, CELL = 128, 4
    threads = N // CELL
    base = (70, 60, 46)
    tone_w = [rnd.gauss(0, 4) for _ in range(threads)]
    tone_f = [rnd.gauss(0, 4) for _ in range(threads)]

    def harmonics():
        return [(rnd.randint(1, 6), rnd.uniform(0, 6.28), rnd.uniform(1.5, 4)) for _ in range(2)]
    slub_w = [harmonics() for _ in range(threads)]
    slub_f = [harmonics() for _ in range(threads)]

    def slub(h, pos):  # thickness/tone variation along a thread; periodic so the tile wraps
        return sum(a * math.sin(2 * math.pi * k * pos / N + p) for k, p, a in h)

    rows = []
    for y in range(N):
        row = []
        for x in range(N):
            cx, cy = x // CELL, y // CELL
            ux, uy = (x % CELL + 0.5) / CELL, (y % CELL + 0.5) / CELL
            if (cx + cy) % 2 == 0:   # warp (vertical) thread on top
                across, along, v = ux, uy, tone_w[cx] + slub(slub_w[cx], y)
            else:                    # weft (horizontal) thread on top
                across, along, v = uy, ux, tone_f[cy] + slub(slub_f[cy], x)
            shade = (0.74 + 0.32 * math.sin(math.pi * across) ** 0.6) * (0.9 + 0.1 * math.sin(math.pi * along))
            v += rnd.gauss(0, 2.5)
            v += 3 * math.sin(2 * math.pi * x / N + 0.5) * math.cos(4 * math.pi * y / N + 1.0)
            roll = rnd.random()
            if roll < 0.012:
                v += 14          # stray light fibre
            elif roll < 0.018:
                v -= 14          # dark fleck, as in natural hemp
            r = (base[0] + v + 2) * shade
            g = (base[1] + v) * shade
            b = (base[2] + v * 0.85 - 2) * shade
            row.append((r, g, b, 255))
        rows.append(row)
    save_tga("hemp", N, N, rows)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    build_frame()
    build_hemp()
    print("frame.tga and hemp.tga written to", os.path.normpath(OUT))
