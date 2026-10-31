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
| `SceneChanger` | `scripts/autoload/scene_changer.gd` | Synchronous and threaded/async scene loading + transitions. |
| `ObjectTracker` | `scripts/autoload/object_tracker.gd` | Tracks every Zurd target — loose launched `RigidBody3D`s **and** fused `MassPiece`s — and auto-cleans freed ones. API: `register_object`/`unregister_object`, `is_trackable`, `get_random_object`, `get_closest_object`, and an `object_registered` signal. |

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
6. **Controls:** **W/S** pitch, **A/D** yaw, **Shift** boost, **Space** launch an object;
   **right-click** swats a Zurd (makes it smaller and forces it to pick a new target). Input
   actions: `ship_pitch_up/down`, `ship_yaw_left/right`, `ship_boost`, `ship_launch`. The
   main menu shows a controls label.

---

## Architecture tour

- **Entry flow:** `scenes/ui/loading_screen/boot.tscn` (the main scene) runs `boot.gd`,
  which calls `SceneChanger.change_scene(...)` to go to the **main menu**
  (`scenes/ui/menus/main_menu.tscn`). The menu's *Start* button calls
  `SceneChanger.change_scene_async(...)` to load the **world**.
- **World:** `scenes/world/base_world.gd` (`class_name BaseWorld`) holds an
  `ObjectContainer` and, on ready, listens for `EventBus.spawn_requested` — when fired it
  parents the spawnable under `ObjectContainer`. `toroidal_world.gd` (`class_name
  ToroidalWorld`) extends it and, each physics frame, wraps any `RigidBody3D`/`CharacterBody3D`
  that leaves the play bounds — fly straight and the world repeats. The wrap math lives in
  `scripts/utils/toroidal_utils.gd`.
- **Player ship** (`scenes/characters/player/`): `PlayerShip` (`class_name PlayerShip`, a
  `CharacterBody3D`) wires up two pieces on ready — `PlayerFlightController` (handles flight
  physics from the `ship_*` inputs and emits `impact_occured` on collision) and
  `LaunchObjectComponent`. The launcher picks a random scene from its `projectile_scenes`,
  spawns it gravity-free with linear-damp "braking" so it coasts to a stop, adds random
  scale/spin/spread, briefly excludes the player from collision until the object clears, then
  emits `EventBus.spawn_requested` and registers it with `ObjectTracker`.
- **Zurd enemy** (`scenes/characters/enemy/`): `Zurd` (`class_name Zurd`, a `CharacterBody3D`)
  is a thin coordinator that delegates to three components each physics frame:
  `ZurdTargetComponent` (asks `ObjectTracker` for a target — `CLOSEST` or `RANDOM`),
  `ZurdMovementComponent` (steers toward the target with slerped turning plus a forward
  raycast for obstacle avoidance against layer 1; holds the mouth on the target while eating
  and pushes masses it bumps), and `ZurdMouthComponent` (an area that eats the target — a
  loose object **or** a fused `MassPiece` — once it has stayed in the mouth for
  `eat_duration`; interrupted if the target leaves or the Zurd is swatted; emits
  `object_eaten`). This component pattern is the intended style for new actors.
- **GLB post-importer** (`scripts/import/glb_post_importer.gd`): a `@tool`
  `EditorScenePostImport` script. Drop a `.glb` into `assets/models/` and, on import, it
  auto-generates **two** scenes under `scenes/objects/`:
  - `static/<name>_static.tscn` — `StaticBody3D`, collision layer 1 (Environment). Uses
    **convex-hull colliders** (one `CollisionConvex` per mesh surface) so terrain/structures
    collide at mesh detail, and applies the shared `golf_terrain` material.
  - `rigid/<name>_rigid.tscn` — `RigidBody3D`, collision layer 3 (Objects), mask 1–4. Uses a
    single **box collider** sized to the combined AABB (cheap dynamic physics).

  Meshes are extracted to shared `.res` files under `assets/meshes/`, and vertex-color
  materials to `assets/materials/objects/`, so both scenes reference the same resources.
  Don't hand-edit the generated scenes; re-import the source `.glb` instead.
- **Sculpture masses** (`scenes/sculpture/`; full spec + plan in `claude/plans/`): the core
  build-up mechanic. `MassManager` (a node in `base_world.tscn` that holds all the tunables)
  watches every body in `ObjectTracker`, counts hits, and handles **fusing, merging, eating,
  and breaking off**. Physics contact callbacks only *queue* requests — the queue is drained
  in the manager's `_physics_process`, because collision shapes can't change inside a physics
  callback. Each clump is one `SculptureMass` (`RigidBody3D`); a fused object becomes a
  `MassPiece` holding its visuals while its `CollisionShape3D`s move onto the mass. The blend
  look is `assets/shaders/sculpture_mass.gdshader`; `SculptureFx` wires placeholder effects to
  the EventBus signals. Try it in `sandbox/test_sculpture_mass.tscn`.
- **Lidar input** (`scripts/lidar/` + `scenes/tools/lidar_setup/`, all C#): drives the
  physical installation. `LidarDevice` wraps the vendored `RpLidar.NET` serial driver; the
  `touch/` code baselines the empty scene and detects touches; `calibration/` maps lidar
  space to the projected image (homography) and saves per-unit settings to
  `user://lidar_config.json`. The **Lidar Setup** scene (run via F6 or the main menu) connects
  a unit, shows its sweep, tunes touch detection, and runs the calibration wizard. Touches
  surface to gameplay as `EventBus.pointer_moved` / `swat_requested`.
- **Terrain:** `sandbox/tileable_terrain.gd` (`class_name TileableTerrain`, a `@tool`
  `MeshInstance3D`) procedurally builds a seamless, tileable terrain mesh from
  `FastNoiseLite` — exported `terrain_size`, `resolution`, `height_scale`, and `noise`
  regenerate the mesh live in the editor. Several terrain shaders/materials exist in
  `assets/` — `golf_terrain` (what the importer currently applies to static bodies) and a
  newer `terrain.gdshader`/`terrain.tres` intended as the primary static/ground shader.
- **Spawning:** `scripts/world/scene_spawner.gd` (`class_name SceneSpawner`) instances a
  `PackedScene` at a location under a container node.
- **`sandbox/`:** a scratch area for playtesting (`test_player`, `test_ground`, `test_wrap`,
  `tileable_terrain`, `test_sculpture_mass`, `TestLidarTouch`, controller experiments). Not
  part of the shipped game.

---

## Known gaps / gotchas

New contributors hit these — they are known and not yet fixed:

1. **Boot's default menu path is wrong.** `scenes/ui/loading_screen/boot.gd` defaults
   `initial_scene_path` to `res://scenes/ui/menus/main_menu/main_menu.tscn`, but the file is
   at `res://scenes/ui/menus/main_menu.tscn` (no extra folder). It works only because the
   value is overridden in the Inspector — verify the Inspector value if boot fails.
2. **`LoadingScreen` isn't registered.** `scripts/autoload/scene_changer.gd` calls a global
   `LoadingScreen` (e.g. `LoadingScreen.show_screen()`), but only `EventBus`, `SceneChanger`,
   and `ObjectTracker` are registered under `[autoload]` in `project.godot`. Async loads may
   error until `LoadingScreen` is added as an autoload.
3. **Mixed indentation.** `scripts/import/glb_post_importer.gd` uses spaces; most other `.gd`
   files use tabs. GDScript convention (and this project's majority) is **tabs** — match the
   file you're editing, and prefer tabs for new files.

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
