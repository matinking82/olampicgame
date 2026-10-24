class_name Board
extends RefCounted
## The 9x9 Sudoku grid. Pure data with no nodes, so it is cheap to copy
## for previews and easy to test headless.

const SIZE := 9
const EMPTY := 0
const WILD := 10
const STONE := 11
const STONE_CRACKED := 12

enum UnitState { INCOMPLETE, SOLVED, JAMMED }

static var _units: Array = []

var cells := PackedInt32Array()


func _init() -> void:
	cells.resize(SIZE * SIZE)
	cells.fill(EMPTY)


static func index_of(c: Vector2i) -> int:
	return c.y * SIZE + c.x


static func cell_at_index(i: int) -> Vector2i:
	return Vector2i(i % SIZE, i / SIZE)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE


static func is_digit(v: int) -> bool:
	return v >= 1 and v <= 9


## A tile the player put down: a digit or a wild.
static func is_tile(v: int) -> bool:
	return is_digit(v) or v == WILD


static func is_stone(v: int) -> bool:
	return v == STONE or v == STONE_CRACKED


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := c + d
		if in_bounds(n):
			out.append(n)
	return out


## All 27 Sudoku units: rows are 0-8, columns 9-17, 3x3 boxes 18-26.
static func units() -> Array:
	if _units.is_empty():
		for y in SIZE:
			var row: Array[Vector2i] = []
			for x in SIZE:
				row.append(Vector2i(x, y))
			_units.append(row)
		for x in SIZE:
			var col: Array[Vector2i] = []
			for y in SIZE:
				col.append(Vector2i(x, y))
			_units.append(col)
		for b in SIZE:
			var box: Array[Vector2i] = []
			var bx := (b % 3) * 3
			var by := (b / 3) * 3
			for dy in 3:
				for dx in 3:
					box.append(Vector2i(bx + dx, by + dy))
			_units.append(box)
	return _units


static func unit_label(u: int) -> String:
	if u < 9:
		return "Row %d" % (u + 1)
	if u < 18:
		return "Column %d" % (u - 8)
	return "Box %d" % (u - 17)


func get_cell(c: Vector2i) -> int:
	return cells[index_of(c)]


func set_cell(c: Vector2i, v: int) -> void:
	cells[index_of(c)] = v


func is_empty(c: Vector2i) -> bool:
	return get_cell(c) == EMPTY


func copy() -> Board:
	var b := Board.new()
	b.cells = cells.duplicate()
	return b


func count_tiles() -> int:
	var n := 0
	for v in cells:
		if is_tile(v):
			n += 1
	return n


func empty_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in cells.size():
		if cells[i] == EMPTY:
			out.append(cell_at_index(i))
	return out


## SOLVED: full and every digit 1-9 once (wilds fill the gaps).
## JAMMED: full but with a repeated digit, so it can never blast.
func unit_state(u: int) -> UnitState:
	var seen := {}
	var repeated := false
	for c: Vector2i in units()[u]:
		var v := get_cell(c)
		if not is_tile(v):
			return UnitState.INCOMPLETE
		if v == WILD:
			continue
		if seen.has(v):
			repeated = true
		seen[v] = true
	return UnitState.JAMMED if repeated else UnitState.SOLVED


func units_in_state(state: UnitState) -> Array[int]:
	var out: Array[int] = []
	for u in units().size():
		if unit_state(u) == state:
			out.append(u)
	return out


## Builds a board from text rows, mainly for tests:
## "." empty, "1"-"9" digits, "*" wild, "#" stone, "%" cracked stone.
static func from_rows(rows: Array) -> Board:
	var b := Board.new()
	for y in mini(rows.size(), SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), SIZE):
			b.set_cell(Vector2i(x, y), char_to_value(row[x]))
	return b


static func char_to_value(ch: String) -> int:
	match ch:
		"*":
			return WILD
		"#":
			return STONE
		"%":
			return STONE_CRACKED
		".", " ":
			return EMPTY
	return int(ch)


static func value_to_char(v: int) -> String:
	match v:
		EMPTY:
			return "."
		WILD:
			return "*"
		STONE:
			return "#"
		STONE_CRACKED:
			return "%"
	return str(v)


func _to_string() -> String:
	var lines := PackedStringArray()
	for y in SIZE:
		var line := ""
		for x in SIZE:
			line += value_to_char(get_cell(Vector2i(x, y)))
		lines.append(line)
	return "\n".join(lines)
