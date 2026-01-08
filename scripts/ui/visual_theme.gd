extends Node
class_name VisualTheme
## VisualTheme - Central repository for all visual styling constants
## Use this for consistent colors, sizes, and styling across the game

# === CHAMPION COLORS ===
# Each champion has a primary and secondary color for gradients
const CHAMPION_COLORS := {
	"Brute": { "primary": Color(0.6, 0.35, 0.15), "secondary": Color(0.8, 0.5, 0.2) },
	"Ranger": { "primary": Color(0.15, 0.45, 0.2), "secondary": Color(0.3, 0.6, 0.35) },
	"Beast": { "primary": Color(0.45, 0.35, 0.2), "secondary": Color(0.6, 0.5, 0.3) },
	"Redeemer": { "primary": Color(0.7, 0.6, 0.3), "secondary": Color(0.9, 0.85, 0.6) },
	"Confessor": { "primary": Color(0.35, 0.15, 0.45), "secondary": Color(0.5, 0.25, 0.6) },
	"Barbarian": { "primary": Color(0.6, 0.15, 0.1), "secondary": Color(0.8, 0.25, 0.15) },
	"Burglar": { "primary": Color(0.25, 0.25, 0.3), "secondary": Color(0.4, 0.4, 0.45) },
	"Berserker": { "primary": Color(0.5, 0.1, 0.15), "secondary": Color(0.7, 0.2, 0.2) },
	"Shaman": { "primary": Color(0.15, 0.4, 0.5), "secondary": Color(0.3, 0.6, 0.7) },
	"Illusionist": { "primary": Color(0.4, 0.2, 0.5), "secondary": Color(0.6, 0.35, 0.7) },
	"DarkWizard": { "primary": Color(0.2, 0.1, 0.3), "secondary": Color(0.35, 0.2, 0.45) },
	"Alchemist": { "primary": Color(0.3, 0.5, 0.2), "secondary": Color(0.5, 0.7, 0.3) }
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
const CARD_WIDTH := 120
const CARD_HEIGHT := 160
const CARD_BORDER := 2
const TILE_SIZE := 64
const CHAMPION_TOKEN_SIZE := 52
const MANA_GEM_SIZE := 20
const HP_BAR_HEIGHT := 6

# === FONT SIZES ===
const FONT_CARD_NAME := 12
const FONT_CARD_COST := 14
const FONT_CARD_DESC := 9
const FONT_CARD_TYPE := 8
const FONT_HP := 11
const FONT_TITLE := 14

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
