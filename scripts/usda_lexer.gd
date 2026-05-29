@tool
extends RefCounted
class_name UsdaLexer

## Low-level character scanner for the USDA parser. Stateless from the
## caller's perspective — exposes peek/consume/read primitives only. Error
## reporting is the parser's job since only it knows what's "expected".

var _source: String = ""
var _cursor: int = 0
var _length: int = 0
var _line: int = 1

func load(source: String) -> void:
	_source = source
	_cursor = 0
	_length = source.length()
	_line = 1

func is_at_end() -> bool:
	return _cursor >= _length

## Skips spaces, tabs, CR, LF, commas, and `#` line comments.
func skip_whitespace() -> void:
	while _cursor < _length:
		var ch: String = _source[_cursor]
		if ch == "\n":
			_line += 1
			_cursor += 1
		elif ch == " " or ch == "\t" or ch == "\r" or ch == ",":
			_cursor += 1
		elif ch == "#":
			while _cursor < _length and _source[_cursor] != "\n":
				_cursor += 1
		else:
			return

## If the next non-whitespace char equals ch (in params, consume it and return true.
func try_consume(ch: String) -> bool:
	skip_whitespace()
	if _cursor < _length and _source[_cursor] == ch:
		_cursor += 1
		return true
	return false

## Returns the next non-whitespace char without consuming it. "" at EOF.
func peek() -> String:
	skip_whitespace()
	return "" if is_at_end() else _source[_cursor]

## Reads strings. Assumes the cursor is on the opening quote.
func read_string() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length and _source[_cursor] != "\"":
		if _source[_cursor] == "\n":
			_line += 1
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads USD asset reference. Assumes the cursor is on the opening @.
func read_asset() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length and _source[_cursor] != "@":
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads USD prim path. Assumes the cursor is on the opening <.
func read_path() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length and _source[_cursor] != ">":
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads an int or float. Return an [int] if the literal has no `.`/`e`/`E`, otherwise return a float [float].
func read_number() -> Variant:
	var start_pos: int = _cursor
	if _source[_cursor] == "+" or _source[_cursor] == "-":
		_cursor += 1
	
	while _cursor < _length:
		var ch: String = _source[_cursor]
		if ch.is_valid_int() or ch == "." or ch == "e" or ch == "E" or ch == "-" or ch == "+":
			_cursor += 1
		else:
			break
	
	var raw: String = _source.substr(start_pos, _cursor - start_pos)
	if raw.contains(".") or raw.contains("e") or raw.contains("E"):
		return float(raw)
	return int(raw)

## Reads an identifier: starts with a letter or `_`, followed by letters, digits, `:` or `.`. Appends `[]` if present.
func read_ident() -> String:
	var start_pos: int = _cursor
	while _cursor < _length:
		var ch: String = _source[_cursor]
		var is_first: bool = _cursor == start_pos
		if ch.is_valid_identifier() or ch == "_" or ch == ":" or ch == ".":
			_cursor += 1
		elif not is_first and ch.is_valid_int():
			_cursor += 1
		else:
			break
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	if _cursor + 1 < _length and _source[_cursor] == "[" and _source[_cursor + 1] == "]":
		_cursor += 2
		text += "[]"
	return text

## Current line number.
func current_line() -> int:
	return _line

## Returns a snapshot the parser can pass to [method restore_state] to undo a lookahead read.
func save_state() -> Dictionary:
	return {"cursor": _cursor, "line": _line}

## Restores cursor/line to a snapshot from [method save_state].
func restore_state(state: Dictionary) -> void:
	_cursor = state["cursor"]
	_line = state["line"]
