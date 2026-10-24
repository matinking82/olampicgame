extends "res://tests/test_case.gd"


func _play(rows: Array, piece: Piece, origin: Vector2i) -> Dictionary:
	var b := Board.from_rows(rows)
	var cells := Rules.place(b, piece, origin)
	return {"board": b, "steps": Rules.resolve(b, cells)}


func test_can_place() -> void:
	var b := Board.from_rows(["1........"])
	var p := domino(2, 3)
	check(not Rules.can_place(b, p, v(0, 0)), "occupied cell")
	check(Rules.can_place(b, p, v(1, 0)), "free cells")
	check(not Rules.can_place(b, p, v(8, 0)), "off the edge")
	check(not Rules.can_place(b, p, v(-1, 0)), "negative")


func test_pair_does_not_pop() -> void:
	var r := _play(["3........"], mono(3), v(1, 0))
	check(r.steps.is_empty(), "no steps")
	check_eq(r.board.get_cell(v(0, 0)), 3, "tile stays")


func test_three_in_a_row_merge_up_where_placed() -> void:
	var r := _play(["33......."], mono(3), v(2, 0))
	var b: Board = r.board
	check_eq(r.steps.size(), 1, "steps")
	check_eq(b.get_cell(v(2, 0)), 4, "merged tile")
	check_eq(b.get_cell(v(0, 0)), Board.EMPTY, "left")
	check_eq(b.get_cell(v(1, 0)), Board.EMPTY, "middle")
	check_eq(r.steps[0].pops[0].digit, 3, "popped digit")
	check_eq(r.steps[0].pops[0].anchor, v(2, 0), "anchor")


func test_bent_group_pops() -> void:
	var r := _play(["3........", "3........"], mono(3), v(1, 1))
	check_eq(r.board.get_cell(v(1, 1)), 4, "merged tile")
	check_eq(r.board.count_tiles(), 1, "only the merged tile left")


func test_merge_cascades() -> void:
	# Three 3s make a 4 next to two 4s, which then make a 5.
	var r := _play(["33.44...."], mono(3), v(2, 0))
	check_eq(r.steps.size(), 2, "two steps")
	check_eq(r.board.get_cell(v(2, 0)), 5, "final tile")
	check_eq(r.board.count_tiles(), 1, "everything else popped")
	check_eq(r.steps[1].depth, 1, "second step depth")


func test_three_nines_make_a_star() -> void:
	var r := _play(["99.......", "12......."], mono(9), v(2, 0))
	var b: Board = r.board
	check_eq(r.steps[0].pops[0].result, Rules.STAR, "star")
	check_eq(b.get_cell(v(2, 0)), Board.EMPTY, "no tile left by a star")
	check_eq(b.get_cell(v(1, 1)), Board.EMPTY, "star clears around it")
	check_eq(b.get_cell(v(0, 1)), 1, "outside the 3x3 survives")


func test_sudoku_row_blasts() -> void:
	var r := _play(["12345678."], mono(9), v(8, 0))
	check_eq(r.steps.size(), 1, "steps")
	check_eq(r.steps[0].units, [0] as Array[int], "row 1 blasted")
	check_eq(r.board.count_tiles(), 0, "row cleared")


func test_jammed_row_does_not_clear() -> void:
	var r := _play(["12345678."], mono(1), v(8, 0))
	check(r.steps.is_empty(), "no steps")
	check_eq(r.board.unit_state(0), Board.UnitState.JAMMED, "jammed")
	check_eq(r.board.count_tiles(), 9, "tiles stay")


func test_blast_and_pop_in_the_same_step() -> void:
	var r := _play(["1234567.9", ".......8.", ".......8."], mono(8), v(7, 0))
	var b: Board = r.board
	check_eq(r.steps.size(), 1, "one step")
	check_eq(r.steps[0].units, [0] as Array[int], "row blasted")
	check_eq(r.steps[0].pops.size(), 1, "8s popped")
	check_eq(b.get_cell(v(7, 0)), 9, "merged 9 left where the 8 went")
	check_eq(b.count_tiles(), 1, "everything else cleared")


func test_two_units_at_once() -> void:
	# The last cell finishes both row 1 and column 1.
	var r := _play([".23456789", "2", "3", "4", "5", "6", "7", "8", "9"], mono(1), v(0, 0))
	check_eq(r.steps[0].units.size(), 2, "row and column")
	check_eq(r.board.count_tiles(), 0, "all cleared")


func test_wild_joins_a_group() -> void:
	var r := _play(["5*......."], mono(5), v(2, 0))
	check_eq(r.board.get_cell(v(2, 0)), 6, "merged through the wild")
	check_eq(r.board.count_tiles(), 1, "wild used up")


func test_wild_completes_a_row() -> void:
	var r := _play(["1234*678."], mono(9), v(8, 0))
	check_eq(r.steps[0].units, [0] as Array[int], "row blasted")


func test_stone_cracks_then_breaks() -> void:
	var r := _play(["33.#....."], mono(3), v(2, 0))
	check_eq(r.board.get_cell(v(3, 0)), Board.STONE_CRACKED, "cracked")
	check_cells(r.steps[0].cracked, [v(3, 0)], "reported")
	var r2 := _play(["33.%....."], mono(3), v(2, 0))
	check_eq(r2.board.get_cell(v(3, 0)), Board.EMPTY, "broken")
	check_cells(r2.steps[0].broken, [v(3, 0)], "reported")


func test_fits_with_rotation() -> void:
	var rows := [".########", ".########"]
	for i in 7:
		rows.append("#########")
	var b := Board.from_rows(rows)
	var p := domino(1, 2)
	check(not Rules.fits(b, p), "flat domino has no room")
	check(Rules.fits_any_rotation(b, p), "upright domino fits")
	b.set_cell(v(0, 0), 5)
	check(not Rules.fits_any_rotation(b, p), "full board")


func test_pop_opportunities() -> void:
	var opps := Rules.pop_opportunities(Board.from_rows(["33......."]))
	check_eq(opps[3], 3, "cells that would pop 3s")
	check_eq(opps[5], 0, "no 5s on the board")


func test_sudoku_needs() -> void:
	var needs := Rules.sudoku_needs(Board.from_rows(["12345678."]))
	check_eq(needs[9], 1, "row 1 needs a 9")
	check_eq(needs[1], 0, "nothing needs a 1")


func test_pencil_marks_for_nearly_finished_units() -> void:
	var marks := Rules.pencil_marks(Board.from_rows(["1234567.."]))
	check_eq(marks.get(v(7, 0)), [8, 9] as Array[int], "row needs 8 or 9")
	check_eq(marks.get(v(8, 0)), [8, 9] as Array[int], "both gaps")
	check(not marks.has(v(0, 1)), "no marks elsewhere")


func test_pencil_marks_intersect_units() -> void:
	# Row 1 needs 8 or 9; column 8 is 1..8 apart from its top cell, so it needs 9.
	var rows := ["1234567.."]
	for d in range(1, 9):
		rows.append(".......%d." % ((d % 8) + 1))
	var marks := Rules.pencil_marks(Board.from_rows(rows))
	check_eq(marks.get(v(7, 0)), [9] as Array[int], "only 9 fits both")


func test_no_pencil_marks_for_messy_units() -> void:
	check(Rules.pencil_marks(Board.from_rows(["1134567.."])).is_empty(), "repeat 1 means no blast")
	check(Rules.pencil_marks(Board.from_rows(["12345...."])).is_empty(), "too many gaps")


func test_cross_and_area() -> void:
	check_eq(Rules.cross(v(4, 4)).size(), 17, "row + column")
	check_eq(Rules.area_3x3(v(0, 0)).size(), 4, "corner area")
	check_eq(Rules.area_3x3(v(4, 4)).size(), 9, "centre area")
