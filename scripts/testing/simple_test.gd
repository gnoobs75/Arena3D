extends SceneTree
## Simple diagnostic test

func _init() -> void:
	print("========================================")
	print("  SIMPLE DIAGNOSTIC TEST")
	print("========================================")
	print("")
	print("NOTE: Autoloads not available in --script mode")
	print("Testing GameController directly...")
	print("")

	# Load the card database manually
	print("[TEST 1] Loading cards.json...")
	var file = FileAccess.open("res://data/cards.json", FileAccess.READ)
	if file == null:
		print("  ERROR: Cannot open cards.json")
		_write_result("FAILED: Cannot open cards.json")
		quit()
		return

	var json_text = file.get_as_text()
	file.close()
	print("  File loaded: %d characters" % json_text.length())

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		print("  ERROR: JSON parse failed")
		_write_result("FAILED: JSON parse error")
		quit()
		return

	var cards = json.data
	print("  Cards parsed: %d entries" % cards.size())

	# Test GameController class exists
	print("")
	print("[TEST 2] Creating GameController...")

	var gc = GameController.new()
	print("  GameController: %s" % gc)

	if gc == null:
		print("  ERROR: GameController is null!")
		_write_result("FAILED: GameController is null")
		quit()
		return

	print("  GameController created successfully")

	# Test GameState
	print("")
	print("[TEST 3] Creating GameState...")

	var p1: Array[String] = ["Brute", "Ranger"]
	var p2: Array[String] = ["Beast", "Shaman"]

	# GameState.create_new_game needs CardDatabase loaded
	# Let's just test if the class exists
	var gs = GameState.new()
	print("  GameState: %s" % gs)

	print("")
	print("========================================")
	print("  BASIC TESTS PASSED")
	print("========================================")

	_write_result("SUCCESS: Basic tests passed")
	quit()


func _write_result(msg: String) -> void:
	var f = FileAccess.open("C:/Claude/arena/test_output.txt", FileAccess.WRITE)
	if f:
		f.store_string("%s\n%s\n" % [Time.get_datetime_string_from_system(), msg])
		f.close()
