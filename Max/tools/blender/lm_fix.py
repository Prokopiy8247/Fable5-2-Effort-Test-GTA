"""lm_fix - furniture / fixture / prop library for the NEON TIDE landmark interiors (used by lm_*.py).

All functions draw into the *current local frame* of the builders they get (use `with C.at(pos, rz, fx, col):`).
Wall-backed pieces: origin on the floor at the BACK centre, x in [-w/2, w/2], y in [0, d], front = local +Y.
Free-standing pieces: origin on the floor at the footprint centre.
`fx` is normally a C.DMB (dry interior colours); `col` a C.Col or None.
"""
import math
import random

import gta_kit as K
import lm_common as C
from lm_common import bx


# --------------------------------------------------------------------------- small generic bits
def floor_quad(mb, x0, x1, y0, y1, z, color):
    return mb.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), color)


def hazard_outline(mb, x0, x1, y0, y1, z, w=0.16, seg=0.6, colors=("hazard_yellow", "black")):
    """Striped rectangle outline painted on a floor (quads `z` high)."""
    k = 0
    for (a0, a1, fixed0, fixed1, horiz) in ((x0, x1, y0, y0 + w, True), (x0, x1, y1 - w, y1, True),
                                           (y0 + w, y1 - w, x0, x0 + w, False), (y0 + w, y1 - w, x1 - w, x1, False)):
        n = max(1, int(round((a1 - a0) / seg)))
        for i in range(n):
            s0 = a0 + (a1 - a0) * i / n
            s1 = a0 + (a1 - a0) * (i + 1) / n
            c = colors[(i + k) % 2]
            if horiz:
                floor_quad(mb, s0, s1, fixed0, fixed1, z, c)
            else:
                floor_quad(mb, fixed0, fixed1, s0, s1, z, c)
        k += 1


def stock_row(fx, x0, x1, y0, y1, z, hmax, colors, rng, wmin=0.2, wmax=0.42, gap=0.03, fill=0.92, hmin=None,
              dmin=0.75, faces="+x-x+y+z"):
    """Row of product boxes standing on a shelf (front edge at y1)."""
    x = x0
    n = 0
    while x < x1 - wmin * 0.8:
        w = min(rng.uniform(wmin, wmax), x1 - x)
        if rng.random() < fill:
            hgt = rng.uniform(hmin if hmin is not None else hmax * 0.55, hmax)
            dd = (y1 - y0) * rng.uniform(dmin, 1.0)
            C.obox(fx, (x, y1 - dd, z), (x + w - gap, y1, z + hgt), rng.choice(colors), faces)
            n += 1
        x += w
    return n


def tyre(fx, pos, axis="X", r=0.33, w=0.21, segs=8, hub=False):
    fx.cyl(r, w, pos, "tire", axis=axis, segs=segs, cap_color="rubber")
    if hub:
        x, y, z = pos
        if axis == "Z":
            C.disc(fx, (x, y, z + w * 0.5 + 0.004), r * 0.56, "black", axis="Z", segs=segs)


def tyre_stack(fx, col, pos, n=4, r=0.33, w=0.21):
    x, y, z = pos
    for i in range(n):
        ox = 0.03 * ((i * 7) % 3 - 1)
        tyre(fx, (x + ox, y - ox * 0.5, z + w * 0.5 + i * w), "Z", r, w, hub=(i == n - 1))
    if col is not None:
        col.box((x - r, y - r, z), (x + r, y + r, z + n * w))


def drum(fx, col, pos, color="blue", r=0.29, h=0.88, segs=8):
    x, y, z = pos
    fx.cyl(r, h, (x, y, z), color, segs=segs, base=True, cap_color="gray_dark")
    for k in (0.33, 0.66):
        fx.cyl(r + 0.014, 0.04, (x, y, z + h * k), color, segs=segs, caps=False)
    if col is not None:
        col.box((x - r * 0.9, y - r * 0.9, z), (x + r * 0.9, y + r * 0.9, z + h))


def crate(fx, col, lo, hi, color="cardboard", tape="tan"):
    bx(fx, lo, hi, color)
    xm = (lo[0] + hi[0]) * 0.5
    bx(fx, (xm - 0.03, lo[1] - 0.003, lo[2]), (xm + 0.03, hi[1] + 0.003, hi[2] + 0.003), tape)
    if col is not None:
        col.box(lo, hi)


# --------------------------------------------------------------------------- counters / tills / seats
def counter(fx, col, x0, x1, y0, y1, h=1.05, body="wood_dark", top="gray_light", kick="black", over=0.03,
            top_t=0.05, bevel=0.012, z=0.0):
    """Axis-aligned service counter (solid cabinet + overhanging top)."""
    bx(fx, (x0 + 0.04, y0 + 0.04, z), (x1 - 0.04, y1 - 0.04, z + 0.1), kick)
    bx(fx, (x0, y0, z + 0.1), (x1, y1, z + h - top_t), body)
    bx(fx, (x0 - over, y0 - over, z + h - top_t), (x1 + over, y1 + over, z + h), top, bevel=bevel)
    if col is not None:
        col.box((x0, y0, z), (x1, y1, z + h))


def register(fx, pos, rz=0.0):
    """Cash register: operator stands at local -Y, customer display toward +Y."""
    with fx.at(pos, rot=(0, 0, rz)):
        bx(fx, (-0.21, -0.2, 0.0), (0.21, 0.2, 0.11), "plastic_black", bevel=0.01)
        bx(fx, (-0.17, -0.17, 0.11), (0.17, 0.02, 0.15), "gray_dark")
        fx.box((0.34, 0.03, 0.24), (0.0, 0.1, 0.3), "plastic_black", rot=(-18, 0, 0), colors={"-y": "screen_blue"})
        bx(fx, (-0.03, 0.06, 0.11), (0.03, 0.12, 0.22), "plastic_black")
        bx(fx, (-0.09, 0.15, 0.2), (0.09, 0.18, 0.3), "plastic_black", colors={"+y": "led_green"})


def monitor(fx, pos, rz=0.0, w=0.5, h=0.32):
    """Flat screen on a stand, screen faces local +Y."""
    with fx.at(pos, rot=(0, 0, rz)):
        bx(fx, (-0.11, -0.08, 0.0), (0.11, 0.08, 0.015), "plastic_black")
        bx(fx, (-0.02, -0.02, 0.015), (0.02, 0.01, 0.14), "plastic_black")
        bx(fx, (-w * 0.5, -0.015, 0.1), (w * 0.5, 0.015, 0.1 + h), "plastic_black", colors={"+y": "screen_blue"})


def office_chair(fx, pos, rz=0.0, color="fabric_dark"):
    """Swivel chair; the sitter faces local +Y."""
    with fx.at(pos, rot=(0, 0, rz)):
        fx.cyl(0.27, 0.035, (0, 0, 0.02), "plastic_black", segs=8, smooth=False)
        fx.cyl(0.03, 0.4, (0, 0, 0.24), "chrome", segs=6)
        bx(fx, (-0.23, -0.22, 0.44), (0.23, 0.22, 0.52), color, bevel=0.02)
        bx(fx, (-0.21, -0.25, 0.56), (0.21, -0.19, 1.0), color)
        bx(fx, (-0.03, -0.24, 0.48), (0.03, -0.2, 0.6), "plastic_black")


def stool(fx, pos, color="red", h=0.62):
    x, y, z = pos
    fx.cyl(0.17, 0.03, (x, y, z + 0.015), "chrome", segs=8)
    fx.cyl(0.025, h - 0.1, (x, y, z + 0.03), "chrome", segs=6, base=True)
    fx.cyl(0.18, 0.08, (x, y, z + h - 0.04), color, segs=10)


def plant(fx, col, pos, h=1.2, pot="terracotta", leaf="leaf_green", seed=1):
    x, y, z = pos
    fx.cyl(0.17, 0.36, (x, y, z), pot, segs=8, r2=0.22, base=True, cap_color="dirt")
    fx.cyl(0.025, h * 0.45, (x, y, z + 0.36), "bark", segs=5, base=True, caps=False)
    fx.ico(h * 0.26, (x, y, z + h * 0.68), leaf, subdiv=1, jitter=0.22, seed=seed, scale=(1.0, 1.0, 1.25))
    fx.ico(h * 0.17, (x + 0.12, y - 0.08, z + h * 0.92), "leaf_light", subdiv=1, jitter=0.2, seed=seed + 3)
    if col is not None:
        col.box((x - 0.2, y - 0.2, z), (x + 0.2, y + 0.2, z + h * 0.8))


def frame_art(fx, axis, a0, a1, z0, z1, c, out, blocks, frame="black", back="white", proud=0.03):
    """Framed poster on a wall plane (`axis`/c/out as in C.pane).  blocks = [(u0,u1,v0,v1,color)] in 0..1."""
    d = proud * out
    if axis == "X":
        bx(fx, (a0, min(c, c + d), z0), (a1, max(c, c + d), z1), frame)
    else:
        bx(fx, (min(c, c + d), a0, z0), (max(c, c + d), a1, z1), frame)
    m = 0.04
    C.pane(fx, axis, a0 + m, a1 - m, z0 + m, z1 - m, c + d + 0.004 * out, back, out)
    for (u0, u1, v0, v1, colr) in blocks:
        C.pane(fx, axis, a0 + m + (a1 - a0 - 2 * m) * u0, a0 + m + (a1 - a0 - 2 * m) * u1,
               z0 + m + (z1 - z0 - 2 * m) * v0, z0 + m + (z1 - z0 - 2 * m) * v1, c + d + 0.009 * out, colr, out)


# --------------------------------------------------------------------------- shelving
def steel_shelf(fx, col, w, d=0.5, h=2.2, levels=4, post="steel_dark", board="steel", stock=None, rng=None,
                hmax=None, wmin=0.25, wmax=0.55, fill=0.85, z0=0.12):
    """Open industrial shelving, back at y=0.  stock = palette names of the boxes put on the boards."""
    for sx in (-1, 1):
        for y in (0.025, d - 0.025):
            xx = sx * (w * 0.5 - 0.025)
            bx(fx, (xx - 0.025, y - 0.025, 0), (xx + 0.025, y + 0.025, h), post)
    step = (h - z0 - 0.05) / max(1, levels - 1)
    for i in range(levels):
        z = z0 + i * step
        bx(fx, (-w * 0.5, 0.0, z), (w * 0.5, d, z + 0.035), board)
        if stock and rng is not None and i < levels - 1 + 1:
            hm = (hmax if hmax else step - 0.1)
            if i == levels - 1:
                hm = min(hm, 0.3)
            stock_row(fx, -w * 0.5 + 0.06, w * 0.5 - 0.06, 0.04, d - 0.03, z + 0.035, hm, stock, rng, wmin, wmax,
                      fill=fill)
    if col is not None:
        col.box((-w * 0.5, 0, 0), (w * 0.5, d, h))


# --------------------------------------------------------------------------- garage equipment
def tool_chest(fx, col, w=1.1, d=0.55, h=0.95, color="red", upper=True, drawers=4):
    for y in (0.08, d - 0.08):
        bx(fx, (-w * 0.5 + 0.08, y - 0.04, 0.0), (w * 0.5 - 0.08, y + 0.04, 0.09), "rubber")
    bx(fx, (-w * 0.5, 0, 0.09), (w * 0.5, d, h), color, bevel=0.015)
    dh = (h - 0.19) / drawers
    for i in range(drawers):
        z = 0.14 + i * dh
        bx(fx, (-w * 0.5 + 0.1, d, z + dh - 0.1), (w * 0.5 - 0.1, d + 0.03, z + dh - 0.07), "aluminum")
        if i > 0:
            bx(fx, (-w * 0.5 + 0.03, d - 0.002, z - 0.012), (w * 0.5 - 0.03, d + 0.004, z), "black")
    bx(fx, (-w * 0.5 - 0.01, -0.005, h), (w * 0.5 + 0.01, d + 0.01, h + 0.025), "rubber")
    top = h + 0.025
    if upper:
        bx(fx, (-w * 0.5 + 0.04, 0.03, top), (w * 0.5 - 0.04, d - 0.09, top + 0.4), color, bevel=0.012)
        for k in (0.1, 0.24):
            bx(fx, (-w * 0.5 + 0.14, d - 0.09, top + k), (w * 0.5 - 0.14, d - 0.065, top + k + 0.025), "aluminum")
        top += 0.4
    if col is not None:
        col.box((-w * 0.5, 0, 0), (w * 0.5, d, top))


def workbench(fx, col, w=2.6, d=0.75, h=0.92, top="wood_mid", frame="steel_dark", board="wood_light", tools=True,
              vise=True, board_h=1.1):
    for sx in (-1, 1):
        for y in (0.06, d - 0.06):
            xx = sx * (w * 0.5 - 0.07)
            bx(fx, (xx - 0.035, y - 0.035, 0), (xx + 0.035, y + 0.035, h - 0.06), frame)
    bx(fx, (-w * 0.5 + 0.05, 0.05, 0.2), (w * 0.5 - 0.05, d - 0.05, 0.24), frame)
    bx(fx, (-w * 0.5, 0, h - 0.06), (w * 0.5, d, h), top, bevel=0.012)
    bx(fx, (w * 0.5 - 0.8, 0.1, h - 0.4), (w * 0.5 - 0.12, d - 0.03, h - 0.06), "gray_dark")
    for k in (0.12, 0.27):
        bx(fx, (w * 0.5 - 0.66, d - 0.03, h - 0.06 - k), (w * 0.5 - 0.26, d - 0.008, h - 0.035 - k), "aluminum")
    if board_h > 0:
        zb = h + 0.22
        bx(fx, (-w * 0.5, 0.0, zb), (w * 0.5, 0.03, zb + board_h), board)
        if tools:
            y = 0.03
            # hammer, wrenches, saw, square ... simple silhouettes hung on the board
            bx(fx, (-w * 0.5 + 0.2, y, zb + 0.35), (-w * 0.5 + 0.24, y + 0.025, zb + 0.75), "wood_dark")
            bx(fx, (-w * 0.5 + 0.13, y, zb + 0.73), (-w * 0.5 + 0.31, y + 0.05, zb + 0.82), "steel_dark")
            for i in range(3):
                xx = -w * 0.5 + 0.5 + i * 0.17
                bx(fx, (xx, y, zb + 0.5 - i * 0.05), (xx + 0.05, y + 0.018, zb + 0.9), "chrome")
            fx.box((0.6, 0.012, 0.16), (0.25, y + 0.008, zb + 0.72), "steel", taper=(1.0, 0.45))
            bx(fx, (0.53, y, zb + 0.66), (0.62, y + 0.03, zb + 0.82), "red")
            bx(fx, (w * 0.5 - 0.75, y, zb + 0.28), (w * 0.5 - 0.15, y + 0.14, zb + 0.31), "steel_dark")
            for i, c in enumerate(("red", "yellow", "blue")):
                xx = w * 0.5 - 0.68 + i * 0.18
                C.obox(fx, (xx, y + 0.01, zb + 0.31), (xx + 0.13, y + 0.12, zb + 0.31 + 0.15 + 0.04 * (i % 2)), c,
                       "+x-x+y+z")
    if vise:
        x = -w * 0.5 + 0.45
        bx(fx, (x - 0.09, d - 0.3, h), (x + 0.09, d - 0.06, h + 0.05), "steel_dark")
        bx(fx, (x - 0.07, d - 0.26, h + 0.05), (x + 0.07, d - 0.18, h + 0.2), "blue_dark")
        bx(fx, (x - 0.07, d - 0.12, h + 0.05), (x + 0.07, d - 0.05, h + 0.2), "blue_dark")
        bx(fx, (x - 0.015, d - 0.05, h + 0.1), (x + 0.015, d + 0.12, h + 0.13), "chrome")
    # stuff on / under the bench
    bx(fx, (0.1, 0.2, h), (0.55, 0.45, h + 0.2), "red")
    bx(fx, (0.22, 0.3, h + 0.2), (0.43, 0.35, h + 0.25), "steel_dark")
    bx(fx, (-0.5, 0.12, 0.24), (0.1, d - 0.15, 0.56), "cardboard")
    if col is not None:
        col.box((-w * 0.5, 0, 0), (w * 0.5, d, h))


def tyre_rack(fx, col, w=3.0, d=0.62, rows=((0.28, 5), (1.12, 3)), top=1.95):
    for sx in (-1, 1):
        for y in (0.03, d - 0.03):
            xx = sx * (w * 0.5 - 0.03)
            bx(fx, (xx - 0.03, y - 0.03, 0), (xx + 0.03, y + 0.03, top), "steel_dark")
    for z, n in rows:
        for y in (0.12, d - 0.12):
            bx(fx, (-w * 0.5, y - 0.025, z), (w * 0.5, y + 0.025, z + 0.05), "steel")
        pitch = 0.245
        x0 = -w * 0.5 + 0.2
        for i in range(n):
            tyre(fx, (x0 + i * pitch, d * 0.5, z + 0.05 + 0.3), "X", 0.33, 0.21)
    for y in (0.12, d - 0.12):
        bx(fx, (-w * 0.5, y - 0.025, top - 0.05), (w * 0.5, y + 0.025, top), "steel")
    if col is not None:
        col.box((-w * 0.5, 0, 0), (w * 0.5, d, top))


def lift_2post(fx, col, gauge=3.74, post=(0.34, 0.44), h=4.2, color="blue"):
    """Clear-floor 2-post lift, arms resting flat on the floor.  Origin between the posts; cars drive along Y."""
    for sx in (-1, 1):
        x = sx * gauge * 0.5
        bx(fx, (x - 0.32, -0.36, 0.0), (x + 0.32, 0.36, 0.02), "steel_dark")
        bx(fx, (x - post[0] * 0.5, -post[1] * 0.5, 0.02), (x + post[0] * 0.5, post[1] * 0.5, h), color, bevel=0.02)
        xi = x - sx * post[0] * 0.5
        bx(fx, (min(xi, xi - sx * 0.14), -0.27, 0.05), (max(xi, xi - sx * 0.14), 0.27, 0.46), "hazard_yellow")
        for sy in (-1, 1):
            ax0, ay0 = xi - sx * 0.08, sy * 0.2
            ax1, ay1 = xi - sx * 1.0, sy * 0.86
            ln = math.hypot(ax1 - ax0, ay1 - ay0)
            ang = math.degrees(math.atan2(ay1 - ay0, ax1 - ax0))
            fx.box((ln, 0.1, 0.05), ((ax0 + ax1) * 0.5, (ay0 + ay1) * 0.5, 0.075), "steel_dark", rot=(0, 0, ang))
            fx.box((0.15, 0.15, 0.035), (ax1, ay1, 0.117), "rubber", rot=(0, 0, ang))
        if col is not None:
            col.box((x - post[0] * 0.5, -post[1] * 0.5, 0.0), (x + post[0] * 0.5, post[1] * 0.5, h))
    bx(fx, (-gauge * 0.5, -0.1, h), (gauge * 0.5, 0.1, h + 0.16), color)
    bx(fx, (-0.25, -0.13, h - 0.07), (0.25, 0.13, h), "hazard_yellow")
    if col is not None:
        col.box((-gauge * 0.5, -0.1, h), (gauge * 0.5, 0.1, h + 0.16))


def compressor(fx, col):
    """Workshop air compressor, back at y=0, 1.1 long on X."""
    fx.cyl(0.26, 1.0, (0, 0.34, 0.44), "red", axis="X", segs=10)
    bx(fx, (-0.32, 0.17, 0.69), (0.08, 0.51, 0.94), "steel_dark")
    fx.cyl(0.085, 0.22, (0.27, 0.34, 0.68), "gray_dark", segs=8, base=True)
    for y in (0.07, 0.61):
        fx.cyl(0.12, 0.05, (-0.38, y, 0.12), "rubber", axis="Y", segs=6)
    bx(fx, (0.36, 0.2, 0.0), (0.42, 0.48, 0.2), "steel_dark")
    bx(fx, (-0.66, 0.12, 0.9), (-0.62, 0.56, 0.94), "steel_dark")
    bx(fx, (-0.66, 0.32, 0.5), (-0.5, 0.36, 0.94), "steel_dark")
    if col is not None:
        col.box((-0.55, 0.05, 0), (0.52, 0.63, 0.94))


def wall_rim(fx, pos, out=-1, r=0.29, w=0.15):
    """Alloy wheel rim displayed on a wall whose normal is out*X (pos = wall point)."""
    x, y, z = pos
    cx = x + out * (w * 0.5 + 0.02)
    fx.cyl(r, w, (cx, y, z), "chrome", axis="X", segs=10, cap_color="aluminum")
    C.disc(fx, (cx + out * (w * 0.5 + 0.005), y, z), r * 0.74, "charcoal", axis="X", segs=10, out=out)
    C.disc(fx, (cx + out * (w * 0.5 + 0.011), y, z), r * 0.3, "chrome", axis="X", segs=5, out=out, rot0=math.pi / 2)


def engine_stand(fx, col):
    """V-engine on a rolling stand (free-standing, crank along local Y)."""
    for sx in (-1, 1):
        bx(fx, (sx * 0.34 - 0.03, -0.45, 0.0), (sx * 0.34 + 0.03, 0.45, 0.07), "red")
    bx(fx, (-0.34, -0.04, 0.02), (0.34, 0.04, 0.08), "red")
    bx(fx, (-0.05, -0.36, 0.07), (0.05, -0.26, 0.6), "red")
    bx(fx, (-0.24, -0.3, 0.42), (0.24, 0.34, 0.5), "black")
    bx(fx, (-0.26, -0.3, 0.5), (0.26, 0.34, 0.82), "gunmetal")
    for sx in (-1, 1):
        fx.box((0.2, 0.6, 0.16), (sx * 0.2, 0.02, 0.9), "aluminum", rot=(0, sx * 32, 0))
        fx.box((0.15, 0.56, 0.06), (sx * 0.25, 0.02, 0.99), "red", rot=(0, sx * 32, 0))
    bx(fx, (-0.1, -0.2, 0.86), (0.1, 0.24, 1.05), "steel_dark")
    fx.cyl(0.13, 0.05, (0.0, 0.37, 0.6), "charcoal", axis="Y", segs=8)
    fx.cyl(0.08, 0.05, (0.17, 0.37, 0.78), "steel", axis="Y", segs=6)
    if col is not None:
        col.box((-0.37, -0.45, 0.0), (0.37, 0.45, 1.05))


def gas_bottles(fx, col):
    """Two welding gas bottles on a trolley, back at y=0."""
    bx(fx, (-0.28, 0.0, 0.0), (0.28, 0.34, 0.05), "steel_dark")
    bx(fx, (-0.28, 0.0, 0.05), (0.28, 0.03, 1.25), "steel_dark")
    for sx, c in ((-1, "blue_dark"), (1, "maroon")):
        fx.cyl(0.12, 1.15, (sx * 0.14, 0.18, 0.05), c, segs=8, base=True)
        bx(fx, (sx * 0.14 - 0.035, 0.145, 1.2), (sx * 0.14 + 0.035, 0.215, 1.32), "brass")
    if col is not None:
        col.box((-0.28, 0.0, 0.0), (0.28, 0.34, 1.3))


def wall_spoiler(fx, w=1.7, color="magenta"):
    """Car wing displayed on a wall (back at y=0, origin = mount height)."""
    fx.box((w, 0.34, 0.045), (0, 0.3, 0.0), color, rot=(12, 0, 0))
    for sx in (-1, 1):
        bx(fx, (sx * w * 0.5 - 0.015, 0.1, -0.12), (sx * w * 0.5 + 0.015, 0.5, 0.12), "black")
        bx(fx, (sx * w * 0.28 - 0.02, 0.0, -0.05), (sx * w * 0.28 + 0.02, 0.26, -0.01), "steel_dark")


# =========================================================================== P1 shops: shared pieces
def oct_ring(cx, cy, z, rx, ry, ch=0.55):
    """Chamfered-rectangle ring (8 points, CCW from above) for lofted bodies."""
    return [(cx + rx, cy - ry * ch, z), (cx + rx, cy + ry * ch, z), (cx + rx * ch, cy + ry, z),
            (cx - rx * ch, cy + ry, z), (cx - rx, cy + ry * ch, z), (cx - rx, cy - ry * ch, z),
            (cx - rx * ch, cy - ry, z), (cx + rx * ch, cy - ry, z)]


def small_sign(fx, text, x, y, z, w, h, board="black", color="neon_red", out=1, axis="X", depth=0.1):
    """Lit box sign with 3D lettering on a wall (axis 'X': wall plane y, readable from out*Y)."""
    if axis == "X" and out > 0:
        bx(fx, (x - w * 0.5, y, z), (x + w * 0.5, y + depth, z + h), board)
        C.sign(fx, text, (x, y + depth, z + h * 0.5), w * 0.82, h * 0.6, color, depth=0.025, res=1, valign="center")
    elif axis == "X":
        bx(fx, (x - w * 0.5, y - depth, z), (x + w * 0.5, y, z + h), board)
        C.sign(fx, text, (x, y - depth, z + h * 0.5), w * 0.82, h * 0.6, color, depth=0.025, res=1, valign="center",
               rot=(0, 0, 180))
    else:
        xa, xb = (y, y + depth) if out > 0 else (y - depth, y)
        bx(fx, (xa, x - w * 0.5, z), (xb, x + w * 0.5, z + h), board)
        C.sign(fx, text, (xb if out > 0 else xa, x, z + h * 0.5), w * 0.82, h * 0.6, color, depth=0.025, res=1,
               valign="center", rot=(0, 0, -90 if out > 0 else 90))


def floor_mat(fx, x0, x1, y0, y1, z, color="black", border=None):
    floor_quad(fx, x0, x1, y0, y1, z, color)
    if border:
        for (a0, a1, b0, b1) in ((x0, x1, y0, y0 + 0.05), (x0, x1, y1 - 0.05, y1), (x0, x0 + 0.05, y0 + 0.05, y1 - 0.05),
                                 (x1 - 0.05, x1, y0 + 0.05, y1 - 0.05)):
            floor_quad(fx, a0, a1, b0, b1, z + 0.003, border)


def wall_cabinet(fx, col, w, d=0.5, h=0.9, body="wood_dark", top="gray_dark", doors=3, handle="chrome", kick="black"):
    """Low wall-backed storage cabinet (back at y=0) with door seams + handles."""
    bx(fx, (-w * 0.5 + 0.03, 0.0, 0.0), (w * 0.5 - 0.03, d - 0.05, 0.1), kick)
    bx(fx, (-w * 0.5, 0.0, 0.1), (w * 0.5, d, h - 0.04), body)
    bx(fx, (-w * 0.5 - 0.02, 0.0, h - 0.04), (w * 0.5 + 0.02, d + 0.03, h), top)
    for i in range(doors):
        xa = -w * 0.5 + w * i / doors
        if i > 0:
            C.pane(fx, "X", xa - 0.006, xa + 0.006, 0.12, h - 0.06, d + 0.004, "black", 1)
        xm = xa + w / doors * (0.85 if i % 2 == 0 else 0.15)
        bx(fx, (xm - 0.012, d, h - 0.3), (xm + 0.012, d + 0.03, h - 0.12), handle)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


# --------------------------------------------------------------------------- weapons shop
GUN_PROFILES = {
    # (x along the gun from the butt, z up), metres for L = 1.0 (z is not scaled)
    "rifle": [(0.0, -0.06), (0.27, -0.012), (0.26, -0.11), (0.32, -0.11), (0.34, -0.012), (0.44, -0.012),
              (0.43, -0.13), (0.49, -0.13), (0.5, -0.012), (0.8, 0.0), (0.8, 0.026), (1.0, 0.026), (1.0, 0.046),
              (0.8, 0.056), (0.33, 0.07), (0.0, 0.075)],
    "shotgun": [(0.0, -0.055), (0.3, -0.008), (0.29, -0.085), (0.34, -0.085), (0.37, -0.008), (0.5, -0.008),
                (0.52, -0.032), (0.74, -0.032), (0.75, 0.0), (1.0, 0.0), (1.0, 0.035), (0.36, 0.05), (0.0, 0.07)],
    "hunter": [(0.0, -0.065), (0.3, -0.02), (0.36, -0.035), (0.38, -0.01), (0.7, 0.0), (1.05, 0.012), (1.05, 0.03),
               (0.66, 0.04), (0.6, 0.075), (0.38, 0.075), (0.33, 0.045), (0.0, 0.07)],
}
PISTOL_PROFILE = [(-0.015, 0.0), (0.03, 0.0), (0.05, 0.065), (0.08, 0.065), (0.085, 0.05), (0.105, 0.05),
                  (0.11, 0.068), (0.19, 0.068), (0.19, 0.1), (0.005, 0.1)]


def long_gun(fx, pos, rot=(0, 0, 0), kind="rifle", color="gunmetal", L=1.0, t=0.04, back=False):
    """Generic long-gun silhouette (profile prism, NOT a real model).  Local frame: butt at x=0, muzzle +X,
    top +Z, the flat show face looks +Y (the -Y face is skipped unless back=True)."""
    pts = [(x * L, z) for x, z in GUN_PROFILES[kind]]
    with fx.at(pos, rot=rot):
        fx.prism(pts, t, color, plane="XZ", caps=(back, True))


def pistol(fx, pos, rot=(0, 0, 0), color="black", s=1.0, t=0.028, plane="XY"):
    """Handgun silhouette.  plane 'XY': lying flat (show face +Z); 'XZ': hanging on a wall (show face +Y)."""
    with fx.at(pos, rot=rot, scale=s):
        fx.prism(PISTOL_PROFILE, t, color, plane=plane, center=False, caps=(False, True))


def glass_counter(fx, col, x0, x1, y0, y1, h=1.05, base_h=0.48, body="wood_dark", kick="black", felt="maroon",
                  frame="steel", skip=(), glass="@Glass"):
    """Axis-aligned glass display counter: cabinet base, felt bed, glass sides + top in a slim steel frame.
    skip = sides without glass ('+x', '-x', '+y', '-y') where two counters meet."""
    bx(fx, (x0 + 0.04, y0 + 0.04, 0.0), (x1 - 0.04, y1 - 0.04, 0.1), kick)
    bx(fx, (x0, y0, 0.1), (x1, y1, base_h), body)
    floor_quad(fx, x0 + 0.03, x1 - 0.03, y0 + 0.03, y1 - 0.03, base_h + 0.03, felt)
    f = 0.03
    for (xa, ya) in ((x0, y0), (x1 - f, y0), (x1 - f, y1 - f), (x0, y1 - f)):
        bx(fx, (xa, ya, base_h), (xa + f, ya + f, h - f), frame)
    bx(fx, (x0, y0, h - f), (x1, y0 + f, h), frame)
    bx(fx, (x0, y1 - f, h - f), (x1, y1, h), frame)
    bx(fx, (x0, y0 + f, h - f), (x0 + f, y1 - f, h), frame)
    bx(fx, (x1 - f, y0 + f, h - f), (x1, y1 - f, h), frame)
    bx(fx, (x0, y0, base_h), (x1, y1, base_h + 0.025), frame)
    zg0, zg1 = base_h + 0.025, h - f
    if "+y" not in skip:
        C.pane(fx, "X", x0 + f, x1 - f, zg0, zg1, y1 - 0.012, glass, 1)
    if "-y" not in skip:
        C.pane(fx, "X", x0 + f, x1 - f, zg0, zg1, y0 + 0.012, glass, -1)
    if "+x" not in skip:
        C.pane(fx, "Y", y0 + f, y1 - f, zg0, zg1, x1 - 0.012, glass, 1)
    if "-x" not in skip:
        C.pane(fx, "Y", y0 + f, y1 - f, zg0, zg1, x0 + 0.012, glass, -1)
    zt = h - 0.012
    fx.quad((x0 + f, y0 + f, zt), (x1 - f, y0 + f, zt), (x1 - f, y1 - f, zt), (x0 + f, y1 - f, zt), glass)
    if col is not None:
        col.box((x0, y0, 0.0), (x1, y1, h))
    return base_h + 0.03


def slatwall(fx, axis, a0, a1, z0, z1, c, out, color="wood_dark", groove="black", step=0.25, d=0.03):
    """Slatted display panel on a wall plane (axis 'X': wall at y=c facing out*Y; 'Y': wall at x=c facing out*X)."""
    if axis == "X":
        bx(fx, (a0, min(c, c + out * d), z0), (a1, max(c, c + out * d), z1), color)
    else:
        bx(fx, (min(c, c + out * d), a0, z0), (max(c, c + out * d), a1, z1), color)
    z = z0 + step
    while z < z1 - 0.06:
        C.pane(fx, axis, a0 + 0.02, a1 - 0.02, z - 0.012, z + 0.012, c + out * (d + 0.004), groove, out)
        z += step


def mannequin(fx, col, pos, rz=0.0, skin="plastic_white", torso=None, collar=None, vest=None, base="chrome",
              legs=None):
    """Abstract torso mannequin on a pole stand (faces local +Y).  torso = garment colour, vest = (main, accent)
    armour vest, legs = skirt / shorts colour (short lofted piece under the hips)."""
    torso = torso or skin
    with fx.at(pos, rot=(0, 0, rz)):
        fx.cyl(0.21, 0.04, (0, 0, 0), base, segs=10, base=True, smooth=False)
        fx.cyl(0.02, 0.92 if legs is None else 0.6, (0, 0, 0.04), "chrome", segs=6, base=True, caps=False)
        rings = [oct_ring(0, 0, 0.94, 0.16, 0.1), oct_ring(0, 0, 1.12, 0.135, 0.09), oct_ring(0, 0, 1.36, 0.18, 0.11),
                 oct_ring(0, 0, 1.52, 0.21, 0.1), oct_ring(0, 0, 1.6, 0.15, 0.08)]
        fx.loft(rings, torso)
        if legs is not None:
            fx.loft([oct_ring(0, 0, 0.6, 0.21, 0.14), oct_ring(0, 0, 0.95, 0.165, 0.105)], legs, cap_end=False)
        fx.cyl(0.045, 0.1, (0, 0, 1.6), skin, segs=6, base=True, caps=False)
        fx.sphere(0.105, (0, 0.01, 1.8), skin, segs=8, rings=5, scale=(0.85, 0.95, 1.22))
        if collar:
            fx.loft([oct_ring(0, 0, 1.56, 0.12, 0.075), oct_ring(0, 0, 1.64, 0.08, 0.06)], collar, cap_start=False,
                    cap_end=False)
        if vest:
            main, acc = vest
            fx.box((0.36, 0.05, 0.4), (0, 0.105, 1.3), main, bevel=0.01)
            fx.box((0.36, 0.05, 0.4), (0, -0.105, 1.3), main, bevel=0.01)
            fx.loft([oct_ring(0, 0, 1.06, 0.18, 0.13), oct_ring(0, 0, 1.2, 0.2, 0.135)], main)
            for sx in (-1, 1):
                bx(fx, (sx * 0.12 - 0.035, -0.11, 1.48), (sx * 0.12 + 0.035, 0.11, 1.58), main)
            for k in range(3):
                bx(fx, (-0.14 + k * 0.1, 0.13, 1.1), (-0.06 + k * 0.1, 0.17, 1.22), acc)
            bx(fx, (-0.1, 0.13, 1.4), (0.1, 0.136, 1.46), acc)
    if col is not None:
        x, y, z = pos
        col.box((x - 0.21, y - 0.21, z), (x + 0.21, y + 0.21, z + 1.9))


def vitrine(fx, col, w=1.6, d=0.55, h=2.1, body="black", back="maroon", light="emis_warm_always"):
    """Tall wall-backed glass display case (back at y=0, front +Y).  Returns the inner floor height."""
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.4), body)
    bx(fx, (-w * 0.5, 0.0, h - 0.14), (w * 0.5, d, h), body)
    for sx in (-1, 1):
        bx(fx, (sx * w * 0.5 - (0.05 if sx > 0 else 0.0), 0.0, 0.4), (sx * w * 0.5 + (0.0 if sx > 0 else 0.05), d, h - 0.14),
           body)
    C.pane(fx, "X", -w * 0.5 + 0.05, w * 0.5 - 0.05, 0.4, h - 0.14, 0.012, back, 1)
    C.obox(fx, (-w * 0.5 + 0.08, d * 0.3, h - 0.17), (w * 0.5 - 0.08, d * 0.6, h - 0.14), light, "-z+y")
    C.pane(fx, "X", -w * 0.5 + 0.05, w * 0.5 - 0.05, 0.4, h - 0.14, d - 0.015, "@Glass", 1)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))
    return 0.4


def desk_lamp(fx, pos, rz=0.0, color="black", shade="orange"):
    with fx.at(pos, rot=(0, 0, rz)):
        fx.cyl(0.08, 0.025, (0, 0, 0), color, segs=8, base=True, smooth=False)
        fx.box((0.022, 0.022, 0.36), (0.0, 0.03, 0.2), color, rot=(-15, 0, 0))
        fx.box((0.022, 0.24, 0.022), (0.0, 0.14, 0.37), color)
        fx.cyl(0.075, 0.1, (0.0, 0.26, 0.32), shade, segs=8, r2=0.035, cap_color="emis_warm_always", smooth=False)


def layered_art(fx, axis, a0, a1, z0, z1, c, out, blocks, frame="black", back="white", proud=0.03):
    """Like frame_art() but every block sits 3 mm in front of the previous one (nested blocks, no z-fighting)."""
    d = proud * out
    if axis == "X":
        bx(fx, (a0, min(c, c + d), z0), (a1, max(c, c + d), z1), frame)
    else:
        bx(fx, (min(c, c + d), a0, z0), (max(c, c + d), a1, z1), frame)
    m = 0.04
    C.pane(fx, axis, a0 + m, a1 - m, z0 + m, z1 - m, c + d + 0.004 * out, back, out)
    for k, (u0, u1, v0, v1, colr) in enumerate(blocks):
        C.pane(fx, axis, a0 + m + (a1 - a0 - 2 * m) * u0, a0 + m + (a1 - a0 - 2 * m) * u1,
               z0 + m + (z1 - z0 - 2 * m) * v0, z0 + m + (z1 - z0 - 2 * m) * v1, c + d + (0.007 + 0.003 * k) * out,
               colr, out)


def target_poster(fx, axis, a0, a1, z0, z1, c, out):
    layered_art(fx, axis, a0, a1, z0, z1, c, out,
                [(0.12, 0.88, 0.1, 0.9, "black"), (0.22, 0.78, 0.22, 0.78, "white"), (0.33, 0.67, 0.36, 0.64, "black"),
                 (0.43, 0.57, 0.46, 0.54, "orange")], frame="black", back="white")


# =========================================================================== home furniture (safehouse)
def legs4(fx, x0, x1, y0, y1, h, s=0.05, color="wood_dark"):
    for x in (x0, x1 - s):
        for y in (y0, y1 - s):
            bx(fx, (x, y, 0.0), (x + s, y + s, h), color)


def sofa(fx, col, w=2.0, d=0.9, color="fabric_blue", cushion=None, legs="wood_dark"):
    """Three-seat sofa, back at y=0, sitter faces +Y, x in [-w/2, w/2]."""
    cushion = cushion or color
    legs4(fx, -w * 0.5 + 0.05, w * 0.5 - 0.05, 0.05, d - 0.05, 0.08, 0.05, legs)
    bx(fx, (-w * 0.5 + 0.02, 0.02, 0.08), (w * 0.5 - 0.02, d - 0.02, 0.4), color)
    bx(fx, (-w * 0.5, 0.0, 0.08), (w * 0.5, 0.2, 0.86), color, bevel=0.025)
    for sx in (-1, 1):
        xa, xb = (-w * 0.5, -w * 0.5 + 0.18) if sx < 0 else (w * 0.5 - 0.18, w * 0.5)
        bx(fx, (xa, 0.0, 0.08), (xb, d, 0.62), color, bevel=0.025)
    n = 2 if w < 1.9 else 3
    sw = (w - 0.36) / n
    for i in range(n):
        xa = -w * 0.5 + 0.18 + i * sw
        bx(fx, (xa + 0.01, 0.2, 0.4), (xa + sw - 0.01, d - 0.02, 0.53), cushion, bevel=0.025)
        fx.box((sw - 0.04, 0.16, 0.34), (xa + sw * 0.5, 0.28, 0.72), cushion, rot=(-12, 0, 0), bevel=0.025)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.53))
        col.box((-w * 0.5, 0.0, 0.53), (w * 0.5, 0.25, 0.86))


def bed(fx, col, w=1.6, L=2.1, frame="wood_mid", sheet="white", blanket="fabric_blue", pillow="white"):
    """Double bed, headboard at y=0, foot toward +Y, x in [-w/2, w/2]."""
    legs4(fx, -w * 0.5 + 0.03, w * 0.5 - 0.03, 0.1, L - 0.03, 0.12, 0.06, frame)
    bx(fx, (-w * 0.5, 0.06, 0.12), (w * 0.5, L, 0.34), frame)
    bx(fx, (-w * 0.5 - 0.04, 0.0, 0.0), (w * 0.5 + 0.04, 0.08, 1.05), frame, bevel=0.02)
    bx(fx, (-w * 0.5 + 0.03, 0.09, 0.34), (w * 0.5 - 0.03, L - 0.03, 0.54), sheet, bevel=0.03)
    bx(fx, (-w * 0.5 + 0.005, 0.85, 0.36), (w * 0.5 - 0.005, L - 0.005, 0.58), blanket, bevel=0.02)
    bx(fx, (-w * 0.5 + 0.0, 0.78, 0.5), (w * 0.5 - 0.0, 0.95, 0.6), sheet, bevel=0.02)
    for sx in (-1, 1):
        fx.box((w * 0.5 - 0.16, 0.36, 0.14), (sx * w * 0.25, 0.32, 0.6), pillow, rot=(-14, 0, 0), bevel=0.04)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, L, 0.58))
        col.box((-w * 0.5 - 0.04, 0.0, 0.58), (w * 0.5 + 0.04, 0.08, 1.05))


def nightstand(fx, col, w=0.5, d=0.42, h=0.55, body="wood_mid", lamp="cream"):
    """Bedside table (back at y=0) with a small lamp."""
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, d, h), body, bevel=0.01)
    bx(fx, (-w * 0.5 + 0.04, d, h - 0.2), (w * 0.5 - 0.04, d + 0.012, h - 0.05), "wood_light")
    bx(fx, (-0.06, d + 0.012, h - 0.14), (0.06, d + 0.03, h - 0.11), "chrome")
    fx.cyl(0.06, 0.2, (0.0, d * 0.45, h), "charcoal", segs=6, base=True, smooth=False)
    fx.cyl(0.14, 0.16, (0.0, d * 0.45, h + 0.2), lamp, segs=8, r2=0.1, base=True, cap_color="emis_warm_always",
           smooth=False)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


def wardrobe(fx, col, w=1.6, d=0.6, h=2.2, body="white", trim="wood_mid", handle="chrome", mirror=True):
    """Two-door wardrobe, back at y=0, doors toward +Y."""
    bx(fx, (-w * 0.5 + 0.03, 0.0, 0.0), (w * 0.5 - 0.03, d - 0.04, 0.08), "charcoal")
    bx(fx, (-w * 0.5, 0.0, 0.08), (w * 0.5, d, h - 0.06), body)
    bx(fx, (-w * 0.5 - 0.03, 0.0, h - 0.06), (w * 0.5 + 0.03, d + 0.03, h), trim)
    C.pane(fx, "X", -0.006, 0.006, 0.12, h - 0.1, d + 0.004, "gray_mid", 1)
    for sx in (-1, 1):
        bx(fx, (sx * 0.06 - 0.012, d, 1.0), (sx * 0.06 + 0.012, d + 0.035, 1.35), handle)
    if mirror:
        C.pane(fx, "X", 0.12, w * 0.5 - 0.12, 0.3, h - 0.35, d + 0.006, "mirror", 1)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


def tv_unit(fx, col, w=1.7, d=0.45, body="wood_dark", tv_w=1.35, tv_h=0.78):
    """Low TV stand (back at y=0) with a flat TV on a foot; the screen (screen_blue) looks +Y."""
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.48), body, bevel=0.01)
    for sx in (-1, 1):
        C.pane(fx, "X", sx * 0.04 - (0.0 if sx > 0 else w * 0.5 - 0.1), sx * 0.04 + (w * 0.5 - 0.1 if sx > 0 else 0.0),
               0.08, 0.4, d + 0.004, "wood_mid", 1)
    bx(fx, (-0.2, d * 0.3, 0.48), (0.2, d * 0.7, 0.5), "black")
    bx(fx, (-0.03, d * 0.45, 0.5), (0.03, d * 0.55, 0.62), "black")
    bx(fx, (-tv_w * 0.5, d * 0.5 - 0.03, 0.6), (tv_w * 0.5, d * 0.5 + 0.02, 0.6 + tv_h), "black",
       colors={"+y": "black"})
    C.pane(fx, "X", -tv_w * 0.5 + 0.03, tv_w * 0.5 - 0.03, 0.63, 0.57 + tv_h, d * 0.5 + 0.026, "screen_blue", 1)
    bx(fx, (0.35, d * 0.25, 0.48), (0.62, d * 0.75, 0.56), "plastic_gray")
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.5))


def coffee_table(fx, col, pos, w=1.0, d=0.55, h=0.4, top="wood_mid", leg="black"):
    x, y, z = pos
    with fx.at(pos):
        legs4(fx, -w * 0.5 + 0.04, w * 0.5 - 0.04, -d * 0.5 + 0.04, d * 0.5 - 0.04, h - 0.04, 0.04, leg)
        bx(fx, (-w * 0.5, -d * 0.5, h - 0.04), (w * 0.5, d * 0.5, h), top, bevel=0.01)
        bx(fx, (-w * 0.5 + 0.06, -d * 0.5 + 0.06, 0.1), (w * 0.5 - 0.06, d * 0.5 - 0.06, 0.12), top)
        bx(fx, (-0.3, -0.12, h), (0.0, 0.1, h + 0.02), "paper")
        fx.cyl(0.04, 0.09, (0.22, 0.05, h), "red", segs=6, base=True, smooth=False)
    if col is not None:
        col.box((x - w * 0.5, y - d * 0.5, z), (x + w * 0.5, y + d * 0.5, z + h))


def rug(fx, x0, x1, y0, y1, z, color="carpet", border="cream", b=0.12):
    floor_quad(fx, x0, x1, y0, y1, z, border)
    floor_quad(fx, x0 + b, x1 - b, y0 + b, y1 - b, z + 0.003, color)


def floor_lamp(fx, col, pos, h=1.65, shade="cream", pole="black"):
    x, y, z = pos
    fx.cyl(0.16, 0.03, (x, y, z), pole, segs=8, base=True, smooth=False)
    fx.cyl(0.015, h - 0.25, (x, y, z + 0.03), pole, segs=5, base=True, caps=False)
    fx.cyl(0.22, 0.3, (x, y, z + h - 0.3), shade, segs=8, r2=0.15, base=True, caps=False, smooth=False)
    C.disc(fx, (x, y, z + h - 0.29), 0.2, "emis_warm_always", axis="Z", segs=8, out=-1)
    C.disc(fx, (x, y, z + h - 0.005), 0.14, "emis_warm_always", axis="Z", segs=8)
    if col is not None:
        col.box((x - 0.12, y - 0.12, z), (x + 0.12, y + 0.12, z + h))


def kitchenette(fx, col, w=3.6, d=0.6, body="white", top="gray_dark", fridge="white", window=None,
                upper_body=None):
    """Back at y=0, x in [-w/2, w/2]: fridge at -X, base cabinets with sink + hob, upper cabinets, hood.
    window = (x0, x1) local range kept free of upper cabinets."""
    upper_body = upper_body or body
    fw = 0.75
    x0 = -w * 0.5 + fw
    # fridge
    bx(fx, (-w * 0.5, 0.0, 0.0), (x0 - 0.02, d + 0.02, 1.95), fridge, bevel=0.015)
    C.pane(fx, "X", -w * 0.5 + 0.02, x0 - 0.04, 1.3, 1.31, d + 0.024, "gray_mid", 1)
    for zz in ((1.4, 1.75), (0.75, 1.15)):
        bx(fx, (x0 - 0.12, d + 0.02, zz[0]), (x0 - 0.09, d + 0.06, zz[1]), "chrome")
    # base run
    bx(fx, (x0, 0.0, 0.0), (w * 0.5, d - 0.06, 0.1), "charcoal")
    bx(fx, (x0, 0.0, 0.1), (w * 0.5, d, 0.88), body)
    bx(fx, (x0 - 0.01, 0.0, 0.88), (w * 0.5 + 0.02, d + 0.03, 0.92), top)
    n = max(2, int(round((w * 0.5 - x0) / 0.6)))
    cw = (w * 0.5 - x0) / n
    for i in range(n):
        xa = x0 + i * cw
        if i > 0:
            C.pane(fx, "X", xa - 0.005, xa + 0.005, 0.12, 0.86, d + 0.004, "gray_light", 1)
        bx(fx, (xa + cw * 0.5 - 0.1, d, 0.78), (xa + cw * 0.5 + 0.1, d + 0.025, 0.8), "chrome")
    # sink (left part) + tap, hob (right part) + oven front
    sx0 = x0 + cw * 0.5 + 0.05
    C.obox(fx, (sx0, 0.12, 0.88), (sx0 + 0.55, d - 0.1, 0.925), "steel", "+z")
    C.obox(fx, (sx0 + 0.05, 0.17, 0.885), (sx0 + 0.5, d - 0.15, 0.926), "steel_dark", "+z")
    bx(fx, (sx0 + 0.25, 0.04, 0.92), (sx0 + 0.3, 0.09, 1.2), "chrome")
    bx(fx, (sx0 + 0.25, 0.04, 1.15), (sx0 + 0.3, 0.26, 1.19), "chrome")
    hx = w * 0.5 - 0.75
    bx(fx, (hx, 0.06, 0.92), (hx + 0.6, d - 0.04, 0.935), "black")
    for (u, v) in ((0.15, 0.17), (0.45, 0.17), (0.15, 0.4), (0.45, 0.4)):
        C.disc(fx, (hx + u, v + 0.03, 0.937), 0.08, "gray_dark", axis="Z", segs=8)
    C.pane(fx, "X", hx + 0.02, hx + 0.58, 0.18, 0.72, d + 0.006, "black", 1)
    bx(fx, (hx + 0.08, d + 0.006, 0.66), (hx + 0.52, d + 0.03, 0.68), "chrome")
    # upper cabinets + hood
    zu0, zu1, du = 1.5, 2.2, 0.34
    runs = [(x0, w * 0.5)]
    if window:
        runs = [(x0, window[0] - 0.05), (window[1] + 0.05, hx - 0.05), (hx + 0.65, w * 0.5)]
    for a, b in runs:
        if b - a < 0.3:
            continue
        bx(fx, (a, 0.0, zu0), (b, du, zu1), upper_body)
        m = max(1, int(round((b - a) / 0.5)))
        for k in range(1, m):
            xa = a + (b - a) * k / m
            C.pane(fx, "X", xa - 0.005, xa + 0.005, zu0 + 0.02, zu1 - 0.02, du + 0.004, "gray_light", 1)
    fx.box((0.62, 0.42, 0.3), (hx + 0.3, 0.21, zu0 + 0.15), "steel", taper=(0.45, 0.6))
    bx(fx, (hx + 0.2, 0.08, zu0 + 0.3), (hx + 0.4, 0.28, zu1), "steel")
    if col is not None:
        col.box((x0, 0.0, 0.0), (w * 0.5, d, 0.92))
        col.box((-w * 0.5, 0.0, 0.0), (x0, d + 0.02, 1.95))


def desk(fx, col, w=1.4, d=0.65, h=0.75, top="wood_light", frame="black", drawers="white"):
    """Work desk, back at y=0, front +Y; drawer block on the +X side."""
    bx(fx, (-w * 0.5, 0.0, h - 0.04), (w * 0.5, d, h), top, bevel=0.008)
    for x in (-w * 0.5 + 0.03, w * 0.5 - 0.47):
        bx(fx, (x, 0.05, 0.0), (x + 0.04, d - 0.05, h - 0.04), frame)
    bx(fx, (-w * 0.5 + 0.07, 0.04, h - 0.3), (w * 0.5 - 0.47, 0.06, h - 0.04), frame)
    bx(fx, (w * 0.5 - 0.43, 0.04, 0.0), (w * 0.5 - 0.02, d - 0.04, h - 0.04), drawers)
    for k in range(3):
        z = 0.08 + k * 0.22
        bx(fx, (w * 0.5 - 0.3, d - 0.04, z + 0.12), (w * 0.5 - 0.15, d - 0.02, z + 0.14), "chrome")
        if k:
            C.pane(fx, "X", w * 0.5 - 0.42, w * 0.5 - 0.03, z - 0.005, z + 0.005, d - 0.036, "gray_light", 1)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


def laptop(fx, pos, rz=0.0, color="plastic_gray"):
    """Open laptop, the user sits at local -Y, screen (screen_blue) faces -Y."""
    with fx.at(pos, rot=(0, 0, rz)):
        bx(fx, (-0.17, -0.12, 0.0), (0.17, 0.12, 0.02), color)
        C.obox(fx, (-0.15, -0.09, 0.02), (0.15, 0.05, 0.023), "black", "+z")
        fx.box((0.34, 0.015, 0.23), (0.0, 0.14, 0.12), color, rot=(-14, 0, 0), colors={"-y": "screen_blue"})


def chair(fx, pos, rz=0.0, color="wood_mid", seat=None):
    """Simple dining chair, sitter faces local +Y."""
    seat = seat or color
    with fx.at(pos, rot=(0, 0, rz)):
        legs4(fx, -0.2, 0.2, -0.2, 0.2, 0.45, 0.04, color)
        bx(fx, (-0.21, -0.21, 0.45), (0.21, 0.21, 0.5), seat, bevel=0.01)
        for x in (-0.2, 0.16):
            bx(fx, (x, -0.21, 0.5), (x + 0.04, -0.17, 0.92), color)
        bx(fx, (-0.2, -0.22, 0.72), (0.2, -0.17, 0.9), color)


GARMENT_COLS = ("red", "navy", "white", "denim", "yellow", "coral_pink", "black", "khaki", "teal", "magenta", "olive",
                "sky_blue", "beige", "maroon", "turquoise", "lime")


def garment_rack(fx, col, L=2.2, h=1.55, rng=None, colors=GARMENT_COLS, metal="chrome", pitch=0.15, long_frac=0.3):
    """Free-standing straight clothes rail along local X (centred on the origin); garments hang across it."""
    rng = rng or random.Random(1)
    for sx in (-1, 1):
        x = sx * L * 0.5
        bx(fx, (x - 0.025, -0.28, 0.0), (x + 0.025, 0.28, 0.03), metal)
        bx(fx, (x - 0.016, -0.016, 0.03), (x + 0.016, 0.016, h), metal)
    bx(fx, (-L * 0.5 - 0.02, -0.014, h - 0.03), (L * 0.5 + 0.02, 0.014, h), metal)
    x = -L * 0.5 + 0.13
    while x < L * 0.5 - 0.1:
        t = rng.uniform(0.045, 0.07)
        w = rng.uniform(0.4, 0.48)
        ln = rng.uniform(0.9, 1.05) if rng.random() < long_frac else rng.uniform(0.6, 0.75)
        C.obox(fx, (x - t * 0.5, -w * 0.5, h - 0.07 - ln), (x + t * 0.5, w * 0.5, h - 0.07), rng.choice(colors),
               "+x-x+y-y+z-z")
        bx(fx, (x - 0.004, -0.005, h - 0.07), (x + 0.004, 0.005, h - 0.02), "chrome")
        x += pitch * rng.uniform(0.85, 1.2)
    if col is not None:
        col.box((-L * 0.5 - 0.03, -0.28, 0.0), (L * 0.5 + 0.03, 0.28, h))


def fold_shelf(fx, col, w=1.8, d=0.42, h=2.1, body="white", rng=None, colors=GARMENT_COLS, levels=4):
    """Wall shelving (back at y=0) with stacks of folded clothes."""
    rng = rng or random.Random(2)
    for sx in (-1, 1):
        bx(fx, (sx * w * 0.5 - (0.03 if sx > 0 else 0.0), 0.0, 0.0), (sx * w * 0.5 + (0.0 if sx > 0 else 0.03), d, h), body)
    bx(fx, (-w * 0.5 + 0.03, 0.0, 0.0), (w * 0.5 - 0.03, d - 0.02, 0.1), "gray_light")
    step = (h - 0.12) / levels
    for i in range(levels + 1):
        z = 0.1 + i * step
        bx(fx, (-w * 0.5 + 0.03, 0.0, z), (w * 0.5 - 0.03, d, z + 0.025), body)
        if i == levels:
            break
        n = 4
        sw = (w - 0.12) / n
        for k in range(n):
            if rng.random() < 0.15:
                continue
            xa = -w * 0.5 + 0.06 + k * sw + 0.02
            zz = z + 0.025
            for m in range(rng.randint(2, 3)):
                th = rng.uniform(0.06, 0.09)
                C.obox(fx, (xa, 0.04, zz), (xa + sw - 0.05, d - 0.03, zz + th), rng.choice(colors), "+x-x+y+z")
                zz += th
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


def shoe_wall(fx, col, w=2.0, d=0.3, h=2.0, body="white", back="gray_light", rng=None, colors=GARMENT_COLS, levels=4):
    """Shoe display (back at y=0): back panel, shallow shelves with shoe pairs."""
    rng = rng or random.Random(3)
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, 0.03, h), back)
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.12), body)
    step = (h - 0.3) / levels
    for i in range(levels):
        zs = 0.12 + i * step
        if i:
            bx(fx, (-w * 0.5 + 0.02, 0.03, zs - 0.025), (w * 0.5 - 0.02, d, zs), body)
        n = 3
        pw = (w - 0.1) / n
        for k in range(n):
            c = rng.choice(colors)
            xa = -w * 0.5 + 0.05 + k * pw + pw * 0.5
            for sx in (-1, 1):
                x0 = xa + sx * 0.065
                C.obox(fx, (x0 - 0.045, 0.05, zs), (x0 + 0.045, 0.3 if d >= 0.3 else d - 0.01, zs + 0.09), c, "+x-x+y+z")
                C.obox(fx, (x0 - 0.04, 0.05, zs + 0.09), (x0 + 0.04, 0.13, zs + 0.15), c, "+x-x+y+z")
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, h))


def fitting_booths(fx, col, x0, x1, y0, y1, z=0.0, n=2, h=2.35, wall="white", curtain="turquoise", trim="black",
                   open_frac=(0.62, 0.38)):
    """n changing booths against a back wall (face y0), open toward +Y at y1, partitions on the floor at z."""
    bw = (x1 - x0) / n
    t = 0.06
    for i in range(n + 1):
        xa = x0 + i * bw - (t if i == n else 0.0) - (t * 0.5 if 0 < i < n else 0.0)
        bx(fx, (xa, y0, z), (xa + t, y1, z + h), wall)
        if col is not None:
            col.box((xa, y0, z), (xa + t, y1, z + h))
    bx(fx, (x0, y1 - 0.06, z + h - 0.3), (x1, y1, z + h), wall)
    bx(fx, (x0, y1 - 0.065, z + h - 0.33), (x1, y1 - 0.055, z + h - 0.3), trim)
    for i in range(n):
        a = x0 + i * bw + t * 0.6
        b = a + (bw - t * 1.2) * open_frac[i % len(open_frac)]
        if i % 2:
            a, b = x0 + (i + 1) * bw - t * 0.6 - (bw - t * 1.2) * open_frac[i % len(open_frac)], x0 + (i + 1) * bw - t * 0.6
        k = max(3, int((b - a) / 0.09))
        fr, bk = [], []
        for j in range(k + 1):
            xx = a + (b - a) * j / k
            yy = y1 - 0.12 + (0.035 if j % 2 else -0.035)
            fr.append((xx, yy + 0.012))
            bk.append((xx, yy - 0.012))
        with fx.at((0, 0, z + 0.06)):
            fx.prism(fr + list(reversed(bk)), h - 0.4, curtain, plane="XY", center=False, caps=(False, False))
        # bench + mirror inside the booth
        xm = x0 + i * bw + bw * 0.5
        bx(fx, (xm - 0.35, y0, z + 0.42), (xm + 0.35, y0 + 0.35, z + 0.47), "wood_light")
        C.pane(fx, "X", xm - 0.3, xm + 0.3, z + 0.7, z + 1.95, y0 + 0.006, "mirror", 1)


def standing_mirror(fx, col, pos, rz=0.0, w=0.6, h=1.8, frame="black"):
    with fx.at(pos, rot=(0, 0, rz)):
        bx(fx, (-w * 0.5 - 0.04, -0.2, 0.0), (w * 0.5 + 0.04, 0.2, 0.04), frame)
        bx(fx, (-w * 0.5, -0.03, 0.04), (w * 0.5, 0.0, 0.04 + h), frame)
        C.pane(fx, "X", -w * 0.5 + 0.04, w * 0.5 - 0.04, 0.08, h, 0.004, "mirror", 1)
    if col is not None:
        x, y, z = pos
        r = max(w * 0.5 + 0.04, 0.2)
        col.box((x - r, y - r, z), (x + r, y + r, z + h))


def display_table(fx, col, pos, w=1.4, d=0.8, h=0.78, top="white", leg="wood_mid", rng=None, colors=GARMENT_COLS):
    """Low display table with folded stacks (centred on pos)."""
    rng = rng or random.Random(4)
    x, y, z = pos
    with fx.at(pos):
        legs4(fx, -w * 0.5 + 0.05, w * 0.5 - 0.05, -d * 0.5 + 0.05, d * 0.5 - 0.05, h - 0.05, 0.05, leg)
        bx(fx, (-w * 0.5, -d * 0.5, h - 0.05), (w * 0.5, d * 0.5, h), top, bevel=0.01)
        for i in range(3):
            for j in range(2):
                xa = -w * 0.5 + 0.1 + i * (w - 0.2) / 3
                ya = -d * 0.5 + 0.08 + j * (d - 0.16) / 2
                zz = h
                for m in range(rng.randint(2, 4)):
                    th = rng.uniform(0.05, 0.07)
                    C.obox(fx, (xa + 0.02, ya + 0.02, zz), (xa + (w - 0.2) / 3 - 0.04, ya + (d - 0.16) / 2 - 0.04, zz + th),
                           rng.choice(colors), "+x-x+y-y+z")
                    zz += th
    if col is not None:
        col.box((x - w * 0.5, y - d * 0.5, z), (x + w * 0.5, y + d * 0.5, z + h))


def pouf(fx, col, pos, r=0.3, h=0.42, color="coral_pink"):
    x, y, z = pos
    fx.cyl(r, h, (x, y, z), color, segs=10, base=True, cap_color=color, smooth=True)
    if col is not None:
        col.box((x - r * 0.9, y - r * 0.9, z), (x + r * 0.9, y + r * 0.9, z + h))


# =========================================================================== convenience store (market)
PRODUCT_COLS = ("red", "yellow", "orange", "blue", "green", "white", "purple", "cyan", "magenta", "lime", "brown",
                "cream", "red_dark", "sky_blue", "coral_orange", "navy", "yellow_dark", "pink")


def gondola(fx, col, L=4.4, d=0.9, h=1.55, levels=4, body="white", shelf="gray_light", rng=None, colors=PRODUCT_COLS,
            header="green", wmin=0.4, wmax=0.75, stocked=3):
    """Double-sided store shelf running along local Y (centred on the origin); both long sides (+X / -X) are
    stocked on the lowest `stocked` levels; a promo end cap + header board at the +Y end."""
    rng = rng or random.Random(5)
    bx(fx, (-d * 0.5 + 0.03, -L * 0.5, 0.0), (d * 0.5 - 0.03, L * 0.5, 0.1), "gray_dark")
    bx(fx, (-0.03, -L * 0.5, 0.1), (0.03, L * 0.5, h), body)
    for sy in (-1, 1):
        ya, yb = (-L * 0.5 - 0.04, -L * 0.5) if sy < 0 else (L * 0.5, L * 0.5 + 0.04)
        bx(fx, (-d * 0.5, ya, 0.0), (d * 0.5, yb, h), body)
    step = (h - 0.1) / levels
    for rz in (-90, 90):
        with fx.at((0, 0, 0), rot=(0, 0, rz)):
            for i in range(levels):
                z = 0.1 + i * step
                if i > 0:
                    bx(fx, (-L * 0.5, 0.03, z - 0.025), (L * 0.5, d * 0.5, z), shelf)
                    C.pane(fx, "X", -L * 0.5, L * 0.5, z - 0.05, z - 0.025, d * 0.5 + 0.004, header, 1)
                if i >= levels - stocked:
                    stock_row(fx, -L * 0.5 + 0.05, L * 0.5 - 0.05, 0.05, d * 0.5 - 0.02, z, step - 0.07, colors, rng,
                              wmin, wmax, gap=0.025, fill=0.95, hmin=step * 0.45)
    # end cap (front, +Y) with stock and a header board on top
    with fx.at((0, L * 0.5 + 0.04, 0)):
        bx(fx, (-d * 0.5, 0.0, 0.0), (d * 0.5, 0.32, 0.12), "gray_dark")
        for i, z in enumerate((0.12, 0.6)):
            if i:
                bx(fx, (-d * 0.5, 0.0, z - 0.025), (d * 0.5, 0.32, z), shelf)
            stock_row(fx, -d * 0.5 + 0.04, d * 0.5 - 0.04, 0.02, 0.3, z, 0.36, colors, rng, 0.2, 0.3, gap=0.02, fill=1.0)
    bx(fx, (-d * 0.5, L * 0.5 - 0.04, h), (d * 0.5, L * 0.5 + 0.04, h + 0.3), header)
    C.pane(fx, "X", -d * 0.5 + 0.05, d * 0.5 - 0.05, h + 0.12, h + 0.18, L * 0.5 + 0.045, "white", 1)
    if col is not None:
        col.box((-d * 0.5, -L * 0.5 - 0.04, 0.0), (d * 0.5, L * 0.5 + 0.36, h))


def fridge_wall(fx, col, x0, x1, y0, d=0.75, h=2.25, n=6, body="white", frame="black", rng=None, colors=PRODUCT_COLS,
                lit="emis_cool_always"):
    """Glass-door drink coolers against a back wall (wall face y0, door fronts at y0 + d) spanning x0..x1,
    lit interior (emissive back panel), 4 shelves of bottles, one glass sheet behind a door-frame grid."""
    rng = rng or random.Random(6)
    yf = y0 + d
    zb, zt = 0.3, h - 0.25
    bx(fx, (x0, y0, 0.0), (x1, yf, zb), "gray_dark")
    C.pane(fx, "X", x0 + 0.1, x1 - 0.1, 0.06, 0.24, yf + 0.004, "black", 1)
    bx(fx, (x0, y0, zt), (x1, yf, h), body)
    C.pane(fx, "X", x0 + 0.05, x1 - 0.05, zt + 0.05, h - 0.05, yf + 0.004, "green", 1)
    for xa, xb in ((x0, x0 + 0.06), (x1 - 0.06, x1)):
        bx(fx, (xa, y0, zb), (xb, yf, zt), body)
    C.pane(fx, "X", x0 + 0.06, x1 - 0.06, zb, zt, y0 + 0.01, lit, 1)
    C.obox(fx, (x0 + 0.06, y0 + 0.05, zt - 0.03), (x1 - 0.06, y0 + 0.2, zt), lit, "-z")
    dw = (x1 - x0) / n
    levels = [zb, 0.78, 1.26, 1.72]
    for k, z in enumerate(levels):
        if k:
            bx(fx, (x0 + 0.06, y0 + 0.05, z - 0.02), (x1 - 0.06, yf - 0.12, z), "gray_light")
        for i in range(n):
            xa = x0 + i * dw + 0.1
            m = 4
            bw = (dw - 0.2) / m
            for j in range(m):
                hh = rng.uniform(0.22, 0.34) if k < 3 else rng.uniform(0.18, 0.26)
                C.obox(fx, (xa + j * bw + 0.015, yf - 0.32, z), (xa + (j + 1) * bw - 0.015, yf - 0.16, z + hh),
                       rng.choice(colors), "+y+z")
    # door grid + glass + handles
    for i in range(n + 1):
        x = x0 + i * dw
        bx(fx, (max(x0, x - 0.03), yf - 0.04, zb), (min(x1, x + 0.03), yf, zt), frame)
    bx(fx, (x0, yf - 0.04, zb), (x1, yf, zb + 0.05), frame)
    bx(fx, (x0, yf - 0.04, zt - 0.05), (x1, yf, zt), frame)
    C.pane(fx, "X", x0 + 0.03, x1 - 0.03, zb + 0.05, zt - 0.05, yf - 0.02, "@Glass", 1)
    for i in range(n):
        x = x0 + (i + 1) * dw - 0.1
        bx(fx, (x - 0.012, yf, 0.85), (x + 0.012, yf + 0.04, 1.6), "chrome")
    if col is not None:
        col.box((x0, y0, 0.0), (x1, yf, h))


def chips_rack(fx, col, pos, rz=0.0, w=0.55, d=0.4, h=1.45, rng=None, colors=PRODUCT_COLS):
    """Free-standing wire rack with snack bags (front +Y)."""
    rng = rng or random.Random(7)
    with fx.at(pos, rot=(0, 0, rz)):
        for x in (-w * 0.5, w * 0.5 - 0.02):
            for y in (-d * 0.5, d * 0.5 - 0.02):
                bx(fx, (x, y, 0.0), (x + 0.02, y + 0.02, h), "chrome")
        for i, z in enumerate((0.3, 0.65, 1.0, 1.35)):
            bx(fx, (-w * 0.5, -d * 0.5, z - 0.015), (w * 0.5, d * 0.5, z), "steel")
            for k in range(2):
                xa = -w * 0.5 + 0.03 + k * (w - 0.06) / 2
                fx.box(((w - 0.1) / 2, 0.08, 0.26), (xa + (w - 0.06) / 4, d * 0.5 - 0.1, z + 0.12),
                       rng.choice(colors), rot=(-12, 0, 0), taper=(0.85, 0.5))
        bx(fx, (-w * 0.5, -d * 0.5, h), (w * 0.5, d * 0.5 + 0.02, h + 0.22), "green")
    if col is not None:
        x, y, z = pos
        r = max(w, d) * 0.5
        col.box((x - r, y - r, z), (x + r, y + r, z + h))


def atm(fx, col, body="gray_mid", accent="green"):
    """Wall-backed cash machine (back at y=0, user stands at +Y)."""
    bx(fx, (-0.35, 0.0, 0.0), (0.35, 0.55, 1.05), body, bevel=0.015)
    fx.box((0.66, 0.36, 0.12), (0.0, 0.42, 1.08), "gray_dark", rot=(25, 0, 0))
    bx(fx, (-0.35, 0.0, 1.05), (0.35, 0.3, 1.75), body, bevel=0.015)
    bx(fx, (-0.36, 0.0, 1.75), (0.36, 0.34, 1.95), accent)
    C.pane(fx, "X", -0.22, 0.22, 1.25, 1.6, 0.304, "black", 1)
    C.pane(fx, "X", -0.18, 0.18, 1.29, 1.56, 0.308, "screen_blue", 1)
    C.pane(fx, "X", -0.25, 0.25, 1.82, 1.88, 0.344, "white", 1)
    bx(fx, (0.12, 0.5, 0.95), (0.27, 0.56, 0.97), "black")
    if col is not None:
        col.box((-0.35, 0.0, 0.0), (0.35, 0.6, 1.95))


def chest_freezer(fx, col, pos, rz=0.0, w=1.4, d=0.7, h=0.85, body="white", lit="emis_cool_always", rng=None,
                  colors=PRODUCT_COLS):
    """Ice-cream chest freezer with a glass lid and lit tubs inside."""
    rng = rng or random.Random(8)
    with fx.at(pos, rot=(0, 0, rz)):
        bx(fx, (-w * 0.5, -d * 0.5, 0.0), (w * 0.5, d * 0.5, 0.12), "gray_dark")
        for (a, b, c_, e) in ((-w * 0.5, w * 0.5, -d * 0.5, -d * 0.5 + 0.06), (-w * 0.5, w * 0.5, d * 0.5 - 0.06, d * 0.5),
                              (-w * 0.5, -w * 0.5 + 0.06, -d * 0.5 + 0.06, d * 0.5 - 0.06),
                              (w * 0.5 - 0.06, w * 0.5, -d * 0.5 + 0.06, d * 0.5 - 0.06)):
            bx(fx, (a, c_, 0.12), (b, e, h), body)
        floor_quad(fx, -w * 0.5 + 0.06, w * 0.5 - 0.06, -d * 0.5 + 0.06, d * 0.5 - 0.06, h - 0.3, lit)
        for i in range(5):
            for j in range(2):
                C.obox(fx, (-w * 0.5 + 0.1 + i * 0.24, -d * 0.5 + 0.1 + j * 0.26, h - 0.3),
                       (-w * 0.5 + 0.3 + i * 0.24, -d * 0.5 + 0.32 + j * 0.26, h - 0.3 + rng.uniform(0.08, 0.16)),
                       rng.choice(colors), "+x-x+y-y+z")
        fx.quad((-w * 0.5 + 0.05, -d * 0.5 + 0.05, h - 0.01), (w * 0.5 - 0.05, -d * 0.5 + 0.05, h - 0.01),
                (w * 0.5 - 0.05, d * 0.5 - 0.05, h - 0.01), (-w * 0.5 + 0.05, d * 0.5 - 0.05, h - 0.01), "@Glass")
        C.pane(fx, "X", -w * 0.5 + 0.1, w * 0.5 - 0.1, 0.3, h - 0.1, d * 0.5 + 0.004, "sky_blue", 1)
    if col is not None:
        x, y, z = pos
        c, s = abs(math.cos(math.radians(rz))), abs(math.sin(math.radians(rz)))
        ex, ey = c * w * 0.5 + s * d * 0.5, s * w * 0.5 + c * d * 0.5
        col.box((x - ex, y - ey, z), (x + ex, y + ey, z + h))


# =========================================================================== barber
def barber_chair(fx, col, pos, rz=0.0, leather="red_dark", metal="chrome"):
    """Hydraulic barber chair, the sitter faces local +Y; seat top at z 0.6."""
    with fx.at(pos, rot=(0, 0, rz)):
        fx.cyl(0.3, 0.04, (0, 0, 0), metal, segs=10, base=True, smooth=False)
        fx.cyl(0.075, 0.36, (0, 0, 0.04), metal, segs=8, base=True, caps=False)
        bx(fx, (-0.22, -0.22, 0.38), (0.22, 0.22, 0.45), "black")
        bx(fx, (-0.28, -0.26, 0.45), (0.28, 0.28, 0.6), leather, bevel=0.03)
        fx.box((0.5, 0.12, 0.62), (0.0, -0.3, 0.92), leather, rot=(-10, 0, 0), bevel=0.03)
        bx(fx, (-0.02, -0.38, 1.2), (0.02, -0.34, 1.32), metal)
        bx(fx, (-0.15, -0.42, 1.3), (0.15, -0.3, 1.42), leather, bevel=0.02)
        for sx in (-1, 1):
            bx(fx, (sx * 0.3 - 0.035, -0.12, 0.6), (sx * 0.3 + 0.035, 0.0, 0.76), metal)
            bx(fx, (sx * 0.3 - 0.045, -0.2, 0.76), (sx * 0.3 + 0.045, 0.3, 0.82), leather, bevel=0.01)
        fx.box((0.42, 0.24, 0.025), (0.0, 0.48, 0.2), metal, rot=(15, 0, 0))
        bx(fx, (-0.02, 0.26, 0.2), (0.02, 0.36, 0.45), metal)
        bx(fx, (0.3, -0.05, 0.3), (0.34, 0.05, 0.36), metal)
    if col is not None:
        x, y, z = pos
        col.box((x - 0.3, y - 0.3, z), (x + 0.3, y + 0.3, z + 0.6))


def mirror_station(fx, col, w=1.2, d=0.42, rng=None):
    """Barber station on a wall (back at y=0, front +Y): vanity with drawers, big framed mirror, light bar, tools."""
    rng = rng or random.Random(9)
    bx(fx, (-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.08), "black")
    bx(fx, (-w * 0.5 + 0.02, 0.0, 0.08), (w * 0.5 - 0.02, d - 0.02, 0.85), "wood_dark")
    bx(fx, (-w * 0.5 - 0.02, 0.0, 0.85), (w * 0.5 + 0.02, d + 0.02, 0.89), "black", bevel=0.008)
    for k in range(3):
        z = 0.2 + k * 0.22
        C.pane(fx, "X", -w * 0.5 + 0.06, w * 0.5 - 0.06, z, z + 0.006, d - 0.016, "black", 1)
        bx(fx, (-0.08, d - 0.02, z + 0.1), (0.08, d + 0.01, z + 0.12), "chrome")
    bx(fx, (-w * 0.5 + 0.05, 0.0, 1.0), (w * 0.5 - 0.05, 0.04, 2.25), "black")
    C.pane(fx, "X", -w * 0.5 + 0.1, w * 0.5 - 0.1, 1.05, 2.2, 0.045, "mirror", 1)
    bx(fx, (-w * 0.5 + 0.1, 0.0, 2.3), (w * 0.5 - 0.1, 0.1, 2.36), "black", colors={"-z": "emis_warm_always"})
    for i in range(3):
        fx.cyl(0.035, rng.uniform(0.14, 0.22), (-w * 0.5 + 0.18 + i * 0.1, 0.12, 0.89),
               rng.choice(("blue", "teal", "yellow", "white", "red")), segs=6, base=True)
    bx(fx, (0.12, 0.12, 0.89), (0.22, 0.2, 0.93), "black")
    bx(fx, (0.3, 0.06, 0.89), (0.52, 0.32, 0.92), "white")
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.89))


def wait_bench(fx, col, w=2.2, d=0.5, seat="leather_black", metal="chrome"):
    """Waiting bench against a wall (back at y=0, sitters face +Y)."""
    for x in (-w * 0.5 + 0.08, w * 0.5 - 0.12):
        bx(fx, (x, 0.08, 0.0), (x + 0.04, d - 0.06, 0.4), metal)
    bx(fx, (-w * 0.5, 0.04, 0.4), (w * 0.5, d, 0.5), seat, bevel=0.02)
    bx(fx, (-w * 0.5, 0.0, 0.55), (w * 0.5, 0.1, 0.95), seat, bevel=0.02)
    n = 3
    for i in range(1, n):
        x = -w * 0.5 + w * i / n
        C.pane(fx, "X", x - 0.006, x + 0.006, 0.6, 0.92, 0.105, "black", 1)
    if col is not None:
        col.box((-w * 0.5, 0.0, 0.0), (w * 0.5, d, 0.5))
        col.box((-w * 0.5, 0.0, 0.5), (w * 0.5, 0.1, 0.95))


def wall_clock(fx, axis, a, z, c, out, r=0.2):
    if axis == "X":
        fx.cyl(r, 0.04, (a, c + out * 0.02, z), "black", axis="Y", segs=12, smooth=False)
        C.disc(fx, (a, c + out * 0.041, z), r * 0.85, "white", axis="Y", segs=12, out=out)
        bx(fx, (a - 0.01, c + out * 0.044 - 0.002, z), (a + 0.01, c + out * 0.044 + 0.002, z + r * 0.7), "black")
        bx(fx, (a, c + out * 0.046 - 0.002, z - 0.01), (a + r * 0.5, c + out * 0.046 + 0.002, z + 0.01), "black")
    else:
        fx.cyl(r, 0.04, (c + out * 0.02, a, z), "black", axis="X", segs=12, smooth=False)
        C.disc(fx, (c + out * 0.041, a, z), r * 0.85, "white", axis="X", segs=12, out=out)
        bx(fx, (c + out * 0.044 - 0.002, a - 0.01, z), (c + out * 0.044 + 0.002, a + 0.01, z + r * 0.7), "black")


def pendant(root, fx, pts, zc, drop=0.7, shade="black", first=1, r=0.22):
    """Round pendant lamps (rod + cone shade + emissive bottom) + markers light_<n> below them."""
    for i, (x, y) in enumerate(pts):
        zs = zc - drop
        fx.cyl(0.01, drop - 0.2, (x, y, zs + 0.2), "black", segs=4, base=True, caps=False)
        fx.cyl(r, 0.22, (x, y, zs), shade, segs=10, r2=0.06, base=True, caps=False, smooth=False)
        C.disc(fx, (x, y, zs + 0.01), r * 0.92, "emis_warm_always", axis="Z", segs=10, out=-1)
        bx(fx, (x - 0.06, y - 0.06, zc - 0.03), (x + 0.06, y + 0.06, zc), "black")
        K.marker(root, "light_%d" % (first + i), (x, y, zs - 0.2))


def coat_rack(fx, pos, h=1.8, color="wood_dark"):
    x, y, z = pos
    fx.cyl(0.2, 0.03, (x, y, z), color, segs=8, base=True, smooth=False)
    fx.cyl(0.02, h, (x, y, z + 0.03), color, segs=6, base=True)
    for k in range(4):
        a = math.radians(45 + k * 90)
        fx.box((0.02, 0.2, 0.02), (x + math.cos(a) * 0.08, y + math.sin(a) * 0.08, z + h - 0.05), color,
               rot=(40, 0, math.degrees(a) - 90))
    fx.box((0.28, 0.14, 0.5), (x + 0.12, y + 0.04, z + h - 0.45), "navy", rot=(0, 8, 30))


def table_round(fx, col, pos, r=0.45, h=0.75, top="wood_light", leg="black"):
    x, y, z = pos
    fx.cyl(r, 0.04, (x, y, z + h - 0.04), top, segs=10, base=True, smooth=False)
    fx.cyl(0.04, h - 0.04, (x, y, z), leg, segs=6, base=True, caps=False)
    fx.cyl(0.25, 0.03, (x, y, z), leg, segs=8, base=True, smooth=False)
    if col is not None:
        col.box((x - r * 0.8, y - r * 0.8, z), (x + r * 0.8, y + r * 0.8, z + h))
