extends Node

# HandController: small adapter/wrapper for hand node operations.
# This lets other systems call into a stable API instead of directly
# depending on specific hand node implementations.

func get_card_node(hand: Node, slot: int) -> Node:
    if not hand:
        return null
    if hand.has_method("get_card_node"):
        return hand.get_card_node(slot)
    return null

func discard_card(hand: Node, slot: int) -> void:
    if not hand:
        return
    if hand.has_method("discard_card"):
        hand.discard_card(slot)

func add_card_to_hand(hand: Node, card_data: Dictionary) -> void:
    if not hand:
        return
    if hand.has_method("add_card_to_hand"):
        hand.add_card_to_hand(card_data)

func get_slot_position(hand: Node, slot: int) -> Vector2:
    if not hand:
        return Vector2.ZERO
    if hand.has_method("get_slot"):
        var s = hand.get_slot(slot)
        if s:
            return s.global_position
    return Vector2.ZERO

func get_slot_node(hand: Node, slot: int) -> Node:
    if not hand:
        return null
    if hand.has_method("get_slot"):
        return hand.get_slot(slot)
    return null

func get_card_count(hand: Node) -> int:
    if not hand:
        return 0
    if hand.has_method("get_card_count"):
        return int(hand.get_card_count())
    return 0

func get_hand_total(hand: Node) -> int:
    if not hand:
        return -1
    if hand.has_method("get_hand_total"):
        return int(hand.get_hand_total())
    # Fallback: try to compute from card_data_map if present
    if hand.has_method("card_data_map") or hand.has_meta("card_data_map") or hand.get("card_data_map") != null:
        var total = 0
        var map = hand.card_data_map
        for i in range(map.size()):
            var cd = map[i]
            if cd and typeof(cd) == TYPE_DICTIONARY and "effect_value" in cd:
                total += cd.effect_value
        return total
    return -1

func get_first_filled_slot(hand: Node) -> int:
    if not hand or not hand.has_method("get_card_count"):
        return -1
    for i in range(hand.get_card_count()):
        var n = get_card_node(hand, i)
        if n:
            if n.has_meta("card_data") or n.has_meta("hidden_card_data"):
                return i
    return -1

func lock_card(hand: Node, slot: int) -> void:
    if not hand:
        return
    if hand.has_method("lock_card"):
        hand.lock_card(slot)

func unlock_card(hand: Node, slot: int) -> void:
    if not hand:
        return
    if hand.has_method("unlock_card"):
        hand.unlock_card(slot)

func play_card(hand: Node, slot: int) -> void:
    if not hand:
        return
    if hand.has_method("play_card"):
        hand.play_card(slot)

func get_card_meta(hand: Node, slot: int) -> Dictionary:
    var node = get_card_node(hand, slot)
    if node:
        if node.has_meta("card_data"):
            return node.get_meta("card_data")
        if node.has_meta("hidden_card_data"):
            return node.get_meta("hidden_card_data")
    return {}

func discard_all_cards(hand: Node) -> void:
    if not hand:
        return
    if hand.has_method("discard_all_cards"):
        hand.discard_all_cards()

func enable_swap_selection(hand: Node) -> void:
    if not hand:
        return
    if hand.has_method("enable_swap_selection"):
        hand.enable_swap_selection()

func disable_swap_selection(hand: Node) -> void:
    if not hand:
        return
    if hand.has_method("disable_swap_selection"):
        hand.disable_swap_selection()
