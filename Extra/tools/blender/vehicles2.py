# Two-wheelers, boat, helicopters and airplanes for Cinder Bay. Executed in Blender through MCP.
import bpy, math
from mathutils import Vector
from fable_lib import *
from vehicles import wheel_geo, build_wheel


def _col_box(aid, coll, root, idx, size, loc, taper=None):
    mb = MB()
    mb.box(size, loc=loc, taper=taper)
    o = mb.finish("%s_COL_%d" % (aid, idx), coll, parent=root)
    o.display_type = 'WIRE'
    return o


def _steering_wheel(aid, coll, root, loc, tilt=-22):
    sw = MB()
    sw.lathe([(-0.018, 0.165), (0, 0.185), (0.018, 0.165), (0, 0.145)], axis='Y', segs=12, m="Trim", ring=True)
    sw.box((0.30, 0.02, 0.035), m="Trim")
    sw.cyl(0.05, 0.05, axis='Y', segs=8, m="Trim")
    sw.cyl(0.025, 0.30, loc=(0, 0.15, 0), axis='Y', segs=6, m="Interior")
    return sw.finish(aid + "_SteeringWheel", coll, smooth=40, parent=root, loc=loc, rot=(math.radians(tilt), 0, 0))


def _seat(mb, x, y, z, recl=0.2, m="Seat"):
    mb.box((0.46, 0.48, 0.12), loc=(x, y + 0.05, z), m=m, bevel=0.03)
    mb.box((0.44, 0.10, 0.56), loc=(x, y - 0.24 - 0.14 * recl, z + 0.30), m=m, rot=(-recl, 0, 0), bevel=0.03)


def build_motorcycle(aid="motorcycle", cell=(0, 0, 0), color="#c9302a"):
    coll = col("Vehicles/Motorcycles")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.5)
    paint = mat("CarPaint_" + aid, color, rough=0.3, metal=0.5)
    wr, ww = 0.31, 0.14
    yf, yr = 0.74, -0.70
    head = Vector((0, 0.50, 0.90))

    def body_geo(mb, lod):
        mb.box((0.30, 0.44, 0.30), loc=(0, 0.04, 0.44), m="DarkSteel", bevel=0.04 if lod == 0 else 0)
        mb.box((0.26, 0.22, 0.20), loc=(0, 0.12, 0.64), m="Steel", bevel=0.03 if lod == 0 else 0)
        mb.tube(head, (0, -0.25, 0.72), 0.03, "DarkSteel")
        mb.tube(head + Vector((0, -0.03, -0.1)), (0, 0.27, 0.36), 0.028, "DarkSteel")
        for s in (1, -1):
            mb.tube((s * 0.10, -0.12, 0.42), (s * 0.10, yr, wr), 0.028, "DarkSteel")
            mb.tube((s * 0.10, -0.50, 0.74), (s * 0.10, yr, wr), 0.018, "Steel")
        mb.ellipse_loft([(0.44, 0, 0.84, 0.09, 0.06), (0.30, 0, 0.89, 0.17, 0.12), (0.05, 0, 0.89, 0.18, 0.12),
                         (-0.20, 0, 0.83, 0.13, 0.07)], segs=8, m=paint)
        mb.box((0.28, 0.60, 0.09), loc=(0, -0.44, 0.80), m="Seat", bevel=0.03 if lod == 0 else 0)
        mb.box((0.22, 0.32, 0.10), loc=(0, -0.82, 0.85), m=paint, taper=(0.6, 0.8), bevel=0.02 if lod == 0 else 0)
        mb.box((0.12, 0.03, 0.045), loc=(0, -0.985, 0.85), m="LightTail")
        mb.box((0.17, 0.52, 0.025), loc=(0, -0.80, 0.68), m="Trim", rot=(math.radians(12), 0, 0))
        mb.box((0.18, 0.015, 0.10), loc=(0, -1.04, 0.60), m="Plate")
        mb.tube((0.15, 0.10, 0.30), (0.19, -0.42, 0.36), 0.035, "Chrome")
        mb.tube((0.19, -0.42, 0.36), (0.22, -0.92, 0.48), 0.06, "Chrome", segs=8)
        mb.box((0.36, 0.05, 0.03), loc=(0, 0.02, 0.30), m="Trim")

    def steer_geo(mb, lod):
        for s in (1, -1):
            mb.tube((s * 0.09, 0.47, 0.96), (s * 0.09, yf, wr), 0.026, "Steel")
        mb.box((0.24, 0.07, 0.04), loc=(0, 0.485, 0.93), m="DarkSteel")
        mb.tube((-0.34, 0.44, 1.02), (0.34, 0.44, 1.02), 0.016, "Trim")
        for s in (1, -1):
            mb.tube((s * 0.08, 0.47, 0.95), (s * 0.08, 0.44, 1.02), 0.014, "Trim", segs=4)
            mb.tube((s * 0.24, 0.44, 1.02), (s * 0.35, 0.44, 1.02), 0.022, "Rubber")
            if lod == 0:
                mb.tube((s * 0.27, 0.45, 1.02), (s * 0.31, 0.47, 1.16), 0.006, "Trim", segs=4)
                mb.box((0.09, 0.015, 0.055), loc=(s * 0.32, 0.47, 1.18), m="Trim")
        mb.cyl(0.095, 0.11, loc=(0, 0.60, 0.86), axis='Y', segs=10, m="Trim")
        mb.cyl(0.078, 0.02, loc=(0, 0.662, 0.86), axis='Y', segs=10, m="LightHead")
        mb.box((0.16, 0.42, 0.025), loc=(0, yf + 0.02, wr * 2 + 0.05), m=paint, rot=(math.radians(-6), 0, 0))

    b = MB()
    body_geo(b, 0)
    b.finish(aid + "_Body", coll, smooth=38, parent=root)
    s = MB()
    steer_geo(s, 0)
    steer = s.finish(aid + "_Steer", coll, smooth=38, parent=root, origin=tuple(head))
    wf = build_wheel(aid + "_Wheel_F", coll, wr, ww * 0.85, 0, parent=steer, loc=(0, yf - head.y, wr - head.z))
    build_wheel(aid + "_Wheel_R", coll, wr, ww, 0, parent=root, loc=(0, yr, wr))
    empty(aid + "_Seat_0", coll, loc=(0, -0.30, 0.86), parent=root, size=0.15)
    empty(aid + "_Seat_1", coll, loc=(0, -0.68, 0.90), parent=root, size=0.15)
    empty(aid + "_P_Head_L", coll, loc=(0, 0.72, 0.86), parent=root, size=0.1)
    empty(aid + "_P_Tail_L", coll, loc=(0, -1.02, 0.85), parent=root, size=0.1)
    empty(aid + "_P_Exhaust", coll, loc=(0.22, -0.98, 0.48), parent=root, size=0.1)
    empty(aid + "_P_Engine", coll, loc=(0, 0.1, 0.7), parent=root, size=0.1)
    _col_box(aid, coll, root, 0, (0.40, 1.9, 0.62), (0, 0.0, 0.62))
    l = MB()
    body_geo(l, 1)
    steer_geo(l, 1)
    wheel_geo(l, wr, ww, loc=(0, yf, wr), simple=True)
    wheel_geo(l, wr, ww, loc=(0, yr, wr), simple=True)
    o = l.finish(aid + "_LOD1", coll, smooth=38, parent=root)
    o.hide_set(True)
    return root


def build_bicycle(aid="bicycle", cell=(0, 0, 0), color="#2f9c95"):
    coll = col("Vehicles/Motorcycles")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.5)
    paint = mat("CarPaint_" + aid, color, rough=0.4, metal=0.4)
    wr, ww = 0.34, 0.05
    yf, yr = 0.60, -0.48
    bb = Vector((0, 0.0, 0.30))
    st = Vector((0, -0.14, 0.80))
    ht = Vector((0, 0.40, 0.88))
    hb = Vector((0, 0.44, 0.72))

    def body_geo(mb):
        r = 0.018
        mb.tube(bb, st, r, paint)
        mb.tube(st, ht, r, paint)
        mb.tube(bb, hb, r * 1.2, paint)
        mb.tube(ht, hb, r * 1.2, paint)
        for s in (1, -1):
            mb.tube(bb + Vector((s * 0.03, 0, 0)), (s * 0.06, yr, wr), r * 0.7, paint, segs=4)
            mb.tube(st + Vector((s * 0.02, 0, -0.06)), (s * 0.06, yr, wr), r * 0.6, paint, segs=4)
        mb.tube(st, st + Vector((0, -0.03, 0.10)), 0.014, "Steel")
        mb.box((0.14, 0.27, 0.045), loc=(0, -0.19, 0.92), m="Trim", taper=(1.0, 1.0), bevel=0.015)
        mb.cyl(0.10, 0.012, loc=(0.05, 0, 0.30), axis='X', segs=10, m="Steel")

    def steer_geo(mb):
        for s in (1, -1):
            mb.tube(hb + Vector((s * 0.05, 0, 0)), (s * 0.05, yf, wr), 0.014, "Steel", segs=4)
        mb.tube(hb, hb + Vector((0.0, 0, 0.0)) + Vector((0.10, 0, 0)), 0.012, "Steel", segs=4)
        mb.tube(hb + Vector((-0.05, 0, 0)), hb + Vector((0.05, 0, 0)), 0.014, "Steel", segs=4)
        mb.tube(ht, ht + Vector((0, 0.02, 0.12)), 0.014, "Steel")
        mb.tube((-0.27, 0.42, 1.00), (0.27, 0.42, 1.00), 0.012, "Steel")
        for s in (1, -1):
            mb.tube((s * 0.19, 0.42, 1.00), (s * 0.28, 0.42, 1.00), 0.017, "Rubber")
    b = MB()
    body_geo(b)
    b.finish(aid + "_Body", coll, smooth=38, parent=root)
    cr = MB()
    for s in (1, -1):
        cr.box((0.02, 0.03, 0.17), loc=(s * 0.08, 0, s * 0.085), m="Steel")
        cr.box((0.09, 0.06, 0.02), loc=(s * 0.13, 0, s * 0.17), m="Trim")
    cr.cyl(0.02, 0.16, axis='X', segs=6, m="Steel")
    cr.finish(aid + "_Crank", coll, parent=root, loc=tuple(bb))
    s = MB()
    steer_geo(s)
    steer = s.finish(aid + "_Steer", coll, smooth=38, parent=root, origin=tuple(ht))
    build_wheel(aid + "_Wheel_F", coll, wr, ww, 3, parent=steer, loc=(0, yf - ht.y, wr - ht.z))
    build_wheel(aid + "_Wheel_R", coll, wr, ww, 3, parent=root, loc=(0, yr, wr))
    empty(aid + "_Seat_0", coll, loc=(0, -0.17, 0.97), parent=root, size=0.15)
    _col_box(aid, coll, root, 0, (0.30, 1.6, 0.55), (0, 0.05, 0.60))
    return root


def build_boat(aid="speedboat", cell=(0, 0, 0), color="#2a67c9", police=False):
    coll = col("Vehicles/Boats")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.6)
    paint = M("PoliceBlack") if police else mat("CarPaint_" + aid, color, rough=0.3, metal=0.3)
    dz = -0.30
    S = [  # y, half beam, keel z, chine z, gunwale z, cockpit
        (3.20, 0.03, 0.86, 0.90, 1.00, False), (2.60, 0.55, 0.30, 0.62, 1.00, False),
        (1.60, 0.95, 0.05, 0.45, 0.98, False), (0.62, 1.08, -0.10, 0.36, 0.95, False),
        (0.60, 1.08, -0.10, 0.36, 0.95, True), (-2.30, 1.10, -0.15, 0.32, 0.92, True),
        (-2.302, 1.10, -0.15, 0.32, 0.92, False), (-3.20, 1.05, -0.12, 0.34, 0.92, False)]
    zf = 0.40 + dz

    def sec(st):
        y, wg, zk, zc, zg, ck = st
        zk, zc, zg = zk + dz, zc + dz, zg + dz
        if ck:
            R = [(wg * 0.86, zc), (wg, zg), (wg - 0.10, zg), (wg - 0.14, zf)]
            c = zf
        else:
            R = [(wg * 0.86, zc), (wg, zg), (wg - 0.10, zg + 0.01), (wg * 0.5, zg + 0.04)]
            c = zg + 0.06
        return [Vector((0, y, zk))] + [Vector((x, y, z)) for x, z in R] + [Vector((0, y, c))] + [Vector((-x, y, z)) for x, z in reversed(R)]

    def mfn(i, j):
        if i < 0 or i >= len(S) - 1:
            return "BoatWhite"
        if j in (0, 9):
            return "BoatWhite"
        if j in (1, 8):
            return paint
        ck = S[i][5] or S[i + 1][5]
        if ck and j in (3, 6):
            return "BoatWhite"
        if ck and j in (4, 5):
            return "Wood"
        return "BoatWhite"

    def hull(mb, lod):
        mb.loft([sec(s) for s in S], mfn)
        zg = 0.95 + dz
        mb.framed([(-0.88, 0.62, zg), (0.88, 0.62, zg), (0.76, 0.30, zg + 0.52), (-0.76, 0.30, zg + 0.52)], "Chrome", "Glass", 0.04, outward=(0, 1, 0.5))
        for s in (1, -1):
            mb.framed([(s * 0.88, 0.62, zg), (s * 0.98, -0.10, zg), (s * 0.80, -0.10, zg + 0.40), (s * 0.76, 0.30, zg + 0.52)], "Chrome", "Glass", 0.04, outward=(s, 0.3, 0.3))
        mb.box((1.80, 0.40, 0.42), loc=(0, 0.38, zf + 0.21), m="BoatWhite", bevel=0.05 if lod == 0 else 0)
        for x in (-0.45, 0.45):
            _seat(mb, x, -0.30, zf + 0.30, 0.15, "Seat")
            mb.box((0.30, 0.30, 0.24), loc=(x, -0.25, zf + 0.12), m="BoatWhite")
        mb.box((1.80, 0.45, 0.30), loc=(0, -2.02, zf + 0.15), m="Seat", bevel=0.04 if lod == 0 else 0)
        mb.box((1.80, 0.12, 0.40), loc=(0, -2.24, zf + 0.42), m="Seat", bevel=0.03 if lod == 0 else 0)
        if lod == 0:
            for s in (1, -1):
                mb.tube((s * 0.50, 2.60, zg + 0.02), (s * 0.50, 2.60, zg + 0.22), 0.015, "Chrome", segs=4)
                mb.tube((s * 0.88, 1.60, zg + 0.02), (s * 0.88, 1.60, zg + 0.22), 0.015, "Chrome", segs=4)
                mb.tube((s * 0.50, 2.60, zg + 0.22), (s * 0.88, 1.60, zg + 0.22), 0.015, "Chrome", segs=4)
                mb.box((0.05, 0.12, 0.04), loc=(s * 0.98, -2.6, zg + 0.03), m="Chrome")
            mb.tube((-0.50, 2.60, zg + 0.22), (0.50, 2.60, zg + 0.22), 0.015, "Chrome", segs=4)
            mb.box((0.04, 0.06, 0.05), loc=(-0.2, 3.05, zg + 0.05), m="LightBarRed")
            mb.box((0.04, 0.06, 0.05), loc=(0.2, 3.05, zg + 0.05), m="TrafficGreen")
        if police:
            mb.tube((-0.7, -0.2, zg + 0.4), (-0.7, -0.2, zg + 1.25), 0.03, "DarkSteel")
            mb.tube((0.7, -0.2, zg + 0.4), (0.7, -0.2, zg + 1.25), 0.03, "DarkSteel")
            mb.box((1.6, 0.5, 0.05), loc=(0, -0.2, zg + 1.27), m="PoliceWhite")
            mb.box((0.5, 0.2, 0.09), loc=(-0.3, -0.2, zg + 1.34), m="LightBarRed")
            mb.box((0.5, 0.2, 0.09), loc=(0.3, -0.2, zg + 1.34), m="LightBarBlue")
            for s in (1, -1):
                mb.box((0.012, 2.4, 0.16), loc=(s * 1.085, -0.6, 0.38), m="PoliceWhite")

    h = MB()
    hull(h, 0)
    h.finish(aid + "_Body", coll, smooth=35, parent=root)
    m = MB()
    m.box((0.38, 0.55, 0.42), loc=(0, -0.05, 0.25), m="DarkSteel", bevel=0.06)
    m.box((0.40, 0.30, 0.06), loc=(0, -0.02, 0.12), m=paint)
    m.box((0.14, 0.22, 0.95), loc=(0, -0.10, -0.42), m="DarkSteel", bevel=0.02)
    m.box((0.03, 0.34, 0.26), loc=(0, -0.18, -0.92), m="DarkSteel")
    m.cyl(0.16, 0.05, loc=(0, -0.26, -0.80), axis='Y', segs=8, m="Steel")
    m.finish(aid + "_Motor", coll, smooth=35, parent=root, loc=(0, -3.28, 0.92 + dz))
    _steering_wheel(aid, coll, root, (-0.45, 0.14, zf + 0.50), -30)
    empty(aid + "_Seat_0", coll, loc=(-0.45, -0.30, zf + 0.40), parent=root, size=0.15)
    empty(aid + "_Seat_1", coll, loc=(0.45, -0.30, zf + 0.40), parent=root, size=0.15)
    empty(aid + "_Seat_2", coll, loc=(-0.45, -2.0, zf + 0.36), parent=root, size=0.15)
    empty(aid + "_Seat_3", coll, loc=(0.45, -2.0, zf + 0.36), parent=root, size=0.15)
    empty(aid + "_P_Wake", coll, loc=(0, -3.4, 0.0), parent=root, size=0.1)
    empty(aid + "_P_Engine", coll, loc=(0, -3.3, 1.0), parent=root, size=0.1)
    _col_box(aid, coll, root, 0, (2.1, 5.0, 0.95), (0, -0.7, 0.20))
    _col_box(aid, coll, root, 1, (1.6, 1.6, 0.6), (0, 2.3, 0.38), taper=(0.3, 0.8))
    return root


def build_heli(aid="helicopter", cell=(0, 0, 0), color="#e9792a", police=False):
    coll = col("Vehicles/Helicopters")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.8)
    paint = M("PoliceBlack") if police else mat("CarPaint_" + aid, color, rough=0.3, metal=0.4)
    paint2 = M("PoliceWhite") if police else mat("CarPaint2_" + aid, "#f1efe6", rough=0.4, metal=0.2)
    segs = 12
    F = [(2.10, 0, 1.22, 0.12, 0.14), (1.70, 0, 1.30, 0.56, 0.50), (1.00, 0, 1.45, 0.80, 0.76),
         (0.00, 0, 1.55, 0.86, 0.86), (-1.00, 0, 1.60, 0.76, 0.72), (-1.80, 0, 1.75, 0.40, 0.40),
         (-2.20, 0, 1.85, 0.20, 0.20), (-5.60, 0, 2.05, 0.10, 0.10)]

    def mfn(i, j):
        if i < 0 or i >= len(F) - 1:
            return paint
        a = 2 * math.pi * (j + 0.5) / segs
        sa = math.sin(a)
        if i <= 1 and sa > -0.30:
            return "Glass"
        if i == 2 and 0.05 < sa < 0.80:
            return "Glass"
        if i >= 6:
            return paint2 if not police else paint
        if sa < -0.55:
            return paint2
        return paint

    def body(mb, lod):
        mb.ellipse_loft(F, segs=segs, m=mfn)
        mb.box((0.85, 1.70, 0.34), loc=(0, -0.45, 2.44), m=paint2, bevel=0.08 if lod == 0 else 0, taper=(0.8, 0.85))
        mb.cyl(0.07, 0.32, loc=(0, -0.20, 2.72), segs=8, m="DarkSteel")
        mb.extrude_poly([(-0.035, -4.9, 2.02), (-0.035, -5.75, 3.10), (-0.035, -6.05, 3.10), (-0.035, -5.70, 1.95)], (0.07, 0, 0), paint)
        mb.box((1.50, 0.36, 0.05), loc=(0, -4.75, 2.05), m=paint, bevel=0.015 if lod == 0 else 0)
        for s in (1, -1):
            mb.box((0.04, 0.40, 0.34), loc=(s * 0.75, -4.75, 2.10), m=paint2)
            mb.tube((s * 0.98, 1.55, 0.06), (s * 0.98, -1.45, 0.06), 0.045, "DarkSteel")
            mb.tube((s * 0.98, 1.55, 0.06), (s * 0.98, 1.85, 0.20), 0.045, "DarkSteel")
            for y in (0.9, -0.8):
                mb.tube((s * 0.98, y, 0.06), (s * 0.55, y, 0.86), 0.035, "DarkSteel")
        mb.cyl(0.14, 0.5, loc=(0.0, -1.6, 2.30), axis='Y', segs=8, m="DarkSteel")
        mb.box((0.05, 0.05, 0.05), loc=(-0.86, 0.0, 1.55), m="LightBarRed")
        mb.box((0.05, 0.05, 0.05), loc=(0.86, 0.0, 1.55), m="TrafficGreen")
        mb.box((0.06, 0.06, 0.06), loc=(0, -5.9, 3.13), m="LightBarRed")
        if lod == 0:
            mb.box((1.45, 2.3, 0.05), loc=(0, 0.35, 0.86), m="Interior")
            for x in (-0.38, 0.38):
                _seat(mb, x, 0.85, 0.98, 0.15)
                _seat(mb, x, -0.25, 0.98, 0.15)
            mb.box((1.2, 0.3, 0.35), loc=(0, 1.55, 1.10), m="Interior", bevel=0.05)
        if police:
            mb.cyl(0.16, 0.22, loc=(0.0, 1.55, 0.70), segs=8, m="DarkSteel")
            mb.sphere(0.17, loc=(0.55, 1.2, 0.72), m="DarkSteel", segs=8, rings=6)
            for s in (1, -1):
                mb.box((0.012, 1.4, 0.22), loc=(s * 0.80, -0.3, 1.50), m="PoliceWhite")
        else:
            for s in (1, -1):
                mb.box((0.012, 1.8, 0.10), loc=(s * 0.835, -0.2, 1.38), m=paint2)

    b = MB()
    body(b, 0)
    b.add_inner_shell("Interior", skip=("Glass", "DarkSteel", "Seat", "Interior", "LightBarRed", "TrafficGreen"))
    b.finish(aid + "_Body", coll, smooth=42, parent=root)
    nb = 4 if police else 3
    r = MB()
    r.cyl(0.14, 0.14, segs=8, m="DarkSteel")
    for i in range(nb):
        a = 2 * math.pi * i / nb
        r.box((4.1, 0.19, 0.03), loc=(2.15 * math.cos(a), 2.15 * math.sin(a), 0.03), m="Trim", rot=(0, 0, a))
        r.box((0.5, 0.08, 0.05), loc=(0.3 * math.cos(a), 0.3 * math.sin(a), 0.0), m="Steel", rot=(0, 0, a))
    r.finish(aid + "_Rotor_Main", coll, parent=root, loc=(0, -0.20, 2.90))
    t = MB()
    t.cyl(0.05, 0.10, axis='X', segs=6, m="DarkSteel")
    t.box((0.02, 0.11, 1.30), m="Trim")
    t.finish(aid + "_Rotor_Tail", coll, parent=root, loc=(0.12, -5.55, 2.45))
    empty(aid + "_Seat_0", coll, loc=(0.38, 0.85, 1.06), parent=root, size=0.15)
    empty(aid + "_Seat_1", coll, loc=(-0.38, 0.85, 1.06), parent=root, size=0.15)
    empty(aid + "_Seat_2", coll, loc=(-0.38, -0.25, 1.06), parent=root, size=0.15)
    empty(aid + "_Seat_3", coll, loc=(0.38, -0.25, 1.06), parent=root, size=0.15)
    empty(aid + "_P_Search", coll, loc=(0.0, 1.55, 0.58), parent=root, size=0.1)
    empty(aid + "_P_Engine", coll, loc=(0, -0.6, 2.6), parent=root, size=0.1)
    _col_box(aid, coll, root, 0, (1.7, 4.0, 1.9), (0, 0.0, 1.35), taper=(0.7, 0.75))
    _col_box(aid, coll, root, 1, (0.3, 3.8, 0.4), (0, -3.9, 2.0))
    _col_box(aid, coll, root, 2, (2.1, 3.2, 0.5), (0, 0.05, 0.25))
    l = MB()
    body(l, 1)
    o = l.finish(aid + "_LOD1", coll, smooth=42, parent=root)
    o.hide_set(True)
    return root


def _wing(mb, span, chord_root, chord_tip, y_le, z, sweep=0.0, dihedral=0.0, m=None, m_tip=None, thick=0.10):
    secs = []
    for x, c, zz, yy in ((-span / 2, chord_tip, z + dihedral, y_le - sweep), (0, chord_root, z, y_le), (span / 2, chord_tip, z + dihedral, y_le - sweep)):
        secs.append([Vector((x, yy, zz)), Vector((x, yy - 0.25 * c, zz + thick * 0.7 * c)), Vector((x, yy - 0.7 * c, zz + thick * 0.5 * c)),
                     Vector((x, yy - c, zz)), Vector((x, yy - 0.7 * c, zz - thick * 0.2 * c)), Vector((x, yy - 0.25 * c, zz - thick * 0.4 * c))])
    return mb.loft(secs, m)


def build_plane(aid="plane", cell=(0, 0, 0), color="#d63a2f"):
    coll = col("Vehicles/Airplanes")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.8)
    paint = mat("CarPaint_" + aid, color, rough=0.3, metal=0.3)
    white = mat("CarPaint2_" + aid, "#f3f1ea", rough=0.35, metal=0.2)
    segs = 10
    F = [(3.15, 0, 1.25, 0.26, 0.28), (2.50, 0, 1.30, 0.50, 0.48), (1.60, 0, 1.38, 0.58, 0.60), (0.90, 0, 1.56, 0.58, 0.72),
         (-0.60, 0, 1.56, 0.55, 0.70), (-1.60, 0, 1.52, 0.38, 0.46), (-4.00, 0, 1.58, 0.09, 0.13)]

    def mfn(i, j):
        if i < 0 or i >= len(F) - 1:
            return "DarkSteel" if i < 0 else white
        a = 2 * math.pi * (j + 0.5) / segs
        sa = math.sin(a)
        if i == 2 and sa > 0.15:
            return "Glass"
        if i == 3 and 0.15 < sa < 0.85:
            return "Glass"
        if i == 0:
            return paint
        if -0.45 < sa < 0.1:
            return paint
        return white

    def body(mb, lod):
        mb.ellipse_loft(F, segs=segs, m=mfn, squareness=0.5)
        _wing(mb, 10.6, 1.55, 1.10, 1.35, 2.26, sweep=0.10, dihedral=0.16, m=white, thick=0.12)
        for s in (1, -1):
            mb.box((0.9, 1.12, 0.03), loc=(s * 4.86, 0.68, 2.44), m=paint)
            mb.tube((s * 0.56, 0.95, 1.02), (s * 2.5, 0.75, 2.22), 0.035, white, segs=6)
        _wing(mb, 3.5, 0.95, 0.65, -3.15, 1.62, sweep=0.15, m=white, thick=0.10)
        mb.extrude_poly([(-0.04, -2.75, 1.66), (-0.04, -3.75, 2.95), (-0.04, -4.15, 2.95), (-0.04, -4.02, 1.60)], (0.08, 0, 0), paint)
        # gear
        mb.tube((0, 2.45, 0.95), (0, 2.50, 0.24), 0.035, "Steel")
        for s in (1, -1):
            mb.tube((s * 0.45, 0.25, 0.95), (s * 1.18, 0.15, 0.27), 0.04, white, segs=6)
        mb.box((0.10, 0.25, 0.10), loc=(0.3, 2.3, 0.88), m="DarkSteel")
        if lod == 0:
            mb.box((1.0, 2.2, 0.05), loc=(0, 0.5, 0.98), m="Interior")
            for x in (-0.28, 0.28):
                _seat(mb, x, 0.75, 1.08, 0.15)
                _seat(mb, x, -0.15, 1.08, 0.15)
            mb.box((1.0, 0.25, 0.30), loc=(0, 1.50, 1.28), m="Interior", bevel=0.04)
            mb.box((0.05, 0.05, 0.05), loc=(-5.3, 0.9, 2.44), m="LightBarRed")
            mb.box((0.05, 0.05, 0.05), loc=(5.3, 0.9, 2.44), m="TrafficGreen")

    b = MB()
    body(b, 0)
    b.add_inner_shell("Interior", skip=("Glass", "DarkSteel", "Seat", "Interior", "Steel", "LightBarRed", "TrafficGreen"))
    b.finish(aid + "_Body", coll, smooth=42, parent=root)
    p = MB()
    p.lathe([(0.0, 0.17), (0.18, 0.12), (0.30, 0.0)], axis='Y', segs=8, m=paint)
    p.box((0.16, 0.03, 2.0), loc=(0, 0.08, 0), m="Trim", rot=(0, math.radians(8), 0))
    p.finish(aid + "_Propeller", coll, smooth=40, parent=root, loc=(0, 3.15, 1.25))
    build_wheel(aid + "_Wheel_N", coll, 0.22, 0.12, 2, parent=root, loc=(0, 2.50, 0.22))
    build_wheel(aid + "_Wheel_L", coll, 0.25, 0.14, 2, parent=root, loc=(-1.20, 0.15, 0.25))
    build_wheel(aid + "_Wheel_R", coll, 0.25, 0.14, 2, parent=root, loc=(1.20, 0.15, 0.25))
    empty(aid + "_Seat_0", coll, loc=(-0.28, 0.75, 1.16), parent=root, size=0.15)
    empty(aid + "_Seat_1", coll, loc=(0.28, 0.75, 1.16), parent=root, size=0.15)
    empty(aid + "_P_Engine", coll, loc=(0, 2.6, 1.6), parent=root, size=0.1)
    _col_box(aid, coll, root, 0, (1.1, 6.6, 1.3), (0, 0.0, 1.45), taper=(0.8, 0.9))
    _col_box(aid, coll, root, 1, (10.4, 1.3, 0.2), (0, 0.7, 2.35))
    _col_box(aid, coll, root, 2, (3.3, 0.9, 1.3), (0, -3.6, 2.2), taper=(0.1, 0.6))
    l = MB()
    body(l, 1)
    o = l.finish(aid + "_LOD1", coll, smooth=42, parent=root)
    o.hide_set(True)
    return root


def build_jet(aid="jet", cell=(0, 0, 0), color="#8d9399"):
    coll = col("Vehicles/Airplanes")
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.8)
    paint = mat("CarPaint_" + aid, color, rough=0.35, metal=0.5)
    paint2 = mat("CarPaint2_" + aid, "#d63a2f", rough=0.35, metal=0.3)
    mat("Afterburner", "#2a1a10", rough=0.5, emit="#ff7a20", estr=0.3)
    segs = 10
    F = [(5.60, 0, 1.45, 0.04, 0.05), (4.40, 0, 1.50, 0.34, 0.34), (3.20, 0, 1.60, 0.52, 0.56), (1.80, 0, 1.68, 0.60, 0.66),
         (0.60, 0, 1.62, 0.66, 0.58), (-2.60, 0, 1.60, 0.62, 0.52), (-4.20, 0, 1.62, 0.42, 0.40)]

    def mfn(i, j):
        if i < 0:
            return paint
        if i >= len(F) - 1:
            return "Afterburner"
        a = 2 * math.pi * (j + 0.5) / segs
        sa = math.sin(a)
        if i in (2, 3) and sa > 0.42:
            return "Glass"
        if i == 0:
            return "DarkSteel"
        return paint

    def body(mb, lod):
        mb.ellipse_loft(F, segs=segs, m=mfn)
        _wing(mb, 8.2, 3.0, 0.9, 1.20, 1.38, sweep=2.3, dihedral=-0.08, m=paint, thick=0.06)
        for s in (1, -1):
            mb.box((0.5, 0.92, 0.03), loc=(s * 3.86, -1.52, 1.34), m=paint2)
            mb.box((0.46, 2.6, 0.50), loc=(s * 0.82, 0.3, 1.50), m=paint, bevel=0.08 if lod == 0 else 0, taper=(1.0, 1.0))
            mb.box((0.40, 0.04, 0.42), loc=(s * 0.82, 1.61, 1.50), m="Under")
            mb.extrude_poly([(s * 0.50 - 0.03, -2.6, 1.95), (s * 0.95 - 0.03, -3.9, 3.25), (s * 1.02 - 0.03, -4.3, 3.25), (s * 0.55 - 0.03, -4.25, 1.90)], (0.06, 0, 0), paint)
            mb.box((0.06, 0.5, 0.20), loc=(s * 1.0, -4.05, 3.20), m=paint2)
        _wing(mb, 4.4, 1.5, 0.6, -2.9, 1.62, sweep=1.0, m=paint, thick=0.06)
        mb.tube((0, 3.3, 1.15), (0, 3.35, 0.24), 0.04, "Steel")
        for s in (1, -1):
            mb.tube((s * 0.9, -0.3, 1.3), (s * 1.25, -0.35, 0.28), 0.045, "Steel")
        if lod == 0:
            _seat(mb, 0, 2.5, 1.40, 0.3)
            _seat(mb, 0, 1.45, 1.48, 0.3)
            mb.box((0.9, 2.4, 0.05), loc=(0, 2.0, 1.32), m="Interior")
            mb.box((0.05, 0.05, 0.05), loc=(-4.1, -1.2, 1.34), m="LightBarRed")
            mb.box((0.05, 0.05, 0.05), loc=(4.1, -1.2, 1.34), m="TrafficGreen")

    b = MB()
    body(b, 0)
    b.finish(aid + "_Body", coll, smooth=42, parent=root)
    build_wheel(aid + "_Wheel_N", coll, 0.22, 0.12, 2, parent=root, loc=(0, 3.35, 0.22))
    build_wheel(aid + "_Wheel_L", coll, 0.27, 0.16, 2, parent=root, loc=(-1.27, -0.35, 0.27))
    build_wheel(aid + "_Wheel_R", coll, 0.27, 0.16, 2, parent=root, loc=(1.27, -0.35, 0.27))
    empty(aid + "_Seat_0", coll, loc=(0, 2.5, 1.48), parent=root, size=0.15)
    empty(aid + "_Seat_1", coll, loc=(0, 1.45, 1.56), parent=root, size=0.15)
    empty(aid + "_P_Engine", coll, loc=(0, -3.6, 1.7), parent=root, size=0.1)
    empty(aid + "_P_Exhaust", coll, loc=(0, -4.3, 1.62), parent=root, size=0.1)
    _col_box(aid, coll, root, 0, (1.3, 9.4, 1.2), (0, 0.6, 1.6), taper=(0.8, 0.9))
    _col_box(aid, coll, root, 1, (8.0, 2.6, 0.2), (0, -0.6, 1.38), taper=(1.0, 1.0))
    _col_box(aid, coll, root, 2, (4.2, 1.2, 1.5), (0, -3.6, 2.4), taper=(0.5, 0.6))
    l = MB()
    body(l, 1)
    o = l.finish(aid + "_LOD1", coll, smooth=42, parent=root)
    o.hide_set(True)
    return root


def build(names=None):
    todo = [
        ("motorcycle", lambda c: build_motorcycle("motorcycle", c)),
        ("bicycle", lambda c: build_bicycle("bicycle", c)),
        ("speedboat", lambda c: build_boat("speedboat", c)),
        ("policeboat", lambda c: build_boat("policeboat", c, police=True)),
        ("helicopter", lambda c: build_heli("helicopter", c)),
        ("policeheli", lambda c: build_heli("policeheli", c, police=True)),
        ("plane", lambda c: build_plane("plane", c)),
        ("jet", lambda c: build_jet("jet", c)),
    ]
    cells = {"motorcycle": (20, 30, 0), "bicycle": (23, 30, 0), "speedboat": (28, 30, 0), "policeboat": (33, 30, 0),
             "helicopter": (20, 45, 0), "policeheli": (32, 45, 0), "plane": (46, 45, 0), "jet": (60, 45, 0)}
    out = []
    for n, fn in todo:
        if names and n not in names:
            continue
        out.append(stats(fn(cells[n])))
    return out


NAMES = ["motorcycle", "bicycle", "speedboat", "policeboat", "helicopter", "policeheli", "plane", "jet"]


def export_all(names=None):
    return [export(n, "vehicles/%s.glb" % n) for n in NAMES if (not names or n in names)]
