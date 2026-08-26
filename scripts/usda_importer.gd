@tool
extends EditorImportPlugin

## Imports Cygon USDA files into Godot PackedScenes.

func _get_importer_name() -> String:
	return "cygon.usda"

func _get_visible_name() -> String:
	return "Cygon USDA"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["usda"])

func _get_resource_type() -> String:
	return "PackedScene"

func _get_save_extension() -> String:
	return "scn"

func _get_priority() -> float:
	return 1.0

func _get_import_order() -> int:
	return 100

func _can_import_threaded() -> bool:
	return false

func _get_preset_count() -> int:
	return 0

func _get_preset_name(_preset_index: int) -> String:
	return ""

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []

func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var file: FileAccess = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("CygonLink: cannot open %s" % source_file)
		return ERR_CANT_OPEN
	var source: String = file.get_as_text()

	var parser: UsdaParser = UsdaParser.new()
	if not parser.is_cygon_file(source):
		push_error("CygonLink: %s is not a Cygon USDA file (read %d bytes)" % [source_file, source.length()])
		return ERR_FILE_UNRECOGNIZED

	var tree: Dictionary = parser.parse(source)
	if not parser.error.is_empty():
		push_error("CygonLink: %s — %s" % [source_file, parser.error])
		return ERR_PARSE_ERROR

	var root: Node3D = _build_root(tree, source_file.get_base_dir())
	if root == null:
		push_error("CygonLink: failed to build scene for %s" % source_file)
		return FAILED

	var packed: PackedScene = PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		return pack_err
	return ResourceSaver.save(packed, "%s.%s" % [save_path, _get_save_extension()])


## Dispatches on file kind. Both kinds return a Node3D root packable as a PackedScene.
func _build_root(tree: Dictionary, base_dir: String) -> Node3D:
	match UsdaParser.classify(tree):
		UsdaParser.Kind.MESH:
			var mesh_prim: Dictionary = UsdaMeshBuilder.find_first_mesh_in_tree(tree)
			if mesh_prim.is_empty():
				return null
			return _wrap_mesh(UsdaMeshBuilder.build(mesh_prim), mesh_prim.name)
		UsdaParser.Kind.SCENE:
			return UsdaSceneBuilder.new().build(tree, base_dir)
	return null


## Builds a StaticBody3D root for a standalone mesh file and claims ownership on its children so they save into the packed scene.
func _wrap_mesh(mesh: ArrayMesh, mesh_name: String) -> Node3D:
	var body: StaticBody3D = UsdaMeshBuilder.build_static_body(mesh, mesh_name)
	if body == null:
		return null
	for child: Node in body.get_children():
		child.owner = body
	return body
