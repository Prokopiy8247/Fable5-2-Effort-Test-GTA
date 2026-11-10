"""chr_accessories - hair, head-wear, eye-wear, vests, packs ... for human_male / human_female.

    import chr_accessories as A; importlib.reload(A)
    A.build_all()                      # every accessory on both characters (bodies must exist)
    A.build("human_female", ["hair_bob"])

Every accessory is its own object `<id>__acc_<name>`, material `Character`, skinned 100 % to ONE bone
(Head / Chest / Hips) and fitted to the profile tables of chr_bodies.SHAPES, so the same code dresses both
bodies.  Godot hides them unless equipped; in Blender they are left hidden (eye icon) to keep the scene tidy -
K.export_asset un-hides them for the export.

Construction: closed lofts of the body's own rounded-rectangle rings grown outward (`grow`), clamped in Y / X
where the shell must stay off the face or the arms (the clamped part runs through the inside of the body and
is never seen), plus a few chunky primitives.  Head-wear crowns are grown >= 22 mm so they enclose the normal
hair shells (<= 19 mm); afro / mohawk are bigger than any hat by design.
"""
import bpy
import math
from mathutils import Vector
import gta_kit as K
import chr_rig as R
import chr_bodies as B
from chr_bodies import (ULEG, HAIR, HEADWEAR, EYEWEAR, OVERLAY, DET_A, DET_B, rrect, row_at, head_row, torso_row)

SOFT = 0.03          # clamped ring points keep 3 % of their overshoot -> no zero-length edges


# --------------------------------------------------------------------------- ring helpers
def ring(row, grow=0.0, ymax=None, ymin=None, xmax=None, z=None, tilt=0.0, dx=0.0):
    out = []
    for x, y, zz in rrect(row, grow, z):
        if ymax is not None and y > ymax:
            y = ymax + (y - ymax) * SOFT
        if ymin is not None and y < ymin:
            y = ymin + (y - ymin) * SOFT
        if xmax is not None and abs(x) > xmax:
            x = math.copysign(xmax + (abs(x) - xmax) * SOFT, x)
        out.append((x + dx, y, zz + tilt * y))
    return out


def rowfb(z, rx, yf, yb, rnd=0.6):
    """Profile row from front / back extents (rounded corners)."""
    cy = (yf + yb) * 0.5
    ry = (yf - yb) * 0.5
    c = rnd * min(rx, ry)
    return (z, rx, ry, ry, c, c, cy)


def hd(sh, z, g=0.0, ymax=None, ymin=None):
    """Head ring at height z grown by g."""
    return ring(head_row(sh, z), g, ymax=ymax, ymin=ymin)


def hat(sh, z, g=0.0, zref=1.748, tilt=0.0):
    """Ring of the widest upper head row placed at height z (crowns that do not follow the skull taper)."""
    return ring(head_row(sh, zref), g, z=z, tilt=tilt)


def tor(sh, z, g=0.0, keys=("abdomen", "chest"), xmax=None, ymax=None, ymin=None):
    return ring(torso_row(sh, z, keys), g, xmax=xmax, ymax=ymax, ymin=ymin)


def front(sh, z, keys=("chest",)):
    r = torso_row(sh, z, keys)
    return r[6] + r[2]


def back(sh, z, keys=("chest",)):
    r = torso_row(sh, z, keys)
    return r[6] - r[3]


def solid(mb, rings, color, ring_colors=None):
    return mb.loft(rings, color, closed=True, cap_start=True, cap_end=True, ring_colors=ring_colors)


def band(mb, inner0, outer0, outer1, inner1, color):
    """Closed strap band (no caps): inner / outer ring at the bottom, outer / inner ring at the top."""
    return mb.loft([inner0, outer0, outer1, inner1], color, closed=True, cap_start=False, cap_end=False)


def ribbon(mb, x, path, w, t, color, sink=0.006):
    """Strap of half-width w and thickness t following a (y, z) polyline at lateral position x; the outer
    side is to the right of the travel direction (front going up -> over the top -> back going down)."""
    rings = []
    n = len(path)
    for i, (y, z) in enumerate(path):
        a = path[max(0, i - 1)]
        b = path[min(n - 1, i + 1)]
        ty, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ty, tz) or 1.0
        ny, nz = tz / ln, -ty / ln
        yi, zi = y - ny * sink, z - nz * sink
        yo, zo = y + ny * t, z + nz * t
        rings.append([(x - w, yi, zi), (x + w, yi, zi), (x + w, yo, zo), (x - w, yo, zo)])
    return mb.loft(rings, color, closed=True, cap_start=True, cap_end=True)


def ellipse(z, rx, ry, cy=0.0, n=12):
    return [(math.cos(2 * math.pi * k / n + math.pi / n) * rx, cy + math.sin(2 * math.pi * k / n + math.pi / n) * ry, z)
            for k in range(n)]


# --------------------------------------------------------------------------- hair (region 9)
def _cap_levels(g):
    """Close-cropped hair shell: nape -> behind the ears -> temples -> full crown."""
    return [(1.628, 0.003, -0.030), (1.655, g * 0.8, -0.025), (1.688, g * 0.9, -0.028), (1.690, g * 0.95, 0.030),
            (1.742, g, 0.048), (1.754, g + 0.001, None), (1.792, g + 0.001, None), (1.806 + g * 0.2, g * 0.75, None)]


def _skull_cap(mb, sh, g):
    solid(mb, [hd(sh, z, gg, ymax=ym) for z, gg, ym in _cap_levels(g)], HAIR)


def hair_short(mb, sh):
    _skull_cap(mb, sh, 0.013)
    mb.box((0.140, 0.050, 0.026), (0.0, 0.074, 1.772), HAIR, rot=(-20, 0, 0), bevel=0.011)      # short quiff


def hair_side(mb, sh):
    _skull_cap(mb, sh, 0.018)
    mb.box((0.135, 0.036, 0.032), (0.022, 0.103, 1.754), HAIR, rot=(-6, -12, 0), bevel=0.010)   # swept fringe
    mb.box((0.012, 0.150, 0.012), (-0.046, 0.0, 1.812), HAIR, rot=(0, 0, 4))                    # parting ridge


def hair_long(mb, sh):
    rings = [ring(rowfb(1.492, 0.092, -0.045, -0.135)),
             ring(rowfb(1.560, 0.106, 0.050, -0.140), ymax=-0.010),
             ring(rowfb(1.620, 0.108, 0.080, -0.132), ymax=0.022),
             hd(sh, 1.690, 0.015, ymax=0.036), hd(sh, 1.744, 0.016, ymax=0.050),
             hd(sh, 1.754, 0.017), hd(sh, 1.792, 0.017), hd(sh, 1.811, 0.012)]
    solid(mb, rings, HAIR)


def hair_pony(mb, sh):
    _skull_cap(mb, sh, 0.010)
    R.limb(mb, (0.0, -0.100, 1.735), (0.0, -0.215, 1.580),
           [(0.0, 0.028, 0.028, 0.028), (0.35, 0.037, 0.037, 0.037), (1.0, 0.013, 0.013, 0.013)], HAIR, n=6,
           ball0=1, ball1=1)
    mb.box((0.050, 0.030, 0.050), (0.0, -0.110, 1.722), HAIR, rot=(38, 0, 0), bevel=0.012)       # tie


def hair_afro(mb, sh):
    lv = [(1.630, 0.090, 0.000, -0.150, -0.040), (1.665, 0.138, 0.060, -0.172, -0.020),
          (1.705, 0.160, 0.100, -0.182, 0.022), (1.745, 0.168, 0.125, -0.185, 0.040),
          (1.757, 0.170, 0.138, -0.185, None), (1.815, 0.165, 0.135, -0.175, None),
          (1.865, 0.130, 0.100, -0.140, None), (1.895, 0.075, 0.050, -0.085, None)]
    solid(mb, [ring(rowfb(z, rx, yf, yb, 0.75), ymax=ym) for z, rx, yf, yb, ym in lv], HAIR)


def hair_mohawk(mb, sh):
    w = 0.022
    prof = [(0.098, 1.742, 1.764), (0.066, 1.760, 1.872), (0.020, 1.775, 1.908), (-0.030, 1.775, 1.902),
            (-0.076, 1.760, 1.876), (-0.108, 1.715, 1.802), (-0.124, 1.640, 1.712)]
    rings = [[(-w, y, zb), (w, y, zb), (w * 0.4, y, zt), (-w * 0.4, y, zt)] for y, zb, zt in prof]
    mb.loft(rings, HAIR, closed=True, cap_start=True, cap_end=True)


def hair_bun(mb, sh):
    _skull_cap(mb, sh, 0.010)
    mb.sphere(0.054, (0.0, -0.070, 1.822), HAIR, segs=8, rings=5, scale=(1.0, 1.0, 0.88))
    mb.cyl(0.036, 0.018, (0.0, -0.062, 1.800), HAIR, axis="Z", segs=8, rot=(28, 0, 0))


def hair_bob(mb, sh):
    rings = [ring(rowfb(1.572, 0.104, 0.045, -0.128), ymax=0.030),
             ring(rowfb(1.600, 0.110, 0.050, -0.134), ymax=0.040),
             hd(sh, 1.660, 0.018, ymax=0.048), hd(sh, 1.720, 0.018, ymax=0.055),
             hd(sh, 1.726, 0.019), hd(sh, 1.790, 0.019), hd(sh, 1.812, 0.013)]
    solid(mb, rings, HAIR)


def beard(mb, sh):
    lv = [(1.534, 0.004, 0.012), (1.556, 0.013, 0.000), (1.596, 0.013, -0.012), (1.630, 0.007, -0.020)]
    solid(mb, [hd(sh, z, g, ymin=ym) for z, g, ym in lv], HAIR)


def mustache(mb, sh):
    y = head_row(sh, 1.627)
    yf = y[6] + y[2]
    for s in (-1.0, 1.0):
        mb.box((0.038, 0.014, 0.013), (s * 0.019, yf + 0.004, 1.627), HAIR, rot=(0, s * 12.0, 0), bevel=0.004)


# --------------------------------------------------------------------------- head-wear (region 11)
def _brim(mb, pts, z, thick, droop, color, y0):
    with mb.at((0.0, y0, z), rot=(-droop, 0, 0)):
        mb.prism([(x, y - y0) for x, y in pts], thick, color, plane="XY", center=False)


def cap(mb, sh):
    solid(mb, [hat(sh, 1.728, 0.016), hat(sh, 1.742, 0.024), hat(sh, 1.786, 0.022), hat(sh, 1.812, 0.004),
               hat(sh, 1.822, -0.030)], HEADWEAR)
    _brim(mb, [(-0.094, 0.075), (0.094, 0.075), (0.092, 0.165), (0.060, 0.218), (-0.060, 0.218), (-0.092, 0.165)],
          1.730, 0.012, 7.0, HEADWEAR, 0.10)
    mb.box((0.022, 0.022, 0.008), (0.0, -0.002, 1.825), HEADWEAR, bevel=0.003)


def beanie(mb, sh):
    solid(mb, [hat(sh, 1.722, 0.022), hat(sh, 1.726, 0.032), hat(sh, 1.760, 0.032), hat(sh, 1.764, 0.026),
               hat(sh, 1.800, 0.022), hat(sh, 1.828, 0.008), hat(sh, 1.848, -0.016), hat(sh, 1.861, -0.044),
               hat(sh, 1.867, -0.072)], HEADWEAR)
    mb.sphere(0.026, (0.0, -0.004, 1.878), HEADWEAR, segs=6, rings=4)                             # bobble


def hat_brim(mb, sh):
    solid(mb, [hat(sh, 1.735, 0.022), hat(sh, 1.800, 0.018), hat(sh, 1.824, 0.008), hat(sh, 1.830, -0.020)],
          HEADWEAR)
    band(mb, hat(sh, 1.752, 0.016), hat(sh, 1.752, 0.027), hat(sh, 1.772, 0.026), hat(sh, 1.772, 0.016), DET_A)
    mb.loft([ellipse(1.750, 0.095, 0.110), ellipse(1.740, 0.215, 0.240), ellipse(1.728, 0.215, 0.240),
             ellipse(1.738, 0.095, 0.110)], HEADWEAR, closed=True, cap_start=False, cap_end=False)


def cap_police(mb, sh):
    t = 0.10
    solid(mb, [hat(sh, 1.730, 0.020), hat(sh, 1.768, 0.021), hat(sh, 1.775, 0.030, tilt=t),
               hat(sh, 1.812, 0.050, tilt=t), hat(sh, 1.824, 0.040, tilt=t), hat(sh, 1.828, 0.000, tilt=t)],
          HEADWEAR)
    _brim(mb, [(-0.087, 0.085), (0.087, 0.085), (0.080, 0.152), (0.046, 0.182), (-0.046, 0.182), (-0.080, 0.152)],
          1.731, 0.010, 15.0, HEADWEAR, 0.10)
    r = head_row(sh, 1.748)
    mb.box((0.032, 0.012, 0.036), (0.0, r[6] + r[2] + 0.042, 1.802), DET_A, rot=(-8, 0, 0), bevel=0.005)


def helmet_tactical(mb, sh):
    solid(mb, [hd(sh, 1.622, 0.020, ymax=-0.028), hd(sh, 1.660, 0.030, ymax=0.012), hd(sh, 1.700, 0.033, ymax=0.034),
               hd(sh, 1.732, 0.034, ymax=0.060), hat(sh, 1.742, 0.035), hat(sh, 1.792, 0.030),
               hat(sh, 1.826, 0.008), hat(sh, 1.842, -0.030)], HEADWEAR)
    band(mb, hat(sh, 1.760, 0.028), hat(sh, 1.760, 0.039), hat(sh, 1.782, 0.039), hat(sh, 1.782, 0.028), EYEWEAR)
    r = head_row(sh, 1.748)
    yf = r[6] + r[2] + 0.035
    mb.box((0.150, 0.036, 0.046), (0.0, yf + 0.012, 1.772), EYEWEAR, bevel=0.010)
    for s in (-1.0, 1.0):
        mb.box((0.058, 0.010, 0.030), (s * 0.036, yf + 0.032, 1.772), EYEWEAR, bevel=0.004)


def helmet_moto(mb, sh):
    rows = [(1.515, 0.075, 0.095, 0.085, 0.050, 0.050, 0.012), (1.535, 0.105, 0.128, 0.110, 0.060, 0.060, 0.012),
            (1.600, 0.122, 0.146, 0.128, 0.065, 0.070, 0.008), (1.655, 0.128, 0.152, 0.138, 0.065, 0.075, 0.004),
            (1.725, 0.130, 0.152, 0.142, 0.065, 0.078, 0.002), (1.780, 0.122, 0.136, 0.134, 0.070, 0.078, 0.000),
            (1.820, 0.095, 0.104, 0.108, 0.060, 0.066, -0.002), (1.842, 0.050, 0.055, 0.060, 0.035, 0.035, -0.002)]
    faces = solid(mb, [ring(r) for r in rows], HEADWEAR)
    mb.repaint(faces, EYEWEAR, lambda c: 1.655 < c.z < 1.725 and c.y > 0.045)
    mb.box((0.090, 0.016, 0.026), (0.0, 0.150, 1.585), DET_B, bevel=0.005)                         # chin vent


# --------------------------------------------------------------------------- eye-wear / face (region 12)
def _temples(mb, z, y_front, color):
    for s in (-1.0, 1.0):
        mb.box((0.036, 0.008, 0.008), (s * 0.084, y_front, z), color)                    # frame end piece
        mb.box((0.006, 0.136, 0.008), (s * 0.101, y_front - 0.066, z), color)            # arm to the ear


def glasses(mb, sh):
    yf, z, w, h, t = 0.127, 1.688, 0.054, 0.038, 0.006
    for s in (-1.0, 1.0):
        x = s * 0.040
        mb.box((w, 0.008, t), (x, yf, z + h * 0.5), EYEWEAR)
        mb.box((w, 0.008, t), (x, yf, z - h * 0.5), EYEWEAR)
        mb.box((t, 0.008, h + t), (x - w * 0.5, yf, z), EYEWEAR)
        mb.box((t, 0.008, h + t), (x + w * 0.5, yf, z), EYEWEAR)
    mb.box((0.028, 0.008, t), (0.0, yf, z + 0.008), EYEWEAR)
    _temples(mb, z + 0.008, yf, EYEWEAR)


def sunglasses(mb, sh):
    yf, z = 0.127, 1.688
    for s in (-1.0, 1.0):
        mb.box((0.060, 0.010, 0.040), (s * 0.039, yf, z), EYEWEAR, bevel=0.006, taper=(1.0, 1.0))
    mb.box((0.024, 0.008, 0.008), (0.0, yf, z + 0.010), EYEWEAR)
    _temples(mb, z + 0.010, yf, EYEWEAR)


def bandana(mb, sh):
    lv = [(1.528, 0.062, 0.122, -0.060), (1.575, 0.090, 0.143, -0.088), (1.640, 0.106, 0.153, -0.110),
          (1.668, 0.106, 0.137, -0.116)]
    solid(mb, [ring(rowfb(z, rx, yf, yb, 0.7)) for z, rx, yf, yb in lv], EYEWEAR)
    mb.box((0.050, 0.030, 0.034), (0.018, -0.126, 1.628), EYEWEAR, bevel=0.008)                  # knot
    mb.box((0.022, 0.012, 0.070), (0.030, -0.132, 1.580), EYEWEAR, rot=(8, 0, 14))
    mb.box((0.022, 0.012, 0.060), (0.004, -0.134, 1.586), EYEWEAR, rot=(8, 0, -10))


def scuba_mask(mb, sh):
    mb.box((0.158, 0.046, 0.068), (0.0, 0.131, 1.688), EYEWEAR, bevel=0.012)
    mb.box((0.132, 0.008, 0.044), (0.0, 0.157, 1.690), DET_B, bevel=0.006)                        # lens
    mb.box((0.046, 0.050, 0.034), (0.0, 0.138, 1.647), EYEWEAR, bevel=0.008)                      # nose pocket
    band(mb, hd(sh, 1.672, -0.004), hd(sh, 1.672, 0.011), hd(sh, 1.700, 0.011), hd(sh, 1.700, -0.004), EYEWEAR)


# --------------------------------------------------------------------------- torso (bone Chest)
def _vest_shell(mb, sh, levels, color):
    return solid(mb, [tor(sh, z, g, xmax=xm) for z, g, xm in levels], color)


def vest_tactical(mb, sh):
    _vest_shell(mb, sh, [(1.195, 0.014, None), (1.215, 0.024, None), (1.360, 0.026, None), (1.385, 0.026, 0.150),
                         (1.400, 0.026, 0.132), (1.468, 0.022, 0.125), (1.478, 0.010, 0.112)], OVERLAY)
    yf = front(sh, 1.262, ("abdomen", "chest")) + 0.026
    for x in (-0.078, 0.0, 0.078):
        mb.box((0.058, 0.032, 0.090), (x, yf + 0.012, 1.262), DET_B, bevel=0.007)                 # magazine pouches
    mb.box((0.150, 0.014, 0.050), (0.0, front(sh, 1.40) + 0.030, 1.400), DET_B, bevel=0.005)      # name panel
    mb.box((0.044, 0.034, 0.078), (-0.092, front(sh, 1.345) + 0.036, 1.345), DET_B, bevel=0.007)  # radio
    mb.box((0.215, 0.024, 0.215), (0.0, back(sh, 1.35) - 0.034, 1.345), OVERLAY, bevel=0.010)     # back plate
    mb.box((0.090, 0.016, 0.022), (0.0, back(sh, 1.45) - 0.030, 1.452), DET_B, bevel=0.004)       # drag handle
    for s in (-1.0, 1.0):                                                                          # shoulder pads
        mb.box((0.062, 0.110, 0.020), (s * 0.098, 0.0, 1.492), OVERLAY, bevel=0.007)


def vest_safety(mb, sh):
    _vest_shell(mb, sh, [(1.165, 0.006, None), (1.180, 0.013, None), (1.360, 0.014, None), (1.385, 0.014, 0.150),
                         (1.400, 0.014, 0.128), (1.470, 0.012, 0.118), (1.478, 0.004, 0.108)], OVERLAY)
    for z0 in (1.215, 1.292):                                                                      # reflective tape
        band(mb, tor(sh, z0, 0.008), tor(sh, z0, 0.019), tor(sh, z0 + 0.030, 0.019), tor(sh, z0 + 0.030, 0.008),
             DET_B)
    for s in (-1.0, 1.0):
        ribbon(mb, s * 0.088, [(front(sh, z) + 0.012, z) for z in (1.325, 1.39, 1.445, 1.474)], 0.014, 0.006, DET_B,
               sink=0.004)


def tie(mb, sh):
    prof = [(1.472, 0.016), (1.450, 0.026), (1.425, 0.017), (1.385, 0.022), (1.310, 0.030), (1.245, 0.034),
            (1.205, 0.004)]
    rings = []
    for z, w in prof:
        y0 = front(sh, z, ("abdomen", "chest")) - 0.004
        rings.append([(-w, y0, z), (w, y0, z), (w, y0 + 0.014, z), (-w, y0 + 0.014, z)])
    mb.loft(rings, DET_A, closed=True, cap_start=True, cap_end=True)


def badge(mb, sh):
    y = front(sh, 1.405)
    mb.box((0.038, 0.008, 0.044), (-0.085, y + 0.002, 1.405), DET_A, bevel=0.006, taper=(1.0, 1.0))
    mb.box((0.018, 0.006, 0.020), (-0.085, y + 0.006, 1.407), DET_B, bevel=0.003)


def _harness(mb, sh, x, color, w=0.017, low=1.235):
    path = [(front(sh, z) + 0.002, z) for z in (low, 1.31, 1.39, 1.445)]
    path += [(0.086, 1.479), (0.025, 1.503), (-0.045, 1.502), (-0.092, 1.478), (back(sh, 1.43) - 0.002, 1.43)]
    for s in (-1.0, 1.0):
        ribbon(mb, s * x, path, w, 0.010, color)


def backpack_chute(mb, sh):
    yb = back(sh, 1.36)
    mb.box((0.270, 0.105, 0.350), (0.0, yb - 0.046, 1.335), OVERLAY, bevel=0.022)
    mb.box((0.230, 0.050, 0.130), (0.0, yb - 0.108, 1.300), OVERLAY, bevel=0.016)                 # reserve pocket
    mb.box((0.200, 0.020, 0.030), (0.0, yb - 0.100, 1.455), DET_B, bevel=0.005)                   # top flap
    _harness(mb, sh, 0.095, OVERLAY)
    yf = front(sh, 1.365)
    mb.box((0.215, 0.012, 0.026), (0.0, yf + 0.004, 1.365), OVERLAY)                               # chest strap
    mb.box((0.040, 0.016, 0.036), (0.0, yf + 0.008, 1.365), DET_B, bevel=0.004)                    # buckle
    mb.box((0.026, 0.022, 0.050), (0.098, front(sh, 1.30) + 0.016, 1.300), DET_B, bevel=0.006)     # rip-cord handle


def scuba_tank(mb, sh):
    yb = back(sh, 1.36)
    yc = yb - 0.092
    mb.cyl(0.078, 0.420, (0.0, yc, 1.300), OVERLAY, axis="Z", segs=10)
    mb.sphere(0.078, (0.0, yc, 1.510), OVERLAY, segs=10, rings=6, scale=(1.0, 1.0, 0.75))
    mb.sphere(0.078, (0.0, yc, 1.090), OVERLAY, segs=10, rings=6, scale=(1.0, 1.0, 0.35))
    mb.cyl(0.022, 0.050, (0.0, yc, 1.585), DET_B, axis="Z", segs=8)                               # valve
    mb.box((0.085, 0.030, 0.030), (0.0, yc, 1.612), DET_B, bevel=0.007)
    mb.box((0.190, 0.022, 0.300), (0.0, yb - 0.012, 1.330), DET_B, bevel=0.008)                   # back plate
    for z in (1.20, 1.40):
        mb.box((0.170, 0.012, 0.028), (0.0, yc + 0.004, z), DET_B, bevel=0.0)                      # tank bands
        mb.cyl(0.082, 0.028, (0.0, yc, z), DET_B, axis="Z", segs=10)
    _harness(mb, sh, 0.095, OVERLAY, low=1.25)
    mb.tube([(0.03, yc, 1.612), (0.085, yc + 0.03, 1.60), (0.135, -0.03, 1.535), (0.140, 0.06, 1.50),
             (0.118, front(sh, 1.43) + 0.014, 1.43), (0.090, front(sh, 1.385) + 0.022, 1.385)], 0.010, DET_B, segs=5)
    mb.box((0.040, 0.030, 0.034), (0.086, front(sh, 1.37) + 0.026, 1.370), DET_B, bevel=0.008)     # regulator


# --------------------------------------------------------------------------- hips (bone Hips)
def holster(mb, sh):
    r = torso_row(sh, 1.00, ("pelvis",))
    x = r[1] + 0.016
    with mb.at((x, -0.020, 0.985), rot=(-12, 0, -4)):
        mb.box((0.042, 0.082, 0.150), (0.0, 0.0, 0.0), DET_A, bevel=0.010, taper=(1.0, 1.0))
        mb.box((0.034, 0.050, 0.070), (0.0, -0.030, 0.092), DET_A, bevel=0.010)                    # pistol grip
        mb.box((0.012, 0.086, 0.030), (0.020, 0.0, 0.050), DET_A)                                  # retention strap
    mb.box((0.012, 0.060, 0.070), (r[1] + 0.004, -0.020, 1.060), DET_A)                            # belt loop


def skirt(mb, sh):
    b = sh["belt"]
    rings = [tor(sh, b["z0"] + 0.004, 0.004, keys=("pelvis",)), tor(sh, b["z0"] - 0.004, 0.014, keys=("pelvis",)),
             tor(sh, 0.950, 0.022, keys=("pelvis",)),
             ring(rowfb(0.860, 0.218, 0.152, -0.162, 0.5)), ring(rowfb(0.780, 0.236, 0.174, -0.182, 0.5))]
    solid(mb, rings, ULEG)


# name -> (builder, bone, regions, smooth angle)
ACCESSORIES = [
    ("hair_short", hair_short, "Head", [9], 50), ("hair_side", hair_side, "Head", [9], 50),
    ("hair_long", hair_long, "Head", [9], 50), ("hair_pony", hair_pony, "Head", [9], 50),
    ("hair_afro", hair_afro, "Head", [9], 60), ("hair_mohawk", hair_mohawk, "Head", [9], 30),
    ("hair_bun", hair_bun, "Head", [9], 50), ("hair_bob", hair_bob, "Head", [9], 50),
    ("beard", beard, "Head", [9], 50), ("mustache", mustache, "Head", [9], 40),
    ("cap", cap, "Head", [11], 50), ("beanie", beanie, "Head", [11], 50), ("hat_brim", hat_brim, "Head", [11, 14], 50),
    ("cap_police", cap_police, "Head", [11, 14], 45), ("helmet_tactical", helmet_tactical, "Head", [11, 12], 50),
    ("helmet_moto", helmet_moto, "Head", [11, 12, 15], 55), ("glasses", glasses, "Head", [12], 30),
    ("sunglasses", sunglasses, "Head", [12], 30), ("bandana", bandana, "Head", [12], 50),
    ("scuba_mask", scuba_mask, "Head", [12, 15], 40),
    ("vest_tactical", vest_tactical, "Chest", [13, 15], 45), ("vest_safety", vest_safety, "Chest", [13, 15], 45),
    ("tie", tie, "Chest", [14], 40), ("badge", badge, "Chest", [14, 15], 30),
    ("backpack_chute", backpack_chute, "Chest", [13, 15], 40), ("scuba_tank", scuba_tank, "Chest", [13, 15], 45),
    ("holster", holster, "Hips", [14], 40), ("skirt", skirt, "Hips", [6], 50),
]
NAMES = [a[0] for a in ACCESSORIES]


def build(asset_id, names=None, hide=True):
    """(Re)build accessories of one character -> [(name, tris)]."""
    sh = B.SHAPES[asset_id]
    root = bpy.data.objects[asset_id]
    rig = R.get_rig(asset_id)
    out = []
    for name, fn, bone, _regions, angle in ACCESSORIES:
        if names is not None and name not in names:
            continue
        part = "acc_" + name
        R.remove_part(asset_id, part)
        mb = R.SkinMB()
        mb.bone(bone)
        fn(mb, sh)
        tris = mb.tri_count()
        obj = mb.to_skinned(root, rig, part, sharp_angle=angle)
        obj["gta_tris"] = tris
        obj["gta_bone"] = bone
        try:
            obj.hide_set(hide)
        except Exception:
            pass
        out.append((name, tris))
    return out


def build_all(names=None):
    return {a: build(a, names) for a in B.CHARACTERS}


def show_only(asset_id, names):
    """QA: un-hide exactly the given accessories of a character (None = hide all)."""
    names = set(names or [])
    for n in NAMES:
        o = bpy.data.objects.get("%s__acc_%s" % (asset_id, n))
        if o is not None:
            o.hide_set(n not in names)


def contact_sheet(asset_id, groups):
    """QA: key `hide_viewport` so that frame i shows only the accessories of groups[i] (look mode 'frames')."""
    objs = {n: bpy.data.objects.get("%s__acc_%s" % (asset_id, n)) for n in NAMES}
    for n, o in objs.items():
        if o is None:
            continue
        o.animation_data_clear()
        o.hide_set(False)
        for i, g in enumerate(groups):
            o.hide_viewport = n not in g
            o.keyframe_insert("hide_viewport", frame=i)
    return len(groups)


def end_contact_sheet(asset_id):
    for n in NAMES:
        o = bpy.data.objects.get("%s__acc_%s" % (asset_id, n))
        if o is None:
            continue
        ad = o.animation_data
        act = ad.action if ad else None
        o.animation_data_clear()
        if act is not None and act.users == 0:
            bpy.data.actions.remove(act)
        o.hide_viewport = False
        o.hide_set(True)
