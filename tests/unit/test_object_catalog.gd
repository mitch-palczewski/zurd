extends "res://tests/test_case.gd"

## The object catalog (hardening plan step 4): even random picks, stepping over usable entries,
## groups, the Sync button's problem report, and the real catalog's health. Sync only ever runs on
## catalogs made here in memory: it saves a catalog loaded from a file.

const CATALOG_PATH := "res://data/object_catalog.tres"


func test_random_picks_are_even_and_skip_empty_entries() -> void:
	var scenes := _real_scenes(5)
	var catalog := ObjectCatalog.new()
	var entries: Array[ObjectCatalogEntry] = [_entry(scenes[0]), null, _entry(null)]
	for i in range(1, scenes.size()):
		entries.append(_entry(scenes[i]))
	catalog.entries = entries

	var picks := {}
	var draws := 10000
	for i in draws:
		var entry := catalog.pick_random()
		picks[entry] = picks.get(entry, 0) + 1
	check(not picks.has(null), "a null entry or an entry without a scene is never picked")
	check_equal(picks.size(), scenes.size(), "every usable entry gets picked")
	# 10,000 draws over 5 entries: 2000 each, give or take 40 (one standard deviation).
	var expected := draws / scenes.size()
	for entry in picks:
		check_near(picks[entry], expected, 200, "%s is picked about as often as the others" % entry.scene.resource_path.get_file())


func test_size_and_entries_count_usable_entries_only() -> void:
	var scenes := _real_scenes(2)
	var first := _entry(scenes[0])
	var second := _entry(scenes[1])
	var catalog := ObjectCatalog.new()
	var entries: Array[ObjectCatalogEntry] = [first, null, _entry(null), second]
	catalog.entries = entries
	check_equal(catalog.size(), 2, "only entries with a scene count")
	check(catalog.get_entry(0) == first, "the first usable entry is index 0")
	check(catalog.get_entry(1) == second, "empty slots are skipped, so a station never lands on one")
	check(catalog.get_entry(2) == null and catalog.get_entry(-1) == null, "out of range: null")

	var empty := ObjectCatalog.new()
	check(empty.pick_random() == null and empty.size() == 0, "an empty catalog picks nothing")


func test_groups() -> void:
	var scenes := _real_scenes(2)
	var catalog := ObjectCatalog.new()
	var groups: Array[StringName] = [&"Shapes", &"", &"Shapes", &"Animals"]
	catalog.groups = groups
	var entry := _entry(scenes[0], &"Shapes")
	var entries: Array[ObjectCatalogEntry] = [entry]
	catalog.entries = entries
	check_equal(Array(catalog.get_group_names()), ["Shapes", "Animals", "Unsorted"], "group names are unique, never empty, and always offer Unsorted")
	check(catalog.find_entry(scenes[0]) == entry, "find_entry finds a listed scene")
	check(catalog.find_entry(scenes[1]) == null and catalog.find_entry(null) == null, "and nothing for an unlisted scene")
	check_equal(catalog.get_group(scenes[0]), &"Shapes", "a listed scene has its entry's group")
	check_equal(catalog.get_group(scenes[1]), ObjectCatalog.DEFAULT_GROUP, "an unlisted scene is Unsorted")

	var node := Node.new()
	check_equal(ObjectCatalog.group_of(node), ObjectCatalog.DEFAULT_GROUP, "an object without a group meta is Unsorted")
	node.set_meta(ObjectCatalog.GROUP_META, &"Animals")
	check_equal(ObjectCatalog.group_of(node), &"Animals", "an object's group meta is its group")
	node.free()


func test_sync_adds_missing_scenes_and_reports_problems() -> void:
	var scenes := _real_scenes(2)
	var catalog := ObjectCatalog.new()
	var groups: Array[StringName] = [&"Unsorted", &"Shapes"]
	catalog.groups = groups
	var entries: Array[ObjectCatalogEntry] = [
		_entry(null),
		_entry(scenes[0], &"Shapes"),
		_entry(scenes[0], &"Shapes"),
		_entry(scenes[1], &"Nope"),
		_entry(_pack(Node3D.new())),
		_entry(_pack(_body_with(SphereShape3D.new(), 1.0))),
		_entry(_pack(_body_with(BoxShape3D.new(), 2.0))),
		_entry(_pack(RigidBody3D.new())),
	]
	catalog.entries = entries

	var result := catalog.sync_with_scenes()
	var added: Array = result["added"]
	var problems: Array = result["problems"]
	check_equal(added.size(), _rigid_scene_paths().size() - 2, "sync adds every rigid scene that isn't listed")
	check_equal(catalog.entries.size(), entries.size() + added.size(), "at the end of the list")
	check_equal(catalog.entries[-1].group, ObjectCatalog.DEFAULT_GROUP, "in group Unsorted")
	check_equal(problems.size(), 7, "one problem per planted mistake, and none from the real scenes")
	var report := "\n".join(PackedStringArray(problems))
	for expected: String in ["Entry 0 has no scene", "listed twice", "group 'Nope'", "root isn't a RigidBody3D",
			"isn't a box or a convex hull", "isn't at scale 1", "no collision shape"]:
		check(report.contains(expected), "the report names: %s" % expected)
	check(catalog.resource_path.is_empty(), "a catalog that isn't a file is never saved")

	var again := catalog.sync_with_scenes()
	check((again["added"] as Array).is_empty(), "a second sync adds nothing")


func test_real_catalog_is_healthy() -> void:
	var catalog := load(CATALOG_PATH) as ObjectCatalog
	if not check(catalog != null, "the catalog loads"):
		return
	var problems := catalog.check()
	check(problems.is_empty(), "the catalog has no problems: %s" % "; ".join(PackedStringArray(problems)))
	var listed := {}
	for entry in catalog.entries:
		if entry and entry.scene:
			listed[entry.scene.resource_path] = true
	var unlisted: Array[String] = []
	for path in _rigid_scene_paths():
		if not listed.has(path):
			unlisted.append(path.get_file())
	check(unlisted.is_empty(), "every rigid scene is in the catalog (press Sync on it): %s" % ", ".join(PackedStringArray(unlisted)))
	check(catalog.size() > 0, "the catalog has objects to launch")


func _entry(scene: PackedScene, group: StringName = ObjectCatalog.DEFAULT_GROUP) -> ObjectCatalogEntry:
	var entry := ObjectCatalogEntry.new()
	entry.scene = scene
	entry.group = group
	return entry


func _rigid_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(ObjectCatalog.OBJECTS_DIR):
		if file.get_extension() == "tscn":
			paths.append(ObjectCatalog.OBJECTS_DIR + file)
	paths.sort()
	return paths


func _real_scenes(count: int) -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for path in _rigid_scene_paths().slice(0, count):
		scenes.append(load(path) as PackedScene)
	return scenes


func _body_with(shape: Shape3D, scale: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	var node := CollisionShape3D.new()
	node.shape = shape
	node.scale = Vector3.ONE * scale
	body.add_child(node)
	return body


## A scene made in memory from [param root] (no file).
func _pack(root: Node) -> PackedScene:
	for child in root.get_children():
		child.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
