class_name ChessHud
extends CanvasLayer
## Merge Mate's overlay: scores and Upgrade meters, the round, whose turn it
## is, the streak, the Upgrade button, toasts and hints. Against the CPU
## only the player's side is shown; two players get one column each.

signal upgrade_pressed
signal pause_pressed

const R := preload("res://chess/chess_rules.gd")

var _score_labels: Array[Label] = []
var _meters: Array[ProgressBar] = []
var _columns: Array[Control] = []
var _best_label: Label
var _round_label: Label
var _streak_label: Label
var _turn_label: Label
var _moves_label: Label
var _hint_label: Label
var _upgrade: Button
var _bottom: VBoxContainer
var _toaster: Toaster
var _shown: Array[float] = [0.0, 0.0]
var _best := 0
var _beat_best := false
var _vs_cpu := true
var _armed := false
var _time := 0.0
var _thinking := false


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_bottom(root)


func _process(delta: float) -> void:
	_time += delta
	if _thinking:
		_turn_label.text = "CPU THINKING" + ".".repeat(1 + int(_time * 3.0) % 3)


func reset(m: ChessMatch, best: int) -> void:
	_vs_cpu = m.vs_cpu
	_best = best
	_beat_best = false
	_shown = [0.0, 0.0]
	_toaster.clear()
	# Against the CPU the Ice column is hidden but keeps its space, so the
	# round and turn banners stay centred over the board.
	_columns[1].modulate.a = 0.0 if m.vs_cpu else 1.0
	_best_label.visible = m.vs_cpu
	_best_label.text = "BEST " + UI.thousands(best) if best > 0 else ""
	_best_label.label_settings.font_color = Color(1, 1, 1, 0.7)
	for side in 2:
		_score_labels[side].text = "0"
	hint("")
	update(m)


func update(m: ChessMatch) -> void:
	for side in 2:
		_tween_score(side, m.scores[side])
		_meters[side].value = 100.0 * m.meter[side] / ChessMatch.METER_GOAL
	_round_label.text = "ROUND %d" % m.round if m.vs_cpu else "2 PLAYERS"
	_moves_label.visible = m.vs_cpu
	var left := m.moves_left()
	_moves_label.text = "%d MOVES LEFT" % left
	_moves_label.label_settings.font_color = Palette.HOT if left <= 10 else Color(1, 1, 1, 0.75)
	var side := m.turn
	var streak := m.streak[side] if not m.vs_cpu else m.streak[0]
	var shown_side := side if not m.vs_cpu else 0
	if streak >= 2:
		var label := "FEVER" if m.is_fever(shown_side) else "STREAK"
		_streak_label.text = "%s  x%s" % [label, Hud.fmt_mult(m.streak_mult(shown_side))]
		_streak_label.label_settings.font_color = Palette.HOT if m.is_fever(shown_side) else Palette.GOLD
	else:
		_streak_label.text = ""
	var charges := m.charges[side]
	var players_turn := not m.is_cpu_turn()
	_upgrade.disabled = charges <= 0 or not players_turn
	_upgrade.text = ("▶ " if _armed else "") + "UPGRADE  x%d" % charges
	UI.style_button(_upgrade, Color("8f5bff") if charges > 0 and players_turn else Color(1, 1, 1, 0.08), _armed)
	if m.vs_cpu and _best > 0 and m.scores[0] > _best and not _beat_best:
		_beat_best = true
		toast("NEW BEST!", Palette.GOLD, 1.3)
		_best_label.text = "NEW BEST!"
		_best_label.label_settings.font_color = Palette.GOLD


## The banner under the top bar saying whose move it is.
func set_turn(m: ChessMatch) -> void:
	_thinking = m.is_cpu_turn()
	if _thinking:
		_turn_label.label_settings.font_color = ChessArt.team_color(1)
		return
	if m.vs_cpu:
		_turn_label.text = "YOUR MOVE"
	else:
		_turn_label.text = "%s'S MOVE" % ChessArt.TEAM_NAMES[m.turn]
	_turn_label.label_settings.font_color = ChessArt.team_color(m.turn)
	_turn_label.pivot_offset = _turn_label.size * 0.5
	_turn_label.scale = Vector2.ONE * 1.25
	create_tween().tween_property(_turn_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Landscape puts the Upgrade button and hints in the bottom-left corner,
## beside the board; portrait centres them under it.
func set_landscape(on: bool) -> void:
	_bottom.anchor_right = 0.0 if on else 1.0
	_bottom.offset_left = 20 if on else 0
	_bottom.offset_right = 280 if on else 0
	_upgrade.custom_minimum_size.x = 250 if on else 300
	for c in _columns:
		c.custom_minimum_size.x = 250 if on else 150
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if on else TextServer.AUTOWRAP_OFF


## Clears the turn banner when the match is over.
func clear_turn() -> void:
	_thinking = false
	_turn_label.text = ""


func set_armed(on: bool) -> void:
	_armed = on


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
	_turn_label = UI.centered(UI.label("", 28))
	mid.add_child(_turn_label)
	_streak_label = UI.centered(UI.label("", 24, Palette.GOLD))
	mid.add_child(_streak_label)

	bar.add_child(_score_column(1))


## Score, Upgrade meter and (for the player against the CPU) the best.
func _score_column(side: int) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(240, 0)
	_columns.append(col)
	var title := UI.label(ChessArt.TEAM_NAMES[side], 20, ChessArt.team_color(side))
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
	fill.bg_color = Color("b48cff")
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

	var bottom := VBoxContainer.new()
	_bottom = bottom
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -150
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	_hint_label = UI.centered(UI.label("", 24, Color(1, 1, 1, 0.9)))
	bottom.add_child(_hint_label)
	_moves_label = UI.centered(UI.label("", 20, Color(1, 1, 1, 0.75)))
	bottom.add_child(_moves_label)
	_upgrade = UI.button("UPGRADE", Color(1, 1, 1, 0.08), Vector2(300, 62), 24)
	_upgrade.pressed.connect(func() -> void: upgrade_pressed.emit())
	bottom.add_child(_upgrade)
