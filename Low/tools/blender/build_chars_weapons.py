# Characters (rigged), accessories, animals, weapons.
from gta_lib import *
PAL['Hat'] = (0x2d3a5c, 0.85, 0, 0)
PAL['PoliceBlue'] = (0x1f2c4d, 0.85, 0, 0)


def human(name, female):
    c = coll('Characters')
    r = root(name, c, slot(6, 2))
    b = B()
    sw = 0.37 if female else 0.43
    hw = 0.35 if female else 0.33
    ax = sw / 2 + 0.065
    lx = 0.092
    b.box((hw, 0.2, 0.22), (0, 0, 0.99), 'Pants', g='hips')
    b.box((sw * 0.8, 0.2, 0.44), (0, 0, 1.3), 'Shirt', taper=(1.25, 1.12), g='chest')
    if female:
        b.box((0.3, 0.1, 0.13), (0, 0.08, 1.38), 'Shirt', taper=(0.9, 0.6), g='chest')
    b.box((0.1, 0.1, 0.08), (0, 0, 1.555), 'Skin', g='chest')
    b.box((0.2, 0.22, 0.24), (0, 0, 1.71), 'Skin', taper=(0.95, 0.95), g='head')
    b.box((0.04, 0.05, 0.05), (0, 0.115, 1.69), 'Skin', g='head')
    for sx in (-1, 1):
        sd = 'l' if sx < 0 else 'r'
        b.box((0.036, 0.02, 0.03), (sx * 0.05, 0.106, 1.74), 'Eye', g='head')
        b.box((0.115, 0.125, 0.3), (sx * ax, 0, 1.36), 'Shirt', g='arm_' + sd)
        b.box((0.095, 0.1, 0.27), (sx * ax, 0, 1.07), 'Skin', g='forearm_' + sd)
        b.box((0.085, 0.11, 0.11), (sx * ax, 0, 0.885), 'Skin', g='forearm_' + sd)
        b.box((0.155, 0.17, 0.42), (sx * lx, 0, 0.71), 'Pants', g='thigh_' + sd)
        b.box((0.135, 0.15, 0.42), (sx * lx, 0, 0.3), 'Pants', g='shin_' + sd)
        b.box((0.14, 0.27, 0.09), (sx * lx, 0.045, 0.045), 'Shoes', g='shin_' + sd)
    mesh = b.obj(name + '__mesh', c, r)
    arm = bpy.data.armatures.new(name + '_rig')
    ao = bpy.data.objects.new(name + '__rig', arm)
    c.objects.link(ao)
    ao.parent = r
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode='EDIT')
    bones = [('hips', (0, 0, 0.95), None), ('chest', (0, 0, 1.1), 'hips'), ('head', (0, 0, 1.55), 'chest')]
    for sx, sd in ((-1, 'l'), (1, 'r')):
        bones += [('arm_' + sd, (sx * ax, 0, 1.48), 'chest'), ('forearm_' + sd, (sx * ax, 0, 1.2), 'arm_' + sd),
                  ('hand_' + sd, (sx * ax, 0, 0.9), 'forearm_' + sd),
                  ('thigh_' + sd, (sx * lx, 0, 0.92), 'hips'), ('shin_' + sd, (sx * lx, 0, 0.51), 'thigh_' + sd)]
    for bn, hd, par in bones:
        eb = arm.edit_bones.new(bn)
        eb.head = hd
        eb.tail = (hd[0], hd[1], hd[2] + 0.12)
        eb.roll = 0
        if par:
            eb.parent = arm.edit_bones[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    mesh.parent = ao
    md = mesh.modifiers.new('Armature', 'ARMATURE')
    md.object = ao
    export(r, 'characters')


human('char_male', False)
human('char_female', True)


def acc(name, fn):
    c = coll('Characters/Accessories')
    r = root(name, c, slot(7, 1.2))
    b = B()
    fn(b)
    b.obj(name + '__mesh', c, r)
    export(r, 'characters')


def hair_short(b):
    b.box((0.215, 0.235, 0.07), (0, -0.005, 0.305), 'Hair')
    b.box((0.215, 0.07, 0.17), (0, -0.095, 0.2), 'Hair')


def hair_long(b):
    hair_short(b)
    b.box((0.23, 0.08, 0.36), (0, -0.1, 0.08), 'Hair')
    for sx in (-1, 1):
        b.box((0.03, 0.14, 0.26), (sx * 0.11, -0.03, 0.17), 'Hair')


def hair_mohawk(b):
    b.box((0.05, 0.25, 0.1), (0, -0.01, 0.32), 'Hair')


def hair_pony(b):
    hair_short(b)
    b.box((0.07, 0.08, 0.24), (0, -0.16, 0.14), 'Hair', taper=(0.6, 0.6))


def beard(b):
    b.box((0.205, 0.06, 0.09), (0, 0.085, 0.085), 'Hair')
    for sx in (-1, 1):
        b.box((0.02, 0.12, 0.1), (sx * 0.1, 0.03, 0.11), 'Hair')


def cap(b):
    b.box((0.22, 0.24, 0.09), (0, 0, 0.31), 'Hat', taper=(0.9, 0.9))
    b.box((0.2, 0.13, 0.02), (0, 0.175, 0.275), 'Hat')


def police_cap(b):
    b.box((0.22, 0.24, 0.06), (0, 0, 0.3), 'PoliceBlue')
    b.box((0.26, 0.28, 0.05), (0, 0, 0.35), 'PoliceBlue', taper=(1.05, 1.05))
    b.box((0.2, 0.1, 0.02), (0, 0.16, 0.275), 'Black')
    b.box((0.05, 0.02, 0.04), (0, 0.125, 0.32), 'Yellow')


def helmet(b):
    b.box((0.25, 0.27, 0.2), (0, -0.005, 0.26), 'GunMetal', taper=(0.85, 0.85))
    b.box((0.21, 0.03, 0.08), (0, 0.125, 0.2), 'Glass')
    for sx in (-1, 1):
        b.box((0.03, 0.1, 0.12), (sx * 0.12, -0.01, 0.15), 'GunMetal')


def glasses(b):
    b.box((0.205, 0.025, 0.04), (0, 0.108, 0.19), 'Black')
    for sx in (-1, 1):
        b.box((0.01, 0.12, 0.015), (sx * 0.102, 0.04, 0.195), 'Black')


def vest(b):
    b.box((0.4, 0.28, 0.36), (0, 0, 0.2), 'GunMetal', taper=(1.12, 1.0))
    for sx in (-0.1, 0.1):
        b.box((0.09, 0.04, 0.1), (sx, 0.15, 0.1), 'Dark')
    b.box((0.2, 0.02, 0.06), (0, 0.142, 0.3), 'White')


def parachute_pack(b):
    b.box((0.3, 0.13, 0.4), (0, -0.17, 0.24), 'Canvas', taper=(0.9, 0.8))
    for sx in (-1, 1):
        b.box((0.04, 0.26, 0.03), (sx * 0.12, -0.02, 0.42), 'Dark')


def scuba(b):
    b.cyl(0.075, 0.5, (0, -0.18, 0.22), 'Yellow', 'z', 8)
    b.cyl(0.03, 0.08, (0, -0.18, 0.5), 'Steel', 'z', 6)
    b.box((0.36, 0.03, 0.05), (0, -0.11, 0.3), 'Dark')


for nm, fn in (('acc_hair_short', hair_short), ('acc_hair_long', hair_long), ('acc_hair_mohawk', hair_mohawk),
               ('acc_hair_pony', hair_pony), ('acc_beard', beard), ('acc_cap', cap), ('acc_police_cap', police_cap),
               ('acc_helmet', helmet), ('acc_glasses', glasses), ('acc_vest', vest), ('acc_parachute_pack', parachute_pack),
               ('acc_scuba', scuba)):
    acc(nm, fn)


# ---------------- animals (rigid low-poly, animated procedurally in Godot) ----------------
def animal(name, fn):
    c = coll('NPCs')
    r = root(name, c, slot(8, 3))
    b = B()
    fn(b)
    b.obj(name + '__mesh', c, r)
    export(r, 'characters')


def quad(b, L_, Wd, Ht, leg, fur, head=0.3, ears=True, antler=False, tail=0.2):
    z = leg + Ht / 2
    b.box((Wd, L_, Ht), (0, 0, z), fur, taper=(0.9, 1))
    b.box((Wd * 0.6, head * 0.9, head * 0.9), (0, L_ / 2 + head * 0.15, z + Ht * 0.3 + head * 0.9), fur, rot=(-25, 0, 0))
    b.box((Wd * 0.75, head, head * 0.75), (0, L_ / 2 + head * 0.55, z + Ht * 0.5 + head * 1.25), fur, taper=(0.7, 0.8))
    b.box((Wd * 0.4, head * 0.5, head * 0.4), (0, L_ / 2 + head * 1.15, z + Ht * 0.5 + head * 1.12), 'FurLight')
    for sx in (-1, 1):
        b.box((0.035, 0.02, 0.035), (sx * Wd * 0.3, L_ / 2 + head * 0.9, z + Ht * 0.5 + head * 1.4), 'Eye')
        if ears:
            b.box((0.05, 0.03, head * 0.45), (sx * Wd * 0.3, L_ / 2 + head * 0.3, z + Ht * 0.5 + head * 1.75), fur, taper=(0.4, 1))
        if antler:
            b.tube((sx * 0.06, L_ / 2 + 0.1, z + Ht * 0.5 + head * 1.6), (sx * 0.3, L_ / 2 - 0.05, z + Ht * 0.5 + head * 2.9), 0.02, 'FurLight', 5)
            b.tube((sx * 0.2, L_ / 2 + 0.02, z + Ht * 0.5 + head * 2.3), (sx * 0.22, L_ / 2 + 0.25, z + Ht * 0.5 + head * 2.8), 0.015, 'FurLight', 5)
        for sy in (-1, 1):
            b.box((Wd * 0.26, Wd * 0.3, leg), (sx * Wd * 0.33, sy * (L_ / 2 - Wd * 0.2), leg / 2), fur, taper=(0.7, 0.7), shift=(0, 0))
    b.box((0.06, tail, 0.06), (0, -L_ / 2 - tail * 0.4, z + Ht * 0.3), 'FurLight', rot=(-30, 0, 0))


animal('animal_deer', lambda b: quad(b, 1.2, 0.36, 0.42, 0.75, 'Fur', 0.26, True, True, 0.12))
animal('animal_dog', lambda b: quad(b, 0.7, 0.24, 0.26, 0.32, 'FurLight', 0.2, True, False, 0.25))
animal('animal_boar', lambda b: quad(b, 1.0, 0.42, 0.5, 0.3, 'WoodDark', 0.3, True, False, 0.1))


def gull(b):
    b.box((0.12, 0.34, 0.11), (0, 0, 0), 'White', taper=(0.7, 0.8))
    b.box((0.08, 0.1, 0.08), (0, 0.2, 0.05), 'White')
    b.box((0.03, 0.08, 0.03), (0, 0.28, 0.04), 'Yellow')
    for sx in (-1, 1):
        b.box((0.5, 0.16, 0.015), (sx * 0.3, 0, 0.04), 'LightGrey', rot=(0, -sx * 12, 0))
    b.box((0.1, 0.12, 0.015), (0, -0.2, 0.02), 'LightGrey')


def shark(b):
    b.loft([(1.6, ell(0.1, 0.1, 0)), (1.0, ell(0.5, 0.5, 0)), (0.0, ell(0.65, 0.7, 0)), (-1.1, ell(0.3, 0.35, 0)), (-1.6, ell(0.08, 0.12, 0))], 'SharkGrey')
    b.prof([(0.1, 0.3), (-0.35, 0.3), (-0.4, 0.75)], 0.05, 'SharkGrey')
    b.prof([(-1.5, 0.0), (-2.0, 0.5), (-1.75, 0.0), (-1.95, -0.35)], 0.05, 'SharkGrey')
    for sx in (-1, 1):
        b.box((0.5, 0.25, 0.04), (sx * 0.45, 0.4, -0.15), 'SharkGrey', rot=(0, sx * 25, sx * -25))
        b.box((0.03, 0.03, 0.04), (sx * 0.2, 1.15, 0.08), 'Eye')
    b.box((0.3, 0.2, 0.03), (0, 1.25, -0.12), 'White')


def fish(b):
    b.loft([(0.18, ell(0.02, 0.04, 0)), (0.05, ell(0.07, 0.14, 0)), (-0.12, ell(0.03, 0.06, 0))], 'FishOrange')
    b.prof([(-0.1, 0.0), (-0.22, 0.08), (-0.22, -0.08)], 0.012, 'FishOrange')


animal('animal_gull', gull)
animal('animal_shark', shark)
animal('animal_fish', fish)


# ---------------- weapons (origin at grip, barrel +Y) ----------------
def gun(name, fn, muzzle, top=None, under=None, mag=None, side=None):
    c = coll('Weapons')
    r = root(name, c, slot(9, 1.5))
    b = B()
    fn(b)
    b.obj(name + '__body', c, r)
    empty(name + '__muzzle', r, muzzle)
    my, mz = muzzle[1], muzzle[2]
    if top is not None:
        m = B()
        m.tube((0, my, mz), (0, my + 0.17, mz), 0.021, 'Dark', 8)
        m.obj(name + '__att_suppressor', c, r)
        m = B()
        ty, tz = top
        m.tube((0, ty - 0.08, tz + 0.035), (0, ty + 0.1, tz + 0.035), 0.02, 'Dark', 8)
        m.cyl(0.024, 0.03, (0, ty + 0.1, tz + 0.035), 'Dark', 'y', 8)
        m.cyl(0.018, 0.005, (0, ty + 0.117, tz + 0.035), 'Glass', 'y', 8)
        m.box((0.014, 0.03, 0.03), (0, ty - 0.03, tz + 0.01), 'Dark')
        m.box((0.014, 0.03, 0.03), (0, ty + 0.05, tz + 0.01), 'Dark')
        m.obj(name + '__att_scope', c, r)
    if side is not None:
        m = B()
        m.tube((0.03, side[0], side[1]), (0.03, side[0] + 0.08, side[1]), 0.014, 'Dark', 6)
        m.cyl(0.012, 0.005, (0.03, side[0] + 0.082, side[1]), 'HeadLight', 'y', 6)
        m.obj(name + '__att_flashlight', c, r)
    if under is not None:
        m = B()
        m.box((0.022, 0.028, 0.085), (0, under[0], under[1] - 0.045), 'Dark', rot=(8, 0, 0))
        m.obj(name + '__att_grip', c, r)
    if mag is not None:
        m = B()
        m.box((0.024, 0.04, 0.07), (0, mag[0], mag[1] - 0.035), 'GunMetal')
        m.obj(name + '__att_extmag', c, r)
    export(r, 'weapons')


def grip(b, y=-0.01, z=-0.02, m='Dark'):
    b.box((0.03, 0.045, 0.1), (0, y, z), m, rot=(-14, 0, 0))


def w_pistol(b):
    b.box((0.03, 0.19, 0.036), (0, 0.065, 0.062), 'WeaponFinish')
    b.box((0.028, 0.13, 0.022), (0, 0.045, 0.036), 'GunMetal')
    b.box((0.008, 0.012, 0.012), (0, 0.15, 0.085), 'Dark'); b.box((0.012, 0.012, 0.012), (0, -0.02, 0.085), 'Dark')
    b.box((0.02, 0.06, 0.008), (0, 0.045, 0.0), 'GunMetal')
    grip(b)


def w_revolver(b):
    b.tube((0, 0.06, 0.07), (0, 0.24, 0.07), 0.013, 'Steel', 8)
    b.box((0.014, 0.17, 0.014), (0, 0.15, 0.05), 'Steel')
    b.cyl(0.027, 0.055, (0, 0.035, 0.06), 'WeaponFinish', 'y', 6)
    b.box((0.026, 0.11, 0.05), (0, 0.02, 0.05), 'Steel')
    b.box((0.01, 0.02, 0.02), (0, -0.035, 0.085), 'Dark')
    grip(b, -0.02, -0.02, 'Wood')


def w_smg(b):
    b.box((0.042, 0.3, 0.06), (0, 0.09, 0.055), 'WeaponFinish')
    b.tube((0, 0.24, 0.055), (0, 0.32, 0.055), 0.012, 'GunMetal', 6)
    b.box((0.026, 0.04, 0.17), (0, 0.1, -0.05), 'GunMetal')
    b.box((0.02, 0.2, 0.012), (0, 0.08, 0.092), 'Dark')
    b.box((0.02, 0.14, 0.02), (0, -0.12, 0.07), 'Dark'); b.box((0.03, 0.02, 0.09), (0, -0.19, 0.045), 'Dark')
    grip(b)


def w_shotgun(b):
    b.tube((0, 0.1, 0.065), (0, 0.78, 0.065), 0.015, 'GunMetal', 8)
    b.tube((0, 0.12, 0.035), (0, 0.6, 0.035), 0.014, 'GunMetal', 8)
    b.box((0.04, 0.26, 0.065), (0, 0.04, 0.05), 'WeaponFinish')
    b.box((0.046, 0.16, 0.045), (0, 0.38, 0.035), 'Wood')
    b.prof([(-0.08, 0.075), (-0.4, 0.05), (-0.4, -0.06), (-0.08, 0.01)], 0.036, 'Wood')
    b.box((0.02, 0.07, 0.008), (0, 0.03, 0.0), 'GunMetal')


def rifle_base(b, hg=0.3, barrel=0.74, stock='full', wood=False):
    body = 'Wood' if wood else 'WeaponFinish'
    b.box((0.042, 0.25, 0.075), (0, 0.06, 0.05), 'WeaponFinish')
    b.box((0.046, hg, 0.052), (0, 0.185 + hg / 2, 0.05), body)
    b.tube((0, 0.18 + hg, 0.052), (0, barrel, 0.052), 0.011, 'GunMetal', 8)
    b.tube((0, barrel - 0.05, 0.052), (0, barrel, 0.052), 0.016, 'GunMetal', 8)
    b.box((0.026, 0.05, 0.16), (0, 0.11, -0.05), 'GunMetal', rot=(10, 0, 0))
    b.box((0.02, 0.3, 0.012), (0, 0.1, 0.094), 'Dark')
    if stock == 'full':
        b.prof([(-0.06, 0.085), (-0.34, 0.08), (-0.34, -0.04), (-0.06, 0.02)], 0.036, body)
    else:
        b.tube((0, -0.06, 0.07), (0, -0.28, 0.07), 0.012, 'GunMetal', 6)
        b.box((0.03, 0.03, 0.11), (0, -0.29, 0.035), 'Dark')
    grip(b)


def w_marksman(b):
    rifle_base(b, 0.36, 0.92, 'full', True)
    b.tube((0, 0.0, 0.135), (0, 0.22, 0.135), 0.02, 'Dark', 8)
    b.box((0.014, 0.03, 0.03), (0, 0.05, 0.11), 'Dark'); b.box((0.014, 0.03, 0.03), (0, 0.17, 0.11), 'Dark')


def w_sniper(b):
    b.box((0.045, 0.3, 0.07), (0, 0.08, 0.05), 'WeaponFinish')
    b.tube((0, 0.2, 0.055), (0, 1.05, 0.055), 0.013, 'GunMetal', 8)
    b.box((0.04, 0.08, 0.04), (0, 1.07, 0.055), 'GunMetal')
    b.box((0.04, 0.3, 0.04), (0, 0.36, 0.04), 'WeaponFinish')
    b.prof([(-0.06, 0.085), (-0.42, 0.09), (-0.42, -0.05), (-0.3, -0.05), (-0.2, 0.02), (-0.06, 0.02)], 0.04, 'WeaponFinish')
    b.box((0.026, 0.06, 0.1), (0, 0.12, -0.02), 'GunMetal')
    b.tube((0, -0.04, 0.14), (0, 0.3, 0.14), 0.026, 'Dark', 8)
    b.cyl(0.032, 0.05, (0, 0.3, 0.14), 'Dark', 'y', 8); b.cyl(0.026, 0.005, (0, 0.327, 0.14), 'Glass', 'y', 8)
    b.box((0.014, 0.03, 0.04), (0, 0.03, 0.105), 'Dark'); b.box((0.014, 0.03, 0.04), (0, 0.2, 0.105), 'Dark')
    for sx in (-1, 1):
        b.tube((0, 0.48, 0.03), (sx * 0.1, 0.52, -0.16), 0.008, 'GunMetal', 5)
    grip(b)


def w_rocket(b):
    b.tube((0, -0.5, 0.1), (0, 0.6, 0.1), 0.055, 'LeafDark', 10)
    b.tube((0, 0.6, 0.1), (0, 0.68, 0.1), 0.055, 'Dark', 10, 0.075)
    b.tube((0, -0.5, 0.1), (0, -0.6, 0.1), 0.055, 'Dark', 10, 0.08)
    b.tube((0, 0.66, 0.1), (0, 0.8, 0.1), 0.045, 'Red', 8, 0.0)
    b.box((0.02, 0.08, 0.07), (-0.06, 0.15, 0.18), 'Dark')
    b.box((0.03, 0.04, 0.09), (0, 0.22, 0.01), 'Dark')
    grip(b, 0.0, 0.0)


def w_grenade(b):
    b.tube((0, 0, -0.045), (0, 0, -0.02), 0.025, 'LeafDark', 8, 0.04)
    b.tube((0, 0, -0.02), (0, 0, 0.02), 0.04, 'LeafDark', 8)
    b.tube((0, 0, 0.02), (0, 0, 0.04), 0.04, 'LeafDark', 8, 0.02)
    b.cyl(0.015, 0.03, (0, 0, 0.05), 'Steel', 'z', 6)
    b.box((0.012, 0.02, 0.07), (0.03, 0, 0.03), 'Steel', rot=(0, -15, 0))


def w_knife(b):
    b.box((0.006, 0.18, 0.03), (0, 0.15, 0.0), 'Steel', taper=(1, 0.1), rot=(0, 0, 0))
    b.box((0.012, 0.02, 0.05), (0, 0.055, 0.0), 'GunMetal')
    b.box((0.022, 0.1, 0.028), (0, 0.0, 0.0), 'Dark')


def w_bat(b):
    b.tube((0, -0.06, 0), (0, 0.3, 0), 0.016, 'Wood', 8, 0.02)
    b.tube((0, 0.3, 0), (0, 0.76, 0), 0.02, 'Wood', 8, 0.036)
    b.cyl(0.022, 0.02, (0, -0.07, 0), 'WoodDark', 'y', 8)


def w_proj(b):
    b.tube((0, -0.2, 0), (0, 0.15, 0), 0.04, 'LeafDark', 8)
    b.tube((0, 0.15, 0), (0, 0.32, 0), 0.04, 'Red', 8, 0.0)
    for a in (0, 90):
        b.box((0.16, 0.08, 0.01), (0, -0.17, 0), 'Dark', rot=(0, a, 0))


gun('wpn_pistol', w_pistol, (0, 0.16, 0.062), (0.02, 0.08), None, (-0.02, -0.07), (0.09, 0.03))
gun('wpn_revolver', w_revolver, (0, 0.24, 0.07))
gun('wpn_smg', w_smg, (0, 0.32, 0.055), (0.06, 0.098), (0.2, 0.03), (0.1, -0.135), (0.16, 0.05))
gun('wpn_shotgun', w_shotgun, (0, 0.78, 0.065), (0.02, 0.085), None, None, (0.5, 0.05))
gun('wpn_rifle', lambda b: rifle_base(b), (0, 0.74, 0.052), (0.06, 0.1), (0.36, 0.028), (0.125, -0.13), (0.38, 0.05))
gun('wpn_carbine', lambda b: rifle_base(b, 0.2, 0.56, 'skel'), (0, 0.56, 0.052), (0.06, 0.1), (0.3, 0.028), (0.125, -0.13), (0.3, 0.05))
gun('wpn_marksman', w_marksman, (0, 0.92, 0.052), None, None, (0.125, -0.13))
gun('wpn_sniper', w_sniper, (0, 1.11, 0.055))
gun('wpn_rocket', w_rocket, (0, 0.8, 0.1))
gun('wpn_grenade', w_grenade, (0, 0, 0))
gun('wpn_knife', w_knife, (0, 0.24, 0))
gun('wpn_bat', w_bat, (0, 0.76, 0))
gun('wpn_proj_rocket', w_proj, (0, 0.32, 0))
print('chars/weapons done')
