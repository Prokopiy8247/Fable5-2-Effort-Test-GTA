"""weapons_heavy.py - grenade, molotov, rocket_launcher, grenade_launcher and the projectiles
rocket, grenade_round (see weapons.py for the toolkit / contract)."""
import math
from mathutils import Matrix
from weapons import (Part, begin, assemble, marker, builder, grip_profile, add_trigger, rail_top,
                     att_flashlight, att_reflex, PI)

OCT = math.cos(PI / 8.0)

# shared rocket warhead profile (radius, y) relative to the warhead base; used by the launcher's
# loaded round ('Mag') and by the flying projectile so both match
WARHEAD = [(0.0400, 0.000), (0.0465, 0.020), (0.0465, 0.067), (0.0300, 0.117), (0.0080, 0.155)]


def _warhead(P, y0, z):
    P.lathe([(r, y0 + t) for r, t in WARHEAD], "Charcoal", origin=(0, 0, z), segs=10)
    P.lathe([(0.0476, y0 + 0.029), (0.0476, y0 + 0.043)], "HazardYellow", origin=(0, 0, z), segs=10)
    P.lathe([(0.0082, y0 + 0.154), (0.0058, y0 + 0.170)], "Steel", origin=(0, 0, z), segs=10)


@builder("grenade")
def build_grenade():
    """Fragmentation hand grenade, upright (+Z), origin at the body centre. ~0.13 m tall."""
    root = begin("grenade")
    Bd = Part()
    Bd.lathe([(0.0130, -0.047), (0.0250, -0.041), (0.0318, -0.020), (0.0318, 0.012), (0.0245, 0.033),
              (0.0150, 0.041)], "OliveDrab", axis='Z', segs=8, spin=PI / 8)
    Bd.lathe([(0.0326, -0.0065), (0.0326, -0.0015)], "GunMetalDark", axis='Z', segs=8, spin=PI / 8)
    Bd.lathe([(0.0242, 0.0345), (0.0192, 0.0388)], "HazardYellow", axis='Z', segs=8, spin=PI / 8)
    for k in range(8):                                        # vertical grooves on the facets' edges
        a = k * PI / 4.0 + PI / 8.0
        Bd.boxc((0.0030, 0.0030, 0.030), (math.cos(a) * 0.0312, math.sin(a) * 0.0312, -0.004), "GunMetalDark",
                rot=(0, 0, a))
    Bd.cylz(0.0100, -0.0500, -0.0465, "GunMetal", segs=8)
    Fz = Part(smooth=40)
    Fz.cylz(0.0115, 0.041, 0.058, "GunMetal", segs=8)
    Fz.cylx(0.0018, -0.020, 0.013, 0.002, 0.066, "Chrome", segs=6)
    ring = []
    for i in range(8):
        a = i * PI / 4.0
        ring.append((-0.030 + 0.0125 * math.cos(a), 0.002, 0.060 + 0.0125 * math.sin(a)))
    Fz.pipe(ring, 0.0017, "Chrome", segs=4, closed=True)
    Fb = Part(bevel=0.0015)
    Fb.boxc((0.022, 0.019, 0.015), (0.0, 0.002, 0.0655), "GunMetal")
    Sp = Part()
    Sp.strip([(-0.006, 0.0745), (0.016, 0.0740), (0.030, 0.054), (0.0358, 0.020), (0.0352, -0.014)], 0.0028, 0.015,
             "Steel")
    assemble(root, "Body", [Bd, Fz, Fb, Sp])
    return root


@builder("molotov")
def build_molotov():
    """Fire bottle: green glass bottle with a paper label and a cloth wick. ~0.28 m tall, upright,
    origin at the middle of the bottle body. Marker 'Muzzle' = wick tip (flame point)."""
    root = begin("molotov", shift=(0, 0, 0.030))
    Bt = Part(smooth=40)
    Bt.lathe([(0.0300, -0.092), (0.0340, -0.086), (0.0340, 0.030), (0.0290, 0.052), (0.0140, 0.082), (0.0120, 0.128),
              (0.0150, 0.131), (0.0150, 0.142)], "LeafDark", axis='Z', segs=12)
    Bt.lathe([(0.0348, -0.060), (0.0348, 0.008)], "Cream", axis='Z', segs=12)
    Bt.lathe([(0.0354, -0.036), (0.0354, -0.024)], "Coral", axis='Z', segs=12)
    Rg = Part()
    Rg.lathe([(0.0168, 0.116), (0.0168, 0.130)], "ShirtWhite", axis='Z', segs=8)
    # cloth wick: chunky wad stuffed in the mouth, twisted tip standing up (charred), flat tail
    # hanging down along the neck
    Rg.lathe([(0.0125, 0.138), (0.0185, 0.146), (0.0195, 0.158), (0.0130, 0.168)], "ShirtWhite", axis='Z', segs=6,
             spin=0.3)
    Rg.tbox((0.020, 0.018), (0.009, 0.008), 0.026, (0.002, 0.000, 0.166), "ShirtWhite", top_offset=(0.004, 0.003))
    Rg.tbox((0.0092, 0.0082), (0.004, 0.004), 0.012, (0.006, 0.003, 0.192), "Charcoal", top_offset=(0.002, 0.001))
    Rg.strip([(0.008, 0.156), (0.021, 0.150), (0.0235, 0.126), (0.021, 0.100), (0.027, 0.076)], 0.006, 0.026,
             "ShirtWhite")
    assemble(root, "Body", [Bt, Rg])
    marker(root, "Muzzle", (0.007, 0.003, 0.204))
    return root


@builder("rocket_launcher")
def build_rocket_launcher():
    """Shoulder-fired tube launcher, olive tube with octagonal bumpers, side optic, carry handle.
    The loaded warhead is the separate 'Mag' mesh (hide it after firing). ~1.07 m tube."""
    root = begin("rocket_launcher")
    tz, tr = 0.118, 0.047
    A = Part(bevel=0.004)
    B = Part(bevel=0.005)
    D = Part()
    O = Part()
    Rn = Part(smooth=40)
    # tube + bands
    Rn.cyl(tr, -0.400, 0.470, tz, "OliveDrab", segs=12)
    for y in (-0.360, -0.110, 0.150, 0.400):
        Rn.lathe([(tr + 0.0025, y), (tr + 0.0025, y + 0.024)], "GunMetalDark", origin=(0, 0, tz), segs=12)
    # octagonal bumpers, exhaust venturi, dark tube mouth
    O.cyl(0.060, 0.452, 0.520, tz, "GunMetalDark", segs=8, spin=PI / 8)
    O.cyl(0.060, -0.470, -0.398, tz, "GunMetalDark", segs=8, spin=PI / 8)
    O.lathe([(0.050, -0.468), (0.070, -0.548), (0.062, -0.548), (0.040, -0.490)], "GunMetal", origin=(0, 0, tz),
            segs=8, spin=PI / 8)
    O.cyl(0.043, 0.5190, 0.5212, tz, "Black", segs=8, spin=PI / 8)
    # trigger housing (tintable), grips
    A.prism([(-0.060, 0.040), (0.115, 0.040), (0.125, 0.050), (0.125, 0.078), (-0.060, 0.078)], 0.042, "Finish")
    A.prism(grip_profile(0.042, -0.072, 0.034, -0.016, 0.28), 0.032, "GunPolymer")
    D.ribs_z(-0.058, 0.012, 5, -0.019, 0.016, 0.0342, 0.0045, "GunMetalDark", rake=0.28)
    D.strip([(0.095, 0.040), (0.090, 0.012), (0.076, 0.002), (0.040, 0.000), (0.026, 0.008)], 0.005, 0.013,
            "GunMetalDark")
    add_trigger(D, 0.050, 0.040)
    A.prism([(0.198, 0.076), (0.252, 0.076), (0.241, 0.044), (0.236, -0.035), (0.204, -0.035), (0.208, 0.044)],
            0.032, "GunPolymer")
    D.ribs_z(-0.024, 0.030, 4, 0.2035, 0.2385, 0.0342, 0.0045, "GunMetalDark")
    # shoulder rest
    B.prism([(-0.330, 0.078), (-0.180, 0.078), (-0.195, 0.036), (-0.320, 0.022)], 0.056, "GunPolymer")
    # side optic (left), bracket, lens, eyecup
    A.boxc((0.036, 0.110, 0.052), (-0.074, 0.090, 0.160), "GunMetalDark")
    D.boxc((0.034, 0.050, 0.018), (-0.050, 0.090, 0.146), "GunMetal")
    D.boxc((0.026, 0.0024, 0.036), (-0.074, 0.1458, 0.162), "Window")
    Rn.cyl(0.0140, 0.012, 0.036, 0.160, "GunPolymer", segs=8, x=-0.074)
    # carry handle + front post
    D.strip([(-0.060, tz + tr - 0.004), (-0.035, tz + tr + 0.034), (0.105, tz + tr + 0.034),
             (0.130, tz + tr - 0.004)], 0.010, 0.016, "GunMetalDark")
    D.box(0.400, 0.412, tz + tr - 0.002, tz + tr + 0.030, 0.006, "GunMetalDark")
    assemble(root, "Body", [A, B, D, O, Rn])

    Wn = Part(smooth=40)
    Wn.cyl(0.040, 0.440, 0.546, tz, "Charcoal", segs=10)
    _warhead(Wn, 0.545, tz)
    assemble(root, "Mag", [Wn], origin=(0, 0.520, tz))

    marker(root, "Muzzle", (0, 0.520, tz))
    marker(root, "Eject", (0, -0.548, tz))          # back-blast point
    marker(root, "Grip_L", (0, 0.222, 0.010))
    return root


@builder("grenade_launcher")
def build_grenade_launcher():
    """Six-shot revolving grenade launcher: big drum ('Mag'), stubby 40 mm barrel, foregrip,
    collapsible stock. ~0.72 m."""
    root = begin("grenade_launcher")
    dz, dr = 0.046, 0.058
    bz = dz + 0.034
    A = Part(bevel=0.004)
    Pm = Part(bevel=0.005)
    B = Part(bevel=0.003)
    D = Part()
    Rn = Part(smooth=40)
    # frame around the drum (tintable)
    A.prism([(-0.045, 0.030), (0.070, 0.030), (0.078, -0.023), (0.094, -0.023), (0.094, 0.114), (-0.030, 0.114),
             (-0.045, 0.098)], 0.052, "Finish")
    A.box(0.090, 0.222, 0.106, 0.118, 0.034, "Finish")
    A.prism([(0.216, -0.023), (0.252, -0.023), (0.252, 0.118), (0.216, 0.118)], 0.052, "Finish")
    A.box(0.090, 0.220, -0.023, -0.013, 0.026, "Finish")
    # barrel + muzzle collar + dark bore
    Rn.lathe([(0.0270, 0.250), (0.0270, 0.420), (0.0305, 0.420), (0.0305, 0.440)], "GunMetalDark",
             origin=(0, 0, bz), segs=12)
    Rn.cyl(0.0215, 0.4395, 0.4412, bz, "Black", segs=12)
    # foregrip + clamp
    Pm.prism([(0.300, bz - 0.026), (0.334, bz - 0.026), (0.329, -0.040), (0.296, -0.040)], 0.030, "GunPolymer")
    D.ribs_z(-0.028, 0.032, 4, 0.2975, 0.3320, 0.0322, 0.0045, "GunMetalDark")
    B.box(0.290, 0.344, bz - 0.036, bz - 0.018, 0.042, "GunMetal")
    # pistol grip, guard, trigger
    Pm.prism(grip_profile(0.032, -0.076, 0.034, -0.018, 0.30), 0.032, "GunPolymer")
    D.ribs_z(-0.062, 0.006, 5, -0.019, 0.016, 0.0342, 0.0045, "GunMetalDark", rake=0.30)
    D.strip([(0.076, 0.004), (0.060, -0.006), (0.040, -0.004), (0.026, 0.006)], 0.005, 0.013, "GunMetalDark")
    add_trigger(D, 0.042, 0.030)
    # stock: tube + butt + pad
    Rn.cyl(0.0130, -0.215, -0.040, 0.086, "GunMetalDark", segs=10)
    Pm.prism([(-0.130, 0.106), (-0.250, 0.106), (-0.260, 0.096), (-0.262, -0.030), (-0.247, -0.036), (-0.212, 0.030),
              (-0.130, 0.062)], 0.040, "GunPolymer")
    B.prism([(-0.258, 0.108), (-0.272, 0.104), (-0.274, -0.034), (-0.258, -0.038)], 0.042, "GunMetalDark")
    # rail + ladder sight
    D.rail(0.000, 0.250, 0.118, pitch=0.030)
    zt = rail_top(0.118)
    for s in (-1, 1):
        D.box(0.226, 0.232, zt, zt + 0.050, 0.004, "GunMetalDark", x=s * 0.010)
    for i in range(3):
        D.box(0.226, 0.232, zt + 0.012 + i * 0.016, zt + 0.016 + i * 0.016, 0.022, "GunMetalDark")
    assemble(root, "Body", [A, Pm, B, D, Rn])

    C = Part(smooth=40)
    C.cyl(dr, 0.096, 0.214, dz, "GunMetal", segs=12, spin=PI / 12)
    C2 = Part()
    fr = dr * math.cos(PI / 12.0) - 0.0008
    for k in range(6):
        a = k * PI / 3.0 + PI / 6.0
        C2.boxc((0.018, 0.084, 0.005), (math.sin(a) * fr, 0.160, dz + math.cos(a) * fr), "GunMetalDark",
                rot=(0, a, 0))
    C2.cyl(0.012, 0.2135, 0.2160, dz, "GunMetalDark", segs=8)
    assemble(root, "Mag", [C, C2], origin=(0, 0.155, dz))

    att_reflex(root, 0.045, zt, w=0.032)
    att_flashlight(root, 0.300, bz, x=0.0410, r=0.011, length=0.078, mount=(0.0310, bz, 0.010, 0.018))

    marker(root, "Muzzle", (0, 0.441, bz))
    marker(root, "Eject", (0.062, 0.155, dz))
    marker(root, "Grip_L", (0, 0.314, 0.000))
    return root


@builder("rocket")
def build_rocket():
    """Rocket projectile (flies along +Y, origin at its centre). Marker 'Exhaust' at the nozzle. ~0.58 m."""
    root = begin("rocket")
    R = Part(smooth=40)
    R.lathe([(0.0220, -0.290), (0.0300, -0.262), (0.0400, -0.250), (0.0400, 0.106)], "OliveDrab", segs=10)
    _warhead(R, 0.105, 0.0)
    R.cyl(0.0180, -0.301, -0.289, 0.0, "GunMetalDark", segs=10)
    R.lathe([(0.0410, -0.110), (0.0410, -0.092)], "GunMetalDark", segs=10)
    F = Part()
    for k in range(4):
        vs = F.prism([(-0.286, 0.034), (-0.188, 0.038), (-0.214, 0.090), (-0.276, 0.098)], 0.0045, "Steel")
        Part.xform(vs, Matrix.Rotation(k * PI / 2.0 + PI / 4.0, 4, 'Y'))
    assemble(root, "Body", [R, F])
    marker(root, "Exhaust", (0, -0.301, 0.0))
    return root


@builder("grenade_round")
def build_grenade_round():
    """40 mm launcher grenade (flies along +Y, origin at its centre). ~0.105 m."""
    root = begin("grenade_round")
    R = Part(smooth=40)
    R.lathe([(0.0185, -0.052), (0.0205, -0.048), (0.0205, -0.006)], "Brass", segs=12)
    R.lathe([(0.0213, -0.006), (0.0213, 0.001)], "Steel", segs=12)
    R.lathe([(0.0200, 0.001), (0.0200, 0.018), (0.0165, 0.034), (0.0090, 0.046)], "OliveDrab", segs=12)
    R.lathe([(0.0091, 0.0458), (0.0060, 0.0525)], "HazardYellow", segs=12)
    R.cyl(0.0065, -0.0535, -0.0515, 0.0, "Steel", segs=8)
    assemble(root, "Body", [R])
    marker(root, "Exhaust", (0, -0.053, 0.0))
    return root
