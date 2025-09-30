# Deck.gd - manages deck, draws, and animations
extends SubViewportContainer

@export var debug_logging: bool = true
# hand_node: the target hand (PlayerHand or OpponentHand)
# card_data_list: array of CustomCardData to deal (or null to auto-generate)
# num_cards: number of cards to deal
# deal_callback: optional callback to animate or handle each card
func deal(hand_node: Node, num_cards: int, card_data_list: Array = [], deal_callback = null) -> void:
	# If no card_data_list provided, generate random cards
	var gm = get_tree().get_root().find_child("GameManager", true, false)
	var candidates = []
	# Prefer deck-local candidate list; fallback to GameManager if available
	if has_method("_get_card_candidates"):
		candidates = _get_card_candidates()
	elif gm and gm.has_method("_get_card_candidates"):
		candidates = gm._get_card_candidates()
	for i in range(num_cards):
		var card_data = null
		var chosen_path: String = ""
		if card_data_list.size() > i:
			card_data = card_data_list[i]
		else:
			if candidates.size() > 0:
				chosen_path = _select_smart_card(candidates)
			card_data = load(chosen_path) as CustomCardData
		if not card_data:
			continue
		# Build metadata and notify listeners about the drawn card
		var meta_path = ""
		if typeof(chosen_path) != TYPE_NIL and chosen_path != "":
			meta_path = chosen_path
		elif card_data and card_data.resource_path:
			meta_path = card_data.resource_path
		var card_meta = _build_card_meta(meta_path)
		_track_drawn_card(card_meta)
		emit_signal("card_drawn", card_meta)
		# Find the target slot in the hand (prefer HandController)
		var slot = null
		var hc = get_tree().get_root().get_node_or_null("/root/HandController")
		if hc and hc.has_method("get_slot_node"):
			slot = hc.get_slot_node(hand_node, i)
		elif hand_node and hand_node.has_method("get_slot"):
			slot = hand_node.get_slot(i)
		if slot and slot.has_method("display"):
			slot.call_deferred("display", card_data)
			slot.visible = true
		# Optionally call a callback for animation
		if deal_callback and deal_callback.is_valid():
			deal_callback.call(card_data, slot, i)


# Convenience: deal a single card to a specific slot index on a hand.
# This will choose card data (using GameManager logic when available),
# call GameManager's animation helper to animate the draw, and update
# the deck count.
func deal_to_slot(hand_node: Node, slot_index: int) -> void:
	var gm = get_tree().get_root().find_child("GameManager", true, false)
	var candidates: Array = []
	if has_method("_get_card_candidates"):
		candidates = _get_card_candidates()
	elif gm and gm.has_method("_get_card_candidates"):
		candidates = gm._get_card_candidates()
	# Select card resource
	var chosen_path: String = ""
	if candidates.size() > 0:
		chosen_path = _select_smart_card(candidates)
	var card_data = load(chosen_path) as CustomCardData
	if not card_data:
		push_warning("[Deck] deal_to_slot: failed to load card resource: %s" % chosen_path)
		return

	# Build metadata and notify listeners
	var meta_path2 = chosen_path if chosen_path != "" else (card_data.resource_path if card_data and card_data.resource_path != "" else "")
	var card_meta2 = _build_card_meta(meta_path2)
	_track_drawn_card(card_meta2)
	emit_signal("card_drawn", card_meta2)

	# Find target slot and animation params
	var slot: Node = null
	var target_pos: Vector2 = Vector2.ZERO
	var target_rotation: float = 0.0
	var target_scale: Vector2 = Vector2.ONE
	if hand_node and hand_node.has_method("get_slot"):
		slot = hand_node.get_slot(slot_index)
	if slot:
		# Opponent slot or explicit slot node
		target_pos = slot.global_position
		if hand_node.has_method("slot_rotations") and slot_index < hand_node.slot_rotations.size():
			target_rotation = hand_node.slot_rotations[slot_index]
		if hand_node.has_method("slot_scales") and slot_index < hand_node.slot_scales.size():
			target_scale = hand_node.slot_scales[slot_index]
	else:
		# Fallback for PlayerHand which exposes slot_positions/rotations/scales arrays
		if hand_node:
			if hand_node.has_method("slot_positions") and slot_index < hand_node.slot_positions.size():
				target_pos = hand_node.slot_positions[slot_index]
			if hand_node.has_method("slot_rotations") and slot_index < hand_node.slot_rotations.size():
				target_rotation = hand_node.slot_rotations[slot_index]
			if hand_node.has_method("slot_scales") and slot_index < hand_node.slot_scales.size():
				target_scale = hand_node.slot_scales[slot_index]

	# Trigger animation via CardDrawAnimation (owned by Deck)
	var start_pos: Vector2 = global_position
	if top_card and is_instance_valid(top_card):
		start_pos = top_card.global_position

	# Prefer the autoload singleton `CardAnimator` if present (registered in project.godot)
	var animator_service: Node = null
	# Global autoloads are exposed on the root as named children; try that first
	var root = get_tree().get_root()
	if root and root.has_node("CardAnimator"):
		animator_service = root.get_node("CardAnimator")
	else:
		# Try explicit root path (another common access pattern for autoloads)
		var root_anim = get_node_or_null("/root/CardAnimator")
		if root_anim:
			animator_service = root_anim
		else:
			# Try a sibling CardAnimator node next to Deck
			var sibling = get_node_or_null("../CardAnimator")
			if sibling:
				animator_service = sibling
	# Enforce autoload: if animator not found, warn and abort the animated path
	if not animator_service:
		push_warning("[Deck] CardAnimator autoload not found. Register 'CardAnimator' in project.godot under [autoload]. Aborting animated draw.")
		# Fallback: place directly into hand without animation
		if slot and slot.has_method("display"):
			slot.call_deferred("display", card_data)
			slot.visible = true
		elif hand_node:
			var hc = get_tree().get_root().get_node_or_null("/root/HandController")
			if hc and hc.has_method("add_card_to_hand"):
				hc.add_card_to_hand(hand_node, card_data)
			elif hand_node.has_method("add_card_to_hand"):
				hand_node.add_card_to_hand(card_data)
		# Decrement deck count and return early
		_count = max(0, _count - 1)
		_update_count_label()
		return

	if animator_service and animator_service.has_method("animate_draw"):
		animator_service.animate_draw(card_data, start_pos, target_pos, target_rotation, target_scale, Vector2.ONE, false, Callable(self, "_on_card_animation_finished").bind(card_data, hand_node, slot, slot_index))
	else:
		# If no animator available, directly place into hand
		if slot and slot.has_method("display"):
			slot.call_deferred("display", card_data)
			slot.visible = true
		elif hand_node:
			var hc2 = get_tree().get_root().get_node_or_null("/root/HandController")
			if hc2 and hc2.has_method("add_card_to_hand"):
				hc2.add_card_to_hand(hand_node, card_data)
			elif hand_node.has_method("add_card_to_hand"):
				hand_node.add_card_to_hand(card_data)

	# Decrement deck count
	_count = max(0, _count - 1)
	_update_count_label()


func _on_card_animation_finished(animated_card: Control, _drawn_card_data: CustomCardData, hand_node: Node, target_slot: Node, slot_index: int) -> void:
	# Opponent logic: if target_slot provided, set hidden data and show back
	if is_instance_valid(target_slot):
		target_slot.set_meta("hidden_card_data", _drawn_card_data)
		if target_slot.has_method("display"):
			var back = _load_card_resource("CardBack")
			target_slot.call_deferred("display", back)
		if target_slot is CanvasItem:
			target_slot.visible = true
		if is_instance_valid(animated_card):
			animated_card.queue_free()
		# Notify listeners that opponent slot was set
		emit_signal("card_animation_finished", target_slot, -1, _drawn_card_data)
		return

	# Player logic: hand_node receives the animated card node
	if slot_index != -1 and is_instance_valid(animated_card):
		if hand_node and hand_node.has_method("receive_card_node"):
			hand_node.call_deferred("receive_card_node", animated_card, slot_index, _drawn_card_data)
		else:
			# Fallback: add card data directly
			if hand_node and hand_node.has_method("add_card_to_hand"):
				hand_node.call_deferred("add_card_to_hand", _drawn_card_data)
			elif is_instance_valid(animated_card):
				animated_card.queue_free()
	elif is_instance_valid(animated_card):
		animated_card.queue_free()

	# Notify listeners that player hand received the animated card
	if hand_node:
		emit_signal("card_animation_finished", hand_node, slot_index, _drawn_card_data)

# =====================================
# Deck.gd
# Manages deck stack, top card, and card draw logic
# =====================================

# Card scene and resource paths
const CardScene = preload("res://scenes/cards.tscn")
const DEFAULT_CARD_BACK_PATH = "res://scripts/resources/CardBack.tres"

# UI node references
@onready var stack_layers: Control = $DeckViewport/DeckControl/StackLayers
@onready var top_card: Node = $DeckViewport/DeckControl/TopCard
@onready var count_label: Label = $DeckViewport/DeckControl/CardCount/AspectRatioContainer/CardCountLabel

# Deck configuration
### Deck configuration
# initial_count: Initial number of cards in deck
@export var initial_count: int = 48
# stack_offset: Offset for stacked cards
@export var stack_offset: int = 60
# stack_x_offset: Horizontal offset for stack
@export var stack_x_offset: int = 8
# top_card_key: Key for top card in deck (enum)
@export_enum("TwoSwap", "TwoDraw", "FourSwap", "FourDraw", "SixSwap", "SixDraw", "EightSwap", "EightDraw", "TenSwap", "TenDraw", "CardBack") var top_card_key: String = "CardBack"

# Internal state
var _count: int = 0
var _last_two_cards: Array[Dictionary] = []
var _current_hand_meta: Array[Dictionary] = []

func _get_card_candidates() -> Array[String]:
	return [
		"res://scripts/resources/TwoDraw.tres", "res://scripts/resources/TwoSwap.tres",
		"res://scripts/resources/FourDraw.tres", "res://scripts/resources/FourSwap.tres",
		"res://scripts/resources/SixDraw.tres", "res://scripts/resources/SixSwap.tres",
		"res://scripts/resources/EightDraw.tres", "res://scripts/resources/EightSwap.tres",
		"res://scripts/resources/TenDraw.tres", "res://scripts/resources/TenSwap.tres"
	]

func _build_card_meta(path: String) -> Dictionary:
	var card_name = _extract_name_from_path(path)
	return {"value": _extract_value(card_name), "effect": _extract_effect(card_name), "path": path}

func _extract_value(card_name: String) -> String:
	if card_name.begins_with("Two"): return "Two"
	if card_name.begins_with("Four"): return "Four"
	if card_name.begins_with("Six"): return "Six"
	if card_name.begins_with("Eight"): return "Eight"
	if card_name.begins_with("Ten"): return "Ten"
	return "Unknown"

func _extract_effect(card_name: String) -> String:
	if card_name.ends_with("Draw"): return "Draw"
	if card_name.ends_with("Swap"): return "Swap"
	return "Unknown"

func _extract_name_from_path(path: String) -> String:
	var filename = path.get_file().get_basename()
	var name_map = {
		"TwoDraw": "Two Draw", "TwoSwap": "Two Swap",
		"FourDraw": "Four Draw", "FourSwap": "Four Swap",
		"SixDraw": "Six Draw", "SixSwap": "Six Swap",
		"EightDraw": "Eight Draw", "EightSwap": "Eight Swap",
		"TenDraw": "Ten Draw", "TenSwap": "Ten Swap"
	}
	return name_map.get(filename, filename)

func _select_smart_card(candidates: Array[String]) -> String:
	var last_effects = {}
	var last_values = {}
	if _last_two_cards.size() > 0:
		var m1 = _last_two_cards[_last_two_cards.size() - 1]
		last_effects[m1.get("effect", "")] = true
		last_values[m1.get("value", "")] = true
	if _last_two_cards.size() > 1:
		var m2 = _last_two_cards[_last_two_cards.size() - 2]
		last_effects[m2.get("effect", "")] = true
		last_values[m2.get("value", "")] = true
	var hand_paths = {}
	for meta in _current_hand_meta:
		hand_paths[meta.get("path", "")] = true
	var b00: Array[String] = []
	var b01: Array[String] = []
	var b10: Array[String] = []
	var b11: Array[String] = []
	for path in candidates:
		if hand_paths.has(path) and randi() % 100 >= 5:
			continue
		var cname = _extract_name_from_path(path)
		var val = _extract_value(cname)
		var eff = _extract_effect(cname)
		var eff_conflict = last_effects.has(eff)
		var val_conflict = last_values.has(val)
		if not eff_conflict and not val_conflict:
			b00.append(path)
		elif not eff_conflict and val_conflict:
			b01.append(path)
		elif eff_conflict and not val_conflict:
			b10.append(path)
		else:
			b11.append(path)
	if not b00.is_empty():
		return b00[randi() % b00.size()]
	if not b01.is_empty():
		return b01[randi() % b01.size()]
	if not b10.is_empty():
		return b10[randi() % b10.size()]
	if not b11.is_empty():
		return b11[randi() % b11.size()]
	return candidates[randi() % candidates.size()]

func _track_drawn_card(card_meta: Dictionary) -> void:
	_last_two_cards.append(card_meta)
	if _last_two_cards.size() > 2:
		_last_two_cards.pop_front()

func _ready():
	if debug_logging:
		print("[Deck] _ready() - ", get_path())

	# SubViewportContainer input config
	mouse_filter = Control.MOUSE_FILTER_PASS
	stretch = true
	var subviewport = $DeckViewport
	if subviewport:
		subviewport.handle_input_locally = false
		subviewport.gui_disable_input = false
	
	# Set initial count and update display
	_count = initial_count
	_update_count_label()
	
	# Initialize stack layers
	if stack_layers:
		stack_layers.z_index = -50
		stack_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in stack_layers.get_children():
			if child:
				child.queue_free()
	
	# Get the card back resource - always use CardBack for the stack
	var card_back_data = _load_card_resource("CardBack")
	
	# Create three stacked placeholder cards
	for i in range(3):
		var card = CardScene.instantiate()
		var layer_name = "StackLayer%d" % (i + 1)
		card.name = layer_name
		var offset_pos = Vector2(i * stack_x_offset, i * stack_offset)
		card.position = offset_pos
		call_deferred("_force_card_position", card, offset_pos)
		card.z_index = -(i + 1) * 10
		if card is Control:
			(card as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			var card_subviewport = card.get_node_or_null("CardsViewport")
			if card_subviewport and card_subviewport is SubViewport:
				card_subviewport.gui_disable_input = true
		stack_layers.add_child(card)
		card.call_deferred("display", card_back_data)
		call_deferred("_debug_card_info", card, layer_name)
	
	# Top card (draw) setup
	if top_card:
		top_card.queue_free()
	var top = CardScene.instantiate()
	top.name = "TopCard"
	top.z_index = 10
	top.position = Vector2.ZERO
	if top is Control:
		(top as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top_subviewport = top.get_node_or_null("CardsViewport")
		if top_subviewport and top_subviewport is SubViewport:
			top_subviewport.gui_disable_input = true
	add_child(top)
	var top_card_data = _load_card_resource(top_card_key)
	top.call_deferred("display", top_card_data)
	top_card = top

	print("[Deck] Setup complete, top_card_key=", top_card_key)

signal request_draw
signal card_drawn(card_meta: Dictionary)
signal card_animation_finished(hand_node: Node, slot_index: int, card_data: CustomCardData)
#-----------------------------------------------------------------------------
# Click-to-draw
# Left-click inside this control emits `request_draw` which the GameManager
# listens to in order to start a draw animation.
#-----------------------------------------------------------------------------
# Handle input events (SubViewportContainer input forwarding)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Check if the mouse event is within our bounds
		var mouse_pos = event.position
		var rect = get_global_rect()
		if rect.has_point(mouse_pos):
			print("[Deck] _input received mouse event within bounds: ", event)
			_handle_mouse_input(event)
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if debug_logging:
		print("[Deck] _gui_input called with event: ", event)
	_handle_mouse_input(event)

# Centralized mouse input handling
func _handle_mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if debug_logging:
			print("[Deck] Mouse button event - button:", event.button_index, " pressed:", event.pressed)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if debug_logging:
				print("[Deck] Left click detected, emitting request_draw")
			request_draw.emit()

# Add mouse enter/exit for debugging
# (No mouse enter/exit debug handlers)

# Update the count label with current count
func _update_count_label():
	if count_label and is_instance_valid(count_label):
		# Trim any extra whitespace in the scene label and set count
		count_label.text = str(_count)
	else:
		# Defensive: don't error if the label path is wrong
		print("[Deck] Warning: count_label not found; cannot update display")

# Set deck count (for GameManager to call)
func set_count(n: int) -> void:
	_count = n
	_update_count_label()
	# Toggle visibility of stack layers based on count
	if stack_layers:
		var stack1 = stack_layers.get_node_or_null("StackLayer1")
		var stack2 = stack_layers.get_node_or_null("StackLayer2")
		var stack3 = stack_layers.get_node_or_null("StackLayer3")
		if stack1: stack1.visible = _count >= 1
		if stack2: stack2.visible = _count >= 2
		if stack3: stack3.visible = _count >= 3

# Get current deck count
func get_count() -> int:
	return _count
	
# Load a card resource by key name
func _load_card_resource(key: String) -> CustomCardData:
	var resource_path = "res://scripts/resources/%s.tres" % key
	var resource = load(resource_path)
	if resource and resource is CustomCardData:
		return resource
	else:
		push_error("Failed to load card resource: %s" % resource_path)
		# Fall back to default card back
		return load(DEFAULT_CARD_BACK_PATH)

# Change the top card to display a different card resource
func set_top_card(card_data: CustomCardData) -> void:
	if top_card:
		top_card.call_deferred("display", card_data)

# Debug helper to check card positions after they're in the scene tree
func _debug_card_info(card: Node, expected_name: String) -> void:
	if card and is_instance_valid(card):
		var size_info = ""
		var bounds_info = ""
		if card is Control:
			var control = card as Control
			size_info = " size: " + str(control.size)
			bounds_info = " bounds: " + str(control.get_rect())
		print("[Deck] ", expected_name, " actual name: '", card.name, "' position: ", card.position, " global_position: ", card.global_position, size_info, bounds_info)

# Force card position after scene setup
func _force_card_position(card: Node, target_position: Vector2) -> void:
	if card and is_instance_valid(card):
		if card is Control:
			var control = card as Control
			# Clear any layout constraints
			control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			control.position = target_position
			print("[Deck] Forced ", card.name, " to position: ", target_position, " actual: ", control.position)
		
# Change the top card by key name (e.g., "TwoSwap", "FourDraw")
func set_top_card_by_key(key: String) -> void:
	var resource = _load_card_resource(key)
	top_card_key = key
	set_top_card(resource)
