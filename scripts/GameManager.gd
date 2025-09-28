
extends Node2D

# =============================
# GameManager.gd
# Main game controller for Low & Behold
# Handles game state, turn logic, card effects, and overlays
# =============================

# --- Overlay Helpers ---
# Show/hide game state overlay UI
func _show_game_state_overlay(text: String):
	var ui_layer = _scene_root().find_child("UILayer", true, false)
	if ui_layer:
		var overlay = ui_layer.get_node_or_null("gameStateOverlay")
		if overlay:
			overlay.visible = true
			var label = overlay.get_node_or_null("Label")
			if label:
				label.text = text
			var rect = overlay.get_node_or_null("OverlayRect")
			if rect:
				var c = rect.color
				rect.color = Color(c.r, c.g, c.b, overlay_alpha)

func _hide_game_state_overlay():
	var ui_layer = _scene_root().find_child("UILayer", true, false)
	if ui_layer:
		var overlay = ui_layer.get_node_or_null("gameStateOverlay")
		if overlay:
			overlay.visible = false

# --- Script Configuration ---
const CardScene = preload("res://scenes/cards.tscn") # Card scene for instancing
const CardGDScript = preload("res://scripts/NewCard.gd") # Card script
const CardBackData = preload("res://scripts/resources/CardBack.tres") # Card back resource

@export var card_data: CustomCardData # Main card data
@export_file("*.tres") var card_data_path: String # Card data file path
@export var card_key: String = "" # Card key
@export var CardPosition: Vector2 = Vector2.ZERO # Card position
@export var CardScale: Vector2 = Vector2.ONE # Card scale
@export var debug_logging: bool = true # Debug logging toggle
@export var first_player: int = 0 # 0 = random, 1 = player, 2 = opponent

# --- Gameplay Rules ---

# --- Overlay Customization ---
@export var overlay_alpha: float = 0.3 # Overlay transparency
@export var overlay_duration: float = 1.2 # Overlay display duration

# --- Card Animation Settings ---
@export_group("Card Animation")
@export var card_draw_flip_duration: float = 0.8
@export var card_draw_move_duration: float = 1.2
@export var card_draw_rotation: float = 15.0
@export var card_final_scale: Vector2 = Vector2(0.8, 0.8) # Final card scale

# --- Internal State ---
enum GameState {
	ROUND_START,
	PLAYER_TURN,
	OPPONENT_TURN,
	CARD_PLAY,
	RESOLVE_EFFECT,
	ROUND_END,
	GAME_OVER
}
var game_state: GameState = GameState.ROUND_START
var round_number: int = 1
var current_player: int = 1 # 1 or 2
var actions_left: int = 2
var player_scores: Array[int] = [0, 0]
var player_hand_nodes: Array = []
var opponent_hand_node = null
var _hand_index: int = 0
var _card_layer: CanvasLayer
var _last_two_cards: Array[Dictionary] = []
var _current_hand_meta: Array[Dictionary] = []

# --- Engine Hooks ---
# Called when node is ready
func _ready():
	randomize()
	_card_layer = CanvasLayer.new()
	_card_layer.name = "CardLayer"
	add_child(_card_layer)

	if card_final_scale.x < 0.1 or card_final_scale.y < 0.1:
		push_warning("[GM] card_final_scale too small; forcing to (0.8,0.8)")
		card_final_scale = Vector2(0.8, 0.8)
	if CardScale.x < 0.01 or CardScale.y < 0.01:
		push_warning("[GM] CardScale too small; forcing to (0.42,0.42)")
		CardScale = Vector2(0.42, 0.42)
	# This line is no longer correct as PlayerHand defines its own scale. We will set it per-animation.
	# card_final_scale = CardScale 

	if debug_logging:
		print("[GM] Default Card Scales:", CardScale, "->", card_final_scale)

	_connect_to_deck()
	_hide_placeholders()
	_configure_score_panels()
	var oh = _scene_root().find_child("opponent_hand", true, false)
	if oh and oh.has_signal("swap_card_selected"):
		oh.connect("swap_card_selected", Callable(self, "_on_opponent_swap_card_selected"))
	# Add GameStateOverlay if not present
	var ui_layer = _scene_root().find_child("UILayer", true, false)
	if ui_layer and not ui_layer.has_node("gameStateOverlay"):
		var overlay_scene = preload("res://scenes/game_state_overlay.tscn").instantiate()
		overlay_scene.name = "gameStateOverlay"
		ui_layer.add_child(overlay_scene)
		overlay_scene.visible = false
		# Set initial transparency
		var rect = overlay_scene.get_node_or_null("OverlayRect")
		if rect:
			var c = rect.color
			rect.color = Color(c.r, c.g, c.b, overlay_alpha)
	# Start the game automatically
	call_deferred("start_round")

## === GameManager: Gameplay State ===

func start_round():
	game_state = GameState.ROUND_START
	print("[GM] Starting round %d" % round_number)
	actions_left = 2
	# Choose who starts the round
	if first_player == 1:
		current_player = 1
	elif first_player == 2:
		current_player = 2
	else:
		current_player = 1 if randi() % 2 == 0 else 2
	print("[GM] Player %d starts the round." % current_player)
	_update_score_panels()
	_update_action_indicators()
	_update_round_counter()
	_auto_draw_hands()
	_show_game_state_overlay("Round %d" % round_number)
	await get_tree().create_timer(overlay_duration).timeout
	_hide_game_state_overlay()
	if current_player == 1:
		game_state = GameState.PLAYER_TURN
		_start_player_turn(current_player)
	else:
		game_state = GameState.OPPONENT_TURN
		_start_player_turn(current_player)

func _auto_draw_hands():
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	player_hand_nodes = [ph]
	opponent_hand_node = oh
	if oh:
		if debug_logging:
			print("[GM] Dealing", oh.max_cards, "cards to OpponentHand")
		for i in range(oh.max_cards):
			_hand_index = i
			if debug_logging:
				print("[GM] OpponentHand auto-draw card", i)
			_on_opponent_deck_request_draw()

	await get_tree().create_timer(0.3).timeout

	if ph:
		if debug_logging:
			print("[GM] Dealing", ph.max_cards, "cards to PlayerHand")
		for i in range(ph.max_cards):
			_hand_index = i
			if debug_logging:
				print("[GM] PlayerHand auto-draw card", i)
			_on_deck_request_draw()

func _on_opponent_deck_request_draw() -> void:
	# This function for the opponent remains largely the same, as OpponentHand still uses slots.
	var candidates = _get_card_candidates()
	var chosen_path = _select_smart_card(candidates)
	var chosen_data = load(chosen_path) as CustomCardData
	if not chosen_data:
		return

	var opponent_hand = _scene_root().find_child("opponent_hand", true, false)
	if not opponent_hand:
		return

	var deck_node = _scene_root().find_child("Deck", true, false)
	if not deck_node:
		return
		
	var target_slot = opponent_hand.get_slot(_hand_index)
	if not target_slot:
		push_warning("[GM] OpponentHand slot %d not found" % _hand_index)
		return
		
	var target_pos = target_slot.global_position
	var target_rotation = opponent_hand.slot_rotations[_hand_index] # <-- CHANGED: Use array
	var target_scale = opponent_hand.slot_scales[_hand_index] # <-- NEW: Get scale from array
	_start_card_animation(chosen_data, deck_node.global_position, target_pos, target_slot, target_rotation, target_scale)
	_update_deck_count(deck_node)

func _start_player_turn(player_num: int):
	current_player = player_num
	actions_left = 2
	_update_action_indicators()
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	var overlay_text = "Your Turn" if player_num == 1 else "Opponent Turn"
	_show_game_state_overlay(overlay_text)
	await get_tree().create_timer(overlay_duration).timeout
	_hide_game_state_overlay()
	if player_num == 1:
		game_state = GameState.PLAYER_TURN
		if ph:
			ph.set_process_input(true)
			ph.set_process(true)
		if oh:
			oh.set_process_input(false)
			oh.set_process(false)
	else:
		game_state = GameState.OPPONENT_TURN
		if ph:
			ph.set_process_input(false)
			ph.set_process(false)
		if oh:
			oh.set_process_input(true)
			oh.set_process(true)
		_execute_opponent_turn()

func _execute_opponent_turn():
	print("[GM] Executing opponent's turn.")
	# Wait a bit to simulate thinking
	await get_tree().create_timer(1.0).timeout

	for i in range(2):
		var oh = _scene_root().find_child("opponent_hand", true, false)
		if not oh or not oh.has_method("get_card_count") or oh.get_card_count() == 0:
			print("[GM] Opponent has no cards to play.")
			break

		# Gather all valid card indices for this action
		var valid_draw_indices = []
		var valid_swap_indices = []
		for idx in range(oh.get_card_count()):
			var node = oh.get_card_node(idx)
			if node and node.has_meta("hidden_card_data"):
				var data = node.get_meta("hidden_card_data")
				if data.effect_type == CustomCardData.EffectType.Draw_Card:
					valid_draw_indices.append(idx)
				elif data.effect_type == CustomCardData.EffectType.Swap_Card:
					valid_swap_indices.append(idx)

		var player_hand = _scene_root().find_child("PlayerHand", true, false)
		var player_has_valid_swap = player_hand and player_hand.get_card_count() > 0

		var card_index = -1
		var card_node = null
		var opp_card_data = null

		# Alternate: first action is draw, second is swap if possible
		if i == 0 and valid_draw_indices.size() > 0:
			card_index = valid_draw_indices[randi() % valid_draw_indices.size()]
		elif i == 1 and valid_swap_indices.size() > 0 and player_has_valid_swap:
			card_index = valid_swap_indices[randi() % valid_swap_indices.size()]
		elif valid_draw_indices.size() > 0:
			card_index = valid_draw_indices[randi() % valid_draw_indices.size()]
		elif valid_swap_indices.size() > 0 and player_has_valid_swap:
			card_index = valid_swap_indices[randi() % valid_swap_indices.size()]
		else:
			print("[GM] Opponent has no valid card to play for action", i)
			continue

		card_node = oh.get_card_node(card_index)
		if card_node and card_node.has_meta("hidden_card_data"):
			opp_card_data = card_node.get_meta("hidden_card_data")
			print("[GM] Opponent plays card at index %d with effect '%s'" % [card_index, opp_card_data.effect_type])
			if card_node.has_method("display"):
				card_node.display(opp_card_data)
			await get_tree().create_timer(1.0).timeout

			actions_left -= 1
			_update_action_indicators()
			match opp_card_data.effect_type:
				CustomCardData.EffectType.Draw_Card:
					oh.discard_card(card_index)
					_hand_index = card_index
					_on_opponent_deck_request_draw()
				CustomCardData.EffectType.Swap_Card:
					# Pick a random card from player's hand to swap
					if player_hand and player_hand.get_card_count() > 0:
						var player_card_index = randi() % player_hand.get_card_count()
						_on_opponent_swap_card_selected(player_card_index)
					else:
						oh.discard_card(card_index)
				_:
					oh.discard_card(card_index)
		await get_tree().create_timer(0.5).timeout
	_end_player_turn()

func player_action_from_hand(card_index: int):
	if actions_left > 0 and current_player == 1:
		actions_left -= 1
		_update_action_indicators()
		var ph = _scene_root().find_child("PlayerHand", true, false)
		var played_card_data = ph.card_data_map[card_index] if ph and ph.card_data_map.size() > card_index else null
		var play_area = _scene_root().find_child("PlayArea", true, false)
		if play_area:
			play_area.visible = true
		# Step 1: Card moves into play area
		await get_tree().create_timer(0.8).timeout
		# Step 2: Card is revealed in play area
		print("[GM] Card revealed in play area.")
		await get_tree().create_timer(0.8).timeout
		# Step 3: Effect resolves
		if played_card_data:
			print("[GM] Player 1 played card at index %d with effect '%s'. Actions left: %d" % [card_index, played_card_data.effect_type, actions_left])
			match played_card_data.effect_type:
				CustomCardData.EffectType.Draw_Card:
					ph.play_card(card_index)
					_hand_index = card_index
					await get_tree().create_timer(0.8).timeout
					_on_deck_request_draw()
				CustomCardData.EffectType.Swap_Card:
					print("[GM] Card effect: Swap - highlight opponent hand for selection")
					var oh = _scene_root().find_child("opponent_hand", true, false)
					if oh and oh.has_method("enable_swap_selection"):
						oh.enable_swap_selection()
					if ph and ph.has_method("lock_card"):
						ph.lock_card(card_index)
					await get_tree().create_timer(0.8).timeout
				_:
					print("[GM] Card has no special effect, just playing it.")
					ph.play_card(card_index)
					await get_tree().create_timer(0.8).timeout
		else:
			print("[GM] Played card at index %d, but no card data was found." % card_index)
			ph.play_card(card_index)
			await get_tree().create_timer(0.8).timeout
		# Step 4: Hide play area after effect
		if play_area:
			play_area.visible = false
		await get_tree().create_timer(0.5).timeout
		if actions_left == 0:
			_end_player_turn()
func _end_player_turn():
	print("[GM] Player %d turn ended" % current_player)
	if current_player == 1:
		_start_player_turn(2)
	else:
		_start_player_turn(1)

func _end_round():
	print("[GM] Ending round %d" % round_number)
	var p1_total = _calculate_hand_total(player_hand_nodes[0])
	var p2_total = _calculate_hand_total(opponent_hand_node)
	print("[GM] Player 1 hand total: %d, Player 2 hand total: %d" % [p1_total, p2_total])
	if p1_total < p2_total:
		player_scores[0] += p1_total
		print("[GM] Player 1 wins round!")
	elif p2_total < p1_total:
		player_scores[1] += p2_total
		print("[GM] Player 2 wins round!")
	else:
		print("[GM] Round is a tie. No score added.")
	_update_score_panels()
	_update_round_counter()
	var round_end_scene = preload("res://scenes/round_end_screen.tscn").instantiate()
	if round_end_scene.has_method("set_scores"):
		round_end_scene.set_scores(player_scores[0], player_scores[1], p1_total, p2_total)
	if round_end_scene.has_signal("continue_pressed"):
		round_end_scene.connect("continue_pressed", Callable(self, "_on_round_end_continue"))
	get_tree().get_root().add_child(round_end_scene)

func _on_round_end_continue():
	_discard_hands()
	# Check if deck is empty to end game
	var deck_node = _scene_root().find_child("Deck", true, false)
	if deck_node and deck_node.has_method("get_count") and deck_node.get_count() <= 0:
		end_game()
	else:
		round_number += 1
		start_round()

func end_game():
	print("[GM] Game Over!")
	var winner = 1 if player_scores[0] > player_scores[1] else 2 if player_scores[1] > player_scores[0] else 0
	var result_text = "Game Over! "
	if winner == 0:
		result_text += "It's a tie! Final Score: %d - %d" % [player_scores[0], player_scores[1]]
	else:
		result_text += "Player %d wins! Final Score: %d - %d" % [winner, player_scores[0], player_scores[1]]
	_show_game_state_overlay(result_text)



func _calculate_hand_total(hand_node):
	var total = 0
	if hand_node and hand_node.has_method("card_data_map"):
		var card_data_map = hand_node.card_data_map
		for i in range(card_data_map.size()):
			var hand_card_data = card_data_map[i]
			if hand_card_data:
				var value = 0
				if "effect_value" in hand_card_data:
					value = hand_card_data.effect_value
				total += value
	return total

func _discard_hands():
	print("[GM] Discarding all cards from hands.")
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	if ph and ph.has_method("discard_all_cards"):
		ph.discard_all_cards()
	if oh and oh.has_method("discard_all_cards"):
		oh.discard_all_cards()
	_update_score_panels()
## === GameManager: Swap Logic ===
func _on_opponent_swap_card_selected(index: int):
	# This logic seems okay, leaving it as is.
	print("[GM] Opponent card selected for swap at index %d" % index)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	var ph = _scene_root().find_child("PlayerHand", true, false)
	if oh and oh.has_method("disable_swap_selection"):
		oh.disable_swap_selection()
	var opp_slot = oh.get_slot(index) if oh and oh.has_method("get_slot") else null
	# Find any valid (non-empty) player card slot
	var player_slot = null
	var player_slot_index = -1
	if ph and ph.has_method("get_card_count") and ph.get_card_count() > 0:
		for i in range(ph.max_cards):
			var card = ph.managed_cards[i]
			if is_instance_valid(card):
				player_slot = card
				player_slot_index = i
				break
	if opp_slot and player_slot:
		var play_area = _scene_root().find_child("PlayArea", true, false)
		# Step 1: Card reveal animation
		if is_instance_valid(opp_slot) and opp_slot is CanvasItem:
			opp_slot.modulate = Color(1,1,1,0.3)
		if is_instance_valid(player_slot) and player_slot is CanvasItem:
			player_slot.modulate = Color(1,1,1,0.3)
		if play_area:
			play_area.visible = true
		await get_tree().create_timer(0.8).timeout
		# Step 2: Drag to play area animation
		print("[GM] Dragging card to play area for swap...")
		await get_tree().create_timer(0.8).timeout
		# Step 3: Swap effect resolution
		if ph and ph.has_method("discard_card"):
			ph.discard_card(player_slot_index)
		if oh and oh.has_method("add_card_to_hand") and is_instance_valid(player_slot) and player_slot.has_meta("card_data"):
			oh.add_card_to_hand(player_slot.get_meta("card_data"))
		var opp_slot_index = oh.hand_slots.find(opp_slot)
		if oh and oh.has_method("discard_card") and opp_slot_index != -1:
			oh.discard_card(opp_slot_index)
		if ph and ph.has_method("play_card"):
			ph.play_card(player_slot_index)
		await get_tree().create_timer(0.8).timeout
		# Step 4: Hide play area after effect
		if play_area:
			play_area.visible = false
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(opp_slot) and opp_slot is CanvasItem:
			opp_slot.modulate = Color(1,1,1,1)
		if is_instance_valid(player_slot) and player_slot is CanvasItem:
			player_slot.modulate = Color(1,1,1,1)
		print("[GM] Swap complete: Player card <-> Opponent card at %d" % player_slot_index)
	else:
		print("[GM] Swap failed: could not find valid slots to swap.")

## === GameManager: Deck Handling ===

func _connect_to_deck():
	if debug_logging:
		print("[GM] Deck connections are now handled internally by GameManager.")

func _on_deck_request_draw() -> void: # <-- THIS IS THE BIGGEST CHANGE
	if debug_logging:
		print("[GM] Player deck requested draw for slot index: %d" % _hand_index)
		
	# Get card data
	var candidates = _get_card_candidates()
	var chosen_path = _select_smart_card(candidates)
	var chosen_data = load(chosen_path) as CustomCardData
	if not chosen_data:
		push_warning("[GM] Failed to load chosen card: %s" % chosen_path)
		return

	# Get hand and deck nodes
	var player_hand = _scene_root().find_child("PlayerHand", true, false)
	var deck_node = _scene_root().find_child("Deck", true, false)
	if not player_hand or not deck_node:
		push_warning("[GM] PlayerHand or Deck node not found; cannot animate card draw.")
		return

	# Get animation parameters directly from PlayerHand
	var start_pos = deck_node.global_position
	var target_pos = player_hand.slot_positions[_hand_index]
	var target_rotation = player_hand.slot_rotations[_hand_index]
	var target_scale = player_hand.slot_scales[_hand_index]

	# Start animation, passing the slot INDEX instead of a slot NODE
	_start_card_animation(chosen_data, start_pos, target_pos, null, target_rotation, target_scale, CardScale, _hand_index)
	_update_deck_count(deck_node)


## === GameManager: Card Creation & Animation ===

func create_card(data: CustomCardData):
	var new_card = CardScene.instantiate()
	add_child(new_card)
	new_card.position = CardPosition
	new_card.scale = CardScale
	new_card.call_deferred("display", data)

# <-- CHANGED: Added p_slot_index parameter
func _start_card_animation(data: CustomCardData, start_pos: Vector2, target_pos: Vector2, target_slot: Node, final_rotation: float = 0.0, p_final_scale: Vector2 = Vector2.ONE, p_start_scale: Vector2 = Vector2.ONE, p_slot_index: int = -1) -> void:
	var animator = CardDrawAnimation.new()
	_card_layer.add_child(animator)
	animator.flip_duration = card_draw_flip_duration
	animator.move_duration = card_draw_move_duration
	animator.rotation_angle = card_draw_rotation
	animator.final_scale = p_final_scale

	var slot_path = "(null)"
	if target_slot != null:
		slot_path = target_slot.get_path()
	if debug_logging:
		print("[GM] _start_card_animation -> data:", data, " target_slot:", slot_path, " final_scale=", animator.final_scale, " slot_index=", p_slot_index)
		
	var suppress_reveal_flag = (target_slot != null and _is_slot_in_opponent_hand(target_slot))
	
	# <-- CHANGED: Bind the slot_index to the callback
	animator.connect("animation_finished", Callable(self, "_on_card_animation_finished").bind(data, target_slot, p_slot_index))
	animator.animate_card_draw(data, start_pos, target_pos, final_rotation, animator.final_scale, p_start_scale, suppress_reveal_flag)

# <-- CHANGED: Added slot_index parameter
func _on_card_animation_finished(animated_card: Control, _drawn_card_data: CustomCardData, _target_slot: Node, slot_index: int) -> void:
	# Opponent logic (uses _target_slot)
	if is_instance_valid(_target_slot) and _is_slot_in_opponent_hand(_target_slot):
		_target_slot.set_meta("hidden_card_data", _drawn_card_data)
		if _target_slot.has_method("display"):
			_target_slot.call_deferred("display", CardBackData)
		if _target_slot is CanvasItem:
			_target_slot.visible = true
		if is_instance_valid(animated_card):
			animated_card.queue_free()
		return

	# Player logic (uses slot_index)
	if slot_index != -1 and is_instance_valid(animated_card):
		var player_hand = _scene_root().find_child("PlayerHand", true, false)
		if player_hand:
			# The handoff! Give the animated card to PlayerHand.
			player_hand.call_deferred("receive_card_node", animated_card, slot_index, _drawn_card_data)
		else:
			# If hand not found, clean up the card to prevent memory leaks
			animated_card.queue_free()
	elif is_instance_valid(animated_card):
		# This case shouldn't happen, but if it does, clean up the card
		animated_card.queue_free()


func _is_slot_in_opponent_hand(slot: Node) -> bool:
	if not slot:
		return false
	var opp_hand = _scene_root().find_child("opponent_hand", true, false)
	if not opp_hand:
		return false
	var cur = slot
	while cur:
		if cur == opp_hand:
			return true
		cur = cur.get_parent()
	return false

## === GameManager: UI & Initialization Helpers ===
# (These functions are unchanged)
# ...
func _hide_placeholders():
	var ph = _scene_root().find_child("PlayerHand", true, false)
	if ph:
		for i in range(1, 5):
			var slot = ph.get_node_or_null("HandSlot" + str(i))
			if slot:
				slot.visible = false

func _configure_score_panels():
	var player_instance = _scene_root().find_child("PlayerScore", true, false)
	if player_instance and player_instance.has_node("OpponentScore"):
		player_instance.get_node("OpponentScore").visible = false
	var opponent_instance = _scene_root().find_child("OppScore", true, false)
	if opponent_instance and opponent_instance.has_node("PlayerScore"):
		opponent_instance.get_node("PlayerScore").visible = false

func _update_score_panels():
	var player_panel = _scene_root().find_child("PlayerScore", true, false)
	var opponent_panel = _scene_root().find_child("OppScore", true, false)
	if player_panel and player_panel.has_method("set_score"):
		player_panel.set_score(player_scores[0])
	if opponent_panel and opponent_panel.has_method("set_score"):
		opponent_panel.set_score(player_scores[1])

func _update_action_indicators():
	var score_panel = _scene_root().find_child("ScorePanel", true, false)
	if score_panel and score_panel.has_method("set_actions_left"):
		score_panel.set_actions_left(actions_left)

func _update_round_counter():
	var round_counter = _scene_root().find_child("round_counter", true, false)
	if round_counter and round_counter.has_method("set_round"):
		round_counter.set_round(round_number)

## === GameManager: Card Selection Logic ===
# (These functions are unchanged)
# ...
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

func _track_drawn_card(card_meta: Dictionary) -> void:
	_last_two_cards.append(card_meta)
	if _last_two_cards.size() > 2:
		_last_two_cards.pop_front()

## === GameManager: Utility Functions ===
# (These functions are mostly unchanged, removing ones we don't need anymore)
# ...
func _scene_root() -> Node:
	return get_tree().get_current_scene()

func _get_card_candidates() -> Array[String]:
	return [
		"res://scripts/resources/TwoDraw.tres", "res://scripts/resources/TwoSwap.tres",
		"res://scripts/resources/FourDraw.tres", "res://scripts/resources/FourSwap.tres",
		"res://scripts/resources/SixDraw.tres", "res://scripts/resources/SixSwap.tres",
		"res://scripts/resources/EightDraw.tres", "res://scripts/resources/EightSwap.tres",
		"res://scripts/resources/TenDraw.tres", "res://scripts/resources/TenSwap.tres"
	]

func _build_card_meta(path: String) -> Dictionary:
	var card_name = _extract_name_from_path(path)
	return {"value": _extract_value(card_name), "effect": _extract_effect(card_name), "path": path}

func _update_deck_count(deck_node: Node):
	if deck_node and deck_node.has_method("get_count") and deck_node.has_method("set_count"):
		var current_count = deck_node.call("get_count")
		deck_node.call("set_count", max(0, int(current_count) - 1))

func _extract_value(card_name: String) -> String:
	if card_name.begins_with("Two"): return "Two"
	if card_name.begins_with("Four"): return "Four"
	if card_name.begins_with("Six"): return "Six"
	if card_name.begins_with("Eight"): return "Eight"
	if card_name.begins_with("Ten"): return "Ten"
	return "Unknown"

func _extract_effect(card_name: String) -> String:
	if card_name.ends_with("Draw"): return "Draw"
	if card_name.ends_with("Swap"): return "Swap"
	return "Unknown"

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

# We no longer need _get_target_slot, _get_target_position, _get_target_rotation, or _get_slot_index
# as this logic is now handled directly in _on_deck_request_draw and _on_card_animation_finished
