extends SceneTree
## Balancing for Tic Tac Roll: a stand-in player (the CPU's own brain with
## its own settings) runs the CPU gauntlet until its hearts run out. From
## the "My project" folder:
##   godot --headless --path sudoku-pop --script res://tools/dice_sim.gd -- --games=8 --seed=1
## Options: --samples=N, --noise=N and --block=N for the player bot,
## --max_rounds=N.

const R := preload("res://dice/dice_rules.gd")
## Rough seconds per turn (rolling, thinking, animation) for each side.
const PLAYER_SECONDS := 9.0
const CPU_SECONDS := 5.0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var games := int(args.get("games", "8"))
	var seed_value := int(args.get("seed", "1"))
	var player := {"samples": int(args.get("samples", "24")), "noise": float(args.get("noise", "1.5")),
		"block": float(args.get("block", "0.85"))}
	var max_rounds := int(args.get("max_rounds", "30"))
	var think_ms := 0.0
	var thinks := 0
	var minutes: Array[float] = []
	var reached: Array[int] = []
	var round_turns: Array[int] = []
	var full_rounds := 0
	var all_rounds := 0
	for g in games:
		var m := DiceMatch.new(seed_value + g)
		m.start()
		var player_turns := 0
		var cpu_turns := 0
		var log_line := ""
		while not m.game_over and m.round <= max_rounds:
			if m.winner >= 0 or m.draw:
				all_rounds += 1
				round_turns.append(m.turns)
				if m.full_board:
					full_rounds += 1
				log_line += ("W" if m.winner == 0 else ("L" if m.winner == 1 else "D"))
				m.next_round()
				continue
			var side := m.turn
			var cfg: Dictionary = DiceMatch.cpu_config(m.round) if side == 1 else player
			if side == 0:
				player_turns += 1
			else:
				cpu_turns += 1
			m.roll()
			while true:
				var t0 := Time.get_ticks_usec()
				var d := DiceAI.decide(m.cats, m.owners, m.marks, side, m.dice, m.rolls_left, cfg, m.rng)
				think_ms += (Time.get_ticks_usec() - t0) / 1000.0
				thinks += 1
				if d.has("claim"):
					m.claim(d.claim)
					break
				if d.has("pass"):
					m.pass_turn()
					break
				m.held = d.hold
				m.roll()
		var mins := (player_turns * PLAYER_SECONDS + cpu_turns * CPU_SECONDS) / 60.0
		minutes.append(mins)
		reached.append(m.round)
		print("game %d: round %d, score %d, %.1f min, jackpots %d, steals %d, best streak %d  %s" % [
			g + 1, m.round, m.scores[0], mins, m.jackpots, m.steals, m.best_streak, log_line])
	minutes.sort()
	reached.sort()
	round_turns.sort()
	print("median round reached %d (%d-%d), median run %.1f min (%.1f-%.1f)" % [
		reached[reached.size() / 2], reached[0], reached[-1], minutes[minutes.size() / 2], minutes[0], minutes[-1]])
	print("median turns per round %d, rounds decided on a full board %d of %d" % [
		round_turns[round_turns.size() / 2], full_rounds, all_rounds])
	print("CPU think: %.1f ms per decision" % (think_ms / maxi(thinks, 1)))
	quit()
