"""Original generic weapon models with modular attachments. Barrel = +Y, grip at origin."""
import sys
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

C = coll("Weapons")
mat("M_Finish", "#2a2c31", 0.45, 0.7)   # tintable receiver finish
mat("M_Scope", "#17181b", 0.4, 0.6)
mat("M_FlashLens", "#fff6d8", 0.2, 0.0, emit="#fff6d8", emit_strength=1.0)
mat("M_Warhead", "#b33a2a", 0.5, 0.3)
_slot = [0]


def weapon(wid, fn, muzzle, atts=None):
    name = "w_" + wid
    wipe([name + "_", name])
    mb = MB()
    fn(mb)
    i = _slot[0]
    _slot[0] += 1
    ob = mb.build(name, C, loc=(-20 + (i % 9) * 1.6, 40 + (i // 9) * 2.0, 1.0))
    empty(name + "_muzzle", C, loc=muzzle, parent=ob, size=0.05)
    for an, afn in (atts or {}).items():
        m = MB()
        afn(m)
        m.build(name + "_att_" + an, C, loc=(0, 0, 0), parent=ob)
    return ob


def grip(mb, y=0.0, z=-0.045, h=0.12, m="M_Grip", w=0.032):
    mb.box((0, y - 0.012, z), (w, 0.05, h), m, rot=(0.22, 0, 0))


def suppressor(y, z, r=0.022, L=0.16):
    return lambda m: m.cyl((0, y + L / 2, z), r, L, "M_Scope", axis='Y', seg=8)


def scope(y, z, L=0.22, r=0.022):
    def f(m):
        m.cyl((0, y, z + 0.035), r, L, "M_Scope", axis='Y', seg=8, cap_m="M_Glass")
        m.cyl((0, y + L / 2 - 0.02, z + 0.035), r * 1.35, 0.05, "M_Scope", axis='Y', seg=8, cap_m="M_Glass")
        for dy in (-L / 4, L / 4):
            m.box((0, y + dy, z + 0.008), (0.018, 0.025, 0.03), "M_Scope")
    return f


def reddot(y, z):
    def f(m):
        m.box((0, y, z + 0.012), (0.03, 0.07, 0.02), "M_Scope")
        m.box((0, y + 0.02, z + 0.04), (0.034, 0.012, 0.04), "M_Scope")
        m.box((0, y + 0.02, z + 0.04), (0.024, 0.014, 0.03), "M_Glass")
    return f


def flashlight(y, z, x=0.0):
    def f(m):
        m.cyl((x, y, z), 0.016, 0.09, "M_Scope", axis='Y', seg=8)
        m.cyl((x, y + 0.05, z), 0.02, 0.02, "M_Scope", axis='Y', seg=8, cap_m="M_FlashLens")
    return f


def foregrip(y, z):
    return lambda m: m.box((0, y, z - 0.05), (0.026, 0.03, 0.10), "M_Polymer", rot=(-0.1, 0, 0))


def extmag(y, z, h=0.10, d=0.03, w=0.024, rot=0.0):
    return lambda m: m.box((0, y, z - h / 2), (w, d, h), "M_Scope", rot=(rot, 0, 0))


# ------------------------------------------------------------ melee
def knife(mb):
    mb.box((0, 0.0, 0), (0.026, 0.11, 0.03), "M_Grip")
    mb.box((0, 0.06, 0), (0.012, 0.014, 0.06), "M_GunLight")
    mb.prism([(0.067, -0.016), (0.067, 0.016), (0.20, 0.012), (0.255, -0.004), (0.19, -0.016)], 0.006, "M_Blade", plane='YZ')


def bat(mb):
    mb.limb((0, -0.10, 0), (0, 0.10, 0), 0.017, 0.016, "M_Grip", seg=7)
    mb.limb((0, 0.10, 0), (0, 0.72, 0), 0.016, 0.034, "M_Wood", seg=8)
    mb.cyl((0, -0.105, 0), 0.024, 0.016, "M_Wood", axis='Y', seg=7)


def crowbar(mb):
    mb.limb((0, -0.10, 0), (0, 0.50, 0), 0.012, 0.012, "M_Navy", seg=6)
    mb.limb((0, 0.50, 0), (0, 0.58, 0.05), 0.012, 0.010, "M_Navy", seg=6)
    mb.box((0, 0.61, 0.065), (0.03, 0.07, 0.008), "M_Navy", rot=(0.5, 0, 0))
    mb.box((0, -0.12, -0.006), (0.026, 0.05, 0.007), "M_Navy", rot=(-0.2, 0, 0))


# ------------------------------------------------------------ handguns
def pistol(mb):
    grip(mb)
    mb.box((0, 0.07, 0.048), (0.028, 0.19, 0.026), "M_Polymer")
    mb.box((0, 0.075, 0.074), (0.03, 0.20, 0.03), "M_Finish")
    mb.box((0, 0.165, 0.10), (0.006, 0.01, 0.01), "M_Gun")
    mb.box((0, -0.01, 0.10), (0.02, 0.01, 0.01), "M_Gun")
    mb.box((0, 0.045, 0.018), (0.008, 0.07, 0.006), "M_Polymer")
    mb.box((0, 0.08, 0.03), (0.008, 0.006, 0.03), "M_Polymer")


def heavy_pistol(mb):
    grip(mb, h=0.13, m="M_Wood", w=0.036)
    mb.box((0, 0.03, 0.055), (0.032, 0.12, 0.05), "M_Finish")
    mb.cyl((0, 0.05, 0.062), 0.03, 0.06, "M_GunLight", axis='Y', seg=6)
    mb.cyl((0, 0.19, 0.078), 0.014, 0.20, "M_Finish", axis='Y', seg=6)
    mb.box((0, 0.17, 0.058), (0.012, 0.14, 0.016), "M_Finish")
    mb.box((0, 0.28, 0.098), (0.006, 0.012, 0.014), "M_Gun")
    mb.box((0, -0.03, 0.095), (0.012, 0.03, 0.02), "M_Gun")
    mb.box((0, 0.04, 0.014), (0.008, 0.07, 0.006), "M_Finish")


# ------------------------------------------------------------ SMG
def smg(mb):
    grip(mb, m="M_Polymer")
    mb.box((0, 0.08, 0.065), (0.04, 0.30, 0.06), "M_Finish")
    mb.cyl((0, 0.27, 0.065), 0.013, 0.10, "M_Gun", axis='Y', seg=6)
    mb.box((0, 0.11, -0.03), (0.024, 0.032, 0.15), "M_Gun")
    mb.box((0, -0.12, 0.07), (0.016, 0.16, 0.014), "M_Gun")
    mb.box((0, -0.20, 0.045), (0.03, 0.014, 0.08), "M_Gun")
    mb.box((0, 0.19, 0.105), (0.008, 0.012, 0.02), "M_Gun")
    mb.box((0, -0.02, 0.105), (0.02, 0.012, 0.02), "M_Gun")


# ------------------------------------------------------------ shotguns
def shotgun(mb):
    mb.box((0, -0.02, -0.03), (0.03, 0.05, 0.08), "M_Wood", rot=(0.35, 0, 0))
    mb.box((0, -0.20, 0.0), (0.034, 0.30, 0.075), "M_Wood", top=(0.03, 0.30), rot=(0.12, 0, 0))
    mb.box((0, 0.06, 0.05), (0.036, 0.22, 0.055), "M_Finish")
    mb.cyl((0, 0.45, 0.065), 0.014, 0.58, "M_Gun", axis='Y', seg=6)
    mb.cyl((0, 0.38, 0.035), 0.013, 0.44, "M_Gun", axis='Y', seg=6)
    mb.cyl((0, 0.32, 0.035), 0.024, 0.16, "M_Wood", axis='Y', seg=6)
    mb.box((0, 0.72, 0.085), (0.006, 0.01, 0.012), "M_Gun")


def auto_shotgun(mb):
    grip(mb, m="M_Polymer")
    mb.box((0, -0.24, 0.045), (0.034, 0.30, 0.07), "M_Polymer", top=(0.03, 0.28))
    mb.box((0, 0.10, 0.06), (0.042, 0.34, 0.07), "M_Finish")
    mb.cyl((0, 0.44, 0.07), 0.016, 0.40, "M_Gun", axis='Y', seg=6)
    mb.box((0, 0.33, 0.045), (0.044, 0.20, 0.05), "M_Polymer")
    mb.cyl((0, 0.10, -0.03), 0.055, 0.06, "M_Gun", axis='X', seg=10)
    mb.box((0, 0.14, 0.105), (0.02, 0.2, 0.012), "M_Gun")


# ------------------------------------------------------------ rifles
def rifle_base(mb, barrel=0.30, stock="M_Polymer", hand="M_Polymer", mag_rot=0.0, body="M_Finish"):
    grip(mb, m="M_Polymer")
    mb.box((0, 0.07, 0.062), (0.04, 0.30, 0.07), body)
    mb.box((0, -0.20, 0.055), (0.032, 0.26, 0.055), stock, top=(0.03, 0.22))
    mb.box((0, -0.32, 0.03), (0.034, 0.03, 0.12), stock)
    mb.box((0, 0.36, 0.062), (0.042, 0.28, 0.052), hand)
    mb.cyl((0, 0.50 + barrel / 2, 0.066), 0.011, barrel, "M_Gun", axis='Y', seg=6)
    mb.cyl((0, 0.50 + barrel - 0.03, 0.066), 0.016, 0.06, "M_Gun", axis='Y', seg=6)
    mb.box((0, 0.13, -0.02), (0.022, 0.05, 0.13), "M_Gun", rot=(mag_rot, 0, 0))
    mb.box((0, 0.44, 0.105), (0.008, 0.014, 0.03), "M_Gun")
    mb.box((0, 0.10, 0.104), (0.03, 0.26, 0.012), "M_Gun")


def assault_rifle(mb):
    rifle_base(mb, barrel=0.24, stock="M_Wood", hand="M_Wood", mag_rot=-0.3)


def carbine(mb):
    rifle_base(mb, barrel=0.18, mag_rot=-0.08)
    mb.box((0, 0.36, 0.062), (0.046, 0.20, 0.056), "M_Polymer")


def marksman(mb):
    rifle_base(mb, barrel=0.44, stock="M_Olive", hand="M_Olive", mag_rot=0.0)
    mb.cyl((0, 0.08, 0.14), 0.02, 0.24, "M_Scope", axis='Y', seg=8, cap_m="M_Glass")
    for dy in (-0.06, 0.06):
        mb.box((0, 0.08 + dy, 0.115), (0.016, 0.02, 0.02), "M_Scope")


def sniper(mb):
    grip(mb, m="M_Polymer")
    mb.box((0, 0.10, 0.06), (0.042, 0.42, 0.066), "M_Finish")
    mb.box((0, -0.26, 0.045), (0.036, 0.30, 0.09), "M_Olive", top=(0.03, 0.26))
    mb.box((0, -0.40, 0.06), (0.04, 0.02, 0.13), "M_Black")
    mb.cyl((0, 0.66, 0.066), 0.014, 0.72, "M_Gun", axis='Y', seg=6)
    mb.box((0, 1.04, 0.066), (0.05, 0.08, 0.036), "M_Gun")
    mb.box((0, 0.12, -0.005), (0.026, 0.07, 0.07), "M_Gun")
    mb.cyl((0, 0.10, 0.15), 0.026, 0.34, "M_Scope", axis='Y', seg=8, cap_m="M_Glass")
    mb.cyl((0, 0.26, 0.15), 0.034, 0.06, "M_Scope", axis='Y', seg=8, cap_m="M_Glass")
    for dy in (-0.08, 0.08):
        mb.box((0, 0.10 + dy, 0.115), (0.018, 0.024, 0.03), "M_Scope")
    for sx in (-1, 1):
        mb.limb((sx * 0.01, 0.56, 0.05), (sx * 0.10, 0.60, -0.16), 0.008, 0.006, "M_Gun", seg=4)


# ------------------------------------------------------------ heavy
def rocket_launcher(mb):
    grip(mb, m="M_Polymer")
    mb.cyl((0, 0.05, 0.085), 0.052, 0.95, "M_Olive", axis='Y', seg=10, cap_m="M_Black")
    mb.cyl((0, 0.52, 0.085), 0.066, 0.10, "M_Olive", axis='Y', seg=10, cap_m="M_Black")
    mb.cyl((0, -0.44, 0.085), 0.07, 0.10, "M_Olive", axis='Y', seg=10, r2=0.052, cap_m="M_Black")
    mb.box((0, 0.22, 0.0), (0.03, 0.035, 0.10), "M_Polymer")
    mb.box((0.06, 0.10, 0.15), (0.03, 0.10, 0.05), "M_Scope")
    mb.cyl((0, 0.62, 0.085), 0.045, 0.14, "M_Warhead", axis='Y', seg=8, r2=0.01)


def grenade_launcher(mb):
    grip(mb, m="M_Polymer")
    mb.box((0, 0.04, 0.06), (0.04, 0.20, 0.07), "M_Finish")
    mb.cyl((0, 0.17, 0.035), 0.055, 0.12, "M_GunLight", axis='Y', seg=6)
    mb.cyl((0, 0.36, 0.075), 0.03, 0.28, "M_Gun", axis='Y', seg=8, cap_m="M_Black")
    mb.box((0, -0.20, 0.05), (0.03, 0.26, 0.05), "M_Polymer")
    mb.box((0, -0.33, 0.03), (0.034, 0.03, 0.11), "M_Polymer")
    mb.box((0, 0.30, 0.0), (0.028, 0.035, 0.09), "M_Polymer")


def grenade(mb):
    mb.ball((0, 0, 0.0), 0.045, "M_Olive", scale=(1, 1, 1.2), sub=1)
    mb.cyl((0, 0, 0.06), 0.018, 0.03, "M_GunLight", seg=6)
    mb.box((0.02, 0, 0.05), (0.01, 0.02, 0.07), "M_GunLight", rot=(0, 0.3, 0))
    mb.cyl((-0.03, 0, 0.07), 0.016, 0.004, "M_GunLight", axis='Y', seg=6)


def molotov(mb):
    mb.cyl((0, 0, 0.0), 0.035, 0.13, "M_Green", seg=8)
    mb.cyl((0, 0, 0.10), 0.035, 0.06, "M_Green", seg=8, r2=0.014)
    mb.cyl((0, 0, 0.15), 0.014, 0.05, "M_Green", seg=6)
    mb.box((0, 0, 0.20), (0.02, 0.006, 0.07), "M_Cream", rot=(0, 0.3, 0))


def rocket(mb):
    mb.cyl((0, 0.0, 0), 0.04, 0.34, "M_Olive", axis='Y', seg=8)
    mb.cyl((0, 0.23, 0), 0.04, 0.12, "M_Warhead", axis='Y', seg=8, r2=0.005)
    for a in range(4):
        mb.push((0, -0.14, 0), (0, a * math.pi / 2, 0))
        mb.box((0, 0, 0.06), (0.006, 0.08, 0.06), "M_GunLight")
        mb.pop()


weapon("knife", knife, (0, 0.25, 0))
weapon("bat", bat, (0, 0.7, 0))
weapon("crowbar", crowbar, (0, 0.6, 0))
weapon("pistol", pistol, (0, 0.18, 0.074), {"suppressor": suppressor(0.175, 0.074, 0.017, 0.13), "flashlight": flashlight(0.12, 0.022),
                                           "extmag": extmag(-0.03, -0.10, 0.06, 0.04, 0.026, 0.22)})
weapon("heavy_pistol", heavy_pistol, (0, 0.29, 0.078), {"scope": reddot(0.05, 0.085), "flashlight": flashlight(0.20, 0.035)})
weapon("smg", smg, (0, 0.32, 0.065), {"suppressor": suppressor(0.32, 0.065, 0.02, 0.15), "scope": reddot(0.06, 0.10),
                                     "flashlight": flashlight(0.20, 0.02), "extmag": extmag(0.11, -0.105, 0.10, 0.032, 0.024),
                                     "grip": foregrip(0.20, 0.035)})
weapon("shotgun", shotgun, (0, 0.74, 0.065), {"flashlight": flashlight(0.56, 0.035, 0.03), "scope": reddot(0.06, 0.08),
                                             "extmag": lambda m: m.cyl((0, 0.63, 0.035), 0.013, 0.14, "M_Scope", axis='Y', seg=6)})
weapon("auto_shotgun", auto_shotgun, (0, 0.64, 0.07), {"suppressor": suppressor(0.64, 0.07, 0.026, 0.16), "scope": reddot(0.08, 0.11),
                                                       "flashlight": flashlight(0.40, 0.012), "grip": foregrip(0.34, 0.02),
                                                       "extmag": lambda m: m.cyl((0, 0.10, -0.03), 0.072, 0.062, "M_Scope", axis='X', seg=10)})
RA = lambda bl: {"suppressor": suppressor(0.50 + bl, 0.066, 0.022, 0.18), "scope": scope(0.10, 0.11), "flashlight": flashlight(0.40, 0.022, 0.035),
                 "grip": foregrip(0.34, 0.036), "extmag": extmag(0.13, -0.085, 0.09, 0.05, 0.023)}
weapon("assault_rifle", assault_rifle, (0, 0.74, 0.066), RA(0.24))
weapon("carbine", carbine, (0, 0.68, 0.066), RA(0.18))
weapon("marksman", marksman, (0, 0.94, 0.066), {"suppressor": suppressor(0.94, 0.066, 0.022, 0.2), "grip": foregrip(0.34, 0.036),
                                               "flashlight": flashlight(0.40, 0.022, 0.035), "extmag": extmag(0.13, -0.085, 0.07, 0.05, 0.023)})
weapon("sniper", sniper, (0, 1.08, 0.066), {"suppressor": suppressor(1.08, 0.066, 0.026, 0.22), "extmag": extmag(0.12, -0.04, 0.06, 0.07, 0.027)})
weapon("rocket_launcher", rocket_launcher, (0, 0.70, 0.085))
weapon("grenade_launcher", grenade_launcher, (0, 0.50, 0.075), {"scope": reddot(0.04, 0.10), "grip": foregrip(0.30, -0.03)})
weapon("grenade", grenade, (0, 0, 0))
weapon("molotov", molotov, (0, 0, 0.2))
weapon("rocket", rocket, (0, 0.3, 0))
print("weapons", [o.name for o in C.objects if o.parent is None])
