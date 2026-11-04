# Cloud-Formation Design Doc

Zurd game · Godot (GDScript) · **Placeholder.** This doc collects what exists and the questions to answer before the cloud moment is designed.


When the cloud forms create additional cloud spheres to re-enforce the cloud look. 

Consider zooming in and pointing the camera at the assending cloud. But this may break continuity in a bad way depending on the pace of the game wanted. 

## 1. Purpose

A cloud forming is the main payoff of the game: the guests' sculpture is finished and leaves the play area. This doc will define what that moment looks, sounds and feels like in the projected room, and whether it changes the game afterwards.

## 2. What Exists Now

From the Sculpture-Mass Design Doc (§4.7, §4.9) and `scenes/sculpture/`:

- When a mass reaches the cloud threshold count, it becomes a cloud permanently and `EventBus.cloud_formed` fires.
- Its material blends to the cloud look over `cloud_transition_time`. The look is a placeholder.
- It stops colliding with the ship, Zurds and new objects, and Zurds can no longer eat it.
- It rises at `rise_speed` to a random height in `atmosphere_y_range` (150–200 m), then drifts slowly. The drift is cosmetic.
- `SculptureFx` hooks placeholder effects to the signal; the design calls for a gong sound.
- The game keeps accepting objects, so a new mass can start.

## 3. Constraints From Other Docs

- **The view never pitches or rolls under player control** (Ship-Controls Design Doc §5.1). The ship's ceiling is 120 m, below the cloud band, so a rising cloud leaves the level view.
- **Three walls** surround the guests, so the moment can use all of them.
- **Walk-up guests** may arrive mid-game and should still understand what just happened.

## 4. Questions to Answer

1. **Seeing the rise:** how do guests watch a cloud leave the view? Options so far:
   - a scripted slow look-up on all walls that follows the cloud, then returns (the only pitch in the game, never player-controlled),
   - a fixed upward framing: a taller field of view or a slight upward camera tilt,
   - something that doesn't move the camera, e.g. a reflection, a shadow, or a light shift on the walls.
2. **Controls during the moment:** do the controls pause, slow down, or keep working?
3. **Sound:** the gong, plus music or a crowd cue? Does it play across all three walls?
4. **Visual transformation:** puffs, fog, light and color changes (Sculpture-Mass Design Doc §4.9 defers puffs and fog).
5. **Zurds:** do they react, e.g. scatter, freeze or stop eating for a moment?
6. **After the moment:** does a cloud count toward a goal or end state, and is progress shown anywhere?
7. **Visibility later:** should finished clouds stay visible from the play area, e.g. as a sky that fills up over a session?

## 5. Out of Scope

- The sculpture-mass rules for reaching the threshold (Sculpture-Mass Design Doc).
- Ship controls (Ship-Controls Design Doc).
- End-game state, unless question 6 decides that a cloud count ends the game.
