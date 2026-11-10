"""chr_anims - pose DSL, FK/IK pose toolkit and Action builder for the NEON TIDE humanoid rig.

    import chr_anims as N; importlib.reload(N)
    N.build_all()                  # (re)creates every Action on human_male__rig and stashes it in the NLA
    N.preview("Walk")              # make a clip the rig's active action (QA with `look` mode "frames")
    N.preview(None)                # back to the rest pose

Pose DSL (spec section 4)
-------------------------
    clip(name, length, {frame: {bone: (rx, ry, rz) degrees, "Hips@loc": (dx, dy, dz)}}, loop=True)

  * rotations are bone-local XYZ eulers (rotation_mode 'XYZ').  Because every bone's rest axes are
    X = right, Y = up, Z = back:  +X swings a hanging limb forward / bends the elbow, -X bends the knee and
    leans the spine forward, +Y turns left, +Z swings a hanging limb to the character's right.
  * "Hips@loc" is the Hips offset from rest in ASSET axes (dx right, dy forward, dz up), metres.
  * every key is a complete pose (bones that are not mentioned are at rest), looping clips get
    first key == last key and cyclic F-curves, one-shots hold their last frame.
  * mirror(pose) swaps L/R.  The clip library itself lives in chr_clips.py (define_all() below loads it).

Pose toolkit
------------
Poses are plain dicts.  fk(pose) evaluates the skeleton in asset space; the helpers solve limbs
analytically so feet stay planted and hands / held items end up where a clip needs them:
    plant(p, side, x, y, lift, pitch, yaw)     foot on (or above) the ground, knee solved
    leg_to(p, side, ankle, ...)                ankle to a point (airborne / seated poses)
    hand_to(p, side, wrist, elbow, rot)        wrist to a point, optional world hand rotation
    hold(p, side, pos, fwd, up, grip)          Prop socket (held item frame) to a world pose
    ground(p)                                  drop / lift the Hips so the lowest body vertex touches z = 0
"""
import bpy
import math
from math import radians, degrees, sin, cos, pi
import numpy as np
from mathutils import Vector, Matrix, Euler
import gta_kit as K
import chr_rig as R

FPS = 30
RIG_ASSET = "human_male"
BONES = R.BONE_NAMES
LOC = "Hips@loc"

# bone-local axes -> asset axes (columns X=(1,0,0), Y=(0,0,1), Z=(0,-1,0))
B3 = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))
B3T = B3.transposed()
I3 = Matrix.Identity(3)


# --------------------------------------------------------------------------- rotations
def rot(rx=0.0, ry=0.0, rz=0.0):
    """Asset-space matrix of a bone-local XYZ euler (degrees)."""
    return B3 @ Euler((radians(rx), radians(ry), radians(rz)), "XYZ").to_matrix() @ B3T


def to_euler(A, compat=None):
    """Asset-space rotation matrix -> bone-local XYZ euler (degrees), closest to `compat` if given."""
    rl = B3T @ A @ B3
    if compat is not None:
        e = rl.to_euler("XYZ", Euler([radians(a) for a in compat], "XYZ"))
    else:
        e = rl.to_euler("XYZ")
    return (degrees(e.x), degrees(e.y), degrees(e.z))


def _unit(v):
    v = Vector(v)
    if v.length < 1e-9:
        return Vector((0.0, 0.0, 1.0))
    return v.normalized()


def frame(fwd, up):
    """Rotation whose +Y (asset forward) points along fwd and +Z along up (orthonormalised)."""
    f = _unit(fwd)
    u = Vector(up)
    u = u - f * u.dot(f)
    if u.length < 1e-6:
        u = Vector((0.0, 0.0, 1.0)) - f * f.z
        if u.length < 1e-6:
            u = Vector((0.0, -1.0, 0.0))
    u.normalize()
    r = f.cross(u)
    return Matrix((r, f, u)).transposed()


def hand_rot(side, fingers, palm):
    """World rotation of a hand from the direction its fingers point and the direction its palm faces.
    (rest: fingers down, palm toward the body, thumb forward)"""
    s = 1.0 if side == "R" else -1.0
    f = _unit(fingers)
    n = Vector(palm)
    n = n - f * n.dot(f)
    if n.length < 1e-6:
        n = Vector((-s, 0.0, 0.0)) - f * (-s * f.x)
    n.normalize()
    cx = -s * n                    # image of +X
    cz = -f                        # image of +Z
    cy = cz.cross(cx)              # image of +Y (thumb direction)
    return Matrix((cx, cy, cz)).transposed()


# held-item grips: socket rotation relative to the hand (asset-space local matrix)
GRIP_GUN = rot(-90.0, 0.0, 0.0)        # barrel along the fingers, top toward the thumb
GRIP_HAMMER = rot(0.0, 0.0, 0.0)       # item axis along the thumb (bats, knives): the rest orientation
GRIPS = {"gun": GRIP_GUN, "hammer": GRIP_HAMMER}


# --------------------------------------------------------------------------- pose helpers
def P(base=None, loc=None, **bones):
    """New pose dict: copy of `base` updated with bone eulers; loc = Hips offset (asset axes)."""
    p = dict(base) if base else {}
    for k, v in bones.items():
        p[k] = tuple(float(a) for a in v)
    if loc is not None:
        p[LOC] = tuple(float(a) for a in loc)
    return p


def mirror(pose):
    out = {}
    for k, v in pose.items():
        if k == LOC:
            out[k] = (-v[0], v[1], v[2])
        else:
            out[R.mirror_name(k)] = (v[0], -v[1], -v[2])
    return out


def mix(a, b, t):
    """Component-wise blend of two poses (euler space)."""
    out = {}
    for k in set(a) | set(b):
        va = a.get(k, (0.0, 0.0, 0.0))
        vb = b.get(k, (0.0, 0.0, 0.0))
        out[k] = tuple(va[i] + (vb[i] - va[i]) * t for i in range(3))
    return out


def add(pose, **bones):
    """Add euler offsets to bones of a pose (in place), e.g. add(p, Spine=(-5, 0, 0))."""
    for k, v in bones.items():
        o = pose.get(k, (0.0, 0.0, 0.0))
        pose[k] = (o[0] + v[0], o[1] + v[1], o[2] + v[2])
    return pose


def move(pose, dx=0.0, dy=0.0, dz=0.0):
    o = pose.get(LOC, (0.0, 0.0, 0.0))
    pose[LOC] = (o[0] + dx, o[1] + dy, o[2] + dz)
    return pose


# --------------------------------------------------------------------------- scalar animation helpers
def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    if isinstance(a, (tuple, list)):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))
    return a + (b - a) * t


def kf(t, keys, ease=True):
    """Value at t of scalar / tuple keys {time: value}; smoothstep (ease in/out) between keys."""
    ks = sorted(keys)
    if t <= ks[0]:
        return keys[ks[0]]
    if t >= ks[-1]:
        return keys[ks[-1]]
    for a, b in zip(ks, ks[1:]):
        if a <= t <= b:
            u = (t - a) / (b - a)
            return lerp(keys[a], keys[b], smooth(u) if ease else u)
    return keys[ks[-1]]


def spline(t, keys, period=None):
    """Catmull-Rom through scalar / tuple keys {time: value}; period = cycle length for closed curves."""
    ks = sorted(keys)
    n = len(ks)

    def val(i):
        if period is not None:
            return keys[ks[i % n]]
        return keys[ks[max(0, min(n - 1, i))]]

    def tim(i):
        if period is not None:
            return ks[i % n] + period * (i // n)
        return ks[max(0, min(n - 1, i))]

    if period is not None:
        t = ks[0] + (t - ks[0]) % period
        idx = n - 1
        for i in range(n):
            if tim(i) <= t < tim(i + 1):
                idx = i
                break
    else:
        if t <= ks[0]:
            return keys[ks[0]]
        if t >= ks[-1]:
            return keys[ks[-1]]
        idx = 0
        for i in range(n - 1):
            if ks[i] <= t <= ks[i + 1]:
                idx = i
                break
    t0, t1 = tim(idx), tim(idx + 1)
    u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
    p0, p1, p2, p3 = val(idx - 1), val(idx), val(idx + 1), val(idx + 2)

    def cr(a, b, c, d):
        return 0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u * u
                      + (-a + 3.0 * b - 3.0 * c + d) * u * u * u)

    if isinstance(p1, (tuple, list)):
        return tuple(cr(p0[i], p1[i], p2[i], p3[i]) for i in range(len(p1)))
    return cr(p0, p1, p2, p3)


def wave(t, period, amp=1.0, phase=0.0):
    return amp * sin(2.0 * pi * (t / period + phase))


# --------------------------------------------------------------------------- forward kinematics
REST = R.HEAD
PARENT = R.PARENT


def fk(pose):
    """-> {bone: (W 3x3 world rotation, p world head position)} in asset space."""
    out = {}
    for b in BONES:
        par = PARENT[b]
        e = pose.get(b)
        A = rot(*e) if e else I3.copy()
        if par is None:
            W = A
            p = REST[b] + Vector(pose.get(LOC, (0.0, 0.0, 0.0)))
        else:
            Wp, pp = out[par]
            W = Wp @ A
            p = pp + Wp @ (REST[b] - REST[par])
        out[b] = (W, p)
    return out


def chain(pose, bone):
    """World rotation + head position of one bone (walks up the parents only)."""
    names = []
    b = bone
    while b is not None:
        names.append(b)
        b = PARENT[b]
    W = None
    p = None
    for b in reversed(names):
        e = pose.get(b)
        A = rot(*e) if e else I3.copy()
        if W is None:
            W = A
            p = REST[b] + Vector(pose.get(LOC, (0.0, 0.0, 0.0)))
        else:
            p = p + W @ (REST[b] - REST[PARENT[b]])
            W = W @ A
    return W, p


def world_rot(pose, bone, W_target, compat=None):
    """Set bone's euler so that its WORLD rotation equals W_target (matrix or euler tuple in world axes)."""
    if not isinstance(W_target, Matrix):
        W_target = rot(*W_target)
    par = PARENT[bone]
    if par is None:
        A = W_target
    else:
        Wp, _pp = chain(pose, par)
        A = Wp.transposed() @ W_target
    pose[bone] = to_euler(A, compat if compat is not None else pose.get(bone))
    return pose


def level_head(pose, pitch=0.0, yaw=0.0, roll=0.0, share=0.5):
    """Keep the head looking at (pitch, yaw, roll) in WORLD axes whatever the torso does; the correction is
    shared between Neck and Head (share = fraction taken by the neck)."""
    Wc, _ = chain(pose, "Chest")
    A = Wc.transposed() @ rot(pitch, yaw, roll)
    e = to_euler(A)
    pose["Neck"] = (e[0] * share, e[1] * share, e[2] * share)
    world_rot(pose, "Head", rot(pitch, yaw, roll))
    return pose


# --------------------------------------------------------------------------- two-bone IK
def _two_bone(Wp, p_root, e, f, target, pole, sign, max_bend=155.0):
    """Analytic IK. e / f = rest vectors root->mid, mid->end; the lower bone bends about X by sign*|phi|.
    pole = direction (parent frame) the mid joint should point to. -> (A_upper, phi_degrees)."""
    t = Wp.transposed() @ (Vector(target) - p_root)
    d = t.length
    a = e.y * f.y + e.z * f.z
    base = e.length_squared + f.length_squared + 2.0 * e.x * f.x
    c = (d * d - base) / (2.0 * a)
    c_min = cos(radians(max_bend))
    c = max(c_min, min(1.0, c))
    phi = sign * math.acos(c)
    Rb = rot(degrees(phi), 0.0, 0.0)
    v = e + Rb @ f
    vn = v.normalized()
    pe = e - vn * e.dot(vn)
    if pe.length < 1e-5:
        pe = Vector((0.0, -sign, 0.0))
        pe = pe - vn * pe.dot(vn)
    pe.normalize()
    tn = t.normalized() if d > 1e-6 else vn
    q = Vector(pole)
    q = q - tn * q.dot(tn)
    if q.length < 1e-5:
        q = pe - tn * pe.dot(tn)
        if q.length < 1e-5:
            q = Vector((1.0, 0.0, 0.0)) - tn * tn.x
    q.normalize()
    f_rest = Matrix((vn, pe, vn.cross(pe))).transposed()
    f_tgt = Matrix((tn, q, tn.cross(q))).transposed()
    return f_tgt @ f_rest.transposed(), degrees(phi)


def _side(side):
    return ("_" + side), (1.0 if side == "R" else -1.0)


def leg_to(pose, side, ankle, foot=None, knee=(0.0, 1.0, 0.0), knee_world=False):
    """Solve UpperLeg/LowerLeg so the ankle reaches `ankle` (asset space). knee = direction the knee points
    (Hips frame unless knee_world). foot = world rotation of the foot (matrix / euler tuple) or None (keep)."""
    sfx, s = _side(side)
    up, lo, ft = "UpperLeg" + sfx, "LowerLeg" + sfx, "Foot" + sfx
    Wh, ph = chain(pose, "Hips")
    p_root = ph + Wh @ (REST[up] - REST["Hips"])
    e = REST[lo] - REST[up]
    f = REST[ft] - REST[lo]
    pole = Vector(knee)
    if knee_world:
        pole = Wh.transposed() @ pole
    A, phi = _two_bone(Wh, p_root, e, f, ankle, pole, -1.0)
    pose[up] = to_euler(A, pose.get(up))
    pose[lo] = (phi, 0.0, 0.0)
    if foot is not None:
        world_rot(pose, ft, foot)
    return pose


def hand_to(pose, side, wrist, elbow=None, hand=None, elbow_world=True):
    """Solve UpperArm/LowerArm so the wrist reaches `wrist` (asset space). elbow = direction the elbow points
    (world unless elbow_world=False -> Chest frame). hand = world rotation of the hand (matrix / euler) or None."""
    sfx, s = _side(side)
    up, lo, hd = "UpperArm" + sfx, "LowerArm" + sfx, "Hand" + sfx
    Wc, pc = chain(pose, "Chest")
    p_root = pc + Wc @ (REST[up] - REST["Chest"])
    e = REST[lo] - REST[up]
    f = REST[hd] - REST[lo]
    if elbow is None:
        elbow = (0.55 * s, -0.6, -0.6)
    pole = Vector(elbow)
    if elbow_world:
        pole = Wc.transposed() @ pole
    A, phi = _two_bone(Wc, p_root, e, f, wrist, pole, 1.0)
    pose[up] = to_euler(A, pose.get(up))
    pose[lo] = (phi, 0.0, 0.0)
    if hand is not None:
        world_rot(pose, hd, hand)
    return pose


def hand_reach(pose, side, palm_pos, fingers, palm, elbow=None):
    """Place the PALM CENTRE (socket position) at palm_pos with the hand oriented by fingers / palm dirs."""
    sfx, s = _side(side)
    Wh = hand_rot(side, fingers, palm)
    d = REST["Prop" + sfx] - REST["Hand" + sfx]
    wrist = Vector(palm_pos) - Wh @ d
    return hand_to(pose, side, wrist, elbow=elbow, hand=Wh)


def hold(pose, side, pos, fwd=(0.0, 1.0, 0.0), up=(0.0, 0.0, 1.0), grip="gun", elbow=None, hand=None):
    """Put the Prop socket (held item frame: +Y asset = item forward, +Z = item top) at `pos` with the item
    pointing along fwd. grip = 'gun' | 'hammer' | matrix (socket rotation relative to the hand);
    hand = explicit world hand rotation (then the socket rotation is whatever is needed)."""
    sfx, s = _side(side)
    Wp = frame(fwd, up)
    G = GRIPS[grip] if isinstance(grip, str) else grip
    Wh = hand if hand is not None else Wp @ G.transposed()
    if not isinstance(Wh, Matrix):
        Wh = rot(*Wh)
    d = REST["Prop" + sfx] - REST["Hand" + sfx]
    wrist = Vector(pos) - Wh @ d
    hand_to(pose, side, wrist, elbow=elbow, hand=Wh)
    world_rot(pose, "Prop" + sfx, Wp)
    return pose


def socket(pose, side, grip="gun"):
    """Set only the socket's local rotation (item orientation relative to the hand)."""
    G = GRIPS[grip] if isinstance(grip, str) else grip
    pose["Prop_" + side] = to_euler(G)
    return pose


def prop_pose(pose, side):
    """World rotation + position of the socket (debug / QA)."""
    return chain(pose, "Prop_" + side)


# --------------------------------------------------------------------------- body cloud (grounding / QA)
_CLOUD = {}


def load_body(asset_id=RIG_ASSET):
    """Per-bone rest vertex clouds of the body mesh (numpy), relative to the bone head."""
    _CLOUD.clear()
    obj = bpy.data.objects.get(asset_id + "__body")
    if obj is None:
        return False
    names = {g.index: g.name for g in obj.vertex_groups}
    per = {}
    for v in obj.data.vertices:
        if not v.groups:
            continue
        bn = names[v.groups[0].group]
        per.setdefault(bn, []).append((v.co.x, v.co.y, v.co.z))
    for bn, pts in per.items():
        h = REST[bn]
        _CLOUD[bn] = np.array(pts, dtype=np.float64) - np.array((h.x, h.y, h.z))
    return True


def _np(W):
    return np.array([[W[i][j] for j in range(3)] for i in range(3)])


def min_z(pose, bones=None):
    """Lowest body vertex (asset z) under a pose -> (z, bone)."""
    if not _CLOUD:
        load_body()
    st = fk(pose)
    best = (1e9, None)
    for bn, cloud in _CLOUD.items():
        if bones is not None and bn not in bones:
            continue
        W, p = st[bn]
        z = float((cloud @ np.array((W[2][0], W[2][1], W[2][2]))).min()) + p.z
        if z < best[0]:
            best = (z, bn)
    return best


def ground(pose, clearance=0.0, bones=None, only_up=False):
    """Shift the Hips vertically so that the lowest body vertex sits at z = clearance."""
    z, _bn = min_z(pose, bones)
    dz = clearance - z
    if only_up and dz < 0.0:
        return pose
    return move(pose, dz=dz)


def foot_height(W_foot, side="R"):
    """Ankle height above the ground for a foot with world rotation W_foot touching the ground."""
    if not _CLOUD:
        load_body()
    cloud = _CLOUD.get("Foot_" + side)
    if cloud is None:
        return 0.09
    row = np.array((W_foot[2][0], W_foot[2][1], W_foot[2][2]))
    return -float((cloud @ row).min())


def foot_rot(pitch=0.0, yaw=0.0, roll=0.0):
    """World rotation of a foot: pitch > 0 toes up, yaw > 0 turned to the character's left."""
    return rot(0.0, yaw, 0.0) @ rot(pitch, 0.0, roll)


def plant(pose, side, x, y, lift=0.0, pitch=0.0, yaw=0.0, roll=0.0, knee=(0.0, 1.0, 0.0), knee_world=False):
    """Foot at ankle (x, y), resting on the ground (+ lift), with the given world pitch / yaw / roll."""
    Wf = foot_rot(pitch, yaw, roll)
    h = foot_height(Wf, side)
    return leg_to(pose, side, (x, y, h + lift), foot=Wf, knee=knee, knee_world=knee_world)


def flat_foot(pose, side, pitch=0.0, yaw=0.0, roll=0.0):
    """Only orient the foot in world space (leg angles untouched)."""
    return world_rot(pose, "Foot_" + side, foot_rot(pitch, yaw, roll))


# --------------------------------------------------------------------------- clip registry (the DSL)
CLIPS = {}


def clip(name, length, frames, loop=True, **meta):
    """Register a clip. frames = {frame: pose dict}. Looping clips get frame `length` == frame 0."""
    keys = {}
    for fr in sorted(frames):
        keys[int(fr)] = dict(frames[fr])
    if 0 not in keys:
        raise ValueError("%s: no key at frame 0" % name)
    if loop:
        keys[int(length)] = dict(keys[0])
    elif int(length) not in keys:
        keys[int(length)] = dict(keys[max(keys)])
    # euler continuity: every key expressed as close as possible to the previous one
    prev = None
    for fr in sorted(keys):
        pose = keys[fr]
        for b in BONES:
            e = pose.get(b, (0.0, 0.0, 0.0))
            if prev is not None:
                pe = prev[b]
                e = tuple(e[i] + 360.0 * round((pe[i] - e[i]) / 360.0) for i in range(3))
                if max(abs(e[i] - pe[i]) for i in range(3)) > 150.0:
                    e2 = to_euler(rot(*e), pe)
                    if sum(abs(e2[i] - pe[i]) for i in range(3)) < sum(abs(e[i] - pe[i]) for i in range(3)):
                        e = e2
            pose[b] = e
        pose.setdefault(LOC, (0.0, 0.0, 0.0))
        prev = pose
    _keep_tracks(keys)
    CLIPS[name] = dict(name=name, length=int(length), loop=bool(loop), keys=keys, meta=meta)
    return CLIPS[name]


KEEP_DEG = 0.08          # imperceptible offsets that keep a track from being "identical to the rest pose"
KEEP_LOC = 0.0003


def _keep_tracks(keys):
    """Godot imports the GLB with `animation/remove_immutable_tracks` (tracks that equal the rest pose are
    dropped) and an AnimationPlayer leaves a bone WITHOUT a track at whatever the previous clip did.  So every
    bone must own a rotation track (and the Hips a position track) in every clip: a bone that would sit exactly
    at rest for a whole clip gets a constant 0.08 degree offset, a resting Hips 0.3 mm."""
    for b in BONES:
        if max(abs(a) for pose in keys.values() for a in pose[b]) < 0.05:
            for pose in keys.values():
                pose[b] = (KEEP_DEG, 0.0, 0.0)
    if max(abs(a) for pose in keys.values() for a in pose[LOC]) < 1e-4:
        for pose in keys.values():
            pose[LOC] = (0.0, 0.0, KEEP_LOC)


def bake(fn, length, step=2, loop=True):
    """Sample a pose function fn(frame) -> pose every `step` frames (dense keys for IK-driven motion)."""
    frames = {}
    fr = 0
    while fr < length:
        frames[fr] = fn(float(fr))
        fr += step
    if not loop:
        frames[length] = fn(float(length))
    return frames


def sample(name, fr):
    """Pose of a registered clip at a (possibly fractional) frame - linear between keys (QA only)."""
    c = CLIPS[name]
    ks = sorted(c["keys"])
    if fr <= ks[0]:
        return dict(c["keys"][ks[0]])
    if fr >= ks[-1]:
        return dict(c["keys"][ks[-1]])
    for a, b in zip(ks, ks[1:]):
        if a <= fr <= b:
            return mix(c["keys"][a], c["keys"][b], (fr - a) / float(b - a))
    return dict(c["keys"][ks[-1]])


# --------------------------------------------------------------------------- Blender actions
def _get_rig():
    rig = R.get_rig(RIG_ASSET)
    if rig is None:
        raise RuntimeError("human_male__rig is missing - build the bodies first")
    return rig


def _remove_action(name):
    act = bpy.data.actions.get(name)
    if act is not None:
        bpy.data.actions.remove(act)


def _clear_stash(rig, names=None):
    ad = rig.animation_data
    if ad is None:
        return
    for tr in list(ad.nla_tracks):
        if names is None or tr.name in names:
            ad.nla_tracks.remove(tr)


def make_action(rig, c):
    """Create the Action of one registered clip (layered action API, Blender 4.4+/5.x)."""
    name = c["name"]
    _remove_action(name)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = act.slots.new(id_type="OBJECT", name=rig.name)
    layer = act.layers.new("Layer")
    strip = layer.strips.new(type="KEYFRAME")
    bag = strip.channelbag(slot, ensure=True)
    keys = c["keys"]
    frs = sorted(keys)
    n = len(frs)

    def curve(path, idx, group, values):
        try:
            fc = bag.fcurves.new(path, index=idx, group_name=group)
        except TypeError:
            fc = bag.fcurves.new(path, index=idx)
        fc.keyframe_points.add(n)
        co = [0.0] * (2 * n)
        for i, fr in enumerate(frs):
            co[2 * i] = float(fr)
            co[2 * i + 1] = values[i]
        fc.keyframe_points.foreach_set("co", co)
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
        if c["loop"]:
            m = fc.modifiers.new("CYCLES")
            m.mode_before = "REPEAT_OFFSET"
            m.mode_after = "REPEAT_OFFSET"
        else:
            fc.extrapolation = "CONSTANT"
        fc.update()
        return fc

    for b in BONES:
        path = 'pose.bones["%s"].rotation_euler' % b
        for i in range(3):
            curve(path, i, b, [radians(keys[fr][b][i]) for fr in frs])
    path = 'pose.bones["Hips"].location'
    # asset (dx, dy, dz) -> bone-local (dx, dz, -dy)
    curve(path, 0, "Hips", [keys[fr][LOC][0] for fr in frs])
    curve(path, 1, "Hips", [keys[fr][LOC][2] for fr in frs])
    curve(path, 2, "Hips", [-keys[fr][LOC][1] for fr in frs])
    act.use_frame_range = True
    act.frame_start = 0.0
    act.frame_end = float(c["length"])
    try:
        act.use_cyclic = bool(c["loop"])
    except Exception:
        pass
    act["gta_loop"] = bool(c["loop"])
    return act, slot


def stash(rig, act):
    """One muted NLA track per action (single strip) so that the glTF exporter writes every clip."""
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        if tr.name == act.name:
            ad.nla_tracks.remove(tr)
    tr = ad.nla_tracks.new()
    tr.name = act.name
    st = tr.strips.new(act.name, 0, act)
    st.name = act.name
    try:
        if st.action_slot is None and len(act.slots):
            st.action_slot = act.slots[0]
    except Exception:
        pass
    tr.mute = True
    return tr


def preview(name=None, rig=None):
    """Make a clip the rig's active action (None = rest pose). Returns (start, end) frames."""
    rig = rig or _get_rig()
    ad = rig.animation_data or rig.animation_data_create()
    if name is None:
        ad.action = None
        R.reset_pose(rig)
        bpy.context.view_layer.update()
        return None
    act = bpy.data.actions[name]
    R.reset_pose(rig)
    ad.action = act
    try:
        ad.action_slot = act.slots[0]
    except Exception:
        pass
    bpy.context.view_layer.update()
    return (int(act.frame_start), int(act.frame_end))


def preview_poses(poses, name="_chr_review"):
    """QA: temp action with one constant key per pose (frame i = pose i); look at it with mode 'frames'."""
    rig = _get_rig()
    frames = {i: dict(p) for i, p in enumerate(poses)}
    c = clip(name, max(1, len(poses) - 1), frames, loop=False)
    del CLIPS[name]
    act, slot = make_action(rig, c)
    act.use_fake_user = False
    for b in act.layers[0].strips[0].channelbag(slot).fcurves:
        for kp in b.keyframe_points:
            kp.interpolation = "CONSTANT"
    ad = rig.animation_data or rig.animation_data_create()
    R.reset_pose(rig)
    ad.action = act
    ad.action_slot = slot
    bpy.context.view_layer.update()
    return len(poses)


def end_review(name="_chr_review"):
    preview(None)
    _remove_action(name)


def build_actions(names=None):
    """(Re)create Actions + NLA stash for the registered clips (all, or the given names)."""
    rig = _get_rig()
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = None
    out = []
    for name, c in CLIPS.items():
        if names is not None and name not in names:
            continue
        act, _slot = make_action(rig, c)
        stash(rig, act)
        out.append((name, c["length"], c["loop"]))
    R.reset_pose(rig)
    return out


def define_all():
    """Register every clip of the library. The clip data lives in chr_clips.py (built on this toolkit)."""
    import importlib
    import chr_clips
    importlib.reload(chr_clips)
    chr_clips.define_all()
    return chr_clips


def build_all(names=None):
    """Define every clip (define_all below) and build the Actions on human_male__rig."""
    load_body()
    CLIPS.clear()
    define_all()
    rig = _get_rig()
    if names is None:
        # drop stale stash tracks of clips that no longer exist
        ad = rig.animation_data
        if ad is not None:
            for tr in list(ad.nla_tracks):
                if tr.name not in CLIPS:
                    ad.nla_tracks.remove(tr)
    return build_actions(names)


def clip_list():
    return [{"name": n, "length": c["length"], "loop": c["loop"]} for n, c in CLIPS.items()]


def qa_report(names=None, step=2):
    """Lowest body point of every clip over time -> [(name, min z, frame, bone, max z of lowest point)]."""
    out = []
    for name, c in CLIPS.items():
        if names is not None and name not in names:
            continue
        lo = (1e9, 0, None)
        hi = -1e9
        fr = 0
        while fr <= c["length"]:
            z, bn = min_z(sample(name, fr))
            if z < lo[0]:
                lo = (z, fr, bn)
            hi = max(hi, z)
            fr += step
        out.append((name, round(lo[0], 3), lo[1], lo[2], round(hi, 3)))
    return out
