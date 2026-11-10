# Extra Blender-authored assets: swappable rim styles and an animated airport radar (keyframed action).
import bpy, math
from fable_lib import *
from vehicles import wheel_geo


def build_wheels(cell=(20, -10, 0)):
    coll = col("Vehicles/Cars")
    kill("wheels")
    root = empty("wheels", coll, loc=cell, size=0.3)
    names = []
    for style in range(5):
        mb = MB()
        wheel_geo(mb, 0.33, 0.22, style)
        mb.finish("wheel_%d" % style, coll, smooth=35, parent=root, loc=(style * 0.9, 0, 0.33))
        names.append("wheel_%d" % style)
    return root


def build_radar(cell=(30, -10, 0)):
    coll = col("StreetProps")
    kill("radar")
    root = empty("radar", coll, loc=cell, size=0.5)
    mb = MB()
    mb.box((3.0, 3.0, 0.5), loc=(0, 0, 0.25), m="Concrete")
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        mb.tube((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.5), (math.cos(a) * 0.5, math.sin(a) * 0.5, 7.5), 0.08, "PaintWhite", segs=4)
        a2 = a + math.pi / 2
        mb.tube((math.cos(a) * 1.1, math.sin(a) * 1.1, 2.6), (math.cos(a2) * 0.8, math.sin(a2) * 0.8, 5.2), 0.04, "PaintRed", segs=4)
    mb.box((1.3, 1.3, 0.25), loc=(0, 0, 7.6), m="DarkSteel")
    mb.finish("radar_Base", coll, smooth=None, parent=root)
    d = MB()
    d.cyl(0.14, 0.9, loc=(0, 0, 0.45), segs=8, m="DarkSteel")
    secs = []
    for k in range(7):
        t = -1.0 + k / 3.0
        x = t * 2.4
        y = 0.55 * t * t
        secs.append([Vector((x, y - 0.3, 0.75)), Vector((x, y - 0.3 + 0.1, 1.25)), Vector((x, y - 0.3, 2.15)), Vector((x, y - 0.36, 2.15)), Vector((x, y - 0.38, 1.25)), Vector((x, y - 0.36, 0.75))])
    d.loft(secs, "PaintWhite")
    d.tube((0, -0.3, 1.45), (0, -1.5, 1.45), 0.035, "DarkSteel", segs=4)
    d.box((0.25, 0.2, 0.25), loc=(0, -1.55, 1.45), m="PaintRed")
    d.box((0.2, 0.2, 0.2), loc=(0, 0.2, 2.3), m="LightBarRed")
    dish = d.finish("radar_Dish", coll, smooth=30, parent=root, loc=(0, 0, 7.7))
    # keyframed spin (linear, 4 s loop at 24 fps)
    prefs = bpy.context.preferences.edit
    old = prefs.keyframe_new_interpolation_type
    prefs.keyframe_new_interpolation_type = 'LINEAR'
    try:
        dish.rotation_mode = 'XYZ'
        for f, ang in ((1, 0.0), (49, math.pi), (97, math.pi * 2)):
            dish.rotation_euler = (0, 0, ang)
            dish.keyframe_insert("rotation_euler", frame=f)
        if dish.animation_data and dish.animation_data.action:
            dish.animation_data.action.name = "RadarSpin"
    finally:
        prefs.keyframe_new_interpolation_type = old
    return root


def build_all():
    return [stats(build_wheels()), stats(build_radar())]


def export_all():
    return [export("wheels", "vehicles/wheels.glb"), export("radar", "props/radar.glb", anim=True)]
