extends Node
## AudioManager - Handles all audio playback for the game
## Manages music, sound effects, and audio settings

# Audio buses
const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"

# Audio players
var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer

# Settings
var _master_volume: float = 1.0
var _music_volume: float = 0.8
var _sfx_volume: float = 1.0
var _ui_volume: float = 1.0
var _music_enabled: bool = true
var _sfx_enabled: bool = true

# Pooling
const MAX_SFX_PLAYERS := 8
var _current_sfx_index := 0

# Loaded sounds cache
var _sound_cache: Dictionary = {}


func _ready() -> void:
	_setup_audio_players()


func _setup_audio_players() -> void:
	# Music player
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)

	# UI player
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = UI_BUS
	add_child(_ui_player)

	# SFX player pool
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_sfx_players.append(player)


# --- Music ---

func play_music(stream: AudioStream, fade_in: float = 1.0) -> void:
	if not _music_enabled:
		return

	if fade_in > 0 and _music_player.playing:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, fade_in * 0.5)
		await tween.finished

	_music_player.stream = stream
	_music_player.volume_db = -80.0 if fade_in > 0 else linear_to_db(_music_volume)
	_music_player.play()

	if fade_in > 0:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", linear_to_db(_music_volume), fade_in * 0.5)


func stop_music(fade_out: float = 1.0) -> void:
	if fade_out > 0:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, fade_out)
		await tween.finished
	_music_player.stop()


func pause_music() -> void:
	_music_player.stream_paused = true


func resume_music() -> void:
	_music_player.stream_paused = false


# --- Sound Effects ---

func play_sfx(stream: AudioStream, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> void:
	if not _sfx_enabled:
		return

	var player := _get_next_sfx_player()
	player.stream = stream
	player.volume_db = linear_to_db(_sfx_volume * volume_scale)
	player.pitch_scale = pitch_scale
	player.play()


func play_sfx_at_position(stream: AudioStream, position: Vector3, volume_scale: float = 1.0) -> void:
	# For 3D positional audio - would use AudioStreamPlayer3D
	# For now, just play regular SFX
	play_sfx(stream, volume_scale)


func _get_next_sfx_player() -> AudioStreamPlayer:
	var player := _sfx_players[_current_sfx_index]
	_current_sfx_index = (_current_sfx_index + 1) % MAX_SFX_PLAYERS
	return player


# --- UI Sounds ---

func play_ui(stream: AudioStream, volume_scale: float = 1.0) -> void:
	_ui_player.stream = stream
	_ui_player.volume_db = linear_to_db(_ui_volume * volume_scale)
	_ui_player.play()


# --- Sound Loading ---

func preload_sound(path: String) -> AudioStream:
	if _sound_cache.has(path):
		return _sound_cache[path]

	var stream := load(path) as AudioStream
	if stream:
		_sound_cache[path] = stream
	return stream


func clear_sound_cache() -> void:
	_sound_cache.clear()


# --- Volume Control ---

func set_master_volume(volume: float) -> void:
	_master_volume = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), linear_to_db(_master_volume))


func set_music_volume(volume: float) -> void:
	_music_volume = clampf(volume, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(_music_volume)


func set_sfx_volume(volume: float) -> void:
	_sfx_volume = clampf(volume, 0.0, 1.0)


func set_ui_volume(volume: float) -> void:
	_ui_volume = clampf(volume, 0.0, 1.0)


func toggle_music(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()


func toggle_sfx(enabled: bool) -> void:
	_sfx_enabled = enabled


# --- Getters ---

func get_master_volume() -> float:
	return _master_volume


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func is_music_enabled() -> bool:
	return _music_enabled


func is_sfx_enabled() -> bool:
	return _sfx_enabled
