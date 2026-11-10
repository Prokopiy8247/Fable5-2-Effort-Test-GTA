"""props_street_utility - utility boxes, power pole, rooftop equipment, ladder
(family module of props_street). Slots 44 - 51.
"""
import math

from mathutils import Matrix

import gta_bl as G
from props_street import prop, arc, ngon, rect


@prop("utility_box", 44, "utility", "static", 180.0, "metal",
      notes="Street utility cabinet 1.2 x 0.55 x 1.45 m on a concrete plinth; doors toward +Y.")
def b_utility_box(a):
    p = a.part()
    p.box((1.22, 0.56, 0.12), (0, 0, 0.06), 'ConcreteDark')
    p.box((1.10, 0.44, 1.24), (0, 0, 0.74), 'Olive')
    p.tbox((1.18, 0.52), (1.10, 0.44), 0.07, (0, 0, 1.36), 'SteelDark')
    a.add(p, bevel=0.016)
    q = a.part()
    yf = 0.221
    for s in (1, -1):
        q.box((0.50, 0.014, 1.10), (s * 0.268, yf, 0.74), 'Olive')          # raised door panels
        for i in range(4):
            q.box((0.34, 0.03, 0.022), (s * 0.268, yf + 0.012, 1.16 - i * 0.055), 'Charcoal',
                  rot=(math.radians(-35), 0, 0))
        q.box((0.03, 0.035, 0.16), (s * 0.05, yf + 0.018, 0.74), 'Steel')   # handles
    q.box((0.014, 0.016, 1.10), (0, yf, 0.74), 'Charcoal')
    q.prism([(0.20, 0.44), (0.36, 0.44), (0.28, 0.58)], yf + 0.007, yf + 0.013, 'HazardYellow', 'Y')
    q.box((0.022, 0.006, 0.06), (0.28, yf + 0.015, 0.495), 'Black')
    q.box((0.14, 0.006, 0.05), (-0.28, yf + 0.010, 0.42), 'White')
    q.cyl(0.035, 0.95, (-0.60, -0.10, 0.475), 'Steel', seg=6)               # conduit
    q.box((0.10, 0.09, 0.03), (-0.585, -0.10, 0.85), 'SteelDark')
    q.box((0.08, 0.20, 0.10), (-0.575, -0.10, 0.99), 'SteelDark')
    a.add(q)


@prop("transformer", 45, "utility", "static", 1400.0, "metal",
      notes="Pad-mounted transformer 1.9 x 1.5 x 1.75 m with cooling fins and three bushings.")
def b_transformer(a):
    p = a.part()
    p.box((1.90, 1.50, 0.12), (0, 0, 0.06), 'Concrete')
    p.box((1.50, 0.90, 1.26), (0, -0.12, 0.75), 'LeafDark')
    p.prism([(0.30, 0.12), (0.70, 0.12), (0.70, 1.14), (0.30, 1.30)], -0.75, 0.75, 'LeafDark', 'X')
    a.add(p, bevel=0.02)
    q = a.part()
    for i in range(9):                                                      # back fins
        q.box((0.024, 0.15, 0.92), (-0.60 + i * 0.15, -0.63, 0.74), 'LeafDark')
    for s in (1, -1):                                                       # side fins
        for i in range(5):
            q.box((0.15, 0.022, 0.92), (s * 0.81, -0.46 + i * 0.14, 0.74), 'LeafDark')
        q.box((0.06, 0.10, 0.07), (s * 0.55, -0.12, 1.415), 'SteelDark')    # lifting lugs
    yf = 0.701
    q.box((0.014, 0.014, 0.96), (0, yf, 0.63), 'Charcoal')                  # door seam
    for s in (1, -1):
        q.box((0.68, 0.012, 0.94), (s * 0.37, yf, 0.63), 'LeafDark')
        q.box((0.035, 0.04, 0.14), (s * 0.07, yf + 0.02, 0.66), 'Steel')
    q.prism([(0.26, 0.74), (0.48, 0.74), (0.37, 0.93)], yf + 0.006, yf + 0.012, 'HazardYellow', 'Y')
    q.box((0.03, 0.006, 0.09), (0.37, yf + 0.014, 0.815), 'Black')
    q.box((0.24, 0.006, 0.10), (-0.37, yf + 0.009, 0.84), 'White')
    a.add(q)
    r = a.part()
    for x in (-0.42, 0.0, 0.42):                                            # bushings
        r.lathe([(0.055, 1.38), (0.055, 1.44), (0.10, 1.45), (0.10, 1.49), (0.055, 1.50), (0.055, 1.54), (0.09, 1.55),
                 (0.09, 1.59), (0.045, 1.60), (0.045, 1.67)], 'Cream', seg=6, center=(x, -0.12, 0))
        r.cyl(0.022, 0.08, (x, -0.12, 1.71), 'Chrome', seg=6)
    a.add(r)


@prop("power_pole", 46, "utility", "static", 520.0, "wood",
      notes="Wooden power pole 9.7 m with crossarm (2.5 m along X), pole transformer and climbing pegs. "
            "Markers Wire_1..Wire_4 sit on the insulator tops (string wires between poles).")
def b_power_pole(a):
    p = a.part()
    p.cyl(0.175, 9.5, (0, 0, 4.75), 'Trunk', seg=8, r2=0.115)
    p.cyl(0.125, 0.04, (0, 0, 9.52), 'SteelDark', seg=8, r2=0.08)
    p.cyl(0.27, 0.78, (0, 0.42, 6.75), 'Steel', seg=10)                     # pole transformer
    p.lathe([(0.27, 7.14), (0.285, 7.15), (0.285, 7.19), (0.0, 7.27)], 'SteelDark', seg=10, center=(0, 0.42, 0))
    a.add(p, smooth=42)
    q = a.part()
    q.box((2.50, 0.11, 0.13), (0, 0.125, 8.75), 'WoodDark')
    q.box((1.40, 0.09, 0.10), (0, 0.115, 7.75), 'WoodDark')
    for s in (1, -1):
        q.strut((s * 0.85, 0.185, 8.70), (0, 0.185, 8.05), 0.012, 'SteelDark', h=0.05)
        q.box((0.06, 0.06, 0.09), (s * 0.55, 0.115, 7.845), 'Cream')        # spool insulators
        q.box((0.085, 0.085, 0.03), (s * 0.55, 0.115, 7.845), 'Cream')
    q.box((0.10, 0.30, 0.06), (0, 0.22, 7.02), 'SteelDark')                 # transformer brackets
    q.box((0.10, 0.30, 0.06), (0, 0.22, 6.48), 'SteelDark')
    for i in range(6):                                                      # climbing pegs
        s = 1 if i % 2 == 0 else -1
        q.box((0.16, 0.025, 0.025), (s * 0.19, 0, 2.6 + i * 0.45), 'Steel')
    q.box((0.16, 0.012, 0.22), (0, 0.168, 1.75), 'HazardYellow')            # pole tag
    q.box((0.10, 0.008, 0.035), (0, 0.176, 1.80), 'Black')
    a.add(q)
    r = a.part()
    xs = (-1.10, -0.48, 0.48, 1.10)
    for x in xs:
        r.lathe([(0.03, 8.815), (0.065, 8.86), (0.065, 8.90), (0.035, 8.925), (0.055, 8.96), (0.0, 9.0)], 'Sky', seg=6,
                center=(x, 0.125, 0))
    for x in (-0.12, 0.12):
        r.lathe([(0.035, 7.19), (0.06, 7.25), (0.03, 7.30), (0.0, 7.33)], 'Cream', seg=6, center=(x, 0.36, 0))
    a.add(r)
    for i, x in enumerate(xs):
        a.marker("Wire_%d" % (i + 1), (x, 0.125, 9.0), size=0.12)


@prop("ac_unit", 47, "utility", "static", 55.0, "metal", anchor="roof",
      notes="AC condenser 1.05 x 0.5 x 0.72 m on two rails; fan grille toward +Y. For rooftops / alleys.")
def b_ac_unit(a):
    p = a.part()
    p.box((0.95, 0.40, 0.64), (0, 0, 0.38), 'White')
    for x in (-0.33, 0.33):
        p.box((0.09, 0.48, 0.06), (x, 0, 0.03), 'Charcoal')
    p.box((0.07, 0.22, 0.34), (0.51, 0.0, 0.30), 'WarmGrey')
    a.add(p, bevel=0.018)
    q = a.part()
    fx, fz, yf = 0.16, 0.38, 0.201
    q.cyl(0.255, 0.012, (fx, yf, fz), 'Charcoal', axis='Y', seg=12)
    q.lathe([(0.255, 0.0), (0.255, 0.03), (0.285, 0.03), (0.285, 0.0)], 'WarmGrey', seg=12, center=(fx, yf, fz), axis='Y',
            cap=False)
    for rr in (0.10, 0.18):
        q.lathe([(rr, 0.018), (rr, 0.03), (rr + 0.022, 0.03), (rr + 0.022, 0.018)], 'Steel', seg=12,
                center=(fx, yf, fz), axis='Y', cap=False)
    for i in range(4):
        an = math.pi * i / 4
        q.box((0.54, 0.012, 0.018), (fx, yf + 0.026, fz), 'Steel', rot=(0, an, 0))
    q.cyl(0.055, 0.03, (fx, yf + 0.02, fz), 'Steel', axis='Y', seg=8)
    for i in range(3):
        an = 2 * math.pi * i / 3 + 0.4
        q.box((0.20, 0.006, 0.07), (fx + math.cos(an) * 0.13, yf + 0.010, fz + math.sin(an) * 0.13), 'SteelDark',
              rot=(0, -an, 0))
    for i in range(6):                                                      # louvres
        q.box((0.24, 0.02, 0.028), (-0.315, yf + 0.006, 0.56 - i * 0.07), 'WarmGrey', rot=(math.radians(-30), 0, 0))
    q.box((0.10, 0.008, 0.04), (-0.36, yf + 0.004, 0.13), 'Teal')           # badge
    for i in range(5):                                                      # top vents
        q.box((0.60, 0.03, 0.012), (-0.05, -0.12 + i * 0.06, 0.704), 'WarmGrey')
    q.tube([(0.545, -0.04, 0.22), (0.63, -0.04, 0.22), (0.66, -0.07, 0.22), (0.66, -0.26, 0.22)], 0.018, 'Brass', seg=5)
    q.tube([(0.545, 0.04, 0.30), (0.67, 0.04, 0.30), (0.70, 0.01, 0.30), (0.70, -0.26, 0.30)], 0.022, 'Black', seg=5)
    a.add(q)


@prop("satellite_dish", 48, "utility", "static", 18.0, "metal", anchor="roof",
      notes="Rooftop satellite dish (diameter 1.25 m) on a mast, aimed +Y and 35 degrees up.")
def b_satellite_dish(a):
    p = a.part()
    p.box((0.44, 0.44, 0.03), (0, 0, 0.015), 'SteelDark')
    p.cyl(0.04, 1.0, (0, 0, 0.52), 'Steel', seg=8)
    p.strut((0.0, -0.20, 0.03), (0.0, -0.03, 0.55), 0.03, 'SteelDark')
    p.strut((0.18, 0.10, 0.03), (0.02, 0.02, 0.55), 0.03, 'SteelDark')
    p.strut((-0.18, 0.10, 0.03), (-0.02, 0.02, 0.55), 0.03, 'SteelDark')
    p.box((0.12, 0.16, 0.14), (0, 0.04, 1.02), 'SteelDark')
    a.add(p)
    d = a.part()
    d.lathe([(0.0, 0.0), (0.21, 0.025), (0.42, 0.095), (0.62, 0.205), (0.635, 0.195), (0.43, 0.075), (0.21, 0.002),
             (0.0, -0.022)], 'White', seg=12, axis='Y')
    d.tube([(0, 0.16, -0.58), (0, 0.40, -0.22), (0, 0.50, -0.02)], 0.016, 'Steel', seg=4)
    d.tube([(0.30, 0.06, 0.0), (0.02, 0.48, 0.0)], 0.009, 'Steel', seg=4)
    d.tube([(-0.30, 0.06, 0.0), (-0.02, 0.48, 0.0)], 0.009, 'Steel', seg=4)
    d.cyl(0.045, 0.13, (0, 0.50, 0.0), 'Charcoal', axis='Y', seg=8)
    d.cyl(0.06, 0.03, (0, 0.44, 0.0), 'Charcoal', axis='Y', seg=8)
    d.box((0.10, 0.08, 0.10), (0, -0.05, 0.0), 'SteelDark')
    M = Matrix.Translation((0, 0.16, 1.08)) @ Matrix.Rotation(math.radians(35), 4, 'X')
    G.transform(d.bm.verts[:], M)
    a.add(d, smooth=40)


@prop("water_tank", 49, "utility", "static", 2200.0, "wood", anchor="roof",
      notes="Rooftop timber water tank on a steel frame, 2.5 m wide, 4.25 m high, ladder on the +Y side.")
def b_water_tank(a):
    p = a.part()
    L = 0.82
    for sx in (1, -1):
        for sy in (1, -1):
            p.box((0.12, 0.12, 1.50), (sx * L, sy * L, 0.75), 'SteelDark')
            p.box((0.24, 0.24, 0.03), (sx * L, sy * L, 0.015), 'SteelDark')
    for s in (1, -1):
        p.box((2 * L + 0.12, 0.10, 0.12), (0, s * L, 1.46), 'SteelDark')
        p.box((0.10, 2 * L + 0.12, 0.12), (s * L, 0, 1.46), 'SteelDark')
        p.strut((-L, s * L, 0.12), (L, s * L, 1.38), 0.05, 'SteelDark')
        p.strut((L, s * L, 0.12), (-L, s * L, 1.38), 0.05, 'SteelDark')
        p.strut((s * L, -L, 0.12), (s * L, L, 1.38), 0.05, 'SteelDark')
        p.strut((s * L, L, 0.12), (s * L, -L, 1.38), 0.05, 'SteelDark')
    for i in range(10):                                                     # ladder
        p.box((0.40, 0.025, 0.025), (0, 1.26, 0.30 + i * 0.33), 'Steel')
    for x in (-0.20, 0.20):
        p.box((0.035, 0.035, 3.45), (x, 1.26, 1.725), 'Steel')
        p.box((0.03, 0.14, 0.03), (x, 1.19, 3.30), 'Steel')
        p.box((0.03, 0.14, 0.03), (x, 1.19, 1.90), 'Steel')
    a.add(p)
    t = a.part()
    t.cyl(1.25, 0.08, (0, 0, 1.56), 'WoodDark', seg=12)
    t.cyl(1.10, 1.90, (0, 0, 2.55), 'Wood', seg=12, r2=1.04)
    for i, z in enumerate((1.78, 2.22, 2.70, 3.22)):
        rr = 1.10 - 0.06 * (z - 1.60) / 1.90 + 0.012
        t.cyl(rr, 0.055, (0, 0, z), 'SteelDark', seg=12, cap=False)
    t.lathe([(1.04, 3.50), (1.20, 3.50), (1.20, 3.54), (0.10, 4.12), (0.0, 4.25)], 'RoofGrey', seg=12)
    t.cyl(0.07, 1.56, (0.35, -0.30, 0.78), 'Steel', seg=6)                  # down pipe
    a.add(t)


@prop("vent_pipe", 50, "utility", "static", 30.0, "metal", anchor="roof",
      notes="Rooftop vent cluster: capped flue (1.45 m), gooseneck pipe and a low turbine vent.")
def b_vent_pipe(a):
    p = a.part()
    p.tbox((0.62, 0.62), (0.38, 0.38), 0.10, (0, 0, 0.0), 'SteelDark')
    p.tbox((0.40, 0.40), (0.24, 0.24), 0.08, (-0.50, 0.05, 0.0), 'SteelDark')
    a.add(p, bevel=0.012)
    q = a.part()
    q.cyl(0.15, 1.02, (0, 0, 0.61), 'Steel', seg=10)
    q.cyl(0.165, 0.05, (0, 0, 0.62), 'SteelDark', seg=10, cap=False)
    q.lathe([(0.17, 1.20), (0.29, 1.20), (0.29, 1.235), (0.0, 1.42)], 'SteelDark', seg=10)
    for i in range(3):
        an = 2 * math.pi * i / 3
        q.box((0.02, 0.02, 0.12), (math.cos(an) * 0.14, math.sin(an) * 0.14, 1.16), 'SteelDark')
    q.tube([(0.44, -0.02, 0.0), (0.44, -0.02, 0.58), (0.44, 0.04, 0.74), (0.44, 0.18, 0.82), (0.44, 0.31, 0.75),
            (0.44, 0.35, 0.62)], 0.075, 'Steel', seg=8)
    q.cyl(0.11, 0.03, (0.44, -0.02, 0.015), 'SteelDark', seg=8)
    q.cyl(0.10, 0.32, (-0.50, 0.05, 0.24), 'Steel', seg=8)                  # turbine vent
    q.lathe([(0.10, 0.40), (0.20, 0.47), (0.22, 0.56), (0.17, 0.66), (0.06, 0.71), (0.0, 0.72)], 'Chrome', seg=8,
            center=(-0.50, 0.05, 0))
    a.add(q, smooth=40)


@prop("fire_escape_ladder", 51, "utility", "static", 45.0, "metal", anchor="wall",
      notes="4.0 m ladder section, 0.48 m wide, rungs every 0.30 m; stackable. Origin = bottom centre of "
            "the ladder plane; climb side is +Y, the wall is at y = -0.20 (Godot z = +0.20). Markers "
            "'Ladder_Bottom' / 'Ladder_Top' on the climb side.")
def b_fire_escape_ladder(a):
    p = a.part()
    for x in (-0.24, 0.24):
        p.box((0.045, 0.022, 4.0), (x, 0, 2.0), 'Charcoal')
    n = 13
    for i in range(n):
        p.cyl(0.015, 0.48, (0, 0, 0.20 + i * 0.30), 'SteelDark', axis='X', seg=6, cap=False)
    for z in (0.45, 2.0, 3.55):
        for x in (-0.24, 0.24):
            p.box((0.03, 0.20, 0.03), (x, -0.10, z), 'Charcoal')
            p.box((0.09, 0.012, 0.14), (x, -0.194, z), 'SteelDark')
    a.add(p)
    a.marker("Ladder_Bottom", (0, 0.15, 0.0))
    a.marker("Ladder_Top", (0, 0.15, 4.0))
