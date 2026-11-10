"""Service landmarks: mod_garage (Torque Garage), gas_station (Halcyon Fuel), shooting_range (Ironsight Range).
See buildings_landmarks.py (entry) and landmark_kit.py (helpers)."""
import math

import gta_bl as G
import building_kit as K
import landmark_kit as LK

PI = math.pi
FL = LK.FLOOR


def _paint_cans(f, x, y, z, n=4, seed=3):
    r = LK.Rnd(seed)
    cols = ("CarRed", "CarBlue", "CarYellow", "CarGreen", "CarOrange", "CarTeal", "CarPurple", "CarWhite")
    for i in range(n):
        c = r.pick(cols)
        f.cyl(x + i * 0.24, y, z, z + 0.26, 0.09, "Chrome", 6)
        f.cyl(x + i * 0.24, y, z + 0.06, z + 0.2, 0.094, c, 6, caps="none")


# ------------------------------------------------------------------------------------------------
def mod_garage(slot):
    """Torque Garage: steel workshop hall under a gable roof with a 5.2 x 3.85 m drive-in bay
    (lift outline, tool benches, tyre racks, paint corner under an extraction hood) + parts annex."""
    b = LK.LB("mod_garage", slot, dict(wall="Steel", wall2="White", base="Charcoal", trim="Charcoal", roof="RoofGrey",
                                       sign="Charcoal", neon="NeonOrange", accent="SafetyOrange", door="SteelDark",
                                       metal="Charcoal", awning="SafetyOrange", awning2="Charcoal"))
    x0, x1, y0, y1 = -10.6, 3.0, -8.6, 7.9
    H, C = 5.6, 5.0
    BX = -4.0                                          # bay centre line
    rm = LK.Room(b, x0, x1, y0, y1, H, C)
    rm.wall("front", [LK.gap(BX - 2.6, BX + 2.6, FL, 3.9), LK.door(0.5, 2.3, 2.5)])
    rm.wall("left", [LK.win(-6.0, -2.0, 3.0, 4.4, nx=2), LK.win(1.0, 5.0, 3.0, 4.4, nx=2)])
    rm.wall("back")
    rm.wall("right")
    rm.floor("Concrete")
    rm.ceiling("White")
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")     # F: u = 3.0 - x

    # --- exterior -------------------------------------------------------------------------------
    F.dado([(0.0, 0.56), (2.64, 4.3), (9.7, 13.6)], h=1.0, proud=0.08)
    for f in (B, L):
        f.dado(h=1.0, proud=0.08)
    for f in (F, B, L, R):
        f.rect(0.0, f.w, 4.02, 4.3, "accent", 0.012, "detail")
    b.gable_roof(x0, x1, y0, y1, H, 1.7, axis="y", over=0.35, gover=0.3)
    F.sign(1.0, 12.6, 4.42, 5.5, "TORQUE GARAGE", board="sign", color="neon", border="NeonYellow", pad=0.2)
    LK.emblem_gear(F, 6.8, 6.42, 0.6)
    F.frame(4.4, 9.6, FL, 3.9, w=0.2, proud=0.1, back=0.0, mat="accent")
    b.poly(((BX - 2.6, y1, FL), (BX + 2.6, y1, FL), (BX + 2.6, y1 + 0.7, 0.0), (BX - 2.6, y1 + 0.7, 0.0)), "Concrete")
    for bx in (BX - 3.0, BX + 3.0):
        LK.bollard(b, bx, y1 + 0.45)
    b.box(BX - 2.6, BX + 2.6, y1 - 0.75, y1 - 0.32, 3.92, 4.4, "Steel", "interior")       # rolled-up door drum
    for i in range(3):                                                                    # door slats peeking out
        b.box(BX - 2.6, BX + 2.6, y1 - 0.2, y1 - 0.14, 3.6 + i * 0.1, 3.68 + i * 0.1, "SteelDark", "detail")
    b.vent(-3.8, -3.5, H + 1.62)
    b.vent(-3.8, 3.0, H + 1.62)
    L.text("TORQUE", 8.25, 2.3, 0.2, "SafetyOrange", 0.02)
    # annex (parts counter, closed)
    am = b.mass(3.0, 10.9, -8.6, 6.4)
    AH = 4.0
    sp = am.front.row(0.0, AH, [K.rollup(3.0, 3.0, mat="SafetyOrange", frame="trim"), K.shop(door="left", head=2.9)], "Cream")
    am.right.row(0.0, AH, [K.win(1.6, 1.4, 1.1, frame="trim", sill_bar="trim")] * 3 + [None], "Cream")
    am.back.row(0.0, AH, [None, K.door(1.1, 2.2, mat="door", frame="trim")], "Cream")
    am.right.dado(h=1.0, proud=0.08)
    am.back.dado([(0.0, 5.2), (6.7, 7.9)], h=1.0, proud=0.08)
    am.front.sign(4.25, 7.65, 3.1, 3.75, "PARTS + SERVICE", board="sign", color="NeonYellow", pad=0.12)
    am.front.text("2", 2.0, 3.45, 0.11, "Charcoal", 0.02)
    b.flat_roof(am.pts, AH, parapet=0.5, wall="Cream")
    b.belt(am.pts, 3.86, h=0.3, proud=0.08, mat="accent", edges=[0, 1, 2])
    b.ac_unit(7.5, -3.0, AH)
    b.ac_unit(7.5, -5.2, AH)
    with LK.at_floor(0.0):                                                                # tyre pile by the annex
        for i in range(3):
            LK.tyre_stack(b, 3.75 + i * 0.75, 6.85, 3 - (i % 2), part="body")
    b.entrance = (BX, y1)

    # --- interior -------------------------------------------------------------------------------
    for side in ("left", "right", "back"):
        f = rm.inner[side]
        f.rect(0.0, f.w, 1.15, 1.4, "accent", 0.008, "interior")
    # lift outline + lane (flush graphics, no collision)
    z = FL + 0.012
    for sx in (-0.85, 0.85):
        LK.hrect(b, BX + sx - 0.32, BX + sx + 0.32, -3.3, 1.3, z + 0.01, "SteelDark")
        for ya in (-3.3, 1.12):
            LK.hrect(b, BX + sx - 0.32, BX + sx + 0.32, ya, ya + 0.18, z + 0.018, "HazardYellow")
    for (xa, xb, ya, yb) in ((-1.75, 1.75, -3.85, -3.7), (-1.75, 1.75, 1.7, 1.85), (-1.75, -1.6, -3.7, 1.7), (1.6, 1.75, -3.7, 1.7)):
        LK.hrect(b, BX + xa, BX + xb, ya, yb, z, "HazardYellow")
    for sx in (-2.45, 2.33):
        LK.hrect(b, BX + sx, BX + sx + 0.12, 2.4, 7.6, z, "HazardYellow")
    # extraction hood with booth lights above the bay
    b.box(BX - 2.5, BX + 2.5, -4.6, 2.6, 4.25, C, "Steel", "interior", "+z")
    for sx in (-1.5, 0.0, 1.5):
        LK.hrect(b, BX + sx - 0.5, BX + sx + 0.5, -4.0, 2.0, 4.245, "LampWarm", down=True)
    b.box(BX - 0.5, BX + 0.5, -8.3, -4.6, 4.3, 4.9, "Steel", "interior", "+y -y")
    # paint corner on the back wall
    bi = rm.inner["back"]                               # u = (x1 - 0.3) - x
    bi.box(3.0, 9.6, 0.5, 2.6, 0.0, 0.06, "WarmGrey", "interior", "k")                   # filter wall
    for i in range(6):
        bi.zigzag_h(3.2 + i * 1.07, 4.1 + i * 1.07, 0.7, 2.4, 0.06, 0.2, 0.05, "Steel", "interior")
    cols = ("CarRed", "CarOrange", "CarYellow", "CarGreen", "CarTeal", "CarBlue", "CarPurple", "CarWhite", "CarSilver", "CarBlack")
    bi.box(0.15, 2.75, 1.45, 2.85, 0.0, 0.04, "Charcoal", "interior", "k")
    for i, c in enumerate(cols):
        ua = 0.3 + (i % 5) * 0.48
        va = 1.6 + (i // 5) * 0.62
        bi.box(ua, ua + 0.38, va, va + 0.5, 0.04, 0.06, c, "interior", "k")
    f = LK.workbench(b, 1.05, -7.9, 0.0, 2.6, 0.75, peg=False, top="Steel")
    _paint_cans(f, -1.0, -0.15, 0.92, 5, seed=3)
    _paint_cans(f, 0.4, 0.05, 0.92, 3, seed=8)
    f.box(-1.15, -0.85, 0.1, 0.25, 0.92, 1.1, "Chrome", "-z")                              # spray gun
    f.box(-1.08, -0.98, 0.1, 0.2, 1.1, 1.26, "CarRed", "-z")
    # tool benches / chests along the left wall
    LK.workbench(b, x0 + 0.72, -3.2, -PI / 2, 2.8, 0.8)
    LK.workbench(b, x0 + 0.72, 3.4, -PI / 2, 2.8, 0.8)
    LK.tool_chest(b, x0 + 0.62, 0.1, -PI / 2, 1.2, 0.55, 1.05, "FireRed")
    LK.tool_chest(b, x0 + 0.62, 6.3, -PI / 2, 1.0, 0.55, 1.3, "CarBlue")
    # tyre racks + stacks
    LK.tyre_rack(b, -8.4, -8.02, 0.0, 3.2, 2.2, 2)
    LK.tyre_stack(b, x0 + 0.75, -6.6, 4)
    LK.tyre_stack(b, x0 + 0.8, -5.8, 2)
    # right-hand side: parts shelf, compressor, drums
    LK.shelf(b, x1 - 0.53, -2.6, PI / 2, 3.6, 0.45, 2.3, 4, frame="SteelDark", goods=("Wood", "CarRed", "Mustard", "Steel", "CarBlue", "WarmGrey"), seed=51)
    f = LK.Fr(b, x1 - 0.75, 2.2, FL, PI / 2)
    f.tube((-0.7, 0.0, 0.55), (0.7, 0.0, 0.55), 0.3, "CarRed", 8)
    f.box(-0.25, 0.25, -0.2, 0.2, 0.85, 1.15, "Charcoal", "-z")
    for sx in (-0.5, 0.5):
        f.box(sx - 0.04, sx + 0.04, -0.25, 0.25, 0.0, 0.3, "Charcoal", "-z")
    LK.barrel(b, 2.2, -7.9, "CarBlue")
    LK.barrel(b, 2.25, -7.15, "Mustard")
    LK.barrel(b, 1.5, -6.6, "CarBlue")
    # engine on a stand
    f = LK.Fr(b, -0.2, 5.6, FL, 0.3)
    f.box(-0.45, 0.45, -0.35, 0.35, 0.0, 0.08, "SafetyOrange", "-z")
    f.box(-0.04, 0.04, -0.04, 0.04, 0.08, 0.6, "SafetyOrange", "-z +z")
    f.box(-0.32, 0.32, -0.25, 0.25, 0.6, 1.05, "SteelDark")
    f.box(-0.28, 0.28, -0.2, 0.2, 1.05, 1.18, "CarRed", "-z")
    f.cyl(-0.38, 0.0, 0.7, 0.95, 0.12, "Chrome", 6)
    for i in range(2):
        for j in range(3):
            LK.ceiling_light(b, x0 + 1.8 + i * 11.0, -6.0 + j * 5.5, C, 0.4, 2.2)

    b.marker("Use_Bay", BX, -1.0, FL, PI)
    b.marker("Staff", x0 + 2.2, 0.4, FL, -PI / 2)
    b.marker("Exit_Bay", BX, 10.4, 0.0, 0.0)
    b.floors = 1
    return b.finish(tags=["garage", "mods", "industrial"], landmark="mod_garage",
                    extra={"sign": "TORQUE GARAGE", "bay": {"width": 5.2, "height": 3.84, "depth": 16.3, "center_x": BX}})


# ------------------------------------------------------------------------------------------------
def _pump(b, key, cx, cy, z0, num):
    """Fuel dispenser as its own object (it can explode); geometry in building space."""
    f = LK.Fr(b, cx, cy, z0, 0.0, key)
    f.box(-0.42, 0.42, -0.27, 0.27, 0.0, 0.14, "Charcoal", "-z")
    f.box(-0.36, 0.36, -0.22, 0.22, 0.14, 1.5, "White", "-z +z")
    f.box(-0.4, 0.4, -0.25, 0.25, 1.5, 1.92, "CarRed", "-z")
    f.box(-0.42, 0.42, -0.27, 0.27, 1.92, 1.98, "Mustard", "-z")
    f.box(-0.37, 0.37, -0.23, 0.23, 0.55, 0.68, "Mustard", "-z +z")
    for sy, face in ((0.22, b.face((cx + 0.36, cy + 0.22), (cx - 0.36, cy + 0.22), z0)),
                     (-0.22, b.face((cx - 0.36, cy - 0.22), (cx + 0.36, cy - 0.22), z0))):
        face.box(0.08, 0.64, 0.95, 1.4, 0.0, 0.015, "Charcoal", key, "k")
        face.box(0.12, 0.42, 1.12, 1.35, 0.015, 0.022, "Sky", key, "k")
        face.box(0.47, 0.6, 1.0, 1.3, 0.015, 0.03, "SteelDark", key, "k")
        face.text(str(num), 0.36, 1.71, 0.05, "White", 0.032, key)
    for sx in (-1, 1):                                     # nozzles + hoses on both ends
        f.box(sx * 0.36, sx * 0.46, -0.1, 0.1, 0.85, 1.25, "Black", "-z")
        f.box(sx * 0.46, sx * 0.52, -0.035, 0.035, 0.3, 1.0, "Black", "-z")
        f.box(sx * 0.36, sx * 0.52, -0.035, 0.035, 0.26, 0.33, "Black")


def gas_station(slot):
    """Halcyon Fuel: canopy with two islands / four pumps (separate objects Pump_1..4), kiosk shop,
    price pylon."""
    b = LK.LB("gas_station", slot, dict(wall="White", wall2="Cream", base="CarRed", trim="White", roof="RoofGrey",
                                        sign="CarRed", neon="NeonYellow", accent="Mustard", metal="Charcoal"))
    # --- kiosk ------------------------------------------------------------------------------------
    kx0, kx1, ky0, ky1 = -8.0, 8.0, -10.6, -3.6
    H, C = 3.8, 3.2
    rm = LK.Room(b, kx0, kx1, ky0, ky1, H, C)
    rm.wall("front", [LK.shopwin(-7.2, -1.6, 0.5, 2.8, nx=3), LK.door(-0.9, 0.9, 2.5), LK.shopwin(1.6, 7.2, 0.5, 2.8, nx=3)])
    rm.wall("left")
    rm.wall("right", [LK.win(-8.6, -6.0, 1.3, 2.5, nx=2)])
    rm.wall("back")
    rm.tiles(("White", "Cream"), 1.1)
    rm.ceiling("White")
    rm.lights(3, 1)
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")     # F: u = 8 - x
    F.dado([(0.0, 6.96), (9.04, 16.0)], h=0.5, proud=0.07)
    for f in (R, B, L):
        f.dado(h=0.5, proud=0.07)
    b.belt(rm.pts, 3.0, h=0.8, proud=0.14, mat="sign")
    for f in (F, R, L, B):
        f.rect(-0.14, f.w + 0.14, 3.06, 3.16, "Mustard", 0.146, "detail")
    F.text("HALCYON FUEL MART", 8.0, 3.47, 0.075, "White", 0.15)
    b.flat_roof(rm.pts, H, parapet=0.4)
    b.ac_unit(-4.0, -7.5, H)
    b.ac_unit(4.0, -8.0, H, turn=True)
    # ice chest + bins + propane cage by the kiosk front
    b.box(3.2, 5.0, -3.6, -2.8, 0.0, 1.05, "White", skip="-z -y")
    b.box(3.15, 5.05, -3.62, -2.75, 1.05, 1.13, "Sky", skip="-z")
    ic = b.face((5.0, -2.8), (3.2, -2.8))
    ic.text("ICE", 0.9, 0.62, 0.1, "CarBlue", 0.012)
    b.box(-6.9, -5.3, -3.6, -3.0, 0.0, 1.5, "SteelDark", skip="-z -y")
    for i in range(3):
        b.cyl(-6.6 + i * 0.5, -3.02, 0.45, 1.25, 0.17, "White", "detail", 6)
    for bx in (-2.6, 2.4):
        b.cyl(bx, -3.2, 0.0, 0.85, 0.24, "Charcoal", "body", 8)
        b.cyl(bx, -3.2, 0.85, 0.9, 0.26, "CarRed", "body", 8)
    b.entrance = (0.0, ky1)

    # --- canopy -------------------------------------------------------------------------------------
    cx0, cx1, cy0, cy1 = -10.5, 10.5, 0.6, 9.6
    CZ = 4.7
    b.box(cx0, cx1, cy0, cy1, -0.3, 0.04, "Concrete", skip="-z")
    b.box(cx0, cx1, cy0, cy1, CZ, CZ + 0.9, "White")
    for face in (b.face((cx1, cy1), (cx0, cy1)), b.face((cx0, cy0), (cx1, cy0)), b.face((cx1, cy0), (cx1, cy1)),
                 b.face((cx0, cy1), (cx0, cy0))):
        face.rect(0.0, face.w, CZ + 0.02, CZ + 0.42, "CarRed", 0.012, "detail")
        face.rect(0.0, face.w, CZ + 0.42, CZ + 0.52, "Mustard", 0.012, "detail")
        if face.w > 12:
            face.text("HALCYON FUEL", face.w / 2, CZ + 0.69, 0.05, "CarRed", 0.012)
        else:
            face.text("HF", face.w / 2, CZ + 0.69, 0.05, "CarRed", 0.012)
        face.neon_line(0.0, face.w, CZ - 0.01, 0.05, "NeonYellow", 0.012)
    IY = 5.1
    pumps = []
    for side, icx in ((-1, -5.5), (1, 5.5)):
        b.box(icx - 3.3, icx + 3.3, IY - 0.65, IY + 0.65, 0.04, 0.2, "Concrete", skip="-z")
        for ex in (icx - 3.3, icx + 3.1):
            b.box(ex, ex + 0.2, IY - 0.65, IY + 0.65, 0.2, 0.22, "HazardYellow", "detail", "-z")
        for colx in (icx - 2.6, icx + 2.6):
            b.box(colx - 0.24, colx + 0.24, IY - 0.24, IY + 0.24, 0.2, CZ, "White", skip="-z +z")
            b.box(colx - 0.28, colx + 0.28, IY - 0.28, IY + 0.28, 0.2, 1.1, "CarRed", skip="-z")
        for ex in (icx - 3.75, icx + 3.75):
            LK.bollard(b, ex, IY - 0.4, 0.9, 0.09, z=0.04)
            LK.bollard(b, ex, IY + 0.4, 0.9, 0.09, z=0.04)
        for px in (icx - 1.0, icx + 1.0):
            pumps.append(px)
        b.box(icx - 0.25, icx + 0.25, IY - 0.2, IY + 0.2, 0.2, 0.95, "Charcoal", skip="-z")        # bin + towel box
        b.box(icx - 0.2, icx + 0.2, IY - 0.15, IY + 0.15, 0.95, 1.25, "Sky", "detail", "-z")
        for ly in (2.6, 7.6):
            LK.hrect(b, icx - 1.6, icx + 1.6, ly - 0.25, ly + 0.25, CZ - 0.005, "LampWarm", down=True)
    for i, px in enumerate(sorted(pumps)):
        key = b.sub("Pump_%d" % (i + 1), origin=(px, IY, 0.2), marker=True)
        _pump(b, key, px, IY, 0.2, i + 1)

    # --- price pylon ----------------------------------------------------------------------------------
    py0, py1, pxa, pxb = 7.9, 9.9, 12.85, 13.15
    for yy in (py0 + 0.25, py1 - 0.25):
        b.box(pxa + 0.03, pxb - 0.03, yy - 0.12, yy + 0.12, 0.0, 2.7, "Steel", skip="-z +z")
    b.box(pxa, pxb, py0, py1, 2.7, 7.0, "White")
    b.box(pxa - 0.04, pxb + 0.04, py0 - 0.04, py1 + 0.04, 7.0, 7.14, "CarRed")
    rows = (("REG", "3.49"), ("PLUS", "3.79"), ("DSL", "4.09"))
    for face in (b.face((pxb, py0), (pxb, py1)), b.face((pxa, py1), (pxa, py0))):
        face.rect(0.0, 2.0, 5.55, 7.0, "CarRed", 0.012, "detail")
        LK.fdisc(face, 1.0, 6.3, 0.58, "Mustard", 10, 0.024)
        face.text("HF", 1.0, 6.3, 0.085, "CarRed", 0.036)
        for k, (name, price) in enumerate(rows):
            va = 4.62 - k * 0.92
            face.rect(0.1, 1.9, va, va + 0.78, "Charcoal", 0.012, "detail")
            face.text(name, 0.52, va + 0.39, 0.042, "White", 0.024)
            face.text(price, 1.36, va + 0.39, 0.058, "NeonYellow", 0.024)
        face.neon_line(0.0, 2.0, 2.72, 0.06, "NeonYellow", 0.012)
    # air / water post
    b.box(-12.6, -12.2, -1.2, -0.8, 0.0, 1.3, "CarBlue", skip="-z")
    b.box(-12.55, -12.25, -0.8, -0.78, 0.7, 1.15, "Sky", "detail", "-y")
    ap = b.face((-12.2, -0.8), (-12.6, -0.8))
    ap.text("AIR", 0.2, 0.45, 0.035, "White", 0.012)

    # --- kiosk interior -------------------------------------------------------------------------------
    LK.counter(b, 4.7, -8.5, 0.0, 4.2, 0.7, 1.02, body="White", top="Charcoal", stripe="CarRed")
    LK.register(b, 5.4, -8.55, 0.0, FL + 1.02)
    LK.shelf(b, 4.7, -10.08, 0.0, 4.6, 0.42, 2.2, 5, frame="White", seed=61, fill=0.97)
    LK.fridge(b, kx0 + 0.68, -7.1, -PI / 2, 5.6, doors=4, band="CarRed", seed=5)
    LK.gondola(b, -3.9, -7.3, PI / 2, 3.8, 0.9, 1.5, 3, seed=71)
    LK.gondola(b, -1.5, -7.3, PI / 2, 3.8, 0.9, 1.5, 3, seed=73)
    LK.shelf(b, -2.6, -10.08, 0.0, 4.6, 0.42, 2.1, 4, seed=77)
    LK.shelf(b, 5.0, -4.12, PI, 3.0, 0.4, 1.1, 3, frame="Charcoal", goods=("White", "Sky", "Mustard", "Rose", "Cream"), seed=79)
    LK.rug(b, 0.0, -4.8, 2.2, 1.3, "Charcoal", "Black")
    LK.plant(b, 7.2, -4.4, 1.2)

    b.marker("Use_Kiosk", 4.7, -7.4, FL, PI)
    b.marker("Staff", 4.7, -9.3, FL, 0.0)
    b.floors = 1
    return b.finish(tags=["fuel", "shop", "midtown"], landmark="gas_station",
                    extra={"sign": "HALCYON FUEL", "canopy_clearance": CZ, "explosive_objects": ["Pump_1", "Pump_2", "Pump_3", "Pump_4"]})


# ------------------------------------------------------------------------------------------------
def _target(b, x, y, z, s=0.3, part="detail"):
    """Ring target facing -X (toward the firing line)."""
    f = b.face((x, y + s * 1.1), (x, y - s * 1.1), z)
    f.box(0.0, s * 2.2, -s * 1.3, s * 1.3, -0.03, 0.0, "Cream", part, "")
    for i, (r, m) in enumerate(((1.0, "Black"), (0.72, "White"), (0.45, "Black"), (0.2, "CarRed"))):
        LK.fdisc(f, s * 1.1, 0.0, s * r, m, 8, 0.008 + i * 0.006, part)


def shooting_range(slot):
    """Ironsight Range: covered five-lane firing line, ~23 m open target yard between concrete walls,
    overhead baffles, earth berm and timber-faced bullet-stop wall. Everything incl. the roof overhang
    stays inside the 30 x 12 m lot (walls at x -14.7 .. 14.96, y -5.7 .. 5.7; roof overhang 0.3 m)."""
    b = LK.LB("shooting_range", slot, dict(wall="WarmGrey", wall2="Cream", base="Charcoal", trim="Charcoal", roof="RoofGrey",
                                           sign="Charcoal", neon="NeonOrange", accent="SafetyOrange", metal="Charcoal"))
    X0, X1, Y0, Y1 = -14.7, 14.96, -5.7, 5.7
    I = Y1 - 0.3                                         # inner half width (inner wall faces)
    XS = -8.6                                            # firing-line edge of the shed
    SH, SC = 4.0, 3.5
    WH = 3.6
    m = b.mass(X0, X1, Y0, Y1, solid=False)
    # --- shed (covered firing line) -------------------------------------------------------------------
    wsh = XS - X0                                        # 6.1 m
    fsh = m.front.sub(X1 - XS, X1 - X0)                  # u = XS - x
    LK.twall(fsh, 0.0, SH, [LK.door(-14.2, -12.4, 2.5), LK.win(-11.4, -9.6, 1.1, 2.4)], inner=(0.0, wsh - 0.3), iv=(FL, SC))
    LK.twall(m.left, 0.0, SH, [], iv=(FL, SC))
    bsh = m.back.sub(0.0, wsh)
    LK.twall(bsh, 0.0, SH, [], inner=(0.3, wsh), iv=(FL, SC))
    b.poly(((X0 + 0.3, -I, FL), (XS, -I, FL), (XS, I, FL), (X0 + 0.3, I, FL)), "Concrete")
    b.poly(((X0 + 0.3, I, SC), (XS, I, SC), (XS, -I, SC), (X0 + 0.3, -I, SC)), "White")
    b.box(XS - 0.3, XS, -I, I, 2.9, SC + 0.5, "wall", skip="+z")              # header beam over the firing line
    for ya, yb in ((I, Y1), (Y0, -I)):                                         # shed wall ends above the yard walls
        b.poly_dir([(XS, ya, WH + 0.12), (XS, yb, WH + 0.12), (XS, yb, SH), (XS, ya, SH)], (1, 0, 0), "wall")
    b.shed_roof(X0, XS + 1.3, Y0, Y1, SH, SH + 0.95, high="right", over=0.3)
    fsh.dado([(0.0, 3.66), (5.74, wsh)], h=0.9, proud=0.08)
    m.left.dado(h=0.9, proud=0.08)
    bsh.dado(h=0.9, proud=0.08)
    for f in (fsh, m.left, bsh):
        f.rect(0.0, f.w, 3.2, 3.45, "accent", 0.012, "detail")
    fsh.sign(0.9, 5.3, 2.62, 3.1, "RANGE", board="sign", color="neon", pad=0.08)
    # --- yard walls ---------------------------------------------------------------------------------
    fy = m.front.sub(0.0, X1 - XS)
    LK.twall(fy, 0.0, WH, [], T=0.3, mat="Concrete", imat="Concrete", inner=(0.5, fy.w), iv=(0.03, WH))
    by = m.back.sub(wsh, X1 - X0)
    LK.twall(by, 0.0, WH, [], T=0.3, mat="Concrete", imat="Concrete", inner=(0.0, by.w - 0.5), iv=(0.03, WH))
    EH = 5.2
    LK.twall(m.right, 0.0, EH, [], T=0.5, mat="Concrete", imat="WoodDark", inner=(0.3, 2 * Y1 - 0.3), iv=(0.03, EH))
    b.box(XS, X1, I - 0.04, Y1 + 0.04, WH, WH + 0.12, "ConcreteDark", skip="-z")
    b.box(XS, X1, Y0 - 0.04, -I + 0.04, WH, WH + 0.12, "ConcreteDark", skip="-z")
    b.box(X1 - 0.54, X1 + 0.04, Y0 - 0.04, Y1 + 0.04, EH, EH + 0.14, "ConcreteDark", skip="-z")
    b.box(X1 - 0.5, X1, I, Y1, WH, EH, "Concrete", skip="-z +z +x -y")
    b.box(X1 - 0.5, X1, Y0, -I, WH, EH, "Concrete", skip="-z +z +x +y")
    for i in range(5):                                                         # timber facing planks
        b.box(X1 - 0.56, X1 - 0.5, -I, I, 3.3 + i * 0.38, 3.34 + i * 0.38, "Trunk", "detail", "+x")
    b.poly(((XS, -I, 0.03), (X1 - 0.5, -I, 0.03), (X1 - 0.5, I, 0.03), (XS, I, 0.03)), "Sand")
    b.prism([(11.3, 0.03), (X1 - 0.5, 0.03), (X1 - 0.5, 3.3)], -I, I, "y", "Dirt")
    fy.text("IRONSIGHT RANGE", fy.w / 2 + 0.6, 2.05, 0.2, "Charcoal", 0.02)
    for uc in (3.5, fy.w - 2.3):
        for i, (r, mm) in enumerate(((0.85, "White"), (0.62, "CarRed"), (0.38, "White"), (0.16, "CarRed"))):
            LK.fdisc(fy, uc, 2.05, r, mm, 10, 0.02 + i * 0.012)
    by.text("IRONSIGHT RANGE", by.w / 2 - 0.1, 2.05, 0.2, "Charcoal", 0.02)
    for f in (fy, by):                                                         # tie the yard walls to the shed
        f.dado(h=0.9, proud=0.08, mat="ConcreteDark")
        f.rect(0.0, f.w, 3.0, 3.2, "accent", 0.012, "detail")
    m.right.rect(0.0, m.right.w, 3.0, 3.2, "accent", 0.012, "detail")        # outer face of the bullet-stop wall
    for i, (r, mm) in enumerate(((0.95, "White"), (0.7, "CarRed"), (0.43, "White"), (0.18, "CarRed"))):
        LK.fdisc(m.right, m.right.w / 2, 1.75, r, mm, 10, 0.012 + i * 0.008)
    # floodlight masts halfway down-range (lamp heads aim at the targets)
    for yy in (I - 0.16, -(I - 0.16)):
        sg = -1.0 if yy > 0 else 1.0
        b.box(0.28, 0.72, yy - 0.16 * sg - 0.06, yy + 0.16 * sg + 0.06, 0.03, 0.3, "ConcreteDark", "detail")
        b.cyl(0.5, yy, 0.3, 7.2, 0.1, "SteelDark", "detail", 8)
        ya, yb = sorted((yy, yy + sg * 1.45))
        b.box(0.43, 0.57, ya, yb, 6.95, 7.07, "SteelDark", "detail")
        for k in range(3):
            yc = yy + sg * (0.35 + k * 0.42)
            b.box(0.57, 0.86, yc - 0.17, yc + 0.17, 6.78, 7.2, "Charcoal", "detail")
            b.box(0.86, 0.89, yc - 0.13, yc + 0.13, 6.82, 7.16, "LampWarm", "detail")
    # range flag + beacons
    b.cyl(X1 - 0.25, Y1 - 0.15, EH, EH + 3.0, 0.05, "Chrome", "detail", 6)
    b.box(X1 - 1.5, X1 - 0.3, Y1 - 0.17, Y1 - 0.13, EH + 2.1, EH + 2.9, "FireRed", "detail")
    for yy in (-(Y1 - 0.15), Y1 - 0.15):
        b.box(XS + 0.05, XS + 0.3, yy - 0.12, yy + 0.12, WH + 0.12, WH + 0.38, LK.beacon(), "detail", "-z")
    # --- lanes ----------------------------------------------------------------------------------------
    PITCH = 2.1
    lanes = [2 * PITCH - PITCH * i for i in range(5)]
    for k in range(4):
        yd = lanes[k] - PITCH / 2
        LK.hrect(b, XS + 0.4, 11.2, yd - 0.05, yd + 0.05, 0.045, "RoadLine")
        LK.partition(b, (-10.7, yd), (-9.25, yd), FL, 2.15, T=0.08, mat="OliveDrab", top=True)
    for xb in (-2.0, 6.0):                                                     # overhead baffles
        b.box(xb - 0.12, xb + 0.12, -I, I, 2.95, 3.6, "WoodDark", skip="-y +y")
    hb = PITCH / 2 - 0.08
    for i, yc in enumerate(lanes):
        # bench segment with gear
        b.box(-9.55, -9.0, yc - hb, yc + hb, FL + 0.95, FL + 1.03, "Wood", "interior")
        b.box(-9.3, -9.22, yc - hb, yc + hb, FL, FL + 0.95, "Charcoal", "interior", "-z +z")
        b.box(-9.5, -9.25, yc - 0.7, yc - 0.4, FL + 1.03, FL + 1.13, "OliveDrab", "interior", "-z")
        b.box(-9.45, -9.3, yc + 0.35, yc + 0.6, FL + 1.03, FL + 1.1, "Brass", "interior", "-z")
        nf = b.face((-2.13, yc + 0.4), (-2.13, yc - 0.4))
        nf.rect(0.1, 0.7, 3.05, 3.5, "White", 0.012, "detail")
        nf.text(str(i + 1), 0.4, 3.275, 0.07, "Charcoal", 0.024)
        b.box(-9.0, 10.9, yc - 0.015, yc + 0.015, 2.86, 2.9, "SteelDark", "detail", "-x")          # carrier cable
        _target(b, 10.9, yc, 1.55, 0.36)
        b.box(10.9, 10.96, yc - 0.03, yc + 0.03, 2.0, 2.88, "SteelDark", "detail", "-z")
        _target(b, 2.2 + (i % 2) * 1.5, yc, 1.6, 0.24)
        tx = 2.2 + (i % 2) * 1.5
        b.box(tx, tx + 0.04, yc - 0.02, yc + 0.02, 1.9, 2.88, "SteelDark", "detail", "-z")
        b.marker("Lane_%d" % (i + 1), -10.2, yc, FL, -PI / 2)
    # --- shed interior ----------------------------------------------------------------------------------
    LK.gun_wall(b, X0 + 0.3, -1.2, -PI / 2, 5.0, rows=3, per=3, seed=31)
    LK.counter(b, -12.5, -3.4, 0.0, 2.8, 0.7, 1.02, body="OliveDrab", top="Charcoal", stripe="SafetyOrange")
    LK.register(b, -11.9, -3.45, 0.0, FL + 1.02)
    t = LK.table(b, -12.4, 0.4, PI / 2, 2.2, 0.9, 0.85, top="Wood", leg="Steel")
    LK.long_gun(t, -0.9, 0.91, 1.05, 0.0, mag=False)
    for k in range(3):
        t.box(0.35 + k * 0.22, 0.52 + k * 0.22, -0.3, -0.05, 0.85, 0.97, ("OliveDrab", "Brass", "CarRed")[k], "-z")
    LK.seat_row(b, -11.6, I - 0.3, PI, 3, "OliveDrab")
    LK.lockers(b, -13.25, -I + 0.27, 0.0, 5, mat="SteelDark")
    LK.barrel(b, -10.9, -I + 0.3, "Charcoal", 0.6, 0.25)
    bi = b.face((-9.0, -I), (X0 + 0.3, -I))               # looks +Y into the shed; u = -9.0 - x
    bi.box(0.9, 2.6, 1.5, 2.4, 0.0, 0.04, "HazardYellow", "interior", "k")
    bi.text("EYES + EARS", 1.75, 1.95, 0.036, "Charcoal", 0.05, "interior")
    for j in range(3):
        LK.ceiling_light(b, -11.6, -3.8 + j * 3.8, SC, 2.2, 0.35)

    b.marker("Use_Start", -12.3, 3.2, FL, -PI / 2)
    b.marker("Target_Area_Min", XS + 0.6, I - 0.1, 0.0)
    b.marker("Target_Area_Max", X1 - 0.6, -(I - 0.1), 4.0)
    b.entrance = (-13.3, Y1)
    b.floors = 1
    return b.finish(tags=["range", "activity", "industrial"], landmark="shooting_range",
                    extra={"sign": "IRONSIGHT RANGE", "firing_line_x": -9.0, "lanes": 5, "lane_pitch": PITCH,
                           "target_distance_max": round(X1 - 0.5 - (-9.0), 2), "static_targets_x": [2.2, 3.7, 10.9]})


BUILD = {"mod_garage": mod_garage, "gas_station": gas_station, "shooting_range": shooting_range}
VIEWS = {
    "mod_garage": dict(cut=4.2, shots=[((-4.0, 12.5, 1.7), (-4.0, 0.0, 1.6)), ((-4.0, 7.0, 1.7), (-4.0, -8.0, 1.6)),
                                       ((2.2, -7.5, 1.8), (-9.0, 2.0, 1.2)), ((-9.5, 6.8, 1.8), (1.0, -8.0, 1.2))]),
    "gas_station": dict(cut=3.0, box=(-9.0, 9.0, -11.5, -2.5),
                        shots=[((0.0, -4.2, 1.7), (3.5, -10.0, 1.2)), ((-14.0, 14.0, 2.4), (0.0, 3.0, 2.0)),
                               ((0.0, 12.5, 1.7), (-5.5, 5.0, 1.2)), ((16.5, 5.0, 2.5), (12.0, 9.0, 4.5))]),
    "shooting_range": dict(cut=2.8, shots=[((-13.3, 4.4, 1.7), (-11.0, -4.0, 1.2)), ((-10.2, 0.0, 1.65), (10.0, 0.0, 1.4)),
                                           ((-13.9, -4.3, 1.8), (-9.5, 4.0, 1.2)), ((12.0, 4.5, 1.7), (-8.0, -3.0, 1.2))]),
}
