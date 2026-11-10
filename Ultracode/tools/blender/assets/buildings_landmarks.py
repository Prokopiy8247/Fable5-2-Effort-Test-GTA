"""buildings_landmarks - the landmark / walk-in buildings of Halcyon Bay (Blender 5.2 via MCP).

Entry module. The builders live in:
    buildings_landmarks_shops.py     gun_shop, clothing_store, general_store, barber
    buildings_landmarks_civic.py     police_station, hospital, safehouse
    buildings_landmarks_service.py   mod_garage, gas_station, shooting_range
    buildings_landmarks_infra.py     airport_hangar, airport_tower, lighthouse, tram_stop, radio_mast, pier_*
helpers in landmark_kit.py (LK), all on top of building_kit.py (K) and gta_bl.py (G).

Inside an MCP `execute_blender_code` call:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    for p in (P, P + r"\\assets"):
        if p not in sys.path: sys.path.append(p)
    import gta_bl as G; importlib.reload(G)
    import buildings_landmarks as LM; importlib.reload(LM); LM.reload()
    G.assert_master()
    LM.run(["gun_shop"])                          # rebuild + audit + measure + exterior / interior previews
    LM.run(LM.ORDER, preview=False, export=True)  # everything -> GLBs
    LM.write_manifest()                           # manifest_landmarks.json from live measurements
    G.save()

Blender: collection GTA_GODOT/Buildings/Landmarks, slot region "landmarks", slots = index in ORDER.
Exports: gta/generated/models/buildings/<id>.glb. Previews: qa/blender_previews/lm_<id>*.png.
"""
import importlib
import json
import os

import bpy
import gta_bl as G
import building_kit as K
import landmark_kit as LK

ORDER = ["police_station", "hospital", "gun_shop", "shooting_range", "mod_garage", "clothing_store", "barber",
         "general_store", "gas_station", "safehouse", "airport_hangar", "airport_tower", "lighthouse", "tram_stop",
         "radio_mast", "pier_straight", "pier_end", "pier_ramp"]
SLOT = dict((n, i) for i, n in enumerate(ORDER))
MANIFEST = os.path.join(G.MODELS_DIR, "buildings", "manifest_landmarks.json")
_MODULES = ("buildings_landmarks_shops", "buildings_landmarks_civic", "buildings_landmarks_service",
            "buildings_landmarks_infra")

BUILD = {}       # id -> function(slot)
VIEWS = {}       # id -> dict(cut=2.7, box=None, shots=[(eye, look), ...], lens=15, ext=(views))


def reload():
    """Reload the kit helpers and every builder module (call after importlib.reload(LM))."""
    importlib.reload(LK)
    BUILD.clear()
    VIEWS.clear()
    for mn in _MODULES:
        try:
            m = importlib.import_module(mn)
        except ImportError as e:
            print("LM: module %s not available (%s)" % (mn, e))
            continue
        m = importlib.reload(m)
        BUILD.update(getattr(m, "BUILD", {}))
        VIEWS.update(getattr(m, "VIEWS", {}))
    return sorted(BUILD)


def previews(name, exterior=True, interior=True):
    out = []
    v = VIEWS.get(name, {})
    if exterior:
        out.append(K.preview(name, "lm_" + name, views=v.get("ext", ("three_quarter", "front", "side", "top")), res=v.get("res", 480)))
    if interior and v.get("cut") is not None:
        cuts = v["cut"] if isinstance(v["cut"], (list, tuple)) else [v["cut"]]
        for i, c in enumerate(cuts):
            out.append(LK.cutaway(name, "lm_%s_cut%s" % (name, "" if i == 0 else str(i + 1)), cut=c, box=v.get("box")))
    if interior and v.get("shots"):
        out.append(LK.shot(name, v["shots"], lens=v.get("lens", 15)))
    return out


def run(names=None, preview=True, interior=True, export=False, exterior=True):
    """Rebuild assets; returns {id: summary}."""
    if not BUILD:
        reload()
    res = {}
    for n in (names or ORDER):
        if n not in BUILD:
            print("LM: no builder for", n)
            continue
        BUILD[n](SLOT[n])
        a = K.audit(n, verbose=False)
        m = K.measure(n)
        res[n] = dict(tris=m["tris"], footprint=m["footprint"], height=m["height"], issues=m["issues"],
                      dup=a["duplicates"], degenerate=a["degenerate"], suspect=a["suspect"])
        print("LM_BUILT %s tris=%d footprint=%s height=%.2f issues=%s dup=%d deg=%d suspect=%d markers=%s" % (
            n, m["tris"], m["footprint"], m["height"], m["issues"], a["duplicates"], a["degenerate"], a["suspect"],
            sorted(LK.check_markers(n))))
        if preview:
            previews(n, exterior, interior)
        if export:
            LK.export(n)
    return res


def export_all(names=None):
    for n in (names or ORDER):
        if bpy.data.objects.get(n) is not None:
            LK.export(n)


def write_manifest(names=None):
    """manifest_landmarks.json for every landmark that is built in the scene AND exported as a GLB
    (an asset that only exists in Blender is skipped and reported, so the manifest never points at a
    missing file). Both landmark artists call this after exporting."""
    names = [n for n in (names or ORDER) if bpy.data.objects.get(n) is not None]
    folder = os.path.dirname(MANIFEST)
    missing = [n for n in names if not os.path.isfile(os.path.join(folder, n + ".glb"))]
    if missing:
        print("LM: not exported yet, left out of the manifest:", missing)
    return K.write_manifest(MANIFEST, [n for n in names if n not in missing])
