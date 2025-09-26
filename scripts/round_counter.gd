extends Control

#-----------------------------------------------------------------------------
# Round counter UI
# Minimal control to display and update the current round number
#-----------------------------------------------------------------------------

signal round_changed(new_round: int)

@export var round_count: int = 0

# Node references
var label: Label

func _ready() -> void:
	label = $Frame/Label
	update_label()

func update_label() -> void:
	if label:
		label.text = "round: " + str(round_count)

func set_round(new_round: int) -> void:
	round_count = new_round
	update_label()
	emit_signal("round_changed", new_round)
