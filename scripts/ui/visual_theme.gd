extends Node
class_name VisualTheme
## VisualTheme - Central repository for all visual styling constants
## Use this for consistent colors, sizes, and styling across the game

# === CHAMPION COLORS ===
# Each champion has a primary and secondary color for gradients
const CHAMPION_COLORS := {
	"Brute": { "primary": Color(0.25, 0.55, 0.15), "secondary": Color(0.35, 0.45, 0.2) },
	"Ranger": { "primary": Color(0.45, 0.32, 0.18), "secondary": Color(0.55, 0.42, 0.25) },
	"Beast": { "primary": Color(0.2, 0.4, 0.15), "secondary": Color(0.3, 0.5, 0.25) },
	"Redeemer": { "primary": Color(0.85, 0.8, 0.3), "secondary": Color(0.95, 0.9, 0.5) },
	"Confessor": { "primary": Color(0.1, 0.12, 0.3), "secondary": Color(0.15, 0.18, 0.4) },
	"Barbarian": { "primary": Color(0.85, 0.5, 0.1), "secondary": Color(0.7, 0.35, 0.1) },
	"Burglar": { "primary": Color(0.35, 0.15, 0.45), "secondary": Color(0.25, 0.1, 0.35) },
	"Berserker": { "primary": Color(0.8, 0.15, 0.1), "secondary": Color(0.6, 0.1, 0.08) },
	"Shaman": { "primary": Color(0.5, 0.75, 0.9), "secondary": Color(0.35, 0.6, 0.8) },
	"Illusionist": { "primary": Color(0.8, 0.2, 0.55), "secondary": Color(0.6, 0.15, 0.45) },
	"DarkWizard": { "primary": Color(0.08, 0.08, 0.1), "secondary": Color(0.1, 0.3, 0.3) },
	"Alchemist": { "primary": Color(0.3, 0.9, 0.15), "secondary": Color(0.2, 0.7, 0.1) }
}

# === CARD TYPE COLORS ===
const CARD_TYPE_COLORS := {
	"Action": { "primary": Color(0.2, 0.35, 0.6), "secondary": Color(0.3, 0.5, 0.75), "border": Color(0.15, 0.25, 0.45) },
	"Response": { "primary": Color(0.55, 0.45, 0.2), "secondary": Color(0.7, 0.6, 0.3), "border": Color(0.4, 0.35, 0.15) },
	"Equipment": { "primary": Color(0.3, 0.5, 0.3), "secondary": Color(0.45, 0.65, 0.45), "border": Color(0.2, 0.35, 0.2) }
}

# === MANA COST COLORS ===
const MANA_COST_COLORS := {
	0: Color(0.5, 0.5, 0.5),   # Gray
	1: Color(0.3, 0.5, 0.8),   # Blue
	2: Color(0.3, 0.7, 0.4),   # Green
	3: Color(0.8, 0.7, 0.2),   # Yellow/Gold
	4: Color(0.8, 0.3, 0.3)    # Red
}

# === CARD BACK DESIGN ===
const CARD_BACK := {
	"primary": Color(0.15, 0.12, 0.2),
	"secondary": Color(0.25, 0.2, 0.3),
	"accent": Color(0.7, 0.55, 0.2),
	"border": Color(0.5, 0.4, 0.15)
}

# === PLAYER TEAM COLORS ===
const PLAYER1_COLOR := Color(0.2, 0.5, 0.85)
const PLAYER1_DARK := Color(0.1, 0.3, 0.5)
const PLAYER2_COLOR := Color(0.85, 0.3, 0.25)
const PLAYER2_DARK := Color(0.5, 0.15, 0.12)

# === BOARD COLORS ===
const TILE_EMPTY := Color(0.22, 0.25, 0.28)
const TILE_EMPTY_ALT := Color(0.2, 0.23, 0.26)  # Checkerboard pattern
const TILE_WALL := Color(0.12, 0.13, 0.15)
const TILE_WALL_ACCENT := Color(0.18, 0.19, 0.22)
const TILE_PIT := Color(0.05, 0.03, 0.08)
const TILE_PIT_EDGE := Color(0.15, 0.1, 0.2)
const TILE_BORDER := Color(0.1, 0.1, 0.12)

# === HIGHLIGHT COLORS ===
const HIGHLIGHT_MOVE := Color(0.2, 0.7, 0.3, 0.4)
const HIGHLIGHT_MOVE_BORDER := Color(0.3, 0.9, 0.4, 0.8)
const HIGHLIGHT_ATTACK := Color(0.8, 0.2, 0.2, 0.4)
const HIGHLIGHT_ATTACK_BORDER := Color(1.0, 0.3, 0.3, 0.8)
const HIGHLIGHT_CAST := Color(0.3, 0.3, 0.8, 0.4)
const HIGHLIGHT_CAST_BORDER := Color(0.4, 0.4, 1.0, 0.8)
const HIGHLIGHT_SELECTED := Color(0.9, 0.75, 0.2, 0.5)
const HIGHLIGHT_SELECTED_BORDER := Color(1.0, 0.85, 0.3, 0.9)
const HIGHLIGHT_HOVER := Color(1.0, 1.0, 1.0, 0.15)

# === UI COLORS ===
const UI_PANEL_BG := Color(0.12, 0.12, 0.15, 0.95)
const UI_PANEL_BORDER := Color(0.3, 0.3, 0.35)
const UI_ACCENT := Color(0.7, 0.55, 0.2)
const UI_TEXT := Color(0.9, 0.9, 0.9)
const UI_TEXT_DIM := Color(0.6, 0.6, 0.65)
const UI_TEXT_HIGHLIGHT := Color(1.0, 0.9, 0.5)

# === MANA GEM COLORS ===
const MANA_GEM_FILLED := Color(0.3, 0.5, 0.9)
const MANA_GEM_EMPTY := Color(0.2, 0.2, 0.25)
const MANA_GEM_BORDER := Color(0.4, 0.6, 1.0)

# === HP BAR COLORS ===
const HP_HIGH := Color(0.3, 0.8, 0.3)      # > 50%
const HP_MEDIUM := Color(0.9, 0.8, 0.2)    # 25-50%
const HP_LOW := Color(0.9, 0.3, 0.2)       # < 25%
const HP_BAR_BG := Color(0.15, 0.15, 0.18)
const HP_BAR_BORDER := Color(0.3, 0.3, 0.35)

# === SIZES ===
const CARD_WIDTH := 140
const CARD_HEIGHT := 185
const CARD_BORDER := 2
const TILE_SIZE := 64
const CHAMPION_TOKEN_SIZE := 52
const MANA_GEM_SIZE := 20
const HP_BAR_HEIGHT := 6

# === FONT SIZES (Enhanced for better hierarchy) ===
const FONT_TITLE_LARGE := 18    # Main titles
const FONT_TITLE := 14          # Section headers
const FONT_SUBTITLE := 12       # Subsections
const FONT_BODY := 10           # Normal text
const FONT_SMALL := 9           # Helper text

# Card-specific
const FONT_CARD_NAME := 13      # Increased for readability
const FONT_CARD_COST := 16      # Increased for visibility
const FONT_CARD_DESC := 10      # Increased for readability
const FONT_CARD_TYPE := 9       # Increased slightly
const FONT_HP := 11
const FONT_STAT_LABEL := 9
const FONT_STAT_VALUE := 14

# === SHADOW & DEPTH SETTINGS ===
const SHADOW_COLOR := Color(0, 0, 0, 0.4)
const SHADOW_SOFT := Color(0, 0, 0, 0.25)
const SHADOW_HARD := Color(0, 0, 0, 0.6)

# Shadow offsets for different UI elements
const SHADOW_OFFSET_TINY := Vector2(1, 1)     # Text shadows
const SHADOW_OFFSET_SMALL := Vector2(2, 2)    # Mana gems, small elements
const SHADOW_OFFSET_MEDIUM := Vector2(3, 3)   # Cards, buttons
const SHADOW_OFFSET_LARGE := Vector2(4, 4)    # Panels, portraits
const SHADOW_OFFSET_XLARGE := Vector2(6, 6)   # HUD panels, floating elements

# Glow settings
const GLOW_SOFT := Color(1.0, 1.0, 1.0, 0.15)
const GLOW_MEDIUM := Color(1.0, 1.0, 1.0, 0.25)
const GLOW_STRONG := Color(1.0, 1.0, 1.0, 0.4)
const GLOW_RADIUS_SMALL := 4.0
const GLOW_RADIUS_MEDIUM := 6.0
const GLOW_RADIUS_LARGE := 8.0

# === GRADIENT DEFINITIONS ===
const GRADIENT_PANEL_TOP := Color(0.14, 0.14, 0.18, 0.95)
const GRADIENT_PANEL_BOTTOM := Color(0.08, 0.08, 0.12, 0.95)

const GRADIENT_CARD_OVERLAY_TOP := Color(0.12, 0.12, 0.15, 0.9)
const GRADIENT_CARD_OVERLAY_BOTTOM := Color(0.08, 0.08, 0.1, 0.85)

const GRADIENT_MANA_FILLED_TOP := Color(0.5, 0.7, 1.0)
const GRADIENT_MANA_FILLED_BOTTOM := Color(0.2, 0.4, 0.8)
const GRADIENT_MANA_EMPTY_TOP := Color(0.25, 0.25, 0.3)
const GRADIENT_MANA_EMPTY_BOTTOM := Color(0.15, 0.15, 0.18)

const GRADIENT_HP_HIGH_TOP := Color(0.4, 0.9, 0.4)
const GRADIENT_HP_HIGH_BOTTOM := Color(0.2, 0.7, 0.3)
const GRADIENT_HP_MEDIUM_TOP := Color(1.0, 0.9, 0.3)
const GRADIENT_HP_MEDIUM_BOTTOM := Color(0.8, 0.7, 0.15)
const GRADIENT_HP_LOW_TOP := Color(1.0, 0.4, 0.3)
const GRADIENT_HP_LOW_BOTTOM := Color(0.8, 0.2, 0.2)

# === BEVEL & INSET EFFECTS ===
const BEVEL_HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.2)  # Top/left edge
const BEVEL_SHADOW := Color(0, 0, 0, 0.3)           # Bottom/right edge
const BEVEL_WIDTH := 1.5

const INSET_HIGHLIGHT := Color(0, 0, 0, 0.25)       # Top/left (inverted)
const INSET_SHADOW := Color(1.0, 1.0, 1.0, 0.1)     # Bottom/right (inverted)

# === SPACING & MARGINS ===
const SPACING_TINY := 2
const SPACING_SMALL := 4
const SPACING_MEDIUM := 8
const SPACING_LARGE := 12
const SPACING_XLARGE := 16

const MARGIN_TINY := 2
const MARGIN_SMALL := 4
const MARGIN_MEDIUM := 8
const MARGIN_LARGE := 12
const MARGIN_XLARGE := 16

const PADDING_CARD := 6         # Padding inside cards
const PADDING_PANEL := 12       # Padding inside panels
const PADDING_BUTTON := 8       # Padding inside buttons

# === ANIMATION & EFFECTS ===
const PULSE_SPEED := 2.0        # Speed of pulse animations
const PULSE_MIN_ALPHA := 0.5    # Minimum alpha in pulse
const PULSE_MAX_ALPHA := 1.0    # Maximum alpha in pulse

const HOVER_SCALE := 1.02       # Scale factor on hover
const HOVER_GLOW_ALPHA := 0.2   # Glow alpha on hover
const HOVER_DURATION := 0.15    # Tween duration for hover

# === CHAMPION SYMBOLS ===
# Unicode symbols to represent each champion on cards
const CHAMPION_SYMBOLS := {
	"Brute": "\u2660",        # Spade
	"Ranger": "\u2665",       # Heart (will use arrows)
	"Beast": "\u2666",        # Diamond
	"Redeemer": "\u2606",     # Star
	"Confessor": "\u2620",    # Skull
	"Barbarian": "\u2694",    # Crossed swords
	"Burglar": "\u2605",      # Filled star
	"Berserker": "\u26A1",    # Lightning
	"Shaman": "\u2604",       # Comet
	"Illusionist": "\u2727",  # Sparkle
	"DarkWizard": "\u263D",   # Moon
	"Alchemist": "\u2697"     # Alembic
}

# === HELPER FUNCTIONS ===

static func get_champion_colors(champion_name: String) -> Dictionary:
	"""Get color palette for a champion."""
	if CHAMPION_COLORS.has(champion_name):
		return CHAMPION_COLORS[champion_name]
	return { "primary": Color(0.4, 0.4, 0.4), "secondary": Color(0.5, 0.5, 0.5) }


static func get_card_type_colors(card_type: String) -> Dictionary:
	"""Get color palette for a card type."""
	if CARD_TYPE_COLORS.has(card_type):
		return CARD_TYPE_COLORS[card_type]
	return CARD_TYPE_COLORS["Action"]


static func get_mana_cost_color(cost: int) -> Color:
	"""Get color for mana cost display."""
	cost = clampi(cost, 0, 4)
	return MANA_COST_COLORS[cost]


static func get_hp_color(current: int, max_hp: int) -> Color:
	"""Get HP bar color based on percentage."""
	var pct := float(current) / float(max_hp) if max_hp > 0 else 0.0
	if pct > 0.5:
		return HP_HIGH
	elif pct > 0.25:
		return HP_MEDIUM
	else:
		return HP_LOW


static func get_player_color(player_id: int) -> Color:
	"""Get primary color for a player."""
	return PLAYER1_COLOR if player_id == 1 else PLAYER2_COLOR


static func get_player_dark_color(player_id: int) -> Color:
	"""Get dark accent color for a player."""
	return PLAYER1_DARK if player_id == 1 else PLAYER2_DARK


static func get_champion_symbol(champion_name: String) -> String:
	"""Get Unicode symbol for a champion."""
	if CHAMPION_SYMBOLS.has(champion_name):
		return CHAMPION_SYMBOLS[champion_name]
	return "\u2022"  # Bullet as fallback


static func create_panel_stylebox(bg_color: Color = UI_PANEL_BG, border_color: Color = UI_PANEL_BORDER, border_width: int = 1) -> StyleBoxFlat:
	"""Create a styled panel StyleBox."""
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


static func create_card_stylebox(card_type: String, is_playable: bool = true) -> StyleBoxFlat:
	"""Create a styled card background StyleBox."""
	var colors := get_card_type_colors(card_type)
	var style := StyleBoxFlat.new()

	if is_playable:
		style.bg_color = colors["primary"]
		style.border_color = colors["border"]
	else:
		style.bg_color = colors["primary"].lerp(Color(0.3, 0.3, 0.3), 0.6)
		style.border_color = colors["border"].lerp(Color(0.2, 0.2, 0.2), 0.6)

	style.set_border_width_all(CARD_BORDER)
	style.set_corner_radius_all(6)
	return style


# === DRAWING HELPER FUNCTIONS ===

static func draw_vertical_gradient(control: Control, rect: Rect2, top_color: Color, bottom_color: Color) -> void:
	"""Draw a vertical gradient rectangle using line drawing."""
	var steps := int(rect.size.y)
	for i in range(steps):
		var t := float(i) / float(maxi(steps - 1, 1))
		var color := top_color.lerp(bottom_color, t)
		var y := rect.position.y + i
		control.draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x + rect.size.x, y), color, 1.0)


static func draw_bevel(control: Control, rect: Rect2, width: float = BEVEL_WIDTH,
					   highlight: Color = BEVEL_HIGHLIGHT, shadow: Color = BEVEL_SHADOW) -> void:
	"""Draw beveled edges (3D raised effect)."""
	# Top edge (highlight)
	control.draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), highlight, width)
	# Left edge (highlight)
	control.draw_line(rect.position, rect.position + Vector2(0, rect.size.y), highlight, width)
	# Bottom edge (shadow)
	control.draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, shadow, width)
	# Right edge (shadow)
	control.draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, shadow, width)


static func draw_inset(control: Control, rect: Rect2, width: float = BEVEL_WIDTH) -> void:
	"""Draw inset edges (3D recessed effect)."""
	draw_bevel(control, rect, width, INSET_HIGHLIGHT, INSET_SHADOW)


static func draw_text_shadow(control: Control, font: Font, pos: Vector2, text: String,
							 font_size: int, color: Color, shadow_offset: Vector2 = SHADOW_OFFSET_TINY,
							 shadow_color: Color = Color(0, 0, 0, 0.6), alignment: int = HORIZONTAL_ALIGNMENT_LEFT,
							 width: int = -1) -> void:
	"""Draw text with a drop shadow for better readability."""
	# Shadow
	control.draw_string(font, pos + shadow_offset, text, alignment, width, font_size, shadow_color)
	# Main text
	control.draw_string(font, pos, text, alignment, width, font_size, color)


static func get_hp_gradient_colors(pct: float) -> Array:
	"""Get gradient colors for HP bar based on percentage. Returns [top_color, bottom_color]."""
	if pct > 0.5:
		return [GRADIENT_HP_HIGH_TOP, GRADIENT_HP_HIGH_BOTTOM]
	elif pct > 0.25:
		return [GRADIENT_HP_MEDIUM_TOP, GRADIENT_HP_MEDIUM_BOTTOM]
	else:
		return [GRADIENT_HP_LOW_TOP, GRADIENT_HP_LOW_BOTTOM]


# =============================================================
# === VISUAL POLISH CONSTANTS =================================
# =============================================================

# === STONE TILE SETTINGS ===
const TILE_DEPTH_EMPTY := 6        # Pixel depth for raised stone slabs
const TILE_DEPTH_WALL := 10        # Pixel depth for tall wall blocks
const TILE_STONE_LIGHT := Color(0.32, 0.34, 0.36)   # Light stone checkerboard
const TILE_STONE_DARK := Color(0.24, 0.26, 0.28)    # Dark stone checkerboard
const TILE_STONE_GRAIN := Color(1.0, 1.0, 1.0, 0.04) # Stone grain overlay
const TILE_SPECULAR := Color(1.0, 1.0, 1.0, 0.12)   # Specular highlight top-left
const TILE_AO_GAP := Color(0, 0, 0, 0.25)            # Ambient occlusion in gaps
const TILE_WALL_TOP := Color(0.18, 0.19, 0.22)       # Wall top face
const TILE_WALL_MORTAR := Color(0.1, 0.1, 0.12, 0.6) # Mortar lines
const TILE_WALL_SIDE := Color(0.1, 0.1, 0.13)        # Wall side face (depth)
const TILE_PIT_VOID := Color(0.02, 0.01, 0.04)       # Pit void center
const TILE_PIT_RIM := Color(0.15, 0.12, 0.18)        # Crumbling pit rim
const TILE_PIT_GLOW := Color(0.5, 0.2, 0.7, 0.35)   # Purple glow from pit
const TILE_LIGHTING_BRIGHT := 0.08  # Brightness boost for top-left tiles
const TILE_LIGHTING_DIM := -0.06    # Darkness for bottom-right tiles

# === BOARD FRAME ===
const FRAME_WOOD := Color(0.12, 0.09, 0.06)          # Dark wood gradient base
const FRAME_WOOD_LIGHT := Color(0.18, 0.14, 0.1)     # Wood gradient top
const FRAME_GOLD_TRIM := Color(0.75, 0.6, 0.2)       # Gold trim line
const FRAME_GOLD_DIM := Color(0.5, 0.4, 0.15)        # Dim gold for inner trim
const FRAME_DIAMOND := Color(0.65, 0.5, 0.18)        # Corner diamond ornaments

# === VFX PARTICLE COLORS ===
const VFX_DUST := Color(0.55, 0.45, 0.3, 0.6)       # Movement dust trail
const VFX_SPARK := Color(1.0, 0.9, 0.5, 0.9)        # Melee impact sparks
const VFX_MAGIC := Color(0.4, 0.5, 1.0, 0.8)        # Magic swirl default
const VFX_CAST := Color(1.0, 1.0, 0.7, 0.7)         # Cast shimmer sparkles
const VFX_DEATH_RING := Color(0.15, 0.05, 0.2, 0.8)  # Death dark ring
const VFX_DEATH_SOUL := Color(0.6, 0.8, 1.0, 0.5)   # Death soul wisps
const VFX_HEAL := Color(0.3, 1.0, 0.4, 0.7)         # Heal sparkles
const VFX_HEAL_GOLD := Color(1.0, 0.9, 0.4, 0.6)    # Heal golden sparkles
const VFX_AMBIENT := Color(1.0, 1.0, 1.0, 0.08)     # Ambient dust motes
const VFX_PIT_SMOKE := Color(0.4, 0.15, 0.6, 0.3)   # Purple pit wisps
const VFX_RANGED := Color(0.9, 0.7, 0.3, 0.8)       # Ranged trail dots
const VFX_MAX_PARTICLES := 200                        # Global particle cap

# === ENHANCED COMBAT TEXT ===
const COMBAT_FONT_DAMAGE := 28     # Bigger damage numbers
const COMBAT_FONT_CRIT := 36       # Critical hit font size
const COMBAT_FONT_HEAL := 24       # Heal number size
const COMBAT_IMPACT_SCALE := 1.8   # Impact pop scale
const COMBAT_SHAKE_THRESHOLD := 3  # Damage amount to trigger shake
const COMBAT_FLASH_THRESHOLD := 5  # Damage amount for red flash

# === ENHANCED CARD HOVER ===
const CARD_HOVER_LIFT := 30        # Pixels to lift on hover
const CARD_HOVER_SCALE := 1.05     # Scale on hover
const CARD_HOVER_TILT := 2.0       # Degrees of tilt on hover
const CARD_GLOW_LAYERS := 4        # Layers for golden hover glow
const CARD_PLAYABLE_PULSE_MIN := 0.15  # Min alpha for playable pulse
const CARD_PLAYABLE_PULSE_MAX := 0.35  # Max alpha for playable pulse

# === HP BAR ENHANCED ===
const HP_BAR_HEIGHT_ENHANCED := 22  # Taller HP bars
const HP_TICK_INTERVAL := 5         # HP tick mark every N points
const HP_DANGER_THRESHOLD := 0.2    # HP % for danger pulse

# === TURN BANNER ===
const TURN_BANNER_FONT := 36       # Dramatic turn banner size
const TURN_BANNER_HEIGHT := 80     # Banner height in pixels

# === RESPONSE SLOT PULSE ===
const RESPONSE_PULSE_COLOR := Color(0.9, 0.5, 0.1, 0.6)  # Orange pulse
const RESPONSE_PULSE_SPEED := 3.0   # Pulse speed when active

# === VIGNETTE ===
const VIGNETTE_COLOR := Color(0, 0, 0, 0.4)  # Dark edge vignette
const VIGNETTE_INNER_RADIUS := 0.35  # Where vignette starts (0-1)

# === SCREEN FLASH ===
const FLASH_ACTION := Color(1.0, 1.0, 0.8, 0.25)   # Action card flash
const FLASH_RESPONSE := Color(0.3, 0.6, 1.0, 0.2)  # Response card flash (cool blue)
const FLASH_EQUIPMENT := Color(0.8, 0.8, 0.9, 0.18) # Equipment card flash (silver)
const FLASH_DAMAGE := Color(1.0, 0.2, 0.1, 0.2)    # Heavy damage flash
const FLASH_HEAL := Color(0.2, 1.0, 0.4, 0.15)     # Heal flash

# === CARD CAST VFX (Type-Specific) ===
# Energy beam: champion-colored arc from caster to target (Action cards)
const ENERGY_BEAM_WIDTH := 3.0            # Base beam width
const ENERGY_BEAM_SEGMENTS := 10          # Segments for sine wobble
const ENERGY_BEAM_WOBBLE := 8.0           # Amplitude of wobble
const ENERGY_BEAM_SPEED := 12.0           # Wobble frequency
const ENERGY_BEAM_LIFETIME := 0.45        # How long beam persists
const ENERGY_BEAM_GLOW := Color(1.0, 1.0, 1.0, 0.3) # Core glow overlay

# Cast burst: radial particle explosion (Action cards)
const VFX_CAST_BURST_COUNT := 18          # Particles in burst
const VFX_CAST_BURST_SPEED := 80.0        # Outward speed
const VFX_CAST_BURST_LIFETIME := 0.5      # Particle duration

# Shield flash: expanding protective ring (Response cards)
const VFX_SHIELD_COLOR := Color(0.3, 0.6, 1.0, 0.7)  # Blue shield
const VFX_SHIELD_EXPAND_SPEED := 60.0      # Ring expansion rate
const VFX_SHIELD_LIFETIME := 0.35          # Quick flash

# Equipment glow: metallic sparkle attach (Equipment cards)
const VFX_EQUIP_COLOR := Color(0.85, 0.85, 0.95, 0.8) # Silver metallic
const VFX_EQUIP_GOLD := Color(1.0, 0.9, 0.5, 0.7)     # Gold accent
const VFX_EQUIP_LIFETIME := 0.6            # Attach duration

# Card fly trail colors per type
const TRAIL_ACTION := Color(1.0, 0.95, 0.6, 0.15)    # Gold trails
const TRAIL_RESPONSE := Color(0.4, 0.6, 1.0, 0.12)   # Blue trails
const TRAIL_EQUIPMENT := Color(0.8, 0.8, 0.9, 0.12)   # Silver trails

# === ARENA CROWD ===
const CROWD_SILHOUETTE := Color(0.06, 0.05, 0.08)     # Dark crowd body
const CROWD_SILHOUETTE_LIGHT := Color(0.1, 0.08, 0.12) # Lighter crowd variant
const CROWD_HEAD_SIZE := 5.0                # Head circle radius
const CROWD_BODY_WIDTH := 9.0              # Shoulder width
const CROWD_BODY_HEIGHT := 12.0            # Body height below head
const CROWD_ROWS := 6                       # Depth rows of spectators (colosseum)
const CROWD_PER_SIDE := 18                  # Spectators per side per row
const CROWD_SWAY_SPEED := 1.2              # Idle sway frequency
const CROWD_SWAY_AMOUNT := 1.8             # Idle sway pixels
const CROWD_REACT_INTENSITY := 6.0         # Reaction movement pixels
const CROWD_REACT_DURATION := 1.0          # Reaction animation length
const CROWD_SHOUT_CHANCE := 0.4            # Chance to show speech bubble on reaction

# Torch/brazier settings
const TORCH_COLOR := Color(1.0, 0.7, 0.2, 0.5)       # Warm fire glow
const TORCH_FLICKER_SPEED := 4.0            # Flicker frequency
const TORCH_RADIUS := 16.0                  # Glow radius
const TORCH_POSITIONS := 4                   # Corner braziers

# === SOUND PATHS ===
const SFX_HIT := ["res://assets/sounds/hit.mp3", "res://assets/sounds/hit1.mp3", "res://assets/sounds/hit2.mp3"]
const SFX_MAGIC := ["res://assets/sounds/magic.mp3", "res://assets/sounds/magic1.mp3", "res://assets/sounds/magic2.mp3"]
const SFX_SPELL_CAST := "res://assets/sounds/spellcast-46164.mp3"
const SFX_MAGIC_IMPACT := "res://assets/sounds/elemental-magic-spell-impact-outgoing-228342 (1).mp3"
const SFX_DEATH := "res://assets/sounds/death.mp3"
const SFX_PAIN := "res://assets/sounds/male-grunting-in-pain-45746.mp3"
const SFX_HEAL := "res://assets/sounds/magic-ascend-3-259526.mp3"
const SFX_VICTORY := "res://assets/sounds/yay.mp3"
const MUSIC_BATTLE := "res://assets/sounds/the-ballad-of-blades-audio-logo-253770.mp3"
const MUSIC_AMBIENT := "res://assets/sounds/relaxing-guitar-loop-v5-245859.mp3"

# === HELPER: Tile lighting modifier ===
static func get_tile_lighting(x: int, y: int, board_size: int = 10) -> float:
	"""Get per-tile brightness modifier. Top-left brighter, bottom-right darker."""
	var nx := float(x) / float(board_size - 1)  # 0..1
	var ny := float(y) / float(board_size - 1)
	var t := (nx + ny) / 2.0  # 0 = top-left, 1 = bottom-right
	return lerpf(TILE_LIGHTING_BRIGHT, TILE_LIGHTING_DIM, t)


static func apply_lighting(color: Color, lighting: float) -> Color:
	"""Apply lighting modifier to a color."""
	if lighting > 0:
		return color.lerp(Color.WHITE, lighting)
	else:
		return color.lerp(Color.BLACK, -lighting)
