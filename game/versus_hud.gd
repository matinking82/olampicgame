class_name VersusHud
extends CanvasLayer
## The overlay for the two-sided games (Flip Pop, Maze Race): each side's
## score and power meter, the round with hearts (or round wins for two
## players) and a pause button, whose turn it is, a line of game info, the
## streak, power buttons, an optional big action button, toasts and hints.
## Landscape puts the action button bottom-right and the powers
## bottom-left; portrait stacks them under the board.

signal power_pressed(index: int)
signal action_pressed
signal pause_pressed

const POWER_COLOR := Color("ff4fcf")
const OFF := Color(1, 1, 1, 0.08)

var titles: Array = ["SUN", "ICE"]
var colors: Array = [Color("ffc61a"), Color("39e0ff")]
var power_names: Array = []
var action_text := ""
var hearts_max := 3

var powers: Array[Button] = []
var action: Button
var _score_labels: Array[Label] = []
var _meters: Array[ProgressBar] = []
var _columns: Array[Control] = []
var _best_label: Label
var _round_label: Label
var _hearts_label: Label
var _turn_label: Label
var _info_label: Label
var _streak_label: Label
var _hint_label: Label
var _bottom: VBoxContainer
var _right: VBoxContainer
var _toaster: Toaster
var _shown: Array[float] = [0.0, 0.0]
var _best := 0
var _beat_best := false
var _vs_cpu := true
var _landscape := true
var _laid_out := false
var _time := 0.0
var _thinking := ""


func _init(team_titles: Array, team_colors: Array, power_list: Array, action_label: String = "") -> void:
	titles = team_titles
	colors = team_colors
	power_names = power_list
	action_text = action_label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_bottom(root)


func _process(delta: float) -> void:
	_time += delta
	if _thinking != "":
		_turn_label.text = _thinking + ".".repeat(1 + int(_time * 3.0) % 3)
	# The action button breathes while it's the thing to press.
	if action != null:
		if not action.disabled:
			action.pivot_offset = action.size * 0.5
			action.scale = Vector2.ONE * (1.0 + 0.035 * sin(_time * 5.0))
		else:
			action.scale = Vector2.ONE


func reset(vs_cpu: bool, best: int) -> void:
	_vs_cpu = vs_cpu
	_best = best
	_beat_best = false
	_shown = [0.0, 0.0]
	_toaster.clear()
	# Against the CPU the second column is hidden but keeps its space, so the
	# round and turn banners stay centred over the board.
	_columns[1].modulate.a = 0.0 if vs_cpu else 1.0
	_best_label.visible = vs_cpu
	_best_label.text = "BEST " + UI.thousands(best) if best > 0 else ""
	_best_label.label_settings.font_color = Color(1, 1, 1, 0.7)
	for side in 2:
		_score_labels[side].text = "0"
	_streak_label.text = ""
	_info_label.text = ""
	hint("")


## Scores and power meters (0-1 full).
func show_scores(scores: Array, meters: Array) -> void:
	for side in 2:
		_tween_score(side, scores[side])
		_meters[side].value = 100.0 * meters[side]
	if _vs_cpu and _best > 0 and scores[0] > _best and not _beat_best:
		_beat_best = true
		toast("NEW BEST!", Palette.GOLD, 1.3)
		_best_label.text = "NEW BEST!"
		_best_label.label_settings.font_color = Palette.GOLD


## The round, with hearts against the CPU or the round wins for two players.
func show_round(round: int, hearts: int, wins: Array) -> void:
	_round_label.text = "ROUND %d" % round
	if _vs_cpu:
		_hearts_label.text = "♥".repeat(hearts) + "♡".repeat(maxi(hearts_max - hearts, 0))
		_hearts_label.label_settings.font_color = Palette.HOT
	else:
		_hearts_label.text = "%s %d  –  %d %s" % [_bare(titles[0]), wins[0], wins[1], _bare(titles[1])]
		_hearts_label.label_settings.font_color = Palette.TEXT


func show_streak(streak: int, mult: float, fever: bool) -> void:
	if streak >= 2:
		_streak_label.text = "%s  x%s" % ["FEVER" if fever else "STREAK", Hud.fmt_mult(mult)]
		_streak_label.label_settings.font_color = Palette.HOT if fever else Palette.GOLD
	else:
		_streak_label.text = ""


## A team title without its symbol ("SUN  ●" -> "SUN").
static func _bare(title: String) -> String:
	return title.replace("●", "").replace("✕", "").replace("◯", "").strip_edges()


## A line of game facts under the turn banner (disc counts, path lengths).
func set_info(text: String, color: Color = Color(1, 1, 1, 0.9)) -> void:
	_info_label.text = text
	_info_label.label_settings.font_color = color


## Whose turn it is; `thinking` animates "CPU THINKING...".
func set_turn(text: String, color: Color, thinking: bool = false) -> void:
	_thinking = text if thinking else ""
	_turn_label.label_settings.font_color = color
	if thinking:
		return
	_turn_label.text = text
	_turn_label.pivot_offset = _turn_label.size * 0.5
	_turn_label.scale = Vector2.ONE * 1.25
	create_tween().tween_property(_turn_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func clear_turn() -> void:
	_thinking = ""
	_turn_label.text = ""


## Restyles a power button: lit in its colour when usable, `armed` outlines it.
func style_power(i: int, text: String, enabled: bool, color: Color = POWER_COLOR, armed: bool = false) -> void:
	var b := powers[i]
	b.text = text
	b.disabled = not enabled
	UI.style_button(b, color if enabled else OFF, armed)


func style_action(text: String, enabled: bool, color: Color = Palette.GOLD) -> void:
	action.text = text
	action.disabled = not enabled
	UI.style_button(action, color if enabled else OFF, false)


func set_landscape(on: bool) -> void:
	if _laid_out and on == _landscape:
		return
	_laid_out = true
	_landscape = on
	_bottom.anchor_right = 0.0 if on else 1.0
	_bottom.offset_left = 20 if on else 0
	_bottom.offset_right = 290 if on else 0
	_right.visible = on
	if action != null:
		if on:
			action.reparent(_right, false)
		else:
			action.reparent(_bottom, false)
			_bottom.move_child(action, 1)
		action.custom_minimum_size = Vector2(250, 84) if on else Vector2(300, 72)
	for c in _columns:
		c.custom_minimum_size.x = 250 if on else 150
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if on else TextServer.AUTOWRAP_OFF


func is_landscape() -> bool:
	return _landscape


func hint(text: String) -> void:
	_hint_label.text = text


func toast(text: String, color: Color = Palette.TEXT, size: float = 1.0) -> void:
	_toaster.push(text, color, size)


func _tween_score(side: int, target: int) -> void:
	var gain := float(target) - _shown[side]
	if absf(gain) < 0.5:
		return
	var label := _score_labels[side]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_shown[side] = v
		label.text = UI.thousands(roundi(v)), _shown[side], float(target), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if gain > 0:
		label.pivot_offset = Vector2(0, label.size.y * 0.5)
		label.scale = Vector2.ONE * (1.08 + minf(gain / 2000.0, 0.35))
		create_tween().tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _build_top(root: Control) -> void:
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 28)
	top.add_theme_constant_override("margin_right", 28)
	top.add_theme_constant_override("margin_top", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar)
	bar.add_child(_score_column(0))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", 0)
	bar.add_child(mid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(row)
	# A spacer as wide as the pause button keeps the label itself centred.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(56, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_round_label = UI.label("ROUND 1", 30)
	_round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_round_label)
	var pause := UI.button("II", Color(1, 1, 1, 0.18), Vector2(56, 52), 24)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	row.add_child(pause)
	_hearts_label = UI.centered(UI.label("", 26, Palette.HOT))
	mid.add_child(_hearts_label)
	_turn_label = UI.centered(UI.label("", 28))
	mid.add_child(_turn_label)
	_info_label = UI.centered(UI.label("", 22))
	mid.add_child(_info_label)
	_streak_label = UI.centered(UI.label("", 24, Palette.GOLD))
	mid.add_child(_streak_label)

	bar.add_child(_score_column(1))


## Score, power meter and (for the player against the CPU) the best.
func _score_column(side: int) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(240, 0)
	_columns.append(col)
	var title := UI.label(titles[side], 20, colors[side])
	col.add_child(title)
	var score := UI.label("0", 50)
	col.add_child(score)
	_score_labels.append(score)
	var meter := ProgressBar.new()
	meter.custom_minimum_size = Vector2(220, 12)
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = POWER_COLOR
	fill.set_corner_radius_all(6)
	meter.add_theme_stylebox_override("background", bg)
	meter.add_theme_stylebox_override("fill", fill)
	col.add_child(meter)
	_meters.append(meter)
	if side == 0:
		_best_label = UI.label("", 18, Color(1, 1, 1, 0.7))
		col.add_child(_best_label)
	else:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meter.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	return col


func _build_bottom(root: Control) -> void:
	_toaster = Toaster.new()
	_toaster.anchor_right = 1.0
	_toaster.anchor_top = 0.24
	_toaster.anchor_bottom = 0.24
	_toaster.offset_top = -50
	_toaster.offset_bottom = 50
	root.add_child(_toaster)

	_bottom = VBoxContainer.new()
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_top = -200
	_bottom.offset_bottom = -18
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 8)
	root.add_child(_bottom)
	_hint_label = UI.centered(UI.label("", 22, Color(1, 1, 1, 0.9)))
	_bottom.add_child(_hint_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(row)
	for i in power_names.size():
		var b := UI.button(power_names[i], OFF, Vector2(130, 54), 18)
		b.pressed.connect(func() -> void: power_pressed.emit(i))
		row.add_child(b)
		powers.append(b)

	_right = VBoxContainer.new()
	_right.anchor_left = 1.0
	_right.anchor_right = 1.0
	_right.anchor_top = 1.0
	_right.anchor_bottom = 1.0
	_right.offset_left = -290
	_right.offset_right = -20
	_right.offset_top = -120
	_right.offset_bottom = -18
	_right.alignment = BoxContainer.ALIGNMENT_END
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_right)
	if action_text != "":
		action = UI.button(action_text, Palette.GOLD, Vector2(250, 84), 30)
		action.pressed.connect(func() -> void: action_pressed.emit())
		_right.add_child(action)
