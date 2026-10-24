extends SceneTree
## Balance check for Code Grid: a perfect player who always checks a grid
## that fits every clue so far (a person takes more). Prints how many checks
## each level takes on average and at worst, and how long the "codes left"
## count takes. From the "My project" folder:
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --script res://tools/grid_sim.gd

const R := preload("res://grid/grid_rules.gd")
const CODES := 20


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for lv in range(1, GridMatch.LEVELS.size() + 1):
		var s := GridMatch.setup(lv)
		var total := 0
		var worst := 0
		var slowest := 0
		for k in CODES:
			var m := GridMatch.new(rng.randi())
			m.level = lv
			m.start_level()
			var used := 0
			while m.is_running() and used < 20:
				var t := Time.get_ticks_msec()
				GridMatch.count_codes(m.n, m.givens, m.clues())
				slowest = maxi(slowest, Time.get_ticks_msec() - t)
				m.grid = R.solve(m.n, m.givens, m.clues(), 1, rng).first
				m.max_checks = 99
				m.check()
				used += 1
			total += used
			worst = maxi(worst, used)
		print("level %d (%dx%d, %d givens, %d checks, par %d): %.1f checks on average, worst %d, slowest count %d ms" % [
			lv, s.n, s.n, s.givens, s.checks, s.par, float(total) / CODES, worst, slowest])
	quit()
