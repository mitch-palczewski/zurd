class_name CloudWisps
extends MultiMeshInstance3D

## Small puffs that come and go around a cloud (Cloud-Formation Design Doc §4.2), like the scraps
## of cloud that form and melt away around real ones. Each slot waits, then a wisp appears just
## outside the cloud, drifts slowly away as it fades in, lasts a while, and thins and shrinks away;
## then the slot waits again and its next wisp appears somewhere else. It sits at the cloud's
## middle without turning, and [CloudSky] scales it as the cloud grows, so sizes and distances here
## are in the cloud's size before growing. Visual only.

## Puffs in one wisp.
const PUFFS_PER_WISP := 4
## Seconds a wisp takes to appear, and to melt away.
const FADE_IN := 8.0
const FADE_OUT := 10.0
## Seconds a wisp lasts, fades included.
const LIFE := Vector2(40.0, 90.0)
## Seconds a slot waits before its next wisp.
const WAIT := Vector2(1.0, 25.0)
## Where a wisp appears, in cloud radii from the middle.
const DISTANCE := Vector2(1.05, 1.5)
## A wisp's size, in cloud radii.
const SIZE := Vector2(0.12, 0.25)
## How fast a wisp drifts, in cloud radii per second.
const DRIFT := Vector2(0.004, 0.012)

## The cloud's radius before growing, in metres.
var cloud_radius: float = 1.0

var _wisps: Array[Wisp] = []
var _rng: RandomNumberGenerator


## One slot's current wisp.
class Wisp:
	## Seconds until the next wisp appears; 0 while one is showing.
	var wait: float = 0.0
	var age: float = 0.0
	var life: float = 1.0
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var size: float = 1.0
	## Each puff, in units of the wisp's size.
	var puffs: Array[Transform3D] = []
	var noise_seed: Color = Color()


## Makes [param count] slots around a cloud of [param radius] (before growing). The first wisps
## trickle in over the first [constant WAIT] seconds.
func setup(count: int, radius: float, sphere: Mesh, puff_material: Material, rng: RandomNumberGenerator) -> void:
	cloud_radius = maxf(radius, 0.01)
	_rng = rng
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = puff_material
	var puffs := MultiMesh.new()
	puffs.transform_format = MultiMesh.TRANSFORM_3D
	# Per-puff noise seed (xyz) and fade (w), read by cloud_puff.gdshader.
	puffs.use_custom_data = true
	puffs.mesh = sphere
	puffs.instance_count = count * PUFFS_PER_WISP
	multimesh = puffs
	_wisps.clear()
	for i in count:
		var wisp := Wisp.new()
		wisp.wait = _rng.randf_range(0.0, WAIT.y)
		_wisps.append(wisp)
	_write()


func _process(delta: float) -> void:
	advance(delta)


## Moves every slot on by [param delta] seconds.
func advance(delta: float) -> void:
	for wisp in _wisps:
		if wisp.wait > 0.0:
			wisp.wait -= delta
			if wisp.wait <= 0.0:
				_spawn(wisp)
			continue
		wisp.age += delta
		wisp.position += wisp.velocity * delta
		if wisp.age >= wisp.life:
			wisp.wait = _rng.randf_range(WAIT.x, WAIT.y)
	_write()


func get_wisp_count() -> int:
	return _wisps.size()


## How much of slot [param index]'s wisp shows: 0 while the slot waits, up to 1 between its fades.
func get_visibility(index: int) -> float:
	var wisp := _wisps[index]
	if wisp.wait > 0.0:
		return 0.0
	return clampf(minf(wisp.age / FADE_IN, (wisp.life - wisp.age) / FADE_OUT), 0.0, 1.0)


func get_visible_count() -> int:
	var count := 0
	for i in _wisps.size():
		if get_visibility(i) > 0.0:
			count += 1
	return count


func _spawn(wisp: Wisp) -> void:
	var direction := _random_direction()
	var drift := (direction * 0.6 + _random_direction() * 0.4).normalized()
	wisp.wait = 0.0
	wisp.age = 0.0
	wisp.life = _rng.randf_range(LIFE.x, LIFE.y)
	wisp.position = direction * cloud_radius * _rng.randf_range(DISTANCE.x, DISTANCE.y)
	wisp.velocity = drift * cloud_radius * _rng.randf_range(DRIFT.x, DRIFT.y)
	wisp.size = cloud_radius * _rng.randf_range(SIZE.x, SIZE.y)
	wisp.puffs.clear()
	for k in PUFFS_PER_WISP:
		var radius := _rng.randf_range(0.35, 0.6)
		var squash := _rng.randf_range(0.7, 1.0)
		var offset := _random_direction() * _rng.randf_range(0.0, 0.6)
		wisp.puffs.append(Transform3D(Basis.from_scale(Vector3(1.0, squash, 1.0) * radius), offset))
	wisp.noise_seed = Color(_rng.randf(), _rng.randf(), _rng.randf(), 0.0)


func _random_direction() -> Vector3:
	var direction := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP


func _write() -> void:
	for i in _wisps.size():
		var wisp := _wisps[i]
		var shown := get_visibility(i)
		# Melting away, a wisp thins out and shrinks.
		var scale_now := wisp.size * (0.5 + 0.5 * shown)
		for k in PUFFS_PER_WISP:
			var index := i * PUFFS_PER_WISP + k
			if shown <= 0.0 or k >= wisp.puffs.size():
				multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
				multimesh.set_instance_custom_data(index, Color(0.0, 0.0, 0.0, 1.0))
				continue
			var puff := wisp.puffs[k]
			multimesh.set_instance_transform(index, Transform3D(puff.basis * scale_now, wisp.position + puff.origin * scale_now))
			var noise_seed := wisp.noise_seed
			multimesh.set_instance_custom_data(index, Color(noise_seed.r + k * 0.13, noise_seed.g, noise_seed.b, 1.0 - shown))
