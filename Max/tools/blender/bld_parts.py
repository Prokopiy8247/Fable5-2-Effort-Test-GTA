"""bld_parts - reusable facade parts (windows, frames, louvres, lod builder, tiling test) for bld_*.py."""
import bpy
import gta_kit as K
import bld_common as B
from bld_common import fq, q, pane, wall, reveal, fbox, cbox, GD


def frame(mb, a, b, c, d, w=0.07, color="charcoal", y=-0.04, y1=GD, bottom=True):
    """Frame ring inside opening a..b x c..d: front ring at Y=y, inner faces back to y1. -> inner rect."""
    ia, ib, ic, id_ = a + w, b - w, c + (w if bottom else 0.0), d - w
    wall(mb, a, b, c, d, (ia, ib, ic, id_), color, y)
    reveal(mb, ia, ib, ic, id_, color, y, y1, sides="lrt" + ("b" if bottom else ""))
    return ia, ib, ic, id_


def vbar(mb, x, c, d, w=0.06, color="charcoal", y=-0.04, y1=GD):
    """Vertical glazing bar: front + two side faces."""
    q(mb, x - w / 2, x + w / 2, c, d, color, y)
    fq(mb, [(x - w / 2, y, c), (x - w / 2, y1, c), (x - w / 2, y1, d), (x - w / 2, y, d)], color, (-1, 0, 0))
    fq(mb, [(x + w / 2, y, c), (x + w / 2, y1, c), (x + w / 2, y1, d), (x + w / 2, y, d)], color, (1, 0, 0))


def hbar(mb, a, b, z, w=0.06, color="charcoal", y=-0.045, y1=GD):
    """Horizontal glazing bar (5 mm behind vertical bars so crossings never z-fight)."""
    q(mb, a, b, z - w / 2, z + w / 2, color, y)
    fq(mb, [(a, y, z - w / 2), (b, y, z - w / 2), (b, y1, z - w / 2), (a, y1, z - w / 2)], color, (0, 0, -1))
    fq(mb, [(a, y, z + w / 2), (b, y, z + w / 2), (b, y1, z + w / 2), (a, y1, z + w / 2)], color, (0, 0, 1))


def window(mb, a, b, c, d, fc="charcoal", fw=0.07, fy=-0.04, wallc="tint_a", vbars=(), hbars=(), bw=0.05,
           split=False, rcolors=None):
    """Recessed framed window in opening a..b x c..d: wall reveal (0 -> fy), frame ring at fy, inner reveal
    to GD, glazing bars, @Window pane(s) at GD. split=True: one pane quad per bar cell. -> inner rect."""
    reveal(mb, a, b, c, d, wallc, 0.0, fy, colors=rcolors)
    ia, ib, ic, id_ = frame(mb, a, b, c, d, fw, fc, fy)
    for x in vbars:
        vbar(mb, x, ic, id_, bw, fc, fy)
    for z in hbars:
        hbar(mb, ia, ib, z, bw, fc, fy - 0.005)
    if split:
        xs = [ia] + [v for x in sorted(vbars) for v in (x - bw / 2, x + bw / 2)] + [ib]
        zs = [ic] + [v for z in sorted(hbars) for v in (z - bw / 2, z + bw / 2)] + [id_]
        for i in range(0, len(xs), 2):
            for j in range(0, len(zs), 2):
                pane(mb, xs[i], xs[i + 1], zs[j], zs[j + 1])
    else:
        pane(mb, ia, ib, ic, id_)
    return ia, ib, ic, id_


def louvre(mb, x0, x1, z0, z1, color="tint_b", fcolor=None, n=5, t=0.05, fw=0.06, y=0.0):
    """Louvred panel (shutter / vent grille): frame ring proud by t, sawtooth slats inside."""
    fc = fcolor or color
    fbox(mb, x0, x1, y, y + t, z0, z1, fc, skip="-y +y")
    a, b, c, d = x0 + fw, x1 - fw, z0 + fw, z1 - fw
    wall(mb, x0, x1, z0, z1, (a, b, c, d), fc, y + t)
    yb, yf = y + t * 0.25, y + t * 0.85
    reveal(mb, a, b, c, d, fc, y + t, yb)
    h = (d - c) / n
    for k in range(n):
        zb, zt = c + k * h, c + (k + 1) * h
        fq(mb, [(a, yf, zb), (b, yf, zb), (b, yb, zt), (a, yb, zt)], color, (0, 1, 1))
        fq(mb, [(a, yb, zb), (b, yb, zb), (b, yf, zb), (a, yf, zb)], color, (0, 0, -1))


def lod(root, W, H, holes=(), wallc="tint_a", bands=(), extra=None):
    """lod1 part: flat wall quads at Y=0 around flat @Window quads (holes), plus (z0, z1, color) bands
    above the wall zone. extra(mb) may add a few more faces."""
    mb = K.MB()
    X = W / 2
    top = bands[0][0] if bands else H
    hs = sorted(holes)
    if not hs:
        wall(mb, -X, X, 0, top, None, wallc)
    cuts = [-X] + [(hs[i][1] + hs[i + 1][0]) * 0.5 for i in range(len(hs) - 1)] + [X]
    for i, h in enumerate(hs):
        wall(mb, cuts[i], cuts[i + 1], 0, top, h, wallc)
        q(mb, h[0], h[1], h[2], h[3], "@Window")
    for z0, z1, col in bands:
        q(mb, -X, X, z0, z1, col)
    if extra:
        extra(mb)
    return B.lod_obj(mb, root)


# ----------------------------------------------------------------------------- tiling test (tinted preview)
def _prev_mat(tag, ta, tb):
    p = K.palette()
    n = p["size"]
    img = bpy.data.images.new("zz_bld_pal_" + tag, n, n, alpha=False)
    px = [1.0, 0.0, 1.0, 1.0] * (n * n)
    A, Bc = K._hex(ta), K._hex(tb)
    for i, e in enumerate(p["colors"]):
        r, g, b = K._hex(e[1])
        if e[5] == "tA":
            r, g, b = r * A[0], g * A[1], b * A[2]
        elif e[5] == "tB":
            r, g, b = r * Bc[0], g * Bc[1], b * Bc[2]
        k = ((n - 1 - i // n) * n + i % n) * 4
        px[k:k + 4] = [r, g, b, 1.0]
    img.pixels = px
    mat = bpy.data.materials.new("zz_bld_prev_" + tag)
    mat.use_nodes = True
    bsdf = next(nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def tile(tag, rows, ta="#e6d3ad", tb="#3f6fa8", wing=2, part="mesh", extras=()):
    """Temporary tiling test `zz_tile_<tag>`. rows (bottom -> top): lists of module ids laid along X.
    A `wing` of modules returns along -Y at the +X end to show a building corner. Tinted preview copies.
    extras: (asset_id, (x, y, z)) placed once (awnings, signs...)."""
    name = "zz_tile_" + tag
    untile(tag)
    root = K.begin_asset(name, B.CAT, 30.0)
    mat = _prev_mat(tag, ta, tb)
    cache = {}

    def data(aid):
        if aid not in cache:
            me = bpy.data.objects["%s__%s" % (aid, part)].data.copy()
            for i, m in enumerate(me.materials):
                if m is not None and m.name == "Palette":
                    me.materials[i] = mat
            cache[aid] = me
        return cache[aid]

    def put(aid, pos, rz=0.0, k=[0]):
        k[0] += 1
        o = bpy.data.objects.new("%s__m%03d" % (name, k[0]), data(aid))
        for c in root.users_collection:
            c.objects.link(o)
        o.parent = root
        o.location = pos
        o.rotation_euler = (0.0, 0.0, rz)
        return o

    z = 0.0
    total = max(sum(bpy.data.objects[a]["gta_w"] for a in row) for row in rows)
    for row in rows:
        x = -total / 2
        for aid in row:
            w = bpy.data.objects[aid]["gta_w"]
            put(aid, (x + w / 2, 0.0, z))
            x += w
        yy = 0.0
        for i in range(wing):
            aid = row[(i + 1) % len(row)]
            w = bpy.data.objects[aid]["gta_w"]
            put(aid, (total / 2, yy - w / 2, z), rz=-1.5707963267948966)
            yy -= w
        z += bpy.data.objects[row[0]]["gta_h"]
    for aid, pos in extras:
        put(aid, pos)
    return name


def untile(tag):
    K.remove_asset("zz_tile_" + tag)
    m = bpy.data.materials.get("zz_bld_prev_" + tag)
    if m is not None and m.users == 0:
        bpy.data.materials.remove(m)
    img = bpy.data.images.get("zz_bld_pal_" + tag)
    if img is not None and img.users == 0:
        bpy.data.images.remove(img)
    for me in [me for me in bpy.data.meshes if me.users == 0 and me.name.split(".")[0].endswith(("__mesh", "__lod1"))
               and any(mm is not None and mm.name.startswith("zz_bld_prev_") for mm in me.materials)]:
        bpy.data.meshes.remove(me)
    return True
