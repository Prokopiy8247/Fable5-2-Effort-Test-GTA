# Buildings (modular generator), street props, interiors, nature, VFX helper meshes.
from gta_lib import *
import random
PAL.update({'TLRed': (0x4a1210, 0.4, 0, 0), 'TLYellow': (0x4a3d10, 0.4, 0, 0), 'TLGreen': (0x103d1a, 0.4, 0, 0),
            'PoliceBlue': (0x1f2c4d, 0.85, 0, 0), 'Water': (0x3a8fc0, 0.2, 0, 0), 'Flash': (0xffd870, 0.5, 0, 4.0), 'Mattress': (0x9db7d6, 0.9, 0, 0)})


def text(name, s, size, loc, mat, parent, c, rz=math.pi):
    cu = bpy.data.curves.new(name + '_c', 'FONT')
    cu.body = s
    cu.size = size
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.extrude = 0.04
    cu.resolution_u = 2
    o = bpy.data.objects.new(name + '_tmp', cu)
    c.objects.link(o)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.curves.remove(cu)
    me.materials.clear()
    me.materials.append(M(mat))
    t = bpy.data.objects.new(name, me)
    c.objects.link(t)
    t.parent = parent
    t.location = loc
    t.rotation_euler = (math.pi / 2, 0, rz)
    return t


def windows(b, rnd, w, d, h, fl, k0, style):
    k = k0
    while (k + 1) * fl <= h + 0.01:
        z = k * fl + fl * 0.55
        for axis, span, off in (('x', w, d / 2), ('x', w, -d / 2), ('y', d, w / 2), ('y', d, -w / 2)):
            n = max(1, int(span / (3.2 if style == 'band' else 2.4)))
            sp = (span - 0.8) / n
            for i in range(n):
                p = -span / 2 + 0.4 + sp * (i + 0.5)
                m = 'WinLit' if rnd.random() < 0.42 else 'WinDark'
                ww = sp - 0.12 if style == 'band' else min(1.4, sp * 0.62)
                wh = fl * 0.62 if style == 'band' else fl * 0.48
                if axis == 'x':
                    b.box((ww, 0.08, wh), (p, off, z), m)
                else:
                    b.box((0.08, ww, wh), (off, p, z), m)
        k += 1


def flat_roof(b, rnd, w, d, h, wall):
    for sx in (-1, 1):
        b.box((0.3, d, 0.6), (sx * (w / 2 - 0.15), 0, h + 0.3), wall)
        b.box((w, 0.3, 0.6), (0, sx * (d / 2 - 0.15), h + 0.3), wall)
    b.box((w - 0.6, d - 0.6, 0.1), (0, 0, h + 0.05), 'Roof')
    for i in range(max(1, int(w * d / 150))):
        s = rnd.uniform(1.2, 2.4)
        b.box((s, s * 1.3, 1.0), (rnd.uniform(-w / 2 + 2, w / 2 - 2), rnd.uniform(-d / 2 + 2, d / 2 - 2), h + 0.6), 'Metal')
    b.box((2.4, 2.4, 2.4), (w / 2 - 2.5, -d / 2 + 2.5, h + 1.2), 'ConcreteDark')


def storefront(b, w, d, awn):
    b.box((w - 1.2, 0.1, 2.3), (0, d / 2, 1.45), 'Glass')
    b.box((1.2, 0.14, 2.3), (0, d / 2 + 0.01, 1.15), 'Door')
    b.box((0.06, 0.05, 0.3), (0.4, d / 2 + 0.1, 1.15), 'Chrome')
    if awn:
        b.box((w - 0.6, 1.3, 0.1), (0, d / 2 + 0.6, 2.95), awn, rot=(-12, 0, 0))


def bld(name, w, d, h, wall, fl=3.3, style='punch', roof='flat', shop=None, sign=None, signmat='SignWhite',
        extra=None, k0=None, row=10, step=45):
    c = coll('Buildings')
    r = root(name, c, slot(row, step))
    rnd = random.Random(name)
    b = B()
    b.box((w, d, h), (0, 0, h / 2), wall)
    b.box((w + 0.16, d + 0.16, 0.45), (0, 0, 0.225), 'ConcreteDark')
    if style:
        windows(b, rnd, w, d, h, fl, (1 if shop else 0) if k0 is None else k0, style)
    if roof == 'flat':
        flat_roof(b, rnd, w, d, h, wall)
    elif roof:
        rh = 0.28 * d if roof[0] == 'g' else 0.1 * d
        tri = [(-w / 2 - 0.4, h - 0.05), (0, h + rh), (w / 2 + 0.4, h - 0.05)]
        b.loft([(-d / 2 - 0.4, tri), (d / 2 + 0.4, tri)], roof[1:])
    if shop:
        storefront(b, w, d, shop)
    else:
        b.box((1.3, 0.14, 2.3), (0, d / 2 + 0.01, 1.15), 'Door')
    if extra:
        extra(b, rnd)
    b.obj(name + '__mesh', c, r)
    if sign:
        sz = min(1.5, (w * 0.8) / max(4, len(sign)) * 1.5)
        zz = (fl + 0.55) if h > fl + 1.6 else h + 0.9
        sb = B()
        sb.box((min(w - 0.5, len(sign) * sz * 0.72 + 1.0), 0.16, sz * 1.5), (0, d / 2 + 0.08, zz), 'Dark')
        if zz > h:
            for sx in (-1, 1):
                sb.box((0.15, 0.15, 1.0), (sx * 2, d / 2 - 0.3, h + 0.4), 'Dark')
        sb.obj(name + '__signboard', c, r)
        text(name + '__sign', sign, sz, (0, d / 2 + 0.17, zz), signmat, r, c)
    export(r, 'buildings')
    return r


def x_setback(w, d, h, wall, top):
    def f(b, rnd):
        b.box((w, d, top), (0, 0, h + top / 2), wall)
        windows(b, rnd, w, d, top, 3.3, 0, 'band')
        for k in range(int(top / 3.3)):
            pass
        b.box((w - 0.6, d - 0.6, 0.3), (0, 0, h + top + 0.15), 'Roof')
        b.tube((0, 0, h + top), (0, 0, h + top + 9), 0.15, 'Steel', 6, 0.03)
    return f


def x_balcony(w, d, h):
    def f(b, rnd):
        k = 1
        while (k + 1) * 3.3 <= h:
            for x in (-w / 4, w / 4):
                b.box((3.2, 1.2, 0.12), (x, d / 2 + 0.6, k * 3.3 + 0.1), 'Concrete')
                b.box((3.2, 0.06, 0.9), (x, d / 2 + 1.17, k * 3.3 + 0.6), 'Metal')
            k += 1
    return f


def x_garage(b, rnd):
    b.box((3.4, 0.12, 2.5), (-3.2, 4.52 + 0.0, 1.25), 'LightGrey')
    for i in range(4):
        b.box((3.4, 0.14, 0.04), (-3.2, 4.53, 0.5 + i * 0.6), 'Grey')
    b.box((0.5, 0.5, 1.2), (3.5, 0, 4.0), 'Brick')


def x_cross(w, d, h):
    def f(b, rnd):
        for sx in (-1, 1):
            b.box((0.6, 0.2, 2.6), (sx * (w / 2 - 3), d / 2 + 0.05, h - 3), 'SignRed')
            b.box((2.6, 0.2, 0.6), (sx * (w / 2 - 3), d / 2 + 0.05, h - 3), 'SignRed')
        b.box((8, 5, 0.3), (0, d / 2 + 2.5, 3.6), 'White')
        for sx in (-1, 1):
            b.box((0.4, 0.4, 3.6), (sx * 3.6, d / 2 + 4.6, 1.8), 'White')
        b.cyl(5, 0.15, (0, 0, h + 0.7), 'ConcreteDark', 'z', 16)
    return f


def x_police(w, d, h):
    def f(b, rnd):
        b.box((w + 0.1, d + 0.1, 0.8), (0, 0, 3.6), 'PoliceBlue' if 'PoliceBlue' in PAL else 'Blue')
        for sx in (-1, 1):
            b.box((0.5, 0.5, 3.4), (sx * 3, d / 2 + 2.6, 1.7), 'Concrete')
        b.box((8, 3.4, 0.4), (0, d / 2 + 1.5, 3.5), 'Concrete')
        b.box((0.4, 0.3, 0.3), (-1.5, d / 2 + 3.0, 3.85), 'SirenBlue'); b.box((0.4, 0.3, 0.3), (1.5, d / 2 + 3.0, 3.85), 'SirenRed')
    return f


def x_factory(b, rnd):
    for x in (-12, -6):
        b.tube((x, -8, 12), (x, -8, 30), 1.4, 'Brick', 10, 1.0)
        b.cyl(1.15, 0.6, (x, -8, 30.2), 'Dark', 'z', 10)
    for i in range(5):
        b.loft([(-14, [(i * 8 - 20, 12), (i * 8 - 20, 15), (i * 8 - 12, 12)]), (14, [(i * 8 - 20, 12), (i * 8 - 20, 15), (i * 8 - 12, 12)])], 'Corrugated')
    for x in (-10, 4):
        b.box((6, 0.2, 5), (x, 14.05, 2.5), 'MetalRust')
    b.tube((16, 10, 0), (16, 10, 9), 2.2, 'Metal', 12)
    b.tube((16, 10, 9), (16, 10, 10.5), 2.2, 'Metal', 12, 0.3)


def x_ware(w, d, h):
    def f(b, rnd):
        for x in (-w / 4, w / 4):
            b.box((7, 0.2, 5.5), (x, d / 2 + 0.05, 2.75), 'LightGrey')
            for i in range(8):
                b.box((7, 0.22, 0.05), (x, d / 2 + 0.06, 0.5 + i * 0.65), 'Grey')
        b.box((w * 0.7, 0.1, 1.2), (0, d / 2 + 0.03, h - 1.6), 'WinDark')
        b.box((w * 0.7, 0.1, 1.2), (0, -d / 2 - 0.03, h - 1.6), 'WinDark')
    return f


c = coll('Buildings')
bld('bld_office_a', 26, 26, 56, 'OfficeBlue', style='band', shop='AwningBlue')
bld('bld_office_b', 22, 30, 42, 'OfficeTeal', style='band')
bld('bld_office_c', 30, 22, 30, 'OfficeGrey', style='punch', shop='AwningRed')
bld('bld_office_d', 22, 22, 36, 'Concrete', style='band', extra=x_setback(15, 15, 36, 'OfficeBlue', 33), roof=None)
bld('bld_apart_a', 24, 16, 20, 'Brick', extra=x_balcony(24, 16, 20))
bld('bld_apart_b', 20, 18, 26.5, 'PlasterCream', extra=x_balcony(20, 18, 26.5))
bld('bld_apart_c', 22, 14, 13.3, 'PlasterPink', shop='AwningGreen')
bld('bld_house_a', 10, 9, 3.4, 'PlasterCream', roof='gRoofRed', row=11, step=20)
bld('bld_house_b', 12, 8, 6.6, 'PlasterBlue', roof='gRoof', row=11, step=20)
bld('bld_house_c', 11, 9, 3.4, 'PlasterMint', roof='gRoofBlue', extra=x_garage, row=11, step=20)
bld('bld_house_d', 9, 9, 6.6, 'PlasterSand', roof='gRoofRed', row=11, step=20)
bld('bld_shop_a', 14, 12, 8, 'PlasterSand', shop='AwningGreen', sign='FRESH MARKET', signmat='SignGreen', row=11, step=20)
bld('bld_shop_b', 12, 12, 7, 'Brick', shop='AwningRed', sign='BEAN ROOM', signmat='SignYellow', row=11, step=20)
bld('bld_shop_c', 16, 12, 9, 'PlasterBlue', shop='AwningYellow', sign='VOLT ELECTRO', signmat='SignBlue', row=11, step=20)
bld('bld_shop_d', 12, 12, 6.6, 'PlasterMint', shop='AwningBlue', sign='PIZZA ORBIT', signmat='SignOrange', row=11, step=20)
bld('bld_gunshop', 14, 12, 6.6, 'ConcreteDark', shop='AwningRed', sign='IRONSIDE ARMS', signmat='SignRed', row=12, step=30)
bld('bld_clothes', 14, 12, 7, 'PlasterPink', shop='AwningBlue', sign='THREADLINE', signmat='SignPurple', row=12, step=30)
bld('bld_barber', 10, 10, 5, 'PlasterCream', shop='AwningRed', sign='CLIP JOINT', signmat='SignWhite', row=12, step=30)
bld('bld_police', 28, 20, 10, 'PlasterSand', sign='POLICE', signmat='SignBlue', extra=x_police(28, 20, 10), row=12, step=30)
bld('bld_hospital', 30, 24, 19.8, 'White', sign='HOSPITAL', signmat='SignRed', extra=x_cross(30, 24, 19.8), row=12, step=35)
bld('bld_warehouse_a', 36, 24, 10, 'Corrugated', style=None, roof='sMetal', extra=x_ware(36, 24, 10), row=13)
bld('bld_warehouse_b', 28, 20, 8, 'CorrugatedGreen', style=None, roof='sMetal', extra=x_ware(28, 20, 8), row=13)
bld('bld_factory', 40, 28, 12, 'Brick', style=None, roof=None, extra=x_factory, sign='KESSLER WORKS', signmat='SignYellow', row=13)
bld('bld_range', 16, 10, 5, 'ConcreteDark', style=None, roof='sMetalRust', sign='BULLSEYE RANGE', signmat='SignOrange', row=13)


def custom(name, fn, row=14, step=45, sign=None, signloc=None, signmat='SignOrange', sz=1.2):
    r = root(name, c, slot(row, step))
    b = B()
    fn(b)
    b.obj(name + '__mesh', c, r)
    if sign:
        text(name + '__sign', sign, sz, signloc, signmat, r, c)
    export(r, 'buildings')


def shell(b, w, d, h, wall, door_w, door_h, t=0.4, roofm='Roof', floor='Concrete'):
    """Enterable room: walls with a front (+Y) opening, roof and floor."""
    b.box((w, t, h), (0, -d / 2 + t / 2, h / 2), wall)
    for sx in (-1, 1):
        b.box((t, d, h), (sx * (w / 2 - t / 2), 0, h / 2), wall)
        sw = (w - door_w) / 2
        b.box((sw, t, h), (sx * (door_w / 2 + sw / 2), d / 2 - t / 2, h / 2), wall)
    b.box((door_w, t, h - door_h), (0, d / 2 - t / 2, door_h + (h - door_h) / 2), wall)
    b.box((w + 0.4, d + 0.4, 0.35), (0, 0, h + 0.17), roofm)
    b.box((w - 0.1, d - 0.1, 0.1), (0, 0, 0.05), floor)


def modshop(b):
    shell(b, 18, 16, 7, 'ConcreteDark', 7, 4.4)
    b.box((18.5, 0.3, 1.6), (0, 8.1, 6.0), 'SignOrange')
    b.box((18.6, 0.32, 0.25), (0, 8.1, 5.05), 'Dark')
    for sx in (-1, 1):
        b.box((0.3, 0.3, 4.4), (sx * 3.65, 8.05, 2.2), 'Yellow')
        b.box((1.5, 4, 1.0), (sx * 7.5, -3, 0.5), 'Red')
        b.box((1.5, 4, 0.08), (sx * 7.5, -3, 1.04), 'Steel')
    b.box((6, 0.8, 0.5), (0, -7, 3.2), 'Steel')
    for x in (-2, 0, 2):
        b.cyl(0.33, 0.24, (x, -7.3, 1.2), 'Tire', 'y', 10)


def gas(b):
    b.box((18, 11, 0.6), (0, 4, 5.4), 'White')
    b.box((18.1, 11.1, 0.25), (0, 4, 5.25), 'SignRed')
    for sx in (-1, 1):
        for y in (0.5, 7.5):
            b.box((0.5, 0.5, 5.2), (sx * 6, y, 2.6), 'LightGrey')
        b.box((2.6, 7.4, 0.25), (sx * 6, 4, 0.125), 'Concrete')
        for y in (2.2, 5.8):
            b.box((0.9, 0.6, 1.7), (sx * 6, y, 1.1), 'Red')
            b.box((0.7, 0.62, 0.4), (sx * 6, y, 1.5), 'White')
    b.box((12, 7, 3.8), (0, -7, 1.9), 'White')
    b.box((12.3, 7.3, 0.3), (0, -7, 3.9), 'SignRed')
    b.box((8, 0.1, 2.2), (0, -3.48, 1.5), 'Glass')
    b.box((1.2, 0.14, 2.3), (4.8, -3.47, 1.15), 'Door')
    b.box((0.4, 0.4, 8), (10.5, 9, 4), 'LightGrey')
    b.box((3.4, 0.5, 2.2), (10.5, 9, 7.6), 'SignRed')


def hangar(b):
    w, d, h = 30, 28, 9
    pts = [(-w / 2 - 0.3, h)] + [(-w / 2 * math.cos(math.pi * i / 8), h + 4.5 * math.sin(math.pi * i / 8)) for i in range(1, 8)] + [(w / 2 + 0.3, h)]
    inner = [(x * 0.97, z - 0.4 if 0 < i < 8 else z) for i, (x, z) in enumerate(pts)]
    b.loft([(-d / 2, pts + inner[::-1]), (d / 2, pts + inner[::-1])], 'Corrugated')
    b.loft([(-d / 2, pts), (-d / 2 + 0.4, pts)], 'Corrugated')
    b.box((w, 0.4, h), (0, -d / 2 + 0.2, h / 2), 'Corrugated')
    for sx in (-1, 1):
        b.box((0.4, d, h), (sx * (w / 2 - 0.2), 0, h / 2), 'Corrugated')
        b.box((3.5, 0.4, h), (sx * (w / 2 - 1.75), d / 2 - 0.2, h / 2), 'Corrugated')
    b.box((w - 0.4, d - 0.4, 0.08), (0, 0, 0.04), 'Concrete')
    b.box((8, 0.1, 0.3), (0, d / 2 + 0.01, h + 2.5), 'SignYellow')


def tower(b):
    b.tube((0, 0, 0), (0, 0, 17), 3.2, 'Concrete', 8, 2.6)
    b.tube((0, 0, 17), (0, 0, 18), 2.6, 'ConcreteDark', 8, 5.2)
    b.tube((0, 0, 18), (0, 0, 21), 5.2, 'WinDark', 8, 5.8)
    b.tube((0, 0, 21), (0, 0, 21.6), 6.1, 'Roof', 8, 5.2)
    b.tube((0, 0, 21.6), (0, 0, 27), 0.12, 'Steel', 6, 0.03)
    b.box((0.5, 0.5, 0.5), (0, 0, 27), 'SirenRed')
    b.box((1.3, 0.2, 2.3), (0, 3.15, 1.15), 'Door')


def parking(b):
    w, d = 30, 30
    for k in range(4):
        z = k * 3.6
        if k > 0:
            b.box((w, d, 0.4), (0, 0, z), 'Concrete')
            for sx in (-1, 1):
                b.box((0.3, d, 1.1), (sx * (w / 2 - 0.15), 0, z + 0.75), 'ConcreteDark')
                b.box((w, 0.3, 1.1), (0, sx * (d / 2 - 0.15), z + 0.75), 'ConcreteDark')
        if k < 3:
            for x in (-14.5, -5, 5, 14.5):
                for y in (-14.5, -5, 5, 14.5):
                    b.box((0.7, 0.7, 3.6), (x, y, z + 1.8), 'ConcreteDark')
    b.box((5, 5, 14), (-12, -12, 7), 'OfficeGrey')
    b.box((6, 0.3, 1.4), (0, 15.2, 4.4), 'SignBlue')


def safehouse(b):
    shell(b, 12, 10, 3.6, 'PlasterCream', 1.5, 2.4, 0.3, 'Roof', 'Wood')
    b.box((12, 10, 3.2), (0, 0, 5.4), 'PlasterCream')
    b.loft([(-5.4, [(-6.4, 6.95), (0, 9.6), (6.4, 6.95)]), (5.4, [(-6.4, 6.95), (0, 9.6), (6.4, 6.95)])], 'RoofBlue')
    for x in (-3.5, 3.5):
        b.box((1.6, 0.1, 1.4), (x, 5.02, 5.4), 'WinLit')
        b.box((1.6, 0.1, 1.3), (x, 5.02, 1.9), 'WinDark')
    b.box((2.2, 1.4, 0.2), (0, 5.6, 0.1), 'Concrete')
    b.box((2.4, 1.6, 0.12), (0, 5.7, 2.75), 'RoofBlue')
    # attached garage
    b.box((6, 0.3, 3.2), (9, -4.85, 1.6), 'PlasterCream')
    b.box((0.3, 10, 3.2), (11.85, 0, 1.6), 'PlasterCream')
    b.box((6.2, 10.2, 0.3), (9, 0, 3.35), 'Roof')
    b.box((5.9, 9.9, 0.08), (9, 0, 0.04), 'Concrete')
    b.box((0.5, 0.3, 3.2), (11.6, 4.85, 1.6), 'PlasterCream')


custom('bld_modshop', modshop, sign='TORQUE WORKS', signloc=(0, 8.28, 6.0), signmat='SignWhite', sz=1.3)
custom('bld_gas', gas, sign='PETROLA', signloc=(0, 9.62, 5.5), signmat='SignWhite', sz=1.0)
custom('bld_hangar', hangar)
custom('bld_tower', tower)
custom('bld_parking', parking, sign='PARKING', signloc=(0, 15.38, 4.4), signmat='SignWhite', sz=1.0)
custom('bld_safehouse', safehouse)

# ---------------- props ----------------
pc = coll('StreetProps')


def prop(name, fn, cpath='StreetProps', row=15, step=4, sub='props'):
    cc = coll(cpath)
    r = root(name, cc, slot(row, step))
    b = B()
    fn(b)
    b.obj(name + '__mesh', cc, r)
    export(r, sub)
    return r


def p_tlight(b):
    b.tube((0, 0, 0), (0, 0, 5.6), 0.09, 'Dark', 6)
    b.box((0.3, 0.3, 0.4), (0, 0, 0.2), 'Dark')
    b.tube((0, 0, 5.4), (0, 3.6, 5.4), 0.06, 'Dark', 6)
    for y, zz in ((3.4, 4.9), (0.0, 3.2)):
        b.box((0.36, 0.3, 1.05), (0, y, zz), 'Dark')
        for i, m in enumerate(('TLRed', 'TLYellow', 'TLGreen')):
            b.cyl(0.11, 0.05, (0.18, y, zz + 0.33 - i * 0.33), m, 'x', 8)
            b.cyl(0.11, 0.05, (-0.18, y, zz + 0.33 - i * 0.33), m, 'x', 8)


def p_lamp(b):
    b.tube((0, 0, 0), (0, 0, 7.2), 0.09, 'Grey', 6, 0.06)
    b.box((0.34, 0.34, 0.5), (0, 0, 0.25), 'Grey')
    b.tube((0, 0, 7.1), (0, 1.8, 7.4), 0.05, 'Grey', 6)
    b.box((0.34, 0.9, 0.12), (0, 2.0, 7.4), 'Grey')
    b.box((0.26, 0.7, 0.05), (0, 2.0, 7.32), 'LampGlow')


def p_stop(b):
    b.tube((0, 0, 0), (0, 0, 2.6), 0.04, 'Steel', 6)
    b.cyl(0.38, 0.04, (0, 0.05, 2.5), 'Red', 'y', 8)
    b.box((0.4, 0.05, 0.1), (0, 0.06, 2.5), 'White')


def p_speed(b):
    b.tube((0, 0, 0), (0, 0, 2.6), 0.04, 'Steel', 6)
    b.box((0.55, 0.04, 0.7), (0, 0.05, 2.4), 'White')
    b.box((0.4, 0.05, 0.12), (0, 0.055, 2.6), 'Black'); b.cyl(0.14, 0.05, (0, 0.055, 2.3), 'Black', 'y', 8)


def p_barrier(b):
    b.prof([(-0.3, 0), (0.3, 0), (0.3, 0.2), (0.1, 0.45), (0.08, 0.9), (-0.08, 0.9), (-0.1, 0.45), (-0.3, 0.2)], 3.0, 'Concrete')


def p_roadblock(b):
    b.box((3.2, 0.08, 0.3), (0, 0, 0.95), 'White')
    for i in range(5):
        b.box((0.3, 0.09, 0.3), (-1.3 + i * 0.65, 0, 0.95), 'SignOrange', rot=(0, 0, 0))
    b.box((3.2, 0.08, 0.16), (0, 0, 0.5), 'White')
    for sx in (-1.4, 1.4):
        b.box((0.08, 0.7, 0.08), (sx, 0, 0.04), 'Dark'); b.box((0.08, 0.08, 1.15), (sx, 0, 0.6), 'Dark')
    b.box((0.2, 0.1, 0.14), (-1.4, 0, 1.2), 'Amber'); b.box((0.2, 0.1, 0.14), (1.4, 0, 1.2), 'Amber')


def p_bench(b):
    b.box((1.8, 0.5, 0.07), (0, 0, 0.45), 'Wood'); b.box((1.8, 0.07, 0.45), (0, -0.24, 0.75), 'Wood', rot=(-10, 0, 0))
    for sx in (-0.75, 0.75):
        b.box((0.08, 0.5, 0.45), (sx, 0, 0.22), 'Dark')


def p_bin(b):
    b.tube((0, 0, 0), (0, 0, 0.9), 0.26, 'LeafDark', 8, 0.3); b.cyl(0.32, 0.08, (0, 0, 0.94), 'Dark', 'z', 8)


def p_hydrant(b):
    b.tube((0, 0, 0), (0, 0, 0.6), 0.12, 'Red', 8); b.tube((0, 0, 0.6), (0, 0, 0.75), 0.12, 'Red', 8, 0.04)
    b.cyl(0.06, 0.4, (0, 0, 0.42), 'Red', 'x', 6); b.cyl(0.16, 0.06, (0, 0, 0.03), 'Red', 'z', 8)


def p_busstop(b):
    b.box((3.6, 1.5, 0.1), (0, 0, 2.5), 'Dark')
    b.box((3.6, 0.06, 2.0), (0, -0.7, 1.3), 'Glass'); b.box((0.06, 1.3, 2.0), (-1.77, 0, 1.3), 'Glass')
    for sx in (-1.75, 1.75):
        b.box((0.1, 0.1, 2.5), (sx, -0.7, 1.25), 'Dark'); b.box((0.1, 0.1, 2.5), (sx, 0.7, 1.25), 'Dark')
    b.box((2.4, 0.4, 0.08), (0, -0.4, 0.5), 'Wood'); b.box((0.5, 0.08, 0.7), (1.75, 0.75, 2.2), 'SignBlue')


def p_fence(b):
    for sx in (-1.5, 1.5):
        b.tube((sx, 0, 0), (sx, 0, 1.9), 0.04, 'Steel', 6)
    b.box((3.0, 0.03, 0.05), (0, 0, 1.85), 'Steel'); b.box((3.0, 0.03, 0.05), (0, 0, 0.1), 'Steel')
    b.box((3.0, 0.015, 1.7), (0, 0, 0.97), 'Metal')


def p_utility(b):
    b.box((0.9, 0.5, 1.3), (0, 0, 0.65), 'LightGrey'); b.box((0.8, 0.52, 0.04), (0, 0, 0.9), 'Grey'); b.box((0.1, 0.53, 0.2), (0.25, 0, 0.6), 'Yellow')


def p_bollard(b):
    b.tube((0, 0, 0), (0, 0, 0.85), 0.09, 'Yellow', 8); b.cyl(0.095, 0.1, (0, 0, 0.7), 'Dark', 'z', 8)


def p_cone(b):
    b.box((0.36, 0.36, 0.04), (0, 0, 0.02), 'SignOrange'); b.tube((0, 0, 0.04), (0, 0, 0.6), 0.13, 'SignOrange', 8, 0.03)
    b.tube((0, 0, 0.3), (0, 0, 0.4), 0.085, 'White', 8, 0.065)


def p_mailbox(b):
    b.box((0.5, 0.5, 0.9), (0, 0, 0.65), 'Blue'); b.prof([(-0.25, 1.1), (0, 1.25), (0.25, 1.1)], 0.5, 'Blue')
    for sx in (-0.2, 0.2):
        for sy in (-0.2, 0.2):
            b.box((0.05, 0.05, 0.2), (sx, sy, 0.1), 'Dark')


def p_dumpster(b):
    b.box((2.2, 1.2, 1.2), (0, 0, 0.7), 'LeafDark', taper=(1.05, 1.1)); b.box((2.35, 1.35, 0.08), (0, 0, 1.34), 'Dark', rot=(4, 0, 0))
    for sx in (-0.9, 0.9):
        b.cyl(0.08, 0.06, (sx, 0.4, 0.08), 'Dark', 'x', 6); b.cyl(0.08, 0.06, (sx, -0.4, 0.08), 'Dark', 'x', 6)


def p_crate(b):
    b.box((1, 1, 1), (0, 0, 0.5), 'Wood')
    for s in (-1, 1):
        b.box((1.04, 0.1, 1.04), (0, s * 0.45, 0.5), 'WoodDark'); b.box((0.1, 1.04, 1.04), (s * 0.45, 0, 0.5), 'WoodDark')


def p_barrel(m):
    def f(b):
        b.tube((0, 0, 0), (0, 0, 0.9), 0.3, m, 10)
        for z in (0.03, 0.45, 0.87):
            b.cyl(0.315, 0.05, (0, 0, z), 'Dark' if m != 'Red' else 'Yellow', 'z', 10)
    return f


def p_container(b):
    b.box((2.44, 6.06, 2.6), (0, 0, 1.3), 'Paint')
    for i in range(14):
        b.box((2.5, 0.12, 2.4), (0, -2.8 + i * 0.43, 1.3), 'Paint')
    b.box((2.3, 0.08, 2.4), (0, 3.04, 1.3), 'Paint2')
    for x in (-0.4, 0.4):
        b.box((0.05, 0.1, 2.2), (x, 3.08, 1.3), 'Steel')


def p_pallet(b):
    for y in (-0.5, 0, 0.5):
        b.box((1.2, 0.1, 0.1), (0, y, 0.05), 'WoodDark')
    for i in range(5):
        b.box((0.16, 1.2, 0.03), (-0.5 + i * 0.25, 0, 0.115), 'Wood')


def p_vending(b):
    b.box((1.0, 0.8, 1.9), (0, 0, 0.95), 'Red'); b.box((0.6, 0.05, 1.1), (-0.12, 0.4, 1.2), 'WinLit'); b.box((0.2, 0.05, 0.5), (0.34, 0.4, 1.2), 'Dark')
    b.box((0.7, 0.06, 0.2), (0, 0.4, 0.35), 'Dark')


def p_ramp(b):
    b.prof([(-3.2, 0), (3.2, 0), (3.2, 2.0), (2.6, 2.0)], 4.2, 'Wood')
    for sx in (-1, 1):
        b.prof([(-3.2, 0), (3.2, 0), (3.2, 2.05), (2.6, 2.05)], 0.15, 'SignOrange', x=sx * 2.1)


def p_ladder(b):
    for sx in (-0.25, 0.25):
        b.box((0.05, 0.05, 8.0), (sx, 0, 4.0), 'Steel')
    for i in range(26):
        b.tube((-0.25, 0, 0.3 + i * 0.3), (0.25, 0, 0.3 + i * 0.3), 0.018, 'Steel', 5)


def p_pier(b):
    b.box((4, 8, 0.2), (0, 0, 0), 'Wood')
    for i in range(10):
        b.box((4.02, 0.06, 0.21), (0, -3.6 + i * 0.8, 0), 'WoodDark')
    for sx in (-1.8, 1.8):
        for sy in (-3.5, 3.5):
            b.tube((sx, sy, -6), (sx, sy, 0.6), 0.16, 'WoodDark', 6)


def p_helipad(b):
    b.cyl(9, 0.12, (0, 0, 0.06), 'ConcreteDark', 'z', 20)
    for i in range(20):
        a = math.radians(i * 18)
        b.box((1.6, 0.4, 0.02), (math.cos(a) * 8, math.sin(a) * 8, 0.125), 'Yellow', rot=(0, 0, i * 18 + 90))
    b.box((0.7, 5, 0.02), (-1.6, 0, 0.125), 'White'); b.box((0.7, 5, 0.02), (1.6, 0, 0.125), 'White'); b.box((3.2, 0.7, 0.02), (0, 0, 0.125), 'White')


def p_target(b):
    b.tube((0, 0, 0), (0, 0, 1.2), 0.03, 'Steel', 6); b.box((0.5, 0.3, 0.04), (0, 0, 0.02), 'Dark')
    b.cyl(0.4, 0.04, (0, 0, 1.5), 'White', 'y', 12); b.cyl(0.27, 0.05, (0, 0, 1.5), 'Red', 'y', 12); b.cyl(0.13, 0.06, (0, 0, 1.5), 'White', 'y', 10)
    b.cyl(0.05, 0.07, (0, 0, 1.5), 'Red', 'y', 8)


def p_cash(b):
    b.box((0.3, 0.16, 0.08), (0, 0, 0.3), 'Cash'); b.box((0.08, 0.17, 0.085), (0, 0, 0.3), 'White')


def p_health(b):
    b.box((0.4, 0.14, 0.32), (0, 0, 0.35), 'White'); b.box((0.2, 0.15, 0.06), (0, 0, 0.35), 'Health'); b.box((0.06, 0.15, 0.2), (0, 0, 0.35), 'Health')


def p_armor(b):
    b.box((0.38, 0.14, 0.4), (0, 0, 0.4), 'ArmorBlue', taper=(1.15, 1)); b.box((0.14, 0.15, 0.1), (0, 0, 0.62), 'Dark')


def p_ammo(b):
    b.box((0.4, 0.24, 0.24), (0, 0, 0.3), 'LeafDark'); b.box((0.42, 0.26, 0.04), (0, 0, 0.41), 'Dark'); b.box((0.2, 0.25, 0.06), (0, 0, 0.3), 'Yellow')


def p_chute(b):
    R = 3.4
    rings = []
    for k in range(-3, 4):
        x = k / 3 * R * 0.95
        hh = math.sqrt(max(0.0, 1 - (k / 3 * 0.95) ** 2))
        rings.append((x, [(-1.6 * hh - 0.3, 5.2 + hh * 1.0), (0, 5.6 + hh * 1.2), (1.6 * hh + 0.3, 5.2 + hh * 1.0), (0, 5.45 + hh * 1.2)]))
    for i in range(len(rings) - 1):
        b.loft([rings[i], rings[i + 1]], 'Canvas' if i % 2 == 0 else 'White')
    for k in (-3, -1, 1, 3):
        for sx in (-1, 1):
            b.tube((0, 0, 0.3), (sx * 1.4, k / 3 * R * 0.9, 5.3), 0.012, 'Dark', 4)


def p_spike(b):
    b.box((0.3, 4, 0.03), (0, 0, 0.015), 'Dark')
    for i in range(16):
        b.tube((0, -1.9 + i * 0.25, 0.03), (0, -1.9 + i * 0.25, 0.14), 0.02, 'Steel', 4, 0.0)


def p_wreck(b):
    def hull(w, keel, top):
        return [(-w / 2, top), (-w * 0.3, keel + 0.3), (0, keel), (w * 0.3, keel + 0.3), (w / 2, top)]
    b.loft([(-7, hull(4.2, 0, 3.0)), (0, hull(4.6, -0.2, 3.0)), (5, hull(3.4, 0.2, 3.3)), (8, hull(0.3, 1.8, 3.8))], 'MetalRust')
    b.box((3.2, 4, 2.2), (0, -3, 4.0), 'MetalRust', rot=(0, 6, 0)); b.box((2.6, 0.1, 0.8), (0, -0.95, 4.4), 'WinDark')
    b.tube((0, 2, 3), (0.8, 2.5, 8), 0.15, 'MetalRust', 6)
    b.box((1.4, 1.4, 1.0), (0.4, 4, 3.6), 'Wood')


def p_tires(b):
    for i in range(3):
        b.cyl(0.36, 0.24, (0, 0, 0.12 + i * 0.25), 'Tire', 'z', 10)


def p_table(b):
    b.box((1.8, 0.8, 0.06), (0, 0, 0.75), 'Wood')
    for sy in (-0.75, 0.75):
        b.box((1.8, 0.3, 0.05), (0, sy, 0.45), 'Wood')
    for sx in (-0.7, 0.7):
        b.box((0.08, 1.7, 0.08), (sx, 0, 0.4), 'Dark'); b.box((0.08, 0.08, 0.75), (sx, 0, 0.37), 'Dark')


def p_fountain(b):
    b.tube((0, 0, 0), (0, 0, 0.7), 3.2, 'Concrete', 12, 3.0); b.cyl(2.7, 0.1, (0, 0, 0.62), 'Water', 'z', 12)
    b.tube((0, 0, 0), (0, 0, 1.8), 0.4, 'Concrete', 8, 0.25); b.tube((0, 0, 1.8), (0, 0, 2.0), 0.3, 'Concrete', 8, 1.0)
    b.cyl(0.85, 0.06, (0, 0, 2.02), 'Water', 'z', 8)


def p_billboard(b):
    for sx in (-3, 3):
        b.box((0.4, 0.4, 9), (sx, 0, 4.5), 'Steel')
    b.box((10, 0.4, 4.4), (0, 0, 9), 'Dark'); b.box((9.6, 0.05, 4.0), (0, 0.22, 9), 'SignYellow')
    b.box((9.6, 0.06, 1.0), (0, 0.23, 7.5), 'SignRed')
    b.cyl(1.1, 0.07, (-2.8, 0.24, 9.6), 'SignRed', 'y', 12)


def p_umbrella(b):
    b.tube((0, 0, 0), (0, 0, 2.2), 0.03, 'Steel', 6); b.tube((0, 0, 1.9), (0, 0, 2.3), 1.4, 'AwningRed', 8, 0.05)
    b.box((0.6, 1.8, 0.08), (1.0, 0, 0.3), 'AwningBlue'); b.box((0.6, 0.6, 0.08), (1.0, -0.95, 0.5), 'AwningBlue', rot=(40, 0, 0))


def p_lifeguard(b):
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.tube((sx * 1.2, sy * 1.2, 0), (sx * 1.0, sy * 1.0, 2.4), 0.07, 'Wood', 6)
    b.box((2.6, 2.6, 0.12), (0, 0, 2.4), 'Wood'); b.box((2.0, 2.0, 1.8), (0, -0.2, 3.4), 'White'); b.box((2.4, 2.6, 0.12), (0, 0, 4.4), 'AwningRed', rot=(8, 0, 0))
    b.box((1.2, 0.05, 0.8), (0, 0.82, 3.6), 'WinDark')
    b.prof([(1.3, 2.4), (3.6, 0), (3.6, 0.12), (1.3, 2.52)], 0.9, 'Wood')


def p_crane(b):
    for sx in (-6, 6):
        for sy in (-4, 4):
            b.box((0.8, 0.8, 22), (sx, sy, 11), 'Yellow')
        b.box((0.6, 8, 0.6), (sx, 0, 21.5), 'Yellow'); b.box((0.6, 8, 0.6), (sx, 0, 8), 'Yellow')
    b.box((13, 1.0, 1.2), (0, 0, 22.6), 'Yellow'); b.box((1.4, 34, 1.6), (0, 6, 24), 'Yellow')
    b.box((3, 3, 2.4), (2.4, -2, 21.6), 'White'); b.box((2.0, 0.1, 1.2), (2.4, -0.48, 21.9), 'WinDark')
    b.tube((0, 16, 23.2), (0, 16, 12), 0.05, 'Dark', 4); b.box((2.5, 1.0, 0.4), (0, 16, 12), 'Dark')


def p_pump(b):
    b.box((0.9, 0.6, 1.7), (0, 0, 0.85), 'Red'); b.box((0.7, 0.62, 0.4), (0, 0, 1.3), 'White')


def p_buoy(b):
    b.tube((0, 0, -0.4), (0, 0, 0.3), 0.6, 'SignOrange', 8, 0.5); b.tube((0, 0, 0.3), (0, 0, 2.0), 0.3, 'SignOrange', 6, 0.08)
    b.box((0.2, 0.2, 0.2), (0, 0, 2.1), 'SirenRed')


for nm, fn in (('prop_traffic_light', p_tlight), ('prop_street_lamp', p_lamp), ('prop_sign_stop', p_stop), ('prop_sign_speed', p_speed),
               ('prop_barrier', p_barrier), ('prop_roadblock', p_roadblock), ('prop_bench', p_bench), ('prop_bin', p_bin),
               ('prop_hydrant', p_hydrant), ('prop_bus_stop', p_busstop), ('prop_fence', p_fence), ('prop_utility_box', p_utility),
               ('prop_bollard', p_bollard), ('prop_cone', p_cone), ('prop_mailbox', p_mailbox), ('prop_dumpster', p_dumpster),
               ('prop_crate', p_crate), ('prop_barrel_explosive', p_barrel('Red')), ('prop_barrel', p_barrel('Blue')),
               ('prop_container', p_container), ('prop_pallet', p_pallet), ('prop_vending', p_vending), ('prop_ramp', p_ramp),
               ('prop_ladder', p_ladder), ('prop_pier', p_pier), ('prop_helipad', p_helipad), ('prop_target', p_target),
               ('prop_pickup_cash', p_cash), ('prop_pickup_health', p_health), ('prop_pickup_armor', p_armor), ('prop_pickup_ammo', p_ammo),
               ('prop_parachute', p_chute), ('prop_spike_strip', p_spike), ('prop_wreck', p_wreck), ('prop_tire_stack', p_tires),
               ('prop_picnic_table', p_table), ('prop_fountain', p_fountain), ('prop_billboard', p_billboard), ('prop_umbrella', p_umbrella),
               ('prop_lifeguard', p_lifeguard), ('prop_crane', p_crane), ('prop_gas_pump', p_pump), ('prop_buoy', p_buoy)):
    prop(nm, fn, step=6 if nm not in ('prop_crane', 'prop_wreck', 'prop_helipad') else 30)


# ---------------- interiors ----------------
def i_bed(b):
    b.box((1.6, 2.1, 0.3), (0, 0, 0.25), 'WoodDark'); b.box((1.5, 1.9, 0.2), (0, 0, 0.5), 'Mattress'); b.box((1.6, 0.1, 0.9), (0, -1.05, 0.55), 'WoodDark')
    b.box((0.6, 0.4, 0.12), (0, -0.7, 0.66), 'White')


def i_wardrobe(b):
    b.box((1.6, 0.6, 2.1), (0, 0, 1.05), 'Wood'); b.box((0.02, 0.62, 2.0), (0, 0.01, 1.05), 'WoodDark')
    b.box((0.04, 0.05, 0.3), (-0.1, 0.32, 1.1), 'Chrome'); b.box((0.04, 0.05, 0.3), (0.1, 0.32, 1.1), 'Chrome')


def i_counter(b):
    b.box((3.0, 0.8, 1.0), (0, 0, 0.5), 'WoodDark'); b.box((3.1, 0.9, 0.06), (0, 0, 1.03), 'Wood'); b.box((0.4, 0.4, 0.3), (1.0, 0, 1.2), 'Dark')


def i_workbench(b):
    b.box((2.2, 0.8, 0.08), (0, 0, 0.92), 'Steel')
    for sx in (-1, 1):
        b.box((0.08, 0.7, 0.9), (sx, 0, 0.45), 'Dark')
    b.box((2.2, 0.06, 1.2), (0, -0.4, 1.6), 'Wood'); b.box((0.5, 0.04, 0.1), (-0.5, -0.36, 1.7), 'GunMetal'); b.box((0.7, 0.04, 0.08), (0.4, -0.36, 1.4), 'GunMetal')
    b.box((0.3, 0.25, 0.2), (0.7, 0, 1.06), 'Red')


for nm, fn in (('int_bed', i_bed), ('int_wardrobe', i_wardrobe), ('int_counter', i_counter), ('int_workbench', i_workbench)):
    prop(nm, fn, 'Interiors', 16, 4)


# ---------------- nature ----------------
def blob(b, cx, cy, cz, r, m, rnd, sq=1.0, n=6):
    rings = []
    for t in (-0.92, -0.5, 0.0, 0.5, 0.92):
        rr = r * math.sqrt(1 - t * t)
        rings.append((cy + t * r, [(cx + x * rnd.uniform(0.85, 1.15), cz + (z - 0) * sq * rnd.uniform(0.85, 1.15)) for x, z in ell(rr * 2, rr * 2, 0, n)]))
    b.loft(rings, m)


def n_tree_round(b):
    rnd = random.Random(1)
    b.tube((0, 0, 0), (0, 0, 3.2), 0.22, 'Trunk', 6, 0.14)
    blob(b, 0, 0, 4.6, 2.0, 'Leaf', rnd, 0.9, 7); blob(b, 0.9, 0.5, 5.5, 1.3, 'LeafLight', rnd); blob(b, -0.9, -0.4, 5.2, 1.4, 'LeafDark', rnd)


def n_tree_tall(b):
    rnd = random.Random(2)
    b.tube((0, 0, 0), (0, 0, 5.0), 0.26, 'Trunk', 6, 0.16)
    blob(b, 0, 0, 6.4, 2.2, 'LeafDark', rnd, 1.3, 7); blob(b, 0.5, -0.6, 8.2, 1.4, 'Leaf', rnd, 1.2)


def n_pine(b):
    b.tube((0, 0, 0), (0, 0, 2.0), 0.2, 'Trunk', 6, 0.15)
    for i, (z, r) in enumerate(((1.4, 1.9), (3.0, 1.5), (4.5, 1.1), (5.8, 0.7))):
        b.tube((0, 0, z), (0, 0, z + 2.2), r, 'LeafDark' if i % 2 == 0 else 'Leaf', 7, 0.0)


def n_palm(b):
    pts = [(0, 0, 0), (0.25, 0, 2.2), (0.7, 0, 4.4), (1.3, 0, 6.4)]
    for i in range(3):
        b.tube(pts[i], pts[i + 1], 0.22 - i * 0.04, 'Trunk', 6, 0.18 - i * 0.04)
    for i in range(7):
        a = i * 360 / 7
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        b.box((0.5, 2.6, 0.05), (1.3 + ca * 1.2, sa * 1.2, 6.2), 'Leaf' if i % 2 else 'LeafLight', rot=(-22, 0, a - 90), taper=(0.3, 1))
    b.cyl(0.14, 0.2, (1.25, 0.15, 6.2), 'WoodDark', 'z', 6)


def n_bush(b):
    rnd = random.Random(3)
    blob(b, 0, 0, 0.55, 0.8, 'Leaf', rnd, 0.8); blob(b, 0.6, 0.2, 0.45, 0.55, 'LeafDark', rnd, 0.8)


def n_rock(seed, r, m):
    def f(b):
        rnd = random.Random(seed)
        blob(b, 0, 0, r * 0.35, r, m, rnd, 0.7, 6)
    return f


def n_grass(b):
    for a in (0, 60, 120):
        b.box((0.5, 0.02, 0.45), (0, 0, 0.22), 'LeafLight', rot=(0, 0, a), taper=(0.5, 1))


for nm, fn in (('nat_tree_round', n_tree_round), ('nat_tree_tall', n_tree_tall), ('nat_pine', n_pine), ('nat_palm', n_palm), ('nat_bush', n_bush),
               ('nat_rock_a', n_rock(5, 1.2, 'Rock')), ('nat_rock_b', n_rock(8, 2.4, 'RockDark')), ('nat_grass', n_grass)):
    prop(nm, fn, 'Nature', 17, 7, 'nature')


# ---------------- VFX helper meshes ----------------
def v_muzzle(b):
    for a in (0, 60, 120):
        b.box((0.01, 0.3, 0.16), (0, 0.15, 0), 'Flash', rot=(0, a, 0), taper=(1, 0.2))
    b.box((0.1, 0.02, 0.1), (0, 0.02, 0), 'Flash', rot=(0, 45, 0))


def v_shard(b):
    b.add([(0, 0, 0), (0.12, 0.02, 0), (0.03, 0.1, 0.02), (0.04, 0.03, 0.08)], [(0, 1, 2), (0, 3, 1), (1, 3, 2), (0, 2, 3)], 'Grey')


prop('vfx_muzzle', v_muzzle, 'VFX_HelperMeshes', 18, 2, 'vfx')
prop('vfx_shard', v_shard, 'VFX_HelperMeshes', 18, 2, 'vfx')
coll('CollisionHelpers')
print('world done')
