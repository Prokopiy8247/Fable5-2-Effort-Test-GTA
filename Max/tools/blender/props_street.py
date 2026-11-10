"""props_street - P1 street props for NEON TIDE: traffic / lighting / signage, street furniture,
fences and walls (SPEC_PROPS_NATURE.md).

Run inside Blender (see props_common.py):

    import props_common as P, props_street as M
    print(P.run(M.IDS))            # build + export + manifest + save
    M.do_layout()                  # contact-sheet placement in the master scene

Roadside orientation rule: +Y points toward the road / the approaching viewer.
"""
import math
import random

import gta_kit as K
import props_common as P
from props_common import asset, cyl_col, box_col

POLE = "steel_dark"


# =========================================================================== traffic, lighting, signage
def _signal_head(mb, x, y, z):
    """3-lens signal head centred at (x, y, z); lenses face +Y (R top, A, G bottom)."""
    P.plate(mb, P.rrect(0.54, 1.2, 0.06, x, z), y - 0.035, 0.03, "hazard_yellow")      # back-plate
    mb.box((0.3, 0.22, 0.98), (x, y + 0.02, z), "charcoal", bevel=0.025)                # housing
    front = y + 0.13
    for i, mat in enumerate(("@SignalR", "@SignalA", "@SignalG")):
        cz = z + 0.31 - i * 0.31
        P.disc(mb, 0.1, (x, front + 0.006, cz), mat, segs=10)
        P.visor(mb, x, front, cz, 0.12, 0.18, "charcoal", segs=4)


@asset("traffic_light", col=cyl_col(0.12, 6.2),
       notes="lenses face +Y, mast arm toward +X; lens materials SignalR / SignalA / SignalG")
def traffic_light(root):
    mb = K.MB()
    mb.cyl(0.21, 0.04, (0, 0, 0), POLE, segs=8, base=True)
    mb.cyl(0.15, 0.5, (0, 0, 0.04), POLE, segs=8, base=True, r2=0.115)
    mb.cyl(0.09, 6.2, (0, 0, 0), POLE, segs=8, base=True)
    mb.cyl(0.09, 0.09, (0, 0, 6.2), POLE, segs=8, base=True, r2=0.03)
    # mast arm toward +X with clamp collar and brace
    mb.cyl(0.07, 5.5, (0, 0, 5.8), POLE, axis="X", segs=8, r2=0.045, base=True)
    mb.cyl(0.115, 0.24, (0, 0, 5.8), POLE, segs=8)
    P.beam(mb, (0.05, 0, 4.95), (1.15, 0, 5.77), (0.05, 0.05), POLE)
    # signal heads
    _signal_head(mb, 0.0, 0.3, 3.3)
    for dz in (-0.36, 0.36):
        mb.box((0.07, 0.16, 0.05), (0, 0.15, 3.3 + dz), POLE)
    _signal_head(mb, 5.2, 0.2, 5.55)
    mb.box((0.08, 0.1, 0.3), (5.2, 0.07, 5.74), POLE)
    # controller cabinet on the back of the pole + pedestrian push button
    mb.box((0.3, 0.17, 0.44), (0, -0.165, 1.4), "gray_mid", bevel=0.015)
    mb.box((0.2, 0.012, 0.3), (0, -0.256, 1.4), "gray_dark")
    mb.box((0.1, 0.05, 0.15), (0, 0.11, 1.1), "hazard_yellow", bevel=0.01)
    mb.cyl(0.022, 0.02, (0, 0.142, 1.085), "steel", axis="Y", segs=6)
    mb.to_object(root, "mesh")


def _street_lamp(root, double):
    mb = K.MB()
    c = "steel"
    mb.cyl(0.21, 0.05, (0, 0, 0), POLE, segs=8, base=True)
    mb.cyl(0.145, 0.7, (0, 0, 0.05), POLE, segs=8, base=True, r2=0.115)
    mb.cyl(0.13, 0.045, (0, 0, 0.75), POLE, segs=8, base=True)
    mb.cyl(0.095, 6.3, (0, 0, 0.75), c, segs=8, base=True, r2=0.06)
    mb.cyl(0.075, 0.12, (0, 0, 6.82), POLE, segs=8, base=True)                          # arm collar
    mb.cyl(0.06, 0.12, (0, 0, 7.05), c, segs=8, base=True, r2=0.02)
    mb.box((0.11, 0.035, 0.2), (0, 0.092, 0.42), "gray_dark")                          # service hatch
    sides = (1, -1) if double else (1,)
    for sgn in sides:
        pts = [(0, 0, 6.88), (0, 0.06 * sgn, 7.14), (0, 0.36 * sgn, 7.37), (0, 0.9 * sgn, 7.46),
               (0, 1.32 * sgn, 7.47)]
        P.ttube(mb, pts, [0.055, 0.052, 0.048, 0.044, 0.04], c, segs=6, smooth=True)
        with mb.at((0, 1.6 * sgn, 7.45), rot=(0, 0, 0 if sgn > 0 else 180)):
            mb.box((0.32, 0.7, 0.1), (0, 0, 0), "charcoal", bevel=0.03, taper=(0.72, 0.88))
            mb.box((0.23, 0.55, 0.022), (0, 0.02, -0.057), "emis_lamp")
            mb.box((0.13, 0.12, 0.075), (0, -0.37, -0.005), "charcoal")
        name = "light" if not double else ("light_a" if sgn > 0 else "light_b")
        K.marker(root, name, (0, 1.6 * sgn, 7.36))
    mb.to_object(root, "mesh")


@asset("street_lamp", col=cyl_col(0.12, 7.5), dynamic=True, mass=90)
def street_lamp(root):
    _street_lamp(root, False)


@asset("street_lamp_double", col=cyl_col(0.12, 7.5), dynamic=True, mass=110)
def street_lamp_double(root):
    _street_lamp(root, True)


@asset("lamp_park", col=cyl_col(0.1, 3.5), dynamic=True, mass=40)
def lamp_park(root):
    mb = K.MB()
    c = "gunmetal"
    prof = [(0.17, 0.0), (0.17, 0.06), (0.115, 0.1), (0.115, 0.34), (0.055, 0.48),
            (0.05, 0.95), (0.07, 0.98), (0.07, 1.03), (0.048, 1.06), (0.042, 2.72), (0.075, 2.75),
            (0.075, 2.8), (0.04, 2.84), (0.04, 2.9), (0.14, 3.0), (0.14, 3.03), (0.1, 3.03)]
    P.lathe(mb, prof, c, segs=8, cap1=True)
    mb.sphere(0.25, (0, 0, 3.22), "emis_lamp", segs=10, rings=6)
    P.lathe(mb, [(0.085, 3.43), (0.085, 3.455), (0.03, 3.47), (0.012, 3.5)], c, segs=8, cap0=True, cap1=True)
    K.marker(root, "light", (0, 0, 3.22))
    mb.to_object(root, "mesh")


def _sign_pole(mb, h, clamps=()):
    mb.cyl(0.075, 0.02, (0, 0, 0), POLE, segs=6, base=True)
    mb.cyl(0.03, h, (0, 0, 0), "steel", segs=6, base=True)
    for z in clamps:
        mb.box((0.1, 0.085, 0.035), (0, 0, z), POLE)


@asset("sign_stop", dynamic=True, mass=15)
def sign_stop(root):
    mb = K.MB()
    zc = 2.1
    _sign_pole(mb, 2.5, (zc - 0.2, zc + 0.2))
    ph = math.radians(22.5)
    P.plate(mb, P.ngon(0.406, 8, 0, zc, ph), 0.035, 0.02, "white", back="aluminum")
    P.plate(mb, P.ngon(0.368, 8, 0, zc, ph), 0.055, 0.008, "red")
    P.text(mb, "STOP", (0, 0.063, zc), width=0.5, color="white", depth=0.012, res=2)
    mb.to_object(root, "mesh")


@asset("sign_speed", dynamic=True, mass=15)
def sign_speed(root):
    mb = K.MB()
    zc = 2.11
    _sign_pole(mb, 2.5, (zc - 0.22, zc + 0.22))
    P.plate(mb, P.rrect(0.6, 0.76, 0.04, 0, zc), 0.035, 0.02, "black", back="aluminum")
    P.plate(mb, P.rrect(0.55, 0.71, 0.03, 0, zc), 0.055, 0.008, "white")
    P.text(mb, "SPEED", (0, 0.069, zc + 0.255), height=0.07, color="black", depth=0.0)
    P.text(mb, "LIMIT", (0, 0.069, zc + 0.155), height=0.07, color="black", depth=0.0)
    P.text(mb, "35", (0, 0.063, zc - 0.11), height=0.3, color="black", depth=0.012, res=2)
    mb.to_object(root, "mesh")


@asset("sign_oneway", dynamic=True, mass=15)
def sign_oneway(root):
    mb = K.MB()
    zc = 2.32
    _sign_pole(mb, 2.5, (zc - 0.09, zc + 0.09))
    P.plate(mb, P.rrect(0.92, 0.32, 0.03, 0, zc), 0.035, 0.02, "black", back="aluminum")
    arrow = [(-0.42, 0), (-0.2, 0.125), (-0.2, 0.068), (0.42, 0.068), (0.42, -0.068), (-0.2, -0.068), (-0.2, -0.125)]
    P.plate(mb, [(x, z + zc) for x, z in arrow], 0.055, 0.008, "white")
    P.text(mb, "ONE WAY", (0.1, 0.069, zc), width=0.5, height=0.078, color="black", depth=0.0)
    mb.to_object(root, "mesh")


def _sign_square(root, letter, face):
    mb = K.MB()
    zc = 2.17
    _sign_pole(mb, 2.5, (zc - 0.18, zc + 0.18))
    P.plate(mb, P.rrect(0.62, 0.62, 0.05, 0, zc), 0.035, 0.02, "white", back="aluminum")
    P.plate(mb, P.rrect(0.56, 0.56, 0.035, 0, zc), 0.055, 0.008, face)
    P.text(mb, letter, (0, 0.063, zc), height=0.36, color="white", depth=0.012, res=2)
    mb.to_object(root, "mesh")


@asset("sign_parking", dynamic=True, mass=15)
def sign_parking(root):
    _sign_square(root, "P", "blue")


@asset("sign_hospital", dynamic=True, mass=15)
def sign_hospital(root):
    _sign_square(root, "H", "blue")


@asset("sign_street", dynamic=True, mass=18)
def sign_street(root):
    mb = K.MB()
    mb.cyl(0.075, 0.02, (0, 0, 0), POLE, segs=6, base=True)
    mb.cyl(0.03, 2.62, (0, 0, 0), "steel", segs=6, base=True)
    g = "green_dark"
    mb.box((0.075, 0.075, 0.05), (0, 0, 2.625), POLE)
    mb.box((0.92, 0.022, 0.18), (0, 0, 2.73), g)                       # blade A, readable from +-Y
    mb.box((0.075, 0.075, 0.03), (0, 0, 2.832), POLE)
    mb.box((0.022, 0.92, 0.16), (0, 0, 2.92), g)                       # blade B, readable from +-X
    for rz, off in ((0, (0, 0.017)), (180, (0, -0.017))):
        P.text(mb, "BAYLINE AVE", (off[0], off[1], 2.73), width=0.8, height=0.095, color="white", depth=0.0,
               rot=(0, 0, rz))
    for rz, off in ((-90, (0.017, 0)), (90, (-0.017, 0))):
        P.text(mb, "MERIDIAN ST", (off[0], off[1], 2.92), width=0.8, height=0.085, color="white", depth=0.0,
               rot=(0, 0, rz))
    mb.to_object(root, "mesh")


@asset("sign_airport", dynamic=True, mass=16)
def sign_airport(root):
    mb = K.MB()
    zc = 2.18
    _sign_pole(mb, 2.5, (zc - 0.18, zc + 0.18))
    P.plate(mb, P.rrect(0.82, 0.62, 0.05, 0, zc), 0.035, 0.02, "white", back="aluminum")
    P.plate(mb, P.rrect(0.76, 0.56, 0.035, 0, zc), 0.055, 0.008, "green")
    with mb.at((0, 0.063, zc), rot=(0, -42, 0)):
        fus = [(0, 0.22), (0.032, 0.16), (0.032, -0.17), (0, -0.215), (-0.032, -0.17), (-0.032, 0.16)]
        mb.prism(fus, 0.008, "white", plane="XZ", center=False)
        for s in (1, -1):
            mb.prism([(s * 0.03, 0.07), (s * 0.22, -0.07), (s * 0.22, -0.11), (s * 0.03, -0.035)], 0.008, "white",
                     plane="XZ", center=False)
            mb.prism([(s * 0.03, -0.12), (s * 0.095, -0.175), (s * 0.095, -0.2), (s * 0.03, -0.178)], 0.008,
                     "white", plane="XZ", center=False)
    mb.to_object(root, "mesh")


JERSEY = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.15, 0.33), (0.09, 0.9), (-0.09, 0.9), (-0.15, 0.33), (-0.3, 0.08)]


@asset("barrier_jersey", notes="tiles end to end along X")
def barrier_jersey(root):
    mb = K.MB()
    rings = []
    for x, sy, sz in ((-1.5, 0.9, 0.975), (-1.46, 1.0, 1.0), (1.46, 1.0, 1.0), (1.5, 0.9, 0.975)):
        rings.append([(x, y * sy, z * sz) for y, z in JERSEY])
    faces = mb.loft(rings, "concrete")
    for f in faces:
        f.normal_update()
        if f.calc_center_median().z < 0.06 and abs(f.normal.y) > 0.9:
            mb.paint([f], "concrete_dark")
    for sx in (-0.75, 0.75):
        for sy in (-1, 1):
            mb.box((0.34, 0.012, 0.055), (sx, sy * 0.3, 0.03), "asphalt_dark")           # drain slots
        mb.tube(P.arc3((sx * 1.25, 0, 0.895), 0.065, 0, 180, 4, "XZ"), 0.013, POLE, segs=4)  # lifting loops
        mb.box((0.16, 0.185, 0.012), (sx * 0.5, 0, 0.9), "safety_orange")              # reflector tabs
    mb.to_object(root, "mesh")


@asset("barrier_plastic", dynamic=True, mass=30)
def barrier_plastic(root):
    mb = K.MB()
    prof = [(-0.25, 0.0), (0.25, 0.0), (0.25, 0.13), (0.125, 0.42), (0.1, 0.9), (-0.1, 0.9), (-0.125, 0.42),
            (-0.25, 0.13)]
    spec = ((-0.80, 0.8, 0.95), (-0.76, 1, 1), (-0.31, 1, 1), (-0.27, 0.82, 1), (-0.23, 1, 1),
            (0.23, 1, 1), (0.27, 0.82, 1), (0.31, 1, 1), (0.76, 1, 1), (0.80, 0.8, 0.95))
    rings = [[(x, y * sy, z * sz) for y, z in prof] for x, sy, sz in spec]
    cols = ["red", "red", "red_dark", "red_dark", "white", "red_dark", "red_dark", "red", "red"]
    mb.loft(rings, "red", ring_colors=cols)
    mb.cyl(0.05, 0.035, (0.5, 0, 0.9), "charcoal", segs=8, base=True)                   # fill cap
    mb.cyl(0.035, 0.02, (-0.5, 0, 0.9), "charcoal", segs=6, base=True)                  # vent plug
    for sx in (-0.52, 0.52):
        for sy in (-1, 1):
            mb.box((0.24, 0.012, 0.075), (sx, sy * 0.25, 0.045), "black")                # fork slots
    for sx in (-1, 1):
        mb.box((0.035, 0.1, 0.5), (sx * 0.8, 0, 0.42), "red_dark")                       # connector lugs
    mb.to_object(root, "mesh")


@asset("barrier_police", dynamic=True, mass=12)
def barrier_police(root):
    mb = K.MB()
    leg = "gray_light"
    for sx in (-0.84, 0.84):
        for sy in (-1, 1):
            P.beam(mb, (sx, sy * 0.28, 0.0), (sx, sy * 0.035, 1.05), (0.075, 0.04), leg, up=(1, 0, 0), skip=("-y",))
        P.beam(mb, (sx, -0.18, 0.42), (sx, 0.18, 0.42), (0.03, 0.05), leg, up=(0, 0, 1))
    yb = 0.105
    mb.box((0.84, 0.03, 0.22), (0, yb, 0.92), "white")
    for s in (-1, 1):
        P.striped_board(mb, 0.58, 0.22, 0.03, pos=(s * 0.71, yb, 0.92), colors=("white", "police_blue"),
                        stripe=0.1, slant=0.12 * s)
    P.text(mb, "POLICE", (0, yb + 0.015, 0.92), width=0.72, height=0.125, color="police_blue", depth=0.01, res=1)
    mb.box((1.84, 0.025, 0.07), (0, 0.19, 0.45), "police_blue")
    mb.to_object(root, "mesh")


@asset("barrier_construction", dynamic=True, mass=10)
def barrier_construction(root):
    mb = K.MB()
    top = 0.86
    spread = 0.225
    for sx in (-0.62, 0.62):
        for sy in (-1, 1):
            P.beam(mb, (sx, sy * (spread + 0.02), 0.0), (sx, sy * 0.02, top), (0.05, 0.03), "gray_light",
                   up=(1, 0, 0), skip=("-y",))
        mb.box((0.035, 0.09, 0.03), (sx, 0, top), "gray_dark")
    tilt = math.degrees(math.atan2(spread, top))
    for sy in (-1, 1):
        for zc in (0.7, 0.38):
            y = sy * (spread + 0.02 - spread * zc / top + 0.028)
            P.striped_board(mb, 1.5, 0.2, 0.02, pos=(0, y, zc), colors=("white", "safety_orange"),
                            stripe=0.15, slant=0.2 * sy, rot=(sy * tilt, 0, 0),
                            sides=("+y",) if sy > 0 else ("-y",))
    # amber warning lamp
    mb.box((0.1, 0.07, 0.045), (0.62, 0, top + 0.03), "charcoal")
    mb.cyl(0.055, 0.05, (0.62, 0, top + 0.085), "hazard_yellow", axis="Y", segs=10)
    for s in (-1, 1):
        P.disc(mb, 0.043, (0.62, s * 0.031, top + 0.085), "emis_always_amber", segs=10, toward=(0, s, 0))
    mb.to_object(root, "mesh")


@asset("spike_strip", col="none")
def spike_strip(root):
    mb = K.MB()
    n = 6
    seg = 3.48 / n
    for i in range(n):
        x = -1.74 + seg * (i + 0.5)
        mb.box((seg - 0.025, 0.3, 0.016), (x, 0, 0), "rubber", base=True)
        for j, sx in enumerate((-0.19, 0.0, 0.19)):
            for sy in (-0.085, 0.085):
                mb.cyl(0.015, 0.044, (x + sx + (0.045 if sy > 0 else -0.045), sy, 0.016), "chrome", segs=4,
                       r2=0.0, base=True, caps=False, smooth=False)
    mb.box((3.48, 0.03, 0.01), (0, 0, 0.004), "steel_dark", base=True)                  # hinge cable
    for sx in (-1, 1):
        mb.box((0.06, 0.3, 0.022), (sx * 1.77, 0, 0), "hazard_yellow", base=True)
    mb.to_object(root, "mesh")


@asset("prop_cone", dynamic=True, mass=2)
def prop_cone(root):
    mb = K.MB()
    s, c = 0.18, 0.045
    base = [(s - c, -s), (s, -s + c), (s, s - c), (s - c, s), (-s + c, s), (-s, s - c), (-s, -s + c), (-s + c, -s)]
    mb.prism(base, 0.035, "rubber", plane="XY", center=False)
    o, w = "cone_orange", "white"
    prof = [(0.158, 0.035), (0.136, 0.055), (0.097, 0.26), (0.079, 0.37), (0.063, 0.46), (0.051, 0.53), (0.03, 0.66)]
    P.lathe(mb, prof, o, segs=8, colors=[o, o, w, o, w, o], cap0=False)
    mb.to_object(root, "mesh")


@asset("prop_bollard", col=cyl_col(0.1, 0.9))
def prop_bollard(root):
    mb = K.MB()
    s = "steel"
    prof = [(0.135, 0.0), (0.135, 0.025), (0.1, 0.04), (0.1, 0.6), (0.1, 0.72), (0.1, 0.85), (0.085, 0.885),
            (0.05, 0.9), (0.0, 0.9)]
    P.lathe(mb, prof, s, segs=10, colors=[POLE, POLE, s, "hazard_yellow", s, s, s, s])
    mb.to_object(root, "mesh")


@asset("prop_bollard_light", col=cyl_col(0.1, 0.9))
def prop_bollard_light(root):
    mb = K.MB()
    c = "charcoal"
    e = "emis_lamp"
    prof = [(0.125, 0.0), (0.125, 0.03), (0.1, 0.045), (0.1, 0.58), (0.08, 0.59), (0.08, 0.8), (0.1, 0.81),
            (0.1, 0.865), (0.075, 0.9), (0.0, 0.9)]
    P.lathe(mb, prof, c, segs=8, colors=[c, c, c, c, e, c, c, c, c])
    for z in (0.64, 0.695, 0.75):
        P.lathe(mb, [(0.078, z), (0.1, z), (0.1, z + 0.016), (0.078, z + 0.016)], c, segs=8, cap0=False, cap1=False)
    mb.to_object(root, "mesh")


@asset("prop_boom_gate", col=box_col((0.42, 0.42, 1.12), (0, 0, 0.56)),
       notes="arm part pivots about its local Y axis (origin at the pivot), closed = horizontal toward +X")
def prop_boom_gate(root):
    mb = K.MB()
    mb.box((0.52, 0.52, 0.04), (0, 0, 0), "concrete", base=True)
    mb.box((0.36, 0.36, 1.02), (0, 0, 0.04), "hazard_yellow", base=True, bevel=0.02)
    mb.box((0.41, 0.41, 0.05), (0, 0, 1.06), "charcoal", base=True, bevel=0.012)
    P.striped_board(mb, 0.36, 0.2, 0.012, pos=(0, 0.183, 0.17), colors=("hazard_yellow", "black"), stripe=0.07,
                    slant=0.1, sides=("+y",))
    mb.box((0.012, 0.24, 0.5), (-0.183, 0, 0.55), "yellow_dark")                         # service door
    mb.box((0.02, 0.03, 0.08), (-0.195, 0.08, 0.55), "charcoal")
    mb.cyl(0.1, 0.05, (0, 0.2, 0.9), "charcoal", axis="Y", segs=10)                      # pivot boss
    mb.cyl(0.05, 0.03, (0, 0, 1.11), "charcoal", segs=8, base=True)
    mb.cyl(0.055, 0.08, (0, 0, 1.14), "emis_always_amber", segs=8, base=True, r2=0.04)   # warning lamp
    mb.to_object(root, "mesh")

    arm = K.MB()
    py, pz = 0.255, 0.9
    for i in range(9):
        skip = ("-x",) if i > 0 else ()
        P.xbox(arm, (0.5, 0.04, 0.09), (0.25 + 0.5 * i, py, pz), "red" if i % 2 == 0 else "white",
               skip=skip + (("+x",) if i < 8 else ()))
    arm.box((0.42, 0.06, 0.15), (-0.2, py, pz), "charcoal", bevel=0.015)                 # counterweight
    arm.cyl(0.075, 0.07, (0, py, pz), POLE, axis="Y", segs=10)
    arm.cyl(0.17, 0.014, (2.25, py + 0.027, pz), "red", axis="Y", segs=12)               # stop disc
    arm.box((0.24, 0.012, 0.055), (2.25, py + 0.036, pz), "white")
    arm.box((0.03, 0.05, 0.1), (4.5, py, pz), "red_dark")
    arm.to_object(root, "arm", origin=(0, py, pz))


# =========================================================================== registry of this module
IDS_TRAFFIC = ["traffic_light", "street_lamp", "street_lamp_double", "lamp_park", "sign_stop", "sign_speed",
               "sign_oneway", "sign_parking", "sign_street", "sign_hospital", "sign_airport", "barrier_jersey",
               "barrier_plastic", "barrier_police", "barrier_construction", "spike_strip", "prop_cone",
               "prop_bollard", "prop_bollard_light", "prop_boom_gate"]
IDS = IDS_TRAFFIC

ROW_Y = K.CATEGORIES["StreetProps"][1]
SHEETS = [
    ("lights", ["traffic_light", "street_lamp", "street_lamp_double", "lamp_park"], 7.0, 6.0, 4),
    ("signs", ["sign_stop", "sign_speed", "sign_oneway", "sign_parking", "sign_street", "sign_hospital",
               "sign_airport"], 1.3, 2.0, 7),
    ("barriers", ["barrier_jersey", "barrier_plastic", "barrier_police", "barrier_construction", "spike_strip",
                  "prop_boom_gate"], 5.6, 2.6, 3),
    ("small", ["prop_cone", "prop_bollard", "prop_bollard_light"], 1.0, 1.5, 3),
]


def do_layout():
    return P.layout(SHEETS, ROW_Y, 0.0)


def build_all(do_export=True):
    out = P.run(IDS, do_export=do_export)
    do_layout()
    return out
