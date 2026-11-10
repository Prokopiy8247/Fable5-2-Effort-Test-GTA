"""Landmark shops: gun_shop (Bay Arms), clothing_store (Tide Threads), general_store (Corner 24),
barber (Harbor Cuts). See buildings_landmarks.py (entry) and landmark_kit.py (helpers)."""
import math

import gta_bl as G
import building_kit as K
import landmark_kit as LK

PI = math.pi
FL = LK.FLOOR


def back_door(face, uc, mat="GunMetal", w=1.1, h=2.2):
    """Painted service door on an outer wall (not an opening)."""
    face.box(uc - w / 2 - 0.1, uc + w / 2 + 0.1, 0.0, h + 0.1, 0.0, 0.05, "trim", "body", "k b")
    face.box(uc - w / 2, uc + w / 2, 0.02, h, 0.05, 0.08, mat, "body", "k b")
    # handle + lamp count as solid shell (part "body") so the footprint covers them (no non-solid overhang at the back)
    face.box(uc + w / 2 - 0.2, uc + w / 2 - 0.14, 0.95, 1.2, 0.08, 0.14, "Chrome", "body", "k")
    face.box(uc - 0.2, uc + 0.2, h + 0.25, h + 0.4, 0.0, 0.16, "LampWarm", "body", "k")


def wall_lamp(face, uc, v, w=0.6):
    face.box(uc - w / 2, uc + w / 2, v + 0.04, v + 0.16, 0.0, 0.3, "Charcoal", "detail", "k")
    face.box(uc - w / 2 + 0.08, uc + w / 2 - 0.08, v, v + 0.04, 0.05, 0.25, "LampWarm", "detail", "k t")


def mannequin(b, x, y, yaw, top="Coral", bottom="Denim", skin="White", z=FL, part="interior"):
    f = LK.Fr(b, x, y, z, yaw, part)
    f.cyl(0, 0, 0.0, 0.04, 0.3, "Chrome", 8)
    for sx in (-0.1, 0.1):
        f.box(sx - 0.07, sx + 0.07, -0.08, 0.08, 0.04, 0.9, bottom, "-z +z")
    f.box(-0.19, 0.19, -0.1, 0.1, 0.9, 1.02, bottom, "-z")
    f.box(-0.2, 0.2, -0.11, 0.11, 1.02, 1.5, top, "-z")
    for sx in (-0.29, 0.21):
        f.box(sx, sx + 0.08, -0.06, 0.06, 0.95, 1.48, top)
    f.box(-0.05, 0.05, -0.05, 0.05, 1.5, 1.56, skin, "-z +z")
    f.box(-0.09, 0.09, -0.1, 0.1, 1.56, 1.8, skin, "-z")
    return f


# ------------------------------------------------------------------------------------------------
def gun_shop(slot):
    """Bay Arms: brick single-storey gun store with a stepped false front; walk-in shop room."""
    b = LK.LB("gun_shop", slot, dict(wall="Brick", wall2="Cream", base="Charcoal", trim="Cream", roof="RoofGrey",
                                     sign="Charcoal", neon="NeonOrange", metal="Charcoal", accent="Mustard"))
    x0, x1, y0, y1 = -7.5, 7.5, -6.0, 6.0
    H, C = 4.2, 3.4
    rm = LK.Room(b, x0, x1, y0, y1, H, C)
    rm.wall("front", [LK.win(-6.4, -2.2, 0.95, 2.65, nx=2, bars=7), LK.door(-0.9, 0.9, 2.5),
                      LK.win(2.2, 6.4, 0.95, 2.65, nx=2, bars=7)])
    rm.wall("right", [LK.win(-3.6, -2.2, 2.0, 2.8, bars=3), LK.win(1.4, 2.8, 2.0, 2.8, bars=3)])
    rm.wall("left")
    rm.wall("back")
    rm.floor("Concrete")
    rm.ceiling("White")
    rm.lights(3, 2)
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")

    # --- exterior -------------------------------------------------------------------------------
    F.dado([(0.0, 6.46), (8.54, 15.0)], h=0.8, proud=0.1)
    for f in (R, B, L):
        f.dado(h=0.8, proud=0.1)
    for u in (0.3, 5.95, 9.05, 14.7):
        F.pilaster(u, 0.8, 3.25, w=0.5, proud=0.14, mat="Terracotta", cap=False)
    b.belt(rm.pts, 3.25, h=0.22, proud=0.16)
    b.flat_roof(rm.pts, H, parapet=0.5)
    # stepped false front with the sign
    b.box(-5.9, 5.9, y1 - 0.3, y1, H, 5.25, "wall", skip="-z")
    b.box(-4.4, 4.4, y1 - 0.3, y1, 5.25, 5.95, "wall", skip="-z")
    b.box(-6.0, 6.0, y1 - 0.36, y1 + 0.06, 5.25, 5.37, "trim", skip="-z")
    b.box(-4.5, 4.5, y1 - 0.36, y1 + 0.06, 5.95, 6.09, "trim", skip="-z")
    F.sign(3.4, 11.6, 3.7, 5.0, "BAY ARMS", board="sign", color="neon", border="NeonYellow", pad=0.2)
    for uc in (2.55, 12.45):                      # target roundels
        LK.fdisc(F, uc, 4.35, 0.56, "White", 10, 0.03)
        LK.fdisc(F, uc, 4.35, 0.42, "CarRed", 10, 0.045)
        LK.fdisc(F, uc, 4.35, 0.27, "White", 10, 0.06)
        LK.fdisc(F, uc, 4.35, 0.12, "CarRed", 10, 0.075)
    F.text("GUNS - AMMO - ARMOR", 7.5, 5.6, 0.085, "Cream", 0.02)
    F.canopy(5.9, 9.1, 2.82, depth=1.5, th=0.16, mat="Charcoal", rods=True)
    F.sign(9.35, 10.75, 2.78, 3.16, "OPEN", board="Black", color="NeonGreen", pad=0.07)
    for uc in (3.2, 11.8):
        wall_lamp(F, uc, 2.82)
    R.text("BAY ARMS", 6.0, 2.9, 0.2, "Cream", 0.02)
    R.text("EST. HALCYON BAY", 6.0, 1.75, 0.07, "Cream", 0.02)
    back_door(B, 11.5)
    b.ac_unit(3.5, -2.5, H)
    b.ac_unit(-4.0, -3.0, H, turn=True)
    b.vent(0.5, -4.2, H)
    b.skylight(-2.5, 1.5, -1.5, 1.5, H)
    b.entrance = (0.0, y1)

    # --- interior -------------------------------------------------------------------------------
    for i, cx in enumerate((-4.65, -2.75, -0.85)):
        LK.display_case(b, cx, -2.9, 0.0, w=1.86, d=0.75, seed=6 + i)
    LK.counter(b, 1.1, -2.9, 0.0, 1.95, 0.75, 1.0, body="WoodDark", top="Charcoal", stripe="Mustard")
    LK.register(b, 1.3, -2.95, 0.0, FL + 1.0)
    LK.counter(b, 2.42, -4.55, -PI / 2, 2.3, 0.6, 1.0, body="WoodDark", top="Charcoal")
    LK.gun_wall(b, -2.2, -5.7, 0.0, 7.6, rows=3, per=5, seed=4)
    LK.gun_wall(b, -7.2, 1.3, -PI / 2, 4.4, rows=3, per=3, seed=9)
    LK.workbench(b, 5.1, -5.25, 0.0, w=2.8, d=0.8)
    LK.tool_chest(b, 6.75, -3.6, PI / 2, w=1.0, mat="OliveDrab")
    ammo = ("OliveDrab", "Brass", "CarRed", "Charcoal", "Mustard", "GunTan")
    LK.shelf(b, 6.95, 0.6, PI / 2, 3.4, 0.5, 2.1, 4, frame="SteelDark", goods=ammo, seed=21)
    LK.display_case(b, -3.6, 1.7, 0.0, w=2.0, d=0.8, seed=12)
    LK.display_case(b, 1.6, 1.7, 0.0, w=2.0, d=0.8, seed=13)
    LK.gondola(b, 4.6, 4.2, 0.0, 2.6, 0.9, 1.45, 3, seed=40, frame="SteelDark", goods=ammo)
    # body-armour stand
    f = LK.Fr(b, -6.2, 4.6, FL, -PI / 4)
    f.cyl(0, 0, 0.0, 0.05, 0.28, "Charcoal", 8)
    f.cyl(0, 0, 0.05, 1.0, 0.03, "Chrome", 6, caps="none")
    f.box(-0.24, 0.24, -0.13, 0.13, 1.0, 1.6, "TacticalBlack")
    f.box(-0.3, -0.24, -0.1, 0.1, 1.38, 1.6, "TacticalBlack")
    f.box(0.24, 0.3, -0.1, 0.1, 1.38, 1.6, "TacticalBlack")
    f.box(-0.14, 0.14, 0.13, 0.16, 1.15, 1.4, "OliveDrab", "-y")
    f.cyl(0, 0, 1.6, 1.82, 0.1, "WarmGrey", 6)
    LK.notice_board(rm.inner["right"], 1.2, 3.0, 1.2, 2.2, seed=5)
    LK.rug(b, 0.0, 4.6, 2.4, 1.5, "Charcoal", "Black")
    LK.plant(b, 6.75, 5.3, 1.2)

    b.marker("Use_Counter", -1.5, -1.9, FL, PI)
    b.marker("Use_Workbench", 5.1, -4.0, FL, PI)
    b.marker("Staff", -1.5, -4.2, FL, 0.0)
    b.floors = 1
    return b.finish(tags=["shop", "weapons", "midtown"], landmark="gun_shop", extra={"sign": "BAY ARMS"})


# ------------------------------------------------------------------------------------------------
def clothing_store(slot):
    """Tide Threads: white boutique with a teal corner fin, striped awnings and big display windows."""
    b = LK.LB("clothing_store", slot, dict(wall="White", wall2="Cream", base="Teal", trim="Navy", roof="RoofGrey",
                                           sign="Navy", neon="NeonCyan", awning="Teal", awning2="White", metal="Charcoal"))
    x0, x1, y0, y1 = -7.5, 7.5, -6.0, 6.0
    H, C = 4.6, 3.6
    rm = LK.Room(b, x0, x1, y0, y1, H, C)
    rm.wall("front", [LK.shopwin(-6.6, -1.6, 0.45, 3.05, nx=3), LK.door(-0.9, 0.9, 2.6), LK.shopwin(1.6, 6.6, 0.45, 3.05, nx=3)])
    rm.wall("right", [LK.win(-1.5, 3.5, 0.9, 2.9, nx=3)])
    rm.wall("left")
    rm.wall("back", imat="Mint")
    rm.floor("TrunkLight")
    rm.ceiling("White")
    rm.lights(3, 2)
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")

    # --- exterior -------------------------------------------------------------------------------
    F.dado([(0.0, 6.46), (8.54, 15.0)], h=0.45, proud=0.08)
    for f in (R, B, L):
        f.dado(h=0.45, proud=0.08)
    F.awning(0.75, 6.05, 3.5, depth=1.3, drop=0.5, stripes=8)
    F.awning(8.95, 14.25, 3.5, depth=1.3, drop=0.5, stripes=8)
    F.sign(3.2, 11.8, 3.62, 4.5, "TIDE THREADS", board="sign", color="neon", border="NeonMagenta", pad=0.18)
    F.canopy(6.3, 8.7, 2.85, depth=1.1, th=0.14, mat="Navy")
    b.flat_roof(rm.pts, H, parapet=0.6)
    # corner fin with a vertical sign
    b.box(-7.5, -6.0, 4.5, 6.0, H, 7.7, "Teal", skip="-z")
    b.box(-7.58, -5.92, 4.42, 6.08, 7.7, 7.86, "White", skip="-z")
    for i, ch in enumerate("TIDE"):
        F.text(ch, 14.25, 7.2 - i * 0.66, 0.105, "NeonMagenta", 0.03)
        L.text(ch, 0.75, 7.2 - i * 0.66, 0.105, "NeonMagenta", 0.03)
    # painted wave stripes on the side walls
    for f in (L, R):
        for (va, vb, m) in ((3.25, 3.6, "Teal"), (3.7, 3.9, "Mint"), (4.0, 4.12, "Coral")):
            f.rect(0.0, f.w, va, vb, m, 0.012, "detail")
    L.text("SURF - STREET - SUN", 6.6, 2.0, 0.13, "Teal", 0.02)
    back_door(B, 3.0, "Teal")
    b.ac_unit(2.5, -3.0, H)
    b.ac_unit(4.6, -3.0, H)
    b.vent(-2.0, -4.0, H)
    b.entrance = (0.0, y1)

    # --- interior -------------------------------------------------------------------------------
    # changing booths (back right)
    for px in (3.9, 5.55):
        LK.partition(b, (px, -5.7), (px, -4.0), FL, 2.3, T=0.08, mat="Teal", ends=(False, True), top=True)
    b.box(3.82, 7.2, -4.05, -3.95, 2.2, 2.32, "Navy", "interior")
    for xa in (3.98, 5.63):
        b.box(xa, xa + 0.6, -4.0, -3.94, FL + 0.2, 2.2, "Coral", "detail")           # curtain (no collision)
        b.box(xa + 0.02, xa + 1.5, -5.7, -5.3, FL, FL + 0.45, "Wood", "interior", "-z -y")
        b.box(xa + 0.35, xa + 1.2, -5.7, -5.66, 0.7, 2.15, "Window", "interior", "-y")
    LK.counter(b, -4.4, -3.4, 0.0, 3.4, 0.75, 1.0, body="White", top="WoodDark", stripe="Teal")
    LK.register(b, -3.5, -3.45, 0.0, FL + 1.0)
    LK.shelf(b, -4.2, -5.47, 0.0, 5.6, 0.45, 2.3, 4, frame="White", goods=LK.CLOTHES, seed=3)
    for i, (rx, ry) in enumerate(((-4.7, 1.2), (-2.8, 1.2), (2.9, -0.6), (4.8, -0.6))):
        LK.clothes_rack(b, rx, ry, PI / 2, 3.0, seed=5 + i * 3)
    LK.shelf(b, -6.97, 0.6, -PI / 2, 5.4, 0.45, 2.2, 5, frame="White", goods=LK.CLOTHES, seed=17, fill=0.95)
    t = LK.table(b, 0.1, 0.2, 0.0, 2.0, 1.1, 0.8, top="White", leg="Chrome")
    LK.folded_stacks(t, 2.0, 1.1, 0.8, 4, seed=9)
    LK.rug(b, 0.1, 0.2, 3.4, 2.4, "Mint", "White")
    # window platforms with mannequins
    looks = (("Coral", "Denim"), ("Mustard", "Navy"), ("Teal", "Khaki"), ("Rose", "Charcoal"))
    for sgn in (-1, 1):
        cx = sgn * 4.1
        b.box(cx - 2.3, cx + 2.3, 4.5, 5.6, FL, FL + 0.25, "White", "interior", "-z")
        for k, dx in enumerate((-1.2, 1.2)):
            top, bot = looks[(k + (0 if sgn < 0 else 2)) % 4]
            mannequin(b, cx + dx, 5.05, 0.0, top, bot, z=FL + 0.25)
    # wall mirror + poster on the mint wall
    b.box(1.5, 2.9, -5.7, -5.66, 0.35, 2.45, "Navy", "interior", "-y")
    b.box(1.6, 2.8, -5.66, -5.65, 0.45, 2.35, "Window", "interior", "-y")
    LK.plant(b, 0.3, -5.25, 1.4)
    LK.plant(b, 6.8, 3.9, 1.2)

    b.marker("Use_Counter", -4.4, -2.4, FL, PI)
    b.marker("Use_Wardrobe", 4.72, -3.1, FL, PI)
    b.marker("Staff", -4.4, -4.5, FL, 0.0)
    b.floors = 1
    return b.finish(tags=["shop", "clothing", "midtown"], landmark="clothing_store", extra={"sign": "TIDE THREADS"})


# ------------------------------------------------------------------------------------------------
def general_store(slot):
    """Corner 24: cream corner store with a red wrap-around fascia and a neon "24" corner tower."""
    b = LK.LB("general_store", slot, dict(wall="Cream", wall2="White", base="Terracotta", trim="White", roof="RoofGrey",
                                          sign="CarRed", neon="NeonYellow", awning="CarRed", awning2="White", metal="Charcoal"))
    x0, x1, y0, y1 = -7.5, 7.5, -6.0, 6.0
    H, C = 4.0, 3.3
    rm = LK.Room(b, x0, x1, y0, y1, H, C)
    rm.wall("front", [LK.shopwin(-6.7, 2.5, 0.6, 2.9, nx=5), LK.door(3.3, 5.1, 2.5)])
    rm.wall("left", [LK.win(-2.2, 2.2, 1.6, 2.7, nx=2)])
    rm.wall("right")
    rm.wall("back")
    rm.tiles(("White", "WarmGrey"), 1.2)
    rm.ceiling("White")
    rm.lights(3, 2)
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")

    # --- exterior -------------------------------------------------------------------------------
    F.dado([(0.0, 2.26), (4.34, 15.0)], h=0.6, proud=0.08)
    for f in (R, B, L):
        f.dado(h=0.6, proud=0.08)
    F.box(-0.22, 15.0, 3.0, 3.9, 0.0, 0.22, "sign", "body", "k")
    R.box(0.0, 12.0, 3.0, 3.9, 0.0, 0.22, "sign", "body", "k")
    for f, ua, ub in ((F, -0.22, 15.0), (R, 0.0, 12.22)):
        f.rect(ua, ub, 3.05, 3.11, "White", 0.225, "detail")
        f.rect(ua, ub, 3.79, 3.85, "White", 0.225, "detail")
    F.text("CORNER 24", 9.6, 3.45, 0.105, "White", 0.23)
    F.text("OPEN 24H", 3.3, 3.45, 0.085, "NeonYellow", 0.23)
    R.text("CORNER 24", 4.4, 3.45, 0.105, "White", 0.23)
    R.text("COLD DRINKS - SNACKS - ICE", 5.6, 1.9, 0.085, "Terracotta", 0.02)
    F.awning(4.9, 14.3, 3.0, depth=1.25, drop=0.45, stripes=10)
    for i, m in enumerate(("Mustard", "SafetyOrange", "Teal")):          # window posters
        ua = 5.6 + i * 3.1
        F.rect(ua, ua + 1.1, 1.75, 2.65, m, -0.122, "detail")
        F.rect(ua + 0.12, ua + 0.98, 2.05, 2.5, "White", -0.118, "detail")
    b.flat_roof(rm.pts, H, parapet=0.5)
    # corner sign tower
    b.box(5.3, 7.5, 3.8, 6.0, H, 6.5, "sign", skip="-z")
    b.box(5.22, 7.58, 3.72, 6.08, 6.5, 6.66, "White", skip="-z")
    F.text("24", 1.1, 5.35, 0.24, "NeonYellow", 0.03)
    R.text("24", 10.9, 5.35, 0.24, "NeonYellow", 0.03)
    F.neon_line(0.1, 2.1, 6.25, 0.07, "NeonYellow")
    R.neon_line(9.9, 11.9, 6.25, 0.07, "NeonYellow")
    F.neon_line(0.1, 2.1, 4.5, 0.07, "NeonYellow")
    R.neon_line(9.9, 11.9, 4.5, 0.07, "NeonYellow")
    back_door(B, 4.0, "SteelDark")
    b.ac_unit(-3.0, -2.5, H)
    b.ac_unit(-0.8, -2.5, H)
    b.vent(2.5, -4.0, H)
    # forecourt props: ice chest, vending machine, newspaper boxes
    b.box(-7.2, -5.3, 6.0, 6.85, 0.0, 1.05, "White", skip="-z -y")
    b.box(-7.25, -5.25, 5.98, 6.9, 1.05, 1.13, "Sky", skip="-z")
    fc = b.face((-5.3, 6.85), (-7.2, 6.85))
    fc.text("ICE", 0.95, 0.62, 0.1, "CarBlue", 0.012)
    LK.vending(b, 6.45, 6.42, 0.0, "CarBlue", seed=5, z=0.0, part="body")
    for i, m in enumerate(("Mustard", "Teal")):
        xa = 2.2 + i * 0.5
        b.box(xa, xa + 0.44, 6.0, 6.4, 0.0, 1.0, m, skip="-z -y")
        b.box(xa + 0.06, xa + 0.38, 6.4, 6.41, 0.5, 0.9, "Sky", "detail", "-y")
    wall_lamp(F, 3.3, 2.66)
    b.entrance = (4.2, y1)

    # --- interior -------------------------------------------------------------------------------
    LK.fridge(b, -2.2, -5.32, 0.0, 9.6, doors=6, band="CarBlue", seed=3)
    # chest freezer
    f = LK.Fr(b, 5.0, -5.15, FL, 0.0)
    f.box(-0.95, 0.95, -0.42, 0.42, 0.0, 0.86, "White", "-z")
    f.box(-0.9, 0.9, -0.38, 0.38, 0.86, 0.9, "Sky", "-z")
    f.box(-0.03, 0.03, -0.42, 0.42, 0.86, 0.93, "Steel", "-z")
    f.box(-0.95, 0.95, 0.42, 0.44, 0.3, 0.62, "CarBlue", "-y")
    for i, gx in enumerate((-4.9, -2.3, 0.3)):
        LK.gondola(b, gx, -0.7, PI / 2, 4.6, 0.9, 1.5, 3, seed=11 + i * 5)
    LK.shelf(b, -6.97, -1.9, -PI / 2, 5.6, 0.42, 2.1, 4, seed=31)
    LK.counter(b, 5.6, 1.4, PI / 2, 3.6, 0.7, 1.02, body="White", top="Charcoal", stripe="CarRed")
    LK.register(b, 5.6, 2.3, PI / 2, FL + 1.02)
    cf = LK.Fr(b, 5.6, 0.4, FL + 1.02, PI / 2)                               # snack stand on the counter
    cf.box(-0.35, 0.35, -0.2, 0.15, 0.0, 0.1, "Mustard", "-z")
    cf.box(-0.35, 0.35, -0.2, 0.0, 0.1, 0.28, "CarRed", "-z")
    cf.box(-0.3, -0.05, 0.02, 0.12, 0.1, 0.2, "Teal", "-z")
    cf.box(0.05, 0.3, 0.02, 0.12, 0.1, 0.18, "Lavender", "-z")
    LK.shelf(b, 6.98, 1.4, PI / 2, 3.6, 0.4, 2.2, 5, frame="White", seed=41, fill=0.97)
    LK.shelf(b, -3.2, 5.47, PI, 3.2, 0.42, 1.15, 3, frame="Charcoal", goods=("White", "Sky", "Mustard", "Rose", "Cream"), seed=23)
    LK.rug(b, 4.2, 4.8, 2.0, 1.3, "Charcoal", "Black")
    # coffee corner
    LK.counter(b, 1.3, 5.3, PI, 1.8, 0.6, 0.95, body="White", top="Charcoal")
    cf = LK.Fr(b, 1.3, 5.3, FL + 0.95, PI)
    cf.box(-0.7, -0.25, -0.2, 0.2, 0.0, 0.55, "Charcoal", "-z")
    cf.box(-0.62, -0.33, 0.2, 0.21, 0.3, 0.5, "LampWarm", "-y")
    cf.box(0.0, 0.3, -0.18, 0.18, 0.0, 0.45, "CarRed", "-z")
    cf.box(0.38, 0.68, -0.18, 0.18, 0.0, 0.45, "CarBlue", "-z")

    b.marker("Use_Counter", 4.5, 1.4, FL, -PI / 2)
    b.marker("Staff", 6.5, 1.4, FL, PI / 2)
    b.marker("Register", 5.6, 2.3, FL + 1.02, PI / 2)
    b.floors = 1
    return b.finish(tags=["shop", "store", "waterfront"], landmark="general_store", extra={"sign": "CORNER 24"})


# ------------------------------------------------------------------------------------------------
def barber(slot):
    """Harbor Cuts: small cream pavilion under a red hip roof, barber pole, checkerboard floor."""
    b = LK.LB("barber", slot, dict(wall="Cream", wall2="Mint", base="Navy", trim="White", roof="RoofRed",
                                   sign="Navy", neon="NeonCyan", awning="CarRed", awning2="White", metal="Charcoal"))
    x0, x1, y0, y1 = -5.5, 5.5, -5.5, 5.5
    H, C = 3.8, 3.2
    rm = LK.Room(b, x0, x1, y0, y1, H, C)
    rm.wall("front", [LK.shopwin(-4.6, 0.3, 0.6, 2.75, nx=3), LK.door(1.1, 2.9, 2.5)])
    rm.wall("right", [LK.win(-2.6, 2.6, 1.4, 2.6, nx=3)])
    rm.wall("left")
    rm.wall("back")
    rm.tiles(("White", "Black"), 1.04)
    rm.ceiling("White")
    rm.lights(2, 2, 1.2)
    F, R, B, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")

    # --- exterior -------------------------------------------------------------------------------
    F.dado([(0.0, 2.46), (4.54, 11.0)], h=0.6, proud=0.08)
    for f in (R, B, L):
        f.dado(h=0.6, proud=0.08)
    b.belt(rm.pts, 3.5, h=0.3, proud=0.1, mat="trim")
    F.sign(4.95, 10.35, 2.9, 3.48, "HARBOR CUTS", board="sign", color="neon", border="NeonMagenta", pad=0.1)
    F.awning(2.35, 4.65, 3.3, depth=1.0, drop=0.4, stripes=4)
    b.hip_roof(x0, x1, y0, y1, H, 1.9, over=0.45)
    b.chimney(-3.0, -2.0, H + 0.6, H + 2.6, 0.6, 0.6, mat="Cream")
    # barber pole between window and door
    px, py = 0.7, y1 + 0.24
    cols = ("CarRed", "White", "CarBlue", "White")
    for i in range(10):
        b.cyl(px, py, 1.2 + i * 0.13, 1.33 + i * 0.13, 0.13, cols[i % 4], "detail", 8, caps="none")
    b.cyl(px, py, 1.08, 1.2, 0.17, "Chrome", "detail", 8, caps="both")
    b.cyl(px, py, 2.5, 2.62, 0.17, "Chrome", "detail", 8, caps="both")
    b.cyl(px, py, 2.62, 2.8, 0.11, "LampWarm", "detail", 8)
    for z in (1.12, 2.54):
        b.box(px - 0.04, px + 0.04, y1, py, z, z + 0.05, "Chrome", "detail")
    wall_lamp(F, 3.5, 2.62, 0.5)
    back_door(B, 8.0, "Navy")
    for f in (L, R):                                                         # painted stripe band
        f.rect(0.0, f.w, 2.95, 3.1, "CarRed", 0.012, "detail")
        f.rect(0.0, f.w, 3.16, 3.24, "CarBlue", 0.012, "detail")
    L.text("HARBOR CUTS", 5.5, 2.2, 0.13, "Navy", 0.02)
    b.entrance = (2.0, y1)

    # --- interior -------------------------------------------------------------------------------
    for i, sy in enumerate((-3.0, -0.6, 1.8)):
        LK.mirror_station(b, -5.2, sy, -PI / 2, 1.5)
        LK.barber_chair(b, -3.85, sy, PI / 2, ("Terracotta", "Terracotta", "Terracotta")[i])
    LK.seat_row(b, 4.75, 1.3, PI / 2, 4, "Teal")
    t = LK.table(b, 4.55, -1.5, 0.0, 0.8, 0.8, 0.48, top="WoodDark", leg="Chrome")
    t.box(-0.25, 0.1, -0.2, 0.15, 0.48, 0.5, "Coral", "-z")
    t.box(-0.05, 0.3, -0.05, 0.3, 0.5, 0.52, "Sky", "-z")
    LK.counter(b, 2.3, -3.6, 0.0, 2.4, 0.65, 1.0, body="Navy", top="White", stripe="CarRed")
    LK.register(b, 2.8, -3.65, 0.0, FL + 1.0)
    LK.shelf(b, 2.3, -4.98, 0.0, 3.4, 0.42, 2.1, 4, frame="White", goods=("Teal", "Coral", "White", "Mustard", "Navy", "Rose"), seed=8)
    # wash station
    f = LK.counter(b, -3.7, -4.88, 0.0, 2.2, 0.62, 0.9, body="White", top="White")
    f.box(-0.75, -0.15, -0.2, 0.22, 0.9, 1.0, "Chrome", "-z")
    f.box(-0.68, -0.22, -0.14, 0.16, 1.0, 1.005, "SteelDark", "-z -x +x -y +y")
    f.box(-0.47, -0.43, -0.3, -0.26, 0.9, 1.2, "Chrome", "-z")
    f.box(-0.47, -0.43, -0.3, -0.1, 1.18, 1.22, "Chrome")
    for i, c in enumerate(("Teal", "Coral", "Mustard")):
        f.box(0.3 + i * 0.2, 0.42 + i * 0.2, -0.15, -0.03, 0.9, 1.12, c, "-z")
    # coat stand
    b.cyl(-0.9, -4.9, FL, FL + 0.05, 0.25, "Charcoal", "interior", 8)
    b.cyl(-0.9, -4.9, FL + 0.05, FL + 1.8, 0.03, "WoodDark", "interior", 6)
    b.box(-1.15, -0.65, -4.92, -4.88, FL + 1.62, FL + 1.66, "WoodDark", "interior")
    b.box(-0.92, -0.88, -5.15, -4.65, FL + 1.7, FL + 1.74, "WoodDark", "interior")
    LK.plant(b, 4.7, 4.6, 1.3)
    LK.rug(b, 2.0, 4.3, 1.9, 1.3, "CarRed", "Navy")

    b.marker("Use_Chair", -3.85, -0.6, FL, PI / 2)
    b.marker("Staff", -2.8, -0.6, FL, PI / 2)
    b.floors = 1
    return b.finish(tags=["shop", "barber", "midtown"], landmark="barber", extra={"sign": "HARBOR CUTS"})


BUILD = {"gun_shop": gun_shop, "clothing_store": clothing_store, "general_store": general_store, "barber": barber}
VIEWS = {
    "gun_shop": dict(cut=2.9, shots=[((0.0, 5.3, 1.7), (-1.5, -5.0, 1.2)), ((-6.6, -1.2, 1.75), (5.5, -5.0, 1.0)),
                                     ((6.6, 5.0, 1.8), (-4.0, -5.0, 1.0)), ((0.0, 14.0, 1.7), (0.0, 0.0, 2.2))]),
    "clothing_store": dict(cut=3.1, shots=[((0.0, 5.3, 1.7), (-1.0, -5.0, 1.2)), ((-6.6, -4.8, 1.75), (5.0, 3.0, 1.0)),
                                           ((6.6, 4.0, 1.8), (3.5, -5.5, 1.0)), ((-2.0, 14.0, 1.7), (0.0, 0.0, 2.6))]),
    "general_store": dict(cut=2.9, shots=[((4.2, 5.3, 1.7), (-3.0, -5.0, 1.0)), ((-6.5, 4.6, 1.75), (6.0, -1.0, 1.0)),
                                          ((1.8, -4.2, 1.8), (6.5, 3.0, 1.0)), ((3.0, 14.0, 1.7), (1.0, 0.0, 2.2))]),
    "barber": dict(cut=2.9, shots=[((2.0, 4.8, 1.7), (-3.5, -3.0, 1.0)), ((4.6, -4.4, 1.75), (-4.5, 1.5, 1.0)),
                                   ((-1.0, 3.5, 1.8), (3.0, -5.0, 1.0)), ((1.5, 12.0, 1.7), (0.0, 0.0, 2.0))]),
}
