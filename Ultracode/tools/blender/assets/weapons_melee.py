"""weapons_melee.py - knife, bat, crowbar (see weapons.py for the toolkit / contract)."""
import math
from weapons import (Part, begin, assemble, marker, builder, PI)


@builder("knife")
def build_knife():
    """Combat knife, clip point, blade along +Y, edge down. ~0.32 m."""
    root = begin("knife")
    Bl = Part()
    # (y, z_edge, z_spine, half thickness)
    st = [(0.058, -0.0185, 0.0170, 0.0026), (0.110, -0.0190, 0.0170, 0.0026), (0.165, -0.0180, 0.0170, 0.0025),
          (0.200, -0.0135, 0.0120, 0.0020), (0.224, -0.0060, 0.0060, 0.0014), (0.240, 0.0005, 0.0018, 0.0004)]
    secs = []
    for y, zb, zt, t in st:
        zm = zb + (zt - zb) * 0.42
        secs.append([(-t, y, zt), (t, y, zt), (t, y, zm), (0.0, y, zb), (-t, y, zm)])
    Bl.loft(secs, "Steel")
    Bl.box(0.075, 0.160, 0.0075, 0.0115, 0.0058, "SteelDark")                 # fuller
    for i in range(5):                                                         # saw-back
        y = 0.070 + i * 0.011
        Bl.prism([(y, 0.0165), (y + 0.008, 0.0165), (y + 0.001, 0.0205)], 0.0050, "SteelDark")
    Gd = Part(bevel=0.0018)
    Gd.prism([(0.048, -0.031), (0.062, -0.034), (0.060, 0.024), (0.048, 0.026)], 0.018, "GunMetalDark")
    Gd.box(-0.082, -0.066, -0.0185, 0.0175, 0.022, "GunMetalDark")            # pommel
    H = Part(bevel=0.0035)
    H.prism([(0.050, -0.016), (0.050, 0.0155), (-0.020, 0.0175), (-0.068, 0.0145), (-0.068, -0.016),
             (-0.050, -0.0205), (-0.030, -0.0160), (-0.010, -0.0200), (0.012, -0.0160), (0.032, -0.0200)],
            0.024, "OliveDrab")
    D = Part()
    D.ribs_y(-0.052, 0.034, 6, -0.0125, 0.0125, 0.0256, 0.0045, "GunPolymer")
    D.cylx(0.0035, -0.0118, 0.0118, -0.074, 0.0, "Steel", segs=6)             # lanyard pin
    assemble(root, "Body", [Bl, Gd, H, D])
    marker(root, "Muzzle", (0, 0.240, 0.001))
    marker(root, "Grip_L", (0, -0.03, 0.0))
    return root


@builder("bat")
def build_bat():
    """Wooden baseball bat with a taped handle, along +Y, origin where the right hand grips. ~0.83 m."""
    root = begin("bat")
    B = Part(smooth=50)
    B.lathe([(0.0240, -0.140), (0.0250, -0.128), (0.0150, -0.117), (0.0128, -0.070), (0.0132, 0.120),
             (0.0170, 0.240), (0.0250, 0.380), (0.0315, 0.500), (0.0335, 0.610), (0.0315, 0.668), (0.0210, 0.690)],
            "Wood", segs=12)
    T = Part()                                     # grip tape: stepped wraps (flat shaded)
    for i in range(7):
        y = -0.106 + i * 0.030
        r = 0.0146 + (0.0006 if i % 2 else 0.0)
        T.lathe([(r, y), (r, y + 0.026)], "Charcoal", segs=12)
    Rg = Part(smooth=50)                           # painted rings near the barrel + end cap ring
    Rg.lathe([(0.0222, 0.318), (0.0234, 0.336)], "Teal", segs=12)
    Rg.lathe([(0.0244, 0.352), (0.0250, 0.361)], "Teal", segs=12)
    Rg.lathe([(0.0338, 0.630), (0.0330, 0.652)], "WoodDark", segs=12)
    assemble(root, "Body", [B, T, Rg])
    marker(root, "Muzzle", (0, 0.690, 0.0))
    marker(root, "Grip_L", (0, -0.085, 0.0))
    return root


@builder("crowbar")
def build_crowbar():
    """Octagonal steel crowbar: gooseneck claw at +Y, chisel tip at -Y. ~0.58 m."""
    root = begin("crowbar")
    r = 0.0095
    C = Part()
    # shaft + gooseneck (bends up/back in the YZ plane)
    neck = []
    cx, cz, R = 0.332, 0.046, 0.046                # hook arc centre / radius
    for i in range(9):
        a = -PI / 2.0 + i * (PI * 1.02 / 8.0)      # from pointing down (shaft tangent) around the front
        neck.append((0.0, cx + R * math.cos(a), cz + R * math.sin(a)))
    path = [(0, -0.150, 0.0), (0, -0.050, 0.0), (0, 0.120, 0.0), (0, 0.270, 0.0)] + neck
    rad = [(r, r)] * 4 + [(r, r), (r, r), (r * 1.02, r * 0.96), (r * 1.08, r * 0.90), (r * 1.18, r * 0.80),
                          (r * 1.32, r * 0.68), (r * 1.50, r * 0.55), (r * 1.66, r * 0.42), (r * 1.78, r * 0.30)]
    C.pipe(path, rad, "CarRed", segs=8, spin=PI / 8)
    # claw prongs (bare steel, V-notch between them)
    end = neck[-1]
    prev = neck[-2]
    dy, dz = end[1] - prev[1], end[2] - prev[2]
    ln = math.hypot(dy, dz)
    dy, dz = dy / ln, dz / ln
    for s in (-1, 1):
        C.pipe([(s * 0.0085, end[1] - dy * 0.004, end[2] - dz * 0.004),
                (s * 0.0095, end[1] + dy * 0.020, end[2] + dz * 0.020),
                (s * 0.0105, end[1] + dy * 0.040, end[2] + dz * 0.040 + 0.002)],
               [(0.0080, 0.0030), (0.0066, 0.0024), (0.0040, 0.0008)], "Steel", segs=6)
    # chisel end: slight upward kick, flattened, bare steel
    C.pipe([(0, -0.150, 0.0), (0, -0.172, 0.002), (0, -0.196, 0.009), (0, -0.218, 0.020)],
           [(r, r), (r * 1.25, r * 0.70), (r * 1.60, r * 0.40), (r * 1.80, r * 0.10)], "Steel", segs=8, spin=PI / 8)
    # collars where paint ends
    K = Part()
    K.cyl(r * 1.22, -0.156, -0.144, 0.0, "GunMetalDark", segs=8, spin=PI / 8)
    K.cyl(r * 1.22, 0.262, 0.274, 0.0, "GunMetalDark", segs=8, spin=PI / 8)
    assemble(root, "Body", [C, K])
    marker(root, "Muzzle", (0, 0.372, 0.070))
    marker(root, "Grip_L", (0, -0.10, 0.0))
    return root
