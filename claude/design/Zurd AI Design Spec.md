# Zurd AI Design Spec

Zurd game · Godot (GDScript) · Five-stage behavioral model, adapted from the Zurd AI Five-Stage Behavioral Model v2. Values marked *proposed* are starting points for tuning.

## 1. Overview

Zurds are the enemies of the game. Each Zurd runs its own state machine with five stages: **Passive, Curious, Suspicious, Hostile, High Alarm**. A Zurd changes stage only when a trigger fires. Zurds share information with nearby Zurds. The player sees a GTA-style **Alert Level** that reports the highest stage among all Zurds. There is one player.

The model is inspired by the way enemies in No Man's Sky escalate, but it is a simplified framework, not a copy of that game's AI.

## 2. Core Concepts

| Term | Meaning |
| --- | --- |
| Stage | The Zurd's current behavior state (1 to 5). Each Zurd has its own. |
| Alert Level | The highest stage among all Zurds, shown to the player. |
| Perception zone | The area where a Zurd notices things. The same at every stage. |
| Sculpture progress | Cloud progress (object count divided by the cloud threshold) of a mass the Zurd can see. See the Sculpture-Mass Design Doc. |
| Point of interest | Something that holds a Passive Zurd's attention, such as an environmental feature like a flower. |

## 3. Alert Level (wanted level)

- The Alert Level equals the highest stage among all active Zurds. 0 means every Zurd is Passive, then 1 = Curious, 2 = Suspicious, 3 = Hostile, 4 = High Alarm.
- It is recalculated whenever any Zurd changes stage, and also when a Zurd despawns or dies.
- *A* short hold (about 2 seconds) before the displayed level drops, so the indicator does not flicker when the top Zurd despawns.
- The HUD presentation is a placeholder, driven by the `alert_level_changed` signal.

## 4. Perception

- Perception is the same at every stage.
- The zone covers the **entire vertical (Y) range**, with a limited size in x and z.
- A Zurd perceives the following **separately**:
  - the ship
  - sculpture masses
  - launched objects
  - points of interest (such as flowers)
- Individual launched objects are less interesting to a Zurd than the ship or a mass.
- Points of interest only hold attention while a Zurd is Passive. From Suspicious on, Zurds suspend autonomous activity.
- *Proposed interest weights* (a starting mechanism for choosing what to attend to):

| Perceived thing | Weight |
| --- | --- |
| Mass | 1.0 |
| Ship | 0.8 |
| Point of interest (Passive only) | 0.5 |
| Launched object | 0.3 |

## 5. The Five Stages

### 5.1 Stage 1: Passive

Unaware and autonomous.

- Wanders within a territory by picking a random point and walking to it.
- **Pauses to investigate** interesting things nearby (points of interest). Otherwise it keeps moving.
- Changes direction without any player influence.
- Neutral toward everything. Does not seek out the player.

**Escalates to Curious** when the ship enters the perception zone, or a launched object enters the perception zone.

**Cooldown:** none. This is the baseline state.

### 5.2 Stage 2: Curious

Awareness and interest, with no hostility.

- Turns toward the player's mass and briefly interrupts its patrol.
- Approaches slowly and deliberately, then keeps a comfortable observation distance.
- Scans the ship, mass or surroundings intermittently. Attention is intermittent, not continuous.
- May follow briefly without aggression.

**Escalates to Suspicious** on repeated launches in short succession (*proposed:* 5 launches within 10 seconds).

**De-escalates to Passive** when the ship leaves the perception zone, the player launches nothing, or the interest timer expires without new stimuli (*proposed:* 8 seconds).

**Cooldown:** short.

### 5.3 Stage 3: Suspicious

Focused observation and investigation.

- Sustained attention on the player's mass. **Begins eating objects off the mass.**
- More assertive approach and closer observation. Repeated scans and persistent following.
- Suspends autonomous activities (no more investigating points of interest).
- Movement and audiovisual cues convey urgency.
- **Shares information with nearby Zurds** (see section 8).
- Still timid about approaching the ship.

**Escalates to Hostile** when the mass the Zurd can see reaches the Hostile threshold (*proposed:* 40% cloud progress).

**De-escalates to Curious** when the player stops building the mass for a time (*proposed:* 20 seconds; launching solitary objects is still allowed), or the ship moves away without further provocation.

**Cooldown:** moderate. Attention persists after the activity stops.

### 5.4 Stage 4: Hostile

Enforcement and active aggression.

- Continuous focus on the ship. Pursues beyond its normal territory.
- Changes color, moves faster, and possibly grows larger (see section 11).
- Expressive hostility: facial expressions and sounds (placeholders).
- **Eats objects off the mass.**
- **Summons reinforcements:** spawns Suspicious Zurds at a set distance from the summoning Zurd (see section 10).

**Becomes Hostile immediately,** from any stage, when the ship runs into the Zurd or the player swats it.

**Escalates to High Alarm** when the mass the Zurd can see reaches the High Alarm threshold (*proposed:* 75% cloud progress), or on repeated attacks on Zurds within a short time (*proposed:* 3 attacks within 15 seconds).

**De-escalates to Suspicious** when the player stops both building and launching for a time (*proposed:* 30 seconds), or the ship escapes direct observation and moves far from every active mass (*proposed:* 60 units).

**Cooldown:** long. Losing sight of the player does not end the encounter.

### 5.5 Stage 5: High Alarm

Maximum threat and coordinated response.

- Multiple Zurds coordinate their pursuit. Reinforcements arrive in waves, and more dangerous units may spawn.
- All Zurds actively search for the ship, not only the mass.
- **Eats objects off the mass faster** than lower stages.
- Bigger, faster and a different color than Hostile. Hostile expressions with jerky movement and grimacing.
- At least one Zurd attacks the ship itself.
- When the ship is lost, Zurds **search** instead of returning to Passive (details are an open question).

**Stays at High Alarm** while aggression continues, while the ship and masses stay visible, or while the mass remains above the High Alarm threshold.

**De-escalates to Hostile** when any of these happen:

- The Zurds have dismantled the player's entire mass.
- The player runs away at full boost and far enough for long enough (*proposed:* 60 units for 10 seconds).
- Every Zurd in the notice zone has been killed or stunned (a large collaborative attack).

**Hard reset (proposed):** if the player leaves the room, or is completely inactive for an extended time (building, launching and attacking all stopped, *proposed:* 90 seconds), all Zurds reset to Passive and extra Zurds despawn. This is the idle "game over" state. It needs confirming.

**Cooldown:** extended.

## 6. Stage Summary

| Stage | Eats objects | Escalates on | De-escalates to | Cooldown |
| --- | --- | --- | --- | --- |
| 1 Passive | No | Ship or launched object perceived | None | None |
| 2 Curious | No | Repeated launches | Passive | Short |
| 3 Suspicious | Yes | Mass reaches Hostile threshold | Curious | Moderate |
| 4 Hostile | Yes | Mass reaches High Alarm threshold, repeated attacks on Zurds | Suspicious | Long |
| 5 High Alarm | Yes (faster) | Sustained aggression | Hostile | Extended |

Swatting, or the ship running into a Zurd, sends that Zurd straight to Hostile from any stage.

## 7. Eating Objects and the Cloud

- Zurds at stages 3 to 5 eat objects off a mass. The eating mechanics (duration, count dropping only when eating finishes, blink and scream) are in the Sculpture-Mass Design Doc.
- **Max eaters per object** is a parameter, so only a set number of Zurds can eat the same object at once.
- Eating does not change a Zurd's color, speed or size.
- Stage 5 eats faster (see section 12).
- **When a mass becomes a cloud**, Zurds follow it, trying and failing to eat the empty cloud. After a delay, most Zurds despawn and the rest de-escalate. They are no longer a threat to the cloud.

## 8. Information Sharing

- Zurds share information with **nearby** Zurds only, within a share radius.
- A shared message carries the target's last-seen position and the sender's stage.
- *O*nly Suspicious or higher senders share. Receivers rise to one stage below the sender, never lower than their current stage and never above Hostile from sharing alone.

## 9. Fighting Zurds

- The player can **swat** Zurds (the primary defense), **run into** them with the ship, or **launch an object** into them.
- A collision bounces the Zurd and briefly disorients it (*proposed:* 1.5 seconds) before it becomes Hostile.
- How many hits kill a Zurd is undecided (see Open Questions).

## 10. Spawning and Despawning

- Hostile Zurds summon reinforcements that spawn as Suspicious Zurds at a set distance from the summoner. High Alarm sends waves, possibly with more dangerous unit types (placeholder).
- Very aggressive Zurds spit out other Zurds (placeholder animation).
- Zurds despawn after a cloud forms (section 7), and extra Zurds despawn on a hard reset.
- Whether spawn counts are fixed or scale with the player's object count is an open question. The numbers below are placeholders.

## 11. Visual Escalation

| Stage | Color | Speed | Size |
| --- | --- | --- | --- |
| 1-3 | Normal | x1.0 | x1.0 |
| 4 Hostile | Hostile tint | x1.25 (proposed) | x1.1 (proposed) |
| 5 High Alarm | Alarm tint | x1.5 (proposed) | x1.25 (proposed) |

Stage changes also trigger expression and sound placeholders.

## 12. Parameters

| Parameter | Description | Proposed value |
| --- | --- | --- |
| Perception size (x, z) | Half-extent of the perception zone; Y is unlimited | 25 units |
| Launches to escalate | Launches within the window to reach Suspicious | 5 |
| Launch window | Time window for the above | 10 s |
| Curious interest timer | Time without stimuli before Curious returns to Passive | 8 s |
| Hostile threshold | Cloud progress seen that escalates to Hostile | 40% |
| High Alarm threshold | Cloud progress seen that escalates to High Alarm | 75% |
| Build stop time (Suspicious) | No building before returning to Curious | 20 s |
| Inactivity time (Hostile) | No building and no launching before returning to Suspicious | 30 s |
| Escape distance | Distance from every active mass to escape | 60 units |
| Attacks to escalate | Attacks on Zurds in the window to reach High Alarm | 3 |
| Attack window | Time window for the above | 15 s |
| Run-away duration (High Alarm) | Time spent far away to return to Hostile | 10 s |
| Disorient time | Stun after a collision | 1.5 s |
| Share radius | Distance within which Zurds share information | 30 units |
| Max eaters per object | Zurds eating one object at once | 1 |
| Eat speed multiplier | Stage 3 / 4 / 5 | x1.0 / x1.25 / x2.0 |
| Summon count | Zurds spawned per Hostile summon | 2 |
| Summon distance | Spawn distance from the summoner | 15 units |
| Summon cooldown | Time between summons per Zurd | 20 s |
| Wave interval and size (High Alarm) | Waves of reinforcements | 25 s, 3 Zurds |
| Max Zurds | Hard cap on active Zurds (placeholder) | 12 |
| Cloud despawn fraction | Share of Zurds that despawn after a cloud forms | 70% |
| Cloud despawn delay | Time before those Zurds despawn (staggered) | 10-25 s |
| Alert Level drop hold | Delay before the displayed level drops | 2 s |
| Hard reset inactivity | Total inactivity before a High Alarm reset | 90 s |

## 13. Movement Behaviors

The stage state machine selects behavior from the existing movement component (hunt a target, avoid obstacles, wander). Each stage needs these movement modes:

| Mode | Used by |
| --- | --- |
| Wander with investigation pauses | Passive |
| Slow approach, hold observation distance, intermittent scan | Curious |
| Persistent follow, approach to eat, keep distance from the ship | Suspicious |
| Continuous pursuit of the ship, beyond territory | Hostile |
| Coordinated pursuit and search | High Alarm |
| Disoriented (brief) | After a collision |
| Follow the cloud | After a cloud forms |

## 14. Events and Placeholders (Event Bus signals)

| Signal | Fired when | Placeholder |
| --- | --- | --- |
| zurd\_stage\_changed | A Zurd changes stage | Expression, color and sound change |
| alert\_level\_changed | The highest stage changes | HUD indicator |
| zurd\_noticed | A Zurd first perceives a target | Notice cue |
| zurd\_investigating | A Passive Zurd pauses at a point of interest | Investigation animation |
| zurd\_info\_shared | A Zurd alerts nearby Zurds | Alert call |
| zurd\_started\_eating / zurd\_finished\_eating | Eating begins or finishes | Eating animation and sound (finish also drives the mass's object\_eaten) |
| zurd\_disoriented | A collision stuns a Zurd | Stun animation |
| zurd\_spawned / zurd\_despawned | A Zurd is created or removed | Spit-out or fade effect |
| zurd\_died | A Zurd is killed | Death effect |

## 15. Changes From the v2 Behavior Doc

- Swatting or running into a Zurd now sends it straight to Hostile from any stage. The "swatting" trigger on lower stages and the "repeated bumping" triggers are removed.
- Stage thresholds are percentages of cloud progress for the mass the Zurd can see, not fixed object counts.
- High Alarm de-escalates to Hostile.
- Naming: "Sentinel" references are removed, and the top stage is called High Alarm.
- Information sharing is local (nearby Zurds), not map-wide.

## 16. Open Questions

1. **Killing a Zurd.** Does killing a Zurd make nearby Zurds more aggressive or make them run away? To be decided by testing the gameplay effect of each.
2. **Hits to kill.** How many swats or hits does it take to kill a Zurd?
3. **Spawn count.** Is the number of Zurds fixed, or proportional to the player's object count? What exactly happens when aggressive Zurds spit out others, and what is the cap?
4. **Choosing between targets.** How does a Zurd decide among multiple masses, loose objects and points of interest? Are the interest weights in section 4 the right mechanism?
5. **Which mass percentage counts.** With several masses in view, do the Hostile and High Alarm thresholds use the largest mass's cloud progress (proposed) or a combined total?
6. **Perception details.** What shape is the x/z zone (circle or box), and does it need line of sight?
7. **The search state.** What does a High Alarm Zurd do after losing the ship: go to the last known position, search for how long, and in what pattern?
8. **Hard reset.** Confirm that leaving the room or long total inactivity resets everything to Passive, rather than only dropping High Alarm to Hostile.
9. **Information sharing.** Is the strength of sharing (receivers one stage below the sender) right, and is the radius appropriate?
10. **Sensitive areas.** The v2 doc mentions "lingering in a sensitive area" as a Curious trigger. Do these areas exist, or should the trigger be dropped?
11. **Launched objects hitting Zurds.** Does a launched object hitting a Zurd make it Hostile, as swatting does?
12. **Disorientation.** Does the bounce and stun apply at every stage, and for how long?
13. **Cloud outcome.** Confirm the proposed despawn fraction, delay, and the step-down path for the remaining Zurds.
14. **High Alarm units.** How many Zurds must attack the ship directly, and what are the "more dangerous units"?
