"""buildings_generic - the generic Halcyon Bay buildings, assembled with building_kit.

Run inside Blender through MCP (see building_kit docstring for the import header):

    import buildings_generic as B; importlib.reload(B)
    B.run(["office_a"])            # quiet: (re)build + audit + measure + preview, ONE summary line per asset
    B.run(B.ORDER, preview=False, export=True)     # rebuild and export everything
    B.build("office_a")            # verbose variant: (re)build one asset at its slot, audit + measure it
    B.build_all()                  # every building
    B.export_all()                 # GLBs -> gta/generated/models/buildings/<id>.glb
    B.write_manifest()             # manifest_generic.json from live measurements
    B.drive_test()                 # parking_a: walk the up-route, report steps / slope / headroom
    B.group_preview("downtown")    # ensemble contact sheet (temporarily lines the assets up)

Full reference: docs/BUILDING_KIT.md. Godot side: gta/code/editor/bld_check_generic.gd verifies every
exported GLB against the manifest.

Every function below builds ONE building facing +Y with its origin at the footprint centre on the
ground. Slots: region "buildings", indices 0..29 (see SLOT).
"""
import math
import os

import bpy
from mathutils import Vector

import gta_bl as G
import building_kit as K

GH = K.GROUND_H
FH = K.FLOOR_H

ORDER = [
    "office_a", "office_b", "office_c", "office_d", "office_e", "office_f",
    "apartment_a", "apartment_b", "apartment_c", "apartment_d",
    "house_a", "house_b", "house_c", "house_d", "house_e", "house_f",
    "storefront_a", "storefront_b", "storefront_c", "storefront_d", "storefront_e", "storefront_f",
    "warehouse_a", "warehouse_b", "warehouse_c", "warehouse_d",
    "parking_a", "garage_row", "shed_a", "kiosk_a",
]
SLOT = dict((n, i) for i, n in enumerate(ORDER))
BUILDERS = {}


def building(fn):
    BUILDERS[fn.__name__] = fn
    return fn


# ================================================================================================
# OFFICES (downtown)
# ================================================================================================
@building
def office_a():
    """Classic 12-storey commercial block: stone base with shops, punched paired windows, attic + cornice."""
    b = K.Builder("office_a", SLOT["office_a"], dict(
        wall="Cream", wall2="Peach", base="WarmGrey", trim="White", roof="RoofGrey", awning="Teal",
        awning2="White", sign="Navy", neon="NeonCyan", door="Navy"))
    m = b.mass(-11.7, 11.7, -9.7, 9.7)
    for f in m.all:
        f.margins(0.9)
    W = K.win(2.5, 1.8, sill=0.8, bars=(2, 1))
    W1 = K.win(2.5, 2.1, sill=0.65, bars=(2, 1), frame="trim", sill_bar="trim")
    WA = K.win(2.5, 1.7, sill=0.8, bars=(2, 1), frame="trim")
    SH = dict(head=3.1, margin=0.45)
    lobby = K.door(2.6, 2.7, glass=0.9, double=True, transom=0.4, frame="trim", recess=0.45)
    m.front.row(0, GH, [K.shop(door="center", **SH), K.shop(door="none", **SH), lobby,
                        K.shop(door="none", **SH), K.shop(door="center", **SH)], "base")
    side0 = [K.shop(door="none", **SH), K.win(2.5, 2.2, sill=0.9, bars=(2, 1)), K.win(2.5, 2.2, sill=0.9, bars=(2, 1)),
             K.shop(door="none", **SH)]
    m.right.row(0, GH, side0, "base")
    m.left.row(0, GH, side0, "base")
    m.back.row(0, GH, [K.rollup(3.2, 3.2), K.door(1.1, 2.2), None, K.louvre(1.6, 0.8, 2.2), K.door(1.1, 2.2)], "base")
    lv = [(FH, W1, "base")] + [(FH, W)] * 9 + [(FH, WA, "wall2")]
    for f in m.all:
        f.stack(GH, lv)
        f.pilasters(0.0, GH + FH - 0.3, w=0.7, proud=0.2, mat="trim")
    ztop = GH + 11 * FH
    b.belt(m.pts, GH - 0.3, 0.3, 0.1, "base")
    b.cornice(m.pts, GH + FH - 0.3, 0.5, 0.32)
    b.belt(m.pts, GH + 10 * FH - 0.28, 0.28, 0.1)
    b.cornice(m.pts, ztop - 0.15, 0.75, 0.3)
    b.flat_roof(m.pts, ztop, parapet=1.2, wall="wall2")
    fr = m.front
    spans = [(fr.m0 + (fr.w - 2 * fr.m0) * i / 5.0, fr.m0 + (fr.w - 2 * fr.m0) * (i + 1) / 5.0) for i in range(5)]
    for i in (0, 1, 3, 4):
        fr.awning(spans[i][0] + 0.45, spans[i][1] - 0.45, 3.62, depth=1.25, drop=0.5, stripes=6)
    c = fr.w / 2.0
    fr.box(c - 2.3, c + 2.3, 3.05, 3.65, 0.0, 1.3, "sign", "detail", "k")
    fr.text("BAY TRUST", c, 3.35, 0.085, "neon", 1.32)
    b.stair_box(-3.0, 1.0, -2.5, 1.5, ztop, wall="wall2")
    b.water_tank(6.5, -4.5, ztop)
    b.ac_unit(-7.5, 4.0, ztop)
    b.ac_unit(-7.5, 1.5, ztop)
    b.ac_unit(5.0, 5.0, ztop, turn=True)
    b.antenna(-8.5, -6.5, ztop, 7.0)
    b.entrance = (0.0, 9.7)
    b.floors = 12
    return b.finish("office", ["downtown", "tall", "shops"])


@building
def office_b():
    """Glass curtain-wall tower (16 floors) on a two-storey white podium."""
    b = K.Builder("office_b", SLOT["office_b"], dict(
        wall="White", base="Concrete", trim="White", accent="Sky", roof="RoofGrey", sign="Charcoal",
        neon="NeonCyan", door="Charcoal", awning="Navy", awning2="White"))
    pod = b.mass(-13.9, 13.9, -11.9, 11.9)
    SH = dict(head=3.2, margin=0.35, frame="metal")
    lobby = K.door(3.0, 2.8, glass=0.92, double=True, transom=0.4, frame="metal", recess=0.5, mat="metal")
    pod.front.row(0, GH, [K.shop(door="none", **SH), K.shop(door="center", **SH), K.shop(door="none", **SH), lobby,
                          K.shop(door="none", **SH), K.shop(door="center", **SH), K.shop(door="none", **SH)], "wall")
    for f in (pod.left, pod.right):
        f.row(0, GH, [K.shop(door="none", **SH), K.shop(door="none", **SH), None, K.shop(door="none", **SH),
                      K.shop(door="none", **SH), None], "wall")
    pod.back.row(0, GH, [K.rollup(3.4, 3.3), K.rollup(3.4, 3.3), None, K.door(1.1, 2.2), K.louvre(1.8, 0.9, 2.2), None,
                         K.door(1.1, 2.2)], "wall")
    for f in pod.all:
        n = f.n(2.0)
        f.row(GH, 4.0, [K.win(f.w - 2.4, 2.0, sill=1.0, bars=(n, 1), panes=(n, 1), bar_mat="metal", reveal="trim")], "wall")
    b.belt(pod.pts, GH - 0.15, 0.4, 0.15, "base")
    b.flat_roof(pod.pts, 8.0, parapet=0.9, roof="Sidewalk")
    fr = pod.front
    fr.canopy(fr.w / 2 - 3.2, fr.w / 2 + 3.2, 3.25, 1.6, 0.3, "metal", rods=True)
    fr.text("AZURE PLAZA", fr.w / 2, 3.4, 0.07, "neon", 1.62)
    tw = b.mass(-11.0, 11.0, -9.0, 9.0, 8.0)
    nfl = 16
    for f in tw.all:
        f.margins(0.55)
        f.curtain(0.0, nfl, FH, bay=2.1, spandrel=1.05, spandrel_mat="accent", mull="trim")
    zt = 8.0 + nfl * FH
    b.belt(tw.pts, zt - 0.1, 0.5, 0.18, "trim")
    b.flat_roof(tw.pts, zt + 0.4, parapet=0.8, cap="trim")
    zr = zt + 0.4
    cr = b.mass(-7.0, 7.0, -5.0, 5.0, zr)
    for f in cr.all:
        f.row(0.0, 3.4, [K.louvre(f.w - 2.0, 1.6, 1.2, mat="SteelDark")], "accent")
    b.box(-7.3, 7.3, -5.3, 5.3, zr + 3.4, zr + 3.7, "trim")
    b.roof_sign("AZURE", 0.0, 4.6, zr + 3.7, px=0.5, color="neon", lift=0.5)
    b.roof_sign("AZURE", 0.0, 4.4, zr + 3.7, px=0.5, color="neon", lift=0.5, facing="back")     # readable from both sides
    b.antenna(5.0, -3.0, zr + 3.7, 8.0)
    b.dish(-5.0, -3.0, zr + 3.7, 0.8)
    for x in (-9.0, 9.0):
        b.ac_unit(x, 6.0, zr, 1.8, 1.2, 1.0, turn=True)
        b.ac_unit(x, -6.0, zr, 1.8, 1.2, 1.0, turn=True)
    for x in (-11.5, 11.5):
        b.planter(x - 1.2, x + 1.2, 9.6, 10.8, 8.0, 0.6)
    b.entrance = (0.0, 11.9)
    b.floors = 18
    return b.finish("office", ["downtown", "tall", "glass"])


@building
def office_c():
    """Stepped art-deco tower (three tiers, 20 floors) with pilaster piers, crown and spire."""
    b = K.Builder("office_c", SLOT["office_c"], dict(
        wall="Peach", wall2="Coral", base="Terracotta", trim="Cream", roof="RoofGrey", accent="Teal",
        sign="Navy", neon="NeonOrange", door="WoodDark", awning="Teal", awning2="Cream"))
    W = K.win(2.3, 1.9, sill=0.75)
    SH = dict(head=3.1, margin=0.5)
    t1 = b.mass(-17.6, 17.6, -13.6, 13.6)
    grand = K.door(3.0, 3.0, glass=0.92, double=True, transom=0.4, frame="trim", recess=0.6)
    t1.front.row(0, GH, [K.shop(door="center", **SH), K.shop(door="none", **SH), K.shop(door="center", **SH), None, grand,
                         None, K.shop(door="center", **SH), K.shop(door="none", **SH), K.shop(door="center", **SH)], "base")
    for f in (t1.left, t1.right):
        f.row(0, GH, [K.shop(door="none", **SH), K.shop(door="center", **SH), None, K.win(2.3, 2.2, sill=0.9), None,
                      K.shop(door="center", **SH), K.shop(door="none", **SH)], "base")
    t1.back.row(0, GH, [K.rollup(3.2, 3.3), K.rollup(3.2, 3.3), None, K.door(1.1, 2.2), K.louvre(1.8, 0.9, 2.2), None,
                        K.door(1.1, 2.2), None, K.louvre(1.8, 0.9, 2.2)], "base")
    for f in t1.all:
        f.stack(GH, [(FH, W)] * 5)
        f.pilasters(0.0, 20.0, w=0.62, proud=0.26, mat="trim")
    b.belt(t1.pts, GH - 0.35, 0.35, 0.12, "trim")
    b.belt(t1.pts, 20.0 - 0.3, 0.3, 0.3, "trim")
    b.flat_roof(t1.pts, 20.0, parapet=1.0, wall="wall2")
    t2 = b.mass(-13.6, 13.6, -9.6, 9.6, 20.0)
    for f in t2.all:
        f.stack(0.0, [(FH, W)] * 9)
        f.pilasters(0.0, 28.8, w=0.62, proud=0.26, mat="trim")
    b.belt(t2.pts, 48.8 - 0.3, 0.3, 0.3, "trim")
    b.flat_roof(t2.pts, 48.8, parapet=1.0, wall="wall2")
    t3 = b.mass(-9.6, 9.6, -5.6, 5.6, 48.8)
    for f in t3.all:
        f.stack(0.0, [(FH, W)] * 5)
        f.pilasters(0.0, 16.0, w=0.62, proud=0.26, mat="trim")
    zt = 64.8
    b.belt(t3.pts, zt - 0.3, 0.3, 0.3, "trim")
    b.flat_roof(t3.pts, zt, parapet=1.0, wall="wall2")
    b.box(-6.6, 6.6, -3.6, 3.6, zt, zt + 2.6, "wall2", "body", "-z")
    b.ring(K.rect_pts(-6.6, 6.6, -3.6, 3.6), [(0.0, zt + 2.3), (0.15, zt + 2.3), (0.15, zt + 2.6), (0.0, zt + 2.6)], "trim")
    b.taper((-5.6, 5.6, -2.9, 2.9), (-1.6, 1.6, -0.9, 0.9), zt + 2.6, zt + 6.0, "accent")
    b.cyl(0.0, 0.0, zt + 6.0, zt + 11.0, 0.22, "Steel", "body", 6, r2=0.05, caps="none")
    b.box(-0.12, 0.12, -0.12, 0.12, zt + 11.0, zt + 11.3, "FireRed", "detail", "-z")
    for f in (K.Face(b, (6.6, 3.6), (-6.6, 3.6), zt), K.Face(b, (-6.6, -3.6), (6.6, -3.6), zt)):
        for u in (2.0, 4.4, 6.6, 8.8, 11.2):
            f.rect(u - 0.06, u + 0.06, 0.3, 2.2, "neon", 0.02, "detail")
    fr = t1.front
    c = fr.w / 2
    fr.box(c - 3.4, c + 3.4, 3.15, 3.95, 0.0, 1.5, "sign", "detail", "k")
    fr.text("CORAL TOWER", c, 3.55, 0.1, "neon", 1.52)
    sp = [(fr.w * i / 9.0, fr.w * (i + 1) / 9.0) for i in range(9)]
    for i in (0, 1, 2, 6, 7, 8):
        fr.awning(sp[i][0] + 0.5, sp[i][1] - 0.5, 3.6, depth=1.2, drop=0.5, stripes=6)
    b.ac_unit(-14.5, 11.0, 20.0)
    b.ac_unit(14.5, 11.0, 20.0)
    b.ac_unit(-14.5, -11.0, 20.0, turn=True)
    b.water_tank(14.5, -11.0, 20.0, 1.3, 2.2)
    b.ac_unit(-11.0, 7.4, 48.8)
    b.ac_unit(11.0, -7.4, 48.8)
    b.entrance = (0.0, 13.6)
    b.floors = 20
    return b.finish("office", ["downtown", "tall", "stepped", "landmark_scale"])


@building
def office_d():
    """Slim glass tower with a cut corner (entrance on the chamfer) and a sloped coral crown."""
    b = K.Builder("office_d", SLOT["office_d"], dict(
        wall="Cream", base="Charcoal", trim="Cream", accent="Coral", roof="Coral", sign="Charcoal",
        neon="NeonMagenta", door="Charcoal", metal="Charcoal"))
    x0, x1, y0, y1, c = -9.8, 9.8, -9.8, 9.8, 5.0
    pts = [(x0, y0), (x1, y0), (x1, y1 - c), (x1 - c, y1), (x0, y1)]
    back, right, cham, front, left = b.faces(pts)
    SH = dict(head=3.2, margin=0.3, frame="trim")
    back.row(0, GH, [K.rollup(3.0, 3.2), K.door(1.1, 2.2), None, K.louvre(1.8, 0.9, 2.2), None], "base")
    right.row(0, GH, [K.shop(door="none", **SH), K.shop(door="none", **SH), K.shop(door="none", **SH)], "base")
    cham.row(0, GH, [K.door(3.2, 2.9, glass=0.92, double=True, transom=0.45, frame="trim", recess=0.5)], "base")
    front.row(0, GH, [K.shop(door="none", **SH), K.shop(door="center", **SH), K.shop(door="none", **SH)], "base")
    left.row(0, GH, [K.shop(door="none", **SH), None, K.shop(door="none", **SH), None, K.shop(door="none", **SH)], "base")
    nfl = 14
    for f in (back, right, front, left):
        f.margins(0.45)
        f.z0 = 0.0
        f.curtain(GH, nfl, FH, bay=2.35, spandrel=1.0, spandrel_mat="accent", mull="trim")
    cham.margins(0.3)
    cham.curtain(GH, nfl, FH, bay=3.3, spandrel=1.0, spandrel_mat=K.WINDOW_MAT, mull="trim", hbar=True)
    zt = GH + nfl * FH
    b.belt(pts, GH - 0.3, 0.3, 0.12, "trim")
    b.belt(pts, zt - 0.05, 0.45, 0.2, "trim")
    z0c = zt + 0.4
    slope = 0.2

    def zc(p):
        return z0c + 0.9 + (y1 - p[1]) * slope

    n = len(pts)
    for i in range(n):
        p = pts[i]
        q = pts[(i + 1) % n]
        b.poly(((p[0], p[1], z0c), (q[0], q[1], z0c), (q[0], q[1], zc(q)), (p[0], p[1], zc(p))), "wall")
    b.poly([(p[0], p[1], zc(p)) for p in pts], "roof")

    # crown dressing (seen from aircraft / neighbouring towers): standing seams, glazed atrium strips,
    # cream coping on the crown edge and a lift / plant penthouse near the high (rear) edge
    def zr(x, y):
        return z0c + 0.9 + (y1 - y) * slope

    for i in range(8):
        x = x0 + (x1 - x0) * (i + 0.5) / 8.0
        ye = y1 if x <= x1 - c else y1 - (x - (x1 - c))
        b.seam((x, y0 + 0.2, zr(x, y0 + 0.2)), (x, ye - 0.2, zr(x, ye - 0.2)), w=0.12, h=0.09, mat="Terracotta")
    for xc in (-7.35, -4.9, -2.45, 0.0, 2.45):
        for (e, g, mm) in ((0.04, 0.14, "trim"), (0.08, 0.0, K.WINDOW_MAT)):
            xa, xb, ya, yb = xc - 0.85 - g, xc + 0.85 + g, 1.6 - g, 6.6 + g
            b.poly_dir([(xa, ya, zr(xa, ya) + e), (xb, ya, zr(xb, ya) + e), (xb, yb, zr(xb, yb) + e), (xa, yb, zr(xa, yb) + e)],
                       (0, 0, 1), mm)
    for i in range(n):
        p = pts[i]
        q = pts[(i + 1) % n]
        b.seam((p[0], p[1], zc(p)), (q[0], q[1], zc(q)), w=0.34, h=0.14, mat="trim")
    px0, px1, py0, py1 = -3.4, 2.6, -8.2, -4.2
    za, zb = zr(0, py1) - 0.2, zr(0, py0) + 1.7
    b.box(px0, px1, py0, py1, za, zb, "wall", "body", "-z +z")
    b.box(px0 - 0.18, px1 + 0.18, py0 - 0.18, py1 + 0.18, zb, zb + 0.2, "trim")
    pf = K.Face(b, (px1, py1), (px0, py1), za)
    pf.zigzag_h(0.7, pf.w - 0.7, 0.75, zb - za - 0.45, 0.012, 0.22, 0.07, "SteelDark")
    pr = K.Face(b, (px1, py0), (px1, py1), za)
    d0 = zr(0, py0 + 1.3) - za
    pr.box(1.2, 2.4, d0, d0 + 2.15, 0.0, 0.04, "trim", "body", "k b")
    pr.rect(1.3, 2.3, d0, d0 + 2.05, "door", 0.045)
    b.dish(1.4, -7.2, zb + 0.2, 0.7)
    front.neon_line(0.4, front.w - 0.4, z0c + 0.35, 0.1, "neon", 0.02)
    cham.neon_line(0.3, cham.w - 0.3, z0c + 0.35, 0.1, "neon", 0.02)
    right.neon_line(0.4, right.w - 0.4, z0c + 0.35, 0.1, "neon", 0.02)
    cham.canopy(cham.w / 2 - 2.4, cham.w / 2 + 2.4, 3.3, 1.4, 0.45, "trim")       # 1.4: stays inside the footprint box
    cham.text("PELICAN", cham.w / 2, 3.52, 0.075, "neon", 1.42)
    b.antenna(-7.5, -8.0, zc((0, -8.0)), 6.0)
    b.solid(x0, x1, y0, y1, 0.0, zt + 4.5)
    b.roof_z = zt + 1.3
    b.entrance = (x1 - c / 2, y1 - c / 2)
    b.floors = 15
    return b.finish("office", ["downtown", "tall", "glass", "corner"])


@building
def office_e():
    """Wide 7-storey brick newspaper block: shops at street level, ribbon windows, rooftop sign."""
    b = K.Builder("office_e", SLOT["office_e"], dict(
        wall="Brick", base="Cream", trim="Cream", roof="RoofGrey", awning="Mustard", awning2="Cream",
        sign="Navy", neon="NeonYellow", door="Navy", metal="Charcoal"))
    m = b.mass(-15.8, 15.8, -11.8, 11.8)
    SH = dict(head=3.1, margin=0.4, frame="metal")
    m.front.row(0, GH, [K.shop(door="center", **SH), K.shop(door="none", **SH), K.shop(door="center", **SH),
                        K.door(2.4, 2.7, glass=0.9, double=True, transom=0.4, frame="metal", recess=0.45),
                        K.door(2.4, 2.7, glass=0.9, double=True, transom=0.4, frame="metal", recess=0.45),
                        K.shop(door="center", **SH), K.shop(door="none", **SH), K.shop(door="center", **SH)], "base")
    for f in (m.left, m.right):
        f.row(0, GH, [K.shop(door="none", **SH), None, K.shop(door="none", **SH), K.shop(door="none", **SH), None,
                      K.shop(door="none", **SH)], "base")
    m.back.row(0, GH, [K.rollup(3.2, 3.3), K.rollup(3.2, 3.3), K.rollup(3.2, 3.3), None, K.door(1.1, 2.2),
                       K.louvre(1.8, 0.9, 2.2), None, K.door(1.1, 2.2)], "base")
    for f in m.all:
        n = f.n(2.2)
        rib = K.win(f.w - 3.0, 1.75, sill=0.85, bars=(n, 1), panes=(n, 1), frame="trim", frame_w=0.22, proud=0.08, bar_mat="trim")
        f.stack(GH, [(FH, [rib])] * 6)
    zt = GH + 6 * FH
    b.belt(m.pts, GH - 0.3, 0.45, 0.15, "trim")
    b.cornice(m.pts, zt - 0.1, 0.6, 0.3)
    b.flat_roof(m.pts, zt, parapet=1.1)
    fr = m.front
    sp = [(fr.w * i / 8.0, fr.w * (i + 1) / 8.0) for i in range(8)]
    for i in (0, 1, 2, 5, 6, 7):
        fr.awning(sp[i][0] + 0.4, sp[i][1] - 0.4, 3.6, depth=1.3, drop=0.5, stripes=0, mats=("awning",) if i % 2 else ("Navy",))
    fr.canopy(sp[3][0] + 0.3, sp[4][1] - 0.3, 3.2, 1.6, 0.35, "sign")
    fr.text("THE HERALD", fr.w / 2, 3.38, 0.06, "neon", 1.62)
    pent = b.mass(-9.0, 9.0, -7.0, 3.0, zt)
    for f in pent.all:
        f.row(0.0, 3.0, [K.win(1.4, 1.0, sill=1.3)] * f.n(4.5), "base")
    b.flat_roof(pent.pts, zt + 3.0, parapet=0.3, cap="trim", wall="base")
    b.roof_sign("THE HERALD", 0.0, 8.5, zt, px=0.42, color="neon", lift=1.6)
    b.roof_sign("THE HERALD", 0.0, 8.3, zt, px=0.42, color="neon", lift=1.6, facing="back")
    b.water_tank(-12.5, -8.0, zt)
    b.ac_unit(12.0, -8.0, zt, 1.8, 1.2, 1.0)
    b.ac_unit(12.0, -5.5, zt, 1.8, 1.2, 1.0)
    b.ac_unit(-12.5, 2.0, zt, turn=True)
    b.antenna(6.0, -4.0, zt + 3.0, 6.0)
    b.entrance = (0.0, 11.8)
    b.floors = 7
    return b.finish("office", ["downtown", "midrise", "shops", "brick"])


@building
def office_f():
    """Concrete-fin slab tower (18 floors) with a taller mustard service core and a vertical sign."""
    b = K.Builder("office_f", SLOT["office_f"], dict(
        wall="WarmGrey", base="ConcreteDark", trim="White", accent="Charcoal", wall2="Mustard", roof="RoofGrey",
        neon="NeonYellow", sign="Charcoal", door="Charcoal", metal="Charcoal"))
    xs = 5.8
    slab = b.mass(-11.8, xs, -11.8, 11.8)
    core = b.mass(xs, 11.8, -6.0, 6.0)
    nfl = 17
    zt = GH + nfl * FH
    SH = dict(head=3.3, margin=0.3, frame="metal")
    lobby = K.door(3.0, 2.9, glass=0.92, double=True, transom=0.4, frame="metal", recess=0.5, mat="metal")
    slab.front.row(0, GH, [K.shop(door="none", **SH), lobby, K.shop(door="none", **SH), K.shop(door="none", **SH)], "base")
    slab.back.row(0, GH, [K.rollup(3.2, 3.3), K.door(1.1, 2.2), None, K.louvre(1.8, 0.9, 2.2)], "base")
    slab.left.row(0, GH, [K.shop(door="none", **SH)] * 6, "base")
    for f in (slab.front, slab.back, slab.left):
        f.margins(0.5)
        f.curtain(GH, nfl, FH, bay=2.1 if f is not slab.left else 2.85, spandrel=0.95, spandrel_mat="accent", mull="trim",
                  mull_w=0.2, mull_proud=0.5, hbar=False)
    r = slab.right
    for (ua, ub) in ((0.0, 5.8), (17.8, 23.6)):
        s = r.sub(ua, ub)
        s.stack(0.0, [(GH, [K.win(2.2, 2.2, sill=0.9)], "base")] + [(FH, [K.win(1.6, 1.7, sill=0.85)])] * nfl)
    b.belt(slab.pts, GH - 0.3, 0.3, 0.14, "trim")
    b.flat_roof(slab.pts, zt, parapet=1.3, cap="trim")
    zc = zt + 2 * FH
    CW = K.win(1.3, 2.3, sill=0.45, reveal="Charcoal")
    core.front.stack(0.0, [(GH, [K.door(1.3, 2.3, frame="trim")], "base")] + [(FH, [None, CW], "wall2")] * (nfl + 2))
    core.back.stack(0.0, [(GH, [K.door(1.3, 2.3)], "base")] + [(FH, [CW, None], "wall2")] * (nfl + 2))
    core.right.stack(0.0, [(GH, [K.louvre(1.8, 0.9, 2.2), K.rollup(3.0, 3.2), K.louvre(1.8, 0.9, 2.2)], "base")]
                     + [(FH, [K.win(1.0, 1.0, sill=1.2), None, K.win(1.0, 1.0, sill=1.2)], "wall2")] * (nfl + 2))
    core.left.z0 = 0.0
    core.left.rect(0.0, core.left.w, zt, zc, "wall2")
    core.left.top = zc
    b.flat_roof(core.pts, zc, parapet=0.9, wall="wall2", cap="trim")
    cf = core.front
    px = 0.42
    for i, ch in enumerate("TALMA"):
        cf.text(ch, 1.6, zc - 3.0 - i * 6 * px, px, "neon", 0.04)
    cf.box(0.55, 2.65, zc - 3.0 - 4 * 6 * px - 3.5 * px, zc - 3.0 + 3.5 * px, 0.0, 0.03, "sign", "detail", "k")
    b.antenna(8.8, 0.0, zc, 9.0)
    b.dish(8.8, -3.5, zc, 0.7)
    for y in (-7.0, -2.0, 3.0, 8.0):
        b.ac_unit(-7.0, y, zt, 2.0, 1.4, 1.1)
    b.box(-1.5, 3.5, -3.0, 3.0, zt, zt + 2.4, "wall", "body", "-z")
    b.box(-1.7, 3.7, -3.2, 3.2, zt + 2.4, zt + 2.6, "trim")
    b.entrance = (-0.8, 11.8)
    b.floors = 18
    return b.finish("office", ["downtown", "tall", "concrete"])


# ================================================================================================
# APARTMENTS
# ================================================================================================
@building
def apartment_a():
    """6-storey coral block: cream stair tower, white colour-block balconies over a ground-floor plinth."""
    b = K.Builder("apartment_a", SLOT["apartment_a"], dict(
        wall="Coral", wall2="Cream", base="WarmGrey", trim="White", roof="RoofGrey", door="Teal",
        awning="Teal", awning2="White", metal="Charcoal"))
    X, YB, YF, YE = 11.9, -7.9, 6.8, 7.9
    nfl = 5
    zt = GH + nfl * FH
    cw = 3.5
    m = b.mass(-X, X, YB, YF)
    W = K.win(1.5, 1.5, sill=0.95, frame="trim", sill_bar="trim")
    FD = K.win(1.7, 2.25, sill=0.05, bars=(2, 1), frame="trim")
    G0 = K.win(2.0, 1.8, sill=1.0, bars=(2, 1), frame="trim", sill_bar="trim")
    G0P = K.win(2.0, 1.8, sill=1.0, bars=(2, 1), frame="trim", planter=True)
    for f in (m.left, m.right):
        f.stack(0.0, [(GH, [G0, None, G0, None], "base")] + [(FH, W)] * nfl)
    m.back.stack(0.0, [(GH, [K.rollup(3.0, 2.8, mat="White"), G0, K.door(1.1, 2.2), G0, G0, K.louvre(1.4, 0.7, 2.4)], "base")]
                 + [(FH, W)] * nfl)
    fr = m.front
    for s in (fr.sub(0.0, X - cw), fr.sub(X + cw, 2 * X)):
        s.stack(GH, [(FH, [FD, FD])] * nfl)
        for k in range(nfl):
            s.balcony(0.06, s.w - 0.06, GH + k * FH, depth=1.1, rail_h=1.05, style="solid", mat="trim")
    eh = GH - 0.14
    for sx in (-1, 1):
        xa, xb = (cw, X) if sx > 0 else (-X, -cw)
        e = b.mass(xa, xb, YF, YE)
        e.h = eh
        e.front.row(0.0, eh, [G0P, G0P], "base")
        o = e.right if sx > 0 else e.left
        o.rect(0.0, o.w, 0.0, eh, "base")
    zc = zt + 2.6
    c = b.mass(-cw, cw, YF, YE)
    CW = K.win(2.0, 1.7, sill=1.5, bars=(2, 2), frame="trim")
    c.front.stack(0.0, [(GH, [K.door(1.6, 2.4, glass=0.5, double=True, frame="trim", transom=0.4)], "wall2")]
                  + [(FH, [CW], "wall2")] * nfl + [(2.6, None, "wall2")])
    for f in (c.left, c.right):
        f.rect(0.0, f.w, 0.0, zc, "wall2")
    b.box(-cw, cw, 3.2, YF, zt, zc, "wall2", "body", "-z +y")
    b.box(-cw - 0.15, cw + 0.15, 3.05, YE + 0.15, zc, zc + 0.2, "trim")
    c.front.awning(1.6, 5.4, 3.35, depth=1.1, drop=0.4, stripes=5)
    c.front.text("SANDPIPER", cw, 3.72, 0.085, "door", 0.03)
    b.belt(m.pts, GH - 0.1, 0.2, 0.06, "trim", edges=[0, 1, 3])
    b.flat_roof(m.pts, zt, parapet=0.8)
    b.water_tank(-7.5, -3.0, zt)
    b.ac_unit(6.0, -4.0, zt)
    b.ac_unit(8.5, -4.0, zt)
    b.ac_unit(7.0, 2.0, zt, turn=True)
    b.antenna(-9.5, 3.5, zt, 4.5)
    b.vent(2.0, -5.0, zt)
    b.entrance = (0.0, YE)
    b.floors = 6
    return b.finish("apartment", ["residential", "midrise", "balconies"])


@building
def apartment_b():
    """9-storey white slab block: loggias between fin walls with checkerboard teal / mustard balcony panels."""
    b = K.Builder("apartment_b", SLOT["apartment_b"], dict(
        wall="White", base="Concrete", trim="White", accent="Teal", roof="RoofGrey", door="Navy",
        metal="Charcoal", sign="Navy"))
    X, YB, YF, YE = 13.9, -9.9, 8.8, 9.9
    nfl = 8
    zt = GH + nfl * FH
    m = b.mass(-X, X, YB, YF)
    FD = K.win(1.7, 2.3, sill=0.05, bars=(2, 1))
    WW = K.win(2.2, 1.5, sill=0.95)
    W = K.win(1.9, 1.5, sill=0.95, sill_bar="Concrete")
    SH = dict(head=3.0, margin=0.5, frame="metal")
    fr = m.front
    fr.row(0, GH, [K.shop(door="none", **SH), K.shop(door="none", **SH), K.shop(door="none", **SH),
                   K.door(2.2, 2.6, glass=0.9, double=True, frame="metal", transom=0.3, mat="metal"),
                   K.shop(door="none", **SH), K.shop(door="none", **SH), K.shop(door="none", **SH),
                   K.shop(door="none", **SH)], "base")
    fr.stack(GH, [(FH, [FD, WW, WW, FD, FD, WW, WW, FD])] * nfl)
    fw = 0.35
    fins = [(-X, -X + fw), (-6.95 - fw / 2, -6.95 + fw / 2), (-fw / 2, fw / 2), (6.95 - fw / 2, 6.95 + fw / 2), (X - fw, X)]
    for (xa, xb) in fins:
        b.box(xa, xb, YF, YE, -K.SKIRT, zt + 1.4, "trim", "body", "-y -z")
    cols = ("Teal", "Mustard")
    for i in range(4):
        xa = fins[i][1]
        xb = fins[i + 1][0]
        for k in range(nfl):
            fr.balcony(X - xb, X - xa, GH + k * FH, depth=1.1, rail_h=1.05, style="solid", mat=cols[(i + k) % 2], sides=False)
    fr.text("MARLIN COURT", 3.475 * 3.5, 3.45, 0.07, "sign", 0.03)
    for f in (m.left, m.right):
        f.stack(0.0, [(GH, [None, K.win(1.9, 1.6, sill=1.2), None, K.win(1.9, 1.6, sill=1.2), None], "base")]
                + [(FH, [W, None, None, None, W])] * nfl)
        f.box(f.w / 2 - 2.6, f.w / 2 + 2.6, GH + 0.5, zt - 0.5, 0.0, 0.07, "accent", "body", "k")
    m.back.stack(0.0, [(GH, [K.rollup(3.0, 3.0), K.win(1.9, 1.6, sill=1.2), K.door(1.1, 2.2), None,
                             K.louvre(1.6, 0.8, 2.3), K.win(1.9, 1.6, sill=1.2), K.door(1.1, 2.2)], "base")] + [(FH, W)] * nfl)
    b.belt(m.pts, GH - 0.12, 0.24, 0.07, "trim", edges=[0, 1, 3])
    b.flat_roof(m.pts, zt, parapet=1.0)
    b.stair_box(-3.0, 3.0, -4.0, 1.0, zt, 3.0)
    for x in (-10.5, -6.5, 6.5, 10.5):
        b.solar(x - 1.6, x + 1.6, -1.5, 1.5, zt)
    b.ac_unit(-9.0, -6.5, zt)
    b.ac_unit(9.0, -6.5, zt)
    b.ac_unit(9.0, 5.0, zt, turn=True)
    b.antenna(0.0, -1.5, zt + 3.2, 5.0)
    b.entrance = (X - 3.475 * 3.5, YE)
    b.solid(-X, X, YF, YE, 0.0, zt)
    b.floors = 9
    return b.finish("apartment", ["residential", "tall", "balconies", "modern"])


@building
def apartment_c():
    """5-storey brick walk-up: raised ground floor with a stoop, cream lintels + cornice, front fire escape."""
    b = K.Builder("apartment_c", SLOT["apartment_c"], dict(
        wall="Brick", base="ConcreteDark", trim="Cream", roof="RoofGrey", door="Teal", metal="Charcoal"))
    X, YB, YF = 9.7, -7.7, 6.7
    m = b.mass(-X, X, YB, YF)
    W = K.win(1.3, 1.75, sill=0.75, bars=(1, 2), sill_bar="trim", lintel="trim")
    WS = K.win(1.3, 1.65, sill=0.6, bars=(1, 2), sill_bar="trim", lintel="trim")
    BW = K.louvre(1.0, 0.45, 0.3)
    D = K.door(1.5, 2.3, glass=0.35, double=True, frame="trim", transom=0.35)
    m.front.stack(0.0, [(1.0, [BW, BW, None, BW, BW], "base"), (3.0, [WS, WS, D, WS, WS])] + [(FH, W)] * 4)
    for f in (m.left, m.right):
        f.stack(0.0, [(1.0, None, "base"), (3.0, [WS, None, None, WS])] + [(FH, [W, None, None, W])] * 4)
    m.back.stack(0.0, [(1.0, [BW, None, BW, None, BW], "base"), (3.0, [WS, WS, WS, WS, WS])] + [(FH, W)] * 4)
    zt = GH + 4 * FH
    fr = m.front
    c = fr.w / 2
    fr.steps(c - 1.15, c + 1.15, 1.0, n=4, tread=0.28)
    for sg in (-1, 1):
        fr.box(c + sg * 1.15, c + sg * 1.5, -K.SKIRT, 1.3, 0.0, 1.14, "concrete", "body", "k b")
    fr.canopy(c - 1.3, c + 1.3, 3.95, 0.8, 0.16, "trim", part="body")
    fr.fire_escape(12.0, 19.0, [GH + i * FH for i in range(4)], depth=1.0, ladder_to=2.7)
    b.belt(m.pts, GH - 0.22, 0.26, 0.08)
    b.cornice(m.pts, zt - 0.45, 0.85, 0.45)
    b.flat_roof(m.pts, zt, parapet=0.9)
    lf = m.left
    lf.text("LUCKY", lf.w / 2, 13.2, 0.3, "trim", 0.02)
    lf.text("CLAM", lf.w / 2, 11.2, 0.3, "trim", 0.02)
    lf.text("CHOWDER HOUSE", lf.w / 2, 9.75, 0.11, "trim", 0.02)
    b.water_tank(4.5, -3.5, zt, 1.25, 2.1)
    b.stair_box(-6.5, -3.5, -1.5, 2.5, zt)
    b.chimney(-8.6, -5.5, zt, zt + 2.4, 0.8, 1.0)
    b.chimney(8.6, 4.0, zt, zt + 2.4, 0.8, 1.0)
    b.vent(1.0, 3.0, zt)
    b.vent(2.2, 3.0, zt)
    b.solid(-1.6, 1.6, YF, YF + 1.15, 0.0, 1.0)
    b.entrance = (0.0, YF + 1.15)
    b.floors = 5
    return b.finish("apartment", ["residential", "midrise", "brick", "fire_escape"])


@building
def apartment_d():
    """7-storey mint mansion block: white bay-window stacks, railed balconies, penthouse under a red hip roof."""
    b = K.Builder("apartment_d", SLOT["apartment_d"], dict(
        wall="Mint", wall2="White", base="Sand", trim="White", roof="RoofRed", door="WoodDark", metal="Charcoal",
        sign="WoodDark"))
    X, YB, YF, YE = 12.9, -8.9, 7.8, 8.9
    nfl = 5
    zt = GH + nfl * FH
    m = b.mass(-X, X, YB, YF)
    W = K.win(1.5, 1.6, sill=0.9, frame="trim", sill_bar="trim")
    W0 = K.win(1.6, 1.8, sill=1.0, frame="trim", sill_bar="trim")
    FD = K.win(1.6, 2.3, sill=0.05, bars=(2, 1), frame="trim")
    BWN = K.win(2.8, 1.9, sill=0.7, bars=(3, 1), frame="trim", sill_bar="trim")
    for f in (m.left, m.right):
        f.stack(0.0, [(GH, [W0, None, W0, None], "base")] + [(FH, W)] * nfl)
    WB = K.win(1.5, 1.6, sill=0.9, frame="trim")
    m.back.stack(0.0, [(GH, [W0, K.door(1.1, 2.2), W0, W0, K.rollup(3.0, 2.8, mat="White"), W0], "base")] + [(FH, WB)] * nfl)
    fr = m.front
    for (ua, ub) in ((0.0, 3.4), (22.4, 25.8)):
        s = fr.sub(ua, ub)
        s.stack(0.0, [(GH, [K.win(1.4, 1.8, sill=1.0, frame="trim", sill_bar="trim")], "base")]
                + [(FH, [K.win(1.3, 1.6, sill=0.9, frame="trim", sill_bar="trim")])] * nfl)
    cs = fr.sub(7.4, 18.4)
    cs.stack(0.0, [(GH, [W0, K.door(1.8, 2.5, glass=0.55, double=True, frame="trim", transom=0.4), W0], "base")]
             + [(FH, [FD, K.win(1.2, 1.4, sill=1.0, frame="trim"), FD])] * nfl)
    for k in range(nfl):
        cs.balcony(0.6, cs.w - 0.6, GH + k * FH, depth=1.0, rail_h=1.0, style="rail")
    cs.canopy(cs.w / 2 - 1.8, cs.w / 2 + 1.8, 3.2, 1.0, 0.18, "trim", part="body")
    cs.text("SEAGLASS", cs.w / 2, 3.62, 0.08, "sign", 0.03)
    for (xa, xb) in ((-9.5, -5.5), (5.5, 9.5)):
        bay = b.mass(xa, xb, YF, YE)
        bay.front.stack(0.0, [(GH, [K.win(2.8, 2.0, sill=1.0, bars=(3, 1), frame="trim", sill_bar="trim")], "wall2")]
                        + [(FH, [BWN], "wall2")] * nfl)
        for f in (bay.left, bay.right):
            f.rect(0.0, f.w, 0.0, zt, "wall2")
        b.box(xa - 0.12, xb + 0.12, YF, YE + 0.12, zt, zt + 0.25, "trim", "body", "-y")
    b.belt(m.pts, GH - 0.12, 0.24, 0.07, "trim", edges=[0, 1, 3])
    b.flat_roof(m.pts, zt, parapet=1.0, roof="Sidewalk")
    p = b.mass(-10.9, 10.9, -6.9, 5.8, zt)
    for f in p.all:
        f.row(0.0, FH, [K.win(1.6, 1.6, sill=0.85, frame="trim")] * f.n(4.4), "wall2")
    b.hip_roof(-10.9, 10.9, -6.9, 5.8, zt + FH, 2.5, over=0.55, mat="roof")
    b.chimney(-6.5, -2.5, zt + FH + 0.9, zt + FH + 3.3, 0.8, 0.8, "wall2", "Concrete", "Terracotta")
    b.chimney(6.5, 1.5, zt + FH + 0.9, zt + FH + 3.3, 0.8, 0.8, "wall2", "Concrete", "Terracotta")
    b.planter(-12.2, -11.4, 0.0, 5.0, zt, 0.5)
    b.planter(11.4, 12.2, 0.0, 5.0, zt, 0.5)
    b.entrance = (0.0, YF)
    b.floors = 7
    return b.finish("apartment", ["residential", "midrise", "balconies", "pitched_roof"])


# ================================================================================================
# HOUSES (suburban)
# ================================================================================================
F0 = 0.35          # house floor level above ground
HS = 2.75          # house storey height


def _hw(w=1.3, h=1.25, **kw):
    """Standard framed house window."""
    d = dict(sill=0.95, frame="trim", sill_bar="trim", bars=(2, 2))
    d.update(kw)
    return K.win(w, h, **d)


def _bay_window(f, u0, u1, v0, v1, depth=0.5, mat="trim", roof="roof"):
    """Box bay window with glass on three sides and a little lean-to roof."""
    f.box(u0, u1, v0, v1, 0.0, depth, mat, "body", "k")
    m = 0.12
    f.pane(u0 + m, u1 - m, v0 + 0.3, v1 - m, depth + 0.012, 3, 1)
    for sf in (f.side_face(u1 + 0.012, 0.0, depth, "+u"), f.side_face(u0 - 0.012, 0.0, depth, "-u")):
        sf.pane(0.08, depth - 0.08, v0 + 0.3, v1 - m, 0.0)
    f.prism([(0.0, v1 + 0.4), (depth + 0.14, v1), (depth + 0.14, v1 - 0.07), (0.0, v1 - 0.07)], u0 - 0.14, u1 + 0.14, roof,
            closed=False)
    f.prism([(0.0, v0 - 0.3), (depth, v0), (0.0, v0)], u0, u1, mat, closed=False)


def _wall_window(f, uc, vc, w=0.8, h=0.8, mat="trim"):
    """Small framed window applied on a wall without cutting it (gables, dormers)."""
    f.box(uc - w / 2 - 0.09, uc + w / 2 + 0.09, vc - h / 2 - 0.09, vc + h / 2 + 0.09, 0.0, 0.05, mat, "body", "k")
    f.pane(uc - w / 2, uc + w / 2, vc - h / 2, vc + h / 2, 0.06)


@building
def house_a():
    """Cream ranch house: red gable roof, front-gabled garage wing, porch and an outside chimney."""
    b = K.Builder("house_a", SLOT["house_a"], dict(
        wall="Cream", wall2="Peach", base="Concrete", trim="White", roof="RoofRed", door="Teal", metal="Charcoal"))
    zt = F0 + HS
    HW = _hw(shutters="door")
    HP = _hw()
    m = b.mass(-5.5, 1.6, -4.4, 2.6)
    m.front.stack(0.0, [(F0, None, "base"), (HS, [HW, K.door(1.0, 2.1, glass=0.3, frame="trim"), HW])])
    m.left.stack(0.0, [(F0, None, "base"), (HS, [None, HP])])
    m.back.stack(0.0, [(F0, None, "base"), (HS, [HP, K.door(0.9, 2.1, glass=0.5, frame="trim"), HP])])
    m.right.sub(0.0, 1.0).stack(0.0, [(F0, None, "base"), (HS, None)])
    b.gable_roof(-5.5, 1.6, -4.4, 2.6, zt, 1.9, axis="x", over=0.45, gover=0.35, gable="wall2")
    _wall_window(m.left, 3.5, zt + 0.75, 0.7, 0.7)
    g = b.mass(1.6, 5.5, -3.4, 4.3)
    g.front.stack(0.0, [(zt, [K.rollup(2.7, 2.25, mat="White", slat=0.56, lights=True, frame="trim")])])
    g.right.stack(0.0, [(zt, [None, K.win(1.2, 0.9, sill=1.5, frame="trim"), None])])
    g.back.stack(0.0, [(zt, None)])
    g.left.sub(0.0, 1.7).stack(0.0, [(zt, None)])
    b.gable_roof(1.6, 5.5, -3.4, 4.3, zt, 1.45, axis="y", over=0.4, gover=0.35, gable="wall2")
    _wall_window(g.front, g.front.w / 2, zt + 0.55, 0.9, 0.5)
    end = m.front.porch(0.05, 4.7, depth=1.5, floor=F0, post_h=2.15, posts=3, drop=0.22, step_u=3.55, step_w=1.3)
    b.chimney(-5.55, 0.85, -K.SKIRT, zt + 2.6, 0.8, 1.1, "Brick")
    b.solid(-3.1, 1.55, 2.6, 4.1, 0.0, F0)
    b.entrance = (-1.95, 2.6 + end)
    b.floors = 1
    return b.finish("house", ["residential", "garage", "porch"])


@building
def house_b():
    """Two-storey sky-blue family house: navy hip roof, bay window, portico, lean-to garage."""
    b = K.Builder("house_b", SLOT["house_b"], dict(
        wall="Sky", wall2="White", base="Concrete", trim="White", roof="Navy", door="Coral", metal="Charcoal"))
    z1 = F0 + HS
    z2 = z1 + HS
    HW = _hw()
    m = b.mass(-5.0, 1.8, -4.5, 3.4)
    m.front.stack(0.0, [(F0, None, "base"), (HS, [None, K.door(1.0, 2.1, glass=0.3, frame="trim")]), (HS, [HW, HW])])
    m.left.stack(0.0, [(F0, None, "base"), (HS, [HW, HW]), (HS, [HW, HW])])
    m.back.stack(0.0, [(F0, None, "base"), (HS, [HW, K.door(0.9, 2.1, glass=0.5, frame="trim")]), (HS, [HW, HW])])
    r = m.right
    r.sub(0.0, 0.9).stack(0.0, [(F0, None, "base"), (HS, None)])
    r.sub(7.3, 7.9).stack(0.0, [(F0, None, "base"), (HS, None)])
    r.stack(z1, [(HS, [HW, HW])])
    r.top = z2
    b.belt(m.pts, z1 - 0.1, 0.2, 0.06, "trim", edges=[0, 2, 3])
    b.hip_roof(-5.0, 1.8, -4.5, 3.4, z2, 1.75, over=0.5, mat="roof")
    _bay_window(m.front, 0.6, 3.0, F0 + 0.7, F0 + 2.35, 0.55)
    g = b.mass(1.8, 5.2, -3.6, 2.8)
    zg = 2.75
    g.front.stack(0.0, [(zg, [K.rollup(2.6, 2.15, mat="White", slat=0.54, frame="trim")])])
    g.right.stack(0.0, [(zg, [K.win(1.1, 0.8, sill=1.5, frame="trim"), None])])
    g.back.stack(0.0, [(zg, [K.door(0.9, 2.05)])])
    b.shed_roof(1.8, 5.2, -3.6, 2.8, zg, zg + 0.75, high="left", over=0.3, fill="wall")
    end = m.front.porch(3.7, 6.3, depth=1.2, floor=F0, post_h=2.15, posts=2, drop=0.22, rail=False, step_w=1.2)
    b.chimney(-3.0, -2.4, z2 + 0.4, z2 + 2.6, 0.7, 0.7, "wall2", "Concrete", "Charcoal")
    b.solid(-4.5, -1.9, 3.4, 4.6, 0.0, F0)
    b.entrance = (1.8 - 5.0, 3.4 + end)
    b.floors = 2
    return b.finish("house", ["residential", "two_storey", "garage"])


@building
def house_c():
    """Peach L-shaped ranch: cross-gable terracotta roof, corner porch, integral garage."""
    b = K.Builder("house_c", SLOT["house_c"], dict(
        wall="Peach", wall2="Cream", base="Concrete", trim="White", roof="Terracotta", door="Navy", metal="Charcoal"))
    zt = F0 + HS
    HW = _hw()
    A = b.mass(-6.4, 6.4, -5.4, 0.6)
    A.back.stack(0.0, [(F0, None, "base"), (HS, [HW, HW, K.door(0.9, 2.1, glass=0.5, frame="trim"), HW])])
    A.left.stack(0.0, [(F0, None, "base"), (HS, [HW])])
    A.right.stack(0.0, [(F0, None, "base"), (HS, [HW])])
    af = A.front.sub(0.0, 7.3)
    af.stack(0.0, [(F0, None, "base")])
    af.row(F0, HS, [None, K.door(1.0, 2.1, glass=0.3, frame="trim"), HW], widths=[3.5, 1.5, 2.3])
    gd = K.Face(b, af.plan(0.25), af.plan(3.25), 0.0)
    gd.box(0.0, 3.0, 0.0, 2.35, 0.0, 0.06, "trim", "body", "k")
    gd.zigzag_h(0.12, 2.88, 0.1, 2.25, 0.065, 0.5, 0.04, "White")
    Bw = b.mass(-6.4, -0.9, 0.6, 5.1)
    Bw.front.stack(0.0, [(F0, None, "base"), (HS, [_hw(w=2.6, h=1.5, sill=0.8, bars=(3, 2), shutters="door")])])
    Bw.left.stack(0.0, [(F0, None, "base"), (HS, [HW])])
    Bw.right.stack(0.0, [(F0, None, "base"), (HS, [_hw(w=1.0)])])
    b.gable_roof(-6.4, 6.4, -5.4, 0.6, zt, 1.75, axis="x", over=0.45, gover=0.35, gable="wall2")
    b.gable_roof(-6.4, -0.9, -1.9, 5.1, zt, 1.55, axis="y", over=0.45, gover=0.35, gable="wall2", ends=(False, True))
    _wall_window(Bw.front, Bw.front.w / 2, zt + 0.6, 0.8, 0.6)
    end = af.porch(3.4, 7.2, depth=1.6, floor=F0, post_h=2.15, posts=3, drop=0.22, step_u=4.25, step_w=1.3)
    b.chimney(6.45, -4.2, -K.SKIRT, zt + 2.3, 0.75, 1.1, "Brick")
    b.solid(-0.8, 3.0, 0.6, 2.2, 0.0, F0)
    b.entrance = (6.4 - 4.25, 0.6 + end)
    b.floors = 1
    return b.finish("house", ["residential", "ranch", "garage", "porch"])


@building
def house_d():
    """Modern two-box house: white render, timber upper storey, charcoal slab roofs, carport, solar."""
    b = K.Builder("house_d", SLOT["house_d"], dict(
        wall="White", wall2="Wood", base="ConcreteDark", trim="Charcoal", roof="Charcoal", door="Mustard",
        metal="Charcoal"))
    z1 = 3.1
    z2 = 5.9
    A = b.mass(-5.4, 0.4, -4.6, 3.0)
    BIG = K.win(1.3, 2.3, sill=0.25, reveal="trim")
    A.front.stack(0.0, [(z1, [BIG, K.door(1.1, 2.3, mat="door", frame="trim")]),
                        (z2 - z1, [K.win(4.2, 1.3, sill=0.85, bars=(4, 1), panes=(4, 1), reveal="trim", bar_mat="trim")], "wall2")])
    A.left.stack(0.0, [(z1, [K.win(1.0, 1.0, sill=1.4, reveal="trim"), BIG]), (z2 - z1, [K.win(2.2, 1.0, sill=1.1, reveal="trim")] * 2, "wall2")])
    A.back.stack(0.0, [(z1, [K.win(2.6, 2.2, sill=0.3, bars=(2, 1), reveal="trim"), K.door(0.9, 2.2)]),
                       (z2 - z1, [K.win(1.6, 1.2, sill=0.9, reveal="trim")] * 2, "wall2")])
    A.right.stack(z1 + 0.3, [(z2 - z1 - 0.3, [K.win(1.6, 2.05, sill=0.05, bars=(2, 1), reveal="trim", bar_mat="trim"), None], "wall2")])
    A.right.sub(5.4, 7.6).stack(0.0, [(z1 + 0.3, None)])
    A.right.top = z2
    Bx = b.mass(0.4, 5.4, -4.6, 0.8)
    zb = 3.1
    Bx.front.stack(0.0, [(zb, [K.win(4.0, 2.3, sill=0.25, bars=(3, 1), panes=(3, 1), reveal="trim", bar_mat="trim")])])
    Bx.right.stack(0.0, [(zb, [K.win(2.4, 1.0, sill=1.5, reveal="trim"), None])])
    Bx.back.stack(0.0, [(zb, [K.win(1.8, 1.0, sill=1.5, reveal="trim")])])
    b.slab_roof(A.pts, z2, 0.3, 0.5, "trim", "roof")
    b.slab_roof(Bx.pts, zb, 0.3, 0.5, "trim", "roof")
    b.box(1.0, 5.6, 0.8, 4.6, 2.55, 2.75, "trim")
    for x in (1.3, 5.3):
        b.box(x - 0.08, x + 0.08, 4.2, 4.36, -K.SKIRT, 2.55, "trim", "body", "-z +z")
    A.front.canopy(3.3, 5.7, 2.55, 1.2, 0.16, "trim", part="body")
    b.solar(-4.6, -1.0, -3.6, -1.2, z2 + 0.3)
    b.cyl(-0.6, 1.8, z2 + 0.3, z2 + 1.5, 0.14, "Steel", "body", 8)
    b.planter(-5.2, -2.6, 3.1, 3.9, 0.0, 0.45)
    b.skylight(-4.5, -2.3, 0.4, 2.0, z2 + 0.3, 0.45, 0.18)
    # board-formed concrete chimney slab piercing the roof edge (breaks up the two-box silhouette)
    b.box(-5.8, -5.4, -1.45, -0.15, -K.SKIRT, z2 + 1.5, "Concrete", "body", "-z")
    b.box(-5.86, -5.34, -1.51, -0.09, z2 + 1.5, z2 + 1.62, "trim")
    # roof terrace on the low wing: timber deck, white balustrade walls, planter, table + parasol
    zt_ = zb + 0.3
    b.poly(((0.75, -4.75, zt_ + 0.02), (5.55, -4.75, zt_ + 0.02), (5.55, 0.95, zt_ + 0.02), (0.75, 0.95, zt_ + 0.02)), "Wood")
    for (xa, xb, ya, yb) in ((0.6, 5.75, 0.95, 1.1), (5.6, 5.75, -4.9, 0.95), (0.6, 5.6, -4.9, -4.75)):
        b.box(xa, xb, ya, yb, zt_, zt_ + 0.95, "wall", "body", "-z")
    b.planter(1.0, 5.3, -4.6, -4.0, zt_, 0.4)
    b.cyl(3.6, -1.6, zt_, zt_ + 0.72, 0.05, "metal", "detail", 6, caps="none")
    b.cyl(3.6, -1.6, zt_ + 0.72, zt_ + 0.77, 0.6, "White", "detail", 8, caps="both")
    b.cyl(3.6, -1.6, zt_ + 0.77, zt_ + 2.15, 0.035, "metal", "detail", 4, caps="none")
    b.cyl(3.6, -1.6, zt_ + 2.0, zt_ + 2.5, 1.35, "Coral", "detail", 8, r2=0.0, caps="bottom")
    for (sx, sy) in ((2.6, -1.6), (4.6, -1.6)):
        b.box(sx - 0.24, sx + 0.24, sy - 0.24, sy + 0.24, zt_ + 0.02, zt_ + 0.46, "Mustard", "detail", "-z")
    b.solid(1.0, 5.6, 0.8, 4.6, 2.55, 2.75)
    b.entrance = (0.4 - 4.35, 3.0)
    b.floors = 2
    return b.finish("house", ["residential", "modern", "carport"])


@building
def house_e():
    """Tall mustard gable-front house: two storeys + attic, full-width porch, steep charcoal roof."""
    b = K.Builder("house_e", SLOT["house_e"], dict(
        wall="Mustard", wall2="Cream", base="Concrete", trim="White", roof="Charcoal", door="Navy", metal="Charcoal"))
    z1 = F0 + HS
    z2 = z1 + HS
    HW = _hw(w=1.15, h=1.35)
    m = b.mass(-3.8, 3.8, -4.4, 2.5)
    m.front.stack(0.0, [(F0, None, "base"), (HS, [HW, K.door(1.0, 2.1, glass=0.3, frame="trim"), HW]), (HS, [HW, HW])])
    for f in (m.left, m.right):
        f.stack(0.0, [(F0, None, "base"), (HS, [HW, HW]), (HS, [HW, HW])])
    m.back.stack(0.0, [(F0, None, "base"), (HS, [HW, K.door(0.9, 2.1, glass=0.5, frame="trim")]), (HS, [HW, HW])])
    b.belt(m.pts, z1 - 0.1, 0.2, 0.06, "trim")
    b.gable_roof(-3.8, 3.8, -4.4, 2.5, z2, 2.6, axis="y", over=0.45, gover=0.4, gable="wall2")
    _wall_window(m.front, m.front.w / 2, z2 + 0.95, 0.9, 1.0)
    _wall_window(m.back, m.back.w / 2, z2 + 0.95, 0.9, 1.0)
    end = m.front.porch(0.0, m.front.w, depth=1.6, floor=F0, post_h=2.2, posts=4, drop=0.25, step_w=1.4)
    b.chimney(3.85, -1.5, -K.SKIRT, z2 + 3.2, 0.75, 1.0, "Brick")
    b.box(-2.6, -0.2, -5.1, -4.4, -K.SKIRT, 2.45, "wall2", "body", "-z +y +z")
    b.shed_roof(-2.6, -0.2, -5.1, -4.4, 2.45, 2.85, high="front", over=0.15, th=0.12, fill="wall2")
    b.solid(-3.8, 3.8, 2.5, 4.1, 0.0, F0)
    b.entrance = (0.0, 2.5 + end)
    b.floors = 2
    return b.finish("house", ["residential", "two_storey", "porch"])


@building
def house_f():
    """Lavender bungalow: grey hip roof, wrap-around porch, side garage with its own gable."""
    b = K.Builder("house_f", SLOT["house_f"], dict(
        wall="Lavender", wall2="White", base="Concrete", trim="White", roof="RoofGrey", door="Coral", metal="Charcoal"))
    zt = F0 + HS
    HW = _hw()
    m = b.mass(-2.4, 4.6, -3.4, 2.8)
    m.front.stack(0.0, [(F0, None, "base"), (HS, [HW, K.door(1.0, 2.1, glass=0.3, frame="trim"), HW])])
    m.right.stack(0.0, [(F0, None, "base"), (HS, [HW, HW])])
    m.back.stack(0.0, [(F0, None, "base"), (HS, [HW, HW])])
    m.left.sub(0.0, 0.8).stack(0.0, [(F0, None, "base"), (HS, None)])
    b.hip_roof(-2.4, 4.6, -3.4, 2.8, zt, 1.6, over=0.5, mat="roof")
    end = m.front.porch(0.0, m.front.w, depth=1.6, floor=F0, post_h=2.15, posts=4, drop=0.2, step_w=1.4)
    m.right.porch(0.0, m.right.w, depth=1.4, floor=F0, post_h=2.15, posts=3, drop=0.2, step_w=0.0, rail=True)
    g = b.mass(-6.2, -2.4, -4.6, 2.0)
    zg = 2.8
    g.front.stack(0.0, [(zg, [K.rollup(2.7, 2.2, mat="White", slat=0.55, lights=True, frame="trim")])])
    g.left.stack(0.0, [(zg, [K.win(1.1, 0.9, sill=1.4, frame="trim"), None, K.win(1.1, 0.9, sill=1.4, frame="trim")])])
    g.back.stack(0.0, [(zg, [K.door(0.9, 2.05)])])
    g.right.sub(0.0, 1.2).stack(0.0, [(zg, None)])
    b.gable_roof(-6.2, -2.4, -4.6, 2.0, zg, 1.35, axis="y", over=0.35, gover=0.3, gable="wall2")
    _wall_window(g.front, g.front.w / 2, zg + 0.5, 0.8, 0.45)
    b.chimney(2.6, -1.2, zt + 0.3, zt + 2.4, 0.7, 0.7, "Brick")
    b.solid(-2.4, 6.0, 2.8, 4.4, 0.0, F0)
    b.solid(4.6, 6.0, -3.4, 2.8, 0.0, F0)
    b.entrance = (1.1, 2.8 + end)
    b.floors = 1
    return b.finish("house", ["residential", "bungalow", "garage", "porch"])


# ================================================================================================
# STOREFRONTS (midtown / neighbourhood shops with flats above)
# ================================================================================================
@building
def storefront_a():
    """Peach two-storey terrace: noodle bar, laundry and record shop under striped awnings, flats above."""
    b = K.Builder("storefront_a", SLOT["storefront_a"], dict(
        wall="Peach", wall2="Cream", base="Terracotta", trim="White", roof="RoofGrey", door="Navy",
        awning="Teal", awning2="White", sign="Navy", neon="NeonMagenta", metal="Charcoal"))
    X, Y = 9.9, 5.9
    zt = GH + FH
    m = b.mass(-X, X, -Y, Y)
    SH = dict(head=3.0, margin=0.3)
    W = K.win(1.3, 1.55, sill=0.9, bars=(2, 2), frame="trim", sill_bar="trim", shutters="door")
    WS = K.win(1.3, 1.55, sill=0.9, bars=(2, 2), frame="trim", sill_bar="trim")
    fr = m.front
    sp = fr.row(0.0, GH, [K.shop(door="center", **SH), K.door(1.0, 2.25, glass=0.3, frame="trim", transom=0.35),
                          K.shop(door="left", **SH), K.shop(door="right", **SH)], "base", widths=[6.0, 1.8, 6.0, 6.0])
    fr.row(GH, FH, [W] * 5)
    fr.dress_shop(sp[0], "KOI NOODLE", "NeonOrange", ("Awning", "White"))
    fr.dress_shop(sp[2], "MOON LAUNDRY", "NeonCyan", ("Teal", "White"))
    fr.dress_shop(sp[3], "VINYL VAULT", "NeonMagenta", ("Navy",), stripes=0)
    fr.canopy(sp[1][0] + 0.1, sp[1][1] - 0.1, 3.0, 0.7, 0.12, "trim")
    SW = K.win(1.2, 1.0, sill=2.0, frame="trim")
    m.right.stack(0.0, [(GH, [K.door(1.0, 2.1, frame="trim"), SW, None], "base"), (FH, [WS, None, WS])])
    m.right.wall_light(m.right.w / 6.0, 2.65, part="body", arm=0.12)
    m.right.downpipe(m.right.w - 0.45, 0.0, zt - 0.4, mat="metal")
    m.left.stack(0.0, [(GH, [None, SW, None], "base"), (FH, [WS, None, WS])])
    m.left.poster(0.8, 2.2, 0.9, 2.9, ("Teal", "Cream"))
    m.left.poster(2.4, 3.8, 0.9, 2.9, ("Mustard", "Navy"))
    m.left.downpipe(m.left.w - 0.45, 0.0, zt - 0.4, mat="metal")
    m.back.stack(0.0, [(GH, [K.door(1.0, 2.1), K.louvre(1.2, 0.7, 2.4), K.rollup(2.6, 2.7), K.door(1.0, 2.1),
                             K.louvre(1.2, 0.7, 2.4)], "base"), (FH, [WS] * 5)])
    b.belt(m.pts, GH - 0.08, 0.2, 0.07)
    b.cornice(m.pts, zt - 0.35, 0.5, 0.28)
    top = b.flat_roof(m.pts, zt, parapet=0.8)
    c = fr.w / 2
    fr.box(c - 3.4, c + 3.4, top, top + 0.75, -0.3, 0.0, "wall", "body", "b")
    fr.box(c - 3.55, c + 3.55, top + 0.75, top + 0.9, -0.36, 0.06, "trim", "body", "")
    fr.text("1958", c, top + 0.38, 0.07, "trim", 0.02, "body")
    b.ac_unit(-6.5, -2.5, zt)
    b.ac_unit(-4.0, -2.5, zt)
    b.ac_unit(1.5, 1.5, zt, turn=True)
    b.vent(5.5, -3.0, zt)
    b.vent(6.6, -3.0, zt)
    b.stair_box(4.0, 7.0, -1.0, 2.2, zt, 2.4, door="back")
    b.dish(-8.4, 3.6, zt)
    b.entrance = (X - 3.0, Y)
    b.floors = 2
    return b.finish("storefront", ["midtown", "shops", "flats"])


@building
def storefront_b():
    """Narrow three-storey gable-front bookshop: teal shopfront, cream flats, red roof, vertical blade sign."""
    b = K.Builder("storefront_b", SLOT["storefront_b"], dict(
        wall="Cream", wall2="Cream", base="Teal", trim="White", roof="RoofRed", door="WoodDark",
        awning="Mustard", awning2="White", sign="WoodDark", neon="NeonGreen", metal="Charcoal"))
    X, Y0, Y1 = 5.5, -5.75, 5.45
    zt = GH + 2 * FH
    m = b.mass(-X, X, Y0, Y1)
    W = K.win(1.25, 1.6, sill=0.85, bars=(2, 2), frame="trim", sill_bar="trim")
    WP = K.win(1.25, 1.6, sill=0.85, bars=(2, 2), frame="trim", planter=True)
    FD = K.win(1.5, 2.25, sill=0.05, bars=(2, 1), frame="trim", balcony=dict(depth=0.7, w=2.6, style="rail"))
    fr = m.front
    sp = fr.row(0.0, GH, [K.shop(door="right", head=3.0, margin=0.35, riser=0.6),
                          K.door(1.0, 2.25, glass=0.3, frame="trim", transom=0.35)], "base", widths=[8.0, 3.0])
    fr.row(GH, FH, [WP, FD, WP])
    fr.row(GH + FH, FH, [W, W, W])
    for f in (m.left, m.right):
        f.stack(0.0, [(GH, [None, K.win(1.2, 1.2, sill=1.6, frame="trim"), None], "base"), (FH, [W, None, W]), (FH, [W, None, W])])
    m.back.stack(0.0, [(GH, [K.door(1.0, 2.1), K.win(1.2, 1.2, sill=1.6, frame="trim"), K.louvre(1.0, 0.6, 2.5)], "base"),
                       (FH, [W] * 3), (FH, [W] * 3)])
    b.belt(m.pts, GH - 0.08, 0.2, 0.07)
    b.belt(m.pts, zt - 0.22, 0.22, 0.07, edges=[0, 2])
    b.gable_roof(-X, X, Y0, Y1, zt, 3.3, axis="y", over=0.4, gover=0.35, gable="wall2")
    fr.applied_window(fr.w / 2, zt + 1.2, 0.9, 1.1)
    m.back.applied_window(m.back.w / 2, zt + 1.2, 0.9, 1.1)
    fr.dress_shop(sp[0], "PALM BOOKS", "NeonGreen", ("Mustard", "White"))
    fr.canopy(sp[1][0] + 0.6, sp[1][1] - 0.6, 3.0, 0.7, 0.12, "trim")
    fr.blade_sign(fr.w - 0.5, 4.5, 9.4, depth=0.85, text="BOOKS", color="NeonGreen")
    b.chimney(3.3, -2.5, zt + 0.9, zt + 3.9, 0.8, 0.8, "Brick")
    b.entrance = (X - (sp[0][1] - 0.35 - 0.63), Y1)
    b.floors = 3
    return b.finish("storefront", ["midtown", "residential", "shops", "flats", "pitched_roof"])


@building
def storefront_c():
    """Single-storey supermarket: white box, red fascia band all round, glazed front, central sign pylon."""
    b = K.Builder("storefront_c", SLOT["storefront_c"], dict(
        wall="White", wall2="Cream", base="WarmGrey", trim="White", roof="RoofGrey", door="Charcoal",
        accent="Awning", sign="Awning", neon="NeonYellow", metal="Charcoal", awning="Awning", awning2="White"))
    X, Y = 11.8, 6.8
    H = 5.4
    m = b.mass(-X, X, -Y, Y)
    fr = m.front
    SH = dict(head=3.3, margin=0.25, frame="metal", riser=0.45, pane=1.6)
    ent = K.door(2.8, 2.6, glass=0.92, double=True, frame="metal", mat="metal", transom=0.6, recess=0.5)
    sp = fr.row(0.0, H, [K.shop(door="none", **SH), K.shop(door="none", **SH), ent, K.shop(door="none", **SH),
                         K.shop(door="none", **SH)], "wall", widths=[5.0, 5.0, 3.6, 5.0, 5.0])
    HW = K.win(2.6, 0.9, sill=2.5, bars=(3, 1), frame="trim")
    for f in (m.left, m.right):
        f.stack(0.0, [(H, [None, HW, HW, None])])
        f.dado(None, 0.6, 0.06)
    m.back.stack(0.0, [(H, [K.rollup(3.2, 3.3), K.rollup(3.2, 3.3), K.door(1.0, 2.1), K.louvre(1.6, 0.8, 2.6), None,
                            K.door(1.0, 2.1)])])
    b.belt(m.pts, 3.75, 1.2, 0.1, "accent")
    b.flat_roof(m.pts, H, parapet=0.8)
    c = fr.w / 2
    a, e = sp[2]
    for (u0, u1) in ((a - 0.45, a + 0.05), (e - 0.05, e + 0.45)):
        fr.box(u0, u1, 0.0, H + 3.0, 0.0, 0.22, "accent", "body", "k b")
    fr.box(a - 1.6, e + 1.6, H + 0.6, H + 3.0, -1.5, 0.22, "accent", "body", "")
    fr.box(a - 1.75, e + 1.75, H + 3.0, H + 3.18, -1.65, 0.37, "trim", "body", "")
    fr.rect(a - 1.4, e + 1.4, H + 0.78, H + 0.86, "neon", 0.24, "detail")
    pw = (e - a) + 3.2
    px = min(0.18, (pw - 0.5) / K.text_rects("BAYFRESH")[1])
    fr.text("BAYFRESH", c, H + 2.1, px, "neon", 0.25)
    fr.text("MARKET", c, H + 1.25, px * 0.5, "trim", 0.25)
    fr.text("FRESH DAILY", (sp[0][0] + sp[1][1]) / 2, 4.35, 0.09, "trim", 0.12)
    fr.text("OPEN 24 HRS", (sp[3][0] + sp[4][1]) / 2, 4.35, 0.09, "trim", 0.12)
    fr.canopy(a - 0.8, e + 0.8, 3.36, 1.5, 0.2, "trim", rods=True)
    b.ac_unit(-7.5, -2.5, H, 2.0, 1.4, 1.1)
    b.ac_unit(-7.5, 0.5, H, 2.0, 1.4, 1.1)
    b.ac_unit(-3.5, -3.5, H, 2.0, 1.4, 1.1, turn=True)
    b.skylight(3.5, 8.5, -4.0, -2.0, H)
    b.skylight(3.5, 8.5, 0.0, 2.0, H)
    b.vent(0.5, -4.5, H)
    b.vent(1.7, -4.5, H)
    b.entrance = (0.0, Y)
    b.floors = 1
    return b.finish("storefront", ["midtown", "shops", "supermarket"])


@building
def storefront_d():
    """Art-deco arcade / picture house: lavender stepped facade, navy base, neon marquee and a tall COMET pylon."""
    b = K.Builder("storefront_d", SLOT["storefront_d"], dict(
        wall="Lavender", wall2="Navy", base="Navy", trim="Cream", roof="RoofGrey", door="Coral",
        sign="Navy", neon="NeonMagenta", accent="NeonCyan", metal="Charcoal"))
    X, Y = 7.85, 6.9
    H = 9.2
    m = b.mass(-X, X, -Y, Y)
    fr = m.front
    D = K.door(2.0, 2.5, glass=0.8, double=True, frame="trim", recess=0.5)
    PC = K.win(1.5, 2.1, sill=0.7, frame="trim", recess=0.08, proud=0.08)
    TB = K.win(1.5, 1.3, sill=1.1, frame="trim", sill_bar="trim", bars=(2, 1))
    sp = fr.row(0.0, GH, [PC, D, TB, D, PC], "base")
    fr.stack(GH, [(H - GH, None)])
    # side walls: deco slot windows, cream piers, poster cases and an exit door on the navy base
    VW = K.win(1.0, 2.9, sill=1.15, frame="trim", bars=(1, 4), recess=0.14)
    posters = (("Coral", "Cream"), ("Mustard", "Navy"), ("Teal", "Cream"), ("Rose", "Navy"))
    for k, f in enumerate((m.left, m.right)):
        f.stack(0.0, [(GH, [None, K.door(1.2, 2.2, frame="trim"), None, None], "base"), (H - GH, [VW, None, None, VW])])
        f.text("COMET", f.w / 2, 6.9, 0.27, "trim", 0.02, "body")
        f.rect(f.w / 2 - 2.85, f.w / 2 + 2.85, 5.55, 5.67, "accent", 0.02, "detail")
        q = f.w / 4.0
        for i, uc in enumerate((q * 0.5, q * 2.5, q * 3.5)):
            f.poster(uc - 0.7, uc + 0.7, 0.85, 2.85, posters[(i + 2 * k) % 4])
    bk = m.back
    bk.stack(0.0, [(GH, [K.door(1.2, 2.2, frame="trim"), K.louvre(1.6, 0.8, 2.4), K.rollup(2.6, 2.7), K.door(1.2, 2.2, frame="trim")], "base"),
                   (H - GH, [K.louvre(1.6, 1.0, 2.9, mat="SteelDark"), None, VW, K.louvre(1.6, 1.0, 2.9, mat="SteelDark")])])
    b.belt(m.pts, GH - 0.1, 0.25, 0.08, "trim")
    top = b.flat_roof(m.pts, H, parapet=0.9)
    for f in (m.left, m.right):
        for u in (0.5, f.w / 4.0, f.w * 0.75, f.w - 0.5):
            f.pilaster(u, GH + 0.15, top, w=0.6, proud=0.08, mat="trim", cap=False)
    for u in (0.5, bk.w / 2.0, bk.w - 0.5):
        bk.pilaster(u, GH + 0.15, top, w=0.6, proud=0.16, mat="trim", cap=False)
    bk.vent_duct(bk.w * 0.375, 3.3, top + 0.55, 0.62, 0.3)
    bk.wall_ladder(bk.w * 0.25 + 0.55, 0.5, top + 0.25)
    for uu in (bk.w / 8.0, bk.w * 7.0 / 8.0):
        bk.wall_light(uu, 2.7, part="body", arm=0.14)
    c = fr.w / 2
    for u in (0.5, 3.4, fr.w - 3.4, fr.w - 0.5):
        fr.pilaster(u, GH + 0.15, top + 0.35, w=0.7, proud=0.22, mat="trim", cap=False)
    fr.box(c - 4.3, c + 4.3, top, top + 0.8, -0.4, 0.0, "wall", "body", "b")
    fr.box(c - 4.4, c + 4.4, top + 0.8, top + 0.92, -0.46, 0.06, "trim", "body", "")
    fr.box(c - 2.3, c + 2.3, top + 0.92, top + 1.7, -0.4, 0.0, "wall", "body", "b")
    fr.box(c - 2.4, c + 2.4, top + 1.7, top + 1.82, -0.46, 0.06, "trim", "body", "")
    fr.box(1.2, fr.w - 1.2, 3.35, 4.35, 0.0, 1.5, "sign", "detail", "k")
    for v in (3.42, 4.2):
        fr.rect(1.3, fr.w - 1.3, v, v + 0.08, "accent", 1.52, "detail")
    fr.text("ARCADE * FILMS", c, 3.85, 0.085, "NeonYellow", 1.52)
    for sf in (fr.side_face(1.2 - 0.02, 0.0, 1.5, "-u"), fr.side_face(fr.w - 1.2 + 0.02, 0.0, 1.5, "+u")):
        for v in (3.42, 4.2):
            sf.rect(0.1, 1.4, v, v + 0.08, "accent", 0.0, "detail")
    fr.blade_sign(c, 4.45, top + 2.6, depth=1.25, text="COMET", board="sign", color="neon", th=0.36, gap=0.0)
    fr.rect(c - 0.07, c + 0.07, 4.6, top + 2.45, "accent", 1.27, "detail")
    for u in (1.5, 2.2, fr.w - 2.2, fr.w - 1.5):
        fr.rect(u - 0.05, u + 0.05, 5.0, 8.7, "accent", 0.02, "detail")
    for u in (5.0, 5.9, fr.w - 5.9, fr.w - 5.0):
        fr.rect(u - 0.05, u + 0.05, 5.0, 8.7, "neon", 0.02, "detail")
    b.ac_unit(-4.5, -3.0, H, 2.2, 1.5, 1.2)
    b.ac_unit(-4.5, 0.0, H, 2.2, 1.5, 1.2)
    b.vent(3.0, -4.0, H, 0.35, 0.8)
    b.vent(4.5, -4.0, H, 0.35, 0.8)
    b.stair_box(2.5, 5.5, -1.5, 1.5, H, 2.4, door="back")
    b.entrance = (X - (sp[1][0] + sp[1][1]) / 2, Y)
    b.floors = 2
    return b.finish("storefront", ["midtown", "downtown", "entertainment", "neon"])


@building
def storefront_e():
    """Mustard taqueria: coral base, serving hatch, long railed balcony for the flat above, red hip roof."""
    b = K.Builder("storefront_e", SLOT["storefront_e"], dict(
        wall="Mustard", wall2="Cream", base="Coral", trim="Cream", roof="RoofRed", door="Teal",
        awning="Teal", awning2="Cream", sign="WoodDark", neon="NeonOrange", metal="Charcoal"))
    X, Y0, Y1 = 6.5, -5.75, 5.25
    zt = GH + FH
    m = b.mass(-X, X, Y0, Y1)
    fr = m.front
    FD = K.win(1.5, 2.25, sill=0.05, bars=(2, 1), frame="trim")
    W = K.win(1.3, 1.5, sill=0.9, bars=(2, 2), frame="trim", sill_bar="trim", shutters="door")
    WS = K.win(1.3, 1.5, sill=0.9, bars=(2, 2), frame="trim", sill_bar="trim")
    sp = fr.row(0.0, GH, [K.shop(door="left", head=3.0, margin=0.35, riser=0.7),
                          K.win(2.2, 1.4, sill=1.1, frame="trim", awning=("awning", "awning2")),
                          K.door(1.0, 2.25, glass=0.3, frame="trim")], "base", widths=[6.0, 4.0, 3.0])
    fr.row(GH, FH, [FD, W, FD])
    fr.balcony(0.8, fr.w - 0.8, GH, depth=1.0, rail_h=1.0, style="rail")
    fr.dress_shop(sp[0], "PLAYA TACOS", "NeonOrange", ("Coral", "Cream"), sign_h=0.58)
    hu = (sp[1][0] + sp[1][1]) / 2
    fr.box(hu - 1.35, hu + 1.35, 1.0, 1.08, 0.0, 0.4, "Wood", "body", "k")
    fr.text("TO GO", hu, 0.6, 0.06, "trim", 0.02, "body")
    for f in (m.left, m.right):
        f.stack(0.0, [(GH, [None, K.win(1.2, 1.2, sill=1.6, frame="trim"), None], "base"), (FH, [WS, None, WS])])
    m.back.stack(0.0, [(GH, [K.door(1.0, 2.1), K.louvre(1.4, 0.7, 2.4), K.win(1.2, 1.2, sill=1.6, frame="trim")], "base"),
                       (FH, [WS] * 3)])
    b.belt(m.pts, GH - 0.08, 0.2, 0.07, edges=[0, 1, 3])
    b.hip_roof(-X, X, Y0, Y1, zt, 2.1, over=0.45, mat="roof")
    b.chimney(-3.6, -2.2, zt + 0.5, zt + 2.9, 0.75, 0.75, "wall2", "Concrete", "Terracotta")
    b.cyl(4.4, -4.2, zt + 0.2, zt + 2.4, 0.2, "Steel", "body", 8)
    b.cyl(4.4, -4.2, zt + 2.4, zt + 2.62, 0.34, "Steel", "body", 8, r2=0.0, caps="bottom")
    b.entrance = (X - (sp[0][0] + 0.35 + 0.08 + 0.55), Y1)
    b.floors = 2
    return b.finish("storefront", ["midtown", "residential", "food", "flats", "pitched_roof"])


@building
def storefront_f():
    """Three-storey brick block: hardware store + florist at street level, flats above, front fire escape."""
    b = K.Builder("storefront_f", SLOT["storefront_f"], dict(
        wall="Brick", wall2="Cream", base="Charcoal", trim="Cream", roof="RoofGrey", door="LeafDark",
        awning="LeafDark", awning2="Cream", sign="Black", neon="NeonYellow", metal="Charcoal"))
    X, Y = 8.9, 5.9
    zt = GH + 2 * FH
    m = b.mass(-X, X, -Y, Y)
    W = K.win(1.3, 1.7, sill=0.8, bars=(1, 2), sill_bar="trim", lintel="trim")
    fr = m.front
    SH = dict(head=3.0, margin=0.3, frame="trim")
    sp = fr.row(0.0, GH, [K.shop(door="left", **SH), K.door(1.0, 2.25, glass=0.3, frame="trim", transom=0.35),
                          K.shop(door="right", **SH)], "base", widths=[8.0, 1.8, 8.0])
    fr.stack(GH, [(FH, [W] * 5)] * 2)
    fr.dress_shop(sp[0], "HARBOR HARDWARE", "NeonYellow", ("Navy",), stripes=0, inset=0.5)
    fr.dress_shop(sp[2], "BLOOM FLORIST", "NeonGreen", ("LeafDark", "Cream"), inset=0.5)
    fr.fire_escape(7.4, 10.4, [GH, GH + FH], depth=1.0, ladder_to=2.9)
    m.right.stack(0.0, [(GH, [K.door(1.0, 2.1, frame="trim"), K.win(1.3, 1.2, sill=1.7, sill_bar="trim", lintel="trim"), None], "base"),
                        (FH, [W, None, W]), (FH, [W, None, W])])
    m.right.wall_light(m.right.w / 6.0, 2.65, part="body", arm=0.12)
    m.right.downpipe(m.right.w - 0.5, 0.0, zt - 0.5, mat="metal")
    lf = m.left
    lf.stack(0.0, [(GH, [None, K.louvre(1.2, 0.7, 2.4), K.door(1.0, 2.1, frame="trim")], "base"), (FH, [W, None, W]), (FH, [W, None, W])])
    lf.wall_light(lf.w * 5.0 / 6.0, 2.65, part="body", arm=0.12)
    lf.poster(0.9, 2.3, 0.9, 2.9, ("Mustard", "Cream"))
    lf.poster(2.5, 3.9, 0.9, 2.9, ("LeafDark", "Cream"))
    lf.text("HARBOR", lf.w / 2, 9.0, 0.105, "trim", 0.02, "body")
    lf.text("HARDWARE", lf.w / 2, 8.2, 0.105, "trim", 0.02, "body")
    lf.text("TOOLS", lf.w / 2, 5.9, 0.105, "trim", 0.02, "body")
    lf.text("PAINT", lf.w / 2, 5.1, 0.105, "trim", 0.02, "body")
    m.back.stack(0.0, [(GH, [K.door(1.0, 2.1), K.rollup(2.6, 2.7), K.louvre(1.2, 0.7, 2.4), None, K.door(1.0, 2.1)], "base"),
                       (FH, [W] * 5), (FH, [W] * 5)])
    b.belt(m.pts, GH - 0.1, 0.24, 0.08)
    b.cornice(m.pts, zt - 0.45, 0.85, 0.42)
    b.flat_roof(m.pts, zt, parapet=0.9)
    b.water_tank(-5.0, -2.5, zt, 1.1, 1.9)
    b.stair_box(2.5, 5.5, -3.5, -0.5, zt, 2.4)
    b.chimney(7.9, 3.5, zt, zt + 2.2, 0.8, 1.0)
    b.chimney(-7.9, 3.5, zt, zt + 2.2, 0.8, 1.0)
    b.vent(0.0, 2.5, zt)
    b.vent(1.1, 2.5, zt)
    b.entrance = (X - 0.93, Y)
    b.floors = 3
    return b.finish("storefront", ["midtown", "shops", "flats", "brick", "fire_escape"])


# ================================================================================================
# WAREHOUSES / INDUSTRY
# ================================================================================================
@building
def warehouse_a():
    """Teal corrugated freight shed: raised loading dock with three roll-up doors under a canopy, gable roof with roof lights."""
    b = K.Builder("warehouse_a", SLOT["warehouse_a"], dict(
        wall="Teal", wall2="White", base="ConcreteDark", trim="White", roof="RoofGrey", door="Charcoal",
        metal="Charcoal", sign="Navy", neon="NeonCyan", concrete="Concrete"))
    X, YB, YF = 15.4, -9.45, 7.0
    H, RISE = 7.2, 2.6
    CR = dict(pitch=1.0, depth=0.12)
    m = b.mass(-X, X, YB, YF)
    fr = m.front
    RD = K.rollup(3.4, 3.6, mat="White", frame="trim")
    wd = [2.4, 6.0, 6.0, 6.0, 3.4, 7.0]
    fr.stack(0.0, [(1.2, None, "base"),
                   (H - 1.3, [None, RD, RD, RD, K.door(1.0, 2.1), K.win(3.0, 1.2, sill=1.0, bars=(3, 1))], "wall",
                    dict(corr=CR, widths=wd))])
    fr.dock(2.2, fr.w, h=1.2, depth=2.45, steps="left")
    fr.canopy(2.2, fr.w, 5.3, 2.6, 0.2, "wall2", part="body")
    u = 2.4
    for i in range(3):
        fr.text(str(i + 1), u + 3.0, 1.2 + 2.9, 0.13, "sign", -0.13, "detail")
        u += 6.0
    fr.sign(8.4, 22.4, 5.62, 6.72, "HALCYON FREIGHT", board="sign", color="wall2", proud=0.2)
    fr.neon_line(8.6, 22.2, 5.68, 0.06, "neon", 0.23)
    HW = K.win(2.6, 1.0, sill=4.6, bars=(3, 1))
    m.back.stack(0.0, [(H - 0.1, [HW] * 7, "wall", dict(corr=CR))])
    m.back.dado()
    m.left.stack(0.0, [(H, [None, K.louvre(2.2, 1.2, 4.6), None, K.louvre(2.2, 1.2, 4.6), None], "wall", dict(corr=CR))])
    m.left.dado()
    m.right.stack(0.0, [(H, [K.louvre(2.2, 1.2, 4.6), K.rollup(4.2, 4.4, mat="White", frame="trim", lights=True), K.door(1.0, 2.1)],
                         "wall", dict(corr=CR, widths=[5.0, 6.45, 5.0]))])
    m.right.dado([(0.0, 5.98), (10.47, 13.31), (14.59, m.right.w)])
    b.gable_roof(-X, X, YB, YF, H, RISE, axis="x", over=0.5, gover=0.4, gable="wall2")
    for f in (m.left, m.right):
        f.box(f.w / 2 - 0.9, f.w / 2 + 0.9, H + 0.55, H + 1.45, 0.0, 0.06, "metal", "body", "k")
    b.roof_lights(-X + 1.5, X - 1.5, YB, YF, H, RISE, n=6)
    c = (YB + YF) / 2.0
    b.box(-9.0, 9.0, c - 0.6, c + 0.6, H + RISE - 0.3, H + RISE + 0.5, "wall2", "body", "-z")
    b.box(-9.3, 9.3, c - 0.9, c + 0.9, H + RISE + 0.5, H + RISE + 0.64, "roof")
    b.solid(-X, X - 2.2, YF, YF + 2.45, 0.0, 1.2)
    b.entrance = (X - 22.1, YF + 2.45)
    b.floors = 1
    return b.finish("warehouse", ["industrial", "dock", "corrugated"])


@building
def warehouse_b():
    """Brick cannery: saw-tooth factory hall, cream office annex, boiler house with two banded chimney stacks."""
    b = K.Builder("warehouse_b", SLOT["warehouse_b"], dict(
        wall="Brick", wall2="Cream", base="ConcreteDark", trim="Cream", roof="RoofGrey", door="Teal",
        metal="Charcoal", sign="Navy", neon="NeonOrange", concrete="Concrete"))
    XH0, XH1, XE, Y = -19.7, 8.0, 19.8, 13.75
    H = 8.0
    hall = b.mass(XH0, XH1, -Y, Y)
    FW = K.win(2.4, 3.4, sill=2.3, bars=(3, 4), frame="trim", frame_w=0.14, sill_bar="trim")
    RU = K.rollup(3.6, 4.2, mat="door", frame="trim", lights=True)
    fr = hall.front
    fr.stack(0.0, [(H, [FW, RU, FW, FW, K.door(1.2, 2.3, frame="trim", canopy=dict(depth=1.0)), FW, FW])])
    hall.left.stack(0.0, [(H, [FW] * 7)])
    hall.back.stack(0.0, [(H, [FW, FW, RU, FW, FW, K.door(1.2, 2.3, frame="trim"), FW])])
    for f in (hall.front, hall.left, hall.back):
        f.pilasters(0.0, 6.3, n=7, w=0.6, proud=0.2, mat="wall", cap=False)
    b.belt(hall.pts, 6.3, 0.3, 0.26, "trim", edges=[0, 2, 3])
    b.belt(hall.pts, H - 0.2, 0.32, 0.12, "trim", edges=[0, 2, 3])
    fr.text("BAYSIDE CANNERY", fr.w / 2, 7.2, 0.17, "wall2", 0.02, "body")
    hall.back.text("BAYSIDE CANNERY", hall.back.w / 2, 7.2, 0.17, "wall2", 0.02, "body")
    r = hall.right
    r.rect(0.0, 14.75, GH + FH, H, "wall")
    r.rect(14.75, r.w, 5.0, H, "wall")
    r.top = H
    b.sawtooth_roof(XH0, XH1, -Y, Y, H, teeth=5, rise=2.4, mat="roof", end="wall", frame="trim")
    an = b.mass(XH1, XE, -Y, 1.0)
    AW = K.win(1.5, 1.5, sill=0.95, bars=(2, 2), frame="wall", sill_bar="wall")
    an.right.stack(0.0, [(GH, [AW, K.door(1.1, 2.2, glass=0.4, frame="wall", canopy=dict(depth=0.14, mat="door", part="body")), AW, AW]),
                         (FH, [AW] * 4)], "wall2")
    an.back.stack(0.0, [(GH, [AW] * 3), (FH, [AW] * 3)], "wall2")
    an.front.rect(0.0, an.front.w, 5.0, GH + FH, "wall2")
    an.front.top = GH + FH
    b.flat_roof(an.pts, GH + FH, parapet=0.6, wall="wall2")
    b.belt(an.pts, GH - 0.1, 0.22, 0.07, "wall", edges=[0, 1])
    bo = b.mass(XH1, XE, 1.0, Y)
    bo.front.stack(0.0, [(5.0, [K.rollup(3.2, 3.4, mat="door", frame="trim"), K.louvre(2.0, 1.0, 2.6), K.door(1.1, 2.2, frame="trim")])])
    bo.right.stack(0.0, [(5.0, [K.louvre(2.0, 1.0, 2.6), None, K.louvre(2.0, 1.0, 2.6)])])
    b.flat_roof(bo.pts, 5.0, parapet=0.5)
    for x in (11.3, 16.5):
        b.box(x - 1.7, x + 1.7, 7.3, 10.7, 5.0, 6.2, "base", "body", "-z")
        b.stack(x, 9.0, 6.2, 27.5, 1.35, 0.85)
    b.tank_h(9.4, 14.2, 3.6, 5.0, 0.95, "White")
    b.silo(17.0, 3.9, 5.0, 9.2, 1.3, "Steel")
    b.tube((14.2, 3.6, 6.35), (15.7, 3.6, 6.35), 0.12, None, 6, "Steel", "body", "none")
    b.tube((11.8, 3.6, 7.3), (11.8, 7.3, 7.3), 0.12, None, 6, "Steel", "body", "none")
    b.tube((11.8, 3.6, 6.3), (11.8, 3.6, 7.42), 0.12, None, 6, "Steel", "body", "top")
    b.water_tank(15.5, -9.0, GH + FH, 1.2, 2.0)
    b.ac_unit(11.5, -4.0, GH + FH)
    b.ac_unit(11.5, -6.5, GH + FH)
    b.vent(14.0, -2.5, GH + FH)
    b.entrance = (XH1 - fr.w * 4.5 / 7.0, Y)
    b.floors = 2
    return b.finish("warehouse", ["industrial", "factory", "brick", "chimney", "tall"])


@building
def warehouse_c():
    """Mustard barrel-roofed depot: big sliding door, cream lean-to office, fuel tank on a plinth."""
    b = K.Builder("warehouse_c", SLOT["warehouse_c"], dict(
        wall="Mustard", wall2="Cream", base="Concrete", trim="Charcoal", roof="Steel", door="Navy",
        metal="Charcoal", sign="Charcoal", neon="NeonOrange", concrete="Concrete"))
    X0, X1, XE, Y = -11.5, 6.6, 11.5, 8.5
    H, RISE = 5.0, 3.4
    CR = dict(pitch=0.9, depth=0.12)
    hall = b.mass(X0, X1, -Y, Y)
    fr = hall.front
    HW = K.win(2.2, 1.1, sill=2.9, bars=(3, 1))
    fr.stack(0.0, [(H, [HW, K.rollup(5.6, 4.3, mat="door", slat=0.48, frame="trim"), K.door(1.0, 2.1)], "wall",
                    dict(corr=CR, widths=[5.5, 7.6, 5.0]))])
    fr.dado([(0.0, 5.5 + 0.86), (5.5 + 6.74, 15.46), (16.74, fr.w)], 0.9)
    hall.left.stack(0.0, [(H, [None, HW, None, HW, None], "wall", dict(corr=CR))])
    hall.left.dado(None, 0.9)
    hall.back.stack(0.0, [(H, [HW, HW, HW, HW], "wall", dict(corr=CR))])
    hall.back.dado(None, 0.9)
    r = hall.right
    r.sub(0.0, 5.0).stack(0.0, [(H, None, "wall", dict(corr=CR))])
    r.sub(0.0, 5.0).dado(None, 0.9)
    r.rect(5.0, r.w, 3.0, H, "wall")
    r.top = H
    b.barrel_roof(X0, X1, -Y, Y, H, RISE, seg=8, axis="y", over=0.3, th=0.2, mat="roof", end="wall2")
    b.belt(hall.pts, H - 0.14, 0.24, 0.2, "trim", edges=[1, 3])
    fr.text("DEPOT 7", fr.w / 2, H + 1.35, 0.26, "trim", 0.02, "body")
    hall.back.text("DEPOT 7", hall.back.w / 2, H + 1.35, 0.26, "trim", 0.02, "body")
    of = b.mass(X1, XE, -3.5, Y)
    OW = K.win(1.5, 1.3, sill=0.95, bars=(2, 1), frame="trim", sill_bar="trim")
    of.front.stack(0.0, [(3.0, [OW, K.door(1.0, 2.1, glass=0.4, frame="trim")])], "wall2")
    of.right.stack(0.0, [(3.0, [OW, OW, OW])], "wall2")
    of.back.stack(0.0, [(3.0, None)], "wall2")
    b.shed_roof(X1, XE, -3.5, Y, 3.0, 4.1, high="left", over=0.3, th=0.18, mat="roof", fill="wall2")
    b.box(6.75, XE, -8.4, -4.2, -K.SKIRT, 0.25, "concrete", "body", "-z")
    b.tank_h(7.5, 11.0, -6.3, 0.25, 0.9, "White")
    b.box(9.1, 9.4, -6.45, -6.15, 2.05, 2.5, "FireRed", "detail", "-z")
    cx = (X0 + X1) / 2.0
    for y in (-5.0, 0.0, 5.0):
        b.vent(cx, y, H + RISE - 0.06, 0.3, 0.6)
    b.solid(6.75, XE, -8.4, -4.2, 0.0, 2.3)
    b.entrance = (X1 - 9.3, Y)
    b.floors = 1
    return b.finish("warehouse", ["industrial", "depot", "corrugated"])


@building
def warehouse_d():
    """White logistics box: navy dado, orange stripe, five flush dock doors with shelters, glazed office corner."""
    b = K.Builder("warehouse_d", SLOT["warehouse_d"], dict(
        wall="White", wall2="Sky", base="Navy", trim="White", roof="RoofGrey", door="Charcoal", accent="SafetyOrange",
        metal="Charcoal", sign="Navy", neon="NeonBlue", concrete="Concrete"))
    X, YB, YF = 17.85, -11.9, 11.25
    H = 9.0
    OWD = 11.7
    m = b.mass(-X, X, YB, YF)
    fr = m.front
    off = fr.sub(0.0, OWD)
    dk = fr.sub(OWD, fr.w)
    RD = K.rollup(3.0, 3.2, sill=0.05, mat="Steel", frame="metal")
    dk.stack(0.0, [(1.2, None, "base"), (H - 1.2, [RD] * 5)])
    bw = dk.w / 5.0
    for i in range(5):
        uc = (i + 0.5) * bw
        dk.box(uc - 1.95, uc - 1.5, 1.25, 4.9, 0.0, 0.6, "metal", "body", "k")
        dk.box(uc + 1.5, uc + 1.95, 1.25, 4.9, 0.0, 0.6, "metal", "body", "k")
        dk.box(uc - 1.5, uc + 1.5, 4.45, 4.9, 0.0, 0.6, "metal", "body", "k l r")
        for du in (-1.1, 1.1):
            dk.box(uc + du - 0.2, uc + du + 0.2, 0.55, 1.2, 0.0, 0.25, "Black", "detail", "k")
        dk.text(str(i + 1), uc, 5.7, 0.14, "base", 0.02, "body")
    dk.band(6.9, 0.45, 0.05, "accent")
    dk.text("BLUEFIN CARGO", dk.w / 2, 8.0, 0.16, "base", 0.02, "body")
    SH = dict(head=3.2, margin=0.3, frame="metal")
    off.row(0.0, GH, [K.shop(door="none", **SH),
                      K.door(2.0, 2.5, glass=0.9, double=True, frame="metal", mat="metal", transom=0.45, recess=0.4),
                      K.shop(door="none", **SH)], "base")
    off.margins(0.45)
    off.curtain(GH, 2, 2.0, bay=1.8, spandrel=0.65, spandrel_mat="wall2", mull="trim")
    off.rect(0.0, off.w, GH + 4.0, H, "wall")
    off.canopy(off.w / 2 - 2.0, off.w / 2 + 2.0, 3.3, 1.4, 0.2, "trim")
    off.text("BLUEFIN", off.w / 2, H - 0.5, 0.1, "neon", 0.03)
    fr.top = H
    rt = m.right
    OW = K.win(2.0, 1.5, sill=0.95, bars=(2, 1), reveal="trim")
    rt.sub(rt.w - 9.2, rt.w).stack(0.0, [(GH, [K.win(2.0, 1.7, sill=1.0, bars=(2, 1), reveal="trim")] * 2, "base"), (FH, [OW] * 2),
                                         (H - GH - FH, None)])
    # service sides: clerestory strip windows, louvres, panel-joint fins, downpipes, roof ladder, painted name
    CW = K.win(3.0, 0.95, sill=4.25, bars=(3, 1), panes=(3, 1), reveal="trim", bar_mat="trim")
    LV = K.louvre(2.4, 1.2, 3.3)
    rs = rt.sub(0.0, rt.w - 9.2)
    rs.stack(0.0, [(1.2, None, "base"), (H - 1.2, [CW, LV, CW])])
    rt.top = H
    lf = m.left
    lf.stack(0.0, [(1.2, None, "base"), (H - 1.2, [LV, CW, CW, CW, LV])])
    bk = m.back
    b1 = bk.sub(0.0, 8.0)
    b1.stack(0.0, [(1.2, None, "base"), (H - 1.2, [CW, None])])
    b2 = bk.sub(8.0, 20.0)
    b2.stack(0.0, [(H, [K.rollup(4.4, 4.6, mat="Steel", frame="metal"), K.rollup(4.4, 4.6, mat="Steel", frame="metal")])])
    b2.dado([(0.0, 0.8), (5.2, 6.8), (11.2, 12.0)], 1.2, 0.04)
    b3 = bk.sub(20.0, bk.w)
    b3.stack(0.0, [(1.2, None, "base"), (H - 1.2, [CW, LV, CW, CW])])
    bk.top = H
    b.belt(m.pts, 6.9, 0.45, 0.05, "accent", edges=[0, 1, 3])
    top = b.flat_roof(m.pts, H, parapet=0.8)
    for (f, n) in ((lf, 5), (rs, 3), (b1, 2), (b3, 4)):
        for i in range(n + 1):
            u = min(max(f.w * i / float(n), 0.16), f.w - 0.16)
            f.fin(u, 1.2, 6.9, w=0.32, proud=0.06, mat="Concrete")
    for (f, u) in ((b1, 4.32), (b3, b3.w * 0.75 - 0.3)):
        f.downpipe(u, 0.0, 6.9)
    lf.text("BLUEFIN CARGO", lf.w / 2, 8.05, 0.16, "base", 0.02, "body")
    b3.text("BLUEFIN", b3.w / 2, 8.05, 0.16, "base", 0.02, "body")
    b1.wall_ladder(6.0, 0.6, top + 0.25)
    for u in (0.4, 5.6, 6.4, 11.6):                 # door-guard bollards beside the two big rear doors
        b2.box(u - 0.13, u + 0.13, 0.0, 1.05, 0.14, 0.4, "HazardYellow", "body", "b")
        b2.box(u - 0.14, u + 0.14, 0.55, 0.78, 0.13, 0.41, "Black", "body", "t b")
    for x in (-11.5, -3.5, 4.5):
        for y in (-6.0, 3.0):
            b.skylight(x - 2.2, x + 2.2, y - 1.1, y + 1.1, H, 0.5)
    b.ac_unit(12.5, 6.0, H, 2.2, 1.5, 1.2)
    b.ac_unit(12.5, 3.0, H, 2.2, 1.5, 1.2)
    b.ac_unit(12.5, -6.0, H, 2.2, 1.5, 1.2, turn=True)
    b.vent(9.5, -8.5, H)
    b.vent(10.7, -8.5, H)
    b.dish(15.0, -9.0, H, 0.7)
    b.solid(-X, X - OWD, YF, YF + 0.6, 1.2, 4.9)
    b.entrance = (X - OWD / 2.0, YF)
    b.floors = 2
    return b.finish("warehouse", ["industrial", "logistics", "dock", "modern"])


# ================================================================================================
# PARKING STRUCTURE
# ================================================================================================
@building
def parking_a():
    """Open three-deck car park 32 x 28 m (collision: trimesh). Really drivable: ground -> deck 1 by the
    back ramp (heading +X), deck 1 -> roof deck by the front ramp (heading -X); loop friendly, every
    turn is 90 degrees. Ramps: 21 m long, 15 % (first / last metre 7.5 %), 5.65 m wide; end lanes 4.65 m
    clear between the columns and the ramp guard walls. Clear height 2.7 m under the decks, 2.6 m under
    the entrance beam."""
    b = K.Builder("parking_a", SLOT["parking_a"], dict(
        wall="Concrete", wall2="Cream", base="ConcreteDark", trim="White", roof="AsphaltLight", accent="Mustard",
        door="Navy", metal="Charcoal", sign="Navy", neon="NeonBlue", concrete="Concrete", core="Teal"))
    X, Y = 15.9, 13.9
    L0, L1, L2 = 0.12, 3.12, 6.12
    TH, PH, WT, DROP = 0.3, 1.08, 0.25, 0.52
    RX, RB, EW, AP = PARKING_RX, 8.0, 3.2, 12.4
    EASE = 1.0
    rect = K.rect_pts(-X, X, -Y, Y)

    def top(x0, x1, y0, y1, z):
        b.poly(((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)), "roof")

    # ground slab with an entrance apron (slopes down to meet the street)
    b.ring(rect, [(0.0, -K.SKIRT), (0.0, L0)], "base", edges=[0, 1, 3])
    for (xa, xb, zz) in ((-X, -EW, L0), (-EW, EW, -0.05), (EW, X, L0)):
        b.poly(((xb, Y, -K.SKIRT), (xa, Y, -K.SKIRT), (xa, Y, zz), (xb, Y, zz)), "base")
    top(-X, X, -Y, AP, L0)
    top(-X, -EW, AP, Y, L0)
    top(EW, X, AP, Y, L0)
    b.poly(((-EW, AP, L0), (EW, AP, L0), (EW, Y, -0.05), (-EW, Y, -0.05)), "roof")
    b.poly_dir([(-EW, AP, L0), (-EW, Y, L0), (-EW, Y, -0.05)], (1, 0, 0), "base")
    b.poly_dir([(EW, AP, L0), (EW, Y, L0), (EW, Y, -0.05)], (-1, 0, 0), "base")

    # decks: deck 1 is open above the back ramp, the roof deck above the front ramp
    b.deck(-X, X, -RB, Y, L1, TH)
    b.deck(-X, -RX, -Y, -RB, L1, TH, skip="+y")
    b.deck(RX, X, -Y, -RB, L1, TH, skip="+y")
    b.deck(-X, X, -Y, RB, L2, TH)
    b.deck(-X, -RX, RB, Y, L2, TH, skip="-y")
    b.deck(RX, X, RB, Y, L2, TH, skip="-y")

    # ramps (solid wedges) + their aisle-side walls + guards round the two deck openings
    slope = b.ramp(-RX, RX, L0, L1, -Y + WT, -RB, ease=EASE)
    b.ramp(RX, -RX, L1, L2, RB, Y - WT, ease=EASE)
    b.box(-RX, RX, -RB, -RB + WT, L0, L1 + PH, "wall2", "body", "-z")
    b.box(-RX - WT, -RX, -Y + WT, -RB + WT, L1, L1 + PH, "wall2", "body", "-z")
    b.box(-RX, RX, RB - WT, RB, L1, L2 + PH, "wall2", "body", "-z")
    b.box(RX, RX + WT, RB - WT, Y - WT, L2, L2 + PH, "wall2", "body", "-z")
    for (yy, sgn, z0) in ((-RB + WT + 0.015, 1, L0), (RB - WT - 0.015, -1, L1)):
        b.poly_dir([(-RX + 0.3, yy, z0 + 1.0), (RX - 0.3, yy, z0 + 1.0), (RX - 0.3, yy, z0 + 1.35), (-RX + 0.3, yy, z0 + 1.35)],
                   (0, sgn, 0), "accent", "detail")

    # perimeter: low wall at street level (open at the entrance), spandrel parapets on both decks
    b.ring(rect, [(0.0, L0), (0.0, L0 + PH), (-WT, L0 + PH), (-WT, L0)], "wall2", closed=True, edges=[0, 1, 3])
    b.box(-X, -EW, Y - WT, Y, L0, L0 + PH, "wall2", "body", "-z")
    b.box(EW, X, Y - WT, Y, L0, L0 + PH, "wall2", "body", "-z")
    for L in (L1, L2):
        b.ring(rect, [(0.0, L - DROP), (0.0, L + PH), (-WT, L + PH), (-WT, L - DROP)], "wall2", closed=True)
        b.ring(rect, [(0.015, L + 0.2), (0.015, L + 0.55)], "accent")
    xc = RX - (L1 - DROP - L0 - PH) * (2 * RX) / (L1 - L0)
    b.prism([(-RX, L0 + PH), (RX, L0 + PH), (RX, L1 - DROP), (-xc, L1 - DROP)], -Y, -Y + WT, "y", "wall2")
    b.prism([(RX, L1 + PH), (xc, L2 - DROP), (-RX, L2 - DROP), (-RX, L1 + PH)], Y - WT, Y, "y", "wall2")

    # structure: perimeter columns (proud of the spandrels), interior columns on the ramp-wall and island lines
    xs = [-X, -9.54, -3.18, 3.18, 9.54, X]
    ys = [-Y, -6.95, 0.0, 6.95, Y]
    ctop = L2 + PH + 0.14
    for x in xs:
        for y in ys:
            ex = abs(abs(x) - X) < 1e-6
            ey = abs(abs(y) - Y) < 1e-6
            if not (ex or ey):
                continue
            x0, x1, y0, y1 = x - 0.3, x + 0.3, y - 0.3, y + 0.3
            if ex:
                x0, x1 = (X - 0.5, X + 0.1) if x > 0 else (-X - 0.1, -X + 0.5)
            if ey:
                y0, y1 = (Y - 0.5, Y + 0.1) if y > 0 else (-Y - 0.1, -Y + 0.5)
            b.box(x0, x1, y0, y1, -K.SKIRT, ctop, "wall", "body", "-z")
    for x in xs[1:-1]:
        for y in (-RB + 0.3, 0.0, RB - 0.3):
            b.box(x - 0.25, x + 0.25, y - 0.25, y + 0.25, L0, L2 - TH, "wall", "body", "-z +z")

    # stair / lift core in the middle island, rising above the roof deck with the big P
    cx0, cx1, cy0, cy1 = -2.3, 2.3, -2.8, 2.0
    ct = L2 + 3.3
    b.box(cx0, cx1, cy0, cy1, L0, ct, "core", "body", "-z +z")
    b.box(cx0 - 0.2, cx1 + 0.2, cy0 - 0.2, cy1 + 0.2, ct, ct + 0.2, "trim")
    cf = K.Face(b, (cx1, cy1), (cx0, cy1), 0.0)
    cb = K.Face(b, (cx0, cy0), (cx1, cy0), 0.0)
    for i, L in enumerate((L0, L1, L2)):
        cf.box(1.1, 2.3, L, L + 2.2, 0.0, 0.05, "trim", "detail", "k b")
        cf.rect(1.2, 2.2, L, L + 2.1, "door", 0.055, "detail")
        cf.rect(1.42, 1.98, L + 1.25, L + 1.85, K.WINDOW_MAT, 0.06)
        cf.text(str(i + 1), 1.7, L + 2.5, 0.09, "trim", 0.03, "detail")
        cb.box(0.9, cb.w - 0.9, L + 0.9, L + 2.1, 0.0, 0.025, "trim", "detail", "k")
        cb.pane(1.0, cb.w - 1.0, L + 1.0, L + 2.0, 0.03, 2, 1)
    for sf in (K.Face(b, (cx1, cy0), (cx1, cy1), 0.0), K.Face(b, (cx0, cy1), (cx0, cy0), 0.0)):
        sf.box(0.0, sf.w, L2 + 2.35, L2 + 2.75, 0.0, 0.03, "accent", "detail", "k")
    for f in (cf, cb):
        f.box(f.w / 2 - 1.0, f.w / 2 + 1.0, L2 + 1.15, L2 + 3.05, 0.0, 0.08, "sign", "detail", "k")
        f.text("P", f.w / 2, L2 + 2.1, 0.26, "neon", 0.1)

    # entrance signage + clearance stripe
    ff = K.Face(b, (X, Y), (-X, Y), 0.0)
    uc = ff.w / 2
    ff.sign(uc - 2.7, uc + 2.7, L1 - DROP + 0.25, L1 + PH - 0.1, "PARKING", board="sign", color="neon", proud=0.1)
    ff.rect(uc - EW + 0.3, uc + EW - 0.3, L1 - DROP, L1 - DROP + 0.16, "HazardYellow", 0.02, "detail")

    # painted bay lines
    def lines(xl, y0, y1, z):
        for x in xl:
            b.poly(((x - 0.06, y0, z + 0.02), (x + 0.06, y0, z + 0.02), (x + 0.06, y1, z + 0.02), (x - 0.06, y1, z + 0.02)),
                   "RoadLine", "detail")

    def fr_(a, c, step):
        n = max(1, int(round((c - a) / step)))
        return [a + (c - a) * i / n for i in range(n + 1)]

    def hatch(x0, x1, y0, y1, z, n=3):
        """No-parking box: outline + diagonal stripes (the manoeuvring pockets beside the ramp ends)."""
        zz = z + 0.02
        w = 0.06
        for (a, c, e, g) in ((x0, x1, y0, y0 + 2 * w), (x0, x1, y1 - 2 * w, y1), (x0, x0 + 2 * w, y0, y1), (x1 - 2 * w, x1, y0, y1)):
            b.poly(((a, e, zz), (c, e, zz), (c, g, zz), (a, g, zz)), "HazardYellow", "detail")
        dy = (y1 - y0) / n
        for i in range(n):
            ya, yb = y0 + i * dy, y0 + (i + 1) * dy
            b.poly(((x0, ya, zz), (x0 + 0.16, ya, zz), (x1, yb, zz), (x1 - 0.16, yb, zz)), "HazardYellow", "detail")

    isl = [x for x in fr_(-9.1, 9.1, 2.6) if abs(x) > 2.5]
    for L in (L0, L1, L2):
        lines(isl, -2.8, 2.0, L)
    PK = RX + WT + 1.55                       # pockets beside the ramp ends: one bay + a hatched strip
    lines(fr_(-15.4, -4.0, 2.85) + fr_(4.0, 15.4, 2.85), 8.6, 13.5, L0)
    lines([-15.4, -PK], 8.6, 13.5, L1)
    hatch(-PK + 0.25, -RX - WT - 0.2, 8.8, 13.3, L1)
    lines([-15.4, -PK], -13.5, -8.6, L1)
    hatch(-PK + 0.25, -RX - WT - 0.2, -13.3, -8.8, L1)
    lines(fr_(-15.4, 15.4, 2.8), -13.5, -8.6, L2)
    lines([PK, 15.4], 8.6, 13.5, L2)
    hatch(RX + WT + 0.2, PK - 0.25, 8.8, 13.3, L2)
    for (x, y, ax) in ((-9.54, 0.0, "x"), (9.54, 0.0, "x"), (1.4, -13.2, "x"), (-15.0, 11.0, "y"), (15.0, 11.0, "y")):
        b.lamp_post(x, y, L2, 4.2, axis=ax)       # all clear of the driving lanes (island line / bay lines / walls)
    b.roof_z = L2
    b.entrance = (0.0, Y)
    b.floors = 3
    return b.finish("parking", ["downtown", "parking", "drivable"], collision="trimesh", extra={
        "levels": [L0, L1, L2], "clear_height": 2.6, "entrance_width": round(2 * (xs[3] - 0.3), 2),      # clear between the jamb columns
        "collision_nodes": ["Building"],
        "ramp_slope": round(slope, 4), "ramp_length": 2 * RX, "lane_width_min": round(X - 0.5 - RX - WT, 2),
        # centre line street -> roof deck in Godot local space [x, z] (z = -blender y); drive it backwards to leave
        "route_up": [[round(px, 2), round(-py, 2)] for (px, py) in PARKING_ROUTE],
        "ramps": [{"from": [-RX, L0, RB + 2.8], "to": [RX, L1, RB + 2.8], "width": Y - WT - RB},
                  {"from": [RX, L1, -(RB + 2.8)], "to": [-RX, L2, -(RB + 2.8)], "width": Y - WT - RB}],
    })


# ================================================================================================
# MISC
# ================================================================================================
@building
def garage_row():
    """Row of five lock-up garages: block walls, colour-coded doors with numbers, mono-pitch roof, lamps."""
    b = K.Builder("garage_row", SLOT["garage_row"], dict(
        wall="WarmGrey", wall2="Concrete", base="ConcreteDark", trim="White", roof="RoofGrey", door="Teal",
        metal="Charcoal", sign="Charcoal"))
    X, YB, YF = 7.75, -3.15, 3.0
    HL, HH = 2.55, 3.15
    m = b.mass(-X, X, YB, YF)
    cols = ("Teal", "Coral", "Mustard", "Sky", "Rust")
    fr = m.front
    sp = fr.row(0.0, HL, [K.rollup(2.5, 2.15, mat=c, slat=0.43, frame="trim") for c in cols])
    # service sides: a side door + meter cabinet, louvres, one small high window per garage at the back
    HWN = K.win(0.95, 0.45, sill=1.6, frame="trim", recess=0.1, bars=(2, 1))
    m.right.stack(0.0, [(HL, [None, K.louvre(0.8, 0.4, 1.7), K.door(0.9, 2.0, frame="trim")])])
    m.left.stack(0.0, [(HL, [None, K.louvre(0.8, 0.4, 1.7), None])])
    m.back.stack(0.0, [(HL, [HWN] * 5)])
    m.back.pilasters(0.0, HL, n=5, w=0.3, proud=0.07, mat="wall2", cap=False)
    m.back.dado(None, 0.45, 0.05)
    m.left.dado(None, 0.45, 0.05)
    m.right.dado([(0.0, 4.4)], 0.45, 0.05)
    m.right.wall_light(m.right.w * 5.0 / 6.0, 2.2, part="body", arm=0.12)
    lf = m.left
    lf.box(3.9, 4.8, 0.75, 1.95, 0.0, 0.22, "SteelDark", "body", "k")          # meter cabinet
    lf.rect(4.15, 4.55, 1.5, 1.72, "HazardYellow", 0.232, "body")
    lf.box(3.86, 4.84, 1.95, 2.0, 0.0, 0.24, "metal", "body", "k")
    s = (HH - HL) / (YF - YB)

    def zr(x, y):
        return HL + (y - YB) * s

    b.shed_roof(-X, X, YB, YF, HL, HH, high="front", over=0.25, th=0.16, mat="roof", fill="wall")
    b.seams(-X - 0.25, X + 0.25, YB - 0.25, YF + 0.25, zr, n=11, along="y", w=0.09, h=0.06, mat="SteelDark")
    for x in (-4.65, 1.55):
        b.vent(x, 0.6, zr(x, 0.6) - 0.02, 0.2, 0.42)
    b.box(-X - 0.2, X + 0.2, YB - 0.24, YB - 0.07, HL - 0.36, HL - 0.24, "metal", "body")      # gutter under the low eave
    fr.pilasters(0.0, HL + 0.1, n=5, w=0.36, proud=0.1, mat="wall2", cap=False)
    for i, (a, c) in enumerate(sp):
        uc = (a + c) / 2
        fr.box(uc - 0.3, uc + 0.3, 2.42, 2.9, 0.0, 0.03, "trim", "body", "k")
        fr.text(str(i + 1), uc, 2.66, 0.065, "sign", 0.04, "body")
    for k in (1, 3):
        u = sp[k][1]
        fr.box(u - 0.16, u + 0.16, 2.62, 2.72, 0.1, 0.42, "metal", "detail", "k")
        fr.box(u - 0.12, u + 0.12, 2.56, 2.62, 0.14, 0.38, "LampWarm", "detail", "t")
    for x in (-X + 0.3, X - 0.3):
        b.tube((x, YB - 0.08, 0.0), (x, YB - 0.08, HL - 0.1), 0.05, None, 6, "metal", "detail", "none")
    b.entrance = (0.0, YF)
    b.floors = 1
    return b.finish("misc", ["garage", "alley", "residential", "industrial"])


@building
def shed_a():
    """Olive board-and-batten tool shed: double doors, small window with a flower box, grey gable roof."""
    b = K.Builder("shed_a", SLOT["shed_a"], dict(
        wall="Olive", wall2="Olive", base="Concrete", trim="Cream", roof="RoofGrey", door="WoodDark", metal="Charcoal"))
    X, Y = 2.25, 1.55
    H = 2.15
    CR = dict(pitch=0.46, depth=0.05)
    m = b.mass(-X, X, -Y, Y)
    fr = m.front
    fr.row(0.0, H - 0.08, [K.door(1.5, 1.9, double=True, recess=0.06), K.win(0.8, 0.7, sill=1.05, bars=(2, 2), recess=0.06, planter=True)],
           "wall", widths=[2.6, 1.9], corr=CR)
    m.back.stack(0.0, [(H - 0.08, None, "wall", dict(corr=CR))])
    for f in (m.left, m.right):
        f.stack(0.0, [(H, None, "wall", dict(corr=CR))])
    for f in m.all:
        f.pilaster(0.07, 0.0, H - 0.1, 0.14, 0.09, "trim", cap=False)
        f.pilaster(f.w - 0.07, 0.0, H - 0.1, 0.14, 0.09, "trim", cap=False)
    b.gable_roof(-X, X, -Y, Y, H, 0.95, axis="x", over=0.3, gover=0.25, gable="wall")
    fr.prism([(0.0, 0.1), (0.7, 0.0), (0.0, 0.0)], 0.5, 2.1, "Wood", closed=False)
    lf = m.left
    lf.box(0.5, 2.3, 0.0, 0.75, 0.09, 0.5, "WoodDark", "body", "k b")
    lf.box(0.6, 2.2, 0.75, 0.95, 0.12, 0.46, "Wood", "body", "k b")
    b.entrance = (X - 1.3, Y)
    b.floors = 1
    return b.finish("misc", ["shed", "yard", "residential"])


@building
def kiosk_a():
    """Street kiosk 4 x 4 m: teal booth, serving hatch with counter and striped awning, flat canopy roof with
    a coral cap and a neon SNACKS sign, magazine rack on the side."""
    b = K.Builder("kiosk_a", SLOT["kiosk_a"], dict(
        wall="Teal", wall2="Cream", base="Navy", trim="White", roof="Coral", door="Navy", awning="Coral",
        awning2="White", sign="Navy", neon="NeonYellow", metal="Charcoal"))
    R = 1.5
    H = 2.6
    m = b.mass(-R, R, -R, R)
    fr = m.front
    fr.stack(0.0, [(0.95, None, "base"), (H - 0.95, [K.win(2.3, 1.05, sill=0.08, frame="trim", bars=(2, 1), recess=0.12)])])
    for f in (m.left, m.right):
        f.stack(0.0, [(0.95, None, "base"), (H - 0.95, [K.win(1.3, 0.9, sill=0.2, frame="trim", recess=0.1)])])
    m.back.stack(0.0, [(H, [K.door(0.85, 2.0, frame="trim", recess=0.08)])])
    m.back.dado([(0.0, 0.95), (2.05, 3.0)], 0.95, 0.02)
    fr.box(0.2, 2.8, 0.95, 1.03, 0.0, 0.4, "trim", "body", "k")
    for u in (0.5, 2.5):
        fr.prism([(0.0, 0.6), (0.34, 0.95), (0.0, 0.95)], u - 0.04, u + 0.04, "metal", "detail", closed=False)
    fr.awning(0.15, 2.85, 2.38, depth=0.85, drop=0.3, valance=0.14, stripes=6)
    b.slab_roof(m.pts, H, 0.16, 0.4, "trim", "trim")
    zs = H + 0.16
    b.taper((-1.35, 1.35, -1.35, 1.35), (-0.5, 0.5, -0.5, 0.5), zs, zs + 0.55, "roof")
    b.cyl(0.0, 0.0, zs + 0.55, zs + 0.95, 0.07, "metal", "detail", 6)
    b.box(-0.1, 0.1, -0.1, 0.1, zs + 0.95, zs + 1.15, "neon", "detail")
    b.roof_sign("SNACKS", 0.0, 1.72, zs, px=0.085, color="neon", lift=0.12)
    b.roof_sign("SNACKS", 0.0, 1.52, zs, px=0.085, color="neon", lift=0.12, facing="back")
    fr.rect(-0.35, fr.w + 0.35, H + 0.04, H + 0.1, "neon", 0.42, "detail")
    rk = m.left
    rk.box(0.25, 2.75, 0.2, 0.92, 0.0, 0.16, "wall2", "detail", "k")
    for i, c in enumerate(("Coral", "Mustard", "Sky", "Mint")):
        rk.rect(0.36 + i * 0.6, 0.36 + i * 0.6 + 0.46, 0.3, 0.82, c, 0.17, "detail")
    b.entrance = (0.0, R)
    b.floors = 1
    return b.finish("misc", ["street", "kiosk", "downtown", "midtown", "beach"])


# ================================================================================================
# registry helpers
# ================================================================================================
def build(name, check=True):
    """(Re)build one building; returns the audit/measure dict."""
    BUILDERS[name]()
    out = {}
    if check:
        out["audit"] = K.audit(name, verbose=True)
        out["measure"] = K.measure(name)
    return out


def run(names, preview=True, export=False):
    """Quiet batch helper for MCP calls: (re)build, audit, measure, optionally preview / export each
    name and print ONE summary line per building."""
    import contextlib
    import io
    import traceback
    if isinstance(names, str):
        names = [names]
    out = {}
    for n in names:
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                BUILDERS[n]()
                a = K.audit(n, verbose=False)
                m = K.measure(n)
                if preview:
                    K.preview(n)
                if export:
                    K.export(n)
            out[n] = m
            print(n, "tris", m["tris"], "fp", m["footprint"], "ctr", m["center"], "h", m["height"], "full", m["full_min"],
                  m["full_max"], "issues", m["issues"], "suspect", a["suspect"], "dup", a["duplicates"], "degen", a["degenerate"])
        except Exception:
            print("FAILED", n)
            traceback.print_exc()
    return out


PARKING_RX = 10.5        # half length of the two parking_a ramps (21 m run for a 3.0 m rise)
_PLX = 12.4              # driving line in the end lanes: the inner third (lane = 10.75 .. 15.4), so the nose has room to swing
PARKING_ROUTE = [(0.0, 16.0), (0.0, 5.0), (-_PLX, 5.0), (-_PLX, -10.8), (_PLX, -10.8), (_PLX, 10.8), (-_PLX, 10.8), (-_PLX, -4.0)]


def drive_test(name="parking_a", route=None, half_width=1.0, clear=2.6, step=0.25, min_width=3.5, max_slope=0.18):
    """Geometric drivability check of the car park: walks the up-route (street -> roof deck, Blender
    asset coordinates) over the `Building` mesh with a probe as wide as a car and reports the biggest
    surface step, the steepest slope, the smallest headroom and the narrowest free lane width (wall to
    wall / column at bumper height). A missing surface, a slope above max_slope, headroom below `clear`
    or a lane narrower than min_width is a failure."""
    from mathutils.bvhtree import BVHTree
    ob = bpy.data.objects[name + "_Building"]
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    route = route or PARKING_ROUTE
    offs = (-half_width, 0.0, half_width)
    zprev = [0.0, 0.0, 0.0]
    res = {"ok": True, "max_step": 0.0, "max_slope": 0.0, "min_headroom": 99.0, "min_width": 99.0, "length": 0.0, "fails": []}
    for (p, q) in zip(route[:-1], route[1:]):
        a = Vector((p[0], p[1], 0.0))
        d = Vector((q[0], q[1], 0.0)) - a
        n = max(1, int(d.length / step))
        t = d.normalized()
        side = Vector((-t.y, t.x, 0.0))
        for i in range(1, n + 1):
            c = a + d * (i / float(n))
            for k, o in enumerate(offs):
                pt = c + side * o
                hit = bvh.ray_cast(Vector((pt.x, pt.y, zprev[k] + 1.0)), Vector((0, 0, -1)), 3.0)
                if hit[0] is None:
                    if abs(pt.y) > 13.85 or abs(pt.x) > 15.85:
                        z = 0.0                       # outside the footprint: the street
                    else:
                        res["ok"] = False
                        res["fails"].append(("no surface", round(pt.x, 2), round(pt.y, 2), round(zprev[k], 2)))
                        continue
                else:
                    z = hit[0].z
                dz = abs(z - zprev[k])
                res["max_step"] = max(res["max_step"], dz)
                if dz > 0.09:
                    res["ok"] = False
                    res["fails"].append(("step", round(pt.x, 2), round(pt.y, 2), round(zprev[k], 2), round(z, 2)))
                sl = dz / (d.length / n)
                res["max_slope"] = max(res["max_slope"], sl)
                if sl > max_slope + 1e-3 and dz <= 0.09:
                    res["ok"] = False
                    res["fails"].append(("slope", round(pt.x, 2), round(pt.y, 2), round(sl, 3)))
                up = bvh.ray_cast(Vector((pt.x, pt.y, z + 0.2)), Vector((0, 0, 1)), 50.0)
                if up[0] is not None:
                    head = up[0].z - z
                    res["min_headroom"] = min(res["min_headroom"], head)
                    if head < clear - 1e-3:
                        res["ok"] = False
                        res["fails"].append(("headroom", round(pt.x, 2), round(pt.y, 2), round(z, 2), round(head, 2)))
                zprev[k] = z
            # free width between walls / columns / parapets at bumper height (0.5 m above the surface)
            pc = Vector((c.x, c.y, zprev[1] + 0.5))
            wl = bvh.ray_cast(pc, side, 30.0)
            wr = bvh.ray_cast(pc, -side, 30.0)
            if wl[0] is not None and wr[0] is not None:
                wdt = wl[3] + wr[3]
                if wdt < res["min_width"]:
                    res["min_width"] = wdt
                    res["min_width_at"] = (round(c.x, 2), round(c.y, 2), round(zprev[1], 2))
                if wdt < min_width - 1e-3:
                    res["ok"] = False
                    res["fails"].append(("width", round(c.x, 2), round(c.y, 2), round(wdt, 2)))
        res["length"] += d.length
    res["end_z"] = [round(z, 3) for z in zprev]
    res["fails"] = res["fails"][:12]
    for key in ("max_step", "max_slope", "min_headroom", "length", "min_width"):
        res[key] = round(res[key], 3)
    print("DRIVE_TEST %s: %s" % (name, res))
    return res


def build_all(names=None, check=True):
    res = {}
    for n in (names or ORDER):
        if n in BUILDERS:
            res[n] = build(n, check)
    return res


def export_all(names=None):
    for n in (names or ORDER):
        if bpy.data.objects.get(n) is not None:
            K.export(n)


def manifest_path():
    return os.path.join(G.MODELS_DIR, "buildings", "manifest_generic.json")


def write_manifest(names=None):
    names = [n for n in (names or ORDER) if bpy.data.objects.get(n) is not None]
    return K.write_manifest(manifest_path(), names, {
        "author": "building_kit / buildings_generic",
        "notes": "footprint = [x, z] of the solid `Building` node; height = top of everything; entrance / "
                 "center_offset / collision_boxes are in Godot local space (x, y up, z = -blender y); "
                 "collision_boxes = optional tighter boxes [cx, cy, cz, sx, sy, sz].",
    })


GROUPS = {
    "downtown": ["office_a", "office_b", "office_c", "office_d", "office_e", "office_f", "parking_a",
                 "storefront_a", "storefront_c", "storefront_d", "kiosk_a"],
    "residential": ["apartment_a", "apartment_b", "apartment_c", "apartment_d", "house_a", "house_b", "house_c",
                    "house_d", "house_e", "house_f", "storefront_b", "storefront_e", "storefront_f", "garage_row", "shed_a"],
    "industrial": ["warehouse_a", "warehouse_b", "warehouse_c", "warehouse_d", "garage_row", "shed_a", "parking_a"],
}


def group_preview(group, out_name=None, gap=8.0, views=("three_quarter", "front", "rear_quarter", "top"), res=512, rows=2):
    """Ensemble preview: temporarily lines the assets up like a street (front facades toward +Y),
    renders a contact sheet and puts every root back in its slot."""
    names = [n for n in (GROUPS[group] if isinstance(group, str) else group) if bpy.data.objects.get(n) is not None]
    saved = {}
    try:
        per = int(math.ceil(len(names) / float(rows)))
        base = G.slot("buildings", 56)
        y = 0.0
        for r in range(rows):
            x = 0.0
            depth = 0.0
            for n in names[r * per:(r + 1) * per]:
                ms = K.measure(n)
                root = bpy.data.objects[n]
                saved[n] = root.location.copy()
                w = ms["full_max"][0] - ms["full_min"][0]
                d = ms["full_max"][1] - ms["full_min"][1]
                root.location = base + Vector((x - ms["full_min"][0], y - ms["full_max"][1], 0.0))
                x += w + gap
                depth = max(depth, d)
            y -= depth + gap * 2.5
        bpy.context.view_layer.update()
        return K.preview(names, out_name or ("group_" + str(group)), views=views, res=res)
    finally:
        for n, loc in saved.items():
            bpy.data.objects[n].location = loc
        bpy.context.view_layer.update()
