"""veh_air - aircraft for NEON TIDE: heli_civil "Dragonfly", heli_police "Skywatch", plane_prop "Kestrel",
plane_jet "Arrow".

    import veh_air as M; importlib.reload(M); print(M.build_all())

Front = +Y, z = 0 at the bottom of the skids / wheels.  Helicopters: origin under the rotor mast (centre of the
skid footprint).  Contract: rotor_main origin at the mast top (spins about Z), rotor_tail origin at the tail hub
(spins about X), prop origin at the hub (spins about Y), control surfaces with their origin on the hinge line and
their local X (rudder: local Z) along it, doors hinged at their front edge (open about local Z).
"""
import math
from mathutils import Vector, Matrix
import gta_kit as K
import veh_oth as U

rad = math.radians
GL = "@Glass"
BLADE_S = (1.0, 0.5, 0.12)          # chord stations of the low-poly rotor blade section


# --------------------------------------------------------------------------- shared helicopter helpers
def _blade(mb, r0, r1, chord, color, tip_color=None, tip_len=0.38, t=0.12, pitch=4.0, root_chord=0.55,
           tip_chord=0.7):
    """Rotor blade along local +X, leading edge toward +Y."""
    xs = [(r0, chord * root_chord), (r0 + 0.28, chord), (r1 - tip_len, chord), (r1, chord * tip_chord)]
    rings = [U.wing_ring(x, c * 0.28, 0.0, c, t=t, camber=0.0, twist=pitch, stations=BLADE_S) for x, c in xs]
    cols = [color, color, tip_color or color]
    return U.loft(mb, rings, lambda i, k: cols[max(0, min(2, i))], smooth=True, sharp=50.0,
                  cap_color=(color, tip_color or color))


def _blade_v(mb, r0, r1, chord, color, tip_color=None, tip_len=0.14, t=0.12):
    """Tail-rotor blade along local +Z, chord along Y, thin in X."""
    zs = [(r0, chord * 0.6), (r0 + 0.08, chord), (r1 - tip_len, chord), (r1, chord * 0.8)]
    rings = [U.wing_ring(z, c * 0.3, 0.0, c, t=t, camber=0.0, vertical=True, stations=BLADE_S) for z, c in zs]
    cols = [color, color, tip_color or color]
    return U.loft(mb, rings, lambda i, k: cols[max(0, min(2, i))], smooth=True, sharp=50.0,
                  cap_color=(color, tip_color or color))


def _skids(mb, half_track, y0, y1, cross, top_z, top_half, r=0.045, color="charcoal"):
    """Two skid tubes (bottom at z = 0) with upturned toes + bow-shaped cross tubes up to the belly."""
    for sx in (-1, 1):
        x = sx * half_track
        mb.tube([(x, y1 + 0.42, 0.34), (x, y1 + 0.22, 0.13), (x, y1, 0.055), (x, y1 - 0.3, r), (x, y0, r)], r, color,
                segs=6)
    for y in cross:
        pts = [(-half_track, y, r + 0.01), (-half_track + 0.10, y, 0.30), (-top_half - 0.14, y, top_z - 0.07),
               (-top_half, y, top_z)]
        pts = pts + [(-x, yy, z) for x, yy, z in reversed(pts)]
        mb.tube(pts, r * 0.85, color, segs=6)
        for sx in (-1, 1):
            mb.box((0.10, 0.12, 0.05), (sx * half_track, y, r + 0.03), "steel_dark")


def _rotor_head(mb, blades, radius, chord, hub_r=0.11, color="charcoal", tip="yellow", phase=90.0):
    """Main rotor in local coordinates (origin = mast top, spins about Z, anticlockwise seen from above)."""
    mb.cyl(hub_r, 0.11, (0, 0, 0), "steel_dark", segs=10)
    U.lathe(mb, [(0.055, hub_r), (0.10, hub_r * 0.75), (0.13, 0.0)], "gunmetal", axis="Z", segs=10)
    mb.cyl(hub_r + 0.05, 0.025, (0, 0, -0.27), "steel_dark", segs=10)
    for i in range(blades):
        with mb.at((0, 0, 0), rot=(0, 0, phase + i * 360.0 / blades)):
            mb.box((0.36, 0.11, 0.055), (0.24, 0, 0), "steel", bevel=0.012)
            mb.tube([(hub_r + 0.03, 0.04, -0.26), (0.27, 0.085, -0.02)], 0.012, "steel", segs=4, caps=False)
            _blade(mb, 0.40, radius, chord, color, tip)


def _tail_rotor(mb, radius, chord, blades=2, color="charcoal", tip="red"):
    """Tail rotor in local coordinates (origin = hub, spins about X, blades in the YZ plane)."""
    mb.cyl(0.05, 0.13, (0, 0, 0), "steel_dark", axis="X", segs=8)
    mb.cyl(0.03, 0.18, (0, 0, 0), "steel", axis="X", segs=6)
    for i in range(blades):
        with mb.at((0, 0, 0), rot=(i * 360.0 / blades + 20.0, 0, 0)):
            mb.box((0.03, 0.05, 0.12), (0, 0, 0.07), "steel")
            _blade_v(mb, 0.08, radius, chord, color, tip)


def _door_from_grid(root, part, rings, cellfn, seg, k0, k1, sill_k, hinge, handle_rot, frame="plastic_black",
                    inner="@D:plastic_gray"):
    """Door = the cells (seg, k0..k1-1) of a fuselage ring grid, as its own object hinged at `hinge`."""
    md = K.MB()
    U.shell(md, rings, cellfn, thickness=0.035, inner=inner, sharp=40.0)
    loop = [(seg, k) for k in range(k0, k1 + 1)] + [(seg + 1, k) for k in range(k1, k0 - 1, -1)] + [(seg, k0)]

    def gp(i, k):
        x, y, z = U.grid_point(rings, i, k, 0.006)
        return (x, y - 0.024 if i == seg else y + 0.024, z)

    md.tube([gp(i, k) for i, k in loop], 0.018, frame, segs=4)
    md.tube([gp(seg, sill_k), gp(seg + 1, sill_k)], 0.016, frame, segs=4)
    # handle on the lower (painted) panel, near the rear edge
    ka, kb = (sill_k, sill_k + 1) if sill_k == k1 - 1 else (sill_k - 1, sill_k)
    pa = Vector(U.grid_point(rings, seg, ka, 0.014)).lerp(Vector(U.grid_point(rings, seg + 1, ka, 0.014)), 0.78)
    pb = Vector(U.grid_point(rings, seg, kb, 0.014)).lerp(Vector(U.grid_point(rings, seg + 1, kb, 0.014)), 0.78)
    md.box((0.03, 0.14, 0.04), tuple((pa + pb) * 0.5), "chrome", rot=(0, handle_rot, 0))
    obj = md.to_object(root, part)
    U.repivot(obj, hinge)
    return obj


# =========================================================================== heli_civil "Dragonfly"
CIVIL_S = [
    # y,     cz,   w,    ht,   hb,   p
    (2.585, 1.20, 0.03, 0.03, 0.03, 2.0),      # 0 nose tip
    (2.50, 1.21, 0.24, 0.20, 0.19, 2.2),       # 1
    (2.28, 1.26, 0.50, 0.38, 0.34, 2.3),       # 2 bubble front
    (1.92, 1.33, 0.71, 0.56, 0.52, 2.4),       # 3
    (1.42, 1.40, 0.82, 0.74, 0.68, 2.4),       # 4 roof front
    (0.85, 1.42, 0.85, 0.80, 0.78, 2.4),       # 5 A pillar / door hinge
    (0.05, 1.42, 0.85, 0.80, 0.80, 2.4),       # 6 B pillar
    (-0.75, 1.42, 0.84, 0.80, 0.78, 2.4),      # 7 C pillar
    (-1.15, 1.44, 0.80, 0.76, 0.72, 2.4),      # 8 rear bulkhead
    (-1.70, 1.52, 0.62, 0.62, 0.52, 2.3),      # 9
    (-2.30, 1.64, 0.38, 0.42, 0.34, 2.2),      # 10
    (-2.80, 1.72, 0.24, 0.26, 0.24, 2.1),      # 11 boom root
    (-4.50, 1.80, 0.17, 0.18, 0.17, 2.0),      # 12
    (-6.25, 1.90, 0.11, 0.12, 0.12, 2.0),      # 13
    (-6.55, 1.92, 0.07, 0.08, 0.08, 2.0),      # 14 boom end
]


def build_heli_civil(export=True):
    root = K.begin_asset("heli_civil", "Helicopters")
    S = CIVIL_S
    rings = [U.sring(y, cz, w, ht, hb, n=16, p=p) for (y, cz, w, ht, hb, p) in S]
    MAST = (0.0, 0.0, 2.95)
    TR = (-0.21, -6.20, 1.92)            # tail rotor hub
    ZF = 0.76                            # cabin floor
    ZS = 0.98                            # seat cushion top

    def cell(i, k, door=None):
        rd = (i == 5 and 2 <= k <= 5)
        ld = (i == 5 and 10 <= k <= 13)
        if door == "fr":
            return (GL if k >= 3 else "@Paint2") if rd else None
        if door == "fl":
            return (GL if k <= 12 else "@Paint2") if ld else None
        if rd or ld:
            return None
        if i in (2, 3) and 3 <= k <= 12:
            return GL
        if i in (4, 6) and (3 <= k <= 5 or 10 <= k <= 12):
            return GL
        if i <= 7:
            return "@Paint2" if (k in (2, 13) and i >= 1) else "@Paint1"
        if i <= 9:
            return "@Paint2" if k in (2, 3, 12, 13) else "@Paint1"
        return "@Paint2" if k in (3, 4, 11, 12) else "@Paint1"

    mb = K.MB()
    sh = U.shell(mb, rings, lambda i, k: cell(i, k), thickness=0.035, inner="@D:plastic_gray", sharp=40.0,
                 liner=lambda i, k: 2 <= i <= 7)
    Q = sh["Q"]
    U.face(mb, [tuple(q) for q in Q[8]], "@D:plastic_gray", toward=(0, 1, 0))
    U.face(mb, rings[-1], "@Paint1", toward=(0, -1, 0))
    U.face(mb, rings[0], "@Paint1", toward=(0, 1, 0))
    # ---- cabin floor
    fl = []
    for i in range(4, 9):
        q = Q[i]
        for k in range(0, 4):
            a, b = q[k], q[k + 1]
            if a.z <= ZF <= b.z:
                t = (ZF - a.z) / max(1e-6, b.z - a.z)
                xf = a.x + (b.x - a.x) * t
                yf = a.y + (b.y - a.y) * t
                fl.append([(-xf, yf, ZF), (xf, yf, ZF)])
                break
    U.loft(mb, fl, "@D:gray_dark", closed=False, smooth=False, outward=(0, 0, 1))

    # ---- window frames
    def frame(pts, r=0.02, dy=0.0, color="plastic_black"):
        line = [U.grid_point(rings, i, k, 0.006) for i, k in pts]
        if dy:
            line = [(x, y + dy, z) for x, y, z in line]
        mb.tube(line, r, color, segs=4)

    frame([(2, k) for k in range(3, 14)])                    # bubble front arc
    frame([(2, 8), (3, 8), (4, 8)])                          # centre post
    frame([(4, k) for k in range(6, 11)])                    # roof front edge
    for kb, kt in ((3, 6), (13, 10)):
        frame([(2, kb), (3, kb), (4, kb), (5, kb)])          # belt line front
        frame([(6, kb), (7, kb)])                            # belt line rear
        frame([(4, kt), (5, kt)])                            # roof edge front
        frame([(6, kt), (7, kt)])                            # roof edge rear
        step = 1 if kt > kb else -1
        ks = list(range(kb, kt + step, step))
        frame([(5, k) for k in ks], dy=0.024)                # A pillar
        frame([(6, k) for k in ks], dy=-0.024)               # B pillar
        frame([(7, k) for k in ks])                          # C pillar

    # ---- engine / transmission cowl, exhaust, intakes
    cowl = [(0.82, 2.14, 0.16, 0.10), (0.42, 2.18, 0.36, 0.28), (0.0, 2.19, 0.43, 0.37), (-0.85, 2.17, 0.46, 0.40),
            (-1.60, 2.10, 0.42, 0.36), (-2.30, 2.00, 0.28, 0.24), (-2.78, 1.93, 0.12, 0.10)]
    U.loft(mb, [U.sring(y, cz, w, ht, 0.12, n=10, p=2.6) for (y, cz, w, ht) in cowl], "@Paint1", smooth=True,
           sharp=40.0)
    for sx in (-1, 1):
        mb.box((0.04, 0.52, 0.17), (sx * 0.452, -0.62, 2.30), "plastic_black")
        for j in range(3):
            mb.box((0.05, 0.50, 0.018), (sx * 0.456, -0.62, 2.25 + j * 0.05), "steel_dark")
    mb.cyl(0.085, 0.40, (0, -1.98, 2.43), "steel_dark", axis="Y", segs=8, rot=(-14, 0, 0), cap_color="black")
    mb.cyl(0.043, 0.48, (0, 0, 2.72), "steel", segs=8)                              # mast
    mb.cyl(0.14, 0.03, (0, 0, 2.62), "steel_dark", segs=10)                         # swash plate (fixed)
    # ---- tail: stabiliser with end plates, fin, gearbox, skid, beacon
    U.loft(mb, [U.wing_ring(x, -4.72, 1.83, 0.44 if abs(x) < 0.5 else 0.38, t=0.10, camber=0.0) for x in
                (-0.95, 0.0, 0.95)], "@Paint1", smooth=True, sharp=50.0)
    for sx, lamp in ((-1, "led_red"), (1, "led_green")):
        mb.box((0.03, 0.44, 0.42), (sx * 0.955, -4.96, 1.83), "@Paint2", shear=(0, -0.12))
        mb.box((0.03, 0.07, 0.05), (sx * 0.975, -4.80, 1.83), lamp)
    fin = [(1.15, -6.32, 0.34), (1.90, -6.10, 0.62), (2.60, -6.47, 0.44), (2.86, -6.61, 0.38)]
    U.loft(mb, [U.wing_ring(z, yl, 0.0, c, t=0.10, camber=0.0, vertical=True) for z, yl, c in fin],
           lambda i, k: "@Paint2" if i == 2 else "@Paint1", smooth=True, sharp=50.0,
           cap_color=("@Paint1", "@Paint2"))
    mb.cyl(0.065, 0.20, (TR[0] * 0.45, TR[1], TR[2]), "steel_dark", axis="X", segs=8)
    mb.tube([(0, -6.44, 1.17), (0, -6.56, 1.0), (0, -6.50, 0.97)], 0.014, "steel_dark", segs=4)
    mb.cyl(0.035, 0.05, (0, -6.80, 2.885), "@LightTail", segs=6)
    mb.box((0.012, 0.16, 0.14), (0, -3.6, 2.02), "white", shear=(0, -0.07))
    # ---- skids, landing light
    _skids(mb, 1.02, -1.60, 1.30, (0.85, -0.75), 0.66, 0.36)
    mb.cyl(0.07, 0.11, (0, 2.26, 0.875), "chrome", axis="Y", segs=8, cap_color="@LightHead")
    mb.box((0.05, 0.08, 0.06), (0, 2.24, 0.925), "steel_dark")
    # ---- interior: seats, bench, console, sticks
    seats = {}
    for name, sx in (("seat_driver", -1), ("seat_passenger", 1)):
        p = (sx * 0.40, 0.40, ZS)
        seats[name] = U.seat(mb, p, w=0.46, d=0.46, back_h=0.62, color="@D:leather_brown", trim="@D:tan",
                             base_h=0.12)
        mb.box((0.36, 0.36, ZS - 0.12 - ZF), (p[0], p[1], (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
        mb.tube([(p[0], 0.80, ZF), (p[0], 0.73, 1.20)], 0.012, "@D:plastic_black", segs=4)
        mb.tube([(p[0], 0.733, 1.17), (p[0], 0.722, 1.27)], 0.02, "@D:plastic_black", segs=5)
    by = -0.74
    mb.box((1.34, 0.44, ZS - 0.12 - ZF), (0, by, (ZS - 0.12 + ZF) * 0.5), "@D:plastic_black")
    U.bench(mb, (0, by, ZS), w=1.36, d=0.44, back_h=0.58, color="@D:leather_brown", trim="@D:tan", base_h=0.12)
    seats["seat_rl"] = (-0.36, by, ZS + U.SEAT_HIP)
    seats["seat_rr"] = (0.36, by, ZS + U.SEAT_HIP)
    mb.box((0.34, 0.50, 0.42), (0, 1.36, ZF + 0.21), "@D:plastic_black", bevel=0.02)
    with mb.at((0, 1.50, 1.36), rot=(-20, 0, 0)):
        mb.box((0.86, 0.06, 0.34), (0, 0, 0), "@D:plastic_black", bevel=0.015)
        mb.box((0.30, 0.012, 0.20), (-0.23, -0.034, 0.03), "screen_blue")
        mb.box((0.30, 0.012, 0.20), (0.23, -0.034, 0.03), "screen_blue")
        for gx in (-0.33, -0.11, 0.11, 0.33):
            mb.cyl(0.035, 0.012, (gx, -0.034, -0.12), "white", axis="Y", segs=8)
    mb.box((0.92, 0.22, 0.03), (0, 1.57, 1.535), "@D:plastic_black")
    body = mb.to_object(root, "body")

    # ------------------------------------------------------------------ doors (hinged at the A pillar)
    hy = S[5][0]
    _door_from_grid(root, "door_fl", rings, lambda i, k: cell(i, k, "fl"), 5, 10, 14, 13,
                    (rings[5][12][0], hy, rings[5][12][2]), -33.5)
    _door_from_grid(root, "door_fr", rings, lambda i, k: cell(i, k, "fr"), 5, 2, 6, 3,
                    (rings[5][4][0], hy, rings[5][4][2]), 33.5)

    # ------------------------------------------------------------------ rotors
    mr = K.MB()
    _rotor_head(mr, 3, 4.70, 0.26)
    rm = mr.to_object(root, "rotor_main")
    rm.location = MAST
    mt = K.MB()
    _tail_rotor(mt, 0.70, 0.14)
    rt = mt.to_object(root, "rotor_tail")
    rt.location = TR

    # ------------------------------------------------------------------ lod1
    ml = K.MB()
    LS = [S[0], S[2], S[3], S[5], S[8], S[11], S[13], S[14]]
    lr = [U.sring(y, cz, w, ht, hb, n=8, p=p) for (y, cz, w, ht, hb, p) in LS]

    def lcol(i, k):
        if i in (1, 2) and 2 <= k <= 5:
            return "glass_dark"
        if i == 3 and k in (2, 5):
            return "glass_dark"
        return "@Paint1"

    U.loft(ml, lr, lcol, smooth=False, cap_color="@Paint1")
    ml.box((0.8, 3.3, 0.36), (0, -0.95, 2.32), "@Paint1", taper=(0.7, 0.8))
    ml.prism([(-6.10, 1.90), (-6.35, 1.15), (-6.66, 1.15), (-6.72, 1.90), (-6.99, 2.86), (-6.61, 2.86)], 0.06,
             "@Paint1", plane="YZ")
    ml.box((1.9, 0.42, 0.04), (0, -4.94, 1.83), "@Paint1")
    for sx in (-1, 1):
        ml.box((0.09, 3.4, 0.09), (sx * 1.02, -0.1, 0.045), "charcoal")
    for y in (0.85, -0.75):
        ml.box((2.04, 0.07, 0.07), (0, y, 0.50), "charcoal")
    ml.box((0.09, 0.09, 0.5), (0, 0, 2.72), "steel_dark")
    for i in range(3):
        with ml.at(MAST, rot=(0, 0, 90 + i * 120)):
            ml.box((4.5, 0.26, 0.03), (2.45, 0, 0), "charcoal")
    ml.box((0.03, 0.14, 1.4), TR, "charcoal", rot=(20, 0, 0))
    lod = ml.to_object(root, "lod1")

    # ------------------------------------------------------------------ collision hulls
    pts = [(-1.02, -1.6, 0.0), (1.02, -1.6, 0.0), (-1.02, 1.6, 0.0), (1.02, 1.6, 0.0), (0, 2.58, 1.2)]
    for (y, cz, w, ht, hb, p) in (S[2], S[5], S[8]):
        pts += U.sring(y, cz, w, ht, hb, n=6, p=2.0)
    U.col_hull(root, "col_body", pts)
    pts = U.sring(-1.7, 1.56, 0.5, 0.55, 0.45, n=4) + U.sring(-6.55, 1.92, 0.10, 0.10, 0.10, n=4)
    pts += [(0, -6.99, 2.86), (0, -6.61, 2.86), (0, -6.35, 1.15), (0, -6.66, 1.15), (-0.95, -4.95, 1.83),
            (0.95, -4.95, 1.83)]
    U.col_hull(root, "col_tail", pts)

    # ------------------------------------------------------------------ markers
    for name, p in seats.items():
        K.marker(root, name, p)
    K.marker(root, "engine", (0, -0.85, 2.57))
    K.marker(root, "light_head_l", (0, 2.32, 0.875))
    K.marker(root, "light_tail_l", (0, -6.80, 2.91))
    U.show(root, "detail")
    if export:
        return U.finish(root, "vehicles/heli_civil", "Helicopters",
                        notes="Dragonfly light helicopter. Origin under the rotor mast (centre of the skid footprint), "
                              "z=0 at the skid bottoms. rotor_main: origin at the mast top, spins about Z (3 blades, "
                              "dia 9.4). rotor_tail: origin at the tail hub on the left of the fin, spins about X. "
                              "Doors hinged at the front edge (open about local Z: left door negative, right positive). "
                              "col_body includes the skid footprint.",
                        extra={"wheel_radius": 0.0, "wheel_width": 0.0, "wheelbase": 0.0, "track": 2.04,
                               "clearance": 0.62, "doors": 2, "seats": 4, "rotor_diameter": 9.4,
                               "tail_rotor_diameter": 1.4})
    return root


def build_all():
    out = [build_heli_civil()]
    K.save_master()
    return "\n".join(out)
