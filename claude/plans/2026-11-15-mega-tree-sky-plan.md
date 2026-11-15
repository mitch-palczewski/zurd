# Mega trees fading into the sky — plan

Status: **approved 2026-11-15** (answers at the end; the canopy footprint follows the trees,
answer 8).

## Goal

Make the mega trees read like trees too tall to see the tops of. Two parts, built in order:

1. **Trunk fade:** the trunks blend into the sky colour as they rise, so no trunk ever shows where it ends.
2. **Canopy:** a painterly 2D canopy floats high above the tree area only (not the whole sky). Its outline is organic and slowly changes shape. It is built from a few stacked, curved, noise-masked shells so it has some depth when the ship moves. It is backdrop only: no collision, no gameplay link.

## What exists now (measured 2026-11-15)

- `scenes/scenery/mega_tree.tscn` is a plain instance of `assets/models/terrain/mega_tree.glb` (one mesh, `Cylinder`, **no material**, so it renders default white). The model is about 16.6 units tall: Y −1.87 … 14.74 plus a node offset of 1.21.
- `scenes/world/terrain02.tscn` (used by `zurd_world02.tscn`) places five of them under `megatree` at scale 100. Their bases are at Y ≈ 20, their tops at **Y ≈ 1600**. They stand 1280–1610 units from the origin along −Z, spread over X −263 … 719.
- The ship's ceiling is Y 120 (`altitude_ceiling`). The ship camera has `fov = 90` (vertical) and never pitches, so **the top edge of the screen is 45° up**. From the play area, a point on a tree is on screen only while its height is less than its distance from the camera. In practice that means **below roughly Y 1000–1300** from the middle of the map, and lower as the ship gets closer. The tree tops are already off screen, so the fade and the canopy must sit low enough to be seen.
- The sky is a `PanoramaSkyMaterial` (`assets/_misc/citrus_orchard_road.hdr`, `energy_multiplier` 0.4), in `scenes/world/environment.tscn`.

## Approach

### Shared: matching the sky's colour

New include file `assets/shaders/sky_match.gdshaderinc` with `sky_color(world_dir)`. It samples the same panorama texture in the view direction, using Godot's own equirectangular mapping, and multiplies by the same energy. A trunk faded to this colour matches the sky *directly behind it*, so it vanishes instead of turning into a flat grey band.
- It's output as `EMISSION`, with `ALBEDO` and specular pushed to 0 as the fade completes, so sunlight and shading don't brighten it.
- Uniforms: `sky_panorama` (the same `.hdr`), `sky_energy` (0.4), `sky_tint`.
- A fallback `fade_color` (used when no panorama is set) keeps it simple if the panorama match looks wrong.

### Part 1: trunk fade

- New `assets/shaders/sky_fade.gdshader` (spatial, opaque) and material `assets/materials/mega_tree.tres`.
- `fade = smoothstep(fade_start, fade_end, world_y + wobble)`. `wobble` is a little 3D noise on world position, so the fade line is uneven instead of a ruled line. Its strength is `fade_wobble`, 0 to turn it off.
- Base trunk look: `base_color` uniform plus a simple vertical shade; no texture yet.
- Assign it in `mega_tree.tscn` as `material_override` on the `Cylinder` child. That's allowed because the scene inherits the `.glb`, so no generated file is edited and a re-export keeps it.
- Shadows still come from the full trunk, which is correct.

### Part 2: canopy

- New `assets/shaders/sky_canopy.gdshader`:
  - Spatial, `unshaded`, `blend_mix`, `cull_disabled`, `depth_draw_never`, no shadows.
  - Shape: the alpha comes from domain-warped FBM on 3D value noise, `fbm(p + warp·fbm(p + t))`, with `TIME · morph_speed` as the third axis. The outline changes shape over time instead of sliding.
  - Coverage: thresholded with soft `edge_softness`, and multiplied by an oval footprint mask (`footprint_radius`, `footprint_falloff`). The canopy then exists only over the trees and thins out at the rim.
  - Colour: the sky colour (shared include) mixed toward `cloud_color`, plus an optional painted `canopy_texture` mapped in world XZ (`texture_scale`, slow `texture_drift`). This keeps the paint stroke in place while the outline changes.
  - Curve: the vertex shader bends a flat subdivided plane into a shallow dome (`dome_depth`): the middle sits higher than the edges, so the canopy isn't seen as a flat sheet from far away.
  - Layers: `instance uniform float layer` changes each shell's noise offset and opacity, so one material serves every layer.
- New scene `scenes/scenery/sky_canopy.tscn`: a `Node3D` with **4** `MeshInstance3D` shells (shared `PlaneMesh`, about 2000 × 2000, 64 subdivisions), stacked `layer_spacing` (~40 units) apart. Plain scene, no script.
- Placed in `terrain02.tscn` under `megatree`, centred over the five trees (about X 230, Z −1450). Its height is a tuning value, see question 4.

## Files

| File | Change |
|---|---|
| `assets/shaders/sky_match.gdshaderinc` | new |
| `assets/shaders/sky_fade.gdshader` | new |
| `assets/shaders/sky_canopy.gdshader` | new |
| `assets/materials/mega_tree.tres` | new |
| `assets/materials/sky_canopy.tres` | new |
| `scenes/scenery/sky_canopy.tscn` | new |
| `scenes/scenery/mega_tree.tscn` | `material_override` on `Cylinder` |
| `scenes/world/terrain02.tscn` | add the canopy instance |
| `CLAUDE.md` | one line under World about the trunk fade and canopy |

## Steps

1. Trunk fade (sky_match include, fade shader, material, override in `mega_tree.tscn`). Stop for a look in the editor and in the game, then tune the heights.
2. Canopy (shader, material, scene, placement). Stop for a look, then tune height, coverage, speed and colour.

## Risks

- **Panorama mapping off:** if the include's mapping doesn't match Godot's sky exactly, the trunk ends in a visible patch of the wrong colour. Check by setting the fade to full on one tree and looking at its edge against the sky; fall back to `fade_color` if needed.
- **Tonemapping and exposure:** emission and sky both go through the same tonemapper, so they should match. Watch for glow or exposure changes in the `Environment` later.
- **Seen from too close or too high:** the canopy is a shell, so it breaks if the ship gets near. That can't happen with the ceiling at 120 and the canopy many hundreds of units up.
- **Transparent sorting:** the shells sort against each other and against `sculpture_cloud` clouds. Sorting goes by mesh centre, and the shells are stacked, so the order stays stable. Check that a rising sculpture cloud doesn't pop through.
- **Cost:** 4 full-screen-ish transparent layers with FBM. Keep the octaves low (4) and measure the frame time in the game.
- **Reflection:** the planar reflection renders the scene again, so trees and canopy appear in the pool, at the same cost a second time while the pool is on screen.

## Verification

- Visual, in `zurd_world02`: fly the full area at low and high altitude. Check that no trunk end or band is visible, the canopy edge looks organic and changes over a minute or two, and the layers show parallax.
- Frame time before/after with the Godot monitor.
- Tests: this is look only, with no rule to test, so no new tests (`tests/README.md`: tests check rules, not tuning). Run the full suite once to confirm nothing broke.

## Open questions

1. **Fade target:** match the panorama behind the trunk (recommended: the trunk vanishes into whatever sky is behind it), or fade to one chosen colour (simpler, more stylised, a visible "haze" tone)?
2. **Fade heights:** start ~Y 250, fully gone by ~Y 800, so the dissolve happens on screen from most of the play area (the tops at 1600 are never seen). OK as a starting point?
3. **Uneven fade line** (noise wobble on the fade height): yes, subtle?
4. **Canopy height:** to be on screen from the play area, its underside has to be around **Y 800–1100**. That's still 7–9× the ship ceiling, but it means the canopy sits **partway up the trees**: the trunks fade and pass up into it, rather than the canopy sitting on the true tops at 1600. Is that the look you want?
5. **Canopy texture:** do you have a painted texture for it, or should I start procedural (sky colour mixed toward a cloud tone) with an empty texture slot for later?
6. **Canopy colour/mood:** light and bright (white/gold, like sun-lit mist), or darker and moody, closer to the Ash Lake grey?
7. **How fast it changes:** slow (the outline noticeably different after about a minute) as the default?
8. **Footprint:** one oval over all five trees, or a patch per tree that merges where they overlap?
9. **Trunk base colour:** keep plain white/grey for now, or a colour you have in mind?
10. **World:** only `terrain02` / `zurd_world02` (the only one with mega trees)? Which world is the main one now that `zurd_world.tscn` is deleted?
11. **Uncommitted changes:** the tree has many (new worlds, terrain, mega tree, reflecting pool moves). Commit them first before I build (recommended), build on top, or stop?

## Answers (2026-11-15)

1. The sky behind them. 2. Yes, adjustable. 3. Yes, subtle. 4. Yes. 5. Start with a stand-in and
leave the slot to swap. 6. A very subtle gold. 7. Slowly, to be refined. 8. Continuous where the
trees stand close: left to Claude, who chose soft patches around each tree that merge (below).
9. Grey-pink. 10. `zurd_world02` / `terrain02` only. 11. Committed by the user before the build.

## As built (changes from the approach above)

- **The trunk fades with transparency, not by painting the sky colour.** Painting the sky colour
  worked against the open sky, but where the far side of the canopy is behind a trunk on screen
  the faded trunk showed sky blue in front of the canopy. The trunk material
  (`sky_fade.gdshader`) now sets `ALPHA`, with `depth_prepass_alpha` so the solid lower trunk still
  writes depth, and `render_priority = -1` so trunks draw before the canopy and other transparent
  things. It vanishes into whatever is behind it. `sky_match.gdshaderinc` is used by the canopy
  only. (Godot draws the background sky from a 256-pixel cubemap, so a surface painted with the
  panorama is slightly sharper than the sky; raising the sky's radiance size to 2048 to match
  crashed the GPU driver on the dev machine, so the environment is unchanged.)
- **The footprint follows the trees.** `SkyCanopy` (`scenes/scenery/sky_canopy.gd`, `@tool`) finds
  every node in group `mega_trees` (added to `mega_tree.tscn`), builds one grid mesh over them
  (margin 1.6 × `tree_radius`, raised `dome_height` in the middle), and bakes into each vertex's
  colour how much canopy belongs there: a sum of soft falloffs around each tree, so close trees
  share one canopy. The shells are built in the editor and the game and aren't saved; *Refresh*
  rebuilds them after trees move. The shared material stays live-tunable in the inspector.
- Added `assets/shaders/noise.gdshaderinc` (3D value noise and fbm) for the fade line and the canopy.
- Added `shape_contrast` to the canopy: without it the noise spans too little and the outline
  followed the round footprint.
- The canopy's colour starts from the sky's brightest channel (not its luminance, which went muddy
  against blue sky), tinted toward `cloud_tint`. The paint slot holds a stand-in `NoiseTexture2D`
  at strength 0.25, read as plain values (mid-grey = no change); clear it or swap in a painting.
- Starting values: fade 250 → 800, wobble 40 m; canopy at Y 850, `tree_radius` 550, 4 shells
  40 m apart.

## Verification done

- Screenshots of `zurd_world02` from four spots (windowed, scratch script). The trunks fade into
  the sky and up into the canopy with no visible ends. The canopy sits over the grove with an
  irregular outline. Two shots 5 s apart at 12× morph speed show the outline changing.
- Test suite: all unit tests pass (including every scene and resource loading). Every scene test
  fails before this change too: they load `res://scenes/world/zurd_world.tscn`, deleted in
  b81ab58.
