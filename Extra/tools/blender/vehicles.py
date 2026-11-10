# Parametric car kit for Cinder Bay. Executed in Blender through MCP.
# Blender axes: +Y = vehicle front, +X = vehicle right, +Z = up.  (glTF/Godot: -Z front)
import bpy, math
from mathutils import Vector
from fable_lib import *


def prof(p, y):
    if y >= p[0][0]:
        return p[0][1]
    if y <= p[-1][0]:
        return p[-1][1]
    for i in range(len(p) - 1):
        y0, v0 = p[i]
        y1, v1 = p[i + 1]
        if y1 <= y <= y0:
            return v0 if y0 == y1 else v0 + (v1 - v0) * (y0 - y) / (y0 - y1)
    return p[-1][1]


def wheel_geo(mb, r, w, style=0, loc=(0, 0, 0), segs=16, simple=False):
    hw = w / 2
    rr = r * 0.66
    x0, y0, z0 = loc
    if simple:
        vs = mb.cyl(r, w, loc=loc, axis='X', segs=8, m="Tire")
        mb.cyl(rr, w + 0.01, loc=loc, axis='X', segs=8, m="Rim")
        return
    dish = min(0.07 if style == 3 else 0.035, hw * 0.6)
    pr = [(-hw + dish, 0.0), (-hw + dish, rr * 0.82), (-hw + 0.012, rr), (-hw, r * 0.90), (-hw * 0.72, r),
          (hw * 0.72, r), (hw, r * 0.90), (hw - 0.012, rr), (hw - dish, rr * 0.82), (hw - dish, 0.0)]

    def mf(k):
        if k in (0, 8):
            return "Rim" if style == 2 else "Trim"
        if k in (1, 7):
            return "Rim"
        return "Tire"
    mb.lathe(pr, axis='X', segs=segs, m=mf, loc=loc)
    n, sw, st = {0: (5, 0.24, 0.016), 1: (6, 0.16, 0.016), 2: (0, 0, 0), 3: (10, 0.09, 0.012), 4: (4, 0.42, 0.014)}[style]
    for side in (-1, 1):
        x = side * (hw - dish + 0.006)
        for i in range(n):
            a = 2 * math.pi * i / n
            mb.box((st, rr * sw, rr * 0.80), loc=(x0 + x, y0 - math.sin(a) * rr * 0.42, z0 + math.cos(a) * rr * 0.42),
                   m="Rim", rot=(a, 0, 0))
        mb.cyl(rr * (0.30 if style == 2 else 0.20), 0.03, loc=(x0 + x, y0, z0), axis='X', segs=8, m="Rim")


def build_wheel(name, coll, r, w, style=0, parent=None, loc=(0, 0, 0)):
    mb = MB()
    wheel_geo(mb, r, w, style)
    return mb.finish(name, coll, smooth=35, loc=loc, parent=parent)


def build_car(aid, P, cell=(0, 0, 0), coll_path="Vehicles/Cars"):
    coll = col(coll_path)
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.6)
    L, W, H = P['L'], P['W'], P['H']
    wr, ww, gc = P['wr'], P['ww'], P['gc']
    yf, yr = P['axf'], P['axr']
    top, plan = P['top'], P['plan']
    sh = P.get('sh', 0.07)
    crown = P.get('crown', 0.03)
    rocker = P.get('rocker', 0.13)
    bottom = P.get('bottom', [(L / 2, gc + 0.12), (L / 2 - 0.30, gc), (-L / 2 + 0.30, gc), (-L / 2, gc + 0.14)])
    paint = M(P['paint']) if P.get('paint') else mat("CarPaint_" + aid, P.get('color', '#b03a2e'), rough=0.3, metal=0.5)
    paint2 = M(P['paint2']) if P.get('paint2') else mat("CarPaint2_" + aid, P.get('color2', '#1b1d21'), rough=0.4, metal=0.3)
    bump_m = "Trim" if P.get('bumper_trim') else paint
    dpaint = M(P['door_paint']) if P.get('door_paint') else paint
    Ra = wr + 0.07
    cab = P.get('cab')
    doors = list(P.get('doors', []))
    floor_z = gc + rocker
    hwf = lambda y: W / 2 * prof(plan, y)
    zt = lambda y: prof(top, y)
    zb = lambda y: prof(bottom, y)
    axles = [yf, yr] + list(P.get('axles_extra', []))

    def arch(y):
        za = 0.0
        for ya in axles:
            dy = abs(y - ya)
            if dy < Ra:
                za = max(za, wr + math.sqrt(Ra * Ra - dy * dy))
        return za

    wells = []
    if cab:
        w0 = doors[0][0] if doors else cab['a'] - 0.30
        w1 = P['well_end'] if 'well_end' in P else ((doors[-1][1] - 0.03) if doors else cab['d'] + 0.30)
        w0 = min(w0, yf - Ra - 0.04)
        w1 = max(w1, yr + Ra + 0.04)
        wells.append((w0, w1, floor_z, sh + 0.10, "Interior"))
        doors = [(min(d0, w0), max(d1, w1 + 0.03)) for d0, d1 in doors]
    if 'bed' in P:
        bd = P['bed']
        wells.append((bd[0], bd[1], bd[2], sh + 0.02, "Trim"))

    def well_at(y):
        for wl in wells:
            if wl[1] <= y <= wl[0]:
                return wl
        return None

    def geo(lod):
        use_doors = doors if lod == 0 else []
        use_wells = wells if lod == 0 else [w for w in wells if w[4] != "Interior"]

        def wat(y):
            for wl in use_wells:
                if wl[1] <= y <= wl[0]:
                    return wl
            return None

        def dat(y):
            for d in use_doors:
                if d[1] < y < d[0]:
                    return d
            return None

        ys = set()
        for pr_ in (top, plan, bottom):
            for y, _ in pr_:
                ys.add(round(y, 4))
        nseg = 10 if lod == 0 else 4
        for ya in axles:
            ys.add(round(ya + Ra, 4))
            ys.add(round(ya - Ra, 4))
            for k in range(nseg + 1):
                ys.add(round(ya + (Ra - 0.002) * math.cos(math.pi * k / nseg), 4))
        for wl in use_wells:
            ys.update([round(wl[0] + 0.002, 4), round(wl[0], 4), round(wl[1], 4), round(wl[1] - 0.002, 4)])
        for d in use_doors:
            ys.update([round(d[0], 4), round(d[0] - 0.002, 4), round(d[1] + 0.002, 4), round(d[1], 4)])
        if cab:
            ys.update([round(cab['a'], 4), round(cab['d'], 4)])
        ys = [y for y in sorted(ys, reverse=True) if -L / 2 - 1e-6 <= y <= L / 2 + 1e-6]
        out = []
        for y in ys:
            if not out or out[-1] - y > 0.0012:
                out.append(y)
        ys = out

        def section(y):
            w = hwf(y)
            t = zt(y)
            b = zb(y)
            za = min(arch(y), t - sh - 0.035)
            z0 = max(b, za)
            z1 = max(b + rocker, za)
            z2 = max(t - sh, z1 + 0.01)
            wl = wat(y)
            if wl and dat(y):
                R = [(w * 0.94, z0), (w, z1), (w, z1), (w, z1), (w, z1), (w - wl[3], wl[2])]
                cz = wl[2]
            elif wl:
                R = [(w * 0.94, z0), (w, z1), (w, z2), (w - sh, t), (w - wl[3], t), (w - wl[3] - 0.001, wl[2])]
                cz = wl[2]
            else:
                R = [(w * 0.94, z0), (w, z1), (w, z2), (w - sh, t), (w - sh - 0.03, t + crown * 0.15), (w * 0.5, t + crown * 0.7)]
                cz = t + crown
            return [Vector((x, y, z)) for x, z in R] + [Vector((0, y, cz))] + [Vector((-x, y, z)) for x, z in reversed(R)]

        def matfn(i, j):
            if i < 0 or i >= len(ys) - 1:
                return paint
            ym = (ys[i] + ys[i + 1]) / 2
            if j == 12:
                return "Under"
            if j in (0, 11):
                if arch(ym) > zb(ym) + 0.001:
                    return "Under"
                return "Trim" if P.get('cladding') else paint
            wl = wat(ys[i]) or wat(ys[i + 1])
            if wl and 4 <= j <= 7:
                return wl[4]
            if (dat(ys[i]) or dat(ys[i + 1])) and j in (1, 2, 3, 8, 9, 10):
                return "Interior"
            return paint

        body = MB()
        body.loft([section(y) for y in ys], matfn)
        parts = {'body': body, 'doors': {}, 'ys': ys}
        cabmb = MB() if lod == 0 else body
        roofmb = MB() if (lod == 0 and P.get('convertible')) else cabmb
        if cab:
            a, b, c, d = cab['a'], cab['b'], cab['c'], cab['d']
            Hr = cab.get('roof_r', H)
            xr = W / 2 * cab.get('wroof', 0.76)
            xb = lambda y: hwf(y) - sh - 0.012
            zbelt = lambda y: zt(y) - 0.004
            margin = cab.get('margin', 0.055)
            roof_m = paint2 if P.get('roof2') else paint

            def B(y, s=1):
                return Vector((s * xb(y), y, zbelt(y)))

            def T(y, s=1):
                if y >= b:
                    t = (a - y) / (a - b) if a != b else 1.0
                    return Vector((s * (xb(a) + (xr - xb(a)) * t), y, zbelt(a) + (H - zbelt(a)) * t))
                if y <= c:
                    t = (y - d) / (c - d) if c != d else 1.0
                    return Vector((s * (xb(d) + (xr - xb(d)) * t), y, zbelt(d) + (Hr - zbelt(d)) * t))
                t = (b - y) / (b - c)
                return Vector((s * xr, y, H + (Hr - H) * t))
            cabmb.framed([B(a, -1), B(a, 1), T(b, 1), T(b, -1)], paint, "Glass", margin, outward=(0, 0.5, 0.8))
            if cab.get('rear_solid'):
                roofmb.poly([B(d, 1), B(d, -1), T(c, -1), T(c, 1)], paint, outward=(0, -0.5, 0.8))
            else:
                roofmb.framed([B(d, 1), B(d, -1), T(c, -1), T(c, 1)], paint, "Glass", margin, outward=(0, -0.5, 0.8))
            roofmb.poly([T(b, -1), T(b, 1), T(c, 1), T(c, -1)], roof_m, outward=(0, 0, 1))
            S = sorted(set([a, d] + [e for dr in doors for e in dr if d < e < a]), reverse=True)
            solid = cab.get('solid', [])
            for k in range(len(S) - 1):
                y1, y2 = S[k], S[k + 1]
                di = None
                for q, dr in enumerate(doors):
                    if abs(dr[0] - y1) < 1e-5 and abs(dr[1] - y2) < 1e-5:
                        di = q
                ym = (y1 + y2) / 2
                is_solid = any(s1 >= ym >= s2 for s1, s2 in solid)
                for s in (1, -1):
                    pts = [B(y1, s), B(y2, s), T(y2, s)]
                    if y2 < c < y1:
                        pts.append(T(c, s))
                    if y2 < b < y1:
                        pts.append(T(b, s))
                    pts.append(T(y1, s))
                    if di is not None and lod == 0:
                        key = (di, s)
                        if key not in parts['doors']:
                            parts['doors'][key] = MB()
                        tgt = roofmb if P.get('convertible') else parts['doors'][key]
                    else:
                        tgt = roofmb
                    fm = dpaint if (di is not None and lod == 0) else paint
                    if is_solid:
                        tgt.poly(pts, fm, outward=(s, 0, 0.3))
                    else:
                        tgt.framed(pts, fm, "Glass", margin, outward=(s, 0, 0.3))
            parts['T'] = T
            parts['B'] = B
        if lod == 0:
            parts['cab'] = cabmb
            parts['roof'] = roofmb if roofmb is not cabmb else None
            # door lower panels
            off = 0.012
            for q, dr in enumerate(doors):
                dys = [y for y in ys if dr[1] <= y <= dr[0]]
                dys = [dr[0]] + [y for y in dys if dr[1] + 0.003 < y < dr[0] - 0.003] + [dr[1]]
                for s in (1, -1):
                    key = (q, s)
                    if key not in parts['doors']:
                        parts['doors'][key] = MB()
                    dm = parts['doors'][key]
                    rows = []
                    for y in dys:
                        w = hwf(y)
                        t = zt(y)
                        z1 = max(zb(y) + rocker, arch(y)) + 0.012
                        rows.append((Vector((s * (w + off), y, z1)), Vector((s * (w + off), y, t - sh)),
                                     Vector((s * (w - sh + off), y, t + off * 0.4))))
                    for k in range(len(rows) - 1):
                        A, Bq = rows[k], rows[k + 1]
                        dm.poly([A[0], Bq[0], Bq[1], A[1]], dpaint, outward=(s, 0, 0))
                        dm.poly([A[1], Bq[1], Bq[2], A[2]], dpaint, outward=(s, 0, 1))
                    yh = dr[1] + 0.14
                    dm.box((0.025, 0.15, 0.03), loc=(s * (hwf(yh) + off + 0.01), yh, zt(yh) - sh - 0.07), m="Chrome")
        return parts

    P0 = geo(0)
    body = P0['body']
    ys = P0['ys']
    yF, yR = L / 2, -L / 2
    zl, zh, wF = zb(yF), zt(yF), hwf(yF)
    zlr, zhr, wR = zb(yR), zt(yR), hwf(yR)
    fh = P.get('light_drop', 0.085)

    def fixtures(mb, lod):
        for s in (1, -1):
            mb.box((wF * 0.40, 0.05, 0.11), loc=(s * wF * 0.70, yF + 0.004, zh - fh), m="LightHead", bevel=0.012 if lod == 0 else 0)
            mb.box((wF * 0.30, 0.05, 0.035), loc=(s * wF * 0.74, yF + 0.004, zh - fh - 0.085), m="LightIndicator")
            mb.box((wR * 0.38, 0.05, 0.10), loc=(s * wR * 0.72, yR - 0.004, zhr - 0.08), m="LightTail", bevel=0.012 if lod == 0 else 0)
            mb.box((wR * 0.13, 0.05, 0.05), loc=(s * wR * 0.44, yR - 0.004, zhr - 0.08), m="LightReverse")
            mb.box((wR * 0.38, 0.05, 0.03), loc=(s * wR * 0.72, yR - 0.004, zhr - 0.155), m="LightIndicator")
            if cab and lod == 0:
                ym = cab['a'] - 0.10
                mb.box((0.15, 0.07, 0.09), loc=(s * (hwf(ym) + 0.075), ym, zt(ym) + 0.05), m=paint2, bevel=0.015)
        mb.box((0.34, 0.02, 0.11), loc=(0, yR - 0.012, zhr - 0.20 if zhr - zlr > 0.34 else zlr + 0.12), m="Plate")
        if 'extra' in P:
            P['extra'](mb, dict(P=P, lod=lod, paint=paint, paint2=paint2, hw=hwf, zt=zt, zb=zb, aid=aid))

    def bumper_geo(mb, front, variant=0):
        y, z, w = (yF, zl, wF) if front else (yR, zlr, wR)
        sgn = 1 if front else -1
        if variant == 0:
            mb.box((2 * w * 1.03, 0.14, 0.14), loc=(0, y + sgn * 0.012, z + 0.085), m=bump_m, bevel=0.03)
            mb.box((2 * w * 0.80, 0.05, 0.05), loc=(0, y + sgn * 0.065, z + 0.045), m="Trim")
        else:
            mb.box((2 * w * 1.05, 0.16, 0.18), loc=(0, y + sgn * 0.02, z + 0.10), m=bump_m, bevel=0.035)
            mb.box((2 * w * 1.10, 0.24, 0.025), loc=(0, y + sgn * 0.06, z + 0.005), m="Trim")
            if front:
                for s in (1, -1):
                    mb.box((w * 0.34, 0.06, 0.07), loc=(s * w * 0.66, y + 0.085, z + 0.09), m="Trim")
            else:
                for i in range(5):
                    mb.box((0.02, 0.22, 0.07), loc=((i - 2) * w * 0.30, y - 0.06, z + 0.03), m="Trim")
        if front:
            mb.box((0.34, 0.02, 0.10), loc=(0, y + 0.09 + (0.01 if variant else 0), z + 0.10), m="Plate")

    def grille_geo(mb, variant=0):
        if variant == 0:
            mb.box((wF * 0.86, 0.04, 0.10), loc=(0, yF + 0.004, zh - fh), m="Trim")
        else:
            mb.box((wF * 0.92, 0.05, 0.13), loc=(0, yF + 0.004, zh - fh), m="Chrome", bevel=0.01)
            for i in range(4):
                mb.box((wF * 0.84, 0.06, 0.012), loc=(0, yF + 0.006, zh - fh - 0.045 + i * 0.03), m="Trim")

    fixtures(body, 0)
    # ---- interior: seats, dash
    seat_h = P.get('seat_h', 0.10)
    recl = P.get('recline', 0.25)
    seats = P.get('seats', [])
    for (sx, sy) in seats:
        body.box((0.46, 0.48, 0.13), loc=(sx, sy + 0.05, floor_z + seat_h), m="Seat", bevel=0.03)
        body.box((0.44, 0.11, 0.56), loc=(sx, sy - 0.24 - 0.14 * recl, floor_z + seat_h + 0.30), m="Seat", rot=(-recl, 0, 0), bevel=0.03)
        body.box((0.24, 0.09, 0.17), loc=(sx, sy - 0.26 - 0.36 * recl, floor_z + seat_h + 0.66), m="Seat", rot=(-recl, 0, 0), bevel=0.03)
    if cab and wells:
        w0 = wells[0][0]
        dw = 2 * (hwf(w0) - sh - 0.11)
        zbelt0 = zt(w0)
        body.box((dw, 0.26, 0.20), loc=(0, w0 - 0.12, zbelt0 - 0.11), m="Interior", bevel=0.04)
    body_o = body.finish(aid + "_Body", coll, smooth=38, parent=root)
    if P0.get('cab') is not None and cab:
        P0['cab'].add_inner_shell("Interior", skip=("Glass",))
        P0['cab'].finish(aid + "_Cabin", coll, smooth=38, parent=root)
    if P0.get('roof') is not None:
        P0['roof'].add_inner_shell("Interior", skip=("Glass",))
        P0['roof'].finish(aid + "_Roof", coll, smooth=38, parent=root)
    for (q, s), dm in P0['doors'].items():
        dr = doors[q]
        dm.add_inner_shell("Interior", skip=("Glass", "Chrome"))
        nm = "%s_Door_%s%s" % (aid, "FR"[q] if q < 2 else "X", "R" if s > 0 else "L")
        dm.finish(nm, coll, smooth=38, parent=root, origin=(s * hwf(dr[0]), dr[0], floor_z))
    # steering wheel
    if seats and cab:
        sx, sy = seats[0]
        sw = MB()
        sw.lathe([(-0.018, 0.165), (0, 0.185), (0.018, 0.165), (0, 0.145)], axis='Y', segs=12, m="Trim", ring=True)
        sw.box((0.30, 0.02, 0.035), m="Trim")
        sw.box((0.035, 0.02, 0.16), loc=(0, 0, -0.08), m="Trim")
        sw.cyl(0.05, 0.05, axis='Y', segs=8, m="Trim")
        sw.cyl(0.025, 0.30, loc=(0, 0.15, 0), axis='Y', segs=6, m="Interior")
        w0 = wells[0][0]
        sw.finish(aid + "_SteeringWheel", coll, smooth=40, parent=root,
                  loc=(sx, w0 - 0.36, zt(w0) - 0.03), rot=(math.radians(-22), 0, 0))
    for i, (sx, sy) in enumerate(seats):
        empty("%s_Seat_%d" % (aid, i), coll, loc=(sx, sy, floor_z + seat_h + 0.07), parent=root, size=0.15)
    # ---- wheels
    track = W / 2 - ww / 2 - P.get('wheel_inset', 0.03)
    wi = 0
    for nm, wy in [("F", yf), ("R", yr)] + [("M%d" % i, y) for i, y in enumerate(P.get('axles_extra', []))]:
        for s, sn in ((-1, "L"), (1, "R")):
            build_wheel("%s_Wheel_%s%s" % (aid, nm, sn), coll, wr, ww, P.get('rim', 0), parent=root, loc=(s * track, wy, wr))
    # ---- swappable parts
    def part(name, fn, smooth=38):
        mb = MB()
        fn(mb)
        if len(mb.bm.verts) == 0:
            mb.bm.free()
            return None
        o = mb.finish("%s_%s" % (aid, name), coll, smooth=smooth, parent=root)
        if name.startswith("Mod_"):
            o.hide_set(True)
        return o
    part("Bumper_F", lambda mb: bumper_geo(mb, True, 0))
    part("Bumper_R", lambda mb: bumper_geo(mb, False, 0))
    part("Grille", lambda mb: grille_geo(mb, 0))
    exz = zlr + 0.02
    part("Exhaust", lambda mb: mb.cyl(0.035, 0.18, loc=(wR * 0.55, yR + 0.03, exz), axis='Y', segs=8, m="Chrome"))
    if P.get('mods', True):
        part("Mod_Bumper_F_1", lambda mb: bumper_geo(mb, True, 1))
        part("Mod_Bumper_R_1", lambda mb: bumper_geo(mb, False, 1))
        part("Mod_Grille_1", lambda mb: grille_geo(mb, 1))

        def ex1(mb):
            for s in (1, -1):
                for o in (0, 0.09):
                    mb.cyl(0.045, 0.20, loc=(s * (wR * 0.55 + o), yR + 0.03, exz), axis='Y', segs=8, m="Chrome")
        part("Mod_Exhaust_1", ex1)
        ys_sp = yR + 0.17
        zsp = zt(ys_sp) + crown * 0.5

        def sp1(mb):
            mb.box((W * 0.80, 0.18, 0.045), loc=(0, ys_sp, zsp + 0.035), m=paint, rot=(math.radians(-14), 0, 0), bevel=0.012)

        def sp2(mb):
            for s in (1, -1):
                mb.box((0.035, 0.10, 0.24), loc=(s * W * 0.27, ys_sp + 0.04, zsp + 0.11), m=paint2)
                mb.box((0.02, 0.30, 0.10), loc=(s * W * 0.46, ys_sp, zsp + 0.25), m=paint2)
            mb.box((W * 0.92, 0.26, 0.03), loc=(0, ys_sp, zsp + 0.24), m=paint2, rot=(math.radians(-8), 0, 0), bevel=0.01)
        part("Mod_Spoiler_1", sp1)
        part("Mod_Spoiler_2", sp2)
        if cab:
            yh = (cab['a'] + yF) / 2
            zhd = zt(yh) + crown

            def hood1(mb):
                mb.box((0.36, 0.52, 0.075), loc=(0, yh, zhd + 0.025), m=paint, taper=(0.8, 0.8), bevel=0.012)
                mb.box((0.26, 0.02, 0.04), loc=(0, yh + 0.262, zhd + 0.03), m="Under")

            def hood2(mb):
                for s in (1, -1):
                    for k in range(3):
                        mb.box((0.24, 0.05, 0.014), loc=(s * 0.27, yh + (k - 1) * 0.10, zt(yh + (k - 1) * 0.10) + crown * 0.6 + 0.004), m="Trim")
            part("Mod_Hood_1", hood1)
            part("Mod_Hood_2", hood2)
            ya0, ya1 = yf - Ra - 0.03, yr + Ra + 0.03

            def skirts(mb):
                for s in (1, -1):
                    mb.box((0.07, ya0 - ya1, 0.085), loc=(s * (W / 2 + 0.005), (ya0 + ya1) / 2, gc + 0.055), m=paint2, bevel=0.02)
            part("Mod_Skirts_1", skirts)
            b_, c_ = cab['b'], cab['c']
            Hr_ = cab.get('roof_r', H)

            def roof1(mb):
                mb.box((0.34, 0.50, 0.08), loc=(0, b_ - 0.32, H + 0.03), m=paint2, taper=(0.75, 0.7), bevel=0.012)
            part("Mod_Roof_1", roof1)

            def stripes(mb, xs, wd):
                e = 0.007
                pts = [y for y in ys if cab['a'] + 0.02 <= y <= yF - 0.03]
                tail = [y for y in ys if yR + 0.03 <= y <= cab['d'] - 0.02]
                for x in xs:
                    for seq in (pts, tail):
                        for k in range(len(seq) - 1):
                            y1, y2 = seq[k], seq[k + 1]
                            f = lambda y: zt(y) + crown * (1 - abs(x) / max(0.3, hwf(y) - sh)) + e
                            mb.poly([(x - wd / 2, y1, f(y1)), (x + wd / 2, y1, f(y1)), (x + wd / 2, y2, f(y2)), (x - wd / 2, y2, f(y2))], paint2, outward=(0, 0, 1))
                    if not P.get('convertible'):
                        mb.poly([(x - wd / 2, b_, H + e), (x + wd / 2, b_, H + e), (x + wd / 2, c_, Hr_ + e), (x - wd / 2, c_, Hr_ + e)], paint2, outward=(0, 0, 1))
            part("Mod_Stripe_1", lambda mb: stripes(mb, (-0.17, 0.17), 0.17))
            part("Mod_Stripe_2", lambda mb: stripes(mb, (0.0,), 0.50))
    # ---- collision helpers
    zbmax = max(z for _, z in top)
    belt = zt(cab['a']) if cab else zbmax
    c0 = MB()
    c0.box((W * 0.95, L * 0.97, belt - gc - 0.08), loc=(0, 0, (belt + gc + 0.08) / 2))
    o = c0.finish(aid + "_COL_0", coll, parent=root)
    o.display_type = 'WIRE'
    if cab:
        a, b, c, d = cab['a'], cab['b'], cab['c'], cab['d']
        c1 = MB()
        c1.box((W * 0.86, a - d, H - belt), loc=(0, (a + d) / 2, (H + belt) / 2),
               taper=(0.85, max(0.2, (b - c) / (a - d))), shear=(0, (b + c) / 2 - (a + d) / 2))
        o = c1.finish(aid + "_COL_1", coll, parent=root)
        o.display_type = 'WIRE'
    if 'col_extra' in P:
        for i, (size, loc) in enumerate(P['col_extra']):
            cx = MB()
            cx.box(size, loc=loc)
            o = cx.finish("%s_COL_%d" % (aid, i + 2), coll, parent=root)
            o.display_type = 'WIRE'
    # ---- markers
    empty(aid + "_P_Head_L", coll, loc=(-wF * 0.70, yF + 0.05, zh - fh), parent=root, size=0.1)
    empty(aid + "_P_Head_R", coll, loc=(wF * 0.70, yF + 0.05, zh - fh), parent=root, size=0.1)
    empty(aid + "_P_Tail_L", coll, loc=(-wR * 0.72, yR - 0.05, zhr - 0.08), parent=root, size=0.1)
    empty(aid + "_P_Tail_R", coll, loc=(wR * 0.72, yR - 0.05, zhr - 0.08), parent=root, size=0.1)
    empty(aid + "_P_Exhaust", coll, loc=(wR * 0.55, yR - 0.08, exz), parent=root, size=0.1)
    ye = P.get('engine_y', (yF + (cab['a'] if cab else 0)) / 2)
    empty(aid + "_P_Engine", coll, loc=(0, ye, zt(ye) + 0.05), parent=root, size=0.1)
    # ---- LOD1 (single merged mesh)
    P1 = geo(1)
    lb = P1['body']
    fixtures(lb, 1)
    bumper_geo(lb, True, 0)
    bumper_geo(lb, False, 0)
    grille_geo(lb, 0)
    for wy in axles:
        for s in (-1, 1):
            wheel_geo(lb, wr, ww, loc=(s * track, wy, wr), simple=True)
    o = lb.finish(aid + "_LOD1", coll, smooth=38, parent=root)
    o.hide_set(True)
    return root
