class_name GridBoardView
extends Node3D
## Code Grid's board: the n x n grid of candy digit tiles (givens wear a
## gold frame and can't move), red frames on clashing squares, a row of
## peg sockets after each row and under each column that light gold for
## the squares the last check found right, crossed-out digits a TEST
## ruled out, and the animations: tiles popping in, a check scanning the
## rows and columns, a cracked code turning gold, and a failed one flipping
## over to show the answer. Squares are indexed like GridRules.

## How hard something hit, 0-1; the game turns it into shake and hit-stop.
signal impact(strength: float)

const R := preload("res://grid/grid_rules.gd")
const CELL := 1.05
const PEG_GAP := 0.2
const SOCKET_COLOR := Color("140c33")

var n := 0
var fx := Fx.new()
var note_base := 0
## Square -> TileNode
var tiles := {}
var _base: Node3D
var _frame_mat: ShaderMaterial
var _frames := Node3D.new()
var _marks := Node3D.new()
var _pegs := Node3D.new()
## [row pegs per row, column pegs per column]: Arrays of MeshInstance3D.
var _row_pegs: Array = []
var _col_pegs: Array = []
var _hover: MeshInstance3D
var _target: Node3D
var _time := 0.0
var _gold_mat: ShaderMaterial
var _socket_mat: StandardMaterial3D


func _ready() -> void:
	add_child(_frames)
	add_child(_marks)
	add_child(_pegs)
	add_child(fx)
	_hover = BoardKit.flat_square(Color(1, 1, 1, 0.18), CELL * 0.95)
	_hover.visible = false
	add_child(_hover)
	_gold_mat = BoardKit.candy(Palette.GOLD, 0.16)
	_socket_mat = BoardKit.glossy(SOCKET_COLOR)


func _process(delta: float) -> void:
	_time += delta
	if _target != null:
		_target.get_node("Arrow").position.y = 1.6 + 0.25 * absf(sin(_time * 4.0))
		var s := 1.0 + 0.12 * sin(_time * 6.0)
		_target.scale = Vector3(s, 1, s)


func cell_to_local(i: int) -> Vector3:
	var h := (n - 1) * 0.5
	return Vector3((i % n - h) * CELL, 0.0, (i / n - h) * CELL)


func cell_to_world(i: int) -> Vector3:
	return to_global(cell_to_local(i))


func world_to_index(p: Vector3) -> int:
	var l := to_local(p)
	var h := (n - 1) * 0.5
	var x := roundi(l.x / CELL + h)
	var y := roundi(l.z / CELL + h)
	if x < 0 or y < 0 or x >= n or y >= n:
		return -1
	return y * n + x


## The board's box, peg rows included, for the camera.
func bounds() -> AABB:
	var half := n * CELL * 0.5 + 0.3
	var pegs := 0.35 + n * PEG_GAP
	return AABB(Vector3(-half, 0, -half), Vector3(half * 2 + pegs, 0.6, half * 2 + pegs))


## Rebuilds the board for an n x n grid.
func setup(size: int) -> void:
	n = size
	if _base != null:
		_base.queue_free()
	for t: TileNode in tiles.values():
		t.queue_free()
	tiles.clear()
	var pegs := 0.35 + n * PEG_GAP
	var made := BoardKit.base(Vector2(n * CELL + 0.45 + pegs, n * CELL + 0.45 + pegs), Vector3(pegs * 0.5, 0, pegs * 0.5))
	_base = made[0]
	_frame_mat = made[1]
	add_child(_base)
	move_child(_base, 0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL * 0.95, CELL * 0.95)
	var mats := [BoardKit.cell_material(Palette.CELL_A, 0.16), BoardKit.cell_material(Palette.CELL_B, 0.16)]
	# The base is shifted to make room for the pegs; the cells aren't.
	var cells := Node3D.new()
	cells.position = -_base.position
	_base.add_child(cells)
	for i in n * n:
		var cell := MeshInstance3D.new()
		cell.mesh = plane
		cell.position = cell_to_local(i) + Vector3(0, 0.003, 0)
		cell.material_override = mats[(i % n + i / n) % 2]
		cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cells.add_child(cell)
	_build_sockets()
	clear_marks()
	hide_target()
	set_hover(-1)


## Shows the grid exactly: tiles, given frames, clash frames, ruled-out
## digits and the last check's pegs.
func show_grid(grid: PackedInt32Array, givens: Dictionary, conflicts: PackedInt32Array, ruled_out: Dictionary,
		last: Dictionary) -> void:
	for i in grid.size():
		set_tile(i, grid[i], false)
	show_frames(givens, conflicts)
	show_ruled_out(ruled_out)
	show_pegs(last)


## Puts digit `v` on a square (0 clears it), popping it in if `animate`.
func set_tile(i: int, v: int, animate: bool = true) -> void:
	var t: TileNode = tiles.get(i)
	if v == R.EMPTY:
		if t != null:
			tiles.erase(i)
			if animate:
				var tw := t.create_tween()
				tw.tween_property(t, "scale", Vector3.ZERO, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
				tw.tween_callback(t.queue_free)
			else:
				t.queue_free()
		return
	if t == null:
		t = TileNode.new(v)
		t.position = cell_to_local(i)
		add_child(t)
		tiles[i] = t
	elif t.value != v:
		t.set_value(v)
	if animate:
		t.scale = Vector3(1.3, 0.5, 1.3)
		t.create_tween().tween_property(t, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		t.flash(0.2)


## Gold frames round the givens, red round squares that clash.
func show_frames(givens: Dictionary, conflicts: PackedInt32Array) -> void:
	for child in _frames.get_children():
		child.queue_free()
	for i: int in givens:
		var f := BoardKit.outline(Color(2.4, 1.9, 0.4), CELL * 0.97)
		f.position = cell_to_local(i) + Vector3(0, 0.02, 0)
		_frames.add_child(f)
	for i in conflicts:
		var f := BoardKit.outline(Color(2.6, 0.3, 0.5), CELL * 0.93)
		f.position = cell_to_local(i) + Vector3(0, 0.03, 0)
		_frames.add_child(f)


## Small crossed-out digits in the corner of squares a TEST ruled out.
func show_ruled_out(ruled_out: Dictionary) -> void:
	clear_marks()
	for i: int in ruled_out:
		var digits: Array = ruled_out[i]
		var l := BoardKit.flat_label(58)
		l.text = " ".join(digits.map(func(d: int) -> String: return "✕%d" % d))
		l.modulate = Color("ff6b8b")
		l.outline_size = 16
		l.no_depth_test = true
		l.render_priority = 2
		l.position = cell_to_local(i) + Vector3(0, TileArt.TILE_HEIGHT + 0.02, -CELL * 0.33)
		_marks.add_child(l)


func clear_marks() -> void:
	for child in _marks.get_children():
		child.queue_free()


## Lights the pegs for a check's counts ({} turns them all off).
func show_pegs(check: Dictionary) -> void:
	for r in n:
		var row: Array = _row_pegs[r]
		var col: Array = _col_pegs[r]
		for k in n:
			var lit_row: bool = not check.is_empty() and k < check.rows[r]
			var lit_col: bool = not check.is_empty() and k < check.cols[r]
			_light(row[k], lit_row)
			_light(col[k], lit_col)


func set_hover(i: int) -> void:
	_hover.visible = i >= 0
	if i >= 0:
		_hover.position = cell_to_local(i) + Vector3(0, 0.015, 0)


## Tutorial pointer: a pulsing gold ring with a bouncing arrow.
func show_target(i: int) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = cell_to_local(i)
	add_child(_target)
	var ring := BoardKit.ring(Color(2.4, 2.0, 0.4, 1.0), CELL * 0.48)
	ring.position.y = 0.04
	_target.add_child(ring)
	var arrow := BoardKit.arrow()
	arrow.name = "Arrow"
	_target.add_child(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null


func set_fever(on: bool) -> void:
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
		_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)


# --- Animations --------------------------------------------------------------------------

## A check: a beam sweeps down each row then across each column, and its
## pegs pop in gold one by one, each a note higher.
func animate_check(check: Dictionary) -> void:
	show_pegs({})
	Sound.play("scan")
	var step := 0.16
	var k := 0
	for r in n:
		var row_center := Vector3(0, 0, cell_to_local(r * n).z)
		get_tree().create_timer(step * r).timeout.connect(func() -> void:
			fx.beam(row_center, Vector3(n * CELL, 0.4, CELL * 0.8), Color("3fd8f0"), 0.35))
		for p in check.rows[r]:
			_pop_peg(_row_pegs[r][p], step * r + 0.04 * p, k)
			k += 1
	var cols_start := step * n + 0.15
	for c in n:
		var col_center := Vector3(cell_to_local(c).x, 0, 0)
		get_tree().create_timer(cols_start + step * c).timeout.connect(func() -> void:
			fx.beam(col_center, Vector3(CELL * 0.8, 0.4, n * CELL), Color("ff4fcf"), 0.35))
		for p in check.cols[c]:
			_pop_peg(_col_pegs[c][p], cols_start + step * c + 0.04 * p, k)
			k += 1
	await get_tree().create_timer(cols_start + step * n + 0.2).timeout


## Cracked: every tile hops and turns gold-bright in a wave, then confetti.
func animate_crack() -> void:
	set_hover(-1)
	for i: int in tiles:
		var t: TileNode = tiles[i]
		var delay := 0.05 * (i % n + i / n)
		var tw := t.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void:
			t.flash(0.4)
			Sound.note(note_base + 4 + (i % n + i / n))
			fx.sparks(t.position + Vector3(0, 0.5, 0), Palette.GOLD, 10, 3.0, 0.8))
		tw.tween_property(t, "position:y", 0.6, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(t, "rotation:y", TAU, 0.3).from(0.0)
		tw.parallel().tween_property(t, "position:y", 0.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	Sound.play("unlock")
	Sound.duck(8.0, 1.2)
	await get_tree().create_timer(0.05 * 2 * n + 0.5).timeout
	celebrate()


## Failed: the tiles flip over one by one to show the code, wrong ones red.
func animate_reveal(code: PackedInt32Array, grid: PackedInt32Array) -> void:
	for i in code.size():
		var delay := 0.04 * i
		var wrong := grid[i] != code[i]
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if wrong:
				set_tile(i, code[i], true)
				fx.sparks(cell_to_local(i) + Vector3(0, 0.5, 0), Palette.INVALID, 8, 2.5, 0.7)
				Sound.play("tick", 0.8, -4.0)
			elif tiles.has(i):
				tiles[i].flash(0.3))
	await get_tree().create_timer(0.04 * code.size() + 0.4).timeout


func celebrate() -> void:
	var half := n * CELL * 0.5
	fx.rain(Vector3.ZERO, Vector3(half, 0, half))
	fx.confetti(Vector3(0, 0.4, 0), Vector3(half * 0.8, 0, half * 0.8), 90, 9.0)
	impact.emit(0.55)


func float_text(text: String, at: Vector3, color: Color, size: int = 110) -> void:
	BoardKit.float_text(self, text, at, color, size)


# --- Building ------------------------------------------------------------------------------

## A socket per square after every row and under every column; a lit socket
## gets a gold peg.
func _build_sockets() -> void:
	for child in _pegs.get_children():
		child.queue_free()
	_row_pegs.clear()
	_col_pegs.clear()
	var socket := CylinderMesh.new()
	socket.top_radius = 0.075
	socket.bottom_radius = 0.075
	socket.height = 0.04
	socket.radial_segments = 16
	socket.rings = 1
	var peg := SphereMesh.new()
	peg.radius = 0.085
	peg.height = 0.17
	var edge := n * CELL * 0.5 + 0.25
	for r in n:
		var row: Array = []
		var col: Array = []
		for k in n:
			var at_row := Vector3(edge + PEG_GAP * (k + 0.5), 0.01, cell_to_local(r * n).z)
			var at_col := Vector3(cell_to_local(r).x, 0.01, edge + PEG_GAP * (k + 0.5))
			for pair: Array in [[at_row, row], [at_col, col]]:
				var s := MeshInstance3D.new()
				s.mesh = socket
				s.material_override = _socket_mat
				s.position = pair[0]
				_pegs.add_child(s)
				var p := MeshInstance3D.new()
				p.mesh = peg
				p.material_override = _gold_mat
				p.position = pair[0] + Vector3(0, 0.07, 0)
				p.visible = false
				_pegs.add_child(p)
				pair[1].append(p)
		_row_pegs.append(row)
		_col_pegs.append(col)


func _light(peg: MeshInstance3D, on: bool) -> void:
	peg.visible = on
	peg.scale = Vector3.ONE


func _pop_peg(peg: MeshInstance3D, delay: float, k: int) -> void:
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		peg.visible = true
		peg.scale = Vector3.ONE * 2.2
		peg.create_tween().tween_property(peg, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		peg.set_instance_shader_parameter("glow", 1.0)
		Sound.note(note_base + mini(k, 12), -4.0))
