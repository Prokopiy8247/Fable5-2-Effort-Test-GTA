"""bld_apartment - P1 apartment kit (W 4.0, upper H 3.2, ground H 4.0). See SPEC_BUILDINGS.md."""
import gta_kit as K
import bld_common as B
import bld_parts as P
from bld_common import fq, q, pane, wall, reveal, fbox, cbox, panel, GD

W, HU, HG = 4.0, 3.2, 4.0
X = W / 2
IDS = ["apt_win_a", "apt_win_b", "apt_balcony", "apt_solid", "apt_ground_door", "apt_ground_win", "apt_parapet"]


def course(mb):
    """String course at the floor edge - shared by all upper modules."""
    cbox(mb, -X, X, 0.0, 0.045, 0.0, 0.11, "concrete_light", c=0.02)


def g_bands(mb, x0=-X, x1=X, plinth=True):
    """Ground floor: plinth band 0-0.6 and the cornice band under the first floor."""
    if plinth:
        cbox(mb, x0, x1, 0.0, 0.05, 0.0, 0.6, "concrete_dark", c=0.025, skip=("back", "bottom"))
    else:
        cbox(mb, -X, X, 0.0, 0.09, 3.76, HG, "concrete_light", c=0.03)


def sill(mb, a, b, z, out=0.14, h=0.09, side=0.1):
    cbox(mb, a - side, b + side, 0.0, out, z - h, z, "concrete_light", c=0.025)


def apt_win_a():
    r = B.begin("apt_win_a", W, HU)
    mb = K.MB()
    a, b, c, d = -0.8, 0.8, 0.95, 2.45
    wall(mb, -X, X, 0, HU, (a, b, c, d))
    P.window(mb, a, b, c, d, "white", 0.07, -0.04, vbars=(0.0,), hbars=(1.95,), bw=0.05)
    sill(mb, a, b, c)
    cbox(mb, a - 0.06, b + 0.06, 0.0, 0.05, d, d + 0.1, "concrete_light", c=0.02)
    P.louvre(mb, -1.27, -0.83, c, d, "tint_b", n=7, t=0.055, fw=0.05)
    P.louvre(mb, 0.83, 1.27, c, d, "tint_b", n=7, t=0.055, fw=0.05)
    course(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(a, b, c, d)])
    return r


def apt_win_b():
    r = B.begin("apt_win_b", W, HU)
    mb = K.MB()
    c, d = 0.9, 2.5
    wins = [(-1.3, -0.5), (0.5, 1.3)]
    wall(mb, -X, 0.0, 0, HU, (wins[0][0], wins[0][1], c, d))
    wall(mb, 0.0, X, 0, HU, (wins[1][0], wins[1][1], c, d))
    for a, b in wins:
        P.window(mb, a, b, c, d, "white", 0.065, -0.04, hbars=(1.98,), bw=0.05)
        cbox(mb, a - 0.05, b + 0.05, 0.0, 0.05, d, d + 0.09, "concrete_light", c=0.02)
    sill(mb, wins[1][0], wins[1][1], c)
    a, b = wins[0]                                           # flower box under the left window
    sill(mb, a, b, c, out=0.1)
    fbox(mb, a - 0.06, b + 0.06, 0.0, 0.27, 0.6, 0.8, "terracotta", colors={"+z": "mud"})
    for i, (dx, s) in enumerate(((-0.3, 1.0), (0.0, 1.15), (0.3, 0.95))):
        mb.ico(0.14 * s, (-0.9 + dx, 0.15, 0.86), "@F:leaf_green", subdiv=1, scale=(1.25, 0.8, 0.8),
               jitter=0.12, seed=3 + i)
    for i, (dx, dy, dz) in enumerate(((-0.36, 0.2, 0.96), (-0.15, 0.24, 0.9), (0.05, 0.2, 1.0), (0.24, 0.25, 0.92),
                                       (0.38, 0.18, 0.97))):
        mb.sphere(0.05, (-0.9 + dx, dy, dz), "flower_red", segs=4, rings=2, smooth=False)
    course(mb)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(wins[0][0], wins[1][1], c, d)])
    return r


def apt_balcony():
    r = B.begin("apt_balcony", W, HU)
    mb = K.MB()
    a, b, c, d = -0.7, 0.7, 0.15, 2.35
    wall(mb, -X, X, 0, HU, (a, b, c, d))
    P.window(mb, a, b, c, d, "white", 0.07, -0.04, vbars=(0.0,), bw=0.07, split=True)
    cbox(mb, a - 0.06, b + 0.06, 0.0, 0.05, d, d + 0.1, "concrete_light", c=0.02)
    course(mb)
    cbox(mb, -1.6, 1.6, 0.0, 1.1, 0.0, 0.15, "concrete_light", c=0.035)                 # slab
    S = "steel_dark"
    fbox(mb, -1.58, 1.58, 1.02, 1.08, 1.09, 1.15, S, skip="")                            # top rails
    fbox(mb, -1.52, 1.52, 1.03, 1.07, 0.2, 0.25, S, skip="-x +x")                        # bottom rail
    fbox(mb, -1.5, 1.5, 1.035, 1.065, 0.3, 1.0, "tint_b", skip="-x +x")                  # front panel
    for s in (-1, 1):
        xa, xb = sorted((s * 1.52, s * 1.58))
        fbox(mb, xa, xb, 0.0, 1.02, 1.09, 1.15, S, skip="-y +y")
        fbox(mb, xa, xb, 1.02, 1.08, 0.15, 1.09, S, skip="+z -z")                        # corner post
        for yk in (0.26, 0.52, 0.78):
            xm = s * 1.55
            fbox(mb, xm - 0.014, xm + 0.014, yk - 0.014, yk + 0.014, 0.15, 1.09, S, skip="+z -z")
    mb.cyl(0.15, 0.3, (1.12, 0.62, 0.15), "terracotta", segs=6, r2=0.2, base=True)        # potted plant
    mb.ico(0.3, (1.12, 0.62, 0.68), "@F:leaf_green", subdiv=1, scale=(1.0, 1.0, 1.15), jitter=0.15, seed=7)
    mb.to_object(r, "mesh")
    P.lod(r, W, HU, [(a + 0.07, b - 0.07, c + 0.07, d - 0.07)],
          extra=lambda m: q(m, -1.58, 1.58, 0.0, 1.15, "tint_b", 1.08))
    return r


def apt_solid():
    r = B.begin("apt_solid", W, HU)
    mb = K.MB()
    wall(mb, -X, X, 0, HU)
    course(mb)
    px, py = 1.25, 0.1
    mb.cyl(0.055, HU, (px, py, 0.0), "steel_dark", segs=6, base=True)                     # downpipe
    for z in (0.55, 2.25):
        mb.cyl(0.075, 0.09, (px, py, z), "steel_dark", segs=6)
        fbox(mb, px - 0.035, px + 0.035, 0.0, py, z - 0.03, z + 0.03, "steel_dark", skip="-y +y")
    mb.to_object(r, "mesh")
    P.lod(r, W, HU)
    return r


def apt_ground_door():
    r = B.begin("apt_ground_door", W, HG)
    mb = K.MB()
    a, b, c, d = -0.6, 0.6, 0.32, 2.52
    dy = -0.10
    wall(mb, -X, X, 0, HG, (a, b, c, d))
    reveal(mb, a, b, c, d, "tint_a", 0.0, -0.03, sides="lrt")
    reveal(mb, a, b, c, d, "concrete_light", 0.0, dy, sides="b")
    ia, ib, _ic, id_ = P.frame(mb, a, b, c, d, 0.08, "white", -0.03, dy, bottom=False)
    q(mb, ia, ib, c, id_, "wood_dark", dy)                                               # door leaf
    panel(mb, ia + 0.1, ib - 0.1, c + 0.14, 1.3, "wood_dark", t=0.025, c=0.05, y=dy)
    wall(mb, ia + 0.1, ib - 0.1, 1.5, id_ - 0.12, (ia + 0.17, ib - 0.17, 1.57, id_ - 0.19), "wood_dark", dy + 0.02)
    pane(mb, ia + 0.1, ib - 0.1, 1.5, id_ - 0.12, dy + 0.008)
    fbox(mb, ib - 0.12, ib - 0.06, dy, dy + 0.06, 1.33, 1.41, "brass")
    cbox(mb, -0.95, 0.95, 0.0, 0.6, 0.0, 0.16, "concrete", c=0.025, skip=("back", "bottom"))       # 2 steps
    cbox(mb, -0.95, 0.95, 0.0, 0.3, 0.16, 0.32, "concrete_light", c=0.025, skip=("back", "bottom"))
    mb.prism([(-1.0, 2.72), (0.0, 3.14), (1.0, 2.72), (1.0, 2.62), (0.0, 3.02), (-1.0, 2.62)], 0.95, "tint_b",
             plane="XZ", center=False, caps=(False, True))                               # pitched canopy
    for s in (-1, 1):
        mb.prism([(0.0, 2.2), (0.75, 2.66), (0.0, 2.66)], 0.06, "white", plane="YZ", pos=(s * 0.82, 0, 0))
        xa, xb = sorted((s * 0.95, s * X))
        g_bands(mb, xa, xb)
    fbox(mb, 0.78, 0.94, 0.0, 0.035, 1.3, 1.56, "steel")                                 # intercom
    q(mb, 0.81, 0.91, 1.43, 1.53, "charcoal", 0.041)
    q(mb, 0.84, 0.88, 1.34, 1.38, "emis_lamp", 0.041)
    fbox(mb, -0.93, -0.79, 0.0, 0.03, 1.84, 2.16, "steel_dark")                          # wall lamp
    fbox(mb, -0.935, -0.785, 0.03, 0.17, 1.9, 2.1, "emis_lamp", skip="-y +z")
    cbox(mb, -0.96, -0.76, 0.02, 0.2, 2.1, 2.15, "steel_dark", c=0.015)
    g_bands(mb, plinth=False)
    mb.to_object(r, "mesh")
    lb = K.MB()
    wall(lb, -X, X, 0, HG, (a, b, c, d))
    q(lb, a, b, c, d, "wood_dark")
    B.lod_obj(lb, r)
    return r


def apt_ground_win():
    r = B.begin("apt_ground_win", W, HG)
    mb = K.MB()
    a, b, c, d = -0.8, 0.8, 1.2, 2.8
    wall(mb, -X, X, 0, HG, (a, b, c, d))
    P.window(mb, a, b, c, d, "white", 0.07, -0.04, vbars=(0.0,), hbars=(2.3,), bw=0.05)
    sill(mb, a, b, c)
    cbox(mb, a - 0.06, b + 0.06, 0.0, 0.05, d, d + 0.1, "concrete_light", c=0.02)
    S = "steel_dark"                                                                     # security grille
    for z in (1.34, 2.66):
        fbox(mb, a - 0.07, b + 0.07, 0.0, 0.07, z - 0.022, z + 0.022, S)
    for i in range(6):
        x = a + 0.14 + i * (b - a - 0.28) / 5
        fbox(mb, x - 0.016, x + 0.016, 0.03, 0.062, 1.26, 2.74, S, skip="-y")
    g_bands(mb)
    g_bands(mb, plinth=False)
    mb.to_object(r, "mesh")
    P.lod(r, W, HG, [(a, b, c, d)])
    return r


def apt_parapet():
    r = B.begin("apt_parapet", W, 0.8, notes="stepped cornice has 45deg mitre wedges reaching 0.15 past x=+-W/2 "
                                               "(hidden inside neighbours, closes box corners)")
    mb = K.MB()
    H = 0.8
    q(mb, -X, X, 0, 0.3, "tint_a")
    fq(mb, [(-X, -0.25, 0), (X, -0.25, 0), (X, -0.25, H), (-X, -0.25, H)], "concrete", (0, -1, 0))
    prof = [(0.0, 0.3), (0.05, 0.3), (0.05, 0.45), (0.10, 0.45), (0.10, 0.6), (0.15, 0.6), (0.15, H)]
    cols = ["tint_b", "tint_b", "concrete_light", "concrete_light", "concrete_light", "concrete_light"]
    for i in range(len(prof) - 1):
        (y0, z0), (y1, z1) = prof[i], prof[i + 1]
        n = (0, 0, -1) if abs(z0 - z1) < 1e-6 else (0, 1, 0)
        fq(mb, [(-X - y0, y0, z0), (X + y0, y0, z0), (X + y1, y1, z1), (-X - y1, y1, z1)], cols[i], n)
    fq(mb, [(-X, -0.25, H), (X, -0.25, H), (X, 0, H), (X + 0.15, 0.15, H), (-X - 0.15, 0.15, H), (-X, 0, H)],
       "concrete_light", (0, 0, 1))
    mb.to_object(r, "mesh")
    lb = K.MB()
    q(lb, -X, X, 0, 0.3, "tint_a")
    fq(lb, [(-X, -0.25, 0), (X, -0.25, 0), (X, -0.25, H), (-X, -0.25, H)], "concrete", (0, -1, 0))
    fbox(lb, -X, X, -0.25, 0.12, 0.3, H, "concrete_light", skip="-x +x -y")
    B.lod_obj(lb, r)
    return r


BUILD = {f.__name__: f for f in (apt_win_a, apt_win_b, apt_balcony, apt_solid, apt_ground_door, apt_ground_win,
                                 apt_parapet)}


def build_all():
    for f in BUILD.values():
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS))
