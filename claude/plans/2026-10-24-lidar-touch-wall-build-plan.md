# Plan: LiDAR touch walls

## Goal

Turn a projected wall into a touch surface. An RPLIDAR A1 scans a plane parallel to the wall,
a centimetre or two in front of it. When a hand breaks that plane, the game learns *where on the
projected image* it happened, and acts on it.

```
Raw scan (angle°, mm)                    LidarDevice (or mouse source)
  → lidar-local 2D (x, y mm)             LidarGeometry.ToLocal
  → touch (id, centroid, down/up)        TouchDetector  (baseline → foreground → blobs → tracking)
  → projected-image UV (0..1, 0..1)      WallCalibration (homography, 5-point touch calibration)
  → game action                          LidarManager → Godot signal → GDScript gameplay
```

## Decisions locked in

- **There is a projected image on the wall.** Calibration maps lidar space onto that image with a
  **homography**, which absorbs projector keystone, sensor rotation and mirroring.
- **UV convention:** (0, 0) is the top-left of the projected image and V grows downward, matching
  Godot viewport coordinates. UV × viewport size = screen pixel.
- **All projectors are displays on one computer**, so the calibration target window is a
  fullscreen Godot window placed on the projector's screen.
- **Each wall shows a camera view of the game world.** A touch's UV becomes a ray from that
  wall's `Camera3D`.
- **One lidar per wall.** Build for N walls, but get one wall working end to end first.
- **Device and detection logic stay in plain C#** under `scripts/lidar/`. Godot nodes are thin
  viewers or bridges, so the game runs exactly the code that was debugged in the setup scene.
- **Main thread only, except inside `LidarDevice`.** Consumers poll `TryGetNewScan`; nothing
  touches Godot nodes from the driver thread.
- **Walls are identified by the lidar's serial number**, not by COM port, because port numbers
  can change on replug.
- **Calibration is saved; the baseline is not.** Calibration is geometry and lasts until the
  sensor moves. The baseline describes the room's contents and is recaptured each session.
- **Angle offset and mirror are display-only.** The homography handles orientation.

## Done so far

| Step | What exists |
|---|---|
| **1. Device, status, 2D view** | `LidarDevice` (connect on a worker thread, whole rotations by angle wrap, three-stage status with the lidar's own health query), `lidar_setup.tscn` with status panel and zoomable 2D point view. |
| **2. Baseline, detection, tracking** | `TouchDetector` with per-0.5° low-percentile baseline, depth-change foreground, sweep-order blob clustering with seam merge, and tracking (ids, confirm after N rotations, release grace, Began/Ended events). Setup scene: capture/clear baseline, live tuning, touch markers, event log. Checked against synthetic scans. |
| **2b. Driver fix** | `RpLidar.NET` vendored into `thirdparty/RpLidar.NET/` and patched: the packaged driver dropped a third to a half of all Sensitivity-mode points (the view blinked between halves of the room) and produced phantom points. See its README. Standard mode is not decoded by the driver; use Sensitivity on an A1. |

## Step 3 — Calibration wizard and UV

**Targets on the projected image.** The wizard has to show targets *on the wall*, so the setup
scene opens a fullscreen target window on the chosen projector's screen.

**Procedure**
1. Capture a baseline with the scan plane clear.
2. Show five targets in turn: four corners **inset about 10%** from the image edges, then the
   centre. The UVs of the targets are known. Corners are inset because a hand near a
   baseline surface (frame, side wall) is not detected, and the nearest corner may sit inside the
   A1's 150 mm minimum range.
3. Accept a target only when there is **exactly one confirmed touch**, held steady for about a
   second (at least 5 rotations, centroid spread under ~20 mm). Average it, then wait for release
   before showing the next target.
4. **Solve and check.** Fit the homography to the four corners and measure how far it misses the
   centre target. That miss is the honest error number; four points alone always fit perfectly.
   Then refit using all five points (least squares, normalised DLT) for the saved result.
5. Reject degenerate results: targets nearly collinear, a non-convex or self-crossing quad, or a
   centre error over a threshold. Offer a redo.

**After calibration**
- Touch markers show UV; the 2D view draws the projected image's outline (UV 0–1 mapped back
  through the inverse homography).
- **The calibrated area becomes the detection area.** Touches outside UV 0–1 plus a small margin
  are ignored and their points drawn dim. This replaces the crude *Max range* setting.
- **Follow test:** the target window draws a dot at every live touch's UV. Touch anywhere and the
  dot should land under your finger.

**Persistence:** `user://lidar_config.json`, one entry per lidar serial: homography, the five
measured points and their UVs, the centre error, date, and display settings (angle offset,
mirror). Connecting to a lidar loads its calibration automatically.

**Done when** the follow-test dot lands within about 2 cm of the fingertip across the whole image,
and calibration survives a restart and a USB replug to a different port.

## Step 4 — `LidarManager` and game hookup, one wall

**Build**
- `LidarManager`, a C# `Node` that owns one wall's pipeline (source, detector, calibration),
  polls in `_Process`, and emits Godot signals that GDScript can connect to: a touch began (wall
  id, touch id, UV) and a touch ended.
- **UV to game:** the projected image is a rendered game view, so UV × viewport size gives a
  screen position, and that view's `Camera3D` turns it into a ray. A touch then aims or launches
  along that ray. This replaces the earlier idea of a fixed 3D wall rectangle.
- **Session start-up in the game:** connect, load calibration by serial, then capture the
  baseline behind an on-screen "keep the wall clear" prompt.
- **Mouse source:** a fake source where clicking the game window produces touches, so gameplay
  can be built without a lidar. Keyboard controls keep working.
- **`ILidarSource`:** a small interface over `LidarDevice` (state, `TryGetNewScan`, connect,
  dispose), so `LidarManager` can take either the real lidar or the mouse source. Introduced here
  because the mouse source is the first thing that needs it.
- **Measure latency** from touch to game event. The A1 turns about 5.5 times a second, so
  confirming after 2 rotations costs roughly 200–400 ms. Try confirming after 1 rotation
  and a higher motor speed.

**Done when** touching the projected wall makes the game act at that point, with acceptable
latency, and the same gameplay works with the mouse source.

## Step 5 — Multiple walls

**Build**
- N walls at once: config per serial, one pipeline per wall in `LidarManager`, and per-wall tabs
  (port, baseline, calibration, live view) in the setup scene.
- Each wall maps to its own viewport/camera.
- **Duplicates at shared edges:** filtering touches to each wall's calibrated area already stops
  most double reports. Only overlapping projections need explicit merging.
- **3D room view (optional):** walls, lidar positions and live touches in one 3D scene. Decide
  after step 4 whether it's still needed; with each wall mapped through its own camera, the 2D
  views and follow test may be enough.

**Done when** all walls run together and each touch is reported once, by the right wall.

## Later, if needed

- Adapt the baseline slowly over time, so a moved chair doesn't need a recapture.
- Save the baseline alongside the calibration for faster start-up.
- Push touch centroids back by a finger radius (the lidar sees only the near side of a hand).
- Correct projector lens distortion, if the follow test shows curved errors near the edges.
- **Recording and replay** (dropped from the main steps: the lidar is at hand, and calibration
  needs the real wall anyway). Build it if:
  - the lidar ends up installed somewhere you can't easily stand at it;
  - an intermittent detection bug can't be reproduced on demand;
  - tuning several walls needs identical input across changes.

  Start with a record-only button (raw scans to a file, about 40 lines) and add replay only when
  needed. `TouchDetector` only consumes `LidarScan`, so adding it later needs no rework.

## Housekeeping

- Commit after each step, as `feat(lidar): ...`.

## Open questions

1. **How many walls, and do their projected images touch or overlap?**
2. **What does a touch do in the game?** Tap to launch, hold, drag? This decides whether step 4
   needs "moved" events as well as began/ended.
3. **Where is each lidar mounted relative to its projected image?** This affects the corner inset
   and the detection range.
4. **How does the game render several camera views on one computer?** One Godot window per
   projector, or one big window spanning them? Decide by step 5.
