"""bld_office - P1 office kit (W 4.0, upper H 3.5, ground H 4.5). See SPEC_BUILDINGS.md."""
import gta_kit as K
import bld_common as B
import bld_parts as P
from bld_common import q, pane, wall, reveal, fbox, cbox, panel, GD

W, HU, HG = 4.0, 3.5, 4.5
X = W / 2
IDS = ["off_win_a", "off_win_b", "off_win_c", "off_solid", "off_ground_glass", "off_ground_door",
       "off_ground_solid", "off_parapet"]


def floorline(mb, c="tint_b"):
    """Thin accent line at the floor edge (shared by all upper modules + parapet so it runs continuously)."""
    cbox(mb, -X, X, 0.0, 0.05, 0.0, 0.12, c, c=0.02)


def g_header(mb):
    """Ground-floor header: tint_b band z 3.6-4.5 with a 0.3 deep canopy lip."""
    q(mb, -X, X, 3.6, HG, "tint_b")
    cbox(mb, -X, X, 0.0, 0.30, 3.6, 3.76, "steel_dark", c=0.04)
    cbox(mb, -X, X, 0.0, 0.04, 4.36, HG, "concrete_light", c=0.015)


def plinth(mb, x0=-X, x1=X, h=0.5):
    cbox(mb, x0, x1, 0.0, 0.06, 0.0, h, "concrete_dark", c=0.03, skip=("back", "bottom"))


def off_win_a():
    r = B.begin("off_win_a", W, HU)
    mb = K.MB()
    a, b, c, d = -1.85, 1.85, 0.55, 3.2
    wall(mb, -X, X, 0, HU, (a, b, c, d))
    reveal(mb, a, b, c, d, "tint_a", 0.0, -0.03)
    ia, ib, ic, id_ = P.frame(mb, a, b, c, d, 0.06, "steel_dark", -0.03)
    pw = (ib - ia - 0.16) / 3
    for i in (1, 2):                                   # projecting mullion fins
        xm = ia + i * pw + (i - 0.5) * 0.08
        fbox(mb, xm - 0.04, xm + 0.04, GD, 0.07, c, d, "steel_dark")
    for i in range(3):
        x0 = ia + i * (pw + 0.08)
        pane(mb, x0, x0 + pw, ic, id_)
    panel(mb, a, b, 0.17, 0.5, "tint_a", t=0.035, c=0.04)          # raised spandrel panel
    cbox(mb, a - 0.05, b + 0.05, 0.0, 0.07, 3.2, 3.29, "concrete_light", c=0.025)   # head ledge
    floorline(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(a, b, c, d)])
    return r


def off_win_b():
    r = B.begin("off_win_b", W, HU)
    mb = K.MB()
    a, b, c, d = -1.2, 1.2, 0.9, 2.8
    wall(mb, -X, X, 0, HU, (a, b, c, d))
    P.window(mb, a, b, c, d, "charcoal", 0.08, -0.05, vbars=(0.0,), bw=0.07, split=True)
    cbox(mb, a - 0.14, b + 0.14, 0.0, 0.15, c - 0.11, c, "concrete_light", c=0.03)   # projecting sill
    cbox(mb, a - 0.08, b + 0.08, 0.0, 0.06, d, d + 0.13, "concrete_light", c=0.02)   # lintel
    for s in (-1, 1):                                  # shallow side panels
        xa, xb = sorted((s * 1.42, s * 1.94))
        panel(mb, xa, xb, 0.9, 2.8, "tint_a", t=0.025, c=0.035)
    floorline(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(a, b, c, d)])
    return r


def off_win_c():
    r = B.begin("off_win_c", W, HU)
    mb = K.MB()
    c, d = 1.0, 2.7
    q(mb, -X, X, 0, c, "tint_b")
    q(mb, -X, X, d, HU, "tint_b")
    reveal(mb, -X, X, c, d, "steel_dark", 0.0, GD, sides="tb")
    cbox(mb, -X, X, 0.0, 0.11, c - 0.09, c, "concrete_light", c=0.03)
    cbox(mb, -X, X, 0.0, 0.11, d, d + 0.09, "concrete_light", c=0.03)
    fbox(mb, -0.035, 0.035, GD, -0.02, c, d, "steel_dark", skip="-y +z -z")
    fbox(mb, -X, -X + 0.04, GD, 0.0, c, d, "steel_dark", skip="-y +z -z")     # half posts at the module
    fbox(mb, X - 0.04, X, GD, 0.0, c, d, "steel_dark", skip="-y +z -z")       # edges (close the ribbon ends)
    pane(mb, -X + 0.04, -0.035, c, d)
    pane(mb, 0.035, X - 0.04, c, d)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(-X, X, c, d)], wallc="tint_b")
    return r


def off_solid():
    r = B.begin("off_solid", W, HU)
    mb = K.MB()
    wall(mb, -X, X, 0, HU)
    for (xa, xb) in ((-X + 0.03, -0.03), (0.03, X - 0.03)):
        panel(mb, xa, xb, 0.17, 1.78, "tint_a")
        panel(mb, xa, xb, 1.84, HU - 0.03, "tint_a")
    floorline(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU)
    return r


def off_ground_glass():
    r = B.begin("off_ground_glass", W, HG)
    mb = K.MB()
    a, b, c, d = -1.85, 1.85, 0.5, 3.6
    wall(mb, -X, X, 0, 3.6, (a, b, c, d))
    P.window(mb, a, b, c, d, "steel_dark", 0.06, -0.04, vbars=(-0.6, 0.6), hbars=(2.9,), bw=0.06, split=True)
    plinth(mb)
    g_header(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HG, [(a, b, c, d)], bands=[(3.6, HG, "tint_b")])
    return r


def off_ground_door():
    r = B.begin("off_ground_door", W, HG)
    mb = K.MB()
    a, b, d = -1.7, 1.7, 2.6
    fy = -0.06
    wall(mb, -X, X, 0, 3.6, (a, b, 0.0, d))
    reveal(mb, a, b, 0.0, d, "steel_dark", 0.0, fy, sides="lrt")
    ia, ib, _ic, id_ = P.frame(mb, a, b, 0.0, d, 0.07, "steel", fy, bottom=False)
    zk = 0.45                                                         # kick rail top = glass bottom
    fbox(mb, ia, ib, GD, fy, 0.0, zk, "steel", skip="-y -z -x +x")
    for x in (-1.0, 1.0):
        P.vbar(mb, x, zk, id_, 0.07, "steel", fy)
    P.vbar(mb, 0.0, zk, id_, 0.10, "steel", fy)
    q(mb, -0.008, 0.008, 0.0, id_, "charcoal", fy + 0.004)            # leaf gap
    for (xa, xb) in ((ia, -1.035), (-0.965, -0.05), (0.05, 0.965), (1.035, ib)):
        pane(mb, xa, xb, zk, id_)
    for s in (-1, 1):                                                 # pull handles
        xa, xb = sorted((s * 0.10, s * 0.14))
        fbox(mb, xa, xb, fy, fy + 0.07, 0.95, 1.5, "chrome")
    fbox(mb, a, b, 0.0, 0.14, 0.0, 0.05, "concrete_light", skip="-y -z")   # threshold
    plinth(mb, -X, a)
    plinth(mb, b, X)
    cbox(mb, -1.9, 1.9, 0.0, 1.2, 3.0, 3.18, "steel_dark", c=0.05)    # canopy slab
    for s in (-1, 1):
        mb.tube([(s * 1.6, 1.0, 3.16), (s * 1.6, 0.0, 3.56)], 0.022, "steel", segs=4, caps=False)
        fbox(mb, s * 0.95 - 0.16, s * 0.95 + 0.16, 0.42, 0.74, 2.97, 3.0, "emis_lamp", skip="+z")
    g_header(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HG, [(ia, ib, zk, id_)], bands=[(3.6, HG, "tint_b")])
    return r


def off_ground_solid():
    r = B.begin("off_ground_solid", W, HG)
    mb = K.MB()
    wall(mb, -X, X, 0, 3.6)
    for (xa, xb) in ((-X + 0.03, -0.03), (0.03, X - 0.03)):
        panel(mb, xa, xb, 0.56, 3.54, "tint_a")
        xm = (xa + xb) / 2
        P.louvre(mb, xm - 0.55, xm + 0.55, 0.95, 1.6, "steel", "steel_dark", n=5, t=0.06, fw=0.06, y=0.03)
    fbox(mb, -0.11, 0.11, 0.0, 0.045, 2.5, 2.95, "steel_dark")       # wall lamp: backplate, shade, lens
    cbox(mb, -0.17, 0.17, 0.045, 0.26, 2.84, 2.92, "steel_dark", c=0.02)
    fbox(mb, -0.10, 0.10, 0.045, 0.19, 2.62, 2.84, "emis_lamp", skip="-y +z")
    plinth(mb)
    g_header(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HG, bands=[(3.6, HG, "tint_b")])
    return r


def off_parapet():
    r = B.begin("off_parapet", W, 1.0)
    mb = K.MB()
    q(mb, -X, X, 0, 0.88, "tint_a")
    B.fq(mb, [(-X, -0.25, 0), (X, -0.25, 0), (X, -0.25, 0.88), (-X, -0.25, 0.88)], "concrete", (0, -1, 0))
    mb.prism([(-0.30, 0.88), (0.05, 0.88), (0.05, 0.97), (0.02, 1.0), (-0.27, 1.0), (-0.30, 0.97)], W,
             "concrete_light", plane="YZ")
    floorline(mb)
    mb.to_object(r, "mesh")
    lb = K.MB()
    fbox(lb, -X, X, -0.25, 0.0, 0.0, 0.88, "tint_a", skip="-x +x -z +z", colors={"-y": "concrete"})
    fbox(lb, -X, X, -0.30, 0.05, 0.88, 1.0, "concrete_light", skip="-x +x -z")
    B.lod_obj(lb, r)
    return r


BUILD = {f.__name__: f for f in (off_win_a, off_win_b, off_win_c, off_solid, off_ground_glass,
                                 off_ground_door, off_ground_solid, off_parapet)}


def build_all():
    for f in BUILD.values():
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS))
