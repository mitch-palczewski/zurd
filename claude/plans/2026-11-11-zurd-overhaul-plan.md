# Plan: Zurd overhaul, built in playtested iterations

*Rewritten 2026-11-12 as an implementation plan for iteration 1, from the **Zurd Core Design Doc**.
Approved 2026-11-12 (with the anger change below); being built. The Zurd AI Design Spec is the
idea bank for later iterations.*

## Goal

Replace the temporary Zurd scripts with the core behaviour: Zurds that push players to build
sculptures instead of spamming objects, start out harmless, and can be stunned and driven off.
Then grow the behaviour one playtested iteration at a time.

Iteration 0 (hardening step 2, the world split) is done: the director has a home in
`game_systems.tscn`, and Zurds have the `Actors/Zurds` container.

## Iteration 1: the core Zurd

### Status (2026-11-12): built

Built as planned, in the five steps. 97 tests pass (about 40 s), including 11 new Zurd scene tests
and 9 anger unit tests. The scene edits were made with the editor closed and match the engine's
own save of each scene line for line.

Changes found while building:

- **Hit cooldown (0.4 s):** one mouse swat fires a spread of 11 projectiles, and a ram stays in
  contact for several frames, so each would have counted as several swats and driven a Zurd off
  at once. Hits within the cooldown of the last one now don't count (in the design doc too).
- **Hunting slows down near the target:** at the new 30 m/s, a Zurd circled food a few metres away
  forever, because its turning circle was wider than the gap. Hunting now slows within
  `arrival_radius` (20 m) and while the target is well off to the side (`min_arrival_speed`
  20%). A test (food right beside a Hostile Zurd) guards it; it fails without the fix.
- **Object hits count even on the Zurd's own target:** a Passive Zurd could pick an approaching
  object to nibble a moment before it entered the hit area, and the hit was then ignored. Only
  the speed check (8 m/s) decides now.
- **Passive Zurds nibble only loose objects** (decision 8), so small sculptures stay safe.
- Tests: `load_world(with_terrain, with_zurds)` keeps other tests Zurd-free, and
  `wait_until_freed` waits on an object without holding it (a condition that held it logs an
  error once it's freed).

Left for Mitch: open the project and play (F5), with the testing HUD at the top left, using the
playtest checklist below.

### What the player sees

Three Zurds drift around near the ship, ignoring the players. If a Zurd happens to drift into an
object, it nibbles it slowly. As loose objects pile up past 15, as a sculpture grows past 15
objects, or as Zurds get swatted, a shared anger rises; launching under the limits only holds it. The Zurds nearest the mess turn
Hostile: tinted red, faster, and hunting loose objects, then large sculptures. Two swats stun a
Zurd and the third drives it far away for 20 s. Ramming it with the ship counts as a swat. Hitting
it with a launched object only stuns it, and then it eats that object. When the players calm
down, the anger falls and the Zurds go back to drifting. A health bar over each Zurd shows its
swats, and a testing HUD shows the anger.

### The anger (exact rules)

*Changed at approval (2026-11-12):* anger rises when the players **add** objects past the limits
or **attack** Zurds, and falls once they stop. A mess that just sits there doesn't keep raising
it.

One value from 0 to 1, kept by the `ZurdDirector` in a pure `ZurdAnger` class so the rules can be
unit-tested. Each event adds a fixed amount:

- **Mess:** an object launched (`object_launched`) while the loose objects (tracked
  `RigidBody3D`s that aren't masses, counting the new one) are over `tolerated_mess` adds
  `mess_anger`.
- **Large sculptures:** when a sculpture (not a cloud) grows by fusing, combining or merging, each
  part added beyond `tolerated_sculpture_size` adds `sculpture_anger`. The director compares each
  mass's part count with the last one it saw, so a merge followed by a combine isn't counted
  twice.
- **Launches under the limits hold the anger** (changed 2026-11-12 after the first play; the
  rush rule was dropped): they reset the calm timer without adding anything.
- **Attacks:** each swat, ram or launched-object hit on a Zurd (`zurd_stunned`,
  `zurd_driven_off`) adds `attack_anger`.
- **Falling:** once nothing has added anger for `calm_delay`, it falls by `decay_rate` per second.
  Launches under the limits don't add anger, so they don't hold it up either.
- Clamped to 0…1. `zurd_anger_changed` fires when it moves by 0.01 or more.

Starting values (exports on the director, tuned at playtests):

| Value | Start | Meaning |
| --- | --- | --- |
| `tolerated_mess` | 15 | Loose objects before launches add anger |
| `mess_anger` | 0.05 | Per launch while over the limit |
| `tolerated_sculpture_size` | 15 | Parts before growth adds anger (hard cut-off) |
| `sculpture_anger` | 0.03 | Per part added beyond the limit |
| `attack_anger` | 0.1 | Per swat, ram or object hit |
| `calm_delay` | 3 s | Quiet time before anger falls |
| `decay_rate` | 0.05 /s | Full anger to calm in 20 s |

### Who turns Hostile

- **How many:** `round(anger × number of Zurds that aren't driven off)`.
- **Which:** ranked by distance to the nearest mess (the nearest loose object, or the nearest
  piece of a large sculpture, anywhere in the world). The nearest turn Hostile first.
- **Calming:** when fewer should be Hostile, the furthest Hostile Zurds return to Passive, but
  only once they've been Hostile for `hostile_cooldown` (10 s).
- A driven-off Zurd is Passive and can't be picked until it returns.
- `zurd_state_changed(zurd, hostile)` fires on every change.

### What a Zurd does

| State | Movement | Eating |
| --- | --- | --- |
| **Passive** | Wanders around its home (the spot it started at), within `home_radius` (100 m), at wander speed (10 m/s). Hovers while nibbling. | Only a loose object within `nibble_distance` (3 m) of its mouth (sculptures are left alone), at `nibble_speed` (×0.33 of normal eating). Never steers toward food. |
| **Hostile** | Hunts at hunting speed (30 m/s): the nearest loose object in sight; else the nearest piece of the largest sculpture in sight over the size limit; else, with nothing in sight, toward the nearest mess anywhere (all Zurds know the world). | Normal eating (the mouth's `eat_duration`). |
| **Stunned** | Stops, knocked back along the hit (`knockback_speed`, 8 m/s, easing to a stop) for `stun_time` (1.5 s). | Bite cancelled; none while stunned. |
| **Driven off** | Flies directly away from the ship at `retreat_speed` (40 m/s) until `retreat_distance` (300 m) from it; stays there (wandering) for `away_time` (20 s), then returns home Passive. | None. |

**Bumping:** a Zurd flying into objects or sculptures it isn't eating knocks them around (the
movement component's push, extended from masses to loose objects).

**Sight** is a vertical cylinder: anything within `sight_radius` (150 m) on the ground plane, at
any height. Targets come from `ObjectTracker`'s list (no physics queries), re-chosen every
0.25 s.

### Hits

- **Swat** (the mouse swat projectile, the lidar later) and **ramming** (the ship hitting the Zurd
  at its existing `min_impact_speed`, 2 m/s) both call `take_swat`. Swat 1 and 2 stun; swat 3
  drives off and resets the count when the Zurd returns. `zurd_stunned` and `zurd_driven_off`
  fire.
- **A launched object** hitting the Zurd's new hit area at `object_hit_speed` (8 m/s) or more
  stuns it without counting as a swat. When the stun ends, that object becomes the Zurd's target
  until it's eaten or gone (in either state).

### Placeholders for playtests

- **Health bar:** a `Label3D` above the Zurd, billboarded, showing swats taken out of 3 (for
  example `■■□`). Always visible during playtests.
- **Hostile look:** a red `material_overlay` on the Zurd's mesh while Hostile. No sounds (no
  assets yet).
- **Testing HUD:** a small on-screen panel (`scenes/ui/hud/zurd_testing_hud.tscn`) with the anger,
  Hostile and total Zurds, loose objects and the largest sculpture. The director adds it when
  `show_testing_hud` is on (on by default for now).

### Files

| File | Change |
| --- | --- |
| `scripts/autoload/event_bus.gd` | New signals: `object_launched(obj)`, `zurd_anger_changed(anger)`, `zurd_state_changed(zurd, hostile)`, `zurd_stunned(zurd)`, `zurd_driven_off(zurd)` |
| `scenes/characters/player/launch_object_component.gd` | Emit `object_launched` |
| `scenes/characters/player/player_ship.gd` | Ramming: an impact on a node with `take_swat` swats it |
| `scenes/characters/enemy/zurd_anger.gd` | New: `ZurdAnger` (RefCounted), the anger rules above |
| `scenes/characters/enemy/zurd_director.gd` | New: `ZurdDirector`, world counts, anger, choosing who's Hostile, spawning the starting Zurds, the testing HUD |
| `scenes/world/game_systems.tscn` | Add the `ZurdDirector` node (with the Zurd scene) |
| `scenes/world/base_world.tscn` | Remove the hand-placed Zurd (the director spawns them) |
| `scenes/characters/enemy/zurd.gd` | Rewritten: state (Passive, Hostile, stunned, driven off), swats and hits, the health bar, the tint. No more growing or shrinking |
| `scenes/characters/enemy/zurd_sight_component.gd` | New, replaces `zurd_target_component.gd`: the sight cylinder and target choice |
| `scenes/characters/enemy/zurd_movement_component.gd` | Home wandering, hunting speed 30, stun knock-back, retreat |
| `scenes/characters/enemy/zurd_mouth_component.gd` | An eating-speed multiplier (for nibbling) and a nibble-distance check |
| `scenes/characters/enemy/zurd.tscn` | Sight component in place of the target component; a hit area (Area3D on the objects layer); the health bar `Label3D`; speeds |
| `scenes/ui/hud/zurd_testing_hud.tscn` + `.gd` | New: the testing HUD |
| `zurd_spawner.gd/.tscn`, `zurd_target_component.gd` | Deleted (replaced; the spawner's idea is in the idea bank) |
| `tests/unit/test_zurd_anger.gd`, `tests/scene/test_zurds.gd` | New tests (below) |
| `tests/test_case.gd` | `load_world` sets the director's starting Zurds to 0 unless a test asks for Zurds, so other tests stay Zurd-free |
| `CLAUDE.md`, `claude/ONBOARDING.md`, `tests/README.md` | The Zurds are no longer "temporary, don't build on"; the new design and tests |

### Build order (each step leaves the game playable; tests run after each)

1. **Signals and anger.** EventBus signals, `object_launched`, `ZurdAnger` with its unit tests.
2. **Director.** World counts, anger, choosing who's Hostile, spawning the starting Zurds;
   `game_systems.tscn` and `base_world.tscn` edits; `load_world` change. The old Zurd still
   runs, Hostile or not.
3. **The new Zurd.** Sight, movement, mouth, states, swats, hits, ramming, placeholders; delete
   the old target component and spawner.
4. **Testing HUD.**
5. **Scene tests, docs,** a full test run, then a playtest.

The scene edits are done by hand with the editor closed, verified like step 2: the engine
re-saves each changed scene and the result is compared with the hand-written file.

### Tests

**`tests/unit/test_zurd_anger.gd`** (pure rules):

- No provocation: anger stays 0, and falls from any value at `decay_rate`.
- Loose objects at the limit add nothing; over it, anger rises in proportion.
- A sculpture at the size limit adds nothing; over it, anger rises in proportion; clouds don't
  count.
- Launching under the limit, however fast, holds the anger; once launches stop, it falls.
- Anger stays within 0…1. The Hostile count is 0 at anger 0, all at anger 1.

**`tests/scene/test_zurds.gd`** (in the world, with Zurds):

- The starting Zurds spawn in `Actors/Zurds`, Passive, near the ship.
- A Passive Zurd doesn't go after an object outside the nibble distance; one inside it gets
  nibbled at the slower speed.
- Loose objects over the limit turn the nearest Zurd Hostile first; it eats loose objects before
  a large sculpture, and leaves a sculpture under the limit alone.
- When the anger falls, a Hostile Zurd stays Hostile for the cooldown, then turns Passive.
- Two swats stun (the bite is cancelled); the third drives the Zurd away from the ship; it comes
  back Passive after the away time with its count reset.
- The ship ramming a Zurd counts as a swat.
- A launched object hitting a Zurd stuns it without counting, and the Zurd then eats it.
- Launching from the ship's launcher under the limit holds the anger, then it falls.

The `tests/README.md` rule "don't pin Zurd behaviour" ends: this behaviour is designed.

### Playtest checklist

- Does 15 loose objects feel fair to a new player still learning the controls?
- Do players notice that scattering objects is what turns the Zurds Hostile?
- Is 15 parts the right size for a "large" sculpture?
- Does holding the anger while launching feel right (the Zurds don't calm down mid-build)?
- How fast should anger rise and fall?
- Do stun, stun and drive-off feel good with mouse swats? Is the health bar readable?
- Do players discover "hit it with an object, then swat it"?
- Watch how many loose objects build up over a long session: do the Zurds keep up?

### Decisions (approved 2026-11-12)

1. **Anger** rises with objects added past the limits and with attacks on Zurds, and falls once
   nothing is added and the Zurds are left alone (rules above).
2. **Large sculptures anger per part added beyond the limit** (bigger is angrier).
3. **A Hostile Zurd with nothing in sight** flies toward the nearest mess anywhere.
4. **Starting Zurds:** 3, placed 80–150 m from the ship when the world starts (a pair and a
   single). Their homes stay where they spawned.
5. **Object hits** need 8 m/s to stun; Zurds flying into objects knock them around.
6. **Speeds:** wander 10 m/s, hunting 30 m/s (was 18), retreat 40 m/s.
7. **Delete** the old spawner, the old target component and the hand-placed Zurd.
8. *(Added while building)* **Passive Zurds nibble only loose objects,** so small sculptures stay
   safe, as the design doc's goal 2 asks.

## Iteration 1.1: Zurds, the terrain and each other

*From the first playtest (2026-11-12): "the Zurds get stuck on terrain", "Zurds overlap one
another often; only one Zurd should go at a target at a time", and "it should be loose object
count + mass count that contribute to the Zurds' anger". Approved and built 2026-11-12.*

### Status (2026-11-12): built

All parts built as below; 102 tests pass. Measured over a minute with 8 Zurds wandering the real
terrain: within 2 m of the ground **0%** of the time with the fix, **14%** with the clearance and
look-ahead switched off (the new test's limit is 5%, so it catches the old behaviour). Building it
turned up a flaky test of mine: "launching holds the anger" launched 12 objects that pile into one
sculpture, and with the sculpture limit tuned to 10 the pile sometimes grew past it and rightly
added anger. The test now keeps both limits out of reach, since it's only about launching.

### The mess counts sculptures too

0. **Mess = loose objects + sculptures.** A launch adds anger when loose objects plus sculptures
   (each sculpture counts one; clouds don't) are over `tolerated_mess`. Scattering many small
   sculptures is then mess too, which pushes players toward one sculpture. The director passes
   that count to `ZurdAnger.on_launch`; the testing HUD shows it as "mess N / 15 (loose L,
   sculptures S)". A test checks that sculptures count toward the limit.

### What's wrong (measured)

A headless minute with 8 Zurds over the real terrain:

- **Half the wander destinations are at or below the ground** (488 of 960 samples). Wander legs go
  up to 40% up or down from the Zurd, with no check against the terrain, and the Zurds start near
  the ship's height, which hovers 4 m above the ground.
- So Zurds fly into hillsides and **grind along them**: 17% to 96% of the minute within 4 m of the
  ground (one Zurd pressed against it the whole time). They don't stop; they slide.
- The obstacle check is **one 5 m ray straight ahead**: 0.17 s of warning at 30 m/s.

### Fix

The terrain is a height field (no caves or overhangs), so the Zurds need terrain awareness, not a
navigation mesh:

1. **Destinations above the ground:** every wander destination is lifted to at least
   `ground_clearance` (*proposed:* 8 m) above the terrain under it (a downward ray).
2. **Terrain following:** while flying, a Zurd checks the ground under it (a downward ray every
   few frames). Below `ground_clearance` it climbs, like the ship's own ground clearance.
3. **Looking ahead by speed:** the forward ray reaches `look_ahead_time` (*proposed:* 1 s) ahead at
   the current speed, at least `avoidance_distance`. When it hits the ground, the Zurd steers
   **up** over it rather than only sideways.
4. **Food on the ground still works:** hunting aims at the target itself, so a Zurd may come down
   to an object lying on a hill; terrain following then applies only between targets, not in the
   last few metres (*proposed:* within `arrival_radius` of the target).

All three settings are exports on the movement component, for tuning.

### One Zurd per target, and personal space

Two causes, two fixes:

5. **Targets are claimed.** The director keeps who's going after what. A Zurd choosing a target
   skips objects another Zurd has claimed (and, for a sculpture, the pieces claimed by others,
   so two Zurds can work on one sculpture from different pieces). A claim is released when the
   Zurd eats the object, drops it (swat, stun, calming down) or is freed. A launched object that
   stuns a Zurd is claimed by that Zurd. If everything in reach is claimed, a Hostile Zurd takes
   the next nearest unclaimed mess, or wanders.
6. **Zurds keep apart.** Zurds don't collide with each other today (they don't check the enemy
   layer), so they fly through one another. Rather than making them collide (which jams Zurds
   against each other), each Zurd steers away from other Zurds within `personal_space`
   (*proposed:* 8 m), more strongly the closer they are. A pair spawned together drifts a little
   apart and stays near each other.

### Tests

- A scene test with the terrain: 8 Zurds wander for a minute; less than a set share of the time
  (*proposed:* 5%) within 2 m of the ground, and no wander destination below the ground.
- Two Hostile Zurds and one loose object: only one goes after it; the other takes another
  object or wanders. With a sculpture, they go after different pieces.
- A claim is released when the object is eaten, or the Zurd is swatted or calms down; the other
  Zurd can then take it.
- Zurds placed on top of each other drift apart to at least most of `personal_space` within a
  few seconds.
- Existing Zurd tests still pass (they run without terrain).

### Files

`scenes/characters/enemy/zurd_movement_component.gd` (destinations, ground check, look-ahead,
keeping apart), `zurd_director.gd` (claims), `zurd_sight_component.gd` (skipping claimed targets),
`zurd.gd` (claiming and releasing), `tests/scene/test_zurds.gd`. No scene edits.

## Iteration 1.2: finishing the meal, slow Passive feeding, a quieter health bar

*Draft 2026-11-12, from playtesting: "if the Zurd has a target and its hostility is reduced it
should still try to eat the target and only after stop being hostile"; "make the hit UI on the
Zurd smaller and more transparent"; "if there is an object in the Zurd's vision even when passive
it should navigate to it and eat it, very slowly". Approved 2026-11-12 with these answers: Passive
Zurds move to food at wander speed (10 m/s) and only the eating is slow; they eat loose objects
only; and "Zurds should be interested in sculptures and watch them nearby" (part 4). Built 2026-11-12.*

**Status (2026-11-12): built.** All four parts, plus, from the same review: a Hostile Zurd takes
3 s a bite (the mouth's `eat_duration`, was 1.5 s) and a Passive one 4 s (`passive_eat_time`,
which replaces the `nibble_speed` multiplier). Mitch's playtest tuning of the Zurd (2× scale, a
5× mesh) is kept. 104 tests pass, including new ones for Passive feeding, watching sculptures and
finishing a target before calming.

1. **Finish the meal before calming.** When the director calms a Hostile Zurd that has a target,
   the Zurd keeps that one target (it doesn't pick new ones) and turns Passive once it's eaten or
   gone. The director counts such a Zurd as already calmed, so it doesn't calm extra Zurds while
   it finishes. If the anger rises again first, the Zurd simply stays Hostile.
2. **Passive Zurds feed on what they see.** A Passive Zurd goes after the nearest loose object in
   sight (claimed, one Zurd per object) at `feeding_speed` (10 m/s, wander speed) and eats it at
   `nibble_speed` (×0.33: 4.5 s a bite). Sculptures stay safe from Passive Zurds. This replaces
   "nibble only within 3 m", so `nibble_distance` goes. Effect: stray objects disappear even when
   the Zurds are calm.
3. **A quieter health bar:** the `Label3D` swat bar becomes smaller (font 40 → 24) and
   half-transparent (alpha 0.5, thinner outline).
4. **Passive Zurds watch sculptures.** With no loose object in sight, a Passive Zurd that sees a
   sculpture goes to watch it: it flies to a spot `watch_distance` (*proposed:* 25 m) from it,
   stops for `watch_pause` (*proposed:* 3 s) facing it, then moves to another spot around it. It
   never eats it while Passive.

Tests: a Hostile Zurd told to calm while it has a target eats it before turning Passive; a
Passive Zurd goes after a loose object in sight no faster than `feeding_speed` and eats it at
`nibble_speed` (replacing the nibble test); a Passive Zurd with a sculpture in sight and no loose
objects watches it from about `watch_distance` and never targets it.

Files: `zurd.gd`, `zurd_director.gd`, `zurd_sight_component.gd`, `zurd.tscn` (the label; with the
editor closed), `tests/scene/test_zurds.gd`, the design doc.

## Later iterations (from the idea bank, when playtests ask for them)

Order to be decided from playtests:

- objectives and the difficulty ramp (Objectives Design Doc);
- more states (Curious, Suspicious) and an Alert Level display;
- the ship attack and killing;
- growth, spitting out new Zurds, population scaling, difficulty per player count;
- following clouds.

## Dependencies

- **Art and sound** from the collaborator; placeholders until then.
- **Lidar step 4** for real swats; until then, mouse swats stand in.
