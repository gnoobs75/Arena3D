class_name BuffRegistry
extends RefCounted
## BuffRegistry - Defines all buff and debuff behaviors
## Central location for buff/debuff effect logic

# Buff categories
enum BuffCategory {
	STAT_MODIFIER,      # Modifies power/range/movement
	ACTION_MODIFIER,    # Grants extra actions
	DAMAGE_MODIFIER,    # Modifies damage dealt/received
	PROTECTION,         # Prevents damage/effects
	MOVEMENT,           # Movement-related buffs
	SPECIAL             # Unique mechanics
}

# Debuff categories
enum DebuffCategory {
	ACTION_LOCK,        # Prevents actions
	STAT_REDUCTION,     # Reduces stats
	DAMAGE_AMPLIFY,     # Increases damage taken
	CONTROL             # Movement/position control
}

# All known buffs with their properties
const BUFFS: Dictionary = {
	# === Stat Modifiers ===
	"powerBonus": {
		"category": BuffCategory.STAT_MODIFIER,
		"stat": "power",
		"stackable": true,
		"description": "Increases power by stack amount"
	},
	"rangeBonus": {
		"category": BuffCategory.STAT_MODIFIER,
		"stat": "range",
		"stackable": true,
		"description": "Increases range by stack amount"
	},
	"movementBonus": {
		"category": BuffCategory.STAT_MODIFIER,
		"stat": "movement",
		"stackable": true,
		"description": "Increases movement by stack amount"
	},

	# === Action Modifiers ===
	"extraAttack": {
		"category": BuffCategory.ACTION_MODIFIER,
		"stackable": false,
		"description": "Can attack again this turn"
	},
	"extraMove": {
		"category": BuffCategory.ACTION_MODIFIER,
		"stackable": false,
		"description": "Can move again this turn"
	},
	"unlimitedMovement": {
		"category": BuffCategory.ACTION_MODIFIER,
		"stackable": false,
		"description": "Movement is not limited this turn"
	},
	"unlimitedRange": {
		"category": BuffCategory.ACTION_MODIFIER,
		"stackable": false,
		"description": "Attack range is unlimited this turn"
	},

	# === Damage Modifiers ===
	"damageReduction": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": true,
		"description": "Reduces incoming damage by stack amount"
	},
	"negateDamage": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": false,
		"description": "Next damage is reduced to 0"
	},
	"leech": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": false,
		"description": "Heal for damage dealt"
	},
	"Enrage": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": true,
		"description": "Gain power when damaged"
	},

	# === Protection ===
	"immune": {
		"category": BuffCategory.PROTECTION,
		"stackable": false,
		"description": "Cannot be targeted or damaged"
	},
	"shield": {
		"category": BuffCategory.PROTECTION,
		"stackable": false,
		"description": "Blocks next instance of damage"
	},
	"untouchable": {
		"category": BuffCategory.PROTECTION,
		"stackable": false,
		"description": "Cannot be targeted by enemies"
	},
	"stealth": {
		"category": BuffCategory.PROTECTION,
		"stackable": false,
		"description": "Hidden from enemies until acting"
	},
	"cheatDeath": {
		"category": BuffCategory.PROTECTION,
		"stackable": false,
		"description": "Survive lethal damage at 1 HP"
	},

	# === Movement ===
	"agility": {
		"category": BuffCategory.MOVEMENT,
		"stackable": false,
		"description": "Can move diagonally"
	},
	"overWall": {
		"category": BuffCategory.MOVEMENT,
		"stackable": false,
		"description": "Can move through walls"
	},

	# === Special ===
	"spiritLink": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Share damage with linked champion"
	},
	"returnToHand": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Card returns to hand after use"
	},
	"castFromDiscard": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Can cast cards from discard pile"
	},
	"shuffleDiscard": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Shuffle discard into deck"
	},
	"gainMana": {
		"category": BuffCategory.SPECIAL,
		"stackable": true,
		"description": "Gain extra mana"
	},
	"stealMana": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Steal mana from opponent"
	},
	"spectreEssence": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Dark Wizard special - gain power from kills"
	},
	"drawOnDamage": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Draw a card when dealing damage"
	},
	"copyStats": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Copy target's stats"
	},
	"critical": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": false,
		"description": "50% chance to deal double damage"
	},
	"returnDamage": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": false,
		"description": "Reflect combat damage back to attacker"
	},
	"redirectDamage": {
		"category": BuffCategory.DAMAGE_MODIFIER,
		"stackable": false,
		"description": "Redirect damage to attacker instead"
	},
	"elkRestoration": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Heal all friendlies when dealing combat damage"
	},
	"apeSmash": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Splash 1 damage to other enemies in range on combat damage"
	},
	"attackHeals": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Attack can heal friendly targets instead of damaging"
	},
	"freeRangerCard": {
		"category": BuffCategory.SPECIAL,
		"stackable": false,
		"description": "Play one Ranger card for free this turn"
	}
}

# All known debuffs with their properties
const DEBUFFS: Dictionary = {
	# === Action Locks ===
	"canAttack": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot attack"
	},
	"canMove": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot move"
	},
	"canCast": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot cast cards"
	},
	"stunned": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot take any actions"
	},
	"silenced": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot cast cards"
	},
	"rooted": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot move but can attack/cast"
	},
	"disarmed": {
		"category": DebuffCategory.ACTION_LOCK,
		"stackable": false,
		"description": "Cannot attack but can move/cast"
	},

	# === Stat Reductions ===
	"powerReduction": {
		"category": DebuffCategory.STAT_REDUCTION,
		"stat": "power",
		"stackable": true,
		"description": "Reduces power by stack amount"
	},
	"rangeReduction": {
		"category": DebuffCategory.STAT_REDUCTION,
		"stat": "range",
		"stackable": true,
		"description": "Reduces range by stack amount"
	},
	"movementReduction": {
		"category": DebuffCategory.STAT_REDUCTION,
		"stat": "movement",
		"stackable": true,
		"description": "Reduces movement by stack amount"
	},
	"powerLocked": {
		"category": DebuffCategory.STAT_REDUCTION,
		"stackable": false,
		"description": "Power cannot be increased"
	},

	# === Damage Amplify ===
	"vulnerable": {
		"category": DebuffCategory.DAMAGE_AMPLIFY,
		"stackable": true,
		"description": "Takes extra damage"
	},
	"marked": {
		"category": DebuffCategory.DAMAGE_AMPLIFY,
		"stackable": false,
		"description": "Takes double damage from next attack"
	},

	# === Control ===
	"dropEquipment": {
		"category": DebuffCategory.CONTROL,
		"stackable": false,
		"description": "Drops all equipment"
	},
	"taunted": {
		"category": DebuffCategory.CONTROL,
		"stackable": false,
		"description": "Must attack the taunter"
	},
	"confused": {
		"category": DebuffCategory.CONTROL,
		"stackable": false,
		"description": "Random target selection"
	}
}


static func get_buff_info(buff_name: String) -> Dictionary:
	"""Get buff properties by name."""
	return BUFFS.get(buff_name, {"description": "Unknown buff"})


static func get_debuff_info(debuff_name: String) -> Dictionary:
	"""Get debuff properties by name."""
	return DEBUFFS.get(debuff_name, {"description": "Unknown debuff"})


static func is_buff_stackable(buff_name: String) -> bool:
	"""Check if a buff stacks."""
	var info := get_buff_info(buff_name)
	return info.get("stackable", false)


static func is_debuff_stackable(debuff_name: String) -> bool:
	"""Check if a debuff stacks."""
	var info := get_debuff_info(debuff_name)
	return info.get("stackable", false)


static func get_stat_buff_name(stat: String, is_positive: bool) -> String:
	"""Get the buff/debuff name for a stat modifier."""
	if is_positive:
		return stat + "Bonus"
	else:
		return stat + "Reduction"


static func prevents_action(champion: ChampionState, action_type: String) -> bool:
	"""Check if champion is prevented from taking an action."""
	# Stunned prevents everything
	if champion.has_debuff("stunned"):
		return true

	match action_type:
		"move":
			return champion.has_debuff("canMove") or champion.has_debuff("rooted")
		"attack":
			return champion.has_debuff("canAttack") or champion.has_debuff("disarmed")
		"cast":
			return champion.has_debuff("canCast") or champion.has_debuff("silenced")

	return false


static func calculate_damage_modifier(champion: ChampionState, base_damage: int, is_incoming: bool, context: Dictionary = {}) -> int:
	"""Calculate modified damage based on buffs/debuffs.
	context can include: is_aoe (bool), is_combat (bool), attacker (ChampionState)"""
	var damage := base_damage

	if is_incoming:
		# Stealth (ignore non-AOE damage) - Stealth Flask
		if champion.has_buff("stealth"):
			var is_aoe: bool = context.get("is_aoe", false)
			if not is_aoe:
				return 0  # Stealth ignores non-AOE damage

		# Incoming damage modifiers
		if champion.has_buff("negateDamage"):
			champion.remove_buff("negateDamage")
			return 0

		if champion.has_buff("shield"):
			champion.remove_buff("shield")
			return 0

		if champion.has_buff("immune"):
			return 0

		# Damage reduction
		var reduction := champion.get_buff_stacks("damageReduction")
		damage = maxi(1, damage - reduction)

		# Vulnerability
		var vulnerability := champion.get_debuff_stacks("vulnerable")
		damage += vulnerability

		# Marked (double damage)
		if champion.has_debuff("marked"):
			champion.remove_debuff("marked")
			damage *= 2

	return damage


static func should_trigger_on_damage(champion: ChampionState) -> Array[String]:
	"""Get list of effects that trigger when champion takes damage."""
	var triggers: Array[String] = []

	if champion.has_buff("Enrage"):
		triggers.append("Enrage")
	if champion.has_buff("spiritLink"):
		triggers.append("spiritLink")

	return triggers


static func apply_on_damage_triggers(champion: ChampionState, damage_taken: int, game_state: GameState) -> void:
	"""Apply effects that trigger when taking damage."""
	if champion.has_buff("Enrage"):
		champion.add_buff("powerBonus", -1, 1, "Enrage")

	if champion.has_buff("spiritLink"):
		# Find linked champion and share damage
		var link_source: String = champion.buffs["spiritLink"].get("source", "")
		if not link_source.is_empty():
			var linked := game_state.get_champion(link_source)
			if linked and linked.is_alive():
				var shared_damage := damage_taken / 2
				linked.take_damage(shared_damage)
				champion.heal(shared_damage)


static func check_cheat_death(champion: ChampionState) -> bool:
	"""Check and apply cheat death if applicable. Returns true if death was prevented."""
	if champion.current_hp <= 0 and champion.has_buff("cheatDeath"):
		champion.current_hp = 1
		champion.remove_buff("cheatDeath")
		return true
	return false
