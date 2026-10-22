"""Vehicle part skins for Convoy Apocalypse, modelled in Blender.

Run inside Blender (exec the file). Writes one item JSON per skin into
ConvoyKit/items/, which tools/build_art_modules.py turns into ArtData modules.
Items there override same-named entries in custom.json, so the redesigned
Engine/Fuel/Minigun/... skins replace the old primitive ones.

Blender Z-up. Export swaps to Roblox (x, z, y) and reverses winding.
1 Blender unit = 1 stud. Skins are centred on the block origin, forward is -Z
in Roblox space, and each must stay inside its block:
  engine 4x2x4   fuel 2x2x2   seat 2x2x2   utility 2x2x2   armor 4x1x2
  minigun / flame / shotgun 2x2x4   tesla 2x3x2   rail 2x2x6
  rocket 4x2x4   mine 4x2x2   ram 6x2x2

Parts flagged accent take the part's tier colour in game, so every skin keeps
at least one glowing or trimmed element that reads as its rarity.
"""
import bpy
import bmesh
import json
import math
import os

KIT = r"C:\Users\TJ\Documents\ConvoyKit"
OUT_DIR = os.path.join(KIT, "items")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.meshes):
    if block.users == 0:
        bpy.data.meshes.remove(block)

pieces = []

DARK = (60, 62, 70)
CHAR = (82, 84, 94)
STEEL = (140, 144, 154)
LIGHT = (196, 198, 206)
RUST = (148, 84, 46)
RED = (170, 42, 38)
OLIVE = (74, 84, 56)
YELLOW = (222, 168, 42)
ORANGE = (255, 122, 36)
BLUE = (90, 190, 255)
GREEN = (80, 220, 130)
WOOD = (96, 68, 42)
WHITE = (226, 222, 210)
RUBBER = (34, 34, 38)


def rbx(x, y, z):
    """Roblox (x, y, z) -> Blender (x, z, y)."""
    return (x, z, y)


def _apply(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def prim(kind, loc, scale, rot=(0.0, 0.0, 0.0), **kw):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=kw.get("verts", 12), radius=1, depth=1, location=loc, rotation=rot
        )
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(
            vertices=kw.get("verts", 8), radius1=1, radius2=kw.get("radius2", 0.0), depth=1,
            location=loc, rotation=rot,
        )
    elif kind == "uv":
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=kw.get("segs", 12), ring_count=kw.get("rings", 7), radius=1, location=loc, rotation=rot
        )
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(
            major_segments=kw.get("maj", 16), minor_segments=kw.get("min", 6),
            major_radius=kw.get("maj_r", 1), minor_radius=kw.get("min_r", 0.08),
            location=loc, rotation=rot,
        )
    else:
        raise ValueError(kind)
    ob = bpy.context.active_object
    ob.scale = scale
    _apply(ob)
    return ob


def bevel(ob, width=0.06):
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = 1
    mod.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def box(loc, size, bev=0.0, rot=None):
    x, y, z = loc
    sx, sy, sz = size
    ob = prim("cube", rbx(x, y, z), (sx, sz, sy))
    if rot:
        # rot is Roblox-axis degrees (rx, ry, rz) -> Blender (rx, rz, ry)
        ob.rotation_euler = (math.radians(rot[0]), math.radians(rot[2]), math.radians(rot[1]))
        _apply(ob)
    if bev:
        bevel(ob, bev)
    return ob


def _axis_rot(axis):
    if axis == "y":
        return (0.0, 0.0, 0.0)
    if axis == "x":
        return (0.0, math.radians(90), 0.0)
    if axis == "z":
        return (math.radians(90), 0.0, 0.0)
    raise ValueError(axis)


def cyl(loc, radius, depth, axis="y", verts=12):
    return prim("cyl", rbx(*loc), (radius, radius, depth), _axis_rot(axis), verts=verts)


def cone(loc, radius, depth, axis="y", verts=8, radius2=0.0, flip=False):
    rot = _axis_rot(axis)
    if flip:
        rot = (rot[0] + math.pi, rot[1], rot[2]) if axis != "x" else (rot[0], rot[1] + math.pi, rot[2])
    return prim("cone", rbx(*loc), (radius, radius, depth), rot, verts=verts, radius2=radius2)


def sphere(loc, radii, segs=12, rings=7):
    rx, ry, rz = radii
    return prim("uv", rbx(*loc), (rx, rz, ry), segs=segs, rings=rings)


def ring(loc, major, minor, axis="y", maj=18, mn=6):
    return prim("torus", rbx(*loc), (1, 1, 1), _axis_rot(axis), maj=maj, min=mn, maj_r=major, min_r=minor)


def join(name, obs):
    obs = [o for o in obs if o is not None]
    if not obs:
        raise RuntimeError("nothing to join for " + name)
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    return ob


def keep(ob, material, rgb, group, accent=False, name=None):
    if name:
        ob.name = name
    ob.name = group + "_" + ob.name
    pieces.append((ob, material, rgb, accent, group))
    return ob


def row(builder, values):
    return [builder(v) for v in values]


# ---------------------------------------------------------------------------
# Engines (block 4 x 2 x 4, y in [-1, 1])
# ---------------------------------------------------------------------------

def engine_core(group, block_rgb=DARK, head_rgb=STEEL, accent_rgb=None):
    keep(box((0, -0.45, 0), (3.6, 1.1, 3.4), 0.1), "Metal", block_rgb, group, name="Block")
    keep(box((0, 0.3, 0), (2.7, 0.55, 2.5), 0.08), "Metal", head_rgb, group, name="Head")
    rails = [box((x, 0.62, 0), (0.34, 0.12, 2.3), 0.03) for x in (-0.95, 0.95)]
    keep(join("Rails", rails), "Neon", accent_rgb or ORANGE, group, accent=True)
    headers = [cyl((x, 0.05, z), 0.17, 0.55, "x", verts=8) for x in (-1.95, 1.95) for z in (-1.0, -0.33, 0.33, 1.0)]
    keep(join("Headers", headers), "CorrodedMetal", RUST, group)
    fins = [box((0, -0.1 + 0.28 * i, -1.85), (2.9, 0.1, 0.22)) for i in range(-2, 3)]
    keep(join("Grille", fins), "Metal", LIGHT, group)
    fan = join("Fan", [cyl((0, -0.1, -1.55), 0.62, 0.08, "z", verts=14),
                       box((0, -0.1, -1.55), (1.3, 0.14, 0.1)), box((0, -0.1, -1.55), (0.14, 1.3, 0.1))])
    keep(fan, "Metal", CHAR, group)
    keep(cyl((1.0, -0.25, 1.75), 0.42, 0.3, "z", verts=12), "Metal", STEEL, group, name="Pulley")


def engine_skin():
    engine_core("EngineSkin")


def engine_turbo_skin():
    g = "EngineTurboSkin"
    engine_core(g, block_rgb=(30, 34, 46), head_rgb=(70, 80, 100), accent_rgb=BLUE)
    keep(join("Snail", [cyl((1.1, 0.95, 0.4), 0.55, 0.8, "x", verts=14), cone((1.1, 0.95, -0.55), 0.36, 0.9, "z", verts=10, radius2=0.2)]),
         "Metal", STEEL, g)
    keep(ring((1.55, 0.95, 0.4), 0.55, 0.07, "x"), "Neon", BLUE, g, accent=True, name="TurboGlow")
    keep(box((-0.4, 1.0, -0.2), (1.6, 0.35, 1.5), 0.06), "Metal", LIGHT, g, name="Intercooler")


def engine_diesel_skin():
    g = "EngineDieselSkin"
    keep(box((0, -0.35, 0), (3.7, 1.3, 3.6), 0.1), "Metal", OLIVE, g, name="Block")
    keep(box((0, 0.55, 0.1), (3.0, 0.4, 2.8), 0.08), "Metal", CHAR, g, name="Head")
    stacks = [cyl((x, 1.0, -1.1), 0.2, 1.2, "y", verts=10) for x in (-1.1, 1.1)]
    keep(join("Stacks", stacks), "CorrodedMetal", RUST, g)
    keep(join("Caps", [cyl((x, 1.62, -1.1), 0.3, 0.1, "y", verts=10) for x in (-1.1, 1.1)]), "Metal", DARK, g)
    keep(join("Injectors", [cyl((x, 0.85, 0.5 + z), 0.12, 0.4, "y", verts=8) for x in (-0.9, 0, 0.9) for z in (0, 0.6)]),
         "Neon", ORANGE, g, accent=True)
    keep(join("Fins", [box((0, -0.5 + 0.3 * i, -1.9), (3.2, 0.12, 0.2)) for i in range(-2, 3)]), "Metal", LIGHT, g)
    keep(cyl((0, -0.3, -1.55), 0.7, 0.1, "z", verts=14), "Metal", CHAR, g, name="Fan")


def engine_rotary_skin():
    g = "EngineRotarySkin"
    keep(box((0, -0.6, 0), (3.0, 0.8, 3.0), 0.1), "Metal", CHAR, g, name="Base")
    keep(join("Housings", [cyl((x, 0.1, 0.1), 0.95, 1.3, "z", verts=18) for x in (-1.0, 1.0)]), "Metal", STEEL, g)
    keep(join("Rings", [ring((x, 0.1, -0.6), 0.9, 0.09, "z", maj=20) for x in (-1.0, 1.0)]), "Neon", ORANGE, g, accent=True)
    keep(join("Ports", [cyl((x, 0.95, 0.2), 0.2, 0.5, "y", verts=8) for x in (-1.0, 1.0)]), "CorrodedMetal", RUST, g)
    keep(box((0, 0.3, 1.5), (2.8, 0.9, 0.35), 0.06), "Metal", DARK, g, name="Gearbox")


# ---------------------------------------------------------------------------
# Fuel (block 2 x 2 x 2)
# ---------------------------------------------------------------------------

def fuel_skin():
    g = "FuelSkin"
    keep(box((0, -0.05, 0), (1.2, 1.5, 0.75), 0.07), "SmoothPlastic", (150, 40, 36), g, name="Can")
    keep(box((0.15, 0.88, 0), (0.3, 0.2, 0.3)), "Metal", DARK, g, name="Neck")
    keep(cone((0.15, 1.05, 0), 0.17, 0.16, "y", verts=8, radius2=0.1), "Metal", STEEL, g, name="Cap")
    keep(ring((-0.2, 0.55, 0), 0.28, 0.05, "z", maj=10, mn=5), "Metal", STEEL, g, name="Handle")
    ribs = [box((0, -0.05, 0.38), (1.0, 0.07, 0.04), rot=(0, 0, a)) for a in (38, -38)]
    keep(join("Ribs", ribs), "SmoothPlastic", (120, 28, 26), g)
    keep(box((0.62, 0.05, 0), (0.07, 0.8, 0.5)), "Neon", YELLOW, g, accent=True, name="Stripe")
    keep(join("Feet", [box((x, -0.88, 0), (0.3, 0.14, 0.7)) for x in (-0.4, 0.4)]), "Metal", DARK, g)


def fuel_barrel_skin():
    g = "FuelBarrelSkin"
    keep(cyl((0, 0, 0), 0.8, 1.7, "y", verts=16), "Metal", (60, 90, 60), g, name="Drum")
    keep(join("Hoops", [ring((0, y, 0), 0.82, 0.06, "y", maj=18) for y in (-0.55, 0, 0.55)]), "Metal", STEEL, g)
    keep(ring((0, 0.86, 0), 0.62, 0.07, "y", maj=16), "Neon", YELLOW, g, accent=True, name="Band")
    keep(join("Bungs", [cyl((0.3, 0.9, 0.2), 0.16, 0.1, "y", verts=8), cyl((-0.3, 0.9, -0.2), 0.12, 0.1, "y", verts=8)]),
         "Metal", DARK, g)
    keep(join("Straps", [box((0, y, 0), (1.7, 0.1, 0.1)) for y in (-0.3, 0.3)]), "Metal", CHAR, g)


def fuel_cell_skin():
    g = "FuelCellSkin"
    keep(cyl((0, 0, 0), 0.5, 1.5, "z", verts=14), "Metal", (70, 76, 90), g, name="Tank")
    keep(join("Caps", [sphere((0, 0, z), (0.5, 0.5, 0.2), segs=12, rings=6) for z in (-0.75, 0.75)]), "Metal", STEEL, g)
    keep(ring((0, 0, 0), 0.52, 0.07, "z", maj=16), "Neon", GREEN, g, accent=True, name="Core")
    keep(join("Mounts", [box((0, -0.62, z), (1.3, 0.16, 0.2), 0.03) for z in (-0.45, 0.45)]), "Metal", DARK, g)
    keep(cyl((0, 0.6, 0), 0.13, 0.25, "y", verts=8), "Metal", DARK, g, name="Valve")


# ---------------------------------------------------------------------------
# Seat (block 2 x 2 x 2)
# ---------------------------------------------------------------------------

def seat_skin():
    g = "SeatSkin"
    keep(box((0, -0.6, 0.05), (1.5, 0.35, 1.5), 0.1), "Fabric", (42, 32, 28), g, name="Cushion")
    keep(box((0, 0.1, 0.65), (1.4, 1.35, 0.3), 0.1, rot=(-8, 0, 0)), "Fabric", (36, 28, 24), g, name="Back")
    keep(box((0, 0.95, 0.72), (0.7, 0.35, 0.25), 0.07, rot=(-8, 0, 0)), "Fabric", (36, 28, 24), g, name="Headrest")
    keep(join("Bolsters", [box((x, -0.3, 0.0), (0.2, 0.75, 1.35), 0.07) for x in (-0.82, 0.82)]), "Fabric", (30, 24, 20), g)
    straps = [box((x, 0.1, 0.5), (0.14, 1.3, 0.05), rot=(-8, 0, 0)) for x in (-0.38, 0.38)]
    keep(join("Harness", straps), "Neon", YELLOW, g, accent=True)
    keep(join("Rails", [box((x, -0.88, 0.0), (0.12, 0.14, 1.6)) for x in (-0.55, 0.55)]), "Metal", STEEL, g)
    keep(ring((0, 0.35, 0.9), 0.75, 0.05, "z", maj=14, mn=5), "Metal", STEEL, g, name="RollHoop")


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

def minigun_skin():
    g = "MinigunSkin"
    keep(box((0, -0.2, 0.9), (1.4, 1.0, 1.6), 0.08), "Metal", DARK, g, name="Housing")
    barrels = []
    for i in range(6):
        a = i * math.pi / 3
        barrels.append(cyl((0.3 * math.cos(a), 0.1 + 0.3 * math.sin(a), -0.75), 0.085, 2.6, "z", verts=7))
    keep(join("Barrels", barrels), "Metal", (66, 68, 76), g)
    keep(join("Clamps", [ring((0, 0.1, z), 0.4, 0.07, "z", maj=14, mn=5) for z in (-1.7, -0.9)]), "Metal", STEEL, g)
    keep(ring((0, 0.1, -0.2), 0.46, 0.09, "z", maj=14, mn=5), "Neon", ORANGE, g, accent=True, name="Glow")
    keep(box((0.78, -0.35, 0.8), (0.4, 0.55, 0.8), 0.05), "Metal", RUST, g, name="AmmoBox")
    keep(box((0, -0.8, 0.9), (0.9, 0.2, 0.9), 0.05), "Metal", STEEL, g, name="Mount")
    keep(cyl((0, 0.55, 1.35), 0.18, 0.5, "x", verts=8), "Metal", STEEL, g, name="Handle")


def tesla_skin():
    g = "TeslaSkin"
    keep(box((0, -1.25, 0), (1.9, 0.4, 1.9), 0.07), "Metal", DARK, g, name="Base")
    keep(cyl((0, -0.25, 0), 0.26, 2.0, "y", verts=10), "Metal", STEEL, g, name="Core")
    keep(join("Insulators", [cyl((0, y, 0), 0.4, 0.14, "y", verts=12) for y in (-0.9, -0.5)]), "Metal", WHITE, g)
    coils = [ring((0, y, 0), r, 0.06, "y", maj=14, mn=5) for y, r in ((-0.15, 0.62), (0.2, 0.52), (0.5, 0.42))]
    keep(join("Coils", coils), "Neon", BLUE, g, accent=True)
    prongs = []
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        prongs.append(cyl((0.5 * math.cos(a), 1.0, 0.5 * math.sin(a)), 0.045, 0.9, "y", verts=6))
    keep(join("Prongs", prongs), "Metal", STEEL, g)
    keep(sphere((0, 1.15, 0), (0.4, 0.4, 0.4)), "Neon", BLUE, g, accent=True, name="Orb")


def flame_skin():
    g = "FlameSkin"
    keep(join("Tanks", [cyl((x, -0.15, 0.7), 0.4, 2.0, "z", verts=12) for x in (-0.45, 0.45)]), "Metal", (96, 52, 36), g)
    keep(join("Straps", [box((0, -0.15, z), (1.5, 0.95, 0.1), 0.02) for z in (0.2, 1.2)]), "Metal", DARK, g)
    keep(cyl((0, 0.25, -0.9), 0.2, 1.5, "z", verts=10), "Metal", STEEL, g, name="Barrel")
    keep(cone((0, 0.25, -1.8), 0.3, 0.45, "z", verts=10, radius2=0.12), "Neon", ORANGE, g, accent=True, name="Nozzle")
    keep(sphere((0.35, 0.55, -0.4), (0.09, 0.09, 0.09), segs=8, rings=5), "Neon", BLUE, g, name="Pilot")
    keep(ring((0, 0.7, 0.3), 0.22, 0.04, "y", maj=10, mn=5), "Metal", RED, g, name="Valve")
    keep(box((0, -0.8, 0.7), (1.4, 0.2, 1.8), 0.04), "Metal", DARK, g, name="Cradle")


def rail_skin():
    g = "RailSkin"
    keep(join("Rails", [box((x, 0.1, -0.1), (0.2, 0.3, 4.8), 0.03) for x in (-0.28, 0.28)]), "Metal", (64, 70, 90), g)
    coils = [ring((0, 0.1, z), 0.46, 0.07, "z", maj=14, mn=5) for z in (-2.2, -1.5, -0.8, -0.1, 0.6)]
    keep(join("Coils", coils), "Neon", BLUE, g, accent=True)
    keep(box((0, -0.15, 1.9), (1.3, 0.9, 1.5), 0.07), "Metal", DARK, g, name="Breech")
    keep(join("Capacitors", [cyl((x, 0.45, 1.8), 0.22, 1.1, "z", verts=10) for x in (-0.5, 0.5)]), "Metal", STEEL, g)
    keep(cyl((0, 0.1, -2.7), 0.26, 0.5, "z", verts=10), "Metal", LIGHT, g, name="Brake")
    keep(box((0, -0.65, 0.3), (1.4, 0.18, 2.2), 0.04), "Metal", STEEL, g, name="Sled")


def ram_skin():
    g = "RamSkin"
    blades = []
    for x, yaw in ((-1.2, 22), (1.2, -22)):
        blades.append(box((x, -0.1, -0.25), (2.6, 1.3, 0.2), 0.05, rot=(0, yaw, 0)))
    keep(join("Plow", blades), "Metal", STEEL, g)
    teeth = [cone((i * 0.5, -0.4, -1.15), 0.12, 0.65, "z", verts=4) for i in range(-5, 6)]
    keep(join("Teeth", teeth), "Metal", LIGHT, g)
    keep(box((0, -0.1, 0.65), (5.6, 0.7, 0.4), 0.06), "CorrodedMetal", RUST, g, name="Frame")
    stripes = [box((x, 0.58, -0.25), (0.4, 0.04, 1.6), rot=(0, 0, 0)) for x in (-2.4, -1.2, 0, 1.2, 2.4)]
    keep(join("Hazard", stripes), "Neon", YELLOW, g, accent=True)
    keep(join("Struts", [box((x, -0.55, 0.2), (0.2, 0.18, 1.1)) for x in (-2, 0, 2)]), "Metal", DARK, g)


def shotgun_skin():
    g = "ShotgunSkin"
    keep(join("Barrels", [cyl((x, 0.15, -0.9), 0.24, 2.6, "z", verts=10) for x in (-0.27, 0.27)]), "Metal", (54, 56, 62), g)
    keep(box((0, 0.42, -0.9), (0.2, 0.08, 2.5), 0.02), "Metal", STEEL, g, name="Rib")
    keep(box((0, 0.0, 0.6), (1.2, 1.0, 1.2), 0.08), "Metal", DARK, g, name="Receiver")
    keep(box((0, -0.15, 1.5), (0.8, 0.8, 0.8), 0.08, rot=(0, 0, 0)), "Wood", WOOD, g, name="Stock")
    keep(box((0, -0.45, -0.4), (0.6, 0.35, 0.9), 0.06), "Wood", (120, 82, 50), g, name="Pump")
    keep(join("Muzzle", [ring((x, 0.15, -2.15), 0.27, 0.06, "z", maj=10, mn=5) for x in (-0.27, 0.27)]), "Neon", ORANGE, g, accent=True)
    keep(box((0, -0.85, 0.2), (0.9, 0.18, 1.5), 0.03), "Metal", STEEL, g, name="Mount")


def rocket_skin():
    g = "RocketSkin"
    keep(box((0, -0.1, 0.5), (3.6, 1.7, 2.8), 0.09), "Metal", (62, 68, 56), g, name="Pod")
    tubes = [cyl((-1.2 + 1.2 * ix, -0.55 + 0.9 * iy, -1.1), 0.36, 0.5, "z", verts=12) for ix in range(3) for iy in range(2)]
    keep(join("Tubes", tubes), "Metal", DARK, g)
    noses = [cone((-1.2 + 1.2 * ix, -0.55 + 0.9 * iy, -1.5), 0.26, 0.55, "z", verts=10, flip=True) for ix in range(3) for iy in range(2)]
    keep(join("Warheads", noses), "Neon", RED, g, accent=True)
    keep(join("Vents", [box((x, 0.5, 1.9), (0.5, 0.5, 0.1)) for x in (-1.2, 0, 1.2)]), "Metal", CHAR, g)
    keep(join("Bands", [box((0, -0.1, z), (3.7, 1.8, 0.12), 0.02) for z in (-0.2, 1.1)]), "Metal", STEEL, g)
    keep(box((0, -0.95, 0.5), (1.4, 0.2, 2.2), 0.04), "Metal", DARK, g, name="Mount")


def mine_skin():
    g = "MineSkin"
    keep(box((0, 0.1, 0.4), (3.0, 1.2, 1.3), 0.08), "Metal", (66, 62, 50), g, name="Hopper")
    keep(box((0, -0.6, -0.4), (2.4, 0.18, 1.2), 0.04, rot=(-18, 0, 0)), "Metal", DARK, g, name="Chute")
    keep(join("Discs", [cyl((x, 0.8, 0.4), 0.45, 0.22, "y", verts=14) for x in (-0.9, 0, 0.9)]), "Metal", CHAR, g)
    keep(join("Fuzes", [cone((x, 1.0, 0.4), 0.16, 0.22, "y", verts=8) for x in (-0.9, 0, 0.9)]), "Neon", RED, g, accent=True)
    keep(join("Mines", [cyl((x, -0.85, -0.55), 0.38, 0.18, "y", verts=12) for x in (-0.8, 0.8)]), "Metal", OLIVE, g)
    keep(box((0, -0.85, 0.7), (2.8, 0.2, 1.0), 0.03), "Metal", STEEL, g, name="Mount")


# ---------------------------------------------------------------------------
# Armor (block 4 x 1 x 2, y in [-0.5, 0.5])
# ---------------------------------------------------------------------------

def armor_plate(g, rgb=(74, 78, 86), thickness=0.5):
    keep(box((0, 0, 0), (3.9, thickness, 1.9), 0.09), "DiamondPlate", rgb, g, name="Plate")
    rivets = [cyl((x, thickness / 2 + 0.03, z), 0.1, 0.08, "y", verts=8) for x in (-1.6, -0.55, 0.55, 1.6) for z in (-0.7, 0.7)]
    keep(join("Rivets", rivets), "Metal", CHAR, g)
    keep(box((0, thickness / 2 + 0.02, -0.82), (3.5, 0.06, 0.16)), "Neon", ORANGE, g, accent=True, name="Trim")


def armor_skin():
    armor_plate("ArmorSkin")


def armor_spiked_skin():
    g = "ArmorSpikedSkin"
    armor_plate(g, rgb=(70, 54, 50))
    spikes = [cone((x, 0.4, -0.2 + z * 0.0), 0.16, 0.9, "y", verts=6) for x in (-1.5, -0.75, 0, 0.75, 1.5) for z in (0,)]
    keep(join("Spikes", spikes), "Metal", LIGHT, g)
    fronts = [cone((x, 0.0, -1.15), 0.14, 0.6, "z", verts=6) for x in (-1.25, 0, 1.25)]
    keep(join("FrontSpikes", fronts), "Metal", LIGHT, g)


def armor_heavy_skin():
    g = "ArmorHeavySkin"
    keep(box((0, -0.12, 0), (3.95, 0.7, 1.95), 0.1), "DiamondPlate", (58, 62, 70), g, name="Plate")
    keep(box((0, 0.3, 0), (3.2, 0.2, 1.5), 0.06), "Metal", STEEL, g, name="Overlay")
    keep(join("Bolts", [cyl((x, 0.43, z), 0.14, 0.1, "y", verts=6) for x in (-1.4, 0, 1.4) for z in (-0.55, 0.55)]), "Metal", CHAR, g)
    chev = [box((x, 0.42, 0.0), (0.22, 0.05, 1.7), rot=(0, 0, 0)) for x in (-1.9, 1.9)]
    keep(join("Hazard", chev), "Neon", YELLOW, g, accent=True)


# ---------------------------------------------------------------------------
# Utilities (block 2 x 2 x 2)
# ---------------------------------------------------------------------------

def utility_base(g, rgb=(52, 58, 52)):
    keep(box((0, -0.55, 0), (1.8, 0.8, 1.8), 0.08), "Metal", rgb, g, name="Crate")
    keep(join("Latches", [box((x, -0.35, 0.92), (0.2, 0.25, 0.08)) for x in (-0.6, 0.6)]), "Metal", STEEL, g)


def utility_repair_skin():
    g = "UtilityRepairSkin"
    utility_base(g)
    keep(box((0, 0.1, 0), (1.5, 0.5, 1.5), 0.07), "SmoothPlastic", WHITE, g, name="Box")
    cross = [box((0, 0.38, 0), (0.9, 0.06, 0.3)), box((0, 0.38, 0), (0.3, 0.06, 0.9))]
    keep(join("Cross", cross), "Neon", RED, g, accent=True)
    keep(ring((0.2, 0.75, -0.2), 0.34, 0.07, "y", maj=12, mn=5), "Metal", STEEL, g, name="Wrench")


def utility_boost_skin():
    g = "UtilityBoostSkin"
    utility_base(g, (40, 46, 60))
    bottles = [cyl((x, 0.3, 0), 0.36, 1.2, "y", verts=14) for x in (-0.45, 0.45)]
    keep(join("Bottles", bottles), "Metal", (70, 80, 100), g)
    keep(join("Domes", [sphere((x, 0.9, 0), (0.36, 0.28, 0.36)) for x in (-0.45, 0.45)]), "Metal", STEEL, g)
    keep(join("Bands", [ring((x, 0.3, 0), 0.37, 0.06, "y", maj=14) for x in (-0.45, 0.45)]), "Neon", BLUE, g, accent=True)
    keep(box((0, 1.1, 0), (1.0, 0.14, 0.14)), "Metal", RED, g, name="Valve")
    keep(ring((0, 0.7, 0.35), 0.45, 0.05, "x", maj=14, mn=5), "Metal", DARK, g, name="Hose")


def utility_magnet_skin():
    g = "UtilityMagnetSkin"
    utility_base(g)
    keep(box((0, 0.85, 0), (1.5, 0.35, 0.5), 0.05), "Metal", RED, g, name="Bridge")
    keep(join("Legs", [box((x, 0.2, 0), (0.4, 0.9, 0.5), 0.05) for x in (-0.55, 0.55)]), "Metal", RED, g)
    keep(join("Tips", [box((x, -0.18, 0), (0.42, 0.18, 0.52), 0.03) for x in (-0.55, 0.55)]), "Neon", LIGHT, g, accent=True)
    keep(join("Coil", [ring((x, 0.35, 0), 0.3, 0.06, "y", maj=10, mn=5) for x in (-0.55, 0.55)]), "Metal", (180, 120, 60), g)


def utility_salvage_skin():
    g = "UtilitySalvageSkin"
    utility_base(g, (66, 58, 42))
    keep(cyl((0, 0.35, 0), 0.7, 0.35, "z", verts=16), "Metal", STEEL, g, name="Gear")
    teeth = [box((0.78 * math.cos(i * math.pi / 4), 0.35 + 0.78 * math.sin(i * math.pi / 4), 0),
                 (0.26, 0.26, 0.36), rot=(0, 0, 0)) for i in range(8)]
    keep(join("Teeth", teeth), "Metal", LIGHT, g)
    keep(cyl((0, 0.35, 0), 0.25, 0.42, "z", verts=10), "Neon", YELLOW, g, accent=True, name="Hub")
    keep(box((0, 0.35, -0.55), (1.8, 0.2, 0.15)), "Metal", DARK, g, name="Guard")


def utility_shield_skin():
    g = "UtilityShieldSkin"
    utility_base(g, (36, 52, 62))
    keep(cyl((0, -0.05, 0), 0.7, 0.2, "y", verts=16), "Metal", CHAR, g, name="Emitter")
    keep(ring((0, 0.05, 0), 0.7, 0.07, "y", maj=18), "Neon", BLUE, g, accent=True, name="Ring")
    keep(sphere((0, 0.5, 0), (0.55, 0.55, 0.55), segs=14, rings=8), "ForceField", (150, 220, 255), g, name="Dome")
    keep(cyl((0, 0.5, 0), 0.12, 0.6, "y", verts=8), "Neon", WHITE, g, name="Core")


def utility_siphon_skin():
    g = "UtilitySiphonSkin"
    utility_base(g, (44, 56, 44))
    keep(cyl((-0.4, 0.2, 0), 0.4, 1.0, "y", verts=14), "Metal", (66, 90, 66), g, name="Tank")
    keep(box((0.5, 0.0, 0), (0.7, 0.8, 0.8), 0.06), "Metal", DARK, g, name="Pump")
    keep(ring((0.05, 0.75, 0), 0.5, 0.07, "x", maj=14, mn=5), "Neon", GREEN, g, accent=True, name="Hose")
    keep(cyl((0.5, 0.55, 0), 0.14, 0.3, "y", verts=8), "Metal", STEEL, g, name="Nozzle")


BUILDERS = [
    engine_skin, engine_turbo_skin, engine_diesel_skin, engine_rotary_skin,
    fuel_skin, fuel_barrel_skin, fuel_cell_skin, seat_skin,
    minigun_skin, tesla_skin, flame_skin, rail_skin, ram_skin, shotgun_skin, rocket_skin, mine_skin,
    armor_skin, armor_spiked_skin, armor_heavy_skin,
    utility_repair_skin, utility_boost_skin, utility_magnet_skin, utility_salvage_skin,
    utility_shield_skin, utility_siphon_skin,
]

# Lay every skin out in a grid for a visual check; export uses original coords
# so each skin is built at the origin and moved afterwards.
for build in BUILDERS:
    build()


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


groups = {}
order = []
for ob, material, rgb, accent, group in pieces:
    data = export_mesh(ob)
    data["material"] = material
    data["color"] = list(rgb)
    data["accent"] = accent
    if group not in groups:
        groups[group] = {"name": group, "folder": "skin", "parts": []}
        order.append(group)
    groups[group]["parts"].append(data)

os.makedirs(OUT_DIR, exist_ok=True)
total_tris = 0
for name in order:
    item = groups[name]
    with open(os.path.join(OUT_DIR, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(item, f, separators=(",", ":"))
    tris = sum(p["counts"][1] for p in item["parts"])
    total_tris += tris
    print(f"{name}: {len(item['parts'])} parts, {tris} tris")
print("WROTE", len(order), "skins,", total_tris, "tris total")

# Leave the scene arranged for inspection: one row per skin group.
group_objs = {}
for ob, material, rgb, accent, group in pieces:
    group_objs.setdefault(group, []).append(ob)
for index, name in enumerate(order):
    col, rw = index % 5, index // 5
    for ob in group_objs[name]:
        ob.location.x += col * 7
        ob.location.y += rw * 7

# Tint the objects so the inspection view shows each part's in-game colour.
for ob, material, rgb, accent, group in pieces:
    ob.color = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
for area in bpy.context.screen.areas if bpy.context.screen else []:
    if area.type == "VIEW_3D":
        area.spaces[0].shading.type = "SOLID"
        area.spaces[0].shading.color_type = "OBJECT"
