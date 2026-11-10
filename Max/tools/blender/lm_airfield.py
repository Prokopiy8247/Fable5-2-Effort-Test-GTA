"""lm_airfield - fuel station + airfield landmarks for NEON TIDE (SPEC_LANDMARKS.md, "P1 - Fuel, airfield").

Run inside Blender (Blender MCP):

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C, lm_fix as F, lm_airfield as A
    for m in (K, C, F, A): importlib.reload(m)
    print(A.build_all())            # build + export + manifest for every asset of this module
    # or: A.build_lm_hangar(); print(A.export("lm_hangar"))
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


GULL = [(-0.5, 0.06), (-0.3, 0.2), (-0.12, 0.14), (0.0, 0.0), (0.12, 0.14), (0.3, 0.2), (0.5, 0.06), (0.3, 0.12),
        (0.13, 0.06), (0.0, -0.1), (-0.13, 0.06), (-0.3, 0.12)]


def gull_logo(mb, pos, s=1.0, color="navy", depth=0.04, out=1):
    """Stylised gull (wing 'M') logo on a plane facing out*Y."""
    pts = [(x * s, z * s) for x, z in GULL]
    with mb.at(pos, rot=(0, 0, 0 if out > 0 else 180)):
        mb.prism(pts, depth, color, plane="XZ", pos=(0, depth * 0.5, 0), caps=(False, True))


# =========================================================================== lm_gas_station  "GULL GAS"
NOTES["lm_gas_station"] = (
    "GULL GAS fuel station. Canopy 14x9 (x -7..7, y -4.5..4.5), underside 4.6, top 5.5, on 4 columns at "
    "(+-3.5, +-2.6) standing on the two pump islands (islands along Y at x +-3.5, 1.3 wide, y -3.5..3.5, top 0.15). "
    "Lanes: central lane x -2.85..2.85 (one car beside each island), outer lanes x +-(4.15..7). Pumps at "
    "(+-3.5, +-1.25). Markers pump_1..4 sit at each pump's foot ON THE GROUND (z 0, under the island top) and their +Y "
    "points to the central lane: a car refuels with its side ~1.5 m from the marker. pump_1 (-3.5, 1.25), pump_2 "
    "(-3.5, -1.25), pump_3 (3.5, 1.25), pump_4 (3.5, -1.25). light_1..4 under the canopy lamps (z 4.35). Price "
    "pylon 7 m at the +X/+Y corner (x 8.6, y 5.2). col: columns, islands, pumps, bollards, bins, pylon + canopy slab.")


def fuel_pump(mb, col, x, y, body="white", accent="green", rng=None):
    """Double-sided fuel dispenser standing on an island top (z 0.15); displays + nozzles on both +-X faces."""
    z0 = 0.15
    bx(mb, (x - 0.32, y - 0.5, z0), (x + 0.32, y + 0.5, z0 + 0.12), "concrete_dark")
    bx(mb, (x - 0.26, y - 0.42, z0 + 0.12), (x + 0.26, y + 0.42, z0 + 1.45), body, bevel=0.02)
    bx(mb, (x - 0.28, y - 0.45, z0 + 1.45), (x + 0.28, y + 0.45, z0 + 1.78), accent, bevel=0.02)
    for o in (-1, 1):
        xf = x + o * 0.265
        C.pane(mb, "Y", y - 0.3, y + 0.3, z0 + 1.53, z0 + 1.7, xf + o * 0.02, "white", o)
        C.pane(mb, "Y", y - 0.28, y + 0.05, z0 + 1.05, z0 + 1.32, xf + o * 0.004, "black", o)
        C.pane(mb, "Y", y - 0.25, y + 0.02, z0 + 1.08, z0 + 1.29, xf + o * 0.008, "screen_blue", o)
        C.pane(mb, "Y", y + 0.1, y + 0.3, z0 + 1.05, z0 + 1.25, xf + o * 0.004, "gray_dark", o)
        for k, c in enumerate(("green", "yellow", "red")):
            C.pane(mb, "Y", y - 0.3 + k * 0.2, y - 0.14 + k * 0.2, z0 + 0.75, z0 + 0.9, xf + o * 0.004, c, o)
        # holster + nozzle + hose loop
        hx = xf + o * 0.06
        bx(mb, (min(xf, hx), y + 0.22, z0 + 0.5), (max(xf, hx), y + 0.36, z0 + 0.7), "black")
        mb.box((0.05, 0.16, 0.05), (hx + o * 0.02, y + 0.29, z0 + 0.66), "gray_dark", rot=(0, o * -30, 0))
        mb.tube([(xf + o * 0.02, y + 0.35, z0 + 1.0), (xf + o * 0.25, y + 0.42, z0 + 0.55),
                 (xf + o * 0.22, y + 0.4, z0 + 0.2), (hx + o * 0.04, y + 0.31, z0 + 0.52)], 0.022, "black", segs=4,
                caps=False)
    if col is not None:
        col.box((x - 0.32, y - 0.5, 0.0), (x + 0.32, y + 0.5, z0 + 1.78))


def bollard(mb, col, x, y, h=1.0, r=0.1, color="hazard_yellow", band="black"):
    mb.cyl(r, h, (x, y, 0.0), color, segs=8, base=True, cap_color=color)
    for z in (h * 0.55, h * 0.8):
        mb.cyl(r + 0.006, 0.08, (x, y, z), band, segs=8, caps=False)
    if col is not None:
        col.box((x - r, y - r, 0.0), (x + r, y + r, h))


def build_lm_gas_station():
    root = K.begin_asset("lm_gas_station", C.CAT)
    sh, col = K.MB(), C.Col()
    rng = random.Random(61)
    CX, CY = 7.0, 4.5                  # canopy half extents
    ZU, ZT = 4.45, 5.5                 # canopy underside / top
    IX, IW, IY = 3.5, 0.65, 3.5        # island centre x, half width, half length
    COLS = [(-IX, -2.6), (-IX, 2.6), (IX, -2.6), (IX, 2.6)]
    PUMPS = [(-IX, 1.25), (-IX, -1.25), (IX, 1.25), (IX, -1.25)]

    # ---------------------------------------------------------------- canopy
    bx(sh, (-CX, -CY, ZU), (CX, CY, ZT - 0.05), "white", colors={"-z": "gray_light"})
    bx(sh, (-CX - 0.05, -CY - 0.05, ZT - 0.05), (CX + 0.05, CY + 0.05, ZT), "gray_mid")
    C.band(sh, -CX, CX, -CY, CY, ZU + 0.04, ZU + 0.22, 0.03, "neon_green")
    C.band(sh, -CX, CX, -CY, CY, ZU + 0.26, ZU + 0.3, 0.02, "green")
    for out in (1, -1):
        yp = out * (CY + 0.035)
        bx(sh, (-3.25, min(out * CY, yp), ZU + 0.34), (3.15, max(out * CY, yp), ZT - 0.1), "green_dark")
        C.sign(sh, "GULL GAS", (-0.75 * out, yp, ZU + 0.7), 5.2, 0.5, "neon_green", depth=0.06, res=TXT_RES,
               valign="center", rot=None if out > 0 else (0, 0, 180))
        gull_logo(sh, (2.15 * out, yp, ZU + 0.64), 1.15, "white", 0.04, out)
    col.box((-CX, -CY, ZU), (CX, CY, ZT))
    # underside lamps (emis_lamp panels) + light markers, perimeter LED strip
    for i, (x, y) in enumerate(((-IX, 1.25), (IX, 1.25), (-IX, -1.25), (IX, -1.25))):
        bx(sh, (x - 0.45, y - 0.8, ZU - 0.04), (x + 0.45, y + 0.8, ZU), "gray_mid", colors={"-z": "emis_lamp"})
        K.marker(root, "light_%d" % (i + 1), (x, y, ZU - 0.25))
    for x in (-5.6, 0.0, 5.6):
        for y in (-2.6, 2.6):
            bx(sh, (x - 0.45, y - 0.8, ZU - 0.04), (x + 0.45, y + 0.8, ZU), "gray_mid", colors={"-z": "emis_lamp"})
    # columns
    for (x, y) in COLS:
        bx(sh, (x - 0.25, y - 0.25, 0.15), (x + 0.25, y + 0.25, ZU), "white")
        bx(sh, (x - 0.28, y - 0.28, 0.15), (x + 0.28, y + 0.28, 1.2), "green")
        bx(sh, (x - 0.3, y - 0.3, 1.2), (x + 0.3, y + 0.3, 1.28), "neon_green")
        col.box((x - 0.28, y - 0.28, 0.15), (x + 0.28, y + 0.28, ZU))
    # islands: curb, yellow noses, pumps, bollards, bin
    for sx in (-1, 1):
        x = sx * IX
        bx(sh, (x - IW, -IY, 0.0), (x + IW, IY, 0.15), "concrete", colors={"+z": "concrete_light"})
        for sy in (-1, 1):
            sh.prism([(x - IW, sy * IY), (x + IW, sy * IY), (x, sy * (IY + 0.6))], 0.15, "hazard_yellow", plane="XY",
                     center=False)
        col.box((x - IW, -IY - 0.3, 0.0), (x + IW, IY + 0.3, 0.15))
        for sy in (-1, 1):
            bollard(sh, col, x, sy * (IY + 0.95), 1.0)
        sh.cyl(0.24, 0.85, (x, 0.0, 0.15), "green", segs=8, base=True, cap_color="black")
        sh.cyl(0.26, 0.08, (x, 0.0, 1.0), "gray_dark", segs=8, base=True)
        col.box((x - 0.24, -0.24, 0.15), (x + 0.24, 0.24, 1.08))
    for (x, y) in PUMPS:
        fuel_pump(sh, col, x, y, rng=rng)
    # ---------------------------------------------------------------- price pylon (+X/+Y corner)
    PXc, PYc = 8.6, 5.2
    bx(sh, (PXc - 1.0, PYc - 0.4, 0.0), (PXc + 1.0, PYc + 0.4, 0.6), "concrete", bevel=0.03)
    for sx in (-1, 1):
        bx(sh, (PXc + sx * 0.6 - 0.14, PYc - 0.14, 0.6), (PXc + sx * 0.6 + 0.14, PYc + 0.14, 4.0), "gray_dark")
    bx(sh, (PXc - 0.95, PYc - 0.25, 4.0), (PXc + 0.95, PYc + 0.25, 5.55), "black")
    bx(sh, (PXc - 0.95, PYc - 0.25, 5.55), (PXc + 0.95, PYc + 0.25, 7.0), "green")
    bx(sh, (PXc - 1.0, PYc - 0.28, 5.5), (PXc + 1.0, PYc + 0.28, 5.6), "neon_green")
    bx(sh, (PXc - 1.0, PYc - 0.28, 6.95), (PXc + 1.0, PYc + 0.28, 7.05), "white")
    for out in (1, -1):
        yf = PYc + out * 0.25
        rot = None if out > 0 else (0, 0, 180)
        C.pane(sh, "X", PXc - 0.82, PXc + 0.82, 6.3, 6.88, yf + out * 0.004, "white", out)
        gull_logo(sh, (PXc, yf + out * 0.004, 6.6), 1.1, "navy", 0.03, out)
        C.sign(sh, "GULL GAS", (PXc, yf, 5.92), 1.6, 0.3, "white", depth=0.03, res=1, valign="center", rot=rot)
        if out > 0:
            for k, (txt, tab) in enumerate((("2.89", "green"), ("3.19", "yellow"), ("3.49", "red"))):
                z = 5.2 - k * 0.45
                C.pane(sh, "X", PXc - 0.8, PXc - 0.55, z - 0.15, z + 0.15, yf + 0.004, tab, 1)
                C.sign(sh, txt, (PXc + 0.18, yf, z), 1.0, 0.3, "led_red", depth=0.02, res=1, valign="center")
    col.box((PXc - 1.0, PYc - 0.4, 0.0), (PXc + 1.0, PYc + 0.4, 7.05))

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(-12, 12, -8, 8))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    for i, (x, y) in enumerate(PUMPS):
        K.marker(root, "pump_%d" % (i + 1), (x, y, 0.0), (0, 0, -90 if x < 0 else 90))
    return root


# =========================================================================== lm_hangar
NOTES["lm_hangar"] = (
    "Arched hangar 26 x 32 (x -13..13, y -16..16), vault = circular arc r 13.45 (centre z -3.45), apex 10.0, "
    "corrugated cladding tint_a_metal (recolour with tint_a), +Y end open. Front door portal: top track beam at "
    "z 7.45..7.85 between two posts at x +-13.15; two door leaves parked at the sides (x +-7.4..+-12.95, static, in "
    "the shell). Clear opening between the parked leaves: x -7.4..7.4, height 7.45 (planes up to ~14 m span). "
    "Back wall with a row of windows and a closed personnel door. Floor top z 0.02 with a yellow guide line on x = 0. "
    "Marker `spot` = aircraft parking point at the centre (0, 0, 0.02), +Y (out of the door). light_1..4 under the "
    "high-bay lamps (z 7.55). col: vault as 8 flat segments per side, back wall, floor slab, portal posts, parked "
    "leaves, fixtures along the walls.")

R_OUT, ZC_ARCH = 13.45, -3.45


def arch_pts(R, n, zc=ZC_ARCH, z0=0.0):
    """n+1 points (x, z) of the arc of radius R (centre (0, zc)) between its two intersections with z = z0."""
    pm = math.acos((z0 - zc) / R)
    return [(R * math.sin(-pm + 2 * pm * k / n), zc + R * math.cos(-pm + 2 * pm * k / n)) for k in range(n + 1)]


def arch_band(mb, R0, R1, y0, y1, color, n=20, faces=("out", "in", "front", "back"), cols=None):
    """Curved band between radii R0 < R1 spanning y0..y1 (vault skin, ribs, frames)."""
    cols = cols or {}
    po, pi = arch_pts(R1, n), arch_pts(R0, n)
    for k in range(n):
        (xa, za), (xb, zb) = po[k], po[k + 1]
        (xc, zc), (xd, zd) = pi[k], pi[k + 1]
        mx, mz = (xa + xb) * 0.5, (za + zb) * 0.5 - ZC_ARCH
        ln = math.hypot(mx, mz)
        nx, nz = mx / ln, mz / ln
        if "out" in faces:
            C.poly_up(mb, [(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], cols.get("out", color), up=(nx, 0, nz))
        if "in" in faces:
            C.poly_up(mb, [(xc, y0, zc), (xd, y0, zd), (xd, y1, zd), (xc, y1, zc)], cols.get("in", color), up=(-nx, 0, -nz))
        if "front" in faces:
            C.poly_up(mb, [(xa, y1, za), (xb, y1, zb), (xd, y1, zd), (xc, y1, zc)], cols.get("front", color), up=(0, 1, 0))
        if "back" in faces:
            C.poly_up(mb, [(xa, y0, za), (xb, y0, zb), (xd, y0, zd), (xc, y0, zc)], cols.get("back", color), up=(0, -1, 0))


def high_bay(root, mb, pts, z_top, drop=1.6, first=1, shade="steel_dark"):
    """Hanging high-bay lamps (rod + cone + emissive lens) + light markers 0.25 below the lens."""
    for i, (x, y) in enumerate(pts):
        zl = z_top - drop
        mb.cyl(0.02, drop, (x, y, zl), "black", segs=4, base=True, caps=False)
        mb.cyl(0.42, 0.35, (x, y, zl - 0.3), shade, segs=10, r2=0.12, base=True, caps=False, smooth=False)
        C.disc(mb, (x, y, zl - 0.29), 0.38, "emis_lamp", axis="Z", segs=10, out=-1)
        K.marker(root, "light_%d" % (first + i), (x, y, zl - 0.55))


def tool_cart(mb, col, pos, rz=0.0, color="red"):
    with mb.at(pos, rot=(0, 0, rz)):
        for (x, y) in ((-0.32, -0.2), (0.32, -0.2), (-0.32, 0.2), (0.32, 0.2)):
            mb.cyl(0.06, 0.04, (x, y, 0.06), "black", axis="Y", segs=6, smooth=False)
        bx(mb, (-0.4, -0.25, 0.12), (0.4, 0.25, 0.85), color, bevel=0.015)
        for k in range(3):
            bx(mb, (-0.32, 0.25, 0.25 + k * 0.2), (0.32, 0.265, 0.27 + k * 0.2), "aluminum")
        bx(mb, (-0.42, -0.27, 0.85), (0.42, 0.27, 0.88), "rubber")
        bx(mb, (0.42, -0.2, 0.7), (0.5, 0.2, 0.74), "chrome")
    if col is not None:
        x, y, z = pos
        col.box((x - 0.45, y - 0.45, z), (x + 0.45, y + 0.45, z + 0.88))


def maint_stairs(mb, col, pos, rz=0.0, color="hazard_yellow"):
    """Rolling maintenance stairs (platform at 2.0 m), climbs toward local +Y."""
    with mb.at(pos, rot=(0, 0, rz)):
        for sx in (-0.45, 0.45):
            mb.box((0.05, 2.9, 0.08), (sx, -0.3, 1.0), color, rot=(-38, 0, 0))
            bx(mb, (sx - 0.03, 0.75, 0.0), (sx + 0.03, 0.81, 3.0), color)
            bx(mb, (sx - 0.03, 1.4, 0.0), (sx + 0.03, 1.46, 3.0), color)
            mb.tube([(sx, -1.5, 1.0), (sx, 0.7, 3.0), (sx, 1.43, 3.0)], 0.025, color, segs=4, caps=False)
        for k in range(8):
            y = -1.35 + k * 0.27
            z = 0.25 * (k + 1)
            bx(mb, (-0.45, y - 0.12, z - 0.03), (0.45, y + 0.12, z), "steel")
        bx(mb, (-0.5, 0.75, 1.97), (0.5, 1.46, 2.03), "steel")
        for (x, y) in ((-0.45, -1.6), (0.45, -1.6), (-0.45, 1.43), (0.45, 1.43)):
            mb.cyl(0.07, 0.05, (x, y, 0.07), "black", axis="X", segs=6, smooth=False)
    if col is not None:
        x, y, z = pos
        c, s = abs(math.cos(math.radians(rz))), abs(math.sin(math.radians(rz)))
        ex, ey = c * 0.5 + s * 1.55, s * 0.5 + c * 1.55
        col.box((x - ex, y - ey, z), (x + ex, y + ey, z + 2.03))


def build_lm_hangar():
    root = K.begin_asset("lm_hangar", C.CAT)
    sh, col = K.MB(), C.Col()
    rng = random.Random(71)
    Y0, Y1 = -16.0, 16.0
    RO, RI = R_OUT, R_OUT - 0.16
    MET, INNER = "tint_a_metal", "gray_light"
    N = 20

    # ---------------------------------------------------------------- vault, seams, ribs, frames
    arch_band(sh, RI, RO, Y0, Y1, MET, N, faces=("out", "in", "front", "back"),
              cols={"in": INNER, "front": "steel_dark", "back": "steel_dark"})
    po = arch_pts(RO, N)
    for k in range(1, N):
        x, z = po[k]
        ln = math.hypot(x, z - ZC_ARCH)
        nx, nz = x / ln, (z - ZC_ARCH) / ln
        tx, tz = -nz, nx
        w = 0.05
        p = [(x - tx * w + nx * 0.012, z - tz * w + nz * 0.012), (x + tx * w + nx * 0.012, z + tz * w + nz * 0.012)]
        C.poly_up(sh, [(p[0][0], Y0, p[0][1]), (p[1][0], Y0, p[1][1]), (p[1][0], Y1, p[1][1]), (p[0][0], Y1, p[0][1])],
                  "steel", up=(nx, 0, nz))
    for y in (-8.0, 0.0, 8.0):
        arch_band(sh, RO - 0.02, RO + 0.09, y - 0.14, y + 0.14, "steel_dark", N, faces=("out", "front", "back"))
    arch_band(sh, RO - 0.02, RO + 0.28, Y1 - 0.45, Y1 + 0.02, "steel_dark", N, faces=("out", "front", "back"))
    arch_band(sh, RI - 0.3, RI + 0.02, Y1 - 0.45, Y1 + 0.02, "steel_dark", N, faces=("in", "front", "back"))
    arch_band(sh, RO - 0.02, RO + 0.12, Y0 - 0.02, Y0 + 0.3, "steel_dark", N, faces=("out", "back"))
    for y in (-12.0, -4.0, 4.0, 12.0):
        arch_band(sh, RI - 0.22, RI + 0.02, y - 0.1, y + 0.1, "steel_dark", N, faces=("in", "front", "back"))
    for sx in (-1, 1):
        bx(sh, (sx * 13.0 - 0.25, Y0, 0.0), (sx * 13.0 + 0.25, Y1, 0.35), "concrete_dark")
    pc = arch_pts(RO, 16)                                # col: 8 flat segments per side
    pci = arch_pts(RI - 0.15, 16)
    for k in range(16):
        prof = [pc[k], pc[k + 1], pci[k + 1], pci[k]]
        col.prism(prof, Y1 - Y0, plane="XZ", pos=(0, (Y0 + Y1) * 0.5, 0))

    # ---------------------------------------------------------------- back wall: windows, door
    pw = arch_pts(RI - 0.02, N)
    sh.prism(pw, 0.3, MET, plane="XZ", pos=(0, Y0 + 0.15, 0), cap_colors=(MET, INNER))
    col.prism(pw, 0.3, plane="XZ", pos=(0, Y0 + 0.15, 0))
    for i in range(6):
        a = -8.0 + i * 2.75
        b = a + 2.0
        for yy, o in ((Y0, -1), (Y0 + 0.3, 1)):
            bx(sh, (a - 0.08, min(yy, yy + o * 0.06), 4.52), (b + 0.08, max(yy, yy + o * 0.06), 5.68), "steel_dark")
            C.pane(sh, "X", a, b, 4.6, 5.6, yy + o * 0.065, "@Window", o)
            bx(sh, ((a + b) * 0.5 - 0.03, min(yy, yy + o * 0.08), 4.6), ((a + b) * 0.5 + 0.03, max(yy, yy + o * 0.08), 5.6),
               "steel_dark")
    for yy, o in ((Y0, -1), (Y0 + 0.3, 1)):
        C.door_surround(sh, 8.5, 9.5, 2.2, yy, w=0.08, proud=0.04, color="steel_dark", out=o)
        bx(sh, (8.5, min(yy, yy + o * 0.025), 0.02), (9.5, max(yy, yy + o * 0.025), 2.2), "gray_mid")
        bx(sh, (8.6, min(yy, yy + o * 0.06), 1.0), (8.9, max(yy, yy + o * 0.06), 1.05), "chrome")
    C.wall_lamp(sh, 9.0, Y0, 2.55, out=-1, color="steel_dark")

    # ---------------------------------------------------------------- front portal: track beam, posts, parked leaves
    bx(sh, (-13.35, Y1 + 0.2, 7.45), (13.35, Y1 + 0.6, 7.85), "steel_dark")
    for sx in (-1, 1):
        bx(sh, (sx * 13.15 - 0.18, Y1 + 0.2, 0.0), (sx * 13.15 + 0.18, Y1 + 0.6, 7.85), "steel_dark")
        col.box((sx * 13.15 - 0.18, Y1 + 0.2, 0.0), (sx * 13.15 + 0.18, Y1 + 0.6, 7.85))
        xa, xb = (7.4, 12.95) if sx > 0 else (-12.95, -7.4)
        bx(sh, (xa, Y1 + 0.28, 0.12), (xb, Y1 + 0.52, 7.4), MET)
        bx(sh, (xa, Y1 + 0.26, 0.05), (xb, Y1 + 0.54, 0.4), "steel_dark")
        bx(sh, (xa, Y1 + 0.26, 7.1), (xb, Y1 + 0.54, 7.4), "steel_dark")
        for k in range(1, 7):
            x = xa + (xb - xa) * k / 7
            for yy, o in ((Y1 + 0.52, 1), (Y1 + 0.28, -1)):
                C.pane(sh, "X", x - 0.04, x + 0.04, 0.4, 7.1, yy + o * 0.006, "steel", o)
        xe = xa if sx > 0 else xb - 0.18
        bx(sh, (xe, Y1 + 0.25, 0.4), (xe + 0.18, Y1 + 0.55, 7.1), "hazard_yellow")
        col.box((xa, Y1 + 0.28, 0.0), (xb, Y1 + 0.52, 7.4))
    for y in (Y1 + 0.32, Y1 + 0.48):
        bx(sh, (-13.3, y - 0.04, 0.0), (13.3, y + 0.04, 0.035), "steel")
    for sx in (-1, 1):
        C.wall_lamp(sh, sx * 4.5, Y1 + 0.6, 7.3, out=1, color="steel_dark", w=0.5)

    # ---------------------------------------------------------------- floor + markings
    FX = 12.78
    sh.quad((-FX, Y0 + 0.3, 0.02), (FX, Y0 + 0.3, 0.02), (FX, Y1, 0.02), (-FX, Y1, 0.02), "concrete")
    col.box((-13.0, Y0, 0.0), (13.0, Y1, 0.02))
    F.floor_quad(sh, -0.1, 0.1, -6.0, Y1, 0.024, "line_yellow")
    F.floor_quad(sh, -1.5, 1.5, 4.9, 5.1, 0.024, "line_yellow")
    for sx in (-1, 1):
        F.floor_quad(sh, sx * 10.2 - 0.06, sx * 10.2 + 0.06, Y0 + 1.0, Y1 - 0.6, 0.024, "line_yellow")
    F.hazard_outline(sh, -2.5, 2.5, -14.4, -12.4, 0.025, w=0.12, seg=0.5)

    # ---------------------------------------------------------------- fixtures along the walls
    for y in (-11.5, -8.6, -5.7):
        with C.at((-11.85, y, 0.02), -90, sh, col):
            F.steel_shelf(sh, col, 2.6, 0.6, 2.2, 4, stock=["cardboard", "cardboard", "tan", "red", "blue_dark", "gray_mid",
                                                         "olive"], rng=rng, wmin=0.35, wmax=0.7, fill=0.8)
    for (x, y, n) in ((-11.0, -1.0, 2), (-11.0, 0.4, 1), (-9.7, -0.4, 1)):
        for k in range(n):
            F.crate(sh, col, (x - 0.6, y - 0.5, 0.02 + k * 0.92), (x + 0.6, y + 0.5, 0.94 + k * 0.92),
                    color="wood_mid" if k % 2 == 0 else "cardboard", tape="wood_dark")
    with C.at((-11.85, 5.5, 0.02), -90, sh, col):
        F.workbench(sh, col, w=2.6, d=0.75, top="wood_mid", frame="steel_dark", board="gray_dark", board_h=0.9)
    F.drum(sh, col, (-11.3, 9.4, 0.02), "blue")
    F.drum(sh, col, (-11.3, 10.1, 0.02), "red")
    tool_cart(sh, col, (11.0, 8.5, 0.02), 90, "red")
    tool_cart(sh, col, (11.0, 7.0, 0.02), 90, "red")
    for i, c in enumerate(("yellow", "yellow", "green_dark")):
        F.drum(sh, col, (11.4, 3.0 + i * 0.65, 0.02), c)
    with C.at((11.85, -1.5, 0.02), 90, sh, col):
        F.compressor(sh, col)
    maint_stairs(sh, col, (10.6, -7.0, 0.02), 90)
    F.tyre_stack(sh, col, (11.5, -11.0, 0.02), n=3)
    F.tyre_stack(sh, col, (11.5, -11.75, 0.02), n=2)
    for x in (-6.0, -3.2):
        with C.at((x, Y0 + 0.3, 0.02), 0, sh, col):
            F.steel_shelf(sh, col, 2.5, 0.55, 2.4, 5, stock=["cardboard", "tan", "gray_mid", "red", "yellow_dark"],
                          rng=rng, wmin=0.3, wmax=0.6, fill=0.8)
    with C.at((4.0, Y0 + 0.3, 0.02), 0, sh, col):
        F.workbench(sh, col, w=3.0, d=0.8, top="wood_mid", frame="steel_dark", board="gray_dark")
    F.crate(sh, col, (6.2, Y0 + 0.5, 0.02), (7.6, Y0 + 1.7, 1.3), "wood_mid", "wood_dark")
    for k in range(2):
        bx(sh, (-1.2 + k * 1.3, 11.5, 0.02), (-0.9 + k * 1.3, 11.8, 0.25), "hazard_yellow")
    high_bay(root, sh, [(-4.5, 7.0), (4.5, 7.0), (-4.5, -7.0), (4.5, -7.0)], 8.95, drop=1.2)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(-14, 14, -17, 17.5))
    sh.to_object(root, "shell", sharp_angle=30)
    col.to_object(root)
    K.marker(root, "spot", (0.0, 0.0, 0.02), (0, 0, 0))
    return root


# =========================================================================== lm_control_tower
NOTES["lm_control_tower"] = (
    "Airfield control tower, footprint 8x8, height 24.0 (antenna tip). Octagonal concrete shaft 4.4 across "
    "(z 0..17.6) with a closed steel door on +Y (no interior), caged ladder on the +X face, window slits; balcony deck "
    "at 17.6 with railing; octagonal cab with outward-slanted @Glass (z 18.6..21.2); roof 21.2..21.55 with antennas, "
    "led_red obstruction light at the mast tip and a rotating airport beacon. Part `beacon` = the beacon drum "
    "(green/white lenses), origin on its axis at (0.9, -0.9, 22.5): spin about Z. col: boxes (shaft, deck, cab, "
    "roof, door step) + deck railing. Extra marker `entrance` in front of the door (ground).")


def oct_pts(h, ch, z=0.0):
    """Chamfered square (8 points, CCW from above), half size h, chamfer ch."""
    return [(h, -h + ch), (h, h - ch), (h - ch, h), (-h + ch, h), (-h, h - ch), (-h, -h + ch), (-h + ch, -h), (h - ch, -h)]


def ring_faces(mb, pts0, z0, pts1, z1, color, out=True):
    """Quad band between two 8-point rings (outward or inward normals)."""
    n = len(pts0)
    for k in range(n):
        a, b = pts0[k], pts0[(k + 1) % n]
        c, d = pts1[(k + 1) % n], pts1[k]
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        ln = math.hypot(mx, my) or 1.0
        up = (mx / ln, my / ln, 0.0) if out else (-mx / ln, -my / ln, 0.0)
        C.poly_up(mb, [(a[0], a[1], z0), (b[0], b[1], z0), (c[0], c[1], z1), (d[0], d[1], z1)], color, up=up)


def build_lm_control_tower():
    root = K.begin_asset("lm_control_tower", C.CAT)
    sh, col = K.MB(), C.Col()
    SH, SC = 2.2, 0.65                  # shaft half size / chamfer
    ZD, ZC0, ZG0, ZG1, ZRF = 17.6, 17.9, 18.6, 21.2, 21.55
    CON, TRIM = "concrete_light", "concrete_dark"

    # ---------------------------------------------------------------- shaft
    shaft = oct_pts(SH, SC)
    sh.prism(shaft, ZD, CON, plane="XY", pos=(0, 0, 0), center=False, caps=(False, False))
    sh.prism(oct_pts(SH + 0.12, SC + 0.05), 0.45, TRIM, plane="XY", pos=(0, 0, 0), center=False, caps=(False, True))
    for z in (3.4, 6.8, 10.2, 13.6):
        sh.prism(oct_pts(SH + 0.03, SC + 0.012), 0.12, TRIM, plane="XY", pos=(0, 0, z), center=False, caps=(False, False))
    col.box((-SH, -SH, 0.0), (SH, SH, ZD))
    # window slits on the four main faces (not +X where the ladder runs, not the door bay)
    for z in (4.4, 7.8, 11.2, 14.6):
        for (axis, c, o) in (("X", SH, 1), ("X", -SH, -1), ("Y", -SH, -1)):
            C.pane(sh, axis, -0.35, 0.35, z, z + 1.5, c + o * 0.006, "@Window", o)
            if axis == "X":
                bx(sh, (-0.42, min(c, c + o * 0.06), z - 0.08), (0.42, max(c, c + o * 0.06), z), TRIM)
            else:
                bx(sh, (min(c, c + o * 0.06), -0.42, z - 0.08), (max(c, c + o * 0.06), 0.42, z), TRIM)
    # door bay on +Y: frame, closed steel door, canopy, lamp, step
    C.door_surround(sh, -0.65, 0.65, 2.35, SH, w=0.12, proud=0.06, color=TRIM)
    bx(sh, (-0.65, SH, 0.18), (0.65, SH + 0.03, 2.35), "steel_dark")
    bx(sh, (-0.5, SH + 0.03, 1.05), (-0.2, SH + 0.07, 1.1), "chrome")
    C.pane(sh, "X", -0.45, 0.45, 1.6, 2.15, SH + 0.034, "@Window", 1)
    bx(sh, (-1.0, SH, 2.7), (1.0, SH + 1.0, 2.82), "steel_dark")
    C.wall_lamp(sh, 0.0, SH, 2.95, out=1, color="steel_dark")
    bx(sh, (-0.9, SH, 0.0), (0.9, SH + 0.8, 0.18), TRIM)
    col.box((-0.9, SH, 0.0), (0.9, SH + 0.8, 0.18))
    # caged ladder on +X (rails, rungs, hoops)
    LX = SH + 0.2
    for y in (-0.25, 0.25):
        bx(sh, (SH, y - 0.03, 2.4), (LX + 0.03, y + 0.03, ZD), "steel_dark")
    z = 2.6
    while z < ZD - 0.2:
        C.obox(sh, (LX - 0.015, -0.25, z), (LX + 0.015, 0.25, z + 0.03), "steel", "+x+z-z")
        z += 0.45
    for zz in range(5, int(ZD), 2):
        bx(sh, (LX, -0.38, zz), (LX + 0.65, -0.34, zz + 0.05), "steel_dark")
        bx(sh, (LX, 0.34, zz), (LX + 0.65, 0.38, zz + 0.05), "steel_dark")
        bx(sh, (LX + 0.61, -0.38, zz), (LX + 0.65, 0.38, zz + 0.05), "steel_dark")
    for (y, x) in ((-0.36, LX + 0.63), (0.36, LX + 0.63), (0.0, LX + 0.63)):
        bx(sh, (x - 0.02, y - 0.02, 5.0), (x + 0.02, y + 0.02, ZD), "steel_dark")

    # ---------------------------------------------------------------- deck + railing
    deck = oct_pts(3.95, 1.15)
    sh.prism(deck, 0.3, CON, plane="XY", pos=(0, 0, ZD), center=False, cap_colors=(TRIM, "concrete"))
    col.box((-3.95, -3.95, ZD), (3.95, 3.95, ZD + 0.3))
    rail = oct_pts(3.85, 1.12)
    for k in range(8):
        a, b = rail[k], rail[(k + 1) % 8]
        sh.tube([(a[0], a[1], ZD + 1.35), (b[0], b[1], ZD + 1.35)], 0.035, "white", segs=4, caps=False)
        sh.tube([(a[0], a[1], ZD + 0.8), (b[0], b[1], ZD + 0.8)], 0.025, "white", segs=4, caps=False)
        bx(sh, (a[0] - 0.035, a[1] - 0.035, ZD + 0.3), (a[0] + 0.035, a[1] + 0.035, ZD + 1.35), "white")
        col.prism([(a[0], a[1]), (b[0], b[1]), (b[0] * 0.98, b[1] * 0.98), (a[0] * 0.98, a[1] * 0.98)], 1.05, plane="XY",
                  pos=(0, 0, ZD + 0.3), center=False)
    # diagonal struts under the deck overhang (two per side)
    for (nx, ny) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        for s in (-1.1, 1.1):
            tx, ty = -ny, nx
            p0 = (nx * SH + tx * s, ny * SH + ty * s, ZD - 1.7)
            p1 = (nx * 3.55 + tx * s, ny * 3.55 + ty * s, ZD - 0.02)
            sh.tube([p0, p1], 0.08, TRIM, segs=4, caps=False)
    # ---------------------------------------------------------------- cab: solid band, slanted glass, roof
    cb0 = oct_pts(3.0, 0.88)
    cbg = oct_pts(3.0, 0.88)
    cbt = oct_pts(3.55, 1.04)
    sh.prism(cb0, ZG0 - (ZD + 0.3), "white", plane="XY", pos=(0, 0, ZD + 0.3), center=False, caps=(False, False))
    sh.prism(oct_pts(3.03, 0.89), 0.12, "navy", plane="XY", pos=(0, 0, ZG0 - 0.2), center=False, caps=(False, False))
    ring_faces(sh, cbg, ZG0, cbt, ZG1, "@Glass", out=True)
    for k in range(8):
        a, b = cbg[k], cbt[k]
        sh.tube([(a[0], a[1], ZG0), (b[0], b[1], ZG1)], 0.06, "steel_dark", segs=4, caps=False)
    sh.prism(oct_pts(3.0, 0.88), 0.06, "steel_dark", plane="XY", pos=(0, 0, ZG0), center=False, caps=(False, True))
    sh.prism(oct_pts(3.55, 1.04), 0.08, "steel_dark", plane="XY", pos=(0, 0, ZG1 - 0.08), center=False, caps=(True, False))
    roof = oct_pts(3.95, 1.16)
    sh.prism(roof, ZRF - ZG1, "white", plane="XY", pos=(0, 0, ZG1), center=False, cap_colors=("gray_light", "roof_dark"))
    col.box((-3.0, -3.0, ZD + 0.3), (3.0, 3.0, ZG1))
    col.box((-3.95, -3.95, ZG1), (3.95, 3.95, ZRF))
    # cab interior: floor, console ring with screens, two seats
    sh.prism(oct_pts(2.95, 0.86), 0.01, "gray_mid", plane="XY", pos=(0, 0, ZG0 - 0.7), center=False, caps=(False, True))
    con = oct_pts(2.6, 0.78)
    con_in = oct_pts(2.1, 0.62)
    for k in range(8):
        a, b = con[k], con[(k + 1) % 8]
        c, d = con_in[(k + 1) % 8], con_in[k]
        C.poly_up(sh, [(a[0], a[1], ZG0 + 0.1), (b[0], b[1], ZG0 + 0.1), (c[0], c[1], ZG0 + 0.1), (d[0], d[1], ZG0 + 0.1)],
                  "charcoal")
        if k % 2 == 0:
            mx, my = (c[0] + d[0]) * 0.5, (c[1] + d[1]) * 0.5
            ang = math.degrees(math.atan2(my, mx)) - 90
            sh.box((0.55, 0.04, 0.35), (mx * 1.12, my * 1.12, ZG0 + 0.32), "black", rot=(0, 0, ang),
                   colors={"-y": "screen_blue"})
    ring_faces(sh, con_in, ZG0 - 0.7, con_in, ZG0 + 0.1, "charcoal", out=False)

    # ---------------------------------------------------------------- roof: masts, obstruction light, beacon
    sh.cyl(0.07, 24.0 - ZRF - 0.12, (-1.6, 1.6, ZRF), "white", segs=6, base=True)
    for z in (22.6, 23.4):
        sh.cyl(0.075, 0.25, (-1.6, 1.6, z), "red", segs=6, caps=False)
    sh.cyl(0.09, 0.12, (-1.6, 1.6, 24.0 - 0.12), "led_red", segs=6, base=True)
    sh.cyl(0.05, 1.6, (1.8, 1.4, ZRF), "steel", segs=6, base=True)
    sh.box((1.3, 0.08, 0.08), (1.8, 1.4, ZRF + 1.5), "steel_dark")
    sh.cyl(0.03, 2.0, (-2.0, -1.2, ZRF), "steel", segs=4, base=True, caps=False)
    sh.cyl(0.11, 0.9, (0.9, -0.9, ZRF), "steel_dark", segs=8, base=True)
    bx(sh, (0.55, -1.25, ZRF + 0.9), (1.25, -0.55, ZRF + 0.95), "steel_dark")
    bx(sh, (-0.6, -2.4, ZRF), (0.6, -1.6, ZRF + 0.7), "gray_light", bevel=0.03)
    bm = K.MB()
    BX, BY, BZ = 0.9, -0.9, ZRF + 0.95
    bm.cyl(0.26, 0.36, (BX, BY, BZ), "charcoal", segs=10, base=True, cap_color="gray_dark")
    for ang, c in ((0, "emis_always_white"), (180, "led_green")):
        with bm.at((BX, BY, BZ + 0.18), rot=(0, 0, ang)):
            bm.cyl(0.13, 0.08, (0, 0.25, 0), c, axis="Y", segs=8, smooth=False)
    bm.to_object(root, "beacon", origin=(BX, BY, BZ))

    # ---------------------------------------------------------------- parts
    C.cull_hidden(sh, C.ground_occ(-5, 5, -5, 5))
    sh.to_object(root, "shell", sharp_angle=35)
    col.to_object(root)
    K.marker(root, "entrance", (0.0, SH + 1.6, 0.0), (0, 0, 180))
    return root


# =========================================================================== lm_terminal
NOTES["lm_terminal"] = (
    "Small airfield terminal (not enterable), 18 x 10 x 5: building x -9..9, y -5..3, roof 4.0, sign fascia to 5.0; "
    "front curtain wall of @Window panes with closed glass entrance doors; canopy y 3..5 (underside 3.1) on 4 columns "
    "at y 4.8; benches, luggage cart, bins, planters and a flight-info board under the canopy. col: building box, "
    "canopy slab, columns, benches, cart, bins, planters, info board.")


def luggage_cart(mb, col, pos, rz=0.0, rng=None):
    """Baggage trolley with a few suitcases (long axis local X)."""
    rng = rng or random.Random(3)
    with mb.at(pos, rot=(0, 0, rz)):
        for (x, y) in ((-0.55, -0.3), (0.55, -0.3), (-0.55, 0.3), (0.55, 0.3)):
            mb.cyl(0.08, 0.05, (x, y, 0.08), "black", axis="Y", segs=6, smooth=False)
        bx(mb, (-0.7, -0.35, 0.16), (0.7, 0.35, 0.22), "steel")
        for x in (-0.7, 0.66):
            bx(mb, (x, -0.35, 0.22), (x + 0.04, 0.35, 0.95), "steel")
        bx(mb, (0.66, -0.35, 0.95), (0.7, 0.35, 1.0), "steel")
        mb.tube([(0.7, -0.3, 0.9), (0.95, -0.3, 1.0), (0.95, 0.3, 1.0), (0.7, 0.3, 0.9)], 0.02, "black", segs=4, caps=False)
        x = -0.62
        for i, c in enumerate(("navy", "red", "olive", "gray_dark", "teal")):
            w = rng.uniform(0.22, 0.3)
            h = rng.uniform(0.5, 0.65)
            if i < 4:
                bx(mb, (x, -0.28, 0.22), (x + w, 0.26, 0.22 + h), c, bevel=0.02)
                bx(mb, (x + w * 0.35, -0.04, 0.22 + h), (x + w * 0.65, 0.04, 0.27 + h), "black")
                x += w + 0.03
            else:
                mb.box((0.62, 0.45, 0.2), (-0.15, 0.0, 0.92), c, bevel=0.02, rot=(0, 4, 0))
    if col is not None:
        x, y, z = pos
        c, s = abs(math.cos(math.radians(rz))), abs(math.sin(math.radians(rz)))
        ex, ey = c * 0.95 + s * 0.38, s * 0.95 + c * 0.38
        col.box((x - ex, y - ey, z), (x + ex, y + ey, z + 1.05))


def park_bench(mb, col, pos, rz=0.0, w=1.8, seat="wood_mid", frame="charcoal"):
    """Outdoor bench, sitters face local +Y."""
    with mb.at(pos, rot=(0, 0, rz)):
        for x in (-w * 0.5 + 0.12, w * 0.5 - 0.16):
            bx(mb, (x, -0.22, 0.0), (x + 0.04, 0.22, 0.42), frame)
            bx(mb, (x, -0.25, 0.42), (x + 0.04, -0.2, 0.85), frame)
        for k in range(3):
            y = -0.18 + k * 0.14
            bx(mb, (-w * 0.5, y, 0.42), (w * 0.5, y + 0.11, 0.46), seat)
        for k in range(2):
            mb.box((w, 0.035, 0.1), (0.0, -0.24, 0.6 + k * 0.15), seat, rot=(-10, 0, 0))
    if col is not None:
        x, y, z = pos
        c, s = abs(math.cos(math.radians(rz))), abs(math.sin(math.radians(rz)))
        ex, ey = c * w * 0.5 + s * 0.27, s * w * 0.5 + c * 0.27
        col.box((x - ex, y - ey, z), (x + ex, y + ey, z + 0.46))


def build_lm_terminal():
    root = K.begin_asset("lm_terminal", C.CAT)
    sh, col = K.MB(), C.Col()
    rng = random.Random(81)
    X0, X1, Y0, Y1 = -9.0, 9.0, -5.0, 3.0
    ZR, ZP = 4.0, 4.4
    WALL, ACC = "white", "navy"
    CY1, CZ = 5.0, 3.1

    # ---------------------------------------------------------------- body
    bx(sh, (X0, Y0, 0.0), (X1, Y1 - 0.3, ZR), WALL, colors={"+z": "roof_gravel"})
    col.box((X0, Y0, 0.0), (X1, Y1, ZR))
    C.band(sh, X0, X1, Y0, Y1 - 0.3, 0.0, 0.45, 0.03, "concrete_dark", sides="ESW")
    C.parapet(sh, None, X0, X1, Y0, Y1 - 0.3, ZR, ZP - ZR, WALL, cope="gray_light", sides="ESW")
    # glazed front: recessed curtain wall between corner piers
    for sx in (-1, 1):
        bx(sh, (sx * 9.0 - (0.6 if sx > 0 else 0.0), Y1 - 0.3, 0.0), (sx * 9.0 + (0.0 if sx > 0 else 0.6), Y1, ZR), WALL)
    GX = 8.4
    C.pane(sh, "X", -GX, GX, 0.25, 3.55, Y1 - 0.29, "@Window", 1)
    bx(sh, (-GX, Y1 - 0.32, 0.0), (GX, Y1 - 0.2, 0.25), "gray_dark")
    nb = 12
    for i in range(nb + 1):
        x = -GX + 2 * GX * i / nb
        bx(sh, (x - 0.05, Y1 - 0.3, 0.25), (x + 0.05, Y1 - 0.18, 3.55), "steel_dark")
    for z in (2.55, 3.5):
        bx(sh, (-GX, Y1 - 0.3, z), (GX, Y1 - 0.2, z + 0.06), "steel_dark")
    # entrance doors (closed) in the central bay
    for sx in (-1, 1):
        bx(sh, (sx * 0.7 - 0.03, Y1 - 0.2, 0.25), (sx * 0.7 + 0.03, Y1 - 0.14, 2.45), "chrome")
    bx(sh, (-1.4, Y1 - 0.2, 0.25), (1.4, Y1 - 0.15, 0.32), "steel_dark")
    C.pane(sh, "X", -1.36, 1.36, 2.2, 2.25, Y1 - 0.145, "white", 1)
    bx(sh, (-1.6, Y1 - 0.3, 0.0), (1.6, Y1 + 0.6, 0.12), "concrete_light")
    # fascia band with the neon sign (full width, in front of the parapet)
    bx(sh, (X0 - 0.1, Y1 - 0.3, 3.55), (X1 + 0.1, Y1, 5.0), ACC)
    bx(sh, (X0 - 0.12, Y1 - 0.32, 4.95), (X1 + 0.12, Y1 + 0.02, 5.05), "gray_light")
    C.sign(sh, "VESPER AIRFIELD", (0.0, Y1, 4.38), 13.5, 0.62, "neon_cyan", depth=0.08, res=TXT_RES, valign="center")
    C.neon_path(sh, [(-8.6, 3.95), (8.6, 3.95)], Y1, w=0.05, d=0.03, color="neon_cyan")
    col.box((X0 - 0.1, Y1 - 0.3, ZR), (X1 + 0.1, Y1, 5.05))
    # canopy on four columns
    bx(sh, (-8.6, Y1, CZ), (8.6, CY1, CZ + 0.3), "white", colors={"-z": "gray_light"})
    bx(sh, (-8.65, CY1 - 0.08, CZ - 0.05), (8.65, CY1 + 0.04, CZ + 0.35), ACC)
    for x in (-6.5, -2.2, 2.2, 6.5):
        sh.cyl(0.13, CZ, (x, CY1 - 0.25, 0.0), "steel", segs=8, base=True)
        col.box((x - 0.13, CY1 - 0.38, 0.0), (x + 0.13, CY1 - 0.12, CZ))
        C.disc(sh, (x, Y1 + 1.0, CZ - 0.005), 0.18, "emis_lamp", axis="Z", segs=8, out=-1)
    col.box((-8.6, Y1, CZ), (8.6, CY1 + 0.04, CZ + 0.35))
    # side + back windows, back door, roof plant, mast
    for x in (-6.0, -3.0, 3.0, 6.0):
        C.pane(sh, "X", x - 0.9, x + 0.9, 1.4, 2.6, Y0 - 0.006, "@Window", -1)
        bx(sh, (x - 1.0, Y0 - 0.08, 1.32), (x + 1.0, Y0, 1.4), "gray_light")
    for (x, o) in ((X1, 1), (X0, -1)):
        for y in (-3.2, -0.8):
            C.pane(sh, "Y", y - 0.8, y + 0.8, 1.4, 2.6, x + o * 0.006, "@Window", o)
    C.door_surround(sh, -0.6, 0.6, 2.2, Y0, w=0.08, proud=0.04, color="gray_dark", out=-1)
    bx(sh, (-0.6, Y0 - 0.025, 0.0), (0.6, Y0, 2.2), "gray_mid")
    C.wall_lamp(sh, 0.0, Y0, 2.5, out=-1, color="gray_dark")
    C.roof_ac(sh, col, -4.5, -2.5, ZR, 2.0, 1.3, 0.9)
    C.roof_ac(sh, col, 1.0, -2.8, ZR, 1.6, 1.1, 0.8)
    sh.cyl(0.05, 0.6, (6.5, -3.5, ZR), "steel", segs=6, base=True)
    sh.cyl(0.32, 0.12, (6.5, -3.5, ZR + 0.55), "white", segs=10, r2=0.06, smooth=False, rot=(0, 30, 0))
    # forecourt furniture
    for x in (-4.4, 4.4):
        park_bench(sh, col, (x, Y1 + 0.75, 0.0), 0)
    luggage_cart(sh, col, (-6.9, Y1 + 1.6, 0.0), 15, rng)
    for x in (-1.9, 1.9):
        sh.cyl(0.22, 0.85, (x, Y1 + 0.5, 0.0), "steel_dark", segs=8, base=True, cap_color="black")
        col.box((x - 0.22, Y1 + 0.28, 0.0), (x + 0.22, Y1 + 0.72, 0.85))
    for x in (-8.2, 8.2):
        sh.cyl(0.42, 0.6, (x, Y1 + 1.3, 0.0), "concrete", segs=8, base=True, cap_color="dirt", smooth=False)
        sh.ico(0.5, (x, Y1 + 1.3, 1.05), "leaf_green", subdiv=1, jitter=0.15, seed=int(x * 10))
        col.box((x - 0.42, Y1 + 0.88, 0.0), (x + 0.42, Y1 + 1.72, 0.6))
    # flight info board on two legs
    IB0, IB1 = 3.2, 4.5
    bx(sh, (IB0 + 0.1, Y1 + 1.55, 0.0), (IB0 + 0.18, Y1 + 1.63, 1.2), "steel_dark")
    bx(sh, (IB1 - 0.18, Y1 + 1.55, 0.0), (IB1 - 0.1, Y1 + 1.63, 1.2), "steel_dark")
    bx(sh, (IB0, Y1 + 1.52, 1.2), (IB1, Y1 + 1.66, 2.05), "black")
    C.pane(sh, "X", IB0 + 0.06, IB1 - 0.06, 1.26, 1.99, Y1 + 1.665, "screen_blue", 1)
    for k in range(4):
        C.pane(sh, "X", IB0 + 0.12, IB1 - 0.4 - (k % 2) * 0.2, 1.84 - k * 0.15, 1.88 - k * 0.15, Y1 + 1.67, "white", 1)
    col.box((IB0, Y1 + 1.52, 0.0), (IB1, Y1 + 1.66, 2.05))

    # ---------------------------------------------------------------- parts
    C.cull_hidden(sh, C.ground_occ(-11, 11, -7, 7))
    sh.to_object(root, "shell", sharp_angle=35)
    col.to_object(root)
    return root


# =========================================================================== build all
BUILDERS = [("lm_gas_station", build_lm_gas_station), ("lm_hangar", build_lm_hangar),
            ("lm_control_tower", build_lm_control_tower), ("lm_terminal", build_lm_terminal)]


def build_all(only=None):
    out = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
        out.append(export(name))
    return "\n".join(out)
