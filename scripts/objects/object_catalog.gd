@tool
class_name ObjectCatalog
extends Resource

## The objects the ship can launch (hardening plan step 4): one entry per object, each a scene and a
## group. Random launches pick evenly across the usable entries (those with a scene), and a launch
## station steps through them in list order. To add a model, drop its .glb into
## assets/models/objects/, then press Sync here.

## Meta on every launched object, and on the [MassPiece] it fuses into: its entry's group.
const GROUP_META := &"catalog_group"
## The group of new entries, and of objects that aren't in a catalog. Always offered.
const DEFAULT_GROUP := &"Unsorted"
## Where the GLB importer puts the scenes of launchable objects.
const OBJECTS_DIR := "res://scenes/objects/rigid/"

## Adds every scene in scenes/objects/rigid/ that isn't listed yet, at the end in group Unsorted,
## and saves the catalog. Then reports problems in the Output panel. It never removes or reorders
## entries.
@export_tool_button("Sync with rigid scenes", "Reload") var sync_button := sync_with_scenes

## The group names an entry can choose from. Unsorted is always offered. No commas.
@export var groups: Array[StringName] = [DEFAULT_GROUP]:
	set(value):
		groups = value
		_share_group_names()

@export var entries: Array[ObjectCatalogEntry] = []:
	set(value):
		entries = value
		_share_group_names()


## A random usable entry, each equally likely; null when there is none.
func pick_random() -> ObjectCatalogEntry:
	var usable := get_usable_entries()
	return null if usable.is_empty() else usable.pick_random()


## The entries with a scene, in list order. Random launches and stations use only these.
func get_usable_entries() -> Array[ObjectCatalogEntry]:
	var usable: Array[ObjectCatalogEntry] = []
	for entry in entries:
		if entry and entry.scene:
			usable.append(entry)
	return usable


## The number of usable entries.
func size() -> int:
	return get_usable_entries().size()


## The usable entry at [param index], or null when it's out of range.
func get_entry(index: int) -> ObjectCatalogEntry:
	var usable := get_usable_entries()
	return usable[index] if index >= 0 and index < usable.size() else null


## The entry for [param scene], or null when it isn't listed.
func find_entry(scene: PackedScene) -> ObjectCatalogEntry:
	if scene == null:
		return null
	var key := _scene_key(scene)
	for entry in entries:
		if entry and entry.scene and _scene_key(entry.scene) == key:
			return entry
	return null


## [param scene]'s group, or [constant DEFAULT_GROUP] when it isn't listed.
func get_group(scene: PackedScene) -> StringName:
	var entry := find_entry(scene)
	return entry.group if entry else DEFAULT_GROUP


## The group of a launched object or a fused [MassPiece], or [constant DEFAULT_GROUP] when it has
## none (for example, an object placed by hand in a scene).
static func group_of(node: Node) -> StringName:
	return node.get_meta(GROUP_META, DEFAULT_GROUP)


## The names an entry can choose from: [member groups], plus [constant DEFAULT_GROUP] if missing.
func get_group_names() -> PackedStringArray:
	var names := PackedStringArray()
	for group in groups:
		if not group.is_empty() and not names.has(group):
			names.append(group)
	if not names.has(DEFAULT_GROUP):
		names.append(DEFAULT_GROUP)
	return names


## Adds every scene in [constant OBJECTS_DIR] that isn't listed yet, at the end and in
## [constant DEFAULT_GROUP], saves the catalog if it added any, then checks every entry (see
## [method check]). Returns [code]{"added": paths, "problems": messages}[/code]; both are also
## reported in the Output panel.
func sync_with_scenes() -> Dictionary:
	var listed := {}
	for entry in entries:
		if entry and entry.scene:
			listed[_scene_key(entry.scene)] = true

	var added: Array[String] = []
	var problems: Array[String] = []
	var new_entries: Array[ObjectCatalogEntry] = entries.duplicate()
	for path in _list_object_scenes():
		if listed.has(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			problems.append("%s can't be loaded as a scene." % path.get_file())
			continue
		var entry := ObjectCatalogEntry.new()
		entry.scene = scene
		new_entries.append(entry)
		added.append(path)

	if not added.is_empty():
		entries = new_entries
		notify_property_list_changed()
		emit_changed()
		if _is_saved_file():
			var error := ResourceSaver.save(self)
			if error != OK:
				problems.append("Couldn't save %s (%s)." % [resource_path, error_string(error)])

	problems.append_array(check())
	_report(added, problems)
	return {"added": added, "problems": problems}


## Problems with the entries: one without a scene, a scene listed twice (it would be picked twice as
## often), a group that isn't offered, and a scene that breaks the box-collider contract the
## sculpture code depends on (a [RigidBody3D] root whose first collision shape is a [BoxShape3D]).
## Empty when there are none.
func check() -> Array[String]:
	var problems: Array[String] = []
	var names := get_group_names()
	var first_index := {}
	for i in entries.size():
		var entry := entries[i]
		if entry == null or entry.scene == null:
			problems.append("Entry %d has no scene; it is skipped." % i)
			continue
		var key := _scene_key(entry.scene)
		var label := _scene_label(entry.scene)
		if first_index.has(key):
			problems.append("%s is listed twice (entries %d and %d), so it is picked twice as often." % [label, first_index[key], i])
		else:
			first_index[key] = i
		if not names.has(entry.group):
			problems.append("%s: group '%s' isn't in the catalog's groups." % [label, entry.group])
		var contract := _check_scene(entry.scene)
		if not contract.is_empty():
			problems.append("%s: %s" % [label, contract])
	return problems


func _share_group_names() -> void:
	var names := get_group_names()
	for entry in entries:
		if entry:
			entry.group_names = names


func _report(added: Array[String], problems: Array[String]) -> void:
	for problem in problems:
		push_warning("ObjectCatalog: " + problem)
	var summary := "ObjectCatalog: %d objects." % size()
	if not added.is_empty():
		var names := PackedStringArray()
		for path in added:
			names.append(_path_label(path))
		summary += " Added %d to %s: %s." % [added.size(), DEFAULT_GROUP, ", ".join(names)]
	summary += " No problems." if problems.is_empty() else " %d problems (see the warnings)." % problems.size()
	print(summary)


func _is_saved_file() -> bool:
	return resource_path.begins_with("res://") and not resource_path.contains("::")


## The object scenes in [constant OBJECTS_DIR], in the FileSystem dock's order.
static func _list_object_scenes() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(OBJECTS_DIR):
		if file.get_extension() == "tscn":
			paths.append(OBJECTS_DIR + file)
	paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return paths


## The empty string when [param scene] keeps the box-collider contract, otherwise what's wrong.
static func _check_scene(scene: PackedScene) -> String:
	var node := scene.instantiate()
	if node == null:
		return "the scene can't be instantiated."
	var problem := ""
	if not node is RigidBody3D:
		problem = "its root isn't a RigidBody3D."
	else:
		var shape := _get_first_collision_shape(node)
		if shape == null:
			problem = "it has no collision shape."
		elif not shape.shape is BoxShape3D:
			problem = "its first collision shape isn't a box, and the sculpture code only measures boxes."
	node.free()
	return problem


## The first [CollisionShape3D] child, the one [ObjectParts] reads an object's size from.
static func _get_first_collision_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


## A scene's identity: its file, or the scene itself when it has none.
static func _scene_key(scene: PackedScene) -> String:
	return scene.resource_path if not scene.resource_path.is_empty() else str(scene.get_instance_id())


## The object's name for messages: its scene's file name without "_rigid.tscn".
static func _scene_label(scene: PackedScene) -> String:
	return _path_label(scene.resource_path) if not scene.resource_path.is_empty() else "An unsaved scene"


static func _path_label(path: String) -> String:
	return path.get_file().get_basename().trim_suffix("_rigid")
