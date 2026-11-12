extends CanvasLayer

## Playtest-only readout of the Zurds (Zurd Core Design Doc §9): the shared anger, how many Zurds are
## Hostile, and the mess that angers them. The [ZurdDirector] adds it as its child when its
## show_testing_hud is on.

const BAR_LENGTH := 10

@onready var _readout: Label = $Readout

var _director: ZurdDirector


func _ready() -> void:
	_director = get_parent() as ZurdDirector


func _process(_delta: float) -> void:
	if _director == null:
		return
	var anger := _director.anger
	var zurds := _director.get_zurds()
	var hostile := zurds.filter(func(zurd: Zurd) -> bool: return zurd.is_hostile).size()
	var away := zurds.filter(func(zurd: Zurd) -> bool: return zurd.is_driven_off()).size()
	var largest := 0
	for mass in _director.get_sculptures():
		largest = maxi(largest, mass.get_part_count())
	var filled := roundi(anger.value * BAR_LENGTH)
	_readout.text = "\n".join(PackedStringArray([
		"ZURDS (testing)",
		"anger  %s %.2f" % ["█".repeat(filled) + "░".repeat(BAR_LENGTH - filled), anger.value],
		"hostile  %d of %d   (driven off: %d)" % [hostile, zurds.size(), away],
		"loose objects  %d / %d" % [_director.get_loose_objects().size(), anger.tolerated_mess],
		"largest sculpture  %d / %d" % [largest, anger.tolerated_sculpture_size],
	]))
