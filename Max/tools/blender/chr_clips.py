"""chr_clips - the NEON TIDE humanoid clip library (spec section 4), built on the chr_anims pose toolkit.

    import chr_anims as N; N.build_all()        # -> chr_clips.define_all() -> Actions on human_male__rig

Authoring model
---------------
pose(**params) builds one full pose from readable parameters (Hips offset / torso eulers, feet planted
with IK, free ankles, FK limbs, wrist / palm IK targets, world-levelled head).  Clips are either
  * tracks(name, length, {frame: params})   parameter keys, IK re-solved on every baked frame
  * cyc(name, length, fn)                    fn(frame) -> pose for procedural loops (gaits, breathing)
  * keyed(name, length, {frame: pose})       full poses blended in euler space (falls, get-ups) with a
                                             floor clamp so nothing sinks into the ground
Conventions that the game code relies on (gta/code/player/character_visual.gd):
  * Prop_L / Prop_R keep ONE constant local rotation in every clip (SOCKET: item forward = along the
    fingers / forearm line, item top = thumb side), because upper-body overlays do not carry the sockets.
  * AimPistol / AimRifle / HoldRifle / Reload / Punch / Throw keep the Hips un-rotated at frame 0 so their
    Spine..Hand rotations can be layered over any locomotion clip.
  * all clips are in place; gait clips list their nominal ground speed in SPEED (m/s at 1x).
"""
import math
from math import sin, cos, pi, radians, degrees, sqrt
from mathutils import Vector
import chr_anims as N
import chr_rig as R

LOC = N.LOC
HX = 0.095                               # hip joint / rest ankle half spacing
LEG_MAX = 0.835                          # longest hip -> ankle distance used for planted feet
SOCKET = N.to_euler(N.GRIP_GUN)          # constant local rotation of both Prop sockets
SPEED = {}                               # clip -> nominal ground speed (m/s) of in-place gaits
NOTES = {}                               # clip -> integration note for the manifest
ARM0 = (2.0, 3.0, 8.0, 10.0)             # relaxed hanging arm (flex, out, turn, elbow)
FOOT0 = (0.01, 0.0, 0.0, 0.0, 8.0)       # relaxed planted foot (out, y, lift, pitch, toe-out)


def lerp(a, b, t):
    return a + (b - a) * t


def _s(side):
    return 1.0 if side == "R" else -1.0


# --------------------------------------------------------------------------- pose builder
def _foot_target(side, f):
    s = _s(side)
    out, y, lift, pitch, toe = f
    Wf = N.foot_rot(pitch, -s * toe, 0.0)
    h = N.foot_height(Wf, side)
    return Vector((s * (HX + out), y, h + lift)), Wf, toe


def _fit_hips(p, targets):
    """Lower the Hips until every planted ankle is within reach (keeps feet on the ground)."""
    Wh, ph = N.chain(p, "Hips")
    drop = 0.0
    for side, ank in targets:
        j = ph + Wh @ (R.HEAD["UpperLeg_" + side] - R.HEAD["Hips"])
        d = ank - j
        h2 = d.x * d.x + d.y * d.y
        if d.length > LEG_MAX and h2 < LEG_MAX * LEG_MAX:
            drop = max(drop, (-d.z) - sqrt(LEG_MAX * LEG_MAX - h2))
    if drop > 0.0:
        N.move(p, dz=-drop)
    return drop


def pose(dz=0.0, dx=0.0, dy=0.0, hips=(0, 0, 0), spine=(0, 0, 0), chest=(0, 0, 0),
         head=(0, 0, 0), nk=None,
         fl=FOOT0, fr=FOOT0, ll=None, lr=None, xl=None, xr=None, nl=None, nr=None,
         al=ARM0, ar=ARM0, wl=None, wr=None, el=None, er=None, hl=None, hr=None, gl=None, gr=None,
         pl=None, pr=None, sl=None, sr=None, two=None, fit=True, floor=None, **_ignored):
    """One full pose.
    dz/dx/dy  Hips offset (asset axes);  hips/spine/chest  local eulers (deg)
    head      WORLD (pitch, yaw, roll) of the head;  nk = (neck euler + head euler) local instead
    fl/fr     planted foot (out, y, lift, pitch, toe_out)      [IK, hips auto-lowered to keep reach]
    xl/xr     free ankle (x, y, z, pitch, yaw) + nl/nr knee pole (world)
    ll/lr     FK leg (flex, knee, foot, out, twist_out)
    al/ar     FK arm (flex, out, turn_in, elbow);  hl/hr hand local euler (right-side convention)
    wl/wr     wrist IK target (x, y, z) + el/er elbow pole (world);  gl/gr = fingers dir + palm dir (6)
    pl/pr     palm IK target (needs gl/gr);  sl/sr = held item (x, y, z, fwd3, up3) socket target
    floor     if not None: finally shift the Hips so the lowest vertex sits at this height
    """
    p = {LOC: (dx, dy, dz), "Hips": tuple(hips), "Spine": tuple(spine), "Chest": tuple(chest),
         "Prop_L": SOCKET, "Prop_R": SOCKET}
    # ---- legs
    plan = []
    for side, f, l, x in (("L", fl, ll, xl), ("R", fr, lr, xr)):
        if l is None and x is None and f is not None:
            ank, Wf, toe = _foot_target(side, f)
            plan.append((side, ank, Wf, toe, f[2]))
    if fit and plan:
        _fit_hips(p, [(side, ank) for side, ank, _w, _t, lift in plan if lift < 0.02])
    for side, ank, Wf, toe, _lift in plan:
        s = _s(side)
        a = radians(toe)
        N.leg_to(p, side, ank, foot=Wf, knee=(s * sin(a), cos(a), 0.12), knee_world=True)
    for side, l, x, n in (("L", ll, xl, nl), ("R", lr, xr, nr)):
        s = _s(side)
        if l is not None:
            flex, knee, foot, out, twist = l
            p["UpperLeg_" + side] = (flex, -s * twist, s * out)
            p["LowerLeg_" + side] = (-knee, 0.0, 0.0)
            p["Foot_" + side] = (foot, 0.0, 0.0)
        elif x is not None:
            N.leg_to(p, side, (x[0], x[1], x[2]), foot=N.foot_rot(x[3], x[4], 0.0),
                     knee=n if n is not None else (0.0, 1.0, 0.3), knee_world=True)
    # ---- arms
    if two is not None and sr is not None:           # two-handed item: left hand grips `two` m along it
        f = Vector(sr[3:6]).normalized() * two
        sl = (sr[0] + f.x, sr[1] + f.y, sr[2] + f.z) + tuple(sr[3:9])
    for side, a, w, e, h, g, pm, sk in (("L", al, wl, el, hl, gl, pl, sl), ("R", ar, wr, er, hr, gr, pr, sr)):
        s = _s(side)
        Wh = N.hand_rot(side, g[0:3], g[3:6]) if g is not None else None
        if sk is not None:
            N.hold(p, side, sk[0:3], fwd=sk[3:6], up=sk[6:9], grip="gun", elbow=e)
        elif pm is not None:
            d = R.HEAD["Prop_" + side] - R.HEAD["Hand_" + side]
            N.hand_to(p, side, Vector(pm) - Wh @ d, elbow=e, hand=Wh)
        elif w is not None:
            N.hand_to(p, side, w, elbow=e, hand=Wh)
        else:
            flex, out, turn, elbow = a
            p["UpperArm_" + side] = (flex, s * turn, s * out)
            p["LowerArm_" + side] = (elbow, 0.0, 0.0)
            if Wh is not None:
                N.world_rot(p, "Hand_" + side, Wh)
        if h is not None and Wh is None and sk is None:
            p["Hand_" + side] = (h[0], s * h[1], s * h[2])
    # ---- head
    if nk is not None:
        p["Neck"] = tuple(nk[0:3])
        p["Head"] = tuple(nk[3:6])
    elif head is not None:
        N.level_head(p, head[0], head[1], head[2])
    if floor is not None:
        N.ground(p, clearance=floor)
    return p


def K(*bases, **kw):
    """Parameter dict: the base dicts merged in order, then updated with kw."""
    d = {}
    for b in bases:
        if b:
            d.update(b)
    d.update(kw)
    return d


def comp(*eulers):
    """Euler of several bone-local rotations applied in sequence, each about the axes produced by the
    previous ones (comp((-78, 0, 0), (0, 10, 0)) = pitch the body forward, then roll it about its own
    long axis)."""
    m = N.I3.copy()
    for e in eulers:
        m = m @ N.rot(*e)
    return N.to_euler(m)


# --------------------------------------------------------------------------- clip runners
def cyc(name, length, fn, loop=True, step=2):
    N.clip(name, length, N.bake(fn, length, step=step, loop=loop), loop=loop)


def tracks(name, length, keys, loop=False, step=1, interp="ease", const=None, post=None):
    """keys = {frame: params}. A parameter that is missing from a key is held from its neighbours;
    parameters are interpolated ('ease' = smoothstep, 'spline' = Catmull-Rom) and the pose is rebuilt
    (IK re-solved) on every baked frame."""
    tr = {}
    for fr in sorted(keys):
        for k, v in keys[fr].items():
            tr.setdefault(k, {})[float(fr)] = v
    if loop:
        for k, t in tr.items():
            if float(length) not in t:
                t[float(length)] = t[min(t)] if 0.0 not in t else t[0.0]
            if 0.0 not in t:
                t[0.0] = t[float(length)]

    def fn(t):
        kw = dict(const or {})
        for k, trk in tr.items():
            if isinstance(trk[min(trk)], str) or len(trk) == 1:
                kw[k] = trk[min(trk)]
            elif interp == "spline":
                kw[k] = N.spline(t, trk)
            else:
                kw[k] = N.kf(t, trk, ease=(interp == "ease"))
        p = pose(**kw)
        if post is not None:
            p = post(p, t) or p
        return p

    N.clip(name, length, N.bake(fn, length, step=step, loop=loop), loop=loop)


def _unwrap(prev, cur):
    for b in N.BONES:
        pe = prev.get(b, (0.0, 0.0, 0.0))
        e = cur.get(b, (0.0, 0.0, 0.0))
        e = tuple(e[i] + 360.0 * round((pe[i] - e[i]) / 360.0) for i in range(3))
        if max(abs(e[i] - pe[i]) for i in range(3)) > 150.0:
            e2 = N.to_euler(N.rot(*e), pe)
            if sum(abs(e2[i] - pe[i]) for i in range(3)) < sum(abs(e[i] - pe[i]) for i in range(3)):
                e = e2
        cur[b] = e
    cur.setdefault(LOC, (0.0, 0.0, 0.0))
    prev.setdefault(LOC, (0.0, 0.0, 0.0))


def keyed(name, length, keys, loop=False, step=1, floor=True, interp="spline"):
    """keys = {frame: full pose}. Eulers are blended between the keys; with floor=True every baked
    frame is lifted when a body vertex would sink below z = 0."""
    frs = sorted(keys)
    poses = [dict(keys[f]) for f in frs]
    for i in range(1, len(poses)):
        _unwrap(poses[i - 1], poses[i])
    names = list(N.BONES) + [LOC]
    per = {b: {float(f): tuple(poses[i].get(b, (0.0, 0.0, 0.0))) for i, f in enumerate(frs)} for b in names}

    def fn(t):
        p = {}
        for b in names:
            if interp == "spline":
                p[b] = N.spline(t, per[b])
            else:
                p[b] = N.kf(t, per[b], ease=(interp == "ease"))
        if floor:
            z, _bn = N.min_z(p)
            if z < 0.0:
                N.move(p, dz=-z)
        return p

    N.clip(name, length, N.bake(fn, length, step=step, loop=loop), loop=loop)


# --------------------------------------------------------------------------- shared stances
IDLE = dict(dz=-0.012, dx=0.0, dy=0.0, hips=(0, 0, 0), spine=(0, 0, 0), chest=(0, 0, 0), head=(0, 0, 0),
            fl=FOOT0, fr=FOOT0, al=ARM0, ar=ARM0)
# boxing guard (left side leading); Hips stay un-rotated so the upper body can be layered
GUARD = dict(dz=-0.06, dx=0.0, dy=0.0, hips=(0, 0, 0), spine=(-3, -5, 0), chest=(-4, -6, 0), head=(-2, 0, 0),
             fl=(0.03, 0.13, 0.0, 0.0, 2.0), fr=(0.05, -0.13, 0.0, -12.0, 30.0),
             wl=(-0.13, 0.27, 1.38), wr=(0.15, 0.18, 1.35), el=(-0.45, -0.3, -1.0), er=(0.45, -0.3, -1.0),
             gl=(0.15, 0.3, 1.0, 1.0, 0.0, 0.0), gr=(-0.15, 0.3, 1.0, -1.0, 0.0, 0.0))


# --------------------------------------------------------------------------- gaits
def _hermite(u, m):
    u2, u3 = u * u, u * u * u
    return (u3 - 2.0 * u2 + u) * m + (-2.0 * u3 + 3.0 * u2) + (u3 - u2) * m


def _gait_foot(f, c):
    d = c["duty"]
    if f < d:
        u = f / d
        return (c["out"], lerp(c["front"], c["back"], u), 0.0, N.kf(u, c["st_pitch"]), c["toe"])
    u = (f - d) / (1.0 - d)
    m = max(-(1.0 - d) / d, -0.6)
    y = c["back"] + (c["front"] - c["back"]) * _hermite(u, m)
    return (c["out"], y, N.kf(u, c["sw_lift"]), N.kf(u, c["sw_pitch"]), c["toe"])


def gait_speed(c, length):
    return round((c["front"] - c["back"]) / (c["duty"] * length / float(N.FPS)), 2)


def gait(t, T, c):
    ph = (t / float(T)) % 1.0
    w = 2.0 * pi * ph
    sw = sin(2.0 * pi * (ph - c["sway_ph"]))
    yaw = c["yaw"] * cos(w)
    roll = c["roll"] * sw
    hl, sl_, cl = c["lean"]
    a = c["arm"]
    sr = -cos(2.0 * pi * (ph - a["lag"]))            # right arm: back at the right foot strike
    kw = dict(dz=c["dz"] - c["bob"] * cos(4.0 * pi * (ph - c["low"])), dx=c["sway"] * sw, dy=c.get("dy", 0.0),
              hips=(-hl, yaw, roll),
              spine=(-sl_, -yaw * c["counter"] * 0.5, -roll * 0.8),
              chest=(-cl, -yaw * c["counter"] * 0.5, -roll * 0.2),
              fr=_gait_foot(ph, c), fl=_gait_foot((ph + 0.5) % 1.0, c), head=c.get("head", (0, 0, 0)))
    for key, v in (("ar", sr), ("al", -sr)):
        fwd = 0.5 + 0.5 * v
        kw[key] = (a["bias"] + a["amp"] * v, a["out"], a["turn"] + a.get("turn_sw", 0.0) * fwd,
                   a["e0"] + a["e1"] * fwd)
    if "hand" in a:
        kw["hl"] = kw["hr"] = a["hand"]
    return pose(**kw)


WALK = dict(duty=0.52, front=0.38, back=-0.40, out=-0.012, toe=7.0,
            st_pitch={0.0: 22.0, 0.14: 0.0, 0.6: 0.0, 1.0: -38.0},
            sw_lift={0.0: 0.0, 0.45: 0.075, 1.0: 0.0}, sw_pitch={0.0: -38.0, 0.35: -22.0, 0.75: 12.0, 1.0: 22.0},
            dz=-0.034, bob=0.018, low=0.01, yaw=8.0, roll=2.6, sway=0.02, sway_ph=0.01, counter=1.6,
            lean=(1.0, 2.0, 1.0), dy=0.01,
            arm=dict(amp=24.0, bias=3.0, out=4.0, turn=6.0, e0=8.0, e1=20.0, lag=0.03))
RUN = dict(duty=0.27, front=0.22, back=-0.52, out=-0.02, toe=4.0,
           st_pitch={0.0: 8.0, 0.25: 0.0, 0.55: -8.0, 1.0: -55.0},
           sw_lift={0.0: 0.0, 0.22: 0.25, 0.5: 0.21, 0.8: 0.09, 1.0: 0.0},
           sw_pitch={0.0: -55.0, 0.2: -75.0, 0.5: -30.0, 0.8: 0.0, 1.0: 8.0},
           dz=-0.05, bob=0.035, low=0.135, yaw=10.0, roll=2.0, sway=0.012, sway_ph=-0.115, counter=1.7,
           lean=(4.0, 5.0, 3.0), dy=0.0,
           arm=dict(amp=36.0, bias=-4.0, out=7.0, turn=14.0, turn_sw=14.0, e0=78.0, e1=20.0, lag=0.02))
SPRINT = dict(duty=0.22, front=0.24, back=-0.56, out=-0.02, toe=2.0,
              st_pitch={0.0: 4.0, 0.3: -4.0, 0.6: -18.0, 1.0: -60.0},
              sw_lift={0.0: 0.0, 0.2: 0.34, 0.5: 0.32, 0.8: 0.12, 1.0: 0.0},
              sw_pitch={0.0: -60.0, 0.2: -80.0, 0.5: -35.0, 0.8: -5.0, 1.0: 4.0},
              dz=-0.058, bob=0.03, low=0.11, yaw=13.0, roll=2.0, sway=0.01, sway_ph=-0.14, counter=1.8,
              lean=(12.0, 8.0, 5.0), dy=-0.02,
              arm=dict(amp=56.0, bias=2.0, out=8.0, turn=8.0, turn_sw=10.0, e0=84.0, e1=14.0, lag=0.02))
CROUCH_ARM = (30.0, 8.0, 12.0, 80.0)
CROUCHWALK = dict(duty=0.56, front=0.36, back=-0.40, out=0.02, toe=8.0,
                  st_pitch={0.0: 12.0, 0.15: 0.0, 0.6: 0.0, 1.0: -36.0},
                  sw_lift={0.0: 0.0, 0.5: 0.09, 1.0: 0.0}, sw_pitch={0.0: -36.0, 0.4: -18.0, 0.8: 8.0, 1.0: 12.0},
                  dz=-0.30, bob=0.012, low=0.03, yaw=7.0, roll=2.0, sway=0.025, sway_ph=0.03, counter=1.5,
                  lean=(24.0, 12.0, 6.0), dy=-0.05,
                  arm=dict(amp=7.0, bias=30.0, out=8.0, turn=12.0, e0=78.0, e1=6.0, lag=0.03))


# --------------------------------------------------------------------------- CORE clips
def c_idle():
    def fn(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        sw = sin(w - 1.1)
        return pose(dz=-0.012 + 0.003 * br, dx=0.007 * sw, hips=(0, 0, 0.7 * sw), spine=(-0.5, 0, -0.5 * sw),
                    chest=(1.2 * br, 0, -0.2 * sw), head=(0.6 * br, 1.5 * sin(w + 2.0), 0),
                    al=(2 - 1.2 * br, 3 + 0.9 * br, 8, 10 + 2.5 * br), ar=(2 - 1.2 * br, 3 + 0.9 * br, 8, 10 + 2.5 * sin(w - 0.5)))
    cyc("Idle", 60, fn)


def c_gaits():
    cyc("Walk", 32, lambda t: gait(t, 32, WALK), step=1)
    cyc("Run", 20, lambda t: gait(t, 20, RUN), step=1)
    cyc("Sprint", 16, lambda t: gait(t, 16, SPRINT), step=1)
    cyc("CrouchWalk", 32, lambda t: gait(t, 32, CROUCHWALK), step=1)
    for n, c, ln in (("Walk", WALK, 32), ("Run", RUN, 20), ("Sprint", SPRINT, 16), ("CrouchWalk", CROUCHWALK, 32)):
        SPEED[n] = gait_speed(c, ln)


def c_crouch_idle():
    def fn(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        return pose(dz=-0.33 + 0.004 * br, dy=-0.06, dx=0.004 * sin(w - 1.0), hips=(-24, 0, 0),
                    spine=(-12 + 0.8 * br, 0, 0), chest=(-6 + 0.8 * br, 0, 0),
                    fl=(0.03, 0.12, 0, 0, 8), fr=(0.04, -0.12, 0, -28, 14),
                    al=(30 - br, 8, 12, 80 + 1.5 * br), ar=(30 - br, 8, 12, 80 + 1.5 * sin(w - 0.6)),
                    head=(0, 2.0 * sin(w + 2.0), 0))
    cyc("CrouchIdle", 60, fn)


def c_air():
    tracks("Jump", 10, {
        0: IDLE,
        4: K(dz=-0.24, dy=-0.03, hips=(-22, 0, 0), spine=(-12, 0, 0), chest=(-6, 0, 0), head=(4, 0, 0),
             al=(-55, 12, 0, 25), ar=(-55, 12, 0, 25)),
        7: K(dz=-0.05, dy=0.0, hips=(-8, 0, 0), spine=(-4, 0, 0), chest=(-2, 0, 0),
             al=(55, 10, 0, 45), ar=(55, 10, 0, 45), fl=(0.01, 0, 0, -14, 8), fr=(0.01, 0, 0, -14, 8)),
        10: K(dz=0.12, hips=(3, 0, 0), spine=(3, 0, 0), chest=(2, 0, 0), head=(6, 0, 0),
              al=(152, 8, 0, 22), ar=(146, 8, 0, 28), fl=(0.01, 0, 0, -44, 8), fr=(0.01, -0.02, 0, -44, 8)),
    })

    def fall(t):
        w = 2.0 * pi * t / 30.0
        s1 = sin(w)
        return pose(hips=(-8 + 2 * s1, 0, 2 * s1), spine=(-5, 0, 0), chest=(-3, 3 * s1, 0), head=(-12, 0, 0),
                    ll=(34 + 8 * s1, 58 + 8 * sin(w + 1.0), -18, 6, 4),
                    lr=(-6 - 8 * s1, 38 - 8 * sin(w + 1.0), -25, 8, 6),
                    al=(22 + 8 * sin(w + 0.5), 74 + 9 * s1, 0, 38 + 10 * sin(w + 2.0)),
                    ar=(18 - 8 * sin(w + 0.5), 70 - 9 * sin(w + 0.4), 0, 42 - 10 * sin(w + 2.0)))
    cyc("Fall", 30, fall)

    wide = dict(fl=(0.04, 0.03, 0, 0, 10), fr=(0.04, -0.03, 0, 0, 10))
    tracks("Land", 10, {
        0: K(wide, dz=-0.06, dy=0.0, hips=(-8, 0, 0), spine=(-6, 0, 0), chest=(-2, 0, 0), head=(-8, 0, 0),
             al=(25, 55, 0, 40), ar=(25, 55, 0, 40)),
        3: K(dz=-0.32, dy=-0.04, hips=(-30, 0, 0), spine=(-14, 0, 0), chest=(-8, 0, 0), head=(2, 0, 0),
             al=(52, 28, 5, 50), ar=(52, 28, 5, 50)),
        10: K(IDLE, **wide),
    })


def c_sit_car():
    def fn(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        st = 0.012 * sin(w + 1.0)                    # tiny steering correction
        hip = Vector((0.0, 0.0, 0.96))
        return pose(hips=(12, 0, 0), spine=(3 + 0.6 * br, 0, 0), chest=(-4 + 0.8 * br, 0, 0),
                    head=(0, 2.5 * sin(w + 2.0), 0),
                    xl=(-0.12, 0.54, hip.z - 0.25, 18, 6), xr=(0.13, 0.60, hip.z - 0.26, 24, -4),
                    nl=(-0.25, 0.3, 1.0), nr=(0.2, 0.3, 1.0),
                    pl=(-0.17, 0.41, hip.z + 0.34 - st), pr=(0.17, 0.41, hip.z + 0.34 + st),
                    gl=(0.25, 0.9, 0.35, 1.0, 0.1, 0.0), gr=(-0.25, 0.9, 0.35, -1.0, 0.1, 0.0),
                    el=(-0.7, -0.3, -1.0), er=(0.7, -0.3, -1.0), floor=0.0)
    cyc("SitCar", 60, fn)
    NOTES["SitCar"] = ("hands on a wheel whose hub is 0.40 in front of / 0.31 above the Hips bone (car kit "
                       "steer_hub), heels 0.26 below / 0.55 in front of the Hips")


def c_aim():
    def pistol(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        g = Vector((0.0, 0.59, 1.545 + 0.004 * br))
        return pose(dz=-0.07 + 0.003 * br, spine=(-6, 0, 0), chest=(-5 + 0.6 * br, 0, 0), head=(-1, 0, 0),
                    fl=(0.06, 0.10, 0, 0, 6), fr=(0.07, -0.12, 0, 0, 22),
                    sr=(g.x, g.y, g.z, 0, 1, 0, 0, 0, 1), er=(0.5, -0.2, -1.0),
                    pl=(g.x - 0.036, g.y - 0.004, g.z - 0.024), gl=(0.5, 0.82, 0.25, 1.0, -0.1, 0.1),
                    el=(-0.5, -0.2, -1.0))
    cyc("AimPistol", 60, pistol)

    def rifle(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        g = Vector((0.09, 0.30, 1.44 + 0.004 * br))
        return pose(dz=-0.06 + 0.003 * br, spine=(-4, -10, 0), chest=(-4 + 0.6 * br, -12, 0), head=(-5, 0, -7),
                    fl=(0.04, 0.14, 0, 0, 0), fr=(0.07, -0.16, 0, 0, 30),
                    sr=(g.x, g.y, g.z, 0, 1, 0, 0, 0, 1), er=(0.9, -0.2, -0.6),
                    pl=(g.x, g.y + 0.30, g.z + 0.03), gl=(0.8, 0.5, 0.2, 0.0, 0.0, 1.0), el=(-0.3, -0.2, -1.0))
    cyc("AimRifle", 60, rifle)

    def low_ready(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        g = Vector((0.19, 0.17, 1.08 + 0.004 * br))
        f = Vector((-0.72, 0.64, -0.27)).normalized()
        s = g + f * 0.30 + Vector((0.0, 0.0, 0.03))
        return pose(dz=-0.012 + 0.003 * br, dx=0.005 * sin(w - 1.1), chest=(1.0 * br, 0, 0), head=(0, 0, 0),
                    sr=(g.x, g.y, g.z, f.x, f.y, f.z, -0.2, 0.2, 1.0), er=(0.6, -0.9, -0.2),
                    pl=(s.x, s.y, s.z), gl=(0.55, 0.55, 0.5, 0.3, -0.3, 1.0), el=(-0.6, -0.4, -0.7))
    cyc("HoldRifle", 60, low_ready)
    NOTES["HoldRifle"] = "grip at the right hip, muzzle down-left; support palm 0.30 along the barrel"

    # Reload: weapon held at the chest by the right hand, left hand fetches a magazine from the belt
    rdy = (0.13, 0.36, 1.26, -0.15, 0.85, 0.5, -0.4, 0.0, 1.0)
    tilt = (0.14, 0.34, 1.28, -0.28, 0.6, 0.75, -0.6, 0.0, 0.8)
    up = (1.0, -0.1, 0.25)
    tracks("Reload", 30, {
        0: K(IDLE, spine=(-2, 0, 0), chest=(-2, 0, 0), sr=rdy, er=(0.6, -0.7, -0.6),
             pl=(0.07, 0.36, 1.22), gl=(0.6, 0.6, 0.5) + up, el=(-0.5, -0.4, -0.8), head=(-6, -4, 0)),
        4: K(sr=tilt, pl=(0.06, 0.33, 1.20), head=(-18, -8, 0)),
        10: K(pl=(-0.17, 0.12, 1.03), gl=(0.2, 0.3, -1.0, 1.0, 0.0, 0.2), head=(-20, 4, 0)),
        13: K(pl=(-0.16, 0.14, 1.05), gl=(0.2, 0.3, -1.0, 1.0, 0.0, 0.2)),
        20: K(sr=tilt, pl=(0.10, 0.33, 1.15), gl=(0.5, 0.4, 0.75) + up, head=(-18, -8, 0)),
        23: K(sr=(0.14, 0.34, 1.295, -0.28, 0.6, 0.75, -0.6, 0.0, 0.8), pl=(0.12, 0.34, 1.215)),
        30: K(sr=rdy, pl=(0.07, 0.36, 1.22), gl=(0.6, 0.6, 0.5) + up, head=(-6, -4, 0)),
    })


def c_melee():
    jab = (0.0, 1.0, 0.05, 0.25, 0.0, -1.0)
    tracks("Punch_L", 12, {
        0: GUARD,
        2: K(wl=(-0.14, 0.23, 1.37), spine=(-3, -3, 0), chest=(-4, -4, 0)),
        5: K(wl=(-0.05, 0.68, 1.43), gl=jab, el=(-0.8, -0.2, -0.6), spine=(-5, -12, 0), chest=(-5, -16, 0),
             dy=0.03, wr=(0.14, 0.17, 1.38)),
        6: K(wl=(-0.05, 0.685, 1.43)),
        9: K(wl=(-0.12, 0.36, 1.39), gl=GUARD["gl"], el=GUARD["el"], spine=(-3, -7, 0), chest=(-4, -8, 0), dy=0.01),
        12: GUARD,
    })
    cross = (0.0, 1.0, 0.05, -0.25, 0.0, -1.0)
    tracks("Punch_R", 12, {
        0: GUARD,
        2: K(wr=(0.17, 0.12, 1.34), spine=(-3, -8, 0), chest=(-4, -9, 0)),
        6: K(wr=(0.03, 0.70, 1.44), gr=cross, er=(0.8, -0.2, -0.6), hips=(0, 8, 0), spine=(-6, 12, 0),
             chest=(-6, 16, 0), dy=0.04, dx=-0.01, fr=(0.05, -0.13, 0.0, -28.0, 6.0), wl=(-0.15, 0.22, 1.40)),
        7: K(wr=(0.03, 0.705, 1.44)),
        10: K(wr=(0.14, 0.32, 1.38), gr=GUARD["gr"], er=GUARD["er"], hips=(0, 3, 0), spine=(-4, 0, 0),
              chest=(-4, 2, 0), dy=0.01, dx=0.0),
        12: GUARD,
    })
    # front push kick with the rear (right) leg
    g = K(GUARD, fl=(0.03, 0.13, 0.0, 0.0, 12.0), nr=(0.0, 0.5, 1.0))
    z0 = N.foot_height(N.foot_rot(-12, -30, 0), "R")
    tracks("Kick", 18, {
        0: K(g, xr=(0.145, -0.13, z0, -12, -30)),
        3: K(xr=(0.12, -0.02, 0.30, -25, -10), dx=-0.03),
        6: K(xr=(0.11, 0.26, 0.66, 10, 0), dx=-0.05, dy=0.02, hips=(4, 0, -3)),
        9: K(xr=(0.10, 0.76, 0.96, 78, 0), dx=-0.06, dy=-0.03, dz=-0.045, hips=(16, 0, -4), spine=(4, -5, 0),
             chest=(0, -6, 0), wl=(-0.30, 0.20, 1.30), wr=(0.32, 0.04, 1.22)),
        10: K(xr=(0.10, 0.765, 0.96, 78, 0)),
        13: K(xr=(0.11, 0.30, 0.62, 15, 0), dx=-0.05, dy=0.01, dz=-0.06, hips=(4, 0, -3), spine=(-3, -5, 0),
              chest=(-4, -6, 0), wl=GUARD["wl"], wr=GUARD["wr"]),
        16: K(xr=(0.14, -0.08, 0.19, -10, -22), dx=-0.02, hips=(0, 0, 0), dy=0.0),
        18: K(xr=(0.145, -0.13, z0, -12, -30), dx=0.0),
    })
    tracks("HitReact_F", 10, {
        0: IDLE,
        2: K(dz=-0.05, dy=-0.05, hips=(6, 0, 0), spine=(12, 4, 0), chest=(12, 6, 0), head=(-14, -4, 0),
             al=(32, 22, 0, 40), ar=(36, 26, 0, 46)),
        5: K(dz=-0.04, dy=-0.03, hips=(3, 0, 0), spine=(6, 2, 0), chest=(5, 3, 0), head=(5, 0, 0),
             al=(14, 12, 4, 25), ar=(16, 14, 4, 28)),
        10: IDLE,
    })


def c_death_back():
    k = {}
    k[0] = pose(**IDLE)
    k[3] = pose(**K(IDLE, dz=-0.05, dy=-0.03, hips=(8, 0, 2), spine=(10, 0, 0), chest=(10, 4, 0), head=(-10, 0, 0),
                    al=(35, 30, 0, 40), ar=(20, 45, 0, 30)))
    k[8] = pose(dz=-0.40, dy=-0.14, hips=(32, 0, 3), spine=(8, 0, 0), chest=(4, 0, 0), nk=(-12, 0, 0, -10, 0, 0),
                fl=(0.03, 0.10, 0, 8, 10), fr=(0.05, 0.16, 0, 12, 14), al=(70, 40, 0, 35), ar=(60, 55, 0, 30))
    k[14] = pose(dy=-0.20, hips=(58, 0, 2), spine=(6, 0, 0), chest=(2, 0, 0), nk=(-14, 0, 0, -12, 0, 0),
                 ll=(56, 46, -15, 6, 8), lr=(50, 36, -15, 8, 12), al=(95, 45, 0, 30), ar=(85, 60, 0, 25), floor=0.0)
    last = dict(dy=-0.22, hips=(90, 0, 2), spine=(0, 0, 0), chest=(-2, 0, 0), nk=(2, 6, 0, 4, 10, 0),
                ll=(3, 10, -28, 9, 12), lr=(-1, 20, -22, 13, 20), floor=0.0)
    k[19] = pose(**K(last, hips=(91, 0, 2), al=(10, 40, -50, 30), ar=(14, 70, -70, 55), lr=(6, 30, -22, 13, 20)))
    k[24] = pose(**K(last, al=(-8, 35, -60, 25), ar=(-6, 70, -80, 60)))
    keyed("Death_Back", 24, k)


def c_swim():
    path = {0.0: (0.22, 0.98, 1.06), 0.15: (0.22, 0.85, 0.86), 0.30: (0.14, 0.50, 0.68), 0.45: (0.24, 0.10, 0.84),
            0.55: (0.30, -0.02, 1.02), 0.70: (0.42, 0.36, 1.12), 0.85: (0.34, 0.74, 1.14)}
    pole = {0.0: (1.0, 0.0, 0.5), 0.30: (1.0, -0.1, 0.25), 0.55: (0.6, -0.3, 0.8), 0.70: (0.4, -0.3, 1.0),
            0.85: (0.7, -0.1, 0.8)}

    def swim(t):
        u = (t / 30.0) % 1.0
        ul = (u + 0.5) % 1.0
        w = 2.0 * pi * u
        rl = sin(2.0 * pi * (u - 0.05))
        k3 = 3.0 * w
        wr = N.spline(u, path, period=1.0)
        wl = N.spline(ul, path, period=1.0)
        er = N.spline(u, pole, period=1.0)
        el = N.spline(ul, pole, period=1.0)
        return pose(dz=0.01 * sin(2.0 * w), hips=comp((-78, 0, 0), (0, -5 * rl, 0)), spine=(4, 8 * rl, 0),
                    chest=(6, 14 * rl, 0),
                    head=(-38, 0, 0),
                    ll=(4 - 12 * sin(k3), 14 + 10 * sin(k3 + 0.6), -35, 2, 0),
                    lr=(4 + 12 * sin(k3), 14 - 10 * sin(k3 + 0.6), -35, 2, 0),
                    wr=wr, er=er, wl=(-wl[0], wl[1], wl[2]), el=(-el[0], el[1], el[2]))
    cyc("Swim", 30, swim, step=1)

    def tread(t):
        w = 2.0 * pi * t / 40.0
        s1 = sin(w)
        return pose(dz=0.012 * sin(2.0 * w), hips=(-6, 0, 0), spine=(-2, 0, 0), chest=(3, 0, 0), head=(6, 0, 0),
                    ll=(18 + 24 * s1, 45 - 22 * sin(w + 0.9), -30, 9, 6),
                    lr=(18 - 24 * s1, 45 + 22 * sin(w + 0.9), -30, 9, 6),
                    al=(34 + 5 * cos(w), 62 + 18 * s1, 10, 46 - 14 * s1), ar=(34 + 5 * cos(w), 62 + 18 * s1, 10, 46 - 14 * s1),
                    hl=(0, 60, 0), hr=(0, 60, 0))
    cyc("SwimIdle", 40, tread)


# --------------------------------------------------------------------------- remaining clips (spec section 4)
CROUCH = dict(dz=-0.33, dy=-0.06, hips=(-24, 0, 0), spine=(-12, 0, 0), chest=(-6, 0, 0), head=(0, 0, 0),
              fl=(0.03, 0.12, 0, 0, 8), fr=(0.04, -0.12, 0, -28, 14), al=CROUCH_ARM, ar=CROUCH_ARM)
LYING = dict(dy=-0.20, hips=(90, 0, 0), spine=(0, 0, 0), chest=(-2, 0, 0), nk=(2, 0, 0, 4, 0, 0),
             ll=(4, 14, -25, 8, 10), lr=(6, 22, -22, 10, 14), al=(-8, 40, -40, 25), ar=(-8, 48, -50, 30), floor=0.0)
PRONE = dict(dy=0.20, hips=(-90, 0, 0), spine=(2, 0, 0), chest=(3, 0, 0), nk=(-4, 30, 0, -4, 42, 0),
             ll=(2, 10, -72, 6, 14), lr=(0, 6, -72, 9, 18), al=(6, 25, -20, 20), ar=(6, 100, -80, 75), floor=0.0)
KNEEL_FALL = dict(dz=-0.36, dy=0.06, hips=(-14, 0, 0), spine=(-10, 0, 0), chest=(-8, 0, 0), nk=(-10, 0, 0, -14, 0, 0),
                  ll=(28, 100, -40, 4, 0), lr=(20, 95, -40, 6, 0), al=(15, 15, 0, 25), ar=(10, 20, 0, 30), floor=0.0)


def c_roll():
    tuck = dict(spine=(-28, 0, 0), chest=(-22, 0, 0), nk=(-25, 0, 0, -25, 0, 0), ll=(115, 125, 10, 8, 6),
                lr=(110, 120, 10, 8, 6), al=(70, 12, 30, 115), ar=(70, 12, 30, 115), floor=0.0)
    k = {
        0: pose(**CROUCH),
        3: pose(hips=(-78, 0, 0), spine=(-20, 0, 0), chest=(-15, 0, 0), nk=(-20, 0, 0, -25, 0, 0),
                ll=(100, 100, 20, 6, 4), lr=(85, 80, 25, 6, 4), al=(120, 15, 10, 30), ar=(120, 15, 10, 30), floor=0.0),
        6: pose(**K(tuck, hips=(-150, 0, 0))),
        10: pose(**K(tuck, hips=(-235, 0, 0))),
        14: pose(**K(tuck, hips=(-305, 0, 0), ll=(105, 120, 15, 8, 6), lr=(100, 115, 15, 8, 6), al=(60, 14, 20, 90),
                     ar=(60, 14, 20, 90))),
        17: pose(dz=-0.50, dy=-0.03, hips=(-378, 0, 0), spine=(-22, 0, 0), chest=(-12, 0, 0), head=(-10, 0, 0),
                 fl=(0.03, 0.10, 0, 0, 8), fr=(0.04, -0.06, 0, -20, 12), al=(45, 14, 10, 70), ar=(45, 14, 10, 70)),
        20: pose(**K(CROUCH, hips=(-384, 0, 0))),
    }
    keyed("Roll", 20, k)


def c_water():
    tracks("Dive", 36, {
        0: K(hips=(-86, 0, 0), spine=(3, 0, 0), chest=(4, 0, 0), head=(-32, 0, 0), dz=0.0,
             wr=(0.06, 0.99, 0.98), wl=(-0.06, 0.99, 0.98), er=(1.0, 0.0, 0.3), el=(-1.0, 0.0, 0.3),
             gr=(0, 1, 0, 0, 0, -1), gl=(0, 1, 0, 0, 0, -1),
             ll=(0, 5, -40, 2, 0), lr=(0, 5, -40, 2, 0)),
        8: K(wr=(0.07, 0.99, 0.97), wl=(-0.07, 0.99, 0.97), ll=(0, 5, -40, 2, 0), lr=(0, 5, -40, 2, 0),
             hips=(-86, 0, 0), dz=0.0),
        14: K(wr=(0.42, 0.72, 0.92), wl=(-0.42, 0.72, 0.92), gr=(0.3, 1, 0, 0.4, 0, -1), gl=(-0.3, 1, 0, -0.4, 0, -1),
              hips=(-83, 0, 0), dz=0.02),
        16: K(ll=(35, 95, 20, 25, 25), lr=(35, 95, 20, 25, 25)),
        20: K(wr=(0.40, 0.42, 0.84), wl=(-0.40, 0.42, 0.84), hips=(-82, 0, 0), dz=0.03),
        22: K(ll=(10, 30, 10, 28, 20), lr=(10, 30, 10, 28, 20)),
        25: K(wr=(0.10, 0.46, 0.80), wl=(-0.10, 0.46, 0.80), gr=(0, 1, 0, 0, 0, -1), gl=(0, 1, 0, 0, 0, -1)),
        28: K(ll=(0, 5, -40, 4, 0), lr=(0, 5, -40, 4, 0), hips=(-86, 0, 0), dz=0.0),
        30: K(wr=(0.07, 0.68, 0.90), wl=(-0.07, 0.68, 0.90)),
    }, loop=True, interp="spline")


def c_ladder():
    T, d = 24.0, 0.6

    def limb(f, top, bot):
        if f < d:
            return lerp(top, bot, f / d), 0.0
        u = (f - d) / (1.0 - d)
        return lerp(bot, top, N.smooth(u)), sin(pi * u)

    def fn(t):
        ph = (t / T) % 1.0
        zr, pr_ = limb(ph, 1.79, 1.27)
        zl, pl_ = limb((ph + 0.5) % 1.0, 1.79, 1.27)
        fl_, bl = limb(ph, 0.62, 0.10)                 # left foot travels with the right hand
        fr_, br = limb((ph + 0.5) % 1.0, 0.62, 0.10)
        sw = sin(2.0 * pi * ph)
        return pose(dz=-0.03 + 0.012 * cos(4.0 * pi * ph), dx=0.015 * sw, hips=(-4, 0, 2.0 * sw),
                    spine=(-2, 0, -1.5 * sw), chest=(0, 4.0 * sw, 0), head=(12, 0, 0),
                    xl=(-0.11, 0.21 - 0.05 * bl, fl_, -8, 0), xr=(0.11, 0.21 - 0.05 * br, fr_, -8, 0),
                    nl=(-0.35, 1.0, 0.3), nr=(0.35, 1.0, 0.3),
                    wl=(-0.20, 0.35 - 0.06 * pl_, zl), wr=(0.20, 0.35 - 0.06 * pr_, zr),
                    gl=(0, 0.35, 1, 0, 1, -0.3), gr=(0, 0.35, 1, 0, 1, -0.3),
                    el=(-0.6, -0.5, -0.6), er=(0.6, -0.5, -0.6))
    cyc("ClimbLadder", 24, fn, step=1)
    SPEED["ClimbLadder"] = round(0.52 / (d * T / N.FPS), 2)
    NOTES["ClimbLadder"] = "rungs 0.35 in front of the Hips (hands) / 0.21 (feet), body upright facing +Y"


def c_traverse():
    up = (0, 0.3, 1, 0, 1, 0)
    dn = dict(el=(-0.6, -0.3, -0.8), er=(0.6, -0.3, -0.8))
    k = {
        0: pose(dz=-0.10, hips=(-18, 0, 0), spine=(-10, 0, 0), chest=(-5, 0, 0), fl=(0.02, 0.16, 0, 0, 6),
                fr=(0.03, -0.20, 0, -25, 8), wl=(-0.19, 0.40, 1.05), wr=(0.19, 0.40, 1.05), **dn),
        4: pose(dz=0.05, hips=(-30, 0, 0), spine=(-8, 0, 0), chest=(-4, 0, 0), fl=(0.02, 0.05, 0.0, -35, 6),
                fr=(0.03, -0.05, 0.10, -40, 8), wl=(-0.19, 0.38, 1.02), wr=(0.19, 0.38, 1.02), **dn),
        8: pose(dz=0.32, hips=(-38, 0, 0), spine=(-6, 0, 0), chest=(0, 0, 0), head=(5, 0, 0),
                ll=(95, 110, 0, 8, 0), lr=(100, 115, 0, 8, 0), wl=(-0.21, 0.10, 1.02), wr=(0.21, 0.10, 1.02), **dn),
        12: pose(dz=0.18, hips=(-5, 0, 0), spine=(-4, 0, 0), ll=(55, 40, 10, 5, 0), lr=(40, 30, 5, 5, 0),
                 wl=(-0.30, -0.18, 1.12), wr=(0.30, -0.18, 1.12), el=(-0.7, -0.6, 0.2), er=(0.7, -0.6, 0.2)),
        15: pose(dz=-0.16, hips=(-16, 0, 0), spine=(-8, 0, 0), chest=(-4, 0, 0), fl=(0.03, 0.06, 0, 0, 8),
                 fr=(0.03, -0.04, 0, 0, 8), al=(20, 30, 0, 40), ar=(20, 30, 0, 40)),
        18: pose(**IDLE),
    }
    keyed("Vault", 18, k)
    NOTES["Vault"] = "hands plant on an obstacle top ~1.0 high, 0.4 in front; root stays in place"
    k = {
        0: pose(hips=(2, 0, 0), spine=(2, 0, 0), chest=(4, 0, 0), head=(22, 0, 0), fl=(0.0, 0.0, 0, -20, 5),
                fr=(0.0, 0.0, 0, -20, 5), wl=(-0.20, 0.26, 1.90), wr=(0.20, 0.26, 1.90), gl=up, gr=up, **dn),
        6: pose(hips=(-4, 0, 0), head=(8, 0, 0), ll=(8, 25, -30, 3, 0), lr=(22, 45, -30, 3, 0),
                wl=(-0.22, 0.24, 1.42), wr=(0.22, 0.24, 1.42), gl=up, gr=up, **dn),
        12: pose(hips=(-22, 0, 0), spine=(-8, 0, 0), head=(0, 0, 0), ll=(5, 20, -30, 3, 0), lr=(85, 105, 0, 6, 0),
                 wl=(-0.24, 0.16, 0.98), wr=(0.24, 0.16, 0.98), gl=(0, 1, 0, 0, 0, -1), gr=(0, 1, 0, 0, 0, -1),
                 el=(-0.8, -0.5, 0.2), er=(0.8, -0.5, 0.2)),
        17: pose(dz=-0.30, hips=(-30, 0, 0), spine=(-12, 0, 0), chest=(-4, 0, 0), fr=(0.04, 0.10, 0, 0, 8),
                 fl=(0.03, -0.20, 0.0, -40, 6), al=(30, 12, 5, 60), ar=(40, 14, 5, 50)),
        24: pose(**IDLE),
    }
    keyed("Mantle", 24, k, floor=False)
    NOTES["Mantle"] = ("in place: hands start on a ledge 1.9 above the feet and end at hip height while the game "
                       "lifts the root onto the ledge")


def c_seats():
    def passenger(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        z = 0.96
        return pose(hips=(12, 0, 0), spine=(3 + 0.6 * br, 0, 0), chest=(-4 + 0.8 * br, 0, 0),
                    head=(0, 8.0 * sin(w + 1.0), 0),
                    xl=(-0.12, 0.50, z - 0.27, 12, 4), xr=(0.12, 0.50, z - 0.27, 12, -4),
                    nl=(-0.2, 0.3, 1.0), nr=(0.2, 0.3, 1.0),
                    pl=(-0.13, 0.27, z + 0.17), pr=(0.13, 0.25, z + 0.17),
                    gl=(0.1, 0.9, -0.35, 0, -0.35, -1), gr=(-0.1, 0.9, -0.35, 0, -0.35, -1),
                    el=(-0.7, -0.6, -0.3), er=(0.7, -0.6, -0.3), floor=0.0)
    cyc("SitPassenger", 60, passenger)

    def bike(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        z = 0.96
        return pose(hips=(-28, 0, 0), spine=(-14 + 0.6 * br, 0, 0), chest=(-8 + 0.6 * br, 0, 0), head=(2, 0, 0),
                    xl=(-0.20, 0.03, z - 0.55, -15, 0), xr=(0.20, 0.03, z - 0.55, -15, 0),
                    nl=(-0.3, 1.0, 0.1), nr=(0.3, 1.0, 0.1),
                    pl=(-0.293, 0.693, z - 0.149), pr=(0.293, 0.693, z - 0.149),
                    gl=(0.1, 0.9, -0.4, 0, -0.3, -1), gr=(-0.1, 0.9, -0.4, 0, -0.3, -1),
                    el=(-0.8, -0.3, -0.6), er=(0.8, -0.3, -0.6), floor=0.0)
    cyc("SitBike", 60, bike)
    NOTES["SitBike"] = ("fitted to bike_sport: grips at (+-0.293, +0.693, -0.149) and pegs at (+-0.215, +0.073, "
                        "-0.645) relative to the Hips bone (= seat_driver marker)")

    def bench(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        return pose(dz=-0.38, hips=(8, 0, 0), spine=(2 + 0.6 * br, 0, 0), chest=(-7 + 0.8 * br, 0, 0),
                    head=(-2, 5.0 * sin(w + 1.0), 0),
                    fl=(0.035, 0.40, 0, 0, 6), fr=(0.045, 0.44, 0, 0, 10), fit=False,
                    pl=(-0.13, 0.27, 0.645), pr=(0.14, 0.24, 0.645),
                    gl=(0.15, 0.9, -0.2, 0, -0.2, -1), gr=(-0.15, 0.9, -0.2, 0, -0.2, -1),
                    el=(-0.7, -0.6, -0.3), er=(0.7, -0.6, -0.3))
    cyc("Sit", 60, bench)
    NOTES["Sit"] = "root on the ground, seat top 0.45 high under the Hips (Hips 0.58 above the ground)"

    idle_w = dict(wl=(-0.275, 0.035, 0.89), wr=(0.275, 0.035, 0.89), el=(-0.3, -1.0, 0.0), er=(0.3, -1.0, 0.0))
    tracks("Carjack", 20, {
        0: K(IDLE, **idle_w),
        5: K(dz=-0.08, dy=0.05, hips=(-14, 0, 0), spine=(-10, 0, 0), chest=(-6, 0, 0), head=(4, 0, 0),
             fl=(0.03, 0.16, 0, 0, 6), fr=(0.04, -0.10, 0, -15, 14),
             wl=(-0.14, 0.56, 1.14), wr=(0.14, 0.56, 1.18), el=(-0.6, -0.3, -0.8), er=(0.6, -0.3, -0.8)),
        8: K(wl=(-0.13, 0.58, 1.13), wr=(0.13, 0.58, 1.17), dy=0.06),
        13: K(dz=-0.10, dy=-0.07, dx=-0.03, hips=(4, 14, 0), spine=(2, 12, 0), chest=(2, 14, 0), head=(0, 20, 0),
              wl=(-0.42, 0.10, 1.05), wr=(-0.12, 0.24, 1.12), el=(-0.5, -0.8, -0.2), er=(0.7, -0.2, -0.7)),
        16: K(wl=(-0.46, -0.02, 1.00), wr=(-0.16, 0.16, 1.06)),
        20: K(IDLE, fl=(0.03, 0.16, 0, 0, 6), fr=(0.04, -0.10, 0, 0, 14), **idle_w),
    })


def c_melee2():
    st = dict(dz=-0.07, fl=(0.05, 0.13, 0, 0, 4), fr=(0.07, -0.13, 0, -10, 28), head=(-2, 0, 0))
    tracks("SwingBat", 16, {
        0: K(st, hips=(0, -8, 0), spine=(-2, -14, 0), chest=(-2, -16, 0), dx=0.02,
             sr=(0.24, 0.02, 1.36, 0.25, -0.45, 0.85, 0.0, 0.9, 0.45), two=0.10,
             er=(0.7, -0.5, -0.5), el=(-0.2, 0.3, -1.0)),
        4: K(hips=(0, -12, 0), spine=(-2, -18, 0), chest=(-2, -20, 0), dx=0.03,
             sr=(0.27, -0.04, 1.42, 0.35, -0.6, 0.72, 0.0, 0.8, 0.6)),
        7: K(hips=(0, 4, 0), spine=(-5, 4, 0), chest=(-4, 6, 0), dx=-0.01, dy=0.03,
             sr=(0.10, 0.45, 1.20, -0.45, 0.89, 0.0, 0.0, 0.0, 1.0), er=(0.7, -0.4, -0.6), el=(-0.6, -0.2, -0.8)),
        10: K(hips=(0, 14, 0), spine=(-4, 18, 0), chest=(-3, 22, 0), dx=-0.03, dy=0.03,
              sr=(-0.30, 0.26, 1.30, -0.85, -0.35, 0.3, 0.0, 0.3, 1.0), fr=(0.07, -0.13, 0, -30, 8),
              er=(0.3, 0.2, -1.0), el=(-0.7, -0.6, -0.3)),
        16: K(st, hips=(0, 0, 0), spine=(-2, -4, 0), chest=(-2, -6, 0), dx=0.0, dy=0.0,
              sr=(0.22, 0.20, 1.12, 0.0, 0.6, 0.8, 0.0, -0.8, 0.6), er=(0.7, -0.5, -0.5), el=(-0.5, -0.2, -0.9)),
    })
    NOTES["SwingBat"] = "two-handed: left hand 0.10 further along the item axis (weapon marker hand_l of `bat`)"
    lg = dict(wl=(-0.16, 0.22, 1.30), el=(-0.45, -0.3, -1.0), gl=GUARD["gl"])
    tracks("Stab", 12, {
        0: K(st, lg, spine=(-3, -6, 0), chest=(-3, -8, 0), sr=(0.20, 0.12, 1.10, 0, 1, 0.1, 0, 0, 1),
             er=(0.5, -0.8, -0.3)),
        3: K(spine=(-3, -12, 0), chest=(-3, -14, 0), sr=(0.25, -0.03, 1.12, 0.1, 1, 0.1, 0, 0, 1), dy=-0.01),
        6: K(hips=(0, 6, 0), spine=(-6, 10, 0), chest=(-5, 14, 0), dy=0.05,
             sr=(0.06, 0.68, 1.22, -0.05, 1, 0.1, 0, 0, 1), er=(0.7, -0.3, -0.6), wl=(-0.22, 0.12, 1.22)),
        8: K(sr=(0.06, 0.685, 1.22, -0.05, 1, 0.1, 0, 0, 1)),
        12: K(st, lg, hips=(0, 0, 0), spine=(-3, -6, 0), chest=(-3, -8, 0), dy=0.0,
              sr=(0.20, 0.12, 1.10, 0, 1, 0.1, 0, 0, 1), er=(0.5, -0.8, -0.3)),
    })
    tracks("Throw", 20, {
        0: K(st, spine=(-2, -6, 0), chest=(-2, -8, 0), wr=(0.24, 0.12, 1.22), er=(0.5, -0.8, -0.3),
             wl=(-0.20, 0.20, 1.16), el=(-0.5, -0.4, -0.8)),
        5: K(hips=(0, -8, 0), spine=(5, -16, 0), chest=(4, -18, 0), dy=-0.04, head=(0, 0, 0),
             wr=(0.34, -0.26, 1.60), er=(0.8, -0.3, -0.5), wl=(-0.12, 0.50, 1.40), el=(-0.5, -0.2, -0.9)),
        9: K(hips=(0, 2, 0), spine=(0, 2, 0), chest=(0, 4, 0), dy=0.0,
             wr=(0.26, 0.14, 1.84), er=(0.9, -0.3, 0.0), wl=(-0.20, 0.36, 1.28)),
        11: K(hips=(0, 8, 0), spine=(-8, 12, 0), chest=(-6, 16, 0), dy=0.05,
              wr=(0.12, 0.62, 1.56), er=(0.8, -0.2, -0.3), wl=(-0.26, 0.14, 1.18)),
        14: K(hips=(0, 10, 0), spine=(-14, 14, 0), chest=(-8, 18, 0), dy=0.06, fr=(0.07, -0.13, 0, -30, 10),
              wr=(-0.10, 0.44, 1.02), er=(0.6, -0.5, -0.4), wl=(-0.30, 0.02, 1.14)),
        20: K(st, hips=(0, 0, 0), spine=(-2, -2, 0), chest=(-2, -2, 0), dy=0.0,
              wr=(0.26, 0.10, 0.98), er=(0.4, -0.9, -0.1), wl=(-0.25, 0.10, 1.00), el=(-0.4, -0.9, -0.1)),
    })

    def block(t):
        w = 2.0 * pi * t / 30.0
        br = sin(w)
        return pose(**K(GUARD, dz=-0.08 + 0.004 * br, spine=(-8, -4, 0), chest=(-6 + 0.8 * br, -5, 0), head=(-8, 0, 0),
                        wl=(-0.10, 0.25, 1.50 + 0.004 * br), wr=(0.11, 0.22, 1.48 + 0.004 * br),
                        el=(-0.2, -0.2, -1.0), er=(0.2, -0.2, -1.0),
                        gl=(0.1, 0.1, 1, 1, 0.3, 0), gr=(-0.1, 0.1, 1, -1, 0.3, 0)))
    cyc("Block", 30, block)
    tracks("HitReact_B", 10, {
        0: IDLE,
        2: K(dz=-0.04, dy=0.06, hips=(-6, 0, 0), spine=(-14, -3, 0), chest=(-12, -4, 0), head=(14, 0, 0),
             al=(-32, 26, 0, 30), ar=(-26, 30, 0, 36), fr=(0.01, 0.0, 0, -12, 8)),
        5: K(dz=-0.04, dy=0.03, hips=(-3, 0, 0), spine=(-8, -1, 0), chest=(-6, -2, 0), head=(-4, 0, 0),
             al=(-10, 14, 4, 22), ar=(-8, 16, 4, 26), fr=FOOT0),
        10: IDLE,
    })


def c_downs():
    k = {
        0: pose(**IDLE),
        3: pose(dz=0.02, dy=-0.04, hips=(28, 0, 0), spine=(8, 0, 0), chest=(6, 0, 0), nk=(-10, 0, 0, -12, 0, 0),
                ll=(35, 25, -10, 6, 4), lr=(20, 40, -10, 6, 4), al=(60, 40, 0, 30), ar=(50, 50, 0, 35)),
        7: pose(dz=-0.35, dy=-0.12, hips=(68, 0, 0), spine=(4, 0, 0), chest=(2, 0, 0), nk=(-14, 0, 0, -14, 0, 0),
                ll=(55, 30, -15, 8, 6), lr=(40, 45, -15, 8, 6), al=(100, 45, 0, 25), ar=(95, 55, 0, 25)),
        11: pose(dy=-0.18, hips=(98, 0, 0), spine=(-4, 0, 0), chest=(-4, 0, 0), nk=(-8, 0, 0, -10, 0, 0),
                 ll=(60, 50, -10, 10, 8), lr=(50, 60, -10, 10, 8), al=(30, 60, -40, 40), ar=(30, 65, -40, 40),
                 floor=0.0),
        15: pose(dy=-0.20, hips=(88, 0, 0), spine=(0, 0, 0), chest=(-2, 0, 0), nk=(0, 0, 0, 0, 0, 0),
                 ll=(25, 35, -20, 9, 9), lr=(30, 42, -20, 10, 12), al=(0, 46, -40, 30), ar=(0, 52, -45, 35),
                 floor=0.0),
        20: pose(**LYING),
    }
    keyed("Knockdown", 20, k)
    feet = dict(fl=(0.05, 0.10, 0, 0, 10), fr=(0.05, 0.02, 0, 0, 12))
    k = {
        0: pose(**LYING),
        5: pose(dy=-0.18, hips=(72, 0, 0), spine=(-14, 0, 0), chest=(-14, 0, 0), nk=(-10, 0, 0, -8, 0, 0),
                ll=(40, 70, -5, 8, 8), lr=(46, 80, -5, 8, 8), al=(-25, 28, -20, 22), ar=(-25, 30, -20, 22),
                floor=0.0),
        10: pose(dy=-0.12, hips=(35, 0, 0), spine=(-22, 0, 0), chest=(-18, 0, 0), head=(-5, 0, 0),
                 ll=(75, 115, 10, 8, 8), lr=(78, 120, 10, 8, 8), al=(20, 20, 0, 40), ar=(-30, 25, -10, 15),
                 floor=0.0),
        15: pose(dz=-0.50, dy=-0.05, hips=(-22, 0, 0), spine=(-20, 0, 0), chest=(-10, 0, 0), head=(0, 0, 0),
                 al=(35, 15, 5, 45), ar=(35, 15, 5, 45), **feet),
        22: pose(dz=-0.22, dy=-0.02, hips=(-26, 0, 0), spine=(-12, 0, 0), chest=(-6, 0, 0), head=(0, 0, 0),
                 al=(15, 8, 5, 30), ar=(15, 8, 5, 30), **feet),
        30: pose(**K(IDLE, **feet)),
    }
    keyed("GetUp", 30, k)
    k = {
        0: pose(**IDLE),
        3: pose(**K(IDLE, dz=-0.04, dy=0.03, hips=(-6, 0, -2), spine=(6, 0, 0), chest=(8, -4, 0), head=(14, 0, 0),
                    al=(-20, 25, 0, 30), ar=(-30, 30, 0, 25))),
        8: pose(**KNEEL_FALL),
        13: pose(dy=0.14, hips=(-50, 0, 0), spine=(-8, 0, 0), chest=(-4, 0, 0), nk=(8, 0, 0, 10, 0, 0),
                 ll=(52, 95, -45, 4, 0), lr=(48, 90, -45, 6, 0), al=(60, 25, 10, 50), ar=(70, 30, 10, 45), floor=0.0),
        18: pose(**K(PRONE, hips=(-88, 0, 0), nk=(0, 20, 0, 0, 30, 0), ll=(8, 25, -60, 6, 8), lr=(5, 14, -60, 8, 10),
                     al=(14, 30, -20, 30), ar=(14, 95, -80, 70))),
        24: pose(**PRONE),
    }
    keyed("Death_Front", 24, k)
    neck = dict(wl=(-0.09, 0.15, 1.47), wr=(0.10, 0.15, 1.45), el=(-0.8, -0.2, -0.8), er=(0.8, -0.2, -0.8))
    toes = dict(fl=(0.01, 0, 0, -12, 8), fr=(0.01, 0, 0, -12, 8))
    k = {
        0: pose(**IDLE),
        4: pose(**K(IDLE, toes, neck, dz=0.0, hips=(4, 0, 0), spine=(10, 0, 0), chest=(10, 0, 0), head=(20, 0, 0))),
        9: pose(**K(IDLE, toes, neck, dz=0.0, dy=-0.03, hips=(5, 0, 0), spine=(10, 0, 0), chest=(12, 4, 0),
                    head=(22, -6, 0))),
        13: pose(**K(IDLE, dz=-0.03, dy=0.0, hips=(2, 0, 0), spine=(14, 0, 0), chest=(8, -6, 0), head=(10, 0, 8),
                     wl=(-0.16, 0.20, 1.30), wr=(0.18, 0.18, 1.28), el=(-0.8, -0.2, -0.8), er=(0.8, -0.2, -0.8))),
        18: pose(**K(KNEEL_FALL, al=(8, 10, 0, 15), ar=(6, 12, 0, 18))),
        21: pose(dy=0.14, hips=(-55, 0, 0), spine=(-8, 0, 0), chest=(-4, 0, 0), nk=(6, 0, 0, 8, 0, 0),
                 ll=(52, 95, -45, 4, 0), lr=(48, 90, -45, 6, 0), al=(40, 20, 10, 30), ar=(45, 25, 10, 30), floor=0.0),
        24: pose(**K(PRONE, al=(6, 30, -20, 25), ar=(6, 40, -30, 35), nk=(-4, -30, 0, -4, -42, 0))),
    }
    keyed("TakedownVictim", 24, k)
    st = dict(dz=-0.08, fl=(0.03, 0.14, 0, 0, 4), fr=(0.05, -0.14, 0, -15, 25))
    tracks("Takedown", 24, {
        0: K(st, dy=0.0, spine=(-4, 0, 0), chest=(-3, 0, 0), head=(-4, 0, 0),
             wl=(-0.22, 0.20, 1.18), wr=(0.24, 0.12, 1.14), el=(-0.5, -0.5, -0.7), er=(0.5, -0.5, -0.7)),
        5: K(dy=0.05, spine=(-6, 6, 0), chest=(-4, 8, 0), wl=(0.10, 0.44, 1.46), el=(-0.8, 0.2, 0.3),
             wr=(0.30, -0.02, 1.22), er=(0.6, -0.8, -0.3)),
        9: K(dy=0.0, spine=(2, 4, 0), chest=(2, 6, 0), wl=(0.08, 0.30, 1.44), wr=(0.30, -0.06, 1.20)),
        13: K(spine=(-2, 8, 0), chest=(-2, 12, 0), wr=(0.10, 0.40, 1.16), er=(0.7, -0.4, -0.5)),
        16: K(wr=(0.10, 0.41, 1.16), wl=(0.08, 0.30, 1.44), el=(-0.8, 0.2, 0.3)),
        20: K(dz=-0.12, spine=(-14, 0, 0), chest=(-10, 0, 0), head=(-18, 0, 0), wl=(-0.10, 0.40, 1.00),
              wr=(0.14, 0.42, 0.98), el=(-0.6, -0.4, -0.6), er=(0.6, -0.4, -0.6)),
        24: K(dz=-0.08, spine=(-4, 0, 0), chest=(-3, 0, 0), head=(-4, 0, 0), wl=(-0.22, 0.20, 1.18),
              wr=(0.24, 0.12, 1.14), el=(-0.5, -0.5, -0.7), er=(0.5, -0.5, -0.7)),
    })
    NOTES["Takedown"] = "attacker stands ~0.40 behind the victim (victim's neck at +0.40 Y, 1.48 high)"
    NOTES["TakedownVictim"] = "ends face-down (same rest pose as Death_Front)"


def c_cover():
    def low(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        g = Vector((0.13, 0.19, 1.02 + 0.004 * br))
        return pose(dz=-0.40 + 0.003 * br, hips=(4, 0, 0), spine=(-2 + 0.6 * br, 0, 0), chest=(-2 + 0.6 * br, 0, 0),
                    head=(0, 26 + 8 * sin(w - 1.0), 0), fl=(0.05, 0.22, 0, 0, 10), fr=(0.05, 0.18, 0, 0, 12), fit=False,
                    sr=(g.x, g.y, g.z, 0.0, 0.15, 1.0, 0.0, -1.0, 0.2), er=(0.7, -0.2, -0.7),
                    pl=(g.x - 0.045, g.y + 0.005, g.z - 0.03), gl=(0.55, 0.3, 0.75, 1.0, -0.2, 0.0),
                    el=(-0.7, -0.1, -0.7))
    cyc("CoverLow", 60, low)

    def high(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        g = Vector((0.15, 0.16, 1.40 + 0.004 * br))
        return pose(dz=-0.03 + 0.003 * br, hips=(3, 0, 0), spine=(0.6 * br, 0, 0), chest=(-1 + 0.6 * br, 0, 0),
                    head=(0, -38 + 6 * sin(w - 1.0), 0), fl=(0.03, 0.08, 0, 0, 10), fr=(0.04, 0.05, 0, 0, 12),
                    sr=(g.x, g.y, g.z, 0.0, 0.15, 1.0, 0.0, -1.0, 0.2), er=(0.8, -0.3, -0.6),
                    pl=(g.x - 0.045, g.y + 0.005, g.z - 0.03), gl=(0.55, 0.3, 0.75, 1.0, -0.2, 0.0),
                    el=(-0.7, -0.1, -0.7))
    cyc("CoverHigh", 60, high)
    NOTES["CoverLow"] = "back to a wall ~0.14 behind the Hips; weapon held muzzle-up at the chest"
    NOTES["CoverHigh"] = NOTES["CoverLow"]


def c_misc():
    def hands_up(t):
        w = 2.0 * pi * t / 40.0
        s1 = sin(w)
        return pose(dz=-0.015 + 0.003 * s1, dx=0.006 * sin(w - 1.0), chest=(1.0 * s1, 0, 0), head=(2, 0, 0),
                    wl=(-0.34, 0.06, 1.74 + 0.008 * sin(2 * w)), wr=(0.34, 0.06, 1.74 + 0.008 * sin(2 * w + 1.0)),
                    el=(-1.0, -0.1, -0.4), er=(1.0, -0.1, -0.4), gl=(0, 0, 1, 0, 1, 0), gr=(0, 0, 1, 0, 1, 0))
    cyc("HandsUp", 40, hands_up)

    def cower(t):
        w = 2.0 * pi * t / 30.0
        tr = sin(5.0 * w)                              # tremble
        return pose(dz=-0.42 + 0.004 * tr, dy=-0.05, hips=(-30, 0, 0), spine=(-22, 1.2 * tr, 0),
                    chest=(-15, 1.5 * tr, 0), head=(-38, 2.0 * sin(w), 0),
                    fl=(0.03, 0.10, 0, 0, 8), fr=(0.04, -0.06, 0, -24, 12),
                    wl=(-0.12, 0.36 + 0.004 * tr, 1.10 + 0.006 * tr), wr=(0.12, 0.36 - 0.004 * tr, 1.10 - 0.006 * tr),
                    el=(-0.8, 0.5, -0.3), er=(0.8, 0.5, -0.3),
                    gl=(0.6, 0.0, 0.6, 0.3, 0.1, -1), gr=(-0.6, 0.0, 0.6, -0.3, 0.1, -1))
    cyc("Cower", 30, cower, step=1)

    def surrender(t):
        w = 2.0 * pi * t / 40.0
        br = sin(w)
        z = 0.52
        return pose(dz=-0.44, hips=(2, 0, 0), spine=(1 + 0.5 * br, 0, 0), chest=(2 + 0.8 * br, 0, 0), head=(-8, 0, 0),
                    ll=(2, 92, -50, 4, 0), lr=(2, 92, -50, 4, 0),
                    wl=(-0.11, -0.11, z + 0.70), wr=(0.11, -0.11, z + 0.70),
                    el=(-1.0, -0.1, 0.1), er=(1.0, -0.1, 0.1), floor=0.0)
    cyc("Surrender", 40, surrender)

    def phone_call(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        return pose(dz=-0.012 + 0.003 * br, dx=0.008 * sin(w - 1.1), hips=(0, 0, 0.8 * sin(w - 1.1)),
                    chest=(1.0 * br, 0, 0), head=(-2 + 1.5 * sin(2 * w), 4, -6),
                    pr=(0.125, 0.035, 1.655 + 0.003 * br), gr=(-0.1, 0.15, 1.0, -1.0, 0.0, 0.0), er=(0.5, 0.3, -1.0),
                    al=(2, 3, 8, 12 + 2 * br))
    cyc("PhoneCall", 60, phone_call)

    def phone_use(t):
        w = 2.0 * pi * t / 60.0
        br = sin(w)
        tap = 0.006 * sin(6.0 * w)
        return pose(dz=-0.012 + 0.003 * br, dx=0.006 * sin(w - 1.1), spine=(-2, 0, 0), chest=(-3 + 0.8 * br, 0, 0),
                    head=(-28 + 1.0 * br, 0, 0),
                    pr=(0.07, 0.30, 1.24 + 0.003 * br), gr=(-0.35, 0.45, 0.82, -0.2, -0.8, 0.55), er=(0.6, -0.5, -0.7),
                    pl=(-0.03, 0.29 + tap, 1.215 + tap), gl=(0.5, 0.5, 0.7, 0.4, -0.6, 0.6), el=(-0.6, -0.5, -0.7))
    cyc("PhoneUse", 60, phone_use)
    lo = (-0.26, 0.08, 0.92)
    tracks("Talk", 80, {
        0: K(IDLE, wr=(0.22, 0.28, 1.12), er=(0.5, -0.7, -0.5), gr=(-0.2, 0.9, 0.3, -0.6, 0, 0.8),
             wl=lo, el=(-0.3, -1.0, 0.0), head=(0, 0, 0), chest=(0, 0, 0), dx=0.0),
        12: K(wr=(0.32, 0.34, 1.22), gr=(0.1, 0.9, 0.35, -0.3, 0, 1.0), head=(2, -4, 0), chest=(0, -3, 0)),
        24: K(wr=(0.22, 0.30, 1.14), gr=(-0.2, 0.9, 0.3, -0.6, 0, 0.8), wl=(-0.27, 0.20, 1.04), head=(-3, 0, 0),
              dx=0.008),
        38: K(wr=(0.17, 0.34, 1.30), gr=(-0.1, 0.5, 0.85, -0.8, 0.2, 0.1), wl=(-0.30, 0.26, 1.10), head=(1, 5, 0),
              chest=(0, 3, 0)),
        50: K(wr=(0.24, 0.30, 1.16), gr=(-0.2, 0.9, 0.3, -0.6, 0, 0.8), wl=(-0.27, 0.16, 1.00), head=(-2, 0, 2)),
        64: K(wr=(0.28, 0.26, 1.08), wl=lo, head=(0, -3, 0), chest=(0, -2, 0), dx=-0.006),
    }, loop=True, interp="spline", step=2)
    up = (0.0, 0.1, 1.0, 0.0, 1.0, 0.0)
    tracks("Wave", 30, {
        0: K(IDLE, wr=(0.275, 0.035, 0.89), er=(0.3, -1.0, 0.0), gr=(0.05, 0.0, -1.0, -1.0, 0.0, 0.0), head=(0, 0, 0)),
        7: K(wr=(0.44, 0.12, 1.78), er=(1.0, -0.2, -0.5), gr=up, head=(4, -6, 0), chest=(0, -3, -2)),
        11: K(wr=(0.30, 0.12, 1.80)),
        15: K(wr=(0.50, 0.12, 1.74)),
        19: K(wr=(0.30, 0.12, 1.80)),
        23: K(wr=(0.48, 0.12, 1.75), er=(1.0, -0.2, -0.5), gr=up, head=(4, -6, 0), chest=(0, -3, -2)),
        30: K(IDLE, wr=(0.275, 0.035, 0.89), er=(0.3, -1.0, 0.0), gr=(0.05, 0.0, -1.0, -1.0, 0.0, 0.0), head=(0, 0, 0)),
    })

    def chute(t):
        w = 2.0 * pi * t / 40.0
        s1 = sin(w)
        return pose(hips=(3 + 2 * s1, 0, 3 * sin(w - 0.8)), spine=(-2, 0, -1.5 * sin(w - 0.8)), chest=(2, 0, 0),
                    head=(-10, 0, 0),
                    ll=(22 - 4 * s1, 28 + 5 * s1, -15, 4, 2), lr=(30 - 4 * sin(w - 0.5), 38 + 5 * sin(w - 0.5), -15, 5, 4),
                    wl=(-0.30, 0.02, 1.86 + 0.01 * s1), wr=(0.30, 0.02, 1.86 - 0.01 * s1),
                    el=(-1.0, 0.1, -0.3), er=(1.0, 0.1, -0.3), gl=(0, 0, 1, 1, 0.3, 0), gr=(0, 0, 1, -1, 0.3, 0))
    cyc("Parachute", 40, chute)
    NOTES["Parachute"] = "hands on toggles 0.43 above the shoulders (canopy risers meet at the shoulders)"

    def freefall(t):
        w = 2.0 * pi * t / 30.0
        fl_ = sin(3.0 * w)
        f2 = sin(3.0 * w + 1.3)
        return pose(dz=0.01 * sin(w), hips=comp((-82, 0, 0), (0, 1.5 * sin(w), 0)), spine=(8, 0, 0), chest=(10, 0, 0),
                    head=(-22, 0, 0),
                    ll=(-12 + 2.5 * fl_, 62 + 4 * f2, -20, 22, 6), lr=(-12 - 2.5 * fl_, 58 - 4 * f2, -20, 22, 6),
                    al=(-10 + 3 * f2, 85, -80, 85 + 4 * fl_), ar=(-10 - 3 * f2, 85, -80, 85 - 4 * fl_))
    cyc("Freefall", 30, freefall, step=1)


# --------------------------------------------------------------------------- QA helpers
def debug_prop(on=True, length=0.6, asset_id=N.RIG_ASSET):
    """QA only: `<id>__dbg_prop`, a stick skinned to Prop_R showing the held item's axes (long = forward,
    fin = top) plus a small block in the left palm. chr_export removes it before every export."""
    import bpy
    R.remove_part(asset_id, "dbg_prop")
    R.remove_part(asset_id, "dbg_prop_l")
    if not on:
        return None
    import gta_kit as KIT
    root = bpy.data.objects[asset_id]
    rig = R.get_rig(asset_id)
    # the sockets are non-deforming bones -> bone-parent the helper (mesh in bone axes: -Z forward, +Y top)
    mb = KIT.MB()
    mb.box((0.03, 0.03, length), (0.0, 0.0, -(length * 0.5 - 0.10)), "red")
    mb.box((0.012, 0.07, 0.10), (0.0, 0.045, -0.02), "yellow")
    obj = mb.to_object(root, "dbg_prop")
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = "Prop_R"
    obj.location = (0.0, -R.BONE_LENGTH, 0.0)
    R.remove_part(asset_id, "dbg_prop_l")
    mb = KIT.MB()
    mb.box((0.04, 0.04, 0.06), (0.0, 0.0, 0.0), "cyan")
    ol = mb.to_object(root, "dbg_prop_l")
    ol.parent = rig
    ol.parent_type = "BONE"
    ol.parent_bone = "Prop_L"
    ol.location = (0.0, -R.BONE_LENGTH, 0.0)
    return obj


def review(specs):
    """QA: temp action with one pose per frame; specs = [(clip, frame), ...]. Look at frames 0..n-1."""
    return N.preview_poses([N.sample(c, f) for c, f in specs])


def show(clip_name, frame):
    """QA: apply one sampled pose statically to the rig (no action) for `look` mode 'angles'."""
    N.preview(None)
    rig = N._get_rig()
    R.set_pose(rig, N.sample(clip_name, frame))


CORE = [c_idle, c_gaits, c_crouch_idle, c_air, c_sit_car, c_aim, c_melee, c_death_back, c_swim]
EXTRA = [c_roll, c_water, c_ladder, c_traverse, c_seats, c_melee2, c_downs, c_cover, c_misc]


def define_all():
    SPEED.clear()
    NOTES.clear()
    for fn in CORE + EXTRA:
        fn()
