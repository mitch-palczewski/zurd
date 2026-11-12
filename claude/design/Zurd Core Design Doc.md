# Zurd Core Design Doc

Zurd game · Godot (GDScript) · The smallest Zurd behaviour that makes the game fun and shapes how
players play. Values marked *proposed* are starting points; the line between Passive and Hostile
is the main thing to playtest.

This doc is what gets built first. The fuller ideas (five stages, information sharing, the ship
attack, growth, nesting-doll spawning, following clouds) stay in the **Zurd AI Design Spec**, the
idea bank. Features move from there into this doc only when a playtest shows they're needed.

## 1. What the Zurds Are For

The Zurds exist to shape how players play. Each rule below serves one of these goals:

1. **Build sculptures, don't spam objects.** Objects scattered across the world are what the
   Zurds care about most. Objects gathered into sculptures are left alone, up to a point.
2. **Small sculptures are fine.** Zurds don't mind small sculptures. Only when a sculpture grows
   to large proportions does it start to anger them.
3. **Start easy, ramp up.** At the start of a game the Zurds don't get in the way. Pressure
   grows as the players progress.
4. **Objectives drive progress.** Players work through objectives that grow in difficulty, size
   and shape. The first one (a cloud of 5 objects) can be finished without any trouble from the
   Zurds.
5. **Build methodically, not in a rush.** Launching doesn't anger the Zurds by itself, but while
   players keep launching the Zurds don't calm down either, and launching fast soon scatters more
   objects than they tolerate.
6. **Some mess is fine.** New players arrive often in a gallery and need time to learn the
   controls, so a reasonable number of loose objects is tolerated. A player clearly launching
   objects everywhere gets noticed.

There is no lose state. The Zurds create pressure, not failure.

## 2. Core Concepts

| Term | Meaning |
| --- | --- |
| Loose object | A launched object that isn't part of a sculpture (mass). |
| Sculpture | A sculpture mass (Sculpture-Mass Design Doc). Its size is its object count. |
| Mess | Loose objects plus sculptures: each loose object counts one, and each sculpture counts one (clouds don't count). Decided 2026-11-12, so scattering many small sculptures is mess too. |
| Anger | One value for the whole world, from 0 to 1, that all Zurds share. It rises with mess, large sculptures and rapid launching, and falls over time. |
| Passive / Hostile | The two states a Zurd can be in. |
| Sight | The space a Zurd sees, where it finds things to eat. |
| Objective | A goal for the players, such as "make a cloud of 5 objects" (section 7). |

## 3. What the Zurds Know

All Zurds know the state of the whole world: the number of loose objects, the sculptures and
their sizes, and recent launches. That keeps aggression simple to scale: one shared **anger**
value, worked out once for the world (by a single "Zurd director").

**Anger rises when the players provoke the Zurds** (decided 2026-11-12):

- **Adding mess:** each object launched while the mess (loose objects plus sculptures) is over
  the **tolerated mess** (*proposed:* 15) adds anger.
- **Growing a large sculpture:** each object added to a sculpture beyond the **tolerated
  sculpture size** (*proposed:* 15 objects, a hard cut-off) adds anger. Smaller sculptures add
  nothing.
- **Attacking Zurds:** each swat, ram, or launched object that hits a Zurd adds anger.

**Launching under the limits holds the anger** (decided 2026-11-12): it neither raises nor lowers
it. Rapid launching on its own no longer angers the Zurds (the earlier rush rule was dropped).

**Anger falls** once the players stop: when nothing is launched, no objects are added past the
limits and the Zurds are left alone for a few seconds (*proposed:* 3 s), it falls steadily. A mess
that just sits there doesn't keep angering them; adding to it does.

**The ramp:** the tolerated amounts are generous at the start and tighten as objectives are
completed (section 7). During the first objective the Zurds stay Passive whatever happens.

## 4. Sight

- Each Zurd sees a **vertical cylinder** around itself: a circle on the ground plane, covering
  every height (*proposed* radius: 150 m). A cone in front of the Zurd is the alternative; it
  reads more clearly as "looking" but is harder to tune.
- Sight decides **what a Zurd goes after**, not whether it's angry (that's the shared anger).
- A Hostile Zurd prefers, in order: loose objects it can see, then the largest sculpture it can
  see (only if that sculpture is above the tolerated size).
- **One Zurd per target** (decided 2026-11-12): a Zurd claims what it goes after, and other Zurds
  leave it alone. Several Zurds can work on one sculpture, each on a different object of it. A
  claim ends when the object is eaten, or the Zurd is swatted, stunned or calms down.

## 4b. Getting Around

- **Personal space:** Zurds keep apart; one closer than *proposed* 8 m is pushed away, more
  strongly the closer it is. A pair stays near each other without overlapping.
- **The terrain:** between targets, Zurds keep at least *proposed* 8 m above the ground and look
  about a second ahead, climbing over hills rather than grinding along them. In the last few
  metres to a target they may come down, so food lying on a hill can still be eaten.

## 5. The Two States

### 5.1 Passive

- Wanders around a loose home area, alone or in pairs.
- Ignores the ship and the players' objects. It doesn't go looking for food.
- **Nibbles** only a loose object it happens to drift really close to (*proposed:* within 3 m),
  and slowly (*proposed:* a third of the Hostile eating speed). Moving the object away, or a swat,
  stops it. It leaves sculptures alone, so small sculptures really are safe.

### 5.2 Hostile

- Goes after what angers the Zurds: **loose objects first**, then large sculptures.
- **Eats objects** (eating mechanics: Sculpture-Mass Design Doc §4.5).
- Looks and sounds different from a Passive Zurd (placeholder tint and sound).

**Bumping:** a Zurd that flies into objects or sculptures it isn't eating knocks them around.

### 5.3 Switching

- **How many Zurds are Hostile follows the anger:** at anger 0 none are, at anger 1 all are
  (*proposed*). As anger rises, the Zurds nearest to the mess turn Hostile first.
- **Calming down:** when anger drops, Hostile Zurds return to Passive, but only after staying
  Hostile for at least the **hostile cooldown** (*proposed:* 10 s), so they don't flicker.
- A Zurd that's been **driven off** (section 6) is Passive while it's away.

## 6. Swatting

Swatting (from the lidar walls; the mouse until the lidar is hooked up) is the players' defence.
**Running into a Zurd with the ship counts as a swat.**

**A launched object hitting a Zurd only stuns it,** and doesn't add to its swat count. When the
stun ends, the Zurd eats that object. This gives the players a tactic: hit a Zurd with an object
to hold it in place while someone gets close enough to swat it.

- **The first swats stun** the Zurd: it stops, is knocked back a little, and any bite it was
  taking is cancelled (*proposed:* swats 1 and 2, a 1.5 s stun each).
- **After a few swats it's driven off** (*proposed:* the 3rd swat): it retreats **away from the
  ship** (there are no set places in the terrain yet), stays away for a while (*proposed:* 20 s),
  then comes back Passive. Its swat count resets.
- **One swat counts once.** Hits within a short cooldown of the last one (*proposed:* 0.4 s)
  don't count, so a swat's spread of projectiles, or a ram that stays in contact for a moment,
  counts as one swat.
- **No killing** at this stage. (Killing, and Zurds that won't be driven off, are in the idea
  bank.)

**A health bar (placeholder):** a small bar over each Zurd shows how close it is to being driven
off, so the third swat doesn't seem random. It's a placeholder for playtests; the final look
(a bar, or a change on the Zurd itself, such as getting dizzier) is decided after playtesting.

## 7. Objectives (requirements on the Zurds)

Objectives have their own design doc (Objectives Design Doc, to be worked out later). Until then,
the Zurds build without them: no grace period and fixed tolerances. What the Zurds need from
objectives:

- **Objectives are a ladder.** The first is very simple: *make a cloud of 5 objects.* Later ones
  grow in size and difficulty, and add shape (for example, a tall sculpture, or one made of
  animals).
- **The first objective has no Zurd trouble.** Zurds stay Passive until it's done.
- **Each completed objective raises the difficulty:** the tolerated mess and sculpture size
  shrink, and anger rises faster.

## 8. Parameters

All *proposed*, tuned in playtests.

| Parameter | Meaning | Proposed |
| --- | --- | --- |
| Starting Zurds | Zurds in the world at the start | 3 |
| Sight radius | Radius of the sight cylinder | 150 m |
| Tolerated mess | Loose objects allowed before anger rises | 15 |
| Mess anger | Anger added per object launched while over the mess limit | 0.05 |
| Tolerated sculpture size | Objects in a sculpture before it angers the Zurds (hard cut-off) | 15 |
| Sculpture anger | Anger added per object added beyond the sculpture size limit | 0.03 |
| Attack anger | Anger added per swat, ram or object hit on a Zurd | 0.1 |
| Calm delay | Time without a launch or a provocation before anger starts to fall | 3 s |
| Anger decay | How fast anger falls once it does | 0.05 per second |
| Hostile cooldown | Least time a Zurd stays Hostile | 10 s |
| Nibble distance | How close a Passive Zurd must drift to an object to nibble it | 3 m |
| Nibble speed | Passive eating speed, compared with Hostile | ×0.33 |
| Stun swats | Swats that stun | 2 |
| Stun time | Length of a stun | 1.5 s |
| Drive-off swat | The swat that drives a Zurd off (ramming counts; launched objects only stun) | 3rd |
| Hit cooldown | Least time between two hits that count | 0.4 s |
| Away time | How long a driven-off Zurd stays away | 20 s |
| Retreat distance | How far from the ship a driven-off Zurd goes | *proposed:* 300 m |
| Personal space | Distance Zurds keep from each other | 8 m |
| Ground clearance | Least height above the ground between targets | 8 m |
| Look-ahead | How far ahead a Zurd looks for obstacles, in time at its speed | 1 s |
| Difficulty step | How much the tolerances tighten per completed objective | *playtest* |

## 9. Signals (EventBus)

| Signal | Fired when |
| --- | --- |
| zurd\_anger\_changed(anger) | The shared anger changes noticeably (for a HUD and sound later) |
| zurd\_state\_changed(zurd, hostile) | A Zurd turns Hostile or Passive |
| zurd\_stunned(zurd) | A swat stuns a Zurd |
| zurd\_driven\_off(zurd) | A Zurd is driven off |

**Testing HUD (placeholder):** an anger indicator on the screen (the shared anger, and the number
of Hostile Zurds), for playtests only. How players learn what angers the Zurds is a later design
question.

## 10. Later (from the idea bank, when playtests ask for it)

- More states between Passive and Hostile (Curious, Suspicious), and a top state where Zurds
  attack the ship (jaws clamped, the ship shaken and shoved).
- An Alert Level display in the HUD.
- Killing Zurds (many swats, a cartoony fall).
- Zurds growing as they eat; angry Zurds spitting out new ones like nesting dolls.
- Population growing with pressure; difficulty scaling with how many are playing.
- Following a new cloud up into the sky.

## 11. Open Questions

Answered 2026-11-12: tolerated sculpture size 15 (hard cut-off); cloud sizes per objective
(later, with objectives); Passive Zurds nibble only what they drift close to; nearest to the mess
turn Hostile first; driven-off Zurds retreat from the ship; a placeholder health bar; ramming is a
swat, a launched object only stuns (then gets eaten); a testing HUD for anger.

Still open:

1. **Anger feedback for players:** how players learn that mess angers the Zurds (out of scope for
   the first build; the testing HUD stands in).
2. **The numbers** in section 8 marked *playtest*.
