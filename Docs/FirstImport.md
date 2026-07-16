# Your First Import
This guide walks you through importing a scene made in Cygon into Godot for the first time.

## Step 1 — Export from Cygon
- In Cygon's Project Manager, set the export path to a folder **inside your Godot project**.
- Use **CTRL + S** or the export button.
- Cygon generates a `.usda` file along with a `meshes/` subfolder (individual mesh files) and a `textures/` folder.
![Cygon export section](Screenshots/Cygon_ExportSection.png)

**Example structure inside your project (MyScene = the name of your Cygon scene):**
```
res://
└── MyScene/
    ├── MyScene.usda
    ├── meshes/
    │     ├── Wall.usda
    │     ├── Stairs.usda
    │     └── Floor.usda
    └── textures/
          └── ...
```

> Keep the relative layout — the importer resolves the `meshes/` and `textures/` paths **relative to the `.usda` location**. Moving the `.usda` away from its folders will break those references.

## Step 1 bis — Alternative: Drag & Drop
If you already have the exported files on disk, drag the `.usda` file **together with its `meshes/` and `textures/` folders** from your OS file explorer into the Godot **FileSystem** dock, keeping the same relative layout.

## Step 2 — Automatic Import
- Cygon Link recognizes Cygon `.usda` files by their header (`#usda 1.0 | Cygon`) and imports them automatically through its `EditorImportPlugin`, no pop-up, no manual approval.
- Each referenced mesh becomes a `StaticBody3D` containing a `MeshInstance3D` and a `CollisionShape3D` (a trimesh collider), and the scene hierarchy and transforms are reconstructed.
- Materials are built as `StandardMaterial3D` (albedo, normal map, metallic/roughness, and UV tiling) and embedded in the scene. For multi-material meshes, one surface + material is created per USD `GeomSubset`.

> Textures (`.png`) are standard Godot imports. If they were just added, Godot may import them a moment before the scene — a reimport of the `.usda` will pick them up.

## Step 3 — Add to Scene
Drag the imported `.usda` asset from the **FileSystem** dock into your **Scene** tree or the 3D viewport, and start using what you built in Cygon.

## Testing Without Cygon
A sample scene can be placed under `Docs/Samples/`. Drop it into the FileSystem dock to verify that:
- Cygon Link correctly intercepts the file,
- meshes, hierarchy, and materials are generated,
- no errors appear in the **Output** panel.

<!-- Add a Godot viewport capture of the imported sample here, e.g.:
![Godot sample import](Screenshots/Godot_SampleImport.png)
-->
