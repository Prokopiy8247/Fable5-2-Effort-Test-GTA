"""veh_cars - parametric low-poly car generator for NEON TIDE: Vesper Bay (cars + service vehicles).

ONE generator (class `Car`) + ONE data dict per vehicle (`CARS`).  Runs inside the user's live Blender:

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import veh_cars as M; importlib.reload(M)
    print(M.build_all())            # build + export + manifest for every vehicle
    print(M.make("car_sedan"))      # or a single one

Construction (see SPEC_VEHICLES.md):
  * a body is modelled in "undeformed space" as a straight extrusion of a side profile (half width W2) with an
    explicit chamfer along the whole perimeter, wheel housings, a door notch and an open cabin (interior tub);
  * `Car.conforming()` then bisects the new geometry at the plan-taper stations / waist / rocker lines and scales
    X by plan(y) * section(z): tapered nose and tail, tucked-under sills - and every detail (bumpers, lamps,
    greenhouse, doors) follows the body automatically because it went through the same function.
Everything mirrored is authored once for the right side (+X) inside `mb.at(scale=(-1, 1, 1))` (the kit flips the
winding), nose / tail details are authored once in an "end frame" where the surface faces +Y.
"""
import bpy
import bmesh
import json
import math
import os
from contextlib import contextmanager
from mathutils import Vector, Euler

import gta_kit as K

PAINT = "@Paint1"
PAINT2 = "@Paint2"
GLASS = "@Glass"
OPEN_TAGS = ("belt", "bed")
TOP_TAGS = ("hood", "cowl", "belt", "deck", "roof", "bed", "step")
TAG_COLORS = {"valance": "plastic_black", "under": "plastic_black", "arch": "black",
              "cowl": "plastic_black", "belt": "plastic_black"}
MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "vehicles_cars.json")


# ============================================================================ small helpers
def lerp(a, b, t):
    return a + (b - a) * t


def pw(x, knots):
    """Piecewise-linear interpolation through sorted (x, value) knots, clamped at the ends."""
    if x <= knots[0][0]:
        return knots[0][1]
    for (x0, v0), (x1, v1) in zip(knots, knots[1:]):
        if x <= x1:
            return v0 if x1 == x0 else v0 + (v1 - v0) * (x - x0) / (x1 - x0)
    return knots[-1][1]


def offset_closed(pts, d):
    """Inward mitre offset of a CCW 2D polygon. d: distance or per-vertex list."""
    n = len(pts)
    nrm = []
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dy) or 1.0
        nrm.append((dy / l, -dx / l))
    out = []
    for i in range(n):
        a, b = nrm[i - 1], nrm[i]
        den = max(0.3, 1.0 + a[0] * b[0] + a[1] * b[1])
        dd = d[i] if isinstance(d, (list, tuple)) else d
        out.append((pts[i][0] - (a[0] + b[0]) / den * dd, pts[i][1] - (a[1] + b[1]) / den * dd))
    return out


def offset_open(pts, d):
    """Mitre offset of an open 2D polyline to its LEFT by d."""
    n = len(pts)
    nrm = []
    for i in range(n - 1):
        dx, dy = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
        l = math.hypot(dx, dy) or 1.0
        nrm.append((-dy / l, dx / l))
    out = []
    for i in range(n):
        if i == 0:
            m = nrm[0]
        elif i == n - 1:
            m = nrm[-1]
        else:
            a, b = nrm[i - 1], nrm[i]
            den = max(0.3, 1.0 + a[0] * b[0] + a[1] * b[1])
            m = ((a[0] + b[0]) / den, (a[1] + b[1]) / den)
        out.append((pts[i][0] + m[0] * d, pts[i][1] + m[1] * d))
    return out


def clip_poly(poly, axis, lo=None, hi=None):
    """Sutherland-Hodgman clip of a 2D polygon to lo <= p[axis] <= hi (keeps the winding)."""
    def clip(pts, bound, keep_ge):
        out = []
        n = len(pts)
        for i in range(n):
            a = pts[i]
            b = pts[(i + 1) % n]
            ia = (a[axis] >= bound - 1e-9) if keep_ge else (a[axis] <= bound + 1e-9)
            ib = (b[axis] >= bound - 1e-9) if keep_ge else (b[axis] <= bound + 1e-9)
            if ia:
                out.append(a)
            if ia != ib and abs(b[axis] - a[axis]) > 1e-12:
                t = (bound - a[axis]) / (b[axis] - a[axis])
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        return out
    pts = list(poly)
    if lo is not None and pts:
        pts = clip(pts, lo, True)
    if hi is not None and pts:
        pts = clip(pts, hi, False)
    return clean_poly(pts, 1e-5)


def clean_poly(pts, min_edge=1e-5):
    """Remove vertices closer than min_edge to their predecessor."""
    out = []
    for p in pts:
        if out and math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) < min_edge:
            continue
        out.append(p)
    while len(out) > 1 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < min_edge:
        out.pop()
    return out


def hull2d(pts):
    """Convex hull (CCW) of 2D points."""
    pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def reduce_poly(pts, nmax):
    """Drop the least significant vertices of a convex polygon until len <= nmax."""
    pts = list(pts)
    while len(pts) > nmax:
        best, bi = None, 0
        n = len(pts)
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            area = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
            if best is None or area < best:
                best, bi = area, i
        pts.pop(bi)
    return pts


def P(mb, pts, color):
    """n-gon through mb.poly (flip-safe under mirrored transforms); drops duplicate points."""
    out = []
    for p in pts:
        v = Vector(p)
        if out and (v - out[-1]).length < 1e-6:
            continue
        out.append(v)
    while len(out) > 1 and (out[0] - out[-1]).length < 1e-6:
        out.pop()
    if len(out) < 3:
        return None
    return mb.poly(out, color)


def ring_loft(mb, rings, color, cap0=True, cap1=True, edge_colors=None, skip=(), cap_colors=None):
    """Skin consecutive rings (each CCW about the extrusion direction ring[0] -> ring[-1])."""
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n):
            if k in skip:
                continue
            k2 = (k + 1) % n
            col = edge_colors[k] if (edge_colors and edge_colors[k]) else color
            P(mb, [a[k], a[k2], b[k2], b[k]], col)
    if cap0:
        P(mb, list(reversed(rings[0])), cap_colors[0] if cap_colors else color)
    if cap1:
        P(mb, rings[-1], cap_colors[1] if cap_colors else color)


def lathe_x(mb, prof, segs):
    """Surface of revolution about the X axis. prof = [(x, radius, color_of_the_strip_starting_here)],
    traversed from the outer (-X) axis point over the tread to the inner (+X) axis point."""
    rings = []
    for (x, rr, _c) in prof:
        rings.append([(x, rr * math.cos(2 * math.pi * k / segs), rr * math.sin(2 * math.pi * k / segs))
                      for k in range(segs)])
    for i in range(len(prof) - 1):
        a, b = rings[i], rings[i + 1]
        ra, rb = prof[i][1], prof[i + 1][1]
        col = prof[i][2]
        if ra < 1e-6 and rb < 1e-6:
            continue
        if ra < 1e-6:
            if abs(prof[i][0] - prof[i + 1][0]) < 1e-6:
                P(mb, list(reversed(b)), col)
            else:
                for k in range(segs):
                    P(mb, [a[0], b[(k + 1) % segs], b[k]], col)
        elif rb < 1e-6:
            if abs(prof[i][0] - prof[i + 1][0]) < 1e-6:
                P(mb, a, col)
            else:
                for k in range(segs):
                    P(mb, [a[k], a[(k + 1) % segs], b[0]], col)
        else:
            for k in range(segs):
                k2 = (k + 1) % segs
                P(mb, [a[k], a[k2], b[k2], b[k]], col)


def hull_object(root, part, pts, color="gray_mid"):
    """Convex hull mesh object from 3D points."""
    mb = K.MB()
    vs = [mb.bm.verts.new(p) for p in pts]
    r = bmesh.ops.convex_hull(mb.bm, input=vs)
    junk = list({g for g in (list(r.get("geom_interior", [])) + list(r.get("geom_unused", [])))
                 if isinstance(g, bmesh.types.BMVert) and g.is_valid})
    if junk:
        bmesh.ops.delete(mb.bm, geom=junk, context="VERTS")
    loose = [v for v in mb.bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(mb.bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(mb.bm, faces=mb.bm.faces[:])
    mb.paint(mb.bm.faces[:], color)
    return mb.to_object(root, part)


def _hide(obj):
    try:
        obj.hide_set(True)
    except Exception:
        pass
    obj.hide_render = True


# ============================================================================ wheels
def make_wheel(root, part, r, w, style="spoke5", rim_ratio=0.66, rim_color="aluminum", cap_color="chrome",
               segs=14, dual=False, disc_color="gunmetal"):
    """Complete wheel (tyre + rim + hub): origin centre, axle X, outer face toward -X."""
    mb = K.MB()
    T = "tire"
    xo, xi = -w * 0.5, w * 0.5
    Rr = r * rim_ratio
    ch = min(0.04, w * 0.2)
    wt = w if not dual else (w - 0.04) * 0.5        # width of one tyre
    xt = xo + wt                                    # inner edge of the outer tyre
    tyre = [(xo, r - ch, T), (xo + ch, r, T), (xt - ch, r, T), (xt, r - ch, T)]
    if dual:
        gap_r = Rr + (r - Rr) * 0.35
        tyre += [(xt, gap_r, "black"), (xi - wt, gap_r, T), (xi - wt, r - ch, T), (xi - wt + ch, r, T),
                 (xi - ch, r, T), (xi, r - ch, T)]
    tyre += [(xi, 0.0, T)]
    if style in ("spoke5", "spoke6", "spoke10", "deep"):
        dish = min(0.085 if style == "deep" else 0.055, wt * 0.42)
        Rin = Rr - 0.018
        prof = [(xo + dish, 0.0, disc_color), (xo + dish, Rin, rim_color), (xo + 0.006, Rr, T)] + tyre
        lathe_x(mb, prof, segs)
        ns = {"spoke5": 5, "spoke6": 6, "spoke10": 10, "deep": 6}[style]
        sw = {"spoke5": 0.085, "spoke6": 0.07, "spoke10": 0.04, "deep": 0.06}[style]
        th = dish - 0.016
        r0 = 0.035
        for k in range(ns):
            a = 2 * math.pi * k / ns
            mb.box((th, sw, Rr - 0.004 - r0), (xo + 0.016 + th * 0.5, -math.sin(a) * r0, math.cos(a) * r0),
                   rim_color, rot=(math.degrees(a), 0, 0), taper=(1.0, 0.6), base=True)
        mb.cyl(0.062, dish - 0.006, (xo + 0.010 + (dish - 0.006) * 0.5, 0, 0), rim_color, axis="X", segs=8,
               cap_color=cap_color)
    elif style == "steel":
        Rin = Rr - 0.02
        prof = [(xo + 0.012, 0.0, cap_color), (xo + 0.012, r * 0.20, cap_color), (xo + 0.03, r * 0.25, rim_color),
                (xo + 0.022, Rin * 0.74, rim_color), (xo + 0.052, Rin, rim_color), (xo + 0.006, Rr, T)] + tyre
        lathe_x(mb, prof, segs)
    elif style == "truck_f":     # protruding hub
        Rin = Rr - 0.02
        prof = [(xo - 0.035, 0.0, cap_color), (xo - 0.035, r * 0.16, rim_color), (xo + 0.01, r * 0.30, rim_color),
                (xo + 0.035, Rin * 0.9, rim_color), (xo + 0.05, Rin, rim_color), (xo + 0.006, Rr, T)] + tyre
        lathe_x(mb, prof, segs)
        for k in range(8):
            a = 2 * math.pi * k / 8
            mb.box((0.02, 0.028, 0.028), (xo + 0.012, math.cos(a) * r * 0.40, math.sin(a) * r * 0.40), cap_color)
    elif style == "truck_r":     # deep dish (dual rear)
        Rin = Rr - 0.02
        dd = min(0.14, wt * 0.55)
        prof = [(xo + dd - 0.05, 0.0, cap_color), (xo + dd - 0.05, r * 0.17, rim_color), (xo + dd, r * 0.26, rim_color),
                (xo + dd, Rin * 0.82, rim_color), (xo + 0.03, Rin, rim_color), (xo + 0.006, Rr, T)] + tyre
        lathe_x(mb, prof, segs)
    else:
        raise ValueError("unknown rim style " + style)
    return mb.to_object(root, part, weld=True, sharp_angle=38)


# ============================================================================ the generator
DEFAULTS = dict(
    category="Cars", paint=PAINT, door_paint=None,
    c=0.05, c_low=0.022, ledge_w=0.13, door_t=0.075, door_gap=0.012,
    arch_gap=0.05, arch_segs=8, arch_pow=2.0, well_depth=None, arch_lip=None,
    tuck=0.035, waist_z=None, rocker_z=None, sill_z=None, floor_z=None,
    taper_f=0.11, taper_r=0.09, plan=None,
    wheel_w=0.22, wheel_w_r=None, rim="spoke5", rim_r=None, rim_ratio=0.66, rim_color="aluminum",
    cap_color="chrome", tyre_inset=0.025,
    handle_color="chrome", mirror_color=None, trim="plastic_black",
    front=(), rear=(), body=(), inside=(), extras=None, extras2=None, door_extras=None, lod_extras=None,
    notes="",
)

INTERIOR = dict(seat="@D:fabric_gray", dash="@D:charcoal", dash2="@D:gray_dark", floor="@D:black",
                wall="@D:charcoal", shelf="@D:gray_dark", door_trim="gray_dark", door_inner="charcoal",
                headliner="@D:gray_light", rear_hip=None, rear_wall=None, cargo=None, steer_tilt=24.0)


class Car:
    def __init__(self, spec):
        s = dict(DEFAULTS)
        s.update(spec)
        it = dict(INTERIOR)
        it.update(spec.get("interior", {}))
        s["interior"] = it
        self.s = s
        self.id = s["id"]
        self.L, self.W, self.H = s["L"], s["W"], s["H"]
        if s.get("cab_H"):          # cab roof height when the vehicle carries a taller box / equipment
            self.H = s["cab_H"]
        if s.get("shell_W"):        # width of the generated shell when a separately built body is wider
            self.W = s["shell_W"]
        self.r = s["wheel_r"]
        self.clr = s["clearance"]
        self.c = s["c"]
        lip = s["arch_lip"]
        self.W2 = self.W * 0.5 - (lip["proud"] if lip else 0.0) - s.get("side_proud", 0.0)
        self.ra = self.r + s["arch_gap"]
        self.ra_o = self.ra + s["c_low"]
        if s["well_depth"] is None:
            s["well_depth"] = max(s["wheel_w"], s["wheel_w_r"] or 0.0) + 0.20
        if s["sill_z"] is None:
            s["sill_z"] = self.clr + 0.12
        if s["floor_z"] is None:
            s["floor_z"] = s["sill_z"] - 0.04
        self.axle_f, self.axle_r = s["axle_f"], s["axle_r"]
        self.marks = {}
        self._end = 0
        # ---- outline
        self.up = self._upper()
        up = self.up
        bi = [i for i, p in enumerate(up) if p["tag"] == "belt"]
        self.has_gh = bool(bi) and ("gh" in s)
        if bi:
            self.belt_pts = [(up[i]["y"], up[i]["z"]) for i in range(bi[0], bi[-1] + 2)]
            self.yc, self.zc = self.belt_pts[0]
            self.yd, self.zd = self.belt_pts[-1]
            self._belt_k = sorted(self.belt_pts)
        ti = [i for i, p in enumerate(up[:-1]) if p["tag"] in TOP_TAGS]
        i0, i1 = ti[0], ti[-1]
        self.nose_pts = sorted((p["z"], p["y"], p["c"]) for p in up[:i0 + 1])
        self.tail_pts = sorted((p["z"], p["y"], p["c"]) for p in up[i1 + 1:])
        self.hood_seg = None
        best = 0.0
        for a, b in zip(up, up[1:]):
            if a["tag"] == "hood" and abs(a["y"] - b["y"]) > best:
                best = abs(a["y"] - b["y"])
                self.hood_seg = ((a["y"], a["z"]), (b["y"], b["z"]))
        self.deck_end = (up[i1 + 1]["y"], up[i1 + 1]["z"])
        self.y_front = max(p["y"] for p in up)
        self.y_rear = min(p["y"] for p in up)
        ar = s.get("shell_arches")
        if ar is None:
            ar = [self.axle_r, self.axle_f]
        self.arches = sorted(a for a in ar if self.y_rear + 0.2 < a < self.y_front - 0.2)
        doors = s.get("doors") or []
        self.notch = (max(d[0] for d in doors), min(d[1] for d in doors)) if doors else None
        self.waist = s["waist_z"] if s["waist_z"] is not None else self.clr + 0.5 * (self._belt_min() - self.clr)
        self.rocker_z = s["rocker_z"] if s["rocker_z"] is not None else self.clr + 0.075
        self.sec = [(self.clr, 1.0 - s["tuck"] / self.W2), (self.waist, 1.0)]
        self.z_cuts = [self.waist] + ([self.rocker_z] if self.rocker_z else [])
        self._plan()
        self.loop = self._loop(False)
        self.loop_lod = self._loop(True)
        if self.has_gh:
            self._gh()
        fa = [a for a in self.arches if a > 0.0]
        self.y_fw = min(self.yc, (max(fa) - self.ra_o - 0.02) if fa else self.yc) if bi else 0.0
        if bi and it.get("firewall") is not None:      # cab-over layouts: the cab floor is above the wheels
            self.y_fw = it["firewall"]
        self.hip = it.get("hip")
        self.track_f = 2.0 * (self.W2 - s["tyre_inset"] - s["wheel_w"] * 0.5)
        wr = s["wheel_w_r"] or s["wheel_w"]
        self.track_r = 2.0 * (self.W2 - s["tyre_inset"] - wr * 0.5)
        if s.get("track"):
            self.track_f = self.track_r = s["track"]
        if s.get("track_r"):
            self.track_r = s["track_r"]

    # ------------------------------------------------------------------ profile
    def _belt_min(self):
        return min(z for (_y, z) in self.belt_pts) if hasattr(self, "belt_pts") else self.H * 0.6

    def _upper(self):
        s = self.s
        raw = s["upper"]
        up = []
        for k, t in enumerate(raw):
            tag, col = t[2], None
            if ":" in tag:
                tag, col = tag.split(":", 1)
            cc = t[3] if len(t) > 3 else (s["c_low"] if k in (0, len(raw) - 1) else s["c"])
            up.append(dict(y=float(t[0]), z=float(t[1]), tag=tag, col=col, c=cc))
        up[-1]["tag"] = "under"
        up[-1]["col"] = None
        return up

    def _arch_pts(self, ya):
        s = self.s
        r, ra, clr = self.r, self.ra, self.clr
        n = s["arch_segs"]
        pw_ = s["arch_pow"]
        pts = []
        if pw_ <= 2.01:
            beta = math.asin(max(-1.0, min(1.0, (r - clr) / ra)))
            for k in range(n + 1):
                th = (math.pi + beta) + (-beta - (math.pi + beta)) * k / n
                pts.append((ya + ra * math.cos(th), r + ra * math.sin(th)))
            pts[0] = (pts[0][0], clr)
            pts[-1] = (pts[-1][0], clr)
        else:
            e = 2.0 / pw_
            pts.append((ya - ra, clr))
            m = n - 2
            for k in range(m + 1):
                th = math.pi - math.pi * k / m
                cx, sz = math.cos(th), math.sin(th)
                pts.append((ya + ra * math.copysign(abs(cx) ** e, cx), r + ra * abs(sz) ** e))
            pts.append((ya + ra, clr))
        return pts

    def _insert(self, up, yv, flag):
        for i in range(len(up) - 1):
            a, b = up[i], up[i + 1]
            if a["tag"] not in OPEN_TAGS:
                continue
            if abs(a["y"] - yv) < 1e-5:
                a[flag] = True
                return
            if b["y"] + 1e-5 < yv < a["y"]:
                t = (a["y"] - yv) / (a["y"] - b["y"])
                p = dict(y=yv, z=lerp(a["z"], b["z"], t), tag=a["tag"], col=a["col"], c=lerp(a["c"], b["c"], t))
                p[flag] = True
                up.insert(i + 1, p)
                return
            if abs(b["y"] - yv) < 1e-5:
                b[flag] = True
                return
        raise ValueError("%s: door edge y=%s is not on the belt" % (self.id, yv))

    def _loop(self, lod):
        s = self.s
        up = [dict(p) for p in self.up]
        low = []
        if not lod:
            if self.notch:
                self._insert(up, self.notch[0], "notch")
                self._insert(up, self.notch[1], "notch_r")
            for ai, ya in enumerate(self.arches):
                pts = self._arch_pts(ya)
                for k, (y, z) in enumerate(pts):
                    low.append(dict(y=y, z=z, tag=("arch" if k < len(pts) - 1 else "under"), col=None,
                                    c=s["c_low"], arch=ai, ak=k))
        loop = up + low
        q = offset_closed([(p["y"], p["z"]) for p in loop], [p["c"] for p in loop])
        for p, qq in zip(loop, q):
            p["Q"] = qq
        return loop

    def _plan(self):
        s = self.s
        if s["plan"]:
            self.plan = sorted(s["plan"])
        else:
            yF, yR = self.y_front, self.y_rear
            fa = [a for a in self.arches if a > 0.0]
            rr = [a for a in self.arches if a <= 0.0]
            yf0 = (max(fa) + self.ra_o + 0.03) if fa else yF - 0.6
            yr0 = (min(rr) - self.ra_o - 0.03) if rr else yR + 0.5
            kn = []
            Lr = yr0 - yR
            tr, tf = s["taper_r"], s["taper_f"]
            if Lr > 0.42:
                kn += [(yR, 1.0 - tr), (yR + 0.2, 1.0 - 0.42 * tr), (yr0, 1.0)]
            elif Lr > 0.1 and tr > 0:
                kn += [(yR, 1.0 - tr * 0.8 * Lr / 0.42), (yr0, 1.0)]
            else:
                kn += [(yR, 1.0)]
            Lf = yF - yf0
            if Lf > 0.42:
                kn += [(yf0, 1.0), (yF - 0.2, 1.0 - 0.42 * tf), (yF, 1.0 - tf)]
            elif Lf > 0.1 and tf > 0:
                kn += [(yf0, 1.0), (yF, 1.0 - tf * 0.8 * Lf / 0.42)]
            else:
                kn += [(yF, 1.0)]
            self.plan = kn
        self.plan_cuts = [y for (y, _v) in self.plan[1:-1]]

    def sx(self, y, z, plan_only=False):
        v = pw(y, self.plan)
        if not plan_only:
            v *= pw(z, self.sec)
        return v

    def hw(self, y, z):
        """Half width of the finished body at (y, z)."""
        return self.W2 * self.sx(y, z)

    def belt_z(self, y):
        return pw(y, self._belt_k)

    def nose_y(self, z):
        return pw(z, [(a, b) for (a, b, _c) in self.nose_pts])

    def tail_y(self, z):
        return pw(z, [(a, b) for (a, b, _c) in self.tail_pts])

    def ey(self, z):
        """Y of the nose / tail surface at height z in the current end frame (outward = +Y)."""
        return self.nose_y(z) if self._end > 0 else -self.tail_y(z)

    def ec(self, z):
        pts = self.nose_pts if self._end > 0 else self.tail_pts
        return pw(z, [(a, c) for (a, _b, c) in pts])

    def rake(self, z0, z1):
        return math.degrees(math.atan2(self.ey(z0) - self.ey(z1), z1 - z0))

    def arch_edge(self):
        """Y (end frame) of the outer edge of the nearest wheel-arch opening."""
        if self._end > 0:
            return max(self.arches) + self.ra_o
        return -(min(self.arches) - self.ra_o)

    # ------------------------------------------------------------------ conform
    @contextmanager
    def conforming(self, mb, cut_z=True, rocker=False, plan_only=False):
        bm = mb.bm
        ov, oe, of = set(bm.verts), set(bm.edges), set(bm.faces)
        yield
        geom = ([v for v in bm.verts if v not in ov] + [e for e in bm.edges if e not in oe] +
                [f for f in bm.faces if f not in of])
        cuts = [((0.0, y, 0.0), (0.0, 1.0, 0.0)) for y in self.plan_cuts]
        if cut_z:
            cuts += [((0.0, 0.0, z), (0.0, 0.0, 1.0)) for z in self.z_cuts]
        for co, no in cuts:
            r = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no,
                                       clear_inner=False, clear_outer=False)
            geom = r["geom"]
        faces = []
        for g in geom:
            if isinstance(g, bmesh.types.BMVert):
                g.co.x *= self.sx(g.co.y, g.co.z, plan_only)
            elif isinstance(g, bmesh.types.BMFace):
                faces.append(g)
        if rocker and self.rocker_z:
            lim = self.rocker_z + 1e-4
            slots = [i for i, m in enumerate(mb.slots) if m in ("Paint1", "Paint2")]
            low = [f for f in faces if f.material_index in slots and max(v.co.z for v in f.verts) <= lim]
            mb.paint(low, "plastic_black")

    # ------------------------------------------------------------------ shell
    def _segcol(self, p):
        return p["col"] if p["col"] else TAG_COLORS.get(p["tag"], self.s["paint"])

    def shell(self, mb, lod=False):
        s = self.s
        W2 = self.W2
        lw, wd, zs = s["ledge_w"], s["well_depth"], s["sill_z"]
        loop = self.loop_lod if lod else self.loop
        n = len(loop)
        paint = s["paint"]

        def QR(p):
            return (W2, p["Q"][0], p["Q"][1])

        def T(p, sg=1):
            return (sg * (W2 - p["c"]), p["y"], p["z"])

        def X(p, d, sg=1):
            return (sg * (W2 - d), p["y"], p["z"])

        for sxx in (1, -1):
            with mb.at(scale=(sxx, 1, 1)):
                pts = []
                for i, p in enumerate(loop):
                    pts.append(QR(p))
                    if p.get("notch"):
                        q = loop[i + 1]
                        pts.append((W2, p["y"], zs))
                        pts.append((W2, q["y"], zs))
                P(mb, pts, paint)
                for i, p in enumerate(loop):
                    q = loop[(i + 1) % n]
                    if p.get("notch"):
                        continue
                    tag = p["tag"]
                    if p["c"] > 1e-6 or q["c"] > 1e-6:
                        P(mb, [QR(p), T(p), T(q), QR(q)], "plastic_black" if tag == "valance" else paint)
                    if tag in OPEN_TAGS and not lod:
                        P(mb, [T(p), X(p, lw), X(q, lw), T(q)], self._segcol(p))
                    elif tag == "arch":
                        P(mb, [T(p), X(p, wd), X(q, wd), T(q)], "black")
                if not lod:
                    for ai in range(len(self.arches)):
                        ap = [p for p in loop if p.get("arch") == ai]
                        P(mb, [X(p, wd) for p in reversed(ap)], "black")
                    if self.notch:
                        a = next(p for p in loop if p.get("notch"))
                        b = next(p for p in loop if p.get("notch_r"))
                        jc = "black"
                        P(mb, [(W2, a["y"], zs), QR(a), T(a), X(a, lw), (W2 - lw, a["y"], zs)], jc)
                        P(mb, [(W2 - lw, b["y"], zs), X(b, lw), T(b), QR(b), (W2, b["y"], zs)], jc)
                        P(mb, [(W2, a["y"], zs), (W2 - lw, a["y"], zs), (W2 - lw, b["y"], zs), (W2, b["y"], zs)],
                          "charcoal")
                    if s["arch_lip"]:
                        self._arch_lips(mb)
        for i, p in enumerate(loop):
            q = loop[(i + 1) % n]
            tag = p["tag"]
            if p.get("notch") or tag == "arch" or (tag in OPEN_TAGS and not lod):
                continue
            P(mb, [T(p), T(p, -1), T(q, -1), T(q)], self._segcol(p))
        if not lod:
            for ai in range(len(self.arches)):
                ap = [p for p in loop if p.get("arch") == ai]
                a, b = ap[0], ap[-1]
                P(mb, [X(a, wd), X(a, wd, -1), X(b, wd, -1), X(b, wd)], "plastic_black")

    def _arch_lips(self, mb):
        """Proud flare ring around every wheel-arch opening (right side; called inside the mirror frame)."""
        lip = self.s["arch_lip"]
        w, pr, col = lip.get("w", 0.05), lip["proud"], lip.get("color", self.s["paint"])
        W2 = self.W2
        for ai, ya in enumerate(self.arches):
            ap = [p for p in self.loop if p.get("arch") == ai]
            inner, outer, outer2 = [], [], []
            for p in ap:
                qy, qz = p["Q"]
                dy, dz = qy - ya, qz - self.r
                l = math.hypot(dy, dz) or 1.0
                dy, dz = dy / l, dz / l
                if qz <= self.clr + 0.03:       # feet: keep the lip ends level with the sill
                    dy, dz = math.copysign(1.0, dy), 0.0
                inner.append((qy, qz))
                outer.append((qy + dy * w, qz + dz * w))
                outer2.append((qy + dy * (w + pr), qz + dz * (w + pr)))
            for k in range(len(ap) - 1):
                a, b = k, k + 1
                P(mb, [(W2 + pr, inner[a][0], inner[a][1]), (W2 + pr, inner[b][0], inner[b][1]),
                       (W2 + pr, outer[b][0], outer[b][1]), (W2 + pr, outer[a][0], outer[a][1])], col)
                P(mb, [(W2 + pr, outer[a][0], outer[a][1]), (W2 + pr, outer[b][0], outer[b][1]),
                       (W2, outer2[b][0], outer2[b][1]), (W2, outer2[a][0], outer2[a][1])], col)
                P(mb, [(W2, inner[a][0], inner[a][1]), (W2, inner[b][0], inner[b][1]),
                       (W2 + pr, inner[b][0], inner[b][1]), (W2 + pr, inner[a][0], inner[a][1])], col)

    # ------------------------------------------------------------------ greenhouse
    def _gh(self):
        g = self.s["gh"]
        self.yrf, self.zrf = g["roof_f"]
        self.yrr, self.zrr = g["roof_r"]
        self.xb = self.W2 - self.c - 0.012
        zlo = min(self.zc, self.zd)
        zhi = max(self.zrf, self.zrr)
        self.gz0 = zlo
        self.gk = g.get("tumble", 0.14) / (zhi - zlo)
        awb, awt = g.get("a_w", (0.125, 0.11))
        if "c_front" in g:
            cwb, cwt = g["c_front"] - self.yd, g["c_front"] - self.yrr
        else:
            cwb, cwt = g.get("c_w", (0.14, 0.12))
        self.a_w, self.c_w = (awb, awt), (cwb, cwt)
        fb = (self.yc - awb, self.belt_z(self.yc - awb))
        ft = (self.yrf - awt, self.roof_z(self.yrf - awt))
        rt = (self.yrr + cwt, self.roof_z(self.yrr + cwt))
        rb = (self.yd + cwb, self.belt_z(self.yd + cwb))
        mid = [p for p in sorted(self.belt_pts) if rb[0] + 1e-4 < p[0] < fb[0] - 1e-4]
        self.dlo = [fb, ft, rt, rb] + mid

    def xg(self, z):
        """X of the (right) side-glass plane at height z."""
        return self.xb - self.gk * (z - self.gz0)

    def roof_z(self, y):
        t = (y - self.yrr) / (self.yrf - self.yrr)
        return lerp(self.zrr, self.zrf, t)

    def _roof_top(self):
        g = self.s["gh"]
        if g.get("roof_top"):
            return list(g["roof_top"])
        H = self.H
        yrf, zrf, yrr, zrr = self.yrf, self.zrf, self.yrr, self.zrr
        Lr = yrf - yrr
        d1, d2 = min(0.16, 0.16 * Lr), min(0.44, 0.34 * Lr)
        top = [(yrf + 0.03, zrf + 0.014), (yrf - d1, zrf + 0.7 * (H - zrf)), (yrf - d2, H)]
        if Lr > 1.2:
            top.append((yrr + d2, H))
        top += [(yrr + d1, zrr + 0.7 * (H - zrr)), (yrr - 0.03, zrr + 0.014)]
        return top

    def _pillar(self, mb, end, w, wf, color, p=0.008, tin=0.055):
        if end > 0:
            ends = ((self.yc, self.zc, w[0]), (self.yrf, self.zrf, w[1]))
        else:
            ends = ((self.yd, self.zd, w[0]), (self.yrr, self.zrr, w[1]))
        rings = []
        for (y, z, ws) in ends:
            x = self.xg(z)
            p0 = (x + p, y + end * p, z)
            p1 = (x + p, y - end * ws, z)
            p2 = (x - tin, y - end * ws, z)
            p3 = (x - wf, y + end * p, z)
            rings.append([p0, p3, p2, p1] if end > 0 else [p0, p1, p2, p3])
        ring_loft(mb, rings, color, cap0=False, cap1=False)

    def pane(self, mb, Wp, frame=0.028, frame_color="plastic_black", po=0.004, ti=0.022, glass=GLASS):
        """Window pane in the side-glass plane: polygon (y, z) CCW seen from +X, with a slim frame."""
        Wp = clean_poly(Wp, 0.035)
        if len(Wp) < 3:
            return

        def G(p, dx=0.0):
            return (self.xg(p[1]) + dx, p[0], p[1])
        if frame:
            Wi = offset_closed(Wp, frame)
            n = len(Wp)
            for k in range(n):
                k2 = (k + 1) % n
                P(mb, [G(Wp[k], po), G(Wp[k2], po), G(Wi[k2], po), G(Wi[k], po)], frame_color)
                P(mb, [G(Wi[k], -ti), G(Wi[k2], -ti), G(Wp[k2], -ti), G(Wp[k], -ti)], frame_color)
                P(mb, [G(Wi[k], po), G(Wi[k2], po), G(Wi[k2], -ti), G(Wi[k], -ti)], frame_color)
                P(mb, [G(Wp[k], po), G(Wp[k], -ti), G(Wp[k2], -ti), G(Wp[k2], po)], frame_color)
            Wg = offset_closed(Wp, frame - 0.006)
        else:
            Wg = Wp
        if glass:
            P(mb, [G(p) for p in Wg], glass)

    def greenhouse(self, mb):
        if not self.has_gh:
            return
        s = self.s
        g = s["gh"]
        it = s["interior"]
        pc = g.get("pillar_color", s["paint"])
        roofc = g.get("roof_color", s["paint"])
        af = g.get("a_face", 0.07)
        cf = g.get("c_face", 0.07)
        doors = s.get("doors") or []
        splits = [d[1] for d in doors[:-1]]
        for sxx in (1, -1):
            with mb.at(scale=(sxx, 1, 1)):
                self._pillar(mb, 1, self.a_w, af, pc)
                self._pillar(mb, -1, self.c_w, cf, g.get("c_color", pc))
                for ys in splits:
                    bw = g.get("b_w", 0.09) * 0.5
                    rings = []
                    for z in (self.belt_z(ys), self.roof_z(ys)):
                        x = self.xg(z)
                        rings.append([(x - 0.008, ys + bw, z), (x - 0.05, ys + bw, z), (x - 0.05, ys - bw, z),
                                      (x - 0.008, ys - bw, z)])
                    ring_loft(mb, rings, "plastic_black", cap0=False, cap1=False)
                for fx in g.get("fixed", ()):
                    Wp = clip_poly(self.dlo, 0, lo=fx[1], hi=fx[0])
                    gl = fx[2] if len(fx) > 2 else GLASS
                    # opaque filler panels (mirror sails) need no frame
                    self.pane(mb, Wp, frame=(g.get("fixed_frame", 0.022) if gl == GLASS else 0.0), glass=gl,
                              frame_color=g.get("frame_color", "plastic_black"))
                    if len(fx) > 3 and fx[3]:            # opaque panel: inner face colour
                        Wq = clean_poly(Wp, 0.035)
                        if len(Wq) >= 3:
                            P(mb, [(self.xg(p[1]) - 0.004, p[0], p[1]) for p in reversed(Wq)], fx[3])
                for (yp, wpost, colp) in g.get("posts", ()):
                    rings = []
                    for z in (self.belt_z(yp), self.roof_z(yp)):
                        x = self.xg(z)
                        rings.append([(x + 0.008, yp + wpost / 2, z), (x - 0.05, yp + wpost / 2, z),
                                      (x - 0.05, yp - wpost / 2, z), (x + 0.008, yp - wpost / 2, z)])
                    ring_loft(mb, rings, colp or pc, cap0=False, cap1=False)
        # roof slab (crowned, chamfered, headliner underneath)
        rings = []
        for (y, zt) in sorted(self._roof_top()):
            yy = min(max(y, self.yrr), self.yrf)
            zb = min(self.roof_z(yy), zt - 0.012)
            cr = min(g.get("roof_c", 0.035), 0.6 * (zt - zb))
            xsb = self.xg(zb) + 0.014
            xst = xsb - self.gk * 1.6 * (zt - cr - zb)
            rings.append([(xst, y, zt - cr), (xsb, y, zb), (-xsb, y, zb), (-xst, y, zt - cr),
                          (-(xst - cr), y, zt), (xst - cr, y, zt)])
        ring_loft(mb, rings, roofc, edge_colors=[roofc, it["headliner"], roofc, roofc, roofc, roofc])
        # windscreen + rear window (slightly tucked under the pillars, extended 2 cm below the belt)
        if g.get("windscreen", True):
            uy, uz = self.yrf - self.yc, self.zrf - self.zc
            ul = math.hypot(uy, uz)
            yb, zb = self.yc - uy / ul * 0.02, self.zc - uz / ul * 0.02
            xb_, xt_ = self.xg(self.zc) - af + 0.012, self.xg(self.zrf) - af + 0.012
            P(mb, [(xb_, yb, zb), (-xb_, yb, zb), (-xt_, self.yrf, self.zrf), (xt_, self.yrf, self.zrf)], GLASS)
            # wipers
            phi = math.degrees(math.atan2(-uy, uz))
            with mb.at((0, self.yc, self.zc), rot=(phi, 0, 0)):
                for wx in (-0.42, 0.20):
                    mb.box((0.46, 0.012, 0.022), (wx * self.W2 / 0.93, 0.012, 0.085), "black", rot=(0, -11, 0))
        if g.get("rear_glass", True):
            uy, uz = self.yrr - self.yd, self.zrr - self.zd
            ul = math.hypot(uy, uz)
            yb, zb = self.yd - uy / ul * 0.02, self.zd - uz / ul * 0.02
            xb_, xt_ = self.xg(self.zd) - cf + 0.012, self.xg(self.zrr) - cf + 0.012
            P(mb, [(-xb_, yb, zb), (xb_, yb, zb), (xt_, self.yrr, self.zrr), (-xt_, self.yrr, self.zrr)], GLASS)

    # ------------------------------------------------------------------ interior
    def tub_line(self):
        """Cabin section line (y, z, colour of the segment starting there) from the cowl edge to the deck edge."""
        s = self.s
        it = s["interior"]
        zf = s["floor_z"]
        zdt = self.zc - 0.035
        yfw = self.y_fw
        yrw = self.rear_wall_y()
        line = [(self.yc, self.zc, "@D:black"), (self.yc, zdt, it["dash"]), (yfw, zdt, "@D:black"),
                (yfw, zf, it["floor"])]
        cg = it["cargo"]
        if cg:
            zc = cg["z"]
            ytw = self.yd
            line += [(yrw, zf, it["wall"]), (yrw, zc, it["shelf"]), (ytw, zc, it["wall"]), (ytw, self.zd, None)]
        elif yrw > self.yd + 0.02:
            zsh = self.zd - 0.03
            line += [(yrw, zf, it["wall"]), (yrw, zsh, it["shelf"]), (self.yd, zsh, "@D:black"),
                     (self.yd, self.zd, None)]
        else:
            line += [(self.yd, zf, it["wall"]), (self.yd, self.zd, None)]
        return line

    def rear_wall_y(self):
        it = self.s["interior"]
        if it["rear_wall"] is not None:
            return it["rear_wall"]
        if it["rear_hip"]:
            return it["rear_hip"][1] - 0.46
        return self.hip[1] - 0.52

    def tub(self, mb):
        if not self.has_gh:
            return
        s = self.s
        it = s["interior"]
        xi = self.W2 - s["ledge_w"]
        zf, zs = s["floor_z"], s["sill_z"]
        line = self.tub_line()
        for a, b in zip(line, line[1:]):
            P(mb, [(xi, a[0], a[1]), (-xi, a[0], a[1]), (-xi, b[0], b[1]), (xi, b[0], b[1])], a[2])
        poly = [(p[0], p[1]) for p in line] + [p for p in sorted(self.belt_pts, reverse=False)[1:-1]]
        poly = clean_poly(poly)
        doors = s.get("doors") or []
        for sxx in (1, -1):
            with mb.at(scale=(sxx, 1, 1)):
                if self.notch:
                    ynf, ynr = self.notch
                    for pl in (clip_poly(poly, 0, lo=ynf), clip_poly(poly, 0, hi=ynr)):
                        P(mb, [(xi, y, z) for (y, z) in pl], it["wall"])
                    P(mb, [(xi, ynf, zf), (xi, ynr, zf), (xi, ynr, zs), (xi, ynf, zs)], it["wall"])
                    for d in doors[:-1]:      # lower B post behind the door shut line
                        ys = d[1]
                        zb = self.belt_z(ys)
                        mb.box((0.03, 0.10, zb - zs), (self.W2 - s["door_t"] - 0.037, ys, (zb + zs) * 0.5),
                               "charcoal")
                else:
                    P(mb, [(xi, y, z) for (y, z) in poly], it["wall"])

    def seat(self, mb, x, hy, hz, w, color, tilt=18.0, back=0.70, headrest=True, bevel=0.025):
        zf = self.s["floor_z"]
        ztop = max(hz - 0.22, zf + 0.07)
        th = min(0.14, ztop - zf)
        mb.box((w, 0.50, th), (x, hy + 0.12, ztop - th * 0.5), color, bevel=min(bevel, th * 0.3))
        if ztop - th - zf > 0.03:
            mb.box((w * 0.7, 0.36, ztop - th - zf), (x, hy + 0.10, (ztop - th + zf) * 0.5), "@D:black")
        by, bz = hy - 0.17, ztop - 0.03
        mb.box((w, 0.11, back), (x, by, bz), color, rot=(tilt, 0, 0), bevel=bevel, base=True, taper=(0.9, 0.8))
        if headrest:
            st, ct = math.sin(math.radians(tilt)), math.cos(math.radians(tilt))
            d = back + 0.11
            mb.box((min(0.27, w * 0.6), 0.09, 0.17), (x, by - st * d, bz + ct * d), color, rot=(tilt, 0, 0),
                   bevel=0.02)

    def furniture(self, mb):
        if not self.has_gh or not self.hip:
            return
        s = self.s
        it = s["interior"]
        hx, hy, hz = self.hip
        zf = s["floor_z"]
        ps = self.sx(hy, self.zc, True)        # plan scale at the cab (1.0 unless the cab is narrower than the body)
        xi = (self.W2 - s["ledge_w"]) * ps
        zdt = self.zc - 0.035
        yfw = self.y_fw
        seatc = it["seat"]
        # dashboard
        ydr = min(hy + 0.62, yfw - 0.2)
        dl = yfw - ydr
        dh = min(0.32, zdt - zf - 0.2)
        lite = bool(it.get("lite"))          # economy: no bevels on the small / half-hidden interior blocks
        lite2 = it.get("lite") == 2          # ... and none on seats / dashboard either (big service vehicles)

        def bv(b):
            return 0.0 if lite else b

        def bv2(b):
            return 0.0 if lite2 else b
        mb.box((2 * xi - 0.02, dl, dh), (0, (yfw + ydr) * 0.5, zdt - dh * 0.5), it["dash"], bevel=bv2(0.03),
               colors={"-y": it["dash2"]})
        mb.box((0.36, 0.17, 0.075), (-hx, ydr + 0.11, zdt + 0.02), it["dash"], bevel=bv(0.02))       # binnacle
        mb.box((0.26, 0.09, dh + 0.12), (0, ydr - 0.01, zdt - 0.06 - (dh + 0.12) * 0.5), it["dash2"], bevel=bv(0.015))
        # centre console + lever
        ch = max(0.10, min(hz - 0.12 - zf, it.get("console_h", 9.0)))
        y0c, y1c = ydr - 0.03, hy - 0.30
        mb.box((0.20, y0c - y1c, ch), (0, (y0c + y1c) * 0.5, zf + ch * 0.5), it["dash"], bevel=bv(0.02))
        mb.box((0.03, 0.03, 0.10), (0, hy + 0.22, zf + ch + 0.04), "@D:black", rot=(-12, 0, 0))
        mb.box((0.05, 0.05, 0.05), (0, hy + 0.20, zf + ch + 0.10), "chrome", bevel=bv(0.012))
        # front seats
        sw = min(0.52, 2 * hx - 0.22)
        for sxx in (1, -1):
            self.seat(mb, sxx * hx, hy, hz, sw, seatc, tilt=it.get("seat_tilt", 18.0), bevel=bv2(0.025))
        # rear bench
        rh = it["rear_hip"]
        if rh:
            rx, ry, rz = rh
            ztop = max(rz - 0.22, zf + 0.07)
            th = min(0.15, ztop - zf)
            bw = 2 * xi - 0.08
            mb.box((bw, 0.50, th), (0, ry + 0.12, ztop - th * 0.5), seatc, bevel=bv2(min(0.025, th * 0.3)))
            mb.box((bw, 0.12, 0.62), (0, ry - 0.17, ztop - 0.03), seatc, rot=(22, 0, 0), bevel=bv2(0.025), base=True,
                   taper=(0.97, 0.8))
            st, ct = math.sin(math.radians(22)), math.cos(math.radians(22))
            for sxx in (1, -1):
                mb.box((0.25, 0.09, 0.15), (sxx * rx, ry - 0.17 - st * 0.70, ztop - 0.03 + ct * 0.70), seatc,
                       rot=(22, 0, 0), bevel=bv(0.02))
        # steering column (the wheel itself is the separate `steering` part)
        hub = self.steer_hub()
        tilt = it["steer_tilt"]
        st, ct = math.sin(math.radians(tilt)), math.cos(math.radians(tilt))
        cl = max(0.12, (ydr + 0.06 - hub[1]) / ct)
        mb.cyl(0.028, cl, (hub[0], hub[1] + ct * (cl * 0.5 + 0.02), hub[2] - st * (cl * 0.5 + 0.02)), "@D:black",
               axis="Y", rot=(-tilt, 0, 0), segs=6)
        # rear-view mirror
        mb.box((0.20, 0.025, 0.06), (0, self.yrf + 0.03, self.zrf - 0.075), "black", bevel=bv(0.008))
        mb.box((0.02, 0.02, 0.06), (0, self.yrf + 0.03, self.zrf - 0.03), "black")
        # covers over wheel housings that intrude into the cabin
        wd = s["well_depth"]
        yrw = self.rear_wall_y()
        zones = [(yrw, yfw, zf)]
        if it["cargo"]:
            zones.append((self.yd, yrw, it["cargo"]["z"]))
        for ya in self.arches:
            top = self.r + self.ra + 0.025
            for (zlo, zhi, zb) in zones:
                lo, hi = max(ya - self.ra - 0.03, zlo), min(ya + self.ra + 0.03, zhi)
                if hi - lo > 0.05 and top > zb + 0.04:
                    x0, x1 = (self.W2 - wd - 0.025) * ps, xi + 0.004
                    for sxx in (1, -1):
                        mb.box((x1 - x0, hi - lo, top - zb), (sxx * (x0 + x1) * 0.5, (lo + hi) * 0.5, (top + zb) * 0.5),
                               it["wall"])

    def steer_hub(self):
        hx, hy, hz = self.hip
        it = self.s["interior"]
        return it.get("steer", (-hx, hy + 0.40, hz + 0.31))

    def steering(self):
        if not self.hip:
            return None
        it = self.s["interior"]
        R = it.get("steer_r", 0.18)
        tr = 0.017
        n = 10
        mb = K.MB()
        rings = []
        for k in range(n + 1):
            a = 2 * math.pi * k / n
            ca, sa = math.cos(a), math.sin(a)
            rings.append([((R + tr) * ca, 0.0, (R + tr) * sa), (R * ca, -tr, R * sa),
                          ((R - tr) * ca, 0.0, (R - tr) * sa), (R * ca, tr, R * sa)])
        ring_loft(mb, rings, "leather_black", cap0=False, cap1=False)
        mb.box((2 * (R - 0.004), 0.018, 0.036), (0, 0.014, 0.0), "plastic_black")
        mb.box((0.036, 0.018, R - 0.004), (0, 0.014, -(R - 0.004) * 0.5), "plastic_black")
        mb.cyl(0.052, 0.04, (0, 0.012, 0), "plastic_black", axis="Y", segs=8, cap_color="charcoal")
        mb.weld()
        bmesh.ops.recalc_face_normals(mb.bm, faces=mb.bm.faces[:])
        obj = mb.to_object(self.root, "steering")
        obj.location = self.steer_hub()
        obj.rotation_euler = Euler((math.radians(-it["steer_tilt"]), 0.0, 0.0), "XYZ")
        return obj

    # ------------------------------------------------------------------ ops (data-driven details)
    def run_ops(self, mb, ops):
        for op in ops:
            getattr(self, "op_" + op[0])(mb, **(op[1] if len(op) > 1 else {}))

    def op_box(self, mb, size, pos, color, pair=False, **kw):
        for sxx in ((1, -1) if pair else (1,)):
            with mb.at(scale=(sxx, 1, 1)):
                mb.box(size, pos, color, **kw)

    def op_cyl(self, mb, r, h, pos, color, pair=False, **kw):
        for sxx in ((1, -1) if pair else (1,)):
            with mb.at(scale=(sxx, 1, 1)):
                mb.cyl(r, h, pos, color, **kw)

    def op_tube(self, mb, pts, r, color, pair=False, **kw):
        for sxx in ((1, -1) if pair else (1,)):
            with mb.at(scale=(sxx, 1, 1)):
                mb.tube(pts, r, color, **kw)

    def op_strip(self, mb, z0, z1, x0=None, x1=None, side=0.0, proud=0.012, depth=0.03, color="chrome",
                 bevel=0.0, colors=None, sides=(1, -1)):
        """Bar following the nose / tail surface. x0=None: one full-width bar (x1=None: wrapped round both
        corners and `side` metres along the body sides; x1: face only, -x1..x1). Otherwise a mirrored pair from
        lateral x0 to x1, or (x1=None) round the corner plus `side` along the body side."""
        W2 = self.W2

        def path(z):
            yn, cn = self.ey(z), self.ec(z)
            if x0 is None:
                if x1 is not None:
                    return [(-x1, yn), (x1, yn)]
                pts = [(-W2, yn - cn), (-(W2 - cn), yn), (W2 - cn, yn), (W2, yn - cn)]
                if side > 1e-6:
                    pts = [(-W2, yn - cn - side)] + pts + [(W2, yn - cn - side)]
                return pts
            if x1 is not None:
                return [(x0, yn), (x1, yn)]
            pts = [(x0, yn), (W2 - cn, yn), (W2, yn - cn)]
            if side > 1e-6:
                pts.append((W2, yn - cn - side))
            return pts

        if bevel > 1e-6:
            b = min(bevel, (z1 - z0) * 0.45)
            lv = [(z0, proud - b), (z0 + b, proud), (z1 - b, proud), (z1, proud - b)]
        else:
            lv = [(z0, proud), (z1, proud)]
        m = len(path(z0)) - 1
        skip = set(range(m + 1, 2 * m + 1))

        def emit(col):
            rings = []
            for z, p in lv:
                pts = path(z)
                o, i = offset_open(pts, p), offset_open(pts, -depth)
                rings.append([(x, y, z) for (x, y) in reversed(o)] + [(x, y, z) for (x, y) in i])
            ring_loft(mb, rings, col, skip=skip)
        if x0 is None:
            emit(color)
        else:
            for sxx in sides:
                with mb.at(scale=(sxx, 1, 1)):
                    emit(colors[sxx] if colors else color)

    def op_bumper(self, mb, z0, z1, proud=0.03, color=None, bevel=0.03, side=None, depth=0.04, x1=None):
        zm = (z0 + z1) * 0.5
        if side is None:
            side = max(0.0, self.ey(zm) - self.ec(zm) - self.arch_edge() - 0.015)
        self.op_strip(mb, z0, z1, None, x1, side, proud=proud, depth=depth, color=color or self.s["paint"],
                      bevel=bevel)
        self.marks["bumper_f" if self._end > 0 else "bumper_r"] = (0.0, (self.ey(zm) + proud) * self._end, z0)

    def op_lamp(self, mb, kind, z0, z1, x0, x1=None, side=0.0, proud=0.012, depth=0.03, bezel=None):
        col = {"head": "@LightHead", "tail": "@LightTail", "rev": "@LightReverse", "aux": "@LightAux",
               "ind": None}[kind]
        colors = {1: "@LightIndR", -1: "@LightIndL"} if kind == "ind" else None
        if bezel:
            e = 0.014
            self.op_strip(mb, z0 - e, z1 + e, x0 - e, None if x1 is None else x1 + e, side + (e if side > 0 else 0),
                          proud=proud - 0.007, depth=depth, color=bezel)
        self.op_strip(mb, z0, z1, x0, x1, side, proud=proud, depth=depth, color=col, colors=colors)
        key = "light_" + kind
        if kind in ("head", "tail") and key not in self.marks:
            zc = (z0 + z1) * 0.5
            xe = (self.W2 - self.ec(zc)) if x1 is None else x1
            yw = (self.ey(zc) + proud) * self._end
            self.marks[key] = ((x0 + xe) * 0.5 * self.sx(yw, zc), yw, zc)

    def op_ebox(self, mb, x, z, size, color, proud=0.006, bevel=0.0, pair=False, colors=None, pair_colors=None):
        """Box lying on the nose / tail face: size = (width, height, depth); front face `proud` off the surface."""
        w, h, d = size
        rk = self.rake(z - h * 0.5, z + h * 0.5)
        y = self.ey(z) + proud - d * 0.5
        for sxx in ((1, -1) if (pair or pair_colors) else (1,)):
            with mb.at(scale=(sxx, 1, 1)):
                mb.box((w, d, h), (x, y, z), pair_colors[sxx] if pair_colors else color, rot=(rk, 0, 0),
                       bevel=bevel, colors=colors)

    def op_grille(self, mb, z0, z1, w, bars=3, frame="chrome", inner="black", bar="plastic_black", x=0.0,
                  proud=0.004, vertical=0):
        zc, h = (z0 + z1) * 0.5, z1 - z0
        rk = self.rake(z0, z1)
        with mb.at((x, self.ey(zc), zc), rot=(rk, 0, 0)):
            if frame:
                mb.box((w + 0.036, 0.04, h + 0.036), (0, proud - 0.02, 0), frame)
            mb.box((w, 0.04, h), (0, proud + 0.006 - 0.02, 0), inner)
            for k in range(bars):
                zz = -h * 0.5 + h * (k + 1) / (bars + 1)
                mb.box((w - 0.012, 0.014, 0.018), (0, proud + 0.006 + 0.003, zz), bar)
            for k in range(vertical):
                xx = -w * 0.5 + w * (k + 1) / (vertical + 1)
                mb.box((0.018, 0.014, h - 0.012), (xx, proud + 0.006 + 0.004, 0), bar)

    def op_plate(self, mb, z, proud=0.008, x=0.0, size=(0.36, 0.115)):
        self.op_ebox(mb, x, z, (size[0], size[1], 0.016), "white", proud=proud)

    def op_exhaust(self, mb, x, z, r=0.035, length=0.18, out=0.045, twin=0.0, color="chrome", both=False):
        xs = [x] if not twin else [x - twin * 0.5, x + twin * 0.5]
        if both:
            xs = xs + [-v for v in xs]
        y = self.ey(z) + out - length * 0.5
        for xx in xs:
            mb.cyl(r, length, (xx, y, z), color, axis="Y", segs=8, cap_color="black")
        yw = (self.ey(z) + out) * self._end
        self.marks.setdefault("exhaust", (xs[0] * self.sx(yw, z), yw, z))

    def op_sbox(self, mb, y, z, size, color=None, proud=0.006, bevel=0.0, sides=(1, -1), colors=None):
        """Box on the body side (mirrored pair): size = (length_y, height, thickness)."""
        ly, h, th = size
        for sxx in sides:
            with mb.at(scale=(sxx, 1, 1)):
                mb.box((th, ly, h), (self.W2 + proud - th * 0.5, y, z), colors[sxx] if colors else color,
                       bevel=bevel)

    def op_hood_panel(self, mb, inset=0.17, h=0.012, m0=0.03, m1=0.05, color=None, bevel=0.008, taper=None,
                      width=None, z_off=0.0):
        """Thin raised panel on the main bonnet segment (m0: margin at the nose end, m1: at the cowl end)."""
        (ya, za), (yb, zb) = self.hood_seg
        ln = math.hypot(ya - yb, za - zb)
        ang = math.degrees(math.atan2(za - zb, ya - yb))
        w = width if width else 2 * (self.W2 - inset)
        with mb.at((0, yb, zb), rot=(ang, 0, 0)):
            mb.box((w, ln - m0 - m1, h), (0, m1 + (ln - m0 - m1) * 0.5, h * 0.5 - 0.003 + z_off),
                   color or self.s["paint"], bevel=bevel, taper=taper)

    def op_antenna(self, mb, x, y, z, h=0.45, lean=-25.0):
        mb.box((0.012, 0.012, h), (x, y, z), "black", rot=(lean, 0, 0), base=True, taper=(0.4, 0.4))
        mb.box((0.03, 0.04, 0.012), (x, y, z + 0.004), "black")

    # ------------------------------------------------------------------ side bands (stripes, rub strips, checker)
    def bands(self, mb, door=None):
        """spec["bands"] = [dict(y0=front, y1=rear, z0, z1, color, proud=0.008, kind="box"|"checker", cell, colors)].
        door=None: the pieces on the fixed body (both sides); door=(y_rear, y_front): the piece on that door
        (call inside the door's mirror frame).  Body and door pieces line up, so a band runs across the doors."""
        s = self.s
        g = s["door_gap"]
        for b in s.get("bands") or ():
            ya, yb = b["y1"], b["y0"]
            if door is None:
                segs = [(ya, yb)]
                if self.notch and not b.get("body_only"):
                    ynf, ynr = self.notch
                    segs = [(ya, min(yb, ynr - 0.004)), (max(ya, ynf + 0.004), yb)]
            else:
                if b.get("body_only"):
                    continue
                segs = [(max(ya, door[0]), min(yb, door[1]))]
            for (a, c) in segs:
                if c - a < 0.03:
                    continue
                if door is None:
                    for sxx in (b.get("sides") or (1, -1)):
                        with mb.at(scale=(sxx, 1, 1)):
                            self._band_piece(mb, b, a, c)
                else:
                    self._band_piece(mb, b, a, c)

    def _band_piece(self, mb, b, a, c):
        W2 = self.W2
        pr = b.get("proud", 0.008)
        z0, z1 = b["z0"], b.get("z1")
        if b.get("kind") == "checker":
            checker(mb, W2, a, c, z0, rows=b.get("rows", 2), cell=b.get("cell", 0.09), proud=pr,
                    colors=b.get("colors", ("black", "white")))
        else:
            th = pr + 0.006
            mb.box((th, c - a, z1 - z0), (W2 + pr - th * 0.5, (a + c) * 0.5, (z0 + z1) * 0.5), b["color"],
                   bevel=b.get("bevel", 0.0))

    # ------------------------------------------------------------------ doors
    def doors(self):
        s = self.s
        g = s["door_gap"]
        zs = s["sill_z"]
        dl = s.get("doors") or []
        objs = []
        for di, (yf, yr) in enumerate(dl):
            y0 = yf - (g if di == 0 else g * 0.5)
            y1 = yr + (g if di == len(dl) - 1 else g * 0.5)
            for side in (-1, 1):
                name = "door_%s%s" % ("fr"[di], "l" if side < 0 else "r")
                mb = K.MB()
                with self.conforming(mb, cut_z=True):
                    with mb.at(scale=(side, 1, 1)):
                        self._door_geo(mb, di, y0, y1, side)
                        self.bands(mb, (y1, y0))
                if s["door_extras"]:
                    s["door_extras"](self, mb, di, side, y0, y1)
                zmid = (zs + self.belt_z(y0)) * 0.5
                objs.append(mb.to_object(self.root, name, origin=(side * self.hw(y0, zmid), y0, zmid)))
        return objs

    def _door_geo(self, mb, di, y0, y1, side):
        s = self.s
        it = s["interior"]
        W2, c, t = self.W2, self.c, s["door_t"]
        zs = s["sill_z"] + 0.006
        paint = s["door_paint"] or s["paint"]

        def ring(y):
            zp = self.belt_z(y)
            return [(W2, y, zp - c), (W2, y, zs), (W2 - t, y, zs), (W2 - t, y, zp), (W2 - c, y, zp)]
        ring_loft(mb, [ring(y1), ring(y0)], paint,
                  edge_colors=[paint, "black", it["door_inner"], "plastic_black", paint], cap_colors=("black", "black"))
        ym = (y0 + y1) * 0.5
        zb = self.belt_z(ym)
        ln = y0 - y1
        # inner trim panel + armrest
        mb.box((0.022, ln - 0.10, zb - zs - 0.14), (W2 - t - 0.009, ym, (zb + zs) * 0.5 + 0.01), it["door_trim"])
        mb.box((0.05, min(0.45, ln * 0.5), 0.045), (W2 - t - 0.035, ym - 0.03, zs + (zb - zs) * 0.62), it["door_inner"])
        # outer handle
        mb.box((0.024, 0.15, 0.036), (W2 + 0.005, y1 + 0.17, zb - 0.105), s["handle_color"], bevel=0.008)
        # glass + frame
        if self.has_gh and not s.get("door_solid"):
            Wp = clip_poly(self.dlo, 0, lo=y1 + 0.004, hi=y0 - 0.004)
            self.pane(mb, Wp, frame=s["gh"].get("door_frame", 0.028),
                      frame_color=s["gh"].get("frame_color", "plastic_black"))
        # mirror on the front doors
        if di == 0 and s.get("mirrors", True):
            mc = s["mirror_color"] or paint
            ymr = min(y0 - 0.09, self.yc - self.a_w[0] - 0.02) if self.has_gh else y0 - 0.09
            md = s.get("mirror_dims")          # truck mirrors: (sx, sy, sz, arm length, z offset)
            if md:
                mb.box((md[3] + 0.03, 0.04, 0.04), (W2 + md[3] * 0.5 - 0.015, ymr, zb + 0.05), "plastic_black")
                mb.box(md[:3], (W2 + md[3], ymr - 0.005, zb + md[4]), mc, colors={"-y": "mirror"})
            else:
                mb.box((0.10, 0.05, 0.035), (W2 - 0.015, ymr, zb + 0.035), "plastic_black")
                mb.box((0.17, 0.08, 0.115), (W2 + 0.095, ymr - 0.005, zb + 0.085), mc, bevel=0.022,
                       colors={"-y": "mirror"})

    # ------------------------------------------------------------------ wheels
    def wheels(self):
        s = self.s
        root = self.root
        r = self.r
        wf = s["wheel_w"]
        wr = s["wheel_w_r"] or wf
        kw = dict(rim_ratio=s["rim_ratio"], rim_color=s["rim_color"], cap_color=s["cap_color"],
                  segs=s.get("wheel_segs", 14), disc_color=s.get("disc_color", "gunmetal"))
        fl = make_wheel(root, "wheel_fl", r, wf, s["rim"], **kw)
        fl.location = (-self.track_f * 0.5, self.axle_f, r)
        K.link_copy(fl, root, "wheel_fr", (self.track_f * 0.5, self.axle_f, r), rot=(0, 0, 180))
        if abs(wr - wf) > 1e-6 or s["rim_r"] or s.get("dual_rear"):
            rl = make_wheel(root, "wheel_rl", r, wr, s["rim_r"] or s["rim"], dual=bool(s.get("dual_rear")), **kw)
            rl.location = (-self.track_r * 0.5, self.axle_r, r)
        else:
            rl = K.link_copy(fl, root, "wheel_rl", (-self.track_r * 0.5, self.axle_r, r))
        K.link_copy(rl, root, "wheel_rr", (self.track_r * 0.5, self.axle_r, r), rot=(0, 0, 180))

    # ------------------------------------------------------------------ lod + collision
    def lod(self):
        s = self.s
        mb = K.MB()
        with self.conforming(mb, cut_z=False, plan_only=True):
            self.shell(mb, lod=True)
            if self.has_gh:
                H = self.H
                xb, xt = self.xb, self.xg(H) - 0.01
                yt0, yt1 = self.yrf - 0.10, self.yrr + 0.10
                bot = [(xb, self.yc, self.zc), (-xb, self.yc, self.zc), (-xb, self.yd, self.zd), (xb, self.yd, self.zd)]
                top = [(xt, yt0, H), (-xt, yt0, H), (-xt, yt1, H), (xt, yt1, H)]
                roofc = s["gh"].get("roof_color", s["paint"])
                zg = s["gh"].get("lod_glass_top")
                if zg:          # tall cab fairings: glass only up to zg, body colour above
                    t = (zg - self.zc) / (H - self.zc)
                    mid = [tuple(lerp(a[i], b[i], t) for i in range(3)) for a, b in zip(bot, top)]
                    ring_loft(mb, [bot, mid], "glass_dark", cap0=False, cap1=False)
                    ring_loft(mb, [mid, top], roofc, cap0=False)
                else:
                    ring_loft(mb, [bot, top], "glass_dark", cap0=False, cap_colors=(None, roofc))
            for end, key in ((1, "light_head"), (-1, "light_tail")):
                mk = self.marks.get(key)
                if not mk or key not in s.get("lod_lamps", ("light_head", "light_tail")):
                    continue
                self._end = end
                z0, z1 = mk[2] - 0.065, mk[2] + 0.065
                with mb.at(scale=(1, end, 1)):
                    for sxx in (1, -1):
                        with mb.at(scale=(sxx, 1, 1)):
                            x0, x1 = self.W2 * 0.5, self.W2 - self.ec(z0) - 0.02
                            y0, y1 = self.ey(z0) + 0.012, self.ey(z1) + 0.012
                            P(mb, [(x1, y0, z0), (x0, y0, z0), (x0, y1, z1), (x1, y1, z1)],
                              "white" if end > 0 else "red")
            self._end = 0
            if s["lod_extras"]:
                s["lod_extras"](self, mb)
        wr = s["wheel_w_r"] or s["wheel_w"]
        for (ya, tr, w) in ((self.axle_f, self.track_f, s["wheel_w"]), (self.axle_r, self.track_r, wr)):
            for sxx in (1, -1):
                mb.cyl(self.r, w, (sxx * (tr * 0.5 + 0.03), ya, self.r), "tire", axis="X", segs=8,
                       cap_color="gray_dark", smooth=False)
        obj = mb.to_object(self.root, "lod1")
        _hide(obj)
        return obj

    def collision(self):
        s = self.s
        zmin = self.clr + 0.1
        pts2 = [(p["y"], max(p["z"], zmin)) for p in self.up]
        pts2 += s.get("col_body_extra", [])
        hull = reduce_poly(hull2d(pts2), 11)
        pts = []
        for (y, z) in hull:
            x = self.W2 * self.sx(y, z, True)
            pts += [(x, y, z), (-x, y, z)]
        a = hull_object(self.root, "col_body", pts, "gray_mid")
        _hide(a)
        b = None
        cp = None
        if s.get("col_cabin"):
            cp = s["col_cabin"](self) if callable(s["col_cabin"]) else s["col_cabin"]
        elif self.has_gh:
            H = self.H
            xt = self.xg(H)
            cp = []
            for sg in (1, -1):
                cp += [(sg * self.xb, self.yc, self.zc), (sg * self.xb, self.yd, self.zd),
                       (sg * self.xg(self.zrf), self.yrf, self.zrf), (sg * self.xg(self.zrr), self.yrr, self.zrr),
                       (sg * xt, self.yrf - 0.2, H), (sg * xt, self.yrr + 0.2, H)]
            cp = [(x * self.sx(y, z, True), y, z) for (x, y, z) in cp]
        if cp:
            b = hull_object(self.root, "col_cabin", cp, "gray_light")
            _hide(b)
        # optional extra convex hulls (cargo boxes ...): the game turns every `col_*` part into a shape
        for name, pts in (s.get("col_extra") or {}).items():
            pts = pts(self) if callable(pts) else pts
            _hide(hull_object(self.root, "col_" + name, pts, "gray_dark"))
        return a, b

    # ------------------------------------------------------------------ markers
    def markers(self):
        s = self.s
        it = s["interior"]
        root = self.root
        mk = dict(self.marks)
        out = {}

        def M(name, pos):
            out[name] = tuple(round(v, 4) for v in pos)
            K.marker(root, name, pos)
        if self.hip:
            hx, hy, hz = self.hip
            M("seat_driver", (-hx, hy, hz))
            M("seat_passenger", (hx, hy, hz))
            if it["rear_hip"]:
                rx, ry, rz = it["rear_hip"]
                M("seat_rl", (-rx, ry, rz))
                M("seat_rr", (rx, ry, rz))
        for kind in ("head", "tail"):
            p = mk.get("light_" + kind)
            if p:
                M("light_%s_l" % kind, (-abs(p[0]), p[1], p[2]))
                M("light_%s_r" % kind, (abs(p[0]), p[1], p[2]))
        if "exhaust" in mk:
            M("exhaust", mk["exhaust"])
        ov = s.get("markers", {})
        if self.hood_seg:
            (ya, za), (yb, zb) = self.hood_seg
            hood = (0.0, (ya + yb) * 0.5, (za + zb) * 0.5)
        else:
            hood = (0.0, self.y_front - 0.5, self.nose_pts[-1][0])
        M("engine", ov.get("engine", hood))
        if "siren" in mk or "siren" in ov:
            M("siren", ov.get("siren", mk.get("siren")))
        M("mod_spoiler", ov.get("mod_spoiler", (0.0, self.deck_end[0], self.deck_end[1])))
        M("mod_hood", ov.get("mod_hood", hood))
        roof = (0.0, (self.yrf + self.yrr) * 0.5, self.H) if self.has_gh else (0.0, 0.0, self.H)
        M("mod_roof", ov.get("mod_roof", roof))
        M("mod_front", ov.get("mod_front", mk.get("bumper_f", (0.0, self.y_front, self.nose_pts[0][0]))))
        M("mod_rear", ov.get("mod_rear", mk.get("bumper_r", (0.0, self.y_rear, self.tail_pts[0][0]))))
        ym = (min(self.arches) + max(self.arches)) * 0.5 if len(self.arches) > 1 else 0.0
        ym = ov.get("skirt_y", ym)
        hx_ = self.hw(ym, self.clr)
        M("mod_skirt_l", (-hx_, ym, self.clr))
        M("mod_skirt_r", (hx_, ym, self.clr))
        for name, pos in ov.get("extra", {}).items():
            M(name, pos)
        self.marker_pos = out
        return out

    # ------------------------------------------------------------------ build
    def build(self):
        s = self.s
        root = K.begin_asset(self.id, s["category"])
        self.root = root
        self.marks = {}
        mb = K.MB()
        with self.conforming(mb, cut_z=True, rocker=True):
            self.shell(mb)
            self.tub(mb)
            self.greenhouse(mb)
            for end, key in ((1, "front"), (-1, "rear")):
                self._end = end
                with mb.at(scale=(1, end, 1)):
                    self.run_ops(mb, s[key])
            self._end = 0
            self.run_ops(mb, s["body"])
            self.bands(mb)
            if s["extras"]:
                s["extras"](self, mb)
        self.furniture(mb)
        self.run_ops(mb, s["inside"])
        if s["extras2"]:
            s["extras2"](self, mb)
        mb.to_object(root, "body")
        self.doors()
        self.wheels()
        self.steering()
        self.lod()
        self.collision()
        self.markers()
        root["gta_name"] = s.get("name", "")
        return root


# ============================================================================ vehicle data
CARS = {}

CARS["car_sedan"] = dict(
    id="car_sedan", name="Meridian", L=4.70, W=1.86, H=1.46,
    wheel_r=0.33, wheel_w=0.22, axle_f=1.45, axle_r=-1.37, clearance=0.17,
    upper=[
        (2.285, 0.205, "valance"), (2.32, 0.27, "nose"), (2.32, 0.55, "nose"), (2.283, 0.735, "nose"),
        (2.19, 0.782, "hood"), (1.19, 0.922, "cowl"), (1.10, 0.93, "belt"), (-1.52, 0.955, "deck"),
        (-2.235, 0.99, "tail"), (-2.318, 0.935, "tail"), (-2.32, 0.56, "tail"), (-2.315, 0.27, "valance"),
        (-2.28, 0.21, "under"),
    ],
    sill_z=0.29,
    doors=[(0.975, 0.0), (0.0, -0.94)],
    gh=dict(roof_f=(0.56, 1.385), roof_r=(-1.08, 1.39), tumble=0.15, a_w=(0.129, 0.11), c_front=-0.955),
    interior=dict(hip=(0.40, 0.02, 0.55), rear_hip=(0.40, -0.80, 0.57)),
    front=[
        ("bumper", dict(z0=0.255, z1=0.535, proud=0.03)),
        ("ebox", dict(x=0.0, z=0.335, size=(1.10, 0.10, 0.03), color="black", proud=0.036)),
        ("ebox", dict(x=0.0, z=0.335, size=(1.06, 0.016, 0.03), color="plastic_black", proud=0.042)),
        ("plate", dict(z=0.455, proud=0.038)),
        ("grille", dict(z0=0.585, z1=0.70, w=0.80, bars=3)),
        ("lamp", dict(kind="head", z0=0.59, z1=0.705, x0=0.47, x1=0.79, bezel="plastic_black")),
        ("lamp", dict(kind="ind", z0=0.59, z1=0.705, x0=0.805, side=0.10)),
    ],
    rear=[
        ("bumper", dict(z0=0.265, z1=0.555, proud=0.03)),
        ("lamp", dict(kind="tail", z0=0.64, z1=0.80, x0=0.57, side=0.12)),
        ("lamp", dict(kind="ind", z0=0.64, z1=0.80, x0=0.43, x1=0.56)),
        ("lamp", dict(kind="rev", z0=0.64, z1=0.80, x0=0.30, x1=0.42)),
        ("plate", dict(z=0.71)),
        ("strip", dict(z0=0.835, z1=0.865, x1=0.52, proud=0.012, color="chrome")),
        ("exhaust", dict(x=0.56, z=0.235)),
    ],
    body=[
        ("hood_panel", dict(inset=0.17)),
        ("sbox", dict(y=-1.93, z=0.76, size=(0.13, 0.13, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        ("antenna", dict(x=0.55, y=-1.20, z=1.40)),
    ],
)


# ============================================================================ shared detail helpers
def checker(mb, x, ya, yb, z0, rows=2, cell=0.09, proud=0.007, colors=("black", "white")):
    """Checker band on the plane x = const (right side, normal +X; call inside a mirror frame for the left).
    The cells sit on a global grid in y, so the pieces on the body and on the doors line up."""
    xo, xi = x + proud, x - 0.004
    lo, hi = min(ya, yb), max(ya, yb)
    for k in range(int(math.floor(lo / cell)), int(math.ceil(hi / cell))):
        a, b = max(lo, k * cell), min(hi, (k + 1) * cell)
        if b - a < 1e-4:
            continue
        for r in range(rows):
            za, zb = z0 + r * cell, z0 + (r + 1) * cell
            P(mb, [(xo, a, za), (xo, b, za), (xo, b, zb), (xo, a, zb)], colors[(k + r) % 2])
    z1 = z0 + rows * cell
    P(mb, [(xo, lo, z1), (xo, hi, z1), (xi, hi, z1), (xi, lo, z1)], colors[0])
    P(mb, [(xo, hi, z0), (xo, lo, z0), (xi, lo, z0), (xi, hi, z0)], colors[0])


def side_text(car, mb, text, y, z, side, size=0.12, depth=0.008, color="police_blue", x=None, res=1):
    """Lettering on a body side (bottom centre at y, z), readable from outside. Final (conformed) space."""
    if x is None:
        x = car.hw(y, z + size * 0.4)
    if depth <= 0.0:
        x += 0.006
    K.add_text(mb, text, size=size, depth=max(depth, 0.0), color=color, pos=(side * x, y, z),
               rot=(0, 0, -90.0 * side), res=res)


def end_text(mb, text, y, z, end=1, size=0.12, depth=0.008, color="black", x=0.0, res=1):
    """Lettering on a face looking forward (end=1) or backward (end=-1); bottom centre at (x, y, z)."""
    K.add_text(mb, text, size=size, depth=max(depth, 0.0), color=color,
               pos=(x, y + (0.005 * end if depth <= 0.0 else 0.0), z), rot=(0, 0, 0.0 if end > 0 else 180.0), res=res)


def lamp_pod(mb, pos, r, length, body="chrome", lens="@LightAux", r_back=None, segs=8, end=1):
    """Small round lamp looking along +Y (end=1) or -Y: tapered housing with a lens cap."""
    cx, cy, cz = pos
    rb = r * 0.6 if r_back is None else r_back
    rings = []
    for (yy, rr) in ((cy - length * 0.5, rb if end > 0 else r), (cy + length * 0.5, r if end > 0 else rb)):
        rings.append([(cx - rr * math.cos(2 * math.pi * k / segs), yy, cz + rr * math.sin(2 * math.pi * k / segs))
                      for k in range(segs)])
    ring_loft(mb, rings, body, cap_colors=((body, lens) if end > 0 else (lens, body)))


def lightbar(car, mb, y, z, w=1.10, d=0.27, h=0.10, mark="siren", bevel=0.018, mid="white", feet=True):
    """Roof light bar: @LightSirenA (red) on the left half (-X), @LightSirenB (blue) on the right half."""
    zb = z + (0.045 if feet else 0.0)
    if feet:
        for sxx in (1, -1):
            mb.box((0.07, d * 0.62, 0.05), (sxx * w * 0.40, y, z + 0.02), "plastic_black")
        mb.box((w * 0.94, d * 0.5, 0.022), (0, y, zb - 0.008), "black")
    cw = 0.15
    lw = (w - cw) * 0.5
    for sxx, col in ((-1, "@LightSirenA"), (1, "@LightSirenB")):
        mb.box((lw, d, h), (sxx * (cw + lw) * 0.5, y, zb + h * 0.5), col, bevel=bevel)
    mb.box((cw + 0.01, d * 0.86, h * 0.9), (0, y, zb + h * 0.46), mid)
    if mark:
        car.marks[mark] = (0.0, y, zb + h * 0.5)
    return zb + h


def lod_lightbar(mb, y, z, w=1.0, d=0.26, h=0.11):
    for sxx, col in ((-1, "red"), (1, "blue")):
        mb.box((w * 0.5, d, h), (sxx * w * 0.25, y, z + h * 0.5 + 0.03), col)


def lod_door_panels(car, mb, color=PAINT2):
    """Flat door-coloured quads for the LOD of two-tone liveries."""
    if not car.notch:
        return
    zs = car.s["sill_z"]
    ynf, ynr = car.notch
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            x = car.W2 + 0.01
            P(mb, [(x, ynr, zs), (x, ynf, zs), (x, ynf, car.belt_z(ynf) - car.c), (x, ynr, car.belt_z(ynr) - car.c)],
              color)


# ============================================================================ P1 cars
# ---------------------------------------------------------------------------- Interceptor (police)
def _police_extras(car, mb):
    lightbar(car, mb, y=-0.04, z=car.H, w=1.08)
    for sxx in (1, -1):                       # A-pillar spotlights
        with mb.at(scale=(sxx, 1, 1)):
            z = car.zc + 0.125
            x = car.xg(z) + 0.078
            y = car.yc - 0.10
            mb.box((0.06, 0.026, 0.026), (x - 0.04, y - 0.015, z - 0.03), "black")
            lamp_pod(mb, (x, y, z), 0.056, 0.11, "chrome", "@LightAux")


def _police_door(car, mb, di, side, y0, y1):
    if di == 0:
        ym = (y0 + y1) * 0.5 - 0.02
        side_text(car, mb, "POLICE", ym, car.belt_z(ym) - 0.345, side, size=0.155, depth=0.008, color="police_blue")


def _police_lod(car, mb):
    lod_door_panels(car, mb)
    lod_lightbar(mb, -0.04, car.H, w=1.0)


CARS["car_police"] = dict(
    id="car_police", name="Interceptor", L=4.95, W=1.92, H=1.50,
    wheel_r=0.35, wheel_w=0.24, axle_f=1.50, axle_r=-1.47, clearance=0.18,
    door_paint=PAINT2, rim="steel", rim_color="black", cap_color="chrome", rim_ratio=0.64,
    mirror_color="plastic_black", handle_color="plastic_black",
    upper=[
        (2.35, 0.22, "valance"), (2.385, 0.285, "nose"), (2.385, 0.62, "nose"), (2.35, 0.79, "nose"),
        (2.25, 0.84, "hood"), (1.22, 0.985, "cowl"), (1.12, 0.995, "belt"), (-1.60, 1.03, "deck"),
        (-2.30, 1.045, "tail"), (-2.405, 0.985, "tail"), (-2.42, 0.60, "tail"), (-2.415, 0.29, "valance"),
        (-2.38, 0.225, "under"),
    ],
    doors=[(0.99, -0.02), (-0.02, -0.99)],
    gh=dict(roof_f=(0.50, 1.425), roof_r=(-1.10, 1.43), tumble=0.16, a_w=(0.13, 0.11), c_front=-1.005,
            roof_color=PAINT2),
    interior=dict(hip=(0.41, 0.0, 0.57), rear_hip=(0.41, -0.86, 0.59), seat="@D:fabric_dark", lite=True),
    bands=[dict(y0=0.975, y1=-0.975, z0=0.60, z1=0.63, color="police_blue", proud=0.006)],
    front=[
        ("bumper", dict(z0=0.27, z1=0.51, proud=0.03)),
        ("ebox", dict(x=0.0, z=0.345, size=(1.04, 0.10, 0.03), color="black", proud=0.036)),
        ("plate", dict(z=0.445, proud=0.038)),
        ("grille", dict(z0=0.565, z1=0.715, w=0.74, bars=2, frame="black", bar="gunmetal")),
        ("lamp", dict(kind="head", z0=0.58, z1=0.715, x0=0.45, x1=0.80, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.58, z1=0.715, x0=0.815, side=0.11)),
        # push bar
        ("ebox", dict(x=0.25, z=0.50, size=(0.06, 0.46, 0.11), color="black", proud=0.115, pair=True)),
        ("ebox", dict(x=0.0, z=0.635, size=(0.56, 0.05, 0.045), color="black", proud=0.10)),
        ("ebox", dict(x=0.0, z=0.40, size=(0.56, 0.05, 0.045), color="black", proud=0.10)),
    ],
    rear=[
        ("bumper", dict(z0=0.28, z1=0.55, proud=0.03)),
        ("lamp", dict(kind="tail", z0=0.72, z1=0.87, x0=0.50, side=0.13)),
        ("lamp", dict(kind="ind", z0=0.72, z1=0.87, x0=0.36, x1=0.49)),
        ("lamp", dict(kind="rev", z0=0.72, z1=0.87, x0=0.22, x1=0.35)),
        ("plate", dict(z=0.795)),
        ("ebox", dict(x=0.0, z=0.925, size=(1.0, 0.03, 0.02), color="black", proud=0.012)),
        ("exhaust", dict(x=0.56, z=0.245, both=True)),
    ],
    body=[
        ("hood_panel", dict(inset=0.24, h=0.022, m0=0.06, taper=(0.9, 0.96), bevel=0.01)),
        ("sbox", dict(y=-1.98, z=0.82, size=(0.13, 0.13, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        ("antenna", dict(x=0.46, y=-1.80, z=1.035, h=0.55)),
    ],
    extras=_police_extras, door_extras=_police_door, lod_extras=_police_lod,
    notes="Two-tone: body + pillars @Paint1, doors + roof @Paint2. Roof light bar (@LightSirenA left / "
          "@LightSirenB right, marker siren), A-pillar spot lamps (@LightAux), push bar, POLICE lettering.",
)


# ---------------------------------------------------------------------------- ZipCab (taxi)
def _taxi_extras(car, mb):
    y, z = 0.24, car.H
    mb.box((0.58, 0.20, 0.03), (0, y, z + 0.012), "plastic_black")
    mb.box((0.52, 0.15, 0.165), (0, y, z + 0.027 + 0.0825), "@LightAux", bevel=0.02)
    for end in (1, -1):
        end_text(mb, "TAXI", y + end * 0.075, z + 0.062, end, size=0.135, depth=0.008, color="black")


def _taxi_lod(car, mb):
    mb.box((0.52, 0.15, 0.17), (0, 0.24, car.H + 0.10), "cream")
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            x = car.W2 + 0.01
            P(mb, [(x, -2.0, 0.745), (x, 1.6, 0.745), (x, 1.6, 0.915), (x, -2.0, 0.915)], "gray_dark")


CARS["car_taxi"] = dict(
    id="car_taxi", name="ZipCab", L=4.60, W=1.84, H=1.62,
    wheel_r=0.33, wheel_w=0.21, axle_f=1.45, axle_r=-1.40, clearance=0.17,
    rim="steel", rim_color="gray_light", cap_color="chrome", rim_ratio=0.64,
    mirror_color="plastic_black", handle_color="plastic_black",
    upper=[
        (2.235, 0.21, "valance"), (2.27, 0.275, "nose"), (2.27, 0.57, "nose"), (2.215, 0.785, "nose"),
        (2.09, 0.86, "hood"), (1.37, 1.03, "cowl"), (1.27, 1.04, "belt"), (-1.72, 1.06, "deck"),
        (-2.19, 1.065, "tail"), (-2.265, 1.005, "tail"), (-2.27, 0.60, "tail"), (-2.265, 0.275, "valance"),
        (-2.23, 0.215, "under"),
    ],
    doors=[(0.985, 0.04), (0.04, -0.93)],
    gh=dict(roof_f=(0.80, 1.545), roof_r=(-1.52, 1.55), tumble=0.12, a_w=(0.125, 0.11), c_front=-1.40,
            fixed=[(1.16, 0.99, "black_gloss"), (-0.945, -9.0)]),
    interior=dict(hip=(0.40, 0.06, 0.63), rear_hip=(0.40, -0.80, 0.65), cargo=dict(z=0.66), lite=True,
                  seat="@D:fabric_dark"),
    bands=[dict(kind="checker", y0=1.62, y1=-2.07, z0=0.745, cell=0.085, rows=2, proud=0.007)],
    front=[
        ("bumper", dict(z0=0.26, z1=0.52, proud=0.03, color="plastic_black")),
        ("plate", dict(z=0.40, proud=0.038)),
        ("grille", dict(z0=0.585, z1=0.735, w=0.60, bars=2)),
        ("lamp", dict(kind="head", z0=0.59, z1=0.745, x0=0.40, x1=0.74, bezel="chrome")),
        ("lamp", dict(kind="ind", z0=0.59, z1=0.745, x0=0.755, side=0.09)),
    ],
    rear=[
        ("bumper", dict(z0=0.265, z1=0.54, proud=0.03, color="plastic_black")),
        ("lamp", dict(kind="tail", z0=0.63, z1=0.95, x0=0.66, side=0.10)),
        ("lamp", dict(kind="ind", z0=0.80, z1=0.95, x0=0.52, x1=0.65)),
        ("lamp", dict(kind="rev", z0=0.63, z1=0.78, x0=0.52, x1=0.65)),
        ("plate", dict(z=0.74)),
        ("ebox", dict(x=0.0, z=0.89, size=(0.56, 0.03, 0.02), color="chrome", proud=0.012)),
        ("exhaust", dict(x=0.50, z=0.235)),
    ],
    body=[
        ("hood_panel", dict(inset=0.16, bevel=0.0)),
        ("sbox", dict(y=-1.95, z=0.66, size=(0.13, 0.13, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        ("antenna", dict(x=0.50, y=-1.42, z=1.60, h=0.40)),
    ],
    extras=_taxi_extras, lod_extras=_taxi_lod,
    notes="Tall-roof cab. Checker band (black/white) across body and doors, roof sign box @LightAux with TAXI "
          "lettering front + rear. Rear luggage bay behind the bench.",
)


# ---------------------------------------------------------------------------- Pico (compact hatchback)
CARS["car_compact"] = dict(
    id="car_compact", name="Pico", L=3.75, W=1.68, H=1.50,
    wheel_r=0.30, wheel_w=0.19, axle_f=1.24, axle_r=-1.17, clearance=0.16,
    rim="steel", rim_color="gray_light", cap_color="chrome", rim_ratio=0.64,
    c=0.045, taper_f=0.12, taper_r=0.07, mirror_color="plastic_black", handle_color="plastic_black",
    upper=[
        (1.81, 0.195, "valance"), (1.845, 0.255, "nose"), (1.845, 0.53, "nose"), (1.795, 0.715, "nose"),
        (1.69, 0.775, "hood"), (1.03, 0.925, "cowl"), (0.94, 0.935, "belt"), (-1.70, 0.975, "tail"),
        (-1.815, 0.90, "tail"), (-1.845, 0.56, "tail"), (-1.84, 0.26, "valance"), (-1.805, 0.20, "under"),
    ],
    doors=[(0.805, -0.26)],
    gh=dict(roof_f=(0.44, 1.425), roof_r=(-1.47, 1.44), tumble=0.13, a_w=(0.12, 0.10), c_w=(0.36, 0.13),
            fixed=[(-0.275, -9.0)]),
    interior=dict(hip=(0.36, -0.08, 0.53), rear_hip=(0.36, -0.84, 0.55), cargo=dict(z=0.62),
                  seat="@D:fabric_blue"),
    bands=[dict(y0=0.83, y1=-0.75, z0=0.47, z1=0.515, color="plastic_black", proud=0.012)],
    front=[
        ("bumper", dict(z0=0.245, z1=0.50, proud=0.03)),
        ("ebox", dict(x=0.0, z=0.315, size=(0.86, 0.085, 0.03), color="black", proud=0.036)),
        ("plate", dict(z=0.43, proud=0.038)),
        ("grille", dict(z0=0.565, z1=0.635, w=0.46, bars=1, frame=None)),
        ("lamp", dict(kind="head", z0=0.545, z1=0.70, x0=0.40, x1=0.70, bezel="chrome")),
        ("lamp", dict(kind="ind", z0=0.545, z1=0.70, x0=0.715, side=0.07)),
    ],
    rear=[
        ("bumper", dict(z0=0.25, z1=0.50, proud=0.03)),
        ("lamp", dict(kind="tail", z0=0.60, z1=0.86, x0=0.60, side=0.09)),
        ("lamp", dict(kind="ind", z0=0.75, z1=0.86, x0=0.47, x1=0.59)),
        ("lamp", dict(kind="rev", z0=0.60, z1=0.71, x0=0.47, x1=0.59)),
        ("plate", dict(z=0.66)),
        ("strip", dict(z0=0.775, z1=0.80, x1=0.22, proud=0.012, color="plastic_black")),
        ("exhaust", dict(x=0.42, z=0.225, r=0.03)),
    ],
    body=[
        ("hood_panel", dict(inset=0.15)),
        ("sbox", dict(y=-1.50, z=0.72, size=(0.12, 0.12, 0.01), color=PAINT, proud=0.004, sides=(1,))),
        ("box", dict(size=(1.16, 0.10, 0.03), pos=(0, -1.49, 1.492), color="plastic_black", rot=(-6, 0, 0))),
        ("box", dict(size=(0.30, 0.016, 0.02), pos=(0.02, -1.615, 1.12), color="black", rot=(-63, 0, 0))),
        ("antenna", dict(x=0.0, y=-1.25, z=1.495, h=0.30, lean=-40.0)),
    ],
    notes="2-door hatchback with rear bench (4 seats) and luggage bay; black rub strips across body and doors.",
)


# ---------------------------------------------------------------------------- Vanta GT (sports)
CARS["car_sports"] = dict(
    id="car_sports", name="Vanta GT", L=4.45, W=1.96, H=1.22,
    wheel_r=0.34, wheel_w=0.25, wheel_w_r=0.30, axle_f=1.30, axle_r=-1.30, clearance=0.12,
    arch_gap=0.04, c=0.045, tyre_inset=0.0, rim="spoke5", rim_ratio=0.75, rim_color="gunmetal",
    sill_z=0.25, floor_z=0.15, taper_f=0.17, taper_r=0.10, tuck=0.05,
    upper=[
        (2.16, 0.15, "valance"), (2.195, 0.20, "nose"), (2.195, 0.41, "nose"), (2.10, 0.55, "nose"),
        (1.72, 0.80, "hood"), (0.73, 0.855, "cowl"), (0.63, 0.865, "belt"), (-1.70, 0.91, "deck"),
        (-2.11, 0.925, "tail"), (-2.185, 0.875, "tail"), (-2.195, 0.50, "tail"), (-2.185, 0.215, "valance"),
        (-2.15, 0.155, "under"),
    ],
    doors=[(0.49, -0.52)],
    gh=dict(roof_f=(0.02, 1.16), roof_r=(-0.70, 1.17), tumble=0.17, a_w=(0.14, 0.11), c_w=(0.50, 0.14),
            fixed=[(-0.535, -9.0)], roof_c=0.03),
    interior=dict(hip=(0.41, -0.24, 0.40), seat="@D:leather_black", dash="@D:charcoal"),
    front=[
        ("bumper", dict(z0=0.165, z1=0.27, proud=0.03, color="plastic_black", bevel=0.02)),
        ("ebox", dict(x=0.0, z=0.335, size=(0.86, 0.10, 0.03), color="black", proud=0.008)),
        ("ebox", dict(x=0.66, z=0.335, size=(0.26, 0.10, 0.03), color="black", proud=0.008, pair=True)),
        ("lamp", dict(kind="head", z0=0.60, z1=0.70, x0=0.50, x1=0.86, proud=0.01, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.425, z1=0.475, x0=0.60, side=0.07, proud=0.008)),
    ],
    rear=[
        ("bumper", dict(z0=0.17, z1=0.33, proud=0.03, color="plastic_black", bevel=0.02)),
        ("ebox", dict(x=0.0, z=0.745, size=(1.50, 0.115, 0.02), color="black", proud=0.008)),
        ("lamp", dict(kind="tail", z0=0.705, z1=0.785, x0=0.40, side=0.10, proud=0.014)),
        ("lamp", dict(kind="ind", z0=0.705, z1=0.785, x0=0.25, x1=0.385, proud=0.014)),
        ("lamp", dict(kind="rev", z0=0.705, z1=0.785, x0=0.10, x1=0.235, proud=0.014)),
        ("plate", dict(z=0.50)),
        ("exhaust", dict(x=0.0, z=0.235, twin=0.17, r=0.042, color="chrome")),
    ],
    body=[
        ("box", dict(size=(0.26, 0.42, 0.014), pos=(0.36, 1.18, 0.838), color="black", rot=(3, 0, 0), pair=True)),
        ("sbox", dict(y=-0.71, z=0.53, size=(0.27, 0.24, 0.012), color="black", proud=0.004)),
        ("sbox", dict(y=-0.71, z=0.53, size=(0.29, 0.03, 0.03), color=PAINT, proud=0.02)),
        ("box", dict(size=(1.60, 0.09, 0.04), pos=(0, -2.06, 0.94), color="plastic_black", rot=(8, 0, 0),
                     bevel=0.012)),
    ],
    arch_lip=dict(proud=0.02, w=0.04),
    notes="Low front-engined GT: droop nose, fastback glass, side intakes ahead of the rear wheels, lip spoiler, "
          "wider rear tyres. 2 seats.",
)


# ---------------------------------------------------------------------------- Ridgeback (SUV)
def _suv_extras(car, mb):
    H = car.H
    for sxx in (1, -1):                       # roof rails on three feet
        with mb.at(scale=(sxx, 1, 1)):
            mb.box((0.045, 2.16, 0.032), (0.655, -0.72, H + 0.046), "plastic_black")
            for yy in (0.26, -0.72, -1.70):
                mb.box((0.05, 0.11, 0.034), (0.655, yy, H + 0.014), "plastic_black")


CARS["car_suv"] = dict(
    id="car_suv", name="Ridgeback", L=4.85, W=2.02, H=1.86, cab_H=1.80,
    wheel_r=0.42, wheel_w=0.27, axle_f=1.55, axle_r=-1.40, clearance=0.30,
    arch_gap=0.06, arch_lip=dict(proud=0.035, w=0.06, color="plastic_black"),
    rim="spoke6", rim_ratio=0.60, rim_color="aluminum", rocker_z=0.42, tuck=0.03,
    taper_f=0.09, taper_r=0.06, mirror_color="plastic_black", handle_color="plastic_black",
    upper=[
        (2.36, 0.385, "valance"), (2.395, 0.45, "nose"), (2.395, 0.84, "nose"), (2.36, 1.035, "nose"),
        (2.25, 1.095, "hood"), (1.185, 1.185, "cowl"), (1.085, 1.195, "belt"), (-2.21, 1.215, "tail"),
        (-2.37, 1.13, "tail"), (-2.395, 0.78, "tail"), (-2.39, 0.45, "valance"), (-2.355, 0.385, "under"),
    ],
    doors=[(0.955, 0.05), (0.05, -0.80)],
    gh=dict(roof_f=(0.58, 1.74), roof_r=(-2.02, 1.745), tumble=0.12, a_w=(0.13, 0.115), c_w=(0.17, 0.13),
            fixed=[(-0.815, -9.0)]),
    interior=dict(hip=(0.43, 0.10, 0.82), rear_hip=(0.43, -0.74, 0.84), cargo=dict(z=0.80), lite=True,
                  seat="@D:leather_brown"),
    front=[
        ("bumper", dict(z0=0.42, z1=0.72, proud=0.035, color="plastic_black", side=0.17)),
        ("ebox", dict(x=0.0, z=0.475, size=(0.92, 0.11, 0.03), color="aluminum", proud=0.047, bevel=0.012)),
        ("plate", dict(z=0.625, proud=0.043)),
        ("ebox", dict(x=0.66, z=0.60, size=(0.17, 0.075, 0.03), color="@LightHead", proud=0.042, pair=True)),
        ("grille", dict(z0=0.79, z1=0.995, w=0.86, bars=3)),
        ("lamp", dict(kind="head", z0=0.81, z1=0.985, x0=0.50, x1=0.82, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.81, z1=0.985, x0=0.835, side=0.10)),
    ],
    rear=[
        ("bumper", dict(z0=0.42, z1=0.70, proud=0.035, color="plastic_black", side=0.17)),
        ("ebox", dict(x=0.0, z=0.47, size=(0.92, 0.10, 0.03), color="aluminum", proud=0.047, bevel=0.012)),
        ("lamp", dict(kind="tail", z0=0.80, z1=1.10, x0=0.72, side=0.10)),
        ("lamp", dict(kind="ind", z0=0.97, z1=1.10, x0=0.58, x1=0.71)),
        ("lamp", dict(kind="rev", z0=0.80, z1=0.93, x0=0.58, x1=0.71)),
        ("plate", dict(z=0.87)),
        ("ebox", dict(x=0.0, z=1.00, size=(0.60, 0.035, 0.022), color="chrome", proud=0.012)),
        ("exhaust", dict(x=0.62, z=0.37, r=0.04)),
    ],
    body=[
        ("hood_panel", dict(inset=0.24, h=0.022, m0=0.05, bevel=0.01)),
        ("sbox", dict(y=-1.93, z=0.97, size=(0.14, 0.14, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        ("box", dict(size=(0.11, 1.62, 0.035), pos=(0.99, 0.075, 0.335), color="plastic_black", pair=True)),
        ("antenna", dict(x=-0.50, y=-1.80, z=1.79, h=0.32, lean=-35.0)),
    ],
    extras=_suv_extras,
    notes="Tall 2-box, black arch flares + sill cladding, running boards, roof rails (roof at 1.80, rails to 1.86), "
          "open luggage bay behind the rear bench.",
)


# ---------------------------------------------------------------------------- Mule (pickup)
PICKUP_BED_Z = 0.87


def _pickup_extras(car, mb):
    """Open load bed: floor, inner walls, cab back, tailgate inner + rail caps (the shell supplies the outside)."""
    s = car.s
    xi = car.W2 - s["ledge_w"]
    zf = PICKUP_BED_Z
    yd, zt = car.yd, car.zd
    y0 = yd - 0.03                           # bed front wall (cab back)
    ye = car.deck_end[0]                     # outer top edge of the tailgate
    y1 = ye + 0.075                          # inner face of the tailgate
    liner = "charcoal"
    P(mb, [(xi, y1, zf), (xi, y0, zf), (-xi, y0, zf), (-xi, y1, zf)], liner)                    # floor
    P(mb, [(xi, y0, zf), (xi, y0, zt), (-xi, y0, zt), (-xi, y0, zf)], s["paint"])               # cab back
    P(mb, [(xi, y0, zt), (xi, yd, zt), (-xi, yd, zt), (-xi, y0, zt)], "plastic_black")
    P(mb, [(xi, y1, zf), (-xi, y1, zf), (-xi, y1, zt), (xi, y1, zt)], s["paint"])               # tailgate inner
    P(mb, [(xi, ye, zt), (xi, y1, zt), (-xi, y1, zt), (-xi, ye, zt)], "plastic_black")          # tailgate top
    top = car.r + car.ra + 0.035
    x0 = car.W2 - s["well_depth"] - 0.03
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            P(mb, [(xi, y0, zf), (xi, y1, zf), (xi, y1, zt), (xi, y0, zt)], s["paint"])         # inner side wall
            # wheel house
            mb.box((xi + 0.004 - x0, 2 * car.ra + 0.08, top - zf + 0.01), ((x0 + xi + 0.004) * 0.5, car.axle_r,
                                                                         (top + zf - 0.01) * 0.5), liner)
            # rail cap
            mb.box((s["ledge_w"] - 0.03, y0 - ye - 0.02, 0.016), (car.W2 - s["ledge_w"] * 0.5 - 0.022, (y0 + ye) * 0.5,
                                                                zt + 0.006), "plastic_black")
    # floor ribs
    for k in range(5):
        xr = -0.5 + 0.25 * k
        mb.box((0.06, y0 - y1 - 0.10, 0.012), (xr, (y0 + y1) * 0.5, zf + 0.004), "gray_dark")


def _pickup_lod(car, mb):
    xi = car.W2 - car.s["ledge_w"]
    z = car.zd + 0.006
    y0, y1 = car.yd - 0.05, car.deck_end[0] + 0.075
    P(mb, [(xi, y1, z), (xi, y0, z), (-xi, y0, z), (-xi, y1, z)], "charcoal")


CARS["car_pickup"] = dict(
    id="car_pickup", name="Mule", L=5.40, W=2.02, H=1.86,
    wheel_r=0.42, wheel_w=0.27, axle_f=1.72, axle_r=-1.62, clearance=0.32,
    arch_gap=0.06, arch_lip=dict(proud=0.03, w=0.055),
    rim="steel", rim_ratio=0.60, rim_color="white", cap_color="chrome",
    taper_f=0.07, taper_r=0.035, tuck=0.03, mirror_color="chrome",
    upper=[
        (2.615, 0.40, "valance"), (2.65, 0.47, "nose"), (2.65, 0.86, "nose"), (2.62, 1.07, "nose"),
        (2.52, 1.13, "hood"), (1.365, 1.215, "cowl"), (1.265, 1.225, "belt"), (-0.26, 1.235, "bed"),
        (-2.60, 1.235, "tail"), (-2.65, 1.185, "tail"), (-2.65, 0.62, "tail"), (-2.64, 0.47, "valance"),
        (-2.605, 0.40, "under"),
    ],
    doors=[(1.135, 0.06)],
    gh=dict(roof_f=(0.74, 1.79), roof_r=(-0.16, 1.795), tumble=0.11, a_w=(0.13, 0.115), c_front=0.045),
    interior=dict(hip=(0.44, 0.33, 0.84), seat="@D:fabric_gray"),
    front=[
        ("bumper", dict(z0=0.50, z1=0.69, proud=0.05, color="chrome", side=0.16)),
        ("plate", dict(z=0.595, proud=0.058)),
        ("grille", dict(z0=0.775, z1=1.02, w=1.02, bars=2, vertical=3)),
        ("lamp", dict(kind="head", z0=0.86, z1=1.015, x0=0.58, x1=0.86, bezel="chrome")),
        ("lamp", dict(kind="ind", z0=0.775, z1=0.84, x0=0.58, side=0.06)),
    ],
    rear=[
        ("bumper", dict(z0=0.46, z1=0.62, proud=0.05, color="chrome", side=0.16)),
        ("lamp", dict(kind="tail", z0=0.93, z1=1.15, x0=0.80, side=0.07)),
        ("lamp", dict(kind="ind", z0=0.81, z1=0.91, x0=0.80, side=0.07)),
        ("lamp", dict(kind="rev", z0=0.69, z1=0.79, x0=0.80, side=0.07)),
        ("plate", dict(z=0.54, proud=0.058)),
        ("ebox", dict(x=0.0, z=1.08, size=(0.26, 0.05, 0.03), color="plastic_black", proud=0.016, bevel=0.01)),
        ("ebox", dict(x=0.0, z=0.90, size=(1.40, 0.30, 0.012), color=PAINT, proud=0.008, bevel=0.01)),
        ("exhaust", dict(x=0.66, z=0.40, r=0.04)),
    ],
    body=[
        ("hood_panel", dict(inset=0.27, h=0.03, m0=0.05, taper=(0.92, 0.97), bevel=0.012)),
        ("sbox", dict(y=-0.62, z=1.02, size=(0.14, 0.14, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        ("antenna", dict(x=0.80, y=1.46, z=1.205, h=0.62, lean=-12.0)),
    ],
    extras=_pickup_extras, lod_extras=_pickup_lod,
    notes="Regular-cab pickup. Open load bed (floor z=%.2f, inner length 2.25, width 1.70 between the walls, "
          "wheel houses) is part of `body`; chrome bumpers; 2 seats." % PICKUP_BED_Z,
)


# ---------------------------------------------------------------------------- Hauler (panel van)
def cab_back_lining(car, mb, color="@D:charcoal", off=0.012):
    """Dark lining on the cab side of a cargo bulkhead (the bulkhead itself stays body-coloured outside)."""
    y = car.yd + off
    xb, xt = car.xg(car.zd) - 0.02, car.xg(car.zrr) - 0.02
    P(mb, [(xb, y, car.zd - 0.04), (-xb, y, car.zd - 0.04), (-xt, y, car.zrr), (xt, y, car.zrr)], color)


CARS["car_van"] = dict(
    id="car_van", name="Hauler", L=5.20, W=2.04, H=2.25, cab_H=2.235,
    wheel_r=0.37, wheel_w=0.24, axle_f=1.74, axle_r=-1.50, clearance=0.20,
    rim="steel", rim_ratio=0.62, rim_color="gray_light", cap_color="gray_mid",
    sill_z=0.44, floor_z=0.42, taper_f=0.10, taper_r=0.025, tuck=0.03,
    mirror_color="plastic_black", handle_color="plastic_black",
    upper=[
        (2.535, 0.25, "valance"), (2.57, 0.32, "nose"), (2.57, 0.72, "nose"), (2.52, 0.91, "nose"),
        (2.40, 0.985, "hood"), (1.86, 1.235, "cowl"), (1.76, 1.25, "belt"), (0.22, 1.25, "bulk"),
        (0.22, 2.25, "roof"), (-2.50, 2.25, "tail"), (-2.57, 2.18, "tail"), (-2.57, 0.62, "tail"),
        (-2.56, 0.32, "valance"), (-2.525, 0.25, "under"),
    ],
    doors=[(1.235, 0.31)],
    gh=dict(roof_f=(1.22, 1.95), roof_r=(0.22, 1.95), tumble=0.035, a_w=(0.13, 0.11), c_w=(0.085, 0.085),
            rear_glass=False, fixed=[(1.64, 1.235)],
            roof_top=[(1.25, 1.964), (1.12, 2.07), (0.68, 2.235), (0.22, 2.235)]),
    interior=dict(hip=(0.50, 0.66, 0.94), seat="@D:fabric_gray", seat_tilt=12.0, steer_tilt=40.0, console_h=0.30),
    bands=[dict(y0=1.27, y1=-1.04, z0=0.75, z1=0.81, color="plastic_black", proud=0.012)],
    front=[
        ("bumper", dict(z0=0.30, z1=0.58, proud=0.03, color="plastic_black")),
        ("plate", dict(z=0.45, proud=0.038)),
        ("grille", dict(z0=0.665, z1=0.835, w=0.84, bars=2, frame="plastic_black")),
        ("lamp", dict(kind="head", z0=0.67, z1=0.85, x0=0.54, x1=0.86, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.67, z1=0.85, x0=0.875, side=0.09)),
    ],
    rear=[
        ("bumper", dict(z0=0.30, z1=0.52, proud=0.03, color="plastic_black")),
        ("lamp", dict(kind="tail", z0=0.88, z1=1.14, x0=0.86, side=0.06)),
        ("lamp", dict(kind="ind", z0=0.76, z1=0.86, x0=0.86, side=0.06)),
        ("lamp", dict(kind="rev", z0=0.64, z1=0.74, x0=0.86, side=0.06)),
        ("ebox", dict(x=0.0, z=1.36, size=(0.016, 1.52, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.0, z=0.60, size=(1.80, 0.016, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.0, z=2.12, size=(1.80, 0.016, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.075, z=1.16, size=(0.035, 0.26, 0.03), color="plastic_black", proud=0.02)),
        ("ebox", dict(x=0.915, z=1.75, size=(0.035, 0.11, 0.03), color="plastic_black", proud=0.014, pair=True)),
        ("ebox", dict(x=0.915, z=1.30, size=(0.035, 0.11, 0.03), color="plastic_black", proud=0.014, pair=True)),
        ("ebox", dict(x=0.0, z=2.165, size=(0.30, 0.035, 0.02), color="@LightTail", proud=0.01)),
        ("plate", dict(z=0.94, x=-0.42)),
        ("exhaust", dict(x=0.62, z=0.27, r=0.035)),
    ],
    body=[
        # sliding cargo door on the right-hand side: seams, rail, handle
        ("sbox", dict(y=0.03, z=1.31, size=(0.016, 1.62, 0.012), color="black", proud=0.004, sides=(1,))),
        ("sbox", dict(y=-1.17, z=1.31, size=(0.016, 1.62, 0.012), color="black", proud=0.004, sides=(1,))),
        ("sbox", dict(y=-0.57, z=2.115, size=(1.20, 0.016, 0.012), color="black", proud=0.004, sides=(1,))),
        ("sbox", dict(y=-0.57, z=0.505, size=(1.20, 0.016, 0.012), color="black", proud=0.004, sides=(1,))),
        ("sbox", dict(y=-1.76, z=1.33, size=(1.15, 0.035, 0.02), color="plastic_black", proud=0.014, sides=(1,))),
        ("sbox", dict(y=-0.10, z=1.14, size=(0.15, 0.045, 0.03), color="plastic_black", proud=0.022, sides=(1,))),
        ("sbox", dict(y=-2.05, z=0.95, size=(0.14, 0.14, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
        # roof ribs
        ("box", dict(size=(1.66, 0.07, 0.022), pos=(0, -0.45, 2.256), color=PAINT)),
        ("box", dict(size=(1.66, 0.07, 0.022), pos=(0, -1.15, 2.256), color=PAINT)),
        ("box", dict(size=(1.66, 0.07, 0.022), pos=(0, -1.85, 2.256), color=PAINT)),
    ],
    markers=dict(mod_roof=(0.0, -1.15, 2.25)),
    extras=cab_back_lining,
    notes="One-box panel van: cab glass only, windowless cargo body (not enterable; bulkhead behind the seats), "
          "sliding-door lines on the right side, twin rear door lines. 2 seats. mod_roof sits on the cargo roof.",
)


# ---------------------------------------------------------------------------- Brawler (muscle)
def _muscle_extras(car, mb):
    """Rear-window louvres: five black slats floating just above the fastback glass."""
    by, bz, ty, tz = car.yd, car.zd, car.yrr, car.zrr
    ln = math.hypot(ty - by, tz - bz)
    ny, nz = -(tz - bz) / ln, (ty - by) / ln
    for k in range(5):
        t = 0.14 + 0.18 * k
        y, z = lerp(by, ty, t) + ny * 0.03, lerp(bz, tz, t) + nz * 0.03
        w = 2 * (car.xg(z) - 0.07) - 0.02
        mb.box((w, 0.125, 0.014), (0, y, z), "plastic_black", rot=(9, 0, 0))


CARS["car_muscle"] = dict(
    id="car_muscle", name="Brawler", L=4.95, W=1.96, H=1.36,
    wheel_r=0.36, wheel_w=0.24, wheel_w_r=0.33, axle_f=1.55, axle_r=-1.35, clearance=0.17,
    arch_gap=0.045, rim="spoke5", rim_ratio=0.60, rim_color="chrome", cap_color="chrome", disc_color="charcoal",
    sill_z=0.30, floor_z=0.21, taper_f=0.07, taper_r=0.08,
    mirror_color="chrome",
    upper=[
        (2.40, 0.245, "valance"), (2.42, 0.31, "nose"), (2.445, 0.56, "nose"), (2.445, 0.775, "nose"),
        (2.385, 0.83, "hood"), (0.93, 0.915, "cowl"), (0.83, 0.925, "belt"), (-1.62, 0.98, "deck"),
        (-2.355, 0.96, "tail"), (-2.445, 0.90, "tail"), (-2.425, 0.50, "tail"), (-2.41, 0.31, "valance"),
        (-2.375, 0.245, "under"),
    ],
    doors=[(0.70, -0.40)],
    gh=dict(roof_f=(0.27, 1.30), roof_r=(-0.80, 1.305), tumble=0.16, a_w=(0.13, 0.11), c_w=(0.64, 0.17),
            fixed=[(-0.415, -9.0)]),
    extras=_muscle_extras,
    interior=dict(hip=(0.42, -0.10, 0.49), rear_wall=-1.27, seat="@D:leather_black"),
    bands=[dict(y0=1.10, y1=-0.915, z0=0.252, z1=0.292, color="chrome", proud=0.01, body_only=True)],
    front=[
        ("bumper", dict(z0=0.36, z1=0.48, proud=0.05, color="chrome", bevel=0.025)),
        ("plate", dict(z=0.305, proud=0.012)),
        ("lamp", dict(kind="ind", z0=0.275, z1=0.33, x0=0.56, x1=0.80, proud=0.012)),
        ("grille", dict(z0=0.545, z1=0.735, w=1.60, bars=1, bar="gunmetal")),
        ("lamp", dict(kind="head", z0=0.57, z1=0.71, x0=0.60, x1=0.76, proud=0.024, bezel="chrome")),
        ("lamp", dict(kind="head", z0=0.57, z1=0.71, x0=0.40, x1=0.56, proud=0.024, bezel="chrome")),
    ],
    rear=[
        ("bumper", dict(z0=0.36, z1=0.48, proud=0.05, color="chrome", bevel=0.025)),
        ("ebox", dict(x=0.0, z=0.705, size=(1.64, 0.19, 0.02), color="black", proud=0.008)),
        ("lamp", dict(kind="tail", z0=0.64, z1=0.77, x0=0.54, x1=0.78, proud=0.02)),
        ("lamp", dict(kind="ind", z0=0.64, z1=0.77, x0=0.385, x1=0.525, proud=0.02)),
        ("lamp", dict(kind="rev", z0=0.64, z1=0.77, x0=0.23, x1=0.37, proud=0.02)),
        ("plate", dict(z=0.705, proud=0.02, size=(0.34, 0.11))),
        ("exhaust", dict(x=0.58, z=0.265, r=0.045, both=True)),
    ],
    body=[
        ("hood_panel", dict(width=0.62, h=0.055, m0=0.28, m1=0.02, taper=(0.80, 0.90), bevel=0.016, color=PAINT2)),
        ("box", dict(size=(0.44, 0.02, 0.03), pos=(0, 2.085, 0.878), color="black", rot=(4, 0, 0))),
        ("box", dict(size=(1.66, 0.11, 0.045), pos=(0, -2.30, 0.975), color=PAINT, rot=(10, 0, 0), bevel=0.014)),
        ("sbox", dict(y=-1.95, z=0.76, size=(0.13, 0.13, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
    ],
    inside=[
        ("box", dict(size=(1.28, 0.46, 0.13), pos=(0, -0.90, 0.31), color="@D:leather_black", bevel=0.02)),
        ("box", dict(size=(1.28, 0.11, 0.46), pos=(0, -1.18, 0.36), color="@D:leather_black", rot=(24, 0, 0),
                     base=True, bevel=0.02)),
    ],
    notes="Long flat bonnet with @Paint2 power bulge, semi-fastback, chrome bumpers, quad headlamps, wider rear "
          "tyres (wheel_width_rear), one exhaust tip each side. A decorative rear bench exists but only 2 seat markers.",
)


# ============================================================================ P2 service vehicles
def seams(mb, x, rects, proud=0.004, w=0.016, color="black"):
    """Panel seam rectangles on the plane x = const (right side, call in a mirror frame for the left).
    rects: (y0, y1, z0, z1)."""
    for (y0, y1, z0, z1) in rects:
        a, b = min(y0, y1), max(y0, y1)
        mb.box((0.012, w, z1 - z0), (x + proud - 0.006, a, (z0 + z1) * 0.5), color)
        mb.box((0.012, w, z1 - z0), (x + proud - 0.006, b, (z0 + z1) * 0.5), color)
        mb.box((0.012, b - a - w, w), (x + proud - 0.006, (a + b) * 0.5, z0), color)
        mb.box((0.012, b - a - w, w), (x + proud - 0.006, (a + b) * 0.5, z1), color)


# ---------------------------------------------------------------------------- Lifeline (ambulance)
AMB_YB, AMB_TOP, AMB_YR = 0.95, 2.60, -2.90       # box front (= cab back), box roof, box rear


def _amb_extras(car, mb):
    """Conformed (undeformed space, x = W2 is the box side)."""
    cab_back_lining(car, mb)
    W2 = car.W2
    for sxx, col in ((1, "@LightSirenB"), (-1, "@LightSirenA")):
        with mb.at(scale=(sxx, 1, 1)):
            for yy in (AMB_YB - 0.17, car.y_rear + 0.19):          # corner flashers
                mb.box((0.03, 0.22, 0.12), (W2 + 0.012, yy, 2.40), col)
            mb.box((0.03, 0.30, 0.10), (W2 + 0.012, -1.25, 2.40), "@LightAux")   # scene lamp
    # curb side (right): entry door; street side (left): compartment doors
    seams(mb, W2, [(0.66, -0.30, 0.66, 2.24)])
    mb.box((0.012, 0.56, 0.40), (W2 + 0.006, 0.18, 1.90), "glass_dark")
    mb.box((0.03, 0.035, 0.18), (W2 + 0.012, -0.20, 1.45), "chrome")
    with mb.at(scale=(-1, 1, 1)):
        seams(mb, W2, [(0.74, -0.18, 0.70, 2.20), (-2.12, AMB_YR + 0.16, 0.70, 2.20)])
        for yy in (-0.10, -2.20):
            mb.box((0.03, 0.035, 0.16), (W2 + 0.012, yy, 1.45), "chrome")


def _amb_extras2(car, mb):
    """Final space."""
    lightbar(car, mb, y=AMB_YB - 0.16, z=AMB_TOP, w=1.76, d=0.24, h=0.10)
    lightbar(car, mb, y=car.y_rear + 0.15, z=AMB_TOP, w=1.40, d=0.20, h=0.09, mark=None)
    for side in (1, -1):
        side_text(car, mb, "AMBULANCE", -1.25, 1.48, side, size=0.28, depth=0.0, color="blue")
    end_text(mb, "AMBULANCE", car.y_rear, 2.27, end=-1, size=0.13, depth=0.0, color="blue")


def _amb_lod(car, mb):
    lod_lightbar(mb, AMB_YB - 0.16, AMB_TOP, w=1.6)
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            x = car.W2 + 0.01
            P(mb, [(x, AMB_YR + 0.06, 1.08), (x, 2.70, 1.08), (x, 2.70, 1.28), (x, AMB_YR + 0.06, 1.28)], PAINT2)


CARS["car_ambulance"] = dict(
    id="car_ambulance", name="Lifeline", L=6.20, W=2.20, H=2.75, cab_H=2.20,
    wheel_r=0.40, wheel_w=0.25, wheel_w_r=0.48, dual_rear=True, axle_f=2.35, axle_r=-1.55, clearance=0.24,
    track=1.73, track_r=1.65, rim="steel", rim_r="truck_r", wheel_segs=12, rim_ratio=0.62, rim_color="aluminum", cap_color="chrome",
    sill_z=0.52, floor_z=0.50, tuck=0.025, mirror_color="plastic_black", handle_color="plastic_black",
    mirror_dims=(0.07, 0.05, 0.30, 0.17, 0.20),
    plan=[(AMB_YR, 1.0), (AMB_YB, 1.0), (AMB_YB + 0.06, 0.93), (2.86, 0.93), (3.10, 0.855)],
    upper=[
        (3.065, 0.31, "valance"), (3.10, 0.38, "nose"), (3.10, 0.80, "nose"), (3.05, 1.02, "nose"),
        (2.93, 1.09, "hood"), (2.10, 1.29, "cowl"), (2.00, 1.31, "belt"), (AMB_YB, 1.32, "bulk"),
        (AMB_YB, AMB_TOP, "roof"), (AMB_YR + 0.08, AMB_TOP, "tail"), (AMB_YR, AMB_TOP - 0.08, "tail"),
        (AMB_YR, 0.62, "tail"), (AMB_YR + 0.01, 0.40, "valance"), (AMB_YR + 0.045, 0.33, "under"),
    ],
    doors=[(1.86, 1.05)],
    gh=dict(roof_f=(1.52, 2.10), roof_r=(AMB_YB, 2.10), tumble=0.05, a_w=(0.13, 0.11), c_w=(0.06, 0.06),
            rear_glass=False, roof_top=[(1.55, 2.114), (1.43, 2.17), (1.24, 2.20), (AMB_YB, 2.20)]),
    interior=dict(hip=(0.50, 1.30, 1.02), seat="@D:fabric_gray", seat_tilt=12.0, steer_tilt=40.0, console_h=0.30,
                  lite=True),
    bands=[dict(y0=2.72, y1=AMB_YR + 0.06, z0=1.08, z1=1.28, color=PAINT2, proud=0.008)],
    front=[
        ("bumper", dict(z0=0.36, z1=0.60, proud=0.035, color="plastic_black")),
        ("plate", dict(z=0.48, proud=0.043)),
        ("ebox", dict(x=0.62, z=0.48, size=(0.16, 0.07, 0.02), color=None, proud=0.048,
                      pair_colors={1: "@LightSirenB", -1: "@LightSirenA"})),
        ("grille", dict(z0=0.70, z1=0.93, w=0.92, bars=2, frame="chrome")),
        ("lamp", dict(kind="head", z0=0.72, z1=0.93, x0=0.52, x1=0.84, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.72, z1=0.93, x0=0.855, side=0.09)),
    ],
    rear=[
        ("ebox", dict(x=0.0, z=0.47, size=(1.70, 0.12, 0.20), color="aluminum", proud=0.15)),
        ("lamp", dict(kind="tail", z0=0.84, z1=1.10, x0=0.88, side=0.05)),
        ("lamp", dict(kind="ind", z0=1.12, z1=1.26, x0=0.88, side=0.05)),
        ("lamp", dict(kind="rev", z0=0.70, z1=0.82, x0=0.88, side=0.05)),
        ("ebox", dict(x=0.0, z=1.50, size=(0.016, 1.80, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.0, z=2.41, size=(1.64, 0.016, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.82, z=1.50, size=(0.016, 1.80, 0.012), color="black", proud=0.004, pair=True)),
        ("ebox", dict(x=0.40, z=1.95, size=(0.56, 0.42, 0.012), color="glass_dark", proud=0.008, pair=True)),
        ("ebox", dict(x=0.07, z=1.40, size=(0.035, 0.20, 0.03), color="chrome", proud=0.02, pair=True)),
        ("plate", dict(z=0.80)),
        ("exhaust", dict(x=0.70, z=0.32, r=0.035)),
    ],
    body=[
        ("hood_panel", dict(inset=0.26, bevel=0.0)),
        ("sbox", dict(y=-2.40, z=1.00, size=(0.14, 0.14, 0.01), color=PAINT, proud=0.004, sides=(-1,))),
    ],
    extras=_amb_extras, extras2=_amb_extras2, lod_extras=_amb_lod,
    markers=dict(mod_roof=(0.0, -1.0, AMB_TOP), mod_rear=(0.0, AMB_YR - 0.15, 0.41)),
    notes="Van cab (2.05 wide) + 2.20 wide box body (not enterable). @Paint2 side stripe, front + rear light bars "
          "(@LightSirenA left / B right, marker siren on the front bar), corner flashers, scene lamps (@LightAux), "
          "decorative rear doors and curb-side entry door, AMBULANCE lettering. Dual rear wheels "
          "(wheel_width_rear = overall dual width). 2 seats.",
)


# ---------------------------------------------------------------------------- Blazeguard (fire engine)
FT_YD, FT_TOP, FT_YR = 1.75, 2.46, -4.10    # cab back, equipment body top, body rear


def cab_back_cap(car, mb, z0, color=PAINT, t=0.04):
    """Cab rear wall between the C pillars from z0 up to the roof (when the body behind the cab is lower)."""
    z1 = car.zrr + 0.012
    x0, x1 = car.xg(z0) + 0.006, car.xg(z1) + 0.006
    mb.box((2 * x0, t, z1 - z0), (0, car.yd - t * 0.5, z0), color, base=True, taper=(x1 / x0, 1.0))


def _ft_extras(car, mb):
    W2 = car.W2
    cab_back_cap(car, mb, FT_TOP - 0.02)
    cab_back_lining(car, mb)
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            sa = "@LightSirenA" if sxx < 0 else "@LightSirenB"
            # roll-up compartment doors (aluminium) with a lift bar
            for (ya, yb, za, zb) in ((0.88, -0.86, 0.62, 2.32), (-0.93, -1.97, 1.18, 2.32),
                                     (-2.07, FT_YR + 0.14, 0.62, 2.32)):
                mb.box((0.014, ya - yb, zb - za), (W2 + 0.007, (ya + yb) * 0.5, (za + zb) * 0.5), "aluminum")
                mb.box((0.03, ya - yb - 0.14, 0.035), (W2 + 0.016, (ya + yb) * 0.5, za + 0.15), "gray_dark")
            # pump house panel + discharge outlets (red caps)
            mb.box((0.02, 0.72, 1.50), (W2 + 0.01, 1.32, 1.52), "steel_dark")
            for yy in (1.52, 1.12):
                mb.cyl(0.065, 0.12, (W2 + 0.07, yy, 1.02), "chrome", axis="X", segs=6, cap_color="red")
            if sxx < 0:                       # operator side: gauges + valve handles
                for yy in (1.55, 1.32, 1.09):
                    mb.cyl(0.06, 0.03, (W2 + 0.035, yy, 1.98), "chrome", axis="X", segs=8, cap_color="white")
                    mb.box((0.05, 0.05, 0.10), (W2 + 0.045, yy, 1.55), "red")
            # running board under the cab doors, warning lamps on the body corners
            mb.box((0.12, 1.02, 0.05), (W2 + 0.05, 2.34, 0.84), "aluminum")
            for yy in (1.60, FT_YR + 0.12):
                mb.box((0.03, 0.18, 0.12), (W2 + 0.012, yy, 2.40), sa)
    # transverse hose reel behind the cab
    yr, zr = 1.30, FT_TOP + 0.30
    mb.cyl(0.21, 1.36, (0, yr, zr), "hazard_yellow", axis="X", segs=10)
    for sxx in (1, -1):
        mb.cyl(0.29, 0.04, (sxx * 0.70, yr, zr), "chrome", axis="X", segs=10)
        mb.box((0.05, 0.10, 0.30), (sxx * 0.78, yr, FT_TOP + 0.15), "gunmetal")
    # ladder rack + ladder
    for yy in (0.72, -3.50):
        for sxx in (1, -1):
            mb.box((0.05, 0.05, 0.44), (sxx * 0.62, yy, FT_TOP + 0.22), "gunmetal")
        mb.box((1.34, 0.06, 0.06), (0, yy, FT_TOP + 0.47), "gunmetal")
    xl, zl = 0.16, FT_TOP + 0.545
    for sxx in (1, -1):
        mb.box((0.045, 4.80, 0.09), (xl + sxx * 0.27, -1.45, zl), "aluminum")
    for k in range(9):
        mb.box((0.50, 0.035, 0.035), (xl, 0.80 - 0.5625 * k, zl), "aluminum")


def _ft_extras2(car, mb):
    lightbar(car, mb, y=3.62, z=car.H, w=2.0, d=0.28, h=0.12, bevel=0.0)


def _ft_door(car, mb, di, side, y0, y1):
    if di == 0:
        ym = (y0 + y1) * 0.5 - 0.04
        side_text(car, mb, "FIRE", ym, 1.58, side, size=0.20, depth=0.0, color="gold")


def _ft_lod(car, mb):
    lod_lightbar(mb, 3.62, car.H, w=1.8)
    mb.box((0.60, 4.80, 0.10), (0.16, -1.45, FT_TOP + 0.53), "aluminum")
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            x = car.W2 + 0.01
            P(mb, [(x, FT_YR + 0.14, 0.62), (x, 0.88, 0.62), (x, 0.88, 2.32), (x, FT_YR + 0.14, 2.32)], "aluminum")


CARS["car_firetruck"] = dict(
    id="car_firetruck", name="Blazeguard", L=8.60, W=2.50, H=3.20, cab_H=3.00,
    wheel_r=0.50, wheel_w=0.34, wheel_w_r=0.62, dual_rear=True, axle_f=3.45, axle_r=-1.45, clearance=0.45,
    rim="steel", rim_r="truck_r", rim_ratio=0.60, rim_color="chrome", cap_color="chrome", wheel_segs=12,
    arch_gap=0.06, tuck=0.0, taper_f=0.04, taper_r=0.0, sill_z=1.22, floor_z=1.18, c=0.05,
    mirror_color="chrome", handle_color="chrome", mirror_dims=(0.08, 0.06, 0.42, 0.24, 0.24),
    upper=[
        (4.265, 0.50, "valance"), (4.30, 0.57, "nose"), (4.30, 1.70, "nose"), (4.27, 1.80, "cowl"),
        (4.21, 1.83, "belt"), (3.70, 1.97, "belt"), (FT_YD, 1.98, "bulk"), (FT_YD, FT_TOP, "roof"),
        (FT_YR + 0.08, FT_TOP, "tail"), (FT_YR, FT_TOP - 0.08, "tail"), (FT_YR, 0.62, "tail"),
        (FT_YR + 0.01, 0.52, "valance"), (FT_YR + 0.045, 0.46, "under"),
    ],
    doors=[(4.02, 2.98), (2.98, 1.90)],
    gh=dict(roof_f=(4.05, 2.90), roof_r=(FT_YD, 2.90), tumble=0.06, a_w=(0.16, 0.14), c_w=(0.07, 0.07), b_w=0.10,
            rear_glass=False, roof_color=PAINT2),
    interior=dict(hip=(0.55, 3.30, 1.68), rear_hip=(0.55, 2.30, 1.70), firewall=4.10, seat="@D:fabric_dark",
                  steer_tilt=50.0, lite=2),
    bands=[dict(y0=4.25, y1=FT_YD + 0.05, z0=1.40, z1=1.52, color=PAINT2, proud=0.008)],
    front=[
        ("ebox", dict(x=0.0, z=0.70, size=(2.40, 0.30, 0.20), color="chrome", proud=0.15, bevel=0.03)),
        ("plate", dict(z=0.70, proud=0.16)),
        ("grille", dict(z0=0.95, z1=1.55, w=1.10, bars=5, frame="chrome")),
        ("lamp", dict(kind="head", z0=1.00, z1=1.16, x0=0.66, x1=1.08, bezel="chrome")),
        ("lamp", dict(kind="ind", z0=0.86, z1=0.95, x0=0.66, x1=0.88)),
        ("ebox", dict(x=0.86, z=1.40, size=(0.32, 0.12, 0.02), color=None, proud=0.012,
                      pair_colors={1: "@LightSirenB", -1: "@LightSirenA"})),
    ],
    rear=[
        ("ebox", dict(x=0.0, z=0.56, size=(2.30, 0.12, 0.20), color="aluminum", proud=0.15)),
        ("lamp", dict(kind="tail", z0=0.80, z1=1.04, x0=0.92, x1=1.16)),
        ("lamp", dict(kind="ind", z0=1.07, z1=1.19, x0=0.92, x1=1.16)),
        ("lamp", dict(kind="rev", z0=0.66, z1=0.77, x0=0.92, x1=1.16)),
        ("ebox", dict(x=0.0, z=1.50, size=(1.30, 1.56, 0.012), color="aluminum", proud=0.008)),
        ("ebox", dict(x=0.0, z=0.88, size=(1.20, 0.035, 0.03), color="gray_dark", proud=0.02)),
        ("ebox", dict(x=1.02, z=2.28, size=(0.18, 0.18, 0.02), color=None, proud=0.012,
                      pair_colors={1: "@LightSirenB", -1: "@LightSirenA"})),
        ("plate", dict(z=1.05, x=-0.66)),
        ("exhaust", dict(x=0.80, z=0.40, r=0.05)),
    ],
    extras=_ft_extras, extras2=_ft_extras2, door_extras=_ft_door, lod_extras=_ft_lod,
    markers=dict(mod_front=(0.0, 4.45, 0.55), mod_rear=(0.0, FT_YR - 0.15, 0.50), mod_roof=(0.0, 2.90, 3.0)),
    notes="Cab-over crew cab (4 doors, 4 seats, floor at 1.18) + equipment body: roll-up compartment doors, pump "
          "panel with gauges + outlets (left), hose reel and ladder rack on top, chrome bumper, light bar on the cab "
          "roof (marker siren), body corner flashers. Cab roof @Paint2. Dual rear wheels.",
)


# ---------------------------------------------------------------------------- Packmaster (box truck)
TK_YB, TK_YR, TK_ZB, TK_TOP, TK_W2 = 1.18, -3.62, 1.10, 3.30, 1.20     # cargo box: front, rear, floor, top, half width


def _tk_extras(car, mb):
    """Conformed: cab-side steps + roof marker lamps."""
    W2 = car.W2
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            for z, d in ((0.62, 0.16), (0.88, 0.10)):
                mb.box((d, 0.40, 0.05), (W2 + d * 0.5 - 0.04, 1.62, z), "aluminum")
            mb.box((0.03, 0.03, 0.55), (W2 + 0.03, 1.40, 1.45), "chrome")             # grab handle
    for x in (-0.30, 0.0, 0.30):
        mb.box((0.10, 0.05, 0.04), (x, car.yrf - 0.04, car.H + 0.012), "@LightAux")


def _tk_extras2(car, mb):
    """Final space: frame, cargo box, roll door, rear bumper, lamps, tank, exhaust."""
    yb, yr, zb, zt, w2 = TK_YB, TK_YR, TK_ZB, TK_TOP, TK_W2
    ym, ln = (yb + yr) * 0.5, yb - yr
    for sxx in (1, -1):
        mb.box((0.10, car.yd - yr + 0.05, 0.26), (sxx * 0.44, (car.yd + yr) * 0.5 - 0.02, 0.82), "charcoal")  # rails
    mb.box((2 * w2 - 0.04, ln - 0.04, 0.10), (0, ym, zb - 0.04), "black")                 # box sub-frame
    mb.box((2 * w2, ln, zt - zb), (0, ym, zb), PAINT2, base=True, bevel=0.035)              # cargo box
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            for z in (zb + 0.04, zt - 0.04):                                                  # top / bottom rails
                mb.box((0.03, ln - 0.06, 0.08), (w2 + 0.005, ym, z), "aluminum")
            mb.box((0.03, 0.08, zt - zb - 0.06), (w2 + 0.005, yb - 0.04, (zb + zt) * 0.5), "aluminum")  # front post
            mb.box((0.10, 0.10, zt - zb - 0.02), (w2 - 0.045, yr - 0.045, (zb + zt) * 0.5), "aluminum")  # rear post
            # under-ride side guard + mudflap + fuel tank (left) / battery box (right)
            mb.box((0.03, 1.15, 0.10), (w2 - 0.06, -0.475, 0.62), "gray_dark")
            mb.box((0.03, 0.06, 0.30), (w2 - 0.08, 0.0, 0.80), "gray_dark")
            mb.box((0.03, 0.06, 0.30), (w2 - 0.08, -0.95, 0.80), "gray_dark")
            mb.box((0.40, 0.02, 0.36), (0.92, car.axle_r - car.r - 0.10, 0.36), "rubber")
    mb.cyl(0.25, 0.85, (-0.86, 0.72, 0.78), "aluminum", axis="Y", segs=10)                  # fuel tank
    mb.box((0.40, 0.55, 0.36), (0.88, 0.72, 0.80), "plastic_black")                         # battery box
    mb.cyl(0.05, 0.55, (0.70, -0.62, 0.52), "chrome", axis="Y", segs=6, cap_color="black")   # tail pipe
    car.marks["exhaust"] = (0.70, -0.895, 0.52)
    # rear: door frame header + sill, roll door with ribs, handle
    yf = yr - 0.005
    mb.box((2 * w2 - 0.10, 0.10, 0.14), (0, yr - 0.045, zt - 0.08), "aluminum")
    mb.box((2 * w2 - 0.10, 0.12, 0.12), (0, yr - 0.05, zb + 0.06), "aluminum")
    mb.box((2 * w2 - 0.24, 0.012, zt - zb - 0.30), (0, yf, (zb + zt) * 0.5 + 0.01), "offwhite")
    for k in range(6):
        z = zb + 0.42 + k * 0.30
        mb.box((2 * w2 - 0.26, 0.016, 0.025), (0, yf - 0.008, z), "gray_mid")
    mb.box((0.30, 0.04, 0.05), (0, yf - 0.02, zb + 0.30), "chrome")
    # rear under-ride bumper + lamps
    mb.box((2.10, 0.10, 0.16), (0, yr - 0.03, 0.58), "black")
    for sxx in (1, -1):
        mb.box((0.08, 0.08, 0.50), (sxx * 0.62, yr + 0.02, 0.83), "black")
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            mb.box((0.22, 0.03, 0.12), (0.92, yr - 0.105, 1.30), "@LightTail")
            mb.box((0.10, 0.03, 0.12), (0.72, yr - 0.105, 1.30), "@LightReverse")
            mb.box((0.06, 0.02, 0.05), (w2 - 0.08, yr - 0.10, zt - 0.08), "@LightTail")      # clearance lamps
            mb.box((0.06, 0.02, 0.05), (w2 - 0.08, yb + 0.03, zt - 0.04), "orange")
    for sxx, col in ((1, "@LightIndR"), (-1, "@LightIndL")):
        mb.box((0.10, 0.03, 0.12), (sxx * 1.08, yr - 0.105, 1.30), col)
    mb.box((0.36, 0.016, 0.115), (0, yr - 0.09, 0.79), "white")                             # plate
    car.marks["light_tail"] = (0.92, yr - 0.12, 1.30)
    for side in (1, -1):
        side_text(car, mb, "TIDEWAY FREIGHT", ym, 2.05, side, size=0.30, depth=0.0, color="white", x=w2)


def _tk_lod(car, mb):
    yb, yr, zb, zt, w2 = TK_YB, TK_YR, TK_ZB, TK_TOP, TK_W2
    mb.box((2 * w2, yb - yr, zt - zb), (0, (yb + yr) * 0.5, zb), PAINT2, base=True)
    mb.box((1.0, car.yd - yr, 0.30), (0, (car.yd + yr) * 0.5, 0.80), "black")
    for sxx in (1, -1):
        mb.box((0.30, 0.02, 0.14), (sxx * 0.85, yr - 0.01, 1.30), "red")


CARS["car_truck"] = dict(
    id="car_truck", name="Packmaster", L=7.40, W=2.40, H=3.30, shell_W=2.20, cab_H=2.70,
    wheel_r=0.48, wheel_w=0.30, wheel_w_r=0.60, dual_rear=True, axle_f=2.62, axle_r=-1.70, clearance=0.45,
    track=1.86, track_r=1.76, rim="truck_f", rim_r="truck_r", rim_ratio=0.58, rim_color="aluminum",
    cap_color="chrome", wheel_segs=12, arch_gap=0.05, tuck=0.02, taper_f=0.06, taper_r=0.0,
    sill_z=1.10, floor_z=1.06, mirror_color="plastic_black", handle_color="chrome",
    mirror_dims=(0.08, 0.06, 0.42, 0.24, 0.24), lod_lamps=("light_head",),
    upper=[
        (3.585, 0.48, "valance"), (3.62, 0.55, "nose"), (3.62, 1.50, "nose"), (3.57, 1.60, "nose"),
        (3.45, 1.64, "hood"), (2.50, 1.80, "cowl"), (2.40, 1.84, "belt"), (1.30, 1.90, "tail"),
        (1.30, 0.52, "valance"), (1.335, 0.45, "under"),
    ],
    doors=[(2.28, 1.36)],
    gh=dict(roof_f=(2.02, 2.60), roof_r=(1.36, 2.62), tumble=0.07, a_w=(0.13, 0.11), c_w=(0.06, 0.06)),
    interior=dict(hip=(0.50, 1.80, 1.54), firewall=2.40, steer=(-0.50, 2.06, 1.86), steer_tilt=40.0,
                  seat="@D:fabric_gray", console_h=0.25, lite=2),
    front=[
        ("ebox", dict(x=0.0, z=0.66, size=(2.26, 0.26, 0.14), color="steel", proud=0.07, bevel=0.02)),
        ("plate", dict(z=0.66, proud=0.08)),
        ("grille", dict(z0=0.86, z1=1.48, w=1.00, bars=4, frame="chrome")),
        ("lamp", dict(kind="head", z0=1.22, z1=1.40, x0=0.62, x1=0.96, bezel="chrome")),
        ("lamp", dict(kind="ind", z0=1.06, z1=1.17, x0=0.62, x1=0.96)),
        ("ebox", dict(x=0.80, z=0.66, size=(0.10, 0.08, 0.06), color="red", proud=0.10, pair=True)),
    ],
    body=[
        ("hood_panel", dict(inset=0.32, h=0.03, m0=0.06, taper=(0.9, 0.97), bevel=0.0)),
    ],
    extras=_tk_extras, extras2=_tk_extras2, lod_extras=_tk_lod,
    col_extra={"box": [(sx * TK_W2, y, z) for sx in (1, -1) for y in (TK_YB, TK_YR) for z in (0.55, TK_TOP)]},
    markers=dict(mod_rear=(0.0, TK_YR - 0.08, 0.50), mod_spoiler=(0.0, TK_YR, TK_TOP), skirt_y=1.70),
    notes="Conventional-cab box truck: cab @Paint1 (2.20 wide), cargo box @Paint2 (2.40 wide, floor 1.10, not "
          "enterable) with aluminium frame and rear roll door, under-ride bumper, fuel tank, dual rear wheels. "
          "Extra collision hull col_box. 2 seats.",
)


# ---------------------------------------------------------------------------- Bulwark (armoured SWAT truck)
def back_panel(car, mb, color=PAINT, wins=(), glass="glass_dark", inner="@D:charcoal"):
    """Opaque panel filling the rear-window opening (gh rear_glass=False), double-sided, with small windows.
    wins: [(u0, u1, v0, v1)], u across (-1..1 of the opening), v up (0 = belt, 1 = roof). Conformed space."""
    cf = car.s["gh"].get("c_face", 0.07)

    def pt(u, v):
        y, z = lerp(car.yd, car.yrr, v), lerp(car.zd, car.zrr, v)
        return ((car.xg(z) - cf + 0.012) * u, y, z)
    us = sorted(set([-1.0, 1.0] + [w[0] for w in wins] + [w[1] for w in wins]))
    for a, b in zip(us, us[1:]):
        w = next((w for w in wins if w[0] <= a + 1e-6 and b <= w[1] + 1e-6), None)
        for (v0, v1) in ([(0.0, 1.0)] if w is None else [(0.0, w[2]), (w[3], 1.0)]):
            q = [pt(a, v0), pt(b, v0), pt(b, v1), pt(a, v1)]
            P(mb, q, color)
            P(mb, list(reversed(q)), inner)
        if w is not None:
            q = [pt(a, w[2]), pt(b, w[2]), pt(b, w[3]), pt(a, w[3])]
            P(mb, q, glass)
            P(mb, list(reversed(q)), glass)


def side_slit(car, mb, y0, y1, z0, z1, color="glass_dark", d=0.006):
    """Window slit lying on the (right) side-glass plane; y0 front, y1 rear. Conformed space."""
    P(mb, [(car.xg(z0) + d, y1, z0), (car.xg(z0) + d, y0, z0), (car.xg(z1) + d, y0, z1), (car.xg(z1) + d, y1, z1)],
      color)


SW_HATCH = (0.0, -1.55)


def _swat_extras(car, mb):
    H = car.H
    back_panel(car, mb, PAINT, wins=[(-0.66, -0.20, 0.42, 0.64), (0.20, 0.66, 0.42, 0.64)])
    # split windscreen centre post
    uy, uz = car.yrf - car.yc, car.zrf - car.zc
    ln = math.hypot(uy, uz)
    with mb.at((0, car.yc, car.zc), rot=(math.degrees(math.atan2(-uy, uz)), 0, 0)):
        mb.box((0.12, 0.04, ln), (0, 0.025, ln * 0.5), PAINT)
    for sxx in (1, -1):
        with mb.at(scale=(sxx, 1, 1)):
            side_slit(car, mb, -0.85, -1.75, 1.98, 2.14)
            side_slit(car, mb, -2.10, -2.80, 1.98, 2.14)
            for yy in (-1.30, -2.45):                                    # gun ports
                mb.cyl(0.065, 0.03, (car.xg(1.84) + 0.012, yy, 1.84), "gunmetal", axis="X", segs=6)
            z = car.zc + 0.13                                            # A-pillar spot lamps
            x = car.xg(z) + 0.075
            mb.box((0.06, 0.026, 0.026), (x - 0.04, car.yc - 0.115, z - 0.03), "black")
            lamp_pod(mb, (x, car.yc - 0.10, z), 0.058, 0.11, "gunmetal", "@LightAux")
            mb.box((0.20, 2.64, 0.06), (car.W2 + 0.06, 0.24, 0.62), "black")            # running board
            mb.box((0.03, 0.70, 0.58), (car.W2 + 0.012, -2.72, 1.22), PAINT2, bevel=0.0)  # armour plate
    # roof: hatch ring + lid, rail
    hx, hy = SW_HATCH
    mb.cyl(0.42, 0.10, (hx, hy, H + 0.05), "gunmetal", segs=10)
    mb.cyl(0.36, 0.05, (hx, hy, H + 0.12), PAINT, segs=10)
    mb.box((0.08, 0.10, 0.06), (hx, hy - 0.30, H + 0.16), "black")
    lightbar(car, mb, y=0.95, z=H, w=1.40, d=0.26, h=0.11, bevel=0.0)


def _swat_door(car, mb, di, side, y0, y1):
    ym = (y0 + y1) * 0.5
    if di == 0:
        side_text(car, mb, "SWAT", ym, 1.12, side, size=0.24, depth=0.0, color="white")


def _swat_extras2(car, mb):
    for side in (1, -1):
        side_text(car, mb, "POLICE", -2.72, 1.04, side, size=0.17, depth=0.0, color="white",
                  x=car.W2 + 0.027)


def _swat_lod(car, mb):
    lod_lightbar(mb, 0.95, car.H, w=1.3)
    mb.box((2.30, 0.30, 0.36), (0, car.y_front + 0.10, 0.62), "black")


CARS["car_swat"] = dict(
    id="car_swat", name="Bulwark", L=6.40, W=2.40, H=2.70, cab_H=2.52,
    wheel_r=0.50, wheel_w=0.36, axle_f=2.20, axle_r=-1.70, clearance=0.42,
    rim="steel", rim_ratio=0.58, rim_color="black", cap_color="gunmetal", wheel_segs=12,
    c=0.08, c_low=0.03, arch_gap=0.06, arch_segs=6, tuck=0.07, taper_f=0.10, taper_r=0.0,
    sill_z=0.80, floor_z=0.76, door_paint=PAINT, mirror_color="black", handle_color="black",
    upper=[
        (3.06, 0.50, "valance"), (3.10, 0.58, "nose"), (3.10, 1.30, "nose"), (3.02, 1.40, "nose"),
        (2.92, 1.44, "hood"), (1.95, 1.62, "cowl"), (1.85, 1.64, "belt"), (-3.12, 1.66, "tail"),
        (-3.12, 0.60, "tail"), (-3.11, 0.50, "valance"), (-3.08, 0.43, "under"),
    ],
    doors=[(1.64, 0.55), (0.55, -0.50)],
    gh=dict(roof_f=(1.40, 2.42), roof_r=(-3.12, 2.42), tumble=0.16, a_w=(0.20, 0.17), b_w=0.14, c_w=(0.10, 0.10),
            rear_glass=False, roof_color=PAINT2, door_frame=0.17, frame_color=PAINT,
            fixed=[(-0.52, -9.0, PAINT, "@D:charcoal")]),
    interior=dict(hip=(0.52, 0.75, 1.24), rear_hip=(0.52, -0.25, 1.26), cargo=dict(z=0.78),
                  seat="@D:fabric_dark", steer_tilt=30.0, lite=2),
    front=[
        ("ebox", dict(x=0.0, z=0.66, size=(2.30, 0.36, 0.30), color="black", proud=0.12)),
        ("ebox", dict(x=0.50, z=0.95, size=(0.10, 0.36, 0.10), color="black", proud=0.10, pair=True)),
        ("ebox", dict(x=0.0, z=0.66, size=(0.50, 0.20, 0.06), color="gunmetal", proud=0.16)),
        ("ebox", dict(x=0.86, z=0.60, size=(0.10, 0.08, 0.08), color="hazard_yellow", proud=0.17, pair=True)),
        ("plate", dict(z=0.80, proud=0.13, x=-0.62)),
        ("grille", dict(z0=0.86, z1=1.30, w=1.10, bars=0, vertical=7, frame="black", inner="black",
                        bar="gunmetal")),
        ("lamp", dict(kind="head", z0=1.12, z1=1.28, x0=0.70, x1=0.98, bezel="black")),
        ("lamp", dict(kind="ind", z0=0.97, z1=1.07, x0=0.70, x1=0.98)),
        ("ebox", dict(x=0.84, z=1.20, size=(0.04, 0.24, 0.05), color="black", proud=0.04, pair=True)),
    ],
    rear=[
        ("ebox", dict(x=0.0, z=0.52, size=(2.10, 0.16, 0.14), color="black", proud=0.05)),
        ("lamp", dict(kind="tail", z0=1.30, z1=1.48, x0=0.86, x1=1.04)),
        ("lamp", dict(kind="ind", z0=1.12, z1=1.26, x0=0.86, x1=1.04)),
        ("lamp", dict(kind="rev", z0=0.96, z1=1.08, x0=0.86, x1=1.04)),
        ("ebox", dict(x=0.0, z=1.48, size=(0.016, 1.70, 0.012), color="black", proud=0.004)),
        ("ebox", dict(x=0.10, z=1.30, size=(0.04, 0.18, 0.04), color="black", proud=0.03, pair=True)),
        ("plate", dict(z=0.80)),
        ("exhaust", dict(x=0.75, z=0.42, r=0.05)),
    ],
    body=[
        ("hood_panel", dict(width=1.30, h=0.03, m0=0.10, m1=0.05, color=PAINT2, bevel=0.0)),
    ],
    extras=_swat_extras, extras2=_swat_extras2, door_extras=_swat_door, lod_extras=_swat_lod,
    markers=dict(mod_front=(0.0, 3.22, 0.48), mod_rear=(0.0, -3.17, 0.44), mod_roof=(0.0, -0.40, 2.52),
                 extra={"hatch": (SW_HATCH[0], SW_HATCH[1], 2.52 + 0.15)}),
    notes="Armoured truck: faceted body, thick-framed slit windows, split windscreen, ram bumper with winch, running "
          "boards, roof hatch (extra marker `hatch` on top of the lid), light bar (marker siren), pillar spot lamps. "
          "4 doors / 4 seats; troop bay behind the second row (not seated). Roof + hood plate @Paint2.",
)


# ============================================================================ entry points
def build(car_id):
    car = Car(CARS[car_id])
    car.build()
    return car


def parts_of(root):
    parts, markers = [], []
    for o in sorted(root.children_recursive, key=lambda o: o.name):
        n = o.name.split("__", 1)[1] if "__" in o.name else o.name
        (parts if o.type == "MESH" else markers).append(n)
    return parts, markers


def tri_split(root):
    lod0 = lod1 = col = 0
    for o in root.children_recursive:
        if o.type != "MESH":
            continue
        o.data.calc_loop_triangles()
        t = len(o.data.loop_triangles)
        n = o.name.split("__", 1)[1]
        if n == "lod1":
            lod1 += t
        elif n.startswith("col_"):
            col += t
        else:
            lod0 += t
    return lod0, lod1, col


def entry(car):
    s = car.s
    root = car.root
    st = K.asset_stats(root)
    parts, markers = parts_of(root)
    lod0, lod1, col = tri_split(root)
    it = s["interior"]
    e = {
        "id": car.id, "name": s.get("name", ""), "glb": "vehicles/" + car.id, "category": s["category"],
        "size": [round(v, 3) for v in st["size"]], "tris": lod0, "tris_lod1": lod1, "tris_col": col,
        "parts": parts, "markers": markers,
        "wheel_radius": car.r, "wheel_width": s["wheel_w"], "wheelbase": round(car.axle_f - car.axle_r, 3),
        "track": round(car.track_f, 3), "clearance": car.clr,
        "doors": 2 * len(s.get("doors") or []), "seats": 2 + (2 if it["rear_hip"] else 0),
        "notes": s.get("notes", ""),
    }
    wr = s["wheel_w_r"]
    if wr and abs(wr - s["wheel_w"]) > 1e-6:
        e["wheel_width_rear"] = wr
        e["track_rear"] = round(car.track_r, 3)
    e["axle_front_y"] = car.axle_f
    e["axle_rear_y"] = car.axle_r
    e["body_size"] = [s["W"], car.L, s["H"]]
    return e


def update_manifest(e):
    data = {"assets": []}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as f:
            data = json.load(f)
    assets = [a for a in data.get("assets", []) if a.get("id") != e["id"]]
    assets.append(e)
    order = list(CARS.keys())
    assets.sort(key=lambda a: order.index(a["id"]) if a["id"] in order else 999)
    data["assets"] = assets
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return len(assets)


def make(car_id, export=True, save=False):
    """Build one vehicle, export its GLB and update the manifest."""
    car = build(car_id)
    e = entry(car)
    if export:
        K.export_asset(car.root, "vehicles/" + car_id)
        update_manifest(e)
    if save:
        K.save_master()
    return e


def build_all(ids=None, save=True):
    out = []
    for cid in (ids or list(CARS.keys())):
        e = make(cid, export=True, save=False)
        out.append((cid, e["tris"], e["tris_lod1"], e["size"]))
    if save:
        K.save_master()
    return out
