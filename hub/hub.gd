extends Node3D
## The arcade's front door: the main menu, the game picker, records for
## every game and the shared settings, over a slowly orbiting showcase of
## pieces from every game.

const TITLE := "POP ARCADE"
## Showcase pieces: [kind, value] where kind is "tile" (a digit), "chess"
## (a ChessRules piece code), "die" (a face), "mark" (0 for X, 1 for O),
## "disc" (a side) or "ship" (a length).
const SHOWCASE := [["tile", 7], ["chess", 5], ["die", 6], ["disc", 0], ["mark", 0], ["ship", 3], ["tile", 3],
	["chess", 10], ["disc", 1], ["die", 5], ["tile", 9], ["chess", 12], ["ship", 2], ["mark", 1]]
const ORBIT_RADIUS := 4.2

var camera: Camera3D
var _showcase := Node3D.new()
var _items: Array[Node3D] = []
var _pages: Array[Control] = []
var _main: Control
var _games: Control
var _records: Control
var _settings: Control
var _title_letters: Array[Label] = []
var _cards: GridContainer
var _cards_scroll: ScrollContainer
var _best_labels := {}
## Per card: the parts that change between landscape and portrait.
var _card_parts: Array[Dictionary] = []
var _records_grid: GridContainer
var _records_tabs := {}
var _records_game := Arcade.SUDOKU
var _time := 0.0


func _ready() -> void:
	var made := Stage.build(self)
	camera = made.camera
	add_child(_showcase)
	_build_showcase()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_build_main(root)
	_build_games(root)
	_build_records(root)
	_settings = SettingsPage.build(root, func() -> void: _open(_main), _reset_records)
	_pages = [_main, _games, _records, _settings]
	get_viewport().size_changed.connect(_layout)
	_layout()
	Sound.start_music(Sound.ARCADE_MUSIC)
	Sound.set_intensity(0, false)
	debug_page(Arcade.hub_page)
	Arcade.hub_page = "main"


func _process(delta: float) -> void:
	_time += delta
	for i in _title_letters.size():
		var l := _title_letters[i]
		l.position.y = sin(_time * 3.0 - i * 0.6) * 8.0
		l.rotation = sin(_time * 2.0 - i * 0.8) * 0.06
	_showcase.rotation.y = _time * 0.18
	for i in _items.size():
		var item := _items[i]
		item.position.y = 0.4 + 0.35 * sin(_time * 1.6 + i * 1.3)
		item.rotation.y = _time * 0.9 + i
		item.rotation.x = 0.25 * sin(_time * 1.1 + i)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


## Esc / Android back: up one page; from the main menu on a phone, quit.
func _back() -> void:
	if _main.visible:
		if OS.has_feature("mobile"):
			get_tree().quit()
	else:
		_open(_main)


func _open(page: Control) -> void:
	UI.open_page(_pages, page)
	if page == _games:
		_size_cards(get_window().content_scale_factor > 1.0)


func _layout() -> void:
	var portrait := Stage.fit_ui(get_window())
	_cards.columns = 1 if portrait else 3
	for parts: Dictionary in _card_parts:
		_layout_card(parts, portrait)
	_size_cards.call_deferred(portrait)
	for game: String in _records_tabs:
		var tab: Button = _records_tabs[game]
		tab.custom_minimum_size = Vector2(134, 46) if portrait else Vector2(200, 50)
		tab.add_theme_font_size_override("font_size", 15 if portrait else 20)
	camera.look_at_from_position(Vector3(0, 4.5, 9.5 if not portrait else 13.0), Vector3(0, 0.3, 0))


## The cards scroll when they don't all fit (six on a phone). Measured a
## couple of frames late, once the grid has laid its cards out again.
func _size_cards(portrait: bool) -> void:
	if not is_inside_tree() or not _games.visible:
		return
	_cards_scroll.custom_minimum_size = Vector2.ZERO
	for i in 2:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var view := get_viewport().get_visible_rect().size
	var want := _cards.get_combined_minimum_size()
	_cards_scroll.custom_minimum_size = Vector2(want.x, minf(want.y, view.y - (250.0 if portrait else 230.0)))


# --- Pages ---------------------------------------------------------------------------------

func _build_main(root: Control) -> void:
	var made := UI.page(root, 0.35)
	_main = made[0]
	var col: VBoxContainer = made[1]
	col.add_theme_constant_override("separation", 12)
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 0)
	col.add_child(title)
	for i in TITLE.length():
		# Each letter wears a candy colour, like a row of tiles.
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(22 if TITLE[i] == " " else 48, 76)
		var l := UI.label(TITLE[i], 66, Palette.DIGITS[(i * 2) % 9])
		holder.add_child(l)
		title.add_child(holder)
		_title_letters.append(l)
	col.add_child(UI.centered(UI.label("Six candy-coated brain battles", 22, Color(1, 1, 1, 0.85))))
	var play := UI.button("PLAY", Palette.GOLD, Vector2(340, 80), 40)
	play.pressed.connect(func() -> void: _open(_games))
	col.add_child(play)
	var recs := UI.button("RECORDS", Palette.power(Powers.Kind.HAMMER), Vector2(320, 60), 26)
	recs.pressed.connect(func() -> void: _show_records(_records_game))
	col.add_child(recs)
	var sets := UI.button("SETTINGS", Palette.power(Powers.Kind.REROLL), Vector2(320, 60), 26)
	sets.pressed.connect(func() -> void: _open(_settings))
	col.add_child(sets)
	if OS.has_feature("pc"):
		var quit := UI.button("QUIT", Color(1, 1, 1, 0.12), Vector2(180, 48), 20)
		quit.pressed.connect(get_tree().quit)
		col.add_child(quit)


func _build_games(root: Control) -> void:
	var made := UI.page(root, 0.45)
	_games = made[0]
	var col: VBoxContainer = made[1]
	col.add_child(UI.centered(UI.label("PICK A GAME", 44, Palette.GOLD)))
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_cards_scroll)
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 10)
	_cards.add_theme_constant_override("v_separation", 14)
	_cards_scroll.add_child(_cards)
	_cards.add_child(_game_card(Arcade.SUDOKU, Palette.DIGITS[2], [
		["PLAY", Palette.GOLD, func() -> void: Arcade.launch(Arcade.SUDOKU)],
	]))
	_cards.add_child(_game_card(Arcade.CHESS, ChessArt.team_color(1), [
		["VS CPU", Palette.GOLD, func() -> void: Arcade.launch(Arcade.CHESS)],
		["2 PLAYERS", Color("ff4fcf"), func() -> void: Arcade.launch(Arcade.CHESS, false, true)],
	]))
	_cards.add_child(_game_card(Arcade.DICE, DiceArt.CAT_COLORS[DiceRules.Cat.FULL_HOUSE], [
		["VS CPU", Palette.GOLD, func() -> void: Arcade.launch(Arcade.DICE)],
		["2 PLAYERS", Color("ff4fcf"), func() -> void: Arcade.launch(Arcade.DICE, false, true)],
	]))
	_cards.add_child(_game_card(Arcade.FLIP, FlipArt.COLORS[0], [
		["VS CPU", Palette.GOLD, func() -> void: Arcade.launch(Arcade.FLIP)],
		["2 PLAYERS", Color("ff4fcf"), func() -> void: Arcade.launch(Arcade.FLIP, false, true)],
	]))
	_cards.add_child(_game_card(Arcade.FLEET, Color("3fd8f0"), [
		["VS CPU", Palette.GOLD, func() -> void: Arcade.launch(Arcade.FLEET)],
		["2 PLAYERS", Color("ff4fcf"), func() -> void: Arcade.launch(Arcade.FLEET, false, true)],
	]))
	_cards.add_child(_game_card(Arcade.GRID, Palette.DIGITS[4], [
		["PLAY", Palette.GOLD, func() -> void: Arcade.launch(Arcade.GRID)],
	]))
	var back := UI.button("BACK", Color(1, 1, 1, 0.15), Vector2(220, 56), 24)
	back.pressed.connect(func() -> void: _open(_main))
	col.add_child(back)


## One game's card: a live 3D picture of the game (click it to play, "?"
## for how to play) beside its candy-lettered name, tagline, best score and
## play buttons.
func _game_card(game: String, accent: Color, buttons: Array) -> Control:
	var info: Dictionary = Arcade.GAMES[game]
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.07)
	style.set_corner_radius_all(22)
	style.set_border_width_all(3)
	style.border_color = accent
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var inner := BoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var picture := Control.new()
	inner.add_child(picture)
	var preview := GamePreview.new(game)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.pressed.connect(buttons[0][2])
	picture.add_child(preview)
	var how := UI.button("?", Color(1, 1, 1, 0.85), Vector2(40, 40), 22)
	how.anchor_left = 1.0
	how.anchor_right = 1.0
	how.offset_left = -46
	how.offset_right = -6
	how.offset_top = 6
	how.offset_bottom = 46
	how.tooltip_text = "How to play"
	how.pressed.connect(func() -> void: Arcade.launch(game, true))
	picture.add_child(how)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 0)
	col.add_child(name_row)
	var letters: Array[Label] = []
	var name_text: String = info.name
	for i in name_text.length():
		var color: Color = Palette.DIGITS[(i * 2) % 9]
		if game == Arcade.CHESS:
			color = ChessArt.team_color(0) if i < 5 else ChessArt.team_color(1)
		elif game == Arcade.DICE and i < 7:
			color = DiceArt.team_color(0) if i < 3 else DiceArt.team_color(1)
		elif game == Arcade.FLIP:
			color = FlipArt.team_color(0) if i < 4 else FlipArt.team_color(1)
		elif game == Arcade.FLEET:
			color = FleetArt.FLAG if i < 4 else FleetArt.team_color(1)
		var l := UI.label(name_text[i], 40, color)
		name_row.add_child(l)
		letters.append(l)
	var tagline := UI.centered(UI.label(info.tagline, 20, Color(1, 1, 1, 0.85)))
	col.add_child(tagline)
	var best := UI.centered(UI.label("", 20, Palette.GOLD))
	col.add_child(best)
	_best_labels[game] = best
	var row := BoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var play_buttons: Array[Button] = []
	for b: Array in buttons:
		var button := UI.button(b[0], b[1], Vector2(140, 54), 22)
		button.pressed.connect(b[2])
		row.add_child(button)
		play_buttons.append(button)
	_card_parts.append({"inner": inner, "picture": picture, "letters": letters,
		"tagline": tagline, "buttons": play_buttons})
	return card


func _layout_card(parts: Dictionary, portrait: bool) -> void:
	parts.inner.vertical = false
	parts.picture.custom_minimum_size = Vector2(120, 120) if portrait else Vector2(124, 124)
	var letters: Array[Label] = parts.letters
	var long_name := letters.size() > 10
	for l in letters:
		l.label_settings.font_size = (22 if long_name else 26) if portrait else (24 if long_name else 28)
	parts.tagline.label_settings.font_size = 13 if portrait else 13
	var buttons: Array[Button] = parts.buttons
	for b in buttons:
		var wide := buttons.size() == 1
		b.custom_minimum_size = Vector2((200 if wide else 98) if portrait else (210 if wide else 100), 44 if portrait else 44)
		b.add_theme_font_size_override("font_size", 17 if portrait else 16)


func _build_records(root: Control) -> void:
	var made := UI.page(root)
	_records = made[0]
	var col: VBoxContainer = made[1]
	col.add_child(UI.centered(UI.label("RECORDS", 48, Palette.GOLD)))
	var tabs := GridContainer.new()
	tabs.columns = 3
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tabs.add_theme_constant_override("h_separation", 10)
	tabs.add_theme_constant_override("v_separation", 8)
	col.add_child(tabs)
	for game: String in Arcade.GAMES:
		var tab := UI.button(Arcade.GAMES[game].name, Color(1, 1, 1, 0.12), Vector2(200, 50), 20)
		tab.pressed.connect(_show_records.bind(game))
		tabs.add_child(tab)
		_records_tabs[game] = tab
	_records_grid = UI.records_grid()
	col.add_child(_records_grid)
	var back := UI.button("BACK", Color(1, 1, 1, 0.15), Vector2(260, 64))
	back.pressed.connect(func() -> void: _open(_main))
	col.add_child(back)


func _show_records(game: String, highlight: int = -1) -> void:
	_records_game = game
	for g: String in _records_tabs:
		UI.style_button(_records_tabs[g], Palette.GOLD if g == game else Color(1, 1, 1, 0.12), false)
	UI.fill_records(_records_grid, Arcade.records(game), highlight, Arcade.GAMES[game].level)
	if not _records.visible:
		_open(_records)


func _refresh_bests() -> void:
	for game: String in _best_labels:
		var best := Arcade.records(game).best()
		_best_labels[game].text = "BEST  " + UI.thousands(best) if best > 0 else "No record yet"


func _reset_records() -> void:
	for game: String in Arcade.GAMES:
		var r := Records.new()
		r.save(Arcade.GAMES[game].records)
	_refresh_bests()


# --- Showcase --------------------------------------------------------------------------------

func _build_showcase() -> void:
	for i in SHOWCASE.size():
		var spec: Array = SHOWCASE[i]
		var item: Node3D
		if spec[0] == "tile":
			item = TileNode.new(spec[1])
			item.scale = Vector3.ONE * 1.4
		elif spec[0] == "die":
			item = DieNode.new(1 if spec[1] == 5 else 0, spec[1])
			item.scale = Vector3.ONE * 1.4
		elif spec[0] == "mark":
			item = MarkNode.new(spec[1])
			item.scale = Vector3.ONE * 1.5
			item.rotation.x = 0.9
		elif spec[0] == "disc":
			item = DiscNode.new(spec[1])
			item.scale = Vector3.ONE * 1.6
		elif spec[0] == "ship":
			item = FleetArt.ship(spec[1], 1 if spec[1] == 2 else 0)
			item.scale = Vector3.ONE * 1.1
		else:
			item = ChessPieceNode.new(spec[1])
			item.scale = Vector3.ONE * 1.35
		var holder := Node3D.new()
		var a := TAU * i / SHOWCASE.size()
		holder.position = Vector3(cos(a) * ORBIT_RADIUS, 0, sin(a) * ORBIT_RADIUS)
		holder.add_child(item)
		_showcase.add_child(holder)
		_items.append(item)


# --- Developer helpers -------------------------------------------------------------------------

## Opens a page by name: main, games, records or settings.
func debug_page(page: String) -> void:
	_refresh_bests()
	match page:
		"games":
			_open(_games)
		"records":
			_show_records(_records_game)
		"settings":
			_open(_settings)
		_:
			_open(_main)
