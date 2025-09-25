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
var _card_layer: CanvasLayer  # Dedicated layer for animated cards
var _last_two_cards: Array[Dictionary] = []  # Track last 2 cards drawn as {value, effect, path}
var _current_hand_meta: Array[Dictionary] = [] # Track cards placed in the current hand (to enforce per-hand diversity)


func _ready():
	# Do not create any test card at startup; cards should appear only when drawn.
	# Seed RNG for random draws
	randomize()

	# Create a dedicated CanvasLayer for card rendering to handle proper layering
	_card_layer = CanvasLayer.new()
	_card_layer.name = "CardLayer"
	add_child(_card_layer)

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
	
	if debug_logging:
		print("[GM] Looking for Deck node...")
		print("[GM] GameManager path: ", get_path())
		print("[GM] Direct Deck lookup result: ", deck_node)
	
	# If not found as direct child, try to find it in scene tree
	if not deck_node:
		var main_scene = get_tree().current_scene
		if main_scene and main_scene != self:
			deck_node = main_scene.get_node_or_null("Deck")
			if debug_logging:
				print("[GM] Tried main_scene.get_node('Deck'): ", deck_node)
		
		# Last resort: recursive search
		if not deck_node:
			deck_node = _find_deck_recursive(get_tree().root)
			if debug_logging:
				print("[GM] Recursive search result: ", deck_node)
	
	if debug_logging:
		if deck_node:
			print("[GM] Found Deck node at: ", deck_node.get_path())
			print("[GM] Deck has request_draw signal: ", deck_node.has_signal("request_draw"))
		else:
			print("[GM] Could not find Deck node anywhere")
	
	if deck_node and deck_node.has_signal("request_draw"):
		if not deck_node.is_connected("request_draw", Callable(self, "_on_deck_request_draw")):
			deck_node.connect("request_draw", Callable(self, "_on_deck_request_draw"))
			if debug_logging:
				print("[GM] Successfully connected to Deck's request_draw signal")
		else:
			if debug_logging:
				print("[GM] Already connected to Deck's request_draw signal")
	
	if debug_logging:
		print("[GM] Animation settings - flip_duration:", card_draw_flip_duration, " move_duration:", card_draw_move_duration, " scale:", card_final_scale)
	
	# Hide any PlayerHand placeholders so no cards are visible until drawn
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

	# If starting a new hand (index 0), clear the per-hand tracking so the next set of draws
	# will be treated as a fresh hand and will avoid internal duplicates.
	if _hand_index == 0:
		_current_hand_meta.clear()
	# When the deck requests a draw, choose a random front-facing card and animate it to PlayerHand
	var candidates: Array[String] = [
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
	
	# Apply smart card selection to avoid repetitive draws
	var chosen_path: String = _select_smart_card(candidates)
	var chosen: CustomCardData = load(chosen_path) as CustomCardData
	if not chosen:
		push_warning("[GM] Failed to load chosen card resource: %s" % chosen_path)
		return

	# Build metadata for tracking using the resource path (avoid relying on resource.card_name)
	var chosen_name := _extract_name_from_path(chosen_path)
	var chosen_meta := {"value": _extract_value(chosen_name), "effect": _extract_effect(chosen_name), "path": chosen_path}

	# Add this card metadata to our tracking array
	_track_drawn_card(chosen_meta)
	# Also add to current hand meta so selection during this hand avoids repeats
	_current_hand_meta.append(chosen_meta)

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
	_card_layer.add_child(animator)  # Add to dedicated card layer instead of GameManager
	
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
func _on_card_animation_finished(animated_card: Control, _drawn_card_data: CustomCardData, _target_slot: Node):
	# The animated card is already in the correct position and showing the right data
	if animated_card:
		animated_card.visible = true
		
		# Set z-index based on hand position for left-to-right stacking
		# Find which slot this card is in and assign z-index accordingly
		if _target_slot:
			var slot_name = _target_slot.name
			var slot_index = 0
			if slot_name.ends_with("1"):
				slot_index = 0
			elif slot_name.ends_with("2"):
				slot_index = 1
			elif slot_name.ends_with("3"):
				slot_index = 2
			elif slot_name.ends_with("4"):
				slot_index = 3
			
			# Set z_index to match PlayerHand pattern: 3, 2, 1, 0 (leftmost highest)
			animated_card.z_index = 3 - slot_index
			
			if debug_logging:
				print("[GM] Card placed in ", slot_name, " with z_index: ", animated_card.z_index)
	
	if debug_logging:
		print("[GM] Card animation finished and placed in hand slot")

# Helper function to recursively find Deck node
func _find_deck_recursive(node: Node) -> Node:
	if node.name == "Deck":
		return node
	
	for child in node.get_children():
		var result = _find_deck_recursive(child)
		if result:
			return result
	
	return null

# Smart card selection to avoid repetitive draws
func _select_smart_card(candidates: Array[String]) -> String:
	# Deterministic bucket selection to strongly prefer diversity.
	# Build lookups for last-two and current-hand to decide conflicts.
	var last_effects = {}
	var last_values = {}
	if _last_two_cards.size() >= 1:
		var m = _last_two_cards[_last_two_cards.size() - 1]
		last_effects[m.get("effect", "")] = true
		last_values[m.get("value", "")] = true
	if _last_two_cards.size() > 1:
		var m2 = _last_two_cards[_last_two_cards.size() - 2]
		last_effects[m2.get("effect", "")] = true
		last_values[m2.get("value", "")] = true

	var hand_effects = {}
	var hand_values = {}
	var hand_paths = {}
	for meta in _current_hand_meta:
		hand_effects[meta.get("effect", "")] = true
		hand_values[meta.get("value", "")] = true
		hand_paths[meta.get("path", "")] = true

	# 5% chance to allow an exact same resource into the same hand
	var exact_allow_chance = 5

	# Buckets: 00 = no effect conflict & no value conflict
	#          01 = no effect conflict & value conflict
	#          10 = effect conflict & no value conflict
	#          11 = effect conflict & value conflict
	var b00: Array[String] = []
	var b01: Array[String] = []
	var b10: Array[String] = []
	var b11: Array[String] = []

	for candidate_path in candidates:
		# enforce rare exact duplicate rule within same hand
		if hand_paths.has(candidate_path):
			var roll := randi() % 100
			if roll >= exact_allow_chance:
				# Skip this candidate to make identical resources rare within a hand
				continue
		# extract values/effects
		var cname = _extract_name_from_path(candidate_path)
		var val = _extract_value(cname)
		var eff = _extract_effect(cname)
		var eff_conflict = last_effects.has(eff) or hand_effects.has(eff)
		var val_conflict = last_values.has(val) or hand_values.has(val)
		if not eff_conflict and not val_conflict:
			b00.append(candidate_path)
		elif not eff_conflict and val_conflict:
			b01.append(candidate_path)
		elif eff_conflict and not val_conflict:
			b10.append(candidate_path)
		else:
			b11.append(candidate_path)

	# Prefer buckets in order: b00, b01, b10, b11
	if not b00.is_empty():
		if debug_logging:
			print("[GM] Bucket b00 (no effect/value conflict):", b00)
			print("[GM] Picked:", b00[randi() % b00.size()])
		return b00[randi() % b00.size()]

	if not b01.is_empty():
		if debug_logging:
			print("[GM] Bucket b01 (value conflict only):", b01)
		return b01[randi() % b01.size()]

	if not b10.is_empty():
		if debug_logging:
			print("[GM] Bucket b10 (effect conflict only):", b10)
		return b10[randi() % b10.size()]

	# If only fully conflicting candidates remain, pick one (we already tried to exclude exact duplicates above)
	if not b11.is_empty():
		if debug_logging:
			print("[GM] Bucket b11 (both conflicts) - falling back:", b11)
		return b11[randi() % b11.size()]

	# As a last resort (shouldn't happen), pick random
	var fallback_idx := randi() % candidates.size()
	if debug_logging:
		print("[GM] _select_smart_card: final random fallback:", candidates[fallback_idx])
	return candidates[fallback_idx]

# Add drawn card metadata to tracking array
func _track_drawn_card(card_meta: Dictionary) -> void:
	# card_meta should include keys: "value", "effect", "path"
	_last_two_cards.append(card_meta)
	# Keep only the last 2 cards
	if _last_two_cards.size() > 2:
		_last_two_cards.pop_front()

# Extract value from card name (e.g., "Two Draw" -> "Two")
func _extract_value(card_name: String) -> String:
	if card_name.begins_with("Two"):
		return "Two"
	elif card_name.begins_with("Four"):
		return "Four"
	elif card_name.begins_with("Six"):
		return "Six"
	elif card_name.begins_with("Eight"):
		return "Eight"
	elif card_name.begins_with("Ten"):
		return "Ten"
	return "Unknown"

# Extract effect from card name (e.g., "Two Draw" -> "Draw")
func _extract_effect(card_name: String) -> String:
	if card_name.ends_with("Draw"):
		return "Draw"
	elif card_name.ends_with("Swap"):
		return "Swap"
	return "Unknown"

# Extract card name from resource path
func _extract_name_from_path(path: String) -> String:
	# Convert "res://scripts/resources/TwoDraw.tres" to "TwoDraw"
	var filename = path.get_file().get_basename()
	# Convert "TwoDraw" to "Two Draw" format for consistency
	if filename == "TwoDraw":
		return "Two Draw"
	elif filename == "TwoSwap":
		return "Two Swap"
	elif filename == "FourDraw":
		return "Four Draw"
	elif filename == "FourSwap":
		return "Four Swap"
	elif filename == "SixDraw":
		return "Six Draw"
	elif filename == "SixSwap":
		return "Six Swap"
	elif filename == "EightDraw":
		return "Eight Draw"
	elif filename == "EightSwap":
		return "Eight Swap"
	elif filename == "TenDraw":
		return "Ten Draw"
	elif filename == "TenSwap":
		return "Ten Swap"
	return filename
