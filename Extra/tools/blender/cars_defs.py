# Car roster definitions (parameters for vehicles.build_car). All original designs.
import math
from fable_lib import *
from vehicles import build_car, build_wheel, wheel_geo


def lightbar(mb, y, z, w=0.95, lod=0):
    mb.box((w, 0.24, 0.045), loc=(0, y, z + 0.022), m="Trim")
    mb.box((w * 0.46, 0.20, 0.09), loc=(-w * 0.25, y, z + 0.085), m="LightBarRed", bevel=0.02 if lod == 0 else 0)
    mb.box((w * 0.46, 0.20, 0.09), loc=(w * 0.25, y, z + 0.085), m="LightBarBlue", bevel=0.02 if lod == 0 else 0)


def bullbar(mb, P, zt, zb):
    yF = P['L'] / 2
    z0 = zb(yF) + 0.05
    z1 = zt(yF) + 0.02
    for s in (1, -1):
        mb.tube((s * 0.38, yF + 0.16, z0), (s * 0.38, yF + 0.16, z1), 0.03, "DarkSteel")
        mb.tube((s * 0.38, yF + 0.16, z0 + 0.06), (s * 0.38, yF + 0.02, z0 + 0.06), 0.025, "DarkSteel")
    for z in (z0 + 0.10, (z0 + z1) / 2, z1 - 0.03):
        mb.tube((-0.62, yF + 0.16, z), (0.62, yF + 0.16, z), 0.028, "DarkSteel")


def ex_police(mb, c):
    P = c['P']
    cab = P['cab']
    lightbar(mb, (cab['b'] + cab['c']) / 2 + 0.25, P['H'], lod=c['lod'])
    if c['lod'] == 0:
        bullbar(mb, P, c['zt'], c['zb'])
        mb.tube((0.55, cab['c'] + 0.1, P['H']), (0.55, cab['c'] + 0.1, P['H'] + 0.45), 0.008, "Trim", segs=4)


def ex_taxi(mb, c):
    P = c['P']
    cab = P['cab']
    y = (cab['b'] + cab['c']) / 2 + 0.1
    mb.box((0.52, 0.17, 0.15), loc=(0, y, P['H'] + 0.085), m="TaxiSign", bevel=0.03 if c['lod'] == 0 else 0)
    mb.box((0.60, 0.22, 0.03), loc=(0, y, P['H'] + 0.01), m="Trim")
    # checker band along the belt line
    if c['lod'] == 0:
        n = 14
        y0, y1 = 1.35, -1.75
        for s in (1, -1):
            for i in range(n):
                if i % 2 == 0:
                    ya = y0 + (y1 - y0) * i / n
                    yb = y0 + (y1 - y0) * (i + 1) / n
                    ym = (ya + yb) / 2
                    mb.box((0.012, abs(ya - yb), 0.07), loc=(s * (c['hw'](ym) + 0.014), ym, c['zt'](ym) - 0.20), m="Trim")


def ex_suv(mb, c):
    P = c['P']
    cab = P['cab']
    if c['lod'] == 0:
        for s in (1, -1):
            x = s * (P['W'] / 2 * cab['wroof'] - 0.06)
            mb.tube((x, cab['b'] - 0.15, P['H'] + 0.05), (x, cab['c'] + 0.15, P['H'] + 0.05), 0.02, "Trim")
            for y in (cab['b'] - 0.25, cab['c'] + 0.25):
                mb.tube((x, y, P['H']), (x, y, P['H'] + 0.05), 0.015, "Trim", segs=4)
        yR = -P['L'] / 2
        wheel_geo(mb, P['wr'] * 0.95, 0.20, 2, loc=(0, yR - 0.13, 0.98), segs=12)
        # rotate spare is skipped; mounted flat cover instead


def ex_pickup(mb, c):
    P = c['P']
    if c['lod'] == 0:
        y = P['cab']['d'] - 0.10
        for s in (1, -1):
            mb.tube((s * 0.80, y, 1.14), (s * 0.80, y, 1.74), 0.03, "DarkSteel")
        mb.tube((-0.80, y, 1.74), (0.80, y, 1.74), 0.03, "DarkSteel")
        for x in (-0.45, -0.15, 0.15, 0.45):
            mb.box((0.14, 0.07, 0.07), loc=(x, y, 1.80), m="LightHead")


def ex_van(mb, c):
    P = c['P']
    if c['lod'] == 0:
        mb.box((P['W'] * 0.84, 0.05, P['H'] - 1.16), loc=(0, 0.18, (P['H'] + 1.12) / 2), m="Interior")


def box_body(mb, c, y0, y1, z0, z1, w, m, stripe=None, door="Corrugated"):
    lod = c['lod']
    mb.box((w, y0 - y1, z1 - z0), loc=(0, (y0 + y1) / 2, (z0 + z1) / 2), m=m, bevel=0.04 if lod == 0 else 0)
    mb.box((w * 0.9, (y0 - y1) * 0.96, 0.12), loc=(0, (y0 + y1) / 2, z0 - 0.06), m="Under")
    if lod == 0:
        mb.box((w * 0.86, 0.03, (z1 - z0) * 0.86), loc=(0, y1 - 0.012, (z0 + z1) / 2), m=door)
        for i in range(1, 6):
            mb.box((w * 0.86, 0.036, 0.015), loc=(0, y1 - 0.012, z0 + (z1 - z0) * (0.07 + i * 0.86 / 6.0)), m="DarkSteel")
    if stripe:
        for s in (1, -1):
            mb.box((0.012, (y0 - y1) * 0.98, 0.22), loc=(s * (w / 2 + 0.004), (y0 + y1) / 2, z0 + (z1 - z0) * 0.42), m=stripe)


def ex_ambulance(mb, c):
    P = c['P']
    box_body(mb, c, 0.72, -2.78, 1.02, 2.62, 2.14, "EmsWhite", stripe="EmsRed", door="EmsWhite")
    lightbar(mb, 1.25, P['H'], 1.2, c['lod'])
    lightbar(mb, -2.55, 2.62, 1.5, c['lod'])
    for s in (1, -1):
        mb.box((0.012, 0.50, 0.50), loc=(s * 1.076, -0.9, 2.05), m="EmsRed")
        mb.box((0.014, 0.16, 0.50), loc=(s * 1.077, -0.9, 2.05), m="EmsWhite")
        mb.box((0.014, 0.50, 0.16), loc=(s * 1.077, -0.9, 2.05), m="EmsWhite")


def ex_truck(mb, c):
    box_body(mb, c, 1.28, -3.25, 1.02, 3.05, 2.36, "PaintWhite", stripe=c['paint'])


def ex_firetruck(mb, c):
    P = c['P']
    lod = c['lod']
    mb.box((2.36, 4.30, 1.20), loc=(0, -1.30, 1.72), m="FireRed", bevel=0.04 if lod == 0 else 0)
    mb.box((2.2, 4.2, 0.12), loc=(0, -1.30, 1.06), m="Under")
    lightbar(mb, 2.55, P['H'], 1.5, lod)
    if lod == 0:
        for s in (1, -1):
            for k in range(3):
                mb.box((0.02, 1.05, 0.72), loc=(s * 1.185, 0.05 - k * 1.25, 1.62), m="Steel")
                mb.box((0.03, 0.9, 0.03), loc=(s * 1.19, 0.05 - k * 1.25, 1.30), m="DarkSteel")
            mb.box((0.02, 4.2, 0.10), loc=(s * 1.185, -1.30, 2.22), m="PaintYellow")
        # ladder
        for s in (1, -1):
            mb.tube((s * 0.30, 0.9, 2.42), (s * 0.30, -3.5, 2.60), 0.035, "Steel")
        for k in range(12):
            y = 0.7 - k * 0.37
            z = 2.42 + (0.9 - y) / 4.4 * 0.18
            mb.tube((-0.30, y, z), (0.30, y, z), 0.022, "Steel", segs=4)
        mb.cyl(0.42, 0.14, loc=(0, -2.9, 2.40), segs=10, m="DarkSteel")
        mb.cyl(0.10, 0.5, loc=(0.75, -0.2, 2.42), axis='Y', segs=8, m="Chrome")
        mb.box((0.5, 0.9, 0.25), loc=(-0.7, -0.4, 2.45), m="DarkSteel", bevel=0.03)


def ex_swat(mb, c):
    P = c['P']
    lod = c['lod']
    lightbar(mb, 1.0, P['H'], 1.2, lod)
    if lod == 0:
        yF = P['L'] / 2
        mb.box((2.0, 0.14, 0.42), loc=(0, yF + 0.13, 0.62), m="DarkSteel", bevel=0.03)
        for s in (1, -1):
            mb.box((0.16, 0.10, 0.05), loc=(s * 0.7, yF + 0.2, 0.5), m="DarkSteel")
            mb.box((0.03, 3.0, 0.12), loc=(s * (P['W'] / 2 + 0.02), -0.6, 0.55), m="DarkSteel")
            mb.box((0.02, 0.9, 0.05), loc=(s * (P['W'] / 2 * 0.9), -1.0, P['H'] + 0.04), m="DarkSteel")
        mb.box((0.7, 0.7, 0.08), loc=(0, -1.2, P['H'] + 0.04), m="DarkSteel", bevel=0.02)


CARS = {
    'compact': dict(L=3.75, W=1.68, H=1.46, axf=1.18, axr=-1.24, wr=0.30, ww=0.20, gc=0.19, color='#e0563a',
                    top=[(1.875, 0.60), (1.80, 0.72), (0.80, 0.88), (-1.70, 0.92), (-1.875, 0.80)],
                    plan=[(1.875, 0.78), (1.70, 0.94), (1.2, 1.0), (-1.4, 1.0), (-1.80, 0.95), (-1.875, 0.86)],
                    cab=dict(a=0.85, b=0.25, c=-1.35, d=-1.78, wroof=0.78),
                    doors=[(0.60, -0.42)], seats=[(-0.36, 0.0), (0.36, 0.0)], rim=2),
    'sedan': dict(L=4.60, W=1.82, H=1.44, axf=1.42, axr=-1.33, wr=0.33, ww=0.22, gc=0.20, color='#3d7ea6',
                  top=[(2.30, 0.62), (2.22, 0.74), (0.95, 0.90), (-1.45, 0.94), (-2.18, 0.90), (-2.30, 0.78)],
                  plan=[(2.30, 0.80), (2.10, 0.94), (1.5, 1.0), (-1.6, 1.0), (-2.15, 0.95), (-2.30, 0.84)],
                  cab=dict(a=0.95, b=0.30, c=-1.00, d=-1.62, wroof=0.76),
                  doors=[(0.72, -0.18), (-0.18, -0.90)],
                  seats=[(-0.38, 0.10), (0.38, 0.10), (-0.38, -0.62), (0.38, -0.62)], rim=1),
    'sports': dict(L=4.35, W=1.92, H=1.20, axf=1.38, axr=-1.30, wr=0.34, ww=0.27, gc=0.12, color='#f2b705',
                   top=[(2.175, 0.50), (2.04, 0.66), (1.50, 0.82), (0.75, 0.84), (-1.25, 0.88), (-2.05, 0.88), (-2.175, 0.72)],
                   plan=[(2.175, 0.76), (1.95, 0.93), (1.3, 1.0), (-1.5, 1.0), (-2.0, 0.96), (-2.175, 0.86)],
                   cab=dict(a=0.70, b=-0.05, c=-0.75, d=-1.35, wroof=0.70),
                   doors=[(0.48, -0.55)], seats=[(-0.40, -0.12), (0.40, -0.12)], recline=0.45, seat_h=0.05,
                   convertible=True, rim=0, light_drop=0.07, engine_y=-1.6),
    'muscle': dict(L=4.85, W=1.90, H=1.34, axf=1.50, axr=-1.40, wr=0.35, ww=0.26, gc=0.18, color='#7d2a8c',
                   top=[(2.425, 0.62), (2.36, 0.80), (1.60, 0.90), (0.55, 0.94), (-1.55, 0.96), (-2.30, 0.94), (-2.425, 0.78)],
                   plan=[(2.425, 0.88), (2.30, 0.97), (1.5, 1.0), (-1.6, 1.0), (-2.3, 0.97), (-2.425, 0.90)],
                   cab=dict(a=0.55, b=-0.10, c=-1.00, d=-1.70, wroof=0.74),
                   doors=[(0.35, -0.70)], seats=[(-0.40, -0.25), (0.40, -0.25)], recline=0.35, rim=4),
    'suv': dict(L=4.75, W=1.95, H=1.80, axf=1.45, axr=-1.40, wr=0.39, ww=0.26, gc=0.27, color='#2f6b4f',
                top=[(2.375, 0.80), (2.30, 0.98), (1.00, 1.10), (-2.25, 1.12), (-2.375, 0.95)],
                plan=[(2.375, 0.86), (2.2, 0.97), (1.5, 1.0), (-2.2, 1.0), (-2.375, 0.92)],
                cab=dict(a=1.00, b=0.50, c=-2.05, d=-2.33, wroof=0.80),
                doors=[(0.78, -0.10), (-0.10, -0.92)],
                seats=[(-0.42, 0.18), (0.42, 0.18), (-0.42, -0.60), (0.42, -0.60)],
                cladding=True, bumper_trim=True, extra=ex_suv, rim=0, seat_h=0.14),
    'pickup': dict(L=5.30, W=1.95, H=1.82, axf=1.72, axr=-1.55, wr=0.40, ww=0.27, gc=0.29, color='#c9772a',
                   top=[(2.65, 0.82), (2.58, 1.00), (1.30, 1.12), (-2.60, 1.14), (-2.65, 1.00)],
                   plan=[(2.65, 0.88), (2.5, 0.98), (1.8, 1.0), (-2.6, 1.0), (-2.65, 0.96)],
                   cab=dict(a=1.30, b=0.80, c=-0.40, d=-0.50, wroof=0.80),
                   doors=[(1.05, 0.05)], well_end=-0.40, bed=(-0.62, -2.52, 0.90),
                   seats=[(-0.42, 0.48), (0.42, 0.48)], cladding=True, bumper_trim=True, extra=ex_pickup, rim=2,
                   seat_h=0.14),
    'van': dict(L=5.10, W=1.98, H=2.15, axf=1.70, axr=-1.50, wr=0.37, ww=0.25, gc=0.24, color='#e9e4d8',
                top=[(2.55, 0.85), (2.50, 1.02), (2.00, 1.12), (-2.50, 1.14), (-2.55, 1.0)],
                plan=[(2.55, 0.90), (2.4, 0.98), (1.9, 1.0), (-2.5, 1.0), (-2.55, 0.97)],
                cab=dict(a=2.00, b=1.45, c=-2.46, d=-2.53, wroof=0.90, solid=[(0.30, -2.6)]),
                doors=[(1.15, 0.30)], well_end=0.20, seats=[(-0.45, 0.62), (0.45, 0.62)],
                bumper_trim=True, extra=ex_van, rim=2, seat_h=0.18),
    'police': dict(L=4.80, W=1.88, H=1.47, axf=1.50, axr=-1.40, wr=0.34, ww=0.24, gc=0.21,
                   paint='PoliceBlack', paint2='PoliceWhite', door_paint='PoliceWhite', roof2=True,
                   top=[(2.40, 0.64), (2.32, 0.77), (1.00, 0.92), (-1.50, 0.96), (-2.28, 0.92), (-2.40, 0.80)],
                   plan=[(2.40, 0.84), (2.20, 0.96), (1.5, 1.0), (-1.7, 1.0), (-2.25, 0.96), (-2.40, 0.86)],
                   cab=dict(a=1.00, b=0.35, c=-1.05, d=-1.68, wroof=0.77),
                   doors=[(0.76, -0.16), (-0.16, -0.92)],
                   seats=[(-0.39, 0.12), (0.39, 0.12), (-0.39, -0.62), (0.39, -0.62)],
                   extra=ex_police, rim=2, bumper_trim=True, mods=False),
    'taxi': dict(L=4.55, W=1.84, H=1.52, axf=1.40, axr=-1.32, wr=0.33, ww=0.22, gc=0.20,
                 paint='TaxiYellow', paint2='Trim',
                 top=[(2.275, 0.64), (2.20, 0.76), (1.00, 0.93), (-1.50, 0.97), (-2.16, 0.93), (-2.275, 0.80)],
                 plan=[(2.275, 0.82), (2.08, 0.95), (1.5, 1.0), (-1.6, 1.0), (-2.12, 0.96), (-2.275, 0.86)],
                 cab=dict(a=1.00, b=0.38, c=-1.15, d=-1.66, wroof=0.79),
                 doors=[(0.76, -0.16), (-0.16, -0.90)],
                 seats=[(-0.38, 0.12), (0.38, 0.12), (-0.38, -0.62), (0.38, -0.62)],
                 extra=ex_taxi, rim=2, mods=False),
    'ambulance': dict(L=5.70, W=2.10, H=2.02, axf=1.95, axr=-1.65, wr=0.38, ww=0.26, gc=0.25,
                      paint='EmsWhite', paint2='EmsRed',
                      top=[(2.85, 0.85), (2.80, 1.02), (2.30, 1.12), (0.70, 1.14), (0.69, 1.02), (-2.80, 1.02), (-2.85, 0.95)],
                      plan=[(2.85, 0.90), (2.7, 0.98), (2.2, 1.0), (-2.8, 1.0), (-2.85, 0.97)],
                      cab=dict(a=2.30, b=1.75, c=0.74, d=0.71, wroof=0.90, rear_solid=True),
                      doors=[(1.45, 0.76)], seats=[(-0.48, 1.05), (0.48, 1.05)], seat_h=0.18,
                      extra=ex_ambulance, rim=2, mods=False, bumper_trim=True,
                      col_extra=[((2.1, 3.5, 1.6), (0, -1.03, 1.82))]),
    'truck': dict(L=6.70, W=2.30, H=2.35, axf=2.45, axr=-2.05, wr=0.46, ww=0.30, gc=0.34, color='#2a67c9',
                  top=[(3.35, 1.00), (3.30, 1.20), (2.85, 1.30), (1.26, 1.32), (1.25, 1.02), (-3.30, 1.02), (-3.35, 0.95)],
                  plan=[(3.35, 0.92), (3.2, 0.99), (2.6, 1.0), (-3.3, 1.0), (-3.35, 0.97)],
                  cab=dict(a=2.85, b=2.45, c=1.30, d=1.27, wroof=0.90, rear_solid=True),
                  doors=[(2.00, 1.32)], seats=[(-0.52, 1.60), (0.52, 1.60)], seat_h=0.25,
                  extra=ex_truck, rim=2, mods=False, bumper_trim=True, rocker=0.20,
                  col_extra=[((2.36, 4.5, 2.0), (0, -0.98, 2.04))]),
    'firetruck': dict(L=7.60, W=2.42, H=2.50, axf=2.75, axr=-2.20, wr=0.50, ww=0.32, gc=0.36,
                      paint='FireRed', paint2='PaintWhite', roof2=True,
                      top=[(3.80, 1.00), (3.75, 1.25), (3.45, 1.32), (0.88, 1.34), (0.87, 1.10), (-3.70, 1.10), (-3.80, 1.0)],
                      plan=[(3.80, 0.94), (3.65, 1.0), (-3.7, 1.0), (-3.80, 0.97)],
                      cab=dict(a=3.45, b=3.15, c=0.92, d=0.89, wroof=0.92, rear_solid=True),
                      doors=[(2.20, 1.40)], seats=[(-0.60, 1.72), (0.60, 1.72)], seat_h=0.30,
                      extra=ex_firetruck, rim=2, mods=False, bumper_trim=True, rocker=0.20,
                      col_extra=[((2.36, 4.3, 1.3), (0, -1.30, 1.75))]),
    'swat': dict(L=5.90, W=2.24, H=2.55, axf=1.95, axr=-1.80, wr=0.47, ww=0.32, gc=0.36,
                 paint='SwatNavy', paint2='Trim',
                 top=[(2.95, 1.00), (2.90, 1.22), (2.20, 1.34), (-2.90, 1.36), (-2.95, 1.2)],
                 plan=[(2.95, 0.90), (2.8, 0.98), (2.2, 1.0), (-2.9, 1.0), (-2.95, 0.97)],
                 cab=dict(a=2.20, b=1.85, c=-2.86, d=-2.93, wroof=0.90, margin=0.12, solid=[(0.60, -3.0)], rear_solid=True),
                 doors=[(1.38, 0.62)], well_end=0.50, seats=[(-0.55, 0.92), (0.55, 0.92)], seat_h=0.28,
                 extra=ex_swat, rim=2, mods=False, bumper_trim=True, cladding=True, rocker=0.22),
}

ORDER = ['compact', 'sedan', 'sports', 'muscle', 'suv', 'pickup', 'van', 'police', 'taxi', 'ambulance', 'truck',
         'firetruck', 'swat']


def build(names=None):
    mat("TaxiSign", "#f7d23e", rough=0.4, emit="#ffd84a", estr=1.2)
    out = []
    for i, n in enumerate(ORDER):
        if names and n not in names:
            continue
        r = build_car(n, CARS[n], cell=(20 + i * 4.0, 20, 0))
        out.append(stats(r))
    return out


def export_all(names=None):
    out = []
    for n in ORDER:
        if names and n not in names:
            continue
        out.append(export(n, "vehicles/%s.glb" % n))
    return out
