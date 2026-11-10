"""props_furniture - P1 street furniture for NEON TIDE (SPEC_PROPS_NATURE.md).

    import props_common as P, props_furniture as M
    print(P.run(M.IDS)); M.do_layout()

Front of every prop faces +Y (toward the road / viewer).
"""
import math
import random

import gta_kit as K
import props_common as P
from props_common import asset, cyl_col, box_col

POLE = "steel_dark"


@asset("prop_bench", notes="sitter faces +Y")
def prop_bench(root):
    mb = K.MB()
    iron, wood = "charcoal", "wood_mid"
    for sx in (-0.72, 0.72):
        P.beam(mb, (sx, 0.21, 0.0), (sx, 0.17, 0.42), (0.05, 0.05), iron, up=(1, 0, 0), skip=("-y",))     # front leg
        P.beam(mb, (sx, -0.27, 0.0), (sx, -0.2, 0.42), (0.05, 0.05), iron, up=(1, 0, 0), skip=("-y",))    # back leg
        P.beam(mb, (sx, -0.2, 0.39), (sx, -0.312, 0.87), (0.045, 0.05), iron, up=(1, 0, 0), skip=("-y",))  # back support
        P.beam(mb, (sx, -0.225, 0.41), (sx, 0.215, 0.42), (0.05, 0.05), iron, up=(1, 0, 0), skip=())       # seat rail
        P.beam(mb, (sx, 0.165, 0.42), (sx, 0.19, 0.63), (0.04, 0.04), iron, up=(1, 0, 0))                  # arm post
        mb.box((0.06, 0.44, 0.035), (sx, -0.01, 0.645), iron, bevel=0.01)                                  # armrest
        mb.box((0.11, 0.09, 0.012), (sx, 0.21, 0.0), iron, base=True)                                      # feet
        mb.box((0.11, 0.09, 0.012), (sx, -0.27, 0.0), iron, base=True)
    for y in (-0.15, -0.035, 0.08, 0.195):
        mb.box((1.7, 0.1, 0.03), (0, y, 0.46), wood)
    for z in (0.57, 0.69, 0.81):
        y = -0.2 - 0.2333 * (z - 0.39) + 0.04
        mb.box((1.7, 0.028, 0.1), (0, y, z), wood, rot=(13.1, 0, 0))
    mb.to_object(root, "mesh")


@asset("prop_bin", dynamic=True, mass=15, col=cyl_col(0.27, 0.95))
def prop_bin(root):
    mb = K.MB()
    g, c, s = "green_dark", "charcoal", "steel"
    prof = [(0.23, 0.0), (0.25, 0.02), (0.25, 0.065), (0.236, 0.075), (0.248, 0.6), (0.264, 0.61), (0.264, 0.67),
            (0.205, 0.67), (0.205, 0.6), (0.0, 0.6)]
    P.lathe(mb, prof, g, segs=10, colors=[c, c, c, g, s, s, s, "black", "black"])
    mb.box((0.2, 0.012, 0.13), (0, 0.246, 0.4), "white")                                # plaque
    mb.box((0.12, 0.014, 0.03), (0, 0.247, 0.42), "green")
    for k in range(3):
        a = math.radians(90 + 120 * k)
        mb.box((0.035, 0.035, 0.16), (math.cos(a) * 0.228, math.sin(a) * 0.228, 0.665), c, base=True,
               rot=(0, 0, math.degrees(a)))
    P.lathe(mb, [(0.285, 0.815), (0.285, 0.855), (0.22, 0.915), (0.1, 0.94), (0.0, 0.945)], c, segs=10)
    mb.cyl(0.05, 0.012, (0, 0, 0.94), s, segs=8, base=True)
    mb.to_object(root, "mesh")


@asset("prop_dumpster", dynamic=True, mass=120)
def prop_dumpster(root):
    mb = K.MB()
    t = "tint_a"
    prof = [(-0.6, 0.2), (-0.54, 0.14), (0.46, 0.14), (0.6, 1.04), (-0.6, 1.22)]
    mb.prism(prof, 1.9, t, plane="YZ")
    slope = math.degrees(math.atan2(1.22 - 1.04, 1.2))
    for sx in (-0.485, 0.485):                                                           # black lids
        with mb.at((sx, 0.0, 1.15), rot=(-slope, 0, 0)):
            mb.box((0.955, 1.27, 0.045), (0, 0.01, 0), "plastic_black", bevel=0.012)
            mb.box((0.3, 0.05, 0.03), (0, 0.6, 0.03), "charcoal")                        # lid handle
    for sx in (-1, 1):                                                                   # fork pockets
        mb.box((0.06, 0.62, 0.15), (sx * 0.97, 0.0, 0.78), t, colors={"+y": "black", "-y": "black"})
        mb.box((0.03, 0.9, 0.05), (sx * 0.955, 0.0, 1.0), t)
    for sx in (-0.55, 0.0, 0.55):                                                        # front / back ribs
        P.beam(mb, (sx, 0.475, 0.16), (sx, 0.612, 1.03), (0.03, 0.07), t, up=(1, 0, 0))
        mb.box((0.07, 0.03, 0.95), (sx, -0.612, 0.7), t)
    mb.box((1.9, 0.035, 0.05), (0, 0.615, 1.02), t)                                      # front lip
    mb.box((0.34, 0.012, 0.2), (0.5, 0.56, 0.62), "white", rot=(-8.8, 0, 0))             # label
    mb.box((0.26, 0.014, 0.05), (0.5, 0.567, 0.66), "red", rot=(-8.8, 0, 0))
    for sx in (-0.78, 0.78):
        for sy in (-0.4, 0.34):
            mb.cyl(0.07, 0.05, (sx, sy, 0.07), "rubber", axis="X", segs=8)
            mb.box((0.07, 0.09, 0.05), (sx, sy, 0.135), POLE)
    mb.to_object(root, "mesh")


@asset("prop_hydrant", dynamic=True, mass=60, col=cyl_col(0.16, 0.8))
def prop_hydrant(root):
    mb = K.MB()
    r, capc = "red", "gray_light"
    prof = [(0.16, 0.0), (0.16, 0.035), (0.105, 0.055), (0.095, 0.455), (0.125, 0.475), (0.125, 0.515), (0.1, 0.535),
            (0.1, 0.6), (0.12, 0.62), (0.12, 0.65), (0.085, 0.71), (0.04, 0.745)]
    P.lathe(mb, prof, r, segs=8, phase=math.radians(22.5))
    mb.cyl(0.036, 0.055, (0, 0, 0.745), capc, segs=5, base=True)                         # operating nut
    for k in range(4):
        a = math.radians(45 + 90 * k)
        mb.box((0.03, 0.03, 0.022), (math.cos(a) * 0.13, math.sin(a) * 0.13, 0.035), POLE, base=True)
    for sx in (-1, 1):                                                                   # side nozzles
        mb.cyl(0.05, 0.075, (sx * 0.085, 0, 0.57), r, axis="X", segs=6, base=True, rot=None if sx > 0 else (0, 0, 180))
        mb.cyl(0.06, 0.03, (sx * 0.16, 0, 0.57), capc, axis="X", segs=6)
    mb.cyl(0.068, 0.08, (0, 0.085, 0.57), r, axis="Y", segs=8, base=True)                # pumper nozzle (+Y)
    mb.cyl(0.08, 0.035, (0, 0.18, 0.57), capc, axis="Y", segs=8)
    mb.box((0.035, 0.02, 0.035), (0, 0.205, 0.57), POLE)
    K.marker(root, "spray", (0, 0, 0.8))
    mb.to_object(root, "mesh")


def _bus_icon(mb):
    """White bus pictogram in the local XZ plane, facing +Y (local y >= 0)."""
    P.plate(mb, P.rrect(0.34, 0.19, 0.03, 0, 0.02), 0.0, 0.006, "white")
    for i in range(3):
        P.qy(mb, -0.135 + i * 0.095, -0.055 + i * 0.095, 0.03, 0.09, 0.012, "blue")
    for sx in (-0.095, 0.095):
        P.disc(mb, 0.036, (sx, 0.004, -0.095), "white", segs=8)


@asset("prop_bus_stop", col="mesh", notes="open side faces +Y (road); `col` part = simple collision boxes")
def prop_bus_stop(root):
    mb = K.MB()
    fr = "gunmetal"

    def zr(y):                                         # roof underside, rising toward the road
        t = (y + 0.8) / 1.6
        return 2.2 + 0.32 * math.sin(t * math.pi * 0.5)

    ys = [-0.8 + 1.6 * i / 6 for i in range(7)]
    top = [(y, zr(y) + 0.07) for y in ys]
    bot = [(y, zr(y)) for y in reversed(ys)]
    mb.prism(top + bot, 4.0, fr, plane="YZ", side_colors=[None] * 7 + ["offwhite"] * 6 + [None])
    ys2 = [-0.8, -0.27, 0.27, 0.74]
    for sx in (-1.9, 0.0, 1.9):                                                          # roof ribs + posts
        rib = [(y, zr(y) + 0.01) for y in ys2] + [(y, zr(y) - 0.11 + 0.05 * (i == 0)) for i, y in enumerate(reversed(ys2))]
        mb.prism(rib, 0.07, fr, plane="YZ", pos=(sx, 0, 0))
        mb.box((0.08, 0.08, zr(-0.72) - 0.02), (sx, -0.72, 0), fr, base=True)
        mb.box((0.16, 0.16, 0.03), (sx, -0.72, 0), POLE, base=True)
    for sx in (-0.95, 0.95):                                                             # glass back wall
        mb.box((1.8, 0.016, 1.62), (sx, -0.72, 1.19), "@Glass")
    for z in (0.36, 2.02):
        mb.box((3.8, 0.05, 0.05), (0, -0.72, z), fr)
    # lit advertising panel on the -X end (both faces)
    px = -1.9
    mb.box((0.14, 1.24, 1.82), (px, -0.06, 1.22), "charcoal", bevel=0.02)
    mb.box((0.1, 0.5, 0.3), (px, -0.06, 0.16), "charcoal")
    for s in (-1, 1):
        x = px + s * 0.076
        P.qx(mb, -0.6, 0.48, 0.42, 2.02, x, "emis_window_cool", facing=s)
        x2 = x + s * 0.006
        P.disc(mb, 0.2, (x2, 0.1 * s, 1.62), "orange", segs=10, toward=(s, 0, 0))
        P.qx(mb, -0.6, 0.48, 0.42, 0.72, x2, "teal", facing=s)
        P.qx(mb, -0.6, 0.48, 0.8, 0.9, x2, "turquoise", facing=s)
        P.text(mb, "VESPER BAY", (x2, -0.06, 1.2), width=0.92, color="navy", depth=0.0, rot=(0, 0, -90 * s))
    # bench + lean rail
    for y in (-0.56, -0.44, -0.32):
        mb.box((2.5, 0.105, 0.035), (0.35, y, 0.47), "wood_mid")
    for sx in (-0.6, 1.3):
        mb.box((0.05, 0.36, 0.45), (sx, -0.44, 0), fr, base=True)
    mb.box((2.5, 0.03, 0.09), (0.35, -0.67, 0.85), fr)
    # pole sign with bus pictogram (visible from both sides)
    sx, sy = 1.93, 0.72
    mb.cyl(0.035, 2.6, (sx, sy, 0), "steel", segs=6, base=True)
    mb.cyl(0.08, 0.02, (sx, sy, 0), POLE, segs=6, base=True)
    mb.box((0.48, 0.03, 0.48), (sx - 0.24, sy, 2.32), "blue", bevel=0.0)
    for rz in (0, 180):
        with mb.at((sx - 0.24, sy, 2.32), rot=(0, 0, rz)):
            with mb.at((0, 0.021, 0.0)):
                _bus_icon(mb)
    mb.box((0.3, 0.02, 0.4), (0.0, -0.69, 1.45), "white")                                # timetable
    mb.box((0.24, 0.022, 0.06), (0.0, -0.688, 1.58), "blue")
    mb.to_object(root, "mesh")

    def col(c):
        c.box((4.0, 1.7, 0.12), (0, 0, 2.42), "gray_mid")
        c.box((3.9, 0.08, 2.3), (0, -0.72, 0), "gray_mid", base=True)
        c.box((0.14, 1.24, 2.15), (px, -0.06, 0), "gray_mid", base=True)
        c.box((2.5, 0.4, 0.49), (0.35, -0.44, 0), "gray_mid", base=True)
        c.box((0.1, 0.1, 2.6), (sx, sy, 0), "gray_mid", base=True)
    P.col_part(root, col)


@asset("prop_mailbox", dynamic=True, mass=25)
def prop_mailbox(root):
    mb = K.MB()
    b, d = "blue", "blue_dark"
    for sx in (-0.19, 0.19):
        for sy in (-0.19, 0.19):
            mb.box((0.055, 0.055, 0.15), (sx, sy, 0), d, base=True)
    pts = [(-0.25, 0.13), (0.25, 0.13)] + K.arc(0, 0.86, 0.25, 0, 180, 6)
    mb.prism(pts, 0.5, b, plane="YZ")
    mb.box((0.52, 0.52, 0.05), (0, 0, 0.13), d, base=True)
    with mb.at((0, 0.215, 0.955), rot=(28, 0, 0)):                                       # pull-down hopper door
        mb.box((0.4, 0.03, 0.2), (0, 0.02, 0), d, bevel=0.008)
        mb.box((0.22, 0.03, 0.025), (0, 0.045, 0.05), "chrome")
    mb.box((0.3, 0.012, 0.13), (0, 0.251, 0.62), "white")                                # label
    mb.box((0.3, 0.014, 0.03), (0, 0.251, 0.665), "red")
    mb.box((0.36, 0.012, 0.3), (0, 0.251, 0.36), d)                                      # collection door
    mb.box((0.04, 0.02, 0.05), (0.13, 0.26, 0.38), "steel")
    for sx in (-1, 1):
        mb.box((0.012, 0.3, 0.035), (sx * 0.251, 0, 0.86), d)                            # side trims
    mb.to_object(root, "mesh")


@asset("prop_newsbox", dynamic=True, mass=15)
def prop_newsbox(root):
    mb = K.MB()
    t = "tint_a"
    mb.box((0.38, 0.32, 0.03), (0, 0, 0), "charcoal", base=True)
    mb.box((0.1, 0.1, 0.44), (0, 0, 0.03), "charcoal", base=True)
    mb.prism([(-0.2, 0.45), (0.2, 0.45), (0.2, 0.99), (-0.2, 1.07)], 0.45, t, plane="YZ")
    mb.box((0.47, 0.42, 0.03), (0, 0, 0.44), "charcoal", base=True)                      # base trim
    mb.box((0.38, 0.012, 0.37), (0, 0.203, 0.71), "charcoal")                            # door frame
    P.qy(mb, -0.16, 0.16, 0.555, 0.865, 0.215, "glass_dark")
    mb.box((0.25, 0.006, 0.2), (0, 0.219, 0.7), "paper")                                 # the paper
    P.qy(mb, -0.1, 0.1, 0.755, 0.78, 0.228, "black")
    P.qy(mb, -0.1, 0.03, 0.7, 0.715, 0.228, "gray_dark")
    P.qy(mb, -0.1, 0.06, 0.665, 0.68, 0.228, "gray_dark")
    mb.box((0.22, 0.025, 0.025), (0, 0.225, 0.515), "chrome")                            # pull handle
    P.text(mb, "NEWS", (0, 0.206, 0.945), width=0.26, color="white", depth=0.0)
    mb.box((0.11, 0.09, 0.15), (0.13, 0.08, 1.03), POLE, base=False, bevel=0.012)        # coin mech
    mb.box((0.03, 0.012, 0.05), (0.13, 0.127, 1.06), "black")
    mb.to_object(root, "mesh")


@asset("prop_vending", dynamic=True, mass=80)
def prop_vending(root):
    mb = K.MB()
    body = "purple"
    mb.box((0.94, 0.72, 0.06), (0, -0.02, 0), "charcoal", base=True)
    mb.box((1.0, 0.76, 1.84), (0, -0.02, 0.06), body, base=True, bevel=0.02)
    yf = 0.36
    mb.box((0.94, 0.02, 0.27), (0, yf, 1.73), "navy")                                    # header
    P.text(mb, "ZAP!", (0.02, yf + 0.01, 1.73), width=0.56, height=0.18, color="neon_yellow", depth=0.02, res=1)
    wx = 0.15                                                                            # display window
    mb.box((0.64, 0.012, 1.02), (wx, yf, 1.06), "emis_cool_always")
    cols = ["red", "yellow", "green", "cyan", "orange", "lime", "magenta", "white", "blue", "red", "teal", "yellow",
            "cyan", "orange", "green", "pink"]
    k = 0
    for row in range(4):
        z = 1.4 - row * 0.245
        P.xbox(mb, (0.6, 0.035, 0.016), (wx, yf + 0.02, z - 0.11), "gray_dark", skip=("-y",))
        for ci in range(4):
            P.xbox(mb, (0.09, 0.03, 0.18), (wx - 0.21 + ci * 0.14, yf + 0.02, z - 0.01), cols[k % len(cols)],
                   skip=("-y", "-z"))
            k += 1
    px = -0.33                                                                           # payment column
    mb.box((0.2, 0.012, 1.02), (px, yf, 1.06), "charcoal")
    mb.box((0.14, 0.012, 0.08), (px, yf + 0.008, 1.43), "screen_blue")
    mb.box((0.12, 0.014, 0.15), (px, yf + 0.008, 1.24), "gray_mid")
    mb.box((0.06, 0.02, 0.1), (px, yf + 0.008, 1.05), "steel")
    mb.box((0.012, 0.022, 0.05), (px, yf + 0.01, 1.05), "black")
    mb.box((0.035, 0.014, 0.035), (px + 0.05, yf + 0.008, 0.92), "led_green")
    mb.box((0.1, 0.014, 0.09), (px, yf + 0.008, 0.68), "black")                          # coin return
    mb.box((0.66, 0.014, 0.24), (wx, yf, 0.33), "black")                                 # dispenser bay
    mb.box((0.56, 0.02, 0.13), (wx, yf + 0.006, 0.36), "gray_dark", rot=(12, 0, 0))
    bolt = [(0.1, 1.55), (-0.13, 0.98), (0.0, 0.98), (-0.12, 0.5), (0.16, 1.14), (0.03, 1.14), (0.2, 1.55)]
    P.plate(mb, bolt, 0.5, 0.008, "neon_cyan", plane="YZ")                               # side lightning bolts
    P.plate(mb, bolt, -0.508, 0.008, "neon_cyan", plane="YZ")
    mb.to_object(root, "mesh")


@asset("prop_parking_meter", dynamic=True, mass=8)
def prop_parking_meter(root):
    mb = K.MB()
    mb.cyl(0.07, 0.02, (0, 0, 0), POLE, segs=6, base=True)
    mb.cyl(0.028, 1.0, (0, 0, 0), "steel", segs=6, base=True)
    mb.box((0.075, 0.075, 0.05), (0, 0, 1.0), POLE)
    pts = [(-0.09, 1.02), (0.09, 1.02)] + K.arc(0, 1.2, 0.09, 0, 180, 5)
    mb.prism(pts, 0.12, "gray_dark", plane="XZ")
    P.plate(mb, [(-0.06, 1.17), (0.06, 1.17)] + K.arc(0, 1.2, 0.06, 0, 180, 4), 0.06, 0.006, "glass_dark")
    mb.box((0.05, 0.012, 0.03), (0.0, 0.063, 1.21), "led_green")
    mb.box((0.1, 0.014, 0.05), (0, 0.062, 1.1), "hazard_yellow")
    mb.box((0.012, 0.02, 0.035), (0.02, 0.064, 1.1), "black")
    mb.box((0.12, 0.012, 0.03), (0, -0.062, 1.1), "red")
    mb.to_object(root, "mesh")


@asset("prop_bike_rack")
def prop_bike_rack(root):
    mb = K.MB()
    r, zt, zb = 0.16, 0.69, 0.33
    x = -0.8
    pts = [(x, 0, 0.0)]
    for h in range(3):
        pts += P.arc3((x + r, 0, zt), r, 180, 0, 4, "XZ")
        x += 2 * r
        if h < 2:
            pts += P.arc3((x + r, 0, zb), r, 180, 360, 4, "XZ")
            x += 2 * r
    pts.append((x, 0, 0.0))
    mb.tube(pts, 0.027, "steel", segs=6)
    for sx in (-0.8, 0.8):
        mb.box((0.16, 0.12, 0.012), (sx, 0, 0), POLE, base=True)
    mb.to_object(root, "mesh")


@asset("prop_planter")
def prop_planter(root):
    mb = K.MB()
    mb.box((1.5, 0.5, 0.52), (0, 0, 0), "concrete", base=True, taper=(1.05, 1.14), bevel=0.02)
    mb.box((1.6, 0.6, 0.08), (0, 0, 0.52), "concrete_light", base=True, bevel=0.015)
    mb.box((1.46, 0.46, 0.02), (0, 0, 0.59), "mud", base=True)
    P.grid_box(mb, (1.4, 0.44, 0.42), (0, 0, 0.6), "@F:leaf_green", dark="@F:leaf_dark", light="@F:leaf_light",
               segs=(5, 2, 2), jitter=0.035, seed=4, speckle=0.12)
    rnd = random.Random(8)
    fc = ["flower_red", "flower_yellow", "flower_white", "flower_purple"]
    for i in range(9):
        x = -0.62 + i * 0.155 + rnd.uniform(-0.03, 0.03)
        front = i % 3 != 1
        y = 0.2 if front else rnd.uniform(-0.1, 0.1)
        z = rnd.uniform(0.78, 0.95) if front else 1.03
        P.octa(mb, 0.05, (x, y + (0.035 if front else 0), z), fc[i % 4], scale=(1, 1, 0.7))
    mb.to_object(root, "mesh")


@asset("prop_planter_round", col=cyl_col(0.5, 0.56))
def prop_planter_round(root):
    mb = K.MB()
    cl, c = "concrete_light", "concrete"
    prof = [(0.3, 0.0), (0.33, 0.04), (0.5, 0.46), (0.52, 0.48), (0.52, 0.56), (0.45, 0.56), (0.45, 0.52), (0.0, 0.52)]
    P.lathe(mb, prof, c, segs=10, colors=[c, c, cl, cl, cl, "mud", "mud"])
    rnd = random.Random(3)
    n = 10
    for i in range(n):                                                                   # agave-like rosette
        a = 2 * math.pi * i / n + rnd.uniform(-0.2, 0.2)
        inner = i % 2 == 0
        reach = 0.28 if inner else 0.52
        h = 0.75 if inner else 0.42
        dx, dy = math.cos(a), math.sin(a)
        base = (dx * 0.05, dy * 0.05, 0.52)
        mid = (dx * reach * 0.6, dy * reach * 0.6, 0.52 + h * 0.75)
        tip = (dx * reach * 1.25, dy * reach * 1.25, 0.52 + h * (1.0 if inner else 0.8))
        P.blade(mb, base, tip, 0.16, "@F:palm_green", normal=(-dy, dx, 0), mid=mid, mid_w=0.13,
                color2="@F:leaf_dark" if inner else "@F:palm_green")
    P.octa(mb, 0.07, (0, 0, 0.6), "@F:leaf_dark", scale=(1, 1, 1.6))
    mb.to_object(root, "mesh")


@asset("prop_utility_box")
def prop_utility_box(root):
    mb = K.MB()
    mb.box((0.8, 0.6, 0.1), (0, 0, 0), "concrete", base=True)
    mb.box((0.7, 0.5, 1.16), (0, 0, 0.1), "gray_light", base=True, bevel=0.015)
    mb.box((0.75, 0.55, 0.04), (0, 0, 1.26), "gray_mid", base=True)
    yf = 0.25
    mb.box((0.6, 0.012, 0.98), (0, yf, 0.68), "gray_mid")                                # door
    mb.box((0.03, 0.03, 0.15), (0.23, yf + 0.016, 0.7), "charcoal")                      # handle
    for z in (0.32, 1.04):
        mb.box((0.025, 0.02, 0.07), (-0.305, yf + 0.006, z), POLE)                       # hinges
    for i in range(3):
        mb.box((0.34, 0.016, 0.02), (0.0, yf + 0.008, 1.06 + i * 0.04), "gray_dark")     # louvres
    mb.prism([(-0.07, 0.0), (0.07, 0.0), (0.0, 0.125)], 0.006, "hazard_yellow", plane="XZ", pos=(-0.13, yf + 0.009, 0.82))
    mb.box((0.016, 0.006, 0.06), (-0.13, yf + 0.013, 0.855), "black", rot=(0, 20, 0))
    mb.cyl(0.03, 0.42, (-0.39, -0.1, 0.1), "steel", segs=6, base=True)                   # conduit
    mb.box((0.06, 0.1, 0.07), (-0.37, -0.1, 0.52), "steel")
    mb.to_object(root, "mesh")


@asset("prop_transformer")
def prop_transformer(root):
    mb = K.MB()
    g, gl = "green_dark", "green"
    mb.box((1.8, 1.4, 0.1), (0, 0, 0), "concrete", base=True)
    prof = [(-0.5, 0.1), (0.55, 0.1), (0.55, 1.14), (0.27, 1.4), (-0.5, 1.4)]
    mb.prism(prof, 1.6, g, plane="YZ")
    mb.box((1.64, 0.82, 0.03), (0, -0.1, 1.4), g, base=True)                             # lid overhang
    for sx in (-0.39, 0.39):                                                             # cabinet doors
        mb.box((0.74, 0.012, 0.92), (sx, 0.553, 0.63), gl)
        mb.box((0.03, 0.03, 0.14), (sx * 0.23, 0.57, 0.66), "charcoal")
    mb.box((0.05, 0.03, 0.06), (0, 0.57, 0.6), "brass")                                  # padlock
    mb.prism([(-0.1, 0.0), (0.1, 0.0), (0.0, 0.175)], 0.006, "hazard_yellow", plane="XZ", pos=(-0.39, 0.563, 0.8))
    mb.box((0.022, 0.006, 0.085), (-0.39, 0.567, 0.85), "black", rot=(0, 22, 0))
    for i in range(7):                                                                   # cooling fins
        P.xbox(mb, (0.03, 0.14, 0.85), (-0.6 + i * 0.2, -0.57, 0.3), g, base=True, skip=("+y",))
    for sx in (-1, 1):
        mb.box((0.012, 0.5, 0.5), (sx * 0.803, -0.05, 0.75), gl)                         # side panels
        mb.box((0.05, 0.1, 0.06), (sx * 0.74, -0.1, 1.46), POLE)                         # lifting lugs
    mb.to_object(root, "mesh")


@asset("prop_manhole", col="none")
def prop_manhole(root):
    mb = K.MB()
    d, c = "steel_dark", "gunmetal"
    P.lathe(mb, [(0.35, 0.0), (0.35, 0.013), (0.335, 0.02), (0.3, 0.02), (0.293, 0.012), (0.0, 0.012)], d, segs=14,
            colors=[d, d, d, c, c])
    P.lathe(mb, [(0.2, 0.012), (0.2, 0.019), (0.165, 0.019), (0.165, 0.012)], d, segs=14, cap0=False, cap1=False)
    for k in range(8):
        a = 360.0 * k / 8 + 22.5
        with mb.at((0, 0, 0.012), rot=(0, 0, a)):
            P.xbox(mb, (0.075, 0.035, 0.007), (0.245, 0, 0), d, base=True, skip=("-z",))
    for rz in (0, 90):
        with mb.at((0, 0, 0.012), rot=(0, 0, rz)):
            P.xbox(mb, (0.3, 0.03, 0.007), (0, 0, 0), d, base=True, skip=("-z",))
    for sx in (-1, 1):
        P.qz(mb, sx * 0.1 - 0.02, sx * 0.1 + 0.02, 0.09, 0.115, 0.0135, "black")
    mb.to_object(root, "mesh")


@asset("prop_atm")
def prop_atm(root):
    mb = K.MB()
    body, acc = "gray_light", "teal"
    mb.box((0.64, 0.5, 0.06), (0, 0, 0), "charcoal", base=True)
    mb.box((0.6, 0.46, 0.92), (0, -0.01, 0.06), body, base=True, bevel=0.015)
    prof = [(-0.24, 0.96), (0.3, 0.96), (0.3, 1.04), (0.12, 1.1), (0.06, 1.62), (-0.24, 1.62)]
    mb.prism(prof, 0.6, body, plane="YZ")
    mb.box((0.64, 0.36, 0.2), (0, -0.07, 1.62), acc, base=True, bevel=0.012)             # lit header / hood
    P.text(mb, "ATM", (0, 0.111, 1.72), height=0.115, color="neon_white", depth=0.012, res=1)
    with mb.at((0, 0.09, 1.36), rot=(6.6, 0, 0)):                                        # screen fascia
        mb.box((0.44, 0.014, 0.33), (0, 0.007, 0.04), "black")
        mb.box((0.34, 0.012, 0.24), (0, 0.016, 0.04), "screen_blue")
        for s in (-1, 1):
            for i in range(3):
                mb.box((0.024, 0.014, 0.03), (s * 0.195, 0.016, -0.03 + i * 0.07), "gray_mid")
        mb.box((0.14, 0.014, 0.022), (-0.1, 0.007, -0.19), "black")                      # card slot
        mb.box((0.02, 0.016, 0.022), (-0.005, 0.007, -0.19), "led_green")
        mb.box((0.12, 0.014, 0.016), (0.13, 0.007, -0.19), "black")                      # receipt slot
    with mb.at((0, 0.21, 1.07), rot=(-18.4, 0, 0)):                                      # keypad shelf
        mb.box((0.22, 0.13, 0.012), (0, 0, 0.006), "gray_dark")
        for ix in range(3):
            for iy in range(3):
                mb.box((0.045, 0.026, 0.008), (-0.06 + ix * 0.06, -0.038 + iy * 0.038, 0.014), "offwhite")
    mb.box((0.36, 0.014, 0.05), (0, 0.222, 0.86), "black")                               # cash slot
    mb.box((0.4, 0.012, 0.3), (0, 0.221, 0.5), "gray_mid")                               # service door
    mb.box((0.03, 0.02, 0.05), (0.15, 0.23, 0.52), "steel")
    for s in (-1, 1):
        mb.box((0.012, 0.3, 1.2), (s * 0.303, -0.01, 0.75), acc)                         # side stripes
    mb.to_object(root, "mesh")


@asset("prop_flagpole", col=cyl_col(0.1, 8.0),
       notes="flag part: origin on the pole axis (z 7.15), flag extends toward +X")
def prop_flagpole(root):
    mb = K.MB()
    c = "concrete"
    P.lathe(mb, [(0.28, 0.0), (0.28, 0.1), (0.2, 0.16), (0.13, 0.2), (0.1, 0.5), (0.07, 0.56)], c, segs=8,
            colors=[c, c, "steel", "steel", "steel"])
    mb.cyl(0.062, 7.3, (0, 0, 0.5), "aluminum", segs=8, base=True, r2=0.035)
    mb.cyl(0.055, 0.04, (0, 0, 7.8), "aluminum", segs=8, base=True)
    mb.sphere(0.08, (0, 0, 7.92), "gold", segs=8, rings=5)
    mb.box((0.03, 0.05, 0.12), (0, 0.078, 1.2), POLE)                                    # cleat
    mb.tube([(0, 0.075, 1.24), (0, 0.055, 7.76)], 0.006, "rope", segs=3, caps=False)     # halyard
    mb.to_object(root, "mesh")

    fl = K.MB()
    nx = 6
    for z0, z1, col in ((7.35, 7.75, "tint_a"), (6.95, 7.35, "white"), (6.55, 6.95, "tint_a")):
        top, bot = [], []
        for i in range(nx + 1):
            u = i / nx
            x = 0.05 + 1.8 * u
            y = 0.1 * math.sin(i * 1.3) * u
            sag = -0.07 * u * u
            top.append((x, y, z1 + sag))
            bot.append((x, y, z0 + sag))
        P.strip2(fl, bot, top, col)
    fl.to_object(root, "flag", origin=(0, 0, 7.15))


@asset("prop_picnic_table")
def prop_picnic_table(root):
    mb = K.MB()
    w, d = "wood_mid", "wood_dark"
    for i in range(5):
        mb.box((1.8, 0.142, 0.04), (0, -0.3 + 0.15 * i, 0.74), w if i % 2 == 0 else "wood_light")
    for sy in (-1, 1):
        for j in range(2):
            mb.box((1.8, 0.142, 0.04), (0, sy * (0.6 + 0.15 * j), 0.44), w if j == 0 else "wood_light")
    for sx in (-0.66, 0.66):
        for sy in (-1, 1):
            P.beam(mb, (sx, sy * 0.72, 0.0), (sx, sy * 0.22, 0.72), (0.09, 0.04), d, up=(1, 0, 0), skip=("-y",))
        mb.box((0.04, 1.56, 0.09), (sx + (0.04 if sx < 0 else -0.04), 0, 0.375), d)
        mb.box((0.04, 0.7, 0.08), (sx + (0.04 if sx < 0 else -0.04), 0, 0.68), d)
    for s in (-1, 1):
        P.beam(mb, (s * 0.6, 0, 0.4), (s * 0.18, 0, 0.71), (0.07, 0.035), d, up=(0, 1, 0))
    mb.to_object(root, "mesh")


# =========================================================================== registry of this module
IDS = ["prop_bench", "prop_bin", "prop_dumpster", "prop_hydrant", "prop_bus_stop", "prop_mailbox", "prop_newsbox",
       "prop_vending", "prop_parking_meter", "prop_bike_rack", "prop_planter", "prop_planter_round",
       "prop_utility_box", "prop_transformer", "prop_manhole", "prop_atm", "prop_flagpole", "prop_picnic_table"]

ROW_Y = K.CATEGORIES["StreetProps"][1]
X0 = 80.0
SHEETS = [
    ("furn_a", ["prop_hydrant", "prop_parking_meter", "prop_bin", "prop_mailbox", "prop_newsbox", "prop_atm",
                "prop_vending", "prop_utility_box"], 1.5, 2.2, 4),
    ("furn_b", ["prop_bench", "prop_bike_rack", "prop_planter", "prop_planter_round", "prop_manhole",
                "prop_picnic_table", "prop_dumpster", "prop_transformer"], 3.0, 3.2, 4),
    ("furn_c", ["prop_bus_stop", "prop_flagpole"], 6.0, 4.0, 2),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, X0)
