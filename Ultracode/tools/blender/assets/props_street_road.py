"""props_street_road - barriers, cones, bollards and road-kit pieces (family module of props_street).

Slots 12 - 25. Imported / reloaded by props_street._load_families().
"""
import math

import gta_bl as G
from props_street import prop, arc, ngon, rect

# jersey barrier cross-section (y, z); +Y = road side
JERSEY = [(-0.30, 0.0), (0.30, 0.0), (0.30, 0.08), (0.17, 0.30), (0.10, 0.84), (-0.10, 0.84), (-0.17, 0.30),
          (-0.30, 0.08)]


def _scaled(profile, sy, sz):
    return [(y * sy, z * sz) for y, z in profile]


@prop("barrier_concrete", 12, "barrier", "static", 1800.0, "concrete", tile=3.0,
      notes="Jersey barrier, 3.0 m long along X, 0.84 m high (cover). Tiles end to end at a 3.0 m pitch.")
def b_barrier_concrete(a):
    p = a.part()
    p.prism(JERSEY, -1.49, 1.49, 'Concrete', 'X')
    a.add(p, bevel=0.022)
    q = a.part()
    for x in (-0.80, 0.80):
        q.box((0.34, 0.615, 0.065), (x, 0, 0.0335), 'ConcreteDark')          # drain / fork slots
    for s in (1, -1):
        for x in (-0.95, 0.0, 0.95):
            q.box((0.13, 0.02, 0.07), (x, s * 0.131, 0.62), 'SafetyOrange', rot=(s * math.radians(-7.4), 0, 0))
    for x in (-1.0, 1.0):
        q.cyl(0.035, 0.012, (x, 0, 0.845), 'ConcreteDark', seg=6)           # lifting sockets
    a.add(q)


@prop("barrier_plastic", 13, "barrier", "dynamic", 60.0, "rubber", tile=2.0,
      notes="Water-filled plastic barrier (orange with white panels), 2.0 m pitch along X.")
def b_barrier_plastic(a):
    prof = [(-0.27, 0.0), (0.27, 0.0), (0.27, 0.15), (0.165, 0.32), (0.135, 0.90), (-0.135, 0.90), (-0.165, 0.32),
            (-0.27, 0.15)]
    p = a.part()
    p.prism(prof, -0.92, 0.92, 'SafetyOrange', 'X')
    p.box((0.16, 0.17, 0.24), (0.99, 0, 0.47), 'SafetyOrange')              # interlock knuckles
    p.box((0.16, 0.17, 0.18), (-0.99, 0, 0.22), 'SafetyOrange')
    p.box((0.16, 0.17, 0.18), (-0.99, 0, 0.72), 'SafetyOrange')
    a.add(p, bevel=0.03)
    q = a.part()
    for x in (-0.45, 0.45):
        q.tbox((0.50, 0.336), (0.50, 0.296), 0.44, (x, 0, 0.39), 'White')   # raised reflective panels
    q.box((0.30, 0.55, 0.08), (-0.45, 0, 0.041), 'Charcoal')                # fork pockets
    q.box((0.30, 0.55, 0.08), (0.45, 0, 0.041), 'Charcoal')
    q.cyl(0.065, 0.035, (0, 0, 0.915), 'White', seg=8)                      # fill cap
    q.cyl(0.03, 0.02, (0.55, 0, 0.908), 'Charcoal', seg=6)
    a.add(q)


@prop("barrier_fence", 14, "barrier", "dynamic", 18.0, "metal", tile=2.3,
      notes="Crowd-control barrier, 2.2 m wide tube frame with flat feet.")
def b_barrier_fence(a):
    W, H0, H1, R = 1.10, 0.17, 1.08, 0.13
    p = a.part()
    loop = (arc((W - R, 0, H1 - R), R, 0, 90, 3) + arc((-W + R, 0, H1 - R), R, 90, 180, 3) +
            arc((-W + R, 0, H0 + R), R, 180, 270, 3) + arc((W - R, 0, H0 + R), R, 270, 360, 3))
    p.tube(loop, 0.022, 'Steel', seg=6, closed=True)
    n = 13
    for i in range(n):
        x = -W + 0.15 + i * (2 * W - 0.30) / (n - 1)
        p.cyl(0.010, H1 - H0, (x, 0, (H0 + H1) / 2), 'Steel', seg=4, cap=False)
    for x in (-0.78, 0.78):
        p.cyl(0.022, 0.16, (x, 0, 0.10), 'Steel', seg=6)
        p.box((0.06, 0.62, 0.025), (x, 0, 0.0125), 'SteelDark')
        p.box((0.06, 0.10, 0.03), (x, 0, 0.035), 'SteelDark')
    # hook + eye connectors on the ends
    p.box((0.05, 0.025, 0.07), (W + 0.035, 0, 0.80), 'SteelDark')
    p.box((0.05, 0.025, 0.07), (W + 0.035, 0, 0.42), 'SteelDark')
    p.box((0.04, 0.05, 0.03), (-W - 0.03, 0, 0.80), 'SteelDark')
    p.box((0.04, 0.05, 0.03), (-W - 0.03, 0, 0.42), 'SteelDark')
    a.add(p, smooth=50)
    q = a.part()
    q.box((0.70, 0.016, 0.24), (0, 0, 0.82), 'Teal')                        # city plate
    for s in (1, -1):
        q.box((0.62, 0.006, 0.05), (0, s * 0.010, 0.82), 'White')
    a.add(q)


def _striped_board(q, length, height, n, slant, colors, tilt, y, z, thick=0.03):
    """Board along X with slanted colour bands, tilted about X by `tilt` and moved to (0, y, z)."""
    from mathutils import Matrix
    hl, hh = length / 2, height / 2
    M = Matrix.Translation((0, y, z)) @ Matrix.Rotation(tilt, 4, 'X')
    for k in range(n):
        x0 = -hl + k * length / n
        x1 = -hl + (k + 1) * length / n
        b0, t0 = (x0 - slant, x0 + slant) if k > 0 else (x0, x0)
        b1, t1 = (x1 - slant, x1 + slant) if k < n - 1 else (x1, x1)
        rings = q.prism([(b0, -hh), (b1, -hh), (t1, hh), (t0, hh)], -thick / 2, thick / 2, colors[k % len(colors)], 'Y')
        G.transform(rings, M)


@prop("roadblock_police", 15, "barrier", "dynamic", 22.0, "wood",
      notes="Police A-frame barricade, 2.6 m wide, blue / white banded boards on both sides, two blue beacons "
            "(material P_SirenBlue, mildly emissive).")
def b_roadblock_police(a):
    tilt = math.atan2(0.30, 1.02)
    p = a.part()
    for x in (-1.0, 1.0):
        for s in (-1, 1):
            p.strut((x, s * 0.345, 0.012), (x, s * 0.045, 1.03), 0.055, 'PoliceWhite', h=0.07)
        p.box((0.05, 0.40, 0.05), (x, 0, 0.36), 'PoliceWhite')
        p.box((0.09, 0.15, 0.07), (x, 0, 1.035), 'SteelDark')
    a.add(p)
    q = a.part()
    for s in (1, -1):
        _striped_board(q, 2.6, 0.22, 8, 0.07, ('PoliceBlue', 'PoliceWhite'), -s * tilt, s * 0.125, 0.86)
        _striped_board(q, 2.6, 0.12, 8, 0.04, ('PoliceWhite', 'PoliceBlue'), -s * tilt, s * 0.225, 0.50, thick=0.026)
    a.add(q)
    g = a.part()
    for x in (-1.0, 1.0):
        g.cyl(0.05, 0.035, (x, 0, 1.085), 'Charcoal', seg=8)
        g.lathe([(0.045, 1.10), (0.045, 1.16), (0.028, 1.20), (0.0, 1.215)], 'SirenBlue', seg=8, center=(x, 0, 0))
    a.add(g, smooth=50)


@prop("cone", 16, "barrier", "dynamic", 3.5, "rubber", notes="Traffic cone, 0.75 m.")
def b_cone(a):
    p = a.part()
    p.box((0.40, 0.40, 0.035), (0, 0, 0.0175), 'Black')
    a.add(p, bevel=0.012)
    q = a.part()

    def r(z):
        return 0.150 - (z - 0.03) * 0.1667
    zs = [0.03, 0.27, 0.40, 0.49, 0.57, 0.75]
    q.lathe([(0.185, 0.03), (0.185, 0.045), (r(0.05), 0.05)] + [(r(z), z) for z in zs[1:]],
            'SafetyOrange', seg=10,
            mats=['SafetyOrange', 'SafetyOrange', 'SafetyOrange', 'White', 'SafetyOrange', 'White', 'SafetyOrange'])
    a.add(q, smooth=42)


@prop("delineator", 17, "barrier", "dynamic", 4.0, "rubber", notes="Flexible lane delineator post, 1.1 m.")
def b_delineator(a):
    p = a.part()
    p.lathe([(0.15, 0.0), (0.15, 0.03), (0.075, 0.075), (0.052, 0.10)], 'Black', seg=8)
    p.lathe([(0.042, 0.10), (0.042, 0.62), (0.042, 0.72), (0.042, 0.80), (0.042, 0.90), (0.042, 1.04), (0.03, 1.085),
             (0.0, 1.10)], 'SafetyOrange', seg=8,
            mats=['SafetyOrange', 'White', 'SafetyOrange', 'White', 'SafetyOrange', 'SafetyOrange', 'SafetyOrange'])
    a.add(p, smooth=50)
    q = a.part()
    q.box((0.10, 0.012, 0.035), (0, 0, 1.07), 'SafetyOrange')               # grab handle
    a.add(q)


@prop("bollard", 18, "barrier", "static", 60.0, "metal", notes="Steel street bollard with a yellow band, 0.96 m.")
def b_bollard(a):
    p = a.part()
    p.lathe([(0.135, 0.0), (0.135, 0.04), (0.105, 0.075), (0.095, 0.60), (0.108, 0.62), (0.108, 0.72), (0.095, 0.74),
             (0.095, 0.86), (0.068, 0.93), (0.0, 0.96)], 'Charcoal', seg=10,
            mats=['Charcoal', 'Charcoal', 'Charcoal', 'Charcoal', 'HazardYellow', 'Charcoal', 'Charcoal', 'Charcoal',
                  'Charcoal'])
    a.add(p, smooth=42)


@prop("bollard_light", 19, "barrier", "static", 25.0, "metal",
      notes="Illuminated path bollard, 0.9 m. Lit section = M_LampGlow; marker 'Light' at its centre.")
def b_bollard_light(a):
    p = a.part()
    p.lathe([(0.125, 0.0), (0.125, 0.035), (0.092, 0.06), (0.092, 0.58)], 'SteelDark', seg=10)
    p.lathe([(0.105, 0.80), (0.105, 0.845), (0.06, 0.885), (0.0, 0.895)], 'SteelDark', seg=10)
    for z in (0.625, 0.69, 0.755):
        p.lathe([(0.076, z - 0.012), (0.098, z - 0.012), (0.098, z + 0.012), (0.076, z + 0.012)], 'SteelDark', seg=10,
                cap=False)
    a.add(p, smooth=42)
    g = a.part()
    g.cyl(0.078, 0.22, (0, 0, 0.69), 'M_LampGlow', seg=10, cap=False)
    a.add(g, smooth=42)
    a.marker("Light", (0, 0, 0.69))


CURB = [(-0.15, 0.0), (0.15, 0.0), (0.15, 0.105), (0.105, 0.15), (-0.15, 0.15)]


@prop("curb_straight", 20, "road", "static", 320.0, "concrete", tile=4.0,
      notes="Kerb, 4 stones = 4.0 m along X, 0.30 deep, 0.15 high; chamfered road face toward +Y.")
def b_curb_straight(a):
    p = a.part()
    for i in range(4):
        x0 = -2.0 + i
        p.prism(CURB, x0 + 0.004, x0 + 0.996, 'Curb', 'X')
    a.add(p, bevel=0.01)


@prop("curb_corner", 21, "road", "static", 130.0, "concrete",
      notes="Quarter-circle kerb, centre-line radius 1.0 m. ORIGIN = centre of the arc (not the bbox centre); "
            "the arc runs from (1,0) to (0,1) in Blender XY = Godot (1,0,0) to (0,0,-1). Road on the outside.")
def b_curb_corner(a):
    p = a.part()
    R = 1.0
    for k in range(3):
        a0 = math.radians(30 * k + 0.3)
        a1 = math.radians(30 * (k + 1) - 0.3)
        secs = []
        for t in (0.0, 0.5, 1.0):
            an = a0 + (a1 - a0) * t
            secs.append([((R + y) * math.cos(an), (R + y) * math.sin(an), z) for y, z in CURB])
        p.loft(secs, 'Curb')
    a.add(p, bevel=0.01, bevel_angle=40)


@prop("speed_bump", 22, "road", "static", 45.0, "rubber", collision="trimesh",
      notes="Rubber speed bump 3.0 m (X) x 0.42 m x 0.065 m, yellow / black segments.")
def b_speed_bump(a):
    prof = [(-0.21, 0.0), (0.21, 0.0), (0.14, 0.042), (0.05, 0.065), (-0.05, 0.065), (-0.14, 0.042)]
    p = a.part()
    for i in range(6):
        x0 = -1.35 + i * 0.45
        p.prism(prof, x0, x0 + 0.45, ('HazardYellow', 'Black')[i % 2], 'X')
    for s in (1, -1):
        p.loft([[(s * 1.35, y, z) for y, z in prof], [(s * 1.5, y * 0.55, z * 0.25) for y, z in prof]], 'Black')
    a.add(p)
    q = a.part()
    for i in (0, 2, 4):
        x = -1.35 + i * 0.45 + 0.225
        q.box((0.05, 0.05, 0.012), (x, 0, 0.066), 'Chrome')                 # cat-eye studs
    a.add(q)


@prop("guardrail", 23, "road", "static", 110.0, "metal", tile=4.0,
      notes="W-beam guardrail, 4.0 m along X, posts at x = -1 and +1 (2 m spacing when tiled). Road side = +Y.")
def b_guardrail(a):
    front = [(0.0, 0.40), (0.05, 0.435), (0.05, 0.495), (0.0, 0.56), (0.05, 0.625), (0.05, 0.685), (0.0, 0.72)]
    back = [(y - 0.022, z) for y, z in reversed(front)]
    p = a.part()
    p.prism(front + back, -2.0, 2.0, 'Steel', 'X')
    for x in (-1.0, 1.0):
        p.box((0.10, 0.012, 0.80), (x, -0.062, 0.40), 'SteelDark')          # I-beam post
        p.box((0.012, 0.11, 0.80), (x, -0.12, 0.40), 'SteelDark')
        p.box((0.10, 0.012, 0.80), (x, -0.178, 0.40), 'SteelDark')
        p.box((0.10, 0.04, 0.30), (x, -0.036, 0.56), 'SteelDark')           # spacer block
        p.box((0.035, 0.02, 0.035), (x, 0.004, 0.56), 'Chrome')             # bolt
        p.box((0.07, 0.012, 0.05), (x + 0.12, 0.004, 0.56), 'SafetyOrange')  # reflector
    a.add(p)


@prop("jersey_end", 24, "road", "static", 700.0, "concrete",
      notes="Sloped terminal for barrier_concrete, 1.5 m. Full profile at x = -0.75 (mates with a barrier end), "
            "nose with hazard bands at x = +0.75.")
def b_jersey_end(a):
    def sec(x):
        t = (x + 0.75) / 1.5
        return [(x, y * (1 - 0.12 * t), z * (1 - 0.72 * t)) for y, z in JERSEY]
    p = a.part()
    p.loft([sec(-0.74), sec(0.30)], 'Concrete')
    a.add(p, bevel=0.02)
    q = a.part()
    for x0, x1, key in ((0.30, 0.45, 'Black'), (0.45, 0.60, 'HazardYellow'), (0.60, 0.75, 'Black')):
        q.loft([sec(x0), sec(x1)], key)
    q.box((0.30, 0.60, 0.06), (-0.30, 0, 0.031), 'ConcreteDark')
    a.add(q)


@prop("parking_stop", 25, "road", "static", 95.0, "concrete", collision="box",
      notes="Parking-bay wheel stop, 1.8 m x 0.18 m x 0.10 m, yellow bands.")
def b_parking_stop(a):
    prof = [(-0.09, 0.0), (0.09, 0.0), (0.062, 0.10), (-0.062, 0.10)]
    p = a.part()
    p.prism(prof, -0.9, 0.9, 'Concrete', 'X')
    a.add(p, bevel=0.012)
    q = a.part()
    big = [(y * 1.04, z * 1.04) for y, z in prof]
    for x in (-0.62, 0.0, 0.62):
        q.prism(big, x - 0.11, x + 0.11, 'HazardYellow', 'X')
    for x in (-0.33, 0.33):
        q.cyl(0.022, 0.012, (x, 0, 0.102), 'Charcoal', seg=6)
    a.add(q)
