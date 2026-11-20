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

> **Replaced by iteration 2 (section 12, decided 2026-11-17):** each Zurd gets its own anger from
> what it perceives. This section describes the shared anger that is built now.

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

- With nothing to eat or watch, it roams, staying loosely near the ship (*proposed:* within
  200 m). Ignores the ship otherwise. (Homes were dropped 2026-11-12.) **Iteration 2 (section
  12.2) gives each Zurd a home again, from its role.**
- **Feeds on loose objects it sees, by choice** (changed 2026-11-12): for each object it sees it
  decides whether to eat it, about half the time when the Zurds are calm and always at full anger,
  and decides again after a while (*proposed:* 20 s). It goes to the ones it wants at an easy pace
  (*proposed:* its wander speed, 10 m/s) and eats them slowly (*proposed:* 4 s a bite, against 3 s
  for a Hostile Zurd). So strays thin out even while the Zurds are calm, but don't vanish.
- **Watches sculptures it sees,** from nearby (*proposed:* 25 m): it stops to look, then moves to
  another spot around it. It never eats a sculpture while Passive, so building one sculpture is
  always the safe play.

### 5.2 Hostile

- Goes after what angers the Zurds: **loose objects first**, then large sculptures.
- **Eats objects** (eating mechanics: Sculpture-Mass Design Doc §4.5).
- Looks and sounds different from a Passive Zurd (placeholder tint and sound).

**Bumping:** a Zurd that flies into objects or sculptures it isn't eating knocks them around.

### 5.3 Switching

> **Replaced by iteration 2 (section 12.1):** each Zurd turns Hostile from its own anger.

- **How many Zurds are Hostile follows the anger:** at anger 0 none are, at anger 1 all are
  (*proposed*). As anger rises, the Zurds nearest to the mess turn Hostile first.
- **Calming down:** when anger drops, Hostile Zurds return to Passive, but only after staying
  Hostile for at least the **hostile cooldown** (*proposed:* 10 s), so they don't flicker. A Zurd
  that has a target when it's told to calm finishes eating that target first, then turns Passive
  (decided 2026-11-12).
- A Zurd that's been **driven off** (section 6) is Passive while it's away.

## 6. Swatting

Swatting (from the lidar walls; the mouse until the lidar is hooked up) is the players' defence.
**Running into a Zurd with the ship counts as a swat.**

**A launched object hitting a Zurd feeds it** (2.1, from the 2.0 playtest, 12.7): no stun, and it
doesn't add to the swat count. The Zurd snatches it out of the air and eats it very quickly, and
being fed calms it a little. Feeding a Zurd buys time, but it grows (12.4). (Until 2.1 a thrown
object stunned the Zurd, which ate it afterwards.)

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

**A health bar (placeholder):** a small, half-transparent bar over each Zurd shows how close it is
to being driven off, so the third swat doesn't seem random. It's a placeholder for playtests; the final look
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

All *proposed*, tuned in playtests. Iteration 2 changed several of these: its values are in 12.6
and 12.8.

| Parameter | Meaning | Proposed |
| --- | --- | --- |
| Starting Zurds | Zurds in the world at the start | 3 |
| Sight radius | Radius of the sight cylinder | 150 m |
| Tolerated mess | Loose objects allowed before anger rises | 15 |
| Mess anger | Anger added per object launched while over the mess limit | 0.05 |
| Tolerated sculpture size | Objects in a sculpture before it angers the Zurds (hard cut-off) | 15 |
| Sculpture anger | Anger added per object added beyond the sculpture size limit | 0.03 |
| Attack anger | Anger added per swat or ram | 0.1 |
| Calm delay | Time without a launch or a provocation before anger starts to fall | 3 s |
| Anger decay | How fast anger falls once it does | 0.05 per second |
| Hostile cooldown | Least time a Zurd stays Hostile | 10 s |
| Hostile bite | Time a Hostile Zurd takes to eat a bite | 3 s |
| Passive bite | Time a Passive Zurd takes to eat a bite | 4 s |
| Feeding speed | Speed a Passive Zurd goes to food at | 10 m/s |
| Watch distance | How far from a sculpture a Passive Zurd watches it from | 25 m |
| Watch pause | How long it stops to look before moving around it | 3 s |
| Calm appetite | Chance a Passive Zurd decides to eat an object it sees, at anger 0 (rising to 1 at full anger) | 0.5 |
| Appetite recheck | How long a Zurd keeps its decision about an object | 20 s |
| Roam radius | How far from the ship an idle Passive Zurd roams | 200 m |
| Hit area | Radius in which a thrown object is caught (fed to the Zurd; 2.1) | 7 m |
| Stun swats | Swats that stun | 2 |
| Stun time | Length of a stun | 1.5 s |
| Drive-off swat | The swat that drives a Zurd off (ramming counts; launched objects feed instead) | 3rd |
| Hit cooldown | Least time between two hits that count | 0.4 s |
| Away time | How long a driven-off Zurd stays away | 20 s |
| Retreat distance | How far from the ship a driven-off Zurd goes | *proposed:* 300 m |
| Personal space | Distance Zurds keep from each other (2.1: a bubble of 1.5× the body radius, and 40 m around the ship) | 8 m |
| Ground clearance | Least height above the ground between targets | 8 m |
| Look-ahead | How far ahead a Zurd looks for obstacles, in time at its speed | 1 s |
| Difficulty step | How much the tolerances tighten per completed objective | *playtest* |

## 9. Signals (EventBus)

| Signal | Fired when |
| --- | --- |
| zurd\_anger\_changed(zurd, anger) | A Zurd's own anger changes noticeably (for sound later). Was the shared anger until iteration 2. |
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
- Angry Zurds spitting out new ones like nesting dolls. (Growing as they eat moved to 12.4.)
- Population growing with pressure; difficulty scaling with how many are playing.
- Following a new cloud up into the sky (now 12.5).

## 10b. Review of the Implementation (2026-11-12)

Decisions from reviewing iterations 1 to 1.2:

- **Passive feeding stays:** it's what Zurds naturally do. Players can still spam past the mess
  limit. To keep it from clearing every stray, each Zurd **chooses** whether to eat an object it
  sees: about half the time it leaves it (*proposed*), and reconsiders after a while; the chance
  rises as the Zurds get angrier. Hostile Zurds eat whatever they go after.
- **Roaming:** with nothing to eat or watch, a Passive Zurd wanders, staying loosely near the ship
  so the Zurds stay part of the scene.
- **Homes are dropped** for now: with feeding and watching, Passive Zurds rarely used them.
- **The Zurd's size** is set per part (mesh, colliders, mouth, hit area), not by scaling its
  body, as Godot advises. The larger hit area is wanted.
- **Later:** spawning more Zurds as objects pile up, or as a sculpture progresses.

## 11. Open Questions

Answered 2026-11-12: tolerated sculpture size 15 (hard cut-off); cloud sizes per objective
(later, with objectives); Passive Zurds nibble only what they drift close to; nearest to the mess
turn Hostile first; driven-off Zurds retreat from the ship; a placeholder health bar; ramming is a
swat, a launched object only stuns (then gets eaten); a testing HUD for anger.

Answered 2026-11-20 (the 2.0 playtest): a thrown object feeds the Zurd and calms it a little
(question 4 below, 12.7).

Still open:

1. **Anger feedback for players:** how players learn that mess angers the Zurds (out of scope for
   the first build; the testing HUD stands in).
2. **The numbers** in section 8 marked *playtest*.
3. **Attacks and anger** (from the 2026-11-12 review; Mitch is still deciding): every swat adds
   anger, so defending makes more Zurds Hostile, which raises the question of why to swat at all.
   Options: only attacks on Passive Zurds anger them; a lower attack anger; driving a Zurd off
   calms the others a little.
4. ~~**Throwing objects at Zurds**~~ (answered 2026-11-20): a throw feeds the Zurd, quickly, and
   calms it a little; it no longer stuns it or counts as an attack.
5. **The sculpture limit and the cloud size** (to settle with objectives): every sculpture passes
   the anger limit (10) on its way to a cloud (20), so finishing a cloud always angers the Zurds.
6. **Spawning:** more Zurds as objects pile up, or as a sculpture grows.

## 12. Iteration 2: Personality (decided 2026-11-17)

Different Zurds with different behaviour, so the game feels balanced and the world feels
inhabited: a few keep the ship company, most are spread across the map, and some watch the
places and sculptures that matter. Built in two steps:
- **2.0:** individual anger, roles, temperament, the nearby-anger testing HUD, role switching;
- **2.1:** feeding, Grazer packs, growth and the cloud chase, with the changes from the 2.0
  playtest (12.7).

The Passive/Hostile states (section 5), sight (4), getting around (4b) and swatting (6) stay
unless changed here.

**Arrival:** all the Zurds are there from the start, which makes testing easier (decided
2026-11-17). Trickling them in, for a calm opening, may come later.

### 12.1 Individual anger

- **Each Zurd has its own anger**, 0 to 1. There is no shared anger.
- **What raises it** is what that Zurd itself perceives:
  - loose objects it sees beyond what it tolerates (*proposed:* 3 in view; this replaces the
    world-wide mess limit);
  - launches it sees;
  - the sculpture it watches growing past the sculpture limit;
  - attacks on it (swats and rams; a thrown object feeds it instead, 12.7).
- **What lowers it:** it falls after a quiet spell, and being fed a thrown object calms it a little
  (2.1).
- **Each role weighs these differently** (12.2), and temperament scales them (12.3).
- **Hostile** when its anger passes the *hostile threshold*; **calm again** below the lower *calm
  threshold*. The gap stops it flickering. The hostile cooldown and "finish the meal before
  calming" (5.3) stay.
- **Appetite rises with its anger:** a calm Zurd eats only some of the strays it sees
  (*proposed:* half), an angry one nearly all.
- **Hunting order stays:** loose objects first, then a sculpture over the limit.
- **Later, only if playtests ask:**
  - anger spreading between nearby Zurds, if too few Zurds take part (it adds feedback loops that
    are hard to tune and to read);
  - a shared background mood for the difficulty ramp.
- **Testing HUD:** the role, state and anger of the few Zurds nearest the ship, and their
  average as "nearby anger". It replaces the shared-anger HUD (decided 2026-11-17).

### 12.2 Roles

| Role | Count | Home | Angered mostly by | When Hostile |
|---|---|---|---|---|
| **Shadow** | 3 | Its own spot around the ship (its own bearing, *proposed* 150–300 m out), following the ship's path a few seconds late; never on its tail | Launches near it; the ship bumping it | Goes after the loose objects nearest the ship |
| **Grazer** | 15 | Its pack (2.1: 3 packs of 5): the pack's middle roams a disc around the world centre (1500 m) and heads for loose objects, like a vacuum; the Grazers wander around it. (2.0: its own patch of the map, spread evenly over the disc.) | Loose objects it sees; **sculptures count like loose objects** | Clears the ground around its pack (sculptures included), then strays nearby |
| **Sentinel** | 5 (scales, see below) | One landmark or one sculpture, which it circles and watches. **One Sentinel per sculpture or landmark.** | Its sculpture growing past the limit | Eats from its sculpture |
| **Brute** (later) | 0 | None: appears where Zurds are angry | Everything | Tougher, hard to drive off; the future ship attacker |

- Each role is a settings file: home, anger weights, hunting, toughness, and its temperament
  ranges.
- **Sentinels are about sculptures** (decided 2026-11-17); Grazers treat a sculpture like any
  other object in their patch.
- **Landmarks** are marker nodes placed by hand in each world. A Sentinel with no free landmark
  or sculpture hangs out near the nearest landmark.
- **Finding sculptures** (a slow beeline, decided 2026-11-17):
  - A sculpture becomes **settled** once nothing has been added to it or taken off it for a while
    (*proposed:* 30 s). That filters out sculptures that break apart and come back together
    while players build.
  - The nearest free Sentinel then **wanders over** at its easy pace and takes it on: a slow
    beeline, so it seems to find it eventually.
  - Not every sculpture gets a Sentinel.
- **Sentinel numbers scale:**
  - When every Sentinel is busy and a settled sculpture has no watcher, a new Sentinel trickles
    in, up to a cap (*proposed:* 8).
  - When a sculpture becomes a cloud (or is eaten away), its Sentinel returns to a landmark.
  - A Sentinel beyond the starting count becomes a Grazer instead.
  - (This replaces the earlier idea of Grazers switching to Sentinels.)

### 12.3 Temperament

Each Zurd rolls a few traits within its role's ranges:

- **Temper:** how fast it gets angry.
- **Patience:** how fast it calms down.
- **Greed:** its baseline appetite.
- **Boldness:** how close it comes to the ship, and how it takes a swat:
  - **A timid Zurd flees and calms after a single swat.**
  - **A bolder one takes more swats to drive off,** and gets angrier with each.
- **Curiosity:** how long it lingers to watch.
- **Body:** a little variety in size, speed and tint (2.1 builds the size: 0.9–1.1×).

### 12.4 Growth (2.1)

Zurds grow as they eat and **stay big forever**, up to a cap (*proposed:* 4–5× their starting size).
A bigger Zurd is **a little slower** and **takes more swats** to drive off.

### 12.5 The cloud chase (2.1)

- **Who joins:** every Zurd that can see the new cloud (decided 2026-11-17).
- **Hostile Zurds drop their hostility:** they stop what they're doing, their anger falls, and
  they join the chase.

- When a cloud forms, Zurds that see it race up after it, snap at it and bounce off comically.
- After a few seconds they give up and scatter back to their homes, which spreads them out again.
- This answers the Cloud-Formation Design Doc's question of how the Zurds react to a new cloud.

### 12.6 As built (2.0, 2026-11-17)

Iteration 2.0 is built (`claude/plans/2026-11-17-zurd-personality-plan.md`). Starting values, all
tunable:

| What | Where | Value |
|---|---|---|
| Hostile / calm thresholds | `Zurd` | 0.6 / 0.3 |
| Calm delay, decay | `Zurd` | 3 s, 0.05 per second × patience |
| Tolerated in view | each role | 3 |
| Shadow | `data/zurd_roles/shadow.tres` | sight 350 m (so it sees the ship from its spot); mess 0.05, launch 0.08, attack 0.25; spot 150–300 m out (bolder nearer), within 50° of the heading; heads back at 45 m/s; faint blue |
| Grazer | `grazer.tres` | sight 150 m; sculptures count as mess; mess 0.12, attack 0.2; faint green |
| Sentinel | `sentinel.tres` | sight 200 m; mess 0.03, sculpture 0.1, attack 0.2; boldness 0.5–1; faint gold |
| Temperament | each role | temper and patience 0.6–1.4, greed 0.3–0.7, boldness 0–1, curiosity 0.6–1.6, pace 0.9–1.1 |
| Swats | `Zurd` | timid below 0.3: 1 swat; bolder: 2–4 |
| Cast | `ZurdDirector` | 3 Shadows, 15 Grazers, 5 Sentinels, cap 8 |
| Grazing disc | `ZurdDirector` | 1500 m around the world origin, patch radius 1500 ÷ √15 ≈ 387 m, at the ship's starting height ± 30 m (2.1 replaced the patches with packs, 12.8) |
| Settle time | `ZurdDirector` | 30 s |
| Landmarks | the worlds | `zurd_world01`: 3 around the middle, 45 m above the ground. `zurd_world02`: the pool court, the grove, the bush garden and the circle grids. |

**How it plays out:**
- **Noticing mess:** only the items beyond a Zurd's tolerance count.
- **Launches:** every launch a Zurd sees holds its anger, but it adds anger only while that Zurd
  sees more mess than it tolerates. Building methodically stays safe.
- **Hostile Zurds act only on what they see** (and, for a Grazer, on what's in its patch). With
  nothing there, they keep to their home until they calm.
- **Being driven off** calms a Zurd: it comes back with its anger at 0.
- **Shadows** have no literal lag: their top speed makes them fall behind on fast flights, and
  they catch up when the ship slows.

### 12.7 Playtest of 2.0 (2026-11-20)

**Kept:**
- **The hostility ramp** is good for now.
- **Swatting:** its point is to preserve a sculpture long enough for it to become a cloud, and
  stunning helps with that. It stays as it is.
- **The sculpture limit (10) below the cloud size (20)** is right: starting a sculpture is easy,
  finishing one is hard.
- **Grazers in the distance:** seeing Zurds far off works.

**To change in 2.1:**
- **A launched object hitting a Zurd feeds it, not stuns it.** The Zurd turns and eats it very
  quickly, the way a hungry Zurd would. It makes a game of precise launching. (Replaces "a launched
  object only stuns it" in §6.)
- **Shadows get lost behind the ship.** When a Shadow is out of view, it moves quickly back to
  where it can be seen.
- **Zurds come too close to the ship,** sometimes into the camera. In general they give the
  players room to manoeuvre.
- **Grazers are a little passive, and their spread is too perfect.** They become packs that roam
  the map and clean up objects, like a vacuum.
- **Growth is a priority** (12.4). **The cloud chase** comes too (12.5).
- **The testing HUD** makes it hard to see which Zurds are getting angrier. In the end this becomes
  a single five-star rating; for now, the HUD should show it per Zurd.

**Later stays later:** Brutes and the ship attack, spreading anger, a background mood, more states,
trickling in, and population growing with the mess.

### 12.8 As built (2.1, 2026-11-20)

Iteration 2.1 is built (`claude/plans/2026-11-20-zurd-growth-and-packs-plan.md`). Starting values,
all tunable:

| What | Where | Value |
|---|---|---|
| Feeding | `Zurd` | a launched object at 8 m/s or more entering the hit area (7 m × size) is caught: it stops in the air, and the Zurd eats it at 4× a Hostile bite (0.75 s); each part eaten takes 0.1 off its anger |
| Ship space | `ZurdMovementComponent` | 40 m around the ship; the push out is 25 m/s at the ship, easing to nothing at the edge; off while a Zurd goes for food inside it, and while it eats |
| Zurd bubble | `ZurdMovementComponent` | 1.5× the body radius, so it grows with the Zurd; a push of up to 20 m/s, at full strength once two bubbles overlap by a third; none while eating |
| Shadow swoop | `Zurd` | out of the camera's view for 1.5 s, a Shadow swoops to its spot at 90 m/s, until it's back in view or at its spot |
| Packs | `ZurdDirector` | 3 packs of 5, spread over the 1500 m disc at the start; Grazers wander within 60 m of the pack's middle; Hostile ones hunt within 250 m of it; a pack smells loose objects 600 m out and moves at 8 m/s; packs keep about 400 m apart |
| Growth | `Zurd` | +0.1 per part eaten, up to 4.5×; speeds × size^−0.3; +1 swat per +1.0 grown (not for timid Zurds); each starts at 0.9–1.1× (the role's `body`) |
| Cloud chase | `Zurd` | 15 s at 50 m/s (6 s at first; longer after a request on 2026-11-20); anger falls to the calm threshold (0.3); a bounce lasts 0.8 s at 25 m/s, spinning 12 rad/s |
| Anger bars | `Zurd`, while the testing HUD is on | 8 cells over each Zurd: green, yellow, then red at the hostile threshold (red while Hostile); arrows while it's rising or falling; the same size on screen at any distance, hidden past 800 m |

**How it plays out:**
- **Shadows move with the ship.** A Shadow's spot moves with the ship, so it carries the ship's
  velocity and wanders or swoops on top of that. Without it, Shadows fell behind at full speed
  (the ship's 55 m/s beats their 45) and kept dropping out of view. In a 40 s test flight with
  turns, a Shadow was out of view for 2.5 s at most, just after a turn.
- **Thrown food comes first:** a caught object becomes the Zurd's target, even over the sculpture
  it was eating. A Zurd chasing a cloud ignores thrown food.
- **Packs** rise or sink to the food they smell (with free flight, objects float at any height),
  then roam at their own height again. A pack leaves food that's nearer another pack to that pack.
- **What grows:** the mesh, body collider, mouth, hit area, the health and anger bars' height, and
  the distances the Zurd keeps (ground clearance, obstacle look-ahead, watch distance). Each Zurd
  has its own copies of the shapes. The body node stays unscaled.
- **The cloud chase** sizes the cloud once, when it forms, and scales that as the cloud grows. A
  Zurd chasing a cloud can't turn Hostile until it gives up.
