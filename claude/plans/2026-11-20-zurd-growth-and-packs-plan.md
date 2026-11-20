# Zurd iteration 2.1 plan: feeding, packs, growth, the cloud chase

Status: **built 2026-11-20** (approved the same day; answers, and what was built, at the end).

Design: Zurd Core Design Doc §12.4, §12.5 and the 2.0 playtest notes (§12.7, 2026-11-20).

## Goal

Act on the 2.0 playtest and build what was planned for 2.1:
1. **Launched objects feed Zurds**, quickly, instead of stunning them (precise launching).
2. **Shadows stay in view:** out of sight, they hurry back.
3. **Zurds give the ship room:** they keep out of a bubble around it.
4. **Grazers roam in packs** that vacuum up loose objects, instead of sitting on an even grid.
5. **Growth:** Zurds grow as they eat; bigger is slower and harder to drive off.
6. **The cloud chase:** Zurds that see a new cloud chase it up comically, give up and scatter home.
7. **The testing HUD** shows each Zurd's anger on the Zurd itself.

## 1. Launched objects feed the Zurd

- A launched object flying into a Zurd's hit area no longer stuns it, and no longer counts as an
  attack.
- The Zurd claims it, turns onto it and eats it at once, at a fast `catch_eat_speed` (*proposed:*
  4× its normal bite, under 1 s).
- It drops whatever it was doing, then carries on. **Being fed calms it a little:** its anger
  falls by `fed_calm` (*proposed:* 0.1 per part), so tossing food can soothe an angry Zurd.
- Growth makes this a trade-off: feeding a Zurd buys time, but makes it bigger.

## 2. Shadows hurry back into view

- A Shadow that has been out of the ship camera's view for `lost_time` (*proposed:* 1.5 s) dashes
  back to its spot at `dash_speed` (*proposed:* 90 m/s, faster than the ship's 55).
- It slows to its usual pace once it's back in view.
- "In view" means inside the ship camera's frustum. When the three-wall camera rig comes, that
  becomes any wall's camera.

## 3. A bubble around the ship

- Every Zurd keeps out of a bubble around the ship (*proposed* radius: 40 m, from the cockpit),
  steering away more strongly the deeper in it is. This works like the personal space between
  Zurds, but with the ship.
- **Food inside the bubble:** a Zurd still goes for it, but only the last few metres in, and it
  leaves straight after the bite (question 3).
- **Ramming** still counts as a swat when the ship flies into a Zurd. The bubble only stops Zurds
  from coming to the ship.

## 3b. A bubble around each Zurd

Zurds crowd and overlap. Each Zurd gets a small bubble of its own:
- **Size:** about its body's size, *proposed* 1.5× its body radius, so it grows with the Zurd.
- **The push gets strong fast** as two bubbles overlap, unlike the current gentle push. Zurds can
  brush past each other, but never sit inside one another.
- It replaces the fixed 8 m personal space, which a grown Zurd would outgrow.

## 4. Grazer packs

- The 15 Grazers form **3 packs of 5**, fixed for now (no merging or splitting).
- **Each pack has a moving centre** that roams the grazing disc. It wanders, and is drawn toward
  the loose objects it knows about: any within `pack_scent` (*proposed:* 600 m) of its centre.
- **Members wander around the pack's centre** (*proposed* radius: 60 m), feed by appetite as now,
  and keep their personal space. Several Zurds together sweep an area clean: the vacuum.
- **Packs keep apart** (*proposed:* at least 400 m between pack centres), so the map stays
  covered.
- **Hostile Grazers** go after loose objects near their pack, then sculptures near it (they still
  treat sculptures like loose objects).
- This replaces the fixed patches. The patch code goes; the director keeps the packs.

## 5. Growth

- **Each part a Zurd eats** grows it by `growth_per_bite` (*proposed:* 0.1×, so 30–40 bites to
  reach the cap), up to `max_growth` (*proposed:* 4.5×). It stays big.
- **What grows:** the Zurd is sized per part, not by scaling its body (iteration 1.3). Its mesh,
  body collider, mouth, hit area and health bar height all grow together, from one `size` value.
- **Bigger is slower:** speeds × `size^-0.3` (*proposed*), so a 4.5× Zurd moves at about 64%.
- **Bigger is harder to drive off:** `+1` swat per `swats_per_growth` of growth (*proposed:* 1 per
  +1.0×), so a full-size bold Zurd takes up to 7 swats.
- **Temperament's body variety** comes now: each Zurd starts at 0.9–1.1× size.
- **That's all:** bigger is slower and takes more swats, nothing else. The mouth grows with the body
  only so it still fits.

## 6. The cloud chase

- On `cloud_formed`, every Zurd that can see the cloud joins, except driven-off ones.
- **Each one:** drops its target and its hostility (anger falls to the calm threshold), races up
  toward the cloud at `chase_speed` (*proposed:* 50 m/s) and snaps at it.
- **Comic beat:** the cloud is see-through and can't be eaten, but the Zurds don't know that. While
  it's still low (it glides out before it climbs), they reach it, snap at it and **bounce off** with
  a spin, again and again, until they give up.
- **After `chase_time`** (*proposed:* 6 s) it gives up and returns to its home at its travel speed.
  For a Grazer, that's its pack. The scattering spreads the Zurds out again.
- It can't eat the cloud (clouds aren't targets).

## 7. The testing HUD on each Zurd

- A small anger bar on each Zurd (a `Label3D`, like the health bar), only while the testing HUD is
  on.
- It runs green, then yellow, then red as the anger nears the hostile threshold, with ▲ while
  rising and ▼ while falling. You can see at a glance which Zurds are heating up.
- The screen readout stays as it is.

## Files

| File | Change |
|---|---|
| `scenes/characters/enemy/zurd.gd` | feeding catch, bubble, Shadow dash, pack home, growth, cloud chase, anger bar |
| `scenes/characters/enemy/zurd_movement_component.gd` | ship bubble push; speeds from growth |
| `scenes/characters/enemy/zurd_mouth_component.gd` | an eat speed for caught objects; `object_eaten` gives the parts eaten (for growth) |
| `scenes/characters/enemy/zurd_director.gd` | packs (centres, roaming, scent, spacing) replace patches; the cloud chase hookup |
| `scenes/characters/enemy/zurd_role.gd`, `data/zurd_roles/*.tres` | pack, dash and chase settings |
| `scenes/characters/enemy/zurd.tscn` | the anger bar label |
| `scenes/ui/hud/zurd_testing_hud.gd` | toggles the per-Zurd bars |
| tests: `test_zurds.gd`, `test_zurd_roles.gd`, maybe `test_zurd_growth.gd` | updated and new |
| Zurd Core Design Doc §6, §12; CLAUDE.md Enemy; `tests/README.md` | updated |

## Steps

1. Feeding instead of stunning; the ship bubble; the per-Zurd anger bars. These are small and
   playtestable on their own.
2. Shadows dashing back into view.
3. Grazer packs.
4. Growth.
5. The cloud chase.
6. Docs; the full suite.

## Tests (rules, not tuning)

- A launched object flying into a Zurd: no stun, no swat; the Zurd eats it within the catch time,
  and its anger doesn't rise.
- A Zurd inside the ship bubble is pushed out, and idle Zurds never settle inside it.
- A Shadow left out of view dashes back into it within a few seconds.
- Packs:
  - the right number of packs and members;
  - members stay near their pack's centre;
  - pack centres stay apart and inside the disc;
  - a pack's centre heads for loose objects within its scent.
- Growth:
  - eating grows a Zurd per part, up to the cap, and the size stays;
  - all its parts scale together, and its body node stays unscaled;
  - speed falls and swats rise with size.
- The cloud chase:
  - a Zurd that sees a new cloud drops its hostility and target and goes up after it;
  - after the chase time it heads home;
  - a Zurd that can't see the cloud carries on.

## Risks

- **Big Zurds are big physics:** a 4.5× Zurd has a body collider of about 15 m. Watch for Zurds
  shoving sculptures apart and blocking each other. Personal space should scale with size.
- **The bubble vs eating near the ship:** Zurds may hover at the bubble's edge next to food just
  inside it. Hence the "go in for the bite" exception, which needs checking in play.
- **"In view"** uses the single ship camera now. The three-wall rig will need the same check per
  wall.

## Questions

1. **Feeding and anger:** should a fed Zurd's anger stay as it is (recommended: it's food, not an
   attack), or should feeding calm it a little, so tossing food is a way to soothe a Zurd?
2. **Shadow dash:** dash back (recommended: you see it swoop in), or simply reappear at the edge of
   the view?
3. **The ship bubble:** 40 m to start? And may Zurds dip in for food that's inside it
   (recommended), or must they wait until it drifts out?
4. **Packs:** 5 packs of 3 Grazers, or fewer, bigger packs (e.g. 3 of 5)? Should packs ever merge
   or split, or stay fixed (recommended: fixed, for now)?
5. **Growth effects:** besides slower and more swats, should big Zurds also eat faster or see
   further? Or keep it simple (recommended)?
6. **Growth numbers:** +0.1× per bite to a cap of 4.5×, speed × size^−0.3, +1 swat per +1×. OK as a
   start?
7. **Cloud chase:** Zurds can't reach a cloud at 1000 m in a few seconds. Fine for them to just
   race upward and give up, or should they get a short snap at it while it's still low (the first
   seconds after it forms)?

## Answers (2026-11-20)

1. Feeding calms a Zurd a little.
2. Shadows swoop back into view.
3. The ship bubble is 40 m and soft: Zurds may dip in and out.
4. 3 packs of 5 Grazers, fixed.
5. Growth only makes a Zurd slower and take more swats.
6. The growth numbers are fine to start.
7. The cloud chase is comic: the Zurds bounce off the see-through cloud.

Added: **a small bubble around each Zurd** (3b), so Zurds stop crowding and overlapping.

## As built (2026-11-20)

All six steps are built; the values are in the Zurd Core Design Doc §12.8. Beyond the plan:

- **Shadows carry the ship's velocity.** A play-through showed the swoop alone wasn't enough: at
  full speed the ship (55 m/s) outruns a Shadow's travel speed (45), so Shadows hovered at the edge
  of the view and kept dropping out (up to 14.7 s at a time). A Shadow's spot moves with the ship,
  so it now moves along with the ship and wanders or swoops on top of that. Wander legs are kept
  relative to the moving middle, which also suits the slowly moving packs. Afterwards: 2.5 s out
  of view at most, just after a turn.
- **A caught object stops in the air** (the Zurd snatches it). Otherwise the thrown object passed
  through the Zurd, which lets its target through its body, and flew on.
- **Packs rise or sink to food** they smell, and roam at their own height again after. With free
  flight, objects float at any height.
- **A pack leaves food that's nearer another pack** to that pack, so packs don't converge on the
  same mess.
- **Timid Zurds stay at one swat**, however big they grow; growth adds swats only to bolder Zurds.
- **The per-Zurd anger bars** are made in code, not in `zurd.tscn` (the editor was open).
- **Small changes outside the file list:** `CloudSky.get_cloud_radius` is now public and static,
  shared with the director, and `ZurdSightComponent.find_patch_target` is now `find_area_target`.
- **Tests:** 9 new scene tests (packs ×3, the swoop, the ship's space, growth ×3, the cloud chase)
  and 1 new unit test (feeding calms it). The feeding, bubble, cast and pack-home tests were
  rewritten. All the Zurd tests pass (51).

## Notes for Mitch

1. **The swat health bar is hard to see.** `HealthLabel` in `zurd.tscn` has a pixel size of
   0.001, so its text is about 2.4 cm tall in the world. The new anger bars keep a fixed size on
   screen. Should the swat bar do the same?
2. **Anger bars hide past 800 m** so far Grazers don't clutter the horizon. Is that right?
3. **Timid Zurds and growth:** a big timid Zurd still flees at the first swat. Keep that, or should
   growth add swats to every Zurd?
4. **The snatch:** a thrown object stops dead when it reaches a Zurd's hit area (7 m × its size).
   It reads as a catch; would you rather the Zurd lunge for it instead?
