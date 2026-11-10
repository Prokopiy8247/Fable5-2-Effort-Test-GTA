"""bld_facades - P1 storefront kit (W 4.0, H 4.5) and industrial kit (W 4.0, H 4.0). See SPEC_BUILDINGS.md."""
import math
import bmesh
import gta_kit as K
import bld_common as B
import bld_parts as P
from bld_common import fq, q, pane, wall, reveal, fbox, cbox, panel, GD

W = 4.0
X = W / 2
HS = 4.5            # storefront module height
HI = 4.0            # industrial module height
FY = 0.04           # fascia board front plane
SHOP_IDS = ["shop_glass", "shop_door", "shop_solid", "shop_awning"]
IND_IDS = ["ind_wall", "ind_wall_win", "ind_door_roll", "ind_door_man", "ind_parapet", "ind_dock"]
NOTE_F = "sign fascia = tint_b board z 3.2-4.2, front plane Y +0.04: mount sign_* at (0, 0.04, 3.25); shop_awning at z 3.08"


# ============================================================================= storefront kit
def s_fascia(mb):
    """Ledge, blank tint_b sign fascia z 3.2-4.2 (4 cm proud) and the top trim."""
    cbox(mb, -X, X, 0.0, 0.10, 3.08, 3.2, "concrete_light", c=0.03)
    fbox(mb, -X, X, 0.0, FY, 3.2, 4.2, "tint_b", skip="-y -z")
    q(mb, -X, X, 4.2, 4.3, "tint_a")
    cbox(mb, -X, X, 0.0, 0.12, 4.3, HS, "concrete_light", c=0.04)


def s_plinth(mb, x0=-X, x1=X):
    cbox(mb, x0, x1, 0.0, 0.07, 0.0, 0.45, "tile_dark", c=0.03, skip=("back", "bottom"))


def s_piers(mb):
    """Half pilasters at the module edges (neighbours complete them)."""
    for s in (-1, 1):
        xa, xb = sorted((s * (X - 0.14), s * X))
        fbox(mb, xa, xb, 0.0, 0.04, 0.45, 3.08, "tint_a", skip="-y -z +z")


def s_lod(r, x0, x1, z0, fill="@Window"):
    mb = K.MB()
    wall(mb, -X, X, 0, 3.2, (x0, x1, z0, 3.2))
    q(mb, x0, x1, z0, 3.2, fill)
    q(mb, -X, X, 3.2, 4.2, "tint_b")
    q(mb, -X, X, 4.2, HS, "concrete_light")
    return B.lod_obj(mb, r)


def glass_leaf(mb, x0, x1, z0, z1, color, y, yg, w=0.09, kick=0.22):
    """Glazed door leaf: tall kick rail, stiles + top rail, pane at yg. -> glass rect."""
    q(mb, x0, x1, z0, z0 + kick, color, y)
    ia, ib, ic, id_ = P.frame(mb, x0, x1, z0 + kick, z1, w, color, y, yg, bottom=False)
    fq(mb, [(ia, y, ic), (ib, y, ic), (ib, yg, ic), (ia, yg, ic)], color, (0, 0, 1))
    pane(mb, ia, ib, ic, id_, yg)
    return ia, ib, ic, id_


def slats(mb, a, b, z0, z1, n, y, color="steel", d=0.045, groove="steel_dark"):
    """Horizontal slats (roller shutter / roll-up door) between z0..z1: flat faces at y+d separated by dark
    V-grooves reaching back to y (readable from every eye level and in flat light)."""
    h = (z1 - z0) / n
    g = min(d, h * 0.22)
    for k in range(n):
        zb, zt = z0 + k * h, z0 + (k + 1) * h
        fq(mb, [(a, y + d, zb + g), (b, y + d, zb + g), (b, y + d, zt - g), (a, y + d, zt - g)], color, (0, 1, 0))
        fq(mb, [(a, y + d, zt - g), (b, y + d, zt - g), (b, y, zt), (a, y, zt)], groove, (0, 1, 1))
        fq(mb, [(a, y, zb), (b, y, zb), (b, y + d, zb + g), (a, y + d, zb + g)], groove, (0, 1, -1))


def shop_glass():
    r = B.begin("shop_glass", W, HS, notes=NOTE_F)
    mb = K.MB()
    a, b, c, d = -1.8, 1.8, 0.45, 3.0
    wall(mb, -X, X, 0.45, 3.08, (a, b, c, d))
    P.window(mb, a, b, c, d, "charcoal", 0.07, -0.04, vbars=(0.0,), hbars=(2.45,), bw=0.07, split=True,
             rcolors={"b": "tile_dark"})
    s_plinth(mb)
    s_piers(mb)
    s_fascia(mb)
    mb.to_object(r, "mesh")
    s_lod(r, a, b, c)
    return r


def shop_door():
    r = B.begin("shop_door", W, HS, notes=NOTE_F + "; recessed entrance: door leaf x -1.42..-0.42, glass plane Y -0.30")
    mb = K.MB()
    a, b, d = -1.5, 1.5, 3.0
    yb, yg = -0.25, -0.30                       # frame plane / glass plane of the recessed entrance
    zt = 0.04                                   # threshold top
    wall(mb, -X, X, 0.45, 3.08, (a, b, 0.45, d))
    reveal(mb, a, b, 0.0, d, "tint_a", 0.0, yb, sides="lrt", colors={"t": "concrete_light"})
    fbox(mb, a, b, yb, 0.06, 0.0, zt, "concrete_light", skip="-y -z -x +x")              # threshold slab
    fq(mb, [(-0.25, -0.2, d - 0.006), (0.25, -0.2, d - 0.006), (0.25, -0.06, d - 0.006), (-0.25, -0.06, d - 0.006)],
       "emis_lamp", (0, 0, -1))                                                           # soffit downlight
    ia, ib, _ic, id_ = P.frame(mb, a, b, zt, d, 0.08, "charcoal", yb, yg, bottom=False)
    zb = 2.36                                                                             # transom bar bottom
    P.hbar(mb, ia, ib, zb + 0.05, 0.10, "charcoal", yb - 0.004, yg)
    xd = ia + 1.0                                                                         # door leaf right edge
    P.vbar(mb, xd + 0.05, zt, zb, 0.10, "charcoal", yb, yg)
    glass_leaf(mb, ia, xd, zt, zb, "steel", yb - 0.012, yg, w=0.09, kick=0.45 - zt)
    fbox(mb, xd - 0.08, xd - 0.04, yb - 0.012, yb + 0.05, 0.95, 1.5, "chrome")            # pull handle
    xs0 = xd + 0.10
    fbox(mb, xs0, ib, yg, yb - 0.012, zt, 0.45, "tile_dark", skip="-y -z -x +x")          # stall riser
    pane(mb, xs0, ib, 0.45, zb, yg)                                                       # side light
    pane(mb, ia, ib, zb + 0.10, id_, yg)                                                  # transom
    s_plinth(mb, -X, a)
    s_plinth(mb, b, X)
    s_piers(mb)
    s_fascia(mb)
    mb.to_object(r, "mesh")
    s_lod(r, ia, ib, 0.45)
    return r


def shop_solid():
    r = B.begin("shop_solid", W, HS, notes=NOTE_F)
    mb = K.MB()
    a, b, d = -1.7, 1.7, 3.0
    ys = -0.08
    wall(mb, -X, X, 0.45, 3.08, (a, b, 0.45, d))
    cbox(mb, a, b, ys, 0.09, 2.68, d, "steel_dark", c=0.03)                               # shutter housing
    for s in (-1, 1):                                                                     # guide rails
        xa, xb = sorted((s * 1.7, s * 1.62))
        fbox(mb, xa, xb, ys, 0.03, 0.0, 2.68, "steel_dark", skip="-y -z +z")
    slats(mb, -1.62, 1.62, 0.13, 2.68, 15, ys)
    fbox(mb, -1.62, 1.62, ys, ys + 0.07, 0.0, 0.13, "steel_dark", skip="-y -z -x +x")     # bottom bar
    fbox(mb, -0.13, 0.13, ys + 0.07, ys + 0.10, 0.025, 0.105, "hazard_yellow")            # lock box
    for s in (-1, 1):                                                                     # lift handles
        fbox(mb, s * 0.9 - 0.12, s * 0.9 + 0.12, ys + 0.03, ys + 0.085, 0.86, 0.91, "steel_dark")
    s_plinth(mb, -X, a)
    s_plinth(mb, b, X)
    s_piers(mb)
    s_fascia(mb)
    mb.to_object(r, "mesh")
    s_lod(r, a, b, 0.0, "steel")
    return r


def shop_awning():
    r = B.begin("shop_awning", notes="attachment: origin = top-back edge on the wall plane; hangs out to Y +1.2, "
                                     "down to Z -0.78; mount at z 3.08 on shop_* modules")
    mb = K.MB()
    D, DZ, T = 1.2, -0.52, 0.03                # depth, drop of the front edge, fabric thickness
    VH = 0.17                                  # valance height (+ 0.09 scallop point)
    n = 8
    sw = W / n
    zv, zp = DZ - VH, DZ - VH - 0.09
    for i in range(n):
        x0, x1 = -X + i * sw, -X + (i + 1) * sw
        xm = (x0 + x1) / 2
        c = "tint_b" if i % 2 == 0 else "white"
        fq(mb, [(x0, 0, 0), (x1, 0, 0), (x1, D, DZ), (x0, D, DZ)], c, (0, 0, 1))                            # top
        fq(mb, [(x0, 0, -T), (x1, 0, -T), (x1, D - T, DZ - T), (x0, D - T, DZ - T)], c, (0, 0, -1))        # underside
        pts = [(x0, D, DZ), (x1, D, DZ), (x1, D, zv), (xm, D, zp), (x0, D, zv)]
        fq(mb, pts, c, (0, 1, 0))                                                                           # valance
        fq(mb, [(p[0], D - T, p[2]) for p in pts], c, (0, -1, 0))
        fq(mb, [(x0, D - T, zv), (xm, D - T, zp), (xm, D, zp), (x0, D, zv)], c, (0, 0, -1))
        fq(mb, [(xm, D - T, zp), (x1, D - T, zv), (x1, D, zv), (xm, D, zp)], c, (0, 0, -1))
    for s in (-1, 1):                                                                                       # side wings
        for x, nx in ((s * X, s), (s * (X - T), -s)):
            fq(mb, [(x, 0, 0), (x, D, DZ), (x, D, zv), (x, 0, zv)], "tint_b", (nx, 0, 0))
        fq(mb, [(s * X, 0, zv), (s * X, D, zv), (s * (X - T), D, zv), (s * (X - T), 0, zv)], "tint_b", (0, 0, -1))
    mb.to_object(r, "mesh")
    return r


def build_shop():
    for f in (shop_glass, shop_door, shop_solid, shop_awning):
        f()
    return B.stats(SHOP_IDS) + "\n" + "\n".join(B.check(SHOP_IDS))


def qa_shop(part="mesh"):
    ex = [("shop_awning", (-6.0, 0.0, 3.08)), ("shop_awning", (6.0, 0.0, 3.08))] if part == "mesh" else []
    return P.tile("shop", [["shop_glass", "shop_door", "shop_solid", "shop_glass"],
                           ["apt_win_a", "apt_balcony", "apt_win_b", "apt_solid"],
                           ["apt_parapet"] * 4], ta="#e9c9a0", tb="#b8473f", wing=2, part=part, extras=ex)


# ============================================================================= industrial kit
PITCH, VW, SL, RD = 0.5, 0.22, 0.04, 0.05      # rib pitch, valley width, slope width, rib depth
IM = "tint_a_metal"


def _ry(x):
    """Corrugation profile depth at x (valleys centred on multiples of PITCH -> module edges are valleys)."""
    u = abs((x + PITCH / 2) % PITCH - PITCH / 2)
    if u <= VW / 2 + 1e-6:
        return 0.0
    if u >= VW / 2 + SL - 1e-6:
        return RD
    return RD * (u - VW / 2) / SL


def corr(mb, x0, x1, z0, z1, color=IM):
    """Corrugated sheet (vertical trapezoid ribs) between x0..x1, z0..z1; valleys lie on Y = 0."""
    xs = {round(x0, 4), round(x1, 4)}
    for k in range(int(math.floor(x0 / PITCH)) - 1, int(math.ceil(x1 / PITCH)) + 2):
        for s in (-1, 1):
            for u in (VW / 2, VW / 2 + SL):
                x = round(k * PITCH + s * u, 4)
                if x0 + 1e-4 < x < x1 - 1e-4:
                    xs.add(x)
    xs = sorted(xs)
    for i in range(len(xs) - 1):
        xa, xb = xs[i], xs[i + 1]
        fq(mb, [(xa, _ry(xa), z0), (xb, _ry(xb), z0), (xb, _ry(xb), z1), (xa, _ry(xa), z1)], color, (0, 1, 0))
    for x, n in ((xs[0], -1), (xs[-1], 1)):
        if _ry(x) > 1e-4:
            fq(mb, [(x, 0, z0), (x, _ry(x), z0), (x, _ry(x), z1), (x, 0, z1)], color, (n, 0, 0))


def i_base(mb, x0=-X, x1=X):
    cbox(mb, x0, x1, 0.0, 0.09, 0.0, 0.5, "concrete", c=0.04, skip=("back", "bottom"))


def i_lod(r, hole=None, fill="@Window", base=True, extra=None):
    mb = K.MB()
    if base:
        q(mb, -X, X, 0, 0.5, "concrete")
    wall(mb, -X, X, 0.5 if base else 0.0, HI, hole, IM)
    if hole:
        q(mb, hole[0], hole[1], hole[2], hole[3], fill)
    if extra:
        extra(mb)
    return B.lod_obj(mb, r)


def hazard_post(mb, x, y, h=1.1, r=0.085, bands=5, segs=6):
    rings = [mb.ring_xy(x, y, h * i / bands, r, r, segs) for i in range(bands + 1)]
    cols = ["hazard_yellow" if i % 2 == 0 else "black" for i in range(bands)]
    mb.loft(rings, "hazard_yellow", closed=True, cap_start=False, cap_end=True, smooth=True, ring_colors=cols)


def ind_wall():
    r = B.begin("ind_wall", W, HI)
    mb = K.MB()
    corr(mb, -X, X, 0.5, HI)
    i_base(mb)
    mb.to_object(r, "mesh")
    i_lod(r)
    return r


def ind_wall_win():
    r = B.begin("ind_wall_win", W, HI)
    mb = K.MB()
    a, b, c, d = -1.89, 1.89, 2.55, 3.55                    # surround outer rect (valley edge to valley edge)
    t, fw = 0.075, 0.05
    corr(mb, -X, X, 0.5, c)
    corr(mb, -X, X, d, HI)
    q(mb, -X, a, c, d, IM)
    q(mb, b, X, c, d, IM)
    fbox(mb, a, b, 0.0, t, c, d, "steel_dark", skip="-y +y")
    ia, ib, ic, id_ = a + fw, b - fw, c + fw, d - fw        # glass z 2.6-3.5
    wall(mb, a, b, c, d, (ia, ib, ic, id_), "steel_dark", t)
    reveal(mb, ia, ib, ic, id_, "steel_dark", t, GD)
    pw = (ib - ia) / 4
    for i in (1, 2, 3):
        P.vbar(mb, ia + i * pw, ic, id_, 0.06, "steel", 0.02, GD)
    for i in range(4):
        pane(mb, ia + i * pw + (0.03 if i else 0.0), ia + (i + 1) * pw - (0.03 if i < 3 else 0.0), ic, id_)
    i_base(mb)
    mb.to_object(r, "mesh")
    i_lod(r, (ia, ib, ic, id_))
    return r


def ind_door_roll():
    r = B.begin("ind_door_roll", W, HI, notes="roll-up door opening x +-1.7, z 0-3.6; bollards reach Y +0.33")
    mb = K.MB()
    a, b, d = -1.7, 1.7, 3.6
    fa, fb, fd = -1.89, 1.89, 3.79                          # frame outer
    yd, t = -0.10, 0.09
    q(mb, -X, fa, 0, HI, IM)
    q(mb, fb, X, 0, HI, IM)
    corr(mb, fa, fb, fd, HI)
    fbox(mb, fa, fb, 0.0, t, 0.0, fd, "tint_b", skip="-y +y -z")
    wall(mb, fa, fb, 0.0, fd, (a, b, 0.0, d), "tint_b", t)
    reveal(mb, a, b, 0.0, d, "tint_b", t, yd, sides="lrt")
    slats(mb, a, b, 0.14, d, 14, yd, "steel", 0.05)
    fbox(mb, a, b, yd, yd + 0.08, 0.0, 0.14, "steel_dark", skip="-y -z -x +x")            # bottom bar
    fbox(mb, -0.3, 0.3, yd + 0.08, yd + 0.12, 0.05, 0.10, "steel")                        # lift handle
    for s in (-1, 1):
        hazard_post(mb, s * 1.8, 0.24)
    mb.to_object(r, "mesh")
    i_lod(r, (a, b, 0.0, d), "steel", base=False)
    return r


def ind_door_man():
    r = B.begin("ind_door_man", W, HI, notes="personnel door opening x +-0.5, z 0-2.1")
    mb = K.MB()
    a, b, d = -0.5, 0.5, 2.1
    fa, fb, fd = -0.61, 0.61, 2.21                          # frame outer (valley edge to valley edge)
    yd, t = -0.05, 0.08
    corr(mb, -X, fa, 0.5, HI)
    corr(mb, fb, X, 0.5, HI)
    corr(mb, fa, fb, fd, HI)
    i_base(mb, -X, fa)
    i_base(mb, fb, X)
    fbox(mb, fa, fb, 0.0, t, 0.0, fd, "steel_dark", skip="-y +y -z")
    wall(mb, fa, fb, 0.0, fd, (a, b, 0.0, d), "steel_dark", t)
    reveal(mb, a, b, 0.0, d, "steel_dark", t, yd, sides="lrt")
    q(mb, a, b, 0.03, d, "steel", yd)                                                     # door leaf
    panel(mb, a + 0.1, b - 0.1, 0.3, 1.0, "steel", t=0.02, c=0.04, y=yd)
    panel(mb, a + 0.1, b - 0.1, 1.15, 1.95, "steel", t=0.02, c=0.04, y=yd)
    q(mb, a + 0.02, b - 0.02, 0.05, 0.24, "steel_dark", yd + 0.006)                       # kick plate
    fbox(mb, b - 0.17, b - 0.09, yd, yd + 0.025, 0.98, 1.16, "steel_dark")                # lock plate + lever
    fbox(mb, b - 0.3, b - 0.1, yd + 0.025, yd + 0.065, 1.07, 1.11, "chrome")
    fbox(mb, a, b, yd, 0.10, 0.0, 0.03, "concrete_light", skip="-y -z -x +x")             # threshold
    fbox(mb, -0.10, 0.10, 0.0, 0.03, 2.44, 2.74, "steel_dark")                            # bulkhead lamp
    fbox(mb, -0.075, 0.075, 0.03, 0.12, 2.48, 2.68, "emis_lamp", skip="-y")
    cbox(mb, -0.12, 0.12, 0.0, 0.16, 2.70, 2.75, "steel_dark", c=0.015)
    fbox(mb, 0.62, 0.88, 0.05, 0.065, 1.45, 1.75, "hazard_yellow")                        # notice plate on a crest
    q(mb, 0.66, 0.84, 1.63, 1.70, "black", 0.07)
    q(mb, 0.66, 0.84, 1.52, 1.57, "black", 0.07)
    mb.to_object(r, "mesh")
    _lod_man(r, a, b, d)
    return r


def _lod_man(r, a, b, d):
    mb = K.MB()
    wall(mb, -X, X, 0.5, HI, (a, b, 0.5, d), IM)
    q(mb, a, b, 0.0, d, "steel")
    q(mb, -X, a, 0.0, 0.5, "concrete")
    q(mb, b, X, 0.0, 0.5, "concrete")
    return B.lod_obj(mb, r)


def ind_parapet():
    r = B.begin("ind_parapet", W, 0.6, notes="flashing fascia stands 0.08 proud of the wall plane (covers the rib tops)")
    mb = K.MB()
    fbox(mb, -X, X, 0.0, 0.08, 0.0, 0.42, IM, skip="-y +z")
    fq(mb, [(-X, -0.25, 0), (X, -0.25, 0), (X, -0.25, 0.42), (-X, -0.25, 0.42)], "steel_dark", (0, -1, 0))
    mb.prism([(-0.30, 0.42), (0.13, 0.42), (0.13, 0.55), (0.08, 0.6), (-0.25, 0.6), (-0.30, 0.55)], W,
             "tint_b_metal", plane="YZ")
    mb.to_object(r, "mesh")
    lb = K.MB()
    fbox(lb, -X, X, -0.25, 0.08, 0.0, 0.42, IM, skip="-x +x -z +z", colors={"-y": "steel_dark"})
    fbox(lb, -X, X, -0.30, 0.13, 0.42, 0.6, "tint_b_metal", skip="-x +x -z")
    B.lod_obj(lb, r)
    return r


def ind_dock():
    r = B.begin("ind_dock", notes="prop: origin on the wall plane at ground; platform 4.0 x 2.4 x 1.2 toward +Y "
                                  "(+0.1 bumpers), steps at the +X end rising toward the wall, handrail to z 2.15")
    mb = K.MB()
    D, Hd, xs = 2.4, 1.2, 1.2
    out = mb.prism([(-X, 0), (-X, D), (xs, D), (xs, 1.0), (X, 1.0), (X, 0)], Hd, "concrete", plane="XY", center=False,
                   caps=(False, True), cap_colors=("concrete", "concrete_light"))
    bmesh.ops.delete(mb.bm, geom=[out["sides"][5]], context="FACES")                      # face against the wall
    fbox(mb, -X, xs, D - 0.14, D + 0.012, Hd - 0.10, Hd + 0.008, "hazard_yellow", skip="-y -z")   # edge angle
    z = Hd + 0.006
    fq(mb, [(-1.3, 1.2, z), (0.3, 1.2, z), (0.3, D - 0.15, z), (-1.3, D - 0.15, z)], "steel_dark", (0, 0, 1))  # leveller
    for x in (-1.6, -0.5, 0.6):                                                           # rubber bumpers
        cbox(mb, x - 0.15, x + 0.15, D, D + 0.1, 0.5, 1.05, "rubber", c=0.03)
    st = [(1.0, 0), (2.4, 0), (2.4, 0.2), (2.12, 0.2), (2.12, 0.4), (1.84, 0.4), (1.84, 0.6), (1.56, 0.6),
          (1.56, 0.8), (1.28, 0.8), (1.28, 1.0), (1.0, 1.0)]
    sc = [None, None] + ["concrete_light", None] * 5
    mb.prism(st, X - xs, "concrete", plane="YZ", pos=((X + xs) / 2, 0, 0), caps=(False, True), side_colors=sc)
    xr = X - 0.05                                                                         # handrail
    mb.tube([(xr, 2.3, 0.2), (xr, 2.3, 1.15), (xr, 1.14, 1.95), (xr, 0.08, 2.15), (xr, 0.08, 1.2)], 0.028,
            "hazard_yellow", segs=5)
    mb.tube([(xr, 1.14, 1.0), (xr, 1.14, 1.95)], 0.024, "hazard_yellow", segs=5, caps=False)
    mb.to_object(r, "mesh")
    return r


def build_ind():
    for f in (ind_wall, ind_wall_win, ind_door_roll, ind_door_man, ind_parapet, ind_dock):
        f()
    return B.stats(IND_IDS) + "\n" + "\n".join(B.check(IND_IDS))


def qa_ind(part="mesh"):
    ex = [("ind_dock", (-2.0, 0.0, 0.0))] if part == "mesh" else []
    return P.tile("ind", [["ind_wall", "ind_door_roll", "ind_door_man", "ind_wall_win"],
                          ["ind_wall_win", "ind_wall", "ind_wall_win", "ind_wall"],
                          ["ind_parapet"] * 4], ta="#8fa9b8", tb="#d9822b", wing=2, part=part, extras=ex)
