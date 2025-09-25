extends Node

# Background picker for scenes/backgrounds.tscn
# Designed to run as an Autoload (singleton) or attached to the `backgrounds` node.

@export var randomize_on_ready: bool = true
@export var randomize_shader_speed: bool = true
@export var shader_speed_min: float = 0.002
@export var shader_speed_max: float = 0.02
@export var randomize_direction: bool = true
@export var random_flip: bool = false

func _ready():
	# Seed RNG for run-to-run variation
	randomize()

	if randomize_on_ready:
		# Try to find a backgrounds node in the current scene and apply immediately
		_find_and_apply()

	# Listen for nodes being added so when the scene loads the backgrounds node will be picked up
	get_tree().connect("node_added", Callable(self, "_on_node_added"))


func _find_and_apply():
	# If this script is attached to the backgrounds node itself and has a Landscape child, use it
	if has_node("Landscape"):
		_choose_random_background(self)
		return

	# Otherwise try current scene first using a safe recursive search
	var cs = get_tree().current_scene
	if cs:
		var bg = _recursive_find_backgrounds(cs)
		if bg:
			_choose_random_background(bg)
			return

	# Last resort: search the whole tree from the root
	var root_bg = _recursive_find_backgrounds(get_tree().get_root())
	if root_bg:
		_choose_random_background(root_bg)


func _on_node_added(node: Node) -> void:
	# When a node named 'backgrounds' appears, apply a random choice
	if node and node.name == "backgrounds":
		_choose_random_background(node)


func _recursive_find_backgrounds(node: Node) -> Node:
	if not node:
		return null
	# If node is named 'backgrounds' or contains a Landscape child, return it
	if node.name == "backgrounds":
		return node
	if node.has_node("Landscape"):
		return node

	for child in node.get_children():
		if child is Node:
			var found = _recursive_find_backgrounds(child)
			if found:
				return found
	return null


func _choose_random_background(bg_node: Node) -> void:
	if not bg_node:
		return

	var landscape = bg_node.get_node_or_null("Landscape")
	if not landscape:
		push_warning("[Backgrounds] Landscape node not found under backgrounds node")
		return

	var candidates: Array = []
	for child in landscape.get_children():
		if child is TextureRect:
			candidates.append(child)
			child.visible = false

	if candidates.size() == 0:
		push_warning("[Backgrounds] No TextureRect candidates found under Landscape")
		return

	var picked: TextureRect = candidates[randi() % candidates.size()]
	picked.visible = true

	# Optionally randomize shader scroll speed and direction
	if randomize_shader_speed and picked.material and picked.material is ShaderMaterial:
		var mat: ShaderMaterial = picked.material
		var sx = lerp(shader_speed_min, shader_speed_max, randf())
		var sy = lerp(shader_speed_min, shader_speed_max, randf())
		if randomize_direction:
			sx *= (-1.0 if (randi() % 2 == 0) else 1.0)
			sy *= (-1.0 if (randi() % 2 == 0) else 1.0)
		mat.set_shader_parameter("scroll_speed", Vector2(sx, sy))

	# Optionally flip the texture horizontally/vertically for another kind of direction change
	if random_flip:
		picked.flip_h = (randi() % 2 == 0)
		picked.flip_v = (randi() % 2 == 0)

	if Engine.is_editor_hint():
		print("[Backgrounds] Picked background: ", picked.name)


func show_background_by_name(requested_name: String) -> bool:
	# Find a backgrounds node and show a specific background by name
	var cs = get_tree().current_scene
	var bg = null
	if cs:
		bg = cs.find_node("backgrounds", true, false)
	if not bg:
		bg = get_tree().get_root().find_node("backgrounds", true, false)
	if not bg:
		return false

	var landscape = bg.get_node_or_null("Landscape")
	if not landscape:
		return false

	for child in landscape.get_children():
		if child is TextureRect and child.name == requested_name:
			for c in landscape.get_children():
				if c is TextureRect:
					c.visible = false
			child.visible = true
			return true
	return false
