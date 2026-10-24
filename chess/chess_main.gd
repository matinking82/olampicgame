extends Node3D
## Wires Merge Mate together: the world and camera, pointer input (drag a
## piece, or tap it and tap where it goes), turns and their animations, the
## CPU thinking on a background thread, rounds, the tutorial and game over.
##
## Touch is handled through Godot's mouse emulation, so one code path
## serves mouse and fingers.

const R := preload("res://chess/chess_rules.gd")
const CAMERA_PITCH := 52.0
const DRAG_START_PX := 10.0
## How high a dragged piece floats, and how far ahead of a finger it sits.
const LIFT := 0.7
const TOUCH_OFFSET := 1.1
## Screen space kept free for the HUD (left, top, right, bottom).
const MARGIN_PORTRAIT := Vector4(12, 205, 12, 165)
const MARGIN_LANDSCAPE := Vector4(290, 150, 290, 30)
## During the tutorial the board sits lower, below the instruction card.
const TUTORIAL_TOP_PORTRAIT := 330.0
const TUTORIAL_TOP_LANDSCAPE := 270.0
## The CPU always "thinks" at least this long, so its moves don't snap.
const CPU_MIN_THINK := 0.55
## Merge Mate's guided first game: a board, the piece to drag, where to
## drop it, and what has to happen to move on.
const TUTORIAL := [
	{
		"text": "Drag your pawn onto the pawn beside it. Twins MERGE into a knight or a bishop!",
		"rows": ["....k...", "", "", "", "", "....P...", "...P....", "....K..."],
		"from": Vector2i(3, 6), "target": Vector2i(4, 5), "goal": "merge",
	},
	{
		"text": "Same tier merges again: a knight and a bishop make a ROOK. Rooks make a QUEEN, queens an EMPRESS!",
		"rows": ["....k...", "", "", "", "", "..NB....", "", "....K..."],
		"from": Vector2i(2, 5), "target": Vector2i(3, 5), "goal": "merge",
	},
	{
		"text": "Pieces move and capture like chess. Slide the rook to the top row: CHECKMATE wins the round!",
		"rows": [".......k", "......pp", "", "", "", "R.......", "", "....K..."],
		"from": Vector2i(0, 5), "target": Vector2i(0, 0), "goal": "mate",
	},
]
const TUTORIAL_TIPS := "New pieces drop onto your two home rows every turn.\n" \
	+ "Merges, captures and checks build a STREAK: 5 in a row is FEVER!\n" \
	+ "Points fill UPGRADE: tap it, then a piece, to raise it a tier for free.\n" \
	+ "Mate the CPU to clear a round. Each round it gets sharper!"

enum Mode { PLAY, PAUSE, OVER, TUTORIAL }

var game: ChessMatch
var board_view: ChessBoardView
var hud: ChessHud
var menus: Menus
var camera: Camera3D
var feel: Feel
var records: Records

var _mode := Mode.PLAY
var _tutorial_step := -1
var _background: ShaderMaterial
var _fever_on := false
var _busy := false
var _armed := false
var _selected := -1
var _targets := PackedInt32Array()
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _drag_touch := false
var _drag_world := Vector3.ZERO
var _hover := -1
var _yaw := 0.0
var _yaw_tween: Tween
var _thread: Thread
## Bumped on every new game, so a CPU move from an abandoned game is dropped.
var _generation := 0
var _two_players := false


func _ready() -> void:
	var made := Stage.build(self)
	camera = made.camera
	_background = made.background
	feel = Feel.new(camera)
	add_child(feel)
	board_view = ChessBoardView.new()
	add_child(board_view)
	hud = ChessHud.new()
	add_child(hud)
	menus = Menus.new()
	add_child(menus)
	records = Arcade.records(Arcade.CHESS)
	board_view.impact.connect(feel.impact)
	hud.upgrade_pressed.connect(_on_upgrade_pressed)
	hud.pause_pressed.connect(_pause)
	menus.resume_pressed.connect(_resume)
	menus.restart_pressed.connect(_play_new)
	menus.menu_pressed.connect(Arcade.open_hub)
	menus.name_submitted.connect(_on_name_submitted)
	menus.tutorial_skipped.connect(_finish_tutorial)
	get_viewport().size_changed.connect(_layout)
	_two_players = Arcade.two_players
	Sound.start_music(Sound.CHESS_MUSIC)
	if Arcade.start_tutorial or not Settings.chess_tutorial_done:
		Arcade.start_tutorial = false
		_start_tutorial()
	else:
		_play_new()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _process(delta: float) -> void:
	if _dragging and board_view.pieces.has(_selected):
		var node: ChessPieceNode = board_view.pieces[_selected]
		var before := node.position
		node.position = before.lerp(_drag_world, 1.0 - exp(-30.0 * delta))
		var velocity := (node.position - before) / maxf(delta, 0.001)
		var lean := Vector3(clampf(velocity.z * 0.03, -0.4, 0.4), 0.0, clampf(-velocity.x * 0.03, -0.4, 0.4))
		node.rotation = node.rotation.lerp(lean, 1.0 - exp(-14.0 * delta))


# --- Screens and flow --------------------------------------------------------------

func _play_new() -> void:
	get_tree().paused = false
	_tutorial_step = -1
	board_view.hide_target()
	menus.hide_all()
	_mode = Mode.PLAY
	new_game()


func new_game(seed_value: int = 0) -> void:
	_generation += 1
	_reset_input()
	_busy = false
	game = ChessMatch.new(seed_value, not _two_players)
	game.start()
	board_view.sync(game.cells)
	board_view.show_last_move(-1, -1)
	board_view.show_check(-1)
	hud.reset(game, records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_yaw = 0.0
	_layout()
	_start_turn()


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


func _back() -> void:
	match _mode:
		Mode.PLAY, Mode.TUTORIAL:
			if _armed:
				_disarm()
			else:
				_pause()
		_:
			menus.back()


func _on_name_submitted(player_name: String) -> void:
	var rank := records.add(player_name, game.scores[0], game.round, game.total_moves)
	records.save(Arcade.GAMES[Arcade.CHESS].records)
	Settings.save()
	menus.show_saved(records, rank)


# --- Tutorial ------------------------------------------------------------------------

func _start_tutorial() -> void:
	get_tree().paused = false
	_two_players = false
	new_game()
	menus.hide_all()
	_mode = Mode.TUTORIAL
	_tutorial_step = 0
	_layout()
	_load_tutorial_step()


func _load_tutorial_step() -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	_reset_input()
	game.start_round()
	game.cells = R.from_rows(step.rows)
	game.turn = 0
	game.spawn_chance = [0.0, 0.0]
	board_view.sync(game.cells)
	board_view.show_last_move(-1, -1)
	board_view.show_check(-1)
	board_view.show_target(R.idx(step.target.x, step.target.y))
	hud.update(game)
	hud.set_turn(game)
	menus.show_tutorial(step.text, _tutorial_step + 1, TUTORIAL.size())


func _check_tutorial(result: Dictionary) -> void:
	var goal: String = TUTORIAL[_tutorial_step].goal
	var done: bool = (goal == "merge" and result.get("kind", "") == "merge") or (goal == "mate" and result.mate)
	await get_tree().create_timer(1.1).timeout
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
	Settings.chess_tutorial_done = true
	Settings.save()
	_two_players = Arcade.two_players
	_play_new()


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_back()
		return
	if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position, event.device == InputEvent.DEVICE_ID_EMULATION)
		else:
			_on_release()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_drag()
	elif event is InputEventMouseMotion:
		_on_move(event.position)


func _can_input() -> bool:
	return not _busy and game.winner < 0 and not game.draw and not game.is_cpu_turn()


func _on_press(pos: Vector2, touch: bool) -> void:
	if not _can_input():
		return
	var i := board_view.world_to_index(Stage.pointer_on_plane(camera, pos, 0.0))
	if _armed:
		if game.can_upgrade(i):
			_use_upgrade(i)
		else:
			_disarm()
		return
	# Tap-tap: a selected piece goes where the second tap lands.
	if _selected >= 0 and _targets.has(i):
		_act(_selected, i, false)
		return
	if i >= 0 and game.cells[i] != R.EMPTY and R.side_of(game.cells[i]) == game.turn:
		if _tutorial_step >= 0 and i != R.idx(TUTORIAL[_tutorial_step].from.x, TUTORIAL[_tutorial_step].from.y):
			hud.hint("Drag the piece the arrow points at")
			return
		_select(i)
		_pressed = true
		_press_pos = pos
		_drag_touch = touch
	else:
		_deselect()


func _on_move(pos: Vector2) -> void:
	if _pressed and not _dragging and pos.distance_to(_press_pos) > DRAG_START_PX:
		_dragging = true
		Sound.play("pickup", 1.0, 0.0, 0.05)
	if not _dragging:
		return
	var p := Stage.pointer_on_plane(camera, pos, LIFT)
	if _drag_touch:
		# Keep the piece ahead of the finger, in whichever way the camera faces.
		var ahead := -camera.global_basis.z
		ahead.y = 0.0
		p += ahead.normalized() * TOUCH_OFFSET
	_drag_world = board_view.to_local(p)
	var over := board_view.world_to_index(board_view.to_global(_drag_world))
	if over != _hover:
		_hover = over
		var valid := _targets.has(over)
		board_view.set_hover(over if valid else -1)
		hud.hint(_describe(_selected, over) if valid else "")


func _on_release() -> void:
	_pressed = false
	if not _dragging:
		return
	_dragging = false
	if _targets.has(_hover):
		_act(_selected, _hover, true)
	else:
		# Not a legal square: the piece floats home and stays selected.
		var node: ChessPieceNode = board_view.pieces.get(_selected)
		if node != null:
			var tw := node.create_tween().set_parallel(true)
			tw.tween_property(node, "position", ChessBoardView.cell_to_local(_selected) + Vector3(0, ChessBoardView.LIFT, 0), 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "rotation", Vector3.ZERO, 0.18)
		if _hover >= 0 and _hover != _selected:
			Sound.play("invalid")
			feel.impact(0.12)
		board_view.set_hover(-1)
		hud.hint("")
	_hover = -1


func _select(i: int) -> void:
	if _selected == i:
		return
	_deselect()
	_selected = i
	_targets = game.targets(i)
	board_view.show_targets(i, _targets, game.cells)
	Sound.play("click", 1.3, 0.0, 0.05)
	if _targets.is_empty():
		hud.hint("That piece is stuck")


func _deselect() -> void:
	_selected = -1
	_targets = PackedInt32Array()
	board_view.clear_targets()
	hud.hint("")


func _cancel_drag() -> void:
	if _dragging and board_view.pieces.has(_selected):
		var node: ChessPieceNode = board_view.pieces[_selected]
		node.position = ChessBoardView.cell_to_local(_selected)
		node.rotation = Vector3.ZERO
	_dragging = false
	_pressed = false
	_hover = -1
	_deselect()
	_disarm()


func _reset_input() -> void:
	_dragging = false
	_pressed = false
	_hover = -1
	_selected = -1
	_targets = PackedInt32Array()
	_armed = false
	board_view.clear_targets()
	if _tutorial_step < 0:
		board_view.hide_target()
	hud.set_armed(false)
	hud.hint("")


## A line under the board saying what dropping here will do.
func _describe(from: int, to: int) -> String:
	var p := game.cells[from]
	var q := game.cells[to]
	var parts: Array[String] = []
	if R.can_merge(p, q):
		var t := R.type_of(p)
		parts.append("MERGE → " + ("KNIGHT or BISHOP" if R.TIER[t] == 1 else R.NAMES[R.merged_type(t)].to_upper()))
	elif q != R.EMPTY:
		parts.append("CAPTURE %s" % R.NAMES[R.type_of(q)].to_upper())
	elif R.type_of(p) == R.PAWN and to / R.SIZE == R.last_row(R.side_of(p)):
		parts.append("PROMOTE → QUEEN")
	if R.in_check(R.apply(game.cells, from, to), 1 - R.side_of(p)):
		parts.append("CHECK")
	return "  +  ".join(parts) + ("!" if not parts.is_empty() else "")


# --- Turns -----------------------------------------------------------------------------

func _act(from: int, to: int, dragged: bool) -> void:
	_busy = true
	_dragging = false
	_pressed = false
	_hover = -1
	_selected = -1
	_targets = PackedInt32Array()
	hud.hint("")
	board_view.set_hover(-1)
	var result := game.act(from, to)
	if result.is_empty():
		_busy = false
		return
	await _play_result(result, dragged)


func _play_result(result: Dictionary, dragged: bool) -> void:
	var generation := _generation
	board_view.note_base = clampi(game.streak[result.side] - 1, 0, 6)
	board_view.show_check(-1)
	await board_view.animate_action(result, dragged)
	if generation != _generation:
		return
	board_view.show_last_move(result.from, result.to)
	_announce(result)
	if result.spawn >= 0:
		await board_view.animate_spawn(result.spawn, result.spawn_piece)
	if generation != _generation:
		return
	await _after(result)


## Toasts, floating points and sounds for what just happened.
func _announce(result: Dictionary) -> void:
	var side: int = result.side
	var mine := side == 0 or not game.vs_cpu
	if result.kind == "merge":
		var tier: int = R.TIER[R.type_of(result.result)]
		var word: String = ChessBoardView.TIER_WORDS[tier]
		if tier == 2:
			word = R.NAMES[R.type_of(result.result)].to_upper() + "!"
		hud.toast(word, ChessArt.color(result.result), 1.0 + 0.12 * tier)
	elif result.kind == "capture" and R.TIER[R.type_of(result.target)] >= 3:
		hud.toast("%s DOWN!" % R.NAMES[R.type_of(result.target)].to_upper(), Palette.HOT, 1.2)
	if result.promoted:
		hud.toast("PROMOTED!", Palette.GOLD, 1.3)
	if result.points > 0 and mine:
		var color := Palette.HOT if result.fever else Palette.GOLD
		board_view.float_text("+%d" % result.points, result.to, color, 90 + mini(result.points, 1500) / 15)
	if mine and result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
		Sound.duck(5.0, 0.8)
	if mine:
		_set_fever(result.fever)
		Sound.set_intensity(result.streak, result.fever)
	for i in result.get("charges_earned", 0):
		if mine:
			hud.toast("+ UPGRADE", Color("b48cff"))
			Sound.play_later(0.12 * i, "coin")


## Settles the end of an action: check, mate, timeouts and whose turn is next.
func _after(result: Dictionary) -> void:
	hud.update(game)
	if result.check and not result.mate:
		board_view.show_check(R.king_square(game.cells, 1 - result.side))
		hud.toast("CHECK!", Palette.HOT if result.side == 0 or not game.vs_cpu else ChessArt.team_color(1), 1.25)
		Sound.play("check")
	if _mode == Mode.TUTORIAL:
		if result.mate:
			await board_view.animate_mate(1, R.king_square(game.cells, 1))
			hud.toast("CHECKMATE!!!", Palette.GOLD, 1.6)
			board_view.celebrate()
			Sound.play("mate")
		_busy = false
		_check_tutorial(result)
		return
	if game.winner >= 0:
		await _round_over(result)
		return
	if game.draw:
		await _draw()
		return
	if result.passed:
		var stuck := 1 - int(result.side)
		hud.toast("%s IS BOXED IN!" % ("CPU" if game.vs_cpu and stuck == 1 else ChessArt.TEAM_NAMES[stuck]), Palette.TEXT)
	_busy = false
	_start_turn()


func _start_turn() -> void:
	hud.set_turn(game)
	hud.update(game)
	board_view.set_turn_color(Color(ChessArt.team_color(game.turn), 0.5))
	var king := R.king_square(game.cells, game.turn)
	board_view.show_check(king if game.in_check(game.turn) else -1)
	if _two_players:
		_turn_camera(180.0 if game.turn == 1 else 0.0)
	if game.is_cpu_turn() and _mode == Mode.PLAY:
		_cpu_turn()


# --- The CPU -----------------------------------------------------------------------------

func _cpu_turn() -> void:
	_busy = true
	var generation := _generation
	var cfg := ChessMatch.cpu_config(game.round)
	var started := Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_think.bind(game.cells.duplicate(), cfg.depth, cfg.noise, game.rng.randi()))
	while _thread.is_alive() or get_tree().paused:
		await get_tree().process_frame
	var move: int = _thread.wait_to_finish()
	_thread = null
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	if waited < CPU_MIN_THINK:
		await get_tree().create_timer(CPU_MIN_THINK - waited).timeout
	while get_tree().paused:
		await get_tree().process_frame
	if generation != _generation or move < 0:
		return
	var result := game.act(R.move_from(move), R.move_to(move))
	if not result.is_empty():
		await _play_result(result, false)


static func _think(cells: PackedInt32Array, depth: int, noise: float, seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return ChessAI.choose(cells, 1, depth, noise, rng)


# --- Rounds and the end ----------------------------------------------------------------------

func _round_over(result: Dictionary) -> void:
	var winner := game.winner
	var loser := 1 - winner
	var generation := _generation
	if result.timeout:
		hud.toast("TIME UP!", Palette.TEXT, 1.3)
		Sound.play("alarm")
		await get_tree().create_timer(0.9).timeout
		hud.toast("%s LEADS!" % ("YOU" if winner == 0 and game.vs_cpu else ("CPU" if game.vs_cpu else ChessArt.TEAM_NAMES[winner])),
			ChessArt.team_color(winner), 1.2)
	await board_view.animate_mate(loser, R.king_square(game.cells, loser))
	if generation != _generation:
		return
	_set_fever(false)
	Sound.set_intensity(0, false)
	var player_won := winner == 0 or not game.vs_cpu
	if player_won:
		if result.mate:
			hud.toast("CHECKMATE!!!", Palette.GOLD, 1.6)
		board_view.celebrate()
		Sound.play("mate")
		Sound.duck(8.0, 1.5)
	else:
		hud.toast("CHECKMATE..." if result.mate else "OUT OF TIME", ChessArt.team_color(1), 1.3)
		Sound.play("game_over")
	await get_tree().create_timer(1.2).timeout
	if generation != _generation:
		return
	if not game.vs_cpu:
		_end_match("%s WINS!" % ChessArt.TEAM_NAMES[winner])
	elif winner == 0:
		await _next_round(result.round_bonus)
	else:
		_end_match("CHECKMATED" if result.mate else "OUT OF TIME")


func _next_round(bonus: int) -> void:
	var generation := _generation
	hud.toast("ROUND CLEAR!  +%s" % UI.thousands(bonus), Palette.GOLD, 1.3)
	Sound.play("level_up")
	hud.update(game)
	await get_tree().create_timer(1.4).timeout
	if generation != _generation:
		return
	game.next_round()
	board_view.sync(PackedInt32Array())
	board_view.show_last_move(-1, -1)
	hud.toast("ROUND %d" % game.round, Palette.TEXT, 1.4)
	# The new armies drop in one by one.
	for i in R.CELLS:
		if game.cells[i] != R.EMPTY:
			board_view.animate_spawn(i, game.cells[i])
			await get_tree().create_timer(0.07).timeout
	await get_tree().create_timer(0.4).timeout
	if generation != _generation:
		return
	_busy = false
	_start_turn()


func _draw() -> void:
	hud.toast("DRAW!", Palette.TEXT, 1.3)
	await get_tree().create_timer(1.4).timeout
	if game.vs_cpu:
		hud.toast("REPLAY ROUND %d" % game.round, Palette.TEXT, 1.2)
		game.start_round()
		board_view.sync(game.cells)
		_busy = false
		_start_turn()
	else:
		_end_match("DRAW")


func _end_match(title: String) -> void:
	_mode = Mode.OVER
	_busy = true
	hud.clear_turn()
	if game.vs_cpu:
		var stats := "Round %d   ·   Rounds won %d   ·   Best streak %d\nMerges %d   ·   Captures %d   ·   Top piece: %s" % [
			game.round, game.rounds_won, game.best_streak, game.total_merges, game.total_captures,
			["Pawn", "Pawn", "Knight", "Rook", "Queen", "Empress"][game.best_tier]]
		menus.show_game_over(title, game.scores[0], stats, records, records.best(), "Rd")
	else:
		var stats := "SUN %s   ·   ICE %s\n%d moves" % [UI.thousands(game.scores[0]), UI.thousands(game.scores[1]), game.plies]
		menus.show_game_over(title, 0, stats, null, 0, "Rd", "REMATCH")


# --- The Upgrade power ---------------------------------------------------------------------------

func _on_upgrade_pressed() -> void:
	if not _can_input() or game.charges[game.turn] <= 0:
		return
	if _armed:
		_disarm()
		return
	_deselect()
	_armed = true
	hud.set_armed(true)
	hud.update(game)
	hud.hint("Tap one of your pieces to upgrade it")
	Sound.play("click", 1.2)


func _disarm() -> void:
	if not _armed:
		return
	_armed = false
	hud.set_armed(false)
	hud.update(game)
	hud.hint("")


func _use_upgrade(at: int) -> void:
	_disarm()
	_busy = true
	var result := game.upgrade(at)
	hud.toast("UPGRADE!", Color("b48cff"), 1.2)
	await board_view.animate_upgrade(at, result.result)
	hud.update(game)
	if result.mate:
		await _round_over(result)
		return
	if result.check:
		board_view.show_check(R.king_square(game.cells, 1 - result.side))
		hud.toast("CHECK!", Palette.HOT, 1.25)
		Sound.play("check")
	_busy = false


# --- Feel and camera -------------------------------------------------------------------------------

func _set_fever(on: bool) -> void:
	if on == _fever_on:
		return
	_fever_on = on
	board_view.set_fever(on)
	var from: float = _background.get_shader_parameter("fever") if _background.get_shader_parameter("fever") != null else 0.0
	create_tween().tween_method(func(v: float) -> void: _background.set_shader_parameter("fever", v),
		from, 1.0 if on else 0.0, 0.6)


## Two players: the camera swings round to whoever moves next.
func _turn_camera(yaw: float) -> void:
	if is_equal_approx(yaw, _yaw):
		return
	if _yaw_tween:
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.tween_method(func(v: float) -> void:
		_yaw = v
		_layout(), _yaw, yaw, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _layout() -> void:
	var portrait := Stage.fit_ui(get_window())
	hud.set_landscape(not portrait)
	var size := get_viewport().get_visible_rect().size
	var m := MARGIN_PORTRAIT if portrait else MARGIN_LANDSCAPE
	if _mode == Mode.TUTORIAL:
		m.y = TUTORIAL_TOP_PORTRAIT if portrait else TUTORIAL_TOP_LANDSCAPE
	var free := Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)
	Stage.fit_camera(camera, Vector3(-4.4, 0, -4.4), Vector3(4.4, 1.2, 4.4), free, size, CAMERA_PITCH, _yaw)


# --- Developer helpers (used by tools/dev_shot.gd) ------------------------------------------------

func debug_summary() -> String:
	return "round %d  score %d  moves %d  winner %d" % [game.round, game.scores[0], game.total_moves, game.winner]


## Plays the player's side with the CPU's search through the normal
## animated path (both sides with two players).
func debug_autoplay(moves: int) -> void:
	for i in moves:
		while _busy or game.is_cpu_turn():
			if game.game_over or _mode == Mode.OVER:
				return
			await get_tree().process_frame
		if game.game_over or _mode == Mode.OVER:
			return
		var m := ChessAI.choose(game.cells, game.turn, 1, 40.0, game.rng)
		if m < 0:
			return
		await _act(R.move_from(m), R.move_to(m), false)
	while _busy:
		await get_tree().process_frame


func debug_round(r: int) -> void:
	game.round = r
	game.start_round()
	board_view.sync(game.cells)
	hud.update(game)


func debug_page(page: String) -> void:
	match page:
		"settings":
			menus.show_settings()
		"pause":
			_pause()
		"tutorial":
			_start_tutorial()
		"tutorial_end":
			menus.show_tutorial_end(TUTORIAL_TIPS)
		"versus":
			_two_players = true
			_play_new()


func debug_game_over() -> void:
	game.scores[0] = 18450
	game.round = 4
	game.rounds_won = 3
	_end_match("CHECKMATED")


## Selects a piece that has a merge and holds it over the merge square.
func debug_hover() -> void:
	var mv := _find_move("merge")
	if mv < 0:
		mv = _find_move("")
	_select(R.move_from(mv))
	_dragging = true
	_drag_world = ChessBoardView.cell_to_local(R.move_to(mv)) + Vector3(0, LIFT, 0)
	board_view.pieces[R.move_from(mv)].position = _drag_world
	_hover = R.move_to(mv)
	board_view.set_hover(_hover)
	hud.hint(_describe(R.move_from(mv), _hover))


## Sets up two rooks side by side and merges them into a queen, without waiting.
func debug_merge() -> void:
	game.cells = R.from_rows(["....k...", "pp...ppp", "", "", "", "..RR....", "PPP..PPP", "....K..."])
	game.turn = 0
	board_view.sync(game.cells)
	_act(R.idx(2, 5), R.idx(3, 5), false)


func debug_upgrade() -> void:
	game.charges[0] = 2
	hud.update(game)
	_on_upgrade_pressed()
	var at := camera.unproject_position(board_view.cell_to_world(R.idx(4, 6)))
	await _sim_click(at, true)
	await _sim_click(at, false)
	while _busy:
		await get_tree().process_frame
	print("debug_upgrade: charges left ", game.charges[0], ", piece now ", R.NAMES[R.type_of(game.cells[R.idx(4, 6)])])


## A back-rank mate in one, played through real input; the round should clear.
func debug_mate() -> void:
	game.cells = R.from_rows([".......k", "......pp", "", "", "", "R.......", "PP......", "....K..."])
	game.turn = 0
	board_view.sync(game.cells)
	await _sim_drag(R.idx(0, 5), R.idx(0, 0))
	print("debug_mate: winner ", game.winner, ", round ", game.round)


## One player move through real input: tap to select, then drag.
func debug_drag() -> void:
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	var mv := _find_move("merge")
	if mv < 0:
		mv = _find_move("")
	var moves := game.total_moves
	await _sim_drag(R.move_from(mv), R.move_to(mv))
	print("debug_drag: moved = ", game.total_moves == moves + 1)
	# Then a tap-tap move.
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	mv = _find_move("")
	moves = game.total_moves
	var a := camera.unproject_position(board_view.cell_to_world(R.move_from(mv)))
	var b := camera.unproject_position(board_view.cell_to_world(R.move_to(mv)))
	await _sim_click(a, true)
	await _sim_click(a, false)
	await _sim_click(b, true)
	await _sim_click(b, false)
	while _busy:
		await get_tree().process_frame
	print("debug_drag: tap-tap moved = ", game.total_moves == moves + 1)


func debug_tutorial() -> void:
	_start_tutorial()
	await get_tree().create_timer(0.6).timeout
	for i in TUTORIAL.size():
		var step: Dictionary = TUTORIAL[i]
		await _sim_drag(R.idx(step.from.x, step.from.y), R.idx(step.target.x, step.target.y))
		await get_tree().create_timer(2.0).timeout
		print("debug_tutorial: after step %d the tutorial is on step %d" % [i + 1, _tutorial_step + 1])
	print("debug_tutorial: end card shown = ", menus.is_open())


## A legal move for the side to move: a merge when `kind` is "merge", else any.
func _find_move(kind: String) -> int:
	for m in R.legal_moves(game.cells, game.turn):
		if kind == "" or R.can_merge(game.cells[R.move_from(m)], game.cells[R.move_to(m)]):
			return m
	return -1


func _sim_drag(from: int, to: int) -> void:
	var a := camera.unproject_position(board_view.cell_to_world(from))
	var b := camera.unproject_position(board_view.cell_to_world(to) + Vector3(0, LIFT, 0))
	await _sim_click(a, true)
	for i in range(1, 13):
		_sim_motion(a.lerp(b, i / 12.0))
		await get_tree().process_frame
	await _sim_click(b, false)
	while _busy:
		await get_tree().process_frame


func _sim_click(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = get_viewport().get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _sim_motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = get_viewport().get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)
