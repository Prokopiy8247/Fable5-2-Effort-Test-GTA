"""gta_bl - shared Blender helper library for the Halcyon Bay asset pipeline.

OWNED BY THE LEAD. Asset authors must NOT edit this file (several agents share one live Blender);
put extra helpers in your own module under tools/blender/assets/.

Usage inside every script sent through the Blender MCP `execute_blender_code` tool:

    import sys, importlib
    P = r"G:\\YouTube\\Fable 5.2 Effort Test GTA\\Ultracode\\tools\\blender"
    if P not in sys.path: sys.path.append(P)
    import gta_bl as G; importlib.reload(G)
    G.assert_master()

Conventions (see docs/ARCHITECTURE.md, "Blender asset contract"):
  * 1 Blender unit = 1 m. Z up. Assets FACE +Y in Blender (=> -Z "forward" in Godot after glTF export).
  * Every asset = one root Empty (named like the asset) placed at its authoring SLOT; all parts are
    children with clean names. export_glb() moves the root to the origin temporarily.
  * Never rely on selection / active object / edit mode between two MCP calls. Use data API + bmesh.
  * Never delete or modify objects outside your own asset roots. Never purge orphans globally.
"""
import bpy
import bmesh
import math
import os
import re
from mathutils import Vector, Matrix, Euler

EXPECTED_BLEND = "GodotFable5.2GTAUltracode.blend"
PROJECT_DIR = os.path.dirname(bpy.data.filepath)
MODELS_DIR = os.path.join(PROJECT_DIR, "gta", "generated", "models")
PREVIEW_DIR = os.path.join(PROJECT_DIR, "qa", "blender_previews")
ROOT_COLLECTION = "GTA_GODOT"

# Authoring slots: region -> (origin, step along X, row step along Y, per row)
REGIONS = {
    "characters": ((0.0, 0.0, 0.0), 4.0, 6.0, 12),
    "weapons": ((0.0, -40.0, 0.0), 2.5, 3.0, 12),
    "props": ((0.0, -80.0, 0.0), 6.0, 8.0, 12),
    "nature": ((0.0, -160.0, 0.0), 12.0, 14.0, 10),
    "animals": ((0.0, -230.0, 0.0), 5.0, 6.0, 10),
    "misc": ((0.0, -280.0, 0.0), 20.0, 25.0, 8),
    "cars": ((0.0, 40.0, 0.0), 10.0, 14.0, 10),
    "service": ((0.0, 90.0, 0.0), 14.0, 18.0, 8),
    "bikes": ((0.0, 150.0, 0.0), 6.0, 8.0, 10),
    "boats": ((0.0, 190.0, 0.0), 20.0, 25.0, 6),
    "aircraft": ((0.0, 260.0, 0.0), 35.0, 40.0, 6),
    "interiors": ((0.0, 420.0, 0.0), 30.0, 30.0, 8),
    "buildings": ((0.0, 600.0, 0.0), 70.0, 80.0, 8),
    "landmarks": ((0.0, 1300.0, 0.0), 90.0, 100.0, 6),
    "kit": ((-400.0, 0.0, 0.0), 8.0, 10.0, 10),
}


# ------------------------------------------------------------------------------------------------
# basics
# ------------------------------------------------------------------------------------------------
def assert_master():
    """Abort unless this Blender instance has the benchmark master file open."""
    fp = bpy.data.filepath
    if os.path.basename(fp) != EXPECTED_BLEND:
        raise RuntimeError("WRONG BLEND FILE OPEN: %r (expected %s) - stop and report." % (fp, EXPECTED_BLEND))
    return fp


def object_mode():
    """Force object mode without depending on the active object."""
    try:
        if bpy.context.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
    except Exception:
        pass


def slot(region, index=0):
    """World location of authoring slot `index` in `region` (see REGIONS)."""
    origin, step, row_step, per_row = REGIONS[region]
    row = index // per_row
    colm = index % per_row
    return Vector((origin[0] + colm * step, origin[1] + row * row_step, origin[2]))


def col(path):
    """Get/create nested collection under GTA_GODOT, e.g. col("Vehicles/Cars")."""
    scene = bpy.context.scene
    root = bpy.data.collections.get(ROOT_COLLECTION)
    if root is None:
        root = bpy.data.collections.new(ROOT_COLLECTION)
        scene.collection.children.link(root)
    parent = root
    if not path:
        return root
    for part in [p for p in path.split("/") if p]:
        child = parent.children.get(part)
        if child is None:
            child = bpy.data.collections.get(part)
            if child is None:
                child = bpy.data.collections.new(part)
            if child.name not in parent.children:
                parent.children.link(child)
        parent = child
    return parent


def link(ob, collection):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    collection.objects.link(ob)
    return ob


def delete_hierarchy(root_name):
    """Delete an asset root and all its descendants (use to rebuild YOUR OWN asset)."""
    root = bpy.data.objects.get(root_name)
    if root is None:
        return 0
    objs = [root] + list(root.children_recursive)
    n = 0
    for o in objs:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        n += 1
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Armature):
                bpy.data.armatures.remove(data)
    return n


def asset_root(name, collection_path, location=(0, 0, 0), rebuild=True):
    """Create the root Empty of an asset at its slot. With rebuild=True an existing asset of the
    same name is deleted first, so scripts are re-runnable."""
    object_mode()
    if rebuild:
        delete_hierarchy(name)
    c = col(collection_path)
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = 'PLAIN_AXES'
    ob.empty_display_size = 0.5
    ob.location = Vector(location)
    c.objects.link(ob)
    return ob


def empty(name, parent, location=(0, 0, 0), rotation=(0, 0, 0), size=0.15, display='ARROWS'):
    """Marker Empty (seat, muzzle, light position ...) parented to `parent`; local transform."""
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = display
    ob.empty_display_size = size
    for c in parent.users_collection:
        c.objects.link(ob)
        break
    ob.parent = parent
    ob.location = Vector(location)
    ob.rotation_euler = Euler(rotation, 'XYZ')
    return ob


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
def _principled(m):
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    node = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if node is None:
        nt.nodes.clear()
        node = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        out.location = (300, 0)
        nt.links.new(node.outputs[0], out.inputs[0])
    return node


def _sock(node, identifier_or_name):
    for s in node.inputs:
        if s.identifier == identifier_or_name or s.name == identifier_or_name:
            return s
    return None


def mat(name, color=(0.8, 0.8, 0.8), rough=0.6, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0, update=False):
    """Get-or-create a flat-colour Principled material (the project uses palette colours, no image
    textures). Existing materials are reused unchanged unless update=True.
    emit: optional (r,g,b) emission colour; emit_strength in Blender units (Godot multiplies it)."""
    m = bpy.data.materials.get(name)
    existed = m is not None
    if m is None:
        m = bpy.data.materials.new(name)
    if existed and not update:
        return m
    node = _principled(m)
    rgba = (color[0], color[1], color[2], 1.0)
    s = _sock(node, 'Base Color')
    if s: s.default_value = rgba
    s = _sock(node, 'Roughness')
    if s: s.default_value = rough
    s = _sock(node, 'Metallic')
    if s: s.default_value = metal
    s = _sock(node, 'Alpha')
    if s: s.default_value = alpha
    if emit is not None:
        s = _sock(node, 'Emission Color') or _sock(node, 'Emission')
        if s: s.default_value = (emit[0], emit[1], emit[2], 1.0)
        s = _sock(node, 'Emission Strength')
        if s: s.default_value = emit_strength
    m.diffuse_color = (color[0], color[1], color[2], alpha)
    m.roughness = rough
    m.metallic = metal
    if alpha < 0.999:
        for attr, val in (("surface_render_method", 'BLENDED'), ("blend_method", 'BLEND')):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    m.use_fake_user = True
    return m


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    """'#RRGGBB' (sRGB, as you would pick it on screen) -> linear (r,g,b) for Blender/glTF."""
    h = h.lstrip('#')
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


# Art-direction palette ("Sunlit Low-Poly"). sRGB hex. Use pmat("Coral") for a shared palette
# material named P_Coral; use mat("M_Paint_Primary", hexc(PALETTE["CarRed"])) for contract materials.
PALETTE = {
    # world / ground
    "Asphalt": "#2F3542", "AsphaltLight": "#474E5C", "RoadLine": "#F2EDE0", "RoadLineYellow": "#F0C246",
    "Sidewalk": "#CFC8B8", "Curb": "#A9A292", "Concrete": "#BDB7AB", "ConcreteDark": "#8D887F",
    "Sand": "#EBD9A8", "Dirt": "#9C7C56", "Rock": "#8E877A", "RockDark": "#6B665D",
    "Grass": "#7CBB5E", "GrassDark": "#4F9A4C", "Leaf": "#5DAA55", "LeafLight": "#8FCB6B", "LeafDark": "#3F8246",
    "Palm": "#6FB36A", "Trunk": "#7A5A3C", "TrunkLight": "#A07C55", "Wood": "#B08556", "WoodDark": "#7B5637",
    # architecture
    "Cream": "#F3E7D0", "Peach": "#F4B78D", "Coral": "#EE7E64", "Terracotta": "#C95A41", "Brick": "#B35A42",
    "Mint": "#A2D9C2", "Sky": "#8FCAE8", "Teal": "#22A7A0", "Navy": "#27405F", "White": "#F5F3EE",
    "WarmGrey": "#B9B1A5", "Charcoal": "#3B404B", "Black": "#1C1E23", "Mustard": "#E2B13C", "Olive": "#8A9A5B",
    "Lavender": "#B7A6E0", "Rose": "#E89AAE", "Steel": "#8E99A6", "SteelDark": "#5B6470", "Rust": "#A8562F",
    "RoofRed": "#B8493A", "RoofGrey": "#5C6370", "Window": "#6FB8D2", "WindowDark": "#2C4A63", "Awning": "#E4572E",
    # metals / vehicle
    "Chrome": "#D5DAE0", "Rim": "#C3C8CF", "Tire": "#17181C", "Trim": "#24262C", "Interior": "#3A3532",
    "CarRed": "#D8342C", "CarBlue": "#2C6FD9", "CarYellow": "#F2C331", "CarWhite": "#F1F1EE", "CarBlack": "#1B1D22",
    "CarSilver": "#BFC5CC", "CarGreen": "#2F9E5C", "CarOrange": "#F0802F", "CarTeal": "#1FA7A0", "CarPurple": "#7A50D0",
    "PoliceBlue": "#1E3A6E", "PoliceWhite": "#F4F5F7", "TaxiYellow": "#F5C518", "AmbulanceWhite": "#F6F6F2",
    "FireRed": "#C62A22", "SafetyOrange": "#F26B1D", "HazardYellow": "#F5D216",
    # emissive
    "NeonMagenta": "#FF3DA6", "NeonCyan": "#2DE2E6", "NeonYellow": "#FFD23F", "NeonOrange": "#FF8A3D",
    "NeonGreen": "#4ADE80", "NeonBlue": "#4D8CFF", "LampWarm": "#FFD9A0", "HeadlightWhite": "#FFF6E0",
    "TailRed": "#E0251B", "IndicatorAmber": "#FFA61A", "SirenRed": "#FF2B2B", "SirenBlue": "#2B6BFF",
    # characters
    "SkinA": "#F2C9A5", "SkinB": "#DDA77B", "SkinC": "#B97C54", "SkinD": "#8A5636", "SkinE": "#5E3A26",
    "HairBlack": "#22201F", "HairBrown": "#5A3A25", "HairBlonde": "#D9B56A", "HairRed": "#A6452A", "HairGrey": "#9A9A98",
    "Denim": "#3F5F8F", "Khaki": "#BFA77A", "ShirtWhite": "#EFEDE6", "ShirtRed": "#C8443A", "ShirtBlue": "#3F7FC8",
    "ShirtGreen": "#4E9A63", "ShirtYellow": "#E8C24A", "Leather": "#4A3426", "ShoeDark": "#2A2A2E", "ShoeWhite": "#E9E7E1",
    "UniformNavy": "#1F2E4D", "TacticalBlack": "#202328", "BadgeGold": "#D9B34A",
    # weapons
    "GunMetal": "#3A3D44", "GunMetalDark": "#25272C", "GunPolymer": "#2B2C2F", "GunWood": "#8A5A34", "GunTan": "#B49B6C",
    "Brass": "#C9A04A", "OliveDrab": "#5F6B45",
}


def pal(key):
    """Linear RGB tuple of a palette colour."""
    return hexc(PALETTE[key])


def pmat(key, rough=0.7, metal=0.0, emit_strength=0.0, alpha=1.0):
    """Shared palette material 'P_<key>'. Emissive if emit_strength > 0 (colour = palette colour)."""
    c = pal(key)
    return mat("P_" + key, c, rough=rough, metal=metal, emit=c if emit_strength > 0 else None,
               emit_strength=emit_strength, alpha=alpha)


# ------------------------------------------------------------------------------------------------
# bmesh geometry builders (all take an open bmesh and append to it)
# ------------------------------------------------------------------------------------------------
def bm_new():
    return bmesh.new()


def _rot_matrix(rot):
    if rot is None:
        return Matrix.Identity(4)
    if isinstance(rot, Matrix):
        return rot.to_4x4()
    return Euler(rot, 'XYZ').to_matrix().to_4x4()


def _assign(verts, mat_index):
    faces = set()
    for v in verts:
        for f in v.link_faces:
            faces.add(f)
    for f in faces:
        f.material_index = mat_index
    return faces


def add_box(bm, size, center=(0, 0, 0), rot=None, mat_index=0):
    """Axis aligned box of `size` (x,y,z) centred at `center`, optional euler rotation (radians)."""
    M = Matrix.Translation(Vector(center)) @ _rot_matrix(rot) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    _assign(ret['verts'], mat_index)
    return ret['verts']


def add_cylinder(bm, radius, depth, center=(0, 0, 0), axis='Z', segments=16, mat_index=0, radius2=None, rot=None, cap=True):
    """Cylinder / cone frustum along `axis` ('X','Y','Z'). radius2 = top radius (defaults to radius)."""
    r2 = radius if radius2 is None else radius2
    A = Matrix.Identity(4)
    if axis == 'X':
        A = Matrix.Rotation(math.pi / 2, 4, 'Y')
    elif axis == 'Y':
        A = Matrix.Rotation(-math.pi / 2, 4, 'X')
    M = Matrix.Translation(Vector(center)) @ _rot_matrix(rot) @ A
    ret = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments,
                                radius1=radius, radius2=r2, depth=depth, matrix=M)
    _assign(ret['verts'], mat_index)
    return ret['verts']


def add_sphere(bm, radius, center=(0, 0, 0), segments=12, rings=8, mat_index=0, scale=(1, 1, 1), rot=None):
    """UV sphere, optionally squashed with `scale`."""
    M = Matrix.Translation(Vector(center)) @ _rot_matrix(rot) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius, matrix=M)
    _assign(ret['verts'], mat_index)
    return ret['verts']


def add_poly(bm, points, mat_index=0):
    """Single n-gon from world-space points (counter-clockwise seen from the front)."""
    vs = [bm.verts.new(Vector(p)) for p in points]
    f = bm.faces.new(vs)
    f.material_index = mat_index
    return vs


def add_loft(bm, sections, mat_index=0, cap_start=True, cap_end=True, close_ring=True):
    """Skin a list of cross-sections. Every section is a list of (x,y,z) points with the SAME
    count and winding. Great for car bodies, hulls, fuselages, limbs. Returns the vert rings."""
    rings = [[bm.verts.new(Vector(p)) for p in sec] for sec in sections]
    n = len(rings[0])
    faces = []
    last = n if close_ring else n - 1
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(last):
            j = (i + 1) % n
            try:
                faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
            except ValueError:
                pass
    if cap_start and close_ring and n >= 3:
        try:
            faces.append(bm.faces.new(list(reversed(rings[0]))))
        except ValueError:
            pass
    if cap_end and close_ring and n >= 3:
        try:
            faces.append(bm.faces.new(rings[-1]))
        except ValueError:
            pass
    for f in faces:
        f.material_index = mat_index
    return rings


def add_prism(bm, profile, lo, hi, axis='X', mat_index=0):
    """Extrude a 2D polygon `profile` between coordinates lo..hi along `axis`.
    axis 'X': profile points are (y, z); 'Y': (x, z); 'Z': (x, y)."""
    def p3(p, t):
        if axis == 'X':
            return (t, p[0], p[1])
        if axis == 'Y':
            return (p[0], t, p[1])
        return (p[0], p[1], t)
    return add_loft(bm, [[p3(p, lo) for p in profile], [p3(p, hi) for p in profile]], mat_index=mat_index)


def add_tapered_box(bm, bottom, top, height, center=(0, 0, 0), top_offset=(0, 0), mat_index=0):
    """Box whose top rectangle differs from the bottom one (cabins, roofs, wedges).
    bottom/top = (size_x, size_y); `center` is the centre of the BOTTOM face."""
    cx, cy, cz = center
    bx, by = bottom[0] / 2, bottom[1] / 2
    tx, ty = top[0] / 2, top[1] / 2
    ox, oy = top_offset
    s0 = [(cx - bx, cy - by, cz), (cx + bx, cy - by, cz), (cx + bx, cy + by, cz), (cx - bx, cy + by, cz)]
    s1 = [(cx + ox - tx, cy + oy - ty, cz + height), (cx + ox + tx, cy + oy - ty, cz + height),
          (cx + ox + tx, cy + oy + ty, cz + height), (cx + ox - tx, cy + oy + ty, cz + height)]
    return add_loft(bm, [s0, s1], mat_index=mat_index)


def transform(verts, matrix):
    """Transform a list (or nested rings) of BMVerts by a 4x4 matrix."""
    flat = []
    for v in verts:
        if isinstance(v, (list, tuple)):
            flat.extend(v)
        else:
            flat.append(v)
    for v in flat:
        v.co = matrix @ v.co
    return flat


# ------------------------------------------------------------------------------------------------
# objects
# ------------------------------------------------------------------------------------------------
def new_object(name, bm, parent=None, materials=(), location=(0, 0, 0), rotation=(0, 0, 0),
               collection=None, smooth_angle=None, uv=True, recalc=True, weld=0.0001):
    """Turn a bmesh into a mesh object (frees the bmesh). Local transform relative to `parent`.
    materials: list of bpy materials matching the mat_index values used while building.
    smooth_angle: None = flat shading (project default); degrees = smooth with sharp edges above it."""
    if weld and weld > 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=weld)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    target = collection
    if target is None and parent is not None and parent.users_collection:
        target = parent.users_collection[0]
    if target is None:
        target = col("")
    target.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    ob.location = Vector(location)
    ob.rotation_euler = Euler(rotation, 'XYZ')
    if smooth_angle is not None:
        shade_smooth(ob, smooth_angle)
    if uv:
        box_uv(ob)
    return ob


def shade_smooth(ob, angle_deg=40.0):
    """Smooth shading with hard edges where the face angle exceeds angle_deg."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) <= limit
        else:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()
    me.update()


def shade_flat(ob):
    for p in ob.data.polygons:
        p.use_smooth = False
    ob.data.update()


def box_uv(ob, scale=1.0, name="UVMap"):
    """Cube-projected UVs in metres (object space). Enough for palette materials and decals."""
    me = ob.data
    uvl = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    if uvl is None:
        return
    data = uvl.data
    verts = me.vertices
    for poly in me.polygons:
        n = poly.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for li in poly.loop_indices:
            co = verts[me.loops[li].vertex_index].co
            if az >= ax and az >= ay:
                uv = (co.x, co.y)
            elif ax >= ay:
                uv = (co.y, co.z)
            else:
                uv = (co.x, co.z)
            data[li].uv = (uv[0] * scale, uv[1] * scale)


def apply_modifiers(ob):
    """Bake the modifier stack into the mesh (no bpy.ops / context needed)."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ob_eval = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ob_eval, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    name = old.name
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    me.name = name
    return ob


def bevel(ob, width=0.02, segments=1, angle_deg=30.0, apply=True):
    """Chamfer hard edges (the 'chunky' look of the art direction). Applied immediately by default."""
    mod = ob.modifiers.new("Bevel", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle_deg)
    try:
        mod.harden_normals = False
    except Exception:
        pass
    if apply:
        apply_modifiers(ob)
        box_uv(ob)
    return ob


def mirror_x(ob, apply=True):
    """Mirror across the object's local X=0 plane (build the +X half only, then mirror)."""
    mod = ob.modifiers.new("Mirror", 'MIRROR')
    mod.use_axis[0] = True
    mod.use_clip = True
    mod.merge_threshold = 0.0005
    if apply:
        apply_modifiers(ob)
        box_uv(ob)
    return ob


def set_origin(ob, point_local):
    """Move the object's origin to `point_local` (object space) without moving the geometry in the world."""
    p = Vector(point_local)
    me = ob.data
    me.transform(Matrix.Translation(-p))
    ob.location = ob.location + (ob.matrix_basis.to_3x3() @ p)
    me.update()


def join(objs, name):
    """Merge mesh objects into the first one's space; keeps and merges material slots."""
    base = objs[0]
    mats = []
    bm = bmesh.new()
    inv = base.matrix_world.inverted()
    bpy.context.view_layer.update()
    for o in objs:
        remap = []
        for m in o.data.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        nf0 = len(bm.faces)
        nv0 = len(bm.verts)
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        M = inv @ o.matrix_world
        for v in bm.verts[nv0:]:
            v.co = M @ v.co
        for f in bm.faces[nf0:]:
            if remap:
                f.material_index = remap[min(f.material_index, len(remap) - 1)]
    parent = base.parent
    loc = base.location.copy()
    rot = base.rotation_euler.copy()
    coll = base.users_collection[0] if base.users_collection else None
    for o in objs:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    ob = new_object(name, bm, parent=parent, materials=mats, location=loc, rotation=rot,
                    collection=coll, recalc=False, weld=0)
    return ob


def children_of(root):
    return [root] + list(root.children_recursive)


# ------------------------------------------------------------------------------------------------
# QA
# ------------------------------------------------------------------------------------------------
_BAD_NAME = re.compile(r'^(Cube|Sphere|Cylinder|Plane|Cone|Torus|Empty|Icosphere|Mesh|Object|Suzanne)(\.\d+)?$')


def validate(root_name, max_tris=None):
    """Print a QA report for an asset: tri counts, bad names, unapplied scale, missing materials."""
    root = bpy.data.objects.get(root_name)
    if root is None:
        print("VALIDATE %s: MISSING ROOT" % root_name)
        return {"ok": False}
    bpy.context.view_layer.update()
    issues = []
    tris = 0
    verts = 0
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    inv = root.matrix_world.inverted()
    meshes = 0
    for o in children_of(root):
        if _BAD_NAME.match(o.name):
            issues.append("placeholder name: " + o.name)
        if o.type != 'MESH':
            continue
        meshes += 1
        me = o.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        verts += len(me.vertices)
        s = o.scale
        if abs(s.x - 1) > 1e-4 or abs(s.y - 1) > 1e-4 or abs(s.z - 1) > 1e-4:
            issues.append("unapplied scale on %s: %s" % (o.name, tuple(round(c, 3) for c in s)))
        if len(me.materials) == 0 or any(m is None for m in me.materials):
            issues.append("missing material on " + o.name)
        if len(me.polygons) == 0:
            issues.append("empty mesh " + o.name)
        for c in o.bound_box:
            w = inv @ (o.matrix_world @ Vector(c))
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    size = (mx - mn) if meshes else Vector((0, 0, 0))
    if max_tris is not None and tris > max_tris:
        issues.append("tri budget exceeded: %d > %d" % (tris, max_tris))
    print("VALIDATE %s: meshes=%d verts=%d tris=%d size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)" % (
        root_name, meshes, verts, tris, size.x, size.y, size.z, mn.x, mn.y, mn.z, mx.x, mx.y, mx.z))
    for i in issues:
        print("  ISSUE:", i)
    return {"ok": not issues, "tris": tris, "verts": verts, "size": tuple(size), "min": tuple(mn), "max": tuple(mx), "issues": issues}


_VIEW_DIRS = {
    "front": (0.0, 1.0, 0.12),
    "back": (0.0, -1.0, 0.12),
    "right": (1.0, 0.0, 0.12),
    "left": (-1.0, 0.0, 0.12),
    "side": (1.0, 0.0, 0.12),
    "top": (0.0, -0.001, 1.0),
    "three_quarter": (0.75, 1.0, 0.55),
    "rear_quarter": (-0.75, -1.0, 0.55),
    "low_front": (0.6, 1.0, 0.15),
}


def preview(names, out_name, views=("three_quarter", "side", "front", "top"), res=420, margin=1.12,
            isolate=True, perspective=False, background=(0.20, 0.22, 0.26)):
    """Render a small Workbench contact sheet (one tile per view) of the given asset roots and save
    it to qa/blender_previews/<out_name>.png. Everything else is hidden only for the render and all
    settings are restored, so it is safe while other authors work in the same file.
    Returns the absolute PNG path - open it with the Read tool to LOOK at your asset."""
    import numpy as np
    object_mode()
    if isinstance(names, str):
        names = [names]
    scene = bpy.context.scene
    objs = set()
    for n in names:
        r = bpy.data.objects.get(n)
        if r is None:
            raise RuntimeError("preview: no object named %r" % n)
        objs.update(children_of(r))
    bpy.context.view_layer.update()
    pts = []
    for o in objs:
        if o.type == 'MESH' and not o.hide_render:
            pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    if not pts:
        raise RuntimeError("preview: nothing to render in %r" % (names,))
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (mn + mx) / 2
    radius = max((mx - mn).length / 2, 0.05)

    r = scene.render
    sh = scene.display.shading
    saved = {
        "engine": r.engine, "rx": r.resolution_x, "ry": r.resolution_y, "pct": r.resolution_percentage,
        "path": r.filepath, "fmt": r.image_settings.file_format, "cam": scene.camera,
        "transparent": r.film_transparent,
    }
    saved_sh = {}
    for k in ("light", "color_type", "show_cavity", "show_shadows", "show_object_outline", "background_type", "background_color", "cavity_type"):
        try:
            v = getattr(sh, k)
            saved_sh[k] = tuple(v) if k == "background_color" else v
        except Exception:
            pass
    hidden = []
    if isolate:
        for o in scene.objects:
            if o not in objs and not o.hide_render:
                o.hide_render = True
                hidden.append(o)
    cam_data = bpy.data.cameras.new("_gta_preview_cam")
    cam = bpy.data.objects.new("_gta_preview_cam", cam_data)
    scene.collection.objects.link(cam)
    tmp_paths = []
    out_path = os.path.join(PREVIEW_DIR, out_name + ".png")
    try:
        try:
            r.engine = 'BLENDER_WORKBENCH'
        except TypeError as e:
            raise RuntimeError("workbench engine unavailable: %s" % e)
        for k, v in (("light", 'STUDIO'), ("color_type", 'MATERIAL'), ("show_cavity", True), ("cavity_type", 'BOTH'),
                     ("show_shadows", False), ("show_object_outline", True), ("background_type", 'VIEWPORT'),
                     ("background_color", background)):
            try:
                setattr(sh, k, v)
            except Exception:
                pass
        r.resolution_x = res
        r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = 'PNG'
        scene.camera = cam
        if perspective:
            cam_data.type = 'PERSP'
            cam_data.lens = 50
        else:
            cam_data.type = 'ORTHO'
            cam_data.ortho_scale = radius * 2 * margin
        cam_data.clip_start = 0.01
        cam_data.clip_end = radius * 12 + 50
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        tiles = []
        for i, vname in enumerate(views):
            d = Vector(_VIEW_DIRS[vname] if isinstance(vname, str) else vname).normalized()
            dist = radius * (3.2 if perspective else 4.0)
            cam.location = center + d * dist
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            tmp = os.path.join(PREVIEW_DIR, "_tmp_%s_%d.png" % (re.sub(r'[^A-Za-z0-9_]', '_', out_name), i))
            r.filepath = tmp
            bpy.ops.render.render(write_still=True)
            tmp_paths.append(tmp)
            img = bpy.data.images.load(tmp, check_existing=False)
            arr = np.empty(res * res * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            tiles.append(arr.reshape(res, res, 4))
            bpy.data.images.remove(img)
        cols = 2 if len(tiles) > 1 else 1
        rows = (len(tiles) + cols - 1) // cols
        sheet = np.zeros((rows * res, cols * res, 4), dtype=np.float32)
        sheet[..., 3] = 1.0
        for i, t in enumerate(tiles):
            rr = rows - 1 - (i // cols)     # image rows are bottom-up
            cc = i % cols
            sheet[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res, :] = t
        out = bpy.data.images.new("_gta_preview_sheet", cols * res, rows * res, alpha=False)
        out.pixels.foreach_set(sheet.ravel())
        out.filepath_raw = out_path
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
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
        r.resolution_x = saved["rx"]
        r.resolution_y = saved["ry"]
        r.resolution_percentage = saved["pct"]
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
        for t in tmp_paths:
            try:
                os.remove(t)
            except Exception:
                pass
    print("PREVIEW_SAVED:", out_path)
    return out_path


# ------------------------------------------------------------------------------------------------
# export / save
# ------------------------------------------------------------------------------------------------
def export_glb(root_name, rel_path, animations=False, apply_modifiers_on_export=True):
    """Export one asset (root Empty + all descendants) to gta/generated/models/<rel_path> as GLB.
    The root is moved to the world origin for the export and restored afterwards. Selection,
    active object and visibility are restored. Returns the absolute path."""
    object_mode()
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError("export_glb: no root %r" % root_name)
    if not rel_path.lower().endswith(".glb"):
        rel_path += ".glb"
    path = os.path.join(MODELS_DIR, rel_path.replace("/", os.sep))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    vl = bpy.context.view_layer
    objs = children_of(root)
    prev_sel = [o for o in vl.objects if o.select_get()]
    prev_active = vl.objects.active
    saved_loc = root.location.copy()
    saved_rot = root.rotation_euler.copy()
    unhid = []
    try:
        for o in prev_sel:
            o.select_set(False)
        root.location = (0.0, 0.0, 0.0)
        root.rotation_euler = (0.0, 0.0, 0.0)
        for o in objs:
            state = (o, o.hide_viewport, o.hide_get() if o.name in vl.objects else False)
            if state[1] or state[2]:
                unhid.append(state)
                o.hide_viewport = False
                try:
                    o.hide_set(False)
                except Exception:
                    pass
            if o.name in vl.objects:
                o.select_set(True)
        vl.objects.active = root
        vl.update()
        props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
        wanted = {
            "filepath": path,
            "export_format": 'GLB',
            "use_selection": True,
            "export_apply": apply_modifiers_on_export,
            "export_yup": True,
            "export_animations": animations,
            "export_cameras": False,
            "export_lights": False,
            "export_extras": True,
            "export_texcoords": True,
            "export_normals": True,
            "export_materials": 'EXPORT',
            "export_skins": True,
            "export_morph": False,
            "use_visible": False,
            "check_existing": False,
        }
        kwargs = {k: v for k, v in wanted.items() if k in props}
        if animations:
            for k, v in (("export_animation_mode", 'ACTIONS'), ("export_force_sampling", True),
                         ("export_bake_animation", False), ("export_anim_single_armature", True),
                         ("export_reset_pose_bones", True), ("export_optimize_animation_size", False)):
                if k in props:
                    kwargs[k] = v
        res = bpy.ops.export_scene.gltf(**kwargs)
        if 'FINISHED' not in res:
            raise RuntimeError("glTF export returned %r" % (res,))
    finally:
        root.location = saved_loc
        root.rotation_euler = saved_rot
        for o, hv, hs in unhid:
            try:
                o.hide_viewport = hv
                o.hide_set(hs)
            except Exception:
                pass
        for o in objs:
            try:
                o.select_set(False)
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
    size = os.path.getsize(path) if os.path.exists(path) else -1
    print("EXPORTED:", path, "bytes=%d" % size)
    return path


def save():
    """Save the master .blend in place (never Save As)."""
    assert_master()
    object_mode()
    bpy.ops.wm.save_mainfile()
    print("SAVED:", bpy.data.filepath)
    return bpy.data.filepath
