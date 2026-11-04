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

## 1. Tests

### Design

`tests/` at the project root (delete the empty, untracked `test/` folder):

```
tests/
  run_tests.gd    extends SceneTree. Names no project classes: those would compile before the
                  autoloads exist and stay broken for the run. Finds every tests/**/test_*.gd,
                  runs each, prints PASS/FAIL per check and a summary, exits 1 on any failure.
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
- Add `tests/*` to both export presets' `exclude_filter`.

### First tests

| File | Checks |
| --- | --- |
| `unit/test_object_parts.gd` | Sizes in both modes (3 and 4 make ≈ 4.5 or 7), absorb order, `remove_last` restores the exact size, `is_bigger_than`, `of()` builds a record from the shape's scale |
| `unit/test_box_overlap.gd` | `MassPiece.get_box_overlap`: apart is negative, overlapping gives the depth, rotated boxes, touching ≈ 0 |
| `unit/test_control_scheme.gd` | Both schemes apply, `get_current` reports them, the project's events come back |
| `unit/test_scene_changer.gd` | A missing path and a non-scene file both fire `load_failed`, close the loading screen and re-enable the menu; a real async load switches scene |
| `unit/test_main_menu.gd` | The controls label comes from the input map; entries whose scene is missing are skipped |
| `scene/test_sculpture.gd` | Port the combining build's checks (`archive/2026-11-04-combining-objects-plan.md`, Verification): fusing, combining (loose, fused, after a merge), growth break-off, bites (loose, fused, through `eat_requested`), break-off keeps parts, cloud counting by parts, same-batch follow |
| `scene/test_ship.gd` | Port the ship-controls build's checks (`archive/2026-11-01-ship-controls-plan.md`, Verification): top speed, coast to hover, turn rate, hover drift bounds, launch speeds, ground clearance |

The checks used to verify the review passes on 2026-11-04 (controls label, both load-failure
paths, UIDs, loading screen layer, menu skipping) are the starting point for the unit tests.

### Done when

- One command runs every test in under 2 minutes and exits non-zero on any failure.
- `CLAUDE.md` "How to run" documents it, replacing "There is no CLI build or test loop".

### Edge cases

- Leave C# out of the first tests: they would need the C# project built first.
- Physics checks use tolerances; `--fixed-fps 60` keeps runs repeatable enough.
- The importer only runs in the editor, so it can't be tested in game mode. `tests/README.md`
  describes the manual check used on 2026-11-04: copy the project to a scratch folder, add test
  models in each `assets/models/` folder, run `--headless --import` there, inspect the output.
- Later, optionally: CI on GitHub Actions. It needs the .NET SDK and a C# build before Godot runs.

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
  The chosen control scheme survives, because it lives in the global input map.
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

### Design

- `scripts/objects/object_catalog_entry.gd` (`class_name ObjectCatalogEntry`, a Resource):
  `scene` (PackedScene), `display_name`, `icon` (Texture2D), `launch_weight` (1.0).
- `scripts/objects/object_catalog.gd` (`class_name ObjectCatalog`, a Resource): `entries`,
  `pick_random()` weighted by `launch_weight` (skipping empty or zero-weight entries), `size()`,
  `get_entry(i)`.
- `data/object_catalog.tres`: the one catalog, which gives `data/` its purpose. It starts with
  today's list: Archway, Arch_01, Crocodile_01, each at weight 1.
- `LaunchObjectComponent`: `projectile_scenes` becomes `catalog: ObjectCatalog`;
  `launch_object(scene = null)` picks from the catalog when no scene is given;
  `get_projectile_count()` becomes `catalog.size()`. `player_ship.tscn` points at the catalog.
- `LaunchStation` selects catalog entries, and `EventBus.launch_selection_changed(station, entry)`
  passes the entry, so a station display later gets the name and icon. Nothing listens yet.
- Optional, cheap: the catalog warns in the editor when an entry's scene isn't a `RigidBody3D`
  with a `BoxShape3D`, the box-collider contract from the review, checked where objects are listed.
- Adding a launchable model becomes: drop the `.glb` into `assets/models/objects/`, then add a
  catalog entry. The catalog references scenes by UID, so the snake_case rename doesn't break it.

### Done when

- Over 10,000 picks the counts match the weights within a few percent; a zero weight is never
  picked; an empty catalog warns and launches nothing.
- Station selection wraps and emits the entry.
- Launching plays as before.

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
| `scenes/world/environment.tscn`, `scenes/world/game_systems.tscn`, `scenes/input/input.tscn` | 2 | New, saved from branches of `base_world.tscn` |
| `scenes/world/base_world.tscn`, `scenes/world/base_world.gd` | 2 | Composition of sub-scenes, actor containers, spawn routing |
| `sandbox/test_sculpture_mass.tscn` | 2 | Editable children, overrides set again |
| `scenes/world/game_session.gd` | 3 | New |
| `scripts/autoload/event_bus.gd` | 3, 4 | `session_started`, `session_resetting`; `launch_selection_changed` passes the entry |
| `scripts/autoload/object_tracker.gd`, `scenes/sculpture/mass_manager.gd` | 3 | Reject despawning objects |
| `scenes/sculpture/sculpture_mass.gd` | 3 | `fade_out(time)` |
| `scripts/objects/object_catalog.gd`, `scripts/objects/object_catalog_entry.gd`, `data/object_catalog.tres` | 4 | New |
| `scenes/characters/player/launch_object_component.gd`, `launch_station.gd`, `player_ship.tscn` | 4 | Use the catalog |
| `scenes/world/terrain.gd`, `terrain.tscn`, `terrain_mesh.res`, `terrain_collision.res` | 5 | Bake |
| `scenes/ui/menus/main_menu.tscn`, `sandbox/world/*`, unused static scenes, `golf_terrain.*` | 6 | Remove |
| `CLAUDE.md`, `claude/ONBOARDING.md` | all | Keep current with each step |

## Open questions for Mitch

Defaults are in place, so building can start before these are answered.

1. **Budget numbers:** 150 loose objects, 8 clouds, reset after about 2 minutes without input.
   They'll be tuned on the exhibit PC with the frame rate logged.
2. **What guests see during a reset:** the loading screen (default) or a fade to black?
3. **Should masses have a cap too?** Default: no. Each mass leaves as a cloud at the threshold.
4. **Catalog names and icons:** fill them in now, or with the launch station display?
5. **Terrain baking:** who presses Bake, and when (default: whoever changes the terrain, before
   committing)?
6. **When is the 1000 × 1000 map idea done?** That triggers step 6.
