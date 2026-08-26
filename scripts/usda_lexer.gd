@tool
extends RefCounted
class_name UsdaLexer

## Low-level character scanner for the USDA parser. Stateless from the
## caller's perspective — exposes peek/consume/read primitives only. Error
## reporting is the parser's job since only it knows what's "expected".
##
## Scanning works on character codes via [method String.unicode_at] rather than
## on one-character strings: indexing a String allocates a new String per
## character, which dominates the cost on files holding tens of thousands of
## numbers.

const _TAB: int = 9
const _LF: int = 10
const _CR: int = 13
const _SPACE: int = 32
const _QUOTE: int = 34
const _HASH: int = 35
const _PLUS: int = 43
const _COMMA: int = 44
const _MINUS: int = 45
const _DOT: int = 46
const _ZERO: int = 48
const _NINE: int = 57
const _COLON: int = 58
const _GREATER: int = 62
const _UPPER_A: int = 65
const _UPPER_E: int = 69
const _UPPER_Z: int = 90
const _BRACKET_OPEN: int = 91
const _BRACKET_CLOSE: int = 93
const _UNDERSCORE: int = 95
const _LOWER_A: int = 97
const _LOWER_E: int = 101
const _LOWER_Z: int = 122
const _AT: int = 64

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
		var code: int = _source.unicode_at(_cursor)
		if code == _LF:
			_line += 1
			_cursor += 1
		elif code == _SPACE or code == _TAB or code == _CR or code == _COMMA:
			_cursor += 1
		elif code == _HASH:
			while _cursor < _length and _source.unicode_at(_cursor) != _LF:
				_cursor += 1
		else:
			return

## If the next non-whitespace char equals ch (in params), consume it and return true.
func try_consume(ch: String) -> bool:
	skip_whitespace()
	if _cursor < _length and _source.unicode_at(_cursor) == ch.unicode_at(0):
		_cursor += 1
		return true
	return false

## Returns the next non-whitespace char without consuming it. "" at EOF.
func peek() -> String:
	skip_whitespace()
	return "" if is_at_end() else _source[_cursor]

## Character code of the next non-whitespace char, or -1 at EOF. Lets callers
## dispatch without allocating a String per lookahead.
func peek_code() -> int:
	skip_whitespace()
	return -1 if is_at_end() else _source.unicode_at(_cursor)

## True if [param code] can open an identifier: a letter or `_`.
static func is_ident_start(code: int) -> bool:
	return (code >= _LOWER_A and code <= _LOWER_Z) \
		or (code >= _UPPER_A and code <= _UPPER_Z) \
		or code == _UNDERSCORE

## True if [param code] can open a number: a digit, sign, or decimal point.
static func is_number_start(code: int) -> bool:
	return (code >= _ZERO and code <= _NINE) \
		or code == _MINUS or code == _PLUS or code == _DOT

## Reads strings. Assumes the cursor is on the opening quote.
func read_string() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length:
		var code: int = _source.unicode_at(_cursor)
		if code == _QUOTE:
			break
		if code == _LF:
			_line += 1
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads USD asset reference. Assumes the cursor is on the opening @.
func read_asset() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length and _source.unicode_at(_cursor) != _AT:
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads USD prim path. Assumes the cursor is on the opening <.
func read_path() -> String:
	_cursor += 1
	var start_pos: int = _cursor
	
	while _cursor < _length and _source.unicode_at(_cursor) != _GREATER:
		_cursor += 1
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	_cursor += 1
	return text

## Reads an int or float. Returns an [int] if the literal has no `.`/`e`/`E`,
## otherwise a [float]. Whether it is a float is decided while scanning, so the
## literal is not walked a second time to find out.
func read_number() -> Variant:
	var start_pos: int = _cursor
	var is_float: bool = false
	
	var first: int = _source.unicode_at(_cursor)
	if first == _PLUS or first == _MINUS:
		_cursor += 1
	
	while _cursor < _length:
		var code: int = _source.unicode_at(_cursor)
		if code >= _ZERO and code <= _NINE:
			_cursor += 1
		elif code == _DOT or code == _LOWER_E or code == _UPPER_E:
			is_float = true
			_cursor += 1
		elif code == _MINUS or code == _PLUS:
			# Only valid here as an exponent sign, e.g. 1.5E-07.
			_cursor += 1
		else:
			break
	
	var raw: String = _source.substr(start_pos, _cursor - start_pos)
	return float(raw) if is_float else int(raw)

## Reads an identifier: starts with a letter or `_`, followed by letters,
## digits, `:` or `.`. Appends `[]` if present.
func read_ident() -> String:
	var start_pos: int = _cursor
	while _cursor < _length:
		var code: int = _source.unicode_at(_cursor)
		if is_ident_start(code) or code == _COLON or code == _DOT:
			_cursor += 1
		elif _cursor > start_pos and code >= _ZERO and code <= _NINE:
			_cursor += 1
		else:
			break
	
	var text: String = _source.substr(start_pos, _cursor - start_pos)
	if _cursor + 1 < _length \
			and _source.unicode_at(_cursor) == _BRACKET_OPEN \
			and _source.unicode_at(_cursor + 1) == _BRACKET_CLOSE:
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
