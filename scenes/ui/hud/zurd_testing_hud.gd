extends CanvasLayer

## Playtest-only readout of the Zurds (Zurd Core Design Doc §12.1): the Zurds nearest the ship with
## their role, state and anger, their average as the nearby anger, how many of each role there are
## and how many are Hostile, and how many settled sculptures have a Sentinel. The [ZurdDirector] adds
## it as its child when its show_testing_hud is on.

const BAR_LENGTH := 10
## How many of the nearest Zurds are listed.
const NEARBY := 5

@onready var _readout: Label = $Readout

var _director: ZurdDirector


func _ready() -> void:
	_director = get_parent() as ZurdDirector


func _process(_delta: float) -> void:
	if _director == null:
		return
	var zurds := _director.get_zurds()
	var ship := get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D
	var near: Array[Zurd] = zurds.duplicate()
	if ship:
		var from := ship.global_position
		near.sort_custom(func(a: Zurd, b: Zurd) -> bool: return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	near = near.slice(0, NEARBY)
	var nearby := 0.0
	for zurd in near:
		nearby += zurd.anger.value / near.size()

	var hostile := zurds.filter(func(zurd: Zurd) -> bool: return zurd.is_hostile).size()
	var away := zurds.filter(func(zurd: Zurd) -> bool: return zurd.is_driven_off()).size()
	var roles: Dictionary[String, int] = {}
	for zurd in zurds:
		roles[zurd.get_role_name()] = roles.get(zurd.get_role_name(), 0) + 1
	var role_counts := PackedStringArray()
	for role_name in roles:
		role_counts.append("%s %d" % [role_name.to_lower(), roles[role_name]])
	var settled := _director.get_sculptures().filter(func(mass: SculptureMass) -> bool: return _director.is_settled(mass))
	var watched := settled.filter(func(mass: SculptureMass) -> bool: return zurds.any(func(zurd: Zurd) -> bool: return zurd.home_sculpture == mass)).size()

	var lines := PackedStringArray([
		"ZURDS (testing)",
		"nearby anger  %s %.2f" % [_bar(nearby), nearby],
		"hostile  %d of %d   (driven off: %d)" % [hostile, zurds.size(), away],
		"   ".join(role_counts),
		"settled sculptures  %d   (with a sentinel: %d)" % [settled.size(), watched],
		"",
	])
	for zurd in near:
		var distance := zurd.global_position.distance_to(ship.global_position) if ship else 0.0
		lines.append("%s  %s  %s %.2f  %d m" % [zurd.get_role_name(), _state(zurd), _bar(zurd.anger.value), zurd.anger.value, roundi(distance)])
	_readout.text = "\n".join(lines)


func _bar(value: float) -> String:
	var filled := clampi(roundi(value * BAR_LENGTH), 0, BAR_LENGTH)
	return "█".repeat(filled) + "░".repeat(BAR_LENGTH - filled)


func _state(zurd: Zurd) -> String:
	if zurd.is_driven_off():
		return "driven off"
	if zurd.is_calming:
		return "calming"
	return "HOSTILE" if zurd.is_hostile else "passive"
