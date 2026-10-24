class_name GridHud
extends CanvasLayer
## Code Grid's overlay: the score with its power meter and best, the level
## with hearts, the checks left and par, the "codes left" counter, the
## streak, every past check as a little card (tap one to load that guess
## back), the digit palette, the big CHECK button, CLEAR, the REVEAL and
## TEST powers, toasts and hints. Landscape puts the cards down the right,
## CHECK bottom-right and the powers bottom-left; portrait puts the cards
## under the top bar and stacks the rest under the board.

signal digit_pressed(v: int)
signal check_pressed
signal clear_pressed
signal power_pressed(index: int)
signal card_pressed(index: int)
signal pause_pressed

const POWER_COLOR := Color("ff4fcf")
const OFF := Color(1, 1, 1, 0.08)
const REVEAL := 0
const TEST := 1

var powers: Array[Button] = []
var check_button: Button
var clear_button: Button
var digit_buttons: Array[Button] = []
var _score_label: Label
var _meter: ProgressBar
var _best_label: Label
var _level_label: Label
var _hearts_label: Label
var _checks_label: Label
var _codes_label: Label
var _streak_label: Label
var _hint_label: Label
var _palette: HBoxContainer
var _bottom: VBoxContainer
var _right: VBoxContainer
var _left_box: VBoxContainer
var _left_row: HBoxContainer
var _cards: GridContainer
var _cards_box: Control
var _toaster: Toaster
var _shown := 0.0
var _best := 0
var _beat_best := false
var _landscape := true
var _laid_out := false
var _time := 0.0
var _selected := 1
var _n := 4
var _counting := false


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_cards(root)
	_build_bottom(root)


func _process(delta: float) -> void:
	_time += delta
	if _counting:
		_codes_label.text = "COUNTING CODES" + ".".repeat(1 + int(_time * 3.0) % 3)
	if not check_button.disabled:
		check_button.pivot_offset = check_button.size * 0.5
		check_button.scale = Vector2.ONE * (1.0 + 0.035 * sin(_time * 5.0))
	else:
		check_button.scale = Vector2.ONE


func reset(best: int) -> void:
	_best = best
	_beat_best = false
	_shown = 0.0
	_score_label.text = "0"
	_toaster.clear()
	_best_label.text = "BEST " + UI.thousands(best) if best > 0 else ""
	_best_label.label_settings.font_color = Color(1, 1, 1, 0.7)
	hint("")


func update(m: GridMatch) -> void:
	_tween_score(m.score)
	_meter.value = 100.0 * m.meter_fill()
	_level_label.text = "LEVEL %d" % m.level
	_hearts_label.text = "♥".repeat(m.hearts) + "♡".repeat(maxi(GridMatch.HEARTS - m.hearts, 0))
	_checks_label.text = "CHECKS LEFT %d  ·  PAR %d" % [m.checks_left(), m.par]
	_checks_label.label_settings.font_color = Palette.HOT if m.checks_left() <= 1 and m.is_running() else Palette.TEXT
	if m.streak >= 2:
		_streak_label.text = "%s  x%s" % ["FEVER" if m.is_fever() else "STREAK", Hud.fmt_mult(m.streak_mult())]
		_streak_label.label_settings.font_color = Palette.HOT if m.is_fever() else Palette.GOLD
	else:
		_streak_label.text = ""
	if _best > 0 and m.score > _best and not _beat_best:
		_beat_best = true
		toast("NEW BEST!", Palette.GOLD, 1.3)
		_best_label.text = "NEW BEST!"
		_best_label.label_settings.font_color = Palette.GOLD
	var running := m.is_running()
	var blocker := m.check_blocker()
	check_button.text = "CHECK!" if blocker == "" else "CHECK"
	check_button.disabled = not running or blocker != ""
	UI.style_button(check_button, Palette.GOLD if not check_button.disabled else OFF, false)
	clear_button.disabled = not running
	var label := "x%d" % m.charges
	_style_power(REVEAL, "REVEAL  " + label, running and m.can_use_power(), Color("3fd8f0"))
	_style_power(TEST, "TEST  " + label, running and m.can_use_power(), Color("8f5bff"))


## The digits for an n x n grid, and which one is selected.
func set_digits(n: int, selected: int) -> void:
	_n = n
	_selected = selected
	for b in digit_buttons:
		b.queue_free()
	digit_buttons.clear()
	for v in range(1, n + 1):
		var b := UI.button(str(v), Palette.DIGITS[v - 1], Vector2(66, 66), 34)
		b.pressed.connect(func() -> void: digit_pressed.emit(v))
		_palette.add_child(b)
		digit_buttons.append(b)
	select_digit(selected)
	_size_digits()


func select_digit(v: int) -> void:
	_selected = v
	for k in digit_buttons.size():
		var b := digit_buttons[k]
		var on := k + 1 == v
		UI.style_button(b, Palette.DIGITS[k], on)
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (1.12 if on else 1.0)


## The "codes left" line: counting, a number, or "at least" when the count gave up.
func set_codes(count: int, complete: bool) -> void:
	_counting = count < 0
	if count < 0:
		return
	if count == 1 and complete:
		_codes_label.text = "ONLY 1 CODE FITS!"
		_codes_label.label_settings.font_color = Palette.GOLD
	else:
		_codes_label.text = "CODES LEFT %s%d" % ["" if complete else "", count] + ("" if complete else "+")
		_codes_label.label_settings.font_color = Color(1, 1, 1, 0.85)


func clear_codes() -> void:
	_counting = false
	_codes_label.text = ""


## One card per check: the guess in candy colours, its row counts down the
## side and column counts along the bottom.
func set_history(checks: Array, n: int) -> void:
	for c in _cards.get_children():
		c.queue_free()
	for k in checks.size():
		var card := CheckCard.new(checks[k], n, k + 1, (56 if _landscape else 54) / n)
		card.pressed.connect(func() -> void: card_pressed.emit(k))
		_cards.add_child(card)
	_cards_box.visible = not checks.is_empty()


func set_landscape(on: bool) -> void:
	if _laid_out and on == _landscape:
		return
	_laid_out = true
	_landscape = on
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.offset_left = 290 if on else 0
	_bottom.offset_right = -290 if on else 0
	_right.visible = on
	if on:
		check_button.reparent(_right, false)
		_left_row.reparent(_left_box, false)
	else:
		check_button.reparent(_bottom, false)
		_bottom.move_child(check_button, 2)
		_left_row.reparent(_bottom, false)
	check_button.custom_minimum_size = Vector2(250, 84) if on else Vector2(300, 70)
	# Cards: down the right on a wide screen, under the top bar on a tall one.
	_cards_box.anchor_left = 1.0 if on else 0.0
	_cards_box.anchor_right = 1.0
	_cards_box.offset_left = -250 if on else 12
	_cards_box.offset_right = -16 if on else -12
	_cards_box.offset_top = 150 if on else 150
	_cards.columns = 2 if on else 4
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_size_digits()


func is_landscape() -> bool:
	return _landscape


func hint(text: String) -> void:
	_hint_label.text = text


func toast(text: String, color: Color = Palette.TEXT, size: float = 1.0) -> void:
	_toaster.push(text, color, size)


func _style_power(i: int, text: String, enabled: bool, color: Color) -> void:
	var b := powers[i]
	b.text = text
	b.disabled = not enabled
	UI.style_button(b, color if enabled else OFF, false)


func _size_digits() -> void:
	var side := 66 if _landscape else (60 if _n <= 5 else 54)
	for b in digit_buttons:
		b.custom_minimum_size = Vector2(side, side)


func _tween_score(target: int) -> void:
	var gain := float(target) - _shown
	if absf(gain) < 0.5:
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_shown = v
		_score_label.text = UI.thousands(roundi(v)), _shown, float(target), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if gain > 0:
		_score_label.pivot_offset = Vector2(0, _score_label.size.y * 0.5)
		_score_label.scale = Vector2.ONE * (1.08 + minf(gain / 2000.0, 0.35))
		create_tween().tween_property(_score_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --- Building ----------------------------------------------------------------------------

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
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(150, 0)
	bar.add_child(col)
	col.add_child(UI.label("SCORE", 20, Palette.GOLD))
	_score_label = UI.label("0", 50)
	col.add_child(_score_label)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(150, 12)
	_meter.show_percentage = false
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = POWER_COLOR
	fill.set_corner_radius_all(6)
	_meter.add_theme_stylebox_override("background", bg)
	_meter.add_theme_stylebox_override("fill", fill)
	col.add_child(_meter)
	_best_label = UI.label("", 18, Color(1, 1, 1, 0.7))
	col.add_child(_best_label)

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
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(56, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_level_label = UI.label("LEVEL 1", 30)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_level_label)
	var pause := UI.button("II", Color(1, 1, 1, 0.18), Vector2(56, 52), 24)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	row.add_child(pause)
	_hearts_label = UI.centered(UI.label("", 26, Palette.HOT))
	mid.add_child(_hearts_label)
	_checks_label = UI.centered(UI.label("", 24))
	mid.add_child(_checks_label)
	_codes_label = UI.centered(UI.label("", 22))
	mid.add_child(_codes_label)
	_streak_label = UI.centered(UI.label("", 24, Palette.GOLD))
	mid.add_child(_streak_label)
	# Balances the score column so the middle stays centred.
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(150, 0)
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(balance)


func _build_cards(root: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	_cards_box = box
	box.add_child(UI.label("CHECKS", 18, Palette.GOLD))
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 8)
	_cards.add_theme_constant_override("v_separation", 8)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_cards)
	box.visible = false


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
	_bottom.offset_top = -260
	_bottom.offset_bottom = -18
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 10)
	root.add_child(_bottom)
	_hint_label = UI.centered(UI.label("", 22, Color(1, 1, 1, 0.9)))
	_bottom.add_child(_hint_label)
	_palette = HBoxContainer.new()
	_palette.alignment = BoxContainer.ALIGNMENT_CENTER
	_palette.add_theme_constant_override("separation", 10)
	_palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_palette)

	_left_box = VBoxContainer.new()
	_left_box.anchor_top = 1.0
	_left_box.anchor_bottom = 1.0
	_left_box.offset_left = 20
	_left_box.offset_right = 290
	_left_box.offset_top = -120
	_left_box.offset_bottom = -18
	_left_box.alignment = BoxContainer.ALIGNMENT_END
	_left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_left_box)
	_left_row = HBoxContainer.new()
	_left_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_left_row.add_theme_constant_override("separation", 8)
	_left_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_box.add_child(_left_row)
	for i in 2:
		var b := UI.button(["REVEAL", "TEST"][i], OFF, Vector2(118, 54), 17)
		b.pressed.connect(func() -> void: power_pressed.emit(i))
		_left_row.add_child(b)
		powers.append(b)
	clear_button = UI.button("CLEAR", Color(1, 1, 1, 0.15), Vector2(84, 54), 17)
	clear_button.pressed.connect(func() -> void: clear_pressed.emit())
	_left_row.add_child(clear_button)

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
	check_button = UI.button("CHECK", Palette.GOLD, Vector2(250, 84), 34)
	check_button.pressed.connect(func() -> void: check_pressed.emit())
	_right.add_child(check_button)


## A past check drawn small: the guess's colours, row counts down the right
## and column counts along the bottom, numbered in the corner.
class CheckCard:
	extends Control
	signal pressed

	var check: Dictionary
	var n := 4
	var number := 1
	var cell := 9

	func _init(c: Dictionary, size_n: int, k: int, cell_px: int) -> void:
		check = c
		n = size_n
		number = k
		cell = cell_px
		custom_minimum_size = Vector2(n * cell + 24, n * cell + 22)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Load this guess"

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Sound.play("click")
			pressed.emit()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		var guess: PackedInt32Array = check.guess
		for i in guess.size():
			var r := Rect2(Vector2(i % n, i / n) * cell + Vector2(2, 2), Vector2(cell - 1, cell - 1))
			draw_rect(r, Palette.DIGITS[guess[i] - 1])
		var font := TileArt.font()
		var fs := 14 if cell >= 11 else 11
		for r in n:
			var v: int = check.rows[r]
			draw_string(font, Vector2(n * cell + 6, r * cell + cell + 1), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Palette.GOLD if v > 0 else Color(1, 1, 1, 0.5))
		for c in n:
			var v: int = check.cols[c]
			draw_string(font, Vector2(c * cell + 3, n * cell + 15), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Palette.GOLD if v > 0 else Color(1, 1, 1, 0.5))
		draw_string(font, Vector2(n * cell + 4, n * cell + 16), "#%d" % number, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1, 1, 1, 0.6))
