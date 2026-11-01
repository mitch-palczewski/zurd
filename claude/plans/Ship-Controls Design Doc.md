# Ship-Controls Design Doc

Zurd game · Godot (GDScript) · Functional design with implementation notes only where a decision is needed

## 1. Overview

Guests steer the trophy room like a fish in water. An 8-way joystick drives and turns it; two buttons raise and lower it. With no input the ship slows to a hover and wanders gently. The view turns left and right but **never pitches or rolls**, because the projected room does not pitch or roll in real life.

One pilot can play the whole game alone: fly and launch objects. An optional launch station lets another guest join. Swatting Zurds stays with the physical flyswatters on the lidar walls and is not covered here.

The game is shown at an art exhibit. Ideally guests are engaged with the piece and stay for an extended time, but given the setting, guests tend to filter in and out and play for a short time. So every control must be understood in seconds with minimal instructions.

Items marked **(later)** are part of the design but not the first build (see section 8). The implementation plan for the first build is `2026-11-01-ship-controls-plan.md`.

## 2. The Art Exhibit Room

| Element | Description |
| --- | --- |
| Walls | Three projected walls in a trapezoid. The front wall is the short parallel side; the left and right walls angle outward toward the back of the room. Each wall shows its own camera view from the ship. |
| Wall view | Open space, with the ship's floor visible at the bottom of the walls and its ceiling at the top. HUD items sit in these top and bottom bands, and the edges of the image blend into the physical room. |
| Pilot station | Central command station in the middle of the room, facing the front wall. Joystick and pilot buttons. |
| Launch station | Next to the pilot station, facing the front wall. The final number and placement of launch stations is undecided; this doc assumes **one**. |
| Swatters | Guests with flyswatters at the lidar walls. Swats are aimed through the wall's camera. |

All launches leave from the middle of the ship and fly straight ahead, whichever button fires them.

## 3. Stations and Controls

### 3.1 Pilot station (required)

| Control | Action | Effect |
| --- | --- | --- |
| Joystick forward / back | Thrust | Move forward / back. Reverse is slower. |
| Joystick left / right | Turn | Rotate the view left / right. Diagonals combine both. |
| Up button | Rise | Move the ship up. |
| Down button | Sink | Move the ship down. |
| Launch button | Pilot launch | Launch a random object straight ahead. |

### 3.2 Launch station (optional, one for now)

| Control | Action | Effect |
| --- | --- | --- |
| Big button | Launch | Launch the selected object straight ahead. |
| Small button 1 | Previous | Select the previous object. |
| Small button 2 | Next | Select the next object. |

The core gameplay loop must be fully playable with only the pilot station in use. A solo pilot launches random objects and may not have fine control over which object launches or over the defence of the ship. The launch station is right next to the pilot station, so the pilot can reach over to choose objects if needed.

The final button layout is undecided. The design treats every launch button the same way: it fires straight ahead from the middle of the ship and has its own cooldown. Launch buttons or stations can be added or moved without changing the rest of the design.

## 4. Parameters

All parameters are exported values so they can be tuned. Speeds will be refined in playtesting; the starting values keep launch speed well above ship speed (see 5.3).

| Parameter | Description | Starting value |
| --- | --- | --- |
| Max forward speed | Top speed going forward. | 18 m/s |
| Max reverse speed | Top speed going backward | 6 m/s |
| Acceleration | How fast the ship reaches its target speed | 10 m/s² |
| Coast-to-hover time | Time to slow to a hover after the stick is released | 1.5 s |
| Input ramp time | Time for a digital input to reach full strength (fakes an analog stick) | 0.3 s |
| Max turn rate | Turn speed at full input | 45°/s |
| Rise / sink speed | Vertical speed at full input | 5 m/s |
| Ground clearance | Closest the ship may sink toward the ground below it | Tune in editor |
| Lowest altitude | Floor used where there is no ground under the ship | Tune in editor |
| Altitude ceiling | Highest the ship may rise. Stays below the cloud band (`MassManager.atmosphere_y_range` starts at 150 m). | 120 m |
| Idle drift speed | Gentle wander while hovering. Must stay below the flight controller's `min_impact_speed` (2.0) so a resting ship never breaks objects off a mass. | 0.5 m/s max |
| Hover bob | Height of the slow up-and-down bob while hovering | Tune by feel |
| Launch speed | Speed of a launched object relative to the ship. Keep it at least about 2.5× the max forward speed. | 45 m/s (currently 20) |
| Launch stop distance | How far an object launched from a hovering ship travels before it stops | 70 m (current value) |
| Ship velocity carry-over | Share of the ship's velocity added to a launched object | 50% (currently 100%) |
| Launch cooldown | Per launch button | 0.5 s (current value on the ship) |
| Camera tilt | Fixed downward tilt of every wall camera. Never changes during play. | 0° |
| Station idle timeout | No input for this long marks a station as empty | 30 s |
| Mass slow zone **(later)** | Radius around a mass inside which the ship's top speed is reduced | 15 m |
| Mass slow zone speed **(later)** | Top speed inside the slow zone | Tune by feel |

## 5. Behaviors

### 5.1 View

- The view only turns left and right (yaw). It never pitches or rolls, not even as a visual effect. The visible ship floor and ceiling don't lean either.
- The camera's field of view is fixed. No speed-based field-of-view change. With three walls, a changing field of view would also break the image at the wall corners.
- Turning starts and stops with a short ease (input ramp time). On three surrounding walls a sudden turn is the most likely cause of motion sickness.
- The sense of motion comes from things that don't tilt the view:
  - space dust streaming past the ship, faster at higher speed,
  - a slow hover bob while the ship is idle.
- **Three walls (later):** all three wall cameras turn together and share one fixed field of view, so the image stays continuous across the wall corners. The first build uses the single front camera.

### 5.2 Movement

- **Thrust:** joystick forward and back set a target speed; the ship accelerates toward it. Reverse is slower because there is no rear wall to see where you're going.
- **Turn:** joystick left always rotates the view left, whether moving forward, in reverse or standing still. No car-style reverse steering.
- **Diagonals:** combine thrust and turn. Back-left reverses while the view turns left.
- **Rise and sink:** holding a button moves the ship up or down at a constant speed.
- **Digital input:** the joystick and buttons are on/off. Every input ramps up over the input ramp time instead of jumping to full strength. An analog stick on a test gamepad gives partial input and ramps the same way.
- **Hover:** with no input the ship slows to a stop within the coast-to-hover time, then bobs and wanders very slowly, always below the idle drift speed. The wander moves the ship's position only; the view never turns unless the pilot turns it.
- **Altitude limits:** there is ground below the play area. The ship can't sink closer than the ground clearance to the ground beneath it, or below the lowest altitude where there is no ground, and can't rise above the altitude ceiling.
- **Mass slow zone (later):** inside the mass slow zone, the ship's top speed drops so a new pilot doesn't crash into the sculpture by accident. Hitting a mass still breaks objects off it (Sculpture-Mass Design Doc §4.6).
- **Sidestep (possible later feature):** moving the ship sideways without turning, for example on the back diagonals (back-left moves back and left, or just left, without rotating). Concern: if the diagonals sidestep while left and right turn, the joystick no longer means the same thing in every direction, which walk-up guests may not work out. A separate control would avoid that.

### 5.3 Launching

- Every launch leaves the middle of the ship and flies straight ahead.
- **Pilot launch** fires a random object.
- **Station launch** fires the station's selected object.
- Each launch button has its own cooldown, so the pilot and the station together can launch twice as fast as one.
- **Selecting:** the station steps through the shared object list with the small buttons, wrapping around at the ends. Sizes stay random, as they are now.
- Launched objects keep the current physics: no gravity, braking to a stop, random spin, random size and small spread.
- **Launch speed vs. ship speed:** launch speed stays well above the ship's top speed, so a launch clearly pulls ahead of a moving ship (about 25 m at the starting values) before it stops. Only part of the ship's velocity is added, so an object lands at a similar distance whether the ship is moving or hovering (70 m hovering, about 85 m at full speed). A ship that keeps flying straight at full speed still reaches its stopped launches a few seconds later, like driving into the spot where you threw a ball; the pilot sees this coming on the front wall.
- **Selected-object display (later):** the station's selected object is shown in the bottom band of the front wall.
- **Aiming is out of scope.** Launches fly level for now; vertical aim comes from the ship's altitude. Power and angle meters, a moving crosshair, and other ways to aim are covered in a separate doc.

### 5.4 Feedback (later)

HUD items sit in the top and bottom bands of the walls.

- **Off-screen Zurds:** a Zurd outside all three walls' views (behind the ship, or far above or below) shows a marker at the edge of the nearest wall.
- **Ship under attack:** a stronger warning on all three walls plus a sound, so the crew knows the ship is in danger.

### 5.5 Walk-up and Idle

- No menus during play. Pressing any control at a station brings it into play immediately.
- Each station panel carries a printed diagram or icons on the buttons (arrows on Up / Down).
- **Station activity:** a station with no input for the station idle timeout counts as empty; any input makes it active again. Changes fire `station_activity_changed`, ready for the idle vista, station prompts and Zurd difficulty.
- The ship hovers in place while nobody is at the pilot station.
- **Idle vista (later):** once the pilot station is empty, the ship slowly drifts and turns to show off vistas: circling a mass, or wandering and smoothly changing which mass it looks at. Any pilot input hands control back immediately. This is the one time the view turns without the pilot, so it stays slow and smooth.

## 6. Implementation Notes

### 6.1 Input actions

All code reads **input actions only**, never keys or devices directly, so the arcade kit, a gamepad and the keyboard all work by changing the input map. Joystick movement is bound to both the left stick and the d-pad, since an arcade encoder may report the stick as either.

Replace the current `ship_pitch_up/down`, `ship_yaw_left/right` and `ship_boost` actions. `ship_launch` stays as the pilot launch; `ship_swat` is unchanged.

| Action | Control | Keyboard | Gamepad |
| --- | --- | --- | --- |
| `ship_forward` / `ship_reverse` | Joystick forward / back | W / S | Left stick or d-pad up / down |
| `ship_turn_left` / `ship_turn_right` | Joystick left / right | A / D | Left stick or d-pad left / right |
| `ship_rise` / `ship_sink` | Up / Down buttons | R / F | Right / left shoulder |
| `ship_launch` | Pilot launch | Space | A (bottom face button) |
| `launch_station_fire` | Station big button | K | Y (top face button) |
| `launch_station_prev` / `launch_station_next` | Station small buttons | J / L | X / B (left / right face buttons) |

The arcade buttons are bound once the kit is wired (see section 11).

### 6.2 Code changes

See the implementation plan for detail. In short:

- **`PlayerFlightController`:** a new flight model. Pitch, auto-level, cockpit lean, FOV boost and boost are removed; the ship rotates only around global Y. Collision handling (`impact_occured`) stays.
- **`LaunchObjectComponent`:** becomes the one shared launcher at the middle of the ship. It owns the object list and launch physics; input and cooldowns move to one `LaunchStation` node per launch button or station.
- **`StationActivity`:** one node per station tracks its last input and fires `station_activity_changed`.
- **Wall cameras (later):** the three-camera rig matched to the trapezoid walls is part of lidar plan step 5 (multiple walls). The first build keeps the single front camera.

## 7. Events (Event Bus signals)

| Signal | Fired when | Used by |
| --- | --- | --- |
| `launch_selection_changed(station, scene)` | A station selects a different object | Selected-object display **(later)** |
| `station_activity_changed(station, active)` | A station becomes active or empty | Idle vista, station prompts and Zurd difficulty **(later)** |

## 8. First Build

The first build changes only the ship's controls and effects.

| In the first build | Later |
| --- | --- |
| New flight model: thrust, turn, rise and sink, input ramps, hover with gentle position-only wander | Idle vista |
| Altitude limits: ground clearance, lowest altitude and ceiling | Three-wall camera rig |
| Level camera with fixed field of view; space dust and hover bob | HUD: selected-object display, Zurd markers, ship-under-attack warning |
| Launches straight ahead from the middle of the ship: pilot launch (random) and one launch station (previous / next selection), each with its own cooldown | Mass slow zone |
| New launch speed and partial velocity carry-over | Final button layout and more launch stations |
| Station activity tracking and its signal | Sidestep (if wanted) |
| New input actions for keyboard and gamepad | |

## 9. Out of Scope

- Launch aiming (power and angle meters, moving crosshair).
- How the pilot defends the ship from Zurds. A repel button was considered and set aside for now.
- Zurd difficulty when nobody is swatting.
- What happens when a Zurd eats the ship.
- The cloud formation moment, including how guests see a cloud rise above the level view (see Cloud-Formation Design Doc).
- Projection mapping onto the trapezoid walls.
- End-game state.

## 10. Open Items

1. **Final button layout:** how many launch stations, where they stand, and which buttons the pilot has.
2. **Boost:** none for now. If playtests show the ship is too slow, try a hold-forward cruise speed before adding a button.
3. **Sidestep:** whether to add it, and on which control (5.2).
4. **Reset between groups:** whether the world resets when every station has been empty for a while.

## 11. Hardware

The priority is to design a control schema for the art installation arcade controller, but for testing purposes the controls are also mapped to a normal controller and to mouse and keyboard. Below are the controllers to support for testing.

- **EG STARTS 2 Player Arcade Games DIY Kit** (2 ellipse oval joystick handles, 20 LED-lit arcade buttons, red and blue). It is unknown whether this will be used in the final installation, but it is the target device to build for.
  - Its USB encoder has 12 button inputs plus a 5-pin joystick input. One pilot station (joystick, Up, Down, Launch) and one launch station (Launch, Previous, Next) need 6 buttons, so both are wired to **one encoder** and the game sees them as one device.
  - The encoder shows up as a gamepad. Its button numbers are bound in the input map after wiring, by pressing each button in Godot's Input Map editor.
  - The kit's button lights are most likely always on, powered by the encoder, so the game can't use them to show cooldowns without extra hardware.
- **8BitDo Ultimate 3C+ wireless controller.** Uses the gamepad column in 6.1.
- **Mouse and keyboard.** Uses the keyboard column in 6.1; the mouse swats in place of the lidar wall.

The arcade encoder and the 8BitDo are both gamepads, so their button numbers overlap. Connect one at a time when testing.
