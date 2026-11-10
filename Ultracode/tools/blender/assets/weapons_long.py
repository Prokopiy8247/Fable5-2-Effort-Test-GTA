"""weapons_long.py - smg, pump_shotgun, auto_shotgun, assault_rifle, carbine, marksman_rifle,
sniper_rifle (see weapons.py for the toolkit / contract)."""
import math
from weapons import (Part, begin, assemble, marker, builder, sh, grip_profile, add_trigger, rail_top,
                     att_suppressor, att_flashlight, att_reflex, att_foregrip, scope_parts, PI)

OCT = math.cos(PI / 8.0)          # inradius factor of an octagon


@builder("smg")
def build_smg():
    """Compact SMG: boxy tintable upper, stick magazine ahead of the trigger, vented shroud,
    skeleton folding stock (shown extended). ~0.61 m."""
    root = begin("smg")
    bz = 0.072
    A = Part(bevel=0.0035)
    B = Part(bevel=0.003)
    D = Part()
    O = Part()
    Rn = Part(smooth=40)
    A.prism([(-0.095, 0.050), (0.200, 0.050), (0.208, 0.058), (0.208, 0.090), (0.198, 0.098), (-0.088, 0.098),
             (-0.095, 0.090)], 0.040, "Finish")
    A.prism([(-0.060, 0.052), (-0.060, 0.034), (0.072, 0.034), (0.076, -0.006), (0.120, -0.006), (0.124, 0.052)],
            0.035, "GunPolymer")
    A.prism(grip_profile(0.036, -0.074, 0.034, -0.016, 0.30), 0.032, "GunPolymer")
    D.ribs_z(-0.060, 0.010, 5, -0.018, 0.016, 0.0346, 0.0045, "GunMetalDark", rake=0.30)
    D.strip([(0.077, 0.006), (0.062, -0.003), (0.040, -0.003), (0.026, 0.006)], 0.005, 0.013, "GunPolymer")
    add_trigger(D, 0.044, 0.034)
    # vented barrel shroud + barrel
    O.cyl(0.0185, 0.208, 0.268, bz, "GunMetal", segs=8, spin=PI / 8)
    for s in (-1, 1):
        for i in range(3):
            D.plate(0.216 + i * 0.017, 0.227 + i * 0.017, bz - 0.005, bz + 0.005, 0.0185 * OCT, "GunMetalDark", side=s)
    Rn.cyl(0.0095, 0.268, 0.300, bz, "GunMetalDark", segs=8)
    Rn.cyl(0.0120, 0.290, 0.300, bz, "Steel", segs=8)
    # rail + sights
    D.rail(-0.060, 0.180, 0.098, pitch=0.024)
    D.box(-0.086, -0.072, 0.098, 0.104, 0.024, "GunMetalDark")
    D.box(0.188, 0.200, 0.098, 0.104, 0.024, "GunMetalDark")
    for s in (-1, 1):
        D.box(-0.086, -0.072, 0.104, 0.121, 0.0045, "GunMetalDark", x=s * 0.0095)
        D.box(0.188, 0.200, 0.104, 0.119, 0.0045, "GunMetalDark", x=s * 0.0095)
    D.box(0.192, 0.196, 0.104, 0.116, 0.003, "GunMetalDark")
    # charging handle (left), ejection port (right), selector
    D.plate(0.095, 0.165, 0.078, 0.085, 0.020, "GunMetalDark", side=-1)
    D.cylx(0.0055, -0.034, -0.020, 0.150, 0.0815, "GunMetalDark", segs=6)
    D.plate(0.068, 0.120, 0.068, 0.090, 0.020, "Steel", side=1)
    for s in (-1, 1):
        D.cylx(0.0030, s * 0.0160, s * 0.0186, 0.004, 0.043, "SafetyOrange", segs=6)
    # stock: hinge block, skeleton frame, butt plate
    A.box(-0.108, -0.093, 0.054, 0.096, 0.034, "GunMetalDark")
    D.strip([(-0.104, 0.088), (-0.296, 0.088), (-0.296, -0.012), (-0.106, 0.060)], 0.009, 0.013, "GunMetalDark",
            closed=True)
    B.prism([(-0.292, 0.097), (-0.308, 0.093), (-0.308, -0.018), (-0.292, -0.022)], 0.030, "GunPolymer")
    assemble(root, "Body", [A, B, D, O, Rn])

    Mg = Part(bevel=0.002)
    Mg.prism([(0.079, 0.030), (0.117, 0.030), (0.121, -0.140), (0.083, -0.140)], 0.026, "GunMetalDark")
    Mg.prism([(0.080, -0.140), (0.124, -0.140), (0.124, -0.150), (0.080, -0.150)], 0.030, "GunPolymer")
    Mg2 = Part()
    Mg2.box(0.096, 0.104, -0.130, -0.012, 0.0278, "GunMetal")
    assemble(root, "Mag", [Mg, Mg2], origin=(0, 0.098, -0.02))

    att_suppressor(root, 0.300, bz, r=0.019, length=0.150)
    att_reflex(root, 0.030, rail_top(0.098))
    att_flashlight(root, 0.212, bz, x=0.0320, r=0.0105, length=0.068, mount=(0.0215, bz, 0.012, 0.016))
    att_foregrip(root, 0.238, bz - 0.0185 * OCT, length=0.085)
    E = Part(bevel=0.002)
    E.prism([(0.079, 0.030), (0.117, 0.030), (0.123, -0.210), (0.085, -0.210)], 0.026, "GunMetalDark")
    E.prism([(0.082, -0.210), (0.126, -0.210), (0.126, -0.220), (0.082, -0.220)], 0.030, "GunPolymer")
    E2 = Part()
    E2.box(0.097, 0.105, -0.200, -0.012, 0.0278, "GunMetal")
    assemble(root, "Att_ExtMag", [E, E2], origin=(0, 0.098, -0.02))

    marker(root, "Muzzle", (0, 0.300, bz))
    marker(root, "Eject", (0.022, 0.094, 0.082))
    marker(root, "Grip_L", (0, 0.098, -0.030))
    return root


@builder("pump_shotgun")
def build_pump_shotgun():
    """Pump-action shotgun: wooden stock and pump, tube magazine, shell saddle. ~1.02 m."""
    root = begin("pump_shotgun", shift=(0, 0, -0.016))
    bz, tz = 0.078, 0.048
    Wd = Part(bevel=0.007)
    Wp = Part(bevel=0.006)
    A = Part(bevel=0.004)
    B = Part(bevel=0.003)
    D = Part()
    Rn = Part(smooth=40)
    Wd.prism([(0.040, 0.070), (-0.030, 0.042), (-0.090, 0.052), (-0.330, 0.040), (-0.335, -0.082), (-0.320, -0.088),
              (-0.105, -0.026), (-0.048, -0.040), (-0.022, -0.034), (0.022, 0.002), (0.040, 0.012)], 0.042, "GunWood")
    B.prism([(-0.331, 0.044), (-0.349, 0.040), (-0.351, -0.086), (-0.335, -0.090)], 0.044, "GunPolymer")
    A.prism([(0.034, 0.010), (0.250, 0.010), (0.250, 0.096), (0.060, 0.096), (0.034, 0.074)], 0.044, "Finish")
    D.strip([(0.050, 0.012), (0.056, -0.014), (0.070, -0.022), (0.104, -0.022), (0.118, 0.010)], 0.005, 0.013,
            "GunMetalDark")
    add_trigger(D, 0.080, 0.010)
    # barrel, magazine tube, clamp, bead
    Rn.cyl(0.0135, 0.250, 0.670, bz, "GunMetalDark", segs=10)
    Rn.cyl(0.0125, 0.250, 0.585, tz, "GunMetalDark", segs=10)
    Rn.cyl(0.0138, 0.580, 0.598, tz, "GunMetal", segs=10)
    B.box(0.552, 0.570, tz - 0.016, bz + 0.017, 0.036, "GunMetal")
    D.box(0.656, 0.664, bz + 0.012, bz + 0.019, 0.0045, "Brass")
    D.box(0.062, 0.080, 0.096, 0.103, 0.014, "GunMetalDark")
    # pump fore-end
    Wp.box(0.325, 0.495, tz - 0.030, tz + 0.020, 0.054, "GunWood")
    D.ribs_y(0.345, 0.475, 7, tz - 0.026, tz + 0.014, 0.0566, 0.007, "Leather")
    D.box(0.250, 0.330, tz + 0.004, tz + 0.013, 0.036, "Steel")
    # ports
    D.plate(0.110, 0.185, 0.058, 0.084, 0.022, "Steel", side=1)
    D.box(0.140, 0.230, 0.007, 0.012, 0.026, "GunMetalDark")
    # shell saddle on the left side
    D.box(0.092, 0.218, 0.040, 0.080, 0.005, "GunPolymer", x=-0.0240)
    for i in range(4):
        y = 0.110 + i * 0.030
        Rn.cylz(0.0100, 0.030, 0.088, "CarRed", segs=8, x=-0.0345, y=y)
        Rn.cylz(0.0106, 0.022, 0.032, "Brass", segs=8, x=-0.0345, y=y)
    assemble(root, "Body", [Wd, Wp, A, B, D, Rn])

    att_suppressor(root, 0.670, bz, r=0.022, length=0.18)
    att_flashlight(root, 0.530, (bz + tz) / 2.0, x=0.0300, r=0.011, length=0.078,
                   mount=(0.020, (bz + tz) / 2.0, 0.012, 0.018))
    att_reflex(root, 0.150, 0.096)
    E = Part(smooth=40)
    E.lathe([(0.0120, 0.585), (0.0120, 0.650), (0.0140, 0.650), (0.0140, 0.664)], "GunMetalDark",
            origin=(0, 0, tz), segs=10)
    E2 = Part(bevel=0.003)
    E2.box(0.628, 0.644, tz - 0.016, bz + 0.017, 0.036, "GunMetal")
    assemble(root, "Att_ExtMag", [E, E2])

    marker(root, "Muzzle", (0, 0.670, bz))
    marker(root, "Eject", (0.024, 0.148, 0.072))
    marker(root, "Grip_L", (0, 0.410, tz - 0.012))
    return root


@builder("auto_shotgun")
def build_auto_shotgun():
    """Box-fed semi-auto shotgun: tintable upper, polymer furniture, big straight magazine. ~1.05 m."""
    root = begin("auto_shotgun")
    bz = 0.078
    A = Part(bevel=0.004)
    H = Part(bevel=0.005)
    B = Part(bevel=0.003)
    D = Part()
    O = Part()
    Rn = Part(smooth=40)
    A.prism([(-0.110, 0.046), (0.270, 0.046), (0.270, 0.104), (0.250, 0.110), (-0.100, 0.110), (-0.110, 0.100)],
            0.046, "Finish")
    A.prism([(-0.070, 0.048), (-0.070, 0.030), (0.076, 0.030), (0.080, -0.014), (0.166, -0.014), (0.172, 0.048)],
            0.040, "GunPolymer")
    A.prism(grip_profile(0.034, -0.076, 0.036, -0.016, 0.30), 0.033, "GunPolymer")
    D.ribs_z(-0.062, 0.008, 5, -0.018, 0.017, 0.0356, 0.0045, "GunMetalDark", rake=0.30)
    D.strip([(0.081, 0.004), (0.066, -0.005), (0.042, -0.005), (0.027, 0.005)], 0.005, 0.013, "GunPolymer")
    add_trigger(D, 0.048, 0.030)
    # handguard with vent slots
    H.prism([(0.270, 0.040), (0.480, 0.046), (0.480, 0.104), (0.270, 0.108)], 0.048, "GunPolymer")
    for i in range(4):
        D.box(0.292 + i * 0.046, 0.326 + i * 0.046, 0.070, 0.086, 0.0494, "GunMetalDark")
    # barrel, gas tube + block, muzzle brake
    Rn.cyl(0.0150, 0.480, 0.660, bz, "GunMetalDark", segs=10)
    Rn.cyl(0.0080, 0.480, 0.590, bz - 0.028, "GunMetalDark", segs=8)
    D.box(0.575, 0.600, bz - 0.038, bz + 0.017, 0.030, "GunMetal")
    O.cyl(0.0200, 0.655, 0.705, bz, "GunMetal", segs=8, spin=PI / 8)
    for s in (-1, 1):
        for y in (0.667, 0.685):
            D.plate(y, y + 0.009, bz - 0.007, bz + 0.007, 0.0200 * OCT, "GunMetalDark", side=s)
    # shell caddy on the right side of the stock
    D.box(-0.292, -0.196, 0.058, 0.094, 0.004, "GunMetalDark", x=0.0205)
    for i in range(3):
        y = -0.274 + i * 0.030
        Rn.cylz(0.0100, 0.052, 0.104, "CarRed", segs=6, x=0.0300, y=y)
        Rn.cylz(0.0106, 0.046, 0.056, "Brass", segs=6, x=0.0300, y=y)
    # fixed stock with lightening cut + butt pad
    H.prism([(-0.110, 0.106), (-0.325, 0.104), (-0.335, 0.094), (-0.335, -0.030), (-0.320, -0.036), (-0.230, 0.030),
             (-0.110, 0.046)], 0.038, "GunPolymer")
    D.prism([(-0.305, 0.026), (-0.240, 0.064), (-0.305, 0.064)], 0.0396, "GunMetalDark")
    B.prism([(-0.331, 0.106), (-0.348, 0.102), (-0.348, -0.034), (-0.331, -0.038)], 0.040, "GunMetalDark")
    # rail + sights
    D.rail(-0.060, 0.250, 0.110, pitch=0.026)
    zt = rail_top(0.110)
    for s in (-1, 1):
        D.box(-0.082, -0.070, 0.110, zt + 0.022, 0.0045, "GunMetalDark", x=s * 0.0095)
    D.box(-0.082, -0.070, zt + 0.018, zt + 0.022, 0.0235, "GunMetalDark")
    D.prism([(0.452, 0.104), (0.474, 0.104), (0.468, 0.140), (0.458, 0.140)], 0.008, "GunMetalDark")
    # ejection port + charging handle (right)
    D.plate(0.050, 0.150, 0.070, 0.098, 0.023, "Steel", side=1)
    D.cylx(0.0055, 0.023, 0.038, 0.168, 0.084, "GunMetalDark", segs=6)
    D.plate(-0.030, 0.012, 0.050, 0.056, 0.020, "GunMetalDark", side=-1, out=0.0015)
    assemble(root, "Body", [A, H, B, D, O, Rn])

    Mg = Part(bevel=0.003)
    Mg.prism([(0.088, 0.020), (0.158, 0.020), (0.154, -0.170), (0.084, -0.170)], 0.036, "GunMetalDark")
    Mg.prism([(0.080, -0.170), (0.158, -0.170), (0.158, -0.181), (0.080, -0.181)], 0.040, "GunPolymer")
    Mg2 = Part()
    Mg2.box(0.100, 0.110, -0.160, -0.022, 0.0378, "GunMetal")
    Mg2.box(0.132, 0.142, -0.160, -0.022, 0.0378, "GunMetal")
    assemble(root, "Mag", [Mg, Mg2], origin=(0, 0.122, -0.02))

    att_suppressor(root, 0.705, bz, r=0.026, length=0.19)
    att_reflex(root, 0.040, zt, w=0.032)
    att_flashlight(root, 0.395, 0.076, x=-0.0370, r=0.011, length=0.078, mount=(-0.0265, 0.076, 0.010, 0.018))
    att_foregrip(root, 0.385, 0.0433, length=0.090)
    Dr = Part(smooth=40)
    Dr.cylx(0.062, -0.027, 0.027, 0.121, -0.088, "GunMetalDark", segs=12)
    Dr.cylx(0.022, -0.031, 0.031, 0.121, -0.088, "GunMetal", segs=8)
    E = Part(bevel=0.003)
    E.prism([(0.088, 0.020), (0.158, 0.020), (0.156, -0.050), (0.086, -0.050)], 0.036, "GunMetalDark")
    assemble(root, "Att_ExtMag", [Dr, E], origin=(0, 0.122, -0.02))

    marker(root, "Muzzle", (0, 0.705, bz))
    marker(root, "Eject", (0.025, 0.100, 0.088))
    marker(root, "Grip_L", (0, 0.385, 0.040))
    return root


@builder("assault_rifle")
def build_assault_rifle():
    """Full-size assault rifle: tintable receiver, tan furniture, curved magazine. ~0.93 m."""
    root = begin("assault_rifle")
    bz = 0.082
    A = Part(bevel=0.004)
    T = Part(bevel=0.0055)
    B = Part(bevel=0.003)
    D = Part()
    O = Part()
    Rn = Part(smooth=40)
    A.prism([(-0.115, 0.036), (0.066, 0.036), (0.068, 0.012), (0.146, 0.008), (0.150, 0.036), (0.205, 0.040),
             (0.205, 0.100), (0.150, 0.106), (-0.070, 0.106), (-0.115, 0.092)], 0.042, "Finish")
    T.prism(grip_profile(0.038, -0.074, 0.034, -0.018, 0.30), 0.033, "GunTan")
    D.ribs_z(-0.060, 0.008, 5, -0.020, 0.015, 0.0352, 0.0045, "GunMetalDark", rake=0.30)
    D.strip([(0.069, 0.016), (0.058, 0.000), (0.040, -0.002), (0.026, 0.008)], 0.005, 0.013, "GunMetalDark")
    add_trigger(D, 0.042, 0.036)
    # handguard with slanted vents
    T.prism([(0.205, 0.044), (0.400, 0.050), (0.400, 0.104), (0.205, 0.108)], 0.047, "GunTan")
    D.ribs_y(0.238, 0.372, 5, 0.070, 0.092, 0.0484, 0.012, "GunMetalDark", slant=0.4)
    # barrel, gas tube, gas block + front sight, flash hider
    Rn.cyl(0.0092, 0.400, 0.560, bz, "GunMetalDark", segs=8)
    Rn.cyl(0.0060, 0.400, 0.462, bz + 0.021, "GunMetalDark", segs=6)
    B.box(0.455, 0.482, bz - 0.014, bz + 0.030, 0.024, "GunMetalDark")
    D.prism([(0.459, bz + 0.030), (0.479, bz + 0.030), (0.473, bz + 0.062), (0.465, bz + 0.062)], 0.007,
            "GunMetalDark")
    O.cyl(0.0125, 0.555, 0.602, bz, "GunMetalDark", segs=8, spin=PI / 8)
    Rn.cyl(0.0134, 0.552, 0.560, bz, "Steel", segs=8)
    # fixed stock + pad
    T.prism([(-0.115, 0.094), (-0.305, 0.086), (-0.315, 0.076), (-0.315, -0.036), (-0.300, -0.042), (-0.225, 0.024),
             (-0.115, 0.040)], 0.038, "GunTan")
    D.prism([(-0.290, 0.020), (-0.235, 0.052), (-0.290, 0.052)], 0.0396, "GunMetalDark")
    B.prism([(-0.311, 0.088), (-0.327, 0.084), (-0.327, -0.040), (-0.311, -0.044)], 0.040, "GunMetalDark")
    # rail, rear sight, controls
    D.rail(-0.060, 0.150, 0.106, pitch=0.021)
    zt = rail_top(0.106)
    D.box(-0.090, -0.074, 0.106, 0.112, 0.024, "GunMetalDark")
    for s in (-1, 1):
        D.box(-0.090, -0.074, 0.112, 0.132, 0.0045, "GunMetalDark", x=s * 0.0095)
    D.plate(0.040, 0.105, 0.068, 0.092, 0.021, "Steel", side=1)
    D.cylx(0.0055, 0.021, 0.036, 0.120, 0.088, "GunMetalDark", segs=6)
    D.plate(-0.020, 0.022, 0.046, 0.052, 0.021, "GunMetalDark", side=-1, out=0.0015)
    for y in (-0.052, 0.176):                                   # receiver pins
        D.cylx(0.0045, -0.0222, 0.0222, y, 0.052, "GunMetalDark", segs=6)
    D.plate(0.152, 0.172, 0.042, 0.054, 0.021, "GunMetalDark", side=1, out=0.0015)   # magazine release
    assemble(root, "Body", [A, T, B, D, O, Rn])

    mag = [(0.076, 0.030), (0.138, 0.030), (0.148, -0.050), (0.174, -0.135), (0.126, -0.150), (0.100, -0.060)]
    Mg = Part(bevel=0.0025)
    Mg.prism(mag, 0.026, "GunMetalDark")
    Mg2 = Part()
    Mg2.strip([(0.108, 0.000), (0.124, -0.055), (0.150, -0.138)], 0.007, 0.0278, "GunMetal")
    assemble(root, "Mag", [Mg, Mg2], origin=(0, 0.110, -0.02))

    att_suppressor(root, 0.602, bz, r=0.020, length=0.165)
    # compact prism optic (original boxy shape)
    Sc = Part(bevel=0.003)
    Sc.prism([(-0.030, zt), (0.070, zt), (0.086, zt + 0.012), (0.086, zt + 0.046), (0.060, zt + 0.052),
              (-0.012, zt + 0.044), (-0.030, zt + 0.034)], 0.036, "GunMetalDark")
    Sc2 = Part()
    Sc2.box(0.0850, 0.0872, zt + 0.015, zt + 0.043, 0.028, "Window")
    Sc2.cyl(0.0130, -0.046, -0.029, zt + 0.023, "GunMetalDark", segs=8)
    Sc2.cyl(0.0100, -0.0475, -0.0455, zt + 0.023, "Window", segs=8)
    Sc2.prism([(-0.008, zt + 0.0448), (0.056, zt + 0.0518), (0.056, zt + 0.0550), (-0.008, zt + 0.0480)], 0.007,
              "CarRed")
    assemble(root, "Att_Scope", [Sc, Sc2])
    att_flashlight(root, 0.322, 0.078, x=0.0365, r=0.0105, length=0.074, mount=(0.0260, 0.078, 0.010, 0.018))
    att_foregrip(root, 0.315, 0.0474, length=0.090)
    E = Part(bevel=0.0025)
    E.prism([(0.076, 0.030), (0.138, 0.030), (0.148, -0.050), (0.176, -0.135), (0.214, -0.205), (0.168, -0.226),
             (0.128, -0.150), (0.100, -0.060)], 0.026, "GunMetalDark")
    E2 = Part()
    E2.strip([(0.108, 0.000), (0.124, -0.055), (0.150, -0.138), (0.188, -0.210)], 0.007, 0.0278, "GunMetal")
    assemble(root, "Att_ExtMag", [E, E2], origin=(0, 0.110, -0.02))

    marker(root, "Muzzle", (0, 0.602, bz))
    marker(root, "Eject", (0.024, 0.072, 0.085))
    marker(root, "Grip_L", (0, 0.300, 0.045))
    return root


@builder("carbine")
def build_carbine():
    """Short flat-top carbine: tintable upper, octagonal free-float handguard with full-length rail,
    collapsible stock. ~0.82 m."""
    root = begin("carbine")
    bz = 0.084
    A = Part(bevel=0.0035)
    Pm = Part(bevel=0.005)
    B = Part(bevel=0.003)
    D = Part()
    O = Part()
    Rn = Part(smooth=40)
    A.prism([(-0.100, 0.066), (0.165, 0.066), (0.165, 0.108), (-0.090, 0.108), (-0.100, 0.098)], 0.040, "Finish")
    A.prism([(-0.100, 0.068), (-0.100, 0.046), (-0.060, 0.036), (0.058, 0.036), (0.060, 0.012), (0.120, 0.008),
             (0.124, 0.040), (0.152, 0.046), (0.152, 0.068)], 0.036, "GunMetalDark")
    Pm.prism(grip_profile(0.038, -0.074, 0.032, -0.018, 0.32), 0.031, "GunPolymer")
    D.ribs_z(-0.060, 0.008, 5, -0.021, 0.013, 0.0332, 0.0045, "GunMetalDark", rake=0.32)
    D.strip([(0.061, 0.014), (0.052, 0.000), (0.038, -0.002), (0.024, 0.008)], 0.005, 0.013, "GunMetalDark")
    add_trigger(D, 0.039, 0.036)
    # buffer tube + collapsible stock
    Rn.cyl(0.0135, -0.270, -0.100, bz, "GunMetalDark", segs=10)
    Pm.prism([(-0.160, 0.104), (-0.285, 0.104), (-0.295, 0.094), (-0.297, -0.030), (-0.282, -0.036), (-0.245, 0.030),
              (-0.160, 0.060)], 0.040, "GunPolymer")
    D.prism([(-0.232, 0.050), (-0.178, 0.062), (-0.178, 0.054), (-0.228, 0.040)], 0.014, "GunMetalDark")
    B.prism([(-0.293, 0.106), (-0.307, 0.102), (-0.309, -0.034), (-0.293, -0.038)], 0.042, "GunMetalDark")
    # octagonal handguard with slots, barrel nut
    hr = 0.0270
    O.cyl(hr, 0.165, 0.400, bz, "GunMetal", segs=8, spin=PI / 8)
    O.cyl(0.0290, 0.160, 0.173, bz, "GunMetalDark", segs=8, spin=PI / 8)
    for s in (-1, 1):
        for i in range(4):
            D.plate(0.190 + i * 0.052, 0.226 + i * 0.052, bz - 0.005, bz + 0.005, hr * OCT, "GunMetalDark", side=s)
    # full-length rail + flip sights
    D.rail(-0.085, 0.395, 0.108, pitch=0.030)
    zt = rail_top(0.108)
    D.prism([(0.360, zt), (0.384, zt), (0.378, zt + 0.034), (0.368, zt + 0.034)], 0.012, "GunMetalDark")
    D.prism([(-0.078, zt), (-0.054, zt), (-0.060, zt + 0.034), (-0.070, zt + 0.034)], 0.012, "GunMetalDark")
    # barrel + flash hider
    Rn.cyl(0.0085, 0.400, 0.472, bz, "GunMetalDark", segs=8)
    O.cyl(0.0115, 0.468, 0.512, bz, "GunMetalDark", segs=8, spin=PI / 8)
    # charging handle, port, deflector, forward assist, selector
    D.box(-0.110, -0.094, 0.096, 0.106, 0.038, "GunMetalDark")
    D.plate(0.015, 0.085, 0.076, 0.098, 0.020, "Steel", side=1)
    D.prism([(-0.014, 0.078), (0.010, 0.078), (-0.004, 0.094)], 0.008, "GunMetalDark", x=0.0225)
    D.cylx(0.0065, 0.019, 0.031, -0.045, 0.092, "GunMetalDark", segs=6)
    D.plate(-0.030, 0.012, 0.050, 0.056, 0.018, "GunMetalDark", side=-1, out=0.0015)
    assemble(root, "Body", [A, Pm, B, D, O, Rn])

    Mg = Part(bevel=0.0025)
    Mg.prism([(0.066, 0.030), (0.116, 0.030), (0.126, -0.085), (0.138, -0.128), (0.092, -0.140), (0.080, -0.085)],
             0.024, "GunMetal")
    Mg2 = Part()
    Mg2.strip([(0.092, 0.000), (0.104, -0.085), (0.114, -0.128)], 0.007, 0.0258, "GunMetalDark")
    assemble(root, "Mag", [Mg, Mg2], origin=(0, 0.095, -0.02))

    att_suppressor(root, 0.512, bz, r=0.019, length=0.155)
    assemble(root, "Att_Scope", scope_parts(-0.012, 0.086, zt + 0.034, r_tube=0.0165, r_obj=0.0195, r_eye=0.0195,
                                            mount_z=zt, ring_ys=(0.040,)))
    att_flashlight(root, 0.318, bz, x=0.0355, r=0.0105, length=0.074, mount=(0.0270, bz, 0.008, 0.016))
    Gp = Part(bevel=0.003)
    hb = bz - hr * OCT
    Gp.prism([(0.225, hb + 0.001), (0.335, hb + 0.001), (0.320, hb - 0.029), (0.262, hb - 0.059), (0.238, hb - 0.055),
              (0.250, hb - 0.025)], 0.028, "GunPolymer")
    assemble(root, "Att_Grip", [Gp])
    E = Part(bevel=0.0025)
    E.prism([(0.066, 0.030), (0.116, 0.030), (0.126, -0.085), (0.140, -0.128), (0.162, -0.195), (0.118, -0.210),
             (0.094, -0.140), (0.080, -0.085)], 0.024, "GunMetal")
    E2 = Part()
    E2.strip([(0.092, 0.000), (0.104, -0.085), (0.116, -0.130), (0.138, -0.196)], 0.007, 0.0258, "GunMetalDark")
    assemble(root, "Att_ExtMag", [E, E2], origin=(0, 0.095, -0.02))

    marker(root, "Muzzle", (0, 0.512, bz))
    marker(root, "Eject", (0.022, 0.050, 0.088))
    marker(root, "Grip_L", (0, 0.280, 0.050))
    return root


@builder("marksman_rifle")
def build_marksman_rifle():
    """Semi-auto marksman rifle: one-piece wooden stock with cheek pad, long barrel, long scope rail,
    box magazine. ~1.12 m."""
    root = begin("marksman_rifle", shift=(0, 0, -0.014))
    bz = 0.086
    Wd = Part(bevel=0.007)
    A = Part(bevel=0.004)
    B = Part(bevel=0.003)
    D = Part()
    Rn = Part(smooth=40)
    Wd.prism([(0.050, 0.062), (-0.025, 0.040), (-0.075, 0.052), (-0.120, 0.080), (-0.345, 0.076), (-0.352, -0.070),
              (-0.338, -0.076), (-0.130, -0.030), (-0.060, -0.046), (-0.028, -0.040), (0.024, 0.002), (0.050, 0.010)],
             0.044, "GunWood")
    Wd.prism([(0.046, 0.010), (0.250, 0.020), (0.470, 0.040), (0.470, 0.076), (0.046, 0.066)], 0.046, "GunWood")
    A.prism([(0.020, 0.060), (0.270, 0.060), (0.270, 0.106), (0.035, 0.106), (0.020, 0.092)], 0.040, "Finish")
    A.prism([(0.270, 0.074), (0.470, 0.076), (0.470, 0.106), (0.270, 0.106)], 0.038, "GunMetal")
    D.ribs_y(0.300, 0.440, 5, 0.084, 0.098, 0.0394, 0.014, "GunMetalDark")
    B.prism([(-0.341, 0.080), (-0.360, 0.076), (-0.362, -0.074), (-0.345, -0.078)], 0.046, "GunMetalDark")
    B.prism([(-0.130, 0.079), (-0.300, 0.076), (-0.300, 0.092), (-0.142, 0.095)], 0.040, "Leather")
    D.strip([(0.040, 0.008), (0.046, -0.016), (0.062, -0.024), (0.092, -0.022), (0.108, 0.014)], 0.005, 0.013,
            "GunMetalDark")
    add_trigger(D, 0.070, 0.012)
    # barrel, muzzle brake, front sight block
    Rn.lathe([(0.0125, 0.270), (0.0125, 0.470), (0.0105, 0.500), (0.0095, 0.715)], "GunMetalDark",
             origin=(0, 0, bz), segs=10)
    B.box(0.708, 0.760, bz - 0.014, bz + 0.014, 0.030, "GunMetal")
    for y in (0.720, 0.738):
        D.box(y, y + 0.010, bz - 0.007, bz + 0.007, 0.0314, "GunMetalDark")
    B.box(0.560, 0.584, bz - 0.012, bz + 0.018, 0.022, "GunMetalDark")
    D.prism([(0.564, bz + 0.018), (0.580, bz + 0.018), (0.576, bz + 0.044), (0.568, bz + 0.044)], 0.006,
            "GunMetalDark")
    # long scope rail
    D.rail(0.030, 0.455, 0.106, pitch=0.030)
    zt = rail_top(0.106)
    # port + charging handle (right), sling studs
    D.plate(0.090, 0.170, 0.078, 0.098, 0.020, "Steel", side=1)
    D.cylx(0.0055, 0.020, 0.036, 0.192, 0.090, "GunMetalDark", segs=6)
    D.cylx(0.0050, -0.024, 0.024, -0.300, -0.050, "Steel", segs=6)
    D.cylx(0.0050, -0.025, 0.025, 0.430, 0.048, "Steel", segs=6)
    assemble(root, "Body", [Wd, A, B, D, Rn])

    Mg = Part(bevel=0.0025)
    Mg.prism([(0.112, 0.030), (0.174, 0.030), (0.178, -0.074), (0.120, -0.080)], 0.028, "GunMetalDark")
    Mg.prism([(0.116, -0.077), (0.181, -0.071), (0.182, -0.081), (0.117, -0.087)], 0.031, "GunPolymer")
    Mg2 = Part()
    Mg2.box(0.141, 0.151, -0.066, 0.006, 0.0298, "GunMetal")
    assemble(root, "Mag", [Mg, Mg2], origin=(0, 0.145, -0.01))

    att_suppressor(root, 0.760, bz, r=0.021, length=0.20)
    assemble(root, "Att_Scope", scope_parts(-0.010, 0.300, zt + 0.034, r_tube=0.0135, r_obj=0.022, r_eye=0.018,
                                            mount_z=zt, ring_ys=(0.075, 0.185)))
    att_flashlight(root, 0.392, 0.090, x=0.0310, r=0.0105, length=0.074, mount=(0.0215, 0.090, 0.010, 0.016))
    # Att_Grip = deployed bipod (stability)
    Bp = Part()
    Bp.box(0.422, 0.456, 0.024, 0.041, 0.036, "GunMetalDark")
    for s in (-1, 1):
        Bp.pipe([(s * 0.014, 0.440, 0.030), (s * 0.088, 0.462, -0.170)], 0.0058, "GunMetalDark", segs=6)
        Bp.boxc((0.020, 0.024, 0.010), (s * 0.090, 0.463, -0.175), "GunPolymer")
    assemble(root, "Att_Grip", [Bp])
    E = Part(bevel=0.0025)
    E.prism([(0.112, 0.030), (0.174, 0.030), (0.180, -0.134), (0.124, -0.140)], 0.028, "GunMetalDark")
    E.prism(sh([(0.116, -0.077), (0.181, -0.071), (0.182, -0.081), (0.117, -0.087)], 0.003, -0.060), 0.031,
            "GunPolymer")
    E2 = Part()
    E2.box(0.143, 0.153, -0.126, 0.006, 0.0298, "GunMetal")
    assemble(root, "Att_ExtMag", [E, E2], origin=(0, 0.145, -0.01))

    marker(root, "Muzzle", (0, 0.760, bz))
    marker(root, "Eject", (0.022, 0.130, 0.092))
    marker(root, "Grip_L", (0, 0.330, 0.030))
    return root


@builder("sniper_rifle")
def build_sniper_rifle():
    """Bolt-action sniper rifle on an olive chassis: heavy barrel, muzzle brake, skeleton stock with
    cheek riser, folded bipod, telescopic sight (part of Body). ~1.25 m."""
    root = begin("sniper_rifle")
    bz = 0.092
    Ch = Part(bevel=0.006)
    A = Part(bevel=0.003)
    B = Part(bevel=0.004)
    D = Part()
    Rn = Part(smooth=40)
    # chassis: fore-end + receiver bed, skeleton butt
    Ch.prism([(-0.065, 0.030), (0.200, 0.030), (0.480, 0.044), (0.480, 0.072), (-0.065, 0.076)], 0.048, "OliveDrab")
    Ch.strip([(-0.050, 0.064), (-0.368, 0.064), (-0.368, -0.048), (-0.300, -0.048), (-0.050, 0.042)], 0.022, 0.040,
             "OliveDrab", closed=True)
    # receiver tube (tintable), bolt shroud, bolt handle + knob, ejection port
    Rn.cyl(0.0185, -0.050, 0.230, bz, "Finish", segs=12)
    Rn.cyl(0.0145, -0.088, -0.050, bz, "GunMetalDark", segs=10)
    Rn.pipe([(0.016, -0.030, bz), (0.040, -0.030, bz - 0.012), (0.054, -0.038, bz - 0.034)], 0.0048, "Steel", segs=6)
    Rn.sphere(0.0115, (0.058, -0.040, bz - 0.041), "GunPolymer", segs=6, rings=4)
    pr = 0.0185 * math.cos(PI / 12.0) - 0.0003
    D.boxc((0.014, 0.070, 0.003), (math.sin(PI / 4) * pr, 0.095, bz + math.cos(PI / 4) * pr), "Steel",
           rot=(0, PI / 4, 0))
    # heavy barrel + muzzle brake
    Rn.lathe([(0.0150, 0.230), (0.0140, 0.300), (0.0112, 0.800)], "GunMetalDark", origin=(0, 0, bz), segs=10)
    A.box(0.795, 0.858, bz - 0.015, bz + 0.015, 0.036, "GunMetal")
    for y in (0.808, 0.832):
        D.box(y, y + 0.012, bz - 0.008, bz + 0.008, 0.0374, "GunMetalDark")
    # grip, guard, trigger
    B.prism(grip_profile(0.032, -0.078, 0.030, -0.022, 0.34), 0.033, "GunPolymer")
    D.ribs_z(-0.064, 0.004, 5, -0.024, 0.011, 0.0352, 0.0045, "GunMetalDark", rake=0.34)
    D.strip([(0.088, 0.012), (0.070, 0.002), (0.044, 0.000), (0.024, 0.010)], 0.005, 0.013, "GunMetalDark")
    add_trigger(D, 0.044, 0.030)
    # cheek riser + butt pad
    B.prism([(-0.130, 0.075), (-0.290, 0.075), (-0.290, 0.100), (-0.142, 0.100)], 0.044, "GunPolymer")
    B.prism([(-0.377, 0.080), (-0.396, 0.076), (-0.396, -0.058), (-0.377, -0.062)], 0.044, "GunMetalDark")
    # scope rail + telescopic sight (default optic, part of Body)
    D.rail(-0.030, 0.220, bz + 0.017, pitch=0.042)
    zt = rail_top(bz + 0.017)
    sz = zt + 0.040
    scope = scope_parts(-0.078, 0.286, sz, r_tube=0.015, r_obj=0.0245, r_eye=0.0195, mount_z=zt,
                        ring_ys=(0.045, 0.165))
    # folded bipod under the fore-end
    for s in (-1, 1):
        Rn.cyl(0.0055, 0.268, 0.452, 0.024, "GunMetalDark", segs=6, x=s * 0.017)
        D.box(0.258, 0.278, 0.015, 0.033, 0.016, "GunPolymer", x=s * 0.017)
    A.box(0.440, 0.470, 0.016, 0.046, 0.046, "GunMetalDark")
    assemble(root, "Body", [Ch, A, B, D, Rn] + scope)

    Mg = Part(bevel=0.0025)
    Mg.prism([(0.088, 0.040), (0.150, 0.040), (0.152, -0.016), (0.092, -0.020)], 0.030, "GunMetalDark")
    Mg.prism([(0.088, -0.018), (0.155, -0.014), (0.156, -0.024), (0.089, -0.028)], 0.033, "GunPolymer")
    assemble(root, "Mag", [Mg], origin=(0, 0.120, 0.0))

    att_suppressor(root, 0.858, bz, r=0.024, length=0.24)
    # Att_Scope = long-range upgrade kit that wraps the default optic: sunshade, eyecup, top-mounted
    # ranging module, big side focus wheel
    K = Part(smooth=40)
    K.lathe([(0.0268, 0.266), (0.0268, 0.376), (0.0228, 0.376), (0.0228, 0.300)], "GunMetalDark",
            origin=(0, 0, sz), segs=10)
    K.cyl(0.0226, 0.2995, 0.3015, sz, "Window", segs=10)
    K.lathe([(0.0218, -0.114), (0.0218, -0.074)], "GunPolymer", origin=(0, 0, sz), segs=10)
    K.cylx(0.0140, -0.036, -0.013, 0.082, sz, "GunMetal", segs=10)
    Kb = Part(bevel=0.002)
    Kb.box(0.048, 0.140, sz + 0.016, sz + 0.046, 0.034, "GunMetalDark")
    Kl = Part()
    Kl.box(0.1392, 0.1412, sz + 0.022, sz + 0.040, 0.024, "Window")
    assemble(root, "Att_Scope", [K, Kb, Kl])
    E = Part(bevel=0.0025)
    E.prism([(0.088, 0.040), (0.150, 0.040), (0.154, -0.070), (0.096, -0.076)], 0.030, "GunMetalDark")
    E.prism(sh([(0.088, -0.018), (0.155, -0.014), (0.156, -0.024), (0.089, -0.028)], 0.003, -0.056), 0.033,
            "GunPolymer")
    assemble(root, "Att_ExtMag", [E], origin=(0, 0.120, 0.0))

    marker(root, "Muzzle", (0, 0.858, bz))
    marker(root, "Eject", (0.024, 0.095, bz + 0.012))
    marker(root, "Grip_L", (0, 0.300, 0.035))
    return root
