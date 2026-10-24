extends SceneTree
## Balance check for Mine Fleet's CPU gunner: how many shots each round's
## gunner needs to sink a fleet (fewer is stronger). From "My project":
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --script res://tools/fleet_sim.gd

const R := preload("res://fleet/fleet_rules.gd")
const GAMES := 40


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for r in range(1, 8):
		var setup := FleetMatch.sea_setup(r)
		var n: int = setup.size
		var cfg := FleetMatch.cpu_config(r)
		var total := 0
		var misses := 0
		var slowest := 0
		for g in GAMES:
			var fleet := R.place_fleet(n, setup.ships, rng)
			var seen := PackedInt32Array()
			seen.resize(n * n)
			while not R.all_sunk(fleet, seen):
				var t := Time.get_ticks_msec()
				var i := FleetAI.choose(seen, R.visible_numbers(fleet, seen, n), n, R.afloat(fleet, seen), cfg, rng)
				slowest = maxi(slowest, Time.get_ticks_msec() - t)
				var shot := R.fire(fleet, seen, n, i)
				total += 1
				if not shot.hit:
					misses += 1
		print("round %d (%dx%d %s, read %.2f, blunder %.2f): %.1f shots, %.1f misses (turns) to sink, slowest %d ms" % [
			r, n, n, str(setup.ships), cfg.read, cfg.blunder, float(total) / GAMES, float(misses) / GAMES, slowest])
	quit()
