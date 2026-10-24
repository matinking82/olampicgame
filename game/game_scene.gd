class_name GameScene
extends Node3D
## Plumbing shared by Flip Pop, Code Crack and Maze Race: the world and
## camera, the menus, pause and back, records, the step-by-step tutorial,
## Fever's backdrop, and the helpers the dev tools drive the game with.
## A game builds its board and HUD, calls _setup(), then _begin(), and
## overrides the hooks in the "To override" section.

enum Mode { PLAY, PAUSE, OVER, TUTORIAL }

var camera: Camera3D
var feel: Feel
var menus: Menus
var records: Records
var game_key := ""

var _mode := Mode.PLAY
var _tutorial_step := -1
## True while something animates or the CPU thinks; input waits.
var _busy := false
## Bumped on every new game, so animations and CPU turns from an abandoned
## game stop where they are.
var _generation := 0
var _two_players := false
var _fever_on := false
var _background: ShaderMaterial


func _setup(key: String, music: Array) -> void:
	game_key = key
	var made := Stage.build(self)
	camera = made.camera
	_background = made.background
	feel = Feel.new(camera)
	add_child(feel)
	menus = Menus.new()
	add_child(menus)
	records = Arcade.records(key)
	menus.resume_pressed.connect(_resume)
	menus.restart_pressed.connect(_play_new)
	menus.menu_pressed.connect(Arcade.open_hub)
	menus.name_submitted.connect(_on_name_submitted)
	menus.tutorial_skipped.connect(_finish_tutorial)
	get_viewport().size_changed.connect(_layout)
	_two_players = Arcade.two_players
	Sound.start_music(music)


## Starts with the tutorial the first time (or when asked for), else plays.
func _begin() -> void:
	if Arcade.start_tutorial or not Settings.tutorial_seen(game_key):
		Arcade.start_tutorial = false
		_start_tutorial()
	else:
		_play_new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


## Waits in game time; stops while the game is paused.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _playing() -> bool:
	return _mode == Mode.PLAY or _mode == Mode.TUTORIAL


# --- To override ---------------------------------------------------------------------

## Deals a fresh game (seed 0 is random) and starts play.
func new_game(_seed_value: int = 0) -> void:
	pass


func _tutorial() -> Array:
	return []


func _tutorial_tips() -> String:
	return ""


## Sets the board up for a tutorial step and points at what to do.
func _load_tutorial_step(_step: Dictionary) -> void:
	pass


## Esc or back during play: cancel something half-done. True if it did.
func _cancel() -> bool:
	return false


## [score, level, turns] for the records.
func _record() -> Array:
	return [0, 1, 0]


func _layout() -> void:
	pass


## The board's own part of Fever (frame, pieces).
func _fever_changed(_on: bool) -> void:
	pass


# --- Screens and flow ------------------------------------------------------------------

func _play_new() -> void:
	get_tree().paused = false
	_tutorial_step = -1
	menus.hide_all()
	_mode = Mode.PLAY
	new_game()


func _pause() -> void:
	if not _playing():
		return
	_cancel()
	_mode = Mode.PAUSE
	get_tree().paused = true
	menus.show_pause()


func _resume() -> void:
	get_tree().paused = false
	menus.hide_all()
	_mode = Mode.TUTORIAL if _tutorial_step >= 0 else Mode.PLAY
	if _mode == Mode.TUTORIAL:
		menus.show_tutorial(_tutorial()[_tutorial_step].text, _tutorial_step + 1, _tutorial().size())


func _back() -> void:
	if _playing():
		if not _cancel():
			_pause()
	else:
		menus.back()


func _on_name_submitted(player_name: String) -> void:
	var r := _record()
	var rank := records.add(player_name, r[0], r[1], r[2])
	records.save(Arcade.GAMES[game_key].records)
	Settings.save()
	menus.show_saved(records, rank)


# --- Tutorial ----------------------------------------------------------------------------

func _start_tutorial() -> void:
	get_tree().paused = false
	_two_players = false
	_mode = Mode.TUTORIAL
	_tutorial_step = 0
	menus.hide_all()
	new_game()
	_layout()
	_show_tutorial_step()


func _show_tutorial_step() -> void:
	var step: Dictionary = _tutorial()[_tutorial_step]
	_load_tutorial_step(step)
	menus.show_tutorial(step.text, _tutorial_step + 1, _tutorial().size())


## Moves the tutorial on once a step's goal is met.
func _advance_tutorial() -> void:
	_tutorial_step += 1
	if _tutorial_step >= _tutorial().size():
		menus.show_tutorial_end(_tutorial_tips())
		return
	_show_tutorial_step()


func _finish_tutorial() -> void:
	Settings.mark_tutorial_seen(game_key)
	_two_players = Arcade.two_players
	_play_new()


# --- Fever and the camera --------------------------------------------------------------

func _set_fever(on: bool) -> void:
	if on == _fever_on:
		return
	_fever_on = on
	_fever_changed(on)
	var now: Variant = _background.get_shader_parameter("fever")
	create_tween().tween_method(func(v: float) -> void: _background.set_shader_parameter("fever", v),
		now if now != null else 0.0, 1.0 if on else 0.0, 0.6)


## Frames the box lo..hi in the screen left free by the HUD margins
## (left, top, right, bottom). Returns true in portrait.
func _fit(lo: Vector3, hi: Vector3, portrait_margin: Vector4, landscape_margin: Vector4,
		tutorial_top: Vector2, pitch: float, yaw: float = 0.0) -> bool:
	var portrait := Stage.fit_ui(get_window())
	var size := get_viewport().get_visible_rect().size
	var m := portrait_margin if portrait else landscape_margin
	menus.tutorial_top = 150.0 if portrait else 96.0
	if _mode == Mode.TUTORIAL:
		m.y = tutorial_top.x if portrait else tutorial_top.y
	var free := Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)
	Stage.fit_camera(camera, lo, hi, free, size, pitch, yaw)
	return portrait


# --- Developer helpers (used by tools/dev_shot.gd) --------------------------------------

func debug_page(page: String) -> void:
	match page:
		"settings":
			menus.show_settings()
		"pause":
			_pause()
		"tutorial":
			_start_tutorial()
		"tutorial_end":
			menus.show_tutorial_end(_tutorial_tips())
		"versus":
			_two_players = true
			_play_new()


## Waits until nothing is animating.
func _idle() -> void:
	while _busy:
		await get_tree().process_frame


## A click at a viewport position (a 3D point unprojected, or a HUD button's centre).
func _sim_tap(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = get_viewport().get_final_transform() * at
		e.global_position = e.position
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame


func _sim_tap_world(p: Vector3) -> void:
	await _sim_tap(camera.unproject_position(p))


func _sim_tap_button(b: Control) -> void:
	await _sim_tap(b.get_global_rect().get_center())
