# Characters (rigged, rigid-skinned humanoid with variants), weapons with attachments, wildlife.
import math

mat('Hat', '#b8322a', rough=0.85)
mat('Uniform', '#1c2740', rough=0.85)
mat('Badge', '#e2c14a', rough=0.3, metal=0.8)


class CB(B):
    def __init__(s):
        super().__init__()
        s.gl = s.bm.verts.layers.int.new('grp')
        s.groups = []
        s.cur = 0

    def bone(s, name):
        if name not in s.groups:
            s.groups.append(name)
        s.cur = s.groups.index(name)
        return s

    def _add(s, verts, faces, m, M=None):
        fs = super()._add(verts, faces, m, M)
        for f in fs:
            for v in f.verts:
                v[s.gl] = s.cur
        return fs

    def skin(s, name, C, arm):
        groups = list(s.groups)
        o = s.obj(name, C, None, weld=False)
        me = o.data
        vals = [d.value for d in me.attributes['grp'].data]
        for gname in groups:
            o.vertex_groups.new(name=gname)
        for i, v in enumerate(vals):
            o.vertex_groups[groups[v]].add([i], 1.0, 'REPLACE')
        me.attributes.remove(me.attributes['grp'])
        o.parent = arm
        md = o.modifiers.new('Armature', 'ARMATURE')
        md.object = arm
        return o


BONES = [  # name, head, tail, parent
    ('Hips', (0, 0, 0.95), (0, 0, 1.1), None),
    ('Spine', (0, 0, 1.1), (0, 0, 1.5), 'Hips'),
    ('Head', (0, 0, 1.5), (0, 0, 1.8), 'Spine'),
    ('UpperArm.R', (0.235, 0, 1.47), (0.235, 0, 1.18), 'Spine'),
    ('LowerArm.R', (0.235, 0, 1.18), (0.235, 0, 0.9), 'UpperArm.R'),
    ('Hand.R', (0.235, 0, 0.9), (0.235, 0, 0.8), 'LowerArm.R'),
    ('UpperArm.L', (-0.235, 0, 1.47), (-0.235, 0, 1.18), 'Spine'),
    ('LowerArm.L', (-0.235, 0, 1.18), (-0.235, 0, 0.9), 'UpperArm.L'),
    ('Hand.L', (-0.235, 0, 0.9), (-0.235, 0, 0.8), 'LowerArm.L'),
    ('UpperLeg.R', (0.095, 0, 0.95), (0.095, 0, 0.52), 'Hips'),
    ('LowerLeg.R', (0.095, 0, 0.52), (0.095, 0, 0.08), 'UpperLeg.R'),
    ('UpperLeg.L', (-0.095, 0, 0.95), (-0.095, 0, 0.52), 'Hips'),
    ('LowerLeg.L', (-0.095, 0, 0.52), (-0.095, 0, 0.08), 'UpperLeg.L'),
]


def make_armature(name, C, place):
    wipe(name)
    ad = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, ad)
    C.objects.link(arm)
    arm.location = place
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for bn, h, t, p in BONES:
        eb = ad.edit_bones.new(bn)
        eb.head = h
        eb.tail = t
        if p:
            eb.parent = ad.edit_bones[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def body(female=False):
    b = CB()
    sw = 0.31 if female else 0.36
    lw = 0.9 if female else 1.0
    ax = 0.21 if female else 0.235
    b.bone('Hips').box('Pants', (0, 0, 1.0), (0.35 if female else 0.34, 0.2, 0.2))
    b.box('Dark', (0, 0, 1.095), (0.355, 0.205, 0.035))
    b.bone('Spine').box('Shirt', (0, 0, 1.3), (sw, 0.2, 0.42), top=(1.05 if female else 1.16, 1.0))
    if female:
        b.box('Shirt', (0, 0.07, 1.36), (0.28, 0.1, 0.13))
    b.cyl('Skin', (0, 0, 1.54), 0.05, 0.08, seg=8)
    b.bone('Head').box('Skin', (0, 0.01, 1.68), (0.18 if female else 0.19, 0.21, 0.23), top=(0.92, 0.92))
    for sx in (-1, 1):
        b.box('Eye', (sx * 0.045, 0.118, 1.7), (0.03, 0.012, 0.03))
    b.box('Skin', (0, 0.125, 1.655), (0.03, 0.03, 0.05))
    for sx, sd in ((1, 'R'), (-1, 'L')):
        b.bone('UpperArm.' + sd).box('Shirt', (sx * ax, 0, 1.33), (0.1 * lw, 0.11 * lw, 0.3))
        b.bone('LowerArm.' + sd).box('Sleeve', (sx * ax, 0, 1.04), (0.085 * lw, 0.095 * lw, 0.28))
        b.bone('Hand.' + sd).box('Skin', (sx * ax, 0, 0.85), (0.07 * lw, 0.09 * lw, 0.11))
        b.bone('UpperLeg.' + sd).box('Pants', (sx * 0.095, 0, 0.73), (0.15 * lw, 0.17 * lw, 0.44), top=(1.06, 1.06))
        b.bone('LowerLeg.' + sd).box('Leg', (sx * 0.095, 0, 0.31), (0.125 * lw, 0.14 * lw, 0.42))
        b.box('Shoes', (sx * 0.095, 0.045, 0.05), (0.125, 0.27, 0.1))
    return b


def build_human():
    C = coll('Characters')
    arm = make_armature('human', C, (-6, 0, 0))
    body(False).skin('human_Body_M', C, arm)
    body(True).skin('human_Body_F', C, arm)
    acc = {}
    b = CB().bone('Head')
    b.box('Hair', (0, -0.005, 1.805), (0.2, 0.225, 0.05)); b.box('Hair', (0, -0.105, 1.71), (0.2, 0.03, 0.16))
    acc['Hair_Short'] = b
    b = CB().bone('Head')
    b.box('Hair', (0, -0.005, 1.805), (0.21, 0.23, 0.06)); b.box('Hair', (0, -0.115, 1.6), (0.22, 0.05, 0.4))
    for sx in (-1, 1):
        b.box('Hair', (sx * 0.1, -0.04, 1.66), (0.03, 0.14, 0.26))
    acc['Hair_Long'] = b
    b = CB().bone('Head')
    b.box('Hair', (0, -0.005, 1.805), (0.2, 0.225, 0.05)); b.box('Hair', (0, -0.105, 1.72), (0.2, 0.03, 0.14))
    b.sphere('Hair', (0, -0.1, 1.86), 0.075, seg=6, rings=4)
    acc['Hair_Bun'] = b
    b = CB().bone('Head')
    b.box('Hair', (0, -0.01, 1.84), (0.05, 0.22, 0.12))
    acc['Hair_Mohawk'] = b
    b = CB().bone('Head')
    b.box('Hair', (0, 0.105, 1.6), (0.17, 0.04, 0.09)); b.box('Hair', (0, 0.12, 1.635), (0.1, 0.02, 0.02))
    acc['Beard'] = b
    b = CB().bone('Head')
    b.box('Hat', (0, 0, 1.815), (0.205, 0.225, 0.08), top=(0.9, 0.9)); b.box('Hat', (0, 0.16, 1.785), (0.18, 0.13, 0.02))
    acc['Cap'] = b
    b = CB().bone('Head')
    b.box('Hat', (0, 0, 1.81), (0.21, 0.23, 0.11), top=(0.75, 0.75)); b.box('Hat', (0, 0, 1.765), (0.22, 0.24, 0.035))
    acc['Beanie'] = b
    b = CB().bone('Head')
    b.box('Uniform', (0, 0, 1.83), (0.24, 0.25, 0.07), top=(1.1, 1.1)); b.box('Black', (0, 0.15, 1.795), (0.2, 0.1, 0.02))
    b.box('Badge', (0, 0.128, 1.83), (0.04, 0.01, 0.04))
    acc['PoliceCap'] = b
    b = CB().bone('Head')
    b.box('Gunmetal', (0, -0.005, 1.74), (0.225, 0.25, 0.2), top=(0.85, 0.85)); b.box('Glass', (0, 0.123, 1.7), (0.19, 0.02, 0.07))
    acc['Helmet'] = b
    b = CB().bone('Head')
    b.box('Dark', (0, 0.122, 1.7), (0.17, 0.012, 0.04))
    for sx in (-1, 1):
        b.box('Dark', (sx * 0.095, 0.06, 1.7), (0.008, 0.12, 0.012))
    acc['Glasses'] = b
    b = CB().bone('Spine')
    b.box('Gunmetal', (0, 0, 1.3), (0.4, 0.26, 0.36), top=(1.08, 1.0))
    b.box('Dark', (0, 0.135, 1.24), (0.3, 0.02, 0.1))
    acc['Vest'] = b
    b = CB().bone('Spine')
    b.box('Fabric', (0, -0.16, 1.32), (0.3, 0.14, 0.4)); b.box('Dark', (0.13, 0.0, 1.33), (0.04, 0.22, 0.38)); b.box('Dark', (-0.13, 0.0, 1.33), (0.04, 0.22, 0.38))
    acc['Pack'] = b
    b = CB().bone('Spine')
    b.cyl('Yellow', (0, -0.18, 1.32), 0.075, 0.46, seg=8); b.cyl('Steel', (0, -0.18, 1.58), 0.03, 0.06, seg=6)
    b.box('Dark', (0, 0.0, 1.33), (0.34, 0.22, 0.05))
    b.bone('Head').box('Glass', (0, 0.125, 1.7), (0.17, 0.04, 0.08))
    acc['Scuba'] = b
    for k, b in acc.items():
        b.skin('human_' + k, C, arm)
    # jacket overlay (changes silhouette)
    b = CB().bone('Spine')
    b.box('Shirt', (0, 0, 1.28), (0.39, 0.23, 0.47), top=(1.14, 1.0))
    b.box('Dark', (0, 0.118, 1.28), (0.02, 0.01, 0.45))
    b.skin('human_Jacket', C, arm)
    MAN['human'] = {'bones': [bn for bn, _, _, _ in BONES], 'acc': list(acc.keys()) + ['Jacket']}
    export_skinned('human', 'characters')


def export_skinned(name, subdir):
    r = bpy.data.objects[name]
    objs = [r] + list(r.children_recursive)
    saved = r.location.copy()
    r.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = r
    d = os.path.join(OUT, subdir)
    os.makedirs(d, exist_ok=True)
    import contextlib, io, logging
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=os.path.join(d, name + '.glb'), export_format='GLB', use_selection=True,
                                  export_apply=False, export_yup=True, export_animations=False, export_skins=True)
    logging.disable(logging.NOTSET)
    r.location = saved


# ---------------- weapons ----------------
def gun(name, place, parts, muzzle, atts=None, kind='gun'):
    C = coll('Weapons')
    r = root(name, C, place)

    def build(pl):
        b = B()
        for p in pl:
            if p[0] == 'b':
                b.box(p[1], p[2], p[3], rot=p[4] if len(p) > 4 else (0, 0, 0))
            elif p[0] == 'c':
                b.cyl(p[1], p[2], p[3], p[4], axis=p[5] if len(p) > 5 else 'Y', seg=8)
            elif p[0] == 't':
                b.box(p[1], p[2], p[3], top=p[4])
        return b
    build(parts).obj(name + '_Body', C, r)
    for an, pl in (atts or {}).items():
        build(pl).obj(name + '_Att_' + an, C, r)
    register(name, muzzle=g(muzzle), kind=kind)
    return r


def std_atts(my, mz, rail_y, rail_z, under_y, under_z, mag_c=None, mag_s=None, scope=True, grip=True, sup_r=0.022):
    a = {'Suppressor': [('c', 'Black', (0, my + 0.09, mz), sup_r, 0.18)],
         'Flashlight': [('c', 'Black', (0, under_y, under_z), 0.016, 0.09), ('c', 'LightHead', (0, under_y + 0.046, under_z), 0.014, 0.004)]}
    if mag_c:
        a['ExtMag'] = [('b', 'Black', mag_c, mag_s)]
    if scope:
        a['Scope'] = [('c', 'Black', (0, rail_y, rail_z + 0.035), 0.02, 0.2), ('c', 'Glass', (0, rail_y + 0.1, rail_z + 0.035), 0.018, 0.004),
                      ('b', 'Black', (0, rail_y, rail_z + 0.008), (0.015, 0.1, 0.02))]
    if grip:
        a['Grip'] = [('b', 'Black', (0, under_y - 0.1, under_z - 0.045), (0.026, 0.03, 0.09))]
    return a


def build_weapons():
    x = -6
    y = -6
    G, Pm, W, S = 'Gunmetal', 'Polymer', 'Wood', 'Steel'
    names = []

    def add(n, parts, muzzle, atts=None, kind='gun'):
        nonlocal x
        gun(n, (x, y, 1), parts, muzzle, atts, kind)
        names.append(n)
        x += 0.6
    add('pistol', [('b', G, (0, 0.06, 0.095), (0.028, 0.2, 0.04)), ('b', Pm, (0, 0.045, 0.062), (0.026, 0.16, 0.028)),
                   ('b', Pm, (0, -0.02, 0.0), (0.028, 0.05, 0.12), (-0.22, 0, 0)), ('b', Pm, (0, 0.04, 0.035), (0.012, 0.06, 0.008)),
                   ('b', Pm, (0, 0.068, 0.045), (0.012, 0.008, 0.028)), ('b', S, (0, 0.14, 0.118), (0.006, 0.01, 0.008))],
        (0, 0.165, 0.095), std_atts(0.165, 0.095, 0, 0, 0.11, 0.05, (0, -0.036, -0.075), (0.024, 0.04, 0.05), scope=False, grip=False, sup_r=0.018))
    add('revolver', [('b', S, (0, 0.11, 0.1), (0.022, 0.22, 0.03)), ('c', S, (0, 0.03, 0.085), 0.03, 0.07), ('b', S, (0, 0.02, 0.085), (0.026, 0.12, 0.06)),
                     ('b', W, (0, -0.035, 0.0), (0.03, 0.05, 0.12), (-0.3, 0, 0)), ('b', S, (0, 0.05, 0.04), (0.01, 0.06, 0.008)),
                     ('b', S, (0, -0.02, 0.125), (0.008, 0.03, 0.02))],
        (0, 0.225, 0.1))
    add('smg', [('b', G, (0, 0.08, 0.1), (0.04, 0.3, 0.06)), ('c', G, (0, 0.27, 0.1), 0.012, 0.1), ('b', Pm, (0, -0.02, 0.0), (0.032, 0.05, 0.13), (-0.2, 0, 0)),
                ('b', Pm, (0, 0.1, 0.0), (0.026, 0.035, 0.16)), ('b', S, (0, -0.16, 0.1), (0.012, 0.2, 0.012)), ('b', S, (0, -0.26, 0.07), (0.03, 0.012, 0.08)),
                ('b', G, (0, 0.08, 0.135), (0.02, 0.24, 0.012))],
        (0, 0.32, 0.1), std_atts(0.32, 0.1, 0.06, 0.14, 0.2, 0.06, (0, 0.1, -0.11), (0.024, 0.033, 0.1)))
    add('shotgun', [('c', G, (0, 0.38, 0.1), 0.016, 0.62), ('c', G, (0, 0.33, 0.07), 0.015, 0.5), ('b', W, (0, 0.33, 0.065), (0.045, 0.2, 0.045)),
                    ('b', G, (0, 0.04, 0.09), (0.04, 0.24, 0.07)), ('b', W, (0, -0.2, 0.06), (0.036, 0.3, 0.09), (0.12, 0, 0)),
                    ('b', W, (0, -0.05, 0.03), (0.032, 0.06, 0.08), (-0.5, 0, 0))],
        (0, 0.69, 0.1), {'Flashlight': [('c', 'Black', (0.03, 0.5, 0.085), 0.016, 0.09), ('c', 'LightHead', (0.03, 0.546, 0.085), 0.014, 0.004)],
                         'ExtMag': [('c', G, (0, 0.6, 0.07), 0.015, 0.12)]})
    add('autoshotgun', [('c', G, (0, 0.36, 0.1), 0.018, 0.56), ('b', Pm, (0, 0.3, 0.085), (0.05, 0.3, 0.06)), ('b', G, (0, 0.03, 0.09), (0.045, 0.26, 0.08)),
                        ('b', Pm, (0, -0.02, 0.0), (0.034, 0.05, 0.13), (-0.2, 0, 0)), ('b', Pm, (0, 0.1, -0.02), (0.04, 0.07, 0.16)),
                        ('b', Pm, (0, -0.25, 0.075), (0.036, 0.26, 0.1))],
        (0, 0.64, 0.1), std_atts(0.64, 0.1, 0.05, 0.135, 0.36, 0.05, (0, 0.1, -0.13), (0.045, 0.075, 0.08), scope=False))
    add('rifle', [('b', G, (0, 0.08, 0.1), (0.04, 0.34, 0.07)), ('c', G, (0, 0.48, 0.105), 0.012, 0.36), ('b', W, (0, 0.34, 0.095), (0.045, 0.24, 0.05)),
                  ('b', W, (0, -0.03, 0.0), (0.032, 0.05, 0.13), (-0.25, 0, 0)), ('b', G, (0, 0.11, -0.02), (0.028, 0.07, 0.2), (0.3, 0, 0)),
                  ('b', W, (0, -0.24, 0.07), (0.036, 0.3, 0.1), (0.1, 0, 0)), ('b', G, (0, 0.6, 0.135), (0.008, 0.012, 0.04)),
                  ('c', S, (0, 0.38, 0.13), 0.008, 0.2)],
        (0, 0.66, 0.105), std_atts(0.66, 0.105, 0.06, 0.14, 0.4, 0.06, (0, 0.135, -0.14), (0.028, 0.07, 0.08)))
    add('carbine', [('b', G, (0, 0.07, 0.1), (0.04, 0.32, 0.075)), ('c', G, (0, 0.42, 0.105), 0.012, 0.28), ('c', Pm, (0, 0.3, 0.105), 0.03, 0.2),
                    ('b', Pm, (0, -0.03, 0.0), (0.032, 0.05, 0.12), (-0.25, 0, 0)), ('b', G, (0, 0.1, -0.01), (0.026, 0.06, 0.16)),
                    ('b', Pm, (0, -0.2, 0.1), (0.03, 0.22, 0.04)), ('b', Pm, (0, -0.3, 0.075), (0.034, 0.05, 0.11)),
                    ('b', G, (0, 0.1, 0.145), (0.02, 0.3, 0.012))],
        (0, 0.56, 0.105), std_atts(0.56, 0.105, 0.06, 0.15, 0.34, 0.065, (0, 0.1, -0.11), (0.026, 0.06, 0.08)))
    add('marksman', [('b', G, (0, 0.08, 0.1), (0.04, 0.36, 0.07)), ('c', G, (0, 0.56, 0.105), 0.012, 0.56), ('b', W, (0, 0.34, 0.09), (0.045, 0.3, 0.05)),
                     ('b', W, (0, -0.03, 0.0), (0.032, 0.05, 0.13), (-0.25, 0, 0)), ('b', G, (0, 0.1, 0.01), (0.026, 0.06, 0.12)),
                     ('b', W, (0, -0.27, 0.07), (0.036, 0.36, 0.11), (0.08, 0, 0)), ('c', 'Black', (0, 0.1, 0.17), 0.02, 0.24),
                     ('c', 'Glass', (0, 0.221, 0.17), 0.018, 0.004), ('b', 'Black', (0, 0.1, 0.143), (0.015, 0.1, 0.02))],
        (0, 0.84, 0.105), std_atts(0.84, 0.105, 0, 0, 0.42, 0.055, (0, 0.1, -0.08), (0.026, 0.06, 0.08), scope=False))
    add('sniper', [('b', G, (0, 0.06, 0.1), (0.045, 0.4, 0.07)), ('c', G, (0, 0.66, 0.105), 0.014, 0.8), ('b', G, (0, 1.06, 0.105), (0.04, 0.08, 0.03)),
                   ('b', Pm, (0, 0.3, 0.085), (0.05, 0.3, 0.05)), ('b', Pm, (0, -0.03, 0.0), (0.034, 0.05, 0.13), (-0.25, 0, 0)),
                   ('b', Pm, (0, -0.3, 0.075), (0.04, 0.34, 0.12)), ('b', Pm, (0, -0.3, 0.15), (0.03, 0.14, 0.03)),
                   ('c', 'Black', (0, 0.08, 0.185), 0.026, 0.34), ('c', 'Glass', (0, 0.251, 0.185), 0.024, 0.004),
                   ('b', 'Black', (0, 0.08, 0.15), (0.016, 0.16, 0.025)), ('b', S, (0.03, 0.42, 0.0), (0.008, 0.012, 0.18), (0, 0.3, 0)),
                   ('b', S, (-0.03, 0.42, 0.0), (0.008, 0.012, 0.18), (0, -0.3, 0)), ('b', G, (0, 0.1, 0.03), (0.03, 0.08, 0.09))],
        (0, 1.1, 0.105), {'Suppressor': [('c', 'Black', (0, 1.2, 0.105), 0.026, 0.24)]})
    add('rpg', [('c', 'Olive', (0, 0.1, 0.1), 0.045, 0.9), ('c', 'Olive', (0, -0.42, 0.1), 0.065, 0.16), ('c', G, (0, 0.6, 0.1), 0.055, 0.14),
                ('b', Pm, (0, -0.0, 0.0), (0.032, 0.05, 0.13), (-0.2, 0, 0)), ('b', Pm, (0, 0.2, 0.01), (0.03, 0.04, 0.11)),
                ('b', G, (0, 0.05, 0.17), (0.02, 0.12, 0.05)), ('c', 'Red', (0, 0.74, 0.1), 0.04, 0.16)],
        (0, 0.85, 0.1))
    add('grenadelauncher', [('c', G, (0, 0.3, 0.1), 0.035, 0.36), ('c', G, (0, 0.06, 0.09), 0.06, 0.14), ('b', G, (0, 0.0, 0.1), (0.04, 0.26, 0.05)),
                            ('b', Pm, (0, -0.03, 0.0), (0.032, 0.05, 0.13), (-0.25, 0, 0)), ('b', Pm, (0, 0.22, 0.02), (0.03, 0.04, 0.1)),
                            ('b', Pm, (0, -0.24, 0.085), (0.034, 0.26, 0.08))],
        (0, 0.49, 0.1))
    add('grenade', [('c', 'Olive', (0, 0, 0.0), 0.04, 0.09, 'Z'), ('c', G, (0, 0, 0.06), 0.018, 0.04, 'Z'), ('b', S, (0.02, 0, 0.06), (0.04, 0.012, 0.05))],
        (0, 0.1, 0), kind='thrown')
    add('knife', [('b', 'Black', (0, 0.0, 0.0), (0.024, 0.11, 0.03)), ('b', S, (0, 0.06, 0.0), (0.012, 0.014, 0.06)),
                  ('t', S, (0, 0.16, 0.0), (0.006, 0.19, 0.035), (1, 0.3))], (0, 0.26, 0), kind='melee')
    add('bat', [('c', W, (0, 0.38, 0), 0.032, 0.5), ('c', W, (0, 0.04, 0), 0.02, 0.26), ('c', 'Black', (0, -0.04, 0), 0.022, 0.14),
                ('c', W, (0, -0.115, 0), 0.028, 0.02)], (0, 0.62, 0), kind='melee')
    add('crowbar', [('c', 'Red', (0, 0.25, 0), 0.012, 0.7), ('b', 'Red', (0, 0.61, 0.025), (0.02, 0.03, 0.07), (0.5, 0, 0)),
                    ('b', S, (0, -0.1, -0.012), (0.02, 0.05, 0.012), (-0.3, 0, 0))], (0, 0.62, 0), kind='melee')
    add('rocket', [('c', 'Olive', (0, 0, 0), 0.04, 0.4), ('c', 'Red', (0, 0.26, 0), 0.04, 0.14), ('b', G, (0, -0.2, 0), (0.16, 0.08, 0.008)),
                   ('b', G, (0, -0.2, 0), (0.008, 0.08, 0.16))], (0, 0.33, 0), kind='projectile')
    export_all(names, 'weapons')
    return names


# ---------------- wildlife ----------------
def animal(name, place, body_parts, legs=None, extra=None):
    C = coll('NPCs/Wildlife')
    r = root(name, C, place)
    b = B()
    for p in body_parts:
        if p[0] == 'b':
            b.box(p[1], p[2], p[3], rot=p[4] if len(p) > 4 else (0, 0, 0), top=p[5] if len(p) > 5 else (1, 1))
        else:
            b.sphere(p[1], p[2], p[3], seg=8, rings=5, scale=p[4])
    b.obj(name + '_Body', C, r)
    for ln, (pos, size, m) in (legs or {}).items():
        lb = B()
        lb.box(m, (0, 0, -size[2] / 2), size)
        lb.obj(name + '_' + ln, C, r, loc=pos)
    for en, (pos, parts) in (extra or {}).items():
        eb = B()
        for p in parts:
            eb.box(p[1], p[2], p[3], rot=p[4] if len(p) > 4 else (0, 0, 0), top=p[5] if len(p) > 5 else (1, 1))
        eb.obj(name + '_' + en, C, r, loc=pos)
    register(name, kind='animal')


def quad_legs(x, yf, yr, z, s, m):
    return {'Leg_FL': ((-x, yf, z), s, m), 'Leg_FR': ((x, yf, z), s, m), 'Leg_RL': ((-x, yr, z), s, m), 'Leg_RR': ((x, yr, z), s, m)}


def build_wildlife():
    F, FD = 'Fur', 'FurDark'
    animal('deer', (-6, 6, 0), [('b', F, (0, 0, 0.95), (0.3, 0.95, 0.36)), ('b', F, (0, 0.55, 1.25), (0.14, 0.2, 0.5), (0.5, 0, 0)),
                                ('b', F, (0, 0.78, 1.5), (0.15, 0.32, 0.16)), ('b', 'Black', (0, 0.945, 1.48), (0.06, 0.02, 0.05)),
                                ('b', 'White', (0, -0.5, 1.05), (0.1, 0.06, 0.14)),
                                ('b', FD, (0.07, 0.7, 1.72), (0.02, 0.02, 0.3), (0, 0.3, 0)), ('b', FD, (-0.07, 0.7, 1.72), (0.02, 0.02, 0.3), (0, -0.3, 0)),
                                ('b', FD, (0.14, 0.7, 1.8), (0.02, 0.1, 0.02)), ('b', FD, (-0.14, 0.7, 1.8), (0.02, 0.1, 0.02))],
           quad_legs(0.1, 0.36, -0.38, 0.8, (0.07, 0.08, 0.8), FD))
    animal('dog', (-4.5, 6, 0), [('b', FD, (0, 0, 0.45), (0.2, 0.6, 0.22)), ('b', FD, (0, 0.4, 0.6), (0.17, 0.22, 0.18)),
                                 ('b', FD, (0, 0.55, 0.56), (0.09, 0.14, 0.08)), ('b', 'Black', (0, 0.625, 0.58), (0.04, 0.02, 0.03)),
                                 ('b', FD, (0.06, 0.34, 0.72), (0.04, 0.03, 0.08)), ('b', FD, (-0.06, 0.34, 0.72), (0.04, 0.03, 0.08)),
                                 ('b', FD, (0, -0.36, 0.56), (0.04, 0.04, 0.22), (-0.6, 0, 0))],
           quad_legs(0.07, 0.22, -0.24, 0.36, (0.055, 0.06, 0.36), FD))
    animal('rabbit', (-3.5, 6, 0), [('b', 'White', (0, 0, 0.16), (0.14, 0.26, 0.16)), ('b', 'White', (0, 0.15, 0.25), (0.11, 0.12, 0.11)),
                                    ('b', 'White', (0.03, 0.14, 0.38), (0.03, 0.02, 0.16)), ('b', 'White', (-0.03, 0.14, 0.38), (0.03, 0.02, 0.16)),
                                    ('b', 'White', (0, -0.15, 0.2), (0.06, 0.05, 0.06))],
           quad_legs(0.05, 0.08, -0.09, 0.09, (0.04, 0.05, 0.09), 'White'))
    animal('cow', (-2, 6, 0), [('b', 'White', (0, 0, 1.0), (0.6, 1.5, 0.6)), ('b', 'Black', (0.305, 0.2, 1.05), (0.02, 0.5, 0.3)), ('b', 'Black', (-0.305, -0.3, 1.0), (0.02, 0.6, 0.35)),
                               ('b', 'White', (0, 0.9, 1.15), (0.3, 0.45, 0.32)), ('b', 'Skin', (0, 1.13, 1.08), (0.22, 0.06, 0.16)),
                               ('b', 'White', (0.2, 0.8, 1.34), (0.14, 0.04, 0.06)), ('b', 'White', (-0.2, 0.8, 1.34), (0.14, 0.04, 0.06)),
                               ('b', 'Skin', (0, -0.3, 0.66), (0.2, 0.24, 0.1))],
           quad_legs(0.2, 0.55, -0.55, 0.72, (0.13, 0.14, 0.72), 'White'))
    animal('seagull', (-0.5, 6, 0.5), [('b', 'Feather', (0, 0, 0), (0.1, 0.3, 0.1)), ('b', 'Feather', (0, 0.17, 0.05), (0.07, 0.09, 0.08)),
                                       ('b', 'Yellow', (0, 0.25, 0.04), (0.025, 0.07, 0.025)), ('b', 'Steel', (0, -0.2, 0.0), (0.09, 0.12, 0.02))],
           None, {'Wing_L': ((-0.05, 0, 0.04), [('b', 'Steel', (-0.28, 0, 0), (0.56, 0.16, 0.015))]),
                  'Wing_R': ((0.05, 0, 0.04), [('b', 'Steel', (0.28, 0, 0), (0.56, 0.16, 0.015))])})
    animal('fish', (0.5, 6, 0.5), [('b', 'Fish', (0, 0, 0), (0.07, 0.28, 0.14), (0, 0, 0), (0.6, 0.8)), ('b', 'Eye', (0.036, 0.09, 0.02), (0.01, 0.02, 0.02)),
                                   ('b', 'Eye', (-0.036, 0.09, 0.02), (0.01, 0.02, 0.02)), ('b', 'Fish', (0, 0, 0.09), (0.015, 0.1, 0.05))],
           None, {'Tail': ((0, -0.14, 0), [('b', 'Fish', (0, -0.06, 0), (0.015, 0.12, 0.16), (0, 0, 0), (1, 1))])})
    animal('shark', (2.5, 6, 0.8), [('b', 'Shark', (0, 0.2, 0), (0.5, 2.0, 0.5), (0, 0, 0), (0.7, 0.9)), ('b', 'Shark', (0, 1.45, -0.03), (0.34, 0.6, 0.3), (0, 0, 0), (0.5, 0.6)),
                                    ('b', 'White', (0, 0.3, -0.24), (0.36, 1.7, 0.04)), ('b', 'Shark', (0, 0.1, 0.42), (0.04, 0.5, 0.42), (-0.5, 0, 0), (1, 0.3)),
                                    ('b', 'Shark', (0.4, 0.5, -0.12), (0.5, 0.3, 0.04), (0, 0.3, -0.4)), ('b', 'Shark', (-0.4, 0.5, -0.12), (0.5, 0.3, 0.04), (0, -0.3, 0.4)),
                                    ('b', 'Eye', (0.2, 1.3, 0.04), (0.02, 0.05, 0.05)), ('b', 'Eye', (-0.2, 1.3, 0.04), (0.02, 0.05, 0.05))],
           None, {'Tail': ((0, -0.8, 0), [('b', 'Shark', (0, -0.3, 0), (0.2, 0.7, 0.3), (0, 0, 0), (0.4, 1)),
                                           ('b', 'Shark', (0, -0.72, 0.22), (0.04, 0.3, 0.6), (0.5, 0, 0)), ('b', 'Shark', (0, -0.7, -0.14), (0.04, 0.25, 0.36), (-0.6, 0, 0))])})
    names = ['deer', 'dog', 'rabbit', 'cow', 'seagull', 'fish', 'shark']
    export_all(names, 'wildlife')
    return names
