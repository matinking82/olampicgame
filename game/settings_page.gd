class_name SettingsPage
extends RefCounted
## The settings screen, shared by the hub and every game's pause menu.
## Changes apply and save straight away through the Settings autoload.


## Builds the page (hidden) under `parent`. BACK calls `on_back`; when
## `on_reset` is given there's also a two-tap button that erases records.
static func build(parent: Control, on_back: Callable, on_reset: Callable = Callable()) -> Control:
	var made := UI.page(parent)
	var page: Control = made[0]
	var col: VBoxContainer = made[1]
	col.add_child(UI.centered(UI.label("SETTINGS", 48, Palette.GOLD)))
	col.add_child(_slider_row("Music", "music_volume"))
	col.add_child(_slider_row("Effects", "sfx_volume"))
	col.add_child(_toggle_row("Screen shake", "screen_shake"))
	col.add_child(_toggle_row("Vibration", "vibration"))
	col.add_child(_toggle_row("Sudoku hints", "hints"))
	if on_reset.is_valid():
		var reset := UI.button("RESET RECORDS", Color(1, 1, 1, 0.12), Vector2(320, 56), 20)
		var armed := [false]
		var disarm := func() -> void:
			armed[0] = false
			reset.text = "RESET RECORDS"
			UI.style_button(reset, Color(1, 1, 1, 0.12), false)
		reset.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				reset.text = "TAP AGAIN TO ERASE"
				UI.style_button(reset, Palette.INVALID, false)
			else:
				disarm.call()
				reset.text = "RECORDS ERASED"
				on_reset.call())
		page.visibility_changed.connect(disarm)
		col.add_child(reset)
	var back := UI.button("BACK", Color(1, 1, 1, 0.15), Vector2(260, 64))
	back.pressed.connect(on_back)
	col.add_child(back)
	return page


static func _slider_row(text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var name_label := UI.label(text, 26)
	name_label.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.get(key)
	slider.custom_minimum_size = Vector2(280, 40)
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = Palette.GOLD
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	slider.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	slider.drag_ended.connect(func(_changed: bool) -> void: Sound.play("coin", 1.0))
	row.add_child(slider)
	return row


static func _toggle_row(text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var name_label := UI.label(text, 26)
	name_label.custom_minimum_size = Vector2(220, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var toggle := UI.button("", Color.WHITE, Vector2(130, 52), 22)
	var refresh := func() -> void:
		var on: bool = Settings.get(key)
		toggle.text = "ON" if on else "OFF"
		UI.style_button(toggle, Palette.DIGITS[4] if on else Color(1, 1, 1, 0.15), false)
	refresh.call()
	toggle.pressed.connect(func() -> void:
		Settings.set_value(key, not Settings.get(key))
		refresh.call())
	row.add_child(toggle)
	return row
