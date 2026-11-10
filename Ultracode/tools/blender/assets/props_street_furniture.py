"""props_street_furniture - benches, bins, hydrant, kiosks, shelters, ground plates
(family module of props_street). Slots 26 - 43.
"""
import math
import random

import gta_bl as G
from props_street import prop, arc, ngon, rect


# ------------------------------------------------------------------------------------------------
@prop("bench", 26, "furniture", "breakable", 55.0, "wood",
      notes="Street bench 1.8 m, cast side frames + wooden slats. Sitter faces +Y; seat height 0.44 m.")
def b_bench(a):
    frame = [(0.30, 0.0), (0.27, 0.42), (-0.20, 0.38), (-0.33, 0.86), (-0.385, 0.845), (-0.27, 0.33), (-0.33, 0.0),
             (-0.265, 0.0), (-0.21, 0.30), (0.21, 0.335), (0.235, 0.0)]
    p = a.part()
    for x in (-0.78, 0.78):
        p.prism(frame, x - 0.03, x + 0.03, 'Charcoal', 'X')
        p.box((0.10, 0.09, 0.02), (x, 0.268, 0.01), 'Charcoal')
        p.box((0.10, 0.09, 0.02), (x, -0.298, 0.01), 'Charcoal')
    a.add(p, bevel=0.008)
    q = a.part()
    for y in (0.21, 0.095, -0.02, -0.135):
        q.box((1.72, 0.098, 0.032), (0, y, 0.42 - (0.27 - y) * 0.0851 + 0.016), 'Wood')
    th = math.atan2(0.13, 0.48)
    for t in (0.36, 0.63, 0.90):
        q.box((1.72, 0.032, 0.105), (0, -0.20 - 0.13 * t + 0.017, 0.38 + 0.48 * t), 'Wood', rot=(th, 0, 0))
    a.add(q, bevel=0.007)


@prop("bench_park", 27, "furniture", "breakable", 120.0, "wood",
      notes="Park bench 2.0 m, concrete pedestals + dark timber planks. Sitter faces +Y.")
def b_bench_park(a):
    p = a.part()
    for x in (-0.72, 0.72):
        p.prism([(-0.25, 0.0), (0.25, 0.0), (0.21, 0.40), (-0.21, 0.40)], x - 0.07, x + 0.07, 'Concrete', 'X')
    a.add(p, bevel=0.018)
    q = a.part()
    for y in (-0.155, 0.0, 0.155):
        q.box((2.0, 0.14, 0.05), (0, y, 0.425), 'WoodDark')
    th = math.atan2(0.10, 0.58)
    for z in (0.63, 0.81):
        q.box((2.0, 0.045, 0.14), (0, -0.20 - 0.10 * (z - 0.30) / 0.58 + 0.035, z), 'WoodDark', rot=(th, 0, 0))
    a.add(q, bevel=0.01)
    s = a.part()
    for x in (-0.72, 0.72):
        s.strut((x, -0.205, 0.28), (x, -0.315, 0.90), 0.06, 'SteelDark', h=0.022)
        s.box((0.03, 0.03, 0.012), (x, 0.155, 0.456), 'Steel')
        s.box((0.03, 0.03, 0.012), (x, -0.155, 0.456), 'Steel')
    a.add(s)


@prop("bin", 28, "furniture", "dynamic", 28.0, "metal",
      notes="Round slatted litter bin with a teal rain hood, 1.1 m.")
def b_bin(a):
    p = a.part()
    p.cyl(0.10, 0.06, (0, 0, 0.03), 'Charcoal', seg=8)
    p.cyl(0.245, 0.74, (0, 0, 0.45), 'Black', seg=10)
    p.lathe([(0.275, 0.07), (0.275, 0.115), (0.24, 0.115)], 'Charcoal', seg=10)
    p.lathe([(0.24, 0.80), (0.28, 0.80), (0.28, 0.85), (0.19, 0.875), (0.19, 0.83)], 'Charcoal', seg=10, cap=False)
    p.lathe([(0.29, 1.02), (0.29, 1.045), (0.11, 1.09), (0.0, 1.10)], 'Teal', seg=10)
    a.add(p, smooth=42)
    q = a.part()
    n = 14
    for i in range(n):
        an = 2 * math.pi * i / n
        q.box((0.018, 0.085, 0.70), (math.cos(an) * 0.262, math.sin(an) * 0.262, 0.46), 'Wood', rot=(0, 0, an))
    for i in range(3):
        an = 2 * math.pi * (i + 0.25) / 3
        q.cyl(0.014, 0.19, (math.cos(an) * 0.225, math.sin(an) * 0.225, 0.94), 'Charcoal', seg=4)
    a.add(q)


@prop("dumpster", 29, "furniture", "static", 380.0, "metal",
      notes="Steel dumpster 1.9 x 1.2 x 1.3 m (good cover). Child 'Lid' has its origin on the rear hinge line "
            "(rotate about local X to open).")
def b_dumpster(a):
    p = a.part()
    p.tbox((1.66, 0.94), (1.86, 1.12), 0.96, (0, 0, 0.16), 'LeafDark')
    a.add(p, bevel=0.025)
    q = a.part()
    q.box((1.74, 1.00, 0.02), (0, 0, 1.113), 'Black')                       # dark inside under the lid
    for x in (-0.62, 0.0, 0.62):                                            # front / back ribs
        q.strut((x, 0.478, 0.20), (x, 0.558, 1.08), 0.07, 'LeafDark', h=0.035)
        q.strut((x, -0.478, 0.20), (x, -0.558, 1.08), 0.07, 'LeafDark', h=0.035)
    for s in (1, -1):                                                       # fork sleeves + side ribs
        q.box((0.09, 0.80, 0.17), (s * 0.935, 0, 0.80), 'Charcoal')
        q.box((0.05, 0.86, 0.06), (s * 0.95, 0, 1.06), 'LeafDark')
    q.box((1.60, 0.012, 0.10), (0, 0.508, 0.42), 'HazardYellow', rot=(math.radians(-5.3), 0, 0))
    q.box((0.36, 0.012, 0.26), (-0.52, 0.538, 0.78), 'White', rot=(math.radians(-5.3), 0, 0))
    q.cyl(0.028, 1.84, (0, -0.585, 1.12), 'SteelDark', axis='X', seg=6)     # hinge bar
    for x in (-0.70, 0.70):
        for y in (-0.36, 0.36):
            q.cyl(0.085, 0.06, (x, y, 0.085), 'Tire', axis='X', seg=8)
            q.box((0.10, 0.10, 0.06), (x, y, 0.17), 'SteelDark')
    a.add(q)
    lid = a.part()
    lid.box((1.92, 1.18, 0.05), (0, 0, 1.15), 'Charcoal')
    lid.box((0.03, 1.18, 0.03), (0, 0, 1.185), 'Black')                     # split line between the two lids
    for x in (-0.48, 0.48):
        lid.box((0.70, 0.90, 0.025), (x, 0.0, 1.185), 'Charcoal')
        lid.box((0.30, 0.05, 0.05), (x, 0.60, 1.15), 'Black')               # front grips
    a.child("Lid", lid, bevel=0.012, origin=(0, -0.585, 1.125))


@prop("recycling_bins", 30, "furniture", "dynamic", 42.0, "rubber",
      notes="Three wheelie bins in a row (blue / green / yellow lids), one rigid group.")
def b_recycling_bins(a):
    p = a.part()
    q = a.part()
    for x, key in ((-0.60, 'CarBlue'), (0.0, 'CarGreen'), (0.60, 'CarYellow')):
        p.tbox((0.42, 0.50), (0.52, 0.62), 0.86, (x, 0.02, 0.08), 'Charcoal')
        p.box((0.56, 0.68, 0.055), (x, 0.03, 0.972), key)
        q.box((0.40, 0.03, 0.04), (x, 0.375, 0.955), key)                   # lid lip
        q.box((0.30, 0.014, 0.16), (x, 0.305, 0.60), key, rot=(math.radians(-4), 0, 0))
        q.prism([(x - 0.06, 0.56), (x + 0.06, 0.56), (x, 0.66)], 0.312, 0.322, 'White', 'Y')
        q.cyl(0.016, 0.46, (x, -0.33, 0.93), 'Charcoal', axis='X', seg=4)   # push handle
        q.box((0.04, 0.08, 0.05), (x - 0.2, -0.30, 0.925), 'Charcoal')
        q.box((0.04, 0.08, 0.05), (x + 0.2, -0.30, 0.925), 'Charcoal')
        for s in (-1, 1):
            q.cyl(0.095, 0.05, (x + s * 0.215, -0.20, 0.095), 'Tire', axis='X', seg=8)
        q.box((0.36, 0.06, 0.08), (x, 0.20, 0.04), 'Charcoal')              # front foot
    a.add(p, bevel=0.018)
    a.add(q)


@prop("hydrant", 31, "furniture", "breakable", 65.0, "metal",
      notes="Fire hydrant 0.8 m; big outlet toward +Y, two side outlets along X.")
def b_hydrant(a):
    p = a.part()
    prof = [(0.175, 0.0), (0.175, 0.035), (0.12, 0.06), (0.108, 0.12), (0.125, 0.13), (0.125, 0.16), (0.105, 0.17),
            (0.105, 0.50), (0.13, 0.52), (0.13, 0.56), (0.11, 0.575), (0.098, 0.66), (0.062, 0.72), (0.036, 0.735)]
    p.lathe(prof, 'FireRed', seg=10, mats=['FireRed'] * 9 + ['White'] * 4)
    p.cyl(0.04, 0.06, (0, 0, 0.765), 'White', seg=5)
    p.cyl(0.052, 0.36, (0, 0, 0.40), 'FireRed', axis='X', seg=8)
    for s in (1, -1):
        p.cyl(0.062, 0.045, (s * 0.195, 0, 0.40), 'White', axis='X', seg=8)
        p.cyl(0.028, 0.03, (s * 0.23, 0, 0.40), 'White', axis='X', seg=5)
    p.cyl(0.07, 0.16, (0, 0.13, 0.37), 'FireRed', axis='Y', seg=8)
    p.cyl(0.082, 0.05, (0, 0.215, 0.37), 'White', axis='Y', seg=8)
    p.cyl(0.032, 0.03, (0, 0.25, 0.37), 'White', axis='Y', seg=5)
    a.add(p, smooth=40)
    q = a.part()
    for i in range(6):
        an = 2 * math.pi * (i + 0.5) / 6
        q.box((0.03, 0.03, 0.02), (math.cos(an) * 0.148, math.sin(an) * 0.148, 0.045), 'SteelDark', rot=(0, 0, an))
    a.add(q)


@prop("mailbox", 32, "furniture", "breakable", 70.0, "metal",
      notes="Street mailbox, vaulted top, pull-down flap toward +Y, white envelope pictogram.")
def b_mailbox(a):
    p = a.part()
    top = arc((0, 0, 0.95), 0.24, 0, 180, 5, plane='YZ')
    prof = [(-0.24, 0.14), (0.24, 0.14)] + [(q[1], q[2]) for q in top]
    p.prism(prof, -0.27, 0.27, 'CarBlue', 'X')
    a.add(p, bevel=0.014)
    q = a.part()
    for x in (-0.22, 0.22):
        for y in (-0.19, 0.19):
            q.box((0.05, 0.05, 0.15), (x, y, 0.075), 'Charcoal')
            q.box((0.09, 0.09, 0.015), (x, y, 0.0075), 'Charcoal')
    q.box((0.552, 0.492, 0.065), (0, 0, 0.50), 'White')                     # band
    ph = math.radians(28)
    q.box((0.46, 0.02, 0.19), (0, math.cos(ph) * 0.246, 0.95 + math.sin(ph) * 0.246), 'Navy', rot=(ph, 0, 0))
    q.box((0.20, 0.035, 0.03), (0, math.cos(ph) * 0.262 + 0.02, 0.95 + math.sin(ph) * 0.262 - 0.05), 'Chrome',
          rot=(ph, 0, 0))
    q.box((0.26, 0.008, 0.17), (0, 0.244, 0.74), 'White')                   # envelope
    q.prism([(-0.13, 0.825), (0.13, 0.825), (0.0, 0.735)], 0.247, 0.252, 'CarBlue', 'Y')
    q.box((0.16, 0.008, 0.05), (0, 0.244, 0.585), 'Navy')
    a.add(q)


@prop("newspaper_box", 33, "furniture", "breakable", 38.0, "metal",
      notes="Coin-operated newspaper box on a pedestal, window toward +Y.")
def b_newspaper_box(a):
    p = a.part()
    p.box((0.48, 0.40, 0.64), (0, 0, 0.80), 'Coral')
    p.box((0.44, 0.36, 0.04), (0, 0, 0.02), 'Charcoal')
    a.add(p, bevel=0.016)
    q = a.part()
    q.box((0.12, 0.12, 0.46), (0, 0, 0.26), 'Charcoal')
    q.box((0.40, 0.012, 0.40), (0, 0.203, 0.83), 'WindowDark')
    q.box((0.30, 0.008, 0.31), (0, 0.208, 0.82), 'White', rot=(math.radians(4), 0, 0))
    q.box((0.24, 0.006, 0.05), (0, 0.214, 0.93), 'Black', rot=(math.radians(4), 0, 0))
    q.box((0.11, 0.006, 0.12), (0.065, 0.214, 0.80), 'WarmGrey', rot=(math.radians(4), 0, 0))
    q.box((0.20, 0.03, 0.03), (0, 0.215, 0.585), 'Chrome')                  # pull handle
    q.box((0.48, 0.012, 0.07), (0, 0.203, 1.075), 'White')
    q.box((0.14, 0.12, 0.13), (-0.14, 0.11, 1.18), 'SteelDark')             # coin mechanism
    q.box((0.012, 0.012, 0.05), (-0.14, 0.172, 1.20), 'Black')
    q.box((0.05, 0.012, 0.03), (-0.14, 0.172, 1.14), 'Chrome')
    a.add(q)


@prop("parking_meter", 34, "furniture", "breakable", 22.0, "metal", notes="Twin-head parking meter, 1.4 m.")
def b_parking_meter(a):
    p = a.part()
    p.cyl(0.085, 0.03, (0, 0, 0.015), 'SteelDark', seg=8)
    p.cyl(0.034, 1.04, (0, 0, 0.55), 'Steel', seg=8)
    p.cyl(0.05, 0.05, (0, 0, 1.065), 'SteelDark', seg=8)
    for x in (-0.13, 0.13):
        p.cyl(0.085, 0.115, (x, 0, 1.30), 'Steel', axis='Y', seg=10)
    a.add(p, smooth=42)
    b = a.part()
    b.box((0.36, 0.06, 0.05), (0, 0, 1.09), 'SteelDark')
    for x in (-0.13, 0.13):
        b.box((0.17, 0.115, 0.20), (x, 0, 1.20), 'SteelDark')
    a.add(b, bevel=0.01)
    q = a.part()
    for x in (-0.13, 0.13):
        q.box((0.11, 0.012, 0.06), (x, 0.058, 1.315), 'WindowDark')
        q.box((0.05, 0.008, 0.035), (x + 0.02, 0.063, 1.315), 'HazardYellow')
        q.box((0.012, 0.014, 0.045), (x - 0.045, 0.058, 1.21), 'Black')
        q.box((0.06, 0.02, 0.04), (x + 0.03, 0.06, 1.18), 'Chrome')
        q.box((0.175, 0.12, 0.022), (x, 0, 1.115), 'HazardYellow')
    a.add(q)


@prop("bike_rack", 35, "furniture", "static", 60.0, "metal",
      notes="Five hoops on two floor rails, 2.3 m long (X), hoops 0.9 m high.")
def b_bike_rack(a):
    p = a.part()
    for i in range(5):
        x = -1.0 + i * 0.5
        pts = [(x, -0.28, 0.02)] + arc((x, 0, 0.60), 0.28, 180, 0, 6, plane='YZ') + [(x, 0.28, 0.02)]
        p.tube(pts, 0.025, 'Steel', seg=6)
    a.add(p, smooth=50)
    q = a.part()
    for y in (-0.28, 0.28):
        q.box((2.30, 0.08, 0.02), (0, y, 0.01), 'SteelDark')
        for x in (-1.1, 1.1):
            q.box((0.03, 0.03, 0.012), (x, y, 0.026), 'Chrome')
    a.add(q)


# ------------------------------------------------------------------------------------------------
@prop("bus_stop", 36, "furniture", "breakable", 420.0, "metal", collision="trimesh",
      notes="Bus shelter 3.9 x 1.8 x 2.65 m, open toward +Y (road). Child 'Glass' = rear panes (M_Glass, "
            "breakable); lit advert panel (M_ScreenGlow) on the -X end; bench inside; flag sign with a bus "
            "pictogram on a pole at the +X front corner.")
def b_bus_stop(a):
    p = a.part()
    for x in (-1.8, 0.0, 1.8):
        p.box((0.09, 0.09, 2.44), (x, -0.65, 1.22), 'Charcoal')
        p.strut((x, -0.65, 2.36), (x, 0.70, 2.53), 0.06, 'Charcoal', h=0.09)
        p.box((0.16, 0.16, 0.03), (x, -0.65, 0.015), 'Charcoal')
    top = [(-0.84, 2.50), (-0.30, 2.585), (0.30, 2.63), (0.90, 2.62)]
    roof = top + [(y, z - 0.07) for y, z in reversed(top)]
    p.prism(roof, -1.96, 1.96, 'Teal', 'X')
    p.box((3.92, 0.03, 0.10), (0, 0.905, 2.585), 'White')                   # fascia
    for z in (0.34, 2.16):
        p.box((3.60, 0.045, 0.05), (0, -0.65, z), 'Charcoal')
    a.add(p)
    # advert light box on the -X end
    ad = a.part()
    ad.box((0.11, 1.06, 1.76), (-1.8, -0.02, 1.26), 'Charcoal')
    a.add(ad, bevel=0.012)
    g = a.part()
    for s in (1, -1):
        g.box((0.012, 0.94, 1.60), (-1.8 + s * 0.058, -0.02, 1.26), 'M_ScreenGlow')
        g.prism(ngon(10, 0.22, -0.02, 1.52), -1.8 + s * 0.064, -1.8 + s * 0.070, 'Mustard', 'X')
        g.box((0.006, 0.94, 0.16), (-1.8 + s * 0.067, -0.02, 0.92), 'Teal')
        g.box((0.006, 0.94, 0.10), (-1.8 + s * 0.067, -0.02, 0.70), 'Navy')
    # bench
    for y in (-0.43, -0.25):
        g.box((2.30, 0.16, 0.04), (0.35, y, 0.47), 'Wood')
    for x in (-0.55, 1.25):
        g.box((0.05, 0.42, 0.05), (x, -0.40, 0.425), 'Charcoal')
        g.box((0.05, 0.05, 0.42), (x, -0.22, 0.21), 'Charcoal')
    # route info board on the rear frame
    g.box((0.50, 0.02, 0.70), (1.20, -0.61, 1.45), 'White')
    g.box((0.40, 0.006, 0.10), (1.20, -0.598, 1.70), 'CarBlue')
    for i in range(4):
        g.box((0.36, 0.006, 0.035), (1.20, -0.598, 1.52 - i * 0.09), 'WarmGrey')
    a.add(g)
    # flag sign
    s = a.part()
    sx, sy, sz = 1.95, 0.72, 2.62
    s.cyl(0.04, 2.95, (sx, sy, 1.475), 'Steel', seg=8)
    s.cyl(0.09, 0.03, (sx, sy, 0.015), 'SteelDark', seg=8)
    a.add(s, smooth=50)
    f = a.part()
    f.box((0.03, 0.56, 0.56), (sx, sy, sz), 'White')
    for d in (1, -1):
        x0 = sx + d * 0.015
        f.box((0.008, 0.50, 0.50), (x0 + d * 0.004, sy, sz), 'CarBlue')
        xp = x0 + d * 0.011
        f.box((0.006, 0.36, 0.20), (xp, sy, sz + 0.02), 'White')            # bus body
        f.box((0.006, 0.30, 0.07), (xp + d * 0.004, sy, sz + 0.06), 'CarBlue')   # window band
        for yy in (-0.10, 0.10):
            f.cyl(0.045, 0.008, (xp, sy + yy, sz - 0.085), 'White', axis='X', seg=8)
            f.box((0.008, 0.02, 0.07), (xp + d * 0.005, sy + yy * 0.5, sz + 0.06), 'White')
    a.add(f)
    gl = a.part()
    for x in (-0.9, 0.9):
        gl.box((1.70, 0.02, 1.77), (x, -0.65, 1.25), 'M_Glass')
    a.child("Glass", gl)


@prop("phone_kiosk", 37, "furniture", "static", 160.0, "metal",
      notes="Public phone kiosk 0.95 x 0.6 x 2.2 m, open toward +Y. Small lit display (M_ScreenGlow).")
def b_phone_kiosk(a):
    p = a.part()
    p.box((0.95, 0.56, 0.05), (0, 0.02, 0.025), 'ConcreteDark')
    p.box((0.86, 0.06, 2.06), (0, -0.20, 1.08), 'Navy')
    p.box((0.96, 0.62, 0.09), (0, 0.03, 2.155), 'Teal')
    for x in (-0.43, 0.43):
        p.prism([(-0.23, 0.50), (0.24, 0.95), (0.24, 2.11), (-0.23, 2.11)], x - 0.022, x + 0.022, 'Navy', 'X')
    p.box((0.38, 0.15, 0.56), (0, -0.10, 1.36), 'Charcoal')
    a.add(p, bevel=0.012)
    q = a.part()
    q.box((0.96, 0.03, 0.20), (0, 0.325, 2.01), 'Teal')                     # header fascia
    yh = 0.343
    q.tube(arc((0, yh, 1.96), 0.13, 25, 155, 4), 0.022, 'White', seg=4, phase=math.pi / 4)   # handset pictogram
    for s in (1, -1):
        q.box((0.075, 0.03, 0.085), (s * 0.125, yh, 1.985), 'White', rot=(0, s * math.radians(-30), 0))
    q.box((0.62, 0.28, 0.03), (0, -0.03, 0.98), 'Steel')                    # shelf
    q.box((0.22, 0.012, 0.085), (-0.03, -0.022, 1.55), 'M_ScreenGlow')
    for r in range(4):
        for c in range(3):
            q.box((0.04, 0.012, 0.03), (-0.03 + (c - 1) * 0.055, -0.022, 1.44 - r * 0.045), 'Steel')
    q.box((0.012, 0.012, 0.05), (-0.14, -0.022, 1.22), 'Black')             # coin slot
    q.box((0.10, 0.02, 0.06), (-0.03, -0.022, 1.15), 'Black')               # coin return
    hx = 0.13                                                               # handset on the reader's left (+X)
    q.box((0.045, 0.05, 0.25), (hx, 0.005, 1.38), 'Black')
    q.box((0.065, 0.075, 0.06), (hx, 0.0, 1.50), 'Black')
    q.box((0.065, 0.075, 0.06), (hx, 0.0, 1.27), 'Black')
    q.tube([(hx, 0.0, 1.24), (0.10, 0.05, 1.06), (0.02, 0.04, 1.03), (-0.06, -0.02, 1.10)], 0.009, 'Black', seg=4)
    a.add(q)


@prop("vending_machine", 38, "furniture", "static", 260.0, "metal", emissive="M_ScreenGlow front + header",
      notes="Drinks vending machine 1.0 x 0.8 x 1.86 m, lit front (M_ScreenGlow) toward +Y.")
def b_vending_machine(a):
    p = a.part()
    p.box((1.0, 0.76, 1.80), (0, 0, 0.96), 'Teal')
    a.add(p, bevel=0.022)
    q = a.part()
    yf = 0.381
    for x in (-0.42, 0.42):
        for y in (-0.30, 0.30):
            q.box((0.07, 0.07, 0.06), (x, y, 0.03), 'Black')
    q.box((0.94, 0.012, 1.72), (0, yf, 0.96), 'Charcoal')                   # door face
    q.box((0.60, 0.012, 1.02), (0.13, yf + 0.008, 1.10), 'M_ScreenGlow')    # lit product window
    q.box((0.90, 0.012, 0.20), (0, yf + 0.008, 1.71), 'M_ScreenGlow')       # lit header
    for i, key in enumerate(('CarRed', 'Mustard', 'White')):
        q.cyl(0.06, 0.008, (0.26 - i * 0.14, yf + 0.016, 1.71), key, axis='Y', seg=8)
    q.box((0.28, 0.008, 0.045), (-0.22, yf + 0.016, 1.71), 'Navy')
    cans = ('CarRed', 'CarOrange', 'CarGreen', 'CarYellow', 'CarBlue')
    for r in range(4):
        zs = 0.66 + r * 0.25
        q.box((0.60, 0.05, 0.02), (0.13, yf + 0.025, zs), 'Charcoal')
        for c in range(5):
            q.cyl(0.043, 0.14, (0.13 + (c - 2) * 0.112, yf + 0.03, zs + 0.08), cans[(c + r * 2) % 5], seg=5)
    # control column (reader's right = -X)
    xc = -0.32
    q.box((0.20, 0.012, 1.02), (xc, yf + 0.008, 1.10), 'SteelDark')
    q.box((0.13, 0.012, 0.07), (xc, yf + 0.016, 1.50), 'M_ScreenGlow')
    for r in range(3):
        for c in range(3):
            q.box((0.032, 0.012, 0.032), (xc + (c - 1) * 0.045, yf + 0.016, 1.36 - r * 0.045), 'Steel')
    q.box((0.012, 0.012, 0.06), (xc + 0.04, yf + 0.016, 1.15), 'Black')
    q.box((0.09, 0.012, 0.02), (xc - 0.02, yf + 0.016, 1.08), 'Black')
    for i, key in enumerate(('CarRed', 'CarYellow', 'CarGreen')):
        q.box((0.04, 0.014, 0.04), (xc + (i - 1) * 0.055, yf + 0.016, 0.95), key)
    q.box((0.10, 0.02, 0.07), (xc, yf + 0.016, 0.72), 'Black')              # coin return
    q.box((0.74, 0.012, 0.24), (0.06, yf + 0.008, 0.33), 'Black')           # delivery bin
    q.box((0.70, 0.03, 0.05), (0.06, yf + 0.02, 0.44), 'Steel')
    for s in (1, -1):                                                       # side stripe
        q.prism([(-0.38, 0.55), (0.38, 1.05), (0.38, 1.33), (-0.38, 0.83)], s * 0.501, s * 0.507, 'White', 'X')
        q.prism([(-0.38, 0.90), (0.38, 1.40), (0.38, 1.48), (-0.38, 0.98)], s * 0.501, s * 0.507, 'Mustard', 'X')
    a.add(q)


@prop("atm", 39, "furniture", "static", 300.0, "metal", emissive="M_ScreenGlow screen + light bar",
      notes="Free-standing cash machine 0.9 x 0.95 x 1.95 m, lit screen (M_ScreenGlow) toward +Y.")
def b_atm(a):
    p = a.part()
    p.box((0.86, 0.70, 1.52), (0, 0, 0.82), 'Navy')
    p.box((0.90, 0.74, 0.07), (0, 0, 0.035), 'Charcoal')
    p.box((0.90, 0.78, 0.36), (0, 0.02, 1.76), 'Teal')
    a.add(p, bevel=0.018)
    q = a.part()
    console = [(0.34, 0.88), (0.57, 0.95), (0.57, 1.00), (0.41, 1.06), (0.37, 1.52), (0.34, 1.52)]
    q.prism(console, -0.37, 0.37, 'Charcoal', 'X')
    ts = math.atan2(0.04, 0.46)
    q.box((0.50, 0.014, 0.36), (0, 0.397, 1.29), 'Black', rot=(ts, 0, 0))
    q.box((0.40, 0.014, 0.27), (0.03, 0.405, 1.30), 'M_ScreenGlow', rot=(ts, 0, 0))
    q.box((0.30, 0.008, 0.05), (0.03, 0.413, 1.38), 'White', rot=(ts, 0, 0))
    q.box((0.20, 0.008, 0.035), (0.08, 0.416, 1.29), 'Navy', rot=(ts, 0, 0))
    q.box((0.26, 0.008, 0.035), (0.05, 0.419, 1.23), 'Navy', rot=(ts, 0, 0))
    for i in range(3):                                                      # soft keys beside the screen
        q.box((0.03, 0.02, 0.035), (-0.215, 0.405, 1.36 - i * 0.07), 'Steel', rot=(ts, 0, 0))
    tk = -math.atan2(0.06, 0.16)
    q.box((0.24, 0.13, 0.012), (0.08, 0.492, 1.034), 'Steel', rot=(tk, 0, 0))
    for r in range(4):
        for c in range(3):
            yy = 0.455 + r * 0.027
            q.box((0.045, 0.02, 0.012), (0.08 + (c - 1) * 0.06, yy, 1.062 - (yy - 0.41) * 0.375), 'White',
                  rot=(tk, 0, 0))
    q.box((0.14, 0.02, 0.028), (-0.22, 0.39, 1.14), 'Black')                # card slot
    q.box((0.03, 0.02, 0.02), (-0.13, 0.392, 1.14), 'NeonGreen')
    q.box((0.40, 0.03, 0.06), (0.0, 0.355, 0.74), 'Black')                  # cash slot
    q.box((0.44, 0.04, 0.02), (0.0, 0.36, 0.695), 'Steel')
    q.box((0.16, 0.02, 0.02), (-0.2, 0.352, 0.60), 'Black')                 # receipt slot
    q.box((0.78, 0.03, 0.045), (0, 0.395, 1.555), 'M_ScreenGlow')           # light bar under the header
    yh = 0.416                                                              # header: banknote pictogram
    q.box((0.34, 0.01, 0.19), (0.12, yh, 1.77), 'White')
    q.cyl(0.055, 0.008, (0.12, yh + 0.006, 1.77), 'Teal', axis='Y', seg=8)
    q.box((0.20, 0.01, 0.045), (-0.22, yh, 1.82), 'White')
    q.box((0.20, 0.01, 0.045), (-0.22, yh, 1.74), 'White')
    for s in (1, -1):                                                       # privacy wings
        q.prism([(0.35, 0.95), (0.60, 1.00), (0.52, 1.52), (0.35, 1.52)], s * 0.40 - 0.012, s * 0.40 + 0.012,
                'Navy', 'X')
    a.add(q)


@prop("planter", 40, "furniture", "static", 450.0, "concrete",
      notes="Concrete street planter 1.1 x 1.1 m with shrubs and flowers, 1.2 m high.")
def b_planter(a):
    p = a.part()
    p.tbox((0.86, 0.86), (1.04, 1.04), 0.56, (0, 0, 0.0), 'Concrete')
    p.box((1.10, 1.10, 0.075), (0, 0, 0.59), 'ConcreteDark')
    a.add(p, bevel=0.025)
    q = a.part()
    q.box((0.96, 0.96, 0.02), (0, 0, 0.635), 'Dirt')
    rng = random.Random(40)
    blobs = [((0.0, 0.02, 0.92), 0.34, 'Leaf'), ((-0.26, -0.22, 0.80), 0.24, 'LeafDark'),
             ((0.27, -0.20, 0.82), 0.25, 'LeafLight'), ((-0.24, 0.26, 0.80), 0.23, 'LeafLight'),
             ((0.26, 0.25, 0.79), 0.23, 'LeafDark')]
    for c, r, key in blobs:
        vs = q.sph(r, c, key, seg=7, rings=4, scale=(1, 1, 0.82))
        for v in vs:
            v.co.x += rng.uniform(-0.035, 0.035)
            v.co.y += rng.uniform(-0.035, 0.035)
            v.co.z += rng.uniform(-0.03, 0.03)
    for i in range(9):
        an = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.12, 0.42)
        q.sph(0.045, (math.cos(an) * rr, math.sin(an) * rr, 0.98 + rng.uniform(-0.12, 0.14) - rr * 0.35),
              ('Rose', 'Mustard', 'White')[i % 3], seg=4, rings=2)
    a.add(q)


@prop("tree_grate", 41, "furniture", "static", 90.0, "metal", collision="none",
      notes="Cast-iron tree grate 1.2 x 1.2 m, 3 cm high, open centre (r 0.24 m) for the trunk.")
def b_tree_grate(a):
    p = a.part()
    p.box((1.16, 1.16, 0.010), (0, 0, 0.005), 'Dirt')
    for s in (1, -1):
        p.box((1.20, 0.07, 0.03), (0, s * 0.565, 0.015), 'Charcoal')
        p.box((0.07, 1.06, 0.03), (s * 0.565, 0, 0.015), 'Charcoal')
    p.lathe([(0.24, 0.0), (0.24, 0.03), (0.31, 0.03), (0.31, 0.0)], 'Charcoal', seg=12, cap=False)
    n = 16
    for i in range(n):
        an = 2 * math.pi * i / n
        L = 0.535 / max(abs(math.cos(an)), abs(math.sin(an)))
        p.box((L - 0.30, 0.04, 0.024), (math.cos(an) * (0.30 + L) / 2, math.sin(an) * (0.30 + L) / 2, 0.012),
              'Charcoal', rot=(0, 0, an))
    for s in (1, -1):
        p.box((0.86, 0.035, 0.024), (0, s * 0.415, 0.012), 'Charcoal')
        p.box((0.035, 0.86, 0.024), (s * 0.415, 0, 0.012), 'Charcoal')
    a.add(p)


@prop("manhole", 42, "furniture", "static", 80.0, "metal", collision="none",
      notes="Manhole cover with a concrete collar, diameter 0.88 m, 3.6 cm high.")
def b_manhole(a):
    p = a.part()
    p.lathe([(0.44, 0.0), (0.44, 0.018), (0.375, 0.026), (0.375, 0.0)], 'ConcreteDark', seg=12, cap=False)
    p.cyl(0.36, 0.028, (0, 0, 0.014), 'Charcoal', seg=12)
    p.lathe([(0.20, 0.028), (0.20, 0.036), (0.25, 0.036), (0.25, 0.028)], 'SteelDark', seg=12, cap=False)
    p.cyl(0.085, 0.036, (0, 0, 0.018), 'SteelDark', seg=6)
    for i in range(8):
        an = 2 * math.pi * (i + 0.5) / 8
        p.box((0.075, 0.035, 0.008), (math.cos(an) * 0.305, math.sin(an) * 0.305, 0.032), 'SteelDark', rot=(0, 0, an))
    for i in range(4):
        an = 2 * math.pi * i / 4 + math.pi / 4
        p.box((0.10, 0.03, 0.008), (math.cos(an) * 0.145, math.sin(an) * 0.145, 0.032), 'SteelDark', rot=(0, 0, an))
    for s in (1, -1):
        p.box((0.05, 0.022, 0.004), (s * 0.30, 0, 0.030), 'Black')          # pick holes
    a.add(p)


@prop("drain", 43, "furniture", "static", 45.0, "metal", collision="none",
      notes="Storm-drain grate 0.72 x 0.46 m, 3 cm high; bars run along Y.")
def b_drain(a):
    p = a.part()
    p.box((0.64, 0.38, 0.008), (0, 0, 0.004), 'Black')
    for s in (1, -1):
        p.box((0.72, 0.05, 0.03), (0, s * 0.205, 0.015), 'Charcoal')
        p.box((0.05, 0.36, 0.03), (s * 0.335, 0, 0.015), 'Charcoal')
    for i in range(7):
        p.box((0.038, 0.36, 0.024), (-0.24 + i * 0.08, 0, 0.012), 'SteelDark')
    p.box((0.62, 0.035, 0.026), (0, 0, 0.013), 'SteelDark')
    a.add(p)
