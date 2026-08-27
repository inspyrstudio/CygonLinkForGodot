@tool
extends RefCounted
class_name UsdaParser

## Parses the Cygon subset of USDA into a plain dict tree.
##
## The first line of every Cygon file is the marker comment [constant MARKER].
## Scene files and mesh files share the same marker — distinguish them by
## calling [method classify] on the parsed tree.

const MARKER: String = "#usda 1.0 | Cygon"

enum Kind { SCENE, MESH }

var error: String = ""

var _lexer: UsdaLexer = UsdaLexer.new()

## True if the first line of the source matches the Cygon marker.
func is_cygon_file(source: String) -> bool:
	return source.get_slice("\n", 0).strip_edges() == MARKER

## Tells a standalone mesh file apart from a scene file.
## Scene markers are checked first: a current-format scene holds its meshes
## inline, so looking for a `def Mesh` alone would misread it as a mesh file.
static func classify(tree: Dictionary) -> Kind:
	for prim: Dictionary in tree.get("prims", []):
		if _has_scene_markers(prim):
			return Kind.SCENE
	
	for prim: Dictionary in tree.get("prims", []):
		if _has_mesh(prim):
			return Kind.MESH
	return Kind.SCENE

## True if the prim or any descendant shows something only a scene file has:
## a material, a `kind` classification, or an external mesh reference.
static func _has_scene_markers(prim: Dictionary) -> bool:
	if prim.get("type", "") == "Material":
		return true
	
	var metadata: Dictionary = prim.get("metadata", {})
	if metadata.has("kind") or metadata.has("prepend references"):
		return true
	
	for child: Dictionary in prim.get("children", []):
		if _has_scene_markers(child):
			return true
	return false

static func _has_mesh(prim: Dictionary) -> bool:
	if prim.get("kind", "def") == "def" and prim.get("type", "") == "Mesh":
		return true
	
	for child: Dictionary in prim.get("children", []):
		if _has_mesh(child):
			return true
	return false

## Parses the source into a dict tree. Returns {} and sets error on failure.
func parse(source: String) -> Dictionary:
	error = ""
	if not is_cygon_file(source):
		error = "Not a Cygon USDA file (missing marker on line 1)"
		return {}
	
	_lexer.load(source)
	
	var metadata: Dictionary = _parse_paren_block()
	if not error.is_empty():
		return {}
	
	var prims: Array = []
	while not _lexer.is_at_end() and error.is_empty():
		var prim: Dictionary = _parse_prim()
		if prim.is_empty():
			break
		prims.append(prim)
	return {"metadata": metadata, "prims": prims}

func _parse_paren_block() -> Dictionary:
	var out: Dictionary = {}
	
	if not _lexer.try_consume("("):
		return out
	
	while error.is_empty():
		if _lexer.try_consume(")"):
			return out
		
		if _lexer.is_at_end():
			error = "Unclosed `(` block at line %d" % _lexer.current_line()
			return out
		
		var key: String = _read_qualified_key()
		if not _lexer.try_consume("="):
			error = "Expected '=' after key '%s' at line %d" % [key, _lexer.current_line()]
			return out
		out[key] = _parse_value()
	return out

func _read_qualified_key() -> String:
	_lexer.skip_whitespace()
	var first: String = _lexer.read_ident()
	
	if UsdaLexer.is_ident_start(_lexer.peek_code()):
		var second: String = _lexer.read_ident()
		return "%s %s" % [first, second]
	return first

func _parse_prim() -> Dictionary:
	_lexer.skip_whitespace()
	if _lexer.is_at_end():
		return {}
	
	var state: Dictionary = _lexer.save_state()
	var keyword: String = _lexer.read_ident()
	if keyword != "def" and keyword != "over" and keyword != "class":
		_lexer.restore_state(state)
		return {}
	
	var prim: Dictionary = {
		"kind": keyword,  # "def", "over" or "class"
		"type": "",
		"name": "",
		"metadata": {},
		"attrs": {},
		"children": [],
	}
	
	# Optional type ident before the quoted name.
	if _lexer.peek() != "\"":
		prim.type = _lexer.read_ident()
	
	if _lexer.peek() != "\"":
		error = "Expected prim name string at line %d" % _lexer.current_line()
		return {}
	
	prim.name = _lexer.read_string()
	prim.metadata = _parse_paren_block()
	if not error.is_empty():
		return {}
	if not _lexer.try_consume("{"):
		error = "Expected '{' after prim header for '%s' at line %d" % [prim.name, _lexer.current_line()]
		return {}
	
	# Body — child prims and attributes are interleaved.
	while error.is_empty():
		if _lexer.try_consume("}"):
			return prim
		
		if _lexer.is_at_end():
			error = "Unclosed `{` block at line %d" % _lexer.current_line()
			return prim
		
		var child: Dictionary = _parse_prim()
		if not child.is_empty():
			prim.children.append(child)
		else:
			_parse_attribute(prim.attrs)
	return prim

func _parse_attribute(out: Dictionary) -> void:
	var name: String = ""
	while UsdaLexer.is_ident_start(_lexer.peek_code()):
		name = _lexer.read_ident()
	
	if name.is_empty():
		error = "Expected attribute name at line %d" % _lexer.current_line()
		return
	
	if _lexer.try_consume("="):
		out[name] = _parse_value()
	else:
		out[name] = null
	
	if _lexer.peek_code() == 0x28:  # (
		out[name + ".meta"] = _parse_paren_block()

## Dispatches on the next character's code rather than on a one-character
## string: this runs once per value, so on a mesh's coordinate arrays it is the
## hottest path in the parser.
func _parse_value() -> Variant:
	var code: int = _lexer.peek_code()
	if code == -1:
		error = "Unexpected EOF in value at line %d" % _lexer.current_line()
		return null
	
	# Numbers first — array elements outnumber every other value by far.
	if UsdaLexer.is_number_start(code):
		return _lexer.read_number()
	if code == 0x28:  # (
		return _parse_tuple()
	if code == 0x5B:  # [
		return _parse_array()
	if code == 0x22:  # "
		return _lexer.read_string()
	if code == 0x40:  # @
		return {"_asset": _lexer.read_asset()}
	if code == 0x3C:  # <
		return {"_path": _lexer.read_path()}
	if UsdaLexer.is_ident_start(code):
		return _lexer.read_ident()
	
	error = "Unexpected char '%s' in value at line %d" % [char(code), _lexer.current_line()]
	return null

func _parse_tuple() -> Array:
	_lexer.try_consume("(")
	var out: Array = []
	while error.is_empty():
		if _lexer.try_consume(")"):
			return out
		if _lexer.is_at_end():
			error = "Unclosed tuple at line %d" % _lexer.current_line()
			return out
		out.append(_parse_value())
	return out

func _parse_array() -> Array:
	_lexer.try_consume("[")
	var out: Array = []
	while error.is_empty():
		if _lexer.try_consume("]"):
			return out
		if _lexer.is_at_end():
			error = "Unclosed array at line %d" % _lexer.current_line()
			return out
		out.append(_parse_value())
	return out
