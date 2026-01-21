class_name ResponseStack
extends RefCounted
## ResponseStack - LIFO stack for response cards with 8 trigger types
## Handles priority passing and stack resolution

signal response_window_opened(trigger: String, context: Dictionary)
signal response_window_closed()
signal response_added(player_id: int, card_name: String)
signal stack_resolving()
signal stack_resolved()
signal priority_changed(player_id: int)

# Trigger types from cards.json
enum Trigger {
	NONE,
	BEFORE_DAMAGE,  # Before damage is dealt
	AFTER_DAMAGE,   # After damage is dealt
	ON_MOVE,        # When a champion moves
	ON_HEAL,        # When healing occurs
	ON_CAST,        # When a card is cast
	ON_DRAW,        # When a card is drawn
	START_TURN,     # At start of turn
	END_TURN        # At end of turn
}

# Map string triggers to enum
const TRIGGER_MAP: Dictionary = {
	"beforeDamage": Trigger.BEFORE_DAMAGE,
	"afterDamage": Trigger.AFTER_DAMAGE,
	"onMove": Trigger.ON_MOVE,
	"onHeal": Trigger.ON_HEAL,
	"onCast": Trigger.ON_CAST,
	"onDraw": Trigger.ON_DRAW,
	"startTurn": Trigger.START_TURN,
	"endTurn": Trigger.END_TURN
}

# Response entry structure
class ResponseEntry:
	var card_name: String
	var player_id: int
	var caster_id: String
	var targets: Array
	var trigger: Trigger
	var context: Dictionary

	func _init(card: String, player: int, caster: String, tgts: Array, trig: Trigger, ctx: Dictionary):
		card_name = card
		player_id = player
		caster_id = caster
		targets = tgts
		trigger = trig
		context = ctx

# Stack state
var _stack: Array[ResponseEntry] = []
var _is_open: bool = false
var _current_trigger: Trigger = Trigger.NONE
var _trigger_context: Dictionary = {}
var _priority_player: int = 0
var _consecutive_passes: int = 0
var _active_player: int = 1

# Reference to game state
var game_state: GameState


func _init(state: GameState) -> void:
	game_state = state


func open_window(trigger_name: String, context: Dictionary, triggering_player: int) -> bool:
	"""
	Open a response window for the given trigger.
	Returns true if the responding player has valid responses.
	"""
	var trigger := _parse_trigger(trigger_name)
	if trigger == Trigger.NONE:
		return false

	# Determine who gets to respond based on trigger type
	var responding_player := _get_responding_player(trigger, context, triggering_player)

	# Only check if the responding player has responses (pass context for target validation)
	if not _player_has_response(responding_player, trigger, context):
		return false

	_is_open = true
	_current_trigger = trigger
	_trigger_context = context.duplicate()
	_trigger_context["trigger"] = trigger_name
	_trigger_context["responding_player"] = responding_player
	_consecutive_passes = 0

	# Priority goes to the responding player (e.g., defender for beforeDamage)
	_active_player = triggering_player
	_priority_player = responding_player

	response_window_opened.emit(trigger_name, _trigger_context)
	priority_changed.emit(_priority_player)

	return true


func _get_responding_player(trigger: Trigger, context: Dictionary, triggering_player: int) -> int:
	"""Determine which player gets to respond based on the trigger type."""
	match trigger:
		Trigger.BEFORE_DAMAGE, Trigger.AFTER_DAMAGE:
			# The player whose champion is being damaged responds
			# Context should have "target" which is the champion being hit
			var target_id: String = context.get("target", "")
			if not target_id.is_empty():
				var target := game_state.get_champion(target_id)
				if target:
					return target.owner_id
			# Fallback to opponent of triggering player
			return 2 if triggering_player == 1 else 1

		Trigger.ON_MOVE:
			# Opponent of the moving champion can respond (e.g., Bear Trap)
			var mover_id: String = context.get("champion", "")
			if not mover_id.is_empty():
				var mover := game_state.get_champion(mover_id)
				if mover:
					return 2 if mover.owner_id == 1 else 1
			return 2 if triggering_player == 1 else 1

		Trigger.ON_HEAL:
			# Opponent can respond when enemy heals (Bloodthirsty)
			return 2 if triggering_player == 1 else 1

		Trigger.ON_DRAW:
			# Opponent responds when player draws extra cards (Hypocrite)
			return 2 if triggering_player == 1 else 1

		Trigger.ON_CAST:
			# Either player could respond to a spell (Confuse)
			# For now, opponent of caster gets priority
			return 2 if triggering_player == 1 else 1

		Trigger.END_TURN:
			# The player whose turn is ending can respond (Nature's Wrath)
			return triggering_player

		Trigger.START_TURN:
			# The player whose turn is starting can respond
			return triggering_player

		_:
			return triggering_player


func close_window() -> void:
	"""Close the response window."""
	_is_open = false
	_current_trigger = Trigger.NONE
	_trigger_context = {}
	_consecutive_passes = 0
	response_window_closed.emit()


func is_open() -> bool:
	return _is_open


func get_priority_player() -> int:
	return _priority_player


func get_current_trigger() -> String:
	return Trigger.keys()[_current_trigger]


func get_trigger_context() -> Dictionary:
	return _trigger_context


# --- Response Actions ---

func add_response(player_id: int, card_name: String, caster_id: String, targets: Array) -> bool:
	"""
	Add a response card to the stack.
	Returns false if invalid.
	"""
	if not _is_open:
		push_warning("ResponseStack: Cannot add response - window not open")
		return false

	if player_id != _priority_player:
		push_warning("ResponseStack: Player %d doesn't have priority" % player_id)
		return false

	# Validate the card is a valid response
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return false

	if card_data.get("type") != "Response":
		return false

	var card_trigger := _parse_trigger(card_data.get("trigger", ""))
	if card_trigger != _current_trigger:
		return false

	# Check mana
	var cost: int = card_data.get("cost", 0)
	if game_state.get_mana(player_id) < cost:
		return false

	# Check card is in hand
	var hand := game_state.get_hand(player_id)
	if card_name not in hand:
		return false

	# Spend mana and remove from hand
	game_state.spend_mana(player_id, cost)
	hand.erase(card_name)

	# Add to stack
	var entry := ResponseEntry.new(
		card_name,
		player_id,
		caster_id,
		targets,
		_current_trigger,
		_trigger_context.duplicate()
	)
	_stack.append(entry)

	# Reset pass counter - new response allows more responses
	_consecutive_passes = 0

	# Switch priority to opponent
	_switch_priority()

	response_added.emit(player_id, card_name)

	return true


func pass_priority() -> bool:
	"""
	Current priority player passes.
	Returns true if stack should resolve (both passed).
	"""
	if not _is_open:
		return false

	_consecutive_passes += 1

	if _consecutive_passes >= 2:
		# Both players passed - resolve stack
		return true
	else:
		# Switch priority to other player
		_switch_priority()
		return false


func resolve() -> Array[Dictionary]:
	"""
	Resolve all responses in LIFO order.
	Returns array of resolution results.
	"""
	if _stack.is_empty():
		close_window()
		return []

	stack_resolving.emit()

	var results: Array[Dictionary] = []
	var effect_processor := EffectProcessor.new(game_state)

	# Resolve in LIFO order (last in, first out)
	while not _stack.is_empty():
		var entry: ResponseEntry = _stack.pop_back()
		var caster := game_state.get_champion(entry.caster_id)

		if caster and caster.is_alive():
			var result := effect_processor.process_card(
				entry.card_name,
				caster,
				entry.targets
			)
			result["player_id"] = entry.player_id
			result["trigger"] = Trigger.keys()[entry.trigger]
			results.append(result)

			# Card goes to discard
			game_state.get_discard(entry.player_id).append(entry.card_name)

	stack_resolved.emit()
	close_window()

	return results


func _switch_priority() -> void:
	"""Switch priority to the other player."""
	_priority_player = 2 if _priority_player == 1 else 1
	priority_changed.emit(_priority_player)


func _parse_trigger(trigger_str: String) -> Trigger:
	"""Convert trigger string to enum."""
	return TRIGGER_MAP.get(trigger_str, Trigger.NONE)


func _check_for_responses(trigger: Trigger) -> bool:
	"""Check if any player has response cards for this trigger."""
	for player_id in [1, 2]:
		if _player_has_response(player_id, trigger):
			return true
	return false


func _player_has_response(player_id: int, trigger: Trigger, context: Dictionary = {}) -> bool:
	"""Check if a specific player has a valid response."""
	var hand := game_state.get_hand(player_id)
	var mana := game_state.get_mana(player_id)

	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)

		if card_data.get("type") != "Response":
			continue

		var card_trigger := _parse_trigger(card_data.get("trigger", ""))
		if card_trigger != trigger:
			continue

		var cost: int = card_data.get("cost", 0)
		if cost > mana:
			continue

		# For onMove, check if the moving enemy is actually in range
		if trigger == Trigger.ON_MOVE:
			if not _has_valid_on_move_target(player_id, card_data, context):
				continue

		# For damage triggers, check character-specific requirements
		if trigger == Trigger.BEFORE_DAMAGE or trigger == Trigger.AFTER_DAMAGE:
			if not _is_valid_damage_response(player_id, card_data, context):
				continue

		# Has at least one valid response
		return true

	return false


func _is_valid_damage_response(player_id: int, card_data: Dictionary, context: Dictionary) -> bool:
	"""Check if a damage response card is valid for this context."""
	var card_character: String = card_data.get("character", "")
	var requires_alive: bool = card_data.get("requiresAlive", false)

	# If the card is character-specific, check that the damaged champion matches
	if not card_character.is_empty():
		var target_id: String = context.get("target", "")
		if target_id.is_empty():
			return false

		var target := game_state.get_champion(target_id)
		if target == null:
			return false

		# The damaged champion must be the specific character this card belongs to
		if target.champion_name != card_character:
			return false

		# If requiresAlive is set, the character must still be alive
		if requires_alive and not target.is_alive():
			return false

	return true


func _has_valid_on_move_target(player_id: int, card_data: Dictionary, context: Dictionary) -> bool:
	"""Check if there's a valid target for an onMove response."""
	var card_range: int = card_data.get("range", 1)
	var target_type: String = card_data.get("target", "enemy")

	# Get the moving champion from context
	var mover_id: String = context.get("champion", "")
	if mover_id.is_empty():
		return false

	var mover := game_state.get_champion(mover_id)
	if mover == null or not mover.is_alive():
		return false

	# For enemy target cards, check if mover is enemy and in range of our champions
	if target_type == "enemy":
		if mover.owner_id == player_id:
			return false  # Mover is our own champion, not a valid enemy target

		# Check if mover is in range of any of our champions
		for champ: ChampionState in game_state.get_champions(player_id):
			if not champ.is_alive():
				continue
			var distance := _get_distance(champ.position, mover.position)
			if distance <= card_range:
				return true
		return false

	return true  # For other target types, allow


func _get_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate Chebyshev distance (8-directional)."""
	return maxi(absi(to.x - from.x), absi(to.y - from.y))


func get_valid_responses(player_id: int) -> Array[String]:
	"""Get all valid response cards for the current window."""
	var valid: Array[String] = []

	if not _is_open:
		return valid

	var hand := game_state.get_hand(player_id)
	var mana := game_state.get_mana(player_id)

	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)

		if card_data.get("type") != "Response":
			continue

		var card_trigger := _parse_trigger(card_data.get("trigger", ""))
		if card_trigger != _current_trigger:
			continue

		var cost: int = card_data.get("cost", 0)
		if cost > mana:
			continue

		# For onMove, check if the moving enemy is actually in range
		if _current_trigger == Trigger.ON_MOVE:
			if not _has_valid_on_move_target(player_id, card_data, _trigger_context):
				continue

		# For damage triggers, check character-specific requirements
		if _current_trigger == Trigger.BEFORE_DAMAGE or _current_trigger == Trigger.AFTER_DAMAGE:
			if not _is_valid_damage_response(player_id, card_data, _trigger_context):
				continue

		valid.append(card_name)

	return valid


func is_empty() -> bool:
	return _stack.is_empty()


func size() -> int:
	return _stack.size()


func peek() -> Dictionary:
	"""Look at top of stack without removing."""
	if _stack.is_empty():
		return {}

	var entry: ResponseEntry = _stack.back()
	return {
		"card_name": entry.card_name,
		"player_id": entry.player_id,
		"caster_id": entry.caster_id,
		"targets": entry.targets
	}


func clear() -> void:
	"""Clear the stack without resolving."""
	_stack.clear()
	close_window()
