# Cygon Link for Godot
Seamless integration and live-sync for USDA files.

Cygon Link is a Godot plugin that brings USDA (Universal Scene Description ASCII) assets exported from Cygon directly into the Godot editor. It parses scene hierarchies, meshes, and materials, and turns them into native Godot `PackedScene` resources — ready to drag into your level.

## Key Features
📦 **Automated Asset Generation**: Converts USDA hierarchies, meshes, and materials directly into native Godot resources (`PackedScene`, `ArrayMesh`, `StandardMaterial3D`) with `StaticBody3D` + collision.

🔥 **Live Reimport**: Godot's import pipeline picks up changes to the source `.usda` file and reimports automatically — keep editing in Cygon, hit save, and the scene refreshes in Godot.

🛠️ **Pure GDScript, Zero Dependencies**: No native code, no third-party libraries, no OpenUSD compile step. Works on every platform Godot supports — without recompiling.

## Getting Started

[//]: # (### Installation via Godot Asset Library)

[//]: # (1. Open the **AssetLib** tab in the Godot editor.)

[//]: # (2. Search for **Cygon Link** *&#40;soon&#41;*.)

[//]: # (3. Click **Download** and install the plugin into your project.)

[//]: # (4. Go to **Project → Project Settings → Plugins** and enable **CygonLink**.)

### Installation via Git (Source Code)
If you prefer the latest development version:

1. Open a terminal inside your project's `addons/` folder (create it if it doesn't exist).
2. Clone the repository:
   ```shell
   git clone https://github.com/inspyrstudio/CygonLinkForGodot.git CygonLink
   ```
3. In Godot, go to **Project → Project Settings → Plugins** and enable **CygonLink**.

## How to Use
1. **Import your assets**: In Cygon, export your level into your Godot project folder. The exporter writes a top-level `.usda` and a `meshes/` subfolder next to it. Use **Ctrl + S** in Cygon or the export button to trigger an export.
2. **Add to scene**: Drag the imported `.usda` from the **FileSystem** into your viewport or scene tree.
3. **Live editing**: Keep Godot open. Edit and re-export from Cygon — Godot's filesystem watcher detects the change and reimports automatically. Your scene updates in place.

## Supported USDA Subset
The parser handles the subset of USDA that Cygon exports.
Files outside this subset will still parse if they fit the grammar, but unknown attributes are stored in the tree and ignored by the builder.

## Miscellaneous
⚙️ **Requirements**
- Godot **4.6** or higher (earlier versions should work, but are untested)
- Cygon **0.2.3i** or higher (earlier versions don't emit the export format the plugin expects)

🤝 **Contributing**
Contributions are welcome — open an issue or PR, or reach out on Discord if something doesn't behave the way you'd expect.
