"""lm_all - rebuild, export and re-list every NEON TIDE landmark (SPEC_LANDMARKS.md) in one call.

Run inside Blender (Blender MCP):

    import sys, importlib, io, contextlib
    p = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Max\\tools\\blender"
    if p not in sys.path: sys.path.append(p)
    import lm_all; importlib.reload(lm_all)
    with contextlib.redirect_stdout(io.StringIO()) as buf:     # the glTF exporter is very noisy
        report = lm_all.build_all()                            # or build_all(only=["lm_hangar", "safehouse"])
    print(report)

Modules (each also has its own build_all()):
    lm_shops    shop_garage, shop_guns, safehouse, shop_clothes, shop_market, shop_barber
    lm_airfield lm_gas_station, lm_hangar, lm_control_tower, lm_terminal
    lm_towers   lm_radio_tower, lm_water_tower, lm_lighthouse, lm_crane, lm_parking_garage
    lm_misc     lm_fountain, lm_statue, lm_viewpoint, lm_gazebo, lm_boathouse, lm_ferris_wheel, lm_basketball
    lm_transit  rail_beam_8, rail_pier, rail_station
Shared code: gta_kit (kit, untouched), lm_common (walls/openings/signs/col/manifest), lm_fix (furniture + props).
Every asset is exported to gta/generated/models/landmarks/<id>.glb and its entry in
gta/resources/data/manifests/landmarks.json is replaced; the master .blend is saved once at the end.
"""
import importlib

MODULES = ["lm_shops", "lm_airfield", "lm_towers", "lm_misc", "lm_transit"]


def _modules():
    import gta_kit as K
    import lm_common as C
    import lm_fix as F
    for m in (K, C, F):
        importlib.reload(m)
    import lm_towers                      # lm_misc imports col_strut from lm_towers
    importlib.reload(lm_towers)
    mods = []
    for name in MODULES:
        m = importlib.import_module(name)
        importlib.reload(m)
        mods.append(m)
    return K, C, mods


def build_all(only=None, skip=(), export=True):
    """Rebuild (and export) the landmarks.  only = list of ids; skip = ids to leave untouched."""
    K, C, mods = _modules()
    C.OPEN_TOP = False
    out = []
    for m in mods:
        for name, fn in m.BUILDERS:
            if (only and name not in only) or name in skip:
                continue
            fn()
            if export:
                out.append(C.finish(name, m.NOTES.get(name, ""), export=True, save=False))
            else:
                out.append(C.qa(name))
    if export and out:
        K.save_master()
    return "\n".join(out)
