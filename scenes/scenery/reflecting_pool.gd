@tool
class_name ReflectingPool
extends Node3D

## A reflecting pool: mirror water (see PlanarReflection) in a checkerboard basin with an outline
## along its edges. Builds the outline from the basin's mesh when it loads (in the editor too), and
## in the game gives the basin a collider that follows its shape exactly (a trimesh, so the
## hollow stays hollow; a convex hull would fill it up to the rim). Both are rebuilt from the mesh,
## so a re-export from Blender needs no changes here.

const OUTLINE_SHADER := preload("res://assets/shaders/edge_outline.gdshader")
const Edges := preload("res://scripts/utils/edge_lines.gd")

## The basin's mesh: gets the outline and the collider.
@export var basin_mesh: MeshInstance3D
## Edges where the faces meet at a sharper angle than this (in degrees) get the outline. Open
## edges always do.
@export_range(1.0, 90.0, 1.0) var outline_angle: float = 20.0
@export var outline_color: Color = Color(0.55, 0.18, 0.85):
	set(value):
		outline_color = value
		if _outline_material:
			_outline_material.set_shader_parameter("outline_color", value)
## Outline width in pixels.
@export_range(0.5, 20.0, 0.5) var outline_width: float = 3.0:
	set(value):
		outline_width = value
		if _outline_material:
			_outline_material.set_shader_parameter("width", value)

var _outline_material: ShaderMaterial


func _ready() -> void:
	if basin_mesh == null or basin_mesh.mesh == null:
		push_warning("ReflectingPool: no basin_mesh set on " + str(get_path()))
		return
	_add_outline()
	if not Engine.is_editor_hint():
		_add_collider()


func _add_outline() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("width", outline_width)

	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = Edges.build_outline_mesh(Edges.find_feature_edges(basin_mesh.mesh, outline_angle))
	outline.material_override = _outline_material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The lines are widened on screen, past the edges' own box.
	outline.extra_cull_margin = 1.0
	outline.layers = basin_mesh.layers
	# Not owned: built on load, never saved into the scene.
	basin_mesh.add_child(outline)


func _add_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "BasinBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = basin_mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	basin_mesh.add_child(body)
