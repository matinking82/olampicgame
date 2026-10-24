extends GameScene
## Wires Flip Four together: the rack, pointer and keyboard input (hover a
## column to preview the drop, tap to drop), turns and their animations,
## the CPU (thinking on a thread), the HINT and UNDO powers, rounds,
## hearts, the tutorial and game over.
##
## Touch goes through Godot's mouse emulation, so one code path serves
## mouse and fingers. Keys: 1-8 drop in a column, H for a hint, U to undo.

const R := preload("res://flip/flip_rules.gd")
const CAMERA_PITCH := 12.0
## Screen space kept free for the HUD (left, top, right, bottom).
const MARGIN_PORTRAIT := Vector4(12, 250, 12, 160)
const MARGIN_LANDSCAPE := Vector4(290, 175, 290, 24)
## Where the rack's top goes during the tutorial (portrait, landscape).
const TUTORIAL_TOP := Vector2(380, 290)
## The CPU takes at least this long, so its moves can be followed.
const CPU_MIN_THINK := 0.55
const HINT := 0
const UNDO := 1
## Steps: what to say, the board (top row first) and the column to drop in.
const TUTORIAL := [
	{
		"text": "You're SUN. Tap a column to DROP a disc: it falls to the lowest free hole, like Connect Four.",
		"rows": [".......", ".......", ".......", ".......", ".......", "......."], "target": 3,
	},
	{
		"text": "Like Reversi, ICE discs trapped in a line between two of yours FLIP to SUN, in any direction! Drop here to flip 2.",
		"rows": [".......", ".......", ".......", ".......", "..oo...", ".xox..."], "target": 3,
	},
	{
		"text": "FOUR IN A ROW LOCKS those discs with a gold ring: they can never flip back. Flip your way to four here!",
		"rows": [".......", ".......", ".......", ".......", ".xo....", "xoo...."], "target": 3,
	},
	{
		"text": "When the rack is full, MOST DISCS WINS. ICE leads 24 to 17... drop the last disc and turn it round!",
		"rows": ["oooxoo.", "xooxooo", "ooxxoxo", "xxooxox", "ooxoxox", "xoxxxoo"], "target": 6,
	},
]
const TUTORIAL_TIPS := "Lock your discs before the CPU flips them back.\n" \
	+ "Big flips and locks build a STREAK: 5 in a row is FEVER!\n" \
	+ "Points fill your power bar: HINT shows a strong drop, UNDO takes one back.\n" \
	+ "Win a round to go on. Lose one and it costs a heart!"

var game: FlipMatch
var board_view: FlipBoardView
var hud: VersusHud

var _hover := -1
var _thread: Thread
var _hinted := -1


func _ready() -> void:
	board_view = FlipBoardView.new()
	add_child(board_view)
	hud = VersusHud.new(["SUN  ●", "●  ICE"], FlipArt.TEAM_UI, ["HINT", "UNDO"])
	add_child(hud)
	_setup(Arcade.FLIP, Sound.FLIP_MUSIC)
	board_view.impact.connect(feel.impact)
	hud.power_pressed.connect(_on_power)
	hud.pause_pressed.connect(_pause)
	_begin()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# --- Hooks -------------------------------------------------------------------------------

func new_game(seed_value: int = 0) -> void:
	_generation += 1
	_busy = false
	_hinted = -1
	game = FlipMatch.new(seed_value, not _two_players)
	game.start()
	board_view.sync(game.board, game.w)
	board_view.hide_target()
	hud.reset(game.vs_cpu, records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_layout()
	_start_turn()


func _tutorial() -> Array:
	return TUTORIAL


func _tutorial_tips() -> String:
	return TUTORIAL_TIPS


func _load_tutorial_step(step: Dictionary) -> void:
	var b := R.from_rows(step.rows)
	game.set_board(b, String(step.rows[0]).length())
	game.turn = 0
	board_view.sync(game.board, game.w)
	_layout()
	_start_turn()
	board_view.show_target(step.target)


func _cancel() -> bool:
	if _hover >= 0:
		_set_hover(-1)
		return true
	return false


func _record() -> Array:
	return [game.scores[0], game.round, game.total_turns]


func _fever_changed(on: bool) -> void:
	board_view.set_fever(on)


func _layout() -> void:
	var box := board_view.bounds()
	var portrait := _fit(box.position, box.end, MARGIN_PORTRAIT, MARGIN_LANDSCAPE, TUTORIAL_TOP, CAMERA_PITCH)
	hud.set_landscape(not portrait)


# --- Input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif _playing() and event.keycode == KEY_H:
			_on_power(HINT)
		elif _playing() and event.keycode == KEY_U:
			_on_power(UNDO)
		elif _playing() and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_try_drop(event.keycode - KEY_1)
		return
	if not _playing():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var col := _column_at(event.position)
		if col >= 0:
			_try_drop(col)
	elif event is InputEventMouseMotion:
		_on_move(event.position)


func _can_input() -> bool:
	return not _busy and game.is_running() and not game.is_cpu_turn()


func _column_at(pos: Vector2) -> int:
	var hit: Variant = Plane(Vector3.BACK, 0.0).intersects_ray(
		camera.project_ray_origin(pos), camera.project_ray_normal(pos))
	return board_view.column_at(hit) if hit != null else -1


func _try_drop(col: int) -> void:
	if not _can_input() or col >= game.w:
		return
	if not game.can_drop(col):
		hud.hint("That column is full")
		Sound.play("invalid")
		feel.impact(0.1)
		return
	if _tutorial_step >= 0 and col != TUTORIAL[_tutorial_step].target:
		hud.hint("Drop in the column the arrow points at")
		return
	_drop(col)


## Hovering a column (mouse) previews the drop.
func _on_move(pos: Vector2) -> void:
	if not _can_input():
		return
	var col := _column_at(pos)
	if col != _hover:
		_set_hover(col if game.can_drop(col) else -1)


func _set_hover(col: int) -> void:
	_hover = col
	if col < 0:
		board_view.set_hover(-1, {}, 0)
		return
	var p := game.preview(col)
	board_view.set_hover(col, p, game.turn)
	var flips: int = p.flipped.size()
	var locks: int = p.locked.size()
	if locks > 0:
		hud.hint("Flips %d, LOCKS %d!" % [flips, locks])
	else:
		hud.hint("Flips %d" % flips if flips > 0 else "No flips here")


func _who(side: int) -> String:
	if game.vs_cpu:
		return "You" if side == 0 else "The CPU"
	return FlipArt.TEAM_NAMES[side]


# --- Turns -----------------------------------------------------------------------------------

func _start_turn() -> void:
	_hover = -1
	_hinted = -1
	_refresh()
	var side := game.turn
	_set_fever(game.is_fever(side) and (side == 0 or not game.vs_cpu))
	board_view.set_turn_color(Color(FlipArt.team_color(side), 0.5))
	if game.is_cpu_turn():
		hud.set_turn("CPU THINKING", FlipArt.team_color(1), true)
		board_view.clear_columns()
		if _mode == Mode.PLAY:
			_cpu_turn()
		return
	hud.set_turn("YOUR DROP" if game.vs_cpu else "%s'S DROP" % FlipArt.TEAM_NAMES[side], FlipArt.team_color(side))
	board_view.show_columns(game.columns(), side)
	if _tutorial_step < 0 and _mode == Mode.PLAY:
		hud.hint("Tap a column to drop a disc")


## Scores, discs, the round and the power buttons.
func _refresh() -> void:
	hud.show_scores(game.scores, [game.meter_fill(0), game.meter_fill(1)])
	hud.show_round(game.round, game.hearts, game.round_wins)
	var shown := game.turn if not game.vs_cpu else 0
	hud.show_streak(game.streak[shown], game.streak_mult(shown), game.is_fever(shown))
	var a := game.count(0)
	var b := game.count(1)
	if game.vs_cpu:
		hud.set_info("YOU %d  ·  %d CPU" % [a, b])
	else:
		hud.set_info("DISCS  %d  –  %d" % [a, b])
	var mine := _can_input()
	var side := game.turn if not game.is_cpu_turn() else 0
	var charges := game.charges[side]
	hud.style_power(HINT, "HINT  x%d" % charges, mine and game.can_hint(), VersusHud.POWER_COLOR)
	hud.powers[UNDO].visible = game.vs_cpu
	hud.style_power(UNDO, "UNDO  x%d" % charges, mine and game.can_undo(), Color("8f5bff"))


func _drop(col: int) -> void:
	_busy = true
	_set_hover(-1)
	hud.hint("")
	var result := game.drop(col)
	if result.is_empty():
		_busy = false
		return
	var generation := _generation
	board_view.note_base = clampi(game.streak[result.side] - 1, 0, 6)
	_refresh()
	await board_view.animate_drop(result)
	if generation != _generation:
		return
	_announce(result)
	await _after(result)


## Toasts, floating points and sounds for a move.
func _announce(result: Dictionary) -> void:
	var side: int = result.side
	var mine := side == 0 or not game.vs_cpu
	var flipped: int = result.flipped.size()
	var runs: int = result.runs.size()
	if runs > 0:
		var word := "LOCKED!" if runs == 1 else ("DOUBLE LOCK!" if runs == 2 else "MEGA LOCK x%d!" % runs)
		if mine:
			hud.toast(word, Palette.GOLD, 1.25 + 0.1 * mini(runs, 4))
		else:
			hud.toast("%s LOCKED A LINE" % _who(side).to_upper(), FlipArt.team_color(side), 1.1)
	elif flipped >= 4:
		hud.toast("MEGA FLIP x%d!" % flipped, Palette.HOT, 1.35)
	elif flipped >= FlipMatch.COMBO_FLIPS:
		hud.toast("FLIP x%d!" % flipped, FlipArt.team_color(side), 1.05)
	if mine and result.points > 0:
		var c := Palette.HOT if result.fever else Palette.GOLD
		board_view.float_text("+%d" % result.points, result.at, c, 90 + mini(result.points, 1500) / 15)
	if mine and result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
		Sound.duck(5.0, 0.8)
	if mine:
		Sound.set_intensity(result.streak, result.fever)
	for k in result.charges_earned:
		if mine:
			hud.toast("+ POWER", VersusHud.POWER_COLOR)
			Sound.play_later(0.12 * k, "coin")


## After a move: the round's end, or the next turn.
func _after(result: Dictionary) -> void:
	_refresh()
	if _mode == Mode.TUTORIAL:
		if result.round_over:
			await _show_count(result)
		else:
			await _wait(0.5)
		_busy = false
		if _mode == Mode.TUTORIAL:
			_advance_tutorial()
		return
	if result.round_over:
		await _round_over(result)
		return
	_busy = false
	_start_turn()


# --- The CPU --------------------------------------------------------------------------------

func _cpu_turn() -> void:
	_busy = true
	var generation := _generation
	var cfg := FlipMatch.cpu_config(game.round)
	var col: int = await _think(cfg, 1)
	if generation != _generation or col < 0:
		return
	board_view.set_hover(col, game.preview(col), 1)
	await _wait(0.3)
	if generation != _generation:
		return
	_drop(col)


## Runs the CPU's search on a thread for `side`, at least CPU_MIN_THINK long.
func _think(cfg: Dictionary, side: int) -> int:
	var started := Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_search.bind(game.board.duplicate(), game.w, game.h, side, cfg.depth, cfg.noise, cfg.endgame,
		game.rng.randi()))
	while _thread.is_alive() or get_tree().paused:
		await get_tree().process_frame
	var col: int = _thread.wait_to_finish()
	_thread = null
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	if waited < CPU_MIN_THINK:
		await _wait(CPU_MIN_THINK - waited)
	return col


static func _search(b: PackedInt32Array, w: int, h: int, side: int, depth: int, noise: float, endgame: int,
		seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return FlipAI.choose(b, w, h, side, depth, noise, endgame, rng)


# --- Rounds and the end ---------------------------------------------------------------------

## Counts the discs out and says who has more.
func _show_count(result: Dictionary) -> void:
	hud.clear_turn()
	board_view.clear_columns()
	var counts: Array = result.counts
	hud.toast("RACK FULL!", Palette.TEXT, 1.1)
	await board_view.animate_count(game.board, result.winner)
	hud.toast("%d  –  %d" % [counts[0], counts[1]], Palette.TEXT, 1.4)
	if result.winner >= 0 and (result.winner == 0 or not game.vs_cpu):
		board_view.celebrate()
		Sound.play("win")
		Sound.duck(8.0, 1.5)
	elif result.winner == 1:
		Sound.play("game_over")
	await _wait(1.2)


func _round_over(result: Dictionary) -> void:
	var generation := _generation
	await _show_count(result)
	if generation != _generation:
		return
	_set_fever(false)
	Sound.set_intensity(0, false)
	var winner: int = result.winner
	if result.draw:
		hud.toast("A DRAW!", Palette.TEXT, 1.3)
	elif game.vs_cpu and winner == 0:
		hud.toast("ROUND CLEAR!  +%s" % UI.thousands(result.round_bonus), Palette.GOLD, 1.3)
		Sound.play("level_up")
	elif game.vs_cpu:
		hud.toast("THE CPU WINS THE ROUND", FlipArt.team_color(1), 1.2)
		if not game.game_over:
			hud.toast("-1 ♥   %d LEFT" % game.hearts, Palette.HOT, 1.3)
			Sound.play("crack", 0.8)
	else:
		hud.toast("%s TAKES THE ROUND" % FlipArt.TEAM_NAMES[winner], FlipArt.team_color(winner), 1.3)
	_refresh()
	await _wait(1.6)
	if generation != _generation:
		return
	if game.game_over:
		_end_match("OUT OF HEARTS" if game.vs_cpu else "%s WINS!" % FlipArt.TEAM_NAMES[winner])
		return
	var replay := game.vs_cpu and winner != 0
	var width_before := game.w
	var blocks_before := FlipMatch.block_pairs(game.round)
	game.next_round()
	await board_view.animate_deal(game.board, game.w)
	if generation != _generation:
		return
	_layout()
	hud.toast(("ROUND %d AGAIN" if replay else "ROUND %d") % game.round, Palette.TEXT, 1.4)
	if game.w != width_before:
		hud.toast("BIGGER RACK!", Palette.GOLD, 1.2)
	elif game.vs_cpu and FlipMatch.block_pairs(game.round) > blocks_before:
		hud.toast("CANDY BLOCKS!", Palette.HOT, 1.2)
	_busy = false
	_start_turn()


func _end_match(title: String) -> void:
	_mode = Mode.OVER
	_busy = true
	hud.clear_turn()
	board_view.clear_columns()
	if game.vs_cpu:
		var stats := "Round %d   ·   Rounds won %d   ·   Best streak %d\nLines locked %d   ·   Discs flipped %d   ·   Biggest flip %d" % [
			game.round, game.rounds_won, game.best_streak, game.lines_locked, game.total_flips, game.best_flip]
		menus.show_game_over(title, game.scores[0], stats, records, records.best(), "Rd")
	else:
		var stats := "SUN %d  –  %d ICE   ·   %d rounds\nSUN %s   ·   ICE %s" % [game.round_wins[0], game.round_wins[1],
			game.round, UI.thousands(game.scores[0]), UI.thousands(game.scores[1])]
		menus.show_game_over(title, 0, stats, null, 0, "Rd", "REMATCH")


# --- Powers -----------------------------------------------------------------------------------

func _on_power(which: int) -> void:
	if not _can_input():
		return
	if _tutorial_step >= 0:
		hud.hint("Powers come later!")
		return
	if which == HINT:
		await _use_hint()
	elif game.undo():
		hud.toast("UNDO!", Color("8f5bff"), 1.1)
		Sound.play("upgrade", 0.8)
		board_view.sync(game.board, game.w)
		_start_turn()


func _use_hint() -> void:
	if not game.spend_hint():
		return
	_busy = true
	var generation := _generation
	_refresh()
	hud.hint("Thinking...")
	var col: int = await _think(FlipMatch.HINT_CONFIG, game.turn)
	if generation != _generation:
		return
	_busy = false
	if col < 0:
		return
	_hinted = col
	board_view.show_target(col)
	Sound.play("upgrade", 1.2)
	var p := game.preview(col)
	hud.hint("Try the arrow: flips %d%s" % [p.flipped.size(), ", locks %d" % p.locked.size() if p.locked.size() > 0 else ""])
	_refresh()


# --- Developer helpers (used by tools/dev_shot.gd) ------------------------------------------

func debug_summary() -> String:
	return "round %d  score %d  hearts %d  turns %d  winner %d  mode %d  discs %d-%d" % [
		game.round, game.scores[0], game.hearts, game.total_turns, game.winner, _mode, game.count(0), game.count(1)]


## Plays the player's moves with a quick CPU brain through the animated path
## (both sides with two players).
func debug_autoplay(turns: int) -> void:
	for t in turns:
		while _busy or game.is_cpu_turn():
			if game.game_over or _mode == Mode.OVER:
				break
			await get_tree().process_frame
		if game.game_over or _mode == Mode.OVER:
			break
		if not game.is_running():
			await get_tree().process_frame
			continue
		var col := FlipAI.choose(game.board, game.w, game.h, game.turn, 2, 2.0, 6, game.rng)
		if col >= 0:
			await _drop(col)
	while _busy and not (game.game_over and _mode == Mode.OVER):
		await get_tree().process_frame


func debug_round(r: int) -> void:
	game.round = r
	game.start_round()
	board_view.sync(game.board, game.w)
	_layout()
	_start_turn()


func debug_game_over() -> void:
	game.scores[0] = 18640
	game.round = 4
	game.rounds_won = 3
	game.hearts = 0
	_end_match("OUT OF HEARTS")


## Hovers the column that flips the most, so the preview shows.
func debug_hover() -> void:
	var best := -1
	var most := -1
	for col in game.columns():
		var p := game.preview(col)
		var v: int = p.flipped.size() + 10 * p.locked.size()
		if v > most:
			most = v
			best = col
	_set_hover(best)


## One drop through a real click.
func debug_drag() -> void:
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	var turns := game.total_turns
	var cols := game.columns()
	await _sim_tap_world(board_view.cell_to_world(R.landing(game.board, game.w, game.h, cols[cols.size() / 2])))
	await _idle()
	print("debug_drag: dropped = ", game.total_turns == turns + 1)


## A drop that flips into a double lock, through a click.
func debug_mate() -> void:
	game.set_board(R.from_rows([".......", ".......", "...o...", "...o...", "..oo...", "xoox..."]), 7)
	game.turn = 0
	board_view.sync(game.board, game.w)
	_start_turn()
	await _sim_tap_world(board_view.cell_to_world(R.landing(game.board, game.w, game.h, 3)))
	await _idle()
	print("debug_mate: discs ", game.count(0), "-", game.count(1), " locked ", R.count_locked(game.board, 0))


## The HINT power, then UNDO after the CPU answers.
func debug_upgrade() -> void:
	game.charges[0] = 2
	_refresh()
	await _sim_tap_button(hud.powers[HINT])
	await _idle()
	print("debug_upgrade: hint at column ", _hinted, ", charges ", game.charges[0])
	_try_drop(_hinted)
	await _idle()
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	var before := game.count(0) + game.count(1)
	await _sim_tap_button(hud.powers[UNDO])
	print("debug_upgrade: undo took discs from ", before, " to ", game.count(0) + game.count(1), ", charges ", game.charges[0])


## The tutorial played through clicks.
func debug_tutorial() -> void:
	_start_tutorial()
	await _wait(0.6)
	for k in TUTORIAL.size():
		var col: int = TUTORIAL[k].target
		await _sim_tap_world(board_view.cell_to_world(R.landing(game.board, game.w, game.h, col)))
		await _wait(0.2)
		await _idle()
		print("debug_tutorial: after step %d the tutorial is on step %d" % [k + 1, _tutorial_step + 1])
	print("debug_tutorial: end card shown = ", menus.is_open())


## The tutorial's big finish, for the screenshot.
func debug_merge() -> void:
	game.set_board(R.from_rows(TUTORIAL[3].rows), 7)
	game.turn = 0
	board_view.sync(game.board, game.w)
	await _drop(6)
