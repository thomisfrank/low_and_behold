extends Node

# test_action_resolver.gd
# Small integration-style tests for ActionResolver.resolve_action

func _ready():
	var ar = load("res://scripts/ActionResolver.gd").new()
	# Test: draw action
	var draw_action = {"type": "draw", "hand": null, "slot": 0}
	var res = ar.resolve_action(1, draw_action)
	assert(res and res.commands.size() == 1 and res.commands[0].cmd == "request_deal")
	print("PASS: draw -> request_deal")

	# Test: play draw effect with hand and slot
	var play_draw = {"type": "play", "effect": "Draw", "hand": null, "slot": 1}
	res = ar.resolve_action(1, play_draw)
	assert(res and res.commands.size() == 2 and res.commands[0].cmd == "discard" and res.commands[1].cmd == "request_deal")
	print("PASS: play Draw -> discard + request_deal")

	# Test: play swap begin (no opponent specified)
	var play_swap_begin = {"type": "play", "effect": "Swap", "player_hand": null, "player_slot": 2}
	res = ar.resolve_action(1, play_swap_begin)
	assert(res and res.commands.size() >= 1 and res.commands[0].cmd == "begin_swap")
	print("PASS: play Swap (begin)")

	# Test: play swap with opponent
	var play_swap_full = {"type": "play", "effect": "Swap", "player_hand": null, "player_slot": 2, "opponent_hand": null, "opponent_slot": 0, "initiator": 2}
	res = ar.resolve_action(2, play_swap_full)
	assert(res and res.commands.size() >= 1 and res.commands[0].cmd == "swap" and res.commands[0].initiator == 2)
	print("PASS: play Swap (full) -> swap")

	# Test: Card_Back via card_meta
	var card_meta_back = {"effect": "Card_Back"}
	var card_back_action = {"type": "play", "card_meta": card_meta_back}
	res = ar.resolve_action(1, card_back_action)
	assert(res and res.commands.size() == 1 and res.commands[0].cmd == "noop")
	print("PASS: Card_Back -> noop")

	print("All ActionResolver tests passed.")
	get_tree().quit()
