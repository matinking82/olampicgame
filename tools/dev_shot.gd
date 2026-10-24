extends Node
## Developer helper for checking the games without clicking around.
## Does nothing unless --shot is passed after "--", for example:
##   Godot --path sudoku-pop --resolution 720x1280 -- --shot=C:/tmp/a.png --seed=5 --moves=6 --hover
## --game=hub|sudoku|chess|dice|flip|code|maze picks the scene (default sudoku). Then:
## --page=NAME opens a screen instead of starting play. Hub pages: main,
## games, records, settings. Game pages: settings, pause, tutorial,
## tutorial_end (chess and dice also: versus for a two-player match).
## Both games: --seed=N, --moves=N (autoplay), --drag (one move via
## simulated mouse input), --hover (hold a piece mid-drag), --tutorial (play
## the tutorial through input), --gameover (show the panel),
## --saveas=Name (type a name on the game-over panel and save).
## Sudoku only: --bomb, --showcase, --icon, --hints, --blast.
## Chess only: --merge (start a merge), --upgrade (use the power), --mate
## (play a mate in one), --round=N (start at that round).
## Dice (the same flags, other meanings): --hover (a roll with lit cells),
## --drag (a turn through clicks), --mate (steal to finish a row), --merge
## (a jackpot claimed), --upgrade (+1 Roll and Nudge), --round=N.
## Flip, fleet and grid also take --hover, --drag, --mate, --merge,
## --upgrade and --round=N (a preview, a move by click, a lock / a sinking /
## a crack, a big moment, the two powers, a starting round or level).
## Capture: --frames=N (wait before the capture), --shots=5,20,40 (several
## captures, saved as <shot>_f5.png and so on), --speed=N (fast-forward),
## --record=path.wav (record everything the game plays).


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if not args.has("shot"):
		return
	var game: String = args.get("game", Arcade.SUDOKU)
	if game != "hub":
		# Straight into play: skip the first-time tutorial unless asked for.
		Settings.tutorial_done = true
		Settings.chess_tutorial_done = true
		Settings.dice_tutorial_done = true
		for key: String in Arcade.GAMES:
			Settings.tutorials[key] = true
		Arcade.two_players = args.get("page", "") == "versus"
		get_tree().change_scene_to_file.call_deferred(Arcade.GAMES[game].scene)
	for i in 3:
		await get_tree().process_frame
	var main = get_tree().current_scene
	var recorder: AudioEffectRecord
	if args.has("record"):
		recorder = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, recorder)
		recorder.set_recording_active(true)
	if args.has("speed"):
		main.feel.set_time_scale(float(args.speed))
	if args.has("round"):
		main.debug_round(int(args.round))
	if args.has("page"):
		main.debug_page(args.page)
	if args.has("seed"):
		main.new_game(int(args.seed))
	if args.has("moves"):
		await main.debug_autoplay(int(args.moves))
	for flag: String in ["showcase", "icon", "hints"]:
		if args.has(flag):
			main.call("debug_" + flag)
	for flag: String in ["drag", "bomb", "tutorial", "merge", "upgrade", "mate"]:
		if args.has(flag):
			await main.call("debug_" + flag)
	if args.has("hover"):
		main.debug_hover()
	if args.has("gameover"):
		main.debug_game_over()
	if args.has("saveas"):
		main.menus._name_edit.text = args.saveas
		main.menus._submit()
		print("records on disk: ", main.records.entries)
	if args.has("blast"):
		main.debug_blast()
	var path: String = args.shot
	if args.has("shots"):
		var frame := 0
		for target in String(args.shots).split(","):
			while frame < int(target):
				await get_tree().process_frame
				frame += 1
			_save(path.get_basename() + "_f%s.png" % target)
	else:
		for i in int(args.get("frames", "40")):
			await get_tree().process_frame
		_save(path)
	if recorder != null:
		recorder.set_recording_active(false)
		recorder.get_recording().save_to_wav(args.record)
		print("recorded ", args.record)
	if main.has_method("debug_summary"):
		print(main.debug_summary())
	get_tree().quit()


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
