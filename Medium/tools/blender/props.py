# Street props, pickups, nature (run inside Blender via MCP after gta_lib.py + vehicles.py for tube()).
import math, random

PC = coll('StreetProps')
NC = coll('Nature')
IC = coll('Interiors')
VC = coll('VFX_HelperMeshes')
_ps = [0]


def pplace():
    i = _ps[0]
    _ps[0] += 1
    return ((i % 12) * 4 - 20, 40 + (i // 12) * 6, 0)


def prop(name, fn, cols=None, C=None, **extra):
    C = C or PC
    r = root(name, C, pplace())
    b = B()
    res = fn(b, r, C)
    b.obj(name + '_Body', C, r)
    register(name, cols=cols if cols is not None else (res or []), kind='prop', **extra)
    return r


def build_props():
    names = []

    def P(name, fn, cols=None, C=None, **extra):
        prop(name, fn, cols, C, **extra)
        names.append(name)

    def traffic_light(b, r, C):
        b.cyl('Dark', (0, 0, 2.9), 0.1, 5.8, seg=8)
        b.cyl('ConcreteDark', (0, 0, 0.15), 0.22, 0.3, seg=8)
        tube(b, 'Dark', (0, 0, 5.6), (-4.2, 0, 5.75), 0.07)
        for x in (-3.9, 0.0):
            z = 5.25 if x < 0 else 3.4
            b.box('Dark', (x, -0.02 if x < 0 else -0.22, z), (0.38, 0.3, 1.1))
            for k, (nm, m) in enumerate((('R', 'SigRed'), ('Y', 'SigYellow'), ('G', 'SigGreen'))):
                b.box('Black', (x, (-0.02 if x < 0 else -0.22) - 0.155, z + 0.33 - k * 0.33), (0.22, 0.02, 0.22))
        for k, (nm, m) in enumerate((('R', 'SigRed'), ('Y', 'SigYellow'), ('G', 'SigGreen'))):
            lb = B()
            lb.box(m, (-3.9, -0.185, 5.25 + 0.33 - k * 0.33), (0.24, 0.03, 0.24))
            lb.box(m, (0.0, -0.385, 3.4 + 0.33 - k * 0.33), (0.24, 0.03, 0.24))
            lb.obj('traffic_light_Lit' + nm, C, r)
    P('traffic_light', traffic_light, [((0, 0, 2.9), (0.3, 0.3, 5.8))], knock=1)

    def street_lamp(b, r, C):
        b.cyl('Steel', (0, 0, 3.6), 0.09, 7.2, seg=8, r2=0.06)
        b.cyl('ConcreteDark', (0, 0, 0.2), 0.2, 0.4, seg=8)
        tube(b, 'Steel', (0, 0, 7.1), (0, -1.8, 7.4), 0.05)
        b.box('Steel', (0, -2.0, 7.4), (0.36, 0.8, 0.12))
        b.box('Lamp', (0, -2.0, 7.33), (0.28, 0.66, 0.04))
    P('street_lamp', street_lamp, [((0, 0, 3.6), (0.26, 0.26, 7.2))], knock=1, light=g((0, -2.0, 7.2)))

    def sign(kind):
        def f(b, r, C):
            b.cyl('Steel', (0, 0, 1.4), 0.04, 2.8, seg=6)
            if kind == 'stop':
                b.cyl('Red', (0, -0.05, 2.5), 0.4, 0.04, axis='Y', seg=8)
                text('sign_stop_T', 'STOP', 0.22, C, r, (0, -0.075, 2.5), 'White', extrude=0.004)
            elif kind == 'speed':
                b.box('White', (0, -0.05, 2.4), (0.6, 0.04, 0.8))
                b.box('Black', (0, -0.072, 2.4), (0.52, 0.002, 0.72)); b.box('White', (0, -0.074, 2.4), (0.47, 0.002, 0.67))
                text('sign_speed_T', '40', 0.36, C, r, (0, -0.078, 2.35), 'Black', extrude=0.004)
            else:
                b.box('Blue', (0, -0.05, 2.4), (0.6, 0.04, 0.6))
                text('sign_park_T', 'P', 0.45, C, r, (0, -0.075, 2.4), 'White', extrude=0.004)
        return f
    for k in ('stop', 'speed', 'park'):
        P('sign_' + k, sign(k), [((0, 0, 1.4), (0.14, 0.14, 2.8))], knock=1)

    def barrier(b, r, C):
        b.box('Concrete', (0, 0, 0.45), (3.0, 0.6, 0.9), top=(1, 0.35))
        b.box('Yellow', (0, 0, 0.905), (3.0, 0.2, 0.02))
    P('barrier', barrier, [((0, 0, 0.45), (3.0, 0.45, 0.9))])

    def barrier_police(b, r, C):
        for i in range(6):
            b.box('White' if i % 2 else 'Red', (-1.25 + i * 0.5, 0, 0.9), (0.5, 0.06, 0.24))
            b.box('Red' if i % 2 else 'White', (-1.25 + i * 0.5, 0, 0.5), (0.5, 0.06, 0.16))
        for sx in (-1, 1):
            b.box('Steel', (sx * 1.3, -0.25, 0.5), (0.06, 0.06, 1.05), rot=(0.25, 0, 0))
            b.box('Steel', (sx * 1.3, 0.25, 0.5), (0.06, 0.06, 1.05), rot=(-0.25, 0, 0))
            b.box('LightAmber', (sx * 1.3, 0, 1.1), (0.12, 0.12, 0.12))
    P('barrier_police', barrier_police, [((0, 0, 0.55), (3.0, 0.5, 1.1))], dynamic=40)

    def spike(b, r, C):
        b.box('Dark', (0, 0, 0.02), (4.5, 0.4, 0.04))
        for i in range(22):
            b.box('Steel', (-2.1 + i * 0.2, 0, 0.07), (0.03, 0.03, 0.1), top=(0.1, 0.1))
    P('spike_strip', spike, [])

    def bench(b, r, C):
        for k in range(3):
            b.box('Wood', (0, -0.15 + k * 0.17, 0.45), (1.8, 0.13, 0.05))
        b.box('Wood', (0, 0.28, 0.75), (1.8, 0.05, 0.14)); b.box('Wood', (0, 0.26, 0.58), (1.8, 0.05, 0.12))
        for sx in (-1, 1):
            b.box('Dark', (sx * 0.8, 0, 0.22), (0.06, 0.5, 0.44)); b.box('Dark', (sx * 0.8, 0.27, 0.6), (0.06, 0.06, 0.5))
    P('bench', bench, [((0, 0.05, 0.4), (1.8, 0.55, 0.8))])

    def bin_(b, r, C):
        b.cyl('Green', (0, 0, 0.45), 0.26, 0.9, seg=10, r2=0.3); b.cyl('Dark', (0, 0, 0.92), 0.31, 0.06, seg=10)
    P('bin', bin_, [((0, 0, 0.47), (0.55, 0.55, 0.95))], dynamic=12)

    def hydrant(b, r, C):
        b.cyl('Red', (0, 0, 0.3), 0.12, 0.6, seg=8); b.cyl('Red', (0, 0, 0.66), 0.14, 0.12, seg=8, r2=0.05)
        b.cyl('Red', (0, 0, 0.42), 0.06, 0.4, axis='X', seg=6); b.cyl('Steel', (0, -0.14, 0.42), 0.06, 0.08, axis='Y', seg=6)
        b.cyl('Red', (0, 0, 0.04), 0.17, 0.08, seg=8)
    P('hydrant', hydrant, [((0, 0, 0.36), (0.32, 0.32, 0.72))], knock=1, hydrant=1)

    def bus_stop(b, r, C):
        for sx in (-1, 1):
            b.box('Steel', (sx * 1.9, 0.6, 1.25), (0.08, 0.08, 2.5)); b.box('Steel', (sx * 1.9, -0.6, 1.25), (0.08, 0.08, 2.5))
            b.box('Glass', (sx * 1.9, 0, 1.3), (0.04, 1.1, 2.0))
        b.box('Glass', (0, 0.62, 1.3), (3.8, 0.04, 2.0))
        b.box('Wall_Teal', (0, 0, 2.55), (4.2, 1.7, 0.1))
        b.box('Wood', (0, 0.3, 0.5), (2.6, 0.4, 0.06)); b.box('Steel', (0, 0.3, 0.25), (2.4, 0.06, 0.5))
        b.box('Blue', (2.5, -0.6, 2.6), (0.5, 0.05, 0.5)); b.cyl('Steel', (2.5, -0.6, 1.3), 0.03, 2.6, seg=6)
    P('bus_stop', bus_stop, [((0, 0.62, 1.3), (3.8, 0.1, 2.6)), ((-1.9, 0, 1.3), (0.1, 1.2, 2.6)), ((1.9, 0, 1.3), (0.1, 1.2, 2.6))])

    def fence_wood(b, r, C):
        for i in range(10):
            b.box('Trim', (-1.35 + i * 0.3, 0, 0.55), (0.2, 0.03, 1.1), top=(0.5, 1))
        b.box('Trim', (0, 0.03, 0.3), (3.0, 0.04, 0.08)); b.box('Trim', (0, 0.03, 0.8), (3.0, 0.04, 0.08))
    P('fence_wood', fence_wood, [((0, 0, 0.55), (3.0, 0.12, 1.1))])

    def fence_chain(b, r, C):
        for sx in (-1, 1):
            b.cyl('Steel', (sx * 1.5, 0, 1.1), 0.035, 2.2, seg=6)
        b.box('Steel', (0, 0, 2.15), (3.0, 0.04, 0.04)); b.box('Steel', (0, 0, 0.08), (3.0, 0.04, 0.04))
        for i in range(11):
            b.box('Steel', (-1.5 + i * 0.3, 0, 1.1), (0.015, 0.015, 2.1))
        for k in range(7):
            b.box('Steel', (0, 0, 0.3 + k * 0.3), (3.0, 0.015, 0.015))
    P('fence_chain', fence_chain, [((0, 0, 1.1), (3.0, 0.12, 2.2))])

    def utility_box(b, r, C):
        b.box('Wall_Grey', (0, 0, 0.7), (1.0, 0.5, 1.4)); b.box('Dark', (0, -0.255, 0.75), (0.02, 0.01, 1.2)); b.box('Yellow', (0.25, -0.255, 1.1), (0.2, 0.01, 0.2))
    P('utility_box', utility_box, [((0, 0, 0.7), (1.0, 0.5, 1.4))])

    def bollard(b, r, C):
        b.cyl('Steel', (0, 0, 0.45), 0.08, 0.9, seg=8); b.cyl('Yellow', (0, 0, 0.8), 0.085, 0.1, seg=8)
    P('bollard', bollard, [((0, 0, 0.45), (0.2, 0.2, 0.9))])

    def cone(b, r, C):
        b.box('Orange', (0, 0, 0.02), (0.4, 0.4, 0.04)); b.cyl('Orange', (0, 0, 0.36), 0.15, 0.66, seg=8, r2=0.03)
        b.cyl('White', (0, 0, 0.4), 0.105, 0.12, seg=8, r2=0.08)
    P('cone', cone, [((0, 0, 0.35), (0.36, 0.36, 0.7))], dynamic=3)

    def mailbox(b, r, C):
        b.box('Blue', (0, 0, 0.65), (0.5, 0.5, 1.0), top=(1, 1)); b.box('Blue', (0, 0, 1.2), (0.5, 0.5, 0.14), top=(0.6, 1)); b.box('Dark', (0, -0.255, 0.95), (0.3, 0.01, 0.05))
        for sx in (-1, 1):
            b.box('Dark', (sx * 0.2, 0, 0.08), (0.06, 0.4, 0.16))
    P('mailbox', mailbox, [((0, 0, 0.65), (0.5, 0.5, 1.3))], knock=1)

    def vending(b, r, C):
        b.box('Wall_Red', (0, 0, 0.95), (1.0, 0.75, 1.9)); b.box('Screen', (-0.12, -0.38, 1.15), (0.62, 0.02, 1.2)); b.box('Lamp', (0.34, -0.38, 1.3), (0.16, 0.02, 0.5))
        b.box('Dark', (-0.1, -0.38, 0.3), (0.5, 0.02, 0.16))
    P('vending', vending, [((0, 0, 0.95), (1.0, 0.75, 1.9))])

    def dumpster(b, r, C):
        b.box('Green', (0, 0, 0.7), (2.0, 1.1, 1.2), top=(1, 1.1)); b.box('Dark', (0, 0.05, 1.34), (2.06, 1.24, 0.08), rot=(0.06, 0, 0))
        for sx in (-1, 1):
            b.box('Steel', (sx * 1.03, 0, 0.9), (0.06, 0.3, 0.06))
    P('dumpster', dumpster, [((0, 0, 0.7), (2.0, 1.15, 1.4))], dynamic=120)

    def meter(b, r, C):
        b.cyl('Steel', (0, 0, 0.55), 0.03, 1.1, seg=6); b.box('Dark', (0, 0, 1.2), (0.16, 0.12, 0.26), top=(0.7, 1)); b.box('Screen', (0, -0.062, 1.22), (0.1, 0.004, 0.1))
    P('parking_meter', meter, [((0, 0, 0.65), (0.14, 0.14, 1.3))], knock=1)

    def crate(b, r, C):
        b.box('Wood', (0, 0, 0.45), (0.9, 0.9, 0.9))
        for sx in (-1, 1):
            b.box('Bark', (sx * 0.42, 0, 0.45), (0.08, 0.94, 0.94)); b.box('Bark', (0, sx * 0.42, 0.45), (0.94, 0.08, 0.94))
    P('crate', crate, [((0, 0, 0.45), (0.94, 0.94, 0.94))], dynamic=25)

    def barrel(b, r, C):
        b.cyl('Red', (0, 0, 0.45), 0.3, 0.9, seg=10)
        for z in (0.2, 0.7):
            b.cyl('Dark', (0, 0, z), 0.31, 0.04, seg=10)
        b.box('Yellow', (0, -0.3, 0.45), (0.2, 0.02, 0.2))
    P('barrel', barrel, [((0, 0, 0.45), (0.56, 0.56, 0.9))], dynamic=30, explosive=1)

    def tires(b, r, C):
        for k in range(4):
            b.cyl('Tire', (0, 0, 0.12 + k * 0.24), 0.36, 0.22, seg=10)
            b.cyl('Dark', (0, 0, 0.12 + k * 0.24), 0.2, 0.23, seg=8)
    P('tire_stack', tires, [((0, 0, 0.48), (0.7, 0.7, 0.96))], dynamic=30)

    def picnic(b, r, C):
        b.box('Wood', (0, 0, 0.75), (1.8, 0.8, 0.06))
        for sy in (-1, 1):
            b.box('Wood', (0, sy * 0.7, 0.45), (1.8, 0.28, 0.05))
        for sx in (-1, 1):
            b.box('Wood', (sx * 0.7, 0, 0.36), (0.08, 1.5, 0.08)); b.box('Wood', (sx * 0.7, 0, 0.55), (0.08, 0.1, 0.4))
    P('picnic_table', picnic, [((0, 0, 0.4), (1.8, 1.6, 0.8))])

    def ladder(b, r, C):
        for sx in (-1, 1):
            b.box('Steel', (sx * 0.25, 0, 3.2), (0.05, 0.05, 6.4))
        for k in range(20):
            b.cyl('Steel', (0, 0, 0.3 + k * 0.31), 0.02, 0.5, axis='X', seg=6)
    P('ladder', ladder, [], ladder=6.4)

    def ramp(b, r, C):
        b.poly('Wood', [(-3.0, 0), (3.0, 0), (3.0, 1.7)], 4.0, axis='X')
        b.box('Yellow', (0, 2.9, 1.72), (4.0, 0.2, 0.02), rot=(0.276, 0, 0))
        for sx in (-1, 1):
            b.box('Wall_Red', (sx * 2.02, 0, 0.5), (0.04, 5.0, 0.2), rot=(0.276, 0, 0))
    P('stunt_ramp', ramp, [], ramps=[g((0, -3.0, 0)) + g((0, 3.0, 1.7)) + [4.0]])

    def target(b, r, C):
        b.box('Wood', (0, 0.05, 0.6), (0.08, 0.06, 1.2)); b.box('Wood', (0, 0.05, 0.03), (0.6, 0.5, 0.06))
        b.cyl('White', (0, 0, 1.4), 0.4, 0.04, axis='Y', seg=14); b.cyl('Red', (0, -0.012, 1.4), 0.27, 0.04, axis='Y', seg=14)
        b.cyl('White', (0, -0.024, 1.4), 0.15, 0.04, axis='Y', seg=12); b.cyl('Red', (0, -0.036, 1.4), 0.06, 0.04, axis='Y', seg=10)
    P('target', target, [])

    def atm(b, r, C):
        b.box('Wall_Navy', (0, 0, 0.9), (0.8, 0.6, 1.8)); b.box('Screen', (0, -0.31, 1.25), (0.5, 0.02, 0.4)); b.box('Steel', (0, -0.33, 0.95), (0.5, 0.06, 0.1))
        b.box('SigGreen', (0, -0.31, 1.62), (0.6, 0.02, 0.14))
    P('atm', atm, [((0, 0, 0.9), (0.8, 0.6, 1.8))])

    def planter(b, r, C):
        b.box('Concrete', (0, 0, 0.3), (1.6, 1.6, 0.6), top=(1.1, 1.1))
        b.sphere('Leaf', (0, 0, 0.95), 0.7, seg=7, rings=4, scale=(1, 1, 0.75)); b.sphere('LeafDark', (0.3, 0.2, 1.1), 0.4, seg=6, rings=4)
    P('planter', planter, [((0, 0, 0.35), (1.7, 1.7, 0.7))])

    def umbrella(b, r, C):
        b.cyl('Trim', (0, 0, 1.1), 0.025, 2.2, seg=6)
        for i in range(8):
            a0 = i * math.pi / 4
            a1 = a0 + math.pi / 4
            b._add([(0, 0, 2.3), (math.cos(a0) * 1.4, math.sin(a0) * 1.4, 1.9), (math.cos(a1) * 1.4, math.sin(a1) * 1.4, 1.9),
                    (0, 0, 2.26), (math.cos(a0) * 1.4, math.sin(a0) * 1.4, 1.86), (math.cos(a1) * 1.4, math.sin(a1) * 1.4, 1.86)],
                   [(0, 1, 2), (5, 4, 3), (1, 4, 5, 2)], 'AwnRed' if i % 2 else 'Trim')
    P('umbrella', umbrella, [])

    def sunbed(b, r, C):
        b.box('Trim', (0, -0.2, 0.3), (0.65, 1.4, 0.06)); b.box('Trim', (0, 0.75, 0.5), (0.65, 0.7, 0.06), rot=(0.6, 0, 0)); b.box('AwnBlue', (0, -0.2, 0.34), (0.55, 1.3, 0.03))
        for sx in (-1, 1):
            for y in (-0.8, 0.4):
                b.box('Wood', (sx * 0.28, y, 0.14), (0.05, 0.05, 0.28))
    P('sunbed', sunbed, [((0, 0, 0.2), (0.65, 2.0, 0.4))])

    def buoy(b, r, C):
        b.cyl('Wall_Red', (0, 0, 0.1), 0.6, 0.7, seg=10, r2=0.45); b.cyl('Wall_Red', (0, 0, 1.0), 0.14, 1.2, seg=6); b.box('Lamp', (0, 0, 1.7), (0.2, 0.2, 0.2))
    P('buoy', buoy, [((0, 0, 0.3), (1.0, 1.0, 1.0))])

    def newsbox(b, r, C):
        b.box('Yellow', (0, 0, 0.55), (0.45, 0.4, 0.9)); b.box('Glass', (0, -0.205, 0.7), (0.35, 0.01, 0.4)); b.box('Dark', (0, 0, 0.05), (0.3, 0.3, 0.1))
    P('newsbox', newsbox, [((0, 0, 0.5), (0.45, 0.4, 1.0))], dynamic=15)

    def counter(b, r, C):
        b.box('Wood', (0, 0, 0.5), (2.4, 0.7, 1.0)); b.box('Steel', (0, 0, 1.02), (2.5, 0.8, 0.05)); b.box('Screen', (0.8, 0.1, 1.25), (0.4, 0.3, 0.4))
    P('counter', counter, [((0, 0, 0.5), (2.4, 0.7, 1.0))], C=IC)

    def clothes_rack(b, r, C):
        for sx in (-1, 1):
            b.box('Steel', (sx * 0.9, 0, 0.8), (0.04, 0.5, 1.6))
        b.cyl('Steel', (0, 0, 1.55), 0.02, 1.8, axis='X', seg=6)
        for i, m in enumerate(('AwnRed', 'AwnBlue', 'AwnYellow', 'AwnGreen', 'Wall_Navy', 'Trim')):
            b.box(m, (-0.65 + i * 0.26, 0, 1.15), (0.06, 0.42, 0.7))
    P('clothes_rack', clothes_rack, [((0, 0, 0.8), (1.9, 0.5, 1.6))], C=IC)

    def gun_rack(b, r, C):
        b.box('Wood', (0, 0, 1.1), (2.2, 0.12, 1.8))
        for k in range(3):
            b.box('Gunmetal', (0, -0.09, 0.6 + k * 0.5), (1.5, 0.05, 0.08)); b.box('Wood', (-0.6, -0.09, 0.56 + k * 0.5), (0.4, 0.05, 0.12))
            b.box('Steel', (0.9, -0.09, 0.55 + k * 0.5), (0.04, 0.1, 0.1)); b.box('Steel', (-0.9, -0.09, 0.55 + k * 0.5), (0.04, 0.1, 0.1))
    P('gun_rack', gun_rack, [((0, 0, 1.1), (2.2, 0.2, 1.8))], C=IC)

    def barber_chair(b, r, C):
        b.cyl('Steel', (0, 0, 0.25), 0.08, 0.5, seg=8); b.cyl('Steel', (0, 0, 0.03), 0.3, 0.06, seg=10)
        b.box('Wall_Red', (0, 0, 0.55), (0.6, 0.6, 0.14)); b.box('Wall_Red', (0, 0.3, 0.95), (0.6, 0.12, 0.8))
        for sx in (-1, 1):
            b.box('Steel', (sx * 0.33, 0, 0.75), (0.06, 0.5, 0.06))
    P('barber_chair', barber_chair, [((0, 0, 0.6), (0.7, 0.7, 1.2))], C=IC)

    # pickups (float + spin in Godot)
    def pk_cash(b, r, C):
        for k in range(3):
            b.box('SigGreen', (0, 0, 0.04 + k * 0.07), (0.3, 0.16, 0.06)); b.box('Trim', (0, 0, 0.04 + k * 0.07), (0.08, 0.165, 0.062))
    P('pickup_cash', pk_cash, [], C=VC)

    def pk_health(b, r, C):
        b.box('White', (0, 0, 0.14), (0.4, 0.16, 0.28)); b.box('Red', (0, -0.082, 0.14), (0.2, 0.01, 0.06)); b.box('Red', (0, -0.082, 0.14), (0.06, 0.01, 0.2))
        b.box('Dark', (0, 0, 0.3), (0.14, 0.04, 0.04))
    P('pickup_health', pk_health, [], C=VC)

    def pk_armor(b, r, C):
        b.box('Gunmetal', (0, 0, 0.2), (0.4, 0.2, 0.4), top=(1.1, 1)); b.box('Dark', (0, -0.105, 0.14), (0.28, 0.01, 0.1))
        for sx in (-1, 1):
            b.box('Gunmetal', (sx * 0.13, 0, 0.44), (0.1, 0.18, 0.1))
    P('pickup_armor', pk_armor, [], C=VC)

    def pk_ammo(b, r, C):
        b.box('Olive', (0, 0, 0.11), (0.34, 0.18, 0.22)); b.box('Dark', (0, 0, 0.235), (0.36, 0.2, 0.03)); b.box('Yellow', (0, -0.092, 0.11), (0.2, 0.01, 0.06))
    P('pickup_ammo', pk_ammo, [], C=VC)

    def pk_chute(b, r, C):
        b.box('Fabric', (0, 0, 0.22), (0.34, 0.2, 0.44)); b.box('Dark', (0.1, -0.105, 0.22), (0.04, 0.01, 0.4)); b.box('Dark', (-0.1, -0.105, 0.22), (0.04, 0.01, 0.4))
    P('pickup_parachute', pk_chute, [], C=VC)

    def pk_scuba(b, r, C):
        b.cyl('Yellow', (0, 0, 0.25), 0.09, 0.5, seg=8); b.cyl('Steel', (0, 0, 0.53), 0.035, 0.07, seg=6)
    P('pickup_scuba', pk_scuba, [], C=VC)

    def canopy(b, r, C):
        n = 7
        for i in range(n):
            a0 = math.pi * (0.2 + 0.6 * i / n)
            a1 = math.pi * (0.2 + 0.6 * (i + 1) / n)
            p0 = (-math.cos(a0) * 3.6, math.sin(a0) * 2.0 + 3.6)
            p1 = (-math.cos(a1) * 3.6, math.sin(a1) * 2.0 + 3.6)
            b.loft('Fabric' if i % 2 else 'Trim', [[(p0[0], -1.2, p0[1]), (p1[0], -1.2, p1[1]), (p1[0], -1.2, p1[1] + 0.12), (p0[0], -1.2, p0[1] + 0.12)],
                                                      [(p0[0], 1.2, p0[1]), (p1[0], 1.2, p1[1]), (p1[0], 1.2, p1[1] + 0.12), (p0[0], 1.2, p0[1] + 0.12)]])
        for sx in (-1, 1):
            for sy in (-1, 1):
                tube(b, 'Dark', (sx * 0.2, 0, 0.4), (sx * 2.9, sy * 1.1, 4.75), 0.008, seg=3)
    P('parachute', canopy, [], C=VC)

    # ---------------- nature ----------------
    rnd = random.Random(7)

    def tree_a(b, r, C):
        b.cyl('Bark', (0, 0, 1.6), 0.22, 3.2, seg=7, r2=0.14)
        for c, rad, m in (((0, 0, 4.4), 2.0, 'Leaf'), ((0.9, 0.5, 3.7), 1.3, 'LeafDark'), ((-0.8, -0.6, 3.9), 1.4, 'Leaf'), ((0.1, -0.2, 5.5), 1.2, 'LeafDark')):
            b.sphere(m, c, rad, seg=7, rings=4, scale=(1, 1, 0.85))
    P('tree_a', tree_a, [((0, 0, 1.6), (0.4, 0.4, 3.2))], C=NC)

    def tree_b(b, r, C):
        b.cyl('Bark', (0, 0, 2.2), 0.2, 4.4, seg=7, r2=0.1)
        b.sphere('LeafDark', (0, 0, 5.8), 1.7, seg=7, rings=5, scale=(1, 1, 1.7)); b.sphere('Leaf', (0.3, 0.2, 6.6), 1.2, seg=6, rings=4, scale=(1, 1, 1.4))
    P('tree_b', tree_b, [((0, 0, 2.2), (0.4, 0.4, 4.4))], C=NC)

    def pine(b, r, C):
        b.cyl('Bark', (0, 0, 1.2), 0.18, 2.4, seg=6)
        for k in range(4):
            b.cyl('LeafDark' if k % 2 else 'Leaf', (0, 0, 2.4 + k * 1.3), 1.9 - k * 0.38, 1.9, seg=7, r2=0.15)
    P('pine', pine, [((0, 0, 1.2), (0.36, 0.36, 2.4))], C=NC)

    def palm(b, r, C):
        pts = [(0, 0, 0), (0.15, 0, 1.6), (0.4, 0, 3.2), (0.75, 0, 4.8), (1.2, 0, 6.2)]
        for i in range(4):
            tube(b, 'Bark', pts[i], pts[i + 1], 0.2 - i * 0.025, seg=6)
        top = pts[-1]
        for i in range(7):
            a = i * 2 * math.pi / 7
            dx, dy = math.cos(a), math.sin(a)
            b.box('Leaf', (top[0] + dx * 1.2, top[1] + dy * 1.2, top[2] - 0.1), (2.4, 0.5, 0.05), rot=(0, 0.35, a))
            b.box('LeafDark', (top[0] + dx * 2.5, top[1] + dy * 2.5, top[2] - 0.9), (1.2, 0.36, 0.05), rot=(0, 0.95, a))
        b.sphere('Bark', (top[0], top[1], top[2] - 0.1), 0.26, seg=6, rings=3)
    P('palm', palm, [((0.2, 0, 2.0), (0.4, 0.4, 4.0))], C=NC)

    def bush(b, r, C):
        b.sphere('Leaf', (0, 0, 0.5), 0.75, seg=7, rings=4, scale=(1.2, 1, 0.8)); b.sphere('LeafDark', (0.5, 0.3, 0.45), 0.5, seg=6, rings=4)
    P('bush', bush, [], C=NC)

    def rock(sc):
        def f(b, r, C):
            fs = b.sphere('Rock', (0, 0, 0.5 * sc), sc, seg=6, rings=4, scale=(1.2, 0.9, 0.7))
            for v in b.bm.verts:
                v.co.x += rnd.uniform(-0.12, 0.12) * sc; v.co.y += rnd.uniform(-0.12, 0.12) * sc; v.co.z += rnd.uniform(-0.08, 0.08) * sc
        return f
    P('rock_a', rock(1.0), [((0, 0, 0.45), (1.8, 1.4, 0.9))], C=NC)
    P('rock_b', rock(2.2), [((0, 0, 1.0), (4.0, 3.0, 2.0))], C=NC)

    def grass(b, r, C):
        for i in range(7):
            a = rnd.uniform(0, 6.28)
            d = rnd.uniform(0, 0.25)
            b.box('Leaf' if i % 2 else 'LeafDark', (math.cos(a) * d, math.sin(a) * d, 0.2), (0.05, 0.015, 0.4 + rnd.uniform(0, 0.2)), rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), a), top=(0.1, 1))
    P('grass', grass, [], C=NC)

    def flowers(b, r, C):
        for i in range(9):
            x, y = rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6)
            b.box('Leaf', (x, y, 0.15), (0.02, 0.02, 0.3)); b.box(('Yellow', 'Red', 'White', 'Neon')[i % 4], (x, y, 0.32), (0.09, 0.09, 0.06))
    P('flowers', flowers, [], C=NC)

    def log(b, r, C):
        b.cyl('Bark', (0, 0, 0.25), 0.25, 2.6, axis='X', seg=8); b.cyl('Wood', (1.3, 0, 0.25), 0.22, 0.02, axis='X', seg=8); b.cyl('Wood', (-1.3, 0, 0.25), 0.22, 0.02, axis='X', seg=8)
    P('log', log, [((0, 0, 0.25), (2.6, 0.5, 0.5))], C=NC)

    def wreck(b, r, C):
        secs = [(-6, 1.6, 0.0, 2.6), (-2, 2.2, -0.3, 2.4), (2, 2.0, -0.2, 2.5), (5, 1.0, 0.3, 3.0), (6.5, 0.1, 1.5, 3.4)]
        b.loft('Wall_Rust', [[(0, y, zk), (hw * 0.8, y, zk + 0.6), (hw, y, zd), (-hw, y, zd), (-hw * 0.8, y, zk + 0.6)] for y, hw, zk, zd in secs])
        b.box('Wall_Rust', (0, -3, 3.4), (2.6, 3.0, 2.0)); b.box('Dark', (0, -1.48, 3.6), (2.0, 0.05, 0.8))
        b.cyl('Wall_Rust', (0, -3.5, 5.2), 0.5, 2.0, seg=8); tube(b, 'Bark', (0, 2, 2.5), (0.8, 2.5, 7.5), 0.12)
    P('wreck', wreck, [((0, 0, 1.3), (3.6, 12.0, 2.6)), ((0, -3, 3.4), (2.6, 3.0, 2.0))], C=NC)

    def coral(b, r, C):
        for i in range(6):
            a = i * 1.05
            tube(b, ('Neon', 'Orange', 'Wall_Pink')[i % 3], (math.cos(a) * 0.2, math.sin(a) * 0.2, 0), (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.9 + (i % 3) * 0.3), 0.09, seg=5)
        b.sphere('Rock', (0, 0, 0.1), 0.5, seg=6, rings=3, scale=(1, 1, 0.5))
    P('coral', coral, [], C=NC)

    def seaweed(b, r, C):
        for i in range(5):
            x, y = rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4)
            b.box('LeafDark', (x, y, 0.9), (0.14, 0.03, 1.8), rot=(rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), rnd.uniform(0, 3)), top=(0.3, 1))
    P('seaweed', seaweed, [], C=NC)
    export_all(names, 'props')
    return names
