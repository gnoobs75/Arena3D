class_name EquipmentSystem
extends RefCounted
## EquipmentSystem - Manages equipment cards with charges
## Equipment cards persist until charges are depleted

signal equipment_equipped(champion_id: String, card_name: String, charges: int)
signal equipment_used(champion_id: String, card_name: String, charges_remaining: int)
signal equipment_depleted(champion_id: String, card_name: String)
signal equipment_dropped(champion_id: String, card_name: String)

# Equipment entry structure
class EquipmentEntry:
	var card_name: String
	var charges_max: int
	var charges_remaining: int
	var effects: Array  # Passive effects while equipped
	var use_effects: Array  # Effects when using a charge
	var owner_id: int

	func _init(card: String, max_charges: int, passive: Array, active: Array, owner: int):
		card_name = card
		charges_max = max_charges
		charges_remaining = max_charges
		effects = passive
		use_effects = active
		owner_id = owner

var game_state: GameState


func _init(state: GameState) -> void:
	game_state = state


func equip(champion: ChampionState, card_name: String) -> bool:
	"""Equip an equipment card to a champion."""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return false

	if card_data.get("type") != "Equipment":
		return false

	var charges: int = card_data.get("charges", 1)
	var effects: Array = card_data.get("effect", [])

	# Separate passive effects from use effects
	var passive_effects: Array = []
	var use_effects: Array = []

	for effect: Dictionary in effects:
		if effect.get("trigger", "") == "onUse":
			use_effects.append(effect)
		else:
			passive_effects.append(effect)

	# Create equipment entry
	var entry := EquipmentEntry.new(
		card_name,
		charges,
		passive_effects,
		use_effects,
		champion.owner_id
	)

	# Store in champion
	champion.equipment[card_name] = {
		"charges_remaining": charges,
		"charges_max": charges,
		"passive_effects": passive_effects,
		"use_effects": use_effects
	}

	# Apply passive effects
	_apply_passive_effects(champion, passive_effects)

	equipment_equipped.emit(champion.unique_id, card_name, charges)
	return true


func use_equipment(champion: ChampionState, card_name: String, targets: Array = []) -> Dictionary:
	"""Use one charge of equipment. Returns effect results."""
	if not champion.has_equipment(card_name):
		return {"success": false, "error": "Equipment not found"}

	var equip_data: Dictionary = champion.equipment[card_name]
	var charges: int = equip_data.get("charges_remaining", 0)

	if charges <= 0:
		return {"success": false, "error": "No charges remaining"}

	# Use a charge
	equip_data["charges_remaining"] = charges - 1
	equipment_used.emit(champion.unique_id, card_name, charges - 1)

	# Check for boostFlasks buff - doubles flask effects
	var is_flask := card_name.to_lower().contains("flask")
	var boosted := false
	if is_flask and champion.has_buff("boostFlasks"):
		boosted = true
		champion.remove_buff("boostFlasks")  # Consume the buff
		print("Boosted flask! %s effect doubled" % card_name)

	# Process use effects
	var results: Array = []
	var use_effects: Array = equip_data.get("use_effects", [])

	if not use_effects.is_empty():
		var effect_processor := EffectProcessor.new(game_state)
		var times := 2 if boosted else 1
		for _i in range(times):
			for effect: Dictionary in use_effects:
				var result := effect_processor._process_single_effect(effect, champion, targets, {})
				results.append(result)

	# Check if depleted
	if charges - 1 <= 0:
		_remove_equipment(champion, card_name)
		equipment_depleted.emit(champion.unique_id, card_name)

	return {
		"success": true,
		"card_name": card_name,
		"charges_remaining": maxi(0, charges - 1),
		"effects": results
	}


func drop_equipment(champion: ChampionState, card_name: String) -> bool:
	"""Drop equipment (from debuff or effect)."""
	if not champion.has_equipment(card_name):
		return false

	_remove_equipment(champion, card_name)
	equipment_dropped.emit(champion.unique_id, card_name)

	# Card goes to discard
	game_state.get_discard(champion.owner_id).append(card_name)

	return true


func drop_all_equipment(champion: ChampionState) -> Array[String]:
	"""Drop all equipment from a champion."""
	var dropped: Array[String] = []
	var equipment_names := champion.equipment.keys()

	for card_name: String in equipment_names:
		if drop_equipment(champion, card_name):
			dropped.append(card_name)

	return dropped


func _remove_equipment(champion: ChampionState, card_name: String) -> void:
	"""Remove equipment and its passive effects."""
	if not champion.equipment.has(card_name):
		return

	var equip_data: Dictionary = champion.equipment[card_name]
	var passive_effects: Array = equip_data.get("passive_effects", [])

	# Remove passive effects
	_remove_passive_effects(champion, passive_effects)

	# Remove from champion
	champion.equipment.erase(card_name)


func _apply_passive_effects(champion: ChampionState, effects: Array) -> void:
	"""Apply passive effects from equipment."""
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"buff":
				var buff_name: String = effect.get("name", "")
				var value = effect.get("value", 1)
				var stacks: int = value if value is int else 1
				champion.add_buff(buff_name, -1, stacks, "equipment")

			"statMod":
				var stat: String = effect.get("stat", "")
				var amount: int = effect.get("value", 0)
				if amount > 0:
					champion.add_buff(stat + "Bonus", -1, amount, "equipment")
				else:
					champion.add_debuff(stat + "Reduction", -1, absi(amount), "equipment")


func _remove_passive_effects(champion: ChampionState, effects: Array) -> void:
	"""Remove passive effects when equipment is removed."""
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"buff":
				var buff_name: String = effect.get("name", "")
				champion.remove_buff(buff_name)

			"statMod":
				var stat: String = effect.get("stat", "")
				var amount: int = effect.get("value", 0)
				if amount > 0:
					champion.remove_buff(stat + "Bonus")
				else:
					champion.remove_debuff(stat + "Reduction")


func get_equipped_items(champion: ChampionState) -> Array[Dictionary]:
	"""Get all equipped items with their status."""
	var items: Array[Dictionary] = []

	for card_name: String in champion.equipment:
		var equip_data: Dictionary = champion.equipment[card_name]
		items.append({
			"card_name": card_name,
			"charges_remaining": equip_data.get("charges_remaining", 0),
			"charges_max": equip_data.get("charges_max", 1)
		})

	return items


func get_total_equipment_count(champion: ChampionState) -> int:
	"""Get number of equipped items."""
	return champion.equipment.size()


func has_usable_equipment(champion: ChampionState) -> bool:
	"""Check if champion has any equipment with charges."""
	for card_name: String in champion.equipment:
		var equip_data: Dictionary = champion.equipment[card_name]
		if equip_data.get("charges_remaining", 0) > 0:
			return true
	return false


func get_equipment_charges(champion: ChampionState, card_name: String) -> int:
	"""Get remaining charges for specific equipment."""
	if not champion.equipment.has(card_name):
		return 0
	return champion.equipment[card_name].get("charges_remaining", 0)


# --- Equipment-specific card effects ---

func process_equipment_card(card_name: String, caster: ChampionState, targets: Array) -> Dictionary:
	"""Process playing an equipment card."""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return {"success": false, "error": "Card not found"}

	# Determine target - self or specified target
	var target_type: String = card_data.get("target", "self")
	var equip_target: ChampionState

	match target_type.to_lower():
		"self":
			equip_target = caster
		"ally", "friendly":
			if targets.is_empty():
				equip_target = caster
			else:
				equip_target = game_state.get_champion(targets[0])
		_:
			equip_target = caster

	if equip_target == null:
		return {"success": false, "error": "Invalid target"}

	# Equip the item
	var equipped := equip(equip_target, card_name)

	return {
		"success": equipped,
		"card_name": card_name,
		"equipped_to": equip_target.unique_id,
		"charges": card_data.get("charges", 1)
	}
