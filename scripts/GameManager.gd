extends Node2D

const CardScene = preload("res://scenes/cards.tscn")

# Mark script to preload to avoid shader/material issues
const CardGDScript = preload("res://scripts/NewCard.gd")

@export var card_data: CustomCardData
@export_file("*.tres") var card_data_path: String
@export var card_key: String = "" # e.g., "TwoSwap" will load res://scripts/resources/TwoSwap.tres
@export var CardPosition: Vector2 = Vector2.ZERO
@export var CardScale: Vector2 = Vector2.ONE
@export var debug_logging: bool = true

# Animation settings
@export_group("Card Animation")
@export var card_draw_flip_duration: float = 0.8
@export var card_draw_move_duration: float = 1.2
@export var card_draw_rotation: float = 15.0
@export var card_final_scale: Vector2 = Vector2(0.8, 0.8)

var _hand_index: int = 0


func _ready():
	# Do not create any test card at startup; cards should appear only when drawn.
	# Seed RNG for random draws
	randomize()

	# Force reasonable scale if it's too small
	if card_final_scale.x < 0.1 or card_final_scale.y < 0.1:
		push_warning("[GM] Card final scale was too small: ", card_final_scale, " - forcing to (0.8, 0.8)")
		card_final_scale = Vector2(0.8, 0.8)
	
	# Also check CardScale (starting scale)
	if CardScale.x < 0.01 or CardScale.y < 0.01:
		push_warning("[GM] Card starting scale was too small: ", CardScale, " - forcing to (0.42, 0.42)")
		CardScale = Vector2(0.42, 0.42)  # Match the deck scale from main.tscn
	
	# If deck and hand should be same scale, match them
	card_final_scale = CardScale
	
	if debug_logging:
		print("[GM] Animation scale settings - start: ", CardScale, " -> final: ", card_final_scale)

	# Connect to Deck's request_draw signal if Deck exists in the scene
	var deck_node = get_node_or_null("Deck")
	if not deck_node:
		deck_node = get_tree().get_root().find_node("Deck", true, false)
	if deck_node and deck_node.has_signal("request_draw"):
		if not deck_node.is_connected("request_draw", Callable(self, "_on_deck_request_draw")):
			deck_node.connect("request_draw", Callable(self, "_on_deck_request_draw"))
	if debug_logging:
		print("[GM] Animation settings - flip_duration:", card_draw_flip_duration, " move_duration:", card_draw_move_duration, " scale:", card_final_scale)	# Hide any PlayerHand placeholders so no cards are visible until drawn
	var ph = get_node_or_null("PlayerHand")
	if not ph:
		ph = get_tree().get_root().find_node("PlayerHand", true, false)
	if ph:
		for slot_name in ["HandSlot1", "HandSlot2", "HandSlot3", "HandSlot4"]:
			if ph.has_node(slot_name):
				var slot = ph.get_node(slot_name)
				if slot and slot is Node:
					slot.visible = false

func create_card(data: CustomCardData):
	# 1. Instantiate blank card scene
	var new_card = CardScene.instantiate()
	
	# 2. Important: Get references to labels
	var top_label = new_card.find_child("TopValue", true, false)
	var bottom_label = new_card.find_child("BottomValue", true, false)
	
	# 3. Add to the tree so @onready paths are valid
	add_child(new_card)
	
	# 4. Apply exported transform settings
	new_card.position = CardPosition
	new_card.scale = CardScale
	
	if debug_logging:
		var sz := Vector2.ZERO
		if new_card is Control:
			sz = (new_card as Control).size
		print("[GM] Card instantiated: pos=", new_card.position, " scale=", new_card.scale, " size=", sz)
	
	# 5. Labels are now positioned directly through scene settings
	if debug_logging and top_label:
		print("[GM] Top label position: ", top_label.offset_left, ", ", top_label.offset_top)
			
	if debug_logging and bottom_label:
		print("[GM] Bottom label position: ", bottom_label.offset_left, ", ", bottom_label.offset_top)
	
	# 6. Defer display until after the node finishes entering the tree
	new_card.call_deferred("display", data)
	if debug_logging:
		print("[GM] display() deferred with data: ", data)

func _on_deck_request_draw() -> void:
	print("[GM] _on_deck_request_draw() called!")
	# When the deck requests a draw, choose a random front-facing card and animate it to PlayerHand
	var candidates := [
		"res://scripts/resources/TwoDraw.tres",
		"res://scripts/resources/TwoSwap.tres",
		"res://scripts/resources/FourDraw.tres",
		"res://scripts/resources/FourSwap.tres",
		"res://scripts/resources/SixDraw.tres",
		"res://scripts/resources/SixSwap.tres",
		"res://scripts/resources/EightDraw.tres",
		"res://scripts/resources/EightSwap.tres",
		"res://scripts/resources/TenDraw.tres",
		"res://scripts/resources/TenSwap.tres",
	]
	# pick a random card resource
	var idx := randi() % candidates.size()
	var chosen_path: String = candidates[idx]
	var chosen: CustomCardData = load(chosen_path) as CustomCardData
	if not chosen:
		push_warning("[GM] Failed to load chosen card resource: %s" % chosen_path)
		return

	# Find PlayerHand node and the target slot
	var ph := get_node_or_null("PlayerHand")
	if not ph:
		# try root-level path
		ph = get_node_or_null("/root/Node2D/PlayerHand")
	if not ph:
		push_warning("[GM] PlayerHand node not found; cannot place drawn card")
		if debug_logging:
			print("[GM] Available nodes: ", get_children())
		return
	else:
		if debug_logging:
			print("[GM] Found PlayerHand at: ", ph.get_path())

	# Find Deck node to get the starting position
	var deck_node = get_node_or_null("Deck")
	if not deck_node:
		push_warning("[GM] Deck node not found; cannot animate card draw")
		return
	
	# Get deck position as starting point
	var deck_pos = deck_node.global_position
	
	# Find target slot and position
	var placeholders := ["HandSlot1", "HandSlot2", "HandSlot3", "HandSlot4"]
	var target_position: Vector2
	var target_slot: Node = null
	
	if _hand_index < placeholders.size():
		var target_name: String = placeholders[_hand_index]
		if ph.has_node(target_name):
			target_slot = ph.get_node(target_name)
			
			# Check if PlayerHand has the custom positioning method
			if ph.has_method("get_slot_position"):
				target_position = ph.get_slot_position(_hand_index)
				if debug_logging:
					print("[GM] Targeting slot ", target_name, " (index ", _hand_index, ") at custom position ", target_position)
			else:
				# Fall back to using the actual node's position
				target_position = target_slot.global_position  
				if debug_logging:
					print("[GM] Targeting slot ", target_name, " (index ", _hand_index, ") at node position ", target_position)
					print("[GM] PlayerHand doesn't have custom positioning, using node positions")
		else:
			push_warning("[GM] Target slot %s not found" % target_name)
			return
	else:
		# No more slots available
		push_warning("[GM] No more hand slots available")
		return
	
	# Create and start the card draw animation
	var animator = CardDrawAnimation.new()
	add_child(animator)
	
	# Set animation parameters from exports
	animator.flip_duration = card_draw_flip_duration
	animator.move_duration = card_draw_move_duration
	animator.rotation_angle = card_draw_rotation
	animator.final_scale = card_final_scale
	
	# Safety check for reasonable scale values
	if card_final_scale.x < 0.1 or card_final_scale.y < 0.1:
		push_warning("[GM] Card scale is very small: ", card_final_scale, " - this may make cards invisible!")
		card_final_scale = Vector2(0.8, 0.8)  # Use reasonable default
		animator.final_scale = card_final_scale
	
	# Connect to animation finished signal
	animator.connect("animation_finished", Callable(self, "_on_card_animation_finished").bind(chosen, target_slot))
	
	# Start the animation from deck to hand slot with proper scaling
	# CardScale is the deck's scale, card_final_scale is the target scale in hand
	animator.animate_card_draw(chosen, deck_pos, target_position, 0.0, card_final_scale, CardScale)
	
	if debug_logging:
		print("[GM] Started animated card draw: ", chosen_path, " from ", deck_pos, " to ", target_position)
		print("[GM] Scale animation: ", CardScale, " -> ", card_final_scale)
	
	_hand_index += 1

	# Update deck visual count if deck exposes set_count
	if deck_node and deck_node.has_method("get_count") and deck_node.has_method("set_count"):
		var current = deck_node.call("get_count")
		deck_node.call("set_count", max(0, int(current) - 1))

# Called when card draw animation finishes
func _on_card_animation_finished(animated_card: Control, drawn_card_data: CustomCardData, target_slot: Node):
	# Replace the target slot with the animated card or update it
	if target_slot and target_slot.has_method("display"):
		# Update the existing slot to show the card
		target_slot.call_deferred("display", drawn_card_data)
		target_slot.visible = true
		
		# Clean up the animated card
		if animated_card and animated_card.get_parent():
			animated_card.get_parent().remove_child(animated_card)
			animated_card.queue_free()
	else:
		# Move the animated card to the target position
		if animated_card and target_slot:
			var parent = target_slot.get_parent()
			if animated_card.get_parent():
				animated_card.get_parent().remove_child(animated_card)
			parent.add_child(animated_card)
			animated_card.position = target_slot.position
			animated_card.visible = true
	
	if debug_logging:
		print("[GM] Card animation finished and placed in hand slot")
