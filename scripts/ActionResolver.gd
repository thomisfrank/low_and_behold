extends Node

signal action_resolved(player_id: int, action: Dictionary, result: Dictionary)

# ActionResolver - computes logical commands for actions; does not perform animations.

func resolve_action(player_id: int, action: Dictionary) -> Dictionary:
    var result := {"commands": []}
    if not action.has("type"):
        result.error = "missing_type"
        return result

    if action.type == "draw":
        if action.has("hand") and action.has("slot"):
            result.commands.append({"cmd": "request_deal", "hand": action.hand, "slot": int(action.slot)})
            result.consumed_actions = 1
            emit_signal("action_resolved", player_id, action, result)
            return result
        else:
            result.error = "invalid_draw_args"
            return result

    if action.type == "discard":
        if action.has("hand") and action.has("slot"):
            result.commands.append({"cmd": "discard", "hand": action.hand, "slot": int(action.slot)})
            result.consumed_actions = 1
            emit_signal("action_resolved", player_id, action, result)
            return result
        else:
            result.error = "invalid_discard_args"
            return result

    if action.type == "play":
        # Determine effect from several possible places: explicit field, metadata dict, or CustomCardData
        var effect = action.get("effect", "")
        var card_meta = action.get("card_meta", null)
        if effect == "" and card_meta != null:
            if typeof(card_meta) == TYPE_DICTIONARY and card_meta.has("effect"):
                effect = str(card_meta.get("effect", ""))
            elif typeof(card_meta) == TYPE_OBJECT and card_meta is CustomCardData:
                match card_meta.effect_type:
                    CustomCardData.EffectType.Draw_Card:
                        effect = "Draw"
                    CustomCardData.EffectType.Swap_Card:
                        effect = "Swap"
                    CustomCardData.EffectType.Card_Back:
                        effect = "Card_Back"
                    _:
                        effect = ""
        if effect == "Draw":
            # discard the played card then request a deal into that slot
            if action.has("hand") and action.has("slot"):
                result.commands.append({"cmd": "discard", "hand": action.hand, "slot": int(action.slot)})
                result.commands.append({"cmd": "request_deal", "hand": action.hand, "slot": int(action.slot)})
                result.consumed_actions = 1
                emit_signal("action_resolved", player_id, action, result)
                return result
            else:
                result.error = "invalid_draw_play_args"
                return result
        elif effect == "Card_Back":
            # Card back: no game effect; do not consume action automatically
            result.commands.append({"cmd": "noop"})
            result.consumed_actions = 0
            emit_signal("action_resolved", player_id, action, result)
            return result
        elif effect == "Swap":
            # If opponent selection is present, perform swap; otherwise instruct caller to begin player-initiated swap
            if action.has("player_hand") and action.has("player_slot"):
                if action.has("opponent_hand") and action.has("opponent_slot"):
                    var swap_cmd = {"cmd": "swap", "player_hand": action.player_hand, "player_slot": int(action.player_slot), "opponent_hand": action.opponent_hand, "opponent_slot": int(action.opponent_slot)}
                    if action.has("initiator"):
                        swap_cmd.initiator = action.initiator
                    result.commands.append(swap_cmd)
                    result.consumed_actions = 1
                    emit_signal("action_resolved", player_id, action, result)
                    return result
                else:
                    result.commands.append({"cmd": "begin_swap", "player_hand": action.player_hand, "player_slot": int(action.player_slot)})
                    result.consumed_actions = 0
                    emit_signal("action_resolved", player_id, action, result)
                    return result
            else:
                result.error = "invalid_swap_args"
                return result

    # Fallback: no special effect
    result.commands.append({"cmd": "noop"})
    result.consumed_actions = 1
    emit_signal("action_resolved", player_id, action, result)
    return result
