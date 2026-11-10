"""Civic landmarks: police_station (HBPD), hospital (Halcyon General), safehouse (loft + garage).
See buildings_landmarks.py (entry) and landmark_kit.py (helpers)."""
import math

import gta_bl as G
import building_kit as K
import landmark_kit as LK

PI = math.pi
FL = LK.FLOOR


def _monitor(b, x, y, z, yaw=0.0):
    """Desk monitor; the screen faces local -Y."""
    f = LK.Fr(b, x, y, z, yaw)
    f.box(-0.12, 0.12, -0.08, 0.08, 0.0, 0.02, "Charcoal", "-z")
    f.box(-0.03, 0.03, -0.02, 0.02, 0.02, 0.14, "Charcoal", "-z +z")
    f.box(-0.3, 0.3, -0.025, 0.025, 0.12, 0.5, "Black")
    f.box(-0.27, 0.27, -0.031, -0.025, 0.15, 0.47, LK.smat("M_ScreenGlow", "Sky"), "+y")


def _painted_door(face, uc, mat="door", w=1.1, h=2.2, part="interior", z=FL):
    face.box(uc - w / 2 - 0.08, uc + w / 2 + 0.08, z, z + h + 0.08, 0.0, 0.03, "trim", part, "k b")
    face.box(uc - w / 2, uc + w / 2, z, z + h, 0.03, 0.06, mat, part, "k b")
    face.box(uc + w / 2 - 0.2, uc + w / 2 - 0.14, z + 0.95, z + 1.15, 0.06, 0.11, "Chrome", part, "k")


# ------------------------------------------------------------------------------------------------
def police_station(slot):
    """HBPD station: two-storey L-shaped block, portico entrance, shield pediment, walk-in lobby with
    front desk, motor-pool canopy with four bays in the notch of the L."""
    b = LK.LB("police_station", slot, dict(wall="White", wall2="Cream", base="WarmGrey", trim="PoliceBlue", roof="RoofGrey",
                                           sign="PoliceBlue", neon="NeonBlue", door="Navy", metal="Charcoal", accent="PoliceBlue"))
    G1, G2 = 4.0, 3.6
    HA = G1 + G2
    A = b.mass(-13.85, 0.0, -11.0, 9.0, solid=False)
    Bm = b.mass(0.0, 13.85, -11.0, 0.5)
    Wg = K.win(1.8, 1.7, 0.95, frame="trim", sill_bar="trim", bars=(2, 2))
    Wu = K.win(2.0, 1.8, 0.8, frame="trim", sill_bar="trim", bars=(2, 1))

    # --- block A, ground floor: lobby walls are thick, the rest is a solid shell ------------------
    LK.twall(A.front, 0.0, G1, [LK.shopwin(-13.0, -9.4, 0.6, 3.0, nx=2), LK.door(-8.2, -5.8, 2.6),
                                LK.shopwin(-4.6, -1.0, 0.6, 3.0, nx=2)], mat="base", imat="wall2", iv=(FL, 3.4))
    fa = A.left.sub(0.0, 8.0)
    LK.twall(fa, 0.0, G1, [LK.win(3.0, 7.0, 1.0, 2.6, nx=2)], mat="base", imat="wall2", inner=(0.3, 8.0), iv=(FL, 3.4))
    A.left.sub(8.0, 20.0).row(0.0, G1, [Wg] * 3, "base")
    fr = A.right.sub(11.5, 20.0)
    LK.twall(fr, 0.0, G1, [LK.door(3.6, 5.4, 2.5)], mat="base", imat="wall2", inner=(0.5, 8.2), iv=(FL, 3.4))
    A.back.row(0.0, G1, [Wg, Wg, K.door(1.1, 2.2, mat="door", frame="trim"), Wg], "base")
    # upper storey
    A.front.row(G1, G2, [Wu, None, None, Wu])
    A.left.row(G1, G2, [Wu] * 5)
    A.right.row(G1, G2, [Wu] * 5)
    A.back.row(G1, G2, [Wu] * 4)
    b.belt(A.pts, 3.72, h=0.42, proud=0.1, mat="accent")
    b.flat_roof(A.pts, HA, parapet=0.8)
    b.solid(-13.85, 0.0, -11.0, 0.7, 0.0, HA)
    b.solid(-13.85, 0.0, 0.7, 9.0, G1, HA)
    # pediment with the shield, letters
    b.box(-9.8, -4.2, 8.6, 9.0, HA, 10.5, "wall", skip="-z")
    b.box(-9.9, -4.1, 8.54, 9.06, 10.5, 10.68, "trim", skip="-z")
    LK.emblem_shield(A.front, 7.0, 9.02, 2.05)
    A.front.text("HBPD", 7.0, 5.95, 0.27, "PoliceBlue", 0.03)
    # portico
    b.box(-11.2, -2.8, 9.0, 11.7, 3.1, 3.56, "PoliceBlue", skip="-y")
    b.box(-11.2, -2.8, 9.0, 11.7, -0.3, FL, "Concrete", skip="-z -y")
    for cx in (-10.6, -3.4):
        b.box(cx - 0.26, cx + 0.26, 10.95, 11.47, FL, 3.1, "White", skip="-z +z")
        b.box(cx - 0.3, cx + 0.3, 10.91, 11.51, FL, FL + 0.5, "PoliceBlue", skip="-z")
        b.box(cx - 0.15, cx + 0.15, 11.47, 11.62, 2.15, 2.6, "NeonBlue", "detail")
    pf = b.face((-2.8, 11.7), (-11.2, 11.7))
    pf.rect(0.0, 8.4, 3.14, 3.18, "White", 0.012, "detail")
    pf.text("POLICE", 4.2, 3.37, 0.058, "White", 0.012)
    # lobby floor / ceiling / back partition
    b.poly(((-13.55, 1.0, FL), (-0.3, 1.0, FL), (-0.3, 8.7, FL), (-13.55, 8.7, FL)), "Cream")
    b.poly(((-13.55, 8.7, 3.4), (-0.3, 8.7, 3.4), (-0.3, 1.0, 3.4), (-13.55, 1.0, 3.4)), "White")
    bp = b.face((-0.3, 1.0), (-13.55, 1.0))           # looks +Y into the lobby; u = -0.3 - x
    bp.rect(0.0, bp.w, FL, 3.4, "wall2")
    for i in range(3):
        for j in range(2):
            LK.ceiling_light(b, -11.5 + i * 4.5, 3.0 + j * 3.6, 3.4)
    # flag pole
    b.cyl(-12.9, 10.6, 0.0, 9.6, 0.06, "Chrome", "detail", 6)
    b.cyl(-12.9, 10.6, 9.6, 9.8, 0.1, "BadgeGold", "detail", 6)
    b.box(-12.84, -11.3, 10.58, 10.62, 8.3, 9.3, "PoliceBlue", "detail")
    b.box(-12.84, -11.3, 10.57, 10.63, 8.72, 8.88, "BadgeGold", "detail")
    # roof kit
    b.antenna(-3.0, -8.0, HA, 6.5)
    b.dish(-1.6, -8.4, HA)
    b.ac_unit(-10.5, -6.0, HA)
    b.ac_unit(-8.3, -6.0, HA)
    b.stair_box(-12.5, -9.5, 2.0, 5.0, HA, 2.6, door="right")
    b.skylight(-7.0, -3.5, 1.5, 5.0, HA)

    # --- wing B (vehicle workshop / cells) ----------------------------------------------------------
    RU = K.rollup(3.0, 3.1, mat="PoliceBlue", lights=True, frame="trim")
    cell = K.win(1.0, 0.6, 2.6, frame="trim", bars=(3, 1))
    Bm.front.row(0.0, 4.2, [RU, RU, RU, K.door(1.1, 2.2, mat="door", frame="trim")], "base")
    Bm.right.row(0.0, 4.2, [cell] * 3, "base")
    Bm.back.row(0.0, 4.2, [cell, cell, K.louvre(), cell], "base")
    b.flat_roof(Bm.pts, 4.2, parapet=0.5, wall="base")
    b.belt(Bm.pts, 3.72, h=0.42, proud=0.1, mat="accent", edges=[0, 1])
    b.ac_unit(5.0, -6.0, 4.2)
    b.ac_unit(9.5, -6.0, 4.2, turn=True)
    b.vent(11.5, -3.0, 4.2)
    Bm.right.text("HBPD", 5.75, 1.5, 0.16, "PoliceBlue", 0.02)

    # --- motor pool canopy -----------------------------------------------------------------------
    b.box(0.0, 13.85, 0.5, 9.3, -0.3, 0.05, "AsphaltLight", skip="-z -y")
    b.box(0.3, 13.75, 0.5, 8.9, 3.3, 3.62, "PoliceBlue", skip="-y")
    cf = b.face((13.75, 8.9), (0.3, 8.9))
    cf.rect(0.0, 13.45, 3.33, 3.37, "White", 0.012, "detail")
    cf.text("HALCYON BAY POLICE", 6.8, 3.49, 0.036, "White", 0.012)
    for px in (0.55, 3.9, 7.2, 10.5, 13.5):
        b.box(px - 0.11, px + 0.11, 8.45, 8.67, 0.05, 3.3, "Steel", skip="-z +z")
    for px in (3.9, 7.2, 10.5):
        LK.hrect(b, px - 0.07, px + 0.07, 1.0, 8.4, 0.062, "RoadLine")
    bays = (2.2, 5.55, 8.85, 11.95)
    for i, cx in enumerate(bays):
        b.box(cx - 0.9, cx + 0.9, 1.2, 1.42, 0.05, 0.18, "Concrete", skip="-z")
        LK.ceiling_light(b, cx, 4.6, 3.3, 0.4, 2.2)
        b.marker("Spawn_Car_%d" % (i + 1), cx, 4.9, 0.05, 0.0)

    # --- lobby interior -----------------------------------------------------------------------------
    LK.counter(b, -7.0, 3.1, 0.0, 6.0, 0.8, 1.1, body="PoliceBlue", top="White", stripe="BadgeGold")
    b.box(-10.0, -4.0, 3.43, 3.5, FL + 1.98, FL + 2.08, "Steel", "interior")
    for px in (-9.97, -8.0, -6.0, -4.03):
        b.box(px - 0.03, px + 0.03, 3.43, 3.5, FL + 1.1, FL + 1.98, "Steel", "interior", "-z +z")
    _monitor(b, -8.6, 2.95, FL + 1.1)
    _monitor(b, -5.4, 2.95, FL + 1.1)
    LK.emblem_shield(bp, 6.7, 2.3, 1.25, d=0.02, part="interior")
    _painted_door(bp, 1.4)
    _painted_door(bp, 12.2)
    LK.notice_board(bp, 9.0, 11.0, 1.2, 2.3, seed=6)
    LK.seat_row(b, -11.3, 8.3, PI, 4, "PoliceBlue")
    LK.seat_row(b, -2.9, 8.3, PI, 4, "PoliceBlue")
    LK.vending(b, -13.1, 2.0, -PI / 2, "CarBlue", seed=3)
    LK.plant(b, -12.95, 8.1, 1.4)
    LK.plant(b, -0.9, 7.9, 1.4)
    LK.plant(b, -0.9, 1.6, 1.2)
    LK.rug(b, -7.0, 5.9, 3.4, 2.2, "PoliceBlue", "BadgeGold")

    b.marker("Use_Desk", -7.0, 4.25, FL, PI)
    b.marker("Spawn_Officer_1", -7.0, 12.9, 0.0, 0.0)
    b.marker("Spawn_Officer_2", 7.0, 10.4, 0.0, 0.0)
    b.entrance = (-7.0, 9.0)
    b.floors = 2
    return b.finish(tags=["civic", "police", "midtown"], landmark="police_station", extra={"sign": "HBPD"})


# ------------------------------------------------------------------------------------------------
def _gurney(b, x, y, yaw):
    f = LK.Fr(b, x, y, FL, yaw)
    for sx in (-0.3, 0.3):
        for sy in (-0.8, 0.8):
            f.box(sx - 0.025, sx + 0.025, sy - 0.025, sy + 0.025, 0.1, 0.6, "Chrome", "-z +z")
            f.box(sx - 0.04, sx + 0.04, sy - 0.06, sy + 0.06, 0.0, 0.12, "Black", "-z")
    f.box(-0.36, 0.36, -0.98, 0.98, 0.6, 0.66, "Steel")
    f.box(-0.33, 0.33, -0.95, 0.95, 0.66, 0.78, "White", "-z")
    f.box(-0.25, 0.25, -0.9, -0.55, 0.78, 0.86, "Sky", "-z")
    f.box(-0.34, 0.34, -0.1, 0.95, 0.78, 0.82, "Mint", "-z")


def hospital(slot):
    """Halcyon General: five-storey ward tower with mint bands and a teal emblem fin, walk-in lobby
    podium, ambulance canopy, rooftop helipad."""
    b = LK.LB("hospital", slot, dict(wall="White", wall2="Cream", base="WarmGrey", trim="Mint", roof="RoofGrey",
                                     accent="Teal", sign="Navy", neon="NeonCyan", door="Teal", metal="Charcoal"))
    G1, FH, NF = 4.2, 3.5, 4
    HT = G1 + FH * NF
    Tm = b.mass(-15.0, 15.0, -13.0, 2.0)
    Wg = K.win(1.8, 1.7, 0.95, frame="trim", sill_bar="trim")
    Wu = K.win(2.2, 1.7, 0.85, frame="trim", bars=(2, 1))
    for f, n in ((Tm.left, 5), (Tm.right, 5), (Tm.back, 10)):
        f.stack(0.0, [(G1, [Wg] * n, "base")] + [(FH, [Wu] * n)] * NF)
    TF = Tm.front                                    # u = 15 - x
    fs = TF.sub(0.0, 13.0)                           # under the ambulance canopy
    fs.row(0.0, G1, [None, K.door(2.6, 2.6, double=True, glass=0.45, mat="White", frame="accent"),
                     K.win(1.8, 1.7, 0.95, frame="trim", sill_bar="trim", count=2, gap=1.3)], "base", widths=[1.55, 4.0, 7.45])
    TF.sub(28.0, 30.0).rect(0.0, 2.0, 0.0, G1, "base")
    v = G1
    for i in range(NF):
        TF.row(v, FH, [Wu] * 8, u0=5.6, u1=29.6)
        v += FH
    TF.top = HT
    for k in range(NF + 1):
        b.belt(Tm.pts, G1 + FH * k - 0.16, h=0.32, proud=0.1, mat="trim")
    b.flat_roof(Tm.pts, HT, parapet=1.0)
    # teal emblem fin above the emergency side
    b.box(10.0, 15.0, 2.0, 2.6, 4.5, HT + 2.7, "accent", skip="-y")
    b.box(9.9, 15.1, 1.9, 2.7, HT + 2.7, HT + 2.9, "White")
    bf = b.face((15.0, 2.6), (10.0, 2.6))
    LK.emblem_heart(bf, 2.5, HT + 0.3, 1.8)
    for k in range(3):
        for ua in (0.7, 3.8):
            bf.pane(ua, ua + 0.5, G1 + FH * k + 0.9, G1 + FH * k + 2.7, 0.02)
    b.roof_sign("HALCYON GENERAL", -3.2, 1.5, HT + 1.1, px=0.27, color="NeonCyan", board="Navy")
    # helipad
    hx, hy = -5.5, -6.0
    LK.hdisc(b, hx, hy, 5.4, HT + 0.03, "Asphalt", 16)
    LK.hring(b, hx, hy, 4.3, 4.75, HT + 0.05, "RoadLine", 16)
    for (xa, xb, ya, yb) in ((-1.5, -0.9, -2.0, 2.0), (0.9, 1.5, -2.0, 2.0), (-0.9, 0.9, -0.3, 0.3)):
        LK.hrect(b, hx + xa, hx + xb, hy + ya, hy + yb, HT + 0.05, "RoadLine")
    b.stair_box(8.5, 12.5, -11.5, -7.5, HT, 2.8, door="left")
    b.ac_unit(5.0, -3.5, HT)
    b.ac_unit(7.2, -3.5, HT)
    b.ac_unit(9.4, -3.5, HT)
    b.vent(3.0, -10.5, HT)
    b.antenna(10.5, -9.5, HT + 2.98, 4.0)

    # --- lobby podium (walk-in) -------------------------------------------------------------------
    rm = LK.Room(b, -13.0, 2.0, 2.0, 10.5, 4.6, 3.6)
    rm.wall("front", [LK.shopwin(-12.2, -7.6, 0.5, 3.1, nx=3), LK.door(-6.7, -4.3, 2.7), LK.shopwin(-3.4, 1.2, 0.5, 3.1, nx=3)])
    rm.wall("left", [LK.win(4.0, 8.6, 0.9, 3.0, nx=2)])
    rm.wall("right", [LK.door(5.0, 6.8, 2.5)])
    bk = b.face((1.7, 2.3), (-12.7, 2.3))            # inner face of the tower wall; u = 1.7 - x
    bk.rect(0.0, bk.w, FL, 3.6, "wall2")
    rm.tiles(("White", "Mint"), 1.45)
    rm.ceiling("White")
    rm.lights(3, 2)
    F = rm.face("front")                              # u = 2 - x
    F.dado([(0.0, 6.16), (8.84, 15.0)], h=0.5, proud=0.08)
    rm.face("left").dado(h=0.5, proud=0.08)
    b.flat_roof(rm.pts, 4.6, parapet=0.6)
    b.belt(rm.pts, 3.95, h=0.35, proud=0.1, mat="trim", edges=[1, 2, 3])
    F.text("HALCYON GENERAL", 11.6, 4.72, 0.085, "Teal", 0.02)
    LK.emblem_heart(F, 1.9, 4.25, 0.62, d=0.12)
    # entrance canopy
    b.box(-8.6, -2.4, 10.5, 12.9, 3.36, 3.76, "White", skip="-y")
    b.box(-8.6, -2.4, 10.5, 12.9, -0.3, FL, "Concrete", skip="-z -y")
    for cx in (-8.1, -2.9):
        b.cyl(cx, 12.4, FL, 3.36, 0.2, "accent", "body", 8, caps="none")
    ef = b.face((-2.4, 12.9), (-8.6, 12.9))
    ef.rect(0.0, 6.2, 3.4, 3.72, "Teal", 0.012, "detail")
    ef.text("MAIN ENTRANCE", 3.1, 3.56, 0.042, "White", 0.024)
    # --- ambulance canopy -------------------------------------------------------------------------
    b.box(2.0, 15.0, 2.0, 12.9, -0.3, 0.05, "AsphaltLight", skip="-z")
    b.box(2.0, 15.0, 2.0, 12.5, 4.0, 4.45, "White", skip="-y")
    cf = b.face((15.0, 12.5), (2.0, 12.5))
    cf.rect(0.0, 13.0, 4.04, 4.41, "FireRed", 0.012, "detail")
    cf.text("EMERGENCY", 6.5, 4.225, 0.052, "White", 0.024)
    sf = b.face((15.0, 2.0), (15.0, 12.5))
    sf.rect(0.0, 10.5, 4.04, 4.41, "FireRed", 0.012, "detail")
    sf.text("EMERGENCY", 5.25, 4.225, 0.052, "White", 0.024)
    for (cx, cy) in ((14.5, 12.0), (14.5, 7.0), (8.3, 12.0), (2.5, 12.0)):
        b.box(cx - 0.2, cx + 0.2, cy - 0.2, cy + 0.2, 0.05, 4.0, "White", skip="-z +z")
        b.box(cx - 0.24, cx + 0.24, cy - 0.24, cy + 0.24, 0.05, 0.9, "accent", skip="-z")
    ax, ay = 11.45, 7.4
    for (xa, xb, ya, yb) in ((-1.9, 1.9, -4.0, -3.85), (-1.9, 1.9, 3.85, 4.0), (-1.9, -1.75, -3.85, 3.85), (1.75, 1.9, -3.85, 3.85)):
        LK.hrect(b, ax + xa, ax + xb, ay + ya, ay + yb, 0.062, "HazardYellow")
    for cx in (5.4, 11.45):
        LK.ceiling_light(b, cx, 7.2, 4.0, 0.4, 3.0)
    b.box(11.15, 11.75, 2.0, 2.16, 3.1, 3.3, LK.beacon(), "detail")

    # --- lobby interior ----------------------------------------------------------------------------
    LK.counter(b, -5.5, 4.5, 0.0, 5.2, 0.85, 1.1, body="White", top="Teal", stripe="Mint")
    LK.counter(b, -7.8, 3.3, PI / 2, 1.55, 0.6, 1.1, body="White", top="Teal")
    LK.counter(b, -3.2, 3.3, -PI / 2, 1.55, 0.6, 1.1, body="White", top="Teal")
    _monitor(b, -6.6, 4.35, FL + 1.1)
    _monitor(b, -4.4, 4.35, FL + 1.1)
    LK.office_chair(b, -6.6, 3.4, 0.0, "Teal")
    LK.office_chair(b, -4.4, 3.4, 0.0, "Teal")
    LK.emblem_heart(bk, 7.2, 2.35, 0.68, d=0.02, part="interior")
    bk.text("RECEPTION", 7.2, 3.3, 0.055, "Teal", 0.02, "interior")
    for ex in (-0.9, 0.7):                             # lift doors
        u = 1.7 - ex
        bk.box(u - 0.72, u + 0.72, FL, 2.42, 0.0, 0.03, "trim", "interior", "k b")
        bk.box(u - 0.62, u + 0.62, FL, 2.3, 0.03, 0.05, "Steel", "interior", "k b")
        bk.box(u - 0.012, u + 0.012, FL, 2.3, 0.05, 0.056, "SteelDark", "interior", "k b")
        bk.box(u - 0.18, u + 0.18, 2.5, 2.62, 0.0, 0.03, "LampWarm", "interior", "k")
    bk.box(1.7 + 0.1 - 0.07, 1.7 + 0.1 + 0.07, 1.1, 1.35, 0.0, 0.03, "Charcoal", "interior", "k")
    LK.seat_row(b, -12.25, 6.3, -PI / 2, 5, "Teal")
    LK.seat_row(b, -9.9, 6.3, PI / 2, 5, "Teal")
    t = LK.table(b, -11.07, 6.3, 0.0, 0.7, 1.5, 0.42, top="White", leg="Chrome")
    t.box(-0.2, 0.15, -0.4, -0.1, 0.42, 0.45, "Coral", "-z")
    t.box(-0.1, 0.25, 0.1, 0.45, 0.42, 0.44, "Sky", "-z")
    LK.vending(b, 1.25, 3.4, PI / 2, "Teal", seed=7)
    LK.vending(b, 1.25, 8.5, PI / 2, "Coral", seed=9)
    _gurney(b, -1.2, 9.3, PI / 2)
    LK.plant(b, -12.2, 9.7, 1.5)
    LK.plant(b, -12.2, 2.9, 1.5)
    LK.plant(b, -8.6, 9.7, 1.3)
    LK.notice_board(rm.inner["left"], 0.4, 1.9, 1.3, 2.4, seed=12)
    LK.hrect(b, -5.7, -5.3, 5.5, 10.2, FL + 0.012, "Coral")
    LK.hrect(b, -5.7, 1.7, 5.5, 5.9, FL + 0.012, "Coral")

    b.marker("Respawn", -5.5, 13.8, 0.0, 0.0)
    b.marker("Use_Reception", -5.5, 5.75, FL, PI)
    b.marker("Spawn_Ambulance", ax, ay, 0.05, 0.0)
    b.entrance = (-5.5, 10.5)
    b.floors = 5
    return b.finish(tags=["civic", "hospital", "midtown"], landmark="hospital",
                    extra={"sign": "HALCYON GENERAL", "helipad": [hx, HT, -hy, 5.4]})


# ------------------------------------------------------------------------------------------------
def safehouse(slot):
    """Player safehouse: white two-storey loft under a mono-pitch roof (living room, kitchen corner,
    desk, wardrobe; bed on the mezzanine) with an attached timber-clad single garage (open front)."""
    b = LK.LB("safehouse", slot, dict(wall="White", wall2="Cream", base="ConcreteDark", trim="Charcoal", roof="Charcoal",
                                      door="Teal", metal="Charcoal", accent="Teal", neon="NeonCyan", sign="Charcoal"))
    hx0, hx1, hy0, hy1 = -9.0, 3.5, -7.0, 6.0
    H, C, MZ = 6.6, 6.3, 3.3
    rm = LK.Room(b, hx0, hx1, hy0, hy1, H, C)
    rm.wall("front", [LK.win(-8.0, -2.2, 0.5, 5.4, nx=3, transom=2.5, sill_bar=False), LK.door(-1.0, 0.8, 2.5),
                      LK.win(1.3, 2.9, 3.6, 5.4)])
    rm.wall("left", [LK.win(-6.0, -4.2, 1.2, 2.4), LK.win(-3.6, -1.2, 4.3, 5.6, nx=2)])
    rm.wall("back", [LK.win(-3.0, 0.2, 4.3, 5.6, nx=2), LK.win(0.8, 2.6, 1.15, 2.4)])
    rm.wall("right", [LK.win(-5.6, -3.2, 4.3, 5.6, nx=2), LK.door(1.0, 2.6, 2.4, frame=False)])
    rm.floor("Wood")
    rm.ceiling("White")
    F = rm.face("front")                              # u = 3.5 - x
    b.shed_roof(hx0, hx1, hy0, hy1, H, 8.2, high="front", over=0.33)
    # mezzanine + balustrade + stair (solid ramp for collision, visual treads on top)
    b.box(-8.7, 3.2, -6.7, -0.5, MZ - 0.25, MZ, "White", skip="+z -x +x -y")
    b.poly(((-8.7, -6.7, MZ), (3.2, -6.7, MZ), (3.2, -0.5, MZ), (-8.7, -0.5, MZ)), "TrunkLight")
    b.box(-7.4, 3.2, -0.5, -0.38, MZ, MZ + 1.0, "White", skip="-z")
    b.box(-7.46, 3.2, -0.55, -0.33, MZ + 1.0, MZ + 1.06, "Wood", skip="+x")
    b.prism([(5.2, FL), (-0.5, FL), (-0.5, MZ)], -8.7, -7.4, "x", "White")
    n = 18
    rise = (MZ - FL) / n
    run = 5.7 / n
    for i in range(n):
        ya = 5.2 - i * run
        zt = FL + (i + 1) * rise
        b.box(-8.69, -7.41, ya - run, ya, zt - rise, zt, "Wood", "detail", "-z -x -y")
    b.extrude([(-7.44, 5.2, FL + 0.92), (-7.44, -0.5, MZ + 0.92), (-7.44, -0.5, MZ + 1.0), (-7.44, 5.2, FL + 1.0)],
              (0.07, 0.0, 0.0), "Wood", "interior")
    for t in (0.0, 0.34, 0.67, 1.0):
        yy = 5.17 - 5.64 * t
        zz = FL + (MZ - FL) * (5.2 - yy) / 5.7
        b.box(-7.44, -7.37, yy - 0.03, yy + 0.03, zz, zz + 0.93, "Charcoal", "interior", "-z +z")

    # --- garage -------------------------------------------------------------------------------------
    GH, GC = 3.5, 3.1
    gm = b.mass(3.5, 8.6, -2.6, 5.4, solid=False)
    LK.twall(gm.front, 0.0, GH, [LK.gap(3.9, 8.0, FL, 2.8)], mat="Wood", imat="wall2", inner=(0.3, 5.1), iv=(FL, GC))
    LK.twall(gm.right, 0.0, GH, [], mat="Wood", imat="wall2", iv=(FL, GC))
    LK.twall(gm.back, 0.0, GH, [], mat="Wood", imat="wall2", inner=(0.0, 4.8), iv=(FL, GC))
    b.poly(((3.5, -2.3, FL), (8.3, -2.3, FL), (8.3, 5.1, FL), (3.5, 5.1, FL)), "Concrete")
    b.poly(((3.5, 5.1, GC), (8.3, 5.1, GC), (8.3, -2.3, GC), (3.5, -2.3, GC)), "White")
    b.poly(((3.9, 5.4, FL), (8.0, 5.4, FL), (8.0, 6.0, 0.0), (3.9, 6.0, 0.0)), "Concrete")
    b.flat_roof(gm.pts, GH, parapet=0.4, wall="Wood")
    b.box(3.9, 8.0, 4.72, 5.08, 2.84, 3.1, "Steel", "interior")
    b.dish(7.6, -1.6, GH)
    b.ac_unit(5.6, 1.0, GH)
    gm.front.frame(0.6, 4.7, FL, 2.8, w=0.14, proud=0.06, back=0.0, mat="trim")

    # --- exterior details -----------------------------------------------------------------------------
    # timber panel around the upper window (matches the garage cladding)
    for (ua, ub, va, vb) in ((0.0, 0.6, 2.95, 6.6), (2.2, 5.1, 2.95, 6.6), (0.6, 2.2, 2.95, 3.6), (0.6, 2.2, 5.4, 6.6)):
        F.box(ua, ub, va, vb, 0.0, 0.06, "Wood", "body", "k")
    F.canopy(2.2, 5.0, 2.72, depth=1.3, th=0.14, mat="Wood")
    F.text("12", 1.7, 2.05, 0.07, "Charcoal", 0.02)
    F.box(1.35, 1.95, 2.42, 2.52, 0.0, 0.26, "Charcoal", "detail", "k")
    F.box(1.42, 1.88, 2.38, 2.42, 0.04, 0.22, "LampWarm", "detail", "k t")
    b.box(-1.6, 1.4, 6.0, 7.3, -0.3, FL, "Concrete", skip="-z -y")
    b.box(-8.0, -2.2, 6.0, 6.55, 0.0, 0.45, "ConcreteDark", skip="-z -y")
    b.box(-7.9, -2.3, 6.08, 6.47, 0.45, 0.78, "Leaf", "detail", "-z")
    key = b.sub("Door_1", origin=(-0.98, 5.72, FL), rot_z=math.radians(-100.0))
    b.box(-0.98, 0.78, 5.7, 5.75, FL, 2.48, "door", key)
    b.box(-0.5, 0.3, 5.694, 5.756, 1.5, 2.1, "Window", key)
    b.box(0.56, 0.63, 5.66, 5.79, 1.0, 1.14, "Chrome", key)

    # --- ground floor ---------------------------------------------------------------------------------
    LK.tv_unit(b, -7.05, 1.6, -PI / 2)
    LK.sofa(b, -3.6, 1.6, PI / 2, 2.4)
    LK.table(b, -5.25, 1.6, PI / 2, 1.2, 0.6, 0.4, top="Wood", leg="Charcoal")
    LK.rug(b, -5.2, 1.6, 2.6, 3.4, "Teal", "Cream")
    LK.sofa(b, -5.0, 4.5, PI, 1.05, 0.9, "Coral", "Peach")
    LK.plant(b, -6.8, 4.9, 1.5)
    LK.plant(b, 2.7, -0.3, 1.3)
    LK.wardrobe(b, 2.88, 4.3, PI / 2, 1.8, 0.6, 2.2)
    LK.desk(b, 1.7, -6.32, 0.0, 1.6)
    LK.office_chair(b, 1.7, -5.45, PI)
    books = ("Navy", "Coral", "Mustard", "Teal", "Cream", "Charcoal", "CarRed")
    LK.shelf(b, -1.3, -6.48, 0.0, 2.2, 0.42, 2.0, 4, frame="Wood", goods=books, seed=14, fill=0.95)
    LK.kitchen_run(b, -5.55, -6.39, 0.0, 4.6)
    LK.tall_fridge(b, -8.3, -6.32, 0.0)
    LK.counter(b, -5.5, -3.7, 0.0, 2.6, 0.8, 0.95, body="White", top="Wood")
    for sx in (-6.3, -5.5, -4.7):
        LK.stool(b, sx, -2.95)
    LK.ceiling_light(b, -5.5, -3.7, MZ - 0.25, 1.6, 0.3)
    LK.ceiling_light(b, 0.6, -3.8, MZ - 0.25, 1.4, 0.3)
    LK.ceiling_light(b, -3.5, 2.6, C, 2.0, 0.4)
    LK.ceiling_light(b, 0.8, 2.6, C, 1.6, 0.4)
    LK.ceiling_light(b, 5.9, 1.4, GC, 1.6, 0.35)
    # --- mezzanine --------------------------------------------------------------------------------------
    with LK.at_floor(MZ):
        LK.bed(b, -2.6, -5.5, 0.0, 1.7, 2.1, "Wood", "Teal")
        LK.wardrobe(b, 2.88, -4.3, PI / 2, 1.8, 0.6, 0.95, mat="Wood", door="Cream", doors=3)
        LK.sofa(b, -6.4, -5.9, 0.0, 1.05, 0.9, "Mustard", "Cream")
    for sx in (-4.1, -1.35):
        b.box(sx, sx + 0.5, -6.65, -6.2, MZ, MZ + 0.5, "Wood", "interior", "-z")
        b.cyl(sx + 0.25, -6.42, MZ + 0.5, MZ + 0.72, 0.04, "Charcoal", "interior", 6, caps="none")
        b.cyl(sx + 0.25, -6.42, MZ + 0.72, MZ + 0.95, 0.14, "LampWarm", "interior", 6, r2=0.09)
    LK.rug(b, -2.6, -3.2, 2.8, 1.5, "Coral", "Cream", z=MZ)
    LK.plant(b, 2.6, -1.3, 1.3, z=MZ)
    # --- garage fit-out ---------------------------------------------------------------------------------
    LK.workbench(b, 5.9, -1.9, 0.0, 2.4, 0.7)
    LK.shelf(b, 8.07, 0.8, PI / 2, 2.2, 0.45, 1.9, 3, frame="SteelDark", goods=("Wood", "WarmGrey", "OliveDrab", "CarRed"), seed=77)
    LK.tyre_stack(b, 7.85, -1.85, 3)
    LK.barrel(b, 4.0, -1.85, "CarBlue")

    b.marker("Use_Bed", -0.95, -5.4, MZ, PI / 2)
    b.marker("Use_Wardrobe", 1.7, 4.3, FL, -PI / 2)
    b.marker("Use_Save", 1.7, -5.25, FL, PI)
    b.marker("Garage_Spot", 5.9, 1.6, FL, 0.0)
    b.marker("Spawn_Inside", -0.1, 4.2, FL, PI)
    b.marker("Door_Front", -0.1, 7.0, FL, PI)
    b.entrance = (-0.1, 6.0)
    b.floors = 2
    return b.finish(tags=["home", "safehouse", "waterfront"], landmark="safehouse",
                    extra={"mezzanine_y": MZ, "garage_bay": [4.8, 7.4, 2.8],
                           "stair": {"bottom": [-8.05, FL, -5.2], "top": [-8.05, MZ, 0.5], "width": 1.3}})


BUILD = {"police_station": police_station, "hospital": hospital, "safehouse": safehouse}
VIEWS = {
    "police_station": dict(cut=3.0, shots=[((-7.0, 8.2, 1.7), (-7.0, 1.0, 1.3)), ((-11.9, 1.5, 1.75), (-2.0, 7.0, 1.0)),
                                           ((7.0, 14.5, 2.2), (7.0, 2.0, 1.5)), ((-9.0, 22.0, 3.0), (-6.0, 0.0, 5.0))]),
    "hospital": dict(cut=3.2, box=(-15.5, 15.5, 1.5, 13.5),
                     shots=[((-5.5, 9.8, 1.7), (-5.5, 2.5, 1.3)), ((-12.0, 3.0, 1.75), (1.0, 9.0, 1.0)),
                            ((9.0, 17.0, 2.2), (11.0, 2.0, 2.0)), ((-2.0, 32.0, 6.0), (0.0, 0.0, 9.0))]),
    "safehouse": dict(cut=[2.95, 6.0], shots=[((-0.1, 5.2, 1.7), (-5.0, -5.0, 1.5)), ((2.6, -5.8, 1.75), (-6.0, 3.0, 1.2)),
                                              ((2.6, -1.4, 5.0), (-4.0, -5.5, 3.6)), ((5.9, 9.5, 1.7), (5.9, -2.0, 1.2))]),
}
