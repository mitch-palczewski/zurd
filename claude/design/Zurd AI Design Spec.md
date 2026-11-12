# Zurd AI Design Spec

Zurd game · Godot (GDScript) · Five-stage behavioral model, adapted from the Zurd AI Five-Stage Behavioral Model v2. Values marked *proposed* are starting points for tuning; items marked *playtest* are decided by playing.

**Idea bank (2026-11-12):** the Zurds are now built from the **Zurd Core Design Doc**, which starts with two states and adds to them as playtests call for it. This spec keeps the fuller ideas; features move from here into the core doc when they're needed.

**Review status (2026-11-11):** first design review done (decisions below). The Zurds will be built **iteratively**: a small part at a time, playtested, then the next part (build plan: `claude/plans/2026-11-11-zurd-overhaul-plan.md`). This spec is the target; playtests may simplify it.

## 0. Decisions From the 2026-11-11 Review

- **No lose state.** Zurds can attack the ship, but it's a dramatic distraction, not a game over (5.5).
- **Pressure ramps with the number of objects in the world.** Zurds should push the players toward building **one sculpture** rather than scattering objects. They appear around the ship without being intensely aggressive at first, so players get time to build. Aggression is dialled in by playtesting.
- **Swats stun and drive Zurds off.** Killing takes many swats, and really only happens at the most aggressive stage, when Zurds attack the ship and won't be driven off. A dying Zurd is a cartoony event: it falls to the ground. Dead Zurds don't come back.
- **Difficulty scales with the players:** slightly easier for a single player.
- **The ship and launched objects hurt Zurds** when they hit them. How the pilot defends the ship is still being debated.
- **An Alert Level display** goes in the HUD / ship display.
- **Distances and speeds are rescaled** to the current ship (55 m/s top speed; launched objects stop about 120 m out). Zurds get faster to match.
- **No world reset between groups** (the world keeps running).
- **Points of interest are a later feature;** sensitive areas are dropped.
- **Art and sound** are being made by a collaborator; the build uses placeholders.

## 1. Overview

Zurds are the enemies of the game. Each Zurd runs its own state machine with five stages: **Passive, Curious, Suspicious, Hostile, High Alarm**. A Zurd changes stage only when a trigger fires. Zurds share information with nearby Zurds. The players see a GTA-style **Alert Level** that reports the highest stage among all Zurds. There is one ship.

Zurds are singular creatures: they wander alone or in pairs. They eat the players' objects, which shrinks sculptures, and at their angriest they clamp onto the ship. There is no lose state: the Zurds create pressure and spectacle, not failure.

The model is inspired by the way enemies in No Man's Sky escalate, but it is a simplified framework, not a copy of that game's AI.

## 2. Core Concepts

| Term | Meaning |
| --- | --- |
| Stage | The Zurd's current behavior state (1 to 5). Each Zurd has its own. |
| Alert Level | The highest stage among all Zurds, shown in the HUD. |
| Perception zone | The area where a Zurd notices things: a circle on the ground plane (x, z) covering every height. The same at every stage. |
| Pressure | How much the world provokes the Zurds. Rises with the number of objects in the world (see open questions for exactly what counts). Sets how many Zurds there are. |
| Sculpture progress | Cloud progress (object count divided by the cloud threshold) of a mass the Zurd can see. See the Sculpture-Mass Design Doc. |
| Home | A point each Zurd wanders around, with a loose radius. A Zurd is easily drawn out of it. |
| Point of interest | *Later feature.* Something that holds a Passive Zurd's attention, such as a flower. |

## 3. Alert Level (wanted level)

- The Alert Level equals the highest stage among all active Zurds. 0 means every Zurd is Passive, then 1 = Curious, 2 = Suspicious, 3 = Hostile, 4 = High Alarm.
- It is recalculated whenever any Zurd changes stage, and also when a Zurd despawns or dies.
- A short hold (about 2 seconds) before the displayed level drops, so the indicator does not flicker when the top Zurd despawns.
- It is shown in the HUD / ship display (placeholder until the HUD is designed), driven by the `alert_level_changed` signal.

## 4. Perception

- Perception is the same at every stage.
- The zone is a **circle on the ground plane covering the entire vertical (Y) range**. No line-of-sight check: the play area is open space.
- A Zurd perceives the following **separately**:
  - the ship
  - sculpture masses
  - loose launched objects
  - points of interest (*later feature*)
- **Choosing what to attend to:** the highest interest weight wins; nearer things win ties.

| Perceived thing | Weight |
| --- | --- |
| Mass | 1.0 |
| Loose object | 1.0 |
| Ship | 0.8, rising to 1.0 (equal to objects and masses) at High Alarm |
| Point of interest (Passive only, later) | 0.5 |

## 5. The Five Stages

### 5.1 Stage 1: Passive

Unaware and autonomous.

- Wanders around its home by picking a random point and flying to it. The home radius is loose.
- Changes direction without any player influence.
- Neutral toward everything. Does not seek out the ship.
- *Later:* pauses to investigate points of interest.

**Escalates to Curious** when the ship enters the perception zone, or a launched object enters the perception zone.

**Cooldown:** none. This is the baseline state.

### 5.2 Stage 2: Curious

Awareness and interest, with no hostility.

- Turns toward the players' objects and mass and briefly interrupts its patrol. **If no objects have been launched, it doesn't turn toward the ship.**
- Approaches slowly and deliberately, then keeps a comfortable observation distance.
- Scans the ship, mass or surroundings intermittently. Attention is intermittent, not continuous.
- May follow briefly without aggression.

**Escalates to Suspicious** on repeated launches in short succession: launches by the ship **inside this Zurd's perception zone** (*proposed:* 5 launches within 10 seconds).

**De-escalates to Passive** when the ship leaves the perception zone, or the interest timer expires without new stimuli (*proposed:* 10 seconds).

**Cooldown:** short.

### 5.3 Stage 3: Suspicious

Focused observation and investigation.

- Sustained attention on the players' mass. **Begins eating objects off the mass.**
- More assertive approach and closer observation. Repeated scans and persistent following.
- **Keeps well away from the ship,** but close enough that the players can see it is looking at the ship.
- Movement and audiovisual cues convey urgency.
- **Shares information with nearby Zurds** (see section 8).

**Escalates to Hostile** when the mass the Zurd can see reaches the Hostile threshold (*playtest*; see open questions on whether this should use world pressure instead).

**De-escalates to Curious** when the players stop building a mass the Zurd can see for a time (*proposed:* 20 seconds; launching solitary objects is still allowed), or the ship moves away without further provocation. **Building** means an object fusing or combining into a mass the Zurd can see.

**Cooldown:** moderate. Attention persists after the activity stops.

### 5.4 Stage 4: Hostile

Enforcement and active aggression.

- Continuous focus on the ship. Pursues beyond its home.
- Changes color, moves faster, and grows larger (see section 11).
- Expressive hostility: facial expressions and sounds (placeholders).
- **Eats objects off the mass.**
- **Summons reinforcements:** spits out Suspicious Zurds, like Russian nesting dolls (see section 10).
- A swat still stuns it and drives it off.

**Becomes Hostile immediately,** from any stage, when the ship runs into the Zurd, a launched object hits it, or the players swat it.

**Escalates to High Alarm** when the mass the Zurd can see reaches the High Alarm threshold, or on repeated attacks on Zurds within a short time (*proposed:* 3 attacks within 15 seconds). The High Alarm threshold is a *playtest* question: it may need to be very high (around 80 objects), so that only spamming objects, or swatting and killing many Zurds, gets there.

**De-escalates to Suspicious** when the players stop both building and launching for a time (*proposed:* 30 seconds), or the ship escapes direct observation and moves far from every active mass.

**Cooldown:** long. Losing sight of the ship does not end the encounter.

### 5.5 Stage 5: High Alarm

Maximum threat and coordinated response.

- Multiple Zurds coordinate their pursuit. Reinforcements arrive in waves. The "more dangerous units" are, for now, simply Zurds that turn red.
- All Zurds actively search for the ship, not only the mass. **The ship counts as much as objects and masses** when a Zurd chooses what to go after.
- **Eats objects off the mass faster** than lower stages.
- Bigger, faster and a different color than Hostile. Hostile expressions with jerky movement and grimacing.
- **Attacks the ship:** at least one Zurd **clamps its jaws onto the ship**. The ship vibrates, the Zurd's tongue moves around the windshield, and it gnaws on the ship. The ship is **shoved around randomly** while it's attacked, so it may crash into sculptures and break objects off them. This is a dramatic distraction, not a lose state.
- **Swats no longer drive it off.** Many swats kill it: it falls to the ground in a cartoony way. Killing a Zurd makes nearby Zurds angrier.
- When the ship is lost, Zurds **search**: they go to its last known position and circle for a while (*proposed:* 20 seconds), then go back to guarding masses as Hostile.

**Stays at High Alarm** while aggression continues, while the ship and masses stay visible, or while the mass remains above the High Alarm threshold.

**De-escalates to Hostile** when any of these happen:

- The Zurds have dismantled the players' entire mass.
- The ship flies away far enough, for long enough (no boost: the ship simply flies away).
- Every Zurd near the ship has been killed or stunned at once (a large collaborative attack). *Open question.*

**Cooldown:** extended.

## 6. Stage Summary

| Stage | Eats objects | Escalates on | De-escalates to | Cooldown |
| --- | --- | --- | --- | --- |
| 1 Passive | No | Ship or launched object perceived | None | None |
| 2 Curious | No | Repeated launches in its zone | Passive | Short |
| 3 Suspicious | Yes | Mass reaches Hostile threshold | Curious | Moderate |
| 4 Hostile | Yes | Mass reaches High Alarm threshold, repeated attacks on Zurds | Suspicious | Long |
| 5 High Alarm | Yes (faster) | Sustained aggression | Hostile | Extended |

Swatting, the ship running into a Zurd, or a launched object hitting it sends that Zurd straight to Hostile from any stage.

Cooldown means the minimum time a Zurd stays in a stage before it can de-escalate (*proposed:* short 3 s, moderate 8 s, long 15 s, extended 30 s).

## 7. Eating Objects and the Cloud

- Zurds at stages 3 to 5 eat objects off a mass. **Loose objects can always be eaten**, not only objects on a mass (which stages graze on loose objects is an open question). The eating mechanics (duration, count dropping only when eating finishes, blink and scream) are in the Sculpture-Mass Design Doc.
- **Max eaters per object** is a parameter, so only a set number of Zurds can eat the same object at once.
- **Eating makes a Zurd grow,** up to a cap. Eating doesn't change its color or speed.
- Stage 5 eats faster (see section 12).
- A swat interrupts a bite: the object is unharmed.
- **When a mass becomes a cloud,** Zurds fly up after it, trying and failing to eat the empty cloud. After a delay, most Zurds despawn and the rest de-escalate. They are no longer a threat to the cloud. (To settle together with the Cloud-Formation Design Doc.)

## 8. Information Sharing

- Zurds share information with **nearby** Zurds only, within a share radius.
- A shared message carries the target's last-seen position and the sender's stage.
- Only Suspicious or higher senders share. Receivers rise to one stage below the sender, never lower than their current stage and never above Hostile from sharing alone.
- *Playtest:* whether sharing is needed at all, and how strong it is.

## 9. Fighting Zurds

- The players can **swat** Zurds (the primary defense, from the lidar walls), **run into** them with the ship, or **launch an object** into them. All three hurt the Zurd.
- **A swat stuns a Zurd and drives it off:** it bounces away and is briefly disoriented (*proposed:* 1.5 seconds) before it becomes Hostile. At High Alarm, swats no longer drive it off.
- **Killing takes many hits** (*playtest*), so in practice Zurds die only at High Alarm, when they stay and fight. A dying Zurd falls to the ground in a cartoony way. Dead Zurds don't come back.
- Killing a Zurd makes nearby Zurds angrier.
- How the pilot defends the ship is still being debated.

## 10. Spawning and Despawning

- **Population scales with pressure** (the objects in the world), at fewer than one Zurd per 10 objects. A few Zurds exist from the start, around the ship, alone or in pairs.
- **Difficulty scales with the players:** with a single player, slightly fewer or calmer Zurds.
- **New Zurds are spat out by angry Zurds,** like Russian nesting dolls. Hostile Zurds summon Suspicious Zurds this way; High Alarm sends waves.
- Dead Zurds don't come back.
- Zurds despawn after a cloud forms (section 7).
- Whether there is a cap, and its size, is *playtest* (and a performance check on the exhibit PC).

## 11. Visual Escalation

| Stage | Color | Speed | Size |
| --- | --- | --- | --- |
| 1-3 | Normal | x1.0 | x1.0 |
| 4 Hostile | Hostile tint | x1.25 (proposed) | x1.1 (proposed) |
| 5 High Alarm | Red | x1.5 (proposed) | x1.25 (proposed) |

Size from eating (section 7) adds to this, up to the growth cap. Stage changes also trigger expression and sound placeholders; the real animations and sounds are being made by a collaborator.

## 12. Parameters

Distances and speeds are rescaled to the current ship (top speed 55 m/s; launched objects stop about 120 m out). All are *proposed* starting points.

| Parameter | Description | Proposed value |
| --- | --- | --- |
| Perception radius | Radius of the perception circle; Y is unlimited | 150 m |
| Base speed | Hunting speed at stages 1-3; Hostile and High Alarm multiply it (section 11) | 30 m/s (wander 10 m/s) |
| Home radius | Loose radius around a Zurd's home | 100 m |
| Launches to escalate | Launches inside the zone within the window to reach Suspicious | 5 |
| Launch window | Time window for the above | 10 s |
| Curious interest timer | Time without stimuli before Curious returns to Passive | 10 s |
| Hostile threshold | Cloud progress seen that escalates to Hostile | 40% (*playtest*) |
| High Alarm threshold | What escalates to High Alarm | *playtest* (perhaps around 80 objects) |
| Build stop time (Suspicious) | No building before returning to Curious | 20 s |
| Inactivity time (Hostile) | No building and no launching before returning to Suspicious | 30 s |
| Escape distance | Distance from every active mass to escape | 300 m |
| Run-away duration (High Alarm) | Time spent far away to return to Hostile | 10 s |
| Attacks to escalate | Attacks on Zurds in the window to reach High Alarm | 3 |
| Attack window | Time window for the above | 15 s |
| Disorient time | Stun after a hit | 1.5 s |
| Hits to kill | Swats, rams or object hits that kill a Zurd | *playtest* (many) |
| Share radius | Distance within which Zurds share information | 150 m |
| Max eaters per object | Zurds eating one object at once | 1 |
| Eat speed multiplier | Stage 3 / 4 / 5 | x1.0 / x1.25 / x2.0 |
| Growth cap | Largest size eating can grow a Zurd to | *playtest* |
| Zurds per object | Population from pressure | Fewer than 1 per 10 objects (*playtest*) |
| Starting Zurds | Zurds in the world at the start | *open* |
| Summon count | Zurds spat out per Hostile summon | 2 |
| Summon distance | Spawn distance from the summoner | 15 m |
| Summon cooldown | Time between summons per Zurd | 20 s |
| Wave interval and size (High Alarm) | Waves of reinforcements | 25 s, 3 Zurds |
| Max Zurds | Cap on active Zurds | *playtest* |
| Search time (High Alarm) | Time spent circling the ship's last known position | 20 s |
| Cloud despawn fraction | Share of Zurds that despawn after a cloud forms | 70% |
| Cloud despawn delay | Time before those Zurds despawn (staggered) | 10-25 s |
| Alert Level drop hold | Delay before the displayed level drops | 2 s |
| Cooldowns | Minimum time in a stage before de-escalating: short / moderate / long / extended | 3 / 8 / 15 / 30 s |

## 13. Movement Behaviors

The stage state machine selects behavior from the movement component (hunt a target, avoid obstacles, wander). Each stage needs these movement modes:

| Mode | Used by |
| --- | --- |
| Wander around home | Passive |
| Slow approach, hold observation distance, intermittent scan | Curious |
| Persistent follow, approach to eat, keep well away from the ship | Suspicious |
| Continuous pursuit of the ship, beyond home | Hostile |
| Coordinated pursuit, search, clamp onto the ship | High Alarm |
| Disoriented (brief bounce away) | After a hit |
| Fall to the ground | Dying |
| Follow the cloud up | After a cloud forms |

## 14. Events and Placeholders (Event Bus signals)

| Signal | Fired when | Placeholder |
| --- | --- | --- |
| zurd\_stage\_changed | A Zurd changes stage | Expression, color and sound change |
| alert\_level\_changed | The highest stage changes | HUD indicator |
| zurd\_noticed | A Zurd first perceives a target | Notice cue |
| zurd\_info\_shared | A Zurd alerts nearby Zurds | Alert call |
| zurd\_started\_eating / zurd\_finished\_eating | Eating begins or finishes | Eating animation and sound (finish also drives the mass's object\_eaten) |
| zurd\_disoriented | A hit stuns a Zurd | Stun animation |
| zurd\_attacking\_ship / zurd\_released\_ship | A Zurd clamps onto the ship, or lets go | Ship vibration, tongue on the windshield, gnawing sound |
| zurd\_spawned / zurd\_despawned | A Zurd is created or removed | Spit-out or fade effect |
| zurd\_died | A Zurd is killed | Cartoony fall to the ground |
| zurd\_investigating | A Passive Zurd pauses at a point of interest (later) | Investigation animation |

## 15. Changes From the v2 Behavior Doc

- Swatting, running into a Zurd or hitting it with a launched object sends it straight to Hostile from any stage. The "swatting" trigger on lower stages and the "repeated bumping" triggers are removed.
- Stage thresholds are percentages of cloud progress for the mass the Zurd can see, not fixed object counts (under review: see open questions).
- High Alarm de-escalates to Hostile.
- Naming: "Sentinel" references are removed, and the top stage is called High Alarm.
- Information sharing is local (nearby Zurds), not map-wide.
- No lose state and no hard reset (2026-11-11 review).
- Sensitive areas are dropped; points of interest are a later feature.

## 16. Open Questions

Answered in the 2026-11-11 review: killing (many hits, angers others), lose state (none), perception shape, target choice, which mass counts (the largest seen), sensitive areas (dropped), launched objects hitting Zurds (Hostile, and it hurts), what spawns look like (spat out), hard reset (none).

Still open (numbers continue the review's questions):

1. **What counts as pressure,** and how it rewards building one sculpture rather than scattering objects (question 50).
2. **Stage thresholds:** per mass seen (as written), or from world pressure (question 51). The High Alarm threshold in particular.
3. **Starting population, growth with pressure, and the cap** (question 52).
4. **How difficulty scales with the players,** and how the game knows how many are playing (question 53).
5. **Which stages graze on loose objects** (question 54).
6. **Growth:** its cap, and whether swats still shrink a Zurd (question 55).
7. **The ship attack:** how long a Zurd stays on, how many at once, how hard the shove (question 56); whether it needs High Alarm (question 57).
8. **Dying:** what happens to the body, and to what the Zurd ate (question 58).
9. **Nesting dolls:** are spat-out Zurds small, and does the spitter shrink (question 59)?
10. **Collaborative stun** as a High Alarm exit (question 47); **stuns at High Alarm** (question 48).
11. **Information sharing:** needed, and how strong (question 62).
12. **The cloud outcome,** with the Cloud-Formation design (question 63).
13. **The pilot's defence** (being debated by the group).
14. **Objectives** for the players (question 49).
