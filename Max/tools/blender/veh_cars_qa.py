"""veh_cars_qa - small QA / batch helpers for veh_cars (run inside Blender through the MCP).

    import veh_cars_qa as Q; importlib.reload(Q)
    print(Q.qa("car_police"))            # rebuild (no export) + one-line stats / contract checks
    print(Q.finish("car_police"))        # export GLB + manifest entry (quiet)
    Q.door("car_police", "door_fl", 60)  # open a door for the hinge check; Q.door(..., 0) resets
"""
import contextlib
import io
import math
import sys

import bpy
from mathutils import Vector

import gta_kit as K

NEED_PARTS = ["body", "door_fl", "door_fr", "wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr", "steering", "lod1",
              "col_body", "col_cabin"]
NEED_MARKERS = ["seat_driver", "seat_passenger", "light_head_l", "light_head_r", "light_tail_l", "light_tail_r",
                "exhaust", "engine", "mod_spoiler", "mod_hood", "mod_roof", "mod_front", "mod_rear", "mod_skirt_l",
                "mod_skirt_r"]


def _M():
    return sys.modules["veh_cars"]


def _part(root, name):
    return bpy.data.objects.get("%s__%s" % (root.name, name))


def _zmin(root, o):
    mw = root.matrix_world.inverted() @ o.matrix_world
    return min((mw @ v.co).z for v in o.data.vertices)


def report(car):
    M = _M()
    root = car.root
    bpy.context.view_layer.update()
    st = K.asset_stats(root)
    parts, markers = M.parts_of(root)
    lod0, lod1, col = M.tri_split(root)
    out = []
    out.append("%s tris=%d lod1=%d col=%d size=%s min=%s max=%s" % (car.id, lod0, lod1, col, st["size"], st["min"],
                                                                 st["max"]))
    body = _part(root, "body")
    mw = root.matrix_world.inverted() @ body.matrix_world
    xs = [(mw @ v.co) for v in body.data.vertices]
    out.append("body bbox x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f tris=%d" % (
        min(p.x for p in xs), max(p.x for p in xs), min(p.y for p in xs), max(p.y for p in xs),
        min(p.z for p in xs), max(p.z for p in xs), len(body.data.polygons) and sum(len(p.vertices) - 2 for p in body.data.polygons)))
    w = []
    for n in ("wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"):
        o = _part(root, n)
        if o:
            w.append("%s(%.3f,%.3f,%.3f zmin %.3f)" % (n[-2:], o.location.x, o.location.y, o.location.z, _zmin(root, o)))
    out.append("wheels " + " ".join(w) + " arch_r=%.3f tyre_out=%.3f W2=%.3f" % (
        car.ra, car.track_f * 0.5 + car.s["wheel_w"] * 0.5, car.W2))
    d = []
    for n in ("door_fl", "door_fr", "door_rl", "door_rr"):
        o = _part(root, n)
        if o:
            o.data.calc_loop_triangles()
            ys = [v.co.y for v in o.data.vertices]
            d.append("%s org(%.3f,%.3f,%.3f) y%+.2f..%+.2f t=%d" % (n[-2:], o.location.x, o.location.y, o.location.z,
                                                                    min(ys), max(ys), len(o.data.loop_triangles)))
    out.append("doors " + " ".join(d))
    cols = []
    for n in parts:
        if n.startswith("col_"):
            cols.append("%s:%dv" % (n, len(_part(root, n).data.vertices)))
    mats = set()
    for o in root.children_recursive:
        if o.type == "MESH":
            for m in o.data.materials:
                mats.add(m.name)
    out.append("col " + " ".join(cols) + " | mats " + ",".join(sorted(mats)))
    miss = [p for p in NEED_PARTS if p not in parts] + [m for m in NEED_MARKERS if m not in markers]
    extra_p = [p for p in parts if p not in NEED_PARTS and p not in ("door_rl", "door_rr")]
    extra_m = [m for m in markers if m not in NEED_MARKERS]
    out.append("missing=%s extra_parts=%s extra_markers=%s" % (miss, extra_p, extra_m))
    mk = car.marker_pos
    out.append("mk " + " ".join("%s(%.2f,%.2f,%.2f)" % (k, v[0], v[1], v[2]) for k, v in mk.items()
                                if k in ("seat_driver", "seat_rl", "light_head_l", "light_tail_l", "exhaust", "engine",
                                         "siren", "mod_spoiler", "mod_roof", "mod_front", "mod_rear", "mod_skirt_l")))
    warn = []
    if lod0 > 4500:
        warn.append("TRIS>4500")
    if lod1 > 350:
        warn.append("LOD>350")
    for n in parts:
        if n.startswith("col_") and len(_part(root, n).data.vertices) > 24:
            warn.append(n + ">24v")
    for n in ("wheel_fl", "wheel_rl"):
        o = _part(root, n)
        if o and abs(_zmin(root, o)) > 0.013:      # 14-gon tyre: the bottom facet sits r*(1-cos(pi/14)) above z=0
            warn.append(n + " not on ground")
    if st["min"][2] < -0.002:
        warn.append("below ground %.3f" % st["min"][2])
    out.append("WARN " + (", ".join(warn) if warn else "none"))
    return "\n".join(out)


def qa(cid):
    """Rebuild one vehicle (no export) and return the stats / contract report."""
    M = _M()
    car = M.build(cid)
    return report(car)


def finish(cid, save=False):
    """Rebuild + export + manifest (quiet)."""
    M = _M()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        e = M.make(cid, export=True, save=False)
    if save:
        with contextlib.redirect_stdout(buf):
            K.save_master()
    return "%s exported tris=%d lod1=%d size=%s" % (cid, e["tris"], e["tris_lod1"], e["size"])


def door(cid, part="door_fl", deg=60.0):
    """Rotate a door about its local Z (hinge check). deg=0 resets."""
    o = bpy.data.objects["%s__%s" % (cid, part)]
    sign = -1.0 if part.endswith("l") else 1.0
    o.rotation_euler = (0.0, 0.0, math.radians(deg) * sign)
    return o.name, deg


def show(cid, lod=False, col=False):
    """Toggle visibility of the lod1 / col parts of one vehicle for a look."""
    root = bpy.data.objects[cid]
    for o in root.children_recursive:
        n = o.name.split("__", 1)[1]
        if o.type != "MESH":
            continue
        if n == "lod1":
            o.hide_set(not lod)
        elif n.startswith("col_"):
            o.hide_set(not col)
        else:
            o.hide_set(lod or col)
    return cid, lod, col
