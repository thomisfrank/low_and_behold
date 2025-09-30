
# =====================================
# score_panel.gd
# Lightweight score display for Player and Opponent
# =====================================
extends Control

# Configuration
### Configuration
# debug: Toggle for debug print statements
@export var debug: bool = false
# label_prefix: Prefix for score label
@export var label_prefix: String = "Score: "
# fills_visible: Show/hide fill indicators
@export var fills_visible: bool = true

# Internal state
var score: int = 0
var trackers: Array[Label] = []

func _ready() -> void:
	# Setup score trackers and fill visibility
	trackers = _find_score_trackers()
	_update_trackers()
	_set_fills_visibility(fills_visible)
	if debug:
		if trackers.size() == 0:
			push_warning("ScorePanel: no ScoreTracker labels found; defaulting to 0")
		else:
			push_warning("ScorePanel: attached %d ScoreTracker labels" % trackers.size())

func set_score(value: int) -> void:
	# Set and update score
	score = value
	_update_trackers()

func set_actions_left(actions: int) -> void:
	# Updates the ActionIndicator Fill nodes based on actions left (0, 1, 2)
	var player_action_indicators = [
		get_node_or_null("../PlayerScore/ScoreFrame/ActivityIndicator/ActionIndicator/Fill"),
		get_node_or_null("../PlayerScore/ScoreFrame/ActivityIndicator/ActionIndicator2/Fill")
	]
	for i in range(player_action_indicators.size()):
		if player_action_indicators[i]:
			player_action_indicators[i].visible = (actions > i)
	var opponent_action_indicators = [
		get_node_or_null("../OpponentScore/frame/ActivityIndicator/ActionIndicator/Fill"),
		get_node_or_null("../OpponentScore/frame/ActivityIndicator/ActionIndicator2/Fill")
	]
	for i in range(opponent_action_indicators.size()):
		if opponent_action_indicators[i]:
			opponent_action_indicators[i].visible = (actions > i)

func add_score(delta: int) -> void:
	# Add to score
	set_score(score + delta)

func _update_trackers() -> void:
	# Update score label text
	for t in trackers:
		if t and is_instance_valid(t):
			t.text = "%s%d" % [label_prefix, score]

func _set_fills_visibility(p_visible: bool) -> void:
	# Set fill visibility for all child TextureRects named "Fill"
	var q: Array = [self]
	while q.size() > 0:
		var n = q.pop_front()
		for c in n.get_children():
			if c is TextureRect and c.name == "Fill":
				c.visible = p_visible
			if c.get_child_count() > 0:
				q.append(c)

func _find_score_trackers() -> Array[Label]:
	var out: Array[Label] = []
	var q: Array = [self]
	while q.size() > 0:
		var n = q.pop_front()
		for c in n.get_children():
			if c is Label and c.name == "ScoreTracker":
				out.append(c)
			if c.get_child_count() > 0:
				q.append(c)
	return out
