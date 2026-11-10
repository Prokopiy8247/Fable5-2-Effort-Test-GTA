"""props_street_fences - 4 m fence / wall / hedge segments and the chain-link gate
(family module of props_street). Slots 52 - 57.

All segments run along X from x = -2 to x = +2 and tile at a 4.0 m pitch (end posts are centred on
x = +-2, so neighbouring segments share them).
"""
import math
import random

import gta_bl as G
from props_street import prop, arc, ngon, rect


def _lattice(p, x0, x1, z0, z1, step, key, y=0.0, wid=0.022, thick=0.008):
    """Chain-link style diamond lattice in the XZ plane: flat diagonal strips clipped to a rect."""
    c = x0 - z1 + step * 0.5
    while c < x1 - z0:                                   # x - z = c
        a0, a1 = max(z0, x0 - c), min(z1, x1 - c)
        if a1 - a0 > 0.06:
            p.strut((a0 + c, y, a0), (a1 + c, y, a1), thick, key, h=wid, cap=False)
        c += step
    c = x0 + z0 + step * 0.5
    while c < x1 + z1:                                   # x + z = c
        a0, a1 = max(z0, c - x1), min(z1, c - x0)
        if a1 - a0 > 0.06:
            p.strut((c - a0, y, a0), (c - a1, y, a1), thick, key, h=wid, cap=False)
        c += step


@prop("fence_chainlink", 52, "fence", "breakable", 60.0, "metal", tile=4.0,
      notes="Chain-link fence, 4.0 m x 2.05 m, posts at x = -2, 0, +2. The mesh is real geometry (lattice).")
def b_fence_chainlink(a):
    p = a.part()
    for x in (-2.0, 0.0, 2.0):
        p.cyl(0.038, 2.03, (x, 0, 1.015), 'Steel', seg=6)
        p.lathe([(0.046, 2.03), (0.046, 2.05), (0.0, 2.08)], 'SteelDark', seg=6, center=(x, 0, 0))
        p.cyl(0.06, 0.03, (x, 0, 0.015), 'ConcreteDark', seg=6)
    p.cyl(0.022, 4.0, (0, 0, 1.97), 'Steel', axis='X', seg=6)
    p.cyl(0.014, 4.0, (0, 0, 0.10), 'Steel', axis='X', seg=4)
    a.add(p, smooth=50)
    q = a.part()
    _lattice(q, -1.97, 1.97, 0.10, 1.97, 0.30, 'Steel')
    a.add(q)


@prop("fence_wood", 53, "fence", "breakable", 85.0, "wood", tile=4.0,
      notes="Timber plank fence, 4.0 m x 1.85 m; planks on the +Y face, rails and posts behind.")
def b_fence_wood(a):
    rng = random.Random(53)
    p = a.part()
    for x in (-2.0, 0.0, 2.0):
        p.box((0.10, 0.10, 1.78), (x, -0.075, 0.89), 'WoodDark')
        p.tbox((0.12, 0.12), (0.03, 0.03), 0.07, (x, -0.075, 1.78), 'WoodDark')
    for z in (0.42, 1.38):
        p.box((4.0, 0.04, 0.09), (0, -0.02, z), 'WoodDark')
    a.add(p)
    q = a.part()
    n = 20
    for i in range(n):
        x0 = -2.0 + i * 0.2 + 0.006
        x1 = x0 + 0.188
        h = 1.80 + rng.choice((0.0, 0.0, -0.03, 0.03, -0.05))
        key = rng.choice(('Wood', 'Wood', 'TrunkLight'))
        q.prism([(x0, 0.05), (x1, 0.05), (x1, h - 0.07), ((x0 + x1) / 2, h), (x0, h - 0.07)], 0.0, 0.024, key, 'Y')
    a.add(q)


@prop("fence_metal", 54, "fence", "breakable", 70.0, "metal", tile=4.0,
      notes="Steel bar railing, 4.0 m x 1.15 m, posts with ball finials at x = -2, 0, +2.")
def b_fence_metal(a):
    p = a.part()
    for x in (-2.0, 0.0, 2.0):
        p.box((0.065, 0.065, 1.10), (x, 0, 0.55), 'Charcoal')
        p.box((0.13, 0.13, 0.025), (x, 0, 0.0125), 'Charcoal')
        p.sph(0.055, (x, 0, 1.135), 'Charcoal', seg=6, rings=4)
    p.box((4.0, 0.055, 0.045), (0, 0, 1.0), 'Charcoal')
    p.box((4.0, 0.04, 0.035), (0, 0, 0.88), 'Charcoal')
    p.box((4.0, 0.04, 0.035), (0, 0, 0.16), 'Charcoal')
    a.add(p)
    q = a.part()
    for i in range(1, 32):
        x = -2.0 + i * 0.125
        if abs(x) < 0.01:
            continue
        q.cyl(0.012, 0.84, (x, 0, 0.58), 'SteelDark', seg=4, cap=False)
    a.add(q)


@prop("wall_low", 55, "fence", "static", 1900.0, "concrete", tile=4.0,
      notes="Low concrete wall, 4.0 m x 0.38 m x 1.0 m (cover height), four 1 m panels with cap stones.")
def b_wall_low(a):
    p = a.part()
    for i in range(4):
        x = -1.5 + i
        p.box((0.992, 0.28, 0.80), (x, 0, 0.50), 'Concrete')
        p.box((0.994, 0.38, 0.10), (x, 0, 0.95), 'Sidewalk')
    a.add(p, bevel=0.016)
    q = a.part()
    q.box((4.0, 0.34, 0.10), (0, 0, 0.05), 'ConcreteDark')
    q.box((3.99, 0.26, 0.80), (0, 0, 0.50), 'ConcreteDark')                 # dark core seen through the joints
    a.add(q)


@prop("hedge", 56, "fence", "static", 120.0, "foliage", tile=4.0,
      notes="Clipped hedge, 4.0 m x 0.9 m x 1.2 m, faceted; flat ends so segments tile.")
def b_hedge(a):
    rng = random.Random(56)
    base = [(-0.40, 0.0), (0.40, 0.0), (0.46, 0.26), (0.46, 0.84), (0.39, 1.08), (0.20, 1.17), (-0.20, 1.17),
            (-0.39, 1.08), (-0.46, 0.84), (-0.46, 0.26)]
    ns = 13
    secs = []
    for i in range(ns):
        x = -2.0 + 4.0 * i / (ns - 1)
        end = i in (0, ns - 1)
        sec = []
        for j, (y, z) in enumerate(base):
            jx = 0.0 if end else rng.uniform(-0.07, 0.07)
            jy = rng.uniform(-0.055, 0.055) * (0.4 if end else 1.0)
            jz = 0.0 if z == 0.0 else rng.uniform(-0.05, 0.05) * (0.4 if end else 1.0)
            sec.append((x + jx, y + jy, z + jz))
        secs.append(sec)
    p = a.part()
    keys = [p.mi('LeafDark'), p.mi('Leaf'), p.mi('LeafLight')]
    p.loft(secs, 'Leaf')
    for f in p.bm.faces:
        c = f.calc_center_median()
        if len(f.verts) > 4:
            f.material_index = keys[1]
        elif c.z < 0.36:
            f.material_index = keys[0]
        elif c.z > 1.0:
            f.material_index = keys[2]
        else:
            f.material_index = keys[1] if rng.random() < 0.72 else keys[rng.choice((0, 2))]
    a.add(p)
    q = a.part()
    q.box((4.0, 0.70, 0.04), (0, 0, 0.02), 'Dirt')
    a.add(q)


@prop("gate_chainlink", 57, "fence", "breakable", 110.0, "metal",
      notes="Double chain-link gate for a 4.0 m opening. 'Mesh' = the two hinge posts (x = -2 / +2); leaves "
            "'Gate_L' (-X side) and 'Gate_R' (+X side) are separate children with their origin on the hinge "
            "axis: rotate them about local Z (Godot Y) to open.")
def b_gate_chainlink(a):
    p = a.part()
    for x in (-2.0, 2.0):
        p.cyl(0.055, 2.15, (x, 0, 1.075), 'Steel', seg=8)
        p.lathe([(0.065, 2.15), (0.065, 2.18), (0.0, 2.23)], 'SteelDark', seg=8, center=(x, 0, 0))
        p.cyl(0.09, 0.04, (x, 0, 0.02), 'ConcreteDark', seg=8)
    a.add(p, smooth=50)
    for name, s in (("Gate_L", -1), ("Gate_R", 1)):
        xh = s * 1.93                         # hinge side
        xc = s * 0.02                         # centre side
        lo, hi = min(xh, xc), max(xh, xc)
        g = a.part()
        g.tube([(lo, 0, 0.10), (hi, 0, 0.10), (hi, 0, 1.98), (lo, 0, 1.98)], 0.024, 'Steel', seg=6, closed=True)
        g.strut((xh, 0, 0.10), (xc, 0, 1.98), 0.02, 'Steel', h=0.03, cap=False)
        _lattice(g, lo + 0.02, hi - 0.02, 0.12, 1.96, 0.30, 'Steel')
        for z in (0.45, 1.65):                # hinge straps
            g.box((0.09, 0.05, 0.05), (s * 1.955, 0, z), 'SteelDark')
        if s < 0:                             # latch + padlock on the left leaf, drop rod on the right
            g.box((0.14, 0.05, 0.06), (0.0, 0.0, 1.05), 'SteelDark')
            g.box((0.06, 0.03, 0.07), (0.0, 0.04, 0.99), 'Brass')
        else:
            g.cyl(0.012, 0.60, (xc + 0.05, 0.03, 0.34), 'SteelDark', seg=4)
        a.child(name, g, origin=(s * 2.0, 0, 0))
