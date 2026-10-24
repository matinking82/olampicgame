extends "res://tests/test_case.gd"


func _filled(count: int) -> Records:
	var r := Records.new()
	for i in count:
		r.add("P%d" % i, (i + 1) * 100, 1, 10, "2026-01-01")
	return r


func test_entries_stay_sorted_best_first() -> void:
	var r := Records.new()
	r.add("Low", 100, 1, 5)
	r.add("High", 900, 3, 50)
	r.add("Mid", 500, 2, 20)
	check_eq(r.entries.map(func(e: Dictionary) -> String: return e.name), ["High", "Mid", "Low"], "order")
	check_eq(r.best(), 900, "best")


func test_rank_is_returned() -> void:
	var r := _filled(3)
	check_eq(r.add("New", 250, 1, 1), 1, "between 300 and 200")
	check_eq(r.add("Top", 5000, 1, 1), 0, "new best")


func test_only_ten_kept() -> void:
	var r := _filled(10)
	check(not r.qualifies(50), "too low for a full board")
	check_eq(r.add("Nope", 50, 1, 1), -1, "rejected")
	check(r.qualifies(150), "beats the last")
	check_eq(r.add("Yes", 150, 1, 1), 9, "takes the last place")
	check_eq(r.entries.size(), Records.MAX_ENTRIES, "still ten")
	check_eq(int(r.entries.back().score), 150, "lowest dropped")


func test_ties_keep_the_older_entry_first() -> void:
	var r := Records.new()
	r.add("First", 300, 1, 1)
	check_eq(r.add("Second", 300, 1, 1), 1, "tie goes below")


func test_zero_never_qualifies() -> void:
	check(not Records.new().qualifies(0), "zero")


func test_names_are_cleaned() -> void:
	check_eq(Records.clean_name("   "), "Player", "blank")
	check_eq(Records.clean_name("  Ana  "), "Ana", "trimmed")
	check_eq(Records.clean_name("ABCDEFGHIJKLMNOP").length(), Records.MAX_NAME, "capped")


func test_json_round_trip() -> void:
	var r := _filled(4)
	var copy := Records.new()
	copy.from_json(r.to_json())
	check_eq(copy.entries.size(), 4, "count")
	check_eq(copy.best(), 400, "best kept")
	check_eq(copy.entries[0].name, "P3", "names kept")


func test_bad_json_is_ignored() -> void:
	var r := Records.new()
	r.from_json("not json at all")
	check(r.entries.is_empty(), "garbage")
	r.from_json('[{"name": "Ok", "score": 10}, {"oops": 1}, 5]')
	check_eq(r.entries.size(), 1, "keeps only valid entries")


func test_save_and_load() -> void:
	var path := "user://test_records.json"
	_filled(3).save(path)
	var loaded := Records.load_from(path)
	check_eq(loaded.best(), 300, "loaded")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Records.load_from(path).entries.is_empty(), "missing file is empty")
