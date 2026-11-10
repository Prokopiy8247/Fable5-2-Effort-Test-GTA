"""car_refine - critic pass for kit cars (art critic of set cars_a; car_kit.py itself is NOT edited).

`Refined(K.Car)` wraps single build steps of the kit and adds what the in-engine screenshots showed
to be missing (first-person camera + glass you can look through):

  * headliner pass   the roof underside and every pillar face that looks INTO the cabin get
                     M_Interior instead of body paint (the kit paints roof slab and pillars on all
                     sides, so the first-person camera sat under a bright body-coloured ceiling and
                     the far-side pillars shone through the glass in paint colour)
  * dash details     gauge panel with two chrome dials under the binnacle, air vents, radio face,
                     glovebox line, defroster slot, rear-view mirror on the windshield header
  * seat()           same seats as the kit, but a head rest is lowered (or dropped) when it would
                     poke through the rear glass (it did on the sedan)
  * lod()            dark cabin floor inside Body_LOD1 so the LOD shell is not see-through hollow

Use it exactly like K.Car:

    import car_kit as K, car_refine as R
    car = R.Refined(params, G.slot("cars", 0)); car.build(); car.finish()

cars_a.CarA and cars_sedan.Sedan derive from it.
"""
from math import radians

from mathutils import Vector

import gta_bl as G
import car_kit as K


class Refined(K.Car):
    HEADLINER_DOT = 0.35      # how squarely a face must look at the cabin centre to become interior
    DASH = True               # gauge panel / vents / radio / mirror

    # ---------------------------------------------------------------- headliner
    def cabin_point(self):
        """A point at chest height in the middle of the cabin (car space)."""
        g = self._gh()
        return Vector((0.0, (g["cy"] + g["dy"]) / 2.0, min(g["zc"], g["zd"]) - 0.10))

    def headliner(self, faces, mb=None):
        """Give paint / roof-coloured faces that face the cabin centre the interior material.
        Returns the number of faces changed."""
        mb = mb or self.body
        M = self.M
        src = {mb.mi(M["paint"])}
        rm = self._mat(self.p["roof_mat"])
        if rm in mb.mats:
            src.add(mb.mats.index(rm))
        ii = mb.mi(M["interior"])
        src.discard(ii)
        c0 = self.cabin_point()
        n = 0
        for f in faces:
            if not f.is_valid or f.material_index not in src:
                continue
            f.normal_update()
            v = c0 - f.calc_center_median()
            if v.length < 1e-6:
                continue
            if f.normal.dot(v) / v.length > self.HEADLINER_DOT:
                f.material_index = ii
                n += 1
        return n

    def greenhouse(self):
        before = set(self.body.bm.faces)
        K.Car.greenhouse(self)
        self.headliner([f for f in self.body.bm.faces if f not in before])

    # ---------------------------------------------------------------- seats
    def _headrest_drop(self, y, ct):
        """How far a head rest of the seat at y (cushion top ct) must come down to stay 4.5 cm
        under the rear glass / the roof."""
        g = self._gh()
        dy, rr, zd, zR = g["dy"], g["rr"], g["zd"], g["zR"]
        yh, zh = y - 0.392, ct + 0.712            # top rear corner of the kit head rest
        limit = zR - self.p["roof_t"] - 0.02
        if yh < rr and rr - dy > 0.02:
            limit = min(limit, zd + (zR - zd) * (yh - dy) / (rr - dy) - 0.045)
        return max(0.0, zh - limit)

    def seat(self, x, y, z_hip, width=0.50, headrest=True):
        b, m = self.body, self.M["seat"]
        ct = z_hip - 0.09
        base = self.p["tub_z"] + 0.03
        b.box((width, 0.50, ct - base), (x, y + 0.10, (ct + base) / 2.0), m, bevel=0.025)
        b.box((width, 0.13, 0.62), (x, y - 0.235, ct + 0.24), m, rot=(radians(14), 0, 0), bevel=0.025)
        if not headrest:
            return
        drop = self._headrest_drop(y, ct)
        if drop > 0.13:
            print("car_refine %s: head rest at y=%.2f skipped (rear glass too low)" % (self.name, y))
            return
        if drop > 0.0:
            print("car_refine %s: head rest at y=%.2f lowered by %.3f m (rear glass)" % (self.name, y, drop))
        n = max(1, int(round(width / 0.62)))
        for i in range(n):
            hx = x + (i - (n - 1) / 2.0) * (width / n)
            b.box((0.26, 0.10, 0.18), (hx, y - 0.33, ct + 0.63 - drop), m, rot=(radians(8), 0, 0))

    # ---------------------------------------------------------------- dash + mirror
    def interior(self):
        K.Car.interior(self)
        if self.DASH:
            self.dash_details()
            self.rear_view_mirror()

    def dash_details(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        cy, zc = g["cy"], g["zc"]
        sx = p["seat_x"]
        dw = 2.0 * (self.belt_x(cy) - 0.02) - 0.02
        yd = cy - 0.43                              # dash face that looks at the cabin
        # instrument panel under the binnacle: black panel, two chrome dials, small centre gauge
        b.box((0.30, 0.014, 0.09), (-sx, yd - 0.006, zc - 0.10), M["trim"])
        for dx in (-0.078, 0.078):
            b.cyl(0.038, 0.012, (-sx + dx, yd - 0.016, zc - 0.098), M["chrome"], axis='Y', segments=6)
        # air vents at both ends of the dash, glovebox line, defroster slot on the dash top
        vx = dw / 2.0 - 0.125
        if vx > sx + 0.24:
            b.box((0.12, 0.012, 0.045), (vx, yd - 0.004, zc - 0.095), M["trim"], mirror=True)
        b.box((0.28, 0.008, 0.012), (sx, yd - 0.003, zc - 0.175), M["trim"])
        b.box((dw * 0.62, 0.05, 0.008), (0, cy - 0.09, zc - 0.018), M["trim"])
        # radio face on the centre stack (kit: trim box whose face is at cy - 0.49)
        yr = cy - 0.49
        b.box((0.15, 0.010, 0.036), (0, yr - 0.004, zc - 0.135), M["chrome"])
        b.box((0.10, 0.006, 0.020), (0, yr - 0.010, zc - 0.135), M["under"])

    def rear_view_mirror(self):
        p, M, b = self.p, self.M, self.body
        g = self._gh()
        rf, zR = g["rf"], g["zR"]
        zu = zR - p["roof_t"]                       # underside of the header
        b.box((0.022, 0.022, 0.07), (0, rf + 0.035, zu - 0.025), M["trim"])
        b.box((0.21, 0.030, 0.062), (0, rf + 0.030, zu - 0.075), M["trim"])
        b.box((0.185, 0.006, 0.044), (0, rf + 0.013, zu - 0.075), M["chrome"])

    # ---------------------------------------------------------------- LOD
    def lod(self):
        K.Car.lod(self)
        g = self._gh()
        lb = self.mb("Body_LOD1")
        z0, z1 = g["zd"] - 0.03, g["zc"] - 0.03
        xd, xc, dy, cy = g["xd"] - 0.01, g["xc"] - 0.01, g["dy"] + 0.01, g["cy"] - 0.01
        # M_Trim: already a surface of every LOD shell (rocker band), so no extra draw call
        lb.face([(-xd, dy, z0), (xd, dy, z0), (xc, cy, z1), (-xc, cy, z1)], self.M["trim"], want=(0, 0, 1))


def build_car(params=None, location=(0, 0, 0), collection="Vehicles/Cars", extras=None, cls=Refined):
    """K.build_car with the refined class."""
    car = cls(params, location, collection)
    car.build()
    if extras:
        extras(car)
    car.finish()
    return car


# ------------------------------------------------------------------------------------------------
# QA: look out of the windshield from the driver's eye point (first-person camera check)
# ------------------------------------------------------------------------------------------------
def eye_preview(root_name, out_name, eye=None, look=None, lens=15.0, res=(960, 540)):
    """Workbench render from inside the car.  eye / look are car-local points; default = 0.70 m above
    Seat_Driver looking forward and slightly down.  Everything outside the asset is hidden for the
    render only; all render settings are restored (same rules as G.preview)."""
    import os
    import bpy
    G.object_mode()
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError("eye_preview: no object %r" % root_name)
    scene = bpy.context.scene
    objs = set(G.children_of(root))
    if eye is None:
        sd = bpy.data.objects.get(root_name + K.NAME_SEP + "Seat_Driver")
        base = Vector(sd.location) if sd is not None else Vector((-0.37, 0.0, 0.47))
        eye = base + Vector((0.0, -0.06, 0.70))
    eye = Vector(eye)
    if look is None:
        look = eye + Vector((0.12, 1.0, -0.16))
    look = Vector(look)
    r = scene.render
    sh = scene.display.shading
    saved = dict(engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage, path=r.filepath,
                 fmt=r.image_settings.file_format, cam=scene.camera, transparent=r.film_transparent)
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type",
              "background_color", "cavity_type"):
        try:
            v = getattr(sh, k)
            saved_sh[k] = tuple(v) if k == "background_color" else v
        except Exception:
            pass
    hidden = []
    for o in scene.objects:
        if o not in objs and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    cam_data = bpy.data.cameras.new("_crit_eye_cam")
    cam = bpy.data.objects.new("_crit_eye_cam", cam_data)
    scene.collection.objects.link(cam)
    out_path = os.path.join(G.PREVIEW_DIR, out_name + ".png")
    try:
        r.engine = 'BLENDER_WORKBENCH'
        for k, v in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                     ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                     ("background_color", (0.55, 0.68, 0.80))):
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        r.resolution_x, r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        cam_data.type = 'PERSP'
        cam_data.lens = lens
        cam_data.clip_start = 0.03
        cam_data.clip_end = 200.0
        mw = root.matrix_world
        d = (mw @ look) - (mw @ eye)
        cam.location = mw @ eye
        cam.rotation_euler = (-d.normalized()).to_track_quat('Z', 'Y').to_euler()
        r.filepath = out_path
        bpy.ops.render.render(write_still=True)
    finally:
        for o in hidden:
            try:
                o.hide_render = False
            except Exception:
                pass
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
        scene.camera = saved["cam"]
        try:
            r.engine = saved["engine"]
        except Exception:
            pass
        r.resolution_x, r.resolution_y, r.resolution_percentage = saved["rx"], saved["ry"], saved["pct"]
        r.filepath = saved["path"]
        r.film_transparent = saved["transparent"]
        try:
            r.image_settings.file_format = saved["fmt"]
        except Exception:
            pass
        for k, v in saved_sh.items():
            try:
                setattr(sh, k, v)
            except Exception:
                pass
    print("PREVIEW_SAVED:", out_path)
    return out_path
