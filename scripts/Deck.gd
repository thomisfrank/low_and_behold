# Deck: manage deck state, stack visuals and animated draws
extends Control

@export var debug_logging: bool = false

# Core resources and defaults
const CardScene = preload("res://scenes/cards.tscn")
const DEFAULT_CARD_BACK_PATH: String = "res://scripts/resources/CardBack.tres"

# Deck state
@export var initial_count: int = 48
var _count: int = 0
var _last_two_cards: Array = []
var top_card: Node = null
var top_card_key: String = "CardBack"

# Visual containers (may be wired in the scene)
var stack_layers: Node = null
@export var stack_x_offset: int = -17
@export var stack_offset: int = 24
var count_label: Node = null

# hand_node: the target hand (PlayerHand or OpponentHand)
# card_data_list: array of CustomCardData to deal (or null to auto-generate)

func deal_to_slot(hand_node: Node, slot_index: int) -> void:
	# Compute the animation start position: prefer the TopCard's global_position
	var start_pos_in_viewport: Vector2 = self.global_position
	if top_card and is_instance_valid(top_card):
		start_pos_in_viewport = top_card.global_position
	var true_start_pos = start_pos_in_viewport

	# Choose card data to draw (use the deck's top card resource if available)
	var card_data: CustomCardData = _load_card_resource(top_card_key)
	if not card_data:
		push_warning("[Deck] deal_to_slot: failed to load card data for top_card_key=%s" % str(top_card_key))
		return

	# Compute the target position/rotation/scale for the requested hand slot
	var slot_info: Dictionary = CoordinateUtils.get_slot_target(hand_node, slot_index)
	if debug_logging:
		var hn_path: String = "<null>"
		if hand_node and hand_node is Node:
			hn_path = hand_node.get_path()
		print("[Deck] deal_to_slot: hand=", hn_path, " slot_index=", slot_index, " slot_info=", slot_info)
	var target_pos: Vector2 = slot_info.get("pos", Vector2.ZERO)
	var target_rotation: float = slot_info.get("rotation", 0.0)
	var target_scale: Vector2 = slot_info.get("scale", Vector2.ONE)
	var slot_node: Node = slot_info.get("slot_node", null)

	var animator_service: Node = get_node_or_null("/root/CardAnimator")
	if not animator_service:
		push_warning("[Deck] CardAnimator autoload not found. Aborting animated draw.")
		return

	if animator_service.has_method("animate_draw"):
		var start_scale: Vector2 = Vector2.ONE
		if top_card and is_instance_valid(top_card) and top_card is CanvasItem:
			start_scale = top_card.scale
		animator_service.animate_draw(card_data, true_start_pos, target_pos, target_rotation, target_scale, start_scale, false, Callable(self, "_on_card_animation_finished").bind(card_data, hand_node, slot_node, slot_index))

	_count = max(0, _count - 1)
	_update_count_label()


func _on_card_animation_finished(animated_card: Control, _drawn_card_data: CustomCardData, hand_node: Node, target_slot: Node, slot_index: int) -> void:
	# Opponent logic: if target_slot provided, set hidden data and show back
	if is_instance_valid(target_slot):
		# Opponent slot: store hidden data and force back display
		target_slot.set_meta("hidden_card_data", _drawn_card_data)
		if target_slot.has_method("display"):
			var back = _load_card_resource("CardBack")
			target_slot.call_deferred("display", back)
		# Notify listeners that this card's animation finished and hidden data is set
		emit_signal("card_animation_finished", hand_node, int(slot_index), _drawn_card_data)
		return

	# Player-hand case: if we have a hand_node that supports receive_card_node,
	# hand implementations will reparent and position the card appropriately.
	# Fallback: attach to the hand_node and store card_data meta.
	if hand_node and hand_node.has_method("receive_card_node"):
		# Remove from current parent (usually CardAnimatorLayer/CanvasLayer) so
		# the hand can safely add_child the node. Use deferred removal if the
		# animated card is currently in the middle of a tree callback.
		if animated_card and animated_card.get_parent():
			var old_parent = animated_card.get_parent()
			if debug_logging:
				print("[Deck] _on_card_animation_finished: removing animated_card from parent", old_parent.get_path())
			# Use deferred removal to avoid altering the tree while tweens/callbacks may be running
			old_parent.call_deferred("remove_child", animated_card)

		# Ensure the animated card shows its face (the drawn card data) before
		# handing it over to the player's hand. Opponent slots intentionally
		# show the back in _on_card_animation_finished above, but for player
		# hands we want the actual face to be visible.
		if animated_card and animated_card.has_method("display") and is_instance_valid(animated_card):
			# Call display synchronously so the card shows its face immediately
			# before we hand the node off to the player's hand. Using a deferred
			# call here risked the receive_card_node running first and leaving the
			# visual as the CardBack.
			animated_card.display(_drawn_card_data)

		# Hand the node off to the hand implementation which will add_child and
		# position/scale the card appropriately.
		hand_node.call_deferred("receive_card_node", animated_card, slot_index, _drawn_card_data)
		# Tag the card with its data for other systems (non-fatal)
		if animated_card:
			animated_card.set_meta("card_data", _drawn_card_data)
		# Notify listeners that this card's animation finished and card node was delivered
		emit_signal("card_animation_finished", hand_node, int(slot_index), _drawn_card_data)
		return

	# Last-resort fallback
	if hand_node and is_instance_valid(hand_node):
		if animated_card and is_instance_valid(animated_card):
			# Move under the hand node so it sits in the same coordinate space
			var gp = animated_card.global_position
			if animated_card.get_parent():
				animated_card.get_parent().remove_child(animated_card)
			hand_node.add_child(animated_card)
			animated_card.global_position = gp
			animated_card.set_meta("card_data", _drawn_card_data)
			# Attempt to place into a slot if possible
			if hand_node.has_method("get_first_filled_slot_index"):
				# Nothing more to do here; the hand should reconcile on its next tick
				pass

func _track_drawn_card(card_meta: Dictionary) -> void:
	_last_two_cards.append(card_meta)
	if _last_two_cards.size() > 2:
		_last_two_cards.pop_front()

func _ready():
	# Strong startup prints to help diagnose why debug output may be missing
	if debug_logging:
		print("[Deck] _ready() - ", get_path())
		print("[Deck] Debug: top_card exists? ", top_card != null, " count_label exists? ", count_label != null)
		# Also emit a warning so it shows in the Debugger panel regardless of print filters
		push_warning("[Deck] READY: " + str(get_path()) + " top_card=" + str(top_card != null) + " count_label=" + str(count_label != null))

	# Input config — Deck used to be a SubViewportContainer. If a
	# DeckViewport SubViewport exists, configure it safely. Keep
	# mouse_filter for Control so the node can pass mouse events.
	mouse_filter = Control.MOUSE_FILTER_PASS
	var subviewport = get_node_or_null("DeckViewport")
	if subviewport and subviewport is SubViewport:
		subviewport.handle_input_locally = false
		subviewport.gui_disable_input = false
	
	# Set initial count and update display
	_count = initial_count
	_update_count_label()
	
	# NOTE: Do not apply any scale to stacked/top card instances here — the
	# deck visuals should remain at their authored size. The animation system
	# will read the deck/top_card scale as the start scale when animating draws.

	# Initialize stack layers
	if stack_layers:
		stack_layers.z_index = -50
		stack_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in stack_layers.get_children():
			if child:
				child.queue_free()
	
	# Get the card back resource - always use CardBack for the stack
	var card_back_data = _load_card_resource("CardBack")
	
	# Create three stacked placeholder cards. If the expected
	# `stack_layers` container is missing (scene changed), fall back to
	# adding the cards directly to this node and emit a warning so the
	# editor/runtime user knows the scene structure differs.
	if stack_layers:
		for i in range(3):
			var card = CardScene.instantiate()
			var layer_name = "StackLayer%d" % (i + 1)
			card.name = layer_name
			var offset_pos = Vector2(i * stack_x_offset, i * stack_offset)
			# Keep card at authored scale for stack placeholders (no explicit scaling).
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
	else:
		push_warning("[Deck] stack_layers not found; adding stack placeholders to Deck root")
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
			add_child(card)
			card.call_deferred("display", card_back_data)
			call_deferred("_debug_card_info", card, layer_name)
	
	# Top card (draw) setup
	if top_card:
		top_card.queue_free()
	var top = CardScene.instantiate()
	top.name = "TopCard"
	top.z_index = 10
	# Keep top card at authored scale; the animator will use this node's scale
	# as the start_scale when creating animated draw cards.
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

	if debug_logging:
		print("[Deck] Setup complete, top_card_key=", top_card_key)

signal request_draw
# Emitted when a card resource is drawn; consumers (GameManager/RoundManager)
# may connect to this signal externally.
signal card_drawn(card_meta: Dictionary)
# Emitted when an animation finishes and a card node is ready for the hand.
# This signal is connected by higher-level managers (e.g., RoundManager)
# or by GameManager; kept as a public hook for external wiring.
signal card_animation_finished(hand_node: Node, slot_index: int, card_data: CustomCardData)
# Click-to-draw handling
# Handle input events (SubViewportContainer input forwarding)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Check if the mouse event is within our bounds
		var mouse_pos = event.position
		var rect = get_global_rect()
		if rect.has_point(mouse_pos):
			if debug_logging:
				print("[Deck] _input received mouse event within bounds: ", event)
				# Also print debug marker for visibility in output
				print("[Deck] Debug: input rect: ", rect, " mouse_pos: ", mouse_pos)
			# Push a warning to ensure an entry appears in the Debugger panel
			push_warning("[Deck] INPUT inside rect: mouse=" + str(mouse_pos) + " rect=" + str(rect))
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
		# Defensive: don't error if the label path is wrong. Try to locate
		# a reasonable label in the scene (for cases where the scene was
		# edited or reverted and wiring was lost).
		count_label = _find_count_label()
		if count_label and is_instance_valid(count_label):
			count_label.text = str(_count)
			if debug_logging:
				print("[Deck] _update_count_label: auto-wired count_label at", count_label.get_path())
		else:
			if debug_logging:
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
		if debug_logging:
			print("[Deck] ", expected_name, " actual name: '", card.name, "' position: ", card.position, " global_position: ", card.global_position, size_info, bounds_info)

# Force card position after scene setup
func _force_card_position(card: Node, target_position: Vector2) -> void:
	if card and is_instance_valid(card):
		if card is Control:
			var control = card as Control
			# Clear any layout constraints
			control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			control.position = target_position
			if debug_logging:
				print("[Deck] Forced ", card.name, " to position: ", target_position, " actual: ", control.position)
		
# Change the top card by key name (e.g., "TwoSwap", "FourDraw")
func set_top_card_by_key(key: String) -> void:
	var resource = _load_card_resource(key)
	top_card_key = key
	set_top_card(resource)


# Try to locate a Label or RichTextLabel child whose name contains 'count'
func _find_count_label(root: Node = null) -> Node:
	var start = root if root != null else get_tree().get_current_scene()
	if not start:
		return null
	for child in start.get_children():
		if not child:
			continue
		# Check by type first
		if child is Label or child is RichTextLabel:
			var lname = ""
			if child.name:
				lname = child.name.to_lower()
			if "count" in lname or "deck" in lname:
				return child
		# Recurse into containers and controls
		var found = _find_count_label(child)
		if found:
			return found
	return null
