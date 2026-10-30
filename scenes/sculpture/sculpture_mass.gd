class_name SculptureMass
extends RigidBody3D

## A group of fused objects that moves as one body (Sculpture-Mass Design Doc §5). Each fused
## object is a [MassPiece] child (its visuals) plus its [CollisionShape3D]s, which are direct
## children of the mass. The [MassManager] creates masses and does all fusing, merging and removal.
## The mass keeps its pieces, its cloud progress and its look, and runs its own cloud transformation.

## Template for the blend material. Each mass works on its own copy, so one value drives the look
## of all its pieces.
@export var blend_material: ShaderMaterial = preload("res://assets/materials/sculpture_mass.tres")

## Set by the [MassManager] that created this mass.
var manager: MassManager
var pieces: Array[MassPiece] = []
## Object count divided by the cloud threshold, from 0 to 1.
var cloud_progress: float = 0.0
## Permanent once set (Design Doc §4.7).
var is_cloud: bool = false

var _material: ShaderMaterial
var _flash_tween: Tween
var _debug_label: Label3D
var _cloud_height: float = 0.0
var _drift_heading: float = 0.0


func _ready() -> void:
	if blend_material:
		_material = blend_material.duplicate() as ShaderMaterial
	else:
		push_warning("SculptureMass: No blend_material assigned; fused objects lose their look.")
		_material = ShaderMaterial.new()

	if manager and manager.debug_labels:
		_debug_label = Label3D.new()
		_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_label.no_depth_test = true
		_debug_label.fixed_size = true
		_debug_label.pixel_size = 0.001
		_debug_label.font_size = 48
		_debug_label.outline_size = 12
		add_child(_debug_label)

	# Only clouds move themselves.
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	# Cosmetic cloud drift (Design Doc §4.7): rise into the atmosphere band, then wander slowly.
	var pos := global_position
	pos.y = move_toward(pos.y, _cloud_height, manager.rise_speed * delta)
	_drift_heading += randf_range(-1.0, 1.0) * delta
	pos += Vector3(cos(_drift_heading), 0.0, sin(_drift_heading)) * manager.drift_speed * delta
	global_position = pos


## Asks the manager to eat [param piece]. A Zurd calls this when it finishes eating. Nothing
## happens if this mass is a cloud.
func request_eat(piece: MassPiece, actor: Node3D) -> void:
	if manager and piece.mass == self:
		manager.request_eat(piece, actor)


## Asks the manager to break off the piece that owns [param shape]. The ship calls this when it
## hits the mass.
func request_break_off(shape: Object) -> void:
	var piece := get_piece_for_shape(shape)
	if manager and piece:
		manager.request_break_off(piece)


## Moves [param body]'s shapes and visuals into this mass as a new piece, keeping their global
## transforms. The caller frees the empty body.
func add_piece(body: RigidBody3D) -> MassPiece:
	var piece := MassPiece.new()
	piece.name = body.name
	piece.mass = self
	piece.capture_body(body)
	add_child(piece, true)
	piece.global_transform = body.global_transform

	for child in body.get_children():
		if child is CollisionShape3D:
			child.reparent(self)
			piece.add_shape(child as CollisionShape3D)
		elif child is Node3D:
			child.reparent(piece)

	pieces.append(piece)
	_apply_look(piece, true)
	return piece


## Takes [param piece] over from another mass when two masses merge.
func adopt_piece(piece: MassPiece) -> void:
	if piece.mass:
		piece.mass.pieces.erase(piece)
	piece.reparent(self)
	for shape in piece.shapes:
		shape.reparent(self)
	piece.mass = self
	pieces.append(piece)
	_apply_look(piece, false)


## Removes [param piece] and its shapes and frees them. They leave the body immediately, because
## a loose copy of the object may take their place before the next physics step.
func remove_piece(piece: MassPiece) -> void:
	piece.unlink_all()
	pieces.erase(piece)
	for shape in piece.shapes:
		if shape.get_parent() == self:
			remove_child(shape)
		shape.queue_free()
	piece.shapes.clear()
	if piece.get_parent() == self:
		remove_child(piece)
	piece.mass = null
	piece.queue_free()


func get_piece_for_shape(shape: Variant) -> MassPiece:
	if not is_instance_valid(shape) or not shape.has_meta(MassPiece.SHAPE_META):
		return null
	var piece: Variant = shape.get_meta(MassPiece.SHAPE_META)
	if is_instance_valid(piece) and piece is MassPiece and piece.mass == self:
		return piece
	return null


## The piece that owns the shape at [param shape_index], as reported by contacts and queries.
func get_piece_for_shape_index(shape_index: int) -> MassPiece:
	if shape_index < 0 or shape_index >= PhysicsServer3D.body_get_shape_count(get_rid()):
		return null
	return get_piece_for_shape(shape_owner_get_owner(shape_find_owner(shape_index)))


func get_closest_piece(point: Vector3) -> MassPiece:
	var closest: MassPiece = null
	var best_distance := INF
	for piece in pieces:
		var distance := point.distance_squared_to(piece.get_center())
		if distance < best_distance:
			best_distance = distance
			closest = piece
	return closest


## Groups the pieces into connected chunks using their neighbor links, largest chunk first
## (Design Doc §4.8).
func get_chunks() -> Array[Array]:
	var chunks: Array[Array] = []
	var seen: Dictionary[MassPiece, bool] = {}
	for start in pieces:
		if seen.has(start):
			continue
		var chunk: Array[MassPiece] = []
		var stack: Array[MassPiece] = [start]
		seen[start] = true
		while not stack.is_empty():
			var piece: MassPiece = stack.pop_back()
			chunk.append(piece)
			for neighbor in piece.neighbors:
				if not seen.has(neighbor):
					seen[neighbor] = true
					stack.append(neighbor)
		chunks.append(chunk)
	chunks.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return chunks


func get_global_center_of_mass() -> Vector3:
	return global_transform * center_of_mass


## Velocity of the mass at [param point], including its spin.
func get_point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - get_global_center_of_mass())


## Updates the physics mass, centre of mass, cloud progress and look after pieces were added or
## removed. Turns the mass into a cloud when it reaches the threshold.
func refresh() -> void:
	if pieces.is_empty():
		return
	var threshold := manager.cloud_threshold_count
	mass = pieces.size() * manager.object_mass
	center_of_mass = _get_local_center()
	_set_cloud_progress(1.0 if is_cloud else minf(float(pieces.size()) / threshold, 1.0))
	if not is_cloud and pieces.size() >= threshold:
		_become_cloud()
	_update_debug_label()


## Blinks the whole mass in [param color] (placeholder effect for eating and merging).
func flash(color: Color, blinks: int = 2, duration: float = 0.5) -> void:
	_material.set_shader_parameter(&"flash_color", color)
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	var step := duration / (blinks * 2.0)
	for _blink in blinks:
		_flash_tween.tween_method(_set_flash_amount, 0.0, 1.0, step)
		_flash_tween.tween_method(_set_flash_amount, 1.0, 0.0, step)


## Turns the mass into a permanent cloud (Design Doc §4.7): it stops colliding, stops being a Zurd
## target, switches to the cloud look and rises into the atmosphere band.
func _become_cloud() -> void:
	is_cloud = true
	collision_layer = 0
	collision_mask = 0
	contact_monitor = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	for piece in pieces:
		ObjectTracker.unregister_object(piece)

	_set_cloud_progress(1.0)
	_cloud_height = randf_range(manager.atmosphere_y_range.x, manager.atmosphere_y_range.y)
	_drift_heading = randf() * TAU
	set_physics_process(true)

	var tween := create_tween()
	tween.tween_method(_set_cloud_form, 0.0, 1.0, maxf(manager.cloud_transition_time, 0.01))
	EventBus.cloud_formed.emit(self)


func _set_cloud_progress(progress: float) -> void:
	if is_equal_approx(progress, cloud_progress):
		return
	cloud_progress = progress
	_material.set_shader_parameter(&"cloud_amount", progress)
	EventBus.cloud_progress_changed.emit(self, progress)


func _set_cloud_form(amount: float) -> void:
	_material.set_shader_parameter(&"cloud_form", amount)


func _set_flash_amount(amount: float) -> void:
	_material.set_shader_parameter(&"flash_amount", amount)


## Puts the mass's blend material on the piece. When [param copy_base_look] is set, first copies
## the object's original colour and surface onto the mesh so the blend starts from its own look.
func _apply_look(piece: MassPiece, copy_base_look: bool) -> void:
	for mesh_instance in piece.get_meshes():
		var original: BaseMaterial3D = null
		if copy_base_look and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
			original = mesh_instance.get_active_material(0) as BaseMaterial3D

		mesh_instance.material_override = _material
		if original:
			mesh_instance.set_instance_shader_parameter(&"base_tint", original.albedo_color)
			mesh_instance.set_instance_shader_parameter(&"base_roughness", original.roughness)
			mesh_instance.set_instance_shader_parameter(&"base_metallic", original.metallic)


## Average of the piece centres in local space. Every object weighs the same (Design Doc §5), so
## this is the centre of mass whatever the objects' sizes.
func _get_local_center() -> Vector3:
	var sum := Vector3.ZERO
	for piece in pieces:
		sum += to_local(piece.get_center())
	return sum / pieces.size()


func _update_debug_label() -> void:
	if not _debug_label:
		return
	_debug_label.position = center_of_mass
	if is_cloud:
		_debug_label.text = "cloud (%d)" % pieces.size()
	else:
		_debug_label.text = "%d/%d" % [pieces.size(), manager.cloud_threshold_count]
