extends Control

const CardScene = preload("res://scenes/cards.tscn")
# Use a path instead of direct resource preload
const DEFAULT_CARD_BACK_PATH = "res://scripts/resources/CardBack.tres"

@onready var stack_layers: Control = $StackLayers
@onready var top_card: Node = $TopCard
@onready var count_label: Label = $CardCountLabel

@export var initial_count: int = 48
@export var stack_offset: int = 10  # Vertical offset between stacked cards
@export_enum("TwoSwap", "TwoDraw", "FourSwap", "FourDraw", "SixSwap", "SixDraw", "EightSwap", "EightDraw", "TenSwap", "TenDraw", "CardBack") var top_card_key: String = "CardBack"

var _count: int = 0

func _ready():
	# Set initial count and update display
	_count = initial_count
	_update_count_label()
	
	# Clean up any existing stack layers from the scene
	if stack_layers:
		for child in stack_layers.get_children():
			if child:
				child.queue_free()
	
	# Get the card back resource - always use CardBack for the stack
	var card_back_data = _load_card_resource("CardBack")
	
	# Create three stacked cards with 10px offset
	for i in range(3):
		var card = CardScene.instantiate()
		card.name = "StackLayer%d" % (i + 1)
		card.position = Vector2(0, i * stack_offset)  # Each card 10px below previous
		stack_layers.add_child(card)
		card.call_deferred("display", card_back_data)
	
	# Set up the top card (draw card)
	if top_card:
		top_card.queue_free()
	var top = CardScene.instantiate()
	top.name = "TopCard"
	add_child(top)
	top.position = Vector2.ZERO  # Centered
	
	# Use the selected top card from the dropdown
	var top_card_data = _load_card_resource(top_card_key)
	top.call_deferred("display", top_card_data)
	top_card = top

signal request_draw

# Handle clicking on the top card
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if top_card and top_card is Control:
			var rect = (top_card as Control).get_global_rect()
			if rect.has_point(get_global_mouse_position()):
				print("[Deck] TopCard clicked, emitting request_draw")
				emit_signal("request_draw")

# Update the count label with current count
func _update_count_label():
	if count_label:
		count_label.text = str(_count)

# Set deck count (for GameManager to call)
func set_count(n: int) -> void:
	_count = n
	_update_count_label()
	# Toggle visibility of stack layers based on count
	if stack_layers:
		var stack1 = stack_layers.get_node_or_null("StackLayer1")
		var stack2 = stack_layers.get_node_or_null("StackLayer2")
		var stack3 = stack_layers.get_node_or_null("StackLayer3")
		if stack1: stack1.visible = _count >= 1
		if stack2: stack2.visible = _count >= 2
		if stack3: stack3.visible = _count >= 3

# Get current deck count
func get_count() -> int:
	return _count
	
# Load a card resource by key name
func _load_card_resource(key: String) -> CustomCardData:
	var resource_path = "res://scripts/resources/%s.tres" % key
	var resource = load(resource_path)
	if resource and resource is CustomCardData:
		return resource
	else:
		push_error("Failed to load card resource: %s" % resource_path)
		# Fall back to default card back
		return load(DEFAULT_CARD_BACK_PATH)

# Change the top card to display a different card resource
func set_top_card(card_data: CustomCardData) -> void:
	if top_card:
		top_card.call_deferred("display", card_data)
		
# Change the top card by key name (e.g., "TwoSwap", "FourDraw")
func set_top_card_by_key(key: String) -> void:
	var resource = _load_card_resource(key)
	top_card_key = key
	set_top_card(resource)
