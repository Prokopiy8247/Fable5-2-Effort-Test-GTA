"""lm_towers - towers / skyline structures for NEON TIDE (SPEC_LANDMARKS.md, "P2 - Towers and skyline pieces").

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C, lm_fix as F, lm_towers as T
    for m in (K, C, F, T): importlib.reload(m)
    print(T.build_all())
"""
import math
import random

import gta_kit as K
import lm_common as C
import lm_fix as F
from lm_common import bx

NOTES = {}
TXT_RES = 2


def export(name):
    return C.finish(name, NOTES.get(name, ""))


def strut(mb, a, b, r, color, segs=4):
    mb.tube([a, b], r, color, segs=segs, caps=False)


def col_strut(col, a, b, s):
    """Collision box of square section s along the segment a-b."""
    ax, ay, az = a
    bx_, by, bz = b
    dx, dy, dz = bx_ - ax, by - ay, bz - az
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    ux, uy, uz = dx / ln, dy / ln, dz / ln
    rx = -math.degrees(math.asin(max(-1.0, min(1.0, uy))))
    cx = math.cos(math.radians(rx))
    ry = math.degrees(math.asin(max(-1.0, min(1.0, ux / cx)))) if abs(cx) > 1e-6 else 0.0
    col.cbox((s, s, ln), ((ax + bx_) * 0.5, (ay + by) * 0.5, (az + bz) * 0.5), rot=(rx, ry, 0))


def railing_ring(mb, pts, z0, h=1.1, color="steel", post_every=1, r=0.03, closed=True, col=None):
    """Tube railing along a polyline of (x, y) points at deck height z0 (top + mid rail + posts)."""
    n = len(pts)
    m = n if closed else n - 1
    for k in range(m):
        a, b = pts[k], pts[(k + 1) % n]
        strut(mb, (a[0], a[1], z0 + h), (b[0], b[1], z0 + h), r, color)
        strut(mb, (a[0], a[1], z0 + h * 0.5), (b[0], b[1], z0 + h * 0.5), r * 0.8, color)
        if col is not None:
            col_strut(col, (a[0], a[1], z0 + h * 0.5), (b[0], b[1], z0 + h * 0.5), 0.1)
    for k in range(0, n if closed else n, post_every):
        a = pts[k]
        strut(mb, (a[0], a[1], z0), (a[0], a[1], z0 + h), r * 1.2, color)


def curved_text(mb, text, R, z, size, color, depth=0.05, center_deg=90.0, res=1):
    """3D lettering wrapped around a vertical cylinder of radius R (readable from outside), centred on the
    direction center_deg (90 = +Y)."""
    n0 = len(mb.bm.verts)
    xmin, xmax, zmin, zmax = C.text_metrics(text)
    K.add_text(mb, text, size=size, depth=depth, color=color, pos=(-(xmin + xmax) * 0.5 * size, 0.0, z), res=res)
    mb.bm.verts.ensure_lookup_table()
    base = math.radians(center_deg)
    for v in mb.bm.verts[n0:]:
        x, y, zz = v.co
        a = base - x / R
        r = R + y
        v.co.x = r * math.cos(a)
        v.co.y = r * math.sin(a)
    mb.bm.normal_update()


# =========================================================================== lm_radio_tower
NOTES["lm_radio_tower"] = (
    "Red/white banded lattice radio tower, base 5x5 tapering to 2x2 at 40 m, total height 42 incl. antennas. "
    "Platforms (grating + railing) at z 14, 28 and 40 (top surfaces). Ladder on the +Y face running through hatches. "
    "Markers: ladder_bottom (ground, 0.5 m in front of the ladder, looking at it), ladder_top (on the 40 m platform "
    "next to the hatch), jump (on the -Y edge of the top platform where the railing has a 1.2 m gap with a short "
    "yellow plank sticking out 0.9 m; +Y of the marker points outward/-Y). "
    "col: 3 platform boxes + 4 slanted leg boxes (+ top railings, plank).")


def build_lm_radio_tower():
    root = K.begin_asset("lm_radio_tower", C.CAT)
    sh, col = K.MB(), C.Col()
    H = 40.0
    W0, W1 = 2.5, 1.0

    def hw(z):
        return W0 + (W1 - W0) * z / H

    bands = 7
    cols_b = ["red", "white"]
    # legs in colour bands
    for sx in (-1, 1):
        for sy in (-1, 1):
            for b in range(bands):
                z0, z1 = H * b / bands, H * (b + 1) / bands
                strut(sh, (sx * hw(z0), sy * hw(z0), z0), (sx * hw(z1), sy * hw(z1), z1), 0.13, cols_b[b % 2], segs=6)
            col_strut(col, (sx * hw(0), sy * hw(0), 0.0), (sx * hw(H), sy * hw(H), H), 0.3)
    # horizontal braces + diagonals on every face
    levels = [0.4] + [H * k / 12 for k in range(1, 13)]
    for i, z in enumerate(levels):
        w = hw(z)
        c = cols_b[int(z / (H / bands)) % 2] if z < H else "red"
        corners = [(w, w), (-w, w), (-w, -w), (w, -w)]
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            strut(sh, (a[0], a[1], z), (b[0], b[1], z), 0.06, c)
        if i + 1 < len(levels):
            z2 = levels[i + 1]
            w2 = hw(z2)
            c2 = [(w2, w2), (-w2, w2), (-w2, -w2), (w2, -w2)]
            cd = cols_b[int((z + z2) * 0.5 / (H / bands)) % 2]
            for k in range(4):
                a, b = corners[k], corners[(k + 1) % 4]
                a2, b2 = c2[k], c2[(k + 1) % 4]
                strut(sh, (a[0], a[1], z), (b2[0], b2[1], z2), 0.05, cd)
                strut(sh, (b[0], b[1], z), (a2[0], a2[1], z2), 0.05, cd)
    # platforms with railings + hatches for the ladder
    for zp, half in ((14.0, 2.7), (28.0, 2.25), (40.0, 1.9)):
        bx(sh, (-half, -half, zp - 0.12), (half, half, zp), "steel_dark", colors={"+z": "steel"})
        for k in range(1, 6):
            y = -half + 2 * half * k / 6
            sh.quad((-half + 0.05, y - 0.02, zp + 0.004), (half - 0.05, y - 0.02, zp + 0.004),
                    (half - 0.05, y + 0.02, zp + 0.004), (-half + 0.05, y + 0.02, zp + 0.004), "steel_dark")
        col.box((-half, -half, zp - 0.12), (half, half, zp))
        h2 = half - 0.05
        if zp < H:
            railing_ring(sh, [(h2, h2), (-h2, h2), (-h2, -h2), (h2, -h2)], zp, 1.1, "red")
        else:
            # top platform: gap in the -Y railing with a short jump plank
            railing_ring(sh, [(0.6, -h2), (h2, -h2), (h2, h2), (-h2, h2), (-h2, -h2), (-0.6, -h2)], zp, 1.1, "red",
                         closed=False, col=col)
            bx(sh, (-0.35, -half - 0.9, zp - 0.1), (0.35, -half + 0.2, zp - 0.02), "steel",
               colors={"+z": "hazard_yellow"})
            col.box((-0.35, -half - 0.9, zp - 0.1), (0.35, -half + 0.2, zp - 0.02))
        sh.quad((-0.4, hw(zp) - 0.35, zp + 0.006), (0.4, hw(zp) - 0.35, zp + 0.006), (0.4, hw(zp) + 0.35, zp + 0.006),
                (-0.4, hw(zp) + 0.35, zp + 0.006), "black")
    # ladder on the +Y face (follows the taper), rungs every 0.5 m
    off = 0.25
    for x in (-0.25, 0.25):
        strut(sh, (x, hw(0) + off, 0.0), (x, hw(H) + off, H + 1.0), 0.025, "steel_dark")
    z = 0.4
    while z < H - 0.2:
        y = hw(z) + off
        C.obox(sh, (-0.25, y - 0.015, z), (0.25, y + 0.015, z + 0.03), "steel", "+y+z")
        z += 0.5
    # antennas + beacons
    sh.cyl(0.12, 1.2, (0, 0, H), "red", segs=6, base=True)
    sh.cyl(0.06, 0.6, (0, 0, H + 1.2), "white", segs=6, base=True)
    for (x, y) in ((1.2, 1.2), (-1.2, -1.2)):
        sh.cyl(0.04, 1.6, (x, y, H), "steel", segs=4, base=True)
        sh.box((0.5, 0.06, 1.0), (x, y + 0.08, H + 0.9), "white")
    for (x, y, z) in ((0, 0, H + 1.8), (hw(28) + 0.05, 0, 28.6), (-hw(28) - 0.05, 0, 28.6), (0, hw(14) + 0.05, 14.6),
                      (0, -hw(14) - 0.05, 14.6)):
        sh.cyl(0.11, 0.2, (x, y, z), "led_red", segs=6, base=True)
    # base pads
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(sh, (sx * W0 - 0.45, sy * W0 - 0.45, 0.0), (sx * W0 + 0.45, sy * W0 + 0.45, 0.4), "concrete")

    C.cull_hidden(sh, C.ground_occ(-4, 4, -4, 4))
    sh.to_object(root, "shell", sharp_angle=50)
    col.to_object(root)
    K.marker(root, "ladder_bottom", (0.0, hw(0) + off + 0.5, 0.0), (0, 0, 180))
    K.marker(root, "ladder_top", (0.0, hw(H) - 0.6, H), (0, 0, 180))
    K.marker(root, "jump", (0.0, -1.9, H), (0, 0, 180))
    return root


# =========================================================================== lm_water_tower
NOTES["lm_water_tower"] = (
    "Water tower, height 20 (finial). Four braced legs (feet at +-3.3) carry a catwalk ring at z 12.4 and a cylindrical "
    "tank r 4.2 (z 12.9..17.6) with a conical roof; 'VESPER BAY' wrapped around the +Y side; ladder up the +Y/+X leg "
    "and the tank wall; rust streaks. col: 4 slanted leg boxes + octagonal tank cylinder + catwalk.")


def build_lm_water_tower():
    root = K.begin_asset("lm_water_tower", C.CAT)
    sh, col = K.MB(), C.Col()
    TR, ZB, ZT = 4.2, 12.9, 17.6
    LB, LT = 3.3, 2.75
    TANK, LEG = "white", "steel"
    # legs, braces, tie rods
    feet = [(LB, LB), (-LB, LB), (-LB, -LB), (LB, -LB)]
    tops = [(LT, LT), (-LT, LT), (-LT, -LT), (LT, -LT)]
    for (fx_, fy), (tx, ty) in zip(feet, tops):
        strut(sh, (fx_, fy, 0.0), (tx, ty, ZB - 0.3), 0.3, LEG, segs=8)
        sh.cyl(0.42, 0.5, (fx_, fy, 0.0), "concrete", segs=8, base=True, smooth=False)
        col_strut(col, (fx_, fy, 0.0), (tx, ty, ZB - 0.3), 0.44)
    for z in (4.2, 8.4):
        t = z / (ZB - 0.3)
        w = LB + (LT - LB) * t
        cs = [(w, w), (-w, w), (-w, -w), (w, -w)]
        for k in range(4):
            a, b = cs[k], cs[(k + 1) % 4]
            strut(sh, (a[0], a[1], z), (b[0], b[1], z), 0.08, LEG)
    zl = [0.5, 4.2, 8.4, ZB - 0.4]
    for i in range(3):
        za, zb_ = zl[i], zl[i + 1]
        wa = LB + (LT - LB) * za / (ZB - 0.3)
        wb = LB + (LT - LB) * zb_ / (ZB - 0.3)
        ca = [(wa, wa), (-wa, wa), (-wa, -wa), (wa, -wa)]
        cb = [(wb, wb), (-wb, wb), (-wb, -wb), (wb, -wb)]
        for k in range(4):
            a, b = ca[k], ca[(k + 1) % 4]
            a2, b2 = cb[k], cb[(k + 1) % 4]
            strut(sh, (a[0], a[1], za), (b2[0], b2[1], zb_), 0.03, "steel_dark")
            strut(sh, (b[0], b[1], za), (a2[0], a2[1], zb_), 0.03, "steel_dark")
    strut(sh, (0, 0, 0.5), (0, 0, ZB - 0.6), 0.3, "steel_dark", segs=8)
    # tank: bottom cone, wall, roof cone, finial
    n = 16
    ring = lambda r, z: [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r, z) for k in range(n)]
    sh.loft([ring(0.6, ZB - 1.0), ring(TR, ZB)], TANK, cap_start=True, cap_end=False, smooth=True)
    sh.loft([ring(TR, ZB), ring(TR, ZB + 0.9), ring(TR, ZT - 0.9), ring(TR, ZT)], TANK, cap_start=False, cap_end=False,
            smooth=True, ring_colors=["sky_blue", TANK, "sky_blue"])
    sh.loft([ring(TR + 0.15, ZT), ring(TR + 0.15, ZT + 0.12), ring(0.35, ZT + 1.9)], "sky_blue", cap_start=True,
            cap_end=True, smooth=False)
    sh.cyl(0.08, 0.6, (0, 0, ZT + 1.85), "steel", segs=6, base=True)
    sh.sphere(0.16, (0, 0, ZT + 2.45), "sky_blue", segs=8, rings=5)
    curved_text(sh, "VESPER", TR, 15.45, 1.5, "navy", depth=0.06, center_deg=90.0, res=1)
    curved_text(sh, "BAY", TR, 14.0, 1.5, "navy", depth=0.06, center_deg=90.0, res=1)
    col.cyl(TR, ZT - ZB + 1.0, (0, 0, ZB - 1.0), segs=8)
    # catwalk ring + railing
    cr = [(math.cos(2 * math.pi * k / n) * (TR + 0.9), math.sin(2 * math.pi * k / n) * (TR + 0.9)) for k in range(n)]
    ci = [(math.cos(2 * math.pi * k / n) * (TR - 0.2), math.sin(2 * math.pi * k / n) * (TR - 0.2)) for k in range(n)]
    for k in range(n):
        a, b = cr[k], cr[(k + 1) % n]
        c_, d = ci[(k + 1) % n], ci[k]
        C.poly_up(sh, [(a[0], a[1], ZB - 0.45), (b[0], b[1], ZB - 0.45), (c_[0], c_[1], ZB - 0.45), (d[0], d[1], ZB - 0.45)],
                  "steel_dark")
        C.poly_up(sh, [(d[0], d[1], ZB - 0.55), (c_[0], c_[1], ZB - 0.55), (b[0], b[1], ZB - 0.55), (a[0], a[1], ZB - 0.55)],
                  "steel_dark", up=(0, 0, -1))
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        ln = math.hypot(mx, my)
        C.poly_up(sh, [(a[0], a[1], ZB - 0.55), (b[0], b[1], ZB - 0.55), (b[0], b[1], ZB - 0.45), (a[0], a[1], ZB - 0.45)],
                  "steel_dark", up=(mx / ln, my / ln, 0))
    railing_ring(sh, [(p[0] * 0.98, p[1] * 0.98) for p in cr], ZB - 0.45, 1.05, "steel", post_every=2)
    col.cyl(TR + 0.9, 0.1, (0, 0, ZB - 0.55), segs=8)
    # ladders: up the +Y/+X leg line (vertical, beside the leg) and up the tank wall
    lx, ly = 2.2, 3.15
    for dx in (-0.22, 0.22):
        strut(sh, (lx + dx, ly, 0.3), (lx + dx, ly, ZB - 0.45), 0.022, "steel_dark")
    z = 0.6
    while z < ZB - 0.6:
        C.obox(sh, (lx - 0.22, ly - 0.012, z), (lx + 0.22, ly + 0.012, z + 0.025), "steel", "+y-y+z")
        z += 0.45
    a0 = math.radians(40)
    ux, uy = math.cos(a0), math.sin(a0)
    for d in (-0.22, 0.22):
        px, py = ux * (TR + 0.18) - uy * d, uy * (TR + 0.18) + ux * d
        strut(sh, (px, py, ZB - 0.45), (px, py, ZT + 0.4), 0.02, "steel_dark")
    z = ZB
    while z < ZT:
        px, py = ux * (TR + 0.18), uy * (TR + 0.18)
        sh.box((0.44, 0.03, 0.025), (px, py, z), "steel", rot=(0, 0, math.degrees(a0) - 90))
        z += 0.45
    # rust streaks under the catwalk + wall seams
    rng = random.Random(4)
    for k in range(10):
        a = rng.uniform(0, 2 * math.pi)
        if 1.1 < a < 2.05:
            continue
        r = TR + 0.006
        w = rng.uniform(0.06, 0.14)
        z1 = rng.uniform(ZT - 0.3, ZT - 0.9)
        z0 = z1 - rng.uniform(0.8, 2.2)
        cx, cy = math.cos(a), math.sin(a)
        tx, ty = -cy, cx
        C.poly_up(sh, [(cx * r - tx * w, cy * r - ty * w, z0), (cx * r + tx * w * 0.4, cy * r + ty * w * 0.4, z0),
                       (cx * r + tx * w, cy * r + ty * w, z1), (cx * r - tx * w, cy * r - ty * w, z1)], "rust",
                  up=(cx, cy, 0))
    C.cull_hidden(sh, C.ground_occ(-5, 5, -5, 5))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== lm_lighthouse
NOTES["lm_lighthouse"] = (
    "Lighthouse on a rock base (base dia ~6+rocks, height 22.0 incl. lightning rod). White tapered tower with two red "
    "bands, gallery deck at 16.0 with railing, @Glass lantern room (16.25..18.75), red cap. Part `lamp` = rotating "
    "lens assembly (emis_always_white lens blocks), origin on the axis at (0, 0, 17.45): spin about Z. Marker `light` "
    "at the lens centre (the game puts an OmniLight there). Door on +Y at the base (closed). col: octagonal tower prism, "
    "plinth cylinder, gallery deck.")


def build_lm_lighthouse():
    root = K.begin_asset("lm_lighthouse", C.CAT)
    sh, col = K.MB(), C.Col()
    rng = random.Random(9)
    n = 16
    ring = lambda r, z: [(math.cos(2 * math.pi * (k + 0.5) / n) * r, math.sin(2 * math.pi * (k + 0.5) / n) * r, z)
                         for k in range(n)]
    ZP, ZG = 1.0, 16.0
    r0, r1 = 2.5, 1.65
    rz = lambda z: r0 + (r1 - r0) * (z - ZP) / (ZG - ZP)
    # rocks + plinth
    for k in range(9):
        a = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
        rr = rng.uniform(3.2, 3.9)
        sh.ico(rng.uniform(1.0, 1.5), (math.cos(a) * rr, math.sin(a) * rr, rng.uniform(-0.3, 0.2)),
               ("rock", "rock_dark", "rock_light")[k % 3], subdiv=1, jitter=0.25, seed=k + 3, scale=(1.3, 1.0, 0.7))
    sh.cyl(3.0, ZP, (0, 0, 0), "concrete", segs=n, base=True, cap_color="concrete_light", smooth=False)
    col.cyl(3.0, ZP, (0, 0, 0), segs=8)
    # tapered tower with red bands
    zs = [ZP, 5.0, 7.5, 10.5, 13.0, ZG]
    cols_ = ["white", "red", "white", "red", "white"]
    sh.loft([ring(rz(z), z) for z in zs], "white", cap_start=False, cap_end=False, smooth=True, ring_colors=cols_)
    col.cyl(r0, ZG - ZP, (0, 0, ZP), segs=8, r2=r1)
    # small windows climbing the tower
    for i, (z, ang) in enumerate(((6.2, 150), (9.0, 30), (11.8, 200), (14.4, 60))):
        a = math.radians(ang)
        r = rz(z) + 0.01
        cx, cy = math.cos(a), math.sin(a)
        tx, ty = -cy, cx
        C.poly_up(sh, [(cx * r - tx * 0.22, cy * r - ty * 0.22, z), (cx * r + tx * 0.22, cy * r + ty * 0.22, z),
                       (cx * r + tx * 0.22, cy * r + ty * 0.22, z + 0.7), (cx * r - tx * 0.22, cy * r - ty * 0.22, z + 0.7)],
                  "@Window", up=(cx, cy, 0))
    # door on +Y
    yd = rz(1.0) - 0.15
    bx(sh, (-0.62, yd - 0.1, ZP), (0.62, yd + 0.4, ZP + 2.45), "white")
    bx(sh, (-0.48, yd + 0.4, ZP), (0.48, yd + 0.43, ZP + 2.15), "navy")
    bx(sh, (0.28, yd + 0.43, ZP + 1.0), (0.34, yd + 0.47, ZP + 1.1), "brass")
    bx(sh, (-0.75, yd + 0.38, ZP + 2.45), (0.75, yd + 0.6, ZP + 2.6), "red")
    bx(sh, (-0.7, yd + 0.4, 0.0), (0.7, yd + 1.3, ZP), "concrete_light")
    col.box((-0.7, yd - 0.1, 0.0), (0.7, yd + 1.3, ZP))
    # gallery deck + railing, lantern room, cap
    sh.cyl(2.45, 0.25, (0, 0, ZG - 0.25), "white", segs=n, base=True, cap_color="gray_light", smooth=False)
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        strut(sh, (math.cos(a) * 1.6, math.sin(a) * 1.6, ZG - 1.4), (math.cos(a) * 2.35, math.sin(a) * 2.35, ZG - 0.25),
              0.07, "white")
    col.cyl(2.45, 0.25, (0, 0, ZG - 0.25), segs=8)
    rp = [(math.cos(2 * math.pi * (k + 0.5) / n) * 2.35, math.sin(2 * math.pi * (k + 0.5) / n) * 2.35) for k in range(n)]
    railing_ring(sh, rp, ZG, 1.05, "black", post_every=2, r=0.025)
    sh.cyl(1.35, 0.55, (0, 0, ZG), "red", segs=8, base=True, smooth=False)
    m = 8
    gl = [(math.cos(2 * math.pi * (k + 0.5) / m) * 1.25, math.sin(2 * math.pi * (k + 0.5) / m) * 1.25) for k in range(m)]
    zg0, zg1 = ZG + 0.55, ZG + 2.75
    for k in range(m):
        a, b = gl[k], gl[(k + 1) % m]
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        ln = math.hypot(mx, my)
        C.poly_up(sh, [(a[0], a[1], zg0), (b[0], b[1], zg0), (b[0], b[1], zg1), (a[0], a[1], zg1)], "@Glass",
                  up=(mx / ln, my / ln, 0))
        strut(sh, (a[0], a[1], zg0), (a[0], a[1], zg1), 0.04, "black")
    sh.cyl(1.25, 0.06, (0, 0, ZG + 1.6), "black", segs=8, caps=False)
    sh.cyl(0.35, 1.0, (0, 0, ZG + 0.55), "gray_dark", segs=8, base=True)
    sh.loft([ring(1.45, zg1), ring(1.45, zg1 + 0.15), ring(0.25, zg1 + 1.45)], "red", cap_start=True, cap_end=True)
    sh.sphere(0.22, (0, 0, zg1 + 1.6), "black", segs=8, rings=5)
    sh.cyl(0.03, 22.0 - (zg1 + 1.7), (0, 0, zg1 + 1.7), "steel", segs=4, base=True)
    # rotating lens assembly (part `lamp`)
    lm = K.MB()
    ZL = ZG + 1.45
    lm.cyl(0.18, 0.7, (0, 0, ZL - 0.35), "brass", segs=8, base=True)
    for ang in (0, 180):
        with lm.at((0, 0, ZL), rot=(0, 0, ang)):
            bx(lm, (-0.32, 0.18, -0.38), (0.32, 0.5, 0.38), "brass")
            bx(lm, (-0.27, 0.5, -0.33), (0.27, 0.56, 0.33), "emis_always_white")
    lm.to_object(root, "lamp", origin=(0, 0, ZL))
    K.marker(root, "light", (0, 0, ZL))

    C.cull_hidden(sh, C.ground_occ(-6, 6, -6, 6))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== lm_crane
NOTES["lm_crane"] = (
    "Ship-to-shore container gantry crane, tint_a_metal structure (the game tints it orange). Four box legs at "
    "x +-7, y +-11 (rail gauge 22 across Y; crane rails along X at y +-11), portal beams at z 20..22, boom girder "
    "z 24..25.6 from y +12 (machinery house end) to y -28 (outreach over the water, -Y), A-frame apex 30.0 with "
    "fore/back stays. Trolley + operator cab at y -16, spreader hanging at z 13. Stair flights up the +X/+Y leg. "
    "Static (no moving parts). col: 4 leg boxes + leg feet bogies.")


def build_lm_crane():
    root = K.begin_asset("lm_crane", C.CAT, spacing=60.0)
    sh, col = K.MB(), C.Col()
    MET, DARK = "tint_a_metal", "steel_dark"
    LX, LY = 7.0, 11.0
    ZP0, ZP1 = 20.0, 22.0
    ZB0, ZB1 = 24.0, 25.6
    BY0, BY1 = -28.0, 12.0
    # legs, bogies, rails
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * LX, sy * LY
            bx(sh, (x - 0.55, y - 0.55, 1.1), (x + 0.55, y + 0.55, ZP1), MET)
            bx(sh, (x - 0.8, y - 1.6, 0.25), (x + 0.8, y + 1.6, 1.1), MET)
            bx(sh, (x - 0.5, y - 1.5, 0.0), (x + 0.5, y + 1.5, 0.25), DARK)
            for dy in (-1.0, 0.0, 1.0):
                sh.cyl(0.32, 0.5, (x, y + dy, 0.32), "black", axis="X", segs=8, smooth=False)
            col.box((x - 0.8, y - 1.6, 0.0), (x + 0.8, y + 1.6, 1.1))
            col.box((x - 0.55, y - 0.55, 1.1), (x + 0.55, y + 0.55, ZP1))
    for sy in (-1, 1):
        bx(sh, (-13.0, sy * LY - 0.15, 0.0), (13.0, sy * LY + 0.15, 0.06), "steel")
    # portal beams + side frames + diagonal braces
    for sy in (-1, 1):
        bx(sh, (-LX - 0.6, sy * LY - 0.6, ZP0), (LX + 0.6, sy * LY + 0.6, ZP1), MET)
    for sx in (-1, 1):
        bx(sh, (sx * LX - 0.5, -LY, ZP0 + 0.3), (sx * LX + 0.5, LY, ZP1 - 0.2), MET)
        bx(sh, (sx * LX - 0.45, -LY, 9.0), (sx * LX + 0.45, LY, 10.0), MET)
        strut(sh, (sx * LX, -LY + 0.6, 10.0), (sx * LX, -2.0, ZP0 + 0.3), 0.3, MET)
        strut(sh, (sx * LX, LY - 0.6, 10.0), (sx * LX, 2.0, ZP0 + 0.3), 0.3, MET)
    # boom: two truss girders (chords + diagonals), cross members, walkway
    for sx in (-1, 1):
        x = sx * 1.6
        bx(sh, (x - 0.35, BY0, ZB1 - 0.4), (x + 0.35, BY1, ZB1), MET)
        bx(sh, (x - 0.35, BY0 + 2.0, ZB0), (x + 0.35, BY1, ZB0 + 0.4), MET)
        n = 10
        for k in range(n):
            ya = BY0 + 2.0 + (BY1 - BY0 - 2.0) * k / n
            yb = BY0 + 2.0 + (BY1 - BY0 - 2.0) * (k + 1) / n
            if k % 2 == 0:
                strut(sh, (x, ya, ZB0 + 0.2), (x, yb, ZB1 - 0.2), 0.1, MET)
            else:
                strut(sh, (x, ya, ZB1 - 0.2), (x, yb, ZB0 + 0.2), 0.1, MET)
            strut(sh, (x, ya, ZB0 + 0.2), (x, ya, ZB1 - 0.2), 0.08, MET)
    sh.box((0.7, 2.2, 0.4), (-1.6, BY0 + 1.0, ZB1 - 0.75), MET, rot=(-20, 0, 0))
    sh.box((0.7, 2.2, 0.4), (1.6, BY0 + 1.0, ZB1 - 0.75), MET, rot=(-20, 0, 0))
    for y in range(int(BY0) + 2, int(BY1), 4):
        bx(sh, (-1.6, y - 0.15, ZB1 - 0.35), (1.6, y + 0.15, ZB1 - 0.05), MET)
    bx(sh, (-1.25, BY0 + 1.0, ZB1), (1.25, BY1, ZB1 + 0.05), "steel")
    # A-frame + stays
    APX, APY, APZ = 1.5, 2.0, 30.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            strut(sh, (sx * LX, sy * (LY - 0.6), ZP1), (sx * APX, APY, APZ - 0.4), 0.35, MET, segs=6)
    bx(sh, (-APX - 0.4, APY - 0.4, APZ - 0.8), (APX + 0.4, APY + 0.4, APZ - 0.15), MET)
    sh.cyl(0.1, 0.15, (APX, APY, APZ - 0.15), "led_red", segs=6, base=True)
    sh.cyl(0.1, 0.15, (-APX, APY, APZ - 0.15), "led_red", segs=6, base=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(sh, (sx * 1.6 - 0.3, sy * LY - 0.3, ZP1), (sx * 1.6 + 0.3, sy * LY + 0.3, ZB0), MET)
    for sx in (-1, 1):
        strut(sh, (sx * APX, APY, APZ - 0.4), (sx * 1.6, BY0 + 1.0, ZB1), 0.06, DARK)
        strut(sh, (sx * APX, APY, APZ - 0.4), (sx * 1.6, -9.0, ZB1), 0.06, DARK)
        strut(sh, (sx * APX, APY, APZ - 0.4), (sx * 1.6, BY1 - 1.0, ZB1), 0.08, DARK)
    sh.cyl(0.12, 0.2, (0.0, BY0 + 0.5, ZB1 + 0.05), "led_red", segs=6, base=True)
    # machinery house on the back end
    bx(sh, (-2.4, 5.0, ZB1), (2.4, 11.6, ZB1 + 3.0), "white", colors={"+z": "gray_light"})
    bx(sh, (-2.5, 4.9, ZB1 + 3.0), (2.5, 11.7, ZB1 + 3.15), DARK)
    for k in range(3):
        C.pane(sh, "Y", 5.8 + k * 1.9, 6.9 + k * 1.9, ZB1 + 1.5, ZB1 + 2.3, 2.406, "@Window", 1)
        C.pane(sh, "Y", 5.8 + k * 1.9, 6.9 + k * 1.9, ZB1 + 1.5, ZB1 + 2.3, -2.406, "@Window", -1)
    C.pane(sh, "X", -1.5, 1.5, ZB1 + 0.4, ZB1 + 2.6, 4.994, "gray_mid", -1)
    sh.cyl(0.25, 1.2, (1.2, 9.5, ZB1 + 3.15), "steel", segs=6, base=True)
    # trolley + operator cab + hoist cables + spreader
    TY = -16.0
    bx(sh, (-2.1, TY - 2.0, ZB1), (2.1, TY + 2.0, ZB1 + 1.2), "white")
    bx(sh, (-2.15, TY - 2.05, ZB1 + 1.2), (2.15, TY + 2.05, ZB1 + 1.3), DARK)
    bx(sh, (0.8, TY - 1.2, ZB0 - 2.6), (2.6, TY + 1.0, ZB0 - 0.2), "white")
    for (axis, a0, a1, c, o) in (("X", 0.9, 2.5, TY - 1.2, -1), ("Y", TY - 1.1, TY + 0.9, 2.6, 1),
                                 ("Y", TY - 1.1, TY + 0.9, 0.8, -1)):
        C.pane(sh, axis, a0, a1, ZB0 - 1.8, ZB0 - 0.5, c + o * 0.006, "@Glass", o)
    strut(sh, (1.7, TY, ZB0 - 0.2), (1.7, TY, ZB0), 0.12, DARK)
    SZ = 13.0
    for (x, y) in ((-1.0, TY - 0.8), (1.0, TY - 0.8), (-1.0, TY + 0.8), (1.0, TY + 0.8)):
        strut(sh, (x * 0.6, y, ZB0), (x * 1.3, y + (0.6 if y > TY else -0.6), SZ + 0.6), 0.03, "black")
    bx(sh, (-3.1, TY - 1.25, SZ), (3.1, TY + 1.25, SZ + 0.5), "hazard_yellow")
    bx(sh, (-1.3, TY - 1.5, SZ + 0.5), (1.3, TY + 1.5, SZ + 0.9), "hazard_yellow")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(sh, (sx * 3.0 - 0.12, TY + sy * 1.15 - 0.12, SZ - 0.15), (sx * 3.0 + 0.12, TY + sy * 1.15 + 0.12, SZ),
               "black")
    # stair flights up the +X/+Y leg (zig-zag along X outside the leg)
    sx0 = LX + 0.75
    for i in range(5):
        z0, z1 = i * 4.0, (i + 1) * 4.0
        ya, yb = (LY - 3.0, LY + 1.5) if i % 2 == 0 else (LY + 1.5, LY - 3.0)
        ln = math.hypot(4.5, 4.0)
        ang = math.degrees(math.atan2(4.0, 4.5))
        sh.box((0.9, ln, 0.12), (sx0 + 0.45, (ya + yb) * 0.5, (z0 + z1) * 0.5), "steel",
               rot=(ang if yb > ya else -ang, 0, 0))
        strut(sh, (sx0 + 0.9, ya, z0 + 1.0), (sx0 + 0.9, yb, z1 + 1.0), 0.03, "hazard_yellow")
        bx(sh, (sx0, yb - (0.0 if yb > ya else 1.0), z1 - 0.1), (sx0 + 0.9, yb + (1.0 if yb > ya else 0.0), z1),
           "steel_dark")
    C.cull_hidden(sh, C.ground_occ(-16, 16, -32, 16))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== lm_parking_garage
NOTES["lm_parking_garage"] = (
    "Drivable 3-level parking structure 32 x 24 (x -16..16, y -12..12); deck tops z 0.02 (ground deck) / 3.2 / 6.4, "
    "slabs 0.3 thick (clear height 2.88 / 2.9). Entrance on +Y: opening x -3.6..4.0 (6.2 m clear lane x -3.6..2.6 + "
    "pay booth island x 2.6..3.9). Circulation: front lane y 5.5..11.75, back lane y -11.75..-4.5, two rows of 2.5 m "
    "bays in between (stair core occupies the two centre front bays, x -2.5..2.5, y 1..5.5, rising to 9.6 with the "
    "neon 'PARKING' sign). Ramp A (level 0 -> 1) in the -X strip x -15.75..-11.25, foot y 6 (z 0.02) up to y -7 "
    "(z 3.2), rising toward -Y; ramp B (level 1 -> 2) in the +X strip x 11.25..15.75 from y -7 (z 3.2) up to y 6 "
    "(z 6.4), rising toward +Y; both 4.5 wide over 13 m (13.8 deg). Ramp A is a solid wedge, ramp B a sloped slab "
    "(lane under it on level 0). Perimeter barriers 1.1 high with a horizontal slot, full walls beside the ramps, "
    "barriers round the slab openings. col: slabs, ramp prisms, barriers/walls, columns, stair core, booth. "
    "Markers: entrance (outside the entrance on the ground), top (top deck centre, z 6.4).")


def build_lm_parking_garage():
    root = K.begin_asset("lm_parking_garage", C.CAT, spacing=50.0)
    sh, col = K.MB(), C.Col()
    X0, X1, Y0, Y1, T = -16.0, 16.0, -12.0, 12.0, 0.25
    LV = [0.02, 3.2, 6.4]
    ST = 0.3
    CON, CON2, EDGE = "concrete_light", "concrete", "blue"
    AX0, AX1 = -15.75, -11.25          # ramp A (clear 4.5)
    BX0, BX1 = 11.25, 15.75            # ramp B
    RY0, RY1 = -7.0, 6.0               # ramp ends
    EN0, EN1, BO0, BO1 = -3.6, 4.0, 2.6, 3.9

    def slab(x0, x1, y0, y1, z):
        bx(sh, (x0, y0, z - ST), (x1, y1, z), CON, colors={"+z": "asphalt_light", "-z": CON2})
        col.box((x0, y0, z - ST), (x1, y1, z))

    # ---------------------------------------------------------------- decks
    sh.quad((X0 + T, Y0 + T, 0.02), (X1 - T, Y0 + T, 0.02), (X1 - T, Y1 - T, 0.02), (X0 + T, Y1 - T, 0.02), "asphalt")
    col.box((X0, Y0, 0.0), (X1, Y1, 0.02))
    z1, z2 = LV[1], LV[2]
    slab(X0, AX1 - 0.0, Y0, RY0, z1)
    slab(X0, AX1, RY1, Y1, z1)
    slab(AX1, BX0 - 0.25, Y0, Y1, z1)
    slab(BX0 - 0.25, X1, Y0, RY0, z1)
    slab(BX0 - 0.25, X1, RY1, Y1, z1)
    slab(X0, BX0 - 0.25, Y0, Y1, z2)
    slab(BX0 - 0.25, X1, Y0, RY0, z2)
    slab(BX0 - 0.25, X1, RY1, Y1, z2)
    # slab edge fascia stripes
    for z in (z1, z2):
        C.band(sh, X0, X1, Y0, Y1, z - 0.22, z - 0.08, 0.01, EDGE, flat=True)

    # ---------------------------------------------------------------- ramps
    sh.prism([(RY1, 0.02), (RY0, z1), (RY0, 0.0), (RY1, 0.0)], AX1 - AX0, CON2, plane="YZ",
             pos=((AX0 + AX1) * 0.5, 0, 0), side_colors=["asphalt_light", CON2, CON2, CON2])
    col.prism([(RY1, 0.02), (RY0, z1), (RY0, 0.0), (RY1, 0.0)], AX1 - AX0, plane="YZ", pos=((AX0 + AX1) * 0.5, 0, 0))
    sh.prism([(RY0, z1), (RY1, z2), (RY1, z2 - ST), (RY0, z1 - ST)], BX1 - BX0, CON, plane="YZ",
             pos=((BX0 + BX1) * 0.5, 0, 0), side_colors=["asphalt_light", CON, CON2, CON])
    col.slope_y(RY0, z1, RY1, z2, BX0, BX1, thick=ST)
    for (xa, xb, za, zb, ya, yb) in ((AX0 + 0.15, AX0 + 0.25, 0.02, z1, RY1, RY0), (AX1 - 0.25, AX1 - 0.15, 0.02, z1, RY1, RY0),
                                     (BX0 + 0.15, BX0 + 0.25, z1, z2, RY0, RY1), (BX1 - 0.25, BX1 - 0.15, z1, z2, RY0, RY1)):
        C.poly_up(sh, [(xa, ya, za + 0.006), (xb, ya, za + 0.006), (xb, yb, zb + 0.006), (xa, yb, zb + 0.006)],
                  "line_yellow")

    # ---------------------------------------------------------------- walls / barriers
    def barrier(x0, x1, y0, y1, z, h=1.1, slot=True, c=CON):
        if slot:
            bx(sh, (x0, y0, z), (x1, y1, z + 0.45), c)
            bx(sh, (x0, y0, z + 0.65), (x1, y1, z + h), c)
            # slot backing posts every ~4 m so the bands read as precast panels
            if (x1 - x0) > (y1 - y0):
                n = max(1, int((x1 - x0) / 4.0))
                for k in range(1, n):
                    x = x0 + (x1 - x0) * k / n
                    bx(sh, (x - 0.1, y0, z + 0.45), (x + 0.1, y1, z + 0.65), c)
            else:
                n = max(1, int((y1 - y0) / 4.0))
                for k in range(1, n):
                    y = y0 + (y1 - y0) * k / n
                    bx(sh, (x0, y - 0.1, z + 0.45), (x1, y + 0.1, z + 0.65), c)
        else:
            bx(sh, (x0, y0, z), (x1, y1, z + h), c)
        col.box((x0, y0, z), (x1, y1, z + h))

    # level 0: perimeter (entrance gap), full walls along ramp A
    barrier(X0, EN0, Y1 - T, Y1, 0.0)
    barrier(EN1, X1, Y1 - T, Y1, 0.0)
    barrier(X0, X1, Y0, Y0 + T, 0.0)
    barrier(X1 - T, X1, Y0 + T, Y1 - T, 0.0)
    barrier(X0, X0 + T, Y0 + T, RY0, 0.0)
    barrier(X0, X0 + T, RY1, Y1 - T, 0.0)
    bx(sh, (X0, RY0, 0.0), (X0 + T, RY1, z1 - ST), CON)
    col.box((X0, RY0, 0.0), (X0 + T, RY1, z1 - ST))
    bx(sh, (AX1, RY0, 0.0), (AX1 + 0.25, RY1, z1 - ST), CON, colors={"+x": CON2})
    col.box((AX1, RY0, 0.0), (AX1 + 0.25, RY1, z1 - ST))
    # level 1: perimeter, barriers round the ramp A opening, full walls along ramp B
    barrier(X0, X1, Y1 - T, Y1, z1)
    barrier(X0, X1, Y0, Y0 + T, z1)
    barrier(X0, X0 + T, Y0 + T, Y1 - T, z1)
    barrier(X1 - T, X1, Y0 + T, RY0, z1)
    barrier(X1 - T, X1, RY1, Y1 - T, z1)
    barrier(AX1, AX1 + 0.25, RY0, RY1, z1)
    barrier(AX0, AX1, RY1, RY1 + 0.25, z1)
    bx(sh, (X1 - T, RY0, z1), (X1, RY1, z2), CON)
    col.box((X1 - T, RY0, z1), (X1, RY1, z2))
    bx(sh, (BX0 - 0.25, RY0, z1 - ST), (BX0, RY1, z2), CON, colors={"-x": CON2})
    col.box((BX0 - 0.25, RY0, z1 - ST), (BX0, RY1, z2))
    # level 2 (open top deck): perimeter + barriers round the ramp B opening
    barrier(X0, X1, Y1 - T, Y1, z2)
    barrier(X0, X1, Y0, Y0 + T, z2)
    barrier(X0, X0 + T, Y0 + T, Y1 - T, z2)
    barrier(X1 - T, X1, Y0 + T, RY0, z2)
    barrier(X1 - T, X1, RY1, Y1 - T, z2)
    barrier(BX0 - 0.25, BX0, RY0, RY1, z2)
    barrier(BX0 - 0.25, X1 - T, RY0 - 0.25, RY0, z2)
    # cap stripes on the top barrier
    C.band(sh, X0, X1, Y0, Y1, z2 + 0.85, z2 + 1.0, 0.006, EDGE, flat=True)

    # ---------------------------------------------------------------- columns
    colpts = [(-7.5, 0.5), (0.0, 0.5), (7.5, 0.5), (-7.5, Y1 - 0.35), (7.5, Y1 - 0.35), (-7.5, Y0 + 0.35),
              (0.0, Y0 + 0.35), (7.5, Y0 + 0.35), (X0 + 0.35, Y0 + 0.35), (X1 - 0.35, Y0 + 0.35),
              (X0 + 0.35, Y1 - 0.35), (X1 - 0.35, Y1 - 0.35)]
    for (x, y) in colpts:
        bx(sh, (x - 0.25, y - 0.25, 0.0), (x + 0.25, y + 0.25, z2 - ST), CON2)
        col.box((x - 0.25, y - 0.25, 0.0), (x + 0.25, y + 0.25, z2 - ST))

    # ---------------------------------------------------------------- bay lines, arrows, lights
    for z in LV:
        zz = z + 0.005
        for row, (ya, yb) in enumerate(((0.6, 5.4), (-4.4, 0.4))):
            for k in range(9):
                x = -10.0 + 2.5 * k
                if row == 0 and -2.6 < x < 2.6:
                    continue
                F.floor_quad(sh, x - 0.06, x + 0.06, ya, yb, zz, "line_white")
            ye = yb if row == 0 else ya
            for (xa, xb) in ((-10.06, -2.5), (2.5, 10.06)) if row == 0 else ((-10.06, 10.06),):
                F.floor_quad(sh, xa, xb, ye - 0.06, ye + 0.06, zz, "line_white")
        for (x, y, rz) in ((-6.0, 8.6, 90), (6.0, 8.6, 90), (-6.0, -8.1, -90), (6.0, -8.1, -90)):
            with sh.at((x, y, zz), rot=(0, 0, rz)):
                C.poly_up(sh, [(-0.35, -0.6, 0), (0.0, 0.2, 0), (0.35, -0.6, 0), (0.0, -0.3, 0)], "line_white")
    for z in (z1, z2):
        for (x, y) in ((-6.0, 8.6), (6.0, 8.6), (-6.0, -8.1), (6.0, -8.1), (-6.0, 0.5), (6.0, 0.5)):
            bx(sh, (x - 0.7, y - 0.09, z - ST - 0.06), (x + 0.7, y + 0.09, z - ST), "gray_mid",
               colors={"-z": "emis_cool_always"})
    for (x, y) in ((-10.0, 0.5), (-5.0, 0.5), (5.0, 0.5), (10.0, 0.5)):
        sh.cyl(0.07, 4.0, (x, y, z2), "gray_dark", segs=6, base=True)
        bx(sh, (x - 0.35, y - 0.12, z2 + 3.9), (x + 0.35, y + 0.12, z2 + 4.05), "gray_dark", colors={"-z": "emis_lamp"})
        col.box((x - 0.1, y - 0.1, z2), (x + 0.1, y + 0.1, z2 + 4.0))

    # ---------------------------------------------------------------- stair core with the PARKING sign
    SX0, SX1, SY0, SY1, SZ = -2.5, 2.5, 1.0, 5.5, z2 + 3.2
    bx(sh, (SX0, SY0, 0.0), (SX1, SY1, SZ), CON, colors={"+z": "roof_gravel"})
    bx(sh, (SX0 - 0.08, SY0 - 0.08, SZ), (SX1 + 0.08, SY1 + 0.08, SZ + 0.15), "gray_light")
    col.box((SX0, SY0, 0.0), (SX1, SY1, SZ + 0.15))
    for z in LV:
        bx(sh, (-0.55, SY1, z), (0.55, SY1 + 0.04, z + 2.15), "steel_dark")
        bx(sh, (-0.65, SY1, z + 2.15), (0.65, SY1 + 0.06, z + 2.25), EDGE)
        C.pane(sh, "X", 0.9, 2.1, z + 0.9, z + 2.4, SY1 + 0.006, "@Window", 1)
    for out in (1, -1):
        yf = SY1 if out > 0 else SY0
        bx(sh, (SX0 - 0.05, min(yf, yf + out * 0.12), z2 + 0.6), (SX1 + 0.05, max(yf, yf + out * 0.12), SZ - 0.15), "navy")
        C.sign(sh, "PARKING", (0.0, yf + out * 0.12, z2 + 1.85), 4.4, 0.9, "neon_blue", depth=0.08, res=TXT_RES,
               valign="center", rot=None if out > 0 else (0, 0, 180))
    for x in (SX0, SX1):
        o = 1 if x > 0 else -1
        C.pane(sh, "Y", SY0 + 0.6, SY1 - 0.6, z2 + 1.0, SZ - 0.5, x + o * 0.006, "@Window", o)

    # ---------------------------------------------------------------- entrance: booth island, raised boom, P sign
    bx(sh, (BO0, 10.0, 0.0), (BO1, Y1 + 0.3, 0.15), "hazard_yellow")
    bx(sh, (BO0 + 0.1, 10.3, 0.15), (BO1 - 0.1, 11.7, 1.0), "white")
    bx(sh, (BO0 + 0.1, 10.3, 2.3), (BO1 - 0.1, 11.7, 2.45), EDGE)
    for (axis, a0, a1, c, o) in (("X", BO0 + 0.15, BO1 - 0.15, 11.7, 1), ("X", BO0 + 0.15, BO1 - 0.15, 10.3, -1),
                                 ("Y", 10.35, 11.65, BO0 + 0.1, -1), ("Y", 10.35, 11.65, BO1 - 0.1, 1)):
        C.pane(sh, axis, a0, a1, 1.0, 2.3, c, "@Glass", o)
    for (x, y) in ((BO0 + 0.1, 10.3), (BO1 - 0.1, 10.3), (BO0 + 0.1, 11.7), (BO1 - 0.1, 11.7)):
        bx(sh, (x - 0.04, y - 0.04, 1.0), (x + 0.04, y + 0.04, 2.3), "white")
    col.box((BO0, 10.0, 0.0), (BO1, Y1 + 0.3, 2.45))
    bx(sh, (BO0 + 0.02, Y1 + 0.0, 0.15), (BO0 + 0.2, Y1 + 0.25, 1.1), "gray_dark")
    bx(sh, (BO0 + 0.07, Y1 + 0.08, 1.1), (BO0 + 0.15, Y1 + 0.16, 4.4), "white")
    for k in range(3):
        bx(sh, (BO0 + 0.065, Y1 + 0.075, 1.6 + k * 1.0), (BO0 + 0.155, Y1 + 0.165, 1.9 + k * 1.0), "red")
    bx(sh, (EN0 - 1.2, Y1, 1.4), (EN0 - 0.2, Y1 + 0.08, 2.4), EDGE)
    C.sign(sh, "P", (EN0 - 0.7, Y1 + 0.08, 1.9), 0.8, 0.7, "white", depth=0.04, res=1, valign="center")
    bx(sh, (EN0 - 0.75, Y1, 0.0), (EN0 - 0.65, Y1 + 0.06, 1.4), "gray_dark")

    C.cull_hidden(sh, C.ground_occ(-17, 17, -13, 13.5))
    sh.to_object(root, "shell", sharp_angle=35)
    col.to_object(root)
    K.marker(root, "entrance", (-0.5, Y1 + 2.0, 0.0), (0, 0, 180))
    K.marker(root, "top", (0.0, -2.0, z2), (0, 0, 0))
    return root


# =========================================================================== build all
BUILDERS = [("lm_radio_tower", build_lm_radio_tower), ("lm_water_tower", build_lm_water_tower),
            ("lm_lighthouse", build_lm_lighthouse), ("lm_crane", build_lm_crane),
            ("lm_parking_garage", build_lm_parking_garage)]


def build_all(only=None):
    out = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
        out.append(export(name))
    return "\n".join(out)
