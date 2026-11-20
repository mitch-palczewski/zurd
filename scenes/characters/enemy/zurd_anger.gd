class_name ZurdAnger
extends RefCounted

## One Zurd's anger, from 0 to 1 (Zurd Core Design Doc §12.1). It rises with what this Zurd itself
## perceives: noticing mess beyond what it tolerates in view, seeing the ship launch while it sees
## too much mess, the sculpture it watches growing past the size limit, and being attacked. The
## amounts come from its role and are scaled by its temper. Every launch it sees holds the anger
## where it is; after a quiet spell it falls, faster for a patient Zurd. The Zurd turns Hostile at
## [member hostile_threshold] and may calm again only below the lower [member calm_threshold], so it
## doesn't flicker between the two. Plain rules with no scene, unit-tested on their own.

## Mess (loose objects, and sculptures when they count) tolerated in view.
var tolerated_in_view: int = 3
## Added per item of mess noticed beyond what's tolerated.
var mess_anger: float = 0.1
## Added per launch seen while there's more mess in view than tolerated.
var launch_anger: float = 0.0
## Added per part the watched sculpture gains beyond the size limit.
var sculpture_anger: float = 0.0
## Added per swat, ram or thrown object.
var attack_anger: float = 0.2
## Multiplies every amount added.
var temper: float = 1.0
## Multiplies how fast it falls.
var patience: float = 1.0
## Seconds without anything holding or adding to it before it starts to fall.
var calm_delay: float = 3.0
## How fast it falls once it does, per second (times patience).
var decay_rate: float = 0.05
## At or above this the Zurd turns Hostile.
var hostile_threshold: float = 0.6
## A Hostile Zurd may calm only below this.
var calm_threshold: float = 0.3

## The anger now, from 0 to 1.
var value: float = 0.0

var _calm_time: float = 0.0


## Takes its amounts from [param role] and its temper and patience from [param temperament].
func configure(role: ZurdRole, temperament: ZurdTemperament) -> void:
	tolerated_in_view = role.tolerated_in_view
	mess_anger = role.mess_anger
	launch_anger = role.launch_anger
	sculpture_anger = role.sculpture_anger
	attack_anger = role.attack_anger
	temper = temperament.temper
	patience = temperament.patience


## Advances [param delta] seconds. It falls once nothing has held or raised it for
## [member calm_delay].
func update(delta: float) -> void:
	_calm_time += delta
	if _calm_time >= calm_delay:
		value = maxf(value - decay_rate * patience * delta, 0.0)


## It just noticed [param new_items] items of mess it hadn't seen before; [param in_view] items are
## in view now, counting them. Only those beyond what it tolerates add anger, so wandering into an
## old pile of 10 counts the 7 past a tolerance of 3.
func on_noticed(new_items: int, in_view: int) -> void:
	var beyond := mini(new_items, in_view - tolerated_in_view)
	if beyond > 0:
		_add(mess_anger * beyond)


## It saw the ship launch while [param in_view] items of mess were in view. That always holds the
## anger; past the tolerance it adds too.
func on_launch_seen(in_view: int) -> void:
	_calm_time = 0.0
	if in_view > tolerated_in_view:
		_add(launch_anger)


## The sculpture it watches gained [param parts_added] parts and now has [param size]. Only the parts
## beyond [param tolerated_size] add anger.
func on_sculpture_grew(parts_added: int, size: int, tolerated_size: int) -> void:
	var beyond := mini(parts_added, size - tolerated_size)
	if beyond > 0:
		_add(sculpture_anger * beyond)


## A swat, ram or thrown object hit it.
func on_attacked() -> void:
	_add(attack_anger)


## Calms it at once: a timid Zurd swatted, a Zurd driven off.
func calm_down() -> void:
	value = 0.0
	_calm_time = 0.0


## Whether a Zurd that is Hostile now ([param hostile]) should be: it turns Hostile at the hostile
## threshold and stays Hostile until the anger falls below the calm threshold.
func should_be_hostile(hostile: bool) -> bool:
	return value > calm_threshold if hostile else value >= hostile_threshold


func _add(amount: float) -> void:
	if amount <= 0.0:
		return
	value = clampf(value + amount * temper, 0.0, 1.0)
	_calm_time = 0.0
