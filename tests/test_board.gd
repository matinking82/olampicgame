extends "res://tests/test_case.gd"


func test_units_cover_every_cell_three_times() -> void:
	check_eq(Board.units().size(), 27, "unit count")
	var count := {}
	for unit: Array in Board.units():
		check_eq(unit.size(), 9, "unit size")
		for c: Vector2i in unit:
			count[c] = count.get(c, 0) + 1
	check_eq(count.size(), 81, "cells covered")
	for c: Vector2i in count:
		check_eq(count[c], 3, "units per cell %s" % c)


func test_box_layout() -> void:
	var middle: Array = Board.units()[18 + 4]
	check(middle.has(v(3, 3)) and middle.has(v(5, 5)), "box 5 is the centre box")
	check(not middle.has(v(2, 3)), "box 5 excludes column 3")
	check(Board.units()[26].has(v(8, 8)), "box 9 is bottom right")


func test_solved_row() -> void:
	var b := Board.from_rows(["123456789"])
	check_eq(b.unit_state(0), Board.UnitState.SOLVED, "row 1")
	check_eq(b.unit_state(1), Board.UnitState.INCOMPLETE, "row 2")


func test_repeated_digit_jams() -> void:
	var b := Board.from_rows(["123456788"])
	check_eq(b.unit_state(0), Board.UnitState.JAMMED, "row 1")


func test_wild_fills_a_gap() -> void:
	var b := Board.from_rows(["1234*6789"])
	check_eq(b.unit_state(0), Board.UnitState.SOLVED, "row 1")


func test_stone_blocks_a_unit() -> void:
	var b := Board.from_rows(["1234#6789"])
	check_eq(b.unit_state(0), Board.UnitState.INCOMPLETE, "row 1")


func test_column_and_box_solved() -> void:
	var b := Board.from_rows(["1", "2", "3", "4", "5", "6", "7", "8", "9"])
	check_eq(b.unit_state(9), Board.UnitState.SOLVED, "column 1")
	var box := Board.from_rows(["123", "456", "789"])
	check_eq(box.unit_state(18), Board.UnitState.SOLVED, "box 1")


func test_from_rows_symbols() -> void:
	var b := Board.from_rows(["5*#%."])
	check_eq(b.get_cell(v(0, 0)), 5, "digit")
	check_eq(b.get_cell(v(1, 0)), Board.WILD, "wild")
	check_eq(b.get_cell(v(2, 0)), Board.STONE, "stone")
	check_eq(b.get_cell(v(3, 0)), Board.STONE_CRACKED, "cracked")
	check_eq(b.get_cell(v(4, 0)), Board.EMPTY, "empty")
	check_eq(str(b).split("\n")[0], "5*#%.....", "round trip")


func test_copy_is_independent() -> void:
	var b := Board.from_rows(["1"])
	var c := b.copy()
	c.set_cell(v(0, 0), 2)
	check_eq(b.get_cell(v(0, 0)), 1, "original unchanged")
