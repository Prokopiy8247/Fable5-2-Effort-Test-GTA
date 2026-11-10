"""props_street_signage - neon signs and billboards (family module of props_street).
Slots 78 - 83.

Neon signs are wall-mounted: origin = centre of the back face (wall plane y = 0), they stick out
toward +Y. Tubes use the emissive palette materials P_Neon*.
Billboard faces use M_Billboard_A / M_Billboard_B with a 0-1 UV square (see props_street.fit_uv),
so the game may swap in its own advert material; the geometric artwork in front of the face is
made of ordinary palette materials.
"""
import math

from mathutils import Matrix

import gta_bl as G
import props_street as S
from props_street import prop, arc, ngon, rect


@prop("neon_sign_a", 78, "signage", "static", 14.0, "metal", anchor="wall", emissive="P_NeonMagenta, P_NeonYellow",
      notes="Neon arrow pointing down, 1.35 x 1.75 m. Wall-mounted: origin = centre of the back face.")
def b_neon_sign_a(a):
    back = [(-0.31, 0.85), (0.31, 0.85), (0.31, 0.16), (0.67, 0.16), (0.0, -0.90), (-0.67, 0.16), (-0.31, 0.16)]
    p = a.part()
    p.prism(back, 0.0, 0.05, 'Charcoal', 'Y')
    a.add(p, bevel=0.012)
    q = a.part()
    q.prism([(x * 0.93, z * 0.93 - 0.002) for x, z in back], 0.05, 0.058, 'Navy', 'Y')
    loop = [(-0.22, 0.75), (0.22, 0.75), (0.22, 0.07), (0.50, 0.07), (0.0, -0.74), (-0.50, 0.07), (-0.22, 0.07)]
    yt = 0.085
    q.tube([(x, yt, z) for x, z in loop], 0.024, 'NeonMagenta', seg=6, closed=True)
    for z in (0.46, 0.20, -0.06):
        q.tube([(-0.12, yt, z + 0.11), (0.0, yt, z), (0.12, yt, z + 0.11)], 0.02, 'NeonYellow', seg=5)
    q.tube([(-0.20, yt, -0.20), (0.0, yt, -0.46), (0.20, yt, -0.20)], 0.02, 'NeonYellow', seg=5)
    for x, z in ((-0.24, 0.80), (0.24, 0.80), (0.0, -0.80), (-0.58, 0.12), (0.58, 0.12)):
        q.box((0.035, 0.03, 0.035), (x, 0.06, z), 'Steel')                  # tube supports / bolts
    q.box((0.16, 0.07, 0.10), (0.0, 0.035, 0.91), 'SteelDark')              # junction box
    a.add(q)


@prop("neon_sign_b", 79, "signage", "static", 16.0, "metal", anchor="wall",
      emissive="P_NeonYellow, P_NeonCyan, P_NeonOrange",
      notes="Round neon star sign, diameter 1.7 m. Wall-mounted: origin = centre of the back face.")
def b_neon_sign_b(a):
    p = a.part()
    p.prism(ngon(12, 0.85, 0, 0, 15), 0.0, 0.05, 'Charcoal', 'Y')
    a.add(p, bevel=0.012, bevel_angle=40)
    q = a.part()
    q.prism(ngon(12, 0.78, 0, 0, 15), 0.05, 0.058, 'Navy', 'Y')
    yt = 0.085
    star = []
    for i in range(10):
        an = math.radians(90 + 36 * i)
        rr = 0.62 if i % 2 == 0 else 0.26
        star.append((math.cos(an) * rr, yt, math.sin(an) * rr))
    q.tube(star, 0.024, 'NeonYellow', seg=6, closed=True)
    q.tube(arc((0, yt, 0), 0.13, 0, 324, 9), 0.018, 'NeonCyan', seg=5, closed=True)
    for i in range(12):
        an = math.radians(15 + 30 * i)
        q.sph(0.035, (math.cos(an) * 0.715, 0.075, math.sin(an) * 0.715), 'NeonOrange', seg=4, rings=2)
    q.box((0.16, 0.07, 0.10), (0.0, 0.035, 0.87), 'SteelDark')
    a.add(q)


@prop("neon_sign_c", 80, "signage", "static", 18.0, "metal", anchor="wall",
      emissive="P_NeonCyan, P_NeonBlue, P_NeonOrange, P_NeonYellow",
      notes="Neon 'sun over waves' panel, 2.1 x 1.0 m. Wall-mounted: origin = centre of the back face.")
def b_neon_sign_c(a):
    p = a.part()
    p.box((2.10, 0.05, 1.00), (0, 0.025, 0), 'Charcoal')
    a.add(p, bevel=0.012)
    q = a.part()
    q.box((1.98, 0.008, 0.88), (0, 0.054, 0), 'Navy')
    yt = 0.085
    for k, (z0, key, ph) in enumerate(((-0.10, 'NeonCyan', 0.0), (-0.24, 'NeonBlue', 1.3), (-0.36, 'NeonCyan', 2.6))):
        pts = []
        for i in range(13):
            x = -0.86 + 1.72 * i / 12
            pts.append((x, yt, z0 + 0.055 * math.sin(2 * math.pi * x / 0.86 + ph)))
        q.tube(pts, 0.021, key, seg=5)
    cx, cz = 0.38, 0.02
    q.tube(arc((cx, yt, cz), 0.20, 0, 180, 6), 0.022, 'NeonOrange', seg=5)
    for an in (20, 55, 90, 125, 160):
        ca, sa = math.cos(math.radians(an)), math.sin(math.radians(an))
        q.tube([(cx + ca * 0.27, yt, cz + sa * 0.27), (cx + ca * 0.37, yt, cz + sa * 0.37)], 0.018, 'NeonYellow', seg=4)
    for i in range(3):                                                      # three abstract "letter" bars
        q.box((0.20 - i * 0.03, 0.02, 0.05), (-0.55 + i * 0.02, 0.07, 0.30 - i * 0.10), 'NeonMagenta')
    for x in (-0.98, 0.98):
        for z in (-0.42, 0.42):
            q.box((0.04, 0.02, 0.04), (x, 0.056, z), 'Steel')
    q.box((0.16, 0.07, 0.10), (0.0, 0.035, 0.52), 'SteelDark')
    a.add(q)


def _wave_band(q, x0, x1, zb, zt, amp, wl, ph, y0, y1, key, n=10):
    top = []
    for i in range(n + 1):
        x = x1 + (x0 - x1) * i / n
        top.append((x, zt + amp * math.sin(2 * math.pi * x / wl + ph)))
    q.prism([(x0, zb), (x1, zb)] + top, y0, y1, key, 'Y')


@prop("billboard", 83, "signage", "static", 2600.0, "metal", collision="trimesh",
      notes="Roadside billboard: face 7.0 x 3.2 m (bottom edge 4.3 m up) on two steel posts, total 7.6 m high, "
            "catwalk, four up-lights (M_LampGlow), ladder. Face = material M_Billboard_A with 0-1 UVs; original "
            "'sun over the bay' artwork in geometry in front of it. Front = +Y.")
def b_billboard(a):
    FW, FH, FZ = 7.0, 3.2, 5.9
    p = a.part()
    for x in (-2.2, 2.2):
        p.box((0.34, 0.26, 7.45), (x, -0.26, 3.725), 'SteelDark')
        p.box((0.95, 0.95, 0.30), (x, -0.26, 0.15), 'Concrete')
    a.add(p, bevel=0.03)
    f = a.part()
    for z in (FZ - 1.45, FZ, FZ + 1.45):
        f.box((FW, 0.10, 0.14), (0, -0.08, z), 'SteelDark')
    for x in (-3.3, -1.1, 1.1, 3.3):
        f.box((0.10, 0.08, FH), (x, -0.07, FZ), 'SteelDark')
    f.box((FW, 0.05, FH), (0, 0.0, FZ), 'M_Billboard_A')
    for s in (1, -1):                                                       # frame
        f.box((FW + 0.16, 0.09, 0.10), (0, 0.0, FZ + s * (FH / 2 + 0.03)), 'White')
        f.box((0.10, 0.09, FH + 0.16), (s * (FW / 2 + 0.03), 0.0, FZ), 'White')
    # catwalk + ladder
    f.box((FW + 0.2, 0.62, 0.05), (0, 0.33, FZ - FH / 2 - 0.16), 'Steel')
    for x in (-3.0, -1.0, 1.0, 3.0):
        f.box((0.06, 0.70, 0.06), (x, 0.24, FZ - FH / 2 - 0.215), 'SteelDark')
    for x in (2.48, 2.86):
        f.box((0.04, 0.04, 4.1), (x, -0.42, 2.25), 'Steel')
    for i in range(8):
        f.box((0.38, 0.03, 0.03), (2.67, -0.42, 0.50 + i * 0.48), 'Steel')
    a.add(f)
    # artwork (thin layers in front of the face, y from 0.025)
    q = a.part()
    zb = FZ - FH / 2 + 0.02
    x0, x1 = -FW / 2 + 0.02, FW / 2 - 0.02
    q.prism(ngon(14, 0.95, -1.55, FZ + 0.25), 0.025, 0.034, 'Mustard', 'Y')
    q.prism(ngon(14, 1.22, -1.55, FZ + 0.25), 0.025, 0.029, 'Peach', 'Y')
    _wave_band(q, x0, x1, zb, FZ - 0.55, 0.11, 2.3, 0.0, 0.025, 0.039, 'Teal')
    _wave_band(q, x0, x1, zb, FZ - 1.02, 0.09, 1.9, 1.4, 0.025, 0.044, 'Navy')
    q.box((2.6, 0.012, 0.50), (1.75, 0.031, FZ + 0.95), 'Coral')            # headline blocks (no text)
    q.box((1.9, 0.012, 0.20), (2.10, 0.031, FZ + 0.45), 'Navy')
    q.box((1.3, 0.012, 0.20), (2.40, 0.031, FZ + 0.15), 'Navy')
    a.add(q)
    # up-lights
    g = a.part()
    for x in (-2.6, -0.87, 0.87, 2.6):
        g.strut((x, 0.60, FZ - FH / 2 - 0.14), (x, 1.22, FZ - FH / 2 - 0.02), 0.04, 'SteelDark')
        g.box((0.34, 0.16, 0.10), (x, 1.24, FZ - FH / 2 + 0.03), 'Charcoal', rot=(math.radians(-35), 0, 0))
        g.box((0.28, 0.02, 0.07), (x, 1.176, FZ - FH / 2 + 0.076), 'M_LampGlow', rot=(math.radians(-35), 0, 0))
    a.add(g)
    a.post.append(lambda mesh: S.fit_uv(mesh, "M_Billboard_A"))


@prop("billboard_roof", 81, "signage", "static", 900.0, "metal", anchor="roof", collision="trimesh",
      notes="Rooftop billboard: face 6.0 x 2.4 m on a raked steel frame (footprint 6.2 x 2.2 m, 3.5 m high), "
            "three down-lights (M_LampGlow) and a cyan neon strip. Face = material M_Billboard_B with 0-1 UVs. "
            "Front = +Y; put the origin on the roof surface near the parapet.")
def b_billboard_roof(a):
    FW, FH, FZ = 6.0, 2.4, 2.15
    p = a.part()
    for x in (-2.7, -0.9, 0.9, 2.7):
        p.box((0.10, 0.10, FZ + FH / 2), (x, -0.08, (FZ + FH / 2) / 2), 'SteelDark')
        p.strut((x, -0.10, FZ + FH / 2 - 0.25), (x, -1.80, 0.08), 0.08, 'SteelDark')
        p.strut((x, -0.10, 1.05), (x, -1.10, 1.05), 0.06, 'SteelDark')
        p.box((0.16, 2.10, 0.10), (x, -0.86, 0.05), 'SteelDark')
    for z in (FZ - 0.95, FZ + 0.95):
        p.box((FW, 0.08, 0.10), (0, -0.07, z), 'SteelDark')
    p.strut((-2.7, -0.95, 1.05), (2.7, -0.95, 1.05), 0.06, 'SteelDark')
    for xa, xb in ((-2.7, -0.9), (0.9, 2.7)):                               # cross bracing in the rake plane
        p.strut((xa, -1.75, 0.12), (xb, -0.14, FZ + FH / 2 - 0.3), 0.04, 'Steel')
        p.strut((xb, -1.75, 0.12), (xa, -0.14, FZ + FH / 2 - 0.3), 0.04, 'Steel')
    p.box((FW, 0.05, FH), (0, 0.0, FZ), 'M_Billboard_B')
    for s in (1, -1):
        p.box((FW + 0.14, 0.08, 0.09), (0, 0.0, FZ + s * (FH / 2 + 0.025)), 'White')
        p.box((0.09, 0.08, FH + 0.14), (s * (FW / 2 + 0.025), 0.0, FZ), 'White')
    a.add(p)
    q = a.part()
    q.prism(ngon(16, 0.78, 1.70, FZ + 0.12), 0.025, 0.036, 'Coral', 'Y')
    q.prism(ngon(16, 0.46, 1.70, FZ + 0.12), 0.036, 0.042, 'Mustard', 'Y')
    for i, w in enumerate((2.9, 2.2, 1.5)):
        q.box((w, 0.012, 0.26), (0.55 - w / 2 - 0.05, 0.031, FZ + 0.62 - i * 0.42), 'Cream')
    q.box((FW - 0.04, 0.012, 0.22), (0, 0.031, FZ - FH / 2 + 0.16), 'Teal')
    q.tube([(-FW / 2, 0.07, FZ + FH / 2 + 0.11), (FW / 2, 0.07, FZ + FH / 2 + 0.11)], 0.03, 'NeonCyan', seg=5)
    for x in (-2.0, 0.0, 2.0):
        q.strut((x, -0.02, FZ + FH / 2 + 0.06), (x, 0.62, FZ + FH / 2 + 0.26), 0.04, 'SteelDark')
        q.box((0.30, 0.16, 0.09), (x, 0.66, FZ + FH / 2 + 0.25), 'Charcoal', rot=(math.radians(28), 0, 0))
        q.box((0.24, 0.10, 0.02), (x, 0.635, FZ + FH / 2 + 0.202), 'M_LampGlow', rot=(math.radians(28), 0, 0))
    a.add(q)
    a.post.append(lambda mesh: S.fit_uv(mesh, "M_Billboard_B"))
