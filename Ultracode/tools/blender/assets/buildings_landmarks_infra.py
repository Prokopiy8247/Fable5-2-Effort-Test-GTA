"""Infrastructure landmarks of Halcyon Bay (landmark artist B): airport_hangar, airport_tower, lighthouse, tram_stop,
radio_mast and the marina pier kit (pier_straight, pier_end, pier_ramp).

Entry / QA: buildings_landmarks.py (LM.run, LM.write_manifest); helpers: landmark_kit.py (LK) on building_kit.py (K).
Every builder takes the slot index (LM.SLOT[name]) and returns the asset root.

    LM.run(["airport_hangar"])                       # rebuild + audit + measure + previews (lm_<id>*.png)
    LM.run(INFRA, preview=False, export=True)        # GLBs -> gta/generated/models/buildings/<id>.glb

Conventions (as the rest of the landmark set): Blender front = +Y (Godot -Z), origin = footprint centre on the
ground, interior floor at LK.FLOOR (6 cm), walls 0.3 m thick. Pier pieces: origin at DECK TOP level (z 0 = walking
level = world PIER_DECK_Y 1.15), the +Y end points to the quay (land), piles reach down to -6 m.
"""
import math
from mathutils import Vector

import gta_bl as G
import building_kit as K
import landmark_kit as LK

PI = math.pi
FL = LK.FLOOR
T = LK.T
INFRA = ["airport_hangar", "airport_tower", "lighthouse", "tram_stop", "radio_mast", "pier_straight", "pier_end", "pier_ramp"]


# ------------------------------------------------------------------------------------------------
# small helpers
# ------------------------------------------------------------------------------------------------
def _ngon(cx, cy, r, n, phase=0.0):
    return [(cx + r * math.cos(phase + 2 * PI * i / n), cy + r * math.sin(phase + 2 * PI * i / n)) for i in range(n)]


def _bar(b, p0, p1, w, mat, part="body", seg=4):
    """Square (seg 4) or round bar between two points, open ends (they always end inside something)."""
    b.tube(p0, p1, w * 0.7071, None, seg, mat, part, "none", PI / 4)


def _hpoly(b, pts, z, mat, part="body", down=False):
    return b.poly_dir([(p[0], p[1], z) for p in pts], (0, 0, -1 if down else 1), mat, part)


def _arc(x0, x1, z, rise, seg):
    """Top polyline of K.Builder.barrel_roof (same parametrisation)."""
    c = (x0 + x1) / 2.0
    half = (x1 - x0) / 2.0
    return [(c + half * math.cos(PI * (1.0 - i / float(seg))), z + rise * math.sin(PI * (1.0 - i / float(seg)))) for i in range(seg + 1)]


def _arc_z(pts, x):
    for (xa, za), (xb, zb) in zip(pts[:-1], pts[1:]):
        if xa - 1e-6 <= x <= xb + 1e-6:
            t = (x - xa) / (xb - xa) if xb - xa > 1e-9 else 0.0
            return za + (zb - za) * t
    return pts[0][1]


def _ribs(face, v0, v1, holes=(), pitch=1.2, w=0.12, depth=0.07, mat="wall", u0=0.6, u1=None, part="detail"):
    """Vertical corrugation ribs on a K.Face, split around holes [(u0, u1, v0, v1)]."""
    u1 = face.w - 0.6 if u1 is None else u1
    n = max(1, int(round((u1 - u0) / pitch)))
    for i in range(n + 1):
        u = u0 + i * (u1 - u0) / n
        segs = [(v0, v1)]
        for (ha, hc, hv0, hv1) in holes:
            if ha - w < u < hc + w:
                new = []
                for (s0, s1) in segs:
                    if s1 <= hv0 or s0 >= hv1:
                        new.append((s0, s1))
                        continue
                    if s0 < hv0:
                        new.append((s0, hv0))
                    if s1 > hv1:
                        new.append((hv1, s1))
                segs = new
        for (s0, s1) in segs:
            if s1 - s0 > 0.25:
                face.box(u - w / 2, u + w / 2, s0, s1, 0.0, depth, mat, part, "k")


def _hole(face, a, c, v0, v1, m=0.22):
    u0, u1 = LK.face_span(face, a, c)
    return (u0 - m, u1 + m, v0 - m, v1 + m)


def _bench(b, x, y, z, yaw, w=2.4, part="body"):
    """Slatted public bench (seat faces local +Y)."""
    f = LK.Fr(b, x, y, z, yaw, part)
    for sx in (-w / 2 + 0.25, w / 2 - 0.25):
        f.box(sx - 0.04, sx + 0.04, -0.22, 0.22, 0.0, 0.42, "Charcoal", "-z")
        f.box(sx - 0.04, sx + 0.04, -0.26, -0.18, 0.42, 0.9, "Charcoal", "-z")
    for k in range(3):
        ya = -0.22 + k * 0.155
        f.box(-w / 2, w / 2, ya, ya + 0.13, 0.42, 0.47, "Wood")
    for k in range(2):
        za = 0.58 + k * 0.17
        f.box(-w / 2, w / 2, -0.26, -0.22, za, za + 0.12, "Wood")
    return f


def _life_ring(b, x, y, z, yaw, part="detail"):
    """Life buoy on a small white post board (ring in the local XZ plane, facing +Y)."""
    f = LK.Fr(b, x, y, z, yaw, part)
    f.box(-0.05, 0.05, -0.05, 0.05, 0.0, 1.45, "White", "-z")
    f.box(-0.36, 0.36, -0.06, -0.02, 0.62, 1.42, "White")
    c = Vector(f.P(0.0, 0.03, 1.02))
    n = 10
    ux = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    uz = Vector((0.0, 0.0, 1.0))
    for i in range(n):
        a0, a1 = 2 * PI * i / n, 2 * PI * (i + 1) / n
        p0 = c + (ux * math.cos(a0) + uz * math.sin(a0)) * 0.27
        p1 = c + (ux * math.cos(a1) + uz * math.sin(a1)) * 0.27
        b.tube(p0, p1, 0.065, None, 6, "Coral" if i % 2 == 0 else "White", part, "none")


# ------------------------------------------------------------------------------------------------
# airport_hangar
# ------------------------------------------------------------------------------------------------
def _leaf(b, xa, xb, yb, num=None):
    """Sliding hangar door leaf parked in front of a corner pier (outer face looks +Y)."""
    b.box(xa, xb, yb, yb + 0.14, 0.0, 9.0, "door", "body")
    f = b.face((xb, yb + 0.14), (xa, yb + 0.14))          # u = xb - x
    w = xb - xa
    f.box(0.0, w, 0.0, 0.32, 0.0, 0.05, "SteelDark", "detail", "k")
    f.box(0.0, w, 8.68, 9.0, 0.0, 0.05, "SteelDark", "detail", "k")
    f.box(0.12, w - 0.12, 6.0, 7.2, 0.0, 0.04, "SteelDark", "detail", "k")
    f.pane(0.22, w - 0.22, 6.1, 7.1, 0.045, 2, 1)
    for i in range(1, 3):
        u = w * i / 3.0
        f.box(u - 0.05, u + 0.05, 0.32, 6.0, 0.0, 0.05, "door", "detail", "k")
        f.box(u - 0.05, u + 0.05, 7.2, 8.68, 0.0, 0.05, "door", "detail", "k")
    if num:
        f.text(num, w / 2.0, 3.6, 0.36, "White", 0.055)


def _tug(b, x, y, yaw):
    """Aircraft tow tractor (mustard, low, four fat tyres); front = local +Y."""
    f = LK.Fr(b, x, y, FL, yaw, "interior")
    f.box(-0.72, 0.72, -1.35, 1.35, 0.24, 0.72, "Mustard", "-z")
    f.box(-0.68, 0.68, 0.45, 1.35, 0.72, 1.02, "Mustard")
    f.box(-0.5, 0.5, 1.35, 1.37, 0.78, 0.96, "Charcoal", "-y")
    f.box(-0.8, 0.8, 1.35, 1.55, 0.26, 0.5, "Black")
    f.box(-0.8, 0.8, -1.5, -1.35, 0.26, 0.5, "Black")
    f.box(-0.08, 0.08, -1.85, -1.5, 0.33, 0.43, "SteelDark")
    f.box(-0.36, 0.36, -0.9, -0.3, 0.72, 0.98, "Charcoal", "-z")
    f.box(-0.36, 0.36, -1.02, -0.9, 0.72, 1.55, "Charcoal", "-z")
    f.tube((0.0, 0.35, 0.95), (0.0, 0.05, 1.35), 0.035, "Charcoal", 4)
    f.box(-0.2, 0.2, -0.02, 0.1, 1.33, 1.38, "Black")
    f.box(-0.72, 0.72, -1.36, -1.3, 0.5, 0.62, "HazardYellow", "-z +z")
    f.box(-0.09, 0.09, 1.0, 1.18, 1.02, 1.12, "SafetyOrange", "-z")
    for sx in (-0.82, 0.82):
        for sy in (-0.85, 0.85):
            LK.tyre(f, (sx - 0.12, sy, 0.3), (sx + 0.12, sy, 0.3), 0.3)


def _stand(b, x, y, yaw, ph=2.4):
    """Rolling maintenance platform with stairs (stairs come up from local +Y)."""
    f = LK.Fr(b, x, y, FL, yaw, "interior")
    f.box(-0.6, 0.6, -0.6, 0.6, ph - 0.08, ph, "HazardYellow")
    for sx in (-0.55, 0.55):
        for sy in (-0.55, 0.55):
            f.box(sx - 0.04, sx + 0.04, sy - 0.04, sy + 0.04, 0.12, ph - 0.08, "HazardYellow", "-z +z")
            f.box(sx - 0.06, sx + 0.06, sy - 0.06, sy + 0.06, 0.0, 0.12, "Black", "-z")
    n = 7
    run = 0.3
    for k in range(n):
        ya = 0.6 + (n - 1 - k) * run
        z = ph * (k + 1) / (n + 1)
        f.box(-0.45, 0.45, ya, ya + run, z - 0.05, z, "SteelDark")
    for sx in (-0.5, 0.5):
        f.tube((sx, 0.6 + n * run, 0.0), (sx, 0.6, ph), 0.035, "HazardYellow", 4)
        f.tube((sx, 0.6 + n * run, 0.95), (sx, 0.6, ph + 0.95), 0.025, "HazardYellow", 4)
        f.tube((sx, 0.6 + n * run, 0.0), (sx, 0.6 + n * run, 0.95), 0.025, "HazardYellow", 4)
    for (a, c) in (((-0.58, -0.58), (0.58, -0.58)), ((-0.58, -0.58), (-0.58, 0.58)), ((0.58, -0.58), (0.58, 0.58))):
        f.tube((a[0], a[1], ph + 1.0), (c[0], c[1], ph + 1.0), 0.025, "HazardYellow", 4)
        f.tube((a[0], a[1], ph + 0.5), (c[0], c[1], ph + 0.5), 0.02, "HazardYellow", 4)
    for (px, py) in ((-0.58, -0.58), (0.58, -0.58), (-0.58, 0.58), (0.58, 0.58)):
        f.tube((px, py, ph), (px, py, ph + 1.0), 0.025, "HazardYellow", 4)


def _wall_prop(b, xw, yc, zc, L=1.45, part="interior"):
    """Spare three-blade propeller mounted on a wall at x = xw (blades in the YZ plane, facing +X)."""
    c = Vector((xw, yc, zc))
    for k in range(3):
        a = PI / 2 + k * 2 * PI / 3
        d = Vector((0.0, math.cos(a), math.sin(a)))
        p = Vector((0.0, -math.sin(a), math.cos(a)))
        root = [c + d * 0.16 + p * 0.1, c + d * L * 0.82 + p * 0.1, c + d * L * 0.82 - p * 0.08, c + d * 0.16 - p * 0.09]
        tip = [c + d * L * 0.82 + p * 0.1, c + d * L + p * 0.05, c + d * L - p * 0.05, c + d * L * 0.82 - p * 0.08]
        b.extrude(root, (0.05, 0.0, 0.0), "Charcoal", part)
        b.extrude(tip, (0.05, 0.0, 0.0), "Mustard", part)
    b.tube((xw, yc, zc), (xw + 0.24, yc, zc), 0.2, 0.1, 8, "Steel", part, "top")


def airport_hangar(slot):
    """Hangar One: 30 x 28.4 m steel shed under a segmented barrel roof with standing ribs and roof lights; open
    24.8 x 8.6 m front (sliding leaves parked in front of the corner piers, track beam above), corrugated side
    walls with clerestory glazing, personnel doors; walk-in maintenance interior (ops cabin, racks, benches, tug,
    work stand, wall propeller, hanging lamps on the roof ties)."""
    b = LK.LB("airport_hangar", slot, dict(wall="White", wall2="Cream", base="Navy", trim="Navy", roof="Steel",
                                           door="Teal", metal="SteelDark", accent="Teal", sign="Navy", neon="NeonCyan",
                                           concrete="Concrete"))
    x0, x1, y0, y1 = -14.85, 14.85, -14.4, 14.0
    H, RISE, TH, SEG = 10.0, 4.2, 0.25, 12
    OX, OH = 12.3, 8.6
    top = _arc(x0, x1, H, RISE, SEG)
    zE = _arc_z(top, x0 + T) - TH                      # roof underside right above the inner wall faces
    DOOR_R = (8.6, 10.4)                               # personnel door (world y) in the right wall
    DOOR_B = (10.4, 12.2)                              # back door (world x)
    CL = (6.9, 8.5)                                    # clerestory sill / head
    side_w = [(-12.0, -8.0), (-5.0, -1.0), (2.0, 6.0)]
    back_w = [(-11.0, -7.0), (-2.0, 2.0)]
    rm = LK.Room(b, x0, x1, y0, y1, H, H)
    rm.wall("front", [LK.gap(-OX, OX, FL, OH)])
    rm.wall("right", [LK.door(DOOR_R[0], DOOR_R[1], 2.5)] + [LK.win(a, c, CL[0], CL[1], nx=2) for a, c in side_w],
            h=H - TH, iv=(FL, zE))
    rm.wall("left", [LK.win(a, c, CL[0], CL[1], nx=2) for a, c in side_w + [(9.0, 12.0)]], h=H - TH, iv=(FL, zE))
    rm.wall("back", [LK.door(DOOR_B[0], DOOR_B[1], 2.5)] + [LK.win(a, c, CL[0], CL[1], nx=2) for a, c in back_w])
    rm.floor("Concrete")
    F, R, Bk, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")

    # --- roof: barrel + inner gable fills + standing ribs + roof lights ----------------------------------
    b.barrel_roof(x0, x1, y0, y1, H, RISE, seg=SEG, axis="y", over=0.45, th=TH, mat="roof", end="wall")
    inner = [(x, z - TH) for x, z in top if x0 + T + 1e-3 < x < x1 - T - 1e-3]
    for yy, dy in ((y1 - T, -1.0), (y0 + T, 1.0)):
        pts = [(x0 + T, yy, H), (x1 - T, yy, H), (x1 - T, yy, zE)] + [(x, yy, z) for x, z in reversed(inner)] + [(x0 + T, yy, zE)]
        b.poly_dir(pts, (0, dy, 0), "wall2")
    ys = [y0 + 0.6 + k * (y1 - y0 - 1.2) / 7.0 for k in range(8)]
    for y in ys:
        for i in range(SEG):
            b.seam((top[i][0], y, top[i][1]), (top[i + 1][0], y, top[i + 1][1]), w=0.16, h=0.09, mat="SteelDark",
                   part="detail", ends=False)
    for k in (1, 3, 5):
        ya, yb = ys[k] + 0.5, ys[k + 1] - 0.5
        for i in (3, SEG - 4):
            (xa, za), (xb, zb) = top[i], top[i + 1]
            nx, nz = -(zb - za), (xb - xa)
            ln = math.hypot(nx, nz)
            nx, nz = nx / ln, nz / ln
            for (e, g, m) in ((0.03, 0.12, "SteelDark"), (0.06, 0.0, "M_Window")):
                pa = (xa + (xb - xa) * 0.12 - g * (xb - xa) / ln, za + (zb - za) * 0.12 - g * (zb - za) / ln)
                pc = (xa + (xb - xa) * 0.88 + g * (xb - xa) / ln, za + (zb - za) * 0.88 + g * (zb - za) / ln)
                q = [(pa[0] + nx * e, ya - g, pa[1] + nz * e), (pc[0] + nx * e, ya - g, pc[1] + nz * e),
                     (pc[0] + nx * e, yb + g, pc[1] + nz * e), (pa[0] + nx * e, yb + g, pa[1] + nz * e)]
                b.poly_dir(q, (nx, 0.0, nz), m, "detail" if m != "M_Window" else "body")

    # --- facades ------------------------------------------------------------------------------------
    holes_r = [_hole(R, DOOR_R[0], DOOR_R[1], 0.0, 2.5)] + [_hole(R, a, c, CL[0], CL[1]) for a, c in side_w]
    holes_l = [_hole(L, a, c, CL[0], CL[1]) for a, c in side_w + [(9.0, 12.0)]]
    holes_b = [_hole(Bk, DOOR_B[0], DOOR_B[1], 0.0, 2.5)] + [_hole(Bk, a, c, CL[0], CL[1]) for a, c in back_w]
    for f, holes in ((R, holes_r), (L, holes_l), (Bk, holes_b)):
        _ribs(f, 1.2, 9.0, holes)
        f.box(-0.1, f.w + 0.1, 9.0, 9.3, 0.0, 0.1, "accent", "detail", "k")
    dr = LK.face_span(R, *DOOR_R)
    db = LK.face_span(Bk, *DOOR_B)
    R.dado([(0.0, dr[0] - 0.16), (dr[1] + 0.16, R.w)], h=1.2, proud=0.08)
    Bk.dado([(0.0, db[0] - 0.16), (db[1] + 0.16, Bk.w)], h=1.2, proud=0.08)
    L.dado(h=1.2, proud=0.08)
    for f, (u0, u1) in ((R, dr), (Bk, db)):
        f.canopy(u0 - 0.4, u1 + 0.4, 2.75, 0.9, mat="Navy")
        f.wall_light((u0 + u1) / 2.0, 3.25)
        f.text("1", u1 + 0.75, 1.9, 0.09, "Navy", 0.02)
    for f in (R, L):
        f.downpipe(0.3, 0.0, 9.7, mat="SteelDark", part="detail")
        f.downpipe(f.w - 0.3, 0.0, 9.7, mat="SteelDark", part="detail")
    L.text("HALCYON AIRFIELD", L.w / 2.0, 5.2, 0.16, "Navy", 0.08)
    # front: parked door leaves, track beam, gable lettering, entry ramp
    for xa, xb, yb, num in ((x0, x0 + 2.62, y1 + 0.42, "1"), (x0 + 0.08, x0 + 2.7, y1 + 0.2, None),
                            (x1 - 2.62, x1, y1 + 0.42, "1"), (x1 - 2.7, x1 - 0.08, y1 + 0.2, None)):
        _leaf(b, xa, xb, yb, num)
    b.box(x0, x1, y1, y1 + 0.75, 9.0, 9.45, "SteelDark", "body")
    for xb in (x0 + 0.3, -7.0, 0.0, 7.0, x1 - 0.3):
        b.box(xb - 0.12, xb + 0.12, y1, y1 + 0.75, 9.45, 9.75, "SteelDark", "detail", "-z")
    F.text("HANGAR ONE", F.w / 2.0, 11.75, 0.3, "Navy", 0.02)
    F.text("HALCYON AIRFIELD", F.w / 2.0, 10.4, 0.1, "Teal", 0.02)
    b.poly(((-OX, y1, FL), (OX, y1, FL), (OX, y1 + 0.9, 0.0), (-OX, y1 + 0.9, 0.0)), "Concrete")
    for sx in (-1, 1):
        LK.bollard(b, sx * 13.4, y1 + 1.0, 0.95, 0.12)
    b.entrance = (0.0, y1)

    # --- interior ------------------------------------------------------------------------------------
    z = FL + 0.004
    LK.hrect(b, -0.1, 0.1, -6.0, y1 - T, z, "HazardYellow")
    LK.hrect(b, -1.8, 1.8, -6.4, -6.0, z, "HazardYellow")
    LK.hrect(b, x0 + T + 0.1, x1 - T - 0.1, -10.25, -10.1, z, "HazardYellow")
    for sx in (-1, 1):
        LK.hrect(b, sx * 11.5 - 0.06, sx * 11.5 + 0.06, -10.1, y1 - T, z, "White")
    for i in range(7):                                                    # hatched apron in front of the ops cabin
        xa = 2.4 + i * 0.85
        LK.hgraphic(b, [(xa, -10.6), (xa + 0.35, -10.6), (xa + 0.75, -10.25), (xa + 0.4, -10.25)], z + 0.002, "HazardYellow")
    # roof structure: arch trusses + tie rods + hanging lamps
    lim = x1 - T - 0.08
    for y in ys[1:-1]:
        chain = [(-lim, _arc_z(top, -lim) - TH - 0.14)] + [(x, zz - TH - 0.14) for x, zz in top if abs(x) < lim] + \
                [(lim, _arc_z(top, lim) - TH - 0.14)]
        for (xa, za), (xb, zb) in zip(chain[:-1], chain[1:]):
            _bar(b, (xa, y, za), (xb, y, zb), 0.2, "SteelDark", "interior")
        _bar(b, (-lim, y, H + 0.35), (lim, y, H + 0.35), 0.09, "SteelDark", "interior")
        for xs in (-7.5, 7.5):
            _bar(b, (xs, y, H + 0.35), (xs, y, _arc_z(top, xs) - TH - 0.2), 0.07, "SteelDark", "interior")
    for y in (ys[1], ys[3], ys[5]):
        for x in (-8.0, 0.0, 8.0):
            _bar(b, (x, y, H + 0.35), (x, y, H - 0.5), 0.04, "Charcoal", "interior")
            b.tube((x, y, H - 0.5), (x, y, H - 0.85), 0.12, 0.46, 8, "Charcoal", "interior", "none")
            _hpoly(b, _ngon(x, y, 0.4, 8), H - 0.84, "LampWarm", "interior", down=True)
    # back wall: racks, bench, tool chests, ops cabin, drums
    G1 = ("CarBlue", "Mustard", "Steel", "WarmGrey", "SafetyOrange", "White", "OliveDrab")
    LK.shelf(b, -12.6, -13.8, 0.0, 3.2, 0.6, 2.6, 4, frame="SteelDark", goods=G1, seed=21)
    LK.shelf(b, -9.2, -13.8, 0.0, 3.2, 0.6, 2.6, 4, frame="SteelDark", goods=G1, seed=22)
    LK.workbench(b, -5.5, -13.7, 0.0, 2.8, 0.8)
    LK.tool_chest(b, -3.0, -13.82, 0.0, 1.2, 0.55, 1.05, "FireRed")
    LK.tool_chest(b, -1.55, -13.82, 0.0, 1.0, 0.55, 1.3, "CarBlue")
    cx0, cx1, cy0, cy1 = 2.0, 8.4, y0 + T, -10.8
    b.box(cx0, cx1, cy0, cy1, FL, FL + 2.8, "Cream", "interior", "-z -y")
    b.box(cx0 - 0.1, cx1 + 0.1, cy0, cy1 + 0.1, FL + 2.8, FL + 2.95, "Charcoal", "interior", "-y")
    cf = b.face((cx1, cy1), (cx0, cy1), FL)                      # u = cx1 - x
    cf.box(0.0, cx1 - cx0, 0.0, 0.25, 0.0, 0.03, "Navy", "interior", "k")
    cf.box(0.42, 1.58, 0.25, 2.2, 0.0, 0.03, "Navy", "interior", "k")
    cf.rect(0.5, 1.5, 0.25, 2.12, "Teal", 0.032, "interior")
    cf.box(2.0, 6.0, 0.95, 2.2, 0.0, 0.03, "Navy", "interior", "k")
    cf.pane(2.08, 5.92, 1.03, 2.12, 0.032, 3, 1)
    cf.text("OPS", 1.0, 2.5, 0.07, "Navy", 0.012, "interior")
    LK.crate(b, 3.2, -12.6, 0.8, FL + 2.95)
    LK.crate(b, 4.3, -12.4, 0.6, FL + 2.95, "OliveDrab", 0.3)
    for (bx, by, m) in ((13.9, -13.6, "CarRed"), (13.9, -12.9, "Mustard"), (13.2, -13.6, "CarRed"), (13.6, -12.2, "CarBlue")):
        LK.barrel(b, bx, by, m)
    # left wall: lockers, bench, tyre rack, propeller, crates
    LK.lockers(b, x0 + T + 0.25, -9.4, -PI / 2, 5, mat="Navy")
    LK.workbench(b, x0 + T + 0.4, -5.6, -PI / 2, 2.8, 0.8)
    LK.tyre_rack(b, x0 + T + 0.35, -1.4, -PI / 2, 2.6, 2.1, 2)
    _wall_prop(b, x0 + T + 0.01, 4.6, 4.8)
    LK.crate(b, x0 + T + 0.6, 10.6, 1.0)
    LK.crate(b, x0 + T + 1.7, 10.4, 0.9, mat="OliveDrab", yaw=0.2)
    LK.crate(b, x0 + T + 0.6, 10.6, 0.7, FL + 1.0, yaw=0.4)
    # right wall: bench, work stand, hose reel, extinguishers
    LK.workbench(b, x1 - T - 0.4, -7.5, PI / 2, 2.8, 0.8)
    LK.tyre_stack(b, x1 - T - 0.5, -4.6, 3, 0.36, 0.25)
    LK.tyre_stack(b, x1 - T - 0.5, -3.8, 2, 0.36, 0.25)
    _stand(b, 10.8, 1.2, PI / 2)
    ri = rm.inner["right"]
    hu = LK.face_u(ri, 6.2)
    ri.box(hu - 0.4, hu + 0.4, 1.0, 1.8, 0.0, 0.12, "FireRed", "interior", "k")
    ri.box(hu - 0.3, hu + 0.3, 1.1, 1.7, 0.12, 0.3, "Black", "interior", "k")
    for yy in (7.9, 11.1):
        b.cyl(x1 - T - 0.14, yy, FL, FL + 0.62, 0.1, "FireRed", "interior", 8)
    b.cyl(DOOR_B[0] - 0.5, y0 + T + 0.14, FL, FL + 0.62, 0.1, "FireRed", "interior", 8)
    # floor kit: wheel chocks, tug
    for sx in (-1.7, 1.7):
        f = LK.Fr(b, sx, -2.3, FL, 0.0, "interior")
        f.poly(((-0.18, -0.12, 0.0), (0.18, -0.12, 0.0), (0.18, -0.12, 0.16), (-0.18, -0.12, 0.16))[::-1], "HazardYellow")
        f.box(-0.18, 0.18, -0.12, 0.12, 0.0, 0.04, "HazardYellow", "-z")
        b.poly_dir([f.P(-0.18, -0.12, 0.16), f.P(0.18, -0.12, 0.16), f.P(0.18, 0.12, 0.04), f.P(-0.18, 0.12, 0.04)],
                   (0, 0.6, 1.0), "HazardYellow", "interior")
    _tug(b, -8.6, 7.6, 0.35)

    b.marker("Spawn_Plane", 0.0, -1.5, FL, 0.0)
    b.floors = 1
    return b.finish(tags=["airport", "hangar", "aviation"], landmark="airport_hangar",
                    extra={"sign": "HANGAR ONE", "opening": {"width": round(2 * (x1 - 2.7), 2), "height": OH, "center_x": 0.0},
                           "clear_height_inside": round(H + 0.35 - 0.05, 2)})


# ------------------------------------------------------------------------------------------------
# airport_tower
# ------------------------------------------------------------------------------------------------
def airport_tower(slot):
    """Halcyon Airfield control tower: white square shaft with a vertical window stack, octagonal glazed cab
    (outward-raked glass) on a gallery with railings, roof radar + antenna + red beacon; low terminal wing in
    front (walk-in lobby: check-in desk, departures board, seats, vending), windsock and generator in the yard."""
    b = LK.LB("airport_tower", slot, dict(wall="White", wall2="Cream", base="Navy", trim="Navy", roof="RoofGrey",
                                          sign="Navy", neon="NeonCyan", accent="Teal", door="Teal", metal="Charcoal"))
    # --- terminal wing --------------------------------------------------------------------------------
    wx0, wx1, wy0, wy1 = -5.92, 5.92, 0.6, 5.8
    WH, WC = 4.2, 3.3
    rm = LK.Room(b, wx0, wx1, wy0, wy1, WH, WC)
    rm.wall("front", [LK.shopwin(-5.4, -1.4, 0.5, 2.8, nx=2), LK.door(-1.0, 1.0, 2.5), LK.shopwin(1.4, 5.4, 0.5, 2.8, nx=2)])
    rm.wall("left", [LK.win(1.5, 3.1, 1.0, 2.5)])
    rm.wall("right", [LK.win(1.5, 3.1, 1.0, 2.5)])
    rm.wall("back")
    rm.tiles(("White", "Cream"), 1.0)
    rm.ceiling("White")
    rm.lights(3, 1)
    F, R, Bk, L = rm.face("front"), rm.face("right"), rm.face("back"), rm.face("left")       # F: u = 6 - x
    du = LK.face_span(F, -1.0, 1.0)
    F.dado([(0.0, du[0] - 0.14), (du[1] + 0.14, F.w)], h=0.5, proud=0.07)
    for f in (R, Bk, L):
        f.dado(h=0.5, proud=0.07)
    b.belt(rm.pts, 2.95, h=0.12, proud=0.05, mat="accent", edges=[0, 1, 3])
    F.sign(0.6, F.w - 0.6, 3.0, 3.95, "HALCYON AIRFIELD", board="sign", color="NeonCyan", pad=0.16)
    F.canopy(du[0] - 0.4, du[1] + 0.4, 2.72, 1.3, mat="Navy", rods=True)
    b.flat_roof(rm.pts, WH, parapet=0.45)
    b.ac_unit(-3.6, 3.0, WH)
    b.ac_unit(-1.2, 3.4, WH, turn=True)
    b.entrance = (0.0, wy1)
    # --- tower shaft ------------------------------------------------------------------------------------
    sx0, sx1, sy0, sy1 = 0.3, 4.7, -4.25, 0.6
    cx, cy = (sx0 + sx1) / 2.0, (sy0 + sy1) / 2.0
    ZS = 14.0
    sh = b.mass(sx0, sx1, sy0, sy1)
    W1 = K.win(0.9, 1.3, sill=0.7, frame="trim", sill_bar="trim")
    lv = [(2.45, [W1], "wall")] * 4
    for f in (sh.left, sh.right, sh.back):
        f.stack(0.0, [(WH, [K.door(1.0, 2.2, frame="trim")] if f is sh.left else None, "wall")] + lv)    # top = ZS
    sh.front.stack(WH + 0.5, [(1.95, [W1], "wall")] + [(2.45, [W1], "wall")] * 3)                       # top = ZS
    for k in range(5):
        b.belt(sh.pts, WH + k * 2.45 - 0.09, h=0.18, proud=0.05, mat="accent", edges=[0, 1, 3] if k == 0 else None)
    for (px, py) in ((sx0, sy0), (sx1, sy0), (sx1, sy1), (sx0, sy1)):
        b.box(px - 0.12, px + 0.12, py - 0.12, py + 0.12, WH + 0.45 if py == sy1 else 0.0, ZS, "Navy", "detail", "-z +z")
    sh.left.wall_light(sh.left.w / 2.0, 2.65)
    # --- cab --------------------------------------------------------------------------------------------
    ph8 = PI / 8
    b.tube((cx, cy, ZS - 0.9), (cx, cy, ZS), 3.0, 3.6, 8, "Navy", "body", "bottom", ph8)
    b.cyl(cx, cy, ZS, ZS + 0.35, 3.6, "Charcoal", "body", 8, caps="both", phase=ph8)
    z0, z1, z2 = ZS + 0.35, ZS + 1.25, ZS + 3.55
    b.cyl(cx, cy, z0, z1, 2.95, "Navy", "body", 8, caps="none", phase=ph8)
    lo = _ngon(cx, cy, 2.95, 8, ph8)
    hi = _ngon(cx, cy, 3.3, 8, ph8)
    for i in range(8):
        j = (i + 1) % 8
        a = (lo[i][0], lo[i][1], z1)
        c = (lo[j][0], lo[j][1], z1)
        d = (hi[j][0], hi[j][1], z2)
        e = (hi[i][0], hi[i][1], z2)
        mx, my = (lo[i][0] + lo[j][0]) / 2.0 - cx, (lo[i][1] + lo[j][1]) / 2.0 - cy
        b.poly_dir([a, c, d, e], (mx, my, -0.12), "M_Window")
        _bar(b, (lo[i][0], lo[i][1], z1), (hi[i][0], hi[i][1], z2), 0.12, "White", "body")
    b.cyl(cx, cy, z1 - 0.06, z1 + 0.06, 3.0, "White", "detail", 8, caps="none", phase=ph8)
    b.cyl(cx, cy, z2, z2 + 0.25, 3.32, "White", "body", 8, caps="bottom", phase=ph8)
    b.cyl(cx, cy, z2 + 0.25, z2 + 0.55, 3.6, "Charcoal", "body", 8, caps="both", phase=ph8)
    _hpoly(b, _ngon(cx, cy, 2.94, 8, ph8), z1 - 0.02, "Charcoal")          # cab floor seen through nothing - keeps it closed
    # gallery railing
    rail = _ngon(cx, cy, 3.48, 8, ph8)
    for i in range(8):
        j = (i + 1) % 8
        for zz, w in ((ZS + 1.4, 0.07), (ZS + 0.9, 0.05)):
            _bar(b, (rail[i][0], rail[i][1], zz), (rail[j][0], rail[j][1], zz), w, "White", "detail")
        for t in (0.0, 0.5):
            px = rail[i][0] + (rail[j][0] - rail[i][0]) * t
            py = rail[i][1] + (rail[j][1] - rail[i][1]) * t
            _bar(b, (px, py, ZS + 0.35), (px, py, ZS + 1.4), 0.06, "White", "detail")
    # roof kit: radar, antenna mast, beacon
    zr = z2 + 0.55
    b.cyl(cx - 1.0, cy + 0.6, zr, zr + 0.9, 0.12, "SteelDark", "detail", 8)
    b.box(cx - 2.0, cx, cy + 0.42, cy + 0.78, zr + 0.9, zr + 1.25, "White", "detail")
    b.box(cx - 1.12, cx - 0.88, cy + 0.48, cy + 0.72, zr + 0.88, zr + 0.95, "SteelDark", "detail", "+z")
    b.antenna(cx + 1.2, cy - 0.8, zr, 3.4, "Steel", LK.beacon())
    b.cyl(cx, cy, zr, zr + 0.4, 0.35, "SteelDark", "detail", 8)
    b.box(cx - 0.15, cx + 0.15, cy - 0.15, cy + 0.15, zr + 0.4, zr + 0.72, LK.beacon(), "detail", "-z")
    b.dish(cx + 1.6, cy + 1.3, zr, 0.45, aim=(0.4, 0.8, 0.6))
    # --- yard: windsock + generator -----------------------------------------------------------------------
    wx, wy = -4.3, -2.4
    b.box(wx - 0.4, wx + 0.4, wy - 0.4, wy + 0.4, 0.0, 0.25, "Concrete", "body", "-z")
    b.cyl(wx, wy, 0.25, 6.2, 0.07, "White", "detail", 6)
    for k in range(3):
        b.cyl(wx, wy, 0.25 + k * 2.0, 0.25 + k * 2.0 + 1.0, 0.075, "SafetyOrange", "detail", 6, caps="none")
    piv = Vector((wx, wy - 0.15, 6.0))
    dvec = Vector((0.15, -1.0, -0.22)).normalized()
    b.tube((wx, wy, 6.0), tuple(piv), 0.03, None, 4, "Steel", "detail", "none")
    ring = 0.4
    for k in range(5):
        a = piv + dvec * (k * 0.52)
        c = piv + dvec * ((k + 1) * 0.52)
        b.tube(a, c, ring - 0.045 * k, ring - 0.045 * (k + 1), 8, "SafetyOrange" if k % 2 == 0 else "White", "detail", "none")
    b.tube(tuple(piv - dvec * 0.02), tuple(piv + dvec * 0.06), ring + 0.03, None, 8, "Steel", "detail", "none")
    gx, gy = -1.9, -4.3
    b.box(gx - 1.0, gx + 1.0, gy - 0.6, gy + 0.6, 0.0, 0.15, "Concrete", "body", "-z")
    b.box(gx - 0.9, gx + 0.9, gy - 0.5, gy + 0.5, 0.15, 1.45, "Mint", "body", "-z")
    b.box(gx - 0.95, gx + 0.95, gy - 0.55, gy + 0.55, 1.45, 1.55, "Charcoal", "body")
    gf = b.face((gx + 0.9, gy + 0.5), (gx - 0.9, gy + 0.5), 0.15)
    for k in range(5):
        gf.box(0.2, 1.0, 0.35 + k * 0.17, 0.43 + k * 0.17, 0.0, 0.03, "SteelDark", "detail", "k")
    gf.box(1.2, 1.6, 0.5, 1.0, 0.0, 0.02, "Charcoal", "detail", "k")
    b.cyl(gx + 0.6, gy - 0.2, 1.55, 2.2, 0.07, "SteelDark", "detail", 6)

    # --- wing interior ------------------------------------------------------------------------------------
    LK.counter(b, -3.2, 2.1, 0.0, 3.2, 0.7, 1.05, body="Navy", top="Cream", stripe="Teal")
    LK.register(b, -2.4, 2.05, 0.0, FL + 1.05)
    LK.register(b, -4.1, 2.05, 0.0, FL + 1.05)
    LK.office_chair(b, -2.4, 1.3, 0.0)
    bi = rm.inner["back"]                                            # u = (wx1 - T) - x
    ub = lambda x: (wx1 - T) - x
    bi.box(ub(-1.6), ub(-4.8), 1.75, 2.95, 0.0, 0.05, "Charcoal", "interior", "k")
    bi.text("DEPARTURES", (ub(-1.6) + ub(-4.8)) / 2.0, 2.78, 0.026, "Mustard", 0.052, "interior")
    for k in range(4):
        v = 2.5 - k * 0.2
        bi.rect(ub(-1.75), ub(-2.7), v, v + 0.1, "White", 0.052, "interior")
        bi.rect(ub(-2.8), ub(-4.1), v, v + 0.1, "Sky", 0.052, "interior")
        bi.rect(ub(-4.2), ub(-4.65), v, v + 0.1, ("NeonGreen" if k != 2 else "Coral"), 0.052, "interior")
    bi.box(ub(2.95), ub(1.85), FL, FL + 2.2, 0.0, 0.03, "Navy", "interior", "k")
    bi.rect(ub(2.88), ub(1.92), FL + 0.02, FL + 2.13, "Teal", 0.032, "interior")
    bi.text("STAFF", ub(2.4), 2.55, 0.045, "Navy", 0.02, "interior")
    LK.seat_row(b, 3.5, 2.35, 0.0, 3, "Teal")
    LK.seat_row(b, 3.5, 4.55, PI, 3, "Teal")
    LK.vending(b, wx0 + T + 0.42, 4.5, -PI / 2, "CarBlue", seed=13)
    LK.plant(b, 5.2, 1.35, 1.3)
    LK.plant(b, -5.25, 5.2, 1.1)
    LK.rug(b, 0.0, 4.75, 2.2, 1.2, "Navy", "Teal")
    li = rm.inner["left"]
    lu = LK.face_u(li, 2.3)
    li.box(lu - 0.55, lu + 0.55, 3.0, 3.25, 0.0, 0.03, "Teal", "interior", "k")
    b.floors = 6
    return b.finish(tags=["airport", "tower", "aviation"], landmark="airport_tower",
                    extra={"sign": "HALCYON AIRFIELD", "cab_floor": round(ZS + 0.35, 2)})


# ------------------------------------------------------------------------------------------------
# lighthouse
# ------------------------------------------------------------------------------------------------
def lighthouse(slot):
    """Halcyon Light: octagonal stone plinth with steps and a pedimented door porch, 16-sided tapered tower in
    red / white bands with small windows, corbelled gallery with railing, open lantern (glass + glazing bars)
    around a glowing lens (M_LampGlow), red cone roof with ventilator ball and lightning rod (~26 m)."""
    b = LK.LB("lighthouse", slot, dict(wall="White", base="Concrete", trim="Charcoal", roof="FireRed", metal="Charcoal",
                                       accent="FireRed"))
    P0 = 0.9
    oc = _ngon(0.0, 0.0, 3.36, 8, PI / 8)                            # apothem 3.1
    b.extrude([(x, y, -0.8) for x, y in oc], (0, 0, P0 + 0.8), "Concrete", "body")
    b.ring(oc, [(0.06, P0 - 0.25), (0.06, P0), (0.0, P0)], "ConcreteDark", closed=False)
    for i in range(3):
        b.box(-0.95, 0.95, 3.1, 3.1 + 0.32 * (3 - i), -0.3, (i + 1) * 0.3, "ConcreteDark", "body", "-z")
    b.solid(-3.1, 3.1, -3.1, 3.1, -0.8, P0)
    # tower
    ZT = 20.0
    r0, r1 = 2.9, 2.05
    rz = lambda z: r0 + (r1 - r0) * (z - P0) / (ZT - P0)
    bands = 7
    for k in range(bands):
        za = P0 + (ZT - P0) * k / bands
        zb = P0 + (ZT - P0) * (k + 1) / bands
        b.cyl(0, 0, za, zb, rz(za), "White" if k % 2 == 0 else "FireRed", "body", 16, r2=rz(zb), caps="none")
    b.solid(-2.35, 2.35, -2.35, 2.35, P0, ZT)
    # porch + door
    b.box(-0.85, 0.85, 2.2, 3.0, P0, P0 + 2.75, "White", "body", "-z")
    b.prism([(-1.0, P0 + 2.75), (1.0, P0 + 2.75), (0.0, P0 + 3.35)], 2.1, 3.12, "y", "FireRed")
    pf = b.face((0.85, 3.0), (-0.85, 3.0), P0)
    pf.box(0.3, 1.4, 0.0, 2.2, 0.0, 0.04, "Charcoal", "body", "k")
    pf.rect(0.38, 1.32, 0.0, 2.12, "WoodDark", 0.045)
    pf.box(1.12, 1.2, 1.0, 1.12, 0.045, 0.09, "Brass", "detail", "k")
    pf.wall_light(1.56, 1.95)
    pf.text("1887", 0.85, 2.58, 0.035, "Charcoal", 0.012)
    # windows (frames on the round wall)
    for (z, ang) in ((5.2, 0.0), (8.6, PI * 0.75), (11.4, PI * 0.25 - PI), (14.4, PI * 1.0), (17.2, -PI * 0.3)):
        rr = rz(z + 0.5)
        f = LK.Fr(b, 0.0, 0.0, z, ang, "body")
        f.box(-0.34, 0.34, rr - 0.12, rr + 0.08, 0.0, 1.05, "Charcoal", "")
        q = [f.P(-0.24, rr + 0.082, 0.1), f.P(0.24, rr + 0.082, 0.1), f.P(0.24, rr + 0.082, 0.95), f.P(-0.24, rr + 0.082, 0.95)]
        b.poly_dir(q, (-math.sin(ang), math.cos(ang), 0.0), "M_Window")
    # gallery
    b.cyl(0, 0, ZT - 0.6, ZT, rz(ZT - 0.6), "Charcoal", "body", 16, r2=2.7, caps="none")
    ZG = ZT + 0.25
    b.cyl(0, 0, ZT, ZG, 2.78, "Charcoal", "body", 16, caps="both")
    b.solid(-2.75, 2.75, -2.75, 2.75, ZT, ZG)
    rp = _ngon(0, 0, 2.62, 16)
    for i in range(16):
        j = (i + 1) % 16
        _bar(b, (rp[i][0], rp[i][1], ZG), (rp[i][0], rp[i][1], ZG + 1.05), 0.06, "Charcoal", "detail")
        for zz, w in ((ZG + 1.05, 0.07), (ZG + 0.55, 0.045)):
            _bar(b, (rp[i][0], rp[i][1], zz), (rp[j][0], rp[j][1], zz), w, "Charcoal", "detail")
    # lantern
    RL = 1.5
    ZL0, ZL1, ZL2 = ZG + 0.95, ZG + 3.05, ZG + 3.2
    b.cyl(0, 0, ZG, ZL0, RL + 0.05, "White", "body", 12, caps="none")
    b.cyl(0, 0, ZL0, ZL0 + 0.08, RL + 0.1, "Charcoal", "body", 12, caps="top")
    b.box(-0.35, 0.35, RL - 0.05 + 0.0, RL + 0.07, ZG + 0.05, ZG + 0.85, "Charcoal", "detail", "-y")
    glass = LK.smat("M_Glass", "Sky")
    lt = _ngon(0, 0, RL, 12)
    for i in range(12):
        j = (i + 1) % 12
        _bar(b, (lt[i][0], lt[i][1], ZL0 + 0.08), (lt[i][0], lt[i][1], ZL1), 0.07, "Charcoal", "body")
        mx, my = (lt[i][0] + lt[j][0]) / 2.0, (lt[i][1] + lt[j][1]) / 2.0
        b.poly_dir([(lt[i][0] * 0.99, lt[i][1] * 0.99, ZL0 + 0.08), (lt[j][0] * 0.99, lt[j][1] * 0.99, ZL0 + 0.08),
                    (lt[j][0] * 0.99, lt[j][1] * 0.99, ZL1), (lt[i][0] * 0.99, lt[i][1] * 0.99, ZL1)], (mx, my, 0.0), glass, "detail")
    for zz in (ZL0 + 1.05,):
        for i in range(12):
            j = (i + 1) % 12
            _bar(b, (lt[i][0], lt[i][1], zz), (lt[j][0], lt[j][1], zz), 0.05, "Charcoal", "body")
    b.cyl(0, 0, ZL1, ZL2, RL + 0.12, "Charcoal", "body", 12, caps="none")
    # lens: glowing drum with brass prism rings on a pedestal
    lamp = LK.glow()
    b.cyl(0, 0, ZL0 + 0.08, ZL0 + 0.55, 0.35, "Brass", "body", 8)
    b.cyl(0, 0, ZL0 + 0.55, ZL1 - 0.35, 0.68, lamp, "body", 10, caps="both")
    for k in range(4):
        zz = ZL0 + 0.7 + k * 0.32
        b.cyl(0, 0, zz, zz + 0.05, 0.71, "Brass", "detail", 10, caps="none")
    b.cyl(0, 0, ZL1 - 0.35, ZL1 - 0.2, 0.45, "Brass", "body", 8)
    # roof
    b.cyl(0, 0, ZL2, ZL2 + 1.3, 1.9, "FireRed", "body", 12, r2=0.24, caps="bottom")
    b.cyl(0, 0, ZL2 - 0.04, ZL2 + 0.06, 1.95, "Charcoal", "detail", 12, caps="none")
    zb = ZL2 + 1.3
    b.tube((0, 0, zb - 0.05), (0, 0, zb + 0.28), 0.12, 0.34, 8, "Charcoal", "body", "none")
    b.tube((0, 0, zb + 0.28), (0, 0, zb + 0.62), 0.34, 0.05, 8, "Charcoal", "body", "none")
    b.cyl(0, 0, zb + 0.6, zb + 1.5, 0.025, "Charcoal", "detail", 4)
    b.box(-0.03, 0.03, -0.35, 0.25, zb + 1.18, zb + 1.22, "Charcoal", "detail")
    b.prism([(-0.12, zb + 1.12), (0.12, zb + 1.12), (0.0, zb + 1.3)], 0.25, 0.32, "y", "Charcoal", "detail")
    b.solid(-1.6, 1.6, -1.6, 1.6, ZG, zb + 0.6)

    b.marker("Gallery", 0.0, 2.25, ZG, 0.0)
    b.marker("Door", 0.0, 4.1, 0.0, PI)
    b.entrance = (0.0, 3.1)
    b.floors = 0
    return b.finish(tags=["coast", "landmark", "waterfront"], landmark="lighthouse", collision="box",
                    extra={"lamp_height": round((ZL0 + ZL1) / 2.0, 2), "lamp_material": "M_LampGlow"})


# ------------------------------------------------------------------------------------------------
# tram_stop
# ------------------------------------------------------------------------------------------------
def tram_stop(slot):
    """Bay Tram stop: raised platform (ramped ends, yellow tactile edge on the +Y / track side), cantilever shelter
    with teal sloped canopy, glass back wall and wind screen, slatted bench, hanging stop sign, totem with the tram
    logo, ticket machine, route map, advertising light box, bin."""
    b = LK.LB("tram_stop", slot, dict(wall="Teal", base="ConcreteDark", trim="White", roof="Teal", metal="Charcoal",
                                      sign="Navy", neon="NeonCyan"))
    PZ = 0.3
    px0, px1, y0, y1 = -4.8, 4.8, -2.0, 2.0
    b.box(px0, px1, y0, y1, -0.4, PZ, "Concrete", "body", "-z -x +x")
    b.ramp(6.0, px1, 0.0, PZ, y0, y1, "x", top="Concrete", mat="ConcreteDark", ease=0.25)
    b.ramp(-6.0, px0, 0.0, PZ, y0, y1, "x", top="Concrete", mat="ConcreteDark", ease=0.25)
    z = PZ + 0.004
    LK.hrect(b, px0, px1, 1.42, 1.82, z, "HazardYellow")
    for k in range(24):
        xa = px0 + 0.2 + k * 0.4
        LK.hrect(b, xa, xa + 0.08, 1.5, 1.74, z + 0.004, "Mustard")
    LK.hrect(b, px0, px1, 1.88, 1.96, z, "White")
    b.box(px0, px1, y1, y1 + 0.02, 0.02, PZ - 0.04, "HazardYellow", "detail", "-y -z")
    # shelter frames
    SX = 3.0
    zf = lambda y: 2.78 + (y + 1.85) * (0.2 / 3.15)              # canopy underside
    for sx in (-SX, SX):
        b.box(sx - 0.08, sx + 0.08, -1.66, -1.5, PZ, zf(-1.58), "Charcoal", "body", "-z")
        _bar(b, (sx, -1.58, zf(-1.58) - 0.12), (sx, 1.15, zf(1.15) - 0.06), 0.12, "Charcoal")
        _bar(b, (sx, -1.58, 1.95), (sx, -0.2, zf(-0.2) - 0.08), 0.09, "Charcoal")
        b.box(sx - 0.14, sx + 0.14, -1.72, -1.44, PZ, PZ + 0.08, "Charcoal", "body", "-z")
    # canopy
    prof = [(-1.85, 2.78), (1.3, 2.98), (1.3, 3.14), (-1.85, 2.94)]
    b.prism(prof, -3.6, 3.6, "x", "Teal")
    fa = b.face((3.62, 1.3), (-3.62, 1.3), 0.0)
    fa.box(0.0, 7.24, 2.88, 3.2, 0.0, 0.06, "White", "detail", "k")
    fa.text("BAY TRAM", 3.62, 3.04, 0.045, "Navy", 0.065)
    for xa, xb in ((-3.4, -0.2), (0.2, 3.4)):
        b.poly_dir([(xa, -0.6, zf(-0.6) - 0.01), (xb, -0.6, zf(-0.6) - 0.01), (xb, 0.4, zf(0.4) - 0.01), (xa, 0.4, zf(0.4) - 0.01)],
                   (0, 0, -1), "LampWarm", "detail")
    # back glass wall + route map, side wind screen, ad box
    gz0, gz1 = PZ + 0.18, 2.42
    b.box(-2.92, 1.8, -1.6, -1.56, gz0, gz1, "M_Window")
    for xa, xb in ((-SX + 0.08, 1.8),):
        for zz in (gz0 - 0.08, gz1):
            b.box(xa, xb, -1.63, -1.53, zz, zz + 0.08, "Charcoal", "body")
    b.box(-0.6, -0.52, -1.63, -1.53, gz0, gz1, "Charcoal", "body", "-z +z")
    b.box(1.8, 2.92, -1.64, -1.52, gz0 - 0.08, gz1 + 0.08, "White", "body")
    mf = b.face((2.92, -1.52), (1.8, -1.52), 0.0)
    mf.rect(0.08, 1.04, gz0 + 0.95, gz1 - 0.05, "Cream", 0.01, "detail")
    mf.text("ROUTE", 0.56, gz1 - 0.2, 0.025, "Navy", 0.012)
    for k in range(5):
        mf.rect(0.18, 0.94, gz0 + 1.05 + k * 0.17, gz0 + 1.09 + k * 0.17, ("Teal", "Coral", "Teal", "Mustard", "Teal")[k], 0.012, "detail")
    mf.rect(0.08, 1.04, gz0 + 0.1, gz0 + 0.85, "Navy", 0.01, "detail")
    mf.text("T", 0.56, gz0 + 0.48, 0.07, "NeonCyan", 0.012)
    b.box(-SX - 0.03, -SX + 0.03, -1.5, -0.25, gz0, gz1, "M_Window")
    for zz in (gz0 - 0.08, gz1):
        b.box(-SX - 0.05, -SX + 0.05, -1.5, -0.2, zz, zz + 0.08, "Charcoal", "body")
    b.box(-SX - 0.05, -SX + 0.05, -0.28, -0.2, gz0, gz1, "Charcoal", "body", "-z +z")
    b.box(SX - 0.07, SX + 0.07, -1.45, -0.25, PZ + 0.1, 2.3, "Charcoal", "body", "-z")
    for sgn in (-1, 1):
        sf = b.face((SX + sgn * 0.072, -1.45 if sgn > 0 else -0.25), (SX + sgn * 0.072, -0.25 if sgn > 0 else -1.45), 0.0)
        sf.rect(0.06, 1.14, PZ + 0.45, 2.2, "Coral", 0.0, "detail")
        sf.rect(0.12, 1.08, PZ + 1.35, 2.12, "Cream", 0.004, "detail")
        sf.rect(0.2, 1.0, PZ + 0.55, 1.2, "Teal", 0.004, "detail")
        sf.text("SUN", 0.6, PZ + 1.73, 0.06, "Coral", 0.008)
    # bench, hanging sign, totem, ticket machine, bin
    _bench(b, -0.6, -1.15, PZ, 0.0, 2.6)
    hs = 0.6
    for sx in (-0.75, 0.75):
        _bar(b, (sx, hs, zf(hs) - 0.01), (sx, hs, 2.6), 0.03, "Charcoal", "detail")
    b.box(-0.95, 0.95, hs - 0.05, hs + 0.05, 2.25, 2.6, "Navy", "detail")
    for sgn in (1, -1):
        hf = b.face((0.95 * sgn, hs + 0.05 * sgn), (-0.95 * sgn, hs + 0.05 * sgn), 0.0)
        hf.text("TRAM STOP", 0.95, 2.425, 0.035, "NeonCyan", 0.01)
    tx, ty = 4.3, -1.25
    b.box(tx - 0.07, tx + 0.07, ty - 0.07, ty + 0.07, PZ, 2.7, "Charcoal", "body", "-z")
    b.box(tx - 0.42, tx + 0.42, ty - 0.1, ty + 0.1, 2.7, 3.55, "Navy", "detail")
    for sgn in (1, -1):
        tf = b.face((tx + 0.42 * sgn, ty + 0.1 * sgn), (tx - 0.42 * sgn, ty + 0.1 * sgn), 0.0)
        LK.fdisc(tf, 0.42, 3.15, 0.3, "White", 10, 0.008)
        tf.text("T", 0.42, 3.15, 0.07, "Teal", 0.016)
        tf.rect(0.06, 0.78, 2.76, 2.86, "NeonCyan", 0.008, "detail")
    b.box(tx - 0.3, tx + 0.3, ty - 0.1, ty + 0.1, 1.55, 2.0, "White", "detail")
    mx0 = -4.3
    b.box(mx0 - 0.3, mx0 + 0.3, -1.55, -1.1, PZ, PZ + 1.6, "Teal", "body", "-z")
    b.box(mx0 - 0.33, mx0 + 0.33, -1.58, -1.07, PZ + 1.6, PZ + 1.68, "Charcoal", "body")
    tm = b.face((mx0 + 0.3, -1.1), (mx0 - 0.3, -1.1), PZ)
    tm.rect(0.1, 0.5, 1.0, 1.42, LK.smat("M_ScreenGlow", "Sky"), 0.01, "detail")
    tm.box(0.12, 0.48, 0.6, 0.9, 0.0, 0.05, "Charcoal", "detail", "k")
    tm.box(0.2, 0.4, 0.3, 0.38, 0.0, 0.06, "Black", "detail", "k")
    tm.text("TICKETS", 0.3, 1.52, 0.012, "White", 0.012)
    b.cyl(4.2, 0.25, PZ, PZ + 0.9, 0.24, "Charcoal", "body", 8)
    b.cyl(4.2, 0.25, PZ + 0.9, PZ + 0.95, 0.26, "Teal", "body", 8)

    b.marker("Use_Bench", -0.6, -0.85, PZ, 0.0)
    b.marker("Board", 0.0, 1.3, PZ, 0.0)
    b.entrance = (0.0, y1)
    b.floors = 0
    return b.finish(tags=["transit", "tram", "street"], landmark="tram_stop",
                    extra={"serves": ["tram_stop_1", "tram_stop_2", "tram_stop_3"], "platform_height": PZ,
                           "platform_edge": "front"})


# ------------------------------------------------------------------------------------------------
# radio_mast
# ------------------------------------------------------------------------------------------------
def radio_mast(slot):
    """Signal Hill radio mast: red / white banded square lattice tower (tapering 2.6 -> 0.9 m) with X bracing,
    caged access ladder up the front face through a hatch into the railed top platform (Parachute_Spot), panel
    antennas, microwave dish, dipoles, red obstruction beacons; fenced concrete pad with an equipment cabinet."""
    b = LK.LB("radio_mast", slot, dict(wall="Cream", base="Concrete", trim="Charcoal", roof="RoofGrey", metal="SteelDark",
                                       door="Steel", sign="Mustard"))
    Z0, TOP, NS = 0.15, 26.0, 9
    W0, W1 = 1.3, 0.45
    hw = lambda z: W0 + (W1 - W0) * (min(z, TOP) - Z0) / (TOP - Z0)
    b.box(-3.0, 3.0, -3.0, 3.0, -0.6, Z0, "Concrete", "body", "-z")
    b.solid(-3.0, 3.0, -3.0, 3.0, -0.6, Z0)
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        b.box(sx * W0 - 0.3, sx * W0 + 0.3, sy * W0 - 0.3, sy * W0 + 0.3, Z0, Z0 + 0.35, "ConcreteDark", "body", "-z")
    zs = [Z0 + (TOP - Z0) * k / NS for k in range(NS + 1)]
    for k in range(NS):
        za, zb = zs[k], zs[k + 1]
        mat = "FireRed" if k % 2 == 0 else "White"
        ha, hb = hw(za), hw(zb)
        for sx, sy in corners:
            _bar(b, (sx * ha, sy * ha, za), (sx * hb, sy * hb, zb), 0.14, mat)
        for i in range(4):
            (ax, ay), (cx_, cy_) = corners[i], corners[(i + 1) % 4]
            _bar(b, (ax * hb, ay * hb, zb), (cx_ * hb, cy_ * hb, zb), 0.09, mat)
            _bar(b, (ax * ha, ay * ha, za), (cx_ * hb, cy_ * hb, zb), 0.06, mat)
            _bar(b, (cx_ * ha, cy_ * ha, za), (ax * hb, ay * hb, zb), 0.06, mat)
    for (z0, z1, h) in ((Z0, 9.0, 1.25), (9.0, 18.0, 0.95), (18.0, TOP - 0.12, 0.65)):
        b.solid(-h, h, -h, h, z0, z1)
    # top platform with ladder hatch + railings
    zp = TOP
    for (xa, xb, ya, yb) in ((-1.4, 1.4, -1.4, 0.45), (-1.4, -0.42, 0.45, 1.4), (0.42, 1.4, 0.45, 1.4), (-0.42, 0.42, 1.15, 1.4)):
        b.box(xa, xb, ya, yb, zp - 0.12, zp, "SteelDark", "body")
    b.solid(-1.4, 1.4, -1.4, 1.4, zp - 0.12, zp)
    pr = [(-1.36, -1.36), (1.36, -1.36), (1.36, 1.36), (-1.36, 1.36)]
    for i in range(4):
        (ax, ay), (cx_, cy_) = pr[i], pr[(i + 1) % 4]
        for t in (0.0, 0.5):
            px, py = ax + (cx_ - ax) * t, ay + (cy_ - ay) * t
            _bar(b, (px, py, zp), (px, py, zp + 1.1), 0.06, "HazardYellow", "detail")
        for zz, w in ((zp + 1.1, 0.06), (zp + 0.55, 0.045)):
            _bar(b, (ax, ay, zz), (cx_, cy_, zz), w, "HazardYellow", "detail")
        _bar(b, (ax, ay, zp + 0.06), (cx_, cy_, zp + 0.06), 0.1, "SteelDark", "detail")
    for sx in (-0.45, 0.45):
        _bar(b, (sx, 0.45, zp), (sx, 0.45, zp + 1.0), 0.05, "HazardYellow", "detail")
        _bar(b, (sx, 1.15, zp), (sx, 1.15, zp + 1.0), 0.05, "HazardYellow", "detail")
        _bar(b, (sx, 0.45, zp + 1.0), (sx, 1.15, zp + 1.0), 0.05, "HazardYellow", "detail")
    # caged ladder up the front face
    yl = lambda z: hw(z) + 0.2
    for sx in (-0.22, 0.22):
        _bar(b, (sx, yl(Z0), Z0), (sx, yl(TOP), TOP), 0.05, "Steel", "detail")
        _bar(b, (sx, yl(TOP), TOP), (sx, yl(TOP), TOP + 1.1), 0.05, "Steel", "detail")
        for zz in zs[1:-1]:
            _bar(b, (sx, hw(zz), zz), (sx, yl(zz), zz), 0.05, "Steel", "detail")
    zz = Z0 + 0.3
    while zz < TOP + 0.9:
        _bar(b, (-0.22, yl(zz), zz), (0.22, yl(zz), zz), 0.035, "Steel", "detail")
        zz += 0.4
    hoops = []
    zz = 2.6
    while zz < TOP - 0.3:
        y = yl(zz)
        hp = [(-0.36, y, zz), (-0.36, y + 0.68, zz), (0.36, y + 0.68, zz), (0.36, y, zz)]
        for a, c in zip(hp[:-1], hp[1:]):
            _bar(b, a, c, 0.04, "Steel", "detail")
        hoops.append(hp)
        zz += 1.3
    for a, c in zip(hoops[:-1], hoops[1:]):
        for idx in (1, 2):
            _bar(b, a[idx], c[idx], 0.03, "Steel", "detail")
    # top mast + antennas + beacons
    b.cyl(0, 0, zp, zp + 2.0, 0.11, "White", "detail", 8, caps="none")
    b.cyl(0, 0, zp + 2.0, zp + 4.2, 0.1, "FireRed", "detail", 8, caps="top")
    for ang in (PI / 6, 5 * PI / 6, 3 * PI / 2):
        f = LK.Fr(b, 0.0, 0.0, zp + 1.25, ang - PI / 2, "detail")
        f.box(-0.16, 0.16, 0.3, 0.42, 0.0, 1.5, "White")
        for zz in (0.3, 1.15):
            f.box(-0.03, 0.03, 0.08, 0.3, zz, zz + 0.08, "SteelDark", "-y")
    b.tube((0.1, 0.0, zp + 1.7), (0.4, 0.0, zp + 1.7), 0.06, None, 6, "SteelDark", "detail", "none")
    b.tube((0.4, 0.0, zp + 1.7), (0.66, 0.0, zp + 1.7), 0.48, 0.52, 12, "White", "detail", "both")
    b.tube((0.66, 0.0, zp + 1.7), (0.7, 0.0, zp + 1.7), 0.4, 0.4, 12, "WarmGrey", "detail", "top")
    for (dx, dy) in ((1, 0), (0, 1)):
        _bar(b, (-0.75 * dx, -0.75 * dy, zp + 3.4), (0.75 * dx, 0.75 * dy, zp + 3.4), 0.05, "Steel", "detail")
        for sg in (-1, 1):
            _bar(b, (sg * 0.72 * dx, sg * 0.72 * dy, zp + 3.0), (sg * 0.72 * dx, sg * 0.72 * dy, zp + 3.8), 0.03, "Steel", "detail")
    beacon = LK.beacon()
    b.box(-0.13, 0.13, -0.13, 0.13, zp + 4.2, zp + 4.5, beacon, "detail")
    b.cyl(0, 0, zp + 4.5, zp + 5.0, 0.02, "Steel", "detail", 4)
    for (sx, sy) in ((-1, -1), (1, 1)):
        h = hw(13.2)
        b.box(sx * h - 0.12 + sx * 0.12, sx * h + 0.12 + sx * 0.12, sy * h - 0.12, sy * h + 0.12, 13.1, 13.4, beacon, "detail")
    # equipment cabinet + cable tray
    b.box(1.65, 2.85, -2.85, -1.65, Z0, 2.35, "Cream", "body", "-z")
    b.box(1.55, 2.95, -2.95, -1.55, 2.35, 2.47, "Charcoal", "body")
    b.solid(1.55, 2.95, -2.95, -1.55, Z0, 2.47)
    cf = b.face((2.85, -1.65), (1.65, -1.65), Z0)
    cf.box(0.15, 1.05, 0.05, 2.0, 0.0, 0.03, "Steel", "detail", "k")
    cf.box(0.85, 0.92, 0.9, 1.15, 0.03, 0.07, "Charcoal", "detail", "k")
    cf.text("HV", 0.6, 1.7, 0.045, "FireRed", 0.035)
    sf = b.face((2.85, -2.85), (2.85, -1.65), Z0)
    sf.box(0.2, 1.0, 0.6, 1.4, 0.0, 0.12, "Steel", "detail", "k")
    LK.fdisc(sf, 0.6, 1.0, 0.28, "SteelDark", 8, 0.125)
    _bar(b, (2.2, -1.9, 2.25), (hw(2.25) + 0.05, -hw(2.25) - 0.05, 2.25), 0.12, "Steel", "detail")
    # fence with gate gap at the front
    FP = 2.88
    fence = [(-FP, -FP), (FP, -FP), (FP, FP), (0.85, FP), (-0.85, FP), (-FP, FP)]
    segs = [((-FP, -FP), (FP, -FP)), ((FP, -FP), (FP, FP)), ((FP, FP), (0.85, FP)), ((-0.85, FP), (-FP, FP)), ((-FP, FP), (-FP, -FP))]
    for (a, c) in segs:
        L_ = math.hypot(c[0] - a[0], c[1] - a[1])
        n = max(1, int(round(L_ / 1.45)))
        for i in range(n + 1):
            px, py = a[0] + (c[0] - a[0]) * i / n, a[1] + (c[1] - a[1]) * i / n
            _bar(b, (px, py, Z0), (px, py, Z0 + 1.9), 0.07, "SteelDark", "detail")
        for zz in (Z0 + 0.15, Z0 + 0.95, Z0 + 1.8):
            _bar(b, (a[0], a[1], zz), (c[0], c[1], zz), 0.04, "Steel", "detail")
        for i in range(n):
            pa = (a[0] + (c[0] - a[0]) * i / n, a[1] + (c[1] - a[1]) * i / n)
            pc = (a[0] + (c[0] - a[0]) * (i + 1) / n, a[1] + (c[1] - a[1]) * (i + 1) / n)
            _bar(b, (pa[0], pa[1], Z0 + 0.15), (pc[0], pc[1], Z0 + 1.8), 0.025, "Steel", "detail")
    wf = b.face((-1.3, FP + 0.03), (-2.1, FP + 0.03), Z0)
    wf.box(0.0, 0.8, 0.9, 1.5, 0.0, 0.03, "Mustard", "detail", "")
    wf.text("DANGER", 0.4, 1.32, 0.022, "Charcoal", 0.035)
    wf.text("HV", 0.4, 1.08, 0.04, "FireRed", 0.035)

    b.marker("Parachute_Spot", 0.8, -0.8, zp, PI)
    b.marker("Ladder_Bottom", 0.0, hw(Z0) + 0.95, Z0, PI)
    b.marker("Ladder_Top", -0.85, 0.2, zp, 0.0)
    b.entrance = (0.0, FP)
    b.floors = 0
    return b.finish(tags=["hill", "mast", "viewpoint"], landmark="radio_mast", collision="box",
                    extra={"platform_height": zp, "ladder": {"axis_x": 0.0, "front_face": True}})


# ------------------------------------------------------------------------------------------------
# pier kit
# ------------------------------------------------------------------------------------------------
PW = 2.0          # half width (world PIER_HALF_W)


def _deck(b, y0, y1, plank=0.3):
    """Flat plank deck (top at z 0) + fascia, kerbs, stringers between y0..y1."""
    n = max(1, int(round((y1 - y0) / plank)))
    for i in range(n):
        ya = y0 + i * (y1 - y0) / n
        yb = y0 + (i + 1) * (y1 - y0) / n
        LK.hrect(b, -PW, PW, ya, yb, 0.0, "Wood" if i % 2 == 0 else "TrunkLight", "body")
    b.box(-PW, PW, y0, y1, -0.32, 0.0, "WoodDark", "body", "+z")
    for sx in (-1, 1):
        b.box(sx * PW - (0.18 if sx > 0 else 0.0), sx * PW + (0.0 if sx > 0 else 0.18), y0, y1, 0.0, 0.14, "WoodDark", "body", "-z")
    for c in (-1.3, 0.0, 1.3):
        b.box(c - 0.1, c + 0.1, y0, y1, -0.6, -0.32, "WoodDark", "body", "+z")


def _bent(b, y, ztop=-0.6, piles=(-1.75, 1.75), bottom=-6.0):
    """Pile bent: cap beam, round piles to the sea bed, X bracing."""
    b.box(-PW, PW, y - 0.16, y + 0.16, ztop - 0.26, ztop, "WoodDark", "body")
    for px in piles:
        b.cyl(px, y, bottom, ztop - 0.26, 0.18, "Trunk", "body", 8, caps="none")
        b.cyl(px, y, ztop - 0.2, ztop + 0.0, 0.2, "Trunk", "body", 8, caps="none")
    a, c = piles[0], piles[-1]
    _bar(b, (a, y + 0.2, ztop - 0.45), (c, y + 0.2, ztop - 2.6), 0.12, "WoodDark")
    _bar(b, (c, y - 0.2, ztop - 0.45), (a, y - 0.2, ztop - 2.6), 0.12, "WoodDark")


def _cleat(b, x, y):
    b.box(x - 0.1, x + 0.1, y - 0.22, y + 0.22, 0.14, 0.2, "Charcoal", "detail", "-z")
    b.box(x - 0.05, x + 0.05, y - 0.06, y + 0.06, 0.2, 0.3, "Charcoal", "detail", "-z")
    b.box(x - 0.06, x + 0.06, y - 0.3, y + 0.3, 0.3, 0.35, "Charcoal", "detail")


def _bollard(b, x, y):
    b.cyl(x, y, 0.0, 0.5, 0.14, "Charcoal", "body", 8)
    b.cyl(x, y, 0.42, 0.52, 0.19, "Charcoal", "body", 8)


def _lamp(b, x, y, mat="LampWarm", h=3.4):
    b.cyl(x, y, 0.0, 0.2, 0.12, "Charcoal", "detail", 8)
    b.cyl(x, y, 0.2, h, 0.055, "Navy", "detail", 6, caps="none")
    b.box(x - 0.16, x + 0.16, y - 0.16, y + 0.16, h - 0.05, h, "Navy", "detail")
    b.box(x - 0.13, x + 0.13, y - 0.13, y + 0.13, h, h + 0.3, mat, "detail", "-z")
    b.tube((x, y, h + 0.3), (x, y, h + 0.5), 0.22, 0.02, 6, "Navy", "detail", "bottom")


def pier_straight(slot):
    """Marina pier, straight 4 x 12 m piece: plank deck on stringers and three pile bents (4 m spacing, so pieces
    tile seamlessly), kerbs, mooring cleats, one lamp post and a life buoy."""
    b = LK.LB("pier_straight", slot, dict(wall="Wood", base="WoodDark", trim="WoodDark", metal="Charcoal"))
    y0, y1 = -6.0, 6.0
    _deck(b, y0, y1)
    for y in (-4.0, 0.0, 4.0):
        _bent(b, y)
    for y in (-4.0, 4.0):
        for sx in (-1.88, 1.88):
            _cleat(b, sx, y)
    _lamp(b, -1.7, 0.0)
    _life_ring(b, 1.72, -1.6, 0.0, PI / 2)
    b.entrance = (0.0, y1)
    return b.finish(category="misc", tags=["pier", "marina", "waterfront"], landmark="",
                    extra={"deck_level": 0.0, "tile_length": 12.0, "width": 4.0, "connects": "+Y and -Y ends (Godot -Z / +Z)"})


def pier_end(slot):
    """Marina pier end, 4 x 6 m: deck, end railing with a gap for the swim ladder (down into the water), corner
    navigation light (green), bollards, bench looking out to sea, life buoy."""
    b = LK.LB("pier_end", slot, dict(wall="Wood", base="WoodDark", trim="WoodDark", metal="Charcoal"))
    y0, y1 = -3.0, 3.0
    _deck(b, y0, y1)
    for y in (1.0, -2.7):
        _bent(b, y)
    # railing: end (gap in the middle for the ladder) + short side returns
    ry = y0 + 0.1
    for (xa, xb) in ((-PW + 0.1, -0.45), (0.45, PW - 0.1)):
        for xp in (xa, xb):
            _bar(b, (xp, ry, 0.14), (xp, ry, 1.1), 0.08, "White", "detail")
        for zz in (1.1, 0.6):
            _bar(b, (xa, ry, zz), (xb, ry, zz), 0.06, "White", "detail")
    for sx in (-PW + 0.1, PW - 0.1):
        _bar(b, (sx, -1.2, 0.14), (sx, -1.2, 1.1), 0.08, "White", "detail")
        for zz in (1.1, 0.6):
            _bar(b, (sx, ry, zz), (sx, -1.2, zz), 0.06, "White", "detail")
    # swim ladder on the end face (x = 0), grab rails above the deck
    ly = y0 - 0.14
    for sx in (-0.24, 0.24):
        _bar(b, (sx, ly, -2.6), (sx, ly, 0.0), 0.05, "Steel", "detail")
        b.tube((sx, ly, 0.0), (sx, ly + 0.05, 0.9), 0.03, None, 6, "Steel", "detail", "none")
        b.tube((sx, ly + 0.05, 0.9), (sx, y0 + 0.35, 0.9), 0.03, None, 6, "Steel", "detail", "none")
        b.tube((sx, y0 + 0.35, 0.9), (sx, y0 + 0.35, 0.0), 0.03, None, 6, "Steel", "detail", "none")
        _bar(b, (sx, ly, -0.15), (sx, y0, -0.15), 0.05, "Steel", "detail")
    zz = -2.4
    while zz < -0.05:
        _bar(b, (-0.24, ly, zz), (0.24, ly, zz), 0.035, "Steel", "detail")
        zz += 0.3
    # nav light, bollards, bench, life ring
    _lamp(b, PW - 0.3, y0 + 0.35, "NeonGreen", 2.6)
    for sx in (-1.75, 1.75):
        _bollard(b, sx, 2.2)
    _bench(b, -0.9, -0.9, 0.0, PI, 1.8, "detail")
    _life_ring(b, -1.72, 0.9, 0.0, -PI / 2)
    b.marker("Ladder_Top", 0.0, y0 + 0.45, 0.0, 0.0)
    b.marker("Ladder_Bottom", 0.0, y0 - 0.6, -1.2, 0.0)
    b.entrance = (0.0, y1)
    return b.finish(category="misc", tags=["pier", "marina", "waterfront"], landmark="",
                    extra={"deck_level": 0.0, "tile_length": 6.0, "width": 4.0, "connects": "+Y end (Godot -Z)"})


def pier_ramp(slot):
    """Marina pier ramp, 4 x 8 m: sloped plank gangway from the quay (+Y end, +1.37 m) down to the pier deck
    (-Y end, z 0), anti-slip battens, steel handrails, sloped stringers, a pile bent and the quay abutment."""
    b = LK.LB("pier_ramp", slot, dict(wall="Wood", base="WoodDark", trim="WoodDark", metal="Charcoal"))
    y0, y1, RISE = -4.0, 4.0, 1.37
    zr = lambda y: RISE * (y - y0) / (y1 - y0)
    n = 27
    for i in range(n):
        ya = y0 + i * (y1 - y0) / n
        yb = y0 + (i + 1) * (y1 - y0) / n
        b.poly_dir([(-PW, ya, zr(ya)), (PW, ya, zr(ya)), (PW, yb, zr(yb)), (-PW, yb, zr(yb))], (0, -0.17, 1.0),
                   "Wood" if i % 2 == 0 else "TrunkLight")
    for sx in (-1, 1):
        b.poly_dir([(sx * PW, y0, -0.32), (sx * PW, y1, RISE - 0.32), (sx * PW, y1, RISE), (sx * PW, y0, 0.0)], (sx, 0, 0), "WoodDark")
    b.poly_dir([(-PW, y0, -0.32), (PW, y0, -0.32), (PW, y1, RISE - 0.32), (-PW, y1, RISE - 0.32)], (0, 0.17, -1.0), "WoodDark")
    b.poly_dir([(-PW, y0, -0.32), (PW, y0, -0.32), (PW, y0, 0.0), (-PW, y0, 0.0)], (0, -1, 0), "WoodDark")
    b.poly_dir([(-PW, y1, RISE - 0.32), (PW, y1, RISE - 0.32), (PW, y1, RISE), (-PW, y1, RISE)], (0, 1, 0), "WoodDark")
    yy = y0 + 0.35
    while yy < y1 - 0.2:
        b.box(-PW + 0.15, PW - 0.15, yy - 0.03, yy + 0.03, zr(yy) - 0.01, zr(yy) + 0.035, "WoodDark", "body", "-z")
        yy += 0.5
    for c in (-1.3, 0.0, 1.3):
        _bar(b, (c, y0, -0.42), (c, y1, RISE - 0.42), 0.2, "WoodDark")
    _bent(b, -2.0, ztop=zr(-2.0) - 0.52)
    # quay abutment (sits against the quay wall)
    b.box(-PW, PW, y1 - 0.75, y1, -2.2, zr(y1 - 0.75) - 0.32, "Concrete", "body")
    # handrails
    posts = [y0 + 0.3, -1.4, 1.2, y1 - 0.3]
    for sx in (-PW + 0.08, PW - 0.08):
        for yp in posts:
            _bar(b, (sx, yp, zr(yp)), (sx, yp, zr(yp) + 1.0), 0.07, "Steel", "detail")
        for h, w in ((1.0, 0.06), (0.5, 0.045)):
            _bar(b, (sx, posts[0], zr(posts[0]) + h), (sx, posts[-1], zr(posts[-1]) + h), w, "Steel", "detail")
    b.entrance = (0.0, y1)
    return b.finish(category="misc", tags=["pier", "marina", "waterfront", "ramp"], landmark="",
                    extra={"deck_level": 0.0, "rise": RISE, "tile_length": 8.0, "width": 4.0,
                           "connects": "-Y end at z 0 (pier deck), +Y end at +1.37 (quay deck)"})


BUILD = {"airport_hangar": airport_hangar, "airport_tower": airport_tower, "lighthouse": lighthouse, "tram_stop": tram_stop,
         "radio_mast": radio_mast, "pier_straight": pier_straight, "pier_end": pier_end, "pier_ramp": pier_ramp}

VIEWS = {
    "airport_hangar": dict(cut=7.6, shots=[((0.0, 21.0, 2.2), (0.0, 0.0, 3.5)), ((0.0, 8.0, 1.7), (-4.0, -14.0, 2.5)),
                                           ((-12.5, 12.0, 1.8), (6.0, -10.0, 2.6)), ((12.5, -8.5, 1.8), (-10.0, 8.0, 2.8))]),
    "airport_tower": dict(cut=3.0, box=(-6.3, 6.3, 0.3, 6.3),
                          shots=[((0.0, 8.5, 1.7), (-2.8, 1.5, 1.4)), ((4.9, 5.0, 1.7), (-4.0, 1.4, 1.4)),
                                 ((-4.3, 5.35, 1.7), (3.6, 1.4, 1.2)), ((8.5, 7.0, 18.5), (2.5, -1.8, 16.8))]),
    "lighthouse": dict(shots=[((6.0, 7.5, 23.5), (0.0, 0.0, 22.0)), ((3.0, 9.0, 1.7), (0.0, 0.0, 3.5))], lens=24),
    "tram_stop": dict(shots=[((0.0, 6.5, 1.7), (0.0, -1.0, 1.4)), ((-7.5, 3.5, 2.0), (1.0, -1.2, 1.3)),
                             ((5.8, 1.8, 1.7), (-3.0, -1.4, 1.3)), ((1.5, -5.0, 2.2), (0.0, 0.5, 1.4))], lens=18),
    "radio_mast": dict(shots=[((5.0, 7.5, 1.7), (0.0, 0.0, 12.0)), ((3.5, 4.5, 28.5), (0.0, 0.0, 26.3))], lens=20),
    "pier_straight": dict(shots=[((4.5, 9.0, 1.8), (0.0, 0.0, -0.5)), ((5.5, -2.0, -0.6), (0.0, 1.0, -1.2))], lens=18),
    "pier_end": dict(shots=[((3.0, 6.0, 1.7), (0.0, -2.0, 0.2)), ((2.5, -6.5, 0.2), (0.0, -2.8, -0.5))], lens=18),
    "pier_ramp": dict(shots=[((4.0, -8.0, 1.6), (0.0, 1.0, 0.4)), ((5.5, 2.0, 0.0), (0.0, 0.0, -0.4))], lens=18),
}
