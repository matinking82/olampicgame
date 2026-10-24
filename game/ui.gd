class_name UI
extends RefCounted
## Shared building blocks for the HUD and menus, so every screen uses the
## same font, outlines, rounded buttons and panels.


static func label(text: String, size: int, color: Color = Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = TileArt.font()
	s.font_size = size
	s.font_color = color
	s.outline_size = maxi(4, size / 6)
	s.outline_color = Palette.INK
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_offset = Vector2(0, 3)
	l.label_settings = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A chunky rounded button that clicks and squishes when pressed.
static func button(text: String, color: Color, min_size: Vector2 = Vector2(320, 72), font_size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", TileArt.font())
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b, color, false)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * 0.94)
	b.button_up.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(Sound.play.bind("click"))
	return b


static func style_button(b: Button, color: Color, outlined: bool) -> void:
	for state_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(22)
		sb.set_content_margin_all(10)
		match state_name:
			"hover":
				sb.bg_color = color.lightened(0.15)
			"pressed":
				sb.bg_color = color.darkened(0.2)
			"focus":
				sb.draw_center = false
			_:
				sb.bg_color = color
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 0 if state_name == "focus" else 6
		sb.shadow_offset = Vector2(0, 4)
		if outlined:
			sb.set_border_width_all(4)
			sb.border_color = Palette.TEXT
		b.add_theme_stylebox_override(state_name, sb)
	# Dark text only on solid light buttons; see-through ones show the dark backdrop.
	var text_color := Palette.INK if color.get_luminance() > 0.6 and color.a > 0.5 else Palette.TEXT
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, text_color)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))


## A rounded dark-violet card with a gold border.
static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a1f63")
	style.set_corner_radius_all(28)
	style.set_border_width_all(4)
	style.border_color = Palette.GOLD
	style.set_content_margin_all(32)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 16
	return style


## A full-screen page: a dim backdrop with a centred card holding a column.
## Returns [page, column].
static func page(parent: Control, dim: float = 0.7) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	parent.add_child(root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.02, 0.15, dim)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", panel_style())
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	return [root, column]


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## A four-column leaderboard grid: rank, name, score, level.
static func records_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return grid


## Fills a records grid, highlighting one rank in gold. `level_word` labels
## the last column ("Lv" for levels, "Rd" for rounds).
static func fill_records(grid: GridContainer, records: Records, highlight: int, level_word: String = "Lv") -> void:
	for child in grid.get_children():
		child.queue_free()
	if records == null or records.entries.is_empty():
		grid.columns = 1
		grid.add_child(centered(label("No records yet. Go set one!", 24, Color(1, 1, 1, 0.8))))
		return
	grid.columns = 4
	for i in records.entries.size():
		var e: Dictionary = records.entries[i]
		var color := Palette.GOLD if i == highlight else (Palette.TEXT if i > 0 else Palette.DIGITS[1])
		var size := 26 if i == highlight else 22
		grid.add_child(label("%d." % (i + 1), size, color))
		grid.add_child(label(str(e.name), size, color))
		var score := label(thousands(int(e.score)), size, color)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(score)
		grid.add_child(label("%s %d" % [level_word, int(e.level)], size - 4, Color(color, 0.7)))


## Shows one page of a set (or none with null) with a fade and a bouncy card.
static func open_page(pages: Array[Control], page: Control) -> void:
	for p in pages:
		p.visible = p == page
	if page == null:
		return
	page.visible = true
	var card: Control = page.get_child(1).get_child(0)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * 0.85
	page.modulate.a = 0.0
	var tw := page.create_tween().set_parallel(true)
	tw.tween_property(page, "modulate:a", 1.0, 0.18)
	tw.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
