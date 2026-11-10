"""bikes_boats - two-wheelers and boats for Halcyon Bay.

Author: two-wheel & boat artist; revised by the art-critic pass (jetski deck rebuilt, speedboat
sheer / stripes / strakes / sport arch, bicycle saddle + kickstand, dinghy bow upsweep).
Assets (all exported to gta/generated/models/vehicles/<id>.glb):
    motorcycle   sport-naked motorbike            Vehicles/Motorcycles   slot bikes[0]
    bicycle      urban mountain bike              Vehicles/Motorcycles   slot bikes[1]
    speedboat    7 m open sport boat + outboard   Vehicles/Boats         slot boats[0]
    jetski       3.5 m personal watercraft (stretch) Vehicles/Boats      slot boats[1]
    dinghy       3.6 m inflatable + outboard (stretch) Vehicles/Boats    slot boats[2]

QA: BB.qa(id) / BB.qa_all() (preview sheets), BB.check_normals(id), BB.check_contract(id), and in
Godot `tools/godot.ps1 -Mode script -Script res://gta/code/editor/bb_audit.gd` (contract audit of
the exported GLBs) plus the look-dev scene gta/tests/scenes/bb_showcase.tscn.

Run inside the live master .blend through the Blender MCP:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G)
    G.assert_master()
    import bikes_boats as BB; importlib.reload(BB)
    BB.build_motorcycle(); BB.qa("motorcycle"); BB.export("motorcycle")

Conventions: Blender Z up, nose +Y, right side +X, metres.  Every builder is re-runnable
(asset_root(..., rebuild=True) replaces the previous version of the asset).

Node names: Blender object names are global, so "Body" / "Seat_Driver" of a second vehicle would
become "Body.001" ... in the shared master file.  Objects are therefore named "<asset>:<Part>" in
Blender (same convention as car_kit.py), every object stores its contract name in the custom
property "gta_name", and export() rewrites the node names inside the exported GLB from that
property (see fix_glb_names).  The GLB always carries the exact contract names (Body, Wheel_F ...).
Col_* and Body_LOD1 are hidden in Blender (viewport + render) but always exported.
"""
import bpy
import bmesh
import math
import os
import re
import json
import struct
from mathutils import Vector, Matrix, Euler

import gta_bl as G

PI = math.pi
VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top")

# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
# Contract materials (ARCHITECTURE 8.2).  G.mat() is get-or-create, so if another vehicle artist
# created one of these first, that definition is reused unchanged (one shared material per name).
CONTRACT = {
    "M_Paint_Primary": dict(key="CarRed", rough=0.35, metal=0.15),
    "M_Paint_Secondary": dict(key="CarWhite", rough=0.4, metal=0.1),
    "M_Glass": dict(key="WindowDark", rough=0.08, alpha=0.45),
    "M_Trim": dict(key="Trim", rough=0.65),
    "M_Chrome": dict(key="Chrome", rough=0.2, metal=0.9),
    "M_Interior": dict(key="Interior", rough=0.8),
    "M_Underbody": dict(key="Black", rough=0.9),
    "M_Plate": dict(key="White", rough=0.6),
    "M_Headlight": dict(key="HeadlightWhite", rough=0.2, emit=1.0),
    "M_Taillight": dict(key="TailRed", rough=0.3, emit=0.6),
    "M_Indicator": dict(key="IndicatorAmber", rough=0.3, emit=0.3),
    "M_Tire": dict(key="Tire", rough=0.9),
    "M_Rim": dict(key="Rim", rough=0.35, metal=0.8),
}
# Roughness / metal hints for palette materials that are metals.
PAL_HINT = {
    "Chrome": dict(rough=0.2, metal=0.9), "Steel": dict(rough=0.4, metal=0.7),
    "SteelDark": dict(rough=0.5, metal=0.6), "Brass": dict(rough=0.35, metal=0.8),
    "GunMetal": dict(rough=0.45, metal=0.6), "GunMetalDark": dict(rough=0.5, metal=0.5),
    "Rim": dict(rough=0.35, metal=0.8), "CarWhite": dict(rough=0.4), "White": dict(rough=0.5),
}


def M(key):
    """Material by key: 'M_*' = contract material, 'P_Collision', otherwise a palette key."""
    if key == "P_Collision":
        return G.mat("P_Collision", (1.0, 0.0, 1.0), rough=1.0, alpha=0.3)
    if key.startswith("M_"):
        d = CONTRACT[key]
        c = G.pal(d["key"])
        e = d.get("emit", 0.0)
        return G.mat(key, c, rough=d.get("rough", 0.6), metal=d.get("metal", 0.0),
                     emit=c if e > 0 else None, emit_strength=e, alpha=d.get("alpha", 1.0))
    return G.pmat(key, **PAL_HINT.get(key, {}))


# ------------------------------------------------------------------------------------------------
# mesh builder
# ------------------------------------------------------------------------------------------------
def _smooth_bm(bm, angle_deg):
    limit = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(0.0) <= limit


class MB:
    """Mesh builder.  Geometry is added to `self.bm` (the current shading group); flush(smooth)
    welds / fixes normals / applies flat or angle-smooth shading to the group and appends it to the
    final mesh.  finish() creates the object.  All groups share one material list."""

    def __init__(self):
        self.master = bmesh.new()
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, key):
        m = M(key)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def flush(self, smooth=None, weld=0.0001, recalc=True):
        bm = self.bm
        if len(bm.verts):
            if weld and weld > 0:
                bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=weld)
            if recalc:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            if smooth is not None:
                _smooth_bm(bm, smooth)
            tmp = bpy.data.meshes.new("_bb_tmp")
            bm.to_mesh(tmp)
            self.master.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
        bm.free()
        self.bm = bmesh.new()

    def finish(self, name, parent, origin=None, smooth=None, location=(0, 0, 0), rotation=(0, 0, 0)):
        self.flush(smooth)
        self.bm.free()
        ob = G.new_object(oname(parent, name), self.master, parent=parent, materials=self.mats,
                          location=location, rotation=rotation, weld=0, recalc=False)
        if origin is not None:
            G.set_origin(ob, origin)
        ob["gta_name"] = name
        return ob


def oname(parent, name):
    """Blender object name of a part: '<asset>:<Part>' (unique in the shared file)."""
    return "%s:%s" % (parent.name, name)


def marker(name, root, loc, rot=(0, 0, 0), size=0.12):
    e = G.empty(oname(root, name), root, loc, rot, size=size)
    e["gta_name"] = name
    return e


def child_marker(name, root, parent, pos, size=0.06):
    """Marker that rides on a moving part (Handlebar, Crank ...).  `pos` is given in ASSET space; the
    parent must be an unrotated child of the root.  Used for hand / foot targets (Grip_L, Pedal_R)."""
    e = G.empty("%s:%s" % (root.name, name), parent, Vector(pos) - parent.location, size=size)
    e["gta_name"] = name
    return e


def light_markers(root, base, pos, dx, back=False):
    """<base> (centre) plus <base>_L / <base>_R (the vehicle code looks for the L/R pair)."""
    rot = (0, 0, PI) if back else (0, 0, 0)
    marker(base, root, pos, rot)
    marker(base + "_L", root, (pos[0] - dx, pos[1], pos[2]), rot)
    marker(base + "_R", root, (pos[0] + dx, pos[1], pos[2]), rot)


def hide_helper(ob, wire=False):
    """Helper meshes (Col_*, Body_LOD1): hidden in viewport + render, still exported."""
    ob.hide_render = True
    try:
        bpy.context.view_layer.update()
        ob.hide_set(True)
    except Exception:
        pass
    if wire:
        ob.display_type = 'WIRE'


# ------------------------------------------------------------------------------------------------
# geometry helpers (append to an open bmesh)
# ------------------------------------------------------------------------------------------------
def _edges_of(verts):
    es = set()
    for v in verts:
        for e in v.link_edges:
            es.add(e)
    return list(es)


def box(bm, size, center=(0, 0, 0), rot=None, mi=0):
    return G.add_box(bm, size, center, rot, mi)


def cbox(bm, size, center=(0, 0, 0), rot=None, mi=0, bev=0.012):
    """Chamfered box (the chunky edge of the art direction), bevelled in bmesh."""
    vs = G.add_box(bm, size, center, rot, mi)
    b = min(bev, min(size) * 0.45)
    if b > 0:
        try:
            bmesh.ops.bevel(bm, geom=_edges_of(vs), offset=b, offset_type='OFFSET', segments=1,
                            profile=0.5, affect='EDGES', clamp_overlap=True, material=mi)
        except Exception as ex:
            print("cbox bevel failed:", ex)


def tube(bm, a, b, r, seg=8, mi=0, r2=None, cap=True):
    """Cylinder / frustum from point a to point b."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    if d.length < 1e-6:
        return []
    Mx = Matrix.Translation((a + b) * 0.5) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r,
                                radius2=(r if r2 is None else r2), depth=d.length, matrix=Mx)
    G._assign(ret['verts'], mi)
    return ret['verts']


def loft(bm, sections, mi=0, strip_mi=None, cap_start=True, cap_end=True, close_ring=True, cap_mi=None):
    """Like G.add_loft, with an optional material index per strip (strip i = points i..i+1)."""
    rings = [[bm.verts.new(Vector(p)) for p in sec] for sec in sections]
    n = len(rings[0])
    last = n if close_ring else n - 1
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(last):
            j = (i + 1) % n
            try:
                f = bm.faces.new((a[i], a[j], b[j], b[i]))
                f.material_index = strip_mi[i] if strip_mi is not None else mi
            except ValueError:
                pass
    cm = mi if cap_mi is None else cap_mi
    if close_ring and n >= 3:
        if cap_start:
            try:
                bm.faces.new(list(reversed(rings[0]))).material_index = cm
            except ValueError:
                pass
        if cap_end:
            try:
                bm.faces.new(rings[-1]).material_index = cm
            except ValueError:
                pass
    return rings


def pipe(bm, pts, r, seg=8, mi=0, cap=True):
    """Bent tube through a polyline with mitred joints. r = radius or list of radii per point."""
    P = [Vector(p) for p in pts]
    n = len(P)
    tans = []
    for i in range(n):
        if i == 0:
            d = P[1] - P[0]
        elif i == n - 1:
            d = P[-1] - P[-2]
        else:
            d = (P[i + 1] - P[i]).normalized() + (P[i] - P[i - 1]).normalized()
        tans.append(d.normalized())
    t0 = tans[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    nrm = (ref - t0 * ref.dot(t0)).normalized()
    prev_t = t0
    rings = []
    for i in range(n):
        t = tans[i]
        axis = prev_t.cross(t)
        if axis.length > 1e-7:
            nrm = Matrix.Rotation(prev_t.angle(t), 3, axis.normalized()) @ nrm
        nrm = (nrm - t * nrm.dot(t)).normalized()
        bn = t.cross(nrm)
        rr = r[i] if isinstance(r, (list, tuple)) else r
        k = 1.0
        m = None
        if 0 < i < n - 1:
            din = (P[i] - P[i - 1]).normalized()
            dout = (P[i + 1] - P[i]).normalized()
            c = max(0.45, din.dot(t))
            k = 1.0 / c
            mm = dout - din
            if mm.length > 1e-6:
                m = mm.normalized()
        ring = []
        for j in range(seg):
            a = 2 * PI * j / seg
            off = (nrm * math.cos(a) + bn * math.sin(a)) * rr
            if m is not None:
                off = off + m * (off.dot(m) * (k - 1.0))
            ring.append(P[i] + off)
        rings.append(ring)
        prev_t = t
    return loft(bm, rings, mi=mi, cap_start=cap, cap_end=cap)


def revolve(bm, profile, seg=16, center=(0, 0, 0), axis='X', mi=0, closed=True, strip_mi=None,
            a0=0.0, a1=None, cap=False):
    """Lathe a profile [(a, r), ...] (a = coordinate along the axis, r = radius) around `axis`.
    closed: the profile is a closed loop (tyre / ring cross-section).  a0..a1 (radians) = partial
    sweep (then the two ends are capped when cap=True and the profile is closed)."""
    cx, cy, cz = center
    full = a1 is None
    count = seg if full else seg + 1
    rings = []
    for i in range(count):
        th = (2 * PI * i / seg) if full else (a0 + (a1 - a0) * i / seg)
        c, s = math.cos(th), math.sin(th)
        ring = []
        for a, r in profile:
            if axis == 'X':
                p = (cx + a, cy + r * c, cz + r * s)
            elif axis == 'Y':
                p = (cx + r * c, cy + a, cz + r * s)
            else:
                p = (cx + r * c, cy + r * s, cz + a)
            ring.append(bm.verts.new(p))
        rings.append(ring)
    n = len(profile)
    last = n if closed else n - 1
    pairs = [(i, (i + 1) % seg) for i in range(seg)] if full else [(i, i + 1) for i in range(seg)]
    for i, i2 in pairs:
        A = rings[i]
        B = rings[i2]
        for j in range(last):
            k = (j + 1) % n
            try:
                f = bm.faces.new((A[j], A[k], B[k], B[j]))
                f.material_index = strip_mi[j] if strip_mi is not None else mi
            except ValueError:
                pass
    if not full and cap and closed:
        for ring in (rings[0], rings[-1]):
            try:
                bm.faces.new(ring).material_index = mi
            except ValueError:
                pass
    return rings


def sec_oct(y, hw, zb, zt, cb=None, ct=None, cx=0.0):
    """Chamfered-rectangle (octagon) cross-section in the XZ plane at `y`."""
    if cb is None:
        cb = min(hw, (zt - zb) * 0.5) * 0.4
    if ct is None:
        ct = cb
    return [(cx - hw + cb, y, zb), (cx + hw - cb, y, zb), (cx + hw, y, zb + cb), (cx + hw, y, zt - ct),
            (cx + hw - ct, y, zt), (cx - hw + ct, y, zt), (cx - hw, y, zt - ct), (cx - hw, y, zb + cb)]


def arc_shell(bm, cy, cz, radius, hw, a0, a1, n=6, thick=0.012, drop=0.03, mi=0):
    """Mudguard: an inverted-U strip (with thickness) following a circle centred (cy, cz) in the
    YZ plane from angle a0 to a1 in degrees (0 = +Y forward, 90 = +Z up)."""
    secs = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        c, s = math.cos(a), math.sin(a)

        def Pt(x, r):
            return (x, cy + r * c, cz + r * s)
        ro = radius + thick
        ri = radius
        w = hw
        secs.append([Pt(-w, ro - drop), Pt(-w * 0.62, ro), Pt(w * 0.62, ro), Pt(w, ro - drop),
                     Pt(w - thick, ro - drop), Pt(w * 0.62 - thick * 0.4, ri), Pt(-w * 0.62 + thick * 0.4, ri),
                     Pt(-w + thick, ro - drop)])
    return loft(bm, secs, mi=mi)


def spokes(bm, n, r0, r1, ax0, ax1, tw0, tw1, twist_deg=0.0, mi=0, x_off=0.0, phase=0.0):
    """Radial cast spokes around the X axis (rectangular section tapering from hub r0 to rim r1)."""
    for i in range(n):
        a_in = phase + 2 * PI * i / n
        a_out = a_in + math.radians(twist_deg)

        def sec(r, a, ax, tw):
            c, s = math.cos(a), math.sin(a)
            return [(x_off + dx, r * c - dt * s, r * s + dt * c)
                    for dx, dt in ((-ax, -tw), (ax, -tw), (ax, tw), (-ax, tw))]
        loft(bm, [sec(r0, a_in, ax0, tw0), sec(r1, a_out, ax1, tw1)], mi=mi)


def sec4(y, hw, zb, zt):
    """Plain rectangular cross-section (LOD shells)."""
    return [(-hw, y, zb), (hw, y, zb), (hw, y, zt), (-hw, y, zt)]


def arc_box(bm, cy, cz, r0, r1, hw, a0, a1, n=3, mi=0):
    """Cheap mudguard (box section following a circle) for LOD shells."""
    secs = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        c, s = math.cos(a), math.sin(a)
        secs.append([(-hw, cy + r0 * c, cz + r0 * s), (hw, cy + r0 * c, cz + r0 * s),
                     (hw, cy + r1 * c, cz + r1 * s), (-hw, cy + r1 * c, cz + r1 * s)])
    return loft(bm, secs, mi=mi)


def prism_x(bm, profile_yz, x0, x1, mi=0):
    """Extrude a (y, z) polygon between x0 and x1."""
    return loft(bm, [[(x0, p[0], p[1]) for p in profile_yz], [(x1, p[0], p[1]) for p in profile_yz]], mi=mi)


def pane(bm, quad, thick=0.012, mi=0):
    """Thin solid plate from 4 corner points (window panes)."""
    q = [Vector(p) for p in quad]
    n = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
    return loft(bm, [[p + n * thick * 0.5 for p in q], [p - n * thick * 0.5 for p in q]], mi=mi)


def col_hull(name, root, points):
    """Convex collision helper from a point cloud (<= 32 verts), material P_Collision."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in points]
    try:
        ret = bmesh.ops.convex_hull(bm, input=vs)
        junk = [e for e in ret.get("geom_interior", []) if isinstance(e, bmesh.types.BMVert)]
        junk += [e for e in ret.get("geom_unused", []) if isinstance(e, bmesh.types.BMVert)]
        if junk:
            bmesh.ops.delete(bm, geom=list(set(junk)), context='VERTS')
    except Exception as ex:
        print("convex hull failed:", ex)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = G.new_object(oname(root, name), bm, parent=root, materials=[M("P_Collision")], weld=0, recalc=False)
    hide_helper(ob, wire=True)
    ob["gta_name"] = name
    print("  %s: %d verts" % (name, len(ob.data.vertices)))
    return ob


# ------------------------------------------------------------------------------------------------
# QA / export
# ------------------------------------------------------------------------------------------------
def fix_glb_names(path):
    """Rewrite node names of an exported GLB from the 'gta_name' custom property (exported as
    extras) and strip Blender's '.001' suffixes from mesh names.  Returns the number of renames."""
    with open(path, 'rb') as f:
        data = f.read()
    magic, ver, _total = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF':
        raise RuntimeError("not a GLB: " + path)
    clen, ctype = struct.unpack_from('<II', data, 12)
    if ctype != 0x4E4F534A:
        raise RuntimeError("first chunk is not JSON")
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    rest = data[20 + clen:]
    changed = 0
    for nd in js.get('nodes', []):
        ex = nd.get('extras')
        if isinstance(ex, dict) and 'gta_name' in ex:
            want = ex.pop('gta_name')
            if nd.get('name') != want:
                nd['name'] = want
                changed += 1
            if ex:
                nd['extras'] = ex
            else:
                nd.pop('extras', None)
    for me in js.get('meshes', []):
        nm = me.get('name', '')
        nm2 = re.sub(r'\.\d{3,}$', '', nm)
        if nm2 != nm:
            me['name'] = nm2
    out = json.dumps(js, separators=(',', ':')).encode('utf-8')
    out += b' ' * ((4 - len(out) % 4) % 4)
    blob = struct.pack('<4sII', b'glTF', ver, 12 + 8 + len(out) + len(rest))
    blob += struct.pack('<II', len(out), 0x4E4F534A) + out + rest
    with open(path, 'wb') as f:
        f.write(blob)
    names = [nd.get('name') for nd in js.get('nodes', [])]
    dup = sorted(set(x for x in names if names.count(x) > 1))
    print("GLB_NAMES_FIXED: %s renamed=%d nodes=%d duplicates=%s" % (os.path.basename(path), changed, len(names), dup))
    return changed


def export(name):
    path = G.export_glb(name, "vehicles/%s.glb" % name)
    fix_glb_names(path)
    return path


def qa(name, views=VIEWS, res=500, tag=None, margin=1.0):
    rep = G.validate(name)
    path = G.preview(name, tag or name, views=views, res=res, margin=margin)
    return rep, path


def qa_lod(name, views=("three_quarter", "side", "rear_quarter", "top"), res=420):
    """Preview of the distance shell: Body_LOD1 + wheels only (what the game draws beyond 75 m)."""
    root = bpy.data.objects[name]
    saved = {}
    for o in root.children_recursive:
        if o.type != 'MESH':
            continue
        saved[o] = o.hide_render
        gn = o.get("gta_name", "")
        o.hide_render = not (gn == "Body_LOD1" or gn.startswith("Wheel"))
    try:
        return G.preview(name, name + "_lod1", views=views, res=res, margin=1.0)
    finally:
        for o, v in saved.items():
            o.hide_render = v


def check_normals(name):
    """Normal / topology QA (spec section 55): every mesh is split into connected shells; a closed
    shell with a negative signed volume is inside-out.  Open shells and zero-area faces are counted.
    Returns the number of inverted shells (0 = good)."""
    root = bpy.data.objects[name]
    bad_total = 0
    for o in sorted(root.children_recursive, key=lambda x: x.name):
        if o.type != 'MESH':
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        seen = set()
        closed = opened = inverted = 0
        degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
        for v0 in bm.verts:
            if v0.index in seen:
                continue
            stack = [v0]
            seen.add(v0.index)
            faces = set()
            while stack:
                v = stack.pop()
                for f in v.link_faces:
                    faces.add(f)
                for e in v.link_edges:
                    w = e.other_vert(v)
                    if w.index not in seen:
                        seen.add(w.index)
                        stack.append(w)
            if not faces:
                continue
            is_closed = all(len(e.link_faces) == 2 for f in faces for e in f.edges)
            if not is_closed:
                opened += 1
                continue
            closed += 1
            vol = 0.0
            for f in faces:
                vs = [l.vert.co for l in f.loops]
                for i in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[i].cross(vs[i + 1]))
            if vol < 0.0:
                inverted += 1
        bm.free()
        bad_total += inverted
        print("  NORMALS %-18s shells: closed=%-3d open=%-3d inverted=%d degenerate_faces=%d" % (
            o.get("gta_name", o.name), closed, opened, inverted, degenerate))
    print("NORMALS %s: inverted shells = %d" % (name, bad_total))
    return bad_total


def check_contract(name):
    """Pivot / placement QA: wheel origins + axle direction, lowest point, marker list, hull verts."""
    root = bpy.data.objects[name]
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted()
    zmin = 1e9
    for o in root.children_recursive:
        if o.type != 'MESH':
            continue
        gn = o.get("gta_name", o.name)
        M4 = inv @ o.matrix_world
        pts = [M4 @ v.co for v in o.data.vertices]
        lo = min(p.z for p in pts)
        if not gn.startswith("Col_"):
            zmin = min(zmin, lo)
        if gn.startswith("Wheel"):
            sx = max(v.co.x for v in o.data.vertices) - min(v.co.x for v in o.data.vertices)
            ry = max(abs(v.co.y) for v in o.data.vertices)
            rz = max(abs(v.co.z) for v in o.data.vertices)
            cy = (max(v.co.y for v in o.data.vertices) + min(v.co.y for v in o.data.vertices)) * 0.5
            cz = (max(v.co.z for v in o.data.vertices) + min(v.co.z for v in o.data.vertices)) * 0.5
            print("  WHEEL %-8s origin=(%.3f, %.3f, %.3f) width_x=%.3f radius_y=%.3f radius_z=%.3f centre_offset=(%.4f, %.4f) bottom_z=%.4f" % (
                gn, o.location.x, o.location.y, o.location.z, sx, ry, rz, cy, cz, lo))
        if gn.startswith("Col_"):
            print("  %-14s verts=%d (limit 32)" % (gn, len(o.data.vertices)))
    marks = sorted(o.get("gta_name", o.name) + ("" if o.parent == root else "<" + o.parent.get("gta_name", "?"))
                   for o in root.children_recursive if o.type == 'EMPTY')
    print("CONTRACT %s: lowest visible z=%.4f markers=%s" % (name, zmin, marks))


def report_children(name):
    root = bpy.data.objects[name]
    for o in sorted(root.children, key=lambda x: x.name):
        gn = o.get("gta_name", "?")
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            print("  %-18s mesh tris=%-5d loc=(%.3f, %.3f, %.3f) mats=%s" % (
                gn, len(o.data.loop_triangles), o.location.x, o.location.y, o.location.z,
                [m.name for m in o.data.materials]))
        else:
            print("  %-18s marker       loc=(%.3f, %.3f, %.3f)" % (gn, o.location.x, o.location.y, o.location.z))


# ================================================================================================
# MOTORCYCLE - sport-naked, ~2.07 m long, wheelbase 1.43 m
# ================================================================================================
def _moto_wheel(name, root, center, R, w, Rr, hub_w, discs=(), sprocket_x=None, seg=20, n_spokes=6, twist=14.0):
    """Motorcycle wheel centred on its own origin, axle along X. discs = [(x, radius), ...]."""
    b = MB()
    h = R - Rr
    half = [(-0.40 * w, Rr - 0.004), (-0.50 * w, Rr + 0.38 * h), (-0.36 * w, Rr + 0.84 * h)]
    prof = half + [(0.0, R)] + [(-a, r) for a, r in reversed(half)]
    revolve(b.bm, prof, seg, mi=b.mi("M_Tire"))
    b.flush(smooth=50)
    # rim barrel + lips
    rim = [(-0.44 * w, Rr + 0.012), (-0.44 * w, Rr - 0.014), (0.0, Rr - 0.034),
           (0.44 * w, Rr - 0.014), (0.44 * w, Rr + 0.012)]
    revolve(b.bm, rim, seg, mi=b.mi("M_Rim"))
    b.flush(smooth=35)
    # hub
    G.add_cylinder(b.bm, 0.048, hub_w, axis='X', segments=12, mat_index=b.mi("M_Rim"))
    G.add_cylinder(b.bm, 0.024, hub_w + 0.03, axis='X', segments=8, mat_index=b.mi("SteelDark"))
    for x, rd in discs:
        revolve(b.bm, [(x - 0.004, rd * 0.60), (x + 0.004, rd * 0.60), (x + 0.004, rd), (x - 0.004, rd)], 14, mi=b.mi("Steel"))
        G.add_cylinder(b.bm, rd * 0.42, 0.014, center=(x * 0.93, 0, 0), axis='X', segments=8, mat_index=b.mi("SteelDark"))
    if sprocket_x is not None:
        revolve(b.bm, [(sprocket_x - 0.004, 0.058), (sprocket_x + 0.004, 0.058), (sprocket_x + 0.004, 0.098),
                       (sprocket_x - 0.004, 0.098)], 14, mi=b.mi("Steel"))
        G.add_cylinder(b.bm, 0.045, 0.016, center=(sprocket_x * 0.93, 0, 0), axis='X', segments=8, mat_index=b.mi("SteelDark"))
    b.flush(smooth=35)
    spokes(b.bm, n_spokes, 0.04, Rr - 0.026, 0.03, 0.02, 0.02, 0.013, twist_deg=twist, mi=b.mi("M_Rim"))
    b.flush()
    return b.finish(name, root, location=center)


def build_motorcycle(index=0):
    root = G.asset_root("motorcycle", "Vehicles/Motorcycles", G.slot("bikes", index))
    root["gta_name"] = "motorcycle"
    RAKE = math.radians(25.0)
    FA = Vector((0.0, 0.74, 0.31))     # front axle
    RA = Vector((0.0, -0.69, 0.32))    # rear axle
    U = Vector((0.0, -math.sin(RAKE), math.cos(RAKE)))     # steering axis direction (up / back)
    N = Vector((0.0, -math.cos(RAKE), -math.sin(RAKE)))    # perpendicular to it, pointing rearwards
    RK = (RAKE, 0.0, 0.0)

    def fk(s, n=0.0, x=0.0):
        """Point on the fork line: s metres up from the front axle, n metres rearwards, x sideways."""
        return FA + U * s + N * n + Vector((x, 0.0, 0.0))

    HEAD = fk(0.61, 0.04)              # steering head centre = Handlebar origin

    # ------------------------------------------------------------------ Body
    b = MB()
    PAINT = b.mi("M_Paint_Primary")
    FRAME = b.mi("M_Paint_Secondary")
    SEAT = b.mi("M_Interior")
    TRIM = b.mi("M_Trim")
    CHROME = b.mi("M_Chrome")
    STEEL = b.mi("Steel")
    DARK = b.mi("SteelDark")
    CHAR = b.mi("Charcoal")

    # -- flat-shaded sculpted parts
    def tank_sec(y, wb, zb, wm, zm, wt, zs, wr, zt):
        return [(-wb, y, zb), (wb, y, zb), (wm, y, zm), (wt, y, zs), (wr, y, zt),
                (-wr, y, zt), (-wt, y, zs), (-wm, y, zm)]
    loft(b.bm, [
        tank_sec(-0.17, 0.060, 0.770, 0.085, 0.800, 0.085, 0.850, 0.045, 0.875),
        tank_sec(-0.06, 0.080, 0.740, 0.115, 0.810, 0.125, 0.920, 0.065, 0.965),
        tank_sec(0.07, 0.100, 0.740, 0.175, 0.830, 0.185, 0.960, 0.085, 1.020),
        tank_sec(0.20, 0.110, 0.750, 0.205, 0.850, 0.195, 0.955, 0.085, 1.015),
        tank_sec(0.30, 0.100, 0.790, 0.165, 0.860, 0.150, 0.930, 0.070, 0.970),
        tank_sec(0.355, 0.060, 0.830, 0.090, 0.865, 0.085, 0.900, 0.045, 0.920),
    ], mi=PAINT)
    # rider seat + pillion pad
    loft(b.bm, [sec_oct(-0.13, 0.085, 0.760, 0.830), sec_oct(-0.22, 0.135, 0.745, 0.815),
                sec_oct(-0.36, 0.155, 0.745, 0.810), sec_oct(-0.47, 0.150, 0.760, 0.835),
                sec_oct(-0.515, 0.135, 0.780, 0.875)], mi=SEAT)
    loft(b.bm, [sec_oct(-0.50, 0.120, 0.830, 0.915), sec_oct(-0.62, 0.115, 0.855, 0.945),
                sec_oct(-0.76, 0.085, 0.905, 0.985), sec_oct(-0.83, 0.060, 0.940, 1.000)], mi=SEAT)
    # tail cowl (upswept)
    loft(b.bm, [sec_oct(-0.10, 0.125, 0.660, 0.770), sec_oct(-0.36, 0.165, 0.690, 0.775),
                sec_oct(-0.56, 0.155, 0.765, 0.860), sec_oct(-0.78, 0.115, 0.870, 0.950),
                sec_oct(-0.93, 0.055, 0.945, 0.995)], mi=PAINT)
    cbox(b.bm, (0.10, 0.035, 0.034), (0, -0.94, 0.972), mi=b.mi("M_Taillight"), bev=0.008)
    # radiator shrouds (angular flank panels)
    for sx in (-1, 1):
        prism_x(b.bm, [(0.14, 0.87), (0.33, 0.855), (0.435, 0.675), (0.385, 0.605), (0.25, 0.745)],
                sx * 0.150, sx * 0.176, mi=PAINT)
    # belly pan
    def belly(y, hw, zb, zt):
        return [(-hw * 0.55, y, zb), (hw * 0.55, y, zb), (hw, y, zb + 0.035), (hw, y, zt), (-hw, y, zt), (-hw, y, zb + 0.035)]
    loft(b.bm, [belly(0.345, 0.07, 0.300, 0.360), belly(0.25, 0.135, 0.215, 0.340),
                belly(0.02, 0.145, 0.190, 0.300), belly(-0.17, 0.125, 0.205, 0.275)], mi=PAINT)
    # engine
    cbox(b.bm, (0.20, 0.34, 0.16), (0, 0.03, 0.69), mi=CHAR, bev=0.02)              # airbox filler under the tank
    cbox(b.bm, (0.24, 0.44, 0.22), (0, 0.02, 0.40), mi=DARK, bev=0.03)             # crankcase / gearbox
    cbox(b.bm, (0.18, 0.24, 0.08), (0, 0.05, 0.265), mi=DARK, bev=0.02)            # sump
    CT = -0.38                                                                   # cylinder bank tilt
    cax = Vector((0.0, -math.sin(CT), math.cos(CT)))
    cc = Vector((0.0, 0.155, 0.585))
    cbox(b.bm, (0.24, 0.19, 0.20), cc, rot=(CT, 0, 0), mi=STEEL, bev=0.015)
    for o in (-0.055, 0.0, 0.055):
        box(b.bm, (0.262, 0.212, 0.014), cc + cax * o, rot=(CT, 0, 0), mi=DARK)
    cbox(b.bm, (0.22, 0.17, 0.05), cc + cax * 0.125, rot=(CT, 0, 0), mi=DARK, bev=0.012)
    cbox(b.bm, (0.03, 0.12, 0.10), (-0.13, -0.13, 0.41), mi=DARK, bev=0.01)       # sprocket cover
    # radiator
    RT = -0.30
    cbox(b.bm, (0.30, 0.03, 0.22), (0, 0.365, 0.62), rot=(RT, 0, 0), mi=TRIM, bev=0.008)
    box(b.bm, (0.26, 0.012, 0.18), (0, 0.365 + math.cos(RT) * 0.013, 0.62 + math.sin(RT) * 0.013), rot=(RT, 0, 0), mi=DARK)
    # frame pivot plates, swingarm
    for sx in (-1, 1):
        cbox(b.bm, (0.022, 0.12, 0.30), (sx * 0.14, -0.155, 0.43), mi=DARK, bev=0.008)
        loft(b.bm, [
            [(sx * 0.115, -0.15, 0.355), (sx * 0.150, -0.15, 0.355), (sx * 0.150, -0.15, 0.445), (sx * 0.115, -0.15, 0.445)],
            [(sx * 0.115, -0.45, 0.315), (sx * 0.150, -0.45, 0.315), (sx * 0.150, -0.45, 0.390), (sx * 0.115, -0.45, 0.390)],
            [(sx * 0.115, -0.75, 0.285), (sx * 0.150, -0.75, 0.285), (sx * 0.150, -0.75, 0.355), (sx * 0.115, -0.75, 0.355)],
        ], mi=STEEL)
        cbox(b.bm, (0.05, 0.09, 0.08), (sx * 0.1325, -0.70, 0.32), mi=DARK, bev=0.01)   # axle adjuster block
        # rider footpeg hanger
        prism_x(b.bm, [(-0.11, 0.52), (-0.11, 0.40), (-0.27, 0.355), (-0.27, 0.40)], sx * 0.151, sx * 0.166, mi=STEEL)
    cbox(b.bm, (0.24, 0.07, 0.07), (0, -0.27, 0.385), mi=STEEL, bev=0.012)          # swingarm brace
    cbox(b.bm, (0.035, 0.085, 0.05), (0.078, -0.69, 0.445), mi=b.mi("Brass"), bev=0.008)   # rear caliper
    box(b.bm, (0.012, 0.03, 0.11), (0.105, -0.69, 0.39), mi=DARK)
    box(b.bm, (0.03, 0.34, 0.012), (-0.098, -0.42, 0.458), rot=(0.054, 0, 0), mi=TRIM)   # chain guard
    # rear hugger
    arc_shell(b.bm, RA.y, RA.z, 0.34, 0.105, 28, 105, n=5, thick=0.012, drop=0.035, mi=TRIM)
    # tail tidy: number plate + indicators
    cbox(b.bm, (0.19, 0.012, 0.12), (0, -1.004, 0.63), rot=(0.22, 0, 0), mi=TRIM, bev=0.004)
    box(b.bm, (0.17, 0.012, 0.10), (0, -1.012, 0.63), rot=(0.22, 0, 0), mi=b.mi("M_Plate"))
    for sx in (-1, 1):
        cbox(b.bm, (0.045, 0.03, 0.028), (sx * 0.128, -0.975, 0.735), mi=b.mi("M_Indicator"), bev=0.006)
    b.flush()

    # -- tubes (smooth)
    for sx in (-1, 1):
        H1 = (sx * 0.03, 0.42, 0.905)
        H2 = (sx * 0.03, 0.475, 0.785)
        A = (sx * 0.145, 0.20, 0.80)
        Bq = (sx * 0.15, -0.10, 0.72)
        C = (sx * 0.145, 0.25, 0.62)
        D = (sx * 0.14, -0.15, 0.52)
        for p, q in ((H1, A), (A, Bq), (H2, C), (C, D), (H2, A), (A, C), (C, Bq), (Bq, D)):
            tube(b.bm, p, q, 0.016, seg=6, mi=FRAME)
        tube(b.bm, C, (sx * 0.125, 0.26, 0.50), 0.014, seg=6, mi=FRAME)             # engine hanger
        tube(b.bm, Bq, (sx * 0.11, -0.62, 0.84), 0.014, seg=6, mi=FRAME)            # subframe (upper)
        tube(b.bm, D, (sx * 0.125, -0.52, 0.775), 0.014, seg=6, mi=FRAME)           # subframe (lower)
        tube(b.bm, (sx * 0.13, -0.40, 0.72), (sx * 0.165, -0.47, 0.565), 0.012, seg=6, mi=FRAME)   # pillion peg hanger
        tube(b.bm, (sx * 0.165, -0.47, 0.56), (sx * 0.235, -0.47, 0.56), 0.013, seg=6, mi=TRIM)
        tube(b.bm, (sx * 0.160, -0.25, 0.375), (sx * 0.255, -0.25, 0.375), 0.014, seg=6, mi=TRIM)  # rider peg
        tube(b.bm, (sx * 0.205, -0.25, 0.37), (sx * 0.20, -0.11, 0.355), 0.007, seg=4, mi=DARK)    # shift / brake lever
        tube(b.bm, (sx * 0.195, -0.11, 0.355), (sx * 0.245, -0.11, 0.355), 0.010, seg=6, mi=TRIM)
        tube(b.bm, (sx * 0.02, -0.975, 0.735), (sx * 0.108, -0.975, 0.735), 0.008, seg=4, mi=TRIM)  # indicator stalk
        # exhaust headers
        pipe(b.bm, [(sx * 0.06, 0.25, 0.60), (sx * 0.065, 0.30, 0.50), (sx * 0.065, 0.335, 0.40),
                    (sx * 0.055, 0.30, 0.28), (sx * 0.04, 0.14, 0.245)], 0.02, seg=6, mi=CHROME)
    pipe(b.bm, [(0.0, 0.10, 0.245), (0.06, -0.10, 0.25), (0.15, -0.26, 0.29), (0.205, -0.31, 0.335)], 0.026, seg=6, mi=CHROME)
    tube(b.bm, (0, -0.89, 0.93), (0, -1.0, 0.68), 0.022, seg=4, mi=TRIM)            # plate holder arm
    tube(b.bm, (-0.098, -0.13, 0.445), (-0.098, -0.69, 0.415), 0.012, seg=4, mi=TRIM)   # chain upper run
    tube(b.bm, (-0.098, -0.13, 0.375), (-0.098, -0.69, 0.225), 0.012, seg=4, mi=TRIM)   # chain lower run
    tube(b.bm, (-0.15, -0.02, 0.285), (-0.21, -0.34, 0.215), 0.011, seg=6, mi=DARK)     # side stand
    tube(b.bm, (-0.165, RA.y, RA.z), (0.165, RA.y, RA.z), 0.014, seg=8, mi=DARK)        # rear axle
    b.flush(smooth=70)

    # -- round parts (smooth, sharp caps)
    tube(b.bm, HEAD - U * 0.09, HEAD + U * 0.09, 0.038, seg=10, mi=FRAME)             # head tube
    G.add_cylinder(b.bm, 0.10, 0.035, center=(0.1375, -0.07, 0.40), axis='X', segments=12, mat_index=STEEL)   # clutch cover
    G.add_cylinder(b.bm, 0.055, 0.047, center=(0.1375, -0.07, 0.40), axis='X', segments=10, mat_index=DARK)
    G.add_cylinder(b.bm, 0.085, 0.035, center=(-0.1375, 0.10, 0.40), axis='X', segments=12, mat_index=STEEL)  # alternator cover
    G.add_cylinder(b.bm, 0.04, 0.047, center=(-0.1375, 0.10, 0.40), axis='X', segments=10, mat_index=DARK)
    G.add_cylinder(b.bm, 0.038, 0.08, center=(0.055, 0.27, 0.36), axis='Y', segments=10, mat_index=CHAR)      # oil filter
    G.add_cylinder(b.bm, 0.042, 0.012, center=(0, 0.10, 1.021), axis='Z', segments=10, mat_index=DARK)        # fuel cap
    tube(b.bm, (0, -0.26, 0.42), (0, -0.17, 0.70), 0.036, seg=8, mi=b.mi("CarYellow"))                         # rear shock spring
    # muffler
    m0 = Vector((0.21, -0.34, 0.345))
    m1 = Vector((0.23, -0.80, 0.505))
    md = (m1 - m0).normalized()
    tube(b.bm, m0, m1, 0.058, seg=10, mi=DARK)
    tube(b.bm, m0 - md * 0.05, m0 + md * 0.002, 0.028, seg=10, mi=CHROME, r2=0.058)   # (2 mm overlap: rings must not weld)
    tube(b.bm, m1 - md * 0.05, m1 + md * 0.006, 0.063, seg=10, mi=CHROME)
    tube(b.bm, m1, m1 + md * 0.022, 0.040, seg=10, mi=TRIM)
    tube(b.bm, m0 + md * 0.02, m0 + md * 0.06, 0.062, seg=10, mi=CHROME)
    b.flush(smooth=40)
    body = b.finish("Body", root)

    # ------------------------------------------------------------------ Handlebar (fork, fender, headlight, bars, mirrors)
    h = MB()
    PAINT = h.mi("M_Paint_Primary")
    TRIM = h.mi("M_Trim")
    CHROME = h.mi("M_Chrome")
    DARK = h.mi("SteelDark")
    GOLD = h.mi("Brass")
    Bc = fk(0.80, 0.03)                 # handlebar clamp centre
    for sx in (-1, 1):
        cbox(h.bm, (0.04, 0.065, 0.10), fk(0.0, x=sx * 0.105), rot=RK, mi=DARK, bev=0.01)               # axle lug
        cbox(h.bm, (0.036, 0.055, 0.10), fk(0.125, 0.06, sx * 0.078), rot=RK, mi=GOLD, bev=0.008)       # brake caliper
        cbox(h.bm, (0.035, 0.04, 0.06), fk(0.765, 0.03, sx * 0.05), rot=RK, mi=DARK, bev=0.006)         # bar riser
        cbox(h.bm, (0.045, 0.035, 0.035), (sx * 0.235, Bc.y - 0.025, Bc.z + 0.055), mi=TRIM, bev=0.006)  # lever perch
        cbox(h.bm, (0.125, 0.028, 0.07), (sx * 0.375, Bc.y - 0.03, Bc.z + 0.215), rot=(0, 0, -sx * 0.15), mi=TRIM, bev=0.012)  # mirror
        box(h.bm, (0.105, 0.004, 0.052), (sx * 0.375, Bc.y - 0.046, Bc.z + 0.215), rot=(0, 0, -sx * 0.15), mi=CHROME)
        cbox(h.bm, (0.05, 0.032, 0.03), (sx * 0.185, 0.56, 0.87), mi=h.mi("M_Indicator"), bev=0.006)
    cbox(h.bm, (0.275, 0.11, 0.032), fk(0.72, 0.02), rot=RK, mi=DARK, bev=0.008)       # upper triple clamp
    cbox(h.bm, (0.275, 0.11, 0.036), fk(0.50, 0.02), rot=RK, mi=DARK, bev=0.008)       # lower triple clamp
    cbox(h.bm, (0.21, 0.03, 0.022), fk(0.338), rot=RK, mi=TRIM, bev=0.004)             # fender bridge
    cbox(h.bm, (0.24, 0.04, 0.04), (0, 0.505, 0.88), mi=DARK, bev=0.006)               # headlight bracket
    # instrument pod
    DT = -0.6
    dc = fk(0.835, -0.03)
    cbox(h.bm, (0.14, 0.035, 0.085), dc, rot=(DT, 0, 0), mi=TRIM, bev=0.008)
    box(h.bm, (0.11, 0.004, 0.055), dc + Vector((0, -math.cos(DT), -math.sin(DT))) * 0.019, rot=(DT, 0, 0), mi=h.mi("WindowDark"))
    # headlight mask
    def hexs(y, hb, hm, ht, zb, zm, zt):
        return [(-hb, y, zb), (hb, y, zb), (hm, y, zm), (ht, y, zt), (-ht, y, zt), (-hm, y, zm)]
    loft(h.bm, [hexs(0.515, 0.085, 0.125, 0.095, 0.790, 0.900, 0.985),
                hexs(0.620, 0.075, 0.115, 0.085, 0.800, 0.885, 0.960),
                hexs(0.665, 0.055, 0.095, 0.070, 0.820, 0.878, 0.935)], mi=PAINT)
    loft(h.bm, [hexs(0.655, 0.042, 0.078, 0.056, 0.832, 0.878, 0.922),
                hexs(0.678, 0.036, 0.070, 0.050, 0.836, 0.878, 0.918)], mi=h.mi("M_Headlight"))
    # fly screen
    loft(h.bm, [[(-0.095, 0.625, 0.945), (0.095, 0.625, 0.945), (0.095, 0.60, 0.94), (-0.095, 0.60, 0.94)],
                [(-0.105, 0.565, 1.02), (0.105, 0.565, 1.02), (0.105, 0.543, 1.01), (-0.105, 0.543, 1.01)],
                [(-0.07, 0.505, 1.10), (0.07, 0.505, 1.10), (0.07, 0.485, 1.088), (-0.07, 0.485, 1.088)]],
         mi=h.mi("WindowDark"))                                                          # smoked (opaque) screen
    # front fender
    arc_shell(h.bm, FA.y, FA.z, 0.33, 0.072, 40, 148, n=6, thick=0.012, drop=0.03, mi=PAINT)
    h.flush()
    # round parts
    bar_l = [(-0.37, Bc.y - 0.085, Bc.z + 0.045), (-0.26, Bc.y - 0.04, Bc.z + 0.05), (-0.13, Bc.y, Bc.z + 0.005), (-0.05, Bc.y, Bc.z)]
    bar = bar_l + [(-p[0], p[1], p[2]) for p in reversed(bar_l)]
    pipe(h.bm, bar, 0.013, seg=6, mi=h.mi("Steel"))
    for sx in (-1, 1):
        tube(h.bm, fk(-0.03, x=sx * 0.105), fk(0.44, x=sx * 0.105), 0.021, seg=8, mi=CHROME)     # stanchion
        tube(h.bm, fk(0.38, x=sx * 0.105), fk(0.76, x=sx * 0.105), 0.031, seg=8, mi=GOLD)        # outer tube
        tube(h.bm, fk(0.76, x=sx * 0.105), fk(0.775, x=sx * 0.105), 0.024, seg=8, mi=DARK)       # fork cap
        end = Vector((sx * 0.37, Bc.y - 0.085, Bc.z + 0.045))
        inner = Vector((sx * 0.26, Bc.y - 0.04, Bc.z + 0.05))
        d = (end - inner).normalized()
        tube(h.bm, end - d * 0.125, end, 0.02, seg=8, mi=TRIM)                                   # grip
        tube(h.bm, end, end + d * 0.02, 0.016, seg=8, mi=CHROME)                                 # bar end
        tube(h.bm, (sx * 0.24, Bc.y + 0.008, Bc.z + 0.05), (sx * 0.39, Bc.y - 0.035, Bc.z + 0.04), 0.007, seg=4, mi=DARK)   # lever
        pipe(h.bm, [(sx * 0.235, Bc.y - 0.02, Bc.z + 0.07), (sx * 0.27, Bc.y - 0.012, Bc.z + 0.15),
                    (sx * 0.335, Bc.y - 0.025, Bc.z + 0.205)], 0.008, seg=5, mi=TRIM)            # mirror stalk
        tube(h.bm, (sx * 0.11, 0.56, 0.87), (sx * 0.165, 0.56, 0.87), 0.008, seg=4, mi=TRIM)     # indicator stalk
    tube(h.bm, (-0.13, FA.y, FA.z), (0.13, FA.y, FA.z), 0.013, seg=8, mi=DARK)                   # front axle
    tube(h.bm, fk(0.735, 0.04), fk(0.758, 0.04), 0.02, seg=8, mi=CHROME)                         # stem nut
    h.flush(smooth=60)
    handlebar = h.finish("Handlebar", root, origin=HEAD)

    # ------------------------------------------------------------------ wheels
    _moto_wheel("Wheel_F", root, FA, 0.31, 0.12, 0.215, 0.11, discs=((-0.066, 0.15), (0.066, 0.15)))
    _moto_wheel("Wheel_R", root, RA, 0.32, 0.18, 0.215, 0.16, discs=((0.078, 0.115),), sprocket_x=-0.098, twist=-14.0)

    # ------------------------------------------------------------------ collision helper + markers
    prof = [(-0.92, 0.80), (-0.60, 0.40), (0.30, 0.22), (0.62, 0.50), (0.62, 0.95), (0.20, 1.03), (-0.80, 0.96)]
    col_hull("Col_Body", root, [(sx * 0.17, y, z) for sx in (-1, 1) for y, z in prof])
    marker("Seat_Driver", root, (0.0, -0.30, 0.905))
    marker("Seat_Passenger_1", root, (0.0, -0.62, 1.045))
    marker("Exit_Driver", root, (-0.80, -0.20, 0.0))
    marker("Exit_Passenger_1", root, (0.80, -0.45, 0.0))
    light_markers(root, "Light_Head", (0.0, 0.69, 0.877), 0.04)
    light_markers(root, "Light_Tail", (0.0, -0.965, 0.972), 0.03, back=True)
    marker("Exhaust", root, tuple(m1 + md * 0.03), rot=(0, 0, PI))
    marker("Engine", root, (0.0, 0.12, 0.52))
    marker("Steer_Axis", root, tuple(HEAD), rot=RK)      # local +Z (Godot +Y) = raked steering axis
    for sx, tag in ((-1, "L"), (1, "R")):                # hand / foot targets for the rider pose
        end = Vector((sx * 0.37, Bc.y - 0.085, Bc.z + 0.045))
        d = (end - Vector((sx * 0.26, Bc.y - 0.04, Bc.z + 0.05))).normalized()
        child_marker("Grip_" + tag, root, handlebar, end - d * 0.0625)      # grip centre, turns with the bars
        marker("Footrest_" + tag, root, (sx * 0.21, -0.25, 0.39), size=0.06)

    # ------------------------------------------------------------------ Body_LOD1 (distance shell, replaces Body + Handlebar)
    l = MB()
    PAINT = l.mi("M_Paint_Primary")
    DARK = l.mi("SteelDark")
    loft(l.bm, [tank_sec(-0.17, 0.060, 0.770, 0.085, 0.800, 0.085, 0.850, 0.045, 0.875),
                tank_sec(0.12, 0.105, 0.740, 0.190, 0.840, 0.190, 0.960, 0.085, 1.020),
                tank_sec(0.355, 0.060, 0.830, 0.090, 0.865, 0.085, 0.900, 0.045, 0.920)], mi=PAINT)
    loft(l.bm, [sec4(-0.13, 0.11, 0.75, 0.825), sec4(-0.50, 0.15, 0.76, 0.84), sec4(-0.83, 0.07, 0.90, 0.99)], mi=l.mi("M_Interior"))
    loft(l.bm, [sec4(-0.10, 0.125, 0.66, 0.77), sec4(-0.56, 0.16, 0.765, 0.855), sec4(-0.93, 0.055, 0.945, 0.99)], mi=PAINT)
    box(l.bm, (0.10, 0.03, 0.034), (0, -0.945, 0.972), mi=l.mi("M_Taillight"))
    box(l.bm, (0.25, 0.50, 0.44), (0, 0.06, 0.47), mi=DARK)                                   # engine
    box(l.bm, (0.27, 0.50, 0.10), (0, 0.09, 0.245), mi=PAINT)                                 # belly pan
    for sx in (-1, 1):
        box(l.bm, (0.02, 0.62, 0.05), (sx * 0.148, 0.08, 0.72), rot=(0.22, 0, 0), mi=l.mi("M_Paint_Secondary"))   # frame rail
        box(l.bm, (0.04, 0.62, 0.07), (sx * 0.132, -0.44, 0.355), rot=(0.14, 0, 0), mi=l.mi("Steel"))             # swingarm
        tube(l.bm, fk(0.0, x=sx * 0.105), fk(0.76, x=sx * 0.105), 0.03, seg=4, mi=l.mi("Brass"))                  # fork leg
    tube(l.bm, m0, m1, 0.058, seg=5, mi=DARK)                                                 # muffler
    arc_box(l.bm, FA.y, FA.z, 0.33, 0.35, 0.072, 40, 148, n=3, mi=PAINT)                      # front fender
    loft(l.bm, [hexs(0.515, 0.085, 0.125, 0.095, 0.790, 0.900, 0.985),
                hexs(0.665, 0.055, 0.095, 0.070, 0.820, 0.878, 0.935)], mi=PAINT, cap_mi=PAINT)
    box(l.bm, (0.11, 0.016, 0.08), (0, 0.672, 0.878), mi=l.mi("M_Headlight"))
    tube(l.bm, (-0.37, Bc.y - 0.05, Bc.z + 0.04), (0.37, Bc.y - 0.05, Bc.z + 0.04), 0.018, seg=4, mi=DARK)   # bars
    hide_helper(l.finish("Body_LOD1", root))
    return root


# ================================================================================================
# BICYCLE - urban hardtail mountain bike, 1.75 m long
# ================================================================================================
def _bicycle_wheel(name, root, center, R, w, Rr, hub_w, rear=False, seg=24, n_spokes=16):
    b = MB()
    h = R - Rr
    half = [(-0.40 * w, Rr - 0.004), (-0.50 * w, Rr + 0.40 * h), (-0.33 * w, Rr + 0.86 * h)]
    prof = half + [(0.0, R)] + [(-a, r) for a, r in reversed(half)]
    revolve(b.bm, prof, seg, mi=b.mi("M_Tire"))
    b.flush(smooth=50)
    rim = [(-0.012, Rr + 0.004), (-0.012, Rr - 0.012), (0.0, Rr - 0.022), (0.012, Rr - 0.012), (0.012, Rr + 0.004)]
    revolve(b.bm, rim, seg, mi=b.mi("M_Rim"))
    b.flush(smooth=35)
    G.add_cylinder(b.bm, 0.017, hub_w, axis='X', segments=8, mat_index=b.mi("SteelDark"))
    for sx in (-1, 1):
        G.add_cylinder(b.bm, 0.03, 0.006, center=(sx * 0.03, 0, 0), axis='X', segments=10, mat_index=b.mi("M_Rim"))
    G.add_cylinder(b.bm, 0.082, 0.004, center=(-0.047, 0, 0), axis='X', segments=14, mat_index=b.mi("Steel"))   # brake rotor (left)
    if rear:
        G.add_cylinder(b.bm, 0.052, 0.032, center=(0.05, 0, 0), axis='X', segments=12, mat_index=b.mi("Steel"), radius2=0.026)  # cassette
    b.flush(smooth=35)
    SP = b.mi("M_Chrome")
    rr = Rr - 0.018
    for i in range(n_spokes):
        a = 2 * PI * i / n_spokes
        side = 1 if i % 2 == 0 else -1
        ah = a + (0.55 if (i // 2) % 2 == 0 else -0.55)
        tube(b.bm, (side * 0.03, 0.027 * math.cos(ah), 0.027 * math.sin(ah)),
             (0.0, rr * math.cos(a), rr * math.sin(a)), 0.0045, seg=3, mi=SP)
    b.flush(smooth=80)
    return b.finish(name, root, location=center)


def build_bicycle(index=1):
    root = G.asset_root("bicycle", "Vehicles/Motorcycles", G.slot("bikes", index))
    root["gta_name"] = "bicycle"
    R = 0.34
    FA = Vector((0.0, 0.54, R))
    RA = Vector((0.0, -0.53, R))
    BBp = Vector((0.0, -0.11, 0.29))          # bottom bracket
    ST = Vector((0.0, -0.245, 0.74))          # seat tube top
    HT1 = Vector((0.0, 0.343, 0.92))          # head tube top
    HT0 = Vector((0.0, 0.385, 0.80))          # head tube bottom
    UB = (HT1 - HT0).normalized()             # steering axis
    HC = (HT0 + HT1) * 0.5                    # Handlebar origin
    sdir = (ST - BBp).normalized()

    # ------------------------------------------------------------------ Body (frame, saddle, chain ...)
    b = MB()
    PAINT = b.mi("M_Paint_Primary")
    DARK = b.mi("SteelDark")
    TRIM = b.mi("M_Trim")
    CHROME = b.mi("M_Chrome")
    LEATHER = b.mi("Leather")
    # saddle
    # (critic pass: the saddle was a flat plank - now a dropped narrow nose, a waist, a wide
    #  padded rear with a kicked-up tail, and rails underneath)
    loft(b.bm, [sec_oct(-0.130, 0.015, 0.916, 0.936), sec_oct(-0.195, 0.024, 0.906, 0.944),
                sec_oct(-0.285, 0.040, 0.902, 0.945), sec_oct(-0.355, 0.074, 0.900, 0.954),
                sec_oct(-0.415, 0.084, 0.908, 0.968), sec_oct(-0.450, 0.062, 0.928, 0.978)], mi=LEATHER)
    cbox(b.bm, (0.058, 0.06, 0.028), (0, -0.292, 0.890), mi=DARK, bev=0.006)                  # saddle clamp
    for sx in (-1, 1):
        box(b.bm, (0.008, 0.045, 0.055), (sx * 0.07, RA.y, RA.z + 0.004), mi=PAINT)           # dropouts
    cbox(b.bm, (0.022, 0.035, 0.085), (0.064, -0.515, 0.265), mi=DARK, bev=0.005)            # rear derailleur
    cbox(b.bm, (0.02, 0.05, 0.032), (-0.06, -0.455, 0.405), mi=DARK, bev=0.005)              # rear brake caliper
    cbox(b.bm, (0.045, 0.016, 0.032), (0, -0.335, 0.878), mi=b.mi("M_Taillight"), bev=0.004)  # rear reflector
    # rear mudguard
    arc_shell(b.bm, RA.y, RA.z, 0.352, 0.032, 62, 158, n=6, thick=0.006, drop=0.012, mi=TRIM)
    b.flush()
    # tubes
    tube(b.bm, (0, -0.232, 0.705), (0, 0.349, 0.895), 0.017, seg=8, mi=PAINT)                # top tube
    tube(b.bm, (0, -0.09, 0.30), (0, 0.375, 0.815), 0.022, seg=8, mi=PAINT)                  # down tube
    tube(b.bm, BBp, ST, 0.017, seg=8, mi=PAINT)                                              # seat tube
    tube(b.bm, HT0, HT1, 0.025, seg=10, mi=PAINT)                                            # head tube
    for sx in (-1, 1):
        tube(b.bm, (sx * 0.035, -0.238, 0.70), (sx * 0.07, RA.y, RA.z), 0.009, seg=6, mi=PAINT)    # seat stays
        tube(b.bm, (sx * 0.03, -0.125, 0.29), (sx * 0.07, RA.y, RA.z), 0.011, seg=6, mi=PAINT)     # chain stays
        ang = math.radians(140.0)
        fp = (sx * 0.030, RA.y + 0.36 * math.cos(ang), RA.z + 0.36 * math.sin(ang))
        tube(b.bm, fp, (sx * 0.074, RA.y, RA.z), 0.004, seg=3, mi=CHROME)                          # mudguard stays
    tube(b.bm, (-0.03, -0.238, 0.70), (0.03, -0.238, 0.70), 0.009, seg=6, mi=PAINT)          # seat stay bridge
    G.add_cylinder(b.bm, 0.027, 0.075, center=BBp, axis='X', segments=10, mat_index=PAINT)   # BB shell
    tube(b.bm, ST - sdir * 0.01, ST + sdir * 0.03, 0.022, seg=8, mi=DARK)                    # seat collar
    tube(b.bm, ST, ST + sdir * 0.165, 0.0125, seg=8, mi=CHROME)                              # seat post
    for sx in (-1, 1):
        pipe(b.bm, [(sx * 0.014, -0.175, 0.912), (sx * 0.022, -0.26, 0.888), (sx * 0.024, -0.33, 0.888),
                    (sx * 0.034, -0.42, 0.916)], 0.004, seg=4, mi=CHROME)                      # saddle rails
    tube(b.bm, (-0.045, -0.185, 0.268), (-0.062, -0.47, 0.305), 0.007, seg=5, mi=DARK)       # kickstand (folded)
    tube(b.bm, (-0.062, -0.47, 0.305), (-0.085, -0.50, 0.300), 0.009, seg=5, mi=TRIM)        # kickstand foot
    # chain (right side)
    tube(b.bm, (0.056, BBp.y, BBp.z + 0.096), (0.056, RA.y, RA.z + 0.046), 0.006, seg=4, mi=DARK)
    tube(b.bm, (0.056, BBp.y, BBp.z - 0.096), (0.060, -0.505, 0.228), 0.006, seg=4, mi=DARK)
    tube(b.bm, (0.060, -0.505, 0.228), (0.058, RA.y + 0.01, RA.z - 0.04), 0.006, seg=4, mi=DARK)
    # water bottle on the down tube
    d0 = Vector((0, -0.09, 0.30))
    d1 = Vector((0, 0.375, 0.815))
    dd = (d1 - d0).normalized()
    dn = Vector((0, -dd.z, dd.y))
    bc = d0 + (d1 - d0) * 0.45 + dn * 0.056
    tube(b.bm, bc - dd * 0.09, bc + dd * 0.07, 0.034, seg=8, mi=b.mi("Teal"))
    tube(b.bm, bc + dd * 0.07, bc + dd * 0.10, 0.02, seg=8, mi=b.mi("White"))
    tube(b.bm, bc - dd * 0.06 - dn * 0.04, bc + dd * 0.03 - dn * 0.04, 0.012, seg=4, mi=DARK)   # cage
    b.flush(smooth=60)
    body = b.finish("Body", root)

    # ------------------------------------------------------------------ Handlebar (bars, stem, fork)
    h = MB()
    PAINT = h.mi("M_Paint_Primary")
    DARK = h.mi("SteelDark")
    CHROME = h.mi("M_Chrome")
    LEATHER = h.mi("Leather")
    crown = HT0 - UB * 0.02
    fdir = (Vector((0, FA.y, FA.z)) - crown).normalized()
    flen = (Vector((0, FA.y, FA.z)) - crown).length
    tilt = math.atan2(-fdir.y, -fdir.z) * -1.0
    cbox(h.bm, (0.155, 0.05, 0.036), crown, rot=(math.atan2(UB.y, UB.z) * -1.0, 0, 0), mi=DARK, bev=0.008)     # fork crown
    BCL = Vector((0.0, 0.43, 0.975))                                                          # bar clamp
    cbox(h.bm, (0.045, 0.03, 0.04), (0, 0.468, 0.972), mi=DARK, bev=0.006)                    # front lamp body
    box(h.bm, (0.036, 0.006, 0.03), (0, 0.485, 0.972), mi=h.mi("M_Headlight"))
    cbox(h.bm, (0.02, 0.032, 0.048), (-0.052, 0.515, 0.415), mi=DARK, bev=0.004)              # front brake caliper
    for sx in (-1, 1):
        box(h.bm, (0.01, 0.03, 0.045), (sx * 0.058, FA.y, FA.z), mi=DARK)                     # fork dropouts
        cbox(h.bm, (0.02, 0.022, 0.022), (sx * 0.205, 0.428, 1.003), mi=DARK, bev=0.004)      # lever clamps
    h.flush()
    steer_top = HT1 + UB * 0.045
    tube(h.bm, HT1, steer_top, 0.018, seg=8, mi=DARK)                                         # headset / spacers
    tube(h.bm, HT1 + UB * 0.028, BCL, 0.016, seg=6, mi=DARK)                                  # stem
    G.add_cylinder(h.bm, 0.021, 0.05, center=BCL, axis='X', segments=8, mat_index=DARK)
    bar_l = [(-0.33, 0.39, 1.02), (-0.15, 0.415, 1.015), (-0.05, 0.43, 0.975)]
    bar = bar_l + [(-p[0], p[1], p[2]) for p in reversed(bar_l)]
    pipe(h.bm, bar, 0.011, seg=6, mi=CHROME)
    for sx in (-1, 1):
        end = Vector((sx * 0.33, 0.39, 1.02))
        inner = Vector((sx * 0.15, 0.415, 1.015))
        d = (end - inner).normalized()
        tube(h.bm, end - d * 0.115, end + d * 0.004, 0.0175, seg=8, mi=LEATHER)               # grips
        tube(h.bm, (sx * 0.205, 0.435, 1.0), (sx * 0.315, 0.44, 0.992), 0.005, seg=4, mi=DARK)  # brake levers
        top = crown + Vector((sx * 0.058, 0, 0))
        mid = top + fdir * (flen * 0.42)
        bot = Vector((sx * 0.058, FA.y, FA.z))
        tube(h.bm, top, mid + fdir * 0.03, 0.014, seg=8, mi=CHROME)                           # stanchion
        tube(h.bm, mid, bot + fdir * 0.02, 0.021, seg=8, mi=PAINT)                            # lower leg
    # fork arch over the tyre
    lt = crown + fdir * (flen * 0.42)
    ap = Vector((0, FA.y, FA.z)) - fdir * 0.368
    pipe(h.bm, [(-0.058, lt.y + 0.012, lt.z), (-0.05, ap.y + 0.02, ap.z), (0.05, ap.y + 0.02, ap.z),
                (0.058, lt.y + 0.012, lt.z)], 0.011, seg=6, mi=PAINT)
    G.add_sphere(h.bm, 0.022, center=(-0.115, 0.418, 1.035), segments=8, rings=5, mat_index=CHROME, scale=(1, 1, 0.7))   # bell
    h.flush(smooth=60)
    handlebar = h.finish("Handlebar", root, origin=HC)

    # ------------------------------------------------------------------ Crank (chainring, arms, pedals)
    c = MB()
    DARK = c.mi("SteelDark")
    STEEL = c.mi("Steel")
    TRIM = c.mi("M_Trim")
    CL = 0.17
    cbox(c.bm, (0.014, CL + 0.03, 0.03), (0.074, CL * 0.5, 0), mi=DARK, bev=0.005)            # right arm (forward)
    cbox(c.bm, (0.014, CL + 0.03, 0.03), (-0.074, -CL * 0.5, 0), mi=DARK, bev=0.005)          # left arm (back)
    cbox(c.bm, (0.09, 0.075, 0.02), (0.128, CL, 0), mi=TRIM, bev=0.004)                       # pedals
    cbox(c.bm, (0.09, 0.075, 0.02), (-0.128, -CL, 0), mi=TRIM, bev=0.004)
    for px, py in ((0.128, CL), (-0.128, -CL)):                                               # pedal reflectors
        for e in (-1, 1):
            box(c.bm, (0.05, 0.005, 0.012), (px, py + e * 0.039, 0), mi=c.mi("M_Indicator"))
    spokes(c.bm, 5, 0.012, 0.082, 0.004, 0.004, 0.013, 0.009, mi=DARK, x_off=0.056, phase=0.3)   # spider
    c.flush()
    revolve(c.bm, [(0.052, 0.076), (0.060, 0.076), (0.060, 0.100), (0.052, 0.100)], 16, mi=STEEL)   # chainring
    G.add_cylinder(c.bm, 0.013, 0.165, axis='X', segments=8, mat_index=STEEL)                 # axle
    G.add_cylinder(c.bm, 0.006, 0.05, center=(0.105, CL, 0), axis='X', segments=6, mat_index=STEEL)
    G.add_cylinder(c.bm, 0.006, 0.05, center=(-0.105, -CL, 0), axis='X', segments=6, mat_index=STEEL)
    c.flush(smooth=40)
    crank = c.finish("Crank", root, location=BBp)

    # ------------------------------------------------------------------ wheels, collision, markers
    _bicycle_wheel("Wheel_F", root, FA, R, 0.048, 0.292, 0.10)
    _bicycle_wheel("Wheel_R", root, RA, R, 0.048, 0.292, 0.135, rear=True)
    prof = [(-0.45, 0.36), (-0.11, 0.24), (0.45, 0.40), (0.45, 1.00), (-0.42, 0.97)]
    col_hull("Col_Body", root, [(sx * 0.08, y, z) for sx in (-1, 1) for y, z in prof])
    marker("Seat_Driver", root, (0.0, -0.33, 1.04))
    marker("Exit_Driver", root, (-0.55, -0.10, 0.0))
    light_markers(root, "Light_Head", (0.0, 0.49, 0.972), 0.015)
    light_markers(root, "Light_Tail", (0.0, -0.345, 0.878), 0.015, back=True)
    marker("Steer_Axis", root, tuple(HC), rot=(math.atan2(UB.y, UB.z) * -1.0, 0, 0))
    for sx, tag in ((-1, "L"), (1, "R")):                # hand / foot targets for the rider pose
        end = Vector((sx * 0.33, 0.39, 1.02))
        d = (end - Vector((sx * 0.15, 0.415, 1.015))).normalized()
        child_marker("Grip_" + tag, root, handlebar, end - d * 0.055)       # grip centre, turns with the bars
        # pedal tops; children of Crank, so they orbit with it (right pedal is forward at rest)
        child_marker("Pedal_" + tag, root, crank, BBp + Vector((sx * 0.128, sx * CL, 0.012)))

    # ------------------------------------------------------------------ Body_LOD1 (replaces Body + Handlebar + Crank)
    l = MB()
    PAINT = l.mi("M_Paint_Primary")
    DARK = l.mi("SteelDark")
    tube(l.bm, (0, -0.232, 0.705), (0, 0.349, 0.895), 0.02, seg=3, mi=PAINT)
    tube(l.bm, (0, -0.09, 0.30), (0, 0.375, 0.815), 0.024, seg=3, mi=PAINT)
    tube(l.bm, BBp, ST + sdir * 0.165, 0.02, seg=3, mi=PAINT)
    tube(l.bm, HT0, HT1 + UB * 0.06, 0.026, seg=4, mi=PAINT)
    for sx in (-1, 1):
        tube(l.bm, (sx * 0.035, -0.238, 0.70), (sx * 0.07, RA.y, RA.z), 0.012, seg=3, mi=PAINT)
        tube(l.bm, (sx * 0.03, -0.125, 0.29), (sx * 0.07, RA.y, RA.z), 0.013, seg=3, mi=PAINT)
        tube(l.bm, crown + Vector((sx * 0.058, 0, 0)), (sx * 0.058, FA.y, FA.z), 0.02, seg=3, mi=PAINT)
    tube(l.bm, (-0.33, 0.40, 1.015), (0.33, 0.40, 1.015), 0.016, seg=3, mi=DARK)
    tube(l.bm, HT1 + UB * 0.04, (0, 0.42, 1.0), 0.018, seg=3, mi=DARK)
    loft(l.bm, [sec4(-0.14, 0.02, 0.91, 0.94), sec4(-0.44, 0.078, 0.915, 0.972)], mi=l.mi("Leather"))
    box(l.bm, (0.012, 0.19, 0.19), (0.056, BBp.y, BBp.z), rot=(0.785, 0, 0), mi=DARK)        # chainring plate
    box(l.bm, (0.30, 0.03, 0.03), (0.0, BBp.y, BBp.z), mi=DARK)                               # crank axle / pedals
    hide_helper(l.finish("Body_LOD1", root))
    return root


# ================================================================================================
# SPEEDBOAT - 6.9 m open sport boat (7.6 m with the outboard), deep-V hull, raked bow
# ================================================================================================
# hull stations: (y, keel z, chine half-width, chine z, gunwale half-width, gunwale z, stem rake)
# stem rake = how far the keel point of that section sits behind the gunwale point (raked bow).
# (critic pass: the sheer is now a real curve - lowest at the aft quarter, sweeping up to a high
#  bow - with more flare forward and a more raked stem; the artist's version was an almost straight
#  line, which made the boat read as a utility skiff.)
BOAT_ST = [
    (-3.20, -0.35, 0.92, -0.03, 1.05, 0.640, 0.0),
    (-2.00, -0.35, 0.99, -0.02, 1.14, 0.610, 0.0),
    (-0.50, -0.35, 1.00, -0.01, 1.18, 0.625, 0.0),
    (0.70, -0.34, 0.93, 0.02, 1.17, 0.700, 0.0),
    (1.70, -0.31, 0.75, 0.08, 1.08, 0.825, 0.02),
    (2.45, -0.24, 0.51, 0.18, 0.89, 0.945, 0.10),
    (3.00, -0.10, 0.28, 0.34, 0.61, 1.040, 0.22),
    (3.40, 0.16, 0.11, 0.57, 0.31, 1.105, 0.32),
    (3.78, 0.58, 0.02, 0.90, 0.05, 1.160, 0.42),
]


SPEEDBOAT_ARCH = True     # sport arch (wake tower) over the aft cockpit; False = the plain runabout


def _st_at(ST, y):
    """Piecewise-linear interpolation of a station table at y."""
    if y <= ST[0][0]:
        return ST[0]
    for a, b in zip(ST[:-1], ST[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))
    return ST[-1]


def _vhull_ring(ST, y, mode, zf=0.10, crown=0.0, cap_w=0.13):
    """16-point hull cross-section: keel, chine, chine flat, boot-stripe top, sheer-stripe line,
    gunwale, cap rail inner, then the deck (mode 'deck') or the cockpit wall + floor ('cockpit').
    The sheer stripe is a wedge: narrow at the stern, widening towards the bow."""
    _, zk, xc, zc, xg, zg, rk = _st_at(ST, y)
    c2 = (xc + 0.045, zc + 0.015)
    t = min(max((y - ST[0][0]) / (ST[-1][0] - ST[0][0]), 0.0), 1.0)
    fs = 0.13 + 0.20 * t                       # sheer stripe: fraction of the topside height
    fb = 0.13                                  # boot stripe (just above the chine)
    s = (xg + (c2[0] - xg) * fs, zg + (c2[1] - zg) * fs)
    bt = (c2[0] + (xg - c2[0]) * fb, c2[1] + (zg - c2[1]) * fb)
    gi = max(xg - cap_w, xg * 0.4)
    if mode == 'cockpit':
        w = (xc - 0.03, zf)
        fz = zf
    else:
        w = (gi * 0.5, zg + crown * 0.75)
        fz = zg + crown
    yc = y - rk * 0.55
    right = [(xc, yc, zc), (c2[0], yc, c2[1]), (bt[0], y - rk * 0.55 * (1.0 - fb), bt[1]),
             (s[0], y - rk * 0.55 * fs, s[1]), (xg, y, zg), (gi, y, zg), (w[0], y, w[1])]
    return [(0.0, y - rk, zk)] + right + [(0.0, y, fz)] + [(-x, yy, z) for x, yy, z in reversed(right)]


def _deck_z(ST, x, y, crown, cap_w=0.13):
    st = _st_at(ST, y)
    xg, zg = st[4], st[5]
    gi = max(xg - cap_w, xg * 0.4)
    x = abs(x)
    pts = [(0.0, zg + crown), (gi * 0.5, zg + crown * 0.75), (gi, zg), (xg, zg)]
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        if x0 <= x <= x1:
            return z0 + (z1 - z0) * (x - x0) / max(x1 - x0, 1e-6)
    return zg


def _outboard(name, root, pivot, scale=1.0, cowl_key="Charcoal", tiller=False):
    """Outboard motor authored around its steering pivot (= object origin).
    Local frame: +Y forward (towards the transom), -Y astern, prop at the bottom rear.
    tiller=True adds a tiller arm reaching forward into the boat (small tender engines)."""
    m = MB()
    COWL = m.mi(cowl_key)
    DARK = m.mi("SteelDark")
    WHITE = m.mi("CarWhite")
    k = scale

    def P(x, y, z):
        return (x * k, y * k, z * k)

    def osec(y, hw, zb, zt):
        return [P(*p) for p in sec_oct(y, hw, zb, zt)]
    # powerhead cowl
    loft(m.bm, [osec(0.02, 0.17, 0.18, 0.55), osec(-0.08, 0.23, 0.13, 0.63), osec(-0.36, 0.23, 0.13, 0.64),
                osec(-0.54, 0.19, 0.17, 0.57), osec(-0.63, 0.12, 0.24, 0.47)], mi=COWL)
    for sx in (-1, 1):
        box(m.bm, (0.006 * k, 0.34 * k, 0.045 * k), P(sx * 0.232, -0.22, 0.47), mi=WHITE)      # side stripe
    # apron under the cowl
    loft(m.bm, [osec(-0.03, 0.13, 0.00, 0.16), osec(-0.22, 0.15, -0.02, 0.16), osec(-0.44, 0.11, 0.02, 0.18)], mi=DARK)

    # leg (lofted along Z): sections are streamlined lozenges in the XY plane
    def lsec(z, hw, y0, y1):
        ym = (y0 + y1) * 0.5
        return [P(0, y0, z), P(hw, ym + (y0 - ym) * 0.4, z), P(hw, ym + (y1 - ym) * 0.4, z), P(0, y1, z),
                P(-hw, ym + (y1 - ym) * 0.4, z), P(-hw, ym + (y0 - ym) * 0.4, z)]
    loft(m.bm, [lsec(0.02, 0.10, -0.03, -0.40), lsec(-0.50, 0.065, -0.07, -0.34), lsec(-0.86, 0.05, -0.09, -0.34)], mi=DARK)
    cbox(m.bm, (0.26 * k, 0.44 * k, 0.022 * k), P(0, -0.30, -0.86), mi=DARK, bev=0.008 * k)    # anti-ventilation plate
    loft(m.bm, [lsec(-0.86, 0.04, -0.10, -0.33), lsec(-1.00, 0.04, -0.10, -0.33)], mi=DARK)    # strut
    loft(m.bm, [[P(-0.012, -0.12, -1.08), P(0.012, -0.12, -1.08), P(0.012, -0.38, -1.08), P(-0.012, -0.38, -1.08)],
                [P(-0.008, -0.26, -1.28), P(0.008, -0.26, -1.28), P(0.008, -0.34, -1.28), P(-0.008, -0.34, -1.28)]], mi=DARK)   # skeg
    cbox(m.bm, (0.20 * k, 0.07 * k, 0.26 * k), P(0, 0.0, 0.05), mi=DARK, bev=0.012 * k)        # swivel bracket
    # propeller blades
    hub = Vector(P(0, -0.47, -1.02))
    for i in range(3):
        a = 2 * PI * i / 3 + 0.4
        Ra = Matrix.Rotation(a, 3, 'Y')
        Rb = Ra @ Matrix.Rotation(math.radians(32), 3, 'Z')
        cbox(m.bm, (0.11 * k, 0.012 * k, 0.13 * k), hub + Ra @ Vector((0, 0, 0.095 * k)), rot=Rb, mi=m.mi("Brass"), bev=0.004 * k)
    m.flush()
    tube(m.bm, P(0, -0.06, -1.02), P(0, -0.42, -1.02), 0.07 * k, seg=10, mi=DARK)             # gearcase torpedo
    tube(m.bm, P(0, 0.03, -1.02), P(0, -0.064, -1.02), 0.02 * k, seg=10, mi=DARK, r2=0.07 * k)   # nose cone (overlaps: no welded ring)
    tube(m.bm, P(0, -0.42, -1.02), P(0, -0.52, -1.02), 0.05 * k, seg=10, mi=m.mi("Brass"), r2=0.03 * k)   # prop hub
    if tiller:                                                                                 # tiller arm + twist grip
        tube(m.bm, P(0, 0.0, 0.40), P(0, 0.62, 0.52), 0.028 * k, seg=6, mi=DARK)
        tube(m.bm, P(0, 0.62, 0.52), P(0, 0.90, 0.575), 0.038 * k, seg=8, mi=m.mi("M_Trim"))
    m.flush(smooth=45)
    return m.finish(name, root, location=pivot)


def _boat_seat(bm, x, y, zf, mi_shell, mi_cush, mi_metal, w=0.50):
    """Helm bucket seat on a pedestal; seat cushion top at zf + 0.38."""
    cbox(bm, (w, 0.50, 0.10), (x, y, zf + 0.28), mi=mi_shell, bev=0.025)
    cbox(bm, (w - 0.07, 0.42, 0.07), (x, y + 0.02, zf + 0.345), mi=mi_cush, bev=0.02)
    T = 0.20
    cbox(bm, (w, 0.10, 0.56), (x, y - 0.27, zf + 0.56), rot=(T, 0, 0), mi=mi_shell, bev=0.025)
    cbox(bm, (w - 0.09, 0.07, 0.44), (x, y - 0.225, zf + 0.58), rot=(T, 0, 0), mi=mi_cush, bev=0.02)
    for sx in (-1, 1):
        cbox(bm, (0.06, 0.34, 0.10), (x + sx * (w * 0.5 - 0.03), y - 0.03, zf + 0.37), mi=mi_shell, bev=0.02)   # bolsters
    G.add_cylinder(bm, 0.05, 0.17, center=(x, y, zf + 0.155), axis='Z', segments=8, mat_index=mi_metal)
    G.add_cylinder(bm, 0.12, 0.025, center=(x, y, zf + 0.0125), axis='Z', segments=10, mat_index=mi_metal)


def _cleat(bm, x, y, z, mi, along='Y', L=0.16):
    d = Vector((0, 1, 0)) if along == 'Y' else Vector((1, 0, 0))
    c = Vector((x, y, z))
    up = Vector((0, 0, 0.04))
    tube(bm, c - d * L * 0.5 + up, c + d * L * 0.5 + up, 0.012, seg=6, mi=mi)
    for s in (-1, 1):
        tube(bm, c + d * (s * L * 0.2) - up * 0.2, c + d * (s * L * 0.2) + up, 0.011, seg=6, mi=mi)


def build_speedboat(index=0):
    root = G.asset_root("speedboat", "Vehicles/Boats", G.slot("boats", index))
    root["gta_name"] = "speedboat"
    ST = BOAT_ST
    ZF = 0.10                   # cockpit floor
    Y_AFT = -2.30               # cockpit rear bulkhead (aft deck behind it)
    Y_DASH = 0.70               # cockpit front bulkhead (foredeck ahead of it)
    CROWN = 0.06

    def zg_at(y):
        return _st_at(ST, y)[5]

    def xg_at(y):
        return _st_at(ST, y)[4]

    b = MB()
    PAINT = b.mi("M_Paint_Primary")
    STRIPE = b.mi("M_Paint_Secondary")
    WHITE = b.mi("CarWhite")
    WOOD = b.mi("Wood")
    CREAM = b.mi("Cream")
    TRIM = b.mi("M_Trim")
    STEEL = b.mi("Steel")
    DARK = b.mi("SteelDark")
    CHROME = b.mi("M_Chrome")
    BOOT = b.mi("Charcoal")

    def sm(right):
        return list(right) + list(reversed(right))
    # strips: bottom, chine flat, boot stripe, topside, sheer stripe, cap rail, deck / wall, deck / floor
    deck_m = sm([WHITE, WHITE, BOOT, PAINT, STRIPE, WHITE, WHITE, WHITE])
    cock_m = sm([WHITE, WHITE, BOOT, PAINT, STRIPE, WHITE, WHITE, WOOD])

    ys = [s[0] for s in ST]
    aft = [y for y in ys if y < Y_AFT] + [Y_AFT]
    mid = [Y_AFT] + [y for y in ys if Y_AFT < y < Y_DASH] + [Y_DASH]
    fwd = [Y_DASH] + [y for y in ys if y > Y_DASH]
    loft(b.bm, [_vhull_ring(ST, y, 'deck', crown=0.0) for y in aft], strip_mi=deck_m, cap_start=True, cap_end=False, cap_mi=PAINT)
    loft(b.bm, [_vhull_ring(ST, Y_AFT, 'deck', crown=0.0), _vhull_ring(ST, Y_AFT, 'cockpit', zf=ZF)],
         mi=WHITE, cap_start=False, cap_end=False)
    loft(b.bm, [_vhull_ring(ST, y, 'cockpit', zf=ZF) for y in mid], strip_mi=cock_m, cap_start=False, cap_end=False)
    loft(b.bm, [_vhull_ring(ST, Y_DASH, 'cockpit', zf=ZF), _vhull_ring(ST, Y_DASH, 'deck', crown=CROWN)],
         mi=WHITE, cap_start=False, cap_end=False)
    loft(b.bm, [_vhull_ring(ST, y, 'deck', crown=CROWN) for y in fwd], strip_mi=deck_m, cap_start=False, cap_end=True, cap_mi=PAINT)
    b.flush()

    for sx in (-1, 1):
        # rub rail along the sheer
        secs = []
        for y in ys:
            xg, zg = xg_at(y), zg_at(y)
            secs.append([(sx * (xg - 0.012), y, zg - 0.05), (sx * (xg + 0.035), y, zg - 0.05),
                         (sx * (xg + 0.035), y, zg + 0.012), (sx * (xg - 0.012), y, zg + 0.012)])
        loft(b.bm, secs, mi=TRIM)
        # coaming pads inside the cockpit
        secs = []
        for y in (Y_AFT + 0.08, -1.2, -0.5, 0.20):
            gi, zg = xg_at(y) - 0.13, zg_at(y)
            secs.append([(sx * (gi - 0.075), y, zg - 0.20), (sx * (gi + 0.005), y, zg - 0.20),
                         (sx * (gi + 0.005), y, zg - 0.03), (sx * (gi - 0.055), y, zg - 0.03)])
        loft(b.bm, secs, mi=CREAM)
        # swim platforms
        cbox(b.bm, (0.56, 0.36, 0.05), (sx * 0.68, -3.37, 0.165), mi=WHITE, bev=0.015)
        box(b.bm, (0.48, 0.28, 0.012), (sx * 0.68, -3.37, 0.195), mi=WOOD)
        # helm seats, rear bench
        _boat_seat(b.bm, sx * 0.48, -0.22, ZF, WHITE, CREAM, STEEL)
        cbox(b.bm, (0.80, 0.46, 0.09), (sx * 0.42, Y_AFT + 0.29, ZF + 0.335), mi=CREAM, bev=0.025)
        cbox(b.bm, (0.80, 0.09, 0.40), (sx * 0.42, Y_AFT + 0.075, ZF + 0.56), rot=(0.12, 0, 0), mi=CREAM, bev=0.025)
        # bow sun pad
        z = _deck_z(ST, 0.45, 1.75, CROWN)
        cbox(b.bm, (0.48, 1.05, 0.075), (sx * 0.25, 1.75, z + 0.02), mi=CREAM, bev=0.02)
    cbox(b.bm, (1.74, 0.52, 0.22), (0, Y_AFT + 0.27, ZF + 0.11), mi=WHITE, bev=0.02)             # bench base
    box(b.bm, (1.50, 0.62, 0.014), (0, -2.76, zg_at(-2.76) + 0.005), mi=WOOD)                     # teak aft deck inlay
    # dashboard cowl (rises above the foredeck, carries the windshield)
    DZ = zg_at(Y_DASH) + CROWN + 0.08
    zfwd = zg_at(Y_DASH + 0.30) - 0.02
    prism_x(b.bm, [(Y_DASH + 0.02, DZ - 0.52), (Y_DASH - 0.33, DZ - 0.47), (Y_DASH - 0.35, DZ - 0.29),
                   (Y_DASH - 0.23, DZ - 0.03), (Y_DASH - 0.18, DZ), (Y_DASH + 0.30, zfwd)], -0.93, 0.93, mi=WHITE)

    def cowl_z(y):
        t = (y - (Y_DASH - 0.18)) / 0.48
        return DZ + (zfwd - DZ) * t
    DT = -0.433
    dn = Vector((0.0, -math.cos(DT), -math.sin(DT)))             # dash face normal (towards the driver, up)
    fc = Vector((0.0, Y_DASH - 0.29, DZ - 0.16))
    HX = 0.48                                                    # helm on the starboard side
    cbox(b.bm, (0.56, 0.012, 0.25), fc + dn * 0.004 + Vector((HX, 0, 0)), rot=(DT, 0, 0), mi=TRIM, bev=0.004)
    cbox(b.bm, (0.44, 0.012, 0.16), fc + dn * 0.004 + Vector((-HX, 0, 0.02)), rot=(DT, 0, 0), mi=TRIM, bev=0.004)
    cbox(b.bm, (0.08, 0.16, 0.12), (0.955, 0.10, 0.40), mi=DARK, bev=0.012)                      # throttle box
    cbox(b.bm, (0.035, 0.045, 0.05), (0.925, 0.195, 0.675), mi=TRIM, bev=0.01)                   # throttle knob
    cbox(b.bm, (0.30, 0.12, 0.34), (0, -3.25, 0.44), mi=DARK, bev=0.015)                         # transom bracket
    # lifting strakes on the V bottom (two per side) + trim tabs at the transom
    for sx in (-1, 1):
        for f, y_end in ((0.36, 2.45), (0.68, 1.70)):
            secs = []
            for y in [yy for yy in ys if yy < y_end] + [y_end]:
                st = _st_at(ST, y)
                zk, xc, zc = st[1], st[2], st[3]
                dx, dz = xc, zc - zk
                ln = math.hypot(dx, dz)
                ux, uz = dx / ln, dz / ln                              # along the bottom, keel -> chine
                nx, nz = uz, -ux                                       # outward (down) normal
                x0, z0 = xc * f, zk + dz * f
                k = 1.0 if y < y_end else 0.15                         # taper out at the front end
                secs.append([(sx * (x0 - ux * 0.03), y - st[6] * (1 - f * 0.45), z0 - uz * 0.03 + 0.004),
                             (sx * (x0 + ux * 0.03), y - st[6] * (1 - f * 0.45), z0 + uz * 0.03 + 0.004),
                             (sx * (x0 + ux * 0.03 + nx * 0.03 * k), y - st[6] * (1 - f * 0.45), z0 + uz * 0.03 + nz * 0.03 * k)])
            loft(b.bm, secs, mi=WHITE)
        cbox(b.bm, (0.34, 0.20, 0.014), (sx * 0.56, -3.29, -0.165), rot=(0.0, -sx * 0.335, 0.0), mi=STEEL, bev=0.004)   # trim tab
    # navigation lights
    zb = _deck_z(ST, 0.0, 3.42, CROWN)
    box(b.bm, (0.05, 0.07, 0.05), (0.03, 3.44, zb + 0.015), mi=b.mi("NeonGreen"))
    box(b.bm, (0.05, 0.07, 0.05), (-0.03, 3.44, zb + 0.015), mi=b.mi("SirenRed"))
    SLX = -(xg_at(-3.0) - 0.07)
    AY0, AY1, ATOP, AXT = -1.66, -0.98, 2.04, 0.82               # sport arch: foot y, top y, top z, top half-width
    if SPEEDBOAT_ARCH:
        # white top fairing of the arch with forward flood lamps and the all-round light
        prism_x(b.bm, [(AY1 + 0.10, ATOP - 0.035), (AY1 + 0.06, ATOP + 0.035), (AY1 - 0.26, ATOP + 0.075),
                       (AY1 - 0.34, ATOP + 0.045), (AY1 - 0.30, ATOP - 0.005)], -AXT - 0.03, AXT + 0.03, mi=WHITE)
        for lx in (-0.46, 0.46):
            cbox(b.bm, (0.16, 0.05, 0.07), (lx, AY1 + 0.085, ATOP - 0.065), mi=TRIM, bev=0.012)
            box(b.bm, (0.13, 0.008, 0.045), (lx, AY1 + 0.112, ATOP - 0.065), mi=b.mi("M_Headlight"))
        cbox(b.bm, (0.06, 0.06, 0.07), (0, AY1 - 0.12, ATOP + 0.115), mi=b.mi("M_Headlight"), bev=0.014)   # all-round light
    else:
        cbox(b.bm, (0.05, 0.05, 0.06), (SLX, -3.0, 1.27), mi=b.mi("M_Headlight"), bev=0.012)     # stern light
    b.flush()

    # round parts
    hubp = fc + dn * 0.13 + Vector((HX, 0, 0.0))
    tube(b.bm, fc + Vector((HX, 0, 0)), hubp, 0.022, seg=8, mi=DARK)                             # steering column
    for gx in (HX - 0.19, HX + 0.19):
        tube(b.bm, fc + Vector((gx, 0, 0.06)) + dn * 0.004, fc + Vector((gx, 0, 0.06)) + dn * 0.02, 0.045, seg=10, mi=WHITE)
    tube(b.bm, (0.945, 0.11, 0.44), (0.925, 0.19, 0.66), 0.011, seg=6, mi=STEEL)                 # throttle lever
    if SPEEDBOAT_ARCH:
        # sport arch over the aft cockpit: swept-forward alloy legs with rear braces
        for sx in (-1, 1):
            foot = Vector((sx * (xg_at(AY0) - 0.065), AY0, zg_at(AY0)))
            foot2 = Vector((sx * (xg_at(AY0 - 0.50) - 0.065), AY0 - 0.50, zg_at(AY0 - 0.50)))
            knee = Vector((sx * (xg_at(AY0) - 0.11), AY0 + 0.20, zg_at(AY0) + 0.80))
            top = Vector((sx * AXT, AY1, ATOP))
            pipe(b.bm, [foot, knee, top], 0.027, seg=6, mi=STEEL)
            pipe(b.bm, [foot2, knee + Vector((0, -0.07, 0.03)), top + Vector((0, -0.24, 0.02))], 0.021, seg=6, mi=STEEL)
            tube(b.bm, foot - Vector((0, 0, 0.004)), foot + Vector((0, 0, 0.03)), 0.045, seg=8, mi=STEEL)      # deck sockets
            tube(b.bm, foot2 - Vector((0, 0, 0.004)), foot2 + Vector((0, 0, 0.03)), 0.04, seg=8, mi=STEEL)
        tube(b.bm, (-AXT, AY1, ATOP), (AXT, AY1, ATOP), 0.027, seg=6, mi=STEEL)
        tube(b.bm, (-AXT, AY1 - 0.24, ATOP + 0.02), (AXT, AY1 - 0.24, ATOP + 0.02), 0.021, seg=6, mi=STEEL)
        tube(b.bm, (0.55, AY1 - 0.20, ATOP + 0.06), (0.55, AY1 - 0.34, ATOP + 0.42), 0.007, seg=4, mi=TRIM)     # whip antenna
    else:
        tube(b.bm, (SLX, -3.0, zg_at(-3.0)), (SLX, -3.0, 1.24), 0.009, seg=6, mi=STEEL)          # stern light pole
    # windshield frame
    A = Vector((0.50, Y_DASH + 0.16, cowl_z(Y_DASH + 0.16) + 0.004))
    D = Vector((0.44, Y_DASH - 0.18, 1.30))
    A2 = Vector((1.07, Y_DASH - 0.04, zg_at(Y_DASH - 0.04) + 0.005))
    D2 = Vector((0.96, Y_DASH - 0.30, 1.24))
    Bp = Vector((1.11, Y_DASH - 0.80, zg_at(Y_DASH - 0.80) + 0.005))
    C = Vector((1.08, Y_DASH - 0.88, 0.90))

    def mx(v):
        return Vector((-v.x, v.y, v.z))
    pipe(b.bm, [mx(Bp), mx(C), mx(D2), mx(D), D, D2, C, Bp], 0.013, seg=6, mi=STEEL)
    pipe(b.bm, [mx(Bp), mx(A2), mx(A), A, A2, Bp], 0.017, seg=6, mi=TRIM)
    for p, q in ((A, D), (A2, D2), (mx(A), mx(D)), (mx(A2), mx(D2))):
        tube(b.bm, p, q, 0.011, seg=6, mi=STEEL)

    # bow rail
    def rp(y, side, lift):
        return Vector((side * max(xg_at(y) - 0.085, 0.0), y, zg_at(y) + lift))
    rail_ys = [2.05, 2.5, 3.0, 3.36]
    left = [rp(1.82, -1, 0.0)] + [rp(y, -1, 0.24) for y in rail_ys]
    right = [rp(y, 1, 0.24) for y in reversed(rail_ys)] + [rp(1.82, 1, 0.0)]
    tip = Vector((0.0, 3.62, zg_at(3.62) + 0.24))
    pipe(b.bm, left + [tip] + right, 0.014, seg=6, mi=STEEL)
    for y in (2.5, 3.0):
        for side in (-1, 1):
            tube(b.bm, rp(y, side, 0.0), rp(y, side, 0.24), 0.011, seg=6, mi=STEEL)
    tube(b.bm, Vector((0, 3.58, zg_at(3.58))), tip, 0.011, seg=6, mi=STEEL)
    # cleats, grab rails
    for sx in (-1, 1):
        _cleat(b.bm, sx * 0.36, 2.95, _deck_z(ST, 0.36, 2.95, CROWN), CHROME)
        _cleat(b.bm, sx * (xg_at(-2.95) - 0.07), -2.95, zg_at(-2.95), CHROME)
        if not SPEEDBOAT_ARCH:                                   # (the arch feet stand where the grab rails were)
            gx = xg_at(-1.4) - 0.065
            zg = zg_at(-1.4)
            pipe(b.bm, [(sx * gx, -1.80, zg - 0.01), (sx * gx, -1.75, zg + 0.07), (sx * gx, -1.05, zg + 0.085), (sx * gx, -1.0, zg + 0.005)],
                 0.012, seg=6, mi=STEEL)
    b.flush(smooth=60)
    b.finish("Body", root)

    # ------------------------------------------------------------------ windshield glass
    g = MB()
    GL = g.mi("M_Glass")
    pane(g.bm, [mx(A), A, D, mx(D)], 0.012, GL)
    for f in (lambda v: v, mx):
        pane(g.bm, [f(A), f(A2), f(D2), f(D)], 0.012, GL)
        pane(g.bm, [f(A2), f(Bp), f(C), f(D2)], 0.012, GL)
    g.finish("Glass_Windshield", root)

    # ------------------------------------------------------------------ steering wheel (spins about its local Y)
    w = MB()
    rim = [(0.017 * math.cos(a), 0.17 + 0.017 * math.sin(a)) for a in [i * PI / 3 for i in range(6)]]
    revolve(w.bm, rim, 14, axis='Y', mi=w.mi("M_Trim"))
    G.add_cylinder(w.bm, 0.045, 0.04, axis='Y', segments=10, mat_index=w.mi("Steel"))
    for a in (PI * 0.5, PI * 0.5 + 2.2, PI * 0.5 - 2.2):
        tube(w.bm, (0, 0, 0), (0.165 * math.cos(a), 0.0, 0.165 * math.sin(a)), 0.012, seg=4, mi=w.mi("Steel"))
    w.flush(smooth=60)
    w.finish("SteeringWheel", root, location=hubp, rotation=(DT, 0, 0))

    # ------------------------------------------------------------------ outboard
    PIV = Vector((0.0, -3.38, 0.45))
    _outboard("Motor", root, PIV)

    # ------------------------------------------------------------------ collision + markers
    pts = []
    for i in (0, 2, 4, 6, 8):
        y, zk, xc, zc, xg, zg, rk = ST[i]
        pts.append((0.0, y - rk, zk))
        for sx in (-1, 1):
            pts.append((sx * (xc + 0.045), y - rk * 0.55, zc + 0.015))
            pts.append((sx * xg, y, zg))
    col_hull("Col_Body", root, pts)
    marker("Seat_Driver", root, (0.48, -0.26, ZF + 0.48))
    marker("Seat_Passenger_1", root, (-0.48, -0.26, ZF + 0.48))
    marker("Seat_Passenger_2", root, (-0.42, Y_AFT + 0.32, ZF + 0.48))
    marker("Seat_Passenger_3", root, (0.42, Y_AFT + 0.32, ZF + 0.48))
    marker("Exit_Driver", root, (0.0, -2.76, zg_at(-2.76) + 0.02))
    marker("Exit_Passenger_1", root, (-0.60, -2.76, zg_at(-2.76) + 0.02))
    marker("Exit_Passenger_2", root, (0.60, -2.76, zg_at(-2.76) + 0.02))
    marker("Exit_Passenger_3", root, (0.0, 1.10, _deck_z(ST, 0.0, 1.10, CROWN) + 0.11))
    marker("Prop", root, (0.0, PIV.y - 0.48, PIV.z - 1.02))
    marker("Wake_L", root, (-0.93, -3.20, 0.0))
    marker("Wake_R", root, (0.93, -3.20, 0.0))
    marker("Engine", root, (0.0, PIV.y - 0.24, PIV.z + 0.62))
    light_markers(root, "Light_Head", (0.0, 3.50, zg_at(3.5) + 0.02), 0.22)
    light_markers(root, "Light_Tail", (0.0, -3.22, zg_at(-3.2) - 0.06), 0.90, back=True)

    # ------------------------------------------------------------------ Body_LOD1 (replaces every mesh part)
    l = MB()
    PAINT = l.mi("M_Paint_Primary")
    WHITE = l.mi("CarWhite")
    WOOD = l.mi("Wood")
    CREAM = l.mi("Cream")
    LSTR = l.mi("M_Paint_Secondary")
    dk = [WHITE, PAINT, LSTR, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, LSTR, PAINT, WHITE]
    ck = [WHITE, PAINT, LSTR, WHITE, WHITE, WOOD, WOOD, WHITE, WHITE, LSTR, PAINT, WHITE]

    def lring(y, mode, crown=0.0):
        r = _vhull_ring(ST, y, mode, zf=ZF, crown=crown)          # keep: keel, chine flat, stripe line, gunwale, cap, wall
        return [r[i] for i in (0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14)]
    loft(l.bm, [lring(-3.20, 'deck'), lring(Y_AFT, 'deck')], strip_mi=dk, cap_start=True, cap_end=False, cap_mi=PAINT)
    loft(l.bm, [lring(Y_AFT, 'deck'), lring(Y_AFT, 'cockpit')], mi=WHITE, cap_start=False, cap_end=False)
    loft(l.bm, [lring(Y_AFT, 'cockpit'), lring(-0.50, 'cockpit'), lring(Y_DASH, 'cockpit')], strip_mi=ck, cap_start=False, cap_end=False)
    loft(l.bm, [lring(Y_DASH, 'cockpit'), lring(Y_DASH, 'deck', CROWN)], mi=WHITE, cap_start=False, cap_end=False)
    loft(l.bm, [lring(y, 'deck', CROWN) for y in (Y_DASH, 1.70, 2.45, 3.40, ST[-1][0])], strip_mi=dk, cap_start=False, cap_end=True, cap_mi=PAINT)
    for sx in (-1, 1):
        box(l.bm, (0.48, 0.14, 0.56), (sx * 0.48, -0.48, ZF + 0.56), rot=(0.2, 0, 0), mi=CREAM)   # helm seat backs
        box(l.bm, (0.46, 0.46, 0.12), (sx * 0.48, -0.20, ZF + 0.32), mi=CREAM)
    box(l.bm, (1.70, 0.50, 0.42), (0, Y_AFT + 0.27, ZF + 0.21), mi=CREAM)                          # bench
    box(l.bm, (1.66, 0.12, 0.40), (0, Y_AFT + 0.07, ZF + 0.58), mi=CREAM)
    prism_x(l.bm, [(Y_DASH + 0.02, DZ - 0.52), (Y_DASH - 0.34, DZ - 0.40), (Y_DASH - 0.20, DZ), (Y_DASH + 0.30, zfwd)], -0.93, 0.93, mi=WHITE)
    GLM = l.mi("M_Glass")
    pane(l.bm, [mx(A), A, D, mx(D)], 0.012, GLM)
    for f in (lambda v: v, mx):
        pane(l.bm, [f(A), f(Bp), f(C), f(D)], 0.012, GLM)
    if SPEEDBOAT_ARCH:
        LST = l.mi("Steel")
        for sx in (-1, 1):
            tube(l.bm, (sx * (xg_at(AY0) - 0.065), AY0, zg_at(AY0)), (sx * AXT, AY1, ATOP), 0.035, seg=3, mi=LST)
            tube(l.bm, (sx * (xg_at(AY0 - 0.5) - 0.065), AY0 - 0.5, zg_at(AY0 - 0.5)), (sx * AXT, AY1 - 0.24, ATOP), 0.03, seg=3, mi=LST)
        box(l.bm, (AXT * 2 + 0.06, 0.42, 0.09), (0, AY1 - 0.12, ATOP + 0.02), mi=WHITE)
    box(l.bm, (0.46, 0.62, 0.50), (0, PIV.y - 0.30, PIV.z + 0.38), mi=l.mi("Charcoal"))            # outboard cowl
    box(l.bm, (0.14, 0.30, 1.10), (0, PIV.y - 0.20, PIV.z - 0.50), mi=l.mi("SteelDark"))           # outboard leg
    hide_helper(l.finish("Body_LOD1", root))
    return root


# ================================================================================================
# JETSKI (stretch) - 3.3 m sit-down personal watercraft, 2 seats, steerable jet nozzle ("Motor")
# Rebuilt in the art-critic pass: wedge hood rising to an instrument cowl, tapered seat pedestal
# with sloped ends, stepped two-up saddle, side fairings that rise towards the bow, raked prow.
# ================================================================================================
# hull stations: (y, keel z, chine half-width, chine z, bond-line half-width, bond-line z, stem rake)
JETSKI_ST = [
    (-1.55, -0.19, 0.42, -0.06, 0.55, 0.17, 0.0),
    (-1.00, -0.22, 0.46, -0.07, 0.59, 0.19, 0.0),
    (-0.20, -0.22, 0.48, -0.06, 0.61, 0.21, 0.0),
    (0.45, -0.21, 0.45, -0.04, 0.59, 0.25, 0.0),
    (0.95, -0.16, 0.35, 0.03, 0.50, 0.31, 0.03),
    (1.35, -0.05, 0.20, 0.15, 0.32, 0.38, 0.08),
    (1.62, 0.14, 0.08, 0.31, 0.13, 0.44, 0.14),
    (1.76, 0.36, 0.02, 0.43, 0.04, 0.475, 0.20),
]
# deck stations: (y, gunwale inset, gunwale rise above the bond line, well outer x, z,
#                 pedestal base x, z, pedestal top x, z, centre-line z)
JETSKI_DECK = [
    (-1.55, 0.060, 0.070, 0.42, 0.250, 0.22, 0.255, 0.12, 0.260, 0.262),    # boarding platform
    (-1.22, 0.060, 0.075, 0.45, 0.262, 0.24, 0.268, 0.13, 0.274, 0.278),
    (-0.98, 0.050, 0.100, 0.47, 0.150, 0.26, 0.150, 0.17, 0.520, 0.550),    # footwells + seat pedestal
    (-0.20, 0.050, 0.110, 0.50, 0.150, 0.27, 0.150, 0.18, 0.550, 0.580),
    (0.25, 0.050, 0.130, 0.48, 0.165, 0.28, 0.165, 0.20, 0.620, 0.670),
    (0.38, 0.055, 0.140, 0.46, 0.300, 0.30, 0.400, 0.19, 0.720, 0.770),     # foot brace / knee panel
    (0.52, 0.060, 0.150, 0.44, 0.470, 0.31, 0.640, 0.18, 0.810, 0.860),     # cowl shoulder (highest)
    (0.72, 0.060, 0.140, 0.40, 0.490, 0.27, 0.660, 0.15, 0.800, 0.845),
    (1.02, 0.060, 0.115, 0.31, 0.500, 0.21, 0.645, 0.11, 0.735, 0.760),     # hood (convex in profile)
    (1.35, 0.050, 0.080, 0.21, 0.495, 0.14, 0.575, 0.07, 0.625, 0.645),
    (1.62, 0.030, 0.038, 0.075, 0.492, 0.048, 0.512, 0.022, 0.528, 0.535),
    (1.76, 0.012, 0.008, 0.022, 0.488, 0.014, 0.491, 0.006, 0.494, 0.496),
]
JETSKI_YS = [s[0] for s in JETSKI_DECK]
# ring point indices (right side; left side = 16 - i)
JS_KEEL, JS_CHINE, JS_BOND, JS_LIP, JS_GUN, JS_WELL, JS_PEDB, JS_PEDT, JS_TOP = range(9)


def _jetski_ring(y):
    """16-point section: keel, chine, bond line, lip, gunwale top, well outer, pedestal base,
    pedestal top, centre top, then the mirrored left side."""
    _, zk, xc, zc, xb, zb, rk = _st_at(JETSKI_ST, y)
    _, gi, gz, xw, zw, xp1, zp1, xp2, zp2, zt = _st_at(JETSKI_DECK, y)
    yc = y - rk * 0.55
    right = [(xc, yc, zc), (xb, y, zb), (xb - gi * 0.35, y, zb + gz * 0.5), (xb - gi, y, zb + gz),
             (xw, y, zw), (xp1, y, zp1), (xp2, y, zp2)]
    return [(0.0, y - rk, zk)] + right + [(0.0, y, zt)] + [(-x, yy, z) for x, yy, z in reversed(right)]


def decal(bm, q, uv, mi, thick=0.014):
    """Thin raised plate on a loft quad q = [a0, b0, b1, a1] (u runs a -> b, v runs 0 -> 1).
    uv = four (u, v) corners.  Used for vents, graphics and mats that must hug a sloped panel."""
    q = [Vector(p) for p in q]

    def pt(u, v):
        return q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)
    return pane(bm, [pt(u, v) for u, v in uv], thick, mi)


def build_jetski(index=1):
    root = G.asset_root("jetski", "Vehicles/Boats", G.slot("boats", index))
    root["gta_name"] = "jetski"
    ST = JETSKI_ST
    b = MB()
    PAINT = b.mi("M_Paint_Primary")
    STRIPE = b.mi("M_Paint_Secondary")
    HULL = b.mi("Charcoal")
    MAT = b.mi("M_Trim")
    SEAT = b.mi("M_Interior")
    STEEL = b.mi("Steel")
    DARK = b.mi("SteelDark")
    SMOKE = b.mi("WindowDark")
    R = _jetski_ring

    def sm(right):
        return list(right) + list(reversed(right))

    def mirror_i(i):
        return 16 - i

    def side_x(y, z):
        """Half-width of the hull side (between chine and bond line) at station y, height z."""
        st = _st_at(ST, y)
        return st[2] + (st[4] - st[2]) * (z - st[3]) / (st[5] - st[3])

    def ringq(ya, yb, i, j, sx=1):
        """Loft quad between stations ya, yb and ring points i, j (sx = -1: the mirrored side)."""
        A, B = R(ya), R(yb)
        if sx < 0:
            i, j = mirror_i(i), mirror_i(j)
        return [A[i], B[i], B[j], A[j]]

    plat_m = sm([HULL, HULL, PAINT, PAINT, MAT, MAT, MAT, MAT])
    well_m = sm([HULL, HULL, PAINT, PAINT, PAINT, MAT, PAINT, PAINT])
    hood_m = sm([HULL, HULL, PAINT, PAINT, PAINT, PAINT, PAINT, STRIPE])
    loft(b.bm, [R(y) for y in (-1.55, -1.22)], strip_mi=plat_m, cap_start=True, cap_end=False, cap_mi=HULL)
    loft(b.bm, [R(y) for y in (-1.22, -0.98, -0.20, 0.25, 0.38, 0.52)], strip_mi=well_m, cap_start=False, cap_end=False)
    loft(b.bm, [R(y) for y in (0.52, 0.72, 1.02, 1.35, 1.62, 1.76)], strip_mi=hood_m, cap_start=False, cap_end=True, cap_mi=PAINT)
    b.flush()

    # saddle: tail, passenger bolster, passenger seat, step, driver dip, nose rising to the cowl
    loft(b.bm, [sec_oct(-1.21, 0.10, 0.50, 0.64), sec_oct(-1.11, 0.165, 0.50, 0.790), sec_oct(-0.96, 0.20, 0.51, 0.850),
                sec_oct(-0.80, 0.21, 0.52, 0.825), sec_oct(-0.50, 0.205, 0.53, 0.815), sec_oct(-0.38, 0.20, 0.54, 0.735),
                sec_oct(-0.12, 0.185, 0.56, 0.700), sec_oct(0.14, 0.16, 0.60, 0.745), sec_oct(0.34, 0.115, 0.66, 0.830)],
         mi=SEAT)
    cbox(b.bm, (0.43, 0.045, 0.03), (0, -0.64, 0.815), mi=MAT, bev=0.008)                              # passenger strap
    for sx in (-1, 1):
        # bumper strip along the bond line (same stations as the hull, so it hugs it exactly)
        secs = []
        for y in JETSKI_YS:
            st = _st_at(ST, y)
            xb, zb = st[4], st[5]
            secs.append([(sx * (xb - 0.012), y, zb - 0.035), (sx * (xb + 0.03), y, zb - 0.035),
                         (sx * (xb + 0.03), y, zb + 0.03), (sx * (xb - 0.012), y, zb + 0.03)])
        loft(b.bm, secs, mi=MAT)
        # sponson: a strake that hugs the flared hull side just above the chine (tapered ends)
        secs = []
        for y, hh, th in ((-1.46, 0.016, 0.030), (-1.39, 0.036, 0.062), (-0.98, 0.036, 0.062), (-0.88, 0.014, 0.026)):
            z0, z1 = 0.03 - hh, 0.03 + hh
            x0, x1 = side_x(y, z0) - 0.015, side_x(y, z1) - 0.015
            secs.append([(sx * x0, y, z0), (sx * (x0 + th), y, z0 + 0.008), (sx * (x1 + th), y, z1), (sx * x1, y, z1)])
        loft(b.bm, secs, mi=MAT)
        # mirror: a wedge fairing growing out of the hood flank, mirror head on top
        loft(b.bm, [sec_oct(0.50, 0.042, 0.50, 0.675, cx=sx * 0.365), sec_oct(0.62, 0.048, 0.52, 0.670, cx=sx * 0.36),
                    sec_oct(0.80, 0.036, 0.52, 0.625, cx=sx * 0.325), sec_oct(0.96, 0.016, 0.50, 0.565, cx=sx * 0.285)], mi=PAINT)
        cbox(b.bm, (0.135, 0.05, 0.085), (sx * 0.395, 0.545, 0.705), rot=(0, 0, -sx * 0.25), mi=MAT, bev=0.014)   # mirror head
        box(b.bm, (0.112, 0.004, 0.062), (sx * 0.389, 0.5195, 0.705), rot=(0, 0, -sx * 0.25), mi=b.mi("M_Chrome"))
        # hood intake slats (on the upper hood flank) and the swoosh graphic on the pedestal
        for v0, v1 in ((0.18, 0.40), (0.56, 0.78)):
            decal(b.bm, ringq(0.72, 1.02, JS_PEDB, JS_PEDT, sx), [(0.12, v0), (0.78, v0), (0.70, v1), (0.04, v1)], MAT)
        decal(b.bm, ringq(-0.98, -0.20, JS_PEDB, JS_PEDT, sx), [(0.30, 0.16), (1.0, 0.46), (1.0, 0.80), (0.30, 0.34)], STRIPE, thick=0.010)
        decal(b.bm, ringq(-0.20, 0.25, JS_PEDB, JS_PEDT, sx), [(0.0, 0.46), (0.82, 0.74), (0.82, 0.96), (0.0, 0.80)], STRIPE, thick=0.010)
        # traction mat ribs on the footwell floor
        for u in (0.18, 0.40, 0.62, 0.84):
            decal(b.bm, ringq(-0.98, -0.20, JS_WELL, JS_PEDB, sx), [(u, 0.12), (u + 0.10, 0.12), (u + 0.10, 0.88), (u, 0.88)], DARK, thick=0.010)
    cbox(b.bm, (0.10, 0.07, 0.085), (0, 1.765, 0.455), mi=MAT, bev=0.02)                               # bow bumper cap
    # instrument cowl ahead of the bars, smoked deflector on its sloped front, gauge facing the rider
    loft(b.bm, [sec_oct(0.47, 0.165, 0.78, 0.905), sec_oct(0.56, 0.170, 0.80, 0.965), sec_oct(0.70, 0.140, 0.80, 0.925),
                sec_oct(0.88, 0.075, 0.74, 0.810)], mi=PAINT)
    pane(b.bm, [(-0.115, 0.585, 0.968), (0.115, 0.585, 0.968), (0.09, 0.705, 0.930), (-0.09, 0.705, 0.930)], 0.012, SMOKE)
    pane(b.bm, [(-0.09, 0.715, 0.927), (0.09, 0.715, 0.927), (0.045, 0.86, 0.823), (-0.045, 0.86, 0.823)], 0.012, SMOKE)
    cbox(b.bm, (0.20, 0.014, 0.075), (0, 0.464, 0.855), rot=(-0.12, 0, 0), mi=SMOKE, bev=0.004)        # gauge
    cbox(b.bm, (0.14, 0.10, 0.10), (0, 0.43, 0.80), mi=MAT, bev=0.015)                                 # steering column boot
    cbox(b.bm, (0.34, 0.26, 0.02), (0, -1.38, 0.268), mi=DARK, bev=0.006)                              # platform mat
    cbox(b.bm, (0.06, 0.04, 0.03), (0, 1.52, 0.575), mi=STEEL, bev=0.008)                              # hood latch
    b.flush()
    pipe(b.bm, [(-0.19, -1.02, 0.60), (-0.17, -1.27, 0.70), (0.17, -1.27, 0.70), (0.19, -1.02, 0.60)], 0.015, seg=6, mi=STEEL)   # grab rail
    pipe(b.bm, [(-0.40, -1.54, 0.12), (-0.40, -1.60, -0.10), (-0.20, -1.60, -0.10), (-0.20, -1.54, 0.12)], 0.012, seg=5, mi=STEEL)   # reboarding step
    tube(b.bm, (0, 1.60, 0.335), (0, 1.66, 0.325), 0.02, seg=6, mi=STEEL)                              # bow eye
    tube(b.bm, (0, -1.54, 0.215), (0, -1.585, 0.215), 0.022, seg=6, mi=STEEL)                          # tow hook
    tube(b.bm, (0, -1.40, -0.07), (0, -1.56, -0.07), 0.10, seg=10, mi=DARK)                            # pump housing
    G.add_cylinder(b.bm, 0.035, 0.012, center=(0.0, 1.20, 0.700), axis='Z', segments=8, mat_index=DARK, rot=(-0.34, 0, 0))   # fuel cap
    b.flush(smooth=60)
    b.finish("Body", root)

    # ------------------------------------------------------------------ Handlebar (origin on the steering axis)
    SA = math.radians(24.0)
    HO = Vector((0.0, 0.44, 0.86))
    UA = Vector((0.0, -math.sin(SA), math.cos(SA)))
    BCc = HO + UA * 0.13
    h = MB()
    TRIM = h.mi("M_Trim")
    cbox(h.bm, (0.21, 0.115, 0.085), BCc + UA * 0.005, rot=(SA, 0, 0), mi=h.mi("M_Paint_Primary"), bev=0.02)        # bar cover
    cbox(h.bm, (0.15, 0.085, 0.03), BCc + UA * 0.055, rot=(SA, 0, 0), mi=h.mi("M_Paint_Secondary"), bev=0.01)       # crash pad
    for sx in (-1, 1):
        cbox(h.bm, (0.035, 0.035, 0.04), (sx * 0.21, BCc.y - 0.035, BCc.z + 0.03), mi=TRIM, bev=0.006)   # lever clamps
    h.flush()
    tube(h.bm, HO - UA * 0.04, BCc, 0.03, seg=8, mi=h.mi("SteelDark"))
    bar_l = [(-0.36, BCc.y - 0.075, BCc.z + 0.035), (-0.16, BCc.y - 0.02, BCc.z + 0.025), (0.0, BCc.y, BCc.z)]
    bar = bar_l + [(-p[0], p[1], p[2]) for p in reversed(bar_l[:-1])]
    pipe(h.bm, bar, 0.015, seg=6, mi=h.mi("SteelDark"))
    for sx in (-1, 1):
        end = Vector((sx * 0.36, BCc.y - 0.075, BCc.z + 0.035))
        inner = Vector((sx * 0.16, BCc.y - 0.02, BCc.z + 0.025))
        d = (end - inner).normalized()
        tube(h.bm, end - d * 0.12, end + d * 0.005, 0.021, seg=8, mi=TRIM)                              # grips
        tube(h.bm, (sx * 0.21, BCc.y - 0.02, BCc.z + 0.035), (sx * 0.34, BCc.y - 0.04, BCc.z + 0.03), 0.006, seg=4, mi=h.mi("Steel"))   # levers
    h.flush(smooth=60)
    handlebar = h.finish("Handlebar", root, origin=HO)
    for sx, tag in ((-1, "L"), (1, "R")):                # hand / foot targets for the rider pose
        end = Vector((sx * 0.36, BCc.y - 0.075, BCc.z + 0.035))
        d = (end - Vector((sx * 0.16, BCc.y - 0.02, BCc.z + 0.025))).normalized()
        child_marker("Grip_" + tag, root, handlebar, end - d * 0.06)        # grip centre, turns with the bars
        marker("Footrest_" + tag, root, (sx * 0.38, -0.12, 0.165), size=0.06)   # footwell floor

    # ------------------------------------------------------------------ steerable jet nozzle
    NP = Vector((0.0, -1.56, -0.07))
    n = MB()
    tube(n.bm, (0, 0.02, 0), (0, -0.13, 0), 0.085, seg=10, mi=n.mi("SteelDark"), r2=0.06)
    tube(n.bm, (0, -0.02, 0), (0, -0.05, 0), 0.092, seg=10, mi=n.mi("Steel"))
    n.flush(smooth=45)
    n.finish("Motor", root, location=NP)

    # ------------------------------------------------------------------ collision + markers
    pts = []
    for i in (0, 2, 4, 6):
        y, zk, xc, zc, xb, zb, rk = ST[i]
        pts.append((0.0, y - rk, zk))
        for sx in (-1, 1):
            pts.append((sx * xc, y - rk * 0.55, zc))
            pts.append((sx * xb, y, zb + 0.03))
    pts.append((0.0, 1.76, 0.49))
    for sx in (-1, 1):
        pts += [(sx * 0.19, -1.05, 0.84), (sx * 0.18, 0.30, 0.80), (sx * 0.17, 0.58, 0.96)]
    col_hull("Col_Body", root, pts)
    marker("Seat_Driver", root, (0.0, -0.14, 0.79))
    marker("Seat_Passenger_1", root, (0.0, -0.68, 0.90))
    marker("Exit_Driver", root, (-0.95, -0.20, 0.0))
    marker("Exit_Passenger_1", root, (0.95, -0.65, 0.0))
    marker("Prop", root, (0.0, -1.70, -0.07))
    marker("Wake_L", root, (-0.40, -1.55, 0.0))
    marker("Wake_R", root, (0.40, -1.55, 0.0))
    marker("Engine", root, (0.0, 0.95, 0.70))
    light_markers(root, "Light_Head", (0.0, 1.72, 0.50), 0.06)
    marker("Steer_Axis", root, tuple(HO), rot=(SA, 0, 0))

    # ------------------------------------------------------------------ Body_LOD1
    l = MB()
    lp, lh, lm, ls = l.mi("M_Paint_Primary"), l.mi("Charcoal"), l.mi("M_Trim"), l.mi("M_Paint_Secondary")
    keep = (JS_KEEL, JS_CHINE, JS_BOND, JS_GUN, JS_WELL, JS_PEDB, JS_PEDT, JS_TOP)

    def lring(y):
        r = R(y)
        idx = list(keep) + [mirror_i(i) for i in reversed(keep[1:-1])]
        return [r[i] for i in idx]

    def lsm(right):
        return list(right) + list(reversed(right))
    loft(l.bm, [lring(-1.55), lring(-1.22)], strip_mi=lsm([lh, lh, lp, lm, lm, lm, lm]), cap_start=True, cap_end=False, cap_mi=lh)
    loft(l.bm, [lring(y) for y in (-1.22, -0.98, 0.25, 0.52)], strip_mi=lsm([lh, lh, lp, lp, lm, lp, lp]), cap_start=False, cap_end=False)
    loft(l.bm, [lring(y) for y in (0.52, 1.02, 1.76)], strip_mi=lsm([lh, lh, lp, lp, lp, lp, ls]), cap_start=False, cap_end=True, cap_mi=lp)
    loft(l.bm, [sec4(-1.19, 0.12, 0.50, 0.70), sec4(-0.96, 0.20, 0.51, 0.845), sec4(-0.50, 0.20, 0.53, 0.81),
                sec4(-0.36, 0.20, 0.54, 0.73), sec4(0.34, 0.12, 0.66, 0.83)], mi=l.mi("M_Interior"))
    loft(l.bm, [sec4(0.47, 0.165, 0.78, 0.93), sec4(0.88, 0.075, 0.74, 0.81)], mi=lp)                   # cowl
    tube(l.bm, (-0.36, BCc.y - 0.05, BCc.z + 0.03), (0.36, BCc.y - 0.05, BCc.z + 0.03), 0.022, seg=4, mi=lm)
    hide_helper(l.finish("Body_LOD1", root))
    return root


# ================================================================================================
# DINGHY (stretch) - 3.6 m inflatable tender with a small tiller outboard
# ================================================================================================
def build_dinghy(index=2):
    root = G.asset_root("dinghy", "Vehicles/Boats", G.slot("boats", index))
    root["gta_name"] = "dinghy"
    TR = 0.21                                       # tube radius
    # tube centre line, port side from the tail cone to the bow: (x, y, z, radius)
    # (critic pass: the bow now sweeps up ~0.24 m like a real inflatable; it was almost level)
    side = [(-0.62, -1.76, 0.20, 0.07), (-0.62, -1.52, 0.20, TR), (-0.63, -0.60, 0.20, TR), (-0.62, 0.30, 0.225, TR),
            (-0.55, 0.88, 0.29, 0.205), (-0.39, 1.28, 0.37, 0.20), (-0.15, 1.50, 0.425, 0.20)]
    BOWZ = 0.44
    path = side + [(0.0, 1.55, BOWZ, 0.20)] + [(-x, y, z, r) for x, y, z, r in reversed(side)]

    b = MB()
    PAINT = b.mi("M_Paint_Primary")
    STRIPE = b.mi("M_Paint_Secondary")
    HULL = b.mi("Charcoal")
    WOOD = b.mi("Wood")
    WOODD = b.mi("WoodDark")
    TRIM = b.mi("M_Trim")
    STEEL = b.mi("Steel")
    ORANGE = b.mi("SafetyOrange")
    # rigid V floor between the tubes: (y, half-width, keel z, chine z, floor z)
    FL = [(-1.44, 0.50, -0.13, 0.03, 0.06), (-0.60, 0.50, -0.14, 0.03, 0.06), (0.30, 0.49, -0.13, 0.03, 0.06),
          (0.88, 0.42, -0.08, 0.08, 0.11), (1.26, 0.25, 0.05, 0.19, 0.21), (1.44, 0.07, 0.19, 0.28, 0.30)]
    fl_m = [HULL, HULL, HULL, WOOD, HULL]
    loft(b.bm, [[(-xw, y, z0), (0.0, y, zk), (xw, y, z0), (xw, y, zf), (-xw, y, zf)] for y, xw, zk, z0, zf in FL],
         strip_mi=fl_m, cap_mi=HULL)
    cbox(b.bm, (0.94, 0.05, 0.44), (0, -1.44, 0.215), mi=WOODD, bev=0.012)                    # transom
    cbox(b.bm, (0.30, 0.07, 0.22), (0, -1.445, 0.34), mi=STEEL, bev=0.008)                    # motor clamp plate
    cbox(b.bm, (1.00, 0.24, 0.04), (0, -0.30, 0.36), mi=WOOD, bev=0.01)                       # mid thwart
    cbox(b.bm, (1.00, 0.22, 0.04), (0, -1.08, 0.36), mi=WOOD, bev=0.01)                       # stern thwart
    cbox(b.bm, (0.30, 0.22, 0.20), (-0.24, -1.26, 0.16), mi=b.mi("FireRed"), bev=0.03)        # fuel tank
    cbox(b.bm, (0.34, 0.26, 0.11), (0.0, 0.98, 0.19), rot=(0, 0, 0.3), mi=ORANGE, bev=0.03)   # life jacket / dry bag
    for sx in (-1, 1):
        cbox(b.bm, (0.13, 0.40, 0.02), (sx * 0.13, 0.52, 0.092), mi=ORANGE, bev=0.006)        # oar blades
        cbox(b.bm, (0.05, 0.07, 0.035), (sx * 0.615, -0.30, 0.425), mi=TRIM, bev=0.01)        # oarlocks
    b.flush()
    # tubes (smooth)
    pipe(b.bm, [p[:3] for p in path], [p[3] for p in path], seg=10, mi=PAINT)
    for x, y, z, r in (side[2], side[3], side[4]):
        for sx in (-1, 1):
            tube(b.bm, (sx * x, y - 0.03, z), (sx * x, y + 0.03, z), r + 0.006, seg=10, mi=STRIPE)   # seam bands
    b.flush(smooth=62)
    # rub strake on the outer equator, handles, oars
    out = []
    n = len(path)
    for i, (x, y, z, r) in enumerate(path[1:-1], start=1):
        p0 = Vector(path[i - 1][:3])
        p1 = Vector(path[i + 1][:3])
        t = (p1 - p0).normalized()
        o = Vector((t.y, -t.x, 0.0)).normalized()          # horizontal normal, pointing outboard (path runs port -> bow -> starboard)
        out.append(Vector((x, y, z)) - o * (r - 0.005))
    pipe(b.bm, out, 0.028, seg=6, mi=TRIM)
    for sx in (-1, 1):
        for y0 in (-0.95, 0.10):
            pipe(b.bm, [(sx * 0.60, y0, 0.405), (sx * 0.60, y0 + 0.04, 0.455), (sx * 0.60, y0 + 0.22, 0.455), (sx * 0.60, y0 + 0.26, 0.405)],
                 0.012, seg=5, mi=b.mi("Cream"))                                                 # grab handles
        tube(b.bm, (sx * 0.13, -0.98, 0.085), (sx * 0.13, 0.36, 0.085), 0.017, seg=6, mi=STEEL)  # oar shafts
        tube(b.bm, (sx * 0.13, -1.0, 0.085), (sx * 0.13, -0.86, 0.085), 0.022, seg=6, mi=TRIM)   # oar grips
    G.add_cylinder(b.bm, 0.03, 0.03, center=(-0.24, -1.20, 0.27), axis='Z', segments=8, mat_index=TRIM)   # fuel cap
    tube(b.bm, (0, 1.72, BOWZ - 0.025), (0, 1.80, BOWZ - 0.055), 0.02, seg=6, mi=STEEL)         # bow ring
    b.flush(smooth=60)
    b.finish("Body", root)

    # ------------------------------------------------------------------ outboard with tiller
    PIV = Vector((0.0, -1.52, 0.38))
    K = 0.6
    motor = _outboard("Motor", root, PIV, scale=K, tiller=True)

    # ------------------------------------------------------------------ collision + markers
    pts = [(0.0, 1.75, BOWZ), (0.0, 1.55, BOWZ - 0.21), (0.0, 1.55, BOWZ + 0.205), (0.0, -1.44, -0.13), (0.0, 0.30, -0.14)]
    for x, y, z, r in (side[1], side[2], side[3], side[4]):
        for sx in (-1, 1):
            pts += [(sx * (abs(x) + r), y, z), (sx * abs(x), y, z - r), (sx * abs(x), y, z + r)]
    col_hull("Col_Body", root, pts)
    marker("Seat_Driver", root, (0.22, -1.08, 0.48))
    marker("Seat_Passenger_1", root, (0.0, -0.30, 0.48))
    marker("Exit_Driver", root, (0.0, 0.25, 0.07))
    marker("Exit_Passenger_1", root, (0.0, 0.70, 0.10))
    marker("Prop", root, (0.0, PIV.y - 0.48 * K, PIV.z - 1.02 * K))
    marker("Wake_L", root, (-0.62, -1.55, 0.0))
    marker("Wake_R", root, (0.62, -1.55, 0.0))
    marker("Engine", root, (0.0, PIV.y - 0.24 * K, PIV.z + 0.62 * K))
    light_markers(root, "Light_Head", (0.0, 1.72, BOWZ + 0.035), 0.10)

    # ------------------------------------------------------------------ Body_LOD1
    l = MB()
    lpath = [path[i] for i in (0, 1, 3, 4, 5, 7, 9, 10, 11, 13, 14)]
    pipe(l.bm, [p[:3] for p in lpath], [p[3] for p in lpath], seg=5, mi=l.mi("M_Paint_Primary"))
    l.flush(smooth=80)
    loft(l.bm, [[(-xw, y, z0), (0.0, y, zk), (xw, y, z0), (xw, y, zf), (-xw, y, zf)] for y, xw, zk, z0, zf in (FL[0], FL[2], FL[4], FL[5])],
         strip_mi=[l.mi("Charcoal"), l.mi("Charcoal"), l.mi("Charcoal"), l.mi("Wood"), l.mi("Charcoal")], cap_mi=l.mi("Charcoal"))
    box(l.bm, (0.94, 0.05, 0.44), (0, -1.44, 0.215), mi=l.mi("WoodDark"))
    box(l.bm, (1.00, 0.24, 0.04), (0, -0.30, 0.36), mi=l.mi("Wood"))
    box(l.bm, (1.00, 0.22, 0.04), (0, -1.08, 0.36), mi=l.mi("Wood"))
    box(l.bm, (0.28, 0.38, 0.32), (0, PIV.y - 0.18, PIV.z + 0.22), mi=l.mi("Charcoal"))
    box(l.bm, (0.09, 0.18, 0.66), (0, PIV.y - 0.12, PIV.z - 0.30), mi=l.mi("SteelDark"))
    hide_helper(l.finish("Body_LOD1", root))
    return root


# single-view close-ups written by qa_all(): id -> {suffix: (view direction, margin)}
ZOOMS = {
    "motorcycle": {"a": ((1.0, 0.0, 0.12), 0.62), "b": ((-1.0, 0.0, 0.12), 0.62)},
    "bicycle": {"a": ((0.8, 0.9, 0.45), 0.80)},
    "speedboat": {"a": ((0.8, 0.9, 0.42), 0.86), "b": ((-0.6, -1.0, 0.25), 0.86)},
    "jetski": {"a": ((0.9, 0.7, 0.5), 0.90), "b": ((-0.7, -1.0, 0.4), 0.90)},
    "dinghy": {"a": ((0.8, 0.9, 0.5), 0.90), "b": ((-0.7, -1.0, 0.45), 0.90)},
}


def qa_all(names=None, zooms=True, lods=True):
    """Regenerate every QA picture of this set: qa/blender_previews/<id>.png (5-view sheet),
    <id>_zoom_<x>.png (close-ups) and <id>_lod1.png (distance shell)."""
    for name in (names or list(ASSETS)):
        qa(name)
        if zooms:
            for tag, (view, margin) in ZOOMS.get(name, {}).items():
                G.preview(name, "%s_zoom_%s" % (name, tag), views=(view,), res=900, margin=margin)
        if lods:
            qa_lod(name)


ASSETS = {
    "motorcycle": build_motorcycle,
    "bicycle": build_bicycle,
    "speedboat": build_speedboat,
    "jetski": build_jetski,
    "dinghy": build_dinghy,
}


def build_all(names=None, do_export=True):
    """Rebuild (and export) every asset of this module - the reproducible pipeline entry point."""
    for name in (names or list(ASSETS)):
        ASSETS[name]()
        rep = G.validate(name)
        if do_export and rep.get("ok"):
            export(name)
