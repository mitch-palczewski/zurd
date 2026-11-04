# Launch-Station Design Doc

Zurd game · Godot (GDScript) · Functional design with implementation notes only where a decision is needed

## 1. Overview

A launch station is a panel of three buttons: one big **Launch** button and two small **Select** buttons (previous / next). Pressing a Select button shows a small copy of an object on a pedestal inside the cockpit, slowly turning. While it is showing, Launch fires that object. After a few seconds without a press the preview goes away, and Launch goes back to firing random objects.

So a guest who only hits the big button still plays: they launch random objects. A guest who finds the small buttons gets to choose. Nothing has to be explained.

This doc covers the station's buttons, the preview pedestal (the station's part of the HUD), and where its launches leave the ship. It replaces the "selected-object display" planned in the Ship-Controls Design Doc (§5.3) and changes where station launches start (Ship-Controls §2, §5.3). The pilot station, flight and launch physics stay as that doc describes.

Items marked **(later)** are part of the design but not the first build (see section 8).

## 2. Stations in the Room

| Element | Description |
| --- | --- |
| Pilot station | Center of the room, facing the front wall. Its launch button fires a **random** object from the **center** of the ship. It has no pedestal and no preview. |
| Launch station | Stands beside the pilot station, facing the front wall. Three buttons. Has its own pedestal and its own launch point, both offset to the side it stands on. |
| More launch stations | The design supports any number. Each one gets its own offset, pedestal, launch point, selection and cooldown. The first build has **one**. |

**Offsets match the room.** A station that stands to the right of the pilot has its pedestal right of center in the cockpit and launches from the right side of the ship. A guest sees their pedestal on their own side of the front wall and their objects leave on that side. Each station sets one sideways offset; height and depth are shared by all stations.

## 3. Controls

| Control | Preview hidden | Preview showing |
| --- | --- | --- |
| Big button (Launch) | Launch a random object | Launch the shown object, keep showing it, restart the hide timer |
| Small button 1 (Previous) | Show the last selected object (no step) | Step to the previous object |
| Small button 2 (Next) | Show the last selected object (no step) | Step to the next object |

- **First press shows, later presses step.** When the preview is hidden, either Select button brings back the station's last selected object without changing it, so a guest who walks up never skips an object they didn't see. Once the preview is showing, each press steps through the list, wrapping at both ends.
- **The selection is remembered.** Hiding the preview doesn't reset the selection. The station starts on the first object in the list.
- **Hide timer.** Every Select or Launch press restarts it. When it runs out the preview hides and Launch goes back to random.
- **Cooldown** is per station and unchanged (Ship-Controls §4). Select buttons work during the cooldown.
- The object list is shared by every station (the launcher's list). Each station keeps its own selected index.
- Launch sizes stay random, as they are now. The preview doesn't show the size an object will launch at.

## 4. The Preview

### 4.1 Pedestal

- **Placeholder shape:** a tapered eight-sided column, narrower at the top, with a thin round disc on top that is a little wider than the column's top. Plain material for now.
- **Position:** on the cockpit floor in front of the camera, at the station's sideways offset, so it shows in the bottom band of the front wall (Ship-Controls §2). It must stay inside the front camera's view at every station offset in use.
- **Comes and goes with the preview.** When there is no preview, the cockpit floor is clear.

### 4.2 Object

- A visual-only copy of the selected object's model: no physics, no collision, never tracked by `ObjectTracker` or the `MassManager`, never eaten.
- **Fit to size:** each object is scaled so its largest dimension fills the same preview box. Every object reads clearly. The real size difference between models isn't shown.
- **Hovers above the disc**, centered on its bounds, so odd shapes (arches, the crocodile) never clip into the disc.
- **Turns slowly around the Y axis** (global up, like the ship). Each new object starts facing the guest.
- The preview doesn't react to a launch: the object stays on the pedestal and keeps turning. The launch itself happens outside the ship (section 5).

### 4.3 Transitions

| Moment | What happens |
| --- | --- |
| Show | The pedestal rises out of the cockpit floor, then the object pops in (grows from zero with a slight overshoot). |
| Step | The current object quickly shrinks, then the new one pops in. The pedestal stays. |
| Hide | The object shrinks to zero, then the pedestal sinks into the floor. |

- Transitions never queue. A press always moves the preview toward its newest state from wherever it is. Stepping several times quickly ends on the last object without playing every swap. Pressing Select while it hides makes it rise again from where it is.
- Launch never waits for a transition. During **Step**, Launch fires the newly selected object. During **Hide**, the selection has already expired, so Launch fires a random object.

## 5. Launching

- **Station launches** leave from the station's **launch point**: outside the hull, at the station's sideways offset, at the same height and depth as today's `LaunchMuzzle`. They fly straight ahead, parallel to the pilot's launches. They don't angle toward the center.
- **Pilot launches** stay random, from the center launch point.
- Launch physics (speed, braking, spin, spread, random size, velocity carry-over, player collision exception) are unchanged and shared by every launch point (Ship-Controls §5.3).
- **Launch feedback:** no effect in the first build. The object leaving the ship is the feedback.
- **Launcher (later):** a cannon or other launcher object at each launch point, outside the ship, with its own launch animation. A station's launcher sits on its side, matching its pedestal.

## 6. Parameters

All parameters are exported so they can be tuned. Sizes and positions are starting points for tuning in the editor against the cockpit model.

| Parameter | Description | Starting value |
| --- | --- | --- |
| Preview hide delay | Time after the last Select or Launch press before the preview hides | 5 s |
| Preview turn speed | How fast the preview object turns around Y | 60°/s (one turn in 6 s) |
| Preview box size | Largest dimension of a fitted preview object | 0.25 m |
| Hover height | Gap between the disc and the bottom of the object's bounds | 0.05 m |
| Pedestal height | Column plus disc | 0.3 m |
| Pedestal rise / sink time | Time for the pedestal to rise out of or sink into the floor | 0.25 s |
| Object pop-in time | Grow from zero, with overshoot | 0.2 s |
| Object shrink time | On hide and at the start of a step | 0.12 s |
| Pedestal depth | Distance in front of the camera, shared by all stations | Tune so it sits in the front wall's bottom band |
| Station offset | Sideways distance of a station's pedestal and launch point from the center. Positive is right. One per station. | ±0.6 m for the pedestal; the launch point uses the same value |

## 7. Implementation Notes

### 7.1 Who owns what

- **`LaunchStation`** owns the selection state: selected index, whether the preview is showing, and the hide timer. It decides what Launch fires: the shown object, or null (random) when the preview is hidden. It also gets an exported sideways offset and a reference to its `LaunchPreview`.
- **`LaunchPreview`** (new scene with its own script, next to the ship scenes): pedestal mesh, disc mesh, and a holder for the object copy. It only displays. `show_object(scene)` and `hide_preview()` drive the transitions in 4.3 from wherever they currently are. The station positions it from its offset at startup. It sits under the ship's `Cockpit` node so it moves with the camera.
- **`LaunchObjectComponent`** stays the one shared launcher. `launch_object(scene, side_offset)` gets a sideways offset that moves the start point along the muzzle's local X. Everything else is unchanged. The pilot launch passes 0.

### 7.2 Building the object copy

Copy only the scene's `MeshInstance3D` nodes (their meshes are already shared `.res` files), not the `RigidBody3D` itself. A real body in the cockpit would collide with the ship (the ship's mask includes layer 3) and register with the tracker. Fit the copy to the preview box from the combined mesh bounds. Cache one copy per scene, so stepping doesn't instantiate a new scene every press.

### 7.3 Placeholder meshes

Build both from `CylinderMesh`s for now: the column with 8 radial segments and a top radius smaller than its bottom radius; the disc with many radial segments and a small height. Replace them later with a modeled pedestal under `assets/models/` (not `objects/` or `scenery/`, so the importer makes no physics scenes).

## 8. Events (Event Bus signals)

| Signal | Fired when | Used by |
| --- | --- | --- |
| `launch_selection_changed(station, scene)` | The preview shows or steps (`scene` = the shown object), or hides (`scene` = null: the station is back to random). Not fired at startup; stations start hidden. | Sounds **(later)**, any other display that needs the selection. `LaunchPreview` is driven directly by its station. |

This changes the existing signal's meaning: it currently fires at startup and on every step, and never with null. Nothing listens to it yet.

## 9. First Build

| In the first build | Later |
| --- | --- |
| Select buttons: first press shows, then steps; selection remembered | Cooldown shown on the pedestal disc (dims while cooling down) |
| Hide timer; Launch fires the shown object, or random when hidden | Sounds: select, show, hide, launch |
| Pedestal (placeholder meshes) rising and sinking with the preview | Cannon or launcher object and launch animation at each launch point |
| Fitted, hovering, turning object copy with scale-pop transitions | Modeled pedestal |
| Per-station sideways offset for pedestal and launch point | More launch stations and their final placement |
| `launch_selection_changed` with null on hide | |

## 10. Out of Scope

- The pilot station and flight (Ship-Controls Design Doc).
- Launch aiming (Ship-Controls §5.3).
- Other HUD items: off-screen Zurd markers, ship-under-attack warning (Ship-Controls §5.4), and join prompts at empty stations.
- Showing an object's launch size in the preview.

## 11. Open Items

1. **Station count and placement:** how many launch stations, and which side each stands on. It sets the offsets (Ship-Controls open item 1).
2. **Three walls:** once the three-wall camera rig exists, check that pedestals at the outer offsets still sit on the front wall and not across a wall corner.
3. **Pilot and the pedestal:** the pilot can reach over to the station's buttons (Ship-Controls §3.2). Check in playtests whether a pilot also wants a preview for their own random launches. The current answer is no.
