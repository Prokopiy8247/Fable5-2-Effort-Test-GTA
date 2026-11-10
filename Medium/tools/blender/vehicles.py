# Vehicle authoring script (run inside Blender via MCP after gta_lib.py).
import math

CARS = coll('Vehicles/Cars')
WHEELC = coll('Vehicles/Wheels')


def tube(b, m, p0, p1, r, seg=6):
    p0 = Vector(p0)
    p1 = Vector(p1)
    d = (p1 - p0).normalized()
    u = d.cross(Vector((0, 0, 1)))
    if u.length < 0.01:
        u = d.cross(Vector((1, 0, 0)))
    u.normalize()
    v = d.cross(u)
    rings = []
    for p in (p0, p1):
        rings.append([tuple(p + r * (math.cos(2 * math.pi * i / seg) * u + math.sin(2 * math.pi * i / seg) * v))
                      for i in range(seg)])
    b.loft(m, rings)


def oval(y, hw, zc, hh, n=8, flat=0.0):
    pts = []
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        z = zc + math.sin(a) * hh
        if flat and math.sin(a) < 0:
            z = zc + math.sin(a) * hh * (1 - flat)
        pts.append((math.cos(a) * hw, y, z))
    return pts


def ring(y, hw, zb, zt, ch=0.07):
    return [(-hw, y, zb + ch), (-hw, y, zt - ch), (-hw + ch, y, zt), (hw - ch, y, zt), (hw, y, zt - ch),
            (hw, y, zb + ch), (hw - ch, y, zb), (-hw + ch, y, zb)]


# ---------------- wheels (unit: radius 0.5, width 0.3, axis X) ----------------
def make_wheels():
    r = root('wheels', WHEELC, (-8, -8, 0))
    styles = {'std': 5, 'sport': 10, 'offroad': 6, 'classic': 4, 'bike': 3}
    k = 0
    for st, spokes in styles.items():
        b = B()
        w = 0.15
        rim_r = {'std': 0.33, 'sport': 0.38, 'offroad': 0.29, 'classic': 0.31, 'bike': 0.4}[st]
        prof = [(-w, rim_r), (-w, 0.45), (-w * 0.7, 0.5), (w * 0.7, 0.5), (w, 0.45), (w, rim_r)]
        seg = 16
        rings = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rings.append([(x, math.cos(a) * rr, math.sin(a) * rr) for x, rr in prof])
        rings.append(rings[0])
        b.loft('Tire', rings, cap=False)
        if st == 'offroad':
            for i in range(12):
                a = 2 * math.pi * i / 12
                b.box('Tire', (0, math.cos(a) * 0.5, math.sin(a) * 0.5), (0.3, 0.07, 0.05), rot=(a - math.pi / 2, 0, 0))
        b.cyl('Rim', (0, 0, 0), rim_r, 0.2, axis='X', seg=seg)
        b.cyl('Dark', (0, 0, 0), rim_r * 0.9, 0.24, axis='X', seg=seg)
        b.cyl('Rim', (0, 0, 0), 0.09, 0.3, axis='X', seg=8)
        for i in range(spokes):
            a = 2 * math.pi * i / spokes
            rr = rim_r * 0.5
            wd = {'std': 0.09, 'sport': 0.035, 'offroad': 0.12, 'classic': 0.13, 'bike': 0.05}[st]
            b.box('Rim', (0, math.cos(a) * rr, math.sin(a) * rr), (0.27, rim_r * 0.95, wd), rot=(a, 0, 0))
        o = b.obj('Wheel_' + st, WHEELC, r, loc=(k * 1.3, 0, 0.5))
        k += 1
    export('wheels', 'vehicles')


def add_wheels(r, name, C, axles, track, wr, ww, style='std'):
    me = bpy.data.objects['Wheel_' + style].data
    out = []
    names = ['FL', 'FR', 'RL', 'RR']
    i = 0
    for ay in (axles[1], axles[0]):
        for sx in (-1, 1):
            o = bpy.data.objects.new('%s_Wheel_%s' % (name, names[i]), me)
            C.objects.link(o)
            o.parent = r
            o.location = (sx * track, ay, wr)
            o.scale = (ww / 0.3, wr / 0.5, wr / 0.5)
            out.append(g((sx * track, ay, wr)))
            i += 1
    return out


def slant(t, m, y0, z0, y1, z1, width, x=0.0, th=0.04, k=0.84):
    ang = math.atan2(z1 - z0, y1 - y0)
    ln = math.hypot(z1 - z0, y1 - y0)
    t.box(m, (x, (y0 + y1) / 2, (z0 + z1) / 2), (width, ln * k, th), rot=(ang, 0, 0))


def car(name, place, secs, cab, axles, track, wr, ww=0.24, wheel='std', cuts=(), kind='car', C=None, mods=True,
        paint='Paint', seat=None, open_=False):
    C = C or CARS
    r = root(name, C, place)
    b = B()
    b.loft(paint, [ring(*s) for s in secs])
    body = b.obj(name + '_Body', C, r)
    W = max(s[1] for s in secs)
    cut = B()
    for ay in axles:
        cut.cyl('Dark', (0, ay, wr), wr + 0.08, 2 * W + 0.4, axis='X', seg=14)
    for c, sz in cuts:
        cut.box('Dark', c, sz)
    boolean_cut(body, cut, C)
    if 'Dark' not in [m.name for m in body.data.materials]:
        body.data.materials.append(mat('Dark'))
    yr, yf = secs[0][0], secs[-1][0]
    zb = min(s[2] for s in secs)
    t = B()
    t.box('Dark', (0, (yr + yf) / 2, zb + 0.2), (2 * (track - ww / 2 - 0.05), (yf - yr) * 0.93, 0.36))
    if cab:
        yb0, yt0, yt1, yb1, z0, zt, hwb, hwt = cab
        t.loft('Glass', [[(-hwb, yb0, z0), (hwb, yb0, z0), (hwt, yt0, zt), (-hwt, yt0, zt)],
                         [(-hwb, yb1, z0), (hwb, yb1, z0), (hwt, yt1, zt), (-hwt, yt1, zt)]])
        t.box(paint, (0, (yt0 + yt1) / 2, zt + 0.01), (2 * hwt + 0.05, yt1 - yt0 + 0.1, 0.05))
        ang = math.atan2(hwb - hwt, zt - z0)
        ym = (yt0 + yt1) / 2 - 0.1
        for sx in (-1, 1):
            t.box(paint, (sx * ((hwb + hwt) / 2 + 0.006), ym, (z0 + zt) / 2), (0.04, 0.12, (zt - z0) / math.cos(ang)),
                  rot=(0, -sx * ang, 0))
            t.box(paint, (sx * (hwb + 0.1), yb1 - 0.12, z0 + 0.08), (0.18, 0.08, 0.1))
    hwf, hwr = secs[-1][1], secs[0][1]
    zft, zrt = secs[-1][3], secs[0][3]
    for sx in (-1, 1):
        t.box('LightHead', (sx * (hwf - 0.2), yf + 0.005, zft - 0.13), (0.3, 0.06, 0.12))
        t.box('LightTail', (sx * (hwr - 0.2), yr - 0.005, zrt - 0.13), (0.3, 0.06, 0.1))
        t.box('LightRev', (sx * (hwr - 0.42), yr - 0.005, zrt - 0.13), (0.1, 0.06, 0.08))
        t.box('Chrome', (sx * (W + 0.005), ((yr + yf) / 2) - 0.25 + 0.0, secs[len(secs) // 2][3] - 0.2), (0.03, 0.14, 0.03))
    t.box('Dark', (0, yf + 0.01, zft - 0.14), (max(0.2, 2 * hwf - 1.0), 0.05, 0.12))
    t.box('Dark', (0, yf + 0.03, secs[-1][2] + 0.09), (2 * hwf + 0.06, 0.16, 0.17))
    t.box('Dark', (0, yr - 0.03, secs[0][2] + 0.09), (2 * hwr + 0.06, 0.16, 0.17))
    t.box('Plate', (0, yr - 0.115, secs[0][2] + 0.1), (0.42, 0.02, 0.12))
    t.box('Plate', (0, yf + 0.115, secs[-1][2] + 0.1), (0.42, 0.02, 0.12))
    t.cyl('Chrome', (hwr - 0.3, yr - 0.08, zb + 0.06), 0.045, 0.25, axis='Y', seg=8)
    wl = add_wheels(r, name, C, axles, track, wr, ww, wheel)
    if seat is None and cab:
        seat = (-0.38, (cab[1] + cab[2]) / 2 + 0.25, cab[4] - 0.35)
    extra = {'wheels': wl, 'wr': wr, 'ww': ww, 'kind': kind, 'open': open_}
    if seat:
        extra['seat'] = g(seat)
    return r, t, C, extra


def finish(name, r, t, C, extra, subdir='vehicles'):
    t.obj(name + '_Top', C, r)
    register(name, **extra)


def mods(name, r, C, secs, cab, hood_y=None):
    """Blender-authored modular customisation parts (hidden by default in Godot)."""
    yr, yf = secs[0][0], secs[-1][0]
    hwr = secs[1][1]
    zr = secs[1][3]
    W = max(s[1] for s in secs)
    zb = min(s[2] for s in secs)
    b = B()
    b.box('Paint2', (0, yr + 0.3, zr + 0.06), (2 * hwr - 0.1, 0.3, 0.05), rot=(-0.12, 0, 0))
    b.obj(name + '_Mod_Spoiler1', C, r)
    b = B()
    b.box('Paint2', (0, yr + 0.22, zr + 0.3), (2 * hwr + 0.05, 0.34, 0.04), rot=(-0.14, 0, 0))
    for sx in (-1, 1):
        b.box('Dark', (sx * (hwr - 0.3), yr + 0.26, zr + 0.15), (0.05, 0.16, 0.3))
        b.box('Paint2', (sx * (hwr + 0.02), yr + 0.22, zr + 0.3), (0.04, 0.4, 0.16))
    b.obj(name + '_Mod_Spoiler2', C, r)
    b = B()
    for sx in (-1, 1):
        b.box('Paint2', (sx * (W + 0.01), (yr + yf) / 2, zb + 0.05), (0.08, (yf - yr) * 0.42, 0.1), top=(0.4, 1))
    b.obj(name + '_Mod_Skirts', C, r)
    hy = hood_y if hood_y is not None else ((cab[3] + yf) / 2 if cab else yf - 0.8)
    hz = max(s[3] for s in secs if s[0] > hy - 0.3) if any(s[0] > hy - 0.3 for s in secs) else zr
    b = B()
    b.box('Paint2', (0, hy, hz + 0.03), (0.5, 0.7, 0.12), top=(0.8, 0.8), shift=(0, -0.05))
    b.box('Dark', (0, hy + 0.34, hz + 0.04), (0.38, 0.03, 0.07))
    b.obj(name + '_Mod_Scoop', C, r)
    b = B()
    zf = secs[-1][2]
    for sx in (-1, 1):
        tube(b, 'Chrome', (sx * 0.45, yf + 0.16, zf), (sx * 0.45, yf + 0.16, zf + 0.5), 0.035)
    tube(b, 'Chrome', (-0.6, yf + 0.16, zf + 0.5), (0.6, yf + 0.16, zf + 0.5), 0.035)
    tube(b, 'Chrome', (-0.6, yf + 0.16, zf + 0.25), (0.6, yf + 0.16, zf + 0.25), 0.035)
    b.obj(name + '_Mod_Bullbar', C, r)
    b = B()
    for sx in (-1, 1):
        b.cyl('Chrome', (sx * (hwr - 0.32), yr - 0.1, zb + 0.07), 0.07, 0.34, axis='Y', seg=8)
        b.cyl('Dark', (sx * (hwr - 0.32), yr - 0.275, zb + 0.07), 0.055, 0.01, axis='Y', seg=8)
    b.obj(name + '_Mod_Exhaust', C, r)


def lightbar(name, r, C, y, z, w=1.1):
    b = B()
    b.box('Dark', (0, y, z + 0.03), (w, 0.26, 0.05))
    b.box('LightRed', (-w * 0.28, y, z + 0.1), (w * 0.42, 0.22, 0.1))
    b.box('LightBlue', (w * 0.28, y, z + 0.1), (w * 0.42, 0.22, 0.1))
    b.box('White', (0, y, z + 0.1), (w * 0.12, 0.22, 0.1))
    b.obj(name + '_Lightbar', C, r)


def side_text(name, r, C, s, size, x, y, z, m='Black'):
    text(name + '_TxtR', s, size, C, r, (x, y, z), m, rot=(math.pi / 2, 0, math.pi / 2), extrude=0.008)
    text(name + '_TxtL', s, size, C, r, (-x, y, z), m, rot=(math.pi / 2, 0, -math.pi / 2), extrude=0.008)


SEDAN = [(-2.3, 0.78, 0.38, 0.74), (-2.15, 0.88, 0.30, 0.88), (-1.2, 0.9, 0.28, 0.9), (0.9, 0.9, 0.28, 0.9),
         (2.0, 0.88, 0.30, 0.78), (2.3, 0.76, 0.38, 0.66)]
SEDAN_CAB = (-1.6, -0.95, 0.35, 1.1, 0.88, 1.42, 0.85, 0.68)


def build_cars():
    x = 0
    # sedan
    r, t, C, e = car('sedan', (x, 0, 0), SEDAN, SEDAN_CAB, (-1.4, 1.4), 0.8, 0.33)
    finish('sedan', r, t, C, e); mods('sedan', r, C, SEDAN, SEDAN_CAB)
    # compact hatchback
    x += 4
    s = [(-1.85, 0.72, 0.36, 0.82), (-1.75, 0.82, 0.28, 1.0), (-0.6, 0.84, 0.26, 0.95), (0.8, 0.84, 0.26, 0.88),
         (1.65, 0.8, 0.28, 0.78), (1.85, 0.7, 0.36, 0.66)]
    c = (-1.78, -1.4, 0.1, 0.85, 0.9, 1.5, 0.8, 0.66)
    r, t, C, e = car('compact', (x, 0, 0), s, c, (-1.2, 1.2), 0.74, 0.3, ww=0.2)
    finish('compact', r, t, C, e); mods('compact', r, C, s, c)
    # sports
    x += 4
    s = [(-2.2, 0.8, 0.32, 0.74), (-2.05, 0.96, 0.24, 0.86), (-0.9, 0.98, 0.2, 0.84), (0.6, 0.96, 0.2, 0.7),
         (1.9, 0.9, 0.22, 0.56), (2.2, 0.74, 0.28, 0.46)]
    c = (-1.55, -0.7, 0.0, 0.9, 0.76, 1.14, 0.86, 0.6)
    r, t, C, e = car('sports', (x, 0, 0), s, c, (-1.35, 1.4), 0.86, 0.34, ww=0.3, wheel='sport')
    for sx in (-1, 1):
        t.box('Dark', (sx * 0.98, -0.75, 0.55), (0.04, 0.5, 0.16), top=(1, 0.6))
    finish('sports', r, t, C, e); mods('sports', r, C, s, c)
    # muscle
    x += 4
    s = [(-2.45, 0.82, 0.4, 0.84), (-2.3, 0.93, 0.3, 0.92), (-1.0, 0.95, 0.28, 0.94), (0.4, 0.95, 0.28, 0.92),
         (2.2, 0.93, 0.3, 0.86), (2.45, 0.84, 0.4, 0.72)]
    c = (-1.75, -1.0, -0.1, 0.5, 0.92, 1.34, 0.88, 0.7)
    r, t, C, e = car('muscle', (x, 0, 0), s, c, (-1.5, 1.55), 0.84, 0.36, ww=0.3, wheel='classic')
    for sx in (-1, 1):
        slant(t, 'Paint2', 0.5, 0.925, 2.2, 0.865, 0.2, x=sx * 0.2, th=0.012, k=0.98)
        t.box('Paint2', (sx * 0.2, -0.55, 1.378), (0.2, 0.98, 0.012))
        slant(t, 'Paint2', -2.3, 0.925, -1.75, 0.94, 0.2, x=sx * 0.2, th=0.012, k=0.98)
    finish('muscle', r, t, C, e); mods('muscle', r, C, s, c)
    # SUV
    x += 4
    s = [(-2.4, 0.84, 0.5, 1.0), (-2.3, 0.96, 0.42, 1.12), (-0.5, 0.97, 0.4, 1.1), (1.0, 0.97, 0.4, 1.06),
         (2.15, 0.94, 0.42, 0.98), (2.4, 0.84, 0.5, 0.84)]
    c = (-2.3, -2.05, 0.2, 1.0, 1.08, 1.8, 0.92, 0.8)
    r, t, C, e = car('suv', (x, 0, 0), s, c, (-1.5, 1.5), 0.84, 0.4, ww=0.28, wheel='offroad')
    for sx in (-1, 1):
        t.box('Dark', (sx * 0.62, -0.9, 1.86), (0.05, 1.9, 0.05))
        t.box('Dark', (sx * 0.985, 0, 0.5), (0.04, 2.0, 0.16))
    finish('suv', r, t, C, e); mods('suv', r, C, s, c)
    # pickup
    x += 4
    s = [(-2.65, 0.86, 0.5, 0.98), (-2.55, 0.96, 0.44, 1.06), (-0.3, 0.97, 0.42, 1.08), (1.2, 0.97, 0.42, 1.06),
         (2.4, 0.94, 0.44, 0.98), (2.65, 0.84, 0.5, 0.84)]
    c = (-0.6, -0.42, 0.62, 1.32, 1.06, 1.78, 0.92, 0.8)
    r, t, C, e = car('pickup', (x, 0, 0), s, c, (-1.65, 1.7), 0.84, 0.4, ww=0.28, wheel='offroad',
                     cuts=[((0, -1.58, 1.0), (1.66, 1.8, 0.5))])
    t.box('Dark', (0, -1.58, 0.77), (1.64, 1.78, 0.04))
    t.box('Chrome', (0, -0.68, 1.5), (1.5, 0.06, 0.06))
    for sx in (-1, 1):
        t.box('Chrome', (sx * 0.72, -0.68, 1.3), (0.06, 0.06, 0.45))
    finish('pickup', r, t, C, e); mods('pickup', r, C, s, c)
    # van
    x += 4
    s = [(-2.5, 0.9, 0.44, 1.9), (-2.44, 0.97, 0.36, 2.0), (1.15, 0.97, 0.36, 2.0), (2.15, 0.96, 0.36, 1.08),
         (2.5, 0.86, 0.44, 0.86)]
    r, t, C, e = car('van', (x, 0, 0), s, None, (-1.5, 1.55), 0.84, 0.36, wheel='std', seat=(-0.4, 0.9, 1.0))
    slant(t, 'Glass', 1.15, 2.0, 2.15, 1.08, 1.7, th=0.05)
    for sx in (-1, 1):
        t.box('Glass', (sx * 0.975, 0.62, 1.52), (0.04, 0.8, 0.5))
        t.box('Dark', (sx * 0.975, -0.9, 1.1), (0.03, 0.03, 1.3))
        t.box('Glass', (sx * 0.45, -2.5, 1.5), (0.6, 0.04, 0.45))
        t.box('Paint2', (sx * 0.978, -0.6, 0.75), (0.02, 3.4, 0.14))
    finish('van', r, t, C, e); mods('van', r, C, s, None, hood_y=1.9)
    # police cruiser
    x += 4
    r, t, C, e = car('police', (x, 0, 0), SEDAN, SEDAN_CAB, (-1.4, 1.4), 0.8, 0.33, wheel='classic')
    for sx in (-1, 1):
        t.box('White', (sx * 0.905, -0.25, 0.6), (0.02, 1.95, 0.5))
        tube(t, 'Dark', (sx * 0.45, 2.42, 0.3), (sx * 0.45, 2.42, 0.78), 0.035)
    tube(t, 'Dark', (-0.6, 2.42, 0.78), (0.6, 2.42, 0.78), 0.035)
    tube(t, 'Dark', (-0.6, 2.42, 0.52), (0.6, 2.42, 0.52), 0.035)
    finish('police', r, t, C, e)
    lightbar('police', r, C, -0.3, 1.45)
    side_text('police', r, C, 'POLICE', 0.26, 0.918, -0.25, 0.6, 'Black')
    # taxi
    x += 4
    r, t, C, e = car('taxi', (x, 0, 0), SEDAN, SEDAN_CAB, (-1.4, 1.4), 0.8, 0.33)
    t.box('LightAmber', (0, -0.3, 1.52), (0.5, 0.2, 0.16), top=(0.8, 0.8))
    for sx in (-1, 1):
        for i in range(8):
            t.box('Black' if i % 2 == 0 else 'White', (sx * 0.905, -1.15 + i * 0.25, 0.8), (0.02, 0.25, 0.1))
    finish('taxi', r, t, C, e)
    side_text('taxi', r, C, 'TAXI', 0.26, 0.908, -0.25, 0.55, 'Black')
    # ambulance
    x += 4.5
    s = [(-3.0, 1.04, 0.5, 2.5), (-2.94, 1.1, 0.45, 2.56), (0.9, 1.1, 0.45, 2.56), (0.96, 0.98, 0.42, 2.02),
         (1.65, 0.98, 0.42, 2.02), (2.5, 0.96, 0.42, 1.12), (2.8, 0.88, 0.5, 0.92)]
    r, t, C, e = car('ambulance', (x, 0, 0), s, None, (-1.7, 1.8), 0.9, 0.4, ww=0.28, seat=(-0.4, 1.4, 1.0))
    slant(t, 'Glass', 1.65, 2.02, 2.5, 1.12, 1.74, th=0.05)
    for sx in (-1, 1):
        t.box('Glass', (sx * 0.985, 1.3, 1.6), (0.04, 0.6, 0.48))
        t.box('Red', (sx * 1.105, -1.0, 1.2), (0.02, 3.8, 0.22))
        t.box('Red', (sx * 1.105, -1.0, 1.9), (0.02, 0.6, 0.18))
        t.box('Red', (sx * 1.105, -1.0, 1.9), (0.02, 0.18, 0.6))
        t.box('LightAmber', (sx * 0.9, -3.0, 2.4), (0.2, 0.05, 0.1))
    t.box('Glass', (0, -3.0, 1.75), (1.2, 0.04, 0.5))
    finish('ambulance', r, t, C, e)
    lightbar('ambulance', r, C, 1.3, 2.04, 1.5)
    side_text('ambulance', r, C, 'AMBULANCE', 0.24, 1.118, -1.0, 0.8, 'Red')
    # box truck
    x += 5
    s = [(-3.5, 1.1, 0.7, 3.0), (-3.44, 1.16, 0.64, 3.06), (1.3, 1.16, 0.64, 3.06), (1.36, 1.08, 0.5, 2.3),
         (2.3, 1.08, 0.5, 2.3), (3.15, 1.06, 0.5, 1.3), (3.4, 0.98, 0.58, 1.0)]
    r, t, C, e = car('truck', (x, 0, 0), s, None, (-2.2, 2.3), 0.98, 0.48, ww=0.34, wheel='offroad', kind='truck',
                     seat=(-0.45, 1.9, 1.3))
    slant(t, 'Glass', 2.3, 2.3, 3.15, 1.3, 1.9, th=0.05)
    for sx in (-1, 1):
        t.box('Glass', (sx * 1.085, 1.85, 1.85), (0.04, 0.7, 0.5))
        t.box('Paint2', (sx * 1.165, -1.05, 1.9), (0.02, 4.4, 1.0))
        t.box('Dark', (sx * 1.0, -0.2, 0.55), (0.3, 1.2, 0.3))
    t.box('Steel', (0, -3.5, 1.8), (2.0, 0.05, 2.2))
    finish('truck', r, t, C, e)
    # fire truck
    x += 5
    s = [(-3.8, 1.12, 0.7, 2.2), (-3.74, 1.18, 0.64, 2.3), (1.6, 1.18, 0.64, 2.3), (1.66, 1.18, 0.55, 2.5),
         (3.1, 1.18, 0.55, 2.5), (3.6, 1.16, 0.55, 1.5), (3.8, 1.1, 0.62, 1.1)]
    r, t, C, e = car('firetruck', (x, 0, 0), s, None, (-2.4, 2.5), 1.0, 0.5, ww=0.36, wheel='offroad', kind='truck',
                     seat=(-0.5, 2.5, 1.4))
    slant(t, 'Glass', 3.1, 2.5, 3.6, 1.5, 2.1, th=0.05)
    for sx in (-1, 1):
        t.box('Glass', (sx * 1.185, 2.55, 1.95), (0.04, 0.8, 0.55))
        t.box('Glass', (sx * 1.185, 1.95, 1.95), (0.04, 0.3, 0.55))
        t.box('White', (sx * 1.185, -1.0, 1.05), (0.02, 5.2, 0.16))
        for k in range(3):
            t.box('Steel', (sx * 1.185, -3.0 + k * 1.5, 1.6), (0.03, 1.2, 0.8))
        tube(t, 'Steel', (sx * 0.3, -3.7, 2.42), (sx * 0.3, 1.6, 2.42), 0.04)
    for k in range(14):
        t.box('Steel', (0, -3.6 + k * 0.4, 2.42), (0.6, 0.05, 0.05))
    t.cyl('Yellow', (0.7, -0.5, 2.45), 0.22, 0.4, axis='X', seg=10)
    t.cyl('Yellow', (-0.7, -0.5, 2.45), 0.22, 0.4, axis='X', seg=10)
    t.box('Chrome', (0, 3.88, 0.8), (2.3, 0.14, 0.3))
    finish('firetruck', r, t, C, e)
    lightbar('firetruck', r, C, 2.5, 2.52, 1.8)
    # armored tactical van
    x += 5
    s = [(-2.8, 1.0, 0.6, 2.0), (-2.6, 1.1, 0.5, 2.2), (0.9, 1.1, 0.5, 2.2), (1.7, 1.08, 0.5, 2.05), (2.3, 1.06, 0.5, 1.3),
         (2.8, 1.0, 0.6, 1.1)]
    r, t, C, e = car('swat', (x, 0, 0), s, None, (-1.7, 1.75), 0.92, 0.46, ww=0.34, wheel='offroad', kind='truck',
                     seat=(-0.45, 1.2, 1.2))
    slant(t, 'Glass', 1.7, 2.05, 2.3, 1.3, 1.7, th=0.06, k=0.6)
    for sx in (-1, 1):
        t.box('Glass', (sx * 1.1, 1.2, 1.75), (0.04, 0.5, 0.3))
        for k in range(3):
            t.box('Glass', (sx * 1.105, -2.0 + k * 0.9, 1.75), (0.03, 0.4, 0.16))
        t.box('Dark', (sx * 1.13, -0.4, 0.62), (0.2, 3.4, 0.08))
        tube(t, 'Dark', (sx * 0.5, 2.95, 0.5), (sx * 0.5, 2.95, 1.25), 0.05)
    tube(t, 'Dark', (-0.75, 2.95, 1.25), (0.75, 2.95, 1.25), 0.05)
    tube(t, 'Dark', (-0.75, 2.95, 0.85), (0.75, 2.95, 0.85), 0.05)
    t.cyl('Dark', (0, -0.6, 2.24), 0.4, 0.1, seg=10)
    finish('swat', r, t, C, e)
    lightbar('swat', r, C, 1.2, 2.2, 1.2)
    side_text('swat', r, C, 'TACTICAL', 0.3, 1.108, -0.6, 1.2, 'White')


def build_bikes():
    C = coll('Vehicles/Motorcycles')
    # motorcycle
    name = 'motorcycle'
    r = root(name, C, (0, 8, 0))
    b = B()
    wr = 0.31
    b.box('Gunmetal', (0, 0.0, 0.44), (0.3, 0.52, 0.34))
    b.cyl('Steel', (0, 0.05, 0.6), 0.13, 0.36, axis='X', seg=8)
    b.box('Paint', (0, 0.2, 0.84), (0.34, 0.6, 0.24), top=(0.7, 0.8), shift=(0, -0.03))
    b.box('Seat', (0, -0.38, 0.8), (0.3, 0.62, 0.1))
    b.box('Paint', (0, -0.72, 0.74), (0.2, 0.4, 0.07), rot=(0.25, 0, 0))
    b.box('LightTail', (0, -0.93, 0.78), (0.12, 0.04, 0.05))
    for sx in (-1, 1):
        tube(b, 'Chrome', (sx * 0.1, 0.74, wr), (sx * 0.1, 0.42, 1.04), 0.028)
        tube(b, 'Dark', (sx * 0.09, -0.1, 0.4), (sx * 0.09, -0.74, wr), 0.03)
        b.box('Dark', (sx * 0.2, -0.2, 0.36), (0.1, 0.1, 0.03))
    tube(b, 'Dark', (-0.34, 0.38, 1.08), (0.34, 0.38, 1.08), 0.02)
    b.cyl('Dark', (0, 0.56, 0.95), 0.1, 0.12, axis='Y', seg=8)
    b.cyl('LightHead', (0, 0.63, 0.95), 0.085, 0.02, axis='Y', seg=8)
    b.box('Paint', (0, 0.74, wr + 0.36), (0.16, 0.45, 0.04), rot=(-0.2, 0, 0))
    tube(b, 'Chrome', (0.17, 0.1, 0.34), (0.17, -0.85, 0.42), 0.045)
    b.obj(name + '_Body', C, r)
    me = bpy.data.objects['Wheel_bike'].data
    for nm, y in (('F', 0.74), ('R', -0.74)):
        o = bpy.data.objects.new('%s_Wheel_%s' % (name, nm), me)
        C.objects.link(o); o.parent = r; o.location = (0, y, wr); o.scale = (0.14 / 0.3, wr / 0.5, wr / 0.5)
    register(name, wheels=[g((-0.12, 0.74, wr)), g((0.12, 0.74, wr)), g((-0.12, -0.74, wr)), g((0.12, -0.74, wr))],
             wr=wr, ww=0.14, kind='bike', open=True, seat=g((0, -0.3, 0.86)))
    # bicycle
    name = 'bicycle'
    r = root(name, C, (2.5, 8, 0))
    b = B()
    wr = 0.34
    A = (0, 0.52, wr); Bk = (0, -0.52, wr); bb = (0, -0.05, 0.3); st = (0, -0.22, 0.9); hd = (0, 0.36, 0.92)
    for p0, p1 in ((bb, st), (bb, hd), (st, hd), (st, Bk), (bb, Bk), (hd, A)):
        tube(b, 'Paint', p0, p1, 0.022)
    b.box('Seat', (0, -0.26, 0.96), (0.14, 0.26, 0.05))
    tube(b, 'Dark', (0, 0.36, 0.92), (0, 0.33, 1.06), 0.018)
    tube(b, 'Dark', (-0.27, 0.33, 1.06), (0.27, 0.33, 1.06), 0.016)
    b.cyl('Steel', bb, 0.09, 0.02, axis='X', seg=10)
    tube(b, 'Dark', (0.09, -0.05, 0.3), (0.09, 0.08, 0.16), 0.014)
    tube(b, 'Dark', (-0.09, -0.05, 0.3), (-0.09, -0.18, 0.44), 0.014)
    b.obj(name + '_Body', C, r)
    for nm, y in (('F', 0.52), ('R', -0.52)):
        o = bpy.data.objects.new('%s_Wheel_%s' % (name, nm), me)
        C.objects.link(o); o.parent = r; o.location = (0, y, wr); o.scale = (0.05 / 0.3, wr / 0.5, wr / 0.5)
    register(name, wheels=[g((-0.1, 0.52, wr)), g((0.1, 0.52, wr)), g((-0.1, -0.52, wr)), g((0.1, -0.52, wr))],
             wr=wr, ww=0.05, kind='bike', open=True, seat=g((0, -0.24, 1.0)))


def build_boats():
    C = coll('Vehicles/Boats')
    name = 'speedboat'
    r = root(name, C, (6, 8, 0))
    b = B()
    secs = [(-2.9, 1.05, -0.3, 0.55), (-1.0, 1.15, -0.38, 0.58), (1.0, 1.05, -0.36, 0.64), (2.4, 0.6, -0.2, 0.74),
            (3.3, 0.06, 0.4, 0.84)]
    b.loft('White', [[(0, y, zk), (hw * 0.75, y, zk + 0.22), (hw, y, zd), (-hw, y, zd), (-hw * 0.75, y, zk + 0.22)]
                     for y, hw, zk, zd in secs])
    for sx in (-1, 1):
        b.loft('Paint', [[(sx * (hw + 0.012), y, zd - 0.22), (sx * (hw + 0.012), y, zd - 0.02), (sx * (hw - 0.03), y, zd - 0.02), (sx * (hw - 0.03), y, zd - 0.22)]
                         for y, hw, zk, zd in secs])
        b.box('White', (sx * 0.92, -1.2, 0.72), (0.14, 3.0, 0.26))
        b.box('Seat', (sx * 0.42, -0.5, 0.86), (0.5, 0.5, 0.12))
        b.box('Seat', (sx * 0.42, -0.74, 1.06), (0.5, 0.1, 0.5))
    b.box('Paint', (0, 1.7, 0.72), (1.5, 1.6, 0.1), top=(0.45, 1))
    b.box('Dark', (0, 0.55, 0.86), (1.7, 0.5, 0.42), top=(0.92, 0.6), shift=(0, -0.05))
    slant(b, 'Glass', 0.5, 1.05, 0.95, 1.5, 1.6, th=0.04, k=1.0)
    b.cyl('Dark', (-0.42, 0.34, 1.08), 0.16, 0.04, axis='Y', seg=10)
    b.box('Seat', (0, -2.3, 0.82), (1.6, 0.6, 0.14))
    b.box('Dark', (0, -3.05, 0.75), (0.5, 0.5, 0.7))
    b.box('Paint2', (0, -3.05, 1.12), (0.52, 0.52, 0.08))
    b.box('Steel', (0, -3.1, 0.1), (0.14, 0.2, 0.7))
    b.obj(name + '_Body', C, r)
    b = B()
    b.cyl('Steel', (0, 0, 0), 0.05, 0.12, axis='Y', seg=6)
    for i in range(3):
        a = i * 2 * math.pi / 3
        b.box('Steel', (math.cos(a) * 0.12, 0, math.sin(a) * 0.12), (0.2, 0.02, 0.1), rot=(0, -a, 0.5))
    b.obj(name + '_Prop', C, r, loc=(0, -3.26, -0.2))
    register(name, kind='boat', open=True, seat=g((-0.42, -0.45, 0.95)))
    # small dinghy
    name = 'dinghy'
    r = root(name, C, (10, 8, 0))
    b = B()
    secs = [(-1.7, 0.75, -0.2, 0.4), (0.4, 0.8, -0.24, 0.42), (1.5, 0.45, -0.1, 0.5), (2.0, 0.05, 0.25, 0.56)]
    b.loft('Orange', [[(0, y, zk), (hw * 0.8, y, zk + 0.15), (hw, y, zd), (-hw, y, zd), (-hw * 0.8, y, zk + 0.15)]
                      for y, hw, zk, zd in secs])
    for sx in (-1, 1):
        tube(b, 'Dark', (sx * 0.74, -1.7, 0.48), (sx * 0.78, 0.4, 0.5), 0.13, seg=8)
        tube(b, 'Dark', (sx * 0.78, 0.4, 0.5), (sx * 0.42, 1.5, 0.56), 0.13, seg=8)
        tube(b, 'Dark', (sx * 0.42, 1.5, 0.56), (0, 2.0, 0.6), 0.13, seg=8)
    b.box('Seat', (0, -0.6, 0.55), (1.3, 0.3, 0.06))
    b.box('Dark', (0, -1.85, 0.6), (0.3, 0.34, 0.5))
    b.box('Steel', (0, -1.9, 0.05), (0.1, 0.14, 0.6))
    b.obj(name + '_Body', C, r)
    register(name, kind='boat', open=True, seat=g((0, -0.9, 0.75)))


def heli(name, place, police=False):
    C = coll('Vehicles/Helicopters')
    r = root(name, C, place)
    b = B()
    zc = 1.45
    b.loft('Paint', [oval(-1.9, 0.35, zc + 0.2, 0.4), oval(-1.2, 0.8, zc, 0.8), oval(0.5, 0.92, zc, 0.88)])
    b.loft('Glass', [oval(0.5, 0.92, zc, 0.88), oval(1.4, 0.8, zc - 0.05, 0.75), oval(2.0, 0.5, zc - 0.2, 0.45),
                     oval(2.25, 0.15, zc - 0.3, 0.15)])
    b.loft('Paint', [oval(-5.4, 0.1, zc + 0.5, 0.12), oval(-1.8, 0.28, zc + 0.3, 0.3)])
    b.box('Paint2', (0, -0.4, zc + 0.95), (0.8, 1.9, 0.4), top=(0.7, 0.8))
    b.cyl('Dark', (0, -0.3, zc + 1.25), 0.07, 0.3, seg=8)
    b.poly('Paint', [(-5.5, zc + 0.3), (-4.7, zc + 0.5), (-5.2, zc + 1.5), (-5.75, zc + 1.5)], 0.06)
    b.box('Paint', (0, -5.1, zc + 0.6), (1.3, 0.4, 0.05))
    b.box('Paint2', (0, 0.0, zc - 0.5), (1.9, 2.2, 0.06))
    for sx in (-1, 1):
        tube(b, 'Dark', (sx * 0.95, -1.5, 0.08), (sx * 0.95, 1.5, 0.08), 0.05)
        tube(b, 'Dark', (sx * 0.95, 1.5, 0.08), (sx * 0.95, 1.85, 0.28), 0.05)
        tube(b, 'Dark', (sx * 0.95, -0.9, 0.08), (sx * 0.6, -0.9, 0.85), 0.04)
        tube(b, 'Dark', (sx * 0.95, 0.9, 0.08), (sx * 0.6, 0.9, 0.85), 0.04)
        b.box('Paint2', (sx * 0.93, -0.3, zc - 0.1), (0.03, 1.5, 0.22))
    if police:
        b.cyl('Dark', (0, 1.5, 0.6), 0.16, 0.2, seg=8)
        b.cyl('LightHead', (0, 1.5, 0.49), 0.13, 0.03, seg=8)
        b.box('LightRed', (0, -1.4, zc + 1.0), (0.1, 0.1, 0.08))
    b.obj(name + '_Body', C, r)
    b = B()
    b.cyl('Dark', (0, 0, 0), 0.14, 0.12, seg=8)
    for i in range(3 if police else 2):
        a = i * 2 * math.pi / (3 if police else 2)
        b.box('Dark', (math.cos(a) * 2.6, math.sin(a) * 2.6, 0.02), (5.0, 0.26, 0.03), rot=(0.05, 0, a))
    b.obj(name + '_Rotor_Main', C, r, loc=(0, -0.3, zc + 1.42))
    b = B()
    b.cyl('Dark', (0, 0, 0), 0.06, 0.1, axis='X', seg=6)
    b.box('Dark', (0, 0, 0), (0.02, 0.12, 1.5))
    b.box('Dark', (0, 0, 0), (0.02, 1.5, 0.12))
    b.obj(name + '_Rotor_Tail', C, r, loc=(0.12, -5.35, zc + 0.95))
    if police:
        side_text(name, r, C, 'POLICE', 0.3, 0.95, -0.3, zc - 0.1, 'White')
    register(name, kind='heli', open=False, seat=g((-0.35, 0.9, 1.2)))


def build_planes():
    C = coll('Vehicles/Airplanes')
    name = 'plane'
    r = root(name, C, (0, 22, 0))
    b = B()
    zc = 1.5
    b.loft('Paint', [oval(-4.0, 0.08, zc + 0.3, 0.12), oval(-1.6, 0.5, zc + 0.05, 0.55), oval(-0.6, 0.62, zc, 0.68),
                     oval(1.3, 0.62, zc, 0.68), oval(2.0, 0.52, zc - 0.05, 0.52), oval(2.5, 0.42, zc - 0.05, 0.42)])
    b.cyl('Paint2', (0, 2.55, zc - 0.05), 0.4, 0.14, axis='Y', seg=10, r2=0.3)
    slant(b, 'Glass', 0.9, zc + 0.5, 1.5, zc + 0.9 - 0.42, 1.0, th=0.3, k=1.0)
    for sx in (-1, 1):
        b.box('Glass', (sx * 0.6, 0.3, zc + 0.3), (0.06, 1.2, 0.36))
        tube(b, 'Paint2', (sx * 0.55, 0.3, zc - 0.5), (sx * 2.4, 0.45, zc + 0.78), 0.035)
        tube(b, 'Steel', (sx * 0.4, 0.5, zc - 0.5), (sx * 1.1, 0.5, 0.34), 0.05)
        b.cyl('Tire', (sx * 1.1, 0.5, 0.3), 0.3, 0.14, axis='X', seg=10)
        b.box('Paint2', (sx * 1.1, 0.5, 0.5), (0.2, 0.7, 0.2), top=(0.8, 0.6))
        b.box('LightRed' if sx < 0 else 'SigGreen', (sx * 5.1, 0.45, zc + 0.8), (0.06, 0.2, 0.06))
    b.box('Paint', (0, 0.45, zc + 0.82), (10.2, 1.5, 0.14), top=(1, 0.8))
    b.box('Paint2', (0, 0.45, zc + 0.9), (10.0, 0.4, 0.02))
    b.box('Paint', (0, -3.6, zc + 0.35), (3.4, 0.8, 0.08))
    b.poly('Paint', [(-4.1, zc + 0.3), (-3.1, zc + 0.4), (-3.75, zc + 1.6), (-4.2, zc + 1.6)], 0.08)
    tube(b, 'Steel', (0, -3.6, zc + 0.2), (0, -3.75, 0.2), 0.03)
    b.cyl('Tire', (0, -3.75, 0.15), 0.15, 0.08, axis='X', seg=8)
    b.obj(name + '_Body', C, r)
    b = B()
    b.cyl('Steel', (0, 0.06, 0), 0.12, 0.26, axis='Y', seg=8, r2=0.03)
    b.box('Dark', (0, 0, 0), (0.16, 0.03, 1.9), rot=(0, 0, 0.2))
    b.obj(name + '_Prop', C, r, loc=(0, 2.66, zc - 0.05))
    register(name, kind='plane', open=False, seat=g((-0.3, 0.6, 1.4)),
             wheels=[g((-1.1, 0.5, 0.3)), g((1.1, 0.5, 0.3)), g((0, -3.75, 0.15))], wr=0.3)
    # jet
    name = 'jet'
    r = root(name, C, (14, 22, 0))
    b = B()
    zc = 1.5
    b.loft('Paint', [oval(-5.0, 0.5, zc, 0.42), oval(-3.0, 0.75, zc, 0.55), oval(0.0, 0.8, zc, 0.6),
                     oval(2.2, 0.6, zc, 0.52), oval(4.2, 0.3, zc - 0.05, 0.3), oval(5.6, 0.03, zc - 0.1, 0.03)])
    b.sphere('Glass', (0, 2.0, zc + 0.42), 0.5, seg=8, rings=5, scale=(0.9, 2.6, 0.75))
    b.poly('Paint', [(0.6, 1.2), (4.6, -2.6), (4.6, -3.5), (0.6, -2.6)], 0.12, axis='Z', c=zc - 0.1)
    b.poly('Paint', [(-0.6, 1.2), (-4.6, -2.6), (-4.6, -3.5), (-0.6, -2.6)], 0.12, axis='Z', c=zc - 0.1)
    b.poly('Paint', [(0.4, -3.6), (2.3, -4.9), (2.3, -5.4), (0.4, -5.0)], 0.08, axis='Z', c=zc)
    b.poly('Paint', [(-0.4, -3.6), (-2.3, -4.9), (-2.3, -5.4), (-0.4, -5.0)], 0.08, axis='Z', c=zc)
    for sx in (-1, 1):
        b.box('Paint2', (sx * 0.62, -4.4, zc + 1.0), (0.07, 1.3, 1.5), rot=(0, sx * 0.3, 0), top=(1, 0.45), shift=(0, -0.35))
        b.box('Dark', (sx * 0.85, 0.9, zc - 0.15), (0.5, 1.6, 0.6), top=(0.8, 1))
        b.cyl('Gunmetal', (sx * 0.38, -5.1, zc), 0.34, 0.5, axis='Y', seg=10, r2=0.4)
        b.cyl('LightAmber', (sx * 0.38, -5.3, zc), 0.26, 0.06, axis='Y', seg=10)
        tube(b, 'Steel', (sx * 0.9, -1.0, zc - 0.4), (sx * 1.2, -1.0, 0.3), 0.05)
        b.cyl('Tire', (sx * 1.2, -1.0, 0.27), 0.27, 0.16, axis='X', seg=10)
        b.box('LightRed' if sx < 0 else 'SigGreen', (sx * 4.58, -3.0, zc - 0.1), (0.06, 0.3, 0.06))
    tube(b, 'Steel', (0, 3.4, zc - 0.3), (0, 3.4, 0.25), 0.05)
    b.cyl('Tire', (0, 3.4, 0.22), 0.22, 0.14, axis='X', seg=10)
    b.obj(name + '_Body', C, r)
    register(name, kind='plane', open=False, seat=g((0, 2.0, 1.5)),
             wheels=[g((-1.2, -1.0, 0.27)), g((1.2, -1.0, 0.27)), g((0, 3.4, 0.22))], wr=0.27)


def build_train():
    C = coll('Vehicles/Transit')
    name = 'monorail'
    r = root(name, C, (26, 22, 0))
    b = B()
    secs = [(-6.2, 0.8, 0.5, 2.3), (-5.6, 1.3, 0.3, 2.9), (5.6, 1.3, 0.3, 2.9), (6.2, 0.8, 0.5, 2.3)]
    b.loft('White', [ring(*s, ch=0.25) for s in secs])
    for sx in (-1, 1):
        b.box('Glass', (sx * 1.305, 0, 1.9), (0.03, 10.4, 0.8))
        b.box('Paint', (sx * 1.305, 0, 1.15), (0.03, 11.0, 0.3))
        for y in (-3.2, 3.2):
            b.box('Paint2', (sx * 1.31, y, 1.4), (0.03, 1.3, 2.0))
            b.box('Glass', (sx * 1.315, y, 1.9), (0.03, 1.0, 0.8))
    for sy in (-1, 1):
        slant(b, 'Glass', sy * 5.6, 2.9, sy * 6.2, 2.3, 1.7, th=0.3, k=1.3) if False else None
        b.box('Glass', (0, sy * 5.98, 2.2), (1.7, 0.2, 0.7), rot=(sy * -0.75, 0, 0))
        b.box('LightHead', (0, sy * 6.21, 1.0), (1.0, 0.05, 0.12))
    b.box('Dark', (0, 0, 0.15), (1.2, 11.0, 0.5))
    b.box('Steel', (0, 0, 2.98), (1.4, 8.0, 0.16))
    b.obj(name + '_Body', C, r)
    register(name, kind='train')


def build_all_vehicles():
    make_wheels()
    build_cars()
    build_bikes()
    build_boats()
    heli('helicopter', (0, 14, 0))
    heli('police_heli', (10, 14, 0), police=True)
    build_planes()
    build_train()
    names = ['sedan', 'compact', 'sports', 'muscle', 'suv', 'pickup', 'van', 'police', 'taxi', 'ambulance', 'truck',
             'firetruck', 'swat', 'motorcycle', 'bicycle', 'speedboat', 'dinghy', 'helicopter', 'police_heli', 'plane',
             'jet', 'monorail']
    export_all(names, 'vehicles')
    return names
