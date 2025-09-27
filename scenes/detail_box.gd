extends Control

signal action_requested(card_data)

var _current_card_data = null

func show_detail(card, card_global_pos: Vector2) -> void:
    # Populate fields from the card data (prefer CustomCardData resource)
    var card_data = null
    if card == null:
        card_data = null
    elif card is CustomCardData:
        card_data = card
    elif typeof(card) == TYPE_DICTIONARY:
        card_data = card
    elif "card_data" in card:
        card_data = card.card_data
    elif card.has_method("get_card_data"):
        card_data = card.call("get_card_data")
    else:
        card_data = card

    # Safe node lookups
    var title_node = get_node_or_null("CardTitle")
    var desc_node = get_node_or_null("CardDescription")
    var action_btn = get_node_or_null("ActionButton")
    var icon_node = get_node_or_null("CardIcon")
    # If we have a CustomCardData resource, use its API
    # Remember current data for action handlers
    _current_card_data = card_data

    if card_data and card_data is CustomCardData:
        if title_node and title_node is Label:
            title_node.text = str(card_data.card_name)
        if desc_node and desc_node is Label:
            desc_node.text = str(card_data.get_description())
        if icon_node and icon_node is TextureRect and card_data.icon:
            icon_node.texture = card_data.icon
            if action_btn and action_btn is Button:
                if card_data and ("action_text" in card_data or card_data.has("action_text")):
                    action_btn.text = str(card_data.action_text)
                elif card_data and ("card_name" in card_data and "Swap" in str(card_data.card_name)):
                    action_btn.text = "Swap cards"
                else:
                    action_btn.text = "Use Card"

                # Ensure the button emits our signal when pressed (connect once)
                if not action_btn.is_connected("pressed", Callable(self, "_on_action_pressed")):
                    action_btn.connect("pressed", Callable(self, "_on_action_pressed"))
    else:
        # Fallbacks for dictionaries or plain objects
        if title_node and title_node is Label:
            if card_data and ("card_name" in card_data or (card_data is Object and card_data.has("card_name"))):
                title_node.text = str(card_data.card_name)
            elif card_data and ("name" in card_data):
                title_node.text = str(card_data.name)
            else:
                title_node.text = "Card"
        if desc_node and desc_node is Label:
            if card_data and ("card_description" in card_data):
                desc_node.text = str(card_data.card_description)
            elif card_data and ("description" in card_data):
                desc_node.text = str(card_data.description)
            else:
                desc_node.text = "No description available"
        if action_btn and action_btn is Button:
            if card_data and ("action_text" in card_data):
                action_btn.text = str(card_data.action_text)
            elif card_data and ("card_name" in card_data and "Swap" in str(card_data.card_name)):
                action_btn.text = "Swap cards"
            else:
                action_btn.text = "Use Card"

    # Offset the tooltip a bit so it doesn't overlap the card
    card_global_pos.x += 50
    card_global_pos.y -= 20

    # Clamp to viewport so the detail box stays on screen
    var screen_size = get_viewport().get_visible_rect().size
    # Use Control.size for the control's dimensions
    card_global_pos = card_global_pos.clamp(Vector2.ZERO, screen_size - size)
    global_position = card_global_pos
    show()

func _on_action_pressed() -> void:
    # Emit the current card data to listeners (e.g., PlayerHand)
    emit_signal("action_requested", _current_card_data)
    hide_detail()

func hide_detail() -> void:
    hide()

