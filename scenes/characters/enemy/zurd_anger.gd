class_name ZurdAnger
extends RefCounted

## The Zurds' shared anger, from 0 to 1 (Zurd Core Design Doc §3). It rises when the players add
## objects past what the Zurds tolerate or attack Zurds. Launching under the limits neither raises
## nor lowers it: it holds. It falls once the players stop launching and leave the Zurds alone. A
## mess that just sits there doesn't keep raising it. Plain rules with no scene, driven by the
## [ZurdDirector], so they're unit-tested on their own.

## Loose objects in the world before launches add anger.
var tolerated_mess: int = 15
## Added per launch while the loose objects are over [member tolerated_mess].
var mess_anger: float = 0.05
## Parts a sculpture may have before growing it adds anger (a hard cut-off).
var tolerated_sculpture_size: int = 15
## Added per part a sculpture gains beyond [member tolerated_sculpture_size].
var sculpture_anger: float = 0.03
## Added per swat, ram or launched-object hit on a Zurd.
var attack_anger: float = 0.1
## Seconds without a launch or anything adding anger before it starts to fall.
var calm_delay: float = 3.0
## How fast anger falls, per second, once it does.
var decay_rate: float = 0.05

## The anger now, from 0 to 1.
var value: float = 0.0

var _calm_time: float = 0.0


## Advances [param delta] seconds. Anger falls once nothing has held or raised it for
## [member calm_delay].
func update(delta: float) -> void:
	_calm_time += delta
	if _calm_time >= calm_delay:
		value = maxf(value - decay_rate * delta, 0.0)


## The ship launched an object; [param loose_count] loose objects are in the world now, counting it.
## Over the mess limit it adds anger; under it, it only holds the anger where it is.
func on_launch(loose_count: int) -> void:
	_calm_time = 0.0
	if loose_count > tolerated_mess:
		_add(mess_anger)


## A sculpture gained [param parts_added] parts and now has [param size]. Only the parts beyond
## [member tolerated_sculpture_size] add anger.
func on_sculpture_grew(parts_added: int, size: int) -> void:
	var beyond := mini(parts_added, size - tolerated_sculpture_size)
	if beyond > 0:
		_add(sculpture_anger * beyond)


## A Zurd was swatted, rammed or hit by a launched object.
func on_zurd_attacked() -> void:
	_add(attack_anger)


## How many of [param zurd_count] Zurds should be Hostile: none at anger 0, all at anger 1.
func get_hostile_count(zurd_count: int) -> int:
	return clampi(roundi(value * zurd_count), 0, zurd_count)


func _add(amount: float) -> void:
	if amount <= 0.0:
		return
	value = clampf(value + amount, 0.0, 1.0)
	_calm_time = 0.0
