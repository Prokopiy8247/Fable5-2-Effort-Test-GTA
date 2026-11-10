"""Wheels library + all road vehicles (lofted low-poly bodies). Run through Blender MCP."""
import sys
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

ONLY = globals().get("ONLY")  # optional list of vehicle ids to rebuild

# ------------------------------------------------------------------ wheels (unit radius, unit width, axle = X, outside = +X)
CW = coll("Vehicles/Wheels")


def wheel_mesh(style):
    name = "wheel_" + style
    old = bpy.data.objects.get(name)
    if old:
        return old
    mb = MB()
    seg = 14
    # tyre
    tire_r_in = 0.62 if style != "offroad" else 0.55
    rings = []
    prof = [(-0.5, 0.92), (-0.42, 1.0), (0.42, 1.0), (0.5, 0.92), (0.5, tire_r_in), (-0.5, tire_r_in)]
    for (x, r) in prof:
        rings.append([(x, math.cos(2 * math.pi * i / seg) * r, math.sin(2 * math.pi * i / seg) * r) for i in range(seg)])
    rings.append(rings[0])
    mb.loft(rings, lambda i, k: "M_Tire")
    if style == "offroad":
        for i in range(seg):
            a = 2 * math.pi * (i + 0.5) / seg
            mb.box((0, math.cos(a) * 1.0, math.sin(a) * 1.0), (0.9, 0.16, 0.12), "M_Tire", rot=(a + math.pi / 2, 0, 0))
    # rim barrel + face
    mb.cyl((0.0, 0, 0), tire_r_in + 0.01, 0.9, "M_Black", axis='X', seg=seg)
    if style == "std":
        mb.cyl((0.40, 0, 0), tire_r_in, 0.08, "M_Rim", axis='X', seg=seg)
        for i in range(5):
            a = 2 * math.pi * i / 5
            mb.box((0.46, math.cos(a) * 0.30, math.sin(a) * 0.30), (0.06, 0.46, 0.13), "M_Rim", rot=(a + math.pi / 2, 0, 0))
        mb.cyl((0.48, 0, 0), 0.14, 0.08, "M_Rim", axis='X', seg=8)
    elif style == "sport":
        mb.cyl((0.36, 0, 0), tire_r_in, 0.05, "M_Black", axis='X', seg=seg)
        for i in range(10):
            a = 2 * math.pi * i / 10
            mb.box((0.44, math.cos(a) * 0.33, math.sin(a) * 0.33), (0.05, 0.56, 0.055), "M_Rim", rot=(a + math.pi / 2, 0, 0))
        mb.cyl((0.46, 0, 0), 0.10, 0.08, "M_Rim", axis='X', seg=8)
        mb.cyl((0.42, 0, 0), tire_r_in, 0.06, "M_Rim", axis='X', seg=seg, r2=tire_r_in - 0.05)
    elif style == "offroad":
        mb.cyl((0.36, 0, 0), tire_r_in, 0.10, "M_Rim", axis='X', seg=seg)
        for i in range(6):
            a = 2 * math.pi * i / 6
            mb.cyl((0.42, math.cos(a) * 0.36, math.sin(a) * 0.36), 0.07, 0.04, "M_Black", axis='X', seg=6)
        mb.cyl((0.44, 0, 0), 0.16, 0.10, "M_Rim", axis='X', seg=8)
    elif style == "classic":
        mb.cyl((0.40, 0, 0), tire_r_in, 0.08, "M_Rim", axis='X', seg=seg, r2=tire_r_in * 0.55)
        mb.cyl((0.47, 0, 0), tire_r_in * 0.55, 0.06, "M_Rim", axis='X', seg=seg, r2=0.12)
        mb.cyl((0.50, 0, 0), 0.12, 0.05, "M_Black", axis='X', seg=8)
    elif style == "bike":
        mb.cyl((0.0, 0, 0), tire_r_in, 0.30, "M_Rim", axis='X', seg=seg, r2=tire_r_in)
        for i in range(6):
            a = 2 * math.pi * i / 6
            mb.box((0.0, math.cos(a) * 0.30, math.sin(a) * 0.30), (0.5, 0.56, 0.06), "M_Rim", rot=(a + math.pi / 2, 0, 0))
        mb.cyl((0.0, 0, 0), 0.14, 1.1, "M_Black", axis='X', seg=8)
    ob = mb.build(name, CW, loc=(0, 0, 0))
    return ob


STYLES = ["std", "sport", "offroad", "classic", "bike"]
wheel_root = bpy.data.objects.get("wheels_lib")
if wheel_root is None:
    wheel_root = empty("wheels_lib", CW, loc=(-12, -14, 0))
    for i, s in enumerate(STYLES):
        w = wheel_mesh(s)
        w.parent = wheel_root
        w.location = (i * 1.6, 0, 1.0)


def place_wheel(parent, name, style, pos, r, w, left, collection):
    src = bpy.data.objects["wheel_" + style]
    ob = bpy.data.objects.new(name, src.data)
    collection.objects.link(ob)
    ob.parent = parent
    ob.location = pos
    ob.scale = (w, r, r)
    ob.rotation_euler = (0, 0, math.pi if left else 0)
    return ob


# ------------------------------------------------------------------ lofted body
def body_loft(mb, secs, two_tone=False, glass="M_Glass", paint="M_Paint"):
    rings = []
    flags = []
    for s in secs:
        y, zb, hw, zsh, hwsh, zt, hwt, flag = s
        if zt is None:
            zt = zsh + 0.035
            hwt = max(hwsh - 0.12, 0.05)
        zm = zb + (zsh - zb) * 0.42
        ring = [(hw - 0.07, y, zb), (hw, y, zm), (hwsh, y, zsh), (hwt, y, zt),
                (-hwt, y, zt), (-hwsh, y, zsh), (-hw, y, zm), (-(hw - 0.07), y, zb)]
        rings.append(ring)
        flags.append(flag)

    def mf(i, k):
        fl = flags[i]
        if k == 7:
            return "M_Under"
        if k in (2, 4):
            return glass if fl in ("cab", "ws", "rw") else paint
        if k == 3:
            return glass if fl in ("ws", "rw") else paint
        if two_tone and k in (1, 5) and fl in ("cab", "pillar"):
            return "M_Paint2"
        if two_tone == "low" and k in (0, 6):
            return "M_Paint2"
        return paint
    mb.loft(rings, mf, cap0=paint, cap1=paint)


def sec_at(secs, y):
    """Interpolated (zb, hw, zsh, hwsh) at y."""
    for a, b in zip(secs, secs[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / max(b[0] - a[0], 1e-6)
            return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3, 4))
    s = secs[0] if y < secs[0][0] else secs[-1]
    return (s[1], s[2], s[3], s[4])


def build_car(vid, spec, loc):
    C = coll("Vehicles/" + spec.get("coll", "Cars"))
    wipe([vid + "_", vid])
    secs = spec["secs"]
    y0 = secs[0][0]
    y1 = secs[-1][0]
    W = max(s[2] for s in secs)
    mb = MB()
    body_loft(mb, secs, spec.get("two_tone", False), paint=spec.get("paint_mat", "M_Paint"))
    wr, ww = spec["wheel_r"], spec["wheel_w"]
    wyf, wyr = spec["wheel_yf"], spec["wheel_yr"]
    track = spec.get("track", W - ww / 2 + 0.04)
    # wheel wells
    wys = [wyf, wyr] + spec.get("extra_axles", [])
    for wy in wys:
        zb, hw, zsh, hwsh = sec_at(secs, wy)
        for sx in (-1, 1):
            mb.cyl((sx * (hw - 0.06), wy, wr), wr * 1.22, 0.14, "M_Black", axis='X', seg=12)
    # bumpers
    zb, hw, zsh, hwsh = sec_at(secs, y1 - 0.1)
    bz = spec.get("bumper_z", zb + 0.16)
    mb.box((0, y1 - 0.02, bz), (hw * 2 + 0.04, 0.22, 0.20), spec.get("bumper_mat", "M_Black"))
    zb2, hw2, zsh2, hwsh2 = sec_at(secs, y0 + 0.1)
    mb.box((0, y0 + 0.02, bz), (hw2 * 2 + 0.04, 0.22, 0.20), spec.get("bumper_mat", "M_Black"))
    # head/tail lights, grille, plates
    fz = spec.get("light_z", secs[-1][3] - 0.12)
    fhw = secs[-1][4]
    lw = spec.get("light_w", 0.34)
    for sx in (-1, 1):
        mb.box((sx * (fhw - lw / 2 - 0.03), y1 + 0.005, fz), (lw, 0.06, 0.14), "M_Headlight")
        mb.box((sx * (fhw - 0.06), y1 - 0.02, fz - 0.17), (0.12, 0.06, 0.07), "M_Indicator")
    gw = max(fhw * 2 - lw * 2 - 0.2, 0.3)
    mb.box((0, y1 + 0.005, fz - 0.03), (gw, 0.05, 0.16), "M_Black")
    mb.box((0, y1 + 0.03, fz - 0.03), (gw * 0.8, 0.02, 0.03), "M_Chrome")
    rz = spec.get("tail_z", secs[0][3] - 0.10)
    rhw = secs[0][4]
    tw = spec.get("tail_w", 0.36)
    for sx in (-1, 1):
        mb.box((sx * (rhw - tw / 2 - 0.02), y0 - 0.005, rz), (tw, 0.06, 0.12), "M_Taillight")
    mb.box((0, y0 - 0.01, rz - 0.22), (0.46, 0.03, 0.13), "M_Plate")
    mb.box((0, y1 + 0.1, bz + 0.02), (0.46, 0.03, 0.12), "M_Plate")
    # mirrors
    my = spec["mirror_y"]
    zbm, hwm, zshm, hwshm = sec_at(secs, my)
    for sx in (-1, 1):
        mb.box((sx * (hwshm + 0.10), my, zshm + 0.06), (0.20, 0.08, 0.12), spec.get("paint_mat", "M_Paint"))
    # interior
    seats = spec["seats"]
    cab_y0, cab_y1 = spec["cab"]
    zbc, hwc, zshc, hwshc = sec_at(secs, (cab_y0 + cab_y1) / 2)
    mb.box((0, (cab_y0 + cab_y1) / 2, zbc + 0.10), (hwc * 2 - 0.2, cab_y1 - cab_y0, 0.08), "M_Interior")
    mb.box((0, cab_y1 - 0.12, zshc - 0.12), (hwshc * 2 - 0.2, 0.3, 0.2), "M_Interior")
    for (sx, sy, sz) in seats:
        mb.box((sx, sy - 0.05, sz - 0.08), (0.48, 0.5, 0.14), "M_Seat")
        mb.box((sx, sy - 0.30, sz + 0.28), (0.48, 0.12, 0.62), "M_Seat", rot=(-0.15, 0, 0))
        mb.box((sx, sy - 0.36, sz + 0.68), (0.26, 0.10, 0.18), "M_Seat")
    dsx, dsy, dsz = seats[0]
    mb.cyl((dsx, dsy + 0.40, dsz + 0.40), 0.17, 0.035, "M_Black", axis='Y', seg=10)
    mb.limb((dsx, dsy + 0.42, dsz + 0.40), (dsx, dsy + 0.62, dsz + 0.30), 0.03, 0.03, "M_Black", seg=4)
    # exhaust
    ex = spec.get("exhaust", (W - 0.35, y0 - 0.02, zb2 + 0.02))
    mb.cyl(ex, 0.05, 0.16, "M_Chrome", axis='Y', seg=8)
    # custom extras
    if "extra" in spec:
        spec["extra"](mb, secs)
    body = mb.build(vid, C, loc=loc)
    body["vehicle_id"] = vid
    # wheels
    style = spec.get("wheel_style", "std")
    place_wheel(body, vid + "_wheel_fl", style, (-track, wyf, wr), wr, ww, True, C)
    place_wheel(body, vid + "_wheel_fr", style, (track, wyf, wr), wr, ww, False, C)
    place_wheel(body, vid + "_wheel_rl", style, (-track, wyr, wr), wr, ww, True, C)
    place_wheel(body, vid + "_wheel_rr", style, (track, wyr, wr), wr, ww, False, C)
    for i, ey in enumerate(spec.get("extra_axles", [])):
        place_wheel(body, vid + "_wheel_x%dl" % i, style, (-track, ey, wr), wr, ww, True, C)
        place_wheel(body, vid + "_wheel_x%dr" % i, style, (track, ey, wr), wr, ww, False, C)
    # doors (overlay skins hinged at the front edge)
    d0, d1 = spec["door"]
    for side, sx in (("l", -1), ("r", 1)):
        zbd, hwd, zshd, hwshd = sec_at(secs, (d0 + d1) / 2)
        dm = MB()
        zlo = zbd + 0.10
        zhi = zshd - 0.03
        dm.box((sx * 0.012, -(d1 - d0) / 2, (zlo + zhi) / 2 - zlo), (0.03, (d1 - d0) - 0.04, zhi - zlo), spec.get("door_mat", spec.get("paint_mat", "M_Paint")))
        dm.box((sx * 0.035, -(d1 - d0) + 0.16, (zhi - zlo) - 0.10), (0.03, 0.14, 0.035), "M_Chrome")
        dm.build(vid + "_door_f" + side, C, loc=(sx * (hwd + 0.004), d1, zlo), parent=body)
    # markers
    for i, s in enumerate(seats):
        empty(vid + "_seat_%d" % i, C, loc=s, parent=body)
    for sx, n in ((-1, "l"), (1, "r")):
        empty(vid + "_headlight_" + n, C, loc=(sx * (fhw - lw / 2), y1 + 0.05, fz), parent=body)
        empty(vid + "_taillight_" + n, C, loc=(sx * (rhw - tw / 2), y0 - 0.05, rz), parent=body)
    empty(vid + "_exhaust", C, loc=(ex[0], ex[1] - 0.1, ex[2]), parent=body)
    # modular customisation parts
    if spec.get("mods", True):
        trunk_z = sec_at(secs, y0 + 0.35)[2]
        thw = sec_at(secs, y0 + 0.35)[3]
        hood_y = (cab_y1 + y1) / 2 + 0.1
        hood_z = sec_at(secs, hood_y)[2]
        roof_z = max(s[5] or 0 for s in secs)
        pm = spec.get("paint_mat", "M_Paint")
        m = MB()
        m.box((0, 0, 0.05), (thw * 2 - 0.1, 0.22, 0.04), pm)
        m.box((0, -0.10, 0.09), (thw * 2 - 0.1, 0.04, 0.06), pm)
        m.build(vid + "_mod_spoiler_1", C, loc=(0, y0 + 0.22, trunk_z), parent=body)
        m = MB()
        for sx in (-1, 1):
            m.box((sx * (thw - 0.25), 0, 0.13), (0.06, 0.20, 0.26), "M_Black")
            m.box((sx * (thw + 0.0), 0, 0.30), (0.03, 0.42, 0.20), pm)
        m.box((0, 0, 0.28), (thw * 2, 0.34, 0.035), pm, rot=(0.14, 0, 0))
        m.build(vid + "_mod_spoiler_2", C, loc=(0, y0 + 0.24, trunk_z), parent=body)
        m = MB()
        for sx in (-1, 1):
            m.box((sx * (W + 0.02), (wyf + wyr) / 2, sec_at(secs, (wyf + wyr) / 2)[0] + 0.06), (0.10, abs(wyf - wyr) - wr * 2.5, 0.12), "M_Black")
        m.build(vid + "_mod_skirts_1", C, loc=(0, 0, 0), parent=body)
        m = MB()
        m.box((0, 0.10, -0.10), (hw * 2 + 0.10, 0.30, 0.05), "M_Black")
        for sx in (-1, 1):
            m.box((sx * (hw - 0.02), 0.02, 0.0), (0.06, 0.26, 0.20), "M_Black")
        m.build(vid + "_mod_bumper_f_1", C, loc=(0, y1, bz), parent=body)
        m = MB()
        m.box((0, -0.08, -0.08), (hw2 * 2 - 0.2, 0.24, 0.10), "M_Black")
        for i in range(4):
            m.box((-0.36 + i * 0.24, -0.12, -0.08), (0.03, 0.26, 0.14), "M_Black")
        m.build(vid + "_mod_bumper_r_1", C, loc=(0, y0, bz), parent=body)
        m = MB()
        m.box((0, 0, 0.05), (0.50, 0.70, 0.10), pm, top=(0.36, 0.5), top_off=(0, -0.05))
        m.box((0, 0.33, 0.05), (0.36, 0.04, 0.06), "M_Black")
        m.build(vid + "_mod_hood_1", C, loc=(0, hood_y, hood_z + 0.02), parent=body)
        m = MB()
        ry = (cab_y0 + cab_y1) / 2 - 0.1
        for sy in (-0.35, 0.35):
            m.box((0, sy, 0.05), (1.25, 0.05, 0.05), "M_Black")
        for sx in (-0.55, 0.55):
            m.box((sx, 0, 0.03), (0.05, 0.9, 0.05), "M_Black")
        m.build(vid + "_mod_roof_1", C, loc=(0, ry, roof_z), parent=body)
        m = MB()
        for sx in (-1, 1):
            for dx in (-0.07, 0.07):
                m.cyl((sx * (W - 0.38) + dx, -0.06, 0), 0.055, 0.22, "M_Chrome", axis='Y', seg=8)
        m.build(vid + "_mod_exhaust_1", C, loc=(0, y0, zb2 + 0.03), parent=body)
    return body


# ------------------------------------------------------------------ specs
def lightbar(mb, y, z, w=1.1):
    mb.box((0, y, z + 0.03), (w + 0.1, 0.30, 0.05), "M_Black")
    mb.box((-w / 4 - 0.02, y, z + 0.11), (w / 2 - 0.06, 0.24, 0.12), "M_Siren_R")
    mb.box((w / 4 + 0.02, y, z + 0.11), (w / 2 - 0.06, 0.24, 0.12), "M_Siren_B")
    mb.box((0, y, z + 0.11), (0.10, 0.26, 0.13), "M_Chrome")


def pushbar(mb, y, z, w):
    for sx in (-1, 1):
        mb.box((sx * w * 0.32, y + 0.14, z + 0.18), (0.07, 0.07, 0.62), "M_Black")
    for dz in (0.0, 0.22, 0.44):
        mb.box((0, y + 0.16, z + dz), (w * 0.9, 0.06, 0.06), "M_Black")


SPECS = {}

SPECS["compact"] = dict(
    secs=[(-1.85, .42, .74, .80, .70, None, 0, 'body'), (-1.76, .26, .82, .95, .78, None, 0, 'rw'),
          (-1.42, .24, .83, .97, .80, 1.46, .64, 'cab'), (-0.55, .24, .83, .97, .80, 1.48, .66, 'pillar'),
          (-0.47, .24, .83, .97, .80, 1.48, .66, 'cab'), (0.30, .24, .83, .97, .80, 1.46, .65, 'ws'),
          (0.88, .24, .83, .95, .79, None, 0, 'body'), (1.66, .26, .81, .80, .76, None, 0, 'body'),
          (1.85, .40, .72, .68, .68, None, 0, 'end')],
    wheel_r=0.30, wheel_w=0.20, wheel_yf=1.18, wheel_yr=-1.20, mirror_y=0.42, cab=(-1.40, 0.55), door=(-0.45, 0.50),
    seats=[(-0.36, -0.10, 0.50), (0.36, -0.10, 0.50), (-0.36, -0.95, 0.52), (0.36, -0.95, 0.52)], wheel_style="classic")

SPECS["sedan"] = dict(
    secs=[(-2.30, .42, .78, .80, .74, None, 0, 'body'), (-2.18, .26, .88, .93, .84, None, 0, 'body'),
          (-1.45, .24, .90, .97, .86, None, 0, 'rw'), (-0.95, .24, .90, .98, .87, 1.42, .66, 'cab'),
          (-0.20, .24, .90, .98, .87, 1.44, .68, 'pillar'), (-0.10, .24, .90, .98, .87, 1.44, .68, 'cab'),
          (0.48, .24, .90, .98, .87, 1.42, .67, 'ws'), (1.12, .24, .90, .96, .86, None, 0, 'body'),
          (2.06, .26, .88, .84, .82, None, 0, 'body'), (2.30, .40, .78, .72, .72, None, 0, 'end')],
    wheel_r=0.33, wheel_w=0.22, wheel_yf=1.40, wheel_yr=-1.38, mirror_y=0.62, cab=(-1.0, 0.75), door=(-0.10, 0.70),
    seats=[(-0.38, 0.05, 0.50), (0.38, 0.05, 0.50), (-0.38, -0.75, 0.52), (0.38, -0.75, 0.52)])

SPECS["sports"] = dict(
    secs=[(-2.20, .36, .82, .72, .78, None, 0, 'body'), (-2.06, .20, .94, .86, .90, None, 0, 'body'),
          (-1.25, .18, .96, .90, .92, None, 0, 'rw'), (-0.40, .18, .96, .86, .90, 1.16, .62, 'cab'),
          (0.22, .18, .96, .84, .89, 1.15, .62, 'ws'), (0.98, .18, .95, .80, .88, None, 0, 'body'),
          (1.95, .18, .92, .60, .84, None, 0, 'body'), (2.20, .28, .80, .48, .74, None, 0, 'end')],
    wheel_r=0.33, wheel_w=0.27, wheel_yf=1.36, wheel_yr=-1.34, mirror_y=0.40, cab=(-0.75, 0.55), door=(-0.38, 0.50),
    seats=[(-0.40, -0.18, 0.36), (0.40, -0.18, 0.36)], wheel_style="sport", light_w=0.30)

SPECS["muscle"] = dict(
    secs=[(-2.45, .42, .82, .84, .80, None, 0, 'body'), (-2.32, .28, .93, .96, .90, None, 0, 'body'),
          (-1.55, .26, .95, .99, .92, None, 0, 'rw'), (-1.00, .26, .95, 1.0, .92, 1.33, .68, 'cab'),
          (0.05, .26, .95, 1.0, .92, 1.32, .68, 'ws'), (0.62, .26, .95, .99, .92, None, 0, 'body'),
          (2.25, .28, .93, .92, .90, None, 0, 'body'), (2.45, .40, .84, .82, .84, None, 0, 'end')],
    wheel_r=0.35, wheel_w=0.28, wheel_yf=1.55, wheel_yr=-1.45, mirror_y=0.25, cab=(-1.05, 0.40), door=(-0.75, 0.30),
    seats=[(-0.40, -0.35, 0.46), (0.40, -0.35, 0.46)], wheel_style="classic", light_w=0.26,
    extra=lambda mb, s: (mb.box((0, 1.45, 1.0), (0.5, 1.2, 0.06), "M_Black"),))

SPECS["suv"] = dict(
    secs=[(-2.40, .55, .86, 1.00, .84, None, 0, 'body'), (-2.30, .36, .95, 1.12, .92, None, 0, 'rw'),
          (-2.04, .34, .96, 1.14, .93, 1.76, .80, 'cab'), (-0.95, .34, .96, 1.14, .93, 1.78, .81, 'pillar'),
          (-0.86, .34, .96, 1.14, .93, 1.78, .81, 'cab'), (-0.05, .34, .96, 1.14, .93, 1.78, .81, 'pillar'),
          (0.04, .34, .96, 1.14, .93, 1.78, .81, 'cab'), (0.72, .34, .96, 1.14, .93, 1.74, .78, 'ws'),
          (1.26, .34, .96, 1.12, .93, None, 0, 'body'), (2.20, .36, .95, 1.02, .90, None, 0, 'body'),
          (2.40, .52, .86, .90, .84, None, 0, 'end')],
    wheel_r=0.40, wheel_w=0.28, wheel_yf=1.45, wheel_yr=-1.42, mirror_y=0.85, cab=(-2.0, 0.95), door=(0.04, 0.90),
    seats=[(-0.40, 0.25, 0.72), (0.40, 0.25, 0.72), (-0.40, -0.65, 0.74), (0.40, -0.65, 0.74)], wheel_style="offroad",
    bumper_z=0.52)


def pickup_extra(mb, secs):
    for sx in (-1, 1):
        mb.box((sx * 0.90, -1.62, 0.92), (0.10, 1.90, 0.42), "M_Paint")
    mb.box((0, -2.60, 0.92), (1.90, 0.10, 0.42), "M_Paint")
    mb.box((0, -0.74, 1.40), (1.40, 0.05, 0.42), "M_Glass")
    mb.box((0, -1.62, 0.735), (1.70, 1.86, 0.03), "M_Black")


SPECS["pickup"] = dict(
    secs=[(-2.65, .50, .90, .70, .88, None, 0, 'body'), (-2.55, .36, .96, .72, .94, None, 0, 'body'),
          (-0.72, .36, .96, .72, .94, None, 0, 'body'), (-0.68, .36, .96, 1.12, .93, 1.80, .80, 'cab'),
          (0.55, .36, .96, 1.12, .93, 1.78, .78, 'ws'), (1.15, .36, .96, 1.12, .93, None, 0, 'body'),
          (2.45, .38, .95, 1.04, .92, None, 0, 'body'), (2.65, .52, .88, .92, .86, None, 0, 'end')],
    wheel_r=0.40, wheel_w=0.28, wheel_yf=1.70, wheel_yr=-1.60, mirror_y=0.70, cab=(-0.62, 0.85), door=(-0.50, 0.75),
    seats=[(-0.40, 0.05, 0.72), (0.40, 0.05, 0.72)], wheel_style="offroad", extra=pickup_extra, bumper_z=0.54,
    tail_z=0.62)

SPECS["van"] = dict(
    secs=[(-2.60, .50, .92, 1.10, .92, 2.15, .88, 'pillar'), (-2.50, .34, .98, 1.15, .98, 2.20, .92, 'pillar'),
          (0.38, .34, .98, 1.15, .98, 2.20, .92, 'cab'), (1.28, .34, .98, 1.15, .98, 2.15, .90, 'ws'),
          (1.95, .34, .98, 1.10, .96, None, 0, 'body'), (2.45, .36, .96, .95, .92, None, 0, 'body'),
          (2.60, .50, .90, .85, .88, None, 0, 'end')],
    wheel_r=0.37, wheel_w=0.26, wheel_yf=1.70, wheel_yr=-1.55, mirror_y=1.30, cab=(0.30, 1.45), door=(0.42, 1.30),
    seats=[(-0.42, 0.72, 0.74), (0.42, 0.72, 0.74)], bumper_z=0.50, tail_z=0.95,
    extra=lambda mb, s: (mb.box((0, -2.61, 1.25), (1.5, 0.03, 1.5), "M_Paint"), mb.box((0, -2.63, 1.25), (0.04, 0.03, 1.5), "M_Black")))


def police_extra(mb, secs):
    lightbar(mb, -0.15, 1.44)
    pushbar(mb, 2.30, 0.30, 1.6)
    mb.box((0, -2.0, 1.02), (0.06, 0.06, 0.5), "M_Black")


SPECS["police"] = dict(
    secs=[(-2.38, .42, .80, .82, .76, None, 0, 'body'), (-2.25, .26, .90, .95, .86, None, 0, 'body'),
          (-1.50, .24, .92, .99, .88, None, 0, 'rw'), (-0.98, .24, .92, 1.0, .89, 1.43, .68, 'cab'),
          (-0.22, .24, .92, 1.0, .89, 1.45, .70, 'pillar'), (-0.12, .24, .92, 1.0, .89, 1.45, .70, 'cab'),
          (0.50, .24, .92, 1.0, .89, 1.43, .69, 'ws'), (1.14, .24, .92, .98, .88, None, 0, 'body'),
          (2.14, .26, .90, .86, .84, None, 0, 'body'), (2.38, .40, .80, .74, .74, None, 0, 'end')],
    wheel_r=0.34, wheel_w=0.24, wheel_yf=1.45, wheel_yr=-1.42, mirror_y=0.64, cab=(-1.0, 0.78), door=(-0.12, 0.72),
    seats=[(-0.38, 0.05, 0.50), (0.38, 0.05, 0.50), (-0.38, -0.75, 0.52), (0.38, -0.75, 0.52)],
    two_tone=True, door_mat="M_Paint2", extra=police_extra, mods=False)


def taxi_extra(mb, secs):
    mb.box((0, -0.1, 1.60), (0.55, 0.20, 0.20), "M_TaxiSign")
    mb.box((0, -0.1, 1.50), (0.65, 0.26, 0.04), "M_Black")
    for sx in (-1, 1):
        for i in range(7):
            mb.box((sx * 0.905, -1.2 + i * 0.36, 0.86), (0.02, 0.18, 0.09), "M_Black")


SPECS["taxi"] = dict(
    secs=[(-2.25, .44, .78, .86, .74, None, 0, 'body'), (-2.14, .28, .88, 1.0, .85, None, 0, 'rw'),
          (-1.70, .26, .90, 1.02, .87, 1.52, .70, 'cab'), (-0.20, .26, .90, 1.02, .87, 1.54, .72, 'pillar'),
          (-0.10, .26, .90, 1.02, .87, 1.54, .72, 'cab'), (0.52, .26, .90, 1.02, .87, 1.52, .70, 'ws'),
          (1.20, .26, .90, 1.0, .86, None, 0, 'body'), (2.02, .28, .88, .86, .82, None, 0, 'body'),
          (2.25, .42, .78, .74, .72, None, 0, 'end')],
    wheel_r=0.33, wheel_w=0.22, wheel_yf=1.38, wheel_yr=-1.36, mirror_y=0.66, cab=(-1.65, 0.80), door=(-0.10, 0.72),
    seats=[(-0.38, 0.08, 0.54), (0.38, 0.08, 0.54), (-0.38, -0.85, 0.56), (0.38, -0.85, 0.56)],
    extra=taxi_extra, mods=False)


def ambulance_extra(mb, secs):
    lightbar(mb, 1.0, 2.36, 1.3)
    mb.box((0, -1.2, 2.72), (0.5, 0.3, 0.14), "M_Siren_R")
    for sx in (-1, 1):
        mb.box((sx * 1.105, -1.1, 1.55), (0.02, 2.4, 0.22), "M_Red")
        mb.box((sx * 1.105, -1.1, 1.95), (0.02, 0.5, 0.5), "M_Red")
        mb.box((sx * 1.105, -1.1, 1.95), (0.02, 0.16, 0.9), "M_Red")
    mb.box((0, -2.86, 1.5), (1.7, 0.03, 1.9), "M_Paint")
    mb.box((0, -2.88, 1.5), (0.04, 0.03, 1.9), "M_Black")


SPECS["ambulance"] = dict(
    secs=[(-2.85, .50, 1.05, 1.2, 1.08, 2.62, 1.06, 'pillar'), (-2.78, .36, 1.10, 1.2, 1.10, 2.66, 1.08, 'pillar'),
          (0.40, .36, 1.10, 1.2, 1.10, 2.66, 1.08, 'pillar'), (0.44, .36, .98, 1.15, .98, 2.30, .90, 'cab'),
          (1.40, .36, .98, 1.15, .98, 2.24, .88, 'ws'), (2.02, .36, .98, 1.10, .96, None, 0, 'body'),
          (2.52, .38, .96, .95, .92, None, 0, 'body'), (2.68, .52, .90, .85, .88, None, 0, 'end')],
    wheel_r=0.38, wheel_w=0.27, wheel_yf=1.72, wheel_yr=-1.70, mirror_y=1.40, cab=(0.45, 1.55), door=(0.50, 1.38),
    seats=[(-0.42, 0.82, 0.76), (0.42, 0.82, 0.76)], extra=ambulance_extra, mods=False, bumper_z=0.52, tail_z=1.0,
    paint_mat="M_Paint")


def firetruck_extra(mb, secs):
    lightbar(mb, 2.55, 2.72, 1.6)
    # ladder
    for sx in (-0.32, 0.32):
        mb.box((sx, -1.2, 3.0), (0.08, 5.4, 0.10), "M_Steel", rot=(0.04, 0, 0))
    for i in range(12):
        mb.box((0, -3.6 + i * 0.44, 3.0 + (i - 6) * 0.017), (0.64, 0.06, 0.06), "M_Steel")
    mb.box((0, -2.9, 2.80), (1.2, 1.0, 0.24), "M_MetalDark")
    # side lockers + hose reels
    for sx in (-1, 1):
        for i in range(4):
            mb.box((sx * 1.215, -3.1 + i * 1.02, 1.55), (0.02, 0.9, 1.1), "M_Steel")
        mb.cyl((sx * 1.23, 0.75, 1.3), 0.32, 0.10, "M_Yellow", axis='X', seg=10)
    mb.box((0, -3.92, 1.5), (2.0, 0.03, 1.4), "M_Steel")


SPECS["firetruck"] = dict(
    secs=[(-3.90, .62, 1.14, 1.30, 1.18, 2.72, 1.16, 'pillar'), (-3.82, .46, 1.20, 1.30, 1.20, 2.76, 1.18, 'pillar'),
          (1.30, .46, 1.20, 1.30, 1.20, 2.76, 1.18, 'pillar'), (1.34, .46, 1.18, 1.45, 1.18, 2.70, 1.10, 'cab'),
          (3.10, .46, 1.18, 1.45, 1.18, 2.68, 1.08, 'ws'), (3.60, .46, 1.18, 1.40, 1.16, None, 0, 'body'),
          (3.72, .60, 1.12, 1.30, 1.12, None, 0, 'end')],
    wheel_r=0.50, wheel_w=0.34, wheel_yf=2.55, wheel_yr=-2.0, extra_axles=[-3.05], mirror_y=3.1, cab=(1.4, 3.3),
    door=(2.0, 3.05), seats=[(-0.55, 2.35, 1.05), (0.55, 2.35, 1.05)], extra=firetruck_extra, mods=False,
    bumper_z=0.70, light_z=1.05, tail_z=1.1, wheel_style="offroad")


def boxtruck_extra(mb, secs):
    mb.box((0, -1.45, 2.05), (2.44, 4.9, 2.5), "M_Paint2")
    mb.box((0, -3.92, 2.05), (2.2, 0.03, 2.3), "M_Steel")
    for i in range(6):
        mb.box((0, -3.94, 1.05 + i * 0.4), (2.2, 0.02, 0.03), "M_MetalDark")
    for sx in (-1, 1):
        mb.box((sx * 1.225, -1.45, 2.3), (0.02, 3.8, 0.5), "M_Paint")
    mb.box((0, -1.4, 0.72), (1.0, 4.6, 0.2), "M_MetalDark")


SPECS["boxtruck"] = dict(
    secs=[(-3.80, .62, 0.6, .80, 0.6, None, 0, 'body'), (1.02, .62, 0.6, .80, 0.6, None, 0, 'body'),
          (1.06, .50, 1.10, 1.35, 1.10, 2.45, 1.04, 'cab'),
          (2.25, .50, 1.10, 1.35, 1.10, 2.42, 1.0, 'ws'), (2.85, .50, 1.10, 1.32, 1.08, None, 0, 'body'),
          (3.30, .50, 1.08, 1.20, 1.04, None, 0, 'body'), (3.45, .64, 1.02, 1.10, 1.0, None, 0, 'end')],
    wheel_r=0.46, wheel_w=0.32, wheel_yf=2.45, wheel_yr=-2.5, mirror_y=2.3, cab=(1.1, 2.45), door=(1.25, 2.25),
    seats=[(-0.52, 1.65, 0.98), (0.52, 1.65, 0.98)], extra=boxtruck_extra, mods=False, bumper_z=0.68, light_z=1.0,
    tail_z=0.72, track=1.0, wheel_style="offroad")


def swat_extra(mb, secs):
    lightbar(mb, 1.0, 2.52, 1.2)
    pushbar(mb, 2.95, 0.5, 2.0)
    for sx in (-1, 1):
        mb.box((sx * 1.13, -1.2, 0.62), (0.16, 2.6, 0.08), "M_Black")
        for i in range(3):
            mb.box((sx * 1.115, -2.0 + i * 0.9, 1.75), (0.02, 0.5, 0.22), "M_Glass")
    mb.box((0, -2.96, 1.45), (1.5, 0.03, 1.7), "M_MetalDark")
    mb.box((0, -0.8, 2.56), (0.8, 0.8, 0.10), "M_MetalDark")


SPECS["swat"] = dict(
    secs=[(-2.95, .60, 1.04, 1.25, 1.08, 2.44, 1.0, 'pillar'), (-2.86, .42, 1.10, 1.30, 1.10, 2.50, 1.02, 'pillar'),
          (0.55, .42, 1.10, 1.30, 1.10, 2.50, 1.02, 'cab'), (1.25, .42, 1.10, 1.30, 1.10, 2.46, 1.0, 'ws'),
          (1.65, .42, 1.10, 1.28, 1.08, None, 0, 'body'), (2.75, .44, 1.08, 1.15, 1.04, None, 0, 'body'),
          (2.95, .60, 1.0, 1.0, 1.0, None, 0, 'end')],
    wheel_r=0.46, wheel_w=0.34, wheel_yf=1.95, wheel_yr=-1.85, mirror_y=1.3, cab=(0.5, 1.5), door=(0.58, 1.25),
    seats=[(-0.48, 0.85, 0.88), (0.48, 0.85, 0.88), (-0.48, -1.0, 0.9), (0.48, -1.0, 0.9)], extra=swat_extra,
    mods=False, bumper_z=0.62, light_z=0.95, tail_z=1.1, wheel_style="offroad")

built = []
for i, (vid, spec) in enumerate(SPECS.items()):
    if ONLY and vid not in ONLY:
        continue
    b = build_car(vid, spec, loc=(i * 4.0 - 20, 0, 0))
    built.append((vid, tri_count(b)))
print("built", built)
