# Plan: More precise object colliders (convex decomposition)

*Approved 2026-11-11 as an experiment, to build after hardening step 1 (tests). If it costs too
much physics time, it is reverted (see Reverting).*

## Context

Mitch's observation from play: **objects fused together but didn't look physically attached.**
There were visible gaps between objects that were touching as far as the physics was concerned.

Reviewing the code, the cause isn't boxes:

- **Masses already collide with each object's exact convex hull.** When an object fuses,
  `SculptureMass` moves its `CollisionShape3D` (since 2026-11-10 the exact hull of the mesh) onto
  the mass unchanged (`sculpture_mass.gd`, around line 81). The mass is one rigid body holding
  every fused hull as a sub-shape (a *compound*), so the hulls are already combined in the precise
  way. Merging them into a single hull would be *less* precise, since it would fill every gap
  between the objects.
- **Boxes are used only for two internal estimates**, never for collisions: growth break-off
  (`MassPiece.get_boxes` / `get_box_overlap`) and the spin estimate
  (`SculptureMass.get_inertia_estimate`), both from each hull's bounding box.

The limit is **one convex hull per object.** A hull is the shape you'd get by shrink-wrapping
the model, so it fills every opening and hollow: under an arch, between a crocodile's legs,
between a tree's branches. Two objects touch where their hulls meet, which can be well away from
the models themselves, so they fuse with a visible gap between them.

**A split hull** (convex decomposition) is several convex hulls that together follow the model
more closely: an arch becomes two posts and a lintel instead of one block. Each object always has
the same hulls, loose or fused, so fusing behaves the same for every object.

## Measured (2026-11-11, Godot 4.7.2, this PC)

Godot's built-in convex decomposition (V-HACD, `MeshInstance3D.create_multiple_convex_collisions`)
is in the 4.7.2 mono build and can run from the importer. It caps each hull at 32 points. On six
models (volume is the collider's total volume; lower means it follows the model more closely):

| Model | Exact hull (today) | Decomposed, concavity 0.05 | Decomposed, 0.01 |
| --- | --- | --- | --- |
| Arch_01 | 1 hull, 186 pts | 5 hulls, 160 pts, **58%** of the volume | 6 hulls, 186 pts, 56% |
| Archway | 1 hull, 175 pts | 7 hulls, 208 pts, **72%** | 9 hulls, 255 pts, 67% |
| Crocodile_01 | 1 hull, 172 pts | 3 hulls, 96 pts, **74%** | 4 hulls, 128 pts, 71% |
| Tree_Stock_01 | 1 hull, 550 pts | 2 hulls, 64 pts, **67%** | 3 hulls, 96 pts, 65% |
| Stairs_01 | 1 hull, 97 pts | 1 hull (nothing gained) | 1 hull |
| Bush_Stock_01 | 1 hull, 1442 pts | 1 hull, 32 pts, 83% (simplified) | 1 hull |

- Concave models lose a quarter to almost half of their collider volume, with about the same or
  fewer points in total. Convex-ish models stay at one hull.
- Decomposing takes about 0.1–1.5 s per model, **at import only**; the game loads the result.
- Not yet measured: the physics cost in play. More sub-shapes per object means more shape pairs
  when objects touch, each cheaper (fewer points). The 2026-11-10 switch from boxes to exact
  hulls cost 2.4× physics time for 150 loose objects pressed together (1.3× with fusing on).

## Decisions (2026-11-11)

- **Automatic decomposition at import, as an experiment.** Kept only where it clearly helps (rule
  below); everything else keeps today's exact hull. Reverted if it costs too much.
- **No hand-made primitive colliders.** The current colliders are good; this is a refinement.
- **Same hulls loose and fused.** One collider set per object, in its rigid scene, so fusing is
  consistent and nothing is swapped at fuse time.
- **Performance budget:** at most 1.5× today's physics time in the 150-object scenarios. Jolt
  runs physics on the CPU, so the exhibit PC's GPU helps rendering but not this; the budget is
  judged on CPU time.
- **Static scenery gets exact triangle-mesh colliders**, as its own small step (below).
- **Order:** after hardening step 1, so the tests guard the change.

### Not chosen

| Option | Why not |
| --- | --- |
| Merge a mass's hulls into one | Less precise: fills the gaps between objects too |
| Hand-made primitive colliders (boxes, spheres, capsules) per model | More precision than needed, and a set to build and keep for every model |
| Triangle-mesh colliders on moving objects | Far too expensive, and unreliable between moving bodies |
| Split hulls only once fused | Two collider sets per object, swapped at fuse time; fusing would no longer match how objects touched |

## Design

### Importer (`scripts/import/glb_post_importer.gd`)

**Objects** (`assets/models/objects/`), for each model:

1. If `DECOMPOSE_OBJECTS` (a new importer constant, `true`) is on, **decompose** at concavity
   0.05 with at most 8 hulls (importer constants). Keep the result if it has **two or more hulls**
   and their total volume is **at most 85%** of the exact hull's.
2. Otherwise keep **today's single exact hull**. Convex-ish models (Stairs, Bush, the GEO set)
   don't change.

Every hull node sits at the model's middle at scale 1, with its points offset from there, as the
single hull does today. That keeps the existing code right without changes:

- The launcher already scales every child shape and its position (`_setup_transform_and_scale`),
  and combining does the same (`ObjectParts.resize_children`, `MassPiece.resize`).
- `MassPiece.get_center` averages shape positions, which all sit at the model's middle.
- `ObjectParts.of` reads the first shape's scale, which the launcher sets on every shape.
- Growth break-off and the spin estimate already measure each shape by its own box, so they
  become more precise for decomposed objects without a change: an object growing into an arch's
  opening no longer knocks off what sits on the far side.

The importer prints one line per model (hulls, points, volume against the single hull), so a
reimport shows which models changed.

**Scenery** (`assets/models/scenery/`): `_attach_convex_colliders` builds exact triangle-mesh
colliders (`create_trimesh_shape`) instead of a convex hull per mesh. Static bodies don't move,
so the exact shape costs little. The folder is empty today (the only static scenes are the old
root copies, used by `sandbox/world/test_ground.tscn`), so this takes effect with the next
scenery model.

### Catalog check (`scripts/objects/object_catalog.gd`)

Every collision shape must be a box or convex hull at scale 1, not only the first, and all of an
object's shapes must sit at the same position (the model's middle), the layout the code above
relies on.

## Steps

1. **Measure before keeping.** A scratch harness (not committed) runs the 150-objects scenario
   (loose objects pressed together, fusing off and on) and a mass at the cloud threshold, with
   today's hulls and with decomposed scenes made in a scratch copy of the project. Record physics
   time per frame. Over 1.5×: stop and report before going on.
2. **Importer:** object decomposition with the keep-or-fall-back rule and the report line;
   triangle-mesh colliders for scenery.
3. **Catalog check** for every shape.
4. **Reimport** the object models in the editor (select `assets/models/objects/`, *Reimport*;
   about a minute), then *Sync with rigid scenes* to run the collider check.
5. **Tests:** decomposed objects fuse, combine, break off and get bitten as before; growth
   break-off respects an arch's opening; the real catalog passes the new check.
6. **Playtest:** fused objects look attached; frame rate holds.
7. **Docs:** `CLAUDE.md` and `ONBOARDING.md` (importer, collider contract),
   `assets/models/README.md`.

## Reverting

If play shows the physics cost is too high: set `DECOMPOSE_OBJECTS` to `false` and reimport the
object models. Every object goes back to its single exact hull; the code and the catalog check
work either way. Middle ground before a full revert: fewer hulls (max 4) or a stricter keep rule
(at most 75% volume), so only the models that gain most stay decomposed.

## Done when

- The decomposed models' scenes have several hulls; convex-ish ones are unchanged.
- Fused concave objects (arch, archway, crocodile, tree) sit visibly closer, without the gaps
  Mitch saw. An object launched into an arch's opening can rest inside it.
- Physics time stays within 1.5× in the step-1 scenarios.
- All tests pass.

## Edge cases

- **Hulls overlap a little** at their seams. They're on one body, so they don't push each other;
  break-off measures each one separately, which only matters if the overlap is large.
- **A decomposition can miss a thin part** (a spike, a tail). The report line and a look in the
  editor catch it; that model then falls back to one hull (an exclusion list in the importer if
  needed).
- **Reimporting regenerates the rigid scenes.** Their UIDs stay, so the catalog keeps working.
- **Root-model duplicates** are gone (commit `a5c7b6d`), so each model writes its mesh files
  once.

## Later (not in this plan)

- **Sinking on fusion** (Mitch, 2026-11-11): when objects fuse, they sink into one another a
  little, so a mass reads as one piece. A design question for the Sculpture-Mass Design Doc
  first: how deep, how fast, and what break-off does with overlapping objects.

## Files

| File | Change |
| --- | --- |
| `scripts/import/glb_post_importer.gd` | Decomposition, fallback rule, report, `DECOMPOSE_OBJECTS`; trimesh for scenery |
| `scripts/objects/object_catalog.gd` | Collider check covers every shape |
| `scenes/objects/rigid/*` | Regenerated by the reimport, not hand-edited |
| `CLAUDE.md`, `claude/ONBOARDING.md`, `assets/models/README.md` | Collider contract |

## Open questions

None open. Thresholds (concavity 0.05, 8 hulls, 85% volume, 1.5× budget) are starting points to
tune from step 1's measurements.
