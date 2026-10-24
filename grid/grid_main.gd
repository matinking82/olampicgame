extends GameScene
## Wires Code Grid together: the board, pointer and keyboard input (pick a
## digit, tap squares to paint it, right-click to clear), checks and their
## animations, the "codes left" counter (counted on a thread), the REVEAL
## and TEST powers, levels, hearts, the tutorial and game over.
##
## Touch goes through Godot's mouse emulation, so one code path serves
## mouse and fingers. Keys: 1-6 pick a digit (and place it on the hovered
## square), Delete clears the hovered square, Enter checks.

const R := preload("res://grid/grid_rules.gd")
const CAMERA_PITCH := 62.0
## Screen space kept free for the HUD (left, top, right, bottom).
const MARGIN_PORTRAIT := Vector4(12, 330, 12, 330)
const MARGIN_LANDSCAPE := Vector4(270, 175, 280, 120)
const TUTORIAL_TOP := Vector2(400, 290)
## The tutorial's code, its givens, and the guess it starts filled with
## (0 empty): the top-left 2x2 corners swapped, and two squares to fill.
const TUTORIAL_CODE := [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]
const TUTORIAL_GIVENS := [4, 5, 6, 7, 12, 13]
const TUTORIAL_GRID := [2, 1, 3, 4, 3, 4, 1, 2, 1, 2, 4, 3, 4, 3, 0, 0]
const TUTORIAL := [
	{
		"text": "Crack the secret grid! Like Sudoku, every row and column uses each digit once. Pick a digit below and fill the two empty squares.",
		"goal": "fill", "targets": [14, 15],
	},
	{
		"text": "Now tap CHECK. Gold pegs count the RIGHT squares in each row (at its end) and each column (below it), but not which ones!",
		"goal": "check",
	},
	{
		"text": "Rows 1 and 3 and columns 1 and 2 each miss 2 pegs: their 4 corner squares are wrong. Swap those digits and CHECK to crack it!",
		"goal": "crack", "targets": [0, 1, 8, 9],
	},
]
const TUTORIAL_TIPS := "Every check counts: crack the code within the limit or it costs a heart.\n" \
	+ "CODES LEFT shows how many grids still fit everything you know.\n" \
	+ "Cracking codes in a row builds a STREAK: 4 in a row is FEVER!\n" \
	+ "Points fill your power bar: REVEAL uncovers a square, TEST says if one is right."

var game: GridMatch
var board_view: GridBoardView
var hud: GridHud

var _digit := 1
var _hover := -1
var _testing := false
var _thread: Thread
## Bumped whenever the clues change, so a stale count is ignored.
var _count_id := 0
var _count_wanted := false


func _ready() -> void:
	board_view = GridBoardView.new()
	add_child(board_view)
	hud = GridHud.new()
	add_child(hud)
	_setup(Arcade.GRID, Sound.GRID_MUSIC)
	board_view.impact.connect(feel.impact)
	hud.digit_pressed.connect(_select)
	hud.check_pressed.connect(_check)
	hud.clear_pressed.connect(_clear)
	hud.power_pressed.connect(_on_power)
	hud.card_pressed.connect(_load_card)
	hud.pause_pressed.connect(_pause)
	_begin()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	# Starts the next count once the last one is done.
	if _thread != null and not _thread.is_alive():
		var found: Dictionary = _thread.wait_to_finish()
		_thread = null
		if found.id == _count_id:
			hud.set_codes(found.count, found.complete)
			if found.count == 1 and found.complete and game.is_running() and not game.checks.is_empty():
				hud.toast("ONLY ONE CODE FITS!", Palette.GOLD, 0.8)
	if _thread == null and _count_wanted:
		_count_wanted = false
		var id := _count_id
		_thread = Thread.new()
		_thread.start(_count.bind(game.n, game.givens.duplicate(), game.clues(), id))


static func _count(n: int, shown: Dictionary, clues: Array, id: int) -> Dictionary:
	var found := GridMatch.count_codes(n, shown, clues)
	found.id = id
	return found


# --- Hooks -------------------------------------------------------------------------------

func new_game(seed_value: int = 0) -> void:
	_generation += 1
	_busy = false
	_testing = false
	game = GridMatch.new(seed_value)
	game.start()
	hud.reset(records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_show_level()


func _tutorial() -> Array:
	return TUTORIAL


func _tutorial_tips() -> String:
	return TUTORIAL_TIPS


func _load_tutorial_step(step: Dictionary) -> void:
	if _tutorial_step == 0:
		var shown := {}
		for i: int in TUTORIAL_GIVENS:
			shown[i] = TUTORIAL_CODE[i]
		game.set_code(PackedInt32Array(TUTORIAL_CODE), shown)
		game.max_checks = 6
		game.par = 3
		for i in TUTORIAL_GRID.size():
			game.place(i, TUTORIAL_GRID[i])
		_show_level()
		_select(2)
	board_view.hide_target()
	if step.has("targets"):
		board_view.show_target(step.targets[0])
	hud.update(game)


func _cancel() -> bool:
	if _testing:
		_disarm()
		return true
	return false


func _record() -> Array:
	return [game.score, game.level, game.total_checks]


func _fever_changed(on: bool) -> void:
	board_view.set_fever(on)


func _layout() -> void:
	var box := board_view.bounds()
	var portrait := _fit(box.position, box.end, MARGIN_PORTRAIT, MARGIN_LANDSCAPE, TUTORIAL_TOP, CAMERA_PITCH)
	hud.set_landscape(not portrait)
	hud.set_history(game.checks, game.n)


## Builds the board and HUD for the current level's code.
func _show_level() -> void:
	board_view.setup(game.n)
	_refresh_board()
	board_view.show_pegs({})
	hud.set_digits(game.n, clampi(_digit, 1, game.n))
	_digit = clampi(_digit, 1, game.n)
	hud.set_history(game.checks, game.n)
	hud.update(game)
	_recount()
	_layout()


func _refresh_board() -> void:
	board_view.show_grid(game.grid, game.givens, game.conflicts(), game.ruled_out,
		game.checks.back() if not game.checks.is_empty() else {})


## Asks for a fresh "codes left" count.
func _recount() -> void:
	_count_id += 1
	_count_wanted = true
	hud.set_codes(-1, false)


# --- Input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif not _playing():
			return
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var v: int = event.keycode - KEY_0
			if v <= game.n:
				_select(v)
				if _hover >= 0:
					_paint(_hover, v, false)
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			if _hover >= 0:
				_paint(_hover, 0, false)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_check()
		return
	if not _playing():
		return
	if event is InputEventMouseButton and event.pressed:
		var i := _cell_at(event.position)
		if i < 0:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _testing:
				_use_test(i)
			else:
				_paint(i, _digit, true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_paint(i, 0, false)
	elif event is InputEventMouseMotion:
		var i := _cell_at(event.position)
		if i != _hover:
			_hover = i
			board_view.set_hover(i)


func _can_input() -> bool:
	return not _busy and game.is_running()


func _cell_at(pos: Vector2) -> int:
	return board_view.world_to_index(Stage.pointer_on_plane(camera, pos, 0.0))


func _select(v: int) -> void:
	_digit = v
	hud.select_digit(v)
	Sound.note(v + 2, -6.0)


## Puts a digit on a square; `toggle` clears it when it already has that digit.
func _paint(i: int, v: int, toggle: bool) -> void:
	if not _can_input():
		return
	if game.is_given(i):
		hud.hint("That square is given: it's already right")
		Sound.play("invalid")
		return
	if _tutorial_step >= 0 and TUTORIAL[_tutorial_step].has("targets") and not TUTORIAL[_tutorial_step].targets.has(i):
		hud.hint("Change the squares the arrow shows")
		return
	if toggle and game.grid[i] == v:
		v = 0
	if not game.place(i, v):
		return
	board_view.set_tile(i, v)
	Sound.play("place" if v != 0 else "pickup", 0.9 + 0.05 * v, -2.0, 0.03)
	board_view.show_frames(game.givens, game.conflicts())
	hud.update(game)
	var blocker := game.check_blocker()
	if blocker == "A row or column repeats a digit":
		hud.hint("A row or column repeats a digit (red squares)")
	elif blocker == "":
		hud.hint("Ready: tap CHECK!")
	else:
		hud.hint("")
	if _tutorial_step >= 0:
		_tutorial_progress()


func _clear() -> void:
	if not _can_input() or _tutorial_step >= 0:
		return
	for i in game.grid.size():
		if not game.is_given(i) and game.grid[i] != 0:
			game.place(i, 0)
			board_view.set_tile(i, 0)
	Sound.play("whoosh", 1.2, -6.0)
	board_view.show_frames(game.givens, game.conflicts())
	hud.update(game)


## Loads a past check's guess back onto the board (givens stay).
func _load_card(k: int) -> void:
	if not _can_input() or _tutorial_step >= 0 or k >= game.checks.size():
		return
	var guess: PackedInt32Array = game.checks[k].guess
	for i in guess.size():
		if not game.is_given(i):
			game.place(i, guess[i])
	_refresh_board()
	board_view.show_pegs(game.checks[k])
	hud.update(game)
	hud.hint("Check #%d loaded" % (k + 1))
	Sound.play("deal")


# --- Tutorial ----------------------------------------------------------------------------------

func _tutorial_progress() -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	if step.goal == "fill":
		if game.check_blocker() == "":
			board_view.hide_target()
			_advance_tutorial()
		else:
			for i: int in step.targets:
				if game.grid[i] == 0:
					board_view.show_target(i)
					break
	elif step.goal == "crack":
		for i: int in step.targets:
			if game.grid[i] != game.code[i]:
				board_view.show_target(i)
				return
		board_view.hide_target()
		hud.hint("Now CHECK it!")


# --- Checks ------------------------------------------------------------------------------------

func _check() -> void:
	if not _can_input():
		return
	var blocker := game.check_blocker()
	if blocker != "":
		hud.hint(blocker)
		Sound.play("invalid")
		feel.impact(0.1)
		return
	if _tutorial_step >= 0 and TUTORIAL[_tutorial_step].goal == "fill":
		return
	_busy = true
	_disarm()
	board_view.set_hover(-1)
	board_view.hide_target()
	hud.hint("")
	var generation := _generation
	board_view.note_base = clampi(game.streak, 0, 6)
	var result := game.check()
	hud.update(game)
	await board_view.animate_check(result)
	if generation != _generation:
		return
	hud.set_history(game.checks, game.n)
	if result.solved:
		await _cracked(result)
		return
	var missing: int = game.n * game.n - result.hits
	hud.toast("%d RIGHT" % result.hits, Palette.GOLD if result.hits * 2 >= game.n * game.n else Palette.TEXT, 1.1)
	board_view.float_text("+%d" % result.points, Vector3(0, 0.5, 0), Palette.GOLD, 90)
	_award_charges(result)
	if result.failed:
		await _failed()
		return
	_recount()
	hud.hint("%d squares still wrong  ·  %d checks left" % [missing, game.checks_left()])
	_busy = false
	if _mode == Mode.TUTORIAL:
		if TUTORIAL[_tutorial_step].goal == "check":
			_advance_tutorial()
		else:
			_tutorial_progress()


func _award_charges(result: Dictionary) -> void:
	for k in result.charges_earned:
		hud.toast("+ POWER", GridHud.POWER_COLOR)
		Sound.play_later(0.12 * k, "coin")


func _cracked(result: Dictionary) -> void:
	var generation := _generation
	hud.clear_codes()
	await board_view.animate_crack()
	if generation != _generation:
		return
	var stars := game.stars()
	hud.toast("CRACKED!", Palette.GOLD, 1.5)
	hud.toast("★".repeat(stars) + "☆".repeat(3 - stars), Palette.GOLD, 1.4)
	if result.perfect:
		hud.toast("PAR OR BETTER!", Palette.HOT, 1.2)
	board_view.float_text("+%s" % UI.thousands(result.points), Vector3(0, 0.5, 0), Palette.HOT if result.fever else Palette.GOLD, 120)
	if result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
	_set_fever(game.is_fever())
	Sound.set_intensity(game.streak + 1, game.is_fever())
	Sound.play("level_up")
	_award_charges(result)
	hud.update(game)
	await _wait(2.4)
	if generation != _generation:
		return
	if _mode == Mode.TUTORIAL:
		_busy = false
		_advance_tutorial()
		return
	game.next_level()
	hud.toast("LEVEL %d" % game.level, Palette.TEXT, 1.4)
	if game.n != board_view.n:
		hud.toast("BIGGER GRID: %dx%d!" % [game.n, game.n], Palette.GOLD, 1.2)
	_show_level()
	Sound.play("deal")
	_busy = false


func _failed() -> void:
	var generation := _generation
	hud.clear_codes()
	hud.toast("OUT OF CHECKS!", Palette.HOT, 1.3)
	Sound.play("game_over")
	_set_fever(false)
	Sound.set_intensity(0, false)
	await board_view.animate_reveal(game.code, game.grid)
	if generation != _generation:
		return
	hud.update(game)
	await _wait(1.6)
	if generation != _generation:
		return
	if game.game_over:
		_end_match()
		return
	hud.toast("-1 ♥   %d LEFT" % game.hearts, Palette.HOT, 1.3)
	Sound.play("crack", 0.8)
	game.next_level()
	hud.toast("NEW CODE", Palette.TEXT, 1.2)
	_show_level()
	_busy = false


func _end_match() -> void:
	_mode = Mode.OVER
	_busy = true
	var stats := "Level %d   ·   Codes cracked %d   ·   Best streak %d\nAt par or better %d   ·   Checks made %d" % [
		game.level, game.levels_cracked, game.best_streak, game.perfect, game.total_checks]
	menus.show_game_over("OUT OF HEARTS", game.score, stats, records, records.best(), "Lv")


# --- Powers -----------------------------------------------------------------------------------

func _on_power(which: int) -> void:
	if not _can_input():
		return
	if _tutorial_step >= 0:
		hud.hint("Powers come later!")
		return
	if not game.can_use_power():
		return
	if which == GridHud.REVEAL:
		var i := game.reveal()
		if i < 0:
			return
		board_view.set_tile(i, game.code[i])
		board_view.show_frames(game.givens, game.conflicts())
		board_view.fx.beam(board_view.cell_to_local(i), Vector3(0.9, 3.0, 0.9), Color("3fd8f0"), 0.7)
		hud.toast("REVEAL!", Color("3fd8f0"), 1.1)
		Sound.play("upgrade", 1.1)
		hud.update(game)
		_recount()
	elif _testing:
		_disarm()
	else:
		_testing = true
		hud.hint("Tap a filled square to TEST it")
		Sound.play("click", 1.2)


func _disarm() -> void:
	if not _testing:
		return
	_testing = false
	hud.hint("")


func _use_test(i: int) -> void:
	_testing = false
	if game.grid[i] == 0 or game.is_given(i):
		hud.hint("TEST a square you've filled in")
		return
	var right := game.test(i)
	if right < 0:
		return
	var at := board_view.cell_to_local(i)
	if right == 1:
		hud.toast("RIGHT!", Palette.GOLD, 1.1)
		board_view.fx.sparks(at + Vector3(0, 0.5, 0), Palette.GOLD, 16, 3.0, 0.9)
		Sound.play("coin")
	else:
		hud.toast("WRONG!", Palette.HOT, 1.1)
		board_view.fx.sparks(at + Vector3(0, 0.5, 0), Palette.INVALID, 16, 3.0, 0.9)
		Sound.play("invalid", 0.8)
	board_view.show_frames(game.givens, game.conflicts())
	board_view.show_ruled_out(game.ruled_out)
	hud.update(game)
	hud.hint("")
	_recount()


# --- Developer helpers (used by tools/dev_shot.gd) ------------------------------------------

func debug_summary() -> String:
	return "level %d  score %d  hearts %d  checks %d  solved %s  mode %d" % [
		game.level, game.score, game.hearts, game.total_checks, str(game.solved), _mode]


## Plays checks the perfect way (a grid that fits every clue), through the
## animated path.
func debug_autoplay(turns: int) -> void:
	for t in turns:
		while _busy:
			await get_tree().process_frame
		if game.game_over or _mode == Mode.OVER:
			break
		var fit: PackedInt32Array = R.solve(game.n, game.givens, game.clues(), 1, game.rng).first
		for i in fit.size():
			if not game.is_given(i):
				game.place(i, fit[i])
		_refresh_board()
		await _check()
	while _busy and _mode != Mode.OVER:
		await get_tree().process_frame


## Fails levels on purpose until the run ends (checks a wrong grid each time).
func debug_round(r: int) -> void:
	game.level = r
	game.start_level()
	_show_level()


func debug_game_over() -> void:
	game.score = 21480
	game.level = 6
	game.levels_cracked = 5
	game.hearts = 0
	_end_match()


## A guess on the board, one check made, hovering a square.
func debug_hover() -> void:
	var fit: PackedInt32Array = R.solve(game.n, game.givens, [], 1, game.rng).first
	if fit == game.code:
		fit = R.solve(game.n, game.givens, [], 2, game.rng).first
	for i in fit.size():
		if not game.is_given(i):
			game.place(i, fit[i])
	game.check()
	game.place(0 if not game.is_given(0) else 1, 0)
	_refresh_board()
	hud.set_history(game.checks, game.n)
	hud.update(game)
	_recount()
	_hover = game.n + 1
	board_view.set_hover(_hover)
	print("debug_hover: last check ", game.checks.back().cols, " col pegs lit ", board_view._col_pegs.map(func(a: Array) -> Array: return a.map(func(p: Node3D) -> bool: return p.visible)))


## Fills the grid through clicks: pick digits on the palette, tap squares.
func debug_drag() -> void:
	var fit: PackedInt32Array = R.solve(game.n, game.givens, [], 1, game.rng).first
	for i in fit.size():
		if game.is_given(i):
			continue
		await _sim_tap_button(hud.digit_buttons[fit[i] - 1])
		await _sim_tap_world(board_view.cell_to_world(i))
	print("debug_drag: blocker '", game.check_blocker(), "'")
	await _sim_tap_button(hud.check_button)
	await _idle()
	print("debug_drag: checks ", game.checks.size())


## Cracks the code through the CHECK button.
func debug_mate() -> void:
	for i in game.code.size():
		if not game.is_given(i):
			game.place(i, game.code[i])
	_refresh_board()
	hud.update(game)
	await _sim_tap_button(hud.check_button)
	await _idle()
	print("debug_mate: level ", game.level, " score ", game.score)


## REVEAL, then TEST on a square.
func debug_upgrade() -> void:
	game.charges = 2
	hud.update(game)
	await _sim_tap_button(hud.powers[GridHud.REVEAL])
	var i := 0
	while game.is_given(i):
		i += 1
	game.place(i, game.code[i] % game.n + 1)
	_refresh_board()
	await _sim_tap_button(hud.powers[GridHud.TEST])
	await _sim_tap_world(board_view.cell_to_world(i))
	print("debug_upgrade: givens ", game.givens.size(), ", ruled out ", game.ruled_out, ", charges ", game.charges)


func debug_tutorial() -> void:
	_start_tutorial()
	await _wait(0.6)
	for pair: Array in [[2, 14], [1, 15]]:
		await _sim_tap_button(hud.digit_buttons[pair[0] - 1])
		await _sim_tap_world(board_view.cell_to_world(pair[1]))
	print("debug_tutorial: after filling the tutorial is on step %d" % (_tutorial_step + 1))
	await _sim_tap_button(hud.check_button)
	await _idle()
	print("debug_tutorial: after checking the tutorial is on step %d" % (_tutorial_step + 1))
	for pair: Array in [[1, 0], [2, 1], [2, 8], [1, 9]]:
		await _sim_tap_button(hud.digit_buttons[pair[0] - 1])
		await _sim_tap_world(board_view.cell_to_world(pair[1]))
	await _sim_tap_button(hud.check_button)
	await _wait(0.2)
	await _idle()
	print("debug_tutorial: end card shown = ", menus.is_open())


## A crack, for the screenshot.
func debug_merge() -> void:
	await debug_mate()
