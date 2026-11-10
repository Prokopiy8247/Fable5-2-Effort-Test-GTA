"""bld_house - P1 house kit (wall modules W 3.0 / H 3.0, roof slices, gables, porch, chimney). See SPEC_BUILDINGS.md.

House floor level = z 0.3 (concrete foundation band 0-0.3 on every wall module, door sill and porch deck at 0.3).
Lap siding: 6 boards of 0.45 from z 0.3 to 3.0; gables continue the same board rhythm.
"""
import math
import bpy
import bmesh
import gta_kit as K
import bld_common as B
import bld_parts as P
from bld_common import fq, q, pane, wall, reveal, fbox, cbox, panel, GD

HW, HH = 3.0, 3.0
X3 = HW / 2
FZ = 0.3                                # foundation top / floor level
SB, SD, SLIP = 0.45, 0.04, 0.035        # siding board height, proud depth, lip height
IDS = ["house_wall", "house_wall_win", "house_wall_door", "house_wall_garage", "house_roof_9", "house_roof_6",
       "house_gable_9", "house_gable_6", "house_porch", "house_chimney"]


# ----------------------------------------------------------------------------- shared parts
def _sy(z, zb):
    u = (z - zb) % SB
    if u < 1e-6 or SB - u < 1e-6:
        return 0.0
    return SD * u / SLIP if u < SLIP else SD * (SB - u) / (SB - SLIP)


def _szs(z0, z1, zb):
    zs = {round(z0, 4), round(z1, 4)}
    k = int(math.floor((z0 - zb) / SB))
    while zb + k * SB < z1:
        for z in (zb + k * SB, zb + k * SB + SLIP):
            if z0 + 1e-4 < z < z1 - 1e-4:
                zs.add(round(z, 4))
        k += 1
    return sorted(zs)


def siding(mb, x0, x1, z0, z1, zb=FZ, color="tint_a", ends=""):
    """Lap siding x0..x1, z0..z1: each board = shadow lip + face leaning back to Y 0. ends 'l'/'r' = end caps."""
    zs = _szs(z0, z1, zb)
    for i in range(len(zs) - 1):
        za, zc = zs[i], zs[i + 1]
        ya, yc = _sy(za, zb), _sy(zc, zb)
        fq(mb, [(x0, ya, za), (x1, ya, za), (x1, yc, zc), (x0, yc, zc)], color, (0, 1, 0))
        for e, x, n in (("l", x0, -1), ("r", x1, 1)):
            if e in ends:
                fq(mb, [(x, 0, za), (x, ya, za), (x, yc, zc), (x, 0, zc)], color, (n, 0, 0))


def found(mb, x0=-X3, x1=X3):
    cbox(mb, x0, x1, 0.0, 0.07, 0.0, FZ, "concrete", c=0.03, skip=("back", "bottom"))


def casing(mb, a, b, c, d, w=0.09, t=0.06, color="white", bottom=True, y1=0.0):
    """Proud trim ring around opening a..b x c..d: outer sides, front ring, inner faces back to y1."""
    oa, ob, oc, od = a - w, b + w, (c - w if bottom else c), d + w
    fbox(mb, oa, ob, 0.0, t, oc, od, color, skip="-y +y" + ("" if bottom else " -z"))
    wall(mb, oa, ob, oc, od, (a, b, c, d), color, t)
    reveal(mb, a, b, c, d, color, t, y1, sides="lrt" + ("b" if bottom else ""))
    return oa, ob, oc, od


def wall_lamp(mb, x, z, y=0.03):
    fbox(mb, x - 0.07, x + 0.07, 0.0, y + 0.03, z - 0.16, z + 0.16, "charcoal")
    fbox(mb, x - 0.055, x + 0.055, y + 0.03, y + 0.15, z - 0.11, z + 0.07, "emis_lamp", skip="-y +z")
    cbox(mb, x - 0.085, x + 0.085, y + 0.01, y + 0.19, z + 0.07, z + 0.12, "charcoal", c=0.015)


def h_lod(r, W, hole=None, fill="@Window", base=True):
    mb = K.MB()
    X = W / 2
    if base:
        q(mb, -X, X, 0, FZ, "concrete")
    wall(mb, -X, X, FZ if base else 0.0, HH, hole, "tint_a")
    if hole:
        q(mb, hole[0], hole[1], hole[2], hole[3], fill)
    return B.lod_obj(mb, r)


# ----------------------------------------------------------------------------- wall modules
def house_wall():
    r = B.begin("house_wall", HW, HH)
    mb = K.MB()
    siding(mb, -X3, X3, FZ, HH, ends="lr")
    found(mb)
    fbox(mb, -0.25, 0.25, 0.07, 0.085, 0.08, 0.22, "charcoal")                 # crawl-space vent
    for z in (0.115, 0.15, 0.185):
        q(mb, -0.22, 0.22, z - 0.008, z + 0.008, "gray_mid", 0.09)
    mb.to_object(r, "mesh")
    h_lod(r, HW)
    return r


def house_wall_win():
    r = B.begin("house_wall_win", HW, HH)
    mb = K.MB()
    a, b, c, d = -0.6, 0.6, 1.0, 2.4
    zm = (c + d) / 2
    oa, ob, _oc, od = casing(mb, a, b, c, d, bottom=False)
    P.window(mb, a, b, c, d, "white", 0.06, -0.04, wallc="white", hbars=(zm,), bw=0.06)
    P.vbar(mb, 0.0, zm + 0.03, d - 0.06, 0.04, "white", -0.045)                # upper sash muntin
    cbox(mb, oa - 0.05, ob + 0.05, 0.0, 0.13, c - 0.08, c, "white", c=0.025)   # sill
    siding(mb, -X3, oa, FZ, HH, ends="l")
    siding(mb, ob, X3, FZ, HH, ends="r")
    siding(mb, oa, ob, FZ, c - 0.08)
    siding(mb, oa, ob, od, HH)
    for s in (-1, 1):
        xa, xb = sorted((s * (ob + 0.03), s * (ob + 0.43)))
        P.louvre(mb, xa, xb, c - 0.03, d + 0.03, "tint_b", n=7, t=0.05, fw=0.05, y=0.035)
    found(mb)
    mb.to_object(r, "mesh")
    h_lod(r, HW, (a, b, c, d))
    return r


def house_wall_door():
    r = B.begin("house_wall_door", HW, HH, notes="door 0.95 x 2.1, sill at z 0.3 (house floor / porch deck level)")
    mb = K.MB()
    a, b, c, d = -0.475, 0.475, FZ, FZ + 2.1
    yd = -0.06
    oa, ob, _oc, od = casing(mb, a, b, c, d, bottom=False, y1=yd)
    fq(mb, [(a, yd, c), (b, yd, c), (b, 0.0, c), (a, 0.0, c)], "concrete_light", (0, 0, 1))      # threshold
    q(mb, a, b, c, d, "tint_b", yd)                                                              # door leaf
    panel(mb, a + 0.1, -0.04, c + 0.15, c + 1.1, "tint_b", t=0.022, c=0.04, y=yd)
    panel(mb, 0.04, b - 0.1, c + 0.15, c + 1.1, "tint_b", t=0.022, c=0.04, y=yd)
    wa, wb, wc, wd = a + 0.2, b - 0.2, c + 1.38, c + 1.88                                         # small window
    fbox(mb, wa - 0.05, wb + 0.05, yd, yd + 0.02, wc - 0.05, wd + 0.05, "white")
    pane(mb, wa, wb, wc, wd, yd + 0.026)
    fbox(mb, b - 0.14, b - 0.06, yd, yd + 0.02, c + 0.95, c + 1.15, "brass")                      # handle
    fbox(mb, b - 0.13, b - 0.07, yd + 0.02, yd + 0.075, c + 1.06, c + 1.12, "brass")
    cbox(mb, -0.9, 0.9, 0.0, 0.35, 0.0, 0.15, "concrete_light", c=0.02, skip=("back", "bottom"))  # step + landing
    cbox(mb, -0.9, 0.9, 0.0, 0.18, 0.15, FZ - 0.01, "concrete_light", c=0.02, skip=("back", "bottom"))
    siding(mb, -X3, oa, FZ, HH, ends="l")
    siding(mb, ob, X3, FZ, HH, ends="r")
    siding(mb, oa, ob, od, HH)
    found(mb, -X3, -0.9)
    found(mb, 0.9, X3)
    wall_lamp(mb, 1.0, 2.0)
    mb.to_object(r, "mesh")
    h_lod(r, HW, (a, b, c, d), "tint_b")
    return r


def house_wall_garage():
    r = B.begin("house_wall_garage", 6.0, HH, notes="W 6.0 (two module widths); garage door opening x +-2.4, z 0-2.3")
    mb = K.MB()
    XG = 3.0
    a, b, d = -2.4, 2.4, 2.3
    yd = -0.08
    oa, ob, _oc, od = casing(mb, a, b, 0.0, d, w=0.1, t=0.06, bottom=False, y1=yd)
    q(mb, a, b, 0.0, d, "gray_light", yd)
    rows, cols = 4, 4
    ph, pw = d / rows, (b - a) / cols
    for i in range(rows):
        for j in range(cols):
            panel(mb, a + j * pw + 0.05, a + (j + 1) * pw - 0.05, i * ph + 0.04, (i + 1) * ph - 0.04, "white",
                  t=0.03, c=0.035, y=yd)
    fbox(mb, -0.22, 0.22, yd + 0.03, yd + 0.07, 0.25, 0.31, "steel_dark")                        # lift handle
    siding(mb, -XG, oa, FZ, HH, ends="l")
    siding(mb, ob, XG, FZ, HH, ends="r")
    siding(mb, oa, ob, od, HH)
    found(mb, -XG, oa)
    found(mb, ob, XG)
    wall_lamp(mb, 0.0, 2.68)
    mb.to_object(r, "mesh")
    h_lod(r, 6.0, (a, b, 0.0, d), "white", base=False)
    return r


# ----------------------------------------------------------------------------- roof slices + gables
def _roof(aid, half, ridge, n, eave=0.45, tv=0.17, s=0.035):
    r = B.begin(aid, 3.0, None, notes="roof slice 3.0 along X for a %.1f m deep house: z 0 = wall top, ridge along X "
                                      "at z %.2f (underside %.2f), eaves overhang %.2f to Y +-%.2f"
                                      % (2 * half, ridge + tv, ridge, eave, half + eave))
    mb = K.MB()
    E = half + eave
    sl = ridge / half
    zu = lambda y: ridge - sl * abs(y)
    zt = lambda y: zu(y) + tv
    L = E / n
    pts, cols = [(E, zu(E))], ["white"]                       # fascia
    for k in range(n):                                        # +Y slope: shingle course + butt riser
        ylo, yhi = E - k * L, max(0.0, E - (k + 1) * L)
        pts += [(ylo, zt(ylo) + s), (yhi, zt(yhi))]
        cols += ["tint_b", "tint_b"]
    for k in range(n - 1, -1, -1):                            # -Y slope
        ylo = E - k * L
        pts.append((-ylo, zt(ylo) + s))
        cols.append("tint_b" if k else "white")
        if k:
            pts.append((-ylo, zt(ylo)))
            cols.append("tint_b")
    pts += [(-E, zu(E)), (0.0, ridge)]                        # closed underside (soffit)
    cols += ["offwhite", "offwhite"]
    mb.prism(pts, 3.0, "tint_b", plane="YZ", side_colors=cols, cap_colors=("white", "white"))
    zr, zl = zt(0.0), zt(0.22)                                # ridge cap
    mb.prism([(-0.22, zl), (0.22, zl), (0.22, zl + 0.07), (0.0, zr + 0.07), (-0.22, zl + 0.07)], 3.0, "tint_b",
             plane="YZ")
    mb.to_object(r, "mesh")
    lb = K.MB()
    zf = zt(E) + s
    for sg in (-1, 1):
        fq(lb, [(-1.5, sg * E, zf), (1.5, sg * E, zf), (1.5, 0, zr + 0.07), (-1.5, 0, zr + 0.07)], "tint_b", (0, 0, 1))
        fq(lb, [(-1.5, sg * E, zu(E)), (1.5, sg * E, zu(E)), (1.5, sg * E, zf), (-1.5, sg * E, zf)], "white",
           (0, sg, 0))
    B.lod_obj(lb, r)
    return r


def house_roof_9():
    return _roof("house_roof_9", 4.5, 2.4, 6)


def house_roof_6():
    return _roof("house_roof_6", 3.0, 1.6, 4)


def _gable(aid, half, ridge):
    r = B.begin(aid, 2 * half, ridge, notes="gable-end infill under %s: face at Y 0, 0.2 thick, white rake boards"
                                            % aid.replace("gable", "roof"))
    mb = K.MB()
    wz = lambda z: half * (1.0 - z / ridge)
    zs = _szs(0.0, ridge, 0.0)
    for i in range(len(zs) - 1):
        za, zc = zs[i], zs[i + 1]
        ya, yc = _sy(za, 0.0), _sy(zc, 0.0)
        fq(mb, [(-wz(za), ya, za), (wz(za), ya, za), (wz(zc), yc, zc), (-wz(zc), yc, zc)], "tint_a", (0, 1, 0))
    t, rw = 0.07, 0.2
    xi = half * (1.0 - rw / ridge)
    for s in (-1, 1):                                                                             # rake boards
        fq(mb, [(s * half, t, 0), (0, t, ridge), (0, t, ridge - rw), (s * xi, t, 0)], "white", (0, 1, 0))
        fq(mb, [(s * xi, 0, 0), (s * xi, t, 0), (0, t, ridge - rw), (0, 0, ridge - rw)], "white", (-s, 0, -1))
        fq(mb, [(s * half, -0.2, 0), (s * half, t, 0), (0, t, ridge), (0, -0.2, ridge)], "white", (s, 0, 1))
    fq(mb, [(-half, -0.2, 0), (half, -0.2, 0), (0, -0.2, ridge)], "wood_light", (0, -1, 0))        # attic side
    zc = ridge * 0.42
    P.louvre(mb, -0.3, 0.3, zc - 0.3, zc + 0.3, "white", n=4, t=0.05, fw=0.05, y=0.035)            # attic vent
    mb.to_object(r, "mesh")
    lb = K.MB()
    fq(lb, [(-half, 0, 0), (half, 0, 0), (0, 0, ridge)], "tint_a", (0, 1, 0))
    B.lod_obj(lb, r)
    return r


def house_gable_9():
    return _gable("house_gable_9", 4.5, 2.4)


def house_gable_6():
    return _gable("house_gable_6", 3.0, 1.6)


# ----------------------------------------------------------------------------- porch + chimney
def house_porch():
    r = B.begin("house_porch", notes="attachment: origin on the wall plane at ground; deck top z 0.31, step at the "
                                     "front centre, shed roof z 2.35-2.68 (fits under the main eave)")
    mb = K.MB()
    DW, DD, DZ = 1.5, 1.65, 0.31
    PX, PY, zb = 1.4, 1.55, 2.25
    Wc = "white"
    fbox(mb, -DW, DW, 0.0, DD, 0.0, DZ, Wc, skip="-y -z", colors={"+z": "wood_light"})             # deck
    fbox(mb, -0.6, 0.6, DD, 2.0, 0.0, 0.155, Wc, skip="-y -z", colors={"+z": "wood_light"})        # step
    for y in (0.42, 0.83, 1.24):                                                                   # plank seams
        fq(mb, [(-DW + 0.03, y - 0.012, DZ + 0.005), (DW - 0.03, y - 0.012, DZ + 0.005),
                (DW - 0.03, y + 0.012, DZ + 0.005), (-DW + 0.03, y + 0.012, DZ + 0.005)], "wood_mid", (0, 0, 1))
    for s in (-1, 1):
        x = s * PX
        fbox(mb, x - 0.065, x + 0.065, PY - 0.065, PY + 0.065, DZ, zb, Wc, skip="-z +z")           # post
        fbox(mb, x - 0.095, x + 0.095, PY - 0.095, PY + 0.095, DZ, DZ + 0.12, Wc, skip="-z")       # base
        fbox(mb, x - 0.095, x + 0.095, PY - 0.095, PY + 0.095, zb - 0.09, zb, Wc, skip="+z")       # capital
        fbox(mb, x - 0.05, x + 0.05, 0.0, PY - 0.07, zb, zb + 0.14, Wc, skip="-y +y +z")           # side beam
        # side railing (wall -> post)
        fbox(mb, x - 0.035, x + 0.035, 0.02, PY - 0.065, 1.13, 1.2, Wc, skip="-y +y")
        fbox(mb, x - 0.025, x + 0.025, 0.02, PY - 0.065, 0.43, 0.48, Wc, skip="-y +y")
        for i in range(5):
            y = 0.02 + (PY - 0.085) * (i + 0.75) / 5.5
            fbox(mb, x - 0.02, x + 0.02, y - 0.02, y + 0.02, 0.48, 1.13, Wc, skip="-z +z")
        # front railing (post -> newel at the step)
        xa, xb = sorted((s * 0.6, s * (PX - 0.065)))
        fbox(mb, xa, xb, PY - 0.035, PY + 0.035, 1.13, 1.2, Wc, skip="-x +x")
        fbox(mb, xa, xb, PY - 0.025, PY + 0.025, 0.43, 0.48, Wc, skip="-x +x")
        for i in range(3):
            xk = xa + (xb - xa) * (i + 0.8) / 3.6 if s > 0 else xb - (xb - xa) * (i + 0.8) / 3.6
            fbox(mb, xk - 0.02, xk + 0.02, PY - 0.02, PY + 0.02, 0.48, 1.13, Wc, skip="-z +z")
        xn = s * 0.6
        fbox(mb, xn - 0.05, xn + 0.05, PY - 0.05, PY + 0.05, DZ, 1.27, Wc, skip="-z")              # newel
    fbox(mb, -DW, DW, PY - 0.07, PY + 0.07, zb, zb + 0.14, Wc, skip="+z")                          # front beam
    sl, zu0, tv, sh, n, D = 0.1, 2.55, 0.1, 0.03, 3, 2.0                                           # shed roof
    zu = lambda y: zu0 - sl * y
    zt = lambda y: zu(y) + tv
    L = D / n
    pts, cols = [(D, zu(D))], ["white"]
    for k in range(n):
        ylo, yhi = D - k * L, max(0.0, D - (k + 1) * L)
        pts += [(ylo, zt(ylo) + sh), (yhi, zt(yhi))]
        cols += ["tint_b", "tint_b"]
    cols[-1] = "white"
    pts.append((0.0, zu(0.0)))
    cols.append("offwhite")
    mb.prism(pts, 2 * DW, "tint_b", plane="YZ", side_colors=cols, cap_colors=("white", "white"))
    mb.to_object(r, "mesh")
    return r


def house_chimney():
    r = B.begin("house_chimney", notes="origin base centre (sink the base into the roof slope)", spacing=4.0)
    mb = K.MB()
    sq = lambda h, z0, z1, col, skip, **kw: fbox(mb, -h, h, -h, h, z0, z1, col, skip=skip, **kw)
    sq(0.30, 0.0, 1.74, "brick_red", "-z +z")
    for z in (0.5, 1.1):
        sq(0.31, z, z + 0.06, "brick_dark", "-z +z")
    sq(0.32, 1.74, 1.82, "brick_dark", "+z")
    sq(0.34, 1.82, 1.92, "brick_red", "+z")
    sq(0.35, 1.92, 2.0, "concrete_light", "")
    for x in (-0.15, 0.15):
        mb.cyl(0.085, 0.2, (x, 0.0, 2.0), "terracotta", segs=6, r2=0.07, base=True, cap_color="black")
    mb.to_object(r, "mesh")
    return r


BUILD = (house_wall, house_wall_win, house_wall_door, house_wall_garage, house_roof_9, house_roof_6,
         house_gable_9, house_gable_6, house_porch, house_chimney)


def build_all():
    for f in BUILD:
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS))


def qa_house(part="mesh", ta="#d9c7a3", tb="#7a3b34"):
    """Temporary `zz_tile_house`: one small 9 x 6 house assembled from the kit + a loose 9 m roof/gable sample.
    Remove with bld_parts.untile('house')."""
    name = "zz_tile_house"
    P.untile("house")
    root = K.begin_asset(name, B.CAT, 30.0)
    mat = P._prev_mat("house", ta, tb)
    cache = {}

    def put(aid, pos, rz=0.0, k=[0]):
        if aid not in cache:
            src = bpy.data.objects.get("%s__%s" % (aid, part)) or bpy.data.objects["%s__mesh" % aid]
            me = src.data.copy()
            for i, m in enumerate(me.materials):
                if m is not None and m.name == "Palette":
                    me.materials[i] = mat
            cache[aid] = me
        k[0] += 1
        o = bpy.data.objects.new("%s__m%03d" % (name, k[0]), cache[aid])
        for c in root.users_collection:
            c.objects.link(o)
        o.parent = root
        o.location = pos
        o.rotation_euler = (0.0, 0.0, math.radians(rz))

    put("house_wall_garage", (-1.5, 3.0, 0))
    put("house_wall_door", (3.0, 3.0, 0))
    put("house_porch", (3.0, 3.0, 0))
    for y, a in ((1.5, "house_wall_win"), (-1.5, "house_wall")):
        put(a, (4.5, y, 0), -90)
    for y, a in ((1.5, "house_wall"), (-1.5, "house_wall_win")):
        put(a, (-4.5, y, 0), 90)
    for x, a in ((-3, "house_wall_win"), (0, "house_wall"), (3, "house_wall_win")):
        put(a, (x, -3.0, 0), 180)
    put("house_gable_6", (4.5, 0, 3.0), -90)
    put("house_gable_6", (-4.5, 0, 3.0), 90)
    for x in (-3, 0, 3):
        put("house_roof_6", (x, 0, 3.0))
    put("house_chimney", (-2.5, -1.2, 3.4))
    put("house_roof_9", (10.5, 0, 0.3))                       # loose 9 m sample next to the house
    put("house_roof_9", (13.5, 0, 0.3))
    put("house_gable_9", (15.0, 0, 0.3), -90)
    return name
