class_name GameController
extends RefCounted
## GameController - Main game logic coordinator
## Integrates all game systems and provides unified interface

signal game_started(player1_champions: Array, player2_champions: Array)
signal game_ended(winner: int, reason: String)
signal turn_started(player_id: int, round_number: int)
signal turn_ended(player_id: int)
signal action_performed(action: Dictionary)
signal response_window_opened(trigger: String, context: Dictionary)
signal response_window_closed()
signal champion_died(champion_id: String)

# Core systems
var game_state: GameState
var turn_manager: TurnManager
var action_system: ActionSystem
var effect_processor: EffectProcessor
var response_stack: ResponseStack
var equipment_system: EquipmentSystem
var custom_effects: CustomEffects

# State flags
var is_initialized: bool = false
var is_game_active: bool = false

# Pending action awaiting response resolution
var _pending_action: Dictionary = {}
var _pending_action_type: String = ""


func initialize(p1_champions: Array[String], p2_champions: Array[String]) -> bool:
	"""Initialize a new game with selected champions."""
	if p1_champions.size() != 2 or p2_champions.size() != 2:
		push_error("GameController: Each player must have exactly 2 champions")
		return false

	# Create game state
	game_state = GameState.create_new_game(p1_champions, p2_champions)

	# Initialize systems
	turn_manager = TurnManager.new(game_state)
	action_system = ActionSystem.new()
	effect_processor = EffectProcessor.new(game_state)
	response_stack = ResponseStack.new(game_state)
	equipment_system = EquipmentSystem.new(game_state)
	custom_effects = CustomEffects.new(game_state)

	# Connect signals
	_connect_signals()

	is_initialized = true
	return true


func _connect_signals() -> void:
	"""Connect internal system signals."""
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.phase_changed.connect(_on_phase_changed)

	response_stack.response_window_opened.connect(_on_response_window_opened)
	response_stack.response_window_closed.connect(_on_response_window_closed)
	response_stack.stack_resolved.connect(_on_response_stack_resolved)


func start_game() -> void:
	"""Begin the game."""
	if not is_initialized:
		push_error("GameController: Not initialized")
		return

	is_game_active = true
	game_started.emit(
		_get_champion_names(1),
		_get_champion_names(2)
	)

	# Start first turn
	turn_manager.start_game()


# === Player Actions ===

func move_champion(champion_id: String, target_pos: Vector2i) -> Dictionary:
	"""Attempt to move a champion."""
	if not _can_act():
		return {"success": false, "error": "Cannot act now"}

	var champion := game_state.get_champion(champion_id)
	if not _validate_champion_action(champion):
		return {"success": false, "error": "Invalid champion or not your turn"}

	var action := ActionSystem.MoveAction.new(champion_id, target_pos)

	if not action.is_valid(game_state):
		return {"success": false, "error": "Invalid move"}

	if action_system.execute_action(action, game_state):
		var result := {
			"success": true,
			"action": "move",
			"champion": champion_id,
			"from": action.from_position,
			"to": target_pos,
			"path": action.path
		}

		action_performed.emit(result)

		# Check for onMove responses
		_check_trigger("onMove", {
			"champion": champion_id,
			"from": action.from_position,
			"to": target_pos
		})

		return result

	return {"success": false, "error": "Move failed"}


func attack_champion(attacker_id: String, target_id: String) -> Dictionary:
	"""Attempt to attack an enemy champion."""
	if not _can_act():
		return {"success": false, "error": "Cannot act now"}

	var attacker := game_state.get_champion(attacker_id)
	if not _validate_champion_action(attacker):
		return {"success": false, "error": "Invalid attacker or not your turn"}

	var action := ActionSystem.AttackAction.new(attacker_id, target_id)

	if not action.is_valid(game_state):
		return {"success": false, "error": "Invalid attack"}

	# Check for beforeDamage responses
	var target := game_state.get_champion(target_id)
	var damage: int = attacker.current_power

	# Apply damage modifiers from buffs
	damage = BuffRegistry.calculate_damage_modifier(target, damage, true)

	if _check_trigger("beforeDamage", {
		"attacker": attacker_id,
		"target": target_id,
		"damage": damage
	}):
		# Response window opened - store pending attack for after resolution
		_pending_action_type = "attack"
		_pending_action = {
			"attacker_id": attacker_id,
			"target_id": target_id,
			"action": action
		}
		return {"success": true, "pending": true, "awaiting_response": true}

	# Execute attack immediately (no responses)
	return _execute_attack(action)


func _execute_attack(action: ActionSystem.AttackAction) -> Dictionary:
	"""Execute attack after response window."""
	if action_system.execute_action(action, game_state):
		var result := {
			"success": true,
			"action": "attack",
			"attacker": action.attacker_id,
			"target": action.target_id,
			"damage": action.damage_dealt
		}

		action_performed.emit(result)

		# Check for afterDamage responses
		_check_trigger("afterDamage", {
			"attacker": action.attacker_id,
			"target": action.target_id,
			"damage": action.damage_dealt
		})

		# Check if target died
		var target := game_state.get_champion(action.target_id)
		if target and target.is_dead():
			# Check cheat death
			if not BuffRegistry.check_cheat_death(target):
				champion_died.emit(action.target_id)
				_check_win_condition()

		return result

	return {"success": false, "error": "Attack failed"}


func cast_card(card_name: String, caster_id: String, targets: Array = []) -> Dictionary:
	"""Attempt to cast a card."""
	if not _can_act():
		return {"success": false, "error": "Cannot act now"}

	var caster := game_state.get_champion(caster_id)
	if not _validate_champion_action(caster):
		return {"success": false, "error": "Invalid caster or not your turn"}

	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return {"success": false, "error": "Card not found"}

	var card_type: String = card_data.get("type", "")

	# Handle equipment cards specially
	if card_type == "Equipment":
		return _cast_equipment(card_name, caster, targets)

	# Create and validate action
	var action := ActionSystem.CastCardAction.new(card_name, caster_id, targets)

	if not action.is_valid(game_state):
		return {"success": false, "error": "Cannot cast card"}

	# Check for onCast responses
	if _check_trigger("onCast", {
		"caster": caster_id,
		"card": card_name,
		"targets": targets
	}):
		return {"success": true, "pending": true, "awaiting_response": true}

	return _execute_cast(action, targets)


func _execute_cast(action: ActionSystem.CastCardAction, targets: Array) -> Dictionary:
	"""Execute card cast after response window."""
	if action_system.execute_action(action, game_state):
		var caster := game_state.get_champion(action.caster_id)

		# Process card effects
		var effect_result := effect_processor.process_card(
			action.card_name,
			caster,
			targets
		)

		var result := {
			"success": true,
			"action": "cast",
			"card": action.card_name,
			"caster": action.caster_id,
			"targets": targets,
			"effects": effect_result
		}

		action_performed.emit(result)

		# Check for deaths
		for champ: ChampionState in game_state.get_all_champions():
			if champ.is_dead() and not BuffRegistry.check_cheat_death(champ):
				champion_died.emit(champ.unique_id)

		_check_win_condition()

		return result

	return {"success": false, "error": "Cast failed"}


func _cast_equipment(card_name: String, caster: ChampionState, targets: Array) -> Dictionary:
	"""Handle equipping an equipment card."""
	var cost: int = CardDatabase.get_card(card_name).get("cost", 0)

	if game_state.get_mana(caster.owner_id) < cost:
		return {"success": false, "error": "Not enough mana"}

	# Spend mana and remove from hand
	game_state.spend_mana(caster.owner_id, cost)
	game_state.play_card(caster.owner_id, card_name)

	# Equip
	var result := equipment_system.process_equipment_card(card_name, caster, targets)
	if result.get("success", false):
		action_performed.emit({
			"action": "equip",
			"card": card_name,
			"champion": result.get("equipped_to", ""),
			"charges": result.get("charges", 0)
		})

	return result


func use_equipment(champion_id: String, card_name: String, targets: Array = []) -> Dictionary:
	"""Use a charge from equipped item."""
	var champion := game_state.get_champion(champion_id)
	if champion == null:
		return {"success": false, "error": "Champion not found"}

	return equipment_system.use_equipment(champion, card_name, targets)


func end_turn() -> Dictionary:
	"""End the current player's turn."""
	print("GameController.end_turn() called, is_game_active=%s, response_stack.is_open=%s" % [is_game_active, response_stack.is_open()])
	if not is_game_active:
		return {"success": false, "error": "Game not active"}

	# Check for endTurn responses
	if _check_trigger("endTurn", {"player": game_state.active_player}):
		print("  endTurn trigger opened response window")
		return {"success": true, "pending": true, "awaiting_response": true}

	print("  Calling turn_manager.end_turn()")
	turn_manager.end_turn()
	return {"success": true}


# === Response Actions ===

func play_response(player_id: int, card_name: String, caster_id: String, targets: Array = []) -> Dictionary:
	"""Play a response card during response window."""
	if not response_stack.is_open():
		return {"success": false, "error": "No response window open"}

	if response_stack.add_response(player_id, card_name, caster_id, targets):
		return {"success": true, "card": card_name}

	return {"success": false, "error": "Invalid response"}


func pass_response() -> Dictionary:
	"""Pass priority during response window."""
	if not response_stack.is_open():
		return {"success": false, "error": "No response window open"}

	var should_resolve := response_stack.pass_priority()

	if should_resolve:
		var results := response_stack.resolve()
		return {"success": true, "resolved": true, "results": results}

	return {"success": true, "resolved": false}


func get_valid_responses(player_id: int) -> Array[String]:
	"""Get valid response cards for current window."""
	return response_stack.get_valid_responses(player_id)


# === Queries ===

func get_valid_moves(champion_id: String) -> Array[Vector2i]:
	"""Get valid move destinations for a champion."""
	var champion := game_state.get_champion(champion_id)
	if champion == null or not champion.can_move():
		return []

	var pathfinder := Pathfinder.new(game_state)
	return pathfinder.get_reachable_tiles(champion)


func get_valid_attack_targets(champion_id: String) -> Array[String]:
	"""Get valid attack targets for a champion."""
	var champion := game_state.get_champion(champion_id)
	if champion == null or not champion.can_attack():
		return []

	var range_calc := RangeCalculator.new()
	var targets: Array[String] = []

	for target: ChampionState in range_calc.get_valid_targets(champion, game_state):
		targets.append(target.unique_id)

	return targets


func get_playable_cards(player_id: int) -> Array[String]:
	"""Get cards that can be played from hand."""
	var playable: Array[String] = []
	var hand := game_state.get_hand(player_id)
	var mana := game_state.get_mana(player_id)

	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		var cost: int = card_data.get("cost", 0)
		var card_type: String = card_data.get("type", "")

		# Response cards can't be played normally
		if card_type == "Response":
			continue

		if cost <= mana:
			playable.append(card_name)

	return playable


func get_all_valid_actions(player_id: int) -> Array:
	"""Get all valid actions for AI evaluation."""
	return action_system.get_valid_actions(game_state, player_id)


func get_game_state() -> GameState:
	"""Get current game state (for AI or UI)."""
	return game_state


func get_state_copy() -> GameState:
	"""Get a copy of game state for simulation."""
	return game_state.duplicate()


# === Internal Helpers ===

func _can_act() -> bool:
	"""Check if actions are allowed."""
	return is_game_active and not response_stack.is_open() and turn_manager.can_perform_action()


func _validate_champion_action(champion: ChampionState) -> bool:
	"""Validate champion can act."""
	if champion == null:
		return false
	if champion.owner_id != game_state.active_player:
		return false
	if not champion.is_alive():
		return false
	return true


func _check_trigger(trigger: String, context: Dictionary) -> bool:
	"""Check and open response window if applicable."""
	return response_stack.open_window(trigger, context, game_state.active_player)


func _check_win_condition() -> void:
	"""Check if game has ended."""
	game_state.check_win_condition()
	if game_state.game_over:
		is_game_active = false
		var reason := "All enemy champions defeated"
		game_ended.emit(game_state.winner, reason)


func _get_champion_names(player_id: int) -> Array:
	"""Get champion names for a player."""
	var names: Array = []
	for champ: ChampionState in game_state.get_champions(player_id):
		names.append(champ.champion_name)
	return names


# === Signal Handlers ===

func _on_turn_started(player_id: int, round_number: int) -> void:
	# Check for startTurn responses
	_check_trigger("startTurn", {"player": player_id, "round": round_number})
	turn_started.emit(player_id, round_number)


func _on_turn_ended(player_id: int) -> void:
	turn_ended.emit(player_id)


func _on_phase_changed(phase: String) -> void:
	# Phase change handling
	pass


func _on_response_window_opened(trigger: String, context: Dictionary) -> void:
	response_window_opened.emit(trigger, context)


func _on_response_window_closed() -> void:
	response_window_closed.emit()


func _on_response_stack_resolved() -> void:
	"""Handle pending action after response stack resolves."""
	if _pending_action_type.is_empty():
		return

	match _pending_action_type:
		"attack":
			_resolve_pending_attack()
		"cast":
			_resolve_pending_cast()

	# Clear pending action
	_pending_action_type = ""
	_pending_action = {}


func _resolve_pending_attack() -> void:
	"""Resolve a pending attack after responses."""
	var attacker_id: String = _pending_action.get("attacker_id", "")
	var target_id: String = _pending_action.get("target_id", "")
	var action = _pending_action.get("action")

	if attacker_id.is_empty() or target_id.is_empty() or action == null:
		return

	var attacker := game_state.get_champion(attacker_id)
	var target := game_state.get_champion(target_id)

	if attacker == null or target == null:
		return

	# Check for attack redirection (Bear Tank)
	if target.has_buff("redirectAttack"):
		var redirect_to_id: String = target.buffs["redirectAttack"].get("source", "")
		var new_target := game_state.get_champion(redirect_to_id)
		if new_target and new_target.is_alive():
			print("Attack redirected from %s to %s (Bear Tank)" % [target.champion_name, new_target.champion_name])
			target.remove_buff("redirectAttack")
			# Update target and action
			target = new_target
			target_id = redirect_to_id
			action.target_id = redirect_to_id
		else:
			target.remove_buff("redirectAttack")

	# Re-validate the attack after responses resolved
	# Target may have moved, died, or gained immunity
	var range_calc := RangeCalculator.new()

	# Check if target is still alive
	if not target.is_alive():
		print("Attack resolved: Target died during response window")
		# Attack consumed but no effect
		attacker.has_attacked = true
		action_performed.emit({
			"success": true,
			"action": "attack",
			"attacker": attacker_id,
			"target": target_id,
			"damage": 0,
			"result": "target_dead"
		})
		return

	# Check if target is still in range (skip for redirected attacks since Beast moved adjacent)
	if not range_calc.can_attack(attacker, target, game_state):
		print("Attack resolved: Target moved out of range - MISS!")
		# Attack consumed but misses
		attacker.has_attacked = true
		action_performed.emit({
			"success": true,
			"action": "attack",
			"attacker": attacker_id,
			"target": target_id,
			"damage": 0,
			"result": "miss"
		})
		return

	# Check for damage immunity/negation buffs applied by responses
	if target.has_buff("negateDamage"):
		print("Attack resolved: Damage negated by buff")
		target.remove_buff("negateDamage")
		attacker.has_attacked = true
		action_performed.emit({
			"success": true,
			"action": "attack",
			"attacker": attacker_id,
			"target": target_id,
			"damage": 0,
			"result": "negated"
		})
		return

	# Attack still valid - execute it
	print("Attack resolved: Executing attack")
	_execute_attack(action)


func _resolve_pending_cast() -> void:
	"""Resolve a pending spell cast after responses."""
	# Similar logic for spells - target may have moved, spell may be redirected, etc.
	var card_name: String = _pending_action.get("card_name", "")
	var caster_id: String = _pending_action.get("caster_id", "")
	var targets: Array = _pending_action.get("targets", [])

	if card_name.is_empty() or caster_id.is_empty():
		return

	# For now, just execute the spell
	# TODO: Add spell-specific response handling (redirect, etc.)
	var caster := game_state.get_champion(caster_id)
	if caster == null or not caster.is_alive():
		return

	effect_processor.process_card(card_name, caster, targets)


# === Undo Support ===

func undo_last_action() -> bool:
	"""Undo the last action (for local play)."""
	return action_system.undo_last_action(game_state)


func redo_action() -> bool:
	"""Redo previously undone action."""
	return action_system.redo_action(game_state)
