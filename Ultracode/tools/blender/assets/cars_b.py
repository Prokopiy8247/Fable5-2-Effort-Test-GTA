"""cars_b - SUV, double-cab pickup, panel van, police cruiser and taxi (vehicle artist cars_b).

Built on car_kit (never edits it).  Run inside an execute_blender_code call after the gta_bl header,
with tools/blender/assets on sys.path:

    import car_kit as K, cars_b as B
    importlib.reload(K); importlib.reload(B)
    B.build("suv")                 # or pickup / van / police_cruiser / taxi ; rebuilds an old one
    B.shots("suv")                 # qa/blender_previews/veh_suv.png (six views)
    B.check("suv")                 # contract nodes present?
    B.export("suv")                # validate + vehicles/suv.glb (clean names, livery paint alias)
    B.build_all(); B.export_all(); B.group_preview(); G.save()

Slots: region 'cars' 10..14.  Collections: Vehicles/Cars (suv, pickup, van), Vehicles/Service
(police_cruiser, taxi).

What this module adds on top of the kit (see docs/VEHICLE_KIT.md for the kit itself):
  * each vehicle has its own explicit build sequence (the kit steps + own geometry in between);
  * `remove_end_cap` / `end_cap_part`: replace the kit's flat tail cap by partial caps so that a
    pickup Tailgate / van rear doors can be real separate objects with a hole behind them;
  * side decals that follow the body side (`side_band`, `checker_band`, `side_text`, `shield`):
    liveries are GEOMETRY (flat quads 5-11 mm off the panel), never textures;
  * a small stroke font (HBPD / TAXI) for lettering;
  * `bull_bar` (police push bumper, SUV / pickup Mod_BumperF_A), roof rails, light bar, spot light,
    taxi roof sign, bed tub, sport bar ...
  * fixed liveries: the taxi and the cruiser are painted with the shared palette materials
    P_TaxiYellow / P_PoliceBlue in Blender (so the .blend looks right and no per-asset duplicate
    material is needed) and `export()` renames that material to the contract name M_Paint_Primary
    inside the GLB.  The game reads the authored colour of M_Paint_Primary for `fixed_livery`
    vehicles, so the taxi arrives yellow and the cruiser blue, and both stay re-paintable.
"""
import json
import math
import os
import struct
from math import radians, pi, sin, cos, atan2, hypot

import bpy
import bmesh

import gta_bl as G
import car_kit as K

SLOTS = {"suv": 10, "pickup": 11, "van": 12, "police_cruiser": 13, "taxi": 14}
COLLECTION = {"suv": "Vehicles/Cars", "pickup": "Vehicles/Cars", "van": "Vehicles/Cars",
              "police_cruiser": "Vehicles/Service", "taxi": "Vehicles/Service"}
VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top", "back")

# Blender material -> GLB material name (fixed liveries, see module docstring)
MATERIAL_ALIAS = {
    "taxi": {"P_TaxiYellow": "M_Paint_Primary"},
    "police_cruiser": {"P_PoliceBlue": "M_Paint_Primary"},
}
PAINT_PBR = {"M_Paint_Primary": dict(roughnessFactor=0.35, metallicFactor=0.15)}

# wheel styles of this module (registered in the kit's table at run time, the kit file is untouched)
K.WHEEL_STYLES["b_suv"] = dict(rim=0.60, dish=0.050, lip=0.024, shoulder=0.040, bulge=0.0,
                                spokes=(5, 0.085, 0.026), hub=0.066)
# b_steel / b_cap: the kit builds only tyre + plain steel disc (14 segments like every other car); the
# hub cap and the slots are added by wheels() below - flat slot quads instead of the kit's 12-tri
# boxes, which pays for the two extra segments (396 tris per wheel instead of 432 at 12 segments).
K.WHEEL_STYLES["b_steel"] = dict(rim=0.60, dish=0.032, lip=0.016, shoulder=0.036, bulge=0.0, solid=True, hub=0.0)
K.WHEEL_STYLES["b_cap"] = dict(rim=0.60, dish=0.024, lip=0.016, shoulder=0.034, bulge=0.0, solid=True, hub=0.0)
WHEEL_TRIM = {"b_steel": dict(cap=0.075, slots=5), "b_cap": dict(cap=0.12, slots=5)}
K.WHEEL_STYLES["b_allterrain"] = dict(rim=0.55, dish=0.045, lip=0.030, shoulder=0.044, bulge=0.0,
                                       spokes=(5, 0.072, 0.028), hub=0.066, lugs=0.016, bars=7)


def _p(**kw):
    d = dict(K.DEFAULTS)
    d.update(kw)
    return d


def new_car(params):
    name = params["name"]
    return K.Car(params, G.slot("cars", SLOTS[name]), COLLECTION[name])


def wheels(car):
    """car.wheels() + domed hub cap and dark slots for this module's steel wheel styles (WHEEL_TRIM).
    Both faces of the wheel get them, so one mesh still serves the left and the right side."""
    car.wheels()
    style = car.p["wheel_style"]
    trim = WHEEL_TRIM.get(style)
    if not trim:
        return
    st = K.WHEEL_STYLES[style]
    mb, M = car.mb("Wheel"), car.M
    hw = car.p["wheel_w"] / 2.0
    rr = car.p["wheel_r"] * st["rim"]
    dish = min(st["dish"], hw - 0.01)
    c = trim["cap"]
    ns = trim["slots"]
    r0 = c + 0.014
    r1 = max(rr - 0.040, r0 + 0.030)
    for sgn in (1.0, -1.0):
        x0 = sgn * (hw - dish)
        prof = [(0.0, 0.0), (0.0, c), (0.020, c * 0.92), (0.036, c * 0.5), (0.040, 0.0)]
        mb.revolve([(x0 + sgn * t - sgn * 0.004, r) for t, r in prof], M["rim"], axis='X', segs=8)
        xs = x0 + sgn * 0.005
        for i in range(ns):
            a = 2.0 * pi * (i + 0.5) / ns
            rad = (0.0, -sin(a), cos(a))
            tan = (0.0, cos(a), sin(a))
            pts = []
            for r, hwid in ((r0, -0.011), (r0, 0.011), (r1, 0.021), (r1, -0.021)):
                pts.append((xs, rad[1] * r + tan[1] * hwid, rad[2] * r + tan[2] * hwid))
            mb.face(pts, M["tire"], want=(sgn, 0, 0))


# ------------------------------------------------------------------------------------------------
# generic helpers
# ------------------------------------------------------------------------------------------------
def fascias(car, front_mat=None, rear_mat=None):
    """Kit fascias with another bumper material (the kit paints bumpers body colour; the only
    paint-coloured thing in front_fascia / rear_fascia is the bumper sweep)."""
    keep = car.M["paint"]
    try:
        car.M["paint"] = front_mat or keep
        car.front_fascia()
        car.M["paint"] = rear_mat or keep
        car.rear_fascia()
    finally:
        car.M["paint"] = keep


def new_faces(mb, before):
    return [f for f in mb.bm.faces if f not in before]


def recolor(mb, src, dst, faces=None):
    """Move faces from material `src` to `dst` in a mesh builder."""
    if src not in mb.mats:
        return 0
    i0, i1 = mb.mats.index(src), mb.mi(dst)
    n = 0
    for f in (faces if faces is not None else mb.bm.faces):
        if f.is_valid and f.material_index == i0:
            f.material_index = i1
            n += 1
    return n


def remove_end_cap(car, rear=True):
    """Delete the flat end cap that K.Car.skin() put on the tail (or nose). Call right after skin()."""
    bm = car.body.bm
    ye = car.y_r if rear else car.y_f
    dead = [f for f in bm.faces if all(abs(v.co.y - ye) < 1e-4 for v in f.verts)]
    if dead:
        bmesh.ops.delete(bm, geom=dead, context='FACES_ONLY')
    return len(dead)


def remove_faces_at_y(mb, y, tol=1e-4):
    dead = [f for f in mb.bm.faces if all(abs(v.co.y - y) < tol for v in f.verts)]
    if dead:
        bmesh.ops.delete(mb.bm, geom=dead, context='FACES_ONLY')
    return len(dead)


def _clip(poly, axis, value, keep_ge):
    """Sutherland-Hodgman clip of a 2D polygon against  coord[axis] >= value  (or <=)."""
    def inside(q):
        return q[axis] >= value - 1e-9 if keep_ge else q[axis] <= value + 1e-9
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ia, ib = inside(a), inside(b)
        if ia:
            out.append(a)
        if ia != ib and abs(b[axis] - a[axis]) > 1e-12:
            t = (value - a[axis]) / (b[axis] - a[axis])
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    res = []
    for q in out:
        if not res or abs(q[0] - res[-1][0]) > 1e-6 or abs(q[1] - res[-1][1]) > 1e-6:
            res.append(q)
    if len(res) > 1 and abs(res[0][0] - res[-1][0]) < 1e-6 and abs(res[0][1] - res[-1][1]) < 1e-6:
        res.pop()
    return res


def end_cap_part(car, clips, mat, rear=True):
    """Re-create a part of the removed end cap.  clips = [(axis, value, keep_ge)] with axis 0 = x,
    1 = z, applied to the +X half of the end section; the result is mirrored."""
    ye = car.y_r if rear else car.y_f
    poly = [(q[0], q[2]) for q in car.section(ye)]
    for axis, value, ge in clips:
        poly = _clip(poly, axis, value, ge)
    if len(poly) >= 3:
        car.body.face([(x, ye, z) for x, z in poly], mat, mirror=True, want=(0, -1 if rear else 1, 0))
    return poly


def _zf(z, y):
    return z(y) if callable(z) else z


def side_quad(mb, car, side, y0, y1, z0, z1, mat, off=0.005):
    """Flat decal quad on the body side (follows the side surface at its four corners).
    z0 / z1 may be numbers or functions of y."""
    pts = []
    for y, zz in ((y0, z0), (y1, z0), (y1, z1), (y0, z1)):
        z = _zf(zz, y)
        pts.append((side * (car.side_x(y, z) + off), y, z))
    return mb.face(pts, mat, want=(side, 0, 0))


def side_pieces(car, side, y0, y1):
    """Split the range y0..y1 by panel: [(mesh builder, ya, yb)] - doors get their own decals so the
    livery moves with them."""
    sfx = "L" if side < 0 else "R"
    g2 = car.p["seam"] / 2.0 + 0.006
    out = []
    y = y0
    for tag, a, b in sorted(car.doors, key=lambda d: d[1]):
        if b <= y0 or a >= y1:
            continue
        if a - 0.006 > y:
            out.append((car.body, y, a - 0.006))
        da, db = max(y0, a + g2), min(y1, b - g2)
        if db > da:
            out.append((car.mb("Door_%s%s" % (tag, sfx)), da, db))
        y = max(y, b + 0.006)
    if y1 > y:
        out.append((car.body, y, y1))
    return [(m, a, b) for m, a, b in out if b - a > 0.004]


def side_band(car, side, y0, y1, z0, z1, mat, off=0.005):
    """Stripe along the body side between y0..y1 (split per panel and per station)."""
    for mb, a, b in side_pieces(car, side, y0, y1):
        ys = [a] + [s for s in car.ys if a + 0.01 < s < b - 0.01] + [b]
        for ya, yb in zip(ys[:-1], ys[1:]):
            side_quad(mb, car, side, ya, yb, z0, z1, mat, off)


def checker_band(car, y0, y1, ztop, sq_y=0.07, sq_z=0.06, rows=2, light=None, dark=None):
    """Two-row checker band as geometry.  ztop = upper edge (number or function of y)."""
    light = light or G.pmat("White")
    dark = dark or G.pmat("Black")
    n = int(round((y1 - y0) / sq_y))
    sq_y = (y1 - y0) / n
    for side in (-1.0, 1.0):
        side_band(car, side, y0, y1, lambda y: _zf(ztop, y) - rows * sq_z, ztop, light, off=0.004)
        for i in range(n):
            for r in range(rows):
                if (i + r) % 2:
                    continue
                ya, yb = y0 + i * sq_y, y0 + (i + 1) * sq_y
                for mb, a, b in side_pieces(car, side, ya, yb):
                    side_quad(mb, car, side, a, b, lambda y, r=r: _zf(ztop, y) - (r + 1) * sq_z,
                              lambda y, r=r: _zf(ztop, y) - r * sq_z, dark, off=0.0075)


# ---- stroke font ------------------------------------------------------------------------------
FONT = {
    "H": (0.60, [[(0, 0), (0, 1)], [(0.6, 0), (0.6, 1)], [(0, 0.5), (0.6, 0.5)]]),
    "B": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.40, 1), (0.6, 0.86), (0.6, 0.64), (0.40, 0.5), (0, 0.5)],
                 [(0.40, 0.5), (0.6, 0.36), (0.6, 0.14), (0.40, 0), (0, 0)]]),
    "P": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.40, 1), (0.6, 0.86), (0.6, 0.62), (0.40, 0.48), (0, 0.48)]]),
    "D": (0.60, [[(0, 0), (0, 1)], [(0, 1), (0.36, 1), (0.6, 0.78), (0.6, 0.22), (0.36, 0), (0, 0)]]),
    "T": (0.60, [[(0, 1), (0.6, 1)], [(0.3, 0), (0.3, 1)]]),
    "A": (0.64, [[(0, 0), (0.32, 1), (0.64, 0)], [(0.12, 0.36), (0.52, 0.36)]]),
    "X": (0.60, [[(0, 0), (0.6, 1)], [(0, 1), (0.6, 0)]]),
    "I": (0.0, [[(0, 0), (0, 1)]]),
    "O": (0.60, [[(0.14, 0), (0, 0.16), (0, 0.84), (0.14, 1), (0.46, 1), (0.6, 0.84), (0.6, 0.16), (0.46, 0), (0.14, 0)]]),
    "L": (0.50, [[(0, 1), (0, 0), (0.50, 0)]]),
    "C": (0.56, [[(0.56, 0.84), (0.42, 1), (0.14, 1), (0, 0.84), (0, 0.16), (0.14, 0), (0.42, 0), (0.56, 0.16)]]),
    "E": (0.52, [[(0.52, 1), (0, 1), (0, 0), (0.52, 0)], [(0, 0.5), (0.40, 0.5)]]),
    "0": (0.55, [[(0, 0), (0, 1), (0.55, 1), (0.55, 0), (0, 0)]]),
    "1": (0.24, [[(0, 0.76), (0.24, 1), (0.24, 0)]]),
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
            quads.extend(_stroke([(u0 + a[0] * height, a[1] * height) for a in line], h))
        u0 += (w + gap) * height
    return quads, u0 - gap * height


def _stroke(pts, h):
    """Polyline -> one quad per segment, half width h, mitred joints (limit 2 h), square caps at open
    ends, closed outlines (first point == last point) mitred all round.  The first version drew every
    segment as its own capped rectangle, which left barbs at every bend of O, C, B, D and P."""
    closed = len(pts) > 2 and hypot(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1]) < 1e-9
    if closed:
        pts = pts[:-1]
    n = len(pts)
    segs = n if closed else n - 1
    dirs = []
    for i in range(segs):
        a, b = pts[i], pts[(i + 1) % n]
        ln = hypot(b[0] - a[0], b[1] - a[1])
        dirs.append(((b[0] - a[0]) / ln, (b[1] - a[1]) / ln))
    left, right = [], []
    for i in range(n):
        if closed:
            d0, d1 = dirs[(i - 1) % segs], dirs[i]
        else:
            d0 = dirs[i - 1] if i > 0 else None
            d1 = dirs[i] if i < segs else None
        if d0 is None or d1 is None:
            d = d1 if d0 is None else d0
            sgn = -1.0 if d0 is None else 1.0
            cx, cy = pts[i][0] + sgn * d[0] * h, pts[i][1] + sgn * d[1] * h
            mx, my, k = -d[1], d[0], h
        else:
            cx, cy = pts[i]
            mx, my = -d0[1] - d1[1], d0[0] + d1[0]
            ml = hypot(mx, my)
            if ml < 1e-6:
                mx, my, k = -d1[1], d1[0], h
            else:
                mx, my = mx / ml, my / ml
                k = h / max(mx * -d1[1] + my * d1[0], 0.5)
        left.append((cx + mx * k, cy + my * k))
        right.append((cx - mx * k, cy - my * k))
    return [[right[i], right[(i + 1) % n], left[(i + 1) % n], left[i]] for i in range(segs)]


def emit_text(mb, text, height, mat, mapf, want, stroke=0.18):
    """Lettering as flat quads.  mapf(u, v) -> (x, y, z); u is centred on 0."""
    quads, width = text_quads(text, height, stroke)
    for q in quads:
        mb.face([mapf(u - width / 2.0, v) for u, v in q], mat, want=want)
    return width


def side_text(mb, car, side, text, yc, z0, height, mat, off=0.007, stroke=0.18):
    """Lettering on the body side, centred on yc, baseline z0, readable from outside on both sides."""
    def mapf(u, v):
        y = yc + side * u
        z = z0 + v
        return (side * (car.side_x(y, z) + off), y, z)
    return emit_text(mb, text, height, mat, mapf, (side, 0, 0), stroke)


SHIELD = [(-0.42, 0.40), (-0.21, 0.50), (0.0, 0.42), (0.21, 0.50), (0.42, 0.40), (0.42, -0.02), (0.30, -0.28),
          (0.0, -0.50), (-0.30, -0.28), (-0.42, -0.02)]


def shield(mb, car, side, yc, zc, size, rim, field, sun, wave):
    """Original HBPD emblem as geometry: shield with a rising sun over two wave bars."""
    def put(poly, mat, off, s=1.0):
        pts = []
        for u, v in poly:
            y, z = yc + side * u * size * s, zc + v * size * s
            pts.append((side * (car.side_x(y, z) + off), y, z))
        mb.face(pts, mat, want=(side, 0, 0))
    # layers sit 8 / 11 / 14 mm off the panel: above the 5 mm pinstripe the shield overlaps (no z-fight)
    put(SHIELD, rim, 0.008)
    put(SHIELD, field, 0.011, 0.84)
    r = 0.17
    put([(r * cos(pi * i / 6.0), 0.03 + r * sin(pi * i / 6.0)) for i in range(7)], sun, 0.014)
    put([(-0.25, -0.10), (0.25, -0.10), (0.25, -0.04), (-0.25, -0.04)], wave, 0.014)
    put([(-0.17, -0.24), (0.17, -0.24), (0.17, -0.18), (-0.17, -0.18)], wave, 0.014)


def bar_between(mb, a, b, radius, mat, segments=8, mirror=False):
    """Tube from point a to point b (both (x, y, z))."""
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    # cylinder along local Y, then rotate: pitch about X, yaw about Z
    yaw = atan2(-dx, dy)
    pitch = atan2(dz, hypot(dx, dy))
    c = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0)
    for sgn in ((1.0, -1.0) if mirror else (1.0,)):
        from mathutils import Euler
        rot = Euler((pitch, 0.0, yaw * sgn), 'XYZ').to_matrix()
        G.add_cylinder(mb.bm, radius, ln, (c[0] * sgn, c[1], c[2]), 'Y', segments, mb.mi(mat), None, rot)


def bull_bar(car, mb, mat, style="bull"):
    """Bar in front of the bumper.  'push' = police push bumper (flat uprights with rubber faces),
    'bull' = tubular hoop with skid plate and two round lamps (SUV / pickup Mod_BumperF_A)."""
    M = car.M
    z0, z1 = car.bumper_f_z
    out = (car.p["bumper_f"] or {}).get("out", 0.05)
    yb = car.y_f + out
    y = yb + (0.06 if style == "push" else 0.085)
    wc = car.w(car.y_f)
    nose = car.zt(car.y_f)
    if style == "push":
        top = min(nose + 0.02, z1 + 0.30)
        xu = 0.29
        hgt = top - z0 + 0.05
        zc = (top + z0 - 0.05) / 2.0
        mb.box((0.075, 0.11, hgt), (xu, y - 0.015, zc), mat, mirror=True, bevel=0.014)
        mb.box((0.05, 0.10, 0.05), (xu, yb + 0.01, z0 + 0.11), mat, mirror=True)
        for zz in (z0 + 0.06, zc + 0.02, top - 0.07):
            mb.box((2 * xu, 0.045, 0.055), (0, y - 0.02, zz), mat)
        # (no wrap-around wings: a bar across the head lamps read as a modelling error, not as a guard)
        # rubber ram strips on the upright faces
        mb.box((0.045, 0.022, hgt - 0.16), (xu, y + 0.045, zc), car.M["under"], mirror=True)
        return
    top = min(nose - 0.02, z1 + 0.30)
    xu = 0.33
    r = 0.028
    # hoop: two uprights + top tube, lower cross tube
    bar_between(mb, (xu, y, z0 - 0.02), (xu, y, top), r, mat, mirror=True)
    bar_between(mb, (-xu - r, y, top), (xu + r, y, top), r, mat)
    bar_between(mb, (-xu, y, z1 - 0.02), (xu, y, z1 - 0.02), r * 0.9, mat)
    # side wings sweeping back to the corners
    for zz, k in ((top - 0.02, 1.0), (z1 - 0.02, 1.0)):
        bar_between(mb, (xu, y, zz), (wc + 0.02, yb - 0.12, zz - 0.02 * k), r * 0.9, mat, mirror=True)
    bar_between(mb, (wc + 0.02, yb - 0.12, top - 0.04), (wc + 0.02, yb - 0.12, z1 - 0.04), r * 0.9, mat, mirror=True)
    # brackets + skid plate
    mb.box((0.05, 0.10, 0.05), (xu, yb + 0.03, z0 + 0.10), M["trim"], mirror=True)
    mb.loft([[(-xu + 0.02, y + 0.02, z1 - 0.05), (xu - 0.02, y + 0.02, z1 - 0.05), (xu - 0.02, y, z1 - 0.07), (-xu + 0.02, y, z1 - 0.07)],
             [(-xu + 0.08, yb - 0.10, z0 - 0.09), (xu - 0.08, yb - 0.10, z0 - 0.09), (xu - 0.08, yb - 0.12, z0 - 0.11), (-xu + 0.08, yb - 0.12, z0 - 0.11)]],
            M["chrome"])
    # round spot lamps on the top tube
    for sx in (-1.0, 1.0):
        mb.cyl(0.085, 0.07, (sx * 0.17, y + 0.005, top + 0.095), M["trim"], axis='Y', segments=10)
        mb.cyl(0.070, 0.02, (sx * 0.17, y + 0.045, top + 0.095), M["head"], axis='Y', segments=10)


def roof_rails(car, mb=None, mat=None):
    b = mb or car.body
    M = car.M
    g = car._gh()
    x = g["xr"] - 0.085
    y0, y1 = g["rr"] + 0.16, g["rf"] - 0.10
    rz = g["rz"]
    b.box((0.034, y1 - y0 - 0.10, 0.03), (x, (y0 + y1) / 2.0, rz + 0.068), mat or M["chrome"], mirror=True, bevel=0.007)
    for t in (0.0, 0.5, 1.0):
        yy = y0 + 0.05 + (y1 - y0 - 0.10) * t
        b.loft([[(x - 0.025, yy - 0.07, rz - 0.03), (x + 0.025, yy - 0.07, rz - 0.03), (x + 0.025, yy + 0.07, rz - 0.03), (x - 0.025, yy + 0.07, rz - 0.03)],
                [(x - 0.018, yy - 0.035, rz + 0.056), (x + 0.018, yy - 0.035, rz + 0.056), (x + 0.018, yy + 0.035, rz + 0.056), (x - 0.018, yy + 0.035, rz + 0.056)]],
               M["trim"], mirror=True)


def running_boards(car, mat, width=0.15):
    p, b = car.p, car.body
    ya = p["axle_r"] + car.Ra + 0.08
    yb = p["axle_f"] - car.Ra - 0.08
    ym = (ya + yb) / 2.0
    zb = K.interp(car.bottom_keys, ym)
    x = car.side_x(ym, p["rocker_z"])
    b.box((width, yb - ya, 0.04), (x + width / 2.0 - 0.045, ym, zb + 0.005), mat, mirror=True)
    b.box((width - 0.03, yb - ya - 0.10, 0.008), (x + width / 2.0 - 0.045, ym, zb + 0.028), car.M["under"], mirror=True)
    for t in (0.12, 0.88):
        b.box((0.10, 0.05, 0.05), (x - 0.03, ya + (yb - ya) * t, zb - 0.01), car.M["under"], mirror=True)


def mud_flaps(car, rear_only=False, h=0.22):
    p, b = car.p, car.body
    for tag, yc in car.axles:
        if rear_only and tag != "R":
            continue
        y = yc - car.Ra - 0.012
        zb = K.interp(car.bottom_keys, y)
        b.box((p["wheel_w"] + 0.04, 0.02, h), (p["track"] / 2.0 + 0.01, y, zb - h / 2.0 + 0.05), car.M["under"], mirror=True)


def partition(car, y, mat=None):
    """Cage partition between the front seats and the rear bench (police, taxi)."""
    b, M, p = car.body, car.M, car.p
    g = car._gh()
    m = mat or M["trim"]
    xb = car.belt_x(y) - 0.07
    zb = car.zt(y) - 0.02
    xt = g["xr"] - 0.08
    ztop = g["zR"] - p["roof_t"] - 0.012
    z0 = p["tub_z"] + 0.32
    b.box((2 * xb, 0.03, zb - z0), (0, y, (zb + z0) / 2.0), m)
    b.loft([[(xb - 0.04, y - 0.015, zb), (xb, y - 0.015, zb), (xb, y + 0.015, zb), (xb - 0.04, y + 0.015, zb)],
            [(xt - 0.04, y - 0.015, ztop), (xt, y - 0.015, ztop), (xt, y + 0.015, ztop), (xt - 0.04, y + 0.015, ztop)]],
           m, mirror=True)
    b.box((2 * xt, 0.03, 0.04), (0, y, ztop - 0.02), m)


def grille_frame(car, slats=0, badge=None):
    """Chrome surround (and optional vertical slats) around the kit grille; makes a taller 'truck' face."""
    b, M = car.body, car.M
    gx, gz, gh = car.grille_box
    yf = car.y_f
    for sx in (-1.0, 1.0):
        b.box((0.026, 0.06, gh + 0.03), (sx * (gx + 0.004), yf + 0.004, gz), M["chrome"])
    b.box((2 * gx + 0.02, 0.06, 0.022), (0, yf + 0.004, gz - gh / 2.0), M["chrome"])
    for i in range(slats):
        x = (i - (slats - 1) / 2.0) * (2 * gx - 0.08) / max(slats - 1, 1)
        b.box((0.016, 0.014, gh - 0.01), (x, yf + 0.03, gz), M["chrome"])
    if badge is not None:
        b.box((0.13, 0.02, 0.055), (0, yf + 0.04, gz), badge, bevel=0.012)


def lod_recolor_sides(car, mat, y0, y1, zmin=0.0):
    """Paint the side faces of Body_LOD1 between y0..y1 (door livery survives at distance)."""
    lb = car.mb("Body_LOD1")
    i0 = lb.mi(car.M["paint"])
    i1 = lb.mi(mat)
    for f in lb.bm.faces:
        if f.material_index != i0:
            continue
        c = f.calc_center_median()
        n = f.normal
        if y0 < c.y < y1 and abs(n.x) > 0.6 and c.z > zmin:
            f.material_index = i1


def lod_recolor_top(car, mat, y0, y1):
    lb = car.mb("Body_LOD1")
    i0 = lb.mi(car.M["paint"])
    i1 = lb.mi(mat)
    for f in lb.bm.faces:
        if f.material_index != i0:
            continue
        c = f.calc_center_median()
        if y0 < c.y < y1 and f.normal.z > 0.6:
            f.material_index = i1


# ------------------------------------------------------------------------------------------------
# SUV  'suv'  - 4.75 m five-door, 1.80 m roof (1.87 over the rails), 0.26 m ground clearance
# ------------------------------------------------------------------------------------------------
SUV = _p(
    name="suv", width=1.92, height=1.80,
    axle_f=1.50, axle_r=-1.42, wheel_r=0.38, wheel_w=0.26, track=1.61, wheel_style="b_suv",
    arch_gap=0.055, arch_lip="trim",
    top=[(-2.30, 1.07), (-2.22, 1.19), (1.02, 1.16), (2.06, 1.115), (2.30, 1.02)],
    bottom=[(-2.30, 0.44), (-1.98, 0.30), (2.00, 0.29), (2.30, 0.42)],
    plan=[(-2.30, 0.915), (-2.10, 0.985), (-1.86, 1.0), (1.90, 1.0), (2.14, 0.97), (2.30, 0.90)],
    crown=0.035, crown_w=0.36, swage_z=0.76, rocker_z=0.46, tub_z=0.36, seat_z=0.64,
    cowl_y=1.02, roof_f=0.50, roof_r=-2.02, deck_y=-2.22, c_pillar=(0.18, 0.15), tumble=0.10, a_pillar=0.13,
    pillars_extra=[(-1.10, -0.93, -1.08, -0.95)],
    doors=[("F", -0.04, 0.96), ("R", -0.93, -0.04)], trunk=None,
    seat_f_y=0.02, seat_r_y=-0.86, seat_color="Khaki",
    head=dict(w=0.30, h=0.17, inset=0.03, z=None), grille=dict(bars=4),
    tail=dict(w=0.17, h=0.34, inset=0.02, z=None),
    bumper_f=dict(h=0.25, out=0.06, wrap=0.42), bumper_r=dict(h=0.24, out=0.06, wrap=0.40),
    plate_r=False, exhaust=dict(x=-0.56, r=0.038),
    mods=[m for m in K.FULL_MODS if m != "Mod_BumperF_A"], spoiler_at="roof",
)


def build_suv():
    car = new_car(SUV)
    p, M, b = car.p, car.M, car.body
    car.skin()
    car.greenhouse()
    car.interior()
    car.bays()
    fascias(car)
    car.details()
    car.closures()
    yf, yr = car.y_f, car.y_r
    # --- face: chrome grille surround with slats, skid plate, round fog lamps
    grille_frame(car, slats=5, badge=M["paint2"])
    z0, z1 = car.bumper_f_z
    of = p["bumper_f"]["out"]
    wc = car.w(yf)
    b.loft([[(-0.44, yf + of + 0.012, z0 + 0.10), (0.44, yf + of + 0.012, z0 + 0.10), (0.44, yf + of - 0.02, z0 + 0.10), (-0.44, yf + of - 0.02, z0 + 0.10)],
            [(-0.36, yf + of - 0.07, z0 - 0.075), (0.36, yf + of - 0.07, z0 - 0.075), (0.36, yf + of - 0.10, z0 - 0.075), (-0.36, yf + of - 0.10, z0 - 0.075)]],
           M["chrome"])
    b.cyl(0.055, 0.03, (wc - 0.36, yf + of + 0.004, z0 + 0.075), M["head"], axis='Y', segments=8, mirror=True)
    b.box((0.16, 0.02, 0.15), (wc - 0.36, yf + of - 0.008, z0 + 0.075), M["trim"], mirror=True)
    # tow hooks
    b.box((0.04, 0.07, 0.05), (0.50, yf + of - 0.012, z0 - 0.02), G.pmat("CarRed"), mirror=True)
    # --- body cladding: roof rails, running boards, mud flaps
    roof_rails(car)
    running_boards(car, M["trim"])
    mud_flaps(car)
    # --- tail: spare wheel on the tailgate, plate, hatch handle, high brake light
    zs = 0.97
    ys = yr - 0.03
    b.box((0.16, 0.05, 0.16), (0, yr - 0.015, zs), M["trim"])
    b.cyl(0.345, 0.14, (0, ys - 0.07, zs), M["trim"], axis='Y', segments=14)
    b.cyl(0.355, 0.09, (0, ys - 0.07, zs), M["under"], axis='Y', segments=14)
    b.cyl(0.255, 0.03, (0, ys - 0.148, zs), M["paint2"], axis='Y', segments=14)
    b.cyl(0.09, 0.03, (0, ys - 0.158, zs), M["chrome"], axis='Y', segments=8)
    b.box((0.32, 0.016, 0.12), (-0.52, yr - 0.012, 0.80), M["plate"])
    b.box((0.35, 0.012, 0.15), (-0.52, yr - 0.004, 0.80), M["trim"])
    b.box((0.20, 0.03, 0.04), (0.52, yr - 0.012, 0.86), M["chrome"], bevel=0.008)
    g = car._gh()
    b.box((0.36, 0.03, 0.035), (0, g["rr"] - 0.055, g["zR"] - 0.03), M["tail"])
    # rear wiper
    b.box((0.30, 0.012, 0.016), (0.12, g["dy"] - 0.01, g["zd"] + 0.07), M["trim"], rot=(0, radians(-12), 0))
    wheels(car)
    car.collision()
    car.lod()
    car.mb("Body_LOD1").cyl(0.35, 0.14, (0, ys - 0.07, zs), M["trim"], axis='Y', segments=8)
    car.mods()
    bull_bar(car, car.mb("Mod_BumperF_A"), M["chrome"], "bull")
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# PICKUP  'pickup' - 5.34 m double cab, open bed with a separate Tailgate
# ------------------------------------------------------------------------------------------------
BED_X = 0.83        # inner half width of the bed
BED_Z = 0.68        # bed floor height
PICKUP = _p(
    name="pickup", width=1.94, height=1.84,
    axle_f=1.70, axle_r=-1.60, wheel_r=0.40, wheel_w=0.28, track=1.61, wheel_style="b_allterrain",
    arch_gap=0.055, arch_lip="trim",
    top=[(-2.60, 1.12), (-0.98, 1.12), (1.10, 1.16), (2.32, 1.11), (2.60, 1.02)],
    bottom=[(-2.60, 0.50), (-2.28, 0.37), (2.24, 0.36), (2.60, 0.47)],
    plan=[(-2.60, 1.0), (2.12, 1.0), (2.42, 0.965), (2.60, 0.90)],
    crown=0.035, crown_w=0.36, shoulder_inset=0.06, swage_z=0.80, rocker_z=0.50, tub_z=0.40, seat_z=0.68,
    cowl_y=1.10, roof_f=0.62, roof_r=-0.88, deck_y=-0.98, c_pillar=(0.12, 0.10), tumble=0.11, a_pillar=0.13,
    doors=[("F", 0.02, 1.06), ("R", -0.88, 0.02)], trunk=None, open_top=[(-2.60, -1.04)],
    seat_f_y=0.20, seat_r_y=-0.56, seat_color="WarmGrey",
    head=dict(w=0.26, h=0.20, inset=0.03, z=None), grille=dict(bars=4),
    tail=dict(w=0.09, h=0.30, inset=0.015, z=0.87),
    bumper_f=dict(h=0.24, out=0.07, wrap=0.44), bumper_r=dict(h=0.20, out=0.09, wrap=0.30),
    plate_r=False, exhaust=dict(x=-0.64, r=0.04),
    mods=["Mod_Spoiler_A", "Mod_BumperR_A", "Mod_Hood_A", "Mod_Skirts_A", "Mod_Exhaust_A", "Mod_Grille_A"],
    spoiler_at="roof",
)


def pickup_bed(car):
    p, M, b = car.p, car.M, car.body
    y0 = car.y_r
    y1 = p["open_top"][0][1]
    xb, zf = BED_X, BED_Z
    zt = car.zt(y0)
    yi = y0 + 0.06
    b.face([(-xb, y0 + 0.002, zf), (xb, y0 + 0.002, zf), (xb, y1, zf), (-xb, y1, zf)], M["trim"], want=(0, 0, 1))
    for i in (-1, 0, 1):
        b.box((0.16, y1 - yi - 0.08, 0.012), (i * 0.36, (yi + y1) / 2.0, zf + 0.006), M["under"])
    b.face([(xb, y0, zf), (xb, y1, zf), (xb, y1, zt), (xb, y0, zt)], M["paint"], mirror=True, want=(-1, 0, 0))
    b.face([(-xb, y1, zf), (xb, y1, zf), (xb, y1, zt), (-xb, y1, zt)], M["paint"], want=(0, -1, 0))
    # rail caps
    xo = car.belt_x(y0)
    b.box((xo - xb + 0.035, y1 - y0, 0.03), ((xo + xb) / 2.0 + 0.004, (y0 + y1) / 2.0, zt + 0.013), M["trim"], mirror=True)
    b.box((2 * xb, 0.075, 0.03), (0, y1 + 0.03, zt + 0.013), M["trim"])
    # wheel houses inside the bed
    yc = p["axle_r"]
    top = car.zc + car.Ra + 0.05
    x0 = car.x_well - 0.03
    b.box((xb - x0, 2 * car.Ra + 0.06, top - zf), ((xb + x0) / 2.0, yc, (top + zf) / 2.0), M["paint"], mirror=True, bevel=0.035)
    # tail: lower panel below the bed floor + the two corner posts that carry the tail lamps
    end_cap_part(car, [(1, zf, False)], M["paint"])
    end_cap_part(car, [(1, zf, True), (0, xb, True)], M["paint"])
    # inner faces of the corner posts (seen when the tailgate is open)
    b.face([(xb, y0, zf), (xb, y0 + 0.06, zf), (xb, y0 + 0.06, zt), (xb, y0, zt)], M["paint"], mirror=True, want=(-1, 0, 0))


def pickup_tailgate(car):
    M = car.M
    mb = car.mb("Tailgate")
    y0 = car.y_r
    xh = BED_X - 0.008
    zf = BED_Z + 0.012
    zt = car.zt(y0)
    prof = [(y0 - 0.004, zf), (y0 + 0.056, zf), (y0 + 0.056, zt), (y0 + 0.030, zt + 0.012), (y0 - 0.004, zt - 0.006)]
    mb.prism(prof, -xh, xh, M["paint"], axis='X')
    # pressed centre panel, handle, top cap, inner ribs
    mb.box((2 * xh - 0.26, 0.014, (zt - zf) - 0.17), (0, y0 - 0.008, (zt + zf) / 2.0 - 0.015), M["paint"], bevel=0.012)
    mb.box((0.24, 0.022, 0.055), (0, y0 - 0.016, zt - 0.072), M["trim"])
    mb.box((2 * xh, 0.068, 0.018), (0, y0 + 0.026, zt + 0.016), M["trim"])
    for i in (-1, 0, 1):
        mb.box((0.34, 0.012, (zt - zf) - 0.12), (i * 0.48, y0 + 0.060, (zt + zf) / 2.0), M["trim"])
    car.origins["Tailgate"] = ((0.0, y0 + 0.026, zf), None)


def pickup_sport_bar(car, mb):
    """Mod_Roof_A of the pickup: tubular sport bar behind the cab with four spot lamps."""
    M = car.M
    zt = car.zt(-1.2) + 0.028
    x = car.belt_x(-1.2) - 0.035
    ya = -1.14
    top = car.p["height"] - 0.04
    r = 0.032
    bar_between(mb, (x, ya, zt), (x - 0.05, ya, top), r, M["chrome"], mirror=True)
    bar_between(mb, (-(x - 0.05) - r, ya, top), (x - 0.05 + r, ya, top), r, M["chrome"])
    bar_between(mb, (x - 0.04, ya, top - 0.10), (x, ya - 0.62, zt), r * 0.9, M["chrome"], mirror=True)
    mb.box((0.09, 0.12, 0.02), (x, ya, zt), M["trim"], mirror=True)
    mb.box((0.09, 0.12, 0.02), (x, ya - 0.62, zt), M["trim"], mirror=True)
    for xx in (-0.48, -0.16, 0.16, 0.48):
        mb.cyl(0.085, 0.08, (xx, ya + 0.01, top + 0.11), M["trim"], axis='Y', segments=10)
        mb.cyl(0.070, 0.02, (xx, ya + 0.055, top + 0.11), M["head"], axis='Y', segments=10)
        mb.box((0.03, 0.03, 0.05), (xx, ya, top + 0.035), M["trim"])


def pickup_bed_wing(car, mb):
    """Mod_Spoiler_B of the pickup: wing across the tail of the bed, standing on the bed rails."""
    M = car.M
    y1 = car.y_r + 0.03
    yw = y1 + 0.20
    zd = car.zt(yw) + 0.028
    zw = zd + 0.24
    hx = car.belt_x(yw) + 0.03
    prof = [(yw + 0.16, zw - 0.012), (yw + 0.06, zw + 0.028), (yw - 0.12, zw + 0.055), (yw - 0.16, zw + 0.046), (yw - 0.03, zw + 0.002)]
    mb.prism(prof, -hx, hx, M["paint"], axis='X')
    for sx in (-1.0, 1.0):
        mb.loft([[(sx * (hx - 0.03) - 0.014, yw + 0.17, zd), (sx * (hx - 0.03) + 0.014, yw + 0.17, zd), (sx * (hx - 0.03) + 0.014, yw - 0.13, zd), (sx * (hx - 0.03) - 0.014, yw - 0.13, zd)],
                 [(sx * hx - 0.014, yw + 0.18, zw + 0.07), (sx * hx + 0.014, yw + 0.18, zw + 0.07), (sx * hx + 0.014, yw - 0.18, zw + 0.085), (sx * hx - 0.014, yw - 0.18, zw + 0.085)]],
                car._mat("paint2"))


def build_pickup():
    car = new_car(PICKUP)
    p, M, b = car.p, car.M, car.body
    car.skin()
    remove_end_cap(car)
    car.greenhouse()
    car.interior()
    car.bays()
    fascias(car, front_mat=M["chrome"], rear_mat=M["chrome"])
    car.details()
    car.closures()
    yf, yr = car.y_f, car.y_r
    pickup_bed(car)
    pickup_tailgate(car)
    # --- face: big chrome grille with vertical slats, tow hooks
    grille_frame(car, slats=7, badge=M["paint"])
    z0, z1 = car.bumper_f_z
    of = p["bumper_f"]["out"]
    b.box((0.04, 0.07, 0.05), (0.46, yf + of - 0.012, z0 - 0.015), M["trim"], mirror=True)
    # cab clearance lamps
    g = car._gh()
    for xx in (-0.44, -0.22, 0.0, 0.22, 0.44):
        b.box((0.09, 0.05, 0.03), (xx, g["rf"] - 0.10, g["rz"] + 0.008), M["indicator"])
    # --- rear: plate + hitch on the chrome step bumper, mud flaps, side steps
    zr0, zr1 = car.bumper_r_z
    orr = p["bumper_r"]["out"]
    b.box((0.32, 0.016, 0.12), (0, yr - orr - 0.010, (zr0 + zr1) / 2.0), M["plate"])
    b.box((0.36, 0.012, 0.15), (0, yr - orr - 0.002, (zr0 + zr1) / 2.0), M["trim"])
    b.box((0.60, 0.07, 0.012), (0, yr - orr + 0.03, zr1 + 0.004), M["under"])       # step tread
    b.box((0.07, 0.16, 0.05), (0, yr - orr + 0.045, zr0 - 0.02), M["trim"])
    b.cyl(0.028, 0.05, (0, yr - orr - 0.012, zr0 + 0.025), M["chrome"], axis='Z', segments=8)
    mud_flaps(car, rear_only=True, h=0.24)
    running_boards(car, M["chrome"], width=0.13)
    wheels(car)
    car.collision()
    car.lod()
    lod_recolor_top(car, M["trim"], car.y_r, p["open_top"][0][1])
    car.mods()
    bull_bar(car, car.mb("Mod_BumperF_A"), M["trim"], "bull")
    pickup_sport_bar(car, car.mb("Mod_Roof_A"))
    pickup_bed_wing(car, car.mb("Mod_Spoiler_B"))
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# VAN  'van' - 5.0 m panel van, 2.02 m roof, sliding-door look, Door_RearL / Door_RearR
# ------------------------------------------------------------------------------------------------
VAN_DOOR_X = 0.735      # outer (hinge) edge of the rear doors
VAN_DOOR_Z0 = 0.63
VAN_DOOR_XA = 0.007     # inner (meeting) edge of each rear door
VAN_WIN_Z = (1.27, 1.74)                                   # rear door window opening
VAN_WIN_X = (VAN_DOOR_XA + 0.115, VAN_DOOR_X - 0.105)
VAN = _p(
    name="van", width=1.96, height=2.02,
    axle_f=1.70, axle_r=-1.46, wheel_r=0.36, wheel_w=0.25, track=1.65, wheel_style="b_steel",
    # nose: high, nearly flat hood with a blunt face (the first version sloped from 1.08 down to 0.80
    # and read as a sedan nose glued to a box)
    top=[(-2.45, 1.08), (-2.42, 1.12), (1.50, 1.10), (2.24, 1.01), (2.45, 0.91)],
    bottom=[(-2.45, 0.44), (-2.12, 0.31), (2.10, 0.29), (2.45, 0.40)],
    plan=[(-2.45, 0.955), (-2.25, 1.0), (2.02, 1.0), (2.30, 0.955), (2.45, 0.87)],
    swage_z=0.72, rocker_z=0.44, tub_z=0.33, seat_z=0.66, tumble=0.07, crown=0.03, crown_w=0.36,
    cowl_y=1.50, roof_f=1.08, roof_r=-2.40, deck_y=-2.42, c_pillar=(0.10, 0.10), a_pillar=0.12,
    pillars_extra=[(-2.33, 0.40, -2.31, 0.40)], b_pillar=None,
    doors=[("F", 0.48, 1.22)], trunk=None, seat_f_y=0.62, seat_r_y=None, seat_color="WarmGrey",
    head=dict(w=0.28, h=0.17, inset=0.03, z=None), grille=dict(bars=2),
    tail=dict(w=0.10, h=0.40, inset=0.02, z=None),
    bumper_f=dict(h=0.24, out=0.06, wrap=0.36), bumper_r=dict(h=0.20, out=0.07, wrap=0.30),
    plate_r=False, exhaust=dict(x=-0.60, r=0.036), mods=[],
)


def upper_x(car, y, z):
    """X of the upper (greenhouse) side panel at height z."""
    g = car._gh()
    zb = car.zt(y) - 0.02
    zp = g["zR"] - 0.012
    t = max(0.0, min(1.0, (z - zb) / (zp - zb)))
    return car.belt_x(y) + (g["xr"] - car.belt_x(y)) * t


def seam_v(car, side, y, z0, z1, mat, wy=0.014, off=0.004):
    """Vertical panel seam on the body side, from z0 up to z1 (may continue onto the upper panel)."""
    b = car.body
    zt = car.zt(y)
    zs = sorted(set([z0] + [q[1] for q in car._side_profile(y) if z0 < q[1] < min(z1, zt)] + [min(z1, zt)]))
    for za, zb in zip(zs[:-1], zs[1:]):
        side_quad(b, car, side, y - wy / 2, y + wy / 2, za, zb, mat, off)
    if z1 > zt:
        pts = []
        for yy, zz in ((y - wy / 2, zt - 0.02), (y + wy / 2, zt - 0.02), (y + wy / 2, z1), (y - wy / 2, z1)):
            pts.append((side * (upper_x(car, yy, zz) + off), yy, zz))
        b.face(pts, mat, want=(side, 0, 0))


def van_side_pressings(car):
    """Raised 'window blank' pressings on the upper side panels, three per side between the seams
    (9 mm proud, chamfered all round): they give the big flat flanks of a panel van some structure."""
    b, M = car.body, car.M
    g = car._gh()
    z0 = car.zt(0.0) + 0.11
    z1 = g["zR"] - 0.15
    ch, out = 0.018, 0.009
    for ya, yb in ((-2.27, -1.60), (-1.44, -0.72), (-0.56, 0.31)):
        secs = []
        for y, proud in ((ya, 0.0), (ya + ch, out), (yb - ch, out), (yb, 0.0)):
            secs.append([(upper_x(car, y, z0) - 0.012, y, z0), (upper_x(car, y, z0 + ch) + proud, y, z0 + ch),
                         (upper_x(car, y, z1 - ch) + proud, y, z1 - ch), (upper_x(car, y, z1) - 0.012, y, z1)])
        b.loft(secs, M["paint"], mirror=True)


def van_clear_doorway(car):
    """The kit skins the 3 cm of body top between the tail and deck_y.  On the van that strip is a
    body-colour bar across the rear doorway at belt height (seen as soon as the doors open): delete it
    and keep only the two bits on top of the corner posts.  Call right after skin()."""
    b = car.body
    yr, dy = car.y_r, car.p["deck_y"]
    zmin = min(car.zt(yr), car.zt(dy)) - 1e-4
    dead = [f for f in b.bm.faces if all(v.co.y <= dy + 1e-4 and v.co.z >= zmin for v in f.verts)]
    if dead:
        bmesh.ops.delete(b.bm, geom=dead, context='FACES')
    b.face([(VAN_DOOR_X, yr, car.zt(yr)), (car.belt_x(yr), yr, car.zt(yr)), (car.belt_x(dy), dy, car.zt(dy)),
            (VAN_DOOR_X, dy, car.zt(dy))], car.M["paint"], mirror=True, want=(0, 0, 1))
    return len(dead)


def van_rear_glass(car):
    """One pane per rear door instead of the kit's single Glass_Rear quad (which would hang in the
    doorway when the doors open).  Glass_Rear = left door window, Glass_Rear_R = right door window;
    build_van() parents them to Door_RearL / Door_RearR after finish()."""
    old = car.parts.pop("Glass_Rear", None)
    if old is not None and old.bm is not None:
        old.bm.free()
    y = car.y_r + 0.002
    (z0, z1), (x0, x1) = VAN_WIN_Z, VAN_WIN_X
    e = 0.008
    for side, name in ((-1.0, "Glass_Rear"), (1.0, "Glass_Rear_R")):
        car.mb(name).face([(side * (x0 - e), y, z0 - e), (side * (x1 + e), y, z0 - e), (side * (x1 + e), y, z1 + e),
                           (side * (x0 - e), y, z1 + e)], car.M["glass"], want=(0, -1, 0))


def nest(car, child, parent):
    """Parent a finished part under another finished part; the world transform does not change
    (both are unrotated, unscaled children of the asset root)."""
    from mathutils import Matrix, Vector
    c, par = car.objects[child], car.objects[parent]
    c.parent = par
    c.matrix_parent_inverse = Matrix.Identity(4)
    c.location = Vector(c.location) - Vector(par.location)
    return c


def van_rear_doors(car):
    M = car.M
    ye = car.y_r
    xe, z0 = VAN_DOOR_X, VAN_DOOR_Z0
    z1 = car.p["height"] - 0.11
    yo, yi = ye - 0.022, ye + 0.027
    wz0, wz1 = VAN_WIN_Z
    for side, sfx in ((-1.0, "L"), (1.0, "R")):
        mb = car.mb("Door_Rear" + sfx)
        xa = VAN_DOOR_XA
        wx0, wx1 = VAN_WIN_X

        def bx(x0, x1, za, zb, mat, ya=yo, yb=yi, bevel=0.0):
            mb.box((x1 - x0, yb - ya, zb - za), (side * (x0 + x1) / 2.0, (ya + yb) / 2.0, (za + zb) / 2.0), mat, bevel=bevel)
        bx(xa, xe, z0, wz0, M["paint"])
        bx(xa, xe, wz1, z1, M["paint"])
        bx(xa, wx0, wz0, wz1, M["paint"])
        bx(wx1, xe, wz0, wz1, M["paint"])
        # pressed lower panel, window rubber, hinges, inner card
        bx(xa + 0.08, xe - 0.08, z0 + 0.09, wz0 - 0.11, M["paint"], ya=yo - 0.009, yb=yo + 0.004, bevel=0.014)
        for (x0, x1, za, zb) in ((wx0 - 0.022, wx1 + 0.022, wz0 - 0.022, wz0), (wx0 - 0.022, wx1 + 0.022, wz1, wz1 + 0.022),
                                 (wx0 - 0.022, wx0, wz0, wz1), (wx1, wx1 + 0.022, wz0, wz1)):
            bx(x0, x1, za, zb, M["trim"], ya=yo - 0.004, yb=yo + 0.004)
        for zz in (z0 + 0.15, 1.17, z1 - 0.15):
            mb.box((0.055, 0.03, 0.10), (side * (xe + 0.012), yo + 0.004, zz), M["trim"])
        bx(xa + 0.05, xe - 0.05, z0 + 0.05, wz0 - 0.05, M["interior"], ya=yi - 0.004, yb=yi + 0.006)
        if side > 0:       # handle + lock on the right-hand door (it opens first)
            mb.box((0.035, 0.03, 0.17), (xa + 0.06, yo - 0.014, 1.08), M["chrome"], bevel=0.008)
            mb.box((0.05, 0.012, 0.05), (xa + 0.06, yo - 0.006, 0.95), M["trim"])
        car.origins["Door_Rear" + sfx] = ((side * xe, ye, z0), None)


def build_van():
    car = new_car(VAN)
    p, M, b = car.p, car.M, car.body
    car.skin()
    remove_end_cap(car)
    van_clear_doorway(car)
    car.greenhouse()
    van_rear_glass(car)
    car.interior()
    remove_faces_at_y(b, p["deck_y"])            # kit's interior rear wall: the doors close that hole now
    car.bays()
    fascias(car, front_mat=M["trim"], rear_mat=M["trim"])
    car.details()
    car.closures()
    yf, yr = car.y_f, car.y_r
    g = car._gh()
    # --- tail: sill below the doors, corner posts with the lamps, post fillers above the belt
    end_cap_part(car, [(1, VAN_DOOR_Z0, False)], M["paint"])
    end_cap_part(car, [(1, VAN_DOOR_Z0, True), (0, VAN_DOOR_X, True)], M["paint"])
    zb = car.zt(yr) + 0.02
    b.face([(VAN_DOOR_X - 0.01, yr, zb), (g["xd"], yr, zb), (g["xr"], yr, g["zR"] - 0.02), (VAN_DOOR_X - 0.02, yr, g["zR"] - 0.02)],
           M["paint"], mirror=True, want=(0, -1, 0))
    b.face([(-VAN_DOOR_X, yr, g["zR"] - 0.11), (VAN_DOOR_X, yr, g["zR"] - 0.11), (VAN_DOOR_X, yr, g["zR"] - 0.02), (-VAN_DOOR_X, yr, g["zR"] - 0.02)],
           M["paint"], want=(0, -1, 0))
    van_rear_doors(car)
    zr0, zr1 = car.bumper_r_z
    orr = p["bumper_r"]["out"]
    b.box((0.32, 0.016, 0.12), (0, yr - orr - 0.010, (zr0 + zr1) / 2.0 + 0.01), M["plate"])
    b.box((0.60, 0.07, 0.012), (0, yr - orr + 0.03, zr1 + 0.004), M["under"])
    b.box((0.30, 0.03, 0.035), (0, yr - 0.02, g["zR"] - 0.035), M["tail"])           # high brake light
    # --- cargo bulkhead behind the seats
    yb_ = 0.20
    xb = car.belt_x(yb_) - 0.03
    tz = p["tub_z"]
    zc = car.zt(yb_)
    b.prism([(-xb, tz), (xb, tz), (xb, zc), (g["xr"] - 0.07, g["zR"] - 0.07), (-(g["xr"] - 0.07), g["zR"] - 0.07), (-xb, zc)],
            yb_ - 0.02, yb_ + 0.02, M["interior"], axis='Y')
    # --- sliding door on the kerb (right) side: seams, top track, rail, handle; panel seams left
    ztop = g["zR"] - 0.05
    zlow = p["rocker_z"] + 0.012
    ya, yb2 = -0.64, 0.38
    seam_v(car, 1.0, ya, zlow, ztop, M["trim"])
    seam_v(car, 1.0, yb2, zlow, ztop, M["trim"])
    b.face([(upper_x(car, ya, ztop) + 0.004, ya, ztop - 0.007), (upper_x(car, yb2, ztop) + 0.004, yb2, ztop - 0.007),
            (upper_x(car, yb2, ztop) + 0.004, yb2, ztop + 0.007), (upper_x(car, ya, ztop) + 0.004, ya, ztop + 0.007)],
           M["trim"], want=(1, 0, 0))
    side_quad(b, car, 1.0, ya, yb2, zlow, zlow + 0.014, M["trim"], 0.004)
    zrail = car.zt(-1.2) - 0.045
    b.box((0.026, 1.16, 0.04), (car.side_x(-1.2, zrail) + 0.004, ya - 0.56, zrail), M["trim"], bevel=0.008)
    b.box((0.03, 0.05, 0.13), (car.side_x(0.26, 0.98) + 0.012, 0.27, 0.98), M["chrome"], bevel=0.008)
    b.box((0.012, 0.09, 0.17), (car.side_x(0.26, 0.98) + 0.002, 0.27, 0.98), M["trim"])
    for yy in (-0.64, -1.52):
        seam_v(car, -1.0, yy, zlow, ztop, M["trim"], wy=0.010)
    seam_v(car, 1.0, -1.52, zlow, ztop, M["trim"], wy=0.010)
    van_side_pressings(car)
    # --- roof ribs, clearance marker lamps, door mirrors (tall truck type)
    y0r, y1r = g["rr"] + 0.20, g["rf"] - 0.30
    for xx in (-0.50, -0.25, 0.0, 0.25, 0.50):
        b.box((0.10, y1r - y0r, 0.014), (xx, (y0r + y1r) / 2.0, g["rz"] + 0.004), M["paint"], bevel=0.006)
    for sfx, side in (("L", -1.0), ("R", 1.0)):
        mb = car.mb("Door_F" + sfx)
        ym = p["doors"][0][2] - 0.13
        xm = car.belt_x(ym)
        zm = car.zt(ym)
        mb.box((0.035, 0.035, 0.30), (side * (xm + 0.16), ym, zm + 0.20), M["trim"])
        mb.box((0.05, 0.10, 0.26), (side * (xm + 0.185), ym - 0.005, zm + 0.20), M["trim"], bevel=0.012)
        mb.box((0.012, 0.085, 0.22), (side * (xm + 0.185), ym - 0.058, zm + 0.20), M["chrome"])
        mb.box((0.15, 0.03, 0.03), (side * (xm + 0.09), ym, zm + 0.30), M["trim"])
    # side marker lamps on the rear quarters, step under the sliding door
    b.box((0.014, 0.10, 0.045), (car.side_x(-2.2, 0.95) + 0.003, -2.22, 0.95), M["tail"], mirror=True)
    zbt = K.interp(car.bottom_keys, 0.0)
    b.box((0.10, 0.86, 0.04), (car.side_x(0.0, p["rocker_z"]) - 0.012, (ya + yb2) / 2.0, zbt + 0.045), M["trim"])
    mud_flaps(car, rear_only=True, h=0.20)
    wheels(car)
    car.collision()
    car.lod()
    # LOD: the kit glazes the whole greenhouse; a panel van is glazed around the cab only
    lb = car.mb("Body_LOD1")
    ig = lb.mi(M["glass"])
    dead = [f for f in lb.bm.faces if f.material_index == ig and (abs(f.normal.x) > 0.5 or f.normal.y < -0.5)]
    bmesh.ops.delete(lb.bm, geom=dead, context='FACES_ONLY')
    yp = p["pillars_extra"][0][1]
    dy, cy = g["dy"], g["cy"]
    lb.face([(g["xd"], dy, g["zd"]), (car.belt_x(yp), yp, car.zt(yp)), (g["xr"], yp, g["rz"]), (g["xr"], g["rr"], g["rz"])],
            M["paint"], mirror=True, want=(1, 0, 0.2))
    lb.face([(car.belt_x(yp), yp, car.zt(yp)), (g["xc"], cy, g["zc"]), (g["xr"], g["rf"], g["rz"]), (g["xr"], yp, g["rz"])],
            M["glass"], mirror=True, want=(1, 0, 0.2))
    lb.face([(-g["xd"], dy, g["zd"]), (g["xd"], dy, g["zd"]), (g["xr"], g["rr"], g["rz"]), (-g["xr"], g["rr"], g["rz"])],
            M["paint"], want=(0, -1, 0.1))
    lb.box((0.46, 0.03, 0.44), (0.38, yr - 0.01, 1.50), M["trim"], mirror=True)
    car.mods()
    car.finish()
    nest(car, "Glass_Rear", "Door_RearL")          # the panes swing with their doors
    nest(car, "Glass_Rear_R", "Door_RearR")
    return car


# ------------------------------------------------------------------------------------------------
# POLICE CRUISER  'police_cruiser' - 4.92 m pursuit sedan, HBPD blue / white livery
# ------------------------------------------------------------------------------------------------
CRUISER = _p(
    name="police_cruiser", width=1.90, height=1.47,
    axle_f=1.50, axle_r=-1.42, wheel_r=0.35, wheel_w=0.25, track=1.60, wheel_style="b_steel",
    top=[(-2.40, 0.97), (-1.56, 1.03), (0.88, 0.99), (2.08, 0.87), (2.40, 0.74)],
    bottom=[(-2.40, 0.36), (-2.00, 0.23), (2.04, 0.21), (2.40, 0.29)],
    plan=[(-2.40, 0.86), (-2.16, 0.965), (-1.88, 1.0), (1.92, 1.0), (2.20, 0.95), (2.40, 0.82)],
    crown=0.035, crown_w=0.34, shoulder_inset=0.10, crease_drop=0.11, swage_z=0.63,
    cowl_y=0.88, roof_f=0.16, roof_r=-0.98, deck_y=-1.56, c_pillar=(0.42, 0.26), tumble=0.15, a_pillar=0.14,
    doors=[("F", -0.12, 0.86), ("R", -0.97, -0.12)],
    seat_f_y=-0.10, seat_r_y=-0.98, seat_color="WarmGrey",
    head=dict(w=0.40, h=0.11, inset=0.03, z=None), grille=dict(bars=2),
    tail=dict(w=0.46, h=0.11, inset=0.02, z=None),
    bumper_f=dict(h=0.23, out=0.06, wrap=0.40), bumper_r=dict(h=0.23, out=0.06, wrap=0.36),
    exhaust=dict(x=-0.52, r=0.036),
    roof_mat="paint2", siren=True, mods=[],
)


def cruiser_light_bar(car, y):
    b, M = car.body, car.M
    g = car._gh()
    z = g["rz"]
    wd = 2.0 * g["xr"] - 0.20
    red = G.mat("M_Siren_Red", G.pal("SirenRed"), rough=0.2)
    blue = G.mat("M_Siren_Blue", G.pal("SirenBlue"), rough=0.2)
    b.box((wd + 0.04, 0.25, 0.03), (0, y, z + 0.048), M["trim"])
    b.box((0.08, 0.17, 0.07), (wd * 0.40, y, z + 0.012), M["trim"], mirror=True)
    seg = (wd - 0.16) / 2.0
    for sx, m in ((-1.0, red), (1.0, blue)):
        # two lens pods per side with a dark divider
        b.box((seg * 0.56, 0.21, 0.09), (sx * (0.08 + seg * 0.72), y, z + 0.108), m, bevel=0.024)
        b.box((seg * 0.40, 0.19, 0.08), (sx * (0.08 + seg * 0.21), y, z + 0.104), m)
        b.box((0.02, 0.22, 0.095), (sx * (0.08 + seg * 0.425), y, z + 0.106), M["trim"])
        # low end stub only: the full-height end caps hid the lenses from the side (the bar read as a
        # black block in profile); now the red / blue end faces show above it
        b.box((0.03, 0.23, 0.045), (sx * (0.08 + seg + 0.012), y, z + 0.078), M["trim"])
    b.box((0.16, 0.18, 0.075), (0, y, z + 0.10), M["chrome"], bevel=0.012)
    b.box((0.10, 0.02, 0.04), (0.0, y + 0.092, z + 0.10), M["head"])                     # takedown light
    car.siren_pos = (0.0, y, z + 0.13)
    return wd


def cruiser_spotlight(car, side=-1.0):
    """A-pillar spot lamp (driver side)."""
    b, M = car.body, car.M
    g = car._gh()
    t = 0.22
    x = g["xc"] + (g["xr"] - g["xc"]) * t
    y = g["cy"] + (g["rf"] - g["cy"]) * t - 0.02
    z = g["zc"] + (g["zR"] - g["zc"]) * t
    xo = x + 0.115
    bar_between(b, (side * (x - 0.01), y, z), (side * xo, y + 0.01, z + 0.01), 0.012, M["chrome"], segments=6)
    b.cyl(0.068, 0.10, (side * xo, y + 0.03, z + 0.012), M["chrome"], axis='Y', segments=8, radius2=0.060)
    b.cyl(0.056, 0.014, (side * xo, y + 0.084, z + 0.012), M["head"], axis='Y', segments=8)
    b.box((0.016, 0.03, 0.05), (side * xo, y - 0.02, z - 0.06), M["trim"])


def build_police_cruiser():
    car = new_car(CRUISER)
    blue = G.pmat("PoliceBlue")
    white = G.pmat("PoliceWhite")
    gold = G.pmat("BadgeGold")
    car.M["paint"] = blue          # exported as M_Paint_Primary (see MATERIAL_ALIAS)
    car.M["paint2"] = white
    p, M, b = car.p, car.M, car.body
    car.skin()
    before = set(b.bm.faces)
    car.greenhouse()
    recolor(b, blue, white, new_faces(b, before))        # pillars white like the roof and doors
    car.interior()
    car.bays()
    fascias(car)
    car.details()
    car.closures()
    yf, yr = car.y_f, car.y_r
    g = car._gh()
    # --- livery: white doors, shield on the front doors, HBPD on the rear doors, gold pinstripe
    for tag, ya, yb in car.doors:
        for sfx, side in (("L", -1.0), ("R", 1.0)):
            mb = car.mb("Door_%s%s" % (tag, sfx))
            recolor(mb, blue, white)
            ym = (ya + yb) / 2.0
            zsw = p["swage_z"]
            zcr = car.zt(ym) - p["crease_drop"]
            zmid = (zsw + 0.019 + zcr - 0.030) / 2.0          # middle of the band between rub strip and pinstripe
            zlow = (p["rocker_z"] + p["seam"] + zsw - 0.019) / 2.0   # middle of the band below the rub strip
            if tag == "F":
                shield(mb, car, side, ym - 0.06, (zsw + zcr) / 2.0 + 0.005, 0.23, gold, blue, gold, white)
                side_text(mb, car, side, "POLICE", ym - 0.01, zlow - 0.075, 0.15, blue, stroke=0.2)
            else:
                side_text(mb, car, side, "HBPD", ym + 0.075, zmid - 0.0775, 0.155, blue, stroke=0.2)   # clear of the handle
    for side in (-1.0, 1.0):
        side_band(car, side, p["doors"][1][1] + 0.01, p["doors"][0][2] - 0.01,
                  lambda y: car.zt(y) - p["crease_drop"] - 0.030, lambda y: car.zt(y) - p["crease_drop"] - 0.012, gold, off=0.005)
    # unit number on the roof (air unit can read it) and on the front fenders
    rz = g["rz"]

    def roof_map(u, v):
        return (u, (g["rf"] + g["rr"]) / 2.0 - 0.42 + v, rz + 0.004)
    emit_text(b, "07", 0.34, blue, roof_map, (0, 0, 1), stroke=0.2)
    # --- hardware
    cruiser_light_bar(car, (g["rf"] + g["rr"]) / 2.0 + 0.16)
    cruiser_spotlight(car, -1.0)
    bull_bar(car, b, M["trim"], "push")
    partition(car, p["seat_f_y"] - 0.47)
    # trunk antennas, blacked-out grille surround, rear deck lights
    b.cyl(0.008, 0.55, (0.42, -2.02, car.zt(-2.02) + 0.30), M["trim"], axis='Z', segments=4, rot=(radians(-10), 0, 0))
    gx, gz, gh = car.grille_box
    b.box((2 * gx - 0.04, 0.02, gh - 0.03), (0, yf + 0.03, gz - 0.005), M["under"])
    for i in range(5):
        b.box((0.014, 0.012, gh - 0.03), ((i - 2) * (2 * gx - 0.08) / 4.0, yf + 0.042, gz - 0.005), M["trim"])
    red = G.mat("M_Siren_Red", G.pal("SirenRed"), rough=0.2)
    blu = G.mat("M_Siren_Blue", G.pal("SirenBlue"), rough=0.2)
    b.box((0.12, 0.03, 0.04), (-0.24, yf + 0.045, gz - 0.005), red)        # grille strobes
    b.box((0.12, 0.03, 0.04), (0.24, yf + 0.045, gz - 0.005), blu)
    wheels(car)
    car.collision()
    car.lod()
    # LOD: white doors + simple light bar so the silhouette survives at distance
    lod_recolor_sides(car, white, p["doors"][1][1] - 0.08, p["doors"][0][2] + 0.06, zmin=p["rocker_z"])
    lb = car.mb("Body_LOD1")
    ybar = (g["rf"] + g["rr"]) / 2.0 + 0.16
    lb.box((0.52, 0.20, 0.10), (-0.30, ybar, rz + 0.07), red)
    lb.box((0.52, 0.20, 0.10), (0.30, ybar, rz + 0.07), blu)
    car.mods()
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# TAXI  'taxi' - 4.74 m purpose-built cab, 1.74 m roof, checker band, lit roof sign
# ------------------------------------------------------------------------------------------------
TAXI = _p(
    name="taxi", width=1.84, height=1.74,
    axle_f=1.46, axle_r=-1.42, wheel_r=0.34, wheel_w=0.23, track=1.56, wheel_style="b_cap",
    top=[(-2.30, 0.98), (-1.88, 1.05), (1.04, 1.03), (1.98, 0.97), (2.30, 0.87)],
    bottom=[(-2.30, 0.38), (-1.94, 0.25), (1.94, 0.23), (2.30, 0.32)],
    plan=[(-2.30, 0.89), (-2.08, 0.975), (-1.84, 1.0), (1.86, 1.0), (2.12, 0.965), (2.30, 0.885)],
    crown=0.03, crown_w=0.32, shoulder_inset=0.07, crease_drop=0.10, swage_z=0.64,
    cowl_y=1.04, roof_f=0.66, roof_r=-1.62, deck_y=-1.88, c_pillar=(0.24, 0.18), tumble=0.09, a_pillar=0.12,
    roof_t=0.06, pillars_extra=[(-1.14, -0.98, -1.12, -1.0)],
    doors=[("F", -0.02, 0.98), ("R", -0.98, -0.02)],
    seat_f_y=0.06, seat_r_y=-1.04, seat_color="Khaki",
    head=None, grille=None, tail=dict(w=0.16, h=0.26, inset=0.02, z=None),
    bumper_f=dict(h=0.20, out=0.07, wrap=0.36), bumper_r=dict(h=0.20, out=0.07, wrap=0.36),
    exhaust=dict(x=-0.50, r=0.034), mods=[],
)


def taxi_sign(car, y):
    """Roof sign 'TaxiSign' (own object, emissive P_NeonYellow, origin at its foot on the roof)."""
    M = car.M
    mb = car.mb("TaxiSign")
    g = car._gh()
    z = g["rz"] - 0.004
    neon = G.pmat("NeonYellow", emit_strength=3.0)
    blk = G.pmat("Black")
    hw, z0, z1 = 0.30, z + 0.04, z + 0.215
    mb.box((2 * hw + 0.06, 0.20, 0.04), (0, y, z + 0.022), M["trim"], bevel=0.01)
    prof = [(y - 0.085, z0), (y + 0.085, z0), (y + 0.055, z1), (y - 0.055, z1)]
    mb.prism(prof, -hw, hw, neon, axis='X')
    for sx in (-1.0, 1.0):
        mb.box((0.03, 0.19, z1 - z0 + 0.012), (sx * (hw + 0.012), y, (z0 + z1) / 2.0 + 0.004), blk)
    mb.box((2 * hw + 0.05, 0.12, 0.014), (0, y, z1 + 0.005), blk)
    th = 0.105
    for face in (1.0, -1.0):            # front (+Y) and rear (-Y) lettering
        def mapf(u, v, face=face):
            zz = z0 + 0.033 + v
            t = (zz - z0) / (z1 - z0)
            yy = y + face * (0.085 - 0.03 * t + 0.004)
            return (-face * u, yy, zz)
        emit_text(mb, "TAXI", th, blk, mapf, (0, face, 0.2), stroke=0.2)
    car.origins["TaxiSign"] = ((0.0, y, g["rz"]), None)
    return (0.0, y, (z0 + z1) / 2.0)


def build_taxi():
    car = new_car(TAXI)
    yellow = G.pmat("TaxiYellow", rough=0.35, metal=0.1)
    car.M["paint"] = yellow        # exported as M_Paint_Primary (see MATERIAL_ALIAS)
    p, M, b = car.p, car.M, car.body
    blk = G.pmat("Black")
    car.skin()
    car.greenhouse()
    car.interior()
    car.bays()
    fascias(car, front_mat=M["chrome"], rear_mat=M["chrome"])
    car.details()
    car.closures()
    yf, yr = car.y_f, car.y_r
    g = car._gh()
    wc = car.w(yf)
    nose = car.zt(yf)
    # --- face: upright chrome grille, round lamps on dark panels, amber park lamps
    gz, gh, gx = nose - 0.165, 0.25, 0.30
    b.box((2 * gx + 0.05, 0.05, gh + 0.05), (0, yf + 0.012, gz), M["chrome"], bevel=0.014)
    b.box((2 * gx - 0.02, 0.02, gh - 0.02), (0, yf + 0.034, gz), M["under"])
    for i in range(6):
        b.box((0.024, 0.016, gh - 0.02), ((i - 2.5) * (2 * gx - 0.08) / 5.0, yf + 0.045, gz), M["chrome"])
    b.box((0.10, 0.02, 0.07), (0, yf + 0.058, gz + gh / 2.0 + 0.012), yellow, bevel=0.012)
    hx, hz = wc - 0.235, nose - 0.15
    b.box((0.34, 0.04, 0.23), (hx, yf + 0.0, hz - 0.01), M["trim"], mirror=True)
    b.cyl(0.098, 0.05, (hx + 0.045, yf + 0.03, hz + 0.005), M["chrome"], axis='Y', segments=12, mirror=True)
    b.cyl(0.082, 0.02, (hx + 0.045, yf + 0.052, hz + 0.005), M["head"], axis='Y', segments=12, mirror=True)
    b.cyl(0.050, 0.035, (hx - 0.105, yf + 0.03, hz - 0.045), M["chrome"], axis='Y', segments=8, mirror=True)
    b.cyl(0.040, 0.02, (hx - 0.105, yf + 0.044, hz - 0.045), M["indicator"], axis='Y', segments=8, mirror=True)
    car.head_pos = (hx + 0.045, yf + 0.07, hz + 0.005)
    # bumper over-riders
    z0, z1 = car.bumper_f_z
    of = p["bumper_f"]["out"]
    b.box((0.06, 0.06, 0.16), (0.36, yf + of + 0.02, (z0 + z1) / 2.0 + 0.01), M["under"], mirror=True)
    zr0, zr1 = car.bumper_r_z
    orr = p["bumper_r"]["out"]
    b.box((0.06, 0.06, 0.16), (0.40, yr - orr - 0.02, (zr0 + zr1) / 2.0 + 0.01), M["under"], mirror=True)
    # --- livery: checker band under the shoulder crease, door numbers
    ztop = lambda y: car.zt(y) - p["crease_drop"] - 0.012
    checker_band(car, -2.02, 1.90, ztop, sq_y=0.07, sq_z=0.06, rows=2, light=G.pmat("White"), dark=blk)
    # --- roof sign, partition, running-board style sill trim, luggage rail on the short deck
    sign_pos = taxi_sign(car, g["rf"] - 0.42)
    partition(car, p["seat_f_y"] - 0.47)
    # door lettering below the rub strip: big TAXI on the front doors, cab number on the rear doors
    zlow = (p["rocker_z"] + p["seam"] + p["swage_z"] - 0.019) / 2.0
    for tag, ya, yb in car.doors:
        for sfx, side in (("L", -1.0), ("R", 1.0)):
            mb = car.mb("Door_%s%s" % (tag, sfx))
            if tag == "F":
                side_text(mb, car, side, "TAXI", (ya + yb) / 2.0 - 0.02, zlow - 0.085, 0.17, blk, stroke=0.2)
            else:
                side_text(mb, car, side, "107", (ya + yb) / 2.0, zlow - 0.065, 0.13, blk, stroke=0.2)
    wheels(car)
    car.collision()
    car.lod()
    lb = car.mb("Body_LOD1")
    lb.box((0.62, 0.17, 0.18), (sign_pos[0], sign_pos[1], sign_pos[2]), G.pmat("NeonYellow", emit_strength=3.0))
    lb.box((0.18, 0.04, 0.18), (car.head_pos[0], yf, car.head_pos[2]), M["head"], mirror=True)
    lb.box((2 * gx, 0.04, gh), (0, yf, gz), M["chrome"])
    for side in (-1.0, 1.0):       # coarse band: one white strip with 14 dark blocks
        for i in range(14):
            ya = -1.9 + i * (3.6 / 14.0)
            pts = [(side * (car.side_x(yy, zz) + 0.012), yy, zz) for yy, zz in
                   ((ya, ztop(ya) - 0.12), (ya + 3.6 / 14.0, ztop(ya) - 0.12), (ya + 3.6 / 14.0, ztop(ya)), (ya, ztop(ya)))]
            lb.face(pts, blk if i % 2 else G.pmat("White"), want=(side, 0, 0))
    car.mods()
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# registry, QA, export
# ------------------------------------------------------------------------------------------------
BUILDERS = {"suv": build_suv, "pickup": build_pickup, "van": build_van,
            "police_cruiser": build_police_cruiser, "taxi": build_taxi}
ORDER = ["suv", "pickup", "van", "police_cruiser", "taxi"]

_BASE = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel", "Hood", "Door_FL", "Door_FR",
         "Glass_Windshield", "Glass_Rear", "Glass_L", "Glass_R", "Seat_Driver", "Seat_Passenger_1", "Exit_Driver",
         "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L", "Light_Tail_R", "Exhaust", "Engine",
         "Col_Body", "Col_Cabin", "Body_LOD1"]
_REAR = ["Door_RL", "Door_RR", "Seat_Passenger_2", "Seat_Passenger_3", "Exit_Passenger_2", "Exit_Passenger_3"]
CONTRACT = {
    "suv": _BASE + _REAR + list(K.FULL_MODS),
    "pickup": _BASE + _REAR + list(K.FULL_MODS) + ["Tailgate"],
    "van": _BASE + ["Door_RearL", "Door_RearR", "Glass_Rear_R"],
    "police_cruiser": _BASE + _REAR + ["Trunk", "Siren"],
    "taxi": _BASE + _REAR + ["Trunk", "TaxiSign"],
}


def build(name):
    car = BUILDERS[name]()
    car.report()
    check(name)
    return car


def check(name):
    root = bpy.data.objects.get(name)
    have = {K.short_name(o) for o in root.children_recursive}
    missing = [n for n in CONTRACT[name] if n not in have]
    bad = sorted(o.name for o in root.children_recursive if not o.name.startswith(name + K.NAME_SEP))
    mats = set()
    for o in root.children_recursive:
        if o.type == 'MESH':
            used = {p.material_index for p in o.data.polygons}
            mats.update(m.name for i, m in enumerate(o.data.materials) if m is not None and i in used)
    print("CONTRACT %s: %d children, missing=%s, badly_named=%s" % (name, len(have), missing, bad))
    print("MATERIALS %s: %s" % (name, sorted(mats)))
    return missing, bad


def shots(name, suffix="", views=VIEWS, res=420):
    return G.preview(name, "veh_" + name + suffix, views=views, res=res)


def shots_tinted(names, out_name, tints, views=("three_quarter", "rear_quarter"), res=420):
    """Preview with M_Paint_Primary temporarily replaced by palette paints on OUR objects only
    (tints = {asset: palette key}); everything is restored afterwards."""
    if isinstance(names, str):
        names = [names]
    base = bpy.data.materials.get("M_Paint_Primary")
    saved = []
    try:
        for nm in names:
            key = tints.get(nm)
            if not key:
                continue
            tint = G.pmat(key, rough=0.35, metal=0.1)
            done = set()
            for o in bpy.data.objects[nm].children_recursive:
                if o.type != 'MESH' or o.data.name in done:
                    continue
                done.add(o.data.name)
                for i, m in enumerate(o.data.materials):
                    if m == base:
                        o.data.materials[i] = tint
                        saved.append((o.data, i))
        return G.preview(names, out_name, views=views, res=res)
    finally:
        for me, i in saved:
            me.materials[i] = base


def patch_glb_materials(path, rename=None, pbr=None):
    """Rewrite material names (and optional pbr factors) in the JSON chunk of a GLB."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _total = struct.unpack_from("<4sII", data, 0)
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    if magic != b"glTF" or ctype != b"JSON":
        raise RuntimeError("not a GLB: %s" % path)
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    rest = data[20 + clen:]
    names = [m.get("name", "") for m in js.get("materials", [])]
    n = 0
    for m in js.get("materials", []):
        nm = m.get("name", "")
        if rename and nm in rename:
            if rename[nm] in names:
                raise RuntimeError("%s: cannot rename %s, %s already exists in the file" % (path, nm, rename[nm]))
            m["name"] = rename[nm]
            n += 1
        if pbr and m.get("name") in pbr and rename and nm in rename:
            m.setdefault("pbrMetallicRoughness", {}).update(pbr[m["name"]])
    out = json.dumps(js, separators=(",", ":")).encode("utf-8")
    out += b" " * ((4 - len(out) % 4) % 4)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", version, 12 + 8 + len(out) + len(rest)))
        f.write(struct.pack("<I4s", len(out), b"JSON"))
        f.write(out)
        f.write(rest)
    os.replace(tmp, path)
    print("GLB_MATERIALS: %d renamed in %s -> %s" % (n, os.path.basename(path), sorted(m.get("name", "") for m in js.get("materials", []))))
    return n


def export(name, quiet=True):
    """validate + export vehicles/<name>.glb (clean node names, livery paint alias)."""
    import contextlib
    import io
    import logging
    res = G.validate(name, max_tris=9800)
    buf = io.StringIO()
    old_disable = logging.root.manager.disable
    try:
        if quiet:
            logging.disable(logging.INFO)          # the glTF exporter logs every primitive
        with contextlib.redirect_stdout(buf if quiet else __import__("sys").stdout):
            path = K.export_glb(name, "vehicles/%s.glb" % name)
    finally:
        logging.disable(old_disable)
    for line in buf.getvalue().splitlines():
        if line.startswith(("EXPORTED", "GLB_NAMES")):
            print(line)
    alias = MATERIAL_ALIAS.get(name)
    patch_glb_materials(path, alias, PAINT_PBR if alias else None)
    return res


def build_all():
    return {n: build(n) for n in ORDER}


def export_all():
    return {n: export(n) for n in ORDER}


def group_preview(out_name="veh_cars_b_group", views=("three_quarter", "side", "front", "top"), res=640):
    """All five side by side: temporarily lines the roots up 3 m apart, then restores the slots."""
    roots = [bpy.data.objects[n] for n in ORDER]
    saved = [r.location.copy() for r in roots]
    try:
        base = G.slot("cars", SLOTS["suv"])
        for i, r in enumerate(roots):
            r.location = (base.x + i * 3.0, base.y, base.z)
        bpy.context.view_layer.update()
        return G.preview(ORDER, out_name, views=views, res=res)
    finally:
        for r, loc in zip(roots, saved):
            r.location = loc
        bpy.context.view_layer.update()
