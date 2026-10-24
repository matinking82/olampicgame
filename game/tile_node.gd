class_name TileNode
extends Node3D
## One tile: a glossy rounded block with its digit on top. Used on the
## board, in the tray and as a ghost. The origin is the bottom centre, so
## squash-and-stretch scales from the floor.

var value := Board.EMPTY
var body := MeshInstance3D.new()
var label := Label3D.new()


func _init(v: int = Board.EMPTY) -> void:
	body.mesh = TileArt.tile_mesh()
	body.position.y = TileArt.TILE_HEIGHT * 0.5
	add_child(body)
	label.font = TileArt.font()
	label.font_size = 120
	label.pixel_size = 0.0049
	label.outline_size = 26
	label.rotation_degrees.x = -90.0
	label.position.y = TileArt.TILE_HEIGHT + 0.005
	label.modulate = Palette.TEXT
	add_child(label)
	set_value(v)


func set_value(v: int) -> void:
	value = v
	body.material_override = TileArt.material(v)
	label.text = TileArt.glyph(v)
	label.outline_modulate = Palette.tile(v).darkened(0.5)
	label.modulate = Palette.INK if v == Board.WILD else Palette.TEXT


func set_ghost(valid: bool) -> void:
	body.material_override = TileArt.ghost_material(value, valid)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.transparency = 0.4


func set_highlight(on: bool) -> void:
	body.material_overlay = TileArt.highlight_material() if on else null


## A white flash that fades out, for tiles that just appeared or got hit.
func flash(time: float = 0.3) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.6, 1.6, 1.6, 0.9)
	body.material_overlay = m
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if body.material_overlay == m:
			body.material_overlay = null)


func set_dimmed(on: bool) -> void:
	body.material_override = TileArt.dim_material() if on else TileArt.material(value)
	label.modulate.a = 0.45 if on else 1.0
