# Models

Drop a `.glb` into the folder that matches what it's for. The importer
(`scripts/import/glb_post_importer.gd`, the project's default for scene imports) does the rest on
import:

| Folder | What you get |
|---|---|
| `objects/` | A rigid scene in `scenes/objects/rigid/`, for objects the ship launches, with one convex-hull collider around the whole model |
| `scenery/` | A static scene in `scenes/objects/static/`, for fixed scenery |
| any other folder, such as `characters/` | Only the shared mesh (`assets/meshes/`) and vertex-colour material (`assets/materials/objects/`) |

Every model gets the shared mesh and material files. A model left directly in `assets/models/` gets
those too, plus a warning, and no scenes. A change to the importer only reaches a model when it's
reimported: select the models in the FileSystem dock and press **Reimport** in the Import dock.

A new object only launches once it's in the object catalog: open `data/object_catalog.tres` and
press **Sync with rigid scenes**. That adds every rigid scene that isn't listed yet to the group
Unsorted; pick its group in the Inspector. To remove an object, delete its catalog entry first: a
catalog that lists a missing scene fails to load in the game, and the ship with it.

Name files in snake_case (`arch_01.glb`): the importer names every generated file after the model,
and exported builds are case-sensitive. Move and rename models in Godot's FileSystem dock, not in
Explorer. Renaming a model changes its generated files' names, so rename those files the same way
in the dock before reimporting; otherwise scenes and resources that use the old files (such as the
object catalog) keep pointing at them.
