class_name Records
extends RefCounted
## The local top-10 leaderboard. Entries are dictionaries with name, score,
## level, turns and date, kept sorted best first. Saved as JSON.

const MAX_ENTRIES := 10
const MAX_NAME := 12
const PATH := "user://records.json"

var entries: Array[Dictionary] = []


## True when this score would make the board (an empty slot or beating the last).
func qualifies(score: int) -> bool:
	if score <= 0:
		return false
	return entries.size() < MAX_ENTRIES or score > int(entries.back().score)


func best() -> int:
	return int(entries[0].score) if not entries.is_empty() else 0


## Inserts a result and returns its rank (0 is first), or -1 if it didn't make it.
## Ties go below the existing entry, so the earlier record keeps its place.
func add(name: String, score: int, level: int, turns: int, date: String = "") -> int:
	if not qualifies(score):
		return -1
	var entry := {
		"name": clean_name(name), "score": score, "level": level, "turns": turns,
		"date": date if date != "" else Time.get_date_string_from_system(),
	}
	var rank := entries.size()
	for i in entries.size():
		if score > int(entries[i].score):
			rank = i
			break
	entries.insert(rank, entry)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)
	return rank


func clear() -> void:
	entries.clear()


static func clean_name(name: String) -> String:
	var n := name.strip_edges().replace("\n", " ")
	if n.is_empty():
		n = "Player"
	return n.left(MAX_NAME)


func to_json() -> String:
	return JSON.stringify(entries)


## Reads entries from JSON, skipping anything malformed.
func from_json(text: String) -> void:
	entries.clear()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Array:
		return
	var data: Array = json.data
	for e: Variant in data:
		if e is Dictionary and e.has("name") and e.has("score"):
			entries.append({
				"name": clean_name(str(e.name)), "score": int(e.score),
				"level": int(e.get("level", 1)), "turns": int(e.get("turns", 0)),
				"date": str(e.get("date", "")),
			})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)


func save(path: String = PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(to_json())


static func load_from(path: String = PATH) -> Records:
	var r := Records.new()
	if FileAccess.file_exists(path):
		r.from_json(FileAccess.get_file_as_string(path))
	return r
