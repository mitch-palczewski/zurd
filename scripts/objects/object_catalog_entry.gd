@tool
class_name ObjectCatalogEntry
extends Resource

## One launchable object in an [ObjectCatalog] (hardening plan step 4).

## The object's rigid scene, from scenes/objects/rigid/.
@export var scene: PackedScene
## A label for later systems (HUD, Zurds, combining rules); nothing reads it yet. In the Inspector
## it is a dropdown of the catalog's groups.
@export var group: StringName = ObjectCatalog.DEFAULT_GROUP

## The catalog's group names, for the Inspector's dropdown. Set by the catalog; not saved.
var group_names: PackedStringArray = PackedStringArray():
	set(value):
		group_names = value
		notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "group" and not group_names.is_empty():
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(group_names)
