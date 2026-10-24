class_name SeaView
extends Node3D
## One sea in Mine Fleet. As the enemy sea it has candy covers over every
## square not yet fired at, numbers on open water, red pegs in hits,
## flags, SONAR readings along its edges, and the sunk ships; as your own
## fleet it has no covers, shows your ships, and marks where the enemy has
## fired. Squares are indexed like FleetRules (y * n + x, row 0 at the far
## side).

## How hard something hit, 0-1; the game turns it into shake and hit-stop.
signal impact(strength: float)

const R := preload("res://fleet/fleet_rules.gd")
const CELL := FleetArt.CELL

var n := 0
var covered := true
## Whose ships are on this sea (their colour).
var owner_side := 1
var fx := Fx.new()
var note_base := 0
var _frame_mat: ShaderMaterial
var _base: Node3D
var _covers := {}
var _numbers := {}
var _pegs := {}
var _ships := {}
var _flags := {}
var _splashes := {}
var _sonar := Node3D.new()
var _items := Node3D.new()
var _hover: MeshInstance3D
var _target: Node3D
var _title: Label3D
var _time := 0.0


func _ready() -> void:
	add_child(_items)
	add_child(_sonar)
	add_child(fx)
	_hover = BoardKit.flat_square(Color(1, 1, 1, 0.22), CELL * 0.92)
	_hover.visible = false
	add_child(_hover)
	_title = BoardKit.flat_label(96)
	add_child(_title)


func _process(delta: float) -> void:
	_time += delta
	for i: int in _pegs:
		var peg: Node3D = _pegs[i]
		peg.set_instance_shader_parameter("glow", 0.9 + 0.4 * sin(_time * 6.0 + i))
	for i: int in _flags:
		var f: Node3D = _flags[i]
		f.rotation.y = 0.25 * sin(_time * 3.0 + i)
	if _target != null:
		_target.get_node("Arrow").position.y = 1.5 + 0.25 * absf(sin(_time * 4.0))
		var s := 1.0 + 0.15 * sin(_time * 6.0)
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


## The sea's box in its parent's space, title included.
func bounds() -> AABB:
	var half := n * CELL * 0.5 + 0.3
	var box := AABB(Vector3(-half, 0, -half - 0.7), Vector3(half * 2 + 0.6, 0.5, half * 2 + 1.3))
	return transform * box


## Rebuilds the sea at size `size`; `cover` puts candy covers on unknown squares.
func setup(size: int, cover: bool, side: int, title: String, title_color: Color) -> void:
	n = size
	covered = cover
	owner_side = side
	if _base != null:
		_base.queue_free()
	var made := BoardKit.base(Vector2(n * CELL + 0.45, n * CELL + 0.45))
	_base = made[0]
	_frame_mat = made[1]
	add_child(_base)
	move_child(_base, 0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL * 0.94, CELL * 0.94)
	var mats := [BoardKit.cell_material(FleetArt.WATER, 0.14), BoardKit.cell_material(FleetArt.WATER_ALT, 0.14)]
	for i in n * n:
		var tile := MeshInstance3D.new()
		tile.mesh = plane
		tile.position = cell_to_local(i) + Vector3(0, 0.003, 0)
		tile.material_override = mats[(i % n + i / n) % 2]
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_base.add_child(tile)
	_title.text = title
	_title.modulate = title_color
	_title.position = Vector3(0, 0.02, -n * CELL * 0.5 - 0.6)
	clear()


func clear() -> void:
	for child in _items.get_children():
		child.queue_free()
	for child in _sonar.get_children():
		child.queue_free()
	_covers.clear()
	_numbers.clear()
	_pegs.clear()
	_ships.clear()
	_flags.clear()
	_splashes.clear()
	set_hover(-1)
	hide_target()


## Shows a side's view exactly, with no animation. `fleet` is the fleet on
## this sea; `seen` what the shooter knows of it. `show_fleet` reveals ships
## that aren't sunk yet (your own fleet against the CPU).
func show_state(fleet: PackedInt32Array, seen: PackedInt32Array, flags: Dictionary, sonar: Dictionary,
		show_fleet: bool) -> void:
	clear()
	for i in n * n:
		var s := seen[i]
		if s == R.UNKNOWN and covered:
			_add_cover(i)
			if flags.has(i):
				set_flag(i, true)
		elif s == R.WATER:
			_add_number(i, R.number(fleet, n, i))
			if not covered:
				_add_splash(i)
		elif s == R.HIT or s == R.SUNK:
			_add_peg(i)
	for id in R.ship_count(fleet):
		var cells := R.ship_cells(fleet, id)
		var sunk := seen[cells[0]] == R.SUNK
		if sunk or show_fleet:
			_add_ship(id, cells, sunk)
	for i: int in sonar:
		show_sonar(i, sonar[i], false)


func set_hover(i: int) -> void:
	_hover.visible = i >= 0
	if i >= 0:
		_hover.position = cell_to_local(i) + Vector3(0, FleetArt.COVER_HEIGHT + 0.02 if _covers.has(i) else 0.02, 0)


func set_flag(i: int, on: bool) -> void:
	if on and not _flags.has(i):
		var f := FleetArt.flag()
		f.position = cell_to_local(i) + Vector3(0, FleetArt.COVER_HEIGHT, 0)
		_items.add_child(f)
		_flags[i] = f
		f.scale = Vector3(1.4, 0.2, 1.4)
		f.create_tween().tween_property(f, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sound.play("hold", 1.2)
	elif not on and _flags.has(i):
		var f: Node3D = _flags[i]
		_flags.erase(i)
		f.queue_free()
		Sound.play("hold", 0.85)


## Tutorial pointer: a pulsing gold ring with a bouncing arrow.
func show_target(i: int) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = cell_to_local(i) + Vector3(0, FleetArt.COVER_HEIGHT, 0)
	add_child(_target)
	var ring := BoardKit.ring(Color(2.4, 2.0, 0.4, 1.0), CELL * 0.45)
	ring.position.y = 0.04
	_target.add_child(ring)
	var arrow := BoardKit.arrow()
	arrow.name = "Arrow"
	_target.add_child(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null


## A SONAR reading: the counts glow at the end of the row and the column.
func show_sonar(i: int, counts: Vector2i, animate: bool = true) -> void:
	var edge := n * CELL * 0.5 + 0.6
	var row := BoardKit.flat_label(150)
	row.text = str(counts.x)
	row.modulate = FleetArt.number_color(counts.x) if counts.x > 0 else Color.WHITE
	row.position = Vector3(edge, 0.05, cell_to_local(i).z)
	var col := BoardKit.flat_label(150)
	col.text = str(counts.y)
	col.modulate = FleetArt.number_color(counts.y) if counts.y > 0 else Color.WHITE
	col.position = Vector3(cell_to_local(i).x, 0.05, edge)
	for l: Label3D in [row, col]:
		l.outline_size = 30
		l.no_depth_test = true
		l.render_priority = 3
		_sonar.add_child(l)
		if animate:
			l.scale = Vector3.ONE * 2.2
			l.create_tween().tween_property(l, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if animate:
		var a := cell_to_local(i)
		fx.beam(Vector3(0, 0, a.z), Vector3(n * CELL, 0.5, 0.3), Color("3fd8f0"), 0.7)
		fx.beam(Vector3(a.x, 0, 0), Vector3(0.3, 0.5, n * CELL), Color("3fd8f0"), 0.7)
		Sound.play("sonar")


func set_fever(on: bool) -> void:
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
		_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)


func set_tint(c: Color) -> void:
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("tint", c)


# --- Animations -------------------------------------------------------------------------

## A shot: a candy bomb drops onto the square, then a splash and the water
## opening, or a blast, a peg and, for a sinking, the ship surfacing.
func animate_fire(result: Dictionary, fleet: PackedInt32Array) -> void:
	set_hover(-1)
	hide_target()
	var i: int = result.at
	var pos := cell_to_local(i)
	var bomb := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	bomb.mesh = s
	bomb.material_override = BoardKit.candy(Color("2a1f63"), 0.32)
	bomb.position = pos + Vector3(0, 4.0, 0)
	add_child(bomb)
	Sound.play("whistle")
	var tw := create_tween()
	tw.tween_property(bomb, "position:y", FleetArt.COVER_HEIGHT if covered else 0.1, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	bomb.queue_free()
	if _flags.has(i):
		set_flag(i, false)
	if result.hit:
		_pop_cover(i, 0.0, true)
		Sound.play("boom")
		fx.sparks(pos + Vector3(0, 0.3, 0), Color("ff8a1f"), 30, 5.0, 1.3)
		fx.debris(pos, FleetArt.COVER, 10)
		fx.ring(pos, FleetArt.HIT, 1.8, 0.4)
		_add_peg(i, true)
		impact.emit(0.5)
		if result.sunk >= 0:
			await get_tree().create_timer(0.3).timeout
			await animate_sink(result.sunk, result.sunk_cells)
			await animate_open(result.opened, fleet)
		else:
			await get_tree().create_timer(0.35).timeout
		return
	Sound.play("splash")
	fx.sparks(pos + Vector3(0, 0.2, 0), Color("6fd6ff"), 18, 3.5, 0.9)
	fx.ring(pos, Color("6fd6ff"), 1.2, 0.35)
	impact.emit(0.15)
	await animate_open(result.opened, fleet)


## Water opening: covers pop off in a wave from the first square, each
## number landing with a note a step higher.
func animate_open(cells: PackedInt32Array, fleet: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var first := cell_to_local(cells[0])
	var longest := 0.0
	for k in cells.size():
		var c := cells[k]
		var dist := cell_to_local(c).distance_to(first)
		var delay := 0.045 * dist + 0.01 * mini(k, 30)
		longest = maxf(longest, delay)
		_pop_cover(c, delay, false)
		var v := R.number(fleet, n, c)
		get_tree().create_timer(delay + 0.08).timeout.connect(func() -> void:
			_add_number(c, v, true)
			if not covered:
				_add_splash(c))
		if k < 14:
			Sound.note_later(delay, note_base + k)
	if cells.size() >= 6:
		Sound.play("whoosh", 1.2, -6.0)
		impact.emit(minf(0.1 + 0.01 * cells.size(), 0.4))
	await get_tree().create_timer(longest + 0.25).timeout


## A sunk ship rises out of the sea, flashing, then sits there.
func animate_sink(id: int, cells: PackedInt32Array) -> void:
	var node := _add_ship(id, cells, true)
	var y := node.position.y
	node.position.y = y - 0.6
	node.scale = Vector3(0.9, 0.2, 0.9)
	Sound.play("sunk")
	Sound.duck(6.0, 0.8)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position:y", y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for c in cells:
		var at := cell_to_local(c)
		fx.beam(at, Vector3(0.8, 2.6, 0.8), Palette.GOLD, 0.7)
		fx.sparks(at + Vector3(0, 0.4, 0), FleetArt.SHIP_COLORS[owner_side], 14, 4.0, 1.0)
	fx.confetti(node.position + Vector3(0, 0.4, 0), Vector3(0.4 * cells.size(), 0, 0.4), 50, 8.0)
	impact.emit(0.7)
	await get_tree().create_timer(0.45).timeout


## The losing fleet goes grey.
func dim_ships() -> void:
	for id: int in _ships:
		var ship: Node3D = _ships[id]
		for part in ship.get_children():
			part.set_instance_shader_parameter("dim", 0.85)


func celebrate() -> void:
	var half := n * CELL * 0.5
	fx.rain(Vector3.ZERO, Vector3(half, 0, half))
	fx.confetti(Vector3(0, 0.3, 0), Vector3(half * 0.8, 0, half * 0.8), 80, 9.0)
	impact.emit(0.5)


func float_text(text: String, i: int, color: Color, size: int = 110) -> void:
	BoardKit.float_text(self, text, cell_to_local(i), color, size)


# --- Pieces ---------------------------------------------------------------------------------

func _add_cover(i: int) -> void:
	var cover := MeshInstance3D.new()
	cover.mesh = FleetArt.cover_mesh()
	cover.position = cell_to_local(i) + Vector3(0, FleetArt.COVER_HEIGHT * 0.5, 0)
	cover.material_override = BoardKit.candy(FleetArt.COVER if (i % n + i / n) % 2 == 0 else FleetArt.COVER_ALT,
		FleetArt.COVER_HEIGHT)
	_items.add_child(cover)
	_covers[i] = cover


## A cover hops, spins and shrinks away.
func _pop_cover(i: int, delay: float, blast: bool) -> void:
	var cover: Node3D = _covers.get(i)
	if cover == null:
		return
	_covers.erase(i)
	var tw := cover.create_tween()
	tw.tween_interval(delay)
	if blast:
		tw.tween_callback(func() -> void: fx.debris(cover.position, FleetArt.COVER, 8))
		tw.tween_property(cover, "scale", Vector3.ZERO, 0.08)
	else:
		tw.tween_property(cover, "position:y", cover.position.y + 0.5, 0.12).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cover, "rotation:y", PI * 0.5, 0.2)
		tw.tween_property(cover, "scale", Vector3.ZERO, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(cover.queue_free)


func _add_number(i: int, v: int, animate: bool = false) -> void:
	if v <= 0 or _numbers.has(i):
		return
	var l := BoardKit.flat_label(130)
	l.text = str(v)
	l.modulate = FleetArt.number_color(v)
	l.outline_size = 26
	l.position = cell_to_local(i) + Vector3(0, 0.02, 0)
	if not covered:
		l.modulate.a = 0.75
	_items.add_child(l)
	_numbers[i] = l
	if animate:
		l.scale = Vector3.ONE * 1.8
		l.create_tween().tween_property(l, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## On your own sea, a ring where the enemy's shot splashed.
func _add_splash(i: int) -> void:
	if _splashes.has(i):
		return
	var ring := BoardKit.ring(Color(0.6, 0.85, 1.0, 0.45), CELL * 0.22)
	ring.position = cell_to_local(i) + Vector3(0, 0.03, 0)
	_items.add_child(ring)
	_splashes[i] = ring


func _add_peg(i: int, animate: bool = false) -> void:
	if _pegs.has(i):
		return
	var peg := FleetArt.hit_peg()
	peg.position = cell_to_local(i) + Vector3(0, FleetArt.SHIP_HEIGHT + 0.12, 0)
	_items.add_child(peg)
	_pegs[i] = peg
	if animate:
		peg.scale = Vector3.ONE * 2.0
		peg.create_tween().tween_property(peg, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _add_ship(id: int, cells: PackedInt32Array, sunk: bool) -> Node3D:
	if _ships.has(id):
		return _ships[id]
	var node := FleetArt.ship(cells.size(), owner_side)
	var center := Vector3.ZERO
	for c in cells:
		center += cell_to_local(c)
	node.position = center / cells.size()
	if cells.size() > 1 and cells[1] - cells[0] != 1:
		node.rotation.y = PI * 0.5
	_items.add_child(node)
	_ships[id] = node
	if sunk:
		for part in node.get_children():
			part.set_instance_shader_parameter("dim", 0.35)
	return node
