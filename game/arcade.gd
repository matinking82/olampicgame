class_name Arcade
extends RefCounted
## The game list, and moving between the hub and the games. Each game is
## its own scene; the hub (main menu, game picker, records, settings) is the
## main scene. Music and settings live in autoloads, so they carry across.

const HUB := "res://hub/hub.tscn"
const SUDOKU := "sudoku"
const CHESS := "chess"
const DICE := "dice"
const FLIP := "flip"
const FLEET := "fleet"
const GRID := "grid"
const GAMES := {
	SUDOKU: {
		"name": "SUDOKU POP", "tagline": "Place  ·  Pop  ·  Blast",
		"scene": "res://game/main.tscn", "records": "user://records.json", "level": "Lv",
	},
	CHESS: {
		"name": "MERGE MATE", "tagline": "Merge  ·  Promote  ·  Checkmate",
		"scene": "res://chess/chess_main.tscn", "records": "user://records_chess.json", "level": "Rd",
	},
	DICE: {
		"name": "TIC TAC ROLL", "tagline": "Roll  ·  Claim  ·  Four in a row",
		"scene": "res://dice/dice_main.tscn", "records": "user://records_dice.json", "level": "Rd",
	},
	FLIP: {
		"name": "FLIP FOUR", "tagline": "Drop  ·  Flip  ·  Lock four",
		"scene": "res://flip/flip_main.tscn", "records": "user://records_flip.json", "level": "Rd",
	},
	FLEET: {
		"name": "MINE FLEET", "tagline": "Fire  ·  Deduce  ·  Sink",
		"scene": "res://fleet/fleet_main.tscn", "records": "user://records_fleet.json", "level": "Rd",
	},
	GRID: {
		"name": "CODE GRID", "tagline": "Fill  ·  Check  ·  Crack",
		"scene": "res://grid/grid_main.tscn", "records": "user://records_grid.json", "level": "Lv",
	},
}

## What the next game scene should start with, set just before switching.
static var start_tutorial := false
static var two_players := false
## Which hub page to show when coming back from a game.
static var hub_page := "main"


static func launch(game: String, tutorial: bool = false, versus: bool = false) -> void:
	start_tutorial = tutorial
	two_players = versus
	_change(GAMES[game].scene)


static func open_hub(page: String = "games") -> void:
	hub_page = page
	_change(HUB)


static func records(game: String) -> Records:
	return Records.load_from(GAMES[game].records)


static func _change(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	Engine.time_scale = 1.0
	tree.change_scene_to_file(path)
