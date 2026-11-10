"""weapons_pickups.py - pickup props: ammo_box, medkit, armor_vest, cash_stack, cash_bag,
parachute_pack, scuba_tank, weapon_crate. Origin at the bottom centre, +Y = front, single mesh
'Body' (see weapons.py for the toolkit / contract). Exported to models/props/pickups/<id>.glb."""
import math
from mathutils import Matrix
from weapons import (Part, begin, assemble, builder, RZ90, PI)


@builder("ammo_box")
def build_ammo_box():
    """Olive steel ammunition can with a carry handle, stencil marks and three loose rounds."""
    root = begin("ammo_box")
    A = Part(bevel=0.006)
    A.boxc((0.150, 0.290, 0.165), (0, 0, 0.0825), "OliveDrab")
    A.boxc((0.158, 0.298, 0.024), (0, 0, 0.177), "OliveDrab")
    P2 = Part(bevel=0.003)
    D = Part()
    for s in (-1, 1):
        P2.boxc((0.006, 0.200, 0.085), (s * 0.0765, 0, 0.080), "OliveDrab")          # embossed panel
        D.boxc((0.0016, 0.050, 0.030), (s * 0.0800, -0.062, 0.084), "HazardYellow")   # stencil block + bars
        D.boxc((0.0016, 0.095, 0.008), (s * 0.0800, 0.036, 0.096), "HazardYellow")
        D.boxc((0.0016, 0.095, 0.008), (s * 0.0800, 0.036, 0.078), "HazardYellow")
    P2.boxc((0.050, 0.010, 0.078), (0, 0.150, 0.134), "GunMetal")                    # front latch
    D.boxc((0.062, 0.013, 0.012), (0, 0.153, 0.171), "GunMetalDark")
    D.cylx(0.006, -0.060, 0.060, -0.150, 0.170, "GunMetalDark", segs=6)              # rear hinge
    D.strip([(-0.072, 0.188), (-0.056, 0.215), (0.056, 0.215), (0.072, 0.188)], 0.008, 0.024, "GunMetalDark")
    Rn = Part(smooth=40)
    for x, y in ((0.110, 0.072), (0.121, 0.040), (0.106, 0.010)):
        Rn.lathe([(0.0064, 0.0), (0.0064, 0.042), (0.0044, 0.049), (0.0044, 0.055)], "Brass", axis='Z',
                 origin=(x, y, 0), segs=6)
        Rn.lathe([(0.0044, 0.055), (0.0037, 0.064), (0.0012, 0.074)], "Rust", axis='Z', origin=(x, y, 0), segs=6)
    assemble(root, "Body", [A, P2, D, Rn])
    return root


@builder("medkit")
def build_medkit():
    """First-aid case: red clamshell with a white seam, steel latches, carry handle and an original
    emblem (red heart on a white disc) on both faces."""
    root = begin("medkit")
    A = Part(bevel=0.012)
    A.boxc((0.300, 0.110, 0.210), (0, 0, 0.105), "CarRed")
    Sm = Part(bevel=0.012)
    Sm.boxc((0.3035, 0.010, 0.2135), (0, 0, 0.105), "White")
    Rn = Part(smooth=40)
    Rn.cyl(0.062, 0.050, 0.0585, 0.108, "White", segs=12)
    Rn.cyl(0.062, -0.0585, -0.050, 0.108, "White", segs=12)
    heart = [(0, -0.036), (0.030, -0.006), (0.036, 0.012), (0.030, 0.027), (0.018, 0.032), (0.006, 0.027),
             (0, 0.018), (-0.006, 0.027), (-0.018, 0.032), (-0.030, 0.027), (-0.036, 0.012), (-0.030, -0.006)]
    hp = [(x, z + 0.107) for x, z in heart]
    D = Part()
    D.prism_y(hp, 0.0570, 0.0606, "CarRed")
    D.prism_y(hp, -0.0606, -0.0570, "CarRed")
    for s in (-1, 1):
        D.boxc((0.030, 0.008, 0.034), (s * 0.095, 0.056, 0.182), "Steel")             # latches
        D.boxc((0.022, 0.030, 0.010), (s * 0.052, 0.0, 0.214), "GunMetalDark")        # handle mounts
    vs = D.strip([(-0.060, 0.214), (-0.046, 0.242), (0.046, 0.242), (0.060, 0.214)], 0.010, 0.026, "GunMetalDark")
    Part.xform(vs, RZ90)
    assemble(root, "Body", [A, Sm, Rn, D])
    return root


def _ring(hw, hd, z, c=0.038):
    return [(-hw + c, -hd, z), (hw - c, -hd, z), (hw, -hd + c, z), (hw, hd - c, z), (hw - c, hd, z),
            (-hw + c, hd, z), (-hw, hd - c, z), (-hw, -hd + c, z)]


@builder("armor_vest")
def build_armor_vest():
    """Body-armour vest standing upright: navy carrier, black plate pocket and pouches, shoulder
    straps, cummerbund, drag handle."""
    root = begin("armor_vest")
    V = Part()
    V.loft([_ring(0.150, 0.088, 0.0), _ring(0.166, 0.100, 0.045), _ring(0.176, 0.110, 0.200),
            _ring(0.182, 0.112, 0.330), _ring(0.164, 0.100, 0.400)], "UniformNavy")
    V.loft([_ring(0.171, 0.106, 0.112, c=0.040), _ring(0.180, 0.113, 0.170, c=0.040)], "Charcoal")   # cummerbund
    S = Part(bevel=0.008)
    for s in (-1, 1):
        S.boxc((0.078, 0.178, 0.052), (s * 0.110, 0, 0.420), "UniformNavy")           # shoulder straps
    D = Part()
    D.boxc((0.136, 0.150, 0.008), (0, 0, 0.4012), "Black")                           # neck opening
    for s in (-1, 1):
        D.boxc((0.006, 0.120, 0.086), (s * 0.1795, 0, 0.350), "Black")               # arm holes
        D.boxc((0.050, 0.010, 0.016), (s * 0.110, 0.090, 0.428), "Steel")            # strap buckles
    Pl = Part(bevel=0.006)
    Pl.boxc((0.250, 0.024, 0.170), (0, 0.118, 0.280), "TacticalBlack")               # front plate pocket
    Pl.boxc((0.250, 0.022, 0.230), (0, -0.117, 0.240), "TacticalBlack")              # back plate pocket
    for x in (-0.084, 0.0, 0.084):
        Pl.boxc((0.070, 0.040, 0.110), (x, 0.126, 0.118), "TacticalBlack")           # magazine pouches
        D.boxc((0.072, 0.042, 0.030), (x, 0.127, 0.160), "Charcoal")                 # pouch flaps
    D.boxc((0.110, 0.003, 0.040), (0, 0.1312, 0.325), "Sky")                         # name-tape panel
    D.strip([(-0.132, 0.395), (-0.148, 0.372), (-0.148, 0.332), (-0.132, 0.312)], 0.006, 0.060, "Charcoal")
    assemble(root, "Body", [V, S, D, Pl])
    return root


def _bundle(P, D, cx, cy, z0, rot):
    """One strapped bundle of notes (0.078 x 0.165 x 0.024)."""
    Mx = Matrix.Translation((cx, cy, 0.0)) @ Matrix.Rotation(rot, 4, 'Z')
    Part.xform(P.boxc((0.078, 0.165, 0.024), (0, 0, z0 + 0.012), "ShirtGreen"), Mx)
    Part.xform(D.boxc((0.0806, 0.034, 0.0262), (0, 0, z0 + 0.012), "Cream"), Mx)
    for y in (-0.052, 0.052):
        Part.xform(D.boxc((0.056, 0.046, 0.0014), (0, y, z0 + 0.0244), "Mint"), Mx)


@builder("cash_stack")
def build_cash_stack():
    """Three strapped bundles of green notes."""
    root = begin("cash_stack")
    P = Part(bevel=0.003)
    D = Part()
    _bundle(P, D, -0.043, 0.004, 0.0, 0.06)
    _bundle(P, D, 0.043, -0.004, 0.0, -0.05)
    _bundle(P, D, 0.004, 0.0, 0.024, 0.42)
    assemble(root, "Body", [P, D])
    return root


@builder("cash_bag")
def build_cash_bag():
    """Tied canvas money sack with a coin emblem and notes sticking out of the neck."""
    root = begin("cash_bag")
    S = Part()
    sc = (1.0, 0.86)
    S.lathe([(0.095, 0.0), (0.135, 0.022), (0.150, 0.090), (0.132, 0.170), (0.085, 0.225), (0.048, 0.250),
             (0.052, 0.262), (0.082, 0.298), (0.072, 0.304)], "Khaki", axis='Z', segs=10, scale=sc, spin=PI / 10)
    S.lathe([(0.055, 0.245), (0.055, 0.260)], "TrunkLight", axis='Z', segs=10, scale=sc, spin=PI / 10)
    S.boxc((0.012, 0.016, 0.050), (0.050, 0.030, 0.232), "TrunkLight", rot=(0.3, 0.25, 0))   # rope ends
    S.boxc((0.012, 0.016, 0.044), (0.062, 0.012, 0.228), "TrunkLight", rot=(-0.2, 0.45, 0))
    Rn = Part(smooth=40)
    Rn.cyl(0.050, 0.100, 0.1340, 0.102, "ShirtGreen", segs=12)
    Rn.cyl(0.037, 0.130, 0.1362, 0.102, "Mint", segs=12)
    D = Part()
    for x in (-0.011, 0.011):
        D.boxc((0.009, 0.004, 0.048), (x, 0.1362, 0.102), "ShirtGreen")
    D.boxc((0.042, 0.004, 0.009), (0, 0.1362, 0.102), "ShirtGreen")
    Bn = Part(bevel=0.003)
    Bn.boxc((0.074, 0.022, 0.130), (-0.012, 0.004, 0.300), "ShirtGreen", rot=(0.10, 0.22, 0.2))
    Bn.boxc((0.074, 0.022, 0.120), (0.022, -0.012, 0.292), "ShirtGreen", rot=(-0.12, -0.30, -0.3))
    assemble(root, "Body", [S, Rn, D, Bn])
    return root


@builder("parachute_pack")
def build_parachute_pack():
    """Parachute rig: navy container with teal flaps, grey harness and an orange rip-cord handle.
    Harness side faces -Y."""
    root = begin("parachute_pack")
    A = Part(bevel=0.018)
    A.boxc((0.330, 0.150, 0.440), (0, 0, 0.220), "Navy")
    Fp = Part(bevel=0.010)
    Fp.boxc((0.280, 0.050, 0.150), (0, 0.068, 0.335), "Teal")                        # reserve flap
    Fp.boxc((0.280, 0.056, 0.190), (0, 0.068, 0.130), "Teal")                        # main container flap
    D = Part()
    D.boxc((0.030, 0.006, 0.200), (0, 0.097, 0.135), "Charcoal")                     # closing-pin cover
    D.boxc((0.060, 0.006, 0.026), (0, 0.0945, 0.270), "SafetyOrange")                # pull tab
    D.boxc((0.200, 0.004, 0.012), (0, 0.0942, 0.385), "Charcoal")
    for s in (-1, 1):
        D.strip([(-0.050, 0.446), (-0.098, 0.424), (-0.114, 0.300), (-0.108, 0.130), (-0.070, 0.052)], 0.008, 0.046,
                "Charcoal", x=s * 0.088)
        D.boxc((0.052, 0.012, 0.018), (s * 0.088, -0.117, 0.250), "Steel")           # adjusters
    D.boxc((0.176, 0.008, 0.030), (0, -0.116, 0.318), "Charcoal")                    # chest strap
    D.boxc((0.036, 0.012, 0.040), (0, -0.118, 0.318), "Steel")
    vs = D.strip([(-0.050, 0.438), (-0.036, 0.468), (0.036, 0.468), (0.050, 0.438)], 0.008, 0.030, "Charcoal")
    Part.xform(vs, RZ90)
    ring = []
    for i in range(8):                                                               # rip-cord D-handle
        a = i * PI / 4.0
        ring.append((0.088 + 0.024 * math.cos(a), -0.124, 0.196 + 0.020 * math.sin(a)))
    D.pipe(ring, 0.0045, "SafetyOrange", segs=4, closed=True)
    assemble(root, "Body", [A, Fp, D])
    return root


@builder("scuba_tank")
def build_scuba_tank():
    """Yellow dive cylinder with boot, valve, regulator + hose and a harness back-plate (on -Y)."""
    root = begin("scuba_tank")
    T = Part(smooth=40)
    T.lathe([(0.086, 0.0), (0.091, 0.008), (0.091, 0.076)], "Charcoal", axis='Z', segs=12)
    T.lathe([(0.084, 0.076), (0.084, 0.490), (0.074, 0.535), (0.046, 0.575), (0.030, 0.590), (0.030, 0.602)],
            "HazardYellow", axis='Z', segs=12)
    for z in (0.200, 0.400):
        T.lathe([(0.0868, z), (0.0868, z + 0.036)], "Charcoal", axis='Z', segs=12)
    T.cylz(0.020, 0.602, 0.642, "Chrome", segs=8)
    T.cylx(0.019, 0.020, 0.050, 0.0, 0.624, "Charcoal", segs=8)
    T.cyl(0.024, 0.014, 0.052, 0.624, "Steel", segs=8)
    T.pipe([(0, 0.050, 0.628), (0.030, 0.088, 0.604), (0.072, 0.098, 0.500), (0.094, 0.082, 0.380),
            (0.097, 0.070, 0.300)], 0.0072, "Charcoal", segs=6)
    T.cyl(0.029, 0.052, 0.086, 0.282, "Charcoal", segs=8, x=0.097)
    T.cyl(0.021, 0.0855, 0.0885, 0.282, "Steel", segs=8, x=0.097)
    Bp = Part(bevel=0.008)
    Bp.boxc((0.200, 0.028, 0.360), (0, -0.098, 0.300), "Charcoal")
    D = Part()
    for s in (-1, 1):
        D.strip([(-0.106, 0.468), (-0.150, 0.440), (-0.166, 0.300), (-0.150, 0.170), (-0.108, 0.142)], 0.007, 0.040,
                "Navy", x=s * 0.068)
        D.boxc((0.046, 0.012, 0.018), (s * 0.068, -0.169, 0.300), "Steel")
    assemble(root, "Body", [T, Bp, D])
    return root


@builder("weapon_crate")
def build_weapon_crate():
    """Military weapon crate: olive body on skids, darker lid with battens, steel latches, corner
    brackets, rope handles and stencil marks (no text)."""
    root = begin("weapon_crate")
    A = Part(bevel=0.008)
    A.boxc((0.880, 0.400, 0.240), (0, 0, 0.140), "Olive")
    A.boxc((0.900, 0.420, 0.060), (0, 0, 0.290), "OliveDrab")
    B = Part(bevel=0.004)
    for x in (-0.330, 0.330):
        B.boxc((0.070, 0.416, 0.240), (x, 0, 0.140), "OliveDrab")                    # side battens
        B.boxc((0.070, 0.424, 0.012), (x, 0, 0.324), "Olive")                        # lid battens
        B.boxc((0.070, 0.400, 0.024), (x, 0, 0.012), "WoodDark")                     # skids
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.boxc((0.060, 0.060, 0.066), (sx * 0.423, sy * 0.183, 0.290), "GunMetalDark")   # corner brackets
    D = Part()
    for x in (-0.180, 0.180):
        D.boxc((0.044, 0.012, 0.074), (x, 0.212, 0.262), "Steel")                    # latches
        D.boxc((0.050, 0.016, 0.014), (x, 0.214, 0.292), "GunMetalDark")
    D.boxc((0.170, 0.0030, 0.046), (0.020, 0.2012, 0.150), "HazardYellow")           # stencil block + bars
    D.boxc((0.110, 0.0030, 0.010), (0.190, 0.2012, 0.166), "HazardYellow")
    D.boxc((0.110, 0.0030, 0.010), (0.190, 0.2012, 0.146), "HazardYellow")
    D.prism_y([(-0.225, 0.150), (-0.190, 0.185), (-0.155, 0.150), (-0.190, 0.115)], 0.1990, 0.2026, "SafetyOrange")
    D.boxc((0.240, 0.060, 0.003), (0, 0, 0.3212), "HazardYellow")                    # lid stripe
    for sx in (-1, 1):                                                               # rope handles
        D.pipe([(sx * 0.441, -0.075, 0.195), (sx * 0.474, -0.052, 0.152), (sx * 0.483, 0.0, 0.136),
                (sx * 0.474, 0.052, 0.152), (sx * 0.441, 0.075, 0.195)], 0.0095, "Khaki", segs=6)
        for sy in (-1, 1):
            D.boxc((0.014, 0.044, 0.034), (sx * 0.446, sy * 0.075, 0.198), "OliveDrab")
    assemble(root, "Body", [A, B, D])
    return root
