"""bld_fronts - P2/P3 feature fronts (W 12.0 = 3 modules, H 4.5; parts mesh + lod1). See SPEC_BUILDINGS.md."""
import bmesh
from mathutils import Vector
import gta_kit as K
import bld_common as B
import bld_parts as P
import bld_qa as Q
from bld_common import fq, q, pane, wall, reveal, fbox, cbox, panel, GD
from bld_house import casing, wall_lamp
from bld_facades import hazard_post

WF, HF, XF = 12.0, 4.5, 6.0
IDS = ["front_police", "front_hospital", "front_hotel", "front_firestation", "front_cinema"]
CL = "concrete_light"


# ----------------------------------------------------------------------------- helpers
def mwall(mb, x0, x1, z0, z1, holes, color="tint_a", y=0.0):
    """Wall with several rectangular holes: one mitred 4-quad frame per hole (strips cut midway between holes)."""
    hs = sorted(holes)
    if not hs:
        return wall(mb, x0, x1, z0, z1, None, color, y)
    cuts = [x0] + [(hs[i][1] + hs[i + 1][0]) * 0.5 for i in range(len(hs) - 1)] + [x1]
    for i, h in enumerate(hs):
        wall(mb, cuts[i], cuts[i + 1], z0, z1, h, color, y)


def hband(mb, x0, x1, z0, z1, fills, wallc="tint_a", y=0.0):
    """LOD band: fill quads [(xa, xb, color)] with wall quads between them."""
    x = x0
    for xa, xb, col in sorted(fills):
        if xa > x + 1e-6:
            q(mb, x, xa, z0, z1, wallc, y)
        q(mb, xa, xb, z0, z1, col, y)
        x = xb
    if x1 > x + 1e-6:
        q(mb, x, x1, z0, z1, wallc, y)


def bulb(mb, p, n=(0, 0, -1), r=0.045, color="emis_lamp"):
    """Marquee bulb: 4-sided pyramid pointing along n."""
    n = Vector(n).normalized()
    t1 = n.cross(Vector((0, 0, 1)))
    if t1.length < 1e-3:
        t1 = n.cross(Vector((1, 0, 0)))
    t1.normalize()
    t2 = n.cross(t1)
    p = Vector(p)
    ap = p + n * r * 1.2
    c = [p + t1 * r, p + t2 * r, p - t1 * r, p - t2 * r]
    for i in range(4):
        fq(mb, [tuple(c[i]), tuple(c[(i + 1) % 4]), tuple(ap)], color, tuple(n))


def bulbs(mb, p0, p1, count, n, r=0.045, color="emis_lamp"):
    for i in range(count):
        t = (i + 0.5) / count
        bulb(mb, [p0[k] + (p1[k] - p0[k]) * t for k in range(3)], n, r, color)


def entrance(mb, a, b, z0, d, leaves=2, fc="steel", fy=-0.06, transom=None, zk=None, rc="steel_dark"):
    """Recessed glazed entrance: frame, kick rail (glass starts >= 0.45), leaf posts, optional transom light."""
    zk = max(0.45, z0 + 0.3) if zk is None else zk
    reveal(mb, a, b, z0, d, rc, 0.0, fy, sides="lrt")
    ia, ib, _c, id_ = P.frame(mb, a, b, z0, d, 0.07, fc, fy, GD, bottom=False)
    fbox(mb, ia, ib, GD, fy, z0, zk, fc, skip="-y -z -x +x")
    top = id_
    if transom:
        P.hbar(mb, ia, ib, transom, 0.07, fc, fy - 0.005, GD)
        pane(mb, ia, ib, transom + 0.035, id_)
        top = transom - 0.035
    lw = (ib - ia) / leaves
    for i in range(1, leaves):
        P.vbar(mb, ia + i * lw, zk, top, 0.07, fc, fy)
    for i in range(leaves):
        pane(mb, ia + i * lw + (0.035 if i else 0.0), ia + (i + 1) * lw - (0.035 if i < leaves - 1 else 0.0), zk, top)
    return ia, ib, zk, top


def pulls(mb, xs, z0, z1, fy=-0.06, color="chrome"):
    for x in xs:
        fbox(mb, x - 0.02, x + 0.02, fy, fy + 0.07, z0, z1, color)


def fwin(mb, a, b, c, d, fc="charcoal", vb=(), hb=(), sill=True, lintel=True):
    P.window(mb, a, b, c, d, fc, 0.07, -0.04, vbars=vb, hbars=hb, bw=0.05)
    if sill:
        cbox(mb, a - 0.12, b + 0.12, 0.0, 0.14, c - 0.1, c, CL, c=0.03)
    if lintel:
        cbox(mb, a - 0.08, b + 0.08, 0.0, 0.07, d, d + 0.14, CL, c=0.02)


def plinth(mb, x0, x1, h=0.5, color="concrete_dark"):
    cbox(mb, x0, x1, 0.0, 0.06, 0.0, h, color, c=0.03, skip=("back", "bottom"))


def begin(aid, notes):
    return B.begin(aid, WF, HF, notes=notes, spacing=15.0)


# ----------------------------------------------------------------------------- police
def front_police():
    r = begin("front_police", "portico (4 columns) + 3 steps protrude to Y +1.0; door sill / platform at z 0.45")
    mb = K.MB()
    zp, sx = 0.45, 3.9
    wins = [(-5.55, -4.15), (-3.15, -1.95), (1.95, 3.15), (4.15, 5.55)]
    wc, wd = 1.35, 2.85
    da, db, dd = -1.1, 1.1, 3.0
    cols = (-3.3, -1.5, 1.5, 3.3)
    mwall(mb, -XF, XF, 0.0, 4.2, [(a, b, wc, wd) for a, b in wins] + [(da, db, zp, dd)])
    for a, b in wins:
        fwin(mb, a, b, wc, wd, vb=((a + b) / 2,), hb=(wd - 0.45,))
    entrance(mb, da, db, zp, dd, leaves=2, transom=2.6)
    pulls(mb, (-0.1, 0.1), 1.3, 1.9)
    for i, yy in enumerate((1.0, 0.85, 0.70)):                                           # steps + platform
        cbox(mb, -sx, sx, 0.0, yy, 0.15 * i, 0.15 * (i + 1), CL, c=0.02, skip=("back", "bottom"))
    for x in cols:
        fbox(mb, x - 0.21, x + 0.21, 0.19, 0.61, zp, 3.2, CL, skip="-z +z")
        fbox(mb, x - 0.27, x + 0.27, 0.13, 0.67, zp, zp + 0.14, CL, skip="-z")
        fbox(mb, x - 0.27, x + 0.27, 0.13, 0.67, 3.06, 3.2, CL, skip="+z")
    fbox(mb, -3.7, 3.7, 0.0, 0.72, 3.2, 4.3, CL, skip="-y +z")                           # entablature
    cbox(mb, -3.85, 3.85, 0.0, 0.9, 4.3, HF, CL, c=0.05)                                 # portico cornice
    cbox(mb, -3.73, 3.73, 0.72, 0.76, 3.52, 3.58, CL, c=0.015)                           # architrave moulding
    q(mb, -3.5, 3.5, 3.25, 3.5, "navy", 0.726)
    K.add_text(mb, "VESPER BAY POLICE", size=0.24, depth=0.0, color="white", pos=(0, 0.733, 3.29), res=1)
    K.add_text(mb, "VBPD", size=0.9, depth=0.07, color="neon_blue", pos=(0, 0.72, 3.63), res=2)
    for x in (-3.3, 3.3):                                                                # blue lamps
        fbox(mb, x - 0.09, x + 0.09, 0.61, 0.66, 2.1, 2.62, "charcoal")
        fbox(mb, x - 0.11, x + 0.11, 0.66, 0.88, 2.2, 2.5, "led_blue", skip="-y")
        cbox(mb, x - 0.14, x + 0.14, 0.64, 0.91, 2.5, 2.56, "charcoal", c=0.02)
        fbox(mb, x - 0.13, x + 0.13, 0.65, 0.90, 2.16, 2.2, "charcoal", skip="-y")
    for s in (-1, 1):
        xa, xb = sorted((s * sx, s * XF))
        plinth(mb, xa, xb)
        xa, xb = sorted((s * 3.85, s * XF))
        cbox(mb, xa, xb, 0.0, 0.12, 4.2, HF, CL, c=0.04)
        xa, xb = sorted((s * 3.7, s * XF))
        fbox(mb, xa, xb, 0.0, 0.03, 3.9, 4.2, "tint_b", skip="-y +z")
    mb.to_object(r, "mesh")
    lb = K.MB()
    q(lb, -XF, XF, 0.0, wc, "tint_a")
    hband(lb, -XF, XF, wc, wd, [(wins[0][0], wins[0][1], "@Window"), (da, db, "@Window"),
                                (wins[3][0], wins[3][1], "@Window")])
    q(lb, -XF, XF, wd, HF, "tint_a")
    fbox(lb, -3.7, 3.7, 0.0, 0.8, 3.2, HF, CL, skip="-y -z")
    for x in cols:
        q(lb, x - 0.21, x + 0.21, zp, 3.2, CL, 0.61)
    fq(lb, [(-sx, 1.0, 0), (sx, 1.0, 0), (sx, 0.55, zp), (-sx, 0.55, zp)], CL, (0, 1, 1))
    B.lod_obj(lb, r)
    return r


# ----------------------------------------------------------------------------- hospital
def front_hospital():
    r = begin("front_hospital", "canopy x +-3.4 protrudes to Y +2.55 on 2 posts; sign band + H block stand on it")
    mb = K.MB()
    Wh = "white"
    ea, eb, ed = -2.6, 2.6, 2.9
    wins = [(-5.6, -3.7), (3.7, 5.6)]
    wc, wd = 1.2, 2.8
    mwall(mb, -XF, XF, 0.0, 4.3, [(wins[0][0], wins[0][1], wc, wd), (ea, eb, 0.0, ed), (wins[1][0], wins[1][1], wc, wd)])
    entrance(mb, ea, eb, 0.0, ed, leaves=4, transom=2.45)
    fbox(mb, -0.25, 0.25, -0.06, 0.05, 2.5, 2.62, "charcoal")                            # door sensor
    for a, b in wins:
        w3 = (b - a) / 3
        fwin(mb, a, b, wc, wd, fc="white", vb=(a + w3, a + 2 * w3), lintel=False)
    for s in (-1, 1):
        xa, xb = sorted((s * 3.4, s * XF))
        fbox(mb, xa, xb, 0.0, 0.04, 3.05, 3.5, "tint_b", skip="-y")                      # accent band
        xa, xb = sorted((s * 2.67, s * XF))
        plinth(mb, xa, xb)
    cbox(mb, -XF, XF, 0.0, 0.12, 4.3, HF, CL, c=0.04)
    cy = 2.5                                                                             # canopy
    fbox(mb, -3.4, 3.4, 0.0, cy, 3.05, 3.5, Wh, skip="-y", colors={"+z": "gray_light"})
    fbox(mb, -3.42, 3.42, cy, cy + 0.02, 3.05, 3.11, "red", skip="-y")
    for x in (-1.9, 0.0, 1.9):                                                           # soffit lights
        fq(mb, [(x - 0.5, 0.9, 3.044), (x + 0.5, 0.9, 3.044), (x + 0.5, 1.5, 3.044), (x - 0.5, 1.5, 3.044)],
           "emis_lamp", (0, 0, -1))
    for x in (-3.0, 3.0):                                                                # posts
        mb.cyl(0.13, 3.05, (x, 2.2, 0.0), Wh, segs=8, base=True, caps=False)
        mb.cyl(0.19, 0.25, (x, 2.2, 0.0), "gray_dark", segs=8, base=True)
    K.add_text(mb, "EMERGENCY", size=0.46, depth=0.05, color="neon_red", pos=(0, cy, 3.145), res=1)
    fbox(mb, -3.3, 1.9, 2.15, 2.3, 3.5, 4.38, "navy", skip="-z")                         # sign band on the canopy
    K.add_text(mb, "VESPER GENERAL", size=0.6, depth=0.05, color="neon_white", pos=(-0.7, 2.3, 3.73), res=1)
    fbox(mb, 2.1, 3.3, 2.05, 2.35, 3.5, 4.45, Wh, skip="-z")                             # white block + green H
    K.add_text(mb, "H", size=1.1, depth=0.05, color="neon_green", pos=(2.7, 2.35, 3.59), res=1)
    mb.to_object(r, "mesh")
    lb = K.MB()
    q(lb, -XF, XF, 0.0, wc, "tint_a")
    hband(lb, -XF, XF, wc, wd, [(wins[0][0], wins[0][1], "@Window"), (ea, eb, "@Window"),
                                (wins[1][0], wins[1][1], "@Window")])
    q(lb, -XF, XF, wd, HF, "tint_a")
    fbox(lb, -3.4, 3.4, 0.0, cy, 3.05, 3.5, Wh, skip="-y")
    q(lb, -3.3, 1.9, 3.5, 4.38, "navy", 2.3)
    q(lb, 2.1, 3.3, 3.5, 4.45, Wh, 2.35)
    for x in (-3.0, 3.0):
        q(lb, x - 0.13, x + 0.13, 0.0, 3.05, Wh, 2.33)
    B.lod_obj(lb, r)
    return r


# ----------------------------------------------------------------------------- hotel
def front_hotel():
    r = begin("front_hotel", "marquee canopy x +-2.6 protrudes to Y +2.26 on 2 gold poles; red carpet strip")
    mb = K.MB()
    G = "gold"
    da, db, dd = -1.3, 1.3, 2.85
    wins = [(-5.3, -3.7), (3.7, 5.3)]
    wc, wd = 0.75, 2.85
    mwall(mb, -XF, XF, 0.0, 4.2, [(wins[0][0], wins[0][1], wc, wd), (da, db, 0.0, dd), (wins[1][0], wins[1][1], wc, wd)])
    entrance(mb, da, db, 0.0, dd, leaves=2, fc="brass", transom=2.35, rc="brass")
    pulls(mb, (-0.12, 0.12), 0.9, 1.7, color=G)
    for a, b in wins:
        fwin(mb, a, b, wc, wd, fc="brass", vb=((a + b) / 2,), hb=(wd - 0.55,))
    for x in (-5.76, -3.2, 3.2, 5.76):                                                   # pilasters
        fbox(mb, x - 0.2, x + 0.2, 0.0, 0.08, 0.5, 4.06, "tint_b", skip="-y -z +z")
        fbox(mb, x - 0.24, x + 0.24, 0.0, 0.11, 4.06, 4.2, G, skip="-y +z")
    for s in (-1, 1):
        xa, xb = sorted((s * 1.37, s * XF))
        plinth(mb, xa, xb, color="granite")
        wall_lamp(mb, s * 3.2, 2.4, y=0.08)
        mb.box((0.5, 0.5, 0.6), (s * 1.95, 0.42, 0.0), "charcoal", base=True)            # planter + shrub
        mb.ico(0.36, (s * 1.95, 0.42, 0.88), "@F:leaf_dark", subdiv=1, jitter=0.12, seed=4 + s)
    cbox(mb, -XF, XF, 0.0, 0.12, 4.2, HF, CL, c=0.04)
    cy, cx, z0, z1 = 2.2, 2.6, 2.95, 3.6                                                 # marquee canopy
    fbox(mb, -cx, cx, 0.0, cy, z0, z1, "maroon", skip="-y", colors={"+z": "roof_dark"})
    for za, zb in ((z0, z0 + 0.08), (z1 - 0.08, z1)):                                    # gold trim
        fbox(mb, -cx - 0.03, cx + 0.03, cy, cy + 0.03, za, zb, G, skip="-y")
        for s in (-1, 1):
            xa, xb = sorted((s * cx, s * (cx + 0.03)))
            fbox(mb, xa, xb, 0.0, cy, za, zb, G, skip="-y +y " + ("-x" if s > 0 else "+x"))
    K.add_text(mb, "TIDELINE HOTEL", size=0.55, depth=0.06, color="neon_pink", pos=(0, cy, 3.085), res=2)
    for y in (0.5, 1.1, 1.7):                                                            # bulb rows
        bulbs(mb, (-2.3, y, z0), (2.3, y, z0), 8, (0, 0, -1))
    bulbs(mb, (-2.45, cy - 0.06, z1), (2.45, cy - 0.06, z1), 12, (0, 0.5, 1))
    for s in (-1, 1):
        bulbs(mb, (s * (cx - 0.06), 0.2, z1), (s * (cx - 0.06), cy - 0.2, z1), 5, (s * 0.5, 0, 1))
        mb.cyl(0.055, z0, (s * 2.42, 2.02, 0.0), G, segs=6, base=True, caps=False)       # poles
        mb.cyl(0.12, 0.1, (s * 2.42, 2.02, 0.0), G, segs=6, base=True)
    fbox(mb, -1.1, 1.1, 0.0, cy, 0.0, 0.025, "fabric_red", skip="-y -z")                 # red carpet
    mb.to_object(r, "mesh")
    lb = K.MB()
    q(lb, -XF, XF, 0.0, wc, "tint_a")
    hband(lb, -XF, XF, wc, wd, [(wins[0][0], wins[0][1], "@Window"), (da, db, "@Window"),
                                (wins[1][0], wins[1][1], "@Window")])
    q(lb, -XF, XF, wd, HF, "tint_a")
    fbox(lb, -cx, cx, 0.0, cy, z0, z1, "maroon", skip="-y")
    B.lod_obj(lb, r)
    return r


# ----------------------------------------------------------------------------- fire station
def _bay_door(mb, a, b, dd, yd=-0.10):
    reveal(mb, a, b, 0.0, dd, "steel_dark", 0.0, yd, sides="lrt")
    q(mb, a, b, 0.0, dd, "red_dark", yd)
    h = dd / 5
    xm = (a + b) / 2
    for i in (0, 1, 2, 4):                                                               # panel sections
        for xa, xb in ((a + 0.04, xm - 0.03), (xm + 0.03, b - 0.04)):
            panel(mb, xa, xb, i * h + 0.03, (i + 1) * h - 0.03, "fire_red", t=0.035, c=0.04, y=yd)
    z0, z1, t = 3 * h + 0.03, 4 * h - 0.03, 0.035                                        # window row
    x0, x1 = a + 0.04, b - 0.04
    fbox(mb, x0, x1, yd, yd + t, z0, z1, "fire_red", skip="-y +y")
    cw = (x1 - x0) / 4
    for k in range(4):
        ca, cb = x0 + k * cw, x0 + (k + 1) * cw
        ha, hb, hc, hd = ca + 0.14, cb - 0.14, z0 + 0.13, z1 - 0.13
        wall(mb, ca, cb, z0, z1, (ha, hb, hc, hd), "fire_red", yd + t)
        reveal(mb, ha, hb, hc, hd, "red_dark", yd + t, yd + 0.008)
        pane(mb, ha, hb, hc, hd, yd + 0.008)
    fbox(mb, xm - 0.25, xm + 0.25, yd + 0.035, yd + 0.075, 0.33, 0.39, "steel_dark")      # lift handle


def front_firestation():
    r = begin("front_firestation", "two bay doors 4.5 x 3.8 (x -5.5..-1.0 and 1.0..5.5); bollards reach Y +0.33")
    mb = K.MB()
    bays = [(-5.5, -1.0), (1.0, 5.5)]
    dd = 3.8
    pa, pb, pd = -0.45, 0.45, 2.1
    mwall(mb, -XF, XF, 0.0, 3.9, [(bays[0][0], bays[0][1], 0.0, dd), (pa - 0.08, pb + 0.08, 0.0, pd + 0.08),
                                  (bays[1][0], bays[1][1], 0.0, dd)])
    for a, b in bays:
        _bay_door(mb, a, b, dd)
    yd = -0.05                                                                           # personnel door
    casing(mb, pa, pb, 0.0, pd, w=0.08, t=0.05, color="steel_dark", bottom=False, y1=yd)
    q(mb, pa, pb, 0.0, pd, "fire_red", yd)
    panel(mb, pa + 0.1, pb - 0.1, 0.25, 1.05, "fire_red", t=0.02, c=0.04, y=yd)
    fbox(mb, pa + 0.2, pb - 0.2, yd, yd + 0.02, 1.3, 1.85, "white")
    pane(mb, pa + 0.25, pb - 0.25, 1.35, 1.8, yd + 0.026)
    fbox(mb, pb - 0.14, pb - 0.08, yd, yd + 0.07, 0.95, 1.15, "chrome")
    wall_lamp(mb, 0.0, 2.52, y=0.0)
    mb.cyl(0.34, 0.05, (0.0, 0.025, 3.3), "gold", axis="Y", segs=10)                     # badge
    mb.cyl(0.24, 0.03, (0.0, 0.06, 3.3), "fire_red", axis="Y", segs=10)
    mb.cyl(0.09, 0.03, (0.0, 0.085, 3.3), "gold", axis="Y", segs=6)
    for xa, xb in ((-XF, -5.5), (-1.0, -0.53), (0.53, 1.0), (5.5, XF)):                  # piers
        plinth(mb, xa, xb)
        fbox(mb, xa, xb, 0.0, 0.03, 3.5, 3.78, "tint_b", skip="-y")
    for x in (-5.76, -0.77, 0.77, 5.76):
        hazard_post(mb, x, 0.24, h=1.0, bands=4)
    q(mb, -XF, XF, 3.9, 4.3, CL)                                                         # lintel band
    cbox(mb, -XF, XF, 0.0, 0.1, 3.84, 3.92, CL, c=0.025)
    cbox(mb, -XF, XF, 0.0, 0.14, 4.3, HF, CL, c=0.04)
    K.add_text(mb, "VBFD ENGINE 7", size=0.46, depth=0.06, color="neon_red", pos=(0, 0.0, 3.95), res=2)
    mb.to_object(r, "mesh")
    lb = K.MB()
    h = dd / 5
    for xa, xb in ((-XF, -5.5), (-1.0, 1.0), (5.5, XF)):
        q(lb, xa, xb, 0.0, dd, "tint_a")
    for a, b in bays:
        q(lb, a, b, 0.0, 3 * h, "fire_red")
        q(lb, a, b, 3 * h, 4 * h, "@Window")
        q(lb, a, b, 4 * h, dd, "fire_red")
    q(lb, -XF, XF, dd, HF, CL)
    B.lod_obj(lb, r)
    return r


# ----------------------------------------------------------------------------- cinema
def front_cinema():
    r = begin("front_cinema", "marquee wedge (plan triangle x +-3.5 at the wall, apex Y +2.5), z 2.9-4.15; "
                              "ASTRA on both wedge faces")
    mb = K.MB()
    ea, eb, ed = -2.2, 2.2, 2.7
    posters = [(-5.45, -4.35), (-3.95, -2.85), (2.85, 3.95), (4.35, 5.45)]
    pc, pd = 0.9, 2.5
    mwall(mb, -XF, XF, 0.0, 4.25, [(ea, eb, 0.0, ed)])
    entrance(mb, ea, eb, 0.0, ed, leaves=4, fc="brass", transom=2.3, rc="charcoal")
    pulls(mb, (-1.2, -0.94, 0.94, 1.2), 0.95, 1.6, color="gold")
    art = [("navy", "neon_pink"), ("maroon", "neon_yellow"), ("blue_dark", "neon_orange"), ("purple", "neon_cyan")]
    for (a, b), (cd, cn) in zip(posters, art):                                           # poster light boxes
        fbox(mb, a, b, 0.0, 0.07, pc, pd, "brass")
        q(mb, a + 0.08, b - 0.08, pc + 0.08, pd - 0.08, "screen_blue", 0.076)
        q(mb, a + 0.08, b - 0.08, pc + 0.08, pc + 0.55, cd, 0.082)
        xm, zm = (a + b) / 2, pd - 0.55
        fq(mb, [(xm + 0.24 * ca, 0.082, zm + 0.24 * sa) for ca, sa in
                ((1, 0), (0.5, 0.866), (-0.5, 0.866), (-1, 0), (-0.5, -0.866), (0.5, -0.866))], cn, (0, 1, 0))
    for s in (-1, 1):
        xa, xb = sorted((s * 2.27, s * XF))
        plinth(mb, xa, xb, 0.45, "tile_dark")
        for x in (s * 2.55, s * 5.8):
            fbox(mb, x - 0.2, x + 0.2, 0.0, 0.06, 0.45, 4.25, "tint_b", skip="-y -z +z")
    cbox(mb, -XF, XF, 0.0, 0.12, 4.25, HF, CL, c=0.04)
    z0, z1 = 2.9, 4.15                                                                   # marquee wedge
    out = mb.prism([(-3.5, 0.0), (3.5, 0.0), (0.0, 2.5)], z1 - z0, "navy", plane="XY", pos=(0, 0, z0), center=False,
                   cap_colors=("maroon", "roof_dark"))
    bmesh.ops.delete(mb.bm, geom=[out["sides"][0]], context="FACES")
    for s in (-1, 1):                                                                    # two wedge faces
        with mb.at((s * 1.75, 1.25, 0.0), rot=(0, 0, -s * 35.538)):
            q(mb, -1.95, 1.95, z0 + 0.09, z0 + 0.52, "white", 0.012)                     # reader board
            for zr, row in ((z0 + 0.33, ((-1.6, -0.95), (-0.8, -0.2), (-0.05, 0.7), (0.85, 1.55))),
                            (z0 + 0.15, ((-1.3, -0.5), (-0.35, 0.3), (0.45, 1.2)))):
                for xa, xb in row:
                    q(mb, xa, xb, zr, zr + 0.1, "black", 0.018)
            K.add_text(mb, "ASTRA", size=0.72, depth=0.06, color="neon_yellow", pos=(0, 0.0, z0 + 0.66), res=2)
            for zz in (z0 + 0.045, z0 + 0.58, z1 - 0.045):
                bulbs(mb, (-2.0, 0.0, zz), (2.0, 0.0, zz), 10, (0, 1, 0))
    bulbs(mb, (-2.2, 0.6, z0), (2.2, 0.6, z0), 8, (0, 0, -1))                            # soffit bulbs
    bulbs(mb, (-1.1, 1.4, z0), (1.1, 1.4, z0), 5, (0, 0, -1))
    mb.to_object(r, "mesh")
    lb = K.MB()
    q(lb, -XF, XF, 0.0, pc, "tint_a")
    hband(lb, -XF, XF, pc, pd, [(a, b, "screen_blue") for a, b in posters] + [(ea, eb, "@Window")])
    q(lb, -XF, XF, pd, HF, "tint_a")
    for s in (-1, 1):
        fq(lb, [(s * 3.5, 0, z0), (0, 2.5, z0), (0, 2.5, z1), (s * 3.5, 0, z1)], "navy", (s, 1, 0))
    fq(lb, [(-3.5, 0, z0), (3.5, 0, z0), (0, 2.5, z0)], "maroon", (0, 0, -1))
    fq(lb, [(-3.5, 0, z1), (3.5, 0, z1), (0, 2.5, z1)], "roof_dark", (0, 0, 1))
    B.lod_obj(lb, r)
    return r


BUILD = (front_police, front_hospital, front_hotel, front_firestation, front_cinema)


def build_all():
    for f in BUILD:
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS, max_tris=1500, max_lod=40))


def qa(ids=None, part="mesh"):
    ids = ids or IDS
    return Q.show("front", [(a, (0.0, 0.0, 5.3 * i)) for i, a in enumerate(ids)], ta="#d8cfc0", tb="#3f6fa8",
                  part=part)
