"""characters_qa.py - critic's QA renders for the modular humanoid (qa/blender_previews/chr_crit_*.png).

Unlike gta_bl.preview() (auto-framed on the T-pose bounding box, one colour per contract material)
these sheets are framed explicitly (centre + vertical span, so faces / hands / shoes can be judged
close up) and every tile can recolour the contract materials M_* the way the game does, so a look
is judged in its real colours. Nothing is left changed in the file: visibility, pose, material
viewport colours and render settings are restored.

    import characters as C, characters_qa as Q
    Q.sheet("chr_crit_faces", [Q.tile(C.LOOKS["player"], view="front", center=(0, 0, 1.66), span=0.42)])
"""
import bpy
import os
import re
import math
from mathutils import Vector
import gta_bl as G
import characters as C

VIEWS = {
    "front": (0.0, 1.0, 0.06),
    "back": (0.0, -1.0, 0.06),
    "side": (1.0, 0.0, 0.06),
    "left": (-1.0, 0.0, 0.06),
    "three_quarter": (0.75, 1.0, 0.35),
    "tq_left": (-0.75, 1.0, 0.35),
    "rear_quarter": (-0.75, -1.0, 0.35),
    "top": (0.0, -0.001, 1.0),
    "high": (0.5, 1.0, 0.9),
    "low": (0.6, 1.0, -0.15),
}

# colour sets that mirror what CharacterVisual does in the game (sRGB hex)
COLORS = {
    "player": {"M_Skin": "#DDA77B", "M_Hair": "#3A2A1E", "M_Top": "#22A7A0", "M_Top_Accent": "#F5F3EE", "M_Bottom": "#27405F",
               "M_Shoes": "#E9E7E1", "M_Eyes": "#3B2A1E"},
    "civ_m": {"M_Skin": "#B97C54", "M_Hair": "#22201F", "M_Top": "#EE7E64", "M_Top_Accent": "#F5F3EE", "M_Bottom": "#3B404B",
              "M_Shoes": "#4A3426", "M_Eyes": "#2A1C14"},
    "civ_f": {"M_Skin": "#F2C9A5", "M_Hair": "#A6452A", "M_Top": "#E8C24A", "M_Top_Accent": "#F5F3EE", "M_Bottom": "#EFEDE6",
              "M_Shoes": "#C8443A", "M_Eyes": "#3F6F4A"},
    "police": {"M_Skin": "#8A5636", "M_Hair": "#22201F", "M_Shoes": "#1C1E23", "M_Eyes": "#2A1C14"},
    "tactical": {"M_Skin": "#DDA77B", "M_Hair": "#5A3A25", "M_Shoes": "#1C1E23", "M_Eyes": "#2A1C14"},
    "medic": {"M_Skin": "#F2C9A5", "M_Hair": "#5A3A25", "M_Shoes": "#F5F3EE", "M_Eyes": "#3F6FA8"},
    "firefighter": {"M_Skin": "#DDA77B", "M_Hair": "#5A3A25", "M_Shoes": "#1C1E23", "M_Eyes": "#2A1C14"},
    "staff": {"M_Skin": "#F2C9A5", "M_Hair": "#A6452A", "M_Top": "#22262C", "M_Top_Accent": "#22A7A0", "M_Bottom": "#27405F",
              "M_Shoes": "#E9E7E1", "M_Eyes": "#3F6F4A"},
    "gang": {"M_Skin": "#B97C54", "M_Hair": "#22201F", "M_Top": "#3B404B", "M_Top_Accent": "#7A50D0", "M_Bottom": "#27405F",
             "M_Shoes": "#1C1E23", "M_Hat": "#7A50D0", "M_Eyes": "#2A1C14"},
    "suit": {"M_Skin": "#F2C9A5", "M_Hair": "#9A9A98", "M_Top": "#27405F", "M_Top_Accent": "#F5F3EE", "M_Bottom": "#27405F",
             "M_Shoes": "#1C1E23", "M_Eyes": "#3F6FA8"},
    "beach_f": {"M_Skin": "#8A5636", "M_Hair": "#22201F", "M_Top": "#EE7E64", "M_Top_Accent": "#F5F3EE", "M_Bottom": "#22A7A0",
                "M_Shoes": "#F5F3EE", "M_Hat": "#EBD9A8", "M_Eyes": "#2A1C14"},
    "hoodie_m": {"M_Skin": "#5E3A26", "M_Hair": "#22201F", "M_Top": "#7A50D0", "M_Top_Accent": "#F2C331", "M_Bottom": "#BFA77A",
                 "M_Shoes": "#F5F3EE", "M_Hat": "#F0802F", "M_Eyes": "#2A1C14"},
    "office_f": {"M_Skin": "#DDA77B", "M_Hair": "#D9B56A", "M_Top": "#F5F3EE", "M_Top_Accent": "#8FCAE8", "M_Bottom": "#3B404B",
                 "M_Shoes": "#1C1E23", "M_Eyes": "#3F6FA8"},
}


def tile(parts, view="front", center=(0.0, 0.0, 0.93), span=2.0, pose="arms_down", colors=None):
    """One picture: list of part names, view (name or direction toward the eye), framing centre
    (root space, metres), vertical span in metres, pose (name / dict / None) and colour set
    (name in COLORS or a dict material -> '#hex')."""
    return {"parts": list(parts), "view": view, "center": tuple(center), "span": float(span), "pose": pose, "colors": colors}


def sheet(out_name, tiles, res=(300, 520), cols=4, background=(0.42, 0.47, 0.54)):
    """Render the tiles into one PNG in qa/blender_previews. Returns the path."""
    import numpy as np
    G.object_mode()
    scene = bpy.context.scene
    arm = bpy.data.objects[C.ARM]
    root = bpy.data.objects[C.ROOT]
    ours = set(G.children_of(root))
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
    hidden = []
    for o in scene.objects:
        if o not in ours and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    part_state = [(o, o.hide_render) for o in arm.children]
    mat_state = {}
    for name in C.CONTRACT_MATS:
        m = bpy.data.materials.get(name)
        if m is not None:
            mat_state[name] = tuple(m.diffuse_color)
    cam_data = bpy.data.cameras.new("_chr_qa_cam")
    cam = bpy.data.objects.new("_chr_qa_cam", cam_data)
    scene.collection.objects.link(cam)
    rx, ry = res
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    tmp_paths = []
    imgs = []
    try:
        r.engine = 'BLENDER_WORKBENCH'
        for k, v in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                     ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                     ("background_color", background), ("show_backface_culling", True)):
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        r.resolution_x, r.resolution_y, r.resolution_percentage = rx, ry, 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        cam_data.type = 'ORTHO'
        cam_data.clip_start = 0.01
        cam_data.clip_end = 100.0
        os.makedirs(G.PREVIEW_DIR, exist_ok=True)
        for i, t in enumerate(tiles):
            want = set(t["parts"])
            for o in arm.children:
                o.hide_render = o.name not in want
            cols_set = t["colors"]
            if isinstance(cols_set, str):
                cols_set = COLORS[cols_set]
            for name, rgba in mat_state.items():
                m = bpy.data.materials[name]
                if cols_set and name in cols_set:
                    c = G.hexc(cols_set[name])
                    m.diffuse_color = (c[0], c[1], c[2], 1.0)
                else:
                    m.diffuse_color = rgba
            C.set_pose(t["pose"])
            d = t["view"]
            d = Vector(VIEWS[d] if isinstance(d, str) else d).normalized()
            center = root.matrix_world @ Vector(t["center"])
            span = t["span"]
            # ortho_scale spans the LARGER image side
            cam_data.ortho_scale = span if ry >= rx else span * rx / ry
            cam.location = center + d * 10.0
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            tmp = os.path.join(G.PREVIEW_DIR, "_tmp_%s_%d.png" % (re.sub(r'[^A-Za-z0-9_]', '_', out_name), i))
            r.filepath = tmp
            bpy.ops.render.render(write_still=True)
            tmp_paths.append(tmp)
            img = bpy.data.images.load(tmp, check_existing=False)
            arr = np.empty(rx * ry * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            imgs.append(arr.reshape(ry, rx, 4))
            bpy.data.images.remove(img)
        cols = min(cols, len(imgs))
        rows = (len(imgs) + cols - 1) // cols
        sheet_px = np.zeros((rows * ry, cols * rx, 4), dtype=np.float32)
        sheet_px[..., 0:3] = background
        sheet_px[..., 3] = 1.0
        for i, t in enumerate(imgs):
            rr = rows - 1 - (i // cols)
            cc = i % cols
            sheet_px[rr * ry:(rr + 1) * ry, cc * rx:(cc + 1) * rx, :] = t
        out = bpy.data.images.new("_chr_qa_sheet", cols * rx, rows * ry, alpha=False)
        out.pixels.foreach_set(sheet_px.ravel())
        out.filepath_raw = out_path
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
    finally:
        C.set_pose(None)
        for o, h in part_state:
            try:
                o.hide_render = h
            except Exception:
                pass
        for name, rgba in mat_state.items():
            bpy.data.materials[name].diffuse_color = rgba
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
        scene.camera = saved["cam"]
        try:
            r.engine = saved["engine"]
        except Exception:
            pass
        r.resolution_x, r.resolution_y, r.resolution_percentage = saved["rx"], saved["ry"], saved["pct"]
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


# ------------------------------------------------------------------------------------------------
# ready-made critic sheets
# ------------------------------------------------------------------------------------------------
def faces(out_name="chr_crit_faces"):
    """Head close-ups: both heads, every hair style, beards."""
    f = (0, 0.0, 1.665)
    sp = 0.48
    T = []
    for parts, col in ((["Head_M", "Hair_Short", "Top_Tee_M"], "player"), (["Head_M", "Hair_Slick", "Beard_Full", "Top_Tee_M"], "civ_m"),
                       (["Head_M", "Hair_Buzz", "Beard_Goatee", "Top_Tee_M"], "gang"), (["Head_M", "Hair_Curly", "Beard_Mustache", "Top_Tee_M"], "hoodie_m"),
                       (["Head_M", "Hair_Mohawk", "Top_Tee_M"], "gang"), (["Head_M", "Hair_Bun", "Beard_Full", "Top_Tee_M"], "suit"),
                       (["Head_F", "Hair_Long", "Top_Tee_F"], "civ_f"), (["Head_F", "Hair_Ponytail", "Top_Tee_F"], "medic"),
                       (["Head_F", "Hair_Curly", "Top_Tee_F"], "beach_f"), (["Head_F", "Hair_Short", "Top_Tee_F"], "office_f"),
                       (["Head_F", "Hair_Bob", "Top_Tee_F"], "staff"), (["Head_F", "Hair_Bun", "Top_Tee_F"], "beach_f")):
        T.append(tile(parts, "front", f, sp, colors=col))
        T.append(tile(parts, "three_quarter", f, sp, colors=col))
    return sheet(out_name, T, res=(280, 280), cols=6)


def headgear(out_name="chr_crit_headgear"):
    f = (0, 0.0, 1.68)
    sp = 0.50
    T = []
    for hat, hair, gl, col in (("Hat_Cap", "Hair_Short_Hat", None, "player"), ("Hat_Beanie", "Hair_Long_Hat", None, "civ_f"),
                               ("Hat_Brim", "Hair_Curly_Hat", "Glasses_Shades", "beach_f"), ("Hat_Bandana", "Hair_Buzz_Hat", None, "gang"),
                               ("Hat_Police", "Hair_Short_Hat", "Glasses_Shades", "police"), ("Hat_Helmet", None, "Glasses_Goggles", "tactical"),
                               ("Hat_FireHelmet", "Hair_Short_Hat", None, "firefighter"), (None, "Hair_Slick", "Glasses_Round", "suit")):
        head = "Head_F" if col in ("civ_f", "beach_f") else "Head_M"
        parts = [head, "Top_Tee_" + head[-1]] + [x for x in (hat, hair, gl) if x]
        T.append(tile(parts, "three_quarter", f, sp, colors=col))
        T.append(tile(parts, "side", f, sp, colors=col))
    return sheet(out_name, T, res=(300, 300), cols=4)


def lineup(out_name, names, view="front", pose="arms_down", res=(260, 520), cols=5, span=2.0):
    """Full figures in their game colours: names = keys of C.LOOKS (colour set of the same name)."""
    T = [tile(C.LOOKS[n], view, (0, 0, 0.94), span, pose=pose, colors=n if n in COLORS else None) for n in names]
    return sheet(out_name, T, res=res, cols=cols)
