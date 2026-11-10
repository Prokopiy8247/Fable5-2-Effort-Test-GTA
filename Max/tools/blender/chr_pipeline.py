"""chr_pipeline - one-call (re)build of the humanoid character deliverables.

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import chr_pipeline as P; importlib.reload(P)
    print(P.rebuild_all())             # bodies kept if present; accessories + 51 Actions + both GLBs + manifest
    print(P.rebuild_all(bodies=True))  # also rebuilds rigs / bodies from chr_bodies.SHAPES

Modules: chr_rig (skeleton, rigid skinning) -> chr_bodies (human_male / human_female) -> chr_accessories
(28 accessories per body) -> chr_anims (pose toolkit, Actions) + chr_clips (the 51 clips) -> chr_export
(GLB + contract check) -> gta/resources/data/manifests/characters.json.
"""
import bpy
import io
import os
import json
import importlib
import contextlib
import gta_kit as K
import chr_rig as R
import chr_bodies as B
import chr_accessories as A
import chr_anims as N
import chr_clips as C
import chr_export as X

MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "characters.json")
REGIONS = ["skin", "torso", "upper_arms", "lower_arms", "hands", "pelvis", "upper_legs", "lower_legs", "feet",
           "hair", "eyes", "headwear", "eyewear", "torso_overlay", "detail_a", "detail_b"]


def _reload():
    for m in (R, B, A, N, C, X):
        importlib.reload(m)


def _body_stats(asset_id):
    o = bpy.data.objects[asset_id + "__body"]
    xs = [v.co for v in o.data.vertices]
    lo = [min(c[i] for c in xs) for i in range(3)]
    hi = [max(c[i] for c in xs) for i in range(3)]
    o.data.calc_loop_triangles()
    return [round(hi[i] - lo[i], 3) for i in range(3)], len(o.data.loop_triangles)


def _tris(name):
    o = bpy.data.objects.get(name)
    if o is None:
        return 0
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def manifest(reports=None):
    """Write characters.json from the scene + the registered clips (N.CLIPS must be defined)."""
    reports = reports or {}
    clips = []
    for c in N.clip_list():
        k0 = N.CLIPS[c["name"]]["keys"][0]
        hips = N.REST["Hips"] + N.Vector(k0.get(N.LOC, (0.0, 0.0, 0.0)))
        e = {"name": c["name"], "length": c["length"], "loop": c["loop"],
             "seconds": round(c["length"] / float(N.FPS), 4), "hips": [round(v, 3) for v in hips]}
        if c["name"] in C.SPEED:
            e["speed"] = C.SPEED[c["name"]]
        if c["name"] in C.NOTES:
            e["note"] = C.NOTES[c["name"]]
        clips.append(e)
    assets = []
    for aid in B.CHARACTERS:
        if bpy.data.objects.get(aid) is None:
            continue
        size, tris = _body_stats(aid)
        accs = []
        for name, _fn, bone, regions, _angle in A.ACCESSORIES:
            if bpy.data.objects.get("%s__acc_%s" % (aid, name)) is None:
                continue
            accs.append({"name": name, "part": "acc_" + name, "bone": bone, "regions": regions,
                         "tris": _tris("%s__acc_%s" % (aid, name))})
        rep = reports.get(aid, {})
        male = aid == N.RIG_ASSET
        assets.append({
            "id": aid, "glb": "characters/" + aid, "category": "Characters", "size": size, "tris": tris,
            "tris_with_accessories": tris + sum(a["tris"] for a in accs),
            "parts": ["rig", "body"] + [a["part"] for a in accs], "markers": [],
            "bones": list(R.BONE_NAMES), "accessories": accs,
            "animations": clips if male else [],
            "glb_bytes": rep.get("size"), "glb_joint_rest_identity": rep.get("joint_rest_ok"),
            "notes": ("Rig + body + accessories + the animation library (30 fps, Actions named exactly like the "
                      "clips)." if male else
                      "Same skeleton / head / accessory names as human_male, exported WITHOUT animations (Godot "
                      "shares the human_male library); scale the model to 0.94 in game."),
        })
    data = {
        "_comment": ("NEON TIDE humanoid characters. Positions are Blender asset-space metres (x right, y forward, "
                     "z up); Godot = (x, z, -y). One skinned mesh per part, material 'Character' (UV.x selects the "
                     "colour region 0-15). GLB node names are '<id>__<part>'; accessories ('acc_*') are skinned "
                     "100 % to one bone and must be hidden unless equipped."),
        "fps": N.FPS,
        "skeleton": [{"name": bn, "parent": par, "head": list(head), "deform": dfm} for bn, head, par, dfm in R.BONES],
        "bone_axes": "every joint: identity rest rotation, local X = character right, Y = up, Z = back",
        "regions": {str(i): n for i, n in enumerate(REGIONS)},
        "prop_socket": ("Prop_L / Prop_R are keyed to ONE constant local rotation (-90 deg about X) in every clip: "
                        "socket -Z (Godot forward) points along the fingers / forearm line, +Y (top) to the thumb "
                        "side. Weapons whose origin is the grip and whose barrel / blade runs along Blender +Y "
                        "attach with an identity transform. In the bare rest pose (no clip) the socket is identity."),
        "animation_notes": [
            "All clips are in place; 'hips' is the Hips bone position at frame 0, 'speed' the ground speed in m/s "
            "a gait covers at 1x playback (use it as NOMINAL_SPEED).",
            "Loop clips end on a copy of frame 0. One-shots hold their last frame.",
            "Every clip owns a rotation track for all 19 bones and a Hips position track that differ from the rest "
            "pose (a bone resting for a whole clip is offset by 0.08 deg, a resting Hips by 0.3 mm), so Godot's "
            "'remove_immutable_tracks' import option cannot drop them and an AnimationPlayer never leaves a bone in "
            "the previous clip's pose.",
            "AimPistol / AimRifle / HoldRifle / Reload / Punch_* / Stab / Throw / Block keep the Hips un-rotated "
            "(at frame 0) so Spine..Hand rotations can be layered over locomotion.",
            "Seated clips (SitCar, SitPassenger, SitBike) are built around the Hips bone = the vehicle seat marker; "
            "the pelvis / thigh underside is 0.13 below the Hips bone.",
            "Lying end poses: Death_Back / Knockdown end on the back with the head toward -Y; Death_Front / "
            "TakedownVictim end face-down with the head toward +Y; GetUp starts from the Knockdown end pose.",
        ],
        "export": {"tool": "gta_kit.export_asset(root, 'characters/<id>', animations=True, extra=...)",
                   "extra": X.ANIM_EXTRA, "scene_fps_during_export": X.FPS},
        "assets": assets,
    }
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    return MANIFEST


def export_all():
    """Export both characters and verify the GLBs -> {asset_id: verify report}."""
    names = [c["name"] for c in N.clip_list()]
    out = {}
    for aid in B.CHARACTERS:
        if bpy.data.objects.get(aid) is None:
            continue
        male = aid == N.RIG_ASSET
        path, _size = X.export(aid, animations=male)
        out[aid] = X.verify(path, expect_anims=names if male else [])
        out[aid]["immutable_tracks"] = X.immutable_tracks(path) if male else []
    return out


def rebuild_all(bodies=False, save=True):
    """Everything: (bodies) -> accessories -> Actions -> GLBs -> manifest. -> short text summary."""
    _reload()
    lines = []
    for aid in B.CHARACTERS:
        if bodies or bpy.data.objects.get(aid + "__body") is None:
            lines.append("body %s" % (B.build(aid, rebuild=bodies),))
    acc = A.build_all()
    lines.append("accessories: " + ", ".join("%s %d" % (k, len(v)) for k, v in acc.items()))
    built = N.build_all()
    lines.append("actions: %d" % len(built))
    reps = export_all()
    for aid, rep in reps.items():
        lines.append("%s.glb %d bytes: joints=%d names_ok=%s rest_identity=%s skins=%d skinned_meshes=%d tris=%d "
                     "animations=%d missing=%s extra=%s rest_only_tracks=%d %s" % (
                         aid, rep["size"], len(rep["joints"]), rep["joint_names_ok"], rep["joint_rest_ok"],
                         rep["skins"], len(rep["skinned_nodes"]), rep["tris"], len(rep["animations"]),
                         rep.get("anims_missing"), rep.get("anims_extra"), len(rep.get("immutable_tracks", [])),
                         rep.get("immutable_tracks", [])[:6]))
    lines.append("manifest: " + manifest(reps))
    if save:
        with contextlib.redirect_stdout(io.StringIO()):
            K.save_master()
        lines.append("saved " + bpy.data.filepath)
    return "\n".join(lines)
