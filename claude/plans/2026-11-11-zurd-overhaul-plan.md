# Plan: Zurd overhaul, built in playtested iterations

*Draft 2026-11-11, after the first design review. Not approved; no code yet. Each iteration below
gets its own short plan section approved before it's built.*

## Goal

Replace the temporary Zurd scripts with the behaviour in `claude/design/Zurd AI Design Spec.md`,
**one small slice at a time**. Each slice is built, tested, played, and the spec is updated from
what the playtest showed before the next slice starts. The spec is the target; playtests may
simplify it (Mitch, 2026-11-11: "build slowly … to get a better idea of what is fun").

## What exists today

| Part | Today | Spec |
| --- | --- | --- |
| `Zurd` (`zurd.gd`) | Coordinator: target → movement → mouth. Grows when it eats (no cap), shrinks when swatted (no minimum). | Stage state machine; growth from eating, capped; swats stun and drive off. |
| `ZurdTargetComponent` | Picks any tracked object (random or closest). | Perceives the ship, masses and loose objects in a circle (all heights), with interest weights. |
| `ZurdMovementComponent` | Hunt, wander, avoidance (layer 1), bobbing, holds the mouth on its target, pushes masses. | More modes (§13). Wander, hunt, hold and push are reused. |
| `ZurdMouthComponent` | Eats a target after `eat_duration` in the mouth; swats cancel a bite; hands bites to `MassManager` via `eat_requested`. | Kept, plus eat speed per stage and an eater cap. |
| `ZurdSpawner` | One Zurd per 10 tracked objects. Not in any world. | Population from pressure (fewer per object), spat out by angry Zurds. |
| Swatting | `SwatEmitter` fires a projectile that calls `take_swat`. Mouse only. | Stun and knock back; hurts; many hits kill. |
| Alert Level, sharing, HUD | None. | §3, §8. |

## Shape of the code (all iterations)

- **`ZurdDirector`** (one per world, in `game_systems.tscn`, from hardening step 2): pressure,
  population (start, spit-outs, waves, the cap), difficulty from active stations, the Alert
  Level, sharing. Every number is an export, for tuning at playtests.
- **Per Zurd**, components like today: `ZurdStageComponent` (stages, triggers, timers),
  `ZurdPerceptionComponent` (what's in the circle, what to attend to), the movement and mouth
  components (extended), `ZurdLook` (tint, size, speed, placeholder expressions and sounds),
  `ZurdHealth` (stun, hits, death).
- **EventBus**: the spec §14 signals, added as each iteration needs them, plus `object_launched`
  from the launcher (Zurds count launches in their zone).
- **A Zurd debug overlay** (iteration 1) for playtests: pressure, Zurd count, each Zurd's stage,
  target and health, so tuning sessions can see why the Zurds act as they do.

## Iterations

Each iteration: build → tests → playtest with its checklist → update the spec → next. Order and
contents can change after any playtest.

### 0. Groundwork (hardening plan steps 2 and 3)

Split `base_world.tscn` (gives the director a home and Zurds an `Actors/Zurds` container) and add
the object budget. No Zurd changes.

### 1. Hungry Zurds: the core pressure loop

*The question it answers: does eating create the right pressure, and does it push players to
build one sculpture?*

- Replace the temporary scripts with the new structure, at its smallest:
  - Zurds wander around a loose home.
  - They notice objects in their perception circle and graze on them: loose objects, and
    objects off a mass.
  - They grow as they eat, up to a cap.
- Swats, rams and launched objects **stun and knock a Zurd back** (no more shrinking), and count
  hits.
- **Population from pressure:** a few Zurds at the start near the ship, more as objects pile up,
  popping out of existing Zurds (placeholder pop). Slightly fewer with only the pilot playing.
- The debug overlay.
- No stages yet, beyond "wandering" and "eating".

Playtest checklist: how many Zurds feel right; eating speed; does scattering objects feel
riskier than building one sculpture; does stun and knock-back feel good with mouse swats; the
growth cap.

### 2. Getting angry: stages and the Alert Level

*The question it answers: does escalation read on the walls, and is it fun to provoke and calm
the Zurds?*

- The stage machine (5 stages, or 3 visible levels first: see review question 65).
- Triggers: launches in the zone, building, swats and hits. De-escalation timers and cooldowns.
- Tint, speed and size per stage.
- The Alert Level, with a placeholder HUD indicator.
- Killing at the top stage: many hits, a cartoony fall, nearby Zurds get angrier.

Playtest checklist: are the thresholds reachable without spamming; can players tell the stages
apart; does calming down happen when it should.

### 3. The ship attack

*The question it answers: is the attack a fun distraction rather than a punishment?*

- At the top stage, a Zurd clamps onto the ship. The ship vibrates and is shoved randomly, and
  can break sculptures it crashes into. Placeholder tongue and gnawing.
- Swats no longer drive the Zurd off; many hits kill it.
- Release rules (from the review answers).

Playtest checklist: duration, shove strength, how often it happens, does the crew rally to
swat.

### 4. The swarm

- Spat-out reinforcements and High Alarm waves (nesting dolls), the cap.
- Information sharing, if iteration 2's playtest shows the Zurds are too uncoordinated.
- Search after losing the ship.
- The cloud outcome: Zurds fly up after a cloud, then most despawn (with the Cloud-Formation
  design).

### Later

Points of interest, objectives, a real "dangerous unit", off-screen Zurd markers and the
ship-under-attack warning (HUD design).

## Tests

Each iteration adds behaviour tests in `tests/scene/test_zurds.gd` (and `tests/unit/` for pure
logic such as pressure and stage rules), reading expected values from the exports. Examples:

- **Iteration 1:** grazing, the growth cap, stun and knock-back on a swat, population following
  pressure, fewer Zurds with one station active.
- **Iteration 2:** each trigger escalates, each timer de-escalates, cooldowns hold, the Alert
  Level holds before dropping, death after the set number of hits.
- **Iteration 3:** clamping, the shove, release.
- **Iteration 4:** summon cooldown and cap, sharing radius and limits, despawning after a cloud.

`tests/README.md`'s "don't pin Zurd behaviour" ends with iteration 1: the new behaviour is
designed, so it's tested.

## Playtests

- A checklist per iteration (above). Results go in the spec (decisions and numbers), and the
  next iteration's plan section is written from them.
- Tuning happens in the Inspector during play, with the debug overlay. Numbers that feel right
  are saved in the scenes.
- Who plays, how often and where is review question 66.

## Dependencies

- **Hardening steps 2 and 3** first (iteration 0).
- **Cloud-Formation design** before iteration 4's cloud outcome.
- **Art and sound** from the collaborator; placeholders until then.
- **Lidar step 4** for real swats; until then, mouse swats stand in.

## Questions for the group

Answered at the review: no lose state; pressure ramps with objects; swats stun and drive off;
killing is rare; difficulty scales with players; Alert Level in the HUD; placeholders for art.

Still for the group (review questions 49, 50, 56, 58, 65, 66):

1. **Objectives:** should the players have objectives (for example, build a sculpture of
   animals)? If so, they get their own design doc.
2. **Pressure:** what exactly raises it, so that scattering objects is riskier than building
   one sculpture?
3. **The ship attack:** how long it lasts, how many Zurds at once, how hard the ship is shoved.
4. **Dying:** does the body stay on the ground or vanish, and does a dying Zurd spit out what it
   ate?
5. **Simplify:** start with three visible levels (calm, hungry, angry) and split them into the
   five stages only if playtests call for it?
6. **Playtests:** who plays, how often, and where (the projected room or a monitor)?
7. **The pilot's defence** (still being debated).
