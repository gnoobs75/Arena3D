@tool
class_name ChampionData
extends Resource
## ChampionData - Resource class for champion definitions
## Stores base stats and metadata for a champion type

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var style: String = ""

@export_group("Base Stats")
@export var base_range: int = 1
@export var base_power: int = 1
@export var base_movement: int = 3
@export var starting_hp: int = 20

@export_group("Visuals")
@export var portrait: Texture2D
@export var model_scene: PackedScene  # 3D model for Battle Chess view


static func from_dict(data: Dictionary) -> ChampionData:
	"""Create ChampionData from dictionary (e.g., from JSON)."""
	var champion := ChampionData.new()
	champion.id = data.get("id", "")
	champion.display_name = data.get("display_name", "")
	champion.description = data.get("description", "")
	champion.style = data.get("style", "")
	champion.base_range = data.get("range", 1)
	champion.base_power = data.get("power", 1)
	champion.base_movement = data.get("movement", 3)
	champion.starting_hp = data.get("starting_hp", 20)
	return champion


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"style": style,
		"range": base_range,
		"power": base_power,
		"movement": base_movement,
		"starting_hp": starting_hp
	}


func _to_string() -> String:
	return "ChampionData<%s R:%d P:%d M:%d>" % [display_name, base_range, base_power, base_movement]
