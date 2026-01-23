extends Node3D
## Board3DTest - Test scene for verifying 3D board functionality
## Run this scene directly to test the 3D board without the full game
## Now featuring: Procedural champions, animations, VFX, Battle Chess choreography

var board: Board3D
var vfx_library: VFXLibrary
var choreographer: CombatChoreographer
var test_champions: Array = []

# Test state
var current_test: int = 0
var test_running: bool = false

func _ready() -> void:
	# Create Board3D
	board = Board3D.new()
	add_child(board)

	# Wait for board to initialize
	await get_tree().process_frame

	# Set up VFX library
	var vfx_container: Node = board.get_node_or_null("VFX")
	if vfx_container:
		vfx_library = VFXLibrary.new(vfx_container)

	# Set up choreographer
	choreographer = CombatChoreographer.new(board)

	# Set up some test terrain
	_setup_test_terrain()

	# Add test champions (now using ChampionFactory!)
	_add_test_champions()

	# Connect signals
	board.tile_clicked.connect(_on_tile_clicked)
	board.champion_clicked.connect(_on_champion_clicked)
	board.tile_hovered.connect(_on_tile_hovered)

	# Show instructions
	_create_ui()

	print("Board3D Test Scene Ready!")
	print("All 12 procedural champions loaded with unique appearances!")
	print("Press 1-9 to run different tests")


func _setup_test_terrain() -> void:
	"""Set up test terrain with walls and pits."""
	var terrain: Array = []
	for x in range(10):
		terrain.append([])
		for y in range(10):
			# Default empty
			var tile_type: int = 0

			# Add some walls
			if (x == 3 and y >= 3 and y <= 6) or (x == 6 and y >= 3 and y <= 6):
				tile_type = 1  # Wall

			# Central pit
			if x >= 4 and x <= 5 and y >= 4 and y <= 5:
				tile_type = 2  # Pit

			terrain[x].append(tile_type)

	board.set_terrain(terrain)


func _add_test_champions() -> void:
	"""Add test champions to the board."""
	# Player 1 champions (bottom left area)
	board.add_champion("brute_p1", Vector2i(1, 8), "Brute", 1)
	board.add_champion("ranger_p1", Vector2i(2, 8), "Ranger", 1)
	test_champions.append("brute_p1")
	test_champions.append("ranger_p1")

	# Player 2 champions (top right area)
	board.add_champion("berserker_p2", Vector2i(8, 1), "Berserker", 2)
	board.add_champion("shaman_p2", Vector2i(7, 1), "Shaman", 2)
	test_champions.append("berserker_p2")
	test_champions.append("shaman_p2")

	# Add one of each champion type for visual testing
	var all_champions: Array[String] = [
		"Beast", "Redeemer", "Confessor", "Barbarian",
		"Burglar", "Illusionist", "DarkWizard", "Alchemist"
	]

	var positions: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 9), Vector2i(9, 9),
		Vector2i(0, 4), Vector2i(9, 4), Vector2i(4, 0), Vector2i(5, 9)
	]

	for i in range(all_champions.size()):
		var champ_name: String = all_champions[i]
		var pos: Vector2i = positions[i]
		var player_id: int = 1 if i % 2 == 0 else 2
		var unique_id: String = champ_name.to_lower() + "_test"
		board.add_champion(unique_id, pos, champ_name, player_id)
		test_champions.append(unique_id)


func _create_ui() -> void:
	"""Create simple test UI."""
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	var label: Label = Label.new()
	label.text = """Board3D Battle Chess Test Scene

Controls:
- Mouse wheel: Zoom in/out
- Click: Select tile/champion
- 1: Test movement animation
- 2: Test Battle Chess attack choreography
- 3: Test highlight system
- 4: Test damage + VFX
- 5: Test death animation + VFX
- 6: Test spell casting + VFX
- 7: Test buff/debuff effects
- 8: Test all champions idle animations
- 9: Run full combat demo
- R: Reset positions

All 12 champions have unique:
- Body proportions and equipment
- Idle quirks and personalities
- Attack and death styles
- VFX color themes"""

	label.position = Vector2(20, 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_test_movement()
			KEY_2:
				_test_battle_chess_attack()
			KEY_3:
				_test_highlights()
			KEY_4:
				_test_damage_vfx()
			KEY_5:
				_test_death_vfx()
			KEY_6:
				_test_spell_casting()
			KEY_7:
				_test_buff_debuff()
			KEY_8:
				_test_idle_animations()
			KEY_9:
				_run_combat_demo()
			KEY_R:
				_reset_positions()


func _test_movement() -> void:
	"""Test champion movement animation."""
	if test_running:
		return
	test_running = true
	print("Testing movement animation...")

	# Move brute in a square pattern
	var champion_id: String = "brute_p1"
	var path: Array[Vector2i] = [
		Vector2i(1, 7),
		Vector2i(2, 7),
		Vector2i(2, 8),
		Vector2i(1, 8)
	]

	for pos in path:
		await board.animate_move(champion_id, [pos], 0.3)
		await get_tree().create_timer(0.1).timeout

	print("Movement test complete!")
	test_running = false


func _test_battle_chess_attack() -> void:
	"""Test full Battle Chess attack choreography."""
	if test_running:
		return
	test_running = true
	print("Testing Battle Chess attack choreography...")

	# Use choreographer for full sequence
	if choreographer:
		await choreographer.play_melee_attack("brute_p1", "berserker_p2", 5)
	else:
		# Fallback to board animation
		await board.animate_attack("brute_p1", "berserker_p2")

	print("Battle Chess attack complete!")
	test_running = false


func _test_highlights() -> void:
	"""Test highlight system."""
	print("Testing highlights...")

	board.clear_highlights()

	# Movement highlights
	var move_tiles: Array = [
		Vector2i(1, 7), Vector2i(2, 7), Vector2i(2, 8),
		Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 9)
	]
	board.set_highlights(move_tiles, Board3D.HighlightType.MOVE)

	await get_tree().create_timer(1.0).timeout

	# Attack highlights
	board.clear_highlights()
	var attack_tiles: Array = [
		Vector2i(2, 8), Vector2i(1, 7), Vector2i(0, 8)
	]
	board.set_highlights(attack_tiles, Board3D.HighlightType.ATTACK)

	await get_tree().create_timer(1.0).timeout

	# Cast highlights
	board.clear_highlights()
	var cast_tiles: Array = [
		Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8)
	]
	board.set_highlights(cast_tiles, Board3D.HighlightType.CAST)

	await get_tree().create_timer(1.0).timeout

	# Selected highlight
	board.set_highlight(Vector2i(1, 8), Board3D.HighlightType.SELECTED)

	await get_tree().create_timer(1.0).timeout
	board.clear_highlights()

	print("Highlight test complete!")


func _test_damage_vfx() -> void:
	"""Test damage effect with VFX."""
	print("Testing damage effect with VFX...")

	var champion: Node3D = board.get_champion_node("brute_p1")
	if champion:
		# Spawn VFX
		if vfx_library:
			vfx_library.spawn_impact(champion.position + Vector3(0, 0.5, 0), Color.RED)
			vfx_library.spawn_champion_attack("Brute", champion.position + Vector3(0, 0.5, 0))

		# Play hit animation
		if champion is Champion3D:
			champion.play_hit_animation(5)

	print("Damage VFX test complete!")


func _test_death_vfx() -> void:
	"""Test death animation with VFX."""
	if test_running:
		return
	test_running = true
	print("Testing death animation with VFX...")

	# Add temporary champion to kill
	board.add_champion("victim", Vector2i(5, 5), "Burglar", 2)
	await get_tree().create_timer(0.5).timeout

	var champion: Node3D = board.get_champion_node("victim")
	if champion:
		# Spawn death VFX
		if vfx_library:
			vfx_library.spawn_death(champion.position, Color.WHITE)

		# Play death animation
		if champion is Champion3D:
			champion.play_death_animation()
			await champion.animation_finished
		else:
			await get_tree().create_timer(0.7).timeout

		board.remove_champion("victim")

	print("Death VFX test complete!")
	test_running = false


func _test_spell_casting() -> void:
	"""Test spell casting with VFX."""
	if test_running:
		return
	test_running = true
	print("Testing spell casting...")

	var shaman: Node3D = board.get_champion_node("shaman_p2")
	if shaman:
		# Cast animation
		if shaman is Champion3D:
			shaman.play_cast_animation(false)

		# Spell VFX
		if vfx_library:
			await get_tree().create_timer(0.2).timeout
			vfx_library.spawn_champion_spell("Shaman", shaman.position + Vector3(0, 0.8, 0))

			# Target VFX
			var brute: Node3D = board.get_champion_node("brute_p1")
			if brute:
				await get_tree().create_timer(0.3).timeout
				vfx_library.spawn_effect(VFXLibrary.EffectType.SPELL_LIGHTNING, brute.position + Vector3(0, 1, 0), Color.CYAN, 0.5)
				if brute is Champion3D:
					brute.play_hit_animation(3)

		if shaman is Champion3D:
			await shaman.animation_finished

	print("Spell casting test complete!")
	test_running = false


func _test_buff_debuff() -> void:
	"""Test buff and debuff effects."""
	print("Testing buff/debuff effects...")

	# Test buff on ranger
	var ranger: Node3D = board.get_champion_node("ranger_p1")
	if ranger:
		if vfx_library:
			vfx_library.spawn_buff(ranger.position, Color.CYAN)
		if ranger is Champion3D:
			ranger.play_buff_animation()

	await get_tree().create_timer(0.5).timeout

	# Test debuff on berserker
	var berserker: Node3D = board.get_champion_node("berserker_p2")
	if berserker:
		if vfx_library:
			vfx_library.spawn_debuff(berserker.position, Color.PURPLE)
		if berserker is Champion3D:
			berserker.play_debuff_animation()

	print("Buff/debuff test complete!")


func _test_idle_animations() -> void:
	"""Watch all champions' unique idle animations."""
	print("Watching idle animations - each champion has unique quirks!")
	print("Observe for 10 seconds...")

	# Just let the idle animations run - they're automatic
	await get_tree().create_timer(10.0).timeout

	print("Idle animation showcase complete!")


func _run_combat_demo() -> void:
	"""Run a full combat demonstration."""
	if test_running:
		return
	test_running = true
	print("Running full combat demo...")

	# Brute attacks Berserker
	print("1. Brute attacks Berserker...")
	if choreographer:
		await choreographer.play_melee_attack("brute_p1", "berserker_p2", 5)
	await get_tree().create_timer(0.5).timeout

	# Shaman casts spell
	print("2. Shaman casts lightning...")
	if choreographer:
		await choreographer.play_spell_cast("shaman_p2", ["ranger_p1"], "lightning")
	await get_tree().create_timer(0.5).timeout

	# Ranger counterattacks (ranged)
	print("3. Ranger fires arrow...")
	if choreographer:
		await choreographer.play_ranged_attack("ranger_p1", "shaman_p2", 3)
	await get_tree().create_timer(0.5).timeout

	print("Combat demo complete!")
	test_running = false


func _reset_positions() -> void:
	"""Reset all champions to starting positions."""
	print("Resetting positions...")

	board.move_champion("brute_p1", Vector2i(1, 8))
	board.move_champion("ranger_p1", Vector2i(2, 8))
	board.move_champion("berserker_p2", Vector2i(8, 1))
	board.move_champion("shaman_p2", Vector2i(7, 1))

	board.clear_highlights()

	print("Positions reset!")


func _on_tile_clicked(grid_pos: Vector2i) -> void:
	"""Handle tile click."""
	print("Tile clicked: ", grid_pos)
	board.clear_highlights()
	board.set_highlight(grid_pos, Board3D.HighlightType.SELECTED)


func _on_champion_clicked(champion_id: String) -> void:
	"""Handle champion click."""
	print("Champion clicked: ", champion_id)

	# Highlight champion's tile
	var champion: Node3D = board.get_champion_node(champion_id)
	if champion:
		var grid_pos: Vector2i = board.world_to_grid(champion.position)
		board.clear_highlights()
		board.set_highlight(grid_pos, Board3D.HighlightType.SELECTED)


func _on_tile_hovered(grid_pos: Vector2i) -> void:
	"""Handle tile hover."""
	# Optional: show hover highlight
	pass
