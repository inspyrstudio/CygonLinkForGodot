@tool
extends EditorPlugin

var import_plugin = null

func _enable_plugin() -> void:
	# Add autoloads here.
	pass

func _disable_plugin() -> void:
	# Remove autoloads here.
	pass

func _enter_tree():
	import_plugin = preload("res://addons/CygonLink/scripts/usda_importer.gd").new()
	add_import_plugin(import_plugin)
#	var efs = EditorInterface.get_resource_filesystem()
#	efs.resources_reimported.connect(_on_resources_reimported)


func _exit_tree():
	if import_plugin != null:
		remove_import_plugin(import_plugin)
		import_plugin = null

#func _on_resources_reimported(resources: PackedStringArray):
#	for res in resources:
#		if res.get_extension() == "usda":
#			print("Hot reload déclenché pour : ", res)
