"""chr_export - GLB export + contract verification for the NEON TIDE humanoids.

    import chr_export as X; importlib.reload(X)
    X.export("human_male", animations=True)      # -> (path, size, report dict)
    X.export("human_female")                     # mesh + skin only (Godot shares the animation library)

The exporter is run quietly (the glTF add-on prints a lot) and with the scene temporarily at 30 fps so that
clip times are frames / 30 whatever the scene's own frame rate is.  Nothing in the scene is left changed.
"""
import bpy
import io
import os
import json
import math
import struct
import contextlib
import gta_kit as K
import chr_rig as R

FPS = 30
# settings on top of K.export_asset's animation defaults (see export()):
#   export_frame_step 1                 every frame is sampled (short 10-12 f clips keep their snap)
#   export_anim_single_armature False   only the Actions stashed on THIS rig's NLA are written, not every
#                                       armature action in the shared .blend
#   export_anim_slide_to_zero True      all clips start at t = 0
ANIM_EXTRA = dict(export_frame_step=1, export_anim_single_armature=False, export_anim_slide_to_zero=True,
                  export_optimize_animation_keep_anim_object=False)


def glb_json(path):
    with open(path, "rb") as fh:
        magic, version, length = struct.unpack("<III", fh.read(12))
        if magic != 0x46546C67:
            raise RuntimeError("not a GLB: " + path)
        clen, ctype = struct.unpack("<II", fh.read(8))
        if ctype != 0x4E4F534A:
            raise RuntimeError("first chunk is not JSON")
        return json.loads(fh.read(clen).decode("utf-8"))


def _accessor_minmax(js, idx):
    acc = js["accessors"][idx]
    return acc.get("min"), acc.get("max"), acc.get("count")


def verify(path, expect_anims=None, fps=FPS):
    """Parse the GLB JSON chunk -> report dict (joint contract, skins, meshes, animations)."""
    js = glb_json(path)
    nodes = js.get("nodes", [])
    rep = {"path": path, "size": os.path.getsize(path), "nodes": len(nodes), "skins": len(js.get("skins", [])),
           "meshes": len(js.get("meshes", [])), "materials": [m.get("name") for m in js.get("materials", [])]}
    bad = []
    joints = []
    if js.get("skins"):
        sk = js["skins"][0]
        joints = [nodes[j].get("name") for j in sk["joints"]]
        for j in sk["joints"]:
            n = nodes[j]
            r = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
            s = n.get("scale", [1.0, 1.0, 1.0])
            if max(abs(r[0]), abs(r[1]), abs(r[2]), abs(abs(r[3]) - 1.0)) > 1e-5:
                bad.append((n.get("name"), "rot", r))
            if max(abs(s[i] - 1.0) for i in range(3)) > 1e-5:
                bad.append((n.get("name"), "scale", s))
        for i, s in enumerate(js["skins"]):
            if [nodes[j].get("name") for j in s["joints"]] != joints:
                bad.append(("skin%d" % i, "joint list differs", None))
    rep["joints"] = joints
    rep["joint_names_ok"] = sorted(joints) == sorted(R.BONE_NAMES)
    rep["joint_rest_ok"] = not bad
    rep["joint_bad"] = bad
    # non-joint nodes with a rotation / scale (root, rig object, meshes) - should be clean as well
    odd = []
    jset = set(js["skins"][0]["joints"]) if js.get("skins") else set()
    for i, n in enumerate(nodes):
        if i in jset:
            continue
        r = n.get("rotation")
        s = n.get("scale")
        t = n.get("translation")
        if (r and max(abs(r[0]), abs(r[1]), abs(r[2])) > 1e-5) or (s and max(abs(v - 1.0) for v in s) > 1e-5) \
                or (t and max(abs(v) for v in t) > 1e-5):
            odd.append((n.get("name"), t, r, s))
    rep["object_nodes_odd"] = odd
    rep["skinned_nodes"] = sorted(n.get("name") for n in nodes if "skin" in n)
    rep["mesh_nodes"] = sorted(n.get("name") for n in nodes if "mesh" in n)
    tris = 0
    for m in js.get("meshes", []):
        for pr in m.get("primitives", []):
            if "indices" in pr:
                tris += js["accessors"][pr["indices"]]["count"] // 3
    rep["tris"] = tris
    anims = []
    for a in js.get("animations", []):
        tmax = 0.0
        tmin = 1e9
        targets = set()
        for ch in a.get("channels", []):
            smp = a["samplers"][ch["sampler"]]
            lo, hi, _cnt = _accessor_minmax(js, smp["input"])
            if hi:
                tmax = max(tmax, hi[0])
            if lo:
                tmin = min(tmin, lo[0])
            targets.add(nodes[ch["target"]["node"]].get("name"))
        anims.append({"name": a.get("name"), "seconds": round(tmax, 4), "frames": int(round(tmax * fps)),
                      "start": round(tmin if tmin < 1e8 else 0.0, 4), "channels": len(a.get("channels", [])),
                      "bones": len(targets)})
    rep["animations"] = anims
    if expect_anims is not None:
        have = {a["name"] for a in anims}
        rep["anims_missing"] = [n for n in expect_anims if n not in have]
        rep["anims_extra"] = sorted(have - set(expect_anims))
    return rep


def immutable_tracks(path, eps=1e-5):
    """[(animation, bone, 'rotation' | 'translation')] of joint tracks that never leave the rest pose, i.e. the
    ones Godot's `animation/remove_immutable_tracks` import option would drop (a missing track lets the bone keep
    the previous clip's value). Only Hips is checked for translation; must be empty for the shipped library."""
    with open(path, "rb") as fh:
        data = fh.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    base = 20 + jlen + 8
    nodes = js.get("nodes", [])
    if not js.get("skins"):
        return []
    joints = js["skins"][0]["joints"]

    def values(idx):
        acc = js["accessors"][idx]
        bv = js["bufferViews"][acc["bufferView"]]
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
        off = base + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride", 4 * n)
        return [struct.unpack_from("<%df" % n, data, off + k * stride) for k in range(acc["count"])]

    out = []
    for a in js.get("animations", []):
        seen = set()
        for ch in a["channels"]:
            node = ch["target"]["node"]
            kind = ch["target"]["path"]
            if node not in joints or kind not in ("rotation", "translation"):
                continue
            name = nodes[node].get("name")
            seen.add((name, kind))
            if kind == "translation" and name != "Hips":
                continue
            vals = values(a["samplers"][ch["sampler"]]["output"])
            if kind == "rotation":
                rest = nodes[node].get("rotation", [0.0, 0.0, 0.0, 1.0])
                same = all(min(max(abs(v[i] - rest[i]) for i in range(4)),
                               max(abs(v[i] + rest[i]) for i in range(4))) < eps for v in vals)
            else:
                rest = nodes[node].get("translation", [0.0, 0.0, 0.0])
                same = all(max(abs(v[i] - rest[i]) for i in range(3)) < eps for v in vals)
            if same:
                out.append((a.get("name"), name, kind))
        for j in joints:
            name = nodes[j].get("name")
            if (name, "rotation") not in seen:
                out.append((a.get("name"), name, "rotation:missing"))
        if ("Hips", "translation") not in seen:
            out.append((a.get("name"), "Hips", "translation:missing"))
    return out


def export(asset_id, animations=False, extra=None, quiet=True):
    """K.export_asset wrapper: quiet, scene temporarily at 30 fps, rig in rest pose. -> (path, size)."""
    root = bpy.data.objects[asset_id]
    rig = R.get_rig(asset_id)
    for o in list(root.children_recursive):          # QA helpers never ship
        if "__dbg_" in o.name:
            R.remove_part(asset_id, o.name.split("__", 1)[1])
    for name in ("_chr_review",):
        act = bpy.data.actions.get(name)
        if act is not None:
            bpy.data.actions.remove(act)
    scn = bpy.context.scene
    old = (scn.render.fps, scn.render.fps_base, scn.frame_current, scn.frame_start, scn.frame_end)
    prev_action = None
    prev_slot = None
    ad = rig.animation_data if rig is not None else None
    if ad is not None:
        prev_action = ad.action
        try:
            prev_slot = ad.action_slot
        except Exception:
            prev_slot = None
        ad.action = None
    if rig is not None:
        R.reset_pose(rig)
    kw = {}
    if animations:
        kw.update(ANIM_EXTRA)
    if extra:
        kw.update(extra)
    buf = io.StringIO()
    try:
        scn.render.fps = FPS
        scn.render.fps_base = 1.0
        if quiet:
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                out = K.export_asset(root, "characters/" + asset_id, animations=animations, extra=kw or None)
        else:
            out = K.export_asset(root, "characters/" + asset_id, animations=animations, extra=kw or None)
    finally:
        scn.render.fps, scn.render.fps_base = old[0], old[1]
        scn.frame_start, scn.frame_end = old[3], old[4]
        scn.frame_set(old[2])
        if rig is not None:
            if ad is not None:
                ad.action = None
            R.reset_pose(rig)
        if bpy.context.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
        bpy.context.view_layer.update()
    return out


def summary(rep, anims=True):
    """Short printable text of a verify() report."""
    lines = ["%s  %d bytes  nodes=%d skins=%d meshes=%d tris=%d" % (
        os.path.basename(rep["path"]), rep["size"], rep["nodes"], rep["skins"], rep["meshes"], rep["tris"]),
        "joints=%d names_ok=%s rest_identity=%s bad=%s odd_object_nodes=%s" % (
            len(rep["joints"]), rep["joint_names_ok"], rep["joint_rest_ok"], rep["joint_bad"],
            rep["object_nodes_odd"]),
        "skinned: " + ", ".join(rep["skinned_nodes"])]
    if anims:
        lines.append("animations (%d): " % len(rep["animations"]) + ", ".join(
            "%s:%df" % (a["name"], a["frames"]) for a in rep["animations"]))
        if "anims_missing" in rep:
            lines.append("missing=%s extra=%s" % (rep["anims_missing"], rep["anims_extra"]))
    return "\n".join(lines)
