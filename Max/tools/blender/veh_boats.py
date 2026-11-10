"""veh_boats - boats for NEON TIDE: boat_speed "Marlin", boat_dinghy, boat_police.

    import veh_boats as M; importlib.reload(M); print(M.build_all())

z = 0 is the waterline, front = +Y.  Parts: body / steering / motor / prop / lod1 / col_body.
`motor`: origin at the transom pivot, turns about local Z.  `prop`: origin on the propeller hub line, spins
about Y.  `steering`: origin at the wheel hub, local Y = column axis.
"""
import math
from mathutils import Vector, Matrix
import gta_kit as K
import veh_oth as U

CAT = "Boats"
rad = math.radians


# --------------------------------------------------------------------------- hull helpers
def _st(ST, y):
    """Linear interpolation of a hull station table [(y, B, Bc, zc, zk, zs), ...] at y
    (B = half beam at the sheer, Bc / zc = chine, zk = keel, zs = sheer height)."""
    if y <= ST[0][0]:
        return (y,) + tuple(ST[0][1:])
    if y >= ST[-1][0]:
        return (y,) + tuple(ST[-1][1:])
    for a, b in zip(ST, ST[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(6))
    return ST[-1]


def _hull_ring(st):
    """Open section gunwale(-X) .. keel .. gunwale(+X): 11 points / 10 sectors."""
    y, B, Bc, zc, zk, zs = st
    cf = min(0.045, max(0.0, (B - Bc) * 0.3))
    c2 = (Bc + cf, zc + cf * 0.4)
    s1 = (c2[0] + (B - c2[0]) * 0.60, c2[1] + (zs - c2[1]) * 0.60)
    s2 = (c2[0] + (B - c2[0]) * 0.84, c2[1] + (zs - c2[1]) * 0.84)
    h = [(0.0, zk), (Bc, zc), c2, s1, s2, (B, zs)]
    return [(-x, y, z) for x, z in reversed(h[1:])] + [(x, y, z) for x, z in h]


def _hull_cols(top, stripe, side, bottom):
    return [top, stripe, side, bottom, bottom, bottom, bottom, side, stripe, top]


def _cleat(mb, pos, yaw=0.0):
    with mb.at(pos, rot=(0, 0, yaw)):
        mb.box((0.028, 0.03, 0.03), (0, -0.035, 0.015), "chrome")
        mb.box((0.028, 0.03, 0.03), (0, 0.035, 0.015), "chrome")
        mb.box((0.03, 0.17, 0.022), (0, 0, 0.04), "chrome")


def _outboard(mb, cowl="black_gloss", accent="aluminum", leg="gunmetal", tiller=False):
    """Outboard motor in local coordinates: origin = top of the clamp bracket on the transom edge, the motor
    hangs off toward -Y.  Gear-case centre line at z = -0.77, propeller hub seat at (0, -0.37, -0.77)."""
    mb.box((0.18, 0.10, 0.26), (0, -0.01, -0.10), "steel_dark")
    mb.box((0.10, 0.12, 0.30), (0, -0.10, -0.04), leg)
    mb.box((0.12, 0.21, 0.72), (0, -0.20, -0.25), leg, taper=(1.25, 1.2))
    cy = -0.21
    rings = [U.zring(0, cy, 0.10, 0.105, 0.19, 10, 3.0), U.zring(0, cy, 0.17, 0.135, 0.24, 10, 3.0),
             U.zring(0, cy - 0.005, 0.37, 0.14, 0.245, 10, 3.0), U.zring(0, cy - 0.005, 0.41, 0.14, 0.245, 10, 3.0),
             U.zring(0, cy - 0.01, 0.52, 0.132, 0.23, 10, 3.0), U.zring(0, cy - 0.015, 0.63, 0.10, 0.17, 10, 2.6)]
    cc = [leg, cowl, accent, cowl, cowl]
    U.loft(mb, rings, lambda i, k: cc[max(0, min(4, i))], smooth=True, sharp=40.0, cap_color=(leg, cowl))
    mb.box((0.18, 0.36, 0.014), (0, -0.22, -0.62), leg, taper=(0.9, 0.9))
    mb.box((0.05, 0.17, 0.16), (0, -0.20, -0.70), leg)
    U.lathe(mb, [(0.19, 0.0), (0.13, 0.045), (-0.04, 0.056), (-0.15, 0.042), (-0.17, 0.034)], leg, axis="Y",
            segs=8, pos=(0, -0.20, -0.77))
    mb.prism([(0.06, -0.80), (-0.12, -0.80), (-0.10, -0.94)], 0.016, leg, plane="YZ", pos=(0, -0.20, 0))
    if tiller:
        mb.tube([(0, -0.06, 0.20), (0, 0.30, 0.26), (0, 0.52, 0.27)], 0.016, "steel_dark", segs=5)
        mb.tube([(0, 0.40, 0.268), (0, 0.54, 0.272)], 0.024, "rubber", segs=6)


def _propeller(mb, r=0.115, color="brass", blades=3):
    """Propeller in local coordinates: hub seat at the origin, axis Y, pointing aft (-Y)."""
    U.lathe(mb, [(0.0, 0.034), (-0.04, 0.03), (-0.07, 0.0)], color, axis="Y", segs=8)
    mb.cyl(0.034, 0.004, (0, 0.0, 0), color, axis="Y", segs=8)
    ln = r - 0.022
    for i in range(blades):
        with mb.at((0, -0.025, 0), rot=(0, i * 360.0 / blades, 0)):
            mb.box((0.085, 0.012, ln), (0, 0, 0.022 + ln * 0.5), color, rot=(0, 0, 35.0), taper=(0.75, 1.0))


# =========================================================================== boat_speed "Marlin"
ST_SPEED = [
    # y,     B,    Bc,    zc,    zk,    zs
    (-3.15, 1.16, 1.05, -0.12, -0.36, 0.72),
    (-1.50, 1.21, 1.085, -0.10, -0.42, 0.75),
    (0.30, 1.21, 1.07, -0.06, -0.45, 0.75),
    (1.60, 1.085, 0.895, 0.04, -0.43, 0.78),
    (2.60, 0.80, 0.565, 0.20, -0.34, 0.83),
    (3.20, 0.47, 0.28, 0.42, -0.15, 0.88),
    (3.55, 0.195, 0.09, 0.62, 0.20, 0.91),
    (3.67, 0.05, 0.02, 0.72, 0.52, 0.925),
]


def build_boat_speed(export=True):
    root = K.begin_asset("boat_speed", CAT)
    ST = ST_SPEED
    Y_AFT, Y_CK0, Y_CK1 = -3.15, -1.90, 1.55
    FLOOR = 0.12
    TIP = (0.0, 3.695, 0.93)
    ys = sorted(set([s[0] for s in ST] + [Y_CK0, Y_CK1]))

    def dk(y):
        st = _st(ST, y)
        B, zs = st[1], st[5]
        return B, B - min(0.06, B * 0.15), B - min(0.21, B * 0.45), zs

    mb = K.MB()
    # ---- hull shell, transom, rub rail
    rings = [_hull_ring(_st(ST, y)) for y in ys]
    hc = _hull_cols("@Paint1", "@Paint2", "@Paint1", "white_gloss")
    U.loft(mb, rings, lambda i, k: hc[k], closed=False, smooth=True, sharp=32.0, tip_end=TIP)
    U.face(mb, rings[0], "@Paint1", toward=(0, -1, 0))
    for sx in (-1, 1):
        pts = [(sx * (_st(ST, y)[1] + 0.01), y, _st(ST, y)[5] - 0.025) for y in ys] + [(0, 3.69, 0.905)]
        mb.tube(pts, 0.03, "rubber", segs=4)
    # ---- aft deck
    r = []
    for y in [y for y in ys if Y_AFT <= y <= Y_CK0]:
        B, T, I, zs = dk(y)
        r.append([(-B, y, zs), (-T, y, zs), (-I, y, zs), (I, y, zs), (T, y, zs), (B, y, zs)])
    U.loft(mb, r, lambda i, k: "@Paint2" if k in (0, 4) else "offwhite", closed=False, smooth=False,
           outward=(0, 0, 1))
    # ---- cockpit tray (side decks, coamings, sole)
    r = []
    for y in [y for y in ys if Y_CK0 <= y <= Y_CK1]:
        B, T, I, zs = dk(y)
        F = I - 0.02
        r.append([(-B, y, zs), (-T, y, zs), (-I, y, zs), (-F, y, FLOOR), (F, y, FLOOR), (I, y, zs), (T, y, zs),
                  (B, y, zs)])
    cols = ["@Paint2", "offwhite", "white_gloss", "wood_light", "white_gloss", "offwhite", "@Paint2"]
    U.loft(mb, r, lambda i, k: cols[k], closed=False, smooth=False, outward=(0, 0, 1))
    B, T, I, zs = dk(Y_CK0)
    U.face(mb, [(-I + 0.02, Y_CK0, FLOOR), (I - 0.02, Y_CK0, FLOOR), (I, Y_CK0, zs), (-I, Y_CK0, zs)],
           "white_gloss", toward=(0, 1, 0))
    B, T, I, zs = dk(Y_CK1)
    cr1 = 0.075 * min(1.0, B / 1.1)
    U.face(mb, [(-I + 0.02, Y_CK1, FLOOR), (I - 0.02, Y_CK1, FLOOR), (I, Y_CK1, zs), (0, Y_CK1, zs + cr1),
                (-I, Y_CK1, zs)], "white_gloss", toward=(0, -1, 0))
    # ---- foredeck (crowned) with tinted hatch
    r = []
    for y in [y for y in ys if y >= Y_CK1]:
        B, T, I, zs = dk(y)
        cr = 0.075 * min(1.0, B / 1.1)
        r.append([(-B, y, zs), (-T, y, zs), (-I, y, zs), (0, y, zs + cr), (I, y, zs), (T, y, zs), (B, y, zs)])
    U.loft(mb, r, lambda i, k: "@Paint2" if k in (0, 5) else "offwhite", closed=False, smooth=True, sharp=40.0,
           outward=(0, 0, 1), tip_end=TIP)

    def deck_z(x, y):
        B, T, I, zs = dk(y)
        cr = 0.075 * min(1.0, B / 1.1)
        return zs + cr * max(0.0, 1.0 - abs(x) / max(I, 1e-3))

    mb.box((0.54, 0.54, 0.03), (0, 2.38, deck_z(0, 2.38) - 0.004), "plastic_black", bevel=0.008)
    mb.box((0.44, 0.44, 0.034), (0, 2.38, deck_z(0, 2.38)), "glass_dark")
    # ---- wrap-around windscreen
    bpts = [(-1.02, 0.75), (-0.98, 1.30), (-0.60, 1.68), (0.60, 1.68), (0.98, 1.30), (1.02, 0.75)]
    base = [(x, y, deck_z(x, y) + 0.012) for x, y in bpts]
    top = [(-0.99, 0.52, 1.02), (-0.88, 0.90, 1.52), (-0.50, 1.20, 1.575), (0.50, 1.20, 1.575),
           (0.88, 0.90, 1.52), (0.99, 0.52, 1.02)]
    for i in range(5):
        mb.quad(base[i], base[i + 1], top[i + 1], top[i], "@Glass", double=True)
    mb.tube(top, 0.021, "chrome", segs=5)
    mb.tube(base, 0.02, "plastic_black", segs=4)
    for i in range(6):
        mb.tube([base[i], top[i]], 0.018, "chrome", segs=4)
    # ---- dash / helm
    dash = [(1.56, FLOOR), (1.56, 0.96), (1.36, 0.985), (1.22, 0.88), (1.26, 0.50), (1.26, FLOOR)]
    mb.prism(dash, 1.74, "white_gloss", plane="YZ",
             side_colors=[None, "plastic_black", "plastic_black", None, None, None])
    with mb.at((-0.52, 1.30, 0.962), rot=(-50, 0, 0)):
        mb.box((0.56, 0.026, 0.15), (0, 0, 0), "plastic_black")
        mb.box((0.13, 0.012, 0.085), (0, -0.016, 0), "screen_blue")
        for gx in (-0.17, 0.17):
            mb.cyl(0.048, 0.012, (gx, -0.016, 0), "white", axis="Y", segs=10)
            mb.cyl(0.012, 0.016, (gx, -0.016, 0), "red", axis="Y", segs=5)
    mb.box((0.07, 0.11, 0.05), (-0.17, 1.20, 0.86), "plastic_black")
    mb.tube([(-0.17, 1.20, 0.87), (-0.17, 1.13, 0.99)], 0.011, "chrome", segs=4)
    mb.sphere(0.024, (-0.17, 1.125, 1.0), "black", segs=6, rings=4)
    mb.tube([(0.40, 1.225, 0.80), (0.40, 1.17, 0.80), (0.72, 1.17, 0.80), (0.72, 1.225, 0.80)], 0.012, "chrome",
            segs=4)
    mb.box((0.46, 0.02, 0.62), (0.10, 1.252, 0.45), "wood_mid")
    mb.box((0.03, 0.02, 0.10), (-0.08, 1.238, 0.47), "chrome")
    # ---- seats
    seats = {}
    for name, sx in (("seat_driver", -1), ("seat_passenger", 1)):
        p = (sx * 0.52, 0.50, 0.62)
        seats[name] = U.seat(mb, p, w=0.50, d=0.50, back_h=0.58, color="offwhite", trim="@Paint2")
        mb.cyl(0.065, 0.36, (p[0], p[1], FLOOR), "chrome", base=True, segs=8)
        mb.cyl(0.15, 0.02, (p[0], p[1], FLOOR), "steel_dark", base=True, segs=8)
    by = -1.56
    mb.box((1.92, 0.50, 0.27), (0, by, FLOOR + 0.135), "white_gloss")
    U.bench(mb, (0, by, 0.52), w=1.92, d=0.50, back_h=0.36, color="offwhite", trim="@Paint2")
    seats["seat_rl"] = (-0.50, by, 0.52 + U.SEAT_HIP)
    seats["seat_rr"] = (0.50, by, 0.52 + U.SEAT_HIP)
    # ---- sun pad, cleats, fuel cap, stern light
    zs_pad = _st(ST, -2.45)[5]
    mb.box((1.80, 1.0, 0.03), (0, -2.45, zs_pad + 0.015), "@Paint2")
    mb.box((1.74, 0.94, 0.08), (0, -2.45, zs_pad + 0.065), "offwhite", bevel=0.03)
    _cleat(mb, (-0.30, 3.08, deck_z(0.30, 3.08)), 12)
    _cleat(mb, (0.30, 3.08, deck_z(0.30, 3.08)), -12)
    _cleat(mb, (-1.04, -2.98, _st(ST, -2.98)[5]))
    _cleat(mb, (1.04, -2.98, _st(ST, -2.98)[5]))
    mb.cyl(0.036, 0.012, (-1.05, -2.25, _st(ST, -2.25)[5] + 0.006), "chrome", segs=8)
    mb.tube([(0.96, -3.02, 0.72), (0.96, -3.02, 1.22)], 0.012, "chrome", segs=4)
    mb.cyl(0.03, 0.045, (0.96, -3.02, 1.24), "emis_always_white", segs=6)
    # ---- bow rail
    rail = []
    for y, h in ((1.82, 0.03), (2.05, 0.27), (2.60, 0.29), (3.10, 0.30), (3.45, 0.30)):
        B, T, I, zs = dk(y)
        rail.append((-(B - 0.075), y, zs + h))
    bow = (0.0, 3.63, 0.925 + 0.30)
    full = rail + [bow] + [(-x, y, z) for x, y, z in reversed(rail)]
    mb.tube(full, 0.016, "chrome", segs=5)
    for x, y, z in rail[2:] + [bow]:
        for sx in ((-1, 1) if x != 0 else (1,)):
            mb.tube([(sx * abs(x), y, z - 0.30 + 0.01), (sx * abs(x), y, z)], 0.012, "chrome", segs=4, caps=False)
    # ---- bow combination light (white ahead, red port, green starboard)
    lz = deck_z(0, 3.50) + 0.03
    mb.box((0.11, 0.09, 0.06), (0, 3.50, lz), "chrome",
           colors={"+y": "@LightHead", "-x": "led_red", "+x": "led_green"})
    # ---- outboard bracket / swim step
    step = [(-1.08, -3.14), (-1.08, -3.21), (-1.01, -3.26), (1.01, -3.26), (1.08, -3.21), (1.08, -3.14)]
    mb.prism(step, 0.16, "@Paint1", plane="XY", pos=(0, 0, 0.19), cap_colors=("white_gloss", "offwhite"))
    body = mb.to_object(root, "body")

    # ------------------------------------------------------------------ steering
    HUB = (-0.52, 1.13, 0.80)
    ms = K.MB()
    with ms.at(HUB, rot=(-25, 0, 0)):
        U.steering_wheel(ms, r=0.17, color="plastic_black", hub="chrome")
        ms.cyl(0.022, 0.13, (0, 0.065, 0), "steel_dark", axis="Y", segs=6)
    st_obj = ms.to_object(root, "steering")
    U.repivot(st_obj, HUB, (-25, 0, 0))

    # ------------------------------------------------------------------ motors + props
    MP = (0.0, -3.26, 0.27)
    mm = K.MB()
    mp = K.MB()
    for sx in (-1, 1):
        with mm.at((sx * 0.34, MP[1], MP[2])):
            _outboard(mm, cowl="black_gloss", accent="@Paint2")
        with mp.at((sx * 0.34, MP[1] - 0.37, MP[2] - 0.77)):
            _propeller(mp)
    mm.box((0.50, 0.05, 0.05), (0, MP[1] - 0.03, MP[2] + 0.06), "steel_dark")
    motor = mm.to_object(root, "motor")
    U.repivot(motor, MP)
    prop = mp.to_object(root, "prop")
    U.repivot(prop, (0.0, MP[1] - 0.37, MP[2] - 0.77))

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    lr = []
    for y in (-3.15, -1.5, 1.6, 2.9, 3.6):
        _y, B, Bc, zc, zk, zs = _st(ST, y)
        lr.append([(0, y, zk), (Bc, y, zc), (B, y, zs), (-B, y, zs), (-Bc, y, zc)])
    lc = ["white", "@Paint1", "offwhite", "@Paint1", "white"]
    U.loft(ml, lr, lambda i, k: lc[k], smooth=False, tip_end=TIP, cap_color="@Paint1")
    ml.box((1.9, 3.35, 0.03), (0, -0.2, 0.765), "gray_dark")
    ml.box((2.0, 0.95, 0.80), (0, 1.22, 0.78), "glass_dark", base=True, taper=(0.9, 0.35), shear=(0, -0.3))
    ml.box((0.5, 0.5, 0.75), (-0.52, 0.42, 0.5), "offwhite")
    ml.box((0.5, 0.5, 0.75), (0.52, 0.42, 0.5), "offwhite")
    ml.box((1.9, 0.5, 0.55), (0, -1.6, 0.55), "offwhite")
    for sx in (-1, 1):
        ml.box((0.27, 0.44, 1.35), (sx * 0.34, -3.48, 0.22), "black")
    lod = ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hull
    pts = []
    for y in (-3.15, -0.5, 1.6, 2.9):
        _y, B, Bc, zc, zk, zs = _st(ST, y)
        pts += [(0, y, zk), (-Bc, y, zc), (Bc, y, zc), (-B, y, zs), (B, y, zs)]
    pts += [TIP, (0, 3.55, 0.2)]
    U.col_hull(root, "col_body", pts)

    # ------------------------------------------------------------------ markers
    for name, p in seats.items():
        K.marker(root, name, p)
    K.marker(root, "wake", (0, -3.15, 0.0))
    K.marker(root, "engine", (0, MP[1] - 0.22, MP[2] + 0.63))
    K.marker(root, "light_head_l", (0, 3.547, lz))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/boat_speed", CAT,
                        notes="Marlin speedboat. z=0 waterline, keel -0.45, gunwale +0.75, windscreen top 1.6. motor: "
                              "twin outboards, origin at the transom pivot (turn about local Z). prop: both propellers, "
                              "origin on the hub line between them (spin about Y). steering: local Y = column axis.",
                        extra={"wheel_radius": 0.0, "wheel_width": 0.0, "wheelbase": 0.0, "track": 0.0,
                               "clearance": 0.0, "doors": 0, "seats": 4, "draft": 0.45, "prop_offset_x": 0.34})
    return root


def build_all():
    out = [build_boat_speed()]
    K.save_master()
    return "\n".join(out)
