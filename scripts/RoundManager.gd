extends Node

# RoundManager: orchestrates rounds, turns, and services
signal round_started(round_number: int)
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal round_ended(winner_data: Dictionary)
signal action_performed(player_id: int, action: Dictionary)
signal request_deal(hand_node: Node, slot_index: int)
signal request_opponent_card_choice(player_id: int)

enum State { ROUND_START, TURN_START, TURN_ACTIVE, TURN_RESOLVING, TURN_END, ROUND_END }
var state: State = State.ROUND_START
var current_round: int = 1
var current_player: int = 1
var actions_left: int = 2
var max_actions_per_turn: int = 2
# Who starts the round (Inspector-friendly dropdown):
# 0 = Random, 1 = Player, 2 = Opponent
enum FirstPlayer { Random, Player, Opponent }
# Inspector-friendly selection for who starts the round (Random/Player/Opponent)
@export var first_player: int = FirstPlayer.Random
var debug_logging: bool = true

# Internal guard: when true, start_turn will queue the request instead of executing it.
var _suspend_turns: bool = false
var _pending_start_player: int = -1

# Internal refs to hand nodes (optional caching)
var player_hand_node: Node = null
var opponent_hand_node: Node = null
var _pending_action = null
var _animator: Node = null
var _swap_anim_counter: int = 0
var _current_swap_action = null
var _swap_stage: int = 0 # 0=to play area, 1=to target slots
var _player_card_at_play_area: bool = false
var _action_resolver: Node = null
var _opponent_ai: Node = null

# Purpose: manage turn/round flow, AI, and hand/deck interactions
var _hand_controller: Node = null
# Internal counters used to synchronize auto-draw completion for opponent
var _rm_expected_opponent_draws: int = 0
var _rm_completed_opponent_draws: int = 0

# Helper: robustly count number of cards in a hand node.
func _count_hand_cards(hand_node: Node) -> int:
	if not hand_node:
		return 0
	# 1) Prefer HandController if available
	if _hand_controller and _hand_controller.has_method("get_card_count"):
		var c = _hand_controller.get_card_count(hand_node)
		if c != 0:
			return c
	# 2) If the hand node itself exposes get_card_count, use it
	if hand_node.has_method("get_card_count"):
		var c2 = hand_node.get_card_count()
		if c2 != 0:
			return c2
	# 3) Fallback: inspect known slot nodes for 'hidden_card_data' or 'card_data'
	var found = 0
	for child in hand_node.get_children():
		if child and child is Node:
			if child.has_meta("hidden_card_data") or child.has_meta("card_data"):
				found += 1
			elif child.visible and child.has_method("has_method") and child.has_method("get_child"):
				# try deeper search for nested slot nodes
				for desc in child.get_children():
					if desc and desc.has_meta and desc.has_meta("hidden_card_data"):
						found += 1
	return found

func _ready() -> void:
	# Connect our own request_deal signal to an internal handler so RoundManager
	# forwards deal requests directly to Deck. This removes the need for
	# GameManager to listen and forward the signal.
	if has_signal("request_deal"):
		connect("request_deal", Callable(self, "_on_request_deal"))

	# Bootstrap core services if they don't already exist as autoloads
	var root = get_tree().get_root()
	if not root.get_node_or_null("/root/ActionResolver"):
		var ar_scene = load("res://scripts/ActionResolver.gd")
		_action_resolver = ar_scene.new()
		root.call_deferred("add_child", _action_resolver)
	else:
		_action_resolver = root.get_node_or_null("/root/ActionResolver")

	if not root.get_node_or_null("/root/OpponentAI"):
		var ai_scene = load("res://scripts/OpponentAI.gd")
		_opponent_ai = ai_scene.new()
		_opponent_ai.name = "OpponentAI"
		root.call_deferred("add_child", _opponent_ai)
	else:
		_opponent_ai = root.get_node_or_null("/root/OpponentAI")

	if not root.get_node_or_null("/root/HandController"):
		var hc_scene = load("res://scripts/HandController.gd")
		_hand_controller = hc_scene.new()
		root.call_deferred("add_child", _hand_controller)
	else:
		_hand_controller = root.get_node_or_null("/root/HandController")

	# Connect ActionResolver's signal to a local handler so RoundManager can
	# forward resolution events to interested parties (GameManager listens too)
	if _action_resolver and _action_resolver.has_signal("action_resolved"):
		_action_resolver.connect("action_resolved", Callable(self, "_on_action_resolved"))


func _on_request_deal(hand_node: Node, slot_index: int) -> void:
	# Try scene-local Deck first, then fall back to an autoload path
	var deck = null
	var scene = get_tree().get_current_scene()
	if scene:
		deck = scene.find_child("Deck", true, false)
	if not deck:
		# try autoload or sibling lookup
		deck = get_node_or_null("/root/Deck")
		if not deck:
			deck = get_node_or_null("../Deck")
	if deck and deck.has_method("deal_to_slot"):
		deck.deal_to_slot(hand_node, slot_index)
	else:
		push_warning("[RM] Could not forward request_deal: Deck missing or does not expose deal_to_slot.")

# Start a new round and the first turn (scaffold behavior)
func start_round():
	# Choose who starts the round
	state = State.ROUND_START
	if first_player == 1:
		current_player = 1
	elif first_player == 2:
		current_player = 2
	else:
		current_player = 1 if randi() % 2 == 0 else 2
	if debug_logging:
		print("[RM] Starting round %d; player %d starts" % [current_round, current_player])
	emit_signal("round_started", current_round)
	# Give the GameManager time to show the round-start overlay.
	var gm = get_tree().get_root().find_child("GameManager", true, false)
	var round_wait: float = 0.8
	var turn_wait: float = 0.8
	if gm:
		if "round_overlay_duration" in gm:
			round_wait = float(gm.round_overlay_duration)
		elif "overlay_duration" in gm:
			# backward compatibility
			round_wait = float(gm.overlay_duration)
		if "turn_overlay_duration" in gm:
			turn_wait = float(gm.turn_overlay_duration)
		elif "overlay_duration" in gm:
			turn_wait = float(gm.overlay_duration)
	# Wait for overlay to hide (prefer signals) so animations do not overlap overlays
	var gm_node = get_tree().get_root().find_child("GameManager", true, false)
	if gm_node and gm_node.has_signal("overlay_hidden"):
		# await the overlay_hidden signal once
		await gm_node.wait_for_signal("overlay_hidden")
	else:
		await get_tree().create_timer(round_wait).timeout
	# Perform auto-draws for hands (opponent then player) before starting the first turn.
	# This prevents card draw completion from consuming the first turn's actions
	# and avoids a second `turn_started` being emitted during the draw sequence.
	await _auto_draw_hands()

	# Start the first turn (this will emit turn_started and let GameManager show turn overlay)
	start_turn(current_player)
	# Wait for the turn overlay to hide before proceeding
	if gm_node and gm_node.has_signal("overlay_hidden"):
		await gm_node.wait_for_signal("overlay_hidden")
	else:
		await get_tree().create_timer(turn_wait).timeout
	# Connect to Deck signals for resolving animations
	var deck = get_tree().get_current_scene().find_child("Deck", true, false)
	if deck:
		if deck.has_signal("card_animation_finished"):
			deck.connect("card_animation_finished", Callable(self, "_on_card_animation_finished"))
		if deck.has_signal("card_drawn"):
			deck.connect("card_drawn", Callable(self, "_on_deck_card_drawn"))

	# Grab services if present
	var root = get_tree().get_root()
	_action_resolver = root.get_node_or_null("/root/ActionResolver")
	_opponent_ai = root.get_node_or_null("/root/OpponentAI")
	_hand_controller = root.get_node_or_null("/root/HandController")

func _auto_draw_hands() -> void:
	# Find hand nodes in the current scene and emit request_deal for each slot
	var scene = get_tree().get_current_scene()
	# current_scene may be null when this runs early; wait a short while for it to become available
	var attempts := 0
	while not scene and attempts < 40:
		# wait 0.05s and retry
		await get_tree().create_timer(0.05).timeout
		scene = get_tree().get_current_scene()
		attempts += 1
	if not scene:
		push_warning("[RM] _auto_draw_hands: no current scene available after waiting; aborting auto-draw")
		return
	player_hand_node = scene.find_child("PlayerHand", true, false)
	if debug_logging:
		print("[RM] _auto_draw_hands: opponent=", opponent_hand_node, " player=", player_hand_node)
	# Suspend turn transitions while auto-drawing to avoid mid-draw turn changes
	_suspend_turns = true
	opponent_hand_node = scene.find_child("opponent_hand", true, false)
	if opponent_hand_node:
		if debug_logging:
			print("[RM] Dealing", opponent_hand_node.max_cards, "cards to OpponentHand")
		# Prepare synchronization counters
		_rm_expected_opponent_draws = opponent_hand_node.max_cards
		_rm_completed_opponent_draws = 0
		var deck = null
		if get_tree().get_current_scene():
			deck = get_tree().get_current_scene().find_child("Deck", true, false)
		if not deck:
			deck = get_node_or_null("/root/Deck")
		if deck and deck.has_signal("card_animation_finished"):
			# Connect to Deck so we observe when opponent slot animations finish
			if not deck.is_connected("card_animation_finished", Callable(self, "_on_deck_card_animation_observed")):
				deck.connect("card_animation_finished", Callable(self, "_on_deck_card_animation_observed"))

		for i in range(opponent_hand_node.max_cards):
			if debug_logging:
				print("[RM] OpponentHand auto-draw card", i)
			emit_signal("request_deal", opponent_hand_node, i)
			# small spacing between opponent draws (0.5s)
			await get_tree().create_timer(0.5).timeout

		# Wait for all expected opponent draw animations to complete (timeout to avoid hang)
		if deck and deck.has_signal("card_animation_finished"):
			var waited := 0.0
			var timeout := 5.0
			while _rm_completed_opponent_draws < _rm_expected_opponent_draws and waited < timeout:
				await get_tree().create_timer(0.1).timeout
				waited += 0.1
			if debug_logging:
				print("[RM] Observed opponent draw completions:", _rm_completed_opponent_draws, "of", _rm_expected_opponent_draws, " waited=", waited)
			# Disconnect our observer to avoid leaking connections
			if deck.is_connected("card_animation_finished", Callable(self, "_on_deck_card_animation_observed")):
				deck.disconnect("card_animation_finished", Callable(self, "_on_deck_card_animation_observed"))

	# short gap between opponent and player draws (0.5s)
	await get_tree().create_timer(0.5).timeout

	if player_hand_node:
		if debug_logging:
			print("[RM] Dealing", player_hand_node.max_cards, "cards to PlayerHand")
		for i in range(player_hand_node.max_cards):
			if debug_logging:
				print("[RM] PlayerHand auto-draw card", i)
			emit_signal("request_deal", player_hand_node, i)
			# small spacing between player draws (0.5s)
			await get_tree().create_timer(0.5).timeout

	if debug_logging:
		print("[RM] _auto_draw_hands: finished emitting deals for opponent and player")

	# Diagnostic: print opponent slot metadata to help debug AI decisions
	if debug_logging and opponent_hand_node:
		for i in range(opponent_hand_node.get_card_count()):
			var sn = null
			if opponent_hand_node.has_method("get_card_node"):
				sn = opponent_hand_node.get_card_node(i)
			else:
				sn = opponent_hand_node.get_slot(i) if opponent_hand_node.has_method("get_slot") else null
			if not sn:
				print("[RM] OppSlot", i, " -> no node")
				continue
			var has_hidden = sn.has_meta("hidden_card_data")
			var has_card = sn.has_meta("card_data")
			var meta_val = null
			if has_hidden:
				meta_val = sn.get_meta("hidden_card_data")
			elif has_card:
				meta_val = sn.get_meta("card_data")
			print("[RM] OppSlot", i, " visible=", sn.visible, " has_hidden=", has_hidden, " has_card=", has_card, " meta=", meta_val)

	# Auto-draws complete; resume normal turn handling and apply any queued start
	_suspend_turns = false
	if _pending_start_player != -1:
		var queued = _pending_start_player
		_pending_start_player = -1
		if debug_logging:
			print("[RM] Applying queued start_turn for player", queued)
		start_turn(queued)

func start_turn(player_id: int) -> void:
	# If turns are currently suspended (e.g., during auto-draw), queue the start
	if _suspend_turns:
		if debug_logging:
			print("[RM] start_turn queued for player", player_id)
		_pending_start_player = player_id
		return

	current_player = player_id
	actions_left = max_actions_per_turn
	state = State.TURN_ACTIVE
	if debug_logging:
		print("[RM] start_turn -> player=", player_id, " actions_left=", actions_left)
	emit_signal("turn_started", player_id)
	# If it's the opponent's turn, kick off the opponent AI flow
	if player_id != 1:
		# run opponent turn logic asynchronously
		_call_deferred_execute_opponent()

func _call_deferred_execute_opponent():
	# simple deferred runner to allow the signal handlers to process first
	call_deferred("_run_execute_opponent")

func _run_execute_opponent():
	_execute_opponent_turn()

func _get_card_animator() -> Node:
	if _animator and is_instance_valid(_animator):
		return _animator
	var root = get_tree().get_root()
	if root and root.has_node("CardAnimator"):
		_animator = root.get_node("CardAnimator")
		return _animator
	var maybe = get_node_or_null("/root/CardAnimator")
	if maybe:
		_animator = maybe
		return _animator
	return null

func _animate_played_card_to_discard(action: Dictionary) -> void:
	# Find source slot node and discard pile target
	var hand = action.get("hand")
	var slot_index = int(action.get("slot", -1))
	var slot_node = null
	if _hand_controller and _hand_controller.has_method("get_card_node"):
		slot_node = _hand_controller.get_card_node(hand, slot_index)
	elif hand and hand.has_method("get_card_node") and slot_index >= 0:
		slot_node = hand.get_card_node(slot_index)
	var discard_node = get_tree().get_current_scene().find_child("DiscardPile", true, false)
	var animator = _get_card_animator()
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	if animator and animator.has_method("animate_draw") and slot_node and play_area and discard_node:
		# Stage 1: animate from slot to play area
		var start_pos = slot_node.global_position
		var play_pos = play_area.global_position
		var played_card_meta = action.get("card_meta", null)
		if played_card_meta == null and slot_node:
			if slot_node.has_meta("card_data"):
				played_card_meta = slot_node.get_meta("card_data")
			elif slot_node.has_meta("hidden_card_data"):
				played_card_meta = slot_node.get_meta("hidden_card_data")
		animator.animate_draw(played_card_meta, start_pos, play_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_played_card_to_playarea_finished").bind(action))
	elif animator and animator.has_method("animate_draw") and slot_node and discard_node:
		# Fallback: animate directly to discard
		var start_pos = slot_node.global_position
		var target_pos = discard_node.global_position
		var played_card_meta = action.get("card_meta", null)
		if played_card_meta == null and slot_node:
			if slot_node.has_meta("card_data"):
				played_card_meta = slot_node.get_meta("card_data")
			elif slot_node.has_meta("hidden_card_data"):
				played_card_meta = slot_node.get_meta("hidden_card_data")
		animator.animate_draw(played_card_meta, start_pos, target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_played_card_to_discard_finished").bind(action))
	else:
		# No animator: immediately resolve
		_on_played_card_to_discard_finished(null, action)

func _on_played_card_to_playarea_finished(_animated_card: Control, action: Dictionary) -> void:
	# Once the played card reaches the play area, animate it from PlayArea to DiscardPile
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	var discard_node = get_tree().get_current_scene().find_child("DiscardPile", true, false)
	var animator = _get_card_animator()
	if animator and animator.has_method("animate_draw") and play_area and discard_node:
		animator.animate_draw(action.get("card_meta", null), play_area.global_position, discard_node.global_position, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_played_card_to_discard_finished").bind(action))
	else:
		_on_played_card_to_discard_finished(null, action)

func _on_played_card_to_discard_finished(_animated_card: Control, action: Dictionary) -> void:
	# After animation, request a draw (action.play was Draw effect)
	# Remove the played card from the originating hand if possible
	var hand = action.get("hand")
	var slot_index = int(action.get("slot", -1))
	if _hand_controller and _hand_controller.has_method("discard_card"):
		_hand_controller.discard_card(hand, slot_index)
	elif hand and hand.has_method("discard_card") and slot_index >= 0:
		hand.discard_card(slot_index)
	# Now request the deck deal for the draw effect
	emit_signal("request_deal", action.get("hand"), int(action.get("slot", -1)))

func _animate_swap_then_perform(action: Dictionary) -> void:
	# Animate both cards to a play area before swapping
	var p_hand = action.get("player_hand")
	var p_slot = int(action.get("player_slot", -1))
	var o_hand = action.get("opponent_hand")
	var o_slot = int(action.get("opponent_slot", -1))
	var p_node = null
	var o_node = null
	if _hand_controller and _hand_controller.has_method("get_card_node"):
		p_node = _hand_controller.get_card_node(p_hand, p_slot)
		o_node = _hand_controller.get_card_node(o_hand, o_slot)
	else:
		p_node = p_hand.get_card_node(p_slot) if p_hand and p_hand.has_method("get_card_node") else null
		o_node = o_hand.get_card_node(o_slot) if o_hand and o_hand.has_method("get_card_node") else null
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	var animator = _get_card_animator()
	_swap_anim_counter = 0
	_current_swap_action = action
	_swap_stage = 0
	# If animator present, animate each to play_area then when both finish call _perform_swap
	if animator and animator.has_method("animate_draw") and play_area:
		var target_pos = play_area.global_position
		if p_node:
			var p_card_meta = null
			if p_node.has_meta("card_data"):
				p_card_meta = p_node.get_meta("card_data")
			elif p_node.has_meta("hidden_card_data"):
				p_card_meta = p_node.get_meta("hidden_card_data")
			_swap_anim_counter += 1
			animator.animate_draw(p_card_meta, p_node.global_position, target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(action))
		if o_node:
			var o_card_meta = null
			if o_node.has_meta("card_data"):
				o_card_meta = o_node.get_meta("card_data")
			elif o_node.has_meta("hidden_card_data"):
				o_card_meta = o_node.get_meta("hidden_card_data")
			_swap_anim_counter += 1
			animator.animate_draw(o_card_meta, o_node.global_position, target_pos + Vector2(30,0), 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(action))
		if _swap_anim_counter == 0:
			_perform_swap(p_hand, p_slot, o_hand, o_slot, action.get("initiator", 2))
	else:
		# No animator: perform immediately
		_perform_swap(p_hand, p_slot, o_hand, o_slot, action.get("initiator", 2))

func begin_swap_for_player(action: Dictionary) -> void:
	# Animate only the player's card to PlayArea and then emit a signal requesting the player choose an opponent card
	var p_hand = action.get("player_hand")
	var p_slot = int(action.get("player_slot", -1))
	var p_node = null
	if _hand_controller and _hand_controller.has_method("get_card_node"):
		p_node = _hand_controller.get_card_node(p_hand, p_slot)
	else:
		p_node = p_hand.get_card_node(p_slot) if p_hand and p_hand.has_method("get_card_node") else null
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	var animator = _get_card_animator()
	_current_swap_action = action
	_swap_stage = 0
	_player_card_at_play_area = false
	# Animate player's card to play area
	if animator and animator.has_method("animate_draw") and p_node and play_area:
		animator.animate_draw(p_node.has_meta("card_data") and p_node.get_meta("card_data") or (p_node.has_meta("hidden_card_data") and p_node.get_meta("hidden_card_data") or null), p_node.global_position, play_area.global_position, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_player_card_at_playarea").bind(action))
	else:
		# If no animator, immediately treat as finished
		_on_player_card_at_playarea(null, action)

func _on_player_card_at_playarea(_animated_card: Control, _action: Dictionary) -> void:
	# Player card has reached play area; now request player's choice of opponent card
	# Emit signal; UI/GameManager should call `complete_swap_with_opponent(opponent_hand, opponent_slot)` when player picks
	_player_card_at_play_area = true
	emit_signal("request_opponent_card_choice", current_player)

func complete_swap_with_opponent(opponent_hand: Node, opponent_slot: int) -> void:
	# Continue the swap flow by animating the opponent's card into PlayArea and then animating both to target slots
	if _current_swap_action == null:
		push_warning("No active swap to complete")
		return
	# Attach opponent selection into current action and animate opponent card to play area
	var action = _current_swap_action
	action.opponent_hand = opponent_hand
	action.opponent_slot = opponent_slot
	var animator = _get_card_animator()
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	# If animator exists, animate opponent card to play area and then start second-stage animation
	var o_node = null
	if _hand_controller and _hand_controller.has_method("get_card_node"):
		o_node = _hand_controller.get_card_node(opponent_hand, opponent_slot)
	else:
		o_node = opponent_hand.get_card_node(opponent_slot) if opponent_hand and opponent_hand.has_method("get_card_node") else null
	if animator and animator.has_method("animate_draw") and o_node and play_area:
		# animate opponent into play area; when finished call _on_opponent_card_at_playarea
		animator.animate_draw(o_node.has_meta("card_data") and o_node.get_meta("card_data") or (o_node.has_meta("hidden_card_data") and o_node.get_meta("hidden_card_data") or null), o_node.global_position, play_area.global_position + Vector2(30,0), 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_opponent_card_at_playarea").bind(action))
	else:
		# No animator: immediately proceed to second-stage
		_animate_playarea_to_target_slots(action)

func _on_opponent_card_at_playarea(_animated_card: Control, action: Dictionary) -> void:
	# Opponent card arrived at play area; if player's card already present, animate both to target slots
	_player_card_at_play_area = _player_card_at_play_area or true
	_animate_playarea_to_target_slots(action)

func _animate_playarea_to_target_slots(action: Dictionary) -> void:
	# Animate from PlayArea to target slots for both cards, then rely on _on_swap_anim_finished to complete the swap
	var p_hand = action.get("player_hand")
	var p_slot = int(action.get("player_slot", -1))
	var o_hand = action.get("opponent_hand")
	var o_slot = int(action.get("opponent_slot", -1))
	var animator = _get_card_animator()
	var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
	if animator and animator.has_method("animate_draw") and play_area:
		_swap_anim_counter = 0
		var p_target_pos = null
		var o_target_pos = null
		if _hand_controller and _hand_controller.has_method("get_slot_position"):
			p_target_pos = _hand_controller.get_slot_position(p_hand, p_slot)
			o_target_pos = _hand_controller.get_slot_position(o_hand, o_slot)
		else:
			p_target_pos = p_hand.get_slot(p_slot).global_position if p_hand and p_hand.has_method("get_slot") else null
			o_target_pos = o_hand.get_slot(o_slot).global_position if o_hand and o_hand.has_method("get_slot") else null
		if p_target_pos:
			_swap_anim_counter += 1
			animator.animate_draw(null, play_area.global_position, p_target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(action))
		if o_target_pos:
			_swap_anim_counter += 1
			animator.animate_draw(null, play_area.global_position + Vector2(30,0), o_target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(action))
		_swap_stage = 1
		if _swap_anim_counter == 0:
			_perform_swap(p_hand, p_slot, o_hand, o_slot, action.get("initiator", 2))
	else:
		_perform_swap(action.get("player_hand"), int(action.get("player_slot")), action.get("opponent_hand"), int(action.get("opponent_slot")), 2)


func _on_action_resolved(player_id: int, action: Dictionary, result: Dictionary) -> void:
	# Process resolved commands from ActionResolver and execute them (draw/discard/swap/begin_swap)
	if debug_logging:
		print("[RM] ActionResolver result:", player_id, action, result)
	if not result:
		return
	if result.commands:
		for c in result.commands:
			var cmd = c.get("cmd", "")
			match cmd:
				"request_deal":
					emit_signal("request_deal", c.get("hand"), int(c.get("slot", -1)))
				"discard":
					if _hand_controller and _hand_controller.has_method("discard_card"):
						_hand_controller.discard_card(c.get("hand"), int(c.get("slot", -1)))
					elif c.get("hand") and c.get("hand").has_method("discard_card"):
						c.get("hand").discard_card(int(c.get("slot", -1)))
				"swap":
					_perform_swap(c.get("player_hand"), int(c.get("player_slot", -1)), c.get("opponent_hand"), int(c.get("opponent_slot", -1)), player_id)
				"begin_swap":
					begin_swap_for_player(c)
				"noop":
					pass

func _on_swap_anim_finished(_animated_card: Control, _action: Dictionary) -> void:
	_swap_anim_counter -= 1
	if _swap_anim_counter <= 0:
		if _swap_stage == 0:
			# Both arrived at play area: animate to target slots
			var cur_action = _current_swap_action
			var p_hand = cur_action.get("player_hand")
			var p_slot = int(cur_action.get("player_slot", -1))
			var o_hand = cur_action.get("opponent_hand")
			var o_slot = int(cur_action.get("opponent_slot", -1))
			var animator = _get_card_animator()
			var play_area = get_tree().get_current_scene().find_child("PlayArea", true, false)
			if animator and animator.has_method("animate_draw") and play_area:
				# Animate from play area to target slots
				_swap_anim_counter = 0
				var p_target_pos = null
				var o_target_pos = null
				if _hand_controller and _hand_controller.has_method("get_slot_position"):
					p_target_pos = _hand_controller.get_slot_position(p_hand, p_slot)
					o_target_pos = _hand_controller.get_slot_position(o_hand, o_slot)
				else:
					p_target_pos = p_hand.get_slot(p_slot).global_position if p_hand and p_hand.has_method("get_slot") else null
					o_target_pos = o_hand.get_slot(o_slot).global_position if o_hand and o_hand.has_method("get_slot") else null
				if p_target_pos:
					_swap_anim_counter += 1
					var return_p_meta = null
					var p_node_now = null
					if _hand_controller and _hand_controller.has_method("get_card_node"):
						p_node_now = _hand_controller.get_card_node(p_hand, p_slot)
					elif p_hand and p_hand.has_method("get_card_node"):
						p_node_now = p_hand.get_card_node(p_slot)
					if p_node_now and p_node_now.has_meta("card_data"):
						return_p_meta = p_node_now.get_meta("card_data")
					elif p_node_now and p_node_now.has_meta("hidden_card_data"):
						return_p_meta = p_node_now.get_meta("hidden_card_data")
					animator.animate_draw(return_p_meta, play_area.global_position, p_target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(cur_action))
				if o_target_pos:
					_swap_anim_counter += 1
					var return_o_meta = null
					var o_node_now = null
					if _hand_controller and _hand_controller.has_method("get_card_node"):
						o_node_now = _hand_controller.get_card_node(o_hand, o_slot)
					elif o_hand and o_hand.has_method("get_card_node"):
						o_node_now = o_hand.get_card_node(o_slot)
					if o_node_now and o_node_now.has_meta("card_data"):
						return_o_meta = o_node_now.get_meta("card_data")
					elif o_node_now and o_node_now.has_meta("hidden_card_data"):
						return_o_meta = o_node_now.get_meta("hidden_card_data")
					animator.animate_draw(return_o_meta, play_area.global_position + Vector2(30,0), o_target_pos, 0.0, Vector2.ONE, Vector2.ONE, false, Callable(self, "_on_swap_anim_finished").bind(cur_action))
				_swap_stage = 1
				if _swap_anim_counter == 0:
					_perform_swap(p_hand, p_slot, o_hand, o_slot, cur_action.get("initiator", 2))
			else:
				# No animator for second stage: perform immediately
				_perform_swap(cur_action.get("player_hand"), int(cur_action.get("player_slot")), cur_action.get("opponent_hand"), int(cur_action.get("opponent_slot")), 2)
		else:
			# Final stage complete
			var cur_action = _current_swap_action
			_perform_swap(cur_action.get("player_hand"), int(cur_action.get("player_slot")), cur_action.get("opponent_hand"), int(cur_action.get("opponent_slot")), 2)
			_current_swap_action = null
			_swap_stage = 0
# Example action: {"type":"draw", "hand": hand_node, "slot": 0}
func perform_action(player_id: int, action: Dictionary) -> void:
	if state != State.TURN_ACTIVE:
		push_warning("RoundManager: not accepting actions in current state")
		return
	if player_id != current_player:
		push_warning("RoundManager: action for wrong player")
		return
	if not action.has("type"):
		push_warning("RoundManager: action missing 'type'")
		return

	# Broadcast the action for observers (UI, analytics, etc.)
	emit_signal("action_performed", player_id, action)

	# Use ActionResolver if available
	if _action_resolver and _action_resolver.has_method("resolve_action"):
		var res = _action_resolver.resolve_action(player_id, action)
		if res and res.has("error"):
			push_warning("ActionResolver error: %s" % res.error)
			return
		# Execute returned commands conservatively
		if res.commands:
			for c in res.commands:
				match c.cmd:
					"request_deal":
						state = State.TURN_RESOLVING
						_pending_action = action
						# prefer hand controller when emitting
						if _hand_controller and _hand_controller.has_method("get_card_count"):
							emit_signal("request_deal", c.hand, int(c.slot))
						else:
							emit_signal("request_deal", c.hand, int(c.slot))
						# resolver indicates draw will consume action; consume after Deck callback
					"discard":
						if _hand_controller and _hand_controller.has_method("discard_card"):
							_hand_controller.discard_card(c.hand, int(c.slot))
						elif c.hand and c.hand.has_method("discard_card"):
							c.hand.discard_card(int(c.slot))
					"begin_swap":
						begin_swap_for_player(action)
					"swap":
						# animate and perform swap; prefer the resolver-provided initiator if present
						var initiator_id = c.get("initiator", player_id)
						_animate_swap_then_perform({"player_hand": c.player_hand, "player_slot": c.player_slot, "opponent_hand": c.opponent_hand, "opponent_slot": c.opponent_slot, "initiator": initiator_id})
			# consume actions if resolver indicated
			if res.has("consumed_actions") and res.consumed_actions > 0:
				actions_left -= int(res.consumed_actions)
				if actions_left <= 0:
					_end_turn()
				else:
					state = State.TURN_ACTIVE
		return

	# Fallback: no resolver, legacy behavior
	actions_left -= 1
	if actions_left <= 0:
		_end_turn()

func _end_turn() -> void:
	state = State.TURN_END
	emit_signal("turn_ended", current_player)
	# Switch player (simple alternation)
	var next_player = 1 if current_player == 2 else 2
	start_turn(next_player)

func _on_card_animation_finished(hand_node: Node, slot_index: int, card_data: CustomCardData) -> void:
	# Called when Deck emits that a card animation finished.
	if debug_logging:
		print("[RM] Card animation finished for hand", hand_node, "slot", slot_index, "card", card_data, " _pending_action=", _pending_action, " actions_left=", actions_left)
	# If we had a pending action (draw), resolve it now
	if _pending_action != null and _pending_action.type == "draw":
		_pending_action = null
		# consume an action and possibly end turn
		actions_left -= 1
		if actions_left <= 0:
			_end_turn()
		else:
			state = State.TURN_ACTIVE

func _perform_swap(player_hand: Node, player_slot: int, opponent_hand: Node, opponent_slot: int, initiator_player_id: int) -> void:
	# Perform a swap: discard played cards and move card_data between hands.
	if debug_logging:
		print("[RM] Performing swap: player_slot", player_slot, "opponent_slot", opponent_slot)
	var player_node = null
	var opp_node = null
	if _hand_controller and _hand_controller.has_method("get_card_node"):
		player_node = _hand_controller.get_card_node(player_hand, player_slot)
		opp_node = _hand_controller.get_card_node(opponent_hand, opponent_slot)
	else:
		if player_hand and player_hand.has_method("get_card_node"):
			player_node = player_hand.get_card_node(player_slot)
		if opponent_hand and opponent_hand.has_method("get_card_node"):
			opp_node = opponent_hand.get_card_node(opponent_slot)

	var player_card_data = null
	var opp_card_data = null
	# Extract card data depending on hidden vs visible
	if player_node:
		if player_node.has_meta("card_data"):
			player_card_data = player_node.get_meta("card_data")
		elif player_node.has_meta("hidden_card_data"):
			player_card_data = player_node.get_meta("hidden_card_data")
	if opp_node:
		if opp_node.has_meta("card_data"):
			opp_card_data = opp_node.get_meta("card_data")
		elif opp_node.has_meta("hidden_card_data"):
			opp_card_data = opp_node.get_meta("hidden_card_data")

	# Discard original slots where appropriate
	if _hand_controller and _hand_controller.has_method("discard_card"):
		_hand_controller.discard_card(player_hand, player_slot)
		_hand_controller.discard_card(opponent_hand, opponent_slot)
	else:
		if player_hand and player_hand.has_method("discard_card") and player_slot >= 0:
			player_hand.discard_card(player_slot)
		if opponent_hand and opponent_hand.has_method("discard_card") and opponent_slot >= 0:
			opponent_hand.discard_card(opponent_slot)

	# Give each player the other's card data (if present)
	if player_card_data:
		if _hand_controller and _hand_controller.has_method("add_card_to_hand"):
			_hand_controller.add_card_to_hand(opponent_hand, player_card_data)
		elif opponent_hand and opponent_hand.has_method("add_card_to_hand"):
			opponent_hand.add_card_to_hand(player_card_data)
	if opp_card_data:
		if _hand_controller and _hand_controller.has_method("add_card_to_hand"):
			_hand_controller.add_card_to_hand(player_hand, opp_card_data)
		elif player_hand and player_hand.has_method("add_card_to_hand"):
			player_hand.add_card_to_hand(opp_card_data)

	# Emit performed action and consume action
	emit_signal("action_performed", initiator_player_id, {"type": "swap", "player_slot": player_slot, "opponent_slot": opponent_slot})
	actions_left -= 1
	if actions_left <= 0:
		_end_turn()
	else:
		state = State.TURN_ACTIVE

func _on_deck_card_drawn(card_meta: Dictionary) -> void:
	# Deck emitted metadata for a drawn card; RoundManager can log or update state
	if debug_logging:
		print("[RM] Deck card_drawn:", card_meta)

func _on_deck_card_animation_observed(hand_node: Node, slot_index: int, _card_data: CustomCardData) -> void:
	# Observe Deck's card_animation_finished events and count opponent completions
	if not hand_node:
		return
	# Only count opponent hand completions for the auto-draw synchronization
	var scene = get_tree().get_current_scene()
	var opp = opponent_hand_node if opponent_hand_node else (scene.find_child("opponent_hand", true, false) if scene else null)
	if hand_node == opp:
		_rm_completed_opponent_draws += 1
		if debug_logging:
			print("[RM] _on_deck_card_animation_observed: opponent slot", slot_index, "completed ->", _rm_completed_opponent_draws)

func _execute_opponent_turn() -> void:
	# Borrowed logic from GameManager for opponent actions; operates on scene hand nodes.
	if debug_logging:
		print("[RM] Executing opponent's turn.")
	# Small safety delay to allow any pending auto-draw reparent/display operations to complete.
	# This helps avoid a race where the hand reports zero cards immediately after draws.
	await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.0).timeout
	# Resolve scene hand nodes
	var scene = get_tree().get_current_scene()
	var oh = opponent_hand_node if opponent_hand_node else (scene.find_child("opponent_hand", true, false) if scene else null)
	var ph = player_hand_node if player_hand_node else (scene.find_child("PlayerHand", true, false) if scene else null)

	# Debug: report hand nodes and counts before calling AI
	if debug_logging:
		print("[RM] _execute_opponent_turn: opponent_hand=", oh, " opponent_count=", _count_hand_cards(oh), " player_hand=", ph, " player_count=", _count_hand_cards(ph))

	# Ensure OpponentAI service exists and exposes the expected API. If missing, create it.
	if not _opponent_ai or not is_instance_valid(_opponent_ai):
		var root = get_tree().get_root()
		var ai_scene = load("res://scripts/OpponentAI.gd")
		_opponent_ai = ai_scene.new()
		root.call_deferred("add_child", _opponent_ai)

	if not _opponent_ai or not _opponent_ai.has_method("decide_next_action"):
		push_warning("[RM] OpponentAI missing or does not expose decide_next_action; ending opponent turn.")
		_end_turn()
		return

	# Use the OpponentAI for every opponent action; legacy inline logic has been removed.
	for i in range(max_actions_per_turn):
		var opp_count = _count_hand_cards(oh)
		if not oh or opp_count == 0:
			if debug_logging:
				print("[RM] Opponent has no cards to play.")
			break

		var chosen = _opponent_ai.decide_next_action(oh, ph)
		if not chosen:
			if debug_logging:
				print("[RM] OpponentAI returned no action; skipping")
			continue
		var ctype = chosen.get("type", "pass")
		if ctype == "pass":
			if debug_logging:
				print("[RM] OpponentAI chose to pass.")
			continue

		# If AI returns a play action with a slot, attempt a brief reveal for UX
		if chosen.has("slot") and oh:
			var cnode = null
			if _hand_controller and _hand_controller.has_method("get_card_node"):
				cnode = _hand_controller.get_card_node(oh, int(chosen.slot))
			elif oh.has_method("get_card_node"):
				cnode = oh.get_card_node(int(chosen.slot))
			var meta = null
			if cnode and cnode.has_meta("hidden_card_data"):
				meta = cnode.get_meta("hidden_card_data")
				if cnode and cnode.has_method("display"):
					cnode.display(meta)
				# small pause for reveal
				await get_tree().create_timer(0.6).timeout

		# Delegate execution to RoundManager so animations/resolution pipeline is respected
		perform_action(2, chosen)
		# brief pause between actions
		await get_tree().create_timer(0.5).timeout

	# End opponent turn after AI-driven actions
	_end_turn()

func end_round(_reason: Dictionary = {}) -> void:
	state = State.ROUND_END
	# Calculate hand totals if hand nodes are present
	var p1_total = -1
	var p2_total = -1
	if player_hand_node and player_hand_node.has_method("get_hand_total"):
		p1_total = player_hand_node.get_hand_total()
	else:
		# Fallback: attempt to compute from card_data_map
		if player_hand_node and player_hand_node.has_method("card_data_map"):
			p1_total = 0
			var map = player_hand_node.card_data_map
			for i in range(map.size()):
				var cd = map[i]
				if cd and typeof(cd) == TYPE_DICTIONARY and "effect_value" in cd:
					p1_total += cd.effect_value
	if _hand_controller and _hand_controller.has_method("get_hand_total"):
		p1_total = _hand_controller.get_hand_total(player_hand_node)
		p2_total = _hand_controller.get_hand_total(opponent_hand_node)
	elif opponent_hand_node and opponent_hand_node.has_method("get_hand_total"):
		p2_total = opponent_hand_node.get_hand_total()
	else:
		if opponent_hand_node and opponent_hand_node.has_method("card_data_map"):
			p2_total = 0
			var map2 = opponent_hand_node.card_data_map
			for i in range(map2.size()):
				var cd2 = map2[i]
				if cd2 and typeof(cd2) == TYPE_DICTIONARY and "effect_value" in cd2:
					p2_total += cd2.effect_value

	var winner = 0
	if p1_total >= 0 and p2_total >= 0:
		if p1_total < p2_total:
			winner = 1
		elif p2_total < p1_total:
			winner = 2
		else:
			winner = 0

	var payload = {"winner": winner, "p1_total": p1_total, "p2_total": p2_total, "round": current_round}
	emit_signal("round_ended", payload)
	# advance round counter for future rounds
	current_round += 1

# Utility: external callers can force a turn start
func force_start_turn(player_id: int) -> void:
	start_turn(player_id)
