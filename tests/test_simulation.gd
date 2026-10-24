extends "res://tests/test_case.gd"
## Plays whole runs with a random bot to catch crashes and endless loops.

const MAX_TURNS := 2000


func test_random_bot_runs_end() -> void:
	for seed_value in [1, 2, 3]:
		var s := GameState.new(seed_value)
		s.start()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		while not s.game_over and s.turns < MAX_TURNS:
			if not _random_move(s, rng) and s.use_power(0, _any_tile(s)).is_empty():
				check(false, "seed %d: stuck with a power the bot couldn't use" % seed_value)
				break
		check(s.game_over, "seed %d ended (turns %d)" % [seed_value, s.turns])
		check(s.score > 0, "seed %d scored" % seed_value)
		print("  random bot, seed %d: %d turns, %d points, level %d, best cascade %d"
			% [seed_value, s.turns, s.score, s.level, s.best_cascade])


func _random_move(s: GameState, rng: RandomNumberGenerator) -> bool:
	var moves := []
	for slot in 3:
		if s.tray[slot] == null:
			continue
		for rot in 4:
			for y in Board.SIZE:
				for x in Board.SIZE:
					if s.can_place(slot, Vector2i(x, y)):
						moves.append([slot, rot, Vector2i(x, y)])
			s.rotate(slot)
	if moves.is_empty():
		return false
	var m: Array = moves[rng.randi_range(0, moves.size() - 1)]
	for i in m[1]:
		s.rotate(m[0])
	s.place(m[0], m[2])
	return true


func _any_tile(s: GameState) -> Vector2i:
	for i in s.board.cells.size():
		if Board.is_digit(s.board.cells[i]):
			return Board.cell_at_index(i)
	return Vector2i(4, 4)
