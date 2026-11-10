"""cars_service - ambulance, firetruck, swat_van, box_truck (service vehicle artist).

Run inside an execute_blender_code call (after the gta_bl header, with tools/blender/assets on
sys.path):

    import car_kit as K, cars_service as S
    importlib.reload(K); importlib.reload(S)
    S.build("ambulance")          # builds the asset at its slot (rebuilds an existing one) + preview
    S.export("ambulance")         # validate + export vehicles/ambulance.glb
    S.build_all(); S.export_all(); S.group_preview(); G.save()

Slots: region 'service' 0 = ambulance, 1 = firetruck, 2 = swat_van, 3 = box_truck.

How the trucks are made (docs/VEHICLE_KIT.md explains the kit itself)
---------------------------------------------------------------------
`Truck` subclasses car_kit.Car.  For ambulance / firetruck / box_truck the kit only builds the CAB
(`cab_only=True`: the shell runs from the cab back to the nose and only the front axle is cut by
the kit); frame, box body, rear arches, rear lamps, collision and LOD are own geometry from the
helpers in this file.  swat_van uses the kit for the whole lower hull and greenhouse.

Differences to a kit car that the game code should know (all documented in the artist report):
  * fixed-livery vehicles use P_* palette materials instead of M_Paint_Primary (`livery=`), because
    the game never repaints them; box_truck keeps M_Paint_Primary (cab) + M_Paint_Secondary (box);
  * rear wheels of ambulance / firetruck / box_truck are twin tyres in ONE wheel node (own mesh);
  * box vehicles carry a third convex helper `Col_Box` next to Col_Body / Col_Cabin;
  * rear barn doors are Door_RL / Door_RR (hinge on the outer edge, same opening sign as side
    doors); their window panes are nested children Glass_Rear_L / Glass_Rear_R.
"""
import bpy
from math import sin, cos, pi, sqrt, radians, asin, atan2
from mathutils import Vector

import gta_bl as G
import car_kit as K

VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top", "back")
SLOTS = {"ambulance": 0, "firetruck": 1, "swat_van": 2, "box_truck": 3}
COLLECTIONS = {"ambulance": "Vehicles/Service", "firetruck": "Vehicles/Service",
               "swat_van": "Vehicles/Service", "box_truck": "Vehicles/Cars"}


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
def siren_mats():
    red = G.mat("M_Siren_Red", G.pal("SirenRed"), rough=0.2)
    blue = G.mat("M_Siren_Blue", G.pal("SirenBlue"), rough=0.2)
    return red, blue


def steel():
    return G.pmat("Steel", rough=0.45, metal=0.35)


def steel_dark():
    return G.pmat("SteelDark", rough=0.5, metal=0.35)


# ------------------------------------------------------------------------------------------------
# lettering + emblems (flat geometry, same stroke-font style as the HBPD cruiser of cars_b)
# ------------------------------------------------------------------------------------------------
# glyph = (advance width, [polylines]) on a unit-height cell; strokes become flat quads
FONT = {
    "A": (0.64, [[(0, 0), (0.32, 1), (0.64, 0)], [(0.12, 0.36), (0.52, 0.36)]]),
    "B": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.40, 1), (0.6, 0.86), (0.6, 0.64), (0.40, 0.5), (0, 0.5)],
                 [(0.40, 0.5), (0.6, 0.36), (0.6, 0.14), (0.40, 0), (0, 0)]]),
    "C": (0.56, [[(0.56, 0.84), (0.42, 1), (0.14, 1), (0, 0.84), (0, 0.16), (0.14, 0), (0.42, 0), (0.56, 0.16)]]),
    "D": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.36, 1), (0.6, 0.78), (0.6, 0.22), (0.36, 0), (0, 0)]]),
    "E": (0.52, [[(0.52, 1), (0, 1), (0, 0), (0.52, 0)], [(0, 0.5), (0.40, 0.5)]]),
    "F": (0.52, [[(0, 0), (0, 1), (0.52, 1)], [(0, 0.5), (0.40, 0.5)]]),
    "G": (0.58, [[(0.58, 0.84), (0.44, 1), (0.14, 1), (0, 0.84), (0, 0.16), (0.14, 0), (0.44, 0), (0.58, 0.16),
                  (0.58, 0.46), (0.32, 0.46)]]),
    "H": (0.60, [[(0, 0), (0, 1)], [(0.6, 0), (0.6, 1)], [(0, 0.5), (0.6, 0.5)]]),
    "I": (0.0, [[(0, 0), (0, 1)]]),
    "L": (0.50, [[(0, 1), (0, 0), (0.50, 0)]]),
    "M": (0.72, [[(0, 0), (0, 1), (0.36, 0.40), (0.72, 1), (0.72, 0)]]),
    "N": (0.60, [[(0, 0), (0, 1), (0.6, 0), (0.6, 1)]]),
    "O": (0.60, [[(0.14, 0), (0, 0.16), (0, 0.84), (0.14, 1), (0.46, 1), (0.6, 0.84), (0.6, 0.16), (0.46, 0), (0.14, 0)]]),
    "P": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.40, 1), (0.6, 0.86), (0.6, 0.62), (0.40, 0.48), (0, 0.48)]]),
    "R": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.40, 1), (0.6, 0.86), (0.6, 0.62), (0.40, 0.48), (0, 0.48)],
                 [(0.30, 0.48), (0.6, 0)]]),
    "S": (0.56, [[(0.56, 0.84), (0.42, 1), (0.14, 1), (0, 0.84), (0, 0.64), (0.14, 0.5), (0.42, 0.5), (0.56, 0.36),
                  (0.56, 0.16), (0.42, 0), (0.14, 0), (0, 0.16)]]),
    "T": (0.60, [[(0, 1), (0.6, 1)], [(0.3, 0), (0.3, 1)]]),
    "U": (0.60, [[(0, 1), (0, 0.16), (0.14, 0), (0.46, 0), (0.6, 0.16), (0.6, 1)]]),
    "X": (0.60, [[(0, 0), (0.6, 1)], [(0, 1), (0.6, 0)]]),
    "0": (0.55, [[(0, 0), (0, 1), (0.55, 1), (0.55, 0), (0, 0)]]),
    "1": (0.24, [[(0, 0.76), (0.24, 1), (0.24, 0)]]),
    "2": (0.55, [[(0, 0.84), (0.14, 1), (0.41, 1), (0.55, 0.84), (0.55, 0.60), (0, 0), (0.55, 0)]]),
    "3": (0.55, [[(0, 1), (0.55, 1), (0.22, 0.56), (0.41, 0.56), (0.55, 0.42), (0.55, 0.16), (0.41, 0), (0.14, 0), (0, 0.16)]]),
    "4": (0.58, [[(0.44, 0), (0.44, 1), (0, 0.32), (0.58, 0.32)]]),
    "7": (0.55, [[(0, 1), (0.55, 1), (0.2, 0)]]),
}


def text_quads(text, height, stroke=0.18, gap=0.34):
    """-> ([quad of four (u, v)], total width).  u runs in reading direction, v up."""
    quads = []
    u0 = 0.0
    h = stroke * height / 2.0
    for ch in text:
        if ch == " ":
            u0 += 0.5 * height
            continue
        w, lines = FONT[ch]
        for line in lines:
            for a, b in zip(line[:-1], line[1:]):
                ax, ay, bx, by = u0 + a[0] * height, a[1] * height, u0 + b[0] * height, b[1] * height
                ln = sqrt((bx - ax) ** 2 + (by - ay) ** 2)
                dx, dy = (bx - ax) / ln, (by - ay) / ln
                ex, ey, nx, ny = dx * h, dy * h, -dy * h, dx * h
                quads.append([(ax - ex - nx, ay - ey - ny), (bx + ex - nx, by + ey - ny),
                              (bx + ex + nx, by + ey + ny), (ax - ex + nx, ay - ey + ny)])
        u0 += (w + gap) * height
    return quads, u0 - gap * height


def emit_text(mb, text, height, mat, mapf, want, stroke=0.18):
    """Lettering as flat quads.  mapf(u, v) -> (x, y, z); u is centred on 0.  Returns the width."""
    quads, width = text_quads(text, height, stroke)
    for q in quads:
        mb.face([mapf(u - width / 2.0, v) for u, v in q], mat, want=want)
    return width


def flank_text(mb, side, x, text, yc, z0, height, mat, stroke=0.18):
    """Lettering on a flat body side at |x|, centred on yc, baseline z0, readable from outside."""
    return emit_text(mb, text, height, mat, lambda u, v: (side * x, yc + side * u, z0 + v), (side, 0, 0), stroke)


def side_text(mb, car, side, text, yc, z0, height, mat, off=0.007, stroke=0.18):
    """Lettering on the kit body side (follows car.side_x), centred on yc, baseline z0."""
    def mapf(u, v):
        y, z = yc + side * u, z0 + v
        return (side * (car.side_x(y, z) + off), y, z)
    return emit_text(mb, text, height, mat, mapf, (side, 0, 0), stroke)


def rear_text(mb, y, text, xc, z0, height, mat, stroke=0.18):
    """Lettering on a rear face at y (seen from behind), centred on xc."""
    return emit_text(mb, text, height, mat, lambda u, v: (xc + u, y, z0 + v), (0, -1, 0), stroke)


def roof_text(mb, z, text, xc, yc, height, mat, stroke=0.18):
    """Lettering on a roof at height z, read from above with the nose pointing up; centred on (xc, yc)."""
    return emit_text(mb, text, height, mat, lambda u, v: (xc + u, yc - height / 2.0 + v, z), (0, 0, 1), stroke)


CREST = [(-0.42, 0.40), (-0.21, 0.50), (0.0, 0.42), (0.21, 0.50), (0.42, 0.40), (0.42, -0.02), (0.30, -0.28),
         (0.0, -0.50), (-0.30, -0.28), (-0.42, -0.02)]
FLAME = [(0.0, -0.34), (0.19, -0.24), (0.26, -0.04), (0.17, 0.16), (0.11, 0.02), (0.02, 0.38), (-0.13, 0.10),
         (-0.19, 0.17), (-0.27, -0.06), (-0.19, -0.25)]


def crest(mb, mapf, want, size, rim, field, kind="police", a=None, b_=None):
    """City crest as stacked flat polygons (same shield outline as the cruiser's HBPD emblem).
    mapf(u, v, off) -> (x, y, z) with off = metres proud of the panel.
    kind 'police': rising sun (a) over two wave bars (b_);  'fire': flame (a) over one wave bar (b_)."""
    def put(poly, mat, off, s=1.0):
        mb.face([mapf(u * size * s, v * size * s, off) for u, v in poly], mat, want=want)
    put(CREST, rim, 0.008)
    put(CREST, field, 0.011, 0.84)
    if kind == "police":
        r = 0.17
        put([(r * cos(pi * i / 6.0), 0.03 + r * sin(pi * i / 6.0)) for i in range(7)], a, 0.014)
        put([(-0.25, -0.10), (0.25, -0.10), (0.25, -0.04), (-0.25, -0.04)], b_, 0.014)
        put([(-0.17, -0.24), (0.17, -0.24), (0.17, -0.18), (-0.17, -0.18)], b_, 0.014)
    else:
        put(FLAME, a, 0.014, 0.80)
        put([(0.0, -0.26), (0.10, -0.20), (0.13, -0.06), (0.03, 0.10), (-0.06, -0.02), (-0.12, -0.18)], b_, 0.017, 0.80)


def side_crest(mb, car, side, yc, zc, size, rim, field, kind="police", a=None, b_=None):
    """crest() on the kit body side."""
    def mapf(u, v, off):
        y, z = yc + side * u, zc + v
        return (side * (car.side_x(y, z) + off), y, z)
    crest(mb, mapf, (side, 0, 0), size, rim, field, kind, a, b_)


# ------------------------------------------------------------------------------------------------
# geometry helpers (all work on a car_kit.MB mesh builder, car-local coordinates)
# ------------------------------------------------------------------------------------------------
def arc_points(yc, zc, R, z_cut, n=8):
    """(y, z) points of a wheel arch around (yc, zc), front end -> over the top -> rear end, cut off
    at height z_cut."""
    s = max(-0.999, min(0.999, (z_cut - zc) / R))
    a0 = asin(s)
    out = []
    for i in range(n + 1):
        t = a0 + (pi - 2.0 * a0) * i / n
        out.append((yc + R * cos(t), zc + R * sin(t)))
    return out


def arch_block(mb, hw, y0, y1, z0, z1, arches, side, top=None, under=None, well=None, ends=None, n=8):
    """Full-width solid block y0..y1 / z0..z1 with wheel-arch tunnels notched into its bottom.
    arches = [(yc, zc, R)].  `side` = material of the two visible flanks."""
    top = top or side
    under = under or side
    well = well or under
    ends = ends or side
    prof = [(y0, z1), (y1, z1), (y1, z0)]
    mats = [top, ends]
    for yc, zc, R in sorted(arches, key=lambda a: -a[0]):
        arc = arc_points(yc, zc, R, z0, n)
        mats.append(under)
        prof += arc
        mats += [well] * (len(arc) - 1)
    mats.append(under)
    prof.append((y0, z0))
    mats.append(ends)
    mb.prism(prof, -hw, hw, None, axis='X', mats=mats, cap_mat=side)


def arch_lip(mb, xe, yc, zc, Ra, mat, z_cut, n=8, out=0.022, grow=0.046):
    """Flared lip around an arch cut into a flat body side at x = +-xe."""
    secs = []
    for y, z in arc_points(yc, zc, Ra, z_cut - 0.02, n):
        dy_, dz_ = (y - yc) / Ra, (z - zc) / Ra
        xi, xo = xe - 0.03, xe + out
        ring = []
        for x, r in ((xi, Ra - 0.008), (xo, Ra - 0.008), (xo, Ra + grow * 0.5), (xo - 0.016, Ra + grow), (xi, Ra + grow)):
            ring.append((x, yc + dy_ * r, zc + dz_ * r))
        secs.append(ring)
    mb.loft(secs, mat, mirror=True)


def box_shell(mb, hw, y0, y1, z0, z1, mat, ch=0.07, end_ch=0.05, roof=None, bottom=None, front=None, rear=None):
    """Box body with chamfered roof edges and chamfered vertical end corners (one closed solid)."""
    roof = roof or mat
    bottom = bottom or mat

    def ring(y, inset):
        x = hw - inset
        return [(-x, y, z0), (x, y, z0), (x, y, z1 - ch), (x - ch, y, z1), (-(x - ch), y, z1), (-x, y, z1 - ch)]
    secs = [ring(y0, end_ch), ring(y0 + end_ch, 0.0), ring(y1 - end_ch, 0.0), ring(y1, end_ch)]
    faces = mb.loft(secs, mats=[bottom, mat, mat, roof, mat, mat], cap_mat=mat)
    if front or rear:
        for f in faces:
            if not f.is_valid:
                continue
            c = f.calc_center_median()
            if rear and abs(c.y - y0) < 1e-4:
                f.material_index = mb.mi(rear)
            if front and abs(c.y - y1) < 1e-4:
                f.material_index = mb.mi(front)


def light_bar(mb, M, y, z, width, depth=0.20, lens_h=0.09, base="trim", pattern="rb"):
    """Roof light bar standing on height z.  pattern: 'rb' = red left / blue right,
    'rbbr' = red outer + blue inner modules on both sides.  Returns the Siren marker position."""
    red, blue = siren_mats()
    bm_ = M[base]
    mb.box((width, depth, 0.035), (0, y, z + 0.045), bm_, bevel=0.008)
    for sx in (-1.0, 1.0):
        mb.box((0.06, depth * 0.5, 0.05), (sx * width * 0.36, y, z + 0.012), bm_)
    zl = z + 0.062 + lens_h / 2.0
    if pattern == "rbbr":
        for sx in (-1.0, 1.0):
            mb.box((width * 0.24, depth - 0.03, lens_h), (sx * width * 0.36, y, zl), red, bevel=0.02)
            mb.box((width * 0.16, depth - 0.03, lens_h), (sx * width * 0.145, y, zl), blue, bevel=0.02)
    else:
        for sx in (-1.0, 1.0):
            mb.box((width * 0.40, depth - 0.03, lens_h), (sx * width * 0.27, y, zl), red if sx < 0 else blue, bevel=0.02)
    mb.box((width * 0.11, depth - 0.05, lens_h * 0.85), (0, y, zl - 0.004), M["chrome"], bevel=0.012)
    return (0.0, y, z + 0.062 + lens_h)


def truck_wheel(mb, M, R=0.45, w=0.27, dual=False, lugs=0, segs=14):
    """Truck wheel, centre at the origin, axle along X, mirror-symmetric (same mesh left / right).
    dual=True: twin tyres with a deep-dish outer rim (rear axle); lugs = number of tread blocks."""
    tire, rim = M["tire"], M["rim"]
    R_full = R
    if lugs:
        R = R - 0.018                    # tread base; the blocks reach the full radius
    rr = R_full * 0.58
    sh = 0.045
    if not dual:
        hw = w / 2.0
        dish = 0.05
        prof = [(-hw + dish, 0.0), (-hw + dish, rr - 0.04), (-hw + 0.012, rr - 0.012), (-hw, rr), (-hw, R - sh),
                (-hw + sh, R), (hw - sh, R), (hw, R - sh), (hw, rr), (hw - 0.012, rr - 0.012), (hw - dish, rr - 0.04),
                (hw - dish, 0.0)]
        mats = [rim, rim, rim, tire, tire, tire, tire, tire, rim, rim, rim]
        mb.revolve(prof, axis='X', segs=segs, mats=mats)
        faces = [(hw - dish, 1.0), (-(hw - dish), -1.0)]
        hub = [(0.0, R_full * 0.34), (0.04, R_full * 0.30), (0.07, R_full * 0.15), (0.07, 0.0)]     # tip 2 cm proud of the tyre
        outer = hw
    else:
        g = 0.03
        xi, xo = g / 2.0, g / 2.0 + w
        dd = 0.13
        for s in (1.0, -1.0):
            prof = [(s * (xo - dd), 0.0), (s * (xo - dd), rr - 0.07), (s * (xo - 0.012), rr - 0.012), (s * xo, rr),
                    (s * xo, R - sh), (s * (xo - sh), R), (s * (xi + sh), R), (s * xi, R - sh), (s * xi, 0.0)]
            mb.revolve(prof, axis='X', segs=segs, mats=[rim, rim, rim, tire, tire, tire, tire, tire])
        faces = [(xo - dd, 1.0), (-(xo - dd), -1.0)]
        hub = [(0.0, R_full * 0.36), (0.07, R_full * 0.32), (0.115, R_full * 0.16), (0.115, 0.0)]
        outer = xo
    for x0, s in faces:
        mb.revolve([(x0 + s * t, r) for t, r in hub], rim, axis='X', segs=8)
        # hand holes: dark quads on the wheel disc
        r0, r1 = R_full * 0.37, rr - 0.045
        if not dual and r1 - r0 > 0.03:
            for i in range(6):
                a = 2.0 * pi * (i + 0.5) / 6
                da = 0.22
                pts = []
                for rr_, aa in ((r0, a - da), (r1, a - da * 0.8), (r1, a + da * 0.8), (r0, a + da)):
                    pts.append((x0 + s * 0.004, -rr_ * sin(aa), rr_ * cos(aa)))
                mb.face(pts, tire, want=(s, 0, 0))
    if lugs:                              # full-width tread bars, one per tyre facet (clean silhouette)
        hgt = 0.045
        ln = 2.0 * R * sin(pi / lugs) * 0.66
        rb = sqrt(max(R_full * R_full - ln * ln / 4.0, 0.01)) - hgt / 2.0      # bar corners end on R
        centres = [0.0] if not dual else [-(outer - w / 2.0), outer - w / 2.0]
        for i in range(lugs):
            a = 2.0 * pi * (i + 0.5) / lugs
            for cx in centres:
                mb.box((w - 0.05, ln, hgt), (cx, -rb * sin(a), rb * cos(a)), tire, rot=(a, 0.0, 0.0))
    return mb


# ------------------------------------------------------------------------------------------------
# Truck = car_kit.Car + cab-only mode, own wheels, livery materials, nested parts
# ------------------------------------------------------------------------------------------------
class Truck(K.Car):
    """Extra params on top of car_kit.DEFAULTS:
       livery / livery2   palette keys that replace M_Paint_Primary / M_Paint_Secondary (fixed liveries)
       cab_only           the kit shell is only the cab; axles outside it get own arches (extras)
       track_r, dual_rear rear track (centre of the twin pair) and twin rear tyres
       tyre_lugs          tread blocks per wheel (0 = plain)
       wheel_segs         wheel roundness
       engine_pos, exits  marker overrides: (x, y, z) / {marker name: (x, y, z)}
    """

    def __init__(self, params, location=(0, 0, 0), collection="Vehicles/Service"):
        super().__init__(params, location, collection)
        p = self.p
        if p.get("livery"):
            self.M["paint"] = G.pmat(p["livery"], rough=0.5)
        if p.get("livery2"):
            self.M["paint2"] = G.pmat(p["livery2"], rough=0.5)
        self.all_axles = list(self.axles)
        if p.get("cab_only"):
            self.axles = [a for a in self.axles if self.y_r <= a[1] <= self.y_f]
        self.nest = {}           # child part -> parent part (re-parented in finish)
        self.siren_pos = None

    # the kit versions assume a rear axle inside the shell
    def details(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy = g["cy"]
        span = g["xc"] * 0.52
        for sx in (-1.0, 1.0):
            x0 = sx * span * 0.5 - span * 0.25
            b.box((span, 0.02, 0.016), (x0, cy + 0.012, g["zc"] + 0.035 + p["crown"] * 0.5), M["trim"],
                  rot=(0, radians(-4), radians(3)))
        b.cyl(0.008, 0.40, (g["xr"] - 0.10, g["rr"] + 0.12, g["rz"] + 0.16), M["trim"], axis='Z', segments=5,
              rot=(radians(-20), 0, 0))

    def wheels(self):
        pass

    def wheel_positions(self):
        p = self.p
        out = []
        for tag, yc in self.all_axles:
            tr = p["track"] if tag == "F" else p.get("track_r", p["track"])
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                out.append(("Wheel_%s%s" % (tag, sfx), (side * tr / 2.0, yc, p["wheel_r"])))
        return out

    def _wheel_objects(self):
        p = self.p
        r = self.root
        meshes = {}
        for name, loc in self.wheel_positions():
            dual = bool(p.get("dual_rear")) and not name.startswith("Wheel_F")
            key = "WheelTwin" if dual else "Wheel"
            if key not in meshes:
                mb = truck_wheel(K.MB(), self.M, p["wheel_r"], p["wheel_w"], dual=dual, lugs=p.get("tyre_lugs", 0),
                                 segs=p.get("wheel_segs", 14))
                ob = mb.obj(self.n(name), r, smooth=35.0)
                ob.data.name = self.n(key)
                meshes[key] = ob.data
            else:
                ob = bpy.data.objects.new(self.n(name), meshes[key])
                for c in r.users_collection:
                    c.objects.link(ob)
                    break
                ob.parent = r
            ob.location = loc
            self.objects[name] = ob

    def finish(self):
        root = super().finish()
        self._wheel_objects()
        p = self.p
        for child, parent in self.nest.items():
            c, pr = self.objects.get(child), self.objects.get(parent)
            if c is not None and pr is not None:
                c.parent = pr
                c.location = Vector(c.location) - Vector(pr.location)
        over = dict(p.get("exits") or {})
        if p.get("engine_pos"):
            over["Engine"] = p["engine_pos"]
        for name, loc in over.items():
            ob = bpy.data.objects.get(self.n(name))
            if ob is not None:
                ob.location = loc
        bpy.context.view_layer.update()
        return root

    # ------------------------------------------------------------ shared truck parts
    def side_band(self, mb, ya, yb, z0, z1, mat, side=1.0, both=False, proud=0.010):
        """Livery band on the cab side between heights z0..z1 (follows the body side)."""
        keys = sorted({k for k, _ in self.plan} | {k for k, _ in self.top})
        ys = [ya] + [s for s in keys if ya + 0.02 < s < yb - 0.02] + [yb]
        secs = []
        for y in ys:
            zt_ = min(z1, self.zt(y) - self.p["crease_drop"] - 0.012)      # stay on the flat flank
            if zt_ - z0 < 0.025:
                break
            xa, xb = self.side_x(y, z0), self.side_x(y, zt_)
            secs.append([(side * (xa - 0.008), y, z0), (side * (xa + proud), y, z0),
                         (side * (xb + proud), y, zt_), (side * (xb - 0.008), y, zt_)])
        if len(secs) >= 2:
            mb.loft(secs, mat, mirror=both)

    def cab_band(self, z0, z1, mat, y_front=None):
        """Band along the whole cab: body parts into Body, door parts into the Door_* objects."""
        g2 = self.p["seam"] / 2.0 + 0.004
        y = self.y_r + 0.004
        end = y_front if y_front is not None else self.y_f - 0.30
        for tag, a, b in sorted(self.doors, key=lambda d: d[1]):
            if a - g2 - y > 0.05:
                self.side_band(self.body, y, a - g2, z0, z1, mat, both=True)
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                self.side_band(self.mb("Door_%s%s" % (tag, sfx)), a + g2, b - g2, z0, z1, mat, side=side)
            y = b + g2
        if end - y > 0.05:
            self.side_band(self.body, y, end, z0, z1, mat, both=True)

    def lean_strip(self, mat, z=None, half=0.019, y_rear=None, y_front=None):
        """Low-poly replacement for the kit rub strip (set side_strip=None): stations only where the
        plan outline bends.  Body parts go into Body, door parts into the Door_* objects."""
        z = self.p["swage_z"] if z is None else z
        g2 = self.p["seam"] / 2.0 + 0.004
        keys = [k for k, _ in self.plan]

        def piece(mb, ya, yb, side=1.0, both=False):
            ys = [ya] + [k for k in keys if ya + 0.02 < k < yb - 0.02] + [yb]
            secs = []
            for y in ys:
                x = self.side_x(y, z)
                secs.append([(side * (x - 0.006), y, z - half), (side * (x + 0.013), y, z - half),
                             (side * (x + 0.013), y, z + half), (side * (x - 0.006), y, z + half)])
            mb.loft(secs, mat, mirror=both)
        cuts = []
        for _, yc in self.axles:
            dz = z - self.zc
            if abs(dz) < self.Ra:
                h = sqrt(self.Ra ** 2 - dz ** 2) + 0.06
                cuts.append((yc - h, yc + h))

        def spans(ya, yb):
            out = [(ya, yb)]
            for ca, cb in cuts:
                nxt = []
                for a_, b_ in out:
                    if cb <= a_ or ca >= b_:
                        nxt.append((a_, b_))
                    else:
                        if ca - a_ > 0.05:
                            nxt.append((a_, ca))
                        if b_ - cb > 0.05:
                            nxt.append((cb, b_))
                out = nxt
            return out
        y = self.y_r + 0.03 if y_rear is None else y_rear
        end = self.y_f - 0.03 if y_front is None else y_front
        for tag, a, b in sorted(self.doors, key=lambda d: d[1]):
            if a - g2 - y > 0.05:
                for sa, sb in spans(y, a - g2):
                    piece(self.body, sa, sb, both=True)
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                for sa, sb in spans(a + g2, b - g2):
                    piece(self.mb("Door_%s%s" % (tag, sfx)), sa, sb, side=side)
            y = b + g2
        if end - y > 0.05:
            for sa, sb in spans(y, end):
                piece(self.body, sa, sb, both=True)

    def front_bumper(self, mat, z0, h, out=0.08, wrap=0.34, plate=True, lamps=True, valance=True):
        """Front bumper in any material (the kit one is always body colour)."""
        M, b = self.M, self.body
        yf = self.y_f
        wc = self.w(yf)
        z1 = z0 + h
        prof = [(-0.07, z0), (out * 0.45, z0), (out, z0 + 0.045), (out, z1 - 0.05), (out * 0.5, z1), (-0.07, z1)]
        b.sweep(self.u_path(True, wrap), prof, mat)
        if valance:
            b.sweep(self.u_path(True, wrap * 0.55), [(-0.07, z0 - 0.05), (out * 0.2, z0 - 0.05), (out * 0.45, z0 + 0.004),
                                                    (-0.07, z0 + 0.004)], M["trim"])
        if lamps:
            b.box((0.16, 0.03, 0.06), (wc - 0.16, yf + out - 0.004, z0 + h * 0.5), M["indicator"], mirror=True)
        if plate:
            b.box((0.32, 0.016, 0.12), (0, yf + out + 0.012, z0 + h * 0.5), M["plate"])
            b.box((0.35, 0.012, 0.15), (0, yf + out + 0.004, z0 + h * 0.5), M["trim"])
        self.bumper_f_z = (z0, z1)

    def cab_collision(self, box=None):
        """Col_Body = lower cab hull, Col_Cabin = greenhouse, optional Col_Box = (hw, y0, y1, z0, z1, ch)."""
        M = self.M
        g = self._gh()
        zlo = min(z for _, z in self.bottom_keys) + 0.02
        prof = [(y, self.zt(y)) for y, _ in self.top]
        low = [(self.y_f, max(K.interp(self.bottom_keys, self.y_f), zlo)), (self.y_f - 0.25, zlo), (self.y_r, zlo)]
        poly = prof + low
        wmax = self.hw * 0.985
        self.mb("Col_Body").loft([[(-wmax, y, z) for y, z in poly], [(wmax, y, z) for y, z in poly]], M["col"])
        zb = min(g["zc"], g["zd"]) - 0.03
        self.mb("Col_Cabin").loft(
            [[(-g["xd"], g["dy"], zb), (g["xd"], g["dy"], zb), (g["xc"], g["cy"], zb), (-g["xc"], g["cy"], zb)],
             [(-g["xr"], g["rr"], g["rz"]), (g["xr"], g["rr"], g["rz"]), (g["xr"], g["rf"], g["rz"]), (-g["xr"], g["rf"], g["rz"])]],
            M["col"])
        if box:
            hw, y0, y1, z0, z1, ch = box
            self.mb("Col_Box").loft(
                [[(-hw, y, z0), (hw, y, z0), (hw, y, z1 - ch), (hw - ch, y, z1), (-(hw - ch), y, z1), (-hw, y, z1 - ch)]
                 for y in (y0, y1)], M["col"])


# ------------------------------------------------------------------------------------------------
# AMBULANCE  -  van-chassis cab + modular box body, 6.05 m
# ------------------------------------------------------------------------------------------------
AMBULANCE = dict(K.DEFAULTS)
AMBULANCE.update(
    name="ambulance", livery="AmbulanceWhite", cab_only=True,
    width=2.02, height=2.05,
    axle_f=1.95, axle_r=-1.45, wheel_r=0.42, wheel_w=0.26, track=1.71, track_r=1.63, dual_rear=True,
    arch_gap=0.055, arch_lip="trim",
    # cab shell only: cab back -> nose
    top=[(0.42, 1.28), (1.72, 1.25), (2.62, 1.10), (2.93, 0.96)],
    bottom=[(0.42, 0.44), (2.55, 0.42), (2.93, 0.52)],
    plan=[(0.42, 1.0), (2.50, 1.0), (2.78, 0.96), (2.93, 0.88)],
    shoulder_inset=0.07, swage_z=0.82, rocker_z=0.54, tub_z=0.46,
    seat_z=0.84, seat_x=0.50, seat_f_y=0.84, seat_r_y=None,
    cowl_y=1.72, roof_f=1.30, roof_r=0.52, deck_y=0.46, tumble=0.09,
    a_pillar=0.12, c_pillar=(0.10, 0.10), b_pillar=None,
    doors=[("F", 0.56, 1.38)], trunk=None, hood="auto",
    head=dict(w=0.30, h=0.17, inset=0.03, z=None), grille=dict(bars=3),
    tail=None, bumper_f=None, bumper_r=None, exhaust=None, plate_r=False,
    siren=True, side_strip=None,
)
AMB = dict(HW=1.13, Y0=-2.95, Y1=0.44, ZS=0.50, ZF=1.06, ZT=2.72)


def ambulance_body(car):
    p, M, b = car.p, car.M, car.body
    white = M["paint"]
    teal = G.pmat("Teal", rough=0.5)
    st = steel()
    red, blue = siren_mats()
    HW, Y0, Y1, ZS, ZF, ZT = (AMB[k] for k in ("HW", "Y0", "Y1", "ZS", "ZF", "ZT"))
    R = p["wheel_r"]
    Ra = R + 0.06
    yr = p["axle_r"]
    # ---- box: skirt with the rear arch tunnel + upper shell + fairing over the cab roof
    arch_block(b, HW, Y0, Y1, ZS, ZF + 0.01, [(yr, R, Ra)], white, top=M["under"], under=M["under"], well=M["under"])
    arch_lip(b, HW, yr, R, Ra, M["trim"], ZS)
    box_shell(b, HW, Y0, Y1, ZF, ZT, white, ch=0.09, end_ch=0.06)
    zb = p["height"] - 0.03

    def cap(y, hx, zt_, c):
        return [(-hx, y, zb), (hx, y, zb), (hx, y, zt_ - c), (hx - c, y, zt_), (-(hx - c), y, zt_), (-hx, y, zt_ - c)]
    b.loft([cap(Y1 - 0.02, HW - 0.07, ZT - 0.02, 0.09), cap(0.92, 0.98, ZT - 0.12, 0.08), cap(1.33, 0.86, zb + 0.10, 0.04)], white)
    # ---- frame, rear axle, exhaust, mud flaps
    b.box((0.10, 2.9, 0.16), (0.42, -1.2, 0.56), M["under"], mirror=True)
    b.cyl(0.07, 1.5, (0, yr, R), M["under"], axis='X', segments=6)
    b.cyl(0.17, 0.30, (0, yr, R), M["under"], axis='Y', segments=8)
    b.box((0.50, 0.02, 0.34), (HW - 0.29, yr - Ra - 0.06, 0.50), M["trim"], mirror=True)
    b.cyl(0.04, 0.5, (HW - 0.22, -2.35, 0.46), M["chrome"], axis='X', segments=8)
    car.exhaust_pos = (HW + 0.02, -2.35, 0.46)
    # ---- livery: teal band + emblem (plus in a circle)
    z0, z1 = 0.97, 1.15
    b.box((0.012, (Y1 - 0.06) - (yr + Ra + 0.09), z1 - z0), (HW + 0.002, ((Y1 - 0.06) + (yr + Ra + 0.09)) / 2.0, (z0 + z1) / 2.0), teal, mirror=True)
    b.box((0.012, (yr - Ra - 0.09) - (Y0 + 0.07), z1 - z0), (HW + 0.002, ((yr - Ra - 0.09) + (Y0 + 0.07)) / 2.0, (z0 + z1) / 2.0), teal, mirror=True)
    b.box((0.012, 2.0 * Ra + 0.18, 0.06), (HW + 0.002, yr, z1 - 0.03), teal, mirror=True)
    car.cab_band(z0, z1, teal, y_front=2.72)
    car.lean_strip(M["trim"])
    orange = G.pmat("SafetyOrange", rough=0.5)                 # thin accent stripe under the teal band
    zo0, zo1 = 0.925, 0.955
    b.box((0.012, (Y1 - 0.06) - (Y0 + 0.07), zo1 - zo0), (HW + 0.002, ((Y1 - 0.06) + (Y0 + 0.07)) / 2.0, (zo0 + zo1) / 2.0), orange, mirror=True)
    car.cab_band(zo0, zo1, orange, y_front=2.72)
    ye, ze, re = -2.12, 1.92, 0.36
    b.cyl(re, 0.014, (HW + 0.004, ye, ze), teal, axis='X', segments=16, mirror=True)
    b.box((0.012, re * 1.30, re * 0.40), (HW + 0.014, ye, ze), white, mirror=True)
    b.box((0.012, re * 0.40, re * 1.30), (HW + 0.014, ye, ze), white, mirror=True)
    # ---- box sides: windows (left), side door with window (right), lockers, scene lights
    gl = car.mb("Glass_Box_L")
    gr = car.mb("Glass_Box_R")
    wz0, wz1 = 1.72, 2.20
    b.box((0.02, 0.92, wz1 - wz0 + 0.08), (-(HW + 0.004), -0.62, (wz0 + wz1) / 2.0), M["trim"])
    b.box((0.012, 0.84, wz1 - wz0), (-(HW + 0.012), -0.62, (wz0 + wz1) / 2.0), M["interior"])
    gl.face([(-(HW + 0.022), -1.04, wz0), (-(HW + 0.022), -0.20, wz0), (-(HW + 0.022), -0.20, wz1), (-(HW + 0.022), -1.04, wz1)],
            M["glass"], want=(-1, 0, 0))
    dy0, dy1, dz0, dz1 = -0.66, 0.20, 0.72, 2.42          # side door (kerb side)
    b.box((0.022, dy1 - dy0, dz1 - dz0), (HW + 0.004, (dy0 + dy1) / 2.0, (dz0 + dz1) / 2.0), white, bevel=0.012)
    for yy in (dy0 - 0.012, dy1 + 0.012):
        b.box((0.012, 0.022, dz1 - dz0 + 0.03), (HW + 0.002, yy, (dz0 + dz1) / 2.0), M["trim"])
    b.box((0.012, dy1 - dy0 + 0.04, 0.022), (HW + 0.002, (dy0 + dy1) / 2.0, dz1 + 0.012), M["trim"])
    b.box((0.02, 0.58, wz1 - wz0 + 0.08), (HW + 0.012, (dy0 + dy1) / 2.0, (wz0 + wz1) / 2.0), M["trim"])
    b.box((0.012, 0.50, wz1 - wz0), (HW + 0.020, (dy0 + dy1) / 2.0, (wz0 + wz1) / 2.0), M["interior"])
    ym = (dy0 + dy1) / 2.0
    gr.face([(HW + 0.030, ym - 0.25, wz0), (HW + 0.030, ym + 0.25, wz0), (HW + 0.030, ym + 0.25, wz1), (HW + 0.030, ym - 0.25, wz1)],
            M["glass"], want=(1, 0, 0))
    b.box((0.03, 0.035, 0.20), (HW + 0.03, dy0 + 0.10, 1.34), M["chrome"], bevel=0.008)
    b.box((0.012, dy1 - dy0 - 0.02, z1 - z0), (HW + 0.017, ym, (z0 + z1) / 2.0), teal)
    b.box((0.012, dy1 - dy0 - 0.02, zo1 - zo0), (HW + 0.017, ym, (zo0 + zo1) / 2.0), orange)
    b.box((0.16, 0.66, 0.035), (HW + 0.05, ym, ZS + 0.03), st, bevel=0.008)                    # side step
    for sx, (ya, yb, za, zc_) in ((-1.0, (-0.10, 0.34, 1.24, 2.40)), (-1.0, (-2.84, -2.10, 1.24, 1.50)),
                                  (1.0, (-2.84, -2.10, 1.24, 1.50)), (-1.0, (-0.95, 0.34, 0.60, 0.92)),
                                  (1.0, (-0.95, -0.74, 0.60, 0.92)), (-1.0, (-2.84, -2.06, 0.60, 0.92)),
                                  (1.0, (-2.84, -2.06, 0.60, 0.92))):
        b.box((0.012, yb - ya + 0.028, zc_ - za + 0.028), (sx * (HW + 0.001), (ya + yb) / 2.0, (za + zc_) / 2.0), M["trim"])   # shut line
        b.box((0.016, yb - ya, zc_ - za), (sx * (HW + 0.004), (ya + yb) / 2.0, (za + zc_) / 2.0), white)   # locker doors
        b.box((0.022, 0.10, 0.03), (sx * (HW + 0.018), yb - 0.09, (za + zc_) / 2.0), M["chrome"])
    for sx, yc_ in ((-1.0, -1.10), (1.0, -1.385)):             # lettering under the windows
        flank_text(b, sx, HW + 0.006, "MEDIC", yc_, 1.30, 0.26, teal, stroke=0.2)
    roof_text(b, ZT + 0.004, "3", 0.0, -0.28, 0.70, teal, stroke=0.2)
    for yy in (Y0 + 0.30, Y1 - 0.30):                       # high side warning lamps + scene lights
        b.box((0.03, 0.24, 0.10), (HW + 0.004, yy, 2.50), red, mirror=True)
    b.box((0.03, 0.30, 0.10), (HW + 0.004, (Y0 + Y1) / 2.0, 2.50), M["chrome"], mirror=True)
    for yy in (Y0 + 0.16, yr + Ra + 0.30, Y1 - 0.16):       # side markers on the skirt
        b.box((0.016, 0.09, 0.04), (HW + 0.004, yy, ZS + 0.15), M["indicator"], mirror=True)
    # ---- roof: AC unit, vent, clearance lights, light bar
    b.box((0.80, 1.10, 0.14), (0.0, -1.45, ZT + 0.06), white, bevel=0.035)
    b.box((0.60, 0.012, 0.07), (0.0, -1.45 + 0.555, ZT + 0.07), M["trim"])
    b.cyl(0.12, 0.08, (0.0, -2.45, ZT + 0.03), st, axis='Z', segments=8)
    for xx in (-0.78, -0.26, 0.26, 0.78):
        b.box((0.09, 0.03, 0.035), (xx, Y0 + 0.005, ZT - 0.13), red)
    car.siren_pos = light_bar(b, M, Y1 + 0.20, ZT - 0.012, 1.80, depth=0.22, lens_h=0.10)
    b.box((0.26, 0.04, 0.09), (0.50, 0.98, 2.52), red, mirror=True, rot=(radians(-14), 0, 0), bevel=0.012)   # fairing flashers
    b.box((0.26, 0.04, 0.09), (0.0, 0.98, 2.52), M["chrome"], rot=(radians(-14), 0, 0), bevel=0.012)
    # ---- rear: barn doors (Door_RL / Door_RR) with nested panes, lamp columns, step bumper
    b.face([(-0.84, Y0 - 0.002, 0.66), (0.84, Y0 - 0.002, 0.66), (0.84, Y0 - 0.002, 2.44), (-0.84, Y0 - 0.002, 2.44)],
           M["interior"], want=(0, -1, 0))
    x0, x1, zd0, zd1 = 0.010, 0.82, 0.66, 2.44
    for side, sfx in ((-1.0, "L"), (1.0, "R")):
        d = car.mb("Door_R" + sfx)
        d.box((x1 - x0, 0.045, zd1 - zd0), (side * (x0 + x1) / 2.0, Y0 - 0.0245, (zd0 + zd1) / 2.0), white, bevel=0.012)
        d.box((0.50, 0.012, 0.56), (side * 0.42, Y0 - 0.049, 1.98), M["trim"])
        d.box((0.42, 0.010, 0.48), (side * 0.42, Y0 - 0.054, 1.98), M["interior"])
        d.box((0.035, 0.03, 0.24), (side * 0.10, Y0 - 0.058, 1.34), M["chrome"], bevel=0.008)
        d.box((x1 - x0 - 0.03, 0.010, z1 - z0), (side * (x0 + x1) / 2.0, Y0 - 0.05, (z0 + z1) / 2.0), teal)
        d.box((x1 - x0 - 0.03, 0.010, zo1 - zo0), (side * (x0 + x1) / 2.0, Y0 - 0.05, (zo0 + zo1) / 2.0), orange)
        rear_text(d, Y0 - 0.052, "MEDIC" if side < 0 else "3", side * 0.45, 1.44, 0.15, teal, stroke=0.2)
        for zz in (0.90, 1.55, 2.20):
            d.box((0.05, 0.03, 0.09), (side * (x1 - 0.02), Y0 - 0.055, zz), M["chrome"])
        gname = "Glass_Rear_" + sfx
        car.mb(gname).face([(side * 0.22, Y0 - 0.061, 1.75), (side * 0.62, Y0 - 0.061, 1.75), (side * 0.62, Y0 - 0.061, 2.21),
                            (side * 0.22, Y0 - 0.061, 2.21)], M["glass"], want=(0, -1, 0))
        car.nest[gname] = "Door_R" + sfx
        car.origins["Door_R" + sfx] = ((side * x1, Y0 - 0.0245, zd0), None)
    xl = (0.84 + HW - 0.06) / 2.0 + 0.01
    b.box((0.19, 0.03, 0.80), (xl, Y0 + 0.004, 1.22), M["trim"], mirror=True)
    b.box((0.15, 0.04, 0.26), (xl, Y0 - 0.008, 1.46), M["tail"], mirror=True, bevel=0.012)
    b.box((0.15, 0.04, 0.20), (xl, Y0 - 0.008, 1.20), M["indicator"], mirror=True, bevel=0.012)
    b.box((0.15, 0.04, 0.18), (xl, Y0 - 0.008, 0.97), M["reverse"], mirror=True, bevel=0.012)
    b.box((0.19, 0.04, 0.12), (xl, Y0 + 0.0, 2.50), red, mirror=True, bevel=0.012)
    car.tail_pos = (xl, Y0 - 0.05, 1.46)
    b.box((2.0 * HW - 0.04, 0.20, 0.07), (0, Y0 - 0.06, ZS + 0.035), st, bevel=0.012)
    b.box((2.0 * HW - 0.30, 0.16, 0.10), (0, Y0 + 0.02, ZS - 0.05), M["trim"])
    b.box((0.32, 0.016, 0.12), (0, Y0 - 0.165, ZS - 0.035), M["plate"])
    b.box((0.36, 0.02, 0.16), (0, Y0 - 0.15, ZS - 0.035), M["trim"])
    b.box((0.12, 0.03, 0.05), (HW - 0.22, Y0 - 0.162, ZS + 0.035), M["tail"], mirror=True)


def ambulance_lod(car):
    p, M = car.p, car.M
    lb = car.mb("Body_LOD1")
    white = M["paint"]
    teal = G.pmat("Teal", rough=0.5)
    HW, Y0, Y1, ZS, ZF, ZT = (AMB[k] for k in ("HW", "Y0", "Y1", "ZS", "ZF", "ZT"))
    R = p["wheel_r"]
    arch_block(lb, HW, Y0, Y1, ZS, ZF, [(p["axle_r"], R, R + 0.06)], white, under=M["under"], n=3)
    lb.box((2 * HW, Y1 - Y0, ZT - ZF), (0, (Y0 + Y1) / 2.0, (ZF + ZT) / 2.0), white)
    lb.box((1.8, 0.9, ZT - 0.1 - p["height"]), (0, Y1 + 0.40, (ZT - 0.1 + p["height"]) / 2.0), white)
    lb.box((0.02, Y1 - Y0 - 0.1, 0.18), (HW, (Y0 + Y1) / 2.0, 1.06), teal, mirror=True)
    red, blue = siren_mats()
    lb.box((0.7, 0.2, 0.1), (-0.45, Y1 + 0.2, ZT + 0.08), red)
    lb.box((0.7, 0.2, 0.1), (0.45, Y1 + 0.2, ZT + 0.08), blue)
    lb.box((0.16, 0.03, 0.5), (0.95, Y0, 1.25), M["tail"], mirror=True)


def build_ambulance():
    car = Truck(AMBULANCE, G.slot("service", SLOTS["ambulance"]), COLLECTIONS["ambulance"])
    car.skin()
    car.greenhouse()
    car.parts.pop("Glass_Rear", None)          # the cab back is covered by the box
    car.interior()
    car.bays()
    car.front_fascia()
    car.front_bumper(car.M["chrome"], 0.47, 0.26, out=0.07)
    car.details()
    car.closures()
    ambulance_body(car)
    car.cab_collision(box=(AMB["HW"], AMB["Y0"], AMB["Y1"], AMB["ZS"], AMB["ZT"], 0.09))
    car.lod()
    ambulance_lod(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# FIRETRUCK  -  cab-over crew-cab pumper with tandem rear axles, 8.1 m
# ------------------------------------------------------------------------------------------------
FIRETRUCK = dict(K.DEFAULTS)
FIRETRUCK.update(
    name="firetruck", livery="FireRed", livery2="White", cab_only=True,
    width=2.46, height=2.80,
    axle_f=2.50, axle_m=-1.44, axle_r=-2.76, wheel_r=0.50, wheel_w=0.29, track=2.10, track_r=1.82, dual_rear=True,
    arch_gap=0.06, arch_lip="chrome", wheel_segs=12, arch_segs=6,
    # flat-faced cab: cab back -> nose
    top=[(1.00, 1.80), (3.78, 1.80), (3.90, 1.72)],
    bottom=[(1.00, 0.64), (3.90, 0.64)],
    plan=[(1.00, 1.0), (3.70, 1.0), (3.90, 0.93)],
    crown=0.0, shoulder_inset=0.05, crease_drop=0.08, crease_inset=0.0, swage_z=1.18, rocker_z=0.84,
    rocker_inset=0.0, sill_inset=0.03, rocker_mat="paint", side_strip=None,
    tub_z=0.98, seat_z=1.40, seat_x=0.68, seat_f_y=2.74, seat_r_y=1.46,
    cowl_y=3.78, roof_f=3.60, roof_r=1.10, deck_y=1.05, tumble=0.05, roof_t=0.07,
    a_pillar=0.14, c_pillar=(0.12, 0.12), b_pillar=0.10, pillar_w=0.07,
    pillars_extra=[(1.84, 1.96, 1.84, 1.96)],
    doors=[("F", 2.90, 3.74), ("R", 1.10, 1.84)], hood=None, trunk=None, roof_mat="paint2",
    head=dict(w=0.34, h=0.20, inset=0.08, z=1.00), grille=None,
    tail=None, bumper_f=None, bumper_r=None, exhaust=None, plate_r=False,
    siren=True, engine_pos=(0.0, 3.80, 1.50),
)
FT = dict(HW=1.25, Y0=-3.92, Y1=0.92, ZS=0.64, Z1=1.30, ZT=2.30)


def _shutter(mb, M, x, ya, yb, za, zb, lines=0):
    """Roll-up locker door on both flanks (x = +-x)."""
    st = steel()
    mb.box((0.02, yb - ya, zb - za), (x + 0.004, (ya + yb) / 2.0, (za + zb) / 2.0), st, mirror=True)
    mb.box((0.03, yb - ya - 0.12, 0.035), (x + 0.02, (ya + yb) / 2.0, za + 0.07), M["chrome"], mirror=True)
    for i in range(lines):
        zz = za + 0.16 + (zb - za - 0.22) * (i + 0.5) / lines
        mb.box((0.006, yb - ya - 0.04, 0.012), (x + 0.015, (ya + yb) / 2.0, zz), steel_dark(), mirror=True)


def firetruck_body(car):
    p, M, b = car.p, car.M, car.body
    red, white, chrome = M["paint"], M["paint2"], M["chrome"]
    st, sd = steel(), steel_dark()
    khaki = G.pmat("Khaki", rough=0.8)
    yellow = G.pmat("HazardYellow", rough=0.5)
    sred, sblue = siren_mats()
    HW, Y0, Y1, ZS, Z1, ZT = (FT[k] for k in ("HW", "Y0", "Y1", "ZS", "Z1", "ZT"))
    R = p["wheel_r"]
    Ra = R + 0.06
    ym, yr = p["axle_m"], p["axle_r"]
    # ---- body: locker skirt with tandem arches, high-side body, bellows to the cab
    arch_block(b, HW, Y0, Y1, ZS, Z1 + 0.01, [(ym, R, Ra), (yr, R, Ra)], red, top=M["under"], under=M["under"], well=M["under"])
    for yc in (ym, yr):
        arch_lip(b, HW, yc, R, Ra, chrome, ZS, n=6)
        b.cyl(0.08, 1.6, (0, yc, R), M["under"], axis='X', segments=6)
    b.cyl(0.19, 1.5, (0, (ym + yr) / 2.0, R), M["under"], axis='Y', segments=6)
    box_shell(b, HW, Y0, Y1, Z1, ZT, red, ch=0.06, end_ch=0.04)
    b.box((2 * HW - 0.26, 0.12, 1.50), (0, Y1 + 0.04, 1.52), M["trim"])
    b.cyl(0.05, 0.40, (HW - 0.18, 1.20, 0.56), chrome, axis='X', segments=8)
    car.exhaust_pos = (HW + 0.04, 1.20, 0.56)
    # ---- livery band (white) on cab and body
    zb0, zb1 = 1.25, 1.37
    car.cab_band(zb0, zb1, white, y_front=3.86)
    b.box((0.012, -0.02 - Y0 - 0.05, zb1 - zb0), (HW + 0.002, (-0.02 + Y0 + 0.05) / 2.0, (zb0 + zb1) / 2.0), white, mirror=True)
    # ---- lockers (roll-up shutters)
    _shutter(b, M, HW, ym + Ra + 0.07, -0.04, 0.72, 1.21)
    _shutter(b, M, HW, Y0 + 0.08, yr - Ra - 0.07, 0.72, 1.21)
    _shutter(b, M, HW, Y0 + 0.08, -2.64, 1.41, 2.18, lines=2)
    _shutter(b, M, HW, -2.58, -1.34, 1.41, 2.18, lines=2)
    _shutter(b, M, HW, -1.28, -0.04, 1.41, 2.18, lines=2)
    # ---- pump panel (both sides): steel panel, gauges, discharges, intake
    b.box((0.02, 0.80, 1.26), (HW + 0.004, 0.46, 1.42), st, mirror=True)
    for yy, zz, rr in ((0.28, 1.84, 0.09), (0.62, 1.84, 0.07)):
        b.cyl(rr, 0.03, (HW + 0.02, yy, zz), chrome, axis='X', segments=8, mirror=True)
        ring = [(HW + 0.037, yy + rr * 0.72 * cos(2 * pi * i / 8), zz + rr * 0.72 * sin(2 * pi * i / 8)) for i in range(8)]
        b.face(ring, white, mirror=True, want=(1, 0, 0))
    for yy in (0.24, 0.68):
        b.cyl(0.065, 0.12, (HW + 0.06, yy, 1.42), chrome, axis='X', segments=6, mirror=True)
        b.cyl(0.05, 0.03, (HW + 0.13, yy, 1.42), red, axis='X', segments=6, mirror=True)
    b.cyl(0.11, 0.14, (HW + 0.07, 0.46, 1.03), chrome, axis='X', segments=8, mirror=True)
    b.cyl(0.085, 0.03, (HW + 0.15, 0.46, 1.03), M["trim"], axis='X', segments=8, mirror=True)
    b.box((0.012, 0.50, 0.05), (HW + 0.016, 0.46, 1.62), M["trim"], mirror=True)            # lever strip
    for yy in (Y0 + 0.14, -2.10, 0.62):                      # side markers
        b.box((0.016, 0.10, 0.045), (HW + 0.004, yy, ZS + 0.05), M["indicator"], mirror=True)
    for yy in (Y0 + 0.30, 0.46):                              # high side flashers
        b.box((0.03, 0.26, 0.07), (HW + 0.004, yy, 2.235), sred, mirror=True)
    # ---- top deck: hose reels + monitor over the pump, hose bed, roof ladder, suction hoses
    for sx in (-1.0, 1.0):
        xc = sx * 0.58
        b.cyl(0.21, 0.62, (xc, 0.46, ZT + 0.29), M["trim"], axis='X', segments=10)
        for dx in (-0.33, 0.33):
            b.cyl(0.28, 0.035, (xc + dx, 0.46, ZT + 0.29), red, axis='X', segments=10)
        b.box((0.74, 0.30, 0.05), (xc, 0.46, ZT + 0.02), st)
    b.cyl(0.09, 0.22, (0, 0.46, ZT + 0.11), red, axis='Z', segments=8)
    b.cyl(0.05, 0.56, (0, 0.62, ZT + 0.33), chrome, axis='Y', segments=6, radius2=0.035, rot=(radians(24), 0, 0))
    b.box((1.24, 3.50, 0.06), (0, -2.02, ZT + 0.03), G.pmat("Cream"))
    for xx in (-0.37, -0.12, 0.12, 0.37):
        b.box((0.02, 3.46, 0.012), (xx, -2.02, ZT + 0.064), khaki)
    # two-section extension ladder standing on edge in a rack (kerb side): reads in the side silhouette
    for xx, ya, yb, za, zb, nr in ((1.13, -3.74, -0.26, ZT + 0.10, ZT + 0.52, 9), (1.045, -3.50, -0.42, ZT + 0.13, ZT + 0.49, 8)):
        for zz in (za, zb):
            b.box((0.035, yb - ya, 0.065), (xx, (ya + yb) / 2.0, zz), st)
        for i in range(nr):
            b.box((0.028, 0.035, zb - za - 0.06), (xx, ya + 0.22 + (yb - ya - 0.44) * i / (nr - 1), (za + zb) / 2.0), st)
    for yy in (-3.28, -2.00, -0.72):                          # rack brackets
        b.box((0.24, 0.07, 0.10), (1.085, yy, ZT + 0.03), M["trim"])
        b.box((0.05, 0.07, 0.50), (0.985, yy, ZT + 0.25), M["trim"])
    b.box((0.24, 3.30, 0.17), (0.80, -2.00, ZT + 0.085), sd, bevel=0.02)          # long equipment locker
    for yy in (-3.20, -2.00, -0.80):
        b.box((0.10, 0.03, 0.02), (0.80, yy, ZT + 0.18), chrome)
    b.cyl(0.022, 3.10, (-0.70, -2.00, ZT + 0.20), yellow, axis='Y', segments=5)       # pike pole on the hose bed edge
    b.box((0.03, 0.14, 0.09), (-0.70, -0.40, ZT + 0.20), st)
    for yy in (-3.30, -0.80):
        b.box((0.07, 0.05, 0.14), (-0.70, yy, ZT + 0.13), M["trim"])
    for xx in (-0.80, -1.03):                                 # hard suction hoses (road side)
        b.cyl(0.075, 3.00, (xx, -2.00, ZT + 0.085), M["trim"], axis='Y', segments=6)
        for yy in (-3.50, -0.50):
            b.cyl(0.088, 0.12, (xx, yy, ZT + 0.085), chrome, axis='Y', segments=6)
    # ---- rear: shutter, chevrons, lamp columns, tailboard, grab rails
    b.box((1.44, 0.02, 0.77), (0, Y0 - 0.004, 1.795), st)
    b.box((1.30, 0.03, 0.035), (0, Y0 - 0.02, 1.48), chrome)
    for i in range(2):
        b.box((1.40, 0.006, 0.012), (0, Y0 - 0.015, 1.72 + i * 0.22), steel_dark())
    ys_ = Y0 - 0.006
    for sx in (-1.0, 1.0):                                     # hazard chevrons on the lower rear panel
        for i in range(4):
            x0 = 0.02 + i * 0.30
            pts = [(x0, 0.72), (x0 + 0.15, 0.72), (x0 + 0.65, 1.30), (x0 + 0.50, 1.30)]
            b.face([(sx * min(x, 1.21), ys_, z) for x, z in pts], yellow, want=(0, -1, 0))
    xl = 1.03
    b.box((0.26, 0.03, 0.74), (xl, Y0 + 0.002, 1.80), M["trim"], mirror=True)
    b.box((0.20, 0.04, 0.22), (xl, Y0 - 0.010, 2.02), M["tail"], mirror=True, bevel=0.012)
    b.box((0.20, 0.04, 0.18), (xl, Y0 - 0.010, 1.79), M["indicator"], mirror=True, bevel=0.012)
    b.box((0.20, 0.04, 0.16), (xl, Y0 - 0.010, 1.59), M["reverse"], mirror=True, bevel=0.012)
    b.box((0.30, 0.04, 0.07), (0.80, Y0 - 0.004, 2.235), sred, mirror=True)
    car.tail_pos = (xl, Y0 - 0.05, 2.02)
    b.box((2 * HW, 0.20, 0.06), (0, Y0 - 0.08, ZS + 0.0), st, bevel=0.012)
    b.box((2 * HW - 0.4, 0.14, 0.12), (0, Y0 + 0.0, ZS - 0.09), M["trim"])
    for sx in (-1.0, 1.0):
        b.cyl(0.022, 1.30, (sx * 0.80, Y0 - 0.034, 1.48), chrome, axis='Z', segments=6)
    b.box((0.32, 0.016, 0.12), (0, Y0 - 0.19, ZS - 0.07), M["plate"])
    b.box((0.36, 0.03, 0.16), (0, Y0 - 0.17, ZS - 0.07), M["trim"])


def firetruck_cab(car):
    p, M, b = car.p, car.M, car.body
    red, white, chrome = M["paint"], M["paint2"], M["chrome"]
    st = steel()
    sred, sblue = siren_mats()
    yf = car.y_f
    g = car._gh()
    hw = car.hw
    # grille, upper warning lamps, indicators, windshield post
    b.box((1.06, 0.05, 0.62), (0, yf + 0.012, 1.34), chrome, bevel=0.014)
    b.box((0.94, 0.02, 0.50), (0, yf + 0.04, 1.34), M["under"])
    for i in range(4):
        b.box((0.94, 0.02, 0.03), (0, yf + 0.052, 1.155 + i * 0.123), chrome)
    b.box((0.05, 0.022, 0.50), (0, yf + 0.054, 1.34), chrome)
    hx = car.head_pos[0]
    b.box((0.24, 0.03, 0.08), (hx, yf + 0.006, 1.19), M["indicator"], mirror=True)
    b.box((0.26, 0.04, 0.11), (hx - 0.02, yf + 0.008, 1.56), sred, mirror=True, bevel=0.012)
    ln = sqrt((g["cy"] - g["rf"]) ** 2 + (g["zR"] - g["zc"]) ** 2)
    b.box((0.07, 0.05, ln), (0, (g["cy"] + g["rf"]) / 2.0 + 0.012, (g["zc"] + g["zR"]) / 2.0), red,
          rot=(atan2(g["cy"] - g["rf"], g["zR"] - g["zc"]), 0, 0))
    # chrome bumper with siren and tow eyes
    car.front_bumper(chrome, 0.58, 0.30, out=0.16, wrap=0.30)
    b.cyl(0.10, 0.22, (-0.56, yf + 0.08, 0.985), chrome, axis='Y', segments=8)
    b.cyl(0.10, 0.09, (-0.56, yf + 0.235, 0.985), chrome, axis='Y', segments=8, radius2=0.045)
    b.box((0.16, 0.14, 0.03), (-0.56, yf + 0.08, 0.885), M["trim"])
    b.box((0.05, 0.05, 0.07), (0.50, yf + 0.17, 0.62), M["trim"], mirror=True)
    # roof: light bar, air horns
    car.siren_pos = light_bar(b, M, 3.22, g["rz"] - 0.012, 2.04, depth=0.26, lens_h=0.11, pattern="rbbr")
    for sx in (-1.0, 1.0):
        b.cyl(0.03, 0.46, (sx * 0.86, 2.72, g["rz"] + 0.085), chrome, axis='Y', segments=8, radius2=0.075)
        b.box((0.05, 0.05, 0.06), (sx * 0.86, 2.62, g["rz"] + 0.02), chrome)
    # steps, grab handles, door shields, engine tunnel
    Ra = car.Ra
    for ya, yb in ((p["axle_f"] + Ra + 0.07, 3.74), (1.10, p["axle_f"] - Ra - 0.07)):
        b.box((0.11, yb - ya, 0.045), (hw + 0.035, (ya + yb) / 2.0, 0.70), st, mirror=True)
    for yy in (2.84, 1.045):
        b.cyl(0.02, 0.66, (hw + 0.026, yy, 1.50), chrome, axis='Z', segments=6, mirror=True)
    gold = G.pmat("BadgeGold", rough=0.4, metal=0.5)
    orange, yellow = G.pmat("SafetyOrange", rough=0.5), G.pmat("HazardYellow", rough=0.5)
    for side, sfx in ((-1.0, "L"), (1.0, "R")):
        d = car.mb("Door_F" + sfx)                               # fire crest above the band, HBFD below
        side_crest(d, car, side, 3.34, 1.55, 0.32, gold, white, "fire", orange, yellow)
        side_text(d, car, side, "HBFD", 3.36, 0.925, 0.17, white)
        d = car.mb("Door_R" + sfx)                               # crew door: unit number + ENGINE
        side_text(d, car, side, "2", 1.47, 1.415, 0.27, white, stroke=0.2)
        side_text(d, car, side, "ENGINE", 1.47, 0.95, 0.12, white, stroke=0.2)
    roof_text(b, g["rz"] + 0.004, "2", 0.0, 1.95, 0.62, red, stroke=0.2)
    car.lean_strip(chrome)
    b.box((0.60, 1.50, 0.40), (0, 2.62, p["tub_z"] + 0.20), M["interior"])


def firetruck_lod(car):
    p, M = car.p, car.M
    lb = car.mb("Body_LOD1")
    red, white = M["paint"], M["paint2"]
    sred, sblue = siren_mats()
    HW, Y0, Y1, ZS, Z1, ZT = (FT[k] for k in ("HW", "Y0", "Y1", "ZS", "Z1", "ZT"))
    R = p["wheel_r"]
    arch_block(lb, HW, Y0, Y1, ZS, Z1, [(p["axle_m"], R, R + 0.06), (p["axle_r"], R, R + 0.06)], red, under=M["under"], n=3)
    lb.box((2 * HW, Y1 - Y0, ZT - Z1), (0, (Y0 + Y1) / 2.0, (Z1 + ZT) / 2.0), red)
    lb.box((0.02, Y1 - Y0 - 0.1, 0.12), (HW, (Y0 + Y1) / 2.0, 1.31), white, mirror=True)
    lb.box((0.02, 3.7, 0.78), (HW, -1.95, 1.80), steel(), mirror=True)
    lb.box((0.02, 0.8, 1.2), (HW, 0.46, 1.42), steel(), mirror=True)
    lb.box((1.9, 0.5, 0.5), (0, 0.46, ZT + 0.25), M["trim"])
    lb.box((0.13, 3.5, 0.46), (1.09, -2.0, ZT + 0.30), steel())
    lb.box((1.44, 0.02, 0.77), (0, Y0, 1.795), steel())
    lb.box((0.22, 0.03, 0.6), (1.03, Y0, 1.80), M["tail"], mirror=True)
    lb.box((0.9, 0.24, 0.12), (-0.5, 3.22, p["height"] + 0.10), sred)
    lb.box((0.9, 0.24, 0.12), (0.5, 3.22, p["height"] + 0.10), sblue)
    lb.box((1.06, 0.04, 0.62), (0, car.y_f + 0.02, 1.34), M["chrome"])
    lb.box((2.3, 0.2, 0.3), (0, car.y_f + 0.06, 0.73), M["chrome"])


def build_firetruck():
    car = Truck(FIRETRUCK, G.slot("service", SLOTS["firetruck"]), COLLECTIONS["firetruck"])
    car.skin()
    car.greenhouse()
    car.interior()
    car.front_fascia()
    car.details()
    car.closures()
    firetruck_cab(car)
    firetruck_body(car)
    car.cab_collision(box=(FT["HW"], FT["Y0"], FT["Y1"], FT["ZS"], FT["ZT"], 0.06))
    car.lod()
    firetruck_lod(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# SWAT_VAN  -  armoured tactical truck: short sloped hood under a tall stepped cab, one-piece hull
#              with small ports, raised troop roof with hatch, ram bar, HBPD TACTICAL livery, 6.3 m
# ------------------------------------------------------------------------------------------------
SWAT = dict(K.DEFAULTS)
SWAT.update(
    name="swat_van", livery="UniformNavy",
    width=2.30, height=2.46,
    axle_f=1.85, axle_r=-1.55, wheel_r=0.52, wheel_w=0.34, track=1.92, tyre_lugs=12, wheel_segs=12,
    arch_gap=0.07, arch_lip="trim", arch_segs=6,
    # the belt line stays high (1.84) along cab + troop compartment and steps down to a low hood
    top=[(-2.95, 1.84), (1.04, 1.84), (1.20, 1.58), (2.42, 1.50), (2.85, 1.36)],
    bottom=[(-2.95, 0.80), (-2.55, 0.60), (2.40, 0.60), (2.85, 0.80)],
    plan=[(-2.95, 0.90), (-2.70, 1.0), (2.25, 1.0), (2.60, 0.90), (2.85, 0.76)],
    crown=0.02, crown_w=0.42, shoulder_inset=0.13, crease_drop=0.15, crease_inset=0.0,
    swage_z=1.16, rocker_z=0.76, rocker_inset=0.0, sill_inset=0.06, rocker_mat="trim", side_strip=None,
    tub_z=0.82, seat_z=1.24, seat_x=0.52, seat_f_y=-0.02, seat_r_y=-1.95,
    cowl_y=1.04, roof_f=0.80, roof_r=-2.93, deck_y=-2.94, tumble=0.13, roof_t=0.08, roof_drop=0.03,
    a_pillar=0.18, c_pillar=(0.12, 0.12), b_pillar=None, pillar_w=0.08,
    # blank armour between the door window and the two troop ports
    pillars_extra=[(-1.00, 0.06, -1.00, 0.06), (-2.30, -1.36, -2.30, -1.36), (-2.84, -2.66, -2.84, -2.66)],
    doors=[("F", -0.12, 0.92)], hood=(1.24, 2.42), trunk=None,
    head=dict(w=0.26, h=0.16, inset=0.05, z=None), grille=None,
    tail=None, bumper_f=None, bumper_r=None, exhaust=None, plate_r=False,
    siren=True, exits={"Exit_Passenger_2": (-0.55, -3.95, 0.0), "Exit_Passenger_3": (0.55, -3.95, 0.0)},
)
SWAT_PORTS = ((-1.36, -1.00), (-2.66, -2.30))          # (ya, yb) of the troop-compartment ports
SWAT_PANELS = ((-1.00, 0.06), (-2.30, -1.36), (-2.84, -2.66))


def swat_extras(car):
    p, M, b = car.p, car.M, car.body
    navy = M["paint"]
    st, sd = steel(), steel_dark()
    black = G.pmat("TacticalBlack", rough=0.8)
    white = G.pmat("White", rough=0.5)
    gold = G.pmat("BadgeGold", rough=0.4, metal=0.5)
    sred, sblue = siren_mats()
    g = car._gh()
    yf, yr = car.y_f, car.y_r
    hw = car.hw
    R, Ra = p["wheel_r"], car.Ra
    belt_z, zR = g["zc"], g["zR"]
    lean = atan2(g["xc"] - g["xr"], zR - belt_z)                 # tumble angle of the upper hull

    def gh_x(y, z):
        """x of the upper hull side at height z."""
        bx = car.belt_x(y)
        return bx + (g["xr"] - bx) * (z - car.zt(y)) / (zR - car.zt(y))
    # ---- nose: armoured louvre grille, steel bumper, ram bar
    hx, hy, hz = car.head_pos
    gw = 2.0 * (hx - p["head"]["w"] / 2.0 - 0.05)
    b.box((gw, 0.05, 0.44), (0, yf + 0.0, hz - 0.12), M["under"])
    for i in range(4):
        b.box((gw - 0.02, 0.07, 0.05), (0, yf + 0.03, hz - 0.29 + i * 0.115), navy, rot=(radians(28), 0, 0))
    car.front_bumper(sd, 0.64, 0.28, out=0.14, wrap=0.45, valance=False)
    y0 = yf + 0.20
    ztop = car.zt(yf) + 0.02
    for sx in (-1.0, 1.0):
        b.box((0.09, 0.10, ztop - 0.64), (sx * 0.46, y0, (ztop + 0.64) / 2.0), st, bevel=0.015)
        b.box((0.07, 0.07, 0.40), (sx * 0.80, y0 - 0.08, ztop - 0.24), st, rot=(0, 0, sx * radians(-22)))
        b.box((0.07, 0.16, 0.07), (sx * 0.46, y0 - 0.10, 0.80), st)
    b.box((1.76, 0.08, 0.08), (0, y0 - 0.02, ztop - 0.02), st, bevel=0.015)
    b.box((1.00, 0.07, 0.07), (0, y0, (ztop + 0.92) / 2.0), st)
    b.cyl(0.085, 0.50, (0, yf + 0.05, 1.005), sd, axis='X', segments=8)                             # winch drum
    for sx in (-1.0, 1.0):
        b.box((0.05, 0.17, 0.19), (sx * 0.275, yf + 0.05, 1.005), st)
    b.box((0.06, 0.06, 0.10), (0.30, yf + 0.20, 0.72), M["chrome"], mirror=True)                   # tow eyes
    # ---- windshield centre post + armoured brow, scuttle plate under the glass
    ln = sqrt((g["cy"] - g["rf"]) ** 2 + (zR - belt_z) ** 2)
    b.box((0.09, 0.06, ln), (0, (g["cy"] + g["rf"]) / 2.0 + 0.014, (belt_z + zR) / 2.0), navy,
          rot=(atan2(g["cy"] - g["rf"], zR - belt_z), 0, 0))
    b.box((2.0 * g["xr"] + 0.06, 0.24, 0.05), (0, g["rf"] + 0.11, g["rz"] - 0.035), navy, rot=(radians(-12), 0, 0))
    ya_, yb_s = g["cy"], car.top[2][0]                             # armoured scuttle plate over the cowl step
    za_, zb_s = belt_z, car.zt(yb_s)
    sl = sqrt((yb_s - ya_) ** 2 + (za_ - zb_s) ** 2)
    ny_, nz_ = (za_ - zb_s) / sl, (yb_s - ya_) / sl
    b.box((2.0 * car.belt_x(ya_) - 0.10, 0.03, sl - 0.05), (0, (ya_ + yb_s) / 2.0 + ny_ * 0.006, (za_ + zb_s) / 2.0 + nz_ * 0.006 - 0.012),
          navy, rot=(atan2(yb_s - ya_, za_ - zb_s), 0, 0))
    car.lean_strip(white)
    # ---- hood vents (part of the Hood object)
    hd = car.mb("Hood")
    yv = 1.72
    slope = atan2(car.zt(yv + 0.3) - car.zt(yv - 0.3), 0.6)
    for sx in (-1.0, 1.0):
        hd.box((0.34, 0.56, 0.035), (sx * 0.52, yv, car.zt(yv) + 0.012), black, rot=(slope, 0, 0))
        for i in range(3):
            yy = yv - 0.16 + i * 0.16
            hd.box((0.26, 0.03, 0.02), (sx * 0.52, yy, car.zt(yy) + 0.035), navy)
    # ---- upper hull: port surrounds (steel shutters above / below each port), spot lamps
    for ya, yb in SWAT_PORTS:
        ym = (ya + yb) / 2.0
        for zz, hh in ((belt_z + 0.055, 0.11), (zR - 0.075, 0.13)):
            b.box((0.035, yb - ya + 0.16, hh), (gh_x(ym, zz) + 0.006, ym, zz), sd, mirror=True, rot=(0, -lean, 0))
        zz = (belt_z + zR) / 2.0 - 0.01
        for yy in (ya - 0.045, yb + 0.045):
            b.box((0.03, 0.05, zR - belt_z - 0.20), (gh_x(yy, zz) + 0.004, yy, zz), sd, mirror=True, rot=(0, -lean, 0))
    # ---- livery: HBPD TACTICAL on the flanks, city crest on the front doors
    zt0 = 1.285
    words = (("HBPD", 0.30), ("TACTICAL", 0.15))
    widths = [text_quads(t, h)[1] for t, h in words]
    gap_w = 0.20
    total = sum(widths) + gap_w
    yc_all = -1.52
    for side in (-1.0, 1.0):
        u = -total / 2.0
        for (t, h), wd in zip(words, widths):
            side_text(b, car, side, t, yc_all + side * (u + wd / 2.0), zt0 + (0.30 - h) / 2.0, h, white)
            u += wd + gap_w
    for side, sfx in ((-1.0, "L"), (1.0, "R")):
        d = car.mb("Door_F" + sfx)
        side_crest(d, car, side, 0.42, 1.44, 0.44, gold, navy, "police", G.pmat("Mustard", rough=0.5), white)
    # ---- running boards with brackets
    ya, yb = p["axle_r"] + Ra + 0.10, p["axle_f"] - Ra - 0.10
    b.box((0.26, yb - ya, 0.05), (hw + 0.10, (ya + yb) / 2.0, 0.58), st, mirror=True, bevel=0.012)
    for yy in (ya + 0.20, (ya + yb) / 2.0, yb - 0.20):
        b.box((0.20, 0.05, 0.10), (hw + 0.05, yy, 0.52), M["trim"], mirror=True)
    # ---- roof: light bar on the cab, raised troop roof with hatch, grab rails, spot lamps
    rz = g["rz"]
    car.siren_pos = light_bar(b, M, 0.50, rz - 0.012, 1.50, depth=0.20, lens_h=0.09)
    xr_ = g["xr"] - 0.05
    rh = 0.20                                                   # raised troop-compartment roof
    wr = xr_ - 0.10

    def rring(y, h0, h1):
        return [(-wr, y, rz - 0.03), (wr, y, rz - 0.03), (wr, y, rz + h0), (wr - 0.12, y, rz + h1), (-(wr - 0.12), y, rz + h1),
                (-wr, y, rz + h0)]
    b.loft([rring(-2.88, rh - 0.09, rh), rring(-0.02, rh - 0.09, rh), rring(0.24, -0.02, -0.01)], navy)
    zt_ = rz + rh
    b.cyl(0.40, 0.08, (0, -1.35, zt_ + 0.03), black, axis='Z', segments=8)                          # hatch ring + lid
    b.cyl(0.33, 0.05, (0, -1.35, zt_ + 0.09), navy, axis='Z', segments=8)
    b.box((0.16, 0.05, 0.035), (0, -1.35, zt_ + 0.13), sd)
    b.box((0.30, 0.07, 0.05), (0, -1.72, zt_ + 0.08), sd)
    for sx in (-1.0, 1.0):
        b.cyl(0.02, 2.50, (sx * xr_, -1.55, rz + 0.13), st, axis='Y', segments=6)
        for yy in (-2.70, -1.55, -0.40):
            b.box((0.035, 0.035, 0.14), (sx * xr_, yy, rz + 0.06), st)
    b.box((0.50, 0.40, 0.10), (0.0, -2.42, zt_ + 0.04), black, bevel=0.02)                          # vent box
    for sx in (-1.0, 1.0):                                                                           # spot lamps
        b.box((0.16, 0.14, 0.12), (sx * (wr - 0.20), -0.12, zt_ + 0.06), black, bevel=0.015)
        b.face([(sx * (wr - 0.27), -0.046, zt_ + 0.015), (sx * (wr - 0.13), -0.046, zt_ + 0.015), (sx * (wr - 0.13), -0.046, zt_ + 0.105),
                (sx * (wr - 0.27), -0.046, zt_ + 0.105)], M["head"], want=(0, 1, 0))
    roof_text(b, zt_ + 0.005, "T1", 0.0, -0.60, 0.44, white)
    zg = (belt_z + zR) / 2.0 - 0.03
    for ya in (-0.47, -1.83):                                    # gun ports in the blank upper-hull armour
        for rr_, off, mat in ((0.075, 0.004, sd), (0.045, 0.008, M["under"])):
            ring = []
            for i in range(8):
                yy, zz = ya + rr_ * cos(2 * pi * i / 8), zg + rr_ * sin(2 * pi * i / 8)
                ring.append((gh_x(yy, zz) + off, yy, zz))
            b.face(ring, mat, mirror=True, want=(1, 0, 0.2))
    # ---- rear: bulkhead, armoured doors (Door_RL / Door_RR) with ports, lamps, step bumper
    yb_ = yr - 0.003
    b.face([(-0.84, yb_, 0.84), (0.84, yb_, 0.84), (0.84, yb_, g["zd"]), (-0.84, yb_, g["zd"])], M["interior"], want=(0, -1, 0))
    yu = g["dy"] + 0.016
    b.face([(-(g["xd"] - 0.03), yu, g["zd"] - 0.01), (g["xd"] - 0.03, yu, g["zd"] - 0.01), (g["xr"] - 0.03, yu, g["zR"]),
            (-(g["xr"] - 0.03), yu, g["zR"])], M["interior"], want=(0, -1, 0))
    x0, x1, zd0, zd1 = 0.012, 0.81, 0.84, 2.34
    for side, sfx in ((-1.0, "L"), (1.0, "R")):
        d = car.mb("Door_R" + sfx)
        d.box((x1 - x0, 0.05, zd1 - zd0), (side * (x0 + x1) / 2.0, yr - 0.032, (zd0 + zd1) / 2.0), navy, bevel=0.014)
        d.box((0.40, 0.014, 0.30), (side * 0.41, yr - 0.060, 2.06), black)
        d.box((0.60, 0.02, 0.50), (side * 0.41, yr - 0.062, 1.40), navy, bevel=0.012)
        d.box((0.04, 0.035, 0.26), (side * 0.11, yr - 0.072, 1.44), st, bevel=0.008)
        for zz in (1.04, 1.64, 2.20):
            d.box((0.06, 0.035, 0.10), (side * (x1 - 0.025), yr - 0.064, zz), sd)
        rear_text(d, yr - 0.077, "HBPD" if side < 0 else "T1", side * 0.41, 1.32, 0.16, white)
        gname = "Glass_Rear_" + sfx
        car.mb(gname).face([(side * 0.25, yr - 0.069, 1.95), (side * 0.57, yr - 0.069, 1.95), (side * 0.57, yr - 0.069, 2.17),
                            (side * 0.25, yr - 0.069, 2.17)], M["glass"], want=(0, -1, 0))
        car.nest[gname] = "Door_R" + sfx
        car.origins["Door_R" + sfx] = ((side * x1, yr - 0.032, zd0), None)
    xl = 0.925
    b.box((0.17, 0.03, 0.50), (xl, yr - 0.004, 1.42), M["trim"], mirror=True)
    b.box((0.13, 0.04, 0.17), (xl, yr - 0.016, 1.56), M["tail"], mirror=True, bevel=0.01)
    b.box((0.13, 0.04, 0.12), (xl, yr - 0.016, 1.40), M["indicator"], mirror=True, bevel=0.01)
    b.box((0.13, 0.04, 0.11), (xl, yr - 0.016, 1.27), M["reverse"], mirror=True, bevel=0.01)
    b.box((0.20, 0.04, 0.06), (0.52, yr - 0.004, g["zR"] - 0.02), sred, mirror=True)
    car.tail_pos = (xl, yr - 0.05, 1.56)
    b.box((2.06, 0.26, 0.07), (0, yr - 0.10, 0.74), st, bevel=0.014)
    b.box((1.70, 0.12, 0.16), (0, yr + 0.0, 0.66), M["trim"])
    b.box((0.32, 0.016, 0.12), (0, yr - 0.236, 0.64), M["plate"])
    b.box((0.36, 0.03, 0.16), (0, yr - 0.215, 0.64), M["trim"])
    b.box((0.05, 0.10, 0.08), (0.62, yr - 0.20, 0.64), M["chrome"], mirror=True)
    b.cyl(0.045, 0.40, (-0.70, yr + 0.10, 0.56), M["chrome"], axis='Y', segments=8)
    car.exhaust_pos = (-0.70, yr - 0.12, 0.56)


def swat_collision(car):
    """Col_Body = full-length lower hull up to the hood line, Col_Cabin = the tall cab + troop hull."""
    p, M = car.p, car.M
    g = car._gh()
    zlo = min(z for _, z in car.bottom_keys) + 0.02
    zh = car.zt(car.p["cowl_y"] + 0.16)
    prof = [(car.y_r, zh)] + [(y, z) for y, z in car.top if y > p["cowl_y"] + 0.01]
    low = [(car.y_f, max(K.interp(car.bottom_keys, car.y_f), zlo)), (car.y_f - 0.30, zlo), (car.y_r + 0.30, zlo),
           (car.y_r, max(K.interp(car.bottom_keys, car.y_r), zlo))]
    poly = prof + low
    wmax = car.hw * 0.985
    car.mb("Col_Body").loft([[(-wmax, y, z) for y, z in poly], [(wmax, y, z) for y, z in poly]], M["col"])
    zc = g["zc"] - p["crease_drop"]
    yb0, yb1 = g["dy"], g["cy"]

    def ring(x, ya, yb, z):
        return [(-x, ya, z), (x, ya, z), (x, yb, z), (-x, yb, z)]
    car.mb("Col_Cabin").loft([ring(wmax, yb0, yb1 + 0.10, zh - 0.02), ring(wmax, yb0, yb1 + 0.04, zc),
                              ring(g["xr"], g["rr"], g["rf"], g["rz"] + 0.18)], M["col"])


def swat_lod(car):
    p, M = car.p, car.M
    lb = car.mb("Body_LOD1")
    sred, sblue = siren_mats()
    white = G.pmat("White", rough=0.5)
    g = car._gh()
    yf, yr = car.y_f, car.y_r
    zn = car.zt(yf)
    lb.box((1.0, 0.08, zn - 0.62), (0, yf + 0.20, (zn + 0.66) / 2.0), steel())
    lb.box((2.1, 0.14, 0.28), (0, yf + 0.07, 0.78), steel_dark())
    lb.box((0.26, 2.1, 0.06), (car.hw + 0.10, 0.15, 0.58), steel(), mirror=True)
    lb.box((0.6, 0.2, 0.10), (-0.36, 0.50, g["rz"] + 0.09), sred)
    lb.box((0.6, 0.2, 0.10), (0.36, 0.50, g["rz"] + 0.09), sblue)
    lb.box((2.0 * g["xr"] - 0.3, 2.9, 0.18), (0, -1.45, g["rz"] + 0.09), M["paint"])
    lb.box((0.14, 0.03, 0.45), (0.925, yr, 1.42), M["tail"], mirror=True)
    lb.box((0.012, 1.03, 0.30), (car.hw + 0.004, -2.14, 1.435), white)                             # HBPD blocks
    lb.box((0.012, 1.03, 0.30), (-(car.hw + 0.004), -0.90, 1.435), white)
    for ya, yb in SWAT_PANELS:                                 # blank armour panels over the long side glass
        lb.face([(car.belt_x(ya) + 0.004, ya, g["zd"]), (car.belt_x(yb) + 0.004, yb, g["zd"]), (g["xr"] + 0.004, yb, g["rz"]),
                 (g["xr"] + 0.004, ya, g["rz"])], M["paint"], mirror=True, want=(1, 0, 0.2))
    lb.face([(-g["xd"], g["dy"] - 0.004, g["zd"]), (g["xd"], g["dy"] - 0.004, g["zd"]), (g["xr"], g["rr"] - 0.004, g["rz"]),
             (-g["xr"], g["rr"] - 0.004, g["rz"])], M["paint"], want=(0, -1, 0))


def build_swat_van():
    car = Truck(SWAT, G.slot("service", SLOTS["swat_van"]), COLLECTIONS["swat_van"])
    car.skin()
    car.greenhouse()
    car.parts.pop("Glass_Rear", None)          # replaced by the two door ports
    car.interior()
    car.bays()
    car.front_fascia()
    car.details()
    car.closures()
    swat_extras(car)
    swat_collision(car)
    car.lod()
    swat_lod(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# BOX_TRUCK  -  low-cab-forward delivery truck with a tall cargo box, 7.05 m
# ------------------------------------------------------------------------------------------------
BOX_TRUCK = dict(K.DEFAULTS)
BOX_TRUCK.update(
    name="box_truck", cab_only=True,
    width=2.10, height=2.36,
    axle_f=2.52, axle_r=-1.70, wheel_r=0.44, wheel_w=0.26, track=1.78, track_r=1.78, dual_rear=True, wheel_segs=14,
    arch_gap=0.06, arch_lip="trim", arch_segs=6,
    top=[(1.82, 1.50), (3.30, 1.50), (3.42, 1.42)],
    bottom=[(1.82, 0.62), (3.42, 0.62)],
    plan=[(1.82, 1.0), (3.22, 1.0), (3.42, 0.92)],
    crown=0.0, shoulder_inset=0.06, crease_drop=0.08, crease_inset=0.0, swage_z=1.12, rocker_z=0.80,
    rocker_inset=0.0, sill_inset=0.03, rocker_mat="trim", side_strip=None,
    tub_z=0.92, seat_z=1.26, seat_x=0.55, seat_f_y=2.26, seat_r_y=None,
    cowl_y=3.30, roof_f=3.06, roof_r=1.92, deck_y=1.87, tumble=0.07, roof_t=0.06,
    a_pillar=0.12, c_pillar=(0.12, 0.12), b_pillar=None,
    doors=[("F", 2.16, 3.20)], hood=None, trunk=None,
    head=dict(w=0.30, h=0.16, inset=0.05, z=0.99), grille=dict(bars=2),
    tail=None, bumper_f=None, bumper_r=None, exhaust=None, plate_r=False,
    engine_pos=(0.0, 3.30, 1.10),
)
BX = dict(HW=1.20, Y0=-3.46, Y1=1.58, ZF=1.05, ZT=3.20)


def box_truck_body(car):
    p, M, b = car.p, car.M, car.body
    paint, paint2 = M["paint"], M["paint2"]
    st, sd = steel(), steel_dark()
    HW, Y0, Y1, ZF, ZT = (BX[k] for k in ("HW", "Y0", "Y1", "ZF", "ZT"))
    R = p["wheel_r"]
    yr = p["axle_r"]
    yf = car.y_f
    g = car._gh()
    # ---- cab dressing: bumper, badge panel, roof marker lamps, step
    car.front_bumper(M["trim"], 0.56, 0.26, out=0.07, wrap=0.30)
    car.lean_strip(M["trim"])
    b.box((1.20, 0.03, 0.10), (0, yf + 0.004, 1.24), M["trim"])
    b.box((0.26, 0.03, 0.06), (0, yf + 0.016, 1.24), M["chrome"], bevel=0.008)
    for xx in (-0.60, -0.30, 0.0, 0.30, 0.60):
        b.box((0.09, 0.05, 0.035), (xx, g["rf"] - 0.06, g["rz"] + 0.012), M["indicator"])
    ya = p["axle_f"] + car.Ra + 0.07
    b.box((0.10, 3.20 - ya, 0.04), (car.hw + 0.03, (ya + 3.20) / 2.0, 0.68), st, mirror=True)
    # ---- chassis: rails, cross members, tank, battery box, exhaust stack, rear axle, mudguards
    b.box((0.10, 5.20, 0.20), (0.43, -0.82, 0.78), M["under"], mirror=True)
    b.box((0.12, 5.00, 0.17), (0.43, -0.92, 0.965), sd, mirror=True)
    for yy in (1.30, 0.20, -0.80, -2.60, -3.30):
        b.box((0.80, 0.08, 0.14), (0, yy, 0.78), M["under"])
    b.cyl(0.23, 0.90, (-0.84, 0.72, 0.66), st, axis='Y', segments=10)
    for yy in (0.46, 0.98):
        b.box((0.50, 0.05, 0.03), (-0.84, yy, 0.90), M["trim"])
        b.box((0.03, 0.05, 0.30), (-0.62, yy, 0.76), M["trim"])
    b.cyl(0.05, 0.05, (-1.07, 0.52, 0.80), M["chrome"], axis='X', segments=6)
    b.box((0.40, 0.74, 0.42), (0.86, 0.74, 0.66), sd, bevel=0.02)
    b.box((0.02, 0.60, 0.05), (1.065, 0.74, 0.74), M["chrome"])
    b.cyl(0.05, 1.86, (-0.84, 1.70, 1.74), M["chrome"], axis='Z', segments=8)
    b.cyl(0.075, 0.90, (-0.84, 1.70, 1.50), sd, axis='Z', segments=8)
    b.box((0.30, 0.04, 0.04), (-0.70, 1.70, 2.20), M["trim"])
    car.exhaust_pos = (-0.84, 1.70, 2.70)
    b.cyl(0.07, 1.6, (0, yr, R), M["under"], axis='X', segments=6)
    b.cyl(0.18, 0.34, (0, yr, R), M["under"], axis='Y', segments=8)
    Rf = R + 0.085
    xc = p["track_r"] / 2.0
    secs = []
    for i in range(7):
        a = radians(15 + 150 * i / 6)
        cy_, cz_ = yr + Rf * cos(a), R + Rf * sin(a)
        ny, nz = cos(a), sin(a)
        secs.append([(xc - 0.31, cy_, cz_), (xc + 0.31, cy_, cz_), (xc + 0.31, cy_ + ny * 0.03, cz_ + nz * 0.03),
                     (xc - 0.31, cy_ + ny * 0.03, cz_ + nz * 0.03)])
    b.loft(secs, M["trim"], mirror=True)
    b.box((0.58, 0.02, 0.40), (xc, yr - Rf - 0.04, 0.40), M["trim"], mirror=True)                 # mud flaps
    for zz in (0.50, 0.72):                                                                         # side under-run guards
        b.box((0.04, 1.25, 0.07), (HW - 0.05, -0.50, zz), st, mirror=True)
    for yy in (-0.95, -0.05):
        b.box((0.04, 0.05, 0.50), (HW - 0.09, yy, 0.74), sd, mirror=True)
    # ---- cargo box: shell, rails, corner posts, livery band + roundel
    box_shell(b, HW, Y0, Y1, ZF, ZT, paint2, ch=0.05, end_ch=0.03, bottom=M["under"])
    L = Y1 - Y0
    ymid = (Y0 + Y1) / 2.0
    b.box((0.03, L + 0.02, 0.11), (HW + 0.002, ymid, ZF + 0.055), st, mirror=True)
    b.box((0.03, L + 0.02, 0.07), (HW - 0.008, ymid, ZT - 0.095), st, mirror=True)
    for yy in (Y0 + 0.04, Y1 - 0.04):
        b.box((0.03, 0.10, ZT - ZF - 0.16), (HW + 0.002, yy, (ZF + ZT) / 2.0 - 0.01), st, mirror=True)
    for yy in (Y0 + 1.28, Y0 + 2.52, Y0 + 3.76):
        b.box((0.012, 0.03, ZT - ZF - 0.28), (HW + 0.002, yy, (ZF + ZT) / 2.0 - 0.01), st, mirror=True)
    zm = 2.10                                                   # livery: band running into three forward chevrons
    yb1 = -0.62
    b.box((0.012, yb1 - (Y0 + 0.20), 0.30), (HW + 0.004, (yb1 + Y0 + 0.20) / 2.0, zm), paint, mirror=True)
    b.box((0.012, yb1 - (Y0 + 0.20), 0.05), (HW + 0.004, (yb1 + Y0 + 0.20) / 2.0, zm - 0.26), paint, mirror=True)
    xs = HW + 0.006
    for i in range(3):
        y0_ = -0.50 + i * 0.52
        t_, d_, h_ = 0.26, 0.40, 0.60
        for sg in (1.0, -1.0):
            b.face([(xs, y0_, zm + sg * h_), (xs, y0_ + t_, zm + sg * h_), (xs, y0_ + t_ + d_, zm), (xs, y0_ + d_, zm)],
                   paint, mirror=True, want=(1, 0, 0))
    ybc = (yb1 + Y0 + 0.20) / 2.0                               # company lettering (original name) around the band
    for sx in (-1.0, 1.0):
        flank_text(b, sx, HW + 0.011, "TIDEHAUL", ybc, 2.42, 0.30, paint, stroke=0.2)
        flank_text(b, sx, HW + 0.011, "CARGO", ybc, 1.50, 0.17, paint, stroke=0.2)
    for i in range(6):                                          # roof bows
        b.box((2.0 * HW - 0.16, 0.05, 0.025), (0, Y0 + 0.42 + i * (L - 0.84) / 5.0, ZT + 0.008), st)
    for yy, mat in ((Y1 - 0.20, M["indicator"]), (ymid, M["indicator"]), (Y0 + 0.20, M["tail"])):   # side markers
        b.box((0.02, 0.10, 0.045), (HW + 0.016, yy, ZF + 0.055), mat, mirror=True)
        b.box((0.02, 0.10, 0.04), (HW + 0.004, yy, ZT - 0.095), mat, mirror=True)
    for xx in (-0.95, -0.12, 0.0, 0.12, 0.95):                                                      # front top clearance lamps
        b.box((0.09, 0.03, 0.04), (xx, Y1 + 0.004, ZT - 0.10), M["indicator"])
    # ---- rear: frame, roll-up door (Trunk), header lamps, lamp bar, under-run bumper
    zd0, zd1 = ZF + 0.12, ZT - 0.24
    xd = HW - 0.13
    b.face([(-xd, Y0 - 0.002, zd0), (xd, Y0 - 0.002, zd0), (xd, Y0 - 0.002, zd1), (-xd, Y0 - 0.002, zd1)], M["interior"], want=(0, -1, 0))
    for sx in (-1.0, 1.0):
        b.box((0.13, 0.05, ZT - ZF - 0.06), (sx * (HW - 0.065), Y0 - 0.02, (ZF + ZT) / 2.0 - 0.01), st)
    b.box((2 * HW - 0.26, 0.05, 0.20), (0, Y0 - 0.02, ZT - 0.13), st)
    b.box((2 * HW, 0.07, 0.12), (0, Y0 - 0.025, ZF + 0.06), sd)
    tr = car.mb("Trunk")
    n = 7
    hz_ = (zd1 - zd0) / n
    prof = [(Y0 + 0.01, zd0)]
    for i in range(n):
        za_ = zd0 + i * hz_
        prof += [(Y0 - 0.014, za_ + 0.012), (Y0 - 0.034, za_ + 0.05), (Y0 - 0.034, za_ + hz_ - 0.012)]
    prof += [(Y0 - 0.014, zd1), (Y0 + 0.01, zd1)]
    tr.prism(prof, -xd + 0.008, xd - 0.008, st, axis='X')
    tr.box((0.30, 0.03, 0.05), (0, Y0 - 0.05, zd0 + 0.10), M["trim"])
    tr.box((0.10, 0.04, 0.10), (0.42, Y0 - 0.05, zd0 + 0.12), M["chrome"], bevel=0.01)
    tr.box((0.04, 0.012, 0.30), (0, Y0 - 0.06, zd0 + 0.27), M["trim"])
    car.origins["Trunk"] = ((0.0, Y0 - 0.014, zd1), None)
    for xx in (-0.16, 0.0, 0.16):
        b.box((0.09, 0.03, 0.04), (xx, Y0 - 0.046, ZT - 0.10), M["tail"])
    b.box((0.09, 0.03, 0.04), (HW - 0.065, Y0 - 0.046, ZT - 0.10), M["tail"], mirror=True)
    xl = 0.88
    b.box((0.56, 0.04, 0.17), (xl, Y0 - 0.01, 0.905), M["trim"], mirror=True)
    b.box((0.20, 0.04, 0.11), (xl + 0.15, Y0 - 0.024, 0.905), M["tail"], mirror=True, bevel=0.01)
    b.box((0.12, 0.04, 0.11), (xl - 0.02, Y0 - 0.024, 0.905), M["indicator"], mirror=True, bevel=0.01)
    b.box((0.10, 0.04, 0.11), (xl - 0.15, Y0 - 0.024, 0.905), M["reverse"], mirror=True, bevel=0.01)
    car.tail_pos = (xl + 0.15, Y0 - 0.06, 0.905)
    b.box((2.20, 0.10, 0.12), (0, Y0 - 0.05, 0.58), sd, bevel=0.015)
    b.box((0.08, 0.10, 0.34), (0.43, Y0 + 0.02, 0.74), sd, mirror=True)
    b.box((0.32, 0.016, 0.12), (0, Y0 - 0.108, 0.58), M["plate"])
    b.box((0.70, 0.22, 0.04), (0, Y0 - 0.10, 0.78), st)                                              # step plate


def box_truck_lod(car):
    p, M = car.p, car.M
    lb = car.mb("Body_LOD1")
    HW, Y0, Y1, ZF, ZT = (BX[k] for k in ("HW", "Y0", "Y1", "ZF", "ZT"))
    lb.box((2 * HW, Y1 - Y0, ZT - ZF), (0, (Y0 + Y1) / 2.0, (ZF + ZT) / 2.0), M["paint2"])
    lb.box((1.0, 5.2, 0.38), (0, -0.85, 0.86), M["under"])
    lb.box((0.02, Y1 - Y0 - 0.34, 0.36), (HW, (Y0 + Y1) / 2.0, 1.80), M["paint"], mirror=True)
    lb.box((2 * HW - 0.26, 0.03, ZT - ZF - 0.36), (0, Y0, (ZF + ZT) / 2.0 - 0.06), steel())
    lb.box((0.5, 0.03, 0.15), (0.88, Y0, 0.905), M["tail"], mirror=True)
    lb.box((2.2, 0.1, 0.12), (0, Y0 - 0.05, 0.58), steel_dark())
    lb.box((0.45, 0.9, 0.45), (-0.84, 0.72, 0.66), steel())
    lb.box((2.0, 0.1, 0.26), (0, car.y_f + 0.03, 0.69), M["trim"])


def build_box_truck():
    car = Truck(BOX_TRUCK, G.slot("service", SLOTS["box_truck"]), COLLECTIONS["box_truck"])
    car.skin()
    car.greenhouse()
    car.interior()
    car.front_fascia()
    car.details()
    car.closures()
    box_truck_body(car)
    car.cab_collision(box=(BX["HW"], BX["Y0"], BX["Y1"], 0.62, BX["ZT"], 0.05))
    car.lod()
    box_truck_lod(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# build / QA / export entry points
# ------------------------------------------------------------------------------------------------
BUILDERS = {"ambulance": build_ambulance, "firetruck": build_firetruck, "swat_van": build_swat_van,
            "box_truck": build_box_truck}

REQUIRED = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel", "Door_FL", "Door_FR",
            "Glass_Windshield", "Glass_L", "Glass_R", "Seat_Driver", "Seat_Passenger_1", "Exit_Driver",
            "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L", "Light_Tail_R", "Exhaust", "Engine",
            "Col_Body", "Col_Cabin", "Body_LOD1"]
EXTRA_REQUIRED = {
    "ambulance": ["Siren", "Door_RL", "Door_RR", "Glass_Rear_L", "Glass_Rear_R", "Hood", "Col_Box"],
    "firetruck": ["Siren", "Door_RL", "Door_RR", "Wheel_ML", "Wheel_MR", "Glass_Rear", "Col_Box"],
    "swat_van": ["Siren", "Door_RL", "Door_RR", "Hood", "Seat_Passenger_2", "Seat_Passenger_3"],
    "box_truck": ["Glass_Rear", "Trunk", "Col_Box"],
}


def check(name):
    """Contract check (recursive: nested panes count)."""
    root = bpy.data.objects.get(name)
    have = {K.short_name(o) for o in root.children_recursive}
    need = REQUIRED + EXTRA_REQUIRED.get(name, [])
    missing = [n for n in need if n not in have]
    bad = sorted(o.name for o in root.children_recursive if not o.name.startswith(name + K.NAME_SEP))
    mats = sorted({m.name for o in root.children_recursive if o.type == 'MESH' for m in o.data.materials if m})
    print("CONTRACT %s: %d nodes, missing=%s, badly_named=%s" % (name, len(have), missing, bad))
    print("MATERIALS %s: %s" % (name, mats))
    return missing, bad


def build(name, preview=True, views=VIEWS, res=420):
    car = BUILDERS[name]()
    car.report()
    check(name)
    if preview:
        G.preview(name, "veh_" + name, views=views, res=res)
    return car


def export(name, max_tris=11000):
    res = G.validate(name, max_tris=max_tris)
    K.export_glb(name, "vehicles/%s.glb" % name)
    return res


def build_all(preview=True):
    return [build(n, preview) for n in BUILDERS]


def export_all():
    return {n: export(n) for n in BUILDERS}


def group_preview(names=None, out="veh_service_group", spacing=4.4):
    """All vehicles side by side for a relative-scale check.  The roots are moved into one tight
    row inside the (empty) service slots 5..6 for the render and put back afterwards."""
    names = names or [n for n in SLOTS if bpy.data.objects.get(n)]
    roots = [bpy.data.objects[n] for n in names]
    saved = [r.location.copy() for r in roots]
    base = G.slot("service", 5)
    try:
        for i, r in enumerate(roots):
            r.location = base + Vector((i * spacing, 0.0, 0.0))
        bpy.context.view_layer.update()
        return G.preview(names, out, views=("three_quarter", "front", "top", "rear_quarter"), res=760, margin=1.04)
    finally:
        for r, loc in zip(roots, saved):
            r.location = loc
        bpy.context.view_layer.update()
