class_name Toaster
extends Label
## The big centre message ("SUDOKU!", "CHECK!"): punches in with a twist,
## holds, then floats off. Messages queue up so none get lost.

const HOLD := 0.7

var _queue: Array = []
var _busy := false


func _init() -> void:
	var s := LabelSettings.new()
	s.font = TileArt.font()
	s.font_size = 64
	s.outline_size = 10
	s.outline_color = Palette.INK
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_offset = Vector2(0, 3)
	label_settings = s
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


## `size` scales the message for bigger moments.
func push(text: String, color: Color = Palette.TEXT, size: float = 1.0) -> void:
	_queue.append([text, color, size])
	if not _busy:
		_run()


func clear() -> void:
	_queue.clear()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var t: Array = _queue.pop_front()
		var size: float = t[2]
		if size >= 1.2:
			Sound.play("whoosh", 0.9 + 0.1 * size)
		text = t[0]
		label_settings.font_color = t[1]
		pivot_offset = self.size * 0.5
		scale = Vector2.ONE * 0.3 * size
		rotation = deg_to_rad(randf_range(-9.0, 9.0))
		modulate.a = 1.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE * 1.25 * size, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "rotation", deg_to_rad(randf_range(-4.0, 4.0)), 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(self, "scale", Vector2.ONE * size, 0.1)
		tw.chain().tween_interval(0.25 if _queue.size() > 0 else HOLD)
		tw.chain().tween_property(self, "modulate:a", 0.0, 0.18)
		tw.tween_property(self, "scale", Vector2.ONE * 0.9 * size, 0.18)
		await tw.finished
	_busy = false
