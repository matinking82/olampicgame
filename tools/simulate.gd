extends SceneTree
## Plays many runs with a bot and reports how long they last, for balancing.
##   Godot --headless --path sudoku-pop --script res://tools/simulate.gd -- --bot=smart --games=8 --seed=1
## Options: --bot=smart|random, --games=N, --seed=N (first seed), --max=N (turn cap).

## Rough time a real player spends per turn (thinking, dragging, watching),
## used to turn turn counts into minutes.
const SECONDS_PER_TURN := 5.0


func _initialize() -> void:
	var args := {"bot": "smart", "games": "8", "seed": "1", "max": "1500"}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var skill := Bot.Skill.SMART if args.bot == "smart" else Bot.Skill.RANDOM
	var rows: Array[Dictionary] = []
	print("seed  turns   min   score  lvl  blasts  pops  bestStrk  fever%  powers  L4@  L7@  L10@  ms/turn")
	for g in int(args.games):
		var seed_value := int(args.seed) + g
		var s := GameState.new(seed_value)
		s.start()
		var bot := Bot.new(skill, seed_value)
		var reached := {}
		var fever_turns := 0
		var started := Time.get_ticks_msec()
		while not s.game_over and s.turns < int(args.max):
			var before := s.turns
			if not bot.step(s):
				break
			if s.turns > before and Scoring.is_fever(s.streak):
				fever_turns += 1
			if not reached.has(s.level):
				reached[s.level] = s.turns
		var ms := float(Time.get_ticks_msec() - started) / maxi(s.turns, 1)
		var row := {
			"seed": seed_value, "turns": s.turns, "score": s.score, "level": s.level,
			"blasts": s.total_blasts, "pops": s.total_pops, "best_streak": s.best_streak,
			"fever": 100.0 * fever_turns / maxi(s.turns, 1), "powers": bot.powers_used,
		}
		rows.append(row)
		print("%4d  %5d  %4.1f  %6d  %3d  %6d  %4d  %8d  %5.1f%%  %6d  %3s  %3s  %4s  %7.0f" % [
			seed_value, s.turns, s.turns * SECONDS_PER_TURN / 60.0, s.score, s.level, s.total_blasts,
			s.total_pops, s.best_streak, row.fever, bot.powers_used,
			str(reached.get(4, "-")), str(reached.get(7, "-")), str(reached.get(10, "-")), ms])
	_summary(rows)
	quit()


func _summary(rows: Array[Dictionary]) -> void:
	for key: String in ["turns", "score", "level", "blasts", "fever"]:
		var values: Array = rows.map(func(r: Dictionary) -> float: return float(r[key]))
		values.sort()
		var mean: float = values.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / values.size()
		print("%-7s  min %8.1f  median %8.1f  mean %8.1f  max %8.1f" % [key, values[0], values[values.size() / 2], mean, values.back()])
	var turns: Array = rows.map(func(r: Dictionary) -> float: return float(r.turns))
	turns.sort()
	print("median run ~%.1f min at %.0f s per turn" % [turns[turns.size() / 2] * SECONDS_PER_TURN / 60.0, SECONDS_PER_TURN])
