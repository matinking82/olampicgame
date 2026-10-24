extends Node
## Autoload "Settings": player preferences, saved to user://settings.cfg.
## Changing a value applies it right away; call save() to keep it.

signal changed

const PATH := "user://settings.cfg"

var music_volume := 0.8
var sfx_volume := 0.9
var screen_shake := true
var vibration := true
var hints := true
var tutorial_done := false
var chess_tutorial_done := false
var dice_tutorial_done := false
## Newer games keep their "tutorial seen" flags here, by Arcade game key.
var tutorials := {}
var player_name := ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		screen_shake = cfg.get_value("feel", "shake", screen_shake)
		vibration = cfg.get_value("feel", "vibration", vibration)
		hints = cfg.get_value("play", "hints", hints)
		tutorial_done = cfg.get_value("play", "tutorial_done", tutorial_done)
		chess_tutorial_done = cfg.get_value("chess", "tutorial_done", chess_tutorial_done)
		dice_tutorial_done = cfg.get_value("dice", "tutorial_done", dice_tutorial_done)
		tutorials = cfg.get_value("play", "tutorials", tutorials)
		player_name = cfg.get_value("play", "name", player_name)
	apply()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save()
	changed.emit()


func tutorial_seen(game: String) -> bool:
	return tutorials.get(game, false)


func mark_tutorial_seen(game: String) -> void:
	tutorials[game] = true
	save()


func apply() -> void:
	Sound.set_volumes(music_volume, sfx_volume)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("feel", "shake", screen_shake)
	cfg.set_value("feel", "vibration", vibration)
	cfg.set_value("play", "hints", hints)
	cfg.set_value("play", "tutorial_done", tutorial_done)
	cfg.set_value("chess", "tutorial_done", chess_tutorial_done)
	cfg.set_value("dice", "tutorial_done", dice_tutorial_done)
	cfg.set_value("play", "tutorials", tutorials)
	cfg.set_value("play", "name", player_name)
	cfg.save(PATH)
