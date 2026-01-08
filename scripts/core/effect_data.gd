@tool
class_name EffectData
extends Resource
## EffectData - Describes a single effect that a card can apply
## Part of CardData, parsed from the "effect" array in cards.json

# Effect types (from cards.json analysis)
enum EffectType {
	DAMAGE,         # Deal damage
	HEAL,           # Restore HP
	STAT_MOD,       # Modify power/range/movement
	BUFF,           # Apply positive effect
	DEBUFF,         # Apply negative effect
	MOVE,           # Force movement
	DRAW,           # Draw cards
	DISCARD,        # Discard cards
	CUSTOM          # Special handler needed
}

# Scope of effect
enum Scope {
	SELF,           # Affects caster
	TARGET,         # Affects target(s)
	ALL_ALLIES,     # Affects all friendly champions
	ALL_ENEMIES,    # Affects all enemy champions
	ALL,            # Affects all champions
	AREA            # Affects area around position
}

# Duration types
enum Duration {
	INSTANT,        # Happens once immediately
	THIS_TURN,      # Lasts until end of turn
	NEXT_TURN,      # Lasts until end of next turn
	PERMANENT,      # Lasts until removed
	ROUNDS          # Lasts X rounds (use duration_value)
}

@export var effect_type: EffectType = EffectType.DAMAGE
@export var scope: Scope = Scope.TARGET
@export var duration: Duration = Duration.INSTANT
@export var duration_value: int = 0  # For ROUNDS duration

@export_group("Values")
@export var value: int = 0                      # Fixed value
@export var value_formula: String = ""          # e.g., "power", "damageTaken", "oppHandSize"
@export var stat_name: String = ""              # For STAT_MOD: "power", "range", "movement"
@export var buff_name: String = ""              # For BUFF/DEBUFF: specific effect name
@export var custom_handler: String = ""         # For CUSTOM: handler function name

@export_group("Conditions")
@export var condition: String = ""              # Optional condition for effect
@export var min_value: int = 0                  # Minimum bound for random/scaled
@export var max_value: int = 0                  # Maximum bound for random/scaled


static func from_dict(data: Dictionary) -> EffectData:
	"""Parse effect data from cards.json effect object."""
	var effect := EffectData.new()

	# Determine effect type from keys present
	if data.has("damage"):
		effect.effect_type = EffectType.DAMAGE
		effect._parse_value(data.get("damage"), effect)
	elif data.has("heal"):
		effect.effect_type = EffectType.HEAL
		effect._parse_value(data.get("heal"), effect)
	elif data.has("statMod"):
		effect.effect_type = EffectType.STAT_MOD
		var mod: Dictionary = data.get("statMod", {})
		effect.stat_name = mod.get("stat", "")
		effect.value = mod.get("amount", 0)
		effect._parse_duration(mod, effect)
	elif data.has("buff"):
		effect.effect_type = EffectType.BUFF
		effect.buff_name = data.get("buff", "")
		effect._parse_duration(data, effect)
	elif data.has("debuff"):
		effect.effect_type = EffectType.DEBUFF
		effect.buff_name = data.get("debuff", "")
		effect._parse_duration(data, effect)
	elif data.has("move"):
		effect.effect_type = EffectType.MOVE
		effect.custom_handler = data.get("move", "")  # Move type as handler
	elif data.has("draw"):
		effect.effect_type = EffectType.DRAW
		effect.value = data.get("draw", 1)
	elif data.has("discard"):
		effect.effect_type = EffectType.DISCARD
		effect.value = data.get("discard", 1)
	elif data.has("custom"):
		effect.effect_type = EffectType.CUSTOM
		effect.custom_handler = data.get("custom", "")

	# Parse scope
	var scope_str: String = data.get("scope", "target")
	match scope_str.to_lower():
		"self":
			effect.scope = Scope.SELF
		"target":
			effect.scope = Scope.TARGET
		"allAllies":
			effect.scope = Scope.ALL_ALLIES
		"allEnemies":
			effect.scope = Scope.ALL_ENEMIES
		"all":
			effect.scope = Scope.ALL
		"area":
			effect.scope = Scope.AREA

	# Parse condition
	effect.condition = data.get("condition", "")

	return effect


func _parse_value(value_data, effect: EffectData) -> void:
	"""Parse a value that could be int, string formula, or dict with min/max."""
	if value_data is int:
		effect.value = value_data
	elif value_data is float:
		effect.value = int(value_data)
	elif value_data is String:
		effect.value_formula = value_data
	elif value_data is Dictionary:
		effect.min_value = value_data.get("min", 0)
		effect.max_value = value_data.get("max", 0)
		effect.value_formula = value_data.get("formula", "")


func _parse_duration(data: Dictionary, effect: EffectData) -> void:
	"""Parse duration from effect data."""
	var duration_str: String = data.get("duration", "instant")
	match duration_str.to_lower():
		"instant":
			effect.duration = Duration.INSTANT
		"thisturn":
			effect.duration = Duration.THIS_TURN
		"nextturn":
			effect.duration = Duration.NEXT_TURN
		"permanent":
			effect.duration = Duration.PERMANENT
		_:
			# Try to parse as number of rounds
			if duration_str.is_valid_int():
				effect.duration = Duration.ROUNDS
				effect.duration_value = duration_str.to_int()
			else:
				effect.duration = Duration.INSTANT


func get_effective_value(context: Dictionary = {}) -> int:
	"""Calculate the effective value based on formula and context."""
	if value_formula.is_empty():
		return value

	match value_formula:
		"power":
			return context.get("power", 0)
		"damageTaken":
			return context.get("damage_taken", 0)
		"oppHandSize":
			return context.get("opponent_hand_size", 0)
		"distance":
			return context.get("distance", 0)
		_:
			return value


func _to_string() -> String:
	var type_name := EffectType.keys()[effect_type]
	if value > 0:
		return "Effect<%s:%d>" % [type_name, value]
	elif not buff_name.is_empty():
		return "Effect<%s:%s>" % [type_name, buff_name]
	else:
		return "Effect<%s>" % type_name
