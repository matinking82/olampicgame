class_name DiceHud
extends CanvasLayer
## Tic Tac Roll's overlay: scores and power meters, the round with hearts
## (or round wins for two players), whose turn it is, the streak, the big
## ROLL button, the two power buttons, toasts and hints. Landscape puts ROLL
## in the bottom-right corner and the powers bottom-left; portrait stacks
## them under the board.

signal roll_pressed
signal extra_pressed
signal nudge_pressed
signal pause_pressed

const R := preload("res://dice/dice_rules.gd")
const POWER_COLOR := Color("ff4fcf")

var _score_labels: Array[Label] = []
var _meters: Array[ProgressBar] = []
var _columns: Array[Control] = []
var _best_label: Label
var _round_label: Label
var _hearts_label: Label
var _streak_label: Label
var _turn_label: Label
var _hint_label: Label
var _roll: Button
var _extra: Button
var _nudge: Button
var _bottom: VBoxContainer
var _right: VBoxContainer
var _toaster: Toaster
var _shown: Array[float] = [0.0, 0.0]
var _best := 0
var _beat_best := false
var _armed := false
var _landscape := true
var _laid_out := false
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
		_turn_label.text = "CPU ROLLING" + ".".repeat(1 + int(_time * 3.0) % 3)
	# The ROLL button breathes while it's the thing to press.
	if not _roll.disabled:
		_roll.pivot_offset = _roll.size * 0.5
		_roll.scale = Vector2.ONE * (1.0 + 0.035 * sin(_time * 5.0))
	else:
		_roll.scale = Vector2.ONE


func reset(m: DiceMatch, best: int) -> void:
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


func update(m: DiceMatch) -> void:
	for side in 2:
		_tween_score(side, m.scores[side])
		_meters[side].value = 100.0 * m.meter[side] / DiceMatch.METER_GOAL
	_round_label.text = "ROUND %d" % m.round
	if m.vs_cpu:
		_hearts_label.text = "♥".repeat(m.hearts) + "♡".repeat(DiceMatch.HEARTS - m.hearts)
		_hearts_label.label_settings.font_color = Palette.HOT
	else:
		_hearts_label.text = "SUN %d  –  %d ICE" % [m.round_wins[0], m.round_wins[1]]
		_hearts_label.label_settings.font_color = Palette.TEXT
	var shown_side := m.turn if not m.vs_cpu else 0
	var streak := m.streak[shown_side]
	if streak >= 2:
		var label := "FEVER" if m.is_fever(shown_side) else "STREAK"
		_streak_label.text = "%s  x%s" % [label, Hud.fmt_mult(m.streak_mult(shown_side))]
		_streak_label.label_settings.font_color = Palette.HOT if m.is_fever(shown_side) else Palette.GOLD
	else:
		_streak_label.text = ""

	var mine := not m.is_cpu_turn() and m.winner < 0 and not m.draw
	var bust := m.is_bust()
	if bust:
		_roll.text = "PASS"
	elif m.rolls_left > 0:
		_roll.text = ("ROLL!" if not m.rolled else "ROLL  ") + ("" if not m.rolled else "●".repeat(m.rolls_left))
	else:
		_roll.text = "PICK A CELL"
	_roll.disabled = not mine or (m.rolls_left <= 0 and not bust)
	UI.style_button(_roll, (Palette.HOT if bust else Palette.GOLD) if not _roll.disabled else Color(1, 1, 1, 0.08), false)
	var charges := m.charges[m.turn]
	_extra.text = "+1 ROLL  x%d" % charges
	_nudge.text = ("▶ " if _armed else "") + "NUDGE  x%d" % charges
	_extra.disabled = not mine or not m.can_extra_roll()
	_nudge.disabled = not mine or not m.can_nudge()
	UI.style_button(_extra, POWER_COLOR if not _extra.disabled else Color(1, 1, 1, 0.08), false)
	UI.style_button(_nudge, Color("8f5bff") if not _nudge.disabled else Color(1, 1, 1, 0.08), _armed)
	if m.vs_cpu and _best > 0 and m.scores[0] > _best and not _beat_best:
		_beat_best = true
		toast("NEW BEST!", Palette.GOLD, 1.3)
		_best_label.text = "NEW BEST!"
		_best_label.label_settings.font_color = Palette.GOLD


## The banner under the top bar saying whose turn it is.
func set_turn(m: DiceMatch) -> void:
	_thinking = m.is_cpu_turn()
	if _thinking:
		_turn_label.label_settings.font_color = DiceArt.team_color(1)
		return
	_turn_label.text = "YOUR TURN" if m.vs_cpu else "%s'S TURN" % DiceArt.TEAM_NAMES[m.turn]
	_turn_label.label_settings.font_color = DiceArt.team_color(m.turn)
	_turn_label.pivot_offset = _turn_label.size * 0.5
	_turn_label.scale = Vector2.ONE * 1.25
	create_tween().tween_property(_turn_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func clear_turn() -> void:
	_thinking = false
	_turn_label.text = ""


func set_landscape(on: bool) -> void:
	if _laid_out and on == _landscape:
		return
	_laid_out = true
	_landscape = on
	_bottom.anchor_right = 0.0 if on else 1.0
	_bottom.offset_left = 20 if on else 0
	_bottom.offset_right = 290 if on else 0
	_right.visible = on
	if on:
		_roll.reparent(_right, false)
	else:
		_roll.reparent(_bottom, false)
		_bottom.move_child(_roll, 1)
	_roll.custom_minimum_size = Vector2(250, 84) if on else Vector2(300, 72)
	for c in _columns:
		c.custom_minimum_size.x = 250 if on else 150
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if on else TextServer.AUTOWRAP_OFF


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
	_hearts_label = UI.centered(UI.label("", 26, Palette.HOT))
	mid.add_child(_hearts_label)
	_turn_label = UI.centered(UI.label("", 28))
	mid.add_child(_turn_label)
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
	var title := UI.label(("SUN  ✕" if side == 0 else "◯  ICE"), 20, DiceArt.team_color(side))
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
	var powers := HBoxContainer.new()
	powers.alignment = BoxContainer.ALIGNMENT_CENTER
	powers.add_theme_constant_override("separation", 10)
	powers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(powers)
	_extra = UI.button("+1 ROLL", Color(1, 1, 1, 0.08), Vector2(130, 54), 18)
	_extra.pressed.connect(func() -> void: extra_pressed.emit())
	powers.add_child(_extra)
	_nudge = UI.button("NUDGE", Color(1, 1, 1, 0.08), Vector2(130, 54), 18)
	_nudge.pressed.connect(func() -> void: nudge_pressed.emit())
	powers.add_child(_nudge)

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
	_roll = UI.button("ROLL!", Palette.GOLD, Vector2(250, 84), 34)
	_roll.pressed.connect(func() -> void: roll_pressed.emit())
	_right.add_child(_roll)
