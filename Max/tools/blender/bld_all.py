"""bld_all - rebuild + export every asset of SPEC_BUILDINGS.md (run inside Blender through the MCP):

    import sys, importlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import bld_all; importlib.reload(bld_all)
    print(bld_all.build_all())            # rebuild in place, export all GLBs, rewrite the manifest, save the master

Single group: bld_all.build_all(["signs"])  (groups: office, apartment, shop, industrial, house, roof, fronts, signs,
billboards). Preview assemblies live in the modules (bld_facades.qa_shop / qa_ind, bld_house.qa_house, bld_roof.qa,
bld_fronts.qa, bld_signs.qa, bld_billboards.qa) and are removed with bld_parts.untile(tag).
"""
import contextlib
import importlib
import io

import gta_kit as K
import bld_common as B
import bld_parts as P
import bld_qa as Q
import bld_office
import bld_apartment
import bld_facades
import bld_house
import bld_roof
import bld_fronts
import bld_signs
import bld_billboards

MODULES = (B, P, Q, bld_office, bld_apartment, bld_facades, bld_house, bld_roof, bld_fronts, bld_signs, bld_billboards)


def groups():
    """name -> (build function, asset ids, max mesh tris, max lod tris)"""
    return {
        "office": (bld_office.build_all, bld_office.IDS, 350, 12),
        "apartment": (bld_apartment.build_all, bld_apartment.IDS, 350, 12),
        "shop": (bld_facades.build_shop, bld_facades.SHOP_IDS, 350, 12),
        "industrial": (bld_facades.build_ind, bld_facades.IND_IDS, 350, 12),
        "house": (bld_house.build_all, bld_house.IDS, 350, 12),
        "roof": (bld_roof.build_all, bld_roof.IDS, 900, 12),
        "fronts": (bld_fronts.build_all, bld_fronts.IDS, 1500, 40),
        "signs": (bld_signs.build_all, bld_signs.IDS, 560, 12),
        "billboards": (bld_billboards.build_all, bld_billboards.IDS, 900, 12),
    }


def all_ids(names=None):
    g = groups()
    return [a for n in (names or g) for a in g[n][1]]


def build_all(names=None, export=True, save=True):
    for m in MODULES:
        importlib.reload(m)
    g = groups()
    lines = []
    for n in (names or list(g)):
        build, ids, mt, ml = g[n]
        build()
        warn = [w for w in B.check(ids, max_tris=mt, max_lod=ml) if not w.startswith("contract OK")]
        if export:
            with contextlib.redirect_stdout(io.StringIO()):
                B.export(ids, save=False)
        lines.append("%-11s %2d assets %s" % (n, len(ids), "; ".join(warn) if warn else "ok"))
    if save:
        K.save_master()
    return "\n".join(lines)
