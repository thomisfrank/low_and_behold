extends Control
class_name PlayerHand

# Exportable hand slot positions and settings
@export_group("Hand Layout")
@export var slot_positions: Array[Vector2] = [
	Vector2(480, 50),    # HandSlot1 position - centered horizontally
	Vector2(640, 50),    # HandSlot2 position  
	Vector2(800, 50),    # HandSlot3 position
	Vector2(960, 50)     # HandSlot4 position
]
@export var slot_rotations: Array[float] = [0.0, 0.0, 0.0, 0.0]  # Rotation for each slot
@export var slot_scales: Array[Vector2] = [
	Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE
]

@export_group("Hand Behavior")
@export var max_cards: int = 4
@export var auto_arrange: bool = true  # Automatically arrange cards when added
@export var debug_layout: bool = false  # Force layout update in editor

@export_group("Hover Effects")
@export var hover_scale: float = 1.5  # Scale factor when hovering
@export var hover_lift: float = -100.0  # How much to move card up when hovered
@export var displacement_amount: float = 80.0  # How much to push adjacent cards
@export var hover_duration: float = 0.2  # Tween duration for hover effects
@export var enable_tooltips: bool = true  # Show tooltips on hover

# Hand slot nodes
var hand_slots: Array[Node] = []

# Hover state tracking
var hovered_card: Node = null
var original_positions: Array[Vector2] = []
var original_scales: Array[Vector2] = []
var original_z_indices: Array[int] = []
var is_hover_active: bool = false
var hover_tween: Tween
var tooltip_panel: Control

# Debounce settings to avoid rapid enter/exit flicker when both SubViewport and card
# signals may fire. Time is in seconds.
var hover_cooldown: float = 0.0

func _ready():
	# Debug: Print the export values to verify they're loaded
	print("[PlayerHand] Loaded slot_positions: ", slot_positions)
	print("[PlayerHand] slot_positions array size: ", slot_positions.size())
	
	# Ensure PlayerHand can receive mouse input
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Reset anchors and set explicit size
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var viewport_size = get_viewport().get_visible_rect().size
	size = viewport_size
	print("[PlayerHand] Size set to viewport size: ", size)
	print("[PlayerHand] Position: ", position, " Global position: ", global_position)
	
	# Auto-center card positions based on viewport width
	_calculate_centered_positions()
	
	# Find all hand slot nodes
	hand_slots = [
		get_node_or_null("HandSlot1"),
		get_node_or_null("HandSlot2"), 
		get_node_or_null("HandSlot3"),
		get_node_or_null("HandSlot4")
	]
	
	print("[PlayerHand] Hand initialized with ", hand_slots.size(), " slots")
	
	# Defer layout application until after the scene is fully ready
	call_deferred("apply_slot_layout")
	
	# Set up hover system after layout is applied
	call_deferred("_setup_hover_system")

# Force layout update (for debugging)
func _process(_delta):
	if debug_layout:
		apply_slot_layout()
		debug_layout = false

# Calculate centered positions for cards based on viewport size
func _calculate_centered_positions():
	var viewport_size = get_viewport().get_visible_rect().size
	var card_width = 200.0  # Standard card width
	var card_spacing = 160.0  # Space between cards
	var total_width = (hand_slots.size() * card_width) + ((hand_slots.size() - 1) * card_spacing)
	var start_x = (viewport_size.x - total_width) / 2.0
	var y_position = 50.0  # Fixed Y position from top
	
	# Update slot_positions array with centered positions
	for i in range(hand_slots.size()):
		var x_position = start_x + (i * (card_width + card_spacing))
		slot_positions[i] = Vector2(x_position, y_position)
	
	print("[PlayerHand] Calculated centered positions: ", slot_positions)

# Handle mouse input for hover detection (backup method)
func _gui_input(event):
	if event is InputEventMouseMotion:
		var local_pos = event.position
		
		# Account for PlayerHand scaling - transform mouse position to match card coordinates
		var actual_pos = local_pos * scale
		print("[PlayerHand] Mouse transformed position: ", actual_pos, " (original: ", local_pos, ")")
		
		# Check which card slot the mouse is over
		for i in range(hand_slots.size()):
			var slot = hand_slots[i]
			if slot and slot.visible and slot is Control:
				var control_slot = slot as Control
				var card_rect = Rect2(control_slot.position, control_slot.size * control_slot.scale)
				
				if card_rect.has_point(actual_pos):
					print("[PlayerHand] Mouse over card ", i, " rect: ", card_rect)
					if not is_hover_active:
						_on_card_hover_start(i)
				elif is_hover_active and hovered_card == slot:
					_on_card_hover_end(i)

# Apply the exported layout settings to hand slots
func apply_slot_layout():
	print("[PlayerHand] Applying slot layout with ", slot_positions.size(), " positions")
	for i in range(min(hand_slots.size(), slot_positions.size())):
		var slot = hand_slots[i]
		if slot and slot is Control:
			var control_slot = slot as Control
			# Force to use position instead of anchors
			control_slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			# Set position directly  
			control_slot.position = slot_positions[i]
			# Make sure size is preserved
			control_slot.size = Vector2(200, 280)  # Standard card size
			
			# DON'T override z_index - let the scene file values take precedence
			# The scene file already has the correct z_index values: 3, 2, 1, 0
			
			if i < slot_rotations.size():
				control_slot.rotation_degrees = slot_rotations[i]
			if i < slot_scales.size():
				control_slot.scale = slot_scales[i]
			
			print("[PlayerHand] Slot ", i+1, " positioned at ", slot_positions[i], " z_index: ", control_slot.z_index, " (actual pos: ", control_slot.position, ") size: ", control_slot.size)
		elif slot and slot is Node2D:
			slot.position = slot_positions[i]
			# DON'T override z_index for Node2D either
			if i < slot_rotations.size():
				slot.rotation_degrees = slot_rotations[i]
			if i < slot_scales.size():
				slot.scale = slot_scales[i]
			
			print("[PlayerHand] Slot ", i+1, " (Node2D) positioned at ", slot_positions[i], " z_index: ", slot.z_index)

# Get the next available hand slot
func get_next_empty_slot() -> Node:
	for slot in hand_slots:
		if slot and not slot.visible:
			return slot
	return null

# Get a specific hand slot by index
func get_slot(index: int) -> Node:
	if index >= 0 and index < hand_slots.size():
		return hand_slots[index]
	return null

# Get the position for a specific hand slot index
func get_slot_position(index: int) -> Vector2:
	if index >= 0 and index < slot_positions.size():
		return slot_positions[index]
	else:
		push_warning("[PlayerHand] Slot position index out of range: ", index)
		return Vector2.ZERO

# Check if hand is full
func is_full() -> bool:
	for slot in hand_slots:
		if slot and not slot.visible:
			return false
	return true

# Get number of cards in hand
func get_card_count() -> int:
	var count = 0
	for slot in hand_slots:
		if slot and slot.visible:
			count += 1
	return count

# Clear all cards from hand
func clear_hand():
	for slot in hand_slots:
		if slot:
			slot.visible = false
			if slot.has_method("display"):
				# Reset to empty state
				var empty_data = load("res://scripts/resources/CardBack.tres")  
				slot.call_deferred("display", empty_data)

# Add a card to the next available slot
func add_card_to_hand(card_data: CustomCardData) -> bool:
	var empty_slot = get_next_empty_slot()
	if empty_slot:
		if empty_slot.has_method("display"):
			empty_slot.call_deferred("display", card_data)
			empty_slot.visible = true
			return true
	return false

# Public method to force layout update (callable from editor/inspector)
func update_layout():
	apply_slot_layout()
	print("[PlayerHand] Layout manually updated")

# === HOVER SYSTEM ===

# Set up the complete hover system after layout is applied
func _setup_hover_system():
	print("[PlayerHand] Setting up hover system...")
	
	# Store original positions and scales for hover reset
	_store_original_states()
	
	# Set up hover detection for each card
	_setup_hover_detection()
	
	# Create tooltip panel
	if enable_tooltips:
		_create_tooltip_panel()
	
	print("[PlayerHand] Hover system setup complete!")

# Store original card states for reset
func _store_original_states():
	original_positions.clear()
	original_scales.clear() 
	original_z_indices.clear()
	
	for i in range(hand_slots.size()):
		var slot = hand_slots[i]
		if slot:
			# Work with any Control node type
			if slot is Control:
				var control_slot = slot as Control
				original_positions.append(control_slot.position)
				original_scales.append(control_slot.scale)
				original_z_indices.append(control_slot.z_index)
				print("[PlayerHand] Stored original state for slot ", i, ": pos=", control_slot.position, " scale=", control_slot.scale)

# Set up mouse detection for each card
func _setup_hover_detection():
	for i in range(hand_slots.size()):
		var slot = hand_slots[i]
		if slot:
			# SubViewportContainer nodes need mouse_filter set to PASS to receive hover events
			if slot is SubViewportContainer:
				var svc = slot as SubViewportContainer
				svc.mouse_filter = Control.MOUSE_FILTER_PASS
				# Also ensure the internal SubViewport receives mouse input
				var viewport = svc.get_child(0)
				if viewport is SubViewport:
					viewport.handle_input_locally = false
					viewport.physics_object_picking = true
				print("[PlayerHand] Setting up hover on SubViewportContainer slot ", i, " at position ", svc.position)
			
			# Connect mouse signals - works for all Control-derived nodes
			if slot is Control:
				var control_slot = slot as Control
				# Ensure the control can receive mouse events
				control_slot.mouse_filter = Control.MOUSE_FILTER_PASS
				
				# Connect hover signals (simple print-only handlers)
				if not control_slot.is_connected("mouse_entered", Callable(self, "_on_card_hover_start")):
					control_slot.connect("mouse_entered", Callable(self, "_on_card_hover_start").bind(i))
					print("[PlayerHand] Connected mouse_entered for slot ", i, " size: ", control_slot.size)
				if not control_slot.is_connected("mouse_exited", Callable(self, "_on_card_hover_end")):
					control_slot.connect("mouse_exited", Callable(self, "_on_card_hover_end").bind(i))
					print("[PlayerHand] Connected mouse_exited for slot ", i)

# Create tooltip panel
func _create_tooltip_panel():
	tooltip_panel = Panel.new()
	tooltip_panel.name = "CardTooltip"
	tooltip_panel.visible = false
	tooltip_panel.z_index = 1000  # Always on top
	
	# Style the panel (basic dark theme)
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.3, 0.9)  # Dark blue-gray
	style_box.border_width_left = 2
	style_box.border_width_right = 2 
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	tooltip_panel.add_theme_stylebox_override("panel", style_box)
	
	# Add tooltip content container
	var vbox = VBoxContainer.new()
	vbox.name = "TooltipContent"
	tooltip_panel.add_child(vbox)
	
	# Title label
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title_label)
	
	# Description label  
	var desc_label = Label.new()
	desc_label.name = "DescriptionLabel"
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 1.0))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(250, 0)
	vbox.add_child(desc_label)
	
	# Action button
	var action_button = Button.new()
	action_button.name = "ActionButton"
	action_button.text = "Use Card"
	vbox.add_child(action_button)
	
	add_child(tooltip_panel)

# Handle card hover start
func _on_card_hover_start(card_index: int):
	# Only act if the card in this slot is the topmost visible card under the mouse
	var top_idx = _get_topmost_visible_slot_under_mouse()
	if top_idx != card_index:
		return

	print("[PlayerHand] Hover START on card ", card_index)
	# Simple print-only behavior: no animations, no tooltips
	var card = hand_slots[card_index]
	if card:
		print("[PlayerHand] Slot ", card_index, " enter; card visible=", card.visible)

# Handle card hover end  
func _on_card_hover_end(_card_index: int):
	print("[PlayerHand] Hover END on card ", _card_index)
	var card = hand_slots[_card_index]
	if card:
		print("[PlayerHand] Slot ", _card_index, " exit; card visible=", card.visible)


# Find the index of the topmost visible hand slot (card) under the current mouse position.
# Prefers higher z_index. Returns -1 if none.
func _get_topmost_visible_slot_under_mouse() -> int:
	var pos = get_global_mouse_position()
	var best_idx: int = -1
	var best_z: int = -2147483648
	for i in range(hand_slots.size()):
		var slot = hand_slots[i]
		if not slot:
			continue
		if not slot.visible:
			continue
		if not (slot is Control):
			continue
		var c = slot as Control
		# Use the control's global rect (accounts for scale/position)
		if not c.get_global_rect().has_point(pos):
			continue
		if c.z_index > best_z:
			best_z = c.z_index
			best_idx = i
	return best_idx

# Animate hover start effects
func _animate_hover_start(card_index: int):
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	
	var card = hand_slots[card_index] as Control
	
	# Scale up and lift the hovered card
	hover_tween.tween_property(card, "scale", original_scales[card_index] * hover_scale, hover_duration)
	hover_tween.tween_property(card, "position", original_positions[card_index] + Vector2(0, hover_lift), hover_duration)
	
	# Raise z-index to appear above others
	card.z_index = 100
	
	# Push adjacent cards away
	for i in range(hand_slots.size()):
		if i == card_index or not hand_slots[i].visible:
			continue
			
		var adjacent_card = hand_slots[i] as Control
		var displacement = Vector2.ZERO
		
		# Left cards move left, right cards move right
		if i < card_index:
			displacement.x = -displacement_amount
		else:
			displacement.x = displacement_amount
			
		hover_tween.tween_property(adjacent_card, "position", original_positions[i] + displacement, hover_duration)

# Animate hover end effects
func _animate_hover_end():
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	
	# Reset all cards to original states
	for i in range(hand_slots.size()):
		var card = hand_slots[i]
		if not card or not card.visible:
			continue
			
		var control_card = card as Control
		hover_tween.tween_property(control_card, "scale", original_scales[i], hover_duration)
		hover_tween.tween_property(control_card, "position", original_positions[i], hover_duration)
		control_card.z_index = original_z_indices[i]

# Show tooltip for hovered card
func _show_tooltip(card: Node, card_index: int):
	if not tooltip_panel:
		return
		
	# Get card data if available
	var card_data: CustomCardData = null
	if card.has_method("get_card_data"):
		card_data = card.call("get_card_data")
	
	# Update tooltip content
	var title_label = tooltip_panel.get_node("TooltipContent/TitleLabel") as Label
	var desc_label = tooltip_panel.get_node("TooltipContent/DescriptionLabel") as Label
	var action_button = tooltip_panel.get_node("TooltipContent/ActionButton") as Button
	
	if card_data:
		title_label.text = card_data.card_name if card_data.card_name else "Card"
		desc_label.text = card_data.card_description if card_data.card_description else "No description available"
		action_button.text = "Swap cards" if "Swap" in card_data.card_name else "Draw new card"
	else:
		title_label.text = "Card " + str(card_index + 1)
		desc_label.text = "Card effect description would appear here"
		action_button.text = "Use Card"
	
	# Position tooltip near the card but ensure it stays on screen
	var card_control = card as Control
	var card_global_pos = card_control.global_position
	var _card_size = card_control.size * card_control.scale
	
	tooltip_panel.position = Vector2(
		card_global_pos.x - 125,  # Center horizontally on card
		card_global_pos.y - 200   # Above the card
	)
	
	# Make sure tooltip stays on screen
	var screen_size = get_viewport().get_visible_rect().size
	tooltip_panel.position.x = clamp(tooltip_panel.position.x, 10, screen_size.x - 300)
	tooltip_panel.position.y = clamp(tooltip_panel.position.y, 10, screen_size.y - 150)
	
	tooltip_panel.visible = true