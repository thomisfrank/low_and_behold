extends Control

# Get node references
@onready var top_value_label: Label = $"Values/TopValue"
@onready var bottom_value_label: Label = $"Values/BottomValue"
@onready var values_container: Control = $"Values"
@onready var icon_node: TextureRect = $"Icon/Icon"
@onready var moving_gradient: ColorRect = $"CardBackground/Padding/MovingGradient"
@onready var front_frame: TextureRect = $"CardBackground/Padding/FrontFrame"
@onready var back_frame: TextureRect = $"CardBackground/Padding/BackFrame"
@onready var background_container: AspectRatioContainer = $"CardBackground"

# Z-index constants for proper layering (bottom to top)
const BACKGROUND_Z = 0
const FRAME_Z = 1      # Frame at the bottom
const GRADIENT_Z = 2   # Gradient in the middle
const VALUES_Z = 3     # Values on top
const ICON_Z = 4       # Icon on top

# Debug toggle
@export var debug_logging: bool = false

# Card appearance state
var _material_instanced: bool = false

func _ready():
	if debug_logging:
		print("[Card] _ready: Card node initialized")
	
	# Ensure proper z-indexing of all elements
	_setup_z_indices()
	
	# Force gradient shader to render below other elements
	if moving_gradient and moving_gradient.material:
		moving_gradient.material.render_priority = -10

# Main function to display a card based on its data resource
func display(data: CustomCardData):
	if debug_logging:
		print("[Card] Displaying card: ", data.card_name, " (", data.effect_type, ")")
	
	# Step 1: Set up the background colors
	_setup_background_colors(data)
	
	# Step 2: Handle frame display based on card type
	_setup_frame(data)
	
	# Step 3: Set the icon
	if icon_node and data.icon:
		icon_node.texture = data.icon
	
	# Step 4: Set up text values based on card type
	_setup_text_values(data)

# Set up proper z-indices for all card elements
func _setup_z_indices():
	# Set z-indices to ensure proper stacking within each card
	if background_container:
		background_container.z_index = BACKGROUND_Z
	if moving_gradient:
		moving_gradient.z_index = GRADIENT_Z
	if front_frame:
		front_frame.z_index = FRAME_Z
	if back_frame:
		back_frame.z_index = FRAME_Z
	if icon_node:
		icon_node.z_index = ICON_Z
	if values_container:
		values_container.z_index = VALUES_Z

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
