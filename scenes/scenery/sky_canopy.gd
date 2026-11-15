@tool
class_name SkyCanopy
extends Node3D

## The canopy high above the mega trees: backdrop only (no collision, no gameplay). It is a few
## stacked shells drawn with sky_canopy.gdshader, which gives them an organic outline that slowly
## changes shape. The canopy covers only the trees in [member tree_group], as one sheet where they
## stand close and in patches where they stand apart.
## This node's height is the lowest shell's height (at its rim); where it sits across (X and Z)
## doesn't matter, the shells go over the trees. Built when it loads, in the editor too; after
## moving or adding trees in the editor, press Refresh. The shells aren't saved with the scene.

## The shells' shape and look (shared, so tuning it in the inspector shows at once).
@export var canopy_material: ShaderMaterial:
	set(value):
		canopy_material = value
		_rebuild_if_ready()
## Group of the trees the canopy covers (mega_tree.tscn is in it).
@export var tree_group: StringName = &"mega_trees":
	set(value):
		tree_group = value
		_rebuild_if_ready()
## How far (metres) the canopy reaches around each tree. Trees closer than about twice this share
## one canopy.
@export_range(10.0, 2000.0, 10.0, "or_greater") var tree_radius: float = 550.0:
	set(value):
		tree_radius = value
		_rebuild_if_ready()
@export_range(1, 8) var layer_count: int = 4:
	set(value):
		layer_count = value
		_rebuild_if_ready()
## Metres between shells.
@export_range(0.0, 500.0, 1.0, "or_greater") var layer_spacing: float = 40.0:
	set(value):
		layer_spacing = value
		_rebuild_if_ready()
## How much higher (metres) the canopy's middle is than its rim, so it isn't a flat sheet.
@export_range(0.0, 1000.0, 1.0, "or_greater") var dome_height: float = 150.0:
	set(value):
		dome_height = value
		_rebuild_if_ready()
## Grid cells along each side of a shell. The canopy's extent is stored per vertex, so more cells
## follow the trees more closely.
@export_range(8, 256) var resolution: int = 64:
	set(value):
		resolution = value
		_rebuild_if_ready()
@export_tool_button("Refresh", "Reload") var refresh_button := rebuild

var _shells: Array[MeshInstance3D] = []
# The shells' middle (world X, Z): over the middle of the trees.
var _middle := Vector2.ZERO


func _ready() -> void:
	set_notify_transform(true)
	rebuild.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_place_shells()


## How much canopy belongs at [param point] (world X, Z) for trees at [param trees]: 1 near a
## tree or between close trees, falling to 0 about 1.5 radii from a lone tree.
static func canopy_amount(point: Vector2, trees: PackedVector2Array, radius: float) -> float:
	var field := 0.0
	for tree in trees:
		var d := point.distance_to(tree) / radius
		field += exp(-d * d)
	return smoothstep(0.1, 0.6, field)


## Rebuilds the shells from the trees where they stand now.
func rebuild() -> void:
	for shell in _shells:
		if is_instance_valid(shell):
			remove_child(shell)
			shell.free()
	_shells.clear()
	if canopy_material == null or not is_inside_tree():
		return
	var trees := PackedVector2Array()
	for node in get_tree().get_nodes_in_group(tree_group):
		if node is Node3D:
			trees.append(Vector2(node.global_position.x, node.global_position.z))
	if trees.is_empty():
		if not Engine.is_editor_hint():
			push_warning("SkyCanopy: no trees in group '%s', so no canopy." % tree_group)
		return
	var mesh := _build_mesh(trees)
	for i in layer_count:
		var shell := MeshInstance3D.new()
		shell.name = "Shell%d" % i
		shell.mesh = mesh
		shell.material_override = canopy_material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.top_level = true
		shell.set_instance_shader_parameter("layer", float(i))
		add_child(shell, false, Node.INTERNAL_MODE_BACK)
		_shells.append(shell)
	_place_shells()


func _rebuild_if_ready() -> void:
	if is_node_ready():
		rebuild()


## A grid over the trees' area with a margin, centred on the trees (sets _middle). Each vertex
## holds its share of canopy in COLOR.r; the middle is raised dome_height above the rim.
func _build_mesh(trees: PackedVector2Array) -> ArrayMesh:
	var low := trees[0]
	var high := trees[0]
	for tree in trees:
		low = low.min(tree)
		high = high.max(tree)
	var margin := tree_radius * 1.6
	low -= Vector2.ONE * margin
	high += Vector2.ONE * margin
	_middle = (low + high) / 2.0
	var half := (high - low) / 2.0

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in resolution + 1:
		for x in resolution + 1:
			var t := Vector2(x, z) / float(resolution) * 2.0 - Vector2.ONE
			var local := t * half
			var rim := clampf(t.length_squared(), 0.0, 1.0)
			vertices.append(Vector3(local.x, dome_height * (1.0 - rim), local.y))
			var amount := canopy_amount(_middle + local, trees, tree_radius)
			colors.append(Color(amount, amount, amount))
			normals.append(Vector3.UP)
	var row := resolution + 1
	for z in resolution:
		for x in resolution:
			var a := z * row + x
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _place_shells() -> void:
	for i in _shells.size():
		_shells[i].global_transform = Transform3D(Basis.IDENTITY,
				Vector3(_middle.x, global_position.y + i * layer_spacing, _middle.y))
