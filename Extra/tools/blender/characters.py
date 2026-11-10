# Rigged low-poly humans + attachable parts for Cinder Bay. Executed in Blender through MCP.
# Character faces +Y (Godot -Z). "_L" = character's left = -X.
import bpy, bmesh, math
from mathutils import Vector
from fable_lib import *

BONES = ["Hips", "Spine", "Chest", "Neck", "Head",
         "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R",
         "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]

MALE = dict(S=1.0, sh=0.200, chest=0.185, chest_d=0.115, waist=0.155, hip=0.172, limb=1.0, bust=0.0, neck=0.055)
FEMALE = dict(S=0.94, sh=0.172, chest=0.160, chest_d=0.108, waist=0.128, hip=0.182, limb=0.86, bust=0.028, neck=0.048)


def _bl(a, b, t):
    t = max(0.0, min(1.0, t))
    return {a: 1.0 - t, b: t}


def build_armature(name, coll, P, parent=None):
    S = P['S']
    kill(name)
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    coll.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    sx = P['sh'] + 0.015
    defs = [("Hips", (0, 0, 0.98), (0, 0, 1.10), None), ("Spine", (0, 0, 1.10), (0, 0, 1.28), "Hips"),
            ("Chest", (0, 0, 1.28), (0, 0, 1.50), "Spine"), ("Neck", (0, 0, 1.50), (0, 0, 1.60), "Chest"),
            ("Head", (0, 0, 1.60), (0, 0, 1.82), "Neck")]
    for sn, s in (("L", -1), ("R", 1)):
        defs += [("UpperArm_" + sn, (s * sx, 0, 1.44), (s * (sx + 0.03), 0, 1.17), "Chest"),
                 ("LowerArm_" + sn, (s * (sx + 0.03), 0, 1.17), (s * (sx + 0.047), 0.01, 0.92), "UpperArm_" + sn),
                 ("Hand_" + sn, (s * (sx + 0.047), 0.01, 0.92), (s * (sx + 0.053), 0.02, 0.80), "LowerArm_" + sn),
                 ("UpperLeg_" + sn, (s * 0.095, 0, 0.96), (s * 0.10, 0.005, 0.54), "Hips"),
                 ("LowerLeg_" + sn, (s * 0.10, 0.005, 0.54), (s * 0.10, 0, 0.10), "UpperLeg_" + sn),
                 ("Foot_" + sn, (s * 0.10, 0, 0.10), (s * 0.10, 0.17, 0.02), "LowerLeg_" + sn)]
    for bn, h, t, par in defs:
        eb = arm.edit_bones.new(bn)
        eb.head = Vector(h) * S
        eb.tail = Vector(t) * S
        eb.roll = 0.0
        if par:
            eb.parent = arm.edit_bones[par]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    ob.display_type = 'WIRE'
    return ob


def body_geo(P, lod=0):
    S = P['S']
    mb = MB()
    dl = mb.bm.verts.layers.deform.verify()
    lm = P['limb']
    seg_t = 10 if lod == 0 else 6
    seg_l = 7 if lod == 0 else 5

    def skin(geom, fn):
        vs = set()
        for g in geom:
            if isinstance(g, bmesh.types.BMFace):
                if g.is_valid:
                    vs.update(g.verts)
            elif g.is_valid:
                vs.add(g)
        for v in vs:
            ws = fn(v.co / S)
            tot = sum(ws.values())
            for b, x in ws.items():
                if x > 0.001:
                    v[dl][BONES.index(b)] = x / tot

    def torso_w(c):
        z = c.z
        if z <= 1.04:
            return {"Hips": 1.0}
        if z <= 1.14:
            return _bl("Hips", "Spine", (z - 1.04) / 0.10)
        if z <= 1.24:
            return {"Spine": 1.0}
        if z <= 1.34:
            return _bl("Spine", "Chest", (z - 1.24) / 0.10)
        return {"Chest": 1.0}

    def arm_w(sn):
        def f(c):
            z = c.z
            if z >= 1.40:
                return {"Chest": 0.35, "UpperArm_" + sn: 0.65}
            if z >= 1.22:
                return {"UpperArm_" + sn: 1.0}
            if z >= 1.12:
                return _bl("UpperArm_" + sn, "LowerArm_" + sn, (1.22 - z) / 0.10)
            if z >= 0.96:
                return {"LowerArm_" + sn: 1.0}
            if z >= 0.90:
                return _bl("LowerArm_" + sn, "Hand_" + sn, (0.96 - z) / 0.06)
            return {"Hand_" + sn: 1.0}
        return f

    def leg_w(sn):
        def f(c):
            z = c.z
            if z >= 0.93:
                return {"Hips": 0.4, "UpperLeg_" + sn: 0.6}
            if z >= 0.60:
                return {"UpperLeg_" + sn: 1.0}
            if z >= 0.48:
                return _bl("UpperLeg_" + sn, "LowerLeg_" + sn, (0.60 - z) / 0.12)
            if z >= 0.16:
                return {"LowerLeg_" + sn: 1.0}
            if z >= 0.085:
                return _bl("LowerLeg_" + sn, "Foot_" + sn, (0.16 - z) / 0.075)
            return {"Foot_" + sn: 1.0}
        return f

    def loftz(st, segs, m, sq=0.0):
        st = [(z * S, cx * S, cy * S, rx * S, ry * S) for z, cx, cy, rx, ry in st]
        return mb.ellipse_loft(st, segs=segs, m=m, axis='Z', squareness=sq)

    # torso
    b = P['bust']
    T = [(0.885, 0, 0, P['hip'] * 0.55, 0.080), (0.99, 0, 0, P['hip'], 0.112), (1.10, 0, 0, P['waist'], 0.098),
         (1.30, 0, b * 0.6, P['chest'], P['chest_d'] + b), (1.41, 0, 0, P['sh'], 0.108), (1.47, 0, 0, P['sh'] * 0.80, 0.095),
         (1.505, 0, 0, 0.085, 0.075)]
    f = loftz(T, seg_t, lambda i, j: "Pants" if i < 2 else "Shirt", 0.25)
    skin(f, torso_w)
    # neck + head
    f = loftz([(1.47, 0, 0.005, P['neck'], P['neck']), (1.61, 0, 0.008, P['neck'] * 0.95, P['neck'] * 0.95)], 6, "Skin")
    skin(f, lambda c: {"Chest": 0.5, "Neck": 0.5} if c.z < 1.52 else {"Neck": 0.5, "Head": 0.5})
    H = [(1.575, 0, 0.012, 0.062, 0.070), (1.63, 0, 0.014, 0.092, 0.102), (1.71, 0, 0.010, 0.104, 0.114),
         (1.78, 0, 0.004, 0.097, 0.108), (1.825, 0, 0.0, 0.058, 0.068)]
    f = loftz(H, 8 if lod == 0 else 6, "Skin", 0.3)
    skin(f, lambda c: {"Head": 1.0})
    hv = []
    for s in (1, -1):
        hv += mb.box((0.028 * S, 0.014 * S, 0.024 * S), loc=(s * 0.042 * S, 0.106 * S, 1.722 * S), m="Eye")
        if lod == 0:
            hv += mb.box((0.044 * S, 0.014 * S, 0.010 * S), loc=(s * 0.043 * S, 0.108 * S, 1.751 * S), m="Hair")
            hv += mb.box((0.02 * S, 0.05 * S, 0.055 * S), loc=(s * 0.107 * S, 0.0, 1.705 * S), m="Skin")
    if lod == 0:
        hv += mb.box((0.026 * S, 0.034 * S, 0.046 * S), loc=(0, 0.118 * S, 1.693 * S), m="Skin", taper=(0.6, 0.5))
        hv += mb.box((0.052 * S, 0.012 * S, 0.008 * S), loc=(0, 0.103 * S, 1.648 * S), m="Mouth")
    skin(hv, lambda c: {"Head": 1.0})
    for sn, s in (("L", -1), ("R", 1)):
        sx = P['sh'] + 0.015
        # arm
        A1 = [(1.478, s * (sx - 0.016), 0, 0.024 * lm, 0.028 * lm), (1.452, s * (sx - 0.006), 0, 0.050 * lm, 0.054 * lm),
              (1.40, s * (sx + 0.004), 0, 0.054 * lm, 0.056 * lm),
              (1.22, s * (sx + 0.025), 0, 0.045 * lm, 0.047 * lm), (1.17, s * (sx + 0.03), 0, 0.043 * lm, 0.045 * lm)]
        A2 = [(1.17, s * (sx + 0.03), 0, 0.043 * lm, 0.045 * lm), (1.12, s * (sx + 0.034), 0.002, 0.042 * lm, 0.044 * lm),
              (0.96, s * (sx + 0.045), 0.008, 0.033 * lm, 0.035 * lm), (0.915, s * (sx + 0.047), 0.01, 0.030 * lm, 0.032 * lm)]
        skin(loftz(A1, seg_l, "Shirt"), arm_w(sn))
        skin(loftz(A2, seg_l, "Sleeve"), arm_w(sn))
        hv = mb.box((0.036 * S * lm, 0.078 * S, 0.105 * S), loc=(s * (sx + 0.05) * S, 0.018 * S, 0.855 * S), m="Skin", taper=(0.9, 0.75), bevel=0.008 if lod == 0 else 0)
        if lod == 0:
            hv += mb.box((0.03 * S, 0.035 * S, 0.05 * S), loc=(s * (sx + 0.04) * S, 0.062 * S, 0.875 * S), m="Skin")
        skin(hv, lambda c, sn=sn: {"Hand_" + sn: 1.0})
        # leg
        L1 = [(0.975, s * 0.095, 0, 0.088 * lm, 0.096 * lm), (0.93, s * 0.096, 0, 0.086 * lm, 0.094 * lm),
              (0.75, s * 0.098, 0.002, 0.072 * lm, 0.080 * lm), (0.60, s * 0.10, 0.004, 0.060 * lm, 0.066 * lm),
              (0.54, s * 0.10, 0.006, 0.056 * lm, 0.062 * lm)]
        L2 = [(0.54, s * 0.10, 0.006, 0.056 * lm, 0.062 * lm), (0.48, s * 0.10, 0.002, 0.055 * lm, 0.062 * lm),
              (0.36, s * 0.10, -0.012, 0.054 * lm, 0.060 * lm), (0.16, s * 0.10, -0.004, 0.041 * lm, 0.046 * lm),
              (0.085, s * 0.10, 0.0, 0.040 * lm, 0.046 * lm)]
        skin(loftz(L1, seg_l, "Pants"), leg_w(sn))
        skin(loftz(L2, seg_l, "Shin"), leg_w(sn))
        fv = mb.box((0.098 * S, 0.27 * S, 0.092 * S), loc=(s * 0.10 * S, 0.052 * S, 0.046 * S), m="Shoes",
                    taper=(0.85, 0.62), shear=(0, -0.045 * S), bevel=0.012 if lod == 0 else 0)
        fv += mb.box((0.102 * S, 0.275 * S, 0.02 * S), loc=(s * 0.10 * S, 0.052 * S, 0.010 * S), m="Sole")
        skin(fv, lambda c, sn=sn: {"Foot_" + sn: 1.0})
    return mb


def build_human(aid, P, cell=(0, 0, 0)):
    coll = col("Characters")
    mat("Mouth", "#7a3f34", rough=0.7)
    mat("Sole", "#e8e4da", rough=0.8)
    kill(aid)
    root = empty(aid, coll, loc=cell, size=0.4)
    arm = build_armature(aid + "_Rig", coll, P, parent=root)
    for lod in (0, 1):
        mb = body_geo(P, lod)
        ob = mb.finish(aid + ("_Body" if lod == 0 else "_BodyLOD1"), coll, smooth=50, parent=arm)
        for bn in BONES:
            ob.vertex_groups.new(name=bn)
        md = ob.modifiers.new("Armature", 'ARMATURE')
        md.object = arm
        if lod == 1:
            ob.location.x = 0.0
            ob.hide_set(True)
    return root


def _hair_cap(mb, m, low=1.70, front=1.775, thick=0.012, back_drop=0.0, side=1.0):
    """Skull cap: rings shifted back at the bottom so the face stays free. Coordinates are head-absolute."""
    R = [(low - back_drop, -0.030, 0.098 * side, 0.090), (1.735, -0.014, 0.110 * side, 0.108),
         (front, 0.006, 0.106, 0.118), (1.815, 0.004, 0.078, 0.090), (1.842, 0.0, 0.03, 0.035)]
    st = [(z, 0, cy, rx + thick, ry + thick) for z, cy, rx, ry in R]
    mb.ellipse_loft(st, segs=8, m=m, axis='Z', squareness=0.3)


def build_parts(cell=(0, 0, 0)):
    """Attachable rigid parts. Head parts are modelled around a head whose bone origin is (0,0,1.60);
    chest parts around a chest bone origin (0,0,1.28). Origins are set to the bone origin."""
    coll = col("Characters")
    kill("char_parts")
    root = empty("char_parts", coll, loc=cell, size=0.4)
    HO = (0, 0, 1.60)
    CO = (0, 0, 1.28)
    out = []
    n = [0]

    def fin(mb, name, origin, smooth=45):
        o = mb.finish(name, coll, smooth=smooth, parent=root, origin=origin)
        o.location = (n[0] * 0.45, 0, origin[2])
        n[0] += 1
        out.append(name)
        return o

    mb = MB(); _hair_cap(mb, "Hair"); fin(mb, "Hair_Short", HO)
    mb = MB(); _hair_cap(mb, "Hair", low=1.69, thick=0.018)
    mb.box((0.20, 0.07, 0.05), loc=(0.02, 0.085, 1.80), m="Hair", rot=(0.25, 0, 0.12), bevel=0.015)
    fin(mb, "Hair_Quiff", HO)
    mb = MB(); _hair_cap(mb, "Hair", low=1.66, thick=0.016, back_drop=0.0)
    mb.ellipse_loft([(1.70, 0, -0.065, 0.118, 0.07), (1.56, 0, -0.075, 0.125, 0.065), (1.44, 0, -0.07, 0.11, 0.04)], segs=8, m="Hair", axis='Z')
    fin(mb, "Hair_Long", HO)
    mb = MB(); _hair_cap(mb, "Hair", low=1.70, thick=0.012)
    mb.sphere(0.05, loc=(0, -0.115, 1.76), m="Hair", segs=6, rings=5)
    mb.ellipse_loft([(1.74, 0, -0.15, 0.035, 0.035), (1.60, 0, -0.17, 0.04, 0.035), (1.50, 0, -0.16, 0.015, 0.015)], segs=6, m="Hair", axis='Z')
    fin(mb, "Hair_Pony", HO)
    mb = MB()
    mb.box((0.045, 0.24, 0.07), loc=(0, -0.01, 1.845), m="Hair", bevel=0.015)
    _hair_cap(mb, "Hair", low=1.74, thick=0.004)
    fin(mb, "Hair_Mohawk", HO)
    mb = MB(); mb.sphere(0.155, loc=(0, -0.01, 1.77), m="Hair", segs=8, rings=6, scale=(1.0, 1.0, 0.92))
    fin(mb, "Hair_Afro", HO)
    mb = MB(); _hair_cap(mb, "Hair", low=1.70, thick=0.012)
    mb.sphere(0.055, loc=(0, -0.03, 1.875), m="Hair", segs=6, rings=5)
    fin(mb, "Hair_Bun", HO)
    mb = MB()
    mb.ellipse_loft([(1.66, 0, 0.055, 0.085, 0.07), (1.60, 0, 0.06, 0.075, 0.065), (1.555, 0, 0.055, 0.045, 0.045)], segs=8, m="Hair", axis='Z')
    fin(mb, "Beard", HO)
    mb = MB(); mb.box((0.07, 0.02, 0.016), loc=(0, 0.108, 1.668), m="Hair"); fin(mb, "Mustache", HO)
    # hats
    mb = MB()
    mb.ellipse_loft([(1.765, 0, 0.0, 0.118, 0.128), (1.82, 0, 0.0, 0.108, 0.118), (1.86, 0, 0.0, 0.06, 0.07)], segs=8, m="HatMain", axis='Z')
    mb.box((0.16, 0.13, 0.014), loc=(0, 0.165, 1.772), m="HatMain", taper=(0.8, 1.0), bevel=0.004)
    fin(mb, "Hat_Cap", HO)
    mb = MB()
    mb.ellipse_loft([(1.735, 0, -0.005, 0.120, 0.130), (1.80, 0, 0.0, 0.114, 0.124), (1.865, 0, 0.0, 0.07, 0.08), (1.885, 0, 0, 0.02, 0.02)], segs=8, m="HatMain", axis='Z')
    mb.ellipse_loft([(1.73, 0, -0.005, 0.126, 0.136), (1.765, 0, -0.005, 0.126, 0.136)], segs=8, m="HatBand", axis='Z')
    fin(mb, "Hat_Beanie", HO)
    mb = MB()
    mb.ellipse_loft([(1.77, 0, 0.0, 0.116, 0.126), (1.80, 0, 0.0, 0.118, 0.128), (1.835, 0, 0.01, 0.15, 0.155), (1.85, 0, 0.01, 0.13, 0.135)], segs=8, m="PoliceHat", axis='Z')
    mb.box((0.17, 0.10, 0.012), loc=(0, 0.155, 1.775), m="Trim", taper=(0.8, 1.0))
    mb.box((0.05, 0.012, 0.04), loc=(0, 0.133, 1.815), m="Badge")
    fin(mb, "Hat_Police", HO)
    mb = MB()
    mb.ellipse_loft([(1.70, 0, -0.01, 0.128, 0.138), (1.78, 0, -0.005, 0.130, 0.140), (1.845, 0, 0.0, 0.10, 0.11), (1.87, 0, 0, 0.04, 0.045)], segs=8, m="Helmet", axis='Z', squareness=0.2)
    mb.box((0.20, 0.02, 0.07), loc=(0, 0.118, 1.725), m="Glass")
    mb.box((0.05, 0.11, 0.07), loc=(-0.125, 0.0, 1.70), m="Helmet")
    mb.box((0.05, 0.11, 0.07), loc=(0.125, 0.0, 1.70), m="Helmet")
    fin(mb, "Hat_Helmet", HO)
    mb = MB()
    mb.ellipse_loft([(1.765, 0, 0.0, 0.118, 0.128), (1.84, 0, 0.0, 0.112, 0.120), (1.865, 0, 0.0, 0.06, 0.07)], segs=8, m="HardHat", axis='Z')
    mb.cyl(0.165, 0.014, loc=(0, 0.02, 1.772), segs=10, m="HardHat")
    fin(mb, "Hat_Hard", HO)
    mb = MB()
    mb.ellipse_loft([(1.77, 0, 0.0, 0.112, 0.122), (1.86, 0, 0.0, 0.098, 0.108), (1.87, 0, 0.0, 0.06, 0.07)], segs=8, m="HatMain", axis='Z')
    mb.cyl(0.19, 0.012, loc=(0, 0.0, 1.772), segs=12, m="HatMain")
    mb.ellipse_loft([(1.775, 0, 0.0, 0.116, 0.126), (1.80, 0, 0.0, 0.114, 0.124)], segs=8, m="HatBand", axis='Z')
    fin(mb, "Hat_Fedora", HO)
    mb = MB()
    mb.ellipse_loft([(1.57, 0, 0.012, 0.075, 0.085), (1.66, 0, 0.012, 0.108, 0.118), (1.76, 0, 0.008, 0.112, 0.122), (1.84, 0, 0.0, 0.07, 0.08)], segs=8, m="HatMain", axis='Z', squareness=0.3)
    mb.box((0.15, 0.02, 0.035), loc=(0, 0.118, 1.722), m="Skin")
    fin(mb, "Hat_Mask", HO)
    # eyewear
    mb = MB()
    for s in (1, -1):
        mb.box((0.052, 0.012, 0.036), loc=(s * 0.043, 0.118, 1.722), m="Glass", bevel=0.006)
        mb.box((0.008, 0.11, 0.008), loc=(s * 0.10, 0.065, 1.728), m="Trim")
    mb.box((0.036, 0.008, 0.008), loc=(0, 0.118, 1.728), m="Trim")
    fin(mb, "Glasses", HO)
    mb = MB()
    for s in (1, -1):
        mb.box((0.058, 0.014, 0.036), loc=(s * 0.044, 0.118, 1.722), m="Trim", bevel=0.008)
        mb.box((0.008, 0.11, 0.010), loc=(s * 0.10, 0.065, 1.728), m="Trim")
    mb.box((0.04, 0.010, 0.010), loc=(0, 0.118, 1.73), m="Trim")
    fin(mb, "Shades", HO)
    # chest gear
    mb = MB()
    mb.ellipse_loft([(1.10, 0, 0.0, 0.180, 0.125), (1.30, 0, 0.004, 0.205, 0.138), (1.44, 0, 0.0, 0.175, 0.125)], segs=10, m="Vest", axis='Z', squareness=0.3)
    for x in (-0.09, 0.0, 0.09):
        mb.box((0.07, 0.035, 0.09), loc=(x, 0.135, 1.17), m="VestPouch", bevel=0.008)
    mb.box((0.16, 0.012, 0.05), loc=(0, 0.142, 1.36), m="Badge")
    fin(mb, "Vest", CO)
    mb = MB()
    mb.box((0.30, 0.15, 0.40), loc=(0, -0.18, 1.30), m="Pack", bevel=0.04)
    for s in (1, -1):
        mb.box((0.045, 0.26, 0.02), loc=(s * 0.12, -0.02, 1.47), m="PackStrap")
        mb.box((0.045, 0.02, 0.32), loc=(s * 0.12, 0.115, 1.32), m="PackStrap")
    mb.box((0.06, 0.03, 0.06), loc=(0.12, 0.13, 1.34), m="PaintRed")
    fin(mb, "Parachute_Pack", CO)
    mb = MB()
    mb.cyl(0.075, 0.48, loc=(0, -0.20, 1.30), segs=8, m="PaintYellow")
    mb.cyl(0.03, 0.08, loc=(0, -0.20, 1.57), segs=6, m="Steel")
    for s in (1, -1):
        mb.box((0.04, 0.26, 0.02), loc=(s * 0.12, -0.02, 1.47), m="PackStrap")
        mb.box((0.04, 0.02, 0.30), loc=(s * 0.12, 0.115, 1.33), m="PackStrap")
    fin(mb, "Scuba_Tank", CO)
    mb = MB()
    mb.box((0.12, 0.03, 0.09), loc=(0, 0.118, 1.69), m="Glass", bevel=0.01)
    mb.box((0.14, 0.02, 0.11), loc=(0, 0.108, 1.69), m="Trim")
    mb.cyl(0.022, 0.06, loc=(0, 0.13, 1.63), axis='Y', segs=6, m="Trim")
    fin(mb, "Scuba_Mask", HO)
    mb = MB()
    mb.box((0.36, 0.03, 0.30), loc=(0, 0.118, 1.10), m="Apron")
    mb.box((0.20, 0.03, 0.20), loc=(0, 0.122, 1.33), m="Apron")
    fin(mb, "Apron", CO)
    return root, out


def parachute(cell=(0, 0, 0)):
    """Deployed ram-air canopy with lines. Origin at the harness point."""
    coll = col("Characters")
    name = "parachute_canopy"
    kill(name)
    root = empty(name, coll, loc=cell, size=0.4)
    mb = MB()
    n = 7
    span, chord, h = 6.4, 2.4, 5.2
    for i in range(n):
        t0 = -1 + 2.0 * i / n
        t1 = -1 + 2.0 * (i + 1) / n
        pts = []
        for t in (t0, t1):
            a = t * 0.75
            x = math.sin(a) * span / 2 / math.sin(0.75)
            z = h + (math.cos(a) - 1) * 2.4
            pts.append((x, z))
        (x0, z0), (x1, z1) = pts
        m = "ChuteA" if i % 2 == 0 else "ChuteB"
        mb.loft([[Vector((x0, chord / 2, z0)), Vector((x0, chord / 4, z0 + 0.22)), Vector((x0, -chord / 2, z0 + 0.02)), Vector((x0, chord / 4, z0 - 0.08))],
                 [Vector((x1, chord / 2, z1)), Vector((x1, chord / 4, z1 + 0.22)), Vector((x1, -chord / 2, z1 + 0.02)), Vector((x1, chord / 4, z1 - 0.08))]], m)
        if i in (0, 2, 4, 6):
            for y in (chord / 2 - 0.2, -chord / 2 + 0.3):
                mb.tube((x0, y, z0 - 0.05), (0.18 if x0 > 0 else -0.18, 0.0, 0.25), 0.008, "Trim", segs=3)
    mb.tube((span / 2 * 0.985, chord / 2 - 0.2, h - 0.62), (0.18, 0, 0.25), 0.008, "Trim", segs=3)
    mb.tube((span / 2 * 0.985, -chord / 2 + 0.3, h - 0.62), (0.18, 0, 0.25), 0.008, "Trim", segs=3)
    mb.finish(name + "_Canopy", coll, smooth=40, parent=root)
    return root


def build_all():
    mat("HatMain", "#c9302a", rough=0.8)
    mat("HatBand", "#1b1d21", rough=0.8)
    mat("PoliceHat", "#1c2740", rough=0.7)
    mat("Badge", "#d9b648", rough=0.3, metal=0.9)
    mat("Helmet", "#22262c", rough=0.5, metal=0.2)
    mat("HardHat", "#f0c21c", rough=0.5)
    mat("Vest", "#232830", rough=0.8)
    mat("VestPouch", "#2f3640", rough=0.8)
    mat("Pack", "#3d4a2f", rough=0.85)
    mat("PackStrap", "#22271c", rough=0.85)
    mat("Apron", "#2f8f5b", rough=0.85)
    mat("ChuteA", "#f2b705", rough=0.8)
    mat("ChuteB", "#e0563a", rough=0.8)
    out = []
    out.append(stats(build_human("human_m", MALE, (20, 10, 0))))
    out.append(stats(build_human("human_f", FEMALE, (21.2, 10, 0))))
    r, names = build_parts((23, 10, 0))
    out.append(stats(r))
    out.append(stats(parachute((36, 10, 0))))
    return out


def export_all():
    return [export("human_m", "characters/human_m.glb"), export("human_f", "characters/human_f.glb"),
            export("char_parts", "characters/char_parts.glb"), export("parachute_canopy", "characters/parachute_canopy.glb")]
