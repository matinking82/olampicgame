class_name Menus
extends CanvasLayer
## The in-game screens shared by every game: pause, settings, game over with
## name entry, and the tutorial cards. Keeps running while the game is
## paused. The game reacts to the signals; the hub has its own menus.

signal resume_pressed
signal restart_pressed
signal menu_pressed
signal name_submitted(name: String)
signal tutorial_skipped

var _settings: Control
var _pause: Control
var _over: Control
var _tutorial_end: Control
var _tutorial_card: Control
var _pages: Array[Control] = []
## Page to return to from Settings.
var _back_to: Control

var _over_title: Label
var _over_score: Label
var _over_ribbon: Label
var _over_stats: Label
var _over_entry: Control
var _name_edit: LineEdit
var _over_list: GridContainer
var _again_button: Button
var _tutorial_label: Label
var _tutorial_count: Label
var _tutorial_tips: Label
var _level_word := "Lv"
## How far down the tutorial card sits; a game can move it below its HUD.
var tutorial_top := 96.0
var _saved := true


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_settings = SettingsPage.build(root, back)
	_build_pause(root)
	_build_over(root)
	_build_tutorial(root)
	_pages = [_settings, _pause, _over, _tutorial_end]


## While the game is paused it doesn't get input, so the menus handle Esc
## and the Android back button themselves.
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree() and get_tree().paused:
		back()


func is_open() -> bool:
	return _pages.any(func(p: Control) -> bool: return p.visible)


func hide_all() -> void:
	for p in _pages:
		p.visible = false
	_tutorial_card.visible = false


## Esc / Android back: leave Settings, close pause. Returns false when there
## was nothing to go back from.
func back() -> bool:
	if _settings.visible:
		_open(_back_to)
		return true
	if _pause.visible:
		resume_pressed.emit()
		return true
	return false


func show_pause() -> void:
	_open(_pause)


func show_settings() -> void:
	_back_to = _current()
	_open(_settings)


## The end of a run: counts the score up, celebrates a new best, and asks
## for a name when the score makes the top 10. With no `records` (a two
## player match) it just shows the result.
func show_game_over(title: String, score: int, stats: String, records: Records, best_before: int,
		level_word: String = "Lv", again_text: String = "PLAY AGAIN") -> void:
	var qualifies := records != null and records.qualifies(score)
	_saved = not qualifies
	_level_word = level_word
	_over_title.text = title
	_over_ribbon.visible = records != null and score > best_before and best_before > 0
	_over_score.visible = records != null
	_over_stats.text = stats
	_over_entry.visible = qualifies
	_over_list.visible = false
	_again_button.text = again_text
	_name_edit.text = Settings.player_name
	_open(_over)
	if records == null:
		Sound.play("coin")
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _over_score.text = UI.thousands(roundi(v)), 0.0, float(score), 1.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Sound.play.bind("coin"))
	if _over_ribbon.visible:
		tw.tween_callback(Sound.play.bind("perfect"))
	if qualifies and not OS.has_feature("mobile"):
		_name_edit.call_deferred("grab_focus")


## After the name is saved: show where it landed.
func show_saved(records: Records, rank: int) -> void:
	_saved = true
	_over_entry.visible = false
	UI.fill_records(_over_list, records, rank, _level_word)
	_over_list.visible = true


func show_tutorial(text: String, step: int, total: int) -> void:
	_tutorial_label.text = text
	_tutorial_count.text = "HOW TO PLAY  %d/%d" % [step, total]
	# As wide as fits: 660 on a landscape screen, the screen minus a margin on a phone.
	var half := minf(330.0, _tutorial_card.get_viewport_rect().size.x * 0.5 - 12.0)
	_tutorial_card.offset_left = -half
	_tutorial_card.offset_right = half
	_tutorial_label.custom_minimum_size.x = half * 2.0 - 40.0
	_tutorial_card.offset_top = tutorial_top
	_tutorial_card.size = Vector2.ZERO
	_tutorial_card.visible = true
	_tutorial_card.pivot_offset = _tutorial_card.size * 0.5
	_tutorial_card.scale = Vector2.ONE * 0.8
	create_tween().tween_property(_tutorial_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_tutorial() -> void:
	_tutorial_card.visible = false


## The card after the last tutorial step, with the game's closing tips.
func show_tutorial_end(tips: String) -> void:
	_tutorial_card.visible = false
	_tutorial_tips.text = tips
	_open(_tutorial_end)


# --- Building ------------------------------------------------------------------

func _build_pause(root: Control) -> void:
	var made := UI.page(root)
	_pause = made[0]
	var col: VBoxContainer = made[1]
	col.add_child(UI.centered(UI.label("PAUSED", 56, Palette.GOLD)))
	var resume := UI.button("RESUME", Palette.GOLD, Vector2(340, 80), 34)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	col.add_child(resume)
	var restart := UI.button("RESTART", Palette.power(Powers.Kind.LASER))
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	col.add_child(restart)
	var sets := UI.button("SETTINGS", Palette.power(Powers.Kind.REROLL))
	sets.pressed.connect(show_settings)
	col.add_child(sets)
	var menu := UI.button("MAIN MENU", Color(1, 1, 1, 0.15))
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	col.add_child(menu)


func _build_over(root: Control) -> void:
	var made := UI.page(root, 0.75)
	_over = made[0]
	var col: VBoxContainer = made[1]
	_over_title = UI.centered(UI.label("", 40, Palette.GOLD))
	col.add_child(_over_title)
	_over_ribbon = UI.centered(UI.label("★ NEW BEST! ★", 34, Palette.HOT))
	col.add_child(_over_ribbon)
	_over_score = UI.centered(UI.label("0", 88))
	col.add_child(_over_score)
	_over_stats = UI.centered(UI.label("", 20, Color(1, 1, 1, 0.8)))
	col.add_child(_over_stats)

	_over_entry = VBoxContainer.new()
	_over_entry.add_theme_constant_override("separation", 10)
	col.add_child(_over_entry)
	_over_entry.add_child(UI.centered(UI.label("TOP 10!  Enter your name", 26, Palette.GOLD)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_over_entry.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = Records.MAX_NAME
	_name_edit.placeholder_text = "Your name"
	_name_edit.custom_minimum_size = Vector2(300, 64)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_override("font", TileArt.font())
	_name_edit.add_theme_font_size_override("font_size", 30)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.1)
	field.set_corner_radius_all(16)
	field.set_border_width_all(3)
	field.border_color = Palette.GOLD
	field.set_content_margin_all(10)
	_name_edit.add_theme_stylebox_override("normal", field)
	_name_edit.add_theme_stylebox_override("focus", field)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	row.add_child(_name_edit)
	var save := UI.button("SAVE", Palette.GOLD, Vector2(140, 64))
	save.pressed.connect(_submit)
	row.add_child(save)

	_over_list = UI.records_grid()
	col.add_child(_over_list)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	col.add_child(buttons)
	_again_button = UI.button("PLAY AGAIN", Palette.GOLD, Vector2(260, 72))
	_again_button.pressed.connect(func() -> void:
		_submit()
		restart_pressed.emit())
	buttons.add_child(_again_button)
	var menu := UI.button("MENU", Color(1, 1, 1, 0.15), Vector2(160, 72))
	menu.pressed.connect(func() -> void:
		_submit()
		menu_pressed.emit())
	buttons.add_child(menu)


func _build_tutorial(root: Control) -> void:
	# A card along the top that leaves the board playable underneath.
	var card := PanelContainer.new()
	var style := UI.panel_style()
	style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", style)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -330
	card.offset_right = 330
	card.offset_top = 96
	card.visible = false
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Only SKIP takes clicks; drags and taps reach the board underneath.
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	_tutorial_card = card
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_tutorial_count = UI.label("", 20, Palette.GOLD)
	_tutorial_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tutorial_count)
	var skip := UI.button("SKIP", Color(1, 1, 1, 0.15), Vector2(110, 44), 20)
	skip.pressed.connect(func() -> void: tutorial_skipped.emit())
	top.add_child(skip)
	_tutorial_label = UI.label("", 26)
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_label.custom_minimum_size = Vector2(620, 0)
	col.add_child(_tutorial_label)

	var made := UI.page(root, 0.6)
	_tutorial_end = made[0]
	var end_col: VBoxContainer = made[1]
	end_col.add_child(UI.centered(UI.label("YOU'RE READY!", 48, Palette.GOLD)))
	_tutorial_tips = UI.label("", 24)
	_tutorial_tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_tips.custom_minimum_size = Vector2(620, 0)
	_tutorial_tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_col.add_child(_tutorial_tips)
	var go := UI.button("LET'S PLAY!", Palette.GOLD, Vector2(360, 84), 36)
	go.pressed.connect(func() -> void: tutorial_skipped.emit())
	end_col.add_child(go)


# --- Helpers ---------------------------------------------------------------------

func _open(page: Control) -> void:
	UI.open_page(_pages, page)


func _current() -> Control:
	for p in _pages:
		if p.visible:
			return p
	return _pause


func _submit() -> void:
	if _saved:
		return
	_saved = true
	Settings.player_name = Records.clean_name(_name_edit.text)
	name_submitted.emit(Settings.player_name)
