extends "res://tests/test_case.gd"

## The world's layout (hardening plan step 2): its parts, where spawned things go, and that the
## worlds built on base_world.tscn keep their own additions and overrides.

const AREA := Vector3(0.0, 100.0, 300.0)
const SLAB := "res://scenes/objects/rigid/GEO_Stock_07_rigid.tscn"
const OTHER := "res://scenes/objects/rigid/GEO_Stock_06_rigid.tscn"
const ZURD_SCENE := "res://scenes/characters/enemy/zurd.tscn"
const PROJECTILE_SCENE := "res://scenes/input/swat/swat_projectile.tscn"
## Scenes that build on base_world.tscn. The sandbox ones may be removed one day; then they're
## skipped.
const SANDBOX_WORLD := "res://sandbox/world/idea_large_world.tscn"
const SCULPTURE_TEST_SCENE := "res://sandbox/test_sculpture_mass.tscn"
const PARTS: Array[String] = [
	"Environment/WorldEnvironment",
	"Environment/DirectionalLight3D",
	"GameSystems/MassManager",
	"GameSystems/SculptureFx",
	"Input/MouseSwatInput",
	"Actors/Ship/PlayerShip",
	"Actors/Zurds",
	"Actors/Objects",
	"Actors/Masses",
	"Actors/Projectiles",
]


func test_the_world_has_its_parts() -> void:
	var world := await load_world(false)
	for part in PARTS:
		check(world.has_node(part), "the world has %s" % part)


func test_spawned_things_go_to_their_container() -> void:
	var world := await load_world(false)
	var slab := spawn_object(SLAB, AREA)
	check(slab.get_parent() == world.get_node(^"Actors/Objects"), "a launched object goes to Actors/Objects")

	var other := spawn_beside(OTHER, slab, Vector3.RIGHT)
	for i in get_mass_manager(world).hits_to_fuse:
		slab.body_entered.emit(other)
	await wait_physics(2)
	var masses := world.get_node(^"Actors/Masses").get_children()
	check(masses.size() == 1 and masses[0] is SculptureMass, "a new sculpture mass goes to Actors/Masses")

	var zurd := (load(ZURD_SCENE) as PackedScene).instantiate() as Node3D
	EventBus.spawn_requested.emit(zurd)
	check(zurd.get_parent() == world.get_node(^"Actors/Zurds"), "a Zurd goes to Actors/Zurds")
	zurd.free()

	var projectile := (load(PROJECTILE_SCENE) as PackedScene).instantiate() as Node3D
	EventBus.spawn_requested.emit(projectile)
	check(projectile.get_parent() == world.get_node(^"Actors/Projectiles"), "a swat projectile goes to Actors/Projectiles")
	projectile.free()


func test_worlds_built_on_the_base_keep_their_additions() -> void:
	var zurd_world := (load(WORLD_PATH) as PackedScene).instantiate()
	check(zurd_world is BaseWorld, "zurd_world builds on the base world")
	check(zurd_world.has_node(^"GameSystems/MassManager") and zurd_world.has_node(^"Actors/Ship/PlayerShip"), "with the base world's layout")
	check(zurd_world.has_node(^"Terrain"), "and keeps its terrain")
	zurd_world.free()

	if ResourceLoader.exists(SANDBOX_WORLD):
		var sandbox_world := (load(SANDBOX_WORLD) as PackedScene).instantiate()
		check(sandbox_world.has_node(^"Actors/Ship/PlayerShip") and sandbox_world.has_node(^"TestLgGround"), "the sandbox large world has the base layout and its ground")
		sandbox_world.free()

	if ResourceLoader.exists(SCULPTURE_TEST_SCENE):
		var test_scene := (load(SCULPTURE_TEST_SCENE) as PackedScene).instantiate()
		var manager := test_scene.get_node_or_null(^"GameSystems/MassManager") as MassManager
		if check(manager != null, "the sculpture test scene has the MassManager"):
			check_equal(manager.cloud_threshold_count, 5, "its cloud threshold override still applies")
			check_equal(manager.hits_to_fuse, 1, "its hits-to-fuse override still applies")
			check(manager.debug_labels, "its debug labels override still applies")
			check(not is_equal_approx(manager.fuse_push, 1.0), "values it doesn't override still come from the base world")
		test_scene.free()
