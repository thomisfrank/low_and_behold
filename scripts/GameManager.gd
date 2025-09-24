extends Node2D

const CardScene = preload("res://scenes/cards.tscn")

# Mark script to preload to avoid shader/material issues
const CardGDScript = preload("res://scripts/Card.gd")

@export var card_data: CustomCardData
@export_file("*.tres") var card_data_path: String
@export var card_key: String = "" # e.g., "TwoSwap" will load res://scripts/resources/TwoSwap.tres
@export var CardPosition: Vector2 = Vector2.ZERO
@export var CardScale: Vector2 = Vector2.ONE
@export var debug_logging: bool = true

var _hand_index: int = 0


func _ready():
	# Do not create any test card at startup; cards should appear only when drawn.
	# Seed RNG for random draws
	randomize()

	# Connect to Deck's request_draw signal if Deck exists in the scene
	var deck_node = get_node_or_null("Deck")
	if not deck_node:
		deck_node = get_tree().get_root().find_node("Deck", true, false)
	if deck_node and deck_node.has_signal("request_draw"):
		deck_node.connect("request_draw", Callable(self, "_on_deck_request_draw"))
		if debug_logging:
			print("[GM] Connected to Deck.request_draw")

	# Hide any PlayerHand placeholders so no cards are visible until drawn
	var ph = get_node_or_null("PlayerHand")
	if not ph:
		ph = get_tree().get_root().find_node("PlayerHand", true, false)
	if ph:
		for slot_name in ["cards", "cards2", "cards3", "cards4"]:
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
	# When the deck requests a draw, choose a random front-facing card and place it in PlayerHand
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

	# Find PlayerHand node and instance the card under it
	var ph := get_node_or_null("PlayerHand")
	if not ph:
		# try root-level path
		ph = get_node_or_null("/root/Node2D/PlayerHand")
	if not ph:
		push_warning("[GM] PlayerHand node not found; cannot place drawn card")
		return

	# Prefer filling placeholders sequentially (cards, cards2, ...)
	var placeholders := ["cards", "cards2", "cards3", "cards4"]
	var placed := false
	if _hand_index < placeholders.size():
		var target_name: String = placeholders[_hand_index]
		if ph.has_node(target_name):
			var slot = ph.get_node(target_name)
			# If the slot is an instance of the card scene, call its display() to show the card front
			if slot and slot.has_method("display"):
				slot.call_deferred("display", chosen)
				slot.visible = true
				placed = true
	if not placed:
		# Fallback: instantiate a new card under PlayerHand
		var card_instance = CardScene.instantiate()
		ph.add_child(card_instance)
		card_instance.call_deferred("display", chosen)
	if debug_logging:
		print("[GM] Drew card into PlayerHand: ", chosen_path, " placed=", placed)
	_hand_index += 1

	# Update deck visual count if deck exposes set_count
	var deck_node = get_node_or_null("Deck")
	if deck_node and deck_node.has_method("get_count") and deck_node.has_method("set_count"):
		var current = deck_node.call("get_count")
		deck_node.call("set_count", max(0, int(current) - 1))
