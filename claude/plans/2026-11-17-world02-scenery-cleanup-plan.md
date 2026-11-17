# World 2 scenery cleanup plan

Status: **approved 2026-11-17** with the answers below; "Changes after the answers" overrides the
sections above where they differ.

## Goal

Tidy the scenery added quickly while prototyping `zurd_world02`, and give it a system that is
easy to keep building on:
- clear folders and names;
- materials saved as files instead of buried inside scenes;
- the world grouped into named areas that can be moved as one;
- scenery that stays put when the terrain moves, and that the ship can bump into.

The world should look the same afterwards; nothing moves in world space.

## What's there now (2026-11-17)

**Models** (`assets/models/terrain/`): `circle_grid`, `flute_section`, `mega_tree`,
`reflecting_pool_01`. This folder isn't one the importer knows, so it makes only the shared
meshes, no scenes. Each model is wrapped by hand in a scene in `scenes/scenery/`. That works well,
but it isn't written down anywhere. `assets/models/scenery/` (the importer's "make a static scene"
folder) is now empty.

**Scenery scenes** (`scenes/scenery/`): `circle_grid`, `flute_section`, `mega_tree`,
`reflecting_pool`, `sky_canopy`, and `bush_stock_pink`.
- `bush_stock_pink` re-colours the launchable `Bush_Stock_01` model; its root is still called
  `Bush_Stock_01`.
- `circle_grid` and `bush_stock_pink` keep their materials inside the scene, so they can't be
  shared or found.
- `scenes/scenery/` isn't listed in CLAUDE.md's layout table.

**Materials** (`assets/materials/`, flat): world materials (`checker`, `reflecting_pool_basin`,
`reflecting_pool_basin02` (used by the flute sections), `reflecting_pool_water`, `mega_tree`,
`sky_canopy`) sit beside game materials (`sculpture_*`) and old-world ones (`terrain`, `water`,
`golf_terrain`).
- `materials/imported/` holds the Ground103 texture set (6 JPGs) and an unused material made from
  it.
- `assets/textures/` is empty.
- The dark floor under the mega trees is a material inside `terrain02.tscn`. It uses the
  **DirectX** normal map; Godot expects the OpenGL one (`NormalGL`), so its bumps are lit from the
  wrong side.

**`terrain02.tscn`**:
- Nodes are named `MeshInstance3D`, `MeshInstance3D3`, `Node3D`…`Node3D5`, `megatree`, `scenery/bush`.
- Groups are by type, not by area: the reflecting pool, its 12 flute sections (four copied groups
  around the pool) and 8 arches form one court; the mega trees, their canopy and the dark floor
  form one grove; there's a bush cluster west and three circle grids south.
- **Nothing in it is solid except the arches and mega trees.** The 10 km floor has no collider, so
  the ship sinks through it (now that the altitude limits are off), launched objects fall through,
  and Zurds find no ground to keep clear of.
- `zurd_world02` places the whole terrain at **Y −332**. The trunk fade uses **world** heights,
  so moving the terrain shifts where the trunks fade.

**Leftovers**: `scenes/objects/static/reflecting_pool_01_static.tscn` was generated when the pool
model was in `scenery/` and is used nowhere. `Arch_01_static`, `Archway_static` and
`Crocodile_01_static` were generated the same way (their models are now in `objects/`) but are
still used: the arches by `terrain02`, the others by `sandbox/world/test_ground.tscn`.

## Proposed changes

### 1. Folders and names
- **Models:** keep `assets/models/terrain/` and write down its role in `assets/models/README.md`:
  *"world pieces you wrap in your own scene in `scenes/scenery/` (mesh only; no generated
  scene)"*. Optional rename, see question 1.
- **Materials:** new `assets/materials/scenery/` for everything the world's scenery uses:

  | Now | Becomes |
  |---|---|
  | `materials/checker.tres` | `scenery/floor_checker.tres` |
  | `materials/reflecting_pool_basin.tres` | `scenery/pool_basin.tres` |
  | `materials/reflecting_pool_basin02.tres` | `scenery/flute_basin.tres` |
  | `materials/reflecting_pool_water.tres` | `scenery/pool_water.tres` |
  | `materials/mega_tree.tres` | `scenery/mega_tree.tres` |
  | `materials/sky_canopy.tres` | `scenery/sky_canopy.tres` |
  | inside `terrain02.tscn` (dark floor) | `scenery/grove_floor.tres`, switched to the GL normal map |
  | inside `bush_stock_pink.tscn` | `scenery/bush_pink.tres` |
  | inside `circle_grid.tscn` | `scenery/circle_grid.tres` |
  | `materials/imported/Ground103_1K-JPG.tres` (unused) | `scenery/ground103.tres` |

  Game materials (`sculpture_*`) and old-world ones stay where they are.
- **Textures:** the Ground103 JPGs move to `assets/textures/ground103/`, and `materials/imported/`
  goes away.
- Every file that points at a moved file gets its path updated, and the editor's UIDs are kept,
  so nothing goes missing. The moves happen with the editor closed, then one headless import
  run so the moved textures are re-imported.

### 2. Scenery scenes
- `bush_stock_pink.tscn`: root renamed to `BushStockPink`; uses `bush_pink.tres`.
- `circle_grid.tscn`: uses `circle_grid.tres`.
- **Solid scenery** (question 3): a small reusable script, `scenes/scenery/solid_scenery.gd`. Put it
  on a scenery scene's root and, in the game, it gives each mesh under it a static trimesh
  collider on layer 1 (Environment). Shapes are built once per mesh and shared by every copy, so
  12 flute sections cost one shape. It goes on `flute_section`, `circle_grid` and
  `bush_stock_pink`. The green bushes, which use the raw model, get a `bush_stock.tscn` wrapper
  with it too. The mega trees keep their import-generated collider; the reflecting pool keeps its
  own.

### 3. `terrain02.tscn` grouped by area
```
Terrain02
├─ Floor            (checker plane; solid, question 2)
├─ PoolCourt        (set piece, question 4)
│   ├─ ReflectingPool
│   ├─ FluteSections / North, South, West, East
│   └─ Arches
├─ MegaTreeGrove    (set piece)
│   ├─ GroveFloor
│   ├─ Trees (10 mega trees)
│   └─ SkyCanopy
├─ BushGarden
└─ CircleGrids
```
- Set pieces are their own scenes in `scenes/world/set_pieces/` (`pool_court.tscn`,
  `mega_tree_grove.tscn`), so a whole area moves, copies or goes into another world as one node.
- Every object keeps its exact world position. Group transforms are kept, not baked, so nothing
  shifts by rounding.

### 4. Trunk fade measured from each tree's foot
`sky_fade.gdshader` measures `fade_start` / `fade_end` in metres **above the tree's own foot** (its
origin) instead of world height. Moving the terrain, a grove or a single tree then keeps the fade
the same. Current values convert so the look doesn't change: the trees' feet are at world Y
≈ −312, so 250 → 562 and 1600 → 1912.

### 5. Leftovers
- Delete `scenes/objects/static/reflecting_pool_01_static.tscn` (unused generated file).
- Keep `Arch_01_static`, `Archway_static`, `Crocodile_01_static`, which are still used. Note in the
  models README that they're orphans (their models moved to `objects/`) and won't update on
  reimport.

### 6. Docs
- `assets/models/README.md`: the `terrain/` folder and the wrap-a-model workflow.
- CLAUDE.md: `scenes/scenery/`, `scenes/world/set_pieces/`, `assets/materials/scenery/` and
  `assets/textures/` in the layout table; world02's areas; solid scenery.

## Files touched

Moved and renamed: the 7 materials and 7 texture files above.
New: 3 materials, `solid_scenery.gd`, `bush_stock.tscn`, 2 set-piece scenes, 1 test.
Edited: `terrain02.tscn`, the 6 scenery scenes, `sky_fade.gdshader`, `mega_tree.tres`, the models
README, CLAUDE.md.
Deleted: `reflecting_pool_01_static.tscn`, `materials/imported/`.

## Steps

1. Folders, material and texture moves, path updates, headless import. Then the tests and
   screenshots (below) to show nothing changed.
2. Saved materials, scenery scene fixes, the trunk-fade change.
3. Solid scenery and the solid floor.
4. Set pieces and the regrouped `terrain02`.
5. Docs; full test run.

## Risks

- **Broken references after moves.** Text paths and UIDs both get updated. Checked by the unit test
  that loads every scene and resource, plus a grep for old paths.
- **Moved textures need re-importing** before the game finds them: one
  `--headless --import` run with the editor closed (the editor would do the same on open).
- **The editor overwriting hand edits:** only if it's open with these scenes. I'll check it's
  closed first.
- **Trimesh colliders cost physics time** where many objects touch them. Flute sections and grids
  are simple shapes; any piece can opt out by removing the script.
- **A solid floor changes play:** objects launched downward now land and pile up on it instead of
  falling forever (Zurds still eat them).

## Verification

- Before/after screenshots of `zurd_world02` from fixed cameras (pool court, grove, bush garden,
  circle grids). The static parts should match pixel for pixel. The canopy changes over time, so
  it's checked by eye.
- Full test suite. New `tests/unit/test_solid_scenery.gd`: a scene with the script gives every mesh
  a collider on layer 1, and two copies share one shape.
- A game-mode check that the ship stops on the floor and on a flute section.

## Open questions

1. **Model folder name:** keep `assets/models/terrain/` (recommended: no churn; just documented),
   or rename it to something that doesn't clash with the world "terrain" scenes, e.g.
   `assets/models/set_pieces/`? Renaming means moving the models and re-importing them.
2. **Solid floor:** should the 10 km floor stop the ship, objects and Zurds (recommended)? If yes,
   should the ship also keep its 4 m `ground_clearance` hover above it (it will, automatically,
   once there's ground under it)?
3. **Solid scenery:** should the flute sections, circle grids and bushes be solid (recommended)?
   Any that should stay ghost-like?
4. **Set pieces:** turn the pool court and the mega tree grove into their own scenes (recommended),
   or just regroup and rename the nodes inside `terrain02.tscn`?
5. **World height:** keep `Terrain02` at Y −332 in `zurd_world02` (the ship starts 332 m above the
   floor), or move the terrain to 0 and start the ship higher? Recommended: keep, since step 4
   makes the fade independent of it.
6. **Ground103:** keep the unused Ground103 material and colour texture (moved, recommended), or
   delete them?
7. **Material names:** OK with the renames in the table (e.g. `reflecting_pool_basin02` →
   `flute_basin`)?
8. **Leftover:** delete `reflecting_pool_01_static.tscn` (recommended)?

## Answers (2026-11-17)

1. Rename the models folder to `set_pieces/`. 2. The floor is solid. 3. Flute sections, circle
grids and bushes are solid. 4. Yes, areas get their own scenes. 5. Move the terrain to 0 and start
the ship higher. 6. Delete Ground103 files that aren't used. 7. Better names welcome. 8. Delete
the leftover.

## Changes after the answers

- **Models:** `assets/models/terrain/` → `assets/models/set_pieces/` (moved with their `.import`
  files, so the UIDs stay; re-imported headless). The importer needs no change: it's "another
  folder" (mesh only).
- **Area scenes** go in `scenes/world/areas/` (`pool_court.tscn`, `mega_tree_grove.tscn`), not
  `set_pieces/`, so "set piece" only means the models.
- **World height:** `Terrain02` moves from Y −332.18 to 0 in `zurd_world02`, which overrides the
  ship's start to Y 332.18 and the cloud band (`MassManager.atmosphere_y_range`, world heights)
  from 150–200 to 482.18–532.18, so the ship, the clouds and the floor keep their spacing. That
  needs `GameSystems` marked editable in `zurd_world02`.
- **Ground103:** only the normal map is used (by the grove floor, switched to the GL version).
  It moves to `assets/textures/ground103_normal.jpg`. The other five textures and the material are
  deleted.
- **Trunk fade:** heights are measured above the trunk mesh's lowest point (`foot_offset`, in the
  model's own units, −1.873 for `mega_tree.glb`); the foot shade gets a start and end height, so
  the look is unchanged. The fade line's noise is sampled at (world X, height above foot,
  world Z), so it doesn't change when the terrain moves either.
- **Floors:** the floor and the grove floor become `StaticBody3D`s with thin `BoxShape3D`s, not
  world boundaries, because Jolt limits a world boundary to 2 km and the floor is 10 km.
- **Names:** `mega_tree.tres` → `mega_tree_trunk.tres`; scenery scene roots are renamed to
  PascalCase (`FluteSection`, `MegaTree`, `CircleGrid`, `BushStock`, `BushStockPink`).
  `bush_stock_pink.tscn` builds on the new `bush_stock.tscn`.

## As built (2026-11-17)

- Everything above, in one pass, with the editor closed; two `--headless --import` runs (after the
  moves, and to register the new scenes' UIDs).
- Flute groups by where their sections sit (−Z north): `Node3D` → North, `Node3D2` → South,
  `Node3D3` → West, `Node3D4` → East. Bushes are `Bush`…`Bush4` and `PinkBush`, `PinkBush2`; trees
  `MegaTree`…`MegaTree10`; arches `Arch`…`Arch8`.
- `zurd_world02`'s root is renamed `ZurdWorld02`.
- **SolidScenery keeps each shape as meta on its mesh, not in a static dictionary.** The dictionary
  kept every mesh alive after its scene was freed: a slow leak across world changes, and the
  headless (dummy) renderer logged `Parameter "material" is null` whenever such a scene was freed.
  The real renderer didn't.
- Verification:
  - Before/after screenshots from six terrain-relative cameras, with time-driven shader motion
    frozen. Pool court, bushes, grids and the overview match (mean difference ≤ 0.0004). The grove
    differs on the grove floor (the normal-map fix) and along the trunks' fade line (its noise is
    now sampled from the foot), as expected.
  - In the game, the ship sinks to Y 4.1 over the open floor (top 0.1 + 4 m clearance) and stops
    on a flute section instead of passing through it.
  - Full suite: 116 tests pass, including the 3 new ones in `tests/unit/test_solid_scenery.gd`.
