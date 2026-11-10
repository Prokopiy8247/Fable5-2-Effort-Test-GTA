"""bld_qa - temporary preview assemblies for the bld_*.py kits (tinted copies, never exported)."""
import math
import bpy
import gta_kit as K
import bld_common as B
import bld_parts as P


def show(tag, items, ta="#e6d3ad", tb="#3f6fa8", part="mesh"):
    """Build `zz_tile_<tag>` from tinted mesh copies. items: (asset_id, (x, y, z)[, rz_deg]).
    Remove it again with hide(tag)."""
    name = "zz_tile_" + tag
    P.untile(tag)
    root = K.begin_asset(name, B.CAT, 30.0)
    mat = P._prev_mat(tag, ta, tb)
    cache = {}
    for k, it in enumerate(items):
        aid, pos = it[0], it[1]
        rz = it[2] if len(it) > 2 else 0.0
        if aid not in cache:
            src = bpy.data.objects.get("%s__%s" % (aid, part)) or bpy.data.objects["%s__mesh" % aid]
            me = src.data.copy()
            for i, m in enumerate(me.materials):
                if m is not None and m.name == "Palette":
                    me.materials[i] = mat
            cache[aid] = me
        o = bpy.data.objects.new("%s__m%03d" % (name, k + 1), cache[aid])
        for c in root.users_collection:
            c.objects.link(o)
        o.parent = root
        o.location = pos
        o.rotation_euler = (0.0, 0.0, math.radians(rz))
    return name


def hide(tag):
    return P.untile(tag)


def grid(tag, ids, cols=4, dx=5.0, dz=0.0, dy=0.0, **kw):
    """Lay assets out in rows (x to the left = +X first so reading order matches a view from +Y)."""
    items = []
    for i, aid in enumerate(ids):
        c, rw = i % cols, i // cols
        items.append((aid, (-(c - (cols - 1) / 2) * dx, -rw * dy, -rw * dz)))
    return show(tag, items, **kw)
