class_name BoardView
extends Node3D
## Draws the board (base, cells, 3x3 lines), its tiles, the ghost preview,
## and plays the animations for each step of a turn.

## How hard something hit, 0-1. The game turns it into shake, hit-stop
## and vibration.
signal impact(strength: float)

const CELL := 1.0
const HALF := (Board.SIZE - 1) * 0.5
const DROP_HEIGHT := 0.9
const CELL_SHADER := preload("res://game/shaders/cell.gdshader")
const NEON_SHADER := preload("res://game/shaders/neon_frame.gdshader")
const SWEEP_STEP := 0.035

## Vector2i -> TileNode
var tiles := {}
var fx := Fx.new()
## Where on the pentatonic ladder this turn's notes start (set per turn
## from the streak, so streaks literally climb).
var note_base := 0
## Pencil marks and jammed outlines (a setting).
var show_hints := true
var _target: Node3D
var _ghosts: Array[TileNode] = []
var _highlighted: Array[TileNode] = []
var _frame_mat: ShaderMaterial
var _hints := Node3D.new()
var _jam_mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_build_base()
	add_child(_hints)
	add_child(fx)


func _process(delta: float) -> void:
	_time += delta
	TileArt.highlight_material().albedo_color.a = 0.28 + 0.2 * sin(_time * 9.0)
	# Tiles about to clear wobble with anticipation; the ghost hovers.
	var wobble := 1.0 + 0.045 * sin(_time * 16.0)
	for t in _highlighted:
		if is_instance_valid(t):
			t.scale = Vector3(wobble, 2.0 - wobble, wobble)
	var bob := 0.03 + 0.05 * (0.5 + 0.5 * sin(_time * 7.0))
	for g in _ghosts:
		g.position.y = bob
	if _jam_mat != null:
		_jam_mat.albedo_color.a = 0.45 + 0.4 * (0.5 + 0.5 * sin(_time * 5.0))
	if _target != null:
		var s := 1.0 + 0.15 * sin(_time * 6.0)
		_target.scale = Vector3(s, 1, s)
		_target.get_node("Arrow").position.y = 1.3 + 0.25 * absf(sin(_time * 4.0))


## Tutorial pointer: a pulsing gold ring with a bouncing arrow over a cell.
func show_target(c: Vector2i) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = cell_to_local(c)
	add_child(_target)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.position.y = 0.05
	ring.scale = Vector3(1, 0.3, 1)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Palette.GOLD * 1.8
	ring.material_override = glow
	_target.add_child(ring)
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	arrow.mesh = cone
	arrow.material_override = glow
	arrow.name = "Arrow"
	_target.add_child(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null


## Redraws the board hints: faint pencil-mark digits in the gaps of nearly
## finished units, and a pulsing red outline around jammed units.
func update_hints(board: Board) -> void:
	for child in _hints.get_children():
		child.queue_free()
	if not show_hints:
		return
	var marks := Rules.pencil_marks(board)
	for c: Vector2i in marks:
		var digits: Array = marks[c]
		if digits.size() > 3:
			continue
		var l := Label3D.new()
		l.text = " ".join(PackedStringArray(digits.map(func(d: int) -> String: return str(d))))
		l.font = TileArt.font()
		l.font_size = 104 if digits.size() == 1 else 72
		l.pixel_size = 0.005
		l.outline_size = 12
		l.outline_modulate = Palette.INK
		l.modulate = Palette.GOLD
		l.rotation_degrees.x = -90.0
		l.position = cell_to_local(c) + Vector3(0, 0.02, 0)
		_hints.add_child(l)
	for u in board.units_in_state(Board.UnitState.JAMMED):
		_outline_unit(u)


func _outline_unit(u: int) -> void:
	var cells: Array = Board.units()[u]
	var lo := cell_to_local(cells[0])
	var hi := lo
	for c: Vector2i in cells:
		lo = lo.min(cell_to_local(c))
		hi = hi.max(cell_to_local(c))
	lo -= Vector3(0.5, 0, 0.5)
	hi += Vector3(0.5, 0, 0.5)
	var w := 0.07
	var size := hi - lo
	var bars := [
		[Vector3(size.x, 0.06, w), Vector3((lo.x + hi.x) * 0.5, 0.5, lo.z)],
		[Vector3(size.x, 0.06, w), Vector3((lo.x + hi.x) * 0.5, 0.5, hi.z)],
		[Vector3(w, 0.06, size.z), Vector3(lo.x, 0.5, (lo.z + hi.z) * 0.5)],
		[Vector3(w, 0.06, size.z), Vector3(hi.x, 0.5, (lo.z + hi.z) * 0.5)],
	]
	for bar: Array in bars:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar[0]
		m.mesh = box
		m.position = bar[1]
		m.material_override = _jam_material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hints.add_child(m)


func _jam_material() -> StandardMaterial3D:
	if _jam_mat == null:
		_jam_mat = StandardMaterial3D.new()
		_jam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_jam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_jam_mat.albedo_color = Color(1.8, 0.2, 0.3, 0.8)
	return _jam_mat


## Fever speeds up the neon frame and turns it up.
func set_fever(on: bool) -> void:
	_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
	_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)


## Confetti rain over the whole board.
func celebrate() -> void:
	fx.rain(Vector3.ZERO, Vector3(4.5, 0, 4.5))
	fx.confetti(Vector3(0, 0.3, 0), Vector3(4, 0, 4), 80, 9.0)
	impact.emit(0.5)


static func cell_to_local(c: Vector2i) -> Vector3:
	return Vector3((c.x - HALF) * CELL, 0.0, (c.y - HALF) * CELL)


func cell_to_world(c: Vector2i) -> Vector3:
	return to_global(cell_to_local(c))


func world_to_cell(p: Vector3) -> Vector2i:
	var l := to_local(p)
	return Vector2i(roundi(l.x / CELL + HALF), roundi(l.z / CELL + HALF))


## Makes the tiles match the board exactly, with no animation.
func sync(board: Board) -> void:
	for i in board.cells.size():
		var c := Board.cell_at_index(i)
		var v := board.cells[i]
		var t: TileNode = tiles.get(c)
		if v == Board.EMPTY:
			if t != null:
				_take(c).queue_free()
			continue
		if t == null:
			t = _spawn(c, v)
		elif t.value != v:
			t.set_value(v)
		t.position = cell_to_local(c)
		t.rotation = Vector3.ZERO
		t.scale = Vector3.ONE
	update_hints(board)


func animate_place(cells: Array, values: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var placed: Array[TileNode] = []
	var tw := create_tween().set_parallel(true)
	for i in cells.size():
		var c: Vector2i = cells[i]
		if tiles.has(c):
			_take(c).queue_free()
		var t := _spawn(c, values[i])
		t.position.y = DROP_HEIGHT
		placed.append(t)
		tw.tween_property(t, "position:y", 0.0, 0.08).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain()
	for t in placed:
		tw.tween_property(t, "scale", Vector3(1.25, 0.68, 1.25), 0.05)
		fx.sparks(t.position + Vector3(0, 0.1, 0), Color(1, 1, 1), 5, 1.6, 0.6)
	tw.tween_callback(impact.emit.bind(0.12))
	tw.tween_callback(Sound.play.bind("place", 1.0, 0.0, 0.06))
	tw.chain()
	for t in placed:
		tw.tween_property(t, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished


## One resolution step, in three beats:
## 1. Solved units light up cell by cell (a sweep), so the player sees why.
## 2. Everything clears at once: popped groups get sucked into their merge
##    cell, blasted tiles and star areas fly off spinning, stones crack.
## 3. Merged tiles burst in with a flash, sparks and a shockwave.
func animate_step(step: Dictionary) -> void:
	var to_anchor := {}
	var biggest := 0
	var stars: Array[Vector2i] = []
	for pop: Dictionary in step.pops:
		biggest = maxi(biggest, pop.cells.size())
		if pop.result == Rules.STAR:
			stars.append(pop.anchor)
		else:
			for c: Vector2i in pop.cells:
				to_anchor[c] = pop.anchor
	var blasted := {}
	for u: int in step.units:
		for c: Vector2i in Board.units()[u]:
			blasted[c] = true

	if not step.units.is_empty():
		await _sweep(step.units)

	var strength := 0.0
	if not step.pops.is_empty():
		strength = 0.2 + 0.05 * (biggest - 3) + 0.12 * step.depth
	if not stars.is_empty():
		strength = maxf(strength, 0.75)
	if not step.units.is_empty():
		strength = maxf(strength, 0.6 + 0.15 * (step.units.size() - 1))
	if strength > 0.0:
		impact.emit(minf(strength, 1.0))
	if not step.units.is_empty() or not stars.is_empty():
		Sound.play("blast" if stars.is_empty() else "star", 1.0, 2.0 * (step.units.size() - 1))
		Sound.duck(6.0, 0.5)
	if not to_anchor.is_empty():
		Sound.play("suck", 1.0, 0.0, 0.05)
	if not step.cracked.is_empty() or not step.broken.is_empty():
		Sound.play("crack", 0.85 if step.broken.size() > 0 else 1.0, 0.0, 0.05)

	for u: int in step.units:
		_blast_unit_fx(u)
	for c in stars:
		var at := cell_to_local(c)
		fx.ring(at, Palette.GOLD, 3.2, 0.5)
		fx.sparks(at + Vector3(0, 0.3, 0), Palette.GOLD, 60, 8.0, 1.4)
		fx.confetti(at, Vector3(1, 0, 1), 40)

	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.05)
	for c: Vector2i in step.cleared:
		if not tiles.has(c):
			continue
		var t := _take(c)
		if to_anchor.has(c) and not blasted.has(c):
			var target := cell_to_local(to_anchor[c]) + Vector3(0, 0.15, 0)
			tw.tween_property(t, "position", target, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(t, "scale", Vector3.ONE * 0.3, 0.16).set_ease(Tween.EASE_IN)
		else:
			fx.sparks(t.position + Vector3(0, 0.3, 0), Palette.tile(t.value), 8, 4.0, 0.8)
			_fly_off(tw, t)
		tw.tween_callback(t.queue_free).set_delay(0.45)
	for c: Vector2i in step.cracked:
		if tiles.has(c):
			var t: TileNode = tiles[c]
			t.set_value(Board.STONE_CRACKED)
			t.flash(0.2)
			t.scale = Vector3(1.2, 0.75, 1.2)
			tw.tween_property(t, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			fx.debris(t.position, Palette.STONE, 8)
	for c: Vector2i in step.broken:
		if tiles.has(c):
			var t := _take(c)
			fx.debris(t.position, Palette.STONE_CRACKED, 18)
			_fly_off(tw, t)
			tw.tween_callback(t.queue_free).set_delay(0.45)
	await tw.finished

	# Each merge rings a note: deeper cascades climb two steps, and several
	# pops in one step stack into a chord.
	var merged := false
	var chord := 0
	for pop: Dictionary in step.pops:
		if pop.result != Rules.STAR:
			Sound.note(note_base + 2 * step.depth + 2 * chord, 1.5 * (pop.cells.size() - 3))
			chord += 1
	for pop: Dictionary in step.pops:
		if pop.result == Rules.STAR:
			continue
		var c: Vector2i = pop.anchor
		if tiles.has(c):
			_take(c).queue_free()
		var t := _spawn(c, pop.result)
		var color := Palette.tile(pop.result)
		t.scale = Vector3.ONE * 0.05
		t.flash(0.35)
		var grow := t.create_tween()
		grow.tween_property(t, "scale", Vector3(1.35, 1.5, 1.35), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		grow.tween_property(t, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		fx.sparks(t.position + Vector3(0, 0.3, 0), color, 16 + 4 * pop.cells.size(), 5.0)
		fx.ring(t.position, color, 1.2 + 0.25 * pop.cells.size(), 0.35)
		merged = true
	if merged:
		await get_tree().create_timer(0.34).timeout


func drop_stone(c: Vector2i) -> void:
	if tiles.has(c):
		_take(c).queue_free()
	var t := _spawn(c, Board.STONE)
	t.position.y = 6.0
	var tw := create_tween()
	tw.tween_property(t, "position:y", 0.0, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		fx.debris(t.position, Palette.STONE, 10)
		Sound.play("thud", 1.0, 0.0, 0.05)
		impact.emit(0.35))
	tw.tween_property(t, "scale", Vector3(1.3, 0.65, 1.3), 0.05)
	tw.tween_property(t, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished


## Extra visuals for a power, played as it goes off (the clearing itself
## is animated by animate_step).
func power_fx(kind: int, target: Vector2i, area: Array) -> void:
	var color := Palette.power(kind)
	var at := cell_to_local(target)
	Sound.play(["laser", "bomb", "nuke", "hammer", "whoosh"][kind])
	Sound.duck(5.0, 0.4)
	match kind:
		Powers.Kind.LASER:
			fx.beam(Vector3(0, 0, at.z), Vector3(9.0, 0.5, 0.8), color, 0.6)
			fx.beam(Vector3(at.x, 0, 0), Vector3(0.8, 0.5, 9.0), color, 0.6)
			impact.emit(0.6)
		Powers.Kind.BOMB:
			fx.ring(at, color, 3.0, 0.5)
			fx.sparks(at + Vector3(0, 0.3, 0), color, 50, 7.0, 1.3)
			impact.emit(0.7)
		Powers.Kind.NUKE:
			for c: Vector2i in area:
				fx.ring(cell_to_local(c), color, 1.4, 0.4)
			impact.emit(0.65)
		Powers.Kind.HAMMER:
			fx.debris(at, Palette.STONE, 16)
			fx.ring(at, color, 1.2, 0.3)
			impact.emit(0.5)


## The run is over: tiles go grey in a diagonal wave with a little hop.
func animate_game_over() -> void:
	Sound.play("game_over")
	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.01)
	for c: Vector2i in tiles:
		var t: TileNode = tiles[c]
		var delay := (c.x + c.y) * 0.04
		tw.tween_callback(t.set_dimmed.bind(true)).set_delay(delay)
		tw.tween_property(t, "position:y", 0.35, 0.1).set_delay(delay).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "position:y", 0.0, 0.18).set_delay(delay + 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	impact.emit(0.45)
	await tw.finished


## Lights up each solved unit one cell after another with a hop and a flash.
func _sweep(units: Array) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.01)
	# The sweep plays the scale upwards, one note per cell (once, even when
	# several units sweep together).
	for i in Board.SIZE:
		tw.tween_callback(Sound.note.bind(note_base + i, -3.0)).set_delay(i * SWEEP_STEP)
	for u: int in units:
		var cells: Array = Board.units()[u]
		for i in cells.size():
			var c: Vector2i = cells[i]
			if not tiles.has(c):
				continue
			var t: TileNode = tiles[c]
			var delay := i * SWEEP_STEP
			tw.tween_callback(t.flash.bind(0.25)).set_delay(delay)
			tw.tween_property(t, "position:y", 0.4, 0.08).set_delay(delay).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "position:y", 0.12, 0.1).set_delay(delay + 0.08).set_ease(Tween.EASE_IN)
	await tw.finished


func _blast_unit_fx(u: int) -> void:
	var cells: Array = Board.units()[u]
	var lo := cell_to_local(cells[0])
	var hi := lo
	for c: Vector2i in cells:
		var p := cell_to_local(c)
		lo = lo.min(p)
		hi = hi.max(p)
	var center := (lo + hi) * 0.5
	var size := hi - lo + Vector3(0.95, 0, 0.95)
	fx.beam(center, Vector3(size.x, 0.6, size.z), Palette.GOLD)
	fx.confetti(center + Vector3(0, 0.3, 0), size * 0.45, 45)
	fx.ring(center, Palette.WILD, 2.6, 0.5)


## Translucent copy of the piece where it would land (red when it can't),
## and a pulsing glow on every tile the placement would clear.
func show_ghost(piece: Piece, origin: Vector2i, valid: bool, preview: Dictionary) -> void:
	hide_ghost()
	var cells := piece.cells_at(origin)
	for i in cells.size():
		var g := TileNode.new(piece.values[i])
		g.position = cell_to_local(cells[i]) + Vector3(0, 0.02, 0)
		g.set_ghost(valid)
		add_child(g)
		_ghosts.append(g)
	if not valid or preview.is_empty():
		return
	for step: Dictionary in preview.steps:
		for c: Vector2i in step.cleared:
			if tiles.has(c):
				var t: TileNode = tiles[c]
				t.set_highlight(true)
				_highlighted.append(t)
			var gi := cells.find(c)
			if gi >= 0:
				_ghosts[gi].set_highlight(true)


func hide_ghost() -> void:
	for g in _ghosts:
		g.queue_free()
	_ghosts.clear()
	for t in _highlighted:
		if is_instance_valid(t):
			t.set_highlight(false)
			t.scale = Vector3.ONE
	_highlighted.clear()


## A label that rises from a cell and fades out.
func float_text(text: String, cell: Vector2i, color: Color, size: int = 110) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = TileArt.font()
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 28
	l.outline_modulate = Palette.INK
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.position = cell_to_local(cell) + Vector3(0, 1.0, 0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 2.6, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


## Launches a tile up and outwards, tumbling, until it shrinks away.
func _fly_off(tw: Tween, t: TileNode) -> void:
	var drift := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	tw.tween_property(t, "position", t.position + drift + Vector3(0, 2.8, 0), 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(t, "rotation", Vector3(randf_range(-3, 3), randf_range(-6, 6), randf_range(-3, 3)), 0.42)
	tw.tween_property(t, "scale", Vector3.ZERO, 0.42).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)


func _spawn(c: Vector2i, v: int) -> TileNode:
	var t := TileNode.new(v)
	t.position = cell_to_local(c)
	add_child(t)
	tiles[c] = t
	return t


func _take(c: Vector2i) -> TileNode:
	var t: TileNode = tiles[c]
	tiles.erase(c)
	return t


func _build_base() -> void:
	# Rainbow neon frame peeking out from under the slab.
	var frame := MeshInstance3D.new()
	frame.mesh = TileArt.rounded_box(Vector3(10.3, 0.4, 10.3), 0.2)
	frame.position.y = -0.34
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = NEON_SHADER
	frame.material_override = _frame_mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)

	# Dark glossy glass slab.
	var slab := MeshInstance3D.new()
	slab.mesh = TileArt.rounded_box(Vector3(9.8, 0.6, 9.8), 0.25)
	slab.position.y = -0.3
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Palette.BOARD
	slab_mat.roughness = 0.12
	slab_mat.metallic = 0.3
	slab_mat.clearcoat_enabled = true
	slab_mat.rim_enabled = true
	slab_mat.rim = 0.4
	slab.material_override = slab_mat
	add_child(slab)

	# Rounded cells, tinted by 3x3 box like a printed Sudoku.
	var cell_mesh := PlaneMesh.new()
	cell_mesh.size = Vector2(0.94, 0.94)
	var mats: Array[ShaderMaterial] = []
	for color: Color in [Palette.CELL_A, Palette.CELL_B]:
		var m := ShaderMaterial.new()
		m.shader = CELL_SHADER
		m.set_shader_parameter("cell_color", color)
		mats.append(m)
	for i in Board.SIZE * Board.SIZE:
		var c := Board.cell_at_index(i)
		var cell := MeshInstance3D.new()
		cell.mesh = cell_mesh
		cell.material_override = mats[(c.x / 3 + c.y / 3) % 2]
		cell.position = cell_to_local(c) + Vector3(0, 0.003, 0)
		cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cell)

	# Glowing lines between the 3x3 boxes.
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Palette.LINE * 1.8
	for k in [-1.5, 1.5]:
		for vertical in [true, false]:
			var bar := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(0.05, 0.03, 9.0) if vertical else Vector3(9.0, 0.03, 0.05)
			bar.mesh = m
			bar.material_override = line_mat
			bar.position = Vector3(k, 0.015, 0) if vertical else Vector3(0, 0.015, k)
			add_child(bar)
