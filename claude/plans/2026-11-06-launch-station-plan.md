# Plan: Launch station (first build)

## Context

The *Launch-Station Design Doc* turns the launch station into a pick-and-preview station. Its
small buttons show a turning copy of the chosen object on a pedestal in the cockpit. Its big
button launches that object, or a random one once the preview has timed out. Station launches
leave from the station's own side of the ship. Today `LaunchStation` steps its selection on every
press and never forgets it, and there is no preview. Every launch leaves the middle of the ship
(`LaunchMuzzle`), and the `launch_station_*` actions have had no bindings since 2026-11-02.
This plan builds section 9 of the design doc ("First Build") and nothing from its "Later" column.

### Decisions (design doc, plus answers from 2026-11-06)

- **Preview size: lower third of the front wall.** The camera is only 0.56 m above the cockpit
  floor. At the design doc's first starting values (0.3 m pedestal, 0.25 m object), the object
  would sit in the middle of the wall. The new starting values are a 0.12 m pedestal and a
  0.12 m object box, 0.7 m in front of the camera (see Placement). Design doc §4.1 and §6 are
  updated to match.
- **Bindings:**

  | Action | Keyboard | Gamepad |
  | --- | --- | --- |
  | Previous | J | LB |
  | Launch | K | X |
  | Next | L | RB |

  LB, X and RB are the gamepad buttons the pilot actions leave free. The arcade kit is bound
  later. Ship-Controls §6.1 is updated to match.
- **The first launch station stands right of the pilot:** side offset +0.6 m, for both its
  pedestal and its launch point.
- **No launch effect and no sound.** The preview doesn't react to a launch.
- **The preview only displays.** `LaunchStation` owns the selection state and drives its
  `LaunchPreview` directly. `launch_selection_changed` is for other listeners (none yet).

### Placement (current cockpit geometry)

| | Cockpit space | On the front wall (from the top) |
| --- | --- | --- |
| Camera | Origin, level, 90° vertical field of view | |
| Floor surface (`ShipBottom`) | y −0.56. Reaches 0.9 m ahead of the camera (0.8 m at x ±0.6) | Its far edge is about 81% down |
| Pedestal base | (0.6, −0.56, −0.7) | About 90% down, three quarters across (16:9) |
| Object (0.12 m box, 0.02 m above the disc) | y −0.42 to −0.30 | About 72–80% down, about 9% of the wall's height |

The hover bob moves the camera and the pedestal together, so the preview stays put on the wall.
These are starting values for tuning on the projector. A new cockpit model would change them.

## Design

### Scenes

```
PlayerShip
 ├─ Cockpit
 │   ├─ Interior
 │   │   ├─ ShipBottom
 │   │   └─ StationPreview (LaunchPreview)   ← new. y and z set in the scene; x set by the station
 │   └─ Camera3D
 ├─ LaunchMuzzle (LaunchObjectComponent)     ← launch_object(scene, side_offset)
 └─ Stations
     ├─ PilotLaunch (LaunchStation)          side_offset 0, no preview: random, from the center
     ├─ StationLaunch (LaunchStation)        side_offset 0.6, preview StationPreview
     └─ PilotActivity, LaunchStationActivity (unchanged)
```

`launch_preview.tscn`, all placeholder geometry with one plain `StandardMaterial3D`:

```
LaunchPreview (Node3D, launch_preview.gd)   ← origin on the floor surface
 └─ Pedestal (Node3D)                        ← y 0 when shown, −sink_depth and invisible when hidden
     ├─ Column (MeshInstance3D)              CylinderMesh: 8 radial segments, 0.105 m tall,
     │                                       bottom radius 0.05, top radius 0.035
     ├─ Disc (MeshInstance3D)                CylinderMesh: 32 radial segments, 0.015 m tall,
     │                                       radius 0.06, on top of the column
     └─ Turntable (Node3D)                   at the disc's top (y 0.12). Turns around Y, scaled for the pop
         └─ one copy per object shown so far, built on first use; only the shown one is visible
```

### Station logic (`LaunchStation`, each frame)

1. Count down the cooldown.
2. **Select** (previous or next) pressed, and the launcher's list isn't empty:
   - Preview hidden: show the selected object without stepping.
   - Preview showing: step by −1 or +1, wrapping. Both buttons in the same frame don't step.
   - Then restart the hide timer, call `preview.show_object(scene)` and emit
     `launch_selection_changed(station_id, scene)`.
3. **Launch** pressed:
   - If the preview is showing, restart the hide timer.
   - If the cooldown is over, call `launcher.launch_object(get_launch_scene(), side_offset)`
     and restart the cooldown. `get_launch_scene()` is the selected scene while the preview
     shows, and null (random) otherwise.
4. **Hide timer:** counts down while the preview shows. At zero the preview stops showing:
   call `preview.hide_preview()` and emit `launch_selection_changed(station_id, null)`.

Presses are handled before the timer, so a press in the timer's last frame keeps the preview.
A station without selection actions (the pilot launch) skips steps 2 and 4 and always launches
random objects. Nothing is emitted at startup: every station starts hidden, on the first object.

### Preview (`LaunchPreview`)

**Retargeting.** `show_object(scene)` and `hide_preview()` set a target: the scene to end on, or
null for hidden. Each call kills the running tween and builds a new one from the current pedestal
height and turntable scale. Transitions therefore never queue, and each step's duration is scaled
by how far it still has to go. Steps that are already done are skipped:

1. **Shrink:** if the copy on the turntable isn't the target, shrink it (`shrink_time`, ease in).
2. **Swap:** hide the old copy and show the target's copy, built on first use. Reset the
   turntable's rotation to 0, so the model's front (+Z, glTF forward) faces the camera.
3. **Target set:** raise the pedestal (`rise_time`, ease out), then pop the object to scale 1
   (`pop_time`, `TRANS_BACK` ease out, for the overshoot).
4. **Target null:** sink the pedestal (`rise_time`, ease in), then hide it.

**Details:**
- The smallest scale is 0.01, not 0, and the copy is hidden at that scale. A zero scale gives a
  basis that can't be inverted.
- `_process` turns the turntable at `turn_speed_degrees` while the pedestal is visible.

**Building a copy** (`_build_copy(scene)`, cached per scene as a hidden child of the turntable):

1. Instantiate the scene without adding it to the tree.
2. For each `MeshInstance3D` in it, add a new `MeshInstance3D` to the copy with:
   - the same mesh, surface override materials and `material_override`;
   - its transform relative to the scene root (the product of its parents' transforms).

   Bodies, shapes and scripts are never copied.
3. Free the instance. It never entered the tree, so nothing ran its `_ready` or registered it.
4. **Fit:** merge the mesh AABBs in the copy's space. Scale the copy by
   `box_size / longest side`. Place the bounds' bottom center `hover_height` above the
   turntable's origin, on its turning axis.
5. A scene without meshes, or with zero-size bounds, warns once and shows an empty pedestal. The
   station still selects and launches it.

### Launch point (`LaunchObjectComponent`)

`launch_object(scene: PackedScene = null, side_offset: float = 0.0)`: the projectile starts at the
muzzle's transform moved `side_offset` along its local X (`translated_local`). Nothing else changes.
The muzzle is 1.8 m ahead of the ship's center, outside the hull, so the point 0.6 m to its right
is outside too.

## Files

**New** (tabs, typed, `class_name`, `push_warning`/`push_error`):
- `scenes/characters/player/launch_preview.gd`: `LaunchPreview` (Node3D). Exports:
  - *Object:* `box_size = 0.12`, `hover_height = 0.02`, `turn_speed_degrees = 60.0`.
  - *Timing:* `rise_time = 0.25`, `pop_time = 0.2`, `shrink_time = 0.12`.
  - *Pedestal:* `sink_depth = 0.14`: the pedestal's height plus a margin, so it hides fully
    under the floor.

  Public functions: `show_object(scene)` and `hide_preview()`.
- `scenes/characters/player/launch_preview.tscn`: the scene above. Make it in the editor, or
  write it by hand and then open and save it in the editor so it gets a uid.

**Modified:**
- `scenes/characters/player/launch_station.gd`:
  - New exports: `side_offset` (float, 0) and `preview` (`LaunchPreview`, optional).
    `preview_hide_delay = 5.0` goes in *Timing*.
  - New public state: `is_showing` (visible in the remote inspector) and `get_launch_scene()`.
  - The station logic above. `_ready` sets `preview.position.x = side_offset`.
  - Remove the deferred `_emit_selection` at startup.
- `scenes/characters/player/launch_object_component.gd`: the `side_offset` parameter.
- `scenes/characters/player/player_ship.tscn`:
  - Instance `launch_preview.tscn` as `Cockpit/Interior/StationPreview` at
    (0.6, −0.562, −0.7).
  - On `StationLaunch`, set `side_offset = 0.6` and `preview`.
  - Make these edits in the editor so Godot assigns the node ids.
- `scripts/autoload/event_bus.gd`: rewrite the `launch_selection_changed` doc comment. It fires
  when a station's preview shows or steps, and with `scene` null when it hides. It doesn't fire
  at startup. Point to Launch-Station Design Doc §8.
- `project.godot` `[input]`: the station bindings above (gamepad LB = button 9, X = 2,
  RB = 10). Add them in Project Settings → Input Map, or by hand with the editor closed. They
  serialize like `ship_launch`'s events.
- `scenes/ui/menus/main_menu.gd`: in `CONTROL_LINES`, change "launch chosen object (launch
  station)" to "launch chosen or random object (launch station)".
- `CLAUDE.md`:
  - The input-actions line: the station bindings, and remove "no bindings yet".
  - The Player entry: `LaunchPreview` and side offsets.
  - Known gaps: remove "The launch station has no bindings".
- `claude/ONBOARDING.md`: the Controls step (lines ~108–113), the Player ship paragraph
  (~132–147) and known gap 2 (~211).

**Already updated with this plan:**
- *Launch-Station Design Doc*: §2, §4.1 and §6, for the placement, sizes and first station's side.
- *Ship-Controls Design Doc* §6.1: the station bindings, plus the pilot's keyboard keys, which
  didn't match `project.godot` (rise / sink are Shift / Ctrl, pilot launch is Space).
- *Hardening plan*, step 4: how the catalog meets the preview (below).

## Build order (each step can be play-tested in `scenes/world/zurd_world.tscn`)

1. **Bindings and launch point.** Add the station bindings and
   `launch_object(scene, side_offset)`. Add `side_offset` to `LaunchStation` and set it to 0.6
   on `StationLaunch`. K now launches from the right side.
2. **Selection logic.**
   - First press shows, later presses step. Add the hide timer.
   - Launch fires the shown object, or a random one.
   - `launch_selection_changed` takes its new meaning.

   Before the preview exists, check `is_showing` and `selected_index` in the remote inspector.
3. **Preview scene.** `LaunchPreview` with the pedestal meshes, building copies, fitting and
   turning. It shows and hides instantly at first. Add it to the ship and wire the station.
4. **Transitions.** The tween chain: rise, pop, shrink and sink, retargeting from the current
   state.
5. **Tune the placement** on a screen, and on the projector when available: pedestal depth,
   height and box size, against the lower-third target.
6. **Docs.** `CLAUDE.md`, `ONBOARDING.md`, the menu label line, and a status note in this plan.

## Relation to the hardening plan

None of `2026-11-04-hardening-plan.md` is built yet, and this plan doesn't wait for it.

- **Step 1 (tests):** if the test runner exists when this is built, the headless checks below
  are committed as `tests/scene/test_launch_station.gd`. Otherwise they run from a scratch
  harness, as in earlier builds.
- **Step 3 (budget):** preview copies are never registered with `ObjectTracker`, so the budget
  never counts or despawns them.
- **Step 4 (catalog):**
  - `LaunchStation` selects catalog entries. It passes `entry.scene` to the preview and to
    `launch_object`.
  - `launch_selection_changed` passes the entry, or null when the preview hides.
  - The preview shows the model itself, so it needs no catalog names or icons. This bears on
    hardening open question 4.

## Edge cases

- **Rapid presses:** each press retargets from the current state. Five quick steps end on the
  fifth object with at most one shrink and one pop, and the objects in between never show.
- **Select during the hide:** the pedestal rises again from where it is. If the object hadn't
  finished shrinking, it grows back from its current size.
- **Launch never waits for a transition.**
  - During a step, it fires the newly selected object.
  - Once the timer has run out, it fires a random object, even while the preview is still
    shrinking.
- **Cooldown:** Select works during it. A Launch press during the cooldown restarts the hide
  timer but doesn't fire.
- **Empty launcher list:** Select does nothing and the preview stays hidden. Launch warns, as
  today.
- **The list shrinks:** `selected_index` is wrapped into range before every use, as today.
- **One object in the list:** stepping keeps it, and the preview doesn't swap.
- **Models with several meshes or nested nodes:** the copy takes every `MeshInstance3D` with its
  transform relative to the scene root, and the bounds merge all of them.
- **A model whose front isn't +Z** starts facing sideways on the pedestal. Fix it in the model,
  not in code.
- **Pilot launch:** no preview and offset 0, so it behaves exactly as today.
- **Control schemes:** `ControlScheme` only swaps the pilot's movement events, so the station's
  bindings are the same in both schemes.
- **Turning ship:** the preview is part of the cockpit, so it turns with the view and keeps its
  place on the wall. Its own turn is around the same vertical axis.

## Open items

- Bind the arcade kit (Ship-Controls §11). Its encoder and the 8BitDo share button numbers, so
  test with one connected at a time.
- Check the placement on the projector. The lower-third numbers come from the placeholder cockpit
  and a 16:9 screen.
- The design doc's "Later" column: cooldown on the disc, sounds, a launcher or cannon, a modeled
  pedestal, and more stations.

## Verification

- **Headless** (`zurd_world.tscn`, fixed 60 fps, pressing the input actions):
  1. **Startup:** no `launch_selection_changed`, `is_showing` is false, and the pedestal is
     hidden.
  2. **Launch points:** K spawns a random object 0.6 m right of the ship's center line (measured
     in ship space). F still launches from the center.
  3. **Selecting:**
     - L from hidden shows object 0 without stepping, and the signal carries its scene.
     - L again shows object 1.
     - J on object 0 wraps to the last object.
  4. **Hide timer:**
     - K while showing launches the shown object (`scene_file_path`).
     - Press K at 0 s and again at 4 s: the preview is still showing at 8 s.
  5. **Hiding:**
     - 5 s without a press: the preview hides and the signal carries null.
     - The next K launches a random object.
     - The next L shows the remembered object.
  6. **Settled preview:**
     - The pedestal is at y 0 and visible, and the turntable's scale is 1.
     - One copy is visible. Its world AABB's longest side is 0.12 ± 0.005, and its bottom sits
       0.02 above the disc.
     - The turntable turns at 60°/s.
  7. **Rapid steps:** five L presses in five frames end on the expected object. One copy is
     visible, and there is never more than one copy per scene.
  8. **Re-show during the sink:** hide, then press L halfway through the sink. The pedestal
     rises from its current height without jumping.
  9. **No physics in the preview:** there is no `CollisionObject3D` or `CollisionShape3D` under
     `StationPreview`, and previewing doesn't change `ObjectTracker`'s count.
  10. **Cooldown:** L works right after K. A second K within 0.5 s launches nothing.
- **F6 on `scenes/world/zurd_world.tscn`**, with the keyboard and the 8BitDo:
  1. L / RB: the pedestal rises at the bottom right of the front wall, and the object pops on,
     turning slowly. J / LB steps, and rapid presses don't stack up.
  2. K / X: that object flies out from the right side. The preview stays and keeps turning.
  3. Wait 5 s: the object shrinks and the pedestal sinks. K launches random objects again,
     still from the right.
  4. Fly, turn and hover: the preview stays fixed on the wall. It never clips the floor or
     leaves the view.
  5. Main menu: the controls label lists J / L and K. Switching to Stick lifts doesn't change
     them.
- Watch Output for `push_warning`/`push_error`.
