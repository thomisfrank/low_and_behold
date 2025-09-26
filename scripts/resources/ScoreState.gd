extends Resource

# Simple shared score/action state resource.
# Use this to share score and action counts between UI and game logic.

class_name ScoreState

signal state_changed(new_score: int, new_actions: int)

@export var total_score: int = 0
@export var actions_taken: int = 0

func set_score(value: int) -> void:
	total_score = value
	emit_signal("state_changed", total_score, actions_taken)

func set_actions(value: int) -> void:
	actions_taken = value
	emit_signal("state_changed", total_score, actions_taken)

func set_state(score: int, actions: int) -> void:
	total_score = score
	actions_taken = actions
	emit_signal("state_changed", total_score, actions_taken)
