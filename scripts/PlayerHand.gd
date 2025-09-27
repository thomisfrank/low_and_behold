# PlayerHand.gd (Complete Reworked Script)

extends Control
class_name PlayerHand

## === PlayerHand: Layout & Settings ===
@export_group("Hand Layout")
@export var slot_positions: Array[Vector2] = [
	Vector2(480, 50),
	Vector2(640, 50),
	Vector2(800, 50),
	Vector2(960, 50)
]
@export var slot_rotations: Array[float] = [0.0, 0.0, 0.0, 0.0]
@export var slot_scales: Array[Vector2] = [Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE]

@export_group("Hand Behavior")
@export var max_cards: int = 4

@export_group("Hover Effects")
@export var hover_scale: float = 1.5
@export var hover_lift: float = -100.0
@export var displacement_amount: float = 80.0
@export var hover_duration: float = 0.2

## === PlayerHand: Internal State ===
# This array will now hold the ACTUAL card nodes, not placeholders.
var managed_cards: Array[Node] = []
var card_data_map: Array[Resource] = []

var hovered_index: int = -1
var hover_tween: Tween

## === PlayerHand: Initialization ===
func _ready():
	# Set this container to span the screen to capture mouse events
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Initialize the arrays to the maximum card count
	managed_cards.resize(max_cards)
	card_data_map.resize(max_cards)
	for i in range(max_cards):
		managed_cards[i] = null
		card_data_map[i] = null

## === PlayerHand: Process & Hover Polling ===
func _process(_delta):
	# Continuously check which card is under the mouse
	var top_idx = _get_topmost_card_under_mouse()

	if top_idx != hovered_index:
		# Mouse moved off the old card, so end its hover effect
		if hovered_index != -1:
			_on_card_hover_end()
		
		# Mouse moved onto a new card, so start its hover effect
		if top_idx != -1:
			_on_card_hover_start(top_idx)

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

	# Apply the final layout position, scale, and rotation
	card_node.position = slot_positions[slot_index]
	card_node.scale = slot_scales[slot_index]
	card_node.rotation_degrees = slot_rotations[slot_index]
	# Set Z-index to ensure cards overlap correctly and can be hovered
	card_node.z_index = max_cards - slot_index
	
## === PlayerHand: Hover System ===

func _get_topmost_card_under_mouse() -> int:
	var mouse_pos = get_global_mouse_position()
	var best_idx = -1
	var best_z = -1

	# Iterate backwards to check topmost cards first
	for i in range(managed_cards.size() - 1, -1, -1):
		var card = managed_cards[i]
		if is_instance_valid(card) and card is Control:
			if card.get_global_rect().has_point(mouse_pos) and card.z_index > best_z:
				best_idx = i
				best_z = card.z_index
	
	return best_idx

func _on_card_hover_start(card_index: int):
	hovered_index = card_index
	_animate_hover(card_index)

func _on_card_hover_end():
	hovered_index = -1
	_animate_hover(-1) # Animate back to default state

func _animate_hover(target_index: int):
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween().set_parallel(true)

	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		if not is_instance_valid(card):
			continue

		var target_pos = slot_positions[i]
		var target_scale = slot_scales[i]
		var target_z = i # Default Z-index

		if target_index != -1: # A card is being hovered
			if i == target_index:
				# This is the hovered card, so lift and enlarge it
				target_pos += Vector2(0, hover_lift)
				target_scale *= hover_scale
				target_z = 100 # Bring to front
			else:
				# Displace adjacent cards
				var displacement = Vector2.ZERO
				if i < target_index:
					displacement.x = -displacement_amount
				else:
					displacement.x = displacement_amount
				target_pos += displacement
		
		# Animate the properties
		hover_tween.tween_property(card, "position", target_pos, hover_duration)
		hover_tween.tween_property(card, "scale", target_scale, hover_duration)
		card.z_index = target_z

## === PlayerHand: Public API (for GameManager) ===

# These functions are still needed by GameManager to know where to animate the card TO.
func get_slot_position(index: int): # The return type hint is removed to allow returning null
	if index >= 0 and index < slot_positions.size():
		# This part is the same: return the correct global position if the slot is valid.
		return global_position + slot_positions[index]
	else:
		# This is the change: return null to signal that the draw should fail.
		push_warning("[PlayerHand] Requested slot index %s is out of range." % index)
		return null
