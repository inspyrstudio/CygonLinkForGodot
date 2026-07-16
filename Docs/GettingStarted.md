# Getting Started with Cygon Link

Cygon Link is a bridge between **Cygon** and **Godot**. [Cygon](WhatIsCygon.md) is a standalone 3D environment blockout and prototyping tool. Cygon Link lets you bring your blockouts into Godot as native scenes, eliminating the traditional export/import friction.

## What does it do?
- **Automated scene generation**. Converts USDA scene hierarchies exported by Cygon directly into native Godot resources: meshes (with colliders), materials, and transforms, packed into a `PackedScene`.
- **Automatic reimport**. Godot watches the source `.usda` on disk and reimports it whenever it changes, so re-exporting from Cygon refreshes the asset in the editor.
- **Multi-material meshes**. Per-face materials are reconstructed from USD `GeomSubset` into separate mesh surfaces, each with its own material.
- **Pure GDScript**. No native code, no OpenUSD build step, no third-party dependencies.

## Before you start
Make sure you have the following ready:

| Software | Minimum Version |
|----------|-----------------|
| Godot    | 4.6+            |
| Cygon    | 0.3.3+          |

> New to Cygon? See [What is Cygon?](WhatIsCygon.md).

## Step-by-step guides
Follow these in order for your first setup:

1. [Requirements](Requirements.md). Check software versions and platform support.
2. [Installation](Installation.md). Install Cygon Link via the Godot Asset Store or a Git clone.
3. [First Import](FirstImport.md). Import your first Cygon scene into Godot.
4. [Live Reimport](LiveSync.md). Keep Godot in sync as you re-export from Cygon.

## How it works
- Export your scene from Cygon into your Godot project folder with **CTRL + S**.
- Switch to Godot, the `.usda` is imported automatically into the FileSystem dock.
- Drag the imported scene into your level.
- Make changes in Cygon, export again, Godot reimports and the asset updates.

For a deeper explanation of the pipeline, see [What is Cygon?](WhatIsCygon.md).

## Dependencies
Cygon Link has no third-party dependencies and needs no additional plugins. It is written entirely in GDScript and ships with its own `EditorImportPlugin`, so it runs on every platform the Godot editor supports without recompiling anything.
