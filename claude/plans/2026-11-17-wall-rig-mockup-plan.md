# Wall rig mock-up plan

Status: **approved 2026-11-17**: default sizes, plus the fair single-camera mode.

## Goal

A throwaway test scene that mocks up the exhibit's three projected walls and shows, side by side
on the same frame, why one camera per wall beats one wide image stretched across the walls.
It's a sandbox scene: not part of the game, excluded from exports.

## The room

- Three wall screens in a trapezoid, seen from above:
  - the **middle wall** faces the guests;
  - the **side walls** meet its ends and angle outward toward the back of the room
    (Ship-Controls Design Doc: "the front wall is the short parallel side").
- **Settings**, all editable in the inspector while it runs:
  - middle wall width;
  - side wall width;
  - wall height;
  - the side walls' angle;
  - the **sweet spot**: where the design assumes guests stand, as a distance from the middle wall
    and an eye height.
- **Defaults:** middle wall 4 m wide, side walls 4 m, walls 2.5 m tall, side walls angled 45°
  outward, sweet spot 3 m from the middle wall at 1.6 m eye height.
- A plain floor and a dark room around the screens, and a small marker at the sweet spot.

## What's on the walls

`zurd_world02` runs in the background (its own world, without Zurds), and you fly the ship as
usual. Its picture goes onto the walls in one of two ways; **Tab** switches between them.

1. **Three cameras.** Each wall gets its own camera at the ship's cockpit, turning with it.
   - Each camera faces its wall's direction, and its view is cut to exactly the shape of that wall
     as seen from the sweet spot (Godot's off-axis "frustum" camera).
   - From the sweet spot, the walls read as one continuous window: straight lines stay straight
     across the corners.
2. **One stretched camera.** A single wide camera covers the whole span, and its image is spread
   across the three walls in proportion to their widths. This is what you'd get with one wide
   window across three projectors.

## The visitor

- The scene's own camera is a guest in the room. Number keys jump between spots:
  - 1: the sweet spot;
  - 2: off to the left;
  - 3: off to the right;
  - 4: close to the middle wall;
  - 5: above the room, looking down at the layout.
- Right mouse drag looks around from wherever you stand.
- A label shows the mode and the spot. **H** hides it.

## What it should prove

- **At the sweet spot:**
  - three cameras: the checker floor, trees and horizon run straight across both corners;
  - stretched: the horizon and floor lines bend at the corners, and the side walls look smeared.
- **Away from the sweet spot:** the three-camera image kinks a little at the corners, as any fixed
  rig does. That shows how much guests standing elsewhere will notice, and helps choose the sweet
  spot.

## Files

| File | Change |
|---|---|
| `sandbox/test_wall_rig.tscn` | new: the room, three wall screens, the visitor camera, a label |
| `sandbox/test_wall_rig.gd` | new: builds the walls from the settings, loads the world into a background viewport, runs the two modes and the visitor |
| CLAUDE.md | `sandbox/` row: mention the mock-up |

No game code changes. The ship flies as usual because its input actions are global.

## How it works

- A background `SubViewport` owns `zurd_world02`'s world. It doesn't draw its own picture.
- Three wall `SubViewport`s share that world. Each has a camera that copies the ship camera's
  position and turn every frame.
- Each wall's picture is that viewport's texture on an unshaded quad.
- **Three cameras:** each camera's off-axis frustum is worked out from the sweet spot and the
  wall's corners, so the camera sees the wall exactly as the sweet spot does.
- **Stretched:** one wide camera's texture, with each wall showing its slice.
- **Not checked:** the pool's mirror follows only the background viewport's camera, so the
  reflection may look off on the walls. That's fine for this test.

## Verification

- Screenshots from spots 1, 2 and 5 in both modes, to show you the difference.
- The test suite, which loads every scene, including the sandbox.

## Questions

1. Are the default room sizes fine to start (middle wall 4 m, side walls 4 m at 45°, walls 2.5 m
   tall, sweet spot 3 m back)? They can all be changed live.
2. Should the stretched mode also have a "fair" version (the single camera's image sliced by angle
   instead of by wall width), or is plain stretching the comparison you want?

## As built (2026-11-17)

- One script builds everything (`sandbox/test_wall_rig.gd`); the `.tscn` is just its root.
- Three modes (Tab):
  - three cameras;
  - one camera, fair: the image projected onto the walls from the sweet spot by a small shader;
  - one camera, stretched: sliced by wall width.
- The single camera gets the three walls' pixels combined (5173 × 380 at the defaults) and sees
  at most 80° to each side.
- **Findings at the defaults** (screenshots from the sweet spot, off to the left, and above):
  - **Three cameras:** one seamless window from the sweet spot; the horizon, checker floor and
    cockpit floor run straight across both corners. Off to the left, a gentle kink at the
    corners: the cost of any fixed rig.
  - **One camera, stretched:** the horizon folds into a V at both corners, the trees are
    squeezed, and the side walls show the wrong directions.
  - **One camera, fair:** right from the sweet spot, but the tops and bottoms of the side walls
    are cut off (beyond what one flat image can reach), and it has 380 px of height against
    640 per wall, so it's softer everywhere.
  - Three cameras win on coverage and sharpness, not just on geometry.
- Note: as a physically correct window, the walls show about 45° of view vertically from the sweet
  spot (the game's camera now shows 90°). How much of the world the walls should show is a
  separate decision for the real rig.
