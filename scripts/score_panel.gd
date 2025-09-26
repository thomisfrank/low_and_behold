extends Control

# ScorePanel - lightweight score display used for Player and Opponent

#--------------------------------------------------------------------------
# Exports / configuration
#--------------------------------------------------------------------------
@export var debug: bool = false
@export var label_prefix: String = "Score: "
@export var fills_visible: bool = true

#--------------------------------------------------------------------------
# Internal state
#--------------------------------------------------------------------------
var score: int = 0
var trackers: Array[Label] = []

#--------------------------------------------------------------------------
# Engine hooks
#--------------------------------------------------------------------------
func _ready() -> void:
	trackers = _find_score_trackers()
	_update_trackers()

	# Apply configured fill visibility to any child TextureRect named "Fill"
	_set_fills_visibility(fills_visible)

	if debug:
		if trackers.size() == 0:
			push_warning("ScorePanel: no ScoreTracker labels found; defaulting to 0")
		else:
			push_warning("ScorePanel: attached %d ScoreTracker labels" % trackers.size())

#--------------------------------------------------------------------------
# Public API
#--------------------------------------------------------------------------
func set_score(value: int) -> void:
	score = value
	_update_trackers()

func add_score(delta: int) -> void:
	set_score(score + delta)

#--------------------------------------------------------------------------
# Internal helpers
#--------------------------------------------------------------------------
func _update_trackers() -> void:
	for t in trackers:
		if t and is_instance_valid(t):
			t.text = "%s%d" % [label_prefix, score]

func _set_fills_visibility(p_visible: bool) -> void:
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
