extends Control
class_name PlayerHand

# Exportable hand slot positions and settings
@export_group("Hand Layout")
@export var slot_positions: Array[Vector2] = [
	Vector2(162, 844),   # HandSlot1 position
	Vector2(412, 835),   # HandSlot2 position  
	Vector2(630, 835),   # HandSlot3 position
	Vector2(866, 835)    # HandSlot4 position
]
@export var slot_rotations: Array[float] = [0.0, 0.0, 0.0, 0.0]  # Rotation for each slot
@export var slot_scales: Array[Vector2] = [
	Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE
]

@export_group("Hand Behavior")
@export var max_cards: int = 4
@export var auto_arrange: bool = true  # Automatically arrange cards when added

# Hand slot nodes
var hand_slots: Array[Node] = []

func _ready():
	# Find all hand slot nodes
	hand_slots = [
		get_node_or_null("HandSlot1"),
		get_node_or_null("HandSlot2"), 
		get_node_or_null("HandSlot3"),
		get_node_or_null("HandSlot4")
	]
	
	# Apply exported positions to slots
	apply_slot_layout()
	
	print("[PlayerHand] Hand initialized with ", hand_slots.size(), " slots")

# Apply the exported layout settings to hand slots
func apply_slot_layout():
	for i in range(min(hand_slots.size(), slot_positions.size())):
		var slot = hand_slots[i]
		if slot and slot is Node2D:
			slot.position = slot_positions[i]
			if i < slot_rotations.size():
				slot.rotation_degrees = slot_rotations[i]
			if i < slot_scales.size():
				slot.scale = slot_scales[i]
			
			print("[PlayerHand] Slot ", i+1, " positioned at ", slot_positions[i])

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