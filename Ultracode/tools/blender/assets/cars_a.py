"""cars_a - compact, sports and muscle (vehicle artist cars_a), built on car_kit.

Run inside an execute_blender_code call (after the gta_bl header, with tools/blender/assets on
sys.path):

    import car_kit as K, cars_a as CA
    importlib.reload(K); importlib.reload(CA)
    CA.build("compact")            # slot cars/1   (rebuilds an existing one)
    CA.build("sports")             # slot cars/2   (has the extra part Roof_Convertible)
    CA.build("muscle")             # slot cars/3
    CA.export("compact")           # validate + vehicles/compact.glb   (same for the others)
    CA.group_preview()             # qa/blender_previews/veh_cars_a_group.png
    G.save()

car_kit.py is NOT edited.  Everything the kit cannot do lives in the subclass `CarA`, which derives
from car_refine.Refined (critic pass: interior-coloured headliner / pillar insides, dash details,
rear-view mirror, head rests kept under the rear glass, LOD cabin floor - see car_refine.py):

  * staggered wheels:  params["rear"] = dict(wheel_r=, wheel_w=, track=, wheel_style=)  gives the rear
    axle its own wheel mesh, arch radius and track (Wheel_RL/RR share the mesh '<asset>:WheelRear').
  * params["targa"] = True: the roof slab becomes the separate object `Roof_Convertible` (origin on
    its rear hinge line = rear edge of the slab, params["targa_hinge_drop"] below the roof top); fixed
    parts are the windshield header, the two rear posts and a roll bar between them.  In Godot it
    folds back with +rotation.x (VehicleSpec.roof_fold_angle = 3.35 rad: the flipped slab then slopes
    from roof height down onto the engine cover between the buttresses) - or simply hide it.
  * params["mid_engine"] = True: engine block under `Trunk` (the engine cover), luggage well under
    `Hood`.  params["trunk_inset"]: narrower lid, body-coloured shoulders left and right of it.
  * own tail pipes (`tail_pipes`) + a Mod_Exhaust_A that sleeves them, `Exhaust_L/_R` markers for
    two-pipe cars (the single `Exhaust` marker is always there as well).

The three cars are subclasses (Compact, Sports, Muscle) that override single build steps
(front_fascia, rear_fascia, details, closures, single mods) - see each class.
"""
import bpy
from math import sin, cos, pi, sqrt, radians, asin, atan2

import gta_bl as G
import car_kit as K
import car_refine as R

interp = K.interp
VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top", "back")


# ------------------------------------------------------------------------------------------------
# CarA - kit car + staggered wheels, targa roof, mid engine, own tail pipes
# ------------------------------------------------------------------------------------------------
class CarA(R.Refined):

    def __init__(self, params=None, location=(0, 0, 0), collection="Vehicles/Cars"):
        p = dict(K.DEFAULTS)
        p.update(params or {})
        rear = p.get("rear") or {}
        gap = p["arch_gap"]
        self.ax = {
            "F": dict(y=p["axle_f"], r=p["wheel_r"], w=p["wheel_w"], track=p["track"], style=p["wheel_style"]),
            "R": dict(y=p["axle_r"], r=rear.get("wheel_r", p["wheel_r"]), w=rear.get("wheel_w", p["wheel_w"]),
                      track=rear.get("track", p["track"]), style=rear.get("wheel_style", p["wheel_style"])),
        }
        for a in self.ax.values():
            a["Ra"] = a["r"] + gap
        self.staggered = any(self.ax["F"][k] != self.ax["R"][k] for k in ("r", "w", "style"))
        self._rear_wheel = None
        self.pipes = []
        K.Car.__init__(self, params, location, collection)
        # the kit keeps ONE arch radius / wheel centre height / well wall: use the safe extremes for the
        # few places that are not overridden below (cabin wheel-houses, skirts, repeaters)
        self.Ra = max(a["Ra"] for a in self.ax.values())
        self.zc = max(a["r"] for a in self.ax.values())
        self.x_well = min(a["track"] / 2.0 - a["w"] / 2.0 - 0.10 for a in self.ax.values())

    # ---------------------------------------------------------------- per-axle arches
    def _axle(self, yc):
        return min(self.ax.values(), key=lambda a: abs(a["y"] - yc))

    def arch_z(self, y):
        z = -1.0
        for a in self.ax.values():
            d = abs(y - a["y"])
            if d < a["Ra"]:
                z = max(z, a["r"] + sqrt(a["Ra"] * a["Ra"] - d * d))
        return z

    def _arch_samples(self, yc, n=None, extra=0.0):
        a = self._axle(yc)
        n = n or self.p["arch_segs"]
        zb = interp(self.bottom_keys, yc)
        s = (zb - a["r"]) / a["Ra"]
        if s >= 1.0:
            return []
        t0 = asin(max(-1.0, min(1.0, s))) - extra
        out = []
        for i in range(n + 1):
            t = pi - t0 - (pi - 2 * t0) * i / n
            out.append((yc + a["Ra"] * cos(t), a["r"] + a["Ra"] * sin(t)))
        return out

    def _arch_lips(self):
        p, b = self.p, self.body
        if not p["arch_lip"]:
            return
        mat = self._mat(p["arch_lip"])
        for tag, a in self.ax.items():
            yc, Ra, zc = a["y"], a["Ra"], a["r"]
            fl = (p.get("arch_flare") or {}).get(tag, 0.0)
            pts = self._arch_samples(yc, extra=0.02)
            if not pts:
                continue
            secs = []
            for y, z in pts:
                dy_, dz_ = (y - yc) / Ra, (z - zc) / Ra
                xe = self.side_x(y, max(z, 0.05))
                xi, xo = xe - 0.03, xe + 0.022 + fl
                ring = []
                for x, r in ((xi, Ra - 0.008), (xo, Ra - 0.008), (xo, Ra + 0.022), (xo - 0.016, Ra + 0.046 + fl), (xi, Ra + 0.046 + fl)):
                    ring.append((x, yc + dy_ * r, zc + dz_ * r))
                secs.append(ring)
            b.loft(secs, mat, mirror=True)

    def side_strips(self):
        p = self.p
        if not p["side_strip"]:
            return
        cuts = []
        for a in self.ax.values():
            dz = p["swage_z"] - a["r"]
            if abs(dz) < a["Ra"]:
                h = sqrt(a["Ra"] ** 2 - dz ** 2) + 0.06
                cuts.append((a["y"] - h, a["y"] + h))
        cuts += [(a - 0.004, b + 0.004) for _, a, b in self.doors]
        cuts.sort()
        y = self.y_r + 0.03
        end = self.y_f - 0.03
        for a, b in cuts + [(end, end)]:
            if a - y > 0.06:
                self._strip_loft(self.body, y, min(a, end), both=True)
            y = max(y, b)

    # ---------------------------------------------------------------- wheels
    def wheel_positions(self):
        out = []
        for tag in ("F", "R"):
            a = self.ax[tag]
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                out.append(("Wheel_%s%s" % (tag, sfx), (side * a["track"] / 2.0, a["y"], a["r"])))
        return out

    def wheels(self):
        a = self.ax["F"]
        K.build_wheel(self.mb("Wheel"), self.M, a["r"], a["w"], a["style"])
        if self.staggered:
            r = self.ax["R"]
            self._rear_wheel = K.build_wheel(K.MB(), self.M, r["r"], r["w"], r["style"])

    def finish(self):
        rw = self._rear_wheel
        root = K.Car.finish(self)
        if rw is not None:
            tmp = rw.obj(self.n("WheelRearTmp"), root, smooth=35.0)
            me = tmp.data
            me.name = self.n("WheelRear")
            for nm in ("Wheel_RL", "Wheel_RR"):
                self.objects[nm].data = me
            bpy.data.objects.remove(tmp, do_unlink=True)
            self._rear_wheel = None
        return root

    # ---------------------------------------------------------------- surface helpers
    def top_z(self, y, x=0.0):
        """Height of the hood / deck surface at (x, y), crown included."""
        p = self.p
        zt = self.zt(y)
        bx = self.belt_x(y)
        cw = min(p["crown_w"], bx * 0.7)
        cz = zt + p["crown"]
        ax = abs(x)
        if ax <= cw:
            return cz
        if ax >= bx:
            return zt
        return cz + (zt - cz) * (ax - cw) / (bx - cw)

    def top_keys(self, y0, y1):
        return [y0] + [y for y, _ in self.top if y0 + 0.01 < y < y1 - 0.01] + [y1]

    def strip_on_top(self, mb, y0, y1, x0, x1, mat, lift=0.006, th=0.02):
        """Thin slab lying on the hood / deck between x0..x1 (keep it on the flat centre facet)."""
        secs = []
        for y in self.top_keys(y0, y1):
            z = self.top_z(y, (x0 + x1) / 2.0)
            secs.append([(x0, y, z - th), (x1, y, z - th), (x1, y, z + lift), (x0, y, z + lift)])
        mb.loft(secs, mat)

    def details_plain(self, antenna=True, fuel_cap=True):
        """Kit details() with switches (wipers and side repeaters always)."""
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy = g["cy"]
        for sx in (-1.0, 1.0):
            x0 = sx * 0.08 - 0.30
            b.box((0.46, 0.02, 0.016), (x0 + 0.21, cy + 0.012, g["zc"] + 0.035 + p["crown"] * 0.5), M["trim"], rot=(0, radians(-4), radians(3)))
        ry = p["axle_r"] + 0.10
        fz = self.arch_z(ry) + 0.12
        if fuel_cap and fz < self.zt(ry) - 0.05:
            b.box((0.012, 0.12, 0.10), (self.side_x(ry, fz) + 0.002, ry, fz), M["paint"], bevel=0.004)
        if antenna:
            b.cyl(0.008, 0.36, (g["xr"] - 0.12, g["rr"] + 0.02, g["rz"] + 0.14), M["trim"], axis='Z', segments=5, rot=(radians(-28), 0, 0))
        fy = p["axle_f"] - self.ax["F"]["Ra"] - 0.10
        fz2 = p["swage_z"] + 0.09
        if not self._in_door(fy):
            b.box((0.014, 0.07, 0.03), (self.side_x(fy, fz2) + 0.002, fy, fz2), M["indicator"], mirror=True)

    def bumper(self, front, prof, mat, wrap):
        self.body.sweep(self.u_path(front, wrap), prof, mat)

    # ---------------------------------------------------------------- exhaust
    def tail_pipes(self, xs, z, r=0.034, length=0.24, out=0.10, bore=0.72):
        """Chrome tail pipes (tips `out` behind the shell end).  Registers them for Mod_Exhaust_A and
        for the Exhaust / Exhaust_L / Exhaust_R markers."""
        b, M = self.body, self.M
        yt = self.y_r - out
        self.pipes = []
        for x in xs:
            b.cyl(r, length, (x, yt + length / 2.0, z), M["chrome"], axis='Y', segments=8)
            b.cyl(r * bore, 0.02, (x, yt + 0.006, z), M["under"], axis='Y', segments=8)
            self.pipes.append((x, yt, z, r))
        if len(xs) > 1 and max(xs) - min(xs) < 0.4:
            self.exhaust_pos = ((min(xs) + max(xs)) / 2.0, yt - 0.02, z)
        else:
            self.exhaust_pos = (min(xs), yt - 0.02, z)

    def mod_exhaust(self, mb):
        """Big-bore sleeves over the stock pipes plus a second tip beside each one."""
        if not self.pipes:
            return K.Car.mod_exhaust(self, mb)
        M = self.M
        for (x, yt, z, r) in self.pipes:
            sx = 1.0 if x >= 0 else -1.0
            R = r * 1.45 + 0.004
            for dx in (0.0, sx * (2 * R + 0.014)):
                xx = x + dx
                mb.cyl(R, 0.22, (xx, yt - 0.03 + 0.11, z), M["chrome"], axis='Y', segments=10, radius2=R * 0.86)
                mb.cyl(R * 0.74, 0.02, (xx, yt - 0.03 + 0.006, z), M["under"], axis='Y', segments=10)
            mb.box((4 * R + 0.06, 0.10, 0.024), (x + sx * (R + 0.007), yt + 0.12, z + R + 0.016), M["trim"])

    def markers(self):
        K.Car.markers(self)
        if len(self.pipes) >= 2:
            lo = min(self.pipes, key=lambda q: q[0])
            hi = max(self.pipes, key=lambda q: q[0])
            G.empty(self.n("Exhaust_L"), self.root, (lo[0], lo[1] - 0.02, lo[2]), rotation=(0, 0, pi))
            G.empty(self.n("Exhaust_R"), self.root, (hi[0], hi[1] - 0.02, hi[2]), rotation=(0, 0, pi))

    # ---------------------------------------------------------------- targa greenhouse
    def greenhouse(self):
        if not self.p.get("targa"):
            return R.Refined.greenhouse(self)
        before = set(self.body.bm.faces)
        self.targa_greenhouse()
        self.headliner([f for f in self.body.bm.faces if f not in before])

    def targa_greenhouse(self):
        p = self.p
        M, b = self.M, self.body
        g = self._gh()
        cy, dy, xc, zc, xd, zd, xr, rz, zR, rf, rr = (g[k] for k in ("cy", "dy", "xc", "zc", "xd", "zd", "xr", "rz", "zR", "rf", "rr"))
        t = p["roof_t"]
        pw = p["pillar_w"]

        def rring(y, drop, narrow):
            x1 = xr - narrow
            x0 = max(x1 - 0.12, 0.05)
            return [(-x1, y, zR - t - drop * 0.4), (-x1, y, zR - drop), (-x0, y, rz - drop), (x0, y, rz - drop),
                    (x1, y, zR - drop), (x1, y, zR - t - drop * 0.4)]
        ov = 0.05
        hd = p.get("targa_header", 0.09)
        seam = 0.008
        pc0, pc1 = p["c_pillar"]
        # fixed windshield header
        b.loft([rring(rf - hd, 0.0, 0.0), rring(rf - 0.04, 0.0, 0.0), rring(rf + ov, 0.04, 0.012)], M["paint"])
        # fixed roll bar between the rear posts (sits inside the roof slab while the roof is up)
        b.box((2 * xr - 0.02, pc1, 0.03), (0, rr + pc1 / 2.0, zR - 0.057), M["trim"])
        # the folding roof: the whole slab from the rear posts to the header, hinged at its rear edge
        y0, y1 = rr - ov, rf - hd - seam
        rc = self.mb("Roof_Convertible")
        rm = self._mat(p["roof_mat"])
        # last ring edge = underside of the slab (it faces up when the roof is folded): a dark roof keeps
        # its own material there (one surface, reads as a tonneau panel), a painted roof gets the lining
        lining = rm if p["roof_mat"] == "trim" else M["interior"]
        rc.loft([rring(y0, 0.04, 0.012), rring(rr + 0.09, 0.0, 0.0), rring(y1, 0.0, 0.0)],
                mats=[rm, rm, rm, rm, rm, lining], cap_mat=rm)
        # hinge line = rear edge of the slab, p["targa_hinge_drop"] below the roof top.  The drop decides
        # where the flipped slab ends up: with 0.08 and the game's fold angle (3.35 rad about +X) its
        # rear edge rests on the engine-cover louvres and its front edge stays at roof height, so the
        # stowed roof reads as a panel sloping down between the buttresses (0.04 left it hovering).
        self.origins["Roof_Convertible"] = ((0.0, y0, rz - p.get("targa_hinge_drop", 0.04)), None)
        self.roof_panel = (y0, y1)
        zp = zR - 0.012
        pa = p["a_pillar"]
        b.loft([[(xc, cy, zc - 0.02), (xc - pw, cy, zc - 0.02), (xc - pw, cy - pa, zc - 0.02), (xc, cy - pa, zc - 0.02)],
                [(xr, rf, zp), (xr - pw, rf, zp), (xr - pw, rf - pa, zp), (xr, rf - pa, zp)]], M["paint"], mirror=True)
        b.loft([[(xd, dy, zd - 0.02), (xd, dy + pc0, zd - 0.02), (xd - pw, dy + pc0, zd - 0.02), (xd - pw, dy, zd - 0.02)],
                [(xr, rr, zp), (xr, rr + pc1, zp), (xr - pw, rr + pc1, zp), (xr - pw, rr, zp)]], M["paint"], mirror=True)
        gi = 0.014
        ws = self.mb("Glass_Windshield")
        ws.face([(-(xc - 0.03), cy - gi, zc - 0.01), (xc - 0.03, cy - gi, zc - 0.01), (xr - 0.03, rf - gi, zR - 0.01),
                 (-(xr - 0.03), rf - gi, zR - 0.01)], M["glass"], want=(0, 1, 1))
        rg = self.mb("Glass_Rear")
        rg.face([(-(xd - 0.03), dy + gi, zd - 0.01), (xd - 0.03, dy + gi, zd - 0.01), (xr - 0.03, rr + gi, zR - 0.01),
                 (-(xr - 0.03), rr + gi, zR - 0.01)], M["glass"], want=(0, -1, 1))
        belt = [y for y in self.ys if dy + 0.03 < y < cy - 0.03 and any(abs(y - ky) < 1e-6 for ky, _ in self.top)]
        belt = [dy + 0.03] + belt + [cy - 0.03]
        side = [(self.belt_x(y) - gi, y, self.zt(y) - 0.01) for y in belt] + [(xr - gi, rf - 0.03, zR - 0.01), (xr - gi, rr + 0.03, zR - 0.01)]
        self.mb("Glass_R").face(side, M["glass"], want=(1, 0, 0.3))
        self.mb("Glass_L").face([(-q[0], q[1], q[2]) for q in side], M["glass"], want=(-1, 0, 0.3))

    # ---------------------------------------------------------------- shell extras for a narrow lid
    def skin(self):
        K.Car.skin(self)
        inset = self.p.get("trunk_inset")
        if inset and self.trunk:
            b, M = self.body, self.M
            ys = [y for y in self.ys if self.trunk[0] - 1e-6 <= y <= self.trunk[1] + 1e-6]
            S = [self.section(y) for y in ys]
            for i in range(len(ys) - 1):
                ya, yb = ys[i], ys[i + 1]
                A, B = S[i][self.P1], S[i + 1][self.P1]
                xa, xb = A[0] - inset, B[0] - inset
                qa, qb = (xa, ya, self.top_z(ya, xa)), (xb, yb, self.top_z(yb, xb))
                b.face([qa, A, B, qb], M["paint"], mirror=True, want=(0, 0, 1))
                b.face([qa, qb, (xb, yb, self.zt(yb) - 0.045), (xa, ya, self.zt(ya) - 0.045)], M["under"], mirror=True, want=(-1, 0, 0))

    def bays(self):
        """Kit bays() with a selectable engine position and support for the narrow lid."""
        p, M, b = self.p, self.M, self.body
        eng = "trunk" if p.get("mid_engine") else "hood"
        for rng, kind in ((self.hood, "hood"), (self.trunk, "trunk")):
            if not rng:
                continue
            ys = [y for y in self.ys if rng[0] - 1e-6 <= y <= rng[1] + 1e-6]
            is_eng = kind == eng
            mat = M["under"] if is_eng else M["interior"]
            wx = self.x_well - 0.06
            y0, y1 = rng[0] + 0.07, rng[1] - 0.07
            depth = 0.22 if kind == "hood" else 0.34
            depth = (p.get("bay_depth") or {}).get(kind, depth)
            zmin = min(self.zt(y) for y in ys) - 0.045 - depth
            inset = p.get("trunk_inset") if kind == "trunk" else None
            for ya, yb in zip(ys[:-1], ys[1:]):
                za, zb = self.zt(ya) - 0.045, self.zt(yb) - 0.045
                xa, xb = self.belt_x(ya), self.belt_x(yb)
                if inset:
                    xa, xb = xa - inset, xb - inset
                b.face([(wx, ya, za), (xa, ya, za), (xb, yb, zb), (wx, yb, zb)], mat, mirror=True, want=(0, 0, 1))
                ca, cb = max(ya, y0), min(yb, y1)
                if ya < y0:
                    ye = min(yb, y0)
                    b.face([(-wx, ya, za), (wx, ya, za), (wx, ye, self._zl(ya, yb, za, zb, ye)),
                            (-wx, ye, self._zl(ya, yb, za, zb, ye))], mat, want=(0, 0, 1))
                if yb > y1:
                    ys_ = max(ya, y1)
                    b.face([(-wx, ys_, self._zl(ya, yb, za, zb, ys_)), (wx, ys_, self._zl(ya, yb, za, zb, ys_)),
                            (wx, yb, zb), (-wx, yb, zb)], mat, want=(0, 0, 1))
                if cb > ca:
                    zca, zcb = self._zl(ya, yb, za, zb, ca), self._zl(ya, yb, za, zb, cb)
                    b.face([(wx, ca, zmin), (wx, cb, zmin), (wx, cb, zcb), (wx, ca, zca)], mat, mirror=True, want=(-1, 0, 0))
            z0 = self.zt(y0) - 0.045
            z1 = self.zt(y1) - 0.045
            b.face([(-wx, y0, zmin), (wx, y0, zmin), (wx, y0, z0), (-wx, y0, z0)], mat, want=(0, 1, 0))
            b.face([(-wx, y1, zmin), (wx, y1, zmin), (wx, y1, z1), (-wx, y1, z1)], mat, want=(0, -1, 0))
            b.face([(-wx, y0, zmin), (wx, y0, zmin), (wx, y1, zmin), (-wx, y1, zmin)], mat, want=(0, 0, 1))
            if is_eng:
                self.engine_block(y0, y1, zmin, depth, wx)

    def engine_block(self, y0, y1, zmin, depth, wx):
        M, b = self.M, self.body
        ym = (y0 + y1) / 2.0
        ln = min(0.62, (y1 - y0) * 0.7)
        b.box((0.46, ln, depth * 0.62), (0, ym, zmin + depth * 0.31), M["trim"], bevel=0.02)
        b.box((0.30, ln * 0.8, 0.05), (0, ym, zmin + depth * 0.62 + 0.02), M["chrome"], bevel=0.012)
        b.cyl(0.05, ln * 0.7, (wx * 0.62, ym, zmin + depth * 0.45), M["chrome"], axis='Y', segments=8)
        b.box((0.18, 0.24, depth * 0.5), (-wx * 0.66, y0 + 0.16, zmin + depth * 0.25), M["trim"], bevel=0.012)

    def closures(self):
        inset = self.p.get("trunk_inset")
        if not inset or not self.trunk:
            return K.Car.closures(self)
        trunk = self.trunk
        self.trunk = None
        try:
            K.Car.closures(self)
        finally:
            self.trunk = trunk
        p, M = self.p, self.M
        mb = self.mb("Trunk")
        gap, th = 0.010, 0.032
        ya, yb = trunk[0] + gap, trunk[1] - gap
        ys = [ya] + [s for s in self.ys if ya + 0.02 < s < yb - 0.02] + [yb]
        rings = []
        for y in ys:
            bx = self.belt_x(y)
            x1 = bx - inset - gap
            cw = min(p["crown_w"], bx * 0.7, x1 - 0.03)
            cz = self.zt(y) + p["crown"]
            ze = self.top_z(y, x1)
            rings.append([(-x1, y, ze), (-cw, y, cz), (cw, y, cz), (x1, y, ze), (x1, y, ze - th), (-x1, y, ze - th)])
        mb.loft(rings, mats=[M["paint"], M["paint"], M["paint"], M["paint"], M["trim"], M["paint"]], cap_mat=M["paint"])
        self.origins["Trunk"] = ((0.0, yb, self.zt(yb)), None)


# ------------------------------------------------------------------------------------------------
# COMPACT - 3.70 m three-door city hatchback: tall glasshouse, round lamps, dark plastic bumpers
# ------------------------------------------------------------------------------------------------
COMPACT = dict(K.DEFAULTS)
COMPACT.update(
    name="compact",
    width=1.66, height=1.50,
    axle_f=1.22, axle_r=-1.20, wheel_r=0.30, wheel_w=0.19, track=1.42, wheel_style="steel",
    arch_lip="trim",
    # short nose, long roof, upright tail (shell 3.60 m + 2 x 5 cm bumper)
    top=[(-1.80, 0.86), (-1.66, 0.96), (0.80, 0.94), (1.60, 0.84), (1.80, 0.76)],
    bottom=[(-1.80, 0.36), (-1.56, 0.24), (1.56, 0.22), (1.80, 0.30)],
    plan=[(-1.80, 0.87), (-1.64, 0.97), (-1.48, 1.0), (1.48, 1.0), (1.66, 0.955), (1.80, 0.85)],
    swage_z=0.58,
    cowl_y=0.80, roof_f=0.22, roof_r=-1.44, deck_y=-1.66,
    tumble=0.12, a_pillar=0.12, c_pillar=(0.20, 0.15),
    doors=[("F", -0.30, 0.78)], trunk=None,
    tub_z=0.25, seat_x=0.34, seat_f_y=-0.20, seat_r_y=-0.98, seat_z=0.50, seat_color="Khaki",
    head=None, grille=None,
    tail=dict(w=0.17, h=0.24, inset=0.025, z=None),
    bumper_f=dict(h=0.24, out=0.06, wrap=0.20),
    bumper_r=dict(h=0.22, out=0.06, wrap=0.20),
    plate_f=True, plate_r=False, exhaust=None,
    mods=list(K.FULL_MODS), spoiler_at="roof",
)


class Compact(CarA):

    def _dark(self, fn):
        """Run a kit fascia step with the bumper in dark plastic instead of paint."""
        M = self.M
        paint = M["paint"]
        M["paint"] = M["trim"]
        try:
            fn(self)
        finally:
            M["paint"] = paint

    def front_fascia(self):
        self._dark(K.Car.front_fascia)
        M, b = self.M, self.body
        yf = self.y_f
        lz, lx, lr = 0.63, 0.46, 0.098
        b.box((1.24, 0.03, 0.21), (0, yf + 0.003, lz), M["trim"])                       # dark mask
        b.cyl(lr + 0.014, 0.034, (lx, yf + 0.022, lz), M["chrome"], axis='Y', segments=10, mirror=True)
        b.cyl(lr, 0.03, (lx, yf + 0.036, lz), M["head"], axis='Y', segments=10, mirror=True)
        gw = lx - lr - 0.05
        for dz in (-0.04, 0.04):
            b.box((2 * gw, 0.014, 0.02), (0, yf + 0.022, lz + dz), M["chrome"])
        b.box((0.10, 0.02, 0.055), (0, yf + 0.026, lz), M["paint"], bevel=0.012)        # badge
        self.head_pos = (lx, yf + 0.06, lz)
        self.grille_box = (gw - 0.01, lz, 0.13)

    def rear_fascia(self):
        self._dark(K.Car.rear_fascia)
        M, b = self.M, self.body
        yr = self.y_r
        z0 = self.bumper_r_z[0]
        pz = 0.69
        b.box((0.40, 0.02, 0.16), (0, yr + 0.002, pz), M["trim"])                       # plate recess
        b.box((0.32, 0.016, 0.12), (0, yr - 0.012, pz), M["plate"])
        b.box((0.22, 0.03, 0.025), (0, yr - 0.012, pz + 0.105), M["chrome"], bevel=0.006)  # hatch handle
        zs = self.zt(yr) - 0.012
        b.box((2 * self.belt_x(yr) - 0.02, 0.016, 0.014), (0, yr + 0.001, zs), M["trim"])  # hatch shut line
        self.tail_pipes([-0.40], z0 - 0.045, r=0.03)

    def details(self):
        K.Car.details(self)
        M, b = self.M, self.body
        g = self._gh()
        dy, rr, zd, zR, rz, xr = g["dy"], g["rr"], g["zd"], g["zR"], g["rz"], g["xr"]
        # roof visor over the hatch glass + high-mounted stop lamp
        b.box((2 * xr - 0.10, 0.17, 0.028), (0, rr - 0.09, rz - 0.047), M["paint"], rot=(radians(-9), 0, 0), bevel=0.008)
        b.box((0.30, 0.02, 0.02), (0, rr - 0.178, rz - 0.058), M["tail"])
        # rear wiper on the hatch glass
        t = 0.06 / max(zR - zd, 0.01)
        b.box((0.36, 0.014, 0.016), (0.08, dy + 0.014 + (rr - dy) * t - 0.014, zd + 0.06), M["trim"], rot=(0, radians(5), 0))
        b.box((0.04, 0.03, 0.03), (-0.09, dy + 0.004, zd + 0.035), M["trim"])

    def lod(self):
        CarA.lod(self)
        M = self.M
        lb = self.mb("Body_LOD1")
        hx, hy, hz = self.head_pos
        lb.box((0.18, 0.04, 0.16), (hx, self.y_f, hz), M["head"], mirror=True)
        for y, (z0, z1), sg in ((self.y_f, self.bumper_f_z, 1.0), (self.y_r, self.bumper_r_z, -1.0)):   # dark bumpers
            lb.box((2 * self.w(y) + 0.04, 0.16, z1 - z0), (0, y - sg * 0.03, (z0 + z1) / 2.0), M["trim"])

    def mod_roof(self, mb):
        """Roof rack with a short cargo box (kept clear of the roof wing Mod_Spoiler_B)."""
        M = self.M
        g = self._gh()
        rz, xr, rf, rr = g["rz"], g["xr"], g["rf"], g["rr"]
        ln = rf - rr
        for y in (rr + ln * 0.37, rr + ln * 0.80):
            mb.box((2 * xr + 0.04, 0.045, 0.028), (0, y, rz + 0.075), M["trim"], bevel=0.008)
            for sx in (-1.0, 1.0):
                mb.box((0.05, 0.07, 0.085), (sx * (xr - 0.035), y, rz + 0.025), M["trim"], bevel=0.01)
        bw, bl = xr * 0.62, ln * 0.60
        yc = rr + ln * 0.585
        z0 = rz + 0.09
        mb.loft([[(-bw * 0.8, yc - bl / 2, z0 + 0.02), (bw * 0.8, yc - bl / 2, z0 + 0.02), (bw * 0.7, yc - bl / 2 + 0.03, z0 + 0.16), (-bw * 0.7, yc - bl / 2 + 0.03, z0 + 0.16)],
                 [(-bw, yc - bl * 0.2, z0), (bw, yc - bl * 0.2, z0), (bw * 0.9, yc - bl * 0.2, z0 + 0.20), (-bw * 0.9, yc - bl * 0.2, z0 + 0.20)],
                 [(-bw, yc + bl * 0.2, z0), (bw, yc + bl * 0.2, z0), (bw * 0.9, yc + bl * 0.2, z0 + 0.18), (-bw * 0.9, yc + bl * 0.2, z0 + 0.18)],
                 [(-bw * 0.7, yc + bl / 2, z0 + 0.03), (bw * 0.7, yc + bl / 2, z0 + 0.03), (bw * 0.6, yc + bl / 2 - 0.05, z0 + 0.10), (-bw * 0.6, yc + bl / 2 - 0.05, z0 + 0.10)]],
                self._mat("paint2"))
        mb.box((2 * bw + 0.012, bl * 0.5, 0.02), (0, yc, z0 + 0.09), M["trim"])


# ------------------------------------------------------------------------------------------------
# SPORTS - 4.40 m mid-engine wedge: targa roof (Roof_Convertible), buttresses, side intakes
# ------------------------------------------------------------------------------------------------
SPORTS = dict(K.DEFAULTS)
SPORTS.update(
    name="sports",
    width=1.92, height=1.20,
    axle_f=1.30, axle_r=-1.25, wheel_r=0.32, wheel_w=0.24, track=1.52, wheel_style="sport",
    rear=dict(wheel_r=0.365, wheel_w=0.30, track=1.57),
    arch_gap=0.045,
    # wedge: low nose, belt rising to a high tail (shell 4.30 m + bumpers)
    top=[(-2.15, 0.845), (-1.62, 0.895), (-0.64, 0.895), (0.85, 0.83), (1.30, 0.765), (1.85, 0.64), (2.15, 0.49)],
    bottom=[(-2.15, 0.30), (-1.80, 0.19), (1.80, 0.17), (2.15, 0.22)],
    # narrow front, wide hips
    plan=[(-2.15, 0.88), (-1.95, 0.975), (-1.68, 1.0), (-0.80, 1.0), (-0.30, 0.955), (1.67, 0.945), (1.95, 0.89), (2.15, 0.76)],
    crown=0.02, crown_w=0.34,
    crease_drop=0.05, swage_z=0.50, rocker_z=0.28, side_strip=None,
    cowl_y=0.85, roof_f=0.13, roof_r=-0.52, deck_y=-0.64,
    tumble=0.17, a_pillar=0.16, c_pillar=(0.18, 0.11), b_pillar=None, roof_mat="trim",
    doors=[("F", -0.52, 0.80)],
    tub_z=0.15, seat_x=0.36, seat_f_y=-0.12, seat_r_y=None, seat_z=0.30, seat_color="WarmGrey",
    head=dict(w=0.30, h=0.07, inset=0.03, z=None), grille=None,
    tail=dict(w=0.52, h=0.10, inset=0.03, z=None),
    bumper_f=dict(h=0.20, out=0.05, wrap=0.34),
    bumper_r=dict(h=0.22, out=0.05, wrap=0.34),
    exhaust=None, engine_y=-1.30,
    mods=list(K.FULL_MODS), spoiler_at="deck",
    targa=True, targa_header=0.09, targa_hinge_drop=0.08, mid_engine=True, trunk_inset=0.08,
    bay_depth={"hood": 0.20, "trunk": 0.30},
)


class Sports(CarA):

    def greenhouse(self):
        CarA.greenhouse(self)
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        pw = p["pillar_w"]
        yb = -1.62
        A = (g["xd"], g["dy"] + 0.02, g["zd"] - 0.02)
        B = (self.belt_x(yb), yb, self.zt(yb) - 0.02)
        C = (g["xr"], g["rr"] + 0.01, g["zR"] - 0.012)
        self.buttress = (A, B, C)
        b.loft([[A, B, C], [(q[0] - pw, q[1], q[2]) for q in (A, B, C)]], M["paint"], mirror=True)

    def front_fascia(self):
        K.Car.front_fascia(self)
        p, M, b = self.p, self.M, self.body
        yf = self.y_f
        hx, hy, hz = self.head_pos
        h = p["head"]
        gx = hx - h["w"] / 2.0 - 0.03
        b.box((2 * gx, 0.04, h["h"] + 0.012), (0, yf - 0.004, hz), M["trim"])           # dark band between the lamps
        b.box((0.12, 0.02, 0.03), (0, yf + 0.02, hz), M["chrome"], bevel=0.006)          # badge
        z0, z1 = self.bumper_f_z
        bh = p["bumper_f"]["h"]
        self.grille_box = (self.w(yf) * 0.58 - 0.03, z0 + bh * 0.36, bh * 0.36)

    def rear_fascia(self):
        K.Car.rear_fascia(self)
        p, M, b = self.p, self.M, self.body
        yr = self.y_r
        wc = self.w(yr)
        z0, z1 = self.bumper_r_z
        tx, ty, tz = self.tail_pos
        # full-width dark tail panel behind lamps and plate (red lamps vanished on a red car) and
        # one slim louvre bar across each lamp cluster (twin light strips)
        t = p["tail"]
        xo = self.side_x(yr, tz + t["h"] / 2.0) - t["inset"]
        b.box((2 * (xo + 0.005), 0.03, t["h"] + 0.04), (0, yr - 0.001, tz), M["trim"])
        b.box((t["w"] + 0.012, 0.008, 0.012), (xo - t["w"] / 2.0, yr - 0.041, tz), M["trim"], mirror=True)
        zl = tz - p["tail"]["h"] / 2.0 - 0.02
        vh = zl - z1 - 0.03
        if vh > 0.05:                                                                    # heat vent grille
            vz = (zl + z1) / 2.0
            b.box((wc * 1.25, 0.02, vh), (0, yr + 0.002, vz), M["under"])
            for i in range(3):
                b.box((wc * 1.25, 0.016, 0.014), (0, yr - 0.006, vz - vh / 2.0 + vh * (i + 0.5) / 3.0), M["trim"])
        ez = z0 + 0.08
        b.box((0.46, 0.03, 0.13), (0, yr - p["bumper_r"]["out"] + 0.004, ez), M["under"], bevel=0.01)
        self.tail_pipes([-0.095, 0.095], ez, r=0.047, out=0.11, bore=0.58)

    def details(self):
        self.details_plain(antenna=False)
        M, b = self.M, self.body
        # side intake scoops on the rear quarters (mouth right behind the door)
        ym = self.doors[0][1] - 0.035
        ye = self.ax["R"]["y"] + self.ax["R"]["Ra"]
        z0, z1 = 0.56, 0.82
        sx = self.side_x
        mouth = [(sx(ym, z0) - 0.012, ym, z0), (sx(ym, z0) + 0.06, ym, z0 + 0.025),
                 (sx(ym, z1) + 0.06, ym, z1 - 0.025), (sx(ym, z1) - 0.012, ym, z1)]
        end = [(sx(ye, z0 + 0.05) - 0.012, ye, z0 + 0.05), (sx(ye, z0 + 0.06) + 0.004, ye, z0 + 0.06),
               (sx(ye, z1 - 0.06) + 0.004, ye, z1 - 0.06), (sx(ye, z1 - 0.05) - 0.012, ye, z1 - 0.05)]
        b.loft([mouth, end], M["paint"], cap_mat=M["under"], mirror=True)
        for k in (1, 2):
            zz = z0 + (z1 - z0) * k / 3.0
            b.box((0.07, 0.014, 0.014), (sx(ym, zz) + 0.025, ym + 0.003, zz), M["paint"], mirror=True)

    def closures(self):
        CarA.closures(self)
        M = self.M
        # engine cover louvres
        t = self.mb("Trunk")
        ya, yb = -1.72, -0.86
        self.strip_on_top(t, ya, yb, -0.31, 0.31, M["under"], lift=0.004)
        n = 6
        for i in range(n):
            y = ya + (yb - ya) * (i + 0.5) / n
            t.box((0.62, 0.085, 0.014), (0, y, self.top_z(y) + 0.022), M["paint"], rot=(radians(14), 0, 0))
        # twin radiator exit vents on the front lid
        h = self.mb("Hood")
        va, vb, xi, xo = self.VENT
        for sgn in (1.0, -1.0):
            xa, xb = sorted((sgn * xi, sgn * xo))
            self.strip_on_top(h, va, vb, xa, xb, M["under"], lift=0.004)
            for i in range(3):
                y = va + (vb - va) * (i + 0.5) / 3.0
                h.box((0.24, 0.07, 0.012), (sgn * 0.19, y, self.top_z(y) + 0.018), M["paint"], rot=(radians(-12), 0, 0))
        # dark intake channel on the doors, widening towards the scoop
        ya_, yb_ = self.doors[0][1] + 0.012, 0.30
        for side, sfx in ((-1.0, "L"), (1.0, "R")):
            d = self.mb("Door_F" + sfx)
            ys = [ya_] + [s for s in self.ys if ya_ + 0.02 < s < yb_ - 0.02] + [yb_]
            secs = []
            for y in ys:
                k = (yb_ - y) / (yb_ - ya_)
                zlo, zhi = 0.655 - 0.095 * k, 0.665 + 0.125 * k
                secs.append([(side * (self.side_x(y, zlo) - 0.004), y, zlo), (side * (self.side_x(y, zlo) + 0.008), y, zlo),
                             (side * (self.side_x(y, zhi) + 0.008), y, zhi), (side * (self.side_x(y, zhi) - 0.004), y, zhi)])
            d.loft(secs, M["under"])
            # body-coloured strakes over the channel (longest in the middle), so it reads as a
            # modelled intake and not as a flat dark decal
            for zs, kmin in self.STRAKES:
                y1s = yb_ - kmin * (yb_ - ya_)
                yss = [ya_ + 0.004] + [yk for yk, _ in self.plan if ya_ + 0.03 < yk < y1s - 0.03] + [y1s]
                secs = []
                for y in yss:
                    xs = self.side_x(y, zs)
                    hz = 0.011 if y < y1s - 1e-6 else 0.004
                    secs.append([(side * (xs + 0.004), y, zs - hz), (side * (xs + 0.026), y, zs - hz),
                                 (side * (xs + 0.026), y, zs + hz), (side * (xs + 0.004), y, zs + hz)])
                d.loft(secs, M["paint"])

    def lod(self):
        CarA.lod(self)
        A, B, C = self.buttress
        self.mb("Body_LOD1").face([A, B, C], self.M["paint"], mirror=True, want=(1, 0, 0.3))

    VENT = (1.36, 1.72, 0.07, 0.31)     # y0, y1, |x| inner, |x| outer of the front-lid vents
    STRAKES = ((0.615, 0.66), (0.675, 0.28), (0.735, 0.75))   # (z, start as share of the channel length)

    def mod_hood(self, mb):
        """Raised extractor cowls over the two front-lid vents (open to the rear)."""
        M = self.M
        va, vb, xi, xo = self.VENT
        for sgn in (1.0, -1.0):
            x0, x1 = sorted((sgn * (xi - 0.03), sgn * (xo + 0.03)))
            secs = []
            for y, h in ((vb + 0.06, 0.004), (va + 0.05, 0.062), (va - 0.04, 0.066)):
                z = self.top_z(y)
                secs.append([(x0, y, z - 0.012), (x1, y, z - 0.012), (x1 - 0.03, y, z + h), (x0 + 0.03, y, z + h)])
            mb.loft(secs, M["paint"])
            z = self.top_z(va - 0.04)
            mb.box((xo - xi - 0.02, 0.012, 0.04), (sgn * (xi + xo) / 2.0, va - 0.044, z + 0.03), M["under"])

    def mod_grille(self, mb):
        """Mesh insert for the big bumper intake (the wedge nose has no upper grille)."""
        p, M = self.p, self.M
        gx, gz, gh = self.grille_box
        y = self.y_f + p["bumper_f"]["out"]
        mb.box((2 * gx + 0.03, 0.03, gh + 0.03), (0, y + 0.004, gz), M["chrome"], bevel=0.008)
        mb.box((2 * gx - 0.02, 0.02, gh - 0.02), (0, y + 0.018, gz), M["under"])
        n = 9
        for i in range(n):
            x = (i - (n - 1) / 2.0) * ((2 * gx - 0.06) / (n - 1))
            mb.box((0.012, 0.012, gh - 0.025), (x, y + 0.026, gz), M["trim"])
        mb.box((2 * gx - 0.02, 0.014, 0.014), (0, y + 0.028, gz), M["chrome"])

    def mod_roof(self, mb):
        """Light pod on the fixed windshield header (works with the roof up or folded)."""
        M = self.M
        g = self._gh()
        rf, rz, xr = g["rf"], g["rz"], g["xr"]
        y = rf - 0.03
        mb.box((2 * xr - 0.16, 0.07, 0.02), (0, y, rz + 0.006), self._mat("paint2"), bevel=0.006)
        for x in (-0.36, -0.12, 0.12, 0.36):
            mb.box((0.03, 0.03, 0.05), (x, y - 0.005, rz + 0.035), M["trim"])
            mb.cyl(0.062, 0.06, (x, y + 0.005, rz + 0.085), M["trim"], axis='Y', segments=8)
            mb.cyl(0.05, 0.02, (x, y + 0.03, rz + 0.085), M["head"], axis='Y', segments=8)


# ------------------------------------------------------------------------------------------------
# MUSCLE - 4.90 m long-hood fastback: quad lamps in a full-width grille, chrome blade bumpers, scoop
# ------------------------------------------------------------------------------------------------
MUSCLE = dict(K.DEFAULTS)
MUSCLE.update(
    name="muscle",
    width=1.90, height=1.35,
    axle_f=1.52, axle_r=-1.38, wheel_r=0.335, wheel_w=0.24, track=1.60, wheel_style="deep",
    rear=dict(wheel_r=0.36, wheel_w=0.31, track=1.54),
    # long flat hood, hip kick over the rear wheel, short deck (shell 4.80 m + bumpers)
    top=[(-2.40, 0.95), (-2.02, 0.99), (-1.25, 1.00), (-0.55, 0.965), (0.50, 0.955), (2.18, 0.89), (2.40, 0.83)],
    bottom=[(-2.40, 0.40), (-2.02, 0.27), (2.02, 0.25), (2.40, 0.34)],
    plan=[(-2.40, 0.90), (-2.15, 0.975), (-1.86, 1.0), (1.95, 1.0), (2.20, 0.965), (2.40, 0.88)],
    crown=0.025, crown_w=0.36,
    swage_z=0.64, rocker_z=0.35, side_strip=None,
    cowl_y=0.50, roof_f=-0.03, roof_r=-0.80, deck_y=-2.02,
    tumble=0.15, a_pillar=0.13, c_pillar=(0.80, 0.42), b_pillar=0.08,
    doors=[("F", -0.62, 0.46)],
    tub_z=0.22, seat_x=0.38, seat_f_y=-0.45, seat_r_y=-1.22, seat_z=0.41, seat_color="Cream",
    head=None, grille=None, tail=None, bumper_f=None, bumper_r=None,
    plate_f=False, plate_r=False, exhaust=None,
    mods=list(K.FULL_MODS), spoiler_at="deck",
    arch_flare={"R": 0.012},
)


class Muscle(CarA):
    TG = 0.46                        # share of the fastback slope that is painted sheet metal (deck -> up)
    STRIPE = (0.05, 0.19)            # |x| range of each racing stripe
    SCOOP = ((0.66, 0.34, 0.012), (0.96, 0.325, 0.06), (1.54, 0.29, 0.095), (1.60, 0.285, 0.085))   # (y, half width, height)
    SCOOP_MOD = ((0.62, 0.37, 0.03), (0.92, 0.36, 0.11), (1.64, 0.33, 0.15), (1.74, 0.325, 0.135))

    def _slope(self, t, off=0.0):
        """(y, z, half width) on the fastback slope: t = 0 at the deck, 1 at the roof edge;
        off = distance along the outward normal of the slope."""
        g = self._gh()
        dy, rr, zd, zR = g["dy"], g["rr"], g["zd"], g["zR"]
        ly, lz = rr - dy, zR - zd
        ln = sqrt(ly * ly + lz * lz)
        return (dy + ly * t - lz / ln * off, zd + lz * t + ly / ln * off, g["xd"] + (g["xr"] - g["xd"]) * t)

    def greenhouse(self):
        CarA.greenhouse(self)
        M, b = self.M, self.body
        tg = self.TG
        # painted lower half of the fastback (the kit would glaze the whole 1.2 m slope)
        secs = []
        for t in (-0.04, tg):
            y1, z1, hx = self._slope(t, 0.006)
            y0, z0, _ = self._slope(t, -0.035)
            secs.append([(-hx, y1, z1), (hx, y1, z1), (hx, y0, z0), (-hx, y0, z0)])
        self.headliner(b.loft(secs, M["paint"]))
        rg = K.MB()                  # replace the kit pane by one that starts above the panel
        self.parts["Glass_Rear"] = rg
        ya, za, xa = self._slope(tg - 0.02, -0.014)
        yb, zb, xb = self._slope(1.0, -0.014)
        rg.face([(-(xa - 0.03), ya, za), (xa - 0.03, ya, za), (xb - 0.03, yb, zb), (-(xb - 0.03), yb, zb)], M["glass"], want=(0, -1, 1))

    def _stripe_secs(self, x0, x1, pts, lift=0.005, th=0.02):
        return [[(x0, y, z - th), (x1, y, z - th), (x1, y, z + lift), (x0, y, z + lift)] for y, z in pts]

    def stripes(self):
        """Twin racing stripes in M_Paint_Secondary from nose to tail (Body, Hood over the scoop, Trunk)."""
        m2 = self.M["paint2"]
        g = self._gh()
        rz, rr, rf = g["rz"], g["rr"], g["rf"]
        hood, trunk, body = self.mb("Hood"), self.mb("Trunk"), self.body
        for sgn in (1.0, -1.0):
            x0, x1 = sorted((sgn * self.STRIPE[0], sgn * self.STRIPE[1]))
            self.strip_on_top(body, self.hood[1] + 0.012, self.y_f - 0.004, x0, x1, m2, 0.005)
            self.strip_on_top(hood, self.SCOOP[-1][0] + 0.03, self.hood[1] - 0.012, x0, x1, m2, 0.005)
            pts = [(self.hood[0] + 0.012, self.top_z(self.hood[0] + 0.012))] + [(y, self.top_z(y) + h) for y, _, h in self.SCOOP]
            hood.loft(self._stripe_secs(x0, x1, pts), m2)
            body.loft(self._stripe_secs(x0, x1, [(rr - 0.05, rz - 0.04), (rr + 0.09, rz), (rf - 0.09, rz), (rf + 0.05, rz - 0.04)]), m2)
            secs = []
            for t in (-0.035, self.TG - 0.004):
                y1, z1, _ = self._slope(t, 0.011)
                y0, z0, _ = self._slope(t, -0.01)
                secs.append([(x0, y1, z1), (x1, y1, z1), (x1, y0, z0), (x0, y0, z0)])
            body.loft(secs, m2)
            self.strip_on_top(trunk, self.trunk[0] + 0.012, self.trunk[1] - 0.012, x0, x1, m2, 0.005)
            self.strip_on_top(body, self.y_r + 0.004, self.trunk[0] - 0.006, x0, x1, m2, 0.005)

    def front_fascia(self):
        M, b = self.M, self.body
        yf = self.y_f
        wc = self.w(yf)
        gz, gh = 0.70, 0.19
        gw = wc - 0.10
        b.box((2 * gw, 0.03, gh), (0, yf, gz), M["under"])                              # grille opening
        for sz in (1.0, -1.0):
            b.box((2 * gw + 0.05, 0.05, 0.022), (0, yf + 0.012, gz + sz * (gh / 2.0 + 0.005)), M["chrome"])
        b.box((0.022, 0.05, gh + 0.03), (gw + 0.014, yf + 0.012, gz), M["chrome"], mirror=True)
        lxs = (gw - 0.11, gw - 0.30)
        for lx in lxs:                                                                   # quad round lamps
            b.cyl(0.082, 0.03, (lx, yf + 0.018, gz), M["chrome"], axis='Y', segments=10, mirror=True)
            b.cyl(0.068, 0.03, (lx, yf + 0.03, gz), M["head"], axis='Y', segments=10, mirror=True)
        gi = lxs[1] - 0.11
        for i in range(3):
            b.box((2 * gi, 0.012, 0.012), (0, yf + 0.02, gz - gh / 2.0 + gh * (i + 1) / 4.0), M["chrome"])
        b.box((0.07, 0.03, gh + 0.01), (0, yf + 0.016, gz), M["paint"], bevel=0.01)      # centre divider
        # chrome blade bumper + body-coloured valance
        o = 0.085
        z0, z1 = 0.455, 0.57
        self.bumper(True, [(-0.07, z0), (o * 0.5, z0), (o, z0 + 0.03), (o, z1 - 0.03), (o * 0.5, z1), (-0.07, z1)], M["chrome"], 0.32)
        v0 = interp(self.bottom_keys, yf) - 0.03
        self.bumper(True, [(-0.07, v0), (0.025, v0), (0.045, v0 + 0.04), (0.045, z0 + 0.005), (-0.07, z0 + 0.005)], M["paint"], 0.22)
        b.box((0.80, 0.02, 0.07), (0, yf + 0.045, v0 + 0.08), M["trim"], bevel=0.008)
        b.box((0.16, 0.02, 0.045), (wc - 0.16, yf + 0.045, v0 + 0.085), M["indicator"], mirror=True)
        b.box((0.32, 0.016, 0.11), (0, yf + o + 0.008, (z0 + z1) / 2.0), M["plate"])
        self.bumper_f_z = (v0, z1)
        self.head_pos = (gw - 0.205, yf + 0.05, gz)
        self.grille_box = (gi - 0.02, gz, gh - 0.02)

    def rear_fascia(self):
        K.Car.rear_fascia(self)             # everything is None: only sets the marker defaults
        M, b = self.M, self.body
        yr = self.y_r
        wc = self.w(yr)
        zt = self.zt(yr)
        ph = 0.16
        pz = zt - 0.135
        hw = wc - 0.09
        b.box((2 * hw, 0.03, ph), (0, yr, pz), M["trim"])                               # tail panel
        for sz in (1.0, -1.0):
            b.box((2 * hw + 0.04, 0.045, 0.018), (0, yr - 0.008, pz + sz * (ph / 2.0 + 0.004)), M["chrome"])
        sw_, lh = 0.155, ph - 0.05
        for i in range(3):
            x = hw - 0.10 - i * (sw_ + 0.02)
            if i < 2:
                b.box((sw_, 0.05, lh), (x, yr - 0.012, pz), M["tail"], mirror=True, bevel=0.012)
            else:
                b.box((sw_, 0.045, lh / 2.0 - 0.006), (x, yr - 0.012, pz + lh / 4.0 + 0.003), M["indicator"], mirror=True)
                b.box((sw_, 0.045, lh / 2.0 - 0.006), (x, yr - 0.012, pz - lh / 4.0 - 0.003), M["reverse"], mirror=True)
        b.box((0.32, 0.016, 0.11), (0, yr - 0.022, pz), M["plate"])
        self.tail_pos = (hw - 0.19, yr - 0.05, pz)
        o = 0.08
        z0, z1 = 0.55, 0.665
        self.bumper(False, [(-0.07, z0), (o * 0.5, z0), (o, z0 + 0.03), (o, z1 - 0.03), (o * 0.5, z1), (-0.07, z1)], M["chrome"], 0.32)
        v0 = interp(self.bottom_keys, yr) - 0.03
        self.bumper(False, [(-0.07, v0), (0.02, v0), (0.04, v0 + 0.04), (0.04, z0 + 0.005), (-0.07, z0 + 0.005)], M["paint"], 0.22)
        self.bumper_r_z = (v0, z1)
        self.tail_pipes([-0.52, 0.52], v0 - 0.035, r=0.042, out=0.11)

    def details(self):
        K.Car.details(self)
        p, M, b = self.p, self.M, self.body
        # chrome rocker moulding between the arches
        ya = self.ax["R"]["y"] + self.ax["R"]["Ra"] + 0.07
        yb = self.ax["F"]["y"] - self.ax["F"]["Ra"] - 0.07
        z = p["rocker_z"] - 0.035
        secs = []
        for y in (ya, yb):
            x = self.side_x(y, z)
            secs.append([(x - 0.006, y, z - 0.016), (x + 0.012, y, z - 0.016), (x + 0.012, y, z + 0.016), (x - 0.006, y, z + 0.016)])
        b.loft(secs, M["chrome"], mirror=True)
        # gills on the rear quarters
        for i in range(3):
            y = -0.76 - i * 0.075
            zg = 0.74
            b.box((0.014, 0.04, 0.15), (self.side_x(y, zg) + 0.003, y, zg), M["trim"], mirror=True, rot=(radians(-14), 0, 0))

    def lod(self):
        CarA.lod(self)
        M = self.M
        lb = self.mb("Body_LOD1")
        g = self._gh()
        ya, za, xa = self._slope(-0.02, 0.012)
        yb, zb, xb = self._slope(self.TG, 0.012)
        lb.face([(-xa, ya, za), (xa, ya, za), (xb, yb, zb), (-xb, yb, zb)], M["paint"], want=(0, -1, 1))
        y0, y1 = self.SCOOP[0][0], self.SCOOP[-1][0]
        lb.box((0.56, y1 - y0, 0.08), (0, (y0 + y1) / 2.0, self.top_z(y1) + 0.03), M["paint"])
        x0, x1 = self.STRIPE
        lf = 0.02
        runs = [[(self.y_r, self.top_z(self.y_r) + lf), (g["dy"], self.top_z(g["dy"]) + lf), (yb, zb + lf)],
                [(g["rr"], g["rz"] + lf), (g["rf"], g["rz"] + lf)],
                [(self.hood[0], self.top_z(self.hood[0]) + lf), (y0, self.top_z(y0) + lf + 0.02), (y1, self.top_z(y1) + 0.075 + lf),
                 (y1 + 0.02, self.top_z(y1) + lf), (self.hood[1], self.top_z(self.hood[1]) + lf), (self.y_f, self.top_z(self.y_f) + lf)]]
        for run in runs:
            for (ya_, za_), (yb_, zb_) in zip(run[:-1], run[1:]):
                lb.face([(x0, ya_, za_), (x1, ya_, za_), (x1, yb_, zb_), (x0, yb_, zb_)], M["paint2"], mirror=True, want=(0, 0, 1))

    def engine_block(self, y0, y1, zmin, depth, wx):
        CarA.engine_block(self, y0, y1, zmin, depth, wx)
        ym = (y0 + y1) / 2.0
        self.body.cyl(0.15, 0.06, (0, ym - 0.05, zmin + depth * 0.62 + 0.075), self.M["chrome"], axis='Z', segments=10)

    def closures(self):
        CarA.closures(self)
        M = self.M
        mb = self.mb("Hood")
        # power bulge that ends in a forward-facing scoop mouth
        y1 = self.SCOOP[-1][0]
        secs = []
        for y, hw, h in self.SCOOP:
            z = self.top_z(y)
            secs.append([(-hw, y, z - 0.012), (hw, y, z - 0.012), (hw - 0.045, y, z + h), (-hw + 0.045, y, z + h)])
        mb.loft(secs, M["paint"])
        z = self.top_z(y1)
        mb.box((0.44, 0.014, 0.048), (0, y1 + 0.003, z + 0.04), M["under"])
        mb.box((0.03, 0.02, 0.066), (0, y1 + 0.005, z + 0.04), M["paint"])
        self.stripes()

    def mod_hood(self, mb):
        """Tall twin-nostril scoop that swallows the stock bulge."""
        M = self.M
        y1 = self.SCOOP_MOD[-1][0]
        secs = []
        for y, hw, h in self.SCOOP_MOD:
            z = self.top_z(y)
            secs.append([(-hw, y, z - 0.012), (hw, y, z - 0.012), (hw - 0.05, y, z + h), (-hw + 0.05, y, z + h)])
        mb.loft(secs, M["paint"])
        z = self.top_z(y1)
        mb.box((0.23, 0.014, 0.075), (0.135, y1 + 0.004, z + 0.066), M["under"], mirror=True)
        for sgn in (1.0, -1.0):
            x0, x1 = sorted((sgn * self.STRIPE[0], sgn * self.STRIPE[1]))
            mb.loft(self._stripe_secs(x0, x1, [(y, self.top_z(y) + h) for y, _, h in self.SCOOP_MOD]), self.M["paint2"])

    def mod_roof(self, mb):
        """Fastback louvres over the rear glass."""
        M = self.M
        g = self._gh()
        dy, rr, zd, zR, xd, xr = g["dy"], g["rr"], g["zd"], g["zR"], g["xd"], g["xr"]
        n = 5
        ta, tb = self.TG + 0.01, 0.985
        for i in range(n):
            t = ta + (tb - ta) * (i + 0.5) / n
            y, z, hx = self._slope(t, 0.04)
            mb.box((2 * (hx - 0.075), 0.115, 0.014), (0, y, z), M["trim"], rot=(radians(-4), 0, 0))
        for sgn in (1.0, -1.0):
            secs = []
            for t in (ta - 0.01, tb + 0.01):
                y1, z1, hx = self._slope(t, 0.058)
                y0, z0, _ = self._slope(t, 0.0)
                secs.append([(sgn * (hx - 0.085), y1, z1), (sgn * (hx - 0.045), y1, z1), (sgn * (hx - 0.045), y0, z0), (sgn * (hx - 0.085), y0, z0)])
            mb.loft(secs, M["trim"])


# ------------------------------------------------------------------------------------------------
# build / QA / export
# ------------------------------------------------------------------------------------------------
CARS = {
    "compact": (Compact, COMPACT, 1, dict(doors=("Door_FL", "Door_FR"), rear_seats=True)),
    "sports": (Sports, SPORTS, 2, dict(doors=("Door_FL", "Door_FR"), rear_seats=False)),
    "muscle": (Muscle, MUSCLE, 3, dict(doors=("Door_FL", "Door_FR"), rear_seats=True)),
}


def build(kind, preview=True, res=420):
    cls, params, idx, chk = CARS[kind]
    car = cls(params, G.slot("cars", idx))
    car.build()
    car.finish()
    car.report()
    K.check_contract(kind, mods=params["mods"], **chk)
    if preview:
        G.preview(kind, "veh_" + kind, views=VIEWS, res=res)
    return car


def export(kind):
    res = G.validate(kind, max_tris=9500)
    K.export_glb(kind, "vehicles/%s.glb" % kind)
    return res


def pose_preview(name, out, poses, views=("three_quarter", "rear_quarter", "side", "top"), res=420, mods=False):
    """Preview with parts rotated ({'Door_FL': (0, 0, -1.0), 'Hood': (0.9, 0, 0)} ...); restores them."""
    saved = []
    try:
        for part, rot in poses.items():
            ob = bpy.data.objects.get(name + K.NAME_SEP + part)
            if ob is None:
                print("pose_preview: no part", part)
                continue
            saved.append((ob, ob.rotation_euler.copy()))
            ob.rotation_euler = rot
        bpy.context.view_layer.update()
        if mods:
            return K.preview_mods(name, out, views=views, res=res)
        return G.preview(name, out, views=views, res=res)
    finally:
        for ob, r in saved:
            ob.rotation_euler = r
        bpy.context.view_layer.update()


def group_preview(names=("compact", "sports", "muscle"), out="veh_cars_a_group", res=760):
    """Two sheets: <out>.png (side by side: 3/4, rear 3/4, front, top) and <out>_side.png (profile
    line-up).  The roots are moved together only for the renders and always put back on their slots."""
    from mathutils import Vector
    names = [n for n in names if bpy.data.objects.get(n) is not None]
    saved = {n: bpy.data.objects[n].location.copy() for n in names}
    base = Vector(G.slot("cars", 1))
    try:
        for i, n in enumerate(names):
            bpy.data.objects[n].location = base + Vector(((i - 1) * 2.7, 0.0, 0.0))
        bpy.context.view_layer.update()
        G.preview(names, out, views=("three_quarter", "rear_quarter", (0.0, 1.0, 0.2), "top"), res=res, margin=1.0)
        for i, n in enumerate(names):
            bpy.data.objects[n].location = base + Vector((0.0, (1 - i) * 5.8, 0.0))
        bpy.context.view_layer.update()
        G.preview(names, out + "_side", views=("side",), res=1000, margin=1.0)
    finally:
        for n, loc in saved.items():
            bpy.data.objects[n].location = loc
        bpy.context.view_layer.update()
