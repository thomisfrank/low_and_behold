extends Control

# Clean, minimal ScorePanel script.
# Attach this to the Control that represents the score UI for player or opponent.
# It searches common paths for the ScoreTracker label and ActionIndicator fills.

@export var debug: bool = false
@export var max_actions: int = 2

var total_score: int = 0
var actions_taken: int = 0

var score_label: Label = null
var action_fills: Array = []

func _ready() -> void:
	var activity_indicator = null

	# Prefer local lookups relative to this node
	score_label = get_node_or_null("ScoreFrame/ScoreTracker")
	activity_indicator = get_node_or_null("ScoreFrame/ActivityIndicator")

	# If not found locally, try siblings named PlayerScore/OppScore under the parent
	if not score_label and get_parent():
		var player_node = get_parent().get_node_or_null("PlayerScore")
		var opp_node = get_parent().get_node_or_null("OppScore")
		if player_node:
			score_label = player_node.get_node_or_null("ScoreFrame/ScoreTracker")
			activity_indicator = player_node.get_node_or_null("ScoreFrame/ActivityIndicator")
		elif opp_node:
			score_label = opp_node.get_node_or_null("ScoreFrame/ScoreTracker")
			activity_indicator = opp_node.get_node_or_null("ScoreFrame/ActivityIndicator")

	# Best-effort: try the scene root for instances named PlayerScore/OppScore
	if not score_label:
		var root = get_tree().get_edited_scene_root() if Engine.is_editor_hint() else get_tree().current_scene
		if root:
			var candidate = root.get_node_or_null("PlayerScore")
			if candidate:
				score_label = candidate.get_node_or_null("ScoreFrame/ScoreTracker")
				activity_indicator = candidate.get_node_or_null("ScoreFrame/ActivityIndicator")
			else:
				candidate = root.get_node_or_null("OppScore")
				if candidate:
					score_label = candidate.get_node_or_null("ScoreFrame/ScoreTracker")
					activity_indicator = candidate.get_node_or_null("ScoreFrame/ActivityIndicator")

	# Collect action fills
	action_fills.clear()
	if activity_indicator:
		var f1 = activity_indicator.get_node_or_null("ActionIndicator/Fill")
		var f2 = activity_indicator.get_node_or_null("ActionIndicator2/Fill")
		if f1:
			action_fills.append(f1)
		if f2:
			action_fills.append(f2)

	if debug:
		print_debug_info()

	_update_score_label()
	_update_action_monitors()

func print_debug_info() -> void:
	print("[ScorePanel] score_label:", score_label)
	print("[ScorePanel] action_fills count:", action_fills.size())
	for i in range(action_fills.size()):
		print("  ", i, "->", action_fills[i])

# Public API
func set_score(value: int) -> void:
	total_score = value
	_update_score_label()

func set_actions(value: int) -> void:
	actions_taken = clamp(value, 0, max_actions)
	_update_action_monitors()

# Internal helpers
func _update_score_label() -> void:
	if score_label:
		score_label.text = "Score: %d" % total_score
	elif debug:
		push_warning("ScorePanel: score_label not found; cannot update text")

func _update_action_monitors() -> void:
	if action_fills.size() == 0:
		if debug:
			push_warning("ScorePanel: action_fills empty; nothing to update")
		return
	var available = clamp(max_actions - actions_taken, 0, action_fills.size())
	for i in range(action_fills.size()):
		action_fills[i].visible = i < available

# Convenience inspector hooks
func _set_total_score_inspector(value: int) -> void:
	set_score(value)

func _set_actions_inspector(value: int) -> void:
	set_actions(value)