extends "res://tests/test_case.gd"

## Graphics settings reaching the game world (performance settings plan): the sun's shadows, the
## reflecting pool and the sky canopy, for nodes already in the world and nodes added later, and
## High giving each node its own values back. Each test works on a config file of its own.

const CANOPY_SCENE := "res://scenes/scenery/sky_canopy.tscn"
const POOL_SCENE := "res://scenes/scenery/reflecting_pool.tscn"

var _config := ""
var _run_config := ""


func before_each() -> void:
	_run_config = Graphics.config_path
	_config = temp_path("graphics_world_test.json")
	DirAccess.remove_absolute(_config)
	Graphics.set_config_path(_config)
	Graphics.set_preset(Graphics.HIGH)


func after_each() -> void:
	Graphics.set_config_path(_run_config)
	DirAccess.remove_absolute(_config)


func test_settings_reach_the_world_and_high_gives_its_own_values_back() -> void:
	var world := await load_world(false)
	# The test world has no pool of its own (zurd_world02 does).
	world.add_child((load(POOL_SCENE) as PackedScene).instantiate())
	var lights := world.find_children("*", "DirectionalLight3D", true, false)
	var reflection := _find_reflection(world)
	if not check(not lights.is_empty(), "the world has a sun") or not check(reflection != null, "the world has a reflecting pool"):
		return
	var light := lights[0] as DirectionalLight3D
	var own_shadows := light.shadow_enabled
	var own_mode := light.directional_shadow_mode
	var own_scale := reflection.resolution_scale

	Graphics.set_setting(Graphics.SHADOWS, &"off")
	check(not light.shadow_enabled, "Shadows Off: the sun casts none")
	Graphics.set_setting(Graphics.SHADOWS, &"low")
	check_equal(light.shadow_enabled, own_shadows, "Shadows Low: the sun keeps its shadows")
	check(light.directional_shadow_mode <= DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "with at most two splits")

	Graphics.set_setting(Graphics.REFLECTIONS, &"off")
	check(not reflection.enabled, "Reflections Off: the pool doesn't reflect")
	Graphics.set_setting(Graphics.REFLECTIONS, &"low")
	check(reflection.enabled, "Reflections Low: it reflects")
	check(reflection.resolution_scale < own_scale, "at a lower resolution")

	Graphics.set_preset(Graphics.HIGH)
	check_equal(light.shadow_enabled, own_shadows, "High gives the sun its own shadows back")
	check_equal(light.directional_shadow_mode, own_mode, "and its own splits")
	check(reflection.enabled, "and the pool its reflection")
	check_near(reflection.resolution_scale, own_scale, 0.0001, "at its own resolution")


func test_nodes_added_later_get_the_settings() -> void:
	var world := await load_world(false)
	Graphics.set_setting(Graphics.SHADOWS, &"off")
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	world.add_child(light)
	check(not light.shadow_enabled, "a light added after Shadows Off casts no shadows")
	Graphics.set_setting(Graphics.SHADOWS, &"high")
	check(light.shadow_enabled, "High gives it its own shadows back")


func test_a_simple_canopy_has_fewer_shells() -> void:
	var world := await load_world(false)
	# A tree for the canopy to cover, so it has shells (rebuilt, so freed, when the setting changes).
	var tree := Node3D.new()
	world.add_child(tree)
	var canopy := (load(CANOPY_SCENE) as PackedScene).instantiate() as SkyCanopy
	tree.add_to_group(canopy.tree_group)
	var own := canopy.layer_count
	world.add_child(canopy)
	await wait_frames(1)
	check_equal(_shell_count(canopy), own, "on High the canopy draws its own number of shells")
	Graphics.set_setting(Graphics.SKY_CANOPY, &"simple")
	var simple := _shell_count(canopy)
	check(simple >= 1 and simple <= mini(own, Graphics.SIMPLE_CANOPY_LAYERS), "Simple draws at most %d shells" % Graphics.SIMPLE_CANOPY_LAYERS)
	Graphics.set_setting(Graphics.SKY_CANOPY, &"full")
	check_equal(_shell_count(canopy), own, "Full draws its own number again")


func _shell_count(canopy: SkyCanopy) -> int:
	return canopy.get_children(true).filter(func(child: Node) -> bool: return child is MeshInstance3D).size()


func _find_reflection(world: Node) -> PlanarReflection:
	for node in world.find_children("*", "", true, false):
		if node is PlanarReflection:
			return node
	return null
