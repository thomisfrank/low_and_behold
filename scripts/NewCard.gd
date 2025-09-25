extends Control

# Get node references
@onready var top_value_label: Label = $"CardsViewport/CardsLabel/Values/TopValue"
@onready var bottom_value_label: Label = $"CardsViewport/CardsLabel/Values/BottomValue"
@onready var values_container: Control = $"CardsViewport/CardsLabel/Values"
@onready var icon_node: TextureRect = $"CardsViewport/CardsLabel/Icon/Icon"
@onready var moving_gradient: ColorRect = $"CardsViewport/CardsLabel/CardBackground/Padding/MovingGradient"
@onready var front_frame: TextureRect = $"CardsViewport/CardsLabel/CardBackground/Padding/FrontFrame"
@onready var back_frame: TextureRect = $"CardsViewport/CardsLabel/CardBackground/Padding/BackFrame"
@onready var background_container: AspectRatioContainer = $"CardsViewport/CardsLabel/CardBackground"

# Debug toggle
@export var debug_logging: bool = false

# Card appearance state
var _material_instanced: bool = false
var _card_data: CustomCardData = null
var _orig_z_index: int = 0
var _orig_scale: Vector2 = Vector2.ONE
@export var hover_scale: float = 1.07
@export var hover_z_offset: int = 200

var _hover_active: bool = false

func _ready():
	if debug_logging:
		print("[Card] _ready: Card node initialized")
	
	# Scene tree order handles layering naturally - no z_index needed
	
	# Force gradient shader to render below other elements
	if moving_gradient and moving_gradient.material:
		moving_gradient.material.render_priority = -10

	# Ensure this control receives mouse enter/exit events and prints on hover.
	# Keep behavior simple: always connect and only print in handlers.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Register this card so we can resolve which card is visually on top
	# when multiple cards overlap. We only want the topmost card to print hover.
	add_to_group("hoverable_cards")

	if not is_connected("mouse_entered", Callable(self, "_on_mouse_entered")):
		connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	if not is_connected("mouse_exited", Callable(self, "_on_mouse_exited")):
		connect("mouse_exited", Callable(self, "_on_mouse_exited"))

# Main function to display a card based on its data resource
func display(data: CustomCardData):
	if debug_logging:
		print("[Card] Displaying card: ", data.card_name, " (", data.effect_type, ")")
	# Store the data so hover handlers can print useful info
	_card_data = data
	# Provide a simple tooltip as well (Godot 4 uses tooltip_text)
	tooltip_text = data.card_name

	# Step 1: Set up the background colors
	_setup_background_colors(data)

	# Ensure the control's interactive rect matches the visible background
	if background_container:
		# Use the background container's size (plus a small padding) so mouse_enter/exit
		# target the visible card area even when children are arranged by containers.
		var pad = Vector2(6, 6)
		custom_minimum_size = background_container.size + pad

	# store original visual state for hover restore
	_orig_scale = self.scale
	_orig_z_index = self.z_index

	# Step 2: Handle frame display based on card type
	_setup_frame(data)

	# Step 3: Set the icon
	if icon_node and data.icon:
		icon_node.texture = data.icon

	# Step 4: Set up text values based on card type
	_setup_text_values(data)

func _on_mouse_entered():
	if _hover_active:
		return

	var global_mouse_pos = get_global_mouse_position()
	var top_candidate: Control = null
	var top_z: int = -2147483648
	for node in get_tree().get_nodes_in_group("hoverable_cards"):
		if node is Control and node.visible:
			var c: Control = node
			if not c.get_global_rect().has_point(global_mouse_pos):
				continue
			if c.z_index > top_z:
				top_z = c.z_index
				top_candidate = c

	if top_candidate != self:
		return

	_hover_active = true
	if _card_data:
		print("[Card][hover] Enter: ", _card_data.card_name, " value=", _card_data.get_effect_value(), " effect=", _card_data.effect_type)
	else:
		print("[Card][hover] Enter: unknown card")
	# No visual changes here; printing only.

func _on_mouse_exited():
	if not _hover_active:
		return

	_hover_active = false
	if _card_data:
		print("[Card][hover] Exit: ", _card_data.card_name)
	else:
		print("[Card][hover] Exit: unknown card")
	# No visual changes; printing only.

# Set up the background colors and shader
func _setup_background_colors(data: CustomCardData):
	# Ensure the material is properly set up
	if moving_gradient and moving_gradient.material and moving_gradient.material is ShaderMaterial:
		# Make sure each card has its own material instance
		if not _material_instanced:
			moving_gradient.material = moving_gradient.material.duplicate()
			_material_instanced = true
		
		# Calculate varied speed based on card properties for natural movement
		var varied_speed = _calculate_varied_speed(data)
		
		# Set the shader parameters from data
		var shader_mat = moving_gradient.material as ShaderMaterial
		shader_mat.set_shader_parameter("color_a", data.color_a)
		shader_mat.set_shader_parameter("color_b", data.color_b)
		shader_mat.set_shader_parameter("speed", varied_speed)
		shader_mat.set_shader_parameter("intensity", data.shader_intensity)
		shader_mat.set_shader_parameter("sharpness", data.shader_sharpness)
	elif debug_logging:
		print("[Card] Warning: Missing gradient material")

# Calculate varied speed for gradient animation to make each card unique
func _calculate_varied_speed(data: CustomCardData) -> float:
	# Base speed from the card data
	var base_speed = data.shader_speed
	
	# Create variation based on card properties
	# Use card name hash for consistent but varied results
	var card_hash = hash(data.card_name)
	var variation_factor = 1.0 + (float(card_hash % 200) / 1000.0 - 0.1)  # ±10% variation
	
	# Additional variation based on card value for systematic differences
	var value_variation = 1.0
	if data.effect_type != CustomCardData.EffectType.Card_Back:
		# Different speed multipliers for different card values
		match data.effect_value:
			2: value_variation = 0.8   # Slower for low values
			4: value_variation = 0.9
			6: value_variation = 1.1   # Faster for higher values
			8: value_variation = 1.2
			10: value_variation = 1.3  # Fastest for highest values
	
	# Different speed for different effect types
	var type_variation = 1.0
	match data.effect_type:
		CustomCardData.EffectType.Draw_Card: type_variation = 1.1  # Draw cards slightly faster
		CustomCardData.EffectType.Swap_Card: type_variation = 0.9  # Swap cards slightly slower
		CustomCardData.EffectType.Card_Back: type_variation = 0.7  # Card backs slowest
	
	# Combine all variations
	var final_speed = base_speed * variation_factor * value_variation * type_variation
	
	# Clamp to reasonable bounds (0.3 to 2.0)
	return clamp(final_speed, 0.3, 2.0)

# Set up which frame to show based on card type
func _setup_frame(data: CustomCardData):
	# Show the correct frame based on card type
	if data.effect_type == CustomCardData.EffectType.Card_Back:
		# Card Back shows the back frame
		if front_frame: front_frame.visible = false
		if back_frame: 
			back_frame.visible = true
			if data.card_frame:
				back_frame.texture = data.card_frame
	else:
		# Regular cards show the front frame
		if back_frame: back_frame.visible = false
		if front_frame: 
			front_frame.visible = true
			if data.card_frame:
				front_frame.texture = data.card_frame

# Set up text values based on card type
func _setup_text_values(data: CustomCardData):
	var value_text = data.get_effect_value()
	
	# Handle values visibility based on card type
	if data.effect_type == CustomCardData.EffectType.Card_Back:
		# Card backs don't show values
		if values_container: values_container.visible = false
	else:
		# Regular cards show values
		if values_container: values_container.visible = true
		if top_value_label: top_value_label.text = value_text
		if bottom_value_label: bottom_value_label.text = value_text
