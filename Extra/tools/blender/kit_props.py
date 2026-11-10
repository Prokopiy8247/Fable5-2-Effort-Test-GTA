# Street props, interior furniture, nature and animals for Cinder Bay. Executed in Blender through MCP.
# Props: origin at ground centre, "front" faces -Y (Godot +Z).
import bpy, math
from mathutils import Vector
from fable_lib import *
from kit_buildings import Kit

T = math.radians


def street(K):
    mat("TrafficRedA", "#5a1010", rough=0.4, emit="#ff2a1a", estr=0.1)
    mat("TrafficYellowA", "#5a4a10", rough=0.4, emit="#ffc81a", estr=0.1)
    mat("TrafficGreenA", "#104a20", rough=0.4, emit="#28ff5a", estr=0.1)
    mat("TrafficRedB", "#5a1010", rough=0.4, emit="#ff2a1a", estr=0.1)
    mat("TrafficYellowB", "#5a4a10", rough=0.4, emit="#ffc81a", estr=0.1)
    mat("TrafficGreenB", "#104a20", rough=0.4, emit="#28ff5a", estr=0.1)
    for g in ("A", "B"):
        # pole at origin (sidewalk corner), arm reaches over the road along -X; lamps face -Y
        mb = MB()
        mb.cyl(0.10, 6.2, loc=(0, 0, 3.1), segs=6, m="DarkSteel", r2=0.07)
        mb.cyl(0.16, 0.5, loc=(0, 0, 0.25), segs=6, m="DarkSteel")
        mb.tube((0, 0, 6.0), (-5.2, 0, 6.2), 0.06, "DarkSteel")
        for x in (-4.8, -2.4):
            mb.box((0.38, 0.30, 1.10), loc=(x, 0, 5.75), m="Trim", bevel=0.04)
            for k, c in enumerate(("TrafficRed", "TrafficYellow", "TrafficGreen")):
                mb.cyl(0.115, 0.06, loc=(x, -0.16, 6.08 - k * 0.33), axis='Y', segs=8, m=c + g)
                mb.box((0.30, 0.16, 0.03), loc=(x, -0.23, 6.21 - k * 0.33), m="Trim")
        mb.box((0.34, 0.26, 0.85), loc=(0.0, -0.16, 2.9), m="Trim", bevel=0.04)
        for k, c in enumerate(("TrafficRed", "TrafficYellow", "TrafficGreen")):
            mb.cyl(0.09, 0.05, loc=(0.0, -0.30, 3.16 - k * 0.26), axis='Y', segs=8, m=c + g)
        K.add("prop_traffic_light_" + g, mb, smooth=40)
    mb = MB()
    mb.cyl(0.09, 7.5, loc=(0, 0, 3.75), segs=6, m="DarkSteel", r2=0.06)
    mb.cyl(0.15, 0.6, loc=(0, 0, 0.3), segs=6, m="DarkSteel")
    mb.tube((0, 0, 7.4), (0, -2.0, 7.9), 0.05, "DarkSteel")
    mb.box((0.34, 0.85, 0.12), loc=(0, -2.3, 7.9), m="DarkSteel", bevel=0.03)
    mb.box((0.26, 0.70, 0.03), loc=(0, -2.3, 7.83), m="LampGlow")
    K.add("prop_street_lamp", mb, smooth=40)
    mb = MB()
    mb.cyl(0.06, 3.6, loc=(0, 0, 1.8), segs=6, m="FrameDark")
    mb.cyl(0.12, 0.3, loc=(0, 0, 0.15), segs=6, m="FrameDark")
    mb.sphere(0.24, loc=(0, 0, 3.75), m="LampGlow", segs=8, rings=5)
    mb.cyl(0.14, 0.08, loc=(0, 0, 3.98), segs=6, m="FrameDark")
    K.add("prop_park_lamp", mb, smooth=40)

    def sign(name, shape, m_face, h=2.6):
        mb = MB()
        mb.cyl(0.035, h, loc=(0, 0, h / 2), segs=5, m="Steel")
        if shape == "oct":
            mb.cyl(0.38, 0.03, loc=(0, -0.05, h - 0.1), axis='Y', segs=8, m=m_face)
            mb.cyl(0.26, 0.035, loc=(0, -0.052, h - 0.1), axis='Y', segs=8, m="PaintWhite")
            mb.cyl(0.22, 0.04, loc=(0, -0.054, h - 0.1), axis='Y', segs=8, m=m_face)
        elif shape == "round":
            mb.cyl(0.34, 0.03, loc=(0, -0.05, h - 0.1), axis='Y', segs=12, m="PaintRed")
            mb.cyl(0.27, 0.035, loc=(0, -0.052, h - 0.1), axis='Y', segs=12, m=m_face)
            mb.box((0.26, 0.04, 0.07), loc=(0, -0.055, h - 0.1), m="Trim")
        elif shape == "rect":
            mb.box((0.62, 0.03, 0.42), loc=(0, -0.05, h - 0.15), m=m_face)
            mb.box((0.36, 0.035, 0.10), loc=(0.04, -0.052, h - 0.15), m="PaintWhite")
            mb.poly([(-0.26, -0.07, h - 0.15), (-0.14, -0.07, h - 0.05), (-0.14, -0.07, h - 0.25)], "PaintWhite", outward=(0, -1, 0))
        elif shape == "tri":
            mb.cyl(0.42, 0.03, loc=(0, -0.05, h - 0.2), axis='Y', segs=3, m="PaintRed", rot=(0, T(60), 0))
            mb.cyl(0.30, 0.035, loc=(0, -0.052, h - 0.2), axis='Y', segs=3, m=m_face, rot=(0, T(60), 0))
        elif shape == "name":
            mb.box((1.1, 0.03, 0.22), loc=(0.45, 0, h - 0.05), m=m_face)
            mb.box((0.8, 0.035, 0.07), loc=(0.45, 0, h - 0.05), m="PaintWhite")
            mb.box((0.03, 1.1, 0.22), loc=(0, 0.45, h - 0.30), m=m_face)
            mb.box((0.035, 0.8, 0.07), loc=(0, 0.45, h - 0.30), m="PaintWhite")
        elif shape == "park":
            mb.box((0.46, 0.03, 0.56), loc=(0, -0.05, h - 0.2), m=m_face)
            mb.box((0.10, 0.035, 0.34), loc=(-0.07, -0.052, h - 0.2), m="PaintWhite")
            mb.box((0.20, 0.035, 0.10), loc=(0.02, -0.052, h - 0.08), m="PaintWhite")
            mb.box((0.20, 0.035, 0.10), loc=(0.02, -0.052, h - 0.22), m="PaintWhite")
            mb.box((0.07, 0.035, 0.14), loc=(0.11, -0.052, h - 0.15), m="PaintWhite")
        K.add(name, mb, smooth=30)
    sign("prop_sign_stop", "oct", "PaintRed")
    sign("prop_sign_speed", "round", "PaintWhite")
    sign("prop_sign_oneway", "rect", "Trim")
    sign("prop_sign_yield", "tri", "PaintWhite")
    sign("prop_sign_street", "name", "SignGreen", 3.2)
    sign("prop_sign_parking", "park", "SignBlue")
    mb = MB()
    mb.extrude_poly([(-0.30, -1.5, 0), (0.30, -1.5, 0), (0.30, -1.5, 0.22), (0.12, -1.5, 0.45), (0.10, -1.5, 0.85), (-0.10, -1.5, 0.85), (-0.12, -1.5, 0.45), (-0.30, -1.5, 0.22)], (0, 3.0, 0), "Concrete")
    K.add("prop_barrier_jersey", mb)
    mb = MB()
    mb.box((0.45, 1.8, 0.75), loc=(0, 0, 0.42), m="PaintOrange", bevel=0.08, taper=(0.55, 1.0))
    mb.box((0.30, 1.82, 0.16), loc=(0, 0, 0.58), m="PaintWhite")
    K.add("prop_barrier_plastic", mb, smooth=40)
    mb = MB()
    mb.box((2.4, 0.06, 0.22), loc=(0, 0, 1.0), m="PoliceWhite")
    for i in range(5):
        mb.box((0.22, 0.065, 0.22), loc=(-0.96 + i * 0.48, 0, 1.0), m="SignBlue")
    for s in (1, -1):
        mb.tube((s * 0.95, -0.35, 0), (s * 0.95, 0, 1.05), 0.03, "DarkSteel", segs=4)
        mb.tube((s * 0.95, 0.35, 0), (s * 0.95, 0, 1.05), 0.03, "DarkSteel", segs=4)
    K.add("prop_barrier_police", mb)
    mb = MB()
    mb.tube((-1.2, 0, 0.05), (-1.2, 0, 1.05), 0.025, "Steel", segs=5)
    mb.tube((1.2, 0, 0.05), (1.2, 0, 1.05), 0.025, "Steel", segs=5)
    mb.tube((-1.2, 0, 1.05), (1.2, 0, 1.05), 0.025, "Steel", segs=5)
    mb.tube((-1.2, 0, 0.25), (1.2, 0, 0.25), 0.02, "Steel", segs=5)
    for i in range(9):
        mb.tube((-0.96 + i * 0.24, 0, 0.25), (-0.96 + i * 0.24, 0, 1.05), 0.012, "Steel", segs=4)
    for s in (1, -1):
        mb.box((0.05, 0.5, 0.04), loc=(s * 1.2, 0, 0.03), m="Steel")
    K.add("prop_barrier_metal", mb)
    mb = MB()
    for z in (0.42,):
        for y in (-0.16, 0.0, 0.16):
            mb.box((1.7, 0.13, 0.04), loc=(0, y, z), m="Wood")
    for z in (0.62, 0.80):
        mb.box((1.7, 0.04, 0.12), loc=(0, 0.25, z), m="Wood", rot=(T(-10), 0, 0))
    for s in (1, -1):
        mb.box((0.06, 0.50, 0.42), loc=(s * 0.72, 0.0, 0.21), m="FrameDark")
        mb.box((0.06, 0.06, 0.50), loc=(s * 0.72, 0.25, 0.65), m="FrameDark", rot=(T(-10), 0, 0))
    K.add("prop_bench", mb)
    mb = MB()
    mb.cyl(0.26, 0.85, loc=(0, 0, 0.45), segs=8, m="PaintGreen", r2=0.30)
    mb.cyl(0.32, 0.08, loc=(0, 0, 0.92), segs=8, m="FrameDark")
    mb.cyl(0.22, 0.02, loc=(0, 0, 0.965), segs=8, m="Under")
    K.add("prop_bin", mb, smooth=40)
    mb = MB()
    mb.cyl(0.13, 0.55, loc=(0, 0, 0.30), segs=8, m="PaintRed")
    mb.cyl(0.17, 0.06, loc=(0, 0, 0.05), segs=8, m="PaintRed")
    mb.sphere(0.13, loc=(0, 0, 0.58), m="PaintRed", segs=8, rings=4)
    mb.cyl(0.05, 0.08, loc=(0, 0, 0.72), segs=6, m="PaintRed")
    mb.cyl(0.06, 0.40, loc=(0, 0, 0.40), axis='X', segs=6, m="PaintRed")
    mb.cyl(0.07, 0.12, loc=(0, -0.14, 0.36), axis='Y', segs=6, m="Chrome")
    K.add("prop_hydrant", mb, smooth=40)
    mb = MB()
    mb.box((3.6, 1.4, 0.08), loc=(0, 0, 2.5), m="FrameDark")
    mb.box((3.5, 0.05, 2.0), loc=(0, 0.65, 1.4), m="GlassClear")
    for s in (1, -1):
        mb.box((0.05, 1.3, 2.0), loc=(s * 1.75, 0, 1.4), m="GlassClear")
        mb.box((0.08, 0.08, 2.5), loc=(s * 1.75, 0.65, 1.25), m="FrameDark")
        mb.box((0.08, 0.08, 2.5), loc=(s * 1.75, -0.65, 1.25), m="FrameDark")
    mb.box((2.4, 0.4, 0.06), loc=(0, 0.35, 0.5), m="Wood")
    mb.box((0.9, 0.06, 1.3), loc=(1.2, 0.60, 1.5), m="SignWhite")
    mb.cyl(0.035, 3.0, loc=(2.4, -0.5, 1.5), segs=5, m="Steel")
    mb.box((0.5, 0.04, 0.5), loc=(2.4, -0.5, 2.8), m="SignBlue")
    K.add("prop_bus_stop", mb)
    mb = MB()
    for x in (-2, 2):
        mb.cyl(0.035, 2.0, loc=(x, 0, 1.0), segs=5, m="Steel")
    mb.tube((-2, 0, 1.98), (2, 0, 1.98), 0.025, "Steel", segs=5)
    mb.tube((-2, 0, 0.1), (2, 0, 0.1), 0.02, "Steel", segs=5)
    mat("ChainLink", "#9aa3aa", rough=0.6, metal=0.5, alpha=0.45)
    mb.poly([(-2, 0, 0.1), (2, 0, 0.1), (2, 0, 1.98), (-2, 0, 1.98)], "ChainLink", outward=(0, -1, 0))
    mb.poly([(-2, 0.001, 0.1), (2, 0.001, 0.1), (2, 0.001, 1.98), (-2, 0.001, 1.98)], "ChainLink", outward=(0, 1, 0))
    K.add("prop_fence_chain", mb)
    mb = MB()
    for i in range(10):
        mb.box((0.30, 0.03, 1.0 + (0.08 if i % 2 else 0)), loc=(-1.8 + i * 0.4, 0, 0.55), m="PaintWhite")
    mb.box((4, 0.05, 0.08), loc=(0, 0.04, 0.35), m="PaintWhite")
    mb.box((4, 0.05, 0.08), loc=(0, 0.04, 0.85), m="PaintWhite")
    K.add("prop_fence_picket", mb)
    mb = MB()
    for i in range(14):
        mb.tube((-1.95 + i * 0.3, 0, 0.1), (-1.95 + i * 0.3, 0, 1.45), 0.015, "FrameDark", segs=4)
    mb.box((4, 0.04, 0.05), loc=(0, 0, 0.2), m="FrameDark")
    mb.box((4, 0.04, 0.05), loc=(0, 0, 1.3), m="FrameDark")
    for x in (-2, 2):
        mb.box((0.10, 0.10, 1.6), loc=(x, 0, 0.8), m="FrameDark")
    K.add("prop_fence_iron", mb)
    mb = MB()
    mb.box((4.0, 0.25, 0.9), loc=(0, 0, 0.45), m="Concrete")
    mb.box((4.0, 0.32, 0.08), loc=(0, 0, 0.94), m="ConcreteDark")
    K.add("prop_wall_low", mb)
    mb = MB()
    mb.box((0.9, 0.5, 1.3), loc=(0, 0, 0.72), m="WallGrey", bevel=0.03)
    mb.box((0.95, 0.55, 0.08), loc=(0, 0, 0.06), m="ConcreteDark")
    mb.box((0.4, 0.02, 0.9), loc=(-0.21, -0.255, 0.75), m="MetalPanel")
    mb.box((0.4, 0.02, 0.9), loc=(0.21, -0.255, 0.75), m="MetalPanel")
    mb.box((0.12, 0.03, 0.12), loc=(0.3, -0.26, 1.2), m="PaintYellow")
    K.add("prop_utility_box", mb)
    mb = MB()
    mb.cyl(0.09, 0.9, loc=(0, 0, 0.45), segs=8, m="FrameDark")
    mb.sphere(0.09, loc=(0, 0, 0.9), m="FrameDark", segs=8, rings=4)
    mb.cyl(0.095, 0.08, loc=(0, 0, 0.7), segs=8, m="PaintYellow")
    K.add("prop_bollard", mb, smooth=40)
    mb = MB()
    mb.cyl(0.17, 0.70, loc=(0, 0, 0.38), segs=8, m="PaintOrange", r2=0.035)
    mb.box((0.42, 0.42, 0.035), loc=(0, 0, 0.018), m="PaintOrange")
    mb.cyl(0.125, 0.12, loc=(0, 0, 0.42), segs=8, m="PaintWhite", r2=0.095)
    K.add("prop_cone", mb, smooth=40)
    mb = MB()
    mb.box((0.45, 0.45, 0.75), loc=(0, 0, 0.85), m="PaintBlue", bevel=0.06)
    mb.cyl(0.225, 0.45, loc=(0, 0, 1.22), axis='X', segs=8, m="PaintBlue")
    mb.box((0.30, 0.02, 0.06), loc=(0, -0.23, 1.15), m="Under")
    for x in (-0.17, 0.17):
        for y in (-0.17, 0.17):
            mb.box((0.05, 0.05, 0.5), loc=(x, y, 0.25), m="PaintBlue")
    K.add("prop_mailbox", mb, smooth=40)
    mb = MB()
    mb.cyl(0.03, 1.1, loc=(0, 0, 0.55), segs=5, m="Steel")
    mb.box((0.16, 0.10, 0.30), loc=(0, 0, 1.22), m="DarkSteel", bevel=0.03)
    mb.box((0.10, 0.02, 0.07), loc=(0, -0.052, 1.27), m="LampGlow")
    K.add("prop_parking_meter", mb)
    mb = MB()
    mb.box((1.9, 1.1, 1.15), loc=(0, 0, 0.72), m="PaintGreen", taper=(1.0, 1.0), bevel=0.03)
    mb.box((1.96, 1.16, 0.07), loc=(0, 0.04, 1.33), m="Trim", rot=(T(4), 0, 0))
    for x in (-0.8, 0.8):
        for y in (-0.4, 0.4):
            mb.cyl(0.07, 0.05, loc=(x, y, 0.07), axis='X', segs=6, m="Rubber")
    mb.box((0.06, 0.5, 0.06), loc=(-0.98, 0, 1.0), m="DarkSteel")
    mb.box((0.06, 0.5, 0.06), loc=(0.98, 0, 1.0), m="DarkSteel")
    K.add("prop_dumpster", mb)
    mb = MB()
    mb.box((0.9, 0.9, 0.9), loc=(0, 0, 0.45), m="Wood")
    for s in (1, -1):
        mb.box((0.94, 0.04, 0.10), loc=(0, s * 0.46, 0.12), m="WoodDark")
        mb.box((0.94, 0.04, 0.10), loc=(0, s * 0.46, 0.78), m="WoodDark")
        mb.box((0.04, 0.94, 0.10), loc=(s * 0.46, 0, 0.12), m="WoodDark")
        mb.box((0.04, 0.94, 0.10), loc=(s * 0.46, 0, 0.78), m="WoodDark")
    K.add("prop_crate", mb)
    mb = MB()
    for y in (-0.5, 0, 0.5):
        mb.box((1.2, 0.10, 0.10), loc=(0, y, 0.05), m="WoodDark")
    for i in range(7):
        mb.box((0.14, 1.1, 0.025), loc=(-0.53 + i * 0.177, 0, 0.115), m="Wood")
    K.add("prop_pallet", mb)
    for nm, m_, band in (("prop_barrel_explosive", "PaintRed", "PaintYellow"), ("prop_barrel", "PaintBlue", "DarkSteel")):
        mb = MB()
        mb.cyl(0.29, 0.88, loc=(0, 0, 0.44), segs=10, m=m_)
        for z in (0.03, 0.30, 0.58, 0.85):
            mb.cyl(0.30, 0.03, loc=(0, 0, z), segs=10, m="DarkSteel" if band == "DarkSteel" else m_)
        mb.cyl(0.295, 0.2, loc=(0, 0, 0.44), segs=10, m=band)
        K.add(nm, mb, smooth=40)
    mb = MB()
    for i in range(4):
        mb.lathe([(-0.11, 0.20), (-0.11, 0.30), (0.0, 0.34), (0.11, 0.30), (0.11, 0.20)], axis='Z', segs=10, m="Tire", loc=(0, 0, 0.11 + i * 0.22))
    K.add("prop_tire_stack", mb, smooth=40)
    mb = MB()
    mb.box((0.95, 0.8, 1.9), loc=(0, 0, 0.98), m="PaintRed", bevel=0.04)
    mb.box((0.75, 0.03, 1.1), loc=(-0.05, -0.405, 1.25), m="SignWhite")
    mb.box((0.14, 0.03, 0.5), loc=(0.38, -0.405, 1.1), m="Trim")
    mb.box((0.6, 0.06, 0.18), loc=(-0.05, -0.41, 0.35), m="Under")
    K.add("prop_vending", mb)
    mb = MB()
    mb.box((0.45, 0.4, 0.9), loc=(0, 0, 0.55), m="PaintYellow", bevel=0.04)
    mb.box((0.34, 0.02, 0.4), loc=(0, -0.205, 0.7), m="GlassClear")
    mb.box((0.06, 0.06, 0.12), loc=(-0.15, -0.12, 0.06), m="Trim")
    mb.box((0.06, 0.06, 0.12), loc=(0.15, 0.12, 0.06), m="Trim")
    K.add("prop_newsbox", mb)
    mb = MB()
    mb.box((1.4, 0.6, 0.5), loc=(0, 0, 0.25), m="Concrete", taper=(1.1, 1.2))
    mb.box((1.3, 0.5, 0.06), loc=(0, 0, 0.5), m="Dirt")
    for x in (-0.4, 0, 0.4):
        mb.sphere(0.24, loc=(x, 0, 0.72), m="Leaf", ico=1, scale=(1, 0.9, 0.9))
    for x in (-0.3, 0.2):
        mb.sphere(0.07, loc=(x, -0.12, 0.9), m="Flower", ico=1)
    K.add("prop_planter", mb)
    mb = MB()
    mb.box((1.8, 0.75, 0.05), loc=(0, 0, 0.75), m="Wood")
    for s in (1, -1):
        mb.box((1.8, 0.28, 0.05), loc=(0, s * 0.62, 0.45), m="Wood")
        mb.tube((s * 0.7, -0.75, 0), (s * 0.7, 0.35, 0.75), 0.03, "WoodDark", segs=4)
        mb.tube((s * 0.7, 0.75, 0), (s * 0.7, -0.35, 0.75), 0.03, "WoodDark", segs=4)
    K.add("prop_picnic_table", mb)
    mb = MB()
    mb.box((0.8, 0.55, 2.0), loc=(0, 0, 1.0), m="WallGrey", bevel=0.03)
    mb.box((0.5, 0.03, 0.4), loc=(0, -0.28, 1.45), m="LampGlow")
    mb.box((0.5, 0.10, 0.25), loc=(0, -0.3, 1.05), m="DarkSteel", rot=(T(-25), 0, 0))
    mb.box((0.84, 0.6, 0.3), loc=(0, 0, 2.0), m="SignGreen")
    K.add("prop_atm", mb)
    mb = MB()
    for s in (1, -1):
        mb.tube((s * 0.22, 0, 0), (s * 0.22, 0, 6.0), 0.03, "Steel", segs=5)
    for i in range(19):
        mb.tube((-0.22, 0, 0.3 + i * 0.3), (0.22, 0, 0.3 + i * 0.3), 0.02, "Steel", segs=4)
    K.add("prop_ladder", mb)
    mb = MB()
    mb.cyl(0.03, 1.5, loc=(0, 0, 0.75), segs=5, m="Steel")
    mb.box((0.5, 0.5, 0.04), loc=(0, 0, 0.02), m="DarkSteel")
    K.add("prop_target_stand", mb)
    mb = MB()
    mb.cyl(0.36, 0.03, axis='Y', segs=12, m="PaintWhite")
    mb.cyl(0.26, 0.035, axis='Y', segs=12, m="PaintRed")
    mb.cyl(0.16, 0.04, axis='Y', segs=12, m="PaintWhite")
    mb.cyl(0.07, 0.045, axis='Y', segs=12, m="PaintRed")
    K.add("prop_target", mb, smooth=30)
    mb = MB()
    for i in range(4):
        for j in range(2 - (i % 2)):
            mb.box((0.75, 0.38, 0.2), loc=((j - 0.5 + (i % 2) * 0.5) * 0.78, 0, 0.1 + i * 0.19), m="Canvas", bevel=0.06)
    K.add("prop_sandbags", mb, smooth=40)
    mb = MB()
    mb.box((1.4, 1.0, 0.9), loc=(0, 0, 0.5), m="WallGrey", bevel=0.03)
    mb.cyl(0.35, 0.06, loc=(0, 0, 0.97), segs=8, m="DarkSteel")
    for i in range(5):
        mb.box((1.2, 0.02, 0.05), loc=(0, -0.51, 0.25 + i * 0.13), m="DarkSteel")
    K.add("prop_ac_unit", mb)
    mb = MB()
    mb.cyl(1.3, 2.4, loc=(0, 0, 2.6), segs=10, m="Wood")
    mb.cyl(1.4, 0.7, loc=(0, 0, 4.15), segs=10, m="RoofDark", r2=0.1)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        mb.tube((math.cos(a) * 1.1, math.sin(a) * 1.1, 0), (math.cos(a) * 1.1, math.sin(a) * 1.1, 1.4), 0.07, "DarkSteel", segs=4)
    K.add("prop_roof_tank", mb, smooth=40)
    mb = MB()
    mb.box((0.6, 0.6, 0.7), loc=(0, 0, 0.35), m="MetalPanel")
    mb.cyl(0.26, 0.5, loc=(0, 0, 0.95), segs=8, m="MetalPanel")
    mb.cyl(0.36, 0.1, loc=(0, 0, 1.25), segs=8, m="DarkSteel", r2=0.1)
    K.add("prop_roof_vent", mb, smooth=40)
    mb = MB()
    mb.tube((0, 0, 0), (0, 0, 7), 0.05, "Steel", segs=4)
    for z, w in ((5.5, 1.2), (6.0, 0.9), (6.5, 0.6)):
        mb.tube((-w / 2, 0, z), (w / 2, 0, z), 0.02, "Steel", segs=4)
    mb.box((0.1, 0.1, 0.1), loc=(0, 0, 7.05), m="LightBarRed")
    K.add("prop_antenna", mb)
    mb = MB()
    mb.lathe([(0.0, 0.0), (0.12, 0.55), (0.30, 0.8)], axis='Z', segs=10, m="PaintWhite", loc=(0, -0.2, 1.0), rot=(T(55), 0, 0))
    mb.tube((0, 0, 0), (0, 0, 1.0), 0.04, "Steel", segs=4)
    K.add("prop_dish", mb, smooth=40)
    mb = MB()
    mb.box((3.2, 2.2, 2.4), loc=(0, 0, 1.2), m="WallGrey")
    mb.box((0.9, 0.05, 2.0), loc=(0.6, -1.11, 1.0), m="Door")
    mb.box((3.3, 2.3, 0.1), loc=(0, 0, 2.45), m="ConcreteDark")
    K.add("prop_roof_stair", mb)
    mb = MB()
    mb.tube((0, 0, 0), (0, 0, 9), 0.11, "WoodDark", segs=6)
    mb.box((2.2, 0.10, 0.12), loc=(0, 0, 8.4), m="WoodDark")
    mb.box((1.4, 0.10, 0.10), loc=(0, 0, 7.7), m="WoodDark")
    for x in (-1.0, 1.0, -0.6, 0.6):
        mb.cyl(0.04, 0.12, loc=(x, 0, 8.52 if abs(x) == 1.0 else 7.8), segs=5, m="Steel")
    K.add("prop_power_pole", mb)
    mb = MB()
    for i, (x, y, s) in enumerate([(0, 0, 0.32), (0.3, 0.15, 0.26), (-0.25, 0.2, 0.28)]):
        mb.sphere(s, loc=(x, y, s * 0.8), m="Trim", ico=1, scale=(1, 1, 0.85))
    K.add("prop_trash_bags", mb)
    mb = MB()
    mb.box((0.5, 0.4, 0.35), loc=(0, 0, 0.175), m="Canvas")
    mb.box((0.4, 0.35, 0.3), loc=(0.05, 0.02, 0.5), m="Canvas", rot=(0, 0, 0.3))
    mb.box((0.35, 0.3, 0.25), loc=(0.5, 0.1, 0.125), m="Canvas", rot=(0, 0, -0.2))
    K.add("prop_boxes", mb)
    mb = MB()
    mb.lathe([(0.0, 3.2), (0.5, 3.2), (0.5, 3.0), (0.25, 2.9)], axis='Z', segs=12, m="Concrete")
    mb.cyl(2.9, 0.06, loc=(0, 0, 0.36), segs=12, m="PoolWater")
    mb.lathe([(0.3, 0.5), (1.6, 0.35), (1.7, 1.1), (1.85, 1.1), (1.85, 0.0)], axis='Z', segs=8, m="Concrete")
    mb.cyl(0.9, 0.05, loc=(0, 0, 1.83), segs=8, m="PoolWater")
    K.add("prop_fountain", mb, smooth=40)
    mb = MB()
    mb.box((1.6, 1.6, 1.2), loc=(0, 0, 0.6), m="Concrete", bevel=0.05)
    mb.sphere(0.9, loc=(0, 0, 2.2), m="Chrome", ico=1, scale=(1, 0.6, 1.3))
    mb.box((0.5, 0.5, 1.6), loc=(0.2, 0, 2.6), m="Chrome", rot=(0.3, 0.5, 0.2))
    K.add("prop_statue", mb)
    mb = MB()
    for x in (-1.5, 1.5):
        for y in (-1.5, 1.5):
            mb.tube((x, y, 0), (x * 0.8, y * 0.8, 3.2), 0.07, "PaintWhite", segs=4)
    mb.box((2.8, 2.8, 0.12), loc=(0, 0, 2.2), m="Wood")
    mb.box((2.6, 2.6, 1.0), loc=(0, 0, 2.75), m="PaintWhite")
    mb.box((2.62, 0.05, 0.5), loc=(0, -1.3, 2.95), m="GlassClear")
    mb.box((3.2, 3.2, 0.12), loc=(0, 0, 3.35), m="PaintRed", rot=(T(6), 0, 0))
    for i in range(7):
        mb.box((0.8, 0.3, 0.05), loc=(0, 1.6 + i * 0.3, 2.0 - i * 0.3), m="Wood")
    K.add("prop_lifeguard_tower", mb)
    mb = MB()
    mb.cyl(0.03, 2.3, loc=(0, 0, 1.15), segs=5, m="Wood")
    mb.cyl(1.5, 0.5, loc=(0, 0, 2.2), segs=8, m="AwningTint", r2=0.05)
    K.add("prop_umbrella", mb)
    mb = MB()
    mb.box((0.65, 1.3, 0.06), loc=(0, -0.2, 0.3), m="PaintWhite")
    mb.box((0.65, 0.7, 0.06), loc=(0, 0.72, 0.5), m="PaintWhite", rot=(T(35), 0, 0))
    for x in (-0.28, 0.28):
        for y in (-0.7, 0.3):
            mb.box((0.05, 0.05, 0.3), loc=(x, y, 0.15), m="PaintWhite")
    K.add("prop_lounger", mb)
    mb = MB()
    mb.lathe([(-0.5, 0.0), (-0.3, 0.45), (0.3, 0.5), (0.6, 0.2), (1.5, 0.12)], axis='Z', segs=8, m=lambda k: "PaintRed" if k != 1 else "PaintWhite")
    mb.sphere(0.14, loc=(0, 0, 1.6), m="LampGlow", segs=6, rings=4)
    K.add("prop_buoy", mb, smooth=40)
    mb = MB()
    mb.cyl(0.05, 8, loc=(0, 0, 4), segs=6, m="Steel")
    mb.box((1.6, 0.03, 1.0), loc=(0.85, 0, 7.4), m="AwningTint")
    mb.sphere(0.09, loc=(0, 0, 8.05), m="Badge", segs=6, rings=4)
    K.add("prop_flagpole", mb)
    mb = MB()
    for i in range(5):
        mb.tube((-0.8 + i * 0.4, -0.3, 0), (-0.8 + i * 0.4, 0, 0.8), 0.02, "Steel", segs=4)
        mb.tube((-0.8 + i * 0.4, 0.3, 0), (-0.8 + i * 0.4, 0, 0.8), 0.02, "Steel", segs=4)
    mb.tube((-0.9, 0, 0.8), (0.9, 0, 0.8), 0.02, "Steel", segs=4)
    K.add("prop_bike_rack", mb)
    mb = MB()
    mb.box((3.6, 0.5, 0.03), loc=(0, 0, 0.015), m="Trim")
    for i in range(18):
        mb.cyl(0.03, 0.09, loc=(-1.7 + i * 0.2, 0, 0.06), segs=4, m="Steel", r2=0.0)
    K.add("prop_spike_strip", mb)
    mb = MB()
    mb.cyl(0.3, 0.45, loc=(0, 0, 0.225), segs=8, m="Bark")
    mb.cyl(0.28, 0.02, loc=(0, 0, 0.455), segs=8, m="BarkPale")
    K.add("prop_stump", mb)
    mb = MB()
    mb.box((0.5, 0.35, 0.3), loc=(0, 0, 0.15), m="Wood", bevel=0.03)
    mb.cyl(0.175, 0.5, loc=(0, 0, 0.30), axis='X', segs=8, m="WoodDark")
    mb.box((0.52, 0.02, 0.06), loc=(0, -0.18, 0.28), m="Badge")
    K.add("prop_chest", mb)
    # curbs
    mb = MB()
    mb.extrude_poly([(-2, 0, 0), (-2, -0.30, 0), (-2, -0.30, 0.02), (-2, -0.18, 0.02), (-2, -0.14, 0.16), (-2, 0, 0.16)], (4, 0, 0), "Curb")
    K.add("curb_straight", mb)
    mb = MB()
    mb.box((0.30, 0.30, 0.16), loc=(-0.15, -0.15, 0.08), m="Curb")
    K.add("curb_corner", mb)


def interiors(K):
    mat("CashGreen", "#2f8f5b", rough=0.6)
    mat("Screen", "#1a2a3a", rough=0.2, emit="#4f9fff", estr=0.8)
    mat("Fabric", "#b3472e", rough=0.95)
    mat("FabricBlue", "#3d5a8a", rough=0.95)
    mat("Mirror", "#c8d8e0", rough=0.03, metal=1.0)
    mb = MB()
    mb.box((3.0, 0.7, 1.0), loc=(0, 0, 0.5), m="Wood")
    mb.box((3.1, 0.8, 0.06), loc=(0, 0, 1.03), m="WoodDark")
    mb.box((0.4, 0.35, 0.3), loc=(0.9, 0, 1.2), m="Trim", bevel=0.03)
    mb.box((0.3, 0.02, 0.2), loc=(0.9, -0.1, 1.42), m="Screen", rot=(T(-20), 0, 0))
    K.add("int_counter", mb)
    mb = MB()
    mb.box((2.0, 0.45, 2.0), loc=(0, 0, 1.0), m="WoodDark")
    for i in range(4):
        mb.box((1.9, 0.42, 0.04), loc=(0, -0.03, 0.3 + i * 0.5), m="Wood")
        for j in range(5):
            cm = ["PaintRed", "PaintBlue", "PaintYellow", "PaintGreen", "PaintOrange"][(i + j) % 5]
            mb.box((0.22, 0.25, 0.28), loc=(-0.75 + j * 0.37, -0.06, 0.46 + i * 0.5), m=cm)
    K.add("int_shelf", mb)
    mb = MB()
    mb.box((3.0, 0.08, 1.6), loc=(0, 0, 1.6), m="WoodDark")
    for i in range(4):
        z = 1.1 + i * 0.36
        mb.box((2.2, 0.05, 0.05), loc=(0, -0.1, z + 0.02), m="GunMetal")
        mb.box((1.2, 0.04, 0.09), loc=(-0.3, -0.1, z + 0.09), m="GunWood" if i % 2 else "GunPolymer")
        mb.box((0.08, 0.04, 0.16), loc=(-0.45, -0.1, z + 0.0), m="GunBlack")
    for x in (-1.3, 1.3):
        mb.box((0.06, 0.12, 1.5), loc=(x, -0.06, 1.6), m="GunMetal")
    K.add("int_gun_rack", mb)
    mb = MB()
    mb.tube((-0.9, 0, 1.6), (0.9, 0, 1.6), 0.02, "Chrome", segs=5)
    for s in (1, -1):
        mb.tube((s * 0.9, 0, 0), (s * 0.9, 0, 1.6), 0.02, "Chrome", segs=5)
        mb.box((0.05, 0.6, 0.04), loc=(s * 0.9, 0, 0.02), m="Chrome")
    cols = ["Fabric", "FabricBlue", "PaintYellow", "PaintGreen", "PaintWhite", "Trim", "PaintOrange"]
    for i in range(7):
        mb.box((0.06, 0.45, 0.7), loc=(-0.72 + i * 0.24, 0, 1.2), m=cols[i], taper=(1.0, 0.8))
    K.add("int_clothes_rack", mb)
    mb = MB()
    mb.box((1.6, 2.1, 0.35), loc=(0, 0, 0.3), m="WoodDark")
    mb.box((1.5, 2.0, 0.2), loc=(0, 0, 0.55), m="PaintWhite", bevel=0.05)
    mb.box((1.5, 1.2, 0.08), loc=(0, -0.38, 0.68), m="FabricBlue", bevel=0.03)
    mb.box((0.6, 0.35, 0.12), loc=(-0.36, 0.75, 0.70), m="PaintWhite", bevel=0.04)
    mb.box((0.6, 0.35, 0.12), loc=(0.36, 0.75, 0.70), m="PaintWhite", bevel=0.04)
    mb.box((1.7, 0.1, 1.1), loc=(0, 1.05, 0.55), m="WoodDark")
    K.add("int_bed", mb, smooth=40)
    mb = MB()
    mb.box((2.0, 0.85, 0.42), loc=(0, 0, 0.25), m="Fabric", bevel=0.06)
    mb.box((2.0, 0.22, 0.55), loc=(0, 0.32, 0.65), m="Fabric", bevel=0.06)
    for s in (1, -1):
        mb.box((0.22, 0.85, 0.35), loc=(s * 0.92, 0, 0.55), m="Fabric", bevel=0.06)
    K.add("int_sofa", mb, smooth=40)
    mb = MB()
    mb.box((1.6, 0.6, 2.1), loc=(0, 0, 1.05), m="Wood")
    mb.box((0.76, 0.03, 1.9), loc=(-0.39, -0.31, 1.05), m="WoodDark")
    mb.box((0.76, 0.03, 1.9), loc=(0.39, -0.31, 1.05), m="WoodDark")
    for s in (1, -1):
        mb.box((0.03, 0.04, 0.2), loc=(s * 0.06, -0.34, 1.05), m="Chrome")
    K.add("int_wardrobe", mb)
    mb = MB()
    mb.box((1.2, 0.7, 0.05), loc=(0, 0, 0.74), m="Wood")
    for x in (-0.52, 0.52):
        for y in (-0.28, 0.28):
            mb.box((0.06, 0.06, 0.72), loc=(x, y, 0.36), m="WoodDark")
    K.add("int_table", mb)
    mb = MB()
    mb.box((0.45, 0.45, 0.05), loc=(0, 0, 0.45), m="Wood")
    mb.box((0.45, 0.05, 0.5), loc=(0, 0.2, 0.72), m="Wood")
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            mb.box((0.04, 0.04, 0.45), loc=(x, y, 0.225), m="WoodDark")
    K.add("int_chair", mb)
    mb = MB()
    mb.box((1.4, 0.45, 0.5), loc=(0, 0, 0.25), m="WoodDark")
    mb.box((1.3, 0.06, 0.75), loc=(0, 0, 0.98), m="Trim")
    mb.box((1.2, 0.02, 0.65), loc=(0, -0.035, 0.98), m="Screen")
    K.add("int_tv", mb)
    mb = MB()
    mb.cyl(0.28, 0.08, loc=(0, 0, 0.04), segs=8, m="Chrome")
    mb.cyl(0.05, 0.45, loc=(0, 0, 0.3), segs=6, m="Chrome")
    mb.box((0.55, 0.55, 0.12), loc=(0, 0, 0.56), m="Fabric", bevel=0.04)
    mb.box((0.52, 0.10, 0.65), loc=(0, 0.25, 0.92), m="Fabric", bevel=0.04, rot=(T(-8), 0, 0))
    for s in (1, -1):
        mb.box((0.07, 0.4, 0.06), loc=(s * 0.3, 0, 0.78), m="Chrome")
    mb.box((0.4, 0.2, 0.04), loc=(0, -0.45, 0.2), m="Chrome")
    K.add("int_barber_chair", mb, smooth=40)
    mb = MB()
    mb.box((1.2, 0.06, 1.4), loc=(0, 0, 1.5), m="WoodDark")
    mb.box((1.05, 0.02, 1.25), loc=(0, -0.035, 1.5), m="Mirror")
    mb.box((1.2, 0.35, 0.05), loc=(0, -0.15, 0.75), m="Wood")
    K.add("int_mirror", mb)
    mb = MB()
    mb.box((2.4, 4.6, 0.14), loc=(0, 0, 0.07), m="PaintYellow")
    for s in (1, -1):
        mb.box((0.25, 0.25, 2.6), loc=(s * 1.5, 0, 1.3), m="PaintBlue")
        mb.box((0.5, 0.6, 0.08), loc=(s * 1.5, 0, 0.04), m="DarkSteel")
    K.add("int_car_lift", mb)
    mb = MB()
    mb.box((1.0, 0.5, 0.95), loc=(0, 0, 0.55), m="PaintRed", bevel=0.02)
    for i in range(5):
        mb.box((0.9, 0.02, 0.14), loc=(0, -0.255, 0.2 + i * 0.17), m="FireRed")
        mb.box((0.3, 0.03, 0.02), loc=(0, -0.27, 0.2 + i * 0.17), m="Chrome")
    for x in (-0.4, 0.4):
        for y in (-0.18, 0.18):
            mb.cyl(0.05, 0.04, loc=(x, y, 0.05), axis='X', segs=6, m="Rubber")
    K.add("int_tool_chest", mb)
    mb = MB()
    mb.box((2.2, 0.7, 0.08), loc=(0, 0, 0.9), m="Wood")
    for x in (-1.0, 1.0):
        mb.box((0.08, 0.6, 0.9), loc=(x, 0, 0.45), m="DarkSteel")
    mb.box((2.2, 0.05, 1.0), loc=(0, 0.33, 1.5), m="WallGrey")
    for i in range(6):
        mb.box((0.05, 0.03, 0.3), loc=(-0.8 + i * 0.32, 0.29, 1.5), m=["Steel", "PaintRed", "DarkSteel"][i % 3])
    mb.box((0.3, 0.25, 0.2), loc=(0.6, 0, 1.04), m="PaintBlue", bevel=0.02)
    K.add("int_workbench", mb)
    mb = MB()
    mb.box((1.1, 0.5, 0.75), loc=(0, 0, 0.375), m="DarkSteel", bevel=0.03)
    mb.box((1.0, 0.45, 0.04), loc=(0, 0, 0.77), m="Steel")
    mb.box((0.25, 0.25, 0.3), loc=(-0.25, 0, 0.94), m="DarkSteel")
    mb.cyl(0.03, 0.3, loc=(0.2, 0, 0.9), axis='Y', segs=6, m="GunMetal")
    K.add("int_gunsmith_bench", mb)


def nature(K):
    def blob(mb, r, loc, m, sc=(1, 1, 1), seed=0, ico=1):
        vs = mb.sphere(r, loc=loc, m=m, ico=ico, scale=sc)
        for v in vs:
            k = ((int(v.co.x * 977 + v.co.y * 613 + v.co.z * 389) + seed * 131) % 17) / 17.0
            c = Vector(loc)
            v.co = c + (v.co - c) * (0.86 + 0.28 * k)
    for lod in (0, 1):
        sfx = "" if lod == 0 else "_lod1"
        mb = MB()
        mb.cyl(0.22, 2.6, loc=(0, 0, 1.3), segs=6 if lod == 0 else 4, m="Bark", r2=0.14)
        if lod == 0:
            blob(mb, 1.7, (0, 0, 4.0), "Leaf", (1, 1, 0.85), 1, 2)
            blob(mb, 1.1, (1.0, 0.4, 3.3), "LeafDark", (1, 1, 0.8), 2)
            blob(mb, 1.0, (-0.9, -0.5, 3.5), "LeafLight", (1, 1, 0.8), 3)
            mb.tube((0, 0, 2.2), (0.8, 0.3, 3.0), 0.07, "Bark", segs=4)
        else:
            blob(mb, 1.9, (0, 0, 3.9), "Leaf", (1.05, 1.05, 0.85), 1)
        K.add("tree_round" + sfx, mb)
        mb = MB()
        mb.cyl(0.18, 2.0, loc=(0, 0, 1.0), segs=6 if lod == 0 else 4, m="Bark", r2=0.12)
        if lod == 0:
            blob(mb, 1.15, (0, 0, 3.4), "LeafDark", (1, 1, 2.0), 4, 2)
            blob(mb, 0.8, (0.1, 0.1, 5.6), "Leaf", (1, 1, 1.6), 5)
        else:
            blob(mb, 1.2, (0, 0, 4.0), "LeafDark", (1, 1, 2.5), 4)
        K.add("tree_tall" + sfx, mb)
        mb = MB()
        mb.cyl(0.17, 1.6, loc=(0, 0, 0.8), segs=6 if lod == 0 else 4, m="Bark")
        tiers = [(1.9, 2.6, 1.2), (1.5, 2.4, 2.6), (1.1, 2.2, 3.9), (0.7, 1.9, 5.1)] if lod == 0 else [(1.9, 5.8, 1.2)]
        for r, h, z in tiers:
            mb.cyl(r, h, loc=(0, 0, z + h / 2), segs=7 if lod == 0 else 5, m="Pine", r2=0.02)
        K.add("tree_pine" + sfx, mb)
        mb = MB()
        pts = [(0, 0, 0), (0.25, 0, 2.0), (0.7, 0, 4.2), (1.3, 0, 6.2)]
        for i in range(3):
            mb.tube(pts[i], pts[i + 1], 0.20 - i * 0.03, "BarkPale", segs=6 if lod == 0 else 4, r2=0.17 - i * 0.03)
        n = 7 if lod == 0 else 5
        for i in range(n):
            a = 2 * math.pi * i / n
            c, s = math.cos(a), math.sin(a)
            top = Vector((1.3, 0, 6.3))
            mid = top + Vector((c * 1.4, s * 1.4, 0.35))
            end = top + Vector((c * 2.7, s * 2.7, -0.9))
            side = Vector((-s, c, 0)) * 0.42
            mb.poly([top, mid - side, end, mid + side], "Palm")
            mb.poly([top, mid + side, end, mid - side], "Palm")
        if lod == 0:
            mb.sphere(0.22, loc=(1.3, 0, 6.15), m="Bark", segs=6, rings=4)
        K.add("tree_palm" + sfx, mb)
    mb = MB(); blob(mb, 0.7, (0, 0, 0.5), "Leaf", (1.2, 1, 0.75), 6); blob(mb, 0.5, (0.6, 0.2, 0.4), "LeafDark", (1, 1, 0.8), 7); K.add("bush_a", mb)
    mb = MB(); blob(mb, 0.55, (0, 0, 0.4), "LeafLight", (1.1, 1.1, 0.8), 8)
    for (x, y) in ((0.2, 0.3), (-0.3, 0.1), (0.1, -0.35)):
        mb.sphere(0.07, loc=(x, y, 0.75), m="Flower", ico=1)
    K.add("bush_b", mb)
    mb = MB(); blob(mb, 0.9, (0, 0, 0.45), "Rock", (1.3, 1.0, 0.7), 9); K.add("rock_a", mb)
    mb = MB(); blob(mb, 1.6, (0, 0, 0.9), "RockDark", (1.0, 1.2, 0.8), 10); blob(mb, 0.8, (1.3, 0.5, 0.4), "Rock", (1, 1, 0.7), 11); K.add("rock_b", mb)
    mb = MB(); blob(mb, 0.4, (0, 0, 0.2), "Rock", (1.1, 0.9, 0.7), 12); K.add("rock_c", mb)
    mb = MB()
    for i in range(7):
        a = i * 0.9
        r = 0.05 + 0.03 * (i % 3)
        x, y = math.cos(a * 2.3) * 0.18 * (i % 3), math.sin(a * 1.7) * 0.18 * (i % 2 + 1)
        h = 0.28 + 0.12 * (i % 4)
        dx, dy = math.cos(a) * r, math.sin(a) * r
        mb.poly([(x - dx, y - dy, 0), (x + dx, y + dy, 0), (x + dx * 0.2 + 0.05, y + dy * 0.2, h)], "Grass")
        mb.poly([(x + dx, y + dy, 0), (x - dx, y - dy, 0), (x + dx * 0.2 + 0.05, y + dy * 0.2, h)], "Grass")
    K.add("grass_clump", mb)
    mb = MB()
    for i in range(5):
        a = i * 1.3
        x, y = math.cos(a) * 0.15, math.sin(a) * 0.15
        mb.tube((x, y, 0), (x * 1.2, y * 1.2, 0.3), 0.008, "Grass", segs=3)
        mb.sphere(0.045, loc=(x * 1.2, y * 1.2, 0.32), m="Flower" if i % 2 else "FlowerYellow", ico=1)
    K.add("flower_clump", mb)
    mb = MB()
    for i in range(6):
        a = i * 1.1
        x, y = math.cos(a) * 0.2, math.sin(a) * 0.2
        mb.tube((x, y, 0), (x * 1.3 + 0.1, y * 1.3, 1.6 + 0.2 * (i % 3)), 0.015, "LeafLight", segs=3)
    mb.cyl(0.03, 0.2, loc=(0.1, 0, 1.6), segs=4, m="Bark")
    K.add("reed", mb)
    mb = MB()
    for i in range(5):
        a = i * 1.25
        x, y = math.cos(a) * 0.15, math.sin(a) * 0.15
        h = 1.0 + 0.4 * (i % 3)
        mb.poly([(x - 0.06, y, 0), (x + 0.06, y, 0), (x + 0.12, y + 0.05, h * 0.5), (x, y, h), (x - 0.1, y - 0.04, h * 0.5)], "Seaweed")
        mb.poly([(x + 0.06, y, 0), (x - 0.06, y, 0), (x - 0.1, y - 0.04, h * 0.5), (x, y, h), (x + 0.12, y + 0.05, h * 0.5)], "Seaweed")
    K.add("seaweed", mb)
    mb = MB()
    for i in range(6):
        a = i * 1.05
        mb.tube((0, 0, 0), (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.45 + 0.1 * (i % 2)), 0.06, "Coral", segs=4, r2=0.035)
    mb.sphere(0.2, loc=(0, 0, 0.1), m="Coral", ico=1)
    K.add("coral", mb)
    mb = MB()
    mb.cyl(0.25, 3.0, loc=(0, 0, 0.25), axis='Y', segs=7, m="Bark")
    mb.tube((0, 0.5, 0.4), (0.3, 0.8, 0.8), 0.06, "Bark", segs=4)
    K.add("log", mb)


def animal(K, name, body, head, legs, tail, mats, wings=None, fin=None):
    """Animals are small hierarchies of rigid parts (procedurally animated in Godot). Faces +Y."""
    coll = K.coll
    kill(name)
    x = (K.n % K.per_row) * K.spacing
    y = (K.n // K.per_row) * K.spacing
    K.n += 1
    root = empty(name, coll, loc=(x, y, 0), parent=K.root, size=0.2)
    mb = MB()
    L, W, H, z = body
    mb.ellipse_loft([(L / 2, 0, z + H * 0.05, W * 0.30, H * 0.36), (L * 0.25, 0, z, W / 2, H / 2), (-L * 0.25, 0, z, W * 0.48, H * 0.48),
                     (-L / 2, 0, z + H * 0.05, W * 0.30, H * 0.34)], segs=7, m=mats[0])
    mb.finish(name + "_Body", coll, smooth=50, parent=root)
    hl, hw, hh, hy, hz, neck = head
    mb = MB()
    if neck > 0:
        mb.tube((0, -neck * 0.5, -neck * 0.8), (0, 0, 0), hw * 0.42, mats[0], segs=6, r2=hw * 0.38)
    mb.ellipse_loft([(hl * 0.62, 0, -hh * 0.12, hw * 0.16, hh * 0.18), (hl * 0.25, 0, -hh * 0.05, hw * 0.32, hh * 0.34), (-hl * 0.1, 0, 0, hw / 2, hh / 2),
                     (-hl * 0.38, 0, 0, hw * 0.4, hh * 0.42)], segs=6, m=mats[0])
    mb.box((hw * 0.34, hl * 0.10, hh * 0.18), loc=(0, hl * 0.62, -hh * 0.12), m=mats[2])
    for s in (1, -1):
        mb.box((hw * 0.10, hl * 0.08, hh * 0.12), loc=(s * hw * 0.36, hl * 0.12, hh * 0.14), m="Eye")
        mb.box((hw * 0.16, hl * 0.10, hh * 0.42), loc=(s * hw * 0.34, -hl * 0.24, hh * 0.56), m=mats[1], taper=(0.4, 0.6), rot=(0, s * 0.3, 0))
    if name == "animal_deer":
        for s in (1, -1):
            mb.tube((s * hw * 0.2, -hl * 0.1, hh * 0.4), (s * hw * 0.9, -hl * 0.3, hh * 1.5), 0.018, "BarkPale", segs=4)
            mb.tube((s * hw * 0.6, -hl * 0.22, hh * 1.0), (s * hw * 0.7, hl * 0.2, hh * 1.5), 0.014, "BarkPale", segs=4)
    mb.finish(name + "_Head", coll, smooth=50, parent=root, loc=(0, hy, hz))
    ll, lw, lx, lyf, lyr, lz = legs
    for nm, sx, yy in (("FL", -1, lyf), ("FR", 1, lyf), ("RL", -1, lyr), ("RR", 1, lyr)):
        mb = MB()
        mb.box((lw, lw * 1.2, ll), loc=(0, 0, -ll / 2), m=mats[1], taper=(1.6, 1.6))
        mb.box((lw * 1.1, lw * 1.5, ll * 0.10), loc=(0, lw * 0.15, -ll * 0.96), m=mats[2])
        mb.finish("%s_Leg_%s" % (name, nm), coll, parent=root, loc=(sx * lx, yy, lz))
    if tail:
        tl, tw, ty, tz = tail
        mb = MB()
        mb.box((tw, tl, tw), loc=(0, -tl / 2, 0), m=mats[1], taper=(0.5, 1.0), rot=(T(-25), 0, 0))
        mb.finish(name + "_Tail", coll, parent=root, loc=(0, ty, tz))
    return root


def animals(K):
    animal(K, "animal_deer", (1.25, 0.42, 0.50, 0.95), (0.36, 0.20, 0.22, 0.78, 1.42, 0.45), (0.74, 0.07, 0.14, 0.42, -0.45, 0.76), (0.14, 0.07, -0.62, 1.05),
           ("FurBrown", "FurTan", "FurBlack"))
    animal(K, "animal_dog", (0.75, 0.28, 0.30, 0.50), (0.26, 0.18, 0.18, 0.48, 0.70, 0.18), (0.36, 0.06, 0.09, 0.26, -0.28, 0.38), (0.26, 0.05, -0.38, 0.60),
           ("FurTan", "FurTan", "FurBlack"))
    animal(K, "animal_coyote", (0.85, 0.26, 0.30, 0.52), (0.28, 0.16, 0.17, 0.52, 0.70, 0.18), (0.38, 0.055, 0.085, 0.30, -0.32, 0.40), (0.34, 0.07, -0.42, 0.58),
           ("FurGrey", "FurTan", "FurBlack"))
    animal(K, "animal_cat", (0.42, 0.16, 0.18, 0.26), (0.14, 0.13, 0.12, 0.26, 0.36, 0.05), (0.18, 0.035, 0.05, 0.15, -0.15, 0.19), (0.26, 0.03, -0.21, 0.30),
           ("FurBlack", "FurBlack", "FurWhite"))
    animal(K, "animal_rabbit", (0.30, 0.14, 0.16, 0.16), (0.12, 0.10, 0.10, 0.17, 0.26, 0.03), (0.10, 0.035, 0.045, 0.10, -0.10, 0.11), (0.05, 0.05, -0.15, 0.18),
           ("FurWhite", "FurWhite", "Flower"))
    animal(K, "animal_boar", (1.0, 0.42, 0.48, 0.52), (0.34, 0.26, 0.26, 0.55, 0.50, 0.0), (0.34, 0.08, 0.13, 0.32, -0.34, 0.36), (0.14, 0.03, -0.5, 0.62),
           ("FurBlack", "FurBlack", "FurGrey"))
    animal(K, "animal_cow", (1.9, 0.70, 0.80, 1.05), (0.46, 0.28, 0.30, 1.10, 1.25, 0.25), (0.72, 0.11, 0.24, 0.62, -0.68, 0.74), (0.6, 0.04, -0.95, 1.25),
           ("FurWhite", "FurBlack", "Flower"))
    # birds: body + two wings
    for nm, m0, m1, sc in (("animal_seagull", "FurWhite", "FurGrey", 1.0), ("animal_pigeon", "FurGrey", "FurGrey", 0.7)):
        kill(nm)
        x = (K.n % K.per_row) * K.spacing
        y = (K.n // K.per_row) * K.spacing
        K.n += 1
        root = empty(nm, K.coll, loc=(x, y, 0.5), parent=K.root, size=0.1)
        mb = MB()
        mb.ellipse_loft([(0.22 * sc, 0, 0.03 * sc, 0.03 * sc, 0.03 * sc), (0.12 * sc, 0, 0.02 * sc, 0.06 * sc, 0.06 * sc), (-0.05 * sc, 0, 0, 0.08 * sc, 0.075 * sc),
                         (-0.24 * sc, 0, 0.0, 0.02 * sc, 0.015 * sc)], segs=6, m=m0)
        mb.box((0.02 * sc, 0.07 * sc, 0.02 * sc), loc=(0, 0.25 * sc, 0.025 * sc), m="Beak")
        mb.box((0.10 * sc, 0.10 * sc, 0.01 * sc), loc=(0, -0.26 * sc, 0), m=m1)
        mb.finish(nm + "_Body", K.coll, smooth=50, parent=root)
        for sn, s in (("L", -1), ("R", 1)):
            mb = MB()
            mb.poly([(0, 0.08 * sc, 0), (s * 0.30 * sc, 0.05 * sc, 0), (s * 0.55 * sc, -0.04 * sc, 0), (s * 0.28 * sc, -0.07 * sc, 0), (0, -0.07 * sc, 0)], m1)
            mb.poly(list(reversed([(0, 0.08 * sc, 0.002), (s * 0.30 * sc, 0.05 * sc, 0.002), (s * 0.55 * sc, -0.04 * sc, 0.002), (s * 0.28 * sc, -0.07 * sc, 0.002), (0, -0.07 * sc, 0.002)])), m0)
            mb.finish("%s_Wing_%s" % (nm, sn), K.coll, parent=root, loc=(s * 0.06 * sc, 0, 0.04 * sc))
    # fish + shark: body + tail
    for nm, m0, L, H in (("animal_fish", "FishOrange", 0.35, 0.14), ("animal_fish_b", "FishBlue", 0.28, 0.16), ("animal_shark", "SharkGrey", 3.2, 0.7)):
        kill(nm)
        x = (K.n % K.per_row) * K.spacing
        y = (K.n // K.per_row) * K.spacing
        K.n += 1
        root = empty(nm, K.coll, loc=(x, y, 0.8), parent=K.root, size=0.1)
        mb = MB()
        mb.ellipse_loft([(L * 0.5, 0, 0, L * 0.02, H * 0.08), (L * 0.3, 0, 0, L * 0.09, H * 0.38), (0, 0, 0, L * 0.11, H / 2), (-L * 0.35, 0, 0, L * 0.03, H * 0.15)], segs=6, m=m0)
        mb.extrude_poly([(-0.01, L * 0.1, H * 0.4), (-0.01, -L * 0.12, H * (1.0 if nm == "animal_shark" else 0.75)), (-0.01, -L * 0.14, H * 0.4)], (0.02, 0, 0), m0)
        for s in (1, -1):
            mb.poly([(s * L * 0.08, L * 0.15, -H * 0.2), (s * L * 0.28, 0, -H * 0.5), (s * L * 0.08, -L * 0.02, -H * 0.2)], m0)
            mb.poly([(s * L * 0.08, -L * 0.02, -H * 0.2), (s * L * 0.28, 0, -H * 0.5), (s * L * 0.08, L * 0.15, -H * 0.2)], m0)
            mb.box((0.012 * L, 0.03 * L, 0.03 * L), loc=(s * L * 0.085, L * 0.33, H * 0.1), m="Eye")
        if nm == "animal_shark":
            mb.box((L * 0.10, L * 0.02, H * 0.05), loc=(0, L * 0.42, -H * 0.12), m="FurWhite")
        mb.finish(nm + "_Body", K.coll, smooth=50, parent=root)
        mb = MB()
        mb.extrude_poly([(-0.01 * L, 0, 0), (-0.01 * L, -L * 0.22, H * 0.55), (-0.01 * L, -L * 0.14, 0), (-0.01 * L, -L * 0.22, -H * 0.45)], (0.02 * L, 0, 0), m0)
        mb.finish(nm + "_Tail", K.coll, parent=root, loc=(0, -L * 0.34, 0))


def build_all():
    mat("PoolWater", "#4fb8d8", rough=0.05, metal=0.2, alpha=0.8)
    mat("GlassClear", "#9fc4d6", rough=0.05, alpha=0.25)
    out = []
    K = Kit("kit_props", "StreetProps", (80, -60, 0), spacing=5.0, per_row=10)
    street(K)
    out.append(stats(K.root)); out.append(str(K.names))
    K = Kit("kit_interiors", "Interiors", (80, -100, 0), spacing=4.0, per_row=8)
    interiors(K)
    out.append(stats(K.root)); out.append(str(K.names))
    K = Kit("kit_nature", "Nature", (80, -130, 0), spacing=7.0, per_row=8)
    nature(K)
    out.append(stats(K.root)); out.append(str(K.names))
    K = Kit("kit_animals", "NPCs", (80, -160, 0), spacing=3.0, per_row=8)
    animals(K)
    out.append(stats(K.root))
    return out


def export_all():
    return [export("kit_props", "props/kit_props.glb", center=False), export("kit_interiors", "props/kit_interiors.glb", center=False),
            export("kit_nature", "world/kit_nature.glb", center=False), export("kit_animals", "characters/kit_animals.glb", center=True)]
