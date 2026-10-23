"""Roadside landforms for Convoy Apocalypse, modelled in Blender.

Run inside Blender (exec the file). Writes one item JSON per landform into
ConvoyKit/items/ (folder "world"), which tools/build_art_modules.py turns into
ArtData modules that ConvoyRunService.buildScenery places beside the road.

Blender Z-up; export swaps to Roblox (x, z, y) and reverses winding.
1 Blender unit = 1 stud. Every piece has its base at Z = 0 (Roblox Y = 0) and
is centred on X/Y, so a CFrame at ground level puts it straight on the ground.

  MountainWaste   brown ridged mountain        ~64 wide, ~40 tall
  MountainSnow    grey mountain, snow caps     ~64 wide, ~48 tall
  MesaDesert      layered red/tan mesa         ~40 wide, ~30 tall
  HillGrass       soft green hill              ~60 wide, ~14 tall
  TowerRuin       broken concrete skyscraper   ~14 wide, ~46 tall
"""
import bpy
import bmesh
import json
import math
import os
import random

from mathutils import Vector, noise

KIT = r"C:\Users\TJ\Documents\ConvoyKit"
OUT_DIR = os.path.join(KIT, "items")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.meshes):
    if block.users == 0:
        bpy.data.meshes.remove(block)

pieces = []  # (object, material, rgb, group)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ridged(x, y, seed, freq):
    n = noise.noise(Vector((x * freq + seed, y * freq - seed, seed * 0.37)))
    return 1.0 - abs(n)


def heightfield(name, size, height, seed, segs=56, ridge=1.0, peaks=1, base=-1.5, round_top=0.0):
    """A mound with ridged noise, falling to `base` at the rim."""
    mesh = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=segs, y_segments=segs, size=size / 2)
    rng = random.Random(seed)
    centres = [(rng.uniform(-0.35, 0.35) * size, rng.uniform(-0.3, 0.3) * size, rng.uniform(0.7, 1.0)) for _ in range(peaks)]
    half = size / 2
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        # Rounded outline: distance from the centre, with a wobble.
        r = math.hypot(x, y) / half
        wobble = 1.0 + 0.12 * noise.noise(Vector((x * 0.06 + seed, y * 0.06, 3.1)))
        edge = smooth((1.0 - r * wobble) / 0.85)
        mass = 0.0
        for cx, cy, w in centres:
            d = math.hypot(x - cx, y - cy) / (half * 0.75)
            mass = max(mass, w * smooth(1.0 - d) ** 0.7)
        rough = (
            0.50 * ridged(x, y, seed, 0.06)
            + 0.32 * ridged(x, y, seed + 7, 0.14)
            + 0.18 * ridged(x, y, seed + 13, 0.30)
        )
        rough = rough ** (3.2 if ridge > 0.5 else 1.0)
        mix = (1 - round_top) * (0.12 + 0.95 * rough * ridge) + round_top * 0.8
        h = height * mass * mix * edge
        v.co.z = max(base, h + base * (1 - edge))
    bm.to_mesh(mesh)
    bm.free()
    return ob


def split_above(ob, z_min, name):
    """Moves every face whose centre is above z_min into a new object."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    high = [f for f in bm.faces if f.calc_center_median().z >= z_min]
    cap_mesh = bpy.data.meshes.new(name)
    cap = bpy.data.objects.new(name, cap_mesh)
    bpy.context.collection.objects.link(cap)
    cap_bm = bmesh.new()
    for f in high:
        verts = [cap_bm.verts.new(v.co.copy()) for v in f.verts]
        cap_bm.faces.new(verts)
    cap_bm.to_mesh(cap_mesh)
    cap_bm.free()
    bmesh.ops.delete(bm, geom=high, context="FACES_ONLY")
    bm.to_mesh(ob.data)
    bm.free()
    return cap


def box_at(name, centre, size, rot_z=0.0, rot_tilt=(0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    ob.rotation_euler = (rot_tilt[0], rot_tilt[1], rot_z)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return ob


def join(name, obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    return ob


def keep(ob, material, rgb, group):
    ob.name = group + "_" + ob.name
    pieces.append((ob, material, rgb, group))


# ---------------------------------------------------------------------------
# Mountains
# ---------------------------------------------------------------------------

mountain = heightfield("Rock", 64, 40, seed=11, peaks=4, ridge=1.0)
keep(mountain, "Slate", (150, 142, 168), "MountainWaste")

snow_mountain = heightfield("Rock", 64, 50, seed=29, peaks=4, ridge=1.0)
snow_cap = split_above(snow_mountain, 30, "Snow")
keep(snow_mountain, "Rock", (120, 134, 160), "MountainSnow")
keep(snow_cap, "Snow", (238, 243, 250), "MountainSnow")

hill = heightfield("Grass", 60, 15, seed=5, peaks=2, ridge=0.25, round_top=0.7, segs=36)
keep(hill, "Grass", (104, 200, 84), "HillGrass")


# ---------------------------------------------------------------------------
# Mesa: stacked strata, each slightly smaller, with noisy rims
# ---------------------------------------------------------------------------

def strata_tier(name, z0, z1, radius, taper, seed, segs=26):
    mesh = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    rng = random.Random(seed)
    ring_bottom, ring_top = [], []
    for i in range(segs):
        a = i / segs * math.tau
        wob = 1.0 + 0.16 * noise.noise(Vector((math.cos(a) * 1.3 + seed, math.sin(a) * 1.3, seed * 0.2)))
        wob += rng.uniform(-0.03, 0.03)
        ring_bottom.append(bm.verts.new((math.cos(a) * radius * wob, math.sin(a) * radius * wob * 0.85, z0)))
        ring_top.append(bm.verts.new((math.cos(a) * radius * taper * wob, math.sin(a) * radius * taper * wob * 0.85, z1)))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((ring_bottom[i], ring_bottom[j], ring_top[j], ring_top[i]))
    bm.faces.new(list(reversed(ring_bottom)))
    bm.faces.new(ring_top)
    bm.to_mesh(mesh)
    bm.free()
    return ob


mesa_tiers = [
    (-1.5, 9.0, 21.0, 0.97, (170, 92, 58)),
    (9.0, 15.0, 19.6, 0.98, (206, 150, 96)),
    (15.0, 21.5, 18.4, 0.97, (184, 108, 68)),
    (21.5, 25.5, 17.2, 0.99, (222, 176, 120)),
    (25.5, 30.0, 16.6, 0.96, (160, 84, 54)),
]
for index, (z0, z1, radius, taper, rgb) in enumerate(mesa_tiers):
    keep(strata_tier("Tier%d" % index, z0, z1, radius, taper, seed=40 + index), "Sandstone", rgb, "MesaDesert")


# ---------------------------------------------------------------------------
# Ruined skyscraper: slab floors, corner columns, a snapped-off top
# ---------------------------------------------------------------------------

def tower(seed):
    rng = random.Random(seed)
    w = 13.0
    d = 11.0
    floors = 10
    floor_h = 4.4
    slabs, columns, walls, rebar = [], [], [], []
    # Columns first: the floors above the shortest of them would float.
    col_heights = {(cx, cy): floors * floor_h - rng.choice([0, 0, 4.4, 8.8, 13.2]) for cx in (-1, 1) for cy in (-1, 1)}
    top_z = max(col_heights.values())
    for f in range(floors + 1):
        if f * floor_h > top_z:
            continue
        slab_w = w * (1.0 if f < floors - 1 else rng.uniform(0.55, 0.8))
        slabs.append(box_at("Slab", (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), f * floor_h + 0.2),
                            (slab_w, d, 0.5)))
    for cx in (-1, 1):
        for cy in (-1, 1):
            height = col_heights[(cx, cy)]
            columns.append(box_at("Column", (cx * (w / 2 - 0.5), cy * (d / 2 - 0.5), height / 2), (1.0, 1.0, height)))
            if rng.random() < 0.7:
                rebar.append(box_at("Rebar", (cx * (w / 2 - 0.5) + rng.uniform(-0.2, 0.2), cy * (d / 2 - 0.5), height + 1.2),
                                    (0.14, 0.14, 2.4), rot_tilt=(rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3))))
    # Back and one side wall, with the lower stories mostly intact and the
    # upper ones eaten away.
    for f in range(floors):
        gone = f > 3 and rng.random() < (0.25 + 0.08 * f)
        if not gone:
            walls.append(box_at("BackWall", (0, d / 2 - 0.3, f * floor_h + floor_h / 2 + 0.3), (w, 0.5, floor_h - 0.4)))
        if f < 6 and rng.random() < 0.7:
            walls.append(box_at("SideWall", (-w / 2 + 0.3, 0, f * floor_h + floor_h / 2 + 0.3), (0.5, d, floor_h - 0.4)))
    # Rubble heap at the foot
    heap = [box_at("Chunk", (rng.uniform(-9, 9), rng.uniform(-8, 8), rng.uniform(0.3, 1.0)),
                   (rng.uniform(1.2, 3.4), rng.uniform(1.2, 3.4), rng.uniform(0.8, 2.0)),
                   rot_z=rng.uniform(0, math.pi), rot_tilt=(rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4)))
            for _ in range(10)]
    return join("Frame", slabs + columns), join("Walls", walls), join("Rubble", heap), join("Rebar", rebar)


frame, walls, rubble, rebar = tower(3)
keep(frame, "Concrete", (130, 132, 138), "TowerRuin")
keep(walls, "Concrete", (108, 112, 120), "TowerRuin")
keep(rubble, "Concrete", (96, 98, 104), "TowerRuin")
keep(rebar, "CorrodedMetal", (140, 82, 46), "TowerRuin")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_mesh(ob):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.calc_loop_triangles()
    mw = ob.matrix_world
    verts = []
    for v in me.vertices:
        c = mw @ v.co
        verts.append([round(c.x, 3), round(c.z, 3), round(c.y, 3)])
    tris = []
    for tri in me.loop_triangles:
        a, b, c = tri.vertices
        tris.append([int(a) + 1, int(c) + 1, int(b) + 1])
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    center = [round((min(xs) + max(xs)) / 2, 3), round((min(ys) + max(ys)) / 2, 3), round((min(zs) + max(zs)) / 2, 3)]
    return {"name": ob.name, "verts": verts, "tris": tris, "center": center, "counts": [len(verts), len(tris)]}


groups, order = {}, []
for ob, material, rgb, group in pieces:
    data = export_mesh(ob)
    data["material"] = material
    data["color"] = list(rgb)
    data["accent"] = False
    if group not in groups:
        groups[group] = {"name": group, "folder": "world", "parts": []}
        order.append(group)
    groups[group]["parts"].append(data)

os.makedirs(OUT_DIR, exist_ok=True)
for name in order:
    item = groups[name]
    with open(os.path.join(OUT_DIR, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(item, f, separators=(",", ":"))
    print(f"{name}: {len(item['parts'])} parts, {sum(p['counts'][1] for p in item['parts'])} tris")

# Lay the landforms out in a row for inspection, tinted with their in-game colours.
group_objs = {}
for ob, material, rgb, group in pieces:
    ob.color = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
    group_objs.setdefault(group, []).append(ob)
for index, name in enumerate(order):
    for ob in group_objs[name]:
        ob.location.x += index * 80
