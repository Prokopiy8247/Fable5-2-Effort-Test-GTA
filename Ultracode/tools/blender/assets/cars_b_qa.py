"""cars_b_qa - QA / close-up preview helpers of the cars_b critic (suv, pickup, van, police_cruiser, taxi).

Read-only towards the scene: everything that is changed for a render (visibility, camera, render and
shading settings, poses) is restored afterwards.  Usage inside an execute_blender_code call after the
gta_bl header (tools/blender/assets on sys.path):

    import cars_b_qa as Q; importlib.reload(Q)
    Q.tight("van", "crit_veh_van_a", [("fq", None, None), ("rq", None, None)])
    Q.tight("police_cruiser", "crit_bar", [((0.4, 1, 0.5), (0, 0, 1.5), 1.6)])   # zoom on a detail
    Q.posed("pickup", "crit_pickup_open", {"Tailgate": ("x", 1.5)}, [("rq", None, None)])
    Q.audit("van")
"""
import math
import os
import re

import bpy
from mathutils import Vector, Euler

import gta_bl as G

DIRS = {
    "fq": (0.80, 1.0, 0.40), "rq": (-0.80, -1.0, 0.42), "fq_l": (-0.80, 1.0, 0.40), "rq_r": (0.80, -1.0, 0.42),
    "side": (1.0, 0.0, 0.06), "side_l": (-1.0, 0.0, 0.06), "front": (0.0, 1.0, 0.08), "back": (0.0, -1.0, 0.08),
    "top": (0.0, -0.001, 1.0), "low_f": (0.55, 1.0, 0.12), "low_r": (-0.55, -1.0, 0.14), "under": (0.3, -0.5, -1.0),
    "high_f": (0.5, 1.0, 0.9), "high_r": (-0.5, -1.0, 0.9),
}


def _objs(names, include=None, only=None):
    """Objects of the asset roots. include = short part names to un-hide for the render (Mod_* ...),
    only = render nothing but these short part names."""
    if isinstance(names, str):
        names = [names]
    objs, show = [], []
    for n in names:
        root = bpy.data.objects.get(n)
        if root is None:
            raise RuntimeError("no object named %r" % n)
        for o in [root] + list(root.children_recursive):
            short = o.name.split(":", 1)[-1]
            if only is not None:
                if short in only:
                    objs.append(o)
                    if o.hide_render:
                        show.append(o)
                continue
            if o.hide_render and include and (short in include or any(short.startswith(i) for i in include)):
                show.append(o)
                objs.append(o)
            elif not o.hide_render:
                objs.append(o)
    return objs, show


def tight(names, out_name, shots, res=720, cols=2, include=None, only=None, cull=False,
          background=(0.20, 0.22, 0.26), margin=1.06):
    """Workbench contact sheet where every tile is framed tightly.
    shots = [(direction | key of DIRS, target (x, y, z) local to the first root or None, width in m or None)].
    With target/width None the tile is fitted to the projected bounds of the rendered objects."""
    import numpy as np
    G.object_mode()
    if isinstance(names, str):
        names = [names]
    scene = bpy.context.scene
    objs, show = _objs(names, include, only)
    oset = set(objs)
    for o in show:
        o.hide_render = False
    bpy.context.view_layer.update()
    root = bpy.data.objects[names[0]]
    pts = []
    for o in objs:
        if o.type == 'MESH':
            pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    r = scene.render
    sh = scene.display.shading
    saved = dict(engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage, path=r.filepath,
                 fmt=r.image_settings.file_format, cam=scene.camera, transparent=r.film_transparent)
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type",
              "background_color", "cavity_type", "show_backface_culling"):
        try:
            v = getattr(sh, k)
            saved_sh[k] = tuple(v) if k == "background_color" else v
        except Exception:
            pass
    hidden = []
    for o in scene.objects:
        if o not in oset and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    cam_data = bpy.data.cameras.new("_crit_cam")
    cam = bpy.data.objects.new("_crit_cam", cam_data)
    scene.collection.objects.link(cam)
    tmp_paths = []
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
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
        cam_data.clip_end = 200.0
        tiles = []
        for i, (d, target, width) in enumerate(shots):
            d = Vector(DIRS[d] if isinstance(d, str) else d).normalized()
            quat = (-d).to_track_quat('-Z', 'Y')
            right = quat @ Vector((1, 0, 0))
            up = quat @ Vector((0, 1, 0))
            if target is None or width is None:
                us = [p.dot(right) for p in pts]
                vs = [p.dot(up) for p in pts]
                ws = [p.dot(d) for p in pts]
                c = right * ((min(us) + max(us)) / 2.0) + up * ((min(vs) + max(vs)) / 2.0) + d * ((min(ws) + max(ws)) / 2.0)
                w = max(max(us) - min(us), max(vs) - min(vs)) * margin
            else:
                c = root.matrix_world @ Vector(target)
                w = width
            cam_data.ortho_scale = w
            cam.location = c + d * 40.0
            cam.rotation_euler = quat.to_euler()
            tmp = os.path.join(G.PREVIEW_DIR, "_tmp_%s_%d.png" % (re.sub(r'[^A-Za-z0-9_]', '_', out_name), i))
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
        sheet = np.zeros((rows * res, cols * res, 4), dtype=np.float32)
        sheet[..., 3] = 1.0
        for i, t in enumerate(tiles):
            rr = rows - 1 - (i // cols)
            cc = i % cols
            sheet[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res, :] = t
        out = bpy.data.images.new("_crit_sheet", cols * res, rows * res, alpha=False)
        out.pixels.foreach_set(sheet.ravel())
        out.filepath_raw = out_path
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
    finally:
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        for o in show:
            try:
                o.hide_render = True
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
    print("PREVIEW_SAVED:", out_path)
    return out_path


def posed(name, out_name, poses, shots, **kw):
    """Render with parts temporarily rotated.  poses = {short part name: (axis 'x'|'y'|'z', radians)}."""
    saved = []
    try:
        for part, (axis, ang) in poses.items():
            o = bpy.data.objects.get(name + ":" + part)
            if o is None:
                print("posed: no part", part)
                continue
            saved.append((o, o.rotation_euler.copy()))
            e = o.rotation_euler.copy()
            setattr(e, axis, getattr(e, axis) + ang)
            o.rotation_euler = e
        bpy.context.view_layer.update()
        return tight(name, out_name, shots, **kw)
    finally:
        for o, e in saved:
            o.rotation_euler = e
        bpy.context.view_layer.update()


def lineup(names, out_name, shots, gap=3.0, **kw):
    """Several roots side by side (temporarily moved, slots restored)."""
    roots = [bpy.data.objects[n] for n in names]
    saved = [r.location.copy() for r in roots]
    try:
        base = saved[0]
        for i, r in enumerate(roots):
            r.location = (base.x + i * gap, base.y, base.z)
        bpy.context.view_layer.update()
        return tight(names, out_name, shots, **kw)
    finally:
        for r, loc in zip(roots, saved):
            r.location = loc
        bpy.context.view_layer.update()


def audit(name):
    """Print a contract audit of one vehicle: parts, tris, origins, materials, markers, bounds."""
    root = bpy.data.objects[name]
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted()
    vis = 0
    total = 0
    rows = []
    for o in sorted(root.children_recursive, key=lambda o: o.name):
        short = o.name.split(":", 1)[-1]
        loc = inv @ o.matrix_world.translation
        if o.type != 'MESH':
            rows.append("  %-18s EMPTY  at (%.3f, %.3f, %.3f) rot=(%.0f, %.0f, %.0f)" % (
                short, loc.x, loc.y, loc.z, *(math.degrees(a) for a in o.rotation_euler)))
            continue
        me = o.data
        me.calc_loop_triangles()
        t = len(me.loop_triangles)
        total += t
        helper = short.startswith(("Mod_", "Col_")) or short == "Body_LOD1"
        if not helper:
            vis += t
        used = sorted({me.materials[p.material_index].name for p in me.polygons if me.materials[p.material_index] is not None})
        co = [inv @ (o.matrix_world @ v.co) for v in me.vertices]
        mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
        mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
        rows.append("  %-18s %5d tris  origin (%.3f, %.3f, %.3f)  bb x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f] hid=%d  %s" % (
            short, t, loc.x, loc.y, loc.z, mn.x, mx.x, mn.y, mx.y, mn.z, mx.z, int(o.hide_render), ",".join(used)))
    print("AUDIT %s: visible tris=%d  whole file=%d" % (name, vis, total))
    for row in rows:
        print(row)
    return vis, total


def flipped(name, parts=None):
    """Rough flipped-face detector for closed-ish parts: count faces whose normal points towards the
    part's own bounding-box centre (only meaningful for convex-ish solids; prints the ratio)."""
    root = bpy.data.objects[name]
    for o in sorted(root.children_recursive, key=lambda o: o.name):
        if o.type != 'MESH':
            continue
        short = o.name.split(":", 1)[-1]
        if parts and short not in parts:
            continue
        me = o.data
        c = sum((Vector(b) for b in o.bound_box), Vector()) / 8.0
        inward = sum(1 for p in me.polygons if (p.center - c).dot(p.normal) < -1e-4)
        print("  %-18s faces=%d inward=%d" % (short, len(me.polygons), inward))
