r"""aircraft.py - Halcyon Bay aircraft builders (Blender 5.2, run through the Blender MCP).

Assets (all reproducible by re-running this module inside the master .blend):
    heli_civil   light civil helicopter           -> models/vehicles/heli_civil.glb
    heli_police  HBPD utility helicopter          -> models/vehicles/heli_police.glb
    plane_prop   high-wing 4-seat propeller plane -> models/vehicles/plane_prop.glb
    plane_jet    small twin-engine sport jet      -> models/vehicles/plane_jet.glb

Usage inside one atomic execute_blender_code call:

    import sys, importlib
    P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
    for p in (P, P + r"\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G); G.assert_master()
    import aircraft as A; importlib.reload(A)
    A.build("heli_civil")          # or A.build_all()
    A.sheet("heli_civil", "heli_civil", views=("three_quarter", "rear_quarter", "side", "front", "top", "under"),
            res=512, cols=3)       # tight QA contact sheet in qa/blender_previews/ (backface culling ON);
                                   # a view may be ("side", (cx, cy, cz), radius) for a detail tile
    A.export("heli_civil")         # validate + GLB + node-name clean-up ; then G.save()
    (A.preview() is the older bounding-sphere sheet through G.preview - the airframe ends up tiny in it.)

Critic pass (2026-11): plane_jet got real landing gear (oleo legs, forks, torque links, braces, doors,
wheel wells); heli_police says POLICE on boom + belly and HBPD on the rear quarter panels, rotor parked
as an X; heli_civil has door shut lines, a boom registration and a pod that tapers into the boom;
plane_prop has door shut lines and an anti-glare panel; tyres touch z = 0 exactly (lathe phase).

Conventions: Z up, nose toward +Y, right side +X, origin on the ground under the centre of
gravity (helicopters: under the rotor mast), lowest point (skids / tyres) at z = 0.
`_L` = aircraft's left = -X.  Pilot (Seat_Driver) sits on the left; the jet seats are in tandem.

Moving parts (Blender local axes; Godot = (x, z, -y), so Blender Z -> Godot Y, Blender Y -> Godot -Z):
    Rotor_Main, RotorBlur_Main  spin about local Z (Godot Y); origin on the mast axis at the hub
    Rotor_Tail                  spins about local X; origin on its axis (heli_police: shrouded fan)
    Propeller, PropBlur         spin about local Y (Godot Z); origin on the crankshaft axis
    Wheel_Nose / Wheel_L / _R   axle = local X, origin at the wheel centre
    Aileron_*, Flap_*, Elevator hinge = local X through the origin, +rotation = trailing edge DOWN
    Rudder                      hinge = local Z (Godot Y) through the origin, +rotation (Blender) =
                                trailing edge to the right (+X)
    Door_F* / Door_R*           hinge = local Z through the origin (front edge of the door); the door
                                window (Glass_L / Glass_R / Glass_RL / Glass_RR) is a CHILD of its door
    Canopy (plane_jet)          hinge = local X through the origin (rear edge), +rotation opens it;
                                Glass_Canopy is its child
    Searchlight (heli_police)   origin at the gimbal; the beam leaves along local +Y (Godot -Z, so
                                look_at() aims it); rest pose is pitched 32 deg down; child marker
                                Searchlight_Beam sits on the lens
    SensorBall (heli_police)    origin at the ball centre

Markers (Empties): Seat_Driver, Seat_Passenger_1..3 (hip points; heli_police adds Seat_Gunner_L / _R
facing outward), Exit_* (on the ground beside each seat's door), Engine, Exhaust (or _L / _R),
Light_Head + Light_Head_L / _R (landing lights; the generic vehicle light code reads the _L / _R
pair), Light_Tail + Light_Tail_L / _R, Light_Beacon, Light_Nav_L / _R (planes), Siren (heli_police).

Helpers: Col_Body / Col_Tail (/ Col_Wing) are convex hulls (<= 32 verts, material P_Collision);
RotorBlur_Main / PropBlur are flat translucent discs (M_RotorBlur). Both kinds are plain visible
meshes in the GLB - the game hides / shows them.

Paint: heli_civil, plane_prop and plane_jet use the shared contract materials M_Paint_Primary /
M_Paint_Secondary; DEFAULT_PAINT is baked into each GLB at export time (the shared Blender
materials are only recoloured for the duration of the export call). heli_police carries a fixed
livery (P_PoliceBlue / P_PoliceWhite / P_BadgeGold) and deliberately has NO M_Paint_* slot.

Blender keeps object names unique per file ("Body.031"), so export() strips the numeric suffixes
inside the GLB (fix_glb_names) - the GLB node names are the clean contract names.
"""
import json
import math
import re
import struct

import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

import gta_bl as G

HELI_COL = "Vehicles/Helicopters"
PLANE_COL = "Vehicles/Airplanes"
SLOTS = {"heli_civil": 0, "heli_police": 1, "plane_prop": 2, "plane_jet": 3}
# default paint baked into the GLB (the shared Blender materials are only changed for the
# duration of the preview / export call and restored afterwards)
DEFAULT_PAINT = {
    "heli_civil": ("CarOrange", "CarWhite"),
    "heli_police": ("PoliceWhite", "PoliceBlue"),
    "plane_prop": ("CarYellow", "CarWhite"),
    "plane_jet": ("CarWhite", "CarTeal"),
}
VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top")
_SUFFIX = re.compile(r"\.\d{3,}$")


def base_name(ob_or_name):
    n = ob_or_name if isinstance(ob_or_name, str) else ob_or_name.name
    return _SUFFIX.sub("", n)


def V(*a):
    return Vector(a[0]) if len(a) == 1 else Vector(a)


# ------------------------------------------------------------------------------------------------
# materials (contract names, shared with every other vehicle; get-or-create only)
# ------------------------------------------------------------------------------------------------
def mats():
    d = {}
    d["paint"] = G.mat("M_Paint_Primary", G.pal("CarRed"), rough=0.35, metal=0.15)
    d["paint2"] = G.mat("M_Paint_Secondary", G.pal("CarWhite"), rough=0.4, metal=0.1)
    d["glass"] = G.mat("M_Glass", G.pal("WindowDark"), rough=0.08, metal=0.0, alpha=0.45)
    d["trim"] = G.mat("M_Trim", G.pal("Trim"), rough=0.6)
    d["chrome"] = G.mat("M_Chrome", G.pal("Chrome"), rough=0.2, metal=1.0)
    d["interior"] = G.mat("M_Interior", G.pal("Interior"), rough=0.9)
    d["under"] = G.mat("M_Underbody", G.pal("Charcoal"), rough=0.9)
    d["tire"] = G.mat("M_Tire", G.pal("Tire"), rough=0.95)
    d["rim"] = G.mat("M_Rim", G.pal("Rim"), rough=0.35, metal=0.8)
    d["headlight"] = G.mat("M_Headlight", G.pal("HeadlightWhite"), rough=0.2, emit=G.pal("HeadlightWhite"), emit_strength=2.0)
    d["taillight"] = G.mat("M_Taillight", G.pal("TailRed"), rough=0.3, emit=G.pal("TailRed"), emit_strength=1.5)
    d["siren_red"] = G.mat("M_Siren_Red", G.pal("SirenRed"), rough=0.3, emit=G.pal("SirenRed"), emit_strength=2.0)
    d["siren_blue"] = G.mat("M_Siren_Blue", G.pal("SirenBlue"), rough=0.3, emit=G.pal("SirenBlue"), emit_strength=2.0)
    d["blur"] = G.mat("M_RotorBlur", (0.05, 0.055, 0.065), rough=0.8, alpha=0.25)
    d["col"] = G.mat("P_Collision", (1.0, 0.1, 0.7), rough=1.0, alpha=0.35)
    for key in ("Charcoal", "WarmGrey", "HazardYellow", "PoliceBlue", "PoliceWhite", "BadgeGold",
                "Steel", "SteelDark", "Black", "White", "Leather", "CarRed", "Navy"):
        d[key] = G.pmat(key)
    d["NavGreen"] = G.pmat("NeonGreen", emit_strength=2.0)
    d["Screen"] = G.pmat("NeonCyan", emit_strength=2.0)
    return d


class Paint:
    """Temporarily recolour the shared paint materials (restored on exit, same MCP call)."""

    def __init__(self, primary=None, secondary=None):
        self.cols = (("M_Paint_Primary", primary), ("M_Paint_Secondary", secondary))
        self.saved = []

    def __enter__(self):
        for name, key in self.cols:
            m = bpy.data.materials.get(name)
            if m is None or key is None:
                continue
            node = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            sock = None
            if node is not None:
                sock = next((s for s in node.inputs if s.identifier == 'Base Color' or s.name == 'Base Color'), None)
            self.saved.append((m, sock, tuple(sock.default_value) if sock else None, tuple(m.diffuse_color)))
            c = G.pal(key) if isinstance(key, str) else key
            if sock:
                sock.default_value = (c[0], c[1], c[2], 1.0)
            m.diffuse_color = (c[0], c[1], c[2], 1.0)
        return self

    def __exit__(self, *exc):
        for m, sock, col, dc in self.saved:
            if sock and col:
                sock.default_value = col
            m.diffuse_color = dc
        self.saved = []
        return False


# ------------------------------------------------------------------------------------------------
# mesh builder
# ------------------------------------------------------------------------------------------------
class MB:
    """Accumulates geometry of ONE object in a bmesh; faces are oriented explicitly (new_object is
    called with recalc=False) so open shells, liners and decals keep their intended normals."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, material):
        for i, m in enumerate(self.mats):
            if m == material:
                return i
        self.mats.append(material)
        return len(self.mats) - 1

    # -- single oriented polygon -----------------------------------------------------------------
    def poly(self, pts, material, normal=None, away=None, toward=None):
        vs = [self.bm.verts.new(Vector(p)) for p in pts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = self.mi(material)
        f.normal_update()
        d = None
        if normal is not None:
            d = Vector(normal)
        elif away is not None:
            d = f.calc_center_median() - Vector(away)
        elif toward is not None:
            d = Vector(toward) - f.calc_center_median()
        if d is not None and f.normal.dot(d) < 0.0:
            f.normal_flip()
        return f

    # -- closed solids -----------------------------------------------------------------------------
    def _finish(self, verts, recalc=False, bevel=0.0, xform=None, bevel_angle=30.0):
        """Post-process freshly added geometry (identified by its verts, NOT by index ranges: the
        bmesh element order is not the creation order once elements were freed)."""
        bm = self.bm
        flat = []
        for v in verts:
            if isinstance(v, (list, tuple)):
                flat.extend(v)
            else:
                flat.append(v)
        faces = []
        seen = set()
        for v in flat:
            for f in v.link_faces:
                if f not in seen:
                    seen.add(f)
                    faces.append(f)
        if xform is not None:
            for v in flat:
                v.co = xform @ v.co
            if xform.determinant() < 0.0 and not recalc:
                bmesh.ops.reverse_faces(bm, faces=faces)
        if recalc:
            bmesh.ops.recalc_face_normals(bm, faces=faces)
        if bevel > 0.0:
            lim = math.radians(bevel_angle)
            edges = []
            eseen = set()
            for f in faces:
                for e in f.edges:
                    if e not in eseen:
                        eseen.add(e)
                        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
                            edges.append(e)
            if edges:
                try:
                    bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect='EDGES', profile=0.5,
                                    clamp_overlap=True, material=-1)
                except Exception as e:      # keep building, an un-chamfered part is still fine
                    print("bevel skipped:", e)

    def box(self, size, center, material, rot=None, bevel=0.0, xform=None):
        vs = G.add_box(self.bm, size, center, rot, self.mi(material))
        self._finish(vs, bevel=bevel, xform=xform)

    def cyl(self, radius, depth, center, material, axis='Z', seg=10, r2=None, rot=None, bevel=0.0, xform=None):
        vs = G.add_cylinder(self.bm, radius, depth, center, axis, seg, self.mi(material), r2, rot)
        self._finish(vs, bevel=bevel, xform=xform)

    def sphere(self, radius, center, material, seg=10, rings=6, scale=(1, 1, 1), rot=None, xform=None):
        vs = G.add_sphere(self.bm, radius, center, seg, rings, self.mi(material), scale, rot)
        self._finish(vs, xform=xform)

    def tube(self, p0, p1, r0, material, r1=None, seg=8, cap=True):
        """Cylinder / cone frustum between two arbitrary points."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = p1 - p0
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        mx = Matrix.Translation((p0 + p1) / 2) @ rot
        ret = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r0,
                                    radius2=r0 if r1 is None else r1, depth=d.length, matrix=mx)
        mi = self.mi(material)
        for v in ret['verts']:
            for f in v.link_faces:
                f.material_index = mi

    def loft(self, sections, material, bevel=0.0, cap_start=True, cap_end=True, xform=None):
        rings = G.add_loft(self.bm, sections, self.mi(material), cap_start, cap_end)
        self._finish(rings, recalc=True, bevel=bevel, xform=xform)

    def path_tube(self, pts, radius, material, seg=8, ref=(1, 0, 0), radii=None):
        """Bent tube along a polyline (mitred joints)."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        ref = Vector(ref)
        secs = []
        for i, p in enumerate(pts):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            t.normalize()
            u = ref.cross(t)
            if u.length < 1e-4:
                u = Vector((0, 0, 1)).cross(t)
            u.normalize()
            v = t.cross(u).normalized()
            k = 1.0
            if 0 < i < n - 1:
                k = 1.0 / max((pts[i + 1] - pts[i]).normalized().dot(t), 0.6)
            r = (radius if radii is None else radii[i]) * k
            secs.append([p + (u * math.cos(a) + v * math.sin(a)) * r
                         for a in (2 * math.pi * j / seg for j in range(seg))])
        self.loft(secs, material)

    def lathe(self, profile, material, axis='Y', origin=(0, 0, 0), seg=12, phase=0.0, xform=None,
              scale=(1.0, 1.0), caps=(True, True), closed=False):
        """Surface of revolution. profile = [(axial, radius), ...]; `scale` squashes the two radial
        axes (elliptic sections); closed=True joins the last ring to the first (torus-like)."""
        o = Vector(origin)
        secs = []
        prof = list(profile) + ([profile[0]] if closed else [])
        for a, r in prof:
            ring = []
            for j in range(seg):
                th = 2 * math.pi * (j + phase) / seg
                c = math.cos(th) * r * scale[0]
                s = math.sin(th) * r * scale[1]
                if axis == 'Y':
                    p = Vector((c, a, s))
                elif axis == 'X':
                    p = Vector((a, c, s))
                else:
                    p = Vector((c, s, a))
                ring.append(o + p)
            secs.append(ring)
        self.loft(secs, material, xform=xform, cap_start=caps[0] and not closed, cap_end=caps[1] and not closed)

    def wing(self, stations, material, u0=0.0, u1=1.0, up=(0, 0, 1), back=(0, -1, 0), tscale=1.0,
             cap_start=True, cap_end=True, xform=None):
        """Aerofoil surface. stations = [(leading_edge_point, chord, thickness), ...]; the part
        between chord fractions u0..u1 is built (u0 > 0 => control surface behind a hinge line).
        u0 / u1 may be lists (one value per station) for straight hinge lines on tapered surfaces."""
        n = len(stations)
        u0s = list(u0) if isinstance(u0, (list, tuple)) else [u0] * n
        u1s = list(u1) if isinstance(u1, (list, tuple)) else [u1] * n
        secs = [af_section(le, c, t * tscale, a0, a1, up, back) for (le, c, t), a0, a1 in zip(stations, u0s, u1s)]
        self.loft(secs, material, cap_start=cap_start, cap_end=cap_end, xform=xform)

    def strut(self, p0, p1, chord, thick, material, chord_dir=(0, 1, 0)):
        """Streamlined (lens section) strut between two points."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = (p1 - p0).normalized()
        c = Vector(chord_dir)
        c = (c - d * c.dot(d)).normalized()
        n = d.cross(c).normalized()

        def sec(p):
            return [p + c * (chord / 2), p + c * (chord * 0.2) + n * (thick / 2), p - c * (chord * 0.3) + n * (thick / 2),
                    p - c * (chord / 2), p - c * (chord * 0.3) - n * (thick / 2), p + c * (chord * 0.2) - n * (thick / 2)]

        self.loft([sec(p0), sec(p1)], material)

    def ribbon(self, pts, width, material, center_fn, out=0.012):
        """Thin raised strip following a polyline on a shell (window frames, seams, stripes)."""
        pts = [Vector(p) for p in pts]
        for a, b in zip(pts[:-1], pts[1:]):
            t = b - a
            if t.length < 1e-5:
                continue
            t.normalize()
            mid = (a + b) / 2
            n = mid - center_fn(mid)
            s = t.cross(n)
            if s.length < 1e-6:
                continue
            s.normalize()
            n = s.cross(t).normalized()
            if n.dot(mid - center_fn(mid)) < 0:
                n = -n
            s *= width / 2
            o = n * out
            self.poly([a - s + o, a + s + o, b + s + o, b - s + o], material, normal=n)

    def disc(self, r_in, r_out, center, material, axis='Z', seg=24, flip=False):
        """Flat annulus (rotor / propeller blur disc)."""
        c = Vector(center)

        def p(r, th):
            if axis == 'Z':
                return c + Vector((math.cos(th) * r, math.sin(th) * r, 0.0))
            if axis == 'Y':
                return c + Vector((math.cos(th) * r, 0.0, math.sin(th) * r))
            return c + Vector((0.0, math.cos(th) * r, math.sin(th) * r))

        nrm = Vector({'Z': (0, 0, 1), 'Y': (0, 1, 0), 'X': (1, 0, 0)}[axis]) * (-1.0 if flip else 1.0)
        for j in range(seg):
            a0 = 2 * math.pi * j / seg
            a1 = 2 * math.pi * (j + 1) / seg
            self.poly([p(r_in, a0), p(r_out, a0), p(r_out, a1), p(r_in, a1)], material, normal=nrm)


# aerofoil: (chord fraction, half thickness fraction)
AF = ((0.0, 0.22), (0.06, 0.42), (0.28, 0.50), (0.70, 0.30), (1.0, 0.06))


def af_h(u):
    for (u0, h0), (u1, h1) in zip(AF[:-1], AF[1:]):
        if u0 <= u <= u1:
            return h0 + (h1 - h0) * (u - u0) / (u1 - u0)
    return AF[-1][1]


def af_us(u0, u1):
    """Chord stations of a section; a fixed count per kind so tapered lofts always match."""
    if u0 <= 0.0 and u1 >= 1.0:
        return [0.0, 0.06, 0.28, 0.70, 1.0]
    if u0 <= 0.0:
        return [0.0, 0.085 * u1, 0.40 * u1, u1]
    return [u0, u1]


def af_section(le, chord, thick, u0=0.0, u1=1.0, up=(0, 0, 1), back=(0, -1, 0)):
    le = Vector(le)
    up = Vector(up)
    back = Vector(back)
    us = af_us(u0, u1)
    top = [le + back * (u * chord) + up * (af_h(u) * thick) for u in us]
    bot = [le + back * (u * chord) - up * (af_h(u) * thick) for u in reversed(us)]
    return top + bot


def hinge_pt(station, u, back=(0, -1, 0)):
    le, chord, _t = station
    return Vector(le) + Vector(back) * (u * chord)


class Parts(dict):
    """name -> MB.  parts("Body") creates the builder on first use."""

    def __call__(self, name):
        if name not in self:
            self[name] = MB()
        return self[name]

    def build(self, root):
        obs = {}
        for name, mb in self.items():
            if len(mb.bm.faces) == 0:
                mb.bm.free()
                continue
            obs[name] = G.new_object(name, mb.bm, parent=root, materials=mb.mats, recalc=False)
        self.clear()
        return obs


class Shell:
    """Fuselage skin from stations of half profiles.  stations = [(y, [(x, z), ...]), ...]; every
    half profile runs from the keel (x = 0, bottom) over the right side to the crown (x = 0, top)
    with the same number of rows.  Bands (between rows) x segments (between stations) can be sent
    to different objects / materials, so glass, doors and stripes fit the hull exactly."""

    def __init__(self, stations):
        self.st = stations
        self.K = len(stations[0][1])
        self.N = len(stations)

    def pt(self, i, k, side=1):
        y, prof = self.st[i]
        x, z = prof[k]
        return Vector((x * side, y, z))

    def center(self, i):
        y, prof = self.st[i]
        zs = [p[1] for p in prof]
        return Vector((0.0, y, (min(zs) + max(zs)) / 2))

    def center_at(self, p):
        """Section centre for an arbitrary point (interpolated along Y)."""
        ys = [s[0] for s in self.st]
        y = p.y
        for i in range(self.N - 1):
            a, b = ys[i], ys[i + 1]
            if (a - y) * (b - y) <= 0 and a != b:
                t = (y - a) / (b - a)
                ca, cb = self.center(i), self.center(i + 1)
                c = ca + (cb - ca) * t
                return Vector((0.0, y, c.z))
        c = self.center(0 if abs(y - ys[0]) < abs(y - ys[-1]) else self.N - 1)
        return Vector((0.0, y, c.z))

    def inset(self, i, k, side, t):
        p = self.pt(i, k, side)
        c = self.center(i)
        d = c - p
        if d.length < t * 1.5:
            return p + d * 0.5
        return p + d.normalized() * t

    def ring(self, i, inset=0.0):
        K = self.K
        idx = [(k, 1) for k in range(K)] + [(k, -1) for k in range(K - 2, 0, -1)]
        return [self.inset(i, k, s, inset) if inset else self.pt(i, k, s) for k, s in idx]

    def rows(self, i, k0, k1, side=1):
        step = 1 if k1 >= k0 else -1
        return [self.pt(i, k, side) for k in range(k0, k1 + step, step)]

    def line(self, k, i0, i1, side=1):
        return [self.pt(i, k, side) for i in range(i0, i1 + 1)]

    def emit(self, parts, tag, liner_t=0.03):
        """tag(i, k, side) -> None | (part_name, material, liner_material_or_None).
        Lined quads get an inner skin (cabin wall) and rim faces toward unlined neighbours (window
        and door openings), so the hull has visible thickness and no see-through slits."""
        specs = {}
        for i in range(self.N - 1):
            for k in range(self.K - 1):
                for side in (1, -1):
                    specs[(i, k, side)] = tag(i, k, side)

        def quad(i, k, side):
            return [self.pt(i, k, side), self.pt(i + 1, k, side), self.pt(i + 1, k + 1, side), self.pt(i, k + 1, side)]

        for (i, k, side), spec in specs.items():
            if spec is None:
                continue
            part, material, liner = spec
            c = (self.center(i) + self.center(i + 1)) / 2
            q = quad(i, k, side)
            parts(part).poly(q, material, away=c)
            if liner is None:
                continue
            qi = [self.inset(i, k, side, liner_t), self.inset(i + 1, k, side, liner_t),
                  self.inset(i + 1, k + 1, side, liner_t), self.inset(i, k + 1, side, liner_t)]
            parts(part).poly(qi, liner, toward=c)
            for key, a, b in (((i - 1, k, side), 0, 3), ((i + 1, k, side), 1, 2), ((i, k - 1, side), 0, 1), ((i, k + 1, side), 3, 2)):
                if key not in specs:
                    continue
                nb = specs[key]
                if nb is not None and nb[2] is not None:
                    continue
                nq = quad(*key)
                nc = (nq[0] + nq[1] + nq[2] + nq[3]) / 4
                parts(part).poly([q[a], q[b], qi[b], qi[a]], liner, toward=nc)

    def cap(self, mb, i, material, normal, inset=0.0):
        mb.poly(self.ring(i, inset), material, normal=normal)


# ------------------------------------------------------------------------------------------------
# object helpers
# ------------------------------------------------------------------------------------------------
def reframe(ob, origin, x_axis=None, z_axis=None):
    """Give `ob` (currently identity basis under its parent) a new local frame: origin at `origin`
    (parent space) and local X along `x_axis` or local Z along `z_axis`. Geometry stays in place."""
    o = Vector(origin)
    if x_axis is not None:
        X = Vector(x_axis).normalized()
        Y = Vector((0, 0, 1)).cross(X).normalized()
        Z = X.cross(Y).normalized()
    elif z_axis is not None:
        Z = Vector(z_axis).normalized()
        Y = Z.cross(Vector((1, 0, 0))).normalized()
        X = Y.cross(Z).normalized()
    else:
        X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    R = Matrix((X, Y, Z)).transposed()
    M = Matrix.Translation(o) @ R.to_4x4()
    ob.data.transform(M.inverted())
    ob.data.update()
    ob.location = o
    ob.rotation_euler = R.to_euler('XYZ')
    G.box_uv(ob)
    return ob


def center_origin(ob):
    """Origin to the bounding-box centre (object must be unrotated)."""
    cs = [v.co for v in ob.data.vertices]
    mn = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    mx = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    G.set_origin(ob, (mn + mx) / 2)
    return ob


def reparent(child, parent):
    """Parent `child` to `parent` (both unrotated children of the same root), keeping its place."""
    child.parent = parent
    child.location = child.location - parent.location
    return child


def hull(name, root, pts, material):
    """Convex collision helper from a point cloud (hidden from renders, wire in the viewport)."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in pts]
    res = bmesh.ops.convex_hull(bm, input=vs)
    junk = []
    for g in list(res.get('geom_interior', [])) + list(res.get('geom_unused', [])):
        if isinstance(g, bmesh.types.BMVert) and g not in junk:
            junk.append(g)
    if junk:
        bmesh.ops.delete(bm, geom=junk, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = G.new_object(name, bm, parent=root, materials=[material], recalc=False)
    ob.display_type = 'WIRE'
    ob.hide_render = True
    if len(ob.data.vertices) > 32:
        print("WARNING: %s has %d verts (> 32)" % (name, len(ob.data.vertices)))
    return ob


def helper_object(ob):
    b = base_name(ob)
    return b.startswith("Col_") or "Blur" in b


def wheel(parts, name, center, radius, width, m, seg=14):
    """Aircraft wheel: tyre + rim, origin at the centre, axle along X."""
    mb = parts(name)
    w = width / 2
    r = radius
    # phase: one tread vertex row exactly at the bottom, so the tyre touches z = centre - radius
    # (with phase 0 a 14-gon's lowest point is 2.5 % short and the aircraft hovers 5 mm)
    ph = seg / 4.0 - math.floor(seg / 4.0)
    mb.lathe([(-w, r * 0.62), (-w, r * 0.86), (-w * 0.55, r), (w * 0.55, r), (w, r * 0.86), (w, r * 0.62)],
             m["tire"], axis='X', origin=center, seg=seg, phase=ph)
    mb.lathe([(-w * 1.04, r * 0.34), (-w * 1.04, r * 0.60), (w * 1.04, r * 0.60), (w * 1.04, r * 0.34)],
             m["rim"], axis='X', origin=center, seg=seg, phase=ph)
    mb.lathe([(-w * 1.16, r * 0.14), (-w * 1.16, r * 0.30), (w * 1.16, r * 0.30), (w * 1.16, r * 0.14)],
             m["trim"], axis='X', origin=center, seg=8)


def seat(mb, pos, m, w=0.46, yaw=0.0, cushion="WarmGrey", back_h=0.62):
    """Chunky seat; pos = floor point under the seat centre; faces +Y rotated by yaw about Z."""
    X = Matrix.Translation(Vector(pos)) @ Matrix.Rotation(yaw, 4, 'Z')
    mb.box((w * 0.78, 0.36, 0.18), (0, 0, 0.09), m["trim"], xform=X)
    mb.box((w, 0.46, 0.13), (0, 0.0, 0.245), m[cushion], bevel=0.025, xform=X)
    mb.box((w, 0.12, back_h), (0, -0.26, 0.24 + back_h / 2), m[cushion], rot=(math.radians(9), 0, 0), bevel=0.025, xform=X)
    mb.box((w * 0.55, 0.09, 0.16), (0, -0.32, 0.30 + back_h + 0.08), m["trim"], bevel=0.02, xform=X)


def finish_rotating(ob, origin, smooth=None):
    G.set_origin(ob, origin)
    if smooth:
        G.shade_smooth(ob, smooth)
    return ob


# ------------------------------------------------------------------------------------------------
# shared aircraft details
# ------------------------------------------------------------------------------------------------
def ring_profile(y, zk, zb, zr, zt, w, wr=0.80, stripe=0.15, wk=0.46, cw=0.88, ck=0.40, sw=0.985, shw=0.52):
    """Half profile rows 0..7: keel, bilge, chine, stripe-low, belt, roof edge, shoulder, crown.
    Bands: 0 belly, 1 bilge, 2 lower side, 3 stripe, 4 window band, 5 roof edge, 6 roof."""
    lower = zb - zk
    return (y, [
        (0.0, zk),
        (w * wk, zk + lower * 0.04),
        (w * cw, zk + lower * ck),
        (w * sw, zb - stripe * min(1.0, lower / 0.5)),
        (w, zb),
        (w * wr, zr),
        (w * wr * shw, zr + (zt - zr) * 0.82),
        (0.0, zt)])


def ngon_ring(y, zc, r, n=8, rz=None):
    rz = r if rz is None else rz
    return [(r * math.cos(2 * math.pi * (j + 0.5) / n), y, zc + rz * math.sin(2 * math.pi * (j + 0.5) / n)) for j in range(n)]


def cowl_sec(y, w, h, z0, zs=None, zc=None):
    """Engine cowl section sitting on a roof: zs = base height at the sides, zc = at the centre."""
    zs = z0 - 0.12 if zs is None else zs
    zc = zs if zc is None else zc
    return [(-w, y, zs), (-w, y, z0 + h * 0.55), (-w * 0.58, y, z0 + h), (w * 0.58, y, z0 + h),
            (w, y, z0 + h * 0.55), (w, y, zs), (0.0, y, zc)]


def rotor_blade(mb, m, radius, chord, yaw, hub_z, root=0.22, droop=0.12, tip_len=0.32, thick=0.045,
                tip_mat="HazardYellow", blade_mat="trim"):
    """One main-rotor blade along +Y (rotated by yaw about Z), with grip, cuff and coloured tip."""
    X = Matrix.Rotation(yaw, 4, 'Z')

    def sec(r, c, t, le_frac=0.3):
        z = hub_z - droop * (r / radius) ** 2
        return [(-c * le_frac, r, z + t / 2), (c * (1 - le_frac), r, z + t * 0.22),
                (c * (1 - le_frac), r, z - t * 0.22), (-c * le_frac, r, z - t / 2)]

    mb.loft([sec(root, chord * 0.42, thick * 1.5, 0.5), sec(root + 0.38, chord * 0.42, thick * 1.3, 0.5)], m["Steel"], xform=X)
    mb.loft([sec(root + 0.36, chord * 0.5, thick, 0.4), sec(root + 0.62, chord, thick),
             sec(radius * 0.6, chord, thick), sec(radius - tip_len, chord, thick * 0.9)], m[blade_mat], xform=X)
    mb.loft([sec(radius - tip_len, chord, thick * 0.9), sec(radius, chord * 0.82, thick * 0.7)], m[tip_mat], xform=X)


def wheel_pant(mb, center, r, w, material):
    """Streamlined wheel fairing (the tyre shows below it)."""
    c = Vector(center)
    secs = []
    for dy, hw, zl, zh in ((r * 1.85, 0.02, 0.10 * r, 0.30 * r), (r * 1.15, w * 0.78, -0.30 * r, 0.98 * r),
                           (0.0, w * 0.90, -0.42 * r, 1.22 * r), (-r * 1.25, w * 0.72, -0.25 * r, 1.0 * r),
                           (-r * 2.45, 0.02, 0.15 * r, 0.36 * r)):
        zm = zl + 0.62 * (zh - zl)
        secs.append([c + Vector(q) for q in ((-hw, dy, zl), (hw, dy, zl), (hw, dy, zm), (hw * 0.55, dy, zh), (-hw * 0.55, dy, zh), (-hw, dy, zm))])
    mb.loft(secs, material)


# -- decals (flat raised polygons: lettering, emblems) -------------------------------------------
def decal_frame(origin, normal, right):
    n = Vector(normal).normalized()
    r = Vector(right)
    r = (r - n * r.dot(n)).normalized()
    return (Vector(origin), r, n.cross(r).normalized(), n)


def decal(mb, pts2d, frame, material, out=0.008):
    o, r, u, n = frame
    return mb.poly([o + r * x + u * y + n * out for x, y in pts2d], material, normal=n)


# block capitals on a 5 x 7 grid: (x, y, w, h)
LETTERS = {
    "H": ((0, 0, 1, 7), (4, 0, 1, 7), (1, 3, 3, 1)),
    "B": ((0, 0, 1, 7), (1, 6, 3, 1), (1, 3, 3, 1), (1, 0, 3, 1), (4, 4, 1, 2), (4, 1, 1, 2)),
    "P": ((0, 0, 1, 7), (1, 6, 3, 1), (1, 3, 3, 1), (4, 4, 1, 2)),
    "D": ((0, 0, 1, 7), (1, 6, 3, 1), (1, 0, 3, 1), (4, 1, 1, 5)),
    "O": ((0, 0, 1, 7), (4, 0, 1, 7), (1, 6, 3, 1), (1, 0, 3, 1)),
    "L": ((0, 0, 1, 7), (1, 0, 4, 1)),
    "I": ((2, 1, 1, 5), (0, 6, 5, 1), (0, 0, 5, 1)),
    "C": ((0, 0, 1, 7), (1, 6, 4, 1), (1, 0, 4, 1)),
    "E": ((0, 0, 1, 7), (1, 6, 4, 1), (1, 3, 3, 1), (1, 0, 4, 1)),
    "0": ((0, 0, 1, 7), (4, 0, 1, 7), (1, 6, 3, 1), (1, 0, 3, 1)),
    "1": ((2, 0, 1, 7), (1, 5, 1, 1), (1, 0, 1, 1), (3, 0, 1, 1)),
    "2": ((0, 6, 5, 1), (4, 4, 1, 2), (0, 3, 5, 1), (0, 1, 1, 2), (0, 0, 5, 1)),
    "3": ((0, 6, 5, 1), (4, 4, 1, 2), (1, 3, 4, 1), (4, 1, 1, 2), (0, 0, 5, 1)),
    "4": ((0, 3, 1, 4), (1, 3, 3, 1), (4, 0, 1, 7)),
    "5": ((0, 6, 5, 1), (0, 4, 1, 2), (0, 3, 5, 1), (4, 1, 1, 2), (0, 0, 5, 1)),
    "6": ((0, 0, 1, 7), (1, 6, 4, 1), (1, 3, 4, 1), (4, 1, 1, 2), (1, 0, 4, 1)),
    "7": ((0, 6, 5, 1), (4, 0, 1, 6)),
    "8": ((0, 0, 1, 7), (4, 0, 1, 7), (1, 6, 3, 1), (1, 3, 3, 1), (1, 0, 3, 1)),
    "9": ((4, 0, 1, 7), (0, 6, 4, 1), (0, 4, 1, 2), (0, 3, 4, 1), (0, 0, 4, 1)),
}


def text_decal(mb, text, frame, height, material, out=0.008):
    unit = height / 7.0
    adv = 6.5 * unit
    x0 = -(len(text) * adv - 1.5 * unit) / 2
    for i, ch in enumerate(text):
        for (a, b, w, h) in LETTERS[ch]:
            xa = x0 + i * adv + a * unit
            ya = -height / 2 + b * unit
            decal(mb, [(xa, ya), (xa + w * unit, ya), (xa + w * unit, ya + h * unit), (xa, ya + h * unit)], frame, material, out)


SHIELD = ((-0.5, 0.48), (0.0, 0.62), (0.5, 0.48), (0.5, -0.02), (0.34, -0.36), (0.0, -0.62), (-0.34, -0.36), (-0.5, -0.02))


def shield_decal(mb, frame, size, m, out=0.008):
    """Original HBPD emblem: gold heater shield, blue field, white five-point star."""
    decal(mb, [(x * size, y * size) for x, y in SHIELD], frame, m["BadgeGold"], out)
    decal(mb, [(x * size * 0.76, y * size * 0.76) for x, y in SHIELD], frame, m["PoliceBlue"], out + 0.004)
    star = []
    for j in range(10):
        rr = (0.27 if j % 2 == 0 else 0.11) * size
        a = math.pi / 2 + j * math.pi / 5
        star.append((rr * math.cos(a), rr * math.sin(a) + 0.02 * size))
    decal(mb, star, frame, m["PoliceWhite"], out + 0.008)


def surf_frame(sa, sb, u_lo, u_hi, face=1, up=(0, 0, 1), back=(0, -1, 0), want_up=(0, 1, 0), right=None):
    """Decal frame on the flat panel of an aerofoil surface between two stations and two chord
    fractions. face = +1 upper (or +up) side, -1 the opposite side. Text runs along the panel (or
    along `right`), its top toward `want_up`; never mirrored."""
    up = Vector(up)
    back = Vector(back)

    def pt(st, u):
        le, c, t = st
        return Vector(le) + back * (u * c) + up * (af_h(u) * t * face)

    a0, a1, b0, b1 = pt(sa, u_lo), pt(sa, u_hi), pt(sb, u_lo), pt(sb, u_hi)
    n = (b0 - a0).cross(a1 - a0)
    if n.dot(up) * face < 0:
        n = -n
    n.normalize()
    r = Vector(right) if right is not None else ((b0 + b1) / 2 - (a0 + a1) / 2)
    r = (r - n * r.dot(n)).normalized()
    if n.cross(r).dot(Vector(want_up)) < 0:
        r = -r
    return decal_frame((a0 + a1 + b0 + b1) / 4, n, r)


# ------------------------------------------------------------------------------------------------
# heli_civil - light civil helicopter (two-blade teetering rotor, bubble cockpit, skids)
# ------------------------------------------------------------------------------------------------
def build_heli_civil():
    m = mats()
    root = G.asset_root("heli_civil", HELI_COL, G.slot("aircraft", SLOTS["heli_civil"]))
    parts = Parts()
    body = parts("Body")
    paint, paint2, glass, trim, interior = m["paint"], m["paint2"], m["glass"], m["trim"], m["interior"]

    # ---- fuselage pod -------------------------------------------------------------------------
    st = [
        ring_profile(2.74, 0.90, 0.985, 1.05, 1.09, 0.10),
        ring_profile(2.50, 0.78, 1.02, 1.17, 1.23, 0.36),
        ring_profile(2.05, 0.67, 1.06, 1.52, 1.64, 0.60, wr=0.84),
        ring_profile(1.50, 0.62, 1.10, 1.88, 2.02, 0.75, wr=0.82),
        ring_profile(0.85, 0.60, 1.12, 2.08, 2.20, 0.80),
        ring_profile(-0.20, 0.60, 1.12, 2.12, 2.24, 0.80),
        ring_profile(-1.15, 0.63, 1.12, 2.08, 2.22, 0.78),
        ring_profile(-1.85, 0.82, 1.20, 1.94, 2.10, 0.60),
        ring_profile(-2.40, 1.20, 1.44, 1.80, 1.92, 0.32),
        ring_profile(-3.05, 1.53, 1.70, 1.86, 1.93, 0.19),      # tail cone, ends inside the boom (no blunt rear wall)
    ]
    sh = Shell(st)

    def tag(i, k, side):
        L = 'L' if side < 0 else 'R'
        lin = interior if 1 <= i <= 5 else None
        if i in (1, 2, 3) and k >= 4:
            return ("Glass_Windshield", glass, None)
        if i == 4:
            if k == 4:
                return ("Glass_" + L, glass, None)
            if k in (2, 3):
                return ("Door_F" + L, paint2 if k == 3 else paint, interior)
        if i == 5:
            if k == 4:
                return ("Glass_R" + L, glass, None)
            if k in (2, 3):
                return ("Door_R" + L, paint2 if k == 3 else paint, interior)
        if i == 6 and k == 4:
            return ("Body", trim, None)            # blanked rear quarter panel (engine bay louvre)
        mat = paint
        if k == 3 and 1 <= i <= 6:
            mat = paint2
        return ("Body", mat, lin)

    sh.emit(parts, tag)
    sh.cap(body, 0, paint, (0, 1, 0))
    sh.cap(body, 9, paint, (0, -1, 0))
    cf = sh.center_at

    # window frames / pillars
    for i in (4, 5, 6):
        for s in (1, -1):
            body.ribbon(sh.rows(i, 4, 5, s), 0.07, trim, cf)
    body.ribbon(sh.rows(4, 5, 7, 1) + sh.rows(4, 6, 5, -1), 0.07, trim, cf)        # windshield header
    body.ribbon(sh.line(7, 1, 4), 0.06, trim, cf, out=0.014)                       # centre post
    for s in (1, -1):
        body.ribbon(sh.line(4, 1, 6, s), 0.05, trim, cf)                           # belt line
        body.ribbon(sh.line(5, 4, 6, s), 0.05, trim, cf)                           # door header
        body.ribbon(sh.rows(1, 4, 7, s), 0.05, trim, cf)                           # nose glazing ring
        for i in (4, 5, 6):                                                        # door shut lines
            body.ribbon(sh.rows(i, 2, 4, s), 0.024, trim, cf, out=0.006)
        body.ribbon(sh.line(2, 4, 6, s), 0.024, trim, cf, out=0.006)               # door sill
        body.box((0.03, 0.14, 0.035), (0.80 * s, 0.62, 1.02), m["chrome"])           # door handles
        body.box((0.03, 0.14, 0.035), (0.795 * s, -0.42, 1.02), m["chrome"])

    # ---- cabin interior ---------------------------------------------------------------------------
    zf = 0.72
    body.poly([(-0.33, 2.0, zf), (0.33, 2.0, zf), (0.50, 1.5, zf), (0.56, 0.85, zf), (0.56, -1.15, zf),
               (-0.56, -1.15, zf), (-0.56, 0.85, zf), (-0.50, 1.5, zf)], interior, normal=(0, 0, 1))
    body.poly(sh.ring(6, 0.03), interior, normal=(0, 1, 0))                         # rear bulkhead
    for sx in (-0.36, 0.36):
        seat(body, (sx, 0.32, zf), m)
        seat(body, (sx, -0.74, zf), m)
    body.box((0.36, 0.40, 0.46), (0, 1.52, zf + 0.23), trim, bevel=0.03)             # centre console
    body.box((0.86, 0.16, 0.26), (0, 1.50, zf + 0.52), trim, rot=(math.radians(-18), 0, 0), bevel=0.03)
    body.box((0.30, 0.02, 0.14), (-0.22, 1.415, zf + 0.53), m["Screen"], rot=(math.radians(-18), 0, 0))
    body.box((0.30, 0.02, 0.14), (0.22, 1.415, zf + 0.53), m["Screen"], rot=(math.radians(-18), 0, 0))
    for sx in (-0.36, 0.36):                                                         # cyclic sticks
        body.tube((sx, 0.72, zf), (sx, 0.62, zf + 0.42), 0.018, trim, seg=6)
        body.box((0.04, 0.05, 0.10), (sx, 0.61, zf + 0.46), trim)

    # ---- engine cowl ("doghouse"), mast ---------------------------------------------------------
    body.loft([cowl_sec(1.00, 0.26, 0.05, 2.15, 2.12, 2.15), cowl_sec(0.55, 0.38, 0.30, 2.17, 2.175, 2.20),
               cowl_sec(-1.25, 0.38, 0.34, 2.17, 2.165, 2.20), cowl_sec(-2.05, 0.30, 0.26, 1.98, 1.86, 1.86),
               cowl_sec(-2.75, 0.17, 0.10, 1.84, 1.72, 1.72)], paint)
    for s in (1, -1):
        body.box((0.05, 0.50, 0.15), (0.385 * s, 0.05, 2.36), trim, bevel=0.012)       # intake grilles
        body.box((0.05, 0.42, 0.10), (0.385 * s, -0.85, 2.37), trim, bevel=0.012)
    body.tube((0, -1.52, 2.46), (0, -1.80, 2.60), 0.085, m["SteelDark"], r1=0.075, seg=8)  # exhaust stack
    body.tube((0, -1.775, 2.59), (0, -1.81, 2.607), 0.058, m["Black"], seg=8)
    body.cyl(0.15, 0.16, (0, 0, 2.55), paint2, seg=10, r2=0.10)                           # mast fairing
    body.cyl(0.05, 0.42, (0, 0, 2.78), m["Steel"], seg=8)                                 # mast
    body.cyl(0.17, 0.035, (0, 0, 2.74), trim, seg=10)                                     # swashplate
    for a in (0.6, 0.6 + math.pi):                                                        # pitch links
        body.tube((0.15 * math.cos(a), 0.15 * math.sin(a), 2.74), (0.12 * math.cos(a), 0.12 * math.sin(a), 2.95), 0.012, m["Steel"], seg=5)

    # ---- tail boom, stabiliser, fin ---------------------------------------------------------------
    boom = [(-2.15, 1.66, 0.275), (-4.55, 1.835, 0.170), (-5.05, 1.87, 0.150), (-5.95, 1.935, 0.110)]
    body.loft([ngon_ring(*boom[0]), ngon_ring(*boom[1])], paint, cap_end=False)
    body.loft([ngon_ring(*boom[1]), ngon_ring(*boom[2])], paint2, cap_start=False, cap_end=False)
    body.loft([ngon_ring(*boom[2]), ngon_ring(*boom[3])], paint, cap_start=False)
    kx = math.cos(math.pi / 8)                                                     # flat side facet of the octagonal boom
    b_slope = kx * (boom[1][2] - boom[0][2]) / (boom[1][0] - boom[0][0])
    b_rise = (boom[1][1] - boom[0][1]) / (boom[1][0] - boom[0][0])
    for s in (1, -1):                                                              # registration on the boom sides
        yb = -3.40
        tb = (yb - boom[0][0]) / (boom[1][0] - boom[0][0])
        rb = boom[0][2] + (boom[1][2] - boom[0][2]) * tb
        zb = boom[0][1] + (boom[1][1] - boom[0][1]) * tb
        text_decal(body, "HB204", decal_frame((rb * kx * s, yb, zb), (s, -b_slope, 0), (0, s, s * b_rise)), 0.115, paint2, out=0.006)
    body.loft([[(-0.05, -2.6, 1.86), (0.05, -2.6, 1.86), (0.05, -2.6, 2.00), (-0.05, -2.6, 2.00)],        # drive-shaft cover
               [(-0.04, -5.6, 1.98), (0.04, -5.6, 1.98), (0.04, -5.6, 2.06), (-0.04, -5.6, 2.06)]], trim)
    body.wing([((-0.98, -4.02, 1.80), 0.50, 0.07), ((0.98, -4.02, 1.80), 0.50, 0.07)], paint)             # stabiliser
    for s in (1, -1):                                                                                      # end plates
        body.wing([((0.98 * s, -3.98, 1.60), 0.42, 0.045), ((0.98 * s, -4.06, 1.80), 0.52, 0.05), ((0.98 * s, -4.16, 2.04), 0.36, 0.045)],
                  paint2, up=(1, 0, 0))
    fin = [((0, -5.60, 1.20), 0.36, 0.06), ((0, -5.40, 1.90), 0.78, 0.085), ((0, -5.86, 2.70), 0.54, 0.07), ((0, -6.04, 3.02), 0.42, 0.06)]
    body.wing(fin[0:3], paint, up=(1, 0, 0), cap_end=False)
    body.wing(fin[2:4], paint2, up=(1, 0, 0), cap_start=False)
    body.path_tube([(0, -5.66, 1.24), (0, -5.86, 1.04), (0, -6.06, 1.00)], 0.022, m["Steel"], seg=6)   # tail skid
    body.cyl(0.085, 0.16, (-0.10, -5.78, 1.935), m["Steel"], axis='X', seg=8)                    # tail gearbox
    body.box((0.05, 0.08, 0.08), (0, -6.05, 1.935), m["White"])                                  # tail position light
    body.cyl(0.045, 0.07, (0, -6.22, 3.06), m["taillight"], seg=6)                               # beacon
    body.box((0.04, 0.10, 0.05), (-1.0, -4.2, 2.07), m["taillight"])                             # nav lights
    body.box((0.04, 0.10, 0.05), (1.0, -4.2, 2.07), m["NavGreen"])

    # ---- landing gear: skids ------------------------------------------------------------------------
    sx = 1.04
    for s in (1, -1):
        body.path_tube([(sx * s, 2.36, 0.30), (sx * s, 2.10, 0.11), (sx * s, 1.80, 0.05), (sx * s, -1.62, 0.05)],
                       0.05, m["Charcoal"], seg=8, ref=(1, 0, 0))
        body.box((0.26, 0.62, 0.035), ((sx - 0.02) * s, 0.25, 0.115), m["Steel"], bevel=0.01)     # step plate
    for y in (1.18, -0.92):
        body.path_tube([(-sx, y, 0.07), (-0.84, y, 0.40), (-0.44, y, 0.67), (0.44, y, 0.67), (0.84, y, 0.40), (sx, y, 0.07)],
                       0.042, m["Charcoal"], seg=8, ref=(0, 1, 0))
    body.cyl(0.075, 0.06, (0, 2.20, 0.705), m["headlight"], axis='Y', seg=8, rot=(math.radians(-25), 0, 0))   # landing light
    body.box((0.10, 0.12, 0.10), (0, 2.16, 0.715), trim)
    body.box((0.02, 0.26, 0.20), (0, -0.2, 0.52), trim, bevel=0.006)                             # blade antenna
    body.cyl(0.05, 0.05, (0, -1.5, 0.74), m["taillight"], seg=6)                                 # belly beacon
    body.tube((0.30, 2.62, 0.93), (0.30, 2.92, 0.93), 0.012, m["Steel"], seg=5)                  # pitot
    text_decal(body, "HB204", decal_frame((0, -0.15, 0.60), (0, 0, -1), (0, 1, 0)), 0.40, paint2, out=0.012)   # belly registration

    # ---- rotors -------------------------------------------------------------------------------------
    hub_z = 2.99
    rm = parts("Rotor_Main")
    rm.cyl(0.13, 0.13, (0, 0, hub_z), m["Steel"], seg=10)
    rm.cyl(0.07, 0.07, (0, 0, hub_z + 0.10), trim, seg=8, r2=0.04)
    rm.box((0.16, 0.56, 0.07), (0, 0, hub_z), m["Charcoal"], bevel=0.012)
    for a in (0.0, math.pi):
        rotor_blade(rm, m, 4.75, 0.30, a, hub_z)
    rm.tube((-0.75, 0, hub_z + 0.02), (0.75, 0, hub_z + 0.02), 0.014, m["Steel"], seg=5)   # stabiliser bar
    for s in (1, -1):
        rm.box((0.16, 0.07, 0.05), (0.78 * s, 0, hub_z + 0.02), m["Charcoal"], bevel=0.01)
    parts("RotorBlur_Main").disc(0.35, 4.75, (0, 0, hub_z - 0.03), m["blur"], axis='Z', seg=28)

    tr_c = Vector((-0.215, -5.78, 1.935))
    rt = parts("Rotor_Tail")
    rt.cyl(0.055, 0.09, tr_c, m["Steel"], axis='X', seg=8)
    for a in (0.0, math.pi):
        X = Matrix.Translation(tr_c) @ Matrix.Rotation(a + 0.35, 4, 'X')
        rt.loft([[(-0.012, -0.045, 0.05), (0.012, -0.045, 0.05), (0.012, 0.045, 0.05), (-0.012, 0.045, 0.05)],
                 [(-0.012, -0.075, 0.26), (0.012, -0.075, 0.26), (0.012, 0.06, 0.26), (-0.012, 0.06, 0.26)],
                 [(-0.010, -0.075, 0.62), (0.010, -0.075, 0.62), (0.010, 0.06, 0.62), (-0.010, 0.06, 0.62)]], trim, xform=X)
        rt.loft([[(-0.010, -0.075, 0.62), (0.010, -0.075, 0.62), (0.010, 0.06, 0.62), (-0.010, 0.06, 0.62)],
                 [(-0.008, -0.06, 0.72), (0.008, -0.06, 0.72), (0.008, 0.05, 0.72), (-0.008, 0.05, 0.72)]], m["HazardYellow"], xform=X)

    # ---- objects --------------------------------------------------------------------------------------
    obs = parts.build(root)
    finish_rotating(obs["Rotor_Main"], (0, 0, hub_z))
    finish_rotating(obs["RotorBlur_Main"], (0, 0, hub_z))
    obs["RotorBlur_Main"].hide_render = True
    finish_rotating(obs["Rotor_Tail"], tr_c)
    center_origin(obs["Glass_Windshield"])
    for L, s in (("L", -1), ("R", 1)):
        G.set_origin(obs["Door_F" + L], sh.pt(4, 4, s))
        G.set_origin(obs["Door_R" + L], sh.pt(5, 4, s))
        center_origin(obs["Glass_" + L])
        center_origin(obs["Glass_R" + L])
        reparent(obs["Glass_" + L], obs["Door_F" + L])
        reparent(obs["Glass_R" + L], obs["Door_R" + L])

    # ---- collision helpers ----------------------------------------------------------------------------
    hull("Col_Body", root, [
        (-1.04, 2.1, 0.0), (1.04, 2.1, 0.0), (-1.04, -1.6, 0.0), (1.04, -1.6, 0.0),
        (-0.36, 2.5, 0.80), (0.36, 2.5, 0.80), (0.0, 2.74, 1.0),
        (-0.80, 0.85, 1.12), (0.80, 0.85, 1.12), (-0.80, -1.15, 1.12), (0.80, -1.15, 1.12),
        (-0.60, 1.5, 1.90), (0.60, 1.5, 1.90),
        (-0.64, 0.85, 2.10), (0.64, 0.85, 2.10), (-0.62, -1.15, 2.10), (0.62, -1.15, 2.10),
        (-0.36, 0.5, 2.52), (0.36, 0.5, 2.52), (-0.36, -1.3, 2.52), (0.36, -1.3, 2.52),
        (-0.34, -2.4, 1.25), (0.34, -2.4, 1.25), (-0.30, -2.4, 2.0), (0.30, -2.4, 2.0)], m["col"])
    hull("Col_Tail", root, [
        (-0.26, -2.2, 1.40), (0.26, -2.2, 1.40), (-0.26, -2.2, 1.93), (0.26, -2.2, 1.93),
        (-0.98, -4.0, 1.78), (0.98, -4.0, 1.78), (-0.98, -4.55, 1.82), (0.98, -4.55, 1.82),
        (-0.10, -5.6, 1.20), (0.10, -5.6, 1.20), (-0.10, -5.95, 1.20), (0.10, -5.95, 1.20),
        (-0.06, -6.04, 3.02), (0.06, -6.04, 3.02), (-0.06, -6.46, 3.02), (0.06, -6.46, 3.02),
        (-0.12, -6.18, 1.9), (0.12, -6.18, 1.9)], m["col"])

    # ---- markers --------------------------------------------------------------------------------------
    hip = zf + 0.36
    G.empty("Seat_Driver", root, (-0.36, 0.32, hip))
    G.empty("Seat_Passenger_1", root, (0.36, 0.32, hip))
    G.empty("Seat_Passenger_2", root, (-0.36, -0.74, hip))
    G.empty("Seat_Passenger_3", root, (0.36, -0.74, hip))
    G.empty("Exit_Driver", root, (-1.75, 0.35, 0.0))
    G.empty("Exit_Passenger_1", root, (1.75, 0.35, 0.0))
    G.empty("Exit_Passenger_2", root, (-1.75, -0.75, 0.0))
    G.empty("Exit_Passenger_3", root, (1.75, -0.75, 0.0))
    G.empty("Engine", root, (0.0, -0.9, 2.40))
    G.empty("Exhaust", root, (0.0, -1.84, 2.63))
    G.empty("Light_Head", root, (0.0, 2.26, 0.68))
    G.empty("Light_Head_L", root, (-0.09, 2.26, 0.68))
    G.empty("Light_Head_R", root, (0.09, 2.26, 0.68))
    G.empty("Light_Tail", root, (0.0, -6.10, 1.935))
    G.empty("Light_Tail_L", root, (-1.02, -4.26, 2.07))
    G.empty("Light_Tail_R", root, (1.02, -4.26, 2.07))
    G.empty("Light_Beacon", root, (0.0, -6.22, 3.12))
    return root


# ------------------------------------------------------------------------------------------------
# heli_police - HBPD utility helicopter (slab-sided cabin, open side bays with outward benches,
# four-blade rotor, shrouded tail fan, searchlight + sensor ball, blue / white / gold livery)
# ------------------------------------------------------------------------------------------------
def police_ring(y, zk, zb, zr, zt, w, wr=0.86):
    """Rows: keel, bilge, sill (cabin floor level), stripe-low, belt, roof edge, shoulder, crown."""
    lower = zb - zk
    return (y, [
        (0.0, zk),
        (w * 0.62, zk + min(0.03, lower * 0.08)),
        (w * 0.93, zk + min(0.22, lower * 0.42)),
        (w, zb - min(0.12, lower * 0.25)),
        (w, zb),
        (w * wr, zr),
        (w * wr * 0.6, zr + (zt - zr) * 0.8),
        (0.0, zt)])


def build_heli_police():
    m = mats()
    root = G.asset_root("heli_police", HELI_COL, G.slot("aircraft", SLOTS["heli_police"]))
    parts = Parts()
    body = parts("Body")
    glass, trim, interior = m["glass"], m["trim"], m["interior"]
    blue, white, gold = m["PoliceBlue"], m["PoliceWhite"], m["BadgeGold"]

    st = [
        police_ring(3.25, 0.98, 1.08, 1.15, 1.19, 0.14),
        police_ring(2.98, 0.84, 1.14, 1.34, 1.40, 0.48),
        police_ring(2.45, 0.74, 1.30, 1.70, 1.80, 0.76),
        police_ring(1.85, 0.70, 1.44, 2.20, 2.32, 0.90),
        police_ring(1.20, 0.70, 1.50, 2.32, 2.44, 0.95),
        police_ring(0.15, 0.70, 1.50, 2.34, 2.46, 0.95),
        police_ring(-1.35, 0.70, 1.50, 2.34, 2.46, 0.95),
        police_ring(-2.05, 0.80, 1.52, 2.26, 2.40, 0.86),
        police_ring(-2.75, 1.05, 1.60, 2.12, 2.24, 0.58),
        police_ring(-3.30, 1.42, 1.72, 2.00, 2.10, 0.32),
    ]
    sh = Shell(st)

    def tag(i, k, side):
        L = 'L' if side < 0 else 'R'
        lin = interior if 1 <= i <= 6 else None
        if i in (2, 3) and k >= 4:
            return ("Glass_Windshield", glass, None)
        if i == 2 and k == 2:
            return ("Glass_Chin", glass, None)
        if i == 4:
            if k == 4:
                return ("Glass_" + L, glass, None)
            if k in (2, 3):
                return ("Door_F" + L, blue if k == 2 else gold, interior)
        if i == 5 and k in (2, 3, 4):
            return None                                 # open side bay
        if i == 6 and k == 4:
            return ("Glass_R" + L, glass, None)
        if i <= 1:
            mat = blue                                  # dark nose
        elif k <= 2:
            mat = blue
        elif k == 3:
            mat = gold
        else:
            mat = white
        return ("Body", mat, lin)

    sh.emit(parts, tag)
    sh.cap(body, 0, blue, (0, 1, 0))
    sh.cap(body, 9, blue, (0, -1, 0))
    cf = sh.center_at

    # frames, pillars, door rails
    for i in (4, 5, 6, 7):
        for s in (1, -1):
            body.ribbon(sh.rows(i, 4, 5, s), 0.08, trim, cf)
    body.ribbon(sh.rows(4, 5, 7, 1) + sh.rows(4, 6, 5, -1), 0.08, trim, cf)        # windshield header
    body.ribbon(sh.line(7, 2, 4), 0.09, trim, cf, out=0.014)                       # centre post
    body.ribbon(sh.rows(2, 4, 7, 1) + sh.rows(2, 6, 4, -1), 0.06, trim, cf)        # windshield base
    for s in (1, -1):
        L = 'L' if s < 0 else 'R'
        body.ribbon(sh.line(4, 2, 7, s), 0.05, trim, cf)                           # belt
        body.ribbon(sh.line(5, 4, 8, s), 0.06, trim, cf, out=0.02)                 # upper door rail
        body.ribbon(sh.line(2, 5, 7, s), 0.06, trim, cf, out=0.02)                 # lower door rail
        body.ribbon(sh.rows(5, 2, 4, s), 0.06, trim, cf)                           # bay edges
        body.ribbon(sh.rows(6, 2, 4, s), 0.06, trim, cf)
        body.box((0.03, 0.16, 0.04), (0.955 * s, 0.95, 1.30), m["chrome"])            # door handle
        # grab rail above the open bay
        body.tube((0.80 * s, -0.05, 2.20), (0.80 * s, -1.15, 2.20), 0.02, m["HazardYellow"], seg=6)
        for y in (-0.05, -1.15):
            body.tube((0.80 * s, y, 2.20), (0.80 * s, y, 2.31), 0.016, m["Steel"], seg=5)
        # emblem on the front doors
        q = [sh.pt(4, 2, s), sh.pt(5, 2, s), sh.pt(5, 3, s), sh.pt(4, 3, s)]
        qc = (q[0] + q[1] + q[2] + q[3]) / 4
        qn = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
        if qn.x * s < 0:
            qn = -qn
        shield_decal(parts("Door_F" + L), decal_frame(qc, qn, (0, s, 0)), 0.30, m)

    # ---- interior -------------------------------------------------------------------------------------
    zf = 0.92
    body.poly([(-0.42, 2.75, zf), (0.42, 2.75, zf), (0.68, 2.45, zf), (0.82, 1.85, zf), (0.87, 1.2, zf), (0.87, -1.35, zf),
               (0.64, -2.05, zf), (-0.64, -2.05, zf), (-0.87, -1.35, zf), (-0.87, 1.2, zf), (-0.82, 1.85, zf), (-0.68, 2.45, zf)],
              m["SteelDark"], normal=(0, 0, 1))
    body.poly(sh.ring(7, 0.03), interior, normal=(0, 1, 0))                         # rear bulkhead
    for sx in (-0.45, 0.45):
        seat(body, (sx, 0.72, zf), m, w=0.48)
    for s in (1, -1):                                                               # outward facing benches
        for y in (-0.25, -0.95):
            seat(body, (0.42 * s, y, zf), m, w=0.56, yaw=-s * math.pi / 2, cushion="Charcoal", back_h=0.5)
    body.box((0.42, 0.46, 0.50), (0, 2.08, zf + 0.25), trim, bevel=0.03)             # console
    body.box((1.20, 0.18, 0.30), (0, 2.02, zf + 0.56), trim, rot=(math.radians(-16), 0, 0), bevel=0.03)
    for sx in (-0.36, 0.0, 0.36):
        body.box((0.28, 0.02, 0.16), (sx, 1.925, zf + 0.57), m["Screen"], rot=(math.radians(-16), 0, 0))
    for sx in (-0.45, 0.45):
        body.tube((sx, 1.16, zf), (sx, 1.04, zf + 0.44), 0.02, trim, seg=6)
        body.box((0.045, 0.05, 0.11), (sx, 1.03, zf + 0.48), trim)

    # ---- twin-engine cowl, mast ---------------------------------------------------------------------
    body.loft([cowl_sec(1.35, 0.34, 0.06, 2.38, 2.385, 2.395), cowl_sec(0.80, 0.54, 0.34, 2.40, 2.395, 2.43),
               cowl_sec(-1.45, 0.54, 0.40, 2.40, 2.39, 2.43), cowl_sec(-2.45, 0.44, 0.32, 2.26, 2.10, 2.10),
               cowl_sec(-3.25, 0.24, 0.12, 2.06, 1.90, 1.90)], white)
    for s in (1, -1):
        body.box((0.26, 0.10, 0.17), (0.27 * s, 0.86, 2.585), trim, rot=(math.radians(-32), 0, 0), bevel=0.015)   # intakes
        body.box((0.05, 0.70, 0.14), (0.545 * s, -0.35, 2.62), trim, bevel=0.012)                               # louvres
        body.tube((0.40 * s, -1.75, 2.66), (0.64 * s, -2.25, 2.74), 0.095, m["SteelDark"], r1=0.085, seg=8)     # exhausts
        body.tube((0.628 * s, -2.225, 2.736), (0.645 * s, -2.26, 2.742), 0.065, m["Black"], seg=8)
    body.cyl(0.19, 0.18, (0, 0, 2.86), blue, seg=10, r2=0.12)                           # mast fairing
    body.cyl(0.06, 0.50, (0, 0, 3.14), m["Steel"], seg=8)                               # mast
    body.cyl(0.20, 0.04, (0, 0, 3.10), trim, seg=10)                                    # swashplate
    for j in range(4):
        a = 0.4 + j * math.pi / 2
        body.tube((0.18 * math.cos(a), 0.18 * math.sin(a), 3.10), (0.15 * math.cos(a), 0.15 * math.sin(a), 3.34), 0.012, m["Steel"], seg=5)
    body.wing([((0, 1.80, 2.36), 0.55, 0.03), ((0, 1.62, 2.84), 0.10, 0.02)], m["Steel"], up=(1, 0, 0))    # wire cutters
    body.wing([((0, 2.70, 0.80), 0.50, 0.03), ((0, 2.52, 0.42), 0.10, 0.02)], m["Steel"], up=(1, 0, 0))

    # ---- tail: slab boom, lettering, stabiliser, shrouded fan, fin -------------------------------------
    def boom_ring(y, zc, rx, rz):
        return [(rx, y, zc - 0.6 * rz), (rx, y, zc + 0.6 * rz), (0.5 * rx, y, zc + rz), (-0.5 * rx, y, zc + rz),
                (-rx, y, zc + 0.6 * rz), (-rx, y, zc - 0.6 * rz), (-0.5 * rx, y, zc - rz), (0.5 * rx, y, zc - rz)]

    b0 = (-3.05, 1.90, 0.30, 0.36)
    b1 = (-6.02, 1.98, 0.17, 0.26)
    body.loft([boom_ring(*b0), boom_ring(*b1)], blue)
    slope = (b1[2] - b0[2]) / (b1[0] - b0[0])
    for s in (1, -1):
        # POLICE on the boom sides (between the tail cone and the stabiliser)
        y = -4.00
        t = (y - b0[0]) / (b1[0] - b0[0])
        x = b0[2] + (b1[2] - b0[2]) * t
        z = b0[1] + (b1[1] - b0[1]) * t
        text_decal(body, "POLICE", decal_frame((x * s, y, z), (s, -slope, 0), (0, s, 0)), 0.22, white)
        # department initials on the white rear quarter panel
        q = [sh.pt(7, 4, s), sh.pt(8, 4, s), sh.pt(8, 5, s), sh.pt(7, 5, s)]
        qc = (q[0] + q[1] + q[2] + q[3]) / 4
        qn = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
        if qn.x * s < 0:
            qn = -qn
        text_decal(body, "HBPD", decal_frame(qc + Vector((0, 0, -0.02)), qn, (0, s, 0)), 0.17, blue, out=0.012)
    # belly lettering, readable from the street when the helicopter is overhead
    text_decal(body, "POLICE", decal_frame((0, 0.0, 0.70), (0, 0, -1), (0, 1, 0)), 0.52, white, out=0.012)
    body.wing([((-1.12, -4.70, 1.97), 0.62, 0.08), ((1.12, -4.70, 1.97), 0.62, 0.08)], blue)                  # stabiliser
    for s in (1, -1):
        body.wing([((1.12 * s, -4.62, 1.66), 0.50, 0.05), ((1.12 * s, -4.70, 1.97), 0.66, 0.06), ((1.12 * s, -4.98, 2.50), 0.40, 0.05)],
                  white, up=(1, 0, 0))
    fc = Vector((0.0, -6.62, 1.98))
    body.lathe([(-0.15, 0.50), (-0.19, 0.58), (-0.12, 0.72), (0.12, 0.72), (0.19, 0.58), (0.15, 0.50)], blue,
               axis='X', origin=fc, seg=14, closed=True)
    body.wing([((0, -6.18, 2.52), 1.00, 0.13), ((0, -6.58, 3.12), 0.76, 0.10)], white, up=(1, 0, 0), cap_end=False)
    body.wing([((0, -6.58, 3.12), 0.76, 0.10), ((0, -6.92, 3.56), 0.52, 0.08)], blue, up=(1, 0, 0), cap_start=False)
    body.wing([((0, -6.30, 1.42), 0.80, 0.11), ((0, -6.48, 1.10), 0.46, 0.07)], blue, up=(1, 0, 0))             # ventral fin
    body.path_tube([(0, -6.60, 1.14), (0, -6.82, 0.96), (0, -7.00, 0.94)], 0.024, m["Steel"], seg=6)            # bumper
    body.cyl(0.10, 0.14, (0.08, fc.y, fc.z), m["Steel"], axis='X', seg=8)                                       # fan gearbox
    for j in range(3):
        a = math.radians(90 + 120 * j)
        body.tube((0.09, fc.y + 0.09 * math.cos(a), fc.z + 0.09 * math.sin(a)),
                  (0.09, fc.y + 0.52 * math.cos(a), fc.z + 0.52 * math.sin(a)), 0.02, m["Steel"], seg=5)        # stators
    body.box((0.05, 0.08, 0.08), (0, -7.37, 3.10), m["White"])                                                 # tail light
    body.cyl(0.05, 0.08, (0, -7.10, 3.60), m["taillight"], seg=6)                                               # beacon
    body.box((0.04, 0.10, 0.05), (-1.14, -4.95, 2.52), m["taillight"])
    body.box((0.04, 0.10, 0.05), (1.14, -4.95, 2.52), m["NavGreen"])

    # ---- skids with long steps ----------------------------------------------------------------------
    sx = 1.24
    for s in (1, -1):
        body.path_tube([(sx * s, 2.75, 0.34), (sx * s, 2.45, 0.12), (sx * s, 2.10, 0.055), (sx * s, -2.05, 0.055)],
                       0.055, m["Charcoal"], seg=8, ref=(1, 0, 0))
        body.box((0.30, 2.10, 0.04), ((sx - 0.10) * s, -0.45, 0.42), m["Steel"], bevel=0.012)              # step board
        for y in (0.30, -1.20):
            body.tube(((sx - 0.10) * s, y, 0.40), (sx * s, y, 0.07), 0.02, m["Charcoal"], seg=5)
    for y in (1.35, -1.55):
        body.path_tube([(-sx, y, 0.08), (-1.02, y, 0.50), (-0.58, y, 0.77), (0.58, y, 0.77), (1.02, y, 0.50), (sx, y, 0.08)],
                       0.048, m["Charcoal"], seg=8, ref=(0, 1, 0))

    # ---- police equipment ---------------------------------------------------------------------------
    body.box((0.16, 0.30, 0.07), (-0.30, 1.75, 0.675), m["siren_red"], bevel=0.012)       # belly strobes
    body.box((0.16, 0.30, 0.07), (0.30, 1.75, 0.675), m["siren_blue"], bevel=0.012)
    body.box((0.26, 0.20, 0.16), (0.0, -1.95, 0.74), trim, bevel=0.02)                    # loudspeaker
    body.box((0.20, 0.03, 0.11), (0.0, -1.85, 0.74), m["Steel"])
    body.box((0.02, 0.30, 0.22), (0, -2.6, 0.92), trim, bevel=0.006)                      # antennas
    body.tube((0.2, -3.6, 2.22), (0.2, -3.9, 2.72), 0.012, trim, seg=5)
    body.cyl(0.085, 0.07, (0, 3.10, 0.93), m["headlight"], axis='Y', seg=8, rot=(math.radians(-15), 0, 0))    # landing light
    # searchlight mount (the lamp itself is the separate 'Searchlight' object)
    gim = Vector((-0.50, 2.28, 0.58))
    body.tube((gim.x, gim.y, 0.80), (gim.x, gim.y, gim.z + 0.20), 0.035, trim, seg=6)
    body.box((0.46, 0.06, 0.05), (gim.x, gim.y, gim.z + 0.215), trim)
    for dx in (-0.215, 0.215):
        body.box((0.03, 0.06, 0.25), (gim.x + dx, gim.y, gim.z + 0.10), trim)
    sl = parts("Searchlight")
    sl.lathe([(-0.16, 0.0), (-0.16, 0.10), (-0.06, 0.165), (0.16, 0.185), (0.20, 0.185)], m["Charcoal"], axis='Y', origin=gim, seg=10,
             caps=(False, False))
    sl.disc(0.160, 0.185, gim + Vector((0, 0.20, 0)), m["chrome"], axis='Y', seg=10)
    sl.disc(0.0, 0.160, gim + Vector((0, 0.19, 0)), m["headlight"], axis='Y', seg=10)
    sl.cyl(0.03, 0.40, gim, m["Steel"], axis='X', seg=6)
    # sensor ball (FLIR turret)
    sc = Vector((0.46, 2.50, 0.56))
    body.cyl(0.11, 0.16, (sc.x, sc.y, 0.72), trim, seg=8)
    sb = parts("SensorBall")
    sb.sphere(0.17, sc, m["Charcoal"], seg=10, rings=7)
    sb.cyl(0.075, 0.04, (sc.x, sc.y + 0.155, sc.z - 0.02), glass, axis='Y', seg=8)
    sb.cyl(0.04, 0.04, (sc.x + 0.09, sc.y + 0.135, sc.z + 0.06), m["Black"], axis='Y', seg=6)

    # ---- rotors -------------------------------------------------------------------------------------
    hub_z = 3.42
    rm = parts("Rotor_Main")
    rm.cyl(0.17, 0.15, (0, 0, hub_z), m["Steel"], seg=12)
    rm.cyl(0.21, 0.05, (0, 0, hub_z + 0.11), m["Charcoal"], seg=12, r2=0.10)             # beanie
    for j in range(4):
        a = math.pi / 4 + j * math.pi / 2               # parked as an X over the cabin (not a + along the boom)
        rm.box((0.15, 0.34, 0.08), (0, 0.24, hub_z), m["Charcoal"], bevel=0.012, xform=Matrix.Rotation(a, 4, 'Z'))
        rotor_blade(rm, m, 5.20, 0.31, a, hub_z, root=0.36, droop=0.16, tip_mat="PoliceWhite")
    parts("RotorBlur_Main").disc(0.4, 5.20, (0, 0, hub_z - 0.04), m["blur"], axis='Z', seg=28)
    rt = parts("Rotor_Tail")
    rt.cyl(0.10, 0.10, (-0.05, fc.y, fc.z), m["Charcoal"], axis='X', seg=10)
    rt.cyl(0.04, 0.06, (-0.13, fc.y, fc.z), m["Steel"], axis='X', seg=10, r2=0.10)       # spinner (small end outboard)
    for j in range(8):
        X = Matrix.Translation((-0.04, fc.y, fc.z)) @ Matrix.Rotation(j * math.pi / 4 + 0.2, 4, 'X')
        rt.box((0.014, 0.115, 0.37), (0, 0, 0.285), trim, rot=(0, 0, math.radians(28)), xform=X)

    # ---- objects --------------------------------------------------------------------------------------
    obs = parts.build(root)
    finish_rotating(obs["Rotor_Main"], (0, 0, hub_z))
    finish_rotating(obs["RotorBlur_Main"], (0, 0, hub_z))
    obs["RotorBlur_Main"].hide_render = True
    finish_rotating(obs["Rotor_Tail"], fc)
    G.set_origin(obs["Searchlight"], gim)
    obs["Searchlight"].rotation_euler = Euler((math.radians(-32), 0.0, 0.0), 'XYZ')
    G.empty("Searchlight_Beam", obs["Searchlight"], (0.0, 0.20, 0.0))
    G.set_origin(obs["SensorBall"], sc)
    center_origin(obs["Glass_Windshield"])
    center_origin(obs["Glass_Chin"])
    for L, s in (("L", -1), ("R", 1)):
        G.set_origin(obs["Door_F" + L], sh.pt(4, 4, s))
        center_origin(obs["Glass_" + L])
        reparent(obs["Glass_" + L], obs["Door_F" + L])
        center_origin(obs["Glass_R" + L])

    # ---- collision helpers ----------------------------------------------------------------------------
    hull("Col_Body", root, [
        (-1.24, 2.5, 0.0), (1.24, 2.5, 0.0), (-1.24, -2.05, 0.0), (1.24, -2.05, 0.0),
        (-0.46, 2.98, 0.86), (0.46, 2.98, 0.86), (0.0, 3.25, 1.08), (-0.46, 2.98, 1.36), (0.46, 2.98, 1.36),
        (-0.95, 1.2, 1.50), (0.95, 1.2, 1.50), (-0.95, -1.35, 1.50), (0.95, -1.35, 1.50),
        (-0.78, 1.85, 2.20), (0.78, 1.85, 2.20),
        (-0.82, 1.2, 2.34), (0.82, 1.2, 2.34), (-0.82, -1.35, 2.34), (0.82, -1.35, 2.34),
        (-0.52, 0.8, 2.82), (0.52, 0.8, 2.82), (-0.52, -1.5, 2.82), (0.52, -1.5, 2.82),
        (-0.34, -3.3, 1.45), (0.34, -3.3, 1.45), (-0.30, -3.3, 2.15), (0.30, -3.3, 2.15)], m["col"])
    hull("Col_Tail", root, [
        (-0.30, -3.1, 1.55), (0.30, -3.1, 1.55), (-0.30, -3.1, 2.25), (0.30, -3.1, 2.25),
        (-1.12, -4.65, 1.90), (1.12, -4.65, 1.90), (-1.12, -5.30, 2.05), (1.12, -5.30, 2.05),
        (-0.19, -6.0, 1.30), (0.19, -6.0, 1.30), (-0.19, -7.25, 1.30), (0.19, -7.25, 1.30),
        (-0.19, -5.9, 1.98), (0.19, -5.9, 1.98), (-0.19, -7.34, 1.98), (0.19, -7.34, 1.98),
        (-0.06, -6.92, 3.56), (0.06, -6.92, 3.56), (-0.06, -7.44, 3.56), (0.06, -7.44, 3.56),
        (-0.06, -6.48, 1.10), (0.06, -6.48, 1.10), (-0.06, -6.94, 1.10), (0.06, -6.94, 1.10)], m["col"])

    # ---- markers --------------------------------------------------------------------------------------
    hip = zf + 0.36
    G.empty("Seat_Driver", root, (-0.45, 0.72, hip))
    G.empty("Seat_Passenger_1", root, (0.45, 0.72, hip))
    G.empty("Seat_Gunner_L", root, (-0.46, -0.25, hip), rotation=(0, 0, math.pi / 2))
    G.empty("Seat_Gunner_R", root, (0.46, -0.25, hip), rotation=(0, 0, -math.pi / 2))
    G.empty("Seat_Passenger_2", root, (-0.46, -0.95, hip), rotation=(0, 0, math.pi / 2))
    G.empty("Seat_Passenger_3", root, (0.46, -0.95, hip), rotation=(0, 0, -math.pi / 2))
    G.empty("Exit_Driver", root, (-2.0, 0.75, 0.0))
    G.empty("Exit_Passenger_1", root, (2.0, 0.75, 0.0))
    G.empty("Exit_Gunner_L", root, (-2.0, -0.45, 0.0))
    G.empty("Exit_Gunner_R", root, (2.0, -0.45, 0.0))
    G.empty("Exit_Passenger_2", root, (-2.0, -1.10, 0.0))
    G.empty("Exit_Passenger_3", root, (2.0, -1.10, 0.0))
    G.empty("Engine", root, (0.0, -0.9, 2.70))
    G.empty("Exhaust_L", root, (-0.66, -2.30, 2.75))
    G.empty("Exhaust_R", root, (0.66, -2.30, 2.75))
    G.empty("Light_Head", root, (0.0, 3.16, 0.92))
    G.empty("Light_Head_L", root, (-0.10, 3.16, 0.92))
    G.empty("Light_Head_R", root, (0.10, 3.16, 0.92))
    G.empty("Light_Tail", root, (0.0, -7.42, 3.10))
    G.empty("Light_Tail_L", root, (-1.16, -5.01, 2.52))
    G.empty("Light_Tail_R", root, (1.16, -5.01, 2.52))
    G.empty("Light_Beacon", root, (0.0, -7.10, 3.66))
    G.empty("Siren", root, (0.0, 1.75, 0.62))
    return root


# ------------------------------------------------------------------------------------------------
# plane_prop - single-engine high-wing four-seater (strut-braced wing, tricycle gear with spats)
# ------------------------------------------------------------------------------------------------
def st_lerp(a, b, t):
    """Interpolate two wing stations (leading edge point, chord, thickness)."""
    return (Vector(a[0]).lerp(Vector(b[0]), t), a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def ring_pts(sh, i, rows=(1, 4, 5)):
    return [sh.pt(i, k, s) for k in rows for s in (1, -1)]


def hinge_frame(ob, sa, sb, u, axis='X'):
    """Give a control surface its hinge frame: origin mid hinge line, local X (or Z) along it."""
    a = hinge_pt(sa, u[0] if isinstance(u, (list, tuple)) else u)
    b = hinge_pt(sb, u[1] if isinstance(u, (list, tuple)) else u)
    d = b - a
    if axis == 'X':
        if d.x < 0:
            d = -d
        return reframe(ob, (a + b) / 2, x_axis=d)
    if d.z < 0:
        d = -d
    return reframe(ob, a if a.z < b.z else b, z_axis=d)


def build_plane_prop():
    m = mats()
    root = G.asset_root("plane_prop", PLANE_COL, G.slot("aircraft", SLOTS["plane_prop"]))
    parts = Parts()
    body = parts("Body")
    paint, paint2, glass, trim, interior = m["paint"], m["paint2"], m["glass"], m["trim"], m["interior"]

    def R(y, zk, zb, zr, zt, w):
        return ring_profile(y, zk, zb, zr, zt, w, wr=0.84, wk=0.62, cw=0.93, ck=0.30)

    st = [
        R(2.70, 1.05, 1.33, 1.44, 1.48, 0.26),      # 0 nose bowl
        R(2.56, 0.98, 1.36, 1.50, 1.55, 0.36),      # 1
        R(2.08, 0.84, 1.44, 1.60, 1.66, 0.50),      # 2
        R(1.38, 0.74, 1.50, 1.64, 1.70, 0.57),      # 3 firewall / windshield base
        R(0.58, 0.72, 1.50, 2.10, 2.17, 0.60),      # 4 windshield top / door front
        R(-0.47, 0.72, 1.50, 2.10, 2.17, 0.60),     # 5 door rear
        R(-1.37, 0.76, 1.50, 2.00, 2.08, 0.56),     # 6 rear side window end
        R(-2.22, 0.88, 1.50, 1.76, 1.84, 0.45),     # 7 rear window base
        R(-3.50, 1.12, 1.50, 1.64, 1.70, 0.24),     # 8
        R(-4.70, 1.36, 1.50, 1.58, 1.62, 0.07),     # 9 tail cone
    ]
    sh = Shell(st)

    def tag(i, k, side):
        L = 'L' if side < 0 else 'R'
        lin = interior if 3 <= i <= 6 else None
        if i == 3 and k >= 4:
            return ("Glass_Windshield", glass, None)
        if i == 4:
            if k == 4:
                return ("Glass_" + L, glass, None)
            if k in (2, 3):
                return ("Door_F" + L, paint2 if k == 3 else paint, interior)
        if i == 5 and k == 4:
            return ("Glass_R" + L, glass, None)
        if i == 6 and k >= 4:
            return ("Glass_Rear", glass, None)
        if i == 0:
            return ("Body", paint2, None)               # nose bowl
        if i in (1, 2) and k >= 5:
            return ("Body", m["Charcoal"], None)        # matt anti-glare panel ahead of the windshield
        return ("Body", paint2 if k == 3 else paint, lin)

    sh.emit(parts, tag)
    sh.cap(body, 0, trim, (0, 1, 0))                    # dark cooling inlet behind the spinner
    sh.cap(body, 9, paint, (0, -1, 0))
    cf = sh.center_at

    # window frames
    body.ribbon(sh.rows(3, 4, 7, 1) + sh.rows(3, 6, 4, -1), 0.06, trim, cf)        # windshield base
    body.ribbon(sh.rows(4, 5, 7, 1) + sh.rows(4, 6, 5, -1), 0.07, trim, cf)        # windshield header
    body.ribbon(sh.rows(7, 4, 7, 1) + sh.rows(7, 6, 4, -1), 0.06, trim, cf)        # rear window base
    body.ribbon(sh.rows(6, 5, 7, 1) + sh.rows(6, 6, 5, -1), 0.06, trim, cf)        # rear window header
    for s in (1, -1):
        body.ribbon(sh.line(5, 3, 4, s), 0.06, trim, cf)                           # A pillar
        for i in (4, 5, 6):
            body.ribbon(sh.rows(i, 4, 5, s), 0.07, trim, cf)                       # door posts
        body.ribbon(sh.line(4, 3, 7, s), 0.045, trim, cf)                          # belt line
        body.ribbon(sh.line(5, 4, 7, s), 0.05, trim, cf)                           # window header
        for i in (4, 5):                                                           # door shut lines
            body.ribbon(sh.rows(i, 2, 4, s), 0.022, trim, cf, out=0.006)
        body.ribbon(sh.line(2, 4, 5, s), 0.022, trim, cf, out=0.006)               # door sill
        body.box((0.03, 0.13, 0.035), (0.605 * s, -0.30, 1.42), m["chrome"])         # door handle
        body.box((0.03, 0.34, 0.10), (0.52 * s, 1.95, 1.14), trim, bevel=0.01)       # cowl gills
        body.tube((0.20 * s, 1.78, 0.82), (0.23 * s, 1.52, 0.66), 0.04, m["chrome"], seg=6)    # exhaust stubs
        body.cyl(0.045, 0.02, (0.18 * s, 2.705, 1.145), m["chrome"], axis='Y', seg=8)          # cowl landing lights
        body.cyl(0.034, 0.03, (0.18 * s, 2.712, 1.145), m["headlight"], axis='Y', seg=8)

    # ---- cabin ------------------------------------------------------------------------------------
    zf = 0.84
    body.poly([(-0.40, 1.38, zf), (0.40, 1.38, zf), (0.44, 0.58, zf), (0.44, -0.47, zf), (0.38, -1.37, zf),
               (-0.38, -1.37, zf), (-0.44, -0.47, zf), (-0.44, 0.58, zf)], interior, normal=(0, 0, 1))
    body.poly([(-0.38, -1.37, zf), (0.38, -1.37, zf), (0.42, -1.37, 1.02), (-0.42, -1.37, 1.02)], interior, normal=(0, 1, 0))
    body.poly([(-0.42, -1.37, 1.02), (0.42, -1.37, 1.02), (0.30, -2.22, 1.02), (-0.30, -2.22, 1.02)], interior, normal=(0, 0, 1))
    body.poly(sh.ring(7, 0.03), interior, normal=(0, 1, 0))                         # rear bulkhead
    body.poly(sh.ring(3, 0.03), interior, normal=(0, -1, 0))                        # firewall
    for sx in (-0.27, 0.27):
        seat(body, (sx, 0.02, zf), m, w=0.42)
        seat(body, (sx, -0.95, zf), m, w=0.42)
        body.tube((sx, 1.13, zf + 0.42), (sx, 0.80, zf + 0.42), 0.015, trim, seg=5)       # yokes
        body.box((0.22, 0.03, 0.10), (sx, 0.78, zf + 0.44), trim, bevel=0.01)
        body.box((0.30, 0.02, 0.18), (sx * 0.9, 1.125, zf + 0.50), m["Screen"])
    body.box((1.02, 0.14, 0.38), (0, 1.20, zf + 0.49), trim, bevel=0.02)                 # instrument panel
    body.box((1.06, 0.30, 0.04), (0, 1.26, zf + 0.70), trim)                             # glare shield

    # ---- wing --------------------------------------------------------------------------------------
    WT = ((0.0, 0.55, 2.25, 1.62, 0.21), (2.45, 0.55, 2.315, 1.62, 0.19), (5.05, 0.41, 2.385, 1.16, 0.13), (5.27, 0.32, 2.39, 0.92, 0.07))

    def ws(x):
        ax = abs(x)
        for a, b in zip(WT[:-1], WT[1:]):
            if a[0] <= ax <= b[0]:
                t = (ax - a[0]) / (b[0] - a[0])
                v = [a[j] + (b[j] - a[j]) * t for j in range(1, 5)]
                return ((x, v[0], v[1]), v[2], v[3])
        a = WT[-1]
        return ((x, a[1], a[2]), a[3], a[4])

    UH = 0.72
    body.wing([ws(-0.62), ws(0.62)], paint)
    for s in (1, -1):
        L = 'L' if s < 0 else 'R'
        body.wing([ws(0.62 * s), ws(2.45 * s)], paint, u1=UH)
        body.wing([ws(2.45 * s), ws(5.05 * s)], paint, u1=UH)
        body.wing([ws(5.05 * s), ws(5.27 * s)], paint2)
        parts("Flap_" + L).wing([ws(0.64 * s), ws(2.43 * s)], paint, u0=UH, tscale=0.9)
        parts("Aileron_" + L).wing([ws(2.47 * s), ws(5.03 * s)], paint, u0=UH, tscale=0.9)
        body.strut((0.58 * s, 0.12, 0.98), (2.30 * s, 0.02, 2.225), 0.13, 0.05, paint2)             # wing strut
        body.box((0.36, 0.06, 0.07), (3.2 * s, 0.505, 2.335), m["headlight"])                       # landing lights
        body.cyl(0.05, 0.02, (1.3 * s, 0.10, 2.39), trim, seg=8)                                   # fuel caps
        body.box((0.05, 0.16, 0.05), (5.29 * s, 0.02, 2.39), m["taillight"] if s < 0 else m["NavGreen"])
        body.box((0.04, 0.06, 0.04), (5.27 * s, -0.56, 2.39), m["White"])
    # registration (fictional): top of the right wing, underside of the left wing
    text_decal(body, "HB318", surf_frame(ws(2.75), ws(4.55), 0.30, 0.70, face=1), 0.40, trim, out=0.006)
    text_decal(body, "HB318", surf_frame(ws(-2.75), ws(-4.55), 0.30, 0.70, face=-1), 0.40, trim, out=0.006)
    # wing root fairing (closes the gap between cabin roof and wing)
    body.loft([[(-0.52, y, 2.085), (-0.52, y, 2.20), (0.52, y, 2.20), (0.52, y, 2.085), (0.0, y, 2.15)] for y in (0.66, -1.05)], paint)
    body.tube((-2.9, 0.66, 2.17), (-2.9, 0.34, 2.17), 0.012, m["Steel"], seg=5)                      # pitot
    body.box((0.02, 0.05, 0.08), (-2.9, 0.36, 2.21), m["Steel"])
    body.tube((0, -0.55, 2.34), (0, -0.85, 2.82), 0.010, trim, seg=5)                               # whip antenna
    body.box((0.02, 0.22, 0.14), (0, -1.0, 0.67), trim, bevel=0.006)                                # belly antenna

    # ---- tail --------------------------------------------------------------------------------------
    HY, UE = -4.12, 0.60

    def hs(x):
        ax = abs(x)
        c = 1.0 - 0.36 * ax / 1.72
        return ((x, HY + UE * c, 1.56), c, 0.10 - 0.03 * ax / 1.72)

    body.wing([hs(-1.72), hs(0.0), hs(1.72)], paint, u1=UE)
    el = parts("Elevator")
    for s in (1, -1):
        el.wing([hs(0.09 * s), hs(1.70 * s)], paint, u0=UE, tscale=0.9)
        body.wing([hs(1.72 * s), ((1.80 * s, HY + 0.30, 1.56), 0.56, 0.05)], paint2)                # stabiliser tips
    FR = ((0, -2.95, 1.55), 1.50, 0.12)
    FT = ((0, -4.02, 2.90), 0.66, 0.08)
    UR = 0.62
    body.wing([FR, FT], paint, u1=UR, up=(1, 0, 0))
    body.wing([FT, ((0, -4.12, 3.00), 0.50, 0.06)], paint2, up=(1, 0, 0))                           # fin cap
    RA, RB = st_lerp(FR, FT, 0.03), st_lerp(FR, FT, 0.985)
    parts("Rudder").wing([RA, RB], paint2, u0=UR, up=(1, 0, 0), tscale=0.9)
    body.wing([((0, -1.95, 1.62), 1.10, 0.05), ((0, -2.95, 2.02), 0.30, 0.04)], paint, up=(1, 0, 0))   # dorsal fillet
    body.cyl(0.045, 0.07, (0, -4.36, 3.03), m["taillight"], seg=6)                                  # beacon
    body.box((0.05, 0.06, 0.06), (0, -4.72, 1.49), m["White"])                                      # tail light

    # ---- landing gear ------------------------------------------------------------------------------
    nw = Vector((0.0, 1.75, 0.19))
    body.tube((0, 1.70, 0.84), (0, 1.74, 0.44), 0.035, m["Steel"], seg=6)
    body.tube((0, 1.74, 0.44), (0, 1.75, 0.30), 0.022, m["chrome"], seg=6)
    for dx in (-0.085, 0.085):
        body.box((0.02, 0.07, 0.20), (dx, 1.75, 0.28), m["Steel"])
    wheel_pant(body, nw, 0.19, 0.115, paint2)
    wheel(parts, "Wheel_Nose", nw, 0.19, 0.12, m)
    mains = {}
    for s in (1, -1):
        L = 'L' if s < 0 else 'R'
        wc = Vector((1.30 * s, -0.42, 0.22))
        mains[L] = wc
        body.strut((0.42 * s, -0.40, 0.80), (1.22 * s, -0.42, 0.27), 0.17, 0.05, paint)               # spring leg
        body.cyl(0.03, 0.16, (1.24 * s, -0.42, 0.22), m["Steel"], axis='X', seg=6)                  # axle
        body.box((0.16, 0.12, 0.025), (0.74 * s, -0.40, 0.60), m["Steel"], rot=(0, -0.60 * s, 0))   # step
        wheel_pant(body, wc, 0.22, 0.13, paint2)
        wheel(parts, "Wheel_" + L, wc, 0.22, 0.15, m)

    # ---- propeller ---------------------------------------------------------------------------------
    pc = Vector((0.0, 2.72, 1.27))
    pr = parts("Propeller")
    pr.lathe([(-0.03, 0.17), (0.10, 0.165), (0.27, 0.10), (0.37, 0.0)], m["chrome"], axis='Y', origin=pc, seg=10)

    def bsec(r, c, t, pitch):
        p = math.radians(pitch)
        d = Vector((math.cos(p), math.sin(p), 0.0))
        n = Vector((-math.sin(p), math.cos(p), 0.0))
        o = Vector((0.0, 0.0, r))
        return [o - d * (c / 2) - n * (t / 2), o + d * (c / 2) - n * (t / 2), o + d * (c / 2) + n * (t / 2), o - d * (c / 2) + n * (t / 2)]

    for a in (0.0, math.pi):
        X = Matrix.Translation(pc + Vector((0, 0.07, 0))) @ Matrix.Rotation(a, 4, 'Y')
        pr.loft([bsec(0.10, 0.08, 0.07, 60), bsec(0.32, 0.17, 0.04, 42), bsec(0.64, 0.16, 0.026, 26), bsec(0.86, 0.11, 0.018, 18)],
                m["Charcoal"], xform=X)
        pr.loft([bsec(0.86, 0.11, 0.018, 18), bsec(0.95, 0.07, 0.012, 16)], m["White"], xform=X)
    parts("PropBlur").disc(0.18, 0.95, pc + Vector((0, 0.07, 0)), m["blur"], axis='Y', seg=24)

    # ---- objects --------------------------------------------------------------------------------------
    obs = parts.build(root)
    finish_rotating(obs["Propeller"], pc)
    finish_rotating(obs["PropBlur"], pc)
    obs["PropBlur"].hide_render = True
    finish_rotating(obs["Wheel_Nose"], nw, smooth=40)
    for L, s in (("L", -1), ("R", 1)):
        finish_rotating(obs["Wheel_" + L], mains[L], smooth=40)
        hinge_frame(obs["Flap_" + L], ws(0.64 * s), ws(2.43 * s), UH)
        hinge_frame(obs["Aileron_" + L], ws(2.47 * s), ws(5.03 * s), UH)
        G.set_origin(obs["Door_F" + L], sh.pt(4, 4, s))
        center_origin(obs["Glass_" + L])
        reparent(obs["Glass_" + L], obs["Door_F" + L])
        center_origin(obs["Glass_R" + L])
    reframe(obs["Elevator"], (0, HY, 1.56), x_axis=(1, 0, 0))
    hinge_frame(obs["Rudder"], RA, RB, UR, axis='Z')
    center_origin(obs["Glass_Windshield"])
    center_origin(obs["Glass_Rear"])

    # ---- collision helpers ----------------------------------------------------------------------------
    hull("Col_Body", root, [Vector((0, 2.74, 1.27))] + ring_pts(sh, 1) + ring_pts(sh, 4) + ring_pts(sh, 5) + ring_pts(sh, 7)
         + ring_pts(sh, 9, rows=(1, 5)), m["col"])
    wpts = []
    for x in (-5.27, -2.45, 2.45, 5.27):
        (px, py, pz), c, t = ws(x)
        wpts += [(px, py, pz + t * 0.5), (px, py, pz - t * 0.5), (px, py - c, pz + 0.03), (px, py - c, pz - 0.03)]
    hull("Col_Wing", root, wpts, m["col"])
    hull("Col_Tail", root, [
        (-0.05, -4.02, 3.00), (0.05, -4.02, 3.00), (-0.05, -4.68, 3.00), (0.05, -4.68, 3.00),
        (-0.10, -2.95, 1.50), (0.10, -2.95, 1.50), (-0.10, -2.95, 1.78), (0.10, -2.95, 1.78),
        (-1.80, -3.74, 1.52), (1.80, -3.74, 1.52), (-1.80, -4.40, 1.52), (1.80, -4.40, 1.52),
        (-1.80, -3.74, 1.60), (1.80, -3.74, 1.60), (-1.80, -4.40, 1.60), (1.80, -4.40, 1.60),
        (-0.07, -4.72, 1.36), (0.07, -4.72, 1.36), (-0.07, -4.72, 1.62), (0.07, -4.72, 1.62)], m["col"])

    # ---- markers --------------------------------------------------------------------------------------
    hip = zf + 0.36
    G.empty("Seat_Driver", root, (-0.27, 0.02, hip))
    G.empty("Seat_Passenger_1", root, (0.27, 0.02, hip))
    G.empty("Seat_Passenger_2", root, (-0.27, -0.95, hip))
    G.empty("Seat_Passenger_3", root, (0.27, -0.95, hip))
    G.empty("Exit_Driver", root, (-1.9, 0.80, 0.0))
    G.empty("Exit_Passenger_1", root, (1.9, 0.80, 0.0))
    G.empty("Exit_Passenger_2", root, (-1.9, -0.35, 0.0))
    G.empty("Exit_Passenger_3", root, (1.9, -0.35, 0.0))
    G.empty("Engine", root, (0.0, 2.05, 1.30))
    G.empty("Exhaust", root, (0.23, 1.50, 0.64))
    G.empty("Light_Head", root, (0.0, 2.78, 1.02))
    G.empty("Light_Head_L", root, (-0.18, 2.75, 1.145))
    G.empty("Light_Head_R", root, (0.18, 2.75, 1.145))
    G.empty("Light_Tail", root, (0.0, -4.76, 1.49))
    G.empty("Light_Tail_L", root, (-1.80, -4.42, 1.56))
    G.empty("Light_Tail_R", root, (1.80, -4.42, 1.56))
    G.empty("Light_Beacon", root, (0.0, -4.36, 3.09))
    G.empty("Light_Nav_L", root, (-5.30, 0.02, 2.39))
    G.empty("Light_Nav_R", root, (5.30, 0.02, 2.39))
    return root


# ------------------------------------------------------------------------------------------------
# plane_jet - small twin-engine sport jet (tandem bubble canopy, swept wing with winglets,
# aft podded engines, T-tail)
# ------------------------------------------------------------------------------------------------
def build_plane_jet():
    m = mats()
    root = G.asset_root("plane_jet", PLANE_COL, G.slot("aircraft", SLOTS["plane_jet"]))
    parts = Parts()
    body = parts("Body")
    paint, paint2, glass, trim, interior = m["paint"], m["paint2"], m["glass"], m["trim"], m["interior"]

    def J(y, zk, zb, zr, zt, w, wr=0.80):
        return ring_profile(y, zk, zb, zr, zt, w, wr=wr, stripe=0.12, wk=0.50, cw=0.87, ck=0.42, sw=0.98, shw=0.55)

    st = [
        J(5.75, 1.17, 1.20, 1.23, 1.25, 0.05),            # 0 nose tip
        J(5.15, 0.99, 1.22, 1.38, 1.43, 0.25),            # 1 radome end
        J(4.35, 0.85, 1.27, 1.55, 1.62, 0.45),            # 2 windscreen base
        J(3.55, 0.79, 1.32, 1.98, 2.10, 0.56, wr=0.72),   # 3 canopy bow
        J(2.60, 0.77, 1.34, 2.12, 2.25, 0.60, wr=0.72),   # 4 canopy mid
        J(1.50, 0.77, 1.36, 2.02, 2.14, 0.62, wr=0.72),   # 5 canopy rear
        J(0.55, 0.77, 1.38, 1.74, 1.82, 0.64),            # 6 canopy fairing end
        J(-1.20, 0.80, 1.40, 1.70, 1.78, 0.62),           # 7
        J(-3.00, 0.96, 1.42, 1.66, 1.72, 0.48),           # 8
        J(-4.30, 1.18, 1.44, 1.58, 1.62, 0.22),           # 9
        J(-4.80, 1.32, 1.44, 1.50, 1.52, 0.06),           # 10 tail cone
    ]
    sh = Shell(st)

    def tag(i, k, side):
        lin = interior if 2 <= i <= 5 else None
        if i == 2 and k >= 4:
            return ("Glass_Windshield", glass, None)
        if i in (3, 4, 5) and k >= 4:
            return ("Glass_Canopy", glass, None)
        if i == 0:
            return ("Body", m["Charcoal"], None)        # radome
        return ("Body", paint2 if k <= 2 else paint, lin)

    sh.emit(parts, tag, liner_t=0.05)
    sh.cap(body, 0, m["Charcoal"], (0, 1, 0))
    sh.cap(body, 10, paint, (0, -1, 0))
    cf = sh.center_at

    # windscreen frame (fixed) and canopy frame (moves with the canopy)
    body.ribbon(sh.rows(2, 4, 7, 1) + sh.rows(2, 6, 4, -1), 0.06, trim, cf)
    can = parts("Canopy")
    for i in (3, 4, 6):
        can.ribbon(sh.rows(i, 4, 7, 1) + sh.rows(i, 6, 4, -1), 0.07, trim, cf)
    for s in (1, -1):
        body.ribbon(sh.line(4, 2, 3, s), 0.05, trim, cf)
        can.ribbon(sh.line(4, 3, 6, s), 0.06, trim, cf)
        body.ribbon(sh.line(3, 1, 10, s), 0.035, m["BadgeGold"], cf)               # pin stripe on the colour break
    body.tube((0, 5.74, 1.21), (0, 5.98, 1.21), 0.012, m["Steel"], seg=5)          # nose probe

    # ---- cockpit -----------------------------------------------------------------------------------
    zf = 0.92
    body.poly([(-0.26, 4.35, zf), (0.26, 4.35, zf), (0.37, 3.55, zf), (0.38, 0.55, zf), (-0.38, 0.55, zf), (-0.37, 3.55, zf)],
              interior, normal=(0, 0, 1))
    body.poly(sh.ring(6, 0.05), interior, normal=(0, 1, 0))
    body.poly(sh.ring(2, 0.05), interior, normal=(0, -1, 0))
    seat(body, (0, 3.05, zf), m, w=0.50, back_h=0.66)
    seat(body, (0, 1.80, zf), m, w=0.50, back_h=0.66)
    body.box((0.74, 0.36, 0.20), (0, 3.93, 1.37), trim, bevel=0.03)                 # glare shield
    body.box((0.66, 0.05, 0.36), (0, 3.76, 1.21), trim)                             # front panel
    for sx in (-0.17, 0.17):
        body.box((0.27, 0.02, 0.17), (sx, 3.73, 1.25), m["Screen"])
    body.box((0.62, 0.10, 0.34), (0, 2.52, 1.22), trim, bevel=0.02)                 # rear panel
    body.box((0.40, 0.02, 0.18), (0, 2.465, 1.26), m["Screen"])
    for y in (3.45, 2.20):
        body.tube((0, y, zf), (0, y - 0.06, zf + 0.34), 0.018, trim, seg=5)         # sticks
        body.box((0.04, 0.05, 0.10), (0, y - 0.07, zf + 0.38), trim)

    # ---- wing ---------------------------------------------------------------------------------------
    def wj(x):
        t = abs(x) / 4.2
        return ((x, 1.75 - 2.60 * t, 1.00 + 0.19 * t), 2.85 - 1.80 * t, 0.22 - 0.13 * t)

    UJ = 0.75
    for s in (1, -1):
        L = 'L' if s < 0 else 'R'
        body.wing([wj(0.50 * s), wj(0.72 * s)], paint)
        body.wing([wj(0.72 * s), wj(2.30 * s)], paint, u1=UJ)
        body.wing([wj(2.30 * s), wj(4.00 * s)], paint, u1=UJ)
        body.wing([wj(4.00 * s), wj(4.20 * s)], paint)
        body.wing([((4.20 * s, -1.10, 1.19), 0.80, 0.07), ((4.37 * s, -1.80, 1.92), 0.36, 0.045)], paint2, up=(1, 0, 0))   # winglet
        parts("Flap_" + L).wing([wj(0.74 * s), wj(2.28 * s)], paint, u0=UJ, tscale=0.9)
        parts("Aileron_" + L).wing([wj(2.32 * s), wj(3.98 * s)], paint, u0=UJ, tscale=0.9)
        body.box((0.04, 0.12, 0.05), (4.39 * s, -1.90, 1.93), m["taillight"] if s < 0 else m["NavGreen"])
        # wing / body fairing
        body.loft([[(0.42 * s, 1.95, 0.84), (0.60 * s, 1.95, 0.98), (0.42 * s, 1.95, 1.10)],
                   [(0.46 * s, 0.4, 0.80), (0.74 * s, 0.4, 0.99), (0.46 * s, 0.4, 1.22)],
                   [(0.46 * s, -1.0, 0.84), (0.72 * s, -1.0, 1.00), (0.46 * s, -1.0, 1.16)],
                   [(0.40 * s, -1.7, 0.92), (0.52 * s, -1.7, 1.02), (0.40 * s, -1.7, 1.10)]], paint2)

    # ---- T-tail -------------------------------------------------------------------------------------
    FR = ((0, -2.20, 1.55), 2.30, 0.16)
    FT = ((0, -3.75, 3.25), 1.45, 0.11)
    UR = 0.68
    body.wing([FR, FT], paint, u1=UR, up=(1, 0, 0))
    RA, RB = st_lerp(FR, FT, 0.10), st_lerp(FR, FT, 0.90)
    parts("Rudder").wing([RA, RB], paint2, u0=UR, up=(1, 0, 0), tscale=0.9)
    body.wing([st_lerp(FR, FT, 0.0), st_lerp(FR, FT, 0.10)], paint, u0=UR, up=(1, 0, 0), tscale=0.9)      # fixed fin base
    body.wing([st_lerp(FR, FT, 0.90), st_lerp(FR, FT, 1.0)], paint, u0=UR, up=(1, 0, 0), tscale=0.9)
    body.lathe([(-3.42, 0.0), (-3.72, 0.09), (-4.95, 0.105), (-5.40, 0.0)], paint2, axis='Y', origin=(0, 0, 3.30), seg=8, phase=0.5)
    for s in (1, -1):                                                                                    # registration on the fin
        text_decal(body, "HB900", surf_frame(st_lerp(FR, FT, 0.13), st_lerp(FR, FT, 0.34), 0.30, 0.66, face=s, up=(1, 0, 0),
                                              want_up=(0, 0, 1), right=(0, s, 0)), 0.165, paint2, out=0.006)
    text_decal(body, "HB900", surf_frame(wj(2.35), wj(3.95), 0.32, 0.72, face=1), 0.32, paint2, out=0.006)   # right wing, top
    HYJ = -4.80

    def hj(x):
        t = abs(x) / 1.80
        c = 1.50 - 0.90 * t
        u = 0.76 - 0.20 * t
        return ((x, HYJ + u * c, 3.30), c, 0.10 - 0.04 * t), u

    hsts = [hj(-1.80), hj(0.0), hj(1.80)]
    body.wing([h[0] for h in hsts], paint, u1=[h[1] for h in hsts])
    el = parts("Elevator")
    for s in (1, -1):
        a, b = hj(0.12 * s), hj(1.78 * s)
        el.wing([a[0], b[0]], paint2, u0=[a[1], b[1]], tscale=0.9)
    body.wing([((0, -3.20, 1.08), 0.95, 0.05), ((0, -3.62, 0.80), 0.42, 0.04)], paint2, up=(1, 0, 0))     # ventral strake
    body.box((0.02, 0.26, 0.16), (0, -0.60, 1.86), trim, bevel=0.006)                                    # blade antenna
    body.cyl(0.045, 0.06, (0, -1.70, 1.80), m["taillight"], seg=6)                                       # beacon
    body.box((0.05, 0.06, 0.05), (0, -5.40, 3.30), m["White"])                                           # tail light

    # ---- engines --------------------------------------------------------------------------------------
    for s in (1, -1):
        nc = Vector((1.06 * s, 0.0, 1.62))
        body.lathe([(-1.50, 0.365), (-2.90, 0.365), (-3.45, 0.30), (-3.72, 0.235)], paint, axis='Y', origin=nc, seg=12, caps=(False, False))
        body.lathe([(-1.42, 0.245), (-1.30, 0.275), (-1.32, 0.335), (-1.50, 0.365)], m["chrome"], axis='Y', origin=nc, seg=12, caps=(False, False))
        body.disc(0.0, 0.245, nc + Vector((0, -1.42, 0)), m["Black"], axis='Y', seg=12)                 # fan face
        body.lathe([(-1.42, 0.10), (-1.28, 0.0)], m["Steel"], axis='Y', origin=nc, seg=8, caps=(True, False))   # spinner
        for j in range(6):                                                                               # fan blades
            a = j * math.pi / 3
            body.poly([nc + Vector((0.05 * math.cos(a), -1.405, 0.05 * math.sin(a))),
                       nc + Vector((0.235 * math.cos(a + 0.12), -1.405, 0.235 * math.sin(a + 0.12))),
                       nc + Vector((0.235 * math.cos(a + 0.42), -1.405, 0.235 * math.sin(a + 0.42)))], m["SteelDark"], normal=(0, 1, 0))
        body.lathe([(-3.72, 0.235), (-3.95, 0.19)], m["SteelDark"], axis='Y', origin=nc, seg=12, caps=(False, False))   # nozzle
        body.disc(0.0, 0.19, nc + Vector((0, -3.86, 0)), m["Black"], axis='Y', seg=12, flip=True)
        body.wing([((0.40 * s, -1.85, 1.60), 1.45, 0.14), ((0.80 * s, -1.95, 1.62), 1.30, 0.12)], paint)           # pylon
        body.ribbon([nc + Vector((0.37 * math.cos(a) , -1.75, 0.37 * math.sin(a))) for a in [j * math.pi / 6 for j in range(13)]],
                    0.10, paint2, lambda p, c=nc: Vector((c.x, p.y, c.z)), out=0.004)                    # coloured cowl band

    # ---- landing gear ------------------------------------------------------------------------------
    # oleo legs with fork / torque links / braces, doors hanging from dark wheel wells (the first
    # version had bare 4 cm sticks, which read as a placeholder under an otherwise detailed airframe)
    steel, chrome = m["Steel"], m["chrome"]
    nw = Vector((0.0, 4.06, 0.19))
    body.box((0.30, 0.86, 0.024), (0, 3.93, 0.814), trim, rot=(math.radians(4.3), 0, 0))               # nose wheel well
    body.tube((0, 3.98, 0.84), (0, 4.04, 0.50), 0.055, steel, seg=8)                                   # oleo cylinder
    body.tube((0, 4.04, 0.50), (0, 4.06, 0.40), 0.034, chrome, seg=8)                                  # piston
    body.box((0.25, 0.10, 0.05), (0, 4.06, 0.415), steel, bevel=0.012)                                 # fork crown
    body.cyl(0.02, 0.24, nw, steel, axis='X', seg=6)                                                   # axle
    body.box((0.20, 0.06, 0.11), (0, 4.085, 0.56), trim, bevel=0.012)                                  # landing light bracket
    body.tube((0, 3.99, 0.66), (0, 3.90, 0.57), 0.014, steel, seg=5)                                   # torque links
    body.tube((0, 3.90, 0.57), (0, 4.00, 0.44), 0.014, steel, seg=5)
    body.tube((0, 3.60, 0.80), (0, 4.01, 0.60), 0.022, steel, seg=6)                                   # drag brace
    for dx in (-0.095, 0.095):
        sg = 1 if dx > 0 else -1
        body.box((0.028, 0.085, 0.24), (dx, 4.06, 0.295), steel, bevel=0.008)                          # fork legs
        body.box((0.02, 0.72, 0.21), (0.166 * sg, 3.93, 0.715), paint2, rot=(0, -0.30 * sg, 0))        # gear doors
        body.cyl(0.042, 0.05, (0.068 * sg, 4.115, 0.56), m["headlight"], axis='Y', seg=8)              # landing lights
    wheel(parts, "Wheel_Nose", nw, 0.19, 0.12, m)

    def under(x, u, drop=0.006):
        """Point on the flat lower wing facet between the 30 % chord line and the flap hinge."""
        (lx, ly, lz), c, t = wj(x)
        ua, ub = 0.40 * UJ, UJ
        h = af_h(ua) + (af_h(ub) - af_h(ua)) * (u - ua) / (ub - ua)
        return Vector((lx, ly - u * c, lz - h * t - drop))

    mains = {}
    for s in (1, -1):
        L = 'L' if s < 0 else 'R'
        wc = Vector((1.30 * s, -0.55, 0.24))
        mains[L] = wc
        body.poly([under(0.78 * s, 0.50), under(1.36 * s, 0.50), under(1.36 * s, 0.74), under(0.78 * s, 0.74)],
                  trim, normal=(0, 0, -1))                                                             # wheel well
        body.tube((1.19 * s, -0.50, 1.01), (1.19 * s, -0.55, 0.52), 0.06, steel, seg=8)                # oleo cylinder
        body.tube((1.19 * s, -0.55, 0.52), (1.19 * s, -0.55, 0.22), 0.036, chrome, seg=8)              # piston
        body.cyl(0.032, 0.16, (1.25 * s, -0.55, 0.24), steel, axis='X', seg=6)                         # axle
        body.cyl(0.11, 0.03, (1.205 * s, -0.55, 0.24), steel, axis='X', seg=10)                        # brake disc
        body.tube((1.19 * s, -0.61, 0.66), (1.19 * s, -0.72, 0.52), 0.015, steel, seg=5)               # torque links
        body.tube((1.19 * s, -0.72, 0.52), (1.19 * s, -0.60, 0.36), 0.015, steel, seg=5)
        body.tube((0.92 * s, -0.45, 0.99), (1.16 * s, -0.53, 0.66), 0.024, steel, seg=6)               # side brace
        body.box((0.022, 0.36, 0.50), (1.262 * s, -0.50, 0.775), paint2, bevel=0.008)                  # leg door
        body.box((0.02, 0.56, 0.30), (0.80 * s, -0.42, 0.84), paint2, rot=(0, 0.35 * s, 0))            # inner door
        wheel(parts, "Wheel_" + L, wc, 0.24, 0.16, m)

    # ---- objects --------------------------------------------------------------------------------------
    obs = parts.build(root)
    finish_rotating(obs["Wheel_Nose"], nw, smooth=40)
    for L, s in (("L", -1), ("R", 1)):
        finish_rotating(obs["Wheel_" + L], mains[L], smooth=40)
        hinge_frame(obs["Flap_" + L], wj(0.74 * s), wj(2.28 * s), UJ)
        hinge_frame(obs["Aileron_" + L], wj(2.32 * s), wj(3.98 * s), UJ)
    reframe(obs["Elevator"], (0, HYJ, 3.30), x_axis=(1, 0, 0))
    hinge_frame(obs["Rudder"], RA, RB, UR, axis='Z')
    center_origin(obs["Glass_Windshield"])
    hinge = Vector((0.0, 0.55, 1.38))
    G.set_origin(obs["Canopy"], hinge)
    center_origin(obs["Glass_Canopy"])
    reparent(obs["Glass_Canopy"], obs["Canopy"])

    # ---- collision helpers ----------------------------------------------------------------------------
    hull("Col_Body", root, [Vector((0, 5.75, 1.21))] + ring_pts(sh, 1) + ring_pts(sh, 3) + ring_pts(sh, 5) + ring_pts(sh, 7)
         + ring_pts(sh, 9, rows=(1, 5)) + [Vector((0, 2.6, 2.25)), Vector((0, -4.8, 1.42))], m["col"])
    wpts = []
    for x in (-4.2, -0.5, 0.5, 4.2):
        (px, py, pz), c, t = wj(x)
        wpts += [(px, py, pz + t * 0.5), (px, py, pz - t * 0.5), (px, py - c, pz + 0.03), (px, py - c, pz - 0.03)]
    wpts += [(-4.37, -1.80, 1.92), (4.37, -1.80, 1.92), (-4.37, -2.16, 1.92), (4.37, -2.16, 1.92)]
    hull("Col_Wing", root, wpts, m["col"])
    tpts = [(-1.80, -4.46, 3.26), (1.80, -4.46, 3.26), (-1.80, -5.06, 3.26), (1.80, -5.06, 3.26),
            (-1.80, -4.46, 3.34), (1.80, -4.46, 3.34), (-1.80, -5.06, 3.34), (1.80, -5.06, 3.34),
            (0.0, -3.42, 3.30), (0.0, -5.40, 3.30), (-0.08, -2.20, 1.60), (0.08, -2.20, 1.60)]
    for s in (1, -1):
        for y in (-1.32, -3.95):
            r = 0.36 if y > -2 else 0.20
            tpts += [((1.06 + r) * s, y, 1.62), ((1.06 - r) * s, y, 1.62 - r), ((1.06 - r) * s, y, 1.62 + r), ((1.06 + r * 0.7) * s, y, 1.62 - r * 0.7), ((1.06 + r * 0.7) * s, y, 1.62 + r * 0.7)]
    hull("Col_Tail", root, tpts, m["col"])

    # ---- markers --------------------------------------------------------------------------------------
    hip = zf + 0.36
    G.empty("Seat_Driver", root, (0.0, 3.05, hip))
    G.empty("Seat_Passenger_1", root, (0.0, 1.80, hip))
    G.empty("Exit_Driver", root, (-1.5, 3.3, 0.0))
    G.empty("Exit_Passenger_1", root, (-1.5, 2.3, 0.0))
    G.empty("Engine", root, (0.0, -2.6, 1.62))
    G.empty("Exhaust_L", root, (-1.06, -4.0, 1.62))
    G.empty("Exhaust_R", root, (1.06, -4.0, 1.62))
    G.empty("Light_Head", root, (0.0, 4.16, 0.56))
    G.empty("Light_Head_L", root, (-0.07, 4.16, 0.56))
    G.empty("Light_Head_R", root, (0.07, 4.16, 0.56))
    G.empty("Light_Tail", root, (0.0, -5.44, 3.30))
    G.empty("Light_Tail_L", root, (-1.80, -5.08, 3.30))
    G.empty("Light_Tail_R", root, (1.80, -5.08, 3.30))
    G.empty("Light_Beacon", root, (0.0, -1.70, 1.86))
    G.empty("Light_Nav_L", root, (-4.40, -1.90, 1.93))
    G.empty("Light_Nav_R", root, (4.40, -1.90, 1.93))
    return root


# ------------------------------------------------------------------------------------------------
# registry / QA / export
# ------------------------------------------------------------------------------------------------
BUILDERS = {}
for _n in ("heli_civil", "heli_police", "plane_prop", "plane_jet"):
    _f = globals().get("build_" + _n)
    if _f is not None:
        BUILDERS[_n] = _f


def build(name):
    G.object_mode()
    root = BUILDERS[name]()
    bpy.context.view_layer.update()
    return root


def build_all():
    return [build(n) for n in BUILDERS]


def preview(name, suffix="", views=VIEWS, helpers=False, res=512, paint=True, exclude=(), cull=True):
    """Contact sheet -> qa/blender_previews/<name><suffix>.png (helpers hidden unless asked;
    `exclude` = base names of parts to hide as well, e.g. the big rotor for close-ups).
    cull=True renders with backface culling, so a flipped face shows up as a hole (worst case of
    what the game engine will draw)."""
    root = bpy.data.objects[name]
    changed = []
    for o in root.children_recursive:
        if o.type != 'MESH':
            continue
        want_hidden = (helper_object(o) and not helpers) or base_name(o) in exclude
        if o.hide_render != want_hidden:
            changed.append((o, o.hide_render))
            o.hide_render = want_hidden
    shading = bpy.context.scene.display.shading
    old_cull = shading.show_backface_culling
    try:
        shading.show_backface_culling = bool(cull)
        pr, se = DEFAULT_PAINT.get(name, (None, None)) if paint else (None, None)
        with Paint(pr, se):
            return G.preview(name, name + suffix, views=views, res=res)
    finally:
        shading.show_backface_culling = old_cull
        for o, h in changed:
            o.hide_render = h


_SHEET_DIRS = dict(G._VIEW_DIRS)
_SHEET_DIRS.update({"low_rear": (-0.6, -1.0, 0.15), "under": (0.55, 0.8, -0.6), "high_front": (0.45, 1.0, 0.9),
                    "side_l": (-1.0, 0.0, 0.12), "low_side": (1.0, 0.25, 0.06)})


def sheet(name, out_name, views=("three_quarter", "rear_quarter", "side", "front"), res=640, margin=1.06,
          exclude=(), helpers=False, cull=True, center=None, radius=None, cols=2, paint=True,
          background=(0.20, 0.22, 0.26)):
    """Tight QA contact sheet of ONE aircraft (critic tool): every tile is framed on the projected
    extents of the visible parts for that view (G.preview frames on the bounding sphere, which makes
    a 10 m rotor shrink the airframe to a quarter of the tile). center / radius (asset-local metres)
    frame a detail instead. Only the asset is rendered; everything is restored afterwards."""
    import os
    import numpy as np
    G.object_mode()
    scene = bpy.context.scene
    root = bpy.data.objects[name]
    mine = set(G.children_of(root))
    bpy.context.view_layer.update()
    changed = []
    for o in scene.objects:
        if o in mine:
            want_hidden = o.type == 'MESH' and ((helper_object(o) and not helpers) or base_name(o) in exclude)
        else:
            want_hidden = True
        if o.hide_render != want_hidden:
            changed.append((o, o.hide_render))
            o.hide_render = want_hidden
    pts = []
    for o in mine:
        if o.type == 'MESH' and not o.hide_render:
            mw = o.matrix_world
            pts.extend(mw @ v.co for v in o.data.vertices)
    r = scene.render
    sh = scene.display.shading
    saved = {"engine": r.engine, "rx": r.resolution_x, "ry": r.resolution_y, "pct": r.resolution_percentage,
             "path": r.filepath, "fmt": r.image_settings.file_format, "cam": scene.camera, "transparent": r.film_transparent}
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type",
              "background_color", "cavity_type", "show_backface_culling"):
        try:
            v = getattr(sh, k)
            saved_sh[k] = tuple(v) if k == "background_color" else v
        except Exception:
            pass
    cam_data = bpy.data.cameras.new("_air_sheet_cam")
    cam = bpy.data.objects.new("_air_sheet_cam", cam_data)
    scene.collection.objects.link(cam)
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    tmp_paths = []
    pr, se = DEFAULT_PAINT.get(name, (None, None)) if paint else (None, None)
    try:
        r.engine = 'BLENDER_WORKBENCH'
        for k, v in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                     ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                     ("background_color", background), ("show_backface_culling", bool(cull))):
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        r.resolution_x = res
        r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        cam_data.type = 'ORTHO'
        cam_data.clip_start = 0.01
        cam_data.clip_end = 400.0
        tiles = []
        with Paint(pr, se):
            for i, vname in enumerate(views):
                det_c, det_r = center, radius
                if isinstance(vname, (list, tuple)) and len(vname) == 3 and isinstance(vname[0], str):
                    vname, det_c, det_r = vname          # ("view", (cx, cy, cz), radius) = detail tile
                d = Vector(_SHEET_DIRS[vname] if isinstance(vname, str) else vname).normalized()
                q = (-d).to_track_quat('-Z', 'Y')
                R = q.to_matrix()
                cx, cy = R.col[0], R.col[1]
                if det_c is not None:
                    c = root.matrix_world @ Vector(det_c)
                    scale = 2.0 * (det_r or 1.0)
                else:
                    xs = [p.dot(cx) for p in pts]
                    ys = [p.dot(cy) for p in pts]
                    ds = [p.dot(d) for p in pts]
                    c = cx * ((min(xs) + max(xs)) / 2) + cy * ((min(ys) + max(ys)) / 2) + d * ((min(ds) + max(ds)) / 2)
                    scale = max(max(xs) - min(xs), max(ys) - min(ys)) * margin
                cam_data.ortho_scale = scale
                cam.location = c + d * 120.0
                cam.rotation_euler = q.to_euler()
                tmp = os.path.join(G.PREVIEW_DIR, "_tmp_sheet_%s_%d.png" % (re.sub(r'[^A-Za-z0-9_]', '_', out_name), i))
                r.filepath = tmp
                bpy.ops.render.render(write_still=True)
                tmp_paths.append(tmp)
                img = bpy.data.images.load(tmp, check_existing=False)
                arr = np.empty(res * res * 4, dtype=np.float32)
                img.pixels.foreach_get(arr)
                tiles.append(arr.reshape(res, res, 4))
                bpy.data.images.remove(img)
        cols = min(cols, len(tiles))
        rows = (len(tiles) + cols - 1) // cols
        big = np.zeros((rows * res, cols * res, 4), dtype=np.float32)
        big[..., 0:3] = background
        big[..., 3] = 1.0
        for i, t in enumerate(tiles):
            rr = rows - 1 - (i // cols)
            cc = i % cols
            big[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res, :] = t
        out = bpy.data.images.new("_air_sheet", cols * res, rows * res, alpha=False)
        out.pixels.foreach_set(big.ravel())
        out.filepath_raw = out_path
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
    finally:
        for o, h in changed:
            try:
                o.hide_render = h
            except Exception:
                pass
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
        scene.camera = saved["cam"]
        try:
            r.engine = saved["engine"]
        except Exception:
            pass
        r.resolution_x = saved["rx"]
        r.resolution_y = saved["ry"]
        r.resolution_percentage = saved["pct"]
        r.filepath = saved["path"]
        r.film_transparent = saved["transparent"]
        try:
            r.image_settings.file_format = saved["fmt"]
        except Exception:
            pass
        for k, v in saved_sh.items():
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        for t in tmp_paths:
            try:
                os.remove(t)
            except Exception:
                pass
    print("SHEET_SAVED:", out_path)
    return out_path


def report(name):
    """Print the part list of an asset (clean names, type, tris, local origin)."""
    root = bpy.data.objects[name]
    rows = []
    for o in sorted(root.children_recursive, key=lambda x: x.name):
        tris = 0
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris = len(o.data.loop_triangles)
        rows.append((base_name(o), o.type, tris, tuple(round(c, 3) for c in o.location), base_name(o.parent)))
    for r in rows:
        print("  %-18s %-5s tris=%-5d origin=%s parent=%s" % r)
    return rows


def fix_glb_names(path):
    """Blender makes object names unique per FILE ('Body.001'); the contract needs the clean names
    inside each GLB, so the numeric suffixes are stripped in the GLB's JSON chunk after export."""
    with open(path, 'rb') as f:
        data = f.read()
    magic, version, _length = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF':
        raise RuntimeError("not a GLB: " + path)
    clen, ctype = struct.unpack_from('<I4s', data, 12)
    if ctype != b'JSON':
        raise RuntimeError("unexpected first chunk in " + path)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    rest = data[20 + clen:]
    n = 0
    for key in ("nodes", "meshes"):
        for it in js.get(key, []):
            nm = it.get("name")
            if nm:
                new = _SUFFIX.sub("", nm)
                if new != nm:
                    it["name"] = new
                    n += 1
    names = [it.get("name") for it in js.get("nodes", [])]
    out = json.dumps(js, separators=(',', ':')).encode('utf-8')
    out += b' ' * ((4 - len(out) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', version, 12 + 8 + len(out) + len(rest)))
        f.write(struct.pack('<I4s', len(out), b'JSON'))
        f.write(out)
        f.write(rest)
    dup = sorted(set(x for x in names if names.count(x) > 1))
    print("GLB names fixed: %d renamed, %d nodes, duplicates=%s" % (n, len(names), dup))
    return names


def export(name):
    """Validate + export to models/vehicles/<name>.glb with the default paint baked in."""
    res = G.validate(name, max_tris=7000)
    pr, se = DEFAULT_PAINT.get(name, (None, None))
    with Paint(pr, se):
        path = G.export_glb(name, "vehicles/%s.glb" % name)
    names = fix_glb_names(path)
    return res, path, names
