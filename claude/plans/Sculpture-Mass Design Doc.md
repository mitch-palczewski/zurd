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

## 4. Behaviors

### 4.1 Adding objects (fusion)

- The ship launches a rigid body object. On its own, a single object floats freely.
- Every collision between a loose object and another object, or an object in a mass, increments that object's hit counter.
- When the hit counter reaches *Hits to fuse*, the object fuses to the thing it is touching. Until then it clatters and bounces off as normal, which is the intended feel.
- If the thing it is touching at that moment is a matching object, loose or in a mass, the two **combine** instead of fusing (4.10).
- Two loose objects that collide also need to reach the hit counter before they form a new mass. (To be revisited as a special case if it does not feel right.)
- When two loose objects form a mass, the mass is created at their combined position.
- Fusion plays a **fusion animation** and a **fusion sound** (placeholders).
- **Momentum is conserved.** The velocity of the mass after fusion is the mass-weighted average of the mass and the incoming object. Each fused object therefore changes the mass's velocity less as the mass grows.
- **No impact threshold:** a collision at any speed counts toward the hit counter. There is no minimum impact speed and no cooldown.

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

- As the mass grows, each object's look moves linearly toward cloud-like: color toward white and a subtle transparency.
- The blend equals cloud progress, so it is **reversible**: if objects are eaten or broken off, the blend moves back.
- At 100% the appearance changes dramatically (see 4.7).

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
- Broken-off objects carry the mass's velocity at their position, so they leave naturally.
- A combined object breaks off whole and stays combined.

### 4.7 Cloud transformation

- When a mass's object count reaches the *Cloud threshold count*, a **gong sound** plays and the mass takes on full cloud properties.
- At 100% the objects stay visible but their material changes dramatically. Additional cloud puffs or fog may appear around the mass (placeholder effect). The mass does not collapse.
- The mass then floats up into the *Atmosphere Y range*, above the play area.
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

The cloud appearance comes from one cloud material on every fused object, driven by a single cloud amount value per mass. Extra puff and fog effects are deferred.

- Cloud amount equals cloud progress (0 to 1) and updates whenever the mass's object count changes.
- From 0% to 99%, each fused object blends linearly from its original look toward white, with a subtle transparency. The blend reverses if objects are eaten or broken off.
- At 100%, the material switches to the dramatic cloud look, with a short transition timed to the gong. The exact look is a placeholder.
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
- **Breaking off:** when an object in a mass grows, the fused objects it now overlaps break off as loose objects, pushed outward, and anything left disconnected falls off (4.8). A loose object that grows simply shoves its neighbours away.
- **Combined objects stay combined,** including when they break off a mass. Only Zurds take them apart, one part per bite (4.5).

## 5. Implementation Decision: One Rigid Body Per Mass

Each mass is a single rigid body. Fused objects become children (their mesh and collision shape), and the original loose body is removed.

- One velocity, one damping value, and one total mass per mass.
- Mass equals the object count (in parts) times the per-object mass. All parts have the same mass, whatever their size.
- Momentum conservation is one formula: `new_velocity = (M * V_mass + m * v_object) / (M + m)`.
- Removing an object spawns a new loose rigid body at its position, carrying the mass's velocity at that point.
- Shapes cannot be changed inside a physics callback, so fusion and removal are deferred by a frame.
- Angular momentum from off-center hits is approximate; treat exact conservation as optional polish.
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
| cloud\_formed | A mass reaches the threshold | Gong sound and cloud material and puffs |

## 7. Out of Scope

- Zurd behavior (separate doc).
- Ship launching and controls (separate doc).
- End-game state.

## 8. Open Items

- Add puff and fog effects later if the cloud material alone is not enough.
