# Solid cloud look plan

Status: **approved 2026-11-17**: about 90% opaque, glow cut down, darker cool lines.

## Goal

Make clouds read as solid shapes from far away (Cloud-Formation Design Doc §4.2, "Look, later"):
- a more solid body, shaded by the light so its form shows;
- darker, more solid undersides, like real cumulus;
- subtle lines along each model's ridges and outline that blend into the cloud.

The objects stay recognisable.

## What's there now

`sculpture_cloud.gdshader` is white and 55% see-through, with a strong glow (`cloud_glow` 0.35)
and a bright rim. The glow flattens the shading, so from far away a cloud is a white blob whose
shape only shows at its outline. There are no edge lines.

## Approach

### 1. A more solid body (`sculpture_cloud.gdshader`)
- Mostly opaque (`cloud_alpha` from 0.55 to about 0.9; question 1), still writing depth as now.
- Lit like the puffs: soft half-Lambert light (white on the lit side, a cool blue-grey in shadow)
  instead of the glow. A little glow stays so it never goes dull grey, and the warm rim stays as
  a thin silver lining.
- The white burst at forming is unchanged.

### 2. Darker, more solid bottoms
- Each cloud's own material copy gets `cloud_middle_y` and `cloud_radius` (world) every frame from
  `CloudSky`, via a new `SculptureMass.set_cloud_bounds()`.
- The lower a fragment sits in the cloud, the more it shifts toward `base_color` (a soft grey) and
  toward fully opaque (`base_strength`, `base_height`). World height, so it stays at the bottom
  however the cloud tumbles.
- The puffs share one material, so they keep their own down-facing shade (their `light()` already
  does that).

### 3. Ridge and outline lines
- **Ridges:** lines along each object's sharp edges, where faces meet at more than
  `ridge_angle` (about 35°), plus open edges. This reuses the pool's edge finder and its screen-width
  line mesh. They're built when the cloud forms, kept on each mesh as meta (one per model, shared
  like `SolidScenery`'s shapes), and hung under each object's mesh, so they swell, tumble and grow
  with it.
- **Subtle and blended:**
  - thin (about 1.5 px);
  - a slightly darker, cool tint of the cloud's own colour, at partial strength (`ridge_color`,
    alpha about 0.35), drawn see-through;
  - fading out on edges that are only a few pixels long on screen, so a far-away cloud doesn't
    turn into a scribble of tiny lines;
  - depth-tested, so only visible ridges show.
- **Outline:** a gentle darkening of the body toward its silhouette (a reversed rim), in the same
  tint, so smooth curves get an outline too. Strength `outline_shade`, small.
- **Shared code:** the pool's line vertex code moves into `edge_outline.gdshaderinc`, used by the
  pool's opaque `edge_outline.gdshader` and a new see-through `cloud_ridges.gdshader`.
  `ReflectingPool.find_feature_edges` / `build_outline_mesh` move to a static helper
  `scripts/utils/edge_lines.gd` (the pool calls it). The pool looks exactly as before.

## Files

| File | Change |
|---|---|
| `assets/shaders/sculpture_cloud.gdshader` | solid, lit body; bottoms; outline shade |
| `assets/shaders/edge_outline.gdshaderinc` | new: the line vertex code |
| `assets/shaders/edge_outline.gdshader` | uses the include (same look) |
| `assets/shaders/cloud_ridges.gdshader`, `assets/materials/cloud_ridges.tres` | new |
| `scripts/utils/edge_lines.gd` | new: edge finder and line mesh, moved from the pool |
| `scenes/scenery/reflecting_pool.gd` | uses `EdgeLines` |
| `scenes/sculpture/sculpture_mass.gd` | `set_cloud_bounds()` |
| `scenes/sculpture/cloud_sky.gd` | ridges in `_dress`; bounds every frame; `ridge_angle`, `ridge_material` |
| `tests/unit/test_reflecting_pool.gd` | points at `EdgeLines` |
| `tests/unit/test_cloud_sky.gd` | ridges: built once per model, on each object |
| Cloud-Formation Design Doc §4.2, CLAUDE.md | updated |

## Risks

- **Busy models** (gargoyles) have many sharp edges. The short-edge fade and the low alpha keep
  them calm; `ridge_angle` thins them further.
- **More opaque clouds hide what's behind them more**: that's the point, but big clouds will block
  more sky.
- **The pool's outline must not change:** checked with before/after screenshots.

## Verification

- Before/after screenshots: the pool (unchanged), and a 20× cloud formed in `zurd_world02`, close
  and from the play area.
- Tests: the pool's edge tests still pass through the helper; ridges are built once per model and
  hang under each object's mesh. Full suite.

## Questions

1. **How solid:** body about 90% opaque with fully solid bottoms (recommended), or fully opaque
   all over?
2. **Glow:** cut it to a little (recommended, so the light shapes the form), or keep it as is?
3. **Line colour:** a slightly darker cool grey (recommended, reads like shading), or a lighter warm
   tint (reads like highlights)?

## As built (2026-11-17)

- As planned: the lit, ~90% opaque body with a little glow, darker solid bottoms by world height,
  a soft silhouette darkening, and the ridge lines (1.5 px, alpha 0.35, cool tint; short edges
  fade). The pool's outline now uses `edge_outline.gdshaderinc` and `EdgeLines`, and is pixel for
  pixel unchanged (before/after screenshots of six views).
- **Added: the details are worked out off the main thread.** Measured on the dev machine:
  - Finding a model's ridges took 25–160 ms, and placing puffs 10–20 ms more, per model. Most of
    that is reading the triangles back from the GPU and looping over them in GDScript.
  - A cloud of six new models stalled the game by about 180 ms at the cloud moment.
  - Now each model is read once (one per frame, a few ms), and a `WorkerThreadPool` task finds its
    ridges and builds its puff surface table. Both are cached as meta on the mesh.
  - The ridges and puffs fill in during the white burst. With them on, the longest frame around a
    cloud forming is the same as with them off.
  - Puffs now hang under each object mesh and work in its own space (`CloudPuffs.build` takes the
    surface table).
- Tests: 125 pass. They now check that ridges are found once per model, that the puff surface
  table holds the area, and, in the world, that a cloud's ridges and puffs arrive.
