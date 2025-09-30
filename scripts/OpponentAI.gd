extends Node

# OpponentAI.gd - simple opponent decision helper

func _count_cards(h: Node) -> int:
    var hc = get_tree().get_root().get_node_or_null("/root/HandController")
    if hc and hc.has_method("get_card_count"):
        return hc.get_card_count(h)
    if h and h.has_method("get_card_count"):
        return h.get_card_count()
    return 0

func _get_card_node(h: Node, idx: int) -> Node:
    var hc = get_tree().get_root().get_node_or_null("/root/HandController")
    if hc and hc.has_method("get_card_node"):
        return hc.get_card_node(h, idx)
    if h and h.has_method("get_card_node"):
        return h.get_card_node(idx)
    return null

func decide_next_action(opponent_hand: Node, player_hand: Node) -> Dictionary:
    # Very simple heuristic: prefer Draw effect if available, otherwise Swap if valid, otherwise pass
    var res = {"type": "pass"}
    if not opponent_hand or _count_cards(opponent_hand) == 0:
        return res

    for i in range(_count_cards(opponent_hand)):
        var node = _get_card_node(opponent_hand, i)
        if node and node.has_meta("hidden_card_data"):
            var data = node.get_meta("hidden_card_data")
            if data.effect_type == CustomCardData.EffectType.Draw_Card:
                res = {"type": "play", "effect": "Draw", "hand": opponent_hand, "slot": i}
                return res

    # fallback: swap if player has cards
    if player_hand and _count_cards(player_hand) > 0:
        for i in range(_count_cards(opponent_hand)):
            var node = _get_card_node(opponent_hand, i)
            if node and node.has_meta("hidden_card_data"):
                var data = node.get_meta("hidden_card_data")
                if data.effect_type == CustomCardData.EffectType.Swap_Card:
                    var player_slot = randi() % _count_cards(player_hand)
                    return {"type": "play", "effect": "Swap", "player_hand": opponent_hand, "player_slot": i, "opponent_hand": player_hand, "opponent_slot": player_slot}
    return res
