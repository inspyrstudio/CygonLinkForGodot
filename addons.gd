@tool
extends EditorPlugin

## Registers the Cygon USDA importer and refreshes already-placed instances when a source file changes on disk.

const _IMPORTER_FILE: String = "scripts/usda_importer.gd"

var _import_plugin: EditorImportPlugin = null
var _refreshing: bool = false

func _enter_tree() -> void:
	var dir: String = get_script().resource_path.get_base_dir()
	var importer_script: GDScript = load(dir.path_join(_IMPORTER_FILE))
	_import_plugin = importer_script.new()
	add_import_plugin(_import_plugin)
	
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	efs.resources_reimported.connect(_on_resources_reimported)

func _exit_tree() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.disconnect(_on_resources_reimported)
	
	if _import_plugin != null:
		remove_import_plugin(_import_plugin)
		_import_plugin = null

func _on_resources_reimported(resources: PackedStringArray) -> void:
	if _refreshing:
		return
	
	var changed: PackedStringArray = PackedStringArray()
	for path: String in resources:
		if path.get_extension().to_lower() == "usda":
			changed.append(path)
	
	if not changed.is_empty():
		_reimport_through_editor(changed)

## Runs the files back through EditorFileSystem.reimport_files() — the same
## entry point the FileSystem dock's "Reimport" uses, to force the cache to update.
func _reimport_through_editor(paths: PackedStringArray) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	
	_refreshing = true
	EditorInterface.get_resource_filesystem().reimport_files(paths)
	await get_tree().process_frame
	_refreshing = false