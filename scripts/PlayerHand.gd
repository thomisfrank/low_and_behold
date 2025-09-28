# =====================================
# PlayerHand.gd
# Manages player hand, card layout, drag-and-drop, and hover effects
# =====================================
extends Control
class_name PlayerHand

# Layout & settings
@export_group("Hand Layout")
@export var slot_positions: Array[Vector2] = [Vector2(480, 50), Vector2(640, 50), Vector2(800, 50), Vector2(960, 50)]
@export var slot_rotations: Array[float] = [0.0, 0.0, 0.0, 0.0]
@export var slot_scales: Array[Vector2] = [Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE]
@export_group("Hand Behavior")
@export var max_cards: int = 4
@export_group("Hover Effects")
@export var hover_scale: float = 1.5
@export var hover_lift: float = -100.0
@export var displacement_amount: float = 80.0
@export var hover_duration: float = 0.2
@export var hover_margin: float = 8.0
@export var hover_position_offset: Vector2 = Vector2(0, -100)
@export var hover_rotation: float = 0.0

# Internal state
var managed_cards: Array[Node] = []
var card_data_map: Array[Resource] = []
var hovered_index: int = -1
var hover_tween: Tween
var dragging: bool = false
var drag_index: int = -1
var drag_offset: Vector2 = Vector2.ZERO
var play_area_node: Control = null

# Signal to notify GameManager when a card is played via drag
signal card_played(card_index)

func _ready():
	# Initialize hand and connect signals
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	managed_cards.resize(max_cards)
	card_data_map.resize(max_cards)
	for i in range(max_cards):
		managed_cards[i] = null
		card_data_map[i] = null
	if get_tree().get_current_scene().has_node("GameManager"):
		var gm = get_tree().get_current_scene().get_node("GameManager")
		connect("card_played", Callable(gm, "player_action_from_hand"))
	var main = get_tree().get_current_scene().get_node_or_null("main")
	if main:
		var ui_layer = main.get_node_or_null("UILayer")
		if ui_layer:
			play_area_node = ui_layer.get_node_or_null("PlayArea")
			if play_area_node:
				play_area_node.visible = true

func _process(_delta):
	# Handle card dragging and hover polling
	if dragging and drag_index != -1:
		var card = managed_cards[drag_index]
		if is_instance_valid(card):
			card.position = get_global_mouse_position() - drag_offset
	if dragging:
		return
	var top_idx = _get_topmost_card_under_mouse()
	if top_idx != hovered_index:
		if hovered_index != -1:
			_on_card_hover_end()
		if top_idx != -1:
			_on_card_hover_start(top_idx)
	elif top_idx == -1 and hovered_index != -1:
		_on_card_hover_end()
# === Drag-and-Drop Logic ===
func _gui_input(event):
	# Handle drag and drop to play cards
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			var top_idx = _get_topmost_card_under_mouse()
			if top_idx != -1:
				_on_card_drag_start(top_idx)
		else:
			_on_card_drag_end()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
		_on_card_drag_end()



# === Play Card API (called by GameManager) ===
func play_card(card_index: int):
	if card_index < 0 or card_index >= managed_cards.size():
		push_warning("[PlayerHand] play_card: Invalid index %d" % card_index)
		return
	var card = managed_cards[card_index]
	if is_instance_valid(card) and card.has_method("locked") and card.locked:
		push_warning("[PlayerHand] play_card: Card at %d is locked and cannot be played." % card_index)
		return
	if is_instance_valid(card):
		card.queue_free()
		managed_cards[card_index] = null
		card_data_map[card_index] = null
# Discard a card at the given index
func discard_card(card_index: int):
	if card_index < 0 or card_index >= managed_cards.size():
		push_warning("[PlayerHand] discard_card: Invalid index %d" % card_index)
		return
	var card = managed_cards[card_index]
	if is_instance_valid(card):
		card.queue_free()
		managed_cards[card_index] = null
		card_data_map[card_index] = null

# Remove all cards from hand (for round discard)
func discard_all_cards():
		for i in range(managed_cards.size()):
			var card = managed_cards[i]
			if is_instance_valid(card):
				card.queue_free()
			managed_cards[i] = null
			card_data_map[i] = null

func get_card_count() -> int:
	var count = 0
	for card in managed_cards:
		if is_instance_valid(card):
			count += 1
	return count

# Get the last played Swap card slot (for swap effect)
func get_last_played_swap_slot():
	for i in range(managed_cards.size()-1, -1, -1):
		var card = managed_cards[i]
		var data = card_data_map[i]
		if is_instance_valid(card) and data and data.get("effect") == "Swap":
			return card
	return null

# Lock/unlock a card at the given index
func lock_card(card_index: int):
	var card = managed_cards[card_index]
	if is_instance_valid(card) and card.has_method("lock_card"):
		card.lock_card()

func unlock_card(card_index: int):
	var card = managed_cards[card_index]
	if is_instance_valid(card) and card.has_method("unlock_card"):
		card.unlock_card()

## === PlayerHand: Core Logic ===

# This is the new "handover" function called by GameManager.
func receive_card_node(card_node: Control, slot_index: int, card_data: CustomCardData):
	if slot_index < 0 or slot_index >= max_cards:
		push_warning("[PlayerHand] Invalid slot_index %d. Cannot place card." % slot_index)
		card_node.queue_free() # Clean up the orphaned card
		return

	# If there's already a card in that slot, remove it first
	if is_instance_valid(managed_cards[slot_index]):
		managed_cards[slot_index].queue_free()

	# Take ownership of the card
	if card_node.get_parent():
		card_node.get_parent().remove_child(card_node)
	add_child(card_node)
	
	# Store the card and its data
	managed_cards[slot_index] = card_node
	card_data_map[slot_index] = card_data

	# Only set position/scale/rotation if the card is not already in the correct place
	var should_snap = false
	if card_node.position.distance_to(slot_positions[slot_index]) > 2.0:
		should_snap = true
	if card_node.scale.distance_to(slot_scales[slot_index]) > 0.05:
		should_snap = true
	if abs(card_node.rotation_degrees - slot_rotations[slot_index]) > 1.0:
		should_snap = true
	if should_snap:
		card_node.position = slot_positions[slot_index]
		card_node.scale = slot_scales[slot_index]
		card_node.rotation_degrees = slot_rotations[slot_index]
	# Always set Z-index so cards stack left-to-right, first card at the bottom
	card_node.z_index = max_cards - slot_index

# === Hover Helpers ===
func _get_topmost_card_under_mouse() -> int:
	# Returns the index of the topmost card under the mouse, or -1 if none
	var mouse_pos = get_local_mouse_position()
	for i in range(managed_cards.size()-1, -1, -1):
		var card = managed_cards[i]
		if is_instance_valid(card):
			var card_size = card.size * card.scale
			var rect = Rect2(card.position - card_size / 2, card_size)
			if rect.has_point(mouse_pos):
				return i
	return -1

func _on_card_hover_start(idx: int):
	hovered_index = idx
	var card = managed_cards[idx]
	if is_instance_valid(card):
		card.scale = slot_scales[idx] * hover_scale
		card.position += hover_position_offset
		card.rotation_degrees = hover_rotation

func _on_card_hover_end():
	if hovered_index == -1:
		return
	var card = managed_cards[hovered_index]
	if is_instance_valid(card):
		card.scale = slot_scales[hovered_index]
		card.position = slot_positions[hovered_index]
		card.rotation_degrees = slot_rotations[hovered_index]
	hovered_index = -1

func _on_card_drag_start(idx: int):
	dragging = true
	drag_index = idx
	var card = managed_cards[idx]
	if is_instance_valid(card):
		drag_offset = get_global_mouse_position() - card.position

func _on_card_drag_end():
	if dragging:
		dragging = false
		var card = managed_cards[drag_index]
		if is_instance_valid(card):
			if play_area_node and play_area_node.get_global_rect().has_point(get_global_mouse_position()):
				emit_signal("card_played", drag_index)
			else:
				# Snap back to hand
				card.position = slot_positions[drag_index]
				card.scale = slot_scales[drag_index]
				card.rotation_degrees = slot_rotations[drag_index]
		drag_index = -1
