class_name TestSessionConfig
extends RefCounted
## Configuration for a test session


enum ExecutionMode {
	HEADLESS,      ## No UI, maximum speed, CLI output
	MINIMAL_UI,    ## Progress bars and live stats
	SPECTATE       ## Full visual game with animations
}


## Execution mode for this session
var execution_mode: ExecutionMode = ExecutionMode.HEADLESS

## Base RNG seed for reproducibility (0 = random)
var base_seed: int = 0

## Total number of matches to run
var num_matches: int = 10

## AI difficulty for player 1
var p1_difficulty: int = 1  # AIController.Difficulty.MEDIUM

## AI difficulty for player 2
var p2_difficulty: int = 1  # AIController.Difficulty.MEDIUM

## Specific matchups to test (if empty, generates random matchups)
var matchups: Array[MatchConfig] = []

## Maximum rounds per match before declaring draw
var max_rounds: int = 50

## Maximum actions per turn (safety limit)
var max_actions_per_turn: int = 30

## Output directory for reports
var output_directory: String = "user://test_reports/"

## Whether to save individual match details
var save_match_details: bool = true

## Speed multiplier for spectate mode (1.0 = normal)
var spectate_speed: float = 1.0

## Auto-advance between matches in spectate mode
var auto_advance: bool = true

## Delay between matches in spectate mode (seconds)
var match_delay: float = 3.0


func _init() -> void:
	matchups = []


func from_command_args(args: Dictionary) -> void:
	"""Parse configuration from command line arguments."""
	if args.has("matches"):
		num_matches = int(args["matches"])
	if args.has("seed"):
		base_seed = int(args["seed"])
	if args.has("p1_difficulty"):
		p1_difficulty = int(args["p1_difficulty"])
	if args.has("p2_difficulty"):
		p2_difficulty = int(args["p2_difficulty"])
	if args.has("max_rounds"):
		max_rounds = int(args["max_rounds"])
	if args.has("output"):
		output_directory = args["output"]
	if args.has("mode"):
		match args["mode"]:
			"headless":
				execution_mode = ExecutionMode.HEADLESS
			"minimal", "ui":
				execution_mode = ExecutionMode.MINIMAL_UI
			"spectate", "watch":
				execution_mode = ExecutionMode.SPECTATE


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	return {
		"execution_mode": ExecutionMode.keys()[execution_mode],
		"base_seed": base_seed,
		"num_matches": num_matches,
		"p1_difficulty": p1_difficulty,
		"p2_difficulty": p2_difficulty,
		"max_rounds": max_rounds,
		"max_actions_per_turn": max_actions_per_turn,
		"output_directory": output_directory,
		"save_match_details": save_match_details,
		"matchup_count": matchups.size()
	}


## Configuration for a single match
class MatchConfig extends RefCounted:
	var match_index: int = 0
	var p1_champions: Array[String] = []
	var p2_champions: Array[String] = []
	var p1_difficulty: int = 1
	var p2_difficulty: int = 1
	var seed_override: int = 0  # 0 = use session seed generator

	func _init() -> void:
		p1_champions = []
		p2_champions = []

	func to_dict() -> Dictionary:
		return {
			"match_index": match_index,
			"p1_champions": p1_champions,
			"p2_champions": p2_champions,
			"p1_difficulty": p1_difficulty,
			"p2_difficulty": p2_difficulty,
			"seed_override": seed_override
		}
