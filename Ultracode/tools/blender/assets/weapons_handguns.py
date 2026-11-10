"""weapons_handguns.py - pistol, heavy_pistol (see weapons.py for the toolkit / contract)."""
import math
from weapons import (Part, begin, assemble, marker, builder, sh, add_trigger, att_suppressor, att_reflex, PI)


@builder("pistol")
def build_pistol():
    """Compact semi-auto: polymer frame, tintable slide. ~0.18 m."""
    root = begin("pistol")
    bz = 0.064                                   # bore axis height above the grip centre
    A = Part(bevel=0.0030)
    D = Part()
    Rn = Part(smooth=40)
    # slide
    A.prism([(-0.037, 0.050), (0.133, 0.050), (0.133, 0.072), (0.125, 0.083), (-0.031, 0.083), (-0.037, 0.076)],
            0.034, "Finish")
    # frame + grip in one profile
    A.prism([(0.123, 0.050), (0.123, 0.040), (0.115, 0.033), (0.038, 0.033), (0.033, 0.020), (0.011, -0.070),
             (-0.043, -0.078), (-0.029, -0.010), (-0.025, 0.022), (-0.043, 0.040), (-0.037, 0.050)],
            0.032, "GunPolymer")
    # slide serrations, ejection port (barrel hood), sights
    D.ribs_y(-0.027, -0.003, 5, 0.055, 0.080, 0.0356, 0.0028, "GunMetalDark", slant=0.25)
    D.box(0.050, 0.086, 0.070, 0.0838, 0.0135, "Steel", x=0.0108)
    D.box(0.117, 0.126, 0.083, 0.0885, 0.0045, "GunMetalDark")
    D.box(-0.031, -0.021, 0.083, 0.0855, 0.024, "GunMetalDark")
    for s in (-1, 1):
        D.box(-0.030, -0.022, 0.0855, 0.0898, 0.006, "GunMetalDark", x=s * 0.0072)
    # muzzle
    Rn.cyl(0.0070, 0.130, 0.1375, bz, "Steel", segs=8)
    Rn.cyl(0.0034, 0.130, 0.1345, 0.0545, "GunMetalDark", segs=6)
    # trigger guard + trigger
    D.strip([(0.092, 0.036), (0.090, 0.010), (0.080, -0.001), (0.046, -0.003), (0.027, 0.004)], 0.005, 0.015,
            "GunPolymer")
    add_trigger(D, 0.058, 0.034)
    # accessory rail teeth, controls
    D.ribs_y(0.092, 0.114, 3, 0.0298, 0.0335, 0.024, 0.005, "GunPolymer")
    D.plate(0.030, 0.062, 0.043, 0.048, 0.016, "GunMetalDark", side=-1, out=0.001)
    D.cylx(0.0036, -0.0172, 0.0172, 0.041, 0.023, "GunMetalDark", segs=6)
    for s in (-1, 1):
        D.cylx(0.0027, s * 0.0150, s * 0.0167, -0.016, 0.045, "SafetyOrange", segs=6)
    # grip texture (ribbed side panels follow the rake)
    D.ribs_z(-0.058, 0.006, 6, -0.020, 0.021, 0.0348, 0.0046, "GunMetalDark", rake=0.25)
    assemble(root, "Body", [A, D, Rn])

    mag_body = [(0.006, -0.071), (-0.036, -0.077), (-0.018, 0.028), (0.024, 0.028)]
    mag_plate = [(0.016, -0.0695), (-0.047, -0.0785), (-0.048, -0.087), (0.017, -0.078)]
    Mg = Part(bevel=0.0015)
    Mg.prism(mag_body, 0.021, "GunMetalDark")
    Mg.prism(mag_plate, 0.034, "GunPolymer")
    assemble(root, "Mag", [Mg], origin=(0, -0.012, -0.03))

    # attachments -----------------------------------------------------------------------------
    att_suppressor(root, 0.1375, bz, r=0.0165, length=0.125)

    F = Part(bevel=0.0015)
    F.box(0.080, 0.122, 0.010, 0.0335, 0.024, "GunPolymer")
    F2 = Part(smooth=40)
    F2.cyl(0.0118, 0.116, 0.139, 0.0205, "GunMetalDark", segs=10)
    F2.cyl(0.0094, 0.1385, 0.1402, 0.0205, "White", segs=10)
    assemble(root, "Att_Flashlight", [F, F2])
    marker(root, "Flashlight", (0, 0.1415, 0.0205))

    R = Part(bevel=0.0012)
    R.box(-0.020, 0.014, 0.083, 0.0895, 0.026, "GunMetalDark")
    for s in (-1, 1):
        R.box(0.003, 0.013, 0.0895, 0.112, 0.0034, "GunMetalDark", x=s * 0.0113)
    R.box(0.003, 0.013, 0.109, 0.112, 0.026, "GunMetalDark")
    R2 = Part()
    R2.box(0.0072, 0.0086, 0.0895, 0.109, 0.020, "Window")
    assemble(root, "Att_Scope", [R, R2])

    E = Part(bevel=0.0015)
    E.prism([(-0.0005, -0.107), (-0.0425, -0.113), (-0.018, 0.028), (0.024, 0.028)], 0.021, "GunMetalDark")
    E.prism(sh(mag_plate, -0.0065, -0.036), 0.034, "GunPolymer")
    E.prism([(0.012, -0.073), (-0.041, -0.0805), (-0.047, -0.112), (0.006, -0.1045)], 0.028, "GunPolymer")
    assemble(root, "Att_ExtMag", [E], origin=(0, -0.012, -0.03))

    marker(root, "Muzzle", (0, 0.1375, bz))
    marker(root, "Eject", (0.018, 0.068, 0.079))
    marker(root, "Grip_L", (-0.004, 0.022, -0.028))
    return root


@builder("heavy_pistol")
def build_heavy_pistol():
    """Large-frame revolver-style hand cannon with a slab barrel. ~0.29 m."""
    root = begin("heavy_pistol")
    bz = 0.076
    A = Part(bevel=0.004)
    D = Part()
    Rn = Part(smooth=40)
    Wd = Part(bevel=0.006)
    # slab-sided barrel with full underlug
    A.prism([(0.072, 0.050), (0.222, 0.050), (0.236, 0.060), (0.236, 0.094), (0.072, 0.094)], 0.026, "Finish")
    # frame window around the cylinder + recoil shield
    A.strip([(0.006, 0.044), (0.068, 0.044), (0.068, 0.108), (0.006, 0.108)], 0.013, 0.029, "Finish", closed=True)
    A.prism([(0.004, 0.038), (0.004, 0.1145), (-0.014, 0.1145), (-0.034, 0.092), (-0.044, 0.056), (-0.036, 0.038)],
            0.029, "Finish")
    # wooden grip
    Wd.prism([(0.024, 0.040), (0.028, 0.004), (0.016, -0.046), (0.010, -0.086), (-0.038, -0.094), (-0.048, -0.062),
              (-0.034, -0.012), (-0.040, 0.040)], 0.036, "GunWood")
    for s in (-1, 1):
        D.cylx(0.0048, s * 0.0170, s * 0.0190, -0.010, -0.032, "Brass", segs=6)
    # trigger guard, trigger, hammer
    D.strip([(0.080, 0.040), (0.078, 0.012), (0.066, -0.001), (0.040, -0.004), (0.026, 0.006)], 0.005, 0.013, "Finish")
    add_trigger(D, 0.042, 0.038, w=0.008)
    D.prism([(-0.012, 0.110), (-0.018, 0.127), (-0.040, 0.137), (-0.044, 0.128), (-0.031, 0.119), (-0.030, 0.104)],
            0.010, "GunMetalDark")
    # sights + barrel rib + side slots
    D.box(0.072, 0.204, 0.094, 0.098, 0.011, "GunMetalDark")
    D.prism([(0.200, 0.098), (0.234, 0.094), (0.230, 0.107), (0.222, 0.107)], 0.0055, "GunMetalDark")
    D.box(0.2235, 0.2305, 0.1005, 0.1075, 0.0062, "SafetyOrange")
    D.box(-0.014, 0.002, 0.1145, 0.1175, 0.024, "GunMetalDark")
    for s in (-1, 1):
        D.box(-0.013, -0.005, 0.1175, 0.122, 0.006, "GunMetalDark", x=s * 0.0078)
    D.box(0.100, 0.196, 0.066, 0.074, 0.0272, "GunMetalDark")
    D.plate(0.014, 0.034, 0.064, 0.072, 0.0145, "GunMetalDark", side=-1, out=0.0015)      # cylinder latch
    # muzzle crown
    Rn.cyl(0.0108, 0.2350, 0.2372, bz, "Steel", segs=10)
    Rn.cyl(0.0080, 0.2360, 0.2380, bz, "GunMetalDark", segs=10)
    assemble(root, "Body", [A, Wd, D, Rn])

    # the cylinder is the 'Mag' (swings out on reload)
    C = Part(smooth=40)
    C.cyl(0.0245, 0.0135, 0.0605, bz, "Steel", segs=12, spin=PI / 12)
    C2 = Part()
    for k in range(6):
        a = k * PI / 3.0 + PI / 6.0
        C2.boxc((0.0060, 0.026, 0.0034), (math.sin(a) * 0.0233, 0.0475, bz + math.cos(a) * 0.0233), "GunMetalDark",
                rot=(0, a, 0))
    assemble(root, "Mag", [C, C2], origin=(0, 0.037, bz))

    # attachments -----------------------------------------------------------------------------
    sz = 0.142
    Sc = Part(smooth=40)
    Sc.lathe([(0.0165, -0.036), (0.0165, -0.012), (0.0125, -0.002), (0.0125, 0.098), (0.018, 0.116), (0.018, 0.158)],
             "GunMetalDark", origin=(0, 0, sz), segs=10)
    Sc.cyl(0.0148, 0.1570, 0.1592, sz, "Window", segs=10)
    Sc.cyl(0.0134, -0.0372, -0.0350, sz, "Window", segs=10)
    Sc.cylz(0.0065, sz + 0.011, sz + 0.023, "GunMetal", segs=8, y=0.048)
    Sc.cylx(0.0065, 0.011, 0.023, 0.048, sz, "GunMetal", segs=8)
    Sm = Part(bevel=0.0015)
    Sm.box(0.020, 0.034, 0.1145, sz + 0.016, 0.032, "GunMetal")
    Sm.box(0.082, 0.096, 0.098, sz + 0.016, 0.032, "GunMetal")
    Sm.box(0.016, 0.100, 0.1145, 0.121, 0.014, "GunMetal")
    assemble(root, "Att_Scope", [Sc, Sm])

    F = Part(smooth=40)
    F.lathe([(0.0105, 0.128), (0.0105, 0.186), (0.0135, 0.192), (0.0135, 0.206)], "GunMetalDark",
            origin=(0, 0, 0.0365), segs=10)
    F.cyl(0.0112, 0.2050, 0.2072, 0.0365, "White", segs=10)
    F1 = Part(bevel=0.0012)
    F1.box(0.140, 0.176, 0.044, 0.052, 0.016, "GunMetal")
    assemble(root, "Att_Flashlight", [F, F1])
    marker(root, "Flashlight", (0, 0.2085, 0.0365))

    marker(root, "Muzzle", (0, 0.238, bz))
    marker(root, "Eject", (0.027, 0.037, bz))
    marker(root, "Grip_L", (-0.004, 0.014, -0.045))
    return root
