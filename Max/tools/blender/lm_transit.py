"""lm_transit - BayLine monorail infrastructure for NEON TIDE (SPEC_LANDMARKS.md, "P2 - Transit").

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C, lm_fix as F, lm_transit as TR
    for m in (K, C, F, TR): importlib.reload(m)
    print(TR.build_all())
"""
import math

import gta_kit as K
import lm_common as C
import lm_fix as F
from lm_common import bx

NOTES = {}
TXT_RES = 2


def export(name):
    return C.finish(name, NOTES.get(name, ""))


# =========================================================================== rail_beam_8
NOTES["rail_beam_8"] = (
    "Monorail guideway beam segment 8.0 (Y) x 0.9 (X) x 1.2 deep. ORIGIN AT THE CENTRE OF ITS TOP FACE: z = 0 is the "
    "running surface, the beam hangs down to z -1.2. Tile along Y every 8.0 m. Steel power rail strip on each side "
    "(z -0.36..-0.24), expansion joint plates at both ends. col: one box.")


def build_rail_beam_8():
    root = K.begin_asset("rail_beam_8", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    L, W, D = 8.0, 0.9, 1.2
    sh.box((W, L - 0.02, D), (0, 0, -D * 0.5), "concrete_light", bevel=0.03, colors={"+z": "concrete"})
    for sx in (-1, 1):
        x = sx * W * 0.5
        bx(sh, (min(x, x + sx * 0.06), -L * 0.5 + 0.05, -0.36), (max(x, x + sx * 0.06), L * 0.5 - 0.05, -0.24), "steel")
        bx(sh, (min(x, x + sx * 0.02), -L * 0.5 + 0.05, -0.4), (max(x, x + sx * 0.02), L * 0.5 - 0.05, -0.2), "steel_dark")
        for k in range(5):
            y = -L * 0.5 + 0.4 + k * (L - 0.8) / 4
            bx(sh, (min(x, x + sx * 0.09), y - 0.06, -0.42), (max(x, x + sx * 0.09), y + 0.06, -0.18), "black")
    for sy in (-1, 1):
        y = sy * (L * 0.5 - 0.01)
        C.pane(sh, "X", -W * 0.5, W * 0.5, -D, 0.0, y, "gray_dark", sy)
    col.box((-W * 0.5, -L * 0.5, -D), (W * 0.5, L * 0.5, 0.0))
    sh.to_object(root, "shell")
    col.to_object(root)
    return root


# =========================================================================== rail_pier
NOTES["rail_pier"] = (
    "T-pier for the monorail: origin on the ground, footing 2.0 sq (z -0.3..0.25), round shaft r 0.45 to z 4.8, "
    "flared head 2.2 (X) x 1.2 (Y) with its top at z 5.8 + two bearing pads; a beam set on it at z 5.8 has its "
    "running surface at 7.0. col: footing, shaft box, head box.")


def build_rail_pier():
    root = K.begin_asset("rail_pier", C.CAT, spacing=20.0)
    sh, col = K.MB(), C.Col()
    bx(sh, (-1.0, -1.0, -0.3), (1.0, 1.0, 0.25), "concrete", bevel=0.03)
    sh.cyl(0.45, 4.6, (0, 0, 0.25), "concrete_light", segs=12, base=True, smooth=True)
    sh.loft([[(-0.42, -0.42, 4.8), (0.42, -0.42, 4.8), (0.42, 0.42, 4.8), (-0.42, 0.42, 4.8)],
             [(-1.1, -0.6, 5.55), (1.1, -0.6, 5.55), (1.1, 0.6, 5.55), (-1.1, 0.6, 5.55)],
             [(-1.1, -0.6, 5.74), (1.1, -0.6, 5.74), (1.1, 0.6, 5.74), (-1.1, 0.6, 5.74)]], "concrete_light",
            cap_start=True, cap_end=True)
    for sy in (-1, 1):
        bx(sh, (-0.35, sy * 0.3 - 0.18, 5.74), (0.35, sy * 0.3 + 0.18, 5.8), "steel_dark")
    bx(sh, (-1.12, -0.62, 5.0), (1.12, -0.6, 5.08), "blue")
    bx(sh, (-1.12, 0.6, 5.0), (1.12, 0.62, 5.08), "blue")
    col.box((-1.0, -1.0, -0.3), (1.0, 1.0, 0.25))
    col.box((-0.45, -0.45, 0.25), (0.45, 0.45, 4.8))
    col.box((-1.1, -0.6, 4.8), (1.1, 0.6, 5.8))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    return root


# =========================================================================== rail_station
NOTES["rail_station"] = (
    "Elevated BayLine station, 24 long (y -12..12). Track beam passes at x = 0 (not modelled). Platform x 1.45..6.6, "
    "floor z 7.55, yellow tactile strip along the edge (x 1.45..1.95), canopy (z 10.2..10.45) on posts at x 6.2 "
    "overhanging the edge, neon 'BAYLINE' signs on both canopy fascias (+X street side, -X track side), benches, "
    "ticket machine, railing on the +X edge. Stairs 1.8 wide outside the +X edge (x 6.6..8.4): foot at the +Y end "
    "(y 12.1, ground), flight 1 down-to-up toward -Y to a mid landing (z 3.775, y 5.9..4.1), flight 2 to the top "
    "landing (z 7.55, y -2.1..-3.9) which opens onto the platform. Markers: entrance (ground at the stair foot), "
    "board (platform edge at the train door, x 1.6, y 0, z 7.55, looking -X at the track), wait (platform centre). "
    "col: platform slab, supports, stair flights as sloped boxes, landings, railings, canopy posts.")


def stair_flight(sh, col, x0, x1, y_start, z_start, n, rise, run, color="concrete_light", nose="hazard_yellow"):
    """Sawtooth stair prism rising toward -Y from (y_start, z_start); returns (y_end, z_end)."""
    pts = [(y_start, z_start)]
    y, z = y_start, z_start
    for i in range(n):
        z += rise
        pts.append((y, z))
        y -= run
        pts.append((y, z))
    pts.append((y, z - 0.35))
    pts.append((y_start, z_start - 0.35))
    sh.prism(pts, x1 - x0, color, plane="YZ", pos=((x0 + x1) * 0.5, 0, 0))
    for i in range(0, n, 2):
        ya = y_start - i * run
        za = z_start + (i + 1) * rise
        sh.quad((x0 + 0.05, ya - 0.06, za + 0.004), (x1 - 0.05, ya - 0.06, za + 0.004), (x1 - 0.05, ya, za + 0.004),
                (x0 + 0.05, ya, za + 0.004), nose)
    col.slope_y(y_start + 0.15, z_start, y, z, x0, x1, thick=0.4)
    return y, z


def build_rail_station():
    root = K.begin_asset("rail_station", C.CAT, spacing=30.0)
    sh, col = K.MB(), C.Col()
    PX0, PX1, Y0, Y1, ZP = 1.45, 6.6, -12.0, 12.0, 7.55
    SX0, SX1 = 6.6, 8.4
    ZC0, ZC1 = 10.2, 10.45
    # ---------------------------------------------------------------- platform + supports
    bx(sh, (PX0, Y0, ZP - 0.35), (PX1, Y1, ZP), "concrete", colors={"+z": "concrete_light"})
    sh.quad((PX0 + 0.02, Y0 + 0.02, ZP + 0.004), (PX0 + 0.5, Y0 + 0.02, ZP + 0.004), (PX0 + 0.5, Y1 - 0.02, ZP + 0.004),
            (PX0 + 0.02, Y1 - 0.02, ZP + 0.004), "hazard_yellow")
    sh.quad((PX0 + 0.55, Y0 + 0.02, ZP + 0.004), (PX0 + 0.6, Y0 + 0.02, ZP + 0.004), (PX0 + 0.6, Y1 - 0.02, ZP + 0.004),
            (PX0 + 0.55, Y1 - 0.02, ZP + 0.004), "white")
    col.box((PX0, Y0, ZP - 0.35), (PX1, Y1, ZP))
    for y in (-9.0, -3.0, 3.0, 9.0):
        sh.cyl(0.4, ZP - 0.95, (4.4, y, 0.0), "concrete_light", segs=10, base=True, smooth=True)
        bx(sh, (PX0 + 0.3, y - 0.35, ZP - 0.95), (PX1, y + 0.35, ZP - 0.35), "concrete")
        bx(sh, (3.6, y - 0.8, -0.2), (5.2, y + 0.8, 0.2), "concrete", bevel=0.03)
        col.box((4.0, y - 0.4, 0.0), (4.8, y + 0.4, ZP - 0.35))
    # ---------------------------------------------------------------- canopy on rear posts
    for y in (-10.0, -5.0, 0.0, 5.0, 10.0):
        bx(sh, (6.1, y - 0.12, ZP), (6.35, y + 0.12, ZC0), "steel_dark")
        sh.box((0.12, 0.12, 3.2), (4.6, y, ZC0 - 0.75), "steel_dark", rot=(0, -62, 0))
        col.box((6.1, y - 0.12, ZP), (6.35, y + 0.12, ZC0))
    bx(sh, (1.2, Y0 - 0.3, ZC0), (6.75, Y1 + 0.3, ZC1), "white", colors={"-z": "gray_light", "+z": "roof_dark"})
    for (xa, xb, o) in ((1.0, 1.2, -1), (6.75, 6.95, 1)):
        bx(sh, (xa, Y0 - 0.3, ZC0 - 0.45), (xb, Y1 + 0.3, ZC1 + 0.1), "navy")
        xf = xa if o < 0 else xb
        C.sign(sh, "BAYLINE", (xf, 0.0, (ZC0 - 0.45 + ZC1 + 0.1) * 0.5), 5.0, 0.55, "neon_cyan", depth=0.06,
               res=TXT_RES, valign="center", rot=(0, 0, 90 if o < 0 else -90))
        for y in (-8.0, 8.0):
            C.pane(sh, "Y", y - 2.5, y + 2.5, ZC0 - 0.12, ZC0 - 0.08, xf + o * 0.006, "neon_cyan", o)
    col.box((1.0, Y0 - 0.3, ZC0 - 0.45), (6.95, Y1 + 0.3, ZC1 + 0.1))
    for y in (-8.0, -3.0, 3.0, 8.0):
        bx(sh, (2.6, y - 1.0, ZC0 - 0.06), (2.9, y + 1.0, ZC0), "gray_mid", colors={"-z": "emis_lamp"})
    # ---------------------------------------------------------------- platform furniture: railing, benches, machine
    for (ya, yb) in ((Y0 + 0.05, -4.0), (-2.0, Y1 - 0.05)):
        bx(sh, (PX1 - 0.06, ya, ZP + 1.0), (PX1, yb, ZP + 1.08), "steel")
        bx(sh, (PX1 - 0.05, ya, ZP + 0.5), (PX1 - 0.01, yb, ZP + 0.54), "steel")
        k = ya
        while k <= yb + 0.01:
            bx(sh, (PX1 - 0.06, k - 0.03, ZP), (PX1, k + 0.03, ZP + 1.0), "steel")
            k += 1.5
        col.box((PX1 - 0.08, ya, ZP), (PX1, yb, ZP + 1.08))
    for (ya, yb) in ((Y0 + 0.05, Y1 - 0.05),):
        for y in (ya, yb):
            bx(sh, (PX0 + 0.8, y - 0.03, ZP), (PX1, y + 0.03, ZP + 1.08), "steel")
            col.box((PX0 + 0.8, y - 0.03, ZP), (PX1, y + 0.03, ZP + 1.08))
    for y in (-7.0, 6.5):
        with sh.at((5.6, y, ZP), rot=(0, 0, 90)):
            for x in (-0.8, 0.76):
                bx(sh, (x, -0.2, 0.0), (x + 0.04, 0.2, 0.42), "steel_dark")
            for k in range(3):
                bx(sh, (-0.95, -0.18 + k * 0.13, 0.42), (0.95, -0.08 + k * 0.13, 0.46), "wood_mid")
            bx(sh, (-0.95, -0.24, 0.55), (0.95, -0.2, 0.85), "wood_mid")
        col.box((5.35, y - 0.95, ZP), (5.85, y + 0.95, ZP + 0.46))
    MX, MY = 6.15, -5.0
    bx(sh, (MX - 0.25, MY - 0.4, ZP), (MX + 0.2, MY + 0.4, ZP + 1.75), "navy", bevel=0.02)
    C.pane(sh, "Y", MY - 0.28, MY + 0.28, ZP + 1.1, ZP + 1.5, MX - 0.256, "screen_blue", -1)
    C.pane(sh, "Y", MY - 0.3, MY + 0.3, ZP + 1.58, ZP + 1.7, MX - 0.256, "neon_cyan", -1)
    bx(sh, (MX - 0.32, MY - 0.2, ZP + 0.85), (MX - 0.25, MY + 0.2, ZP + 0.98), "gray_dark")
    col.box((MX - 0.25, MY - 0.4, ZP), (MX + 0.2, MY + 0.4, ZP + 1.75))
    # route map panel on a post
    bx(sh, (PX1 - 0.12, 2.0, ZP), (PX1 - 0.04, 2.08, ZP + 2.2), "steel_dark")
    bx(sh, (PX1 - 0.16, 1.4, ZP + 1.2), (PX1 - 0.1, 2.7, ZP + 2.1), "white")
    for k, c in enumerate(("blue", "neon_cyan", "magenta")):
        C.pane(sh, "Y", 1.5, 2.6, ZP + 1.4 + k * 0.22, ZP + 1.45 + k * 0.22, PX1 - 0.165, c, -1)

    # ---------------------------------------------------------------- stairs (+X side, foot at the +Y end)
    n, rise, run = 22, ZP / 44.0, 0.28
    yf = 12.1
    y1, z1 = stair_flight(sh, col, SX0, SX1, yf, 0.0, n, rise, run)
    bx(sh, (SX0, y1 - 1.8, z1 - 0.3), (SX1, y1, z1), "concrete", colors={"+z": "concrete_light"})
    col.box((SX0, y1 - 1.8, z1 - 0.3), (SX1, y1, z1))
    y2, z2 = stair_flight(sh, col, SX0, SX1, y1 - 1.8, z1, n, rise, run)
    bx(sh, (SX0 - 0.05, y2 - 1.8, ZP - 0.3), (SX1, y2, ZP), "concrete", colors={"+z": "concrete_light"})
    col.box((SX0 - 0.05, y2 - 1.8, ZP - 0.3), (SX1, y2, ZP))
    for (yy, zz) in ((y1 - 0.9, z1), (y2 - 0.9, ZP)):
        for x in (SX0 + 0.35, SX1 - 0.35):
            sh.cyl(0.14, zz - 0.3, (x, yy, 0.0), "steel_dark", segs=6, base=True)
            col.box((x - 0.14, yy - 0.14, 0.0), (x + 0.14, yy + 0.14, zz - 0.3))
    # stair railings (sloped tubes) + landing rails
    for x in (SX0 + 0.12, SX1 - 0.12):
        for (ya, za, yb, zb) in ((yf, 0.0, y1, z1), (y1 - 1.8, z1, y2, z2)):
            sh.tube([(x, ya, za + 1.0), (x, yb, zb + 1.0)], 0.03, "steel", segs=4, caps=False)
            for t in (0.0, 0.5, 1.0):
                yy, zz = ya + (yb - ya) * t, za + (zb - za) * t
                bx(sh, (x - 0.025, yy - 0.025, zz), (x + 0.025, yy + 0.025, zz + 1.0), "steel")
            col.prism([(ya, za + 0.2), (yb, zb + 0.2), (yb, zb + 1.05), (ya, za + 1.05)], 0.06, plane="YZ", pos=(x, 0, 0))
    for x in (SX1 - 0.12,):
        bx(sh, (x - 0.03, y1 - 1.8, z1 + 0.97), (x + 0.03, y1, z1 + 1.03), "steel")
        bx(sh, (x - 0.03, y2 - 1.8, ZP + 0.97), (x + 0.03, y2, ZP + 1.03), "steel")
        col.box((x - 0.06, y2 - 1.8, ZP), (x + 0.06, y2, ZP + 1.05))
    bx(sh, (SX0 + 0.1, y2 - 1.83, ZP + 0.97), (SX1 - 0.1, y2 - 1.77, ZP + 1.03), "steel")
    col.box((SX0 + 0.1, y2 - 1.86, ZP), (SX1 - 0.1, y2 - 1.8, ZP + 1.05))
    # station totem at the stair foot
    bx(sh, (SX1 + 0.3, yf + 0.2, 0.0), (SX1 + 0.6, yf + 1.1, 3.2), "navy")
    C.sign(sh, "BAYLINE", (SX1 + 0.6, yf + 0.65, 2.5), 0.85, 0.14, "neon_cyan", depth=0.03, res=1, valign="center",
           rot=(0, 0, -90))
    bx(sh, (SX1 + 0.62, yf + 0.3, 1.0), (SX1 + 0.63, yf + 1.0, 2.1), "neon_cyan")
    col.box((SX1 + 0.3, yf + 0.2, 0.0), (SX1 + 0.6, yf + 1.1, 3.2))

    C.cull_hidden(sh, C.ground_occ(-1, 10, -14, 15))
    sh.to_object(root, "shell", sharp_angle=40)
    col.to_object(root)
    K.marker(root, "entrance", ((SX0 + SX1) * 0.5, yf + 1.2, 0.0), (0, 0, 180))
    K.marker(root, "board", (1.6, 0.0, ZP), (0, 0, 90))
    K.marker(root, "wait", (4.0, 0.0, ZP), (0, 0, 90))
    return root


# =========================================================================== build all
BUILDERS = [("rail_beam_8", build_rail_beam_8), ("rail_pier", build_rail_pier), ("rail_station", build_rail_station)]


def build_all(only=None):
    out = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
        out.append(export(name))
    return "\n".join(out)
