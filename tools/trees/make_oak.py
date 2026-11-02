"""Procedural oak for Lethe Protocol, built with Blender as a Python module (pip install bpy).

    python3 tools/trees/make_oak.py <out dir> [variants=4] [preview=<png>]

Writes, per variant v (0..n-1), into <out dir>:
  oak_v.glb      two meshes: "lod0" (full: ~10 m tall, trunk with root flare, 3 limb levels, ~600 leaf cards) and "lod1"
                 (trunk and main limbs only, ~170 big cards). Each mesh has two surfaces, material "bark" and "leaves".
  (and, once for all variants) oak_impostor.png: 8 views of every variant (side views around the tree) for the far billboards.

Vertex colour (COLOR_0, linear, read by shaders/oak.gdshader):  r = wind sway weight (0 trunk .. 1 leaf tips),
g = per-branch phase (0..1), b = ambient occlusion (dark inside the crown), a = 1.
Leaf card normals point away from the crown centre (blended with the card's own normal), so the canopy shades like a volume.
Units are metres, the tree stands on the origin; Game scales it by the tree's height (h / 10).
"""
import math
import random
import sys
import os

import bpy
import bmesh
from mathutils import Vector, Matrix, Quaternion, noise

HEIGHT = 10.0                 # nominal height (Godot scales by tree h / HEIGHT)
CROWN_C = Vector((0.0, 0.0, 6.5))   # crown centre (leaf normals, AO)
CROWN_R = Vector((6.0, 6.0, 3.8))   # crown ellipsoid radii
ATLAS_CELLS = 2               # leaf atlas: 2 x 2 clusters


# ---------------------------------------------------------------- branch skeleton

class Branch:
    def __init__(self, pts, radii, level, phase):
        self.pts = pts            # list of Vector
        self.radii = radii        # list of float
        self.level = level
        self.phase = phase
        self.children = []


def grow(start, direction, length, r0, r1, level, rng, segs, gnarl=0.25, up=0.0):
    """A bent tube from start along direction: returns points / radii."""
    pts, radii = [start.copy()], [r0]
    d = direction.normalized()
    p = start.copy()
    step = length / segs
    seed = rng.random() * 100.0
    for i in range(1, segs + 1):
        t = i / segs
        n = noise.noise_vector(Vector((seed + t * 2.2, seed * 0.7, level * 3.1)))
        d = (d + n * gnarl + Vector((0, 0, up))).normalized()
        p = p + d * step
        pts.append(p.copy())
        radii.append(r0 + (r1 - r0) * t ** 0.8)
    return pts, radii


def at(br, t):
    """Point, tangent, radius at fraction t along a branch."""
    n = len(br.pts) - 1
    f = min(n - 1e-4, max(0.0, t * n))
    i = int(f)
    k = f - i
    p = br.pts[i].lerp(br.pts[i + 1], k)
    tan = (br.pts[i + 1] - br.pts[i]).normalized()
    r = br.radii[i] + (br.radii[i + 1] - br.radii[i]) * k
    return p, tan, r


def inside_crown(p):
    q = p - CROWN_C
    return (q.x / CROWN_R.x) ** 2 + (q.y / CROWN_R.y) ** 2 + (q.z / CROWN_R.z) ** 2


def side_dir(tan, rng, angle):
    """A direction at `angle` from the tangent, at a random roll, biased outward and slightly up."""
    perp = tan.orthogonal().normalized()
    roll = Quaternion(tan, rng.uniform(0, math.tau))
    perp = roll @ perp
    return (tan * math.cos(angle) + perp * math.sin(angle)).normalized()


def build_skeleton(rng):
    # trunk: short and thick, slight lean, forks at 2.4-3.0 m
    fork_h = rng.uniform(2.4, 3.0)
    lean = Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1.0))
    tp, tr = grow(Vector((0, 0, 0)), lean, fork_h, 0.42, 0.32, 0, rng, 6, gnarl=0.08)
    trunk = Branch(tp, tr, 0, 0.0)
    limbs = []
    n_limbs = rng.randint(3, 5)
    base_roll = rng.uniform(0, math.tau)
    for i in range(n_limbs):
        a = base_roll + math.tau * i / n_limbs + rng.uniform(-0.35, 0.35)
        tilt = math.radians(rng.uniform(40, 62))
        d = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        start_t = rng.uniform(0.82, 1.0)
        sp, _, _ = at(trunk, start_t)
        length = rng.uniform(4.8, 6.2)
        lp, lr = grow(sp, d, length, 0.23, 0.06, 1, rng, 9, gnarl=0.3, up=0.04)
        lb = Branch(lp, lr, 1, rng.random())
        trunk.children.append(lb)
        limbs.append(lb)
    # an extra leader going straight up from the fork
    lp, lr = grow(trunk.pts[-1], Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1)), rng.uniform(3.8, 4.6), 0.18, 0.05, 1, rng, 8, gnarl=0.25)
    lb = Branch(lp, lr, 1, rng.random())
    trunk.children.append(lb)
    limbs.append(lb)
    # level 2 and 3
    for lb in limbs:
        n2 = rng.randint(5, 7)
        for j in range(n2):
            t = 0.22 + 0.78 * (j + rng.random() * 0.7) / n2
            p, tan, r = at(lb, t)
            d = side_dir(tan, rng, math.radians(rng.uniform(38, 70)))
            # keep the shoots out of the trunk and inside the crown
            out = Vector((p.x, p.y, 0)).normalized() if Vector((p.x, p.y)).length > 0.3 else d
            d = (d + out * 0.4 + Vector((0, 0, 0.15))).normalized()
            length = rng.uniform(1.6, 2.9) * (1.15 - t * 0.4)
            bp, brr = grow(p, d, length, r * 0.6, 0.022, 2, rng, 5, gnarl=0.4, up=0.05)
            b2 = Branch(bp, brr, 2, rng.random())
            lb.children.append(b2)
            for k in range(rng.randint(3, 5)):
                t3 = 0.3 + 0.7 * (k + rng.random() * 0.6) / 4
                p3, tan3, r3 = at(b2, t3)
                d3 = side_dir(tan3, rng, math.radians(rng.uniform(35, 65)))
                d3 = (d3 + Vector((0, 0, 0.25))).normalized()
                cp, cr = grow(p3, d3, rng.uniform(0.6, 1.2), r3 * 0.7, 0.008, 3, rng, 3, gnarl=0.5)
                b2.children.append(Branch(cp, cr, 3, rng.random()))
    return trunk


def walk(br):
    yield br
    for c in br.children:
        yield from walk(c)


# ---------------------------------------------------------------- mesh building

class MeshData:
    def __init__(self):
        self.verts, self.norms, self.uvs, self.cols, self.faces = [], [], [], [], []

    def add_vert(self, p, n, uv, col):
        self.verts.append(p)
        self.norms.append(n)
        self.uvs.append(uv)
        self.cols.append(col)
        return len(self.verts) - 1


def sway(p):
    """Wind weight by height and distance from the trunk."""
    horiz = Vector((p.x, p.y)).length
    return min(1.0, max(0.0, (p.z - 2.0) / 8.0) * 0.5 + horiz / 6.0 * 0.6)


def ao_at(p):
    k = inside_crown(p)
    return min(1.0, 0.5 + 0.5 * min(1.0, k ** 0.7))


def tube(md, br, sides, flare=False):
    rings = []
    vlen = 0.0
    n = len(br.pts)
    for i in range(n):
        p = br.pts[i]
        if i < n - 1:
            tan = (br.pts[i + 1] - p).normalized()
        else:
            tan = (p - br.pts[i - 1]).normalized()
        if i > 0:
            vlen += (p - br.pts[i - 1]).length
        x = tan.orthogonal().normalized()
        y = tan.cross(x).normalized()
        ring = []
        r = br.radii[i]
        circ = max(1, round(r * math.tau / 0.9))         # bark texture repeats about every 0.9 m around the trunk
        for s in range(sides + 1):
            a = math.tau * s / sides
            rr = r
            if flare and i == 0:
                rr = r * (1.6 + 0.25 * math.cos(a * 5))  # root flare with five buttresses
            elif flare and i == 1:
                rr = r * (1.15 + 0.06 * math.cos(a * 5))
            nrm = x * math.cos(a) + y * math.sin(a)
            q = p + nrm * rr
            col = (sway(q) * (0.0 if br.level == 0 else 1.0), br.phase, ao_at(q) * (0.8 if br.level == 0 else 1.0), 1.0)
            ring.append(md.add_vert(q, nrm, (s / sides * circ, vlen / 0.9), col))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(sides):
            a, b, c, d = rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i + 1][s]
            md.faces.append((a, b, c, d))
    if flare:
        # sink the flare a little into the ground
        for v in rings[0]:
            md.verts[v] = md.verts[v] - Vector((0, 0, 0.12))


def card(md, centre, normal, up, size, cell, phase, rng):
    """One leaf-cluster quad (two triangles), its normal bent outward from the crown centre."""
    right = up.cross(normal).normalized()
    up = normal.cross(right).normalized()
    out = (centre - CROWN_C)
    out = Vector((out.x / CROWN_R.x, out.y / CROWN_R.y, out.z / CROWN_R.z * 0.8)).normalized()
    u0 = (cell % ATLAS_CELLS) / ATLAS_CELLS
    v0 = (cell // ATLAS_CELLS) / ATLAS_CELLS
    du = 1.0 / ATLAS_CELLS
    idx = []
    h = size * 0.5
    for (sx, sy, uu, vv) in [(-1, -1, 0, 1), (1, -1, 1, 1), (1, 1, 1, 0), (-1, 1, 0, 0)]:
        q = centre + right * (sx * h) + up * (sy * h)
        n = (out * 0.75 + normal * 0.25 + (q - centre).normalized() * 0.15).normalized()
        col = (min(1.0, sway(q) + 0.25), phase, ao_at(q), 1.0)
        # glTF UV: v down from the top, matching PIL rows
        idx.append(md.add_vert(q, n, (u0 + uu * du * 0.998 + 0.001, v0 + vv * du * 0.998 + 0.001), col))
    md.faces.append(tuple(idx))


def leaves(md, skel, rng, density, size_k):
    for br in walk(skel):
        if br.level < 2:
            continue
        if br.level == 2 and density < 1.0:
            pass
        n = (3 if br.level == 3 else 3) if density >= 1.0 else (1 if br.level == 2 else 0)
        if density < 1.0 and br.level == 3:
            continue
        for i in range(n):
            t = rng.uniform(0.55, 1.0)
            p, tan, r = at(br, t)
            # the card sits beyond the twig, its plane roughly along the twig, rolled at random
            nrm = side_dir(tan, rng, math.radians(90))
            centre = p + tan * 0.25 * size_k + nrm.cross(tan) * rng.uniform(-0.15, 0.15)
            if inside_crown(centre) > 1.25:
                continue
            up = (tan + Vector((0, 0, 0.6))).normalized()
            size = rng.uniform(1.3, 1.9) * size_k
            card(md, centre, nrm, up, size, rng.randrange(ATLAS_CELLS * ATLAS_CELLS), br.phase, rng)
    # fill the crown: cards scattered on the crown shell where branch tips are sparse
    count = int(260 * density)
    lump_seed = rng.random() * 50.0
    for i in range(count):
        z = rng.uniform(-0.55, 1.0)
        a = rng.uniform(0, math.tau)
        s = math.sqrt(max(0.0, 1 - z * z)) * rng.uniform(0.75, 0.97)
        dirn = Vector((math.cos(a) * s, math.sin(a) * s, z))
        lump = 1.0 + 0.22 * noise.noise(dirn * 1.6 + Vector((lump_seed, 0, 0)))     # clumps, not a perfect ball
        q = CROWN_C + Vector((dirn.x * CROWN_R.x, dirn.y * CROWN_R.y, dirn.z * CROWN_R.z * 0.92)) * lump
        nrm = (q - CROWN_C).normalized()
        nrm = (nrm + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(-0.4, 0.6)))).normalized()
        up = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 1)).normalized()
        if abs(up.dot(nrm)) > 0.95:
            up = Vector((1, 0, 0))
        card(md, q, nrm, up, rng.uniform(1.6, 2.3) * size_k, rng.randrange(4), rng.random(), rng)


def to_object(name, bark, leaf, bark_mat, leaf_mat):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    col_layer = bm.loops.layers.color.new("Col")
    all_norms = []
    for mi, md in enumerate([bark, leaf]):
        bv = [bm.verts.new(p) for p in md.verts]
        for f in md.faces:
            try:
                face = bm.faces.new([bv[i] for i in f])
            except ValueError:
                continue
            face.material_index = mi
            face.smooth = True
            for loop, vi in zip(face.loops, f):
                loop[uv_layer].uv = (md.uvs[vi][0], 1.0 - md.uvs[vi][1])
                loop[col_layer] = md.cols[vi]
                all_norms.append(md.norms[vi])
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bark_mat)
    me.materials.append(leaf_mat)
    me.normals_split_custom_set(all_norms)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------- materials (for the preview render and the glTF material names)

def materials(tex_dir):
    bark = bpy.data.materials.new("bark")
    bark.use_nodes = True
    nt = bark.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(tex_dir, "oak_bark.jpg"))
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    nimg = nt.nodes.new("ShaderNodeTexImage")
    nimg.image = bpy.data.images.load(os.path.join(tex_dir, "oak_bark_normal.jpg"))
    nimg.image.colorspace_settings.name = "Non-Color"
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nimg.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.9

    leaf = bpy.data.materials.new("leaves")
    leaf.use_nodes = True
    nt = leaf.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(tex_dir, "oak_leaves.png"))
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    # vertex AO darkens the base colour in the preview
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vc.outputs["Color"], sep.inputs["Color"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(img.outputs["Color"], mul.inputs[6])
    nt.links.new(sep.outputs["Blue"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    try:
        bsdf.inputs["Subsurface Weight"].default_value = 0.0
        bsdf.inputs["Transmission Weight"].default_value = 0.0
    except KeyError:
        pass
    leaf.blend_method = "CLIP" if hasattr(leaf, "blend_method") else None
    return bark, leaf


# ---------------------------------------------------------------- preview / impostor rendering (Cycles, CPU)

def setup_render(res_x, res_y, samples, transparent):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"


def sun_and_sky(strength=1.0):
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.7, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6 * strength
    sc.world = world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5 * strength
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), 0, math.radians(35))
    sc.collection.objects.link(so)


def camera(ortho_scale=None):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    if ortho_scale:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho_scale
    else:
        cam.lens = 40
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


def look_at(obj, eye, target):
    obj.location = eye
    d = (Vector(target) - Vector(eye)).normalized()
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def main():
    out_dir = sys.argv[1]
    n_var = 4
    preview = None
    for a in sys.argv[2:]:
        if a.startswith("variants="):
            n_var = int(a.split("=")[1])
        if a.startswith("preview="):
            preview = a.split("=", 1)[1]
    os.makedirs(out_dir, exist_ok=True)
    stats = []
    for v in range(n_var):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bark_mat, leaf_mat = materials(out_dir)
        rng = random.Random(1000 + v * 77)
        skel = build_skeleton(rng)
        # LOD0: everything
        bark0, leaf0 = MeshData(), MeshData()
        for br in walk(skel):
            sides = {0: 12, 1: 8, 2: 5, 3: 3}[br.level]
            tube(bark0, br, sides, flare=br.level == 0)
        leaves(leaf0, skel, random.Random(v * 13 + 5), 1.0, 1.0)
        o0 = to_object("lod0", bark0, leaf0, bark_mat, leaf_mat)
        # LOD1: trunk + limbs, big cards on the level-2 shoots and the shell
        bark1, leaf1 = MeshData(), MeshData()
        for br in walk(skel):
            if br.level <= 1:
                tube(bark1, Branch(br.pts[::2] + ([br.pts[-1]] if len(br.pts) % 2 == 0 else []),
                                   br.radii[::2] + ([br.radii[-1]] if len(br.radii) % 2 == 0 else []), br.level, br.phase),
                     {0: 7, 1: 5}[br.level], flare=br.level == 0)
        leaves(leaf1, skel, random.Random(v * 13 + 6), 0.5, 1.7)
        o1 = to_object("lod1", bark1, leaf1, bark_mat, leaf_mat)
        o1.location.x = 0.0
        tri0 = sum(len(f) - 2 for f in bark0.faces + leaf0.faces)
        tri1 = sum(len(f) - 2 for f in bark1.faces + leaf1.faces)
        stats.append((v, tri0, len(leaf0.faces), tri1, len(leaf1.faces)))
        if preview and v == 0:
            _preview(o0, o1, preview)
        bpy.ops.object.select_all(action="DESELECT")
        o0.select_set(True)
        o1.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, f"oak_{v}.glb"), use_selection=True, export_format="GLB",
                                  export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_image_format="NONE",
                                  export_materials="PLACEHOLDER", export_yup=True)
    for s in stats:
        print("OAK variant %d: lod0 %d tris (%d cards), lod1 %d tris (%d cards)" % s)


def _preview(o0, o1, path):
    """A 4-view turntable of LOD0 (and LOD1 at the right) in daylight, for judging the look."""
    o1.hide_render = True
    setup_render(800, 640, 48, False)
    sun_and_sky()
    ground = bpy.data.meshes.new("g")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    bm.to_mesh(ground)
    bm.free()
    gm = bpy.data.materials.new("grass")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.12, 0.25, 0.05, 1)
    ground.materials.append(gm)
    go = bpy.data.objects.new("g", ground)
    bpy.context.scene.collection.objects.link(go)
    cam = camera()
    shots = []
    base, ext = os.path.splitext(path)
    for i, ang in enumerate([0, 90, 180, 270]):
        a = math.radians(ang + 20)
        look_at(cam, (math.cos(a) * 20, math.sin(a) * 20, 3.2), (0, 0, 4.6))
        f = f"{base}_{i}{ext}"
        bpy.context.scene.render.filepath = f
        bpy.ops.render.render(write_still=True)
        shots.append(f)
    # close-up of the trunk and the crown from below
    look_at(cam, (5.5, -4.0, 1.6), (0, 0, 3.8))
    f = f"{base}_close{ext}"
    bpy.context.scene.render.filepath = f
    bpy.ops.render.render(write_still=True)
    shots.append(f)
    o1.hide_render = False
    o0.hide_render = True
    look_at(cam, (math.cos(0.35) * 20, math.sin(0.35) * 20, 3.2), (0, 0, 4.6))
    f = f"{base}_lod1{ext}"
    bpy.context.scene.render.filepath = f
    bpy.ops.render.render(write_still=True)
    o0.hide_render = False
    o1.hide_render = True
    print("PREVIEW", shots + [f])


if __name__ == "__main__":
    main()
