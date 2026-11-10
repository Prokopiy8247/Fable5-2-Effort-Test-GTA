# Buildings / landmark kit (run inside Blender via MCP after gta_lib.py). Fronts face Blender -Y (Godot +Z).
import math, random

for _n, _c in {'Wall_Cream': '#e6d9b8', 'Wall_Brick': '#a5553f', 'Wall_Grey': '#8f9498', 'Wall_Blue': '#5b7fa6',
               'Wall_Teal': '#3f8c8a', 'Wall_Sand': '#d2b48c', 'Wall_White': '#ecece6', 'Wall_Charcoal': '#3b3f46',
               'Wall_Pink': '#d98c8c', 'Wall_Mint': '#9ccfb4', 'Wall_Yellow': '#e6c65a', 'Wall_Rust': '#9a5a3a',
               'Wall_Navy': '#27406b', 'Wall_Red': '#b23a30', 'Roof': '#4a4d52', 'RoofRed': '#a1493a', 'Trim': '#f2efe6',
               'MetalCorr': '#8fa0a8', 'WoodDeck': '#9a7a52', 'AwnRed': '#c9463c', 'AwnGreen': '#3f8f5c',
               'AwnBlue': '#3c6fc9', 'AwnYellow': '#e3b23c', 'Door': '#5a3d2b', 'Floor': '#b8a88c', 'Rug': '#a03c48',
               'Bed': '#4a6fa8', 'Pillow': '#f1eee4', 'Screen': '#101820'}.items():
    mat(_n, _c, rough=0.85)
mat('GlassTower', '#3f6f96', rough=0.1, metal=0.7)
BC = coll('Buildings')
_slot = [0]


def nextplace():
    i = _slot[0]
    _slot[0] += 1
    return ((i % 8) * 45 - 150, -60 - (i // 8) * 50, 0)


def faces4(w, d):
    # (centre fn along face, normal axis) -> list of (pos(u), size(u)) generators
    return [('x', -d / 2, -1, w), ('x', d / 2, 1, w), ('y', -w / 2, -1, d), ('y', w / 2, 1, d)]


def wbox(b, m, axis, off, sgn, u, z, su, sz, th=0.08):
    if axis == 'x':
        b.box(m, (u, off + sgn * th / 2, z), (su, th, sz))
    else:
        b.box(m, (off + sgn * th / 2, u, z), (th, su, sz))


def windows(b, w, d, h, style, fh, start, wm='Window', spacing=2.6, ww=1.4, wh=1.5, skip_front_gf=True):
    nf = int((h - 0.9) / fh)
    for f in range(start, nf):
        z = f * fh + fh * 0.55 + 0.2
        for axis, off, sgn, W in faces4(w, d):
            if style == 'band':
                wbox(b, wm, axis, off, sgn, 0, z, W - 1.2, wh)
            elif style == 'curtain':
                wbox(b, wm, axis, off, sgn, 0, z, W - 0.5, fh - 0.5)
            else:
                n = max(1, int((W - 1.2) / spacing))
                for i in range(n):
                    u = (i - (n - 1) / 2) * spacing
                    wbox(b, wm, axis, off, sgn, u, z, ww, wh)
                    if style == 'sill':
                        wbox(b, 'Trim', axis, off, sgn, u, z - wh / 2 - 0.08, ww + 0.2, 0.1, th=0.16)


def roof_stuff(b, w, d, h, seed=1, parapet=True, ac=3, roofm='Roof'):
    rnd = random.Random(seed)
    b.box(roofm, (0, 0, h + 0.03), (w - 0.3, d - 0.3, 0.06))
    if parapet:
        for sx in (-1, 1):
            b.box('Trim', (sx * (w / 2 - 0.12), 0, h + 0.3), (0.24, d, 0.6))
            b.box('Trim', (0, sx * (d / 2 - 0.12), h + 0.3), (w, 0.24, 0.6))
    for i in range(ac):
        x = rnd.uniform(-w / 2 + 2, w / 2 - 2)
        y = rnd.uniform(-d / 2 + 2, d / 2 - 2)
        s = rnd.uniform(1.0, 2.0)
        b.box('Steel', (x, y, h + 0.5), (s, s * 0.8, 0.9))
        b.box('Dark', (x, y, h + 0.97), (s * 0.6, s * 0.5, 0.05))


def shopfront(b, w, d, fh, awn=None, door_x=0.0, gh=2.5):
    y = -d / 2
    gw = (w - 3.0) / 2
    for sx in (-1, 1):
        b.box('Window', (sx * (1.0 + gw / 2 + 0.2), y - 0.03, 0.5 + gh / 2), (gw, 0.08, gh))
    b.box('Door', (door_x, y - 0.03, 1.15), (1.4, 0.08, 2.3))
    b.box('Window', (door_x, y - 0.05, 1.5), (1.0, 0.08, 1.2))
    b.box('Chrome', (door_x + 0.5, y - 0.1, 1.1), (0.05, 0.05, 0.4))
    if awn:
        b.box(awn, (0, y - 0.7, fh - 0.15), (w - 0.6, 1.4, 0.08), rot=(-0.28, 0, 0))


def signboard(name, r, C, s, w, y, z, col='Neon', size=0.9, board='Dark'):
    b = B()
    bw = min(w - 0.6, len(s) * size * 0.72 + 0.8)
    b.box(board, (0, y - 0.1, z), (bw, 0.16, size * 1.5))
    b.obj(name + '_SignBoard', C, r)
    text(name + '_Sign', s, size, C, r, (0, y - 0.19, z), col, extrude=0.03)


def bld(name, w, d, h, wall, style='grid', fh=3.3, gf='plain', sign=None, sign_col='Neon', awn=None, ac=3, seed=1,
        wm='Window', spacing=2.6, extra=None, kind='building', roofm='Roof', sign_size=0.9):
    r = root(name, BC, nextplace())
    b = B()
    b.box(wall, (0, 0, h / 2), (w, d, h))
    b.box('ConcreteDark', (0, 0, 0.2), (w + 0.12, d + 0.12, 0.4))
    windows(b, w, d, h, style, fh, 1 if gf != 'plain' else 0, wm=wm, spacing=spacing)
    if gf == 'shop':
        shopfront(b, w, d, fh, awn)
    elif gf == 'door':
        b.box('Door', (0, -d / 2 - 0.03, 1.2), (1.8, 0.08, 2.4))
        b.box('Trim', (0, -d / 2 - 0.3, 2.7), (3.0, 0.7, 0.14))
        for sx in (-1, 1):
            n = max(0, int((w / 2 - 2.5) / 2.6))
            for i in range(n):
                b.box(wm, (sx * (2.8 + i * 2.6), -d / 2 - 0.03, 1.7), (1.4, 0.08, 1.5))
    elif gf == 'lobby':
        b.box(wm, (0, -d / 2 - 0.03, 1.9), (w - 2.0, 0.08, 3.0))
        b.box('Dark', (0, -d / 2 - 0.05, 1.3), (2.4, 0.08, 2.4))
        b.box('Trim', (0, -d / 2 - 1.0, 3.6), (6.0, 2.0, 0.2))
        for sx in (-1, 1):
            b.cyl('Trim', (sx * 2.7, -d / 2 - 1.8, 1.8), 0.15, 3.6, seg=8)
    roof_stuff(b, w, d, h, seed, ac=ac, roofm=roofm)
    cols = [((0, 0, h / 2), (w, d, h))]
    if extra:
        cols += extra(b, r) or []
    b.obj(name + '_Body', BC, r)
    if sign:
        signboard(name, r, BC, sign, w, -d / 2, min(h - 0.8, fh + 0.75) if gf == 'shop' else h - 1.2, sign_col, sign_size)
    register(name, cols=cols, kind=kind, door=g((0, -d / 2 - 1.2, 0)))
    return r


def house(name, w, d, wall, roofm='RoofRed', seed=1, garage=False):
    r = root(name, BC, nextplace())
    b = B()
    h = 3.4
    b.box(wall, (0, 0, h / 2), (w, d, h))
    b.box('ConcreteDark', (0, 0, 0.15), (w + 0.1, d + 0.1, 0.3))
    b.poly(roofm, [(-d / 2 - 0.5, h), (d / 2 + 0.5, h), (0, h + 2.4)], w + 0.8, axis='X')
    b.box('Door', (-w / 4, -d / 2 - 0.03, 1.2), (1.1, 0.08, 2.2))
    b.box('Concrete', (-w / 4, -d / 2 - 0.7, 0.12), (2.2, 1.4, 0.24))
    b.box('Trim', (-w / 4, -d / 2 - 0.7, 2.6), (2.6, 1.5, 0.1))
    for sx in (-1, 1):
        b.box('Trim', (-w / 4 + sx * 1.1, -d / 2 - 1.3, 1.35), (0.12, 0.12, 2.5))
    if garage:
        b.box('Trim', (w / 4, -d / 2 - 0.03, 1.2), (3.0, 0.08, 2.3))
        for k in range(4):
            b.box('ConcreteDark', (w / 4, -d / 2 - 0.08, 0.3 + k * 0.55), (2.9, 0.04, 0.04))
    else:
        b.box('Window', (w / 4, -d / 2 - 0.03, 1.8), (2.0, 0.08, 1.3))
        b.box('Trim', (w / 4, -d / 2 - 0.08, 1.1), (2.3, 0.16, 0.1))
    for sx in (-1, 1):
        b.box('Window', (sx * (w / 2 + 0.03), 0, 1.8), (0.08, 1.6, 1.2))
        b.box('Window', (sx * w / 4, d / 2 + 0.03, 1.8), (1.6, 0.08, 1.2))
    b.box('Wall_Brick', (w / 3, d / 5, h + 2.0), (0.8, 0.8, 2.2))
    b.obj(name + '_Body', BC, r)
    register(name, cols=[((0, 0, (h + 1.2) / 2), (w, d, h + 1.2))], kind='building', door=g((-w / 4, -d / 2 - 1.8, 0)))


def shell(b, wall, w, d, h, t=0.3, door_w=1.4, door_h=2.3, door_x=0.0, floor=None, inner='Wall_White'):
    """Hollow room with a door opening in the front (-Y) wall. Returns collision boxes."""
    cols = []

    def W(c, s):
        b.box(wall, c, s)
        cols.append((c, s))
    W((0, d / 2 - t / 2, h / 2), (w, t, h))
    W((-w / 2 + t / 2, 0, h / 2), (t, d, h))
    W((w / 2 - t / 2, 0, h / 2), (t, d, h))
    lw = (w / 2 + door_x) - door_w / 2
    rw = (w / 2 - door_x) - door_w / 2
    W((-w / 2 + lw / 2, -d / 2 + t / 2, h / 2), (lw, t, h))
    W((w / 2 - rw / 2, -d / 2 + t / 2, h / 2), (rw, t, h))
    W((door_x, -d / 2 + t / 2, (h + door_h) / 2), (door_w, t, h - door_h))
    W((0, 0, h + 0.1), (w, d, 0.2))
    if floor:
        b.box(floor, (0, 0, 0.02), (w - 2 * t, d - 2 * t, 0.04))
    return cols


def build_safehouse():
    name = 'safehouse'
    r = root(name, BC, nextplace())
    b = B()
    w, d, h = 11.0, 9.0, 3.2
    cols = shell(b, 'Wall_Mint', w, d, h, door_x=-2.5, floor='Floor')
    b.poly('RoofRed', [(-d / 2 - 0.5, h + 0.2), (d / 2 + 0.5, h + 0.2), (0, h + 2.6)], w + 0.8, axis='X')
    b.box('Window', (2.2, -d / 2 - 0.02, 1.7), (2.4, 0.06, 1.3))
    b.box('Trim', (-2.5, -d / 2 - 0.6, 2.7), (2.6, 1.3, 0.1))
    for sx in (-1, 1):
        b.box('Window', (sx * (w / 2 + 0.02), 0, 1.7), (0.06, 2.0, 1.2))
    # furniture
    f = []

    def F(m, c, s, col=True):
        b.box(m, c, s)
        if col:
            f.append((c, s))
    F('Wood', (3.6, 2.6, 0.25), (2.0, 2.6, 0.5)); F('Bed', (3.6, 2.4, 0.56), (1.9, 2.1, 0.14), False); F('Pillow', (3.6, 3.5, 0.62), (1.4, 0.5, 0.14), False)
    F('Wood', (-4.6, 2.5, 1.1), (0.8, 2.4, 2.2)); F('Trim', (-4.18, 2.5, 1.1), (0.04, 0.05, 2.0), False)
    F('Seat', (0.4, 3.4, 0.4), (2.6, 1.0, 0.8)); F('Wall_Navy', (0.4, 3.25, 0.5), (2.4, 0.7, 0.25), False)
    F('Wood', (0.4, 1.3, 0.25), (1.4, 0.8, 0.5))
    F('Wood', (0.4, -3.8, 0.4), (2.0, 0.5, 0.8)); F('Screen', (0.4, -3.85, 1.35), (1.6, 0.08, 0.9), False)
    F('Rug', (0.4, 0.3, 0.05), (3.4, 2.4, 0.02), False)
    F('Wood', (-4.4, -2.6, 0.45), (1.0, 1.8, 0.9)); F('Steel', (-4.4, -2.6, 0.92), (0.9, 1.7, 0.04), False)
    F('Lamp', (3.0, 0.0, 3.05), (0.5, 0.5, 0.08), False)
    b.obj(name + '_Body', BC, r)
    register(name, cols=cols + f, kind='building', door=g((-2.5, -d / 2 - 1.5, 0)), wardrobe=g((-3.7, 2.5, 0)), bed=g((2.3, 2.5, 0)),
             inside=g((0.4, -1.0, 0)))


def build_garage_shop():
    name = 'shop_mods'
    r = root(name, BC, nextplace())
    b = B()
    w, d, h = 16.0, 14.0, 5.5
    cols = shell(b, 'Wall_Charcoal', w, d, h, door_w=6.0, door_h=4.0, door_x=0, floor='ConcreteDark')
    b.box('Orange', (0, -d / 2 - 0.02, 4.3), (w, 0.08, 0.5))
    for sx in (-1, 1):
        b.box('Yellow', (sx * 3.15, -d / 2 - 0.03, 2.0), (0.3, 0.08, 4.0))
        b.box('Steel', (sx * 7.2, 3.0, 0.5), (1.0, 4.0, 1.0)); cols.append(((sx * 7.2, 3.0, 0.5), (1.0, 4.0, 1.0)))
        b.box('Red', (sx * 7.2, 3.0, 1.15), (0.9, 1.0, 0.3))
        for k in range(3):
            b.cyl('Tire', (sx * 7.0, -2.0 - k * 0.9, 0.35), 0.35, 0.25, axis='X', seg=10)
    b.box('Lamp', (0, 0, h - 0.05), (6.0, 0.4, 0.06))
    b.box('Lamp', (0, 3.5, h - 0.05), (6.0, 0.4, 0.06))
    b.box('Yellow', (0, 0, 0.05), (4.0, 6.5, 0.02))
    b.box('ConcreteDark', (0, 0, 0.06), (3.6, 6.1, 0.02))
    roof_stuff(b, w, d, h + 0.2, 4, ac=2)
    b.obj(name + '_Body', BC, r)
    signboard(name, r, BC, 'TORQUE BAY', w, -d / 2, 4.95, 'LightAmber', 0.8)
    register(name, cols=cols, kind='building', door=g((0, -d / 2 - 4, 0)), bay=g((0, 0, 0)))


def build_hangar():
    name = 'hangar'
    r = root(name, BC, nextplace())
    b = B()
    w, d, h = 32.0, 28.0, 11.0
    cols = shell(b, 'MetalCorr', w, d, h, t=0.5, door_w=24.0, door_h=8.5, floor=None)
    b.poly('Roof', [(-w / 2, h + 0.2), (w / 2, h + 0.2), (w / 4, h + 2.2), (-w / 4, h + 2.2)], d, axis='Y')
    for sx in (-1, 1):
        b.box('Yellow', (sx * 12.2, -d / 2 - 0.03, 4.25), (0.4, 0.1, 8.5))
        for k in range(4):
            b.box('Window', (sx * (w / 2 + 0.03), -9 + k * 6, 7.5), (0.08, 3.0, 1.2))
    b.box('Lamp', (0, 0, h - 0.1), (12, 0.5, 0.08))
    b.obj(name + '_Body', BC, r)
    signboard(name, r, BC, 'HANGAR 1', w, -d / 2, 9.8, 'White', 1.2, board='Wall_Navy')
    register(name, cols=cols, kind='building', door=g((0, -d / 2 - 6, 0)))


def build_gas():
    name = 'gas_station'
    r = root(name, BC, nextplace())
    b = B()
    cols = []
    b.box('Wall_White', (0, 6, 2.0), (12, 6, 4.0)); cols.append(((0, 6, 2.0), (12, 6, 4.0)))
    b.box('Wall_Red', (0, 6, 4.2), (12.4, 6.4, 0.5))
    b.box('Window', (-2, 2.97, 1.7), (6, 0.08, 2.2)); b.box('Door', (3.5, 2.97, 1.15), (1.4, 0.08, 2.3))
    b.box('Wall_White', (0, -3.5, 5.3), (15, 9, 0.6)); b.box('Wall_Red', (0, -3.5, 5.0), (15.2, 9.2, 0.2))
    b.box('Lamp', (0, -3.5, 4.88), (10, 5, 0.05))
    for sx in (-1, 1):
        for sy in (-6.5, -0.5):
            b.box('Trim', (sx * 5.5, sy, 2.5), (0.5, 0.5, 5.0)); cols.append(((sx * 5.5, sy, 2.5), (0.5, 0.5, 5.0)))
        b.box('Concrete', (sx * 2.6, -3.5, 0.1), (1.2, 4.6, 0.2))
        for py in (-4.8, -2.2):
            b.box('Wall_Red', (sx * 2.6, py, 1.0), (0.8, 0.6, 1.6)); cols.append(((sx * 2.6, py, 1.0), (0.8, 0.6, 1.6)))
            b.box('Screen', (sx * 2.6 + 0.0, py - 0.31, 1.35), (0.5, 0.02, 0.4))
            b.box('Dark', (sx * 2.6 + 0.42, py, 0.9), (0.06, 0.1, 0.5))
    b.obj(name + '_Body', BC, r)
    signboard(name, r, BC, 'SUNBELT FUEL', 15, -8.1, 5.3, 'White', 0.6, board='Wall_Red')
    register(name, cols=cols, kind='building', door=g((3.5, 1.5, 0)), pumps=g((0, -3.5, 0)))


def build_parking():
    name = 'parking_garage'
    r = root(name, BC, nextplace())
    b = B()
    cols = []
    zt = 3.8

    def S(m, c, s, col=True):
        b.box(m, c, s)
        if col:
            cols.append((c, s))
    S('Concrete', (2.5, 0, zt - 0.2), (25, 24, 0.4))
    S('Concrete', (-12.5, 10, zt - 0.2), (5, 4, 0.4))
    for x in (-9.5, 0, 9, 14.5):
        for y in (-11.5, 0, 11.5):
            S('ConcreteDark', (x, y, (zt - 0.4) / 2), (0.6, 0.6, zt - 0.4))
    # ramp along the -X side
    ang = math.atan2(zt, 18.0)
    b.box('Concrete', (-12.5, -1.0, zt / 2 - 0.15), (5.0, 18.0 / math.cos(ang), 0.3), rot=(ang, 0, 0))
    for c, s in (((2.5, -11.9, zt + 0.5), (25, 0.2, 1.0)), ((15.1, 0, zt + 0.5), (0.2, 24, 1.0)), ((2.5, 11.9, zt + 0.5), (25, 0.2, 1.0)),
                 ((-12.5, 11.9, zt + 0.5), (5, 0.2, 1.0)), ((-15.1, 10, zt + 0.5), (0.2, 4, 1.0)), ((-9.9, -2.0, zt + 0.5), (0.2, 20, 1.0))):
        S('Trim', c, s)
    for k in range(7):
        b.box('Trim', (-6 + k * 3.2, -6.5, zt + 0.01), (0.12, 5, 0.02))
        b.box('Trim', (-6 + k * 3.2, 6.5, zt + 0.01), (0.12, 5, 0.02))
    b.box('Wall_Blue', (15.4, 0, 2.6), (0.3, 6, 1.6))
    b.obj(name + '_Body', BC, r)
    text(name + '_Sign', 'PARKING', 1.0, BC, r, (15.58, 0, 2.6), 'White', rot=(math.pi / 2, 0, math.pi / 2), extrude=0.03)
    register(name, cols=cols, kind='building', door=g((-12.5, -14, 0)),
             ramps=[g((-12.5, -10.0, 0)) + g((-12.5, 8.0, zt)) + [5.0]])


def build_station():
    name = 'metro_station'
    r = root(name, BC, nextplace())
    b = B()
    cols = []
    zt = 6.6

    def S(m, c, s, col=True):
        b.box(m, c, s)
        if col:
            cols.append((c, s))
    S('Concrete', (0, -6.0, zt - 0.2), (20, 9, 0.4))
    S('Concrete', (7.5, -11.75, zt - 0.2), (5, 2.5, 0.4))
    for x in (-9, 0, 9):
        S('ConcreteDark', (x, -10.0, (zt - 0.4) / 2), (0.7, 0.7, zt - 0.4))
    ang = math.atan2(zt, 14.0)
    b.box('Concrete', (-2.0, -11.8, zt / 2 - 0.15), (14.0 / math.cos(ang), 2.4, 0.3), rot=(0, -ang, 0))
    S('Trim', (-2.5, -10.45, zt + 0.5), (15, 0.12, 1.0))
    S('Trim', (-10.0, -6.0, zt + 0.5), (0.12, 9, 1.0))
    S('Trim', (10.0, -7.3, zt + 0.5), (0.12, 11.5, 1.0))
    S('Trim', (7.5, -13.0, zt + 0.5), (5, 0.12, 1.0))
    b.box('Yellow', (0, -1.8, zt + 0.01), (20, 0.3, 0.02))
    for x in (-8, 8):
        S('Steel', (x, -9.5, zt + 1.6), (0.25, 0.25, 3.2))
    b.box('Wall_Teal', (0, -6.5, zt + 3.3), (19, 7.5, 0.2))
    for x in (-4, 4):
        b.box('Wood', (x, -8.6, zt + 0.45), (2.4, 0.5, 0.1)); b.box('Steel', (x, -8.6, zt + 0.2), (2.0, 0.1, 0.4))
    b.obj(name + '_Body', BC, r)
    signboard(name, r, BC, 'SKYLINE METRO', 19, -10.3, zt + 2.6, 'NeonCyan', 0.7)
    register(name, cols=cols, kind='building', door=g((-9.5, -11.8, 0)), platform=g((0, -4.0, zt)),
             ramps=[g((-9.0, -11.8, 0)) + g((5.0, -11.8, zt)) + [2.4]])
    # track kit
    for nm, parts in (('track_beam', [('Concrete', (0, 0, 5.6), (20, 1.0, 0.8)), ('Steel', (0, 0, 6.02), (20, 0.5, 0.06))]),
                      ('track_pillar', [('ConcreteDark', (0, 0, 2.6), (1.1, 1.1, 5.2)), ('ConcreteDark', (0, 0, 5.1), (1.8, 1.6, 0.4))])):
        rr = root(nm, BC, nextplace())
        bb = B()
        for m, c, s in parts:
            bb.box(m, c, s)
        bb.obj(nm + '_Body', BC, rr)
        register(nm, cols=[(parts[0][1], parts[0][2])], kind='building')


def build_misc_structures():
    # pier module (deck top at z=0, 6 x 12)
    r = root('pier', BC, nextplace())
    b = B()
    b.box('WoodDeck', (0, 0, -0.15), (6, 12, 0.3))
    for k in range(12):
        b.box('Wood', (0, -5.5 + k, 0.005), (6, 0.06, 0.01))
    for sx in (-1, 1):
        for y in (-5, 0, 5):
            b.cyl('Bark', (sx * 2.7, y, -3.0), 0.22, 6.6, seg=8)
            b.cyl('Bark', (sx * 2.85, y, 0.5), 0.1, 1.0, seg=6)
        b.box('Wood', (sx * 2.85, 0, 0.9), (0.1, 12, 0.08))
    b.obj('pier_Body', BC, r)
    register('pier', cols=[((0, 0, -0.15), (6, 12, 0.3)), ((-2.85, 0, 0.5), (0.15, 12, 1.0)), ((2.85, 0, 0.5), (0.15, 12, 1.0))], kind='building')
    # lighthouse
    r = root('lighthouse', BC, nextplace())
    b = B()
    b.cyl('Wall_White', (0, 0, 7), 2.6, 14, seg=12, r2=1.7)
    b.cyl('Wall_Red', (0, 0, 4), 2.42, 2.0, seg=12, r2=2.18)
    b.cyl('Wall_Red', (0, 0, 10), 2.0, 2.0, seg=12, r2=1.78)
    b.cyl('Dark', (0, 0, 14.15), 2.3, 0.3, seg=12)
    b.cyl('Lamp', (0, 0, 15.3), 1.2, 2.0, seg=10)
    b.cyl('Wall_Red', (0, 0, 16.7), 1.6, 0.9, seg=10, r2=0.1)
    b.box('Door', (0, -2.55, 1.1), (1.0, 0.2, 2.2))
    b.obj('lighthouse_Body', BC, r)
    register('lighthouse', cols=[((0, 0, 8), (4.4, 4.4, 16))], kind='building')
    # control tower
    r = root('control_tower', BC, nextplace())
    b = B()
    b.box('Wall_White', (0, 0, 8), (5, 5, 16))
    b.box('Window', (0, 0, 17.6), (8, 8, 2.4), top=(1.15, 1.15))
    b.box('Roof', (0, 0, 19.0), (9.6, 9.6, 0.4))
    b.cyl('Steel', (0, 0, 21), 0.08, 3.6, seg=6); b.box('LightRed', (0, 0, 22.9), (0.2, 0.2, 0.2))
    b.box('Door', (0, -2.53, 1.1), (1.2, 0.1, 2.2))
    b.box('Wall_Red', (0, 0, 15.9), (5.2, 5.2, 0.5))
    b.obj('control_tower_Body', BC, r)
    register('control_tower', cols=[((0, 0, 10), (5, 5, 20))], kind='building')
    # dock crane
    r = root('crane', BC, nextplace())
    b = B()
    cols = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box('Yellow', (sx * 6, sy * 4, 9), (0.8, 0.8, 18)); cols.append(((sx * 6, sy * 4, 9), (0.8, 0.8, 18)))
        b.box('Yellow', (sx * 6, 0, 17.6), (0.8, 8.8, 0.8))
        b.box('Yellow', (sx * 6, 0, 6), (0.5, 8, 0.5))
    b.box('Yellow', (0, 0, 18.5), (13, 2.0, 1.2))
    b.box('Yellow', (0, -9, 19.4), (2.0, 34, 1.0))
    b.box('Wall_White', (0, -3, 17.2), (2.4, 3.0, 2.0)); b.box('Window', (0, -4.52, 17.3), (2.0, 0.06, 1.0))
    tube(b, 'Steel', (0, -18, 19), (0, -18, 9), 0.05); b.box('Steel', (0, -18, 8.8), (2.4, 6.0, 0.3))
    b.obj('crane_Body', BC, r)
    register('crane', cols=cols, kind='building')
    # shipping container
    r = root('container', BC, nextplace())
    b = B()
    b.box('Paint', (0, 0, 1.3), (2.44, 6.06, 2.6))
    for k in range(14):
        for sx in (-1, 1):
            b.box('Paint', (sx * 1.24, -2.8 + k * 0.43, 1.3), (0.05, 0.2, 2.3))
    b.box('Dark', (0, -3.04, 1.3), (0.06, 0.03, 2.3)); b.box('Steel', (0.3, -3.05, 1.3), (0.04, 0.03, 2.2)); b.box('Steel', (-0.3, -3.05, 1.3), (0.04, 0.03, 2.2))
    b.obj('container_Body', BC, r)
    register('container', cols=[((0, 0, 1.3), (2.44, 6.06, 2.6))], kind='building')
    # silo / tanks
    r = root('silo', BC, nextplace())
    b = B()
    b.cyl('Wall_White', (0, 0, 5), 3.5, 10, seg=14); b.cyl('Steel', (0, 0, 10.4), 3.5, 0.8, seg=14, r2=0.6)
    tube(b, 'Steel', (3.6, 0, 0), (3.6, 0, 10.2), 0.05); tube(b, 'Steel', (3.6, 0.5, 0), (3.6, 0.5, 10.2), 0.05)
    b.box('Wall_Red', (0, 0, 7), (7.06, 7.06, 0.5), top=(1, 1))
    b.obj('silo_Body', BC, r)
    register('silo', cols=[((0, 0, 5), (6.2, 6.2, 10))], kind='building')
    # billboard
    r = root('billboard', BC, nextplace())
    b = B()
    b.box('Steel', (-3, 0, 4), (0.4, 0.4, 8)); b.box('Steel', (3, 0, 4), (0.4, 0.4, 8))
    b.box('Wall_Navy', (0, 0, 9.5), (12, 0.4, 4.4)); b.box('Wall_Yellow', (0, -0.21, 9.5), (11.4, 0.04, 3.8))
    b.obj('billboard_Body', BC, r)
    text('billboard_Sign', 'VISIT PORT CINDER', 1.0, BC, r, (0, -0.26, 10.0), 'Wall_Navy', extrude=0.03)
    text('billboard_Sign2', 'sun  sea  speed', 0.7, BC, r, (0, -0.26, 8.6), 'Wall_Red', extrude=0.03)
    register('billboard', cols=[((-3, 0, 4), (0.4, 0.4, 8)), ((3, 0, 4), (0.4, 0.4, 8))], kind='building')
    # water tower
    r = root('water_tower', BC, nextplace())
    b = B()
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube(b, 'Steel', (sx * 2.2, sy * 2.2, 0), (sx * 1.6, sy * 1.6, 9), 0.12)
    b.cyl('Wall_Rust', (0, 0, 11), 2.8, 4.2, seg=12); b.cyl('Roof', (0, 0, 13.7), 2.9, 1.2, seg=12, r2=0.2)
    b.obj('water_tower_Body', BC, r)
    register('water_tower', cols=[((0, 0, 7), (4.6, 4.6, 14))], kind='building')
    # gazebo viewpoint
    r = root('gazebo', BC, nextplace())
    b = B()
    cols = []
    b.cyl('WoodDeck', (0, 0, 0.15), 3.2, 0.3, seg=8)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        p = (math.cos(a) * 2.9, math.sin(a) * 2.9, 1.6)
        b.box('Trim', p, (0.16, 0.16, 2.9)); cols.append((p, (0.16, 0.16, 2.9)))
    b.cyl('RoofRed', (0, 0, 3.7), 3.6, 1.4, seg=8, r2=0.2)
    b.obj('gazebo_Body', BC, r)
    register('gazebo', cols=cols + [((0, 0, 0.15), (5.6, 5.6, 0.3))], kind='building')
    # lifeguard tower
    r = root('lifeguard_tower', BC, nextplace())
    b = B()
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box('Wood', (sx * 1.1, sy * 1.1, 1.0), (0.14, 0.14, 2.0))
    b.box('WoodDeck', (0, 0, 2.05), (3.0, 3.0, 0.14))
    b.box('Wall_White', (0, 0.3, 3.0), (2.2, 2.0, 1.8)); b.box('Wall_Red', (0, 0.3, 4.0), (2.6, 2.4, 0.2)); b.box('Window', (0, -0.72, 3.1), (1.4, 0.05, 0.8))
    ang = math.atan2(2.0, 3.0)
    b.box('WoodDeck', (0, -3.0, 1.0), (1.0, 3.0 / math.cos(ang), 0.1), rot=(ang, 0, 0))
    b.obj('lifeguard_tower_Body', BC, r)
    register('lifeguard_tower', cols=[((0, 0, 2.05), (3.0, 3.0, 0.14)), ((0, 0.3, 3.0), (2.2, 2.0, 1.8))], kind='building',
             ramps=[g((0, -4.5, 0)) + g((0, -1.5, 2.1)) + [1.0]])


def build_all_buildings():
    _slot[0] = 0
    bld('tower_a', 28, 28, 72, 'Wall_Charcoal', 'curtain', fh=4.0, gf='lobby', wm='GlassTower', ac=5, seed=2)
    bld('tower_b', 24, 30, 54, 'Wall_Blue', 'band', gf='lobby', ac=4, seed=3)
    bld('tower_c', 30, 22, 42, 'Wall_Cream', 'sill', gf='lobby', ac=4, seed=4)
    bld('office_d', 26, 18, 27, 'Wall_Grey', 'band', gf='lobby', seed=5)
    bld('hotel', 28, 20, 36, 'Wall_Sand', 'grid', gf='lobby', sign='HOTEL MIRADOR', sign_col='Neon', seed=6, sign_size=1.3)
    bld('bank', 26, 18, 13, 'Wall_White', 'grid', fh=4.2, gf='lobby', sign='CINDER TRUST', sign_col='Badge', seed=7)
    bld('shop_guns', 15, 12, 6.2, 'Wall_Charcoal', gf='shop', sign='BRASS TACK ARMS', sign_col='LightAmber', awn='AwnRed', ac=1, seed=8, sign_size=0.7)
    bld('shop_clothes', 14, 12, 7.5, 'Wall_Pink', gf='shop', sign='THREAD COUNT', sign_col='White', awn='AwnBlue', ac=1, seed=9, sign_size=0.7)
    bld('shop_barber', 10, 10, 6.0, 'Wall_Teal', gf='shop', sign='CLIP JOINT', sign_col='White', awn='AwnYellow', ac=1, seed=10, sign_size=0.7)
    bld('shop_food', 12, 10, 5.5, 'Wall_Yellow', gf='shop', sign='PITA STOP', sign_col='Wall_Red', awn='AwnGreen', ac=1, seed=11, sign_size=0.7)
    bld('shop_market', 16, 12, 5.5, 'Wall_White', gf='shop', sign='24/7 MARKET', sign_col='SigGreen', awn='AwnGreen', ac=2, seed=12, sign_size=0.7)
    bld('shop_tattoo', 9, 10, 9.5, 'Wall_Brick', 'sill', gf='shop', sign='INK HARBOR', sign_col='NeonCyan', awn='AwnRed', ac=1, seed=13, sign_size=0.6)
    bld('apartment_a', 24, 16, 20, 'Wall_Brick', 'sill', gf='door', seed=14)
    bld('apartment_b', 18, 16, 26.6, 'Wall_Sand', 'sill', gf='door', seed=15)
    bld('apartment_c', 22, 14, 13.4, 'Wall_Mint', 'sill', gf='door', seed=16)
    house('house_a', 11, 9, 'Wall_Cream', 'RoofRed', 1, garage=True)
    house('house_b', 10, 8, 'Wall_Blue', 'Roof', 2)
    house('house_c', 12, 9, 'Wall_Yellow', 'RoofRed', 3, garage=True)
    house('house_d', 10, 9, 'Wall_Pink', 'Roof', 4)

    def wh_doors(n, w, d):
        def f(b, r):
            for i in range(n):
                x = (i - (n - 1) / 2) * (w / n)
                b.box('Steel', (x, -d / 2 - 0.03, 2.4), (4.4, 0.08, 4.8))
                for k in range(8):
                    b.box('ConcreteDark', (x, -d / 2 - 0.08, 0.4 + k * 0.6), (4.3, 0.03, 0.05))
                b.box('Yellow', (x, -d / 2 - 0.05, 4.95), (4.8, 0.08, 0.2))
        return f
    bld('warehouse_a', 32, 20, 9.5, 'MetalCorr', 'none', gf='plain', ac=2, seed=20, extra=wh_doors(3, 32, 20), sign='HARBOR FREIGHT CO', sign_col='White', sign_size=0.9)
    bld('warehouse_b', 24, 34, 11, 'Wall_Rust', 'none', gf='plain', ac=2, seed=21, extra=wh_doors(2, 24, 34))

    def chimneys(b, r):
        out = []
        for x in (-10, -5):
            b.cyl('Wall_Brick', (x, 4, 15), 1.3, 12, seg=10, r2=0.9); b.cyl('Wall_White', (x, 4, 19.5), 1.0, 1.0, seg=10, r2=0.95)
            out.append(((x, 4, 12), (2.4, 2.4, 22)))
        b.box('Steel', (8, 0, 13.5), (10, 8, 3.0)); b.box('Window', (8, -4.03, 13.6), (9, 0.06, 1.2))
        return out
    bld('factory', 36, 24, 12, 'Wall_Grey', 'band', fh=5.0, gf='plain', ac=3, seed=22, extra=chimneys, sign='ASHWORKS', sign_col='LightAmber')

    def station_x(b, r):
        b.box('Wall_Navy', (0, -9.03, 4.4), (26.2, 0.1, 0.8))
        for sx in (-1, 1):
            b.box('LightBlue', (sx * 3.2, -9.3, 3.3), (0.3, 0.3, 0.4))
        b.box('Trim', (0, -10.2, 3.2), (6, 2.4, 0.2))
    bld('police_station', 26, 18, 9.5, 'Wall_White', 'grid', gf='door', seed=23, extra=station_x, sign='POLICE', sign_col='White', sign_size=1.1)

    def hosp_x(b, r):
        b.box('Red', (0, -11.05, 13.0), (3.0, 0.1, 0.9)); b.box('Red', (0, -11.05, 13.0), (0.9, 0.1, 3.0))
        b.box('Trim', (0, -13.0, 3.6), (10, 4, 0.3))
        for sx in (-1, 1):
            b.box('Trim', (sx * 4.6, -14.6, 1.8), (0.3, 0.3, 3.6))
        b.cyl('ConcreteDark', (0, 0, 16.75), 6.0, 0.1, seg=16); b.box('White', (0, 0, 16.82), (0.5, 3.0, 0.02))
        b.box('White', (-1.2, 0, 16.82), (0.5, 3.0, 0.02)) ; b.box('White', (1.2, 0, 16.82), (0.5, 3.0, 0.02)); b.box('White', (0, 0, 16.83), (2.4, 0.5, 0.02))
    bld('hospital', 30, 22, 16, 'Wall_White', 'band', gf='lobby', ac=0, seed=24, extra=hosp_x, sign='ST. EMBER MEDICAL', sign_col='Red', sign_size=0.9)

    def fire_x(b, r):
        for sx in (-1, 1):
            b.box('Wall_Red', (sx * 4.5, -8.03, 2.4), (5.0, 0.08, 4.6))
            for k in range(3):
                b.box('Window', (sx * 4.5, -8.08, 1.5 + k * 1.2), (4.2, 0.03, 0.5))
    bld('fire_station', 20, 16, 8.5, 'Wall_Brick', 'grid', gf='plain', seed=25, extra=fire_x, sign='FIRE DEPT', sign_col='White')
    bld('terminal', 30, 12, 7, 'Wall_White', 'band', fh=3.4, gf='lobby', seed=26, sign='CINDER AIRFIELD', sign_col='NeonCyan', wm='GlassTower')
    build_safehouse()
    build_garage_shop()
    build_hangar()
    build_gas()
    build_parking()
    build_station()
    build_misc_structures()
    names = ['tower_a', 'tower_b', 'tower_c', 'office_d', 'hotel', 'bank', 'shop_guns', 'shop_clothes', 'shop_barber', 'shop_food',
             'shop_market', 'shop_tattoo', 'apartment_a', 'apartment_b', 'apartment_c', 'house_a', 'house_b', 'house_c', 'house_d',
             'warehouse_a', 'warehouse_b', 'factory', 'police_station', 'hospital', 'fire_station', 'terminal', 'safehouse', 'shop_mods',
             'hangar', 'gas_station', 'parking_garage', 'metro_station', 'track_beam', 'track_pillar', 'pier', 'lighthouse',
             'control_tower', 'crane', 'container', 'silo', 'billboard', 'water_tower', 'gazebo', 'lifeguard_tower']
    export_all(names, 'buildings')
    return names
