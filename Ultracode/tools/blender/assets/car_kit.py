"""car_kit - parametric 'Sunlit Low-Poly' road-vehicle toolkit for Halcyon Bay (Blender 5.2, via MCP).

Produces the complete vehicle node contract of docs/ARCHITECTURE.md section 8.2 from ONE readable
parameter dict.  Full guide, lessons learned and tri counts: docs/VEHICLE_KIT.md.
Reference asset built with it: tools/blender/assets/cars_sedan.py.  Starter parameter sets for other
silhouettes (hatchback, SUV, wedge sports car, pickup, van): tools/blender/assets/car_kit_examples.py.

QUICK START (inside an execute_blender_code call, after the standard gta_bl header)
-----------------------------------------------------------------------------------
    A = P + r"\\assets"
    if A not in sys.path: sys.path.append(A)
    import car_kit as K; importlib.reload(K)

    params = dict(K.DEFAULTS)              # DEFAULTS = a 4.6 m family sedan
    params.update(name="compact", ...)     # override what you need (PARAMETER REFERENCE below)
    car = K.Car(params, G.slot("cars", 1)) # creates the root Empty (rebuilds an old one of that name)
    car.build()                            # everything from the contract, incl. mods / LOD / collision
    # optional own geometry BEFORE finish():  car.body.box(...), car.body.loft(...), car.body.sweep(...)
    car.finish()                           # creates the Blender objects + markers, hides helper meshes
    car.report(); K.check_contract(car.name)
    G.preview(car.name, "veh_compact", views=("three_quarter", "rear_quarter", "side", "front", "top"))
    K.preview_mods(car.name, "veh_compact_mods")       # same, with every Mod_* visible
    G.validate(car.name, max_tris=9000)
    K.export_glb(car.name, "vehicles/compact.glb")     # NOT G.export_glb - see NAMES below
    G.save()

    (short form:  car = K.build_car(params, G.slot("cars", 1), extras=my_function) )

NAMES - READ THIS
-----------------
Blender object names are global, so twenty vehicles cannot each own an object called "Body".  The kit
therefore names every part '<asset>:<part>' in the .blend ("sedan:Body", "sedan:Wheel_FL" ...) and
`K.export_glb()` rewrites the GLB so that Godot receives the clean contract names (Body, Wheel_FL).
Always export through K.export_glb().  Use car.n("Part") / K.short_name(ob) to convert.

`car.build()` is just the list of steps below - copy it and leave steps out / add your own when your
vehicle needs something different (pickup bed, van box, light bar ...):

    car.skin()            lower body shell from the station loft (fenders, quarters, rocker, underbody,
                          end caps, wheel-arch lips, rub strip).  Holes are left for doors / hood /
                          trunk / cabin.
    car.greenhouse()      A/B/C pillars + roof slab (into Body) and the 4 glass pane objects
    car.interior()        tub, sills, dash, console, seats, parcel shelf, wheel-houses, SteeringWheel
    car.bays()            dark engine bay under the hood (+ engine block) and trunk well
    car.front_fascia()    head lights, grille, bumper, indicators, plate
    car.rear_fascia()     tail lights (+reverse, indicator), plate, bumper, exhaust tip
    car.details()         wipers, fuel cap, antenna, side repeaters
    car.closures()        Door_* (hinge origins, handles, mirrors), Hood, Trunk
    car.wheels()          Wheel_FL/FR/RL/RR (+ML/MR) - one shared mesh, origin at centre, axle = local X
    car.collision()       Col_Body, Col_Cabin (convex, <= 32 verts, P_Collision)
    car.lod()             Body_LOD1
    car.mods()            Mod_* parts listed in params["mods"]
    (finish() adds the markers: Seat_*, Exit_*, Light_*, Exhaust, Engine, + Siren if params["siren"])
    car.light_bar()       optional roof light bar (M_Siren_Red / M_Siren_Blue) for emergency vehicles

COORDINATES
-----------
Blender, metres, car local space: +Y = nose, +X = right side, Z up, origin on the ground under the
centre.  `_L` = left = -X (driver side, right-hand traffic).  Everything is described by:

  * `top`     [(y, z)]   the shoulder line of the LOWER body from tail to nose: tail top, trunk deck,
                         rear-glass base (deck_y), belt line, windshield base (cowl_y), hood, nose top.
                         The shell spans top[0].y .. top[-1].y; bumpers add ~5 cm at each end.
  * `bottom`  [(y, z)]   lower edge of the body side (sill); wheel arches are cut into it automatically
                         as true semicircles (radius wheel_r + arch_gap) around every axle.
  * `plan`    [(y, f)]   half-width factor seen from above (1.0 = full width); narrows nose and tail.
  * the cross-section at every station (see `Car.section`):
        C0 centre top (+crown) - C1 crown edge - P1 belt/shoulder edge - P2 crease - Psw swage line
        (max width) - Prk rocker top - Psl sill - well - floor.
  * the cabin: cowl_y / roof_f / roof_r / deck_y + height + tumble (how much the glass leans in).

To get another silhouette change the three polylines and the cabin numbers:
  hatchback   short `top` tail, deck_y close to the tail, steep rear glass, trunk=None, spoiler_at="roof"
  wedge sport low nose key, low roof (1.20), roof_f far back, tumble 0.16, crease_drop 0.05
  muscle      long flat hood, short deck, high belt, c_pillar=(0.45, 0.30), wide track
  SUV         height 1.75, belt 1.10, wheel_r 0.38, roof_r far back, near-vertical rear glass,
              pillars_extra for the C pillar (the c_pillar parameter then describes the D pillar)
  pickup      cabin ends mid-car, open_top=[(bed range)] + own bed tub (see car_kit_examples.py)
  van / box   cowl_y far forward, short hood, long roof, `pillars_extra` as blank side panels,
              build the cargo box with car.body.loft()/box() before finish()

PARAMETER REFERENCE  (all lengths in metres; see DEFAULTS for the sedan values)
-------------------
  name, width, height                overall size (length follows from `top` + bumpers)
  axle_f, axle_r, axle_m             axle Y positions (axle_m only for 6-wheelers -> Wheel_ML/MR)
  wheel_r, wheel_w, track            wheel radius / tyre width / centre-to-centre track
  wheel_style                        key of WHEEL_STYLES: stock, sport, classic, offroad, deep, steel, truck
  arch_gap, arch_segs, arch_lip      arch clearance, roundness, lip material ("paint"/"trim"/None)
  top, bottom, plan                  the three polylines (above)
  crown, crown_w                     hood/trunk centre rise and half-width of the flat centre part
  shoulder_inset, crease_drop, crease_inset, swage_z, rocker_z, rocker_inset, sill_inset
                                     side cross-section (belt chamfer, crease, max-width line, rocker)
  rocker_mat, side_strip             "paint"/"trim" lower band; rub strip on the swage line ("trim",
                                     "chrome", None)
  cowl_y, roof_f, roof_r, deck_y     cabin key stations (windshield base, roof front/rear, rear glass base)
  tumble, roof_t, roof_drop          glass lean-in, roof thickness, roof edge drop (crown)
  a_pillar, c_pillar, b_pillar       pillar sizes: a = length along Y of its footprint;
                                     c = (base, top) lengths; b = width or None
  pillars_extra                      [(yb0, yb1, yt0, yt1)] extra side pillars / blank panels
  roof_mat                           "paint" / "paint2" / "trim"
  doors                              [("F", y_rear, y_front), ("R", y_rear, y_front)] -> Door_FL/FR/RL/RR
  door_hinge                         {"F": "front", "R": "front"}  ("rear" = suicide door)
  hood, trunk                        (y_rear, y_front) or "auto" or None
  open_top                           [(y0, y1)] ranges where the body top is left open (pickup bed ...)
  tub_z, seat_x, seat_f_y, seat_r_y, seat_z
                                     cabin floor height and hip points; seat_r_y=None -> no rear bench
  seat_color                         palette key of the seat material (P_<key>)
  head, tail, grille, bumper_f, bumper_r, plate_f, plate_r, exhaust
                                     fascia dictionaries (None = skip and model your own)
  mods, spoiler_at                   list of Mod_* names to build (customisable cars: FULL_MODS);
                                     spoilers sit on the "deck" or on the "roof"
  engine_y, siren                    Engine marker override; add a `Siren` marker (use car.light_bar())

To replace a generated part (your own spoiler, grille ...): leave it out of params / set its
dictionary to None and build into `car.mb("Mod_Spoiler_A")` (any contract name) or `car.body`
inside your extras function.  car.mb(name) creates a new child object of that name.

NODE / PIVOT CONVENTIONS (also in docs/VEHICLE_KIT.md - the vehicle code relies on them)
  * Wheel_xx: origin at the wheel centre, spin about local X.  The wheel mesh is mirror-symmetric
    (rim face on both sides) so the same mesh works on the left and on the right.
  * Door_xx: origin on the hinge line at the bottom of the door; hinge axis = Blender Z (Godot Y).
    Left doors open with a NEGATIVE Godot rotation.y, right doors with a positive one.
  * Hood: origin at the rear edge (cowl), opens with +rotation.x in Godot.  Trunk: origin at its
    front edge, opens with -rotation.x.
  * SteeringWheel: origin at the hub, tilted object; spin about its local Z in Godot (local Y in Blender).
  * Glass_* are direct children of the root (they stay in the cabin frame when a door opens).
  * Mod_*, Col_*, Body_LOD1 are hidden in Blender (eye icon + render) but always exported.
  * Materials are the shared contract materials (M_Paint_Primary ...).  G.mat() never changes a
    material that already exists, so their values are whatever the first author set.

Geometry helpers for your own parts live on the `MB` mesh builder (car.body is one):
  box, cyl, loft, prism, sweep, revolve, face, bevel - every solid gets outward normals immediately.
"""
import bpy
import bmesh
import math
from math import sin, cos, pi, sqrt, radians, asin
from mathutils import Vector

import gta_bl as G

KIT_VERSION = "1.0"
NAME_SEP = ":"          # Blender object names are '<asset>:<part>'; export_glb() strips '<asset>:'


def short_name(ob):
    """Contract name of a part object ('sedan:Wheel_FL' -> 'Wheel_FL')."""
    nm = ob.name
    return nm.split(NAME_SEP, 1)[1] if NAME_SEP in nm else nm

FULL_MODS = ["Mod_Spoiler_A", "Mod_Spoiler_B", "Mod_BumperF_A", "Mod_BumperR_A", "Mod_Hood_A",
             "Mod_Skirts_A", "Mod_Roof_A", "Mod_Exhaust_A", "Mod_Grille_A"]

# ------------------------------------------------------------------------------------------------
# default parameters = the reference family sedan (4.60 x 1.80 x 1.45 m)
# ------------------------------------------------------------------------------------------------
DEFAULTS = dict(
    name="sedan",
    width=1.80, height=1.45,
    # running gear
    axle_f=1.40, axle_r=-1.35, axle_m=None,
    wheel_r=0.34, wheel_w=0.23, track=1.52, wheel_style="stock",
    arch_gap=0.05, arch_segs=8, arch_lip="paint",
    # lower body polylines, tail (-Y) -> nose (+Y)
    top=[(-2.25, 0.92), (-1.42, 1.00), (0.92, 0.96), (2.03, 0.81), (2.25, 0.69)],
    bottom=[(-2.25, 0.36), (-1.86, 0.24), (1.92, 0.22), (2.25, 0.30)],
    plan=[(-2.25, 0.85), (-2.02, 0.965), (-1.76, 1.0), (1.82, 1.0), (2.07, 0.955), (2.25, 0.83)],
    crown=0.03, crown_w=0.30,
    shoulder_inset=0.09, crease_drop=0.10, crease_inset=0.02,
    swage_z=0.62, rocker_z=0.34, rocker_inset=0.015, sill_inset=0.05,
    rocker_mat="trim", side_strip="trim",
    # cabin
    cowl_y=0.92, roof_f=0.27, roof_r=-0.84, deck_y=-1.42,
    tumble=0.13, roof_t=0.055, roof_drop=0.035,
    a_pillar=0.13, c_pillar=(0.30, 0.20), b_pillar=0.09, pillar_w=0.06,
    pillars_extra=[],
    roof_mat="paint",
    # closures
    doors=[("F", -0.12, 0.90), ("R", -0.95, -0.12)],
    door_hinge={"F": "front", "R": "front"},
    door_t=0.055, seam=0.012,
    hood="auto", trunk="auto", open_top=[],
    # interior
    tub_z=0.24, seat_x=0.37, seat_f_y=-0.10, seat_r_y=-0.95, seat_z=0.47, seat_color="Khaki",
    # fascia
    head=dict(w=0.30, h=0.12, inset=0.02, z=None),
    grille=dict(bars=3),
    tail=dict(w=0.36, h=0.13, inset=0.02, z=None),
    bumper_f=dict(h=0.22, out=0.05, wrap=0.34),
    bumper_r=dict(h=0.22, out=0.05, wrap=0.34),
    plate_f=True, plate_r=True,
    exhaust=dict(x=-0.48, r=0.034),
    # extras
    mods=[], spoiler_at="deck", engine_y=None, siren=False,
)

# rim = rim radius / wheel radius, dish = how deep the spoke face sits, spokes = (count, width, thick)
WHEEL_STYLES = {
    "stock":   dict(rim=0.62, dish=0.035, lip=0.014, shoulder=0.030, bulge=0.0, spokes=(5, 0.070, 0.022), hub=0.050),
    "sport":   dict(rim=0.72, dish=0.030, lip=0.012, shoulder=0.026, bulge=0.0, spokes=(5, 0.030, 0.020), twin=0.17, hub=0.042),
    "classic": dict(rim=0.60, dish=0.022, lip=0.016, shoulder=0.034, bulge=0.008, solid=True, cap=0.115, slots=6, hub=0.0),
    "offroad": dict(rim=0.56, dish=0.040, lip=0.030, shoulder=0.042, bulge=0.0, spokes=(6, 0.062, 0.026), hub=0.062,
                    lugs=0.016, bars=14),
    "deep":    dict(rim=0.68, dish=0.085, lip=0.022, shoulder=0.028, bulge=0.0, spokes=(6, 0.050, 0.018), hub=0.055),
    "steel":   dict(rim=0.60, dish=0.030, lip=0.016, shoulder=0.036, bulge=0.008, solid=True, cap=0.07, slots=6, hub=0.0),
    "truck":   dict(rim=0.56, dish=0.060, lip=0.020, shoulder=0.040, bulge=0.010, solid=True, cap=0.10, slots=8, hub=0.0,
                    lugs=0.012, bars=7),
}


# ------------------------------------------------------------------------------------------------
# small maths helpers
# ------------------------------------------------------------------------------------------------
def interp(keys, y):
    """Piecewise-linear lookup in a sorted [(y, value)] list (clamped at both ends)."""
    if y <= keys[0][0]:
        return keys[0][1]
    for (y0, v0), (y1, v1) in zip(keys[:-1], keys[1:]):
        if y <= y1:
            if y1 - y0 < 1e-9:
                return v1
            t = (y - y0) / (y1 - y0)
            return v0 + (v1 - v0) * t
    return keys[-1][1]


def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    c = len(pts)
    for i in range(c):
        a = pts[i]
        b = pts[(i + 1) % c]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


def contract_materials(seat_color="Khaki"):
    """The shared contract materials (created once, reused by every vehicle)."""
    m = {}
    m["paint"] = G.mat("M_Paint_Primary", G.pal("CarRed"), rough=0.35, metal=0.1)
    m["paint2"] = G.mat("M_Paint_Secondary", G.pal("CarWhite"), rough=0.4, metal=0.05)
    m["glass"] = G.mat("M_Glass", G.pal("WindowDark"), rough=0.08, alpha=0.45)
    m["trim"] = G.mat("M_Trim", G.pal("Trim"), rough=0.7)
    m["chrome"] = G.mat("M_Chrome", G.pal("Chrome"), rough=0.22, metal=0.7)
    m["interior"] = G.mat("M_Interior", G.pal("Interior"), rough=0.85)
    m["under"] = G.mat("M_Underbody", G.pal("Black"), rough=0.9)
    m["plate"] = G.mat("M_Plate", G.pal("RoadLine"), rough=0.6)
    m["head"] = G.mat("M_Headlight", G.pal("HeadlightWhite"), rough=0.15)
    m["tail"] = G.mat("M_Taillight", G.pal("TailRed"), rough=0.25)
    m["indicator"] = G.mat("M_Indicator", G.pal("IndicatorAmber"), rough=0.25)
    m["reverse"] = G.mat("M_ReverseLight", G.pal("White"), rough=0.2)
    m["tire"] = G.mat("M_Tire", G.pal("Tire"), rough=0.92)
    m["rim"] = G.mat("M_Rim", G.pal("Rim"), rough=0.32, metal=0.6)
    m["col"] = G.mat("P_Collision", (1.0, 0.0, 1.0), alpha=0.3)
    m["seat"] = G.pmat(seat_color, rough=0.8)
    return m


# ------------------------------------------------------------------------------------------------
# MB - mesh builder (one per output object)
# ------------------------------------------------------------------------------------------------
class MB:
    """A bmesh plus its material slots.  Shell faces (`face`) keep the winding you give them;
    every solid (`box`, `cyl`, `loft`, `sweep`, `revolve`) gets outward normals right away, so the
    final object is created without a global normal recalculation."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []
        self._vc = {}

    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def empty(self):
        return len(self.bm.faces) == 0

    def _v(self, p):
        k = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
        v = self._vc.get(k)
        if v is None or not v.is_valid:
            v = self.bm.verts.new((p[0], p[1], p[2]))
            self._vc[k] = v
        return v

    def face(self, pts, mat, mirror=False, want=None):
        """One polygon from points.  Winding = as given (counter-clockwise seen from outside), or
        pass want=(nx,ny,nz) to orient it automatically.  mirror=True adds the X-mirrored twin."""
        pts = [tuple(q) for q in pts]
        if want is not None and _newell(pts).dot(Vector(want)) < 0.0:
            pts = list(reversed(pts))
        vs = []
        for q in pts:
            v = self._v(q)
            if v not in vs:
                vs.append(v)
        f = None
        if len(vs) >= 3:
            try:
                f = self.bm.faces.new(vs)
                f.material_index = self.mi(mat)
            except ValueError:
                f = None
        if mirror:
            self.face([(-q[0], q[1], q[2]) for q in reversed(pts)], mat, False, None)
        return f

    def bevel(self, faces, width, angle=30.0):
        """Chamfer the hard edges of the given faces (width in metres)."""
        lim = radians(angle)
        edges = set()
        for f in faces:
            if not f.is_valid:
                continue
            for e in f.edges:
                if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
                    edges.add(e)
        if not edges:
            return
        try:
            bmesh.ops.bevel(self.bm, geom=list(edges), offset=width, offset_type='OFFSET', segments=1,
                            profile=0.5, affect='EDGES', clamp_overlap=True, material=-1)
        except Exception as ex:
            print("car_kit: bevel skipped:", ex)

    def box(self, size, center, mat, rot=None, mirror=False, bevel=0.0):
        """Box of size (x,y,z) at center, optional euler rot; mirror=True adds the twin at -X."""
        for sgn in ((1.0, -1.0) if mirror else (1.0,)):
            c = (center[0] * sgn, center[1], center[2])
            r = rot
            if rot is not None and sgn < 0:
                r = (rot[0], -rot[1], -rot[2])
            vs = G.add_box(self.bm, size, c, r, self.mi(mat))
            if bevel > 0:
                self.bevel(list({f for v in vs for f in v.link_faces}), bevel)

    def cyl(self, radius, depth, center, mat, axis='Y', segments=10, radius2=None, mirror=False, rot=None):
        for sgn in ((1.0, -1.0) if mirror else (1.0,)):
            c = (center[0] * sgn, center[1], center[2])
            r = rot
            if rot is not None and sgn < 0:
                r = (rot[0], -rot[1], -rot[2])
            G.add_cylinder(self.bm, radius, depth, c, axis, segments, self.mi(mat), radius2, r)

    def loft(self, sections, mat=None, mats=None, closed=True, cap=True, loop=False, cap_mat=None,
             mirror=False, bevel=0.0):
        """Skin cross-sections (same point count each) into a SOLID with outward normals.
        mats = one material per section edge (point i -> i+1); cap_mat for the end caps;
        loop=True joins the last section back to the first (rings, tyres)."""
        if mirror:
            self.loft([[(-q[0], q[1], q[2]) for q in sec] for sec in sections], mat, mats, closed, cap,
                      loop, cap_mat, False, bevel)
        bm = self.bm
        rings = [[bm.verts.new((q[0], q[1], q[2])) for q in sec] for sec in sections]
        n = len(rings[0])
        mis = [self.mi(m) for m in mats] if mats else None
        mi0 = self.mi(mat) if mat is not None else (mis[0] if mis else 0)
        cmi = self.mi(cap_mat) if cap_mat is not None else mi0
        pairs = list(zip(rings[:-1], rings[1:]))
        if loop:
            pairs.append((rings[-1], rings[0]))
        last = n if closed else n - 1
        for a, b in pairs:
            for i in range(last):
                j = (i + 1) % n
                try:
                    f = bm.faces.new((a[i], a[j], b[j], b[i]))
                except ValueError:
                    continue
                f.material_index = mis[i] if mis else mi0
        if cap and closed and not loop and n >= 3:
            for ring in (list(reversed(rings[0])), rings[-1]):
                try:
                    f = bm.faces.new(ring)
                    f.material_index = cmi
                except ValueError:
                    pass
        verts = [v for r in rings for v in r]
        bmesh.ops.remove_doubles(bm, verts=verts, dist=1e-5)
        verts = [v for v in verts if v.is_valid]
        faces = list({f for v in verts for f in v.link_faces})
        bmesh.ops.recalc_face_normals(bm, faces=faces)
        if bevel > 0:
            self.bevel(faces, bevel)
            return []
        return faces

    def prism(self, profile, lo, hi, mat, axis='X', mats=None, cap_mat=None, bevel=0.0):
        """Extrude a closed 2D profile between lo..hi.  axis 'X': points (y,z); 'Y': (x,z); 'Z': (x,y)."""
        def p3(q, t):
            if axis == 'X':
                return (t, q[0], q[1])
            if axis == 'Y':
                return (q[0], t, q[1])
            return (q[0], q[1], t)
        return self.loft([[p3(q, lo) for q in profile], [p3(q, hi) for q in profile]], mat, mats=mats,
                         cap_mat=cap_mat, bevel=bevel)

    def sweep(self, path, profile, mat=None, mats=None, cap_mat=None, miter_max=1.7):
        """Sweep a closed profile [(d, z)] along a plan-view polyline [(x, y)].  d is measured along
        the outward normal of the path, where 'outward' = left of the direction of travel
        (walk the front bumper from the left corner to the right corner)."""
        n = len(path)
        secs = []
        for i in range(n):
            ns = []
            for a, b in ((i - 1, i), (i, i + 1)):
                if a < 0 or b >= n:
                    continue
                d = Vector((path[b][0] - path[a][0], path[b][1] - path[a][1]))
                if d.length < 1e-9:
                    continue
                d.normalize()
                ns.append(Vector((-d.y, d.x)))
            if len(ns) == 2:
                m = (ns[0] + ns[1])
                if m.length < 1e-6:
                    m = ns[0].copy()
                m.normalize()
                m *= 1.0 / max(m.dot(ns[0]), 1.0 / miter_max)
            else:
                m = ns[0]
            secs.append([(path[i][0] + m.x * d, path[i][1] + m.y * d, z) for d, z in profile])
        return self.loft(secs, mat, mats=mats, cap_mat=cap_mat)

    def revolve(self, profile, mat=None, axis='X', segs=14, mats=None, closed=False, phase=0.0, mod=None):
        """Lathe a profile [(t, r)] (t along the axis, r = radius) around `axis`.  An open profile
        should start and end on the axis (r = 0) so the result is a closed solid.
        mod(segment_index, point_index, r) -> r lets single rings wobble (tyre lugs, gear teeth)."""
        secs = []
        for i in range(segs):
            a = phase + 2.0 * pi * i / segs
            c, s = cos(a), sin(a)
            prof = profile if mod is None else [(t, mod(i, k, r)) for k, (t, r) in enumerate(profile)]
            if axis == 'X':
                secs.append([(t, r * c, r * s) for t, r in prof])
            elif axis == 'Y':
                secs.append([(r * c, t, r * s) for t, r in prof])
            else:
                secs.append([(r * c, r * s, t) for t, r in prof])
        return self.loft(secs, mat, mats=mats, closed=closed, cap=False, loop=True)

    def obj(self, name, parent, smooth=None):
        """Create the mesh object (frees the bmesh)."""
        ob = G.new_object(name, self.bm, parent=parent, materials=self.mats, smooth_angle=smooth,
                          recalc=False, weld=0.0001)
        self.bm = None
        return ob


# ------------------------------------------------------------------------------------------------
# wheels
# ------------------------------------------------------------------------------------------------
def build_wheel(mb, M, radius=0.34, width=0.23, style="stock", segs=14):
    """Add one wheel (tyre + rim, centre at the origin, axle along X, rim face on BOTH sides so the
    same mesh serves left and right) to mesh builder `mb`.  Materials M_Tire / M_Rim only."""
    st = WHEEL_STYLES[style]
    R = radius
    hw = width / 2.0
    tire, rim = M["tire"], M["rim"]
    lug = st.get("lugs", 0.0)
    segs = st.get("segs", segs)
    Rt = R - lug                          # tread base radius (lugs reach R)
    rr = R * st["rim"]
    dish = min(st["dish"], hw - 0.01)
    lip = st["lip"]
    sh = st["shoulder"]
    bulge = st.get("bulge", 0.0)
    dish_mat = rim if st.get("solid") else tire
    prof = [(-hw + dish, 0.0), (-hw + dish, rr - 0.03), (-hw + lip, rr - 0.012), (-hw, rr)]
    mats = [dish_mat, rim, rim]
    if bulge > 0:
        prof.append((-hw - bulge, (rr + Rt - sh) / 2.0))
        mats.append(tire)
    prof += [(-hw, Rt - sh), (-hw + sh, Rt), (hw - sh, Rt), (hw, Rt - sh)]
    mats += [tire, tire, tire, tire]
    if bulge > 0:
        prof.append((hw + bulge, (rr + Rt - sh) / 2.0))
        mats.append(tire)
    prof += [(hw, rr), (hw - lip, rr - 0.012), (hw - dish, rr - 0.03), (hw - dish, 0.0)]
    mats += [tire, rim, rim, dish_mat]
    mb.revolve(prof, axis='X', segs=segs, mats=mats)
    if lug > 0 and st.get("bars"):        # staggered tread blocks (alternating left / right half)
        nb = st["bars"]
        bw = width * 0.58
        hgt = lug + 0.03
        rb = R - hgt / 2.0
        for i in range(nb):
            a = 2.0 * pi * (i * (segs // nb) + 0.5) / segs
            sx = 1.0 if i % 2 == 0 else -1.0
            mb.box((bw, 2.0 * Rt * sin(pi / segs) * 0.60, hgt), (sx * (hw - bw / 2.0 + 0.008), -rb * sin(a), rb * cos(a)), tire,
                   rot=(a, 0.0, 0.0))
    for sgn in (1.0, -1.0):
        x0 = sgn * (hw - dish)                           # dish floor
        if st.get("spokes"):
            n, wsp, tx = st["spokes"]
            r0, r1 = 0.02, rr - 0.028
            ln = r1 - r0
            rc = (r0 + r1) / 2.0
            twin = st.get("twin", 0.0)
            for i in range(n):
                a0 = 2.0 * pi * i / n
                for da in ((-twin, twin) if twin else (0.0,)):
                    a = a0 + da
                    tilt = (da * 0.9) if twin else 0.0
                    mb.box((tx, wsp, ln), (x0 + sgn * (tx / 2 - 0.003), -rc * sin(a), rc * cos(a)), rim,
                           rot=(a - tilt, 0.0, 0.0))
        if st.get("hub", 0.0) > 0:
            hh = (st["spokes"][2] if st.get("spokes") else 0.02) + 0.012
            mb.cyl(st["hub"], hh, (x0 + sgn * (hh / 2 - 0.003), 0, 0), rim, axis='X', segments=8,
                   radius2=None)
        if st.get("cap", 0.0) > 0:                       # domed hub cap
            c = st["cap"]
            capprof = [(0.0, c), (0.02, c * 0.92), (0.036, c * 0.5), (0.04, 0.0)]
            mb.revolve([(x0 + sgn * t - sgn * 0.004, r) for t, r in ([(0.0, 0.0)] + capprof)], rim, axis='X', segs=8)
        if st.get("slots"):
            ns = st["slots"]
            rs = (st.get("cap", 0.08) + rr - 0.03) / 2.0
            for i in range(ns):
                a = 2.0 * pi * (i + 0.5) / ns
                mb.box((0.012, 0.030, max(0.035, (rr - 0.03 - st.get("cap", 0.08)) * 0.55)),
                       (x0 + sgn * 0.002, -rs * sin(a), rs * cos(a)), tire, rot=(a, 0.0, 0.0))
    return mb


def build_wheel_asset(name, style, location, radius=0.34, width=0.23, collection="Vehicles/Cars", segs=14):
    """Stand-alone shared wheel: root Empty `name` with ONE child mesh called 'Wheel'."""
    M = contract_materials()
    root = G.asset_root(name, collection, location)
    mb = build_wheel(MB(), M, radius, width, style, segs)
    mb.obj(name + NAME_SEP + "Wheel", root, smooth=35.0)
    return root


# ------------------------------------------------------------------------------------------------
# Car
# ------------------------------------------------------------------------------------------------
class Car:
    # section point indices
    C0, C1, P1, P2, PSW, PRK, PSL, WT, WB, F0 = range(10)

    def __init__(self, params=None, location=(0, 0, 0), collection="Vehicles/Cars"):
        p = dict(DEFAULTS)
        p.update(params or {})
        self.p = p
        self.name = p["name"]
        self.M = contract_materials(p["seat_color"])
        self.hw = p["width"] / 2.0
        self.top = sorted(p["top"])
        self.bottom_keys = sorted(p["bottom"])
        self.plan = sorted(p["plan"])
        self.y_r = self.top[0][0]
        self.y_f = self.top[-1][0]
        self.axles = [("F", p["axle_f"]), ("R", p["axle_r"])]
        if p.get("axle_m") is not None:
            self.axles.insert(1, ("M", p["axle_m"]))
        self.Ra = p["wheel_r"] + p["arch_gap"]
        self.zc = p["wheel_r"]
        self.x_well = p["track"] / 2.0 - p["wheel_w"] / 2.0 - 0.10
        # closures
        cy, dy = p["cowl_y"], p["deck_y"]
        self.hood = p["hood"]
        if self.hood == "auto":
            self.hood = (cy + 0.07, self.top[-2][0])
        self.trunk = p["trunk"]
        if self.trunk == "auto":
            self.trunk = (self.y_r + 0.05, dy - 0.05)
        self.doors = list(p["doors"])
        self.root = G.asset_root(self.name, collection, location)
        # mesh builders
        self.body = MB()
        self.parts = {}          # name -> MB for the other objects
        self.origins = {}        # name -> origin (local point)
        self.objects = {}
        self._stations()

    # ---------------------------------------------------------------- profile functions
    def w(self, y):
        """Body half-width at station y (at the swage line)."""
        return self.hw * interp(self.plan, y)

    def zt(self, y):
        """Shoulder / belt height of the lower body at y."""
        return interp(self.top, y)

    def belt_x(self, y):
        return self.w(y) - self.p["shoulder_inset"]

    def arch_z(self, y):
        z = -1.0
        for _, yc in self.axles:
            d = abs(y - yc)
            if d < self.Ra:
                z = max(z, self.zc + sqrt(self.Ra * self.Ra - d * d))
        return z

    def _side_profile(self, y):
        p = self.p
        w = self.w(y)
        zt = self.zt(y)
        cr = zt - p["crease_drop"]
        sw = min(p["swage_z"], cr - 0.04)
        rk = min(p["rocker_z"], sw - 0.04)
        zb = min(interp(self.bottom_keys, y), rk - 0.02)
        return [(w - p["shoulder_inset"], zt), (w - p["crease_inset"], cr), (w, sw),
                (w - p["rocker_inset"], rk), (w - p["sill_inset"], zb)]

    def side_x(self, y, z):
        """X of the body side surface at (y, z) (ignores wheel arches)."""
        prof = self._side_profile(y)
        if z >= prof[0][1]:
            return prof[0][0]
        for (x0, z0), (x1, z1) in zip(prof[:-1], prof[1:]):
            if z >= z1:
                t = (z0 - z) / max(z0 - z1, 1e-9)
                return x0 + (x1 - x0) * t
        return prof[-1][0]

    def section(self, y, arches=True):
        """The 10 cross-section points of the +X half at station y (see class constants)."""
        p = self.p
        prof = self._side_profile(y)
        zt = prof[0][1]
        zb = prof[-1][1]
        za = self.arch_z(y) if arches else -1.0
        zb2 = zb
        if za > zb + 1e-4:
            lim = prof[1][1] - 0.01
            if za > lim + 0.004 and not getattr(self, "_arch_warned", False):
                self._arch_warned = True
                print("car_kit WARNING %s: ARCH CLAMPED at y=%.2f (arch %.3f > fender crease %.3f) - raise `top` over the "
                      "axle, lower crease_drop or use a smaller wheel" % (self.name, y, za, lim))
            za = min(za, lim)
            edge = (self.side_x(y, za), za)
            prof = [prof[0]] + [q if q[1] > za else edge for q in prof[1:]]
            zb2 = za
        xw = min(self.x_well, prof[-1][0] - 0.03)
        fl = zb - 0.03
        cz = zt + p["crown"]
        cw = min(p["crown_w"], prof[0][0] * 0.7)
        return [(0.0, y, cz), (cw, y, cz)] + [(x, y, z) for x, z in prof] + [(xw, y, zb2), (xw, y, fl), (0.0, y, fl)]

    def _arch_samples(self, yc, n=None, extra=0.0):
        """[(y, z)] points of the wheel arch around axle yc, rear -> front."""
        n = n or self.p["arch_segs"]
        zb = interp(self.bottom_keys, yc)
        s = (zb - self.zc) / self.Ra
        if s >= 1.0:
            return []
        t0 = asin(max(-1.0, min(1.0, s))) - extra
        out = []
        for i in range(n + 1):
            t = pi - t0 - (pi - 2 * t0) * i / n
            out.append((yc + self.Ra * cos(t), self.zc + self.Ra * sin(t)))
        return out

    def _stations(self):
        p = self.p
        ys = [y for y, _ in self.top] + [y for y, _ in self.bottom_keys] + [y for y, _ in self.plan]
        ys += [p["cowl_y"], p["deck_y"]]
        for rng in (self.hood, self.trunk):
            if rng:
                ys += [rng[0], rng[1]]
        for _, a, b in self.doors:
            ys += [a, b]
        for a, b in p["open_top"]:
            ys += [a, b]
        for _, yc in self.axles:
            ys += [y for y, _ in self._arch_samples(yc)]
        ys = sorted(y for y in ys if self.y_r - 1e-6 <= y <= self.y_f + 1e-6)
        out = []
        for y in ys:
            if not out or y - out[-1] > 0.004:
                out.append(y)
        self.ys = out
        return out

    def n(self, part):
        """Blender object name of a part: '<asset>:<part>' (unique in the shared .blend; the prefix
        is stripped from the GLB by car_kit.export_glb)."""
        return self.name + NAME_SEP + part

    def _in(self, rng, y):
        return bool(rng) and rng[0] < y < rng[1]

    def _in_door(self, y):
        return any(a < y < b for _, a, b in self.doors)

    def _mat(self, key):
        return self.M[key] if key in self.M else G.pmat(key)

    def mb(self, name):
        if name not in self.parts:
            self.parts[name] = MB()
        return self.parts[name]

    # ---------------------------------------------------------------- lower body shell
    def skin(self):
        p, M, b = self.p, self.M, self.body
        cy, dy = p["cowl_y"], p["deck_y"]
        S = [self.section(y) for y in self.ys]
        rocker = self._mat(p["rocker_mat"])
        for i in range(len(S) - 1):
            ym = (self.ys[i] + self.ys[i + 1]) / 2.0
            A, B = S[i], S[i + 1]
            in_door = self._in_door(ym)
            for k in range(9):
                if k <= 1:
                    if dy < ym < cy or self._in(self.hood, ym) or self._in(self.trunk, ym):
                        continue
                    if any(a < ym < c for a, c in p["open_top"]):
                        continue
                    mat = M["trim"] if (self.hood and cy < ym < self.hood[0]) else M["paint"]
                elif k <= 4:
                    if in_door:
                        continue
                    mat = M["paint"]
                elif k == 5:
                    mat = rocker
                else:
                    mat = M["under"]
                b.face([A[k], A[k + 1], B[k + 1], B[k]], mat, mirror=True)
        b.face(S[-1], M["paint"], mirror=True, want=(0, 1, 0))
        b.face(S[0], M["paint"], mirror=True, want=(0, -1, 0))
        self._arch_lips()
        self.side_strips()

    def _strip_loft(self, mb, ya, yb, side=1.0, both=False):
        """Rub strip along the swage line between ya..yb on one side (or both)."""
        mat = self._mat(self.p["side_strip"])
        ys = [ya] + [s for s in self.ys if ya + 0.02 < s < yb - 0.02] + [yb]
        secs = []
        for y in ys:
            x, z = self._side_profile(y)[2]
            secs.append([(side * (x - 0.006), y, z - 0.019), (side * (x + 0.013), y, z - 0.019),
                         (side * (x + 0.013), y, z + 0.019), (side * (x - 0.006), y, z + 0.019)])
        mb.loft(secs, mat, mirror=both)

    def side_strips(self):
        """Body part of the rub strip (the door parts are added in closures())."""
        p = self.p
        if not p["side_strip"]:
            return
        cuts = []
        for _, yc in self.axles:
            dz = p["swage_z"] - self.zc
            if abs(dz) < self.Ra:
                h = sqrt(self.Ra ** 2 - dz ** 2) + 0.06
                cuts.append((yc - h, yc + h))
        cuts += [(a - 0.004, b + 0.004) for _, a, b in self.doors]
        cuts.sort()
        y = self.y_r + 0.03
        end = self.y_f - 0.03
        for a, b in cuts + [(end, end)]:
            if a - y > 0.06:
                self._strip_loft(self.body, y, min(a, end), both=True)
            y = max(y, b)

    def _arch_lips(self):
        p, b = self.p, self.body
        if not p["arch_lip"]:
            return
        mat = self._mat(p["arch_lip"])
        Ra = self.Ra
        for _, yc in self.axles:
            pts = self._arch_samples(yc, extra=0.02)
            if not pts:
                continue
            secs = []
            for y, z in pts:
                dy_, dz_ = (y - yc) / Ra, (z - self.zc) / Ra
                xe = self.side_x(y, max(z, 0.05))
                xi, xo = xe - 0.03, xe + 0.022
                ring = []
                for x, r in ((xi, Ra - 0.008), (xo, Ra - 0.008), (xo, Ra + 0.022), (xo - 0.016, Ra + 0.046), (xi, Ra + 0.046)):
                    ring.append((x, yc + dy_ * r, self.zc + dz_ * r))
                secs.append(ring)
            b.loft(secs, mat, mirror=True)

    # ---------------------------------------------------------------- cabin
    def _gh(self):
        p = self.p
        cy, dy = p["cowl_y"], p["deck_y"]
        xc, zc = self.belt_x(cy), self.zt(cy)
        xd, zd = self.belt_x(dy), self.zt(dy)
        xr = min(xc, xd) - p["tumble"]
        rz = p["height"]
        zR = rz - p["roof_drop"]
        return dict(cy=cy, dy=dy, xc=xc, zc=zc, xd=xd, zd=zd, xr=xr, rz=rz, zR=zR, rf=p["roof_f"], rr=p["roof_r"])

    def greenhouse(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy, dy, xc, zc, xd, zd, xr, rz, zR, rf, rr = (g[k] for k in ("cy", "dy", "xc", "zc", "xd", "zd", "xr", "rz", "zR", "rf", "rr"))
        t = p["roof_t"]
        pw = p["pillar_w"]
        roof_mat = self._mat(p["roof_mat"])
        # roof slab (full width sections, rear -> front)
        def rring(y, drop, narrow):
            x1 = xr - narrow
            x0 = max(x1 - 0.12, 0.05)
            return [(-x1, y, zR - t - drop * 0.4), (-x1, y, zR - drop), (-x0, y, rz - drop), (x0, y, rz - drop),
                    (x1, y, zR - drop), (x1, y, zR - t - drop * 0.4)]
        ov = 0.05
        b.loft([rring(rr - ov, 0.04, 0.012), rring(rr + 0.09, 0.0, 0.0), rring(rf - 0.09, 0.0, 0.0),
                rring(rf + ov, 0.04, 0.012)], roof_mat)
        zp = zR - 0.012                      # pillar tops end inside the roof slab
        # A pillars
        pa = p["a_pillar"]
        b.loft([[(xc, cy, zc - 0.02), (xc - pw, cy, zc - 0.02), (xc - pw, cy - pa, zc - 0.02), (xc, cy - pa, zc - 0.02)],
                [(xr, rf, zp), (xr - pw, rf, zp), (xr - pw, rf - pa, zp), (xr, rf - pa, zp)]], M["paint"], mirror=True)
        # C pillars
        pc0, pc1 = p["c_pillar"]
        b.loft([[(xd, dy, zd - 0.02), (xd, dy + pc0, zd - 0.02), (xd - pw, dy + pc0, zd - 0.02), (xd - pw, dy, zd - 0.02)],
                [(xr, rr, zp), (xr, rr + pc1, zp), (xr - pw, rr + pc1, zp), (xr - pw, rr, zp)]], M["paint"], mirror=True)
        # B pillar (between the first two doors) + extra pillars / blank panels
        pil = list(p["pillars_extra"])
        if p["b_pillar"] and len(self.doors) >= 1:
            yb = self.doors[0][1]            # rear edge of the front door
            hb = p["b_pillar"] / 2.0
            ytop = min(max(yb - 0.02, rr + pc1 + 0.1), rf - pa - 0.1)
            pil.append((yb - hb, yb + hb, ytop - hb * 0.85, ytop + hb * 0.85))
        for yb0, yb1, yt0, yt1 in pil:
            x0, x1 = self.belt_x(yb0), self.belt_x(yb1)
            z0, z1 = self.zt(yb0) - 0.02, self.zt(yb1) - 0.02
            b.loft([[(x0, yb0, z0), (x1, yb1, z1), (x1 - pw, yb1, z1), (x0 - pw, yb0, z0)],
                    [(xr, yt0, zp), (xr, yt1, zp), (xr - pw, yt1, zp), (xr - pw, yt0, zp)]], M["paint"], mirror=True)
        # glass panes (separate objects)
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

    # ---------------------------------------------------------------- interior
    def seat(self, x, y, z_hip, width=0.50, headrest=True):
        """Bucket seat / bench (hip point at x, y, z_hip) into the Body mesh."""
        b, m = self.body, self.M["seat"]
        ct = z_hip - 0.09
        base = self.p["tub_z"] + 0.03
        b.box((width, 0.50, ct - base), (x, y + 0.10, (ct + base) / 2.0), m, bevel=0.025)
        b.box((width, 0.13, 0.62), (x, y - 0.235, ct + 0.24), m, rot=(radians(14), 0, 0), bevel=0.025)
        if headrest:
            n = max(1, int(round(width / 0.62)))
            for i in range(n):
                hx = x + (i - (n - 1) / 2.0) * (width / n)
                b.box((0.26, 0.10, 0.18), (hx, y - 0.33, ct + 0.63), m, rot=(radians(8), 0, 0))

    def interior(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy, dy = g["cy"], g["dy"]
        tz = p["tub_z"]
        I = M["interior"]
        ys = [y for y in self.ys if dy - 1e-6 <= y <= cy + 1e-6]
        xt = lambda y: self.belt_x(y) - 0.02
        for ya, yb in zip(ys[:-1], ys[1:]):
            ym = (ya + yb) / 2.0
            b.face([(-xt(ya), ya, tz), (xt(ya), ya, tz), (xt(yb), yb, tz), (-xt(yb), yb, tz)], I, want=(0, 0, 1))
            door = self._in_door(ym)
            rk = p["rocker_z"]
            ta = rk if door else self.zt(ya) - 0.004
            tb = rk if door else self.zt(yb) - 0.004
            b.face([(xt(ya), ya, tz), (xt(yb), yb, tz), (xt(yb), yb, tb), (xt(ya), ya, ta)], I, mirror=True, want=(-1, 0, 0))
            if door:        # sill top between the tub wall and the rocker edge
                b.face([(xt(ya), ya, rk), (xt(yb), yb, rk), (self.side_x(yb, rk), yb, rk), (self.side_x(ya, rk), ya, rk)],
                       M["trim"], mirror=True, want=(0, 0, 1))
        b.face([(-xt(cy), cy, tz), (xt(cy), cy, tz), (xt(cy), cy, g["zc"]), (-xt(cy), cy, g["zc"])], I, want=(0, -1, 0))
        b.face([(-xt(dy), dy, tz), (xt(dy), dy, tz), (xt(dy), dy, g["zd"]), (-xt(dy), dy, g["zd"])], I, want=(0, 1, 0))
        # B posts hidden behind the door edges (visible when the doors are open)
        if len(self.doors) >= 2:
            yb = self.doors[0][1]
            b.box((0.06, 0.09, self.zt(yb) - tz), (xt(yb) - 0.01, yb, (self.zt(yb) + tz) / 2.0), I, mirror=True)
        # wheel-houses where an arch reaches into the cabin
        for _, yc in self.axles:
            y0, y1 = max(yc - self.Ra - 0.03, dy), min(yc + self.Ra + 0.03, cy)
            if y1 - y0 > 0.05:
                top = self.zc + self.Ra + 0.04
                x0 = self.x_well - 0.03
                x1 = xt((y0 + y1) / 2.0) + 0.01
                b.box((x1 - x0, y1 - y0, top - tz), ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (top + tz) / 2.0), I, mirror=True)
        # dash, binnacle, console, parcel shelf
        dw = 2.0 * xt(cy) - 0.02
        b.box((dw, 0.42, 0.30), (0, cy - 0.22, g["zc"] - 0.17), I, bevel=0.04)
        sx = p["seat_x"]
        b.box((0.36, 0.16, 0.08), (-sx, cy - 0.38, g["zc"] - 0.01), I)
        b.box((0.22, 0.10, 0.12), (0, cy - 0.44, g["zc"] - 0.16), M["trim"])
        cl = (cy - 0.40) - (p["seat_f_y"] - 0.30)
        b.box((0.22, cl, 0.22), (0, p["seat_f_y"] - 0.30 + cl / 2.0, tz + 0.11), I)
        b.box((0.05, 0.05, 0.16), (0, p["seat_f_y"] + 0.28, tz + 0.27), M["trim"])
        if g["rr"] - dy > 0.15:
            b.box((2.0 * xt(dy) - 0.02, 0.40, 0.04), (0, dy + 0.20, g["zd"] - 0.05), I)
        # seats
        sz = p["seat_z"]
        self.seat(-sx, p["seat_f_y"], sz)
        self.seat(sx, p["seat_f_y"], sz)
        if p["seat_r_y"] is not None:
            bw = min(2.0 * xt(p["seat_r_y"]) - 0.06, 1.42)
            self.seat(0.0, p["seat_r_y"], sz + 0.02, width=bw)
        # steering wheel (own object, local Y = column axis)
        sw = self.mb("SteeringWheel")
        r = 0.185
        sw.revolve([(-0.014, r - 0.028), (-0.014, r), (0.014, r), (0.014, r - 0.028)], M["trim"], axis='Y', segs=10, closed=True)
        sw.cyl(0.05, 0.05, (0, 0.01, 0), M["trim"], axis='Y', segments=8)
        for a in (0.0, pi, -pi / 2):
            sw.box((r - 0.04, 0.02, 0.035), (cos(a) * (r / 2), 0.004, sin(a) * (r / 2)), M["trim"], rot=(0, -a, 0))
        sw.cyl(0.028, 0.26, (0, 0.14, 0), I, axis='Y', segments=6)
        self.origins["SteeringWheel"] = ((-sx, p["seat_f_y"] + 0.40, sz + 0.37), (radians(-24), 0, 0))

    def bays(self):
        """Dark surfaces under hood / trunk so seams and opened lids never show through the car."""
        p, M, b = self.p, self.M, self.body
        for rng, kind in ((self.hood, "hood"), (self.trunk, "trunk")):
            if not rng:
                continue
            ys = [y for y in self.ys if rng[0] - 1e-6 <= y <= rng[1] + 1e-6]
            mat = M["under"] if kind == "hood" else M["interior"]
            wx = self.x_well - 0.06
            y0, y1 = rng[0] + 0.07, rng[1] - 0.07
            depth = 0.22 if kind == "hood" else 0.34
            zmin = min(self.zt(y) for y in ys) - 0.045 - depth
            for ya, yb in zip(ys[:-1], ys[1:]):
                za, zb = self.zt(ya) - 0.045, self.zt(yb) - 0.045
                xa, xb = self.belt_x(ya), self.belt_x(yb)
                # outer strips of the lid surface (between the well and the fender)
                b.face([(wx, ya, za), (xa, ya, za), (xb, yb, zb), (wx, yb, zb)], mat, mirror=True, want=(0, 0, 1))
                ca, cb = max(ya, y0), min(yb, y1)
                if ya < y0:
                    b.face([(-wx, ya, za), (wx, ya, za), (wx, min(yb, y0), self._zl(ya, yb, za, zb, min(yb, y0))),
                            (-wx, min(yb, y0), self._zl(ya, yb, za, zb, min(yb, y0)))], mat, want=(0, 0, 1))
                if yb > y1:
                    b.face([(-wx, max(ya, y1), self._zl(ya, yb, za, zb, max(ya, y1))), (wx, max(ya, y1), self._zl(ya, yb, za, zb, max(ya, y1))),
                            (wx, yb, zb), (-wx, yb, zb)], mat, want=(0, 0, 1))
                if cb > ca:     # well side walls
                    zca, zcb = self._zl(ya, yb, za, zb, ca), self._zl(ya, yb, za, zb, cb)
                    b.face([(wx, ca, zmin), (wx, cb, zmin), (wx, cb, zcb), (wx, ca, zca)], mat, mirror=True, want=(-1, 0, 0))
            z0 = self.zt(y0) - 0.045
            z1 = self.zt(y1) - 0.045
            b.face([(-wx, y0, zmin), (wx, y0, zmin), (wx, y0, z0), (-wx, y0, z0)], mat, want=(0, 1, 0))
            b.face([(-wx, y1, zmin), (wx, y1, zmin), (wx, y1, z1), (-wx, y1, z1)], mat, want=(0, -1, 0))
            b.face([(-wx, y0, zmin), (wx, y0, zmin), (wx, y1, zmin), (-wx, y1, zmin)], mat, want=(0, 0, 1))
            if kind == "hood":      # simple engine: block, rocker cover, intake, battery
                ym = (y0 + y1) / 2.0
                ln = min(0.62, (y1 - y0) * 0.7)
                b.box((0.46, ln, depth * 0.62), (0, ym, zmin + depth * 0.31), M["trim"], bevel=0.02)
                b.box((0.30, ln * 0.8, 0.05), (0, ym, zmin + depth * 0.62 + 0.02), M["chrome"], bevel=0.012)
                b.cyl(0.05, ln * 0.7, (wx * 0.62, ym, zmin + depth * 0.45), M["chrome"], axis='Y', segments=8)
                b.box((0.18, 0.24, depth * 0.5), (-wx * 0.66, y0 + 0.16, zmin + depth * 0.25), M["trim"], bevel=0.012)

    @staticmethod
    def _zl(ya, yb, za, zb, y):
        if yb - ya < 1e-9:
            return za
        return za + (zb - za) * (y - ya) / (yb - ya)

    # ---------------------------------------------------------------- fascias
    def u_path(self, front=True, wrap=0.34, grow=0.0):
        """Plan-view bumper path around the nose (left -> right) or the tail (right -> left),
        following the `plan` outline at the swage line.  grow widens it."""
        ye = self.y_f if front else self.y_r
        y0 = ye - wrap if front else ye + wrap
        keys = [y for y, _ in self.plan if min(y0, ye) + 0.02 < y < max(y0, ye) - 0.02]
        ysd = sorted([y0] + keys + [ye], reverse=not front)       # from the wrap end to the end cap
        half = [(self.w(y) + grow, y) for y in ysd]
        if front:
            return [(-x, y) for x, y in half] + [(x, y) for x, y in reversed(half)]
        return [(x, y) for x, y in half] + [(-x, y) for x, y in reversed(half)]

    def front_fascia(self):
        p, M, b = self.p, self.M, self.body
        yf = self.y_f
        wc = self.w(yf)
        zt = self.zt(yf)
        h = p["head"]
        hz = None
        if h:
            hz = h.get("z") or (zt - 0.035 - h["h"] / 2.0)
            hx = self.side_x(yf, hz + h["h"] / 2.0) - h["inset"] - h["w"] / 2.0
            b.box((h["w"], 0.07, h["h"]), (hx, yf + 0.004, hz), M["head"], mirror=True, bevel=0.014)
            b.box((h["w"] + 0.03, 0.05, h["h"] + 0.03), (hx, yf - 0.006, hz), M["trim"], mirror=True)
            self.head_pos = (hx, yf + 0.05, hz)
            gr = p["grille"]
            if gr:
                gx = hx - h["w"] / 2.0 - 0.035
                gh = h["h"] + 0.01
                b.box((2 * gx, 0.05, gh), (0, yf - 0.002, hz), M["trim"])
                b.box((2 * gx + 0.02, 0.06, 0.022), (0, yf + 0.004, hz + gh / 2.0), M["chrome"], bevel=0.006)
                nb = gr.get("bars", 3)
                for i in range(nb):
                    zz = hz - gh / 2.0 + gh * (i + 0.6) / (nb + 0.6)
                    b.box((2 * gx - 0.03, 0.012, 0.014), (0, yf + 0.026, zz), M["chrome"])
                self.grille_box = (gx, hz, gh)
        else:
            self.head_pos = (wc - 0.2, yf + 0.05, zt - 0.1)
        bf = p["bumper_f"]
        if bf:
            z0 = bf.get("z0") or (interp(self.bottom_keys, yf) - 0.03)
            z1 = z0 + bf["h"]
            o = bf["out"]
            prof = [(-0.07, z0), (o * 0.45, z0), (o, z0 + 0.045), (o, z1 - 0.05), (o * 0.5, z1), (-0.07, z1)]
            path = self.u_path(True, bf["wrap"])
            b.sweep(path, prof, M["paint"])
            # lower intake + valance
            iw = wc * 0.58
            b.box((2 * iw, 0.03, bf["h"] * 0.36), (0, yf + o - 0.005, z0 + bf["h"] * 0.36), M["trim"], bevel=0.008)
            b.sweep(self.u_path(True, bf["wrap"] * 0.55), [(-0.07, z0 - 0.035), (o * 0.2, z0 - 0.035), (o * 0.45, z0 + 0.004), (-0.07, z0 + 0.004)], M["trim"])
            # indicators / fog lights in the bumper corners
            ix = wc - 0.13
            b.box((0.15, 0.03, 0.05), (ix, yf + o - 0.004, z1 - 0.085), M["indicator"], mirror=True)
            if p["plate_f"]:
                b.box((0.32, 0.016, 0.12), (0, yf + o + 0.012, z0 + bf["h"] * 0.42), M["plate"])
                b.box((0.35, 0.012, 0.15), (0, yf + o + 0.004, z0 + bf["h"] * 0.42), M["trim"])
            self.bumper_f_z = (z0, z1)

    def rear_fascia(self):
        p, M, b = self.p, self.M, self.body
        yr = self.y_r
        wc = self.w(yr)
        zt = self.zt(yr)
        t = p["tail"]
        if t:
            tz = t.get("z") or (zt - 0.05 - t["h"] / 2.0)
            xo = self.side_x(yr, tz + t["h"] / 2.0) - t["inset"]
            tw = t["w"]
            tx = xo - tw / 2.0
            sub = min(0.10, tw * 0.3)                     # inner column: indicator over reverse light
            b.box((tw - sub, 0.07, t["h"]), (xo - (tw - sub) / 2.0, yr - 0.004, tz), M["tail"], mirror=True, bevel=0.014)
            b.box((sub - 0.012, 0.06, t["h"] / 2.0 - 0.008), (xo - tw + sub / 2.0, yr - 0.004, tz + t["h"] / 4.0), M["indicator"], mirror=True)
            b.box((sub - 0.012, 0.06, t["h"] / 2.0 - 0.008), (xo - tw + sub / 2.0, yr - 0.004, tz - t["h"] / 4.0), M["reverse"], mirror=True)
            b.box((tw + 0.03, 0.05, t["h"] + 0.03), (tx, yr + 0.006, tz), M["trim"], mirror=True)
            self.tail_pos = (tx, yr - 0.05, tz)
            if p["plate_r"]:
                pz = tz - 0.005
                gap = xo - tw - 0.03
                if gap > 0.22:
                    b.box((min(2 * gap, 0.62), 0.03, t["h"] + 0.03), (0, yr + 0.004, pz), M["trim"])
                    b.box((0.32, 0.016, 0.12), (0, yr - 0.018, pz), M["plate"])
                    b.box((min(2 * gap, 0.62) + 0.02, 0.04, 0.02), (0, yr - 0.006, pz + t["h"] / 2.0 + 0.02), M["chrome"], bevel=0.006)
                else:
                    b.box((0.32, 0.016, 0.12), (0, yr - 0.012, tz - t["h"] - 0.02), M["plate"])
        else:
            self.tail_pos = (wc - 0.2, yr - 0.05, zt - 0.1)
        br = p["bumper_r"]
        z0 = interp(self.bottom_keys, yr) - 0.03
        if br:
            z0 = br.get("z0") or z0
            z1 = z0 + br["h"]
            o = br["out"]
            prof = [(-0.07, z0), (o * 0.45, z0), (o, z0 + 0.045), (o, z1 - 0.05), (o * 0.5, z1), (-0.07, z1)]
            b.sweep(self.u_path(False, br["wrap"]), prof, M["paint"])
            b.sweep(self.u_path(False, br["wrap"] * 0.55), [(-0.07, z0 - 0.035), (o * 0.2, z0 - 0.035), (o * 0.45, z0 + 0.004), (-0.07, z0 + 0.004)], M["trim"])
            b.box((0.10, 0.02, 0.035), (wc - 0.16, yr - o + 0.002, z0 + br["h"] * 0.38), M["tail"], mirror=True)   # reflectors
            self.bumper_r_z = (z0, z1)
        ex = p["exhaust"]
        if ex:
            ez = z0 - 0.055
            ey = yr - 0.02
            b.cyl(ex["r"], 0.22, (ex["x"], ey + 0.05, ez), M["chrome"], axis='Y', segments=8)
            b.cyl(ex["r"] * 0.7, 0.02, (ex["x"], ey - 0.055, ez), M["under"], axis='Y', segments=8)
            self.exhaust_pos = (ex["x"], ey - 0.08, ez)
        else:
            self.exhaust_pos = (-0.4, yr - 0.05, z0)

    def details(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy = g["cy"]
        # wipers on the cowl
        for sx in (-1.0, 1.0):
            x0 = sx * 0.08 - 0.30
            b.box((0.46, 0.02, 0.016), (x0 + 0.21, cy + 0.012, g["zc"] + 0.035 + p["crown"] * 0.5), M["trim"], rot=(0, radians(-4), radians(3)))
        # fuel cap (right rear quarter), antenna, side repeaters
        ry = p["axle_r"] + 0.10
        fz = self.arch_z(ry) + 0.12
        if fz < self.zt(ry) - 0.05:
            b.box((0.012, 0.12, 0.10), (self.side_x(ry, fz) + 0.002, ry, fz), M["paint"], bevel=0.004)
        b.cyl(0.008, 0.36, (g["xr"] - 0.12, g["rr"] + 0.02, g["rz"] + 0.14), M["trim"], axis='Z', segments=5, rot=(radians(-28), 0, 0))
        fy = p["axle_f"] - self.Ra - 0.10
        fz2 = p["swage_z"] + 0.09
        if not self._in_door(fy):
            b.box((0.014, 0.07, 0.03), (self.side_x(fy, fz2) + 0.002, fy, fz2), M["indicator"], mirror=True)

    # ---------------------------------------------------------------- doors, hood, trunk
    def closures(self):
        p, M = self.p, self.M
        g2 = p["seam"] / 2.0
        for tag, ya, yb in self.doors:
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                name = "Door_%s%s" % (tag, sfx)
                mb = self.mb(name)
                ys = [ya + g2] + [s for s in self.ys if ya + g2 + 0.02 < s < yb - g2 - 0.02] + [yb - g2]
                rings = []
                for y in ys:
                    S = self.section(y)
                    P1, P2, PSW, PRK = S[2], S[3], S[4], S[5]
                    zlow = PRK[2] + p["seam"]
                    xi = P1[0] - p["door_t"]
                    outer = [P1, P2, PSW, (PRK[0], y, zlow)]
                    outer = [(q[0], y, max(q[2], zlow)) for q in outer]
                    ring = [(xi, y, P1[2])] + outer + [(xi, y, zlow)]
                    rings.append([(side * q[0], q[1], q[2]) for q in ring])
                mb.loft(rings, mats=[M["trim"], M["paint"], M["paint"], M["paint"], M["trim"], M["interior"]], cap_mat=M["trim"])
                # handle
                yh = ya + 0.17
                zh = self.zt(yh) - p["crease_drop"] - 0.05
                mb.box((0.03, 0.15, 0.034), (side * (self.side_x(yh, zh) + 0.010), yh, zh), M["chrome"], bevel=0.008)
                if p["side_strip"]:
                    self._strip_loft(mb, ya + g2 + 0.004, yb - g2 - 0.004, side)
                # armrest / door card detail
                mb.box((0.05, (yb - ya) * 0.55, 0.05), (side * (self.belt_x(yh) - p["door_t"] - 0.02), (ya + yb) / 2.0, self.zt(yh) - 0.30), M["interior"])
                if tag == "F":      # wing mirror
                    ym = yb - 0.11
                    xm = self.belt_x(ym)
                    zm = self.zt(ym)
                    mb.box((0.10, 0.05, 0.035), (side * (xm + 0.035), ym, zm + 0.03), M["trim"])
                    mb.box((0.15, 0.085, 0.10), (side * (xm + 0.125), ym - 0.005, zm + 0.065), M["paint"], bevel=0.018)
                    mb.box((0.125, 0.012, 0.075), (side * (xm + 0.125), ym - 0.05, zm + 0.065), M["chrome"])
                hinge = p["door_hinge"].get(tag, "front")
                hy = (yb - g2) if hinge == "front" else (ya + g2)
                self.origins[name] = ((side * self.side_x(hy, p["swage_z"]), hy, p["rocker_z"] + p["seam"]), None)
        gap = 0.010
        for rng, name in ((self.hood, "Hood"), (self.trunk, "Trunk")):
            if not rng:
                continue
            mb = self.mb(name)
            ya, yb = rng[0] + gap, rng[1] - gap
            ys = [ya] + [s for s in self.ys if ya + 0.02 < s < yb - 0.02] + [yb]
            rings = []
            th = 0.032
            for y in ys:
                zt = self.zt(y)
                x1 = self.belt_x(y) - gap
                cw = min(p["crown_w"], x1 * 0.7)
                cz = zt + p["crown"]
                rings.append([(-x1, y, zt), (-cw, y, cz), (cw, y, cz), (x1, y, zt), (x1, y, zt - th), (-x1, y, zt - th)])
            mb.loft(rings, mats=[M["paint"], M["paint"], M["paint"], M["paint"], M["trim"], M["paint"]], cap_mat=M["paint"])
            hy = ya if name == "Hood" else yb
            self.origins[name] = ((0.0, hy, self.zt(hy)), None)

    # ---------------------------------------------------------------- wheels
    def wheel_positions(self):
        p = self.p
        out = []
        for tag, yc in self.axles:
            for side, sfx in ((-1.0, "L"), (1.0, "R")):
                out.append(("Wheel_%s%s" % (tag, sfx), (side * p["track"] / 2.0, yc, p["wheel_r"])))
        return out

    def wheels(self):
        p = self.p
        build_wheel(self.mb("Wheel"), self.M, p["wheel_r"], p["wheel_w"], p["wheel_style"])

    # ---------------------------------------------------------------- collision, LOD
    def collision(self):
        p, M = self.p, self.M
        g = self._gh()
        cb = self.mb("Col_Body")
        keys = [y for y, _ in self.top]
        zlo = min(z for _, z in self.bottom_keys) + 0.02
        prof = []
        for y in keys:
            prof.append((y, self.zt(y) + (p["crown"] if self.y_r < y < self.y_f else 0.0)))
        low = [(self.y_f, max(interp(self.bottom_keys, self.y_f), zlo)), (self.y_f - 0.30, zlo), (self.y_r + 0.30, zlo),
               (self.y_r, max(interp(self.bottom_keys, self.y_r), zlo))]
        poly = prof + low
        wmax = self.hw * 0.985
        cb.loft([[(-wmax, y, z) for y, z in poly], [(wmax, y, z) for y, z in poly]], M["col"])
        cc = self.mb("Col_Cabin")
        zb = min(g["zc"], g["zd"]) - 0.03
        cc.loft([[(-g["xd"], g["dy"], zb), (g["xd"], g["dy"], zb), (g["xc"], g["cy"], zb), (-g["xc"], g["cy"], zb)],
                 [(-g["xr"], g["rr"], g["rz"]), (g["xr"], g["rr"], g["rz"]), (g["xr"], g["rf"], g["rz"]), (-g["xr"], g["rf"], g["rz"])]], M["col"])

    def lod(self):
        p, M = self.p, self.M
        g = self._gh()
        lb = self.mb("Body_LOD1")
        ys = [y for y, _ in self.top] + [y for y, _ in self.plan] + [p["cowl_y"], p["deck_y"]]
        for _, yc in self.axles:
            ys += [y for y, _ in self._arch_samples(yc, n=3)]
        ys = sorted(set(round(y, 4) for y in ys if self.y_r - 1e-6 <= y <= self.y_f + 1e-6))
        idx = (self.C0, self.P1, self.PSW, self.PSL, self.F0)
        S = [[self.section(y)[i] for i in idx] for y in ys]
        mats = [M["paint"], M["paint"], M["paint"], M["trim"]]
        for A, B in zip(S[:-1], S[1:]):
            for k in range(4):
                lb.face([A[k], A[k + 1], B[k + 1], B[k]], mats[k], mirror=True)
        lb.face(S[-1], M["paint"], mirror=True, want=(0, 1, 0))
        lb.face(S[0], M["paint"], mirror=True, want=(0, -1, 0))
        cy, dy, xc, zc, xd, zd, xr, rz, rf, rr = (g[k] for k in ("cy", "dy", "xc", "zc", "xd", "zd", "xr", "rz", "rf", "rr"))
        lb.face([(-xc, cy, zc), (xc, cy, zc), (xr, rf, rz), (-xr, rf, rz)], M["glass"], want=(0, 1, 1))
        lb.face([(-xd, dy, zd), (xd, dy, zd), (xr, rr, rz), (-xr, rr, rz)], M["glass"], want=(0, -1, 1))
        lb.face([(xd, dy, zd), (xc, cy, zc), (xr, rf, rz), (xr, rr, rz)], M["glass"], mirror=True, want=(1, 0, 0.2))
        lb.face([(-xr, rr, rz), (xr, rr, rz), (xr, rf, rz), (-xr, rf, rz)], self._mat(p["roof_mat"]), want=(0, 0, 1))
        if p["head"]:
            hx, hy, hz = self.head_pos
            lb.box((p["head"]["w"], 0.04, p["head"]["h"]), (hx, self.y_f, hz), M["head"], mirror=True)
        if p["tail"]:
            tx, ty, tz = self.tail_pos
            lb.box((p["tail"]["w"], 0.04, p["tail"]["h"]), (tx, self.y_r, tz), M["tail"], mirror=True)

    # ---------------------------------------------------------------- mod parts
    def mods(self):
        fn = {"Mod_Spoiler_A": self.mod_spoiler_lip, "Mod_Spoiler_B": self.mod_spoiler_wing,
              "Mod_BumperF_A": self.mod_bumper_f, "Mod_BumperR_A": self.mod_bumper_r, "Mod_Hood_A": self.mod_hood,
              "Mod_Skirts_A": self.mod_skirts, "Mod_Roof_A": self.mod_roof, "Mod_Exhaust_A": self.mod_exhaust,
              "Mod_Grille_A": self.mod_grille}
        for name in self.p["mods"]:
            if name in fn:
                fn[name](self.mb(name))

    def _spoiler_base(self):
        """(y of the trailing edge, z(y) of the surface, half width) for spoilers: deck or roof."""
        p = self.p
        if p["spoiler_at"] == "roof" or not self.trunk and p["spoiler_at"] == "auto":
            g = self._gh()
            return g["rr"] - 0.045, (lambda y: g["rz"] - 0.04), g["xr"] - 0.02
        y1 = self.y_r + 0.012
        return y1, (lambda y: self.zt(y) + p["crown"]), self.belt_x(y1) - 0.012

    def mod_spoiler_lip(self, mb):
        """Ducktail lip on the trailing edge of the deck (or roof, params["spoiler_at"])."""
        M = self.M
        y1, zf, hx = self._spoiler_base()
        y0 = y1 + 0.24
        secs = []
        for x, dz, k in ((-1.0, -0.03, 0.75), (-0.82, 0.0, 1.0), (0.82, 0.0, 1.0), (1.0, -0.03, 0.75)):
            xx = x * hx
            z0, z1 = zf(y0) + dz, zf(y1) + dz
            secs.append([(xx, y0, z0 - 0.012), (xx, y1 - 0.02, z1 - 0.012), (xx, y1 - 0.045, z1 + 0.085 * k),
                         (xx, y1 - 0.005, z1 + 0.09 * k), (xx, y0, z0 + 0.012)])
        mb.loft(secs, M["paint"])

    def mod_spoiler_wing(self, mb):
        """Raised wing on two uprights with end plates."""
        M = self.M
        y1, zf, hx0 = self._spoiler_base()
        yw = y1 + 0.19
        zd = zf(yw)
        zw = zd + 0.27
        hx = hx0 + 0.04
        prof = [(yw + 0.15, zw - 0.012), (yw + 0.06, zw + 0.026), (yw - 0.12, zw + 0.052), (yw - 0.155, zw + 0.045), (yw - 0.03, zw + 0.002)]
        mb.prism(prof, -hx, hx, M["paint"], axis='X')
        for sx in (-1.0, 1.0):
            mb.box((0.022, 0.36, 0.13), (sx * hx, yw - 0.005, zw + 0.03), self._mat("paint2"), bevel=0.006)
            xu = sx * hx * 0.55
            mb.loft([[(xu - 0.016, yw + 0.10, zd - 0.01), (xu + 0.016, yw + 0.10, zd - 0.01), (xu + 0.016, yw - 0.06, zd - 0.01), (xu - 0.016, yw - 0.06, zd - 0.01)],
                     [(xu - 0.016, yw + 0.05, zw + 0.01), (xu + 0.016, yw + 0.05, zw + 0.01), (xu + 0.016, yw - 0.07, zw + 0.02), (xu - 0.016, yw - 0.07, zw + 0.02)]], M["trim"])

    def mod_bumper_f(self, mb):
        """Sport front: deeper air dam, splitter blade and corner canards."""
        p, M = self.p, self.M
        z0, z1 = getattr(self, "bumper_f_z", (0.27, 0.49))
        o = (p["bumper_f"] or {}).get("out", 0.05)
        wrap = (p["bumper_f"] or {}).get("wrap", 0.34)
        path = self.u_path(True, wrap * 0.9, grow=0.004)
        mb.sweep(path, [(-0.05, z0 - 0.07), (o + 0.02, z0 - 0.07), (o + 0.035, z0 + 0.02), (o + 0.012, z0 + 0.10), (-0.05, z0 + 0.10)], M["paint"])
        mb.sweep(self.u_path(True, wrap * 0.8, grow=0.0), [(-0.05, z0 - 0.095), (o + 0.11, z0 - 0.095), (o + 0.11, z0 - 0.072), (-0.05, z0 - 0.072)], M["trim"])
        wc = self.w(self.y_f)
        mb.box((wc * 0.9, 0.03, 0.07), (0, self.y_f + o + 0.022, z0 - 0.015), M["trim"], bevel=0.008)
        for sx in (-1.0, 1.0):
            mb.box((0.02, 0.22, 0.012), (sx * (wc + 0.055), self.y_f - 0.06, z0 + 0.14), M["trim"], rot=(radians(12), 0, sx * radians(-24)))

    def mod_bumper_r(self, mb):
        """Rear diffuser with fins under the bumper."""
        p, M = self.p, self.M
        z0, z1 = getattr(self, "bumper_r_z", (0.31, 0.53))
        o = (p["bumper_r"] or {}).get("out", 0.05)
        wrap = (p["bumper_r"] or {}).get("wrap", 0.34)
        mb.sweep(self.u_path(False, wrap * 0.85, grow=0.004), [(-0.05, z0 - 0.09), (o + 0.012, z0 - 0.09), (o + 0.03, z0 + 0.03), (o + 0.012, z0 + 0.09), (-0.05, z0 + 0.09)], M["paint"])
        wc = self.w(self.y_r)
        mb.box((wc * 1.25, 0.05, 0.09), (0, self.y_r - o - 0.008, z0 - 0.045), M["trim"], bevel=0.01)
        n = 4
        for i in range(n):
            x = (i - (n - 1) / 2.0) * (wc * 1.0 / n)
            mb.box((0.016, 0.20, 0.085), (x, self.y_r - o + 0.03, z0 - 0.06), self._mat("paint2"), rot=(radians(-10), 0, 0))

    def mod_hood(self, mb):
        """Hood scoop."""
        p, M = self.p, self.M
        if not self.hood:
            return
        ya = self.hood[0] + (self.hood[1] - self.hood[0]) * 0.22
        yb = self.hood[0] + (self.hood[1] - self.hood[0]) * 0.80
        cr = p["crown"]
        hw0, hw1 = 0.26, 0.20
        za, zb = self.zt(ya) + cr, self.zt(yb) + cr
        hgt = 0.075
        mb.loft([[(-hw0, ya, za - 0.01), (hw0, ya, za - 0.01), (hw0 - 0.03, ya - 0.02, za + hgt), (-hw0 + 0.03, ya - 0.02, za + hgt)],
                 [(-hw1, yb, zb - 0.01), (hw1, yb, zb - 0.01), (hw1 - 0.03, yb - 0.03, zb + hgt * 0.75), (-hw1 + 0.03, yb - 0.03, zb + hgt * 0.75)]], M["paint"])
        mb.box((hw1 * 2 - 0.09, 0.02, hgt * 0.5), (0, yb - 0.012, zb + hgt * 0.36), M["trim"], rot=(radians(-18), 0, 0))

    def mod_skirts(self, mb):
        """Side skirts between the wheel arches."""
        p, M = self.p, self.M
        ya = p["axle_r"] + self.Ra + 0.035
        yb = p["axle_f"] - self.Ra - 0.035
        rk = p["rocker_z"]
        for sx in (1.0, -1.0):
            secs = []
            for y, k in ((ya, 0.55), (ya + 0.10, 1.0), (yb - 0.10, 1.0), (yb, 0.55)):
                x = self.side_x(y, rk)
                zb_ = interp(self.bottom_keys, y)
                secs.append([(sx * (x - 0.05), y, zb_ - 0.045), (sx * (x + 0.03 * k), y, zb_ - 0.045), (sx * (x + 0.045 * k), y, zb_ + 0.02),
                             (sx * (x + 0.02 * k), y, rk - 0.01), (sx * (x - 0.05), y, rk - 0.01)])
            mb.loft(secs, M["paint"])

    def mod_roof(self, mb):
        """Roof rack with a slim cargo box."""
        p, M = self.p, self.M
        g = self._gh()
        rz, xr, rf, rr = g["rz"], g["xr"], g["rf"], g["rr"]
        ln = rf - rr
        ys = (rr + ln * 0.22, rr + ln * 0.78)
        for y in ys:
            mb.box((2 * xr + 0.04, 0.045, 0.028), (0, y, rz + 0.075), M["trim"], bevel=0.008)
            for sx in (-1.0, 1.0):
                mb.box((0.05, 0.07, 0.085), (sx * (xr - 0.035), y, rz + 0.025), M["trim"], bevel=0.01)
        bw, bl = xr * 0.62, ln * 0.92
        yc = (rf + rr) / 2.0 - 0.03
        z0 = rz + 0.09
        mb.loft([[(-bw * 0.8, yc - bl / 2, z0 + 0.02), (bw * 0.8, yc - bl / 2, z0 + 0.02), (bw * 0.7, yc - bl / 2 + 0.03, z0 + 0.16), (-bw * 0.7, yc - bl / 2 + 0.03, z0 + 0.16)],
                 [(-bw, yc - bl * 0.2, z0), (bw, yc - bl * 0.2, z0), (bw * 0.9, yc - bl * 0.2, z0 + 0.20), (-bw * 0.9, yc - bl * 0.2, z0 + 0.20)],
                 [(-bw, yc + bl * 0.2, z0), (bw, yc + bl * 0.2, z0), (bw * 0.9, yc + bl * 0.2, z0 + 0.18), (-bw * 0.9, yc + bl * 0.2, z0 + 0.18)],
                 [(-bw * 0.7, yc + bl / 2, z0 + 0.03), (bw * 0.7, yc + bl / 2, z0 + 0.03), (bw * 0.6, yc + bl / 2 - 0.05, z0 + 0.10), (-bw * 0.6, yc + bl / 2 - 0.05, z0 + 0.10)]],
                self._mat("paint2"))
        mb.box((2 * bw + 0.012, bl * 0.5, 0.02), (0, yc, z0 + 0.09), M["trim"])

    def mod_exhaust(self, mb):
        """Twin big-bore tail pipes on both sides."""
        p, M = self.p, self.M
        z0 = getattr(self, "bumper_r_z", (0.31, 0.53))[0]
        wc = self.w(self.y_r)
        for sx in (-1.0, 1.0):
            for dx in (-0.055, 0.055):
                x = sx * (wc * 0.62) + dx
                mb.cyl(0.046, 0.26, (x, self.y_r + 0.04, z0 - 0.035), M["chrome"], axis='Y', segments=10, radius2=0.040)
                mb.cyl(0.034, 0.02, (x, self.y_r - 0.085, z0 - 0.035), M["under"], axis='Y', segments=10)
            mb.box((0.26, 0.12, 0.03), (sx * (wc * 0.62), self.y_r + 0.08, z0 + 0.012), M["trim"])

    def mod_grille(self, mb):
        """Sport grille: chrome surround, black mesh bars and a centre badge."""
        p, M = self.p, self.M
        gx, gz, gh = getattr(self, "grille_box", (0.34, self.zt(self.y_f) - 0.1, 0.13))
        yf = self.y_f
        mb.box((2 * gx + 0.03, 0.045, gh + 0.03), (0, yf + 0.022, gz), M["chrome"], bevel=0.01)
        mb.box((2 * gx - 0.02, 0.02, gh - 0.02), (0, yf + 0.042, gz), M["under"])
        n = 7
        for i in range(n):
            x = (i - (n - 1) / 2.0) * ((2 * gx - 0.06) / (n - 1))
            mb.box((0.014, 0.014, gh - 0.025), (x, yf + 0.054, gz), M["trim"])
        mb.box((2 * gx - 0.02, 0.016, 0.016), (0, yf + 0.056, gz), M["chrome"])
        mb.box((0.09, 0.02, 0.06), (0, yf + 0.062, gz), self._mat("paint2"), bevel=0.012)

    def light_bar(self, y=None, width=None, mb=None, base="trim"):
        """Roof light bar (M_Siren_Red left / M_Siren_Blue right) for emergency vehicles.  Call it
        before finish(); set params["siren"]=True to get the `Siren` marker as well."""
        g = self._gh()
        mb = mb or self.body
        y = (g["rf"] + g["rr"]) / 2.0 + 0.15 if y is None else y
        wd = width or (2.0 * g["xr"] - 0.16)
        red = G.mat("M_Siren_Red", G.pal("SirenRed"), rough=0.2)
        blue = G.mat("M_Siren_Blue", G.pal("SirenBlue"), rough=0.2)
        z = g["rz"]
        mb.box((wd, 0.20, 0.035), (0, y, z + 0.035), self._mat(base), bevel=0.008)
        for sx in (-1.0, 1.0):
            mb.box((0.05, 0.10, 0.05), (sx * wd * 0.36, y, z + 0.0), self._mat(base))
            mb.box((wd * 0.40, 0.17, 0.085), (sx * wd * 0.27, y, z + 0.09), red if sx < 0 else blue, bevel=0.02)
        mb.box((wd * 0.12, 0.15, 0.075), (0, y, z + 0.085), self.M["chrome"], bevel=0.012)
        self.siren_pos = (0.0, y, z + 0.11)

    # ---------------------------------------------------------------- markers
    def markers(self):
        p = self.p
        r = self.root
        sx, sz = p["seat_x"], p["seat_z"]
        G.empty(self.n("Seat_Driver"), r, (-sx, p["seat_f_y"], sz))
        G.empty(self.n("Seat_Passenger_1"), r, (sx, p["seat_f_y"], sz))
        ex = self.hw + 0.75
        fy = p["seat_f_y"] + 0.15
        if self.doors:
            fy = (self.doors[0][1] + self.doors[0][2]) / 2.0
        G.empty(self.n("Exit_Driver"), r, (-ex, fy, 0.0))
        G.empty(self.n("Exit_Passenger_1"), r, (ex, fy, 0.0))
        if p["seat_r_y"] is not None:
            ry = p["seat_r_y"] + 0.15
            if len(self.doors) >= 2:
                ry = (self.doors[1][1] + self.doors[1][2]) / 2.0
            G.empty(self.n("Seat_Passenger_2"), r, (-sx, p["seat_r_y"], sz + 0.02))
            G.empty(self.n("Seat_Passenger_3"), r, (sx, p["seat_r_y"], sz + 0.02))
            G.empty(self.n("Exit_Passenger_2"), r, (-ex, ry, 0.0))
            G.empty(self.n("Exit_Passenger_3"), r, (ex, ry, 0.0))
        hx, hy, hz = getattr(self, "head_pos", (self.hw - 0.25, self.y_f, 0.6))
        tx, ty, tz = getattr(self, "tail_pos", (self.hw - 0.25, self.y_r, 0.8))
        G.empty(self.n("Light_Head_L"), r, (-hx, hy, hz))
        G.empty(self.n("Light_Head_R"), r, (hx, hy, hz))
        G.empty(self.n("Light_Tail_L"), r, (-tx, ty, tz), rotation=(0, 0, pi))
        G.empty(self.n("Light_Tail_R"), r, (tx, ty, tz), rotation=(0, 0, pi))
        G.empty(self.n("Exhaust"), r, getattr(self, "exhaust_pos", (-0.4, self.y_r, 0.3)), rotation=(0, 0, pi))
        ey = p["engine_y"]
        if ey is None:
            ey = (self.hood[0] + self.hood[1]) / 2.0 if self.hood else p["axle_f"]
        G.empty(self.n("Engine"), r, (0.0, ey, self.zt(ey) + 0.02))
        if p["siren"]:
            g = self._gh()
            G.empty(self.n("Siren"), r, getattr(self, "siren_pos", (0.0, (g["rf"] + g["rr"]) / 2.0, g["rz"] + 0.10)))

    # ---------------------------------------------------------------- assembly
    def build(self):
        self.skin()
        self.greenhouse()
        self.interior()
        self.bays()
        self.front_fascia()
        self.rear_fascia()
        self.details()
        self.closures()
        self.wheels()
        self.collision()
        self.lod()
        self.mods()
        return self

    def finish(self):
        """Turn every mesh builder into its Blender object, add markers, hide helper meshes."""
        r = self.root
        obs = self.objects
        obs["Body"] = self.body.obj(self.n("Body"), r)
        wheel_mb = self.parts.pop("Wheel", None)
        for name, mb in list(self.parts.items()):
            if mb.empty():
                continue
            ob = mb.obj(self.n(name), r)
            if name in self.origins:
                loc, rot = self.origins[name]
                if name == "SteeringWheel":
                    ob.location = loc
                    ob.rotation_euler = rot
                else:
                    G.set_origin(ob, loc)
            obs[name] = ob
        if wheel_mb is not None:
            first = None
            for name, loc in self.wheel_positions():
                if first is None:
                    first = wheel_mb.obj(self.n(name), r, smooth=35.0)
                    first.data.name = self.n("Wheel")
                    ob = first
                else:
                    ob = bpy.data.objects.new(self.n(name), first.data)
                    for c in r.users_collection:
                        c.objects.link(ob)
                        break
                    ob.parent = r
                ob.location = loc
                obs[name] = ob
        self.markers()
        bpy.context.view_layer.update()
        for name, ob in obs.items():
            if name.startswith(("Mod_", "Col_")) or name == "Body_LOD1":
                ob.hide_render = True           # G.preview skips them
                try:
                    ob.hide_set(True)           # eye icon only: still evaluated, still exported
                except Exception:
                    pass
                if name.startswith("Col_"):
                    ob.display_type = 'WIRE'
        self.parts = {}
        return self.root

    def report(self):
        """Per-object triangle counts (prints and returns a dict)."""
        out = {}
        for o in G.children_of(self.root):
            if o.type == 'MESH':
                o.data.calc_loop_triangles()
                out[short_name(o)] = len(o.data.loop_triangles)
        vis = sum(n for k, n in out.items() if not (k.startswith(("Mod_", "Col_")) or k == "Body_LOD1"))
        print("TRIS %s: visible=%d  all=%d  %s" % (self.name, vis, sum(out.values()), out))
        return out


def build_car(params=None, location=(0, 0, 0), collection="Vehicles/Cars", extras=None):
    """One-call builder.  extras(car) is called before finish() so you can add your own geometry."""
    car = Car(params, location, collection)
    car.build()
    if extras:
        extras(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# export + QA helpers
# ------------------------------------------------------------------------------------------------
def strip_glb_prefix(path, prefix):
    """Rewrite the JSON chunk of a .glb: remove `prefix` from node and mesh names.
    Needed because Blender object names are global: twenty vehicles cannot all own an object
    called 'Body', so parts are named '<asset>:<part>' in the .blend and cleaned here."""
    import json
    import os
    import struct
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise RuntimeError("not a GLB: %s" % path)
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    if ctype != b"JSON":
        raise RuntimeError("unexpected first chunk in %s" % path)
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    rest = data[20 + clen:]
    count = 0
    for key in ("nodes", "meshes"):
        for item in js.get(key, []):
            nm = item.get("name", "")
            if nm.startswith(prefix):
                item["name"] = nm[len(prefix):]
                count += 1
    out = json.dumps(js, separators=(",", ":")).encode("utf-8")
    out += b" " * ((4 - len(out) % 4) % 4)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", version, 12 + 8 + len(out) + len(rest)))
        f.write(struct.pack("<I4s", len(out), b"JSON"))
        f.write(out)
        f.write(rest)
    os.replace(tmp, path)
    return count


def export_glb(root_name, rel_path):
    """G.export_glb + strip the '<asset>:' prefix so the GLB carries the clean contract names
    (Body, Wheel_FL ...).  ALWAYS export vehicles through this function."""
    path = G.export_glb(root_name, rel_path)
    n = strip_glb_prefix(path, root_name + NAME_SEP)
    print("GLB_NAMES_CLEANED: %d names in %s" % (n, path))
    return path


def preview_mods(root_name, out_name, mods=None, views=("three_quarter", "rear_quarter", "side", "front"), res=420):
    """Preview with Mod_* parts visible (all, or only the listed contract names); restores visibility."""
    root = bpy.data.objects.get(root_name)
    saved = []
    try:
        for o in G.children_of(root):
            sn = short_name(o)
            if o.type == 'MESH' and sn.startswith("Mod_") and (mods is None or sn in mods):
                saved.append((o, o.hide_render))
                o.hide_render = False
        return G.preview(root_name, out_name, views=views, res=res)
    finally:
        for o, hr in saved:
            o.hide_render = hr


def preview_only(root_name, out_name, names, views=("three_quarter", "rear_quarter", "side", "top"), res=420):
    """Preview only the listed child parts of an asset (LOD, collision helpers, single parts)."""
    root = bpy.data.objects.get(root_name)
    saved = []
    try:
        for o in G.children_of(root):
            if o.type == 'MESH':
                saved.append((o, o.hide_render))
                o.hide_render = short_name(o) not in names
        return G.preview(root_name, out_name, views=views, res=res)
    finally:
        for o, hr in saved:
            o.hide_render = hr


def check_contract(root_name, mods=FULL_MODS, doors=("Door_FL", "Door_FR", "Door_RL", "Door_RR"), rear_seats=True):
    """Print which contract nodes are present / missing under an asset root."""
    root = bpy.data.objects.get(root_name)
    have = {short_name(o) for o in root.children}
    need = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel", "Hood", "Trunk",
            "Glass_Windshield", "Glass_Rear", "Glass_L", "Glass_R", "Seat_Driver", "Seat_Passenger_1",
            "Exit_Driver", "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L", "Light_Tail_R",
            "Exhaust", "Engine", "Col_Body", "Col_Cabin", "Body_LOD1"] + list(doors) + list(mods)
    if rear_seats:
        need += ["Seat_Passenger_2", "Seat_Passenger_3", "Exit_Passenger_2", "Exit_Passenger_3"]
    missing = [n for n in need if n not in have]
    bad = sorted(o.name for o in root.children if not o.name.startswith(root_name + NAME_SEP))
    print("CONTRACT %s: %d children, missing=%s, badly_named=%s" % (root_name, len(have), missing, bad))
    return missing, bad
