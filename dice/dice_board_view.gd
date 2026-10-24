class_name DiceBoardView
extends Node3D
## Tic Tac Roll's table: the 4x4 board of category cells, the X and O marks
## with the score each was claimed with, the dice tray in front, and the
## animations for rolls, holds, claims, steals, lines and new rounds.
## Cells are indexed like DiceRules (y * 4 + x, row 0 at the far side).

## How hard something hit, 0-1; the game turns it into shake and hit-stop.
signal impact(strength: float)

const R := preload("res://dice/dice_rules.gd")
const CELL_SHADER := preload("res://game/shaders/cell.gdshader")
const NEON_SHADER := preload("res://game/shaders/neon_frame.gdshader")
const CELL := 1.3
const CELL_SIZE := 1.2
## The dice sit in a row in the tray; held dice slide forward toward the board.
const TRAY_Z := 3.8
const DIE_GAP := 0.98
const HOLD_SHIFT := -0.12
## Held dice also rise a little off the tray.
const HOLD_LIFT := 0.16
const STEAL_COLOR := Color("ff4f8b")

## Cell index -> MarkNode
var marks := {}
var dice: Array[DieNode] = []
var fx := Fx.new()
## Where on the pentatonic ladder notes start (set from the streak).
var note_base := 0
var _cells: Array[Node3D] = []
var _names: Array[Label3D] = []
var _rules: Array[Label3D] = []
var _minis: Array[DieNode] = []
var _cats_shown := PackedInt32Array()
## Cells whose rule line an option label is covering.
var _hidden_rules: Array[int] = []
var _badges := {}
var _hold_rings: Array[MeshInstance3D] = []
var _options := Node3D.new()
var _option_mats: Array[StandardMaterial3D] = []
var _hover: MeshInstance3D
var _target: Node3D
var _die_arrows: Array[Node3D] = []
var _frame_mat: ShaderMaterial
var _cell_mats := {}
var _held: Array[bool] = [false, false, false, false, false]
var _time := 0.0


func _ready() -> void:
	_build_base()
	add_child(_options)
	add_child(fx)
	_hover = _flat_square(Color(1, 1, 1, 0.2), CELL_SIZE * 0.98)
	_hover.visible = false
	add_child(_hover)
	for d in R.DICE:
		var ring := _disc(Color(2.4, 1.9, 0.4, 0.9), 0.5)
		ring.visible = false
		add_child(ring)
		_hold_rings.append(ring)
		var die := DieNode.new(0, d + 1)
		die.position = die_slot(d)
		add_child(die)
		dice.append(die)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.1 + 0.07 * sin(_time * 7.0)
	for m in _option_mats:
		m.albedo_color.a = pulse
	for d in R.DICE:
		_hold_rings[d].position = Vector3(dice[d].position.x, 0.02, dice[d].position.z)
		if _held[d]:
			dice[d].set_glow(0.7 + 0.3 * sin(_time * 6.0 + d))
	if _target != null:
		var s := 1.0 + 0.15 * sin(_time * 6.0)
		_target.scale = Vector3(s, 1, s)
		_target.get_node("Arrow").position.y = 1.6 + 0.25 * absf(sin(_time * 4.0))
	for a in _die_arrows:
		a.position.y = 1.35 + 0.2 * absf(sin(_time * 4.0))


static func cell_to_local(i: int) -> Vector3:
	return Vector3((i % R.SIZE - 1.5) * CELL, 0.0, (i / R.SIZE - 1.5) * CELL)


static func die_slot(d: int, held: bool = false) -> Vector3:
	return Vector3((d - 2) * DIE_GAP, HOLD_LIFT if held else 0.0, TRAY_Z + (HOLD_SHIFT if held else 0.0))


func cell_to_world(i: int) -> Vector3:
	return to_global(cell_to_local(i))


func die_to_world(d: int) -> Vector3:
	return to_global(dice[d].position + Vector3(0, DiceArt.DIE_SIZE * 0.5, 0))


## The cell under a world point (on the board's surface), or -1.
func world_to_index(p: Vector3) -> int:
	var l := to_local(p)
	var x := roundi(l.x / CELL + 1.5)
	var y := roundi(l.z / CELL + 1.5)
	if not R.in_bounds(x, y):
		return -1
	var c := cell_to_local(R.idx(x, y))
	if absf(l.x - c.x) > CELL_SIZE * 0.5 or absf(l.z - c.z) > CELL_SIZE * 0.5:
		return -1
	return R.idx(x, y)


## The die under a world point (at dice height), or -1.
func die_at(p: Vector3) -> int:
	var l := to_local(p)
	var best := -1
	var best_d := 0.6
	for d in R.DICE:
		var dist := Vector2(l.x - dice[d].position.x, l.z - dice[d].position.z).length()
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Makes the board and dice match the match exactly, with no animation.
func sync(m: DiceMatch) -> void:
	for i in R.CELLS:
		_set_category(i, m.cats[i])
		_cells[i].rotation = Vector3.ZERO
		var who := m.owners[i]
		var node: MarkNode = marks.get(i)
		if node != null and (who == R.NONE or node.side != who):
			marks.erase(i)
			node.queue_free()
			node = null
		if who != R.NONE:
			if node == null:
				node = _add_mark(i, who)
			node.position = cell_to_local(i)
			node.scale = Vector3.ONE
			node.set_glow(0.0)
			node.set_dimmed(0.0)
		_set_badge(i, who, m.marks[i])
	sync_dice(m)


func sync_dice(m: DiceMatch, fever: bool = false) -> void:
	for d in R.DICE:
		var die := dice[d]
		die.set_side(m.turn, fever)
		die.show_value(m.dice[d], _yaw(d))
		die.scale = Vector3.ONE
		die.set_dimmed(0.0)
		die.set_flash(0.0)
		_held[d] = m.held[d] and m.rolled
		die.position = die_slot(d, _held[d])
		die.set_glow(0.0)
		_hold_rings[d].visible = _held[d]


## Dice for a new turn: the mover's colour, all back in the tray.
func reset_dice(side: int, fever: bool) -> void:
	for d in R.DICE:
		_held[d] = false
		_hold_rings[d].visible = false
		var die := dice[d]
		die.set_glow(0.0)
		die.set_side(side, fever)
		die.set_dimmed(0.0)
		var tw := die.create_tween()
		tw.tween_property(die, "position", die_slot(d), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Hints -------------------------------------------------------------------------

## Lights the cells the dice can claim, with the points each would score
## printed along its bottom edge: gold rings for free cells, pink to steal.
func show_options(m: DiceMatch) -> void:
	clear_options()
	for i in m.options():
		var stealing := m.owners[i] != R.NONE
		var color := STEAL_COLOR if stealing else Palette.GOLD
		# The whole cell glows (pulsed in _process); the points sit on its
		# bottom edge, above any mark on it.
		var glow := _flat_square(Color(color, 0.15), CELL_SIZE * 0.97)
		var mat: StandardMaterial3D = glow.material_override
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.position = cell_to_local(i) + Vector3(0, 0.02, 0)
		_options.add_child(glow)
		_option_mats.append(mat)
		var frame := _outline(Color(color.r * 2.2, color.g * 2.2, color.b * 2.2), CELL_SIZE * 0.97)
		frame.position = cell_to_local(i) + Vector3(0, 0.025, 0)
		_options.add_child(frame)
		var s := R.score(m.cats[i], m.dice)
		var label := _flat_label(50)
		label.text = ("STEAL %d" if stealing else "+%d") % s
		label.modulate = color
		label.outline_size = 20
		label.no_depth_test = true
		label.render_priority = 3
		label.position = cell_to_local(i) + Vector3(0, DiceArt.MARK_HEIGHT + 0.05, 0.44)
		_options.add_child(label)
		_rules[i].visible = false
		_hidden_rules.append(i)


func clear_options() -> void:
	for child in _options.get_children():
		child.queue_free()
	_option_mats.clear()
	_hover.visible = false
	for i in _hidden_rules:
		_rules[i].visible = not marks.has(i)
	_hidden_rules.clear()


func set_hover(i: int) -> void:
	_hover.visible = i >= 0
	if i >= 0:
		_hover.position = cell_to_local(i) + Vector3(0, 0.015, 0)


## Tutorial pointer: a pulsing gold ring with a bouncing arrow over a cell.
func show_target(i: int) -> void:
	hide_target()
	_target = Node3D.new()
	_target.position = cell_to_local(i)
	add_child(_target)
	_target.add_child(_ring_mark(Color(2.4, 2.0, 0.4, 1.0), CELL_SIZE * 0.55))
	var arrow := _arrow()
	arrow.name = "Arrow"
	_target.add_child(arrow)


## Tutorial pointers over dice.
func show_die_targets(which: Array) -> void:
	hide_target()
	for d: int in which:
		var arrow := _arrow()
		arrow.scale = Vector3.ONE * 0.8
		arrow.position = Vector3(die_slot(d).x, 1.35, die_slot(d).z)
		add_child(arrow)
		_die_arrows.append(arrow)


func hide_target() -> void:
	if _target != null:
		_target.queue_free()
		_target = null
	for a in _die_arrows:
		a.queue_free()
	_die_arrows.clear()


## Faster, brighter neon frame during Fever, and rainbow dice.
func set_fever(on: bool, side: int) -> void:
	_frame_mat.set_shader_parameter("speed", 0.35 if on else 0.06)
	_frame_mat.set_shader_parameter("energy", 4.0 if on else 2.6)
	for die in dice:
		die.set_side(side, on)


## Tints the frame toward the side whose turn it is.
func set_turn_color(c: Color) -> void:
	_frame_mat.set_shader_parameter("tint", c)


# --- Animations --------------------------------------------------------------------

## Throws the dice that aren't held: they tumble in from the front, bounce
## twice and land showing their new faces.
func animate_roll(moved: PackedInt32Array, values: PackedInt32Array) -> void:
	clear_options()
	Sound.play("roll", 1.0, 0.0, 0.08)
	var longest := 0.0
	for k in moved.size():
		var d := moved[k]
		var die := dice[d]
		_held[d] = false
		_hold_rings[d].visible = false
		die.set_glow(0.0)
		var dest := die_slot(d)
		var start := dest + Vector3(randf_range(-0.5, 0.5), 0.0, 1.4)
		var final := Quaternion(DiceArt.face_basis(values[d], _yaw(d)))
		var axis := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
		var spin := randf_range(2.5, 4.0) * TAU
		var time := 0.62 + 0.05 * k
		longest = maxf(longest, time)
		var tw := die.create_tween()
		tw.tween_method(func(t: float) -> void:
			die.position = start.lerp(dest, 1.0 - pow(1.0 - t, 2.0))
			die.position.y = 1.7 * pow(1.0 - t, 2.0) * absf(cos(PI * 2.5 * t))
			die.body.quaternion = Quaternion(axis, spin * pow(1.0 - t, 2.0)) * final, 0.0, 1.0, time)
		for hit: float in [0.2, 0.6, 1.0]:
			Sound.play_later(time * hit, "clack", 1.0 + 0.08 * k + randf_range(-0.05, 0.05), -3.0 * (1.0 - hit))
		tw.tween_callback(func() -> void:
			die.value = values[d]
			fx.sparks(dest + Vector3(0, 0.1, 0), DiceArt.DIE_COLORS[maxi(die.side, 0)], 5, 1.6, 0.6))
		tw.tween_property(die, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		tw.tween_property(die, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(longest + 0.12).timeout
	impact.emit(0.12)


## A held die slides forward and glows; a released one slides back.
func set_held(d: int, on: bool) -> void:
	_held[d] = on
	_hold_rings[d].visible = on
	var die := dice[d]
	if not on:
		die.set_glow(0.0)
	Sound.play("hold", 1.15 if on else 0.9, 0.0, 0.03)
	var dest := die_slot(d, on)
	var start := die.position
	var tw := die.create_tween()
	tw.tween_method(func(t: float) -> void:
		die.position = start.lerp(dest, t) + Vector3(0, 0.35 * sin(t * PI), 0), 0.0, 1.0, 0.16)
	tw.tween_property(die, "scale", Vector3(1.15, 0.85, 1.15), 0.04)
	tw.tween_property(die, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Nudge: the die hops, turns over and lands one pip higher.
func animate_nudge(d: int, v: int) -> void:
	var die := dice[d]
	var base := die.position
	var from := die.body.quaternion
	var to := Quaternion(DiceArt.face_basis(v, _yaw(d)))
	fx.beam(base, Vector3(0.8, 2.2, 0.8), Color("ff4fcf"), 0.5)
	Sound.play("upgrade", 1.3, -4.0)
	var tw := die.create_tween()
	tw.tween_method(func(t: float) -> void:
		die.position = base + Vector3(0, 0.9 * sin(t * PI), 0)
		die.body.quaternion = from.slerp(to, t), 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		die.value = v
		die.flash(0.25)
		Sound.play("clack", 1.2)
		fx.sparks(base + Vector3(0, 0.3, 0), Color("ff4fcf"), 12, 2.5, 0.8)
		impact.emit(0.15))
	await tw.finished


## Five of a kind on the dice: a rainbow flash, light and confetti.
func animate_jackpot() -> void:
	for d in R.DICE:
		dice[d].flash(0.6)
		fx.beam(dice[d].position, Vector3(0.8, 3.5, 0.8), Palette.DIGITS[d * 2], 0.8)
	fx.confetti(Vector3(0, 0.5, TRAY_Z), Vector3(2.2, 0, 0.3), 90, 9.0)
	Sound.play("jackpot")
	Sound.duck(8.0, 1.2)
	impact.emit(0.7)


## Nothing fits: the dice go grey and shiver.
func animate_bust() -> void:
	clear_options()
	Sound.play("bust")
	for d in R.DICE:
		var die := dice[d]
		die.create_tween().tween_method(die.set_dimmed, 0.0, 0.85, 0.3)
		var x := die.position.x
		var tw := die.create_tween()
		for k in 4:
			tw.tween_property(die, "position:x", x + (0.08 if k % 2 == 0 else -0.08), 0.05)
		tw.tween_property(die, "position:x", x, 0.05)
	impact.emit(0.2)
	await get_tree().create_timer(0.7).timeout


## A claim: a stolen mark bursts off first, then the new X or O drops in
## with the score it was claimed with.
func animate_claim(result: Dictionary) -> void:
	clear_options()
	var i: int = result.at
	var side: int = result.side
	var pos := cell_to_local(i)
	var color: Color = DiceArt.MARK_COLORS[side]
	if result.stolen:
		var old: MarkNode = marks.get(i)
		marks.erase(i)
		_set_badge(i, R.NONE, 0)
		if old != null:
			_burst(old, pos)
		Sound.play("steal")
		await get_tree().create_timer(0.18).timeout
	var node := _add_mark(i, side)
	node.position.y = 3.2
	node.scale = Vector3(0.6, 1.5, 0.6)
	node.rotation.y = -PI * 0.5
	Sound.play("whoosh", 1.3, -6.0)
	var tw := create_tween()
	tw.tween_property(node, "position:y", 0.0, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(node, "scale", Vector3.ONE, 0.22)
	tw.parallel().tween_property(node, "rotation:y", 0.0, 0.22)
	await tw.finished
	node.flash(0.25)
	Sound.play("stamp", 1.0 + 0.05 * side, 0.0, 0.05)
	var big: bool = result.jackpot or R.FIXED.has(result.cat)
	for k in 3 if big else 2:
		Sound.note_later(0.04 * k, note_base + k * 2)
	fx.sparks(pos + Vector3(0, 0.15, 0), color, 16 if big else 10, 3.0, 0.9)
	fx.ring(pos, color, 1.3, 0.35)
	if result.jackpot:
		fx.beam(pos, Vector3(1.1, 4.0, 1.1), Palette.GOLD, 0.8)
		fx.confetti(pos + Vector3(0, 0.4, 0), Vector3(0.4, 0, 0.4), 60, 8.0)
		Sound.play("star", 1.0, -2.0)
	_cells[i].create_tween().tween_property(_cells[i], "position:y", -0.08, 0.05)
	_cells[i].create_tween().tween_property(_cells[i], "position:y", 0.0, 0.25).set_delay(0.05) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	impact.emit(0.3 if big or result.stolen else 0.18)
	_set_badge(i, side, result.value)
	var squash := create_tween()
	squash.tween_property(node, "scale", Vector3(1.3, 0.6, 1.3), 0.05)
	squash.tween_property(node, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await squash.finished


## Four in a row: a neon bar sweeps across the line and the marks hop in turn.
func animate_line(line: PackedInt32Array, side: int) -> void:
	var a := cell_to_local(line[0])
	var b := cell_to_local(line[line.size() - 1])
	var color: Color = DiceArt.MARK_COLORS[side]
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.12, 0.16)
	bar.mesh = box
	bar.material_override = _unshaded(Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 0.95))
	bar.position = a.lerp(b, 0.5) + Vector3(0, 0.45, 0)
	bar.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	bar.scale = Vector3(0.01, 1, 1)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bar)
	var length := a.distance_to(b) + CELL * 0.8
	var tw := create_tween()
	tw.tween_property(bar, "scale:x", length, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k in line.size():
		var node: MarkNode = marks.get(line[k])
		var at := cell_to_local(line[k])
		Sound.note_later(0.09 * k, note_base + 4 + k * 2)
		get_tree().create_timer(0.09 * k).timeout.connect(func() -> void:
			fx.sparks(at + Vector3(0, 0.4, 0), color, 18, 4.0, 1.0)
			fx.ring(at, color, 1.6, 0.4)
			if node != null and is_instance_valid(node):
				node.set_glow(1.5)
				node.flash(0.3)
				var hop := node.create_tween()
				hop.tween_property(node, "position:y", 0.7, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				hop.tween_property(node, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE))
	impact.emit(0.7)
	await get_tree().create_timer(0.9).timeout
	var fade := bar.create_tween()
	fade.tween_property(bar, "scale:y", 0.0, 0.4).set_delay(0.6)
	fade.tween_callback(bar.queue_free)


## The losing side's marks go grey.
func dim_side(side: int) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.01)
	for i: int in marks:
		var n: MarkNode = marks[i]
		if n.side == side:
			tw.tween_method(n.set_dimmed, 0.0, 1.0, 0.4).set_delay(0.04 * i)


## A new round: the marks pop away and every cell flips over to its new
## category, in a wave from the far corner.
func animate_deal(m: DiceMatch) -> void:
	for i: int in marks.keys():
		var node: MarkNode = marks[i]
		marks.erase(i)
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3(1.3, 1.3, 1.3), 0.08).set_delay(0.02 * i)
		tw.tween_property(node, "scale", Vector3.ZERO, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tw.tween_callback(node.queue_free)
	for i in R.CELLS:
		_set_badge(i, R.NONE, 0)
	await get_tree().create_timer(0.3).timeout
	for i in R.CELLS:
		var cell := _cells[i]
		var cat := m.cats[i]
		var delay := 0.045 * (i % R.SIZE + i / R.SIZE)
		var tw := cell.create_tween()
		tw.tween_property(cell, "rotation:x", PI * 0.5, 0.12).set_delay(delay).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			_set_category(i, cat)
			Sound.play("deal", 1.0 + 0.04 * i, -4.0))
		tw.tween_property(cell, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.045 * 6 + 0.45).timeout
	for i in R.CELLS:
		if m.owners[i] != R.NONE:
			var node := _add_mark(i, m.owners[i])
			node.position.y = 3.0
			create_tween().tween_property(node, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			_set_badge(i, m.owners[i], m.marks[i])
			Sound.play_later(0.25, "stamp")


## Confetti rain over the whole board.
func celebrate() -> void:
	fx.rain(Vector3.ZERO, Vector3(3.0, 0, 3.0))
	fx.confetti(Vector3(0, 0.3, 0), Vector3(2.6, 0, 2.6), 80, 9.0)
	impact.emit(0.5)


## A label that rises from a cell and fades out.
func float_text(text: String, i: int, color: Color, size: int = 110) -> void:
	var l := _billboard(text, size, color)
	l.render_priority = 10
	l.position = cell_to_local(i) + Vector3(0, 1.3, 0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 2.9, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


# --- Pieces --------------------------------------------------------------------------

func _add_mark(i: int, side: int) -> MarkNode:
	var node := MarkNode.new(side)
	node.position = cell_to_local(i)
	add_child(node)
	marks[i] = node
	return node


## A stolen mark bursts into its colour and tumbles off the board.
func _burst(node: MarkNode, pos: Vector3) -> void:
	var color: Color = DiceArt.MARK_COLORS[node.side]
	node.flash(0.2)
	fx.debris(pos, color, 16)
	fx.sparks(pos + Vector3(0, 0.3, 0), color, 20, 4.5, 1.1)
	fx.ring(pos, STEAL_COLOR, 1.8, 0.4)
	var drift := Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "position", pos + drift + Vector3(0, 2.4, 0), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "rotation", Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4)), 0.45)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(node.queue_free)
	impact.emit(0.45)


## The score a cell was claimed with sits on its mark, and the cell's
## name moves to its top edge so the mark doesn't hide it.
func _set_badge(i: int, who: int, value: int) -> void:
	_set_owned_look(i, who != R.NONE)
	var badge: Label3D = _badges.get(i)
	if who == R.NONE:
		if badge != null:
			badge.visible = false
		return
	if badge == null:
		# Printed flat on top of the mark, so it never covers a cell name.
		badge = _flat_label(78)
		badge.outline_size = 24
		badge.no_depth_test = true
		badge.render_priority = 2
		badge.position = cell_to_local(i) + Vector3(0, DiceArt.MARK_HEIGHT + 0.04, 0.06)
		add_child(badge)
		_badges[i] = badge
	badge.text = str(value)
	badge.modulate = DiceArt.team_color(who)
	badge.visible = true
	badge.scale = Vector3.ONE * 1.6
	badge.create_tween().tween_property(badge, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Paints a cell with its category: name and rule, a tint of its colour,
## and for the face-count cells a little white die showing the face.
func _set_category(i: int, cat: int) -> void:
	var color := DiceArt.cat_color(cat)
	var tile: MeshInstance3D = _cells[i].get_child(0)
	if not _cell_mats.has(cat):
		var m := ShaderMaterial.new()
		m.shader = CELL_SHADER
		m.set_shader_parameter("cell_color", Palette.CELL_B.lerp(color, 0.22))
		m.set_shader_parameter("corner", 0.14)
		_cell_mats[cat] = m
	tile.material_override = _cell_mats[cat]
	_cats_shown[i] = cat
	var upper := R.is_upper(cat)
	_minis[i].visible = upper
	_rules[i].visible = true
	if upper:
		_minis[i].show_value(cat + 1)
	_fit_name(i, cat)
	_names[i].modulate = color
	_rules[i].text = DiceArt.cat_rule(cat)
	_rules[i].modulate = Color(color, 0.85)


func _set_owned_look(i: int, owned: bool) -> void:
	var name_label := _names[i]
	var cat: int = _cats_shown[i]
	if owned:
		name_label.text = DiceArt.cat_label(cat).replace("\n", " ")
		name_label.font_size = clampi(int(1.1 / (maxi(name_label.text.length(), 1) * 0.0045 * 0.62)), 22, 34)
		name_label.position = Vector3(0, 0.012, -0.47)
	else:
		_fit_name(i, cat)
	# An owned cell's name draws over the mark's arms.
	name_label.no_depth_test = owned
	name_label.render_priority = 1 if owned else 0
	_rules[i].visible = not owned
	_minis[i].visible = R.is_upper(cat) and not owned


func _fit_name(i: int, cat: int) -> void:
	var name_label := _names[i]
	name_label.text = "" if R.is_upper(cat) else DiceArt.cat_label(cat)
	var longest := 0
	for line in name_label.text.split("\n"):
		longest = maxi(longest, line.length())
	name_label.font_size = clampi(int(1.02 / (maxi(longest, 1) * 0.0045 * 0.66)), 30, 66)
	name_label.position = Vector3(0, 0.012, -0.08)


# --- Building ------------------------------------------------------------------------

func _build_base() -> void:
	var frame := MeshInstance3D.new()
	frame.mesh = TileArt.rounded_box(Vector3(5.75, 0.4, 5.75), 0.2)
	frame.position.y = -0.34
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = NEON_SHADER
	frame.material_override = _frame_mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)

	var slab := MeshInstance3D.new()
	slab.mesh = TileArt.rounded_box(Vector3(5.45, 0.6, 5.45), 0.25)
	slab.position.y = -0.3
	slab.material_override = _glossy(Palette.BOARD)
	add_child(slab)

	# The dice tray: a padded candy trough in front of the board.
	var tray := MeshInstance3D.new()
	tray.mesh = TileArt.rounded_box(Vector3(5.5, 0.5, 1.75), 0.25)
	tray.position = Vector3(0, -0.27, TRAY_Z - 0.2)
	tray.material_override = _glossy(Color("3a1a6e"))
	add_child(tray)

	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL_SIZE, CELL_SIZE)
	_cats_shown.resize(R.CELLS)
	for i in R.CELLS:
		var cell := Node3D.new()
		cell.position = cell_to_local(i)
		add_child(cell)
		_cells.append(cell)
		var tile := MeshInstance3D.new()
		tile.mesh = plane
		tile.position.y = 0.003
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cell.add_child(tile)
		var name_label := _flat_label(60)
		name_label.position = Vector3(0, 0.012, -0.08)
		cell.add_child(name_label)
		_names.append(name_label)
		var rule := _flat_label(36)
		rule.position = Vector3(0, 0.012, 0.42)
		cell.add_child(rule)
		_rules.append(rule)
		var mini := DieNode.new(-1, 1)
		mini.scale = Vector3.ONE * 0.62
		mini.position = Vector3(0, 0.0, -0.08)
		cell.add_child(mini)
		_minis.append(mini)


func _flat_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.font = TileArt.font()
	l.font_size = size
	l.pixel_size = 0.0045
	l.outline_size = 14
	l.outline_modulate = Palette.INK
	l.line_spacing = -10
	l.rotation_degrees.x = -90.0
	return l


func _billboard(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = TileArt.font()
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 26
	l.outline_modulate = Palette.INK
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


## Slight per-die turns, so the row doesn't look machine-placed.
func _yaw(d: int) -> float:
	return [0.12, -0.08, 0.05, -0.14, 0.09][d]


func _arrow() -> Node3D:
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	arrow.mesh = cone
	arrow.material_override = _unshaded(Color(2.4, 2.0, 0.4))
	return arrow


func _glossy(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.12
	m.metallic = 0.3
	m.clearcoat_enabled = true
	m.rim_enabled = true
	m.rim = 0.4
	return m


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


func _disc(c: Color, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.06
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 6
	m.mesh = torus
	m.scale = Vector3(1, 0.3, 1)
	m.material_override = _unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _ring_mark(c: Color, radius: float) -> MeshInstance3D:
	var m := _disc(c, radius)
	m.position.y = 0.04
	return m


## A thin glowing square border, lying flat.
func _outline(c: Color, size: float) -> Node3D:
	var frame := Node3D.new()
	var mat := _unshaded(c)
	for k in 4:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size, 0.02, 0.05)
		bar.mesh = box
		bar.material_override = mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.rotation.y = PI * 0.5 * k
		bar.position = Vector3(0, 0, size * 0.5 - 0.025).rotated(Vector3.UP, PI * 0.5 * k)
		frame.add_child(bar)
	return frame


func _flat_square(c: Color, size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	m.mesh = plane
	m.material_override = _unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
