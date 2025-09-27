extends Node2D

## === GameManager: Script Configuration ===

const CardScene = preload("res://scenes/cards.tscn")
const CardGDScript = preload("res://scripts/NewCard.gd") # Preload for stability
const CardBackData = preload("res://scripts/resources/CardBack.tres")

@export var card_data: CustomCardData
@export_file("*.tres") var card_data_path: String
@export var card_key: String = "" # e.g., "TwoSwap" loads res://scripts/resources/TwoSwap.tres
@export var CardPosition: Vector2 = Vector2.ZERO
@export var CardScale: Vector2 = Vector2.ONE
@export var debug_logging: bool = true

## === GameManager: Animation Settings ===

@export_group("Card Animation")
@export var card_draw_flip_duration: float = 0.8
@export var card_draw_move_duration: float = 1.2
@export var card_draw_rotation: float = 15.0
@export var card_final_scale: Vector2 = Vector2(0.8, 0.8)

## === GameManager: Internal State ===

var _hand_index: int = 0
var _card_layer: CanvasLayer
var _last_two_cards: Array[Dictionary] = []
var _current_hand_meta: Array[Dictionary] = []

## === GameManager: Engine Hooks ===

func _ready():
	randomize()

	# Card rendering layer
	_card_layer = CanvasLayer.new()
	_card_layer.name = "CardLayer"
	add_child(_card_layer)

	# Enforce reasonable scales
	if card_final_scale.x < 0.1 or card_final_scale.y < 0.1:
		push_warning("[GM] card_final_scale too small; forcing to (0.8,0.8)")
		card_final_scale = Vector2(0.8, 0.8)
	if CardScale.x < 0.01 or CardScale.y < 0.01:
		push_warning("[GM] CardScale too small; forcing to (0.42,0.42)")
		CardScale = Vector2(0.42, 0.42)
	card_final_scale = CardScale

	if debug_logging:
		print("[GM] Scales:", CardScale, "->", card_final_scale)

	_connect_to_deck()
	_hide_placeholders()
	_configure_score_panels()
	# Deal a quick opponent hand on load (animated, one-by-one)
	call_deferred("_deal_initial_opponent_hand")

## === GameManager: Deck Handling ===

# Connects to the Deck's request_draw signal.
func _connect_to_deck():
	# robustly find the Deck node anywhere under this scene
	var deck_node = _scene_root().find_child("Deck", true, false)
	if deck_node and deck_node.has_signal("request_draw"):
		if not deck_node.is_connected("request_draw", Callable(self, "_on_deck_request_draw")):
			deck_node.connect("request_draw", Callable(self, "_on_deck_request_draw"))
			if debug_logging:
				print("[GM] Connected to Deck.request_draw")
	elif debug_logging:
		print("[GM] Deck node not found")

# Handles the deck's request to draw a card.
func _on_deck_request_draw() -> void:
		if debug_logging:
			print("[GM] Deck requested draw")

		if _hand_index == 0:
			_current_hand_meta.clear()

		var candidates = _get_card_candidates()
		var chosen_path = _select_smart_card(candidates)
		var chosen_data = load(chosen_path) as CustomCardData
		if not chosen_data:
			push_warning("[GM] Failed to load chosen card: %s" % chosen_path)
			return

		var chosen_meta = _build_card_meta(chosen_path)
		_track_drawn_card(chosen_meta)
		_current_hand_meta.append(chosen_meta)

		var player_hand = _scene_root().find_child("PlayerHand", true, false)
		if not player_hand:
			push_warning("[GM] PlayerHand node not found; cannot place drawn card")
			return

		var deck_node = _scene_root().find_child("Deck", true, false)
		if not deck_node:
			push_warning("[GM] Deck node not found; cannot animate card draw")
			return
	
		var target_slot = _get_target_slot(player_hand)
	
		# --- THIS IS THE NEW LOGIC ---
		# First, get the target position from the PlayerHand.
		var target_pos = _get_target_position(player_hand, target_slot)

		# Now, check if it's null. If it is, the draw fails here.
		if target_pos == null:
			push_error("[GM] Draw failed. PlayerHand reported an invalid target slot. (Hand is likely full)")
			# We stop the function here so no animation is created.
			return
		# --- END OF NEW LOGIC ---

		var start_pos = deck_node.global_position
		var target_rotation = _get_target_rotation(player_hand, target_slot)

		_start_card_animation(chosen_data, start_pos, target_pos, target_slot, target_rotation)

		_hand_index += 1
		_update_deck_count(deck_node)

## === GameManager: Card Creation & Animation ===

# Creates a new card instance.
func create_card(data: CustomCardData):
	var new_card = CardScene.instantiate()
	add_child(new_card)
	new_card.position = CardPosition
	new_card.scale = CardScale
	new_card.call_deferred("display", data)
	if debug_logging:
		print("[GM] Card instantiated:", new_card.position, new_card.scale)

# Starts the card draw animation.
func _start_card_animation(data: CustomCardData, start_pos: Vector2, target_pos: Vector2, target_slot: Node, final_rotation: float = 0.0, p_final_scale: Variant = null, p_start_scale: Variant = null) -> void:
	var animator = CardDrawAnimation.new()
	_card_layer.add_child(animator)

	animator.flip_duration = card_draw_flip_duration
	animator.move_duration = card_draw_move_duration
	animator.rotation_angle = card_draw_rotation

	# allow per-animation override of scales
	if p_final_scale != null:
		animator.final_scale = p_final_scale
	else:
		animator.final_scale = card_final_scale

	var start_scale = p_start_scale if p_start_scale != null else CardScale

	if animator.final_scale.x < 0.05 or animator.final_scale.y < 0.05:
		push_warning("[GM] Card final scale very small; forcing to (0.8,0.8)")
		animator.final_scale = Vector2(0.8, 0.8)

	# Minimal debug: log that an animator was started and what slot it's targeting
	var slot_path = "(null)"
	if target_slot:
		slot_path = str(target_slot.get_path())
	if debug_logging:
		print("[GM] _start_card_animation -> data:", data, " target_slot:", slot_path, " final_scale=", animator.final_scale)

	# No immediate back placement here; let the animator finish and reveal the card.
	animator.connect("animation_finished", Callable(self, "_on_card_animation_finished").bind(data, target_slot))
	# If this animation targets an opponent slot, ask the animator not to reveal the face
	var suppress_reveal_flag = false
	if target_slot and _is_slot_in_opponent_hand(target_slot):
		suppress_reveal_flag = true
		if debug_logging:
			print("[GM] Detected opponent slot; suppressing reveal for:", slot_path)
	animator.animate_card_draw(data, start_pos, target_pos, final_rotation, animator.final_scale, start_scale, suppress_reveal_flag)
	if debug_logging:
		print("[GM] Started draw", start_pos, "->", target_pos, " final_scale=", animator.final_scale, " start_scale=", start_scale)

# Called when the card draw animation finishes.
func _on_card_animation_finished(animated_card: Control, _drawn_card_data: CustomCardData, _target_slot: Node) -> void:
	# --- OPPONENT LOGIC (No changes here) ---
	var is_opp_slot = _is_slot_in_opponent_hand(_target_slot)
	if is_opp_slot and is_instance_valid(_target_slot):
		_target_slot.set_meta("hidden_card_data", _drawn_card_data)
		if _target_slot.has_method("display"):
			_target_slot.call_deferred("display", CardBackData)
		if _target_slot is CanvasItem:
			_target_slot.visible = true
		if animated_card and animated_card.is_inside_tree():
			animated_card.queue_free()
		return

	# --- PLAYER HAND LOGIC (This is the updated part) ---
	if animated_card and _target_slot:
		var player_hand = _scene_root().find_child("PlayerHand", true, false)
		if player_hand:
			# Get the index of the slot (e.g., "HandSlot3" -> 2)
			var slot_index = _get_slot_index(_target_slot.name)
			# "Hand over" the animated card node to the PlayerHand to manage
			player_hand.call_deferred("receive_card_node", animated_card, slot_index, _drawn_card_data)

func _is_slot_in_opponent_hand(slot: Node) -> bool:
	if not slot:
		return false

	# Prefer an explicit ancestry check: find the opponent_hand node in the scene
	# and see if it's an ancestor of the provided slot. This is far more
	# reliable than string-matching node names (which can fail if nodes are
	# renamed or reparented).
	var root = _scene_root()
	if not root:
		return false

	var opp_hand = root.find_child("opponent_hand", true, false)
	if opp_hand:
		# Walk up the parent chain from the slot to see if we hit opp_hand
		var cur: Node = slot
		while cur:
			if cur == opp_hand:
				return true
			cur = cur.get_parent()

	return false

## === GameManager: UI & Initialization Helpers ===

# Hides placeholder cards in the player's hand.
func _hide_placeholders():
	var ph = _scene_root().find_child("PlayerHand", true, false)
	if ph:
		for i in range(1, 5):
			var slot = ph.get_node_or_null("HandSlot" + str(i))
			if slot:
				slot.visible = false

# Configures the initial state of the score panels.
func _configure_score_panels():
	# Explicitly target the instantiated score panel nodes by the names used
	# in the main scene. Each instance of the ScorePanel packed scene contains
	# both a PlayerScore and OpponentScore child; hide the opposite child on
	# each instance so the UI shows the correct side.
	var player_instance = _scene_root().find_child("PlayerScore", true, false)
	if player_instance and player_instance.has_node("OpponentScore"):
		player_instance.get_node("OpponentScore").visible = false

	var opponent_instance = _scene_root().find_child("OppScore", true, false)
	if opponent_instance and opponent_instance.has_node("PlayerScore"):
		opponent_instance.get_node("PlayerScore").visible = false

## === GameManager: Card Selection Logic ===

# Selects a card from the candidates using a smart algorithm to avoid repetition.
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

# Tracks the last two drawn cards.
func _track_drawn_card(card_meta: Dictionary) -> void:
	_last_two_cards.append(card_meta)
	if _last_two_cards.size() > 2:
		_last_two_cards.pop_front()

## === GameManager: Utility Functions ===

# Recursively finds the Deck node in the scene.
func _find_deck_recursive(node: Node) -> Node:
	if node.name == "Deck":
		return node
	for child in node.get_children():
		var result = _find_deck_recursive(child)
		if result:
			return result
	return null

# Returns the most appropriate scene root to search under (current scene or first child of root)
func _scene_root() -> Node:
	var s = get_tree().get_current_scene()
	if s:
		return s
	if get_tree().get_root().get_child_count() > 0:
		return get_tree().get_root().get_child(0)
	return get_tree().get_root()

# Returns the list of card resource paths.
func _get_card_candidates() -> Array[String]:
	return [
		"res://scripts/resources/TwoDraw.tres", "res://scripts/resources/TwoSwap.tres",
		"res://scripts/resources/FourDraw.tres", "res://scripts/resources/FourSwap.tres",
		"res://scripts/resources/SixDraw.tres", "res://scripts/resources/SixSwap.tres",
		"res://scripts/resources/EightDraw.tres", "res://scripts/resources/EightSwap.tres",
		"res://scripts/resources/TenDraw.tres", "res://scripts/resources/TenSwap.tres"
	]

## === GameManager: Opponent Startup ===
func _deal_initial_opponent_hand() -> void:
	var opp_hand = _scene_root().find_child("OppHand", true, false)
	if not opp_hand:
		# try alternative node names used in scenes (case variations)
		opp_hand = _scene_root().find_child("OpponentHand", true, false)
	if not opp_hand:
		opp_hand = _scene_root().find_child("opponent_hand", true, false)
	if not opp_hand:
		opp_hand = _scene_root().find_child("opponentHand", true, false)
	if not opp_hand:
		if debug_logging:
			print("[GM] No opponent hand found on startup; skipping initial deal")
		return
	elif debug_logging:
		print("[GM] Found opponent hand:", opp_hand.get_path())

	# Number of cards to deal to opponent (use max_cards if available)
	var count = 4
	# try to read an exported max_cards property if present on the opponent hand
	var maybe_max = null
	# safe get: returns null if property doesn't exist
	maybe_max = opp_hand.get("max_cards") if opp_hand else null
	if typeof(maybe_max) == TYPE_INT or typeof(maybe_max) == TYPE_FLOAT:
		count = int(maybe_max)
	if debug_logging:
		print("[GM] Dealing", count, "cards to", opp_hand.name)

	# Prepare short animation parameters (very quick)
	var orig_flip = card_draw_flip_duration
	var orig_move = card_draw_move_duration
	card_draw_flip_duration = 0.12
	card_draw_move_duration = 0.18

	# Sequentially draw into opponent hand with tiny delay between each
	for i in range(count):
		# pick a candidate and animate draw from deck to opponent slot
		var candidates = _get_card_candidates()
		var chosen_path = _select_smart_card(candidates)
		var chosen_data = load(chosen_path) as CustomCardData
		if not chosen_data:
			continue

		# find deck position
		var deck_node = _scene_root().find_child("Deck", true, false)
		if not deck_node:
			continue
		var start_pos = deck_node.global_position

		# determine the target slot node on the opponent hand
		var target_slot: Node = null
		# Prefer scanning slots by index so we can skip already-reserved ones
		var max_slots = 4
		var maybe_max_slots = opp_hand.get("max_cards") if opp_hand and opp_hand.has_method("get") else null
		if typeof(maybe_max_slots) == TYPE_INT:
			max_slots = int(maybe_max_slots)
		if opp_hand.has_method("get_slot"):
			for j in range(max_slots):
				var candidate = opp_hand.get_slot(j)
				if candidate and not candidate.visible and not (candidate.has_meta("reserved") and candidate.get_meta("reserved")):
					target_slot = candidate
					break
		# fallback to get_next_empty_slot if none found
		if not target_slot and opp_hand.has_method("get_next_empty_slot"):
			var cand = opp_hand.get_next_empty_slot()
			if cand and not (cand.has_meta("reserved") and cand.get_meta("reserved")):
				target_slot = cand
		# fallback: if we still don't have a slot, skip
		if not target_slot:
			continue

		# Mark the slot reserved so subsequent draws don't reuse it while animating
		if target_slot:
			target_slot.set_meta("reserved", true)
			# Hide the slot visually until the animation finishes so nothing is visible prematurely
			if target_slot is CanvasItem:
				target_slot.visible = false

		var target_pos = Vector2.ZERO
		if opp_hand.has_method("get_slot_position"):
			target_pos = opp_hand.get_slot_position(i)
		elif target_slot:
			target_pos = target_slot.global_position

		# determine the final scale for the slot: prefer the slot's current scale, then opp_hand exported slot_scales, else 0.32
		var slot_final_scale: Vector2 = Vector2(0.32, 0.32)
		if target_slot and (target_slot is Node2D or target_slot is CanvasItem):
			slot_final_scale = target_slot.scale
		elif opp_hand and opp_hand.has_method("get_slot_position"):
			# try reading exported slot_scales from the opponent hand if present
			var maybe_scales = null
			maybe_scales = opp_hand.get("slot_scales") if opp_hand else null
			if typeof(maybe_scales) == TYPE_ARRAY and i < maybe_scales.size():
				var s = maybe_scales[i]
				if typeof(s) == TYPE_VECTOR2:
					slot_final_scale = s

		# start animation targeting the actual slot node, pass final scale so the animator matches the slot
		_start_card_animation(chosen_data, start_pos, target_pos, target_slot, 0.0, slot_final_scale, CardScale)

		# slight pause between draws so animations stagger (yield)
		await get_tree().create_timer(0.06).timeout

	# restore original timings
	card_draw_flip_duration = orig_flip
	card_draw_move_duration = orig_move

# Builds metadata for a card from its resource path.
func _build_card_meta(path: String) -> Dictionary:
	var card_name = _extract_name_from_path(path)
	return {"value": _extract_value(card_name), "effect": _extract_effect(card_name), "path": path}

# Gets the target hand slot for the next card.
func _get_target_slot(player_hand: Node) -> Node:
	var placeholders = ["HandSlot1", "HandSlot2", "HandSlot3", "HandSlot4"]
	if _hand_index < placeholders.size():
		var target_name = placeholders[_hand_index]
		if player_hand.has_node(target_name):
			return player_hand.get_node(target_name)
		else:
			push_warning("[GM] Target slot %s not found" % target_name)
	else:
		push_warning("[GM] No more hand slots available")
	return null

# Gets the target position for the card in the hand.
func _get_target_position(player_hand: Node, _target_slot: Node) -> Vector2:
		if player_hand.has_method("get_slot_position"):
			return player_hand.get_slot_position(_hand_index)
		push_warning("[GM] PlayerHand node is missing the 'get_slot_position' method. Returning Vector2.ZERO.")
		return Vector2.ZERO

# Gets the target rotation for the card in the hand.
func _get_target_rotation(player_hand: Node, target_slot: Node) -> float:
	if target_slot and target_slot.has_method("get_rotation"):
		return target_slot.get_rotation()
	elif player_hand.has_method("get_slot_rotation"):
		# Fallback: use PlayerHand's slot rotation method
		return player_hand.get_slot_rotation(_hand_index)
	push_warning("[GM] Could not get rotation from target_slot or PlayerHand. Returning 0.0.")
	return 0.0

# Updates the visual count of the deck.
func _update_deck_count(deck_node: Node):
	if deck_node and deck_node.has_method("get_count") and deck_node.has_method("set_count"):
		var current_count = deck_node.call("get_count")
		deck_node.call("set_count", max(0, int(current_count) - 1))

# Extracts the card's base value from its name.
func _extract_value(card_name: String) -> String:
	if card_name.begins_with("Two"): return "Two"
	if card_name.begins_with("Four"): return "Four"
	if card_name.begins_with("Six"): return "Six"
	if card_name.begins_with("Eight"): return "Eight"
	if card_name.begins_with("Ten"): return "Ten"
	return "Unknown"

# Extracts the card's effect from its name.
func _extract_effect(card_name: String) -> String:
	if card_name.ends_with("Draw"): return "Draw"
	if card_name.ends_with("Swap"): return "Swap"
	return "Unknown"

# Extracts a clean name from the card's resource path.
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

# Gets the index of a hand slot from its name.
func _get_slot_index(slot_name: String) -> int:
	if slot_name.ends_with("1"): return 0
	if slot_name.ends_with("2"): return 1
	if slot_name.ends_with("3"): return 2
	if slot_name.ends_with("4"): return 3
	return 0
