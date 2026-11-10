"""Reproducible GLB export of every GTA_GODOT asset root + manifest.json. Run through Blender MCP.
Set CATS = [...] before exec to limit categories."""
import sys, json, time
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

CATS = globals().get("CATS") or ["vehicles", "characters", "weapons", "buildings", "props", "nature", "animals"]
MAP = {
    "vehicles": ["Vehicles/Cars", "Vehicles/Motorcycles", "Vehicles/Boats", "Vehicles/Helicopters", "Vehicles/Airplanes", "Vehicles/Wheels"],
    "characters": ["Characters"],
    "weapons": ["Weapons"],
    "buildings": ["Buildings"],
    "props": ["StreetProps", "Interiors", "VFX_HelperMeshes"],
    "nature": ["Nature"],
    "animals": ["NPCs/Animals"],
}
manifest_path = os.path.join(EXPORT, "manifest.json")
manifest = {}
if os.path.exists(manifest_path):
    try:
        manifest = json.load(open(manifest_path))
    except Exception:
        manifest = {}


def bounds(root):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    inv = root.matrix_world.inverted()
    for o in hierarchy(root):
        if o.type != 'MESH' or "-colonly" in o.name or "_mod_" in o.name:
            continue
        M = inv @ o.matrix_world
        for v in o.data.vertices:
            p = M @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


t0 = time.time()
count = 0
for cat in CATS:
    for cpath in MAP[cat]:
        c = coll(cpath)
        for ob in list(c.objects):
            if ob.parent is not None:
                continue
            if cpath == "Vehicles/Wheels" and ob.name != "wheels_lib":
                continue
            if ob.name.startswith("kit_"):
                rel = "buildings/kit/%s.glb" % ob.name
            else:
                rel = "%s/%s.glb" % (cat, ob.name)
            bpy.context.view_layer.update()
            lo, hi = bounds(ob)
            export_glb(ob, rel, skins=(cat == "characters"))
            # Godot axes: x = x, y = z(up), z = -y
            manifest[ob.name] = {"path": "res://gta/generated/models/" + rel, "cat": cat,
                                 "min": [round(lo.x, 3), round(lo.z, 3), round(-hi.y, 3)],
                                 "max": [round(hi.x, 3), round(hi.z, 3), round(-lo.y, 3)], "tris": tri_count(ob)}
            count += 1
json.dump(manifest, open(manifest_path, "w"), indent=1, sort_keys=True)
# re-hide optional parts in the working file for a clean viewport
for o in bpy.data.objects:
    if "_mod_" in o.name or (o.name.startswith("char_") and "_att_" in o.name) or (o.name.startswith("w_") and "_att_" in o.name):
        o.hide_set(True)
print("exported", count, "in", round(time.time() - t0, 1), "s; manifest entries", len(manifest))
