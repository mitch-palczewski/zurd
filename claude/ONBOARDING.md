# Onboarding: the zurd tech stack

Welcome to **zurd**. This guide gets a new contributor — even one who has never touched
Godot — from zero to running the game and understanding how it's put together. For the
game's story, commit-message rules, and collision-layer tables, read [../README.md](../README.md)
first; this document covers the *tech stack* and *how to work in it*.

---

## What you're building

A multiplayer immersive game where guests steer a trans-dimensional trophy room through a
vast expanse of space. Players deploy objects from the room's cache of curiosities to build
islands of matter and defend them from an infestation of roving *Zurd* skulls that gobble up
objects — and, if the ship is poorly defended, the ship itself. You defend by swatting the
Zurds like flies.

---

## The tech stack, explained

### Godot Engine 4.7 — .NET edition
Godot is an open-source game engine. It is both the **editor** (where you build scenes and
write scripts) and the **runtime** (pressing Play runs the game inside the editor). This
project runs on **Godot 4.7.2-stable** (the `project.godot` `config/features` tag is `4.7`).
Use the **.NET / Mono** download, *not* the standard build.

**Why the .NET build?** Most code is GDScript, but the project now also has **C#** (see
below), so the .NET/Mono editor is required — and you must **build** the C# project before
running (the `[dotnet] project/assembly_name="zurd"` setting names that assembly).

### GDScript — gameplay
The language for all **gameplay** code. It's Python-like, tab-indented, and tightly
integrated with the engine. Files end in `.gd`. This codebase uses **typed** variables and
return types (e.g. `func spawn() -> Node3D:`) and `class_name` declarations — follow that
style.

### C# — lidar hardware only
C# (`.cs`) is used **only** for the **lidar** touch-input system (`scripts/lidar/`,
`scenes/tools/lidar_setup/`), because the RPLIDAR driver is a .NET library
(`RpLidar.NET`, vendored and patched under `thirdparty/`). This is the installation's
physical input: a lidar scans a wall/floor and turns touches into pointer + swat events.
C# files are PascalCase (a Godot node's class must be `partial` and match its file name,
e.g. `LidarSetup.cs` → `class LidarSetup`) and live in `namespace Zurd.Lidar`. If you're
only doing gameplay work, you can ignore this subsystem — but you still need the .NET SDK
so the project compiles.

### Scenes, scripts, and resources
- **Scene (`.tscn`)** — a tree of nodes; the fundamental building block. Scenes can be
  nested (instanced) inside other scenes.
- **Script (`.gd` or `.cs`)** — attached to a node to give it behaviour.
- **Resource (`.tres`, `.gdshader`, `.glb`, `.res`, …)** — reusable data assets (materials,
  shaders, 3D models, shared meshes).
- **`.import` / `.uid` files** (including `.cs.uid`) — engine bookkeeping generated on
  import/build. Don't hand-edit them.
- **`zurd.sln` / `zurd.csproj`** — the C# solution/project Godot generates and MSBuild
  builds. The one NuGet dependency is `System.IO.Ports` (serial, for the lidar).

### Autoloads (singletons)
Scripts registered as **autoloads** are global — accessible from anywhere by name without
instancing a scene. This project registers three (in `project.godot`):

| Name | Script | Responsibility |
|---|---|---|
| `EventBus` | `scripts/autoload/event_bus.gd` | Central signal bus. Signals: `spawn_requested(Node3D)`, `object_eaten(actor, obj, mass)`, lidar/input `swat_requested(uv)` and `pointer_moved(uv)`, and the sculpture-mass events `object_hit`, `object_fused`, `masses_merged`, `objects_broken_off`, `cloud_progress_changed`, `cloud_formed`. |
| `SceneChanger` | `scripts/autoload/scene_changer.gd` | Synchronous and threaded/async scene loading + transitions. A failed async load fires `load_failed`, so the loading screen closes and the menu works again. |
| `ObjectTracker` | `scripts/autoload/object_tracker.gd` | Tracks every Zurd target — loose launched `RigidBody3D`s **and** fused `MassPiece`s — and auto-cleans freed ones. API: `register_object`/`unregister_object`, `is_trackable`, `get_random_object`, `get_closest_object`, and an `object_registered` signal. |
| `Controllers` | `scripts/autoload/controllers.gd` | Gives each connected controller a `ControllerProfile` (Standard gamepad, Arcade kit, or Off) and binds its buttons and axes to that controller only. Remembers choices and learned layouts in `user://controller_config.json`. API: `get_devices`, `set_profile`, `save_learned_profile`, `reset_profile`, and a `devices_changed` signal. |

### Forward+ renderer & Jolt physics
**Forward+** is the high-end desktop rendering backend (vs. Mobile / Compatibility), chosen
for richer lighting. The 3D physics engine is **Jolt Physics**
(`project.godot` → `[physics] 3d/physics_engine="Jolt Physics"`), switched in to reduce
objects snagging on collider edges.

---

## Dependencies to run on localhost

Assets and scripts are committed directly to the repo. The only package pulled on demand is
the `System.IO.Ports` NuGet dependency, which Godot restores automatically the first time it
builds the C# project (needs internet once). You need to install these applications:

| Dependency | Why you need it | Notes |
|---|---|---|
| **Godot Engine 4.7.2-stable — .NET/Mono build** | The editor *is* the runtime; "running on localhost" = pressing Play in the editor | Match the project's version (4.7.2-stable). Download the **.NET (mono)** variant. |
| **.NET 10 SDK** | **Required** — the C# lidar code won't compile without it (and Godot can't build the project assembly) | The mono editor wants the .NET runtime **10.0.12** (bundled with SDK `10.0.x`). Install with `winget install Microsoft.DotNet.SDK.10 --source winget`, then restart the editor and any terminals so they pick up the PATH. Without it the GDScript game still runs, but the lidar scripts fail to build |
| **VS Code** (or another IDE) | Editing scripts + git/GitHub integration | Optional extensions (see README): *godot-tools*, *Godot Files*, *C# Tools for Godot* |
| **Git** + a **GitHub account with access** to the repo | Clone, commit, push | See [Committing your work](#committing-your-work) |
| *(hardware, optional)* **RPLIDAR unit** | Only to run the physical touch input; the game plays fine with mouse/keyboard | Configure it via the **Lidar Setup** scene (see below) |

---

## First run, step by step

1. **Clone** the repo:
   ```
   git clone https://github.com/mitch-palczewski/zurd.git
   cd zurd
   ```
2. **Open in Godot**: launch the Godot 4.7.2 **.NET (mono)** editor → *Import* → select this
   project folder → *Import & Edit*.
3. **Let Godot reimport assets** on first open (it builds `.godot/`, which is gitignored).
4. **Build the C# project**: click **Build** (the hammer icon, top-right of the editor). Do
   this on first open and again any time you pull C# changes — otherwise the lidar code is
   stale/missing. First build restores the `System.IO.Ports` NuGet package (needs internet).
5. **Press F5** (Play). You'll boot → main menu → press *Start* → the world loads. The menu
   also has a **Lidar Setup** entry (only needed for the physical install).
6. **Controls:** **W/S** forward/back, **A/D** turn, **Shift/Ctrl** rise/sink, **Space**
   launches a random object. **Left-click** swats a Zurd (makes it smaller and forces it to
   pick a new target). A gamepad works too (left stick or d-pad; Y/A or the triggers to
   rise/sink; B to launch). The launch station is **J/L** (or LB/RB) to show and choose an
   object, which appears on a pedestal in the cockpit, and **K** (or X) to launch it; with no
   object shown, K launches a random one from the right side. Input actions:
   `ship_forward/reverse`, `ship_turn_left/right`, `ship_rise/sink`, `ship_launch`,
   `launch_station_fire/prev/next`. The main menu's controls label is read from the live
   input map, so it always shows the current keys.
7. **Controllers:** each connected controller gets a *profile*, its own layout, so a gamepad
   and the arcade kit can be plugged in together (Ship-Controls Design Doc §6.3). The main
   menu's **Controllers** section lists them with a profile each: *Standard gamepad* (the
   8BitDo layout above), *Arcade kit*, or *Off*. The arcade kit's layout is learned once per
   computer: **Controller setup…** → *Learn* → press any button on the encoder, then each
   control when asked → *Save*. The same screen lights up pressed controls, to test a layout.
   Choices are saved in `user://controller_config.json`. Don't add controller bindings in
   Project Settings: they would match every controller, so the game drops them at startup.

---

## Architecture tour

- **Entry flow:** `scenes/ui/loading_screen/boot.tscn` (the main scene) runs `boot.gd`,
  which calls `SceneChanger.change_scene(...)` to go to the **main menu**
  (`scenes/ui/menus/main_menu.tscn`). The menu's *Start* button calls
  `SceneChanger.change_scene_async(...)` to load the **world**.
- **World:** `scenes/world/base_world.gd` (`class_name BaseWorld`) holds an
  `ObjectContainer` and, on ready, listens for `EventBus.spawn_requested` — when fired it
  parents the spawnable under `ObjectContainer`. The playable world, `zurd_world.tscn`, is
  `base_world.tscn` plus the procedural terrain. The world doesn't wrap: the toroidal world
  was removed in November 2026, and teleportation may come later for a small part of the map.
- **Player ship** (`scenes/characters/player/`, designed in
  `claude/design/Ship-Controls Design Doc.md`): `PlayerShip` (`class_name PlayerShip`, a
  `CharacterBody3D`) sets up `PlayerFlightController` on ready. The controller flies the ship
  "like a fish in water" from the `ship_*` inputs: thrust, turn, rise and sink, each eased in
  so a digital arcade stick feels smooth. With no input the ship coasts to a hover with a
  gentle drift and a cockpit bob. It only ever turns around global Y, so the projected view
  never pitches or rolls, and it stays between a ground clearance and a ceiling. It emits
  `impact_occurred` on collision. `LaunchObjectComponent` (the `LaunchMuzzle` node) is the one
  shared launcher: `launch_object(scene, side_offset)` spawns that scene (or a random one from
  its object catalog) straight ahead, from the middle or moved sideways to a station's own
  side, gravity-free with linear-damp "braking" so it coasts to a stop, adds random
  scale/spin/spread and half the ship's velocity, briefly excludes the player from collision
  until the object clears, then emits `EventBus.spawn_requested` and registers it with
  `ObjectTracker`. The **object catalog** (`data/object_catalog.tres`, an `ObjectCatalog`
  resource from `scripts/objects/`) lists every launchable object: its scene and one group
  (Animals, Figures, …; labels only for now). Random launches pick evenly from it, and every
  launched object carries its group as meta `catalog_group`, which it keeps while fused into a
  mass and after breaking off. Launch buttons live under `Stations`: each
  `LaunchStation` has its own cooldown and side offset. The launch station also keeps a
  selected object (designed in `claude/design/Launch-Station Design Doc.md`): the first
  select press shows it on its `LaunchPreview` (a pedestal in the cockpit with a turning,
  mesh-only copy of the object), later presses step, and its launch button fires it until
  the preview hides 5 s after the last press. Then it's back to random objects
  (`launch_selection_changed`, null on hide). Each `StationActivity` reports a station going
  active or empty (`station_activity_changed`).
- **Zurd enemy** (`scenes/characters/enemy/`): `Zurd` (`class_name Zurd`, a `CharacterBody3D`)
  is a thin coordinator that delegates to three components each physics frame:
  `ZurdTargetComponent` (asks `ObjectTracker` for a target — `CLOSEST` or `RANDOM`),
  `ZurdMovementComponent` (steers toward the target with slerped turning plus a forward
  raycast for obstacle avoidance against layer 1; holds the mouth on the target while eating
  and pushes masses it bumps), and `ZurdMouthComponent` (an area that eats the target — a
  loose object **or** a fused `MassPiece` — once it has stayed in the mouth for
  `eat_duration`; interrupted if the target leaves or the Zurd is swatted; emits
  `object_eaten`). This component pattern is the intended style for new actors. The Zurd
  scripts themselves are **temporary**: a Zurd design doc and a full overhaul are coming. For
  now there is one hand-placed Zurd; `ZurdSpawner` is kept out of the world while the
  sculpture system is tested.
- **GLB post-importer** (`scripts/import/glb_post_importer.gd`): a `@tool`
  `EditorScenePostImport` script, set as the project's default for scene imports, so a new
  model needs no setup. It only handles models under `assets/models/`, and the folder you drop
  a `.glb` into decides which scene it gets under `scenes/objects/` (see
  `assets/models/README.md`):
  - `objects/` → `rigid/<name>_rigid.tscn` — `RigidBody3D`, collision layer 3 (Objects), mask
    1–4. Uses a single **convex-hull collider**: the exact hull around the whole mesh, so
    objects collide close to their shape (holes and hollows are filled in). The hull's node
    sits at the model's middle at scale 1; the launcher and the sculpture masses depend on
    that (the object's size is read from that scale, and growth break-off measures the hull
    by its bounding box).
  - `scenery/` → `static/<name>_static.tscn` — `StaticBody3D`, collision layer 1
    (Environment). Uses **convex-hull colliders** (one `CollisionConvex` per mesh) so
    structures collide at mesh detail.
  - any other folder, such as `characters/` → no scene, only the mesh and material files.

  Every model's meshes are extracted to shared `.res` files under `assets/meshes/`, and its
  vertex-color materials to `assets/materials/objects/`, so all its scenes reference the same
  resources and look the same. Don't hand-edit the generated files; re-import the source
  `.glb` instead. Changing the importer doesn't reimport existing models on its own: select
  them in the FileSystem dock and press *Reimport* in the Import dock. A new launchable object
  also needs a catalog entry: open `data/object_catalog.tres` and press **Sync with rigid
  scenes**, then pick its group.
- **Sculpture masses** (`scenes/sculpture/`; spec in `claude/design/`, plan in `claude/plans/archive/`): the core
  build-up mechanic. `MassManager` (a node in `base_world.tscn` that holds all the tunables)
  watches every body in `ObjectTracker`, counts hits, and handles **fusing, merging, eating,
  and breaking off**. Physics contact callbacks only *queue* requests — the queue is drained
  in the manager's `_physics_process`, because collision shapes can't change inside a physics
  callback. Each clump is one `SculptureMass` (`RigidBody3D`); a fused object becomes a
  `MassPiece` holding its visuals while its `CollisionShape3D`s move onto the mass. Fused
  objects stay solid (`assets/shaders/sculpture_mass.gdshader`, opaque, only part of the way
  toward white as the mass grows); at the threshold the mass jumps to the cloud look
  (`sculpture_cloud.gdshader`) in a white flash while every object puffs up, then holds a
  moment before rising. `SculptureFx` wires placeholder effects to the EventBus signals. Try
  it in `sandbox/test_sculpture_mass.tscn`.
- **Lidar input** (`scripts/lidar/` + `scenes/tools/lidar_setup/`, all C#): drives the
  physical installation. `LidarDevice` wraps the vendored `RpLidar.NET` serial driver; the
  `touch/` code baselines the empty scene and detects touches; `calibration/` maps lidar
  space to the projected image (homography) and saves per-unit settings to
  `user://lidar_config.json`. The **Lidar Setup** scene (run via F6 or the main menu) connects
  a unit, shows its sweep, tunes touch detection, and runs the calibration wizard. Touches
  don't reach gameplay yet: the bridge that will turn them into `EventBus.pointer_moved` /
  `swat_requested` (`LidarManager`, step 4 of the lidar plan) comes once a lidar is set up
  against a screen or projection. Until then the mouse is the only swat input.
- **Terrain:** `scenes/world/terrain.gd` (`class_name Terrain`, a `@tool` `MeshInstance3D`)
  builds the landscape (continents, ridged mountains, hills, river valleys) from
  `FastNoiseLite` in `_ready`, with a trimesh collider on layer 1. The mesh isn't saved in
  the scene. Its material is `assets/materials/terrain.tres`. The older `TileableTerrain`
  prototype is in `sandbox/world/`.
- **`sandbox/`:** a scratch area for playtesting (`test_sculpture_mass`, `TestLidarTouch`,
  and old terrain and map prototypes in `world/`). Not part of the shipped game: the export
  presets exclude it, and the main menu hides entries whose scene isn't in the build.

---

## Known gaps / gotchas

New contributors hit these — they are known and not yet fixed:

1. **Lidar touches don't reach gameplay yet** (see Lidar input above). Use the mouse to swat.
2. **Zurds are temporary.** Expect odd behaviour, such as a Zurd swatted many times shrinking
   to nothing; the overhaul will replace these scripts.
3. **Nothing despawns.** Long sessions pile up loose objects and clouds; there's no object
   budget or session reset yet.
4. **No automated tests are committed yet.**

Style: every `.gd` and `.gdshader` file is indented with **tabs** (the GDScript style guide;
`.editorconfig` sets it), and file and folder names are snake_case except C# files.

---

## Committing your work

Commit standards live in [../README.md](../README.md): use `tag(scope): description` with
tags `feat | fix | docs | asset | tool | refactor`.

### Authenticate git (recommended: GitHub CLI)
The repo is pushed over HTTPS. The simplest one-time setup uses the **GitHub CLI** (`gh`),
which configures git credentials for you:

```
gh auth login          # GitHub.com → HTTPS → login with a web browser (or paste a token)
gh auth status         # confirm you're logged in
git push --dry-run origin main   # proves auth + write access without pushing anything
```

To push you need **write access** to `mitch-palczewski/zurd`. Check your role:

```
gh repo view mitch-palczewski/zurd --json viewerPermission
```

Expect `WRITE`, `MAINTAIN`, or `ADMIN`. If it returns `READ`, ask the repo owner (Mitch) to
add you as a collaborator — credentials alone can't grant permission your account lacks.

### Alternative: Personal Access Token (PAT)
If you prefer not to use `gh`: create a **fine-grained PAT** on github.com scoped to the
`zurd` repo with **Contents: Read and write**, then use it as the *password* on your first
`git push`. Git Credential Manager (already the configured helper on Windows) caches it for
future pushes.
