"""veh_parts - vehicle mod parts (SPEC_VEHICLES "P2 - Mod parts"), category VehicleParts, single part `mesh`.

    import veh_parts as VP; importlib.reload(VP); print(VP.build_all())

Authored for a nominal 1.80 m wide car (the game scales X to the car).  Origin where the part touches the car.
Wheels: radius exactly 0.5, width 0.34, axle X, outer face -X, origin centre, rims in tint_a_metal.
Exports vehicles/parts/<id>.glb and writes gta/resources/data/manifests/vehicle_parts.json.
"""
import contextlib
import io
import json
import math
import os

import gta_kit as K
import veh_oth as U
import veh_cars as C

P1 = "@Paint1"
RIM = "tint_a_metal"
MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "vehicle_parts.json")
NOTES = {}


def _wheel(root, style, rim_ratio, cap="chrome", disc="gunmetal"):
    return C.make_wheel(root, "mesh", 0.5, 0.34, style, rim_ratio=rim_ratio, rim_color=RIM, cap_color=cap,
                        segs=16, disc_color=disc)


def rim_steel(root):
    _wheel(root, "steel", 0.62)


def rim_sport5(root):
    _wheel(root, "spoke5", 0.70)


def rim_deep(root):
    _wheel(root, "deep", 0.72, disc="black")


def rim_offroad(root):
    mb = K.MB()
    xo, r, w = -0.17, 0.5, 0.34
    for k in range(18):                                     # chunky tread blocks
        a = 360.0 * k / 18
        off = 0.06 if k % 2 else -0.06
        with mb.at((0, 0, 0), rot=(a, 0, 0)):
            mb.box((0.17, 0.11, 0.04), (off, 0, r - 0.02), "tire")
    U.tube_ring(mb, xo - 0.004, 0.0, 0.0, 0.5 * 0.56 + 0.015, 0.022, RIM, plane="YZ", segs=16, tsegs=4)
    for k in range(12):                                     # beadlock bolts
        a = 2 * math.pi * k / 12
        mb.box((0.02, 0.025, 0.025), (xo - 0.03, math.cos(a) * 0.295, math.sin(a) * 0.295), "steel_dark")
    w0 = C.make_wheel(root, "tmp_w", r - 0.03, w, "steel", rim_ratio=0.56 * 0.5 / 0.47, rim_color=RIM,
                      cap_color="steel_dark", segs=16)
    _merge_into(mb, w0)
    mb.to_object(root, "mesh", weld=True)


def _merge_into(mb, obj):
    """Append an object's mesh to an MB (keeps materials) and delete the object."""
    import bpy
    import bmesh
    tmp = bmesh.new()
    tmp.from_mesh(obj.data)
    uv = tmp.loops.layers.uv.active
    for f in tmp.faces:
        mat = obj.data.materials[f.material_index].name if obj.data.materials else "Palette"
        vs = [mb.bm.verts.new(v.co) for v in f.verts]
        nf = mb.bm.faces.new(vs)
        nf.smooth = f.smooth
        nf.material_index = mb._slot(mat)
        for l0, l1 in zip(f.loops, nf.loops):
            if uv is not None:
                l1[mb.uvl].uv = l0[uv].uv
    tmp.free()
    me = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if me.users == 0:
        bpy.data.meshes.remove(me)


def rim_classic(root):
    mb = K.MB()
    xo = -0.17
    for k in range(16):                                     # whitewall ring on the outer sidewall
        a0, a1 = 2 * math.pi * k / 16, 2 * math.pi * (k + 1) / 16
        U.face(mb, [(xo - 0.003, r * math.cos(a), r * math.sin(a)) for r, a in ((0.36, a0), (0.36, a1), (0.43, a1),
                                                                                (0.43, a0))], "white", toward=(-1, 0, 0))
    w0 = C.make_wheel(root, "tmp_w", 0.5, 0.34, "spoke10", rim_ratio=0.64, rim_color=RIM, cap_color="chrome",
                      segs=16)
    _merge_into(mb, w0)
    mb.to_object(root, "mesh")


# ---------------------------------------------------------------------------- spoilers (origin bottom centre)
def _wing(mb, span, chord, z, y_le, color, t=0.14):
    U.loft(mb, [U.wing_ring(x, y_le, z, chord, t=t, camber=-0.06) for x in (-span / 2, span / 2)], color,
           smooth=True, sharp=50.0, cap_color=color)


def spoiler_lip(root):
    mb = K.MB()
    mb.prism([(0.03, 0.0), (-0.12, 0.0), (-0.15, 0.055), (-0.10, 0.06)], 1.50, P1, plane="YZ")
    for sx in (-1, 1):
        mb.box((0.06, 0.15, 0.03), (sx * 0.74, -0.05, 0.015), P1, taper=(0.4, 1.0))
    mb.to_object(root, "mesh")


def spoiler_wing(root):
    mb = K.MB()
    for sx in (-1, 1):
        mb.box((0.06, 0.16, 0.20), (sx * 0.48, -0.06, 0.0), P1, base=True, taper=(0.8, 0.7), shear=(0, -0.05))
        mb.box((0.02, 0.26, 0.12), (sx * 0.71, -0.12, 0.22), P1)
    _wing(mb, 1.40, 0.26, 0.21, 0.0, P1)
    mb.to_object(root, "mesh")


def spoiler_gt(root):
    mb = K.MB()
    for sx in (-1, 1):
        mb.box((0.03, 0.14, 0.44), (sx * 0.45, -0.10, 0.0), "steel_dark", base=True, shear=(0, -0.10))
        mb.box((0.10, 0.18, 0.02), (sx * 0.45, -0.04, 0.01), "steel_dark")
        mb.box((0.025, 0.44, 0.22), (sx * 0.86, -0.25, 0.47), "plastic_black")
    _wing(mb, 1.70, 0.34, 0.47, -0.08, "plastic_black", t=0.13)
    mb.box((1.70, 0.04, 0.035), (0, -0.40, 0.49), P1, rot=(-25, 0, 0))                 # gurney flap
    mb.to_object(root, "mesh")


# ---------------------------------------------------------------------------- hood / roof (origin bottom centre)
def hood_scoop(root):
    mb = K.MB()
    mb.box((0.62, 0.80, 0.13), (0, -0.05, 0.0), P1, base=True, taper=(0.82, 1.0), bevel=0.02)
    mb.box((0.46, 0.04, 0.085), (0, 0.33, 0.055), "black")
    mb.box((0.02, 0.04, 0.085), (0, 0.345, 0.055), "plastic_black")
    mb.to_object(root, "mesh")


def hood_vents(root):
    mb = K.MB()
    for sx in (-1, 1):
        with mb.at((sx * 0.30, 0.0, 0.0)):
            mb.box((0.36, 0.50, 0.02), (0, 0, 0.0), P1, base=True, bevel=0.006)
            mb.box((0.28, 0.42, 0.012), (0, 0, 0.02), "black", base=True)
            for j in range(5):
                mb.box((0.30, 0.025, 0.03), (0, -0.16 + j * 0.08, 0.02), "plastic_black", base=True,
                       rot=(-25, 0, 0))
    mb.to_object(root, "mesh")


def roof_scoop(root):
    mb = K.MB()
    mb.box((0.50, 0.70, 0.12), (0, 0.0, 0.0), P1, base=True, taper=(0.75, 1.0), bevel=0.02)
    mb.box((0.36, 0.04, 0.08), (0, 0.33, 0.05), "black")
    mb.to_object(root, "mesh")


def roof_rack(root):
    mb = K.MB()
    for sx in (-1, 1):
        mb.box((0.05, 1.40, 0.04), (sx * 0.62, 0.0, 0.07), "plastic_black")
        for y in (-0.60, 0.60):
            mb.box((0.06, 0.08, 0.07), (sx * 0.62, y, 0.0), "plastic_black", base=True)
    for y in (-0.55, 0.0, 0.50):
        mb.box((1.30, 0.04, 0.03), (0, y, 0.105), "steel_dark")
    mb.box((1.10, 0.16, 0.12), (0, 0.66, 0.12), "plastic_black", base=True, bevel=0.01)
    for x in (-0.39, -0.13, 0.13, 0.39):
        mb.cyl(0.05, 0.02, (x, 0.745, 0.18), "chrome", axis="Y", segs=8, cap_color="@LightAux")
    mb.to_object(root, "mesh")


# ---------------------------------------------------------------------------- bumpers / skirt / exhausts
def bumper_splitter(root):
    """Front lip at the bumper's lower edge (origin), sticking out forward (+Y)."""
    mb = K.MB()
    mb.prism([(-0.10, 0.0), (0.12, -0.02), (0.14, 0.0), (-0.10, 0.03)], 1.70, "plastic_black", plane="YZ")
    for sx in (-1, 1):
        mb.box((0.20, 0.10, 0.015), (sx * 0.80, 0.06, 0.12), "plastic_black", rot=(0, sx * -12, 0))
        mb.box((0.012, 0.18, 0.05), (sx * 0.84, 0.02, 0.025), "plastic_black")
    mb.to_object(root, "mesh")


def bumper_bullbar(root):
    mb = K.MB()
    c = "steel_dark"
    for sx in (-1, 1):
        mb.tube([(sx * 0.42, 0.00, 0.02), (sx * 0.42, 0.14, 0.10), (sx * 0.42, 0.16, 0.55), (sx * 0.30, 0.13, 0.68)],
                0.03, c, segs=8)
        mb.box((0.08, 0.06, 0.06), (sx * 0.42, 0.02, 0.05), "plastic_black")
    mb.tube([(-0.30, 0.13, 0.68), (0.30, 0.13, 0.68)], 0.03, c, segs=8)
    mb.tube([(-0.42, 0.16, 0.30), (0.42, 0.16, 0.30)], 0.025, c, segs=8)
    mb.tube([(-0.80, 0.08, 0.18), (-0.42, 0.15, 0.20)], 0.025, c, segs=8)
    mb.tube([(0.42, 0.15, 0.20), (0.80, 0.08, 0.18)], 0.025, c, segs=8)
    mb.box((0.60, 0.03, 0.22), (0, 0.17, 0.40), "plastic_black")
    mb.to_object(root, "mesh")


def bumper_diffuser(root):
    """Rear diffuser at the rear bumper's lower edge (origin), extending backward (-Y)."""
    mb = K.MB()
    mb.box((1.40, 0.30, 0.02), (0, -0.10, 0.0), "plastic_black", base=True, rot=(-8, 0, 0))
    for k in range(5):
        x = -0.56 + k * 0.28
        mb.prism([(0.04, 0.0), (-0.26, 0.0), (-0.26, 0.10)], 0.015, "plastic_black", plane="YZ", pos=(x, 0, 0))
    mb.to_object(root, "mesh")


def skirt_sport(root):
    """LEFT side skirt, 2.6 long; origin = centre of its top inner edge (mounted at mod_skirt_l, mirrored by Godot)."""
    mb = K.MB()
    prof = [(0.02, 0.0), (0.02, -0.09), (-0.05, -0.09), (-0.075, -0.05), (-0.06, 0.0)]
    rings = []
    for y, s in ((-1.30, 0.55), (-1.20, 1.0), (1.20, 1.0), (1.30, 0.55)):
        rings.append([(x * s + (0.02 * (1 - s)), y, z * s) for (x, z) in prof])
    U.loft(mb, rings, lambda i, k: "plastic_black" if k == 1 else P1, smooth=False, cap_color=P1)
    mb.to_object(root, "mesh")


def exhaust_dual(root):
    mb = K.MB()
    for x in (-0.06, 0.06):
        mb.cyl(0.042, 0.16, (x, -0.08, 0), "chrome", axis="Y", segs=10, cap_color="chrome")
        mb.cyl(0.032, 0.012, (x, -0.163, 0), "black", axis="Y", segs=10)
    mb.box((0.20, 0.04, 0.06), (0, -0.01, 0), "steel_dark")
    mb.to_object(root, "mesh")


def exhaust_big(root):
    mb = K.MB()
    mb.cyl(0.07, 0.22, (0, -0.11, 0), "chrome", axis="Y", segs=12, r2=0.05, cap_color="chrome")
    mb.cyl(0.058, 0.012, (0, -0.223, 0), "black", axis="Y", segs=12)
    mb.to_object(root, "mesh")


PARTS = [rim_steel, rim_sport5, rim_deep, rim_offroad, rim_classic, spoiler_lip, spoiler_wing, spoiler_gt,
         hood_scoop, hood_vents, roof_scoop, roof_rack, bumper_splitter, bumper_bullbar, bumper_diffuser,
         skirt_sport, exhaust_dual, exhaust_big]


def build(fn):
    pid = fn.__name__
    root = K.begin_asset(pid, "VehicleParts")
    fn(root)
    return root


def build_all(export=True, save=True):
    entries = []
    out = []
    for fn in PARTS:
        root = build(fn)
        st = K.asset_stats(root)
        pid = root.name
        if export:
            with contextlib.redirect_stdout(io.StringIO()):
                K.export_asset(root, "vehicles/parts/" + pid)
        entries.append({"id": pid, "glb": "vehicles/parts/" + pid, "category": "VehicleParts",
                        "size": [round(v, 3) for v in st["size"]], "tris": st["tris"], "parts": ["mesh"],
                        "markers": [], "notes": (fn.__doc__ or "").strip()})
        out.append((pid, st["tris"], st["size"]))
    if export:
        with open(MANIFEST, "w", encoding="utf-8") as f:
            f.write("{ \"assets\": [\n")
            f.write(",\n".join("  " + json.dumps(a) for a in entries))
            f.write("\n] }\n")
    if save:
        with contextlib.redirect_stdout(io.StringIO()):
            K.save_master()
    return out
