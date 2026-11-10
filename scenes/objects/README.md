# Generated: do not edit

`static/` and `rigid/` are written by the GLB importer (`scripts/import/glb_post_importer.gd`)
when a model in `assets/models/` is imported: a rigid scene for models in `assets/models/objects/`,
a static scene for models in `assets/models/scenery/` (see that folder's README). Edits are
overwritten on the next import. To change an object, change the `.glb` or the importer and
re-import.

The rigid scenes' single convex-hull collider, centred on its node at scale 1, is relied on by the
launcher and the sculpture-mass code (see the importer's `_attach_convex_hull_collider`).
