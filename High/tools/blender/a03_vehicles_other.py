"""Motorcycle, bicycle, boat, helicopters and airplanes. Run through Blender MCP after a02_cars.py."""
import sys
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *


def place_wheel(parent, name, style, pos, r, w, left, collection):
    src = bpy.data.objects["wheel_" + style]
    ob = bpy.data.objects.new(name, src.data)
    collection.objects.link(ob)
    ob.parent = parent
    ob.location = pos
    ob.scale = (w, r, r)
    ob.rotation_euler = (0, 0, math.pi if left else 0)
    return ob


def oct_ring(y, zc, hw, hh, n=8):
    k = 1.0 / math.cos(math.pi / n)
    pts = []
    for i in range(n):
        a = math.pi / n + 2 * math.pi * i / n
        pts.append((math.cos(a) * hw * k, y, zc + math.sin(a) * hh * k))
    return pts


def tube_loft(mb, stations, paint="M_Paint", glass="M_Glass", belly=None, cap0=True, cap1=True):
    rings = [oct_ring(s[0], s[1], s[2], s[3]) for s in stations]
    flags = [s[4] for s in stations]

    def mf(i, k):
        fl = flags[i]
        if fl == 'glassfull' and k in (0, 1, 2, 3, 7):
            return glass
        if fl == 'glass' and k in (0, 1, 2):
            return glass
        if fl == 'glassside' and k in (0, 2, 3, 7):
            return glass
        if belly and k in (4, 5, 6):
            return belly
        if fl == 'p2':
            return "M_Paint2"
        return paint
    mb.loft(rings, mf, cap0=paint if cap0 else None, cap1=paint if cap1 else None)


# ================================================================== MOTORCYCLE
def build_motorcycle(loc):
    vid = "motorcycle"
    C = coll("Vehicles/Motorcycles")
    wipe([vid + "_", vid])
    mb = MB()
    wr = 0.32
    yf, yr = 0.78, -0.70
    # frame / engine
    mb.box((0, 0.02, 0.42), (0.26, 0.50, 0.30), "M_MetalDark")
    mb.cyl((0, 0.05, 0.50), 0.13, 0.34, "M_Metal", axis='X', seg=8)
    mb.limb((0, 0.45, 0.80), (0, yf - 0.02, wr), 0.035, 0.03, "M_Chrome", seg=6)
    for sx in (-1, 1):
        mb.limb((sx * 0.09, 0.47, 0.86), (sx * 0.09, yf, wr), 0.028, 0.028, "M_Chrome", seg=5)
        mb.limb((sx * 0.07, -0.05, 0.40), (sx * 0.07, yr, wr), 0.03, 0.03, "M_MetalDark", seg=5)
    # tank, seat, tail
    mb.box((0, 0.20, 0.78), (0.30, 0.52, 0.22), "M_Paint", top=(0.22, 0.40), top_off=(0, 0.02))
    mb.box((0, -0.30, 0.76), (0.28, 0.56, 0.10), "M_Seat")
    mb.box((0, -0.68, 0.78), (0.22, 0.30, 0.12), "M_Paint", top=(0.14, 0.2), top_off=(0, -0.03))
    mb.box((0, -0.86, 0.76), (0.14, 0.04, 0.06), "M_Taillight")
    # fenders
    mb.box((0, yf, wr + 0.36), (0.14, 0.50, 0.04), "M_Paint")
    mb.box((0, yr - 0.05, wr + 0.38), (0.16, 0.44, 0.04), "M_Paint")
    # handlebar + headlight
    mb.limb((-0.34, 0.42, 1.02), (0.34, 0.42, 1.02), 0.022, 0.022, "M_Chrome", seg=5)
    for sx in (-1, 1):
        mb.limb((sx * 0.34, 0.42, 1.02), (sx * 0.24, 0.42, 1.02), 0.03, 0.03, "M_Black", seg=5)
        mb.limb((sx * 0.09, 0.47, 0.86), (sx * 0.12, 0.42, 1.02), 0.02, 0.02, "M_Chrome", seg=5)
    mb.cyl((0, 0.58, 0.90), 0.10, 0.12, "M_Chrome", axis='Y', seg=8, cap_m="M_Headlight")
    # exhaust
    mb.limb((0.16, 0.10, 0.34), (0.19, -0.80, 0.42), 0.045, 0.06, "M_Chrome", seg=6)
    mb.box((0.13, -0.05, 0.16), (0.04, 0.3, 0.03), "M_Black")
    body = mb.build(vid, C, loc=loc)
    place_wheel(body, vid + "_wheel_f", "bike", (0, yf, wr), wr, 0.13, False, C)
    place_wheel(body, vid + "_wheel_r", "bike", (0, yr, wr), wr, 0.16, False, C)
    empty(vid + "_seat_0", C, loc=(0, -0.22, 0.82), parent=body)
    empty(vid + "_seat_1", C, loc=(0, -0.55, 0.84), parent=body)
    empty(vid + "_headlight_l", C, loc=(0, 0.68, 0.90), parent=body)
    empty(vid + "_taillight_l", C, loc=(0, -0.92, 0.76), parent=body)
    empty(vid + "_exhaust", C, loc=(0.19, -0.9, 0.42), parent=body)
    return body


def build_bicycle(loc):
    vid = "bicycle"
    C = coll("Vehicles/Motorcycles")
    wipe([vid + "_", vid])
    mb = MB()
    wr = 0.34
    yf, yr = 0.55, -0.50
    t = 0.022
    seat = (0, -0.18, 0.92)
    bb = (0, 0.0, 0.30)
    head = (0, 0.40, 0.86)
    mb.limb(bb, seat, t, t, "M_Paint", seg=5)
    mb.limb(bb, head, t * 1.2, t, "M_Paint", seg=5)
    mb.limb((0, -0.14, 0.80), head, t, t, "M_Paint", seg=5)
    mb.limb(head, (0, 0.44, 1.02), t, t, "M_Chrome", seg=5)
    for sx in (-1, 1):
        mb.limb(bb, (sx * 0.04, yr, wr), t * 0.8, t * 0.8, "M_Paint", seg=4)
        mb.limb((0, -0.14, 0.80), (sx * 0.04, yr, wr), t * 0.7, t * 0.7, "M_Paint", seg=4)
        mb.limb((0, 0.40, 0.80), (sx * 0.04, yf, wr), t * 0.8, t * 0.8, "M_Chrome", seg=4)
    mb.limb((-0.26, 0.44, 1.02), (0.26, 0.44, 1.02), 0.016, 0.016, "M_Black", seg=5)
    mb.box((0, -0.20, 0.95), (0.14, 0.26, 0.05), "M_Seat", top=(0.10, 0.2))
    mb.cyl(bb, 0.09, 0.02, "M_Chrome", axis='X', seg=8)
    mb.box((0.10, 0.0, 0.18), (0.08, 0.10, 0.02), "M_Black")
    mb.box((-0.10, 0.0, 0.42), (0.08, 0.10, 0.02), "M_Black")
    body = mb.build(vid, C, loc=loc)
    place_wheel(body, vid + "_wheel_f", "bike", (0, yf, wr), wr, 0.05, False, C)
    place_wheel(body, vid + "_wheel_r", "bike", (0, yr, wr), wr, 0.05, False, C)
    empty(vid + "_seat_0", C, loc=(0, -0.18, 0.98), parent=body)
    return body


# ================================================================== BOAT
def build_boat(vid, loc, police=False):
    C = coll("Vehicles/Boats")
    wipe([vid + "_", vid])
    mb = MB()
    # hull sections: (y, keel_z, half_w_chine, chine_z, half_w_gunwale, gunwale_z)
    S = [(-3.2, -0.30, 0.95, -0.05, 1.12, 0.52), (-1.0, -0.36, 1.05, -0.05, 1.22, 0.56), (1.2, -0.32, 0.98, 0.0, 1.16, 0.62),
         (2.6, -0.18, 0.62, 0.14, 0.78, 0.70), (3.5, 0.30, 0.10, 0.50, 0.14, 0.78)]
    rings = []
    for (y, kz, cw, cz, gw, gz) in S:
        rings.append([(0, y, kz), (cw, y, cz), (gw, y, gz), (gw - 0.10, y, gz + 0.03), (-(gw - 0.10), y, gz + 0.03), (-gw, y, gz), (-cw, y, cz)])

    def mf(i, k):
        if k in (0, 6):
            return "M_Paint2" if not police else "M_Paint2"
        if k in (1, 5):
            return "M_Paint"
        return "M_White"
    mb.loft(rings, mf, cap0="M_Paint", cap1="M_Paint")
    # cockpit recess + coaming
    mb.box((0, -0.9, 0.60), (1.7, 3.4, 0.03), "M_Interior")
    for sx in (-1, 1):
        mb.box((sx * 0.98, -0.9, 0.72), (0.16, 3.6, 0.22), "M_White")
    mb.box((0, -2.95, 0.72), (2.0, 0.22, 0.22), "M_White")
    # console + windshield
    mb.box((0, 0.75, 0.86), (1.9, 0.5, 0.50), "M_White", top=(1.8, 0.3), top_off=(0, -0.08))
    mb.box((0, 0.72, 1.28), (1.76, 0.05, 0.42), "M_Glass", rot=(-0.5, 0, 0))
    mb.box((0, 0.62, 1.5), (1.84, 0.05, 0.04), "M_Chrome")
    mb.cyl((-0.42, 0.42, 1.02), 0.16, 0.03, "M_Black", axis='Y', seg=10)
    seats = [(-0.42, -0.2, 0.92), (0.42, -0.2, 0.92), (-0.42, -1.7, 0.92), (0.42, -1.7, 0.92)]
    for (sx, sy, sz) in seats:
        mb.box((sx, sy - 0.02, sz - 0.14), (0.50, 0.5, 0.30), "M_Seat")
        mb.box((sx, sy - 0.30, sz + 0.20), (0.50, 0.12, 0.55), "M_Seat", rot=(-0.12, 0, 0))
    # bow rail + cleats
    for sx in (-1, 1):
        mb.limb((sx * 0.95, 1.5, 0.72), (sx * 0.3, 3.1, 0.98), 0.02, 0.02, "M_Chrome", seg=4)
        mb.limb((sx * 0.95, 1.5, 0.72), (sx * 0.95, 1.5, 0.96), 0.02, 0.02, "M_Chrome", seg=4)
        mb.limb((sx * 0.95, 1.5, 0.96), (sx * 0.3, 3.1, 0.98), 0.02, 0.02, "M_Chrome", seg=4)
    # outboard motor
    mb.box((0, -3.42, 0.62), (0.44, 0.50, 0.50), "M_Black", top=(0.36, 0.4))
    mb.box((0, -3.42, 0.90), (0.40, 0.46, 0.08), "M_Paint")
    mb.box((0, -3.50, 0.05), (0.10, 0.20, 0.70), "M_MetalDark")
    mb.cyl((0, -3.62, -0.26), 0.16, 0.05, "M_Chrome", axis='Y', seg=6)
    if police:
        mb.box((0, 0.62, 1.60), (1.0, 0.24, 0.05), "M_Black")
        mb.box((-0.26, 0.62, 1.68), (0.44, 0.2, 0.11), "M_Siren_R")
        mb.box((0.26, 0.62, 1.68), (0.44, 0.2, 0.11), "M_Siren_B")
        for sx in (-1, 1):
            mb.limb((sx * 0.9, 0.62, 1.05), (sx * 0.5, 0.62, 1.6), 0.025, 0.025, "M_Chrome", seg=4)
    body = mb.build(vid, C, loc=loc)
    for i, s in enumerate(seats):
        empty(vid + "_seat_%d" % i, C, loc=s, parent=body)
    empty(vid + "_exhaust", C, loc=(0, -3.7, -0.2), parent=body)
    empty(vid + "_headlight_l", C, loc=(0, 3.4, 0.8), parent=body)
    return body


# ================================================================== HELICOPTERS
def rotor(name, C, parent, loc, radius, blades, chord, axis='Z'):
    mb = MB()
    for i in range(blades):
        a = 2 * math.pi * i / blades
        if axis == 'Z':
            mb.push((0, 0, 0), (0, 0, a))
            mb.box((radius / 2 + 0.1, 0, 0), (radius, chord, 0.03), "M_Black")
            mb.box((radius - 0.15, 0, 0.002), (0.25, chord, 0.032), "M_Yellow")
            mb.pop()
        else:
            mb.push((0, 0, 0), (a, 0, 0))
            mb.box((0, radius / 2, 0), (0.03, radius, chord), "M_Black")
            mb.pop()
    if axis == 'Z':
        mb.cyl((0, 0, 0), 0.14, 0.12, "M_MetalDark", seg=8)
    else:
        mb.cyl((0, 0, 0), 0.07, 0.08, "M_MetalDark", axis='X', seg=8)
    return mb.build(name, C, loc=loc, parent=parent)


def build_heli(vid, loc, police=False):
    C = coll("Vehicles/Helicopters")
    wipe([vid + "_", vid])
    mb = MB()
    if not police:
        st = [(2.45, 1.15, 0.22, 0.22, 'glassfull'), (1.95, 1.25, 0.62, 0.55, 'glassfull'), (1.10, 1.40, 0.80, 0.78, 'glass'),
              (0.20, 1.45, 0.82, 0.82, 'body'), (-0.90, 1.50, 0.75, 0.75, 'body'), (-1.60, 1.68, 0.34, 0.38, 'body'),
              (-4.60, 1.88, 0.11, 0.13, 'end')]
        mast_z, rr, tail_y, tail_z = 2.32, 4.3, -4.5, 1.95
        seats = [(-0.36, 1.05, 1.02), (0.36, 1.05, 1.02), (-0.36, 0.10, 1.02), (0.36, 0.10, 1.02)]
        skid_x, skid_y0, skid_y1, belly_z = 0.92, -1.1, 1.7, 0.72
    else:
        st = [(3.0, 1.22, 0.28, 0.26, 'glassfull'), (2.35, 1.35, 0.72, 0.60, 'glass'), (1.45, 1.52, 0.96, 0.86, 'glass'),
              (0.40, 1.58, 1.02, 0.96, 'p2'), (-1.60, 1.62, 0.96, 0.92, 'body'), (-2.50, 1.85, 0.40, 0.44, 'body'),
              (-5.70, 2.08, 0.13, 0.15, 'end')]
        mast_z, rr, tail_y, tail_z = 2.62, 5.0, -5.6, 2.18
        seats = [(-0.42, 1.45, 1.08), (0.42, 1.45, 1.08), (-0.42, -0.2, 1.08), (0.42, -0.2, 1.08)]
        skid_x, skid_y0, skid_y1, belly_z = 1.08, -1.6, 2.1, 0.70
    tube_loft(mb, st, belly="M_Paint2" if police else None)
    # interior floor + seats + dash
    mb.box((0, seats[0][1] - 0.4, seats[0][2] - 0.26), (st[3][2] * 1.6, 2.0, 0.05), "M_Interior")
    for (sx, sy, sz) in seats:
        mb.box((sx, sy - 0.02, sz - 0.12), (0.46, 0.46, 0.14), "M_Seat")
        mb.box((sx, sy - 0.26, sz + 0.20), (0.46, 0.10, 0.56), "M_Seat")
    mb.box((0, seats[0][1] + 0.62, seats[0][2] + 0.05), (0.9, 0.3, 0.4), "M_Interior")
    # engine cowl + mast
    mb.box((0, -0.3, st[3][1] + st[3][3] + 0.14), (0.9, 1.8, 0.34), "M_Paint", top=(0.6, 1.3))
    mb.cyl((0, 0, mast_z - 0.12), 0.07, 0.36, "M_MetalDark", seg=6)
    # tail fin + stabiliser
    mb.prism([(tail_y + 0.5, tail_z - 0.55), (tail_y - 0.35, tail_z - 0.75), (tail_y - 0.55, tail_z + 0.85), (tail_y - 0.1, tail_z + 0.85)], 0.07, "M_Paint", plane='YZ')
    mb.box((0, tail_y + 0.9, tail_z - 0.05), (1.5, 0.36, 0.05), "M_Paint")
    for sx in (-1, 1):
        mb.box((sx * 0.75, tail_y + 0.9, tail_z - 0.05), (0.05, 0.42, 0.36), "M_Paint2")
    # skids
    for sx in (-1, 1):
        mb.limb((sx * skid_x, skid_y0, 0.06), (sx * skid_x, skid_y1, 0.06), 0.045, 0.045, "M_MetalDark", seg=6)
        mb.limb((sx * skid_x, skid_y1, 0.06), (sx * skid_x, skid_y1 + 0.3, 0.22), 0.045, 0.04, "M_MetalDark", seg=6)
        for sy in (skid_y0 + 0.5, skid_y1 - 0.6):
            mb.limb((sx * skid_x, sy, 0.06), (sx * (skid_x - 0.3), sy, belly_z), 0.035, 0.035, "M_MetalDark", seg=5)
    # doors (dark outlines) + lights
    for sx in (-1, 1):
        mb.box((sx * (st[3][2] + 0.012), seats[0][1] - 0.5, st[3][1] - 0.15), (0.02, 1.5, 0.05), "M_Black")
    mb.box((0, st[0][0] - 0.2, st[0][1] - 0.32), (0.16, 0.12, 0.10), "M_Headlight")
    mb.box((0, tail_y - 0.5, tail_z + 0.9), (0.08, 0.08, 0.08), "M_Taillight")
    if police:
        mb.cyl((0, 2.3, 0.62), 0.16, 0.22, "M_MetalDark", axis='Y', seg=8, cap_m="M_Headlight")
        mb.limb((0, 2.3, 0.62), (0, 2.2, 0.82), 0.04, 0.04, "M_MetalDark", seg=4)
        for sx in (-1, 1):
            mb.box((sx * 1.035, -0.5, 1.9), (0.02, 1.6, 0.16), "M_Paint2")
            mb.box((sx * 0.5, 0.9, 2.5), (0.3, 0.2, 0.10), "M_Siren_R" if sx < 0 else "M_Siren_B")
    body = mb.build(vid, C, loc=loc)
    rotor(vid + "_rotor_main", C, body, (0, 0, mast_z + 0.1), rr, 3 if not police else 4, 0.26)
    rotor(vid + "_rotor_tail", C, body, (0.16, tail_y, tail_z), 0.72, 2, 0.14, axis='X')
    for i, s in enumerate(seats):
        empty(vid + "_seat_%d" % i, C, loc=s, parent=body)
    empty(vid + "_headlight_l", C, loc=(0, st[0][0], st[0][1] - 0.35), parent=body)
    empty(vid + "_exhaust", C, loc=(0, -1.4, st[3][1] + st[3][3] + 0.2), parent=body)
    return body


# ================================================================== AIRPLANES
def wing(mb, root_y, tip_y, span, root_chord, tip_chord, z, dihedral, m, thick=0.12, x0=0.0):
    """Mirrored pair of tapered wings. root leading edge at root_y, tip leading edge at tip_y."""
    for sx in (-1, 1):
        zt = z + span * math.tan(dihedral)
        pts_top = [(sx * x0, root_y, z + thick / 2), (sx * x0, root_y - root_chord, z + thick / 2),
                   (sx * (x0 + span), tip_y - tip_chord, zt + thick / 4), (sx * (x0 + span), tip_y, zt + thick / 4)]
        pts_bot = [(p[0], p[1], p[2] - (thick if abs(p[0]) <= x0 + 0.01 else thick / 2)) for p in pts_top]
        vs = pts_top + pts_bot
        fs = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 3, 7, 4), (1, 5, 6, 2), (3, 2, 6, 7), (0, 4, 5, 1)]
        mb.add(vs, fs, m)


def build_plane(vid, loc, jet=False):
    C = coll("Vehicles/Airplanes")
    wipe([vid + "_", vid])
    mb = MB()
    if not jet:
        st = [(3.55, 1.45, 0.20, 0.22, 'body'), (3.0, 1.45, 0.52, 0.52, 'body'), (2.0, 1.45, 0.62, 0.62, 'glass'),
              (1.1, 1.55, 0.64, 0.72, 'glass'), (-0.2, 1.55, 0.62, 0.70, 'body'), (-2.0, 1.60, 0.36, 0.42, 'body'),
              (-4.3, 1.75, 0.10, 0.16, 'end')]
        tube_loft(mb, st, belly="M_Paint2")
        wing(mb, 1.55, 1.25, 5.2, 1.55, 1.05, 2.22, 0.03, "M_Paint", thick=0.16, x0=0.0)
        for sx in (-1, 1):
            mb.limb((sx * 0.62, 0.9, 1.15), (sx * 2.2, 0.9, 2.20), 0.035, 0.035, "M_Chrome", seg=4)
            mb.box((sx * 5.2, 0.75, 2.42), (0.06, 0.9, 0.10), "M_Paint2")
        wing(mb, -3.5, -3.75, 1.7, 0.9, 0.6, 1.80, 0.0, "M_Paint", thick=0.08)
        mb.prism([(-3.3, 1.8), (-4.35, 1.8), (-4.6, 3.1), (-4.1, 3.1)], 0.08, "M_Paint", plane='YZ')
        mb.box((0, -4.35, 2.95), (0.09, 0.5, 0.3), "M_Paint2")
        mb.cyl((0, 3.72, 1.45), 0.16, 0.36, "M_Chrome", axis='Y', seg=8, r2=0.03)
        seats = [(-0.30, 1.6, 1.22), (0.30, 1.6, 1.22), (-0.30, 0.7, 1.22), (0.30, 0.7, 1.22)]
        gear_f, gear_r, gear_x, wr = 2.75, 0.55, 1.15, 0.26
        prop_pos = (0, 3.80, 1.45)
    else:
        st = [(5.6, 1.55, 0.08, 0.08, 'body'), (4.6, 1.60, 0.42, 0.40, 'glass'), (3.4, 1.72, 0.66, 0.62, 'glass'),
              (2.2, 1.78, 0.74, 0.72, 'body'), (-1.5, 1.80, 0.74, 0.72, 'body'), (-3.6, 1.90, 0.46, 0.48, 'body'),
              (-5.4, 2.05, 0.12, 0.16, 'end')]
        tube_loft(mb, st, belly="M_Paint2")
        wing(mb, 1.4, -1.0, 5.4, 2.6, 0.9, 1.35, 0.06, "M_Paint", thick=0.18, x0=0.3)
        for sx in (-1, 1):
            mb.box((sx * 5.7, -1.5, 1.95), (0.06, 0.8, 0.7), "M_Paint2")
            # rear engines
            mb.cyl((sx * 1.15, -2.9, 2.15), 0.34, 1.9, "M_Paint2", axis='Y', seg=8, cap_m="M_Black")
            mb.box((sx * 0.80, -2.9, 2.1), (0.5, 0.9, 0.10), "M_Paint")
        mb.prism([(-3.6, 2.2), (-5.2, 2.2), (-6.1, 4.2), (-5.2, 4.2)], 0.10, "M_Paint", plane='YZ')
        wing(mb, -5.1, -5.7, 2.2, 1.0, 0.5, 4.15, 0.0, "M_Paint", thick=0.08)
        seats = [(-0.34, 3.7, 1.42), (0.34, 3.7, 1.42), (-0.34, 2.3, 1.42), (0.34, 2.3, 1.42)]
        gear_f, gear_r, gear_x, wr = 4.2, -0.6, 1.5, 0.30
        prop_pos = None
    # interior
    mb.box((0, (seats[0][1] + seats[2][1]) / 2, seats[0][2] - 0.26), (1.0, 2.2, 0.05), "M_Interior")
    for (sx, sy, sz) in seats:
        mb.box((sx, sy - 0.02, sz - 0.12), (0.42, 0.44, 0.14), "M_Seat")
        mb.box((sx, sy - 0.25, sz + 0.20), (0.42, 0.10, 0.56), "M_Seat")
    mb.box((0, seats[0][1] + 0.55, seats[0][2] + 0.10), (0.9, 0.25, 0.35), "M_Interior")
    # gear struts
    mb.limb((0, gear_f, wr), (0, gear_f, st[1][1] - 0.4), 0.04, 0.05, "M_MetalDark", seg=5)
    for sx in (-1, 1):
        mb.limb((sx * gear_x, gear_r, wr), (sx * 0.45, gear_r, 1.1 if not jet else 1.3), 0.045, 0.06, "M_MetalDark", seg=5)
    # lights
    mb.box((0, st[0][0] - 0.5, st[1][1] - 0.5), (0.14, 0.10, 0.08), "M_Headlight")
    body = mb.build(vid, C, loc=loc)
    place_wheel(body, vid + "_wheel_f", "bike", (0, gear_f, wr), wr, 0.12, False, C)
    place_wheel(body, vid + "_wheel_rl", "bike", (-gear_x, gear_r, wr), wr, 0.14, True, C)
    place_wheel(body, vid + "_wheel_rr", "bike", (gear_x, gear_r, wr), wr, 0.14, False, C)
    if prop_pos:
        pm = MB()
        for i in range(3):
            a = 2 * math.pi * i / 3
            pm.push((0, 0, 0), (0, a, 0))
            pm.box((0, 0, 0.55), (0.16, 0.03, 1.1), "M_Black", top=(0.08, 0.03))
            pm.pop()
        pm.cyl((0, 0.05, 0), 0.10, 0.2, "M_Chrome", axis='Y', seg=8, r2=0.02)
        pm.build(vid + "_prop", C, loc=prop_pos, parent=body)
    for i, s in enumerate(seats):
        empty(vid + "_seat_%d" % i, C, loc=s, parent=body)
    empty(vid + "_headlight_l", C, loc=(0, st[0][0], st[0][1] - 0.5), parent=body)
    empty(vid + "_exhaust", C, loc=(0, st[-1][0], st[-1][1]), parent=body)
    return body


out = []
out.append(("motorcycle", tri_count(build_motorcycle((-20, 16, 0)))))
out.append(("bicycle", tri_count(build_bicycle((-17, 16, 0)))))
out.append(("speedboat", tri_count(build_boat("speedboat", (-12, 16, 0.4)))))
out.append(("policeboat", tri_count(build_boat("policeboat", (-7, 16, 0.4), police=True))))
out.append(("heli", tri_count(build_heli("heli", (4, 18, 0)))))
out.append(("heli_police", tri_count(build_heli("heli_police", (16, 18, 0), police=True))))
out.append(("plane", tri_count(build_plane("plane", (30, 18, 0)))))
out.append(("jet", tri_count(build_plane("jet", (46, 18, 0), jet=True))))
print(out)
