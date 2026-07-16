# Live Reimport

Cygon Link relies on Godot's built-in import pipeline to stay in sync with Cygon. When you re-export a scene from Cygon over the same files, Godot detects the changed `.usda` on disk and reimports it automatically, no manual step, no extra setup.

> This is an **editor-time** workflow. It refreshes the imported asset in the FileSystem dock and any open scene that uses it. Updating instances live while the game is *running* (Play Mode) is **not** currently supported.

## Setup
- Follow the [First Import](FirstImport.md) guide to import your scene (keep `meshes/` and `textures/` next to the `.usda`).
- Drag the imported asset into your scene.
- Keep the Godot editor open.

## Editing Loop
Once set up, the workflow is:
- Open your scene in **Cygon**.
- Make changes, modify geometry or transforms.
- Export with **CTRL + S** or the Cygon export button, **over the same files**.
- Switch back to **Godot**. It detects the changed `.usda` and reimports it; the asset refreshes in the editor.

## Manual reimport
If Godot does not pick up a change (for example, files added outside the project while the editor was closed):
- Right-click the `.usda` (or its folder) in the **FileSystem** dock and choose **Reimport**, or
- Use **Project → Tools → Reimport** to reprocess changed resources.

> Because referenced meshes are read directly from disk during import, editing a file under `meshes/` and reimporting the top-level `.usda` is enough to rebuild the whole scene.
