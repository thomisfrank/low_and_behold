extends Control

# Minimal OpponentHand
# - Mirrors PlayerHand layout/slot API but without hover/tooltips
# - Adds real card instances to slots but forces their visual to show the back

@export_group("Hand Layout")
@export var slot_positions: Array[Vector2] = [
	Vector2(688, 835),
	Vector2(805, 840),
	Vector2(912, 830),
	Vector2(1019, 835)
]
@export var slot_rotations: Array[float] = [0.0, 0.0, 0.0, 0.0]
@export var slot_scales: Array[Vector2] = [Vector2(0.32, 0.32), Vector2(0.32, 0.32), Vector2(0.32, 0.32), Vector2(0.32, 0.32)]

@export_group("Hand Behavior")
@export var max_cards: int = 4
@export var auto_arrange: bool = true
@export var debug_layout: bool = false

var hand_slots: Array[Node] = []
var _processed_slots: Array = []

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Set layout area to viewport size
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var viewport_size = get_viewport().get_visible_rect().size
	size = viewport_size

	# collect slot nodes (must match the scene's children names)
	hand_slots = [
		get_node_or_null("HandSlot1"),
		get_node_or_null("HandSlot2"),
		get_node_or_null("HandSlot3"),
		get_node_or_null("HandSlot4")
	]
	if debug_layout:
		print("[OppHand] slots:", hand_slots)

	# Only compute centered positions if auto_arrange is enabled. Otherwise
	# honor inspector-provided `slot_positions` and ensure the array is large enough.
	if auto_arrange:
		_calculate_centered_positions()
	else:
		while slot_positions.size() < hand_slots.size():
			slot_positions.append(Vector2.ZERO)

	# Start with an empty opponent hand (no visible cards)
	clear_hand()

	call_deferred("apply_slot_layout")

# Layout helpers
func _calculate_centered_positions():
	var viewport_size = get_viewport().get_visible_rect().size
	var card_width = 200.0
	var card_spacing = 160.0
	var total_width = (hand_slots.size() * card_width) + ((hand_slots.size() - 1) * card_spacing)
	var start_x = (viewport_size.x - total_width) / 2.0
	var y_position = 50.0

	for i in range(hand_slots.size()):
		var x_position = start_x + (i * (card_width + card_spacing))
		if i >= slot_positions.size():
			slot_positions.append(Vector2(x_position, y_position))
		else:
			slot_positions[i] = Vector2(x_position, y_position)

func apply_slot_layout():
	# Use inspector positions unless auto_arrange is enabled
	if auto_arrange:
		_calculate_centered_positions()
	else:
		while slot_positions.size() < hand_slots.size():
			slot_positions.append(Vector2.ZERO)

	for i in range(min(hand_slots.size(), slot_positions.size())):
		var slot = hand_slots[i]
		if not slot:
			continue
		if slot is Control:
			var control_slot = slot as Control
			control_slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			control_slot.position = slot_positions[i]
			control_slot.size = Vector2(200, 280)
			if i < slot_rotations.size():
				control_slot.rotation_degrees = slot_rotations[i]
			if i < slot_scales.size():
				control_slot.scale = slot_scales[i]
		else:
			slot.position = slot_positions[i]
			if i < slot_rotations.size():
				slot.rotation_degrees = slot_rotations[i]
			if i < slot_scales.size():
				slot.scale = slot_scales[i]

# API similar to PlayerHand
func get_next_empty_slot() -> Node:
	for slot in hand_slots:
		if slot and not slot.visible:
			return slot
	return null

func get_slot(index: int) -> Node:
	if index >= 0 and index < hand_slots.size():
		return hand_slots[index]
	return null

func get_slot_position(index: int) -> Vector2:
	if index >= 0 and index < slot_positions.size():
		return slot_positions[index]
	push_warning("[OppHand] Slot position index out of range: %s" % index)
	return Vector2.ZERO

func get_card_count() -> int:
	var count = 0
	for slot in hand_slots:
		if slot and slot.visible:
			count += 1
	return count

func clear_hand():
	for slot in hand_slots:
		if slot:
			slot.visible = false
			if slot.has_method("display"):
				var empty_data = load("res://scripts/resources/CardBack.tres")
				if debug_layout:
					print("[OppHand] clear_hand: calling display(CardBack) on", slot)
				slot.call_deferred("display", empty_data)

# Add a real card to the next available slot, but force the visual back
func add_card_to_hand(card_data: CustomCardData) -> bool:
	var empty_slot = get_next_empty_slot()
	if empty_slot:
		if empty_slot.has_method("display"):
			if debug_layout:
				print("[OppHand] add_card_to_hand: display(face) on slot", empty_slot)
			empty_slot.call_deferred("display", card_data)
			empty_slot.visible = true
			# ensure visual back is shown after display finishes
			call_deferred("_force_show_back_on", empty_slot)
			return true
	return false

func _force_show_back_on(slot: Node) -> void:
	if not slot:
		return
	# paths match NewCard.gd scene structure
	var back = slot.get_node_or_null("CardsViewport/CardsLabel/CardBackground/Padding/BackFrame")
	var front = slot.get_node_or_null("CardsViewport/CardsLabel/CardBackground/Padding/FrontFrame")
	var values = slot.get_node_or_null("CardsViewport/CardsLabel/Values")
	if back:
		back.visible = true
	if front:
		front.visible = false
	if values:
		values.visible = false

func update_layout():
	apply_slot_layout()


func _process(_delta: float) -> void:
	# Detect newly-visible slot nodes and force them to show the back
	for slot in hand_slots:
		if not slot:
			continue
		# if a slot became visible and we haven't processed it yet
		if slot.visible and _processed_slots.find(slot) == -1:
			_force_show_back_on(slot)
			_processed_slots.append(slot)
