# Performance settings — build plan

Status: **built (2026-11-20); the Low/Medium tuning waits on questions 13–15** (see Measurements)

## Goal

Let the game run smoothly on the development machine (Ryzen 5 with integrated graphics) and still look
its best on a decent consumer GPU. Add a **Performance** section to the main menu: one quality preset
plus a few individual settings, saved per computer like the controller config. Show an optional
frame-rate counter so the effect of each setting can be seen.

## Where the GPU time goes today

All rendering settings are Godot defaults (nothing set in `project.godot`):

| Cost | Where | Notes |
|---|---|---|
| Full-resolution 3D at 1900×1060 or the window size | root viewport | The biggest lever on an integrated GPU: rendering 3D at 0.67× scale is about half the pixels. |
| The pool's planar reflection renders the scene a second time | `PlanarReflection` (`resolution_scale` 0.5, only while the water is on screen) | A second camera pass, with shadows. |
| Directional shadows: 4 splits, 4096 atlas, soft filtering | `environment.tscn` light, project defaults | Each split re-renders the shadow casters. |
| Sky canopy: 4 stacked transparent shells with domain-warped noise | `SkyCanopy` (`layer_count` 4, `resolution` 64) | Large transparent overdraw when looking up at the grove. |
| Clouds: lit shader, ridge lines, puff MultiMeshes, wisps | `sculpture_cloud.gdshader`, `CloudPuffs`, `CloudWisps` | Grows with the number of clouds, which never despawn. |
| Camera far plane 12 km | `player_ship.tscn` | Keeps the far side of the gyre in view; mostly costs culling, not fill. |

## Proposed settings

| Setting | Choices | What it changes |
|---|---|---|
| **Preset** | Low · Medium · High · Custom | Sets all the settings below; changing any one switches the preset to Custom. |
| **3D resolution** | 50% · 67% · 75% · 85% · 100% | `Viewport.scaling_3d_scale` on the root viewport, upscaled with FSR 1 (sharpened). The menus and HUD stay full resolution. |
| **Shadows** | Off · Low · High | Off: the sun casts none. Low: 2 splits, 2048 atlas, hard edges, shorter distance. High: today's look. |
| **Reflections** | Off · Low · High | Covers every reflection in the game: today every `PlanarReflection` (the pool), later any new reflecting surface or screen-space reflections. Off: water shows its colour only, as in the editor. Low: 0.33 scale, no shadows in the mirror. High: today's 0.5. |
| **Sky canopy** | Simple · Full | Simple: 2 shells instead of 4 (open question 4). |
| **Anti-aliasing** | Off · FXAA · MSAA 2× | Default off; FXAA is nearly free. |
| **Frame limit** | VSync · 30 · 60 · Unlimited | VSync is today's behaviour. |
| **Show FPS** | on / off | A small corner label: fps and frame time. Also toggled in game with **F3**. |

The presets (starting points, to be tuned on your machine; see Verification):

| | Low | Medium | High |
|---|---|---|---|
| 3D resolution | 67% | 100% | 100% |
| Shadows | Low | High | High |
| Reflections | Off | Off | High |
| Sky canopy | Full (Simple only if measured costly) | Full | Full |
| Anti-aliasing | Off | FXAA | FXAA |
| Frame limit | VSync | VSync | VSync |
| Default for | (none) | integrated GPUs | everything else |

**Medium** is today's look without reflections, the way the game ran well on the integrated GPU
before the pool arrived. **Low** is the fallback for weaker machines.

**First launch:** if there is no saved config, the game picks Medium when the GPU is integrated
(`RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU`), else High.

**Sky canopy:** measured first (Verification). If it costs little on this machine, the canopy
setting is left out and the canopy always shows in full. Otherwise the setting stays, and Low uses
Simple (2 layers). Either way it is playtested and revisited.

## Design

- **New autoload `Graphics`** (`scripts/autoload/graphics.gd`), the same pattern as `Controllers`:
  - holds the current settings;
  - `set_preset(id)`, `set_setting(name, value)`, `get_setting(name)`, signal `settings_changed`;
  - saves to `user://graphics_config.json`; `config_path` / `set_config_path(path)` so the tests never
    touch `user://`.
- **Applying the settings:**
  - Viewport-wide settings (3D resolution, anti-aliasing, frame limit, the shadow atlas size and filter) go on the root viewport, `RenderingServer` and `DisplayServer`.
  - Per-node settings reach scenes as they load: the autoload watches `SceneTree.node_added` and adjusts each `DirectionalLight3D`, `PlanarReflection` and `SkyCanopy` it sees. On a change it re-applies them to the ones already in the tree. So no world or scenery scene needs editing, and a new world picks the settings up for free.
- **Original values:** each node's values from its scene are stored as meta when the node is first seen. "High" restores those values instead of hard-coding today's numbers, so tuning a scene in the editor still counts.
- **`PlanarReflection`**: add a small `set_quality(...)` (or use its existing `enabled` / `resolution_scale`, plus turning off shadows on its mirror camera through its own environment or light mask). This is the one script change outside the new files.
- **`SkyCanopy`**: it already rebuilds when `layer_count` changes, so Simple sets `layer_count` to 2 on the instance at runtime. Nothing is saved to the scene.
- **Menu:** a *Performance* section in `main_menu.tscn` under the Controllers section, built in code like the controller list. Each row is a label plus an `OptionButton` (or a `CheckBox` for Show FPS). Changes apply at once, so the menu's background (if any 3D shows) and the next world use them.
- **FPS label:** a `CanvasLayer` owned by the autoload, so it shows on every screen; F3 is a new input action `toggle_fps`.

## Files to touch

| File | Change |
|---|---|
| `scripts/autoload/graphics.gd` | **new**: the settings, presets, save/load, applying them |
| `project.godot` | register the `Graphics` autoload; add the `toggle_fps` action (F3) |
| `scenes/ui/menus/main_menu.gd`, `main_menu.tscn` | the Performance section |
| `scenes/scenery/planar_reflection.gd` | a quality hook (resolution, mirror shadows) |
| `tests/unit/test_graphics.gd` | **new**: unit checks (below) |
| `tests/scene/test_graphics_in_world.gd` | **new**: scene checks (below) |
| `CLAUDE.md`, `tests/README.md`, `claude/ONBOARDING.md` if it lists autoloads | document the autoload, the config file and the menu section |

## Steps

1. The `Graphics` autoload with presets, save/load and the viewport-wide settings, plus its unit tests.
2. The node hooks (light, reflection, canopy) and the scene tests.
3. The main-menu section and the FPS label (F3).
4. Measure the presets on this machine in `zurd_world02` (below) and tune the Low/Medium numbers.
5. Docs.

## Tests (added to `tests/`)

Unit (`test_graphics.gd`, with its own config path):
- each preset sets every setting to its listed choice;
- changing one setting switches the preset to Custom;
- settings saved and loaded again come back the same;
- a missing or broken config file falls back to the default preset without errors;
- an unknown value in the file is ignored for that setting only.

Scene (`test_graphics_in_world.gd`, in `zurd_world01`, which has the pool):
- Low turns off the sun's shadows and the pool reflection and sets the root viewport's 3D scale to 0.5;
- High restores the scene's own values;
- a light added after the setting changed still gets it.

Every test restores the settings it changed, so other tests see the defaults.

## Verification

- The full suite passes.
- A windowed harness (scratchpad, not committed) on this machine: first time reflections on vs. off and canopy Full vs. Simple with everything else the same, then fly the same 30 s path through
  `zurd_world02` (pool, grove and canopy, a few clouds) under each preset and print the average and
  worst frame times. Screenshots of each preset from the same spot, to check Low still reads well.
  Report the numbers to you before tuning.

## Risks

- **`project.godot` while the editor is open:** the editor may write its own copy back over a hand
  edit. Workaround: add the autoload and the action, then reload the project in the editor (or close
  it first). I'll say so when I get there.
- FSR 1 at 50% blurs the thin purple pool outline and the cloud ridge lines (both are screen-width
  lines). If that looks bad, Low could use 67%, or `bilinear` with a sharper `fsr_sharpness`.
- Integrated-GPU detection isn't reliable on every driver; the first-launch choice is only a default.
- The projector rig (3 walls) may later need its own resolution handling; this plan only covers the
  single window.

## Answered (2026-11-20)

1. Preset dropdown **and** individual settings.
2. Main menu only, plus F3 in game. A pause menu (Esc on keyboard, Start on a controller, the PC
   convention) is separate work for a later plan.
3. The reflection setting is general: **Reflections**, covering every reflection, not just the pool.
4. *(open, see 9)*
5. Integrated GPUs start with **reflections off** (see 10 for the rest).
6. F3 is fine, keyboard only.
7. Saved per computer in `user://graphics_config.json`.
8. Explained; see 11.

Mitch expects the reflection to be most of the cost. The measurement in Verification checks that
first: reflections on vs. off with everything else the same.

9. Sky canopy: keep it if it isn't a big cost. Measure it, playtest, and check back (see the Sky canopy note under the presets).
10. Integrated GPUs start on **Medium**: today's look with reflections off. Mitch's machine ran well
    before the reflections, and the models are small.
11. Frame limit stays as a setting; every preset uses VSync.
12. View distance, cloud detail and Zurd count are left out.

## As built (2026-11-20)

Built as planned, with these differences:

- **Reflections Low** renders the reflection at 0.66 of its own resolution (0.33 for the pool), with
  shadows still in the mirror. Godot has no switch for one viewport's sun shadows, and shadows
  measured at 2 ms or less. `planar_reflection.gd` is unchanged: the autoload sets its `enabled` and
  `resolution_scale`.
- **Shadows Low:** 2 splits, a 2048 map and hard edges. The shadow distance is unchanged.
- **The Performance panel** is built entirely in code by `main_menu.gd`, on the right of the screen;
  `main_menu.tscn` is unchanged (it was open in the editor). On the right, it doesn't make the
  centre column taller.
- **Frame limit:** 30 and 60 fps keep VSync on (no tearing). Unlimited turns VSync off.
- **The scene test adds the reflecting pool** to the test world: `zurd_world01` has no pool. The
  pool is only in `zurd_world02`'s `PoolCourt`; CLAUDE.md said `terrain.tscn` placed one, and is
  corrected.
- **Bug found while measuring:** a canopy rebuilds its shells when its setting changes, which freed
  nodes later in the list the settings were being applied to (script errors). Fixed. The canopy test
  now gives the canopy a tree, so it has shells to rebuild; the test fails without the fix.

## Measurements (2026-11-20)

Dev machine: AMD Radeon integrated graphics (Vulkan, Forward+), window 1900×1060. GPU time per frame
(main view plus the reflection while it renders), median of 3 rounds, VSync off. Four fixed views in
`zurd_world02`: the ship's start, over the pool, the grove from 1.2 km, and under the canopy.
16.7 ms is 60 fps. With VSync on a 60 Hz screen, a frame over 16.7 ms waits for the next refresh,
so the game falls toward 30 fps.

**What each feature costs** (one change at a time from today's look, which is 23–32 ms):

| Change | GPU time saved |
|---|---|
| Sky canopy hidden | 13–19 ms |
| Sky canopy 1 shell / 2 shells (of 4) | 10–13 / 6–8.5 ms |
| Canopy noise 7 layers instead of 10 (shader not changed; tested in memory) | 3–4 ms |
| 2 shells and 7 noise layers | 8.5–11 ms |
| Reflections off (only while the pool is on screen) | 5 ms |
| Reflection at 0.33 instead of 0.5 | 2 ms |
| Shadows off / Low | 0–2 / 0.5–1.5 ms |
| 3D resolution 67% / 50% (FSR) | 6–11 / 10–17 ms |
| FXAA | costs 1–2 ms |

The sky canopy is most of the cost, not the reflection: it fills much of the sky from almost
anywhere, and each shell runs 10 layers of 3D noise per pixel.

**The presets as built:**

| View | High | Medium | Low |
|---|---|---|---|
| Start | 22.9 ms | 23.5 ms | 11.3 ms |
| Pool | 26.9 | 21.2 | 10.3 |
| Grove | 25.9 | 26.0 | 12.7 |
| Under the canopy | 33.6 | 32.2 | 13.1 |

**Candidates for a retuned Medium** (Simple canopy, no reflections, no AA, full shadows):

| View | at 100% | at 85% | at 75% | Low (for comparison) |
|---|---|---|---|---|
| Start | 14.4 ms | 13.9 ms | 11.8 ms | 9.6 ms |
| Pool | 14.4 | 14.3 | 13.2 | 10.4 |
| Grove | 17.4 | 16.4 | 14.2 | 11.6 |
| Under the canopy | 24.4 | 21.2 | 17.3 | 13.6 |

Screenshots of each preset from the pool and the grove views: Low (67% with FSR, Simple canopy) still
reads well; the canopy keeps its look with 2 shells, a little softer.

## Open questions (tuning)

13. Medium as planned (today's look minus reflections) barely helps on this machine (21–32 ms),
    because the canopy is the cost. Which should integrated GPUs start on?
    - (a) **Low**: holds 60 fps everywhere with room to spare (10–14 ms).
    - (b) **A retuned Medium**: 75% resolution, Simple canopy, no reflections, no AA, full shadows.
      It holds 60 fps except right under the canopy (17 ms).
14. If (a): should Medium become "100%, Simple canopy, no reflections, no AA, full shadows" (14–24 ms),
    so it sits between Low and High?
15. A cheaper canopy shader would help every preset: 7 noise layers instead of 10 saves 3–4 ms
    (timed, not yet compared by eye: the finest layers add fine detail to the outline). That's a
    shader change, so it would be a small plan of its own. Worth doing?
