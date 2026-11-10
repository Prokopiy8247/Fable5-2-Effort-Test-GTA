"""cars_service_qa - QA helpers of the service-vehicle critic (ambulance, firetruck, swat_van, box_truck).

Read-only helpers: tri breakdowns, close previews, LOD / collision previews, contract audit.
Nothing in here changes an asset.  Use inside an execute_blender_code call:

    import cars_service_qa as Q; importlib.reload(Q)
    Q.breakdown("firetruck")
    Q.close("firetruck", "crit_firetruck_c")
"""
import bpy
from mathutils import Vector

import gta_bl as G
import car_kit as K

NAMES = ("ambulance", "firetruck", "swat_van", "box_truck")


def _tris(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def breakdown(name, by_material=True):
    """Tri count per object and (for Body) per material."""
    root = bpy.data.objects[name]
    vis = 0
    rows = []
    for o in sorted(root.children_recursive, key=lambda o: o.name):
        if o.type != 'MESH':
            continue
        t = _tris(o)
        sn = K.short_name(o)
        hidden = sn.startswith("Col_") or sn == "Body_LOD1"
        if not hidden:
            vis += t
        rows.append((sn, t, len(o.data.materials)))
    print("BREAKDOWN %s: visible=%d  %s" % (name, vis, ", ".join("%s=%d/%dm" % r for r in rows)))
    if by_material:
        body = bpy.data.objects.get(name + K.NAME_SEP + "Body")
        if body is not None:
            me = body.data
            me.calc_loop_triangles()
            cnt = {}
            for lt in me.loop_triangles:
                m = me.materials[lt.material_index]
                cnt[m.name] = cnt.get(m.name, 0) + 1
            print("  Body by material:", ", ".join("%s=%d" % kv for kv in sorted(cnt.items(), key=lambda kv: -kv[1])))
    return vis


def close(name, out, views=("three_quarter", "rear_quarter"), res=512, margin=0.80):
    return G.preview(name, out, views=views, res=res, margin=margin)


def only(name, out, parts, views=("three_quarter", "rear_quarter", "side", "top"), res=420, margin=1.0):
    """Preview only the named parts (e.g. Body_LOD1, Col_*) - temporarily un-hides them for the render."""
    root = bpy.data.objects[name]
    saved = []
    try:
        for o in root.children_recursive:
            saved.append((o, o.hide_render))
            o.hide_render = K.short_name(o) not in parts
        return G.preview(name, out, views=views, res=res, margin=margin)
    finally:
        for o, h in saved:
            o.hide_render = h


def lod_preview(name, out=None):
    wheels = [K.short_name(o) for o in bpy.data.objects[name].children_recursive if K.short_name(o).startswith("Wheel_")]
    return only(name, out or ("crit_%s_lod" % name), ["Body_LOD1"] + wheels)


def col_preview(name, out=None):
    parts = [K.short_name(o) for o in bpy.data.objects[name].children_recursive if K.short_name(o).startswith("Col_")]
    return only(name, out or ("crit_%s_col" % name), parts, views=("three_quarter", "side", "front", "top"))


def audit(name):
    """Contract audit in Blender: pivots, markers, materials, helper sizes."""
    root = bpy.data.objects[name]
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted()
    out = []
    for o in sorted(root.children_recursive, key=lambda o: o.name):
        sn = K.short_name(o)
        loc = inv @ o.matrix_world.translation
        if o.type == 'MESH':
            me = o.data
            bb = [inv @ (o.matrix_world @ Vector(c)) for c in o.bound_box]
            mn = Vector((min(p.x for p in bb), min(p.y for p in bb), min(p.z for p in bb)))
            mx = Vector((max(p.x for p in bb), max(p.y for p in bb), max(p.z for p in bb)))
            out.append("%-18s MESH loc=(%.3f,%.3f,%.3f) bb=(%.2f..%.2f, %.2f..%.2f, %.2f..%.2f) v=%d t=%d mats=%s parent=%s" % (
                sn, loc.x, loc.y, loc.z, mn.x, mx.x, mn.y, mx.y, mn.z, mx.z, len(me.vertices), _tris(o),
                [m.name for m in me.materials], K.short_name(o.parent)))
        else:
            out.append("%-18s EMPTY loc=(%.3f,%.3f,%.3f) parent=%s" % (sn, loc.x, loc.y, loc.z, K.short_name(o.parent)))
    print("AUDIT %s\n  " % name + "\n  ".join(out))
