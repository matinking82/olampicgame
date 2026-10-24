class_name GamePreview
extends Panel
## A live little 3D scene showing what a game looks like, for its card in
## the game picker: candy number tiles bouncing on a mini Sudoku board, or
## the two chess armies facing off with pawns hopping, dice bouncing in
## front of a tic-tac-toe board of X and O, discs hopping in an upright
## rack, a little sea of covers, numbers and a ship, or a grid of digit
## tiles with gold pegs. Rendered in its own SubViewport and clipped to a
## rounded card shape. Click it to play.

signal pressed

const R := preload("res://chess/chess_rules.gd")
## A 3x3 Sudoku box with two gaps; 0 is empty.
const SUDOKU_DIGITS := [5, 3, 0, 6, 0, 1, 9, 8, 7]
## A slice of a Merge Mate board, 4 wide and 3 deep: Ice at the back, Sun
## in front.
const CHESS_ROWS := ["kp.r", ".p..", "PPQN"]
## A 3x3 slice of a Tic Tac Roll board: X is 0, O is 1, empty -1; and the dice.
const DICE_MARKS := [0, 1, -1, 1, 0, -1, -1, 1, 0]
const DICE_FACES := [6, 6, 6, 2, 6]
## A slice of a Flip Four rack, top row first: x Sun, o Ice, capitals locked.
const FLIP_ROWS := [".ox.", "xoXo", "oXXx"]
## A corner of a Mine Fleet sea: # covered, a digit open water, s a sunk
## ship square, h a hit.
const FLEET_ROWS := ["#1ss", "#12#", "h#1#", "##1#"]
## A Code Grid corner, with how many each row has right.
const GRID_DIGITS := [1, 2, 3, 3, 1, 2, 2, 3, 1]
const GRID_PEGS := [3, 1, 2]

var _viewport := SubViewport.new()
var _stage := Node3D.new()
var _bobbers: Array[Node3D] = []
var _time := 0.0
var _game: String
var _camera := Camera3D.new()


func _init(game: String) -> void:
	_game = game
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var shape := StyleBoxFlat.new()
	shape.bg_color = Color.WHITE
	shape.set_corner_radius_all(16)
	add_theme_stylebox_override("panel", shape)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)
	_viewport.add_child(_stage)
	_build_world()
	if game == Arcade.SUDOKU:
		_build_sudoku()
	elif game == Arcade.CHESS:
		_build_chess()
	elif game == Arcade.DICE:
		_build_dice()
	elif game == Arcade.FLIP:
		_build_flip()
	elif game == Arcade.FLEET:
		_build_fleet()
	else:
		_build_grid()
	resized.connect(_frame)
	mouse_entered.connect(func() -> void: _punch(1.04))
	mouse_exited.connect(func() -> void: _punch(1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Sound.play("click")
		pressed.emit()


func _process(delta: float) -> void:
	_time += delta
	_stage.rotation.y = 0.35 * sin(_time * 0.5)
	for i in _bobbers.size():
		var node := _bobbers[i]
		# A wave of little hops, each piece a beat after the last.
		var t := fmod(_time * 1.6 - i * 0.22, 2.4)
		node.position.y = 0.45 * maxf(0.0, sin(t * PI)) if t < 1.0 else 0.0
		var squash := 1.0 - 0.15 * maxf(0.0, sin(minf(t, 1.0) * PI * 2.0 + PI))
		node.scale = Vector3(2.0 - squash, squash, 2.0 - squash) * float(node.get_meta("size", 1.0))


func _punch(target: float) -> void:
	pivot_offset = size * 0.5
	create_tween().tween_property(self, "scale", Vector2.ONE * target, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = {Arcade.SUDOKU: Color("2b1d6b"), Arcade.CHESS: Color("16205e"), Arcade.DICE: Color("3a1660"),
		Arcade.FLIP: Color("2a1450"), Arcade.FLEET: Color("10285a"), Arcade.GRID: Color("231a5e")}[_game]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8a8ff")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 4.0, 4.9), Vector3(0, 0.3, 0.15))


## Wide pictures frame the scene by height, square ones by width, so the
## pieces fill the card without being cut off.
func _frame() -> void:
	if size.x >= size.y * 1.3:
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.fov = 34.0
	else:
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		_camera.fov = 44.0 if _game == Arcade.CHESS else 40.0


func _slab(size: Vector3, color: Color) -> MeshInstance3D:
	var slab := MeshInstance3D.new()
	slab.mesh = TileArt.rounded_box(size, 0.18)
	slab.position.y = -size.y * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.12
	m.clearcoat_enabled = true
	m.rim_enabled = true
	m.rim = 0.4
	slab.material_override = m
	return slab


func _build_sudoku() -> void:
	_stage.add_child(_slab(Vector3(3.5, 0.35, 3.5), Palette.BOARD))
	for i in SUDOKU_DIGITS.size():
		var at := Vector3(i % 3 - 1, 0, i / 3 - 1) * 1.05
		var cell := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.95, 0.95)
		cell.mesh = plane
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Palette.CELL_B
		cell.material_override = cm
		cell.position = at + Vector3(0, 0.004, 0)
		_stage.add_child(cell)
		if SUDOKU_DIGITS[i] != 0:
			var tile := TileNode.new(SUDOKU_DIGITS[i])
			tile.position = at
			_stage.add_child(tile)
			_bobbers.append(tile)


func _build_chess() -> void:
	var w: int = CHESS_ROWS[0].length()
	var d := CHESS_ROWS.size()
	_stage.add_child(_slab(Vector3(w + 0.5, 0.35, d + 0.5), Palette.BOARD))
	var cells := R.from_rows(CHESS_ROWS)
	for y in d:
		for x in w:
			var at := Vector3(x - (w - 1) * 0.5, 0, y - (d - 1) * 0.5)
			var cell := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(0.95, 0.95)
			cell.mesh = plane
			var cm := StandardMaterial3D.new()
			cm.albedo_color = ChessBoardView.LIGHT if (x + y) % 2 == 0 else ChessBoardView.DARK
			cell.material_override = cm
			cell.position = at + Vector3(0, 0.004, 0)
			_stage.add_child(cell)
			var p := cells[R.idx(x, y)]
			if p != R.EMPTY:
				var node := ChessPieceNode.new(p)
				node.position = at
				_stage.add_child(node)
				_bobbers.append(node)


func _build_dice() -> void:
	_stage.add_child(_slab(Vector3(3.6, 0.35, 3.9), Palette.BOARD))
	for i in DICE_MARKS.size():
		var at := Vector3(i % 3 - 1, 0, i / 3 - 1) * 0.95 + Vector3(0, 0, -0.45)
		var cell := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.84, 0.84)
		cell.mesh = plane
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Palette.CELL_B
		cell.material_override = cm
		cell.position = at + Vector3(0, 0.004, 0)
		_stage.add_child(cell)
		if DICE_MARKS[i] >= 0:
			var mark := MarkNode.new(DICE_MARKS[i])
			mark.set_meta("size", 0.9)
			_bobbers.append(mark)
			mark.position = at
			_stage.add_child(mark)
	for d in DICE_FACES.size():
		var die := DieNode.new(0, DICE_FACES[d])
		die.set_meta("size", 0.52)
		die.position = Vector3((d - 2) * 0.5, 0, 1.4)
		die.show_value(DICE_FACES[d], [0.2, -0.15, 0.1, -0.25, 0.15][d])
		_stage.add_child(die)
		_bobbers.append(die)


## A bobbing piece sits in a holder, so its hop starts from where it stands.
func _hold(piece: Node3D, at: Vector3, size: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	_stage.add_child(holder)
	holder.add_child(piece)
	piece.set_meta("size", size)
	_bobbers.append(piece)


func _build_flip() -> void:
	var w: int = FLIP_ROWS[0].length()
	var h := FLIP_ROWS.size()
	var gap := 0.78
	var panel := _slab(Vector3(w * gap + 0.4, h * gap + 0.4, 0.25), Palette.BOARD)
	panel.position = Vector3(0, h * gap * 0.5 + 0.05, -0.3)
	_stage.add_child(panel)
	_stage.add_child(_slab(Vector3(w * gap + 0.8, 0.25, 1.2), Color("3a1a6e")))
	for y in h:
		var row: String = FLIP_ROWS[y]
		for x in w:
			var ch := row[x]
			if ch == ".":
				continue
			var disc := DiscNode.new(0 if ch.to_lower() == "x" else 1)
			disc.set_locked(ch == "X" or ch == "O")
			_hold(disc, Vector3((x - (w - 1) * 0.5) * gap, (h - 1 - y) * gap + 0.4, -0.1), 0.85)


func _build_fleet() -> void:
	var n := FLEET_ROWS.size()
	_stage.add_child(_slab(Vector3(n + 0.4, 0.35, n + 0.4), Palette.BOARD))
	for y in n:
		var row: String = FLEET_ROWS[y]
		for x in n:
			var at := Vector3(x - (n - 1) * 0.5, 0, y - (n - 1) * 0.5) * 0.95
			var cell := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(0.88, 0.88)
			cell.mesh = plane
			var cm := StandardMaterial3D.new()
			cm.albedo_color = FleetArt.WATER
			cell.material_override = cm
			cell.position = at + Vector3(0, 0.004, 0)
			_stage.add_child(cell)
			var ch := row[x]
			if ch == "#":
				var cover := MeshInstance3D.new()
				cover.mesh = FleetArt.cover_mesh()
				cover.position.y = FleetArt.COVER_HEIGHT * 0.5
				cover.material_override = BoardKit.candy(FleetArt.COVER, FleetArt.COVER_HEIGHT)
				_hold(cover, at, 1.0)
			elif ch == "h":
				var peg := FleetArt.hit_peg()
				peg.position.y = 0.25
				_hold(peg, at, 1.0)
			elif ch != "s":
				var l := BoardKit.flat_label(130)
				l.text = ch
				l.modulate = FleetArt.number_color(int(ch))
				l.outline_size = 26
				l.position = at + Vector3(0, 0.02, 0)
				_stage.add_child(l)
	var ship := FleetArt.ship(2, 1)
	ship.position = Vector3(1.0, 0, -1.5) * 0.95
	_stage.add_child(ship)


func _build_grid() -> void:
	_stage.add_child(_slab(Vector3(3.9, 0.35, 3.4), Palette.BOARD))
	for i in GRID_DIGITS.size():
		var at := Vector3(i % 3 - 1.25, 0, i / 3 - 1) * 1.02
		var cell := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.95, 0.95)
		cell.mesh = plane
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Palette.CELL_B
		cell.material_override = cm
		cell.position = at + Vector3(0, 0.004, 0)
		_stage.add_child(cell)
		var tile := TileNode.new(GRID_DIGITS[i])
		tile.position = at
		_stage.add_child(tile)
		_bobbers.append(tile)
	var peg_mesh := SphereMesh.new()
	peg_mesh.radius = 0.1
	peg_mesh.height = 0.2
	for r in 3:
		for k in 3:
			var peg := MeshInstance3D.new()
			peg.mesh = peg_mesh
			var lit: bool = k < GRID_PEGS[r]
			peg.material_override = BoardKit.candy(Palette.GOLD if lit else Color("140c33"), 0.2)
			peg.position = Vector3(1.6 + 0.24 * k, 0.1, (r - 1) * 1.02)
			_stage.add_child(peg)
