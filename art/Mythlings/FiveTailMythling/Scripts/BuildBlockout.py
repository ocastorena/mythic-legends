"""Build the approved five-tail Mythling blockout in Blender.

Run with:
    blender --background --python BuildBlockout.py

The script intentionally creates an unrigged approval mesh. The final mesh,
UV atlas, armature, and animations are produced only after blockout approval.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ASSET_DIR = Path(__file__).resolve().parents[1]
RENDER_DIR = ASSET_DIR / "Renders" / "BlockoutV1"
BLEND_PATH = ASSET_DIR / "FiveTailMythling_BlockoutV1.blend"

FORWARD = Vector((0.0, -1.0, 0.0))
UP = Vector((0.0, 0.0, 1.0))


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.82) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    return material


def link_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)


def create_ico(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    subdivisions: int = 2,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    accent_material: bpy.types.Material | None = None,
    dark_material: bpy.types.Material | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    link_to_collection(obj, collection)
    obj.data.materials.append(material)
    if accent_material:
        obj.data.materials.append(accent_material)
    if dark_material:
        obj.data.materials.append(dark_material)

    # Subtle planar variation makes the blockout read like the concept while
    # retaining a small, deterministic palette.
    for polygon in obj.data.polygons:
        if dark_material and polygon.center.z < -0.18:
            polygon.material_index = len(obj.data.materials) - 1
        elif accent_material and polygon.normal.z > 0.58 and polygon.index % 5 == 0:
            polygon.material_index = 1
        else:
            polygon.material_index = 0

    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_prism_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    start_radius: float,
    end_radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    sides: int = 6,
    width_scale: float = 1.0,
    depth_scale: float = 0.82,
    alternate_material: bpy.types.Material | None = None,
) -> bpy.types.Object:
    start_v = Vector(start)
    end_v = Vector(end)
    axis = (end_v - start_v).normalized()
    reference = UP if abs(axis.dot(UP)) < 0.94 else Vector((1.0, 0.0, 0.0))
    basis_x = axis.cross(reference).normalized()
    basis_y = axis.cross(basis_x).normalized()

    vertices: list[tuple[float, float, float]] = []
    for point, radius in ((start_v, start_radius), (end_v, end_radius)):
        for index in range(sides):
            angle = math.tau * index / sides
            offset = (
                basis_x * math.cos(angle) * radius * width_scale
                + basis_y * math.sin(angle) * radius * depth_scale
            )
            vertices.append(tuple(point + offset))

    faces: list[tuple[int, ...]] = []
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, sides * 2)))
    for index in range(sides):
        next_index = (index + 1) % sides
        faces.append((index, next_index, sides + next_index, sides + index))

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    if alternate_material:
        obj.data.materials.append(alternate_material)
        for polygon in obj.data.polygons:
            if polygon.index >= 2 and polygon.index % 3 == 0:
                polygon.material_index = 1
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_poly_tube(
    name: str,
    points: list[tuple[float, float, float]],
    radii: list[float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    sides: int = 7,
    width_scale: float = 1.0,
    depth_scale: float = 0.76,
    alternate_material: bpy.types.Material | None = None,
) -> bpy.types.Object:
    vectors = [Vector(point) for point in points]
    vertices: list[tuple[float, float, float]] = []

    for index, point in enumerate(vectors):
        if index == 0:
            tangent = (vectors[1] - point).normalized()
        elif index == len(vectors) - 1:
            tangent = (point - vectors[index - 1]).normalized()
        else:
            tangent = (vectors[index + 1] - vectors[index - 1]).normalized()

        reference = UP if abs(tangent.dot(UP)) < 0.92 else Vector((1.0, 0.0, 0.0))
        basis_x = tangent.cross(reference).normalized()
        basis_y = tangent.cross(basis_x).normalized()
        for side_index in range(sides):
            angle = math.tau * side_index / sides
            offset = (
                basis_x * math.cos(angle) * radii[index] * width_scale
                + basis_y * math.sin(angle) * radii[index] * depth_scale
            )
            vertices.append(tuple(point + offset))

    faces: list[tuple[int, ...]] = []
    faces.append(tuple(range(sides - 1, -1, -1)))
    last_start = (len(vectors) - 1) * sides
    faces.append(tuple(range(last_start, last_start + sides)))
    for ring_index in range(len(vectors) - 1):
        ring_start = ring_index * sides
        next_start = (ring_index + 1) * sides
        for side_index in range(sides):
            next_side = (side_index + 1) % sides
            faces.append(
                (
                    ring_start + side_index,
                    ring_start + next_side,
                    next_start + next_side,
                    next_start + side_index,
                )
            )

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    if alternate_material:
        obj.data.materials.append(alternate_material)
        for polygon in obj.data.polygons:
            if polygon.index >= 2 and polygon.index % 4 == 0:
                polygon.material_index = 1
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_wedge(
    name: str,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    mirror_x: bool = False,
    rotation_z: float = 0.0,
) -> bpy.types.Object:
    sx, sy, sz = size
    direction = -1.0 if mirror_x else 1.0
    vertices = [
        (-sx * direction, -sy, -sz),
        (sx * direction, -sy, -sz * 0.62),
        (sx * 0.25 * direction, -sy, sz),
        (-sx * direction, sy, -sz),
        (sx * direction, sy, -sz * 0.62),
        (sx * 0.25 * direction, sy, sz),
    ]
    faces = [
        (0, 2, 1),
        (3, 4, 5),
        (0, 1, 4, 3),
        (1, 2, 5, 4),
        (2, 0, 3, 5),
    ]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = center
    obj.rotation_euler.z = rotation_z
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_face_plate(
    name: str,
    vertices: list[tuple[float, float, float]],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_paw(
    name: str,
    location: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    facing_front: bool,
) -> bpy.types.Object:
    scale = (0.42, 0.68 if facing_front else 0.56, 0.24)
    offset_y = -0.18 if facing_front else -0.08
    paw = create_ico(
        name,
        (location[0], location[1] + offset_y, location[2]),
        scale,
        material,
        collection,
        subdivisions=1,
    )
    paw["CollisionProxyHint"] = "Use simple Studio box/capsule collision"
    return paw


def create_leg(
    prefix: str,
    hip: tuple[float, float, float],
    joint: tuple[float, float, float],
    ankle: tuple[float, float, float],
    paw: tuple[float, float, float],
    material: bpy.types.Material,
    dark: bpy.types.Material,
    collection: bpy.types.Collection,
    front: bool,
) -> list[bpy.types.Object]:
    upper = create_prism_between(
        f"{prefix}_Upper",
        hip,
        joint,
        0.39 if front else 0.52,
        0.31,
        material,
        collection,
        width_scale=1.0,
        depth_scale=0.86,
        alternate_material=dark,
    )
    lower = create_prism_between(
        f"{prefix}_Lower",
        joint,
        ankle,
        0.31,
        0.22,
        material,
        collection,
        width_scale=0.9,
        depth_scale=0.78,
        alternate_material=dark,
    )
    foot = create_paw(f"{prefix}_Paw", paw, dark, collection, facing_front=front)
    return [upper, lower, foot]


def create_ear(
    prefix: str,
    x: float,
    y: float,
    z: float,
    width: float,
    height: float,
    splay: float,
    charcoal: bpy.types.Material,
    cyan: bpy.types.Material,
    collection: bpy.types.Collection,
) -> list[bpy.types.Object]:
    mirror = x < 0.0
    outer = create_wedge(
        f"{prefix}_Outer",
        (x, y, z),
        (width, 0.22, height),
        charcoal,
        collection,
        mirror_x=mirror,
        rotation_z=splay,
    )
    inner = create_wedge(
        f"{prefix}_Inner",
        (x, y - 0.235, z - height * 0.08),
        (width * 0.56, 0.025, height * 0.67),
        cyan,
        collection,
        mirror_x=mirror,
        rotation_z=splay,
    )
    return [outer, inner]


def create_tail(
    index: int,
    points: list[tuple[float, float, float]],
    radii: list[float],
    charcoal: bpy.types.Material,
    slate: bpy.types.Material,
    cyan: bpy.types.Material,
    collection: bpy.types.Collection,
) -> list[bpy.types.Object]:
    body_points = points[:-1]
    body_radii = radii[:-1]
    body = create_poly_tube(
        f"Tail_{index:02d}_Body",
        body_points,
        body_radii,
        charcoal,
        collection,
        sides=7,
        width_scale=1.18,
        depth_scale=0.72,
        alternate_material=slate,
    )
    tip = create_poly_tube(
        f"Tail_{index:02d}_CyanTip",
        points[-2:],
        radii[-2:],
        cyan,
        collection,
        sides=7,
        width_scale=1.16,
        depth_scale=0.7,
    )
    body["FutureTailChain"] = f"Tail_{index:02d}_01..04"
    tip["FutureTailChain"] = f"Tail_{index:02d}_04"
    return [body, tip]


def add_camera(
    name: str,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    ortho_scale: float,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    camera_data = bpy.data.cameras.new(name)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new(name, camera_data)
    collection.objects.link(camera)
    camera.location = location
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return camera


def add_area_light(
    name: str,
    location: tuple[float, float, float],
    energy: float,
    size: float,
    collection: bpy.types.Collection,
    color: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> bpy.types.Object:
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    collection.objects.link(light)
    light.location = location
    light.rotation_euler = (0.0, 0.0, 0.0)
    direction = Vector((0.0, 0.5, 2.7)) - light.location
    light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return light


def triangulated_face_count(objects: list[bpy.types.Object]) -> int:
    total = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    return total


def render_views(scene: bpy.types.Scene, cameras: dict[str, bpy.types.Object]) -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    for view_name, camera in cameras.items():
        scene.camera = camera
        scene.render.filepath = str(RENDER_DIR / f"FiveTailMythling_{view_name}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_percentage = 100
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.color = (0.055, 0.065, 0.085)

    model_collection = bpy.data.collections.new("FiveTailMythling_Blockout")
    render_collection = bpy.data.collections.new("Render_Setup")
    scene.collection.children.link(model_collection)
    scene.collection.children.link(render_collection)

    root = bpy.data.objects.new("FiveTailMythling_ROOT", None)
    model_collection.objects.link(root)
    root["Stage"] = "BlockoutV1"
    root["TailCount"] = 5
    root["Runes"] = "Deferred to texture"
    root["TargetUse"] = "Player-sized arena Mythling; up to 20 visible"
    root["ForwardAxis"] = "-Y"
    root["UpAxis"] = "Z"

    charcoal = make_material("Palette_Charcoal", (0.075, 0.095, 0.14, 1.0))
    slate = make_material("Palette_Slate", (0.18, 0.22, 0.31, 1.0))
    mid_gray = make_material("Palette_MidGray", (0.28, 0.32, 0.40, 1.0))
    dark = make_material("Palette_DeepShadow", (0.018, 0.025, 0.045, 1.0))
    blue = make_material("Palette_Blue", (0.015, 0.25, 0.72, 1.0), roughness=0.62)
    cyan = make_material("Palette_Cyan", (0.02, 0.72, 1.0, 1.0), roughness=0.5)
    black = make_material("Palette_Black", (0.004, 0.006, 0.012, 1.0))

    objects: list[bpy.types.Object] = []

    # Torso and shoulder mass.
    objects.append(create_ico("Body_Core", (0.0, 0.05, 3.05), (1.18, 2.0, 1.08), charcoal, model_collection, 2, accent_material=slate, dark_material=dark))
    objects.append(create_ico("Chest", (0.0, -1.25, 3.32), (1.03, 1.1, 1.34), slate, model_collection, 2, accent_material=mid_gray, dark_material=dark))
    objects.append(create_ico("Hindquarters", (0.0, 1.22, 3.05), (1.16, 1.06, 1.03), charcoal, model_collection, 2, accent_material=slate, dark_material=dark))
    objects.append(create_ico("Neck", (0.0, -1.72, 3.91), (0.82, 0.8, 1.26), charcoal, model_collection, 2, rotation=(math.radians(-18), 0.0, 0.0), accent_material=slate, dark_material=dark))
    objects.append(create_wedge("Chest_Mane", (0.0, -2.0, 3.37), (0.72, 0.4, 1.02), dark, model_collection))

    # Head, muzzle, nose, four ears, cheek plates, and rigid glowing eyes.
    objects.append(create_ico("Head", (0.0, -2.35, 4.56), (0.94, 0.85, 0.72), mid_gray, model_collection, 2, accent_material=slate, dark_material=charcoal))
    objects.append(create_ico("Muzzle", (0.0, -3.02, 4.25), (0.49, 0.70, 0.38), slate, model_collection, 1, accent_material=mid_gray, dark_material=dark))
    objects.append(create_ico("Nose", (0.0, -3.66, 4.24), (0.31, 0.24, 0.20), black, model_collection, 1))
    objects.extend(create_ear("Ear_Main_L", -0.48, -2.24, 5.36, 0.48, 1.05, math.radians(-6), charcoal, blue, model_collection))
    objects.extend(create_ear("Ear_Main_R", 0.48, -2.24, 5.36, 0.48, 1.05, math.radians(6), charcoal, blue, model_collection))
    objects.extend(create_ear("Ear_Outer_L", -0.94, -2.15, 5.05, 0.38, 0.74, math.radians(-18), charcoal, blue, model_collection))
    objects.extend(create_ear("Ear_Outer_R", 0.94, -2.15, 5.05, 0.38, 0.74, math.radians(18), charcoal, blue, model_collection))
    objects.append(create_wedge("Cheek_L", (-0.70, -2.83, 4.14), (0.34, 0.13, 0.31), cyan, model_collection, mirror_x=True, rotation_z=math.radians(-8)))
    objects.append(create_wedge("Cheek_R", (0.70, -2.83, 4.14), (0.34, 0.13, 0.31), cyan, model_collection, mirror_x=False, rotation_z=math.radians(8)))
    objects.append(
        create_face_plate(
            "Eye_L",
            [
                (-0.64, -3.105, 4.67),
                (-0.25, -3.195, 4.64),
                (-0.30, -3.215, 4.50),
                (-0.57, -3.145, 4.54),
            ],
            cyan,
            model_collection,
        )
    )
    objects.append(
        create_face_plate(
            "Eye_R",
            [
                (0.25, -3.195, 4.64),
                (0.64, -3.105, 4.67),
                (0.57, -3.145, 4.54),
                (0.30, -3.215, 4.50),
            ],
            cyan,
            model_collection,
        )
    )

    # Animation-neutral legs with readable bend direction and paw placement.
    leg_specs = [
        ("Leg_FL", (-0.75, -1.25, 3.65), (-0.79, -1.48, 2.18), (-0.76, -1.46, 0.43), (-0.76, -1.54, 0.23), True),
        ("Leg_FR", (0.75, -1.25, 3.65), (0.79, -1.48, 2.18), (0.76, -1.46, 0.43), (0.76, -1.54, 0.23), True),
        ("Leg_HL", (-0.78, 1.03, 3.36), (-0.86, 1.50, 2.12), (-0.72, 0.92, 0.43), (-0.72, 0.73, 0.23), False),
        ("Leg_HR", (0.78, 1.03, 3.36), (0.86, 1.50, 2.12), (0.72, 0.92, 0.43), (0.72, 0.73, 0.23), False),
    ]
    for prefix, hip, joint, ankle, paw, front in leg_specs:
        objects.extend(create_leg(prefix, hip, joint, ankle, paw, charcoal, dark, model_collection, front))

    # Five independently readable tails: center chain plus two mirrored pairs.
    tail_specs = [
        [
            (0.0, 1.72, 3.32),
            (0.0, 2.65, 3.92),
            (0.0, 4.15, 4.72),
            (0.0, 5.60, 5.10),
            (0.0, 6.55, 5.62),
        ],
        [
            (-0.20, 1.68, 3.28),
            (-0.52, 2.63, 3.64),
            (-1.10, 4.05, 4.00),
            (-1.80, 5.42, 4.05),
            (-2.45, 6.28, 4.50),
        ],
        [
            (0.20, 1.68, 3.28),
            (0.52, 2.63, 3.64),
            (1.10, 4.05, 4.00),
            (1.80, 5.42, 4.05),
            (2.45, 6.28, 4.50),
        ],
        [
            (-0.36, 1.58, 3.05),
            (-0.76, 2.46, 2.98),
            (-1.55, 3.72, 2.70),
            (-2.42, 4.92, 2.50),
            (-3.10, 5.76, 2.72),
        ],
        [
            (0.36, 1.58, 3.05),
            (0.76, 2.46, 2.98),
            (1.55, 3.72, 2.70),
            (2.42, 4.92, 2.50),
            (3.10, 5.76, 2.72),
        ],
    ]
    for index, points in enumerate(tail_specs, start=1):
        objects.extend(create_tail(index, points, [0.34, 0.52, 0.68, 0.47, 0.035], charcoal, slate, cyan, model_collection))

    for obj in objects:
        obj.parent = root

    # Floor and neutral studio lighting exist only in the render collection.
    floor_material = make_material("Render_Floor", (0.16, 0.18, 0.22, 1.0), roughness=1.0)
    bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0.0, 0.5, 0.0))
    floor = bpy.context.object
    floor.name = "Render_Floor"
    floor.data.materials.append(floor_material)
    link_to_collection(floor, render_collection)

    add_area_light("Key_Light", (-7.0, -8.0, 11.0), 1450.0, 6.0, render_collection, (0.78, 0.88, 1.0))
    add_area_light("Fill_Light", (8.0, -3.0, 7.0), 1050.0, 5.0, render_collection, (0.42, 0.62, 1.0))
    add_area_light("Rim_Light", (0.0, 8.0, 10.0), 1750.0, 5.0, render_collection, (0.05, 0.42, 1.0))

    cameras = {
        "Front": add_camera("Camera_Front", (0.0, -16.0, 3.35), (0.0, 0.6, 3.1), 7.2, render_collection),
        "Left": add_camera("Camera_Left", (-15.5, 0.8, 3.6), (0.0, 1.15, 3.2), 10.8, render_collection),
        "Rear": add_camera("Camera_Rear", (0.0, 16.0, 3.5), (0.0, 1.7, 3.3), 7.7, render_collection),
        "Top": add_camera("Camera_Top", (0.0, 1.1, 17.0), (0.0, 1.1, 0.0), 11.8, render_collection),
        "ThreeQuarter": add_camera("Camera_ThreeQuarter", (9.6, -12.8, 7.3), (0.0, 1.1, 3.1), 11.4, render_collection),
    }

    triangle_count = triangulated_face_count(objects)
    root["BlockoutTriangles"] = triangle_count
    root["ObjectCount"] = len(objects)
    root["ApproxHeight"] = 6.41
    root["ApproxBodyLength"] = 5.40
    root["ApproxFullLengthWithTails"] = 10.23

    scene.camera = cameras["ThreeQuarter"]
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    render_views(scene, cameras)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    print(f"BLOCKOUT_BLEND={BLEND_PATH}")
    print(f"BLOCKOUT_RENDER_DIR={RENDER_DIR}")
    print(f"BLOCKOUT_TRIANGLES={triangle_count}")
    print(f"BLOCKOUT_OBJECTS={len(objects)}")


if __name__ == "__main__":
    main()
