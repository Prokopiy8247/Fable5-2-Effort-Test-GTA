"""veh_air2 - plane_prop "Kestrel" and heli_police "Skywatch" (same conventions / helpers as veh_air.py).

    import veh_air2 as A2; importlib.reload(A2)
    print(A2.build_plane_prop())        # build + export + manifest (vehicles_other.json)
    print(A2.build_heli_police())

Front = +Y, z = 0 at the bottom of the wheels / skids, level attitude.
Plane: origin on the ground under the wing's quarter chord (the game puts the centre of mass 0.1 m ahead of the
origin); prop origin at the hub (spins about Y); control surfaces have their origin on the hinge line with their
local X (rudder: local Z) along it - both ailerons keep local X pointing to the right (+X);
door_fl hinged at its front edge (opens about local Z).
"""
import math
from mathutils import Vector
import gta_kit as K
import veh_oth as U
import veh_air as A
import veh_cars as C

GL = "@Glass"
P1, P2 = "@Paint1", "@Paint2"


def _door(root, part, rings, cellfn, seg, k0, k1, sill_k, hinge, hk, handle_rot):
    """Door = cells (seg, k0..k1-1) of a fuselage ring grid as its own object hinged at `hinge` (copy of
    veh_air._door_from_grid with an explicit handle sector hk = (k_a, k_b))."""
    md = K.MB()
    U.shell(md, rings, cellfn, thickness=0.035, inner="@D:plastic_gray", sharp=40.0)
    loop = [(seg, k) for k in range(k0, k1 + 1)] + [(seg + 1, k) for k in range(k1, k0 - 1, -1)] + [(seg, k0)]

    def gp(i, k):
        x, y, z = U.grid_point(rings, i, k, 0.006)
        return (x, y - 0.024 if i == seg else y + 0.024, z)

    md.tube([gp(i, k) for i, k in loop], 0.018, "plastic_black", segs=4)
    md.tube([gp(seg, sill_k), gp(seg + 1, sill_k)], 0.016, "plastic_black", segs=4)
    pa = Vector(U.grid_point(rings, seg, hk[0], 0.014)).lerp(Vector(U.grid_point(rings, seg + 1, hk[0], 0.014)), 0.78)
    pb = Vector(U.grid_point(rings, seg, hk[1], 0.014)).lerp(Vector(U.grid_point(rings, seg + 1, hk[1], 0.014)), 0.78)
    md.box((0.03, 0.14, 0.04), tuple((pa + pb) * 0.5), "chrome", rot=(0, handle_rot, 0))
    obj = md.to_object(root, part)
    U.repivot(obj, hinge)
    return obj


def _axis_rot(d):
    """Euler XYZ (deg) that turns local +X onto direction d."""
    d = Vector(d).normalized()
    return (0.0, -math.degrees(math.asin(max(-1.0, min(1.0, d.z)))), math.degrees(math.atan2(d.y, d.x)))


# =========================================================================== plane_prop "Kestrel"
KS = [
    # y,     cz,   w,    ht,   hb,   p
    (2.27, 1.20, 0.13, 0.13, 0.13, 2.0),     # 0 cowl lip (spinner base)
    (2.22, 1.20, 0.40, 0.36, 0.38, 2.4),     # 1 cowl front
    (1.95, 1.22, 0.50, 0.46, 0.44, 2.6),     # 2
    (1.30, 1.30, 0.55, 0.52, 0.47, 2.8),     # 3 firewall / windscreen base
    (0.90, 1.40, 0.57, 0.62, 0.56, 3.0),     # 4 windscreen
    (0.50, 1.45, 0.57, 0.62, 0.60, 3.2),     # 5 A pillar, door front (hinge)
    (-0.45, 1.45, 0.57, 0.62, 0.60, 3.2),    # 6 B pillar, door rear
    (-1.20, 1.48, 0.53, 0.59, 0.56, 3.0),    # 7 rear windows
    (-1.90, 1.53, 0.42, 0.52, 0.42, 2.8),    # 8 cabin end / baggage bulkhead
    (-3.10, 1.60, 0.27, 0.34, 0.25, 2.4),    # 9
    (-4.20, 1.64, 0.17, 0.22, 0.16, 2.2),    # 10 fin root
    (-5.40, 1.70, 0.06, 0.08, 0.06, 2.0),    # 11 tail end
]
DIH = math.tan(math.radians(1.7))
W_ZR = 2.16                  # wing chord line height at the root
S_AIL = 0.75                 # aileron / flap hinge (chord fraction)
AIL = (2.62, 4.88)           # aileron span
TP_YH, TP_Z, T_S = -5.05, 1.70, 0.55      # elevator hinge line (y, z), chord fraction
F_S = 0.62                   # rudder hinge chord fraction
HUB = (0.0, 2.30, 1.20)
MAIN = (1.20, -0.20, 0.24)   # main wheel centre (x, y, r)
NOSE = (1.65, 0.19)          # nose wheel (y, r)


def w_le(x):
    ax = abs(x)
    return 0.50 if ax <= 2.6 else 0.50 - 0.12 * (ax - 2.6) / 2.8


def w_ch(x):
    ax = abs(x)
    return 1.55 if ax <= 2.6 else 1.55 - 0.43 * (ax - 2.6) / 2.8


def w_z(x):
    return W_ZR + abs(x) * DIH


def wring(x, s0=0.0, s1=1.0, t=0.13):
    return U.wing_ring(x, w_le(x), w_z(x), w_ch(x), t=t, camber=0.02, s0=s0, s1=s1)


def w_hinge(x):
    c = w_ch(x)
    return Vector((x, w_le(x) - S_AIL * c, w_z(x) + 0.02 * 4.0 * S_AIL * (1.0 - S_AIL) * c))


def t_ch(x):
    return 0.90 - 0.24 * abs(x) / 1.70


def tring(x, s0=0.0, s1=1.0):
    ch = t_ch(x)
    return U.wing_ring(x, TP_YH + T_S * ch, TP_Z, ch, t=0.10, camber=0.0, s0=s0, s1=s1)


def f_le(z):
    return -4.10 - 0.90 * (z - 1.80) / 1.05


def f_ch(z):
    return 1.40 - 0.60 * (z - 1.80) / 1.05


def fring(z, s0=0.0, s1=1.0):
    return U.wing_ring(z, f_le(z), 0.0, f_ch(z), t=0.10, camber=0.0, s0=s0, s1=s1, vertical=True)


def f_hinge(z):
    return Vector((0.0, f_le(z) - F_S * f_ch(z), z))


def _kestrel_cell(i, k, door=None):
    rd = (i == 5 and 2 <= k <= 5)
    ld = (i == 5 and 10 <= k <= 13)
    if door == "fl":
        return (GL if k <= 11 else (P2 if k == 12 else P1)) if ld else None
    if ld:
        return None
    if rd:                                   # right door is fixed (only door_fl opens)
        return GL if k >= 4 else (P2 if k == 3 else P1)
    if i in (3, 4) and 5 <= k <= 10:         # windscreen
        return GL
    if i == 6 and k in (4, 5, 10, 11):       # rear side windows
        return GL
    if i == 7 and k in (5, 10):              # aft quarter windows
        return GL
    if 2 <= i <= 10 and k in (3, 12):        # cheat line
        return P2
    return P1


def build_plane_prop(export=True):
    root = K.begin_asset("plane_prop", "Airplanes")
    S = KS
    rings = [U.sring(y, cz, w, ht, hb, n=16, p=p) for (y, cz, w, ht, hb, p) in S]
    ZF = 0.95                # cabin floor
    ZS = 1.22                # seat cushion top
    mb = K.MB()
    sh = U.shell(mb, rings, lambda i, k: _kestrel_cell(i, k), thickness=0.035, inner="@D:plastic_gray",
                 sharp=40.0, liner=lambda i, k: 3 <= i <= 7)
    Q = sh["Q"]
    U.face(mb, [tuple(q) for q in Q[3]], "@D:charcoal", toward=(0, -1, 0))
    U.face(mb, [tuple(q) for q in Q[8]], "@D:plastic_gray", toward=(0, 1, 0))
    U.face(mb, rings[0], P1, toward=(0, 1, 0))
    U.face(mb, rings[-1], P1, toward=(0, -1, 0))
    # ---- cabin floor
    fl = []
    for i in range(3, 9):
        q = Q[i]
        for k in range(0, 4):
            a, b = q[k], q[k + 1]
            if a.z <= ZF <= b.z:
                t = (ZF - a.z) / max(1e-6, b.z - a.z)
                fl.append([(-(a.x + (b.x - a.x) * t), a.y, ZF), ((a.x + (b.x - a.x) * t), a.y, ZF)])
                break
    U.loft(mb, fl, "@D:gray_dark", closed=False, smooth=False, outward=(0, 0, 1))

    # ---- window frames (tubes along grid lines)
    def frame(pts, r=0.018, dy=0.0):
        line = [U.grid_point(rings, i, k, 0.006) for i, k in pts]
        mb.tube([(x, y + dy, z) for x, y, z in line], r, "plastic_black", segs=4)

    frame([(3, k) for k in range(5, 12)])                    # windscreen bottom
    frame([(3, 8), (4, 8), (5, 8)])                          # centre post
    for kb, kt in ((4, 6), (12, 10)):
        frame([(3, kb + (1 if kb == 4 else -1)), (4, kb + (1 if kb == 4 else -1)), (5, kb + (1 if kb == 4 else -1))])
        frame([(6, kb), (7, kb)])
        frame([(6, kt), (7, kt)])
        step = 1 if kt > kb else -1
        frame([(6, k) for k in range(kb, kt + step, step)], dy=-0.024)
        frame([(7, k) for k in range(kb, kt + step, step)])
    frame([(5, k) for k in range(2, 7)], dy=-0.024)          # fixed right door outline
    frame([(5, 2), (6, 2)])
    frame([(5, 4), (6, 4)])
    # ---- wing: box to the hinge line, fixed flaps + tip trailing edges, struts, lights
    U.loft(mb, [wring(x, 0.0, S_AIL) for x in (-5.4, -4.9, -2.6, 0.0, 2.6, 4.9, 5.4)], P1, smooth=True,
           sharp=50.0, cap_color=P1)
    for sx in (1, -1):
        U.loft(mb, [wring(sx * x, S_AIL + 0.006, 1.0) for x in (0.42, 2.58)], P1, smooth=False, cap_color=P1)
        U.loft(mb, [wring(sx * x, S_AIL + 0.006, 1.0) for x in (4.92, 5.40)], P1, smooth=False, cap_color=P1)
        y0 = w_le(sx * 2.55) - 0.30 * w_ch(2.55)
        mb.tube([(sx * 0.52, y0 + 0.02, 1.02), (sx * 2.55, y0, w_z(2.55) - 0.07)], 0.032, "gray_light", segs=6)
        mb.box((0.05, 0.08, 0.05), (sx * 2.55, y0, w_z(2.55) - 0.07), "gray_dark")
        tip = Vector((sx * 5.40, w_le(5.4) - 0.25, w_z(5.4)))
        mb.box((0.03, 0.14, 0.06), (tip.x + sx * 0.02, tip.y, tip.z), "@LightIndR" if sx > 0 else "@LightIndL")
    lx = -1.80                                                # landing light in the left wing leading edge
    mb.box((0.22, 0.03, 0.07), (lx, w_le(lx) + 0.005, w_z(lx) - 0.012), "@LightHead")
    # ---- tail: stabiliser, fin, dorsal fillet, beacon
    U.loft(mb, [tring(x, 0.0, T_S) for x in (-1.70, 0.0, 1.70)], P1, smooth=True, sharp=50.0, cap_color=P1)
    U.loft(mb, [fring(z, 0.0, F_S) for z in (1.62, 2.85)], P1, smooth=True, sharp=50.0, cap_color=P1)
    mb.prism([(-3.10, 1.84), (-4.20, 1.84), (f_le(2.10), 2.10)], 0.05, P1, plane="YZ")
    mb.box((0.05, 0.10, 0.05), (0, f_le(2.85) - 0.25, 2.875), "led_red")
    # ---- cowling details: intakes, exhaust, nose gear, main gear
    for sx in (1, -1):
        mb.box((0.16, 0.03, 0.08), (sx * 0.24, 2.21, 1.36), "black")
    mb.cyl(0.035, 0.22, (0.22, 1.55, 0.80), "steel_dark", axis="Y", rot=(-25, 0, 0), segs=6, cap_color="black")
    ny, nr = NOSE
    mb.cyl(0.04, 0.46, (0, ny + 0.04, 0.62), "chrome", segs=8)
    mb.cyl(0.055, 0.12, (0, ny + 0.04, 0.82), "gray_dark", segs=8)
    for sx in (1, -1):
        mb.box((0.02, 0.06, 0.26), (sx * 0.075, ny, nr + 0.11), "gray_dark")
    mb.box((0.17, 0.08, 0.03), (0, ny + 0.02, nr + 0.24), "gray_dark")
    mx, my, mr = MAIN
    for sx in (1, -1):
        mb.tube([(sx * 0.40, my, 0.90), (sx * (mx - 0.10), my, mr + 0.02)], 0.038, "gray_light", segs=4)
        mb.cyl(0.03, 0.10, (sx * (mx - 0.07), my, mr), "steel_dark", axis="X", segs=6)
    # ---- interior: panel, yokes, seats
    with mb.at((0, 1.12, 1.60)):
        mb.box((1.00, 0.10, 0.30), (0, 0, 0), "@D:plastic_black")
        mb.box((1.04, 0.22, 0.04), (0, 0.02, 0.17), "@D:plastic_black")
        mb.box((0.26, 0.012, 0.16), (-0.26, -0.056, 0.02), "screen_blue")
        mb.box((0.26, 0.012, 0.16), (0.20, -0.056, 0.02), "screen_blue")
        for gx in (-0.42, 0.42, 0.0):
            mb.cyl(0.035, 0.012, (gx, -0.056, 0.0), "white", axis="Y", segs=8)
    for sx in (1, -1):
        mb.cyl(0.016, 0.26, (sx * 0.27, 0.94, 1.52), "@D:plastic_black", axis="Y", segs=6)
        mb.box((0.26, 0.04, 0.09), (sx * 0.27, 0.80, 1.53), "@D:plastic_black")
    seats = {}
    for name, sx in (("seat_driver", -1), ("seat_passenger", 1)):
        p = (sx * 0.27, 0.25, ZS)
        seats[name] = U.seat(mb, p, w=0.44, d=0.46, back_h=0.60, color="@D:fabric_gray", trim="@D:fabric_dark",
                             base_h=0.12)
        mb.box((0.30, 0.30, ZS - 0.12 - ZF), (p[0], p[1], (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
    by = -0.66
    mb.box((0.98, 0.42, ZS - 0.12 - ZF), (0, by, (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
    U.bench(mb, (0, by, ZS), w=1.00, d=0.44, back_h=0.56, color="@D:fabric_gray", trim="@D:fabric_dark",
            base_h=0.12)
    seats["seat_rl"] = (-0.27, by, ZS + U.SEAT_HIP)
    seats["seat_rr"] = (0.27, by, ZS + U.SEAT_HIP)
    mb.to_object(root, "body")

    # ------------------------------------------------------------------ door_fl (left, hinged at the A pillar)
    hy = S[5][0]
    _door(root, "door_fl", rings, lambda i, k: _kestrel_cell(i, k, "fl"), 5, 10, 14, 12,
          (rings[5][12][0], hy, rings[5][12][2]), (12, 13), -20.0)

    # ------------------------------------------------------------------ control surfaces
    for sx, part in ((1, "aileron_r"), (-1, "aileron_l")):
        ma = K.MB()
        U.loft(ma, [wring(sx * x, S_AIL + 0.006, 1.0) for x in AIL], P1, smooth=False, cap_color=P1)
        a, b = w_hinge(sx * AIL[0]), w_hinge(sx * AIL[1])
        d = (b - a) if sx > 0 else (a - b)
        U.repivot(ma.to_object(root, part), tuple(a), _axis_rot(d))
    me = K.MB()
    for sx in (1, -1):
        U.loft(me, [tring(sx * x, T_S + 0.01, 1.0) for x in (0.09, 1.70)], P1, smooth=False, cap_color=P1)
    U.repivot(me.to_object(root, "elevator"), (0.0, TP_YH, TP_Z))
    mru = K.MB()
    U.loft(mru, [fring(z, F_S + 0.01, 1.0) for z in (1.80, 2.85)], P2, smooth=False, cap_color=P2)
    h0, h1 = f_hinge(1.80), f_hinge(2.85)
    dv = h1 - h0
    U.repivot(mru.to_object(root, "rudder"), tuple(h0), (math.degrees(math.atan2(-dv.y, dv.z)), 0.0, 0.0))

    # ------------------------------------------------------------------ prop (origin at the hub, spins about Y)
    mp = K.MB()
    mp.cyl(0.16, 0.26, (0, 0.07, 0), "white", axis="Y", r2=0.03, segs=10)
    mp.cyl(0.16, 0.03, (0, -0.075, 0), "steel_dark", axis="Y", segs=10)
    for kb in range(2):
        with mp.at((0, 0, 0), rot=(0, kb * 180.0, 0)):
            mp.box((0.13, 0.024, 0.80), (0, 0, 0.10), "black", base=True, taper=(0.6, 1.0), rot=(0, 0, 18))
            mp.box((0.08, 0.026, 0.07), (0, 0, 0.90), "yellow", base=True, rot=(0, 0, 18))
    pr = mp.to_object(root, "prop")
    pr.location = HUB

    # ------------------------------------------------------------------ wheels (origin centre, axle X)
    rw = MAIN[2]
    wl = C.make_wheel(root, "wheel_l", rw, 0.15, "steel", rim_ratio=0.55, rim_color="white", cap_color="chrome",
                      segs=12)
    wl.location = (-MAIN[0], MAIN[1], rw)
    K.link_copy(wl, root, "wheel_r", (MAIN[0], MAIN[1], rw), rot=(0, 0, 180))
    wn = C.make_wheel(root, "wheel_n", NOSE[1], 0.11, "steel", rim_ratio=0.55, rim_color="white",
                      cap_color="chrome", segs=12)
    wn.location = (0.0, NOSE[0], NOSE[1])

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    LS = [S[0], S[2], S[3], S[5], S[6], S[8], S[10], S[11]]
    lr = [U.sring(y, cz, w, ht, hb, n=8, p=p) for (y, cz, w, ht, hb, p) in LS]

    def lcol(i, k):
        if i in (2, 3) and 2 <= k <= 5:
            return "glass_dark"
        if i == 4 and k in (2, 5):
            return "glass_dark"
        return P1
    U.loft(ml, lr, lcol, smooth=False, cap_color=P1)
    U.loft(ml, [U.wing_ring(x, w_le(x), w_z(x), w_ch(x), t=0.12, camber=0.0, stations=(1.0, 0.3))
                for x in (-5.4, 0.0, 5.4)], P1, smooth=False, cap_color=P1)
    ml.box((3.4, 0.80, 0.06), (0, TP_YH + 0.05, TP_Z), P1)
    ml.prism([(-3.95, 1.70), (-5.55, 1.70), (-5.80, 2.85), (-5.00, 2.85)], 0.08, P1, plane="YZ")
    ml.box((0.10, 0.06, 1.85), (0, HUB[1] + 0.02, HUB[2]), "black")
    for sx in (1, -1):
        ml.box((0.04, 0.06, 2.30), (sx * 1.535, 0.05, 1.56), "gray_light", rot=(0, sx * 62.0, 0))
        ml.cyl(MAIN[2], 0.14, (sx * MAIN[0], MAIN[1], MAIN[2]), "tire", axis="X", segs=8, smooth=False)
        ml.box((0.06, 0.06, 0.95), (sx * 0.75, MAIN[1], 0.58), "gray_light", rot=(0, -sx * 48.0, 0))
    ml.cyl(NOSE[1], 0.11, (0, NOSE[0], NOSE[1]), "tire", axis="X", segs=8, smooth=False)
    ml.box((0.06, 0.06, 0.60), (0, NOSE[0], 0.55), "gray_light")
    ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hulls
    pts = []
    for (y, cz, w, ht, hb, p) in (S[1], S[4], S[7], S[9]):
        pts += U.sring(y, cz, w, ht, hb, n=6, p=2.0)
    pts += [(0, S[11][0], S[11][1])]
    U.col_hull(root, "col_body", pts)
    wp = []
    for x in (-5.4, 0.0, 5.4):
        for y, dz in ((w_le(x), 0.0), (w_le(x) - w_ch(x), 0.0)):
            wp += [(x, y, w_z(x) - 0.10), (x, y, w_z(x) + 0.10)]
    U.col_hull(root, "col_wing", wp)

    # ------------------------------------------------------------------ markers
    for name, p in seats.items():
        K.marker(root, name, p)
    K.marker(root, "engine", (0.0, 1.75, 1.45))
    K.marker(root, "exhaust", (0.22, 1.45, 0.75))
    K.marker(root, "light_head_l", (lx, w_le(lx) + 0.02, w_z(lx) - 0.012))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/plane_prop", "Airplanes",
                        notes="Kestrel high-wing 4-seat prop plane. Origin on the ground under the wing quarter chord, "
                              "z=0 at the wheel bottoms, level attitude. prop: origin at the hub, spins about Y. "
                              "aileron_l/_r, elevator: origin on the hinge line, local X along it (both ailerons "
                              "point local X to the right). rudder: hinge = local Z. door_fl hinged at its front edge "
                              "(only the left door opens). Tip lights: @LightIndL left, @LightIndR right; landing light "
                              "(@LightHead, marker light_head_l) in the left wing leading edge.",
                        extra={"wheel_radius": MAIN[2], "wheel_radius_nose": NOSE[1], "wheel_width": 0.15,
                               "wheelbase": round(NOSE[0] - MAIN[1], 3), "track": round(2 * MAIN[0], 3),
                               "clearance": 0.82, "doors": 1, "seats": 4, "wingspan": 10.8,
                               "prop_diameter": 1.92})
    return root


# =========================================================================== heli_police "Skywatch"
PS = [
    # y,     cz,   w,    ht,   hb,   p
    (3.30, 1.25, 0.04, 0.04, 0.04, 2.0),     # 0 nose tip
    (3.18, 1.27, 0.34, 0.26, 0.28, 2.2),     # 1
    (2.90, 1.32, 0.66, 0.52, 0.48, 2.3),     # 2 bubble
    (2.40, 1.40, 0.86, 0.74, 0.66, 2.4),     # 3
    (1.70, 1.46, 0.95, 0.86, 0.78, 2.6),     # 4 roof front
    (0.95, 1.48, 0.95, 0.88, 0.80, 2.8),     # 5 cockpit side window rear
    (0.30, 1.48, 0.95, 0.88, 0.80, 2.8),     # 6 rear door opening front
    (-1.10, 1.48, 0.94, 0.88, 0.80, 2.8),    # 7 rear door opening rear
    (-1.70, 1.52, 0.86, 0.82, 0.72, 2.6),    # 8 rear bulkhead
    (-2.40, 1.64, 0.56, 0.62, 0.48, 2.4),    # 9
    (-3.00, 1.76, 0.32, 0.36, 0.28, 2.2),    # 10 boom root
    (-5.20, 1.86, 0.22, 0.24, 0.20, 2.0),    # 11
    (-6.45, 1.92, 0.18, 0.20, 0.16, 2.0),    # 12 boom end (inside the duct lip)
]
FEN = (0.0, -7.05, 2.00)     # fenestron fan hub
FEN_R = 0.50


def _sky_cell(i, k):
    if i == 0:
        return P1
    if i <= 3:                                   # bubble + chin windows
        return GL if 2 <= k <= 13 else P2
    if i == 4 and (3 <= k <= 5 or 10 <= k <= 12):
        return GL
    if i == 5 and (k in (4, 5, 10, 11)):
        return GL
    if i == 6 and (2 <= k <= 5 or 10 <= k <= 13):
        return None                              # open rear side doors
    if i == 7 and k in (4, 11):
        return GL
    if k in (0, 1, 14, 15) or (i <= 8 and k in (2, 13)):
        return P2                                # white belly / lower band
    return P1


def build_heli_police(export=True):
    root = K.begin_asset("heli_police", "Helicopters")
    S = PS
    rings = [U.sring(y, cz, w, ht, hb, n=16, p=p) for (y, cz, w, ht, hb, p) in S]
    MAST = (0.0, 0.0, 3.22)
    ZF, ZS = 0.80, 1.06
    mb = K.MB()
    sh = U.shell(mb, rings, _sky_cell, thickness=0.035, inner="@D:plastic_gray", sharp=40.0,
                 liner=lambda i, k: 1 <= i <= 7)
    Q = sh["Q"]
    U.face(mb, [tuple(q) for q in Q[8]], "@D:plastic_gray", toward=(0, 1, 0))
    U.face(mb, rings[0], P1, toward=(0, 1, 0))
    U.face(mb, rings[-1], P1, toward=(0, -1, 0))
    fl = []
    for i in range(3, 9):
        q = Q[i]
        for k in range(0, 4):
            a, b = q[k], q[k + 1]
            if a.z <= ZF <= b.z:
                t = (ZF - a.z) / max(1e-6, b.z - a.z)
                xf = a.x + (b.x - a.x) * t
                fl.append([(-xf, a.y, ZF), (xf, a.y, ZF)])
                break
    U.loft(mb, fl, "@D:gray_dark", closed=False, smooth=False, outward=(0, 0, 1))

    def frame(pts, r=0.02, dy=0.0):
        line = [U.grid_point(rings, i, k, 0.006) for i, k in pts]
        mb.tube([(x, y + dy, z) for x, y, z in line], r, "plastic_black", segs=4)

    frame([(1, k) for k in range(2, 15)])                    # bubble front arc
    frame([(1, 8), (2, 8), (3, 8), (4, 8)])                  # centre post
    frame([(4, k) for k in range(6, 11)])                    # roof front edge
    for kb, kt in ((3, 6), (13, 10)):
        step = 1 if kt > kb else -1
        frame([(4, k) for k in range(kb, kt + step, step)])  # A pillar
        frame([(5, k) for k in range(kb, kt + step, step)])
        frame([(6, k) for k in range(kb - step, kt + step, step)], dy=-0.02)   # door opening edges
        frame([(7, k) for k in range(kb - step, kt + step, step)], dy=0.02)
    # ---- twin-engine cowl, exhausts, intakes, mast
    cowl = [(1.15, 2.30, 0.20, 0.10), (0.80, 2.42, 0.52, 0.32), (0.0, 2.46, 0.62, 0.40), (-1.40, 2.44, 0.64, 0.42),
            (-2.40, 2.34, 0.50, 0.32), (-3.05, 2.12, 0.20, 0.12)]
    U.loft(mb, [U.sring(y, cz, w, ht, 0.12, n=10, p=2.6) for (y, cz, w, ht) in cowl], P1, smooth=True, sharp=40.0)
    for sx in (-1, 1):
        mb.box((0.04, 0.60, 0.18), (sx * 0.635, -0.50, 2.50), "plastic_black")
        for j in range(3):
            mb.box((0.05, 0.58, 0.018), (sx * 0.64, -0.50, 2.45 + j * 0.05), "steel_dark")
        mb.cyl(0.085, 0.40, (sx * 0.36, -2.30, 2.64), "steel_dark", axis="Y", segs=8, rot=(-16, 0, 0),
               cap_color="black")
    mb.cyl(0.045, 0.46, (0, 0, 2.99), "steel", segs=8)
    mb.cyl(0.15, 0.03, (0, 0, 2.90), "steel_dark", segs=10)
    # ---- tail: stabiliser with end plates, fenestron duct + fin, tail skid
    U.loft(mb, [U.wing_ring(x, -5.70, 1.90, 0.55, t=0.10, camber=0.0) for x in (-1.15, 0.0, 1.15)], P1,
           smooth=True, sharp=50.0)
    for sx in (-1, 1):
        mb.box((0.03, 0.50, 0.40), (sx * 1.16, -5.95, 1.92), P2, shear=(0, -0.10))
    fx, fy, fz = FEN
    U.tube_ring(mb, fx, fy, fz, FEN_R + 0.12, 0.15, P1, plane="YZ", segs=16, tsegs=6)
    for a in (0.0, 120.0, 240.0):                                     # stator struts
        with mb.at(FEN, rot=(a + 30.0, 0, 0)):
            mb.box((0.03, 0.04, FEN_R - 0.08), (0.06, 0, 0.08 + (FEN_R - 0.08) * 0.5), "steel_dark")
    fin = [(fz + 0.55, fy + 0.30, 0.95), (fz + 0.95, fy - 0.20, 0.70), (fz + 1.05, fy - 0.40, 0.55)]
    U.loft(mb, [U.wing_ring(z, yl, 0.0, c, t=0.12, camber=0.0, vertical=True) for z, yl, c in fin],
           lambda i, k: P2 if i == 1 else P1, smooth=True, sharp=50.0, cap_color=(P1, P2))
    mb.tube([(0, fy + 0.10, fz - FEN_R - 0.20), (0, fy - 0.15, 1.10), (0, fy - 0.30, 1.05)], 0.02, "steel_dark",
            segs=4)
    mb.cyl(0.035, 0.05, (0, fy - 0.40, fz + 1.075), "led_red", segs=6)
    # ---- skids, landing light, searchlight mount, strobes
    A._skids(mb, 1.15, -1.80, 1.50, (1.00, -0.95), ZF - 0.12, 0.46)
    mb.cyl(0.07, 0.11, (0.30, 2.55, 0.78), "chrome", axis="Y", segs=8, cap_color="@LightHead")
    SL = (0.0, 2.25, 0.56)
    mb.box((0.10, 0.12, 0.16), (0, SL[1], SL[2] + 0.19), "steel_dark")
    for sx, col in ((-1, "@LightSirenA"), (1, "@LightSirenB")):
        mb.box((0.10, 0.18, 0.06), (sx * 0.50, 1.00, 2.36), col)          # roof strobes
        mb.box((0.10, 0.18, 0.06), (sx * 0.42, -0.40, 0.69), col)         # belly strobes
        mb.box((0.03, 0.12, 0.08), (sx * 0.23, -4.80, 1.92), col)         # boom strobes
    # ---- POLICE lettering on the tail boom
    for side in (1, -1):
        K.add_text(mb, "POLICE", size=0.26, depth=0.012, color=P2, pos=(side * 0.284, -4.05, 1.72),
                   rot=(0, 0, -92.6 * side), res=1)
    # ---- interior: cockpit seats + console, rear bench, gunner jump seats at the open doors
    seats = {}
    for name, sx in (("seat_driver", -1), ("seat_passenger", 1)):
        p = (sx * 0.42, 1.05, ZS)
        seats[name] = U.seat(mb, p, w=0.48, d=0.46, back_h=0.62, color="@D:leather_black", trim="@D:charcoal",
                             base_h=0.12)
        mb.box((0.36, 0.36, ZS - 0.12 - ZF), (p[0], p[1], (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
        mb.tube([(p[0], 1.45, ZF), (p[0], 1.38, 1.22)], 0.012, "@D:plastic_black", segs=4)
    mb.box((0.36, 0.50, 0.42), (0, 1.62, ZF + 0.21), "@D:plastic_black")
    with mb.at((0, 1.80, 1.30), rot=(-20, 0, 0)):
        mb.box((1.10, 0.06, 0.34), (0, 0, 0), "@D:plastic_black")
        mb.box((0.34, 0.012, 0.22), (-0.30, -0.034, 0.03), "screen_blue")
        mb.box((0.34, 0.012, 0.22), (0.30, -0.034, 0.03), "screen_blue")
    by = -1.40
    mb.box((1.40, 0.42, ZS - 0.12 - ZF), (0, by, (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
    U.bench(mb, (0, by, ZS), w=1.40, d=0.44, back_h=0.56, color="@D:fabric_dark", trim="@D:charcoal", base_h=0.12)
    seats["seat_rl"] = (-0.40, by, ZS + U.SEAT_HIP)
    seats["seat_rr"] = (0.40, by, ZS + U.SEAT_HIP)
    gun = {}
    for name, sx in (("gunner_l", -1), ("gunner_r", 1)):
        p = (sx * 0.30, -0.40, ZS)
        gun[name] = U.seat(mb, p, w=0.44, d=0.42, back_h=0.50, color="@D:fabric_dark", trim="@D:charcoal",
                           base_h=0.12, headrest=False, yaw=90.0 * -sx)
        mb.box((0.32, 0.36, ZS - 0.12 - ZF), (p[0], p[1], (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
    mb.to_object(root, "body")

    # ------------------------------------------------------------------ rotors + searchlight
    mr = K.MB()
    A._rotor_head(mr, 4, 5.30, 0.32, hub_r=0.13, phase=45.0)
    mr.to_object(root, "rotor_main").location = MAST
    mt = K.MB()
    mt.cyl(0.10, 0.20, (0, 0, 0), "steel_dark", axis="X", segs=8)
    for kb in range(9):
        with mt.at((0, 0, 0), rot=(kb * 40.0, 0, 0)):
            mt.box((0.025, 0.09, FEN_R - 0.12), (0.03, 0, 0.09 + (FEN_R - 0.12) * 0.5), "charcoal", rot=(0, 0, 0))
    mt.to_object(root, "rotor_tail").location = FEN
    ms = K.MB()
    ms.box((0.06, 0.10, 0.12), (0, 0, 0.12), "steel_dark")
    for sx in (-1, 1):
        ms.box((0.03, 0.06, 0.20), (sx * 0.165, 0, 0.04), "steel_dark")
    ms.cyl(0.14, 0.30, (0, 0.0, 0), "gunmetal", axis="Y", segs=10, cap_color="gunmetal")
    ms.cyl(0.125, 0.02, (0, 0.155, 0), "@LightHead", axis="Y", segs=10)
    ms.cyl(0.10, 0.06, (0, -0.17, 0), "steel_dark", axis="Y", segs=8)
    ms.to_object(root, "searchlight").location = SL

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    LS = [S[0], S[2], S[4], S[6], S[8], S[10], S[12]]
    lr = [U.sring(y, cz, w, ht, hb, n=8, p=p) for (y, cz, w, ht, hb, p) in LS]

    def lcol(i, k):
        if i in (0, 1) and 2 <= k <= 5:
            return "glass_dark"
        if i in (2, 3) and k in (2, 5):
            return "glass_dark"
        return P1 if 2 <= k <= 5 else P2
    U.loft(ml, lr, lcol, smooth=False, cap_color=P1)
    ml.box((1.1, 4.0, 0.40), (0, -0.90, 2.48), P1, taper=(0.7, 0.85))
    ml.box((0.24, 1.40, 1.30), (0, FEN[1] - 0.05, FEN[2] + 0.20), P1)
    ml.box((2.3, 0.50, 0.05), (0, -5.95, 1.90), P1)
    for sx in (-1, 1):
        ml.box((0.09, 3.3, 0.09), (sx * 1.15, -0.15, 0.045), "charcoal")
    for y in (1.00, -0.95):
        ml.box((2.30, 0.07, 0.07), (0, y, 0.40), "charcoal")
    ml.box((0.09, 0.09, 0.45), (0, 0, 3.0), "steel_dark")
    for i in range(4):
        with ml.at(MAST, rot=(0, 0, 45 + i * 90)):
            ml.box((5.0, 0.30, 0.03), (2.70, 0, 0), "charcoal")
    ml.box((0.20, 0.30, 0.22), (0, SL[1], SL[2]), "gunmetal")
    ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hulls
    pts = [(-1.15, -1.8, 0.0), (1.15, -1.8, 0.0), (-1.15, 1.5, 0.0), (1.15, 1.5, 0.0), (0, 3.30, 1.25)]
    for (y, cz, w, ht, hb, p) in (S[3], S[5], S[8]):
        pts += U.sring(y, cz, w, ht, hb, n=6, p=2.0)
    U.col_hull(root, "col_body", pts)
    pts = U.sring(-2.4, 1.64, 0.56, 0.62, 0.48, n=4) + U.sring(-6.45, 1.92, 0.20, 0.20, 0.18, n=4)
    pts += [(0, fy - 0.75, fz - 0.3), (0, fy - 0.75, fz + 0.4), (0, fy - 0.45, fz + 1.10), (0, fy + 0.30, fz + 0.60),
            (-0.18, fy, fz - 0.65), (0.18, fy, fz - 0.65), (-1.16, -5.95, 1.92), (1.16, -5.95, 1.92)]
    U.col_hull(root, "col_tail", pts)

    # ------------------------------------------------------------------ markers
    for name, p in seats.items():
        K.marker(root, name, p)
    K.marker(root, "gunner_l", gun["gunner_l"], rot=(0, 0, 90))
    K.marker(root, "gunner_r", gun["gunner_r"], rot=(0, 0, -90))
    K.marker(root, "engine", (0, -0.70, 2.70))
    K.marker(root, "light_head_l", (0.30, 2.62, 0.78))
    K.marker(root, "light_tail_l", (0, fy - 0.40, fz + 1.12))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/heli_police", "Helicopters",
                        notes="Skywatch twin-engine police helicopter. Origin under the rotor mast, z=0 at the skid "
                              "bottoms. rotor_main: origin at the mast top, spins about Z (4 blades, dia 10.6). "
                              "rotor_tail: fenestron fan inside the shrouded tail, origin at the fan hub, spins about X. "
                              "searchlight: pod under the nose, origin at its gimbal, lens (@LightHead) looks along +Y "
                              "at rest. Open rear side doors; gunner_l / gunner_r = hip points on jump seats facing "
                              "outward (rotated -/+90 deg about Z). Strobes @LightSirenA (left) / B (right). No doors.",
                        extra={"wheel_radius": 0.0, "wheel_width": 0.0, "wheelbase": 0.0, "track": 2.30,
                               "clearance": 0.68, "doors": 0, "seats": 4, "rotor_diameter": 10.6,
                               "tail_rotor_diameter": 1.0})
    return root