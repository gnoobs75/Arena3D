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

		# Special case: attackHeals buff allows "attacking" allies to heal them
		if attacker.has_buff("attackHeals"):
			# Can target allies for healing
			if attacker.owner_id != target.owner_id:
				return false  # With attackHeals, can ONLY target allies
		else:
			# Normal attack - can't attack allies
			if attacker.owner_id == target.owner_id:
				return false

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
			"attacker_hp": attacker.current_hp,
			"has_attacked": attacker.has_attacked,
			"had_extra_attack": attacker.has_buff("extraAttack")
		}

		# Calculate base damage/heal amount
		var amount: int = attacker.current_power

		# Check for attackHeals buff - heal ally instead of damage
		if attacker.has_buff("attackHeals"):
			# This is a heal action, not damage
			damage_dealt = target.heal(amount)
			print("%s heals %s for %d (attackHeals)" % [attacker.champion_name, target.champion_name, damage_dealt])
		else:
			# Normal damage attack
			var damage: int = amount

			# Critical hit (50% chance for double damage) - Bloodletter equipment
			if attacker.has_buff("critical"):
				if randi() % 2 == 0:
					damage *= 2
					print("Critical hit! Damage doubled to %d" % damage)

			# Check for redirectDamage (Self-Hate) - damage goes to attacker instead
			if target.has_buff("redirectDamage"):
				target.remove_buff("redirectDamage")
				damage_dealt = attacker.take_damage(damage)
				print("Damage redirected to attacker! %s takes %d damage" % [attacker.champion_name, damage_dealt])
				# Skip normal damage to target
			else:
				# Deal damage to target normally
				damage_dealt = target.take_damage(damage)

		# Check for extra attack buff
		if not attacker.has_attacked:
			# First attack of the turn - just mark as attacked
			attacker.has_attacked = true
		elif attacker.has_buff("extraAttack"):
			# Already attacked once, but has extra attack buff - consume it
			attacker.remove_buff("extraAttack")
			# has_attacked stays true, but we allowed this attack
		else:
			# No extra attack available - this shouldn't happen if is_valid was checked
			attacker.has_attacked = true

		executed = true

		# Post-damage effects (only if damage was dealt to target, not redirected, and not a heal)
		if damage_dealt > 0 and not target.has_buff("redirectDamage") and not attacker.has_buff("attackHeals"):
			# Check for leech
			if attacker.has_buff("leech"):
				attacker.heal(damage_dealt)

			# Return damage (Intimidation) - reflect damage back to attacker
			if target.has_buff("returnDamage"):
				var reflected: int = attacker.take_damage(damage_dealt)
				print("Return damage! %s takes %d reflected damage" % [attacker.champion_name, reflected])

			# Elk Restoration - heal all friendlies when dealing combat damage
			if attacker.has_buff("elkRestoration"):
				for ally: ChampionState in state.get_champions(attacker.owner_id):
					if ally.is_alive():
						ally.heal(2)
				print("Elk Restoration healed all friendlies for 2")

			# Ape Smash - splash 1 damage to other enemies in range
			if attacker.has_buff("apeSmash"):
				var opp_id := 2 if attacker.owner_id == 1 else 1
				var range_calc := RangeCalculator.new()
				for enemy: ChampionState in state.get_champions(opp_id):
					if enemy.is_alive() and enemy.unique_id != target_id:
						if range_calc.can_attack(attacker, enemy, state):
							enemy.take_damage(1)
							print("Ape Smash splashes 1 damage to %s" % enemy.champion_name)

			# Draw on damage (Cheetah Form)
			if attacker.has_buff("drawOnDamage"):
				state.draw_card(attacker.owner_id)
				print("Draw on damage triggered - drew a card")

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

		# Restore extraAttack buff if it was consumed
		if undo_data.get("had_extra_attack", false) and not attacker.has_buff("extraAttack"):
			attacker.add_buff("extraAttack", 0, 1, "undo")

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

		# Check for freeRangerCard buff - Ranger cards cost 0
		var card_character: String = card_data.get("character", "")
		if card_character == "Ranger" and caster.has_buff("freeRangerCard"):
			cost = 0  # Free Ranger card

		if state.get_mana(caster.owner_id) < cost:
			return false

		# Check for action restriction conflicts
		# If a card applies "canAttack: false" to self, caster must not have attacked yet
		if _card_prevents_attack_on_self(card_data) and caster.has_attacked:
			return false

		# If a card applies "canMove: false" to self, caster must not have moved yet
		if _card_prevents_move_on_self(card_data) and caster.has_moved:
			return false

		# Validate targets based on card requirements
		return _validate_targets(state, card_data)

	func _card_prevents_attack_on_self(card_data: Dictionary) -> bool:
		"""Check if a card applies canAttack: false debuff to self."""
		var effects: Array = card_data.get("effect", [])
		for effect: Dictionary in effects:
			var effect_type: String = effect.get("type", "")
			if effect_type == "debuff":
				var debuff_name: String = effect.get("name", "")
				var debuff_target: String = effect.get("target", "")
				var debuff_value = effect.get("value", true)
				# Check for canAttack debuff on self
				if debuff_name == "canAttack" and debuff_target == "self" and debuff_value == false:
					return true
		return false

	func _card_prevents_move_on_self(card_data: Dictionary) -> bool:
		"""Check if a card applies canMove: false debuff to self."""
		var effects: Array = card_data.get("effect", [])
		for effect: Dictionary in effects:
			var effect_type: String = effect.get("type", "")
			if effect_type == "debuff":
				var debuff_name: String = effect.get("name", "")
				var debuff_target: String = effect.get("target", "")
				var debuff_value = effect.get("value", true)
				# Check for canMove debuff on self
				if debuff_name == "canMove" and debuff_target == "self" and debuff_value == false:
					return true
		return false

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

		# Check for freeRangerCard buff
		var card_character: String = card_data.get("character", "")
		var free_ranger := false
		if card_character == "Ranger" and caster.has_buff("freeRangerCard"):
			cost = 0
			free_ranger = true

		# Store undo data
		undo_data = {
			"mana": state.get_mana(caster.owner_id),
			"hand": state.get_hand(caster.owner_id).duplicate(),
			"had_free_ranger": free_ranger
		}

		# Spend mana
		state.spend_mana(caster.owner_id, cost)

		# Consume freeRangerCard buff if used
		if free_ranger:
			caster.remove_buff("freeRangerCard")
			print("Free Ranger card used: %s" % card_name)

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
