# Plan: Sculpture-Mass system

## Context

The *Sculpture-Mass Design Doc* says how launched objects build up into masses, how Zurds and
the ship take masses apart, and how a mass that reaches the threshold becomes a permanent
drifting cloud. None of this exists yet. Launched objects are plain `RigidBody3D`s from
`scenes/objects/rigid/` (generated, no script), `ObjectTracker` only knows loose bodies, and
Zurds eat instantly on contact (`zurd_mouth_component.gd`). This plan adds the mass system as
the spec describes, including its Section 5 decision: **one `RigidBody3D` per mass, with fused
objects' meshes and shapes as its children**.

### Decisions (spec, plus answers from 2026-10-26)

- **Zurd scope:** we make the minimum Zurd changes the mass needs: Zurds can target fused
  objects, eating is timed and can be interrupted, and Zurds push masses. Provocation stays in
  the Zurd doc.
- **Loose + loose:** when **either** object reaches *Hits to fuse*, both become a new mass at
  their midpoint.
- **Mass + mass:** they merge on **first contact**, and the larger mass absorbs the smaller.
- **A 1-object remnant becomes loose again.** A mass with 0 objects is freed.
- Confirmed on review:
  - Only collisions with Objects-layer bodies (loose objects or masses) count as hits. The
    ship, Zurds and the environment don't. The hit counter exists for its look: objects should
    visibly clatter off each other before they fuse, so `object_hit` also drives a small
    visual cue (placeholder).
  - Ship break-off uses the ship's existing `min_impact_speed` gate (`impact_occured`), so a
    gentle nudge breaks nothing.
  - Zurds ignore a mass once it becomes a cloud. Its pieces are removed from `ObjectTracker`.
  - **Sound is deferred.** There are no audio files yet, so no audio slots or players for now.
    The signals stay, ready for sound later.
  - **The cloud look still needs design.** `cloud_form` in the blend shader and
    `assets/shaders/cloud.gdshader` are placeholders.
- Defaults chosen (easy to change later):
  - Angular velocity is left unchanged when an object fuses (the spec allows approximating it).
    Off-center ship hits already add torque through `apply_impulse`.
  - All objects have the same mass, whatever their launch scale (spec §5).

## Status (2026-10-30)

All seven build steps are written. They have **not been play-tested yet** and haven't been through
an editor parse check. Things added during the build that the plan didn't have:

- **`refuse_delay` (1 s) and `detach_speed` (1 u/s)** on `MassManager`. An object that leaves a
  mass spawns touching its old neighbours, so without a delay it would fuse straight back on its
  next contact, and a falling-off chunk would re-form as a new mass at once. This bends the spec's "no
  cooldown" rule, but only for objects that just left a mass. Set both to 0 for the strict spec.
- **Zurds hold on while eating** (`ZurdMovementComponent.process_eating`, `hold_strength`). A
  hunting Zurd flies through its target at full speed, so the target would never stay in the
  mouth for the whole eat duration.
- **The mouth checks the exact piece with a shape query every frame,** instead of relying on
  shape enter/exit signals, whose indices go stale when shapes move between bodies.
- **Zurds push only masses,** not loose objects, so their existing behaviour with loose objects
  is unchanged.

## Architecture

```
ObjectContainer
 └─ SculptureMass (RigidBody3D, layer 3, mask 1–4, gravity 0, contact monitor, custom COM)
     ├─ MassPiece (Node3D at the original body's transform)
     │    └─ <visual root moved from the loose body>  ← material_override = mass blend material
     ├─ CollisionBox (CollisionShape3D moved from the loose body, meta "mass_piece" → piece)
     └─ …
```

- **`MassManager`** (node in `base_world.tscn`) owns all cross-body logic and all tunables. It
  listens to `ObjectTracker.object_registered` to hook contact signals onto every loose body, so
  the generated rigid scenes stay untouched. Contact callbacks only **queue requests**. The
  manager runs the queue in its own `_physics_process`, which comes after the engine's
  `flush_queries`, so changing shapes there is safe.
- **Resolve shape indices to nodes inside the callback** (`shape_find_owner` →
  `shape_owner_get_owner`). Indices shift when shapes are added or removed, so the queue must
  store nodes, not indices.
- **Fuse:** move the loose body's visual root under a new `MassPiece` and its `CollisionShape3D`
  under the mass, keeping global transforms (`Node.reparent`). Record `scene_file_path`, the
  launch scale and the damp values on the piece, then `queue_free` the loose body (spec: "the
  original loose body is removed").
- **Remove (eat / break off):** for a break-off, create a fresh instance of the recorded scene
  and apply the recorded scale and damp. Place it at the piece's transform with velocity
  `V + ω × (p − COM_global)`, add it with `EventBus.spawn_requested`, and register it with
  `ObjectTracker`. A fresh instance means the object's original look comes back by itself.
  Then free the piece's nodes.
- **Structure graph:** each piece keeps an undirected `neighbors` set. When an object fuses,
  its neighbors are the piece it hit plus every piece of that mass found by an `intersect_shape`
  query with a small margin. When masses merge, the two pieces at the contact point are linked.
  After any removal, a BFS finds the connected chunks. The largest chunk stays and each piece in
  the others becomes loose.
- **Momentum:** `V' = (M·V + m·v)/(M+m)`, with `M = count · object_mass`. Set `mass` and a
  custom `center_of_mass` (the average of the piece shape centers, so every object weighs the
  same) after each change in count.

## Files

**New** (tabs, typed, `class_name`, `push_warning`/`push_error`):
- `scenes/sculpture/mass_manager.gd`: `MassManager`. It has these exports:
  `cloud_threshold_count = 60`, `hits_to_fuse = 2`, `atmosphere_y_range = Vector2(150, 200)`,
  `mass_linear_damp`, `mass_angular_damp`, `object_mass = 1.0`, `neighbor_margin`,
  `rise_speed`, `drift_speed`, `mass_scene`, `debug_labels`. It owns the hit counts, the request
  queue (de-duplicated per body or pair, with consumed bodies skipped), `_create_mass`, `_fuse`,
  `_merge`, `_remove_piece(piece, cause, actor)`, `_spawn_loose` and `_split_check`. It also has
  the public `request_eat(piece, actor)` and `request_break_off(shape)`.
- `scenes/sculpture/sculpture_mass.gd` + `sculpture_mass.tscn`: `SculptureMass`. It holds the
  pieces, count, `cloud_progress` and `is_cloud`. It owns its per-mass `ShaderMaterial` (sets
  `cloud_amount`, plus `flash()` for the red blink). It also runs the cloud transition: layer
  and mask set to 0, contact monitor off, kinematic freeze, unregister pieces, tween up into the
  atmosphere range, then a cosmetic drift. It has an optional debug `Label3D` showing
  `count/threshold`.
- `scenes/sculpture/mass_piece.gd`: `MassPiece` (Node3D). It holds `mass`, `shapes`,
  `neighbors`, `source_scene_path`, `spawn_scale`, `linear_damp` and `angular_damp`.
- `scenes/sculpture/sculpture_fx.gd`: `SculptureFx`. This placeholder only listens to the
  EventBus and does visuals only for now (sound comes later, on the same signals): a small cue
  on `object_hit`, the fusion "pop" scale tween on `object_fused`, and
  `mass.flash(Color.RED)` on `object_eaten`.
- `assets/shaders/sculpture_mass.gdshader`. Albedo is `COLOR.rgb * base_tint`, where
  `base_tint` is an `instance uniform` copied from each object's original material. It mixes
  toward white with `cloud_amount` and lowers alpha by up to `max_transparency` (subtle, about
  0.2). `cloud_form` (0–1) adds a **placeholder** dramatic look (rim and soft shading borrowed
  from `assets/shaders/cloud.gdshader`) until the cloud look is designed.
  `flash_color`/`flash_amount` drive the red blink. Check that 0% looks identical to the
  original (vertex-color sRGB handling).
- `sandbox/test_sculpture_mass.tscn`: an instance of `toroidal_world.tscn` with a small
  threshold (5), `hits_to_fuse = 1` and debug labels on.

**Modified** (each edited file keeps its current indentation, because some use spaces and mixing
breaks GDScript):
- `scripts/autoload/event_bus.gd`: add `object_hit(obj, other)`, `object_fused(mass, piece)`,
  `masses_merged(mass, absorbed_count)`, `objects_broken_off(mass, objects)`,
  `cloud_progress_changed(mass, progress)` and `cloud_formed(mass)`. Change `object_eaten` to
  `(actor: Node3D, obj: Node3D, mass: SculptureMass)`, with `mass` null for loose objects.
  Emit it before freeing.
- `scripts/autoload/object_tracker.gd`: track `Node3D` (loose bodies and pieces). Add
  `signal object_registered` and `unregister_object()`. Purge entries that are invalid or no
  longer `is_inside_tree()`. `zurd_spawner.gd` keeps counting `active_objects`, which now
  includes pieces.
- `scenes/characters/player/player_flight_controller.gd`: also emit
  `collision.get_collider_shape()` in `impact_occured`.
- `scenes/characters/player/player_ship.gd`: if the collider is a `SculptureMass`, call
  `request_break_off(shape)`. The flight controller already applies the impulse, so the mass's
  velocity changes too.
- `scenes/characters/enemy/zurd_target_component.gd`: targets become `Node3D`. A target is
  valid only if it is valid, in the tree and not in a cloud.
- `scenes/characters/enemy/zurd_mouth_component.gd`: add `@export var eat_duration`. For a
  loose target, match it with `body_entered`/`body_exited`; for a piece, match its shape with
  `body_shape_entered`/`body_shape_exited`. The timer starts on entry. Eating is interrupted
  (object unharmed) if the target leaves the mouth, becomes invalid or knocked off, or on
  `cancel_eating()`. When the timer finishes: free a loose target, or call
  `manager.request_eat(piece, actor)` for a piece. The collision exception goes to the target's
  *body* (the mass for a piece) and is reapplied if that body changes after a merge.
- `scenes/characters/enemy/zurd.gd`: types change to `Node3D`, and `take_swat` also calls
  `mouth_componet.cancel_eating()`.
- `scenes/characters/enemy/zurd_movement_component.gd`: add `@export var push_force`. After
  `move_and_slide`, apply impulses to `RigidBody3D` colliders, the same way the flight
  controller does.
- `scenes/world/base_world.tscn`: add `MassManager` and `SculptureFx` nodes.
- `CLAUDE.md`: add a Key systems entry and a layout row for `scenes/sculpture/`. Also fix the
  stale importer name (`glb_physics_importer.gd` → `glb_post_importer.gd`).

## Build order (each step can be play-tested in the sandbox scene)

1. **Plumbing.** EventBus signals, `ObjectTracker` generalization, and the type updates in the
   Zurd target and mouth code so everything compiles. Sandbox scene.
2. **Fusion.** `MassManager`, `SculptureMass`, `MassPiece`: contact hooks, hit counting
   (`body_entered` increments; `body_shape_entered` records which piece was touched),
   loose + loose → new mass, loose → mass, momentum, damping, COM, debug label,
   `object_hit` and `object_fused`.
3. **Merging and structure.** Mass ↔ mass merge (deduplicate the pair, larger absorbs smaller),
   the neighbor graph, the removal API, split check, dissolving 1-object remnants,
   `masses_merged`.
4. **Ship break-off.** Flight controller and ship changes, velocity at point,
   `objects_broken_off`.
5. **Zurd eating.** Timed, interruptible eating of pieces and loose objects; cancel on swat;
   Zurds push masses; `object_eaten` with the mass.
6. **Cloud.** Blend shader and per-mass material, `cloud_progress_changed`, cloud
   transformation (`cloud_formed`, collisions off, unregister, rise, drift, `cloud_form`
   transition).
7. **FX placeholders and docs.** `SculptureFx` (visuals only) and `CLAUDE.md`.

## Edge cases to handle

- **Same-frame conflicts:** skip bodies already used this frame. If a loose target was just
  fused into a mass, follow it to that mass.
- A count can pass the threshold through a merge. The mass becomes a cloud anyway and progress
  is clamped to 1.
- `request_eat` on a cloud does nothing. Clouds can't merge, because they have no collisions.
- If the ship breaks off a piece a Zurd is eating, the target is freed and the eat is
  interrupted.
- Launch scale is uniform, so scaled shapes are fine in Jolt. Only uniform scale is supported.
- The blend shader assumes vertex-colored meshes, like all current rigid objects. A mesh
  without vertex colors would render as plain tint.

## Open items

- Design the cloud look (`cloud_form` in `sculpture_mass.gdshader`, `cloud.gdshader`).
- Add sound once audio files exist, hooked to the existing EventBus signals.
- Puff and fog effects (spec §8). `CloudPuffs` (`scripts/world/cloud_from_mesh.gd`) is a
  possible starting point.

## Verification

- **Parse check:** `godot --headless --path . --quit` if Godot is on PATH. Otherwise open the
  editor and check Output for script errors.
- **F6 on `sandbox/test_sculpture_mass.tscn`** (threshold 5, `hits_to_fuse` 1, debug labels):
  1. Two objects collide → one mass at their midpoint, label `2/5`, slightly whiter.
  2. Fire into a mass → it fuses. Each new object moves the mass less as it grows.
  3. `hits_to_fuse = 3` → an object bounces twice and fuses on the third hit.
  4. Two masses touch → they merge, and the label shows the combined count.
  5. Ship into a mass → only the pieces it touches break off, keep their velocity and return to
     their original look. Removing a bridging piece drops the smaller chunk. Hitting a
     2-object mass leaves two loose objects.
  6. A Zurd eats a piece → the count drops only when the timer finishes, the mass blinks red
     and the blend reverses. Swatting mid-eat leaves the piece intact.
  7. Count reaches 5 → `cloud_formed`. The ship flies through it, it rises into the
     atmosphere band and drifts, Zurds ignore it, and new launches start a new mass.
  8. Toroidal wrap still works for masses and clouds.
- Watch Output for `push_warning`/`push_error` and any "Can't change this state while flushing
  queries" error.
- **Performance check:** set the threshold to 100, build a full mass, and watch physics time in
  Debugger → Monitors.
