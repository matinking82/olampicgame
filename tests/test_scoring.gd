extends "res://tests/test_case.gd"


func _step(depth: int, units: Array, pop_sizes: Array) -> Dictionary:
	var pops := []
	for size: int in pop_sizes:
		var cells := []
		cells.resize(size)
		pops.append({"cells": cells, "result": 4})
	return {"depth": depth, "units": units, "pops": pops}


func test_pop_points_grow_with_size() -> void:
	check_eq(Scoring.pop_points(3), 30, "pop of 3")
	check_eq(Scoring.pop_points(4), 80, "pop of 4")
	check_eq(Scoring.pop_points(5), 150, "pop of 5")


func test_multi_unit_blast() -> void:
	check_eq(Scoring.step_points(_step(0, [0], [])), 500, "one unit")
	check_eq(Scoring.step_points(_step(0, [0, 9], [])), 2000, "two units")


func test_cascade_multiplier() -> void:
	check_eq(Scoring.step_points(_step(2, [], [3])), 60, "third step doubles")


func test_streak_and_fever() -> void:
	check_eq(Scoring.streak_mult(0), 1.0, "no streak")
	check_eq(Scoring.streak_mult(1), 1.0, "first clear")
	check_eq(Scoring.streak_mult(2), 1.25, "streak 2")
	check_eq(Scoring.streak_mult(5), 2.0, "streak 5")
	check(not Scoring.is_fever(5), "no fever at 5")
	check_eq(Scoring.streak_mult(6), 4.5, "fever doubles at 6")
	check_eq(Scoring.streak_mult(40), 6.0, "capped at x3, doubled")


func test_levels_follow_turns() -> void:
	var per := Difficulty.TURNS_PER_LEVEL
	check_eq(Difficulty.level_for(0), 1, "start")
	check_eq(Difficulty.level_for(per - 1), 1, "just below 2")
	check_eq(Difficulty.level_for(per), 2, "level 2")
	check_eq(Difficulty.level_for(per * 4), 5, "level 5")
	check_eq(Difficulty.threshold(3), per * 2, "threshold")


func test_difficulty_ramps_up() -> void:
	check_eq(Difficulty.stone_every(1), 0, "no stones early")
	check(Difficulty.stone_every(20) > 0, "stones late")
	check(Difficulty.shape_weights(1).size() < Difficulty.shape_weights(20).size(), "more shapes late")
	check_eq(Difficulty.digit_mode(1), Difficulty.DigitMode.HELPFUL, "helpful early")
	check_eq(Difficulty.digit_mode(20), Difficulty.DigitMode.TOUGH, "tough late")
