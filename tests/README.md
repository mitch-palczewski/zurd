# Tests

Automated checks of the game's rules: sculpture masses, the ship's flight, launching, the object
catalog, controllers, loading and the project's files. They run headless in about half a minute.
Run them before committing code changes; a failure means a rule changed, on purpose or not.

## Running

From the project folder, with the Godot 4.7.2 .NET **console** executable (it sits next to the
editor exe in the Godot download; it isn't on PATH):

```bash
"<Godot>/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd > "$TEMP/zurd_tests.txt" 2>&1; echo "exit $?"
```

- It runs in game mode, so it's safe while the editor is open.
- `--fixed-fps 60` runs game time as fast as the computer can, so a minute of play takes a few
  seconds.
- The run prints `PASS` or `FAIL` for each test, the failed checks with what was expected, and a
  summary ending in `RESULT: PASS` or `RESULT: FAIL`. The exit code is 0 when everything passed, 1
  otherwise.
- To run some tests only, add their path after `--`: `-- unit` (a folder), `-- test_object_parts`
  (a file), or several.
- Godot's own warnings and errors appear in the output too. Some tests trigger them on purpose,
  for example a scene that fails to load. Those tests declare the errors they expect, so an error
  only fails a test when it wasn't expected.
- A run stops itself after 10 minutes.

## Your files are safe

The tests never read or write `user://` files. Before anything loads, the runner points the
Controllers autoload at a temporary file in the OS temp folder, and deletes that folder afterwards.
To make sure, the runner fingerprints `user://controller_config.json`, `user://lidar_config.json`
and `data/object_catalog.tres` before and after the run. If one changed, the run fails, and the
file as it was before is kept in the OS temp folder under `zurd_tests_backup/`.

## What's covered

| Folder | Runs | Covers |
| --- | --- | --- |
| `unit/` | without the game world | object parts and sizes, break-off geometry, the object catalog (and that every rigid scene is in it and keeps the collider contract), the object tracker, controller profiles and the Controllers autoload, scene loading, the main menu, and that every scene and resource loads |
| `scene/` | in `zurd_world.tscn` | sculpture masses (fuse, combine, merge, growth break-off, bites, break-off, clouds), the ship's flight, launching and the launch station |

Not covered, on purpose:

- **Zurd behaviour.** The Zurd scripts are temporary. Scene tests remove the hand-placed Zurd, and
  bites come from `EventBus.eat_requested`.
- **Visuals and effects** (shaders, SculptureFx, the preview's animation).
- **The lidar C# code.** It needs the .NET build. It was tested with scratch C# harnesses.
- **The GLB importer.** It only runs in the editor. To check it by hand:
  1. Copy the project to a scratch folder. The copy shares the project's name, and so its
     `user://` folder: first add `config/use_custom_user_dir=true` and
     `config/custom_user_dir_name="zurd_test_copy"` under `[application]` in the copy's
     `project.godot`.
  2. Put test models in each `assets/models/` folder of the copy.
  3. Run `<Godot> --headless --path <copy> --import`.
  4. Inspect the scenes, meshes and materials it made.

## Adding a test

A test file is `tests/unit/test_<topic>.gd` or `tests/scene/test_<topic>.gd`, and starts with:

```gdscript
extends "res://tests/test_case.gd"
```

It extends the base class by path, so a new file runs without the editor registering a class.
Every method named `test_...` is a test, run in order. A test can `await`. Optional hooks:
`before_all`, `after_all`, `before_each`, `after_each`. A test fails when:

- a check fails;
- it logs an error it didn't allow;
- it makes no checks;
- it doesn't finish (stuck for 2 minutes of game time and 20 real seconds).

`test_case.gd` has the tools:

- **Checks:** `check(condition, what)`, `check_equal(actual, expected, what)`,
  `check_near(actual, expected, tolerance, what)`. `what` says the rule in plain words; it's what a
  failure prints.
- **Waiting:** `wait_frames`, `wait_physics`, `wait_seconds` (game time), and
  `wait_until(condition, seconds)`, which also allows that long in real time, for loading on other
  threads.
- **Signals:** `watch(signal)` records each emission's arguments; `listen(signal, callable)`
  connects for the rest of the test.
- **Input:** `tap(action)` presses an action for one frame; `hold` and `release` keep it down.
- **The world:** `load_world(with_terrain)` loads the game world for the test, without its Zurd,
  and frees it after. `get_ship`, `get_mass_manager`, `spawn_object` and `spawn_beside` place
  objects the way the launcher does.
- **Errors and files:** `allow_error(text)` for code that should report an error, `was_logged(text)`,
  and `temp_path(name)` for files a test writes.

Rules that keep the tests cheap to keep:

- **Test rules, not tuning.** Read expected values from the nodes' exports (`max_forward_speed`,
  `hits_to_fuse`), so changing a number in the Inspector never breaks a test. A test may set an
  export to make a case quick (a low cloud threshold); the world is reloaded for every test.
- **Drive the game through its own entry points:** input actions, EventBus signals, the bodies'
  contact signals, public methods.
- **No exact frame timings.** Use tolerances, and wait until something happens.
- **A flaky test gets fixed or deleted**, never rerun until it passes.
- When a change alters a tested rule on purpose, update the test in the same change.
