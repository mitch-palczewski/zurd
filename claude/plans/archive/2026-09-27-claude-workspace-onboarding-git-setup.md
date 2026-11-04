# Plan: Claude workspace, onboarding doc, dependencies & git-push setup for `zurd`

## Context

`zurd` is a **Godot Engine 4.7 (.NET edition) 3D multiplayer game** by the Feed Collective, written entirely in **GDScript** (no `.cs` files yet, though the project is configured for the .NET/Mono build). The repo has a good human-facing `README.md` (setup, commit standards, collision layers, autoloads) but nothing tailored for working *with Claude Code*, no place to keep planning docs, and no tech-stack onboarding that walks a new contributor through the architecture. The user also wants confidence they can commit and push to the GitHub remote (`https://github.com/mitch-palczewski/zurd.git`).

This change adds:
1. A root `CLAUDE.md` so Claude Code auto-loads project conventions each session.
2. A `claude/plans/` folder to store plan files like this one.
3. A tech-stack onboarding document at `claude/ONBOARDING.md`.
4. A documented, verified path to authenticate and push via the already-installed `gh` CLI.

**Decisions locked in (from user):** root `CLAUDE.md` only (not `claude/claude.md`); still create `claude/plans/`; authenticate git with `gh auth login`.

## What exists today (from exploration)

- **Engine/stack:** `project.godot` → `config/features=PackedStringArray("4.7", "Forward Plus")`, `[dotnet] project/assembly_name="zurd"`, viewport 1920×1080, stretch `canvas_items`/`expand`.
- **Entry flow:** main scene = `res://scenes/ui/loading_screen/boot.tscn` (`uid://bhphi872t6fdt`) → `boot.gd` calls `SceneChanger.change_scene(initial_scene_path)` → main menu → `SceneChanger.change_scene_async(world_scene_path)` → `toroidal_world.tscn` (extends `base_world.tscn`).
- **Autoloads (registered in `project.godot`):** `EventBus` (`scripts/autoload/event_bus.gd`, currently just a stub/commented signal), `SceneChanger` (`scripts/autoload/scene_changer.gd`, threaded async scene loading).
- **Key systems:** `scripts/import/glb_physics_importer.gd` (`@tool EditorScenePostImport`, auto-generates mesh/collider/static/rigid `.tscn` per imported `.glb`, assigns collision layers 1/3); `scripts/utils/toroidal_utils.gd` (world-wrap math); `scripts/world/scene_spawner.gd` (`class_name SceneSpawner`); `scenes/world/toroidal_world.gd` (wraps RigidBody3D/CharacterBody3D at bounds).
- **Input map:** `move_up/down/left/right` bound to W/S/A/D.
- **Git state:** remote `origin` = the mitch-palczewski repo; local `main` tracks `origin/main` and is in sync; only untracked file is `zurd.code-workspace`. Credential helper = `manager` (Git Credential Manager). `gh` CLI **2.96.0 is installed**. `git ls-remote origin` succeeds (read access confirmed).

### Gotchas found (document these; do NOT fix in this task)
- `scenes/ui/loading_screen/boot.gd:2` default `initial_scene_path` = `res://scenes/ui/menus/main_menu/main_menu.tscn` but the real file is `res://scenes/ui/menus/main_menu.tscn` (extra folder segment). Works only if overridden in the Inspector — flag as a likely bug.
- `scripts/autoload/scene_changer.gd` references a global `LoadingScreen` (e.g. `LoadingScreen.show_screen()`), but `LoadingScreen` is **not** registered under `[autoload]` in `project.godot` (only `EventBus`, `SceneChanger` are). Flag as a gap.
- Indentation is inconsistent: `glb_physics_importer.gd` uses **spaces**, most other `.gd` files use **tabs**. GDScript convention is tabs; `.editorconfig` only sets charset, not indent.

## Files to create

```
CLAUDE.md                     # NEW – Claude Code project guidance (root, auto-loaded)
claude/
  ONBOARDING.md               # NEW – tech-stack onboarding + localhost dependencies
  plans/
	.gitkeep                  # NEW – keeps the empty plans folder tracked
	lets-create-a-claude-*.md # this plan, copied in during implementation
```

### 1. `CLAUDE.md` (repo root) — Claude Code guidance
Concise, agent-facing. Sections:
- **Project**: one-liner on what zurd is; link to `README.md` and `claude/ONBOARDING.md` instead of duplicating.
- **Stack & versions**: Godot **4.7 .NET edition**, GDScript, Forward+. Note the project is currently pure GDScript even though `.NET` is configured.
- **How to run**: open in the Godot editor and press Play (F5) / play current scene (F6); main scene is `boot.tscn`. No CLI build/test loop — there is no npm/dotnet test harness. (If headless verification is ever needed: `godot --headless --path . --quit` to import; note this requires the Godot binary on PATH.)
- **Repo layout map**: `scenes/` (world, ui, objects, characters), `scripts/` (autoload, import, utils, world), `assets/`, `sandbox/` (throwaway/playtest scenes — `test_*`), `data/`.
- **Conventions Claude must follow**:
  - Commit message format from README: `tag(scope): description` with tags `feat|fix|docs|asset|tool|refactor`.
  - GDScript style: **use tabs** for indentation (match the majority of files); use `class_name` + typed vars/returns as existing scripts do; use `push_warning`/`push_error` not `print` for diagnostics.
  - Collision layers (from README table): 1 Environment, 2 Player, 3 Objects, 4 Enemies, 5 UI.
  - Autoload globals available everywhere: `EventBus`, `SceneChanger`.
  - `.import`, `.uid`, and generated `scenes/objects/{mesh,collider,static,rigid}/*` files come from the importer — don't hand-edit generated scenes; re-import the `.glb` instead.
  - Don't edit `.godot/` (gitignored) or commit `.vscode/`.
- **Attribution footer** for commits/PRs (per session policy).
- Short "Known gaps" note pointing at the three gotchas above.

### 2. `claude/ONBOARDING.md` — tech-stack onboarding (human-facing)
Audience: a new contributor who may be new to Godot. Sections:
- **What you're building**: brief game concept (pull from README).
- **The tech stack explained**: Godot 4.7 .NET edition (why .NET: enables C# even though code is GDScript today); GDScript basics; scenes vs scripts vs resources (`.tscn`/`.gd`/`.tres`); autoloads/singletons; the Forward+ renderer.
- **Dependencies to run on localhost** (the core of the "investigation"):
  | Dependency | Why | Notes |
  |---|---|---|
  | **Godot Engine 4.7 – .NET/Mono build** | The editor *is* the runtime; "localhost" = pressing Play in the editor | Version must match `config/features` (4.7). Download the **.NET** variant, not standard. |
  | **.NET SDK** | Required by the Godot .NET build to load/run | Latest LTS SDK; needed even though there are no `.cs` files yet |
  | **VS Code** (or another IDE) | Script editing + git/GitHub integration | Optional: Godot Tools + C# extensions |
  | **Git + GitHub account with repo access** | Clone/commit/push | See git section below |
  - Note: there is **no** package manager step (no `npm install`, no `dotnet restore` needed for the current GDScript-only state) — assets and scripts are committed directly.
- **First run, step by step**: clone → open folder in Godot .NET editor via *Import* → let it reimport assets → press Play → boot → main menu → start world. Controls: WASD.
- **Architecture tour**: entry flow (boot → menu → world), the two autoloads, the GLB physics importer pipeline (drop a `.glb` in `assets/models/` → generates mesh/collider/static/rigid scenes), toroidal world wrapping, `sandbox/` as the playtest area.
- **Known gaps / gotchas**: the three items listed above, so a newcomer isn't blocked.
- **Committing your work**: pointer to the git section / README commit standards.

### 3. `claude/plans/`
- Create with a `.gitkeep`. This plan file will be copied here during implementation so plans live in the repo.

## Git push & commit setup (investigation result + steps to document)

**Finding:** Push capability depends on two independent things — (a) credentials on this machine, (b) the GitHub account having write access to `mitch-palczewski/zurd`. Read access already works (`git ls-remote` succeeded). `gh` CLI 2.96.0 is installed, so `gh auth login` is the chosen path and it also configures Git Credential Manager automatically.

Document (and, at implementation time, optionally run interactively with the user) these steps:
1. **Authenticate:** `gh auth login` → GitHub.com → HTTPS → "Login with a web browser" (or paste a PAT). This stores credentials via the credential helper so plain `git push` works afterward.
2. **Confirm identity & scopes:** `gh auth status`.
3. **Confirm write access to the repo:** `gh repo view mitch-palczewski/zurd --json viewerPermission` — expect `WRITE`, `MAINTAIN`, or `ADMIN`. If it shows `READ`, the user must be added as a collaborator by the repo owner (Mitch) — a PAT cannot grant permission the account lacks. Call this out explicitly.
4. **Dry-run the push safely:** `git push --dry-run origin main` (no changes pushed; proves auth + permission end-to-end).
5. **If preferring a PAT instead of browser:** create a *fine-grained* PAT scoped to the `zurd` repo with Contents: Read/Write, then use it as the password on first `git push` (Credential Manager caches it).

> Note on the PAT the user offered to generate: with `gh auth login`, a manually generated PAT is optional. It's only needed for the non-interactive / PAT-based path (step 5) or CI. The plan proceeds with `gh auth login`.

The `zurd.code-workspace` untracked file: decide whether to commit it (VS Code multi-root workspace) or gitignore it — mention, but not part of this task unless the user asks.

## Verification

1. **Structure:** `CLAUDE.md` exists at root; `claude/ONBOARDING.md` and `claude/plans/.gitkeep` exist. `git status` shows them as new/untracked.
2. **Claude auto-load:** starting a fresh Claude Code session in this repo surfaces `CLAUDE.md` context (conventions, run instructions).
3. **Onboarding accuracy:** every path/command in `ONBOARDING.md` is verified against the repo (e.g. main scene `boot.tscn`, autoload names, importer output dirs). Optionally validate that a Godot 4.7 .NET editor opens the project without import errors.
4. **Git push:** `gh auth status` shows logged in; `gh repo view mitch-palczewski/zurd --json viewerPermission` returns a write-capable role; `git push --dry-run origin main` succeeds. A real commit + push of the new docs (using a `docs:` message) confirms end-to-end — only when the user approves pushing.

## Out of scope (note, don't do unless asked)
- Fixing the `boot.gd` main_menu path bug, registering `LoadingScreen` as an autoload, or normalizing indentation. These are documented as known gaps only.
