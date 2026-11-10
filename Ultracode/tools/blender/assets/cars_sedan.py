"""cars_sedan - the reference car 'sedan' and the shared alternative wheels (lead vehicle artist).

Run inside an execute_blender_code call (after the gta_bl header, with tools/blender/assets on
sys.path):

    import car_kit as K, cars_sedan as S
    importlib.reload(K); importlib.reload(S)
    S.build_sedan()          # builds 'sedan' at slot cars/0 (rebuilds an existing one)
    S.export_sedan()         # validate + export vehicles/sedan.glb
    S.build_wheels()         # wheel_sport / wheel_classic / wheel_offroad / wheel_deep at cars/30..33
    S.export_wheels()        # vehicles/parts/wheel_<style>.glb
    G.save()

Every other car module should look like this file: a parameter dict on top of K.DEFAULTS plus
(optionally) an `extras(car)` function for geometry the kit does not know about.

Critic pass (cars_a critic): the sedan is built with car_refine.Refined instead of the bare K.Car
(interior-coloured headliner and pillar insides, dash details, rear-view mirror, rear head rests
kept under the rear glass, LOD cabin floor), the rear bench sits 4 cm further forward, and
sedan_extras() adds a third brake light on the parcel shelf.
"""
import gta_bl as G
import car_kit as K
import car_refine as R

SEDAN = dict(K.DEFAULTS)
SEDAN.update(
    name="sedan",
    width=1.80, height=1.45,
    # running gear: wheelbase 2.75 m, 0.68 m wheels (slightly oversized on purpose - art direction)
    axle_f=1.40, axle_r=-1.35, wheel_r=0.34, wheel_w=0.23, track=1.52, wheel_style="stock",
    # three-box profile, tail -> nose (shell is 4.50 m, bumpers add 5 cm at each end = 4.60 m)
    top=[(-2.25, 0.90), (-1.46, 0.965), (0.95, 0.925), (2.03, 0.79), (2.25, 0.68)],
    bottom=[(-2.25, 0.36), (-1.86, 0.24), (1.92, 0.22), (2.25, 0.30)],
    plan=[(-2.25, 0.85), (-2.02, 0.965), (-1.76, 1.0), (1.82, 1.0), (2.07, 0.955), (2.25, 0.83)],
    swage_z=0.60,
    # cabin: long glasshouse, raked screens, thick C pillar
    cowl_y=0.95, roof_f=0.30, roof_r=-0.90, deck_y=-1.46,
    doors=[("F", -0.12, 0.90), ("R", -0.95, -0.12)],
    head=dict(w=0.33, h=0.13, inset=0.02, z=None),
    tail=dict(w=0.38, h=0.14, inset=0.02, z=None),
    seat_r_y=-0.91,           # 4 cm forward of the kit default: head rests clear the rear glass
    seat_color="Khaki",
    mods=list(K.FULL_MODS),
)

WHEEL_PARTS = [("wheel_sport", "sport", 30), ("wheel_classic", "classic", 31),
               ("wheel_offroad", "offroad", 32), ("wheel_deep", "deep", 33)]

PREVIEW_VIEWS = ("three_quarter", "rear_quarter", "side", "front", "top", "back")


def sedan_extras(car):
    """Sedan-only dressing on top of the generic kit build."""
    p, M, b = car.p, car.M, car.body
    # chrome belt-line strip under the side windows is part of the doors in the kit; add a chrome
    # trunk handle strip and a small badge block on the nose
    yf = car.y_f
    b.box((0.10, 0.02, 0.035), (0.0, yf + 0.035, car.zt(yf) - 0.035), M["chrome"], bevel=0.006)
    # third brake light on the parcel shelf, behind the rear glass
    g = car._gh()
    b.box((0.26, 0.05, 0.03), (0.0, g["dy"] + 0.10, g["zd"] - 0.012), M["tail"])
    b.box((0.30, 0.07, 0.014), (0.0, g["dy"] + 0.11, g["zd"] - 0.034), M["trim"])


def build_sedan(preview=True):
    car = R.build_car(SEDAN, G.slot("cars", 0), extras=sedan_extras)
    car.report()
    K.check_contract("sedan")
    if preview:
        G.preview("sedan", "veh_sedan", views=PREVIEW_VIEWS)
    return car


def export_sedan():
    res = G.validate("sedan", max_tris=9000)
    K.export_glb("sedan", "vehicles/sedan.glb")
    return res


def build_wheels(preview=True):
    for name, style, idx in WHEEL_PARTS:
        K.build_wheel_asset(name, style, G.slot("cars", idx) + G.Vector((0.0, 0.0, 0.34)))
        if preview:
            G.preview(name, "veh_" + name, views=("three_quarter", "side", "front", "rear_quarter"), res=360)


def export_wheels():
    out = {}
    for name, style, idx in WHEEL_PARTS:
        out[name] = G.validate(name, max_tris=900)
        K.export_glb(name, "vehicles/parts/%s.glb" % name)
    return out
