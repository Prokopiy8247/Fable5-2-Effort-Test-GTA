"""Modular building kit + assembled buildings (with -colonly collision helpers). Run through Blender MCP.
Local building frame: footprint centred on origin, ground at z=0, 'front' = -Y (Godot +Z)."""
import sys, random
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

CB = coll("Buildings")
CK = coll("Buildings/Kit")
CC = coll("CollisionHelpers")
mat("M_Col", "#ff00ff", 1.0)
mat("M_ShopFront", "#3d5a6b", 0.2, 0.3)
mat("M_Awning_A", "#d8503c", 0.8)
mat("M_Awning_B", "#2f9c95", 0.8)
mat("M_Awning_C", "#e9a23b", 0.8)
mat("M_Corrugated", "#8fa3ad", 0.6, 0.5)
mat("M_CorrugatedRust", "#a5694a", 0.7, 0.4)
mat("M_CorrugatedTeal", "#4f8f8b", 0.6, 0.4)
mat("M_Door", "#4a3528", 0.7)
mat("M_Cross", "#e8443a", 0.5, 0.0, emit="#e8443a", emit_strength=1.0)
_layout = [0]


def next_loc():
    i = _layout[0]
    _layout[0] += 1
    return (-60 + (i % 8) * 48, 90 + (i // 8) * 60, 0)


def text(mb, s, size, loc, rotz, m, depth=0.06):
    cu = bpy.data.curves.new("tmp_txt", 'FONT')
    cu.body = s
    cu.size = size
    cu.extrude = depth
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new("tmp_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    vs = [(v.co.x, -v.co.z - depth, v.co.y) for v in me.vertices]
    fs = [tuple(p.vertices) for p in me.polygons]
    mb.push(loc, (0, 0, rotz))
    mb.add(vs, fs, m)
    mb.pop()
    bpy.data.meshes.remove(me)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.curves.remove(cu)


# ------------------------------------------------------------------ kit modules (local facade frame: x along, -y outward, z up)
def k_office(mb, xc, z0, bw, h, rng, P):
    g = "M_WindowLit" if rng.random() < 0.6 else "M_WindowDark"
    mb.box((xc, -0.03, z0 + h * 0.5 + 0.05), (bw - 0.45, 0.06, h - 0.75), g)


def k_office_ground(mb, xc, z0, bw, h, rng, P):
    mb.box((xc, -0.03, z0 + h * 0.5 - 0.1), (bw - 0.5, 0.06, h - 0.9), "M_ShopFront")
    mb.box((xc, -0.06, z0 + 0.25), (bw - 0.5, 0.12, 0.5), P["trim"])


def k_apt(mb, xc, z0, bw, h, rng, P, balcony=False):
    g = "M_WindowLit" if rng.random() < 0.5 else "M_WindowDark"
    if balcony:
        mb.box((xc, -0.03, z0 + 1.15), (bw - 1.4, 0.06, 2.1), g)
        mb.box((xc, -0.62, z0 + 0.02), (bw - 0.7, 1.24, 0.14), P["trim"])
        mb.box((xc, -1.21, z0 + 0.60), (bw - 0.7, 0.05, 0.9), P["rail"])
        for sx in (-1, 1):
            mb.box((xc + sx * (bw - 0.7) / 2, -0.62, z0 + 0.60), (0.05, 1.2, 0.9), P["rail"])
    else:
        mb.box((xc, -0.03, z0 + 1.75), (bw - 1.9, 0.06, 1.5), g)
        mb.box((xc, -0.08, z0 + 0.96), (bw - 1.7, 0.16, 0.08), P["trim"])


def k_shop(mb, xc, z0, bw, h, rng, P, awn="M_Awning_A", door=False):
    mb.box((xc, -0.03, z0 + 1.55), (bw - 0.6, 0.06, 2.5), "M_ShopFront")
    mb.box((xc, -0.07, z0 + 0.15), (bw - 0.6, 0.14, 0.3), P["trim"])
    if door:
        mb.box((xc, -0.05, z0 + 1.15), (1.3, 0.08, 2.3), "M_Door")
        mb.box((xc, -0.07, z0 + 1.3), (1.0, 0.08, 1.5), "M_ShopFront")
    mb.box((xc, -0.65, z0 + 3.05), (bw - 0.3, 1.3, 0.10), awn, rot=(-0.22, 0, 0))
    mb.box((xc, -1.28, z0 + 2.82), (bw - 0.3, 0.05, 0.22), awn)


def k_blank(mb, xc, z0, bw, h, rng, P):
    pass


def k_door(mb, xc, z0, bw, h, rng, P):
    mb.box((xc, -0.05, z0 + 1.15), (1.5, 0.10, 2.3), "M_Door")
    mb.box((xc, -0.08, z0 + 2.38), (1.9, 0.16, 0.16), P["trim"])
    mb.box((xc, -0.6, z0 + 0.06), (2.4, 1.2, 0.12), "M_ConcreteDark")


def k_industrial(mb, xc, z0, bw, h, rng, P):
    mb.box((xc, -0.03, z0 + h - 1.0), (bw - 0.8, 0.06, 0.8), "M_WindowDark")
    for i in range(3):
        mb.box((xc - bw / 2 + (i + 0.5) * bw / 3, -0.04, z0 + (h - 1.6) / 2), (0.08, 0.08, h - 1.6), P["trim"])


def k_roller(mb, xc, z0, bw, h, rng, P):
    dh = min(h - 0.6, 4.2)
    mb.box((xc, -0.04, z0 + dh / 2), (bw - 0.8, 0.08, dh), "M_Steel")
    for i in range(int(dh / 0.45)):
        mb.box((xc, -0.09, z0 + 0.3 + i * 0.45), (bw - 0.8, 0.03, 0.04), "M_MetalDark")
    mb.box((xc, -0.10, z0 + dh + 0.1), (bw - 0.5, 0.2, 0.2), P["trim"])


KIT = {"office": k_office, "office_ground": k_office_ground, "apt": k_apt, "shop": k_shop, "door": k_door,
       "industrial": k_industrial, "roller": k_roller}


def build_kit():
    """Stand-alone copies of the kit modules for the Blender library collection."""
    P = dict(trim="M_Concrete", rail="M_MetalDark", wall="M_Stucco")
    rng = random.Random(1)
    for i, (kn, fn) in enumerate(KIT.items()):
        name = "kit_" + kn
        wipe(name)
        mb = MB()
        mb.box((0, 0.15, 1.7), (4.0, 0.3, 3.4), P["wall"])
        fn(mb, 0, 0, 4.0, 3.4, rng, P)
        mb.build(name, CK, loc=(-60 + i * 5, 70, 0))


# ------------------------------------------------------------------ generic assembler
def facade_sides(w, d):
    return [((0, -d / 2, 0), 0.0, w), ((w / 2, 0, 0), math.pi / 2, d), ((0, d / 2, 0), math.pi, w), ((-w / 2, 0, 0), 3 * math.pi / 2, d)]


def finish(name, mb, col, loc=None):
    wipe(name)
    ob = mb.build(name, CB, loc=loc or next_loc())
    c = col.build(name + "_col-colonly", CC, loc=(0, 0, 0), parent=ob)
    c.display_type = 'WIRE'
    c.hide_render = True
    return ob


def roof_clutter(mb, w, d, H, rng, n=4, tank=False, antenna=False):
    for i in range(n):
        x = rng.uniform(-w / 2 + 3, w / 2 - 3)
        y = rng.uniform(-d / 2 + 3, d / 2 - 3)
        mb.box((x, y, H + 0.6), (2.0, 1.6, 1.2), "M_Metal")
        mb.cyl((x, y, H + 1.25), 0.6, 0.1, "M_MetalDark", seg=8)
    mb.box((w / 4, d / 4, H + 1.4), (3.5, 3.0, 2.8), "M_ConcreteDark")
    mb.box((w / 4, d / 4 - 1.52, H + 1.1), (1.0, 0.06, 2.0), "M_Door")
    if tank:
        mb.cyl((-w / 4, -d / 4, H + 2.8), 1.6, 2.6, "M_Wood", seg=10)
        mb.cyl((-w / 4, -d / 4, H + 4.4), 1.7, 0.7, "M_Roof", seg=10, r2=0.1)
        for a in range(4):
            mb.box((-w / 4 + math.cos(a * 1.57 + 0.78) * 1.2, -d / 4 + math.sin(a * 1.57 + 0.78) * 1.2, H + 0.75), (0.15, 0.15, 1.5), "M_MetalDark")
    if antenna:
        mb.limb((0, 0, H), (0, 0, H + 14), 0.25, 0.05, "M_Metal", seg=5)
        mb.box((0, 0, H + 9), (1.8, 0.08, 0.08), "M_Metal")
        mb.box((0, 0, H + 14), (0.2, 0.2, 0.2), "M_Siren_R")


def tower(name, w, d, floors, style, wall, trim, ground="office_ground", gh=4.4, fh=3.4, bay=4.0, seed=1, crown=False,
          sign=None, sign_mat="M_Neon_B", tank=False, antenna=False, rail="M_MetalDark", awn=None):
    rng = random.Random(seed)
    P = dict(wall=wall, trim=trim, rail=rail)
    H = gh + (floors - 1) * fh
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), wall)
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    for (o, rz, L) in facade_sides(w, d):
        n = max(1, round(L / bay))
        bw = L / n
        mb.push(o, (0, 0, rz))
        for f in range(floors):
            z0 = 0 if f == 0 else gh + (f - 1) * fh
            h = gh if f == 0 else fh
            for b in range(n):
                xc = -L / 2 + (b + 0.5) * bw
                if f == 0:
                    if ground == "shop":
                        k_shop(mb, xc, z0, bw, h, rng, P, awn=awn or rng.choice(["M_Awning_A", "M_Awning_B", "M_Awning_C"]), door=(b % 2 == 0))
                    elif ground == "door" or (b == n // 2 and rz == 0.0):
                        k_door(mb, xc, z0, bw, h, rng, P)
                    elif ground == "office_ground":
                        k_office_ground(mb, xc, z0, bw, h, rng, P)
                    elif ground == "apt":
                        k_apt(mb, xc, z0, bw, h, rng, P)
                elif style == "office":
                    k_office(mb, xc, z0, bw, h, rng, P)
                else:
                    k_apt(mb, xc, z0, bw, h, rng, P, balcony=((b + f) % 2 == 0 and n > 2))
            if style == "office" or f == 0:
                mb.box((0, -0.07, z0 + h - 0.12), (L + 0.14, 0.14, 0.3), trim)
        if style == "office":
            for b in range(n + 1):
                mb.box((-L / 2 + b * bw, -0.09, H / 2), (0.34, 0.18, H), trim)
        mb.pop()
    # parapet + roof
    for (o, rz, L) in facade_sides(w, d):
        mb.push(o, (0, 0, rz))
        mb.box((0, 0.15, H + 0.4), (L, 0.3, 0.8), trim)
        mb.pop()
    mb.box((0, 0, H + 0.05), (w - 0.6, d - 0.6, 0.1), "M_ConcreteDark")
    col.box((0, 0, H + 0.05), (w, d, 0.3), "M_Col")
    roof_clutter(mb, w, d, H, rng, n=max(1, int(w * d / 300)), tank=tank, antenna=antenna)
    if crown:
        mb.box((0, 0, H + 3.0), (w * 0.6, d * 0.6, 6.0), wall)
        mb.box((0, 0, H + 6.3), (w * 0.64, d * 0.64, 0.6), trim)
        for (o, rz, L) in facade_sides(w * 0.6, d * 0.6):
            mb.push(o, (0, 0, rz))
            mb.box((0, -0.04, H + 3.0), (L - 1.5, 0.08, 4.0), "M_WindowLit")
            mb.pop()
        col.box((0, 0, H + 3.3), (w * 0.6, d * 0.6, 6.6), "M_Col")
    if sign:
        text(mb, sign, 1.8, (0, -d / 2 - 0.2, gh + 0.9), 0, sign_mat, 0.12)
    return finish(name, mb, col)


def shop_row(name, w, d, units, floors=1, wall="M_Stucco", trim="M_White", signs=None, seed=1):
    rng = random.Random(seed)
    P = dict(wall=wall, trim=trim, rail="M_MetalDark")
    gh, fh = 4.4, 3.4
    H = gh + (floors - 1) * fh
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), wall)
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    uw = w / units
    awns = ["M_Awning_A", "M_Awning_B", "M_Awning_C"]
    neons = ["M_Neon_A", "M_Neon_B", "M_Neon_C"]
    for u in range(units):
        xc0 = -w / 2 + (u + 0.5) * uw
        nb = max(1, round(uw / 4.5))
        bw = uw / nb
        a = awns[(u + seed) % 3]
        mb.push((0, -d / 2, 0))
        for b in range(nb):
            xc = xc0 - uw / 2 + (b + 0.5) * bw
            k_shop(mb, xc, 0, bw, gh, rng, P, awn=a, door=(b == nb // 2))
        mb.box((xc0, -0.12, gh - 0.45), (uw - 0.6, 0.24, 0.8), "M_DarkGrey")
        mb.box((xc0 - uw / 2, -0.10, H / 2), (0.4, 0.2, H), trim)
        mb.pop()
        if signs and u < len(signs) and signs[u]:
            text(mb, signs[u], min(0.62, (uw - 1.2) / max(len(signs[u]), 1) * 1.5), (xc0, -d / 2 - 0.26, gh - 0.45), 0, neons[(u + seed) % 3], 0.06)
    mb.push((0, -d / 2, 0))
    mb.box((w / 2, -0.10, H / 2), (0.4, 0.2, H), trim)
    mb.pop()
    for (o, rz, L) in facade_sides(w, d):
        mb.push(o, (0, 0, rz))
        mb.box((0, 0.15, H + 0.35), (L, 0.3, 0.7), trim)
        if floors > 1:
            n = max(1, round(L / 4.0))
            for b in range(n):
                k_apt(mb, -L / 2 + (b + 0.5) * L / n, gh, L / n, fh, rng, P)
        elif rz != 0.0:
            pass
        mb.pop()
    mb.push((0, d / 2, 0), (0, 0, math.pi))
    mb.box((w / 4, -0.05, 1.1), (1.2, 0.1, 2.2), "M_Door")
    mb.pop()
    mb.box((0, 0, H + 0.05), (w - 0.6, d - 0.6, 0.1), "M_ConcreteDark")
    col.box((0, 0, H + 0.05), (w, d, 0.3), "M_Col")
    roof_clutter(mb, w, d, H, rng, n=1)
    return finish(name, mb, col)


def house(name, w, d, floors, wall, roof, seed=1, garage=True, trim="M_White"):
    rng = random.Random(seed)
    fh = 3.0
    H = floors * fh
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), wall)
    mb.box((0, 0, 0.15), (w + 0.2, d + 0.2, 0.3), "M_ConcreteDark")
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    # gable roof along X
    rh = 2.6
    ov = 0.5
    mb.prism([(-d / 2 - ov, H), (d / 2 + ov, H), (0, H + rh)], w + ov * 2, roof, plane='YZ', cap_m=wall)
    col.prism([(-d / 2 - ov, H), (d / 2 + ov, H), (0, H + rh)], w + ov * 2, "M_Col", plane='YZ')
    mb.box((w / 4, d / 5, H + rh * 0.75), (0.8, 0.8, 2.2), "M_Brick")
    # front (-Y)
    mb.push((0, -d / 2, 0))
    dx = -w / 6
    mb.box((dx, -0.05, 1.25), (1.1, 0.10, 2.2), "M_Door")
    mb.box((dx, -0.08, 2.42), (1.5, 0.16, 0.14), trim)
    mb.box((dx, -1.0, 0.2), (3.0, 2.0, 0.4), "M_ConcreteDark")
    mb.box((dx, -1.1, 2.85), (3.4, 2.2, 0.14), roof)
    for sx in (-1, 1):
        mb.box((dx + sx * 1.4, -1.9, 1.6), (0.16, 0.16, 2.5), trim)
    for f in range(floors):
        for wx in ([w / 4] if f == 0 else [-w / 4, w / 4]):
            g = "M_WindowLit" if rng.random() < 0.6 else "M_WindowDark"
            mb.box((wx, -0.03, f * fh + 1.7), (1.8, 0.06, 1.3), g)
            mb.box((wx, -0.07, f * fh + 1.0), (2.1, 0.14, 0.1), trim)
            for sx in (-1, 1):
                mb.box((wx + sx * 1.12, -0.05, f * fh + 1.7), (0.34, 0.06, 1.3), roof)
    mb.pop()
    for (o, rz, L) in facade_sides(w, d)[1:]:
        mb.push(o, (0, 0, rz))
        for f in range(floors):
            g = "M_WindowLit" if rng.random() < 0.5 else "M_WindowDark"
            mb.box((0, -0.03, f * fh + 1.7), (1.6, 0.06, 1.2), g)
            mb.box((0, -0.07, f * fh + 1.05), (1.9, 0.14, 0.1), trim)
        mb.pop()
    if garage:
        gx = w / 2 + 2.6
        mb.box((gx, 0.5, 1.5), (5.2, d - 1.0, 3.0), wall)
        mb.box((gx, 0.5, 3.1), (5.6, d - 0.6, 0.25), roof)
        mb.box((gx, -d / 2 + 0.96, 1.25), (4.0, 0.08, 2.5), trim)
        for i in range(4):
            mb.box((gx, -d / 2 + 0.92, 0.5 + i * 0.6), (4.0, 0.03, 0.04), "M_Grey")
        col.box((gx, 0.5, 1.6), (5.2, d - 1.0, 3.2), "M_Col")
    return finish(name, mb, col)


def warehouse(name, w, d, h, wall, roofm="M_RoofSlate", seed=1, doors=2, stacks=0, sign=None):
    rng = random.Random(seed)
    P = dict(wall=wall, trim="M_MetalDark", rail="M_MetalDark")
    mb = MB()
    col = MB()
    mb.box((0, 0, h / 2), (w, d, h), wall)
    mb.box((0, 0, 0.5), (w + 0.2, d + 0.2, 1.0), "M_ConcreteDark")
    col.box((0, 0, h / 2), (w, d, h), "M_Col")
    mb.prism([(-d / 2 - 0.4, h), (d / 2 + 0.4, h), (0, h + d * 0.16)], w + 0.6, roofm, plane='YZ', cap_m=wall)
    col.prism([(-d / 2 - 0.4, h), (d / 2 + 0.4, h), (0, h + d * 0.16)], w + 0.6, "M_Col", plane='YZ')
    for (o, rz, L) in facade_sides(w, d):
        n = max(1, round(L / 6.0))
        bw = L / n
        mb.push(o, (0, 0, rz))
        for b in range(n):
            xc = -L / 2 + (b + 0.5) * bw
            if rz == 0.0 and b < doors:
                k_roller(mb, xc, 0, bw, h, rng, P)
            else:
                k_industrial(mb, xc, 0, bw, h, rng, P)
            mb.box((-L / 2 + b * bw, -0.06, h / 2), (0.25, 0.12, h), "M_MetalDark")
        mb.box((L / 2, -0.06, h / 2), (0.25, 0.12, h), "M_MetalDark")
        mb.pop()
    mb.push((0, -d / 2, 0))
    mb.box((w / 2 - 2.5, -0.05, 1.1), (1.2, 0.1, 2.2), "M_Door")
    mb.pop()
    for i in range(stacks):
        x = -w / 2 + 4 + i * 5
        mb.cyl((x, d / 4, h + 5), 1.1, 12, "M_Brick", seg=10, r2=0.8)
        mb.cyl((x, d / 4, h + 11.2), 0.95, 0.5, "M_ConcreteDark", seg=10)
        col.box((x, d / 4, h + 5), (2.0, 2.0, 12), "M_Col")
    for i in range(3):
        mb.cyl((-w / 3 + i * w / 3, 0, h + d * 0.16 + 0.3), 0.7, 0.8, "M_Metal", seg=8)
    if sign:
        text(mb, sign, 1.6, (0, -d / 2 - 0.15, h - 1.6), 0, "M_White", 0.08)
    return finish(name, mb, col)


def room_shell(mb, col, w, d, h, wall, floor_m, t=0.4, door_w=2.0, door_h=2.6, door_x=0.0, inner=None, roof_m="M_ConcreteDark"):
    """Hollow single room with a doorway on the front (-Y)."""
    inner = inner or wall
    mb.box((0, 0, 0.1), (w, d, 0.2), floor_m)
    col.box((0, 0, 0.1), (w, d, 0.2), "M_Col")
    parts = [((0, d / 2 - t / 2, h / 2), (w, t, h)), ((-w / 2 + t / 2, 0, h / 2), (t, d - 2 * t, h)), ((w / 2 - t / 2, 0, h / 2), (t, d - 2 * t, h))]
    lw = (w / 2 + door_x - door_w / 2)
    rw = (w / 2 - door_x - door_w / 2)
    parts.append(((-w / 2 + lw / 2, -d / 2 + t / 2, h / 2), (lw, t, h)))
    parts.append(((w / 2 - rw / 2, -d / 2 + t / 2, h / 2), (rw, t, h)))
    parts.append(((door_x, -d / 2 + t / 2, door_h + (h - door_h) / 2), (door_w, t, h - door_h)))
    for c, s in parts:
        mb.box(c, s, wall)
        col.box(c, s, "M_Col")
    mb.box((0, 0, h + 0.15), (w + 0.3, d + 0.3, 0.3), roof_m)
    col.box((0, 0, h + 0.15), (w + 0.3, d + 0.3, 0.3), "M_Col")
    mb.box((0, 0, h - 0.02), (w - 2 * t, d - 2 * t, 0.04), inner)


def gunshop(name):
    w, d, h = 16.0, 13.0, 4.4
    mb = MB()
    col = MB()
    room_shell(mb, col, w, d, h, "M_BrickDark", "M_ConcreteDark", door_w=2.4, door_h=2.8, inner="M_Cream")
    mb.box((0, -d / 2 - 0.1, h + 0.9), (w + 0.3, 0.3, 1.5), "M_DarkGrey")
    text(mb, "BRASS & BOLT", 1.0, (0, -d / 2 - 0.26, h + 0.95), 0, "M_Neon_C", 0.08)
    text(mb, "ARMS", 0.5, (0, -d / 2 - 0.26, h + 0.3), 0, "M_White", 0.05)
    for sx in (-1, 1):
        mb.box((sx * 4.6, -d / 2 - 0.03, 1.9), (4.4, 0.06, 2.2), "M_ShopFront")
        for i in range(5):
            mb.box((sx * 4.6 - 1.8 + i * 0.9, -d / 2 - 0.08, 1.9), (0.06, 0.06, 2.2), "M_MetalDark")
    # counter + shelves + racks
    mb.box((0, 3.0, 0.75), (9.0, 0.9, 1.1), "M_WoodDark")
    mb.box((0, 3.0, 1.33), (9.2, 1.1, 0.06), "M_Wood")
    col.box((0, 3.0, 0.75), (9.0, 0.9, 1.3), "M_Col")
    mb.box((0, d / 2 - 0.55, 2.0), (12.0, 0.3, 2.6), "M_WoodDark")
    for i in range(9):
        x = -5.2 + i * 1.3
        mb.box((x, d / 2 - 0.75, 2.0 + (i % 3) * 0.5), (1.0, 0.08, 0.10), "M_Gun")
        mb.box((x - 0.3, d / 2 - 0.75, 1.9 + (i % 3) * 0.5), (0.10, 0.08, 0.26), "M_Grip")
    for sx in (-1, 1):
        mb.box((sx * (w / 2 - 0.75), 0.5, 1.2), (0.6, 6.0, 2.0), "M_MetalDark")
        col.box((sx * (w / 2 - 0.75), 0.5, 1.2), (0.6, 6.0, 2.0), "M_Col")
        for i in range(8):
            mb.box((sx * (w / 2 - 1.08), -2.1 + i * 0.75, 1.0 + (i % 2) * 0.8), (0.1, 0.5, 0.3), "M_Olive")
    for x in (-4, 0, 4):
        mb.box((x, 0, h - 0.1), (1.6, 0.4, 0.08), "M_LampGlow")
    ob = finish(name, mb, col)
    empty(name + "_counter", CB, loc=(0, 1.6, 0.2), parent=ob)
    empty(name + "_clerk", CB, loc=(0, 4.2, 0.2), parent=ob)
    return ob


def modgarage(name):
    w, d, h = 18.0, 18.0, 6.0
    mb = MB()
    col = MB()
    room_shell(mb, col, w, d, h, "M_CorrugatedTeal", "M_ConcreteDark", door_w=7.0, door_h=4.6, inner="M_Grey", roof_m="M_RoofSlate")
    mb.box((0, -d / 2 - 0.12, h + 1.1), (w + 0.3, 0.3, 2.0), "M_DarkGrey")
    text(mb, "TORQUE HOUSE", 1.25, (0, -d / 2 - 0.3, h + 1.2), 0, "M_Neon_A", 0.1)
    text(mb, "CUSTOM  +  REPAIR", 0.5, (0, -d / 2 - 0.3, h + 0.35), 0, "M_White", 0.05)
    for sx in (-1, 1):
        mb.box((sx * 3.7, -d / 2 - 0.1, 2.3), (0.4, 0.3, 4.6), "M_Yellow")
    mb.box((0, -d / 2 - 0.1, 4.75), (7.8, 0.3, 0.3), "M_Yellow")
    # lift pad, tool walls, tyre stacks
    mb.box((0, 1.0, 0.24), (3.2, 6.0, 0.08), "M_Yellow")
    mb.box((0, 1.0, 0.26), (2.6, 5.4, 0.08), "M_MetalDark")
    for sx in (-1, 1):
        mb.box((sx * (w / 2 - 0.9), 2.0, 1.0), (0.9, 8.0, 1.0), "M_Red")
        mb.box((sx * (w / 2 - 0.9), 2.0, 1.53), (1.0, 8.2, 0.06), "M_Steel")
        mb.box((sx * (w / 2 - 0.5), 2.0, 3.0), (0.1, 7.0, 1.8), "M_WoodDark")
        col.box((sx * (w / 2 - 0.9), 2.0, 1.0), (0.9, 8.0, 1.6), "M_Col")
        for i in range(6):
            mb.box((sx * (w / 2 - 0.6), -0.8 + i * 1.1, 3.0 + (i % 2) * 0.3), (0.06, 0.12, 0.7), "M_Steel")
    for i in range(4):
        mb.cyl((-w / 2 + 1.4, -d / 2 + 1.6 + (i // 2) * 0.1, 0.33 + i * 0.26), 0.36, 0.24, "M_Tire", seg=10)
        mb.cyl((w / 2 - 1.4, -d / 2 + 1.6, 0.33 + i * 0.26), 0.36, 0.24, "M_Tire", seg=10)
    mb.box((0, d / 2 - 0.9, 1.2), (6.0, 0.8, 2.0), "M_Red")
    col.box((0, d / 2 - 0.9, 1.2), (6.0, 0.8, 2.0), "M_Col")
    for x in (-5, 0, 5):
        mb.box((x, 0, h - 0.12), (0.4, 8.0, 0.08), "M_LampGlow")
    ob = finish(name, mb, col)
    empty(name + "_bay", CB, loc=(0, 1.0, 0.3), parent=ob)
    return ob


def safehouse(name):
    w, d, h = 13.0, 11.0, 3.4
    mb = MB()
    col = MB()
    room_shell(mb, col, w, d, h, "M_StuccoBlue", "M_Wood", t=0.35, door_w=1.6, door_h=2.5, door_x=-2.5, inner="M_Cream", roof_m="M_Cream")
    # second floor (solid) + roof
    mb.box((0, 0, h + 0.3 + 1.5), (w, d, 3.0), "M_StuccoBlue")
    col.box((0, 0, h + 0.3 + 1.5), (w, d, 3.0), "M_Col")
    H2 = h + 3.3
    mb.prism([(-d / 2 - 0.5, H2), (d / 2 + 0.5, H2), (0, H2 + 2.6)], w + 1.0, "M_RoofRed", plane='YZ', cap_m="M_StuccoBlue")
    col.prism([(-d / 2 - 0.5, H2), (d / 2 + 0.5, H2), (0, H2 + 2.6)], w + 1.0, "M_Col", plane='YZ')
    for wx in (-3.5, 3.5):
        mb.box((wx, -d / 2 - 0.03, h + 1.9), (2.2, 0.06, 1.4), "M_WindowLit")
        mb.box((wx, -d / 2 - 0.07, h + 1.15), (2.5, 0.14, 0.1), "M_White")
    mb.box((3.0, -d / 2 - 0.03, 1.8), (3.6, 0.06, 1.5), "M_ShopFront")
    mb.box((-2.5, -d / 2 - 1.0, 0.1), (3.2, 2.0, 0.2), "M_ConcreteDark")
    mb.box((-2.5, -d / 2 - 1.1, 2.9), (3.6, 2.2, 0.14), "M_RoofRed")
    for sx in (-1, 1):
        mb.box((-2.5 + sx * 1.5, -d / 2 - 1.9, 1.5), (0.16, 0.16, 2.8), "M_White")
    # interior furniture: bed, wardrobe, desk + laptop, sofa, rug, lamp
    mb.box((4.3, 3.2, 0.45), (2.2, 3.2, 0.5), "M_WoodDark")
    mb.box((4.3, 3.0, 0.78), (2.0, 2.6, 0.2), "M_Navy")
    mb.box((4.3, 4.3, 0.92), (1.6, 0.6, 0.16), "M_White")
    col.box((4.3, 3.2, 0.5), (2.2, 3.2, 0.8), "M_Col")
    mb.box((-5.3, 3.6, 1.3), (1.2, 2.4, 2.4), "M_WoodDark")
    mb.box((-4.68, 3.6, 1.3), (0.04, 0.06, 2.2), "M_Wood")
    col.box((-5.3, 3.6, 1.3), (1.2, 2.4, 2.4), "M_Col")
    mb.box((0.0, 4.5, 0.85), (2.4, 1.0, 0.1), "M_Wood")
    for sx in (-1, 1):
        mb.box((sx * 1.1, 4.5, 0.5), (0.1, 0.9, 0.7), "M_WoodDark")
    mb.box((0.0, 4.6, 1.08), (0.6, 0.04, 0.4), "M_Black")
    mb.box((0.0, 4.4, 0.92), (0.6, 0.4, 0.03), "M_Grey")
    mb.box((0.0, 4.585, 1.08), (0.52, 0.02, 0.32), "M_Neon_B")
    col.box((0.0, 4.5, 0.6), (2.4, 1.0, 1.0), "M_Col")
    mb.box((-1.5, -1.0, 0.5), (3.0, 1.2, 0.6), "M_Teal")
    mb.box((-1.5, -0.45, 0.95), (3.0, 0.3, 0.7), "M_Teal")
    col.box((-1.5, -0.9, 0.6), (3.0, 1.3, 1.0), "M_Col")
    mb.box((-1.5, -2.8, 0.215), (3.4, 2.2, 0.03), "M_Terracotta")
    mb.box((0, 0, h - 0.1), (1.0, 1.0, 0.08), "M_LampGlow")
    # garage
    gx = w / 2 + 3.2
    mb.box((gx, 0.5, 1.7), (6.4, d - 1.0, 3.4), "M_StuccoBlue")
    mb.box((gx, 0.5, 3.5), (6.8, d - 0.6, 0.25), "M_RoofRed")
    mb.box((gx, -d / 2 + 0.96, 1.4), (5.0, 0.08, 2.8), "M_White")
    for i in range(5):
        mb.box((gx, -d / 2 + 0.92, 0.5 + i * 0.55), (5.0, 0.03, 0.04), "M_Grey")
    col.box((gx, 0.5, 1.8), (6.4, d - 1.0, 3.6), "M_Col")
    ob = finish(name, mb, col)
    empty(name + "_bed", CB, loc=(3.0, 3.0, 0.2), parent=ob)
    empty(name + "_wardrobe", CB, loc=(-4.2, 3.6, 0.2), parent=ob)
    empty(name + "_laptop", CB, loc=(0.0, 3.6, 0.2), parent=ob)
    empty(name + "_garage", CB, loc=(gx, -d / 2 - 4.5, 0.0), parent=ob)
    empty(name + "_spawn", CB, loc=(-2.5, -3.7, 0.25), parent=ob)
    return ob


def police_station(name):
    w, d = 30.0, 20.0
    ob = None
    rng = random.Random(7)
    P = dict(wall="M_White", trim="M_Navy", rail="M_MetalDark")
    H = 8.6
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), "M_White")
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    mb.box((0, 0, 0.6), (w + 0.3, d + 0.3, 1.2), "M_Navy")
    for (o, rz, L) in facade_sides(w, d):
        n = round(L / 4.0)
        bw = L / n
        mb.push(o, (0, 0, rz))
        for f in range(2):
            for b in range(n):
                if rz == 0.0 and f == 0 and b in (n // 2 - 1, n // 2):
                    continue
                k_office(mb, -L / 2 + (b + 0.5) * bw, f * 4.2 + 0.4, bw, 3.6, rng, P)
        mb.box((0, -0.08, 4.3), (L + 0.2, 0.16, 0.5), "M_Navy")
        mb.box((0, 0.15, H + 0.4), (L, 0.3, 0.8), "M_Navy")
        mb.pop()
    mb.push((0, -d / 2, 0))
    mb.box((0, -1.6, 0.25), (9.0, 3.2, 0.5), "M_Concrete")
    mb.box((0, -1.6, 4.6), (9.4, 3.4, 0.4), "M_Navy")
    for sx in (-1, 1):
        mb.box((sx * 4.0, -2.9, 2.4), (0.5, 0.5, 4.2), "M_White")
    mb.box((0, -0.05, 1.75), (3.0, 0.1, 2.5), "M_ShopFront")
    mb.pop()
    col.box((0, -d / 2 - 1.6, 0.25), (9.0, 3.2, 0.5), "M_Col")
    text(mb, "POLICE", 1.5, (0, -d / 2 - 3.32, 4.6), 0, "M_White", 0.1)
    text(mb, "MARLOW BAY PD", 0.6, (0, -d / 2 - 0.2, 6.4), 0, "M_Navy", 0.06)
    mb.box((0, 0, H + 0.05), (w - 0.6, d - 0.6, 0.1), "M_ConcreteDark")
    col.box((0, 0, H + 0.05), (w, d, 0.3), "M_Col")
    roof_clutter(mb, w, d, H, rng, n=2, antenna=True)
    mb.limb((-w / 2 + 2, -d / 2 - 2, 0), (-w / 2 + 2, -d / 2 - 2, 9), 0.08, 0.05, "M_Steel", seg=5)
    mb.box((-w / 2 + 2.9, -d / 2 - 2, 8.3), (1.8, 0.04, 1.1), "M_Navy")
    ob = finish(name, mb, col)
    empty(name + "_door", CB, loc=(0, -d / 2 - 4.5, 0.0), parent=ob)
    return ob


def hospital(name):
    w, d, floors = 36.0, 24.0, 6
    rng = random.Random(11)
    P = dict(wall="M_White", trim="M_Teal", rail="M_MetalDark")
    gh, fh = 4.6, 3.6
    H = gh + (floors - 1) * fh
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), "M_White")
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    for (o, rz, L) in facade_sides(w, d):
        n = round(L / 4.0)
        bw = L / n
        mb.push(o, (0, 0, rz))
        for f in range(floors):
            z0 = 0 if f == 0 else gh + (f - 1) * fh
            for b in range(n):
                if rz == 0.0 and f == 0 and abs(b - (n - 1) / 2) < 1.6:
                    continue
                k_office(mb, -L / 2 + (b + 0.5) * bw, z0, bw, fh, rng, P)
            mb.box((0, -0.07, z0 + (gh if f == 0 else fh) - 0.15), (L + 0.14, 0.14, 0.35), "M_Teal")
        mb.box((0, 0.15, H + 0.4), (L, 0.3, 0.8), "M_White")
        mb.pop()
    mb.push((0, -d / 2, 0))
    mb.box((0, -3.0, 4.4), (14.0, 6.0, 0.4), "M_Teal")
    for sx in (-1, 1):
        mb.box((sx * 6.4, -5.5, 2.1), (0.5, 0.5, 4.2), "M_White")
    mb.box((0, -0.05, 1.6), (5.0, 0.1, 3.0), "M_ShopFront")
    mb.pop()
    text(mb, "BAYSIDE MEDICAL", 1.3, (0, -d / 2 - 6.02, 4.4), 0, "M_White", 0.1)
    # red cross sign
    mb.box((0, -d / 2 - 0.15, H - 2.5), (0.9, 0.2, 3.0), "M_Cross")
    mb.box((0, -d / 2 - 0.15, H - 2.5), (3.0, 0.2, 0.9), "M_Cross")
    mb.box((0, 0, H + 0.05), (w - 0.6, d - 0.6, 0.1), "M_ConcreteDark")
    col.box((0, 0, H + 0.05), (w, d, 0.3), "M_Col")
    # rooftop helipad
    mb.cyl((-8, 0, H + 0.3), 7.0, 0.4, "M_DarkGrey", seg=16)
    mb.cyl((-8, 0, H + 0.52), 5.6, 0.05, "M_Yellow", seg=16, r2=5.6)
    mb.cyl((-8, 0, H + 0.54), 5.2, 0.05, "M_DarkGrey", seg=16)
    mb.box((-8, 0, H + 0.58), (0.6, 3.6, 0.04), "M_White")
    mb.box((-9.4, 0, H + 0.58), (0.6, 3.6, 0.04), "M_White")
    mb.box((-6.6, 0, H + 0.58), (0.6, 3.6, 0.04), "M_White")
    mb.box((-8, 0, H + 0.585), (3.2, 0.6, 0.04), "M_White")
    col.cyl((-8, 0, H + 0.3), 7.0, 0.5, "M_Col", seg=12)
    mb.box((10, 4, H + 1.6), (6, 5, 3.2), "M_ConcreteDark")
    ob = finish(name, mb, col)
    empty(name + "_door", CB, loc=(0, -d / 2 - 8.0, 0.0), parent=ob)
    empty(name + "_helipad", CB, loc=(-8, 0, H + 0.6), parent=ob)
    return ob


def gas_station(name):
    mb = MB()
    col = MB()
    # canopy
    mb.box((0, 0, 5.2), (18.0, 10.0, 0.7), "M_White")
    mb.box((0, 0, 5.2), (18.2, 10.2, 0.3), "M_Orange")
    col.box((0, 0, 5.2), (18.0, 10.0, 0.7), "M_Col")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 7.0, sy * 3.0, 2.45), (0.5, 0.5, 4.9), "M_Steel")
            col.box((sx * 7.0, sy * 3.0, 2.45), (0.5, 0.5, 4.9), "M_Col")
    for i in range(6):
        mb.box((-7.5 + i * 3.0, 0, 4.83), (1.6, 0.5, 0.06), "M_LampGlow")
    text(mb, "FUELIO", 1.0, (0, -5.12, 5.2), 0, "M_Orange", 0.08)
    # pump islands
    for sx in (-1, 1):
        mb.box((sx * 3.5, 0, 0.12), (1.4, 7.0, 0.24), "M_Concrete")
        col.box((sx * 3.5, 0, 0.12), (1.4, 7.0, 0.24), "M_Col")
        for sy in (-2.0, 2.0):
            mb.box((sx * 3.5, sy, 1.05), (0.8, 0.55, 1.7), "M_Orange")
            mb.box((sx * 3.5, sy, 1.45), (0.82, 0.4, 0.5), "M_Black")
            mb.box((sx * 3.5, sy, 2.0), (0.9, 0.65, 0.2), "M_White")
            col.box((sx * 3.5, sy, 1.05), (0.8, 0.55, 1.9), "M_Col")
    # kiosk
    mb.box((0, 11.5, 2.0), (12.0, 7.0, 4.0), "M_White")
    mb.box((0, 11.5, 4.15), (12.4, 7.4, 0.3), "M_Orange")
    mb.box((0, 7.97, 1.8), (8.0, 0.06, 2.4), "M_ShopFront")
    mb.box((3.0, 7.95, 1.2), (1.3, 0.1, 2.3), "M_Door")
    col.box((0, 11.5, 2.1), (12.0, 7.0, 4.2), "M_Col")
    text(mb, "SNACKS + COFFEE", 0.5, (0, 7.9, 3.45), 0, "M_Neon_C", 0.05)
    # price pylon
    mb.box((-12, -6, 3.5), (0.5, 0.5, 7.0), "M_Steel")
    mb.box((-12, -6, 6.0), (3.0, 0.5, 2.6), "M_Orange")
    mb.box((-12, -6.27, 6.0), (2.6, 0.04, 2.2), "M_White")
    col.box((-12, -6, 3.5), (0.6, 0.6, 7.0), "M_Col")
    ob = finish(name, mb, col)
    empty(name + "_shop", CB, loc=(3.0, 6.5, 0.0), parent=ob)
    return ob


def hangar(name):
    w, d, h = 30.0, 28.0, 9.0
    mb = MB()
    col = MB()
    t = 0.5
    mb.box((0, 0, 0.05), (w, d, 0.1), "M_Concrete")
    for c, s in (((0, d / 2 - t / 2, h / 2), (w, t, h)), ((-w / 2 + t / 2, 0, h / 2), (t, d - 2 * t, h)), ((w / 2 - t / 2, 0, h / 2), (t, d - 2 * t, h))):
        mb.box(c, s, "M_Corrugated")
        col.box(c, s, "M_Col")
    # arched roof from segments
    segs = 8
    for i in range(segs):
        a0 = math.pi * i / segs
        a1 = math.pi * (i + 1) / segs
        x0, z0 = -math.cos(a0) * (w / 2 + 0.3), h + math.sin(a0) * 5.0
        x1, z1 = -math.cos(a1) * (w / 2 + 0.3), h + math.sin(a1) * 5.0
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        L = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(z1 - z0, x1 - x0)
        mb.box((cx, 0, cz), (L + 0.05, d + 0.6, 0.3), "M_RoofSlate", rot=(0, -ang, 0))
        col.box((cx, 0, cz), (L + 0.05, d + 0.6, 0.3), "M_Col", rot=(0, -ang, 0))
    # back + front gable infill
    pts = [(-math.cos(math.pi * i / segs) * (w / 2), h + math.sin(math.pi * i / segs) * 4.8) for i in range(segs + 1)]
    mb.prism(pts, t, "M_Corrugated", plane='XZ', c=(0, d / 2 - t / 2, 0))
    mb.prism(pts + [(w / 2, h - 0.01)], 0.3, "M_Corrugated", plane='XZ', c=(0, -d / 2 + 0.15, 0))
    for sx in (-1, 1):
        mb.box((sx * (w / 2 - 2.0), -d / 2 + 0.25, h / 2), (4.0, 0.5, h), "M_Corrugated")
        col.box((sx * (w / 2 - 2.0), -d / 2 + 0.25, h / 2), (4.0, 0.5, h), "M_Col")
        mb.box((sx * (w / 2 - 4.2), -d / 2 - 0.05, h / 2), (0.5, 0.6, h), "M_Yellow")
    for i in range(3):
        mb.box((-8 + i * 8, 0, h + 3.2), (0.6, d - 4, 0.1), "M_LampGlow")
    text(mb, "HANGAR 1", 1.6, (0, -d / 2 - 0.05, h + 2.3), 0, "M_White", 0.1)
    return finish(name, mb, col)


def terminal(name):
    w, d = 40.0, 14.0
    rng = random.Random(5)
    P = dict(wall="M_White", trim="M_Steel", rail="M_MetalDark")
    H = 9.0
    mb = MB()
    col = MB()
    mb.box((0, 0, H / 2), (w, d, H), "M_White")
    col.box((0, 0, H / 2), (w, d, H), "M_Col")
    for (o, rz, L) in facade_sides(w, d):
        n = round(L / 4.0)
        bw = L / n
        mb.push(o, (0, 0, rz))
        for b in range(n):
            mb.box((-L / 2 + (b + 0.5) * bw, -0.03, 4.4), (bw - 0.3, 0.06, 7.0), "M_ShopFront" if b % 3 else "M_WindowLit")
            mb.box((-L / 2 + b * bw, -0.08, H / 2), (0.25, 0.16, H), "M_Steel")
        mb.pop()
    mb.box((0, 0, H + 0.3), (w + 3.0, d + 3.0, 0.6), "M_Steel")
    col.box((0, 0, H + 0.3), (w + 3.0, d + 3.0, 0.6), "M_Col")
    text(mb, "MARLOW BAY AIRFIELD", 1.5, (0, -d / 2 - 1.55, H + 0.35), 0, "M_Navy", 0.1)
    return finish(name, mb, col)


def control_tower(name):
    mb = MB()
    col = MB()
    mb.cyl((0, 0, 9.0), 3.0, 18.0, "M_White", seg=8, r2=2.4)
    col.cyl((0, 0, 9.0), 3.0, 18.0, "M_Col", seg=8, r2=2.4)
    mb.cyl((0, 0, 18.4), 4.6, 0.8, "M_Steel", seg=8)
    mb.cyl((0, 0, 20.3), 4.2, 3.0, "M_ShopFront", seg=8, r2=4.9)
    mb.cyl((0, 0, 22.1), 5.2, 0.6, "M_White", seg=8)
    col.cyl((0, 0, 20.4), 5.0, 4.6, "M_Col", seg=8)
    mb.limb((0, 0, 22.4), (0, 0, 27.0), 0.15, 0.05, "M_Steel", seg=5)
    mb.box((0, 0, 27.0), (0.25, 0.25, 0.25), "M_Siren_R")
    mb.box((0, -2.9, 1.1), (1.2, 0.3, 2.2), "M_Door")
    for i in range(4):
        mb.box((0, -2.75 + i * 0.07, 4.0 + i * 3.6), (1.0, 0.1, 1.2), "M_WindowDark")
    return finish(name, mb, col)


def parking(name):
    w, d = 36.0, 30.0
    mb = MB()
    col = MB()
    levels = 3
    lh = 3.4
    for l in range(1, levels + 1):
        z = l * lh
        mb.box((0, 0, z), (w, d, 0.4), "M_Concrete")
        col.box((0, 0, z), (w, d, 0.4), "M_Col")
        for (o, rz, L) in facade_sides(w, d):
            mb.push(o, (0, 0, rz))
            mb.box((0, 0.1, z + 0.7), (L, 0.2, 1.0), "M_ConcreteDark")
            mb.box((0, -0.02, z + 0.7), (L - 2, 0.05, 0.25), "M_Yellow")
            mb.pop()
    for ix in range(7):
        for iy in range(4):
            x = -w / 2 + 0.5 + ix * (w - 1.0) / 6
            y = -d / 2 + 0.5 + iy * (d - 1.0) / 3
            if iy in (1, 2) and ix in (1, 2, 3, 4, 5):
                continue
            mb.box((x, y, levels * lh / 2), (0.7, 0.7, levels * lh), "M_ConcreteDark")
            col.box((x, y, levels * lh / 2), (0.7, 0.7, levels * lh), "M_Col")
    mb.box((w / 2 - 3, d / 2 - 3, levels * lh / 2 + 1.5), (5, 5, levels * lh + 3.0), "M_Concrete")
    col.box((w / 2 - 3, d / 2 - 3, levels * lh / 2 + 1.5), (5, 5, levels * lh + 3.0), "M_Col")
    text(mb, "PARK", 2.0, (0, -d / 2 - 0.1, levels * lh + 0.7), 0, "M_Neon_B", 0.1)
    return finish(name, mb, col)


def lighthouse(name):
    mb = MB()
    col = MB()
    mb.cyl((0, 0, 0.75), 4.2, 1.5, "M_Rock", seg=10, r2=3.6)
    for i in range(4):
        mb.cyl((0, 0, 1.5 + 2.5 + i * 5.0), 2.6 - i * 0.3, 5.0, "M_White" if i % 2 == 0 else "M_Red", seg=10, r2=2.3 - i * 0.3)
    col.cyl((0, 0, 11.0), 2.8, 22.0, "M_Col", seg=8, r2=1.6)
    col.cyl((0, 0, 0.75), 4.2, 1.5, "M_Col", seg=8)
    mb.cyl((0, 0, 21.8), 2.4, 0.4, "M_MetalDark", seg=10)
    mb.cyl((0, 0, 23.2), 1.3, 2.4, "M_LampGlow", seg=8)
    mb.cyl((0, 0, 25.0), 1.9, 1.4, "M_Red", seg=10, r2=0.1)
    mb.box((0, -2.6, 2.6), (1.0, 0.3, 2.0), "M_Door")
    return finish(name, mb, col)


def station(name):
    """Elevated monorail station platform with stairs."""
    mb = MB()
    col = MB()
    ph = 6.0
    mb.box((0, 0, ph - 0.25), (22.0, 5.0, 0.5), "M_Concrete")
    col.box((0, 0, ph - 0.25), (22.0, 5.0, 0.5), "M_Col")
    for sx in (-8, 0, 8):
        mb.box((sx, 0, (ph - 0.5) / 2), (0.8, 0.8, ph - 0.5), "M_ConcreteDark")
        col.box((sx, 0, (ph - 0.5) / 2), (0.8, 0.8, ph - 0.5), "M_Col")
    mb.box((0, 0.5, ph + 3.2), (22.0, 5.0, 0.25), "M_Teal")
    for sx in (-10, -5, 0, 5, 10):
        mb.box((sx, 2.3, ph + 1.6), (0.2, 0.2, 3.2), "M_Steel")
    mb.box((0, 2.4, ph + 0.55), (22.0, 0.1, 1.1), "M_ShopFront")
    col.box((0, 2.5, ph + 0.8), (22.0, 0.2, 1.6), "M_Col")
    text(mb, "SKYLINE", 0.8, (0, -2.52, ph - 0.25), 0, "M_White", 0.05)
    # stairs down the +X end towards -Y
    steps = 20
    for i in range(steps):
        z = ph - (i + 1) * (ph / steps)
        mb.box((12.5 + i * 0.42, 0, z + 0.15), (0.44, 2.4, 0.3), "M_ConcreteDark")
    col.box((12.5 + steps * 0.21 - 0.2, 0, ph / 2 - 0.1), (math.hypot(steps * 0.42, ph), 2.4, 0.3), "M_Col", rot=(0, math.atan2(ph, steps * 0.42), 0))
    for sy in (-1.2, 1.2):
        mb.box((12.5 + steps * 0.21 - 0.2, sy, ph / 2 + 0.9), (math.hypot(steps * 0.42, ph), 0.08, 0.1), "M_Steel", rot=(0, math.atan2(ph, steps * 0.42), 0))
    ob = finish(name, mb, col)
    empty(name + "_board", CB, loc=(0, -1.5, ph), parent=ob)
    return ob


build_kit()
out = []
B = lambda ob: out.append((ob.name, tri_count(ob)))
B(tower("off_a", 36, 36, 16, "office", "M_Concrete", "M_ConcreteDark", seed=1, tank=True))
B(tower("off_b", 36, 36, 11, "office", "M_White", "M_Teal", seed=2))
B(tower("off_c", 36, 16, 9, "office", "M_ConcreteDark", "M_DarkGrey", seed=3))
B(tower("off_d", 16, 16, 14, "office", "M_Navy", "M_Steel", seed=4, antenna=True))
B(tower("off_e", 30, 30, 22, "office", "M_DarkGrey", "M_Steel", seed=5, crown=True, antenna=True, sign="ORBIS", sign_mat="M_Neon_B"))
B(tower("off_f", 36, 16, 6, "office", "M_Brick", "M_Cream", seed=6, tank=True, ground="shop"))
B(tower("off_g", 16, 16, 9, "office", "M_Terracotta", "M_Cream", seed=16, ground="shop"))
B(tower("apt_a", 36, 16, 6, "apt", "M_Stucco", "M_White", ground="apt", gh=3.4, seed=7))
B(tower("apt_b", 36, 16, 5, "apt", "M_StuccoPink", "M_White", ground="shop", seed=8))
B(tower("apt_c", 16, 16, 8, "apt", "M_StuccoBlue", "M_White", ground="apt", gh=3.4, seed=9, tank=True))
B(tower("apt_d", 30, 20, 7, "apt", "M_StuccoMint", "M_Cream", ground="apt", gh=3.4, seed=10))
B(tower("apt_e", 36, 16, 4, "apt", "M_Brick", "M_Cream", ground="shop", seed=11, tank=True))
B(tower("hotel", 36, 20, 10, "apt", "M_Cream", "M_Terracotta", ground="office_ground", seed=12, sign="CORALINE HOTEL", sign_mat="M_Neon_A", rail="M_ShopFront"))
B(shop_row("shop_a", 36, 14, 3, 1, "M_Stucco", "M_White", ["NOODLE BAR", "PAWN", "VINYL"], seed=1))
B(shop_row("shop_b", 36, 14, 3, 2, "M_StuccoPink", "M_White", ["BAKERY", "BOOKS", "PHARMA"], seed=2))
B(shop_row("shop_c", 16, 14, 1, 1, "M_StuccoMint", "M_White", ["MINI MART"], seed=3))
B(shop_row("shop_d", 36, 16, 4, 2, "M_Brick", "M_Cream", ["CAFE", "TATTOO", "LAUNDRY", "PIZZA"], seed=4))
B(shop_row("shop_clothing", 16, 14, 1, 1, "M_White", "M_Black", ["THREADLINE"], seed=5))
B(shop_row("shop_barber", 16, 14, 1, 1, "M_StuccoBlue", "M_White", ["FADE ROOM"], seed=6))
B(shop_row("shop_food", 16, 14, 1, 1, "M_Terracotta", "M_Cream", ["BITE BOX"], seed=7))
cols = [("M_Stucco", "M_RoofRed"), ("M_StuccoPink", "M_RoofSlate"), ("M_StuccoBlue", "M_Roof"), ("M_StuccoMint", "M_RoofRed"),
        ("M_White", "M_RoofSlate"), ("M_Cream", "M_Roof")]
for i, (wc, rc) in enumerate(cols):
    B(house("house_" + "abcdef"[i], 10 + (i % 3) * 1.5, 8.5 + (i % 2) * 1.5, 1 + (i % 2), wc, rc, seed=20 + i, garage=(i % 3 != 2)))
B(warehouse("wh_a", 36, 24, 9, "M_Corrugated", seed=30, doors=3, sign="DOCKSIDE FREIGHT"))
B(warehouse("wh_b", 30, 16, 7, "M_CorrugatedRust", seed=31, doors=2))
B(warehouse("wh_c", 36, 36, 10, "M_Brick", "M_RoofSlate", seed=32, doors=2, stacks=2, sign="MARLOW WORKS"))
B(warehouse("wh_d", 16, 16, 6, "M_CorrugatedTeal", seed=33, doors=1))
B(gunshop("shop_gun"))
B(modgarage("garage_mod"))
B(safehouse("safehouse"))
B(police_station("police_station"))
B(hospital("hospital"))
B(gas_station("gas_station"))
B(hangar("hangar"))
B(terminal("terminal"))
B(control_tower("control_tower"))
B(parking("parking"))
B(lighthouse("lighthouse"))
B(station("station"))
print(out)
print("total tris", sum(t for n, t in out))
