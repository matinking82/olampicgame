class_name Bot
extends RefCounted
## A computer player for balancing, playing GameState runs headless.
## RANDOM makes any legal move (a beginner). SMART scores every legal move
## by how healthy the board looks afterwards, roughly how a good player
## thinks, and uses powers when the board gets tight.

enum Skill { RANDOM, SMART }

var skill: Skill
var rng := RandomNumberGenerator.new()
var powers_used := 0


func _init(p_skill: Skill, seed_value: int) -> void:
	skill = p_skill
	rng.seed = seed_value


## Plays one turn: a placement, or a power when that's the better call.
## Returns false when there's nothing left to do.
func step(s: GameState) -> bool:
	if s.game_over:
		return false
	if skill == Skill.SMART and not s.powers.slots.is_empty():
		if (s.is_stuck() or s.board.empty_cells().size() < 18) and _use_best_power(s):
			return true
	var move := _pick_move(s)
	if move.is_empty():
		return _use_best_power(s)
	for r in move.rot:
		s.rotate(move.slot)
	s.place(move.slot, move.origin)
	return true


## Higher is better. Free space and pairs ready to pop are good; repeated
## digits inside a unit (it can never blast) and jammed units are bad;
## nearly finished clean units are good; lone holes only a single fits are bad.
static func evaluate(board: Board) -> float:
	var score := 0.0
	for i in board.cells.size():
		var v := board.cells[i]
		if v == Board.EMPTY:
			score += 1.0
			var c := Board.cell_at_index(i)
			var open := 0
			for n in Board.neighbors(c):
				if board.get_cell(n) == Board.EMPTY:
					open += 1
			if open == 0:
				score -= 2.5
		elif Board.is_stone(v):
			score -= 2.0
		elif Board.is_digit(v):
			var c := Board.cell_at_index(i)
			if c.x + 1 < Board.SIZE and board.get_cell(c + Vector2i.RIGHT) == v:
				score += 1.5
			if c.y + 1 < Board.SIZE and board.get_cell(c + Vector2i.DOWN) == v:
				score += 1.5
	for unit: Array in Board.units():
		var seen := {}
		var filled := 0
		var repeats := 0
		var blocked := false
		for c: Vector2i in unit:
			var v := board.get_cell(c)
			if Board.is_stone(v):
				blocked = true
			elif Board.is_tile(v):
				filled += 1
				if v != Board.WILD:
					if seen.has(v):
						repeats += 1
					seen[v] = true
		if repeats > 0:
			score -= 4.0 * repeats + (20.0 if filled == Board.SIZE else 0.0)
		elif not blocked:
			score += filled * filled * 0.12
	return score


func _pick_move(s: GameState) -> Dictionary:
	var best := {}
	var best_score := -INF
	var options: Array = []
	for slot in 3:
		if s.tray[slot] == null:
			continue
		for rot in 4:
			var p := s.piece(slot)
			for y in Board.SIZE:
				for x in Board.SIZE:
					var origin := Vector2i(x, y)
					if not Rules.can_place(s.board, p, origin):
						continue
					if skill == Skill.RANDOM:
						options.append({"slot": slot, "rot": rot, "origin": origin})
						continue
					var score := _score_move(s, p, origin)
					if score > best_score:
						best_score = score
						best = {"slot": slot, "rot": rot, "origin": origin}
			s.rotate(slot)
	if skill == Skill.RANDOM:
		return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else {}
	return best


func _score_move(s: GameState, p: Piece, origin: Vector2i) -> float:
	var sim := s.board.copy()
	var steps := Rules.resolve(sim, Rules.place(sim, p, origin))
	var points := 0
	for step in steps:
		points += Scoring.step_points(step)
	var score := evaluate(sim) + points * 0.02
	if not steps.is_empty():
		score += 8.0
	return score + rng.randf() * 0.01


## Picks the power and target that clear the most (stones count double,
## since only powers really deal with them). Reroll is used as-is.
func _use_best_power(s: GameState) -> bool:
	var best_slot := -1
	var best_target := GameState.NO_CELL
	var best_gain := 0.0
	for i in s.powers.slots.size():
		var kind := s.powers.slots[i]
		if kind == Powers.Kind.REROLL:
			if best_gain < 3.0:
				best_slot = i
				best_target = GameState.NO_CELL
				best_gain = 3.0
			continue
		for y in Board.SIZE:
			for x in Board.SIZE:
				var target := Vector2i(x, y)
				var gain := _power_gain(s.board, kind, target)
				if gain > best_gain:
					best_gain = gain
					best_slot = i
					best_target = target
	if best_slot < 0:
		return false
	if s.use_power(best_slot, best_target).is_empty():
		return false
	powers_used += 1
	return true


static func _power_gain(board: Board, kind: int, target: Vector2i) -> float:
	var area: Array[Vector2i] = []
	match kind:
		Powers.Kind.LASER:
			area = Rules.cross(target)
		Powers.Kind.BOMB:
			area = Rules.area_3x3(target)
		Powers.Kind.NUKE:
			var v := board.get_cell(target)
			if not Board.is_digit(v):
				return 0.0
			area = Rules.cells_with_value(board, v)
		Powers.Kind.HAMMER:
			area = [target]
	var gain := 0.0
	for c in area:
		var v := board.get_cell(c)
		if Board.is_tile(v):
			gain += 1.0
		elif Board.is_stone(v):
			gain += 2.0
	return gain
