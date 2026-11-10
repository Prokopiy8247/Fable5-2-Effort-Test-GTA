"""chr_rig - shared humanoid skeleton + rigid ("action figure") skinning helpers for NEON TIDE.

Executed inside Blender through the MCP (see SPEC_COMMON.md / SPEC_CHARACTERS.md):

    import chr_rig as R; importlib.reload(R)
    root, rig = R.ensure_character("human_male")        # root Empty + armature `<id>__rig`

Skeleton contract (identical for every humanoid):
  * character faces +Y, left side is -X, feet on z = 0, height 1.80
  * EVERY bone points straight up (tail = head + 0.1 z) with roll so that the bone-local axes are
    X = character's right, Y = up, Z = back  ->  joint rest rotations are the identity in glTF / Godot.
  * +X rot: hanging limb swings FORWARD (elbow bend too); -X on LowerLeg bends the knee;
    -X on Spine/Chest/Neck/Head leans forward.  +Y rot: turn to the character's left.
    +Z rot: hanging limb swings toward the character's right.
  * Prop_L / Prop_R: non-deforming attachment sockets in the palm.  They ARE animated by the clips:
    the socket's local -Z is the held item's forward (barrel / blade), +Y its top.
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix
import gta_kit as K

# name, head (x, y, z), parent, deform
BONES = [
    ("Hips", (0.0, 0.0, 0.96), None, True),
    ("Spine", (0.0, 0.0, 1.08), "Hips", True),
    ("Chest", (0.0, 0.0, 1.26), "Spine", True),
    ("Neck", (0.0, 0.0, 1.48), "Chest", True),
    ("Head", (0.0, 0.0, 1.56), "Neck", True),
    ("UpperArm_L", (-0.20, 0.0, 1.43), "Chest", True),
    ("LowerArm_L", (-0.235, 0.0, 1.15), "UpperArm_L", True),
    ("Hand_L", (-0.265, 0.0, 0.89), "LowerArm_L", True),
    ("Prop_L", (-0.275, 0.03, 0.80), "Hand_L", False),
    ("UpperArm_R", (0.20, 0.0, 1.43), "Chest", True),
    ("LowerArm_R", (0.235, 0.0, 1.15), "UpperArm_R", True),
    ("Hand_R", (0.265, 0.0, 0.89), "LowerArm_R", True),
    ("Prop_R", (0.275, 0.03, 0.80), "Hand_R", False),
    ("UpperLeg_L", (-0.095, 0.0, 0.93), "Hips", True),
    ("LowerLeg_L", (-0.095, 0.0, 0.51), "UpperLeg_L", True),
    ("Foot_L", (-0.095, 0.0, 0.09), "LowerLeg_L", True),
    ("UpperLeg_R", (0.095, 0.0, 0.93), "Hips", True),
    ("LowerLeg_R", (0.095, 0.0, 0.51), "UpperLeg_R", True),
    ("Foot_R", (0.095, 0.0, 0.09), "LowerLeg_R", True),
]
BONE_NAMES = [b[0] for b in BONES]
BONE_INDEX = {b[0]: i for i, b in enumerate(BONES)}
HEAD = {b[0]: Vector(b[1]) for b in BONES}
PARENT = {b[0]: b[2] for b in BONES}
DEFORM = {b[0]: b[3] for b in BONES}
BONE_LENGTH = 0.1
ROLL_Z = (0.0, -1.0, 0.0)          # bone-local Z axis = character's back


def J(name):
    """Rest joint position (asset space) as a Vector copy."""
    return HEAD[name].copy()


def mirror_name(name):
    if name.endswith("_L"):
        return name[:-2] + "_R"
    if name.endswith("_R"):
        return name[:-2] + "_L"
    return name


# --------------------------------------------------------------------------- armature
def _remove_object(name):
    o = bpy.data.objects.get(name)
    if o is None:
        return
    data = o.data
    bpy.data.objects.remove(o, do_unlink=True)
    if data is not None and data.users == 0:
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Armature):
            bpy.data.armatures.remove(data)


def build_rig(root):
    """(Re)create the armature object `<root>__rig` as a child of root. Leaves Blender in Object Mode."""
    name = root.name + "__rig"
    _remove_object(name)
    arm = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm)
    for c in root.users_collection:
        c.objects.link(rig)
    rig.parent = root
    vl = bpy.context.view_layer
    vl.update()
    prev_active = vl.objects.active
    prev_sel = [o for o in vl.objects if o.select_get()]
    try:
        for o in prev_sel:
            o.select_set(False)
        rig.select_set(True)
        vl.objects.active = rig
        # the one allowed Edit Mode section: edit bones cannot be created any other way
        bpy.ops.object.mode_set(mode="EDIT")
        try:
            ebs = arm.edit_bones
            for bn, head, parent, deform in BONES:
                eb = ebs.new(bn)
                eb.head = head
                eb.tail = (head[0], head[1], head[2] + BONE_LENGTH)
                eb.use_connect = False
                if parent:
                    eb.parent = ebs[parent]
                eb.align_roll(ROLL_Z)
                eb.use_deform = deform
        finally:
            bpy.ops.object.mode_set(mode="OBJECT")
    finally:
        try:
            rig.select_set(False)
        except Exception:
            pass
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        try:
            vl.objects.active = prev_active
        except Exception:
            pass
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    arm.display_type = "STICK"
    rig.show_in_front = False
    rig["gta_bones"] = ",".join(BONE_NAMES)
    return rig


def get_rig(asset_id):
    return bpy.data.objects.get(asset_id + "__rig")


def ensure_character(asset_id, rebuild=False):
    """Root Empty + rig. rebuild=True recreates the whole asset (body, accessories, NLA stash are lost)."""
    root = bpy.data.objects.get(asset_id)
    rig = get_rig(asset_id)
    if rebuild or root is None or rig is None or rig.parent is not root:
        root = K.begin_asset(asset_id, "Characters")
        rig = build_rig(root)
    return root, rig


def verify_rig(rig, eps=1e-5):
    """-> (ok, report lines). Checks head positions, parents and the X=right / Y=up / Z=back rest axes."""
    ok = True
    lines = []
    want = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))     # columns X=(1,0,0) Y=(0,0,1) Z=(0,-1,0)
    for bn, head, parent, deform in BONES:
        b = rig.data.bones.get(bn)
        if b is None:
            ok = False
            lines.append("MISSING " + bn)
            continue
        m3 = b.matrix_local.to_3x3()
        d_axes = max(abs(m3[i][j] - want[i][j]) for i in range(3) for j in range(3))
        d_head = (b.head_local - Vector(head)).length
        par = b.parent.name if b.parent else None
        good = d_axes < eps and d_head < eps and par == parent and b.use_deform == deform and not b.use_connect
        ok = ok and good
        lines.append("%-11s head=(%.3f, %.3f, %.3f) parent=%-11s axes_err=%.1e %s" % (
            bn, b.head_local.x, b.head_local.y, b.head_local.z, par, d_axes, "OK" if good else "BAD"))
    return ok, lines


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def set_pose(rig, pose):
    """Debug helper: apply {bone: (rx, ry, rz) deg, 'Hips@loc': (dx, dy, dz) asset axes} to the rig."""
    reset_pose(rig)
    for key, val in pose.items():
        if key == "Hips@loc":
            rig.pose.bones["Hips"].location = (val[0], val[2], -val[1])
        else:
            rig.pose.bones[key].rotation_euler = [math.radians(a) for a in val]
    bpy.context.view_layer.update()


# --------------------------------------------------------------------------- skinned mesh builder
class SkinMB(K.MB):
    """K.MB that remembers which bone every vertex was created for (rigid 100 % skinning).

        mb = SkinMB()
        mb.bone("UpperArm_R"); mb.loft(...)      # everything built from here on belongs to UpperArm_R
        mb.bone("LowerArm_R"); ...
        mb.mirror_skin()                          # mirror across X, swapping _L/_R bones
        mb.bone("Chest"); ...
        obj = mb.to_skinned(root, rig, "body", sharp_angle=50)
    """
    LAYER = "gta_bone_id"

    def __init__(self):
        super().__init__()
        self.wl = self.bm.verts.layers.int.new(self.LAYER)
        self._cur = 0

    def bone(self, name):
        self._flush()
        self._cur = BONE_INDEX[name] + 1
        return self

    def _flush(self):
        if not self._cur:
            return
        wl = self.wl
        cur = self._cur
        for v in self.bm.verts:
            if v[wl] == 0:
                v[wl] = cur

    def mirror_skin(self):
        """Duplicate everything mirrored across the YZ plane; mirrored verts go to the opposite-side bone."""
        self._flush()
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        ret = bmesh.ops.duplicate(self.bm, geom=geom)
        new_verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
        new_faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
        wl = self.wl
        swap = {BONE_INDEX[n] + 1: BONE_INDEX[mirror_name(n)] + 1 for n in BONE_NAMES}
        for v in new_verts:
            v.co.x = -v.co.x
            v[wl] = swap.get(v[wl], v[wl])
        bmesh.ops.reverse_faces(self.bm, faces=new_faces)
        return new_faces

    def repaint(self, faces, color, pred):
        """Repaint the faces whose centre satisfies pred(Vector) -> bool."""
        hit = [f for f in faces if f.is_valid and pred(f.calc_center_median())]
        self.paint(hit, color)
        return hit

    def to_skinned(self, root, rig, part, sharp_angle=50.0):
        self._flush()
        obj = self.to_object(root, part, sharp_angle=sharp_angle)
        return skin_object(obj, rig, self.LAYER)


def skin_object(obj, rig, layer_name):
    """Vertex groups from the int vertex attribute `layer_name` (bone index + 1), Armature modifier, parent."""
    mesh = obj.data
    attr = mesh.attributes.get(layer_name)
    ids = [d.value for d in attr.data]
    mesh.attributes.remove(attr)
    per = {}
    for vi, bid in enumerate(ids):
        if bid <= 0:
            raise RuntimeError("%s: vertex %d has no bone" % (obj.name, vi))
        per.setdefault(bid - 1, []).append(vi)
    for bi in sorted(per):
        vg = obj.vertex_groups.new(name=BONE_NAMES[bi])
        vg.add(per[bi], 1.0, "REPLACE")
    for m in list(obj.modifiers):
        obj.modifiers.remove(m)
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    mod.use_vertex_groups = True
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj["gta_bones_used"] = ",".join(BONE_NAMES[bi] for bi in sorted(per))
    return obj


def remove_part(asset_id, part):
    _remove_object("%s__%s" % (asset_id, part))


# --------------------------------------------------------------------------- shape helpers
def _sgn_pow(v, e):
    return math.copysign(abs(v) ** e, v)


def sring(cx, cy, z, rx, ryf, ryb=None, n=10, p=2.0, phase=None, tilt=0.0):
    """Horizontal super-ellipse ring (CCW seen from above). ryf / ryb = front (+Y) / back half depth,
    p = 2 ellipse .. 4 rounded box. tilt (m): front edge raised / back lowered by tilt (sloped ring)."""
    if ryb is None:
        ryb = ryf
    if phase is None:
        phase = math.pi / n
    e = 2.0 / p
    pts = []
    for k in range(n):
        a = phase + 2.0 * math.pi * k / n
        c = _sgn_pow(math.cos(a), e)
        s = _sgn_pow(math.sin(a), e)
        y = s * (ryf if s >= 0.0 else ryb)
        dz = tilt * (s if s >= 0.0 else s)
        pts.append((cx + c * rx, cy + y, z + dz))
    return pts


def oring(c, axis, rs, rf, rb=None, n=8, p=2.0, phase=None, ref=(0.0, 1.0, 0.0), offs=(0.0, 0.0)):
    """Ring perpendicular to `axis` at centre c. Local frame: front f = `ref` projected, side s = axis x f
    (for a limb hanging down, s = +X and f = +Y). rs = side radius, rf / rb = front / back radius.
    offs = (side, front) shift of the centre."""
    if rb is None:
        rb = rf
    if phase is None:
        phase = math.pi / n
    d = Vector(axis).normalized()
    f = Vector(ref)
    f = f - d * f.dot(d)
    if f.length < 1e-6:
        f = Vector((0.0, 0.0, 1.0)) - d * d.z
    f.normalize()
    s = d.cross(f)
    cc = Vector(c) + s * offs[0] + f * offs[1]
    e = 2.0 / p
    pts = []
    for k in range(n):
        a = phase + 2.0 * math.pi * k / n
        cs = _sgn_pow(math.cos(a), e)
        sn = _sgn_pow(math.sin(a), e)
        pts.append(tuple(cc + s * (cs * rs) + f * (sn * (rf if sn >= 0.0 else rb))))
    return pts


def limb(mb, p0, p1, stations, color, n=8, p=2.0, ball0=2, ball1=2, ref=(0.0, 1.0, 0.0), ring_colors=None,
         phase=None):
    """Capsule-like closed limb segment from joint p0 to joint p1 (rigid skinning friendly).

    stations: [(t, rs, rf, rb[, side_off, front_off]), ...] with t = 0..1 along p0 -> p1; the first / last
    station define the ball radius at the joints. ball0 / ball1 = number of extra rings forming the rounded
    end beyond the first / last station (0 = flat cap). Returns the faces."""
    p0 = Vector(p0)
    p1 = Vector(p1)
    ax = p1 - p0
    length = ax.length
    d = ax / length
    rings = []

    def st_ring(st, t_abs, scale):
        t, rs, rf, rb = st[0], st[1], st[2], st[3]
        so = st[4] if len(st) > 4 else 0.0
        fo = st[5] if len(st) > 5 else 0.0
        return oring(p0 + d * t_abs, d, rs * scale, rf * scale, rb * scale, n=n, p=p, phase=phase, ref=ref,
                     offs=(so, fo))

    lat = {0: [], 1: [50.0], 2: [65.0, 32.0], 3: [70.0, 45.0, 22.0]}
    first = stations[0]
    r0 = max(first[1], first[2], first[3])
    for ang in lat[ball0]:
        a = math.radians(ang)
        rings.append(st_ring(first, first[0] * length - r0 * math.sin(a), math.cos(a)))
    for st in stations:
        rings.append(st_ring(st, st[0] * length, 1.0))
    last = stations[-1]
    r1 = max(last[1], last[2], last[3])
    for ang in reversed(lat[ball1]):
        a = math.radians(ang)
        rings.append(st_ring(last, last[0] * length + r1 * math.sin(a), math.cos(a)))
    rc = None
    if ring_colors:
        rc = [None] * len(lat[ball0]) + list(ring_colors)
    return mb.loft(rings, color, closed=True, cap_start=True, cap_end=True, ring_colors=rc)


def shell(mb, rings, color, ring_colors=None):
    """Closed loft of horizontal rings (pelvis, chest, head ...)."""
    return mb.loft(rings, color, closed=True, cap_start=True, cap_end=True, ring_colors=ring_colors)


def band(mb, ring_fn, z0, z1, thick, color, n=12, inner=0.0, bevel_top=0.0):
    """Closed band (belt / collar / strap) around a profile. ring_fn(z, grow) -> ring points."""
    r_in0 = ring_fn(z0, -inner)
    r_out0 = ring_fn(z0, thick)
    r_out1 = ring_fn(z1, thick)
    r_in1 = ring_fn(z1, -inner)
    rings = [r_in0, r_out0, r_out1, r_in1]
    return mb.loft(rings, color, closed=True, cap_start=True, cap_end=True)
