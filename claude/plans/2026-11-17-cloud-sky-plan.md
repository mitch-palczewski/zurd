# Cloud sky plan

Status: **approved 2026-11-17** (the user's go-ahead once the Cloud-Formation Design Doc questions
were answered; nothing open).

## Goal

Build Cloud-Formation Design Doc §4. A new cloud rises up and outward over 40 s, growing to 6× its
size. It then circles the play area with every other cloud in a slow gyre, in a thick zone
(1000–1550 m) at about the sky canopy's level. Clouds drift into one another and apart, but a
gentle push keeps them from staying overlapped. Each cloud bobs, tumbles slowly in any direction
and breathes. It's dressed with soft puffs on its objects, and small puffs come and go around it.
The objects stay recognisable. The same in every world.

## Design

**`CloudSky`** (new node in `game_systems.tscn`, `scenes/sculpture/cloud_sky.gd`) owns everything a
cloud does after forming, and holds the tunables (§4.4). It listens to `EventBus.cloud_formed`.

- Each cloud has a small state: where it formed, its age, its own radius, and its orbit (ring
  radius, height, angle).
- Every physics frame `step(delta)`:
  1. advances each orbit at `TAU / gyre_lap_time × (middle radius / radius)^gyre_shear`, so inner
     rings turn faster and clouds pass one another;
  2. pushes apart pairs of arrived clouds whose spheres overlap. The push changes their orbits
     (radius, height, angle; clamped to the ring and zone), so they part for good, gently
     (`push_speed`);
  3. places each cloud.
- **Rise:** a new cloud holds for `rise_delay`, then over `rise_time` moves from where it formed to
  its orbit point. The horizontal blend leads the vertical one, so it glides out first and then
  climbs (an arc), and it grows from 1× to `scale_multiplier` on the way. Its orbit's angle is the
  bearing from the centre to where it formed (so it moves outward), with a random ring radius and
  height.
- **Small life:** a bob, a breathing scale and a tumble (a slow turn around an axis that itself
  turns slowly) fade in during the rise.
- `step` also works on bare states without nodes, so the unit tests can drive it.

**`SculptureMass`**: when it becomes a cloud, it gathers its pieces under a new `CloudBody` node at
its centre, before emitting `cloud_formed`, so every listener sees the final layout.
- `CloudSky` turns and scales that body, and moves the mass so the body sits on the cloud's path.
- The mass's own drift (`_physics_process`, `_cloud_height`, `_drift_heading`) goes.
- Collision shapes stay on the mass, as before; they're off for clouds.

**`SculptureFx`**: the cloud puff-up scales each piece around its centre in the piece's parent space
(the cloud body) instead of the mass's.

**Details** (visual only, no shadows):
- **`CloudPuffs`** (`cloud_puffs.gd`, a `MultiMeshInstance3D` under the cloud body): about 8 soft
  spheres per object, scattered over its surface by area and half sunk into it (adapted from the
  old `CloudPuffs`, commit `a22d649`). They turn and grow with the cloud.
- **`CloudWisps`** (`cloud_wisps.gd`, a `MultiMeshInstance3D` under the mass at the body's centre,
  not turning, scaled by the cloud's growth): 3–8 slots (picked per cloud), each a cluster of a few
  puffs. A slot waits, appears just outside the cloud, drifts slowly, and fades in, lives, fades
  and shrinks away, then starts again elsewhere. Like the small fragments around real clouds,
  they come and go.
- Shader: the unused `assets/shaders/cloud.gdshader` (built for these puffs) is renamed
  `cloud_puff.gdshader`. It fades each puff by `INSTANCE_CUSTOM.w` (0 shows it, so plain meshes
  still work) and gives each puff its own pulse phase. New material: `assets/materials/cloud_puff.tres`.

**Tunables move:** `atmosphere_y_range`, `rise_speed`, `drift_speed` and `cloud_rise_delay` leave
`MassManager`; `CloudSky` has the zone, gyre, rise, spacing, small-life and detail settings.
`zurd_world02` drops its `MassManager` override (and `GameSystems` stops being editable there),
so every world uses `game_systems.tscn`'s values.

**Ship camera:** `far` goes from 4000 m (Godot's default) to 12000 m, so clouds on the far side of
the gyre aren't cut off. The mirror camera copies it.

## Files

| File | Change |
|---|---|
| `scenes/sculpture/cloud_sky.gd` | new |
| `scenes/sculpture/cloud_puffs.gd` | new |
| `scenes/sculpture/cloud_wisps.gd` | new |
| `assets/shaders/cloud.gdshader` (+ `.uid`) | renamed `cloud_puff.gdshader`; per-puff fade and pulse |
| `assets/materials/cloud_puff.tres` | new |
| `scenes/sculpture/sculpture_mass.gd` | cloud body; own drift removed |
| `scenes/sculpture/sculpture_fx.gd` | puff-up in the parent's space |
| `scenes/sculpture/mass_manager.gd` | cloud motion tunables removed |
| `scenes/world/game_systems.tscn` | `CloudSky` node |
| `scenes/world/zurd_world02.tscn` | override removed |
| `scenes/characters/player/player_ship.tscn` | camera `far` 12000 |
| `scenes/characters/player/player_flight_controller.gd` | doc comment pointed at `CloudSky` |
| `tests/unit/test_cloud_sky.gd` | new |
| `tests/scene/test_sculpture.gd` | a cloud test |
| Cloud-Formation and Sculpture-Mass design docs, CLAUDE.md, `tests/README.md` | updated |

## Steps

1. Shader rename and puff material; `CloudPuffs`, `CloudWisps`.
2. `CloudSky`; `SculptureMass` cloud body; `SculptureFx` fix; tunables moved; scenes.
3. Tests; full suite.
4. Look at it: a windowed run that forms a cloud and screenshots the rise and the gyre.
5. Docs.

## Risks

- **The editor is open** (`terrain02.tscn`). New `class_name`s aren't registered for game-mode runs
  until the editor rescans, so the new scripts are referenced with `preload` constants, not their
  class names. `game_systems.tscn`, `zurd_world02.tscn` and `player_ship.tscn` change on disk:
  reload them if the editor asks, and don't save stale copies over them. The editor writes the
  new scripts' `.uid` files on its next scan; commit them.
- **Overdraw:** big see-through clouds plus puffs cost fill rate. There's no cap on clouds (decided).
  Watch the frame time once many clouds are up.
- **Transparent sorting** between a cloud's objects and its puffs can flip as the view moves. The
  look is still a placeholder (§4.2 note).
- **A 12 km far plane** lowers depth precision far away. Godot 4.3+ uses reversed Z, so it should
  be fine; watch for flicker on distant scenery.

## Verification

- `tests/unit/test_cloud_sky.gd`:
  - inner rings turn faster; the middle radius takes one lap time;
  - a new cloud holds, rises out and up to its ring and zone, gliding out before climbing, and
    grows to the multiplier;
  - clouds stay in the ring and zone over long runs;
  - two overlapping clouds part and don't stay overlapped;
  - the tumble is a pure rotation;
  - puffs sit on their objects;
  - wisp slots come and go, never more than their count.
- `tests/scene/test_sculpture.gd`: a cloud formed in the world gathers its pieces under its body,
  reaches the zone, grows to the multiplier and gets puffs and wisps.
- Full suite passes.
- Windowed screenshots of a cloud forming, rising and circling.

## As built (2026-11-17)

- As planned, with these changes:
  - **Puffs hang under each object's piece**, not under the cloud body. Under the body they ended
    up buried when `SculptureFx` swells the objects 1.2×; under the piece they swell, tumble and
    grow with it.
  - `CloudPuffs` keeps its `placements`, because a headless run's renderer doesn't keep MultiMesh
    transforms (they read back as identity).
  - The puff material draws at `render_priority` 1, after the clouds' objects, whose depth then
    always hides the sunk half of each puff.
  - `cloud_puff.tres` references its shader by path only: the open editor hadn't rescanned the
    renamed shader's UID, so the UID still pointed at `cloud.gdshader`. The editor will add the UID
    back when it saves the material.
- **Tests:** 124 pass, including the 7 new unit tests in `tests/unit/test_cloud_sky.gd` and
  `test_cloud_rises_into_the_sky_dressed_in_puffs` in `tests/scene/test_sculpture.gd`.
- **Visual check** (windowed, `zurd_world02`, clouds of 6 objects):
  - Forming, the rise (it glides out toward the grove, then climbs), the gyre, puffs and wisps all
    work.
  - **At 6× the clouds read small:** about 180 m across and 2–4 km from the play area, they're specks
    next to the 1.6 km trees and the canopy.
  - **At 20×** they read as giant, recognisable objects in the sky, with their puffs and wisps.
  - The multiplier stays 6× as agreed; trying 20× is the first tuning suggestion.
