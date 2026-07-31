"""Build the improved single-object Mythling production base.

This script is intended to be executed inside the live Blender session through
Blender MCP. It preserves the rough V1 collection as a hidden scale reference,
creates one render-mesh object, adds the original concept as a camera
background, renders approval views, and saves a new .blend.

The V2 mesh is a silhouette/volume approval base. Final welded deformation
topology, UVs, armature, weights, and animation follow visual approval.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Euler, Vector


ASSET_DIR = Path(__file__).resolve().parents[1]
REFERENCE_PATH = Path("/Users/omar/Downloads/Gemini_Generated_Image_3utdxt3utdxt3utd.png")
OUTPUT_BLEND = ASSET_DIR / "FiveTailMythling_ProductionBaseV2.blend"
RENDER_DIR = ASSET_DIR / "Renders" / "ProductionBaseV2"

PRODUCTION_COLLECTION = "FiveTailMythling_ProductionBaseV2"
REFERENCE_COLLECTION = "FiveTailMythling_Reference"
RENDER_COLLECTION = "FiveTailMythling_RenderSetupV2"


def remove_collection(name: str) -> None:
    collection = bpy.data.collections.get(name)
    if not collection:
        return
    for obj in list(collection.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float = 0.82,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing:
        bpy.data.materials.remove(existing, do_unlink=True)
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    if emission_strength > 0.0:
        if "Emission Color" in shader.inputs:
            shader.inputs["Emission Color"].default_value = color
        if "Emission Strength" in shader.inputs:
            shader.inputs["Emission Strength"].default_value = emission_strength
    return material


class MeshBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.materials: list[int] = []
        self.components: dict[str, tuple[int, int]] = {}

    def add_vertex(self, value: Vector | tuple[float, float, float]) -> int:
        self.vertices.append(tuple(value))
        return len(self.vertices) - 1

    def add_face(self, indices: tuple[int, ...] | list[int], material_index: int) -> None:
        self.faces.append(tuple(indices))
        self.materials.append(material_index)

    def mark_component(self, name: str, face_start: int) -> None:
        self.components[name] = (face_start, len(self.faces))

    def add_ellipsoid(
        self,
        name: str,
        center: tuple[float, float, float],
        radii: tuple[float, float, float],
        material_index: int,
        *,
        segments: int = 12,
        rings: int = 6,
        rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
        lower_material_index: int | None = None,
    ) -> None:
        face_start = len(self.faces)
        center_v = Vector(center)
        rotation_matrix = Euler(rotation, "XYZ").to_matrix()

        top = self.add_vertex(center_v + rotation_matrix @ Vector((0.0, 0.0, radii[2])))
        ring_indices: list[list[int]] = []
        for ring in range(1, rings):
            theta = math.pi * ring / rings
            z = math.cos(theta) * radii[2]
            ring_radius = math.sin(theta)
            current: list[int] = []
            for segment in range(segments):
                phi = math.tau * segment / segments
                local = Vector(
                    (
                        math.cos(phi) * radii[0] * ring_radius,
                        math.sin(phi) * radii[1] * ring_radius,
                        z,
                    )
                )
                current.append(self.add_vertex(center_v + rotation_matrix @ local))
            ring_indices.append(current)
        bottom = self.add_vertex(center_v + rotation_matrix @ Vector((0.0, 0.0, -radii[2])))

        first = ring_indices[0]
        for segment in range(segments):
            self.add_face((top, first[segment], first[(segment + 1) % segments]), material_index)

        for ring_index in range(len(ring_indices) - 1):
            upper = ring_indices[ring_index]
            lower = ring_indices[ring_index + 1]
            for segment in range(segments):
                mat = material_index
                if lower_material_index is not None and ring_index >= len(ring_indices) // 2:
                    mat = lower_material_index
                self.add_face(
                    (
                        upper[segment],
                        lower[segment],
                        lower[(segment + 1) % segments],
                        upper[(segment + 1) % segments],
                    ),
                    mat,
                )

        last = ring_indices[-1]
        for segment in range(segments):
            mat = lower_material_index if lower_material_index is not None else material_index
            self.add_face((last[(segment + 1) % segments], last[segment], bottom), mat)
        self.mark_component(name, face_start)

    def add_loft(
        self,
        name: str,
        points: list[tuple[float, float, float]],
        widths: list[float],
        heights: list[float],
        segment_materials: list[int],
        *,
        sides: int = 8,
        cap_start: bool = True,
        cap_end: bool = True,
        roll: float = 0.0,
    ) -> None:
        face_start = len(self.faces)
        vectors = [Vector(point) for point in points]
        rings: list[list[int]] = []

        for index, point in enumerate(vectors):
            if index == 0:
                tangent = (vectors[1] - point).normalized()
            elif index == len(vectors) - 1:
                tangent = (point - vectors[index - 1]).normalized()
            else:
                tangent = (vectors[index + 1] - vectors[index - 1]).normalized()

            reference = Vector((0.0, 0.0, 1.0))
            if abs(tangent.dot(reference)) > 0.94:
                reference = Vector((1.0, 0.0, 0.0))
            axis_x = tangent.cross(reference).normalized()
            axis_z = tangent.cross(axis_x).normalized()
            if roll:
                rotated_x = axis_x * math.cos(roll) + axis_z * math.sin(roll)
                rotated_z = -axis_x * math.sin(roll) + axis_z * math.cos(roll)
                axis_x, axis_z = rotated_x, rotated_z

            ring: list[int] = []
            for side in range(sides):
                angle = math.tau * side / sides
                offset = (
                    axis_x * math.cos(angle) * widths[index]
                    + axis_z * math.sin(angle) * heights[index]
                )
                ring.append(self.add_vertex(point + offset))
            rings.append(ring)

        if cap_start:
            self.add_face(tuple(reversed(rings[0])), segment_materials[0])
        if cap_end:
            self.add_face(tuple(rings[-1]), segment_materials[-1])

        for ring_index in range(len(rings) - 1):
            mat = segment_materials[min(ring_index, len(segment_materials) - 1)]
            current = rings[ring_index]
            following = rings[ring_index + 1]
            for side in range(sides):
                next_side = (side + 1) % sides
                self.add_face(
                    (
                        current[side],
                        following[side],
                        following[next_side],
                        current[next_side],
                    ),
                    mat,
                )
        self.mark_component(name, face_start)

    def add_ear(
        self,
        name: str,
        root: tuple[float, float, float],
        width: float,
        height: float,
        depth: float,
        splay: float,
        outer_material: int,
        inner_material: int,
    ) -> None:
        face_start = len(self.faces)
        root_v = Vector(root)
        sign = -1.0 if root[0] < 0.0 else 1.0
        tip = root_v + Vector((math.sin(splay) * height * sign, 0.04, math.cos(splay) * height))
        left = root_v + Vector((-width, -depth * 0.45, 0.0))
        right = root_v + Vector((width, -depth * 0.45, 0.0))
        back_left = root_v + Vector((-width * 0.85, depth * 0.55, 0.0))
        back_right = root_v + Vector((width * 0.85, depth * 0.55, 0.0))
        back_tip = tip + Vector((0.0, depth * 0.72, -0.08))

        indices = [self.add_vertex(v) for v in (left, right, tip, back_left, back_right, back_tip)]
        self.add_face((indices[0], indices[2], indices[1]), outer_material)
        self.add_face((indices[3], indices[4], indices[5]), outer_material)
        self.add_face((indices[0], indices[1], indices[4], indices[3]), outer_material)
        self.add_face((indices[1], indices[2], indices[5], indices[4]), outer_material)
        self.add_face((indices[2], indices[0], indices[3], indices[5]), outer_material)

        inset_center = root_v + Vector((0.0, -depth * 0.50, height * 0.08))
        inset_tip = tip + Vector((0.0, -depth * 0.50, -height * 0.18))
        inset_left = inset_center + Vector((-width * 0.50, 0.0, 0.0))
        inset_right = inset_center + Vector((width * 0.50, 0.0, 0.0))
        inner = [self.add_vertex(v) for v in (inset_left, inset_tip, inset_right)]
        self.add_face((inner[0], inner[1], inner[2]), inner_material)
        self.mark_component(name, face_start)

    def add_plate(
        self,
        name: str,
        points: list[tuple[float, float, float]],
        material_index: int,
    ) -> None:
        face_start = len(self.faces)
        indices = [self.add_vertex(point) for point in points]
        self.add_face(tuple(indices), material_index)
        self.mark_component(name, face_start)


def add_materials() -> list[bpy.types.Material]:
    return [
        make_material("V2_Charcoal", (0.045, 0.060, 0.095, 1.0)),
        make_material("V2_Slate", (0.105, 0.118, 0.155, 1.0)),
        make_material("V2_MidGray", (0.220, 0.238, 0.280, 1.0)),
        make_material("V2_DeepShadow", (0.010, 0.014, 0.027, 1.0)),
        make_material("V2_Blue", (0.010, 0.205, 0.590, 1.0), roughness=0.62, emission_strength=0.12),
        make_material("V2_Cyan", (0.010, 0.600, 1.000, 1.0), roughness=0.48, emission_strength=0.38),
        make_material("V2_Black", (0.002, 0.004, 0.009, 1.0)),
    ]


def build_render_mesh(collection: bpy.types.Collection, materials: list[bpy.types.Material]) -> bpy.types.Object:
    CHARCOAL, SLATE, MID, SHADOW, BLUE, CYAN, BLACK = range(7)
    builder = MeshBuilder()

    # Strong wolf body: high shoulder, narrow ribcage, muscular haunches.
    builder.add_ellipsoid("Torso", (0.0, 0.05, 3.10), (1.03, 1.78, 0.92), CHARCOAL, segments=14, rings=7, lower_material_index=SHADOW)
    builder.add_ellipsoid("Chest", (0.0, -1.17, 3.40), (0.96, 0.98, 1.23), SLATE, segments=14, rings=7, lower_material_index=SHADOW)
    builder.add_ellipsoid("Haunches", (0.0, 1.22, 3.08), (1.03, 1.02, 1.00), CHARCOAL, segments=14, rings=7, lower_material_index=SHADOW)
    builder.add_ellipsoid(
        "Neck",
        (0.0, -1.74, 4.00),
        (0.79, 0.72, 1.13),
        CHARCOAL,
        segments=12,
        rings=6,
        rotation=(math.radians(-18.0), 0.0, 0.0),
        lower_material_index=SHADOW,
    )

    # Layered angular chest mane.
    builder.add_loft(
        "ChestMane",
        [(0.0, -2.05, 4.18), (0.0, -2.12, 3.55), (0.0, -2.00, 2.92)],
        [0.68, 0.84, 0.48],
        [0.25, 0.34, 0.16],
        [SHADOW, SHADOW],
        sides=6,
    )

    # Wolf head and rigid jaw.
    builder.add_ellipsoid("Cranium", (0.0, -2.46, 4.70), (0.87, 0.80, 0.64), MID, segments=14, rings=7, lower_material_index=CHARCOAL)
    builder.add_loft(
        "UpperMuzzle",
        [(0.0, -2.84, 4.51), (0.0, -3.31, 4.40), (0.0, -3.76, 4.33)],
        [0.60, 0.45, 0.29],
        [0.37, 0.29, 0.21],
        [SLATE, MID],
        sides=8,
    )
    builder.add_loft(
        "Jaw",
        [(0.0, -2.88, 4.20), (0.0, -3.35, 4.10), (0.0, -3.66, 4.13)],
        [0.50, 0.35, 0.22],
        [0.22, 0.18, 0.12],
        [SHADOW, CHARCOAL],
        sides=8,
    )
    builder.add_ellipsoid("Nose", (0.0, -3.86, 4.33), (0.31, 0.19, 0.20), BLACK, segments=8, rings=4)

    # Four ears, matching the original artwork.
    builder.add_ear("MainEarL", (-0.43, -2.28, 5.12), 0.36, 1.15, 0.34, math.radians(9.0), SHADOW, BLUE)
    builder.add_ear("MainEarR", (0.43, -2.28, 5.12), 0.36, 1.15, 0.34, math.radians(9.0), SHADOW, BLUE)
    builder.add_ear("OuterEarL", (-0.82, -2.24, 5.02), 0.29, 0.76, 0.29, math.radians(21.0), SHADOW, BLUE)
    builder.add_ear("OuterEarR", (0.82, -2.24, 5.02), 0.29, 0.76, 0.29, math.radians(21.0), SHADOW, BLUE)

    # Heavy brows, narrow eyes, cheek plates, and muzzle color blocks.
    builder.add_plate("BrowL", [(-0.76, -3.11, 4.84), (-0.18, -3.24, 4.79), (-0.29, -3.27, 4.61), (-0.66, -3.18, 4.65)], CHARCOAL)
    builder.add_plate("BrowR", [(0.18, -3.24, 4.79), (0.76, -3.11, 4.84), (0.66, -3.18, 4.65), (0.29, -3.27, 4.61)], CHARCOAL)
    builder.add_plate("EyeL", [(-0.64, -3.175, 4.73), (-0.27, -3.255, 4.68), (-0.31, -3.27, 4.58), (-0.57, -3.21, 4.62)], CYAN)
    builder.add_plate("EyeR", [(0.27, -3.255, 4.68), (0.64, -3.175, 4.73), (0.57, -3.21, 4.62), (0.31, -3.27, 4.58)], CYAN)
    builder.add_plate("CheekAccentL", [(-0.53, -3.20, 4.43), (-0.96, -2.98, 4.52), (-1.23, -2.76, 4.25), (-0.88, -2.99, 4.05), (-0.60, -3.17, 4.13)], CYAN)
    builder.add_plate("CheekAccentR", [(0.53, -3.20, 4.43), (0.96, -2.98, 4.52), (1.23, -2.76, 4.25), (0.88, -2.99, 4.05), (0.60, -3.17, 4.13)], CYAN)
    builder.add_plate("MuzzleAccentL", [(-0.44, -3.40, 4.37), (-0.10, -3.77, 4.32), (-0.15, -3.72, 4.17), (-0.40, -3.37, 4.20)], BLUE)
    builder.add_plate("MuzzleAccentR", [(0.10, -3.77, 4.32), (0.44, -3.40, 4.37), (0.40, -3.37, 4.20), (0.15, -3.72, 4.17)], BLUE)

    # Canine legs with readable elbows, hocks, and integrated paws.
    front_legs = [
        ("FrontLegL", -0.76),
        ("FrontLegR", 0.76),
    ]
    for name, x in front_legs:
        builder.add_loft(
            name,
            [
                (x, -1.20, 3.80),
                (x * 1.05, -1.42, 2.55),
                (x * 1.02, -1.50, 1.48),
                (x, -1.52, 0.52),
            ],
            [0.42, 0.34, 0.27, 0.23],
            [0.46, 0.36, 0.28, 0.22],
            [SLATE, CHARCOAL, CHARCOAL],
            sides=8,
        )
        builder.add_ellipsoid(f"{name}Paw", (x, -1.72, 0.27), (0.43, 0.66, 0.27), SHADOW, segments=8, rings=4)

    hind_legs = [
        ("HindLegL", -0.79),
        ("HindLegR", 0.79),
    ]
    for name, x in hind_legs:
        builder.add_loft(
            name,
            [
                (x, 1.06, 3.48),
                (x * 1.08, 1.48, 2.48),
                (x * 0.98, 1.18, 1.55),
                (x * 0.90, 0.76, 0.55),
            ],
            [0.55, 0.45, 0.32, 0.23],
            [0.58, 0.46, 0.34, 0.22],
            [CHARCOAL, CHARCOAL, SLATE],
            sides=8,
        )
        builder.add_ellipsoid(f"{name}Paw", (x * 0.90, 0.49, 0.27), (0.45, 0.58, 0.27), SHADOW, segments=8, rings=4)

    # Five broad tails in the dramatic raised fan from the original artwork.
    tail_paths = [
        [(0.00, 1.65, 3.35), (0.00, 2.45, 4.00), (0.00, 3.45, 4.78), (0.00, 4.55, 5.27), (0.00, 5.60, 5.48), (0.00, 6.45, 5.90)],
        [(-0.16, 1.64, 3.30), (-0.46, 2.47, 3.78), (-1.05, 3.55, 4.18), (-1.68, 4.63, 4.28), (-2.20, 5.55, 4.38), (-2.68, 6.25, 4.82)],
        [(0.16, 1.64, 3.30), (0.46, 2.47, 3.78), (1.05, 3.55, 4.18), (1.68, 4.63, 4.28), (2.20, 5.55, 4.38), (2.68, 6.25, 4.82)],
        [(-0.30, 1.57, 3.09), (-0.76, 2.36, 3.15), (-1.52, 3.35, 3.17), (-2.35, 4.33, 3.00), (-3.00, 5.20, 2.90), (-3.48, 5.92, 3.18)],
        [(0.30, 1.57, 3.09), (0.76, 2.36, 3.15), (1.52, 3.35, 3.17), (2.35, 4.33, 3.00), (3.00, 5.20, 2.90), (3.48, 5.92, 3.18)],
    ]
    tail_widths = [0.30, 0.47, 0.61, 0.66, 0.43, 0.06]
    tail_heights = [0.27, 0.42, 0.55, 0.59, 0.39, 0.05]
    for index, path in enumerate(tail_paths, start=1):
        builder.add_loft(
            f"Tail{index}",
            path,
            tail_widths,
            tail_heights,
            [CHARCOAL, CHARCOAL, SLATE, SLATE, CYAN],
            sides=9,
            roll=0.0,
        )

    mesh = bpy.data.meshes.new("FiveTailMythling_RenderMesh_V2_Mesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.validate(verbose=True)
    mesh.update()
    obj = bpy.data.objects.new("FiveTailMythling_RenderMesh_V2", mesh)
    collection.objects.link(obj)
    for material in materials:
        obj.data.materials.append(material)
    for polygon, material_index in zip(obj.data.polygons, builder.materials, strict=True):
        polygon.material_index = material_index
        polygon.use_smooth = False

    obj["Stage"] = "ProductionBaseV2"
    obj["SingleRenderMesh"] = True
    obj["TailCount"] = 5
    obj["EarCount"] = 4
    obj["JawBonePlanned"] = True
    obj["Runes"] = "Deferred to texture"
    obj["OriginalReferenceIsAuthoritative"] = True
    obj["ComponentFaceRanges"] = str(builder.components)
    return obj


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
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    return camera


def add_area_light(
    name: str,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    energy: float,
    size: float,
    color: tuple[float, float, float],
    collection: bpy.types.Collection,
) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()


def configure_scene(
    production_collection: bpy.types.Collection,
    reference_collection: bpy.types.Collection,
    render_collection: bpy.types.Collection,
    render_mesh: bpy.types.Object,
) -> dict[str, bpy.types.Object]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.color = (0.025, 0.032, 0.050)

    floor_material = make_material("V2_RenderFloor", (0.075, 0.085, 0.105, 1.0), roughness=1.0)
    bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0.0, 0.8, 0.0))
    floor = bpy.context.object
    floor.name = "V2_RenderFloor"
    floor.data.materials.append(floor_material)
    for source in list(floor.users_collection):
        source.objects.unlink(floor)
    render_collection.objects.link(floor)

    target = (0.0, 0.7, 3.15)
    add_area_light("V2_Key", (-7.0, -8.5, 10.5), target, 1250.0, 5.5, (0.72, 0.82, 1.0), render_collection)
    add_area_light("V2_Fill", (7.0, -3.5, 7.0), target, 850.0, 5.0, (0.28, 0.48, 1.0), render_collection)
    add_area_light("V2_Rim", (0.0, 8.0, 10.5), target, 1500.0, 4.5, (0.02, 0.42, 1.0), render_collection)

    cameras = {
        "ThreeQuarter": add_camera("V2_Camera_ThreeQuarter", (-10.0, -13.0, 7.1), target, 12.6, render_collection),
        "Front": add_camera("V2_Camera_Front", (0.0, -16.0, 3.7), (0.0, 0.65, 3.25), 8.6, render_collection),
        "Left": add_camera("V2_Camera_Left", (-16.0, 0.9, 3.8), (0.0, 1.05, 3.20), 11.8, render_collection),
        "Rear": add_camera("V2_Camera_Rear", (0.0, 16.0, 3.8), (0.0, 1.3, 3.25), 9.0, render_collection),
        "Top": add_camera("V2_Camera_Top", (0.0, 1.2, 17.0), (0.0, 1.2, 0.0), 13.0, render_collection),
    }

    if REFERENCE_PATH.exists():
        background = cameras["ThreeQuarter"].data.background_images.new()
        background.image = bpy.data.images.load(str(REFERENCE_PATH), check_existing=True)
        background.alpha = 0.34
        background.display_depth = "BACK"
        cameras["ThreeQuarter"].data.show_background_images = True

    bpy.context.view_layer.objects.active = render_mesh
    render_mesh.select_set(True)
    scene.camera = cameras["ThreeQuarter"]
    return cameras


def render_views(cameras: dict[str, bpy.types.Object]) -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    for name, camera in cameras.items():
        scene.camera = camera
        scene.render.filepath = str(RENDER_DIR / f"FiveTailMythling_V2_{name}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    # Preserve V1 as a hidden historical reference.
    rough_collection = bpy.data.collections.get("FiveTailMythling_Blockout")
    if rough_collection:
        rough_collection.hide_viewport = True
        rough_collection.hide_render = True
    old_render = bpy.data.collections.get("Render_Setup")
    if old_render:
        old_render.hide_viewport = True
        old_render.hide_render = True

    remove_collection(PRODUCTION_COLLECTION)
    remove_collection(REFERENCE_COLLECTION)
    remove_collection(RENDER_COLLECTION)

    production_collection = bpy.data.collections.new(PRODUCTION_COLLECTION)
    reference_collection = bpy.data.collections.new(REFERENCE_COLLECTION)
    render_collection = bpy.data.collections.new(RENDER_COLLECTION)
    bpy.context.scene.collection.children.link(production_collection)
    bpy.context.scene.collection.children.link(reference_collection)
    bpy.context.scene.collection.children.link(render_collection)

    materials = add_materials()
    render_mesh = build_render_mesh(production_collection, materials)
    cameras = configure_scene(production_collection, reference_collection, render_collection, render_mesh)

    # Store validation information on the single render mesh.
    render_mesh.data.calc_loop_triangles()
    render_mesh["VertexCount"] = len(render_mesh.data.vertices)
    render_mesh["PolygonCount"] = len(render_mesh.data.polygons)
    render_mesh["TriangleCount"] = len(render_mesh.data.loop_triangles)
    render_mesh["MaterialSlotCount"] = len(render_mesh.data.materials)

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    render_views(cameras)
    bpy.context.scene.camera = cameras["ThreeQuarter"]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

    print(f"V2_BLEND={OUTPUT_BLEND}")
    print(f"V2_RENDER_MESH={render_mesh.name}")
    print(f"V2_VERTICES={len(render_mesh.data.vertices)}")
    print(f"V2_POLYGONS={len(render_mesh.data.polygons)}")
    print(f"V2_TRIANGLES={len(render_mesh.data.loop_triangles)}")
    print("V2_TAILS=5")
    print("V2_EARS=4")


if __name__ == "__main__":
    main()
