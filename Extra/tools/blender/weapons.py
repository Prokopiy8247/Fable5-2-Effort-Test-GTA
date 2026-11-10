# Original generic weapon models for Cinder Bay. Executed in Blender through MCP.
# Origin = main grip. Barrel points +Y (Godot -Z), up = +Z.
import bpy, math
from mathutils import Vector
from fable_lib import *

T = math.radians


class W:
    def __init__(self, wid, cell):
        self.wid = wid
        self.coll = col("Weapons")
        kill(wid)
        self.root = empty(wid, self.coll, loc=cell, size=0.1)
        self.mb = MB()

    def B(self, size, loc, m="GunMetal", **kw):
        if 'bevel' not in kw:
            kw['bevel'] = min(size) * 0.18 if min(size) > 0.012 else 0
        self.mb.box(size, loc=loc, m=m, **kw)

    def C(self, r, depth, loc, m="GunMetal", axis='Y', segs=8, **kw):
        self.mb.cyl(r, depth, loc=loc, axis=axis, segs=segs, m=m, **kw)

    def part(self, name, smooth=40, hide=False):
        """Finish the current builder as a child part and start a new one."""
        o = None
        if len(self.mb.bm.verts) > 0:
            o = self.mb.finish("%s_%s" % (self.wid, name), self.coll, smooth=smooth, parent=self.root)
            if hide:
                o.hide_set(True)
        self.mb = MB()
        return o

    def mark(self, name, loc):
        empty("%s_%s" % (self.wid, name), self.coll, loc=loc, parent=self.root, size=0.03)

    def grip(self, y=-0.02, m="GunGrip", h=0.10, w=0.028):
        self.B((w, 0.042, h), (0, y - 0.012, -h / 2 + 0.005), m, rot=(T(14), 0, 0))

    def guard(self, y0=0.005, y1=0.065, z=-0.035):
        self.B((0.008, y1 - y0, 0.006), (0, (y0 + y1) / 2, z), "GunBlack", bevel=0)
        self.B((0.008, 0.006, abs(z)), (0, y1, z / 2), "GunBlack", bevel=0)
        self.B((0.006, 0.006, 0.022), (0, (y0 + y1) / 2 - 0.005, -0.012), "GunBlack", bevel=0, rot=(T(-15), 0, 0))

    def suppressor(self, y, z, r=0.018, L=0.16):
        self.C(r, L, (0, y + L / 2, z), "GunBlack", segs=10)
        self.C(r * 0.8, 0.012, (0, y + L + 0.005, z), "GunMetal", segs=10)
        self.part("Att_Suppressor", hide=True)
        self.mark("Muzzle_S", (0, y + L + 0.02, z))

    def flashlight(self, y, z, side=0.0):
        self.C(0.013, 0.07, (side, y, z), "GunBlack", segs=8)
        self.C(0.016, 0.02, (side, y + 0.04, z), "GunBlack", segs=8)
        self.C(0.012, 0.004, (side, y + 0.051, z), "LightHead", segs=8)
        self.part("Att_Flashlight", hide=True)
        self.mark("Light", (side, y + 0.06, z))

    def scope(self, y, z, L=0.16, r=0.017, name="Att_Scope", hide=True):
        self.C(r, L, (0, y, z + r + 0.012), "GunBlack", segs=8)
        self.C(r * 1.3, L * 0.25, (0, y + L * 0.42, z + r + 0.012), "GunBlack", segs=8)
        self.C(r * 1.15, L * 0.2, (0, y - L * 0.42, z + r + 0.012), "GunBlack", segs=8)
        self.C(r * 1.1, 0.004, (0, y + L * 0.55, z + r + 0.012), "Lens", segs=8)
        self.B((0.012, 0.03, 0.014), (0, y + L * 0.2, z + 0.005), "GunBlack", bevel=0)
        self.B((0.012, 0.03, 0.014), (0, y - L * 0.2, z + 0.005), "GunBlack", bevel=0)
        self.part(name, hide=hide)

    def reddot(self, y, z):
        self.B((0.026, 0.05, 0.008), (0, y, z + 0.004), "GunBlack", bevel=0)
        self.B((0.004, 0.012, 0.034), (-0.012, y + 0.015, z + 0.022), "GunBlack", bevel=0)
        self.B((0.004, 0.012, 0.034), (0.012, y + 0.015, z + 0.022), "GunBlack", bevel=0)
        self.B((0.026, 0.012, 0.004), (0, y + 0.015, z + 0.04), "GunBlack", bevel=0)
        self.B((0.020, 0.003, 0.028), (0, y + 0.015, z + 0.023), "Lens", bevel=0)
        self.part("Att_Scope", hide=True)

    def foregrip(self, y, z):
        self.B((0.024, 0.03, 0.085), (0, y, z - 0.045), "GunPolymer")
        self.part("Att_Grip", hide=True)

    def extmag(self, size, loc, rot=None, m="GunBlack"):
        self.B(size, loc, m, rot=rot)
        self.part("Att_ExtMag", hide=True)


def pistol(cell):
    w = W("w_pistol", cell)
    w.B((0.028, 0.185, 0.034), (0, 0.05, 0.047), "GunMetal")
    w.B((0.026, 0.15, 0.022), (0, 0.04, 0.02), "GunPolymer")
    w.grip(m="GunPolymer", h=0.105)
    w.guard()
    w.B((0.006, 0.01, 0.008), (0, 0.13, 0.068), "GunBlack", bevel=0)
    w.B((0.014, 0.008, 0.008), (0, -0.035, 0.068), "GunBlack", bevel=0)
    w.C(0.008, 0.012, (0, 0.146, 0.047), "GunBlack")
    w.part("Body")
    w.mark("Muzzle", (0, 0.155, 0.047))
    w.suppressor(0.145, 0.047, 0.016, 0.13)
    w.flashlight(0.085, 0.0)
    w.extmag((0.024, 0.036, 0.06), (0, -0.045, -0.125), rot=(T(14), 0, 0))
    return w.root


def revolver(cell):
    w = W("w_revolver", cell)
    w.C(0.011, 0.17, (0, 0.135, 0.052), "Steel")
    w.B((0.014, 0.15, 0.018), (0, 0.125, 0.034), "Steel")
    w.C(0.025, 0.05, (0, 0.022, 0.042), "Steel", segs=6)
    w.B((0.022, 0.09, 0.07), (0, 0.0, 0.03), "Steel")
    w.B((0.03, 0.045, 0.11), (0, -0.045, -0.05), "GunWood", rot=(T(22), 0, 0))
    w.guard(0.0, 0.055)
    w.B((0.008, 0.02, 0.018), (0, -0.05, 0.075), "Steel", bevel=0, rot=(T(-30), 0, 0))
    w.B((0.005, 0.012, 0.012), (0, 0.21, 0.068), "Steel", bevel=0)
    w.part("Body")
    w.mark("Muzzle", (0, 0.225, 0.052))
    w.scope(0.04, 0.062, 0.12, 0.013)
    return w.root


def smg(cell):
    w = W("w_smg", cell)
    w.B((0.042, 0.27, 0.062), (0, 0.085, 0.05), "GunMetal")
    w.C(0.011, 0.09, (0, 0.26, 0.05), "GunBlack")
    w.grip(h=0.10)
    w.guard()
    w.B((0.03, 0.012, 0.012), (0, 0.085, 0.086), "GunBlack", bevel=0)
    w.B((0.008, 0.016, 0.02), (0, 0.20, 0.09), "GunBlack", bevel=0)
    for s in (1, -1):
        w.mb.tube((s * 0.016, -0.05, 0.065), (s * 0.016, -0.25, 0.065), 0.006, "GunBlack", segs=4)
    w.B((0.045, 0.012, 0.09), (0, -0.255, 0.04), "GunBlack")
    w.part("Body")
    w.B((0.024, 0.034, 0.15), (0, 0.10, -0.045), "GunBlack")
    w.part("Mag")
    w.mark("Muzzle", (0, 0.31, 0.05))
    w.suppressor(0.30, 0.05, 0.02, 0.15)
    w.flashlight(0.20, 0.008)
    w.reddot(0.06, 0.081)
    w.foregrip(0.19, 0.02)
    w.extmag((0.024, 0.034, 0.09), (0, 0.10, -0.165))
    return w.root


def shotgun(cell):
    w = W("w_shotgun", cell)
    w.B((0.042, 0.24, 0.062), (0, 0.06, 0.05), "GunMetal")
    w.C(0.012, 0.56, (0, 0.44, 0.066), "GunMetal")
    w.C(0.011, 0.44, (0, 0.38, 0.04), "GunMetal")
    w.B((0.036, 0.25, 0.05), (0, -0.18, 0.02), "GunWood", rot=(T(-10), 0, 0))
    w.B((0.036, 0.03, 0.10), (0, -0.305, 0.0), "Rubber")
    w.guard(0.0, 0.06, -0.03)
    w.B((0.006, 0.008, 0.01), (0, 0.70, 0.082), "GunBlack", bevel=0)
    w.part("Body")
    w.C(0.024, 0.17, (0, 0.33, 0.042), "GunWood", segs=8)
    w.part("Pump")
    w.mark("Muzzle", (0, 0.73, 0.066))
    w.flashlight(0.52, 0.04, 0.03)
    w.C(0.011, 0.14, (0, 0.66, 0.04), "GunMetal")
    w.part("Att_ExtMag", hide=True)
    return w.root


def autoshotgun(cell):
    w = W("w_autoshotgun", cell)
    w.B((0.046, 0.30, 0.07), (0, 0.08, 0.05), "GunPolymer")
    w.C(0.013, 0.36, (0, 0.40, 0.06), "GunMetal")
    w.B((0.04, 0.26, 0.045), (0, 0.33, 0.05), "GunBlack")
    w.grip(h=0.10)
    w.guard()
    w.B((0.036, 0.20, 0.07), (0, -0.17, 0.035), "GunPolymer")
    w.B((0.038, 0.025, 0.11), (0, -0.28, 0.02), "Rubber")
    w.B((0.03, 0.22, 0.012), (0, 0.10, 0.092), "GunBlack", bevel=0)
    w.part("Body")
    w.C(0.062, 0.05, (0, 0.12, -0.035), "GunBlack", axis='X', segs=10)
    w.part("Mag")
    w.mark("Muzzle", (0, 0.59, 0.06))
    w.flashlight(0.44, 0.02)
    w.foregrip(0.30, 0.03)
    w.C(0.075, 0.07, (0, 0.12, -0.045), "GunBlack", axis='X', segs=10)
    w.part("Att_ExtMag", hide=True)
    w.reddot(0.06, 0.098)
    return w.root


def rifle(cell):
    w = W("w_rifle", cell)
    w.B((0.042, 0.25, 0.07), (0, 0.065, 0.05), "GunMetal")
    w.B((0.044, 0.25, 0.052), (0, 0.31, 0.055), "GunPolymer")
    w.C(0.009, 0.20, (0, 0.53, 0.06), "GunMetal")
    w.C(0.013, 0.05, (0, 0.63, 0.06), "GunBlack")
    w.B((0.008, 0.012, 0.05), (0, 0.50, 0.095), "GunBlack", bevel=0)
    w.grip(h=0.10, m="GunPolymer")
    w.guard()
    w.B((0.036, 0.20, 0.062), (0, -0.19, 0.04), "GunPolymer")
    w.C(0.016, 0.08, (0, -0.06, 0.055), "GunMetal")
    w.B((0.038, 0.022, 0.10), (0, -0.30, 0.03), "Rubber")
    w.B((0.026, 0.30, 0.012), (0, 0.12, 0.091), "GunBlack", bevel=0)
    w.part("Body")
    w.B((0.024, 0.055, 0.17), (0, 0.105, -0.065), "GunBlack", rot=(T(-12), 0, 0))
    w.part("Mag")
    w.mark("Muzzle", (0, 0.665, 0.06))
    w.suppressor(0.64, 0.06, 0.02, 0.18)
    w.flashlight(0.36, 0.055, 0.036)
    w.scope(0.08, 0.097, 0.16, 0.016)
    w.foregrip(0.32, 0.03)
    w.extmag((0.024, 0.055, 0.09), (0, 0.128, -0.185), rot=(T(-22), 0, 0))
    return w.root


def carbine(cell):
    """Bullpup layout for a distinct silhouette."""
    w = W("w_carbine", cell)
    w.B((0.046, 0.52, 0.085), (0, -0.04, 0.045), "Olive")
    w.B((0.04, 0.16, 0.055), (0, 0.29, 0.05), "GunPolymer")
    w.C(0.009, 0.12, (0, 0.42, 0.055), "GunMetal")
    w.C(0.013, 0.04, (0, 0.49, 0.055), "GunBlack")
    w.grip(h=0.095, m="GunPolymer")
    w.B((0.01, 0.20, 0.008), (0, 0.10, -0.075), "GunPolymer", bevel=0)
    w.B((0.01, 0.008, 0.08), (0, 0.20, -0.035), "GunPolymer", bevel=0)
    w.B((0.014, 0.26, 0.02), (0, 0.05, 0.115), "GunBlack", bevel=0)
    w.B((0.012, 0.012, 0.03), (0, -0.06, 0.10), "GunBlack", bevel=0)
    w.B((0.012, 0.012, 0.03), (0, 0.16, 0.10), "GunBlack", bevel=0)
    w.B((0.048, 0.025, 0.10), (0, -0.305, 0.04), "Rubber")
    w.part("Body")
    w.B((0.024, 0.055, 0.15), (0, -0.16, -0.06), "GunBlack", rot=(T(-10), 0, 0))
    w.part("Mag")
    w.mark("Muzzle", (0, 0.52, 0.055))
    w.suppressor(0.50, 0.055, 0.02, 0.16)
    w.flashlight(0.30, 0.05, 0.034)
    w.reddot(0.05, 0.125)
    w.foregrip(0.27, 0.025)
    w.extmag((0.024, 0.055, 0.08), (0, -0.14, -0.17), rot=(T(-18), 0, 0))
    return w.root


def marksman(cell):
    w = W("w_marksman", cell)
    w.B((0.04, 0.30, 0.06), (0, 0.08, 0.05), "GunMetal")
    w.B((0.042, 0.34, 0.045), (0, 0.36, 0.04), "GunWood")
    w.C(0.009, 0.40, (0, 0.68, 0.058), "GunMetal")
    w.B((0.014, 0.03, 0.03), (0, 0.88, 0.058), "GunBlack")
    w.B((0.036, 0.30, 0.06), (0, -0.20, 0.015), "GunWood", rot=(T(-8), 0, 0))
    w.B((0.03, 0.05, 0.09), (0, -0.04, -0.02), "GunWood", rot=(T(20), 0, 0))
    w.B((0.036, 0.022, 0.11), (0, -0.355, -0.005), "Rubber")
    w.guard(0.0, 0.06, -0.03)
    w.part("Body")
    w.B((0.024, 0.06, 0.09), (0, 0.11, -0.02), "GunBlack")
    w.part("Mag")
    w.scope(0.09, 0.08, 0.22, 0.016, name="Scope", hide=False)
    w.mark("Muzzle", (0, 0.90, 0.058))
    w.suppressor(0.89, 0.058, 0.02, 0.20)
    w.extmag((0.024, 0.06, 0.07), (0, 0.11, -0.10))
    w.foregrip(0.40, 0.02)
    return w.root


def sniper(cell):
    w = W("w_sniper", cell)
    w.B((0.046, 0.36, 0.07), (0, 0.09, 0.05), "GunMetal")
    w.B((0.042, 0.22, 0.05), (0, 0.36, 0.045), "GunPolymer")
    w.C(0.012, 0.62, (0, 0.76, 0.06), "GunMetal")
    w.B((0.04, 0.07, 0.036), (0, 1.09, 0.06), "GunBlack")
    w.grip(h=0.10, m="GunPolymer")
    w.guard()
    w.mb.tube((0, -0.09, 0.06), (0, -0.36, 0.06), 0.012, "GunMetal")
    w.mb.tube((0, -0.09, 0.0), (0, -0.36, -0.01), 0.010, "GunMetal")
    w.B((0.04, 0.03, 0.13), (0, -0.375, 0.025), "Rubber")
    w.B((0.03, 0.10, 0.03), (0, -0.25, 0.085), "GunPolymer")
    for s in (1, -1):
        w.mb.tube((s * 0.02, 0.44, 0.03), (s * 0.05, 0.62, -0.02), 0.006, "GunBlack", segs=4)
    w.part("Body")
    w.B((0.03, 0.08, 0.08), (0, 0.13, -0.02), "GunBlack")
    w.part("Mag")
    w.scope(0.10, 0.085, 0.30, 0.021, name="Scope", hide=False)
    w.mark("Muzzle", (0, 1.13, 0.06))
    w.suppressor(1.12, 0.06, 0.024, 0.24)
    w.extmag((0.03, 0.08, 0.06), (0, 0.13, -0.09))
    return w.root


def rocket_mesh(mb, y0=0.0):
    mb.lathe([(y0, 0.0), (y0 - 0.10, 0.045), (y0 - 0.22, 0.05), (y0 - 0.30, 0.025), (y0 - 0.55, 0.022), (y0 - 0.55, 0.0)],
             axis='Y', segs=8, m=lambda k: "GunAccent" if k < 2 else "Olive")
    for i in range(4):
        a = i * math.pi / 2
        mb.box((0.003, 0.10, 0.07), loc=(math.cos(a) * 0.045, y0 - 0.50, math.sin(a) * 0.045), m="DarkSteel", rot=(0, -a + math.pi / 2, 0))


def rpg(cell):
    w = W("w_rpg", cell)
    w.C(0.042, 0.92, (0, 0.10, 0.10), "Olive", segs=10)
    w.mb.lathe([(-0.36, 0.042), (-0.50, 0.075)], axis='Y', segs=10, m="DarkSteel", loc=(0, 0, 0.10))
    w.B((0.05, 0.30, 0.03), (0, 0.10, 0.06), "GunWood")
    w.grip(h=0.10, m="GunWood")
    w.B((0.028, 0.04, 0.09), (0, 0.24, 0.0), "GunWood")
    w.guard()
    w.B((0.02, 0.05, 0.07), (-0.05, 0.06, 0.16), "GunBlack")
    w.part("Body")
    rocket_mesh(w.mb, 0.86)
    w.mb.transform(list(w.mb.bm.verts), loc=(0, 0, 0.10))
    w.part("Rocket")
    w.mark("Muzzle", (0, 0.90, 0.10))
    return w.root


def grenade_launcher(cell):
    w = W("w_glauncher", cell)
    w.B((0.045, 0.16, 0.06), (0, 0.02, 0.05), "GunMetal")
    w.C(0.062, 0.11, (0, 0.14, 0.035), "DarkSteel", segs=6)
    w.C(0.028, 0.26, (0, 0.33, 0.06), "GunMetal", segs=8)
    w.grip(h=0.10, m="GunPolymer")
    w.guard()
    w.B((0.026, 0.035, 0.085), (0, 0.30, -0.005), "GunPolymer")
    w.mb.tube((0, -0.06, 0.06), (0, -0.30, 0.05), 0.012, "GunMetal")
    w.B((0.04, 0.025, 0.11), (0, -0.31, 0.03), "Rubber")
    w.B((0.02, 0.04, 0.05), (0, 0.10, 0.11), "GunBlack")
    w.part("Body")
    w.mark("Muzzle", (0, 0.47, 0.06))
    return w.root


def grenade(cell):
    w = W("w_grenade", cell)
    w.mb.lathe([(-0.045, 0.0), (-0.035, 0.03), (0.0, 0.038), (0.035, 0.03), (0.045, 0.014), (0.062, 0.014), (0.062, 0.0)],
               axis='Z', segs=8, m=lambda k: "Olive" if k < 4 else "Steel")
    w.B((0.01, 0.022, 0.07), (0.0, 0.03, 0.03), "Steel", bevel=0, rot=(T(-18), 0, 0))
    w.part("Body")
    return w.root


def molotov(cell):
    w = W("w_molotov", cell)
    mat("BottleGlass", "#3f7a3a", rough=0.1, alpha=0.6)
    w.mb.lathe([(-0.10, 0.0), (-0.10, 0.035), (0.04, 0.035), (0.08, 0.014), (0.13, 0.014), (0.13, 0.0)], axis='Z', segs=8, m="BottleGlass")
    w.B((0.02, 0.02, 0.07), (0.005, 0, 0.16), "Canvas", rot=(0, T(15), 0))
    w.part("Body")
    return w.root


def knife(cell):
    w = W("w_knife", cell)
    w.B((0.022, 0.028, 0.11), (0, 0, -0.02), "GunGrip")
    w.B((0.012, 0.06, 0.012), (0, 0.004, 0.04), "Steel", bevel=0)
    w.mb.extrude_poly([(-0.002, -0.014, 0.046), (-0.002, 0.018, 0.046), (-0.002, 0.016, 0.20), (-0.002, 0.0, 0.235), (-0.002, -0.014, 0.19)], (0.004, 0, 0), "Chrome")
    w.part("Body")
    return w.root


def bat(cell):
    w = W("w_bat", cell)
    w.mb.lathe([(-0.10, 0.0), (-0.10, 0.022), (-0.08, 0.016), (0.20, 0.018), (0.50, 0.033), (0.72, 0.034), (0.74, 0.0)],
               axis='Z', segs=8, m=lambda k: "Rubber" if k < 3 else "GunWood")
    w.part("Body")
    return w.root


def crowbar(cell):
    w = W("w_crowbar", cell)
    w.mb.tube((0, 0, -0.10), (0, 0, 0.48), 0.011, "PaintRed", segs=6)
    w.mb.tube((0, 0, 0.48), (0, 0.05, 0.55), 0.011, "PaintRed", segs=6)
    w.mb.tube((0, 0.05, 0.55), (0, 0.10, 0.52), 0.010, "DarkSteel", segs=6)
    w.mb.tube((0, 0, -0.10), (0, -0.03, -0.14), 0.010, "DarkSteel", segs=6)
    w.part("Body")
    return w.root


def nightstick(cell):
    w = W("w_nightstick", cell)
    w.mb.tube((0, 0, -0.10), (0, 0, 0.48), 0.014, "GunBlack", segs=8)
    w.mb.tube((0, 0, 0.02), (0, 0.10, 0.02), 0.012, "GunBlack", segs=6)
    w.part("Body")
    return w.root


BUILDERS = [pistol, revolver, smg, shotgun, autoshotgun, rifle, carbine, marksman, sniper, rpg, grenade_launcher,
            grenade, molotov, knife, bat, crowbar, nightstick]


def vfx_helpers(cell):
    coll = col("VFX_HelperMeshes")
    kill("vfx_kit")
    root = empty("vfx_kit", coll, loc=cell, size=0.2)
    mat("FlashCore", "#fff2b0", rough=0.5, emit="#ffd060", estr=6.0)
    mat("Money", "#4f9a4a", rough=0.8)
    mat("MoneyBand", "#f0ead0", rough=0.8)
    mat("MedWhite", "#f1f1ec", rough=0.6)
    mat("ArmorBlue", "#2a4f8f", rough=0.5, metal=0.3)
    mat("Brass", "#c9a03a", rough=0.3, metal=1.0)
    items = []

    def fin(mb, name, smooth=None):
        o = mb.finish(name, coll, smooth=smooth, parent=root, loc=(len(items) * 0.6, 0, 0.3))
        items.append(name)
    mb = MB()
    for a in (0, 60, 120):
        mb.poly([(-0.06, 0, 0), (0, 0.02, 0), (0.06, 0, 0), (0, 0.34, 0)], "FlashCore")
        mb.transform(list(mb.bm.verts)[-4:], rot=(0, T(a), 0))
    for a in (0, 45, 90, 135):
        mb.poly([(-0.10, 0.03, 0), (0.0, 0.0, 0), (0.10, 0.03, 0), (0, 0.06, 0)], "FlashCore")
        mb.transform(list(mb.bm.verts)[-4:], rot=(0, T(a), 0))
    fin(mb, "vfx_muzzle")
    mb = MB(); mb.cyl(0.006, 0.022, axis='Y', segs=6, m="Brass"); fin(mb, "vfx_shell", 40)
    for i, sc in enumerate([(1, 0.7, 0.5), (0.6, 1, 0.8), (0.8, 0.5, 1)]):
        mb = MB(); mb.sphere(0.12, m="ConcreteDark", ico=1, scale=sc)
        for v in mb.bm.verts:
            v.co *= 0.8 + 0.4 * ((v.index * 7919 + i * 31) % 10) / 10.0
        fin(mb, "vfx_debris_%d" % i)
    mb = MB(); mb.poly([(0, 0, 0), (0.10, 0, 0.02), (0.03, 0, 0.14)], "Glass"); fin(mb, "vfx_shard")
    mb = MB(); mb.box((0.16, 0.08, 0.05), m="Money"); mb.box((0.05, 0.084, 0.054), m="MoneyBand"); fin(mb, "pickup_money")
    mb = MB(); mb.box((0.30, 0.12, 0.22), m="MedWhite", bevel=0.02)
    mb.box((0.14, 0.01, 0.045), loc=(0, 0.062, 0), m="PaintRed"); mb.box((0.045, 0.01, 0.14), loc=(0, 0.062, 0), m="PaintRed")
    mb.box((0.10, 0.02, 0.02), loc=(0, 0, 0.12), m="Trim"); fin(mb, "pickup_health", 40)
    mb = MB(); mb.ellipse_loft([(-0.20, 0, 0, 0.17, 0.11), (0.0, 0, 0, 0.20, 0.13), (0.14, 0, 0, 0.17, 0.11)], segs=8, m="ArmorBlue", axis='Z', squareness=0.3)
    mb.box((0.14, 0.02, 0.05), loc=(0, 0.125, 0.05), m="Steel"); fin(mb, "pickup_armor", 40)
    mb = MB(); mb.box((0.26, 0.16, 0.14), m="Olive", bevel=0.012); mb.box((0.27, 0.165, 0.02), loc=(0, 0, 0.045), m="DarkSteel")
    mb.box((0.10, 0.02, 0.02), loc=(0, 0, 0.085), m="DarkSteel"); fin(mb, "pickup_ammo", 40)
    mb = MB(); rocket_mesh(mb, 0.28); fin(mb, "proj_rocket", 40)
    mb = MB(); mb.cyl(0.02, 0.07, axis='Y', segs=6, m="Olive"); mb.sphere(0.02, loc=(0, 0.035, 0), m="Brass", segs=6, rings=4); fin(mb, "proj_grenade40", 40)
    return root


def build_all():
    out = []
    for i, fn in enumerate(BUILDERS):
        r = fn((20 + (i % 9) * 0.6, 4 + (i // 9) * 1.5, 1.0))
        out.append(stats(r))
    out.append(stats(vfx_helpers((20, 1, 0))))
    return out


def export_all():
    roots = [o.name for o in bpy.data.objects if o.name.startswith("w_") and o.parent is None and o.type == 'EMPTY']
    return [export(roots, "weapons/weapons.glb", center=False), export("vfx_kit", "props/vfx_kit.glb")]
