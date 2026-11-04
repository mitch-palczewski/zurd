# Plan: Combining matching objects

## Context

The *Sculpture-Mass Design Doc* now has §4.10: when an object is shot into the same kind of
object, the two become one bigger object instead of fusing. Zurds eat a combined object one part
per bite, so it visibly shrinks. This plan builds on the sculpture-mass system from
`2026-10-26-sculpture-mass-plan.md` (`MassManager`, `SculptureMass`, `MassPiece`, `SculptureFx`).
Today every object is one fixed-size thing: the launcher picks a random scale (1–7) for the
object's children, a fused `MassPiece` remembers that scale as `spawn_scale`, and every count and
weight is "number of objects".

### Decisions (answers from 2026-11-02 and 2026-11-04)

- **Match** = the same model (`scene_file_path`), at any size. Any loose object can combine,
  including broken-off ones.
- **When:** the hit counter is kept. When an object's counter reaches `hits_to_fuse` and the
  thing it's touching matches, the two combine instead of fusing.
- **Pairs:**
  - **Loose + loose:** the bigger object (more parts, then larger size) stays put and grows, and
    the smaller one is absorbed. The hit counter resets to 0.
  - **Loose into a piece:** the piece grows in place inside its mass.
  - **Masses merging:** only the touching pair combines.
- **Size:** `combine_size_mode` on `MassManager`:
  - `ADD_VOLUMES` (the default): scales 3 and 4 make ∛(27 + 64) ≈ 4.5.
  - `ADD_SCALES`: 3 + 4 = 7.
  - There is no cap in either mode.
- **Counting:** a combined object counts as all its parts, for cloud progress, mass weight,
  chunk size and the debug label. A loose combined body weighs parts × its normal weight.
- **Momentum** works like fusing, weighted by parts, including `fuse_push`/`fuse_spin` when
  absorbing into a mass.
- **Growth:** the collision shape grows at once and the visuals catch up with a short, snappy
  animation. The animation isn't designed yet, so the placeholder is a ~0.25 s tween with a
  little overshoot.
- **Yellow flash** on the combined object only, not the whole mass. The combine sound is
  deferred.
- **Growth break-off:** fused pieces that the grown piece *now* overlaps break off as loose
  objects, pushed outward. Then the usual structure check drops anything left disconnected. A
  loose object that grows just shoves its neighbours, through Jolt.
- **Combined objects stay combined,** including when broken off by the ship.
- **Bites:**
  - Each bite takes the normal `eat_duration` and removes the **most recently added part**, so
    the object shrinks back the way it grew.
  - The Zurd keeps chewing while the object stays in its mouth. This is already what happens:
    after a bite the object is still its target.
  - The count drops by 1 per bite, and the mass blinks red per bite.
  - A shrinking piece keeps all its links, even if a gap opens.
  - The Zurd grows `obj_scale_factor` per bite, the same as eating that many separate objects.
- **Out of scope:** the Cloud-Formation doc notes (extra cloud spheres, camera on the rising
  cloud).

## Status (2026-11-04)

All five build steps are written. A headless harness drove the real `MassManager` in
`toroidal_world.tscn` and passed all 66 checks: sizes in both modes, keeper choice, weights and
momentum, growth break-off, merge combines, bites (loose, fused and through the Zurd's mouth),
break-off keeping parts, cloud counting by parts, same-batch follow, the launcher offsets, and the
FX tween and flash. Soak runs of the real game loop (about 40 s each, launching mostly arches)
logged no errors or warnings in either size mode:
- in *Add volumes* the biggest object reached 17 parts at size ≈ 12;
- in *Add scales* it reached 11 parts at size ≈ 35.

**Not checked:** how it looks and feels (no renderer headless).

Changes from the plan:

- **`growth_break_depth` (0.1)** on `MassManager` (Breaking Off group): how far a growing piece
  must push into a neighbour before the neighbour breaks off. The plan compared plain overlap
  before and after, but neighbours that were only touching already "overlap" by a hair, so they
  would never have broken off. Depth is measured with a box-vs-box separating axis test
  (`MassPiece.get_box_overlap`), not a physics query, so it doesn't depend on shapes changed
  earlier in the same batch.
- **A loose object that reaches its hit count against a mass also combines with any matching
  piece it's touching,** not only the one it last hit.
- **`MassManager.request_eat` and `SculptureMass.request_eat` are gone;** the Zurd's mouth emits
  `EventBus.eat_requested` for every target.

## Design

### Parts record: `ObjectParts`

A small `RefCounted` that every object carries. Loose bodies hold it in a meta, because the
generated rigid scenes have no script. Pieces hold it in a var.

```
ObjectParts
  scales: PackedFloat32Array   # each part's own launch size, oldest first
  sizes:  PackedFloat32Array   # the object's size after each part joined; the last is the current size
  part_mass: float             # physics weight of one part (the scene's RigidBody3D.mass)
```

- `count()` is `scales.size()`, and `get_size()` is `sizes[-1]`.
- `absorb(other, mode)` appends `other`'s parts one at a time, oldest first. Each part pushes a
  new size, `combine(previous_size, part_scale, mode)`.
- `remove_last()` pops one entry from both arrays. A bite therefore restores the exact previous
  size with **no mode lookup**, so switching the toggle mid-game never breaks shrinking.
- `static of(body)` returns the body's record. If it has none, it creates a 1-part record from
  the body's `CollisionShape3D` scale (launch scale) and `mass`, and stores it.

### Resizing an object

Scaling a node scales it around its own origin. The collision boxes sit slightly off the body
origin, so each child's **position is scaled by the same ratio** (`new_size / old_size`) as its
scale. That keeps box and mesh lined up at any size.
- **Loose body:** every `Node3D` child is rescaled.
- **Piece:** the visual children of the piece are rescaled, and so are its shapes, which live
  on the mass. A shape is placed relative to the piece's origin.
- Collision shapes and visuals both jump to the new size, and the manager emits
  `EventBus.object_resized(obj, old_size, new_size)`. `SculptureFx` then sets the visuals back
  to the old size and tweens them to the new one, so the animation lives only in the effects.
  Without `SculptureFx` the change is instant.
- `SculptureFx` must also update its stored `BASE_SCALE_META`. Otherwise the next hit punch
  snaps the visuals back to the old size.

### Combining (in `MassManager`, still queued and run in `_physics_process`)

`_process_fuse(body, other)`, when the counter is reached:
1. **`other` is a loose body with the same `scene_file_path`:** `_combine_loose(keep, absorb)`.
   - The bigger one keeps. Its velocity becomes the parts-weighted average of the two.
   - `keep.parts.absorb(absorb.parts)`. Its `mass` is updated and it's resized.
   - The hit counter and touched-piece meta reset. `absorb` is freed.
   - Emits `objects_combined`.
2. **`other` is a mass, and the touched piece (`TOUCHED_META`) matches:**
   `_combine_into_piece(piece, body)`.
   - Momentum is applied exactly as in `_fuse`, weighted by parts, with push and spin.
   - Then `piece.parts.absorb(...)`, a resize, the growth break-off, `refresh`, and
     `objects_combined`.
3. **Otherwise:** fuse as today.

`_merge(keep, absorb, a, b)`: after adopting, if `a` and `b` match, `_combine_pieces(a, b)`
runs. The bigger piece absorbs the other one's parts. The smaller piece is removed without
spawning anything, and its links move to the survivor. Then the growth break-off runs.

**Growth break-off** (`_break_overlapped(piece, old_size)`):
1. Measure how deep the piece's boxes push into each other piece of its mass, at the old size
   and at the new size (box-vs-box separating axis test, `MassPiece.get_box_overlap`).
2. Pieces pushed into by more than `growth_break_depth` now, but not before, are the ones it
   **now** overlaps. Pieces that already overlapped that much stay. (Plain overlap wouldn't
   work: neighbours that were only touching already overlap by a hair.)
3. Those pieces detach with `detach_speed`, pushed away from the grown piece's centre.
4. `_settle` then drops disconnected chunks or a 1-piece remnant.
5. Emits `objects_broken_off`.

### Counting by parts

| Where | Change |
|---|---|
| `SculptureMass.refresh` | `mass` = parts × `object_mass`; `cloud_progress` = parts ÷ threshold; the debug label shows parts |
| Centre of mass and `get_inertia_estimate` | weighted by each piece's parts |
| `get_chunks` | sorts by parts |
| `_fuse`, `_merge`, `_process_merge` | weights and "larger mass" use parts |
| Remnant rule | unchanged: a mass with **one piece** becomes loose, whatever that piece's part count |

### Eating in bites

Today the mouth frees loose targets itself and sends pieces to `SculptureMass.request_eat`. Both
cases now go through the manager, so shrinking lives in one place:

1. The mouth emits a new `EventBus.eat_requested(actor, obj)`, in the same request pattern as
   `spawn_requested`.
2. `MassManager` queues the request. `_process_eat`:
   - **More than one part:** `remove_last()`, then the resize (and the weight for a loose body).
     For a piece it also runs `refresh`. Emits `object_eaten`.
   - **One part:** the object is removed exactly as today. A loose body is freed. A piece is
     removed, then `_settle` runs.
3. `SculptureMass.request_eat` is removed, since nothing calls it any more.

`object_eaten(actor, obj, mass)` still fires per bite. `obj` may still exist afterwards.

## Files

**New** (tabs, typed, `class_name`):
- `scenes/sculpture/object_parts.gd`: `ObjectParts`, plus the `SizeMode` enum.

**Modified:**
- `scripts/autoload/event_bus.gd`: add `eat_requested(actor, obj)`,
  `objects_combined(obj, absorbed_parts)` and `object_resized(obj, old_size, new_size)`.
- `scenes/sculpture/mass_manager.gd`:
  - New exports: a `Combining` group with `combine_size_mode`.
  - Combine branch in `_process_fuse`. New functions `_combine_loose`, `_combine_into_piece`,
    `_combine_pieces`, `_break_overlapped` and `_resize`.
  - Combine in `_merge`. Bites in `_process_eat`, which listens to `eat_requested`.
  - Part-weighted momentum. `_spawn_loose` restores the parts, size and weight.
  - Redirects requests whose body was absorbed earlier in the batch (see edge cases).
- `scenes/sculpture/mass_piece.gd`: `parts: ObjectParts` replaces `spawn_scale`;
  `capture_body`/`restore_body` carry it; a `resize` helper for its shapes and visuals.
- `scenes/sculpture/sculpture_mass.gd`:
  - `get_part_count()`.
  - Part-weighted `refresh`, centre of mass, inertia estimate and chunk sort.
  - Remove `request_eat`.
- `scenes/sculpture/sculpture_fx.gd`:
  - `object_resized` → tween the visuals from the old to the new size (export
    `resize_time` ≈ 0.25 s, overshoot) and update the stored base scale.
  - `objects_combined` → yellow flash on that object's meshes (export
    `combine_flash_color`). This uses a short `material_overlay`, which works on loose
    objects (their own material) and on pieces (the shared mass material) alike.
- `scenes/characters/enemy/zurd_mouth_component.gd`: `_eat_target` emits
  `EventBus.eat_requested` for both loose and fused targets, instead of freeing or calling
  the mass.
- `scenes/characters/player/launch_object_component.gd`: also scale each child's position
  by the launch scale, so the collision box stays centred on the mesh.
- `CLAUDE.md`: mention combining and `ObjectParts` in the sculpture-masses entry and the
  EventBus list.

## Build order (each step can be play-tested in `sandbox/test_sculpture_mass.tscn`)

1. **Parts plumbing.** `ObjectParts`, parts on loose bodies and pieces, counting by parts
   everywhere, resize helpers, and the launcher position fix. Nothing changes in play yet:
   every object is one part.
2. **Loose + loose combine,** with `object_resized`/`objects_combined` and the FX tween and
   flash.
3. **Combine into a piece,** with the growth break-off.
4. **Combine on merge.**
5. **Bites:** `eat_requested`, the mouth change, shrinking loose objects and pieces.
6. **Docs:** `CLAUDE.md`, and a status note here.

## Edge cases

- **Same-batch conflicts:**
  - A body absorbed earlier in the batch is recorded as absorbed → keeper, the same way
    `_fused_this_batch` follows fused bodies. A later request involving it then acts on the
    keeper or is skipped.
  - Two loose objects that both reach the counter queue two requests for the same pair. The
    second one finds the absorbed body gone and does nothing.
- **A Zurd mid-bite on an object that gets absorbed:** the target is freed, so the eat is
  interrupted and the Zurd retargets. A Zurd mid-bite on the keeper carries on.
- **A shape that grows into the ship, a Zurd or another mass** gets pushed apart by Jolt, may
  trigger a ship break-off, or merges on contact. All of that is existing behaviour.
- **A loose object growing inside terrain:** Jolt's depenetration can fling it hard. Check this
  in the sandbox, and tune Jolt's penetration settings only if needed.
- **Changing `combine_size_mode` mid-game** affects only later combines. Existing sizes and
  bites come from the stored history.
- **Clouds** don't collide, so they never combine or get bitten. `_is_live_mass` already
  rejects them.

## Verification

- Headless: a temporary harness in game mode, as for the mass build. It checks:
  - **Combining and sizes:** combine sizes in both modes (3 + 4 → 4.5 / 7); the keeper
    choice and part counts.
  - **Weights and momentum:** parts-weighted momentum and mass weight.
  - **Growth break-off:** only newly overlapped pieces leave.
  - **Bites:**
    - a 3-part object shrinks 3 → 2 → 1 → gone, with the cloud count dropping each bite;
    - links are unchanged after a shrink;
    - a broken-off combined piece respawns at its size with its parts.
- **F6 on the sandbox scene.** Pick one model with the launch stations (J/L), then fire:
  1. Two of the same model into each other → one bigger object pops up with a yellow flash.
     The label counts both.
  2. Fire a matching model into a mass piece → that piece grows, and anything it now overlaps
     breaks off.
  3. A non-matching model still fuses as before.
  4. A Zurd chews a combined piece → it shrinks a step per bite, and the mass blinks red each
     time.
  5. Ship into a combined piece → it leaves whole and at its size.
  6. Switch `combine_size_mode` to `ADD_SCALES` → growth is much bigger.
- Watch Output for warnings or errors, and for objects flung out of terrain.
