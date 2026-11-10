"""lm_shops - enterable shops + the safehouse for NEON TIDE (SPEC_LANDMARKS.md, P1).

Run inside Blender (Blender MCP):

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K, lm_common as C, lm_fix as F, lm_shops as M
    for m in (K, C, F, M): importlib.reload(m)
    print(M.build_all())            # build + export + manifest for every asset of this module
    # or: M.build_shop_garage(); print(M.export("shop_garage"))
"""
import math
import random

import gta_kit as K
import lm_common as C
import lm_fix as F
from lm_common import bx

NOTES = {}
TXT_RES = 2      # curve resolution of the 3D sign lettering


def export(name):
    return C.finish(name, NOTES.get(name, ""))


# =========================================================================== shop_garage  "TORQUE HOUSE"
NOTES["shop_garage"] = (
    "TORQUE HOUSE mod garage. Footprint 16x14 (x -8..8, y -7..7), walls 0.25, wall/parapet top 6.0, stepped sign "
    "false-front above the bay to z 8.1. Interior floor 0.02, ceiling 5.3. Bay opening x -2.5..2.5, z 0..4.02 "
    "(4.0 clear) in the +Y wall; part `door` = roll-up door inside the wall thickness, origin at the centre of its "
    "TOP edge (0, 6.875, 4.02) - scale Z towards the origin or slide up 4 m (it stays hidden inside the false "
    "front). Lift posts at x +-1.87 (3.4 m clear), overhead beam at z 4.2. Office booth in the back +X corner "
    "(counter hatch on its +Y side). Extra marker `spawn`. Bollards / tyre stack stand up to 0.75 m in front of "
    "the +Y wall.")


def build_shop_garage():
    root = K.begin_asset("shop_garage", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(11)
    X0, X1, Y0, Y1, T = -8.0, 8.0, -7.0, 7.0, 0.25
    ZF, ZC, ZR, ZP = 0.02, 5.3, 5.55, 6.0
    EXT, INN, BASE = "navy", "@D:gray_light", "charcoal"
    BX0, BX1, BZ = -2.5, 2.5, 4.02
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn, ys, xe, xw = Y1 - T / 2, Y0 + T / 2, X1 - T / 2, X0 + T / 2

    # ---------------------------------------------------------------- shell
    win = [(-4.6, -2.2, 3.5, 4.6, "glass"), (-1.2, 1.2, 3.5, 4.6, "glass"), (2.2, 4.6, 3.5, 4.6, "glass")]
    C.wall(sh, col, "X", X0, X1, yn, 0, ZR, EXT, INN, 1, T, [(BX0, BX1, 0, BZ)])
    C.wall(sh, col, "X", X0, X1, ys, 0, ZR, EXT, INN, -1, T)
    C.wall(sh, col, "Y", yi0, yi1, xe, 0, ZR, EXT, INN, 1, T, win)
    C.wall(sh, col, "Y", yi0, yi1, xw, 0, ZR, EXT, INN, -1, T, win)
    for o in win:      # frameless clerestory glass set in the reveal + a proud steel sill
        for xc, sgn in ((xe, 1), (xw, -1)):
            C.pane(sh, "Y", o[0], o[1], o[2], o[3], xc, "@Glass", sgn)
            xo = xc + sgn * T / 2
            bx(sh, (min(xo, xo + sgn * 0.06), o[0] - 0.08, o[2] - 0.08), (max(xo, xo + sgn * 0.06), o[1] + 0.08, o[2]),
               "steel_dark")
    C.floor_slab(sh, col, X0, X1, Y0, Y1, "@D:concrete", ZF, T)
    C.threshold(sh, col, BX0, BX1, yi1, Y1, "concrete_dark", ZF, lip=0.4)
    C.flat_roof(sh, col, X0, X1, Y0, Y1, ZC, ZR, "@D:gray_mid", "roof_dark", T)
    C.parapet(sh, col, X0, X1, Y0, Y1, ZR, ZP - ZR - 0.08, EXT)
    gap = {"N": [(BX0 - 0.22, BX1 + 0.22)]}
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.9, 0.04, BASE, gap)
    C.band(sh, X0, X1, Y0, Y1, 0.9, 1.0, 0.05, "hazard_yellow", gap)

    # bay frame with hazard guards + bollards
    for sx in (-1, 1):
        xa, xb = (BX0 - 0.22, BX0) if sx < 0 else (BX1, BX1 + 0.22)
        bx(sh, (xa, Y1, 1.3), (xb, Y1 + 0.06, BZ), "steel_dark")
        bx(sh, (xa, Y1, 0.0), (xb, Y1 + 0.07, 1.3), "hazard_yellow")
        for k in range(3):
            z = 0.1 + k * 0.4
            sh.quad((xb, Y1 + 0.075, z), (xa, Y1 + 0.075, z + 0.1), (xa, Y1 + 0.075, z + 0.28),
                    (xb, Y1 + 0.075, z + 0.18), "black")
        sh.cyl(0.11, 1.0, (sx * 3.0, Y1 + 0.34, 0), "hazard_yellow", segs=8, base=True)
        sh.cyl(0.118, 0.14, (sx * 3.0, Y1 + 0.34, 0.74), "black", segs=8, caps=False)
        col.box((sx * 3.0 - 0.1, Y1 + 0.24, 0), (sx * 3.0 + 0.1, Y1 + 0.44, 1.0))
    bx(sh, (BX0 - 0.22, Y1, BZ), (BX1 + 0.22, Y1 + 0.06, BZ + 0.22), "steel_dark")

    # stepped sign board (false front) - also hides the roll door if Godot slides it straight up
    SB = "black"
    yf = Y1 + 0.08
    bx(sh, (-4.6, Y1, 4.5), (4.6, yf, ZR), SB)
    bx(sh, (-4.6, Y1 - 0.3, ZR), (4.6, yf, 7.2), SB)
    bx(sh, (-3.6, Y1 - 0.3, 7.2), (3.6, yf, 8.1), SB)
    for xb in (-3.0, 0.0, 3.0):          # raking struts behind the sign board
        sh.box((0.1, 0.1, 2.9), (xb, Y1 - 1.15, ZR + 1.05), "steel_dark", rot=(-40, 0, 0))
    col.box((-4.6, Y1 - 0.3, ZR), (4.6, yf, 7.2))
    col.box((-3.6, Y1 - 0.3, 7.2), (3.6, yf, 8.1))
    C.sign(sh, "TORQUE HOUSE", (0, yf, 7.0), 6.5, 0.72, "neon_yellow", depth=0.1, res=TXT_RES)
    C.sign(sh, "CUSTOMS", (0.0, yf, 5.98), 3.5, 0.55, "neon_pink", depth=0.08, rot=(0, 5, 0), res=TXT_RES)
    sh.box((4.0, 0.035, 0.05), (0, yf + 0.0175, 5.8), "neon_pink", rot=(0, 5, 0))
    # painted speed stripes on the front flanks and along the side walls
    for sx in (-1, 1):
        C.poly_up(sh, [(sx * 4.95, Y1 + 0.006, 1.02), (sx * 5.6, Y1 + 0.006, 1.02), (sx * 7.4, Y1 + 0.006, 5.5),
                       (sx * 6.75, Y1 + 0.006, 5.5)], "hazard_yellow", up=(0, 1, 0))
        C.poly_up(sh, [(sx * 5.85, Y1 + 0.006, 1.02), (sx * 6.1, Y1 + 0.006, 1.02), (sx * 7.9, Y1 + 0.006, 5.5),
                       (sx * 7.65, Y1 + 0.006, 5.5)], "magenta", up=(0, 1, 0))
    C.band(sh, X0, X1, Y0, Y1, 2.35, 2.7, 0.006, "hazard_yellow", sides="EW", flat=True)
    C.band(sh, X0, X1, Y0, Y1, 2.1, 2.2, 0.006, "magenta", sides="EW", flat=True)
    path = [(-4.5, 4.6), (-4.5, 7.1), (-3.5, 7.1), (-3.5, 8.0), (3.5, 8.0), (3.5, 7.1), (4.5, 7.1), (4.5, 4.6),
            (-4.5, 4.6)]
    for a, b in zip(path, path[1:]):
        bx(sh, (min(a[0], b[0]) - 0.025, yf, min(a[1], b[1]) - 0.025),
           (max(a[0], b[0]) + 0.025, yf + 0.035, max(a[1], b[1]) + 0.025), "neon_yellow")
    cz0, cs = 4.74, 0.25
    bx(sh, (-4.25, yf, cz0), (4.25, yf + 0.012, cz0 + 2 * cs), "white")
    for i in range(34):
        r = i % 2
        xa = -4.25 + i * cs
        C.pane(sh, "X", xa, xa + cs, cz0 + r * cs, cz0 + (r + 1) * cs, yf + 0.017, "black", 1)

    # wall lamps, downpipes, back door, roof plant
    for sx in (-1, 1):
        bx(sh, (sx * 6.0 - 0.2, Y1, 3.9), (sx * 6.0 + 0.2, Y1 + 0.32, 4.0), "steel_dark")
        bx(sh, (sx * 6.0 - 0.15, Y1 + 0.05, 3.86), (sx * 6.0 + 0.15, Y1 + 0.28, 3.9), "emis_lamp")
        bx(sh, (sx * 8.0 - (0.1 if sx < 0 else 0.0), Y0 + 0.3, 0.0), (sx * 8.0 + (0.1 if sx > 0 else 0.0), Y0 + 0.42, ZR),
           "steel_dark")
    bx(sh, (5.25, Y0 - 0.04, 0.0), (6.35, Y0, 2.2), "steel_dark")
    bx(sh, (5.32, Y0 - 0.06, 0.02), (6.28, Y0, 2.13), "gray_mid")
    bx(sh, (5.4, Y0 - 0.1, 1.0), (5.46, Y0 - 0.06, 1.12), "chrome")
    bx(sh, (5.55, Y0 - 0.22, 2.36), (6.05, Y0, 2.46), "steel_dark", colors={"-z": "emis_lamp"})
    bx(sh, (3.0, -4.0, ZR), (5.0, -2.6, ZR + 0.12), "steel_dark")
    bx(sh, (3.1, -3.9, ZR + 0.12), (4.9, -2.7, ZR + 1.0), "gray_light", bevel=0.03)
    C.disc(sh, (4.0, -3.3, ZR + 1.005), 0.5, "charcoal", axis="Z", segs=12)
    col.box((3.0, -4.0, ZR), (5.0, -2.6, ZR + 1.0))
    sh.cyl(0.3, 1.5, (-4.5, -2.0, ZR), "steel", segs=10, base=True)
    sh.cyl(0.44, 0.14, (-4.5, -2.0, ZR + 1.57), "steel_dark", segs=10, r2=0.12)
    col.box((-4.8, -2.3, ZR), (-4.2, -1.7, ZR + 1.6))
    # tyres + drum outside, left of the bay
    F.tyre_stack(sh, col, (-6.4, Y1 + 0.42, 0.0), n=3)
    F.drum(sh, col, (-5.55, Y1 + 0.38, 0.0), "red")

    # ---------------------------------------------------------------- fixtures
    ing = {"N": [(BX0 - 0.02, BX1 + 0.02)]}
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, 1.2, 0.012, "gray_dark", ing)
    C.band_in(fx, xi0, xi1, yi0, yi1, 1.2, 1.36, 0.016, "hazard_yellow", ing)
    if not C.OPEN_TOP:
        for y in (-3.4, 0.0, 3.4):
            bx(fx, (xi0, y - 0.1, ZC - 0.3), (xi1, y + 0.1, ZC), "steel_dark")
    C.ceiling_lights(root, fx, [(-2.45, 2.7), (2.45, 2.7), (-2.45, -1.7), (2.45, -1.7)], ZC, size=(0.2, 2.6),
                     drop=0.75, emis="emis_cool_always")
    F.hazard_outline(fx, -2.45, 2.45, -2.9, 3.9, ZF + 0.006)
    with C.at((0, 0.5, ZF), 0, fx, col):
        F.lift_2post(fx, col)
    bx(fx, (BX0 - 0.2, yi1 - 0.32, BZ + 0.06), (BX1 + 0.2, yi1, BZ + 0.6), "steel_dark")
    bx(fx, (BX1 + 0.2, yi1 - 0.3, BZ + 0.14), (BX1 + 0.6, yi1, BZ + 0.5), "gray_dark")

    # west wall: tyre rack, tyre stack, drums, compressor
    with C.at((xi0, 3.3, ZF), -90, fx, col):
        F.tyre_rack(fx, col, w=3.0)
    F.tyre_stack(fx, col, (xi0 + 0.45, 1.2, ZF), n=4)
    F.drum(fx, col, (xi0 + 0.4, 0.2, ZF), "blue")
    F.drum(fx, col, (xi0 + 0.4, -0.5, ZF), "orange")
    with C.at((xi0, -3.0, ZF), -90, fx, col):
        F.compressor(fx, col)
    # back wall: workbench + parts shelving
    with C.at((-5.3, yi0, ZF), 0, fx, col):
        F.workbench(fx, col, w=2.8)
    with C.at((-0.7, yi0, ZF), 0, fx, col):
        F.steel_shelf(fx, col, 4.4, 0.55, 2.3, 4, stock=["cardboard", "cardboard", "tan", "red", "blue_dark", "gray_mid"],
                      rng=rng, wmin=0.35, wmax=0.7, fill=0.8)
    # east wall: tool chests, cabinet, rim display over a low shelf
    with C.at((xi1, 5.5, ZF), 90, fx, col):
        F.tool_chest(fx, col)
    with C.at((xi1, 4.2, ZF), 90, fx, col):
        F.tool_chest(fx, col, upper=False, drawers=5)
    bx(fx, (xi1 - 0.5, 2.45, ZF), (xi1, 3.45, 1.95), "red")
    bx(fx, (xi1 - 0.512, 2.94, ZF + 0.1), (xi1 - 0.5, 2.96, 1.9), "black")
    for dy in (-0.07, 0.07):
        bx(fx, (xi1 - 0.54, 2.95 + dy - 0.012, 0.95), (xi1 - 0.5, 2.95 + dy + 0.012, 1.2), "aluminum")
    col.box((xi1 - 0.5, 2.45, 0), (xi1, 3.45, 1.95))
    with C.at((xi1, -0.9, ZF), 90, fx, col):
        F.steel_shelf(fx, col, 2.6, 0.5, 1.25, 3, stock=["cardboard", "tan", "gray_dark", "yellow_dark"], rng=rng,
                      wmin=0.3, wmax=0.6)
    for i in range(4):
        F.wall_rim(fx, (xi1, -1.95 + i * 0.7, 2.0), out=-1)

    # engine on a stand, welding bottles, wing + banner on the back wall, painted walkway to the office
    with C.at((-4.4, -3.4, ZF), 25, fx, col):
        F.engine_stand(fx, col)
    with C.at((xi0, -4.4, ZF), -90, fx, col):
        F.gas_bottles(fx, col)
    with C.at((-5.3, yi0, 3.0), 0, fx):
        F.wall_spoiler(fx)
    F.frame_art(fx, "X", -2.4, 1.0, 2.75, 3.85, yi0, 1, [(0.0, 1.0, 0.0, 1.0, "hazard_yellow"), (0.06, 0.94, 0.38, 0.62, "black"),
                                                       (0.06, 0.94, 0.1, 0.2, "magenta"), (0.06, 0.94, 0.8, 0.9, "magenta")])
    F.floor_quad(fx, 3.2, 4.4, -2.85, 6.55, ZF + 0.005, "concrete_dark")
    for xa in (3.2, 4.32):
        F.floor_quad(fx, xa, xa + 0.08, -2.85, 6.55, ZF + 0.009, "hazard_yellow")

    # office booth (back +X corner): partitions, counter hatch, lid with clutter
    OX0, OX1, OY0, OY1, PT, OH = 3.75, xi1, yi0, -3.25, 0.12, 2.7
    C.wall(fx, col, "Y", OY0, OY1, OX0 + PT / 2, ZF, OH, "white", "white", -1, PT,
           [(-6.45, -5.45, 0, 2.12), (-5.2, -3.5, 1.0, 2.5, "glass")])
    C.glazing(fx, "Y", -5.2, -3.5, 1.0, 2.5, OX0 + PT / 2, n=1, fd=0.08, out=-1)
    C.wall(fx, col, "X", OX0 + PT, OX1, OY1 - PT / 2, ZF, OH, "white", "white", 1, PT, [(4.1, 7.5, 1.0, 2.3)])
    bx(fx, (4.0, OY1 - PT - 0.3, 1.0), (7.6, OY1 + 0.32, 1.05), "wood_mid", bevel=0.012)
    col.box((4.1, OY1 - PT, 0.0), (7.5, OY1 + 0.32, 1.05))
    col.box((4.1, OY1 - PT - 0.3, 0.9), (7.5, OY1 - PT, 1.05))
    bx(fx, (OX0 - 0.03, OY0, OH - 0.25), (OX1, OY1 + 0.03, OH - 0.02), "hazard_yellow")
    if not C.OPEN_TOP:
        bx(fx, (OX0 - 0.03, OY0, OH - 0.02), (OX1, OY1 + 0.03, OH + 0.08), "gray_dark")
        bx(fx, (5.2, -5.4, OH - 0.3), (6.4, -4.6, OH - 0.25), "emis_warm_always")
    col.box((OX0, OY0, OH - 0.25), (OX1, OY1, OH + 0.08))
    bx(fx, (4.3, OY1, 2.46), (7.3, OY1 + 0.03, 2.52), "neon_pink")
    F.monitor(fx, (6.7, OY1 - PT - 0.12, 1.05), 180)
    bx(fx, (6.45, OY1 - PT - 0.28, 1.05), (6.95, OY1 - PT - 0.2, 1.07), "plastic_black")
    bx(fx, (4.6, OY1 + 0.05, 1.05), (4.78, OY1 + 0.2, 1.13), "plastic_black", colors={"+z": "screen_blue"})
    F.office_chair(fx, (5.8, -4.95, ZF), 20)
    bx(fx, (7.1, yi0, ZF), (7.7, yi0 + 0.6, 1.3), "gray_mid")
    for k in range(3):
        bx(fx, (7.25, yi0 + 0.6, 0.3 + k * 0.4), (7.55, yi0 + 0.625, 0.33 + k * 0.4), "aluminum")
    bx(fx, (4.3, yi0, 1.55), (6.6, yi0 + 0.28, 1.58), "wood_mid")
    for i, c in enumerate(("red", "blue", "green_dark", "yellow", "white", "navy")):
        C.obox(fx, (4.4 + i * 0.3, yi0 + 0.02, 1.58), (4.66 + i * 0.3, yi0 + 0.26, 1.58 + 0.3 + 0.03 * (i % 3)), c,
               "+x-x+y+z")
    bx(fx, (5.3, yi0, ZF), (6.3, yi0 + 0.03, 2.13), "gray_mid")
    bx(fx, (5.38, yi0 + 0.03, 1.0), (5.44, yi0 + 0.07, 1.12), "chrome")
    if not C.OPEN_TOP:
        F.crate(fx, None, (4.2, -6.4, OH + 0.08), (5.0, -5.7, OH + 0.6))
        F.crate(fx, None, (5.1, -6.5, OH + 0.08), (5.7, -6.0, OH + 0.45))
        F.tyre(fx, (6.7, -5.6, OH + 0.08 + 0.105), "Z", hub=True)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh)
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    C.roll_door(root, "door", BX0, BX1, yn, 0.0, BZ, color="steel", bar="hazard_yellow", slat=0.25)
    col.to_object(root)
    K.marker(root, "bay", (0, 0.5, ZF), (0, 0, 180))
    K.marker(root, "entrance", (0, Y1 + 8.0, 0), (0, 0, 180))
    K.marker(root, "counter", (5.8, -2.3, ZF), (0, 0, 180))
    K.marker(root, "staff", (5.8, -4.35, ZF), (0, 0, 0))
    K.marker(root, "spawn", (4.6, 2.6, ZF), (0, 0, 180))
    return root


# =========================================================================== shared storefront pieces
def storefront_windows(sh, wins, z0, z1, yn, Y1, frame="steel_dark", sill="steel", kick=None, every=1.4, fw=0.06):
    """Framed glass in front-wall openings (wall centre plane yn, outer face Y1) + sill and optional kick plate."""
    for a, b in wins:
        C.glazing(sh, "X", a, b, z0, z1, yn, frame=frame, every=every, fw=fw, fd=0.1, out=1)
        bx(sh, (a - 0.05, Y1, z0 - 0.06), (b + 0.05, Y1 + 0.07, z0), sill)
        if kick:
            bx(sh, (a, Y1, 0.0), (b, Y1 + 0.025, z0 - 0.06), kick)


def entrance_marks(root, x, Y1, zf=0.02, spawn=None, extra=()):
    K.marker(root, "entrance", (x, Y1 + 1.5, 0.0), (0, 0, 180))
    if spawn:
        K.marker(root, "spawn", (spawn[0], spawn[1], zf), (0, 0, spawn[2] if len(spawn) > 2 else 180))
    for nm, p, rz in extra:
        K.marker(root, nm, (p[0], p[1], zf if len(p) < 3 else p[2]), (0, 0, rz))


# =========================================================================== shop_guns  "BULWARK ARMS"
NOTES["shop_guns"] = (
    "BULWARK ARMS gun shop. Footprint 12x10 (x -6..6, y -5..5), walls 0.25, interior floor 0.02, ceiling 3.2, roof "
    "3.45, parapet coping 4.0, sign box to 4.15, door canopy + bollards up to 1.1 m in front of the +Y wall. "
    "Entrance opening 1.6x2.42 at x -0.8..0.8 in the +Y wall with sliding glass leaves door_l / door_r (origin = "
    "bottom centre of each leaf; door_l slides -0.8 X, door_r +0.8 X). Storefront windows have security bars. "
    "L-shaped glass counter (long leg along X at y -2.3..-1.65, short leg along Y at x 3.9..4.55), staff zone behind "
    "it, long-gun racks on the back wall, pistol board on the +X wall, ammo shelves + armour mannequin on the -X side. "
    "Closed RANGE door in the back wall at x -3.5..-2.5 (solid in col). Gunsmith workbench on the -X wall at "
    "y -4.6..-2.4; marker `workbench` stands in front of it looking at it (-X). counter/staff face each other across "
    "the cash-wrap section of the counter (register on it).")


def build_shop_guns():
    root = K.begin_asset("shop_guns", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(23)
    X0, X1, Y0, Y1, T = -6.0, 6.0, -5.0, 5.0, 0.25
    ZF, ZC, ZR, ZP = 0.02, 3.2, 3.45, 4.0
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn = Y1 - T / 2
    EXT, TRIM, ACC = "charcoal", "steel_dark", "orange"
    DX, DH = 0.8, 2.42
    WZ0, WZ1 = 0.55, 2.65
    wins = [(-5.45, -1.35), (1.35, 5.45)]
    RD0, RD1 = -3.5, -2.5                      # closed RANGE door in the back wall

    # ---------------------------------------------------------------- shell
    C.box_shell(sh, fx, col, X0, X1, Y0, Y1, T, ZF, ZC, ZR, ZP, ext=EXT, inn="@D:concrete_light",
                floor="@D:concrete_dark", ceil="@D:gray_dark", cope="steel",
                front=[(-DX, DX, 0.0, DH)] + [(a, b, WZ0, WZ1, "glass") for a, b in wins])
    storefront_windows(sh, wins, WZ0, WZ1, yn, Y1, frame=TRIM, sill="steel", kick=TRIM)
    for a, b in wins:
        C.bars(sh, a, b, WZ0, WZ1, Y1 - 0.035, step=0.3, color="steel")
    C.door_surround(sh, -DX, DX, DH, Y1, w=0.1, proud=0.05, color=TRIM)
    C.threshold(sh, col, -DX, DX, yi1, Y1, "steel_dark", ZF, lip=0.3)
    C.sliding_doors(root, sh, 0.0, yi1, -1, ZF, 1.6, 2.4, frame=TRIM, accent=ACC)
    # corner pilasters, side ribs, plinth + accent stripe
    for sx in (-1, 1):
        xa, xb = (X0 - 0.06, X0 + 0.32) if sx < 0 else (X1 - 0.32, X1 + 0.06)
        bx(sh, (xa, Y1 - 0.32, 0.0), (xb, Y1 + 0.06, ZP + 0.1), TRIM)
    for y in (-3.4, -1.0, 1.4, 3.4):
        bx(sh, (X1, y - 0.08, 0.5), (X1 + 0.07, y + 0.08, ZP - 0.02), TRIM)
        bx(sh, (X0 - 0.07, y - 0.08, 0.5), (X0, y + 0.08, ZP - 0.02), TRIM)
    for x in (-1.2, 1.6, 4.2):
        bx(sh, (x - 0.08, Y0 - 0.07, 0.5), (x + 0.08, Y0, ZP - 0.02), TRIM)
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.5, 0.04, "concrete_dark", sides="ESW", gaps={"S": [(RD0 - 0.15, RD1 + 0.15)]})
    C.band(sh, X0, X1, Y0, Y1, 2.88, 3.0, 0.006, ACC, sides="ESW", flat=True)
    # sign box (false front) with neon lettering, shield emblems and an orange underline
    SB0, SB1, SD = 2.95, 4.18, 0.28
    yf = Y1 + SD
    bx(sh, (-5.55, Y1, SB0 + 0.05), (5.55, yf, SB1 - 0.05), "black")
    bx(sh, (-5.6, Y1, SB1 - 0.05), (5.6, yf + 0.03, SB1), "steel")
    bx(sh, (-5.6, Y1, SB0), (5.6, yf + 0.03, SB0 + 0.05), "steel")
    C.sign(sh, "BULWARK ARMS", (0.25, yf, 3.27), 8.0, 0.72, "neon_orange", depth=0.07, res=TXT_RES)
    bx(sh, (-3.9, yf, 3.1), (4.4, yf + 0.03, 3.15), "neon_orange")
    shield = [(-0.32, 0.36), (0.32, 0.36), (0.32, -0.02), (0.0, -0.38), (-0.32, -0.02)]
    chev = [(-0.24, 0.02), (0.0, -0.16), (0.24, 0.02), (0.24, 0.14), (0.0, -0.04), (-0.24, 0.14)]
    with sh.at((-4.75, yf, 3.57)):
        sh.prism(shield, 0.05, "steel", plane="XZ", pos=(0, 0.025, 0), caps=(False, True))
        sh.prism(chev, 0.03, "neon_orange", plane="XZ", pos=(0, 0.065, 0), caps=(False, True))
    # door canopy on brackets with a down light
    bx(sh, (-1.45, Y1, 2.7), (1.45, Y1 + 1.05, 2.8), TRIM)
    bx(sh, (-1.47, Y1 + 1.0, 2.64), (1.47, Y1 + 1.1, 2.82), ACC)
    bx(sh, (-0.3, Y1 + 0.45, 2.685), (0.3, Y1 + 0.65, 2.7), "emis_lamp")
    for sx in (-1, 1):
        sh.prism([(0.0, 2.7), (0.75, 2.7), (0.0, 2.25)], 0.05, TRIM, plane="YZ", pos=(sx * 1.3, Y1, 0))
    # CCTV camera at the front +X corner, bollards
    bx(sh, (5.55, Y1 + 0.06, 2.75), (5.65, Y1 + 0.25, 2.8), TRIM)
    sh.box((0.12, 0.26, 0.12), (5.6, Y1 + 0.3, 2.7), "white", rot=(-20, 0, 25))
    for x in (-4.4, -2.4, 2.4, 4.4):
        sh.cyl(0.11, 0.95, (x, Y1 + 0.75, 0.0), "steel_dark", segs=8, base=True, cap_color="black")
        sh.cyl(0.115, 0.1, (x, Y1 + 0.75, 0.7), ACC, segs=8, caps=False)
        col.box((x - 0.11, Y1 + 0.64, 0.0), (x + 0.11, Y1 + 0.86, 0.95))
    # back: closed RANGE door seen from outside, lamp; roof plant
    C.door_surround(sh, RD0, RD1, 2.2, Y0, w=0.08, proud=0.04, color=TRIM, out=-1)
    bx(sh, (RD0, Y0 - 0.025, 0.02), (RD1, Y0, 2.2), "gunmetal")
    bx(sh, (RD0 + 0.12, Y0 - 0.06, 1.0), (RD0 + 0.6, Y0 - 0.025, 1.05), "steel")
    C.wall_lamp(sh, (RD0 + RD1) * 0.5, Y0, 2.5, out=-1, color=TRIM)
    C.roof_ac(sh, col, 2.6, -1.8, ZR, 1.7, 1.15, 0.85)
    sh.cyl(0.18, 0.9, (-3.5, -2.2, ZR), "steel", segs=8, base=True, cap_color="steel_dark")
    sh.cyl(0.26, 0.08, (-3.5, -2.2, ZR + 0.95), "steel_dark", segs=8, r2=0.1)
    col.box((-3.7, -2.4, ZR), (-3.3, -2.0, ZR + 1.0))

    # ---------------------------------------------------------------- fixtures
    gaps = {"S": [(RD0 - 0.1, RD1 + 0.1)]}
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, 1.1, 0.012, "charcoal", gaps, sides="SEW")
    C.band_in(fx, xi0, xi1, yi0, yi1, 1.1, 1.18, 0.016, ACC, gaps, sides="SEW")
    if not C.OPEN_TOP:
        for y in (-0.4, 3.3):
            bx(fx, (xi0, y - 0.09, ZC - 0.26), (xi1, y + 0.09, ZC), "charcoal")
    C.ceiling_lights(root, fx, [(-3.0, 1.7), (2.2, 1.7), (-3.0, -2.4), (2.2, -2.6)], ZC, size=(1.7, 0.24), drop=0.3,
                     emis="emis_warm_always", housing="charcoal")
    F.floor_mat(fx, -1.05, 1.05, 3.55, 4.65, ZF + 0.004, "black", border=ACC)
    # L-shaped glass display counter + cash wrap with the register
    CY0, CY1 = -2.3, -1.65
    zb = F.glass_counter(fx, col, -1.3, 3.25, CY0, CY1, skip=("+x",))
    F.glass_counter(fx, col, 3.9, 4.55, CY1, 1.2, skip=("-y",))
    F.counter(fx, col, 3.25, 4.55, CY0, CY1, 1.06, body="wood_dark", top="gray_dark")
    F.register(fx, (3.9, -1.98, 1.06), 0.0)
    for i, x in enumerate((-0.95, -0.35, 0.25, 0.85, 1.45, 2.05, 2.65)):
        F.pistol(fx, (x, -2.12, zb), (0, 0, 8 - 16 * (i % 2)), ("black", "gunmetal", "steel_dark", "black")[i % 4])
        F.floor_quad(fx, x + 0.18, x + 0.26, -1.86, -1.8, zb + 0.004, "white")
    for i, y in enumerate((-1.2, -0.55, 0.1, 0.75)):
        if i % 2 == 0:
            F.pistol(fx, (4.13, y - 0.12, zb), (0, 0, 80), "black")
        else:
            fx.cyl(0.035, 0.32, (4.22, y, zb + 0.035), "black", axis="Y", segs=6)
            fx.cyl(0.05, 0.06, (4.22, y + 0.15, zb + 0.05), "black", axis="Y", segs=6)
    # back wall: storage cabinet + long-gun slatwall (staff side)
    with C.at((2.2, yi0, ZF), 0, fx, col):
        F.wall_cabinet(fx, col, 6.6, 0.5, 0.9, body="charcoal", top="wood_mid", doors=6)
    F.slatwall(fx, "X", -1.1, 5.5, 1.05, 2.95, yi0, 1, color="wood_mid", groove="wood_dark", step=0.3)
    kinds = ("rifle", "shotgun", "hunter")
    cols = ("black", "gunmetal", "wood_dark", "military_tan", "black", "olive", "black", "charcoal", "gunmetal")
    for r, z in enumerate((1.32, 1.88, 2.45)):
        for c, x in enumerate((-0.95, 0.75, 2.45, 4.15)):
            kd = kinds[(r + c) % 3]
            F.long_gun(fx, (x, yi0 + 0.06, z), (0, 0, 0), kd, cols[(r * 4 + c) % len(cols)], L=1.12 if kd != "hunter" else 1.05)
    # +X wall behind the short leg: pistol board
    F.slatwall(fx, "Y", -2.1, 1.1, 1.15, 2.45, xi1, -1, color="charcoal", groove="black", step=0.32)
    for r, z in enumerate((1.4, 1.85)):
        for c, y in enumerate((-1.75, -0.95, -0.15, 0.65)):
            F.pistol(fx, (xi1 - 0.035, y, z), (0, 0, 90), ("black", "gunmetal", "steel", "black")[(r + c) % 4], s=1.3,
                     plane="XZ")
    F.small_sign(fx, "PISTOLS", -0.45, xi1, 2.55, 1.7, 0.3, board="black", color="neon_orange", out=-1, axis="Y",
                 depth=0.06)
    # -X wall: ammo shelving, workbench, armour mannequin
    for y in (-0.95, 1.0):
        with C.at((xi0, y, ZF), -90, fx, col):
            F.steel_shelf(fx, col, 1.9, 0.45, 2.0, 4, post="charcoal", board="steel_dark",
                          stock=["olive", "military_green", "orange", "red_dark", "yellow_dark", "black", "military_tan"],
                          rng=rng, hmax=0.24, wmin=0.14, wmax=0.3, fill=0.9)
    F.small_sign(fx, "AMMO", 0.0, xi0, 2.25, 1.4, 0.32, board="black", color="neon_orange", out=1, axis="Y", depth=0.06)
    with C.at((xi0, -3.5, ZF), -90, fx, col):
        F.workbench(fx, col, w=2.2, d=0.75, top="wood_mid", frame="charcoal", board="gray_dark")
        bx(fx, (-0.55, 0.48, 0.921), (0.55, 0.72, 0.925), "green_dark")
        F.long_gun(fx, (-0.48, 0.6, 0.925 + 0.02), (90, 0, 0), "hunter", "wood_mid", L=0.95)
        F.desk_lamp(fx, (0.85, 0.15, 0.92), 45, "black", ACC)
    F.mannequin(fx, col, (-4.45, 3.35, ZF), -25, skin="plastic_gray", torso="black", vest=("olive", "military_tan"))
    # vitrine with long guns in the front +X corner
    with C.at((xi1, 3.15, ZF), 90, fx, col):
        z0 = F.vitrine(fx, col, w=1.6, d=0.5, h=2.1, body="black", back="maroon")
        for i, x in enumerate((-0.5, 0.0, 0.5)):
            F.long_gun(fx, (x, 0.25, z0 + 0.06), (0, -90, 0), kinds[i], ("black", "wood_mid", "gunmetal")[i], L=1.05)
    # back wall customer side: RANGE door, target poster
    bx(fx, (RD0 - 0.08, yi0, ZF), (RD1 + 0.08, yi0 + 0.04, 2.3), "charcoal")
    bx(fx, (RD0, yi0 + 0.02, ZF), (RD1, yi0 + 0.05, 2.2), "gunmetal")
    bx(fx, (RD0 + 0.1, yi0 + 0.05, 1.0), (RD1 - 0.1, yi0 + 0.1, 1.07), "steel")
    F.small_sign(fx, "RANGE", (RD0 + RD1) * 0.5, yi0, 2.38, 0.9, 0.32, board="black", color="neon_red", out=1,
                 axis="X", depth=0.07)
    F.target_poster(fx, "X", -4.85, -3.85, 1.35, 2.55, yi0, 1)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(X0 - 2, X1 + 2, Y0 - 2, Y1 + 2))
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    col.to_object(root)
    entrance_marks(root, 0.0, Y1, ZF, spawn=(0.4, 1.4, 180),
                   extra=[("counter", (3.4, -1.0), 180), ("staff", (3.6, -3.05), 0), ("workbench", (-4.4, -3.5), 90)])
    return root


# =========================================================================== safehouse  "The Hideout"
NOTES["safehouse"] = (
    "The Hideout beach bungalow. Origin = ground centre of the HOUSE (house x -6..6, y -4.5..4.5); the 6x7 garage is "
    "attached on -X (x -12..-6, y -2.5..4.5, front flush with the house front), so garage_spot / garage_out sit at "
    "x -8.875 (matches the stand-in's x -9). House on a 0.45 plinth: interior floor z 0.45 (no step at the door: "
    "porch deck 0.45, two 0.15 steps down to the ground in front of the porch, col = sloped prism), ceiling 3.2, "
    "low hip roof (tint_b) eave 3.55 / ridge 4.8; walls tint_a (recolourable); garage floor 0.02, flat roof 2.97. "
    "Part `door` = front door leaf (opening x -1.5..-0.5, z 0.45..2.6), origin on the hinge line (-1.49, 4.295, 0.45): "
    "rotate about Z, it swings into the house (negative yaw = toward -Y). Part `garage_door` = roll door (opening "
    "x -10.375..-7.375, z 0..2.4), origin at the centre of its TOP edge: scale Z toward the origin (roll-up) - do not "
    "slide it (it would poke through the garage roof). `entrance` stands on the porch deck 1.5 m in front of the door "
    "(z 0.45). bed / wardrobe / save stand on the floor facing the furniture; save = the desk chair spot.")


def build_safehouse():
    root = K.begin_asset("safehouse", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(5)
    X0, X1, Y0, Y1, T = -6.0, 6.0, -4.5, 4.5, 0.25
    ZF, ZC, ZR = 0.45, 3.2, 3.4
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn, ys, xe, xw = Y1 - T / 2, Y0 + T / 2, X1 - T / 2, X0 + T / 2
    EXT, TRIM, INN = "tint_a", "white", "@D:wall_interior"
    GIN = "@D:concrete_light"
    GX0, GX1, GY0, GY1, GZ = -12.0, -6.0, -2.5, 4.5, 2.75
    gxc = (GX0 + T + GX1) * 0.5                 # garage interior centre x (-8.875)
    DR0, DR1, DZ = -1.5, -0.5, 2.6              # front door opening
    GD0, GD1, GDZ = gxc - 1.5, gxc + 1.5, 2.4   # garage door opening
    WF = [(-5.0, -2.6), (2.8, 4.8)]             # front windows
    WZ0, WZ1 = 1.3, 2.55
    KW = (-4.75, -3.75)                         # kitchen window (back wall)
    BW = (3.4, 4.8)                             # bedroom back window
    RW = (0.9, 2.5)                             # bedroom side window (+X wall)
    LW = (-3.45, -2.75)                         # small window in the exposed part of the -X wall

    # ---------------------------------------------------------------- house shell
    C.wall(sh, col, "X", X0, X1, yn, 0.0, ZR, EXT, INN, 1, T,
           [(DR0, DR1, ZF, DZ)] + [(a, b, WZ0, WZ1, "glass") for a, b in WF])
    C.wall(sh, col, "X", X0, X1, ys, 0.0, ZR, EXT, INN, -1, T,
           [(KW[0], KW[1], 1.55, 2.45, "glass"), (BW[0], BW[1], 1.4, 2.5, "glass")])
    C.wall(sh, col, "Y", yi0, yi1, xe, 0.0, ZR, EXT, INN, 1, T, [(RW[0], RW[1], WZ0, WZ1, "glass")])
    C.wall(sh, col, "Y", yi0, GY0, xw, 0.0, ZR, EXT, INN, -1, T, [(LW[0], LW[1], 1.5, 2.4, "glass")])
    C.wall(sh, col, "Y", GY0, yi1, xw, 0.0, GZ, GIN, INN, -1, T)
    C.wall(sh, col, "Y", GY0, yi1, xw, GZ, ZR, EXT, INN, -1, T)
    C.floor_slab(fx, col, X0, X1, Y0, Y1, "@D:floor_wood", ZF, T)
    C.flat_roof(sh, col, X0, X1, Y0, Y1, ZC, ZR, "@D:ceiling", "roof_dark", T)
    if not C.OPEN_TOP:
        C.hip_roof(sh, -6.45, 6.6, -5.1, 5.1, 3.55, 1.25, "tint_b", fascia=TRIM, soffit=TRIM)
    col.box((-6.45, -5.1, ZR), (6.6, 5.1, 3.55))
    col.hip(-6.45, 6.6, -5.1, 5.1, 3.55, 1.25)
    # windows: white frames, sills, flower box
    for a, b in WF:
        C.glazing(sh, "X", a, b, WZ0, WZ1, yn, frame=TRIM, every=1.2, fw=0.07, fd=0.12, out=1, hbars=(2.05,))
        bx(sh, (a - 0.08, Y1, WZ0 - 0.07), (b + 0.08, Y1 + 0.08, WZ0), TRIM)
    for a, b, z0, z1 in ((KW[0], KW[1], 1.55, 2.45), (BW[0], BW[1], 1.4, 2.5)):
        C.glazing(sh, "X", a, b, z0, z1, ys, frame=TRIM, every=1.2, fw=0.07, fd=0.12, out=-1)
        bx(sh, (a - 0.08, Y0 - 0.08, z0 - 0.07), (b + 0.08, Y0, z0), TRIM)
    C.glazing(sh, "Y", RW[0], RW[1], WZ0, WZ1, xe, frame=TRIM, every=1.2, fw=0.07, fd=0.12, out=1, hbars=(2.05,))
    bx(sh, (X1, RW[0] - 0.08, WZ0 - 0.07), (X1 + 0.08, RW[1] + 0.08, WZ0), TRIM)
    C.glazing(sh, "Y", LW[0], LW[1], 1.5, 2.4, xw, frame=TRIM, every=1.2, fw=0.07, fd=0.12, out=-1)
    bx(sh, (X0 - 0.08, LW[0] - 0.08, 1.43), (X0, LW[1] + 0.08, 1.5), TRIM)
    bx(sh, (-4.9, Y1, 0.98), (-2.7, Y1 + 0.28, 1.2), "wood_mid")
    for i in range(4):
        sh.ico(0.2, (-4.6 + i * 0.55, Y1 + 0.15, 1.26), "leaf_green" if i % 2 else "leaf_dark", subdiv=1, jitter=0.2,
               seed=i + 3, scale=(1.3, 0.8, 0.8))
        sh.ico(0.07, (-4.45 + i * 0.55, Y1 + 0.22, 1.36), ("flower_red", "flower_yellow", "coral_pink", "flower_white")[i],
               subdiv=0)
    # plinth, corner trims, downpipes
    C.band(sh, X0, X1, Y0, Y1, 0.0, ZF, 0.03, "stucco_sand", sides="NSEW", gaps={"W": [(GY0, Y1 + 1.0)]})
    for (x, y) in ((X1, Y1), (X1, Y0), (X0, Y0)):
        sx, sy = (1 if x > 0 else -1), (1 if y > 0 else -1)
        bx(sh, (min(x, x + sx * 0.06) - (0.1 if sx > 0 else 0.0), min(y, y + sy * 0.06) - (0.1 if sy > 0 else 0.0), ZF),
           (max(x, x + sx * 0.06) + (0.0 if sx > 0 else 0.1), max(y, y + sy * 0.06) + (0.0 if sy > 0 else 0.1), ZR), TRIM)
    for x in (5.6, -5.6):
        sh.cyl(0.05, ZR + 0.05, (x, Y0 - 0.1, 0.0), "white", segs=6, base=True)

    # front door: surround, sill, hinged leaf `door`
    C.door_surround(sh, DR0, DR1, DZ, Y1, w=0.1, proud=0.04, color=TRIM, z0=ZF)
    sh.quad((DR0, yi1, ZF + 0.004), (DR1, yi1, ZF + 0.004), (DR1, Y1 + 0.04, ZF + 0.004), (DR0, Y1 + 0.04, ZF + 0.004),
            "wood_dark")
    dm = K.MB()
    lx0, lx1, ly0, ly1, lz0, lz1 = DR0 + 0.01, DR1 - 0.01, 4.27, 4.32, ZF + 0.01, DZ - 0.02
    wz0, wz1 = ZF + 1.3, lz1 - 0.16
    bx(dm, (lx0, ly0, lz0), (lx1, ly1, wz0), "stucco_coral")
    bx(dm, (lx0, ly0, wz1), (lx1, ly1, lz1), "stucco_coral")
    bx(dm, (lx0, ly0, wz0), (lx0 + 0.17, ly1, wz1), "stucco_coral")
    bx(dm, (lx1 - 0.17, ly0, wz0), (lx1, ly1, wz1), "stucco_coral")
    C.pane(dm, "X", lx0 + 0.17, lx1 - 0.17, wz0, wz1, (ly0 + ly1) * 0.5, "@Glass", 1)
    for yy, o in ((ly1, 1), (ly0, -1)):
        for (za, zb_) in ((lz0 + 0.15, lz0 + 0.62), (lz0 + 0.74, wz0 - 0.12)):
            C.pane(dm, "X", lx0 + 0.13, lx1 - 0.13, za, zb_, yy + o * 0.004, "coral_orange", o)
    for yy, o in ((ly1, 1), (ly0, -1)):
        bx(dm, (lx1 - 0.13, min(yy, yy + o * 0.06), 1.36), (lx1 - 0.08, max(yy, yy + o * 0.06), 1.42), "brass")
    dm.to_object(root, "door", origin=(lx0, (ly0 + ly1) * 0.5, ZF))

    # porch: deck, steps, railings, posts, lean-to roof, lamp
    PX0, PX1, PY1 = -3.2, 1.2, 6.3
    SX0, SX1 = -1.75, -0.25
    bx(sh, (PX0, Y1, 0.0), (PX1, PY1, ZF), TRIM, colors={"+z": "wood_mid"})
    for k in range(1, 6):
        y = Y1 + k * 0.3
        sh.quad((PX0 + 0.02, y - 0.006, ZF + 0.003), (PX1 - 0.02, y - 0.006, ZF + 0.003),
                (PX1 - 0.02, y + 0.006, ZF + 0.003), (PX0 + 0.02, y + 0.006, ZF + 0.003), "wood_dark")
    col.box((PX0, Y1, 0.0), (PX1, PY1, ZF))
    for i, (ya, yb) in enumerate(((PY1, PY1 + 0.3), (PY1 + 0.3, PY1 + 0.6))):
        bx(sh, (SX0, ya, 0.0), (SX1, yb, ZF - 0.15 * (i + 1)), TRIM, colors={"+z": "wood_mid"})
    col.slope_y(PY1, ZF, PY1 + 0.65, 0.0, SX0, SX1, thick=ZF)
    posts = [(PX0 + 0.05, PY1 - 0.05), (SX0 - 0.05, PY1 - 0.05), (SX1 + 0.05, PY1 - 0.05), (PX1 - 0.05, PY1 - 0.05)]
    for (x, y) in posts:
        bx(sh, (x - 0.06, y - 0.06, ZF), (x + 0.06, y + 0.06, 2.86), TRIM)
        col.box((x - 0.06, y - 0.06, ZF), (x + 0.06, y + 0.06, 2.86))
    for (x, y) in ((PX0 + 0.05, Y1 + 0.08), (PX1 - 0.05, Y1 + 0.08)):
        bx(sh, (x - 0.05, y - 0.05, ZF), (x + 0.05, y + 0.05, ZF + 0.95), TRIM)
    rails = [((PX0 + 0.05, PY1 - 0.05), (SX0 - 0.05, PY1 - 0.05)), ((SX1 + 0.05, PY1 - 0.05), (PX1 - 0.05, PY1 - 0.05)),
             ((PX0 + 0.05, Y1 + 0.08), (PX0 + 0.05, PY1 - 0.05)), ((PX1 - 0.05, Y1 + 0.08), (PX1 - 0.05, PY1 - 0.05))]
    for (a, b) in rails:
        xa, xb = min(a[0], b[0]) - 0.035, max(a[0], b[0]) + 0.035
        ya, yb = min(a[1], b[1]) - 0.035, max(a[1], b[1]) + 0.035
        bx(sh, (xa, ya, ZF + 0.88), (xb, yb, ZF + 0.95), TRIM)
        bx(sh, (xa + 0.01, ya + 0.01, ZF + 0.12), (xb - 0.01, yb - 0.01, ZF + 0.17), TRIM)
        n = max(1, int(round(max(xb - xa, yb - ya) / 0.16)))
        for k in range(1, n):
            t = k / n
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            bx(sh, (x - 0.018, y - 0.018, ZF + 0.17), (x + 0.018, y + 0.018, ZF + 0.88), TRIM)
        col.box((xa, ya, ZF), (xb, yb, ZF + 0.95))
    sh.prism([(Y1, 3.3), (PY1 + 0.25, 2.86), (PY1 + 0.25, 2.76), (Y1, 3.2)], PX1 - PX0 + 0.4, "tint_b", plane="YZ",
             pos=((PX0 + PX1) * 0.5, 0, 0), side_colors=["tint_b", TRIM, TRIM, TRIM], cap_colors=(TRIM, TRIM))
    col.slope_y(Y1, 3.3, PY1 + 0.25, 2.86, PX0 - 0.2, PX1 + 0.2, thick=0.1)
    C.disc(sh, ((DR0 + DR1) * 0.5, 5.35, 2.955), 0.15, "emis_lamp", axis="Z", segs=8, out=-1)
    sh.cyl(0.19, 0.08, ((DR0 + DR1) * 0.5, 5.35, 2.96), TRIM, segs=8, base=True, smooth=False)
    F.plant(sh, col, (PX1 - 0.45, Y1 + 0.45, ZF), h=1.1, pot="terracotta", seed=4)
    sh.quad((-1.4, Y1 + 0.3, ZF + 0.004), (-0.6, Y1 + 0.3, ZF + 0.004), (-0.6, Y1 + 0.85, ZF + 0.004),
            (-1.4, Y1 + 0.85, ZF + 0.004), "rope")
    bx(sh, (-0.3, Y1, 1.75), (-0.06, Y1 + 0.02, 1.95), "navy")                      # house number plate

    # ---------------------------------------------------------------- garage shell
    C.wall(sh, col, "X", GX0, GX1, yn, 0.0, GZ, EXT, GIN, 1, T, [(GD0, GD1, 0.0, GDZ)])
    C.wall(sh, col, "X", GX0, GX1, GY0 + T / 2, 0.0, GZ, EXT, GIN, -1, T)
    C.wall(sh, col, "Y", GY0 + T, yi1, GX0 + T / 2, 0.0, GZ, EXT, GIN, -1, T)
    F.floor_quad(fx, GX0 + T, GX1, GY0 + T, yi1, 0.02, "concrete")
    col.box((GX0, GY0, 0.0), (GX1, GY1, 0.02))
    C.threshold(sh, col, GD0, GD1, yi1, Y1, "concrete_dark", 0.02, lip=0.25)
    if not C.OPEN_TOP:
        bx(sh, (GX0 - 0.35, GY0 - 0.35, GZ), (GX1, GY1 + 0.35, GZ + 0.22), "tint_b", colors={"-z": TRIM})
    col.box((GX0 - 0.35, GY0 - 0.35, GZ), (GX1, GY1 + 0.35, GZ + 0.22))
    C.band(sh, GX0, GX1 - 0.06, GY0, GY1, 0.0, 0.3, 0.03, "stucco_sand", sides="NSW", gaps={"N": [(GD0 - 0.12, GD1 + 0.12)]})
    C.door_surround(sh, GD0, GD1, GDZ, Y1, w=0.12, proud=0.04, color=TRIM)
    C.wall_lamp(sh, GD1 + 0.55, Y1, 2.35, out=1, color="charcoal")
    C.roll_door(root, "garage_door", GD0, GD1, yn, 0.0, GDZ, color="tint_b", bar="gray_mid", slat=0.25)

    # ---------------------------------------------------------------- interior fixtures
    # partition with a doorway into the bedroom
    PXc, PT = 1.0, 0.12
    C.wall(fx, col, "Y", yi0, yi1, PXc, ZF, ZC, "wall_interior", "wall_interior", 1, PT, [(0.3, 1.5, ZF, ZF + 2.15)])
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, ZF + 0.1, 0.01, "white",
              {"N": [(DR0 - 0.12, DR1 + 0.12)]}, sides="NSEW")
    C.ceiling_lights(root, fx, [(-3.0, 0.3), (3.4, 0.6)], ZC, size=(0.55, 0.55), emis="emis_warm_always",
                     housing="white")
    # living room
    with C.at((xi0, 1.9, ZF), -90, fx, col):
        F.tv_unit(fx, col)
    F.rug(fx, -5.0, -3.0, 0.85, 2.95, ZF + 0.004, "fabric_blue", "cream")
    F.coffee_table(fx, col, (-4.0, 1.9, ZF), w=0.6, d=1.0)
    with C.at((-1.9, 1.9, ZF), 90, fx, col):
        F.sofa(fx, col, 2.0, 0.9, "stucco_teal", cushion="turquoise")
    F.floor_lamp(fx, col, (-2.2, 3.3, ZF))
    F.plant(fx, col, (-5.35, 3.85, ZF), h=1.3, seed=7)
    F.layered_art(fx, "X", -1.75, -0.35, 1.75, 2.6, yi0, 1,
                  [(0.0, 1.0, 0.0, 0.45, "sky_blue"), (0.0, 1.0, 0.0, 0.18, "sand"), (0.62, 0.8, 0.55, 0.85, "yellow")],
                  frame="wood_dark", back="ice_blue")
    # kitchenette + dining
    KC = -3.85
    with C.at((KC, yi0, ZF), 0, fx, col):
        F.kitchenette(fx, col, w=3.8, window=(KW[0] - KC, KW[1] - KC), upper_body="stucco_mint")
    F.floor_quad(fx, -5.75, -1.95, -4.25 + 0.6, -2.9, ZF + 0.003, "tile_white")
    F.table_round(fx, col, (-3.5, -2.0, ZF), r=0.45)
    F.chair(fx, (-4.15, -2.0, ZF), -90)
    F.chair(fx, (-2.85, -2.0, ZF), 90)
    # bedroom
    with C.at((xi1, -1.8, ZF), 90, fx, col):
        F.bed(fx, col, blanket="stucco_teal")
    with C.at((xi1, -3.05, ZF), 90, fx, col):
        F.nightstand(fx, col)
    with C.at((2.15, yi0, ZF), 0, fx, col):
        F.wardrobe(fx, col, body="white", trim="wood_mid")
    with C.at((4.0, yi1, ZF), 180, fx, col):
        F.desk(fx, col, w=1.4, d=0.62)
    F.laptop(fx, (4.0, 3.92, ZF + 0.75), 0)
    F.office_chair(fx, (4.0, 3.1, ZF), 0, "fabric_dark")
    F.rug(fx, 2.0, 3.4, -2.3, -0.5, ZF + 0.004, "cream", "wood_light")
    F.layered_art(fx, "Y", -2.6, -1.0, 1.8, 2.5, PXc + PT / 2, 1,
                  [(0.0, 1.0, 0.55, 1.0, "coral_orange"), (0.0, 1.0, 0.0, 0.55, "navy"), (0.4, 0.6, 0.45, 0.75, "yellow")],
                  frame="black", back="white")
    # garage: shelf, tyres, bumper, oil stain, roll-box, light
    with C.at((GX0 + T, 0.4, 0.02), -90, fx, col):
        F.steel_shelf(fx, col, 2.2, 0.45, 1.9, 4, stock=["cardboard", "cardboard", "tan", "red", "blue_dark", "gray_mid",
                                                        "yellow_dark"], rng=rng, wmin=0.3, wmax=0.6, fill=0.8)
    F.tyre_stack(fx, col, (GX0 + T + 0.4, GY0 + T + 0.45, 0.02), n=3)
    bx(fx, (gxc - 1.2, GY0 + T, 0.25), (gxc + 1.2, GY0 + T + 0.08, 0.45), "rubber")
    F.floor_quad(fx, gxc - 1.3, gxc + 1.3, GY0 + T + 0.6, GY0 + T + 0.7, 0.026, "line_yellow")
    F.floor_quad(fx, gxc - 0.45, gxc + 0.35, 0.2, 0.9, 0.025, "concrete_dark")
    bx(fx, (GD0 - 0.15, yi1 - 0.32, GDZ + 0.02), (GD1 + 0.15, yi1, GZ), "steel_dark")
    C.ceiling_lights(root, fx, [(gxc, 0.6)], GZ, size=(1.2, 0.2), emis="emis_cool_always", housing="steel_dark",
                     first=3)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(-13, 7, -6, 8))
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC) +
                  C.room_occluders(GX0 + T, GX1, GY0 + T, yi1, 0.02, GZ))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    col.to_object(root)
    K.marker(root, "entrance", ((DR0 + DR1) * 0.5, Y1 + 1.5, ZF), (0, 0, 180))
    K.marker(root, "spawn", (-0.95, 2.4, ZF), (0, 0, 180))
    K.marker(root, "bed", (4.45, -3.05, ZF), (0, 0, 0))
    K.marker(root, "wardrobe", (2.15, -3.05, ZF), (0, 0, 180))
    K.marker(root, "save", (4.0, 3.1, ZF), (0, 0, 0))
    K.marker(root, "garage_spot", (gxc, 1.0, 0.02), (0, 0, 0))
    K.marker(root, "garage_out", (gxc, Y1 + 7.0, 0.0), (0, 0, 0))
    return root


# =========================================================================== shared: striped awning
def striped_awning(sh, x0, x1, y_wall, z_top, depth, drop, val=0.22, colors=("turquoise", "white"), stripe=0.55,
                   under="white", arm="steel"):
    """Fabric awning on a wall facing +Y: sloped striped top from (y_wall, z_top) to (y_wall + depth, z_top - drop)
    plus a striped valance; plain underside; side cheeks; two diagonal arms."""
    n = max(2, int(round((x1 - x0) / stripe)))
    yf, zf = y_wall + depth, z_top - drop
    for i in range(n):
        a = x0 + (x1 - x0) * i / n
        b = x0 + (x1 - x0) * (i + 1) / n
        c = colors[i % len(colors)]
        C.poly_up(sh, [(b, y_wall, z_top), (a, y_wall, z_top), (a, yf, zf), (b, yf, zf)], c, up=(0, 0.3, 1))
        C.poly_up(sh, [(a, yf, zf), (a, yf, zf - val), (b, yf, zf - val), (b, yf, zf)], c, up=(0, 1, 0))
    C.poly_up(sh, [(x0, y_wall, z_top - 0.01), (x1, y_wall, z_top - 0.01), (x1, yf - 0.01, zf - 0.01),
                   (x0, yf - 0.01, zf - 0.01)], under, up=(0, -0.3, -1))
    C.poly_up(sh, [(x1, yf - 0.01, zf), (x1, yf - 0.01, zf - val), (x0, yf - 0.01, zf - val), (x0, yf - 0.01, zf)], under,
              up=(0, -1, 0))
    for x, o in ((x0, -1), (x1, 1)):
        pts = [(x, y_wall, z_top), (x, yf, zf), (x, yf, zf - val)]
        C.poly_up(sh, pts, colors[0], up=(o, 0, 0))
    for x in (x0 + 0.15, x1 - 0.15):
        dy, dz = depth, (z_top - 0.55) - (zf - 0.02)
        ln = math.hypot(dy, dz)
        ang = math.degrees(math.atan2(dz, dy))
        sh.box((0.035, ln, 0.035), (x, y_wall + dy * 0.5, (z_top - 0.55 + zf - 0.02) * 0.5), arm, rot=(-ang, 0, 0))


def planter(sh, col, pos, r=0.3, h=0.55, pot="white", leaf="leaf_green", seed=1):
    x, y, z = pos
    sh.cyl(r, h, (x, y, z), pot, segs=8, base=True, cap_color="dirt", smooth=False)
    sh.ico(r * 1.05, (x, y, z + h + r * 0.75), leaf, subdiv=1, jitter=0.12, seed=seed)
    if col is not None:
        col.box((x - r, y - r, z), (x + r, y + r, z + h))


# =========================================================================== shop_clothes  "THREADLINE"
NOTES["shop_clothes"] = (
    "THREADLINE clothing store. Footprint 12x10 (x -6..6, y -5..5), walls 0.25, floor 0.02, ceiling 3.2, roof 3.45, "
    "parapet 4.0. Striped awning over the whole storefront (y 5..6.1, lowest edge z 2.33) + two planters at the door "
    "(y 5.4). Entrance 1.6x2.42 at x -0.8..0.8 with door_l / door_r (slide 0.8 along -X / +X). Window displays with "
    "the two torso mannequins, garment racks, folded-stack shelves on the -X wall, shoe wall on the +X wall, counter + "
    "register in the back +X corner (navy feature wall with a neon sign), two fitting booths with curtains in the back "
    "-X corner; marker `wardrobe` stands in front of them facing -Y.")


def build_shop_clothes():
    root = K.begin_asset("shop_clothes", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(31)
    X0, X1, Y0, Y1, T = -6.0, 6.0, -5.0, 5.0, 0.25
    ZF, ZC, ZR, ZP = 0.02, 3.2, 3.45, 4.0
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn = Y1 - T / 2
    EXT, ACC, SIGN = "white", "turquoise", "navy"
    DX, DH = 0.8, 2.42
    WZ0, WZ1 = 0.35, 2.75
    wins = [(-5.4, -1.3), (1.3, 5.4)]

    # ---------------------------------------------------------------- shell
    C.box_shell(sh, fx, col, X0, X1, Y0, Y1, T, ZF, ZC, ZR, ZP, ext=EXT, inn="@D:white", floor="@D:wood_light",
                ceil="@D:ceiling", cope="gray_light",
                front=[(-DX, DX, 0.0, DH)] + [(a, b, WZ0, WZ1, "glass") for a, b in wins])
    storefront_windows(sh, wins, WZ0, WZ1, yn, Y1, frame="black", sill="gray_light", every=2.05, fw=0.05)
    C.door_surround(sh, -DX, DX, DH, Y1, w=0.08, proud=0.04, color="black")
    C.threshold(sh, col, -DX, DX, yi1, Y1, "gray_dark", ZF, lip=0.3)
    C.sliding_doors(root, sh, 0.0, yi1, -1, ZF, 1.6, 2.4, frame="black", accent=ACC)
    # turquoise portal posts, plinth, side accent band
    for sx in (-1, 1):
        xa, xb = (X0 - 0.12, X0 + 0.55) if sx < 0 else (X1 - 0.55, X1 + 0.12)
        bx(sh, (xa, Y1 - 0.3, 0.0), (xb, Y1 + 0.14, ZP + 0.12), ACC)
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.3, 0.03, "gray_light", sides="ESW")
    C.band(sh, X0, X1, Y0, Y1, 3.05, 3.25, 0.006, ACC, sides="ESW", flat=True)
    # sign band with neon lettering + neon frame, striped awning, planters
    yf = Y1 + 0.2
    bx(sh, (-5.4, Y1, 3.08), (5.4, yf, 3.98), SIGN)
    C.sign(sh, "THREADLINE", (0.0, yf, 3.53), 7.4, 0.58, "neon_cyan", depth=0.07, res=TXT_RES, valign="center")
    C.neon_path(sh, [(-5.25, 3.16), (5.25, 3.16), (5.25, 3.9), (-5.25, 3.9), (-5.25, 3.16)], yf, w=0.04, d=0.03,
                color="neon_cyan")
    striped_awning(sh, -5.35, 5.35, Y1, 3.02, 1.1, 0.45, val=0.24, colors=(ACC, "white"))
    planter(sh, col, (-1.4, Y1 + 0.4, 0.0), r=0.28, h=0.55, pot="white", seed=3)
    planter(sh, col, (1.4, Y1 + 0.4, 0.0), r=0.28, h=0.55, pot="white", seed=5)
    # back + roof details
    C.door_surround(sh, 3.0, 4.0, 2.15, Y0, w=0.08, proud=0.04, color="gray_mid", out=-1)
    bx(sh, (3.0, Y0 - 0.025, 0.02), (4.0, Y0, 2.15), "gray_light")
    C.wall_lamp(sh, 3.5, Y0, 2.45, out=-1, color="gray_dark")
    C.roof_ac(sh, col, -2.5, -2.0, ZR, 1.7, 1.15, 0.85)
    C.roof_ac(sh, col, 1.5, -2.6, ZR, 1.2, 0.9, 0.7, rz=90)

    # ---------------------------------------------------------------- fixtures
    C.ceiling_lights(root, fx, [(-3.0, 1.6), (3.0, 1.6), (-3.0, -2.0), (3.0, -2.0)], ZC, size=(0.6, 0.6),
                     emis="emis_warm_always", housing="white")
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, 0.12, 0.01, "gray_light", sides="SEW")
    # window displays with the two mannequins
    for sx, outfit in ((-1, dict(torso="magenta", collar="black", legs="black")),
                       (1, dict(torso="denim", collar="white", legs="khaki"))):
        xa, xb = (wins[0] if sx < 0 else wins[1])
        bx(fx, (xa - 0.05, yi1 - 0.9, ZF), (xb + 0.05, yi1, 0.28), "white", colors={"+z": "gray_light"})
        col.box((xa - 0.05, yi1 - 0.9, 0.0), (xb + 0.05, yi1, 0.28))
        F.mannequin(fx, col, ((xa + xb) * 0.5 + sx * 0.6, yi1 - 0.45, 0.28), sx * -15, skin="plastic_white", **outfit)
        F.pouf(fx, None, ((xa + xb) * 0.5 - sx * 0.9, yi1 - 0.45, 0.28), r=0.22, h=0.3, color="coral_pink")
    # garment racks + display table
    with C.at((-2.7, 0.9, ZF), 0, fx, col):
        F.garment_rack(fx, col, 2.4, rng=rng)
    with C.at((2.7, 0.9, ZF), 0, fx, col):
        F.garment_rack(fx, col, 2.4, rng=rng)
    F.display_table(fx, col, (0.0, -0.7, ZF), rng=rng)
    # -X wall: folded stacks + standing mirror; +X wall: shoe wall
    for y in (-1.45, 0.45):
        with C.at((xi0, y, ZF), -90, fx, col):
            F.fold_shelf(fx, col, 1.8, rng=rng)
    F.standing_mirror(fx, col, (xi0 + 0.25, 2.55, ZF), -90)
    for y in (-0.75, 1.35):
        with C.at((xi1, y, ZF), 90, fx, col):
            F.shoe_wall(fx, col, 2.0, rng=rng)
    F.pouf(fx, col, (4.7, 0.3, ZF), r=0.3, h=0.42, color="turquoise")
    # counter + register, navy feature wall with neon sign, bag shelf
    F.counter(fx, col, 1.6, 4.4, -3.3, -2.7, 1.05, body="white", top="wood_light")
    bx(fx, (1.6, -2.71, 0.1), (4.4, -2.69, 0.98), ACC)
    F.register(fx, (3.6, -3.0, 1.05), 0.0)
    for i, c in enumerate(("turquoise", "white", "coral_pink")):
        C.obox(fx, (1.85 + i * 0.28, -3.15, 1.05), (2.1 + i * 0.28, -2.95, 1.35 - i * 0.05), c, "+x-x+y-y+z")
    C.pane(fx, "X", 1.0, xi1, ZF, ZC, yi0 + 0.008, SIGN, 1)
    C.sign(fx, "THREADLINE", (3.4, yi0 + 0.01, 2.42), 3.3, 0.42, "neon_cyan", depth=0.03, res=1, valign="center")
    with C.at((3.4, yi0, ZF), 0, fx, col):
        F.wall_cabinet(fx, col, 3.4, 0.4, 0.95, body="white", top="wood_light", doors=4)
        for i, c in enumerate(("white", "turquoise", "coral_pink", "white", "navy")):
            C.obox(fx, (-1.5 + i * 0.6, 0.06, 0.95), (-1.05 + i * 0.6, 0.34, 1.25 + (i % 2) * 0.12), c, "+x-x+y+z")
    # fitting booths in the back -X corner, waiting pouf, poster
    F.fitting_booths(fx, col, xi0, -2.75, yi0, -3.25, z=ZF, n=2, curtain=ACC)
    F.pouf(fx, col, (-1.9, -2.6, ZF), r=0.28, h=0.42, color="yellow")
    F.layered_art(fx, "X", -2.3, -0.6, 1.0, 2.4, yi0, 1,
                  [(0.0, 1.0, 0.0, 1.0, "coral_pink"), (0.2, 0.8, 0.12, 0.88, "white"), (0.3, 0.7, 0.2, 0.62, "turquoise"),
                   (0.38, 0.62, 0.66, 0.8, "navy")], frame="white", back="white")
    F.plant(fx, col, (-0.45, -4.3, ZF), h=1.4, pot="white", seed=9)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(X0 - 2, X1 + 2, Y0 - 2, Y1 + 2))
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    col.to_object(root)
    entrance_marks(root, 0.0, Y1, ZF, spawn=(0.0, 2.6, 180),
                   extra=[("counter", (3.0, -2.05), 180), ("staff", (3.0, -3.95), 0), ("wardrobe", (-4.25, -2.55), 180)])
    return root


# =========================================================================== shop_market  "QUIKNOOK 24"
NOTES["shop_market"] = (
    "QUIKNOOK 24 convenience store. Footprint 12x10 (x -6..6, y -5..5), walls 0.25, floor 0.02, ceiling 3.2, roof "
    "3.45, parapet 4.0; front canopy to y 6.45 on two posts at x +-5.5 (fascia sign 2.7..3.7), ice chest + bin "
    "under it. Entrance 1.6x2.42 at x 1.4..3.0 (door_l slides -X, door_r +X). Three gondolas along Y (x -3.55, "
    "-1.35, 0.85) + -X wall shelving = three shelf aisles 1.3 wide, lit drinks coolers along the back wall "
    "(x -5.6..1.0), counter along Y at x 3.8..4.4 (staff behind it on the +X side), chips rack at its front end, "
    "ATM against the -X wall near the front. Marker `register` = the cash register itself ON the counter top "
    "(z 1.05), its +Y looks at the customer (-X); `counter` = customer spot in front of it, `staff` behind it.")


def build_shop_market():
    root = K.begin_asset("shop_market", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(41)
    X0, X1, Y0, Y1, T = -6.0, 6.0, -5.0, 5.0, 0.25
    ZF, ZC, ZR, ZP = 0.02, 3.2, 3.45, 4.0
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn = Y1 - T / 2
    EXT, ACC, DARK = "white", "green", "green_dark"
    DC, DX, DH = 2.2, 0.8, 2.42
    WZ0, WZ1 = 0.5, 2.6
    wins = [(-5.45, 0.95), (3.45, 5.45)]

    # ---------------------------------------------------------------- shell
    C.box_shell(sh, fx, col, X0, X1, Y0, Y1, T, ZF, ZC, ZR, ZP, ext=EXT, inn="@D:white", floor="@D:tile_white",
                ceil="@D:ceiling", cope="gray_light",
                front=[(DC - DX, DC + DX, 0.0, DH)] + [(a, b, WZ0, WZ1, "glass") for a, b in wins],
                back=[(2.0, 3.0, 0.0, 2.15, "door")])
    storefront_windows(sh, wins, WZ0, WZ1, yn, Y1, frame="gray_dark", sill="gray_light", kick="gray_dark", every=1.6,
                       fw=0.06)
    C.door_surround(sh, DC - DX, DC + DX, DH, Y1, w=0.08, proud=0.04, color="gray_dark")
    C.threshold(sh, col, DC - DX, DC + DX, yi1, Y1, "gray_dark", ZF, lip=0.3)
    C.sliding_doors(root, sh, DC, yi1, -1, ZF, 1.6, 2.4, frame="gray_dark", accent=ACC)
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.4, 0.03, "gray_mid", sides="ESW", gaps={"S": [(1.9, 3.1)]})
    C.band(sh, X0, X1, Y0, Y1, 2.95, 3.25, 0.006, ACC, sides="ESW", flat=True)
    C.band(sh, X0, X1, Y0, Y1, 3.25, 3.32, 0.006, "white", sides="ESW", flat=True)
    # canopy + fascia sign
    CY1 = Y1 + 1.45
    bx(sh, (X0 + 0.05, Y1, 2.88), (X1 - 0.05, CY1 - 0.2, 3.12), "white", colors={"-z": "white"})
    bx(sh, (X0 - 0.1, CY1 - 0.25, 2.7), (X1 + 0.1, CY1, 3.72), DARK)
    bx(sh, (X0 - 0.12, CY1 - 0.25, 2.62), (X1 + 0.12, CY1 + 0.02, 2.72), ACC)
    bx(sh, (X0 - 0.12, CY1 - 0.25, 3.7), (X1 + 0.12, CY1 + 0.02, 3.8), ACC)
    C.sign(sh, "QUIKNOOK 24", (0.0, CY1, 3.21), 8.6, 0.62, "neon_green", depth=0.08, res=TXT_RES, valign="center")
    for x in (-5.0, -3.0, -1.0, 1.0, 3.0, 5.0):
        C.disc(sh, (x, Y1 + 0.7, 2.875), 0.16, "emis_lamp", axis="Z", segs=8, out=-1)
    for sx in (-1, 1):
        sh.cyl(0.1, 2.7, (sx * 5.5, CY1 - 0.15, 0.0), "gray_dark", segs=8, base=True, cap_color="gray_dark")
        col.box((sx * 5.5 - 0.1, CY1 - 0.25, 0.0), (sx * 5.5 + 0.1, CY1 - 0.05, 2.7))
    col.box((X0 - 0.1, Y1, 2.7), (X1 + 0.1, CY1, 3.8))
    # ice chest + bin under the canopy
    bx(sh, (-5.0, Y1 + 0.1, 0.0), (-3.7, Y1 + 0.85, 1.0), "white", bevel=0.02)
    bx(sh, (-5.02, Y1 + 0.08, 0.95), (-3.68, Y1 + 0.87, 1.04), "sky_blue")
    C.pane(sh, "X", -4.9, -3.8, 0.12, 0.85, Y1 + 0.856, "sky_blue", 1)
    C.sign(sh, "ICE", (-4.35, Y1 + 0.86, 0.5), 0.8, 0.4, "white", depth=0.03, res=1, valign="center")
    col.box((-5.0, Y1 + 0.1, 0.0), (-3.7, Y1 + 0.85, 1.04))
    sh.cyl(0.26, 0.95, (3.55, Y1 + 0.45, 0.0), ACC, segs=8, base=True, cap_color="black")
    sh.cyl(0.28, 0.08, (3.55, Y1 + 0.45, 0.95), "gray_dark", segs=8, base=True)
    col.box((3.29, Y1 + 0.19, 0.0), (3.81, Y1 + 0.71, 1.03))
    # back door, lamp, roof plant
    C.door_surround(sh, 2.0, 3.0, 2.15, Y0, w=0.08, proud=0.04, color="gray_dark", out=-1)
    bx(sh, (2.0, Y0 + 0.1, 0.02), (3.0, Y0 + 0.14, 2.15), "gray_light")
    C.wall_lamp(sh, 2.5, Y0, 2.45, out=-1, color="gray_dark")
    C.roof_ac(sh, col, -3.0, -1.5, ZR, 1.9, 1.2, 0.9)
    C.roof_ac(sh, col, 2.0, -2.5, ZR, 1.9, 1.2, 0.9)

    # ---------------------------------------------------------------- fixtures
    C.ceiling_lights(root, fx, [(-2.45, 0.4), (2.6, 1.0), (-1.6, -3.3), (2.6, -2.6)], ZC, size=(1.6, 0.26),
                     emis="emis_warm_always", housing="white")
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, 0.15, 0.01, ACC, {"S": [(1.95, 3.05)]}, sides="SEW")
    F.floor_mat(fx, DC - 0.95, DC + 0.95, 3.6, 4.7, ZF + 0.004, "gray_dark", border=ACC)
    # back wall: drinks coolers + staff door
    F.fridge_wall(fx, col, xi0, 1.0, yi0, d=0.75, n=6, rng=rng)
    bx(fx, (1.95, yi0, ZF), (3.05, yi0 + 0.04, 2.2), "gray_mid")
    bx(fx, (2.03, yi0 + 0.02, ZF), (2.97, yi0 + 0.06, 2.12), "gray_light")
    bx(fx, (2.1, yi0 + 0.06, 1.0), (2.9, yi0 + 0.1, 1.06), "chrome")
    for i, (x, y) in enumerate(((3.6, -4.3), (4.25, -4.35), (3.9, -4.3))):
        F.crate(fx, col if i < 2 else None, (x - 0.3, y - 0.3, ZF + (0.55 if i == 2 else 0.0)),
                (x + 0.3, y + 0.3, ZF + (1.0 if i == 2 else 0.55)))
    # gondolas (three aisles) + -X wall shelving
    for x in (-3.55, -1.35, 0.85):
        with C.at((x, -0.2, ZF), 0, fx, col):
            F.gondola(fx, col, L=4.4, d=0.9, rng=rng, wmin=0.26, wmax=0.48)
    for y in (-1.3, 0.9):
        with C.at((xi0, y, ZF), -90, fx, col):
            F.steel_shelf(fx, col, 2.1, 0.45, 1.85, 4, post="white", board="gray_light", stock=list(F.PRODUCT_COLS),
                          rng=rng, hmax=0.36, wmin=0.35, wmax=0.65, fill=0.95)
    with C.at((xi0, 3.35, ZF), -90, fx, col):
        F.atm(fx, col)
    F.chest_freezer(fx, col, (-3.0, 3.75, ZF), 0, rng=rng)
    for i, (x, y, z) in enumerate(((-0.95, 3.95, 0.0), (-0.35, 3.95, 0.0), (-0.65, 3.95, 0.38))):
        C.obox(fx, (x - 0.28, y - 0.3, ZF + z), (x + 0.28, y + 0.3, ZF + z + 0.38), ("sky_blue", "white", "blue")[i],
               "+x-x+y-y+z")
    col.box((-1.25, 3.65, 0.0), (-0.05, 4.25, 0.8))
    # counter (along Y) with register, candy display, chips rack; back cabinet with small packs
    F.counter(fx, col, 3.8, 4.4, -0.6, 2.6, 1.05, body="white", top="gray_dark")
    C.pane(fx, "Y", -0.5, 2.5, 0.12, 0.98, 3.79, ACC, -1)
    F.register(fx, (4.1, 0.9, 1.05), 90)
    bx(fx, (3.88, 1.9, 1.05), (4.3, 2.45, 1.12), "gray_mid")
    bx(fx, (4.0, 1.9, 1.12), (4.3, 2.45, 1.2), "gray_mid")
    for i in range(4):
        C.obox(fx, (3.9, 1.93 + i * 0.13, 1.12), (3.99, 2.04 + i * 0.13, 1.17), F.PRODUCT_COLS[i * 3], "+x-x+y-y+z")
        C.obox(fx, (4.02, 1.93 + i * 0.13, 1.2), (4.12, 2.04 + i * 0.13, 1.26), F.PRODUCT_COLS[i * 3 + 1], "+x-x+y-y+z")
    F.chips_rack(fx, col, (4.1, 3.05, ZF), 90, rng=rng)
    with C.at((xi1, 1.0, ZF), 90, fx, col):
        F.wall_cabinet(fx, col, 3.2, 0.35, 0.95, body="white", top="gray_dark", doors=4)
        bx(fx, (-1.6, 0.0, 1.35), (1.6, 0.02, 2.25), "gray_dark")
        for sx in (-1, 1):
            bx(fx, (sx * 1.6 - (0.03 if sx > 0 else 0.0), 0.0, 1.35), (sx * 1.6 + (0.0 if sx > 0 else 0.03), 0.3, 2.25),
               "gray_dark")
        bx(fx, (-1.6, 0.0, 2.25), (1.6, 0.3, 2.29), "gray_dark")
        for k, z in enumerate((1.38, 1.68, 1.98)):
            bx(fx, (-1.58, 0.02, z - 0.02), (1.58, 0.3, z), "gray_light")
            F.stock_row(fx, -1.55, 1.55, 0.04, 0.28, z, 0.22, list(F.PRODUCT_COLS), rng, 0.12, 0.25, gap=0.015,
                        fill=1.0, hmin=0.15, dmin=1.0, faces="+y+z")
        F.monitor(fx, (1.2, 0.15, 0.95), 0, 0.42, 0.28)
    # neon OPEN sign hanging in the right window, promo posters on the glass
    bx(fx, (4.0, yi1 - 0.08, 1.62), (5.0, yi1 - 0.06, 2.12), "black")
    C.sign(fx, "OPEN", (4.5, yi1 - 0.06, 1.87), 0.8, 0.3, "neon_red", depth=0.03, res=1, valign="center")
    for (a, b, z0, z1, c) in ((-4.9, -3.9, 1.6, 2.4, "yellow"), (-2.2, -1.2, 1.7, 2.45, "red"),
                              (0.05, 0.75, 0.9, 1.5, "cyan")):
        for o, dy in ((1, 0.0), (-1, 0.004)):
            C.pane(fx, "X", a, b, z0, z1, yn - 0.06 - dy, c, o)
            C.pane(fx, "X", a + 0.1, b - 0.1, z0 + 0.12, z0 + 0.3, yn - 0.06 - dy + o * 0.003, "white", o)

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(X0 - 2, X1 + 2, Y0 - 2, Y1 + 3))
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    col.to_object(root)
    entrance_marks(root, DC, Y1, ZF, spawn=(1.9, 2.0, 180),
                   extra=[("counter", (3.2, 0.9), -90), ("staff", (5.0, 0.9), 90), ("register", (4.1, 0.9, 1.05), 90)])
    return root


# =========================================================================== shop_barber  "FADE FACTORY"
NOTES["shop_barber"] = (
    "FADE FACTORY barber. Footprint 8x8 (x -4..4, y -4..4), walls 0.25, floor 0.02 (checker tiles), ceiling 3.2, roof "
    "3.45, parapet 4.0. Entrance 1.6x2.42 at x 1.0..2.6 in the +Y wall (door_l slides -X, door_r +X). Part `pole` = "
    "the striped core of the barber pole outside (x 3.3, y 4.22), origin on its axis at the bottom of the stripes "
    "(z 1.35): spin it about local Z; caps, bracket and glass sleeve are in the shell. Two barber chairs facing "
    "mirror stations on the -X wall; marker `chair` = seat point of the first chair (seat top z 0.62, looking at the "
    "mirror, -X). Reception counter in the back +X corner (counter / staff), waiting bench on the +X wall.")


def barber_pole_core(root, x, y, z0, h=0.95, r=0.085, segs=8, rings=16, colors=("red", "red", "white", "white", "blue",
                                                                             "blue", "white", "white")):
    """Striped barber-pole core as its own part `pole` (origin on the axis at the bottom, spins about Z)."""
    mb = K.MB()
    pts = []
    for i in range(rings + 1):
        z = z0 + h * i / rings
        pts.append([(x + math.cos(2 * math.pi * k / segs) * r, y + math.sin(2 * math.pi * k / segs) * r, z)
                    for k in range(segs)])
    for i in range(rings):
        for k in range(segs):
            k2 = (k + 1) % segs
            mb.quad(pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k], colors[(k + i) % len(colors)])
    mb.poly(list(reversed(pts[0])), "white")
    mb.poly(pts[-1], "white")
    return mb.to_object(root, "pole", origin=(x, y, z0), sharp_angle=50)


def build_shop_barber():
    root = K.begin_asset("shop_barber", C.CAT)
    sh, fx, col = K.MB(), C.DMB(), C.Col()
    rng = random.Random(51)
    X0, X1, Y0, Y1, T = -4.0, 4.0, -4.0, 4.0, 0.25
    ZF, ZC, ZR, ZP = 0.02, 3.2, 3.45, 4.0
    xi0, xi1, yi0, yi1 = X0 + T, X1 - T, Y0 + T, Y1 - T
    yn = Y1 - T / 2
    EXT, ACC = "stucco_cream", "brick_red"
    DC, DX, DH = 1.8, 0.8, 2.42
    WZ0, WZ1 = 0.55, 2.6
    wins = [(-3.45, 0.6)]
    PX, PY, PZ = 3.3, Y1 + 0.22, 1.35          # barber pole axis / bottom of the stripes

    # ---------------------------------------------------------------- shell
    C.box_shell(sh, fx, col, X0, X1, Y0, Y1, T, ZF, ZC, ZR, ZP, ext=EXT, inn="@D:white", floor="@D:tile_white",
                ceil="@D:ceiling", cope="white",
                front=[(DC - DX, DC + DX, 0.0, DH)] + [(a, b, WZ0, WZ1, "glass") for a, b in wins])
    storefront_windows(sh, wins, WZ0, WZ1, yn, Y1, frame="black", sill="white", every=1.4, fw=0.06)
    a, b = wins[0]
    bx(sh, (a, Y1, 0.0), (b, Y1 + 0.03, WZ0 - 0.06), "tile_white")
    nck = 16
    cs = (b - a) / nck
    for i in range(nck):
        for r in range(2):
            if (i + r) % 2:
                C.pane(sh, "X", a + i * cs, a + (i + 1) * cs, r * 0.245, (r + 1) * 0.245, Y1 + 0.034, "tile_dark", 1)
    C.door_surround(sh, DC - DX, DC + DX, DH, Y1, w=0.08, proud=0.04, color="black")
    C.threshold(sh, col, DC - DX, DC + DX, yi1, Y1, "black", ZF, lip=0.3)
    C.sliding_doors(root, sh, DC, yi1, -1, ZF, 1.6, 2.4, frame="black", accent="red")
    bx(sh, (DC - 0.95, Y1, 2.6), (DC + 0.95, Y1 + 0.75, 2.7), "black")
    bx(sh, (DC - 0.95, Y1 + 0.7, 2.56), (DC + 0.95, Y1 + 0.78, 2.72), "red")
    for sx in (-1, 1):
        xa, xb = (X0 - 0.06, X0 + 0.3) if sx < 0 else (X1 - 0.3, X1 + 0.06)
        bx(sh, (xa, Y1 - 0.3, 0.0), (xb, Y1 + 0.06, ZP + 0.08), ACC)
    C.band(sh, X0, X1, Y0, Y1, 0.0, 0.45, 0.03, ACC, sides="ESW")
    C.band(sh, X0, X1, Y0, Y1, 2.75, 2.85, 0.006, "red", sides="ESW", flat=True)
    C.band(sh, X0, X1, Y0, Y1, 2.9, 3.0, 0.006, "navy", sides="ESW", flat=True)
    # sign board with neon lettering and a white neon outline
    yf = Y1 + 0.22
    bx(sh, (-3.62, Y1, 2.86), (3.62, yf, 3.9), "black")
    C.sign(sh, "FADE FACTORY", (0.0, yf, 3.38), 6.3, 0.6, "neon_red", depth=0.07, res=TXT_RES, valign="center")
    C.neon_path(sh, [(-3.48, 2.96), (3.48, 2.96), (3.48, 3.8), (-3.48, 3.8), (-3.48, 2.96)], yf, w=0.035, d=0.03,
                color="neon_white")
    # barber pole: bracket, chrome caps, glass sleeve (static) + spinning striped core (part `pole`)
    bx(sh, (PX - 0.08, Y1, PZ - 0.3), (PX + 0.08, Y1 + 0.03, PZ + 1.25), "chrome")
    for z in (PZ - 0.12, PZ + 1.07):
        bx(sh, (PX - 0.025, Y1, z - 0.025), (PX + 0.025, PY, z + 0.025), "chrome")
    sh.cyl(0.125, 0.12, (PX, PY, PZ - 0.12), "chrome", segs=10, base=True)
    sh.cyl(0.04, 0.1, (PX, PY, PZ - 0.22), "chrome", segs=6, base=True)
    sh.cyl(0.125, 0.1, (PX, PY, PZ + 0.95), "chrome", segs=10, base=True)
    sh.sphere(0.11, (PX, PY, PZ + 1.08), "chrome", segs=10, rings=5, scale=(1, 1, 0.8))
    sh.cyl(0.11, 0.95, (PX, PY, PZ), "@Glass", segs=10, base=True, caps=False)
    barber_pole_core(root, PX, PY, PZ)
    # back + roof
    C.door_surround(sh, -2.5, -1.5, 2.15, Y0, w=0.08, proud=0.04, color="black", out=-1)
    bx(sh, (-2.5, Y0 - 0.025, 0.02), (-1.5, Y0, 2.15), "red_dark")
    C.wall_lamp(sh, -2.0, Y0, 2.45, out=-1, color="black")
    C.roof_ac(sh, col, 0.5, -1.5, ZR, 1.5, 1.0, 0.8)

    # ---------------------------------------------------------------- fixtures
    cell = 0.5
    nx = int(round((xi1 - xi0) / cell))
    for i in range(nx):
        for j in range(nx):
            if (i + j) % 2:
                F.floor_quad(fx, xi0 + i * cell, xi0 + (i + 1) * cell, yi0 + j * cell, yi0 + (j + 1) * cell, ZF + 0.003,
                             "tile_dark")
    C.band_in(fx, xi0, xi1, yi0, yi1, ZF, 1.0, 0.012, "red_dark", sides="SEW")
    C.band_in(fx, xi0, xi1, yi0, yi1, 1.0, 1.06, 0.016, "black", sides="SEW")
    F.pendant(root, fx, [(-2.25, 0.9), (-2.25, -1.5), (2.3, 0.9)], ZC, drop=0.75, shade="black")
    # mirror stations + chairs (-X wall)
    for y in (0.9, -1.5):
        with C.at((xi0, y, ZF), -90, fx, col):
            F.mirror_station(fx, col, 1.2, rng=rng)
        F.barber_chair(fx, col, (-2.25, y, ZF), 90)
    # waiting bench + TV + side table (+X wall)
    with C.at((xi1, 0.9, ZF), 90, fx, col):
        F.wait_bench(fx, col, 2.2)
    bx(fx, (xi1 - 0.07, 0.3, 1.7), (xi1, 1.5, 2.42), "black")
    C.pane(fx, "Y", 0.34, 1.46, 1.74, 2.38, xi1 - 0.074, "screen_blue", -1)
    bx(fx, (xi1 - 0.45, 2.2, ZF), (xi1, 2.65, 0.55), "wood_dark")
    for k, c in enumerate(("red", "navy", "white")):
        C.obox(fx, (xi1 - 0.4, 2.27, 0.55 + k * 0.015), (xi1 - 0.12, 2.6, 0.564 + k * 0.015), c, "+x-x+y-y+z")
    col.box((xi1 - 0.45, 2.2, 0.0), (xi1, 2.65, 0.55))
    # reception counter + shelf behind (back +X corner), clock, poster
    F.counter(fx, col, 1.45, 3.3, -2.45, -1.85, 1.05, body="black", top="wood_mid")
    C.pane(fx, "X", 1.5, 3.25, 0.2, 0.9, -1.846, "red", 1)
    C.pane(fx, "X", 1.5, 3.25, 0.4, 0.6, -1.843, "white", 1)
    F.register(fx, (2.7, -2.2, 1.05), 0.0)
    with C.at((2.45, yi0, ZF), 0, fx, col):
        F.wall_cabinet(fx, col, 2.4, 0.35, 0.9, body="wood_dark", top="black", doors=3)
        bx(fx, (-1.2, 0.0, 1.45), (1.2, 0.25, 1.48), "black")
        bx(fx, (-1.2, 0.0, 1.85), (1.2, 0.25, 1.88), "black")
        for z in (1.48, 1.88):
            for i in range(9):
                fx.cyl(0.035, rng.uniform(0.14, 0.22), (-1.05 + i * 0.26, 0.12, z), rng.choice(("teal", "yellow", "white",
                       "red", "blue", "black")), segs=6, base=True)
    F.wall_clock(fx, "X", 2.45, 2.55, yi0, 1)
    F.layered_art(fx, "X", -1.4, 0.2, 1.3, 2.5, yi0, 1,
                  [(0.0, 1.0, 0.0, 1.0, "white"), (0.1, 0.3, 0.05, 0.95, "red"), (0.4, 0.6, 0.05, 0.95, "navy"),
                   (0.7, 0.9, 0.05, 0.95, "red")], frame="black", back="cream")
    # shampoo basin (back -X corner), coat rack, plant, door mat
    with C.at((-2.95, yi0, ZF), 0, fx, col):
        F.wall_cabinet(fx, col, 0.9, 0.5, 0.85, body="white", top="black", doors=2)
        C.obox(fx, (-0.3, 0.1, 0.8), (0.3, 0.42, 0.856), "steel", "+z")
        bx(fx, (-0.03, 0.02, 0.85), (0.03, 0.08, 1.12), "chrome")
        bx(fx, (-0.03, 0.02, 1.08), (0.03, 0.24, 1.12), "chrome")
        C.pane(fx, "X", -0.4, 0.4, 1.3, 2.1, 0.006, "mirror", 1)
    F.coat_rack(fx, (3.3, 3.3, ZF))
    F.plant(fx, col, (-3.3, 3.3, ZF), h=1.3, pot="white", seed=11)
    F.floor_mat(fx, DC - 0.9, DC + 0.9, 3.0, 3.7, ZF + 0.006, "black", border="red")

    # ---------------------------------------------------------------- parts + markers
    C.cull_hidden(sh, C.ground_occ(X0 - 2, X1 + 2, Y0 - 2, Y1 + 2))
    C.cull_hidden(fx, C.room_occluders(xi0, xi1, yi0, yi1, ZF, ZC))
    sh.to_object(root, "shell")
    fx.to_object(root, "fixtures")
    col.to_object(root)
    entrance_marks(root, DC, Y1, ZF, spawn=(0.4, 1.6, 180),
                   extra=[("counter", (2.4, -1.25), 180), ("staff", (2.4, -2.95), 0), ("chair", (-2.25, 0.9, 0.62), 90)])
    return root


# =========================================================================== build all
BUILDERS = [("shop_garage", build_shop_garage), ("shop_guns", build_shop_guns), ("safehouse", build_safehouse),
            ("shop_clothes", build_shop_clothes), ("shop_market", build_shop_market), ("shop_barber", build_shop_barber)]


def build_all(only=None):
    out = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
        out.append(export(name))
    return "\n".join(out)
