extends "res://tests/test_case.gd"

## ZurdAnger: one Zurd's own anger (Zurd Core Design Doc §12.1). Noticing mess past what it
## tolerates, launches it sees while it does, its sculpture growing past the limit and attacks raise
## it, scaled by its temper; being fed lowers it a little (§12.7). Every launch it sees holds it; it
## falls after a quiet spell, scaled by its patience. The hostile and calm thresholds keep the Zurd
## from flickering between its states.


func test_starts_calm_and_stays_calm_without_provocation() -> void:
	var anger := ZurdAnger.new()
	anger.sculpture_anger = 0.1
	anger.launch_anger = 0.1
	anger.update(60.0)
	check_equal(anger.value, 0.0, "with nothing happening, anger stays 0")
	anger.on_noticed(anger.tolerated_in_view, anger.tolerated_in_view)
	anger.on_launch_seen(anger.tolerated_in_view)
	anger.on_sculpture_grew(1, 15, 15)
	check_equal(anger.value, 0.0, "mess up to the tolerance, launches seen while it isn't passed, and a sculpture up to the limit add nothing")


func test_noticing_mess_past_the_tolerance_adds_anger() -> void:
	var anger := ZurdAnger.new()
	anger.on_noticed(1, anger.tolerated_in_view + 1)
	check_near(anger.value, anger.mess_anger, 0.0001, "the first item noticed past the tolerance adds mess_anger")
	anger.value = 0.0
	anger.on_noticed(10, 10)
	check_near(anger.value, anger.mess_anger * (10 - anger.tolerated_in_view), 0.0001,
			"wandering into an old pile counts only the items past the tolerance")


func test_temper_scales_what_it_gains() -> void:
	var placid := ZurdAnger.new()
	placid.temper = 0.5
	var hot := ZurdAnger.new()
	hot.temper = 1.5
	placid.on_attacked()
	hot.on_attacked()
	check_near(placid.value, placid.attack_anger * 0.5, 0.0001, "a placid Zurd gains less")
	check_near(hot.value, hot.attack_anger * 1.5, 0.0001, "a hot-tempered one more")


func test_launches_seen_hold_the_anger_and_add_past_the_tolerance() -> void:
	var anger := ZurdAnger.new()
	anger.launch_anger = 0.1
	anger.value = 0.5
	for i in 20:
		anger.on_launch_seen(1)
		anger.update(anger.calm_delay * 0.5)
	check_equal(anger.value, 0.5, "launches seen while the mess is tolerated hold the anger, however long they go on")
	anger.on_launch_seen(anger.tolerated_in_view + 1)
	check_near(anger.value, 0.6, 0.0001, "a launch seen while there's too much mess adds launch_anger")
	anger.update(anger.calm_delay + 1.0)
	check(anger.value < 0.6, "once the launches stop, it falls")


func test_anger_falls_after_a_quiet_spell_scaled_by_patience() -> void:
	var anger := ZurdAnger.new()
	anger.value = 0.9
	anger.update(anger.calm_delay * 0.5)
	check_equal(anger.value, 0.9, "it holds for calm_delay")
	anger.update(anger.calm_delay * 0.5)
	var start := anger.value
	anger.update(2.0)
	check_near(start - anger.value, anger.decay_rate * 2.0, 0.0001, "then falls by decay_rate per second")
	var patient := ZurdAnger.new()
	patient.patience = 2.0
	patient.value = 0.9
	patient.update(patient.calm_delay)
	var patient_start := patient.value
	patient.update(2.0)
	check_near(patient_start - patient.value, patient.decay_rate * 2.0 * 2.0, 0.0001, "a patient Zurd calms faster (patience times)")
	anger.update(1000.0)
	check_equal(anger.value, 0.0, "down to 0, never below")


func test_only_sculpture_growth_past_the_limit_adds_anger() -> void:
	var anger := ZurdAnger.new()
	anger.sculpture_anger = 0.05
	anger.on_sculpture_grew(3, 17, 15)
	check_near(anger.value, 0.1, 0.0001, "only the parts past the limit count (2 of the 3 added)")
	anger.value = 0.0
	anger.on_sculpture_grew(4, 30, 15)
	check_near(anger.value, 0.2, 0.0001, "a sculpture already past the limit: every added part counts")


func test_being_fed_calms_it_a_little() -> void:
	var anger := ZurdAnger.new()
	anger.temper = 2.0
	anger.value = 0.5
	anger.on_fed()
	check_near(anger.value, 0.5 - anger.fed_calm, 0.0001, "each part of a thrown object it eats takes fed_calm off, whatever its temper")
	anger.value = anger.fed_calm * 0.5
	anger.on_fed()
	check_equal(anger.value, 0.0, "but never below 0")


func test_anger_stays_within_zero_and_one() -> void:
	var anger := ZurdAnger.new()
	for i in 100:
		anger.on_attacked()
	check_equal(anger.value, 1.0, "anger never goes above 1")
	anger.calm_down()
	check_equal(anger.value, 0.0, "calm_down calms it at once")


func test_thresholds_keep_it_from_flickering() -> void:
	var anger := ZurdAnger.new()
	anger.value = anger.hostile_threshold - 0.01
	check(not anger.should_be_hostile(false), "a calm Zurd stays calm just under the hostile threshold")
	anger.value = anger.hostile_threshold
	check(anger.should_be_hostile(false), "and turns Hostile at it")
	anger.value = (anger.hostile_threshold + anger.calm_threshold) * 0.5
	check(anger.should_be_hostile(true), "a Hostile Zurd stays Hostile between the two thresholds")
	check(not anger.should_be_hostile(false), "where a calm one stays calm")
	anger.value = anger.calm_threshold - 0.01
	check(not anger.should_be_hostile(true), "below the calm threshold a Hostile Zurd calms")


func test_configure_takes_the_role_and_temperament() -> void:
	var role := ZurdRole.new()
	role.tolerated_in_view = 7
	role.mess_anger = 0.11
	role.launch_anger = 0.12
	role.sculpture_anger = 0.13
	role.attack_anger = 0.14
	var temperament := ZurdTemperament.new()
	temperament.temper = 1.3
	temperament.patience = 0.7
	var anger := ZurdAnger.new()
	anger.configure(role, temperament)
	check(anger.tolerated_in_view == 7 and anger.mess_anger == 0.11 and anger.launch_anger == 0.12
			and anger.sculpture_anger == 0.13 and anger.attack_anger == 0.14, "the amounts come from the role")
	check(anger.temper == 1.3 and anger.patience == 0.7, "temper and patience from the temperament")
