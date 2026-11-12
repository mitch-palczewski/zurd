extends SceneTree

## Runs every test in tests/ and exits with 1 when anything fails (tests/README.md, hardening plan
## step 1). In game mode, so it's safe while the editor is open:
##     <Godot console exe> --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
## Arguments after "--" run only the test files whose path contains one of them ("-- unit",
## "-- test_object_parts").
##
## This script names no project classes: it compiles before the autoloads exist, and a project class
## compiled now would stay broken for the whole run. Test files are loaded later, by path. It prints
## its report instead of using push_warning/push_error: the output is the report.

const TESTS_DIR := "res://tests/"
## Test folders run in this order; any other folder runs after them.
const FOLDER_ORDER: Array[String] = ["unit", "scene"]
## Files a run must leave untouched: the player's settings, and data a test could save by mistake.
## A change fails the run, and the file as it was before the run is kept in the OS temp folder.
const GUARDED_FILES: Array[String] = [
	"user://controller_config.json",
	"user://lidar_config.json",
	"res://data/object_catalog.tres",
]
## The [Logger] error type of warnings. Every other type (errors, script errors, shader errors)
## fails the test that logged it unless the test allowed it.
const WARNING_TYPE := 1
## Real seconds a test may take, whatever its frame count: with --fixed-fps, frames can run much
## faster than real time, while loading on other threads runs in real time.
const MIN_REAL_SECONDS_PER_STEP := 20.0
## Real seconds a whole run may take before it stops itself and fails. (Not --quit-after: it counts
## frames, and without a world loaded, frames run tens of thousands a second.)
const MAX_RUN_SECONDS := 600.0


## Collects every error and warning Godot logs. Godot may call it from any thread.
class LogCapture extends Logger:
	var _entries: Array[Dictionary] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := code if rationale.is_empty() else "%s (%s)" % [rationale, code]
		_mutex.lock()
		_entries.append({"type": error_type, "text": text, "file": file, "line": line, "function": function})
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var result := _entries.size()
		_mutex.unlock()
		return result

	## Everything logged from entry [param index] on.
	func since(index: int) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		_mutex.lock()
		result.assign(_entries.slice(index))
		_mutex.unlock()
		return result


var _log := LogCapture.new()
var _started_msec := 0
var _temp_dir := ""
var _filters := PackedStringArray()
## What each guarded file looked like before the run: path -> {"exists", "md5", "bytes"}.
var _guard: Dictionary = {}
var _finished := false

var _tests_run := 0
var _tests_failed := 0
var _checks_passed := 0
var _checks_failed := 0
var _failures := PackedStringArray()

# The test being run.
var _current := ""
var _current_checks := 0
var _current_failed := false
var _current_log_start := 0
var _allowed_errors := PackedStringArray()


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	OS.add_logger(_log)
	_filters = OS.get_cmdline_user_args()
	_temp_dir = OS.get_temp_dir().path_join("zurd_tests")
	_remove_temp_dir()
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	_snapshot_guarded_files()
	# The autoloads exist but aren't ready yet, so Controllers loads its config from here, never
	# from the real file.
	var controllers := root.get_node_or_null(^"Controllers")
	if controllers:
		controllers.set(&"config_path", get_temp_path("controller_config.json"))
	if controllers == null or controllers.get(&"config_path") != get_temp_path("controller_config.json"):
		print("RESULT: FAIL (couldn't point Controllers at a temporary config, so no test ran; the real one stays untouched)")
		_finished = true
		quit(1)
		return
	_run()


## Runs every frame, even when a test's coroutine has stopped, so a stuck run always ends.
func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() - _started_msec > MAX_RUN_SECONDS * 1000.0:
		print("RESULT: FAIL (the run took longer than %d s, so it was stopped)" % MAX_RUN_SECONDS)
		_finished = true
		_remove_temp_dir()
		quit(1)
	return false


func _finalize() -> void:
	if not _finished:
		print("RESULT: FAIL (the run stopped before it finished)")
		_remove_temp_dir()
		quit(1)
	OS.remove_logger(_log)


# ==============================================================================
# CALLED BY TEST FILES (through test_case.gd)
# ==============================================================================

func record_check(passed: bool, what: String) -> void:
	_current_checks += 1
	if passed:
		_checks_passed += 1
	else:
		_checks_failed += 1
		_record_failure(what)


## Lets the current test log errors containing [param text] without failing.
func allow_error(text: String) -> void:
	_allowed_errors.append(text)


## True when the current test logged a warning or error containing [param text].
func was_logged(text: String) -> bool:
	for entry in _log.since(_current_log_start):
		if String(entry["text"]).contains(text):
			return true
	return false


## A path for [param file_name] in this run's temporary folder (in the OS temp folder, removed after
## the run).
func get_temp_path(file_name: String) -> String:
	return _temp_dir.path_join(file_name)


# ==============================================================================
# RUNNING
# ==============================================================================

func _run() -> void:
	await process_frame
	var started := Time.get_ticks_msec()
	var files := _find_test_files()
	if files.is_empty():
		_failures.append("No test files match %s." % [_filters])
	else:
		print("Running %d test files%s." % [files.size(), "" if _filters.is_empty() else " matching %s" % [_filters]])
	for path in files:
		await _run_file(path)
	_check_guarded_files()
	_remove_temp_dir()
	_print_summary((Time.get_ticks_msec() - started) / 1000.0)
	_finished = true
	quit(0 if _failures.is_empty() else 1)


func _run_file(path: String) -> void:
	var label := path.trim_prefix(TESTS_DIR)
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_begin(label, "(loading)")
		_record_failure("the file can't be loaded; see the script error above.")
		_end(false)
		return
	var test: Node = script.new()
	if not test.has_method(&"check"):
		_begin(label, "(loading)")
		_record_failure("it doesn't extend res://tests/test_case.gd.")
		_end(false)
		test.free()
		return
	test.set(&"_runner", self)
	test.name = label.get_file().get_basename()
	root.add_child(test)
	await process_frame

	var methods := _get_test_methods(script)
	if methods.is_empty():
		_begin(label, "(loading)")
		_record_failure("it has no test_ methods.")
		_end(false)

	var file_ready := true
	if test.has_method(&"before_all"):
		_begin(label, "before_all")
		file_ready = await _run_step(test, &"before_all")
		_end(false)
	for method in methods:
		_begin(label, method)
		if not file_ready:
			_record_failure("skipped: before_all didn't finish.")
		else:
			var prepared := true
			if test.has_method(&"before_each"):
				prepared = await _run_step(test, &"before_each")
			if prepared:
				await _run_step(test, method)
			if test.has_method(&"after_each"):
				await _run_step(test, &"after_each")
		await _run_step(test, &"_cleanup")
		_end(true)
	if file_ready and test.has_method(&"after_all"):
		_begin(label, "after_all")
		await _run_step(test, &"after_all")
		await _run_step(test, &"_cleanup")
		_end(false)

	test.queue_free()
	await process_frame


## Calls [param method] on [param test] and waits for it to finish: up to the test's frame_limit, and
## at least [constant MIN_REAL_SECONDS_PER_STEP]. Returns false when it didn't: it hung, or a script
## error stopped it partway.
func _run_step(test: Node, method: StringName) -> bool:
	var state := {"done": false}
	var log_start := _log.count()
	_call_and_flag(test, method, state)
	var limit: int = test.get(&"frame_limit")
	var deadline := Time.get_ticks_msec() + int(MIN_REAL_SECONDS_PER_STEP * 1000.0)
	var frames := 0
	while not state["done"]:
		var error := _find_script_error_in(method, log_start)
		if not error.is_empty():
			_record_failure("%s stopped at a script error: %s" % [method, error])
			return false
		if frames >= limit and Time.get_ticks_msec() >= deadline:
			_record_failure("%s didn't finish (gave up after %d frames and %.0f real seconds)." % [method, frames, MIN_REAL_SECONDS_PER_STEP])
			return false
		await process_frame
		frames += 1
	return true


func _call_and_flag(test: Node, method: StringName, state: Dictionary) -> void:
	await test.call(method)
	state["done"] = true


## The text of a script error raised in the function [param method] itself since [param log_start]:
## a coroutine stops at a script error, so the step will never finish.
func _find_script_error_in(method: StringName, log_start: int) -> String:
	for entry in _log.since(log_start):
		if entry["type"] != WARNING_TYPE and entry["function"] == String(method) and String(entry["file"]).begins_with(TESTS_DIR):
			return "%s (%s:%d)" % [entry["text"], String(entry["file"]).get_file(), entry["line"]]
	return ""


func _begin(label: String, method: String) -> void:
	_current = "%s > %s" % [label, method]
	_current_checks = 0
	_current_failed = false
	_current_log_start = _log.count()
	_allowed_errors.clear()


## Ends the current test or hook: fails it for errors it didn't allow and, for a test, for making no
## checks, then prints its result.
func _end(is_test: bool) -> void:
	for entry in _log.since(_current_log_start):
		if entry["type"] == WARNING_TYPE or _is_allowed(entry["text"]):
			continue
		_record_failure("unexpected error: %s" % entry["text"])
	if is_test and _current_checks == 0 and not _current_failed:
		_record_failure("it made no checks.")
	if not is_test and not _current_failed:
		return
	if is_test:
		_tests_run += 1
		if _current_failed:
			_tests_failed += 1
	print("%s %s (%d checks)" % ["FAIL" if _current_failed else "PASS", _current, _current_checks])


func _is_allowed(text: String) -> bool:
	for allowed in _allowed_errors:
		if text.contains(allowed):
			return true
	return false


func _record_failure(message: String) -> void:
	_current_failed = true
	var line := "  %s: %s" % [_current, message]
	print(line)
	_failures.append(line)


func _get_test_methods(script: Script) -> Array[StringName]:
	var methods: Array[StringName] = []
	for info in script.get_script_method_list():
		var method := StringName(info["name"])
		if String(method).begins_with("test_") and not methods.has(method):
			methods.append(method)
	return methods


# ==============================================================================
# FINDING TESTS
# ==============================================================================

func _find_test_files() -> Array[String]:
	var found: Array[String] = []
	for folder in DirAccess.get_directories_at(TESTS_DIR):
		_collect_test_files(TESTS_DIR.path_join(folder), found)
	found.sort_custom(_runs_before)
	if _filters.is_empty():
		return found
	var selected: Array[String] = []
	for path in found:
		for filter in _filters:
			if path.trim_prefix(TESTS_DIR).contains(filter):
				selected.append(path)
				break
	return selected


func _collect_test_files(dir: String, found: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.get_extension() == "gd":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect_test_files(dir.path_join(sub), found)


func _runs_before(a: String, b: String) -> bool:
	var rank_a := _folder_rank(a)
	var rank_b := _folder_rank(b)
	if rank_a != rank_b:
		return rank_a < rank_b
	return a.naturalnocasecmp_to(b) < 0


func _folder_rank(path: String) -> int:
	var folder := path.trim_prefix(TESTS_DIR).get_slice("/", 0)
	var rank := FOLDER_ORDER.find(folder)
	return rank if rank >= 0 else FOLDER_ORDER.size()


# ==============================================================================
# GUARDED FILES AND TEMPORARY FILES
# ==============================================================================

func _snapshot_guarded_files() -> void:
	for path in GUARDED_FILES:
		var exists := FileAccess.file_exists(path)
		_guard[path] = {
			"exists": exists,
			"md5": FileAccess.get_md5(path) if exists else "",
			"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray(),
		}


func _check_guarded_files() -> void:
	_current = "guarded files"
	for path in GUARDED_FILES:
		var before: Dictionary = _guard[path]
		var exists := FileAccess.file_exists(path)
		var md5 := FileAccess.get_md5(path) if exists else ""
		if exists == before["exists"] and md5 == before["md5"]:
			continue
		var message := "%s changed during the run (a test wrote to it, or it was saved meanwhile)." % path
		if before["exists"]:
			message += " The file as it was before the run is at %s." % _back_up(path, before["bytes"])
		_record_failure(message)


## Writes [param bytes], a guarded file's content from before the run, next to the run's temporary
## folder, where the run doesn't remove it. Returns where.
func _back_up(path: String, bytes: PackedByteArray) -> String:
	var dir := OS.get_temp_dir().path_join("zurd_tests_backup")
	DirAccess.make_dir_recursive_absolute(dir)
	var backup := dir.path_join("%s_%d.%s" % [path.get_file().get_basename(), Time.get_unix_time_from_system(), path.get_extension()])
	var file := FileAccess.open(backup, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
	return backup


func _remove_temp_dir() -> void:
	if _temp_dir.is_empty() or not DirAccess.dir_exists_absolute(_temp_dir):
		return
	for file in DirAccess.get_files_at(_temp_dir):
		DirAccess.remove_absolute(_temp_dir.path_join(file))
	DirAccess.remove_absolute(_temp_dir)


func _print_summary(seconds: float) -> void:
	print("")
	print("%d tests, %d checks: %d tests failed, %d checks failed (%.1f s)." % [_tests_run, _checks_passed + _checks_failed, _tests_failed, _checks_failed, seconds])
	if not _failures.is_empty():
		print("Failures:")
		for line in _failures:
			print(line)
	print("RESULT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
