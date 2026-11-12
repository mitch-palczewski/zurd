extends "res://tests/test_case.gd"

## ZurdAnger: the Zurds' shared anger (Zurd Core Design Doc §3). It rises when objects are added
## past the limits or Zurds are attacked, and falls once the players stop.


func test_starts_calm_and_stays_calm_without_provocation() -> void:
	var anger := ZurdAnger.new()
	anger.update(60.0)
	check_equal(anger.value, 0.0, "with nothing happening, anger stays 0")
	anger.on_launch(anger.tolerated_mess)
	anger.on_sculpture_grew(1, anger.tolerated_sculpture_size)
	check_equal(anger.value, 0.0, "launching up to the mess limit, and sculptures up to the size limit, add nothing")


func test_launches_over_the_mess_limit_add_anger() -> void:
	var anger := ZurdAnger.new()
	anger.on_launch(anger.tolerated_mess + 1)
	check_near(anger.value, anger.mess_anger, 0.0001, "each launch while over the limit adds mess_anger")
	anger.update(1.0)
	anger.on_launch(anger.tolerated_mess + 2)
	check_near(anger.value, anger.mess_anger * 2.0, 0.0001, "and the next one adds it again")


func test_a_mess_that_sits_there_lets_anger_fall() -> void:
	var anger := ZurdAnger.new()
	anger.on_launch(anger.tolerated_mess + 5)
	var after_launch := anger.value
	anger.update(anger.calm_delay * 0.5)
	check_equal(anger.value, after_launch, "anger holds right after a provocation")
	anger.update(anger.calm_delay * 0.5 + 1.0)
	check(anger.value < after_launch, "then falls, though the loose objects are still over the limit")
	anger.update(1000.0)
	check_equal(anger.value, 0.0, "down to 0, never below")


func test_anger_falls_at_the_decay_rate() -> void:
	var anger := ZurdAnger.new()
	anger.value = 0.5
	anger.update(anger.calm_delay)
	var start := anger.value
	anger.update(2.0)
	check_near(start - anger.value, anger.decay_rate * 2.0, 0.0001, "anger falls by decay_rate per second")


func test_rushing_adds_anger() -> void:
	var anger := ZurdAnger.new()
	for i in anger.rush_launches:
		anger.on_launch(1)
		anger.update(0.5)
	check_equal(anger.value, 0.0, "up to rush_launches launches in the window add nothing")
	anger.on_launch(1)
	check_near(anger.value, anger.rush_anger, 0.0001, "each launch past the limit adds rush_anger")
	anger.value = 0.0
	anger.update(anger.rush_window + 0.1)
	anger.on_launch(1)
	check_equal(anger.value, 0.0, "launches older than the window no longer count")


func test_only_sculpture_growth_beyond_the_limit_adds_anger() -> void:
	var anger := ZurdAnger.new()
	var limit := anger.tolerated_sculpture_size
	anger.on_sculpture_grew(3, limit + 2)
	check_near(anger.value, anger.sculpture_anger * 2.0, 0.0001, "only the parts beyond the limit count (2 of the 3 added)")
	anger.value = 0.0
	anger.on_sculpture_grew(4, limit + 10)
	check_near(anger.value, anger.sculpture_anger * 4.0, 0.0001, "a sculpture already over the limit: every added part counts")


func test_attacks_on_zurds_add_anger() -> void:
	var anger := ZurdAnger.new()
	anger.on_zurd_attacked()
	check_near(anger.value, anger.attack_anger, 0.0001, "a swat, ram or object hit adds attack_anger")


func test_anger_stays_within_zero_and_one() -> void:
	var anger := ZurdAnger.new()
	for i in 100:
		anger.on_zurd_attacked()
	check_equal(anger.value, 1.0, "anger never goes above 1")


func test_hostile_count_follows_anger() -> void:
	var anger := ZurdAnger.new()
	check_equal(anger.get_hostile_count(3), 0, "anger 0: no Hostile Zurds")
	anger.value = 1.0
	check_equal(anger.get_hostile_count(3), 3, "anger 1: all of them")
	anger.value = 0.34
	check_equal(anger.get_hostile_count(3), 1, "a third of the anger: one of three")
	check_equal(anger.get_hostile_count(0), 0, "no Zurds: none")
