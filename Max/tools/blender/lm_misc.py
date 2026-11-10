"""lm_misc - plaza / park / marina landmarks for NEON TIDE (SPEC_LANDMARKS.md, P2 small pieces + P3).

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C, lm_fix as F, lm_misc as M
    for m in (K, C, F, M): importlib.reload(m)
    print(M.build_all())
"""
import math
import random

import gta_kit as K
import lm_common as C
import lm_fix as F
from lm_common import bx
from lm_towers import col_strut

NOTES = {}
TXT_RES = 2


def export(name):
    return C.finish(name, NOTES.get(name, ""))


def ring(r, z, n=16, rot=0.0, cx=0.0, cy=0.0):
    return [(cx + math.cos(2 * math.pi * k / n + rot) * r, cy + math.sin(2 * math.pi * k / n + rot) * r, z) for k in range(n)]


def annulus(mb, r0, r1, z, color, n=16, up=True):
    """Flat ring between radii r0 < r1 at height z (normal up or down)."""
    a, b = ring(r1, z, n), ring(r0, z, n)
    for k in range(n):
        k2 = (k + 1) % n
        C.poly_up(mb, [a[k], a[k2], b[k2], b[k]], color, up=(0, 0, 1 if up else -1))


def tube_ring(mb, r, z, rr, color, n=16, segs=4):
    """Closed horizontal tube (rail ring) of radius r at height z."""
    pts = [p for p in ring(r, z, n)]
    pts.append(pts[0])
    mb.tube(pts, rr, color, segs=segs, caps=False)


def torus(mb, pos, R=0.32, r=0.07, axis="Y", colors=("safety_orange", "white"), n=12, m=6):
    """Life ring: torus around `axis` with 4 alternating colour quarters."""
    x0, y0, z0 = pos
    rings = []
    for i in range(n + 1):
        a = 2 * math.pi * i / n
        ca, sa = math.cos(a), math.sin(a)
        rr = []
        for j in range(m):
            b = 2 * math.pi * j / m
            u = R + r * math.cos(b)
            v = r * math.sin(b)
            if axis == "Y":
                rr.append((x0 + ca * u, y0 + v, z0 + sa * u))
            else:
                rr.append((x0 + v, y0 + ca * u, z0 + sa * u))
        rings.append(rr)
    for i in range(n):
        c = colors[(i * 4 // n) % len(colors)]
        mb.loft([rings[i], rings[i + 1]], c, cap_start=False, cap_end=False, smooth=True)


# =========================================================================== lm_fountain
NOTES["lm_fountain"] = (
    "Plaza fountain dia 8.0: granite step ring (r 4.0), marble basin wall r 3.3..3.7 up to z 0.8, water surface "
    "(ice_blue) at z 0.55, eight arcing jets, two-tier centre piece with water curtains (ice_blue) and a spray top "
    "(3.3). col: 12 boxes forming the basin ring, basin floor at z 0.45 (you can wade in), centre pedestal.")


def build_lm_fountain():
    root = K.begin_asset("lm_fountain", C.CAT, spacing=30.0)
    sh, col = K.MB(), C.Col()
    n = 24
    sh.cyl(4.0, 0.15, (0, 0, 0), "granite", segs=n, base=True, smooth=False)
    # basin wall: outer face, coping, inner face; water
    sh.loft([ring(3.6, 0.15, n), ring(3.6, 0.7, n)], "marble", cap_start=False, cap_end=False, smooth=True)
    sh.loft([ring(3.72, 0.7, n), ring(3.72, 0.8, n)], "marble", cap_start=False, cap_end=False, smooth=True)
    annulus(sh, 3.25, 3.72, 0.8, "marble", n)
    annulus(sh, 3.6, 3.72, 0.7, "marble", n, up=False)
    sh.loft([ring(3.25, 0.8, n), ring(3.25, 0.5, n)], "marble", cap_start=False, cap_end=False, smooth=True,
            fix_normals=False)
    C.disc(sh, (0, 0, 0.55), 3.26, "ice_blue", axis="Z", segs=n)
    # centre piece: pedestal, lower bowl, column, upper bowl, finial + spray
    sh.cyl(0.55, 0.8, (0, 0, 0.55), "marble", segs=8, base=True, smooth=False)
    sh.loft([ring(0.4, 1.3, 12), ring(1.45, 1.55, 12), ring(1.6, 1.7, 12), ring(1.5, 1.72, 12)], "marble",
            cap_start=True, cap_end=False, smooth=True)
    C.disc(sh, (0, 0, 1.66), 1.5, "ice_blue", axis="Z", segs=12)
    sh.cyl(0.18, 0.85, (0, 0, 1.66), "marble", segs=8, base=True)
    sh.loft([ring(0.2, 2.5, 10), ring(0.75, 2.66, 10), ring(0.82, 2.76, 10), ring(0.74, 2.77, 10)], "marble",
            cap_start=True, cap_end=False, smooth=True)
    C.disc(sh, (0, 0, 2.73), 0.75, "ice_blue", axis="Z", segs=10)
    sh.cyl(0.07, 0.35, (0, 0, 2.73), "marble", segs=6, base=True)
    sh.ico(0.22, (0, 0, 3.12), "foam_white", subdiv=1, jitter=0.25, seed=2)
    # water curtains falling from the bowls + foam rings
    sh.cyl(1.62, 1.05, (0, 0, 0.6), "@Glass", segs=12, base=True, caps=False)
    sh.cyl(0.84, 0.95, (0, 0, 1.7), "@Glass", segs=10, base=True, caps=False)
    sh.cyl(1.78, 0.07, (0, 0, 0.55), "foam_white", segs=12, base=True, caps=False)
    sh.cyl(0.98, 0.06, (0, 0, 1.66), "foam_white", segs=10, base=True, caps=False)
    # eight arcing jets from the rim toward the centre
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        ca, sa = math.cos(a), math.sin(a)
        sh.tube([(ca * 3.25, sa * 3.25, 0.82), (ca * 2.7, sa * 2.7, 1.45), (ca * 2.15, sa * 2.15, 1.25),
                 (ca * 1.9, sa * 1.9, 0.56)], 0.05, "foam_white", segs=4, caps=False)
        sh.cyl(0.07, 0.06, (ca * 3.35, sa * 3.35, 0.8), "bronze", segs=6, base=True)
    # col: basin ring of 12 boxes, wading floor, pedestal
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        col.cbox((0.45, 2.0, 0.8), (math.cos(a) * 3.48, math.sin(a) * 3.48, 0.4), rot=(0, 0, math.degrees(a)))
    col.cyl(3.3, 0.45, (0, 0, 0), segs=12)
    col.cyl(0.6, 2.8, (0, 0, 0), segs=8)
    col.cyl(1.6, 0.4, (0, 0, 1.3), segs=8)
    C.cull_hidden(sh, C.ground_occ(-5, 5, -5, 5))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== lm_statue
NOTES["lm_statue"] = (
    "Abstract sculpture 3 x 3 x 6: granite step + bevelled plinth (2.2 sq, top 1.6) with a bronze plaque on +Y, six "
    "twisted stacked triangular prisms in bronze rising to 6.0. col: step, plinth, sculpture box.")


def build_lm_statue():
    root = K.begin_asset("lm_statue", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    bx(sh, (-1.5, -1.5, 0.0), (1.5, 1.5, 0.2), "granite", bevel=0.03)
    bx(sh, (-1.1, -1.1, 0.2), (1.1, 1.1, 1.6), "granite", bevel=0.05)
    bx(sh, (-1.16, -1.16, 1.5), (1.16, 1.16, 1.6), "rock_dark", bevel=0.02)
    bx(sh, (-0.45, 1.1, 0.75), (0.45, 1.13, 1.15), "bronze")
    C.pane(sh, "X", -0.36, 0.36, 0.95, 0.99, 1.134, "gold", 1)
    C.pane(sh, "X", -0.3, 0.3, 0.86, 0.89, 1.134, "gold", 1)
    col.box((-1.5, -1.5, 0.0), (1.5, 1.5, 0.2))
    col.box((-1.16, -1.16, 0.2), (1.16, 1.16, 1.6))
    z = 1.6
    for i in range(6):
        h = 0.73 - i * 0.04
        rad = 0.8 - i * 0.07
        rot = math.radians(i * 38)
        ox, oy = 0.16 * math.cos(i * 1.2), 0.16 * math.sin(i * 1.2)
        tri = [(ox + math.cos(rot + 2 * math.pi * k / 3) * rad, oy + math.sin(rot + 2 * math.pi * k / 3) * rad)
               for k in range(3)]
        sh.prism(tri, h, "bronze" if i % 2 == 0 else "copper", plane="XY", pos=(0, 0, z), center=False)
        sh.prism([(p[0] * 0.55, p[1] * 0.55) for p in tri], 0.05, "gold", plane="XY", pos=(0, 0, z + h), center=False,
                 caps=(False, True))
        z += h + 0.05
    sh.ico(0.18, (0.05, 0.0, z + 0.12), "gold", subdiv=1)
    col.box((-0.8, -0.8, 1.6), (0.8, 0.8, z + 0.3))
    C.cull_hidden(sh, C.ground_occ(-2, 2, -2, 2))
    sh.to_object(root, "shell")
    col.to_object(root)
    return root


# =========================================================================== lm_viewpoint
NOTES["lm_viewpoint"] = (
    "Hilltop viewing deck 9 x 6 (x -4.5..4.5, y -3..3), timber deck top z 0.6 on posts reaching down to z -1.4 "
    "(sink into slopes), railing on the front (+Y = view direction) and sides, steps down at the back (-Y, x -0.8..0.8) "
    "to z 0. Two coin binoculars at the front rail, bench, info board. Marker `view` at the front rail centre (deck "
    "height, looking +Y). col: deck box, railing boxes, steps slope, binocular posts, bench, board.")


def build_lm_viewpoint():
    root = K.begin_asset("lm_viewpoint", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    X0, X1, Y0, Y1, ZD = -4.5, 4.5, -3.0, 3.0, 0.6
    WD, WL = "wood_dark", "wood_light"
    # posts + beams + deck boards
    for x in (X0 + 0.15, -1.5, 1.5, X1 - 0.15):
        for y in (Y0 + 0.15, Y1 - 0.15):
            bx(sh, (x - 0.1, y - 0.1, -1.4), (x + 0.1, y + 0.1, ZD - 0.12), WD)
        bx(sh, (x - 0.08, Y0, ZD - 0.32), (x + 0.08, Y1, ZD - 0.12), WD)
    bx(sh, (X0, Y0, ZD - 0.12), (X1, Y1, ZD), WL, colors={"-z": WD})
    for k in range(1, 15):
        y = Y0 + 6.0 * k / 15
        sh.quad((X0 + 0.02, y - 0.008, ZD + 0.003), (X1 - 0.02, y - 0.008, ZD + 0.003), (X1 - 0.02, y + 0.008, ZD + 0.003),
                (X0 + 0.02, y + 0.008, ZD + 0.003), WD)
    col.box((X0, Y0, ZD - 0.32), (X1, Y1, ZD))
    for x in (X0 + 0.15, X1 - 0.15):
        for y in (Y0 + 0.15, Y1 - 0.15):
            col.box((x - 0.1, y - 0.1, -1.4), (x + 0.1, y + 0.1, ZD))
    # railing (front + sides + back corners) with cable infill
    rail = [((X0 + 0.06, Y0 + 0.06), (X0 + 0.06, Y1 - 0.06)), ((X0 + 0.06, Y1 - 0.06), (X1 - 0.06, Y1 - 0.06)),
            ((X1 - 0.06, Y1 - 0.06), (X1 - 0.06, Y0 + 0.06)), ((X0 + 0.06, Y0 + 0.06), (-0.9, Y0 + 0.06)),
            ((0.9, Y0 + 0.06), (X1 - 0.06, Y0 + 0.06))]
    for (a, b) in rail:
        xa, xb = min(a[0], b[0]) - 0.05, max(a[0], b[0]) + 0.05
        ya, yb = min(a[1], b[1]) - 0.05, max(a[1], b[1]) + 0.05
        bx(sh, (xa, ya, ZD + 1.0), (xb, yb, ZD + 1.1), WL, bevel=0.01)
        ln = max(xb - xa, yb - ya)
        n = max(1, int(round(ln / 1.5)))
        for k in range(n + 1):
            t = k / n
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            bx(sh, (x - 0.06, y - 0.06, ZD), (x + 0.06, y + 0.06, ZD + 1.0), WD)
        for z in (ZD + 0.35, ZD + 0.7):
            if xb - xa > yb - ya:
                bx(sh, (xa, (ya + yb) * 0.5 - 0.008, z - 0.008), (xb, (ya + yb) * 0.5 + 0.008, z + 0.008), "steel")
            else:
                bx(sh, ((xa + xb) * 0.5 - 0.008, ya, z - 0.008), ((xa + xb) * 0.5 + 0.008, yb, z + 0.008), "steel")
        col.box((xa, ya, ZD), (xb, yb, ZD + 1.1))
    # steps down at the back
    for i in range(3):
        y0 = Y0 - 0.3 * (i + 1)
        bx(sh, (-0.8, y0, ZD - 0.2 * (i + 1) - 0.4), (0.8, y0 + 0.3, ZD - 0.2 * (i + 1) + 0.0), WL, colors={"-y": WD})
    col.slope_y(Y0, ZD, Y0 - 0.95, 0.0, -0.8, 0.8, thick=0.6)
    # coin binoculars
    for x in (-2.0, 2.0):
        with sh.at((x, Y1 - 0.55, ZD)):
            sh.cyl(0.18, 0.05, (0, 0, 0), "steel_dark", segs=8, base=True, smooth=False)
            sh.cyl(0.06, 1.15, (0, 0, 0.05), "teal", segs=6, base=True)
            bx(sh, (-0.12, -0.1, 1.2), (0.12, 0.12, 1.42), "teal", bevel=0.02)
            for sx in (-0.07, 0.07):
                sh.cyl(0.06, 0.3, (sx, 0.18, 1.33), "teal", axis="Y", segs=8, cap_color="black")
                sh.cyl(0.04, 0.08, (sx, -0.14, 1.33), "black", axis="Y", segs=6)
            bx(sh, (-0.06, -0.16, 1.0), (0.06, -0.06, 1.15), "yellow")
        col.box((x - 0.15, Y1 - 0.7, ZD), (x + 0.15, Y1 - 0.4, ZD + 1.45))
    # bench + info board
    with sh.at((0.0, 0.3, ZD)):
        for x in (-0.75, 0.71):
            bx(sh, (x, -0.2, 0.0), (x + 0.04, 0.2, 0.42), "charcoal")
        for k in range(3):
            bx(sh, (-0.9, -0.18 + k * 0.13, 0.42), (0.9, -0.08 + k * 0.13, 0.46), WL)
        bx(sh, (-0.9, -0.24, 0.55), (0.9, -0.2, 0.85), WL)
    col.box((-0.9, 0.06, ZD), (0.9, 0.5, ZD + 0.46))
    with sh.at((-3.3, -1.6, ZD), rot=(0, 0, 0)):
        for x in (-0.6, 0.56):
            bx(sh, (x, -0.04, 0.0), (x + 0.04, 0.0, 1.5), WD)
        sh.box((1.3, 0.06, 0.8), (0.0, 0.02, 1.2), WD, rot=(-20, 0, 0))
        with sh.at((0.0, 0.055, 1.2), rot=(-20, 0, 0)):
            C.pane(sh, "X", -0.58, 0.58, -0.35, 0.35, 0.006, "sky_blue", 1)
            C.pane(sh, "X", -0.58, 0.05, -0.35, 0.12, 0.009, "grass", 1)
            C.pane(sh, "X", -0.2, 0.3, 0.0, 0.35, 0.012, "sand", 1)
            C.pane(sh, "X", -0.12, -0.04, 0.05, 0.13, 0.015, "red", 1)
    col.box((-3.95, -1.7, ZD), (-2.65, -1.4, ZD + 1.6))
    C.cull_hidden(sh)
    sh.to_object(root, "shell")
    col.to_object(root)
    K.marker(root, "view", (0.0, Y1 - 0.6, ZD), (0, 0, 0))
    return root


# =========================================================================== lm_gazebo
NOTES["lm_gazebo"] = (
    "Octagonal park gazebo dia 5: platform top z 0.45 (r 2.5) with two steps on +Y, 8 white posts, railing with "
    "balusters (open on +Y), benches inside, teal octagonal roof (eave 3.0, apex 4.5) with a gold finial to 5.0. "
    "col: platform prism, step slope, posts, railing segments, roof pyramid.")


def build_lm_gazebo():
    root = K.begin_asset("lm_gazebo", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    n = 8
    rot = math.pi / 8
    oct_ = lambda r: [(math.cos(2 * math.pi * k / n + rot) * r, math.sin(2 * math.pi * k / n + rot) * r) for k in range(n)]
    ZP = 0.45
    sh.prism(oct_(2.5), ZP, "white", plane="XY", pos=(0, 0, 0), center=False, cap_colors=("white", "wood_light"))
    sh.prism(oct_(2.58), 0.06, "white", plane="XY", pos=(0, 0, ZP - 0.06), center=False, caps=(True, True),
             cap_colors=("white", "wood_light"))
    col.prism(oct_(2.5), ZP, plane="XY", pos=(0, 0, 0), center=False)
    for i in range(2):
        y0 = 2.31 + 0.3 * i
        bx(sh, (-0.8, y0, 0.0), (0.8, y0 + 0.32, ZP - 0.15 * (i + 1)), "white", colors={"+z": "wood_light"})
    col.slope_y(2.3, ZP, 2.95, 0.0, -0.8, 0.8, thick=0.45)
    # posts, railing between posts (front +Y segment open), benches
    pp = oct_(2.25)
    for k, (x, y) in enumerate(pp):
        bx(sh, (x - 0.08, y - 0.08, ZP), (x + 0.08, y + 0.08, 3.0), "white")
        col.box((x - 0.08, y - 0.08, ZP), (x + 0.08, y + 0.08, 3.0))
    for k in range(n):
        a, b = pp[k], pp[(k + 1) % n]
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        if my > 2.0:
            continue
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        sh.box((ln, 0.08, 0.06), (mx, my, ZP + 0.92), "white", rot=(0, 0, ang))
        sh.box((ln, 0.06, 0.05), (mx, my, ZP + 0.12), "white", rot=(0, 0, ang))
        for j in range(1, 5):
            t = j / 5
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            bx(sh, (x - 0.02, y - 0.02, ZP + 0.14), (x + 0.02, y + 0.02, ZP + 0.89), "white")
        col.cbox((ln, 0.12, 0.95), (mx, my, ZP + 0.48), rot=(0, 0, ang))
        if my < -1.0:
            nx_, ny_ = -mx / math.hypot(mx, my), -my / math.hypot(mx, my)
            sh.box((ln * 0.8, 0.38, 0.05), (mx + nx_ * 0.3, my + ny_ * 0.3, ZP + 0.44), "wood_mid", rot=(0, 0, ang))
            for s in (-0.3, 0.3):
                sh.box((0.05, 0.3, 0.42), (mx + nx_ * 0.3 + math.cos(math.radians(ang)) * s * ln,
                                           my + ny_ * 0.3 + math.sin(math.radians(ang)) * s * ln, ZP + 0.21), "wood_dark",
                       rot=(0, 0, ang))
    # eave ring, decorative brackets, roof pyramid, finial
    eave = oct_(2.85)
    sh.prism(eave, 0.18, "white", plane="XY", pos=(0, 0, 2.95), center=False, cap_colors=("white", "roof_teal"))
    for (x, y) in pp:
        ang = math.degrees(math.atan2(y, x))
        with sh.at((x * 0.97, y * 0.97, 2.95), rot=(0, 0, ang - 90)):
            sh.prism([(-0.4, 0.0), (0.4, 0.0), (0.0, -0.3)], 0.05, "white", plane="XZ", pos=(0, 0, 0))
    apex = (0, 0, 4.5)
    for k in range(n):
        a, b = eave[k], eave[(k + 1) % n]
        C.poly_up(sh, [(a[0], a[1], 3.13), (b[0], b[1], 3.13), apex], "roof_teal")
    for (x, y) in eave:
        sh.tube([(x, y, 3.14), (0, 0, 4.5)], 0.04, "white", segs=4, caps=False)
    sh.cyl(0.12, 0.2, (0, 0, 4.4), "white", segs=8, base=True)
    sh.sphere(0.13, (0, 0, 4.72), "gold", segs=8, rings=5)
    sh.cyl(0.025, 0.3, (0, 0, 4.8), "gold", segs=4, base=True)
    col.cyl(2.85, 1.55, (0, 0, 2.95), segs=8, r2=0.1)
    C.cull_hidden(sh, C.ground_occ(-3, 3, -3, 4))
    sh.to_object(root, "shell")
    col.to_object(root)
    return root


# =========================================================================== lm_boathouse
NOTES["lm_boathouse"] = (
    "Marina shack 7 x 5 (x -3.5..3.5, y -2.5..2.5), board-and-batten walls, gable roof (ridge along X, top 4.0), not "
    "enterable. Front (+Y, faces the water) with a service hatch + propped flap, closed door, neon 'MARINA' sign "
    "(neon_cyan) on the fascia, two life rings, plank deck y 2.5..3.7 (top z 0.2) with mooring bollards, rope coil and "
    "a boat fuel pump at the +X end of the deck. col: body box, deck slab, pump, bollards.")


def build_lm_boathouse():
    root = K.begin_asset("lm_boathouse", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    X0, X1, Y0, Y1 = -3.5, 3.5, -2.5, 2.5
    ZE, ZR = 2.75, 4.0
    WALL, BAT, TRIM = "plank_gray", "wood_dark", "white"
    # body with a stone plinth, battens, corner trims
    bx(sh, (X0, Y0, 0.0), (X1, Y1, ZE), WALL)
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.35, 0.03, "rock_dark")
    for (axis, a0, a1, c, o) in (("X", X0, X1, Y1, 1), ("X", X0, X1, Y0, -1), ("Y", Y0, Y1, X1, 1), ("Y", Y0, Y1, X0, -1)):
        k = a0 + 0.45
        while k < a1 - 0.2:
            if axis == "X":
                if o > 0 and (-2.6 < k < 0.6 or 1.55 < k < 2.75):
                    k += 0.5
                    continue
                bx(sh, (k - 0.03, min(c, c + o * 0.025), 0.35), (k + 0.03, max(c, c + o * 0.025), ZE), BAT)
            else:
                bx(sh, (min(c, c + o * 0.025), k - 0.03, 0.35), (max(c, c + o * 0.025), k + 0.03, ZE), BAT)
            k += 0.5
    for (x, y) in ((X0, Y0), (X1, Y0), (X0, Y1), (X1, Y1)):
        bx(sh, (x - 0.06, y - 0.06, 0.35), (x + 0.06, y + 0.06, ZE), TRIM)
    col.box((X0, Y0, 0.0), (X1, Y1, ZE))
    # gable roof (ridge along X) + gable ends + fascia
    ov = 0.4
    for sy in (-1, 1):
        ye = sy * (Y1 + ov)
        C.poly_up(sh, [(X0 - ov, ye, ZE - 0.1), (X1 + ov, ye, ZE - 0.1), (X1 + ov, 0.0, ZR), (X0 - ov, 0.0, ZR)],
                  "corrugated_blue")
        C.poly_up(sh, [(X0 - ov, ye, ZE - 0.22), (X1 + ov, ye, ZE - 0.22), (X1 + ov, 0.0, ZR - 0.12), (X0 - ov, 0.0, ZR - 0.12)],
                  TRIM, up=(0, 0, -1))
        bx(sh, (X0 - ov, min(ye, ye - sy * 0.05), ZE - 0.24), (X1 + ov, max(ye, ye - sy * 0.05), ZE - 0.08), TRIM)
    for sx in (-1, 1):
        x = sx * (X1 + ov)
        for sy in (-1, 1):
            ye = sy * (Y1 + ov)
            C.poly_up(sh, [(x, ye, ZE - 0.1), (x, 0.0, ZR), (x, 0.0, ZR - 0.12), (x, ye, ZE - 0.22)], TRIM, up=(sx, 0, 0))
        C.poly_up(sh, [(sx * X1, Y0, ZE), (sx * X1, Y1, ZE), (sx * X1, 0.0, ZR - 0.12)], WALL, up=(sx, 0, 0))
    bx(sh, (X0 - ov - 0.02, -0.08, ZR - 0.06), (X1 + ov + 0.02, 0.08, ZR + 0.04), TRIM)
    col.prism([(Y0 - ov, ZE - 0.1), (Y1 + ov, ZE - 0.1), (0.0, ZR)], X1 - X0 + 2 * ov, plane="YZ", pos=(0, 0, 0))
    # front: service hatch with propped flap + counter, door, sign, life rings
    HX0, HX1 = -2.5, 0.5
    bx(sh, (HX0 - 0.1, Y1, 1.0), (HX1 + 0.1, Y1 + 0.06, 2.3), TRIM)
    C.pane(sh, "X", HX0, HX1, 1.08, 2.2, Y1 + 0.065, "glass_dark", 1)
    bx(sh, (HX0 - 0.15, Y1, 0.98), (HX1 + 0.15, Y1 + 0.4, 1.05), "wood_mid")
    sh.box((HX1 - HX0 + 0.2, 0.05, 1.1), ((HX0 + HX1) * 0.5, Y1 + 0.45, 2.55), "corrugated_blue", rot=(-62, 0, 0))
    for x in (HX0 + 0.1, HX1 - 0.1):
        sh.tube([(x, Y1 + 0.05, 2.0), (x, Y1 + 0.85, 2.72)], 0.02, "steel", segs=4, caps=False)
    bx(sh, (1.65, Y1, 0.0), (2.65, Y1 + 0.05, 2.2), TRIM)
    bx(sh, (1.73, Y1 + 0.05, 0.02), (2.57, Y1 + 0.08, 2.12), "navy")
    bx(sh, (2.42, Y1 + 0.08, 1.0), (2.48, Y1 + 0.12, 1.1), "brass")
    C.wall_lamp(sh, 2.15, Y1, 2.35, out=1, color="charcoal", w=0.3)
    yb = Y1 + ov + 0.02
    bx(sh, (-2.9, Y1 + 0.2, ZE - 0.08), (1.3, yb - 0.05, ZE + 0.62), "navy")
    C.sign(sh, "MARINA", (-0.8, yb - 0.05, ZE + 0.27), 3.6, 0.5, "neon_cyan", depth=0.06, res=TXT_RES, valign="center")
    for x in (-3.15, 3.15):
        torus(sh, (x, Y1 + 0.1, 1.55), 0.3, 0.065, axis="Y")
        bx(sh, (x - 0.03, Y1, 1.82), (x + 0.03, Y1 + 0.1, 1.9), "steel")
    # plank deck, bollards, rope coil, crates, boat fuel pump
    DY1 = Y1 + 1.2
    bx(sh, (X0 - 0.3, Y1, -0.6), (X1 + 0.3, DY1, 0.2), "wood_dark", colors={"+z": "plank_gray"})
    for k in range(1, 12):
        x = X0 - 0.3 + (X1 - X0 + 0.6) * k / 12
        sh.quad((x - 0.008, Y1 + 0.02, 0.203), (x + 0.008, Y1 + 0.02, 0.203), (x + 0.008, DY1 - 0.02, 0.203),
                (x - 0.008, DY1 - 0.02, 0.203), "wood_dark")
    col.box((X0 - 0.3, Y1, -0.6), (X1 + 0.3, DY1, 0.2))
    for x in (-2.8, 0.8):
        sh.cyl(0.13, 0.45, (x, DY1 - 0.25, 0.2), "black", segs=8, base=True, cap_color="black")
        sh.cyl(0.18, 0.06, (x, DY1 - 0.25, 0.58), "black", segs=8, base=True)
        col.box((x - 0.13, DY1 - 0.38, 0.2), (x + 0.13, DY1 - 0.12, 0.65))
    sh.cyl(0.3, 0.12, (-1.7, Y1 + 0.75, 0.2), "rope", segs=10, base=True, cap_color="rope")
    sh.cyl(0.14, 0.13, (-1.7, Y1 + 0.75, 0.2), "wood_dark", segs=8, base=True)
    F.crate(sh, col, (-3.3, Y1 + 0.2, 0.2), (-2.75, Y1 + 0.75, 0.65), "wood_mid", "wood_dark")
    PX, PY = 2.95, Y1 + 0.6
    bx(sh, (PX - 0.3, PY - 0.25, 0.2), (PX + 0.3, PY + 0.25, 0.32), "concrete_dark")
    bx(sh, (PX - 0.22, PY - 0.18, 0.32), (PX + 0.22, PY + 0.18, 1.45), "yellow", bevel=0.02)
    bx(sh, (PX - 0.24, PY - 0.2, 1.45), (PX + 0.24, PY + 0.2, 1.62), "navy")
    C.pane(sh, "X", PX - 0.15, PX + 0.15, 1.1, 1.32, PY + 0.185, "screen_blue", 1)
    C.sign(sh, "FUEL", (PX, PY + 0.2, 1.535), 0.4, 0.12, "white", depth=0.01, res=1, valign="center")
    sh.tube([(PX + 0.22, PY, 1.2), (PX + 0.45, PY + 0.1, 0.7), (PX + 0.35, PY + 0.25, 0.35), (PX + 0.24, PY + 0.19, 0.8)],
            0.022, "black", segs=4, caps=False)
    col.box((PX - 0.3, PY - 0.25, 0.2), (PX + 0.3, PY + 0.25, 1.62))
    C.cull_hidden(sh, C.ground_occ(-5, 5, -4, 5))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== lm_ferris_wheel (P3)
FW_AXLE, FW_R, FW_N = 13.0, 11.0, 12
NOTES["lm_ferris_wheel"] = (
    "Ferris wheel dia 22, axle at (0, 0, 13). Part `base` = A-frame supports, axle bearings, boarding deck (top z 0.15) "
    "and ticket booth. Part `wheel` = rims, inner neon ring, spokes with neon_pink/neon_cyan strips, hub; wheel plane "
    "XZ, axle along Y, origin at the axle: spin about its local Y. Parts gondola_01..12 = cabins, siblings of `wheel` "
    "(children of the root), origin at each hanging pivot: gondola_k pivot for wheel angle a is "
    "axle + 11 * (cos(a + (k-1)*30 deg), 0, sin(a + (k-1)*30 deg)) in asset space (k=1 at +X, counter-clockwise seen "
    "from +Y); keep their rotation at identity so they hang upright. gondola_10 (k=10, 270 deg) is at the bottom with "
    "its floor at the deck. col: base only (legs, deck, booth).")


def gondola_mesh(color):
    """One gondola cabin, origin at its pivot (the cabin hangs below, -Z)."""
    mb = K.MB()
    bx(mb, (-0.05, -0.85, -0.06), (0.05, 0.85, 0.06), "steel_dark")
    for sy in (-0.45, 0.45):
        bx(mb, (-0.035, sy - 0.035, -0.45), (0.035, sy + 0.035, 0.0), "steel_dark")
    W, D, H = 0.75, 0.62, 1.4
    zt = -0.45
    mb.loft([[(-W - 0.08, -D - 0.08, zt - 0.12), (W + 0.08, -D - 0.08, zt - 0.12), (W + 0.08, D + 0.08, zt - 0.12),
              (-W - 0.08, D + 0.08, zt - 0.12)],
             [(-0.25, -0.2, zt + 0.1), (0.25, -0.2, zt + 0.1), (0.25, 0.2, zt + 0.1), (-0.25, 0.2, zt + 0.1)]], color,
            cap_start=True, cap_end=True)
    bx(mb, (-W, -D, zt - H), (W, D, zt - H + 0.75), color, bevel=0.03)
    bx(mb, (-W - 0.02, -D - 0.02, zt - H + 0.72), (W + 0.02, D + 0.02, zt - H + 0.8), "white")
    for (x, y) in ((-W + 0.04, -D + 0.04), (W - 0.04, -D + 0.04), (W - 0.04, D - 0.04), (-W + 0.04, D - 0.04)):
        bx(mb, (x - 0.035, y - 0.035, zt - H + 0.8), (x + 0.035, y + 0.035, zt - 0.12), "white")
    for (axis, a0, a1, c, o) in (("X", -W + 0.08, W - 0.08, D - 0.04, 1), ("X", -W + 0.08, W - 0.08, -D + 0.04, -1),
                                 ("Y", -D + 0.08, D - 0.08, W - 0.04, 1), ("Y", -D + 0.08, D - 0.08, -W + 0.04, -1)):
        C.pane(mb, axis, a0, a1, zt - H + 0.8, zt - 0.14, c, "@Glass", o)
    return mb


def build_lm_ferris_wheel():
    root = K.begin_asset("lm_ferris_wheel", C.CAT, spacing=40.0)
    base, col = K.MB(), C.Col()
    AZ, R = FW_AXLE, FW_R
    # ---------------------------------------------------------------- base: A-frames, bearings, deck, booth
    for sy in (-1, 1):
        yb, yt = sy * 2.7, sy * 1.45
        for sx in (-1, 1):
            base.tube([(sx * 6.8, yb, 0.0), (0.0, yt, AZ - 0.2)], 0.32, "white", segs=6, caps=True)
            base.cyl(0.55, 0.4, (sx * 6.8, yb, 0.0), "concrete", segs=8, base=True, smooth=False)
            col_strut(col, (sx * 6.8, yb, 0.0), (0.0, yt, AZ - 0.2), 0.6)
        for z in (4.5, 8.8):
            w = 6.8 * (1.0 - z / AZ)
            y = yb + (yt - yb) * z / AZ
            base.tube([(-w, y, z), (w, y, z)], 0.16, "white", segs=6, caps=False)
            base.tube([(-w, y, z), (w * 0.55, y, z + 3.6 if z < 8 else z + 2.6)], 0.09, "white", segs=4, caps=False)
        bx(base, (-0.55, yt - 0.35, AZ - 0.7), (0.55, yt + 0.35, AZ + 0.6), "steel_dark")
    base.cyl(0.32, 3.6, (0, 0, AZ), "steel", axis="Y", segs=10)
    for sx in (-1, 1):
        base.tube([(sx * 6.8, -2.7, 0.3), (sx * 6.8, 2.7, 0.3)], 0.14, "white", segs=4, caps=False)
    bx(base, (-3.6, -3.2, 0.0), (3.6, 3.2, 0.15), "plank_gray", colors={"-x": "white", "+x": "white", "-y": "white",
                                                                        "+y": "white"})
    col.box((-3.6, -3.2, 0.0), (3.6, 3.2, 0.15))
    for (xa, xb, ya, yb) in ((-3.55, -1.2, 3.12, 3.18), (1.2, 3.55, 3.12, 3.18), (-3.55, 3.55, -3.18, -3.12),
                             (-3.6, -3.54, -3.18, -1.0), (-3.6, -3.54, 1.0, 3.18), (3.54, 3.6, -3.18, -1.0),
                             (3.54, 3.6, 1.0, 3.18)):
        bx(base, (xa, ya, 1.0), (xb, yb, 1.06), "neon_pink")
        bx(base, (xa, ya, 0.15), (xb, yb, 0.2), "white")
        n = max(1, int(max(xb - xa, yb - ya) / 1.2))
        for k in range(n + 1):
            x = xa + (xb - xa) * k / n
            y = ya + (yb - ya) * k / n
            bx(base, (x - 0.03, y - 0.03, 0.15), (x + 0.03, y + 0.03, 1.0), "white")
        col.box((xa, ya, 0.15), (xb, yb, 1.06))
    # ticket booth
    KX, KY = 5.2, 4.6
    bx(base, (KX - 0.8, KY - 0.7, 0.0), (KX + 0.8, KY + 0.7, 1.1), "white")
    bx(base, (KX - 0.8, KY - 0.7, 1.1), (KX + 0.8, KY + 0.7, 2.2), "turquoise")
    C.pane(base, "X", KX - 0.6, KX + 0.6, 1.2, 2.0, KY + 0.706, "@Glass", 1)
    bx(base, (KX - 0.95, KY - 0.85, 2.2), (KX + 0.95, KY + 0.85, 2.35), "coral_pink")
    base.loft([[(KX - 0.95, KY - 0.85, 2.35), (KX + 0.95, KY - 0.85, 2.35), (KX + 0.95, KY + 0.85, 2.35),
                (KX - 0.95, KY + 0.85, 2.35)], [(KX - 0.1, KY - 0.1, 3.0), (KX + 0.1, KY - 0.1, 3.0),
                                                 (KX + 0.1, KY + 0.1, 3.0), (KX - 0.1, KY + 0.1, 3.0)]], "white")
    bx(base, (KX - 0.85, KY + 0.7, 2.45), (KX + 0.85, KY + 0.78, 2.8), "navy")
    C.sign(base, "RIDE", (KX, KY + 0.78, 2.625), 1.2, 0.22, "neon_pink", depth=0.03, res=1, valign="center")
    col.box((KX - 0.8, KY - 0.7, 0.0), (KX + 0.8, KY + 0.7, 2.35))
    base.to_object(root, "base", sharp_angle=40)

    # ---------------------------------------------------------------- wheel (origin on the axle)
    wh = K.MB()
    n = 24
    for y in (-0.9, 0.9):
        pts = [(math.cos(2 * math.pi * k / n) * R, y, AZ + math.sin(2 * math.pi * k / n) * R) for k in range(n)]
        wh.tube(pts + [pts[0]], 0.13, "white", segs=4, caps=False)
        pin = [(math.cos(2 * math.pi * k / n) * 7.4, y, AZ + math.sin(2 * math.pi * k / n) * 7.4) for k in range(n)]
        wh.tube(pin + [pin[0]], 0.08, "neon_cyan", segs=4, caps=False)
    for k in range(FW_N):
        a = 2 * math.pi * k / FW_N
        ca, sa = math.cos(a), math.sin(a)
        for y in (-0.9, 0.9):
            wh.tube([(ca * 0.8, y * 0.7, AZ + sa * 0.8), (ca * R, y, AZ + sa * R)], 0.07, "white", segs=4, caps=False)
            ys = y + (0.11 if y > 0 else -0.11)
            wh.box((R - 1.4, 0.03, 0.09), (ca * (R + 0.4) * 0.5, ys, AZ + sa * (R + 0.4) * 0.5),
                   "neon_pink" if k % 2 == 0 else "neon_cyan", rot=(0, -math.degrees(a), 0))
        wh.tube([(ca * R, -0.95, AZ + sa * R), (ca * R, 0.95, AZ + sa * R)], 0.07, "steel_dark", segs=4, caps=False)
        a2 = a + math.pi / FW_N
        for y in (-0.9, 0.9):
            wh.tube([(ca * 7.4, y, AZ + sa * 7.4), (math.cos(a2) * R, y, AZ + math.sin(a2) * R)], 0.05, "white", segs=4,
                    caps=False)
    wh.cyl(0.95, 2.2, (0, 0, AZ), "white", axis="Y", segs=12, cap_color="neon_pink")
    wh.cyl(0.5, 2.5, (0, 0, AZ), "steel_dark", axis="Y", segs=8)
    wh.to_object(root, "wheel", origin=(0, 0, AZ), sharp_angle=50)
    # ---------------------------------------------------------------- gondolas (3 colour variants, linked copies)
    meshes = {}
    for k in range(FW_N):
        a = 2 * math.pi * k / FW_N
        piv = (math.cos(a) * R, 0.0, AZ + math.sin(a) * R)
        variant = k % 3
        name = "gondola_%02d" % (k + 1)
        if variant not in meshes:
            mb = gondola_mesh(("coral_pink", "turquoise", "yellow")[variant])
            obj = mb.to_object(root, name, origin=(0, 0, 0))
            obj.location = piv
            meshes[variant] = obj
        else:
            K.link_copy(meshes[variant], root, name, piv)
    col.to_object(root)
    return root


# =========================================================================== lm_basketball (P3)
NOTES["lm_basketball"] = (
    "Half-court basketball 15 x 14 (x -7.5..7.5, y -7..7), slab top z 0.08, court lines (line_white) incl. key, "
    "free-throw circle, three-point arc and half-court circle; hoop on a post behind the -Y baseline (rim centre "
    "(0, -5.4, 3.05), backboard y -6.0), facing +Y. Marker `hoop` at the rim centre, `shoot` at the free-throw spot "
    "(ground, looking at the hoop). col: slab, post, arm + backboard.")


def build_lm_basketball():
    root = K.begin_asset("lm_basketball", C.CAT, spacing=25.0)
    sh, col = K.MB(), C.Col()
    X0, X1, Y0, Y1, ZS = -7.5, 7.5, -7.0, 7.0, 0.08
    bx(sh, (X0, Y0, 0.0), (X1, Y1, ZS), "concrete", colors={"+z": "blue_dark"})
    col.box((X0, Y0, 0.0), (X1, Y1, ZS))
    z = ZS + 0.004
    BL, HY = -6.6, -5.4
    sh.quad((-2.45, BL, z), (2.45, BL, z), (2.45, -0.8, z), (-2.45, -0.8, z), "teal")
    z2 = z + 0.003
    lw = 0.06

    def line(a, b):
        (xa, ya), (xb, yb) = a, b
        dx, dy = xb - xa, yb - ya
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln * lw * 0.5, dx / ln * lw * 0.5
        C.poly_up(sh, [(xa - nx, ya - ny, z2), (xb - nx, yb - ny, z2), (xb + nx, yb + ny, z2), (xa + nx, ya + ny, z2)],
                  "line_white")

    def arc(cx, cy, r, a0, a1, n):
        pts = [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, cy + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r)
               for i in range(n + 1)]
        for p, q in zip(pts, pts[1:]):
            line(p, q)

    for a, b in (((-7.2, BL), (7.2, BL)), ((-7.2, BL), (-7.2, 6.8)), ((7.2, BL), (7.2, 6.8)), ((-7.2, 6.8), (7.2, 6.8)),
                 ((-2.45, BL), (-2.45, -0.8)), ((2.45, BL), (2.45, -0.8)), ((-2.45, -0.8), (2.45, -0.8))):
        line(a, b)
    arc(0.0, -0.8, 1.8, 0, 180, 10)
    ang = math.degrees(math.asin(6.6 / 6.75))
    yk = HY + math.cos(math.radians(ang)) * 6.75
    line((-6.6, BL), (-6.6, yk))
    line((6.6, BL), (6.6, yk))
    arc(0.0, HY, 6.75, 90 - ang, 90 + ang, 18)
    arc(0.0, 6.8, 1.8, 180, 360, 10)
    # hoop: post, arm, backboard, rim, net
    sh.cyl(0.11, 3.25, (0, -6.95, ZS), "steel_dark", segs=8, base=True)
    sh.cyl(0.3, 0.06, (0, -6.95, ZS), "steel_dark", segs=8, base=True, smooth=False)
    bx(sh, (-0.08, -6.95, 3.05), (0.08, -6.05, 3.2), "steel_dark")
    bx(sh, (-0.9, -6.08, 2.9), (0.9, -6.02, 3.95), "white", bevel=0.01)
    for (a0, a1, b0, b1, c) in ((-0.88, 0.88, 2.92, 2.97, "red"), (-0.88, 0.88, 3.88, 3.93, "red"),
                                (-0.88, -0.83, 2.92, 3.93, "red"), (0.83, 0.88, 2.92, 3.93, "red"),
                                (-0.3, 0.3, 3.08, 3.13, "red"), (-0.3, 0.3, 3.45, 3.5, "red"), (-0.3, -0.25, 3.08, 3.5, "red"),
                                (0.25, 0.3, 3.08, 3.5, "red")):
        C.pane(sh, "X", a0, a1, b0, b1, -6.015, c, 1)
    rp = [(math.cos(2 * math.pi * k / 12) * 0.23, HY + math.sin(2 * math.pi * k / 12) * 0.23, 3.05) for k in range(12)]
    sh.tube(rp + [rp[0]], 0.012, "orange", segs=4, caps=False)
    bx(sh, (-0.05, -6.02, 3.03), (0.05, HY - 0.2, 3.07), "orange")
    sh.cyl(0.15, 0.42, (0, HY, 2.63), "white", segs=10, r2=0.23, base=True, caps=False, smooth=False)
    col.box((-0.15, -7.05, ZS), (0.15, -6.85, 3.25))
    col.box((-0.9, -6.1, 2.9), (0.9, -6.0, 3.95))
    C.cull_hidden(sh, C.ground_occ(-8, 8, -8, 8))
    sh.to_object(root, "shell")
    col.to_object(root)
    K.marker(root, "hoop", (0.0, HY, 3.05), (0, 0, 0))
    K.marker(root, "shoot", (0.0, -0.8, ZS), (0, 0, 180))
    return root


# =========================================================================== build all
BUILDERS = [("lm_fountain", build_lm_fountain), ("lm_statue", build_lm_statue), ("lm_viewpoint", build_lm_viewpoint),
            ("lm_gazebo", build_lm_gazebo), ("lm_boathouse", build_lm_boathouse),
            ("lm_ferris_wheel", build_lm_ferris_wheel), ("lm_basketball", build_lm_basketball)]


def build_all(only=None):
    out = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
        out.append(export(name))
    return "\n".join(out)
