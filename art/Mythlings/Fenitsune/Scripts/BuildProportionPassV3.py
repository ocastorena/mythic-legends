"""Create Fenitsune V3 from the approved single-object production base.

Executed through Blender MCP. This is a non-destructive proportion pass:
the V1 and V2 files remain available, while the active result is saved under
the creature's production name, Fenitsune.
"""

from __future__ import annotations

import ast
import importlib.util
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


SCRIPT_DIR = Path(__file__).resolve().parent
FENITSUNE_DIR = SCRIPT_DIR.parent
LEGACY_BUILDER = FENITSUNE_DIR.parent / "FiveTailMythling" / "Scripts" / "BuildProductionBaseV2.py"
REFERENCE_PATH = Path("/Users/omar/Downloads/Gemini_Generated_Image_3utdxt3utdxt3utd.png")
OUTPUT_BLEND = FENITSUNE_DIR / "Fenitsune_ProportionPassV3.blend"
RENDER_DIR = FENITSUNE_DIR / "Renders" / "ProportionPassV3"

PRODUCTION_COLLECTION = "Fenitsune_ProductionBaseV3"
REFERENCE_COLLECTION = "Fenitsune_Reference"
RENDER_COLLECTION = "Fenitsune_RenderSetupV3"


def load_builder_module():
    spec = importlib.util.spec_from_file_location("fenitsune_v2_builder", LEGACY_BUILDER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def component_vertex_indices(obj: bpy.types.Object, component_name: str) -> set[int]:
    components = ast.literal_eval(obj["ComponentFaceRanges"])
    face_start, face_end = components[component_name]
    indices: set[int] = set()
    for polygon in obj.data.polygons[face_start:face_end]:
        indices.update(polygon.vertices)
    return indices


def transform_component(
    obj: bpy.types.Object,
    component_name: str,
    *,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    translation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    center: tuple[float, float, float] | None = None,
) -> None:
    indices = component_vertex_indices(obj, component_name)
    if not indices:
        return
    if center is None:
        center_v = sum((obj.data.vertices[index].co for index in indices), Vector()) / len(indices)
    else:
        center_v = Vector(center)
    scale_v = Vector(scale)
    translation_v = Vector(translation)
    for index in indices:
        vertex = obj.data.vertices[index]
        vertex.co = center_v + (vertex.co - center_v) * scale_v + translation_v


def bend_tail(
    obj: bpy.types.Object,
    component_name: str,
    *,
    lateral_sign: float,
    lateral_amount: float,
    vertical_amount: float,
    wave_phase: float,
) -> None:
    indices = component_vertex_indices(obj, component_name)
    ys = [obj.data.vertices[index].co.y for index in indices]
    minimum_y = min(ys)
    span_y = max(ys) - minimum_y
    for index in indices:
        vertex = obj.data.vertices[index]
        t = (vertex.co.y - minimum_y) / span_y if span_y else 0.0
        envelope = math.sin(math.pi * t)
        vertex.co.x += lateral_sign * lateral_amount * envelope
        vertex.co.z += vertical_amount * math.sin(math.tau * t + wave_phase) * envelope


def append_cheek_silhouettes(obj: bpy.types.Object, shadow_material_index: int) -> None:
    left = [
        (-0.57, -3.145, 4.52),
        (-1.05, -2.94, 4.61),
        (-1.35, -2.66, 4.24),
        (-0.92, -2.98, 3.96),
        (-0.57, -3.14, 4.07),
    ]
    right = [(-x, y, z) for x, y, z in reversed(left)]

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for points in (left, right):
        vertices = [bm.verts.new(point) for point in points]
        face = bm.faces.new(vertices)
        face.material_index = shadow_material_index
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def configure_reference_camera(camera: bpy.types.Object) -> None:
    camera.data.type = "PERSP"
    camera.data.lens = 62.0
    camera.data.sensor_width = 36.0
    target = Vector((0.0, 0.75, 3.25))
    close_location = Vector((-9.3, -13.4, 6.9))
    camera.location = target + (close_location - target) * 1.28
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()

    camera.data.background_images.clear()
    if REFERENCE_PATH.exists():
        background = camera.data.background_images.new()
        background.image = bpy.data.images.load(str(REFERENCE_PATH), check_existing=True)
        background.alpha = 0.38
        background.display_depth = "BACK"
        camera.data.show_background_images = True


def neutralize_palette(materials: list[bpy.types.Material]) -> None:
    palette = {
        "V2_Charcoal": (0.035, 0.045, 0.070, 1.0),
        "V2_Slate": (0.090, 0.100, 0.125, 1.0),
        "V2_MidGray": (0.205, 0.220, 0.255, 1.0),
        "V2_DeepShadow": (0.008, 0.011, 0.022, 1.0),
    }
    for material in materials:
        material.name = material.name.replace("V2_", "Fenitsune_")
        source_name = material.name.replace("Fenitsune_", "V2_")
        if source_name not in palette:
            continue
        color = palette[source_name]
        material.diffuse_color = color
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = color


def apply_proportion_pass(render_mesh: bpy.types.Object) -> None:
    # Larger but less domed head.
    transform_component(render_mesh, "Cranium", scale=(1.09, 1.01, 0.94), translation=(0.0, -0.02, 0.02))

    # Shorter, wider, deeper muzzle with a retained jaw seam.
    muzzle_anchor = (0.0, -2.84, 4.42)
    transform_component(render_mesh, "UpperMuzzle", scale=(1.10, 0.84, 1.12), center=muzzle_anchor)
    transform_component(render_mesh, "Jaw", scale=(1.08, 0.85, 1.13), center=(0.0, -2.88, 4.16))
    transform_component(render_mesh, "Nose", scale=(1.04, 0.90, 1.05), translation=(0.0, 0.10, 0.0))

    # Stronger shoulders and neck, with a slightly shorter torso.
    transform_component(render_mesh, "Chest", scale=(1.09, 1.02, 1.10), translation=(0.0, -0.02, 0.04))
    transform_component(render_mesh, "Neck", scale=(1.10, 1.04, 1.10), translation=(0.0, -0.02, 0.05))
    transform_component(render_mesh, "ChestMane", scale=(1.12, 1.0, 1.08), translation=(0.0, -0.01, 0.02))
    transform_component(render_mesh, "Torso", scale=(0.98, 0.92, 0.96), translation=(0.0, -0.03, 0.02))
    transform_component(render_mesh, "Haunches", scale=(1.0, 0.92, 0.96), translation=(0.0, -0.08, 0.0))

    # Integrate facial features with the revised skull.
    facial_components = (
        "BrowL",
        "BrowR",
        "EyeL",
        "EyeR",
        "CheekAccentL",
        "CheekAccentR",
        "MuzzleAccentL",
        "MuzzleAccentR",
    )
    for name in facial_components:
        transform_component(render_mesh, name, scale=(1.05, 0.98, 1.04), translation=(0.0, -0.02, 0.0))
    transform_component(render_mesh, "CheekAccentL", scale=(0.82, 1.0, 0.86))
    transform_component(render_mesh, "CheekAccentR", scale=(0.82, 1.0, 0.86))

    # Broader, outward-leaning four-ear silhouette.
    for name, sign in (
        ("MainEarL", -1.0),
        ("MainEarR", 1.0),
        ("OuterEarL", -1.0),
        ("OuterEarR", 1.0),
    ):
        indices = component_vertex_indices(render_mesh, name)
        minimum_z = min(render_mesh.data.vertices[index].co.z for index in indices)
        maximum_z = max(render_mesh.data.vertices[index].co.z for index in indices)
        span_z = maximum_z - minimum_z
        for index in indices:
            vertex = render_mesh.data.vertices[index]
            t = (vertex.co.z - minimum_z) / span_z if span_z else 0.0
            vertex.co.x += sign * 0.15 * t

    # Thicker legs and larger paws without changing stance height.
    for name in ("FrontLegL", "FrontLegR", "HindLegL", "HindLegR"):
        transform_component(render_mesh, name, scale=(1.20, 1.16, 1.0))
    for name in ("FrontLegLPaw", "FrontLegRPaw", "HindLegLPaw", "HindLegRPaw"):
        transform_component(render_mesh, name, scale=(1.18, 1.16, 1.06))

    # Keep the full fan volume while adding individual organic bends.
    bend_tail(render_mesh, "Tail1", lateral_sign=1.0, lateral_amount=0.18, vertical_amount=0.11, wave_phase=0.3)
    bend_tail(render_mesh, "Tail2", lateral_sign=-1.0, lateral_amount=0.18, vertical_amount=0.15, wave_phase=0.8)
    bend_tail(render_mesh, "Tail3", lateral_sign=1.0, lateral_amount=0.18, vertical_amount=0.15, wave_phase=-0.7)
    bend_tail(render_mesh, "Tail4", lateral_sign=-1.0, lateral_amount=0.24, vertical_amount=0.18, wave_phase=1.2)
    bend_tail(render_mesh, "Tail5", lateral_sign=1.0, lateral_amount=0.24, vertical_amount=0.18, wave_phase=-1.1)

    # Dark backing turns the cyan cheek polygons into inset layered fur.
    append_cheek_silhouettes(render_mesh, shadow_material_index=3)
    render_mesh.data.update()


def main() -> None:
    builder = load_builder_module()
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    # Preserve every previous pass as hidden reference data.
    for collection_name in (
        "FiveTailMythling_Blockout",
        "FiveTailMythling_ProductionBaseV2",
        "Render_Setup",
        "FiveTailMythling_RenderSetupV2",
    ):
        collection = bpy.data.collections.get(collection_name)
        if collection:
            collection.hide_viewport = True
            collection.hide_render = True

    builder.remove_collection(PRODUCTION_COLLECTION)
    builder.remove_collection(REFERENCE_COLLECTION)
    builder.remove_collection(RENDER_COLLECTION)

    production_collection = bpy.data.collections.new(PRODUCTION_COLLECTION)
    reference_collection = bpy.data.collections.new(REFERENCE_COLLECTION)
    render_collection = bpy.data.collections.new(RENDER_COLLECTION)
    bpy.context.scene.collection.children.link(production_collection)
    bpy.context.scene.collection.children.link(reference_collection)
    bpy.context.scene.collection.children.link(render_collection)

    materials = builder.add_materials()
    neutralize_palette(materials)
    render_mesh = builder.build_render_mesh(production_collection, materials)
    render_mesh.name = "Fenitsune_RenderMesh_V3"
    render_mesh.data.name = "Fenitsune_RenderMesh_V3_Mesh"
    apply_proportion_pass(render_mesh)

    builder.RENDER_DIR = RENDER_DIR
    cameras = builder.configure_scene(
        production_collection,
        reference_collection,
        render_collection,
        render_mesh,
    )
    cameras = {name: camera for name, camera in cameras.items()}
    for name, camera in cameras.items():
        camera.name = f"Fenitsune_Camera_{name}"
    configure_reference_camera(cameras["ThreeQuarter"])
    cameras["Front"].data.ortho_scale = 10.0
    cameras["Left"].data.ortho_scale = 13.0
    cameras["Rear"].data.ortho_scale = 10.5
    cameras["Top"].data.ortho_scale = 14.5

    render_mesh["DisplayName"] = "Fenitsune"
    render_mesh["Stage"] = "ProportionPassV3"
    render_mesh["SingleRenderMesh"] = True
    render_mesh["PreserveFullTailFanVolume"] = True
    render_mesh["OriginalReferenceIsAuthoritative"] = True
    render_mesh.data.calc_loop_triangles()
    render_mesh["VertexCount"] = len(render_mesh.data.vertices)
    render_mesh["PolygonCount"] = len(render_mesh.data.polygons)
    render_mesh["TriangleCount"] = len(render_mesh.data.loop_triangles)

    bpy.context.scene.camera = cameras["ThreeQuarter"]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

    original_render_dir = builder.RENDER_DIR
    for name, camera in cameras.items():
        bpy.context.scene.camera = camera
        bpy.context.scene.render.filepath = str(RENDER_DIR / f"Fenitsune_V3_{name}.png")
        bpy.ops.render.render(write_still=True)
    builder.RENDER_DIR = original_render_dir

    bpy.context.scene.camera = cameras["ThreeQuarter"]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

    print(f"FENITSUNE_BLEND={OUTPUT_BLEND}")
    print(f"FENITSUNE_RENDER_MESH={render_mesh.name}")
    print(f"FENITSUNE_VERTICES={len(render_mesh.data.vertices)}")
    print(f"FENITSUNE_POLYGONS={len(render_mesh.data.polygons)}")
    print(f"FENITSUNE_TRIANGLES={len(render_mesh.data.loop_triangles)}")
    print("FENITSUNE_TAILS=5")
    print("FENITSUNE_EARS=4")


if __name__ == "__main__":
    main()
