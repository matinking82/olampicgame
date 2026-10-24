class_name FlipBoardView
extends Node3D
## Flip Four's rack: an upright candy board of round holes (candy blocks
## fill some in later rounds) standing on a foot, the discs in it, markers
## over the columns that still take a disc, the hover preview (the column
## lit, a ghost disc where it would land, the discs it would flip pulsing,
## the cells it would lock ringed), and the animations: drops, a wave of
## coin flips, lines locking, the round's count and the rack emptying.
## Cells are indexed like FlipRules (y * w + x, row 0 at the top).

## How hard something hit, 0-1; the game turns it into shake and hit-stop.
signal impact(strength: float)

const R := preload("res://flip/flip_rules.gd")
const CELL := 1.0
## Height of the bottom row's centre above the floor.
const FLOOR := 0.75
const HOLE_COLOR := Color("170f3a")
const BLOCK_COLOR := Color("9a8fd8")

var w := 0
var h := 0
## Cell index -> DiscNode
var discs := {}
var fx := Fx.new()
## Where on the pentatonic ladder notes start (set from the streak).
var note_base := 0
var _rack: Node3D
var _frame_mat: ShaderMaterial
var _blocks := {}
var _markers := Node3D.new()
var _marker_mats: Array[StandardMaterial3D] = []
var _column := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()
var _ghost_mats: Array[StandardMaterial3D] = []
var _hover_label: Label3D
var _lit: Array[int] = []
var _lock_rings := Node3D.new()
var _target: Node3D
var _time := 0.0
var _fever := false
var _tint: Variant = null


func _ready() -> void:
	add_child(_markers)
	add_child(_lock_rings)
	add_child(fx)
	var box := BoxMesh.new()
	box.size = Vector3(CELL * 0.92, 1, 0.05)
	_column.mesh = box
	_column.material_override = BoardKit.unshaded(Color(1, 1, 1, 0.1))
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	add_child(_column)
	_ghost.mesh = FlipArt.disc_mesh()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.basis = FlipArt.face_basis(0)
	for side in 2:
		_ghost_mats.append(BoardKit.unshaded(Color(FlipArt.COLORS[side], 0.45)))
	_ghost.visible = false
	add_child(_ghost)
	_hover_label = BoardKit.billboard("", 70, Palette.GOLD)
	_hover_label.render_priority = 4
	_hover_label.visible = false
	add_child(_hover_label)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.5 + 0.35 * sin(_time * 6.0)
	for k in _marker_mats.size():
		_marker_mats[k].albedo_color.a = pulse
	for k in _markers.get_child_count():
		var m: Node3D = _markers.get_child(k)
		m.position.y = top_y() + 0.9 + 0.08 * sin(_time * 5.0 + k * 0.7)
	for i in _lit:
		var d: DiscNode = discs.get(i)
		if d != null:
			d.set_flash(0.3 + 0.2 * sin(_time * 8.0))
	for ring: Node3D in _lock_rings.get_children():
		ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(_time * 7.0))
	if _target != null:
		_target.get_node("Arrow").position.y = 0.95 + 0.2 * absf(sin(_time * 4.0))


func cell_to_local(i: int) -> Vector3:
	return Vector3((i % w - (w - 1) * 0.5) * CELL, (h - 1 - i / w) * CELL + FLOOR, 0.0)


func cell_to_world(i: int) -> Vector3:
	return to_global(cell_to_local(i))


func column_to_world(col: int) -> Vector3:
	return to_global(Vector3((col - (w - 1) * 0.5) * CELL, top_y() + 0.75, 0.0))


## The centre height of the top row.
func top_y() -> float:
	return (h - 1) * CELL + FLOOR


## The column under a point on the rack's face, or -1. Anything from the
## floor to a little above the rack counts.
func column_at(p: Vector3) -> int:
	var l := to_local(p)
	var col := roundi(l.x / CELL + (w - 1) * 0.5)
	if col < 0 or col >= w or l.y < 0.0 or l.y > top_y() + 1.4:
		return -1
	return col


## The box the camera keeps in view.
func bounds() -> AABB:
	var half := w * CELL * 0.5 + 0.35
	return AABB(Vector3(-half, 0.0, -0.4), Vector3(half * 2.0, top_y() + 1.35, 0.8))


## Makes the rack match exactly, with no animation, rebuilding it when its
## shape or blocks change.
func sync(board: PackedInt32Array, width: int) -> void:
	_build(board, width)
	for i in board.size():
		var o := R.owner(board[i])
		var d: DiscNode = discs.get(i)
		if o < 0:
			if d != null:
				discs.erase(i)
				d.queue_free()
			continue
		if d == null:
			d = _add_disc(i, o)
		d.show_side(o)
		d.set_locked(R.is_locked(board[i]))
		d.position = cell_to_local(i)
		d.scale = Vector3.ONE
		d.set_glow(0.0)
		d.set_dimmed(0.0)
		d.set_flash(0.0)


# --- Hints ----------------------------------------------------------------------------

## Bobbing dots over the columns the side to move can drop in.
func show_columns(cols: PackedInt32Array, side: int) -> void:
	clear_columns()
	var c: Color = FlipArt.COLORS[side]
	for col in cols:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		dot.mesh = sphere
		var m := BoardKit.unshaded(Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 0.7))
		dot.material_override = m
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.position = Vector3((col - (w - 1) * 0.5) * CELL, top_y() + 0.75, 0.0)
		_markers.add_child(dot)
		_marker_mats.append(m)


func clear_columns() -> void:
	for child in _markers.get_children():
		child.queue_free()
	_marker_mats.clear()
	set_hover(-1, {}, 0)


## Previews a drop: the column lit, a ghost disc where it lands, the discs
## it would flip pulsing and the cells it would lock ringed in gold.
func set_hover(col: int, preview: Dictionary, side: int) -> void:
	for k in _lit:
		var d: DiscNode = discs.get(k)
		if d != null:
			d.set_flash(0.0)
	_lit.clear()
	for ring in _lock_rings.get_children():
		ring.queue_free()
	var on := col >= 0 and not preview.is_empty()
	_column.visible = on
	_ghost.visible = on
	_hover_label.visible = on
	if not on:
		return
	var at: int = preview.at
	var x := (col - (w - 1) * 0.5) * CELL
	_column.scale.y = top_y() + 0.5
	_column.position = Vector3(x, (top_y() + 0.5) * 0.5, -0.12)
	_column.material_override.albedo_color = Color(FlipArt.COLORS[side], 0.14)
	_lit.assign(Array(preview.flipped))
	_ghost.material_override = _ghost_mats[side]
	_ghost.position = cell_to_local(at) + Vector3(0, 0, 0.05)
	for c: int in preview.locked:
		var ring := MeshInstance3D.new()
		ring.mesh = FlipArt.ring_mesh()
		ring.rotation.x = PI * 0.5
		ring.material_override = BoardKit.unshaded(Color(2.4, 2.0, 0.4, 0.8))
		ring.position = cell_to_local(c) + Vector3(0, 0, 0.12)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lock_rings.add_child(ring)
	var flips: int = preview.flipped.size()
	var locks: int = preview.locked.size()
	var parts: Array[String] = []
	if flips > 0:
		parts.append("FLIP %d" % flips)
	if locks > 0:
		parts.append("LOCK %d" % locks)
	_hover_label.text = "  ".join(parts)
	_hover_label.modulate = Palette.GOLD if locks > 0 else FlipArt.team_color(side)
	_hover_label.position = cell_to_local(at) + Vector3(0, 0.62, 0.5)


## Tutorial and HINT pointer: a bouncing gold arrow over a column.
func show_target(col: int) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = Vector3((col - (w - 1) * 0.5) * CELL, top_y(), 0.2)
	add_child(_target)
	var arrow := BoardKit.arrow()
	arrow.name = "Arrow"
	arrow.scale = Vector3.ONE * 1.2
	_target.add_child(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null


func set_fever(on: bool) -> void:
	_fever = on
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
		_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)


func set_turn_color(c: Color) -> void:
	_tint = c
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("tint", c)


# --- Animations ------------------------------------------------------------------------

## A move: the disc drops down its column and bounces, the trapped discs
## spin round like coins in a wave outward, then any new lines lock.
func animate_drop(result: Dictionary) -> void:
	clear_columns()
	hide_target()
	var i: int = result.at
	var side: int = result.side
	var dest := cell_to_local(i)
	var color: Color = FlipArt.COLORS[side]
	var disc := _add_disc(i, side)
	var start := Vector3(dest.x, top_y() + 1.2, 0.0)
	disc.position = start
	var fall := sqrt(maxf(start.y - dest.y, 0.1)) * 0.16
	Sound.play("whoosh", 1.5, -10.0)
	var tw := create_tween()
	tw.tween_property(disc, "position:y", dest.y, fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(disc, "position:y", dest.y + 0.18, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(disc, "position:y", dest.y, 0.08).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	Sound.play_later(fall, "place", 1.0 + 0.05 * side)
	await tw.finished
	fx.sparks(dest + Vector3(0, -0.3, 0.2), color, 8, 2.2, 0.6)
	impact.emit(0.12)
	var flipped: PackedInt32Array = result.flipped
	var longest := 0.0
	var order := Array(flipped)
	order.sort_custom(func(a: int, b: int) -> bool: return _steps(i, a) < _steps(i, b))
	for k in order.size():
		var c: int = order[k]
		var delay := 0.05 + 0.08 * (_steps(i, c) - 1) + 0.02 * k
		longest = maxf(longest, delay + 0.36)
		_flip(c, side, delay, k)
	if not order.is_empty():
		await get_tree().create_timer(longest + 0.05).timeout
		impact.emit(minf(0.12 + 0.05 * flipped.size(), 0.6))
	for run: PackedInt32Array in result.runs:
		await animate_lock(run, side, result.locked)


## One disc hops toward the player, spins round like a coin and settles.
func _flip(i: int, side: int, delay: float, k: int) -> void:
	var d: DiscNode = discs.get(i)
	if d == null:
		return
	var home := d.position
	var from := d.body.quaternion
	var tw := d.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		Sound.play("flip", 1.0 + 0.04 * k, -2.0, 0.03)
		Sound.note(note_base + k))
	tw.tween_method(func(t: float) -> void:
		d.position = home + Vector3(0, 0.12 * sin(t * PI), 0.55 * sin(t * PI))
		d.body.quaternion = Quaternion(Vector3.UP, PI * t) * from, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		d.position = home
		d.show_side(side)
		d.flash(0.2)
		fx.sparks(home + Vector3(0, 0, 0.3), FlipArt.COLORS[side], 5, 1.8, 0.6))
	tw.tween_property(d, "scale", Vector3(1.18, 1.18, 0.8), 0.04)
	tw.tween_property(d, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A line locks: a neon bar sweeps along it and each disc gets its gold ring.
func animate_lock(run: PackedInt32Array, side: int, fresh: PackedInt32Array) -> void:
	var a := cell_to_local(run[0])
	var b := cell_to_local(run[run.size() - 1])
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.14, 0.1)
	bar.mesh = box
	var color: Color = FlipArt.COLORS[side]
	bar.material_override = BoardKit.unshaded(Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 0.95))
	bar.position = a.lerp(b, 0.5) + Vector3(0, 0, 0.3)
	bar.rotation.z = atan2(b.y - a.y, b.x - a.x)
	bar.scale = Vector3(0.01, 1, 1)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bar)
	var tw := create_tween()
	tw.tween_property(bar, "scale:x", a.distance_to(b) + CELL * 0.8, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Sound.play("lock")
	for k in run.size():
		var c := run[k]
		var d: DiscNode = discs.get(c)
		var at := cell_to_local(c)
		Sound.note_later(0.08 * k, note_base + 4 + k * 2)
		get_tree().create_timer(0.08 * k).timeout.connect(func() -> void:
			fx.sparks(at + Vector3(0, 0, 0.3), Palette.GOLD, 14, 3.5, 0.9)
			if d != null and is_instance_valid(d):
				d.flash(0.3)
				d.set_locked(true, fresh.has(c)))
	impact.emit(0.5)
	await get_tree().create_timer(0.08 * run.size() + 0.45).timeout
	var fade := bar.create_tween()
	fade.tween_property(bar, "scale:y", 0.0, 0.3)
	fade.tween_callback(bar.queue_free)


## The round's end: every disc lights up in turn as they're counted; then
## the loser's go grey.
func animate_count(board: PackedInt32Array, winner: int) -> void:
	var order: Array[int] = []
	for i in board.size():
		if R.owner(board[i]) >= 0:
			order.append(i)
	var step := minf(0.04, 1.6 / maxf(order.size(), 1.0))
	for k in order.size():
		var d: DiscNode = discs.get(order[k])
		if d != null:
			get_tree().create_timer(step * k, false).timeout.connect(func() -> void:
				if is_instance_valid(d):
					d.flash(0.25)
					var hop := d.create_tween()
					hop.tween_property(d, "position:z", 0.3, 0.07)
					hop.tween_property(d, "position:z", 0.0, 0.12))
		if k % 3 == 0:
			Sound.play_later(step * k, "tick", 1.0 + 0.4 * k / order.size(), -4.0)
	await get_tree().create_timer(step * order.size() + 0.3).timeout
	if winner >= 0:
		dim_side(1 - winner)


func dim_side(side: int) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.01)
	for i: int in discs:
		var d: DiscNode = discs[i]
		if d.side == side:
			tw.tween_method(d.set_dimmed, 0.0, 1.0, 0.4).set_delay(0.01 * (i % 16))


## A new round: the rack's floor opens and every disc drops out, the rack
## is rebuilt for the new shape and blocks, and blocks pop in.
func animate_deal(board: PackedInt32Array, width: int) -> void:
	clear_columns()
	hide_target()
	Sound.play("whoosh", 0.8)
	for i: int in discs.keys():
		var d: DiscNode = discs[i]
		discs.erase(i)
		var tw := d.create_tween()
		tw.tween_interval(0.02 * (i % maxi(w, 1)))
		tw.tween_property(d, "position:y", -3.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(d.queue_free)
	await get_tree().create_timer(0.6).timeout
	_build(board, width, true)
	var k := 0
	for i: int in _blocks:
		var block: Node3D = _blocks[i]
		block.scale = Vector3.ZERO
		block.create_tween().tween_property(block, "scale", Vector3.ONE, 0.3).set_delay(0.08 * k) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sound.play_later(0.08 * k, "deal")
		k += 1
	await get_tree().create_timer(0.3 + 0.08 * k).timeout


func celebrate() -> void:
	var half := w * CELL * 0.5
	fx.rain(Vector3(0, top_y() * 0.5, 0.5), Vector3(half, 0, 0.6))
	fx.confetti(Vector3(0, 0.2, 0.6), Vector3(half, 0, 0.3), 80, 9.0)
	impact.emit(0.5)


func float_text(text: String, i: int, color: Color, size: int = 110) -> void:
	BoardKit.float_text(self, text, cell_to_local(i) + Vector3(0, -0.9, 0.4), color, size)


# --- Building -----------------------------------------------------------------------------

func _add_disc(i: int, side: int) -> DiscNode:
	var old: DiscNode = discs.get(i)
	if old != null:
		old.queue_free()
	var d := DiscNode.new(side)
	d.position = cell_to_local(i)
	add_child(d)
	discs[i] = d
	return d


## King-move steps between two cells.
func _steps(a: int, b: int) -> int:
	return maxi(absi(a % w - b % w), absi(a / w - b / w))


## The rack for this board's shape and blocks. Does nothing if it already
## matches, unless `force`.
func _build(board: PackedInt32Array, width: int, force: bool = false) -> void:
	var height := board.size() / width
	var same := width == w and height == h and not force
	if same:
		for i in board.size():
			if (board[i] == R.BLOCK) != _blocks.has(i):
				same = false
				break
	if same:
		return
	w = width
	h = height
	if _rack != null:
		_rack.queue_free()
	_blocks.clear()
	_rack = Node3D.new()
	add_child(_rack)
	move_child(_rack, 0)
	var size := Vector2(w * CELL + 0.5, h * CELL + 0.5)
	var center_y := FLOOR + (h - 1) * CELL * 0.5

	# The neon frame and the panel stand up behind the discs.
	var frame := MeshInstance3D.new()
	frame.mesh = TileArt.rounded_box(Vector3(size.x + 0.3, size.y + 0.3, 0.3), 0.2)
	frame.position = Vector3(0, center_y, -0.4)
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = BoardKit.NEON_SHADER
	frame.material_override = _frame_mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rack.add_child(frame)
	set_fever(_fever)
	if _tint != null:
		_frame_mat.set_shader_parameter("tint", _tint)
	var panel := MeshInstance3D.new()
	panel.mesh = TileArt.rounded_box(Vector3(size.x, size.y, 0.3), 0.25)
	panel.position = Vector3(0, center_y, -0.3)
	panel.material_override = BoardKit.glossy(Palette.BOARD)
	_rack.add_child(panel)
	var foot := MeshInstance3D.new()
	foot.mesh = TileArt.rounded_box(Vector3(size.x + 0.6, 0.3, 1.4), 0.15)
	foot.position = Vector3(0, -0.02, -0.15)
	foot.material_override = BoardKit.glossy(Color("3a1a6e"))
	_rack.add_child(foot)

	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = FlipArt.RADIUS + 0.05
	hole_mesh.bottom_radius = FlipArt.RADIUS + 0.05
	hole_mesh.height = 0.02
	hole_mesh.radial_segments = 32
	hole_mesh.rings = 1
	var hole_mat := BoardKit.glossy(HOLE_COLOR)
	for i in w * h:
		var at := cell_to_local(i)
		if board[i] == R.BLOCK:
			var block := MeshInstance3D.new()
			block.mesh = TileArt.rounded_box(Vector3(0.82, 0.82, 0.5), 0.16)
			block.material_override = BoardKit.candy(BLOCK_COLOR, 0.82)
			block.position = at
			_rack.add_child(block)
			_blocks[i] = block
			continue
		var hole := MeshInstance3D.new()
		hole.mesh = hole_mesh
		hole.rotation.x = PI * 0.5
		hole.position = at + Vector3(0, 0, -0.14)
		hole.material_override = hole_mat
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rack.add_child(hole)
