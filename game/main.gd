extends Node3D
## Wires the game together: builds the world, fits the camera to the
## screen, turns pointer input into drags, taps and power targets, and
## plays each turn's result on the views.
##
## Touch is handled through Godot's mouse emulation, so one code path
## serves mouse and fingers.

## How high a dragged piece floats above the board.
const LIFT := 0.9
## On touch, the dragged piece sits this far above the finger so it stays visible.
const TOUCH_OFFSET := 1.8
const DRAG_START_PX := 10.0
const CAMERA_PITCH := 60.0
## Screen space kept free for the HUD (left, top, right, bottom). Portrait
## has the power buttons along the bottom; landscape has them on the left.
const MARGIN_PORTRAIT := Vector4(20, 125, 20, 150)
const MARGIN_LANDSCAPE := Vector4(250, 70, 30, 60)
const NO_HOVER := Vector2i(-100, -100)
## Words for chain reactions, by cascade depth.
const CASCADE_WORDS := ["", "Sweet!", "Juicy!", "Delicious!", "DIVINE!", "LEGENDARY!"]
## The guided first game: a board, one tray piece, where to drop it, and
## what has to happen to move on ("pop", "blast" or "any").
const TUTORIAL := [
	{
		"text": "Drag the 3 onto the glowing cell. Three of a kind POP and merge into the next number!",
		"rows": ["", "", "", "", "33.......", "", "", "", ""],
		"piece": [[Vector2i(0, 0)], [3]], "target": Vector2i(2, 4), "goal": "pop",
	},
	{
		"text": "Fill a row, column or box with 1 to 9, each once, for a SUDOKU BLAST! Gold pencil digits show what's missing.",
		"rows": ["", "", "", "", "", "", "12345678.", "", ""],
		"piece": [[Vector2i(0, 0)], [9]], "target": Vector2i(8, 6), "goal": "blast",
	},
	{
		"text": "Tap a tray piece to turn it. Turn this one upright and drop it on the glow to pop the 5s.",
		"rows": ["", "", "", "....5....", "", "", "", "", ""],
		"piece": [[Vector2i(0, 0), Vector2i(1, 0)], [5, 5]], "target": Vector2i(4, 4), "goal": "pop",
	},
]

## The tips on the card after the last tutorial step.
const TUTORIAL_TIPS := "Clear on most turns to build a STREAK: it survives two quiet moves.
" 	+ "6 in a row starts FEVER for double points!
" 	+ "Big pops and full meters earn POWERS. Tap one, then the board.
" 	+ "The run ends when nothing in your tray fits."

enum Mode { PLAY, PAUSE, OVER, TUTORIAL }

var state: GameState
var board_view: BoardView
var tray_view: TrayView
var hud: Hud
var menus: Menus
var camera: Camera3D
var feel: Feel
var records: Records

var _mode := Mode.PLAY
var _tutorial_step := -1
var _best_before := 0

var _busy := false
var _press_slot := -1
var _press_pos := Vector2.ZERO
var _drag_slot := -1
var _drag_node: PieceNode
var _drag_touch := false
var _drag_target := Vector3.ZERO
var _hover := NO_HOVER
var _armed := -1
var _fever_on := false
var _background: ShaderMaterial


func _ready() -> void:
	_build_world()
	board_view = BoardView.new()
	add_child(board_view)
	tray_view = TrayView.new()
	add_child(tray_view)
	hud = Hud.new()
	add_child(hud)
	menus = Menus.new()
	add_child(menus)
	records = Arcade.records(Arcade.SUDOKU)
	hud.power_pressed.connect(_on_power_pressed)
	hud.pause_pressed.connect(_pause)
	board_view.impact.connect(_on_impact)
	menus.resume_pressed.connect(_resume)
	menus.restart_pressed.connect(_play_new)
	menus.menu_pressed.connect(_to_menu)
	menus.name_submitted.connect(_on_name_submitted)
	menus.tutorial_skipped.connect(_finish_tutorial)
	Settings.changed.connect(_on_settings_changed)
	board_view.show_hints = Settings.hints
	get_viewport().size_changed.connect(_layout)
	Sound.start_music(Sound.ARCADE_MUSIC)
	# The hub asks for the tutorial; first-timers get it anyway.
	if Arcade.start_tutorial or not Settings.tutorial_done:
		Arcade.start_tutorial = false
		_start_tutorial()
	else:
		_play_new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


# --- Screens and flow ----------------------------------------------------------

func _play_new() -> void:
	get_tree().paused = false
	_tutorial_step = -1
	new_game()
	_mode = Mode.PLAY
	hud.visible = true
	menus.hide_all()


func _to_menu() -> void:
	Arcade.open_hub()


func _pause() -> void:
	if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
		return
	_cancel_drag()
	_mode = Mode.PAUSE
	get_tree().paused = true
	menus.show_pause()


func _resume() -> void:
	get_tree().paused = false
	menus.hide_all()
	_mode = Mode.TUTORIAL if _tutorial_step >= 0 else Mode.PLAY
	if _mode == Mode.TUTORIAL:
		menus.show_tutorial(TUTORIAL[_tutorial_step].text, _tutorial_step + 1, TUTORIAL.size())


## Drops whatever the pointer was doing: a held piece goes back to the tray.
func _cancel_drag() -> void:
	if _drag_node != null and _drag_slot >= 0:
		tray_view.return_node(_drag_slot, _drag_node)
	_drag_node = null
	_drag_slot = -1
	_press_slot = -1
	_hover = NO_HOVER
	board_view.hide_ghost()
	_disarm()


## Esc on desktop, the back button on Android.
func _back() -> void:
	match _mode:
		Mode.PLAY, Mode.TUTORIAL:
			if _armed >= 0:
				_disarm()
			else:
				_pause()
		_:
			menus.back()


func _on_name_submitted(player_name: String) -> void:
	var rank := records.add(player_name, state.score, state.level, state.turns)
	records.save()
	Settings.save()
	menus.show_saved(records, rank)


func _on_settings_changed() -> void:
	board_view.show_hints = Settings.hints
	board_view.update_hints(state.board)


# --- Tutorial --------------------------------------------------------------------

func _start_tutorial() -> void:
	get_tree().paused = false
	new_game()
	menus.hide_all()
	hud.visible = true
	_mode = Mode.TUTORIAL
	_tutorial_step = 0
	_load_tutorial_step()


## Puts the current step's board and piece in place and points at the target.
func _load_tutorial_step() -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	state.board = Board.from_rows(step.rows)
	state.tray = [Piece.make(step.piece[0], step.piece[1]), null, null]
	state.streak = 0
	state.misses = 0
	board_view.sync(state.board)
	board_view.show_target(step.target)
	tray_view.show_tray(state, true)
	tray_view.update_fit(state)
	hud.update(state)
	menus.show_tutorial(step.text, _tutorial_step + 1, TUTORIAL.size())


## Moves on when the move did what the step asked, otherwise tries again.
func _check_tutorial(result: Dictionary) -> void:
	var goal: String = TUTORIAL[_tutorial_step].goal
	var units := 0
	var pops := 0
	for step: Dictionary in result.get("steps", []):
		units += step.units.size()
		pops += step.pops.size()
	var done := goal == "any" or (goal == "pop" and pops > 0) or (goal == "blast" and units > 0)
	await get_tree().create_timer(0.9).timeout
	if _mode != Mode.TUTORIAL:
		return
	if not done:
		hud.toast("Try again!", Palette.TEXT)
	else:
		_tutorial_step += 1
		if _tutorial_step >= TUTORIAL.size():
			board_view.hide_target()
			menus.show_tutorial_end(TUTORIAL_TIPS)
			return
	_load_tutorial_step()


func _finish_tutorial() -> void:
	Settings.tutorial_done = true
	Settings.save()
	_tutorial_step = -1
	board_view.hide_target()
	_play_new()


func new_game(seed_value: int = 0) -> void:
	if _drag_node != null:
		_drag_node.queue_free()
		_drag_node = null
	_drag_slot = -1
	_press_slot = -1
	_armed = -1
	_busy = false
	board_view.hide_ghost()
	state = GameState.new(seed_value)
	state.start()
	board_view.sync(state.board)
	tray_view.show_tray(state, true)
	tray_view.update_fit(state)
	hud.reset(state, records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_layout()


func _process(delta: float) -> void:
	if _drag_node != null:
		var before := _drag_node.position
		_drag_node.position = before.lerp(_drag_target, 1.0 - exp(-30.0 * delta))
		# Lean into the motion like something carried, then settle.
		var velocity := (_drag_node.position - before) / maxf(delta, 0.001)
		var lean := Vector3(clampf(velocity.z * 0.03, -0.4, 0.4), 0.0, clampf(-velocity.x * 0.03, -0.4, 0.4))
		_drag_node.rotation = _drag_node.rotation.lerp(lean, 1.0 - exp(-14.0 * delta))


# --- Feel ------------------------------------------------------------------------

func _on_impact(strength: float) -> void:
	feel.impact(strength)


func _set_fever(on: bool) -> void:
	if on == _fever_on:
		return
	_fever_on = on
	board_view.set_fever(on)
	var from: float = _background.get_shader_parameter("fever") if _background.get_shader_parameter("fever") != null else 0.0
	create_tween().tween_method(func(v: float) -> void: _background.set_shader_parameter("fever", v),
		from, 1.0 if on else 0.0, 0.6)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_back()
		return
	if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.keycode == KEY_SPACE:
			_rotate_held()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_rotate_held(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position, mb.device == InputEvent.DEVICE_ID_EMULATION)
			else:
				_on_release()
	elif event is InputEventMouseMotion:
		_on_move(event.position)


func _on_press(pos: Vector2, touch: bool) -> void:
	if _busy or state.game_over:
		return
	var ground := _pointer_on_plane(pos, 0.0)
	if _armed >= 0:
		var cell := board_view.world_to_cell(ground)
		if Board.in_bounds(cell):
			_use_power(_armed, cell)
		else:
			_disarm()
		return
	var slot := tray_view.slot_at(ground)
	if slot >= 0 and state.tray[slot] != null:
		_press_slot = slot
		_press_pos = pos
		_drag_touch = touch


func _on_move(pos: Vector2) -> void:
	if _press_slot >= 0 and _drag_slot < 0 and pos.distance_to(_press_pos) > DRAG_START_PX:
		_start_drag(_press_slot)
	if _drag_slot >= 0:
		_drag_to(pos)


func _on_release() -> void:
	if _drag_slot >= 0:
		_drop()
	elif _press_slot >= 0:
		_rotate_slot(_press_slot)
	_press_slot = -1


## R, Space or right-click: rotates the dragged piece, or the tray piece
## under the pointer when nothing is being dragged.
func _rotate_held(pos: Variant = null) -> void:
	if _busy:
		return
	if _drag_slot >= 0:
		Sound.play("rotate", 1.0, 0.0, 0.08)
		state.rotate(_drag_slot)
		var old := _drag_node
		_drag_node = PieceNode.new(state.piece(_drag_slot))
		add_child(_drag_node)
		_drag_node.global_transform = old.global_transform
		old.queue_free()
		_hover = NO_HOVER
		_drag_to(get_viewport().get_mouse_position())
	elif pos != null:
		var slot := tray_view.slot_at(_pointer_on_plane(pos, 0.0))
		if slot >= 0 and state.tray[slot] != null:
			_rotate_slot(slot)


func _rotate_slot(slot: int) -> void:
	Sound.play("rotate", 1.0, 0.0, 0.08)
	state.rotate(slot)
	tray_view.spin_slot(slot, state.piece(slot))
	tray_view.update_fit(state)


# --- Dragging ----------------------------------------------------------------

func _start_drag(slot: int) -> void:
	Sound.play("pickup", 1.0, 0.0, 0.05)
	_drag_slot = slot
	_drag_node = tray_view.take_node(slot)
	_drag_target = _drag_node.position
	_drag_node.create_tween().tween_property(_drag_node, "scale", Vector3.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover = NO_HOVER


func _drag_to(pos: Vector2) -> void:
	var p := _pointer_on_plane(pos, LIFT)
	if _drag_touch:
		p.z -= TOUCH_OFFSET
	_drag_target = p
	var origin := board_view.world_to_cell(p + _drag_node.first_cell_offset())
	if origin != _hover:
		_hover = origin
		_refresh_ghost()


func _refresh_ghost() -> void:
	var piece := state.piece(_drag_slot)
	var on_board := piece.cells_at(_hover).all(func(c: Vector2i) -> bool: return Board.in_bounds(c))
	if not on_board:
		board_view.hide_ghost()
		hud.hint("")
		return
	var valid := state.can_place(_drag_slot, _hover)
	var preview := state.preview(_drag_slot, _hover) if valid else {}
	board_view.show_ghost(piece, _hover, valid, preview)
	hud.hint(_describe(preview))


func _drop() -> void:
	var slot := _drag_slot
	var node := _drag_node
	_drag_slot = -1
	_drag_node = null
	board_view.hide_ghost()
	hud.hint("")
	if state.can_place(slot, _hover):
		node.queue_free()
		await _play_turn(state.place(slot, _hover))
	else:
		tray_view.return_node(slot, node)
		Sound.play("invalid")
		_on_impact(0.15)
	_hover = NO_HOVER


## A short line under the board saying what the hovered drop will do.
func _describe(preview: Dictionary) -> String:
	if preview.is_empty() or preview.steps.is_empty():
		return ""
	var units := 0
	var pops := 0
	for step: Dictionary in preview.steps:
		units += step.units.size()
		pops += step.pops.size()
	var parts: Array[String] = []
	if units > 0:
		parts.append("SUDOKU x%d" % units if units > 1 else "SUDOKU")
	if pops > 0:
		parts.append("POP x%d" % pops if pops > 1 else "POP")
	if preview.steps.size() > 1:
		parts.append("CASCADE x%d" % preview.steps.size())
	return "  +  ".join(parts) + "!"


# --- Turns and powers --------------------------------------------------------

func _play_turn(result: Dictionary) -> void:
	_busy = true
	# Each clearing turn in a streak starts the note ladder one step higher.
	board_view.note_base = clampi(result.streak - 1, 0, 6)
	await board_view.animate_place(result.cells, result.values)
	for step: Dictionary in result.steps:
		_announce_step(step)
		await board_view.animate_step(step)
	if result.points > 0:
		var color := Palette.HOT if result.fever else Palette.GOLD
		var size := 90 + mini(result.points, 2000) / 18
		board_view.float_text("+%d" % result.points, result.cells[0], color, size)
	if result.stone != GameState.NO_CELL:
		await board_view.drop_stone(result.stone)
	if result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
		Sound.duck(5.0, 0.8)
	elif result.fever and not result.steps.is_empty():
		hud.toast("FEVER x%s" % Hud.fmt_mult(result.multiplier), Palette.HOT)
	_set_fever(result.fever)
	if result.dealt:
		tray_view.show_tray(state, true)
	_finish_move(result)


## Picks the combo word for a step: Sudoku blasts beat stars beat chain
## reactions beat big pops. Plain 3-pops get no word, so words stay special.
func _announce_step(step: Dictionary) -> void:
	var stars := 0
	var biggest := 0
	for pop: Dictionary in step.pops:
		biggest = maxi(biggest, pop.cells.size())
		if pop.result == Rules.STAR:
			stars += 1
	var units: int = step.units.size()
	if units > 0:
		var words := ["SUDOKU!", "DOUBLE SUDOKU!!", "TRIPLE SUDOKU!!!"]
		hud.toast(words[units - 1] if units <= words.size() else "SUDOKU x%d!!!" % units, Palette.GOLD, 1.2 + 0.15 * units)
	elif stars > 0:
		hud.toast("GOLDEN STAR!", Palette.GOLD, 1.3)
	elif step.depth > 0:
		hud.toast(CASCADE_WORDS[mini(step.depth, CASCADE_WORDS.size() - 1)], Palette.HOT, 1.0 + 0.1 * step.depth)
	elif biggest >= 6:
		hud.toast("INCREDIBLE!", Palette.HOT, 1.3)
	elif biggest == 5:
		hud.toast("MEGA POP!", Palette.GOLD, 1.15)
	elif biggest == 4:
		hud.toast("Nice!", Palette.TEXT)


func _on_power_pressed(slot: int) -> void:
	if _busy or state.game_over or slot >= state.powers.slots.size():
		return
	var kind := state.powers.slots[slot]
	if not Powers.needs_target(kind):
		_use_power(slot, GameState.NO_CELL)
	elif _armed == slot:
		_disarm()
	else:
		_armed = slot
		hud.set_armed(slot)
		hud.hint(_aim_hint(kind))


func _aim_hint(kind: int) -> String:
	match kind:
		Powers.Kind.LASER:
			return "Tap a cell: clears its row and column"
		Powers.Kind.BOMB:
			return "Tap a cell: clears the 3x3 around it"
		Powers.Kind.NUKE:
			return "Tap a number: removes every tile with it"
		Powers.Kind.HAMMER:
			return "Tap a tile or stone to smash it"
	return ""


func _use_power(slot: int, cell: Vector2i) -> void:
	var kind := state.powers.slots[slot]
	var result := state.use_power(slot, cell)
	if result.is_empty():
		hud.hint("Pick a numbered tile" if kind == Powers.Kind.NUKE else "Pick a tile")
		return
	_disarm()
	_busy = true
	hud.toast(Powers.kind_name(kind).to_upper() + "!", Palette.power(kind))
	if kind == Powers.Kind.REROLL:
		Sound.play("whoosh", 1.2)
		tray_view.show_tray(state, true)
	else:
		board_view.power_fx(kind, cell, result.area)
		await board_view.animate_step({
			"depth": 0, "units": [], "pops": [],
			"cleared": result.cleared, "cracked": result.cracked, "broken": result.broken,
		})
	_finish_move(result)


func _finish_move(result: Dictionary) -> void:
	board_view.sync(state.board)
	tray_view.update_fit(state)
	hud.update(state)
	Sound.set_intensity(state.streak, Scoring.is_fever(state.streak))
	if result.perfect:
		hud.toast("PERFECT BOARD!", Palette.GOLD, 1.5)
		board_view.celebrate()
		Sound.play("perfect")
		Sound.duck(8.0, 1.2)
	for i in result.powers_earned.size():
		var kind: int = result.powers_earned[i]
		hud.toast("+ " + Powers.kind_name(kind), Palette.power(kind))
		Sound.play_later(0.12 * i, "coin")
	if result.overflow > 0:
		hud.toast("+%d BONUS" % (result.overflow * Powers.OVERFLOW_POINTS), Palette.GOLD)
		Sound.play("coin", 1.2)
	if result.level_up:
		hud.toast("LEVEL %d!" % result.level, Palette.TEXT, 1.4)
		Sound.play_later(0.15, "level_up")
		if not result.perfect:
			board_view.celebrate()
	_busy = false
	if _mode == Mode.TUTORIAL:
		_check_tutorial(result)
	elif state.game_over:
		_busy = true
		_mode = Mode.OVER
		_best_before = records.best()
		_set_fever(false)
		Sound.set_intensity(0, false)
		await board_view.animate_game_over()
		_busy = false
		_show_game_over(_best_before)
	elif state.is_stuck():
		Sound.play("alarm")
		hud.toast("LAST CHANCE!", Palette.HOT)
		hud.hint("Nothing fits. Use a power!")


func _show_game_over(best_before: int) -> void:
	var stats := "Level %d   ·   Best streak %d   ·   Biggest chain %d
Pops %d   ·   Sudoku blasts %d" % [
		state.level, state.best_streak, state.best_cascade, state.total_pops, state.total_blasts]
	menus.show_game_over("NO MOVES LEFT", state.score, stats, records, best_before)


func _disarm() -> void:
	_armed = -1
	hud.set_armed(-1)
	hud.hint("")


# --- World and camera --------------------------------------------------------

func _build_world() -> void:
	var made := Stage.build(self)
	camera = made.camera
	_background = made.background
	feel = Feel.new(camera)
	add_child(feel)


## Portrait screens put the tray under the board, landscape beside it; then
## the camera backs off just far enough for everything to fit.
func _layout() -> void:
	var portrait := Stage.fit_ui(get_window())
	var size := get_viewport().get_visible_rect().size
	tray_view.set_vertical(not portrait)
	hud.set_landscape(not portrait)
	var lo := Vector3(-5, 0, -5)
	var hi: Vector3
	var m := MARGIN_PORTRAIT if portrait else MARGIN_LANDSCAPE
	if portrait:
		tray_view.position = Vector3(0, 0, 7.3)
		hi = Vector3(5, 0.5, 8.9)
	else:
		tray_view.position = Vector3(7.5, 0, 0)
		hi = Vector3(9.1, 0.5, 5)
	var free := Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)
	_fit_camera(lo, hi, free, size)


func _fit_camera(lo: Vector3, hi: Vector3, free: Rect2, size: Vector2) -> void:
	Stage.fit_camera(camera, lo, hi, free, size, CAMERA_PITCH)


func _pointer_on_plane(screen: Vector2, height: float) -> Vector3:
	return Stage.pointer_on_plane(camera, screen, height)


# --- Developer helpers (used by tools/dev_shot.gd) ---------------------------

## Plays moves through the normal animated path, preferring clears.
func debug_autoplay(moves: int) -> void:
	for i in moves:
		if state.game_over:
			return
		var move := _debug_best_move()
		if move.is_empty():
			if state.powers.slots.is_empty():
				return
			# Stuck: fire the first power at the numbered tile nearest the middle.
			var target := Vector2i(4, 4)
			var best := 1000
			for cell_index in state.board.cells.size():
				var c := Board.cell_at_index(cell_index)
				var dist := (c - Vector2i(4, 4)).length_squared()
				if Board.is_digit(state.board.cells[cell_index]) and dist < best:
					best = dist
					target = c
			await _use_power(0, target)
			while _busy:
				await get_tree().process_frame
			continue
		for r in move.rot:
			state.rotate(move.slot)
		tray_view.set_slot(move.slot, null)
		await _play_turn(state.place(move.slot, move.origin))
	while _busy:
		await get_tree().process_frame


## Holds the best-looking move over the board, as if mid-drag.
func debug_hover() -> void:
	var move := _debug_best_move()
	if move.is_empty():
		return
	for r in move.rot:
		state.rotate(move.slot)
	tray_view.set_slot(move.slot, state.piece(move.slot))
	_start_drag(move.slot)
	_drag_node.scale = Vector3.ONE
	_drag_target = board_view.cell_to_world(move.origin) - _drag_node.first_cell_offset() + Vector3(0, LIFT, 0)
	_drag_node.position = _drag_target
	_hover = move.origin
	_refresh_ghost()


## Sets up a move that finishes row 5 and pops three 5s in the same step,
## then starts playing it without waiting, so frames can be grabbed mid-effect.
func debug_blast() -> void:
	state.board = Board.from_rows(["", "", "", "....5....", "1234.6789", "....5....", "...44...."])
	state.tray = [Piece.make([Vector2i.ZERO], [5]), Piece.make([Vector2i.ZERO], [1]), null]
	state.streak = 4
	board_view.sync(state.board)
	tray_view.show_tray(state, false)
	_play_turn(state.place(0, Vector2i(4, 4)))


## A board showing the hints: a row one blast away (pencil marks), a
## column needing one digit, and a jammed row.
func debug_hints() -> void:
	state.board = Board.from_rows([
		"1234567..", "........2", "........3", "........4", "........5",
		"........6", "........7", "112345689", "........1",
	])
	state.streak = 3
	state.misses = 1
	board_view.sync(state.board)
	hud.update(state)


## Fills the board with one of every tile type for checking the art.
func debug_showcase() -> void:
	state.board = Board.from_rows([
		"", "", "123456789", "", ".*.#.%...", "", "987654321",
	])
	board_view.sync(state.board)


## Frames four candy tiles close up with no UI, for rendering the app icon.
func debug_icon() -> void:
	hud.visible = false
	menus.hide_all()
	state.board = Board.from_rows(["", "", "", "...95", "...37"])
	board_view.show_hints = false
	board_view.sync(state.board)
	tray_view.visible = false
	get_viewport().size_changed.disconnect(_layout)
	var size := get_viewport().get_visible_rect().size
	var lo := board_view.cell_to_world(Vector2i(3, 3)) - Vector3(0.62, 0, 0.62)
	var hi := board_view.cell_to_world(Vector2i(4, 4)) + Vector3(0.62, 0.45, 0.62)
	_fit_camera(lo, hi, Rect2(Vector2.ZERO, size), size)


func debug_game_over() -> void:
	_mode = Mode.OVER
	_show_game_over(records.best())


func debug_summary() -> String:
	return "score %d  turns %d" % [state.score, state.turns]


## Leaves the main menu straight into a run, for the dev tools.
func debug_enter_play() -> void:
	Settings.tutorial_done = true
	_play_new()


## Opens one screen for a screenshot: settings, pause, tutorial or tutorial_end.
func debug_page(page: String) -> void:
	match page:
		"settings":
			menus.show_settings()
		"pause":
			_play_new()
			_pause()
		"tutorial":
			_start_tutorial()
		"tutorial_end":
			menus.show_tutorial_end(TUTORIAL_TIPS)


## Plays one move through real input events: taps to rotate, then
## presses, drags and releases. Prints whether each part worked.
func debug_drag() -> void:
	var move := _debug_best_move()
	if move.is_empty():
		print("debug_drag: no move")
		return
	var slot: int = move.slot
	var slot_screen := camera.unproject_position(tray_view.to_global(tray_view.slot_local(slot)))
	# Four taps should spin the piece all the way round.
	var start := state.piece(slot).rotated()
	await _sim_click(slot_screen, true)
	await _sim_click(slot_screen, false)
	print("debug_drag: one tap rotates = ", state.piece(slot).offsets == start.offsets and state.piece(slot).values == start.values)
	for i in 3:
		await _sim_click(slot_screen, true)
		await _sim_click(slot_screen, false)
	for r in move.rot:
		var before := state.piece(slot).offsets.duplicate()
		await _sim_click(slot_screen, true)
		await _sim_click(slot_screen, false)
		print("debug_drag: tap rotated = ", state.piece(slot).offsets != before or state.piece(slot).extent().x == state.piece(slot).extent().y)
	var turns_before := state.turns
	await _sim_drag(slot, move.origin)
	print("debug_drag: placed = ", state.turns == turns_before + 1)


## Plays the whole tutorial through real input, rotating on the step that
## asks for it, and reports whether each step moved on.
func debug_tutorial() -> void:
	_start_tutorial()
	await get_tree().create_timer(0.6).timeout
	for i in TUTORIAL.size():
		if i == 2:
			var at := camera.unproject_position(tray_view.to_global(tray_view.slot_local(0)))
			await _sim_click(at, true)
			await _sim_click(at, false)
		await _sim_drag(0, TUTORIAL[i].target)
		await get_tree().create_timer(1.6).timeout
		print("debug_tutorial: after step %d the tutorial is on step %d" % [i + 1, _tutorial_step + 1])
	print("debug_tutorial: end card shown = ", menus.is_open())


## Presses on a tray slot, drags so the piece's first cell lands on
## `origin`, and releases, all as mouse events.
func _sim_drag(slot: int, origin: Vector2i) -> void:
	var slot_screen := camera.unproject_position(tray_view.to_global(tray_view.slot_local(slot)))
	var ext := state.piece(slot).extent()
	var offset := Vector3(-(ext.x - 1) * 0.5, 0.0, -(ext.y - 1) * 0.5)
	var target := camera.unproject_position(board_view.cell_to_world(origin) - offset + Vector3(0, LIFT, 0))
	await _sim_click(slot_screen, true)
	for i in range(1, 13):
		_sim_motion(slot_screen.lerp(target, i / 12.0))
		await get_tree().process_frame
	print("  drag: dragging = ", _drag_slot == slot, ", hover = ", _hover, ", want ", origin)
	await _sim_click(target, false)
	while _busy:
		await get_tree().process_frame


## Gives the player a Bomb, arms it like the button does, and taps the
## centre cell through real input.
func debug_bomb() -> void:
	state.powers.add(Powers.Kind.BOMB)
	hud.update(state)
	_on_power_pressed(0)
	var tiles_before := state.board.count_tiles()
	var at := camera.unproject_position(board_view.cell_to_world(Vector2i(4, 4)))
	await _sim_click(at, true)
	await _sim_click(at, false)
	while _busy:
		await get_tree().process_frame
	print("debug_bomb: used = ", state.powers.slots.is_empty(), ", tiles ", tiles_before, " -> ", state.board.count_tiles())


func _sim_click(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _to_window(at)
	e.global_position = e.position
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _sim_motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _to_window(at)
	e.global_position = e.position
	Input.parse_input_event(e)


## Viewport coordinates (what the camera uses) to window coordinates (what
## input events carry); they differ when the screen is stretched.
func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _debug_best_move() -> Dictionary:
	var best := {}
	var best_score := -1.0
	for slot in 3:
		if state.tray[slot] == null:
			continue
		for rot in 4:
			for y in Board.SIZE:
				for x in Board.SIZE:
					var pv := state.preview(slot, Vector2i(x, y))
					if pv.is_empty():
						continue
					var cleared := 0
					for step: Dictionary in pv.steps:
						cleared += step.cleared.size()
					var score := cleared * 10.0 + randf()
					if score > best_score:
						best_score = score
						best = {"slot": slot, "rot": rot, "origin": Vector2i(x, y)}
			state.rotate(slot)
	return best
