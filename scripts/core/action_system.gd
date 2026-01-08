class_name ActionSystem
extends RefCounted
## ActionSystem - Command pattern implementation for game actions
## Supports execute, undo, and validation

# Action types
enum ActionType {
	MOVE,
	ATTACK,
	CAST_CARD,
	END_TURN,
	PASS_RESPONSE
}


# Base action class
class Action:
	var action_type: ActionType
	var player_id: int
	var executed: bool = false
	var undo_data: Dictionary = {}

	func is_valid(_state: GameState) -> bool:
		return false

	func execute(_state: GameState) -> bool:
		return false

	func undo(_state: GameState) -> bool:
		return false

	func get_description() -> String:
		return "Unknown Action"


# Move Action
class MoveAction extends Action:
	var champion_id: String
	var from_position: Vector2i
	var to_position: Vector2i
	var path: Array[Vector2i] = []

	func _init(champ_id: String, target_pos: Vector2i):
		action_type = ActionType.MOVE
		champion_id = champ_id
		to_position = target_pos

	func is_valid(state: GameState) -> bool:
		var champion := state.get_champion(champion_id)
		if not champion:
			return false
		if champion.owner_id != state.active_player:
			return false
		if not champion.can_move():
			return false

		# Calculate path and check if reachable
		var pathfinder := Pathfinder.new(state)
		path = pathfinder.find_path(champion.position, to_position, champion)
		return path.size() > 0 and path.size() <= champion.movement_remaining

	func execute(state: GameState) -> bool:
		var champion := state.get_champion(champion_id)
		if not champion:
			return false

		# Store undo data
		undo_data = {
			"from_position": champion.position,
			"movement_remaining": champion.movement_remaining,
			"has_moved": champion.has_moved
		}

		from_position = champion.position

		# Move champion
		champion.position = to_position
		champion.movement_remaining -= path.size()
		champion.has_moved = true
		executed = true

		return true

	func undo(state: GameState) -> bool:
		if not executed:
			return false

		var champion := state.get_champion(champion_id)
		if not champion:
			return false

		champion.position = undo_data.get("from_position", Vector2i.ZERO)
		champion.movement_remaining = undo_data.get("movement_remaining", 0)
		champion.has_moved = undo_data.get("has_moved", false)
		executed = false

		return true

	func get_description() -> String:
		return "Move %s to %s" % [champion_id, to_position]


# Attack Action
class AttackAction extends Action:
	var attacker_id: String
	var target_id: String
	var damage_dealt: int = 0

	func _init(atk_id: String, tgt_id: String):
		action_type = ActionType.ATTACK
		attacker_id = atk_id
		target_id = tgt_id

	func is_valid(state: GameState) -> bool:
		var attacker := state.get_champion(attacker_id)
		var target := state.get_champion(target_id)

		if not attacker or not target:
			return false
		if attacker.owner_id != state.active_player:
			return false
		if attacker.owner_id == target.owner_id:
			return false  # Can't attack allies
		if not attacker.can_attack():
			return false
		if not target.is_alive():
			return false

		# Check range
		var range_calc := RangeCalculator.new()
		return range_calc.can_attack(attacker, target, state)

	func execute(state: GameState) -> bool:
		var attacker := state.get_champion(attacker_id)
		var target := state.get_champion(target_id)

		if not attacker or not target:
			return false

		# Store undo data
		undo_data = {
			"target_hp": target.current_hp,
			"has_attacked": attacker.has_attacked
		}

		# Deal damage
		damage_dealt = target.take_damage(attacker.current_power)
		attacker.has_attacked = true
		executed = true

		# Check for leech
		if attacker.has_buff("leech"):
			attacker.heal(damage_dealt)

		return true

	func undo(state: GameState) -> bool:
		if not executed:
			return false

		var attacker := state.get_champion(attacker_id)
		var target := state.get_champion(target_id)

		if not attacker or not target:
			return false

		target.current_hp = undo_data.get("target_hp", target.max_hp)
		attacker.has_attacked = undo_data.get("has_attacked", false)
		executed = false

		return true

	func get_description() -> String:
		return "%s attacks %s for %d damage" % [attacker_id, target_id, damage_dealt]


# Cast Card Action
class CastCardAction extends Action:
	var card_name: String
	var caster_id: String
	var targets: Array  # Can be champion IDs or positions

	func _init(card: String, caster: String, tgts: Array = []):
		action_type = ActionType.CAST_CARD
		card_name = card
		caster_id = caster
		targets = tgts

	func is_valid(state: GameState) -> bool:
		var caster := state.get_champion(caster_id)
		if not caster:
			return false
		if caster.owner_id != state.active_player:
			return false
		if not caster.can_cast():
			return false

		# Check card is in hand
		var hand := state.get_hand(caster.owner_id)
		if card_name not in hand:
			return false

		# Check mana
		var card_data := CardDatabase.get_card(card_name)
		var cost: int = card_data.get("cost", 0)
		if state.get_mana(caster.owner_id) < cost:
			return false

		# Validate targets based on card requirements
		return _validate_targets(state, card_data)

	func _validate_targets(state: GameState, card_data: Dictionary) -> bool:
		var target_type: String = str(card_data.get("target", "none"))
		var caster := state.get_champion(caster_id)
		if caster == null:
			return false

		match target_type.to_lower():
			"none":
				return true  # No target needed
			"self":
				# Self-targeting can have empty targets or caster in targets
				return true
			"enemy":
				if targets.is_empty():
					return false
				var target := state.get_champion(str(targets[0]))
				if target == null or target.owner_id == state.active_player:
					return false
				return _is_in_range(caster, target)
			"ally", "friendly":
				# Friendly targets an ally (can include self for some cards)
				if targets.is_empty():
					return false
				var target := state.get_champion(str(targets[0]))
				if target == null or target.owner_id != state.active_player:
					return false
				return _is_in_range(caster, target)
			"champion", "any":
				if targets.is_empty():
					return false
				var target := state.get_champion(str(targets[0]))
				if target == null:
					return false
				return _is_in_range(caster, target)
			"allyorself":
				if targets.is_empty():
					return false
				var target := state.get_champion(str(targets[0]))
				if target == null or target.owner_id != state.active_player:
					return false
				return _is_in_range(caster, target)
			"direction":
				# Direction targeting - targets should contain direction string
				if targets.is_empty():
					return false
				var dir: String = str(targets[0]).to_lower()
				return dir in ["up", "down", "left", "right"]
			"position":
				# Position targeting - targets should contain "x,y" string
				if targets.is_empty():
					return false
				var pos_str: String = str(targets[0])
				return pos_str.contains(",")  # Basic validation
			_:
				return true

	func _is_in_range(caster: ChampionState, target: ChampionState) -> bool:
		"""Check if target is within caster's range."""
		# Self is always in range
		if caster.unique_id == target.unique_id:
			return true

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

			# Must be in a cardinal direction (one axis must be 0)
			if dx != 0 and dy != 0:
				return false

			var dist: int = absi(dx) + absi(dy)
			return dist <= caster.current_range

	func execute(state: GameState) -> bool:
		var caster := state.get_champion(caster_id)
		if not caster:
			return false

		var card_data := CardDatabase.get_card(card_name)
		var cost: int = card_data.get("cost", 0)

		# Store undo data
		undo_data = {
			"mana": state.get_mana(caster.owner_id),
			"hand": state.get_hand(caster.owner_id).duplicate()
		}

		# Spend mana
		state.spend_mana(caster.owner_id, cost)

		# Remove card from hand
		state.play_card(caster.owner_id, card_name)

		# Effects will be processed by EffectProcessor
		# For now, mark as executed
		executed = true

		# Card goes to discard
		state.get_discard(caster.owner_id).append(card_name)

		return true

	func undo(state: GameState) -> bool:
		if not executed:
			return false

		var caster := state.get_champion(caster_id)
		if not caster:
			return false

		# Restore mana and hand
		if caster.owner_id == 1:
			state.player1_mana = undo_data.get("mana", 5)
			state.player1_hand = undo_data.get("hand", [])
		else:
			state.player2_mana = undo_data.get("mana", 5)
			state.player2_hand = undo_data.get("hand", [])

		# Remove from discard
		var discard := state.get_discard(caster.owner_id)
		var idx := discard.rfind(card_name)
		if idx >= 0:
			discard.remove_at(idx)

		executed = false
		return true

	func get_description() -> String:
		return "%s casts %s" % [caster_id, card_name]


# Pass Response Action
class PassResponseAction extends Action:
	func _init(p_id: int):
		action_type = ActionType.PASS_RESPONSE
		player_id = p_id

	func is_valid(_state: GameState) -> bool:
		return true  # Always valid during response window

	func execute(_state: GameState) -> bool:
		executed = true
		return true

	func undo(_state: GameState) -> bool:
		executed = false
		return true

	func get_description() -> String:
		return "Player %d passes priority" % player_id


# Action history for undo support
var history: Array = []  # Array of Action objects
var history_index: int = -1


func execute_action(action: Action, state: GameState) -> bool:
	"""Execute an action and add to history."""
	if not action.is_valid(state):
		return false

	if not action.execute(state):
		return false

	# Clear redo history
	if history_index < history.size() - 1:
		history = history.slice(0, history_index + 1)

	history.append(action)
	history_index = history.size() - 1

	return true


func undo_last_action(state: GameState) -> bool:
	"""Undo the most recent action."""
	if history_index < 0:
		return false

	var action: Action = history[history_index]
	if action.undo(state):
		history_index -= 1
		return true

	return false


func redo_action(state: GameState) -> bool:
	"""Redo a previously undone action."""
	if history_index >= history.size() - 1:
		return false

	history_index += 1
	var action: Action = history[history_index]
	return action.execute(state)


func clear_history() -> void:
	"""Clear action history."""
	history.clear()
	history_index = -1


func get_valid_actions(state: GameState, player_id: int) -> Array:
	"""Generate all valid actions for a player. Used by AI."""
	var actions: Array = []

	for champion: ChampionState in state.get_champions(player_id):
		if not champion.is_alive():
			continue

		# Generate move actions
		if champion.can_move():
			var pathfinder := Pathfinder.new(state)
			var reachable := pathfinder.get_reachable_tiles(champion)
			for pos: Vector2i in reachable:
				var move := MoveAction.new(champion.unique_id, pos)
				if move.is_valid(state):
					actions.append(move)

		# Generate attack actions
		if champion.can_attack():
			var range_calc := RangeCalculator.new()
			for enemy: ChampionState in state.get_champions(3 - player_id):
				if enemy.is_alive() and range_calc.can_attack(champion, enemy, state):
					var attack := AttackAction.new(champion.unique_id, enemy.unique_id)
					if attack.is_valid(state):
						actions.append(attack)

		# Generate cast actions
		if champion.can_cast():
			var hand := state.get_hand(player_id)
			for card_name: String in hand:
				var card_data := CardDatabase.get_card(card_name)
				if card_data.get("type") == "Action":
					var cost: int = card_data.get("cost", 0)
					if state.get_mana(player_id) >= cost:
						# Generate for each valid target
						var target_actions := _generate_cast_targets(state, champion, card_data, card_name)
						actions.append_array(target_actions)

	return actions


func _generate_cast_targets(state: GameState, caster: ChampionState, card_data: Dictionary, card_name: String) -> Array:
	"""Generate cast actions for all valid targets."""
	var actions: Array = []
	var target_type: String = str(card_data.get("target", "none"))

	match target_type.to_lower():
		"none":
			var cast := CastCardAction.new(card_name, caster.unique_id, [])
			if cast.is_valid(state):
				actions.append(cast)
		"self":
			# Self-targeting cards pass caster as target
			var cast := CastCardAction.new(card_name, caster.unique_id, [caster.unique_id])
			if cast.is_valid(state):
				actions.append(cast)
		"enemy":
			for enemy: ChampionState in state.get_champions(3 - caster.owner_id):
				if enemy.is_alive():
					var cast := CastCardAction.new(card_name, caster.unique_id, [enemy.unique_id])
					if cast.is_valid(state):
						actions.append(cast)
		"ally", "friendly":
			# Friendly targets allies - typically includes other allies, may include self
			for ally: ChampionState in state.get_champions(caster.owner_id):
				if ally.is_alive():
					var cast := CastCardAction.new(card_name, caster.unique_id, [ally.unique_id])
					if cast.is_valid(state):
						actions.append(cast)
		"champion", "any":
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive():
					var cast := CastCardAction.new(card_name, caster.unique_id, [champ.unique_id])
					if cast.is_valid(state):
						actions.append(cast)
		"allyorself":
			for ally: ChampionState in state.get_champions(caster.owner_id):
				if ally.is_alive():
					var cast := CastCardAction.new(card_name, caster.unique_id, [ally.unique_id])
					if cast.is_valid(state):
						actions.append(cast)
		"position", "direction":
			# Position/direction targeting requires different handling
			# For now, skip these complex targeting types in AI generation
			pass

	return actions
