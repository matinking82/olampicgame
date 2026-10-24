extends "res://tests/test_case.gd"

const ELL := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]


func test_four_rotations_return_the_original() -> void:
	var p := Piece.make(ELL, [1, 2, 3, 4])
	var r := p.rotated().rotated().rotated().rotated()
	check_eq(r.offsets, p.offsets, "offsets")
	check_eq(r.values, p.values, "values")


func test_rotation_is_clockwise() -> void:
	# 5 on the left, 7 on the right. Clockwise puts 5 on top, 7 below.
	var r := domino(5, 7).rotated()
	check_eq(r.extent(), v(1, 2), "now vertical")
	check_eq(r.value_at(v(0, 0)), 5, "top")
	check_eq(r.value_at(v(0, 1)), 7, "bottom")


func test_rotations_stay_normalised() -> void:
	var p := Piece.make(ELL, [1, 2, 3, 4])
	for i in 4:
		p = p.rotated()
		for o in p.offsets:
			check(o.x >= 0 and o.y >= 0, "offset %s after %d turns" % [o, i + 1])


func test_cells_at() -> void:
	check_cells(domino(1, 2).cells_at(v(3, 4)), [v(3, 4), v(4, 4)], "cells")


func test_extent() -> void:
	check_eq(Piece.make(ELL, [1, 2, 3, 4]).extent(), v(2, 3), "ell")
	check_eq(mono(1).extent(), v(1, 1), "mono")
