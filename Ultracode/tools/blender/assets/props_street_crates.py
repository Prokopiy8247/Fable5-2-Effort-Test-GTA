"""props_street_crates - crates, barrels, loose yard / alley clutter (family module of props_street).
Slots 58, 59, 65 - 71, 77.
"""
import math
import random

from mathutils import Matrix

import gta_bl as G
from props_street import prop, arc, ngon, rect


def _since(part, n0):
    return part.bm.verts[:][n0:]


def _crate(p, s, h, pos=(0, 0, 0), rz=0.0, braces=True):
    """Wooden crate: plank core + frame boards (+ diagonal braces), s x s x h, bottom centre at pos."""
    n0 = len(p.bm.verts)
    e = 0.085
    p.box((s - 0.05, s - 0.05, h - 0.05), (0, 0, h / 2), 'Wood')
    c = s / 2 - e / 2
    for sx in (1, -1):
        for sy in (1, -1):
            p.box((e, e, h), (sx * c, sy * c, h / 2), 'WoodDark')
    for z in (e / 2, h - e / 2):
        for sgn in (1, -1):
            p.box((s - 2 * e, e, e), (0, sgn * c, z), 'WoodDark')
            p.box((e, s - 2 * e, e), (sgn * c, 0, z), 'WoodDark')
    if braces:
        o = s / 2 - 0.012
        d = s / 2 - e
        for sgn in (1, -1):
            p.strut((-d, sgn * o, e), (d, sgn * o, h - e), 0.03, 'WoodDark', h=0.075)
            p.strut((sgn * o, -d, h - e), (sgn * o, d, e), 0.03, 'WoodDark', h=0.075)
    p.box((s - 2 * e, 0.09, 0.03), (0, 0, h - 0.012), 'WoodDark')
    G.transform(_since(p, n0), Matrix.Translation(pos) @ Matrix.Rotation(rz, 4, 'Z'))


@prop("crate_wood", 58, "container", "dynamic", 45.0, "wood", notes="Wooden shipping crate, 0.9 m cube.")
def b_crate_wood(a):
    p = a.part()
    _crate(p, 0.90, 0.90)
    a.add(p)


@prop("crate_stack", 59, "container", "dynamic", 150.0, "wood",
      notes="Stack of four crates (one rigid group), about 1.9 x 1.6 x 1.6 m.")
def b_crate_stack(a):
    p = a.part()
    _crate(p, 0.90, 0.90, (-0.48, 0.0, 0.0), math.radians(4))
    _crate(p, 0.80, 0.80, (0.45, 0.06, 0.0), math.radians(-9))
    _crate(p, 0.70, 0.70, (-0.42, 0.02, 0.90), math.radians(24))
    _crate(p, 0.52, 0.48, (0.38, -0.70, 0.0), math.radians(15), braces=False)
    a.add(p)


@prop("pallet", 65, "container", "dynamic", 22.0, "wood", notes="Timber pallet 1.2 x 1.0 x 0.15 m.")
def b_pallet(a):
    p = a.part()
    for i in range(7):
        p.box((0.105, 1.0, 0.022), (-0.5475 + i * 0.1825, 0, 0.133), ('Wood', 'TrunkLight')[i % 2])
    for y in (-0.45, 0.0, 0.45):
        p.box((1.2, 0.10, 0.022), (0, y, 0.011), 'Wood')
        for x in (-0.54, 0.0, 0.54):
            p.box((0.12, 0.10, 0.10), (x, y, 0.072), 'WoodDark')
    a.add(p)


_DRUM = [(0.268, 0.0), (0.287, 0.014), (0.287, 0.036), (0.274, 0.048), (0.274, 0.282), (0.291, 0.296), (0.291, 0.318),
         (0.274, 0.332), (0.274, 0.558), (0.291, 0.572), (0.291, 0.594), (0.274, 0.608), (0.274, 0.842), (0.287, 0.854),
         (0.287, 0.876), (0.270, 0.886), (0.262, 0.858)]


def _drum(a, body, mid=None, lid=None):
    p = a.part()
    mats = [body] * (len(_DRUM) - 1)
    if mid:
        mats[7] = mid
    if lid:
        mats[-1] = lid
        mats[-2] = lid
    p.lathe(_DRUM, body, seg=12, mats=mats)
    p.cyl(0.035, 0.022, (0.14, 0.05, 0.866), 'Steel', seg=6)
    p.cyl(0.02, 0.018, (-0.15, -0.08, 0.864), 'Steel', seg=6)
    a.add(p, smooth=40)


@prop("barrel", 66, "container", "dynamic", 30.0, "metal", notes="Steel drum (200 l), 0.58 x 0.89 m, blue.")
def b_barrel(a):
    _drum(a, 'CarBlue')
    q = a.part()
    q.box((0.20, 0.008, 0.11), (0, 0.276, 0.70), 'White')
    q.box((0.14, 0.006, 0.022), (0, 0.281, 0.72), 'CarBlue')
    q.box((0.10, 0.006, 0.022), (0, 0.281, 0.68), 'CarBlue')
    a.add(q)


@prop("barrel_explosive", 67, "container", "dynamic", 60.0, "metal",
      notes="Explosive fuel drum: red, yellow hazard band, flame diamonds front and back. The game makes it "
            "damageable / explosive.")
def b_barrel_explosive(a):
    _drum(a, 'FireRed', mid='HazardYellow', lid='Black')
    q = a.part()
    for s in (1, -1):
        q.box((0.19, 0.008, 0.19), (0, s * 0.277, 0.445), 'White', rot=(0, math.radians(45), 0))
        q.box((0.15, 0.008, 0.15), (0, s * 0.281, 0.445), 'Black', rot=(0, math.radians(45), 0))
        y0, y1 = (0.285, 0.290) if s > 0 else (-0.290, -0.285)
        q.prism([(-0.045, 0.40), (0.045, 0.40), (0.055, 0.455), (0.022, 0.44), (0.0, 0.52), (-0.03, 0.455),
                 (-0.055, 0.47)], y0, y1, 'HazardYellow', 'Y')
    a.add(q)


@prop("gas_canister", 68, "container", "dynamic", 24.0, "metal",
      notes="Propane cylinder 0.33 x 0.62 m, orange; meant as an explosive physics prop.")
def b_gas_canister(a):
    p = a.part()
    p.lathe([(0.135, 0.0), (0.15, 0.0), (0.15, 0.055), (0.135, 0.055)], 'Charcoal', seg=10, cap=False)
    p.lathe([(0.09, 0.03), (0.155, 0.06), (0.166, 0.10), (0.166, 0.335), (0.166, 0.385), (0.155, 0.43), (0.105, 0.485),
             (0.04, 0.505)], 'SafetyOrange', seg=10,
            mats=['SafetyOrange', 'SafetyOrange', 'SafetyOrange', 'White', 'SafetyOrange', 'SafetyOrange',
                  'SafetyOrange'])
    p.lathe([(0.095, 0.47), (0.112, 0.47), (0.112, 0.605), (0.095, 0.605)], 'SafetyOrange', seg=10, cap=False)
    p.cyl(0.026, 0.07, (0, 0, 0.535), 'Brass', seg=6)
    p.cyl(0.048, 0.016, (0, 0, 0.578), 'Charcoal', seg=6)
    p.cyl(0.014, 0.06, (0, 0.04, 0.54), 'Brass', axis='Y', seg=5)
    a.add(p, smooth=40)
    q = a.part()
    for s in (1, -1):
        q.box((0.014, 0.085, 0.04), (s * 0.108, 0, 0.555), 'Black')          # grip cut-outs
    q.box((0.13, 0.008, 0.13), (0, 0.166, 0.26), 'White', rot=(0, math.radians(45), 0))
    q.prism([(-0.03, 0.225), (0.03, 0.225), (0.038, 0.265), (0.014, 0.255), (0.0, 0.31), (-0.02, 0.265),
             (-0.038, 0.275)], 0.171, 0.175, 'FireRed', 'Y')
    a.add(q)


_TIRE = [(0.19, 0.03), (0.29, 0.0), (0.335, 0.04), (0.335, 0.17), (0.29, 0.21), (0.19, 0.18), (0.19, 0.03)]


@prop("tire_stack", 69, "container", "dynamic", 45.0, "rubber",
      notes="Four stacked tyres plus one leaning against the stack, 0.85 m high.")
def b_tire_stack(a):
    p = a.part()
    offs = ((0.0, 0.0), (0.03, -0.02), (-0.025, 0.03), (0.035, 0.02))
    for i, (x, y) in enumerate(offs):
        p.lathe(_TIRE, 'Tire', seg=10, center=(x, y, i * 0.21), cap=False, phase=i * 0.4)
    n0 = len(p.bm.verts)
    p.lathe(_TIRE, 'Tire', seg=10, center=(-0.105, 0, 0), axis='X', cap=False)
    G.transform(p.bm.verts[:][n0:], Matrix.Translation((0.50, -0.02, 0.325)) @ Matrix.Rotation(math.radians(-17), 4, 'Y'))
    a.add(p, smooth=40)
    q = a.part()
    q.cyl(0.19, 0.012, (0.035, 0.02, 0.66), 'Black', seg=10)                # dark well inside the top tyre
    a.add(q)


def _bag(p, c, r, key, rng, squash=0.78):
    vs = p.sph(r, c, key, seg=8, rings=5, scale=(1, 1, squash))
    zmin = c[2] - r * squash
    floor = zmin + r * 0.22
    for v in vs:
        v.co.x += rng.uniform(-0.10, 0.10) * r
        v.co.y += rng.uniform(-0.10, 0.10) * r
        v.co.z += rng.uniform(-0.07, 0.07) * r
        if v.co.z < floor:
            v.co.z = floor
    top = c[2] + r * squash
    p.cyl(0.045, 0.06, (c[0], c[1], top + 0.01), key, seg=6, r2=0.02)
    p.cyl(0.02, 0.07, (c[0] + 0.01, c[1], top + 0.07), key, seg=6, r2=0.07)
    return floor


@prop("trash_bags", 70, "container", "dynamic", 14.0, "rubber",
      notes="Pile of three tied rubbish bags (one rigid group), about 1.2 x 1.0 x 0.75 m.")
def b_trash_bags(a):
    rng = random.Random(70)
    p = a.part()
    bags = (((-0.26, 0.05, 0.0), 0.36, 'Black'), ((0.28, 0.10, 0.0), 0.31, 'Charcoal'),
            ((0.04, -0.30, 0.0), 0.27, 'White'))
    for (x, y, _z), r, key in bags:
        sq = 0.80
        cz = r * sq - r * 0.22
        _bag(p, (x, y, cz), r, key, rng, sq)
    a.add(p)


def _carton(p, size, pos, rz, key='Khaki', taped=True):
    n0 = len(p.bm.verts)
    sx, sy, sz = size
    p.box((sx, sy, sz), (0, 0, sz / 2), key)
    if taped:
        p.box((sx + 0.006, 0.055, sz + 0.006), (0, 0, sz / 2), 'Cream')
        p.box((0.12, 0.004, 0.08), (sx * 0.2, sy / 2 + 0.002, sz * 0.6), 'White')
    G.transform(p.bm.verts[:][n0:], Matrix.Translation(pos) @ Matrix.Rotation(rz, 4, 'Z'))


@prop("cardboard_boxes", 71, "container", "dynamic", 9.0, "wood",
      notes="Pile of cardboard cartons, one of them open (one rigid group), about 1.25 x 1.0 x 0.75 m.")
def b_cardboard_boxes(a):
    p = a.part()
    _carton(p, (0.62, 0.46, 0.40), (-0.22, 0.05, 0.0), math.radians(6))
    _carton(p, (0.40, 0.34, 0.30), (-0.25, 0.06, 0.40), math.radians(-18))
    _carton(p, (0.46, 0.40, 0.34), (0.38, 0.18, 0.0), math.radians(-12), taped=False)
    # the third carton is open: dark inside + four flaps
    n0 = len(p.bm.verts)
    p.box((0.42, 0.36, 0.01), (0, 0, 0.338), 'Leather')
    for s in (1, -1):
        p.box((0.46, 0.20, 0.012), (0, s * 0.275, 0.385), 'Khaki', rot=(s * math.radians(38), 0, 0))
        p.box((0.17, 0.40, 0.012), (s * 0.29, 0, 0.30), 'Khaki', rot=(0, s * math.radians(62), 0))
    G.transform(p.bm.verts[:][n0:], Matrix.Translation((0.38, 0.18, 0.0)) @ Matrix.Rotation(math.radians(-12), 4, 'Z'))
    _carton(p, (0.34, 0.26, 0.24), (0.18, -0.34, 0.0), math.radians(28))
    # flattened sheet leaning on the pile
    p.box((0.56, 0.012, 0.60), (-0.625, -0.02, 0.354), 'Khaki', rot=(0, math.radians(-12), math.radians(84)))
    a.add(p)


@prop("shopping_cart", 77, "container", "dynamic", 22.0, "metal",
      notes="Wire shopping trolley 0.6 x 1.0 x 1.03 m; push handle at -Y, nose toward +Y.")
def b_shopping_cart(a):
    def lerp(p0, p1, t):
        return tuple(p0[i] + (p1[i] - p0[i]) * t for i in range(3))
    W = 0.008
    p = a.part()
    for s in (1, -1):
        tr, tf = (s * 0.27, -0.36, 0.93), (s * 0.22, 0.52, 0.90)
        br, bf = (s * 0.21, -0.29, 0.53), (s * 0.16, 0.44, 0.57)
        for k in range(7):
            t = k / 6.0
            p.strut(lerp(br, bf, t), lerp(tr, tf, t), W, 'Steel', cap=False)
        for u in (0.36, 0.70):
            p.strut(lerp(br, tr, u), lerp(bf, tf, u), W, 'Steel', cap=False)
        # chassis side tube
        p.tube([(s * 0.27, -0.47, 0.99), (s * 0.27, -0.41, 0.55), (s * 0.25, -0.37, 0.17), (s * 0.17, 0.43, 0.15)],
               0.014, 'Steel', seg=5)
        p.strut((s * 0.25, -0.37, 0.24), (s * 0.17, 0.43, 0.22), W, 'Steel', cap=False)
    for end, (yt, zt, yb, zb, xt, xb) in enumerate(((0.52, 0.90, 0.44, 0.57, 0.22, 0.16),
                                                    (-0.36, 0.93, -0.29, 0.53, 0.27, 0.21))):
        for k in range(1, 4):
            t = k / 4.0
            p.strut((-xb + 2 * xb * t, yb, zb), (-xt + 2 * xt * t, yt, zt), W, 'Steel', cap=False)
        for u in (0.36, 0.70):
            xa = xb + (xt - xb) * u
            p.strut((-xa, yb + (yt - yb) * u, zb + (zt - zb) * u), (xa, yb + (yt - yb) * u, zb + (zt - zb) * u), W,
                    'Steel', cap=False)
    for k in range(1, 4):                                                   # floor wires
        t = k / 4.0
        p.strut((-0.21 + 0.42 * t, -0.29, 0.53), (-0.16 + 0.32 * t, 0.44, 0.57), W, 'Steel', cap=False)
    for t in (0.25, 0.5, 0.75):
        y = -0.29 + 0.73 * t
        xw = 0.21 - 0.05 * t
        p.strut((-xw, y, 0.53 + 0.04 * t), (xw, y, 0.53 + 0.04 * t), W, 'Steel', cap=False)
        p.strut((-(0.25 - 0.08 * t), -0.37 + 0.80 * t, 0.24 - 0.02 * t), ((0.25 - 0.08 * t), -0.37 + 0.80 * t, 0.24 - 0.02 * t),
                W, 'Steel', cap=False)
    p.tube([(0.27, -0.36, 0.93), (0.22, 0.52, 0.90), (-0.22, 0.52, 0.90), (-0.27, -0.36, 0.93)], 0.012, 'Steel',
           seg=4, closed=True)
    p.tube([(0.21, -0.29, 0.53), (0.16, 0.44, 0.57), (-0.16, 0.44, 0.57), (-0.21, -0.29, 0.53)], 0.010, 'Steel',
           seg=4, closed=True)
    p.cyl(0.012, 0.36, (0, 0.43, 0.15), 'Steel', axis='X', seg=4)
    p.cyl(0.012, 0.52, (0, -0.37, 0.17), 'Steel', axis='X', seg=4)
    a.add(p)
    q = a.part()
    q.cyl(0.02, 0.56, (0, -0.47, 0.99), 'CarRed', axis='X', seg=6)          # handle grip
    q.box((0.44, 0.016, 0.20), (0, -0.345, 0.80), 'CarRed', rot=(math.radians(-10), 0, 0))   # child seat flap
    for x, y in ((0.25, -0.37), (-0.25, -0.37), (0.17, 0.43), (-0.17, 0.43)):
        q.cyl(0.058, 0.032, (x, y - 0.03, 0.058), 'Tire', axis='X', seg=8)
        q.box((0.05, 0.03, 0.10), (x, y - 0.01, 0.12), 'SteelDark')
    a.add(q, smooth=42)
