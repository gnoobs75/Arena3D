@tool
class_name CardData
extends Resource
## CardData - Resource class for card definitions
## Stores all card properties parsed from cards.json

# Card types
enum CardType {
	ACTION,     # Standard spell, used on your turn
	RESPONSE,   # Interrupt spell, used in response to triggers
	EQUIPMENT   # Permanent item with charges
}

# Target types
enum TargetType {
	NONE,           # No target needed
	SELF,           # Only targets self
	ALLY,           # Targets friendly champion
	ENEMY,          # Targets enemy champion
	ANY_CHAMPION,   # Targets any champion
	TILE,           # Targets board tile
	ALLY_OR_SELF    # Targets self or ally
}

# Response triggers
enum Trigger {
	NONE,           # Not a response card
	BEFORE_DAMAGE,  # Before damage is dealt
	AFTER_DAMAGE,   # After damage is dealt
	ON_MOVE,        # When a champion moves
	ON_HEAL,        # When healing occurs
	ON_CAST,        # When a card is cast
	ON_DRAW,        # When a card is drawn
	START_TURN,     # At start of turn
	END_TURN        # At end of turn
}

@export var id: String = ""
@export var display_name: String = ""
@export var champion_id: String = ""  # Which champion owns this card
@export var description: String = ""

@export_group("Card Properties")
@export var card_type: CardType = CardType.ACTION
@export var mana_cost: int = 0
@export var copies_in_deck: int = 1
@export var target_type: TargetType = TargetType.NONE
@export var trigger: Trigger = Trigger.NONE
@export var charges: int = 0  # For equipment cards

@export_group("Effects")
@export var effects: Array[EffectData] = []

@export_group("Visuals")
@export var card_art: Texture2D
@export var card_animation: SpriteFrames  # For animated card art


static func from_dict(data: Dictionary) -> CardData:
	"""Create CardData from dictionary (parsed from cards.json)."""
	var card := CardData.new()

	card.id = data.get("name", "").to_snake_case()
	card.display_name = data.get("name", "")
	card.champion_id = data.get("character", "")
	card.description = data.get("description", "")
	card.mana_cost = data.get("cost", 0)
	card.copies_in_deck = data.get("Number in Deck", 1)
	card.charges = data.get("charges", 0)

	# Parse card type
	var type_str: String = data.get("type", "Action")
	match type_str:
		"Action":
			card.card_type = CardType.ACTION
		"Response":
			card.card_type = CardType.RESPONSE
		"Equipment":
			card.card_type = CardType.EQUIPMENT

	# Parse target type
	var target_str: String = data.get("target", "none")
	match target_str.to_lower():
		"none":
			card.target_type = TargetType.NONE
		"self":
			card.target_type = TargetType.SELF
		"ally":
			card.target_type = TargetType.ALLY
		"enemy":
			card.target_type = TargetType.ENEMY
		"champion", "any":
			card.target_type = TargetType.ANY_CHAMPION
		"tile":
			card.target_type = TargetType.TILE
		"allyorself":
			card.target_type = TargetType.ALLY_OR_SELF

	# Parse trigger for response cards
	var trigger_str: String = data.get("trigger", "")
	match trigger_str.to_lower():
		"beforedamage":
			card.trigger = Trigger.BEFORE_DAMAGE
		"afterdamage":
			card.trigger = Trigger.AFTER_DAMAGE
		"onmove":
			card.trigger = Trigger.ON_MOVE
		"onheal":
			card.trigger = Trigger.ON_HEAL
		"oncast":
			card.trigger = Trigger.ON_CAST
		"ondraw":
			card.trigger = Trigger.ON_DRAW
		"startturn":
			card.trigger = Trigger.START_TURN
		"endturn":
			card.trigger = Trigger.END_TURN
		_:
			card.trigger = Trigger.NONE

	# Parse effects
	var effect_array: Array = data.get("effect", [])
	for effect_dict: Dictionary in effect_array:
		var effect := EffectData.from_dict(effect_dict)
		card.effects.append(effect)

	return card


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	var effect_dicts: Array = []
	for effect: EffectData in effects:
		effect_dicts.append({
			"type": EffectData.EffectType.keys()[effect.effect_type],
			"value": effect.value,
			"scope": EffectData.Scope.keys()[effect.scope]
		})

	return {
		"id": id,
		"name": display_name,
		"character": champion_id,
		"description": description,
		"type": CardType.keys()[card_type],
		"cost": mana_cost,
		"copies_in_deck": copies_in_deck,
		"target": TargetType.keys()[target_type],
		"trigger": Trigger.keys()[trigger],
		"charges": charges,
		"effects": effect_dicts
	}


func is_playable(mana_available: int) -> bool:
	"""Check if card can be played with available mana."""
	return mana_cost <= mana_available


func requires_target() -> bool:
	"""Check if this card needs a target to be played."""
	return target_type != TargetType.NONE and target_type != TargetType.SELF


func is_response() -> bool:
	"""Check if this is a response card."""
	return card_type == CardType.RESPONSE


func is_equipment() -> bool:
	"""Check if this is an equipment card."""
	return card_type == CardType.EQUIPMENT


func _to_string() -> String:
	return "Card<%s (%d mana) %s>" % [display_name, mana_cost, CardType.keys()[card_type]]
