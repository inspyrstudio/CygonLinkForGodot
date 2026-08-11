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

## Returns MESH if the tree contains a `def Mesh` at any depth, else SCENE.
static func classify(tree: Dictionary) -> Kind:
	for prim: Dictionary in tree.get("prims", []):
		if _has_mesh(prim):
			return Kind.MESH
	return Kind.SCENE

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
	
	var next_ch: String = _lexer.peek()
	if not next_ch.is_empty() and (next_ch.is_valid_identifier() or next_ch == "_"):
		var second: String = _lexer.read_ident()
		return "%s %s" % [first, second]
	return first

func _parse_prim() -> Dictionary:
	_lexer.skip_whitespace()
	if _lexer.is_at_end():
		return {}
	
	var state: Dictionary = _lexer.save_state()
	var keyword: String = _lexer.read_ident()
	if keyword != "def" and keyword != "over":
		_lexer.restore_state(state)
		return {}
	
	var prim: Dictionary = {
		"kind": keyword,  # "def" or "over"
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
	var idents: Array[String] = []
	while true:
		var ch: String = _lexer.peek()
		if ch.is_empty():
			break
		if not (ch.is_valid_identifier() or ch == "_"):
			break
		idents.append(_lexer.read_ident())
	
	if idents.is_empty():
		error = "Expected attribute name at line %d" % _lexer.current_line()
		return
	
	var name: String = idents[idents.size() - 1]
	if _lexer.try_consume("="):
		out[name] = _parse_value()
	else:
		out[name] = null
	
	if _lexer.peek() == "(":
		out[name + ".meta"] = _parse_paren_block()

func _parse_value() -> Variant:
	var ch: String = _lexer.peek()
	if ch.is_empty():
		error = "Unexpected EOF in value at line %d" % _lexer.current_line()
		return null
	if ch == "\"":
		return _lexer.read_string()
	if ch == "@":
		return {"_asset": _lexer.read_asset()}
	if ch == "<":
		return {"_path": _lexer.read_path()}
	if ch == "(":
		return _parse_tuple()
	if ch == "[":
		return _parse_array()
	if ch.is_valid_int() or ch == "-" or ch == "+" or ch == ".":
		return _lexer.read_number()
	if ch.is_valid_identifier() or ch == "_":
		return _lexer.read_ident()
	error = "Unexpected char '%s' in value at line %d" % [ch, _lexer.current_line()]
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
