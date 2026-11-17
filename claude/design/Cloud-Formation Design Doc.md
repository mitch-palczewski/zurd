# Cloud-Formation Design Doc

Zurd game · Godot (GDScript) · **Partly designed.** What a cloud does after it forms (§4) is decided and built; the moment itself (how guests see it, sound, the ship's and the Zurds' reactions) is still open (§5).


When the cloud forms create additional cloud spheres to re-enforce the cloud look. 

> Built 2026-11-17 (§4.2): `CloudPuffs` (`scenes/sculpture/cloud_puffs.gd`, adapted from the editor-only version in git commit `a22d649`) scatters soft puffs over each of a cloud's objects, and `CloudWisps` keeps small puffs coming and going around it. Both use `cloud_puff.gdshader`.

Consider zooming in and pointing the camera at the assending cloud. But this may break continuity in a bad way depending on the pace of the game wanted. 

## 1. Purpose

A cloud forming is the main payoff of the game: the guests' sculpture is finished and leaves the play area. This doc will define what that moment looks, sounds and feels like in the projected room, and whether it changes the game afterwards.

## 2. What Exists Now

From the Sculpture-Mass Design Doc (§4.7, §4.9) and `scenes/sculpture/`:

- When a mass reaches the cloud threshold count, it becomes a cloud permanently and `EventBus.cloud_formed` fires.
- Its look jumps (Sculpture-Mass Design Doc §4.7): until then its objects are solid and only part of the way to white, and at the threshold the mass swaps to the cloud material in a white flash while every object puffs up, settling 1.2× its size over `cloud_transition_time`. The cloud look is a placeholder (see the note in §4.2).
- It stops colliding with the ship, Zurds and new objects, and Zurds can no longer eat it.
- Its objects gather under a cloud body at its middle, and `CloudSky` (in `game_systems.tscn`) takes it from there: §4, built 2026-11-17.
- `SculptureFx` hooks placeholder effects to the signal (the puff-up); the design calls for a gong sound.
- The game keeps accepting objects, so a new mass can start. There is no cap on clouds (decided again 2026-11-17).

## 3. Constraints From Other Docs

- **The view never pitches or rolls under player control** (Ship-Controls Design Doc §5.1). Its top edge is 45° above level (90° vertical field of view), so a cloud *h* metres above the ship is only on screen from at least *h* metres away. High clouds are therefore always seen from a distance, which is why they must be big (§4.2).
- The ship's altitude limits are off for prototyping (ceiling 10 km), but guests fly well below the cloud zone. The ship's camera draws 12 km, so clouds on the far side of the gyre stay visible.
- **Three walls** surround the guests, so the moment can use all of them.
- **Walk-up guests** may arrive mid-game and should still understand what just happened.

## 4. Cloud Behaviour After Forming

Decided 2026-11-17 and built (`CloudSky`, `scenes/sculpture/cloud_sky.gd`). The values in 4.4 are
starting points for playtests; every world uses the same ones.

### 4.1 Rise

- After the burst and the *Rise delay*, the cloud rises to its place in the cloud zone (4.3) over
  the *Rise time*, starting slowly and arriving gently. It travels **up and outward** along an
  arc: it glides out first (away from the gyre centre, along its bearing from it), then climbs.
  Moving out first keeps it on screen longer, since the view never tilts up.
- It **grows while it rises**, reaching its full size (4.2) as it arrives.

### 4.2 Size and look

- **Proportional:** a cloud's final size is its sculpture's size times the *Scale multiplier*, so
  bigger sculptures make bigger clouds.
- **The objects stay recognisable.** A cloud is a weird giant object in the sky (a chair, a lion,
  a crocodile), like the shapes people find in real clouds. It isn't hidden in fog.
- **Cloud details** stress that it's a cloud. They're visual only: no collisions, and they don't
  count as clouds.
  - **Puffs** on each object: soft spheres scattered over its surface and half sunk into it. They
    swell, tumble and grow with their object.
  - **Wisps** around the cloud, like the scraps around real clouds: a few slots (3–8 per cloud),
    each a small cluster of puffs that appears just outside the cloud, drifts slowly away as it
    fades in, lasts 40–90 s, then thins and shrinks away. After a short wait the slot's next wisp
    appears somewhere else. They come and go rather than staying.
- **A solid look (built 2026-11-17)**, so clouds read as shapes from far away:
  - The body is about 90% opaque and shaded by the light like the puffs (white on the lit side, a
    cool blue-grey in shadow), with only a little glow and a thin warm rim.
  - **Darker, fully solid bottoms**, like the base of a real cumulus. "Bottom" is world height
    within the cloud, so it stays at the bottom as the cloud tumbles: `CloudSky` gives each
    cloud's material its middle and size every frame.
  - **Ridges and outline:** thin, partly see-through lines in a darker cool tint along each
    object's sharp edges (`cloud_ridges.gdshader`). Lines on edges only a few pixels long on screen
    fade out, so a far-off cloud doesn't turn into a scribble. The body also darkens gently toward
    its silhouette, so smooth curves get an outline too.

### 4.3 The cloud zone and the gyre

- **Height:** the zone sits at about the same level as the sky canopy, and it's **thick**: clouds
  spread over a few hundred metres of height, which gives depth.
- **Gyre:** every cloud circles a fixed centre (the world's origin) slowly, in the same direction
  (which direction doesn't matter), which gives the sky some organisation. Inner rings turn a
  little faster (*Gyre shear*), so clouds on neighbouring rings pass one another. Real clouds
  often line up in rows ("cloud streets"). Clouds on rings around one centre may do that on their
  own, so test the gyre as it is first and only add lanes if the lines don't appear.
- **Stays in the play area:** a cloud never leaves its ring range or the zone.
- **Spacing:** clouds may drift into one another and apart again, but a gentle push moves
  overlapping clouds' orbits apart, so they don't *stay* overlapped. No merging.
- **Small life:** each cloud bobs gently, tumbles slowly in any direction (its axis wanders) and
  breathes (a slight swell in and out). It all fades in as the cloud rises.
- **The sky canopy is ignored:** clouds have no connection to it and may pass in front of or
  behind it.

### 4.4 Tunables

On the `CloudSky` node in `scenes/world/game_systems.tscn`.

| Tunable | What it does | Value |
|---|---|---|
| Zone heights | Heights (world) where clouds' middles circle | 1000–1550 m (the canopy in `zurd_world02` is at about 1210–1480 m) |
| Gyre centre | The point (X, Z) clouds circle | The world's origin (the pool court in `zurd_world02`) |
| Gyre radius range | How far from the centre clouds circle | 1200–3500 m; may need to be bigger |
| Gyre lap time | One lap at the middle radius | 15 min |
| Gyre shear | How much faster inner rings turn (0: like a wheel; 1: every ring at the same m/s) | 1 |
| Rise delay | How long a new cloud holds still, so guests see the change | 0.8 s |
| Rise time | Leaving to arriving in the zone | 40 s |
| Scale multiplier | Final size ÷ sculpture size | 6×. First look (2026-11-17): from the play area, 6× clouds are small specks 2–4 km away; 20× reads as giant objects in the sky. |
| Push speed | Fastest each overlapping cloud is pushed apart | 4 m/s |
| Bob | Height and period | ±10 m, 30 s |
| Tumble | One full turn | 4 min |
| Breath | Swell and period | ±3%, 15 s |
| Puffs per object, puff size | Puffs on each object; radius as a share of the object's longest side | 8; 8–16% |
| Wisp count | Wisps per cloud (min, max) | 3–8 |
| Ridge angle | Faces meeting at a sharper angle get a ridge line | 35° |

The look's own values (opacity, glow, shading, outline, base) are on `assets/materials/sculpture_cloud.tres` and `cloud_ridges.tres` (line colour, width, fade).

## 5. Questions to Answer

Key, still open (2026-11-17): **how the ship reacts to a new cloud** (2) and **how the Zurds react** (5).

1. **Seeing the rise:** how do guests watch a cloud leave the view? Options so far:
   - a scripted slow look-up on all walls that follows the cloud, then returns (the only pitch in the game, never player-controlled),
   - a fixed upward framing: a taller field of view or a slight upward camera tilt,
   - something that doesn't move the camera, e.g. a reflection, a shadow, or a light shift on the walls.
2. **Controls during the moment:** do the controls pause, slow down, or keep working? How does the ship react to a new cloud?
3. **Sound:** the gong, plus music or a crowd cue? Does it play across all three walls?
4. **Visual transformation:** puffs are built (4.2). Still open: fog, light and color changes, and the look note in 4.2.
5. **Zurds:** do they react, e.g. scatter, freeze or stop eating for a moment?
6. **After the moment:** does a cloud count toward a goal or end state, and is progress shown anywhere?
7. ~~**Visibility later:**~~ Answered 2026-11-17: clouds stay around the play area in the gyre (4.3), so the sky fills up over a session.

## 6. Out of Scope

- The sculpture-mass rules for reaching the threshold (Sculpture-Mass Design Doc).
- Ship controls (Ship-Controls Design Doc).
- End-game state, unless question 6 decides that a cloud count ends the game.
