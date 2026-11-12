# Plan: Zurd overhaul, built in playtested iterations

*Draft, rewritten 2026-11-12 to build from the **Zurd Core Design Doc** (two states, shared
anger, swats that stun and drive off). Not approved; no code yet. The Zurd AI Design Spec is the
idea bank for later iterations.*

## Goal

Replace the temporary Zurd scripts with the core behaviour: Zurds that make players build
sculptures instead of spamming objects, start easy, and can be stunned and driven off. Then grow
the behaviour one playtested step at a time.

## What exists today

| Part | Today | Core design |
| --- | --- | --- |
| `Zurd` (`zurd.gd`) | Coordinator: target → movement → mouth. Grows when it eats, shrinks when swatted. | Passive or Hostile; no growth or shrinking for now. |
| `ZurdTargetComponent` | Picks any tracked object, random or closest. | Hostile: loose objects it can see, then the largest sculpture over the size limit. Passive: none. |
| `ZurdMovementComponent` | Hunt, wander, avoidance, bobbing, holds the mouth on its target, pushes masses. | Reused: wander (Passive), hunt (Hostile), plus stun, knock-back and retreat. |
| `ZurdMouthComponent` | Eats a target after `eat_duration`; swats cancel a bite. | Reused, with a slower nibble for Passive Zurds. |
| `ZurdSpawner` | One Zurd per 10 objects. Not in any world. | Not used: a fixed number of Zurds (3) for now. |
| Swatting | Projectile calls `take_swat`; shrinks the Zurd. | Stun, stun, drive off. Ramming counts; launched objects only stun. |

## Iteration 0: groundwork (hardening plan step 2)

Split `base_world.tscn` (the director's home in `game_systems.tscn`, and an `Actors/Zurds`
container). No Zurd changes. (Step 3, the object budget, was dropped: the Zurds eating the mess
is what keeps loose objects in check.)

## Iteration 1: the core Zurd (Zurd Core Design Doc)

**Build:**

- **`ZurdDirector`** (in `game_systems.tscn`): counts loose objects, sculpture sizes and recent
  launches; works out the shared anger (mess over 15 loose objects, sculptures over 15 objects,
  launch bursts, decay); decides how many Zurds are Hostile, nearest to the mess first; places
  the starting Zurds. Every number is an export, for tuning at playtests.
- **Per Zurd:**
  - a Passive / Hostile state with a hostile cooldown;
  - sight (a cylinder) for choosing targets;
  - Passive wandering, and nibbling an object it drifts close to;
  - Hostile hunting of loose objects, then large sculptures;
  - swats: stun, stun, then retreat from the ship and return Passive. Ramming counts as a
    swat; a launched object only stuns, then the Zurd eats it.
- **EventBus:** `object_launched` (from the launcher), and the core doc's signals
  (`zurd_anger_changed`, `zurd_state_changed`, `zurd_stunned`, `zurd_driven_off`).
- **Placeholders for playtests:** a health bar over each Zurd, a tint for Hostile, and a testing
  HUD showing the anger and the number of Hostile Zurds.
- The temporary scripts, the old swat-shrink and eat-growth, and the unused spawner are removed
  or replaced.

**Tests** (`tests/scene/test_zurds.gd`, `tests/unit/test_zurd_anger.gd`), reading the exports:

- Anger stays 0 up to the tolerated mess and sculpture size, rises above them, rises on a launch
  burst, and decays.
- The number of Hostile Zurds follows the anger, nearest to the mess first; the cooldown holds.
- Passive Zurds don't hunt; they nibble only within the nibble distance, at the slower speed.
- Hostile Zurds go after loose objects before sculptures, and ignore sculptures under the limit.
- Swats: two stuns, then a retreat away from the ship; the count resets on return. Ramming
  counts; a launched object stuns and is then eaten.

**Playtest checklist:**

- Does the mess limit feel fair to a new player learning the controls?
- Do players notice that scattering objects is what turns the Zurds Hostile?
- Is 15 the right size for "large"?
- Does a launch burst feel like a fair trigger?
- Do stun, stun and drive-off feel good with mouse swats? Is the health bar readable?
- Is "stun it with an object, then swat it" a tactic players find?

## Later iterations (from the idea bank, when playtests ask for them)

Order to be decided from playtests:

- objectives and the difficulty ramp (Objectives Design Doc);
- more states (Curious, Suspicious) and an Alert Level display;
- the ship attack and killing;
- growth, spitting out new Zurds, population scaling, difficulty per player count;
- following clouds.

## Dependencies

- **Hardening step 2** first (iteration 0).
- **Art and sound** from the collaborator; placeholders until then.
- **Lidar step 4** for real swats; until then, mouse swats stand in.

## Open questions

- The *playtest* numbers in the core doc §8.
- How players learn what angers the Zurds (out of scope for iteration 1; the testing HUD stands
  in).
