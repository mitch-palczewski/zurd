# Plan: Hardening (tests, world split, object budget and session reset, object catalog, terrain, sandbox)

## Context

The codebase review of 2026-11-04 (the "zurd Codebase Review" Claude doc) found the core systems
solid and the gaps in hardening: no committed tests, nothing that bounds a long exhibit session,
one world scene that holds everything, a hand-kept list of launchable objects, a terrain built on
the main thread after the loading bar fills, and sandbox prototypes the main menu still links to.
This plan covers those six items. The lidar bridge and the Zurd overhaul are separate: they wait
on hardware and on the Zurd design doc.

Already done in the review passes, so not part of this plan: tabs everywhere, API typos fixed,
load-failure recovery, named collision layers, the folder-based importer as the project-wide
default, the loading screen as a `CanvasLayer`, sandbox excluded from exports, UIDs on the
hand-written scenes, unused files removed.

### Decisions that shape this plan

- No wrapping world. Teleportation, if it comes, covers a small part of the map.
- The Zurd scripts are temporary. Tests must not pin Zurd behaviour; they cover only the
  sculpture system's side of eating (`EventBus.eat_requested` → `MassManager`).
- One hand-placed Zurd while the sculpture system is tested; the spawner stays out.
- The session layer (HUD, attract mode) comes later. Build so it fits: one session node owns
  resets and the budget, and the HUD will listen to the EventBus only.

### Measured (2026-11-04, headless, Godot 4.7.2)

| Step | Time |
| --- | --- |
| Background load of `zurd_world.tscn` (inside the progress bar) | 43 ms |
| `instantiate()` | 3 ms |
| `add_child` → `Terrain._ready()`, on the main thread after the bar shows 100% | 324 ms |
| … of which noise and heights | ~116 ms |
| … building the mesh | ~73 ms |
| … creating the trimesh collision shape | ~62 ms |
| … assigning mesh and collider to the renderer and physics (the remainder) | ~75 ms |

Baked sizes, compressed binary: mesh 751 KB, collision shape 710 KB. The raw heights are 128 KB.

## Order

1. **Tests.** Everything after this is checked by them.
2. **Split `base_world.tscn`.** Moved ahead of the budget (third on the original list) so the
   session node and the actor containers are built once, in their final place. The tests from
   step 1 guard the scene surgery.
3. **Object budget and session reset.**
4. **Object catalog.**
5. **Terrain bake.**
6. **Sandbox removal**, when the 1000 × 1000 map idea is done. Independent of the rest.

Each step is its own commit (or a few) and leaves the game playable.

**Status (2026-11-11):** step 4 was built first and is done (commit `e3ed361`; root-model
cleanup in `a5c7b6d`); only an Inspector check in the editor is left for Mitch. Step 1 is revised
and approved (2026-11-11). Steps 2, 3 and 5 are not started; step 6 waits on its trigger. The
object-colliders experiment (`2026-11-11-object-colliders-plan.md`) runs after step 1.

## 1. Tests

*Revised and approved 2026-11-11* for the object catalog, convex-hull colliders and Controllers,
with Mitch's answers (Decisions below).

### Why, and what it costs

The sculpture system has many rules that depend on each other (fuse, combine, merge, grow and
knock off, bite, break off, cloud), and every build so far was checked by a scratch harness
that was thrown away afterwards: the catalog build alone ran 63 checks that no longer exist.
Committed tests keep those checks, so a later change (step 2's scene surgery, step 3's
despawning, the Zurd overhaul, a new model) that breaks an old rule fails a command instead of
surfacing in a playtest.

Mitch doesn't want to maintain tests. So they're built to need little upkeep, and Claude does
the upkeep:

- **Tests check behaviour, not tuning.** Expected values are read from the nodes' exports
  (`max_speed`, `preview_hide_delay`, `hits_to_fuse`, ...), so changing a number in the
  Inspector never breaks a test. A test fails only when a rule from a design doc changes.
- **Nothing temporary or visual is tested:** no Zurd behaviour, no shaders or effects, no
  screenshots, no exact frame timings (physics checks use tolerances).
- **Claude runs the suite before every code commit**, and when a change alters a tested rule on
  purpose, updates the test in the same change. A new feature's plan lists its new checks, which
  replace the throwaway harness. This goes in `CLAUDE.md` (Workflow).
- **A flaky test gets fixed or deleted**, never re-run until it passes.

### Decisions (2026-11-11)

- Include every test that guards a rule worth keeping (list below), leaving out what is
  temporary, visual, editor-only or C#.
- `test_box_overlap.gd` becomes `test_piece_geometry.gd`. Reviewing the code: growth
  break-off isn't box *or* hull. `get_shape_bounds` turns a box or a hull into a box in the
  shape's space, `get_boxes` places those boxes at a size in global space, and
  `get_overlap` / `get_box_overlap` measure the deepest pair. All three run on every growth, so
  all three are tested; the hull path is the one every real object takes now.
- Ship checks split in two: flight (physics, tolerances) and launch station (catalog stepping,
  preview timing, launching). They set up differently and fail for different reasons.
- Controllers get tests: the per-device binding and the saved config are easy to break and
  hard to notice without the controllers plugged in.
- Under 2 minutes for the whole run.
- **No test may touch Mitch's `user://` files** (below).
- No CI for now. The suite runs locally before each commit; GitHub Actions would need Godot
  and the .NET SDK downloaded on every run and its own upkeep. Worth it only once several people
  commit.
- Delete `scenes/world/toroidal_world.tscn` (unused; only archived plans name it, and they stay
  unedited) and the empty, untracked `test/` folder in this step.

### Design

```
tests/
  run_tests.gd    extends SceneTree. Names no project classes: those would compile before the
                  autoloads exist and stay broken for the run. Guards the user files (below),
                  finds every tests/**/test_*.gd, runs each, prints PASS/FAIL per check and a
                  summary, exits 1 on any failure.
  test_case.gd    extends Node. check(cond, what), check_near(a, b, tolerance, what),
                  wait_frames(n), wait_physics(n), load_world() (instances zurd_world.tscn).
  unit/           tests that need no world
  scene/          tests that run in the real world scene
  README.md       how to run, how to add a test, the manual importer check
```

- Test files say `extends "res://tests/test_case.gd"`, by path rather than class name, so a new
  test runs without the editor first registering its class.
- One command, in game mode (safe while the editor is open):
  `<Godot console exe> --headless --fixed-fps 60 --quit-after 36000 --path . -s res://tests/run_tests.gd`.
  An optional filter after `--` runs one folder or file (`-- unit`, `-- test_object_parts`).
  `--fixed-fps 60` makes simulated minutes run in seconds; `--quit-after` stops a hung run.
  Write the output to a file rather than piping it, or it arrives only at exit.
- Each scene test loads its own fresh world and frees it after, so tests don't leak into each
  other.
- Add `tests/*` to both export presets' `exclude_filter` (`sandbox/*,tests/*`).

### Keeping `user://` untouched

The only game code that writes `user://` is `Controllers` (`controller_config.json`, on every
profile choice, learned layout or reset). The lidar config is C# and not tested here.

- `Controllers` gets `set_config_path(path)`: it switches the file and reloads from it, starting
  from the built-in profiles. `CONFIG_PATH` stays the default, so the game is unchanged.
- First thing in a run, the runner points `Controllers` at a file in the OS temp folder (empty),
  so every test, including the main menu's controller list, saves there and starts from the
  built-in profiles whatever this PC has saved. The temp file is deleted at the end.
- **Guard:** at start and end the runner records whether `user://controller_config.json` and
  `user://lidar_config.json` exist and their contents' hash, plus `data/object_catalog.tres`.
  Any change fails the run with a loud message. Godot still writes its own logs to
  `user://logs/`, as on every play.
- Catalog sync saves the catalog file. Tests sync only catalogs made in memory, which never save
  (sync saves only a catalog loaded from `res://`).

### Tests

**unit/**

| File | Checks |
| --- | --- |
| `test_object_parts.gd` | Sizes in both modes (3 and 4 make ≈ 4.5 or 7), absorb order, `remove_last` restores the exact size, `is_bigger_than`, `of()` builds a record from the shape's scale |
| `test_piece_geometry.gd` | `get_shape_bounds`: a box, a hull's bounding box, other shapes empty. `get_boxes`: scales around the piece's origin, hull by its bounds, skips shapes with no volume. `get_box_overlap`: apart is negative, overlap gives the depth, rotated boxes, touching ≈ 0, parallel edges. `get_overlap`: the deepest pair |
| `test_object_catalog.gd` | Even picks over 10,000 draws, null entries never picked, `size` / `get_entry` over usable entries only, `find_entry` / `get_group` / `group_of`, empty catalog. Sync on an in-memory catalog reports a planted null entry, duplicate, unknown group and a scene that breaks the collider contract. **The real catalog:** `check()` finds no problems and every scene in `scenes/objects/rigid/` is listed (catches a model imported but not synced, or an import that breaks the collider contract) |
| `test_object_tracker.gd` | Register, unregister, freed objects drop out, `is_trackable`, closest and random picks |
| `test_controller_profile.gd` | `to_dict` / `load_dict` round trip; the standard gamepad binds every ship action |
| `test_controllers.gd` | Fake controllers each get a profile, bound to their own device only (two at once); Off unbinds; the choice and a learned layout survive save and reload; reset restores the built-in layout; a broken config file warns and falls back; controller events in Project Settings are dropped |
| `test_scene_changer.gd` | A missing path and a non-scene file both fire `load_failed`, close the loading screen and re-enable the menu; a real async load switches scene |
| `test_main_menu.gd` | The controls label comes from the input map; entries whose scene is missing are skipped; a fake controller shows in the controller list and picking a profile applies it |
| `test_project_files.gd` | Every `.tscn` and `.tres` under `scenes/` and `data/` loads with no missing dependency (C# lidar scenes skipped); the input actions the code reads exist |

**scene/**

| File | Checks |
| --- | --- |
| `test_sculpture.gd` | Port the combining build's checks (`archive/2026-11-04-combining-objects-plan.md`, Verification): fusing, combining (loose, fused, after a merge), growth break-off, bites (loose, fused, through `eat_requested`), break-off keeps parts, cloud counting by parts, same-batch follow. Plus: `catalog_group` on the piece while fused and on the new body after break-off |
| `test_ship_flight.gd` | Port the ship-controls build's checks (`archive/2026-11-01-ship-controls-plan.md`, Verification): top speed, coast to hover, turn rate, hover drift bounds, ground clearance, lowest altitude and ceiling |
| `test_launch_station.gd` | Steps and wraps through the catalog in list order; preview shows on the first press and hides `preview_hide_delay` after the last, with `launch_selection_changed` sending the scene then null; Launch fires the selected object while shown, random ones after; cooldown; side offset; launch speeds; each launched object carries `catalog_group`, is registered with `ObjectTracker` and loses its player collision exception once clear; `station_activity_changed` goes active on input and empty after `idle_timeout` |

Step 2 adds a world-layout test (each spawned kind in its container); step 3 adds budget and
reset tests.

**Left out:** Zurd behaviour (temporary), the lidar C# code (needs a build; has its own scratch
approach), the importer (editor only; manual check in `tests/README.md`), shaders and effects
(placeholders), the Controller Setup screen's UI (`test_controllers.gd` covers what it saves).

### Done when

- One command runs every test in under 2 minutes and exits non-zero on any failure.
- It passes on the current code, and a check broken on purpose makes it fail (then restored).
- The `user://` guard passes, and a planted write to the real config path trips it (then
  removed).
- `CLAUDE.md`: "How to run" documents the command, replacing "There is no CLI build or test
  loop"; the Workflow section says to run it before code commits and keep tests in step; the
  "No committed tests" known gap goes. `ONBOARDING.md` likewise.
- `toroidal_world.tscn` and `test/` are gone; nothing references them outside the archive.

### Edge cases

- The importer only runs in the editor, so it can't be tested in game mode. `tests/README.md`
  describes the manual check used on 2026-11-04: copy the project to a scratch folder, add test
  models in each `assets/models/` folder, run `--headless --import` there, inspect the output.
- A new `class_name` script isn't known in game mode until the editor rescans (on window focus).
  With the editor closed, run `--headless --import` once first.
- Physics checks use tolerances; `--fixed-fps 60` keeps runs repeatable enough.

## 2. Split `base_world.tscn`

### Target

```
BaseWorld (Node3D, base_world.gd)          ← still the template zurd_world.tscn inherits
├─ Environment    environment.tscn          WorldEnvironment (sky), DirectionalLight3D
├─ GameSystems    game_systems.tscn         MassManager, SculptureFx (GameSession, step 3)
├─ Input          scenes/input/input.tscn   MouseSwatInput (LidarManager later)
└─ Actors (Node3D)
   ├─ Ship         PlayerShip
   ├─ Zurds        the hand-placed Zurd
   ├─ Objects      loose objects
   ├─ Masses       sculpture masses and clouds
   └─ Projectiles  swat projectiles
zurd_world.tscn = BaseWorld + Terrain (as now)
```

`base_world.tscn` stays the template, because `sandbox/world/idea_large_world.tscn` inherits it
too. Flattening it into one world scene is a choice for step 6.

### Steps

1. In the editor, add `Environment` (Node3D) under BaseWorld, move WorldEnvironment and
   DirectionalLight3D into it, then right-click it → Save Branch as Scene →
   `scenes/world/environment.tscn`. Do the same for `GameSystems` (Node: MassManager,
   SculptureFx) → `scenes/world/game_systems.tscn`, and `Input` (Node: MouseSwatInput) →
   `scenes/input/input.tscn`. Working in the editor keeps node ids and the inherited scenes'
   overrides consistent.
2. Replace `ObjectContainer` with `Actors` and its five containers; move PlayerShip into `Ship`
   and the Zurd into `Zurds`.
3. `base_world.gd`: send each `spawn_requested` node to its container: `SculptureMass` → Masses,
   `Zurd` → Zurds, `SwatProjectile` → Projectiles, anything else → Objects. Only
   `base_world.gd` and `base_world.tscn` use `ObjectContainer` today.
4. `sandbox/test_sculpture_mass.tscn` overrides three `MassManager` values (threshold 5,
   `hits_to_fuse` 1, debug labels), which now sit inside an instanced sub-scene. In the editor,
   right-click GameSystems → Editable Children, then set the three values again.
5. Reopen and save `zurd_world.tscn` (it places Terrain at child index 6) and
   `sandbox/world/idea_large_world.tscn` (index 3) so their child order is right.
6. Update `CLAUDE.md` and `ONBOARDING.md` (world layout, spawn flow).

### Done when

- All tests pass unchanged. A new test checks that each kind of spawned node lands in its
  container, and that the sculpture test scene's overrides still apply.
- `zurd_world.tscn` and `sandbox/test_sculpture_mass.tscn` play as before.

## 3. Object budget and session reset

### Design

`GameSession` (`scenes/world/game_session.gd`, `class_name GameSession`, a Node in
`game_systems.tscn`) owns both. Nothing else frees objects for budget or reset reasons, so the
HUD and attract mode can hook in later through its signals.

**Budget**
- **Loose objects:** `max_loose_objects`, starting at 150 (tune on the exhibit PC). GameSession
  keeps loose bodies in arrival order from `ObjectTracker.object_registered` (a `RigidBody3D` that
  isn't a `SculptureMass`; objects broken off a mass arrive again as new). Over the cap, the
  oldest despawns: it's unregistered from `ObjectTracker`, its collision is turned off, its
  visuals shrink to nothing over `despawn_time` (1 s), and it's freed.
- **Fused objects are never despawned.** The sculptures are the point, and each mass leaves on
  its own as a cloud at the threshold.
- **Clouds:** `max_clouds`, starting at 8. On `EventBus.cloud_formed`, the oldest cloud over the
  cap fades out (a new `SculptureMass.fade_out(time)` tweens `cloud_alpha` to 0) and is freed.
- **A despawning object is off-limits.** GameSession sets a `despawning` meta on it.
  `ObjectTracker.is_trackable()` rejects it, so a Zurd already chasing it lets go (unregistering
  alone doesn't stop a Zurd that already has it as its target). `MassManager._is_loose()` and
  `_is_fuse_partner()` reject it too, because a fuse queued in the same frame could still use it.

**Reset**
- GameSession tracks which stations are active from `EventBus.station_activity_changed`.
  Stations start empty.
- When no station is active, a `reset_after_idle` timer starts: 90 s, after StationActivity's
  own 30 s `idle_timeout`, so about 2 minutes without input. Any station going active cancels it.
- On timeout it resets only if something happened this session (an object was launched or a
  station was used), so an untouched world isn't reloaded over and over.
- A reset reloads the current world: `SceneChanger.change_scene_async(get_tree().current_scene.scene_file_path)`.
  A reload is guaranteed clean, with no per-system reset code to keep in step with the Zurd
  overhaul or new systems. It costs one loading screen: about 0.4 s today, less after step 5.
- New EventBus signals for the HUD and attract mode: `session_started` (GameSession is ready) and
  `session_resetting` (just before the reload), documented like the others.

### Done when (tests, with short times and `--fixed-fps`)

- 160 launches leave 150 loose objects, the oldest gone first; fused objects are untouched.
- A despawning object never fuses or combines, and a Zurd targeting it lets go.
- The 9th cloud fades out the 1st.
- A reset fires only after every station has been empty for the full time; activity cancels
  it; an untouched world isn't reset; after a reset, `ObjectTracker` is empty and the world is
  fresh.

## 4. Object catalog

*Redefined 2026-11-10.* The asset library (2026-11-08) brought the launchable objects from 3 to
51, all listed by hand in one `projectile_scenes` array in `player_ship.tscn`. The catalog moves
that list into one curated resource, gives each object a group, and makes adding a model a
button press.

### Status (2026-11-10)

Built, except the root-model cleanup, which is done by hand in the editor (below). A scratch
harness (not committed) ran against a copy of the project, headless in Godot 4.7.2 at a fixed
60 fps, and passed **63 of 63 checks**: every item under "Done when", plus the Inspector hints
(the group dropdown and the tool button, read from the property list), a second sync adding
nothing, sync leaving an unchanged catalog's file alone, and editing `groups` refreshing the
entries' dropdown. 102,000 picks gave each of the 51 objects between 1907 and 2072 picks
(2000 expected). The Inspector itself (the dropdown and the Sync button) hasn't been checked
in the editor yet.

Changes from the design below, found while building:

- **The launcher warns about an empty or missing catalog**, not `pick_random()`, which returns
  null quietly. The launcher knows the context.
- **A catalog that lists a missing scene fails to load in the game**, and so does the ship
  (checked: the `.tres` parse stops at the missing `ext_resource`). The old array in
  `player_ship.tscn` behaved the same. Sync can't report a missing file in the game for that
  reason; in the editor the FileSystem dock warns before deleting a scene the catalog uses.
- **Sync is `sync_with_scenes()`** (`sync` was a keyword in Godot 3). It returns
  `{"added": paths, "problems": messages}` for tests, and prints a one-line summary besides the
  warnings, so a press with nothing to do still shows a result.
- **Messages name objects without `_rigid`** (`Archway is listed twice ...`).

### Decisions (2026-11-10)

- **An entry is a scene and one group.** No launch weight, size range, display name, icon or
  station flag. Random launches pick evenly across all entries, and the launch size stays the
  launcher's global `min_scale`–`max_scale` (1–7). The models are already normalised to a longest
  side of about 3 m (spires and pillar about 4 m), so per-object sizes aren't needed yet. Fields
  can be added later without changing the file format of the rest.
- **Groups are labels for later.** Nothing reads them yet: no group weights, filters or station
  order. Each entry has exactly one group, chosen from a list of names kept on the catalog.
- **Launched objects carry their group** as meta `catalog_group`, and it survives fusing and
  breaking off, so later systems (HUD, Zurds, combining rules) can read it from any loose object
  or `MassPiece` without a lookup.
- **Curated, with a sync button.** Nothing launches until it's in the catalog. A tool button adds
  every scene in `scenes/objects/rigid/` that isn't listed yet, at the end of the list, in group
  `Unsorted`, and reports problems (below).
- **The launch station steps through the whole catalog in list order**, the same set random
  launches use. The list order is hand-arranged; sync only appends.
- **Combining stays as it is.** With 51 even picks, matching objects rarely meet, so combining
  (Sculpture-Mass §4.10) will be rare. Revisit after playtests; a session palette or
  group-based combining were considered and left out.
- `EventBus.launch_selection_changed(station, scene)` and `launch_object(scene, side_offset)` keep
  passing the scene. Nothing listens to the signal, and the preview shows the model itself.

### Design

- `scripts/objects/object_catalog_entry.gd` (`@tool`, `class_name ObjectCatalogEntry`, a
  Resource): `scene: PackedScene`, `group: StringName` (default `&"Unsorted"`). In the Inspector,
  `group` is a dropdown built from the catalog's `groups` (`_validate_property` with an enum hint;
  the catalog hands its names to its entries when it loads or its `groups` change). The name is
  stored, not an index, so reordering groups changes nothing.
- `scripts/objects/object_catalog.gd` (`@tool`, `class_name ObjectCatalog`, a Resource):
  - `groups: Array[StringName]`, starting with the draft below. `Unsorted` is always present.
  - `entries: Array[ObjectCatalogEntry]`.
  - `pick_random() -> ObjectCatalogEntry`: even pick over usable entries (scene not null), null
    when there are none.
  - `size()`, `get_entry(i)`: over usable entries only, so the station never lands on an empty slot.
  - `find_entry(scene)`, `get_group(scene)` (`Unsorted` when unlisted), `get_group_names()`,
    `check()`, the static `group_of(node)`, and `const GROUP_META := &"catalog_group"`.
  - `@export_tool_button("Sync with rigid scenes")`: appends missing scenes from
    `res://scenes/objects/rigid/`, then reports with `push_warning`: entries whose scene is null or
    missing, a scene listed twice (it would be picked twice as often), a group not in `groups`,
    and a scene whose root isn't a `RigidBody3D` whose first collider is a box or (since
    2026-11-10) a convex hull at scale 1, the contract the launcher and the sculpture code depend
    on. It only reports; it never removes or reorders entries.
- `data/object_catalog.tres`: the one catalog, which gives `data/` its purpose. Scenes are
  referenced by UID, so the snake_case rename of the models doesn't break it.
- `LaunchObjectComponent`: `projectile_scenes` becomes `@export var catalog: ObjectCatalog`.
  A random launch uses `catalog.pick_random()`. Every launched object gets
  `set_meta(ObjectCatalog.GROUP_META, group)` from its entry (`find_entry` for a scene passed in
  by a station; `Unsorted` if the scene isn't in the catalog). `get_projectile_count()` becomes
  `get_object_count()` → `catalog.size()`, and a new `get_object_scene(i)` replaces the station's
  direct read of `projectile_scenes[i]`.
- `LaunchStation`: uses `get_object_count()` / `get_object_scene(i)`; otherwise unchanged.
- `MassPiece`: `capture_body` stores the body's `catalog_group` and also sets it as meta on the
  piece; `restore_body` puts it back on the new body when an object breaks off. Combined objects
  share a model, so they share a group. `SculptureMass` itself has no group.
- `player_ship.tscn`: `LaunchMuzzle.catalog` points at `data/object_catalog.tres`; the 51
  `ExtResource` lines for the old array go.

### Starting groups (draft; re-sort in the Inspector)

| Group | Objects |
| --- | --- |
| Animals | Bull_01, Bull_02, Cavallo_01, Crocodile_01, Eagle_01, Leone_01–03 |
| Figures | Gargoyle_01–05, BurntBoy_01, Shield_Man, Tounge_01 |
| Architecture | Arch_01, Archway, BrickWall_01, Pillar_01, Piling_01–02, Spire_Stock_01–02, Stairs_01, Pathway_01 |
| Geometry | GEO_Stock_02–07, Texture_Form_01 |
| Nature | Bush_Stock_01, Tree_Stock_01 |
| Unsorted | BT_02, BT_07, BT_08, BT_08-h, BT_09, BT_10, Carpet_01, Medallion_01, Misc_01, Misc_02, Misc_04, Misc_05, Fribourg, Rochefort_01, Stammheim_01, Zuzgen |

The list starts in today's `projectile_scenes` order, so the station steps through objects as it
does now.

### Cleanup in the same step: root model duplicates

`Arch_01.glb`, `Archway.glb` and `Crocodile_01.glb` sit both directly in `assets/models/` and in
`assets/models/objects/`. Both copies write the same generated mesh and material files, so
whichever imports last wins. `Zurd_01.glb` is still directly in `assets/models/` too. In the
editor's FileSystem dock:

1. Delete the three root copies (and their `.import` files).
2. Move `Zurd_01.glb` into `assets/models/characters/`; the dock updates the Zurd scene's
   references.
3. Reimport the three `objects/` copies and `Zurd_01.glb`, then check that the rigid scenes and
   the Zurd still show their meshes.
4. Update `assets/models/README.md` and the "Model files" known gap in `CLAUDE.md` (only the
   snake_case rename remains).

### Done when

- Over 10,000 picks every usable entry is picked within a few percent of evenly; null entries are
  never picked; an empty catalog warns and launches nothing (and the station shows nothing).
- Sync on the current project adds nothing after the first run, and reports a planted null entry,
  duplicate, unknown group and non-box scene.
- The station steps and wraps through the catalog in list order.
- A launched object has the `catalog_group` meta of its entry; after it fuses and breaks off, the
  new body has the same group, and the `MassPiece` had it while fused.
- Launching plays as before. No `projectile_scenes` references are left (grep).
- Checked with a scratch headless harness until step 1 exists; then these checks become
  `tests/unit/test_object_catalog.gd` and part of `tests/scene/test_sculpture.gd`.

### Edge cases

- **Removing a model:** delete its catalog entry first. A catalog that lists a missing scene
  fails to load in the game, and the ship with it (see Status).
- **Keeping a model out:** Sync adds back every rigid scene that isn't listed, so deleting an
  entry alone doesn't keep a model out; move its `.glb` out of `objects/` and delete its rigid
  scene too. If that gets in the way, an "excluded" list that Sync skips is a small addition.
- **Renaming or removing a group** leaves entries with a name not in `groups`; they still work,
  and sync reports them.
- **A scene launched by a station that isn't in the catalog** (only possible if a script passes
  one) gets group `Unsorted`.
- **Sandbox scenes** that instance `player_ship.tscn` get the same catalog. A test can point
  `LaunchMuzzle.catalog` at a smaller `.tres`.

## 5. Terrain bake

### Decision

Bake the mesh and the collision shape, not just the heights. Baking the heights (128 KB) would
save only the ~116 ms of noise. Baking the mesh and shape (~1.4 MB compressed) removes all
~250 ms of generation, and the files load on the loader thread, inside the progress bar. What
stays on the main thread is assigning them (~75 ms; re-measure after the change).

### Design

- `Terrain` gets `baked_mesh: ArrayMesh` and `baked_collision: ConcavePolygonShape3D`, saved as
  compressed binary files next to the scene (`scenes/world/terrain_mesh.res`,
  `scenes/world/terrain_collision.res`), plus `baked_settings_hash`.
- A **Bake** tool button generates and saves both, and stores a hash of every shape setting.
- At runtime, `_ready()` assigns the bake when the hash matches the current settings. Otherwise
  it generates as now and, in editor builds, warns that the bake is stale.
- In the editor, changing a setting still regenerates live; the files change only on Bake.
- Each re-bake adds ~1.4 MB to git history, so bake when the map settles, not on every tweak.

### Done when

- Adding the world to the tree takes under ~100 ms with a fresh bake (was 324 ms); measure it.
- Changing a setting without baking falls back to generation, with the warning.
- The ship's ground ray and the Zurds' avoidance rays hit the baked collider.

### Not chosen

- **Generating on a worker thread:** the world would start without terrain for ~0.3 s, so the
  ship's ground check and the loading screen would need a "world ready" handshake. More moving
  parts for the same result.
- **A `HeightMapShape3D` collider** (built from the heights, cheaper to build and store) is worth
  a look later. It needs the shape scaled unevenly to fit the grid, which needs checking with Jolt.

## 6. Sandbox removal (when the 1000 × 1000 map idea is done)

Trigger: Mitch calls the map idea done.

1. Remove "1000 x 1000 Map Example" from `main_menu.tscn`'s scene list.
2. Delete `sandbox/world/` (6.9 MB: `idea_large_world`, `test_lg_ground`, `test_ground`,
   `test_wrap`, `tileable_*`, `map_idea_04.jpg`). Keep a copy of the map sketch outside the repo,
   such as the workspace folder, if it's still useful.
3. Delete what that leaves unused, after a grep confirms it:
   `scenes/objects/static/{Arch_01,Archway,Crocodile_01}_static.tscn` (only `test_ground` used
   them, and models in `objects/` no longer get static scenes), then `golf_terrain.tres` and
   `golf_terrain.gdshader`.
4. With only `zurd_world.tscn` inheriting `base_world.tscn`, decide whether to flatten them into
   one world scene, and settle the `zurd_world` / `main_world` name (review doc, Naming).
5. Update `CLAUDE.md` (sandbox row) and `ONBOARDING.md` (sandbox, terrain).

Done when the tests pass, the editor opens with no missing-dependency dialog, and grep finds no
references.

## Files

| File | Step | Change |
| --- | --- | --- |
| `tests/run_tests.gd`, `tests/test_case.gd`, `tests/README.md`, `tests/unit/*`, `tests/scene/*` | 1 | New |
| `export_presets.cfg` | 1 | Exclude `tests/*` |
| `scripts/autoload/controllers.gd` | 1 | `set_config_path(path)`, so tests never write the real config |
| `scenes/world/toroidal_world.tscn`, `test/` | 1 | Delete (unused) |
| `scenes/world/environment.tscn`, `scenes/world/game_systems.tscn`, `scenes/input/input.tscn` | 2 | New, saved from branches of `base_world.tscn` |
| `scenes/world/base_world.tscn`, `scenes/world/base_world.gd` | 2 | Composition of sub-scenes, actor containers, spawn routing |
| `sandbox/test_sculpture_mass.tscn` | 2 | Editable children, overrides set again |
| `scenes/world/game_session.gd` | 3 | New |
| `scripts/autoload/event_bus.gd` | 3 | `session_started`, `session_resetting` |
| `scripts/autoload/object_tracker.gd`, `scenes/sculpture/mass_manager.gd` | 3 | Reject despawning objects |
| `scenes/sculpture/sculpture_mass.gd` | 3 | `fade_out(time)` |
| `scripts/objects/object_catalog.gd`, `scripts/objects/object_catalog_entry.gd`, `data/object_catalog.tres` | 4 | New |
| `scenes/characters/player/launch_object_component.gd`, `launch_station.gd`, `player_ship.tscn` | 4 | Use the catalog; group meta on launch |
| `scenes/sculpture/mass_piece.gd` | 4 | Carry `catalog_group` through fuse and break-off |
| `assets/models/{Arch_01,Archway,Crocodile_01}.glb`, `Zurd_01.glb`, `assets/models/README.md` | 4 | Delete root duplicates, move Zurd into `characters/` (in the editor) |
| `scenes/world/terrain.gd`, `terrain.tscn`, `terrain_mesh.res`, `terrain_collision.res` | 5 | Bake |
| `scenes/ui/menus/main_menu.tscn`, `sandbox/world/*`, unused static scenes, `golf_terrain.*` | 6 | Remove |
| `CLAUDE.md`, `claude/ONBOARDING.md` | all | Keep current with each step |

## Open questions for Mitch

Defaults are in place, so building can start before these are answered.

1. **Budget numbers:** 150 loose objects, 8 clouds, reset after about 2 minutes without input.
   They'll be tuned on the exhibit PC with the frame rate logged.
2. **What guests see during a reset:** the loading screen (default) or a fade to black?
3. **Should masses have a cap too?** Default: no. Each mass leaves as a cloud at the threshold.
4. ~~**Catalog names and icons:** fill them in now, or with the launch station display?~~
   Answered 2026-11-10: neither. The preview shows the model itself; entries hold a scene and a
   group (step 4).
5. **Terrain baking:** who presses Bake, and when (default: whoever changes the terrain, before
   committing)?
6. **When is the 1000 × 1000 map idea done?** That triggers step 6.
