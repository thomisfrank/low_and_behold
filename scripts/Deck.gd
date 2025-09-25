extends SubViewportContainer

const CardScene = preload("res://scenes/cards.tscn")
# Use a path instead of direct resource preload
const DEFAULT_CARD_BACK_PATH = "res://scripts/resources/CardBack.tres"

@onready var stack_layers: Control = $DeckViewport/DeckControl/StackLayers
@onready var top_card: Node = $DeckViewport/DeckControl/TopCard
@onready var count_label: Label = $DeckViewport/DeckControl/CardCount/AspectRatioContainer/CardCountLabel

@export var initial_count: int = 48
@export var stack_offset: int = 60  # Vertical offset between stacked cards
@export var stack_x_offset: int = 8  # Small horizontal offset for realistic stacking
@export_enum("TwoSwap", "TwoDraw", "FourSwap", "FourDraw", "SixSwap", "SixDraw", "EightSwap", "EightDraw", "TenSwap", "TenDraw", "CardBack") var top_card_key: String = "CardBack"

var _count: int = 0

func _ready():
	print("[Deck] _ready() called - script attached to: ", get_path())
	
	# Configure SubViewportContainer for proper input handling
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch = true  # Make sure container stretches to handle full area
	
	# Configure SubViewport for input forwarding
	var subviewport = $DeckViewport
	if subviewport:
		subviewport.handle_input_locally = false
		subviewport.gui_disable_input = false  # Allow input processing
		print("[Deck] SubViewport configured for input forwarding")
	
	print("[Deck] SubViewportContainer input setup complete")
	
	# Set initial count and update display
	_count = initial_count
	_update_count_label()
	
	# Clean up any existing stack layers from the scene
	if stack_layers:
		stack_layers.z_index = -50  # Ensure stack is behind everything
		stack_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse input
		for child in stack_layers.get_children():
			if child:
				child.queue_free()
	
	# Get the card back resource - always use CardBack for the stack
	var card_back_data = _load_card_resource("CardBack")
	
	# Create three stacked cards with proper z-indexing and offset
	for i in range(3):
		var card = CardScene.instantiate()
		var layer_name = "StackLayer%d" % (i + 1)
		card.name = layer_name
		# Use both horizontal and vertical offset for realistic stacking (like your Figma mock)
		var offset_pos = Vector2(i * stack_x_offset, i * stack_offset)
		
		# Set position directly (scene file now uses position-based layout)
		card.position = offset_pos
		
		# Force position after everything is set up
		call_deferred("_force_card_position", card, offset_pos)
		
		# Set z-index so bottom cards render behind top cards
		card.z_index = -(i + 1) * 10  # Bottom card has lowest z-index
		
		print("[Deck] Creating ", layer_name, " at position: ", offset_pos, " with z_index: ", card.z_index)
		
		# Ensure stack cards don't block mouse input (SubViewportContainer structure)
		if card is Control:
			(card as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Also disable input on the SubViewport inside
			var card_subviewport = card.get_node_or_null("CardsViewport")
			if card_subviewport and card_subviewport is SubViewport:
				card_subviewport.gui_disable_input = true
		stack_layers.add_child(card)
		card.call_deferred("display", card_back_data)
		
		# Debug: Check actual position and size after adding to scene
		call_deferred("_debug_card_info", card, layer_name)
	
	# Set up the top card (draw card)
	if top_card:
		top_card.queue_free()
	var top = CardScene.instantiate()
	top.name = "TopCard"
	top.z_index = 10  # Highest z-index to appear above stack
	
	# Set position for top card (scene file now uses position-based layout)
	top.position = Vector2.ZERO  # Centered
	
	# Configure input handling
	if top is Control:
		(top as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Also disable input on the SubViewport inside
		var top_subviewport = top.get_node_or_null("CardsViewport")
		if top_subviewport and top_subviewport is SubViewport:
			top_subviewport.gui_disable_input = true
	add_child(top)
	
	# Use the selected top card from the dropdown
	var top_card_data = _load_card_resource(top_card_key)
	top.call_deferred("display", top_card_data)
	top_card = top
	
	print("[Deck] Setup complete, top_card_key=", top_card_key)
	
	# Debug: Show actual scale information
	var deck_scale = get_global_transform().get_scale()
	print("[Deck] Deck global scale: ", deck_scale)
	print("[Deck] Stack offset (", stack_x_offset, ", ", stack_offset, ") will appear as ~(", stack_x_offset * deck_scale.x, ", ", stack_offset * deck_scale.y, ") pixels on screen")
	
	# Connect mouse signals for debugging
	if not is_connected("mouse_entered", Callable(self, "_on_mouse_entered")):
		connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	if not is_connected("mouse_exited", Callable(self, "_on_mouse_exited")):
		connect("mouse_exited", Callable(self, "_on_mouse_exited"))

signal request_draw

# Handle input events (SubViewportContainer input forwarding)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Check if the mouse event is within our bounds
		var mouse_pos = event.position
		var rect = get_global_rect()
		if rect.has_point(mouse_pos):
			print("[Deck] _input received mouse event within bounds: ", event)
			_handle_mouse_input(event)
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	print("[Deck] _gui_input called with event: ", event)
	_handle_mouse_input(event)

# Centralized mouse input handling
func _handle_mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("[Deck] Mouse button event - button:", event.button_index, " pressed:", event.pressed)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("[Deck] Left click detected, emitting request_draw")
			request_draw.emit()

# Add mouse enter/exit for debugging
func _on_mouse_entered():
	print("[Deck] Mouse entered deck area")

func _on_mouse_exited():
	print("[Deck] Mouse exited deck area")

# Update the count label with current count
func _update_count_label():
	if count_label and is_instance_valid(count_label):
		# Trim any extra whitespace in the scene label and set count
		count_label.text = str(_count)
	else:
		# Defensive: don't error if the label path is wrong
		print("[Deck] Warning: count_label not found; cannot update display")

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

# Debug helper to check card positions after they're in the scene tree
func _debug_card_info(card: Node, expected_name: String) -> void:
	if card and is_instance_valid(card):
		var size_info = ""
		var bounds_info = ""
		if card is Control:
			var control = card as Control
			size_info = " size: " + str(control.size)
			bounds_info = " bounds: " + str(control.get_rect())
		print("[Deck] ", expected_name, " actual name: '", card.name, "' position: ", card.position, " global_position: ", card.global_position, size_info, bounds_info)

# Force card position after scene setup
func _force_card_position(card: Node, target_position: Vector2) -> void:
	if card and is_instance_valid(card):
		if card is Control:
			var control = card as Control
			# Clear any layout constraints
			control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			control.position = target_position
			print("[Deck] Forced ", card.name, " to position: ", target_position, " actual: ", control.position)
		
# Change the top card by key name (e.g., "TwoSwap", "FourDraw")
func set_top_card_by_key(key: String) -> void:
	var resource = _load_card_resource(key)
	top_card_key = key
	set_top_card(resource)
