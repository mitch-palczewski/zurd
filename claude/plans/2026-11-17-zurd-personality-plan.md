# Zurd personality plan (iteration 2.0)

Status: **approved 2026-11-17**, with the answers at the end. Mitch is away during the build, so
questions that come up go in "Notes for Mitch" at the end instead of blocking.

Design: Zurd Core Design Doc §12 (decided 2026-11-17). This is iteration **2.0**:
- individual anger;
- roles (Shadow, Grazer, Sentinel);
- temperament;
- landmarks and Sentinels finding sculptures;
- the nearby-anger testing HUD.

Growth and the cloud chase are **2.1**, planned after 2.0 has been playtested.

## Goal

Different Zurds with different behaviour, so the world feels inhabited and the game balanced.
3 Shadows keep the ship company, 15 Grazers spread over the map, and 5 Sentinels watch
landmarks and settled sculptures. Each Zurd gets angry from what it sees itself, and each has a
temperament of its own. This also fixes the playtest problems (Zurds on the ship's tail, and
chasing it as a pack), because only Shadows care where the ship is, each in its own spot.

## What changes

### 1. Individual anger (replaces the shared anger)

`ZurdAnger` becomes **one per Zurd**: still a plain class with no scene, unit-tested on its own.

**What adds anger.** Each source is multiplied by the Zurd's role weight (section 2) and its
temper (section 3):
- **Noticing mess:** the first time a Zurd sees a loose object, it adds anger if it now sees more
  than it tolerates (*proposed:* 3). It remembers what it has noticed, so a mess sitting in view
  counts once, but roaming into an old mess counts.
- **Seeing a launch:** the ship launches while the ship is within the Zurd's sight.
- **Its sculpture growing:** each part its watched sculpture gains beyond the sculpture limit
  (Sentinels).
- **Being attacked:** a swat, ram or thrown object. How it takes a swat depends on boldness
  (section 3).

**What takes it away:** it falls after a quiet spell (`calm_delay`), at `decay_rate` × patience.

**Hostile and calm:**
- It turns Hostile above `hostile_threshold` (*proposed:* 0.6) and calms below `calm_threshold`
  (*proposed:* 0.3).
- The hostile cooldown and finishing the meal before calming stay as they are.
- The Zurd decides this itself; the director no longer picks who's Hostile.

**Appetite** = lerp(greed, 1, anger), per Zurd.

**The director keeps:**
- claims (one Zurd per target);
- sculpture growth bookkeeping;
- settled sculptures and Sentinel assignment;
- spawning.

The shared `anger`, `get_hostile_count`, `_update_hostility`, the mess counting and the world-wide
tolerances go.

**Signal:** `zurd_anger_changed(anger)` becomes `zurd_anger_changed(zurd, anger)`, fired when a
Zurd's anger changes noticeably (for sound later).

### 2. Roles

A **`ZurdRole`** resource (`scenes/characters/enemy/zurd_role.gd`), with one `.tres` per role in
`data/zurd_roles/`: `shadow.tres`, `grazer.tres`, `sentinel.tres`. Each holds:
- its name and placeholder tint (a faint body tint, so roles can be told apart in playtests);
- its anger weights (noticing mess, launches seen, sculpture growth, attacks) and its tolerance;
- its home settings;
- its temperament ranges (section 3);
- how it hunts when Hostile.

The director has the counts (`shadow_count` 3, `grazer_count` 15, `sentinel_count` 5,
`sentinel_cap` 8). It spawns them **all at the start**:
- Shadows around the ship;
- Grazers at their patches;
- Sentinels at landmarks.

`spawn_zurd(at, role)` also serves the tests.

**What each role does:**

| Role | Calm, with nothing to eat | Hostile goes after |
|---|---|---|
| **Shadow** | Keeps its own spot around the ship: its own bearing relative to the ship's heading (the three spread evenly), *proposed* 150–300 m out (bolder is closer), at where the ship was a few seconds ago (*proposed:* 3 s). It drifts around that spot and never sits on the ship's tail. | Loose objects nearest the ship (within its sight), then sculptures over the limit |
| **Grazer** | Wanders its patch. The 15 patches are spread evenly over a disc around the world centre (a sunflower spiral, *proposed* radius 1500 m; patch radius follows from the spacing). | Loose objects in its patch, then sculptures in its patch, which count like loose objects (question 1), then strays nearby |
| **Sentinel** | Circles and watches its home: a landmark, or a settled sculpture. | Pieces of its sculpture; with a landmark home, loose objects near it |

- **Passive feeding stays for every role:** it eats strays it sees, by appetite.
- **Only Sentinels stop to watch sculptures** (question 3).

### 3. Temperament

`ZurdTemperament`, a plain class. Each Zurd rolls its traits within its role's ranges when it
spawns:

| Trait | Does | Range (*proposed*) |
|---|---|---|
| Temper | Multiplies the anger it gains | 0.6–1.4 |
| Patience | Multiplies how fast its anger falls | 0.6–1.4 |
| Greed | Its calm appetite | 0.3–0.7 |
| Boldness | 0–1. Shadow distance, and swats | Shadow 0.3–1, Grazer 0–1, Sentinel 0.5–1 |
| Curiosity | Multiplies how long it watches (Sentinels) | 0.6–1.6 |
| Pace | Multiplies its speeds | 0.9–1.1 |

**Swats by boldness** (§12.3):
- A **timid** Zurd (boldness below *proposed* 0.3) flees and calms after **one** swat: driven off
  at once, its anger set to 0.
- A bolder one needs more swats to drive off, about 2–4 by boldness, and each swat adds attack
  anger (× temper), so it gets angrier.

The placeholder health bar shows its own number of swats.

**Body size variety comes with growth in 2.1** (question 6). 2.0 varies pace and tint only.

### 4. Landmarks and Sentinels finding sculptures

- **Landmarks** are `Marker3D` nodes in the group `zurd_landmarks`, placed by hand, one Sentinel
  each.
- **Where:**
  - `zurd_world02`: the pool court, the mega tree grove, the bush garden and the circle grids
    (4 landmarks, in the area scenes and `terrain02.tscn`);
  - `zurd_world01`: 3 spots I'll pick (question 5).

  You can move them in the editor.
- A Sentinel with no free landmark hangs out near the nearest one.
- **Settled sculptures:** the director notes when each sculpture's part count last changed. One
  unchanged for `settle_time` (*proposed:* 30 s) is settled.
- **Assignment:** for each settled sculpture without a Sentinel, the nearest free Sentinel (one
  whose home is a landmark) takes it as its home and wanders over at its easy pace.
- **Scaling:** if none is free and Sentinels are under the cap (8), a new Sentinel spawns at the
  nearest landmark and wanders over. Unwatched settled sculptures wait for the next free one.
- **When its sculpture becomes a cloud, or is eaten away:**
  - a Sentinel within the starting count goes back to a free landmark (or near the nearest);
  - one beyond the starting count becomes a Grazer, taking the patch with the fewest Grazers.

### 5. The testing HUD (replaced)

- The five Zurds nearest the ship, one line each: role, state (Passive / Hostile / calming /
  driven off) and an anger bar.
- Their average as **nearby anger**.
- Counts per role and how many are Hostile.
- Settled sculptures with and without a Sentinel.

## Files

| File | Change |
|---|---|
| `scenes/characters/enemy/zurd_anger.gd` | per-Zurd anger: sources, weights, thresholds, decay |
| `scenes/characters/enemy/zurd_role.gd` | new: `ZurdRole` resource |
| `scenes/characters/enemy/zurd_temperament.gd` | new: traits rolled from a role |
| `data/zurd_roles/shadow.tres`, `grazer.tres`, `sentinel.tres` | new |
| `scenes/characters/enemy/zurd.gd` | own anger and hostility; role homes; swats by boldness; noticing mess |
| `scenes/characters/enemy/zurd_director.gd` | role counts and spawning, patches, landmarks, settled sculptures, Sentinel assignment; shared anger removed |
| `scenes/characters/enemy/zurd_sight_component.gd` | hostile targets by role (near the ship, in a patch, one sculpture) |
| `scenes/characters/enemy/zurd_movement_component.gd` | a Shadow's moving spot (small helper; wander and watch are reused) |
| `scenes/ui/hud/zurd_testing_hud.gd` (and `.tscn` if needed) | the nearby-anger readout |
| `scripts/autoload/event_bus.gd` | `zurd_anger_changed(zurd, anger)` |
| `scenes/world/game_systems.tscn` | director counts (and its old anger settings removed) |
| `scenes/world/areas/*.tscn`, `terrain02.tscn`, `zurd_world01.tscn` | landmark markers |
| `tests/unit/test_zurd_anger.gd` | rewritten for per-Zurd anger |
| `tests/unit/test_zurd_roles.gd` | new: temperament ranges, patch layout, swat rule |
| `tests/scene/test_zurds.gd` | shared-anger tests rewritten per Zurd; new role tests |
| Zurd Core Design Doc §12 (values as built), CLAUDE.md (Enemy bullet), `tests/README.md` | updated |

## Steps

1. **Individual anger:** the `ZurdAnger` rewrite, hostility per Zurd, appetite, the new HUD.
   Every Zurd is a Grazer-like default for now. Rewrite the anger tests.
2. **Roles and temperament:** the resources, spawning by role (all at the start), Grazer
   patches, Shadow spots, swats by boldness. Tests.
3. **Landmarks and Sentinels:** markers in both worlds, settled sculptures, assignment, scaling,
   returning. Tests.
4. **Docs, the full suite, and a playtest checklist.**

The game stays playable after each step, with the tests run each time.

## Tests (rules, not tuning)

**Unit tests:**
- anger: noticing past tolerance adds weight × temper, once per object; a launch seen adds;
  decay waits for `calm_delay` and scales with patience; the hostile and calm thresholds give
  hysteresis;
- temperament: traits roll within the role's ranges;
- patches: N centres, all inside the disc, none too close together;
- swats: the swats needed rise with boldness, and a timid Zurd needs one.

**Scene tests** (in `zurd_world01`):
- the world starts with 3 Shadows near the ship, 15 Grazers at their patches and 5 Sentinels at
  landmarks;
- a mess in one Zurd's view angers that Zurd, not one far away;
- a Shadow keeps its distance from the ship and isn't on its tail after the ship flies off;
- a Grazer stays in its patch;
- a settled sculpture gets one Sentinel, and one only, after `settle_time`;
- with every Sentinel busy, a new one spawns up to the cap;
- a Sentinel whose sculpture becomes a cloud goes home;
- a timid Zurd flees after one swat; a bold one takes more and its anger rises;
- the existing feeding, claim, personal-space and terrain tests, adapted.

## Risks

- **23 Zurds:** sight checks every 0.25 s each over every tracked object, plus terrain rays. That
  should be fine, but watch the frame time with many objects; the look interval can be spread out.
- **World scale:** sight (150 m) and speeds were tuned in `zurd_world01`. In `zurd_world02`'s
  1500 m disc, Grazers see only part of their patch, which is fine for grazing. Shadows (30 m/s
  hunting) fall behind a 55 m/s ship, which suits "a few seconds late", but they may lag a lot on
  long flights.
- **Balance:** with anger from what each Zurd sees, a lot may happen out of sight, or very little.
  The nearby-anger HUD is there to judge it. Spreading anger stays a later option.
- **Tests:** about half of `test_zurds.gd` is written against the shared anger and gets rewritten.

## Questions

1. **Grazers and sculptures:** you said Grazers treat sculptures like loose objects. Should
   Passive Grazers also nibble sculptures in their patch, or only Hostile ones? I'd say only
   Hostile ones, so that building one sculpture stays the safe play while the Zurds are calm.
2. **Shadow spots:** their bearings turn with the ship's heading (recommended: their spots stay
   around you as you turn, so at least one is usually on the walls), or stay fixed to the world
   (north, south-east, ...)?
3. **Watching:** only Sentinels stop to watch sculptures (recommended: it's their thing), or
   Grazers and Shadows too, now and then (by curiosity)?
4. **Grazing disc:** the same 1500 m radius in both worlds (simplest), or 1000 m in
   `zurd_world01` as the doc says now?
5. **World 1 landmarks:** fine if I pick 3 spots around its middle, for you to move later?
6. **Body size:** leave size variety for 2.1 (with growth, which needs the same size mechanism),
   or roll a little size variety now?
7. **The proposed numbers:** hostile 0.6, calm 0.3, tolerance 3 in view, settle time 30 s,
   Shadows 150–300 m out and 3 s behind, timid below boldness 0.3. OK as starting points?

## Answers (2026-11-17)

1. Only Hostile Grazers eat from sculptures in their patch.
2. Shadow spots turn with the ship's heading, and Shadows **try to stay within the players'
   view**: their spots sit in the front arc the camera sees, not all around the ship.
3. Only Sentinels watch sculptures.
4. 1500 m grazing disc in both worlds.
5. Claude picks 3 landmark spots in `zurd_world01`.
6. Body size variety waits for 2.1.
7. The proposed numbers are fine as starting points.

## As built (2026-11-17)

- **All three steps, built in one pass and tested together:**
  - per-Zurd `ZurdAnger`;
  - `ZurdRole` (`data/zurd_roles/`) and `ZurdTemperament`;
  - the director's cast, patches, Shadow bearings, landmarks and Sentinels;
  - the nearby-anger HUD;
  - `zurd_anger_changed(zurd, anger)`.
- **Landmarks:**
  - `zurd_world02`: pool court (60 m up), grove (120 m), bush garden, circle grids;
  - `zurd_world01`: North (0, −30, −250), SouthEast (250, −30, 150) and SouthWest (−250, −30, 150),
    about 45 m above its ground.
- **Tests:** 135 pass, twice in a row.
  - New: `tests/unit/test_zurd_roles.gd` (5 tests), and `tests/unit/test_zurd_anger.gd` rewritten
    (9).
  - `tests/scene/test_zurds.gd` rewritten (28): the cast, a Grazer's patch, a Shadow's spot in view
    (and catching up after the ship flies on), feeding and appetite, mess angering only the Zurd
    that sees it, launches holding the anger of Zurds that see them, thresholds and the cooldown,
    hunting by role, only Sentinels watching, a Sentinel's sculpture angering it, settled
    sculptures getting one Sentinel, extras up to the cap, leaving a cloud, timid and bold swats,
    and the old claim, ramming, object-hit, personal-space and terrain tests.
- **Played in `zurd_world02`** (windowed, with the full cast):
  - 60 fps (about 17 ms a frame) with all 23 Zurds, idle and while launching.
  - Scattering 14 objects around the ship in 8 s turned all three Shadows Hostile. 15 s later they
    were eating and calming (one calming, two at 0.4–0.6). A Sentinel that could see some of it
    rose to 0.35, and far-off Grazers barely noticed.

## Notes for Mitch

Decisions made while you were away. Change any you disagree with:

1. **Shadows stay in view:**
   - Their spots spread over 50° to each side of the heading, a quarter step off dead ahead, so the
     ship doesn't fly into them.
   - Far from their spot, they head back at 45 m/s (`travel_speed`), faster than they wander, so
     they keep up.
   - The plan's "3 s behind the ship" is dropped: their top speed already makes them trail on fast
     flights and catch up when you slow down.
2. **Shadows see 350 m** (Grazers 150, Sentinels 200). Their spots are 150–300 m out, so with the
   old 150 m sight they couldn't see the ship or its launches.
3. **Noticing counts only what's past the tolerance:** a Grazer that wanders into a pile of 10
   gets 7 items' worth of anger, not 10.
4. **Launch anger needs too much mess in view.** Every launch a Zurd sees holds its anger, but it
   adds only while that Zurd sees more than it tolerates. Building methodically stays safe, as in
   the original rules.
5. **Hostile Zurds act only on what they see** (a Grazer also on what's in its patch). The old
   "go after the nearest object anywhere in the world" fallback is gone, since anger is now
   individual. With nothing in sight they keep to their home until they calm.
6. **Driven off means calmed:** bold or timid, a driven-off Zurd comes back with its anger at 0.
7. **Thrown objects** anger the Zurd they hit (the doc lists them as attacks), besides stunning it.
8. **Role tints** (placeholders): Shadows faint blue, Grazers faint green, Sentinels faint gold;
   Hostile is still red.
9. **Heights in `zurd_world02`:**
   - Grazers hover at about the ship's starting height (332 m ± 30), so they're in the level view.
   - Sentinels sit at their landmarks, near the scenery (60–120 m up), well below where you start.
   - Raise the landmark markers if you want Sentinels higher.
10. **Balance to watch:** Shadows turn Hostile quickly when you scatter objects near the ship
    (each messy launch adds about 0.13). Their `launch_anger` and `mess_anger` in `shadow.tres` are
    the knobs.
