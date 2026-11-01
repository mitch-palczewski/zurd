# Plan: Ship controls (first build)

## Context

The *Ship-Controls Design Doc* replaces the current flight-sim controls with "fish in water"
controls for the projected room: the view turns but never pitches or rolls, the ship hovers when
left alone, and launches come from the pilot and from an optional launch station. Today
`PlayerFlightController` always flies forward (`base_speed`, with a `boost_speed` the ship scene
sets to 1), pitches and yaws with W/S/A/D, auto-levels, leans the `Cockpit` (which carries the
camera) and widens the FOV on boost. `LaunchObjectComponent` reads `ship_launch` itself, keeps
one cooldown and adds the ship's full velocity to each launch. This plan builds section 8 of the
design doc ("First Build") and nothing from its "Later" column.

### Decisions (design doc, plus answers from 2026-11-01)

- **Scope:** only the ship's controls and effects. One front camera. No HUD, no idle vista, no
  mass slow zone.
- **Launches:** every launch leaves the middle of the ship (`LaunchMuzzle`) and flies straight
  ahead. Two launch buttons for now: the pilot launch (random object) and one launch station
  (selected object, previous / next). Each has its own cooldown. The final button layout is
  undecided, so a launch button is a node that can be duplicated.
- **Speeds:** top speed 18 m/s, launch speed 45 m/s, stop distance 70 m, 50% of the ship's
  velocity carried into a launch. All exported; to be refined in playtesting.
- **Hover:** the idle wander moves the ship's position only. It never turns the view.
- **Station activity is built now,** as infrastructure for the later idle vista, station
  prompts and Zurd difficulty. Nothing consumes `station_activity_changed` yet.
- **Input:** code reads input actions only. Keyboard and gamepad bindings now; the arcade kit
  (one encoder for the pilot and the launch station) is bound after it's wired.
- **No floor lean.** The visible ship floor and ceiling stay level with the camera.

## Architecture

```
PlayerShip (CharacterBody3D, motion_mode floating)
 ├─ CollisionShape3D
 ├─ Cockpit (Node3D)              ← never rotates; the hover bob offsets its position
 │   ├─ Interior/ShipBottom
 │   └─ Camera3D                  ← fixed FOV, fixed tilt
 ├─ FlightController (PlayerFlightController)
 ├─ LaunchMuzzle (LaunchObjectComponent)   ← the one shared launcher; no input of its own
 ├─ Stations (Node)
 │   ├─ PilotLaunch (LaunchStation)        fire: ship_launch, random object
 │   ├─ StationLaunch (LaunchStation)      fire/prev/next: launch_station_*, selected object
 │   ├─ PilotActivity (StationActivity)    station "pilot"
 │   └─ LaunchStationActivity (StationActivity)  station "launch_station"
 ├─ SpaceDust (GPUParticles3D, world space)
 └─ SwatEmitter
```

- **Flight model, per physics frame:**
  1. Read `thrust`, `turn` and `lift` with `Input.get_axis`, and ease each toward its raw value
     over `input_ramp_time` (`move_toward`). Analog sticks give partial values and ease the same
     way.
  2. Forward speed moves toward `thrust × max_forward_speed` (or `max_reverse_speed` in reverse)
     at `acceleration` when speeding up, and at `max_forward_speed / coast_to_hover_time` when
     slowing down.
  3. Yaw: `ship.rotate_y(turn × max_turn_rate × delta)`. The ship never has pitch or roll, so
     local and global Y are the same.
  4. Vertical speed is `lift × rise_speed`.
  5. Hover amount eases toward 1 when there's no input and the ship has nearly stopped, and
     toward 0 otherwise. The wander velocity (random-walk heading, like the cloud drift in
     `sculpture_mass.gd`, at `idle_drift_speed`) and the bob are scaled by it.
  6. Altitude limits adjust the vertical velocity (below), then `move_and_slide()` and the
     existing `_handle_collisions`.
- **Altitude limits:** a downward ray against layer 1 (Environment), as long as
  `ground_clearance` plus a small margin. On a hit, the floor is the hit height plus
  `ground_clearance`. Otherwise it's `lowest_altitude`. If the ship is below the floor, its
  vertical speed is set to climb back at no more than `rise_speed`, so it rides up over hills
  without snapping. Downward speed is clamped so it doesn't cross the floor or rise through
  `altitude_ceiling`.
- **Launch path:** `LaunchStation` handles its button presses, cooldown and selection, then
  calls `launcher.launch_object(scene)`, where `scene` is `null` for a random object. The
  launcher keeps all the existing launch physics. The only change is that it adds
  `ship.velocity × ship_velocity_carry_over` instead of the full velocity.
- **Station activity:** each `StationActivity` checks its action list every frame
  (`is_action_pressed` for held inputs, `is_action_just_pressed` for taps). Any use resets the
  idle timer and, if the station was empty, marks it active. After `idle_timeout` with no use
  it's marked empty. Both changes emit `EventBus.station_activity_changed`. Stations start
  empty and don't emit at startup.

## Files

**New** (tabs, typed, `class_name`, `push_warning`/`push_error`):
- `scenes/characters/player/launch_station.gd`: `LaunchStation` (Node). Exports:
  `station_id: StringName`, `launcher: LaunchObjectComponent`, `fire_action`, `prev_action`,
  `next_action` (leave both empty for random launches), `cooldown_time = 0.5`. Holds
  `selected_index`. Emits `EventBus.launch_selection_changed(station_id, scene)` on each
  selection change, and once (deferred) on ready if it has a selection. Checks its actions with
  `InputMap.has_action` on ready and `push_error`s any that are missing.
- `scenes/characters/player/station_activity.gd`: `StationActivity` (Node). Exports:
  `station_id: StringName`, `actions: Array[StringName]`, `idle_timeout = 30.0`. Public
  `is_active`, so it can be watched in the remote inspector.
- `scenes/characters/player/space_dust.tscn`: `GPUParticles3D` with `local_coords = false`, a
  box emitter around the ship (about 60 × 30 × 60 m), zero initial velocity, a long lifetime,
  `preprocess` equal to the lifetime so it starts full, and a tiny unshaded billboard quad that
  fades in and out. The ship flies through still dust, so it streams faster at higher speed with
  no script. Large `visibility_aabb`.

**Modified:**
- `project.godot` `[input]`: remove `ship_pitch_up/down`, `ship_yaw_left/right` and
  `ship_boost`. Add `ship_forward`, `ship_reverse`, `ship_turn_left`, `ship_turn_right`,
  `ship_rise`, `ship_sink`, `launch_station_fire`, `launch_station_prev` and
  `launch_station_next`, and add a gamepad event to `ship_launch`. Bindings are design doc §6.1:
  keyboard, plus gamepad left stick, d-pad, shoulders and face buttons. Keep deadzone 0.2.
  Make these edits in Project Settings → Input Map so Godot writes the event serialization.
- `scenes/characters/player/player_flight_controller.gd`: rewritten. Export groups:
  - *Speed:* `max_forward_speed = 18`, `max_reverse_speed = 6`, `acceleration = 10`,
    `coast_to_hover_time = 1.5`.
  - *Handling:* `input_ramp_time = 0.3`, `max_turn_rate` (degrees, 45), `rise_speed = 5`.
  - *Altitude:* `ground_clearance`, `lowest_altitude`, `altitude_ceiling = 120`,
    `ground_mask = 1`.
  - *Hover:* `idle_drift_speed = 0.5`, `hover_blend_time`, `hover_bob_height`,
    `hover_bob_frequency`.
  - *View:* `camera_tilt` (degrees, 0).
  - *Collision Interaction:* `push_force` and `min_impact_speed`, unchanged.

  Remove pitch, auto-level, cockpit lean, the FOV boost and the pitch-based camera offset.
  `setup()` flattens the ship's basis to yaw only, zeroes the `Cockpit` rotation, applies the
  camera tilt and stores the cockpit's base position for the bob. `_handle_collisions` uses
  the absolute forward speed for its impulse, so collisions in reverse still push. The file
  currently uses spaces; since it's rewritten whole, it switches to tabs per `CLAUDE.md`.
  `impact_occured` keeps its signature.
- `scenes/characters/player/launch_object_component.gd`: remove `input_action`,
  `cooldown_time`, `cooldown_timer` and `_process`. `launch_object(scene: PackedScene = null)`
  launches the given scene, or a random one when null. Defaults become `launch_speed = 45` and
  `target_stop_distance = 70`. Add `@export_range(0.0, 1.0) var ship_velocity_carry_over = 0.5`
  and use it in `_calculate_launch_velocity`. Add `get_projectile_count()` for stations to
  wrap their selection.
- `scenes/characters/player/player_ship.tscn`: drop the stale overrides (`base_speed`,
  `boost_speed` on `FlightController`; `cooldown_time` on `LaunchMuzzle`). Add the `Stations`
  node with its four children (wired as in Architecture) and an instance of `space_dust.tscn`.
  Make these edits in the editor so Godot assigns uids and `unique_id`s.
- `scripts/autoload/event_bus.gd`: add, with doc comments and `@warning_ignore("unused_signal")`
  like the others, under a `# Ship controls` heading:
  `launch_selection_changed(station: StringName, scene: PackedScene)` and
  `station_activity_changed(station: StringName, active: bool)`.
- `CLAUDE.md`: replace the input-actions line, and update the Player entry (shared launcher,
  `LaunchStation`, `StationActivity`, hover flight).
- `claude/ONBOARDING.md`: update the Controls step (lines ~108–111) and the Player ship
  paragraph (lines ~127–133).

`player_ship.gd` needs no change: `set_flight_enabled` and the break-off call still work.

## Build order (each step can be play-tested)

1. **Input map.** New actions with keyboard and gamepad bindings, old ones removed. The flight
   controller stops compiling against the old names until step 2, so do steps 1 and 2 together.
2. **Flight model.** Rewrite `PlayerFlightController`: thrust, turn, rise and sink, input
   ramps, coast to hover, level camera, no FOV change. Remove the stale overrides from
   `player_ship.tscn`.
3. **Hover.** Hover amount, position-only wander and the cockpit bob.
4. **Altitude limits.** Ground ray, lowest altitude and ceiling.
5. **Launching.** Strip input from `LaunchObjectComponent`, add `launch_object(scene)` and the
   velocity carry-over, write `LaunchStation`, add the `Stations` node with `PilotLaunch` and
   `StationLaunch`, and add the `launch_selection_changed` signal.
6. **Station activity.** `StationActivity`, its two nodes and the `station_activity_changed`
   signal.
7. **Space dust.** `space_dust.tscn` under the ship. Tune its size and density on the
   projector if possible, since tiny particles read differently on a wall than on a monitor.
8. **Docs.** `CLAUDE.md` and `ONBOARDING.md`.

## Edge cases to handle

- **Tilted placement:** a ship placed with pitch or roll in a scene is flattened to yaw only in
  `setup()`.
- **Opposite inputs** (forward and back together) cancel to 0 through `Input.get_axis`.
- **The ground ray only hits Environment** (layer 1), never objects, masses or Zurds, so a
  mass under the ship doesn't push it up.
- **The wander can't damage masses.** `idle_drift_speed` (0.5) is below `min_impact_speed`
  (2.0), so a drifting ship never breaks off a piece.
- **Toroidal wrap** teleports the ship. Space dust is briefly thin after a wrap. The launcher's
  collision-exception loop measures distance, so a wrap mid-launch ends the exception early.
  This already happens today.
- **Empty `projectile_scenes`:** `LaunchStation` doesn't launch or step its selection, and the
  launcher's existing warning fires once per press.
- **Selection after the list changes:** `selected_index` is wrapped into range before every use.
- **Held inputs keep a station active.** `is_action_pressed` covers a stick held for longer
  than the idle timeout.

## Open items

- Bind the arcade kit's buttons once it's wired (design doc §11). Test with one gamepad
  connected at a time, since the encoder's and the 8BitDo's button numbers overlap.
- Idle vista, HUD, mass slow zone and three-wall camera rig (design doc §8, "Later").
- Tune speeds and launch values in the room.

## Verification

- **Parse check:** `godot --headless --path . --quit` if Godot is on PATH. Otherwise open the
  editor and check Output for script errors and for warnings about missing properties in
  `player_ship.tscn`.
- **F6 on `scenes/world/toroidal_world.tscn`** (keyboard):
  1. Hold W → the ship reaches 18 m/s in about 2 s. Release → it stops in about 1.5 s, then
     bobs and drifts slowly. The view never tilts or rolls, and the FOV never changes.
  2. A / D → turning eases in and out. S + A reverses while the view turns left. Turning works
     while hovering.
  3. R / F → the ship rises and sinks. It stops at the 120 m ceiling and at `lowest_altitude`.
  4. Space → a random object flies straight ahead. Launching at full speed, the object pulls
     clearly ahead (about 25 m) before stopping. Launching while hovering, it stops about 70 m
     out.
  5. J / L, then K → the station launches the selected object. Pressing Space and K together
     launches two objects; each button keeps its own cooldown.
  6. Remote inspector on `PilotActivity` → `is_active` turns true on input and false 30 s after
     the last input. The same for `LaunchStationActivity` with J / K / L.
  7. Space dust streams past faster at higher speed and is still while hovering.
- **F6 on `scenes/world/idea_large_world.tscn`** (has ground): sink onto the ground → the ship
  stops at `ground_clearance`. Fly over a rise → it climbs over smoothly.
- **F6 on `sandbox/test_sculpture_mass.tscn`:** build a small mass. Ramming it still breaks
  pieces off, and leaving the ship hovering next to it for a minute breaks nothing.
- **Gamepad (8BitDo):** repeat steps 1–5 with the left stick, d-pad, shoulders and face buttons.
- **Swat:** mouse swats still hit Zurds through the level camera.
- Watch Output for `push_warning`/`push_error`.
