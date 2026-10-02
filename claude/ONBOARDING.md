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

**Why the .NET build if the code is GDScript?** The project is configured for .NET
(`[dotnet] project/assembly_name="zurd"`), which enables writing gameplay in **C#** later.
Today there are **no `.cs` files** — everything is GDScript — but the .NET editor is required
so the project opens with matching features and can adopt C# without a re-setup.

### GDScript
The scripting language for all current gameplay code. It's Python-like, tab-indented, and
tightly integrated with the engine. Files end in `.gd`. This codebase uses **typed**
variables and return types (e.g. `func spawn() -> Node3D:`) and `class_name` declarations —
follow that style.

### Scenes, scripts, and resources
- **Scene (`.tscn`)** — a tree of nodes; the fundamental building block. Scenes can be
  nested (instanced) inside other scenes.
- **Script (`.gd`)** — attached to a node to give it behaviour.
- **Resource (`.tres`, `.gdshader`, `.glb`, …)** — reusable data assets (materials, shaders,
  3D models).
- **`.import` / `.uid` files** — engine bookkeeping generated on import. Don't hand-edit them.

### Autoloads (singletons)
Scripts registered as **autoloads** are global — accessible from anywhere by name without
instancing a scene. This project registers two (in `project.godot`):

| Name | Script | Responsibility |
|---|---|---|
| `EventBus` | `scripts/autoload/event_bus.gd` | Central signal bus for global events (interaction, spawning, UI). Currently a stub. |
| `SceneChanger` | `scripts/autoload/scene_changer.gd` | Synchronous and threaded/async scene loading + transitions. |

### Forward+ renderer
The high-end desktop rendering backend (vs. Mobile / Compatibility). Chosen for richer
lighting and effects.

---

## Dependencies to run on localhost

There is **no package-manager step** — no `npm install`, no `dotnet restore`. Assets and
scripts are committed directly to the repo. You only need to install these applications:

| Dependency | Why you need it | Notes |
|---|---|---|
| **Godot Engine 4.7.2-stable — .NET/Mono build** | The editor *is* the runtime; "running on localhost" = pressing Play in the editor | Match the project's version (4.7.2-stable). Download the **.NET (mono)** variant. |
| **.NET SDK** | Required by the Godot .NET build to load and run | Install the latest LTS SDK; needed even though there are no `.cs` files yet |
| **VS Code** (or another IDE) | Editing scripts + git/GitHub integration | Optional extensions: *Godot Tools*, *C#* |
| **Git** + a **GitHub account with access** to the repo | Clone, commit, push | See [Committing your work](#committing-your-work) |

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
4. **Press F5** (Play). You'll boot → main menu → press *Start* → the world loads.
5. **Controls:** movement is **WASD** (`move_up/down/left/right` in the input map). The
   sandbox player also hot-swaps control schemes with number keys **1–4**.

---

## Architecture tour

- **Entry flow:** `scenes/ui/loading_screen/boot.tscn` (the main scene) runs `boot.gd`,
  which calls `SceneChanger.change_scene(...)` to go to the **main menu**
  (`scenes/ui/menus/main_menu.tscn`). The menu's *Start* button calls
  `SceneChanger.change_scene_async(...)` to load the **world**.
- **World:** `scenes/world/base_world.gd` (`class_name BaseWorld`) holds an
  `ObjectContainer`. `toroidal_world.gd` (`class_name ToroidalWorld`) extends it and, each
  physics frame, wraps any `RigidBody3D`/`CharacterBody3D` that leaves the play bounds —
  fly straight and the world repeats. The wrap math lives in
  `scripts/utils/toroidal_utils.gd`.
- **GLB physics importer** (`scripts/import/glb_physics_importer.gd`): a `@tool`
  `EditorScenePostImport` script. Drop a `.glb` into `assets/models/` and, on import, it
  auto-generates four scenes under `scenes/objects/`:
  - `mesh/<name>_mesh.tscn` — visuals (with vertex colors enabled)
  - `collider/<name>_collider.tscn` — a box collider sized to the model's AABB
  - `static/<name>_static.tscn` — `StaticBody3D`, collision layer 1 (Environment)
  - `rigid/<name>_rigid.tscn` — `RigidBody3D`, collision layer 3 (Objects)

  Don't hand-edit the generated scenes; re-import the source `.glb` instead.
- **Spawning:** `scripts/world/scene_spawner.gd` (`class_name SceneSpawner`) instances a
  `PackedScene` at a location under a container node.
- **`sandbox/`:** a scratch area for playtesting (`test_player`, `test_ground`, `test_wrap`,
  controller experiments). Not part of the shipped game.

---

## Known gaps / gotchas

New contributors hit these — they are known and not yet fixed:

1. **Boot's default menu path is wrong.** `scenes/ui/loading_screen/boot.gd` defaults
   `initial_scene_path` to `res://scenes/ui/menus/main_menu/main_menu.tscn`, but the file is
   at `res://scenes/ui/menus/main_menu.tscn` (no extra folder). It works only because the
   value is overridden in the Inspector — verify the Inspector value if boot fails.
2. **`LoadingScreen` isn't registered.** `scripts/autoload/scene_changer.gd` calls a global
   `LoadingScreen` (e.g. `LoadingScreen.show_screen()`), but only `EventBus` and
   `SceneChanger` are registered under `[autoload]` in `project.godot`. Async loads may error
   until `LoadingScreen` is added as an autoload.
3. **Mixed indentation.** `glb_physics_importer.gd` uses spaces; most other `.gd` files use
   tabs. GDScript convention (and this project's majority) is **tabs** — match the file
   you're editing, and prefer tabs for new files.

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
