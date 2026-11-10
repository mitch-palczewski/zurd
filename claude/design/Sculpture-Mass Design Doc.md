# Sculpture-Mass Design Doc

Zurd game · Godot (GDScript) · Functional design with implementation notes only where a decision is needed

## 1. Overview

The player builds a **sculptural mass** out of objects. The player's ship launches rigid body objects into other objects; once an object has hit enough times it fuses to what it hit, or, if what it hit is the same kind of object, **combines** with it into one bigger object. Enemy Zurds, when provoked, eat objects off a mass to shrink it. When a mass reaches the threshold object count it transforms into a **cloud**, permanently, and ascends above the play area to drift for the rest of play. The world has zero gravity.

## 2. Core Concepts

| Term | Meaning |
| --- | --- |
| Loose object | A rigid body launched by the ship (or broken off a mass). Floats freely until it fuses. |
| Mass | A group of fused objects that moves as one body. More than one mass can exist at once. |
| Cloud | A mass that has reached 100% of the threshold. Permanent; cannot shrink or be eaten. |
| Cloud progress | Object count divided by the threshold count, from 0% to 100%. |
| Combined object | Two or more matching objects merged into one bigger object (4.10). |
| Part | One launched object's worth of matter. A plain object is one part; a combined object is all the parts that went into it. |

Object counts in this doc count parts: a combined object made of 3 objects counts as 3.

## 3. Parameters

All parameters are exposed as exported values so they can be tuned.

| Parameter | Description | Starting value |
| --- | --- | --- |
| Cloud threshold count | Objects needed to transform a mass into a cloud | 60 (range under consideration: 60-100) |
| Hits to fuse | Collisions before a loose object fuses, or combines with a matching object. May be set to 1 for simplicity | Tune by feel |
| Atmosphere Y range | The band of heights where a finished cloud hovers | Tune in editor |
| Mass damping (linear / angular) | Slows a mass so it does not float forever | Tune by feel |
| Eat duration | Time a Zurd needs to eat one object, or one part of a combined object | Tune by feel |
| Combine size mode | How a combined object's size is worked out (4.10): *Add volumes* (scales 3 and 4 make about 4.5) or *Add scales* (3 + 4 = 7). A toggle for testing | Add volumes |
| Resize animation time | Length of the grow and shrink animation. Short and snappy | About 0.25 s, tune by feel |
| Refuse delay | Time after an object leaves a mass (knocked or fallen off) before its hits count again, so it drifts clear instead of fusing straight back (4.1). 0 = no delay | 1 s |
| Detach speed | Extra speed pushing an object that leaves a mass away from it, on top of the mass's own velocity at that point (4.6) | 1 m/s |
| Fuse push | How hard a fusing object pushes the mass. 1 = plain momentum conservation (4.1); higher counts the object as that many objects, so masses get knocked around more | 1 (the world currently uses 7.15) |
| Fuse spin | How much an off-centre fuse spins the mass. 0 = no spin; 1 = roughly physical (5) | 0 (the world currently uses 3.25) |
| Growth break depth | How far a growing object must push into a fused neighbour before the neighbour breaks off (4.10) | 0.1 m |
| Cloud transition time | How long the white burst takes to settle into the cloud look (4.7) | 2 s (most of the flash is gone in about 0.3 s) |
| Cloud rise delay | How long a new cloud holds still before it rises, so guests see the change (4.7) | 0.8 s |

## 4. Behaviors

### 4.1 Adding objects (fusion)

- The ship launches a rigid body object. On its own, a single object floats freely.
- Every collision between a loose object and another object, or an object in a mass, increments that object's hit counter.
- When the hit counter reaches *Hits to fuse*, the object fuses to the thing it is touching. Until then it clatters and bounces off as normal, which is the intended feel.
- If the thing it is touching at that moment is a matching object, loose or in a mass, the two **combine** instead of fusing (4.10).
- Two loose objects that collide also need to reach the hit counter before they form a new mass. (To be revisited as a special case if it does not feel right.)
- When two loose objects form a mass, the mass is created at their combined position.
- Fusion plays a **fusion animation** and a **fusion sound** (placeholders).
- **Momentum is conserved.** The velocity of the mass after fusion is the mass-weighted average of the mass and the incoming object. Each fused object therefore changes the mass's velocity less as the mass grows. *Fuse push* above 1 deliberately exaggerates the incoming object's weight in this average.
- **No impact threshold:** a collision at any speed counts toward the hit counter. There is no minimum impact speed and no cooldown, with one exception: an object that has just left a mass ignores hits for *Refuse delay*. Without it, a broken-off object, which starts out touching its old neighbours, would fuse straight back, and a falling-off chunk would re-form as a new mass at once.

### 4.2 Multiple masses and merging

- More than one mass can exist at the same time.
- When two masses collide and merge, their objects are shared into one mass, and the combined object count is used for the threshold.
- The merged mass conserves momentum, like any other fusion.
- If the two objects that touch when the masses meet are matching objects, they also combine (4.10). Only that touching pair combines.
- Each mass tracks its own count and its own cloud progress.

### 4.3 Mass movement

- A mass is free floating.
- Its velocity is changed by fused objects (4.1), the ship colliding with it, and Zurds running into it.
- Damping slows it over time so it does not drift forever.

### 4.4 Growth and cloud blend

- Fused objects stay **solid**: opaque, shaded and casting shadows like loose objects, so a mass reads as a real thing until it becomes a cloud.
- As the mass grows, each object's look moves **part of the way** toward cloud-like: color toward white (about 45% of the way just before 100%) and slightly more matte. The change eases in, so most of it comes in the last stretch.
- The blend follows cloud progress, so it is **reversible**: if objects are eaten or broken off, the blend moves back.
- At 100% the appearance **jumps** (see 4.7). The blend deliberately stops well short of the cloud look, so the jump is big.

### 4.5 Zurds eating objects

- Zurd behavior (provocation, targeting) is covered in the separate Zurd design doc. The mass only needs to support the following.
- A Zurd eats one object at a time. Eating takes *Eat duration*.
- Objects have no individual health. If the Zurd is interrupted, the object is unharmed and stays on the mass.
- The object count drops **only when eating finishes**.
- **Combined objects are eaten one part per bite.** Each bite takes *Eat duration* and removes the most recently added part, so the object visibly shrinks back the way it grew. The Zurd keeps chewing while the object stays in its mouth, and the object is gone when its last part is eaten. The count drops by one per bite. This applies to loose combined objects too.
- When an object (or a part) is eaten, the whole mass **blinks red** and a **scream of devastation sound** plays (placeholders).
- If the eaten object was holding other objects to the mass, the dependents fall off (see 4.8).
- A mass that is a cloud can no longer be eaten. Zurds may still try, but nothing happens.

### 4.6 Ship collision

- If the ship collides with a mass, a **collision sound** plays (placeholder).
- Only the objects the ship actually hits break off. They become loose rigid bodies again and can be re-fused later.
- The ship's impact also changes the mass's velocity.
- Broken-off objects carry the mass's velocity at their position, plus *Detach speed* away from the mass, so they leave naturally.
- A combined object breaks off whole and stays combined.

### 4.7 Cloud transformation

- When a mass's object count reaches the *Cloud threshold count*, a **gong sound** plays and the mass takes on full cloud properties.
- At 100% the objects stay visible but the look jumps at once: the whole mass flashes white and every object puffs up (to 1.5× in 0.15 s), then over the *Cloud transition time* the flash settles into the see-through, glowing cloud material and each object settles 1.2× its size, so the cloud reads fuller and softer. Each object puffs around its own middle. Additional cloud puffs or fog may appear around the mass (placeholder effect). The mass does not collapse.
- The cloud holds still for the *Cloud rise delay*, then floats up into the *Atmosphere Y range*, above the play area.
- **Permanent:** a cloud never shrinks back, and Zurds are no longer a threat to it.
- **Collisions:** a cloud stops colliding with the ship, Zurds and new objects, so it does not interfere with gameplay.
- As a cloud it drifts around for the rest of play. The drift is purely cosmetic.
- The game keeps accepting new objects after a cloud forms, so a new mass can start. The end-game state is out of scope for now.

### 4.8 Structural dependents

- Each fused object remembers which fused objects it was touching when it fused.
- When an object is removed (eaten or knocked off), any objects no longer connected to the main body fall off as loose rigid bodies.
- If the structure splits into two chunks, the larger chunk (by count) stays as the mass. The smaller chunk falls off as loose objects.
- A combined object that shrinks from a bite keeps everything it is attached to, even if a gap opens. Only removing it breaks its links.

### 4.9 Cloud look (material)

The look comes from two materials per mass, each shared by all its fused objects: a solid blend material before 100%, driven by a single cloud amount value, and a cloud material from 100%. Extra puff and fog effects are deferred.

- Cloud amount equals cloud progress (0 to 1) and updates whenever the mass's object count changes.
- From 0% to 99%, each fused object stays opaque and blends part of the way from its original look toward white and matte, easing in (4.4). The blend reverses if objects are eaten or broken off.
- At 100%, the mass swaps to the cloud material: white, see-through, glowing at the rim, with a hint of each object's own color. It starts as a white flash timed to the gong (4.7). The exact cloud look is a placeholder.
- Only fused objects show the blend. An object that leaves the mass returns to its original look.
- Additional puff and fog effects are out of scope for now.

### 4.10 Combining matching objects

When an object is shot into the same kind of object, the two become one bigger object instead of fusing.

- **Matching:** two objects match when they are the same model, at any size. Any loose object can combine, including objects broken off a mass.
- **When:** combining uses the hit counter. When an object's counter reaches *Hits to fuse* and the thing it is touching is a matching object, they combine instead of fusing.
- **Which pairs combine:**
  - Loose + loose: the bigger object (more parts, then larger size) stays where it is and grows; the smaller one is absorbed. The combined object's hit counter starts again from 0.
  - Loose + an object in a mass: the object in the mass grows in place and the loose one is absorbed.
  - Masses merging: only the pair that touches combines (4.2).
- **Size:** set by *Combine size mode*: add the volumes (default) or add the scales. There is no maximum size.
- **Counting:** a combined object counts as all its parts, for cloud progress and for weight, whether it is loose or in a mass.
- **Momentum:** conserved like fusion (4.1), weighted by parts.
- **Look and sound:** the collision shape grows at once; the object visibly scales up in a short, snappy animation with a **yellow flash** on the combined object only, and a **combine sound** plays (placeholders; the animation is not designed yet).
- **Breaking off:** when an object in a mass grows, the fused objects it now pushes into by more than *Growth break depth* (and didn't before it grew) break off as loose objects, pushed outward, and anything left disconnected falls off (4.8). Neighbours that were only touching stay. A loose object that grows simply shoves its neighbours away.
- **Combined objects stay combined,** including when they break off a mass. Only Zurds take them apart, one part per bite (4.5).

## 5. Implementation Decision: One Rigid Body Per Mass

Each mass is a single rigid body. Fused objects become children (their mesh and collision shape), and the original loose body is removed.

- One velocity, one damping value, and one total mass per mass.
- Mass equals the object count (in parts) times the per-object mass. All parts have the same mass, whatever their size.
- Momentum conservation is one formula: `new_velocity = (M * V_mass + m * v_object) / (M + m)`.
- Removing an object spawns a new loose rigid body at its position, carrying the mass's velocity at that point.
- Shapes cannot be changed inside a physics callback, so fusion and removal are deferred by a frame.
- Angular momentum from off-center hits is approximate; treat exact conservation as optional polish. *Fuse spin* adds the spin from an off-centre fuse using an estimated inertia (0 turns it off).
- Expected size is 60-100 shapes per mass, which this approach handles comfortably. Joint-based approaches were rejected as jittery and costly at that count.

## 6. Events and Placeholders (Event Bus signals)

Animation and sound hooks are signals on an Event Bus, so audio and effects can be attached without touching the mass code.

| Signal | Fired when | Placeholder hooked to it |
| --- | --- | --- |
| object\_hit | A counted hit lands on a loose object | Clatter sound |
| object\_fused | An object fuses to a mass | Fusion animation and sound |
| masses\_merged | Two masses combine | Merge effect |
| object\_eaten | A Zurd finishes eating an object, or one part of a combined object | Red blink and scream sound |
| objects\_broken\_off | The ship, or a growing object, breaks objects off a mass | Collision sound |
| objects\_combined | Two matching objects combine | Yellow flash and combine sound |
| object\_resized | An object grows from a combine or shrinks from a bite | Grow and shrink animation |
| cloud\_progress\_changed | A mass's count changes | Cloud blend update |
| cloud\_formed | A mass reaches the threshold | Gong sound; objects puff up (the white flash and cloud material are the mass's own); later, cloud puffs |

## 7. Out of Scope

- Zurd behavior (separate doc).
- Ship launching and controls (separate doc).
- End-game state.

## 8. Open Items

- Add puff and fog effects later if the cloud material alone is not enough.
