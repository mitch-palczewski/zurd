# Objectives Design Doc

Zurd game · Godot (GDScript) · **Placeholder.** Started 2026-11-12 to collect what's known; to be
worked out after the first Zurd build.

## 1. Purpose

Objectives give the players goals that grow over a game: a ladder of sculptures to build, each a
little harder than the last. They also set the difficulty: the Zurds get stricter as objectives
are completed (Zurd Core Design Doc §3, §7).

## 2. What's Known

- **The first objective is very simple:** make a cloud of 5 objects. It can be completed
  without any trouble from the Zurds (they stay Passive until it's done).
- **Later objectives grow in difficulty, size and shape:** bigger clouds, and sculptures with a
  shape or theme (for example, a tall sculpture, or one made of animals; the object catalog's
  groups could define themes).
- **The cloud size changes per objective.** Today the cloud threshold is one number (20) in the
  MassManager.
- **Completing an objective raises the Zurd difficulty:** the tolerated mess and sculpture size
  shrink, and anger rises faster.

## 3. Questions to Answer

1. **The ladder:** how many objectives, and what is each one?
2. **Shape and theme:** how is a sculpture's shape or theme judged (object groups, height, width)?
3. **Showing objectives:** where on the walls, and how is completing one celebrated (with the
   Cloud-Formation design)?
4. **Failing or skipping:** can an objective be abandoned, and what happens when a sculpture
   becomes a cloud that doesn't match the current objective?
5. **New groups arriving:** in a gallery, groups change often. Does the ladder restart for a new
   group, and how does the game know? (The world doesn't reset between groups.)
6. **The end:** what happens after the last objective?
