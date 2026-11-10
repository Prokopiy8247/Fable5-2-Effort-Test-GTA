"""car_kit_examples - UNPOLISHED starter parameter sets that prove car_kit can do other silhouettes.

These are NOT shipped assets.  They exist so that the artists of compact / sports / muscle / suv /
pickup / van / service vehicles have a working starting point: copy the dict into your own module,
rename it, then iterate on proportions and add your own geometry in an `extras(car)` function.

    import car_kit as K, car_kit_examples as E
    car = E.demo("suv", G.slot("cars", 34))     # builds root 'kitdemo_suv'
    G.preview("kitdemo_suv", "kitdemo_suv", views=("three_quarter", "side", "rear_quarter", "front"))
    G.delete_hierarchy("kitdemo_suv")           # clean up your test build

Lessons baked into these numbers (see docs/VEHICLE_KIT.md):
  * the fender must clear the tyre: zt(axle) - crease_drop  >  wheel_r*2 + arch_gap  (the kit prints
    'ARCH CLAMPED' when it does not);
  * doors should start ~10 cm behind the front arch and end before the rear arch;
  * keep `plan` at 1.0 over both axles, taper only the last ~45 cm of nose and tail.
"""
import gta_bl as G
import car_kit as K


def _p(**kw):
    d = dict(K.DEFAULTS)
    d.update(kw)
    return d


EXAMPLES = {
    # 3.74 m three-door hatchback
    "hatch": _p(
        width=1.68, height=1.48, axle_f=1.18, axle_r=-1.17, wheel_r=0.31, wheel_w=0.20, track=1.44,
        top=[(-1.82, 0.84), (-1.66, 0.96), (0.72, 0.92), (1.62, 0.80), (1.82, 0.70)],
        bottom=[(-1.82, 0.36), (-1.55, 0.24), (1.50, 0.22), (1.82, 0.30)],
        plan=[(-1.82, 0.86), (-1.62, 0.97), (-1.45, 1.0), (1.45, 1.0), (1.66, 0.95), (1.82, 0.84)],
        swage_z=0.58, cowl_y=0.72, roof_f=0.12, roof_r=-1.28, deck_y=-1.64, c_pillar=(0.20, 0.14),
        doors=[("F", -0.30, 0.70)], trunk=None, seat_f_y=-0.25, seat_r_y=-0.98,
        tail=dict(w=0.26, h=0.16, inset=0.02, z=None), wheel_style="classic"),
    # 4.86 m five-door SUV
    "suv": _p(
        width=1.92, height=1.78, axle_f=1.45, axle_r=-1.40, wheel_r=0.38, wheel_w=0.26, track=1.62,
        top=[(-2.38, 1.00), (-2.30, 1.12), (1.00, 1.08), (2.10, 0.98), (2.38, 0.86)],
        bottom=[(-2.38, 0.46), (-2.00, 0.34), (2.00, 0.32), (2.38, 0.42)],
        plan=[(-2.38, 0.90), (-2.15, 0.98), (-1.90, 1.0), (1.90, 1.0), (2.20, 0.96), (2.38, 0.86)],
        swage_z=0.74, rocker_z=0.46, tub_z=0.36, seat_z=0.62,
        cowl_y=1.00, roof_f=0.45, roof_r=-2.06, deck_y=-2.30, c_pillar=(0.16, 0.14), tumble=0.11,
        pillars_extra=[(-1.16, -0.98, -1.14, -1.00)],
        doors=[("F", -0.10, 0.95), ("R", -0.98, -0.10)], trunk=None,
        seat_f_y=-0.05, seat_r_y=-0.92, wheel_style="offroad", arch_lip="trim",
        head=dict(w=0.34, h=0.16, inset=0.02, z=None), tail=dict(w=0.20, h=0.30, inset=0.02, z=None)),
    # 4.40 m two-seat wedge sports car
    "wedge": _p(
        width=1.90, height=1.20, axle_f=1.32, axle_r=-1.28, wheel_r=0.33, wheel_w=0.26, track=1.60,
        top=[(-2.15, 0.84), (-1.45, 0.92), (0.55, 0.86), (1.80, 0.71), (2.15, 0.54)],
        bottom=[(-2.15, 0.30), (-1.80, 0.20), (1.80, 0.17), (2.15, 0.22)],
        plan=[(-2.15, 0.90), (-1.90, 0.99), (-1.60, 1.0), (1.60, 1.0), (1.95, 0.93), (2.15, 0.80)],
        crease_drop=0.05, swage_z=0.50, rocker_z=0.28, tub_z=0.19, seat_z=0.38, tumble=0.17,
        cowl_y=0.55, roof_f=-0.18, roof_r=-0.82, deck_y=-1.45, c_pillar=(0.34, 0.20), a_pillar=0.16,
        doors=[("F", -0.55, 0.50)], seat_f_y=-0.42, seat_r_y=None, b_pillar=None,
        head=dict(w=0.30, h=0.07, inset=0.02, z=None), grille=None, wheel_style="sport",
        tail=dict(w=0.50, h=0.09, inset=0.02, z=None)),
    # 5.34 m single-cab pickup (the bed tub is added by extras)
    "pickup": _p(
        width=1.94, height=1.80, axle_f=1.72, axle_r=-1.55, wheel_r=0.39, wheel_w=0.27, track=1.64,
        top=[(-2.62, 1.06), (0.95, 1.10), (2.30, 1.00), (2.62, 0.88)],
        bottom=[(-2.62, 0.50), (-2.30, 0.38), (2.25, 0.36), (2.62, 0.46)],
        plan=[(-2.62, 0.95), (-2.40, 1.0), (2.10, 1.0), (2.45, 0.96), (2.62, 0.88)],
        swage_z=0.78, rocker_z=0.50, tub_z=0.40, seat_z=0.66,
        cowl_y=0.95, roof_f=0.42, roof_r=-0.36, deck_y=-0.48, c_pillar=(0.10, 0.10), tumble=0.11,
        doors=[("F", -0.40, 0.90)], trunk=None, open_top=[(-2.56, -0.56)], b_pillar=None,
        seat_f_y=-0.02, seat_r_y=None, wheel_style="offroad", arch_lip="trim",
        head=dict(w=0.30, h=0.18, inset=0.02, z=None), tail=dict(w=0.14, h=0.30, inset=0.02, z=None)),
    # 5.00 m panel van
    "van": _p(
        width=1.96, height=2.05, axle_f=1.72, axle_r=-1.45, wheel_r=0.35, wheel_w=0.24, track=1.66,
        top=[(-2.45, 1.02), (-2.38, 1.12), (1.52, 1.08), (2.22, 0.94), (2.45, 0.80)],
        bottom=[(-2.45, 0.42), (-2.10, 0.30), (2.10, 0.28), (2.45, 0.38)],
        plan=[(-2.45, 0.94), (-2.25, 1.0), (2.05, 1.0), (2.30, 0.96), (2.45, 0.88)],
        swage_z=0.70, rocker_z=0.42, tub_z=0.32, seat_z=0.62, tumble=0.07,
        cowl_y=1.52, roof_f=1.12, roof_r=-2.34, deck_y=-2.38, c_pillar=(0.10, 0.10), a_pillar=0.12,
        pillars_extra=[(-2.30, 0.42, -2.26, 0.42)], b_pillar=None,
        doors=[("F", 0.50, 1.24)], trunk=None, seat_f_y=0.62, seat_r_y=None, wheel_style="steel",
        head=dict(w=0.30, h=0.16, inset=0.02, z=None), tail=dict(w=0.14, h=0.34, inset=0.02, z=None)),
}


def pickup_extras(car):
    """Bed tub for the pickup example: floor, inner walls, cab back wall."""
    p, M, b = car.p, car.M, car.body
    (y0, y1), = p["open_top"]
    xb = car.belt_x((y0 + y1) / 2.0) - 0.03
    zf = car.zc + car.Ra + 0.03
    zt = car.zt((y0 + y1) / 2.0)
    b.face([(-xb, y0, zf), (xb, y0, zf), (xb, y1, zf), (-xb, y1, zf)], M["trim"], want=(0, 0, 1))
    b.face([(xb, y0, zf), (xb, y1, zf), (xb, y1, zt), (xb, y0, zt)], M["paint"], mirror=True, want=(-1, 0, 0))
    b.face([(-xb, y1, zf), (xb, y1, zf), (xb, y1, zt), (-xb, y1, zt)], M["paint"], want=(0, -1, 0))
    b.face([(-xb, y0, zf), (xb, y0, zf), (xb, y0, zt), (-xb, y0, zt)], M["paint"], want=(0, 1, 0))
    # bed rail caps
    b.box((0.07, y1 - y0 + 0.06, 0.03), (xb + 0.035, (y0 + y1) / 2.0, zt + 0.012), M["trim"], mirror=True)


EXTRAS = {"pickup": pickup_extras}


def demo(kind, location=None, name=None):
    """Build one example as root 'kitdemo_<kind>' and return the Car."""
    params = dict(EXAMPLES[kind])
    params["name"] = name or ("kitdemo_" + kind)
    car = K.build_car(params, location if location is not None else G.slot("cars", 34), extras=EXTRAS.get(kind))
    car.report()
    return car
