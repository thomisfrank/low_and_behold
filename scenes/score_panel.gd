extends Control

# Minimal ScorePanel
# - Finds Label nodes named "ScoreTracker" under this node
# - Defaults the displayed number to 0
# - Provides a tiny API: set_score(value) and add_score(delta)

@export var debug: bool = false

@export var label_prefix: String = "Score: "
@export var fills_visible: bool = true

var score: int = 0
var trackers: Array[Label] = []

func _ready() -> void:
	# find score tracker labels and update UI once
	trackers = _find_score_trackers()
	_update_trackers()
	if debug:
		if trackers.size() == 0:
			push_warning("ScorePanel: no ScoreTracker labels found; defaulting to 0")
		else:
			push_warning("ScorePanel: attached %d ScoreTracker labels" % trackers.size())

		# Debug: list the exact ScoreTracker label paths and any TextureRect named "Fill"
		var tracker_paths: Array = []
		for t in trackers:
			if t:
				tracker_paths.append(t.get_path())
		push_warning("ScorePanel: trackers -> %s" % tracker_paths)

		var found_fills: Array = []
		var q: Array = [self]
		while q.size() > 0:
			var n = q.pop_front()
			for c in n.get_children():
				if c is TextureRect and c.name == "Fill":
					found_fills.append(c.get_path())
				if c.get_child_count() > 0:
					q.append(c)
		push_warning("ScorePanel: Fill nodes -> %s" % found_fills)

	# set any TextureRect named "Fill" to the exported visibility
	var queue: Array = [self]
	while queue.size() > 0:
		var node = queue.pop_front()
		for c in node.get_children():
			if c is TextureRect and c.name == "Fill":
				c.visible = fills_visible
			if c.get_child_count() > 0:
				queue.append(c)

# Public API
func set_score(value: int) -> void:
	score = value
	_update_trackers()

func add_score(delta: int) -> void:
	set_score(score + delta)

# Internal
func _update_trackers() -> void:
	for t in trackers:
		if t:
			t.text = "%s%d" % [label_prefix, score]


func _find_score_trackers() -> Array[Label]:
	var out: Array[Label] = []
	var queue: Array = [self]
	while queue.size() > 0:
		var node = queue.pop_front()
		for c in node.get_children():
			if c is Label and c.name == "ScoreTracker":
				out.append(c)
			if c.get_child_count() > 0:
				queue.append(c)
	return out
