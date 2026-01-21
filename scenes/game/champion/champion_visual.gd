extends Node2D
class_name ChampionVisual
## ChampionVisual - Battle Chess-style animated character with HP bar
## Replaces the old ChampionToken with sprite-based visuals and animations

signal animation_finished(anim_name: String)

# Animation states
enum AnimState { IDLE, WALK, ATTACK, HIT, CAST, DEATH }

const TOKEN_SIZE := 52  # Match original token size
const SPRITE_SCALE := 0.12  # Scale for character art to fit in tile

var champion_state: ChampionState
var owner_id: int = 1
var champion_name: String = ""
var current_hp: int = 20
var max_hp: int = 20
var is_selected: bool = false

# Visual components
var _sprite: Sprite2D
var _hp_bar: Control
var _selection_indicator: Node2D
var _shadow: Sprite2D

# Animation state
var _current_anim: AnimState = AnimState.IDLE
var _anim_tween: Tween
var _idle_tween: Tween


func _ready() -> void:
	# Create components if not already created by setup()
	if _sprite == null:
		_create_visual_components()
	_start_idle_animation()


func _create_visual_components() -> void:
	"""Create the visual components for the champion."""
	# Shadow under the character
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	_shadow.modulate = Color(0, 0, 0, 0.3)
	_shadow.position = Vector2(0, 18)
	_shadow.scale = Vector2(SPRITE_SCALE * 0.8, SPRITE_SCALE * 0.3)
	add_child(_shadow)

	# Selection indicator (ring around champion)
	_selection_indicator = Node2D.new()
	_selection_indicator.name = "SelectionIndicator"
	_selection_indicator.visible = false
	add_child(_selection_indicator)
	_selection_indicator.set_script(SelectionRing)

	# Main character sprite
	_sprite = Sprite2D.new()
	_sprite.name = "CharacterSprite"
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position = Vector2(0, -8)  # Offset up slightly
	add_child(_sprite)

	# HP bar at bottom
	_hp_bar = HPBarDrawer.new()
	_hp_bar.name = "HPBar"
	_hp_bar.position = Vector2(-TOKEN_SIZE / 2, TOKEN_SIZE / 2 - 12)
	add_child(_hp_bar)


func setup(champ: ChampionState) -> void:
	"""Initialize with champion data."""
	# Ensure visual components exist (may be called before _ready)
	if _sprite == null:
		_create_visual_components()

	champion_state = champ
	current_hp = champ.current_hp
	max_hp = champ.max_hp
	owner_id = champ.owner_id
	champion_name = champ.champion_name

	# Load character texture
	var texture_path := "res://assets/art/characters/%s.png" % champion_name
	var texture := load(texture_path) as Texture2D
	if texture:
		_sprite.texture = texture
		if _shadow:
			_shadow.texture = texture
	else:
		push_warning("ChampionVisual: Could not load texture for %s" % champion_name)

	# Apply team color tint
	_apply_team_tint()

	# Update HP bar
	_update_hp_bar()


func _apply_team_tint() -> void:
	"""Apply subtle team color tint to character."""
	var team_color := VisualTheme.get_player_color(owner_id)
	# Very subtle tint - mostly preserve original colors
	_sprite.modulate = Color.WHITE.lerp(team_color, 0.15)


func update_hp(hp: int, max_val: int) -> void:
	"""Update HP display."""
	var old_hp := current_hp
	current_hp = hp
	max_hp = max_val
	_update_hp_bar()

	# Flash on damage
	if hp < old_hp:
		_flash_damage()


func _update_hp_bar() -> void:
	"""Update HP bar visual."""
	if _hp_bar and _hp_bar is HPBarDrawer:
		(_hp_bar as HPBarDrawer).set_hp(current_hp, max_hp, owner_id)


func set_selected(selected: bool) -> void:
	"""Set selection state."""
	is_selected = selected
	if _selection_indicator:
		_selection_indicator.visible = selected
		if selected and _selection_indicator.has_method("start_pulse"):
			_selection_indicator.start_pulse()


func _start_idle_animation() -> void:
	"""Start subtle idle breathing animation."""
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()

	_idle_tween = create_tween()
	_idle_tween.set_loops()

	# Subtle breathing/bobbing
	var base_scale := Vector2(SPRITE_SCALE, SPRITE_SCALE)
	var breathe_scale := base_scale * Vector2(1.0, 1.02)

	_idle_tween.tween_property(_sprite, "scale", breathe_scale, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(_sprite, "scale", base_scale, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _flash_damage() -> void:
	"""Flash red when taking damage."""
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()
	_anim_tween.tween_property(_sprite, "modulate", Color.RED, 0.1)
	_anim_tween.tween_callback(_apply_team_tint)


# === Animation Methods ===

func play_walk_animation(direction: Vector2) -> void:
	"""Play walk animation in given direction."""
	_current_anim = AnimState.WALK

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	# Bob up and down while walking
	var base_y := _sprite.position.y
	_anim_tween.tween_property(_sprite, "position:y", base_y - 4, 0.1)
	_anim_tween.tween_property(_sprite, "position:y", base_y, 0.1)
	_anim_tween.tween_property(_sprite, "position:y", base_y - 4, 0.1)
	_anim_tween.tween_property(_sprite, "position:y", base_y, 0.1)
	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("walk")
	)


func play_attack_animation(target_direction: Vector2) -> void:
	"""Play attack animation towards target."""
	_current_anim = AnimState.ATTACK

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	var original_pos := _sprite.position
	var lunge_offset := target_direction.normalized() * 12
	var lunge_pos := original_pos + lunge_offset

	# Lunge forward
	_anim_tween.tween_property(_sprite, "position", lunge_pos, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Return
	_anim_tween.tween_property(_sprite, "position", original_pos, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("attack")
	)


func play_hit_animation() -> void:
	"""Play hit reaction animation."""
	_current_anim = AnimState.HIT

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	var original_pos := _sprite.position

	# Shake and flash
	_anim_tween.tween_property(_sprite, "modulate", Color.RED, 0.05)
	_anim_tween.tween_property(_sprite, "position:x", original_pos.x - 4, 0.05)
	_anim_tween.tween_property(_sprite, "position:x", original_pos.x + 4, 0.05)
	_anim_tween.tween_property(_sprite, "position:x", original_pos.x - 2, 0.05)
	_anim_tween.tween_property(_sprite, "position:x", original_pos.x, 0.05)
	_anim_tween.tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("hit")
	)


func play_cast_animation() -> void:
	"""Play spell casting animation."""
	_current_anim = AnimState.CAST

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	var base_scale := Vector2(SPRITE_SCALE, SPRITE_SCALE)
	var cast_scale := base_scale * 1.1

	# Glow and scale up briefly
	_anim_tween.tween_property(_sprite, "modulate", Color(1.3, 1.3, 1.5), 0.15)
	_anim_tween.parallel().tween_property(_sprite, "scale", cast_scale, 0.15)
	_anim_tween.tween_property(_sprite, "scale", base_scale, 0.2)
	_anim_tween.parallel().tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("cast")
	)


func play_death_animation() -> void:
	"""Play death animation."""
	_current_anim = AnimState.DEATH

	# Stop idle animation
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	# Fall and fade out
	_anim_tween.tween_property(_sprite, "rotation", deg_to_rad(90), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_anim_tween.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.5).set_delay(0.2)
	_anim_tween.parallel().tween_property(_hp_bar, "modulate:a", 0.0, 0.3)
	_anim_tween.parallel().tween_property(_shadow, "modulate:a", 0.0, 0.3)
	_anim_tween.tween_callback(func():
		animation_finished.emit("death")
	)


func play_heal_animation() -> void:
	"""Play healing effect animation."""
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	# Green glow
	_anim_tween.tween_property(_sprite, "modulate", Color(0.5, 1.5, 0.5), 0.2)
	_anim_tween.tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func(): animation_finished.emit("heal"))


func play_buff_animation() -> void:
	"""Play buff applied animation."""
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	var base_scale := Vector2(SPRITE_SCALE, SPRITE_SCALE)

	# Brief cyan glow and scale
	_anim_tween.tween_property(_sprite, "modulate", Color(0.5, 1.2, 1.5), 0.15)
	_anim_tween.parallel().tween_property(_sprite, "scale", base_scale * 1.05, 0.15)
	_anim_tween.tween_property(_sprite, "scale", base_scale, 0.15)
	_anim_tween.parallel().tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func(): animation_finished.emit("buff"))


func play_debuff_animation() -> void:
	"""Play debuff applied animation."""
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	var base_scale := Vector2(SPRITE_SCALE, SPRITE_SCALE)

	# Purple flash and shrink
	_anim_tween.tween_property(_sprite, "modulate", Color(1.2, 0.5, 1.2), 0.15)
	_anim_tween.parallel().tween_property(_sprite, "scale", base_scale * 0.95, 0.15)
	_anim_tween.tween_property(_sprite, "scale", base_scale, 0.15)
	_anim_tween.parallel().tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func(): animation_finished.emit("debuff"))


# === Inner Classes ===

class HPBarDrawer extends Control:
	"""Draws the HP bar below the champion."""
	var _current_hp: int = 20
	var _max_hp: int = 20
	var _owner_id: int = 1

	func _init() -> void:
		size = Vector2(TOKEN_SIZE, 10)
		custom_minimum_size = size

	func set_hp(hp: int, max_val: int, owner: int) -> void:
		_current_hp = hp
		_max_hp = max_val
		_owner_id = owner
		queue_redraw()

	func _draw() -> void:
		var bar_width := size.x
		var bar_height := 6.0
		var bar_y := 2.0

		# Background
		draw_rect(Rect2(0, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BG)

		# HP fill
		var hp_pct := float(_current_hp) / float(_max_hp) if _max_hp > 0 else 0.0
		var hp_color := VisualTheme.get_hp_color(_current_hp, _max_hp)
		draw_rect(Rect2(0, bar_y, bar_width * hp_pct, bar_height), hp_color)

		# Border
		draw_rect(Rect2(0, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BORDER, false, 1.0)

		# HP text
		var font := ThemeDB.fallback_font
		var hp_text := str(_current_hp)
		draw_string(font, Vector2(bar_width / 2 - 4, bar_y + 5), hp_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)


class SelectionRing extends Node2D:
	"""Animated selection ring around champion."""
	var _pulse_tween: Tween
	var _radius: float = 30.0
	var _alpha: float = 0.8

	func _draw() -> void:
		var color := VisualTheme.HIGHLIGHT_SELECTED_BORDER
		color.a = _alpha
		draw_arc(Vector2.ZERO, _radius, 0, TAU, 32, color, 3.0, true)

	func start_pulse() -> void:
		if _pulse_tween and _pulse_tween.is_valid():
			_pulse_tween.kill()

		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(self, "_alpha", 0.4, 0.5)
		_pulse_tween.tween_property(self, "_alpha", 0.8, 0.5)

	func _process(_delta: float) -> void:
		queue_redraw()
