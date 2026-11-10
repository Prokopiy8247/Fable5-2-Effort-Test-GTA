# -*- coding: utf-8 -*-
"""wpn_pickups - NEON TIDE pickups and held / special items (tools/blender/SPEC_WEAPONS.md, "P2 - Pickups" and
"P2 - Held / special items"; fx_muzzle_flash / fx_tracer are particles in the game and are not built here).

Run inside Blender through the MCP:

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import props_common as P; importlib.reload(P)
    import wpn_firearms as F; importlib.reload(F)
    import wpn_pickups as W; importlib.reload(W)
    print(W.run_pickups())     # build + export the 12 pickups, write pickups.json, save the .blend
    print(W.run_held())        # build + export phone + parachute_canopy, merge them into weapons.json, save
    print(W.build_held(preview=True))   # QA only: tint cells shown as orange / white (never exported)

Pickups: path pickups/<id>, single part `body`, origin = bounding-box centre (they float and spin about the
vertical axis in game, so every side is dressed). Held items: path weapons/<id>, entries in weapons.json written
with wpn_firearms.describe (same format as the other weapons). Original generic designs, no brands / logos.
"""
import contextlib
import io
import json
import math
import os

import bpy
from mathutils import Vector

import gta_kit as K
import props_common as P
import wpn_firearms as F

PICKUPS = ["pickup_health", "pickup_armor", "pickup_ammo", "pickup_cash", "pickup_cash_big", "pickup_parachute",
           "pickup_scuba", "pickup_snack", "pickup_wrench", "pickup_bribe", "pickup_weapon_crate", "pickup_treasure"]
HELD = ["phone", "parachute_canopy"]
PICKUP_MANIFEST = os.path.join(K.PROJECT, "gta", "resources", "data", "manifests", "pickups.json")
EXTRA_POS = {"pickup_treasure": (92.0, F.ROW_Y, 0.0)}   # not in wpn_firearms.ROW_ORDER
QA_ORIGIN = (-22.0, F.ROW_Y, 1.0)
REG = {}
PREVIEW = {}   # colour substitutions for QA builds only (tint cells are white in the atlas)


class GB2(F.GB):
    """wpn_firearms.GB with this module's own preview colour map."""

    def paint(self, faces, color):
        K.MB.paint(self, faces, PREVIEW.get(color, color))


def pickup(pid, notes=""):
    def deco(fn):
        REG[pid] = {"id": pid, "fn": fn, "glb": "pickups/" + pid, "notes": notes}
        return fn
    return deco


# =========================================================================== helpers
def center(mb):
    """Move the geometry so the bounding-box centre sits on the origin; returns the applied offset."""
    vs = list(mb.bm.verts)
    lo = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
    hi = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
    c = (lo + hi) * 0.5
    for v in vs:
        v.co -= c
    return c


def plus_pts(L, a):
    h = a * 0.5
    return [(-h, L), (h, L), (h, h), (L, h), (L, -h), (h, -h), (h, -L), (-h, -L), (-h, -h), (-L, -h), (-L, h),
            (-h, h)]


def star_pts(n, R, r, phase=90.0):
    out = []
    for k in range(2 * n):
        a = math.radians(phase) + k * math.pi / n
        rr = R if k % 2 == 0 else r
        out.append((math.cos(a) * rr, math.sin(a) * rr))
    return out


def plate_xz(mb, pts, thick, color, y=0.0, ch=0.0):
    """GB.plate for an outline given in the XZ plane (faces +-Y), centred on y."""
    with mb.at((0.0, y, 0.0), rot=(0.0, 0.0, 90.0)):
        mb.plate([(-x, z) for x, z in pts], thick, color, ch=ch)


def bundle(mb, pos, L, Wd, H, rz=0.0, band="yellow", detail=True, top="green", side="stucco_mint"):
    """Banded bundle of banknotes, long side along X."""
    with mb.at(pos, rot=(0.0, 0.0, rz)):
        mb.box((L, Wd, H), (0, 0, 0), side, colors={"+z": top, "-z": top})
        if band:
            mb.box((0.045, Wd + 0.008, H + 0.008), (0, 0, 0), band)
        if detail:
            for sx in (-1, 1):
                mb.box((L * 0.24, Wd * 0.6, 0.003), (sx * L * 0.3, 0, H * 0.5 + 0.0015), "green_dark")


def rim_frame(mb, L, Wd, t, h, pos, color):
    """Rectangular frame (4 boxes) of outer size L x Wd, bar width t, height h, centred on pos."""
    x, y, z = pos
    for sy in (-1, 1):
        mb.box((L, t, h), (x, y + sy * (Wd - t) * 0.5, z), color)
    for sx in (-1, 1):
        mb.box((t, Wd - 2 * t, h), (x + sx * (L - t) * 0.5, y, z), color)


def stats_line(name):
    st = P.stats(name)
    flag = ""
    if st["inverted"]:
        flag += " !!inverted=%d" % st["inverted"]
    if st["degenerate"]:
        flag += " !!degenerate=%d" % st["degenerate"]
    return "%-20s tris=%4d size=%s min=%s parts=%s markers=%s%s" % (name, st["tris"], st["size"], st["min"],
                                                                       st["parts"], st["markers"], flag)


# =========================================================================== PICKUPS
@pickup("pickup_health", "White med-kit case, raised GREEN plus on front, back and both ends (no red cross), "
                         "grey lid seam, carry handle on top.")
def b_health(mb):
    Wh, G = "white", "green"
    mb.hull([(-0.085, 0.0, 0.205, 0.14, 0.025), (-0.07, 0.0, 0.22, 0.155, 0.03), (0.07, 0.0, 0.22, 0.155, 0.03),
             (0.085, 0.0, 0.205, 0.14, 0.025)], Wh)
    with mb.at((0.0, 0.0, 0.1), rot=(90.0, 0.0, 0.0)):
        mb.hull([(-0.006, 0.0, 0.226, 0.091, 0.022), (0.006, 0.0, 0.226, 0.091, 0.022)], "gray_light")
    mb.prism(plus_pts(0.085, 0.056), 0.012, G, plane="XZ", pos=(0, 0.089, -0.02), caps=(False, True))
    mb.prism(plus_pts(0.085, 0.056), 0.012, G, plane="XZ", pos=(0, -0.089, -0.02), caps=(True, False))
    mb.prism(plus_pts(0.05, 0.034), 0.012, G, plane="YZ", pos=(0.224, 0, -0.02), caps=(False, True))
    mb.prism(plus_pts(0.05, 0.034), 0.012, G, plane="YZ", pos=(-0.224, 0, -0.02), caps=(True, False))
    P.ttube(mb, [(-0.085, 0, 0.15), (-0.075, 0, 0.205), (-0.045, 0, 0.222), (0.045, 0, 0.222), (0.075, 0, 0.205),
                 (0.085, 0, 0.15)], 0.013, "charcoal", segs=6)
    for sx in (-1, 1):
        mb.box((0.034, 0.04, 0.016), (sx * 0.085, 0, 0.158), "gray_mid")
        mb.box((0.032, 0.012, 0.03), (sx * 0.14, 0.088, 0.1), "gray_mid")


@pickup("pickup_armor", "Ballistic vest: police_blue front / back panels with neck and arm openings, navy shoulder "
                        "straps, side cummerbund and three mag pouches, reflective chest / back strips, gold badge.")
def b_armor(mb):
    B, N, C = "police_blue", "navy", "charcoal"
    front = [(-0.19, -0.23), (0.19, -0.23), (0.2, 0.02), (0.16, 0.08), (0.13, 0.13), (0.125, 0.23), (0.065, 0.23),
             (0.04, 0.17), (0.0, 0.15), (-0.04, 0.17), (-0.065, 0.23), (-0.125, 0.23), (-0.13, 0.13), (-0.16, 0.08),
             (-0.2, 0.02)]
    back = [(x, (0.205 if abs(x) < 0.05 and z < 0.23 else z)) for x, z in front]
    plate_xz(mb, front, 0.055, B, y=0.045, ch=0.012)
    plate_xz(mb, back, 0.055, B, y=-0.045, ch=0.012)
    mb.box((0.37, 0.04, 0.24), (0, 0, -0.11), C)
    mb.box((0.24, 0.04, 0.16), (0, 0, 0.09), C)
    for sx in (-1, 1):
        mb.box((0.03, 0.13, 0.19), (sx * 0.192, 0, -0.125), N)
        mb.box((0.062, 0.14, 0.026), (sx * 0.095, 0, 0.222), N)
    for px in (-0.105, 0.0, 0.105):
        mb.box((0.08, 0.036, 0.1), (px, 0.0905, -0.13), N)
        mb.box((0.084, 0.042, 0.032), (px, 0.092, -0.07), C)
    mb.box((0.2, 0.008, 0.045), (0, 0.0765, 0.03), "gray_light")
    mb.box((0.27, 0.008, 0.06), (0, -0.0765, 0.04), "gray_light")
    P.octa(mb, 0.022, (-0.085, 0.077, 0.1), "gold", scale=(1.0, 0.35, 1.2))


@pickup("pickup_ammo", "Olive ammo can with the lid hinged open, two rows of big brass rounds (copper tips) "
                       "standing in the packing, latch lever, carry handle and yellow stencil labels.")
def b_ammo(mb):
    O, I = "olive", "military_green"
    L, Wd, H, t = 0.34, 0.16, 0.2, 0.012
    mb.box((L, Wd, t), (0, 0, t * 0.5), O)
    for sy in (-1, 1):
        mb.box((L, t, H), (0, sy * (Wd - t) * 0.5, H * 0.5), O, colors={("-y" if sy > 0 else "+y"): I})
        P.xbox(mb, (0.15, 0.004, 0.03), (-0.04 * sy, sy * (Wd * 0.5 + 0.002), 0.06), "yellow_dark",
               skip=(("-y",) if sy > 0 else ("+y",)), base=True)
    for sx in (-1, 1):
        mb.box((t, Wd - 2 * t, H), (sx * (L - t) * 0.5, 0, H * 0.5), O, colors={("-x" if sx > 0 else "+x"): I})
        P.xbox(mb, (0.004, 0.08, 0.025), (sx * (L * 0.5 + 0.002), 0, 0.07), "yellow_dark",
               skip=(("-x",) if sx > 0 else ("+x",)), base=True)
    mb.box((L - 2 * t, Wd - 2 * t, 0.118), (0, 0, t + 0.059), "cardboard")
    prof = [(0.013, 0.0), (0.013, 0.078), (0.008, 0.091), (0.0, 0.115)]
    for ix in range(4):
        for iy in (-1, 1):
            with mb.at((-0.105 + ix * 0.07 + (0.012 if iy > 0 else 0.0), iy * 0.033, 0.128)):
                P.lathe(mb, prof, "brass", segs=5, colors=["brass", "brass", "copper"], cap0=False, smooth=False)
    # lid hinged on the back top edge, opened 112 deg
    with mb.at((0, -Wd * 0.5, H), rot=(112.0, 0.0, 0.0)):
        mb.box((L + 0.008, Wd + 0.008, 0.026), (0, Wd * 0.5, 0.013), O, colors={"-z": I})
        mb.box((0.13, 0.026, 0.01), (0, Wd * 0.5, 0.031), "steel_dark")
        for sx in (-1, 1):
            mb.box((0.016, 0.03, 0.016), (sx * 0.065, Wd * 0.5, 0.031), "steel_dark")
    mb.box((0.03, 0.012, 0.075), (0, Wd * 0.5 + 0.006, H - 0.035), "steel_dark")


@pickup("pickup_cash", "Three slightly offset bundles of green banknotes with yellow paper bands, '$' printed on "
                       "the middle band (front and back).")
def b_cash(mb):
    L, Wd, H = 0.34, 0.155, 0.042
    for k, (dx, dy, rz) in enumerate(((0.0, 0.0, 0.0), (0.008, -0.006, 4.0), (-0.006, 0.004, -3.0))):
        bundle(mb, (dx, dy, H * (k + 0.5)), L, Wd, H, rz)
    with mb.at((0.008, -0.006, H * 1.5), rot=(0.0, 0.0, 4.0)):
        P.text(mb, "$", (0.0, Wd * 0.5 + 0.004, 0.0), height=0.034, color="green_dark", depth=0.003)
        P.text(mb, "$", (0.0, -Wd * 0.5 - 0.004, 0.0), height=0.034, color="green_dark", depth=0.003,
               rot=(0.0, 0.0, 180.0))


@pickup("pickup_cash_big", "Open black attache case (aluminium rims, red lining) packed with 8 banded bundles, two "
                           "more strapped in the lid, handle and latches on the front.")
def b_cash_big(mb):
    Bk, Al = "leather_black", "aluminum"
    L, Wd, Hb = 0.48, 0.33, 0.085
    mb.box((L, Wd, Hb), (0, 0, Hb * 0.5), Bk, bevel=0.008, colors={"+z": "red_dark"})
    rim_frame(mb, L + 0.006, Wd + 0.006, 0.014, 0.018, (0, 0, Hb - 0.005), Al)
    bl, bw, bh = 0.205, 0.068, 0.046
    for ix in (-1, 1):
        for iy in range(4):
            bundle(mb, (ix * 0.108, -0.111 + iy * 0.074, Hb - 0.012), bl, bw, bh, detail=(iy % 2 == 0))
    with mb.at((0, -Wd * 0.5, Hb), rot=(100.0, 0.0, 0.0)):
        mb.box((L, Wd, 0.05), (0, Wd * 0.5, 0.025), Bk, colors={"-z": "red_dark"}, bevel=0.008)
        rim_frame(mb, L + 0.006, Wd + 0.006, 0.014, 0.016, (0, Wd * 0.5, 0.004), Al)
        for ix in (-1, 1):
            bundle(mb, (ix * 0.108, Wd * 0.5, -0.024), bl, bw, bh)
        mb.box((L - 0.05, 0.03, 0.006), (0, Wd * 0.5, -0.049), "charcoal")
    y0 = Wd * 0.5
    P.ttube(mb, [(-0.065, y0 - 0.004, 0.05), (-0.055, y0 + 0.035, 0.05), (0.055, y0 + 0.035, 0.05),
                 (0.065, y0 - 0.004, 0.05)], 0.011, Bk, segs=6)
    for sx in (-1, 1):
        mb.box((0.026, 0.012, 0.026), (sx * 0.065, y0 + 0.004, 0.05), Al)
        mb.box((0.032, 0.01, 0.03), (sx * 0.16, y0 + 0.004, Hb - 0.014), Al)


@pickup("pickup_parachute", "Packed parachute rig: navy main + reserve containers with orange flaps, padded back "
                            "panel, black harness (main lift webs, chest strap with steel buckle, leg loops), "
                            "red ripcord handle and an orange pilot-chute handle.")
def b_parachute(mb):
    N, O, Bk = "navy", "orange", "black"
    mb.hull([(-0.085, 0.0, 0.15, 0.2, 0.035), (-0.07, 0.0, 0.165, 0.215, 0.045), (0.06, 0.0, 0.165, 0.215, 0.045),
             (0.075, 0.0, 0.15, 0.2, 0.035)], N)
    mb.hull([(-0.075, 0.25, 0.135, 0.035, 0.02), (-0.065, 0.25, 0.145, 0.045, 0.025), (0.055, 0.25, 0.145, 0.045, 0.025),
             (0.065, 0.25, 0.135, 0.035, 0.02)], N)
    mb.box((0.25, 0.01, 0.17), (0, -0.088, -0.04), O)
    mb.box((0.03, 0.012, 0.36), (0, -0.09, -0.005), N)
    mb.box((0.2, 0.06, 0.01), (0, -0.01, 0.297), O)
    mb.box((0.3, 0.026, 0.4), (0, 0.086, 0.0), "charcoal")
    for sx in (-1, 1):
        mb.box((0.045, 0.014, 0.52), (sx * 0.08, 0.104, 0.02), Bk)
        mb.box((0.045, 0.1, 0.014), (sx * 0.08, 0.06, 0.29), Bk)
        mb.box((0.032, 0.02, 0.05), (sx * 0.08, 0.113, 0.2), "steel")
        P.ttube(mb, [(sx * 0.08, 0.104, -0.23), (sx * 0.085, 0.15, -0.27), (sx * 0.13, 0.17, -0.285),
                     (sx * 0.175, 0.13, -0.265), (sx * 0.17, 0.09, -0.22)], 0.011, Bk, segs=4)
    mb.box((0.22, 0.012, 0.035), (0, 0.113, 0.07), Bk)
    mb.box((0.042, 0.02, 0.042), (0, 0.119, 0.07), "steel")
    mb.box((0.04, 0.026, 0.03), (0.08, 0.12, -0.02), "red")
    P.octa(mb, 0.024, (0.13, -0.07, -0.225), O)


@pickup("pickup_scuba", "Yellow scuba tank (rubber boot, white label band, black cam band with buckle), chrome "
                        "valve with black hand wheel, regulator first stage, hoses to the second stage and to the "
                        "pressure gauge.")
def b_scuba(mb):
    Y = "yellow"
    st = [(-0.27, 0.07), (-0.262, 0.086), (-0.2, 0.086), (-0.03, 0.086), (0.03, 0.086), (0.12, 0.086), (0.18, 0.072),
          (0.215, 0.045), (0.232, 0.022)]
    mb.lathe(st, Y, segs=10, axis="Z", c=(0.0, 0.0), ring_colors=["rubber", "rubber", Y, "white", Y, Y, Y, Y],
             cap_colors=("rubber", "chrome"))
    mb.lathe([(0.03, 0.0915), (0.075, 0.0915)], "black", segs=10, axis="Z", c=(0.0, 0.0), caps=False)
    mb.box((0.03, 0.016, 0.05), (0, -0.095, 0.052), "steel")
    mb.zcyl(0.02, 0.226, 0.262, 0, 0, "chrome", segs=8)
    mb.box((0.05, 0.042, 0.036), (0, 0, 0.272), "chrome")
    mb.xcyl(0.026, 0.025, 0.042, 0, 0.272, "black", segs=8)
    mb.ycyl(0.022, 0.02, 0.07, 0.272, "chrome", segs=8)
    P.ttube(mb, [(0.0, 0.07, 0.272), (0.03, 0.115, 0.23), (0.095, 0.125, 0.13), (0.115, 0.11, 0.02)], 0.009,
            "black", segs=5)
    mb.hull([(0.09, -0.005, 0.028, 0.03, 0.012, 0.115), (0.135, -0.005, 0.028, 0.03, 0.012, 0.115)], "black")
    mb.ycyl(0.02, 0.134, 0.14, -0.005, "yellow", x=0.115, segs=8)
    mb.box((0.04, 0.026, 0.018), (0.08, 0.112, -0.005), "charcoal")
    P.ttube(mb, [(-0.015, 0.06, 0.262), (-0.07, 0.11, 0.2), (-0.115, 0.105, 0.08), (-0.12, 0.09, -0.04)], 0.008,
            "black", segs=5)
    mb.ycyl(0.036, 0.07, 0.1, -0.075, "black", x=-0.12, segs=10, cap_color="white")
    mb.box((0.004, 0.032, 0.002), (-0.12, 0.1005, -0.068), "red", rot=(0.0, 35.0, 0.0))


@pickup("pickup_snack", "Burger (sesame bun, lettuce, patty, cheese corners, tomato) and a red-banded soda cup "
                        "with lid and straw on a red tray.")
def b_snack(mb):
    Bun, Bun2 = "wood_light", "tan"
    mb.box((0.44, 0.26, 0.018), (0, 0, 0.009), "red", bevel=0.006)
    with mb.at((-0.1, 0.0, 0.018)):
        P.lathe(mb, [(0.082, 0.0), (0.097, 0.012), (0.101, 0.034)], Bun, segs=10, colors=[Bun2, Bun], smooth=False)
        pts = []
        for k in range(14):
            a = 2.0 * math.pi * k / 14
            r = 0.116 if k % 2 == 0 else 0.101
            pts.append((math.cos(a) * r, math.sin(a) * r))
        mb.prism(pts, 0.008, "leaf_green", plane="XY", pos=(0, 0, 0.038))
        mb.cyl(0.107, 0.028, (0, 0, 0.056), "brown", segs=10, smooth=False)
        mb.box((0.19, 0.19, 0.006), (0, 0, 0.073), "yellow", rot=(0.0, 0.0, 45.0))
        mb.cyl(0.094, 0.012, (0, 0, 0.082), "red", segs=10, smooth=False)
        P.lathe(mb, [(0.096, 0.088), (0.104, 0.103), (0.094, 0.13), (0.064, 0.15), (0.0, 0.158)], Bun, segs=10,
                colors=[Bun2, Bun, Bun, Bun], smooth=False)
        for k, (r, z) in enumerate(((0.072, 0.142), (0.072, 0.142), (0.072, 0.142), (0.04, 0.154), (0.04, 0.154),
                                    (0.082, 0.136), (0.02, 0.158))):
            a = math.radians(40 + k * 101)
            P.octa(mb, 0.008, (math.cos(a) * r, math.sin(a) * r, z + 0.002), "cream", scale=(1.0, 0.55, 0.4),
                   rot=(0.0, 0.0, math.degrees(a)))
    with mb.at((0.125, 0.0, 0.018)):
        P.lathe(mb, [(0.05, 0.0), (0.053, 0.05), (0.058, 0.12), (0.062, 0.17), (0.066, 0.215)], "white", segs=10,
                colors=["white", "red", "red", "white"], smooth=False)
        P.lathe(mb, [(0.0695, 0.209), (0.0705, 0.222), (0.052, 0.232), (0.0, 0.236)], "plastic_white", segs=10,
                smooth=False)
        P.ttube(mb, [(0.012, 0.008, 0.225), (0.03, 0.02, 0.33)], 0.0065, "red", segs=5)
        mb.prism(star_pts(5, 0.022, 0.009), 0.004, "yellow", plane="XZ", pos=(0.0, 0.057, 0.095),
                 caps=(False, True))


def _wrench(mb):
    """Combination wrench in the XZ plane, axis along Z: open jaw at +Z, box end (hex) at -Z."""
    out = [(0.013, -0.12), (0.014, 0.12), (0.03, 0.135), (0.036, 0.16), (0.028, 0.185), (0.012, 0.19), (0.014, 0.165),
           (0.0, 0.155), (-0.014, 0.165), (-0.012, 0.19), (-0.028, 0.185), (-0.036, 0.16), (-0.03, 0.135),
           (-0.014, 0.12), (-0.013, -0.12), (-0.028, -0.13), (-0.036, -0.155), (-0.026, -0.18), (0.0, -0.19),
           (0.026, -0.18), (0.036, -0.155), (0.028, -0.13)]
    mb.prism(out, 0.012, "chrome", plane="XZ")
    hexa = [(math.cos(math.radians(30 + 60 * k)) * 0.0145, -0.155 + math.sin(math.radians(30 + 60 * k)) * 0.0145)
            for k in range(6)]
    mb.prism(hexa, 0.016, "charcoal", plane="XZ")


@pickup("pickup_wrench", "Repair pickup: red toolbox (handle, latches, lid seam) with two crossed chrome "
                         "combination wrenches standing above it.")
def b_wrench(mb):
    R = "red"
    mb.hull([(-0.1, 0.08, 0.19, 0.072, 0.012), (-0.092, 0.08, 0.2, 0.08, 0.016), (0.092, 0.08, 0.2, 0.08, 0.016),
             (0.1, 0.08, 0.19, 0.072, 0.012)], R)
    with mb.at((0.0, 0.0, 0.118), rot=(90.0, 0.0, 0.0)):
        mb.hull([(-0.005, 0.0, 0.204, 0.096, 0.014), (0.005, 0.0, 0.204, 0.096, 0.014)], "red_dark")
    P.ttube(mb, [(-0.09, 0, 0.155), (-0.08, 0, 0.205), (0.08, 0, 0.205), (0.09, 0, 0.155)], 0.012, "black", segs=6)
    for sx in (-1, 1):
        mb.box((0.03, 0.03, 0.014), (sx * 0.09, 0, 0.163), "steel")
        mb.box((0.03, 0.012, 0.035), (sx * 0.12, 0.103, 0.118), "steel")
    for dy, ry in ((0.0075, 42.0), (-0.0075, 138.0)):
        with mb.at((0.0, dy, 0.35), rot=(0.0, ry, 0.0)):
            _wrench(mb)


@pickup("pickup_bribe", "Gold six-point police-style star token with ball tips, raised centre disc with a "
                        "police_blue inlay and a small gold star (same on both faces).")
def b_bribe(mb):
    Gd = "gold"
    R, r = 0.165, 0.088
    plate_xz(mb, star_pts(6, R, r), 0.036, Gd, ch=0.01)
    for k in range(6):
        a = math.radians(90.0 + k * 60.0)
        mb.ico(0.026, (math.cos(a) * (R + 0.012), 0.0, math.sin(a) * (R + 0.012)), Gd, subdiv=1)
    mb.ycyl(0.072, -0.024, 0.024, 0.0, Gd, segs=12, smooth=False)
    mb.ycyl(0.052, -0.03, 0.03, 0.0, "police_blue", segs=12, smooth=False)
    mb.prism(star_pts(5, 0.036, 0.015), 0.07, Gd, plane="XZ")


@pickup("pickup_weapon_crate", "Small generic military crate: green box with olive frame boards and lid, rope "
                               "handles, steel latches, tan stencil star and bars (no text).")
def b_crate(mb):
    G, O, T = "military_green", "olive", "military_tan"
    L, Wd, H = 0.56, 0.32, 0.27
    mb.box((L, Wd, H), (0, 0, H * 0.5), G)
    for sy in (-1, 1):
        y = sy * (Wd * 0.5 + 0.006)
        skip = ("-y",) if sy > 0 else ("+y",)
        for sx in (-1, 1):
            P.xbox(mb, (0.05, 0.012, H), (sx * (L * 0.5 - 0.025), y, 0.0), O, skip=skip, base=True)
        for z in (0.0, H - 0.04):
            P.xbox(mb, (L - 0.1, 0.012, 0.04), (0, y, z), O, skip=skip, base=True)
        ys = sy * (Wd * 0.5 + 0.003)
        mb.prism(star_pts(5, 0.058, 0.023), 0.006, T, plane="XZ", pos=(0, ys, H * 0.5 + 0.006),
                 caps=(sy < 0, sy > 0))
        for bx in (-0.13, 0.13):
            P.xbox(mb, (0.09, 0.006, 0.016), (bx, ys, H * 0.5 - 0.008), T, skip=skip, base=True)
        mb.box((0.035, 0.014, 0.05), (sy * 0.14, sy * (Wd * 0.5 + 0.012), H - 0.01), "steel_dark")
    mb.box((L + 0.016, Wd + 0.016, 0.03), (0, 0, H + 0.015), O)
    for sx in (-1, 1):
        x = sx * (L * 0.5 + 0.004)
        P.ttube(mb, [(x, -0.06, 0.19), (x + sx * 0.03, -0.055, 0.15), (x + sx * 0.04, 0.0, 0.135),
                     (x + sx * 0.03, 0.055, 0.15), (x, 0.06, 0.19)], 0.01, "rope", segs=5)
        for by in (-0.06, 0.06):
            mb.box((0.02, 0.04, 0.04), (x + sx * 0.006, by, 0.19), O)
        P.xbox(mb, (0.006, 0.14, 0.04), (sx * (L * 0.5 + 0.003), 0.0, 0.05), T,
               skip=(("-x",) if sx > 0 else ("+x",)), base=True)


@pickup("pickup_treasure", "Small open treasure chest: wooden body with dark plank seams and brass corners, gold lock "
                           "plate, barrel lid (brass bands) hinged open, heap of gold coins with loose coins, two "
                           "gems and a pearl strand.")
def b_treasure(mb):
    Wd, Wk, Br, Gd = "wood_mid", "wood_dark", "brass", "gold"
    L, W, H = 0.46, 0.3, 0.19
    mb.box((L, W, H), (0, 0, H * 0.5), Wd, colors={"+z": Wk})
    for z in (0.065, 0.128):
        mb.box((L + 0.01, W + 0.01, 0.01), (0, 0, z), Wk)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.03, 0.03, H + 0.004), (sx * (L * 0.5 - 0.009), sy * (W * 0.5 - 0.009), H * 0.5), Br)
    mb.box((0.06, 0.012, 0.075), (0, W * 0.5 + 0.004, H - 0.03), Gd)
    mb.box((0.012, 0.006, 0.026), (0, W * 0.5 + 0.012, H - 0.035), "black")
    arc = [(W * 0.5 + math.cos(math.radians(a)) * W * 0.5, math.sin(math.radians(a)) * 0.105)
           for a in (0, 30, 60, 90, 120, 150, 180)]
    arc2 = [(W * 0.5 + math.cos(math.radians(a)) * (W * 0.5 + 0.007), math.sin(math.radians(a)) * 0.113 - 0.004 *
             (1.0 if a in (0, 180) else 0.0)) for a in (0, 30, 60, 90, 120, 150, 180)]
    with mb.at((0, -W * 0.5, H), rot=(108.0, 0.0, 0.0)):
        mb.prism(arc, L, Wd, plane="YZ", cap_colors=(Wk, Wk), side_colors=[None] * 6 + [Wk])
        for x in (-0.15, 0.15):
            mb.prism(arc2, 0.03, Br, plane="YZ", pos=(x, 0.0, 0.0))
    mb.ico(0.2, (0, 0.0, H - 0.012), Gd, subdiv=2, jitter=0.12, seed=4, scale=(1.08, 0.7, 0.36))
    for (x, y, z, rx, ry) in ((-0.08, 0.03, 0.238, 20, -10), (0.05, -0.04, 0.244, 15, 25), (0.12, 0.05, 0.218, -25, 10),
                              (-0.15, -0.05, 0.212, 10, -30), (0.0, 0.075, 0.236, 30, 0), (0.09, 0.2, 0.003, 0, 0),
                              (0.135, 0.185, 0.012, 0, 25)):
        mb.cyl(0.026, 0.006, (x, y, z), Gd, axis="Z", segs=8, rot=(rx, ry, 0.0), smooth=False)
    P.octa(mb, 0.024, (0.035, 0.02, 0.262), "red_gloss", scale=(1.0, 1.0, 0.8))
    P.octa(mb, 0.02, (-0.1, -0.02, 0.246), "blue_gloss")
    P.ttube(mb, [(-0.05, 0.1, 0.225), (-0.07, 0.158, 0.195), (-0.062, 0.162, 0.13)], 0.008, "white", segs=4)


# =========================================================================== pickups: build / QA / export
def begin_pickup(pid):
    if pid in F.ROW_ORDER:
        return F.begin(pid)
    root = K.begin_asset(pid, "Weapons")
    root.location = EXTRA_POS.get(pid, root.location)
    return root


def build_pickups(ids=None):
    ids = PICKUPS if ids is None else ([ids] if isinstance(ids, str) else ids)
    out = []
    for pid in ids:
        root = begin_pickup(pid)
        mb = GB2()
        REG[pid]["fn"](mb)
        center(mb)
        mb.to_object(root, "body")
        out.append(stats_line(pid))
    return "\n".join(out)


def qa_layout(ids, on=True, cols=4, cell=0.9):
    """Gather assets into a compact grid (front view = from +Y) for QA; on=False restores the row slots."""
    for i, n in enumerate(ids):
        o = bpy.data.objects.get(n)
        if o is None:
            continue
        if on:
            o.location = (QA_ORIGIN[0] + (i % cols) * cell, QA_ORIGIN[1], QA_ORIGIN[2] + (i // cols) * cell)
        elif n in F.ROW_ORDER:
            o.location = F.row_pos(n)
        else:
            o.location = EXTRA_POS.get(n, o.location)
    bpy.context.view_layer.update()
    return "layout " + ("QA" if on else "row")


def _export(root, rel):
    with contextlib.redirect_stdout(io.StringIO()):
        path, size = F.export_glb(root, rel)
    return size


def write_pickup_manifest(ids=None):
    ids = PICKUPS if ids is None else ids
    data = {"assets": []}
    if os.path.exists(PICKUP_MANIFEST):
        with open(PICKUP_MANIFEST, "r", encoding="utf-8") as f:
            data = json.load(f)
    by_id = {e["id"]: e for e in data.get("assets", [])}
    for pid in ids:
        glb = os.path.join(K.MODELS, REG[pid]["glb"].replace("/", os.sep) + ".glb")
        if not os.path.exists(glb) or pid not in bpy.data.objects:
            continue
        st = P.stats(pid)
        by_id[pid] = {"id": pid, "glb": REG[pid]["glb"], "category": "Pickups", "size": st["size"],
                      "tris": st["tris"], "parts": st["parts"], "markers": st["markers"], "origin": "bbox_centre",
                      "bbox_min": st["min"], "bbox_max": st["max"], "notes": REG[pid]["notes"]}
    order = {p: i for i, p in enumerate(PICKUPS)}
    out = {"_comment": ("NEON TIDE pickups (gta/code/world/pickups.gd loads 'pickups/pickup_<kind>'). Single part "
                        "'body', origin = bounding-box centre, Blender asset space (x right, y front, z up; Godot = "
                        "(x, z, -y)). They float and spin about the vertical axis, so every side is dressed."),
           "assets": sorted(by_id.values(), key=lambda e: order.get(e["id"], 99))}
    os.makedirs(os.path.dirname(PICKUP_MANIFEST), exist_ok=True)
    with open(PICKUP_MANIFEST, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return len(out["assets"])


def run_pickups(ids=None, save=True):
    global PREVIEW
    PREVIEW = {}
    ids = PICKUPS if ids is None else ids
    rep = build_pickups(ids)
    sizes = ["%s %d B" % (pid, _export(bpy.data.objects[pid], REG[pid]["glb"])) for pid in ids]
    n = write_pickup_manifest()
    if save:
        K.save_master()
    return rep + "\nexported: " + ", ".join(sizes) + "\npickups.json entries: %d" % n


# =========================================================================== HELD ITEMS
def _rrect(w, h, r, n=2):
    pts = []
    for cx, cz, a0 in ((w * 0.5 - r, h * 0.5 - r, 0.0), (-w * 0.5 + r, h * 0.5 - r, 90.0),
                       (-w * 0.5 + r, -h * 0.5 + r, 180.0), (w * 0.5 - r, -h * 0.5 + r, 270.0)):
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def build_phone():
    root = F.begin("phone")
    mb = GB2()
    Wd, T, H = 0.075, 0.009, 0.15
    c = 0.0012
    h = T * 0.5
    out = _rrect(Wd, H, 0.009)
    out_in = _rrect(Wd - 2 * c, H - 2 * c, 0.009 - c)
    scr = _rrect(Wd - 0.007, H - 0.011, 0.0065)
    rings = [[(x, h, z) for x, z in out_in], [(x, h - c, z) for x, z in out], [(x, -h + c, z) for x, z in out],
             [(x, -h, z) for x, z in out_in], [(x, -h, z) for x, z in scr]]
    faces = mb.loft(rings, "steel_dark", closed=True, cap_start=True, cap_end=True,
                    ring_colors=["charcoal", "steel_dark", "black", "black"])
    mb.paint([faces[-2]], "charcoal")
    mb.paint([faces[-1]], "screen_blue")
    # camera bump on the back (+Y), upper corner, two lenses + flash
    mb.box((0.026, 0.0024, 0.03), (0.0175, h + 0.001, 0.053), "black")
    for z in (0.061, 0.045):
        mb.ycyl(0.0058, h + 0.0018, h + 0.0034, z, "gray_dark", x=0.0215, segs=8, cap_color="glass_dark")
    mb.ycyl(0.0022, h + 0.0018, h + 0.0028, 0.053, "white", x=0.0095, segs=6)
    mb.box((0.0016, 0.0035, 0.022), (-Wd * 0.5 - 0.0004, 0.0, 0.035), "steel_dark")
    mb.box((0.0016, 0.0035, 0.013), (Wd * 0.5 + 0.0004, 0.0, 0.042), "steel_dark")
    mb.to_object(root, "body")
    return root


def _interp(pts, x):
    for i in range(len(pts) - 1):
        x0, z0 = pts[i]
        x1, z1 = pts[i + 1]
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0) if x1 > x0 else 0.0
            return z0 + (z1 - z0) * t
    return pts[-1][1] if x > pts[-1][0] else pts[0][1]


def build_canopy():
    """Ram-air canopy: 8 cells (9 ribs) on an 8 m radius arc, projected span 7.5, chord 3.0, open leading edge,
    double-sided skins, tint_a with a tint_b centre stripe and stabilisers, 16 lines to the riser points."""
    root = F.begin("parachute_canopy")
    mb = GB2()
    A, B = "tint_a", "tint_b"
    # half = 3.636 at the reference surface puts the outermost top-skin points at x = +-3.75 (span 7.5)
    R, half, chord, cells = 8.0, 3.636, 3.0, 8
    C = Vector((0.0, -0.6, 5.5))
    top = [(0.0, -0.03), (0.05, 0.15), (0.18, 0.25), (0.4, 0.24), (0.68, 0.15), (1.0, 0.0)]
    bot = [(0.06, -0.19), (0.28, -0.2), (0.6, -0.13), (1.0, 0.0)]
    phimax = math.asin(half / R)
    ribs = [phimax * (2.0 * i / cells - 1.0) for i in range(cells + 1)]

    def pt(phi, xi, z):
        u = Vector((math.sin(phi), 0.0, math.cos(phi)))
        return C + (u - Vector((0.0, 0.0, 1.0))) * R + Vector((0.0, chord * (0.5 - xi), 0.0)) + u * z

    # top skin with billowed mid-cell stations
    stations = []
    for i in range(cells):
        stations.append((ribs[i], 0.0))
        stations.append(((ribs[i] + ribs[i + 1]) * 0.5, 1.0))
    stations.append((ribs[-1], 0.0))
    grid = [[pt(phi, xi, z * (1.0 + 0.28 * bl)) for xi, z in top] for phi, bl in stations]
    mid = len(stations) // 2
    for j in range(len(stations) - 1):
        col = B if j in (mid - 1, mid) else A
        for k in range(len(top) - 1):
            mb.quad(grid[j][k], grid[j][k + 1], grid[j + 1][k + 1], grid[j + 1][k], col, double=True)
    # bottom skin (open in front of the first bottom point)
    gb = [[pt(phi, xi, z) for xi, z in bot] for phi in ribs]
    for j in range(cells):
        for k in range(len(bot) - 1):
            mb.quad(gb[j][k], gb[j][k + 1], gb[j + 1][k + 1], gb[j + 1][k], A, double=True)
    # ribs (airfoil walls between the cells)
    for i, phi in enumerate(ribs):
        poly = [pt(phi, xi, z) for xi, z in top] + [pt(phi, xi, z) for xi, z in reversed(bot[:-1])]
        mb.poly(poly, A)
        mb.poly(list(reversed(poly)), A)
    # stabiliser panels under the tips
    for phi in (ribs[0], ribs[-1]):
        a = pt(phi, 0.2, _interp(bot, 0.2))
        b = pt(phi, 0.78, _interp(bot, 0.78))
        u = Vector((math.sin(phi), 0.0, math.cos(phi)))
        c = pt(phi, 0.6, _interp(bot, 0.6)) - u * 0.62
        mb.poly([a, b, c], B)
        mb.poly([c, b, a], B)
    # 16 suspension lines (A and C rows on the 8 outer ribs) converging on the riser points
    for i, phi in enumerate(ribs):
        if i == cells // 2:
            continue
        side = -1.0 if i < cells // 2 else 1.0
        for xi in (0.15, 0.66):
            P.ttube(mb, [(side * 0.2, 0.0, 0.0), tuple(pt(phi, xi, _interp(bot, xi)))], 0.009, "gray_mid", segs=3,
                    caps=False)
    mb.to_object(root, "mesh")
    F.mk(root, "riser_l", (-0.2, 0.0, 0.0))
    F.mk(root, "riser_r", (0.2, 0.0, 0.0))
    return root


HELD_INFO = {
    "phone": dict(path="weapons/phone",
                  notes="Smartphone 0.075 x 0.009 x 0.15 standing upright in the XZ plane, origin = centre. Screen "
                        "(screen_blue, glows) faces -Y toward the holder, camera bump on the back (+Y) upper +X "
                        "corner, buttons on both sides. Part body."),
    "parachute_canopy": dict(path="weapons/parachute_canopy",
                             notes="Ram-air canopy, 8 cells, projected span 7.5 (X) x chord 3.0 (Y) on an 8 m arc, "
                                   "open leading edge toward +Y, double-sided. tint_a = canopy, tint_b = centre "
                                   "stripe + stabilisers (player_moves.gd sets orange / white). 16 lines converge on "
                                   "the riser points (+-0.2, 0, 0); origin = the jumper's shoulders, canopy centre "
                                   "(0, -0.6, 5.5). Single part mesh; markers riser_l / riser_r."),
}
HELD_BUILD = {"phone": build_phone, "parachute_canopy": build_canopy}


def _register_held():
    """(Re-)register the held items in wpn_firearms.REG so F.describe writes the standard weapons.json format."""
    for n in HELD:
        F.REG[n] = dict(id=n, glb=HELD_INFO[n]["path"], category="Weapons", length=None,
                        notes=HELD_INFO[n]["notes"], build=HELD_BUILD[n])


def build_held(ids=None, preview=False):
    global PREVIEW
    ids = HELD if ids is None else ([ids] if isinstance(ids, str) else ids)
    PREVIEW = {"tint_a": "orange", "tint_b": "white"} if preview else {}
    out = []
    try:
        for n in ids:
            HELD_BUILD[n]()
            out.append(stats_line(n) + ("  [PREVIEW colours]" if preview else ""))
    finally:
        PREVIEW = {}
    return "\n".join(out)


def write_weapons_entries(ids=None):
    """Merge only the held-item entries into weapons.json (every other entry is kept untouched)."""
    ids = HELD if ids is None else ids
    _register_held()
    with open(F.MANIFEST, "r", encoding="utf-8") as f:
        data = json.load(f)
    by_id = {e["id"]: e for e in data.get("assets", [])}
    for n in ids:
        e = F.describe(n)
        if e is not None:
            by_id[n] = e
    order = F.ROW_ORDER
    data["assets"] = sorted(by_id.values(), key=lambda e: (order.index(e["id"]) if e["id"] in order else 999,
                                                           e["id"]))
    with open(F.MANIFEST, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return len(data["assets"])


def run_held(ids=None, save=True):
    ids = HELD if ids is None else ids
    rep = build_held(ids, preview=False)
    sizes = ["%s %d B" % (n, _export(bpy.data.objects[n], HELD_INFO[n]["path"])) for n in ids]
    n = write_weapons_entries(ids)
    if save:
        K.save_master()
    return rep + "\nexported: " + ", ".join(sizes) + "\nweapons.json entries: %d" % n
