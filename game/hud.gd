class_name Hud
extends CanvasLayer
## In-game overlay: score and best, level, streak, power meter, power
## buttons, pause button, toasts and hints. Built in code so the whole HUD
## is in one place. Menus and the game-over screen live in Menus.

signal power_pressed(slot: int)
signal pause_pressed

var _score_label: Label
var _best_label: Label
var _level_label: Label
var _streak_label: Label
var _hint_label: Label
var _toaster: Toaster
var _meter: ProgressBar
var _power_row: BoxContainer
var _power_buttons: Array[Button] = []
var _kinds: Array[int] = []
var _armed := -1
var _best := 0
var _beat_best := false
var _shown_score := 0.0
var _score_tween: Tween


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_messages(root)
	_build_powers(root)


## Clears everything for a new run. `best` is the record to beat.
func reset(state: GameState, best: int) -> void:
	if _score_tween:
		_score_tween.kill()
	_shown_score = 0.0
	_score_label.text = "0"
	_toaster.clear()
	_armed = -1
	_best = best
	_beat_best = false
	_best_label.text = "BEST " + UI.thousands(best) if best > 0 else ""
	hint("")
	update(state)


func update(state: GameState) -> void:
	_tween_score(state.score)
	_level_label.text = "LEVEL %d" % state.level
	if state.streak >= 2:
		var label := "FEVER" if Scoring.is_fever(state.streak) else "STREAK"
		_streak_label.text = "%s  x%s" % [label, fmt_mult(Scoring.streak_mult(state.streak))]
		# The streak survives a couple of quiet moves; show how many are left.
		if state.misses > 0:
			_streak_label.text += "  ·  %d left" % (Scoring.STREAK_GRACE - state.misses)
		_streak_label.label_settings.font_color = Palette.HOT if Scoring.is_fever(state.streak) else Palette.GOLD
	else:
		_streak_label.text = ""
	_meter.value = state.powers.meter_ratio() * 100.0
	_kinds = state.powers.slots.duplicate()
	_refresh_powers()
	if _best > 0 and state.score > _best and not _beat_best:
		_beat_best = true
		toast("NEW BEST!", Palette.GOLD, 1.3)
		_best_label.label_settings.font_color = Palette.GOLD
	if _beat_best:
		_best_label.text = "NEW BEST!"


## Power buttons run along the bottom in portrait and down the left side
## in landscape, where the tray takes the right side.
func set_landscape(on: bool) -> void:
	_power_row.vertical = on
	if on:
		_power_row.anchor_left = 0.0
		_power_row.anchor_right = 0.0
		_power_row.anchor_top = 0.5
		_power_row.anchor_bottom = 0.5
		_power_row.offset_left = 28
		_power_row.offset_right = 28 + 190
		_power_row.offset_top = -120
		_power_row.offset_bottom = 120
		_place(_hint_label, 0.0, 1.0, 1.0, -50, -14)
	else:
		_place(_power_row, 0.0, 1.0, 1.0, -88, -18)
		_place(_hint_label, 0.0, 1.0, 1.0, -132, -96)


## Highlights the power waiting for a target, or none with -1.
func set_armed(slot: int) -> void:
	_armed = slot
	_refresh_powers()


func hint(text: String) -> void:
	_hint_label.text = text


## Big centre message; `size` scales it for bigger moments. Messages
## queue up so none get lost.
func toast(text: String, color: Color = Palette.TEXT, size: float = 1.0) -> void:
	_toaster.push(text, color, size)


static func fmt_mult(m: float) -> String:
	return "%d" % m if is_equal_approx(m, roundf(m)) else ("%.2f" % m).trim_suffix("0")


func _refresh_powers() -> void:
	for i in _power_buttons.size():
		var b := _power_buttons[i]
		if i < _kinds.size():
			var kind := _kinds[i]
			b.text = ("▶ " if i == _armed else "") + Powers.kind_name(kind)
			b.disabled = false
			UI.style_button(b, Palette.power(kind), i == _armed)
		else:
			b.text = "·"
			b.disabled = true
			UI.style_button(b, Color(1, 1, 1, 0.08), false)


## Counts the score up and punches the label bigger the more was gained.
func _tween_score(target: int) -> void:
	var gain := float(target) - _shown_score
	if _score_tween:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(_show_score, _shown_score, float(target), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if gain > 0.5:
		var punch := 1.08 + minf(gain / 2000.0, 0.35)
		_score_label.pivot_offset = Vector2(0, _score_label.size.y * 0.5)
		_score_label.scale = Vector2.ONE * punch
		create_tween().tween_property(_score_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _show_score(v: float) -> void:
	_shown_score = v
	_score_label.text = UI.thousands(roundi(v))


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

	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 0)
	bar.add_child(left)
	left.add_child(UI.label("SCORE", 20, Color(1, 1, 1, 0.75)))
	_score_label = UI.label("0", 54)
	left.add_child(_score_label)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(230, 12)
	_meter.show_percentage = false
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.GOLD
	fill.set_corner_radius_all(6)
	_meter.add_theme_stylebox_override("background", bg)
	_meter.add_theme_stylebox_override("fill", fill)
	left.add_child(_meter)
	_best_label = UI.label("", 18, Color(1, 1, 1, 0.7))
	left.add_child(_best_label)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(gap)

	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(right)
	var level_row := HBoxContainer.new()
	level_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.alignment = BoxContainer.ALIGNMENT_END
	level_row.add_theme_constant_override("separation", 16)
	right.add_child(level_row)
	_level_label = UI.label("LEVEL 1", 30)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_row.add_child(_level_label)
	var pause := UI.button("II", Color(1, 1, 1, 0.18), Vector2(56, 52), 24)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	level_row.add_child(pause)
	_streak_label = UI.label("", 26, Palette.GOLD)
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_streak_label)


func _build_messages(root: Control) -> void:
	_toaster = Toaster.new()
	_place(_toaster, 0.0, 1.0, 0.2, -50, 50)
	root.add_child(_toaster)

	_hint_label = UI.centered(UI.label("", 26, Color(1, 1, 1, 0.9)))
	root.add_child(_hint_label)


func _build_powers(root: Control) -> void:
	var row := BoxContainer.new()
	_power_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	for i in Powers.MAX_SLOTS:
		var b := UI.button("·", Color(1, 1, 1, 0.08), Vector2(170, 64), 22)
		b.size_flags_horizontal = Control.SIZE_FILL
		b.pressed.connect(func() -> void: power_pressed.emit(i))
		row.add_child(b)
		_power_buttons.append(b)
	_refresh_powers()
	set_landscape(false)


## Stretches a control across the screen width at a height anchor.
func _place(c: Control, left: float, right: float, anchor_y: float, top: float, bottom: float) -> void:
	c.anchor_left = left
	c.anchor_right = right
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = top
	c.offset_bottom = bottom
