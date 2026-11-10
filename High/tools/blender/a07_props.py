"""Street props, nature, pickups, transit pieces and animals. Run through Blender MCP."""
import sys, random
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

CP = coll("StreetProps")
CN = coll("Nature")
CI = coll("Interiors")
CV = coll("VFX_HelperMeshes")
CA = coll("NPCs/Animals")
mat("M_TLon_R", "#ff3020", 0.4, 0.0, emit="#ff3020", emit_strength=4.0)
mat("M_TLon_Y", "#ffc020", 0.4, 0.0, emit="#ffc020", emit_strength=4.0)
mat("M_TLon_G", "#30ff60", 0.4, 0.0, emit="#30ff60", emit_strength=4.0)
mat("M_ChainLink", "#9aa0a8", 0.5, 0.6, alpha=0.35, double=True)
mat("M_Grass", "#5fa043", 0.95, double=True)
mat("M_Flower", "#f0d24a", 0.9, double=True)
mat("M_Coral", "#e8727a", 0.9)
mat("M_Seaweed", "#2f7d4f", 0.9, double=True)
mat("M_Target", "#f1eee6", 0.8)
_n = {"p": 0, "n": 0, "a": 0}


def P(name, fn, c=None, kind="p", children=None):
    c = c or CP
    wipe(name)
    mb = MB()
    fn(mb)
    i = _n[kind]
    _n[kind] += 1
    base = {"p": (-60, -40), "n": (-60, -90), "a": (-60, -120)}[kind]
    ob = mb.build(name, c, loc=(base[0] + (i % 14) * 6.0, base[1] - (i // 14) * 8.0, 0))
    for (cn, cloc, cfn) in (children or []):
        if cfn is None:
            empty(name + "_" + cn, c, loc=cloc, parent=ob)
        else:
            m2 = MB()
            cfn(m2)
            m2.build(name + "_" + cn, c, loc=cloc, parent=ob)
    return ob


# ------------------------------------------------------------------ street
def traffic_light(mb):
    mb.cyl((0, 0, 0.15), 0.22, 0.3, "M_MetalDark", seg=8)
    mb.limb((0, 0, 0.3), (0, 0, 5.6), 0.09, 0.07, "M_MetalDark", seg=6)
    mb.limb((0, 0, 5.5), (-3.6, 0, 5.8), 0.07, 0.05, "M_MetalDark", seg=6)
    mb.box((-3.6, 0, 5.35), (0.38, 0.30, 1.15), "M_Black")
    mb.box((-3.6, -0.16, 5.35), (0.5, 0.04, 1.3), "M_Black")
    for i, m in enumerate(("M_TL_Red", "M_TL_Yellow", "M_TL_Green")):
        mb.cyl((-3.6, -0.19, 5.72 - i * 0.37), 0.12, 0.04, m, axis='Y', seg=8)
    mb.box((0, -0.14, 2.6), (0.24, 0.16, 0.5), "M_Black")


def tl_lamp(m):
    return lambda mb: mb.cyl((0, 0, 0), 0.125, 0.05, m, axis='Y', seg=8)


def street_lamp(mb):
    mb.cyl((0, 0, 0.2), 0.2, 0.4, "M_MetalDark", seg=8)
    mb.limb((0, 0, 0.4), (0, 0, 7.0), 0.08, 0.055, "M_MetalDark", seg=6)
    mb.limb((0, 0, 7.0), (0, -1.9, 7.35), 0.055, 0.045, "M_MetalDark", seg=6)
    mb.box((0, -2.2, 7.32), (0.34, 0.8, 0.12), "M_MetalDark")
    mb.box((0, -2.2, 7.25), (0.26, 0.66, 0.05), "M_LampGlow")


def sign(shape):
    def f(mb):
        mb.limb((0, 0, 0), (0, 0, 2.7), 0.035, 0.035, "M_Metal", seg=5)
        if shape == "stop":
            mb.cyl((0, -0.05, 2.5), 0.38, 0.04, "M_Red", axis='Y', seg=8, phase=math.pi / 8)
            mb.box((0, -0.075, 2.5), (0.5, 0.01, 0.12), "M_White")
        elif shape == "speed":
            mb.cyl((0, -0.05, 2.5), 0.36, 0.04, "M_Red", axis='Y', seg=12)
            mb.cyl((0, -0.06, 2.5), 0.28, 0.04, "M_White", axis='Y', seg=12)
            mb.box((0, -0.085, 2.5), (0.2, 0.01, 0.26), "M_Black")
        elif shape == "parking":
            mb.box((0, -0.05, 2.5), (0.6, 0.04, 0.6), "M_Blue")
            mb.box((-0.05, -0.075, 2.5), (0.1, 0.01, 0.4), "M_White")
            mb.box((0.05, -0.075, 2.6), (0.2, 0.01, 0.2), "M_White")
        elif shape == "street":
            mb.box((0, -0.05, 2.6), (1.1, 0.03, 0.24), "M_Green")
            mb.box((0, -0.07, 2.6), (0.9, 0.01, 0.06), "M_White")
    return f


def barrier_jersey(mb):
    mb.prism([(-0.32, 0), (0.32, 0), (0.30, 0.25), (0.12, 0.5), (0.1, 0.9), (-0.1, 0.9), (-0.12, 0.5), (-0.30, 0.25)], 3.0, "M_Concrete", plane='YZ')


def barrier_plastic(mb):
    mb.prism([(-0.28, 0), (0.28, 0), (0.14, 0.9), (-0.14, 0.9)], 2.0, "M_Orange", plane='YZ')
    mb.box((0, 0, 0.6), (2.02, 0.34, 0.16), "M_White")


def bench(mb):
    for sx in (-0.8, 0.8):
        mb.box((sx, 0, 0.22), (0.08, 0.5, 0.44), "M_MetalDark")
        mb.box((sx, 0.24, 0.65), (0.08, 0.06, 0.5), "M_MetalDark")
    for i in range(3):
        mb.box((0, -0.16 + i * 0.17, 0.46), (1.9, 0.14, 0.05), "M_Wood")
    for i in range(2):
        mb.box((0, 0.27, 0.62 + i * 0.2), (1.9, 0.05, 0.14), "M_Wood")


def bin_(mb):
    mb.cyl((0, 0, 0.45), 0.28, 0.9, "M_DarkGrey", seg=8, r2=0.32)
    mb.cyl((0, 0, 0.94), 0.34, 0.08, "M_Black", seg=8)
    mb.box((0, -0.3, 0.6), (0.3, 0.02, 0.2), "M_Green")


def hydrant(mb):
    mb.cyl((0, 0, 0.3), 0.13, 0.6, "M_Red", seg=8)
    mb.cyl((0, 0, 0.64), 0.15, 0.08, "M_Red", seg=8)
    mb.cyl((0, 0, 0.74), 0.11, 0.14, "M_Red", seg=8, r2=0.03)
    mb.cyl((0, 0, 0.42), 0.06, 0.42, "M_Red", axis='X', seg=6)
    mb.cyl((0, -0.14, 0.42), 0.07, 0.1, "M_Chrome", axis='Y', seg=6)
    mb.cyl((0, 0, 0.03), 0.19, 0.06, "M_Red", seg=8)


def bus_stop(mb):
    for sx in (-1.8, 1.8):
        mb.box((sx, 0.6, 1.25), (0.1, 0.1, 2.5), "M_MetalDark")
        mb.box((sx, -0.6, 1.25), (0.1, 0.1, 2.5), "M_MetalDark")
        mb.box((sx, 0, 1.4), (0.04, 1.2, 1.8), "M_Glass")
    mb.box((0, 0.6, 1.4), (3.6, 0.04, 1.8), "M_Glass")
    mb.box((0, 0, 2.55), (4.0, 1.6, 0.1), "M_Teal")
    mb.box((0, 0.35, 0.45), (2.6, 0.4, 0.06), "M_Wood")
    for sx in (-1.1, 1.1):
        mb.box((sx, 0.35, 0.22), (0.06, 0.36, 0.44), "M_MetalDark")
    mb.limb((2.4, -0.5, 0), (2.4, -0.5, 2.8), 0.04, 0.04, "M_Metal", seg=5)
    mb.box((2.4, -0.55, 2.6), (0.5, 0.04, 0.5), "M_Blue")


def fence_wood(mb):
    for sx in (-1.5, 1.5):
        mb.box((sx, 0, 0.75), (0.12, 0.12, 1.5), "M_WoodDark")
    for i in range(10):
        mb.box((-1.35 + i * 0.3, 0, 0.75), (0.24, 0.04, 1.4), "M_Wood")
    for z in (0.4, 1.1):
        mb.box((0, 0.04, z), (3.0, 0.05, 0.1), "M_WoodDark")


def fence_chain(mb):
    for sx in (-1.5, 1.5):
        mb.limb((sx, 0, 0), (sx, 0, 2.2), 0.04, 0.04, "M_Metal", seg=5)
    mb.box((0, 0, 1.1), (3.0, 0.02, 2.1), "M_ChainLink")
    mb.box((0, 0, 2.18), (3.0, 0.05, 0.05), "M_Metal")


def wall_low(mb):
    mb.box((0, 0, 0.45), (3.0, 0.4, 0.9), "M_Rock")
    mb.box((0, 0, 0.94), (3.1, 0.5, 0.1), "M_Concrete")


def utility_box(mb):
    mb.box((0, 0, 0.7), (0.9, 0.5, 1.4), "M_Grey")
    mb.box((0, -0.26, 0.75), (0.8, 0.02, 1.2), "M_MetalDark")
    mb.box((0, 0, 0.04), (1.0, 0.6, 0.08), "M_Concrete")


def bollard(mb):
    mb.cyl((0, 0, 0.45), 0.09, 0.9, "M_MetalDark", seg=8)
    mb.cyl((0, 0, 0.78), 0.095, 0.1, "M_Yellow", seg=8)


def cone(mb):
    mb.box((0, 0, 0.02), (0.4, 0.4, 0.04), "M_Orange")
    mb.cyl((0, 0, 0.36), 0.15, 0.66, "M_Orange", seg=8, r2=0.03)
    mb.cyl((0, 0, 0.40), 0.115, 0.12, "M_White", seg=8, r2=0.09)


def dumpster(mb):
    mb.box((0, 0, 0.7), (2.0, 1.1, 1.1), "M_Green", top=(2.1, 1.2))
    mb.box((0, 0.05, 1.3), (2.12, 1.25, 0.08), "M_Black", rot=(0.08, 0, 0))
    for sx in (-0.8, 0.8):
        for sy in (-0.4, 0.4):
            mb.cyl((sx, sy, 0.08), 0.08, 0.06, "M_Black", axis='X', seg=6)


def crate(mb):
    mb.box((0, 0, 0.5), (1.0, 1.0, 1.0), "M_Wood")
    for sx in (-1, 1):
        mb.box((sx * 0.5, 0, 0.5), (0.04, 1.04, 0.14), "M_WoodDark", rot=(0.78, 0, 0))
        mb.box((0, sx * 0.5, 0.5), (1.04, 0.04, 0.14), "M_WoodDark", rot=(0, 0.78, 0))
    for z in (0.06, 0.94):
        mb.box((0, 0, z), (1.06, 1.06, 0.1), "M_WoodDark")


def pallet(mb):
    for y in (-0.5, 0, 0.5):
        mb.box((0, y, 0.05), (1.2, 0.1, 0.1), "M_WoodDark")
    for i in range(5):
        mb.box((-0.5 + i * 0.25, 0, 0.12), (0.18, 1.1, 0.03), "M_Wood")


def barrel(m):
    def f(mb):
        mb.cyl((0, 0, 0.45), 0.3, 0.9, m, seg=10)
        for z in (0.05, 0.45, 0.85):
            mb.cyl((0, 0, z), 0.315, 0.04, "M_MetalDark", seg=10)
        if m == "M_Red":
            mb.box((0, -0.3, 0.6), (0.24, 0.02, 0.2), "M_Yellow")
    return f


def mailbox(mb):
    mb.box((0, 0, 0.55), (0.5, 0.45, 0.9), "M_Blue")
    mb.cyl((0, 0, 1.0), 0.225, 0.5, "M_Blue", axis='X', seg=8)
    mb.box((0, -0.24, 0.85), (0.3, 0.02, 0.05), "M_Black")
    for sx in (-0.2, 0.2):
        mb.box((sx, 0, 0.05), (0.06, 0.4, 0.1), "M_MetalDark")


def vending(mb):
    mb.box((0, 0, 0.95), (1.0, 0.8, 1.9), "M_Red")
    mb.box((-0.12, -0.41, 1.15), (0.62, 0.02, 1.2), "M_Neon_B")
    mb.box((0.36, -0.41, 1.1), (0.16, 0.02, 0.5), "M_Black")
    mb.box((0, -0.41, 0.3), (0.7, 0.02, 0.2), "M_Black")


def atm(mb):
    mb.box((0, 0, 0.75), (0.7, 0.6, 1.5), "M_Grey")
    mb.box((0, -0.26, 1.25), (0.6, 0.12, 0.5), "M_Navy", rot=(0.3, 0, 0))
    mb.box((0, -0.31, 1.3), (0.4, 0.02, 0.28), "M_Neon_B", rot=(0.3, 0, 0))
    mb.box((0, -0.32, 0.9), (0.36, 0.06, 0.16), "M_MetalDark")


def newsbox(mb):
    mb.box((0, 0, 0.55), (0.45, 0.4, 0.9), "M_Yellow")
    mb.box((0, -0.21, 0.65), (0.36, 0.02, 0.5), "M_Glass")
    mb.box((0, 0, 0.05), (0.2, 0.2, 0.1), "M_MetalDark")


def planter(mb):
    mb.box((0, 0, 0.3), (1.4, 1.4, 0.6), "M_Concrete", top=(1.6, 1.6))
    mb.box((0, 0, 0.58), (1.4, 1.4, 0.06), "M_Brown")
    mb.ball((0, 0, 1.0), 0.6, "M_Leaf", scale=(1, 1, 0.8), sub=1)
    mb.ball((0.3, 0.2, 0.8), 0.4, "M_LeafLight", sub=1)


def parking_meter(mb):
    mb.limb((0, 0, 0), (0, 0, 1.1), 0.03, 0.03, "M_Metal", seg=5)
    mb.box((0, 0, 1.22), (0.16, 0.12, 0.28), "M_DarkGrey")
    mb.box((0, -0.065, 1.26), (0.1, 0.01, 0.1), "M_Neon_B")


def billboard(mb):
    for sx in (-3.5, 3.5):
        mb.box((sx, 0, 4.0), (0.4, 0.4, 8.0), "M_MetalDark")
    mb.box((0, 0, 9.5), (11.0, 0.5, 4.6), "M_DarkGrey")
    mb.box((0, -0.27, 9.5), (10.4, 0.04, 4.0), "M_Neon_A")
    mb.box((0, -0.3, 9.5), (9.6, 0.04, 3.2), "M_Navy")
    mb.cyl((-2.2, -0.34, 9.5), 1.1, 0.04, "M_Neon_C", axis='Y', seg=12)
    mb.box((1.8, -0.34, 10.0), (3.8, 0.04, 0.5), "M_White")
    mb.box((1.4, -0.34, 9.1), (3.0, 0.04, 0.3), "M_Neon_B")
    mb.box((0, 0.6, 7.3), (11.0, 1.0, 0.1), "M_MetalDark")


def picnic_table(mb):
    mb.box((0, 0, 0.75), (1.8, 0.8, 0.06), "M_Wood")
    for sy in (-0.7, 0.7):
        mb.box((0, sy, 0.45), (1.8, 0.28, 0.05), "M_Wood")
    for sx in (-0.7, 0.7):
        mb.box((sx, 0, 0.38), (0.08, 1.6, 0.08), "M_WoodDark")
        mb.box((sx, 0.3, 0.38), (0.08, 0.08, 0.76), "M_WoodDark", rot=(0.4, 0, 0))
        mb.box((sx, -0.3, 0.38), (0.08, 0.08, 0.76), "M_WoodDark", rot=(-0.4, 0, 0))


def beach_set(mb):
    mb.limb((0, 0, 0), (0, 0, 2.3), 0.03, 0.03, "M_White", seg=5)
    mb.cyl((0, 0, 2.2), 1.5, 0.5, "M_Canopy", seg=8, r2=0.05)
    mb.cyl((0, 0, 1.94), 1.5, 0.04, "M_Canopy2", seg=8)
    for sx in (-1, 1):
        mb.box((sx * 0.9, 0.2, 0.3), (0.6, 1.5, 0.06), "M_Teal" if sx > 0 else "M_Yellow")
        mb.box((sx * 0.9, 1.05, 0.55), (0.6, 0.6, 0.06), "M_Teal" if sx > 0 else "M_Yellow", rot=(0.8, 0, 0))
        for sy in (-0.4, 0.7):
            mb.box((sx * 0.9, sy, 0.14), (0.56, 0.05, 0.28), "M_White")


def lifeguard(mb):
    for sx in (-1.1, 1.1):
        for sy in (-1.1, 1.1):
            mb.limb((sx * 1.2, sy * 1.2, 0), (sx, sy, 2.4), 0.07, 0.07, "M_Wood", seg=5)
    mb.box((0, 0, 2.5), (3.0, 3.0, 0.16), "M_Wood")
    mb.box((0, 0.3, 3.6), (2.4, 2.0, 2.0), "M_White")
    mb.box((0, -0.72, 3.7), (1.6, 0.04, 1.0), "M_WindowDark")
    mb.box((0, 0.2, 4.75), (3.0, 3.0, 0.14), "M_Red", rot=(0.12, 0, 0))
    for i in range(7):
        mb.box((0, -1.7 - i * 0.32, 2.3 - i * 0.33), (1.0, 0.3, 0.06), "M_Wood")
    for sx in (-1.45, 1.45):
        mb.box((sx, 0, 3.0), (0.06, 3.0, 0.06), "M_Wood")


def pier(mb):
    mb.box((0, 0, 1.0), (4.0, 8.0, 0.2), "M_Wood")
    for i in range(8):
        mb.box((0, -3.5 + i * 1.0, 1.105), (3.9, 0.9, 0.02), "M_WoodDark" if i % 2 else "M_Wood")
    for sx in (-1.8, 1.8):
        for sy in (-3.6, 3.6):
            mb.cyl((sx, sy, -3.0), 0.16, 9.0, "M_WoodDark", seg=6)
            mb.cyl((sx, sy, 1.6), 0.19, 0.12, "M_Rock", seg=6)
        mb.box((sx, 0, 1.75), (0.08, 8.0, 0.08), "M_WoodDark")
        mb.box((sx, 0, 1.4), (0.05, 8.0, 0.05), "M_WoodDark")


def dock_crane(mb):
    for sx in (-6, 6):
        for sy in (-4, 4):
            mb.box((sx, sy, 9.0), (0.9, 0.9, 18.0), "M_Yellow")
        mb.box((sx, 0, 17.5), (0.9, 8.0, 1.0), "M_Yellow")
        mb.box((sx, 0, 6.0), (0.5, 8.0, 0.5), "M_Yellow")
    mb.box((0, 0, 18.6), (13.0, 9.0, 1.2), "M_Yellow")
    mb.box((0, -12.0, 19.8), (2.0, 36.0, 1.2), "M_Yellow")
    mb.box((0, -27.0, 21.5), (0.4, 0.4, 3.0), "M_MetalDark")
    mb.limb((0, 0, 26.0), (0, -28.0, 20.4), 0.12, 0.12, "M_MetalDark", seg=4)
    mb.box((0, 0, 22.5), (1.0, 1.0, 7.0), "M_Yellow")
    mb.box((0, -10.0, 18.6), (3.0, 3.6, 2.4), "M_White")
    mb.box((0, -11.85, 18.7), (2.4, 0.06, 1.2), "M_WindowDark")
    mb.limb((0, -20.0, 19.2), (0, -20.0, 10.0), 0.05, 0.05, "M_Black", seg=4)
    mb.box((0, -20.0, 9.8), (2.6, 6.2, 0.4), "M_Red")


def container(mb):
    mb.box((0, 0, 1.3), (2.44, 6.06, 2.6), "M_Paint")
    for i in range(13):
        for sx in (-1, 1):
            mb.box((sx * 1.23, -2.8 + i * 0.466, 1.3), (0.04, 0.2, 2.3), "M_Paint")
    mb.box((0, -3.04, 1.3), (2.2, 0.04, 2.4), "M_Paint")
    for sx in (-0.5, 0.5):
        mb.box((sx, -3.08, 1.3), (0.05, 0.05, 2.3), "M_Steel")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 1.17, sy * 2.98, 1.3), (0.12, 0.12, 2.62), "M_MetalDark")


def ladder(mb):
    for sx in (-0.25, 0.25):
        mb.box((sx, 0, 4.0), (0.06, 0.06, 8.0), "M_Steel")
    for i in range(26):
        mb.box((0, 0, 0.3 + i * 0.3), (0.5, 0.04, 0.04), "M_Steel")
    for z in (2.0, 5.0, 7.8):
        for sx in (-0.25, 0.25):
            mb.box((sx, 0.15, z), (0.04, 0.3, 0.04), "M_Steel")


def ramp(mb):
    mb.prism([(-4.0, 0), (4.0, 0), (4.0, 2.4)], 4.0, "M_Wood", plane='YZ', cap_m="M_WoodDark")
    mb.box((0, 0, 0.02), (4.2, 8.2, 0.04), "M_WoodDark")
    for i in range(4):
        mb.box((0, -2.6 + i * 1.9, 0.42 + i * 0.57), (4.02, 0.5, 0.03), "M_Yellow", rot=(0.29, 0, 0))


def target(mb):
    mb.limb((0, 0, 0), (0, 0, 1.2), 0.04, 0.04, "M_MetalDark", seg=5)
    mb.box((0, 0, 0.03), (0.6, 0.5, 0.06), "M_MetalDark")
    mb.cyl((0, 0, 1.55), 0.45, 0.05, "M_Target", axis='Y', seg=12)
    mb.cyl((0, -0.03, 1.55), 0.32, 0.02, "M_Red", axis='Y', seg=12)
    mb.cyl((0, -0.04, 1.55), 0.2, 0.02, "M_Target", axis='Y', seg=12)
    mb.cyl((0, -0.05, 1.55), 0.08, 0.02, "M_Red", axis='Y', seg=12)


def canopy(mb):
    cells = 7
    span = 6.4
    for i in range(cells):
        t0 = -1 + 2 * i / cells
        t1 = -1 + 2 * (i + 1) / cells
        x0, x1 = t0 * span / 2, t1 * span / 2
        z0 = 6.2 - (t0 ** 2) * 1.2
        z1 = 6.2 - (t1 ** 2) * 1.2
        m = "M_Canopy" if i % 2 == 0 else "M_Canopy2"
        mb.add([(x0, -1.3, z0), (x1, -1.3, z1), (x1, 1.3, z1 + 0.15), (x0, 1.3, z0 + 0.15),
                (x0, -1.3, z0 - 0.22), (x1, -1.3, z1 - 0.22), (x1, 1.3, z1 - 0.05), (x0, 1.3, z0 - 0.05)],
               [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (2, 6, 7, 3), (1, 5, 6, 2), (0, 3, 7, 4)], m)
    for sx in (-1, -0.45, 0.45, 1):
        z = 6.0 - (sx ** 2) * 1.2
        for sy in (-1.2, 1.2):
            mb.limb((sx * span / 2 * 0.95, sy, z), (0.2 * (1 if sx > 0 else -1), 0, 0.3), 0.012, 0.012, "M_Black", seg=3)


def pk(kind):
    def f(mb):
        if kind == "cash":
            for i in range(3):
                mb.box((0, 0, 0.05 + i * 0.07), (0.34, 0.18, 0.06), "M_Cash", rot=(0, 0, i * 0.3))
                mb.box((0, 0, 0.05 + i * 0.07), (0.08, 0.19, 0.065), "M_White", rot=(0, 0, i * 0.3))
        elif kind == "health":
            mb.box((0, 0, 0.16), (0.42, 0.2, 0.32), "M_White")
            mb.box((0, -0.105, 0.16), (0.2, 0.01, 0.07), "M_HealthRed")
            mb.box((0, -0.105, 0.16), (0.07, 0.01, 0.2), "M_HealthRed")
            mb.box((0, 0, 0.34), (0.16, 0.04, 0.04), "M_Grey")
        elif kind == "armor":
            mb.box((0, 0, 0.25), (0.42, 0.2, 0.46), "M_ArmorBlue", top=(0.36, 0.2))
            mb.box((0, -0.105, 0.3), (0.2, 0.02, 0.14), "M_Navy")
            for sx in (-1, 1):
                mb.box((sx * 0.13, 0, 0.5), (0.08, 0.16, 0.1), "M_ArmorBlue")
        elif kind == "ammo":
            mb.box((0, 0, 0.11), (0.36, 0.2, 0.22), "M_Olive")
            mb.box((0, 0, 0.235), (0.38, 0.22, 0.03), "M_Olive")
            mb.box((0, -0.105, 0.12), (0.2, 0.01, 0.08), "M_Yellow")
            mb.box((0, 0, 0.27), (0.14, 0.03, 0.03), "M_MetalDark")
        elif kind == "weapon":
            mb.box((0, 0, 0.14), (0.9, 0.36, 0.28), "M_Olive")
            mb.box((0, 0, 0.29), (0.92, 0.38, 0.04), "M_Olive")
            for sx in (-0.3, 0.3):
                mb.box((sx, -0.19, 0.2), (0.06, 0.02, 0.1), "M_MetalDark")
            mb.box((0, -0.185, 0.14), (0.3, 0.01, 0.1), "M_Yellow")
        elif kind == "parachute":
            mb.box((0, 0, 0.2), (0.36, 0.2, 0.4), "M_Canopy", top=(0.3, 0.16))
            for sx in (-0.1, 0.1):
                mb.box((sx, -0.105, 0.2), (0.04, 0.01, 0.4), "M_Black")
        elif kind == "scuba":
            mb.cyl((0, 0, 0.26), 0.09, 0.5, "M_Tank", seg=8)
            mb.cyl((0, 0, 0.55), 0.035, 0.08, "M_MetalDark", seg=6)
            mb.box((0, -0.12, 0.2), (0.2, 0.06, 0.1), "M_Black")
    return f


def train_car(mb):
    L, w = 12.0, 2.7
    rings = []
    for (y, hw, z0, z1) in ((-L / 2, 1.0, 0.5, 2.6), (-L / 2 + 0.8, w / 2, 0.3, 3.0), (L / 2 - 0.8, w / 2, 0.3, 3.0), (L / 2, 1.0, 0.5, 2.6)):
        rings.append([(hw, y, z0), (hw, y, z1 - 0.3), (hw - 0.3, y, z1), (-(hw - 0.3), y, z1), (-hw, y, z1 - 0.3), (-hw, y, z0)])
    mb.loft(rings, lambda i, k: "M_White" if k in (0, 4) else ("M_Teal" if k in (1, 2, 3) else "M_MetalDark"), cap0="M_ShopFront", cap1="M_ShopFront")
    for sx in (-1, 1):
        mb.box((sx * (w / 2 + 0.01), 0, 1.9), (0.04, L - 3.0, 0.9), "M_WindowLit")
        mb.box((sx * (w / 2 + 0.015), 0, 0.9), (0.04, L - 1.8, 0.2), "M_Neon_B")
        for dy in (-3.0, 3.0):
            mb.box((sx * (w / 2 + 0.02), dy, 1.4), (0.05, 1.4, 2.0), "M_MetalDark")
    mb.box((0, 0, 0.1), (1.1, L - 1.0, 0.5), "M_MetalDark")


def rail_pillar(mb):
    mb.box((0, 0, 3.0), (0.9, 0.9, 6.0), "M_Concrete")
    mb.box((0, 0, 6.2), (2.4, 1.2, 0.5), "M_Concrete", top=(1.2, 1.0))
    mb.box((0, 0, 0.15), (1.6, 1.6, 0.3), "M_ConcreteDark")


def rail_beam(mb):
    mb.box((0, 0, -0.35), (0.9, 10.0, 0.7), "M_Concrete")
    mb.box((0, 0, 0.02), (0.7, 10.0, 0.06), "M_MetalDark")


def wreck(mb):
    S = [(-5, 0.2, 0.6, 1.0, 0.9, 2.2), (-2, 0.0, 1.5, 0.9, 1.9, 2.4), (2, 0.0, 1.6, 0.9, 2.0, 2.5), (5, 0.3, 1.0, 1.2, 1.2, 2.6), (7, 1.4, 0.1, 1.9, 0.15, 2.8)]
    rings = [[(0, y, kz), (cw, y, cz), (gw, y, gz), (gw - 0.25, y, gz), (-(gw - 0.25), y, gz), (-gw, y, gz), (-cw, y, cz)] for (y, kz, cw, cz, gw, gz) in S]
    mb.push((0, 0, 0), (0, 0.35, 0))
    mb.loft(rings, lambda i, k: "M_Rust" if (i + k) % 3 else "M_MetalDark", cap0="M_Rust", cap1="M_Rust")
    mb.box((0, -2.0, 3.4), (2.6, 3.0, 2.0), "M_Rust")
    mb.box((0, -0.45, 3.6), (2.0, 0.06, 0.8), "M_Black")
    mb.limb((0, 2.0, 2.4), (0.8, 2.6, 6.5), 0.14, 0.08, "M_MetalDark", seg=5)
    mb.pop()
    mb.box((3.2, 1.0, 0.4), (1.2, 1.2, 0.8), "M_Wood", rot=(0.2, 0.3, 0.4))
    mb.box((-3.4, -1.5, 0.3), (0.9, 0.9, 0.6), "M_Gold", rot=(0.1, 0.2, 0.7))


def buoy(mb):
    mb.cyl((0, 0, 0.1), 0.7, 0.6, "M_Red", seg=8, r2=0.5)
    mb.cyl((0, 0, 1.0), 0.3, 1.2, "M_Red", seg=6, r2=0.12)
    mb.box((0, 0, 1.7), (0.18, 0.18, 0.2), "M_LampGlow")


def water_tower(mb):
    for a in range(4):
        x, y = math.cos(a * 1.57 + 0.78) * 2.6, math.sin(a * 1.57 + 0.78) * 2.6
        mb.limb((x * 1.3, y * 1.3, 0), (x, y, 14), 0.2, 0.16, "M_Steel", seg=5)
    mb.cyl((0, 0, 16.5), 4.2, 5.0, "M_White", seg=12)
    mb.cyl((0, 0, 19.6), 4.3, 1.4, "M_Teal", seg=12, r2=0.3)
    mb.cyl((0, 0, 13.8), 4.2, 0.6, "M_Teal", seg=12, r2=4.2)
    mb.cyl((0, 0, 7.0), 0.4, 14.0, "M_Steel", seg=6)


def radio_tower(mb):
    for a in range(3):
        x, y = math.cos(a * 2.094) * 2.0, math.sin(a * 2.094) * 2.0
        mb.limb((x, y, 0), (x * 0.15, y * 0.15, 34), 0.16, 0.08, "M_Red", seg=4)
    for i in range(8):
        z = 3 + i * 4
        r = 2.0 * (1 - z / 36.0)
        mb.cyl((0, 0, z), r * 1.02, 0.14, "M_White" if i % 2 else "M_Red", seg=3)
    mb.limb((0, 0, 34), (0, 0, 40), 0.08, 0.03, "M_Steel", seg=4)
    mb.box((0, 0, 40), (0.3, 0.3, 0.3), "M_Siren_R")
    mb.cyl((0.6, 0, 28), 0.7, 0.3, "M_White", axis='X', seg=8, r2=0.2)


def windsock(mb):
    mb.limb((0, 0, 0), (0, 0, 5.0), 0.05, 0.04, "M_White", seg=5)
    mb.cyl((0.9, 0, 4.9), 0.3, 1.8, "M_Orange", axis='X', seg=6, r2=0.14)
    mb.cyl((0.45, 0, 4.9), 0.27, 0.3, "M_White", axis='X', seg=6, r2=0.24)


def helipad(mb):
    mb.cyl((0, 0, 0.04), 8.0, 0.08, "M_DarkGrey", seg=20)
    mb.cyl((0, 0, 0.085), 6.6, 0.02, "M_Yellow", seg=20)
    mb.cyl((0, 0, 0.09), 6.2, 0.02, "M_DarkGrey", seg=20)
    mb.box((-1.4, 0, 0.105), (0.6, 4.0, 0.02), "M_White")
    mb.box((1.4, 0, 0.105), (0.6, 4.0, 0.02), "M_White")
    mb.box((0, 0, 0.105), (3.2, 0.6, 0.02), "M_White")


def fountain(mb):
    mb.cyl((0, 0, 0.3), 4.0, 0.6, "M_Concrete", seg=12)
    mb.cyl((0, 0, 0.52), 3.6, 0.2, "M_Water", seg=12)
    mb.cyl((0, 0, 1.0), 0.5, 1.6, "M_Concrete", seg=8)
    mb.cyl((0, 0, 1.9), 1.6, 0.3, "M_Concrete", seg=10, r2=1.8)
    mb.cyl((0, 0, 2.06), 1.5, 0.1, "M_Water", seg=10)
    mb.cyl((0, 0, 2.6), 0.2, 1.0, "M_Concrete", seg=6)


def statue(mb):
    mb.box((0, 0, 0.9), (2.2, 2.2, 1.8), "M_Concrete", top=(1.8, 1.8))
    mb.box((0, 0, 1.9), (1.4, 1.4, 0.2), "M_ConcreteDark")
    mb.limb((0, 0, 2.0), (0, 0, 3.4), 0.34, 0.26, "M_Gold", seg=6)
    mb.ball((0, 0, 3.75), 0.3, "M_Gold", sub=1)
    mb.limb((0.3, 0, 3.2), (1.0, 0, 4.3), 0.11, 0.08, "M_Gold", seg=5)
    mb.limb((-0.3, 0, 3.2), (-0.6, 0.3, 2.5), 0.11, 0.08, "M_Gold", seg=5)
    mb.cyl((1.05, 0, 4.5), 0.25, 0.3, "M_Gold", seg=6, r2=0.02)


def gazebo(mb):
    mb.cyl((0, 0, 0.2), 3.2, 0.4, "M_Wood", seg=8)
    for a in range(8):
        x, y = math.cos(a * math.pi / 4) * 2.9, math.sin(a * math.pi / 4) * 2.9
        mb.box((x, y, 1.8), (0.16, 0.16, 2.8), "M_White")
    mb.cyl((0, 0, 3.9), 3.6, 1.6, "M_RoofRed", seg=8, r2=0.2)
    mb.cyl((0, 0, 3.15), 3.3, 0.14, "M_White", seg=8)


def stall(mb):
    mb.box((0, 0, 0.9), (2.4, 1.0, 0.08), "M_Wood")
    for sx in (-1.1, 1.1):
        for sy in (-0.4, 0.4):
            mb.box((sx, sy, 1.2), (0.07, 0.07, 2.4), "M_WoodDark")
    mb.box((0, 0, 2.5), (2.8, 1.6, 0.08), "M_Canopy", rot=(0.1, 0, 0))
    mb.box((0, -0.82, 2.3), (2.8, 0.04, 0.24), "M_Canopy2")
    for i in range(5):
        mb.box((-0.9 + i * 0.45, 0, 1.02), (0.3, 0.5, 0.16), ["M_Orange", "M_Red", "M_Green", "M_Yellow", "M_Purple"][i])


def ac_unit(mb):
    mb.box((0, 0, 0.45), (1.0, 0.5, 0.9), "M_White")
    mb.cyl((0, -0.26, 0.45), 0.3, 0.03, "M_MetalDark", axis='Y', seg=8)


def street_clock(mb):
    mb.limb((0, 0, 0), (0, 0, 3.4), 0.1, 0.07, "M_MetalDark", seg=6)
    mb.cyl((0, 0, 3.9), 0.55, 0.3, "M_MetalDark", axis='Y', seg=12)
    mb.cyl((0, 0, 3.9), 0.46, 0.32, "M_White", axis='Y', seg=12)
    mb.box((0, -0.17, 4.05), (0.04, 0.02, 0.32), "M_Black")
    mb.box((0.1, -0.17, 3.9), (0.24, 0.02, 0.04), "M_Black")


out = []
tl = P("traffic_light", traffic_light, children=[("red", (-3.6, -0.20, 5.72), tl_lamp("M_TLon_R")), ("yellow", (-3.6, -0.20, 5.35), tl_lamp("M_TLon_Y")),
                                                 ("green", (-3.6, -0.20, 4.98), tl_lamp("M_TLon_G"))])
P("street_lamp", street_lamp, children=[("bulb", (0, -2.2, 7.2), None)])
for s in ("stop", "speed", "parking", "street"):
    P("sign_" + s, sign(s))
for n, f in (("barrier_jersey", barrier_jersey), ("barrier_plastic", barrier_plastic), ("bench", bench), ("bin", bin_), ("hydrant", hydrant),
             ("bus_stop", bus_stop), ("fence_wood", fence_wood), ("fence_chain", fence_chain), ("wall_low", wall_low), ("utility_box", utility_box),
             ("bollard", bollard), ("cone", cone), ("dumpster", dumpster), ("crate", crate), ("pallet", pallet), ("barrel_red", barrel("M_Red")),
             ("barrel_blue", barrel("M_Blue")), ("mailbox", mailbox), ("vending", vending), ("atm", atm), ("newsbox", newsbox), ("planter", planter),
             ("parking_meter", parking_meter), ("billboard", billboard), ("picnic_table", picnic_table), ("beach_set", beach_set),
             ("lifeguard", lifeguard), ("pier", pier), ("dock_crane", dock_crane), ("container", container), ("ladder", ladder), ("ramp", ramp),
             ("target", target), ("rail_pillar", rail_pillar), ("rail_beam", rail_beam), ("wreck", wreck), ("buoy", buoy),
             ("water_tower", water_tower), ("radio_tower", radio_tower), ("windsock", windsock), ("helipad", helipad), ("fountain", fountain),
             ("statue", statue), ("gazebo", gazebo), ("stall", stall), ("ac_unit", ac_unit), ("street_clock", street_clock)):
    P(n, f)
P("train_car", train_car, children=[("seat_0", (0.6, 0, 0.75), None), ("door", (1.6, 0, 0.5), None)])
P("canopy", canopy, c=CV)
for k in ("cash", "health", "armor", "ammo", "weapon", "parachute", "scuba"):
    P("pk_" + k, pk(k), c=CI)


# ------------------------------------------------------------------ nature
def tree_round(seed, h=6.0, leaf="M_Leaf", leaf2="M_LeafLight"):
    def f(mb):
        r = random.Random(seed)
        mb.limb((0, 0, 0), (0.1, 0.05, h * 0.55), 0.26, 0.16, "M_Trunk", seg=6)
        mb.limb((0.1, 0.05, h * 0.5), (0.8, 0.3, h * 0.72), 0.12, 0.07, "M_Trunk", seg=5)
        mb.limb((0.1, 0.05, h * 0.5), (-0.7, -0.4, h * 0.75), 0.12, 0.07, "M_Trunk", seg=5)
        mb.ball((0, 0, h * 0.82), h * 0.30, leaf, scale=(1.1, 1.1, 0.85), sub=1)
        for i in range(4):
            a = i * 1.57 + r.uniform(-0.4, 0.4)
            mb.ball((math.cos(a) * h * 0.2, math.sin(a) * h * 0.2, h * (0.68 + r.uniform(0, 0.12))), h * r.uniform(0.17, 0.22), leaf2 if i % 2 else leaf, sub=1)
    return f


def pine(mb):
    mb.limb((0, 0, 0), (0, 0, 3.0), 0.22, 0.14, "M_Trunk", seg=6)
    for i in range(4):
        mb.cyl((0, 0, 2.6 + i * 1.7), 2.1 - i * 0.45, 2.4, "M_LeafDark" if i % 2 == 0 else "M_Leaf", seg=7, r2=0.15, phase=i * 0.4)


def palm(mb):
    pts = [(0, 0, 0), (0.25, 0, 2.2), (0.6, 0, 4.4), (1.1, 0, 6.4), (1.6, 0, 8.0)]
    for i in range(len(pts) - 1):
        mb.limb(pts[i], pts[i + 1], 0.24 - i * 0.03, 0.21 - i * 0.03, "M_Trunk", seg=6)
    top = Vector(pts[-1])
    for i in range(8):
        a = i * math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        p1 = top + d * 1.6 + Vector((0, 0, 0.5))
        p2 = top + d * 3.2 + Vector((0, 0, -0.6))
        mb.limb(top, p1, 0.5, 0.42, "M_Palm", seg=3, squash=0.12, up=(0, 0, 1))
        mb.limb(p1, p2, 0.42, 0.06, "M_Palm" if i % 2 else "M_LeafLight", seg=3, squash=0.12, up=(0, 0, 1))
    for i in range(3):
        mb.ball(top + Vector((math.cos(i * 2.1) * 0.25, math.sin(i * 2.1) * 0.25, -0.25)), 0.16, "M_Brown", sub=1)


def bush(mb):
    mb.ball((0, 0, 0.5), 0.75, "M_Leaf", scale=(1.2, 1.0, 0.75), sub=1)
    mb.ball((0.5, 0.2, 0.4), 0.5, "M_LeafLight", sub=1)
    mb.ball((-0.45, -0.25, 0.38), 0.48, "M_LeafDark", sub=1)


def hedge(mb):
    mb.box((0, 0, 0.6), (3.0, 0.8, 1.2), "M_LeafDark", top=(2.9, 0.6))


def rock(seed, s=1.0):
    def f(mb):
        r = random.Random(seed)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=s)
        vs = []
        for v in bm.verts:
            k = r.uniform(0.75, 1.15)
            vs.append((v.co.x * k * 1.2, v.co.y * k, max(v.co.z * k * 0.7 + s * 0.35, -0.1)))
        fs = [tuple(v.index for v in fc.verts) for fc in bm.faces]
        bm.free()
        mb.add(vs, fs, "M_Rock" if seed % 2 else "M_RockDark")
    return f


def grass_tuft(mb):
    for i in range(3):
        a = i * math.pi / 3
        c, s = math.cos(a), math.sin(a)
        mb.add([(-0.3 * c, -0.3 * s, 0), (0.3 * c, 0.3 * s, 0), (0.38 * c, 0.38 * s, 0.5), (0, 0, 0.62), (-0.38 * c, -0.38 * s, 0.45)], [(0, 1, 2, 3, 4)], "M_Grass")


def flower(mb):
    for i in range(3):
        a = i * math.pi / 3
        c, s = math.cos(a), math.sin(a)
        mb.add([(-0.2 * c, -0.2 * s, 0), (0.2 * c, 0.2 * s, 0), (0.22 * c, 0.22 * s, 0.3), (-0.22 * c, -0.22 * s, 0.3)], [(0, 1, 2, 3)], "M_Grass")
    for i in range(4):
        mb.box((math.cos(i * 1.6) * 0.14, math.sin(i * 1.6) * 0.14, 0.36 + (i % 2) * 0.06), (0.1, 0.1, 0.06), "M_Flower" if i % 2 else "M_Pink")


def seaweed(mb):
    for i in range(4):
        a = i * 1.4
        x, y = math.cos(a) * 0.25, math.sin(a) * 0.25
        mb.limb((x, y, 0), (x + 0.2, y, 1.0), 0.12, 0.1, "M_Seaweed", seg=3, squash=0.15)
        mb.limb((x + 0.2, y, 1.0), (x - 0.1, y + 0.1, 2.0 + i * 0.2), 0.1, 0.03, "M_Seaweed", seg=3, squash=0.15)


def coral(mb):
    mb.ball((0, 0, 0.25), 0.5, "M_Coral", scale=(1.2, 1, 0.6), sub=1)
    for i in range(5):
        a = i * 1.26
        mb.limb((math.cos(a) * 0.2, math.sin(a) * 0.2, 0.3), (math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0 + (i % 2) * 0.3), 0.1, 0.05, "M_Coral" if i % 2 else "M_Orange", seg=4)


P("tree_a", tree_round(1, 6.5), c=CN, kind="n")
P("tree_b", tree_round(2, 8.5, "M_LeafDark", "M_Leaf"), c=CN, kind="n")
P("tree_c", tree_round(3, 5.0, "M_LeafLight", "M_Leaf"), c=CN, kind="n")
P("pine", pine, c=CN, kind="n")
P("palm", palm, c=CN, kind="n")
P("bush", bush, c=CN, kind="n")
P("hedge", hedge, c=CN, kind="n")
P("rock_a", rock(1, 1.0), c=CN, kind="n")
P("rock_b", rock(2, 1.8), c=CN, kind="n")
P("rock_c", rock(3, 0.5), c=CN, kind="n")
P("grass_tuft", grass_tuft, c=CN, kind="n")
P("flower", flower, c=CN, kind="n")
P("seaweed", seaweed, c=CN, kind="n")
P("coral", coral, c=CN, kind="n")


# ------------------------------------------------------------------ animals
def quadruped(name, L, H, bw, fur, fur2, leg_r, head_fn, tail_fn=None):
    hip_z = H
    def body(mb):
        mb.box((0, 0, hip_z + bw * 0.25), (bw, L, bw * 0.95), fur, top=(bw * 0.8, L * 0.96))
        mb.box((0, 0, hip_z - bw * 0.15), (bw * 0.8, L * 0.9, bw * 0.3), fur2)
        if tail_fn:
            tail_fn(mb)

    def leg(mb):
        mb.limb((0, 0, 0), (0, 0.02, -H * 0.5), leg_r, leg_r * 0.75, fur, seg=5)
        mb.limb((0, 0.02, -H * 0.5), (0, 0, -H), leg_r * 0.72, leg_r * 0.5, fur2, seg=5)
    ch = [("leg_fl", (-bw * 0.32, L * 0.38, hip_z), leg), ("leg_fr", (bw * 0.32, L * 0.38, hip_z), leg),
          ("leg_rl", (-bw * 0.32, -L * 0.38, hip_z), leg), ("leg_rr", (bw * 0.32, -L * 0.38, hip_z), leg),
          ("head", (0, L * 0.48, hip_z + bw * 0.45), head_fn)]
    return P(name, body, c=CA, kind="a", children=ch)


def deer_head(mb):
    mb.limb((0, 0, 0), (0, 0.3, 0.55), 0.12, 0.09, "M_Fur", seg=5)
    mb.box((0, 0.42, 0.62), (0.16, 0.36, 0.17), "M_Fur", top=(0.12, 0.3))
    mb.box((0, 0.61, 0.58), (0.09, 0.06, 0.07), "M_Eye")
    for sx in (-1, 1):
        mb.box((sx * 0.11, 0.3, 0.74), (0.04, 0.1, 0.14), "M_Fur")
        mb.limb((sx * 0.05, 0.34, 0.7), (sx * 0.2, 0.3, 1.05), 0.022, 0.016, "M_Cream", seg=4)
        mb.limb((sx * 0.14, 0.32, 0.9), (sx * 0.3, 0.42, 1.0), 0.016, 0.01, "M_Cream", seg=4)


def dog_head(mb):
    mb.limb((0, 0, 0), (0, 0.14, 0.14), 0.1, 0.09, "M_FurDark", seg=5)
    mb.box((0, 0.24, 0.18), (0.18, 0.22, 0.17), "M_FurDark")
    mb.box((0, 0.4, 0.14), (0.1, 0.14, 0.09), "M_FurLight")
    mb.box((0, 0.48, 0.16), (0.05, 0.03, 0.04), "M_Eye")
    for sx in (-1, 1):
        mb.box((sx * 0.08, 0.2, 0.3), (0.05, 0.07, 0.1), "M_FurDark")


def boar_head(mb):
    mb.box((0, 0.2, -0.02), (0.3, 0.4, 0.3), "M_FurDark", top=(0.22, 0.36))
    mb.box((0, 0.46, -0.08), (0.14, 0.16, 0.13), "M_Brown")
    for sx in (-1, 1):
        mb.limb((sx * 0.07, 0.48, -0.1), (sx * 0.13, 0.52, 0.05), 0.02, 0.008, "M_Cream", seg=4)
        mb.box((sx * 0.12, 0.08, 0.16), (0.05, 0.08, 0.1), "M_FurDark")


def cow_head(mb):
    mb.box((0, 0.26, 0.02), (0.3, 0.46, 0.3), "M_FurLight", top=(0.24, 0.4))
    mb.box((0, 0.52, -0.06), (0.22, 0.12, 0.16), "M_Pink")
    for sx in (-1, 1):
        mb.limb((sx * 0.13, 0.1, 0.16), (sx * 0.28, 0.14, 0.3), 0.03, 0.012, "M_Cream", seg=4)
        mb.box((sx * 0.2, 0.08, 0.08), (0.12, 0.05, 0.08), "M_FurLight")


quadruped("ani_deer", 1.25, 0.95, 0.36, "M_Fur", "M_FurLight", 0.055, deer_head, lambda mb: mb.box((0, -0.66, 1.08), (0.08, 0.1, 0.14), "M_FurLight"))
quadruped("ani_dog", 0.7, 0.42, 0.24, "M_FurDark", "M_FurLight", 0.04, dog_head, lambda mb: mb.limb((0, -0.34, 0.5), (0, -0.55, 0.66), 0.03, 0.015, "M_FurDark", seg=4))
quadruped("ani_boar", 1.05, 0.45, 0.42, "M_FurDark", "M_Brown", 0.055, boar_head, lambda mb: mb.box((0, 0, 0.8), (0.06, 0.8, 0.1), "M_Black"))
quadruped("ani_cow", 1.9, 0.8, 0.66, "M_FurLight", "M_FurLight", 0.075, cow_head,
          lambda mb: (mb.box((0.2, 0.2, 1.2), (0.3, 0.6, 0.2), "M_Black"), mb.box((-0.34, -0.4, 1.0), (0.02, 0.5, 0.4), "M_Black"),
                      mb.limb((0, -0.95, 1.2), (0, -1.0, 0.5), 0.03, 0.02, "M_FurLight", seg=4)))


def seagull(mb):
    mb.ball((0, 0, 0), 0.12, "M_White", scale=(0.8, 1.9, 0.8), sub=1)
    mb.ball((0, 0.22, 0.05), 0.07, "M_White", sub=1)
    mb.cyl((0, 0.32, 0.04), 0.02, 0.08, "M_Yellow", axis='Y', seg=4, r2=0.004)
    mb.box((0, -0.26, 0.0), (0.12, 0.14, 0.015), "M_Grey")


def gull_wing(sx):
    def f(mb):
        mb.add([(0, -0.09, 0), (0, 0.09, 0), (sx * 0.34, 0.06, 0.02), (sx * 0.62, -0.06, 0.0), (sx * 0.3, -0.1, 0.0)], [(0, 1, 2, 3, 4)], "M_Fabric")
    return f


P("ani_seagull", seagull, c=CA, kind="a", children=[("wing_l", (-0.07, 0, 0.03), gull_wing(-1)), ("wing_r", (0.07, 0, 0.03), gull_wing(1))])


def fish_body(m, L):
    def f(mb):
        mb.ball((0, 0, 0), L * 0.3, m, scale=(0.35, 1.6, 0.75), sub=1)
        mb.box((0, L * 0.1, L * 0.2), (0.02, L * 0.3, L * 0.14), m, top=(0.02, L * 0.12), top_off=(0, -L * 0.08))
        for sx in (-1, 1):
            mb.box((sx * L * 0.12, L * 0.12, -L * 0.08), (L * 0.16, L * 0.12, 0.015), m, rot=(0, sx * 0.5, 0))
            mb.box((sx * L * 0.085, L * 0.36, L * 0.04), (0.015, 0.03, 0.03), "M_Eye")
    return f


def fish_tail(m, L):
    def f(mb):
        mb.prism([(0, 0), (-L * 0.26, L * 0.2), (-L * 0.2, 0), (-L * 0.26, -L * 0.2)], 0.02, m, plane='YZ')
    return f


P("ani_fish", fish_body("M_Fish", 0.5), c=CA, kind="a", children=[("tail", (0, -0.22, 0), fish_tail("M_Fish", 0.5))])
P("ani_shark", fish_body("M_Shark", 3.2), c=CA, kind="a", children=[("tail", (0, -1.45, 0), fish_tail("M_Shark", 3.2))])
print("props", _n)
