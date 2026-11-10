"""Rigged low-poly humanoids (male/female) with skinned modular attachments. Run through Blender MCP."""
import sys
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

mat("M_Hat", "#c8382b", 0.8)
mat("M_Vest", "#23262d", 0.8)
mat("M_Pack", "#4a5a3a", 0.85)
mat("M_Badge", "#e3b341", 0.3, 0.9)
mat("M_Tank", "#e0c020", 0.4, 0.6)
mat("M_Lens", "#101216", 0.1, 0.5)

C = coll("Characters")


def build_character(name, loc, P):
    wipe([name + "_", name])
    old = bpy.data.objects.get(name)
    H = P["scale"]
    sh = P["shoulder"]      # half shoulder width
    hipw = P["hip"]         # half hip joint offset
    Z = lambda z: z * H
    J = {
        "Hips": ((0, 0, Z(0.95)), (0, 0, Z(1.08)), None),
        "Spine": ((0, 0, Z(1.08)), (0, 0, Z(1.28)), "Hips"),
        "Chest": ((0, 0, Z(1.28)), (0, 0, Z(1.50)), "Spine"),
        "Neck": ((0, 0, Z(1.50)), (0, 0, Z(1.58)), "Chest"),
        "Head": ((0, 0, Z(1.58)), (0, 0, Z(1.80)), "Neck"),
    }
    for side, sx in (("L", -1), ("R", 1)):
        J["UpperArm_" + side] = ((sx * sh, 0, Z(1.455)), (sx * (sh + 0.02), 0, Z(1.18)), "Chest")
        J["LowerArm_" + side] = ((sx * (sh + 0.02), 0, Z(1.18)), (sx * (sh + 0.03), 0, Z(0.92)), "UpperArm_" + side)
        J["Hand_" + side] = ((sx * (sh + 0.03), 0, Z(0.92)), (sx * (sh + 0.03), 0, Z(0.80)), "LowerArm_" + side)
        J["UpperLeg_" + side] = ((sx * hipw, 0, Z(0.95)), (sx * hipw, 0, Z(0.52)), "Hips")
        J["LowerLeg_" + side] = ((sx * hipw, 0, Z(0.52)), (sx * hipw, 0, Z(0.10)), "UpperLeg_" + side)
        J["Foot_" + side] = ((sx * hipw, 0, Z(0.10)), (sx * hipw, 0.16, Z(0.02)), "LowerLeg_" + side)
    # armature
    arm_data = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name, arm_data)
    C.objects.link(arm)
    arm.location = loc
    bpy.context.view_layer.objects.active = arm
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bn, (h, t, p) in J.items():
        b = arm_data.edit_bones.new(bn)
        b.head = h
        b.tail = t
        b.roll = 0
    for bn, (h, t, p) in J.items():
        if p:
            arm_data.edit_bones[bn].parent = arm_data.edit_bones[p]
    bpy.ops.object.mode_set(mode='OBJECT')

    def skinned(mb, oname):
        ob = mb.build(oname, C, loc=(0, 0, 0), parent=arm)
        md = ob.modifiers.new("Armature", 'ARMATURE')
        md.object = arm
        return ob

    # ------------------------------------------------ body
    mb = MB()
    cw, ww_, hw = P["chest_w"], P["waist_w"], P["hips_w"]
    mb.group("Hips")
    mb.box((0, 0, Z(0.99)), (hw, 0.21, Z(0.20)), "M_Pants", top=(ww_ + 0.02, 0.19))
    mb.group("Spine")
    mb.box((0, 0, Z(1.18)), (ww_, 0.19, Z(0.21)), "M_Shirt", top=(cw - 0.04, 0.21))
    mb.group("Chest")
    mb.box((0, 0.005, Z(1.385)), (cw - 0.04, 0.22, Z(0.24)), "M_Shirt", top=(cw, 0.20))
    if P.get("bust"):
        mb.box((0, 0.09, Z(1.37)), (cw - 0.08, 0.10, Z(0.13)), "M_Shirt", top=(cw - 0.12, 0.06))
    mb.group("Neck")
    mb.limb((0, 0, Z(1.49)), (0, 0.005, Z(1.60)), 0.05, 0.046, "M_Skin", seg=6)
    mb.group("Head")
    hs = P["head"]
    mb.ball((0, 0.012, Z(1.69)), 0.1, "M_Skin", scale=(0.92 * hs, 1.0 * hs, 1.18 * hs), sub=2)
    mb.box((0, 0.108 * hs, Z(1.675)), (0.026, 0.03, 0.04), "M_Skin")
    for sx in (-1, 1):
        mb.box((sx * 0.037, 0.094 * hs, Z(1.705)), (0.022, 0.012, 0.014), "M_Eye")
        mb.box((sx * 0.094 * hs, 0.0, Z(1.69)), (0.02, 0.03, 0.045), "M_Skin")
    for side, sx in (("L", -1), ("R", 1)):
        s0 = Vector(J["UpperArm_" + side][0])
        e0 = Vector(J["LowerArm_" + side][0])
        w0 = Vector(J["Hand_" + side][0])
        ar = P["arm_r"]
        mb.group("UpperArm_" + side)
        mb.ball(s0, ar * 1.28, "M_Shirt", sub=1)
        mb.limb(s0, e0, ar * 1.08, ar * 0.9, "M_Shirt", seg=6)
        mb.group("LowerArm_" + side)
        mb.ball(e0, ar * 0.92, "M_Sleeve", sub=1)
        mb.limb(e0, w0, ar * 0.88, ar * 0.70, "M_Sleeve", seg=6)
        mb.group("Hand_" + side)
        mb.box(w0 + Vector((0, 0.005, -0.06)), (0.042, 0.085, 0.11), "M_Skin", top=(0.05, 0.07))
        mb.box(w0 + Vector((0, 0.05, -0.04)), (0.03, 0.03, 0.05), "M_Skin")
        h0 = Vector(J["UpperLeg_" + side][0])
        k0 = Vector(J["LowerLeg_" + side][0])
        a0 = Vector(J["Foot_" + side][0])
        lr = P["leg_r"]
        mb.group("UpperLeg_" + side)
        mb.ball(h0 + Vector((0, 0, -0.02)), lr * 1.05, "M_Pants", sub=1)
        mb.limb(h0, k0, lr, lr * 0.76, "M_Pants", seg=6)
        mb.group("LowerLeg_" + side)
        mb.ball(k0, lr * 0.76, "M_Shin", sub=1)
        mb.limb(k0, a0 + Vector((0, 0, -0.02)), lr * 0.74, lr * 0.52, "M_Shin", seg=6)
        mb.group("Foot_" + side)
        mb.box(a0 + Vector((0, 0.055, -0.055)), (0.095, 0.26, 0.09), "M_Shoes", top=(0.085, 0.20), top_off=(0, -0.02))
    skinned(mb, name + "_body")

    # ------------------------------------------------ attachments (all skinned to one bone)
    hz = Z(1.69)

    def att(aname, bone, fn):
        m = MB()
        m.group(bone)
        fn(m)
        skinned(m, name + "_att_" + aname)

    def hair_short(m):
        m.ball((0, -0.008, hz + 0.022), 0.1, "M_Hair", scale=(0.98 * hs, 1.02 * hs, 1.12 * hs), sub=2)
        m.box((0, 0.05 * hs, hz + 0.118 * hs), (0.13 * hs, 0.09, 0.03), "M_Hair")
    att("hair_short", "Head", hair_short)

    def hair_long(m):
        m.ball((0, -0.012, hz + 0.022), 0.1, "M_Hair", scale=(1.0 * hs, 1.04 * hs, 1.14 * hs), sub=2)
        m.box((0, -0.075, hz - 0.11), (0.19 * hs, 0.07, 0.26), "M_Hair", top=(0.17 * hs, 0.09))
        for sx in (-1, 1):
            m.box((sx * 0.085 * hs, -0.02, hz - 0.07), (0.035, 0.11, 0.2), "M_Hair")
    att("hair_long", "Head", hair_long)

    def hair_bun(m):
        m.ball((0, -0.008, hz + 0.022), 0.1, "M_Hair", scale=(0.98 * hs, 1.02 * hs, 1.12 * hs), sub=2)
        m.ball((0, -0.09, hz + 0.10), 0.05, "M_Hair", sub=1)
    att("hair_bun", "Head", hair_bun)

    def hair_mohawk(m):
        m.ball((0, -0.006, hz + 0.012), 0.1, "M_Hair", scale=(0.94 * hs, 1.0 * hs, 1.10 * hs), sub=2)
        m.prism([(-0.10, hz + 0.02), (0.09, hz + 0.08), (0.06, hz + 0.20), (-0.06, hz + 0.19)], 0.035, "M_Hair", plane='YZ')
    att("hair_mohawk", "Head", hair_mohawk)

    def hair_afro(m):
        m.ball((0, -0.012, hz + 0.045), 0.1, "M_Hair", scale=(1.25 * hs, 1.25 * hs, 1.30 * hs), sub=2)
    att("hair_afro", "Head", hair_afro)

    def beard(m):
        m.box((0, 0.065 * hs, hz - 0.075), (0.13 * hs, 0.07, 0.085), "M_Hair", top=(0.15 * hs, 0.08))
    att("beard", "Head", beard)

    def moustache(m):
        m.box((0, 0.10 * hs, hz - 0.045), (0.07, 0.02, 0.018), "M_Hair")
    att("moustache", "Head", moustache)

    def cap(m):
        m.ball((0, 0.0, hz + 0.045), 0.1, "M_Hat", scale=(1.02 * hs, 1.06 * hs, 0.95 * hs), sub=2)
        m.box((0, 0.13 * hs, hz + 0.055), (0.15, 0.12, 0.018), "M_Hat")
    att("cap", "Head", cap)

    def beanie(m):
        m.ball((0, -0.004, hz + 0.05), 0.1, "M_Hat", scale=(1.03 * hs, 1.07 * hs, 1.05 * hs), sub=2)
        m.cyl((0, 0, hz + 0.045), 0.106 * hs, 0.04, "M_Hat", seg=10)
    att("beanie", "Head", beanie)

    def fedora(m):
        m.cyl((0, 0, hz + 0.085), 0.17, 0.014, "M_Hat", seg=12)
        m.cyl((0, 0, hz + 0.135), 0.10 * hs, 0.10, "M_Hat", seg=10, r2=0.085 * hs)
        m.cyl((0, 0, hz + 0.098), 0.103 * hs, 0.02, "M_Black", seg=10)
    att("fedora", "Head", fedora)

    def police_cap(m):
        m.cyl((0, 0, hz + 0.10), 0.105 * hs, 0.05, "M_Hat", seg=10, r2=0.125 * hs)
        m.cyl((0, 0, hz + 0.132), 0.125 * hs, 0.016, "M_Hat", seg=10)
        m.box((0, 0.12 * hs, hz + 0.075), (0.15, 0.09, 0.014), "M_Black")
        m.box((0, 0.105 * hs, hz + 0.105), (0.03, 0.012, 0.03), "M_Badge")
    att("police_cap", "Head", police_cap)

    def helmet(m):
        m.ball((0, -0.004, hz + 0.04), 0.1, "M_Vest", scale=(1.1 * hs, 1.14 * hs, 1.08 * hs), sub=2)
        m.box((0, 0.09 * hs, hz + 0.02), (0.17, 0.05, 0.06), "M_Lens")
        for sx in (-1, 1):
            m.box((sx * 0.1 * hs, 0, hz - 0.03), (0.03, 0.08, 0.09), "M_Vest")
    att("helmet", "Head", helmet)

    def sunglasses(m):
        m.box((0, 0.10 * hs, Z(1.705)), (0.15 * hs, 0.02, 0.034), "M_Lens")
        for sx in (-1, 1):
            m.box((sx * 0.088 * hs, 0.04, Z(1.708)), (0.008, 0.11, 0.012), "M_Black")
    att("sunglasses", "Head", sunglasses)

    def glasses(m):
        for sx in (-1, 1):
            m.box((sx * 0.037, 0.103 * hs, Z(1.705)), (0.05, 0.008, 0.036), "M_Glass")
            m.box((sx * 0.088 * hs, 0.04, Z(1.708)), (0.006, 0.11, 0.008), "M_Black")
        m.box((0, 0.105 * hs, Z(1.715)), (0.03, 0.008, 0.008), "M_Black")
    att("glasses", "Head", glasses)

    def scuba_mask(m):
        m.box((0, 0.105 * hs, Z(1.70)), (0.16 * hs, 0.04, 0.07), "M_Glass")
        m.box((0, 0.10 * hs, Z(1.70)), (0.175 * hs, 0.02, 0.085), "M_Black")
        m.box((0, 0.11 * hs, Z(1.63)), (0.05, 0.05, 0.04), "M_Black")
    att("scuba_mask", "Head", scuba_mask)

    def vest(m):
        m.box((0, 0.005, Z(1.36)), (cw + 0.03, 0.27, Z(0.36)), "M_Vest", top=(cw + 0.01, 0.25))
        m.box((0, 0.14, Z(1.30)), (0.22, 0.03, 0.10), "M_Pack")
        for sx in (-1, 1):
            m.box((sx * 0.09, 0.145, Z(1.42)), (0.07, 0.03, 0.08), "M_Pack")
    att("vest", "Chest", vest)

    def jacket(m):
        m.box((0, 0.0, Z(1.385)), (cw + 0.03, 0.25, Z(0.25)), "M_Hat", top=(cw + 0.035, 0.24))
        m.box((0, 0.125, Z(1.39)), (0.06, 0.012, Z(0.24)), "M_Shirt")
    att("jacket", "Chest", jacket)

    def pack(m):
        m.box((0, -0.17, Z(1.36)), (0.28, 0.14, 0.38), "M_Pack", top=(0.24, 0.10))
        for sx in (-1, 1):
            m.box((sx * 0.11, 0.0, Z(1.46)), (0.04, 0.26, 0.03), "M_Black")
            m.box((sx * 0.11, 0.115, Z(1.36)), (0.04, 0.02, 0.22), "M_Black")
    att("pack", "Chest", pack)

    def tank(m):
        m.cyl((0, -0.18, Z(1.36)), 0.075, 0.46, "M_Tank", seg=8)
        m.cyl((0, -0.18, Z(1.36) + 0.26), 0.03, 0.08, "M_MetalDark", seg=6)
        m.box((0, -0.10, Z(1.36)), (0.26, 0.04, 0.3), "M_Black")
    att("tank", "Chest", tank)

    def belt(m):
        m.box((0, 0, Z(1.075)), (ww_ + 0.035, 0.225, 0.045), "M_Black")
        m.box((0.13, 0.03, Z(1.03)), (0.05, 0.10, 0.12), "M_Black")
        m.box((0, 0.115, Z(1.075)), (0.04, 0.012, 0.04), "M_Badge")
    att("belt", "Hips", belt)

    def badge(m):
        m.box((-0.10, 0.115, Z(1.43)), (0.035, 0.012, 0.045), "M_Badge")
    att("badge", "Chest", badge)

    def apron(m):
        m.box((0, 0.11, Z(1.22)), (ww_ - 0.02, 0.016, Z(0.46)), "M_White")
    att("apron", "Spine", apron)
    return arm


MALE = dict(scale=1.0, shoulder=0.205, hip=0.095, chest_w=0.41, waist_w=0.31, hips_w=0.33, head=1.08, arm_r=0.054, leg_r=0.097)
FEMALE = dict(scale=0.94, shoulder=0.175, hip=0.095, chest_w=0.345, waist_w=0.25, hips_w=0.345, head=1.04, arm_r=0.045,
              leg_r=0.09, bust=True)
a = build_character("char_male", (-20, 30, 0), MALE)
b = build_character("char_female", (-18, 30, 0), FEMALE)
print("chars", tri_count(a), tri_count(b), [c.name for c in a.children][:6])
