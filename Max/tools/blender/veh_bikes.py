"""veh_bikes - two-wheelers for NEON TIDE: bike_sport "Wasp" (naked sport bike) and bicycle "BMX".

    import veh_bikes as M; importlib.reload(M); print(M.build_all())

Contract (SPEC_VEHICLES.md): parts body / fork / wheel_f / wheel_r (/ crank) / lod1 / col_body, `fork` has its
origin on the steering axis at the steering head and is tilted so that its local Z IS the steering axis.
"""
import math
from mathutils import Vector, Matrix
import gta_kit as K
import veh_oth as U

CAT = "Motorcycles"
rad = math.radians


def _arc_band(mb, cy, cz, r_in, r_out, a0, a1, n, width, color, edge=0.012, inner_color=None):
    """Mudguard: curved band around (cy, cz) in the YZ plane (0 deg = +Y, 90 deg = up), rounded shoulders."""
    hw = width * 0.5
    rings = []
    for i in range(n + 1):
        a = rad(a0 + (a1 - a0) * i / n)
        ca, sa = math.cos(a), math.sin(a)
        sec = [(-hw, r_out - edge), (-hw * 0.55, r_out), (hw * 0.55, r_out), (hw, r_out - edge),
               (hw, r_in - edge), (-hw, r_in - edge)]
        rings.append([(x, cy + ca * r, cz + sa * r) for x, r in sec])
    ic = inner_color or color
    return U.loft(mb, rings, lambda i, k: ic if k == 4 else color, smooth=True, sharp=30.0, cap_color=color)


def _moto_wheel(mb, r, w, rim_r, disc_r=0.15, disc_sides=(), sprocket=False, segs=16, spokes=5):
    """Cast sport wheel centred on the origin, axle along X."""
    hw = w * 0.5
    sh = r - rim_r
    prof = [(-hw * 0.78, rim_r)]
    for k in range(5):
        u = math.pi * k / 4.0
        prof.append((-hw * math.cos(u), rim_r + sh * 0.32 + sh * 0.68 * math.sin(u)))
    prof.append((hw * 0.78, rim_r))
    U.lathe(mb, prof, "tire", axis="X", segs=segs)
    a = hw * 0.80
    rimp = [(-a, rim_r + 0.006), (-a, rim_r - 0.022), (0.0, rim_r - 0.042), (a, rim_r - 0.022), (a, rim_r + 0.006)]
    U.lathe(mb, rimp, "gunmetal", axis="X", segs=segs, colors=["aluminum", None, None, "aluminum"], flip=True)
    hub_r = 0.042
    r0 = hub_r * 0.7
    ln = (rim_r - 0.03) - r0
    for i in range(spokes):
        with mb.at((0, 0, 0), rot=(i * 360.0 / spokes + 18.0, 0, 0)):
            mb.box((0.032, 0.058, ln), (0, 0, r0 + ln * 0.5), "gunmetal", taper=(0.75, 0.55))
    mb.cyl(hub_r, w * 0.8 + 0.02, (0, 0, 0), "steel_dark", axis="X", segs=10)
    mb.cyl(0.017, w + 0.09, (0, 0, 0), "chrome", axis="X", segs=6)
    for sx in disc_sides:
        x = sx * (hw * 0.80 + 0.014)
        t = 0.004
        dp = [(x - t, disc_r - 0.055), (x - t, disc_r), (x + t, disc_r), (x + t, disc_r - 0.055),
              (x - t, disc_r - 0.055)]
        U.lathe(mb, dp, "steel", axis="X", segs=12, colors=[None, None, None, "-"])
        mb.cyl(disc_r - 0.043, 0.006, (x, 0, 0), "charcoal", axis="X", segs=5)
    if sprocket:
        x = -(hw * 0.80 + 0.016)
        mb.cyl(0.105, 0.006, (x, 0, 0), "steel", axis="X", segs=14)
        mb.cyl(0.06, 0.012, (x, 0, 0), "charcoal", axis="X", segs=8)


# =========================================================================== bike_sport
def build_bike_sport(export=True):
    root = K.begin_asset("bike_sport", CAT)
    R = 0.31
    WB = 1.43
    AFY, ARY = WB * 0.5, -WB * 0.5
    RAKE = 25.0
    sr, cr = math.sin(rad(RAKE)), math.cos(rad(RAKE))
    OFF = 0.035
    PZ = 0.84
    t_ax = (PZ + OFF * sr - R) / cr                 # distance pivot -> axle along the steering axis
    PY = AFY - OFF * cr - t_ax * sr
    P = (0.0, PY, PZ)
    MF = Matrix.Translation(Vector(P)) @ K._rot_matrix((RAKE, 0, 0))

    # ------------------------------------------------------------------ body
    mb = K.MB()
    # twin-spar frame + headstock
    spar = [(PY + 0.015, PZ + 0.045), (PY + 0.035, PZ - 0.065), (-0.02, 0.585), (-0.155, 0.47), (-0.165, 0.36),
            (-0.27, 0.36), (-0.29, 0.56), (-0.20, 0.705), (0.05, 0.80)]
    for sx in (-1, 1):
        mb.prism(spar, 0.03, "aluminum", plane="YZ", pos=(sx * 0.135, 0, 0))
    with mb.at(P, rot=(RAKE, 0, 0)):
        mb.cyl(0.036, 0.17, (0, 0, -0.03), "aluminum", segs=8)
        mb.box((0.27, 0.075, 0.12), (0, -0.045, -0.035), "aluminum", bevel=0.015)
    # engine
    mb.box((0.30, 0.38, 0.20), (0, 0.04, 0.36), "gunmetal", bevel=0.03)
    mb.box((0.22, 0.28, 0.05), (0, 0.04, 0.245), "steel_dark")
    with mb.at((0, 0.12, 0.45), rot=(-22, 0, 0)):
        mb.box((0.262, 0.165, 0.20), (0, 0, 0.10), "steel_dark")
        for j in range(3):
            mb.box((0.285, 0.19, 0.014), (0, 0, 0.045 + j * 0.048), "gunmetal")
        mb.box((0.25, 0.20, 0.05), (0, 0, 0.222), "red_dark", bevel=0.015)
    mb.cyl(0.092, 0.035, (0.158, -0.045, 0.375), "aluminum", axis="X", segs=12)
    mb.cyl(0.05, 0.05, (0.158, -0.045, 0.375), "steel_dark", axis="X", segs=8)
    mb.cyl(0.075, 0.04, (-0.158, 0.10, 0.36), "aluminum", axis="X", segs=10)
    mb.box((0.03, 0.15, 0.12), (-0.157, -0.11, 0.41), "charcoal")
    # radiator
    with mb.at((0, 0.315, 0.50), rot=(-12, 0, 0)):
        mb.box((0.30, 0.028, 0.23), (0, 0, 0), "black")
        mb.box((0.33, 0.02, 0.25), (0, -0.012, 0), "steel_dark")
    # belly pan
    belly = [
        U.hring(0.39, [(0.0, 0.245), (0.07, 0.255), (0.11, 0.33), (0.0, 0.335)]),
        U.hring(0.23, [(0.0, 0.150), (0.11, 0.170), (0.172, 0.34), (0.0, 0.345)]),
        U.hring(-0.10, [(0.0, 0.140), (0.11, 0.160), (0.172, 0.30), (0.0, 0.305)]),
        U.hring(-0.27, [(0.0, 0.205), (0.08, 0.215), (0.13, 0.28), (0.0, 0.285)]),
    ]
    U.loft(mb, belly, lambda i, k: "plastic_black" if k in (2, 3) else "@Paint2", smooth=False,
           cap_color="plastic_black")
    # tank
    tank = [
        U.sring(PY - 0.045, 0.865, 0.085, 0.065, 0.07, n=12, p=2.4),
        U.sring(0.30, 0.86, 0.172, 0.118, 0.12, n=12, p=2.6),
        U.sring(0.14, 0.85, 0.196, 0.156, 0.13, n=12, p=2.6),
        U.sring(-0.04, 0.84, 0.180, 0.128, 0.11, n=12, p=2.6),
        U.sring(-0.17, 0.82, 0.130, 0.072, 0.07, n=12, p=2.4),
    ]
    U.loft(mb, tank, lambda i, k: "@Paint2" if k in (5, 6) else "@Paint1", smooth=True, sharp=42.0,
           cap_color="plastic_black")
    mb.cyl(0.036, 0.014, (0, 0.17, 1.004), "chrome", segs=8)
    # side shrouds (radiator cowls) with accent
    sh = [(0.17, 0.83), (0.22, 0.66), (0.10, 0.44), (-0.13, 0.37), (-0.20, 0.50), (-0.06, 0.66), (0.0, 0.86)]
    ac = [(0.14, 0.74), (0.17, 0.66), (0.08, 0.50), (-0.08, 0.45), (0.0, 0.62)]
    for sx in (-1, 1):
        with mb.at((sx * 0.200, 0.30, 0), rot=(0, 0, sx * 7.0)):
            mb.prism(sh, 0.024, "@Paint1", plane="YZ")
            mb.prism(ac, 0.024, "@Paint2", plane="YZ", pos=(sx * 0.008, 0, 0))
    # seat, pillion pad, under-seat panel
    mb.box((0.30, 0.42, 0.075), (0, -0.37, 0.7625), "leather_black", bevel=0.025, taper=(0.86, 0.96))
    mb.box((0.25, 0.40, 0.11), (0, -0.37, 0.675), "plastic_black")
    mb.box((0.20, 0.25, 0.05), (0, -0.705, 0.897), "leather_black", bevel=0.018, rot=(-13, 0, 0))
    # tail unit with LED tail lamp
    tail = [
        U.hring(-0.48, [(0.0, 0.660), (0.140, 0.690), (0.168, 0.785), (0.120, 0.830), (0.0, 0.830)]),
        U.hring(-0.72, [(0.0, 0.745), (0.120, 0.770), (0.152, 0.845), (0.110, 0.885), (0.0, 0.885)]),
        U.hring(-0.94, [(0.0, 0.845), (0.070, 0.860), (0.094, 0.910), (0.070, 0.950), (0.0, 0.955)]),
        U.hring(-1.02, [(0.0, 0.898), (0.035, 0.904), (0.046, 0.930), (0.035, 0.955), (0.0, 0.960)]),
    ]

    def tail_col(i, k):
        if i >= 2:
            return "plastic_black" if k in (0, 7) else "@LightTail"
        return "plastic_black" if k in (0, 7) else "@Paint1"

    U.loft(mb, tail, tail_col, smooth=False, cap_color=("plastic_black", "@LightTail"))
    # plate hanger + rear indicators
    with mb.at((0, -0.895, 0.83), rot=(-20, 0, 0)):
        mb.box((0.05, 0.022, 0.22), (0, 0, -0.11), "plastic_black")
        mb.box((0.17, 0.008, 0.115), (0, -0.016, -0.20), "white")
        mb.box((0.19, 0.012, 0.135), (0, -0.006, -0.20), "plastic_black")
        mb.box((0.30, 0.016, 0.016), (0, 0, -0.105), "plastic_black")
        mb.box((0.05, 0.034, 0.028), (-0.165, 0, -0.105), "@LightIndL")
        mb.box((0.05, 0.034, 0.028), (0.165, 0, -0.105), "@LightIndR")
    # trellis subframe
    for sx in (-1, 1):
        mb.tube([(sx * 0.125, -0.19, 0.67), (sx * 0.115, -0.66, 0.775)], 0.012, "steel_dark", segs=5)
        mb.tube([(sx * 0.135, -0.25, 0.53), (sx * 0.115, -0.62, 0.76)], 0.012, "steel_dark", segs=5)
    # swing-arm, shock, chain, hugger
    arm = [(-0.15, 0.47), (-0.15, 0.385), (-0.70, 0.27), (-0.765, 0.285), (-0.765, 0.335), (-0.70, 0.35)]
    for sx in (-1, 1):
        mb.prism(arm, 0.03, "aluminum", plane="YZ", pos=(sx * 0.128, 0, 0))
    mb.box((0.23, 0.06, 0.07), (0, -0.31, 0.405), "aluminum")
    with mb.at((0, -0.275, 0.43), rot=(20, 0, 0)):
        mb.cyl(0.036, 0.19, (0, 0, 0.11), "yellow", segs=8)
        mb.cyl(0.018, 0.27, (0, 0, 0.12), "steel_dark", segs=6)
    cx = -0.092
    mb.tube([(cx, -0.11, 0.447), (cx, ARY, R + 0.103)], 0.011, "steel_dark", segs=4)
    mb.tube([(cx, -0.11, 0.365), (cx, ARY, R - 0.103)], 0.011, "steel_dark", segs=4)
    mb.cyl(0.042, 0.02, (cx, -0.11, 0.406), "steel_dark", axis="X", segs=8)
    _arc_band(mb, ARY, R, R + 0.022, R + 0.04, 28, 118, 6, 0.21, "plastic_black")
    # exhaust: headers, collector, muffler on the right
    for sx in (-0.075, 0.075):
        mb.tube([(sx, 0.245, 0.52), (sx, 0.30, 0.44), (sx * 0.9, 0.285, 0.34), (sx * 0.8, 0.21, 0.30)], 0.022,
                "steel", segs=6)
    mb.tube([(0.07, -0.20, 0.235), (0.17, -0.36, 0.27), (0.228, -0.47, 0.325)], 0.03, "steel", segs=7)
    m0 = Vector((0.232, -0.46, 0.322))
    m1 = Vector((0.262, -0.92, 0.535))
    md = (m1 - m0).normalized()
    mb.tube([tuple(m0), tuple(m1)], 0.058, "gunmetal", segs=10)
    mb.tube([tuple(m0 - md * 0.004), tuple(m0 + md * 0.03)], 0.062, "chrome", segs=10)
    mb.tube([tuple(m1 - md * 0.05), tuple(m1 + md * 0.006)], 0.062, "chrome", segs=10)
    mb.tube([tuple(m1), tuple(m1 + md * 0.022)], 0.04, "black", segs=8)
    ex_tip = tuple(m1 + md * 0.022)
    mb.box((0.012, 0.20, 0.06), tuple((m0 + m1) * 0.5 + Vector((0.058, 0, 0.012))), "plastic_black",
           rot=(-24.8, 0, -3.5))
    # foot pegs, hangers, levers, side stand
    for sx in (-1, 1):
        mb.prism([(-0.20, 0.50), (-0.30, 0.50), (-0.315, 0.375), (-0.26, 0.365)], 0.012, "aluminum", plane="YZ",
                 pos=(sx * 0.166, 0, 0))
        mb.cyl(0.013, 0.09, (sx * 0.215, -0.287, 0.39), "steel_dark", axis="X", segs=6)
        mb.tube([(sx * 0.19, -0.27, 0.385), (sx * 0.205, -0.13, 0.372)], 0.008, "steel_dark", segs=4)
        mb.cyl(0.011, 0.05, (sx * 0.225, -0.125, 0.372), "steel_dark", axis="X", segs=5)
        mb.tube([(sx * 0.13, -0.50, 0.675), (sx * 0.19, -0.57, 0.53)], 0.012, "aluminum", segs=4)
        mb.cyl(0.012, 0.075, (sx * 0.215, -0.57, 0.53), "steel_dark", axis="X", segs=5)
    mb.tube([(-0.15, -0.09, 0.265), (-0.20, -0.37, 0.185)], 0.012, "steel_dark", segs=5)
    mb.box((0.05, 0.07, 0.012), (-0.215, -0.385, 0.18), "steel_dark", rot=(15, 0, 0))
    body = mb.to_object(root, "body")

    # ------------------------------------------------------------------ fork (local Z = steering axis)
    mf = K.MB()
    with mf.at(P, rot=(RAKE, 0, 0)):
        for sx in (-1, 1):
            x = sx * 0.105
            mf.cyl(0.027, 0.38, (x, OFF, -0.12), "gold", segs=8)
            mf.cyl(0.020, 0.27, (x, OFF, -0.43), "chrome", segs=8)
            mf.box((0.042, 0.065, 0.075), (x, OFF, -t_ax + 0.005), "steel_dark")
            mf.box((0.04, 0.05, 0.085), (sx * 0.072, OFF - 0.068, -t_ax + 0.115), "red")
            mf.box((0.03, 0.03, 0.03), (sx * 0.083, OFF - 0.012, -t_ax + 0.335), "plastic_black")
        mf.box((0.275, 0.115, 0.03), (0, OFF * 0.5, 0.05), "steel_dark", bevel=0.008)
        mf.box((0.275, 0.115, 0.036), (0, OFF * 0.5, -0.115), "steel_dark", bevel=0.008)
        mf.cyl(0.022, 0.02, (0, 0, 0.075), "chrome", segs=6)
        bar = [(-0.35, -0.085, 0.09), (-0.17, -0.01, 0.108), (0.17, -0.01, 0.108), (0.35, -0.085, 0.09)]
        mf.tube(bar, 0.013, "steel_dark", segs=6)
        hands = {}
        for sx in (-1, 1):
            e = Vector((sx * 0.35, -0.085, 0.09))
            b = Vector((sx * 0.17, -0.01, 0.108))
            d = (b - e).normalized()
            mf.tube([tuple(e), tuple(e + d * 0.125)], 0.019, "rubber", segs=8)
            mf.tube([tuple(e - d * 0.018), tuple(e)], 0.021, "chrome", segs=8)
            hands[sx] = MF @ (e + d * 0.062)
            mf.box((0.035, 0.045, 0.04), (sx * 0.06, -0.005, 0.082), "aluminum")
            mf.tube([(sx * 0.225, -0.035, 0.105), (sx * 0.24, 0.035, 0.098), (sx * 0.365, 0.0, 0.086)], 0.006,
                    "chrome", segs=4)
            mf.box((0.04, 0.032, 0.032), (sx * 0.20, 0.012, 0.128), "plastic_black")
            mf.tube([(sx * 0.215, -0.005, 0.115), (sx * 0.30, 0.02, 0.245), (sx * 0.345, 0.012, 0.275)], 0.007,
                    "plastic_black", segs=4)
            mf.box((0.115, 0.022, 0.062), (sx * 0.375, 0.012, 0.29), "plastic_black", colors={"-y": "mirror"})
    # head-lamp cowl, fly screen, dash, front indicators (world aligned)
    def lens_y(z):
        return 0.672 - (0.85 - z) * 0.30
    cowl = [
        U.hring(0.50, [(0.0, 0.700), (0.100, 0.715), (0.140, 0.800), (0.105, 0.905), (0.0, 0.925)]),
        U.hring(0.60, [(0.0, 0.690), (0.095, 0.710), (0.130, 0.795), (0.090, 0.880), (0.0, 0.900)]),
        [(x, lens_y(z), z) for x, _y, z in
         U.hring(0.0, [(0.0, 0.722), (0.062, 0.738), (0.088, 0.795), (0.058, 0.842), (0.0, 0.852)])],
    ]
    U.loft(mf, cowl, lambda i, k: "@Paint1" if i == 0 else "plastic_black", smooth=False,
           cap_color=("plastic_black", "@LightHead"))
    mf.quad((-0.088, 0.598, 0.884), (0.088, 0.598, 0.884), (0.062, 0.50, 1.0), (-0.062, 0.50, 1.0), "@Glass",
            double=True)
    mf.box((0.15, 0.03, 0.075), (0, 0.488, 0.935), "plastic_black", rot=(-28, 0, 0), colors={"-y": "screen_blue"})
    mf.box((0.05, 0.036, 0.03), (-0.175, 0.56, 0.80), "@LightIndL")
    mf.box((0.05, 0.036, 0.03), (0.175, 0.56, 0.80), "@LightIndR")
    mf.box((0.32, 0.016, 0.016), (0, 0.555, 0.80), "plastic_black")
    # front mudguard
    _arc_band(mf, AFY, R, R + 0.022, R + 0.042, 30, 130, 7, 0.15, "@Paint1", inner_color="plastic_black")
    fork = mf.to_object(root, "fork")
    U.repivot(fork, P, (RAKE, 0, 0))

    # ------------------------------------------------------------------ wheels
    mw = K.MB()
    _moto_wheel(mw, R, 0.12, 0.225, disc_r=0.15, disc_sides=(-1, 1))
    wf = mw.to_object(root, "wheel_f")
    wf.location = (0, AFY, R)
    mw = K.MB()
    _moto_wheel(mw, R, 0.19, 0.225, disc_r=0.115, disc_sides=(1,), sprocket=True)
    wr = mw.to_object(root, "wheel_r")
    wr.location = (0, ARY, R)

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    ml.cyl(R, 0.12, (0, AFY, R), "tire", axis="X", segs=8, cap_color="gunmetal")
    ml.cyl(R, 0.19, (0, ARY, R), "tire", axis="X", segs=8, cap_color="gunmetal")
    ml.prism([(0.40, 0.84), (0.42, 0.40), (0.30, 0.18), (-0.25, 0.18), (-0.30, 0.50), (-0.20, 0.72)], 0.28,
             "gunmetal", plane="YZ", side_colors=[None, "@Paint2", "@Paint2", None, None, None])
    ml.box((0.36, 0.56, 0.25), (0, 0.11, 0.865), "@Paint1", taper=(0.7, 0.8))
    ml.prism([(-0.16, 0.80), (-0.16, 0.68), (-0.55, 0.68), (-1.02, 0.90), (-1.02, 0.96), (-0.60, 0.90),
              (-0.55, 0.80)], 0.27, "@Paint1", plane="YZ",
             side_colors=[None, "plastic_black", "plastic_black", "red", "leather_black", None, "leather_black"])
    with ml.at(P, rot=(RAKE, 0, 0)):
        for sx in (-1, 1):
            ml.box((0.05, 0.05, 0.66), (sx * 0.105, OFF, -0.27), "steel_dark")
        ml.box((0.72, 0.04, 0.04), (0, -0.03, 0.10), "plastic_black")
    ml.box((0.25, 0.17, 0.21), (0, 0.585, 0.80), "@Paint1", colors={"+y": "white"})
    ml.box((0.10, 0.50, 0.11), (0.25, -0.69, 0.43), "gunmetal", rot=(-24.8, 0, 0))
    ml.box((0.28, 0.58, 0.07), (0, -0.44, 0.37), "aluminum", rot=(13, 0, 0))
    lod = ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hull
    pts = []
    for z, hw, y0, y1 in ((0.26, 0.15, -0.72, 0.52), (0.62, 0.24, -0.92, 0.62), (1.0, 0.17, -1.0, 0.56)):
        pts += [(-hw, y0, z), (hw, y0, z), (-hw, y1, z), (hw, y1, z)]
    U.col_hull(root, "col_body", pts)

    # ------------------------------------------------------------------ markers
    K.marker(root, "seat_driver", (0, -0.36, 0.80 + U.SEAT_HIP))
    K.marker(root, "seat_passenger", (0, -0.705, 0.925 + U.SEAT_HIP))
    K.marker(root, "light_head_l", (0, lens_y(0.79) + 0.004, 0.79))
    K.marker(root, "light_tail_l", (0, -1.024, 0.93))
    K.marker(root, "exhaust", ex_tip)
    K.marker(root, "engine", (0, 0.10, 0.70))
    K.marker(root, "hand_l", tuple(hands[-1]))
    K.marker(root, "hand_r", tuple(hands[1]))
    K.marker(root, "foot_l", (-0.215, -0.287, 0.405))
    K.marker(root, "foot_r", (0.215, -0.287, 0.405))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/bike_sport", CAT,
                        notes="Wasp naked sport bike. fork: origin on the steering axis at the steering head, local Z = "
                              "steering axis (rake 25 deg). Seat markers are hip points 0.25 above the cushion.",
                        extra={"wheel_radius": R, "wheel_width": 0.12, "wheel_width_rear": 0.19, "wheelbase": WB,
                               "track": 0.0, "clearance": 0.14, "doors": 0, "seats": 2, "rake_deg": RAKE})
    return root


# =========================================================================== bicycle
def _bmx_wheel(mb, r, w=0.056, rim_r=0.232, segs=16, spokes=12):
    hw = w * 0.5
    sh = r - rim_r
    prof = [(-hw * 0.7, rim_r)]
    for k in range(5):
        u = math.pi * k / 4.0
        prof.append((-hw * math.cos(u), rim_r + sh * 0.35 + sh * 0.65 * math.sin(u)))
    prof.append((hw * 0.7, rim_r))
    U.lathe(mb, prof, "tire", axis="X", segs=segs)
    a = hw * 0.72
    rimp = [(-a, rim_r + 0.004), (-a, rim_r - 0.016), (a, rim_r - 0.016), (a, rim_r + 0.004)]
    U.lathe(mb, rimp, "aluminum", axis="X", segs=segs, flip=True)
    mb.cyl(0.021, 0.085, (0, 0, 0), "steel_dark", axis="X", segs=8)
    mb.cyl(0.03, 0.006, (-0.034, 0, 0), "steel", axis="X", segs=8)
    mb.cyl(0.03, 0.006, (0.034, 0, 0), "steel", axis="X", segs=8)
    for i in range(spokes):
        a0 = 2.0 * math.pi * i / spokes
        sx = -1 if i % 2 == 0 else 1
        a1 = a0 + (0.5 if i % 4 < 2 else -0.5)        # crossed lacing
        p0 = (sx * 0.034, math.cos(a0) * 0.028, math.sin(a0) * 0.028)
        p1 = (0.0, math.cos(a1) * (rim_r - 0.012), math.sin(a1) * (rim_r - 0.012))
        mb.tube([p0, p1], 0.0035, "steel", segs=3, caps=False)


def build_bicycle(export=True):
    root = K.begin_asset("bicycle", CAT)
    R = 0.28
    WB = 1.14
    AFY, ARY = WB * 0.5, -WB * 0.5
    RAKE = 16.0
    sr, cr = math.sin(rad(RAKE)), math.cos(rad(RAKE))
    OFF = 0.03
    PZ = 0.625
    t_ax = (PZ + OFF * sr - R) / cr
    PY = AFY - OFF * cr - t_ax * sr
    P = (0.0, PY, PZ)
    MF = Matrix.Translation(Vector(P)) @ K._rot_matrix((RAKE, 0, 0))
    BB = (0.0, -0.20, 0.30)

    def onaxis(t):
        """Point on the steering axis, t metres above the pivot."""
        return (0.0, PY - sr * t, PZ + cr * t)

    # ------------------------------------------------------------------ body
    mb = K.MB()
    ht_top, ht_bot = onaxis(0.055), onaxis(-0.06)
    st_top = (0.0, -0.275, 0.53)
    mb.tube([ht_bot, ht_top], 0.026, "@Paint1", segs=8)
    mb.tube([onaxis(0.058), onaxis(0.07)], 0.029, "steel_dark", segs=8)
    mb.tube([onaxis(-0.072), onaxis(-0.06)], 0.029, "steel_dark", segs=8)
    mb.tube([onaxis(0.03), (0, st_top[1] + 0.01, st_top[2] - 0.012)], 0.0175, "@Paint1", segs=7)       # top tube
    mb.tube([onaxis(-0.04), (0, BB[1] + 0.01, BB[2] + 0.01)], 0.021, "@Paint1", segs=7)               # down tube
    mb.tube([BB, (0, st_top[1], st_top[2] + 0.03)], 0.0175, "@Paint1", segs=7)                        # seat tube
    mb.cyl(0.027, 0.074, BB, "@Paint1", axis="X", segs=8)
    for sx in (-1, 1):
        mb.tube([(sx * 0.03, BB[1] - 0.01, BB[2]), (sx * 0.062, ARY + 0.02, R)], 0.011, "@Paint1", segs=5)
        mb.tube([(sx * 0.02, st_top[1] - 0.004, st_top[2] - 0.02), (sx * 0.062, ARY + 0.02, R + 0.008)], 0.0095,
                "@Paint1", segs=5)
        mb.box((0.008, 0.06, 0.04), (sx * 0.064, ARY + 0.005, R), "@Paint1", bevel=0.003)             # dropout
        mb.cyl(0.02, 0.105, (sx * 0.122, ARY, R), "steel", axis="X", segs=8)                          # stunt peg
    mb.box((0.05, 0.02, 0.02), (0, -0.40, 0.445), "@Paint1")                                         # stay bridge
    # seat post + clamp + saddle
    mb.tube([(0, st_top[1], st_top[2] + 0.02), (0, -0.318, 0.675)], 0.012, "chrome", segs=6)
    mb.tube([(0, st_top[1], st_top[2] + 0.018), (0, st_top[1] - 0.004, st_top[2] + 0.04)], 0.022, "steel_dark",
            segs=7)
    saddle = [
        U.hring(-0.46, [(0.0, 0.690), (0.055, 0.694), (0.068, 0.716), (0.045, 0.732), (0.0, 0.735)]),
        U.hring(-0.39, [(0.0, 0.672), (0.060, 0.680), (0.070, 0.705), (0.048, 0.722), (0.0, 0.724)]),
        U.hring(-0.29, [(0.0, 0.676), (0.035, 0.682), (0.040, 0.702), (0.028, 0.716), (0.0, 0.718)]),
        U.hring(-0.19, [(0.0, 0.690), (0.016, 0.693), (0.020, 0.706), (0.014, 0.717), (0.0, 0.719)]),
    ]
    U.loft(mb, saddle, "leather_black", smooth=True, sharp=50.0)
    mb.box((0.03, 0.08, 0.02), (0, -0.335, 0.667), "steel_dark")
    # chain ring, chain, rear cog (drive side = right)
    dx = 0.052
    mb.cyl(0.088, 0.005, (dx, BB[1], BB[2]), "steel", axis="X", segs=14)
    mb.cyl(0.055, 0.007, (dx, BB[1], BB[2]), "@Paint2", axis="X", segs=6)
    mb.cyl(0.032, 0.012, (dx, ARY, R), "steel", axis="X", segs=8)
    mb.tube([(dx, BB[1], BB[2] + 0.088), (dx, ARY, R + 0.032)], 0.006, "steel_dark", segs=4)
    mb.tube([(dx, BB[1], BB[2] - 0.088), (dx, ARY, R - 0.032)], 0.006, "steel_dark", segs=4)
    body = mb.to_object(root, "body")

    # ------------------------------------------------------------------ fork + handlebar (local Z = steering axis)
    mf = K.MB()
    hands = {}
    with mf.at(P, rot=(RAKE, 0, 0)):
        mf.cyl(0.015, 0.23, (0, 0, 0.02), "steel_dark", segs=6)                 # steerer
        mf.box((0.15, 0.05, 0.035), (0, 0.008, -0.09), "@Paint1", bevel=0.01)   # crown
        for sx in (-1, 1):
            mf.tube([(sx * 0.058, 0.008, -0.095), (sx * 0.064, OFF, -t_ax)], 0.014, "@Paint1", segs=6)
            mf.box((0.008, 0.05, 0.045), (sx * 0.066, OFF, -t_ax), "@Paint1", bevel=0.003)
            mf.cyl(0.02, 0.105, (sx * 0.124, OFF, -t_ax), "steel", axis="X", segs=8)     # front stunt pegs
        # stem + bar clamp
        mf.box((0.05, 0.075, 0.045), (0, 0.025, 0.115), "steel_dark", bevel=0.008)
        mf.cyl(0.02, 0.07, (0, 0.05, 0.115), "steel_dark", axis="X", segs=8)
        bz = 0.115
        bar = [(-0.36, -0.035, bz + 0.235), (-0.24, -0.02, bz + 0.235), (-0.085, 0.05, bz), (0.085, 0.05, bz),
               (0.24, -0.02, bz + 0.235), (0.36, -0.035, bz + 0.235)]
        mf.tube(bar, 0.0125, "chrome", segs=6)
        mf.tube([(-0.165, 0.014, bz + 0.12), (0.165, 0.014, bz + 0.12)], 0.0095, "chrome", segs=5)
        for sx in (-1, 1):
            e = Vector((sx * 0.36, -0.035, bz + 0.235))
            b = Vector((sx * 0.24, -0.02, bz + 0.235))
            d = (b - e).normalized()
            mf.tube([tuple(e), tuple(e + d * 0.115)], 0.018, "rubber", segs=8)
            mf.tube([tuple(e - d * 0.008), tuple(e + d * 0.006)], 0.023, "rubber", segs=8)
            hands[sx] = MF @ (e + d * 0.058)
        # rear brake lever (right)
        mf.tube([(0.235, -0.02, bz + 0.225), (0.245, 0.04, bz + 0.21), (0.345, 0.012, bz + 0.212)], 0.005,
                "steel_dark", segs=4)
    fork = mf.to_object(root, "fork")
    U.repivot(fork, P, (RAKE, 0, 0))

    # ------------------------------------------------------------------ wheels (shared mesh)
    mw = K.MB()
    _bmx_wheel(mw, R)
    wf = mw.to_object(root, "wheel_f")
    wf.location = (0, AFY, R)
    K.link_copy(wf, root, "wheel_r", (0, ARY, R))

    # ------------------------------------------------------------------ crank (spins about X at the bottom bracket)
    mc = K.MB()
    mc.cyl(0.011, 0.17, (0, 0, 0), "steel", axis="X", segs=6)
    CL = 0.165
    for sx, dy in ((1, 1), (-1, -1)):
        mc.box((0.016, CL + 0.03, 0.03), (sx * 0.078, dy * CL * 0.5, 0), "steel_dark", bevel=0.005)
        mc.cyl(0.007, 0.06, (sx * 0.112, dy * CL, 0), "steel", axis="X", segs=5)
        mc.box((0.085, 0.088, 0.022), (sx * 0.142, dy * CL, 0), "plastic_black", bevel=0.005)
        mc.box((0.075, 0.07, 0.03), (sx * 0.142, dy * CL, 0), "steel_dark")
    crank = mc.to_object(root, "crank")
    crank.location = BB

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    for y in (AFY, ARY):
        rings = []
        for i in range(9):
            a = 2.0 * math.pi * i / 8.0
            ca, sa = math.cos(a), math.sin(a)
            rings.append([(x, y + ca * rr, R + sa * rr) for x, rr in ((-0.025, R), (0.025, R), (0.025, R - 0.05),
                                                                        (-0.025, R - 0.05))])
        U.loft(ml, rings[:-1] + [rings[0]], "tire", cap_start=False, cap_end=False, smooth=False)

    def bar_box(a, b, t, color):
        a, b = Vector(a), Vector(b)
        d = b - a
        ln = d.length
        pitch = math.degrees(math.atan2(d.z, math.hypot(d.x, d.y)))
        yaw = math.degrees(math.atan2(-d.x, d.y))
        ml.box((t, ln, t), tuple((a + b) * 0.5), color, rot=(pitch, 0, yaw))

    bar_box(onaxis(0.03), (0, st_top[1], st_top[2]), 0.04, "@Paint1")
    bar_box(onaxis(-0.04), BB, 0.045, "@Paint1")
    bar_box(BB, (0, -0.318, 0.675), 0.04, "@Paint1")
    bar_box(BB, (0, ARY, R), 0.05, "@Paint1")
    bar_box((0, st_top[1], st_top[2]), (0, ARY, R), 0.04, "@Paint1")
    bar_box(onaxis(0.34), (0, AFY, R), 0.045, "@Paint1")
    hb = MF @ Vector((0, -0.02, 0.35))
    ml.box((0.72, 0.035, 0.035), tuple(hb), "chrome")
    ml.box((0.13, 0.27, 0.045), (0, -0.33, 0.705), "leather_black")
    ml.box((0.30, 0.10, 0.03), BB, "steel_dark")
    lod = ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hull
    pts = []
    for z, hw, y0, y1 in ((0.20, 0.10, -0.55, 0.50), (0.62, 0.16, -0.62, 0.56), (0.98, 0.30, 0.22, 0.42)):
        pts += [(-hw, y0, z), (hw, y0, z), (-hw, y1, z), (hw, y1, z)]
    pts += [(-0.07, -0.47, 0.74), (0.07, -0.47, 0.74)]
    U.col_hull(root, "col_body", pts)

    # ------------------------------------------------------------------ markers
    K.marker(root, "seat_driver", (0, -0.33, 0.725 + U.SEAT_HIP))
    K.marker(root, "hand_l", tuple(hands[-1]))
    K.marker(root, "hand_r", tuple(hands[1]))
    K.marker(root, "foot_l", (-0.142, BB[1] - CL, BB[2] + 0.02))
    K.marker(root, "foot_r", (0.142, BB[1] + CL, BB[2] + 0.02))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/bicycle", CAT,
                        notes="BMX. fork: local Z = steering axis (rake 16 deg). crank: origin at the bottom bracket, "
                              "spins about X, rest pose = cranks level (right pedal forward). Chain ring is part of "
                              "body as specified. seat_driver = hip point 0.25 above the saddle.",
                        extra={"wheel_radius": R, "wheel_width": 0.056, "wheelbase": WB, "track": 0.0,
                               "clearance": 0.19, "doors": 0, "seats": 1, "rake_deg": RAKE})
    return root


def build_all():
    out = [build_bike_sport(), build_bicycle()]
    K.save_master()
    return "\n".join(out)
