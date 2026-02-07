class_name AIController
extends RefCounted
## AIController - Main AI decision-making system
## Supports multiple difficulty levels

signal thinking_started()
signal thinking_finished()
signal action_chosen(action: Dictionary)

# Developer mode reasoning capture
var capture_reasoning: bool = false
var last_reasoning: Dictionary = {}
var last_scored_actions: Array = []  # All evaluated actions with scores

enum Difficulty {
	EASY,
	MEDIUM,
	HARD
}

const DIFFICULTY_PROFILES := {
	Difficulty.EASY: {
		"name": "Easy",
		"optimal_chance": 0.4,
		"score_randomization": 0.35,
		"lookahead": 0,
		"thinking_delay": 0.5
	},
	Difficulty.MEDIUM: {
		"name": "Medium",
		"optimal_chance": 0.7,
		"score_randomization": 0.15,
		"lookahead": 1,
		"thinking_delay": 0.8
	},
	Difficulty.HARD: {
		"name": "Hard",
		"optimal_chance": 0.95,
		"score_randomization": 0.05,
		"lookahead": 2,
		"thinking_delay": 1.0
	}
}

var difficulty: Difficulty = Difficulty.EASY
var profile: Dictionary
var player_id: int = 2
var game_controller: GameController

# Track actions per champion to balance between them
var _champion_action_count: Dictionary = {}  # champion_id -> action count this turn
# Track champions that need follow-up actions (e.g., just cast extraAttack, need to move+attack)
var _champion_needs_followup: Dictionary = {}  # champion_id -> reason string


func _init(controller: GameController, player: int = 2) -> void:
	game_controller = controller
	player_id = player
	set_difficulty(Difficulty.EASY)


func set_difficulty(diff: Difficulty) -> void:
	"""Set AI difficulty level."""
	difficulty = diff
	profile = DIFFICULTY_PROFILES[diff]


## ===== PUBLIC API FOR EXTERNAL USE (e.g., match_runner) =====

func get_valid_actions_for_player() -> Array:
	"""Get all valid actions for this AI's player. Public API for testing system."""
	var state := game_controller.get_game_state()
	return _get_all_valid_actions(state)


func choose_best_action(valid_actions: Array) -> Dictionary:
	"""Choose the best action from a list of valid actions. Public API for testing system."""
	if valid_actions.is_empty():
		return {"type": "end_turn"}

	var state := game_controller.get_game_state()

	# Score actions
	var scored_actions: Array = []
	for action: Dictionary in valid_actions:
		var score := _score_action(action, state)

		# Apply randomization based on difficulty
		var randomization: float = profile.get("score_randomization", 0.0)
		score *= randf_range(1.0 - randomization, 1.0 + randomization)

		scored_actions.append({"action": action, "score": score})

	# Sort by score
	scored_actions.sort_custom(func(a, b): return a["score"] > b["score"])

	# Filter out zero or negative score actions (they would have no effect)
	var viable_actions: Array = scored_actions.filter(func(a): return a["score"] > 0.0)

	# If no viable actions, end turn
	if viable_actions.is_empty():
		return {"type": "end_turn"}

	# Choose action based on difficulty
	var optimal_chance: float = profile.get("optimal_chance", 0.5)

	if randf() < optimal_chance:
		return viable_actions[0]["action"]
	else:
		var top_count := mini(3, viable_actions.size())
		var index := randi() % top_count
		return viable_actions[index]["action"]


func manage_response_slot() -> void:
	"""Evaluate and place the best response card in response slot. Public API."""
	_manage_response_slot()


## ===== END PUBLIC API =====


func take_turn() -> void:
	"""Execute AI turn - make decisions and perform actions."""
	thinking_started.emit()

	# Reset action tracking for new turn
	_champion_action_count.clear()
	_champion_needs_followup.clear()

	# Manage response slot at start of turn
	_manage_response_slot()

	var actions_taken := 0
	var max_actions := 20  # Safety limit
	var consecutive_failures := 0
	var max_failures := 5  # Break if too many consecutive failures

	while actions_taken < max_actions:
		# Wait for any response windows to close before continuing
		while game_controller.response_stack.is_open():
			print("AI: Waiting for response window to close...")
			await _delay(0.5)
			# Safety check - if we've been waiting too long, something is wrong
			consecutive_failures += 1
			if consecutive_failures > 10:
				print("AI: Response window stuck, forcing end turn")
				break

		if consecutive_failures > 10:
			break

		var action := _choose_action()

		if action.is_empty() or action.get("type") == "end_turn":
			break

		var result := _execute_action(action)
		if result.get("success", false):
			actions_taken += 1
			consecutive_failures = 0  # Reset on success
			action_chosen.emit(action)

			# Track action for this champion
			var champ_id: String = action.get("champion", "")
			if not champ_id.is_empty():
				_champion_action_count[champ_id] = _champion_action_count.get(champ_id, 0) + 1

			# Track follow-up needs: if we just cast a buff that requires follow-up actions
			if action.get("type") == "cast":
				var cast_card_data := CardDatabase.get_card(action.get("card", ""))
				var cast_effects: Array = cast_card_data.get("effect", [])
				var has_attack_buff := false  # extraAttack or combat synergy
				var has_move_buff := false    # extraMove, movement boost, unlimitedMovement
				for eff: Dictionary in cast_effects:
					var eff_type: String = str(eff.get("type", "")).to_lower()
					var eff_name: String = str(eff.get("name", "")).to_lower()
					var eff_stat: String = str(eff.get("stat", "")).to_lower()
					# Attack-requiring buffs
					if eff_type == "buff" and eff_name in ["extraattack", "extra_attack",
							"leech", "refuel", "critical", "attackheals",
							"apesmash", "elkrestoration"]:
						has_attack_buff = true
					# Power/range boosts (thisTurn) also need an attack follow-up
					elif eff_type == "statmod" and eff_stat in ["power", "range"]:
						var dur: String = str(eff.get("duration", "")).to_lower()
						var val = eff.get("value", 0)
						if dur == "thisturn" and ((val is int and val > 0) or val is String):
							has_attack_buff = true
					# Movement buffs
					elif eff_type == "buff" and eff_name in ["extramove", "extra_move",
							"unlimitedmovement", "agility"]:
						has_move_buff = true
					elif eff_type == "statmod" and eff_stat in ["movement", "movementspeed"]:
						var val = eff.get("value", 0)
						if val is int and val > 0:
							has_move_buff = true

				# Determine which champion needs the follow-up: the BUFF TARGET, not the caster
				# For friendly-targeted cards (Encouragement, Inspire, Alchemist flasks),
				# the follow-up belongs to the target champion
				var followup_champ := champ_id  # Default: caster
				var card_tgt_type: String = str(cast_card_data.get("target", "")).to_lower()
				if card_tgt_type in ["friendly", "ally", "allyorself"]:
					var cast_targets: Array = action.get("targets", [])
					if not cast_targets.is_empty():
						followup_champ = str(cast_targets[0])

				# Set follow-up based on what was granted
				if has_attack_buff and has_move_buff:
					_champion_needs_followup[followup_champ] = "move_then_attack"
				elif has_attack_buff:
					_champion_needs_followup[followup_champ] = "attack"
				elif has_move_buff:
					_champion_needs_followup[followup_champ] = "move"

			# Clear/advance follow-up if champion completed the needed action
			var followup: String = _champion_needs_followup.get(champ_id, "")
			if action.get("type") == "attack" and followup in ["attack", "move_then_attack"]:
				_champion_needs_followup.erase(champ_id)
			elif action.get("type") == "move" and followup == "move":
				_champion_needs_followup.erase(champ_id)  # Extra move used, done
			elif action.get("type") == "move" and followup == "move_then_attack":
				# Moved once — check if champion can now attack; if not, still need to move closer
				var followup_state := game_controller.get_game_state()
				var moved_champ := followup_state.get_champion(champ_id)
				if moved_champ:
					var range_calc := RangeCalculator.new()
					var targets_in_range := range_calc.get_valid_targets(moved_champ, followup_state)
					if not targets_in_range.is_empty():
						_champion_needs_followup[champ_id] = "attack"  # In range, attack next
					elif moved_champ.can_move():
						# Still not in range but can move again (extraMove) — keep moving
						_champion_needs_followup[champ_id] = "move_then_attack"
						print("AI: %s moved but still not in range, will move again" % moved_champ.champion_name)
					else:
						_champion_needs_followup[champ_id] = "attack"  # Can't move more, try attack
				else:
					_champion_needs_followup[champ_id] = "attack"
			elif action.get("type") == "move" and followup == "kite":
				_champion_needs_followup.erase(champ_id)  # Kited, done

			# After attacking, set kite follow-up if champion can still move
			# This ensures the AI prioritizes repositioning after attacking
			if action.get("type") == "attack" and not champ_id.is_empty():
				var kite_state := game_controller.get_game_state()
				var atk_champ := kite_state.get_champion(champ_id)
				if atk_champ and atk_champ.can_move():
					var threats := _get_position_threat_count(atk_champ.position, atk_champ, kite_state)
					if threats > 0:
						_champion_needs_followup[champ_id] = "kite"
						print("AI: %s should kite after attacking (%d threats)" % [atk_champ.champion_name, threats])
		else:
			consecutive_failures += 1
			print("AI: Action failed (%d consecutive failures)" % consecutive_failures)
			if consecutive_failures >= max_failures:
				print("AI: Too many failures, ending turn")
				break

		# Small delay between actions for visual feedback
		await _delay(0.3)

	# End turn
	game_controller.end_turn()
	thinking_finished.emit()


func _choose_action() -> Dictionary:
	"""Choose the next action to take."""
	var state := game_controller.get_game_state()

	# Get all valid actions
	var valid_actions := _get_all_valid_actions(state)

	# Debug: count action types per champion
	var champ_actions: Dictionary = {}  # champ_id -> {move: int, attack: int, cast: int}
	for action: Dictionary in valid_actions:
		var champ_id: String = action.get("champion", "unknown")
		if not champ_actions.has(champ_id):
			champ_actions[champ_id] = {"move": 0, "attack": 0, "cast": 0}
		var action_type: String = action.get("type", "")
		if champ_actions[champ_id].has(action_type):
			champ_actions[champ_id][action_type] += 1

	print("AI: Found %d valid actions:" % valid_actions.size())
	for champ_id: String in champ_actions:
		var counts: Dictionary = champ_actions[champ_id]
		var champ := state.get_champion(champ_id)
		var name: String = champ.champion_name if champ else champ_id
		print("  %s: moves=%d, attacks=%d, casts=%d (actions taken: %d)" % [
			name, counts["move"], counts["attack"], counts["cast"],
			_champion_action_count.get(champ_id, 0)
		])

	if valid_actions.is_empty():
		print("AI: No valid actions, ending turn")
		return {"type": "end_turn"}

	# PRIORITY: If a champion just cast a buff (e.g., extraAttack) and needs follow-up,
	# force their actions to be considered first (move into range, then attack)
	if not _champion_needs_followup.is_empty():
		var followup_actions: Array = []
		for followup_champ_id: String in _champion_needs_followup:
			var needed: String = _champion_needs_followup[followup_champ_id]
			for a: Dictionary in valid_actions:
				if a.get("champion", "") != followup_champ_id:
					continue
				# Prioritize actions based on follow-up need
				if needed == "attack" and (a.get("type") == "attack" or a.get("type") == "move"):
					followup_actions.append(a)
				elif needed == "move" and a.get("type") == "move":
					followup_actions.append(a)
				elif needed == "move_then_attack" and (a.get("type") == "move" or a.get("type") == "attack"):
					followup_actions.append(a)
				elif needed == "kite" and a.get("type") == "move":
					followup_actions.append(a)
		if not followup_actions.is_empty():
			print("AI: Prioritizing follow-up actions for champion with buff (%d available)" % followup_actions.size())
			valid_actions = followup_actions

	# Strategic check: don't end turn if one champion hasn't done anything useful
	# Filter actions to prioritize inactive champions
	var dominated_by_one_champ := _check_champion_imbalance(state)
	if dominated_by_one_champ:
		var inactive_champ_actions := valid_actions.filter(func(a: Dictionary) -> bool:
			var champ_id: String = a.get("champion", "")
			return _champion_action_count.get(champ_id, 0) == 0
		)
		if not inactive_champ_actions.is_empty():
			print("AI: Prioritizing inactive champion actions (%d available)" % inactive_champ_actions.size())
			valid_actions = inactive_champ_actions

	# Score actions
	var scored_actions: Array = []
	for action: Dictionary in valid_actions:
		var score := _score_action(action, state)

		# Skip actions with non-positive scores (they would have no effect or be harmful)
		if score <= 0:
			continue

		# Apply randomization based on difficulty
		var randomization: float = profile.get("score_randomization", 0.0)
		score *= randf_range(1.0 - randomization, 1.0 + randomization)

		scored_actions.append({"action": action, "score": score})

	# If all actions had zero or negative scores, end turn
	if scored_actions.is_empty():
		print("AI: All actions scored 0 or less, ending turn")
		return {"type": "end_turn"}

	# Sort by score
	scored_actions.sort_custom(func(a, b): return a["score"] > b["score"])

	# Choose action based on difficulty
	var optimal_chance: float = profile.get("optimal_chance", 0.5)
	var chosen_action: Dictionary

	if randf() < optimal_chance:
		# Pick best action
		chosen_action = scored_actions[0]["action"]
	else:
		# Pick random from top 3
		var top_count := mini(3, scored_actions.size())
		var index := randi() % top_count
		chosen_action = scored_actions[index]["action"]

	# Debug output
	var action_type: String = chosen_action.get("type", "unknown")
	var score: float = scored_actions[0]["score"] if not scored_actions.is_empty() else 0.0
	print("AI: Chose %s action (best score: %.1f)" % [action_type, score])
	if action_type == "cast":
		print("AI: Casting card '%s'" % chosen_action.get("card", ""))

	return chosen_action


func _get_all_valid_actions(state: GameState) -> Array:
	"""Get all valid actions for AI player."""
	var actions: Array = []

	for champ: ChampionState in state.get_champions(player_id):
		if not champ.is_alive():
			continue

		# Move actions
		if champ.can_move():
			var pathfinder := Pathfinder.new(state)
			var reachable := pathfinder.get_reachable_tiles(champ)
			for pos: Vector2i in reachable:
				actions.append({
					"type": "move",
					"champion": champ.unique_id,
					"target": pos
				})

		# Attack actions
		if champ.can_attack():
			var range_calc := RangeCalculator.new()
			var targets := range_calc.get_valid_targets(champ, state)
			for target: ChampionState in targets:
				actions.append({
					"type": "attack",
					"champion": champ.unique_id,
					"target": target.unique_id
				})

		# Cast actions
		if champ.can_cast():
			var hand := state.get_hand(player_id)
			var mana := state.get_mana(player_id)

			for card_name: String in hand:
				var card_data := CardDatabase.get_card(card_name)
				var cost: int = card_data.get("cost", 0)
				var card_type: String = card_data.get("type", "")

				if card_type == "Response":
					continue  # Response cards played reactively

				# CRITICAL: Champions can only cast their own cards
				var card_character: String = card_data.get("character", "")
				if not card_character.is_empty() and card_character != champ.champion_name:
					continue  # This card belongs to a different champion

				# Equipment cards: check if already equipped (can't equip twice)
				if card_type == "Equipment":
					if champ.has_equipment(card_name):
						continue  # Already equipped, skip
					# Check stackable property - some equipment can't be re-equipped
					var stackable: bool = card_data.get("stackable", true)
					if not stackable and champ.has_equipment(card_name):
						continue

				if cost <= mana:
					# Check if the card would have any effect before adding as valid action
					if not _would_card_have_effect(state, champ, card_data):
						continue  # Skip cards that would do nothing

					var cast_targets := _get_valid_cast_targets(state, champ, card_data)
					for targets: Array in cast_targets:
						actions.append({
							"type": "cast",
							"champion": champ.unique_id,
							"card": card_name,
							"targets": targets
						})

	# === Response slot actions ===
	# AI can place Response cards in the slot (doesn't require a specific champion)
	var current_slot := state.get_response_slot(player_id)
	if current_slot.is_empty():  # Only if slot is empty
		var hand := state.get_hand(player_id)
		for card_name: String in hand:
			var card_data := CardDatabase.get_card(card_name)
			if card_data.get("type", "") == "Response":
				# Check if this response card belongs to one of our living champions
				var card_character: String = card_data.get("character", "")
				var has_valid_owner := false
				for champ: ChampionState in state.get_champions(player_id):
					if champ.is_alive() and (card_character.is_empty() or card_character == champ.champion_name):
						has_valid_owner = true
						break
				if has_valid_owner:
					actions.append({
						"type": "place_response",
						"card": card_name
					})

	return actions


func _get_valid_cast_targets(state: GameState, caster: ChampionState, card_data: Dictionary) -> Array:
	"""Get valid target combinations for a card."""
	var target_sets: Array = []
	var target_type: String = card_data.get("target", "none")

	# Check if this is a healing card - we'll filter targets that don't need healing
	var is_heal_card := _is_healing_card(card_data)

	# Check if this card applies buffs - we'll filter targets that already have them
	var buff_names := _get_card_buff_names(card_data)
	var is_buff_card := not buff_names.is_empty()

	match target_type.to_lower():
		"none":
			# For AOE heals with no target, check if any friendly needs healing
			if is_heal_card:
				var any_needs_healing := false
				for ally: ChampionState in state.get_living_champions(player_id):
					if _would_heal_have_effect(card_data, ally, state):
						any_needs_healing = true
						break
				if not any_needs_healing:
					pass  # Don't add - no one needs healing
				else:
					target_sets.append([])
			else:
				target_sets.append([])
		"self":
			# Self-targeting cards should pass the caster's ID
			# Skip if this is a heal that wouldn't have effect (full HP or condition not met)
			if is_heal_card and not _would_heal_have_effect(card_data, caster, state):
				pass  # Don't add - heal wouldn't do anything
			# Skip if this is a buff and caster already has it
			elif is_buff_card and _target_already_has_buffs(caster, buff_names):
				pass  # Don't add - caster already has buff
			else:
				target_sets.append([caster.unique_id])
		"enemy":
			var opp_id := 1 if player_id == 2 else 2
			for enemy: ChampionState in state.get_living_champions(opp_id):
				# Check if enemy is in range for targeted cards
				if _is_valid_target_for_card(caster, enemy, card_data, state):
					target_sets.append([enemy.unique_id])
		"ally", "friendly":
			for ally: ChampionState in state.get_living_champions(player_id):
				if ally.unique_id != caster.unique_id:
					if _is_valid_target_for_card(caster, ally, card_data, state):
						# Skip if this is a heal that wouldn't have effect
						if is_heal_card:
							var would_work := _would_heal_have_effect(card_data, ally, state)
							print("AI: Heal target check - %s (HP: %d/%d), would_work=%s, card=%s" % [ally.champion_name, ally.current_hp, ally.max_hp, would_work, card_data.get("name", "?")])
							if not would_work:
								continue
						# Skip if this is a buff and ally already has it
						if is_buff_card and _target_already_has_buffs(ally, buff_names):
							continue
						target_sets.append([ally.unique_id])
		"champion", "any":
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive():
					if _is_valid_target_for_card(caster, champ, card_data, state):
						# Skip if this is a heal that wouldn't have effect
						if is_heal_card and not _would_heal_have_effect(card_data, champ, state):
							continue
						# Skip if this is a buff and target already has it
						if is_buff_card and _target_already_has_buffs(champ, buff_names):
							continue
						target_sets.append([champ.unique_id])
		"allyorself":
			for ally: ChampionState in state.get_living_champions(player_id):
				if _is_valid_target_for_card(caster, ally, card_data, state):
					# Skip if this is a heal that wouldn't have effect
					if is_heal_card and not _would_heal_have_effect(card_data, ally, state):
						continue
					# Skip if this is a buff and ally already has it
					if is_buff_card and _target_already_has_buffs(ally, buff_names):
						continue
					target_sets.append([ally.unique_id])
		"position":
			# Position-targeted cards (AOE spells like Rain of Arrows, Healing Rain, Light Bomb)
			target_sets = _get_position_targets(state, caster, card_data)
		"direction":
			# Direction-targeted cards (Ground Pound)
			target_sets = _get_direction_targets(state, caster, card_data)
		_:
			target_sets.append([])

	return target_sets


func _get_position_targets(state: GameState, caster: ChampionState, card_data: Dictionary) -> Array:
	"""Get valid position targets for AOE spells."""
	var target_sets: Array = []
	var effects: Array = card_data.get("effect", [])
	var is_healing := false
	var is_damage := false

	# Determine effect type
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "heal":
			is_healing = true
		elif etype == "damage":
			is_damage = true

	# For damage AOE, target positions near enemies (must be in caster range)
	if is_damage:
		var opp_id := 1 if player_id == 2 else 2
		for enemy: ChampionState in state.get_living_champions(opp_id):
			if _is_position_in_caster_range(caster, enemy.position):
				var pos_str := "%d,%d" % [enemy.position.x, enemy.position.y]
				target_sets.append([pos_str])

	# For healing AOE, target positions near friendlies who actually need healing
	elif is_healing:
		for ally: ChampionState in state.get_living_champions(player_id):
			if not _is_position_in_caster_range(caster, ally.position):
				continue
			# Only target if ally actually needs AND would benefit from healing
			if ally.current_hp < ally.max_hp:
				var would_work := _would_heal_have_effect(card_data, ally, state)
				print("AI: Position heal target check - %s at (%d,%d), HP: %d/%d, would_work=%s, card=%s" % [ally.champion_name, ally.position.x, ally.position.y, ally.current_hp, ally.max_hp, would_work, card_data.get("name", "?")])
				if would_work:
					var pos_str := "%d,%d" % [ally.position.x, ally.position.y]
					target_sets.append([pos_str])
			else:
				print("AI: Position heal skipped - %s at full HP (%d/%d)" % [ally.champion_name, ally.current_hp, ally.max_hp])

	# For movement AOE (Light Bomb), target positions adjacent to enemies so they get pushed
	else:
		var opp_id := 1 if player_id == 2 else 2
		var added_positions: Dictionary = {}
		for enemy: ChampionState in state.get_living_champions(opp_id):
			var adjacent_offsets := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
			for offset: Vector2i in adjacent_offsets:
				var adj_pos := enemy.position + offset
				if state.is_valid_position(adj_pos) and _is_position_in_caster_range(caster, adj_pos):
					var pos_str := "%d,%d" % [adj_pos.x, adj_pos.y]
					if not added_positions.has(pos_str):
						added_positions[pos_str] = true
						target_sets.append([pos_str])

	# If no valid targets found, return empty to skip this card
	return target_sets


func _get_direction_targets(state: GameState, caster: ChampionState, _card_data: Dictionary) -> Array:
	"""Get valid direction targets for line-of-sight spells."""
	var target_sets: Array = []
	var directions := ["up", "down", "left", "right"]
	var opp_id := 1 if player_id == 2 else 2

	for dir: String in directions:
		# Check if there's an enemy in this direction
		if _has_enemy_in_direction(state, caster.position, dir, opp_id):
			target_sets.append([dir])

	return target_sets


func _has_enemy_in_direction(state: GameState, from_pos: Vector2i, direction: String, opp_id: int) -> bool:
	"""Check if there's an enemy in the given direction from a position."""
	var dir_vec: Vector2i
	match direction:
		"up":
			dir_vec = Vector2i(0, -1)
		"down":
			dir_vec = Vector2i(0, 1)
		"left":
			dir_vec = Vector2i(-1, 0)
		"right":
			dir_vec = Vector2i(1, 0)
		_:
			return false

	var pos := from_pos + dir_vec
	while state.is_valid_position(pos):
		var terrain := state.get_terrain(pos)
		if terrain == GameState.Terrain.WALL:
			break  # Hit a wall, stop looking

		var champ := state.get_champion_at(pos)
		if champ != null and champ.is_alive() and champ.owner_id == opp_id:
			return true  # Found enemy

		pos += dir_vec

	return false


func _is_valid_target_for_card(caster: ChampionState, target: ChampionState, card_data: Dictionary, _state: GameState) -> bool:
	"""Check if a target is valid for a card (including range check).
	Must match the game's action_system.gd _is_in_range logic exactly."""
	# Self is always valid
	if caster.unique_id == target.unique_id:
		return true

	# Cards with explicit "global" range have no range restriction
	var card_range: String = str(card_data.get("range", "")).to_lower()
	if card_range == "global":
		return true

	# All other cards (including heal/buff) must be in range
	# This matches the game's action_system.gd _is_in_range check
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		# Melee: Chebyshev distance (8 directions)
		var dist: int = maxi(absi(target_pos.x - caster_pos.x), absi(target_pos.y - caster_pos.y))
		return dist <= caster.current_range
	else:
		# Ranged: Must be in cardinal direction and within range
		var dx: int = target_pos.x - caster_pos.x
		var dy: int = target_pos.y - caster_pos.y
		if dx != 0 and dy != 0:
			return false
		var dist: int = absi(dx) + absi(dy)
		return dist <= caster.current_range


func _is_healing_card(card_data: Dictionary) -> bool:
	"""Check if a card's primary purpose is healing."""
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "heal":
			return true
	return false


func _would_heal_have_effect(card_data: Dictionary, target: ChampionState, state: GameState) -> bool:
	"""Check if a heal card would actually heal the target (not just HP check, but also conditions)."""
	# If target is at full HP, no healing needed
	if target.current_hp >= target.max_hp:
		return false

	var hp_missing := target.max_hp - target.current_hp

	# Require minimum HP missing to avoid wasting heals on nearly-full targets
	# This also helps avoid no-ops when response cards might heal the target first
	# Only apply this minimum if target is not critically low (below 50% HP)
	var min_missing := 3
	if target.current_hp > target.max_hp / 2 and hp_missing < min_missing:
		return false  # Target is healthy enough, don't heal yet

	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype != "heal":
			continue

		var heal_value = effect.get("value", 0)

		# Check for conditional heals that might not trigger
		var condition: Dictionary = effect.get("condition", {})

		# Second Wind: "ifDamageAbove" condition
		if condition.has("ifDamageAbove"):
			var threshold: int = condition.get("ifDamageAbove", 0)
			var damage_taken: int = target.damage_taken_last_turn
			if damage_taken <= threshold:
				return false  # Condition not met, heal won't trigger

		# Life Payment: heal value is "oppHandSize"
		if heal_value is String:
			if heal_value == "oppHandSize":
				var opp_id := 1 if player_id == 2 else 2
				var opp_hand := state.get_hand(opp_id)
				if opp_hand.size() == 0:
					return false  # No cards in opponent's hand, heal is 0
			elif heal_value == "damageTaken":
				# Second Wind style - check if any damage was taken
				var damage_taken: int = target.damage_taken_last_turn
				if damage_taken <= 0:
					return false  # No damage taken, heal is 0

		# If heal value is 0, no effect
		if heal_value is int and heal_value <= 0:
			return false

	return true  # Heal should have effect


func _would_card_have_effect(state: GameState, caster: ChampionState, card_data: Dictionary) -> bool:
	"""Check if a card would have any meaningful effect when cast by this caster.
	This prevents the AI from casting cards that would do nothing (no targets in range,
	buffs that can't be used, heals on full HP targets, draws from empty sources, etc.)"""
	var effects: Array = card_data.get("effect", [])
	var opp_id := 1 if player_id == 2 else 2
	var card_target: String = str(card_data.get("target", "")).to_lower()

	# === CHECK CARD-LEVEL CONDITIONS ===
	var card_condition: Dictionary = card_data.get("condition", {})

	# ifDamaged - card only works if caster was damaged (e.g., Nature's Wrath)
	if card_condition.get("ifDamaged", false):
		if caster.damage_taken_last_turn <= 0:
			return false

	# ifNotInRange - card only works if caster is safe from enemies (e.g., Safe House)
	if card_condition.get("ifNotInRange", false):
		for enemy: ChampionState in state.get_living_champions(opp_id):
			if _is_in_caster_range(enemy, caster, state):
				return false

	# === SPECIAL: Pure self-heal cards — check if caster needs healing ===
	if card_target == "self" and _is_pure_heal_card(effects):
		if caster.current_hp >= caster.max_hp:
			return false  # Already at full HP, heal is wasted

	# === SPECIAL: Cards with both extraMove AND extraAttack (e.g., Endless Energy) ===
	# These are powerful combo cards - useful if enemies exist and caster can fight
	var has_extra_move := false
	var has_extra_attack := false
	for eff: Dictionary in effects:
		var buff_name: String = str(eff.get("name", "")).to_lower()
		if buff_name in ["extramove", "extra_move"]:
			has_extra_move = true
		if buff_name in ["extraattack", "extra_attack"]:
			has_extra_attack = true
	if has_extra_move and has_extra_attack:
		# Both buffs present - check there are enemies and caster can potentially attack
		if state.get_living_champions(opp_id).is_empty():
			return false  # No enemies to fight
		# Only cast if caster hasn't fully exhausted their actions
		if caster.has_attacked and caster.has_moved and caster.movement_remaining <= 0:
			return false  # Already done everything, card is wasted

	# === CHECK EACH EFFECT ===
	var any_effect_useful := false
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		var scope: String = str(effect.get("scope", "")).to_lower()
		var effect_condition: Dictionary = effect.get("condition", {})

		# --- Effect-level condition checks ---
		if effect_condition.has("ifLifeBelow"):
			var threshold: int = effect_condition.get("ifLifeBelow", 0)
			if caster.current_hp > threshold:
				continue
		if effect_condition.has("ifDamageAbove"):
			var threshold: int = effect_condition.get("ifDamageAbove", 0)
			if caster.damage_taken_last_turn <= threshold:
				continue

		# --- Scaling value checks (must be > 0) ---
		var effect_value = effect.get("value", 0)
		if effect_value is String:
			var calculated := _calculate_effect_value(effect_value, caster, state, effect_condition)
			if calculated <= 0:
				continue

		# --- DAMAGE checks ---
		if etype == "damage":
			var is_aoe := scope in ["enemies", "allenemies", "all_enemies", "all"]
			# Check if at least one valid target exists without full damage protection
			var has_damageable_target := false
			if scope == "enemies":
				for enemy: ChampionState in state.get_living_champions(opp_id):
					if _is_in_caster_range(caster, enemy, state) and not _has_full_damage_protection(enemy, is_aoe):
						has_damageable_target = true
						break
				if not has_damageable_target:
					continue
			elif scope in ["randomenemy", "allenemies", "all_enemies"]:
				for enemy: ChampionState in state.get_living_champions(opp_id):
					if not _has_full_damage_protection(enemy, is_aoe):
						has_damageable_target = true
						break
				if not has_damageable_target:
					continue
			elif scope == "all":
				# AOE all - useful if any enemy can be damaged
				for enemy: ChampionState in state.get_living_champions(opp_id):
					if not _has_full_damage_protection(enemy, true):
						has_damageable_target = true
						break
				if not has_damageable_target:
					continue
			# Single target damage with target "enemy" — need living unprotected enemies
			elif card_target == "enemy":
				for enemy: ChampionState in state.get_living_champions(opp_id):
					if not _has_full_damage_protection(enemy, is_aoe):
						has_damageable_target = true
						break
				if not has_damageable_target:
					continue
			any_effect_useful = true
			continue

		# --- HEAL checks ---
		if etype == "heal":
			# Check scaling heal values (Life Payment heals by oppHandSize)
			if effect_value is String:
				var heal_val_str: String = str(effect_value).to_lower()
				if heal_val_str == "opphandsize":
					# Life Payment - heal based on opponent's hand size
					if state.get_hand(opp_id).is_empty():
						continue  # No healing if opponent has no cards
					# Also check if caster needs healing
					if card_target == "self" and caster.current_hp >= caster.max_hp:
						continue
			if scope in ["allfriendlies", "all_friendlies", "friendlies"]:
				# Check if any friendly needs healing
				var any_needs_heal := false
				for champ: ChampionState in state.get_living_champions(player_id):
					if champ.current_hp < champ.max_hp:
						any_needs_heal = true
						break
				if not any_needs_heal:
					continue
			elif card_target == "self":
				if caster.current_hp >= caster.max_hp:
					continue
			elif card_target == "friendly":
				# At least one friendly needs healing
				var any_needs_heal := false
				for champ: ChampionState in state.get_living_champions(player_id):
					if champ.current_hp < champ.max_hp:
						any_needs_heal = true
						break
				if not any_needs_heal:
					continue
			any_effect_useful = true
			continue

		# --- DRAW checks ---
		if etype == "draw":
			var draw_source: String = str(effect.get("source", "")).to_lower()
			var draw_from: String = str(effect_condition.get("from", "")).to_lower()

			# Over Confident: draw based on damaged champions this turn
			if effect_value is String and str(effect_value).to_lower() == "damagedchamps":
				var damaged_count := 0
				for champ: ChampionState in state.get_all_champions():
					if champ.is_alive() and champ.damage_taken_this_turn > 0:
						damaged_count += 1
				if damaged_count == 0:
					continue
				# Also check deck not empty
				if state.get_deck(player_id).is_empty():
					continue
				any_effect_useful = true
				continue

			# Check if drawing from discard pile (via source or condition.from)
			if draw_source in ["discard", "oppdiscard", "opponentdiscard"] or draw_from == "discard":
				var source_pile: Array
				if draw_source in ["oppdiscard", "opponentdiscard"]:
					source_pile = state.get_discard(opp_id)
				else:
					source_pile = state.get_discard(player_id)
				if source_pile.is_empty():
					continue
				# Check if any card in the discard pile matches the filter conditions
				var filter_char: String = str(effect_condition.get("filter", "")).to_lower()
				var max_cost: int = effect_condition.get("maxCost", -1)
				var max_mana: int = effect_condition.get("maxMana", -1)
				if not filter_char.is_empty() or max_cost >= 0 or max_mana >= 0:
					var has_match := false
					for discard_card_name: String in source_pile:
						var discard_card := CardDatabase.get_card(discard_card_name)
						var card_char: String = str(discard_card.get("character", "")).to_lower()
						var card_cost: int = discard_card.get("cost", 0)
						# Filter by character name or card name substring
						if not filter_char.is_empty():
							if card_char != filter_char and filter_char not in discard_card_name.to_lower():
								continue
						if max_cost >= 0 and card_cost > max_cost:
							continue
						if max_mana >= 0 and card_cost > max_mana:
							continue
						has_match = true
						break
					if not has_match:
						continue
			else:
				# Drawing from deck
				var deck := state.get_deck(player_id)
				if deck.is_empty():
					continue
				# Check for filtered deck searches (e.g., Evil Within - search for Confessor cards)
				var filter_char: String = str(effect_condition.get("filter", "")).to_lower()
				if not filter_char.is_empty():
					var has_match := false
					for card_name: String in deck:
						var deck_card := CardDatabase.get_card(card_name)
						var card_char: String = str(deck_card.get("character", "")).to_lower()
						if card_char == filter_char.to_lower():
							has_match = true
							break
					if not has_match:
						continue  # No matching cards in deck
			any_effect_useful = true
			continue

		# --- DISCARD checks ---
		if etype == "discard":
			if scope in ["oppdiscard", "opponent"]:
				if state.get_hand(opp_id).is_empty():
					continue
			elif scope == "self" or scope.is_empty():
				# Self-discard as cost — only wasteful if hand is empty (besides this card)
				if state.get_hand(player_id).size() <= 1:
					continue
			any_effect_useful = true
			continue

		# --- BUFF utility checks ---
		if etype == "buff":
			var buff_name: String = str(effect.get("name", "")).to_lower()

			# extraAttack — need to be able to attack someone this turn
			if buff_name in ["extraattack", "extra_attack"]:
				# Can attack with normal movement, OR with extended movement (if we also have extraMove)
				if not _can_attack_any_enemy_this_turn(state, caster):
					if not (_has_extra_move_card_in_hand(state, caster) and _can_attack_with_extended_movement(state, caster)):
						continue

			# extraMove — useful if we haven't moved or need more repositioning
			elif buff_name in ["extramove", "extra_move"]:
				# Only useful if the champion can still benefit from extra movement
				if caster.has_moved and caster.movement_remaining <= 0:
					# Already exhausted movement — extra move is useful (reset)
					pass
				elif not caster.has_moved:
					# Haven't moved yet — extra move queues a second move phase
					pass
				else:
					continue  # Still has movement remaining, extra move is redundant

			# unlimitedMovement handled separately in the Quick Advantage block above

			# Combat synergy buffs — need to NOT have attacked yet and be able to attack
			elif buff_name in ["leech", "refuel", "attackheals", "critical",
					"apesmash", "elkrestoration", "copystats"]:
				if caster.has_attacked and not caster.has_buff("extraAttack"):
					continue  # Already attacked, combat synergy is wasted
				if not _can_attack_any_enemy_this_turn(state, caster):
					continue

			# returnDamage/intimidation — only useful if enemies can attack us
			elif buff_name in ["returndamage"]:
				# Still useful as deterrent even if not immediately attacked
				pass

			# damageReduction/shield/immune — always potentially useful as protection
			elif buff_name in ["damagereduction", "shield", "immune", "negateDamage", "negatespell"]:
				pass  # Always useful to have

			# stealMana/gainMana/bonusMana — check if mana would be useful
			elif buff_name in ["gainmana", "bonusmana"]:
				pass  # Mana is always useful

			# castFromDiscard — need cards in discard
			elif buff_name in ["castfromdiscard"]:
				if state.get_discard(player_id).is_empty():
					continue

			# Already has this exact buff (non-stackable) — avoid waste
			elif caster.has_buff(buff_name):
				# Some buffs stack, some don't — skip non-combat buffs that are already active
				if buff_name in ["stealth", "immune", "cheatdeath", "untouchable"]:
					continue

			any_effect_useful = true
			continue

		# --- STATMOD utility checks ---
		if etype == "statmod":
			var stat_name: String = str(effect.get("stat", "")).to_lower()
			var duration: String = str(effect.get("duration", "")).to_lower()

			# Power boost — only useful if we haven't attacked yet and can attack this turn
			if stat_name == "power" and duration == "thisturn":
				if caster.has_attacked and not caster.has_buff("extraAttack"):
					continue  # Already attacked, buff is wasted
				if not _can_attack_any_enemy_this_turn(state, caster):
					continue

			# Range boost (thisTurn) — only useful if we haven't attacked yet and can attack
			elif stat_name == "range" and duration == "thisturn":
				if caster.has_attacked and not caster.has_buff("extraAttack"):
					continue  # Already attacked, buff is wasted
				if not _can_attack_any_enemy_this_turn(state, caster):
					continue

			# Movement boost (thisTurn) — only useful if we haven't already moved
			elif stat_name in ["movement", "movementspeed"] and duration == "thisturn":
				if caster.has_moved and not caster.can_move():
					continue

			# nextTurn or persistent buffs — always useful
			any_effect_useful = true
			continue

		# --- DEBUFF checks ---
		if etype == "debuff":
			var debuff_name: String = str(effect.get("name", "")).to_lower()

			# Self-debuffs are COSTS, not benefits - don't count as useful
			# (e.g., Nap Time's "canAttack=false" on self is a downside)
			if card_target == "self" or scope == "self":
				continue  # Self-debuff, skip

			# dropEquipment — only useful if someone actually has equipment
			if debuff_name == "dropequipment":
				var anyone_has_equipment := false
				for champ: ChampionState in state.get_all_champions():
					if champ.is_alive() and not champ.equipment.is_empty():
						anyone_has_equipment = true
						break
				if not anyone_has_equipment:
					continue
				any_effect_useful = true
				continue

			if card_target == "enemy":
				# Need living enemies to target
				if state.get_living_champions(opp_id).is_empty():
					continue

				# Check if any enemy doesn't already have this debuff
				var any_enemy_can_debuff := false
				for enemy: ChampionState in state.get_living_champions(opp_id):
					if not enemy.has_debuff(debuff_name):
						any_enemy_can_debuff = true
						break
				if not any_enemy_can_debuff:
					continue

			elif scope in ["enemies", "allenemies", "all_enemies"]:
				if state.get_living_champions(opp_id).is_empty():
					continue

			any_effect_useful = true
			continue

		# --- MOVE effect checks ---
		if etype == "move":
			var move_value: String = str(effect.get("value", "")).to_lower()
			# Move effects (push, pull, teleport) — generally useful if targets exist
			if card_target == "enemy":
				if state.get_living_champions(opp_id).is_empty():
					continue
			# overWall (Heave) — only useful if enemy is near a wall AND can be thrown over
			# Enemy must be at position 1 or 8 (adjacent to wall) to be thrown over
			# Position 0 or 9 is AT the edge, nothing on the other side
			if move_value == "overwall":
				var any_throwable := false
				for enemy: ChampionState in state.get_living_champions(opp_id):
					var p := enemy.position
					# Can throw over if at position 1 or 8 (adjacent to wall, with space beyond)
					if p.x == 1 or p.x == 8 or p.y == 1 or p.y == 8:
						any_throwable = true
						break
				if not any_throwable:
					continue
			# toWall (Light Bomb) — only useful if some enemy is NOT already at a wall
			# AND the enemy is close enough to be in potential AOE range
			elif move_value == "towall":
				var any_pushable := false
				for enemy: ChampionState in state.get_living_champions(opp_id):
					var p := enemy.position
					# Not at wall if not at board edge (0 or 9 for a 10x10 board)
					# AND enemy must be within reasonable distance from caster (AOE range ~3)
					if p.x > 0 and p.x < 9 and p.y > 0 and p.y < 9:
						var dist := maxi(absi(caster.position.x - p.x), absi(caster.position.y - p.y))
						if dist <= 5:  # Reasonable targeting distance for AOE
							any_pushable = true
							break
				if not any_pushable:
					continue
			any_effect_useful = true
			continue

		# --- CUSTOM / ATTACK / other effects — assume useful ---
		any_effect_useful = true

	return any_effect_useful


func _is_pure_heal_card(effects: Array) -> bool:
	"""Check if a card's effects are purely healing (no damage, buffs, etc.)."""
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype != "heal":
			return false
	return not effects.is_empty()


func _has_full_damage_protection(champion: ChampionState, is_aoe: bool) -> bool:
	"""Check if a champion has protection that would completely block damage.
	is_aoe: true if the damage source is AOE (stealth doesn't protect from AOE)"""
	# Immune completely blocks all damage
	if champion.has_buff("immune"):
		return true
	# Shield blocks next instance
	if champion.has_buff("shield"):
		return true
	# negateDamage reduces next damage to 0
	if champion.has_buff("negateDamage"):
		return true
	# Stealth only protects from non-AOE damage
	if champion.has_buff("stealth") and not is_aoe:
		return true
	return false


func _calculate_effect_value(value_string: String, caster: ChampionState, state: GameState, condition: Dictionary = {}) -> int:
	"""Calculate the actual value for string-based effect values."""
	var opp_id := 1 if player_id == 2 else 2

	match value_string.to_lower():
		"power":
			return caster.current_power
		"opphandsize":
			return state.get_hand(opp_id).size()
		"damagetaken":
			return caster.damage_taken_last_turn
		"handsize":
			return state.get_hand(player_id).size()
		"discardcount":
			# Check for filter condition (e.g., Shadow Burst filters by DarkWizard)
			var filter_char: String = str(condition.get("filter", "")).to_lower()
			if filter_char.is_empty():
				return state.get_discard(player_id).size()
			# Filtered discard count
			var count := 0
			for card_name: String in state.get_discard(player_id):
				var card_data := CardDatabase.get_card(card_name)
				if str(card_data.get("character", "")).to_lower() == filter_char:
					count += 1
			return count
		"damagedchamps":
			var count := 0
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive() and champ.damage_taken_this_turn > 0:
					count += 1
			return count
		_:
			# Unknown string value, assume it would work
			return 1


func _is_in_caster_range(caster: ChampionState, target: ChampionState, state: GameState) -> bool:
	"""Check if target is within caster's attack range (for cards that use caster's range)."""
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		# Melee: Chebyshev distance (8 directions)
		var dist: int = maxi(absi(target_pos.x - caster_pos.x), absi(target_pos.y - caster_pos.y))
		return dist <= caster.current_range
	else:
		# Ranged: Must be adjacent OR in cardinal direction within range
		var dx: int = target_pos.x - caster_pos.x
		var dy: int = target_pos.y - caster_pos.y
		var chebyshev: int = maxi(absi(dx), absi(dy))

		# Adjacent (distance 1) is always in range for ranged
		if chebyshev <= 1:
			return true

		# Beyond adjacent, must be in cardinal direction
		if dx != 0 and dy != 0:
			return false
		var dist: int = absi(dx) + absi(dy)
		return dist <= caster.current_range


func _can_attack_any_enemy_this_turn(state: GameState, champ: ChampionState) -> bool:
	"""Check if champion can attack any enemy this turn - either already in range or can move into range."""
	var opp_id := 1 if player_id == 2 else 2
	var enemies := state.get_living_champions(opp_id)
	if enemies.is_empty():
		return false

	# Check if already in attack range of any enemy
	var range_calc := RangeCalculator.new()
	var current_targets := range_calc.get_valid_targets(champ, state)
	if not current_targets.is_empty():
		return true

	# Check if can move into attack range
	if champ.can_move():
		var pathfinder := Pathfinder.new(state)
		var reachable := pathfinder.get_reachable_tiles(champ)
		for tile: Vector2i in reachable:
			# Simulate being at this tile and check attack range
			var original_pos := champ.position
			champ.position = tile
			var targets_from_tile := range_calc.get_valid_targets(champ, state)
			champ.position = original_pos
			if not targets_from_tile:
				continue
			if targets_from_tile.size() > 0:
				return true

	return false


func _has_pre_attack_buff(effects: Array) -> bool:
	"""Check if effects contain buffs that should be cast before attacking.
	Covers: power/range statMods, extraAttack, and combat synergy buffs (leech, refuel, critical, etc.)."""
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "statmod":
			var stat: String = str(effect.get("stat", "")).to_lower()
			var duration: String = str(effect.get("duration", "")).to_lower()
			var value = effect.get("value", 0)
			if stat in ["power", "range"] and duration == "thisturn":
				# Positive power/range boosts must come before attack
				if value is int and value > 0:
					return true
				# String values like "handSize" (Grand Finale) are also pre-attack buffs
				if value is String:
					return true
		elif etype == "buff":
			var buff_name: String = str(effect.get("name", "")).to_lower()
			# All combat synergy buffs should be cast before attacking
			if buff_name in ["extraattack", "extra_attack", "leech", "refuel",
					"critical", "attackheals", "apesmash", "elkrestoration",
					"copystats"]:
				return true
	return false


func _has_power_buff_available(state: GameState, champ: ChampionState) -> bool:
	"""Check if this champion (or an ally) has a castable card that would give this champion power.
	Covers: self-targeted power buffs, friendly-targeted power buffs from ally's hand."""
	var mana := state.get_mana(champ.owner_id)
	# Check own hand for self-targeted power buffs
	var hand := state.get_hand(champ.owner_id)
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		if card_data.is_empty() or card_data.get("cost", 99) > mana:
			continue
		var card_char: String = str(card_data.get("character", ""))
		var card_target: String = str(card_data.get("target", "")).to_lower()
		# Self-targeted: must belong to this champion
		if card_target == "self" and card_char != champ.champion_name:
			continue
		# Check effects for power boost
		for eff: Dictionary in card_data.get("effect", []):
			var etype: String = str(eff.get("type", "")).to_lower()
			if etype == "statmod" and str(eff.get("stat", "")).to_lower() == "power":
				var val = eff.get("value", 0)
				if (val is int and val > 0) or val is String:
					return true
	return false


func _has_extra_move_card_in_hand(state: GameState, champ: ChampionState) -> bool:
	"""Check if the champion has an extraMove or movement boost card in hand they could cast."""
	var hand := state.get_hand(champ.owner_id)
	var mana := state.get_mana(champ.owner_id)
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		if card_data.is_empty():
			continue
		# Must be castable by this champion
		var card_char: String = card_data.get("character", "")
		if not card_char.is_empty() and card_char != champ.champion_name:
			continue
		var card_cost: int = card_data.get("cost", 0)
		if card_cost > mana:
			continue
		# Check if card grants extra movement
		var effects: Array = card_data.get("effect", [])
		for eff: Dictionary in effects:
			var eff_type: String = str(eff.get("type", "")).to_lower()
			var eff_name: String = str(eff.get("name", "")).to_lower()
			var eff_stat: String = str(eff.get("stat", "")).to_lower()
			if eff_type == "buff" and eff_name in ["extramove", "extra_move", "unlimitedmovement"]:
				return true
			if eff_type == "statmod" and eff_stat in ["movement", "movementspeed"]:
				var val = eff.get("value", 0)
				if val is int and val > 0:
					return true
	return false


func _can_attack_with_extended_movement(state: GameState, champ: ChampionState) -> bool:
	"""Check if champion could attack an enemy after using double movement (e.g., cast extraMove, move, move again).
	This simulates having twice the movement range to determine if an extraMove card would enable an attack."""
	var opp_id := 1 if player_id == 2 else 2
	var enemies := state.get_living_champions(opp_id)
	if enemies.is_empty():
		return false

	var range_calc := RangeCalculator.new()
	# Temporarily double movement to simulate extraMove
	var orig_movement := champ.current_movement
	var orig_remaining := champ.movement_remaining
	champ.current_movement = orig_movement * 2
	champ.movement_remaining = orig_movement * 2

	var pathfinder := Pathfinder.new(state)
	var reachable := pathfinder.get_reachable_tiles(champ)

	var can_reach := false
	for tile: Vector2i in reachable:
		var original_pos := champ.position
		champ.position = tile
		var targets := range_calc.get_valid_targets(champ, state)
		champ.position = original_pos
		if targets.size() > 0:
			can_reach = true
			break

	# Restore original values
	champ.current_movement = orig_movement
	champ.movement_remaining = orig_remaining
	return can_reach


func _is_position_in_caster_range(caster: ChampionState, target_pos: Vector2i) -> bool:
	"""Check if a board position is within the caster's attack range."""
	var caster_pos: Vector2i = caster.position
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		var dist: int = maxi(absi(target_pos.x - caster_pos.x), absi(target_pos.y - caster_pos.y))
		return dist <= caster.current_range
	else:
		var dx: int = target_pos.x - caster_pos.x
		var dy: int = target_pos.y - caster_pos.y
		var chebyshev: int = maxi(absi(dx), absi(dy))
		if chebyshev <= 1:
			return true
		if dx != 0 and dy != 0:
			return false
		var dist: int = absi(dx) + absi(dy)
		return dist <= caster.current_range


func _is_draw_with_self_damage(effects: Array) -> bool:
	"""Check if effects contain both a draw and self-damage (e.g., Lifetap)."""
	var has_draw := false
	var has_self_damage := false
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "draw":
			has_draw = true
		elif etype == "damage":
			has_self_damage = true
	return has_draw and has_self_damage


func _get_self_damage_amount(effects: Array, caster: ChampionState) -> int:
	"""Get total self-damage from effects."""
	var total := 0
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "damage":
			total += _calculate_card_damage(effect.get("value", 0), caster)
	return total


func _can_move_into_attack_range(state: GameState, champ: ChampionState) -> bool:
	"""Check if champion can move into attack range of any enemy (but isn't currently in range)."""
	if not champ.can_move():
		return false
	var opp_id := 1 if player_id == 2 else 2
	var range_calc := RangeCalculator.new()
	var pathfinder := Pathfinder.new(state)
	var reachable := pathfinder.get_reachable_tiles(champ)
	for tile: Vector2i in reachable:
		var original_pos := champ.position
		champ.position = tile
		var targets_from_tile := range_calc.get_valid_targets(champ, state)
		champ.position = original_pos
		if targets_from_tile.size() > 0:
			return true
	return false


func _get_card_buff_names(card_data: Dictionary) -> Array[String]:
	"""Get the names of buffs this card would apply."""
	var buff_names: Array[String] = []
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "buff":
			var buff_name: String = effect.get("name", "")
			if not buff_name.is_empty():
				buff_names.append(buff_name)
	return buff_names


func _target_already_has_buffs(target: ChampionState, buff_names: Array[String]) -> bool:
	"""Check if target already has all the buffs this card would apply."""
	if buff_names.is_empty():
		return false
	# If target has ALL the buffs already, the card would be redundant
	for buff_name: String in buff_names:
		if not target.has_buff(buff_name):
			return false  # At least one buff is missing, card would do something
	return true  # All buffs already present, card would be redundant


func _calculate_card_damage(damage_value, caster: ChampionState) -> int:
	"""Calculate damage amount from card effect value (handles string values like 'power')."""
	if damage_value is int:
		return damage_value
	elif damage_value is float:
		return int(damage_value)
	elif damage_value is String:
		match damage_value:
			"power":
				return caster.current_power
			"doublePower":
				return caster.current_power * 2
			"random1or2":
				return 1  # Conservative estimate for AI scoring
			"handSize":
				var state := game_controller.get_game_state()
				return state.get_hand(caster.owner_id).size()
			"oppHandSize":
				var state := game_controller.get_game_state()
				var opp_id := 2 if caster.owner_id == 1 else 1
				return state.get_hand(opp_id).size()
			_:
				# Try to parse as integer string
				if damage_value.is_valid_int():
					return damage_value.to_int()
				return 0
	return 0


func _score_action(action: Dictionary, state: GameState) -> float:
	"""Score an action based on utility."""
	var score := 0.0
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			score = _score_move(action, state)
		"attack":
			score = _score_attack(action, state)
		"cast":
			score = _score_cast(action, state)
		"place_response":
			score = _score_place_response(action, state)

	# If the action has no intrinsic value (e.g., heal on full HP), skip it entirely
	# Don't add fairness bonuses to worthless actions
	if score <= 0.0:
		return 0.0

	# Strong fairness bonus for champions that haven't acted
	# This ensures both champions participate in each turn
	var champ_id: String = action.get("champion", "")
	var action_count: int = _champion_action_count.get(champ_id, 0)

	# Check if the OTHER champion has already acted
	var other_champ_acted := false
	var other_champ_action_count := 0
	for other_id: String in _champion_action_count:
		if other_id != champ_id:
			other_champ_action_count = _champion_action_count[other_id]
			if other_champ_action_count > 0:
				other_champ_acted = true
				break

	if action_count == 0:
		# Strong bonus for champions that haven't acted at all
		score += 8.0
		# Extra bonus if the other champion already acted - balance the turn
		if other_champ_acted:
			score += 5.0
	elif action_count == 1:
		score += 3.0  # Smaller bonus for only one action
	elif action_count >= 3:
		# Penalty for using same champion too much
		score -= 2.0

	return score


func _score_move(action: Dictionary, state: GameState) -> float:
	"""Score a move action with kiting/hit-and-run awareness.
	Ranged champions prefer maintaining distance; all champions prefer safe positions post-attack."""
	var score := 2.0  # Base move value
	var champion := state.get_champion(action.get("champion", ""))
	var target_pos: Vector2i = action.get("target", Vector2i.ZERO)

	if champion == null:
		return 0.0

	var opp_id := 1 if player_id == 2 else 2
	var range_calc := RangeCalculator.new()
	var is_ranged: bool = champion.current_range > 1

	# Check current attack capability
	var current_targets := range_calc.get_valid_targets(champion, state)
	var can_currently_attack := not current_targets.is_empty()

	# Simulate being at target position to check attack range from there
	var original_pos := champion.position
	champion.position = target_pos
	var targets_from_new_pos := range_calc.get_valid_targets(champion, state)
	var will_be_in_range := not targets_from_new_pos.is_empty()
	var low_hp_enemy_in_range := false
	for t: ChampionState in targets_from_new_pos:
		if t.current_hp <= champion.current_power:
			low_hp_enemy_in_range = true
			break
	champion.position = original_pos

	# Calculate distances to enemies from current and target positions
	var current_min_dist := 999
	var target_min_dist := 999
	for enemy: ChampionState in state.get_living_champions(opp_id):
		current_min_dist = mini(current_min_dist, _chebyshev_distance(champion.position, enemy.position))
		target_min_dist = mini(target_min_dist, _chebyshev_distance(target_pos, enemy.position))

	# Safety evaluation: how threatened is this position?
	var current_threats := _get_position_threat_count(champion.position, champion, state)
	var target_threats := _get_position_threat_count(target_pos, champion, state)
	var target_is_safe := target_threats == 0

	# === POST-ATTACK KITING (Hit and Run) ===
	# After attacking, moving to safety is the HIGHEST priority for all champions
	if champion.has_attacked:
		# Kiting: move to a safe position after attacking
		if target_is_safe and current_threats > 0:
			score += 20.0  # HUGE bonus — escape from danger after attacking
			if is_ranged:
				score += 5.0  # Extra incentive for ranged to kite
		elif target_threats < current_threats:
			score += (current_threats - target_threats) * 8.0  # Reduce threat exposure
		elif target_is_safe:
			score += 10.0  # Already safe but moving to stay safe
		else:
			score += 1.0  # Post-attack move to equally threatened position

		# For ranged champions: prefer maintaining distance even after attacking
		if is_ranged and target_min_dist > current_min_dist:
			score += (target_min_dist - current_min_dist) * 3.0  # Reward moving away

		return maxf(score, 0.5)

	# === PRE-ATTACK MOVEMENT ===

	# 0-power champion with no buff potential — don't move toward enemies to attack
	var has_damage_potential := champion.current_power > 0 or _has_power_buff_available(state, champion)

	# Haven't attacked yet — need to get into attack range
	if not can_currently_attack and will_be_in_range and has_damage_potential:
		score += 15.0  # High priority to get into the fight
		if low_hp_enemy_in_range:
			score += 10.0  # Moving to kill is very valuable

		# RANGED CHAMPIONS: prefer attack positions that are SAFE (max range, not melee)
		if is_ranged:
			if target_is_safe:
				score += 8.0  # Attack from safety = ideal
			elif target_threats < current_threats:
				score += 3.0
			# Penalize moving INTO melee range when you have range
			if target_min_dist <= 1:
				score -= 10.0  # Never walk into melee if you can shoot from afar!
			# Prefer positions at max range (further = safer)
			score += minf(target_min_dist, champion.current_range) * 1.0

	elif not can_currently_attack and not will_be_in_range:
		# Can't attack from either position — evaluate approach (only if we can deal damage)
		if has_damage_potential:
			if target_min_dist < current_min_dist:
				score += (current_min_dist - target_min_dist) * 2.5  # Getting closer
			# Melee champions want to close distance aggressively
			if not is_ranged and target_min_dist <= 1:
				score += 6.0  # Adjacent to enemy

	elif can_currently_attack and not champion.has_attacked:
		# Currently in attack range and haven't attacked — should attack first!
		score -= 8.0  # Strong penalty — attack before moving!

		# Exception: if moving to a MUCH safer position AND still in range, consider it
		if will_be_in_range and target_threats < current_threats:
			score += (current_threats - target_threats) * 4.0

	# === GENERAL SAFETY PREFERENCE ===
	# All champions prefer less-threatened positions
	if target_threats < current_threats:
		score += (current_threats - target_threats) * 2.0
	elif target_threats > current_threats:
		score -= (target_threats - current_threats) * 2.0

	# Ranged champions: penalize moving CLOSER to melee enemies unnecessarily
	if is_ranged and target_min_dist < current_min_dist and target_min_dist <= 2:
		var closing_penalty := (current_min_dist - target_min_dist) * 3.0
		score -= closing_penalty

	return maxf(score, 0.5)  # Minimum score to keep moves as options


func _chebyshev_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate Chebyshev distance (8-directional king moves)."""
	return maxi(absi(to.x - from.x), absi(to.y - from.y))


func _is_position_safe(pos: Vector2i, champion: ChampionState, state: GameState) -> bool:
	"""Check if a position is safe from enemy melee attacks next turn.
	Returns true if no enemy can move+attack this position on their next turn."""
	var opp_id := 1 if player_id == 2 else 2
	for enemy: ChampionState in state.get_living_champions(opp_id):
		if _can_enemy_reach_and_attack(enemy, pos, state):
			return false
	return true


func _get_position_threat_count(pos: Vector2i, champion: ChampionState, state: GameState) -> int:
	"""Count how many enemies could reach and attack this position next turn."""
	var opp_id := 1 if player_id == 2 else 2
	var threats := 0
	for enemy: ChampionState in state.get_living_champions(opp_id):
		if _can_enemy_reach_and_attack(enemy, pos, state):
			threats += 1
	return threats


func _can_enemy_reach_and_attack(enemy: ChampionState, target_pos: Vector2i, state: GameState) -> bool:
	"""Check if an enemy champion could move to attack a given position on their next turn.
	Uses the enemy's movement + range to determine threat radius."""
	var enemy_movement: int = enemy.current_movement
	var enemy_range: int = enemy.current_range
	var is_melee: bool = enemy_range <= 1

	if is_melee:
		# Melee: can reach target_pos if Chebyshev distance <= movement + range
		var dist := _chebyshev_distance(enemy.position, target_pos)
		return dist <= enemy_movement + enemy_range
	else:
		# Ranged enemy: can attack from cardinal directions at range
		# They need to move to a tile from which they can shoot target_pos
		# Simplification: check if enemy could reach a cardinal-aligned tile within range
		var dist := _chebyshev_distance(enemy.position, target_pos)
		# If very far away, can't reach even with full movement + range
		if dist > enemy_movement + enemy_range:
			return false
		# Ranged can also attack adjacent (all 8 dirs), so check Chebyshev for adjacent
		if dist <= enemy_movement + 1:
			return true
		# Check cardinal alignment: enemy needs to reach a tile on same row/col within range
		# They can move enemy_movement tiles then fire enemy_range tiles in cardinal direction
		var dx := target_pos.x - enemy.position.x
		var dy := target_pos.y - enemy.position.y
		# Same row: enemy moves along x, then fires along y (or is already aligned)
		if absi(dx) <= enemy_movement and absi(dy) <= enemy_range:
			return true
		if absi(dy) <= enemy_movement and absi(dx) <= enemy_range:
			return true
		return false


func _check_champion_imbalance(state: GameState) -> bool:
	"""Check if one champion has been doing all the work while the other is idle."""
	var living_champs := state.get_living_champions(player_id)
	if living_champs.size() < 2:
		return false  # Only one champion, no imbalance possible

	# Check action counts
	var max_actions := 0
	var min_actions := 999
	var idle_count := 0

	for champ: ChampionState in living_champs:
		var count: int = _champion_action_count.get(champ.unique_id, 0)
		max_actions = maxi(max_actions, count)
		min_actions = mini(min_actions, count)
		if count == 0:
			idle_count += 1

	# Imbalance if one champion has done 2+ actions and another has done none
	if max_actions >= 2 and idle_count > 0:
		return true

	return false


func _score_attack(action: Dictionary, state: GameState) -> float:
	"""Score an attack action - ATTACKS ARE HIGH PRIORITY."""
	var attacker := state.get_champion(action.get("champion", ""))
	var target := state.get_champion(action.get("target", ""))

	if attacker == null or target == null:
		return 0.0

	# 0 power = 0 damage = pointless unless champion can buff power first
	if attacker.current_power <= 0:
		if _has_power_buff_available(state, attacker):
			return 1.0  # Very low — should buff first, then attack
		return 0.0

	var score := 15.0  # HIGH base attack value - attacking is the goal!

	# MASSIVE bonus for potential kills - this is the win condition
	if target.current_hp <= attacker.current_power:
		score += 25.0  # Huge kill bonus - always take the kill!

	# Strong bonus for attacking low HP enemies (close to kill)
	var hp_ratio := float(target.current_hp) / float(target.max_hp)
	score += (1.0 - hp_ratio) * 8.0  # Up to +8 for near-dead enemies

	# Prefer attacking high-threat enemies (high power = dangerous)
	if target.current_power >= 2:
		score += 3.0

	# Bonus if attacker has high power (maximize damage output)
	score += attacker.current_power * 2.0

	return score


func _score_cast(action: Dictionary, state: GameState) -> float:
	"""Score a card cast action - prioritize damage and kills."""
	var score := 3.0  # Base cast value
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)
	var targets: Array = action.get("targets", [])
	var caster := state.get_champion(action.get("champion", ""))

	if card_data.is_empty() or caster == null:
		return 0.0

	var cost: int = card_data.get("cost", 0)
	var effects: Array = card_data.get("effect", [])
	var mana := state.get_mana(player_id)

	# Special case: self-targeted cards with self-damage that provide a benefit
	# (Lifetap: draw+damage, Berserker Enrage: power+damage, No Pain No Gain: extraAttack+damage,
	#  Pursuit: movement+damage)
	var card_target_type: String = str(card_data.get("target", "")).to_lower()
	var self_damage_amount := _get_self_damage_amount(effects, caster)
	if card_target_type == "self" and self_damage_amount > 0:
		# Don't cast if self-damage would kill us or leave us critically low
		if caster.current_hp <= self_damage_amount + 2:
			return 0.0  # Too risky
		# Draw + self-damage (Lifetap): high priority for card advantage
		if _is_draw_with_self_damage(effects):
			if caster.current_hp > self_damage_amount + 5:
				return 20.0
			return 12.0
		# Power/extraAttack + self-damage (Berserker Enrage, No Pain No Gain):
		# only if we can attack
		if _has_pre_attack_buff(effects):
			if not caster.has_attacked and _can_attack_any_enemy_this_turn(state, caster):
				return 18.0 if caster.current_hp > self_damage_amount + 5 else 10.0
			return 0.0  # Wasted if can't attack
		# Movement + self-damage (Pursuit): only if we need movement
		var has_move_buff := false
		for eff: Dictionary in effects:
			var sn: String = str(eff.get("stat", "")).to_lower()
			if eff.get("type", "").to_lower() == "statmod" and sn in ["movement", "movementspeed"]:
				has_move_buff = true
		if has_move_buff:
			if not _can_attack_any_enemy_this_turn(state, caster) or not caster.has_moved:
				return 14.0 if caster.current_hp > self_damage_amount + 5 else 8.0
			return 2.0  # Already in range and moved, limited value

	# Tradeoff cards: special scoring for cards with mixed positive/negative effects
	var has_movement_boost := false
	var has_range_penalty := false
	var has_power_boost := false
	var has_move_lock := false
	var has_attack_lock := false
	for eff: Dictionary in effects:
		var et: String = str(eff.get("type", "")).to_lower()
		var sn: String = str(eff.get("stat", "")).to_lower()
		var bn: String = str(eff.get("name", "")).to_lower()
		if et == "statmod" and sn in ["movement", "movementspeed"] and eff.get("value", 0) is int and eff.get("value", 0) > 0:
			has_movement_boost = true
		if et == "statmod" and sn == "range" and eff.get("value", 0) is int and eff.get("value", 0) < 0:
			has_range_penalty = true
		if et == "statmod" and sn == "power" and eff.get("value", 0) is int and eff.get("value", 0) > 0:
			has_power_boost = true
		if et == "debuff" and bn == "canmove" and eff.get("value", true) == false:
			has_move_lock = true
		if et == "debuff" and bn == "canattack" and eff.get("value", true) == false:
			has_attack_lock = true
		if et == "buff" and bn == "unlimitedmovement":
			has_movement_boost = true

	# Swiftness-type: +movement, -range → only useful when out of range and need to close in
	if has_movement_boost and has_range_penalty:
		var range_calc := RangeCalculator.new()
		var in_range := range_calc.get_valid_targets(caster, state).size() > 0
		if in_range:
			return 0.0  # Already in range — range penalty would be harmful
		# Not in range — movement helps close the gap
		return 10.0

	# Focus Shot-type: +power, locks movement → only useful when already in attack range
	if has_power_boost and has_move_lock:
		var range_calc := RangeCalculator.new()
		var in_range := range_calc.get_valid_targets(caster, state).size() > 0
		if not in_range:
			return 0.0  # Can't move AND not in range — useless
		if caster.has_attacked and not caster.has_buff("extraAttack"):
			return 0.0  # Already attacked — buff is wasted
		return 18.0  # In range, haven't attacked — very strong

	# Quick Advantage-type: unlimited movement, locks attack → escape-only card
	if has_movement_boost and has_attack_lock:
		# This is purely a "get away" card — only use when BOTH threatened AND low HP
		if caster.has_attacked:
			return 0.0  # Already attacked, card is invalid anyway
		# Check if enemies can reach/attack us
		var enemies_threatening := 0
		for enemy: ChampionState in state.get_champions(3 - player_id):
			if not enemy.is_alive():
				continue
			var dist: int = maxi(absi(caster.position.x - enemy.position.x), absi(caster.position.y - enemy.position.y))
			if dist <= enemy.current_range + enemy.current_movement:
				enemies_threatening += 1
		if enemies_threatening == 0:
			return 0.0  # Not in danger, no need to flee
		# STRICT: Must be BOTH threatened AND low HP to justify giving up attack
		var hp_pct := float(caster.current_hp) / float(caster.max_hp)
		if hp_pct > 0.5:
			return 0.0  # Above 50% HP — fight instead, don't waste the card
		# Low HP AND threatened — escape is justified
		return 6.0 + (1.0 - hp_pct) * 10.0  # More desperate = higher value

	# Evaluate effects
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"damage":
				var damage = effect.get("value", 0)
				var scope: String = effect.get("scope", "target")

				# Calculate actual damage amount (handle string values like "power")
				var actual_damage := _calculate_card_damage(damage, caster)

				# Skip if damage would be 0 (e.g., DarkWizard with 0 power casting Shadow Bolt)
				if actual_damage <= 0:
					# Don't return 0 yet - card might have other effects
					continue

				# Check if target has damage immunity/reduction
				var has_valid_target := false
				if not targets.is_empty():
					var target := state.get_champion(str(targets[0]))
					if target:
						# Check for immunity
						if target.has_buff("immune") or target.has_buff("shield"):
							# Damage would be negated, skip this effect
							continue
						# Check for damage reduction
						var reduction := target.get_buff_stacks("damageReduction")
						var final_damage := maxi(0, actual_damage - reduction)
						if final_damage <= 0:
							# Damage would be reduced to 0, skip
							continue
						has_valid_target = true
						actual_damage = final_damage

				# Damage is very valuable - 3 points per damage
				score += actual_damage * 3.0

				# Multi-target damage is extremely valuable
				if scope == "enemies" or scope == "allenemies":
					score += actual_damage * 5.0

				# HUGE bonus for kill potential
				if has_valid_target and not targets.is_empty():
					var target := state.get_champion(str(targets[0]))
					if target and target.current_hp <= actual_damage:
						score += 20.0  # Big kill bonus for spells too!

			"heal":
				var heal = effect.get("value", 0)
				# Determine the heal target first
				var heal_target: ChampionState = null
				if not targets.is_empty():
					var target_id: String = str(targets[0])
					var potential_target := state.get_champion(target_id)
					if potential_target:
						heal_target = potential_target
					else:
						# Check if it's a position target (e.g., "7,5" for AOE heals)
						var parts := target_id.split(",")
						if parts.size() == 2:
							var pos := Vector2i(int(parts[0]), int(parts[1]))
							# Find FRIENDLY champion at this position who needs healing most
							var best_target: ChampionState = null
							var most_missing := 0
							for champ: ChampionState in state.get_living_champions(player_id):
								var dist := maxi(absi(champ.position.x - pos.x), absi(champ.position.y - pos.y))
								if dist <= 1:  # AOE radius
									var missing := champ.max_hp - champ.current_hp
									if missing > most_missing:
										most_missing = missing
										best_target = champ
							if best_target:
								heal_target = best_target
							else:
								# No friendly at this position needs healing
								return 0.0
				else:
					# No target specified, default to caster for self-heals
					heal_target = caster

				# If we somehow have no heal target, skip
				if heal_target == null:
					return 0.0

				# Check if target is at full HP (no healing needed)
				var hp_missing := heal_target.max_hp - heal_target.current_hp
				if hp_missing <= 0:
					return 0.0  # Target at full HP, heal has no effect

				if heal is int:
					var effective_heal := mini(heal, hp_missing)

					# If healing would have no effect, return very low score immediately
					if effective_heal <= 0:
						return 0.0  # Don't cast heals that do nothing

					# Value healing based on effectiveness
					score += effective_heal * 1.5

					# Urgent healing when target is very low
					if heal_target.current_hp <= 5:
						score += effective_heal * 2.5
				elif heal is String:
					# Handle string-based heal values (e.g., "oppHandSize", "damageTaken")
					var computed_heal := 0
					if heal == "oppHandSize":
						var opp_id := 1 if player_id == 2 else 2
						var opp_hand := state.get_hand(opp_id)
						computed_heal = opp_hand.size()
					elif heal == "damageTaken":
						computed_heal = heal_target.damage_taken_last_turn

					if computed_heal <= 0:
						return 0.0  # No healing would occur

					var effective_heal := mini(computed_heal, hp_missing)
					score += effective_heal * 1.5

					if heal_target.current_hp <= 5:
						score += effective_heal * 2.5

			"statMod":
				var stat: String = effect.get("stat", "")
				var value = effect.get("value", 0)
				var sm_duration: String = str(effect.get("duration", "")).to_lower()
				# Handle string values (e.g., Grand Finale power=handSize)
				var numeric_value: int = 0
				if value is int:
					numeric_value = value
				elif value is String:
					# Estimate string-based values
					if value == "handSize":
						numeric_value = state.get_hand(player_id).size()
					elif value == "power":
						numeric_value = caster.current_power
					elif value == "random":
						numeric_value = 2  # Average estimate
					else:
						numeric_value = 2  # Default estimate
				if numeric_value > 0:
					match stat:
						"power":
							if sm_duration == "thisturn" and caster.has_attacked and not caster.has_buff("extraAttack"):
								score += 0.0  # Wasted — already attacked
							elif sm_duration == "thisturn" and not caster.has_attacked:
								score += numeric_value * 6.0  # High priority — buff BEFORE attacking
							else:
								score += numeric_value * 4.0
						"range":
							if sm_duration == "thisturn" and caster.has_attacked and not caster.has_buff("extraAttack"):
								score += 0.0  # Wasted
							elif sm_duration == "thisturn" and not caster.has_attacked:
								score += numeric_value * 3.0  # Buff before attacking
							else:
								score += numeric_value * 2.0
						"movement", "movementspeed":
							score += numeric_value * 1.5
						"random":
							# Random stat boost (Versatility, Battlecry) — average usefulness
							if sm_duration == "thisturn" and not caster.has_attacked:
								score += numeric_value * 4.0  # Could be power
							else:
								score += numeric_value * 2.0
				elif numeric_value < 0:
					# Negative statMods (e.g., range -2 from Power Shot) — penalty
					match stat:
						"range":
							score += numeric_value * 1.0  # Small penalty
						"power":
							score += numeric_value * 2.0  # Bigger penalty

			"buff":
				var buff_name: String = effect.get("name", "")
				# Determine the buff target
				var buff_target: ChampionState = caster
				if not targets.is_empty():
					var target_id: String = str(targets[0])
					var potential_target := state.get_champion(target_id)
					if potential_target:
						buff_target = potential_target

				# If target already has this buff, don't cast it
				if buff_target.has_buff(buff_name):
					return 0.0  # Don't apply redundant buffs

				# For buffs on the caster that need attacking, use caster.
				# For friendly-targeted buffs, use buff_target.
				var attacker_for_buff: ChampionState = buff_target
				var can_attack := not attacker_for_buff.has_attacked or attacker_for_buff.has_buff("extraAttack")
				var has_targets := _can_attack_any_enemy_this_turn(state, attacker_for_buff)

				match buff_name:
					"extraAttack":
						var range_calc := RangeCalculator.new()
						var attack_targets := range_calc.get_valid_targets(attacker_for_buff, state)
						if not attack_targets.is_empty():
							score += 12.0
						elif _can_move_into_attack_range(state, attacker_for_buff):
							score += 10.0
						elif _can_attack_with_extended_movement(state, attacker_for_buff):
							score += 8.0  # Need extraMove first, but combo is viable
						else:
							score += 4.0
					"extraMove":
						# Extra move is especially valuable if it enables reaching enemies
						if has_targets:
							score += 4.0  # Already in range, minor repositioning value
						elif _can_attack_with_extended_movement(state, attacker_for_buff):
							score += 10.0  # Double move gets us into attack range!
						else:
							score += 6.0  # Repositioning value
					"leech":
						if can_attack and has_targets:
							score += 8.0  # Great if we can attack right after
						else:
							score += 2.0
					"refuel":
						if can_attack and has_targets:
							score += 7.0  # Draw on attack is strong
						else:
							score += 2.0
					"critical":
						if can_attack and has_targets:
							score += attacker_for_buff.current_power * 3.0  # 50% double damage
						else:
							score += 1.0
					"attackHeals", "attackheals":
						if can_attack:
							score += 6.0  # Healing through attack is strong
						else:
							score += 1.0
					"apesmash":
						if can_attack and has_targets:
							score += 6.0  # Push enemy on attack
						else:
							score += 1.0
					"elkrestoration", "elkRestoration":
						if can_attack and has_targets:
							score += 5.0  # Heal on attack
						else:
							score += 1.0
					"unlimitedMovement", "unlimitedmovement":
						if buff_target.has_moved:
							score += 1.0  # Already moved, most of the value is wasted
						else:
							score += 7.0  # Great for positioning
					"unlimitedRange", "unlimitedrange":
						if can_attack:
							score += 10.0  # Can attack anyone on the board
						else:
							score += 2.0
					"immune":
						score += 7.0  # Strong protection
					"shield":
						score += 5.0
					"stealth":
						score += 4.0
					"cheatDeath", "cheatdeath":
						# More valuable at low HP
						var hp_pct := float(buff_target.current_hp) / float(buff_target.max_hp)
						score += 4.0 + (1.0 - hp_pct) * 6.0  # 4-10 based on HP
					"untouchable":
						score += 5.0  # No damage this turn
					"freeRangerCard", "freerangercard":
						score += 6.0  # Free casts are strong
					_:
						score += 3.0

			"debuff":
				# Debuffs that disable are valuable
				var debuff_name: String = effect.get("name", "")
				if debuff_name in ["stunned", "canAttack", "canMove"]:
					score += 6.0
				else:
					score += 3.0

			"draw":
				var draw_count = effect.get("value", 1)
				if draw_count is int:
					score += draw_count * 2.0

			"move":
				# Movement effects (push, pull, etc.)
				score += 4.0

			"control":
				# Mind control (Betrayal) - use enemy champion to attack their ally
				# Value based on the controlled champion's power
				if not targets.is_empty():
					var controlled := state.get_champion(str(targets[0]))
					if controlled:
						score += controlled.current_power * 4.0 + 8.0  # Very strong effect

	# Prefer using mana efficiently - don't waste mana at end of turn
	if mana >= cost:
		# Bonus for using mana that would otherwise be wasted
		var leftover_mana := mana - cost
		if leftover_mana < 2:
			score += 2.0

	# Scale by cost for efficiency, but don't penalize too much
	if cost > 0:
		score = score * (1.0 + 1.0 / cost)

	# Buff-before-attack priority: if this card buffs power/range and the caster
	# hasn't attacked yet but CAN attack, give a big priority bonus so it happens first
	if not caster.has_attacked and _has_pre_attack_buff(effects):
		if _can_attack_any_enemy_this_turn(state, caster):
			score += 10.0  # Cast buffs before attacking!

	return score


func _score_place_response(action: Dictionary, state: GameState) -> float:
	"""Score placing a response card in the slot."""
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)

	if card_data.is_empty():
		return 0.0

	var score := 2.0  # Base value for having a response ready

	# Evaluate the response card's trigger and effects
	var trigger: String = card_data.get("trigger", "")
	var effects: Array = card_data.get("effect", [])

	# beforeDamage responses are very valuable (damage prevention)
	if trigger == "beforeDamage":
		score += 5.0
		# Check for damage prevention/reduction effects
		for effect: Dictionary in effects:
			var etype: String = effect.get("type", "")
			if etype == "buff" and effect.get("name", "") in ["immune", "shield", "damageReduction"]:
				score += 3.0

	# afterDamage responses can be valuable for retaliation
	elif trigger == "afterDamage":
		score += 3.0
		for effect: Dictionary in effects:
			var etype: String = effect.get("type", "")
			if etype == "damage":
				score += 4.0  # Counter-attack is valuable

	# onMove, onCast - situational but useful
	elif trigger in ["onMove", "onCast"]:
		score += 2.0

	# Prioritize placing responses when we have champions at low HP
	for champ: ChampionState in state.get_living_champions(player_id):
		var hp_percent := float(champ.current_hp) / float(champ.max_hp)
		if hp_percent < 0.4:
			score += 3.0  # Protect low HP champions
			break

	# Lower priority if we're winning comfortably
	var opp_id := 1 if player_id == 2 else 2
	var our_total_hp := 0
	var their_total_hp := 0
	for champ: ChampionState in state.get_living_champions(player_id):
		our_total_hp += champ.current_hp
	for champ: ChampionState in state.get_living_champions(opp_id):
		their_total_hp += champ.current_hp

	if our_total_hp > their_total_hp * 1.5:
		score -= 2.0  # Less urgent when winning

	return score


func _execute_action(action: Dictionary) -> Dictionary:
	"""Execute the chosen action through game controller."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			return game_controller.move_champion(
				action.get("champion", ""),
				action.get("target", Vector2i.ZERO)
			)
		"attack":
			return game_controller.attack_champion(
				action.get("champion", ""),
				action.get("target", "")
			)
		"cast":
			return game_controller.cast_card(
				action.get("card", ""),
				action.get("champion", ""),
				action.get("targets", [])
			)
		"place_response":
			var card_name: String = action.get("card", "")
			var state := game_controller.get_game_state()
			var success := state.set_response_slot(player_id, card_name)
			if success:
				print("AI Player %d placed '%s' in response slot" % [player_id, card_name])
			return {"success": success, "action": "place_response", "card": card_name}

	return {"success": false}


func handle_response_window(trigger: String, context: Dictionary) -> Dictionary:
	"""Decide whether to play a response card."""
	var state := game_controller.get_game_state()
	var valid_responses := game_controller.get_valid_responses(player_id)

	if valid_responses.is_empty():
		return {"action": "pass"}

	# Easy AI: Moderate chance to use responses
	if difficulty == Difficulty.EASY:
		if randf() < 0.5:  # 50% chance to respond (increased from 30%)
			var chosen: String = valid_responses[randi() % valid_responses.size()]
			return {"action": "respond", "card": chosen}
		return {"action": "pass"}

	# Medium/Hard: Evaluate response value
	var best_response := ""
	var best_score := 0.0

	for card_name: String in valid_responses:
		var score := _score_response(card_name, trigger, context, state)
		if score > best_score:
			best_score = score
			best_response = card_name

	# Threshold for playing response - lowered to encourage more response usage
	var threshold := 2.0 if difficulty == Difficulty.HARD else 3.0
	if best_score >= threshold:
		return {"action": "respond", "card": best_response}

	return {"action": "pass"}


func _score_response(card_name: String, trigger: String, context: Dictionary, state: GameState) -> float:
	"""Score a response card for the current trigger."""
	var score := 0.0
	var card_data := CardDatabase.get_card(card_name)
	var effects: Array = card_data.get("effect", [])

	# Base value from trigger type
	match trigger:
		"beforeDamage":
			# Value damage prevention highly - especially for high damage
			var incoming_damage: int = context.get("damage", 0)
			score += incoming_damage * 3.0  # Increased from 2.0

			# Extra value if our champion is low HP
			var target_id: String = context.get("target", "")
			var target := state.get_champion(target_id)
			if target and target.owner_id == player_id:
				var hp_ratio := float(target.current_hp) / float(target.max_hp)
				if hp_ratio < 0.3:
					score += 8.0  # High value to protect low HP champ
				elif hp_ratio < 0.5:
					score += 4.0

		"afterDamage":
			# Counter-attack responses are valuable
			score += 4.0

			# Extra value if we dealt damage (counterattack opportunity)
			var attacker_id: String = context.get("attacker", "")
			var attacker := state.get_champion(attacker_id)
			if attacker and attacker.owner_id != player_id:
				score += 3.0  # Enemy attacked us, good time to counter

		"onMove":
			# Movement traps and reactions
			score += 3.0

			# Extra value if enemy moved into range
			var mover_id: String = context.get("champion", "")
			var mover := state.get_champion(mover_id)
			if mover and mover.owner_id != player_id:
				score += 4.0  # Enemy moved, good time to trap

		"onCast":
			# Spell reactions (counterspells, etc.)
			score += 4.0

		"onHeal":
			# Healing disruption
			score += 3.0

		"onDraw":
			# Card draw triggers
			score += 2.0

		"startTurn", "endTurn":
			# Turn-based triggers
			score += 2.0

	# Add value based on card effects
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		match etype:
			"damage":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.5
			"heal":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.0
			"buff":
				var buff_name: String = effect.get("name", "")
				if buff_name in ["negateDamage", "negateSpell"]:
					score += 6.0  # Very valuable
				elif buff_name == "dodge":
					score += 5.0
				else:
					score += 2.0
			"move":
				score += 3.0  # Movement effects are tactical

	return score


func _delay(seconds: float) -> void:
	"""Helper for async delay."""
	# AIController is a RefCounted, so we need to get tree from Engine singleton
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout


func _manage_response_slot() -> void:
	"""Evaluate and place the best response card in the response slot."""
	var state := game_controller.get_game_state()
	var hand := state.get_hand(player_id)
	var current_slot := state.get_response_slot(player_id)

	# Find all response cards in hand
	var response_cards: Array[Dictionary] = []
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		if card_data.get("type", "") == "Response":
			response_cards.append({
				"name": card_name,
				"data": card_data,
				"score": _score_response_card_for_slot(card_name, card_data, state)
			})

	if response_cards.is_empty():
		# No response cards available - clear slot if we have one
		# (Keep existing card in slot since it's better than nothing)
		return

	# Sort by score
	response_cards.sort_custom(func(a, b): return a["score"] > b["score"])

	var best_card: Dictionary = response_cards[0]

	# If we already have a card in slot, only replace if new one is better
	if not current_slot.is_empty():
		var current_score := _score_response_card_for_slot(current_slot, CardDatabase.get_card(current_slot), state)
		if best_card["score"] <= current_score:
			# Keep current card
			return

	# Place the best response card in the slot
	var card_to_place: String = best_card["name"]
	if state.set_response_slot(player_id, card_to_place):
		print("AI: Placed '%s' in response slot (score: %.1f)" % [card_to_place, best_card["score"]])


func _score_response_card_for_slot(card_name: String, card_data: Dictionary, state: GameState) -> float:
	"""Score a response card for slot placement."""
	var score := 0.0
	var trigger: String = card_data.get("trigger", "")
	var cost: int = card_data.get("cost", 0)
	var effects: Array = card_data.get("effect", [])
	var reasoning_parts: Array = []  # For developer mode

	# Base score by trigger type
	match trigger:
		"beforeDamage":
			# Defensive cards are valuable
			score += 5.0
		"afterDamage":
			# Reactive damage/effects
			score += 4.0
		"onMove":
			# Traps and movement reactions
			score += 3.0
		"onHeal":
			# Usually disruption
			score += 3.0
		"onCast":
			# Spell reactions
			score += 3.0
		_:
			score += 2.0

	# Evaluate effects
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")
		match effect_type:
			"damage":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.5
			"heal":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.0
			"move":
				# Movement effects (dodge, etc.) are valuable
				score += 3.0
			"buff":
				var buff_name: String = effect.get("name", "")
				if buff_name in ["negateDamage", "negateSpell"]:
					score += 8.0  # Damage/spell negation is very valuable
				elif buff_name == "shield":
					score += 6.0
				else:
					score += 2.0
			"statMod":
				score += 2.0

	# Penalize high-cost cards (harder to trigger)
	if cost > 3:
		score -= (cost - 3) * 1.0

	# Penalize cards with random chance conditions (unreliable for response slot)
	# Example: "Now You See Me" has condition.chance = 0.5 (50% to work)
	var condition: Dictionary = card_data.get("condition", {})
	if condition.has("chance"):
		var chance_value: float = condition.get("chance", 1.0)
		# Heavily penalize unreliable cards - multiply score by chance
		# A 50% card is worth half as much in the response slot
		score *= chance_value
		# Additional penalty for very unreliable cards
		if chance_value < 0.5:
			score -= 3.0

	# Bonus for character-specific cards if that character is alive and healthy
	var card_character: String = card_data.get("character", "")
	if not card_character.is_empty():
		for champ: ChampionState in state.get_champions(player_id):
			if champ.champion_name == card_character:
				if champ.is_alive():
					# Bonus if the character is low health (needs protection)
					var hp_ratio := float(champ.current_hp) / float(champ.max_hp)
					if hp_ratio < 0.5:
						score += 3.0
				else:
					# Character is dead - card is useless
					score = -10.0
				break

	return score


# ===== DEVELOPER MODE REASONING =====

func get_last_reasoning() -> Dictionary:
	"""Get the reasoning breakdown for the last chosen action."""
	return last_reasoning


func get_last_scored_actions() -> Array:
	"""Get all scored actions from the last decision, sorted by score."""
	return last_scored_actions


func describe_action(action: Dictionary) -> String:
	"""Convert an action dictionary to a human-readable description."""
	var action_type: String = action.get("type", "unknown")
	var state := game_controller.get_game_state()

	match action_type:
		"move":
			var champ := state.get_champion(action.get("champion", ""))
			var champ_name: String = champ.champion_name if champ else "Unknown"
			var target: Vector2i = action.get("target", Vector2i.ZERO)
			return "Move %s to (%d, %d)" % [champ_name, target.x, target.y]
		"attack":
			var champ := state.get_champion(action.get("champion", ""))
			var target := state.get_champion(action.get("target", ""))
			var champ_name: String = champ.champion_name if champ else "Unknown"
			var target_name: String = target.champion_name if target else "Unknown"
			var target_hp: String = "%d/%d HP" % [target.current_hp, target.max_hp] if target else ""
			return "Attack %s → %s (%s)" % [champ_name, target_name, target_hp]
		"cast":
			var champ := state.get_champion(action.get("champion", ""))
			var champ_name: String = champ.champion_name if champ else "Unknown"
			var card_name: String = action.get("card", "Unknown")
			var targets: Array = action.get("targets", [])
			var target_str := ""
			if not targets.is_empty():
				var first_target = targets[0]
				if first_target is String:
					var target_champ := state.get_champion(first_target)
					if target_champ:
						target_str = " on %s" % target_champ.champion_name
					else:
						target_str = " at %s" % first_target
			return "%s casts '%s'%s" % [champ_name, card_name, target_str]
		"end_turn":
			return "End Turn"
		"place_response":
			var card_name: String = action.get("card", "Unknown")
			var card_data := CardDatabase.get_card(card_name)
			var trigger: String = card_data.get("trigger", "")
			return "Place '%s' in response slot (triggers on %s)" % [card_name, trigger]
		_:
			return "Unknown action: %s" % action_type


func build_reasoning_for_action(action: Dictionary, score: float, state: GameState) -> Dictionary:
	"""Build a detailed reasoning breakdown for an action."""
	var reasoning := {
		"action": action,
		"action_description": describe_action(action),
		"total_score": score,
		"breakdown": [],
		"champion": "",
		"type": action.get("type", "unknown")
	}

	var champ := state.get_champion(action.get("champion", ""))
	if champ:
		reasoning["champion"] = champ.champion_name

	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			reasoning["breakdown"] = _build_move_reasoning(action, state)
		"attack":
			reasoning["breakdown"] = _build_attack_reasoning(action, state)
		"cast":
			reasoning["breakdown"] = _build_cast_reasoning(action, state)
		"place_response":
			reasoning["breakdown"] = _build_place_response_reasoning(action, state)

	return reasoning


func _build_move_reasoning(action: Dictionary, state: GameState) -> Array:
	"""Build reasoning breakdown for a move action."""
	var parts: Array = []
	var champion := state.get_champion(action.get("champion", ""))
	var target_pos: Vector2i = action.get("target", Vector2i.ZERO)

	if champion == null:
		return parts

	parts.append({"factor": "Base move value", "value": 2.0})

	var opp_id := 1 if player_id == 2 else 2
	var range_calc := RangeCalculator.new()
	var current_targets := range_calc.get_valid_targets(champion, state)
	var can_currently_attack := not current_targets.is_empty()

	# Check if moving into attack range
	for enemy: ChampionState in state.get_living_champions(opp_id):
		var target_dist := _chebyshev_distance(target_pos, enemy.position)
		var is_melee: bool = champion.current_range <= 1
		var will_be_in_range := false

		if is_melee:
			will_be_in_range = target_dist <= champion.current_range
		else:
			var dx: int = enemy.position.x - target_pos.x
			var dy: int = enemy.position.y - target_pos.y
			var is_cardinal: bool = (dx == 0 and dy != 0) or (dy == 0 and dx != 0)
			var dist: int = absi(dx) + absi(dy)
			will_be_in_range = is_cardinal and dist <= champion.current_range

		if not can_currently_attack and will_be_in_range:
			parts.append({"factor": "Moving into attack range", "value": 15.0})
			if enemy.current_hp <= champion.current_power:
				parts.append({"factor": "Can kill after moving", "value": 10.0})
			break

	if can_currently_attack:
		parts.append({"factor": "Already in range (should attack)", "value": -5.0})

	return parts


func _build_attack_reasoning(action: Dictionary, state: GameState) -> Array:
	"""Build reasoning breakdown for an attack action."""
	var parts: Array = []
	var attacker := state.get_champion(action.get("champion", ""))
	var target := state.get_champion(action.get("target", ""))

	if attacker == null or target == null:
		return parts

	parts.append({"factor": "Base attack value", "value": 15.0})

	# Kill potential
	if target.current_hp <= attacker.current_power:
		parts.append({"factor": "KILL POTENTIAL!", "value": 25.0})

	# Low HP bonus
	var hp_ratio := float(target.current_hp) / float(target.max_hp)
	var low_hp_bonus := (1.0 - hp_ratio) * 8.0
	if low_hp_bonus > 0.5:
		parts.append({"factor": "Low HP target (%d%%)" % int(hp_ratio * 100), "value": low_hp_bonus})

	# High threat target
	if target.current_power >= 2:
		parts.append({"factor": "High threat target (power %d)" % target.current_power, "value": 3.0})

	# Attacker power bonus
	var power_bonus := attacker.current_power * 2.0
	parts.append({"factor": "Attacker power bonus", "value": power_bonus})

	return parts


func _build_cast_reasoning(action: Dictionary, state: GameState) -> Array:
	"""Build reasoning breakdown for a cast action."""
	var parts: Array = []
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)
	var caster := state.get_champion(action.get("champion", ""))

	if card_data.is_empty() or caster == null:
		return parts

	parts.append({"factor": "Base cast value", "value": 3.0})

	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")
		match effect_type:
			"damage":
				var damage = effect.get("value", 0)
				var actual_damage := _calculate_card_damage(damage, caster)
				if actual_damage > 0:
					parts.append({"factor": "Damage effect (%d dmg)" % actual_damage, "value": actual_damage * 3.0})
			"heal":
				var heal = effect.get("value", 0)
				if heal is int and heal > 0:
					parts.append({"factor": "Heal effect (%d HP)" % heal, "value": heal * 1.5})
			"buff":
				var buff_name: String = effect.get("name", "")
				if buff_name == "extraAttack":
					parts.append({"factor": "Extra Attack buff", "value": 12.0})
				else:
					parts.append({"factor": "Buff: %s" % buff_name, "value": 3.0})
			"debuff":
				var debuff_name: String = effect.get("name", "")
				parts.append({"factor": "Debuff: %s" % debuff_name, "value": 6.0})
			"draw":
				var draw_count = effect.get("value", 1)
				if draw_count is int:
					parts.append({"factor": "Draw %d cards" % draw_count, "value": draw_count * 2.0})

	var cost: int = card_data.get("cost", 0)
	if cost > 0:
		parts.append({"factor": "Mana efficiency (cost %d)" % cost, "value": 1.0 / cost})

	return parts


func _build_place_response_reasoning(action: Dictionary, state: GameState) -> Array:
	"""Build reasoning breakdown for placing a response card in the slot."""
	var parts: Array = []
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)

	if card_data.is_empty():
		return parts

	parts.append({"factor": "Base response slot value", "value": 2.0})

	var trigger: String = card_data.get("trigger", "")
	match trigger:
		"beforeDamage":
			parts.append({"factor": "Damage prevention trigger", "value": 5.0})
		"afterDamage":
			parts.append({"factor": "Counter-attack trigger", "value": 3.0})
		"onMove", "onCast":
			parts.append({"factor": "Situational trigger", "value": 2.0})

	# Check for valuable effects
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		var buff_name: String = effect.get("name", "")
		if etype == "buff" and buff_name in ["negateDamage", "negateSpell", "immune", "shield", "dodge"]:
			parts.append({"factor": "Defensive buff (%s)" % buff_name, "value": 3.0})
		elif etype == "damage":
			var value = effect.get("value", 0)
			if value is int:
				parts.append({"factor": "Counter damage (%d)" % value, "value": value * 1.5})

	# Low HP protection bonus
	var opp_id := 1 if player_id == 2 else 2
	for champ: ChampionState in state.get_living_champions(player_id):
		var hp_percent := float(champ.current_hp) / float(champ.max_hp)
		if hp_percent < 0.4:
			parts.append({"factor": "Protect low HP champion", "value": 3.0})
			break

	return parts


func evaluate_and_capture_actions(state: GameState) -> Array:
	"""Evaluate all actions and capture reasoning for developer mode."""
	var valid_actions := _get_all_valid_actions(state)
	var scored_actions: Array = []

	for action: Dictionary in valid_actions:
		var score := _score_action(action, state)

		# Skip zero or negative scores
		if score <= 0:
			continue

		# Apply randomization based on difficulty
		var randomization: float = profile.get("score_randomization", 0.0)
		var randomized_score := score * randf_range(1.0 - randomization, 1.0 + randomization)

		var entry := {
			"action": action,
			"base_score": score,
			"randomized_score": randomized_score,
			"reasoning": build_reasoning_for_action(action, score, state) if capture_reasoning else {}
		}
		scored_actions.append(entry)

	# Sort by randomized score
	scored_actions.sort_custom(func(a, b): return a["randomized_score"] > b["randomized_score"])

	# Store for developer mode access
	if capture_reasoning:
		last_scored_actions = scored_actions

	return scored_actions


func evaluate_intel_choice(own_card_name: String, opp_card_name: String) -> Dictionary:
	"""Evaluate Intel card — decide whether to keep each card on top or put on bottom.
	Returns {own_to_bottom: bool, opp_to_bottom: bool}."""
	var state := game_controller.get_game_state()
	var own_to_bottom := false
	var opp_to_bottom := false

	# Score own card — high score = keep on top (we want to draw it)
	if not own_card_name.is_empty():
		var own_score := _score_intel_card(own_card_name, player_id, state)
		own_to_bottom = own_score < 5
		print("Intel AI: Own card '%s' score=%d -> %s" % [own_card_name, own_score, "bottom" if own_to_bottom else "keep"])

	# Score opponent card — high score = put on bottom (deny them a good card)
	if not opp_card_name.is_empty():
		var opp_id := 2 if player_id == 1 else 1
		var opp_score := _score_intel_card(opp_card_name, opp_id, state)
		opp_to_bottom = opp_score >= 5
		print("Intel AI: Opp card '%s' score=%d -> %s" % [opp_card_name, opp_score, "bottom" if opp_to_bottom else "keep"])

	return {"own_to_bottom": own_to_bottom, "opp_to_bottom": opp_to_bottom}


func _score_intel_card(card_name: String, owner_id: int, state: GameState) -> int:
	"""Score a card's usefulness for a given player (0-10). Higher = more useful."""
	var card_data: Dictionary = CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return 5  # Unknown card, neutral

	var cost: int = card_data.get("cost", 0)
	var card_type: String = str(card_data.get("type", "")).to_lower()
	var effects: Array = card_data.get("effect", [])
	var opp_id := 2 if owner_id == 1 else 1
	var score := 5  # Baseline

	# Check team status
	var friendlies := state.get_living_champions(owner_id)
	var enemies := state.get_living_champions(opp_id)
	var any_low_hp := false
	var all_full_hp := true
	for champ: ChampionState in friendlies:
		if champ.current_hp < champ.max_hp:
			all_full_hp = false
		if champ.current_hp <= champ.max_hp * 0.5:
			any_low_hp = true

	# Evaluate based on effects
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		match etype:
			"damage":
				if not enemies.is_empty():
					score = maxi(score, 7)
				else:
					score = mini(score, 2)
			"heal":
				if any_low_hp:
					score = maxi(score, 8)
				elif all_full_hp:
					score = mini(score, 2)
				else:
					score = maxi(score, 5)
			"buff":
				score = maxi(score, 6)
			"statmod":
				var val = effect.get("value", 0)
				if val is int and val > 0:
					score = maxi(score, 6)
			"draw":
				score = maxi(score, 6)
			"debuff":
				if not enemies.is_empty():
					score = maxi(score, 6)

	# Response cards are always potentially useful
	if card_type == "response":
		score = maxi(score, 6)

	# Equipment is moderately useful
	if card_type == "equipment":
		score = maxi(score, 5)

	# High cost penalty — harder to cast
	if cost >= 4:
		score -= 2
	elif cost >= 3:
		score -= 1

	# Low cost bonus — easy to play
	if cost <= 1:
		score += 1

	return clampi(score, 0, 10)


func handle_mind_control(champion_id: String, state: GameState) -> void:
	"""AI controls an enemy champion via mind control (Betrayal).
	Moves the controlled champion toward its ally, then attacks the ally."""
	var champion := state.get_champion(champion_id)
	if champion == null or not champion.is_alive():
		return

	var range_calc := RangeCalculator.new()

	# Find allies of the controlled champion (these are our attack targets)
	var ally_targets: Array[ChampionState] = []
	for ally: ChampionState in state.get_living_champions(champion.owner_id):
		if ally.unique_id != champion.unique_id:
			ally_targets.append(ally)

	if ally_targets.is_empty():
		print("AI Mind Control: No allies to attack")
		return

	# Check if already in range of an ally
	var in_range_target: ChampionState = null
	for ally: ChampionState in ally_targets:
		if range_calc.can_attack(champion, ally, state):
			in_range_target = ally
			break

	# If not in range, try to move closer
	if in_range_target == null and champion.can_move():
		var pathfinder := Pathfinder.new(state)
		var reachable := pathfinder.get_reachable_tiles(champion)
		var best_tile := Vector2i(-1, -1)
		var best_score := -999.0

		for tile: Vector2i in reachable:
			# Check if we'd be in attack range from this tile
			var original_pos := champion.position
			champion.position = tile
			for ally: ChampionState in ally_targets:
				if range_calc.can_attack(champion, ally, state):
					# Prefer tiles that put us in range, closer to low-HP allies
					var score := 100.0 - ally.current_hp  # Prefer attacking low HP
					if score > best_score:
						best_score = score
						best_tile = tile
						in_range_target = ally
			champion.position = original_pos

			# If no in-range tile found, pick closest to any ally
			if best_score < 0:
				for ally: ChampionState in ally_targets:
					var dist := _chebyshev_distance(tile, ally.position)
					var score := -float(dist)
					if score > best_score:
						best_score = score
						best_tile = tile

		# Execute move
		if best_tile != Vector2i(-1, -1) and best_tile != champion.position:
			var old_pos := champion.position
			champion.position = best_tile
			champion.has_moved = true
			print("AI Mind Control: Moved %s from %s to %s" % [champion.champion_name, old_pos, best_tile])

	# Re-check for in-range targets after moving
	if in_range_target == null:
		for ally: ChampionState in ally_targets:
			if range_calc.can_attack(champion, ally, state):
				in_range_target = ally
				break

	# Attack if in range
	if in_range_target != null:
		var damage: int = champion.current_power
		var actual_damage: int = in_range_target.take_damage(damage)
		champion.has_attacked = true
		print("AI Mind Control: %s attacks %s for %d damage (%d HP remaining)" % [
			champion.champion_name, in_range_target.champion_name, actual_damage, in_range_target.current_hp])
	else:
		print("AI Mind Control: Could not reach any ally to attack")
