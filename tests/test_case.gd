extends Node

## The base of every test file (tests/README.md). A test file extends it by path, so it runs without
## the editor first registering a class:
##     extends "res://tests/test_case.gd"
## The runner (run_tests.gd) calls each method whose name starts with test_, in order; a test can
## await. Optional hooks: before_all, after_all, before_each, after_each.[br]
## A test fails when a check fails, when it logs an error it didn't allow ([method allow_error]),
## when it makes no checks, or when it doesn't finish within [member frame_limit] frames.[br]
## Tests check behaviour, not tuning: expected values come from the nodes' exports.

const WORLD_PATH := "res://scenes/world/zurd_world.tscn"

## Frames one test may take before it counts as stuck (120 s at 60 fps).
var frame_limit: int = 7200

## Set by the runner before the test is added to the tree.
var _runner: Object
var _worlds: Array[Node] = []
var _connections: Array[Array] = []


# ==============================================================================
# CHECKS
# ==============================================================================

func check(condition: bool, what: String) -> bool:
	_runner.record_check(condition, what)
	return condition


func check_equal(actual: Variant, expected: Variant, what: String) -> bool:
	var same := _same(actual, expected)
	_runner.record_check(same, what if same else "%s: got %s, expected %s" % [what, actual, expected])
	return same


## Numbers or vectors within [param tolerance] of each other.
func check_near(actual: Variant, expected: Variant, tolerance: float, what: String) -> bool:
	var difference := _difference(actual, expected)
	var near := difference <= tolerance
	_runner.record_check(near, what if near else "%s: got %s, expected %s ± %s" % [what, actual, expected, tolerance])
	return near


## Lets this test log errors containing [param text] without failing (for code that should report
## an error). Call it before the code that logs them.
func allow_error(text: String) -> void:
	_runner.allow_error(text)


## True when this test logged a warning or error containing [param text].
func was_logged(text: String) -> bool:
	return _runner.was_logged(text)


## A path for [param file_name] in the run's temporary folder (in the OS temp folder, removed after
## the run). Tests write files there, never to user://.
func temp_path(file_name: String) -> String:
	return _runner.get_temp_path(file_name)


# ==============================================================================
# WAITING
# ==============================================================================

func wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func wait_physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Game time: with --fixed-fps 60, a simulated second takes 60 frames, however fast they run.
func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits physics frames until [param condition] returns true. Gives up once [param seconds] have
## passed in game time and in real time: with --fixed-fps, frames run faster than real time, and
## work on other threads (loading) runs in real time. Returns whether it came true.
func wait_until(condition: Callable, seconds: float) -> bool:
	var frames := ceili(seconds * Engine.physics_ticks_per_second)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frame := 0
	while not condition.call():
		if frame >= frames and Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().physics_frame
		frame += 1
	return true


# ==============================================================================
# SIGNALS AND INPUT
# ==============================================================================

## Records every emission of [param sig] as an array of its first four arguments (missing ones are
## null). Disconnected after the test.
func watch(sig: Signal) -> Array:
	var calls: Array = []
	listen(sig, func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null) -> void:
		calls.append([a, b, c, d]))
	return calls


## Connects [param callable] to [param sig] until the end of the test.
func listen(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_connections.append([sig, callable])


## Presses [param action] right after a frame starts, so every node's _process sees it as just
## pressed in this frame, and releases it a frame later.
func tap(action: StringName) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)


## Holds [param action] down until [method release] or the end of the test.
func hold(action: StringName) -> void:
	Input.action_press(action)


func release(action: StringName) -> void:
	Input.action_release(action)


# ==============================================================================
# THE GAME WORLD
# ==============================================================================

## Loads the game world for a scene test and returns it; it's freed after the test. Without
## [param with_terrain] the terrain is left out, which saves building it. The hand-placed Zurd is
## always left out: Zurds are temporary, and tests don't pin their behaviour.
func load_world(with_terrain := true) -> Node3D:
	var world := (load(WORLD_PATH) as PackedScene).instantiate() as Node3D
	if not with_terrain:
		_remove_now(world.get_node_or_null(^"Terrain"))
	for zurd in world.find_children("*", "", true, false).filter(_is_zurd):
		_remove_now(zurd)
	get_tree().root.add_child(world)
	_worlds.append(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	return world


func get_ship(world: Node) -> PlayerShip:
	return world.find_child("PlayerShip", true, false) as PlayerShip


func get_mass_manager(world: Node) -> MassManager:
	return world.find_child("MassManager", true, false) as MassManager


## Spawns the object scene at [param path] the way the launcher does, without its randomness: at
## [param size], weightless, moving at [param velocity], added to the world through the EventBus and
## tracked, so the world's MassManager watches it.
func spawn_object(path: String, position: Vector3, size := 1.0, velocity := Vector3.ZERO) -> RigidBody3D:
	var body := (load(path) as PackedScene).instantiate() as RigidBody3D
	ObjectParts.resize_children(body, 1.0, size)
	body.gravity_scale = 0.0
	body.linear_velocity = velocity
	EventBus.spawn_requested.emit(body)
	body.global_position = position
	ObjectTracker.register_object(body)
	return body


## Spawns the object scene at [param path] (see [method spawn_object]) next to [param other], an
## unrotated body: [param gap] apart from it along [param direction] (one axis), centred on it
## along the other two.
func spawn_beside(path: String, other: CollisionObject3D, direction: Vector3, gap := 0.1, size := 1.0) -> RigidBody3D:
	var box := get_body_bounds(other)
	box.position += other.global_position
	return spawn_beside_box(path, box, direction, gap, size)


## Like [method spawn_beside], next to [param box] (in global space).
func spawn_beside_box(path: String, box: AABB, direction: Vector3, gap := 0.1, size := 1.0) -> RigidBody3D:
	var body := spawn_object(path, box.get_center(), size)
	var own := get_body_bounds(body)
	var axis := direction.abs().max_axis_index()
	var center := box.get_center()
	if direction[axis] > 0.0:
		center[axis] = box.end[axis] + gap + own.size[axis] * 0.5
	else:
		center[axis] = box.position[axis] - gap - own.size[axis] * 0.5
	body.global_position = center - own.get_center()
	return body


## The box around [param body]'s collision shapes, in the body's own space.
func get_body_bounds(body: CollisionObject3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		var box := shape.transform * MassPiece.get_shape_bounds(shape.shape)
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


# ==============================================================================
# CALLED BY THE RUNNER
# ==============================================================================

## Runs after every test: disconnects watched signals, releases every input action and frees the
## loaded worlds.
func _cleanup() -> void:
	for connection in _connections:
		var sig: Signal = connection[0]
		if sig.get_object() != null and sig.is_connected(connection[1]):
			sig.disconnect(connection[1])
	_connections.clear()
	for action in InputMap.get_actions():
		Input.action_release(action)
	for world in _worlds:
		if is_instance_valid(world):
			world.queue_free()
	_worlds.clear()
	await get_tree().process_frame
	await get_tree().process_frame


func _same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return a == b
	if typeof(a) != typeof(b):
		# StringName and String compare equal by text.
		if typeof(a) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(b) in [TYPE_STRING, TYPE_STRING_NAME]:
			return String(a) == String(b)
		return false
	return a == b


func _difference(a: Variant, b: Variant) -> float:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return absf(float(a) - float(b))
	if typeof(a) == typeof(b) and typeof(a) in [TYPE_VECTOR2, TYPE_VECTOR3]:
		return a.distance_to(b)
	return INF


func _is_zurd(node: Node) -> bool:
	var script := node.get_script() as Script
	return script != null and script.get_global_name() == &"Zurd"


func _remove_now(node: Node) -> void:
	if node == null:
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.free()
