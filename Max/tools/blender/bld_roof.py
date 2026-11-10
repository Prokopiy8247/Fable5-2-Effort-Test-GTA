"""bld_roof - P2 roof props (single part `mesh`, origin base centre, glb buildings/roof/<id>). See SPEC_BUILDINGS.md."""
import math
import gta_kit as K
import bld_common as B
import bld_parts as P
import bld_qa as Q
from bld_common import fq, q, wall, reveal, fbox, cbox, panel
from bld_house import casing, wall_lamp

IDS = ["roof_ac", "roof_vent", "roof_duct", "roof_tank", "roof_antenna", "roof_stairhut", "roof_skylight",
       "roof_helipad"]


def begin(aid, notes="", spacing=6.0):
    return B.begin(aid, glb="buildings/roof/" + aid, notes=notes, spacing=spacing)


def roof_ac():
    r = begin("roof_ac")
    mb = K.MB()
    for y in (-0.34, 0.34):
        mb.box((1.4, 0.12, 0.1), (0, y, 0), "steel_dark", base=True)                    # skids
    mb.box((1.5, 0.96, 0.88), (0, 0, 0.1), "gray_light", base=True, bevel=0.03)         # cabinet
    P.louvre(mb, -0.66, 0.66, 0.2, 0.9, "steel_dark", "gray_mid", n=7, t=0.025, fw=0.05, y=0.48)
    with mb.at(rot=(0, 0, 180)):
        P.louvre(mb, -0.66, 0.66, 0.2, 0.9, "steel_dark", "gray_mid", n=7, t=0.025, fw=0.05, y=0.48)
    for x in (-0.38, 0.38):                                                             # top fans
        mb.cyl(0.32, 0.08, (x, 0, 0.98), "steel_dark", segs=10, base=True, cap_color="black")
        mb.cyl(0.09, 0.03, (x, 0, 1.06), "gray_mid", segs=6, base=True)
        for a in (45, -45):
            mb.box((0.62, 0.035, 0.016), (x, 0, 1.068), "gray_mid", rot=(0, 0, a))
    mb.box((0.05, 0.3, 0.4), (0.775, -0.18, 0.55), "gray_dark")                         # control box
    mb.box((0.012, 0.1, 0.06), (0.806, -0.18, 0.62), "hazard_yellow")
    for y in (0.16, 0.24):                                                              # refrigerant lines
        mb.tube([(-0.74, y, 0.42), (-0.78, y, 0.42), (-0.78, y, 0.0)], 0.018, "copper", segs=4, caps=False)
    mb.to_object(r, "mesh")
    return r


def roof_vent():
    r = begin("roof_vent", spacing=4.0)
    mb = K.MB()
    mb.box((0.5, 0.5, 0.03), (0, 0, 0), "steel_dark", base=True)                        # flashing plate
    mb.cyl(0.2, 0.06, (0, 0, 0.03), "steel_dark", segs=10, r2=0.125, base=True, caps=False)
    mb.cyl(0.12, 0.4, (0, 0, 0.03), "steel", segs=10, base=True, caps=False)            # stack
    mb.cyl(0.25, 0.05, (0, 0, 0.4), "steel", segs=10, base=True)                        # cap skirt
    mb.cyl(0.25, 0.12, (0, 0, 0.45), "steel", segs=10, r2=0.07, base=True)              # cap cone
    mb.cyl(0.05, 0.035, (0, 0, 0.57), "steel_dark", segs=6, base=True)
    mb.to_object(r, "mesh")
    return r


def roof_duct():
    r = begin("roof_duct", notes="L-shaped in plan: 2.25 m run along X + 1.25 m branch toward +Y (outlet louvre)")
    mb = K.MB()
    A, S = "aluminum", "steel_dark"
    with mb.at((0.365, -0.59, 0.0)):
        mb.box((2.25, 0.5, 0.4), (-0.375, 0, 0.45), A, bevel=0.02)                      # leg A: x -1.5..0.75
        mb.box((0.5, 1.25, 0.4), (0.5, 0.875, 0.45), A, bevel=0.02)                     # leg B: y 0.25..1.5
        mb.box((0.5, 0.5, 0.3), (-1.25, 0, 0.0), A, base=True)                          # riser into the roof
        mb.box((0.66, 0.66, 0.1), (-1.25, 0, 0.0), "gray_dark", base=True)              # curb
        for x in (-0.85, -0.1):                                                         # flanges
            mb.box((0.04, 0.58, 0.48), (x, 0, 0.45), S)
        mb.box((0.58, 0.04, 0.48), (0.5, 0.75, 0.45), S)
        for (x, y, sx, sy) in ((-0.45, 0, 0.2, 0.7), (0.5, 0, 0.2, 0.7), (0.5, 1.15, 0.7, 0.2)):
            mb.box((sx, sy, 0.25), (x, y, 0), "concrete", base=True)                    # sleepers
        P.louvre(mb, 0.3, 0.7, 0.29, 0.61, S, S, n=4, t=0.03, fw=0.04, y=1.5)           # outlet
    mb.to_object(r, "mesh")
    return r


def roof_tank():
    r = begin("roof_tank", notes="wooden water tank on a steel frame; ladder on the +Y side")
    mb = K.MB()
    S = "steel_dark"
    R, zb, zt, L = 1.12, 0.95, 2.6, 0.78
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * L, sy * L
            fbox(mb, x - 0.06, x + 0.06, y - 0.06, y + 0.06, 0.0, zb - 0.12, S, skip="-z +z")      # legs
            fbox(mb, x - 0.13, x + 0.13, y - 0.13, y + 0.13, 0.0, 0.04, S, skip="-z")              # foot plates
    for y in (-L, L):
        fbox(mb, -1.0, 1.0, y - 0.07, y + 0.07, zb - 0.12, zb, S, skip="")                         # support beams
        fbox(mb, -L, L, y - 0.035, y + 0.035, 0.42, 0.5, S, skip="-x +x")                          # tie beams
        mb.tube([(-L, y, 0.5), (L, y, zb - 0.12)], 0.025, S, segs=4, caps=False)                   # braces
    for x in (-L, L):
        fbox(mb, x - 0.035, x + 0.035, -L, L, 0.42, 0.5, S, skip="-y +y")
        mb.tube([(x, L, 0.5), (x, -L, zb - 0.12)], 0.025, S, segs=4, caps=False)
    mb.cyl(1.2, 0.06, (0, 0, zb), S, segs=12, base=True)                                           # deck plate
    mb.cyl(R, zt - zb - 0.06, (0, 0, zb + 0.06), "wood_mid", segs=12, base=True, caps=False, smooth=False)
    for z in (1.2, 1.8, 2.4):                                                                      # hoops
        mb.cyl(R + 0.025, 0.07, (0, 0, z), S, segs=12, caps=False)
    mb.cyl(1.2, 0.52, (0, 0, zt), "roof_slate", segs=12, r2=0.06, base=True, smooth=False)         # conical roof
    mb.cyl(0.05, 0.08, (0, 0, zt + 0.52), S, segs=6, base=True)
    mb.cyl(0.07, zb, (0.3, -0.3, 0), "steel", segs=6, base=True, caps=False)                       # down pipe
    for x in (-0.2, 0.2):                                                                          # ladder
        fbox(mb, x - 0.02, x + 0.02, R + 0.07, R + 0.11, 0.0, 2.7, S, skip="-z")
    for i in range(8):
        z = 0.3 + i * 0.31
        fbox(mb, -0.2, 0.2, R + 0.075, R + 0.105, z - 0.015, z + 0.015, S, skip="-x +x")
    mb.to_object(r, "mesh")
    return r


def roof_antenna():
    r = begin("roof_antenna", notes="6 m mast on a ballast block, 2 dishes, 3 sector panels, led_red beacon")
    mb = K.MB()
    S = "steel_dark"
    mb.box((0.9, 0.9, 0.18), (0, 0, 0), "concrete", base=True, bevel=0.03)                         # ballast block
    mb.cyl(0.07, 5.62, (0, 0, 0.18), S, segs=6, r2=0.035, base=True)                               # mast
    for a in (90, 210, 330):                                                                       # struts
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        mb.tube([(0.4 * ca, 0.4 * sa, 0.18), (0.03 * ca, 0.03 * sa, 2.2)], 0.022, S, segs=4, caps=False)

    def dish(z, rz, rad):
        with mb.at((0, 0, z), rot=(0, 0, rz)):
            mb.box((0.06, 0.3, 0.06), (0, 0.15, 0), S)
            mb.cyl(0.07, 0.16, (0, 0.34, 0), "white", axis="Y", segs=10, r2=rad, cap_color="gray_light")
            mb.cyl(0.02, 0.2, (0, 0.5, 0), S, axis="Y", segs=4)

    dish(3.3, 20, 0.36)
    dish(4.3, 200, 0.28)
    for a in (0, 120, 240):                                                                        # sector panels
        with mb.at((0, 0, 5.0), rot=(0, 0, a)):
            mb.box((0.16, 0.07, 0.9), (0, 0.17, 0), "gray_light")
            for dz in (-0.25, 0.25):
                mb.box((0.04, 0.12, 0.04), (0, 0.09, dz), S)
    mb.box((0.9, 0.03, 0.03), (0, 0, 5.6), S)                                                      # cross arm + whips
    for x in (-0.44, 0.44):
        mb.cyl(0.012, 0.36, (x, 0, 5.6), S, segs=4, base=True)
    mb.cyl(0.05, 0.07, (0, 0, 5.8), "steel", segs=6, base=True)
    mb.sphere(0.07, (0, 0, 5.93), "led_red", segs=6, rings=4)
    mb.to_object(r, "mesh")
    return r


def roof_stairhut():
    r = begin("roof_stairhut", notes="access hut 3 x 3 x 2.6; door on +Y, louvre on +X")
    mb = K.MB()
    Hh, R_ = 2.4, 1.4
    for k in range(4):                                         # k: 0 = +Y (door), 1 = -X, 2 = -Y, 3 = +X
        with mb.at(rot=(0, 0, 90 * k)):
            with mb.at((0, R_, 0)):
                if k == 0:
                    a, b, d = -0.45, 0.45, 2.05
                    yd = -0.05
                    wall(mb, -R_, R_, 0.0, Hh, (a - 0.07, b + 0.07, 0.0, d + 0.07), "concrete")
                    casing(mb, a, b, 0.0, d, w=0.07, t=0.05, color="steel_dark", bottom=False, y1=yd)
                    q(mb, a, b, 0.0, d, "steel", yd)
                    panel(mb, a + 0.09, b - 0.09, 0.3, 0.95, "steel", t=0.02, c=0.04, y=yd)
                    panel(mb, a + 0.09, b - 0.09, 1.1, 1.9, "steel", t=0.02, c=0.04, y=yd)
                    q(mb, a + 0.02, b - 0.02, 0.03, 0.22, "steel_dark", yd + 0.006)
                    fbox(mb, b - 0.16, b - 0.08, yd, yd + 0.025, 0.95, 1.13, "steel_dark")
                    fbox(mb, b - 0.28, b - 0.09, yd + 0.025, yd + 0.065, 1.03, 1.07, "chrome")
                    wall_lamp(mb, 0.0, 2.27, y=0.0)
                    cbox(mb, -R_ - 0.04, a - 0.07, 0.0, 0.04, 0.0, 0.3, "concrete_dark", c=0.02, skip=("back", "bottom"))
                    cbox(mb, b + 0.07, R_ + 0.04, 0.0, 0.04, 0.0, 0.3, "concrete_dark", c=0.02, skip=("back", "bottom"))
                    fbox(mb, 0.75, 1.05, 0.0, 0.015, 1.45, 1.65, "hazard_yellow")                  # notice plate
                    q(mb, 0.79, 1.01, 1.56, 1.61, "black", 0.02)
                else:
                    wall(mb, -R_, R_, 0.0, Hh, None, "concrete")
                    cbox(mb, -R_ - 0.04, R_ + 0.04, 0.0, 0.04, 0.0, 0.3, "concrete_dark", c=0.02,
                         skip=("back", "bottom"))
                    if k == 3:
                        P.louvre(mb, -0.6, 0.6, 1.45, 2.05, "steel_dark", "steel_dark", n=5, t=0.04, fw=0.05)
                    elif k == 1:
                        fbox(mb, -0.25, 0.25, 0.0, 0.14, 1.0, 1.7, "gray_dark")                    # electrical box
                        fbox(mb, -0.2, 0.2, 0.14, 0.15, 1.08, 1.62, "gray_mid", skip="-y -x +x -z +z")
                        mb.cyl(0.03, 1.0, (0.0, 0.05, 0.0), "steel_dark", segs=5, base=True, caps=False)
                    else:
                        panel(mb, -1.25, -0.03, 0.4, 2.25, "concrete", t=0.02, c=0.04)
                        panel(mb, 0.03, 1.25, 0.4, 2.25, "concrete", t=0.02, c=0.04)
    mb.box((3.0, 3.0, 0.2), (0, 0, Hh), "concrete_dark", base=True, bevel=0.04, colors={"+z": "roof_gravel"})
    mb.to_object(r, "mesh")
    return r


def roof_skylight():
    r = begin("roof_skylight", notes="2 x 2 curb with a truncated glass pyramid (4 @Window quads)")
    mb = K.MB()
    S = "steel_dark"
    for k in range(4):
        with mb.at(rot=(0, 0, 90 * k)):
            q(mb, -1.0, 1.0, 0.0, 0.25, "concrete_light", 1.0)                                     # curb
            fq(mb, [(-1.0, 1.0, 0.25), (1.0, 1.0, 0.25), (0.86, 0.86, 0.25), (-0.86, 0.86, 0.25)], S, (0, 0, 1))
            mb.quad((0.86, 0.86, 0.25), (-0.86, 0.86, 0.25), (-0.22, 0.22, 0.85), (0.22, 0.22, 0.85), "@Window")
            mb.tube([(0.86, 0.86, 0.26), (0.22, 0.22, 0.86)], 0.035, S, segs=4, caps=False)        # hip bar
            mb.tube([(0.0, 0.86, 0.26), (0.0, 0.22, 0.86)], 0.022, S, segs=4, caps=False)          # glazing bar
    mb.box((0.54, 0.54, 0.07), (0, 0, 0.83), S, base=True)
    mb.to_object(r, "mesh")
    return r


def roof_helipad():
    r = begin("roof_helipad", notes="12 x 12 x 0.1 pad; markings are flat faces 5 mm above the deck", spacing=12.0)
    mb = K.MB()
    fbox(mb, -6, 6, -6, 6, 0.0, 0.1, "asphalt_dark", skip="-z")
    z = 0.105

    def flat(x0, x1, y0, y1, col):
        fq(mb, [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], col, (0, 0, 1))

    n, ro, ri = 24, 4.2, 3.75
    for i in range(n):                                                                             # white ring
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        fq(mb, [(ro * math.cos(a0), ro * math.sin(a0), z), (ro * math.cos(a1), ro * math.sin(a1), z),
                (ri * math.cos(a1), ri * math.sin(a1), z), (ri * math.cos(a0), ri * math.sin(a0), z)],
           "line_white", (0, 0, 1))
    flat(-1.5, -0.9, -1.8, 1.8, "line_white")                                                      # "H"
    flat(0.9, 1.5, -1.8, 1.8, "line_white")
    flat(-0.9, 0.9, -0.3, 0.3, "line_white")
    o, i_ = 5.75, 5.5
    for k in range(4):
        with mb.at(rot=(0, 0, 90 * k)):
            fq(mb, [(-o, o, z), (o, o, z), (i_, i_, z), (-i_, i_, z)], "line_yellow", (0, 0, 1))   # edge line
            mb.cyl(0.15, 0.06, (5.62, 5.62, 0.1), "steel_dark", segs=8, base=True)                 # corner light
            mb.cyl(0.1, 0.1, (5.62, 5.62, 0.16), "led_green", segs=8, r2=0.05, base=True)
    mb.to_object(r, "mesh")
    return r


BUILD = (roof_ac, roof_vent, roof_duct, roof_tank, roof_antenna, roof_stairhut, roof_skylight, roof_helipad)


def build_all():
    for f in BUILD:
        f()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS, max_tris=900))


def qa():
    z = 0.1
    return Q.show("roof", [("roof_helipad", (0, 0, 0)), ("roof_ac", (4.2, 3.6, z)), ("roof_vent", (1.9, 4.2, z)),
                           ("roof_duct", (-0.6, 3.6, z)), ("roof_skylight", (-4.0, 3.6, z)),
                           ("roof_tank", (3.8, -2.6, z)), ("roof_antenna", (0.4, -3.4, z)),
                           ("roof_stairhut", (-3.6, -2.6, z))])
