class_name ChessBoardView
extends Node3D
## Merge Mate's board: the glossy 8x8 slab, the pieces, move hints, and the
## animations for moves, captures, merges, spawns, upgrades and checkmate.
## Squares are indexed like ChessRules (y * 8 + x, row 0 at the far side).

## How hard something hit, 0-1; the game turns it into shake and hit-stop.
signal impact(strength: float)

const R := preload("res://chess/chess_rules.gd")
const HALF := 3.5
const CELL_SHADER := preload("res://game/shaders/cell.gdshader")
const NEON_SHADER := preload("res://game/shaders/neon_frame.gdshader")
const LIGHT := Color("3b2e86")
const DARK := Color("221a56")
const LIFT := 0.32
## The words for each tier a merge reaches.
const TIER_WORDS := ["", "", "UPGRADE!", "ROOK!", "QUEEN!!", "EMPRESS!!!"]

## Square index -> ChessPieceNode
var pieces := {}
var fx := Fx.new()
## Where on the pentatonic ladder notes start (set from the streak).
var note_base := 0
var _marks := Node3D.new()
var _pulsing: Array[Node3D] = []
var _selected: ChessPieceNode
var _hover: MeshInstance3D
var _last: Array[MeshInstance3D] = []
var _check: MeshInstance3D
var _target: Node3D
var _frame_mat: ShaderMaterial
var _time := 0.0


func _ready() -> void:
	_build_base()
	add_child(_marks)
	add_child(fx)
	_hover = _flat_square(Color(1, 1, 1, 0.22), 0.96)
	_hover.visible = false
	add_child(_hover)
	_check = _disc(Color(2.2, 0.15, 0.3, 0.75), 0.48)
	_check.visible = false
	add_child(_check)
	for i in 2:
		var m := _flat_square(Color(1.0, 0.85, 0.3, 0.16), 0.94)
		m.visible = false
		add_child(m)
		_last.append(m)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + 0.12 * sin(_time * 7.0)
	for n in _pulsing:
		if is_instance_valid(n):
			n.scale = Vector3(pulse, n.scale.y, pulse)
	if _check.visible:
		_check.scale = Vector3.ONE * (1.0 + 0.2 * sin(_time * 10.0))
	if _selected != null and is_instance_valid(_selected):
		_selected.set_glow(0.8 + 0.4 * sin(_time * 8.0))
	if _target != null:
		var s := 1.0 + 0.15 * sin(_time * 6.0)
		_target.scale = Vector3(s, 1, s)
		_target.get_node("Arrow").position.y = 1.7 + 0.25 * absf(sin(_time * 4.0))


static func cell_to_local(i: int) -> Vector3:
	return Vector3(i % R.SIZE - HALF, 0.0, i / R.SIZE - HALF)


func cell_to_world(i: int) -> Vector3:
	return to_global(cell_to_local(i))


## The square under a world point, or -1 off the board.
func world_to_index(p: Vector3) -> int:
	var l := to_local(p)
	var x := roundi(l.x + HALF)
	var y := roundi(l.z + HALF)
	return R.idx(x, y) if R.in_bounds(x, y) else -1


## Makes the pieces match the board exactly, with no animation. Squares
## past the end of `cells` count as empty, so an empty array clears the board.
func sync(cells: PackedInt32Array) -> void:
	for i in R.CELLS:
		var p := cells[i] if i < cells.size() else R.EMPTY
		var node: ChessPieceNode = pieces.get(i)
		if p == R.EMPTY:
			if node != null:
				pieces.erase(i)
				node.queue_free()
			continue
		if node == null:
			node = _add(i, p)
		elif node.piece != p:
			node.set_piece(p)
		node.position = cell_to_local(i)
		node.rotation = Vector3.ZERO
		node.scale = Vector3.ONE
		node.set_glow(0.0)
		node.set_flash(0.0)
		node.set_dimmed(0.0)


# --- Hints -------------------------------------------------------------------------

## Lifts the chosen piece and marks where it can go: dots for moves, red
## rings for captures, pulsing gold rings for merges.
func show_targets(from: int, targets: PackedInt32Array, cells: PackedInt32Array) -> void:
	clear_targets()
	_selected = pieces.get(from)
	if _selected != null:
		_selected.create_tween().tween_property(_selected, "position:y", LIFT, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var side := R.side_of(cells[from])
	for t in targets:
		var q := cells[t]
		var at := cell_to_local(t)
		if q == R.EMPTY:
			var dot := _disc(Color(ChessArt.team_color(side) * 1.6, 0.85), 0.13)
			dot.position = at + Vector3(0, 0.02, 0)
			_marks.add_child(dot)
		elif R.side_of(q) != side:
			var ring := _ring_mark(Color(2.2, 0.25, 0.35, 0.9), 0.46)
			ring.position = at
			_marks.add_child(ring)
			_pulsing.append(ring)
		else:
			var ring := _ring_mark(Color(2.4, 1.9, 0.4, 0.95), 0.46)
			ring.position = at
			_marks.add_child(ring)
			_pulsing.append(ring)
			var plus := Label3D.new()
			plus.text = "+"
			plus.font = TileArt.font()
			plus.font_size = 120
			plus.pixel_size = 0.006
			plus.outline_size = 24
			plus.outline_modulate = Palette.INK
			plus.modulate = Palette.GOLD
			plus.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plus.no_depth_test = true
			plus.position = at + Vector3(0.32, ChessArt.height(R.type_of(q)) * ChessPieceNode.SIZE + 0.15, 0)
			_marks.add_child(plus)


## Drops the lifted piece back and removes the marks.
func clear_targets() -> void:
	for child in _marks.get_children():
		child.queue_free()
	_pulsing.clear()
	if _selected != null and is_instance_valid(_selected):
		_selected.set_glow(0.0)
		_selected.create_tween().tween_property(_selected, "position:y", 0.0, 0.1)
	_selected = null
	_hover.visible = false


func set_hover(i: int) -> void:
	_hover.visible = i >= 0
	if i >= 0:
		_hover.position = cell_to_local(i) + Vector3(0, 0.012, 0)


func show_last_move(from: int, to: int) -> void:
	for k in 2:
		var i := from if k == 0 else to
		_last[k].visible = i >= 0
		if i >= 0:
			_last[k].position = cell_to_local(i) + Vector3(0, 0.008, 0)


## A pulsing red glow under a king in check (-1 hides it).
func show_check(king: int) -> void:
	_check.visible = king >= 0
	if king >= 0:
		_check.position = cell_to_local(king) + Vector3(0, 0.02, 0)


## Tutorial pointer: a pulsing gold ring with a bouncing arrow over a square.
func show_target(i: int) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = cell_to_local(i)
	add_child(_target)
	var ring := _ring_mark(Color(2.4, 2.0, 0.4, 1.0), 0.5)
	_target.add_child(ring)
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	arrow.mesh = cone
	arrow.material_override = _unshaded(Color(2.4, 2.0, 0.4))
	arrow.name = "Arrow"
	_target.add_child(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null


## Faster, brighter neon frame during Fever.
func set_fever(on: bool) -> void:
	_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
	_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)


## Tints the frame toward the side whose turn it is.
func set_turn_color(c: Color) -> void:
	_frame_mat.set_shader_parameter("tint", c)


# --- Animations --------------------------------------------------------------------

## Plays one action from ChessMatch.act. `dragged` is true when the player
## carried the piece there, so it just drops instead of hopping.
func animate_action(result: Dictionary, dragged: bool = false) -> void:
	clear_targets()
	var from: int = result.from
	var to: int = result.to
	var node: ChessPieceNode = pieces.get(from)
	if node == null:
		return
	pieces.erase(from)
	var victim: ChessPieceNode = pieces.get(to)
	var dest := cell_to_local(to)
	var dist := node.position.distance_to(dest)
	var arc := 0.25 + 0.12 * dist
	if R.type_of(result.piece) == R.KNIGHT or result.kind != "move":
		arc += 0.45
	var time := clampf(0.12 + 0.045 * dist, 0.14, 0.34)
	if dragged:
		arc = 0.0
		time = 0.1
	Sound.play("pickup", 1.0, -4.0, 0.08)
	await _hop(node, dest, arc, time)
	match result.kind:
		"move":
			pieces[to] = node
			Sound.play("move", 1.0, 0.0, 0.1)
			await _land(node, 0.1)
		"capture":
			pieces[to] = node
			_burst(victim, to)
			await _land(node, 0.3)
		"merge":
			if victim != null:
				victim.queue_free()
			pieces[to] = node
			await _merge_reveal(node, to, result.result, R.TIER[R.type_of(result.piece)] == 1)
	if result.promoted:
		await _promote(node, to)
	node.position = dest


func animate_spawn(i: int, p: int) -> void:
	if i < 0:
		return
	var node := _add(i, p)
	node.position.y = 5.0
	node.scale = Vector3(0.6, 1.4, 0.6)
	var tw := create_tween()
	tw.tween_property(node, "position:y", 0.0, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(node, "scale", Vector3.ONE, 0.28)
	tw.tween_callback(func() -> void:
		fx.sparks(cell_to_local(i) + Vector3(0, 0.1, 0), ChessArt.color(p), 10, 2.4, 0.7)
		fx.ring(cell_to_local(i), ChessArt.TRIM[R.side_of(p)], 0.9, 0.3)
		Sound.play("drop", 1.0 + 0.1 * R.side_of(p), 0.0, 0.08)
		impact.emit(0.1))
	tw.tween_property(node, "scale", Vector3(1.3, 0.7, 1.3), 0.05)
	tw.tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished


## The Upgrade power: the piece spins up in a column of light and changes.
func animate_upgrade(at: int, p: int) -> void:
	clear_targets()
	var node: ChessPieceNode = pieces.get(at)
	if node == null:
		return
	var pos := cell_to_local(at)
	fx.beam(pos, Vector3(0.9, 3.0, 0.9), ChessArt.color(p), 0.7)
	Sound.play("upgrade")
	var tw := create_tween()
	tw.tween_property(node, "position:y", 0.8, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(node, "rotation:y", TAU * 2.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	node.rotation.y = 0.0
	await _merge_reveal(node, at, p, R.TIER[R.type_of(node.piece)] == 1)
	node.position = pos


## Mate: the loser's king topples, and the loser's army goes grey.
func animate_mate(loser: int, king: int) -> void:
	var node: ChessPieceNode = pieces.get(king)
	show_check(-1)
	if node != null:
		node.flash(0.4)
		Sound.play("crack", 0.7)
		var tw := create_tween()
		tw.tween_property(node, "rotation:x", deg_to_rad(84.0) * (1 if loser == 0 else -1), 0.55) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(node, "position:y", 0.2, 0.55)
		fx.ring(node.position, Color(1.0, 0.2, 0.3), 3.0, 0.6)
		impact.emit(0.85)
		await tw.finished
	var dim := create_tween().set_parallel(true)
	dim.tween_interval(0.01)
	for i: int in pieces:
		var n: ChessPieceNode = pieces[i]
		if R.side_of(n.piece) == loser:
			dim.tween_method(n.set_dimmed, 0.0, 1.0, 0.4).set_delay(0.03 * (i % 8 + i / 8))
	await dim.finished


## Confetti rain over the whole board.
func celebrate() -> void:
	fx.rain(Vector3.ZERO, Vector3(4.0, 0, 4.0))
	fx.confetti(Vector3(0, 0.3, 0), Vector3(3.5, 0, 3.5), 80, 9.0)
	impact.emit(0.5)


## A label that rises from a square and fades out.
func float_text(text: String, i: int, color: Color, size: int = 110) -> void:
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
	l.position = cell_to_local(i) + Vector3(0, 1.4, 0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 3.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


# --- Animation pieces --------------------------------------------------------------

## Moves a piece to `dest` along an arc of the given height.
func _hop(node: ChessPieceNode, dest: Vector3, arc: float, time: float) -> void:
	var start := node.position
	var lean_axis := Vector3(dest.z - start.z, 0, start.x - dest.x).normalized()
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		node.position = start.lerp(dest, t) + Vector3(0, arc * 4.0 * t * (1.0 - t), 0)
		if lean_axis != Vector3.ZERO:
			node.rotation = lean_axis * -0.35 * sin(t * PI), 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	node.rotation = Vector3.ZERO


## Squash on landing, then spring back.
func _land(node: ChessPieceNode, strength: float) -> void:
	fx.sparks(node.position + Vector3(0, 0.08, 0), Color(1, 1, 1), 5, 1.6, 0.6)
	impact.emit(strength)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.25, 0.72, 1.25), 0.05)
	tw.tween_property(node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished


## A captured piece bursts into its colours and tumbles off the board.
func _burst(victim: ChessPieceNode, at: int) -> void:
	if victim == null:
		return
	var tier: int = maxi(1, R.TIER[R.type_of(victim.piece)])
	var color := ChessArt.color(victim.piece)
	var pos := cell_to_local(at)
	victim.flash(0.2)
	fx.debris(pos, color, 10 + tier * 4)
	fx.sparks(pos + Vector3(0, 0.4, 0), color, 16 + tier * 8, 4.0 + tier, 1.0 + 0.1 * tier)
	fx.ring(pos, color, 1.4 + 0.3 * tier, 0.4)
	Sound.play("capture", 1.15 - 0.07 * tier, 0.0, 0.05)
	if tier >= 3:
		Sound.play("blast", 1.1, -4.0)
	var drift := Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var tw := victim.create_tween().set_parallel(true)
	tw.tween_property(victim, "position", pos + drift + Vector3(0, 2.6, 0), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(victim, "rotation", Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4)), 0.45)
	tw.tween_property(victim, "scale", Vector3.ZERO, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(victim.queue_free)
	impact.emit(0.2 + 0.1 * tier)


## Two twins fuse: squash, a flash, and the new piece springs up. Pawn
## merges spin like a slot machine between knight and bishop first.
func _merge_reveal(node: ChessPieceNode, at: int, result: int, slot_spin: bool) -> void:
	var pos := cell_to_local(at)
	var tier: int = R.TIER[R.type_of(result)]
	var color := ChessArt.color(result)
	Sound.play("suck", 1.2, -2.0)
	var squash := create_tween()
	squash.tween_property(node, "scale", Vector3(1.4, 0.45, 1.4), 0.08)
	await squash.finished
	node.flash(0.35)
	if slot_spin:
		var side := R.side_of(result)
		var spins := 7
		for k in spins:
			node.set_piece(R.piece(R.KNIGHT if k % 2 == 0 else R.BISHOP, side))
			node.scale = Vector3.ONE * 0.9
			node.rotation.y = randf() * TAU
			Sound.play("tick", 1.0 + 0.06 * k, -2.0)
			await get_tree().create_timer(0.045 + 0.012 * k).timeout
		node.rotation.y = 0.0
	node.set_piece(result)
	node.scale = Vector3(0.3, 1.6, 0.3)
	node.position = pos
	for k in tier + 1:
		Sound.note_later(0.05 * k, note_base + k * 2)
	fx.sparks(pos + Vector3(0, 0.5, 0), color, 14 + 8 * tier, 3.5 + tier, 1.0 + 0.1 * tier)
	fx.ring(pos, color, 1.2 + 0.5 * tier, 0.45)
	if tier >= 3:
		fx.beam(pos, Vector3(0.9, 3.5, 0.9), color, 0.6)
		fx.confetti(pos + Vector3(0, 0.6, 0), Vector3(0.3, 0, 0.3), 20 + 15 * tier, 6.0 + tier)
		Sound.play("star", 0.9 + 0.1 * tier, -2.0)
	impact.emit(0.15 + 0.12 * tier)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.3, 1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tw.finished


## A pawn on the far row: a column of light and it becomes a queen.
func _promote(node: ChessPieceNode, at: int) -> void:
	var pos := cell_to_local(at)
	fx.beam(pos, Vector3(0.9, 4.0, 0.9), Palette.GOLD, 0.8)
	Sound.play("level_up")
	await _merge_reveal(node, at, node.piece, false)


func _add(i: int, p: int) -> ChessPieceNode:
	var node := ChessPieceNode.new(p)
	node.position = cell_to_local(i)
	add_child(node)
	pieces[i] = node
	return node


# --- Building ------------------------------------------------------------------------

func _build_base() -> void:
	var frame := MeshInstance3D.new()
	frame.mesh = TileArt.rounded_box(Vector3(9.3, 0.4, 9.3), 0.2)
	frame.position.y = -0.34
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = NEON_SHADER
	frame.material_override = _frame_mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)

	var slab := MeshInstance3D.new()
	slab.mesh = TileArt.rounded_box(Vector3(8.8, 0.6, 8.8), 0.25)
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

	# Checkered cells; each side's two home rows (where its pieces appear)
	# carry a hint of its team colour.
	var cell_mesh := PlaneMesh.new()
	cell_mesh.size = Vector2(0.95, 0.95)
	var mats := {}
	for i in R.CELLS:
		var x := i % R.SIZE
		var y := i / R.SIZE
		var base := LIGHT if (x + y) % 2 == 0 else DARK
		var team := 0 if y >= 6 else (1 if y <= 1 else -1)
		var key := Vector2i((x + y) % 2, team)
		if not mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = CELL_SHADER
			m.set_shader_parameter("cell_color", base.lerp(ChessArt.TRIM[team], 0.13) if team >= 0 else base)
			m.set_shader_parameter("corner", 0.12)
			mats[key] = m
		var cell := MeshInstance3D.new()
		cell.mesh = cell_mesh
		cell.material_override = mats[key]
		cell.position = cell_to_local(i) + Vector3(0, 0.003, 0)
		cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cell)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


func _disc(c: Color, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 32
	m.mesh = cyl
	m.material_override = _unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _ring_mark(c: Color, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.06
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 6
	m.mesh = torus
	m.scale = Vector3(1, 0.3, 1)
	m.position.y = 0.04
	var mat := _unshaded(c)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _flat_square(c: Color, size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	m.mesh = plane
	m.material_override = _unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
