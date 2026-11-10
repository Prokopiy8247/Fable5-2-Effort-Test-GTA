"""bld_signs - P2 neon signs (single part `mesh`, glb buildings/signs/<id>). See SPEC_BUILDINGS.md.

Fascia signs: origin = bottom centre on the wall plane, <= 3.6 x 0.9 x 0.25, dark backing board + 3D text in ONE neon
colour + simple pictogram. Blade signs: origin on the wall plane, panel in the YZ plane, text on both faces.
"""
import math
from mathutils import Vector
import gta_kit as K
import bld_common as B
import bld_qa as Q
from bld_common import fq, q, fbox

D = 0.08                                 # backing board thickness
FASCIA = ["sign_cafe", "sign_bar", "sign_pizza", "sign_pawn", "sign_24h", "sign_market", "sign_tattoo", "sign_arcade",
          "sign_diner", "sign_gym", "sign_books", "sign_noodles", "sign_club", "sign_laundry", "sign_bank", "sign_taxi"]
BLADES = ["sign_blade_hotel", "sign_blade_motel", "sign_open"]
IDS = FASCIA + BLADES
_tw = {}


def text_w(text):
    """Width of `text` at size 1.0 (measured once)."""
    if text not in _tw:
        mb = K.MB()
        K.add_text(mb, text, size=1.0, depth=0.0, color="white", res=1)
        xs = [v.co.x for v in mb.bm.verts]
        _tw[text] = max(xs) - min(xs)
        mb.bm.free()
    return _tw[text]


def ntube(mb, pts, y, col, r=0.02, closed=False, segs=4):
    """Neon tube along 2D (x, z) points lying in the plane Y = y (diamond section, mitred, never twists)."""
    p3 = [Vector((p[0], y, p[1])) for p in pts]
    n = len(p3)
    side = Vector((0.0, 1.0, 0.0))
    rings = []
    for i in range(n):
        a = p3[(i - 1) % n] if closed else p3[max(i - 1, 0)]
        b = p3[(i + 1) % n] if closed else p3[min(i + 1, n - 1)]
        din = p3[i] - a
        dout = b - p3[i]
        if din.length < 1e-9:
            din = dout.copy()
        if dout.length < 1e-9:
            dout = din.copy()
        din.normalize()
        dout.normalize()
        d = din + dout
        if d.length < 1e-6:
            d = dout.copy()
        d.normalize()
        k = 1.0 / max(0.5, d.dot(dout))
        up = side.cross(d)
        rings.append([tuple(p3[i] + side * (math.cos(2 * math.pi * j / segs) * r)
                            + up * (math.sin(2 * math.pi * j / segs) * r * k)) for j in range(segs)])
    if closed:
        rings.append(list(rings[0]))
    mb.loft(rings, col, closed=True, cap_start=not closed, cap_end=not closed, smooth=False)


def circle(cx, cz, r, n=8, a0=0.0):
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / n), cz + r * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


# ----------------------------------------------------------------------------- board outlines (x, z)
def shp_rect(w, h, c=0.04):
    return [(-w / 2 + c, 0), (w / 2 - c, 0), (w / 2, c), (w / 2, h - c), (w / 2 - c, h), (-w / 2 + c, h),
            (-w / 2, h - c), (-w / 2, c)]


def shp_oct(w, h):
    return shp_rect(w, h, 0.2)


def shp_caps(w, h, n=5):
    r = h / 2
    pts = []
    for i in range(n + 1):
        a = math.radians(-90 + 180 * i / n)
        pts.append((w / 2 - r + r * math.cos(a), r + r * math.sin(a)))
    for i in range(n + 1):
        a = math.radians(90 + 180 * i / n)
        pts.append((-w / 2 + r + r * math.cos(a), r + r * math.sin(a)))
    return pts


def shp_arch(w, h, bump=0.14):
    hb = h - bump
    return [(-w / 2, 0), (w / 2, 0), (w / 2, hb), (w * 0.3, hb), (w * 0.22, h), (-w * 0.22, h), (-w * 0.3, hb),
            (-w / 2, hb)]


def shp_arrow(w, h, tip=0.4):
    return [(-w / 2, h / 2), (-w / 2 + tip, 0), (w / 2, 0), (w / 2, h), (-w / 2 + tip, h)]


def shp_ticket(w, h, n=0.12):
    return [(-w / 2 + n, 0), (w / 2 - n, 0), (w / 2 - n, n), (w / 2, n), (w / 2, h - n), (w / 2 - n, h - n),
            (w / 2 - n, h), (-w / 2 + n, h), (-w / 2 + n, h - n), (-w / 2, h - n), (-w / 2, n), (-w / 2 + n, n)]


def shp_gable(w, h, g=0.16):
    hb = h - g
    return [(-w / 2, 0), (w / 2, 0), (w / 2, hb), (0, h), (-w / 2, hb)]


SHAPES = {"rect": shp_rect, "oct": shp_oct, "caps": shp_caps, "arch": shp_arch, "arrow": shp_arrow,
          "ticket": shp_ticket, "gable": shp_gable}
TOPCUT = {"arch": 0.14, "gable": 0.16}          # height lost to the shaped top
SIDEPAD = {"caps": 0.3, "oct": 0.26, "arrow": 0.4, "ticket": 0.26}


# ----------------------------------------------------------------------------- pictograms (centre x, z; ~0.56 wide)
def p_cup(mb, x, z, y, c):
    ntube(mb, [(x - 0.17, z + 0.1), (x - 0.13, z - 0.2), (x + 0.13, z - 0.2), (x + 0.17, z + 0.1)], y, c, closed=True)
    ntube(mb, [(x - 0.17, z + 0.04), (x - 0.27, z + 0.02), (x - 0.27, z - 0.09), (x - 0.15, z - 0.11)], y, c, 0.016)
    for dx in (-0.06, 0.06):
        ntube(mb, [(x + dx, z + 0.16), (x + dx + 0.04, z + 0.23), (x + dx, z + 0.3)], y, c, 0.014)


def p_glass(mb, x, z, y, c):
    ntube(mb, [(x - 0.2, z + 0.24), (x + 0.2, z + 0.24), (x, z)], y, c, closed=True)
    ntube(mb, [(x, z), (x, z - 0.24)], y, c)
    ntube(mb, [(x - 0.12, z - 0.24), (x + 0.12, z - 0.24)], y, c)
    ntube(mb, [(x - 0.04, z + 0.12), (x - 0.2, z + 0.34)], y, c, 0.014)


def p_slice(mb, x, z, y, c):
    ntube(mb, [(x - 0.23, z + 0.22), (x + 0.23, z + 0.22), (x, z - 0.27)], y, c, closed=True)
    for dx, dz in ((-0.08, 0.1), (0.07, 0.09), (0.0, -0.06)):
        mb.box((0.06, 0.03, 0.06), (x + dx, y, z + dz), c, rot=(0, 45, 0))


def p_balls(mb, x, z, y, c):
    ntube(mb, [(x - 0.22, z + 0.27), (x + 0.22, z + 0.27)], y, c)
    for dx, dz in ((-0.17, 0.06), (0.17, 0.06), (0.0, -0.14)):
        ntube(mb, [(x + dx, z + 0.27), (x + dx, z + dz + 0.08)], y, c, 0.012)
        mb.ico(0.09, (x + dx, y + 0.03, z + dz), c, subdiv=1)


def p_clock(mb, x, z, y, c):
    ntube(mb, circle(x, z, 0.25, 8, math.pi / 8), y, c, closed=True)
    ntube(mb, [(x, z), (x, z + 0.16)], y, c, 0.016)
    ntube(mb, [(x, z), (x - 0.11, z - 0.05)], y, c, 0.016)


def p_basket(mb, x, z, y, c):
    ntube(mb, [(x - 0.23, z + 0.04), (x - 0.15, z - 0.23), (x + 0.15, z - 0.23), (x + 0.23, z + 0.04)], y, c,
          closed=True)
    ntube(mb, [(x - 0.15, z + 0.04), (x - 0.08, z + 0.25), (x + 0.08, z + 0.25), (x + 0.15, z + 0.04)], y, c, 0.016)
    for dx in (-0.08, 0.08):
        ntube(mb, [(x + dx, z - 0.02), (x + dx * 0.8, z - 0.17)], y, c, 0.012)


def p_star(mb, x, z, y, c):
    pts = []
    for i in range(10):
        rr = 0.28 if i % 2 == 0 else 0.12
        a = math.pi / 2 + i * math.pi / 5
        pts.append((x + rr * math.cos(a), z + rr * math.sin(a) - 0.01))
    ntube(mb, pts, y, c, 0.018, closed=True)


def p_joystick(mb, x, z, y, c):
    mb.box((0.44, 0.05, 0.11), (x, y + 0.01, z - 0.2), c)
    ntube(mb, [(x + 0.06, z - 0.14), (x + 0.01, z + 0.14)], y + 0.01, c, 0.024)
    mb.ico(0.085, (x, y + 0.02, z + 0.19), c, subdiv=1)
    mb.box((0.07, 0.04, 0.05), (x - 0.13, y + 0.01, z - 0.12), c)


def p_dumbbell(mb, x, z, y, c):
    ntube(mb, [(x - 0.28, z), (x + 0.28, z)], y, c, 0.022)
    for s in (-1, 1):
        mb.box((0.06, 0.05, 0.3), (x + s * 0.16, y + 0.005, z), c)
        mb.box((0.05, 0.05, 0.2), (x + s * 0.23, y + 0.005, z), c)


def p_book(mb, x, z, y, c):
    for s in (-1, 1):
        ntube(mb, [(x, z - 0.2), (x + s * 0.27, z - 0.13), (x + s * 0.27, z + 0.2), (x, z + 0.13)], y, c, 0.018)
    ntube(mb, [(x, z - 0.2), (x, z + 0.13)], y, c, 0.018)


def p_bowl(mb, x, z, y, c):
    ntube(mb, [(x - 0.25, z), (x - 0.14, z - 0.22), (x + 0.14, z - 0.22), (x + 0.25, z)], y, c, closed=True)
    ntube(mb, [(x + 0.06, z + 0.02), (x - 0.2, z + 0.3)], y, c, 0.013)
    ntube(mb, [(x - 0.02, z + 0.02), (x - 0.26, z + 0.25)], y, c, 0.013)
    ntube(mb, [(x + 0.14, z + 0.08), (x + 0.18, z + 0.16), (x + 0.14, z + 0.24)], y, c, 0.013)


def p_sparkle(mb, x, z, y, c):
    k, m = 0.29, 0.07
    ntube(mb, [(x, z + k), (x + m, z + m), (x + k, z), (x + m, z - m), (x, z - k), (x - m, z - m), (x - k, z),
               (x - m, z + m)], y, c, 0.018, closed=True)


def p_washer(mb, x, z, y, c):
    ntube(mb, [(x - 0.22, z - 0.26), (x + 0.22, z - 0.26), (x + 0.22, z + 0.26), (x - 0.22, z + 0.26)], y, c,
          closed=True)
    ntube(mb, circle(x, z - 0.05, 0.12, 6), y, c, 0.016, closed=True)
    ntube(mb, [(x - 0.14, z + 0.17), (x + 0.14, z + 0.17)], y, c, 0.012)


def p_temple(mb, x, z, y, c):
    ntube(mb, [(x - 0.27, z + 0.1), (x + 0.27, z + 0.1), (x, z + 0.28)], y, c, 0.018, closed=True)
    for dx in (-0.17, 0.0, 0.17):
        mb.box((0.06, 0.04, 0.26), (x + dx, y, z - 0.07), c)
    mb.box((0.54, 0.04, 0.05), (x, y, z - 0.235), c)


PICTS = {"cup": p_cup, "glass": p_glass, "slice": p_slice, "balls": p_balls, "clock": p_clock, "basket": p_basket,
         "star": p_star, "joystick": p_joystick, "dumbbell": p_dumbbell, "book": p_book, "bowl": p_bowl,
         "sparkle": p_sparkle, "washer": p_washer, "temple": p_temple}

# id: (text, neon colour, board shape, board colour, pictogram, neon border)
SPEC = {
    "sign_cafe": ("CAFE", "neon_orange", "caps", "charcoal", "cup", False),
    "sign_bar": ("BAR", "neon_pink", "ticket", "black", "glass", True),
    "sign_pizza": ("PIZZA", "neon_red", "oct", "charcoal", "slice", False),
    "sign_pawn": ("PAWN", "neon_yellow", "rect", "black", "balls", False),
    "sign_24h": ("24H", "neon_green", "caps", "black", "clock", True),
    "sign_market": ("MARKET", "neon_cyan", "arch", "navy", "basket", False),
    "sign_tattoo": ("TATTOO", "neon_purple", "oct", "black", "star", False),
    "sign_arcade": ("ARCADE", "neon_purple", "ticket", "navy", "joystick", False),
    "sign_diner": ("DINER", "neon_red", "arrow", "charcoal", None, True),
    "sign_gym": ("GYM", "neon_blue", "rect", "gunmetal", "dumbbell", True),
    "sign_books": ("BOOKS", "neon_blue", "arch", "charcoal", "book", False),
    "sign_noodles": ("NOODLES", "neon_orange", "rect", "maroon", "bowl", False),
    "sign_club": ("CLUB", "neon_pink", "oct", "black", "sparkle", True),
    "sign_laundry": ("LAUNDRY", "neon_cyan", "arch", "charcoal", "washer", False),
    "sign_bank": ("BANK", "neon_green", "gable", "gunmetal", "temple", False),
    "sign_taxi": ("TAXI", "neon_yellow", "rect", "black", None, False),
}


def fascia(aid):
    text, col, shape, bcol, pict, border = SPEC[aid]
    mb = K.MB()
    h = 0.9
    uh = h - TOPCUT.get(shape, 0.0)                       # usable height
    m = SIDEPAD.get(shape, 0.18)
    pw, gap = (0.58, 0.14) if pict else (0.0, 0.0)
    size = min(0.66, (3.6 - 2 * m - pw - gap) / text_w(text))
    tw = text_w(text) * size
    bw = min(3.6, tw + pw + gap + 2 * m)
    pts = SHAPES[shape](bw, h)
    mb.prism(pts, D, "steel_dark", plane="XZ", center=False, caps=(False, True), cap_colors=(bcol, bcol))
    zc = uh / 2
    off = -0.2 if shape == "arrow" else 0.0               # keep clear of the arrow tip (at -X)
    px = bw / 2 - m - pw / 2
    tx = (px - pw / 2 - gap - tw / 2) if pict else -off
    K.add_text(mb, text, size=size, depth=0.05, color=col, pos=(tx, D, zc - 0.35 * size), res=2)
    if pict:
        PICTS[pict](mb, px, zc, D + 0.02, col)
    if border:
        sx, sz = (bw - 0.13) / bw, (h - 0.13) / h
        ntube(mb, [(p[0] * sx, h / 2 + (p[1] - h / 2) * sz) for p in pts], D + 0.014, col, 0.014, closed=True)
    if aid == "sign_taxi":                                # checker strips
        n = int((bw - 0.3) / 0.1)
        for zz in (0.07, h - 0.17):
            for i in range(n):
                if i % 2 == 0:
                    x0 = -n * 0.05 + i * 0.1
                    q(mb, x0, x0 + 0.1, zz, zz + 0.1, col, D + 0.008)
    r = B.begin(aid, glb="buildings/signs/" + aid, spacing=5.0,
                notes="fascia sign %.2f x %.2f: origin bottom centre on the wall plane; '%s' in %s"
                      % (bw, h, text, col))
    mb.to_object(r, "mesh")
    return r


# ----------------------------------------------------------------------------- blade signs
def blade(aid, text, col, w=1.0, h=5.0, bcol="charcoal", foot=0.0, crown=True):
    r = B.begin(aid, glb="buildings/signs/" + aid, spacing=5.0,
                notes="blade sign %.1f x %.1f: origin on the wall plane at the blade's bottom; panel in the YZ plane "
                      "(Y +0.2..+%.1f), '%s' stacked vertically on both faces" % (w, h, w + 0.2, text))
    mb = K.MB()
    T, y0 = 0.2, 0.2
    y1 = y0 + w
    yc = (y0 + y1) / 2
    S = "steel_dark"
    fbox(mb, -T / 2, T / 2, y0, y1, 0.0, h, bcol, skip="")
    fbox(mb, -T / 2 - 0.015, T / 2 + 0.015, y1 - 0.02, y1 + 0.03, 0.0, h, S, skip="-y")           # outer edge trim
    if crown:
        fbox(mb, -T / 2 - 0.02, T / 2 + 0.02, y0 - 0.02, y1 + 0.04, h, h + 0.08, S, skip="-z")
        fbox(mb, -T / 2, T / 2, y0 + 0.15, y1 - 0.15, h + 0.08, h + 0.2, bcol, skip="-z")
    for z in (0.4, h / 2, h - 0.4):                                                               # wall brackets
        fbox(mb, -0.04, 0.04, 0.0, y0, z - 0.04, z + 0.04, S, skip="-y +y")
        fbox(mb, -0.13, 0.13, 0.0, 0.025, z - 0.13, z + 0.13, S)
    n = len(text)
    pitch = (h - 0.36 - foot) / n
    size = min((pitch - 0.12) / 0.7, (w - 0.2) / 0.86)
    for s, rz in ((1, -90), (-1, 90)):
        with mb.at(rot=(0, 0, rz)):
            cx = -s * yc
            for i, ch in enumerate(text):
                zc = h - 0.18 - pitch * (i + 0.5)
                K.add_text(mb, ch, size=size, depth=0.05, color=col, pos=(cx, T / 2, zc - 0.35 * size), res=2)
            ntube(mb, [(cx - w / 2 + 0.07, 0.07), (cx + w / 2 - 0.07, 0.07), (cx + w / 2 - 0.07, h - 0.07),
                       (cx - w / 2 + 0.07, h - 0.07)], T / 2 + 0.014, col, 0.014, closed=True)
            if foot > 0.0:                                                                        # down chevrons
                for dz in (0.0, 0.17):
                    ntube(mb, [(cx - 0.24, foot - 0.02 + dz), (cx, foot - 0.26 + dz), (cx + 0.24, foot - 0.02 + dz)],
                          T / 2 + 0.02, col, 0.018)
    mb.to_object(r, "mesh")
    return r


def sign_blade_hotel():
    return blade("sign_blade_hotel", "HOTEL", "neon_pink", 1.0, 4.8, "charcoal")      # + 0.2 crown = 5.0


def sign_blade_motel():
    return blade("sign_blade_motel", "MOTEL", "neon_cyan", 0.9, 4.4, "navy", foot=0.62, crown=False)


def sign_open():
    r = B.begin("sign_open", glb="buildings/signs/sign_open", spacing=5.0,
                notes="projecting sign: origin = wall plate of the bracket arm; board 0.9 x 0.4 hangs under the arm in "
                      "the YZ plane (Y +0.12..+1.02, Z -0.5..-0.1), 'OPEN' on both faces")
    mb = K.MB()
    T, y0, y1, z0, z1 = 0.07, 0.12, 1.02, -0.5, -0.1
    S = "steel_dark"
    fbox(mb, -0.07, 0.07, 0.0, 0.02, -0.1, 0.1, S)
    fbox(mb, -0.02, 0.02, 0.02, 1.06, -0.02, 0.02, S, skip="-y")
    for y in (0.3, 0.84):
        fbox(mb, -0.012, 0.012, y - 0.012, y + 0.012, z1, -0.02, S, skip="-z +z")
    fbox(mb, -T / 2, T / 2, y0, y1, z0, z1, "black", skip="")
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    for s, rz in ((1, -90), (-1, 90)):
        with mb.at(rot=(0, 0, rz)):
            cx = -s * yc
            K.add_text(mb, "OPEN", size=0.27, depth=0.03, color="neon_green", pos=(cx, T / 2, zc - 0.095), res=2)
            ntube(mb, [(cx - 0.41, z0 + 0.04), (cx + 0.41, z0 + 0.04), (cx + 0.41, z1 - 0.04), (cx - 0.41, z1 - 0.04)],
                  T / 2 + 0.012, "neon_green", 0.012, closed=True)
    mb.to_object(r, "mesh")
    return r


def build_all():
    for aid in FASCIA:
        fascia(aid)
    sign_blade_hotel()
    sign_blade_motel()
    sign_open()
    return B.stats(IDS) + "\n" + "\n".join(B.check(IDS, max_tris=560))


def qa(which="fascia"):
    if which == "fascia":
        return Q.grid("sign", FASCIA, cols=4, dx=4.0, dz=1.15)
    return Q.show("sign", [("sign_blade_hotel", (2.0, 0, 0)), ("sign_blade_motel", (0, 0, 0)),
                           ("sign_open", (-2.0, 0, 2.5))])
