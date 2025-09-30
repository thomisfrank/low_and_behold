
# =====================================
# round_counter.gd
# Minimal UI to display and update current round number
# =====================================
extends Control

# Signal emitted when round changes
signal round_changed(new_round: int)

# Current round
### Current round
# round_count: Current round number
@export var round_count: int = 0

# UI node reference
var label: Label

func _ready() -> void:
	# Setup label and update display
	label = $Frame/Label
	update_label()

func update_label() -> void:
	# Update label text
	if label:
		label.text = "round: " + str(round_count)

func set_round(new_round: int) -> void:
	# Set new round and update label
	round_count = new_round
	update_label()
	emit_signal("round_changed", new_round)
