extends Node3D
## Wires Tic Tac Roll together: the world and camera, pointer and keyboard
## input (tap dice to hold them, ROLL, tap a lit cell to claim it), turns
## and their animations, the CPU's turns, rounds, hearts, the tutorial and
## game over.
##
## Touch goes through Godot's mouse emulation, so one code path serves
## mouse and fingers. Keys: Space rolls (or passes), 1-5 hold dice.

const R := preload("res://dice/dice_rules.gd")
const CAMERA_PITCH := 56.0
## Screen space kept free for the HUD (left, top, right, bottom).
const MARGIN_PORTRAIT := Vector4(12, 225, 12, 215)
const MARGIN_LANDSCAPE := Vector4(290, 170, 290, 16)
## During the tutorial the board sits lower, below the instruction card.
const TUTORIAL_TOP_PORTRAIT := 360.0
const TUTORIAL_TOP_LANDSCAPE := 280.0
## Beats in the CPU's turn, so it reads like someone playing.
const CPU_START := 0.5
const CPU_LOOK := 0.55
const CPU_HOLD_STEP := 0.14
## The tutorial's fixed board.
const TUTORIAL_CATS := [
	R.Cat.CHANCE, R.Cat.FIVES, R.Cat.SMALL_STRAIGHT, R.Cat.TWOS,
	R.Cat.THREES, R.Cat.FULL_HOUSE, R.Cat.TWO_PAIRS, R.Cat.SIXES,
	R.Cat.FOUR_KIND, R.Cat.THREE_KIND, R.Cat.BIG_STRAIGHT, R.Cat.ONES,
	R.Cat.FOURS, R.Cat.FIVE_KIND, R.Cat.THREE_KIND, R.Cat.CHANCE,
]
## Steps: what to say, what has to happen, the scripted dice, and for the
## steps that set up a board, who owns what (cell: [side, score]).
const TUTORIAL := [
	{
		"text": "Tap ROLL to throw the five dice. You get 3 rolls a turn.",
		"goal": "roll", "rig": [4, 4, 2, 4, 6], "setup": {},
	},
	{
		"text": "Three 4s! Tap them to HOLD them, then ROLL the other two.",
		"goal": "hold_roll", "hold": [0, 1, 3], "rig": [2, 2],
	},
	{
		"text": "FULL HOUSE! Lit cells fit your dice. Claim the FULL HOUSE cell with your X.",
		"goal": "claim", "target": 5,
	},
	{
		"text": "FOUR IN A ROW wins! Your 26 beats the CPU's 12 on that 3 OF A KIND: STEAL it to finish the row!",
		"goal": "line", "target": 9, "dice": [6, 6, 6, 5, 3],
		"setup": {5: [0, 25], 8: [0, 24], 10: [0, 40], 11: [0, 3], 9: [1, 12], 2: [1, 30], 12: [1, 8]},
	},
]
const TUTORIAL_TIPS := "Beat the number on a CPU cell to STEAL it.\n" \
	+ "Combos and steals build a STREAK: 5 in a row is FEVER!\n" \
	+ "Points fill your power bar: +1 ROLL, or NUDGE a die up a pip.\n" \
	+ "Win a round to go on. Lose one and it costs a heart!"

enum Mode { PLAY, PAUSE, OVER, TUTORIAL }

var game: DiceMatch
var board_view: DiceBoardView
var hud: DiceHud
var menus: Menus
var camera: Camera3D
var feel: Feel
var records: Records

var _mode := Mode.PLAY
var _tutorial_step := -1
var _background: ShaderMaterial
var _fever_on := false
var _busy := false
var _armed := false
var _hover := -1
## Bumped on every new game, so animations and CPU turns from an abandoned
## game stop where they are.
var _generation := 0
var _two_players := false


func _ready() -> void:
	var made := Stage.build(self)
	camera = made.camera
	_background = made.background
	feel = Feel.new(camera)
	add_child(feel)
	board_view = DiceBoardView.new()
	add_child(board_view)
	hud = DiceHud.new()
	add_child(hud)
	menus = Menus.new()
	add_child(menus)
	records = Arcade.records(Arcade.DICE)
	board_view.impact.connect(feel.impact)
	hud.roll_pressed.connect(_on_roll)
	hud.extra_pressed.connect(_on_extra)
	hud.nudge_pressed.connect(_on_nudge)
	hud.pause_pressed.connect(_pause)
	menus.resume_pressed.connect(_resume)
	menus.restart_pressed.connect(_play_new)
	menus.menu_pressed.connect(Arcade.open_hub)
	menus.name_submitted.connect(_on_name_submitted)
	menus.tutorial_skipped.connect(_finish_tutorial)
	get_viewport().size_changed.connect(_layout)
	_two_players = Arcade.two_players
	Sound.start_music(Sound.DICE_MUSIC)
	if Arcade.start_tutorial or not Settings.dice_tutorial_done:
		Arcade.start_tutorial = false
		_start_tutorial()
	else:
		_play_new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


## Waits in game time; stops while the game is paused.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


# --- Screens and flow --------------------------------------------------------------

func _play_new() -> void:
	get_tree().paused = false
	_tutorial_step = -1
	board_view.hide_target()
	menus.hide_all()
	_mode = Mode.PLAY
	new_game()


func new_game(seed_value: int = 0) -> void:
	_generation += 1
	_busy = false
	_disarm()
	game = DiceMatch.new(seed_value, not _two_players)
	game.start()
	board_view.sync(game)
	board_view.clear_options()
	hud.reset(game, records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_layout()
	_start_turn()


func _pause() -> void:
	if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
		return
	_disarm()
	_mode = Mode.PAUSE
	get_tree().paused = true
	menus.show_pause()


func _resume() -> void:
	get_tree().paused = false
	menus.hide_all()
	_mode = Mode.TUTORIAL if _tutorial_step >= 0 else Mode.PLAY
	if _mode == Mode.TUTORIAL:
		menus.show_tutorial(TUTORIAL[_tutorial_step].text, _tutorial_step + 1, TUTORIAL.size())


func _back() -> void:
	match _mode:
		Mode.PLAY, Mode.TUTORIAL:
			if _armed:
				_disarm()
			else:
				_pause()
		_:
			menus.back()


func _on_name_submitted(player_name: String) -> void:
	var rank := records.add(player_name, game.scores[0], game.round, game.total_turns)
	records.save(Arcade.GAMES[Arcade.DICE].records)
	Settings.save()
	menus.show_saved(records, rank)


# --- Tutorial ------------------------------------------------------------------------

func _start_tutorial() -> void:
	get_tree().paused = false
	_two_players = false
	new_game()
	menus.hide_all()
	_mode = Mode.TUTORIAL
	_tutorial_step = 0
	_layout()
	_load_tutorial_step()


func _load_tutorial_step() -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	_disarm()
	board_view.hide_target()
	if step.has("setup"):
		game.start_round()
		game.cats = PackedInt32Array(TUTORIAL_CATS)
		game.turn = 0
		for i: int in step.setup:
			game.owners[i] = step.setup[i][0]
			game.marks[i] = step.setup[i][1]
		if step.has("dice"):
			game.dice = PackedInt32Array(step.dice)
			game.rolled = true
			game.rolls_left = 2
		board_view.sync(game)
		_start_turn()
	game.rigged.assign(step.get("rig", []))
	match step.goal:
		"hold_roll":
			board_view.show_die_targets(step.hold)
		"claim", "line":
			board_view.show_target(step.target)
			board_view.show_options(game)
	hud.update(game)
	menus.show_tutorial(step.text, _tutorial_step + 1, TUTORIAL.size())


## Moves the tutorial on once its goal is met.
func _advance_tutorial() -> void:
	_tutorial_step += 1
	if _tutorial_step >= TUTORIAL.size():
		board_view.hide_target()
		menus.show_tutorial_end(TUTORIAL_TIPS)
		return
	_load_tutorial_step()


func _finish_tutorial() -> void:
	Settings.dice_tutorial_done = true
	Settings.save()
	_two_players = Arcade.two_players
	_play_new()


## Whether the tutorial lets this happen right now; says why not if not.
func _tutorial_allows(action: String, arg: int = -1) -> bool:
	if _tutorial_step < 0:
		return true
	var step: Dictionary = TUTORIAL[_tutorial_step]
	match step.goal:
		"roll":
			if action != "roll":
				hud.hint("Tap ROLL first!")
				return false
		"hold_roll":
			if action == "roll":
				for d in R.DICE:
					if game.held[d] != step.hold.has(d):
						hud.hint("Hold the three 4s first")
						return false
			elif action != "hold":
				hud.hint("Tap the 4s to hold them")
				return false
		"claim", "line":
			if action != "claim" or arg != step.target:
				hud.hint("Tap the cell the arrow points at")
				return false
	return true


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
			return
		if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
			return
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_roll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_on_die(event.keycode - KEY_1)
		return
	if _mode != Mode.PLAY and _mode != Mode.TUTORIAL:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_press(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_disarm()
	elif event is InputEventMouseMotion:
		_on_move(event.position)


func _can_input() -> bool:
	return not _busy and game.winner < 0 and not game.draw and not game.is_cpu_turn()


func _on_press(pos: Vector2) -> void:
	if not _can_input():
		return
	var d := board_view.die_at(Stage.pointer_on_plane(camera, pos, DiceArt.DIE_SIZE * 0.5))
	if d >= 0:
		_on_die(d)
		return
	var i := board_view.world_to_index(Stage.pointer_on_plane(camera, pos, 0.0))
	if _armed:
		_disarm()
		return
	if i < 0:
		return
	if game.can_claim(i):
		if _tutorial_allows("claim", i):
			_claim(i)
	elif game.rolled:
		hud.hint(_why_not(i))
		Sound.play("invalid")
		feel.impact(0.1)
	else:
		hud.hint("ROLL first, then claim a cell your dice fit")


## Hovering a lit cell (mouse) says what claiming it would do.
func _on_move(pos: Vector2) -> void:
	if not _can_input() or not game.rolled:
		return
	var i := board_view.world_to_index(Stage.pointer_on_plane(camera, pos, 0.0))
	if i == _hover:
		return
	_hover = i
	var valid := game.can_claim(i)
	board_view.set_hover(i if valid else -1)
	if valid:
		hud.hint(_describe(i))
	elif i >= 0 and game.owners[i] != R.NONE:
		hud.hint("%s holds %s with %d" % [_who(game.owners[i]), R.NAMES[game.cats[i]].to_upper(), game.marks[i]])


func _on_die(d: int) -> void:
	if not _can_input():
		return
	if _armed:
		_use_nudge(d)
		return
	if not game.rolled:
		hud.hint("Tap ROLL first!")
		return
	if game.rolls_left <= 0:
		hud.hint("No rolls left: claim a lit cell")
		return
	if not _tutorial_allows("hold"):
		return
	game.toggle_hold(d)
	board_view.set_held(d, game.held[d])
	hud.hint("")


## The line under the board for a lit cell.
func _describe(i: int) -> String:
	var s := R.score(game.cats[i], game.dice)
	var name: String = R.NAMES[game.cats[i]].to_upper()
	if game.owners[i] != R.NONE:
		return "STEAL %s: %d beats %d" % [name, s, game.marks[i]]
	return "%s  →  +%s" % [name, UI.thousands(s * DiceMatch.CLAIM_MULT)]


## Why a tapped cell can't be claimed.
func _why_not(i: int) -> String:
	var name: String = R.NAMES[game.cats[i]].to_upper()
	if game.owners[i] == game.turn:
		return "That cell is already yours"
	var s := R.score(game.cats[i], game.dice)
	if s < 0:
		return "Your dice don't make %s" % name
	return "%d doesn't beat %d on %s" % [s, game.marks[i], name]


func _who(side: int) -> String:
	if game.vs_cpu:
		return "You" if side == 0 else "The CPU"
	return DiceArt.TEAM_NAMES[side]


# --- Turns -----------------------------------------------------------------------------

func _start_turn() -> void:
	_hover = -1
	hud.set_turn(game)
	hud.update(game)
	_set_fever(game.is_fever(game.turn) and (game.turn == 0 or not game.vs_cpu))
	board_view.reset_dice(game.turn, _fever_on)
	board_view.set_turn_color(Color(DiceArt.team_color(game.turn), 0.5))
	if game.is_cpu_turn() and _mode == Mode.PLAY:
		_cpu_turn()
	elif _mode == Mode.PLAY:
		hud.hint("Tap ROLL!" if game.vs_cpu else "%s: tap ROLL!" % DiceArt.TEAM_NAMES[game.turn])


func _on_roll() -> void:
	if not _can_input():
		return
	if game.is_bust():
		_pass()
		return
	if not game.can_roll() or not _tutorial_allows("roll"):
		return
	_disarm()
	await _roll()
	if _tutorial_step >= 0 and _mode == Mode.TUTORIAL:
		_advance_tutorial()


## Rolls through the animated path; used by the player and the CPU.
func _roll() -> void:
	_busy = true
	var generation := _generation
	hud.hint("")
	var result := game.roll()
	hud.update(game)
	await board_view.animate_roll(result.moved, result.dice)
	if generation != _generation:
		return
	if result.jackpot:
		board_view.animate_jackpot()
		hud.toast("JACKPOT!!!", Palette.GOLD, 1.6)
	hud.update(game)
	var mine := not game.is_cpu_turn()
	if mine:
		board_view.show_options(game)
		var options := game.options()
		if game.is_bust():
			hud.toast("NO MATCH!", Palette.TEXT, 1.1)
			Sound.play("thud", 1.2)
			hud.hint("Nothing fits: +1 ROLL or PASS" if game.can_extra_roll() else "Nothing fits: tap PASS")
		elif options.is_empty():
			hud.hint("Nothing fits yet: hold dice and roll again")
		elif _tutorial_step < 0:
			hud.hint("Tap dice to hold, then roll, or claim a lit cell" if game.rolls_left > 0 else "Claim a lit cell")
	_busy = false


func _claim(i: int) -> void:
	_busy = true
	_disarm()
	hud.hint("")
	board_view.set_hover(-1)
	var result := game.claim(i)
	if result.is_empty():
		_busy = false
		return
	await _play_claim(result)


func _play_claim(result: Dictionary) -> void:
	var generation := _generation
	board_view.note_base = clampi(game.streak[result.side] - 1, 0, 6)
	await board_view.animate_claim(result)
	if generation != _generation:
		return
	_announce(result)
	await _after(result)


func _pass() -> void:
	_busy = true
	var generation := _generation
	var result := game.pass_turn()
	hud.toast("PASS", Palette.TEXT)
	await board_view.animate_bust()
	if generation != _generation:
		return
	await _after(result)


## Toasts, floating points and sounds for a claim.
func _announce(result: Dictionary) -> void:
	var side: int = result.side
	var mine := side == 0 or not game.vs_cpu
	var cat: int = result.cat
	var color := DiceArt.cat_color(cat)
	if result.stolen:
		hud.toast("STOLEN!" if mine else "%s STOLE A CELL!" % _who(side).to_upper(), Palette.HOT, 1.25)
	elif result.combo:
		var word: String = R.NAMES[cat].to_upper() + "!"
		if R.is_upper(cat):
			word = "%s %ds!" % [["", "", "", "THREE", "FOUR", "FIVE"][result.value / (cat + 1)], cat + 1]
		hud.toast(word, color, 1.0 + (0.25 if R.FIXED.has(cat) else 0.0))
	if result.points > 0 and mine:
		var c := Palette.HOT if result.fever else Palette.GOLD
		board_view.float_text("+%d" % result.points, result.at, c, 90 + mini(result.points, 1500) / 15)
	if mine and result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
		Sound.duck(5.0, 0.8)
	if mine:
		Sound.set_intensity(result.streak, result.fever)
	for k in result.charges_earned:
		if mine:
			hud.toast("+ POWER", DiceHud.POWER_COLOR)
			Sound.play_later(0.12 * k, "coin")


## After a claim or pass: the round's end, or the next turn.
func _after(result: Dictionary) -> void:
	hud.update(game)
	if _mode == Mode.TUTORIAL:
		var goal: String = TUTORIAL[_tutorial_step].goal
		if goal == "line" and not result.line.is_empty():
			await board_view.animate_line(result.line, 0)
			hud.toast("FOUR IN A ROW!", Palette.GOLD, 1.6)
			board_view.celebrate()
			Sound.play("win")
			await _wait(1.2)
		_busy = false
		if _mode == Mode.TUTORIAL:
			_advance_tutorial()
		return
	if game.winner >= 0 or game.draw:
		await _round_over(result)
		return
	_warn_threats(result.side)
	_busy = false
	_start_turn()


## A side one cell from a line gets a warning.
func _warn_threats(side: int) -> void:
	for line in R.lines():
		var own := 0
		var other := 0
		for c in line:
			if game.owners[c] == side:
				own += 1
			elif game.owners[c] == 1 - side:
				other += 1
		if own == R.LINE - 1 and other == 0:
			if game.vs_cpu and side == 1:
				hud.toast("CPU NEEDS ONE MORE!", DiceArt.team_color(1), 1.1)
			elif game.vs_cpu:
				hud.toast("ONE MORE FOR THE ROW!", Palette.GOLD, 1.1)
			else:
				hud.toast("%s NEEDS ONE MORE!" % DiceArt.TEAM_NAMES[side], DiceArt.team_color(side), 1.1)
			Sound.play("check")
			return


# --- The CPU -----------------------------------------------------------------------------

func _cpu_turn() -> void:
	_busy = true
	var generation := _generation
	var cfg := DiceMatch.cpu_config(game.round)
	await _wait(CPU_START)
	while generation == _generation:
		await _roll()
		_busy = true
		if generation != _generation:
			return
		await _wait(CPU_LOOK)
		if generation != _generation:
			return
		var decision := DiceAI.decide(game.cats, game.owners, game.marks, 1, game.dice, game.rolls_left, cfg, game.rng)
		if decision.has("claim"):
			board_view.set_hover(decision.claim)
			await _wait(0.3)
			if generation != _generation:
				return
			_claim(decision.claim)
			return
		if decision.has("pass"):
			_pass()
			return
		for d in R.DICE:
			if decision.hold[d] != game.held[d]:
				game.toggle_hold(d)
				board_view.set_held(d, game.held[d])
				await _wait(CPU_HOLD_STEP)
		await _wait(0.2)


# --- Rounds and the end ----------------------------------------------------------------------

func _round_over(result: Dictionary) -> void:
	var generation := _generation
	var winner := game.winner
	hud.clear_turn()
	if not result.line.is_empty():
		await board_view.animate_line(result.line, winner)
		if generation != _generation:
			return
	elif game.draw:
		hud.toast("BOARD FULL: DRAW!", Palette.TEXT, 1.3)
	else:
		hud.toast("BOARD FULL!", Palette.TEXT, 1.3)
		await _wait(0.8)
		hud.toast("%s %s MORE CELLS" % [_who(winner).to_upper(), "HAVE" if winner == 0 and game.vs_cpu else "HAS"],
			DiceArt.team_color(winner), 1.2)
	_set_fever(false)
	Sound.set_intensity(0, false)
	if winner >= 0:
		board_view.dim_side(1 - winner)
		var player_won := winner == 0 or not game.vs_cpu
		if player_won:
			if not result.line.is_empty():
				hud.toast("FOUR IN A ROW!", Palette.GOLD, 1.6)
			board_view.celebrate()
			Sound.play("win")
			Sound.duck(8.0, 1.5)
		else:
			hud.toast("THE CPU WINS THE ROUND", DiceArt.team_color(1), 1.2)
			Sound.play("game_over")
	await _wait(1.4)
	if generation != _generation:
		return
	if game.game_over:
		if game.vs_cpu:
			_end_match("OUT OF HEARTS")
		else:
			_end_match("%s WINS!" % DiceArt.TEAM_NAMES[winner])
		return
	await _next_round(result)


func _next_round(result: Dictionary) -> void:
	var generation := _generation
	if game.vs_cpu and game.winner == 0:
		hud.toast("ROUND CLEAR!  +%s" % UI.thousands(result.round_bonus), Palette.GOLD, 1.3)
		Sound.play("level_up")
	elif game.vs_cpu and game.winner == 1:
		hud.toast("-1 ♥   %d LEFT" % game.hearts, Palette.HOT, 1.3)
		Sound.play("crack", 0.8)
	elif not game.vs_cpu and game.winner >= 0:
		hud.toast("%s TAKES THE ROUND" % DiceArt.TEAM_NAMES[game.winner], DiceArt.team_color(game.winner), 1.3)
	hud.update(game)
	await _wait(1.3)
	if generation != _generation:
		return
	var replay := game.vs_cpu and game.winner != 0
	game.next_round()
	board_view.clear_options()
	await board_view.animate_deal(game)
	if generation != _generation:
		return
	hud.toast(("ROUND %d AGAIN" if replay else "ROUND %d") % game.round, Palette.TEXT, 1.4)
	_busy = false
	_start_turn()


func _end_match(title: String) -> void:
	_mode = Mode.OVER
	_busy = true
	hud.clear_turn()
	board_view.clear_options()
	if game.vs_cpu:
		var stats := "Round %d   ·   Rounds won %d   ·   Best streak %d\nSteals %d   ·   Jackpots %d   ·   Best claim %d" % [
			game.round, game.rounds_won, game.best_streak, game.steals, game.jackpots, game.best_claim]
		menus.show_game_over(title, game.scores[0], stats, records, records.best(), "Rd")
	else:
		var stats := "SUN %d  –  %d ICE   ·   %d rounds\nSUN %s   ·   ICE %s" % [game.round_wins[0], game.round_wins[1],
			game.round, UI.thousands(game.scores[0]), UI.thousands(game.scores[1])]
		menus.show_game_over(title, 0, stats, null, 0, "Rd", "REMATCH")


# --- Powers ---------------------------------------------------------------------------------

func _on_extra() -> void:
	if not _can_input() or not game.can_extra_roll():
		return
	if _tutorial_step >= 0:
		hud.hint("Powers come later!")
		return
	_disarm()
	game.extra_roll()
	hud.toast("+1 ROLL!", DiceHud.POWER_COLOR, 1.2)
	Sound.play("upgrade")
	board_view.clear_options()
	hud.update(game)
	hud.hint("Hold what you like and ROLL")


func _on_nudge() -> void:
	if not _can_input():
		return
	if _armed:
		_disarm()
		return
	if _tutorial_step >= 0:
		hud.hint("Powers come later!")
		return
	if not game.can_nudge():
		if not game.rolled:
			hud.hint("Roll first, then nudge a die")
		return
	_armed = true
	hud.set_armed(true)
	hud.update(game)
	hud.hint("Tap a die to turn it up one pip")
	Sound.play("click", 1.2)


func _disarm() -> void:
	if not _armed:
		return
	_armed = false
	hud.set_armed(false)
	if game != null:
		hud.update(game)
	hud.hint("")


func _use_nudge(d: int) -> void:
	_disarm()
	if not game.nudge(d):
		return
	_busy = true
	var generation := _generation
	await board_view.animate_nudge(d, game.dice[d])
	if generation != _generation:
		return
	board_view.show_options(game)
	hud.update(game)
	if game.is_bust():
		hud.hint("Still nothing fits")
	_busy = false


# --- Feel and camera -------------------------------------------------------------------------------

func _set_fever(on: bool) -> void:
	if on == _fever_on:
		return
	_fever_on = on
	board_view.set_fever(on, game.turn)
	var from: float = _background.get_shader_parameter("fever") if _background.get_shader_parameter("fever") != null else 0.0
	create_tween().tween_method(func(v: float) -> void: _background.set_shader_parameter("fever", v),
		from, 1.0 if on else 0.0, 0.6)


func _layout() -> void:
	var portrait := Stage.fit_ui(get_window())
	hud.set_landscape(not portrait)
	var size := get_viewport().get_visible_rect().size
	var m := MARGIN_PORTRAIT if portrait else MARGIN_LANDSCAPE
	# On a phone the card would cover the score column; it goes below it.
	menus.tutorial_top = 150.0 if portrait else 96.0
	if _mode == Mode.TUTORIAL:
		m.y = TUTORIAL_TOP_PORTRAIT if portrait else TUTORIAL_TOP_LANDSCAPE
	var free := Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)
	Stage.fit_camera(camera, Vector3(-2.95, 0, -2.95), Vector3(2.95, 0.9, 4.7), free, size, CAMERA_PITCH)


# --- Developer helpers (used by tools/dev_shot.gd) ------------------------------------------------

func debug_summary() -> String:
	return "round %d  score %d  hearts %d  turns %d  winner %d  mode %d" % [
		game.round, game.scores[0], game.hearts, game.total_turns, game.winner, _mode]


## Plays the player's turns with the CPU's brain through the animated path
## (both sides with two players).
func debug_autoplay(turns: int) -> void:
	var cfg := {"samples": 20, "noise": 1.0, "block": 0.9}
	for t in turns:
		while _busy or game.is_cpu_turn():
			if game.game_over or _mode == Mode.OVER:
				break
			await get_tree().process_frame
		if game.game_over or _mode == Mode.OVER:
			break
		if game.winner >= 0 or game.draw:
			await get_tree().process_frame
			continue
		await _on_roll()
		while true:
			var d := DiceAI.decide(game.cats, game.owners, game.marks, game.turn, game.dice, game.rolls_left, cfg, game.rng)
			if d.has("claim"):
				await _claim(d.claim)
				break
			if d.has("pass"):
				await _pass()
				break
			for k in R.DICE:
				if d.hold[k] != game.held[k]:
					_on_die(k)
			await _on_roll()
	# A finished run waits for its game-over panel.
	while _busy and not (game.game_over and _mode == Mode.OVER):
		await get_tree().process_frame


func debug_round(r: int) -> void:
	game.round = r
	game.start_round()
	board_view.sync(game)
	hud.update(game)


func debug_page(page: String) -> void:
	match page:
		"settings":
			menus.show_settings()
		"pause":
			_pause()
		"tutorial":
			_start_tutorial()
		"tutorial_end":
			menus.show_tutorial_end(TUTORIAL_TIPS)
		"versus":
			_two_players = true
			_play_new()


func debug_game_over() -> void:
	game.scores[0] = 24680
	game.round = 5
	game.rounds_won = 4
	game.hearts = 0
	_end_match("OUT OF HEARTS")


## A mid-round board with a roll on the table and its options lit.
func debug_hover() -> void:
	for i: int in [0, 5, 6, 10]:
		game.owners[i] = 0
		game.marks[i] = 20
	for i: int in [3, 9, 12]:
		game.owners[i] = 1
		game.marks[i] = 8
	board_view.sync(game)
	game.rigged.assign([3, 3, 5, 3, 3])
	await _on_roll()
	game.toggle_hold(0)
	board_view.set_held(0, true)
	game.toggle_hold(1)
	board_view.set_held(1, true)
	var opts := game.options()
	if not opts.is_empty():
		board_view.set_hover(opts[0])
		hud.hint(_describe(opts[0]))
	print("debug_hover: dice ", game.dice, " held ", game.held, " options ", opts, " at ", Engine.get_process_frames())


## One player turn through real input: click ROLL, click two dice, click a lit cell.
func debug_drag() -> void:
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	var turns := game.total_turns
	await _sim_tap(hud._roll.get_global_rect().get_center())
	while _busy:
		await get_tree().process_frame
	for d in [0, 1]:
		await _sim_tap(camera.unproject_position(board_view.die_to_world(d)))
	print("debug_drag: held = ", game.held, " rolled = ", game.rolled)
	var opts := game.options()
	if opts.is_empty():
		await _sim_tap(hud._roll.get_global_rect().get_center())
		while _busy:
			await get_tree().process_frame
		await _sim_tap(hud._roll.get_global_rect().get_center())
		while _busy:
			await get_tree().process_frame
		opts = game.options()
	if not opts.is_empty():
		await _sim_tap(camera.unproject_position(board_view.cell_to_world(opts[0])))
	elif game.is_bust():
		await _sim_tap(hud._roll.get_global_rect().get_center())
	while _busy:
		await get_tree().process_frame
	print("debug_drag: claimed = ", game.total_turns == turns + 1)


## Sets up a steal that completes a row, and plays it through input.
func debug_mate() -> void:
	for i: int in [4, 5, 7]:
		game.owners[i] = 0
		game.marks[i] = 20
	game.owners[6] = 1
	game.marks[6] = 5
	game.cats[6] = R.Cat.CHANCE
	board_view.sync(game)
	game.dice = PackedInt32Array([6, 6, 5, 4, 3])
	game.rolled = true
	game.rolls_left = 2
	board_view.sync_dice(game)
	board_view.show_options(game)
	await _sim_tap(camera.unproject_position(board_view.cell_to_world(6)))
	while _busy:
		await get_tree().process_frame
	print("debug_mate: winner ", game.winner, ", round ", game.round)


## Claims a Five of a Kind with a jackpot roll.
func debug_merge() -> void:
	game.rigged.assign([5, 5, 5, 5, 5])
	await _on_roll()
	for i in R.CELLS:
		if game.cats[i] == R.Cat.FIVE_KIND:
			await _claim(i)
			break


func debug_upgrade() -> void:
	game.charges[0] = 2
	hud.update(game)
	game.rigged.assign([1, 2, 3, 4, 6])
	await _on_roll()
	_on_extra()
	_on_nudge()
	await _sim_tap(camera.unproject_position(board_view.die_to_world(4)))
	while _busy:
		await get_tree().process_frame
	print("debug_upgrade: charges left ", game.charges[0], ", dice ", game.dice, ", rolls left ", game.rolls_left)


func debug_tutorial() -> void:
	_start_tutorial()
	await _wait(0.6)
	var roll_at := hud._roll.get_global_rect().get_center()
	await _sim_tap(roll_at)
	await _wait(1.2)
	print("debug_tutorial: after rolling the tutorial is on step %d" % (_tutorial_step + 1))
	for d: int in TUTORIAL[1].hold:
		await _sim_tap(camera.unproject_position(board_view.die_to_world(d)))
	await _sim_tap(roll_at)
	await _wait(1.2)
	print("debug_tutorial: after holding the tutorial is on step %d, dice %s" % [_tutorial_step + 1, game.dice])
	for k in [2, 3]:
		await _sim_tap(camera.unproject_position(board_view.cell_to_world(TUTORIAL[k].target)))
		await _wait(3.5)
		print("debug_tutorial: after step %d the tutorial is on step %d" % [k + 1, _tutorial_step + 1])
	print("debug_tutorial: end card shown = ", menus.is_open())


## A click at a viewport position (a 3D point unprojected, or a HUD button's centre).
func _sim_tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = get_viewport().get_final_transform() * at
		e.global_position = e.position
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
