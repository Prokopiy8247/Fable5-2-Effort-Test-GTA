# Cars / road vehicles. Run inside Blender via MCP: exec(open(...).read())
from gta_lib import *


def wheel(name, parent, c, loc, r, w):
    b = B()
    b.cyl(r, w, (0, 0, 0), 'Tire', 'x', 12)
    b.cyl(r * 0.62, w + 0.02, (0, 0, 0), 'Rim', 'x', 8)
    b.cyl(r * 0.2, w + 0.05, (0, 0, 0), 'Dark', 'x', 6)
    return b.obj(name, c, parent, loc)


def car(name, L_, W, H, clr, belt, nose, hood, deck, tail, cf, cr, rf, rr, wr, axf, axr,
        extra=None, ww=0.24, cabw=0.9, top=0.84, sgr=None, row=0, sub='vehicles'):
    c = coll('Vehicles/Cars')
    r = root(name, c, slot(row, 7))
    b = B()
    h = L_ / 2
    b.prof([(-h, clr + 0.12), (-h + 0.1, clr), (h - 0.1, clr), (h, clr + 0.12), (h, nose), (h - 0.3, hood),
            (cf, belt), (cr, belt), (-h + 0.25, deck), (-h, tail)], W, 'Paint')
    Wc = W * cabw
    nar = (belt, H, top)
    b.prof([(cf, belt - 0.02), (rf, H - 0.05), (rr, H - 0.05), (cr, belt - 0.02)], Wc, 'Paint', nar=nar)
    b.prof([(rf + 0.04, H - 0.06), (rf - 0.06, H), (rr + 0.06, H), (rr - 0.04, H - 0.06)], Wc + 0.02, 'Paint', nar=nar)
    b.prof([(cf + 0.03, belt + 0.05), (rf + 0.03, H - 0.1), (rf - 0.05, H - 0.1), (cf - 0.05, belt + 0.05)], Wc - 0.12, 'Glass', nar=nar)
    b.prof([(cr - 0.03, belt + 0.05), (cr + 0.05, belt + 0.05), (rr + 0.05, H - 0.1), (rr - 0.03, H - 0.1)], Wc - 0.12, 'Glass', nar=nar)
    s1 = rr + 0.08 if sgr is None else max(rr + 0.08, sgr)
    s0 = cr + 0.22 if sgr is None else max(cr + 0.22, sgr)
    b.prof([(cf - 0.22, belt + 0.05), (rf - 0.08, H - 0.1), (s1, H - 0.1), (s0, belt + 0.05)], Wc + 0.02, 'Glass', nar=nar)
    mid = (rf + s1) / 2
    b.prof([(mid - 0.05, belt), (mid - 0.05, H - 0.05), (mid + 0.05, H - 0.05), (mid + 0.05, belt)], Wc + 0.035, 'Paint', nar=nar)
    b.box((W + 0.04, 0.16, 0.16), (0, h - 0.04, clr + 0.14), 'Dark')
    b.box((W + 0.04, 0.16, 0.16), (0, -h + 0.04, clr + 0.14), 'Dark')
    b.box((W * 0.5, 0.05, 0.13), (0, h, nose - 0.13), 'Dark')
    for sx in (-1, 1):
        b.box((0.32, 0.06, 0.12), (sx * (W / 2 - 0.2), h, nose - 0.09), 'HeadLight')
        b.box((0.32, 0.06, 0.1), (sx * (W / 2 - 0.2), -h, tail - 0.09), 'TailLight')
        b.box((0.1, 0.06, 0.06), (sx * (W / 2 - 0.08), h, nose - 0.2), 'Amber')
        b.box((0.13, 0.07, 0.09), (sx * (Wc / 2 + 0.07), cf - 0.12, belt + 0.07), 'Paint')
        for ay in (axf, axr):
            b.box((0.03, 2 * wr + 0.2, 2 * wr + 0.1 - clr), (sx * W / 2, ay, (clr + 2 * wr + 0.1) / 2), 'Dark')
    b.box((0.42, 0.03, 0.13), (0, -h - 0.005, clr + 0.34), 'Plate')
    b.box((0.42, 0.03, 0.13), (0, h + 0.085, clr + 0.14), 'Plate')
    b.tube((W / 2 - 0.3, -h - 0.06, clr + 0.05), (W / 2 - 0.3, -h + 0.3, clr + 0.05), 0.04, 'Chrome', 6)
    dims = dict(L=L_, W=W, H=H, h=h, clr=clr, belt=belt, nose=nose, hood=hood, deck=deck, tail=tail, cf=cf, cr=cr, rf=rf, rr=rr, Wc=Wc, top=top)
    if extra:
        extra(b, dims)
    b.obj(name + '__body', c, r)
    wx = W / 2 - ww / 2 + 0.04
    wheel(name + '__wheel_fl', r, c, (-wx, axf, wr), wr, ww)
    wheel(name + '__wheel_fr', r, c, (wx, axf, wr), wr, ww)
    wheel(name + '__wheel_rl', r, c, (-wx, axr, wr), wr, ww)
    wheel(name + '__wheel_rr', r, c, (wx, axr, wr), wr, ww)
    # customization parts (hidden by default in Godot, enabled at the mod garage)
    m = B()
    for sx in (-1, 1):
        m.box((0.05, 0.12, 0.24), (sx * W * 0.32, -h + 0.28, deck + 0.1), 'Paint2')
    m.box((W * 0.95, 0.32, 0.04), (0, -h + 0.24, deck + 0.24), 'Paint2')
    m.box((0.04, 0.36, 0.12), (-W * 0.475, -h + 0.24, deck + 0.26), 'Paint2')
    m.box((0.04, 0.36, 0.12), (W * 0.475, -h + 0.24, deck + 0.26), 'Paint2')
    m.obj(name + '__mod_spoiler', c, r)
    m = B()
    for sx in (-1, 1):
        m.box((0.07, axf - axr - 2 * wr - 0.25, 0.1), (sx * (W / 2 + 0.01), (axf + axr) / 2, clr + 0.04), 'Paint2')
    m.obj(name + '__mod_skirts', c, r)
    m = B()
    m.box((W + 0.12, 0.34, 0.05), (0, h - 0.02, clr + 0.02), 'Paint2')
    for sx in (-1, 1):
        m.box((0.05, 0.3, 0.14), (sx * (W / 2 + 0.03), h - 0.05, clr + 0.1), 'Paint2')
    m.obj(name + '__mod_bumper', c, r)
    m = B()
    hy = (h - 0.3 + cf) / 2
    m.box((0.55, min(0.7, (h - 0.3 - cf) * 0.7), 0.1), (0, hy, (hood + belt) / 2 + 0.05), 'Paint2', taper=(0.8, 0.8))
    m.box((0.4, 0.04, 0.05), (0, hy + min(0.7, (h - 0.3 - cf) * 0.7) / 2, (hood + belt) / 2 + 0.05), 'Dark')
    m.obj(name + '__mod_hood', c, r)
    m = B()
    for sx in (-1, 1):
        for dx in (-0.07, 0.07):
            m.tube((sx * (W / 2 - 0.35) + dx, -h - 0.12, clr + 0.07), (sx * (W / 2 - 0.35) + dx, -h + 0.3, clr + 0.07), 0.055, 'Chrome', 8)
    m.obj(name + '__mod_exhaust', c, r)
    m = B()
    m.box((Wc * top * 0.7, (rf - rr) * 0.6, 0.07), (0, (rf + rr) / 2, H + 0.03), 'Paint2', taper=(0.85, 0.8))
    m.obj(name + '__mod_roof', c, r)
    export(r, sub)
    return r


def lightbar(b, d, z=None):
    z = d['H'] + 0.06 if z is None else z
    y = (d['rf'] + d['rr']) / 2 + 0.2
    b.box((1.0, 0.24, 0.05), (0, y, z - 0.02), 'Dark')
    b.box((0.44, 0.22, 0.11), (-0.28, y, z + 0.05), 'SirenRed')
    b.box((0.44, 0.22, 0.11), (0.28, y, z + 0.05), 'SirenBlue')
    b.box((0.1, 0.2, 0.1), (0, y, z + 0.05), 'White')


def x_police(b, d):
    lightbar(b, d)
    b.box((d['W'] + 0.02, 1.9, d['belt'] - d['clr'] - 0.3), (0, -0.3, (d['belt'] + d['clr']) / 2 + 0.08), 'Paint2')
    for sx in (-1, 1):
        b.box((0.06, 0.1, 0.5), (sx * 0.4, d['h'] + 0.1, d['clr'] + 0.3), 'Dark')
    b.box((0.9, 0.06, 0.06), (0, d['h'] + 0.12, d['clr'] + 0.5), 'Dark')
    b.box((0.9, 0.06, 0.06), (0, d['h'] + 0.12, d['clr'] + 0.25), 'Dark')


def x_taxi(b, d):
    y = (d['rf'] + d['rr']) / 2
    b.box((0.55, 0.2, 0.17), (0, y, d['H'] + 0.085), 'SignYellow')
    b.box((d['W'] + 0.02, d['L'] * 0.7, 0.1), (0, 0, d['belt'] - 0.16), 'Paint2')


def x_pickup(b, d):
    y0, y1 = -d['h'] + 0.08, d['cr'] - 0.05
    ym = (y0 + y1) / 2
    for sx in (-1, 1):
        b.box((0.09, y1 - y0, 0.14), (sx * (d['W'] / 2 - 0.045), ym, d['belt'] + 0.07), 'Paint')
    b.box((d['W'], 0.09, 0.14), (0, y0, d['belt'] + 0.07), 'Paint')
    b.box((d['W'] - 0.18, y1 - y0 - 0.05, 0.02), (0, ym + 0.02, d['belt'] + 0.01), 'Dark')
    b.box((0.08, 0.08, 0.5), (-d['Wc'] / 2 + 0.1, d['cr'] - 0.08, d['belt'] + 0.3), 'Dark')
    b.box((0.08, 0.08, 0.5), (d['Wc'] / 2 - 0.1, d['cr'] - 0.08, d['belt'] + 0.3), 'Dark')
    b.box((d['Wc'], 0.07, 0.07), (0, d['cr'] - 0.08, d['belt'] + 0.56), 'Dark')


def x_muscle(b, d):
    for sx in (-0.22, 0.22):
        b.prof([(d['h'] - 0.32, d['hood'] + 0.005), (d['cf'] + 0.02, d['belt'] + 0.005), (d['cf'] + 0.02, d['belt'] + 0.012), (d['h'] - 0.32, d['hood'] + 0.012)], 0.2, 'Paint2', x=sx)


def x_sports(b, d):
    for sx in (-1, 1):
        b.box((0.03, 0.5, 0.16), (sx * d['W'] / 2, -0.55, d['clr'] + 0.32), 'Dark')
    b.box((d['W'] * 0.8, 0.05, 0.08), (0, -d['h'], d['clr'] + 0.16), 'Dark')


def x_suv(b, d):
    for sx in (-1, 1):
        b.box((0.05, (d['rf'] - d['rr']) * 0.85, 0.05), (sx * d['Wc'] * d['top'] * 0.42, (d['rf'] + d['rr']) / 2, d['H'] + 0.04), 'Dark')
    b.cyl(0.36, 0.2, (0, -d['h'] - 0.1, d['belt'] - 0.15), 'Tire', 'y', 10)
    b.cyl(0.2, 0.22, (0, -d['h'] - 0.1, d['belt'] - 0.15), 'Paint', 'y', 8)


def x_van(b, d):
    for sx in (-1, 1):
        b.box((0.02, 0.04, d['belt'] - d['clr'] + 0.5), (sx * (d['W'] / 2 + 0.005), -0.2, (d['belt'] + d['clr']) / 2 + 0.25), 'Dark')
        b.box((0.02, 1.4, 0.04), (sx * (d['W'] / 2 + 0.005), -0.9, d['belt'] - 0.25), 'Dark')


def x_ambulance(b, d):
    lightbar(b, d, d['H'] + 0.06)
    for sx in (-1, 1):
        b.box((0.02, 3.0, 0.22), (sx * (d['W'] / 2 + 0.005), -0.9, d['belt'] - 0.2), 'Red')
        b.box((0.03, 0.6, 0.18), (sx * (d['Wc'] / 2 * 0.93), -1.2, d['belt'] + 0.6), 'Red')
        b.box((0.03, 0.18, 0.6), (sx * (d['Wc'] / 2 * 0.93), -1.2, d['belt'] + 0.6), 'Red')
    b.box((d['W'] * 0.8, 0.03, 0.2), (0, -d['h'] - 0.005, d['belt'] - 0.2), 'Red')


def x_swat(b, d):
    lightbar(b, d, d['H'] + 0.06)
    for sx in (-1, 1):
        b.box((0.12, d['L'] * 0.55, 0.06), (sx * (d['W'] / 2 + 0.06), -0.3, d['clr'] + 0.08), 'Dark')
        b.box((0.04, 0.5, 0.04), (sx * (d['Wc'] / 2 * 0.9), -1.0, d['H'] - 0.25), 'Dark')
    b.box((d['W'] + 0.1, 0.2, 0.5), (0, d['h'] + 0.06, d['clr'] + 0.3), 'Dark')
    b.box((0.6, 0.6, 0.12), (0, -1.0, d['H'] + 0.06), 'Paint2')


def x_truck(b, d):
    y0, y1 = -d['h'] + 0.05, d['cr'] - 0.12
    b.box((d['W'] + 0.1, y1 - y0, 2.3), (0, (y0 + y1) / 2, d['belt'] + 1.0), 'Paint2')
    b.box((d['W'] + 0.12, 0.06, 2.3), (0, y0 - 0.01, d['belt'] + 1.0), 'LightGrey')
    b.box((d['W'] * 0.9, 0.3, 0.5), (0, d['cr'] + 0.0, d['H'] + 0.2), 'Paint', taper=(0.9, 0.6))


def x_fire(b, d):
    lightbar(b, d, d['H'] + 0.06)
    y0, y1 = -d['h'] + 0.05, d['cr'] - 0.1
    b.box((d['W'], y1 - y0, 1.0), (0, (y0 + y1) / 2, d['belt'] + 0.5), 'Paint')
    for sx in (-1, 1):
        b.box((0.02, (y1 - y0) * 0.8, 0.5), (sx * (d['W'] / 2 + 0.005), (y0 + y1) / 2, d['belt'] + 0.45), 'Steel')
        b.box((0.06, y1 - y0 + 0.8, 0.06), (sx * 0.28, (y0 + y1) / 2 + 0.3, d['belt'] + 1.16), 'Steel')
    n = int((y1 - y0 + 0.8) / 0.4)
    for i in range(n):
        b.box((0.56, 0.05, 0.05), (0, y0 - 0.3 + 0.2 + i * 0.4 + 0.3, d['belt'] + 1.16), 'Steel')
    b.box((d['W'] + 0.02, d['L'] * 0.9, 0.1), (0, 0, d['clr'] + 0.45), 'White')
    b.cyl(0.14, 0.5, (d['W'] / 2 - 0.3, y0 + 0.4, d['belt'] + 1.1), 'Chrome', 'y', 8)


#    name            L     W     H     clr   belt  nose  hood  deck  tail  cf    cr     rf     rr     wr    axf   axr
car('car_compact', 3.7, 1.66, 1.5, 0.22, 0.95, 0.75, 0.86, 0.95, 0.9, 0.8, -1.62, 0.32, -1.38, 0.3, 1.15, -1.15)
car('car_sedan', 4.6, 1.8, 1.42, 0.22, 0.92, 0.7, 0.82, 0.9, 0.85, 0.85, -1.5, 0.28, -0.85, 0.33, 1.42, -1.35)
car('car_sports', 4.4, 1.92, 1.14, 0.14, 0.74, 0.5, 0.64, 0.78, 0.72, 0.5, -1.8, -0.15, -0.75, 0.34, 1.42, -1.32, extra=x_sports, ww=0.3, top=0.78)
car('car_muscle', 4.95, 1.92, 1.32, 0.2, 0.9, 0.76, 0.87, 0.88, 0.8, 0.3, -1.75, -0.18, -1.0, 0.36, 1.6, -1.42, extra=x_muscle, ww=0.3)
car('car_suv', 4.7, 1.95, 1.82, 0.32, 1.1, 0.9, 1.02, 1.1, 1.05, 0.9, -2.27, 0.48, -2.12, 0.4, 1.47, -1.42, extra=x_suv, ww=0.28, top=0.88)
car('car_pickup', 5.3, 1.96, 1.82, 0.34, 1.1, 0.92, 1.04, 1.1, 1.1, 1.05, -0.5, 0.65, -0.38, 0.42, 1.72, -1.62, extra=x_pickup, ww=0.28, top=0.88)
car('car_van', 5.0, 1.95, 2.1, 0.26, 1.15, 0.85, 1.02, 1.15, 1.15, 2.05, -2.45, 1.62, -2.4, 0.36, 1.6, -1.5, extra=x_van, top=0.92, sgr=0.75)
car('car_police', 4.7, 1.84, 1.44, 0.22, 0.93, 0.72, 0.84, 0.9, 0.86, 0.85, -1.5, 0.28, -0.85, 0.34, 1.45, -1.38, extra=x_police)
car('car_taxi', 4.6, 1.8, 1.44, 0.22, 0.92, 0.7, 0.82, 0.9, 0.85, 0.85, -1.5, 0.28, -0.9, 0.33, 1.42, -1.35, extra=x_taxi)
car('car_ambulance', 5.8, 2.1, 2.55, 0.3, 1.2, 0.9, 1.08, 1.2, 1.2, 2.4, -2.85, 2.0, -2.8, 0.4, 1.9, -1.8, extra=x_ambulance, top=0.95, sgr=1.2, row=1)
car('car_swat', 5.6, 2.2, 2.4, 0.4, 1.35, 1.1, 1.25, 1.35, 1.35, 1.7, -2.75, 1.45, -2.7, 0.48, 1.8, -1.7, extra=x_swat, ww=0.34, top=0.9, sgr=0.6, row=1)
car('car_truck', 7.0, 2.3, 2.5, 0.45, 1.3, 1.0, 1.2, 1.0, 1.0, 3.45, 2.0, 3.15, 2.1, 0.5, 2.6, -2.2, extra=x_truck, ww=0.34, top=0.92, row=1)
car('car_firetruck', 7.6, 2.4, 2.7, 0.45, 1.35, 1.0, 1.25, 1.05, 1.05, 3.75, 1.7, 3.45, 1.8, 0.52, 2.8, -2.5, extra=x_fire, ww=0.36, top=0.94, row=1)
print('cars done')
