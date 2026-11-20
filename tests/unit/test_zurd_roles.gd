extends "res://tests/test_case.gd"

## The Zurds' roles and temperaments (Zurd Core Design Doc §12.2, §12.3): what each role is angered
## by most, temperaments rolled within their role's ranges, swats by boldness, the Grazers' patches
## spread over the map, and the Shadows' spots in the players' view.

const SHADOW := preload("res://data/zurd_roles/shadow.tres")
const GRAZER := preload("res://data/zurd_roles/grazer.tres")
const SENTINEL := preload("res://data/zurd_roles/sentinel.tres")


func test_each_role_has_its_home_and_its_main_anger() -> void:
	check(SHADOW.home == ZurdRole.Home.SHIP and GRAZER.home == ZurdRole.Home.PATCH and SENTINEL.home == ZurdRole.Home.WATCH,
			"Shadows home on the ship, Grazers on a patch, Sentinels on what they watch")
	check(SHADOW.launch_anger > GRAZER.launch_anger and SHADOW.launch_anger > SENTINEL.launch_anger,
			"Shadows are the ones launches near them anger most")
	check(GRAZER.mess_anger > SHADOW.mess_anger and GRAZER.mess_anger > SENTINEL.mess_anger,
			"Grazers are the ones mess in their patch angers most")
	check(GRAZER.sculptures_count_as_mess and not SHADOW.sculptures_count_as_mess and not SENTINEL.sculptures_count_as_mess,
			"only Grazers count a sculpture like a loose object")
	check(SENTINEL.sculpture_anger > 0.0 and SHADOW.sculpture_anger == 0.0 and GRAZER.sculpture_anger == 0.0,
			"only Sentinels are angered by the sculpture they watch growing")


func test_temperaments_roll_within_the_role_ranges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for role: ZurdRole in [SHADOW, GRAZER, SENTINEL]:
		var inside := true
		for i in 200:
			var temperament := ZurdTemperament.roll(role, rng)
			inside = inside and _within(temperament.temper, role.temper) and _within(temperament.patience, role.patience)
			inside = inside and _within(temperament.greed, role.greed) and _within(temperament.boldness, role.boldness)
			inside = inside and _within(temperament.curiosity, role.curiosity) and _within(temperament.pace, role.pace)
		check(inside, "every %s trait rolls within its range" % role.role_name)


func test_swats_to_drive_off_follow_boldness() -> void:
	var timid_below := 0.3
	var swats := Vector2i(2, 4)
	var temperament := ZurdTemperament.new()
	temperament.boldness = 0.1
	check_equal(temperament.get_drive_off_swats(timid_below, swats), 1, "a timid Zurd flees after one swat")
	temperament.boldness = timid_below
	check_equal(temperament.get_drive_off_swats(timid_below, swats), swats.x, "just past timid it takes the fewest of the bold swats")
	temperament.boldness = 1.0
	check_equal(temperament.get_drive_off_swats(timid_below, swats), swats.y, "the boldest takes the most")
	var previous := 0
	var rising := true
	for step in 21:
		temperament.boldness = step / 20.0
		var needed := temperament.get_drive_off_swats(timid_below, swats)
		rising = rising and needed >= previous
		previous = needed
	check(rising, "the bolder, the more swats it takes")


func test_patches_spread_evenly_over_the_disc() -> void:
	var center := Vector3(100.0, 50.0, -200.0)
	var radius := 1500.0
	var count := 15
	var patches := ZurdDirector.get_patch_centers(center, radius, count)
	check_equal(patches.size(), count, "one patch per Grazer")
	var inside := true
	var farthest := 0.0
	var closest := INF
	for i in patches.size():
		var distance := Vector2(patches[i].x - center.x, patches[i].z - center.z).length()
		inside = inside and distance <= radius and is_equal_approx(patches[i].y, center.y)
		farthest = maxf(farthest, distance)
		for j in range(i + 1, patches.size()):
			closest = minf(closest, patches[i].distance_to(patches[j]))
	check(inside, "every patch is inside the disc, at its height")
	check(farthest >= radius * 0.8, "they reach out across the disc (%.0f m of %.0f)" % [farthest, radius])
	var share := radius / sqrt(count)
	check(closest >= share * 0.5, "and none crowd each other (closest %.0f m, a patch's radius is %.0f m)" % [closest, share])


func test_shadow_spots_stay_in_view_and_off_the_ships_path() -> void:
	for count: int in [1, 2, 3, 5]:
		var arc := 50.0
		var bearings := ZurdDirector.get_shadow_bearings(count, arc)
		# Spread evenly, then shifted a quarter of the spacing, so none is closer than that to dead ahead.
		var quarter_step := 2.0 * arc / count * 0.25
		var in_view := true
		var off_path := true
		for bearing in bearings:
			in_view = in_view and absf(rad_to_deg(bearing)) <= arc + 0.001
			off_path = off_path and absf(rad_to_deg(bearing)) >= quarter_step - 0.01
		check(bearings.size() == count and in_view, "%d Shadows: every spot is within the view arc" % count)
		check(off_path, "%d Shadows: none sits dead ahead, in the ship's path" % count)


func _within(value: float, range_: Vector2) -> bool:
	return value >= range_.x - 0.000001 and value <= range_.y + 0.000001
