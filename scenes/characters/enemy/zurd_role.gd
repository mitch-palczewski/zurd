class_name ZurdRole
extends Resource

## One kind of Zurd (Zurd Core Design Doc §12.2): where it spends its calm time, what angers it
## most, how it hunts when Hostile, and the ranges its temperament is rolled from (§12.3). The
## [ZurdDirector] spawns Zurds by role; the roles live in data/zurd_roles/.

enum Home {
	## Its own spot around the ship, in the players' view (Shadow). Hostile, it goes after the loose
	## objects nearest the ship, then sculptures over the size limit.
	SHIP,
	## Its pack, which roams the map and vacuums up loose objects (Grazer). Hostile, it clears the
	## ground around its pack, sculptures included, then strays nearby.
	PACK,
	## A landmark or a settled sculpture, which it circles and watches (Sentinel). Hostile, it eats
	## its sculpture.
	WATCH,
}

@export var role_name: String = "Zurd"
@export var home: Home = Home.PACK
## Faint placeholder tint over the body while Passive, so the roles can be told apart in playtests.
@export var tint: Color = Color(1.0, 1.0, 1.0, 0.0)

@export_group("Sight")
## Radius of its sight cylinder (Zurd Core Design Doc §4).
@export var sight_radius: float = 150.0

@export_group("Anger")
## Mess (loose objects, and sculptures when they count) it tolerates in view: noticing more adds
## anger.
@export var tolerated_in_view: int = 3
## Whether each sculpture in view counts as one item of mess, like a loose object.
@export var sculptures_count_as_mess: bool = false
## Added per item of mess it notices beyond what it tolerates.
@export var mess_anger: float = 0.1
## Added per launch it sees while it sees more mess than it tolerates. Every launch it sees holds
## its anger where it is.
@export var launch_anger: float = 0.0
## Added per part the sculpture it watches gains beyond the sculpture size limit.
@export var sculpture_anger: float = 0.0
## Added per swat or ram that doesn't drive it off (a timid Zurd flees at the first).
@export var attack_anger: float = 0.2

@export_group("Getting Around")
## Speed it heads home at when it's far away; 0 keeps its wander speed.
@export var travel_speed: float = 0.0
## How far around its home it roams: a Shadow's spot, a Sentinel's landmark without a sculpture.
## A Grazer roams around its pack's middle, as far as the director's pack_radius.
@export var home_radius: float = 40.0

@export_group("Shadow")
## How far from the ship its spot is (min, max): the boldest nearest.
@export var ship_distance: Vector2 = Vector2(150.0, 300.0)
## Its spot's height above (or below) the ship (min, max).
@export var ship_height: Vector2 = Vector2(-5.0, 15.0)
## The Shadows' spots spread over this angle to each side of the ship's heading (degrees), so they
## stay in the players' view.
@export_range(0.0, 90.0, 1.0) var view_arc: float = 50.0

@export_group("Temperament")
## Each trait is rolled between min and max (ZurdTemperament).
@export var temper: Vector2 = Vector2(0.6, 1.4)
@export var patience: Vector2 = Vector2(0.6, 1.4)
@export var greed: Vector2 = Vector2(0.3, 0.7)
@export var boldness: Vector2 = Vector2(0.0, 1.0)
@export var curiosity: Vector2 = Vector2(0.6, 1.6)
@export var pace: Vector2 = Vector2(0.9, 1.1)
## Its size at spawn, before it grows by eating (Zurd Core Design Doc §12.4).
@export var body: Vector2 = Vector2(0.9, 1.1)
