extends Control

# count the number of rounds that have passed
@export var round_count: int = 0:
	set(value):
		round_count = value
		if is_inside_tree():
			update_label()

var label: Label

func _ready():
	label = $Frame/Label
	update_label()

func update_label():
	if label:
		label.text = "round: " + str(round_count)

func set_round(new_round: int):
	self.round_count = new_round
