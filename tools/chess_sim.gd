extends SceneTree
## Balancing for Merge Mate: a stand-in player (the same search, with some
## slack) runs the CPU gauntlet until it's mated. From the "My project" folder:
##   godot --headless --path sudoku-pop --script res://tools/chess_sim.gd -- --games=4 --seed=1
## Options: --depth=N and --noise=N for the player bot, --max_rounds=N.

const R := preload("res://chess/chess_rules.gd")
## Rough seconds per player move (thinking + animation) and per CPU move.
const PLAYER_SECONDS := 7.0
const CPU_SECONDS := 2.0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var games := int(args.get("games", "4"))
	var seed_value := int(args.get("seed", "1"))
	var depth := int(args.get("depth", "2"))
	var noise := float(args.get("noise", "60"))
	var max_rounds := int(args.get("max_rounds", "12"))
	var cpu_ms := 0.0
	var cpu_calls := 0
	var rows: Array[String] = []
	var minutes: Array[float] = []
	for g in games:
		var m := ChessMatch.new(seed_value + g)
		m.start()
		var round_plies: Array[int] = []
		var draws := 0
		while not m.game_over and m.round <= max_rounds:
			if m.winner >= 0:
				round_plies.append(m.plies)
				m.next_round()
				continue
			if m.draw:
				round_plies.append(-m.plies)
				draws += 1
				m.start_round()
				continue
			var mv: int
			if m.turn == 0:
				_use_upgrades(m)
				if m.winner >= 0:
					continue
				mv = ChessAI.choose(m.cells, 0, depth, noise, m.rng)
			else:
				var cfg := ChessMatch.cpu_config(m.round)
				var t0 := Time.get_ticks_usec()
				mv = ChessAI.choose(m.cells, 1, cfg.depth, cfg.noise, m.rng)
				cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0
				cpu_calls += 1
			if mv < 0:
				break
			m.act(R.move_from(mv), R.move_to(mv))
		var mins := (m.total_moves * PLAYER_SECONDS + m.total_moves * CPU_SECONDS) / 60.0
		minutes.append(mins)
		rows.append("game %d: reached round %d, won %d, score %d, %d moves (~%.1f min), draws %d, plies per round %s, best tier %d" % [
			g, m.round, m.rounds_won, m.scores[0], m.total_moves, mins, draws, str(round_plies), m.best_tier])
		print(rows.back())
	minutes.sort()
	print("median minutes %.1f, CPU think %.0f ms avg over %d calls" % [
		minutes[minutes.size() / 2], cpu_ms / maxi(cpu_calls, 1), cpu_calls])
	quit()


## Spends charges on whichever piece looks best upgraded.
func _use_upgrades(m: ChessMatch) -> void:
	while m.charges[0] > 0:
		var best := -1
		var best_score := -ChessAI.INF
		for i in R.CELLS:
			if m.can_upgrade(i):
				var next := m.cells.duplicate()
				next[i] = R.piece(R.merged_type(R.type_of(next[i])), 0)
				var s := ChessAI.evaluate(next, 0)
				if s > best_score:
					best_score = s
					best = i
		if best < 0:
			return
		m.upgrade(best)
