

extends Node2D

# Minimal GameManager: small, well-documented, guarded debug prints.

@export var debug_logging: bool = false
@export var overlay_duration: float = 0.8
@export var overlay_alpha: float = 0.6
@export var CardScale: Vector2 = Vector2(0.42, 0.42)
@export var card_final_scale: Vector2 = Vector2(0.8, 0.8)

var _round_manager: Node = null
var _awaiting_roundmanager_swap: bool = false
var player_scores: Array[int] = [0, 0]
var deck_draw_history: Array = []
var _hand_index: int = 0
var RoundManagerClass = null

func _ready() -> void:
	randomize()
	# Sanity clamps
	if card_final_scale.x < 0.1 or card_final_scale.y < 0.1:
		push_warning("[GM] card_final_scale too small; forcing to (0.8,0.8)")
		card_final_scale = Vector2(0.8, 0.8)
	if CardScale.x < 0.01 or CardScale.y < 0.01:
		push_warning("[GM] CardScale too small; forcing to (0.42,0.42)")
		CardScale = Vector2(0.42, 0.42)

	if debug_logging:
		print("[GM] Default Card Scales: " + str(CardScale) + " -> " + str(card_final_scale))

	_hide_placeholders()
	_configure_score_panels()
	_connect_to_deck()

	# connect opponent-hand swap signal if available
	var oh = _scene_root().find_child("opponent_hand", true, false)
	if oh and oh.has_signal("swap_card_selected"):
		oh.connect("swap_card_selected", Callable(self, "_on_opponent_swap_card_selected"))

	# bootstrap RoundManager
	if not RoundManagerClass:
		RoundManagerClass = load("res://scripts/RoundManager.gd")
	if RoundManagerClass:
		_round_manager = RoundManagerClass.new()
		get_tree().get_root().call_deferred("add_child", _round_manager)
		if _round_manager.has_signal("turn_started"):
			_round_manager.connect("turn_started", Callable(self, "_on_round_turn_started"))
		if _round_manager.has_signal("round_ended"):
			_round_manager.connect("round_ended", Callable(self, "_on_round_ended"))
		if _round_manager.has_signal("request_opponent_card_choice"):
			_round_manager.connect("request_opponent_card_choice", Callable(self, "_on_request_opponent_card_choice"))
	else:
		push_warning("[GM] Could not load RoundManager.gd")

	if _round_manager and _round_manager.has_method("start_round"):
		call_deferred("_deferred_start_round_via_manager")
	else:
		call_deferred("start_round")


# === Round bootstrapping ===
func _deferred_start_round_via_manager() -> void:
	if _round_manager and _round_manager.has_method("start_round"):
		_round_manager.start_round()


# === Turn handling ===
func _start_player_turn(player_num: int) -> void:
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	var overlay_text = "Your Turn" if player_num == 1 else "Opponent Turn"
	_show_game_state_overlay(overlay_text)
	await get_tree().create_timer(overlay_duration).timeout
	_hide_game_state_overlay()
	if player_num == 1:
		if ph:
			ph.set_process_input(true)
			ph.set_process(true)
		if oh:
			oh.set_process_input(false)
			oh.set_process(false)
	else:
		if ph:
			ph.set_process_input(false)
			ph.set_process(false)
		if oh:
			oh.set_process_input(true)
			oh.set_process(true)


func _on_round_turn_started(player_id: int) -> void:
	if debug_logging:
		print("[GM] turn_started ->", player_id)
	_show_game_state_overlay("Your Turn" if player_id == 1 else "Opponent Turn")
	await get_tree().create_timer(overlay_duration).timeout
	_hide_game_state_overlay()


# === Player actions ===
func player_action_from_hand(card_index: int) -> void:
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var hc = _get_hand_controller()
	var played_card_data = {}
	if hc and hc.has_method("get_card_meta"):
		played_card_data = hc.get_card_meta(ph, card_index)
	elif ph and ph.card_data_map.size() > card_index:
		played_card_data = ph.card_data_map[card_index]

	var play_area = _scene_root().find_child("PlayArea", true, false)
	if play_area:
		play_area.visible = true
	await get_tree().create_timer(0.8).timeout

	if debug_logging:
		print("[GM] Card revealed in play area.")

	await get_tree().create_timer(0.8).timeout
	if played_card_data:
		if debug_logging:
			print("[GM] Played card idx=" + str(card_index) + " effect=" + str(played_card_data.effect_type))
		match played_card_data.effect_type:
			CustomCardData.EffectType.Draw_Card:
				if hc and hc.has_method("play_card"):
					hc.play_card(ph, card_index)
				elif ph and ph.has_method("play_card"):
					ph.play_card(card_index)
				_hand_index = card_index
				await get_tree().create_timer(0.8).timeout
				_on_deck_request_draw()
			CustomCardData.EffectType.Swap_Card:
				if debug_logging:
					print("[GM] effect=Swap -> enabling opponent selection")
				var oh = _scene_root().find_child("opponent_hand", true, false)
				if hc and hc.has_method("enable_swap_selection"):
					hc.enable_swap_selection(oh)
				elif oh and oh.has_method("enable_swap_selection"):
					oh.enable_swap_selection()
				if hc and hc.has_method("lock_card"):
					hc.lock_card(ph, card_index)
				elif ph and ph.has_method("lock_card"):
					ph.lock_card(card_index)
				await get_tree().create_timer(0.8).timeout
			_:
				if hc and hc.has_method("play_card"):
					hc.play_card(ph, card_index)
				elif ph and ph.has_method("play_card"):
					ph.play_card(card_index)
				await get_tree().create_timer(0.8).timeout
	else:
		if debug_logging:
			print("[GM] Played card missing metadata at index " + str(card_index))
		if ph and ph.has_method("play_card"):
			ph.play_card(card_index)
		await get_tree().create_timer(0.8).timeout

	if play_area:
		play_area.visible = false
	await get_tree().create_timer(0.5).timeout


func _end_player_turn() -> void:
	if debug_logging:
		print("[GM] Player turn ended -> switching")
	if _round_manager and _round_manager.has_method("start_turn"):
		_round_manager.call_deferred("start_turn")


# === Round end and scoring ===
func _end_round() -> void:
	if debug_logging:
		print("[GM] Ending round")
	var p1_total = _calculate_hand_total(_scene_root().find_child("PlayerHand", true, false))
	var p2_total = _calculate_hand_total(_scene_root().find_child("opponent_hand", true, false))
	if debug_logging:
		print("[GM] Scores: ", p1_total, p2_total)
	if p1_total < p2_total:
		player_scores[0] += p1_total
	elif p2_total < p1_total:
		player_scores[1] += p2_total
	_update_score_panels()


func _on_round_ended(payload: Dictionary) -> void:
	if debug_logging:
		print("[GM] Round ended payload: " + str(payload))
	var p1_total = payload.get("p1_total", -1)
	var p2_total = payload.get("p2_total", -1)
	var winner = payload.get("winner", 0)
	if p1_total >= 0 and p2_total >= 0:
		if winner == 1:
			player_scores[0] += p1_total
		elif winner == 2:
			player_scores[1] += p2_total
	_update_round_counter()
	var round_end_scene = preload("res://scenes/round_end_screen.tscn").instantiate()
	if round_end_scene.has_method("set_scores"):
		round_end_scene.set_scores(player_scores[0], player_scores[1], p1_total, p2_total)
	if round_end_scene.has_signal("continue_pressed"):
		round_end_scene.connect("continue_pressed", Callable(self, "_on_round_end_continue"))
	get_tree().get_root().add_child(round_end_scene)


func _on_request_opponent_card_choice(player_id: int) -> void:
	if debug_logging:
		print("[GM] request_opponent_card_choice ->", player_id)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	if oh and oh.has_method("enable_swap_selection"):
		oh.enable_swap_selection()
	_awaiting_roundmanager_swap = true


func end_game() -> void:
	if debug_logging:
		print("[GM] Game Over")
	var winner = 1 if player_scores[0] > player_scores[1] else 2 if player_scores[1] > player_scores[0] else 0
	var result_text = "Game Over! "
	if winner == 0:
		result_text += "It's a tie! Final Score: %d - %d" % [player_scores[0], player_scores[1]]
	else:
		result_text += "Player %d wins! Final Score: %d - %d" % [winner, player_scores[0], player_scores[1]]
	_show_game_state_overlay(result_text)


# === Helpers ===
func _calculate_hand_total(hand_node):
	var hc = _get_hand_controller()
	if hc and hc.has_method("get_hand_total"):
		return hc.get_hand_total(hand_node)
	if hand_node and hand_node.has_method("get_hand_total"):
		return hand_node.get_hand_total()
	var total = 0
	if hand_node and hand_node.has_method("card_data_map"):
		var card_data_map = hand_node.card_data_map
		for i in range(card_data_map.size()):
			var hand_card_data = card_data_map[i]
			if hand_card_data and "effect_value" in hand_card_data:
				total += int(hand_card_data.effect_value)
	return total


func _discard_hands() -> void:
	if debug_logging:
		print("[GM] Discarding all cards from hands")
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	var hc = _get_hand_controller()
	if hc and hc.has_method("discard_all_cards"):
		hc.discard_all_cards(ph)
		hc.discard_all_cards(oh)
	else:
		if ph and ph.has_method("discard_all_cards"):
			ph.discard_all_cards()
		if oh and oh.has_method("discard_all_cards"):
			oh.discard_all_cards()
	_update_score_panels()



## === GameManager: Swap Logic ===
func _on_opponent_swap_card_selected(index: int) -> void:
	if debug_logging:
		print("[GM] Opponent swap selected ->", index)
	var oh = _scene_root().find_child("opponent_hand", true, false)
	var ph = _scene_root().find_child("PlayerHand", true, false)
	var hc = _get_hand_controller()
	if hc and hc.has_method("disable_swap_selection"):
		hc.disable_swap_selection(oh)
	elif oh and oh.has_method("disable_swap_selection"):
		oh.disable_swap_selection()

	# If RoundManager requested an opponent card choice, forward to it
	if _awaiting_roundmanager_swap and _round_manager and _round_manager.has_method("complete_swap_with_opponent"):
		_awaiting_roundmanager_swap = false
		_round_manager.complete_swap_with_opponent(oh, index)
		return

	# fallback legacy swap (keeps visuals)
	var player_slot_index = -1
	if hc and hc.has_method("get_first_filled_slot"):
		player_slot_index = hc.get_first_filled_slot(ph)
	elif ph and ph.has_method("get_first_filled_slot_index"):
		player_slot_index = ph.get_first_filled_slot_index()

	if player_slot_index == -1:
		if debug_logging:
			print("[GM] Swap failed: no valid player slot")
		return

	if _round_manager and _round_manager.has_method("perform_action"):
		var action = {"type": "play", "effect": "Swap", "player_hand": ph, "player_slot": player_slot_index, "opponent_hand": oh, "opponent_slot": index}
		_round_manager.perform_action(2, action)
	else:
		# legacy visual swap
		if debug_logging:
			print("[GM] Performing legacy swap visuals")
		# minimal visual feedback
		var play_area = _scene_root().find_child("PlayArea", true, false)
		if play_area:
			play_area.visible = true
		await get_tree().create_timer(0.8).timeout
		if play_area:
			play_area.visible = false



## === Deck hookup ===
func _connect_to_deck() -> void:
	if debug_logging:
		print("[GM] Connecting to Deck signals")
	var deck_node = _scene_root().find_child("Deck", true, false)
	if deck_node and deck_node.has_signal("card_drawn"):
		deck_node.connect("card_drawn", Callable(self, "_on_deck_card_drawn"))


func _on_deck_card_drawn(card_meta: Dictionary) -> void:
	if debug_logging:
		print("[GM] _on_deck_card_drawn: " + str(card_meta))
	deck_draw_history.append(card_meta)
	if deck_draw_history.size() > 20:
		deck_draw_history.pop_front()


func _on_action_resolved(player_id: int, action: Dictionary, result: Dictionary) -> void:
	if debug_logging:
		print("[GM] Action resolved ->", player_id, action, result)
	if result and result.commands:
		for c in result.commands:
			if c.cmd == "begin_swap":
				var _oh = _scene_root().find_child("opponent_hand", true, false)
				if _oh and _oh.has_method("enable_swap_selection"):
					_oh.enable_swap_selection()
				return


func _on_deck_request_draw() -> void:
	if debug_logging:
		print("[GM] request_draw slot ->" + str(_hand_index))
	var deck_node = _scene_root().find_child("Deck", true, false)
	var player_hand = _scene_root().find_child("PlayerHand", true, false)
	if deck_node and deck_node.has_method("deal_to_slot") and player_hand:
		deck_node.deal_to_slot(player_hand, _hand_index)
	else:
		push_warning("[GM] Could not deal card: Deck or PlayerHand missing or deal() not found.")


## === UI Helpers ===
func _hide_placeholders() -> void:
	var ph = _scene_root().find_child("PlayerHand", true, false)
	if ph:
		for i in range(1, 5):
			var slot = ph.get_node_or_null("HandSlot" + str(i))
			if slot:
				slot.visible = false


func _configure_score_panels() -> void:
	var player_instance = _scene_root().find_child("PlayerScore", true, false)
	if player_instance and player_instance.has_node("OpponentScore"):
		player_instance.get_node("OpponentScore").visible = false
	var opponent_instance = _scene_root().find_child("OppScore", true, false)
	if opponent_instance and opponent_instance.has_node("PlayerScore"):
		opponent_instance.get_node("PlayerScore").visible = false


func _update_score_panels() -> void:
	var player_panel = _scene_root().find_child("PlayerScore", true, false)
	var opponent_panel = _scene_root().find_child("OppScore", true, false)
	if player_panel and player_panel.has_method("set_score"):
		player_panel.set_score(player_scores[0])
	if opponent_panel and opponent_panel.has_method("set_score"):
		opponent_panel.set_score(player_scores[1])


func _update_action_indicators() -> void:
	var score_panel = _scene_root().find_child("ScorePanel", true, false)
	if score_panel and score_panel.has_method("set_actions_left"):
		score_panel.set_actions_left(0)


func _update_round_counter() -> void:
	var round_counter = _scene_root().find_child("round_counter", true, false)
	if round_counter and round_counter.has_method("set_round"):
		round_counter.set_round(0)


func _scene_root() -> Node:
	return get_tree().get_current_scene()


func _get_hand_controller():
	var root = get_tree().get_root()
	if root.has_node("HandController"):
		return root.get_node("HandController")
	return null


func _show_game_state_overlay(text: String) -> void:
	# Non-invasive overlay helper: if a node named 'GameOverlay' exists, set text and show it.
	if debug_logging:
		print("[GM] overlay ->", text)
	var overlay = _scene_root().find_child("GameOverlay", true, false)
	if overlay:
		if overlay.has_method("set_text"):
			overlay.set_text(text)
		overlay.visible = true


func _hide_game_state_overlay() -> void:
	var overlay = _scene_root().find_child("GameOverlay", true, false)
	if overlay:
		overlay.visible = false
