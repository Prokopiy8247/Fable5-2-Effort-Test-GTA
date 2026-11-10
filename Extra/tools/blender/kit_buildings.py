# Modular building kit + landmark buildings for Cinder Bay. Executed in Blender through MCP.
# Facade modules: 4 m wide (x in [-2,2]), wall plane at y=0 facing -Y (Godot +Z), base at z=0.
# Materials ending in "Tint" are tinted per instance in Godot (MultiMesh instance colour).
import bpy, math
from mathutils import Vector
from fable_lib import *

T = math.radians
GH = 4.2   # ground floor height
FH = 3.4   # upper floor height


def panel(mb, w, h, openings, m_wall, x0=None):
    """Front wall quad grid with rectangular recessed openings.
    openings: (xa, xb, za, zb, depth, m_back[, m_reveal])"""
    xa = -w / 2 if x0 is None else x0
    xs = sorted(set([xa, xa + w] + [o[0] for o in openings] + [o[1] for o in openings]))
    zs = sorted(set([0.0, h] + [o[2] for o in openings] + [o[3] for o in openings]))
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            cx = (xs[i] + xs[i + 1]) / 2
            cz = (zs[j] + zs[j + 1]) / 2
            if any(o[0] < cx < o[1] and o[2] < cz < o[3] for o in openings):
                continue
            mb.poly([(xs[i], 0, zs[j]), (xs[i + 1], 0, zs[j]), (xs[i + 1], 0, zs[j + 1]), (xs[i], 0, zs[j + 1])], m_wall, outward=(0, -1, 0))
    for o in openings:
        a, b, c, d, dep, mback = o[:6]
        mrev = o[6] if len(o) > 6 else m_wall
        mb.poly([(a, dep, c), (b, dep, c), (b, dep, d), (a, dep, d)], mback, outward=(0, -1, 0))
        mb.poly([(a, 0, c), (a, dep, c), (a, dep, d), (a, 0, d)], mrev, outward=(1, 0, 0))
        mb.poly([(b, 0, c), (b, dep, c), (b, dep, d), (b, 0, d)], mrev, outward=(-1, 0, 0))
        mb.poly([(a, 0, d), (b, 0, d), (b, dep, d), (a, dep, d)], mrev, outward=(0, 0, -1))
        mb.poly([(a, 0, c), (b, 0, c), (b, dep, c), (a, dep, c)], mrev, outward=(0, 0, 1))


class Kit:
    def __init__(self, root_name, coll_path, cell, spacing=6.0, per_row=10):
        self.coll = col(coll_path)
        kill(root_name)
        self.root = empty(root_name, self.coll, loc=cell, size=0.5)
        self.n = 0
        self.spacing = spacing
        self.per_row = per_row
        self.names = []

    def add(self, name, mb, smooth=None, big=1):
        x = (self.n % self.per_row) * self.spacing
        y = (self.n // self.per_row) * self.spacing
        o = mb.finish(name, self.coll, smooth=smooth, parent=self.root, loc=(x, y, 0))
        self.n += big
        self.names.append(name)
        return o


def facade_modules(K):
    # --- glass office
    mb = MB()
    panel(mb, 4, FH, [(-2, 2, 0.8, FH, 0.06, "WindowGlass")], "WallTint")
    for x in (-2, -0.67, 0.67, 2):
        mb.box((0.07, 0.10, FH - 0.8), loc=(x, 0.0, (FH + 0.8) / 2), m="FrameDark")
    mb.box((4, 0.10, 0.07), loc=(0, 0.0, 0.8), m="FrameDark")
    K.add("bm_office_upper", mb)
    mb = MB()
    panel(mb, 4, GH, [(-2, 2, 0.12, 3.45, 0.08, "WindowGlass")], "WallTint")
    for x in (-2, 0, 2):
        mb.box((0.09, 0.12, 3.33), loc=(x, 0.0, 1.785), m="FrameDark")
    mb.box((4, 0.25, 0.10), loc=(0, -0.08, 3.5), m="FrameDark")
    K.add("bm_office_ground", mb)
    mb = MB()
    panel(mb, 4, GH, [(-2, 2, 0.02, 3.45, 0.3, "WindowGlass")], "WallTint")
    mb.box((2.0, 0.08, 2.5), loc=(0, 0.26, 1.27), m="FrameDark")
    mb.box((0.90, 0.09, 2.3), loc=(-0.47, 0.25, 1.2), m="WindowGlass")
    mb.box((0.90, 0.09, 2.3), loc=(0.47, 0.25, 1.2), m="WindowGlass")
    for s in (1, -1):
        mb.box((0.04, 0.06, 0.5), loc=(s * 0.10, 0.19, 1.2), m="Chrome")
    mb.box((3.2, 1.5, 0.14), loc=(0, -0.75, 3.0), m="FrameDark")
    mb.box((3.0, 1.3, 0.02), loc=(0, -0.75, 2.92), m="LampGlow")
    K.add("bm_office_door", mb)
    mb = MB()
    mb.box((4, 0.3, 0.8), loc=(0, 0.15, 0.4), m="WallTint")
    mb.box((4, 0.36, 0.08), loc=(0, 0.15, 0.84), m="FrameDark")
    K.add("bm_parapet_modern", mb)
    # --- concrete grid office / generic midrise
    mb = MB()
    panel(mb, 4, FH, [(-1.75, -0.25, 0.9, 2.9, 0.22, "WindowGlass"), (0.25, 1.75, 0.9, 2.9, 0.22, "WindowGlass")], "WallTint")
    for x in (-1.0, 1.0):
        mb.box((1.5, 0.05, 0.06), loc=(x, 0.20, 1.9), m="WindowFrame")
        mb.box((0.05, 0.05, 2.0), loc=(x, 0.20, 1.9), m="WindowFrame")
    K.add("bm_grid_upper", mb)
    # --- apartments
    mb = MB()
    panel(mb, 4, FH, [(-0.8, 0.8, 1.0, 2.5, 0.16, "WindowGlass", "WindowFrame")], "WallTint")
    mb.box((1.8, 0.14, 0.08), loc=(0, -0.05, 0.96), m="WindowFrame")
    mb.box((0.05, 0.05, 1.5), loc=(0, 0.14, 1.75), m="WindowFrame")
    for s in (1, -1):
        mb.box((0.38, 0.05, 1.5), loc=(s * 1.02, -0.025, 1.75), m="AwningTint")
    K.add("bm_apt_window", mb)
    mb = MB()
    panel(mb, 4, FH, [(-0.75, 0.75, 0.12, 2.5, 0.16, "WindowGlass", "WindowFrame")], "WallTint")
    mb.box((0.05, 0.05, 2.38), loc=(0, 0.14, 1.31), m="WindowFrame")
    mb.box((2.8, 1.1, 0.12), loc=(0, -0.55, 0.06), m="Concrete")
    mb.box((2.8, 0.04, 0.05), loc=(0, -1.08, 1.05), m="FrameDark")
    for i in range(8):
        mb.box((0.03, 0.03, 0.95), loc=(-1.38 + i * 0.394, -1.08, 0.58), m="FrameDark")
    for s in (1, -1):
        mb.box((0.04, 1.08, 0.05), loc=(s * 1.38, -0.54, 1.05), m="FrameDark")
        mb.box((0.03, 0.03, 0.95), loc=(s * 1.38, -0.55, 0.58), m="FrameDark")
    K.add("bm_apt_balcony", mb)
    mb = MB()
    panel(mb, 4, GH, [(-0.7, 0.7, 0.0, 2.4, 0.25, "Door", "WindowFrame")], "WallTint")
    mb.box((0.06, 0.04, 0.25), loc=(0.5, 0.22, 1.15), m="Chrome")
    mb.box((2.2, 0.9, 0.10), loc=(0, -0.45, 2.65), m="AwningTint", rot=(T(8), 0, 0))
    mb.box((1.8, 0.6, 0.15), loc=(0, -0.3, 0.075), m="Concrete")
    mb.box((0.3, 0.12, 0.3), loc=(1.2, -0.06, 2.2), m="LampGlow")
    K.add("bm_apt_ground_door", mb)
    mb = MB()
    panel(mb, 4, GH, [(-0.9, 0.9, 1.2, 2.9, 0.16, "WindowGlass", "WindowFrame")], "WallTint")
    mb.box((2.0, 0.14, 0.08), loc=(0, -0.05, 1.16), m="WindowFrame")
    mb.box((0.05, 0.05, 1.7), loc=(0, 0.14, 2.05), m="WindowFrame")
    mb.box((4, 0.06, 0.5), loc=(0, -0.03, 0.25), m="ConcreteDark")
    K.add("bm_apt_ground_window", mb)
    mb = MB()
    mb.box((4, 0.3, 0.7), loc=(0, 0.15, 0.35), m="WallTint")
    mb.box((4.0, 0.5, 0.12), loc=(0, 0.08, 0.76), m="Concrete")
    K.add("bm_parapet_classic", mb)
    # --- storefronts (ground)
    mb = MB()
    panel(mb, 4, GH, [(-1.75, 1.75, 0.5, 2.9, 0.12, "ShopGlass", "FrameDark")], "WallTint")
    mb.box((3.7, 0.10, 0.75), loc=(0, -0.05, 3.5), m="SignTint")
    mb.box((3.9, 1.1, 0.07), loc=(0, -0.55, 2.82), m="AwningTint", rot=(T(14), 0, 0))
    mb.box((0.05, 0.06, 2.4), loc=(0, 0.10, 1.7), m="FrameDark")
    K.add("bm_shop_window", mb)
    mb = MB()
    panel(mb, 4, GH, [(-1.75, 1.75, 0.03, 2.9, 0.12, "ShopGlass", "FrameDark")], "WallTint")
    mb.box((1.25, 0.08, 2.6), loc=(0, 0.10, 1.33), m="FrameDark")
    mb.box((1.05, 0.09, 2.4), loc=(0, 0.095, 1.28), m="ShopGlass")
    mb.box((0.04, 0.07, 0.6), loc=(0.42, 0.04, 1.2), m="Chrome")
    mb.box((3.7, 0.10, 0.75), loc=(0, -0.05, 3.5), m="SignTint")
    mb.box((3.9, 1.1, 0.07), loc=(0, -0.55, 2.82), m="AwningTint", rot=(T(14), 0, 0))
    K.add("bm_shop_door", mb)
    # --- brick
    mb = MB()
    panel(mb, 4, FH, [(-1.55, -0.45, 0.9, 2.7, 0.18, "WindowGlass"), (0.45, 1.55, 0.9, 2.7, 0.18, "WindowGlass")], "BrickTint")
    for x in (-1.0, 1.0):
        mb.box((1.3, 0.12, 0.10), loc=(x, -0.02, 0.86), m="Concrete")
        mb.box((1.3, 0.10, 0.16), loc=(x, -0.02, 2.78), m="Concrete")
        mb.box((1.1, 0.04, 0.05), loc=(x, 0.16, 1.8), m="WindowFrame")
    K.add("bm_brick_upper", mb)
    mb = MB()
    panel(mb, 4, GH, [(-1.2, 1.2, 0.6, 3.0, 0.2, "ShopGlass", "Concrete")], "BrickTint")
    mb.box((4, 0.08, 0.6), loc=(0, -0.04, 0.3), m="ConcreteDark")
    mb.box((4, 0.12, 0.22), loc=(0, -0.04, 3.9), m="Concrete")
    mb.box((0.06, 0.05, 2.4), loc=(0, 0.17, 1.8), m="FrameDark")
    K.add("bm_brick_ground", mb)
    mb = MB()
    panel(mb, 4, GH, [(-0.75, 0.75, 0.0, 2.5, 0.25, "Door", "Concrete")], "BrickTint")
    mb.box((4, 0.12, 0.22), loc=(0, -0.04, 3.9), m="Concrete")
    mb.box((1.9, 0.14, 0.2), loc=(0, -0.03, 2.62), m="Concrete")
    mb.box((0.06, 0.04, 0.25), loc=(0.52, 0.22, 1.15), m="Chrome")
    K.add("bm_brick_door", mb)
    mb = MB()
    mb.box((4, 0.3, 0.6), loc=(0, 0.15, 0.3), m="BrickTint")
    mb.box((4.0, 0.55, 0.18), loc=(0, 0.06, 0.66), m="Concrete")
    for i in range(8):
        mb.box((0.2, 0.12, 0.14), loc=(-1.75 + i * 0.5, -0.12, 0.50), m="Concrete")
    K.add("bm_parapet_brick", mb)
    # --- industrial
    def ribs(mb, h, m="CorrTint"):
        for i in range(8):
            mb.box((0.12, 0.06, h), loc=(-1.75 + i * 0.5, -0.01, h / 2), m=m)
    mb = MB(); panel(mb, 4, FH, [], "CorrTint"); ribs(mb, FH); K.add("bm_ind_upper", mb)
    mb = MB(); panel(mb, 4, FH, [(-1.6, 1.6, 1.9, 2.9, 0.1, "WindowGlass", "FrameDark")], "CorrTint")
    for x in (-0.8, 0, 0.8):
        mb.box((0.05, 0.05, 1.0), loc=(x, 0.08, 2.4), m="FrameDark")
    K.add("bm_ind_window", mb)
    mb = MB(); panel(mb, 4, GH, [], "CorrTint"); ribs(mb, GH)
    mb.box((4, 0.10, 0.9), loc=(0, -0.03, 0.45), m="ConcreteDark")
    K.add("bm_ind_ground", mb)
    mb = MB(); panel(mb, 4, GH, [(-1.7, 1.7, 0.0, 3.5, 0.15, "MetalPanel", "FrameDark")], "CorrTint")
    for i in range(9):
        mb.box((3.4, 0.03, 0.03), loc=(0, 0.13, 0.35 + i * 0.38), m="DarkSteel")
    for s in (1, -1):
        mb.cyl(0.08, 1.0, loc=(s * 1.9, -0.25, 0.5), segs=6, m="PaintYellow")
    mb.box((0.4, 0.15, 0.25), loc=(0, -0.08, 3.85), m="LampGlow")
    K.add("bm_ind_door", mb)
    mb = MB()
    mb.box((4, 0.2, 0.5), loc=(0, 0.10, 0.25), m="CorrTint")
    mb.box((4, 0.26, 0.06), loc=(0, 0.10, 0.53), m="DarkSteel")
    K.add("bm_parapet_ind", mb)
    # blank walls (alley sides / rear)
    mb = MB(); panel(mb, 4, FH, [], "WallTint"); K.add("bm_blank_upper", mb)
    mb = MB(); panel(mb, 4, GH, [], "WallTint"); mb.box((4, 0.06, 0.5), loc=(0, -0.03, 0.25), m="ConcreteDark"); K.add("bm_blank_ground", mb)
    mb = MB(); panel(mb, 4, FH, [], "BrickTint"); K.add("bm_brick_blank", mb)


def gable_house(K, name, w, d, h, roof_h, wall, roof, garage=True, porch=True, two_storey=False):
    """Suburban house, front faces -Y. Origin at footprint centre."""
    mb = MB()
    hh = h * (1.9 if two_storey else 1.0)
    win = []
    floors = [0.0, h] if two_storey else [0.0]
    for z0 in floors:
        for x in (-w / 2 + 1.6, w / 2 - 1.6):
            if z0 == 0 and garage and x > 0:
                continue
            win.append((x - 0.7, x + 0.7, z0 + 1.0, z0 + 2.2, 0.12, "WindowGlass", "WindowFrame"))
    dx = -0.2 if garage else 0.0
    ops = win + [(dx - 0.5, dx + 0.5, 0.0, 2.15, 0.15, "Door", "WindowFrame")]
    if garage:
        ops.append((w / 2 - 3.2, w / 2 - 0.5, 0.0, 2.3, 0.12, "MetalPanel", "WindowFrame"))
    panel(mb, w, hh, ops, wall)
    vs = list(mb.bm.verts)
    mb.transform(vs, loc=(0, -d / 2, 0))
    # other walls
    mb.poly([(-w / 2, d / 2, 0), (w / 2, d / 2, 0), (w / 2, d / 2, hh), (-w / 2, d / 2, hh)], wall, outward=(0, 1, 0))
    for s in (1, -1):
        mb.poly([(s * w / 2, -d / 2, 0), (s * w / 2, d / 2, 0), (s * w / 2, d / 2, hh), (s * w / 2, 0, hh + roof_h), (s * w / 2, -d / 2, hh)], wall, outward=(s, 0, 0))
        mb.box((0.05, 1.2, 1.1), loc=(s * (w / 2 + 0.01), 0.5, 1.6), m="WindowGlass")
    ov = 0.45
    mb.poly([(-w / 2 - ov, -d / 2 - ov, hh - 0.12), (w / 2 + ov, -d / 2 - ov, hh - 0.12), (w / 2 + ov, 0, hh + roof_h + 0.08), (-w / 2 - ov, 0, hh + roof_h + 0.08)], roof, outward=(0, -1, 1))
    mb.poly([(-w / 2 - ov, d / 2 + ov, hh - 0.12), (w / 2 + ov, d / 2 + ov, hh - 0.12), (w / 2 + ov, 0, hh + roof_h + 0.08), (-w / 2 - ov, 0, hh + roof_h + 0.08)], roof, outward=(0, 1, 1))
    mb.poly([(-w / 2 - ov, -d / 2 - ov, hh - 0.14), (w / 2 + ov, -d / 2 - ov, hh - 0.14), (w / 2 + ov, d / 2 + ov, hh - 0.14), (-w / 2 - ov, d / 2 + ov, hh - 0.14)], "WindowFrame", outward=(0, 0, -1))
    mb.box((0.7, 0.7, 1.6), loc=(-w / 4, d / 5, hh + roof_h * 0.6 + 0.4), m="Brick")
    if porch:
        mb.box((3.0, 1.6, 0.18), loc=(dx, -d / 2 - 0.8, 0.09), m="Concrete")
        mb.box((3.2, 1.8, 0.10), loc=(dx, -d / 2 - 0.8, 2.55), m=roof)
        for s in (1, -1):
            mb.box((0.12, 0.12, 2.4), loc=(dx + s * 1.35, -d / 2 - 1.5, 1.3), m="WindowFrame")
    mb.box((w + 0.1, d + 0.1, 0.2), loc=(0, 0, 0.0), m="ConcreteDark")
    return K.add(name, mb, big=2)


def shop_shell(K, name, w=10.0, d=8.0, h=4.0, bay=False, sign="SignTint"):
    """Small enterable building. Front faces -Y, doorway centred. bay=True: wide vehicle door."""
    mb = MB()
    t = 0.25
    dw = 2.6 if bay else 0.8
    dh = 3.3 if bay else 2.4
    mb.box((w, d, 0.2), loc=(0, 0, -0.02), m="FloorTile")
    mb.box((w, d, 0.25), loc=(0, 0, h + 0.125), m="RoofGravel")
    mb.box((w, t, h), loc=(0, d / 2 - t / 2, h / 2), m="WallTint")
    for s in (1, -1):
        mb.box((t, d, h), loc=(s * (w / 2 - t / 2), 0, h / 2), m="WallTint")
        fw = w / 2 - dw
        mb.box((fw, t, 0.7), loc=(s * (dw + fw / 2), -d / 2 + t / 2, 0.35), m="WallTint")
        mb.box((fw, t, h - 3.0), loc=(s * (dw + fw / 2), -d / 2 + t / 2, 3.0 + (h - 3.0) / 2), m="WallTint")
        if bay:
            mb.box((fw, t, 2.3), loc=(s * (dw + fw / 2), -d / 2 + t / 2, 1.85), m="WallTint")
        else:
            mb.box((fw - 0.3, 0.06, 2.3), loc=(s * (dw + fw / 2), -d / 2 + t / 2, 1.85), m="GlassClear")
            mb.box((0.3, t, 2.3), loc=(s * (w / 2 - 0.15), -d / 2 + t / 2, 1.85), m="WallTint")
        mb.box((0.12, t + 0.06, dh), loc=(s * dw, -d / 2 + t / 2, dh / 2), m="FrameDark")
    mb.box((2 * dw, t, h - dh), loc=(0, -d / 2 + t / 2, dh + (h - dh) / 2), m="WallTint")
    mb.box((w * 0.7, 0.25, 1.0), loc=(0, -d / 2 - 0.05, h + 0.65), m=sign)
    mb.box((w * 0.74, 0.18, 1.1), loc=(0, -d / 2 + 0.05, h + 0.65), m="FrameDark")
    mb.box((w + 0.2, d + 0.2, 0.12), loc=(0, 0, h + 0.3), m="FrameDark")
    for x in (-w / 4, w / 4):
        mb.box((1.2, 0.3, 0.05), loc=(x, 0, h - 0.03), m="LampGlow")
    if not bay:
        mb.box((w * 0.5, 1.2, 0.08), loc=(0, -d / 2 - 0.6, 2.95), m="AwningTint", rot=(T(10), 0, 0))
    return K.add(name, mb, big=2)


def landmarks(K):
    mat("FloorTile", "#cfc8b8", rough=0.6)
    mat("GlassClear", "#9fc4d6", rough=0.05, alpha=0.25)
    mat("ShopGlass", "#5f8fa8", rough=0.08, metal=0.2)
    mat("HospitalCross", "#e03a2f", rough=0.5, emit="#ff3020", estr=1.2)
    mat("PoliceBlue", "#27457f", rough=0.6)
    mat("HelipadPaint", "#f0c21c", rough=0.7)
    mat("Tarmac", "#44464b", rough=0.9)
    gable_house(K, "bld_house_a", 11, 8, 2.9, 2.2, "WallTint", "RoofTile")
    gable_house(K, "bld_house_b", 9, 7.5, 2.9, 2.6, "WallTint", "RoofDark", garage=False)
    gable_house(K, "bld_house_c", 12, 8, 2.9, 2.0, "WallTint", "RoofTile", two_storey=True)
    gable_house(K, "bld_house_d", 8, 9, 2.9, 2.4, "WallTint", "RoofDark", garage=False, porch=False, two_storey=True)
    shop_shell(K, "bld_shop", 10, 8, 4.0)
    shop_shell(K, "bld_garage", 14, 12, 5.0, bay=True)
    # safehouse: enterable 2-room home with a garage wing
    mb = MB()
    w, d, h, t = 10.0, 9.0, 3.2, 0.25
    mb.box((w, d, 0.2), loc=(0, 0, -0.02), m="Wood")
    mb.box((w + 0.6, d + 0.6, 0.25), loc=(0, 0, h + 0.125), m="RoofDark")
    mb.box((w, t, h), loc=(0, d / 2 - t / 2, h / 2), m="WallTint")
    for s in (1, -1):
        mb.box((t, d, h), loc=(s * (w / 2 - t / 2), 0, h / 2), m="WallTint")
    mb.box((3.6, t, h), loc=(-3.2, -d / 2 + t / 2, h / 2), m="WallTint")
    mb.box((4.4, t, h), loc=(2.8, -d / 2 + t / 2, h / 2), m="WallTint")
    mb.box((2.0, t, h - 2.3), loc=(-0.4, -d / 2 + t / 2, 2.3 + (h - 2.3) / 2), m="WallTint")
    mb.box((2.2, 0.06, 1.3), loc=(2.8, -d / 2 - 0.01, 1.7), m="WindowGlass")
    mb.box((2.2, 0.06, 1.3), loc=(-3.2, -d / 2 - 0.01, 1.7), m="WindowGlass")
    mb.box((t, 5.0, h), loc=(1.0, 2.0, h / 2), m="WallWhite")
    mb.box((3.0, 1.8, 0.12), loc=(-0.4, -d / 2 - 0.9, 2.6), m="AwningTint")
    mb.box((2.6, 1.4, 0.16), loc=(-0.4, -d / 2 - 0.7, 0.02), m="Concrete")
    mb.box((1.2, 0.3, 0.05), loc=(-2, 0, h - 0.03), m="LampGlow")
    mb.box((w * 0.5, 0.2, 0.7), loc=(0, -d / 2 - 0.02, h + 0.6), m="SignTint")
    K.add("bld_safehouse", mb, big=2)
    # police station
    mb = MB()
    mb.box((26, 16, 8.5), loc=(0, 0, 4.25), m="Concrete")
    mb.box((26.6, 16.6, 0.5), loc=(0, 0, 8.75), m="PoliceBlue")
    mb.box((10, 3, 0.6), loc=(0, -9.5, 0.3), m="ConcreteDark")
    mb.box((8, 2, 0.3), loc=(0, -10.5, 0.15), m="ConcreteDark")
    for x in (-4, -1.4, 1.4, 4):
        mb.cyl(0.35, 5.0, loc=(x, -9.2, 3.1), segs=8, m="WallWhite")
    mb.box((10.4, 3.4, 0.7), loc=(0, -9.4, 5.95), m="PoliceBlue")
    mb.box((7, 0.2, 1.0), loc=(0, -11.15, 5.95), m="SignWhite")
    mb.box((2.4, 0.3, 3.0), loc=(0, -8.02, 2.1), m="ShopGlass")
    for fl in (0, 1):
        for x in (-11, -9, -7, 7, 9, 11) + ((-4.5, -1.5, 1.5, 4.5) if fl == 1 else ()):
            mb.box((1.3, 0.12, 1.7), loc=(x, -8.02, 2.2 + fl * 3.8), m="WindowGlass")
    for s in (1, -1):
        for fl in (0, 1):
            for i in range(4):
                mb.box((0.12, 1.3, 1.7), loc=(s * 13.02, -5.5 + i * 3.6, 2.2 + fl * 3.8), m="WindowGlass")
    mb.cyl(0.06, 7, loc=(7.5, -10.5, 3.5), segs=6, m="Steel")
    mb.box((1.5, 0.04, 0.9), loc=(8.3, -10.5, 6.4), m="PoliceBlue")
    for s in (1, -1):
        mb.sphere(0.3, loc=(s * 5.4, -11.0, 1.2), m="LampGlow", segs=6, rings=4)
        mb.cyl(0.08, 1.0, loc=(s * 5.4, -11.0, 0.5), segs=6, m="FrameDark")
    K.add("bld_police", mb, big=5)
    # hospital
    mb = MB()
    mb.box((30, 18, 13), loc=(0, 0, 6.5), m="WallWhite")
    mb.box((12, 12, 3.5), loc=(0, 0, 14.75), m="WallWhite")
    mb.box((30.4, 18.4, 0.4), loc=(0, 0, 13.2), m="StuccoTeal")
    mb.box((30.1, 0.1, 0.9), loc=(0, -9.02, 4.4), m="StuccoTeal")
    mb.box((9, 5, 0.4), loc=(0, -11.5, 3.8), m="StuccoTeal")
    for s in (1, -1):
        mb.cyl(0.25, 3.8, loc=(s * 4.0, -13.5, 1.9), segs=8, m="WallWhite")
    mb.box((5, 0.3, 3.0), loc=(0, -9.02, 1.6), m="ShopGlass")
    mb.box((3.0, 0.3, 0.9), loc=(0, -6.02, 15.2), m="HospitalCross")
    mb.box((0.9, 0.3, 3.0), loc=(0, -6.02, 15.2), m="HospitalCross")
    mb.box((1.6, 0.2, 0.5), loc=(0, -14.02, 3.8), m="HospitalCross")
    mb.box((0.5, 0.2, 1.6), loc=(0, -14.02, 3.8), m="HospitalCross")
    for fl in range(3):
        mb.box((28, 0.12, 1.6), loc=(0, -9.03, 6.2 + fl * 2.9), m="WindowGlass")
        for s in (1, -1):
            mb.box((0.12, 16, 1.6), loc=(s * 15.03, 0, 3.2 + fl * 3.6), m="WindowGlass")
    mb.box((28, 0.12, 1.6), loc=(0, 9.03, 6.4), m="WindowGlass")
    mb.cyl(4.2, 0.1, loc=(9, 2, 13.45), segs=16, m="Tarmac")
    mb.box((2.4, 0.5, 0.02), loc=(9, 2, 13.52), m="HelipadPaint")
    mb.box((0.5, 2.4, 0.02), loc=(8.05, 2, 13.52), m="HelipadPaint")
    mb.box((0.5, 2.4, 0.02), loc=(9.95, 2, 13.52), m="HelipadPaint")
    K.add("bld_hospital", mb, big=6)
    # gas station
    mb = MB()
    mb.box((16, 9, 0.5), loc=(0, 0, 5.25), m="WallWhite")
    mb.box((16.1, 9.1, 0.25), loc=(0, 0, 5.3), m="PaintOrange")
    mb.box((15, 8, 0.04), loc=(0, 0, 4.98), m="LampGlow")
    for x in (-5, 5):
        for y in (-2.5, 2.5):
            mb.box((0.4, 0.4, 5.0), loc=(x, y, 2.5), m="WallWhite")
        mb.box((1.6, 6.0, 0.2), loc=(x, 0, 0.1), m="Concrete")
        for y in (-1.6, 1.6):
            mb.box((0.9, 0.5, 1.5), loc=(x, y, 0.95), m="PaintOrange", bevel=0.05)
            mb.box((0.7, 0.52, 0.5), loc=(x, y, 1.25), m="FrameDark")
            mb.box((0.5, 0.54, 0.25), loc=(x, y, 1.3), m="SignWhite")
    mb.box((0.5, 0.5, 8.5), loc=(9.5, -5.5, 4.25), m="WallWhite")
    mb.box((3.2, 0.5, 2.2), loc=(9.5, -5.5, 7.4), m="PaintOrange")
    mb.box((2.6, 0.54, 0.7), loc=(9.5, -5.5, 7.6), m="SignWhite")
    K.add("bld_gas_canopy", mb, big=3)
    # hangar
    mb = MB()
    n = 10
    W_, D_, H_ = 30.0, 34.0, 11.0
    secs = []
    for y in (-D_ / 2, D_ / 2):
        ring = []
        for i in range(n + 1):
            a = math.pi * i / n
            ring.append(Vector((math.cos(a) * W_ / 2, y, max(0.0, math.sin(a)) ** 0.75 * H_)))
        secs.append(ring)
    mb.loft(secs, "CorrTint", closed=False, cap_start=False, cap_end=False)
    mb.add_inner_shell("MetalPanel", eps=0.15)
    back = [Vector((math.cos(math.pi * i / n) * W_ / 2, D_ / 2, max(0.0, math.sin(math.pi * i / n)) ** 0.75 * H_)) for i in range(n + 1)]
    mb.poly(back, "CorrTint", outward=(0, 1, 0))
    mb.poly([p - Vector((0, 0.15, 0)) for p in back], "MetalPanel", outward=(0, -1, 0))
    mb.box((W_, D_, 0.1), loc=(0, 0, 0.0), m="Concrete")
    for s in (1, -1):
        mb.box((4.0, 0.3, 9.0), loc=(s * 12.6, -D_ / 2, 4.0), m="CorrTint")
    mb.box((W_ * 0.5, 0.4, 1.4), loc=(0, -D_ / 2 - 0.1, H_ + 0.2), m="SignTint")
    K.add("bld_hangar", mb, smooth=30, big=7)
    # control tower
    mb = MB()
    mb.box((6, 6, 20), loc=(0, 0, 10), m="Concrete", taper=(0.8, 0.8))
    mb.box((9, 9, 0.5), loc=(0, 0, 20.2), m="ConcreteDark")
    mb.cyl(4.6, 3.2, loc=(0, 0, 22.0), segs=8, m="WindowGlass", r2=5.2)
    mb.cyl(5.5, 0.4, loc=(0, 0, 23.8), segs=8, m="ConcreteDark")
    mb.cyl(0.08, 5, loc=(0, 0, 26.5), segs=4, m="Steel")
    mb.sphere(0.25, loc=(0, 0, 29.0), m="LightBarRed", segs=6, rings=4)
    mb.box((2.2, 0.3, 2.6), loc=(0, -2.95, 1.3), m="Door")
    K.add("bld_control_tower", mb, smooth=20, big=2)
    # parking deck with ramp (drivable)
    mb = MB()
    PW, PD, PH = 36.0, 28.0, 3.6
    mb.box((PW, PD - 6, 0.4), loc=(0, 3, PH - 0.2), m="Concrete")
    for x in range(-2, 3):
        for y in (-7.5, 3, 13.5):
            mb.box((0.6, 0.6, PH - 0.4), loc=(x * 8.5, y, (PH - 0.4) / 2), m="ConcreteDark")
    mb.poly([(-PW / 2, -PD / 2, 0), (-PW / 2 + 0.0, -PD / 2 + 6, 0), (PW / 2 - 12, -PD / 2 + 6, PH), (PW / 2 - 12, -PD / 2, PH)], "Concrete", outward=(0, 0, 1))
    mb.poly([(-PW / 2, -PD / 2, 0), (PW / 2 - 12, -PD / 2, PH), (PW / 2 - 12, -PD / 2, 0)], "ConcreteDark", outward=(0, -1, 0))
    mb.poly([(-PW / 2, -PD / 2 + 6, 0), (PW / 2 - 12, -PD / 2 + 6, PH), (PW / 2 - 12, -PD / 2 + 6, 0)], "ConcreteDark", outward=(0, 1, 0))
    mb.box((12, 6, 0.4), loc=(PW / 2 - 6, -PD / 2 + 3, PH - 0.2), m="Concrete")
    mb.box((0.2, PD, 1.0), loc=(PW / 2 - 0.1, 0, PH + 0.5), m="ConcreteDark")
    mb.box((0.2, PD - 6, 1.0), loc=(-PW / 2 + 0.1, 3, PH + 0.5), m="ConcreteDark")
    mb.box((PW, 0.2, 1.0), loc=(0, PD / 2 - 0.1, PH + 0.5), m="ConcreteDark")
    mb.box((12, 0.2, 1.0), loc=(PW / 2 - 6, -PD / 2 + 0.1, PH + 0.5), m="ConcreteDark")
    mb.box((24, 0.2, 1.0), loc=(-6, -PD / 2 + 6.1, PH + 0.5), m="ConcreteDark")
    for i in range(9):
        mb.box((0.12, 4.6, 0.02), loc=(-16 + i * 3.6, 11, PH + 0.01), m="PaintWhite")
    mb.box((4, 0.3, 1.2), loc=(-PW / 2 + 3, -PD / 2 - 0.1, 3.4), m="SignBlue")
    K.add("bld_parking", mb, big=7)
    # lighthouse
    mb = MB()
    mb.lathe([(0, 3.2), (1.2, 3.0), (1.2, 2.4), (16, 1.6), (16, 2.3), (16.4, 2.3), (16.4, 1.5)], axis='Z', segs=10,
             m=lambda k: "PaintRed" if k == 3 else "WallWhite")
    mb.cyl(1.4, 2.2, loc=(0, 0, 17.5), segs=8, m="LampGlow")
    mb.lathe([(18.6, 1.8), (20.0, 0.0)], axis='Z', segs=8, m="PaintRed")
    mb.box((1.0, 0.3, 2.1), loc=(0, -3.1, 1.05), m="Door")
    K.add("bld_lighthouse", mb, smooth=30, big=2)
    # water tower
    mb = MB()
    mb.lathe([(12, 0.0), (12, 2.6), (13, 3.4), (16.5, 3.4), (17.6, 0.0)], axis='Z', segs=10, m="MetalPanel")
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        mb.tube((math.cos(a) * 3.0, math.sin(a) * 3.0, 0), (math.cos(a) * 2.2, math.sin(a) * 2.2, 12.6), 0.16, "DarkSteel")
        a2 = a + math.pi / 2
        mb.tube((math.cos(a) * 2.7, math.sin(a) * 2.7, 4.5), (math.cos(a2) * 2.4, math.sin(a2) * 2.4, 9), 0.07, "DarkSteel", segs=4)
    mb.cyl(0.3, 12, loc=(0, 0, 6), segs=6, m="DarkSteel")
    K.add("bld_water_tower", mb, smooth=30, big=2)
    # dock crane
    mb = MB()
    for x in (-6, 6):
        for y in (-4, 4):
            mb.box((0.7, 0.7, 22), loc=(x, y, 11), m="PaintYellow")
        mb.box((0.6, 8.6, 0.8), loc=(x, 0, 21.6), m="PaintYellow")
        mb.box((0.5, 8.0, 0.5), loc=(x, 0, 8), m="PaintYellow")
    mb.box((30, 1.2, 1.4), loc=(4, -1.5, 23), m="PaintYellow")
    mb.box((30, 1.2, 1.4), loc=(4, 1.5, 23), m="PaintYellow")
    mb.box((3, 4, 2.6), loc=(-3, 0, 21.2), m="WallWhite")
    mb.box((2.9, 0.1, 1.2), loc=(-3, -2.02, 21.5), m="WindowGlass")
    mb.box((2.4, 3.4, 1.0), loc=(12, 0, 22.0), m="DarkSteel")
    for s in (1, -1):
        mb.tube((12 + s * 0.8, 0, 21.5), (12 + s * 0.8, 0, 9.0), 0.04, "Trim", segs=4)
    mb.box((2.6, 6.2, 0.4), loc=(12, 0, 8.8), m="DarkSteel")
    mb.tube((-6, 0, 22), (-2, 0, 30), 0.25, "PaintYellow")
    mb.tube((-2, 0, 30), (18, 0, 23.6), 0.12, "DarkSteel", segs=4)
    K.add("bld_crane", mb, big=6)
    # pier segment (8 m long, 5 m wide), deck top at z=0
    mb = MB()
    mb.box((5, 8, 0.25), loc=(0, 0, -0.125), m="Wood")
    for i in range(8):
        mb.box((5.0, 0.04, 0.02), loc=(0, -3.5 + i, 0.005), m="WoodDark")
    for s in (1, -1):
        for y in (-3.5, 3.5):
            mb.cyl(0.18, 7.0, loc=(s * 2.2, y, -3.3), segs=6, m="WoodDark")
        mb.box((0.14, 8, 0.14), loc=(s * 2.4, 0, 0.07), m="WoodDark")
    K.add("bld_pier", mb, big=2)
    # elevated rail: straight 16 m segment (track top at z=0) + pillar + station platform + train car
    mb = MB()
    mb.box((3.4, 16, 0.5), loc=(0, 0, -0.45), m="Concrete")
    for s in (1, -1):
        mb.box((0.10, 16, 0.14), loc=(s * 0.75, 0, -0.07), m="DarkSteel")
        mb.box((0.25, 16, 0.5), loc=(s * 1.7, 0, -0.2), m="ConcreteDark")
    for i in range(16):
        mb.box((2.2, 0.22, 0.08), loc=(0, -7.5 + i, -0.17), m="WoodDark")
    K.add("rail_straight", mb, big=3)
    mb = MB()
    mb.box((1.2, 1.2, 8.0), loc=(0, 0, -4.7), m="Concrete", taper=(0.8, 0.8))
    mb.box((3.6, 1.6, 0.8), loc=(0, 0, -0.9), m="Concrete")
    K.add("rail_pillar", mb)
    mb = MB()
    mb.box((5, 30, 0.5), loc=(4.3, 0, 0.55), m="Concrete")
    mb.box((0.3, 30, 0.02), loc=(2.1, 0, 0.81), m="PaintYellow")
    mb.box((5.4, 30, 0.25), loc=(4.3, 0, 4.3), m="StuccoTeal")
    for y in (-12, -4, 4, 12):
        mb.box((0.3, 0.3, 3.5), loc=(6.4, y, 2.55), m="FrameDark")
    mb.box((0.15, 6, 1.0), loc=(6.7, 0, 3.4), m="SignWhite")
    for y in (-8, 8):
        mb.box((0.5, 1.8, 0.45), loc=(5.9, y, 1.0), m="Wood")
    # stairs down to street (7.4 m drop) along +Y end
    for i in range(20):
        mb.box((2.0, 0.42, 0.4), loc=(5.4, 15.2 + i * 0.42, 0.6 - i * 0.4), m="ConcreteDark")
    mb.box((5, 4, 0.5), loc=(4.3, -17, 0.55), m="Concrete")
    K.add("rail_station", mb, big=4)
    mb = MB()
    mat("TrainBody", "#e9e4d8", rough=0.4, metal=0.3)
    mat("TrainStripe", "#2f9c95", rough=0.4, metal=0.3)
    mb.box((2.9, 15.0, 2.7), loc=(0, 0, 1.95), m="TrainBody", bevel=0.25)
    mb.box((2.92, 15.02, 0.5), loc=(0, 0, 1.1), m="TrainStripe")
    mb.box((2.94, 13.0, 0.9), loc=(0, 0, 2.35), m="Glass")
    mb.box((2.3, 15.04, 0.9), loc=(0, 0, 2.4), m="Glass")
    for y in (-4.5, 0.0, 4.5):
        mb.box((2.96, 1.5, 2.0), loc=(0, y, 1.75), m="TrainStripe")
        mb.box((2.98, 1.2, 1.0), loc=(0, y, 2.2), m="Glass")
    mb.box((2.2, 14, 0.5), loc=(0, 0, 0.5), m="Under")
    for y in (-5, 5):
        mb.box((2.4, 2.6, 0.5), loc=(0, y, 0.35), m="DarkSteel")
    for s in (1, -1):
        mb.box((0.5, 0.06, 0.2), loc=(s * 0.9, 7.52, 1.3), m="LightHead")
        mb.box((0.5, 0.06, 0.2), loc=(s * 0.9, -7.52, 1.3), m="LightTail")
    K.add("train_car", mb, smooth=40, big=3)
    # shipping container
    mb = MB()
    mb.box((2.44, 6.06, 2.6), loc=(0, 0, 1.3), m="CorrTint")
    for i in range(12):
        for s in (1, -1):
            mb.box((0.05, 0.25, 2.3), loc=(s * 1.23, -2.75 + i * 0.5, 1.3), m="CorrTint")
    mb.box((2.3, 0.05, 2.4), loc=(0, -3.04, 1.3), m="MetalPanel")
    for x in (-0.6, -0.2, 0.2, 0.6):
        mb.cyl(0.02, 2.3, loc=(x, -3.08, 1.3), segs=4, m="Steel")
    K.add("prop_container", mb, big=2)
    # billboard
    mb = MB()
    mb.box((10, 0.3, 4.5), loc=(0, 0, 9.5), m="FrameDark")
    mb.box((9.6, 0.06, 4.1), loc=(0, -0.17, 9.5), m="SignTint")
    for x in (-3, 3):
        mb.cyl(0.25, 7.3, loc=(x, 0.2, 3.65), segs=6, m="DarkSteel")
    for x in (-3.5, 0, 3.5):
        mb.box((0.3, 0.9, 0.2), loc=(x, -0.9, 7.1), m="FrameDark")
        mb.box((0.25, 0.2, 0.1), loc=(x, -1.3, 7.2), m="LampGlow")
    K.add("prop_billboard", mb, big=2)
    # stunt ramp: curved kicker (gentle entry so bumpers clear it, ~21 degree exit)
    mb = MB()
    RN = 7
    prof = [(-6.0 + 9.0 * i / RN, 2.2 * (i / RN) ** 1.6) for i in range(RN + 1)]
    for i in range(RN):
        (y0, h0), (y1, h1) = prof[i], prof[i + 1]
        mb.poly([(-2.2, y0, h0), (2.2, y0, h0), (2.2, y1, h1), (-2.2, y1, h1)], "Wood" if i % 2 == 0 else "WoodDark", outward=(0, 0, 1))
        for s in (1, -1):
            mb.poly([(s * 2.2, y0, h0), (s * 2.2, y1, h1), (s * 2.2, y1, 0), (s * 2.2, y0, 0)], "PaintYellow", outward=(s, 0, 0))
            # kerb rails along both edges
            mb.poly([(s * 2.2, y0, h0), (s * 2.2, y1, h1), (s * 2.2, y1, h1 + 0.16), (s * 2.2, y0, h0 + 0.16)], "PaintRed", outward=(s, 0, 0))
            mb.poly([(s * 2.05, y0, h0), (s * 2.05, y1, h1), (s * 2.05, y1, h1 + 0.16), (s * 2.05, y0, h0 + 0.16)], "PaintRed", outward=(-s, 0, 0))
            mb.poly([(s * 2.05, y0, h0 + 0.16), (s * 2.2, y0, h0 + 0.16), (s * 2.2, y1, h1 + 0.16), (s * 2.05, y1, h1 + 0.16)], "PaintRed", outward=(0, 0, 1))
    mb.poly([(-2.2, 3.0, 0), (2.2, 3.0, 0), (2.2, 3.0, 2.2), (-2.2, 3.0, 2.2)], "DarkSteel", outward=(0, 1, 0))
    # scaffold legs + chevron board at the lip
    for x in (-2.0, 0.0, 2.0):
        mb.box((0.12, 0.12, 2.1), loc=(x, 2.9, 1.05), m="DarkSteel")
        mb.box((0.10, 0.10, 1.2), loc=(x, 1.0, 0.6), m="DarkSteel")
    mb.box((4.4, 0.06, 0.5), loc=(0, 3.04, 1.75), m="PaintYellow")
    for k in range(4):
        mb.box((0.38, 0.07, 0.5), loc=(-1.65 + k * 1.1, 3.045, 1.75), m="FrameDark")
    K.add("prop_stunt_ramp", mb, big=2)
    # rooftop helipad disc
    mb = MB()
    mb.cyl(6.0, 0.12, loc=(0, 0, 0.06), segs=20, m="Tarmac")
    mb.lathe([(0.125, 5.2), (0.125, 5.6)], axis='Z', segs=20, m="HelipadPaint")
    mb.box((2.6, 0.55, 0.02), loc=(0, 0, 0.13), m="HelipadPaint")
    mb.box((0.55, 3.0, 0.02), loc=(-1.1, 0, 0.13), m="HelipadPaint")
    mb.box((0.55, 3.0, 0.02), loc=(1.1, 0, 0.13), m="HelipadPaint")
    K.add("prop_helipad", mb, big=2)
    # sunken wreck (two hull pieces)
    mb = MB()
    S = [(7, 0.1, 2.5), (5, 1.6, 0.6), (0, 2.4, 0.0), (-5, 2.2, 0.2)]
    secs = []
    for y, hw_, zk in S:
        secs.append([Vector((0, y, zk)), Vector((hw_ * 0.8, y, zk + 1.0)), Vector((hw_, y, 3.2)), Vector((hw_ - 0.2, y, 3.2)), Vector((hw_ * 0.7, y, zk + 1.2)),
                     Vector((-hw_ * 0.7, y, zk + 1.2)), Vector((-hw_ + 0.2, y, 3.2)), Vector((-hw_, y, 3.2)), Vector((-hw_ * 0.8, y, zk + 1.0))])
    mb.loft(secs, "Rust", cap_start=False, cap_end=False)
    mb.box((3.0, 3.5, 2.4), loc=(0, -2.5, 4.2), m="Rust", rot=(0.0, 0.12, 0.0))
    mb.cyl(0.4, 3.0, loc=(0, -3.0, 6.2), segs=6, m="RockDark", rot=(0.3, 0, 0))
    mb.tube((0, 3.5, 3.2), (0.8, 3.0, 8.5), 0.12, "Rust", segs=5)
    K.add("prop_wreck", mb, big=3)


def build_all():
    mat("WallTint", "#f2efe8", rough=0.9)
    mat("BrickTint", "#c98a72", rough=0.92)
    mat("CorrTint", "#dfe6ea", rough=0.55, metal=0.3)
    mat("AwningTint", "#f4f1ea", rough=0.85)
    mat("SignTint", "#f4f1ea", rough=0.5, emit="#f4f1ea", estr=0.3)
    mat("ShopGlass", "#5f8fa8", rough=0.08, metal=0.2)
    K = Kit("kit_facade", "Buildings", (80, 20, 0), spacing=5.0, per_row=8)
    facade_modules(K)
    K2 = Kit("kit_landmarks", "Buildings", (80, 80, 0), spacing=22.0, per_row=8)
    landmarks(K2)
    return [stats(K.root), stats(K2.root), str(K.names), str(K2.names)]


def export_all():
    return [export("kit_facade", "world/kit_facade.glb", center=False), export("kit_landmarks", "world/kit_landmarks.glb", center=False)]
