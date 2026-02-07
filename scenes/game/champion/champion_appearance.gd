class_name ChampionAppearance
extends RefCounted
## ChampionAppearance - Data-driven visual configuration for each champion
## Defines body proportions, colors, equipment, and personality for articulated 2D rendering

# Body proportions (pixels, relative to ~52px token)
var body_scale: float = 1.0
var head_radius: float = 7.0
var torso_width: float = 12.0
var torso_height: float = 14.0
var arm_length: float = 12.0
var arm_width: float = 3.5
var leg_length: float = 14.0
var leg_width: float = 4.0
var shoulder_width: float = 14.0

# Colors
var skin_color: Color = Color(0.7, 0.55, 0.4)
var primary_color: Color = Color(0.4, 0.4, 0.4)
var secondary_color: Color = Color(0.5, 0.5, 0.5)
var accent_color: Color = Color(0.8, 0.7, 0.3)

# Equipment
var weapon_type: String = "none"  # none, fists, bow, staff, axe, dagger, sword, wand, flask
var has_hood: bool = false
var has_cloak: bool = false
var has_robe: bool = false
var has_halo: bool = false
var has_goggles: bool = false
var has_backpack: bool = false

# Special effects
var has_glow: bool = false
var glow_color: Color = Color.WHITE
var is_floating: bool = false
var float_height: float = 0.0
var is_hunched: bool = false

# Dual wielding
var dual_wield: bool = false
var left_weapon_type: String = "none"

# Weapon scaling
var weapon_scale: float = 1.0

# Blindfold (Confessor)
var has_blindfold: bool = false
var blindfold_color: Color = Color(0.15, 0.12, 0.2)

# Hand glow (Redeemer)
var has_hand_glow: bool = false
var hand_glow_color: Color = Color(1.0, 0.95, 0.6, 0.6)

# Crystal staff (Illusionist)
var has_staff_crystal: bool = false
var crystal_color: Color = Color(0.8, 0.5, 0.9)

# Electricity (Shaman)
var has_electricity: bool = false
var electricity_color: Color = Color(0.4, 0.8, 1.0)

# Smoke wisps (Illusionist)
var has_smoke_wisps: bool = false
var smoke_color: Color = Color(0.6, 0.3, 0.8, 0.5)

# Dark butterflies (DarkWizard)
var has_dark_butterflies: bool = false
var butterfly_color: Color = Color(0.2, 0.0, 0.3)

# Dark aura (DarkWizard)
var has_dark_aura: bool = false
var dark_aura_color: Color = Color(0.1, 0.0, 0.15, 0.4)

# Potion smoke (Alchemist)
var has_potion_smoke: bool = false
var potion_smoke_color: Color = Color(0.3, 0.9, 0.15, 0.5)

# Beast transformation
var beast_form: String = "base"  # base, bear, elk, ape

# Hair (art-inspired)
var hair_style: String = "none"  # none, mohawk, flowing, wild, flame, tentacles, spiky
var hair_color: Color = Color(0.4, 0.3, 0.2)
var hair_size: float = 1.0  # multiplier for how prominent hair is

# Facial features (art-inspired)
var has_tusks: bool = false
var has_beard: bool = false
var beard_color: Color = Color(0.4, 0.3, 0.2)
var has_horns: bool = false  # Viking-style horns (Barbarian)
var horn_color: Color = Color(0.8, 0.8, 0.7)
var has_pointed_ears: bool = false
var has_face_mask: bool = false  # dark eye band (Ranger)
var mask_color: Color = Color(0.1, 0.1, 0.1)
var eye_style: String = "normal"  # normal, single_glow, crescent, hidden
var eye_glow_color: Color = Color(1.0, 1.0, 1.0, 0.9)

# Torso details (art-inspired)
var has_lacing: bool = false  # X-lace pattern (Brute)
var has_coat: bool = false  # lab coat (Alchemist)
var coat_color: Color = Color(0.9, 0.9, 0.9)
var has_arm_bands: bool = false
var arm_band_color: Color = Color(0.3, 0.3, 0.3)

# Shadow spirit (Beast)
var has_shadow_spirit: bool = false

# Idle personality
var idle_speed: float = 1.0  # Multiplier for breathing/sway speed
var idle_intensity: float = 1.0  # How much the idle moves

# Attack style
var attack_style: String = "melee"  # melee, ranged, magic, heavy
var attack_style_override: String = ""  # dance, dual_melee, dual_axe, electric


static func create_for_champion(champion_name: String) -> ChampionAppearance:
	"""Factory method to create appearance for a specific champion."""
	var app := ChampionAppearance.new()
	var colors := VisualTheme.get_champion_colors(champion_name)
	app.primary_color = colors.get("primary", Color(0.4, 0.4, 0.4))
	app.secondary_color = colors.get("secondary", Color(0.5, 0.5, 0.5))

	match champion_name:
		"Brute":
			_configure_brute(app)
		"Ranger":
			_configure_ranger(app)
		"Beast":
			_configure_beast(app)
		"Redeemer":
			_configure_redeemer(app)
		"Confessor":
			_configure_confessor(app)
		"Barbarian":
			_configure_barbarian(app)
		"Burglar":
			_configure_burglar(app)
		"Berserker":
			_configure_berserker(app)
		"Shaman":
			_configure_shaman(app)
		"Illusionist":
			_configure_illusionist(app)
		"DarkWizard":
			_configure_dark_wizard(app)
		"Alchemist":
			_configure_alchemist(app)
		_:
			push_warning("ChampionAppearance: No config for '%s', using defaults" % champion_name)

	return app


# === CHAMPION CONFIGURATIONS ===

static func _configure_brute(app: ChampionAppearance) -> void:
	# Art: Green orc, tusks/underbite, tiny head on massive body, X-laced black vest, arm bracers
	app.body_scale = 1.25
	app.head_radius = 6.5
	app.torso_width = 16.0
	app.torso_height = 16.0
	app.arm_length = 14.0
	app.arm_width = 5.5
	app.leg_length = 12.0
	app.leg_width = 6.0
	app.shoulder_width = 18.0
	app.skin_color = Color(0.35, 0.6, 0.25)
	app.accent_color = Color(0.3, 0.3, 0.25)
	app.weapon_type = "fists"
	app.has_tusks = true
	app.has_pointed_ears = true
	app.has_lacing = true
	app.has_arm_bands = true
	app.arm_band_color = Color(0.25, 0.25, 0.25)
	app.idle_speed = 0.7
	app.idle_intensity = 0.8
	app.attack_style = "heavy"


static func _configure_ranger(app: ChampionAppearance) -> void:
	# Art: Dark flowing hair, eye mask/face paint, all-black outfit, bow, quiver
	app.body_scale = 0.9
	app.head_radius = 6.5
	app.torso_width = 10.0
	app.torso_height = 14.0
	app.arm_length = 14.0
	app.arm_width = 3.0
	app.leg_length = 16.0
	app.leg_width = 3.5
	app.shoulder_width = 12.0
	app.skin_color = Color(0.75, 0.6, 0.5)
	app.accent_color = Color(0.55, 0.42, 0.25)
	app.weapon_type = "bow"
	app.hair_style = "flowing"
	app.hair_color = Color(0.1, 0.08, 0.12)
	app.hair_size = 1.0
	app.has_face_mask = true
	app.mask_color = Color(0.08, 0.08, 0.1)
	app.idle_speed = 1.1
	app.attack_style = "ranged"


static func _configure_beast(app: ChampionAppearance) -> void:
	# Art: Beard, green tunic, meditating pose, dark shadow spirit with antlers behind him
	app.body_scale = 1.05
	app.head_radius = 7.5
	app.torso_width = 13.0
	app.torso_height = 12.0
	app.arm_length = 15.0
	app.arm_width = 4.0
	app.leg_length = 12.0
	app.leg_width = 5.0
	app.shoulder_width = 15.0
	app.skin_color = Color(0.6, 0.5, 0.4)
	app.accent_color = Color(0.6, 0.5, 0.3)
	app.weapon_type = "fists"
	app.is_hunched = true
	app.has_beard = true
	app.beard_color = Color(0.3, 0.25, 0.18)
	app.has_shadow_spirit = true
	app.idle_speed = 1.4
	app.idle_intensity = 1.3
	app.attack_style = "melee"


static func _configure_redeemer(app: ChampionAppearance) -> void:
	# Art: Flowing golden hair, white gown/robe, ankh, yellow cape, pale angelic skin, halo
	app.body_scale = 1.0
	app.head_radius = 6.5
	app.torso_width = 11.0
	app.torso_height = 16.0
	app.arm_length = 13.0
	app.arm_width = 3.0
	app.leg_length = 15.0
	app.leg_width = 3.5
	app.shoulder_width = 12.0
	app.skin_color = Color(0.85, 0.75, 0.65)
	app.accent_color = Color(1.0, 0.95, 0.7)
	app.weapon_type = "none"
	app.has_robe = true
	app.has_halo = true
	app.has_glow = true
	app.glow_color = Color(1.0, 0.95, 0.6, 0.3)
	app.has_hand_glow = true
	app.hand_glow_color = Color(1.0, 0.95, 0.6, 0.6)
	app.hair_style = "flowing"
	app.hair_color = Color(0.9, 0.8, 0.3)
	app.hair_size = 1.2
	app.idle_speed = 0.6
	app.idle_intensity = 0.7
	app.attack_style = "magic"


static func _configure_confessor(app: ChampionAppearance) -> void:
	# Art: Purple flowing hair tendrils, dancer, purple top, blindfolded, floating
	app.body_scale = 1.05
	app.head_radius = 6.0
	app.torso_width = 10.0
	app.torso_height = 17.0
	app.arm_length = 14.0
	app.arm_width = 3.0
	app.leg_length = 15.0
	app.leg_width = 3.0
	app.shoulder_width = 11.0
	app.skin_color = Color(0.5, 0.45, 0.5)
	app.accent_color = Color(0.3, 0.35, 0.6)
	app.weapon_type = "none"
	app.has_robe = true
	app.is_floating = true
	app.float_height = 3.0
	app.has_glow = true
	app.glow_color = Color(0.2, 0.25, 0.5, 0.25)
	app.has_blindfold = true
	app.blindfold_color = Color(0.15, 0.12, 0.2)
	app.hair_style = "tentacles"
	app.hair_color = Color(0.4, 0.15, 0.5)
	app.hair_size = 1.3
	app.idle_speed = 0.5
	app.idle_intensity = 0.5
	app.attack_style = "magic"
	app.attack_style_override = "dance"


static func _configure_barbarian(app: ChampionAppearance) -> void:
	# Art: Viking horns, wild orange beard + flowing hair, shirtless, arm bands, big axe
	app.body_scale = 1.15
	app.head_radius = 7.0
	app.torso_width = 14.0
	app.torso_height = 15.0
	app.arm_length = 13.0
	app.arm_width = 5.0
	app.leg_length = 13.0
	app.leg_width = 5.5
	app.shoulder_width = 16.0
	app.skin_color = Color(0.6, 0.4, 0.3)
	app.accent_color = Color(0.8, 0.2, 0.15)
	app.weapon_type = "axe"
	app.weapon_scale = 1.6
	app.has_horns = true
	app.horn_color = Color(0.75, 0.7, 0.55)
	app.hair_style = "wild"
	app.hair_color = Color(0.85, 0.5, 0.15)
	app.hair_size = 1.2
	app.has_beard = true
	app.beard_color = Color(0.85, 0.5, 0.15)
	app.has_arm_bands = true
	app.arm_band_color = Color(0.5, 0.35, 0.2)
	app.idle_speed = 1.0
	app.idle_intensity = 1.2
	app.attack_style = "heavy"


static func _configure_burglar(app: ChampionAppearance) -> void:
	# Art: Purple hood covering face, single glowing eye peering out, daggers, cloak
	app.body_scale = 0.85
	app.head_radius = 6.0
	app.torso_width = 9.0
	app.torso_height = 12.0
	app.arm_length = 11.0
	app.arm_width = 2.5
	app.leg_length = 13.0
	app.leg_width = 3.0
	app.shoulder_width = 10.0
	app.skin_color = Color(0.55, 0.5, 0.45)
	app.accent_color = Color(0.3, 0.3, 0.35)
	app.weapon_type = "dagger"
	app.dual_wield = true
	app.left_weapon_type = "dagger"
	app.has_hood = true
	app.has_cloak = true
	app.eye_style = "single_glow"
	app.eye_glow_color = Color(0.7, 0.4, 1.0, 0.9)
	app.idle_speed = 1.3
	app.idle_intensity = 0.9
	app.attack_style = "melee"
	app.attack_style_override = "dual_melee"


static func _configure_berserker(app: ChampionAppearance) -> void:
	# Art: Red mohawk, pointed ears, chunky muscular build, red boots/accents, dual axes
	app.body_scale = 1.2
	app.head_radius = 7.0
	app.torso_width = 15.0
	app.torso_height = 16.0
	app.arm_length = 14.0
	app.arm_width = 5.0
	app.leg_length = 13.0
	app.leg_width = 5.5
	app.shoulder_width = 17.0
	app.skin_color = Color(0.55, 0.35, 0.3)
	app.accent_color = Color(0.9, 0.15, 0.1)
	app.weapon_type = "axe"
	app.dual_wield = true
	app.left_weapon_type = "axe"
	app.has_glow = true
	app.glow_color = Color(1.0, 0.2, 0.1, 0.2)
	app.hair_style = "mohawk"
	app.hair_color = Color(0.9, 0.15, 0.1)
	app.hair_size = 1.3
	app.has_pointed_ears = true
	app.has_arm_bands = true
	app.arm_band_color = Color(0.6, 0.1, 0.08)
	app.idle_speed = 1.5
	app.idle_intensity = 1.4
	app.attack_style = "heavy"
	app.attack_style_override = "dual_axe"


static func _configure_shaman(app: ChampionAppearance) -> void:
	# Art: Flame-like ice-blue hair rising upward, tribal charms, ethereal, staff with lightning
	app.body_scale = 1.0
	app.head_radius = 7.5
	app.torso_width = 11.0
	app.torso_height = 14.0
	app.arm_length = 13.0
	app.arm_width = 3.5
	app.leg_length = 14.0
	app.leg_width = 4.0
	app.shoulder_width = 13.0
	app.skin_color = Color(0.55, 0.5, 0.45)
	app.accent_color = Color(0.3, 0.8, 0.9)
	app.weapon_type = "staff"
	app.has_glow = true
	app.glow_color = Color(0.2, 0.7, 0.8, 0.3)
	app.has_electricity = true
	app.electricity_color = Color(0.4, 0.8, 1.0)
	app.hair_style = "flame"
	app.hair_color = Color(0.4, 0.75, 0.95)
	app.hair_size = 1.4
	app.idle_speed = 0.8
	app.attack_style = "magic"
	app.attack_style_override = "electric"


static func _configure_illusionist(app: ChampionAppearance) -> void:
	# Art: Massive wild magenta/pink hair, mischievous look, crystal staff, smoke wisps
	app.body_scale = 0.95
	app.head_radius = 6.5
	app.torso_width = 10.0
	app.torso_height = 15.0
	app.arm_length = 13.0
	app.arm_width = 3.0
	app.leg_length = 15.0
	app.leg_width = 3.5
	app.shoulder_width = 11.0
	app.skin_color = Color(0.6, 0.5, 0.6)
	app.accent_color = Color(0.8, 0.5, 0.9)
	app.weapon_type = "staff"
	app.has_staff_crystal = true
	app.crystal_color = Color(0.8, 0.3, 0.65)
	app.has_smoke_wisps = true
	app.smoke_color = Color(0.6, 0.3, 0.8, 0.5)
	app.has_glow = true
	app.glow_color = Color(0.7, 0.4, 0.9, 0.25)
	app.hair_style = "wild"
	app.hair_color = Color(0.85, 0.25, 0.6)
	app.hair_size = 1.8
	app.idle_speed = 1.0
	app.idle_intensity = 1.1
	app.attack_style = "magic"


static func _configure_dark_wizard(app: ChampionAppearance) -> void:
	# Art: Dark shadow entity, crescent moon eyes, teal energy, non-humanoid, hood/robe
	app.body_scale = 1.05
	app.head_radius = 6.5
	app.torso_width = 11.0
	app.torso_height = 16.0
	app.arm_length = 14.0
	app.arm_width = 3.0
	app.leg_length = 15.0
	app.leg_width = 3.5
	app.shoulder_width = 12.0
	app.skin_color = Color(0.15, 0.12, 0.18)
	app.accent_color = Color(0.1, 0.4, 0.4)
	app.weapon_type = "staff"
	app.has_hood = true
	app.has_robe = true
	app.has_glow = true
	app.glow_color = Color(0.1, 0.3, 0.3, 0.3)
	app.has_dark_butterflies = true
	app.butterfly_color = Color(0.2, 0.0, 0.3)
	app.has_dark_aura = true
	app.dark_aura_color = Color(0.1, 0.0, 0.15, 0.4)
	app.eye_style = "crescent"
	app.eye_glow_color = Color(0.2, 0.8, 0.7, 0.9)
	app.idle_speed = 0.7
	app.idle_intensity = 0.8
	app.attack_style = "magic"


static func _configure_alchemist(app: ChampionAppearance) -> void:
	# Art: Wild spiky neon green hair, white lab coat, round goggles, flasks, backpack
	app.body_scale = 0.95
	app.head_radius = 7.5
	app.torso_width = 11.0
	app.torso_height = 13.0
	app.arm_length = 12.0
	app.arm_width = 3.5
	app.leg_length = 13.0
	app.leg_width = 4.0
	app.shoulder_width = 13.0
	app.skin_color = Color(0.6, 0.55, 0.45)
	app.accent_color = Color(0.3, 0.9, 0.15)
	app.weapon_type = "flask"
	app.dual_wield = true
	app.left_weapon_type = "flask"
	app.has_goggles = true
	app.has_backpack = true
	app.has_potion_smoke = true
	app.potion_smoke_color = Color(0.3, 0.9, 0.15, 0.5)
	app.hair_style = "spiky"
	app.hair_color = Color(0.3, 0.9, 0.15)
	app.hair_size = 1.2
	app.has_coat = true
	app.coat_color = Color(0.9, 0.9, 0.88)
	app.idle_speed = 1.2
	app.idle_intensity = 1.0
	app.attack_style = "ranged"
