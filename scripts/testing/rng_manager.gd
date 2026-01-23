class_name RNGManager
extends RefCounted
## Manages RNG seeds for reproducible test sessions


## Base seed for the entire session
var base_seed: int = 0

## Current match seed
var current_match_seed: int = 0

## Pre-generated seeds for each match
var match_seeds: Array[int] = []

## Internal RNG for generating match seeds
var _seed_generator: RandomNumberGenerator


func _init() -> void:
	_seed_generator = RandomNumberGenerator.new()
	match_seeds = []


func set_session_seed(seed_value: int) -> void:
	"""Initialize session with a base seed. Pass 0 for random seed."""
	if seed_value == 0:
		# Generate random base seed
		randomize()
		base_seed = randi()
	else:
		base_seed = seed_value

	# Initialize seed generator
	_seed_generator.seed = base_seed

	# Pre-generate seeds for many matches
	_generate_match_seeds(10000)

	print("[RNG] Session seed: %d" % base_seed)


func _generate_match_seeds(count: int) -> void:
	"""Pre-generate deterministic seeds for each match."""
	match_seeds.clear()
	for i in range(count):
		match_seeds.append(_seed_generator.randi())


func get_match_seed(match_index: int) -> int:
	"""Get the deterministic seed for a specific match index."""
	if match_index < 0:
		return base_seed
	if match_index >= match_seeds.size():
		# Generate more seeds if needed
		var old_state := _seed_generator.state
		while match_seeds.size() <= match_index:
			match_seeds.append(_seed_generator.randi())
	return match_seeds[match_index]


func apply_match_seed(match_index: int) -> void:
	"""Apply the seed for a match, affecting global RNG."""
	current_match_seed = get_match_seed(match_index)
	seed(current_match_seed)


func get_reproducibility_info() -> Dictionary:
	"""Get information for reproducing this session."""
	return {
		"base_seed": base_seed,
		"current_match_seed": current_match_seed,
		"matches_seeded": match_seeds.size()
	}


func get_replay_command(match_index: int) -> String:
	"""Get command to replay a specific match."""
	var match_seed := get_match_seed(match_index)
	return "godot --headless --script res://scripts/testing/headless_runner.gd -- --matches=1 --seed=%d" % match_seed


## Create a separate RNG instance for a specific purpose (e.g., AI decisions)
func create_match_rng(match_index: int) -> RandomNumberGenerator:
	"""Create a seeded RNG for a specific match."""
	var rng := RandomNumberGenerator.new()
	rng.seed = get_match_seed(match_index)
	return rng


## Utility: Get the seed that would produce a specific outcome
static func find_seed_for_outcome(target_func: Callable, max_attempts: int = 10000) -> int:
	"""Find a seed that makes target_func return true. For debugging."""
	var test_rng := RandomNumberGenerator.new()
	for i in range(max_attempts):
		test_rng.seed = i
		seed(i)
		if target_func.call():
			return i
	return -1


## Verify that seeds are deterministic
func verify_determinism() -> bool:
	"""Verify that the RNG produces consistent results."""
	var test_seed := 12345

	# First run
	seed(test_seed)
	var results1: Array[int] = []
	for i in range(10):
		results1.append(randi())

	# Second run with same seed
	seed(test_seed)
	var results2: Array[int] = []
	for i in range(10):
		results2.append(randi())

	# Compare
	for i in range(10):
		if results1[i] != results2[i]:
			push_error("[RNG] Determinism check failed at index %d" % i)
			return false

	return true
