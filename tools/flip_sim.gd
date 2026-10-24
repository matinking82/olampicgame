extends SceneTree
## Balance check for Flip Four's CPU: each round's CPU plays the next
## round's (and a random mover), and its moves are timed. From the
## "My project" folder:
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --script res://tools/flip_sim.gd

const R := preload("res://flip/flip_rules.gd")
const GAMES := 4


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in range(1, 8):
		var shape := FlipMatch.board_shape(r)
		var cfg := FlipMatch.cpu_config(r)
		var stronger := FlipMatch.cpu_config(r + 1)
		var vs_random := 0
		var vs_next := 0
		var slowest := 0
		var total_ms := 0
		var moves := 0
		var lengths := 0
		for g in GAMES * 2:
			var b := R.new_board(shape.x, shape.y, R.make_blocks(shape.x, shape.y, FlipMatch.block_pairs(r), rng))
			var side := g % 2
			var random := g < GAMES
			var turn := 0
			var won := -1
			while won < 0 and not R.is_full(b, shape.x):
				var col: int
				if turn == side:
					var t := Time.get_ticks_msec()
					col = FlipAI.choose(b, shape.x, shape.y, turn, cfg.depth, cfg.noise, cfg.endgame, rng)
					var took := Time.get_ticks_msec() - t
					slowest = maxi(slowest, took)
					total_ms += took
					moves += 1
				elif random:
					var ms := R.moves(b, shape.x)
					col = ms[rng.randi_range(0, ms.size() - 1)]
				else:
					col = FlipAI.choose(b, shape.x, shape.y, turn, stronger.depth, stronger.noise, stronger.endgame, rng)
				R.drop(b, shape.x, shape.y, col, turn)
				lengths += 1
				turn = 1 - turn
			won = R.leader(b)
			if won == side:
				if random:
					vs_random += 1
				else:
					vs_next += 1
		print("round %d (%dx%d, depth %d, noise %.0f): beats random %d/%d, beats next round %d/%d, avg %d ms, slowest %d ms" % [
			r, shape.x, shape.y, cfg.depth, cfg.noise, vs_random, GAMES, vs_next, GAMES, total_ms / maxi(moves, 1), slowest])
	quit()
