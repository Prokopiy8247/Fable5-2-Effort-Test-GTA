"""props_street - Halcyon Bay street furniture (STREET FURNITURE ARTIST).

Reproducible builder for every prop exported to gta/generated/models/props/<id>.glb and listed in
gta/generated/models/props/manifest_street.json. Run inside the master .blend through the Blender
MCP `execute_blender_code` tool:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for q in (P, P + r"\\assets"):
        if q not in sys.path: sys.path.append(q)
    import gta_bl as G; importlib.reload(G); G.assert_master()
    import props_street as S; importlib.reload(S)
    S.build("bench")            # (re)build one prop at its slot
    S.preview("bench")          # contact sheet -> qa/blender_previews/prop_bench.png
    S.export("bench")           # validate + export GLB (+ node-name patch)
    S.build_all(); S.export_all(); S.write_manifest(); G.save()

Conventions (docs/ARCHITECTURE.md 8.1 / 8.4, docs/PROPS_STREET.md):
  * collection GTA_GODOT/StreetProps, slot region 'props' indices 0-83
  * origin = bottom centre on the ground (wall-mounted props: centre of the wall plate), front = +Y
  * root Empty named like the prop, ONE joined mesh child 'Mesh' (+ extra children where parts move
    or light up, + marker empties)
  * Blender object names are unique per file, so children are named '<prop>.<Part>' in the .blend
    and export() rewrites the GLB node names to the bare contract names ('Mesh', 'Lamp_Red', ...).
"""
import bpy
import bmesh
import math
import os
import json
import struct
import random
from mathutils import Vector, Matrix, Euler

import gta_bl as G

COLL = "StreetProps"
REGION = "props"
SEP = "."
PREVIEW_PREFIX = "prop_"

# id -> dict(slot, category, physics, mass, surface, anchor, notes)
REG = {}
BUILDERS = {}
ORDER = []


def prop(pid, slot, category, physics, mass, surface, anchor="ground", **extra):
    def deco(fn):
        info = dict(slot=slot, category=category, physics=physics, mass=mass, surface=surface, anchor=anchor)
        info.update(extra)
        REG[pid] = info
        BUILDERS[pid] = fn
        if pid not in ORDER:
            ORDER.append(pid)
        return fn
    return deco


# ------------------------------------------------------------------------------------------------
# materials (shared palette materials; one per colour)
# ------------------------------------------------------------------------------------------------
_PARAMS = {  # palette key -> (roughness, metallic)
    "Steel": (0.45, 0.35), "SteelDark": (0.5, 0.35), "Chrome": (0.25, 0.8), "Rim": (0.35, 0.6),
    "Charcoal": (0.6, 0.15), "Black": (0.6, 0.0), "Trim": (0.5, 0.1), "Tire": (0.9, 0.0),
    "Rust": (0.85, 0.2), "Brass": (0.4, 0.7), "Concrete": (0.9, 0.0), "ConcreteDark": (0.9, 0.0),
    "Curb": (0.9, 0.0), "Sidewalk": (0.9, 0.0), "Wood": (0.8, 0.0), "WoodDark": (0.8, 0.0),
}


def _dim(key, f):
    c = G.pal(key)
    return (c[0] * f, c[1] * f, c[2] * f)


def M(key):
    """Material for a palette key ('Steel' -> P_Steel) or one of the contract names below."""
    if key == "M_LampGlow":
        c = G.pal("LampWarm")
        return G.mat("M_LampGlow", c, rough=0.4, emit=c, emit_strength=3.0)
    if key == "M_Glass":
        return G.mat("M_Glass", G.pal("Window"), rough=0.08, metal=0.0, alpha=0.45)
    if key == "M_ScreenGlow":
        c = G.pal("Sky")
        return G.mat("M_ScreenGlow", c, rough=0.3, emit=c, emit_strength=1.6)
    if key == "M_Billboard_A":
        return G.mat("M_Billboard_A", G.pal("Cream"), rough=0.7)
    if key == "M_Billboard_B":
        return G.mat("M_Billboard_B", G.pal("Navy"), rough=0.7)
    # unlit signal lenses: the game swaps / overrides them with an emissive material when lit
    if key == "M_Signal_Red":
        return G.mat("M_Signal_Red", _dim("SirenRed", 0.30), rough=0.3)
    if key == "M_Signal_Yellow":
        return G.mat("M_Signal_Yellow", _dim("IndicatorAmber", 0.30), rough=0.3)
    if key == "M_Signal_Green":
        return G.mat("M_Signal_Green", _dim("NeonGreen", 0.30), rough=0.3)
    if key.startswith("Neon"):
        return G.pmat(key, rough=0.4, emit_strength=4.0)
    if key in ("SirenBlue", "SirenRed"):
        return G.pmat(key, rough=0.3, emit_strength=1.5)
    r, m = _PARAMS.get(key, (0.7, 0.0))
    return G.pmat(key, rough=r, metal=m)


# ------------------------------------------------------------------------------------------------
# point helpers
# ------------------------------------------------------------------------------------------------
def arc(c, r, a0, a1, n, plane='XZ'):
    """n+1 points on an arc (degrees a0..a1) around centre c in a plane ('XZ', 'YZ', 'XY')."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        ca, sa = math.cos(a) * r, math.sin(a) * r
        if plane == 'XZ':
            out.append((c[0] + ca, c[1], c[2] + sa))
        elif plane == 'YZ':
            out.append((c[0], c[1] + ca, c[2] + sa))
        else:
            out.append((c[0] + ca, c[1] + sa, c[2]))
    return out


def ngon(n, r, cx=0.0, cz=0.0, rot=0.0, sx=1.0, sz=1.0):
    """2D regular polygon (list of (u, v)), first vertex at angle `rot` degrees."""
    r0 = math.radians(rot)
    return [(cx + math.cos(r0 + 2 * math.pi * i / n) * r * sx, cz + math.sin(r0 + 2 * math.pi * i / n) * r * sz)
            for i in range(n)]


def rect(w, h, cx=0.0, cz=0.0):
    return [(cx - w / 2, cz - h / 2), (cx + w / 2, cz - h / 2), (cx + w / 2, cz + h / 2), (cx - w / 2, cz + h / 2)]


# ------------------------------------------------------------------------------------------------
# Part: a bmesh under construction with palette-key materials
# ------------------------------------------------------------------------------------------------
class Part:
    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, key):
        m = M(key)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    # --- gta_bl primitives ---------------------------------------------------------------------
    def box(self, size, center, mat, rot=None):
        return G.add_box(self.bm, size, center, rot, self.mi(mat))

    def cyl(self, r, depth, center, mat, axis='Z', seg=10, r2=None, rot=None, cap=True):
        return G.add_cylinder(self.bm, r, depth, center, axis, seg, self.mi(mat), r2, rot, cap)

    def sph(self, r, center, mat, seg=8, rings=5, scale=(1, 1, 1), rot=None):
        return G.add_sphere(self.bm, r, center, seg, rings, self.mi(mat), scale, rot)

    def prism(self, profile, lo, hi, mat, axis='Y'):
        """Extrude a 2D polygon between lo..hi along axis. 'X': (y,z)  'Y': (x,z)  'Z': (x,y)."""
        return G.add_prism(self.bm, profile, lo, hi, axis, self.mi(mat))

    def tbox(self, bottom, top, height, center, mat, top_offset=(0, 0)):
        return G.add_tapered_box(self.bm, bottom, top, height, center, top_offset, self.mi(mat))

    def loft(self, sections, mat, cap_start=True, cap_end=True, close_ring=True):
        return G.add_loft(self.bm, sections, self.mi(mat), cap_start, cap_end, close_ring)

    # --- own builders --------------------------------------------------------------------------
    def _skin(self, rings, mi, closed_path=False, cap_start=True, cap_end=True):
        bm = self.bm
        vr = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(vr[0])
        pairs = list(zip(vr[:-1], vr[1:]))
        if closed_path:
            pairs.append((vr[-1], vr[0]))
        for a_, b_ in pairs:
            for i in range(n):
                j = (i + 1) % n
                f = bm.faces.new((a_[i], a_[j], b_[j], b_[i]))
                f.material_index = mi
        if not closed_path and n >= 3:
            if cap_start:
                bm.faces.new(list(reversed(vr[0]))).material_index = mi
            if cap_end:
                bm.faces.new(vr[-1]).material_index = mi
        return vr

    def tube(self, pts, r, mat, seg=6, closed=False, cap=True, r_end=None, phase=0.0, squash=(1.0, 1.0)):
        """Sweep a circle of radius r (seg sides) along a polyline with mitred corners.
        squash = (scale along the frame normal, scale along the binormal)."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        info = []
        for i in range(n):
            if closed:
                d1 = (pts[i] - pts[(i - 1) % n]).normalized()
                d2 = (pts[(i + 1) % n] - pts[i]).normalized()
            else:
                d1 = (pts[i] - pts[i - 1]).normalized() if i > 0 else None
                d2 = (pts[i + 1] - pts[i]).normalized() if i < n - 1 else None
                if d1 is None:
                    d1 = d2
                if d2 is None:
                    d2 = d1
            t = d1 + d2
            if t.length < 1e-6:
                t = d1.copy()
            t.normalize()
            m = d2 - d1
            ms = 1.0 / max(0.35, t.dot(d1))
            info.append((t, m.normalized() if m.length > 1e-6 else None, ms))
        t0 = info[0][0]
        up = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
        nrm = (up - t0 * up.dot(t0)).normalized()
        prev = t0
        rings = []
        for i, (t, m, ms) in enumerate(info):
            ax = prev.cross(t)
            if ax.length > 1e-6:
                nrm = Matrix.Rotation(prev.angle(t), 3, ax.normalized()) @ nrm
            nrm = (nrm - t * nrm.dot(t)).normalized()
            bn = t.cross(nrm)
            rr = r if r_end is None else r + (r_end - r) * i / max(1, n - 1)
            ring = []
            for k in range(seg):
                a = phase + 2 * math.pi * k / seg
                o = (nrm * (math.cos(a) * squash[0]) + bn * (math.sin(a) * squash[1])) * rr
                if m is not None and ms > 1.0001:
                    o = o + m * (o.dot(m) * (ms - 1.0))
                ring.append(pts[i] + o)
            rings.append(ring)
            prev = t
        return self._skin(rings, self.mi(mat), closed_path=closed, cap_start=cap, cap_end=cap)

    def strut(self, p0, p1, w, mat, h=None, cap=True):
        """Rectangular bar (w wide, h high) from p0 to p1."""
        h = w if h is None else h
        s = math.sqrt(2.0)
        return self.tube([p0, p1], 0.5 * s, mat, seg=4, cap=cap, phase=math.pi / 4, squash=(h, w))

    def lathe(self, profile, mat, seg=12, center=(0, 0, 0), axis='Z', cap=True, mats=None, phase=0.0, squash=(1.0, 1.0)):
        """Revolve a (radius, height) profile around an axis through `center`.
        mats: optional palette key per band (len(profile) - 1)."""
        bm = self.bm
        c = Vector(center)

        def P(rad, h, a):
            u, v = math.cos(a) * rad * squash[0], math.sin(a) * rad * squash[1]
            if axis == 'Z':
                return c + Vector((u, v, h))
            if axis == 'Y':
                return c + Vector((u, h, v))
            return c + Vector((h, u, v))
        rings = []
        for rad, h in profile:
            if rad <= 1e-6:
                rings.append([bm.verts.new(P(0.0, h, 0.0))])
            else:
                rings.append([bm.verts.new(P(rad, h, phase + 2 * math.pi * k / seg)) for k in range(seg)])
        base = self.mi(mat)
        for b in range(len(rings) - 1):
            ra, rb = rings[b], rings[b + 1]
            mi = self.mi(mats[b]) if mats else base
            for i in range(seg):
                j = (i + 1) % seg
                if len(ra) == 1 and len(rb) == 1:
                    continue
                if len(ra) == 1:
                    f = bm.faces.new((ra[0], rb[j], rb[i]))
                elif len(rb) == 1:
                    f = bm.faces.new((ra[i], ra[j], rb[0]))
                else:
                    f = bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
                f.material_index = mi
        if cap:
            if len(rings[0]) > 2:
                bm.faces.new(list(reversed(rings[0]))).material_index = self.mi(mats[0]) if mats else base
            if len(rings[-1]) > 2:
                bm.faces.new(rings[-1]).material_index = self.mi(mats[-1]) if mats else base
        return rings

    def to_object(self, name, parent, bevel=0.0, smooth=None, bevel_angle=50.0):
        ob = G.new_object(name, self.bm, parent=parent, materials=self.mats, weld=0)
        self.bm = None
        if bevel and bevel > 0.0:
            G.bevel(ob, bevel, 1, bevel_angle)
        if smooth is not None:
            G.shade_smooth(ob, smooth)
        return ob


# ------------------------------------------------------------------------------------------------
# Asset: root + joined 'Mesh' + extra children + markers
# ------------------------------------------------------------------------------------------------
def _root_name(pid):
    """Blender name of the root. Normally the prop id; if another author already owns an object of
    that name outside StreetProps we never touch it and use a prefixed name (export() restores it)."""
    ex = bpy.data.objects.get(pid)
    if ex is not None:
        mine = any(c.name == COLL for c in ex.users_collection) and ex.type == 'EMPTY'
        if not mine:
            return "street_" + pid
    return pid


class Asset:
    def __init__(self, pid):
        self.id = pid
        self.rname = _root_name(pid)
        self.root = G.asset_root(self.rname, COLL, G.slot(REGION, REG[pid]["slot"]), rebuild=True)
        self.root["gta_prop_id"] = pid
        self.tmp = []
        self.kids = []
        self.post = []          # callables(mesh_object) run after the join (e.g. fit_uv)

    def part(self):
        return Part()

    def add(self, part, bevel=0.0, smooth=None, bevel_angle=50.0):
        """Finish a Part that will be merged into the joined 'Mesh' child."""
        ob = part.to_object("%s%stmp%d" % (self.id, SEP, len(self.tmp)), self.root, bevel, smooth, bevel_angle)
        self.tmp.append(ob)
        return ob

    def child(self, name, part, bevel=0.0, smooth=None, origin=None, bevel_angle=50.0):
        """Finish a Part as its own named child mesh (moving / lightable parts)."""
        ob = part.to_object(self.id + SEP + name, self.root, bevel, smooth, bevel_angle)
        if origin is not None:
            G.set_origin(ob, origin)
        self.kids.append(ob)
        return ob

    def marker(self, name, loc, rot=(0, 0, 0), size=0.2):
        return G.empty(self.id + SEP + name, self.root, loc, rot, size)

    def finish(self):
        if self.tmp:
            # G.join() reads base.matrix_world before it updates the view layer: freshly created
            # objects still have an identity world matrix there, which would bake the slot offset
            # into the vertices. Evaluate the transforms first.
            bpy.context.view_layer.update()
            mesh = G.join(self.tmp, self.id + SEP + "Mesh")
            self.tmp = []
            return mesh
        return None


# ------------------------------------------------------------------------------------------------
# build / preview / export / manifest
# ------------------------------------------------------------------------------------------------
def build(pid):
    G.object_mode()
    a = Asset(pid)
    BUILDERS[pid](a)
    mesh = a.finish()
    for fn in a.post:
        fn(mesh)
    return a.rname


def fit_uv(ob, mat_name, name="UVMap"):
    """Give the +Y / -Y facing polygons that use material `mat_name` a full 0-1 UV square (u runs
    left-to-right as READ from the side the face looks at, v runs up) so the game can put a
    texture / shader on e.g. a billboard face. Everything else keeps the box-projected UVs."""
    me = ob.data
    slots = [i for i, m in enumerate(me.materials) if m is not None and m.name == mat_name]
    if not slots:
        return 0
    polys = [p for p in me.polygons if p.material_index in slots and abs(p.normal.y) > 0.9]
    if not polys:
        return 0
    xs = [me.vertices[v].co.x for p in polys for v in p.vertices]
    zs = [me.vertices[v].co.z for p in polys for v in p.vertices]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    uvl = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    for p in polys:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = (x1 - co.x) / (x1 - x0) if p.normal.y > 0 else (co.x - x0) / (x1 - x0)
            uvl.data[li].uv = (u, (co.z - z0) / (z1 - z0))
    return len(polys)


def build_many(ids):
    return [build(i) for i in ids]


def build_all():
    return build_many(ORDER)


def root_of(pid):
    for n in (pid, "street_" + pid):
        ob = bpy.data.objects.get(n)
        if ob is not None and ob.get("gta_prop_id") == pid:
            return ob
    return None


def preview(pid, views=("three_quarter", "front", "side", "rear_quarter"), res=420):
    r = root_of(pid)
    return G.preview(r.name, PREVIEW_PREFIX + pid, views=views, res=res)


def preview_group(ids, out_name, views=("three_quarter", "front"), res=512):
    names = [root_of(i).name for i in ids]
    return G.preview(names, out_name, views=views, res=res)


FAMILIES = {
    "signals_lamps": ["wall_lamp", "traffic_light_ped", "street_lamp_b", "street_lamp_a", "traffic_light"],
    "signs": ["sign_stop", "sign_yield", "sign_speed", "sign_noentry", "sign_parking", "sign_oneway", "sign_street"],
    "barriers": ["cone", "delineator", "bollard", "bollard_light", "barrier_plastic", "barrier_concrete",
                 "barrier_fence", "roadblock_police"],
    "road_kit": ["parking_stop", "speed_bump", "curb_corner", "curb_straight", "jersey_end", "guardrail"],
    "furniture_small": ["hydrant", "bin", "parking_meter", "mailbox", "newspaper_box", "planter", "manhole", "drain",
                        "tree_grate"],
    "furniture_large": ["bench", "bench_park", "recycling_bins", "bike_rack", "dumpster", "atm", "vending_machine",
                        "phone_kiosk", "bus_stop"],
    "utilities": ["ac_unit", "vent_pipe", "satellite_dish", "utility_box", "transformer", "fire_escape_ladder",
                  "water_tank", "power_pole"],
    "fences": ["wall_low", "hedge", "fence_metal", "fence_wood", "fence_chainlink", "gate_chainlink"],
    "crates": ["gas_canister", "barrel", "barrel_explosive", "pallet", "trash_bags", "cardboard_boxes", "tire_stack",
               "shopping_cart", "crate_wood", "crate_stack"],
    "signage": ["neon_sign_a", "neon_sign_b", "neon_sign_c", "billboard_roof", "billboard"],
}


def preview_family(family, cols=None, gap=0.5, view=(0.55, 1.0, 0.62), res=1024, cull=False):
    """One contact tile of a whole family: the roots are packed into a grid for the render only and
    put back afterwards (same call). cull=True renders with back-face culling to expose flipped
    normals. Output: qa/blender_previews/props_family_<family>.png"""
    ids = [i for i in FAMILIES[family] if root_of(i) is not None]
    roots = [root_of(i) for i in ids]
    saved = [r.location.copy() for r in roots]
    st = [stats(i) for i in ids]
    cw = max(s[1].x for s in st) + gap
    cd = max(s[1].y for s in st) + gap
    cols = cols or int(math.ceil(math.sqrt(len(ids))))
    base = saved[0].copy()
    sh = bpy.context.scene.display.shading
    old_cull = sh.show_backface_culling
    try:
        for k, (r, s) in enumerate(zip(roots, st)):
            c = (s[2] + s[3]) / 2
            r.location = base + Vector(((k % cols) * cw - c.x, -(k // cols) * cd - c.y, 0.0))
        bpy.context.view_layer.update()
        sh.show_backface_culling = bool(cull)
        return G.preview([r.name for r in roots], "props_family_" + family + ("_cull" if cull else ""),
                         views=(view,), res=res)
    finally:
        sh.show_backface_culling = old_cull
        for r, l in zip(roots, saved):
            r.location = l
        bpy.context.view_layer.update()


def closeup(pid, lo, hi, out=None, views=("three_quarter", "front"), res=512):
    """Preview only the box lo..hi (root space) of a prop - for sign faces, lamp heads, details."""
    r = root_of(pid)
    me = bpy.data.meshes.new("_sp_frame")
    me.from_pydata([tuple(lo), tuple(hi)], [(0, 1)], [])
    ob = bpy.data.objects.new("_sp_frame", me)
    r.users_collection[0].objects.link(ob)
    ob.parent = r
    keep = set(G.children_of(r))
    hidden = []
    try:
        # same temporary render-isolation G.preview() uses (restored below, inside this one call)
        for o in bpy.context.scene.objects:
            if o not in keep and not o.hide_render:
                o.hide_render = True
                hidden.append(o)
        return G.preview([ob.name], out or (PREVIEW_PREFIX + pid + "_closeup"), views=views, res=res, isolate=False)
    finally:
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)


def stats(pid):
    """(tris, size_xyz_blender, min, max, child names) of a built prop, in root space."""
    r = root_of(pid)
    bpy.context.view_layer.update()
    inv = r.matrix_world.inverted()
    tris = 0
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    kids = []
    for o in r.children_recursive:
        kids.append((o.name.split(SEP, 1)[-1], o.type))
        if o.type != 'MESH':
            continue
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        for c in o.bound_box:
            w = inv @ (o.matrix_world @ Vector(c))
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return tris, (mx - mn), mn, mx, kids


def _patch_glb_names(path, rename):
    """Rewrite node names inside a GLB (JSON chunk) according to the dict `rename`."""
    with open(path, 'rb') as f:
        data = f.read()
    magic, ver, total = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF':
        raise RuntimeError("not a GLB: " + path)
    clen, ctype = struct.unpack_from('<II', data, 12)
    if ctype != 0x4E4F534A:
        raise RuntimeError("first GLB chunk is not JSON: " + path)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    rest = data[20 + clen:]
    n = 0
    for node in js.get('nodes', []):
        nm = node.get('name', '')
        if nm in rename:
            node['name'] = rename[nm]
            n += 1
    out = json.dumps(js, separators=(',', ':')).encode('utf-8')
    out += b' ' * ((4 - len(out) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(out) + len(rest)))
        f.write(struct.pack('<II', len(out), 0x4E4F534A))
        f.write(out)
        f.write(rest)
    return n


def export(pid, max_tris=900):
    r = root_of(pid)
    if r is None:
        raise RuntimeError("export: prop %r is not built" % pid)
    res = G.validate(r.name, max_tris=max_tris)
    # 'Mesh' is the contract name of the joined child; here it is '<prop>.Mesh', so the generic
    # placeholder-name check cannot fire. Extra sanity: nothing may sit far away from the root.
    far = max(abs(v) for v in tuple(res.get("min", (0, 0, 0))) + tuple(res.get("max", (0, 0, 0))))
    if far > 12.0:
        raise RuntimeError("export %s: geometry is %.1f m away from its root (bad transform?)" % (pid, far))
    path = G.export_glb(r.name, "props/%s.glb" % pid)
    rename = {r.name: pid}
    for o in r.children_recursive:
        rename[o.name] = o.name.split(SEP, 1)[-1]
    n = _patch_glb_names(path, rename)
    print("PATCHED %s: %d node names" % (pid, n))
    return res


def export_all(ids=None):
    bad = []
    for pid in (ids or ORDER):
        res = export(pid)
        if not res.get("ok", False):
            bad.append((pid, res.get("issues")))
    print("EXPORT_ALL done: %d props, issues: %s" % (len(ids or ORDER), bad))
    return bad


def write_manifest():
    """Write gta/generated/models/props/manifest_street.json from the props that exist in the file."""
    out = []
    for pid in ORDER:
        r = root_of(pid)
        if r is None:
            continue
        info = REG[pid]
        tris, size, mn, mx, kids = stats(pid)
        e = {
            "id": pid, "file": pid + ".glb", "category": info["category"],
            # Godot axes: x = Blender x, y = Blender z (up), z = Blender y (depth)
            "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
            "physics": info["physics"], "mass": info["mass"], "surface": info["surface"],
            "anchor": info["anchor"],
            # AABB centre in Godot axes relative to the origin (Blender (x, y, z) -> Godot (x, z, -y))
            "center": [round((mn.x + mx.x) / 2, 3), round((mn.z + mx.z) / 2, 3), round(-(mn.y + mx.y) / 2, 3)],
            "tris": tris,
            "children": [k for k, t in kids if t == 'MESH'],
            "markers": [k for k, t in kids if t == 'EMPTY'],
        }
        # LOD hint (spec 43 / ARCHITECTURE 10): suggested visibility_range_end in metres
        md = max(size.x, size.y, size.z)
        e["vis_range"] = 70 if md < 1.0 else (120 if md < 2.6 else 260)
        for k in ("collision", "tile", "notes", "emissive"):
            if k in info:
                e[k] = info[k]
        out.append(e)
    path = os.path.join(G.MODELS_DIR, "props", "manifest_street.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"author": "street_furniture", "props": out}, f, indent=1)
    print("MANIFEST:", path, len(out), "props")
    return path


# ================================================================================================
# FAMILY 1 - signals, lamps, signs                                              (slots 0 - 11)
# ================================================================================================
def _visor(p, cx, cy, cz, r=0.15, length=0.2, mat='Black'):
    """Open-bottom hood over a signal lens (C-shaped prism along +Y)."""
    out = arc((cx, 0, cz), r, -25, 205, 4)
    inn = arc((cx, 0, cz), r - 0.02, 205, -25, 4)
    prof = [(q[0], q[2]) for q in out + inn]
    p.prism(prof, cy, cy + length, mat, 'Y')


def _signal_head(bev, plain, lenses, cx, cy, cz, backplate=True):
    """3-lamp vertical head facing +Y. bev: Part for bevelled housings, plain: Part for thin parts,
    lenses: [red, yellow, green] Parts."""
    bev.box((0.34, 0.20, 1.08), (cx, cy, cz), 'Charcoal')
    if backplate:
        plain.box((0.64, 0.02, 1.40), (cx, cy - 0.085, cz), 'Black')
        yb = cy - 0.07
        plain.box((0.64, 0.012, 0.05), (cx, yb, cz + 0.675), 'HazardYellow')
        plain.box((0.64, 0.012, 0.05), (cx, yb, cz - 0.675), 'HazardYellow')
        plain.box((0.05, 0.012, 1.30), (cx - 0.295, yb, cz), 'HazardYellow')
        plain.box((0.05, 0.012, 1.30), (cx + 0.295, yb, cz), 'HazardYellow')
    for k, dz in enumerate((0.34, 0.0, -0.34)):
        _visor(plain, cx, cy + 0.10, cz + dz)
        lenses[k].lathe([(0.115, 0.0), (0.085, 0.028), (0.0, 0.04)],
                        ('M_Signal_Red', 'M_Signal_Yellow', 'M_Signal_Green')[k], seg=8,
                        center=(cx, cy + 0.10, cz + dz), axis='Y', cap=False)


@prop("traffic_light", 0, "signal", "static", 340.0, "metal",
      notes="Pole at the kerb, mast arm reaches 5.3 m toward +X (Godot +X), lamps face +Y (Godot -Z). "
            "Lamp_Red/Lamp_Yellow/Lamp_Green each hold the arm lens and the pole repeater lens; "
            "node origin = arm lens centre. Lens materials M_Signal_* are unlit (dark) by default.")
def b_traffic_light(a):
    p = a.part()
    p.cyl(0.27, 0.10, (0, 0, 0.05), 'ConcreteDark', seg=8)
    p.cyl(0.18, 0.60, (0, 0, 0.40), 'SteelDark', seg=10, r2=0.14)
    p.cyl(0.12, 5.6, (0, 0, 0.7 + 2.8), 'SteelDark', seg=10, r2=0.09)
    p.cyl(0.10, 0.08, (0, 0, 6.34), 'Charcoal', seg=8, r2=0.03)
    p.tube([(0, 0, 5.45), (0.42, 0, 5.98), (1.15, 0, 6.17), (5.3, 0, 6.25)], 0.085, 'SteelDark', seg=8, r_end=0.055)
    p.strut((0.0, 0, 4.9), (1.0, 0, 6.1), 0.055, 'SteelDark')
    a.add(p, smooth=42)
    b = a.part()
    q = a.part()
    lens = [a.part(), a.part(), a.part()]
    _signal_head(b, q, lens, 4.55, 0.20, 6.22, backplate=True)
    q.box((0.10, 0.14, 0.16), (4.55, 0.07, 6.22), 'Charcoal')            # arm clamp
    _signal_head(b, q, lens, 0.0, 0.27, 3.35, backplate=False)
    q.box((0.08, 0.16, 0.08), (0, 0.12, 3.70), 'Charcoal')
    q.box((0.08, 0.16, 0.08), (0, 0.12, 3.00), 'Charcoal')
    b.box((0.34, 0.24, 0.52), (0, -0.21, 1.45), 'Steel')                  # controller cabinet
    q.box((0.28, 0.012, 0.42), (0, -0.335, 1.45), 'SteelDark')
    q.box((0.08, 0.10, 0.10), (0, -0.09, 1.45), 'Charcoal')
    a.add(b, bevel=0.015)
    a.add(q)
    for k, nm in enumerate(("Lamp_Red", "Lamp_Yellow", "Lamp_Green")):
        a.child(nm, lens[k], origin=(4.55, 0.32, 6.22 + (0.34, 0.0, -0.34)[k]))


@prop("traffic_light_ped", 1, "signal", "breakable", 45.0, "metal",
      notes="Pedestrian signal on a post, faces +Y. Lamp_Stop (upper, standing figure) and Lamp_Walk "
            "(lower, walking figure) are separate unlit lens meshes; node origin = lens centre.")
def b_traffic_light_ped(a):
    p = a.part()
    p.cyl(0.13, 0.06, (0, 0, 0.03), 'ConcreteDark', seg=8)
    p.cyl(0.085, 0.30, (0, 0, 0.21), 'SteelDark', seg=8, r2=0.06)
    p.cyl(0.055, 2.55, (0, 0, 0.36 + 1.275), 'SteelDark', seg=8)
    p.cyl(0.06, 0.05, (0, 0, 2.93), 'Charcoal', seg=8, r2=0.02)
    a.add(p, smooth=50)
    b = a.part()
    q = a.part()
    cy, cz = 0.17, 2.50
    b.box((0.34, 0.20, 0.70), (0, cy, cz), 'Charcoal')
    q.box((0.08, 0.12, 0.10), (0, 0.06, cz + 0.18), 'Charcoal')
    q.box((0.08, 0.12, 0.10), (0, 0.06, cz - 0.18), 'Charcoal')
    for dz in (0.165, -0.165):
        q.box((0.26, 0.012, 0.26), (0, cy + 0.10, cz + dz), 'Black')
        q.box((0.32, 0.16, 0.02), (0, cy + 0.17, cz + dz + 0.15), 'Black')        # hood top
        q.box((0.02, 0.16, 0.14), (-0.15, cy + 0.17, cz + dz + 0.08), 'Black')
        q.box((0.02, 0.16, 0.14), (0.15, cy + 0.17, cz + dz + 0.08), 'Black')
    # push button box
    b.box((0.13, 0.09, 0.20), (0, 0.095, 1.10), 'HazardYellow')
    q.cyl(0.03, 0.03, (0, 0.15, 1.08), 'Chrome', axis='Y', seg=8)
    q.box((0.07, 0.012, 0.04), (0, 0.142, 1.16), 'Black')
    a.add(b, bevel=0.012)
    a.add(q)
    yl, t = cy + 0.112, 0.014
    s = a.part()                                                            # standing figure (stop)
    z0 = cz + 0.165
    s.cyl(0.028, t, (0, yl, z0 + 0.075), 'M_Signal_Red', axis='Y', seg=8)
    s.box((0.085, t, 0.085), (0, yl, z0 + 0.005), 'M_Signal_Red')
    s.box((0.03, t, 0.09), (-0.065, yl, z0 + 0.0), 'M_Signal_Red')
    s.box((0.03, t, 0.09), (0.065, yl, z0 + 0.0), 'M_Signal_Red')
    s.box((0.036, t, 0.085), (-0.022, yl, z0 - 0.078), 'M_Signal_Red')
    s.box((0.036, t, 0.085), (0.022, yl, z0 - 0.078), 'M_Signal_Red')
    a.child("Lamp_Stop", s, origin=(0, yl, z0))
    w = a.part()                                                            # walking figure (walk)
    z1 = cz - 0.165
    w.cyl(0.028, t, (-0.012, yl, z1 + 0.078), 'M_Signal_Green', axis='Y', seg=8)
    w.box((0.07, t, 0.09), (0, yl, z1 + 0.008), 'M_Signal_Green', rot=(0, math.radians(-10), 0))
    w.box((0.028, t, 0.10), (0.05, yl, z1 + 0.01), 'M_Signal_Green', rot=(0, math.radians(40), 0))
    w.box((0.028, t, 0.10), (-0.055, yl, z1 + 0.012), 'M_Signal_Green', rot=(0, math.radians(-40), 0))
    w.box((0.034, t, 0.11), (0.04, yl, z1 - 0.078), 'M_Signal_Green', rot=(0, math.radians(-28), 0))
    w.box((0.034, t, 0.11), (-0.04, yl, z1 - 0.078), 'M_Signal_Green', rot=(0, math.radians(28), 0))
    a.child("Lamp_Walk", w, origin=(0, yl, z1))


def _cobra_section(w, h, y, zc):
    return [(-w / 2, y, zc - h / 2), (w / 2, y, zc - h / 2), (w / 2, y, zc + h * 0.1),
            (w * 0.28, y, zc + h / 2), (-w * 0.28, y, zc + h / 2), (-w / 2, y, zc + h * 0.1)]


@prop("street_lamp_a", 2, "lamp", "breakable", 180.0, "metal",
      notes="Tall road lamp; the arm reaches 3.3 m toward +Y (Godot -Z, over the road). Lens = "
            "material M_LampGlow; marker 'Light' just below the lens.")
def b_street_lamp_a(a):
    p = a.part()
    p.cyl(0.27, 0.08, (0, 0, 0.04), 'ConcreteDark', seg=8)
    p.cyl(0.18, 0.95, (0, 0, 0.555), 'SteelDark', seg=10, r2=0.14)
    p.cyl(0.155, 0.05, (0, 0, 1.05), 'Charcoal', seg=10)
    p.cyl(0.12, 6.1, (0, 0, 1.05 + 3.05), 'Steel', seg=10, r2=0.085)
    pts = [(0, 0, 7.0)]
    for i in range(1, 7):
        t = math.radians(90.0 * i / 6)
        pts.append((0, 1.45 * (1 - math.cos(t)), 7.0 + 1.72 * math.sin(t)))
    pts.append((0, 2.25, 8.72))
    p.tube(pts, 0.085, 'Steel', seg=8, r_end=0.055)
    a.add(p, smooth=42)
    h = a.part()
    h.loft([_cobra_section(0.16, 0.13, 2.10, 8.72), _cobra_section(0.42, 0.20, 2.36, 8.72),
            _cobra_section(0.46, 0.21, 3.05, 8.71), _cobra_section(0.26, 0.10, 3.28, 8.72)], 'SteelDark')
    a.add(h, bevel=0.015)
    g = a.part()
    g.tbox((0.30, 0.56), (0.34, 0.60), 0.05, (0, 2.71, 8.565), 'M_LampGlow')
    g.box((0.09, 0.012, 0.42), (0, 0.154, 0.55), 'Charcoal')               # service door on the base
    a.add(g)
    a.marker("Light", (0, 2.71, 8.53))


@prop("street_lamp_b", 3, "lamp", "breakable", 70.0, "metal",
      notes="Promenade / park lamp, 4.6 m. Lantern lens = M_LampGlow; marker 'Light' at the lens centre.")
def b_street_lamp_b(a):
    p = a.part()
    p.lathe([(0.21, 0.0), (0.21, 0.07), (0.14, 0.13), (0.105, 0.55), (0.12, 0.60), (0.075, 0.68), (0.06, 0.78)],
            'Charcoal', seg=10)
    p.cyl(0.058, 2.95, (0, 0, 0.78 + 1.475), 'Charcoal', seg=8, r2=0.045)
    p.lathe([(0.045, 3.72), (0.085, 3.76), (0.085, 3.80), (0.045, 3.84)], 'Teal', seg=8)
    p.lathe([(0.045, 3.84), (0.20, 3.93), (0.20, 3.97), (0.17, 3.97)], 'Charcoal', seg=10)
    p.lathe([(0.32, 4.30), (0.32, 4.335), (0.18, 4.43), (0.06, 4.50), (0.035, 4.58), (0.0, 4.64)], 'Charcoal', seg=10)
    a.add(p, smooth=42)
    g = a.part()
    g.cyl(0.165, 0.33, (0, 0, 4.135), 'M_LampGlow', seg=10, r2=0.215)
    for k in range(5):
        an = 2 * math.pi * (k + 0.5) / 5
        g.strut((math.cos(an) * 0.185, math.sin(an) * 0.185, 3.97), (math.cos(an) * 0.235, math.sin(an) * 0.235, 4.30),
                0.022, 'Charcoal')
    a.add(g)
    a.marker("Light", (0, 0, 4.13))


@prop("wall_lamp", 4, "lamp", "static", 4.0, "metal", anchor="wall",
      notes="Wall-mounted gooseneck lamp. Origin = centre of the wall plate (wall plane y = 0), lamp "
            "hangs 0.56 m out toward +Y. Lens = M_LampGlow; marker 'Light' under the shade.")
def b_wall_lamp(a):
    p = a.part()
    p.tube([(0, 0.03, 0.0), (0, 0.16, 0.06), (0, 0.33, 0.21), (0, 0.48, 0.24), (0, 0.56, 0.15), (0, 0.56, 0.06)],
           0.02, 'Charcoal', seg=6)
    p.lathe([(0.035, 0.07), (0.05, 0.04), (0.075, 0.0), (0.20, -0.09), (0.20, -0.105)], 'Teal', seg=10,
            center=(0, 0.56, 0))
    a.add(p, smooth=42)
    b = a.part()
    b.box((0.15, 0.03, 0.26), (0, 0.015, 0.0), 'Charcoal')
    b.box((0.07, 0.03, 0.07), (0, 0.04, 0.0), 'Charcoal')
    a.add(b, bevel=0.008)
    g = a.part()
    g.cyl(0.17, 0.02, (0, 0.56, -0.098), 'M_LampGlow', seg=10)
    g.sph(0.06, (0, 0.56, -0.10), 'M_LampGlow', seg=6, rings=4)
    a.add(g)
    a.marker("Light", (0, 0.56, -0.14))


# ---- signs -------------------------------------------------------------------------------------
SIGN_Y = 0.040          # back of the sign plate (pole radius 0.036)
SIGN_Z = 2.42           # sign centre height


def _sign_post(p, h=2.95, clamps=(SIGN_Z + 0.18, SIGN_Z - 0.18)):
    p.cyl(0.085, 0.035, (0, 0, 0.0175), 'SteelDark', seg=8)
    p.cyl(0.036, h, (0, 0, h / 2), 'Steel', seg=8)
    for z in clamps:
        p.box((0.10, 0.045, 0.035), (0, 0.012, z), 'SteelDark')


def _sign_plate(q, prof_back, layers):
    """Sign built from stacked prisms: steel back + list of (profile, palette key)."""
    y = SIGN_Y
    q.prism(prof_back, y, y + 0.010, 'Steel', 'Y')
    y += 0.010
    for prof, key in layers:
        q.prism(prof, y, y + 0.008, key, 'Y')
        y += 0.008
    return y


_SEG7 = {0: 'abcdef', 1: 'bc', 2: 'abged', 3: 'abgcd', 4: 'fgbc', 5: 'afgcd', 6: 'afgedc', 7: 'abc', 8: 'abcdefg',
         9: 'abcdfg'}


def _seg7(q, digit, cx, cz, w, h, t, y, d, key):
    """Seven-segment numeral that reads correctly from +Y (the reader's right is -X)."""
    hw, hh = w / 2, h / 2
    S = {'a': ((w, t), (0, hh - t / 2)), 'd': ((w, t), (0, -hh + t / 2)), 'g': ((w, t), (0, 0)),
         'b': ((t, hh), (hw - t / 2, hh / 2)), 'c': ((t, hh), (hw - t / 2, -hh / 2)),
         'e': ((t, hh), (-hw + t / 2, -hh / 2)), 'f': ((t, hh), (-hw + t / 2, hh / 2))}
    for s in _SEG7[digit]:
        (sx, sz), (ox, oz) = S[s]
        q.box((sx, d, sz), (cx - ox, y, cz + oz), key)


@prop("sign_stop", 5, "sign", "breakable", 14.0, "metal", notes="Red octagon with a white raised-hand pictogram.")
def b_sign_stop(a):
    p = a.part()
    _sign_post(p)
    a.add(p, smooth=50)
    q = a.part()
    y = _sign_plate(q, ngon(8, 0.42, 0, SIGN_Z, 22.5), [(ngon(8, 0.42, 0, SIGN_Z, 22.5), 'White'),
                                                        (ngon(8, 0.375, 0, SIGN_Z, 22.5), 'FireRed')])
    yc, d = y + 0.003, 0.006
    q.box((0.20, d, 0.17), (0.0, yc, SIGN_Z - 0.10), 'White')                       # palm
    for i, (x, hh) in enumerate(((0.078, 0.17), (0.026, 0.21), (-0.026, 0.22), (-0.078, 0.18))):
        q.box((0.042, d, hh), (x, yc, SIGN_Z - 0.03 + hh / 2), 'White')
    q.box((0.045, d, 0.15), (0.135, yc, SIGN_Z - 0.06), 'White', rot=(0, math.radians(-35), 0))   # thumb
    q.box((0.13, d, 0.07), (0.0, yc, SIGN_Z - 0.215), 'White')                      # wrist
    a.add(q)


@prop("sign_yield", 6, "sign", "breakable", 12.0, "metal", notes="Inverted white triangle with a red border.")
def b_sign_yield(a):
    p = a.part()
    _sign_post(p)
    a.add(p, smooth=50)
    q = a.part()
    zc = SIGN_Z + 0.08
    _sign_plate(q, ngon(3, 0.52, 0, zc, -90), [(ngon(3, 0.52, 0, zc, -90), 'FireRed'),
                                               (ngon(3, 0.30, 0, zc, -90), 'White')])
    a.add(q)


@prop("sign_speed", 7, "sign", "breakable", 12.0, "metal", notes="Round speed-limit sign, '40' built from geometry.")
def b_sign_speed(a):
    p = a.part()
    _sign_post(p)
    a.add(p, smooth=50)
    q = a.part()
    y = _sign_plate(q, ngon(16, 0.40, 0, SIGN_Z), [(ngon(16, 0.40, 0, SIGN_Z), 'FireRed'),
                                                   (ngon(16, 0.31, 0, SIGN_Z), 'White')])
    _seg7(q, 4, 0.125, SIGN_Z, 0.17, 0.30, 0.045, y + 0.003, 0.006, 'Black')
    _seg7(q, 0, -0.125, SIGN_Z, 0.17, 0.30, 0.045, y + 0.003, 0.006, 'Black')
    a.add(q)


@prop("sign_oneway", 8, "sign", "breakable", 11.0, "metal",
      notes="Double-sided blade on top of the post; the arrow points toward local +X (Godot +X) on both faces.")
def b_sign_oneway(a):
    p = a.part()
    zc = 2.78
    _sign_post(p, h=2.60, clamps=())
    p.box((0.09, 0.07, 0.05), (0, 0, zc - 0.185), 'SteelDark')             # saddle bracket under the blade
    p.box((0.09, 0.05, 0.03), (0, 0, zc + 0.18), 'SteelDark')
    a.add(p, smooth=50)
    q = a.part()
    q.box((0.98, 0.022, 0.34), (0, 0, zc), 'White')
    for s in (1, -1):
        q.box((0.93, 0.008, 0.29), (0, s * 0.013, zc), 'Black')
        q.box((0.50, 0.006, 0.085), (-0.10, s * 0.019, zc), 'White')
        q.prism([(0.14, zc - 0.115), (0.37, zc), (0.14, zc + 0.115)], s * 0.016, s * 0.022, 'White', 'Y')
    a.add(q)


@prop("sign_parking", 9, "sign", "breakable", 12.0, "metal", notes="Blue square with a white geometric 'P'.")
def b_sign_parking(a):
    p = a.part()
    _sign_post(p)
    a.add(p, smooth=50)
    q = a.part()
    y = _sign_plate(q, rect(0.62, 0.62, 0, SIGN_Z), [(rect(0.62, 0.62, 0, SIGN_Z), 'White'),
                                                     (rect(0.56, 0.56, 0, SIGN_Z), 'CarBlue')])
    yc, d = y + 0.003, 0.006
    q.box((0.085, d, 0.40), (0.105, yc, SIGN_Z), 'White')                 # stem (reader's left = +X)
    q.box((0.21, d, 0.075), (0.0, yc, SIGN_Z + 0.1625), 'White')
    q.box((0.21, d, 0.075), (0.0, yc, SIGN_Z - 0.0125), 'White')
    q.box((0.08, d, 0.25), (-0.105, yc, SIGN_Z + 0.075), 'White')
    a.add(q)


@prop("sign_street", 10, "sign", "breakable", 13.0, "metal",
      notes="Two crossed street-name blades (one along X, one along Y) with abstract name blocks.")
def b_sign_street(a):
    p = a.part()
    _sign_post(p, h=2.86, clamps=())
    p.cyl(0.045, 0.06, (0, 0, 2.89), 'SteelDark', seg=8)
    p.cyl(0.045, 0.05, (0, 0, 3.145), 'SteelDark', seg=8)
    p.lathe([(0.04, 3.39), (0.055, 3.43), (0.0, 3.50)], 'SteelDark', seg=8)
    a.add(p, smooth=50)
    q = a.part()
    for axis, zc in (('X', 3.02), ('Y', 3.27)):
        def bx(size, c, key):
            if axis == 'X':
                q.box(size, c, key)
            else:
                q.box((size[1], size[0], size[2]), (c[1], c[0], c[2]), key)
        bx((0.96, 0.024, 0.22), (0, 0, zc), 'Teal')
        for s in (1, -1):
            bx((0.92, 0.006, 0.022), (0, s * 0.013, zc + 0.085), 'White')
            bx((0.92, 0.006, 0.022), (0, s * 0.013, zc - 0.085), 'White')
            for x, w in ((-0.30, 0.20), (-0.04, 0.26), (0.27, 0.16)):
                bx((w, 0.006, 0.075), (x * s, s * 0.013, zc), 'White')
    a.add(q)


@prop("sign_noentry", 11, "sign", "breakable", 12.0, "metal", notes="Red disc with a white bar.")
def b_sign_noentry(a):
    p = a.part()
    _sign_post(p)
    a.add(p, smooth=50)
    q = a.part()
    y = _sign_plate(q, ngon(16, 0.40, 0, SIGN_Z), [(ngon(16, 0.40, 0, SIGN_Z), 'White'),
                                                   (ngon(16, 0.365, 0, SIGN_Z), 'FireRed')])
    q.box((0.52, 0.006, 0.13), (0, y + 0.003, SIGN_Z), 'White')
    a.add(q)


# ================================================================================================
# The other families live in sibling modules (same folder); they register themselves through
# @prop when imported. Reloading this module reloads them too.
# ================================================================================================
FAMILY_MODULES = ("props_street_road", "props_street_furniture", "props_street_utility",
                  "props_street_fences", "props_street_crates", "props_street_signage")


def _load_families():
    import importlib
    for name in FAMILY_MODULES:
        try:
            mod = importlib.import_module(name)
        except ModuleNotFoundError as e:
            if e.name != name:
                raise
            continue
        importlib.reload(mod)


_load_families()
