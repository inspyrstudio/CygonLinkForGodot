# Installation

> New to Cygon? See [What is Cygon?](WhatIsCygon.md).

[//]: # (## Option 1 — Via the Godot Asset Store &#40;Recommended&#41;)
[//]: # (*&#40;soon&#41;*)
[//]: # ()
[//]: # (Once published, Cygon Link will be available from the in-editor Asset Library:)
[//]: # (- Open the **AssetLib** tab at the top of the Godot editor.)
[//]: # (- Search for **Cygon Link**.)
[//]: # (- Click **Download**, then **Install**, the files are placed under `addons/CygonLink/`.)
[//]: # (- Enable the plugin &#40;see [Enabling the plugin]&#40;#enabling-the-plugin&#41; below&#41;.)

## Option 1 — Via Git (Source Code)
Install the latest version straight from the repository:
- Open a terminal inside your project's `addons/` folder (create it if it doesn't exist).
- Clone the repository into a `CygonLink` folder:
  ```shell
  git clone https://github.com/inspyrstudio/CygonLinkForGodot.git CygonLink
  ```
- The plugin is now under `addons/CygonLink/`.

You can also download the repository as a ZIP and extract it into `addons/CygonLink/`.

## Enabling the plugin
- Open **Project → Project Settings → Plugins**.
- Find **CygonLink** in the list and toggle it **On**.

## Verifying the Installation
After enabling:
- No errors appear in the **Output** panel.
- Dropping a Cygon `.usda` file into your project imports it automatically as a scene (see [First Import](FirstImport.md)).
- A sample scene under `Docs/Samples/` (if bundled) imports without errors.

> For importing your own scenes from Cygon, see the [First Import Guide](FirstImport.md).
