"""bld_billboards - P3 billboards (single part `mesh`, glb buildings/<id>). See SPEC_BUILDINGS.md.

billboard_a/b/c: panel 10 x 4.5, bottom at z 9, faces +Y, catwalk + 3 lamps; origin on the ground under the panel
centre (pole axis plane Y = 0). roof_billboard_a/b: panel 8 x 4 on a low steel truss; origin base centre.
All ads are fictional.
"""
import math
import gta_kit as K
import bld_common as B
import bld_qa as Q
from bld_common import fq, q, fbox
from bld_signs import text_w

IDS = ["billboard_a", "billboard_b", "billboard_c", "roof_billboard_a", "roof_billboard_b"]
S, SD = "steel", "steel_dark"


class Art:
    """Flat ad artwork in screen coordinates: u = left -> right as read from +Y, v = up from the panel bottom.
    Layers k are stacked 6 mm apart in front of the panel face."""

    def __init__(self, mb, y, z0):
        self.mb, self.y, self.z0 = mb, y, z0

    def L(self, k):
        return self.y + 0.006 * k

    def rect(self, u0, u1, v0, v1, col, k=1):
        q(self.mb, -u1, -u0, self.z0 + v0, self.z0 + v1, col, self.L(k))

    def poly(self, pts, col, k=2):
        fq(self.mb, [(-u, self.L(k), self.z0 + v) for u, v in pts], col, (0, 1, 0))

    def disc(self, u, v, r, col, k=2, n=14, a0=0.0, a1=360.0, sv=1.0):
        m = n if abs(a1 - a0) >= 359.9 else n + 1
        self.poly([(u + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
                    v + sv * r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(m)], col, k)

    def ring(self, u, v, r0, r1, col, k=2, n=14, a0=0.0, a1=360.0, sv=1.0):
        for i in range(n):
            t0, t1 = (math.radians(a0 + (a1 - a0) * j / n) for j in (i, i + 1))
            self.poly([(u + r0 * math.cos(t0), v + sv * r0 * math.sin(t0)),
                       (u + r1 * math.cos(t0), v + sv * r1 * math.sin(t0)),
                       (u + r1 * math.cos(t1), v + sv * r1 * math.sin(t1)),
                       (u + r0 * math.cos(t1), v + sv * r0 * math.sin(t1))], col, k)

    def star(self, u, v, s, col, k=2):
        t = s * 0.3
        self.poly([(u, v + s), (u + t, v + t), (u + s, v), (u + t, v - t), (u, v - s), (u - t, v - t), (u - s, v),
                   (u - t, v + t)], col, k)

    def text(self, s, u, v, size, col, maxw=None, depth=0.08, res=2, k=1):
        if maxw:
            size = min(size, maxw / text_w(s))
        K.add_text(self.mb, s, size=size, depth=depth, color=col, pos=(-u, self.L(k), self.z0 + v), res=res)
        return size


# ----------------------------------------------------------------------------- structure
def panel(mb, w, h, z0, yb, t=0.3):
    """Sign box (steel_dark frame + plain back) with 3 back stringers. -> front plane Y."""
    fbox(mb, -w / 2, w / 2, yb, yb + t, z0, z0 + h, SD, skip="")
    for f in (0.15, 0.5, 0.85):
        z = z0 + h * f
        fbox(mb, -w / 2 + 0.15, w / 2 - 0.15, yb - 0.1, yb, z - 0.08, z + 0.08, S, skip="+y")
    return yb + t


def lamp(mb, x, y, z, reach=0.9):
    """Flood lamp on an arm, aimed back/up at the panel."""
    mb.tube([(x, y, z), (x, y + reach, z - 0.12)], 0.03, SD, segs=4, caps=False)
    mb.box((0.55, 0.22, 0.16), (x, y + reach + 0.05, z - 0.08), SD, rot=(-35, 0, 0), colors={"-y": "emis_lamp"})


def catwalk(mb, w, yf, z0, d=0.8, drop=0.9):
    zc = z0 - drop                                           # deck top
    fbox(mb, -w / 2, w / 2, yf - 0.3, yf + d, zc - 0.08, zc, SD, skip="")
    yr = yf + d - 0.03
    for zr in (zc + 0.5, zc + 0.95):
        fbox(mb, -w / 2, w / 2, yr - 0.025, yr + 0.025, zr - 0.025, zr + 0.025, S, skip="-x +x")
    n = 5
    for i in range(n):
        x = -w / 2 + 0.04 + (w - 0.08) * i / (n - 1)
        fbox(mb, x - 0.025, x + 0.025, yr - 0.025, yr + 0.025, zc, zc + 0.95, S, skip="-z +z")
        fbox(mb, x - 0.03, x + 0.03, yf - 0.2, yf - 0.14, zc, z0, SD, skip="-z +z")                # hangers
    return zc


def street(mb, poles, z0=9.0, w=10.0, h=4.5, torque=False, brace=False):
    yb = 0.42
    yf = panel(mb, w, h, z0, yb)
    for x, rad in poles:
        mb.cyl(rad, z0 + h - 0.7, (x, 0, 0), S, segs=10, base=True)
        mb.box((rad * 3.6, rad * 3.6, 0.3), (x, 0, 0), "concrete", base=True, bevel=0.04)
        for zz in (z0 + 0.5, z0 + h - 1.3):
            fbox(mb, x - rad * 0.8, x + rad * 0.8, 0.0, yb - 0.1, zz - 0.2, zz + 0.2, SD, skip="-y +y")
    if torque:
        mb.cyl(0.32, w - 0.6, (0, 0.02, z0 + h * 0.5), S, axis="X", segs=8)
    if brace and len(poles) == 2:
        (xa, _r), (xb, _r2) = poles
        mb.tube([(xa, 0, 3.0), (xb, 0, 7.6)], 0.07, SD, segs=4, caps=False)
        mb.tube([(xb, 0, 3.0), (xa, 0, 7.6)], 0.07, SD, segs=4, caps=False)
    zc = catwalk(mb, w, yf, z0)
    for x in (-3.3, 0.0, 3.3):
        lamp(mb, x, yf + 0.8, zc - 0.04)
    return Art(mb, yf, z0)


def rooftop(mb, w=8.0, h=4.0, z0=1.0):
    yf = panel(mb, w, h, z0, 0.0, t=0.2)
    xs = (-w / 2 + 0.7, 0.0, w / 2 - 0.7)
    for x in xs:
        fbox(mb, x - 0.09, x + 0.09, -2.0, 0.9, 0.0, 0.16, SD, skip="-z")                         # skid
        fbox(mb, x - 0.07, x + 0.07, -0.24, -0.1, 0.16, z0 + h - 0.3, SD, skip="-z +z")           # upright
        mb.tube([(x, -1.9, 0.16), (x, -0.2, z0 + h * 0.72)], 0.05, SD, segs=4, caps=False)         # back stays
        if x != 0.0:                                                                              # outer frames only
            mb.tube([(x, -1.0, 0.16), (x, -0.2, z0 + h * 0.25)], 0.04, SD, segs=4, caps=False)
            mb.tube([(x, 0.85, 0.16), (x, 0.1, z0 + 0.02)], 0.04, SD, segs=4, caps=False)          # front strut
    for a, b in ((xs[0], xs[1]), (xs[2], xs[1])):                                                 # V bracing
        mb.tube([(a, -0.17, 0.2), (b, -0.17, z0 - 0.02)], 0.03, SD, segs=4, caps=False)
    fbox(mb, -w / 2 + 0.3, w / 2 - 0.3, -1.98, -1.84, 0.16, 0.28, SD, skip="-z")                   # rear tie beam
    for x in (-2.6, 0.0, 2.6):
        lamp(mb, x, yf, z0 + 0.06, reach=1.0)
    return Art(mb, yf, z0)


def _begin(aid, notes):
    return B.begin(aid, notes=notes, spacing=14.0)


# ----------------------------------------------------------------------------- the ads
def billboard_a():
    r = _begin("billboard_a", "monopole billboard, fictional ad 'ZAP! SODA'; panel 10 x 4.5 with bottom at z 9, "
                              "faces +Y (front plane Y +0.72), catwalk + 3 lamps reach Y +2.6")
    mb = K.MB()
    A = street(mb, [(0.0, 0.42)])
    A.rect(-4.85, 4.85, 0.15, 4.35, "blue")
    A.disc(-3.05, 2.25, 1.8, "cyan", k=2, n=16)
    A.poly([(-3.5, 4.2), (-2.1, 4.2), (-2.85, 2.65), (-1.95, 2.65), (-3.9, 0.3), (-3.3, 2.05), (-4.2, 2.05)],
           "yellow", k=3)
    for u, v, rr in ((4.2, 3.8, 0.32), (4.5, 3.0, 0.2), (-0.75, 0.6, 0.22), (4.35, 0.75, 0.28), (-0.9, 3.9, 0.16)):
        A.disc(u, v, rr, "sky_blue", k=2, n=8)
    A.rect(-0.9, 3.9, 1.97, 2.09, "white", k=2)
    A.text("ZAP!", 1.5, 2.35, 2.3, "yellow", maxw=5.0)
    A.text("SODA", 1.5, 0.5, 1.75, "white", maxw=4.6)
    mb.to_object(r, "mesh")
    return r


def billboard_b():
    r = _begin("billboard_b", "twin-pole billboard, fictional ad 'ORBIT GUM'; panel 10 x 4.5 with bottom at z 9, "
                              "faces +Y, catwalk + 3 lamps")
    mb = K.MB()
    A = street(mb, [(-3.0, 0.28), (3.0, 0.28)], brace=True)
    A.rect(-4.85, 4.85, 0.15, 4.35, "navy")
    A.disc(3.0, 2.3, 1.3, "magenta", k=2, n=16)
    A.disc(2.65, 2.75, 0.5, "pink", k=3, n=10)
    A.ring(3.0, 2.3, 1.72, 1.98, "lime", k=4, n=14, sv=0.3)
    A.disc(4.72, 2.62, 0.12, "white", k=5, n=6)
    for u, v, s in ((-4.4, 3.85, 0.17), (-0.2, 4.0, 0.12), (1.0, 0.55, 0.14), (4.5, 0.6, 0.11), (4.4, 3.95, 0.13)):
        A.star(u, v, s, "white")
    A.text("ORBIT", -1.75, 2.35, 1.9, "white", maxw=5.3)
    A.text("GUM", -1.75, 0.5, 1.9, "lime", maxw=4.0)
    mb.to_object(r, "mesh")
    return r


def billboard_c():
    r = _begin("billboard_c", "offset-pole (cantilever) billboard, fictional ad 'SUNSET RADIO 99.1'; panel 10 x 4.5 "
                              "with bottom at z 9, faces +Y; pole at x +3.3")
    mb = K.MB()
    A = street(mb, [(3.3, 0.45)], torque=True)
    A.rect(-4.85, 4.85, 0.15, 1.55, "purple")
    A.rect(-4.85, 4.85, 1.55, 2.95, "magenta")
    A.rect(-4.85, 4.85, 2.95, 4.35, "orange")
    A.disc(-2.9, 0.15, 1.9, "yellow", k=2, n=14, a0=0.0, a1=180.0)
    for v0, v1 in ((0.52, 0.66), (0.96, 1.07), (1.36, 1.43)):
        A.rect(-4.82, -0.98, v0, v1, "purple", k=3)
    for r0 in (2.2, 2.58):
        A.ring(-2.9, 0.15, r0, r0 + 0.1, "white", k=2, n=8, a0=25.0, a1=135.0)
    A.text("SUNSET RADIO", 1.95, 3.32, 1.0, "white", maxw=5.5, res=1)
    A.text("99.1", 2.0, 0.85, 2.6, "yellow", maxw=4.9)
    mb.to_object(r, "mesh")
    return r


def roof_billboard_a():
    r = _begin("roof_billboard_a", "rooftop billboard 8 x 4 on a low steel truss (panel bottom z 1.0, total 5.0 high), "
                                   "fictional ad 'FLY VESPER AIR'; faces +Y, stays reach Y -2.0, lamps Y +1.5")
    mb = K.MB()
    A = rooftop(mb)
    A.rect(-3.85, 3.85, 0.15, 3.85, "sky_blue")
    for u, v, rr in ((-3.0, 0.72, 0.56), (-2.25, 0.6, 0.42), (-3.45, 0.5, 0.34), (3.05, 3.3, 0.36), (3.5, 3.18, 0.26),
                     (2.65, 3.2, 0.24)):
        A.disc(u, v, rr, "white", k=2, n=10)
    A.poly([(-3.3, 1.5), (1.25, 2.72), (1.2, 2.88), (-3.3, 1.64)], "white", k=2)          # contrail
    A.poly([(1.1, 2.5), (3.45, 3.0), (2.45, 1.95)], "white", k=3)                          # paper plane
    A.poly([(2.45, 1.95), (3.45, 3.0), (2.7, 2.5)], "gray_light", k=4)
    A.text("FLY", -2.55, 2.6, 1.45, "navy", maxw=2.3)
    A.text("VESPER AIR", 0.95, 0.42, 1.2, "navy", maxw=5.5)
    mb.to_object(r, "mesh")
    return r


def roof_billboard_b():
    r = _begin("roof_billboard_b", "rooftop billboard 8 x 4 on a low steel truss (panel bottom z 1.0, total 5.0 high), "
                                   "fictional ad 'BIG WAVE SURF SHOP'; faces +Y")
    mb = K.MB()
    A = rooftop(mb)
    A.rect(-3.85, 3.85, 0.15, 3.85, "turquoise")
    A.disc(2.95, 3.0, 0.62, "yellow", k=2, n=10)
    A.poly([(-3.85, 0.15), (3.85, 0.15), (3.85, 0.95), (2.3, 1.05), (1.4, 1.6), (1.0, 2.4), (1.45, 3.05),
            (0.55, 2.95), (-0.3, 2.3), (-1.2, 1.55), (-2.6, 1.15), (-3.85, 1.05)], "blue", k=3)
    A.poly([(1.0, 2.4), (1.45, 3.05), (0.55, 2.95), (0.25, 2.62)], "foam_white", k=4)
    A.text("BIG WAVE", -1.9, 2.8, 1.1, "white", maxw=3.6, res=1)
    A.text("SURF SHOP", 0.0, 0.3, 1.1, "white", maxw=5.6, k=3)
    mb.to_object(r, "mesh")
    return r


BUILD = (billboard_a, billboard_b, billboard_c, roof_billboard_a, roof_billboard_b)


def build_all():
    for f in BUILD:
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS, max_tris=900))


def qa():
    return Q.show("bb", [("billboard_a", (11.0, 0, 0)), ("billboard_b", (0, 0, 0)), ("billboard_c", (-11.0, 0, 0)),
                         ("roof_billboard_a", (5.5, 0, 14.5)), ("roof_billboard_b", (-5.5, 0, 14.5))])
