class_name ZurdTemperament
extends RefCounted

## One Zurd's character (Zurd Core Design Doc §12.3), rolled within its role's ranges when it
## spawns, so two Zurds of the same role behave differently.

## Multiplies the anger it gains.
var temper: float = 1.0
## Multiplies how fast its anger falls.
var patience: float = 1.0
## Its calm appetite: the chance it eats a loose object it sees while calm.
var greed: float = 0.5
## 0 to 1: how close a Shadow keeps to the ship, and how it takes a swat (see
## [method get_drive_off_swats]).
var boldness: float = 0.5
## Multiplies how long a Sentinel stops to watch.
var curiosity: float = 1.0
## Multiplies its speeds.
var pace: float = 1.0


## Traits rolled between each range's min and max in [param role].
static func roll(role: ZurdRole, rng: RandomNumberGenerator) -> ZurdTemperament:
	var temperament := ZurdTemperament.new()
	temperament.temper = rng.randf_range(role.temper.x, role.temper.y)
	temperament.patience = rng.randf_range(role.patience.x, role.patience.y)
	temperament.greed = rng.randf_range(role.greed.x, role.greed.y)
	temperament.boldness = rng.randf_range(role.boldness.x, role.boldness.y)
	temperament.curiosity = rng.randf_range(role.curiosity.x, role.curiosity.y)
	temperament.pace = rng.randf_range(role.pace.x, role.pace.y)
	return temperament


## True when it's timid: boldness under [param timid_below].
func is_timid(timid_below: float) -> bool:
	return boldness < timid_below


## Swats that drive it off: one for a timid Zurd, then more the bolder it is, from [param swats].x
## just above timid to [param swats].y at the boldest.
func get_drive_off_swats(timid_below: float, swats: Vector2i) -> int:
	if is_timid(timid_below):
		return 1
	var bolder := clampf(inverse_lerp(timid_below, 1.0, boldness), 0.0, 1.0) if timid_below < 1.0 else 1.0
	return roundi(lerpf(swats.x, swats.y, bolder))
