# -*- coding: utf-8 -*-
"""wpn_melee_misc - NEON TIDE melee weapons, throwables / projectiles and weapon attachments
(tools/blender/SPEC_WEAPONS.md, P1 "Melee and throwables" + "Attachments").

Run inside Blender through the MCP (after wpn_firearms, which owns the shared helpers and the registry):

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import gta_kit as K; importlib.reload(K)
    import wpn_firearms as F; importlib.reload(F)
    import wpn_melee_misc as M; importlib.reload(M)
    print(F.build(M.NAMES, export=True))

Melee weapons: origin at the grip, business end toward +Y, single part `body`, extra marker `tip` (+ `hand_l` on
two-handed ones). Attachments: origin at the mount point (see each note), part `body`; they use the same tint cells
as the weapons (tint_a_metal / tint_b), so Godot must apply the weapon's tint instance parameters to them as well.
"""
import math

import gta_kit as K
import wpn_firearms as F
from wpn_firearms import GB, A, B, asset, begin, mk

NAMES = ["knife", "bat", "crowbar", "nightstick", "grenade", "rocket", "grenade_40mm",
         "att_suppressor", "att_suppressor_large", "att_scope_reddot", "att_scope_4x", "att_scope_sniper",
         "att_flashlight", "att_grip", "att_laser"]


# =========================================================================== MELEE
@asset("knife", "weapons/knife", length=0.30,
       notes="Combat knife: clip-point blade toward +Y, cutting edge down (-Z). Origin = handle centre. Marker tip.")
def build_knife():
    root = begin("knife")
    mb = GB()
    # blade body, thin ground edge, fuller, sawback notches
    mb.plate([(0.064, 0.016), (0.185, 0.016), (0.215, 0.008), (0.242, -0.004), (0.226, -0.008), (0.196, -0.012),
              (0.064, -0.012)], 0.0045, "steel", ch=0.0015)
    mb.plate([(0.064, -0.0115), (0.196, -0.0115), (0.226, -0.0075), (0.2425, -0.0042), (0.224, -0.0145),
              (0.196, -0.019), (0.064, -0.019)], 0.0016, "chrome")
    mb.box((0.0058, 0.090, 0.004), (0, 0.122, 0.006), "steel_dark")
    mb.row(3, (0, 0.086, 0.0158), (0, 0.108, 0.0158), (0.0056, 0.005, 0.004), "steel_dark")
    # guard
    mb.plate([(0.057, -0.029), (0.066, -0.031), (0.066, 0.027), (0.057, 0.025)], 0.015, "steel_dark", ch=0.002)
    # wrapped handle (banded) + pommel
    ys = [-0.050, -0.032, -0.014, 0.004, 0.022, 0.040, 0.058]
    st = []
    for y in ys:
        t = abs((y - 0.004) / 0.054)
        st.append((y, -0.001, 0.0115 - 0.0015 * t, 0.0155 - 0.002 * t, 0.005))
    mb.hull(st, B, ring_colors=[B if i % 2 == 0 else "charcoal" for i in range(len(ys) - 1)])
    mb.hull([(-0.061, -0.001, 0.009, 0.012, 0.004), (-0.050, -0.001, 0.0105, 0.0145, 0.004)], "steel_dark")
    mb.to_object(root, "body")
    mk(root, "tip", (0, 0.242, -0.004))
    return root


@asset("bat", "weapons/bat", length=0.85,
       notes="Baseball bat along +Y, taped handle; origin on the axis at the grip, 7 cm above the knob end. "
             "Markers: tip (barrel end), hand_l (second hand, 10 cm up the handle).")
def build_bat():
    root = begin("bat")
    mb = GB()
    Wd, T = "wood_light", "leather_black"
    st = [(-0.070, 0.015), (-0.066, 0.024), (-0.056, 0.024), (-0.049, 0.0145), (0.010, 0.0130), (0.190, 0.0150),
          (0.400, 0.0240), (0.416, 0.0248), (0.560, 0.0320), (0.720, 0.0330), (0.762, 0.0290), (0.780, 0.0170)]
    cols = [Wd, Wd, Wd, T, T, Wd, "red_dark", Wd, Wd, Wd, Wd]
    mb.lathe(st, Wd, segs=8, ring_colors=cols, cap_colors=("wood_mid", "wood_mid"))
    mb.to_object(root, "body")
    mk(root, "tip", (0, 0.780, 0))
    mk(root, "hand_l", (0, 0.100, 0))
    return root


@asset("crowbar", "weapons/crowbar", length=0.65,
       notes="Hex-bar crowbar: chisel end behind the hand, gooseneck claw at +Y curling up (+Z) and back. Red paint "
             "worn to steel at both ends. Origin on the shaft. Markers: tip (front of the hook), hand_l.")
def build_crowbar():
    root = begin("crowbar")
    mb = GB()
    cyc, czc, rr = 0.455, 0.050, 0.050
    pts = [(-0.135, -0.011, 1.0, 1.7, 0.18), (-0.102, -0.003, 1.0, 1.35, 0.6), (-0.072, 0.0), (0.455, 0.0)]
    for a in (-60, -30, 0, 30, 60, 90, 120):
        r = math.radians(a)
        pts.append((cyc + math.cos(r) * rr, czc + math.sin(r) * rr))
    r = math.radians(150.0)
    ey, ez = cyc + math.cos(r) * rr, czc + math.sin(r) * rr
    pts.append((ey, ez, 1.0, 1.4, 0.6))
    pts.append((ey - 0.5 * 0.032, ez - 0.866 * 0.032, 1.0, 1.75, 0.2))
    n = len(pts) - 1
    cols = ["red"] * n
    cols[0] = cols[1] = "steel"
    cols[-1] = cols[-2] = "steel"
    mb.bar_yz(pts, 0.0105, "red", segs=6, colors=cols)
    mb.to_object(root, "body")
    mk(root, "tip", (0, 0.505, 0.050))
    mk(root, "hand_l", (0, 0.130, 0))
    return root


@asset("nightstick", "weapons/nightstick", length=0.60,
       notes="Side-handle police baton. Origin = centre of the SIDE HANDLE (held like a pistol grip, handle axis = Z); "
             "the main shaft runs along Y at z=0.062 (short end behind the hand). Marker tip = front end of the shaft.")
def build_nightstick():
    root = begin("nightstick")
    mb = GB()
    zs = 0.062
    st = [(-0.135, 0.011), (-0.128, 0.0165), (-0.110, 0.0165), (-0.108, 0.0155), (0.440, 0.0155), (0.442, 0.0165),
          (0.458, 0.0165), (0.465, 0.011)]
    mb.lathe(st, "black", segs=8, c=(0.0, zs),
             ring_colors=["charcoal", "charcoal", "charcoal", "black", "charcoal", "charcoal", "charcoal"])
    sh = [(-0.068, 0.012), (-0.064, 0.019), (-0.056, 0.019), (-0.052, 0.0145), (0.020, 0.0135), (0.030, 0.0165),
          (0.050, 0.0165)]
    mb.lathe(sh, "black", segs=8, axis="Z", c=(0.0, 0.0),
             ring_colors=["charcoal", "charcoal", "charcoal", "rubber", "charcoal", "charcoal"])
    mb.to_object(root, "body")
    mk(root, "tip", (0, 0.465, zs))
    return root


# =========================================================================== THROWABLES / PROJECTILES
@asset("grenade", "weapons/grenade", length=0.10,
       notes="Frag grenade, origin = body centre. Fuse up (+Z), safety lever on the +Y side, pin ring on -X.")
def build_grenade():
    root = begin("grenade")
    mb = GB()
    G, G2 = "military_green", "olive"
    st = [(-0.034, 0.012), (-0.030, 0.022), (-0.016, 0.0295), (0.000, 0.0305), (0.016, 0.0285), (0.028, 0.020),
          (0.033, 0.012)]
    mb.lathe(st, G, segs=8, axis="Z", smooth=False, ring_colors=[G, G2, G, G2, G, G2])
    mb.zcyl(0.011, 0.031, 0.047, 0, 0, "steel_dark", segs=8)
    mb.zcyl(0.013, 0.045, 0.051, 0, 0, "steel", segs=8)
    mb.strap([(-0.004, 0.0525), (0.018, 0.0515), (0.030, 0.030), (0.0335, 0.000), (0.031, -0.014)], 0.013, 0.002,
             "steel")
    mb.xcyl(0.0015, -0.018, 0.012, 0.0, 0.040, "steel", segs=4)
    ring = []
    for k in range(7):
        a = 2.0 * math.pi * k / 6
        ring.append((-0.027 + math.cos(a) * 0.010, 0.0, 0.040 + math.sin(a) * 0.010))
    mb.tube(ring, 0.0016, "steel", segs=4)
    mb.to_object(root, "body")
    return root


@asset("rocket", "weapons/rocket", length=0.55,
       notes="Rocket projectile (matches launcher_rocket__rocket_loaded), origin = centre, flies toward +Y. Marker "
             "exhaust at the nozzle, rotated 180 deg about Z so its +Y points backward (trail direction).")
def build_rocket():
    root = begin("rocket")
    mb = GB()
    G = "military_green"
    st = [(-0.275, 0.027), (-0.250, 0.019), (-0.240, 0.028), (0.060, 0.028), (0.100, 0.040), (0.112, 0.040),
          (0.196, 0.040), (0.240, 0.026), (0.264, 0.012), (0.275, 0.005)]
    cols = ["steel_dark", "steel_dark", "charcoal", G, "hazard_yellow", G, G, G, "steel"]
    mb.lathe(st, G, segs=10, ring_colors=cols, cap_colors=("black", "steel"))
    for ang in (45.0, 135.0, 225.0, 315.0):
        with mb.at(rot=(0, ang, 0)):
            mb.plate([(-0.262, 0.024), (-0.170, 0.024), (-0.222, 0.072), (-0.262, 0.072)], 0.003, "steel_dark")
    mb.to_object(root, "body")
    mk(root, "exhaust", (0, -0.275, 0), rot=(0, 0, 180.0))
    return root


@asset("grenade_40mm", "weapons/grenade_40mm", length=0.10,
       notes="40 mm launcher round: brass case, copper driving band, gold nose. Origin = centre, nose toward +Y.")
def build_grenade_40mm():
    root = begin("grenade_40mm")
    mb = GB()
    st = [(-0.050, 0.0215), (-0.046, 0.0215), (-0.046, 0.0200), (-0.004, 0.0200), (-0.004, 0.0208), (0.004, 0.0208),
          (0.004, 0.0198), (0.022, 0.0190), (0.038, 0.0135), (0.047, 0.0070), (0.050, 0.0030)]
    cols = ["brass", "brass", "brass", "copper", "copper", "copper", "gold", "gold", "gold", "gold"]
    mb.lathe(st, "brass", segs=8, ring_colors=cols, cap_colors=("brass", "gold"))
    mb.disc(0.006, (0, -0.0506, 0), "steel", axis="Y", segs=6, flip=True)
    mb.to_object(root, "body")
    return root


# =========================================================================== ATTACHMENTS
@asset("att_suppressor", "weapons/att/att_suppressor",
       notes="Suppressor dia 0.04 x 0.16. Origin = rear face centre (put it on the weapon's 'suppressor' marker), "
             "extends +Y. Marker muzzle = new muzzle position.")
def build_att_suppressor():
    root = begin("att_suppressor")
    mb = GB()
    st = [(0.000, 0.0125), (0.010, 0.0125), (0.012, 0.020), (0.118, 0.020), (0.126, 0.020), (0.150, 0.020),
          (0.160, 0.0165)]
    mb.lathe(st, A, segs=10, ring_colors=["steel_dark", "steel_dark", A, "black", A, A],
             cap_colors=("steel_dark", "black"))
    mb.to_object(root, "body")
    mk(root, "muzzle", (0, 0.160, 0))
    return root


@asset("att_suppressor_large", "weapons/att/att_suppressor_large",
       notes="Large two-stage suppressor dia 0.05 x 0.22. Origin = rear face centre, extends +Y. Marker muzzle.")
def build_att_suppressor_large():
    root = begin("att_suppressor_large")
    mb = GB()
    st = [(0.000, 0.014), (0.012, 0.014), (0.014, 0.025), (0.086, 0.025), (0.090, 0.0225), (0.120, 0.0225),
          (0.128, 0.0225), (0.158, 0.0225), (0.166, 0.0225), (0.208, 0.0225), (0.220, 0.0175)]
    cols = ["steel_dark", "steel_dark", A, A, A, "black", A, "black", A, A]
    mb.lathe(st, A, segs=10, ring_colors=cols, cap_colors=("steel_dark", "black"))
    mb.to_object(root, "body")
    mk(root, "muzzle", (0, 0.220, 0))
    return root


@asset("att_scope_reddot", "weapons/att/att_scope_reddot",
       notes="Compact reflex sight. Origin = bottom centre of the clamp (put it on the 'scope' marker), window faces "
             "the shooter (-Y). Lens uses the Glass material; the dot is led_red.")
def build_att_scope_reddot():
    root = begin("att_scope_reddot")
    mb = GB()
    mb.hull([(-0.024, 0.005, 0.014, 0.005, 0.002), (0.024, 0.005, 0.014, 0.005, 0.002)], "steel_dark")
    mb.xcyl(0.0045, 0.012, 0.019, -0.008, 0.005, "steel", segs=6)
    mb.plate([(-0.024, 0.009), (0.026, 0.009), (0.026, 0.016), (0.012, 0.018), (-0.024, 0.018)], 0.030, A, ch=0.002)
    arch = [(-0.015, 0.017), (-0.015, 0.040), (-0.010, 0.046), (0.010, 0.046), (0.015, 0.040), (0.015, 0.017),
            (0.011, 0.017), (0.011, 0.038), (0.008, 0.042), (-0.008, 0.042), (-0.011, 0.038), (-0.011, 0.017)]
    with mb.at((0, 0.016, 0), rot=(0, 0, 90.0)):
        mb.plate(arch, 0.014, A)
    mb.quad((-0.011, 0.016, 0.018), (0.011, 0.016, 0.018), (0.011, 0.016, 0.0415), (-0.011, 0.016, 0.0415), "@Glass",
            double=True)
    mb.box((0.003, 0.0012, 0.003), (0, 0.0152, 0.030), "led_red")
    mb.box((0.014, 0.010, 0.006), (0, -0.015, 0.0205), "black")
    mb.to_object(root, "body")
    return root


def _scope(root, L, zt, r_tube, r_obj, r_eye, base_half, ring_y, knobs):
    """Tube scope on a two-ring mount; origin bottom centre of the base, objective toward +Y."""
    mb = GB()
    h = L * 0.5
    st = [(-h, r_eye), (-h + L * 0.14, r_eye), (-h + L * 0.17, r_tube), (h - L * 0.30, r_tube),
          (h - L * 0.24, r_obj), (h, r_obj)]
    mb.lathe(st, A, segs=8, c=(0.0, zt), ring_colors=["rubber", A, A, A, A], cap_colors=("glass_dark", "glass_dark"))
    # turrets (top elevation, right windage)
    mb.zcyl(knobs, zt + r_tube - 0.002, zt + r_tube + 0.013, 0.0, 0.010, "steel_dark", segs=6)
    mb.xcyl(knobs, r_tube - 0.002, r_tube + 0.013, 0.010, zt, "steel_dark", segs=6)
    # base + two ring blocks
    mb.hull([(-base_half, 0.005, 0.012, 0.005, 0.002), (base_half, 0.005, 0.012, 0.005, 0.002)], "steel_dark")
    rb = r_tube + 0.0045
    for y in (-ring_y, ring_y):
        mb.hull([(y - 0.007, zt, rb, rb, rb * 0.45), (y + 0.007, zt, rb, rb, rb * 0.45)], "steel_dark")
        mb.box((0.012, 0.012, zt - rb - 0.006), (0, y, 0.008 + (zt - rb - 0.006) * 0.5), "steel_dark")
    mb.to_object(root, "body")


@asset("att_scope_4x", "weapons/att/att_scope_4x",
       notes="4x tube scope, 0.20 long, on a two-ring mount. Origin = bottom centre of the base ('scope' marker); "
             "objective toward +Y, optical axis at z=0.040. Marker eye = ocular lens centre.")
def build_att_scope_4x():
    root = begin("att_scope_4x")
    _scope(root, 0.200, 0.040, 0.0125, 0.0185, 0.0165, 0.046, 0.030, 0.0075)
    mk(root, "eye", (0, -0.100, 0.040))
    return root


@asset("att_scope_sniper", "weapons/att/att_scope_sniper",
       notes="Long-range scope, 0.36 long, large objective, turrets. Origin = bottom centre of the base ('scope' "
             "marker); objective toward +Y, optical axis at z=0.046. Marker eye = ocular lens centre.")
def build_att_scope_sniper():
    root = begin("att_scope_sniper")
    _scope(root, 0.360, 0.046, 0.0150, 0.0275, 0.0205, 0.070, 0.050, 0.0095)
    mk(root, "eye", (0, -0.180, 0.046))
    return root


@asset("att_flashlight", "weapons/att/att_flashlight",
       notes="Weapon light. Origin = TOP centre of the clamp (hangs under the barrel from the 'under' marker). "
             "Lens = emis_always_white. Marker light at the lens, +Y forward.")
def build_att_flashlight():
    root = begin("att_flashlight")
    mb = GB()
    zc = -0.024
    mb.hull([(-0.020, -0.006, 0.011, 0.006, 0.002), (0.020, -0.006, 0.011, 0.006, 0.002)], "steel_dark")
    st = [(-0.046, 0.0085), (-0.040, 0.0115), (0.022, 0.0115), (0.030, 0.0165), (0.050, 0.0165), (0.055, 0.0150)]
    mb.lathe(st, A, segs=10, c=(0.0, zc), ring_colors=["rubber", A, A, A, "black"],
             cap_colors=("rubber", "emis_always_white"))
    mb.row(2, (0, -0.012, zc), (0, 0.004, zc), (0.0245, 0.004, 0.012), "black")
    mb.to_object(root, "body")
    mk(root, "light", (0, 0.055, zc))
    return root


@asset("att_grip", "weapons/att/att_grip",
       notes="Vertical foregrip. Origin = TOP centre of the clamp ('under' marker). Marker hand_l = support-hand palm "
             "position on the grip.")
def build_att_grip():
    root = begin("att_grip")
    mb = GB()
    mb.hull([(-0.024, -0.006, 0.012, 0.006, 0.003), (0.024, -0.006, 0.012, 0.006, 0.003)], "steel_dark")
    mb.xcyl(0.004, -0.0155, 0.0155, 0.014, -0.006, "steel", segs=6)
    st = [(-0.010, 0.0155), (-0.020, 0.0138), (-0.032, 0.0152), (-0.044, 0.0136), (-0.056, 0.0152), (-0.068, 0.0138),
          (-0.082, 0.0165), (-0.092, 0.0165), (-0.096, 0.0130)]
    mb.lathe(st, B, segs=8, axis="Z", c=(0.0, 0.0), scale=(0.92, 1.12), cap_colors=(B, "black"))
    mb.to_object(root, "body")
    mk(root, "hand_l", (0, 0, -0.052))
    return root


@asset("att_laser", "weapons/att/att_laser",
       notes="Laser sight box. Origin = TOP centre of the clamp ('under' marker). Emitter = led_red. Marker light at "
             "the emitter, +Y forward.")
def build_att_laser():
    root = begin("att_laser")
    mb = GB()
    zc = -0.017
    mb.box((0.016, 0.022, 0.0075), (0, 0, -0.0035), "steel_dark")
    mb.hull([(-0.022, zc, 0.011, 0.011, 0.003), (0.022, zc, 0.011, 0.011, 0.003)], A)
    mb.ycyl(0.0055, 0.020, 0.027, zc, "black", segs=8, cap_color="led_red")
    mb.ycyl(0.007, -0.026, -0.021, zc, "steel_dark", segs=8)
    mb.box((0.002, 0.010, 0.007), (-0.0115, -0.004, zc), "rubber")
    mb.box((0.003, 0.003, 0.0015), (0.004, 0.010, zc + 0.0112), "brass")
    mb.to_object(root, "body")
    mk(root, "light", (0, 0.027, zc))
    return root
