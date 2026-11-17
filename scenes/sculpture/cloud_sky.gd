class_name CloudSky
extends Node

## Everything a cloud does once it has formed (Cloud-Formation Design Doc §4). A new cloud holds
## still for [member rise_delay], then rises up and outward to its place in the cloud zone over
## [member rise_time], growing to [member scale_multiplier] times its size. There it circles the
## play area with every other cloud in a slow gyre, inner rings a little faster, so clouds drift
## into one another and apart; a gentle push ([member push_speed]) makes sure they don't stay
## overlapped. Each cloud bobs, tumbles slowly and breathes.
## It also dresses each new cloud: puffs on its objects ([CloudPuffs]) and small puffs that come and
## go around it ([CloudWisps]), and subtle lines along its objects' ridges, so their shapes read
## from far away. Every frame it also tells each cloud's material where the cloud is, for its
## darker base (sculpture_cloud.gdshader). Visual only: clouds don't collide.
## [method step] moves the clouds. It works on bare [SkyCloud] states too, which is how the tests
## drive it.

const Puffs := preload("res://scenes/sculpture/cloud_puffs.gd")
const Wisps := preload("res://scenes/sculpture/cloud_wisps.gd")
const Edges := preload("res://scripts/utils/edge_lines.gd")

## Meta on an object's mesh holding its ridge line mesh, so each model's ridges are found once.
const RIDGES_META := &"cloud_ridges_mesh"
## Meta on an object's mesh holding its surface table for placing puffs (CloudPuffs).
const PUFF_TABLE_META := &"cloud_puff_table"

## On the way up, the climb lags the glide outward by this power, so the path is an arc: out
## first, then up.
const CLIMB_LAG := 1.6
## Slowest push, as a share of [member push_speed], so even clouds that barely touch part.
const MIN_PUSH := 0.25
## The tumble's axis turns once every this many tumbles, so the tumble wanders in any direction.
const AXIS_TURN_TUMBLES := 3.0

@export_group("Zone")
## Heights (world) where the clouds' middles circle. The same in every world.
@export var zone_heights: Vector2 = Vector2(1000.0, 1550.0)
## The point (world X, Z) the clouds circle.
@export var gyre_center: Vector2 = Vector2.ZERO
## How far from the centre clouds circle, in metres.
@export var gyre_radius_range: Vector2 = Vector2(1200.0, 3500.0)
## Seconds for one lap at the middle of [member gyre_radius_range].
@export var gyre_lap_time: float = 900.0
## How much faster inner rings turn than outer ones, so clouds pass one another: 0 turns the whole
## sky like a wheel, 1 moves every ring at the same speed in metres per second.
@export_range(0.0, 2.0, 0.05) var gyre_shear: float = 1.0

@export_group("Rise")
## How long a new cloud holds still after forming, so guests see the change. 0 rises at once.
@export var rise_delay: float = 0.8
## Seconds from leaving to arriving in the zone. It starts slowly and arrives gently.
@export var rise_time: float = 40.0
## A cloud's final size divided by its sculpture's size.
@export var scale_multiplier: float = 6.0

@export_group("Spacing")
## Fastest (m/s) each of two overlapping clouds is pushed apart. Gentle, so clouds can drift into
## one another before they part.
@export var push_speed: float = 4.0

@export_group("Small Life")
## How far (m) a cloud bobs up and down.
@export var bob_height: float = 10.0
## Seconds for one bob.
@export var bob_period: float = 30.0
## Seconds for one full turn of the slow tumble.
@export var tumble_period: float = 240.0
## How much a cloud swells in and out (0.03 is 3%).
@export var breath: float = 0.03
## Seconds for one breath.
@export var breath_period: float = 15.0

@export_group("Details")
## Material of the puffs and wisps (cloud_puff.gdshader).
@export var puff_material: Material = preload("res://assets/materials/cloud_puff.tres")
## Puffs scattered over each object of a cloud.
@export_range(0, 100) var puffs_per_object: int = 8
## A puff's radius (min, max), as a share of its object's longest side.
@export var puff_size: Vector2 = Vector2(0.08, 0.16)
## How many small puffs come and go around each cloud (min, max; picked per cloud).
@export var wisp_count: Vector2i = Vector2i(3, 8)
## Material of the ridge lines (cloud_ridges.gdshader); none draws no ridges.
@export var ridge_material: Material = preload("res://assets/materials/cloud_ridges.tres")
## Edges where an object's faces meet at a sharper angle than this (degrees) get a ridge line, as
## do open edges. Read when a model's ridges are first found.
@export_range(1.0, 90.0, 1.0) var ridge_angle: float = 35.0

## Every cloud in the sky.
var clouds: Array[SkyCloud] = []

var _rng := RandomNumberGenerator.new()
var _sphere: SphereMesh
## Models whose ridges and puff tables are being worked out: { Mesh: ModelJob }.
var _model_jobs: Dictionary = {}
## Models waiting to have their triangles read, one per frame: reading them back from the GPU
## takes several milliseconds per model.
var _read_queue: Array[Mesh] = []


## The once-per-model work a cloud's details need: its ridge lines and its puff surface table.
## The triangles are read on the main thread (one model per frame); the rest runs on a worker
## thread, so a cloud of new models doesn't stall the game as it forms. Until it's done, the
## cloud's ridge and puff nodes wait (they appear during the cloud's white burst).
class ModelJob:
	const Lines := preload("res://scripts/utils/edge_lines.gd")
	const PuffsScript := preload("res://scenes/sculpture/cloud_puffs.gd")
	var surfaces: Array = []
	var angle: float = 35.0
	## Results, once [method run] is done.
	var ridge_arrays: Array = []
	var puff_table: Dictionary = {}
	## -1 until the triangles have been read and the worker task started.
	var task_id: int = -1
	var waiting_ridges: Array[MeshInstance3D] = []
	var waiting_puffs: Array[MultiMeshInstance3D] = []

	func run() -> void:
		ridge_arrays = Lines.build_outline_arrays(Lines.find_feature_edges_in(surfaces, angle))
		puff_table = PuffsScript.make_surface_table(surfaces)


## One cloud's state.
class SkyCloud:
	## The cloud's mass; null for a bare state (tests).
	var mass: SculptureMass
	var has_mass: bool = false
	## Its wisps, which grow with it; null without.
	var wisps: Node3D
	## Its middle (world) when it formed.
	var start: Vector3 = Vector3.ZERO
	## Seconds since it formed.
	var age: float = 0.0
	## Its radius before growing, in metres.
	var radius: float = 1.0
	## Its orbit: ring radius, height (world) and angle around the gyre centre.
	var ring: float = 0.0
	var height: float = 0.0
	var angle: float = 0.0
	## Its middle (world) now.
	var center: Vector3 = Vector3.ZERO
	## How many times its own size it has grown, and that with its breathing.
	var growth: float = 1.0
	var size: float = 1.0
	var tumble: Quaternion = Quaternion.IDENTITY
	var tumble_axis: Vector3 = Vector3.UP
	var axis_turn: Vector3 = Vector3.RIGHT
	var bob_phase: float = 0.0
	var breath_phase: float = 0.0


func _ready() -> void:
	_rng.randomize()
	EventBus.cloud_formed.connect(_on_cloud_formed)


func _physics_process(delta: float) -> void:
	step(delta)


func _process(_delta: float) -> void:
	# Read one waiting model's triangles and hand the rest of its work to a worker thread.
	while not _read_queue.is_empty():
		var mesh: Mesh = _read_queue.pop_front()
		var job: ModelJob = _model_jobs.get(mesh)
		if job == null:
			continue
		job.surfaces = Edges.get_surfaces(mesh)
		job.angle = ridge_angle
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Cloud details")
		break
	for mesh: Mesh in _model_jobs.keys():
		var job: ModelJob = _model_jobs[mesh]
		if job.task_id < 0 or not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_model_jobs.erase(mesh)
		mesh.set_meta(RIDGES_META, Edges.mesh_from_arrays(job.ridge_arrays))
		mesh.set_meta(PUFF_TABLE_META, job.puff_table)
		for ridges in job.waiting_ridges:
			if is_instance_valid(ridges):
				ridges.mesh = mesh.get_meta(RIDGES_META)
		for puffs in job.waiting_puffs:
			if is_instance_valid(puffs):
				_build_puffs(puffs as Puffs, job.puff_table)


func _exit_tree() -> void:
	# Every worker task must be waited for, even when the world closes mid-job.
	for mesh: Mesh in _model_jobs.keys():
		var job: ModelJob = _model_jobs[mesh]
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
	_model_jobs.clear()
	_read_queue.clear()


## Starts a cloud whose middle was at [param start] (world) when it formed, with [param radius]
## (metres, before growing). Its orbit's angle is its bearing from the gyre centre, so it rises
## outward; its ring and height are random within the gyre and the zone.
func add_cloud(start: Vector3, radius: float, mass: SculptureMass = null) -> SkyCloud:
	var cloud := SkyCloud.new()
	cloud.mass = mass
	cloud.has_mass = mass != null
	cloud.start = start
	cloud.center = start
	cloud.radius = maxf(radius, 0.01)
	var flat := Vector2(start.x, start.z) - gyre_center
	cloud.angle = flat.angle() if flat.length() > 1.0 else _rng.randf() * TAU
	cloud.ring = _rng.randf_range(gyre_radius_range.x, gyre_radius_range.y)
	cloud.height = _rng.randf_range(zone_heights.x, zone_heights.y)
	cloud.bob_phase = _rng.randf() * TAU
	cloud.breath_phase = _rng.randf() * TAU
	cloud.tumble_axis = _random_direction()
	cloud.axis_turn = _random_direction()
	clouds.append(cloud)
	return cloud


## Moves every cloud on by [param delta] seconds.
func step(delta: float) -> void:
	# Clouds whose mass is gone (the world closed) leave the sky.
	for i in range(clouds.size() - 1, -1, -1):
		if clouds[i].has_mass and not is_instance_valid(clouds[i].mass):
			clouds.remove_at(i)
	for cloud in clouds:
		cloud.age += delta
		if cloud.age > rise_delay:
			cloud.angle += get_angular_speed(cloud.ring) * delta
	_push_apart(delta)
	for cloud in clouds:
		_place(cloud, delta)


## How far through its rise [param cloud] is: 0 while it holds still, 1 once it has arrived.
func get_rise(cloud: SkyCloud) -> float:
	if rise_time <= 0.0:
		return 1.0 if cloud.age >= rise_delay else 0.0
	return clampf((cloud.age - rise_delay) / rise_time, 0.0, 1.0)


## How fast (radians per second) the ring at [param radius] turns.
func get_angular_speed(radius: float) -> float:
	var middle := (gyre_radius_range.x + gyre_radius_range.y) * 0.5
	return TAU / maxf(gyre_lap_time, 0.001) * pow(middle / maxf(radius, 1.0), gyre_shear)


## Where [param cloud]'s orbit is now (world), without its bob.
func get_orbit_point(cloud: SkyCloud) -> Vector3:
	return Vector3(gyre_center.x + cos(cloud.angle) * cloud.ring, cloud.height, gyre_center.y + sin(cloud.angle) * cloud.ring)


## Gently pushes apart every pair of arrived clouds whose spheres overlap. The push moves their
## orbits, so once apart they stay apart.
func _push_apart(delta: float) -> void:
	for i in clouds.size():
		var a := clouds[i]
		if get_rise(a) < 1.0:
			continue
		for j in range(i + 1, clouds.size()):
			var b := clouds[j]
			if get_rise(b) < 1.0:
				continue
			var offset := a.center - b.center
			var reach := a.radius * a.size + b.radius * b.size
			var distance := offset.length()
			if distance >= reach:
				continue
			var direction := offset / distance if distance > 0.001 else Vector3.UP
			var depth := 1.0 - distance / reach
			var nudge := direction * push_speed * lerpf(MIN_PUSH, 1.0, depth) * delta
			_nudge(a, nudge)
			_nudge(b, -nudge)


## Moves [param cloud]'s orbit by [param move] (world), staying within the gyre and the zone.
func _nudge(cloud: SkyCloud, move: Vector3) -> void:
	var outward := Vector2(cos(cloud.angle), sin(cloud.angle))
	var along := Vector2(-outward.y, outward.x)
	var flat := Vector2(move.x, move.z)
	cloud.ring = clampf(cloud.ring + flat.dot(outward), gyre_radius_range.x, gyre_radius_range.y)
	cloud.angle += flat.dot(along) / maxf(cloud.ring, 1.0)
	cloud.height = clampf(cloud.height + move.y, zone_heights.x, zone_heights.y)


func _place(cloud: SkyCloud, delta: float) -> void:
	var rise := get_rise(cloud)
	var home := get_orbit_point(cloud)
	var outward := smoothstep(0.0, 1.0, rise)
	var climb := smoothstep(0.0, 1.0, pow(rise, CLIMB_LAG))
	var center := Vector3(lerpf(cloud.start.x, home.x, outward), lerpf(cloud.start.y, home.y, climb), lerpf(cloud.start.z, home.z, outward))
	# The small life fades in as the cloud rises.
	center.y += bob_height * sin(TAU * cloud.age / maxf(bob_period, 0.01) + cloud.bob_phase) * rise
	cloud.center = center
	cloud.growth = lerpf(1.0, scale_multiplier, outward)
	cloud.size = cloud.growth * (1.0 + breath * sin(TAU * cloud.age / maxf(breath_period, 0.01) + cloud.breath_phase) * rise)
	if tumble_period > 0.0 and rise > 0.0:
		var turn := TAU / tumble_period * delta
		cloud.tumble_axis = cloud.tumble_axis.rotated(cloud.axis_turn, turn / AXIS_TURN_TUMBLES).normalized()
		cloud.tumble = (Quaternion(cloud.tumble_axis, turn * rise) * cloud.tumble).normalized()
	_apply(cloud)


## Puts [param cloud]'s mass where its state says: the body turned and scaled around the cloud's
## middle, the mass moved so the body sits on the cloud's path, the wisps grown with it.
func _apply(cloud: SkyCloud) -> void:
	if not cloud.has_mass or not is_instance_valid(cloud.mass):
		return
	var body: Node3D = cloud.mass.get_cloud_body()
	if body == null:
		return
	body.basis = Basis(cloud.tumble).scaled(Vector3.ONE * cloud.size)
	cloud.mass.global_position = cloud.center - cloud.mass.global_basis * body.position
	cloud.mass.set_cloud_bounds(cloud.center.y, cloud.radius * cloud.size)
	if is_instance_valid(cloud.wisps):
		cloud.wisps.scale = Vector3.ONE * cloud.growth


func _on_cloud_formed(mass: SculptureMass) -> void:
	var body: Node3D = mass.get_cloud_body()
	if body == null:
		push_warning("CloudSky: a cloud formed without a cloud body; it stays where it is.")
		return
	var cloud := add_cloud(body.global_position, _get_radius(body), mass)
	_dress(cloud, body)


## Puffs and ridge lines on each of the cloud's object meshes, and wisps around it. Both hang under
## the mesh; they fill in as soon as the model's details are known ([ModelJob]).
func _dress(cloud: SkyCloud, body: Node3D) -> void:
	for piece in cloud.mass.pieces:
		# Before anything is added: the ridges are mesh instances too.
		for mesh_instance in piece.get_meshes():
			var mesh := mesh_instance.mesh
			if mesh == null:
				continue
			var job: ModelJob = null
			var known := mesh.has_meta(RIDGES_META) and mesh.has_meta(PUFF_TABLE_META)
			if not known:
				job = _model_jobs.get(mesh)
				if job == null:
					job = ModelJob.new()
					_model_jobs[mesh] = job
					_read_queue.append(mesh)
			if puff_material and puffs_per_object > 0:
				var puffs := Puffs.new()
				puffs.name = "CloudPuffs"
				mesh_instance.add_child(puffs)
				if known:
					_build_puffs(puffs, mesh.get_meta(PUFF_TABLE_META))
				else:
					job.waiting_puffs.append(puffs)
			if ridge_material:
				var ridges := MeshInstance3D.new()
				ridges.name = "CloudRidges"
				ridges.material_override = ridge_material
				ridges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# The lines are widened on screen, past the mesh's own box.
				ridges.extra_cull_margin = 1.0
				mesh_instance.add_child(ridges)
				if known:
					ridges.mesh = mesh.get_meta(RIDGES_META)
				else:
					job.waiting_ridges.append(ridges)
	if puff_material and wisp_count.y > 0:
		var wisps := Wisps.new()
		wisps.name = "CloudWisps"
		cloud.mass.add_child(wisps)
		wisps.position = body.position
		wisps.setup(_rng.randi_range(maxi(wisp_count.x, 0), wisp_count.y), cloud.radius, _get_sphere(), puff_material, _rng)
		cloud.wisps = wisps


func _build_puffs(puffs: Puffs, table: Dictionary) -> void:
	puffs.build(table, puffs_per_object, puff_size, _get_sphere(), puff_material, _rng)


## The ridge line mesh for an object's [param mesh] (EdgeLines), found right away (on this thread)
## the first time it's asked for and kept on the mesh, so every cloud with that model shares it.
func get_ridge_mesh(mesh: Mesh) -> ArrayMesh:
	if not mesh.has_meta(RIDGES_META):
		mesh.set_meta(RIDGES_META, Edges.build_outline_mesh(Edges.find_feature_edges(mesh, ridge_angle)))
	return mesh.get_meta(RIDGES_META)


## Half the longest side of the box around the cloud's objects, in metres: roughly its radius.
func _get_radius(body: Node3D) -> float:
	var to_body := body.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := (to_body * mesh_instance.global_transform) * mesh_instance.get_aabb()
		bounds = bounds.merge(box) if has_bounds else box
		has_bounds = true
	return bounds.get_longest_axis_size() * 0.5 if has_bounds else 1.0


## The unit sphere every puff and wisp uses.
func _get_sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 10
		_sphere.rings = 5
	return _sphere


func _random_direction() -> Vector3:
	var direction := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
