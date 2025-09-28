
# =====================================
# round_end_screen.gd
# Handles round end UI, score display, and continue button
# =====================================
extends Control

# Signal emitted when continue is pressed
signal continue_pressed

# UI node references
@onready var continue_button = $"CanvasLayer/ContinueButton/Button"
@onready var player_score_label = $"CanvasLayer/PlayerScore"
@onready var opponent_score_label = $"CanvasLayer/OpponentScore"
@onready var player_total_label = $"CanvasLayer/PlayerTotal"
@onready var opponent_total_label = $"CanvasLayer/OpponentTotal"
@onready var player_win_label = $"CanvasLayer/PlayerWinCondition"
@onready var opponent_win_label = $"CanvasLayer/OpponentWinCondition"
@onready var button_label = $"CanvasLayer/ContinueButton/ButtonLabel"

func _ready():
	# Setup continue button and hide win/tie labels
	continue_button.pressed.connect(_on_continue_pressed)
	button_label.text = "Okay"
	player_win_label.visible = false
	opponent_win_label.visible = false

# Set scores, totals, and win/tie status
func set_scores(p1_score: int, p2_score: int, p1_total: int = -1, p2_total: int = -1):
	# Set scores, totals, and win/tie status
	player_score_label.text = str(p1_score)
	opponent_score_label.text = str(p2_score)
	if p1_total >= 0:
		player_total_label.text = str(p1_total)
	if p2_total >= 0:
		opponent_total_label.text = str(p2_total)
	if p1_total >= 0 and p2_total >= 0:
		if p1_total < p2_total:
			player_win_label.text = "Win!"
			player_win_label.visible = true
			opponent_win_label.visible = false
		elif p2_total < p1_total:
			opponent_win_label.text = "Win!"
			opponent_win_label.visible = true
			player_win_label.visible = false
		else:
			player_win_label.text = "Tie"
			opponent_win_label.text = "Tie"
			player_win_label.visible = true
			opponent_win_label.visible = true

func _on_continue_pressed():
	# Emit continue signal and close screen
	emit_signal("continue_pressed")
	queue_free()
