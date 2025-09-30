
# =====================================
# NewCard.gd
# Card node: handles display, lock state, and UI references
# =====================================
extends Control

# Debug logging toggle
### Debug logging toggle
# debug_logging: Toggle for debug print statements
@export var debug_logging: bool = false

# UI node references
@onready var top_value_label: Label = $"CardsViewport/CardsLabel/Values/TopValue"
@onready var bottom_value_label: Label = $"CardsViewport/CardsLabel/Values/BottomValue"
@onready var values_container: Control = $"CardsViewport/CardsLabel/Values"
@onready var icon_node: TextureRect = $"CardsViewport/CardsLabel/Icon/Icon"
@onready var moving_gradient: ColorRect = $"CardsViewport/CardsLabel/CardBackground/Padding/MovingGradient"
@onready var front_frame: TextureRect = $"CardsViewport/CardsLabel/CardBackground/Padding/FrontFrame"
@onready var back_frame: TextureRect = $"CardsViewport/CardsLabel/CardBackground/Padding/BackFrame"
@onready var background_container: AspectRatioContainer = $"CardsViewport/CardsLabel/CardBackground"

# Internal state
var _card_data: CustomCardData = null
var _material_instanced: bool = false

# Locked state and overlay
var locked: bool = false
var lock_overlay: ColorRect = null

func _ready():
	# Called when node enters scene tree
	if debug_logging:
		print("[Card] _ready: Card node initialized")
	# Force gradient shader to render below other UI elements
	if moving_gradient and moving_gradient.material:
		moving_gradient.material.render_priority = -10
	# Create lock overlay (white, semi-transparent)
	lock_overlay = ColorRect.new()
	lock_overlay.color = Color(1,1,1,0.6)
	lock_overlay.visible = false
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(lock_overlay)
	lock_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lock_overlay.anchor_left = 0
	lock_overlay.anchor_top = 0
	lock_overlay.anchor_right = 1
	lock_overlay.anchor_bottom = 1
	lock_overlay.z_index = 999
	mouse_filter = Control.MOUSE_FILTER_STOP

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------

# Configures and displays the card based on the provided card data resource.
func display(data: CustomCardData):
	if not data:
		push_warning("[Card] Display function called with null data.")
		return

	if debug_logging:
		print("[Card] Displaying card: ", data.card_name, " (", data.effect_type, ")")

	_card_data = data
	# no system tooltip: card name is shown via UI tooltips managed by PlayerHand

	# Configure the card's visual appearance.
	_setup_background_colors(data)
	_setup_frame(data)
	_setup_text_values(data)
	_setup_icon(data)

	# Ensure the control's interactive area matches the visible card background.
	if background_container:
		var pad = Vector2(6, 6)
		custom_minimum_size = background_container.size + pad

	# Store original visual state (kept for callers that may want to use it);
	# other scripts (deck/hand) should manage hover/interactions.
	# Note: we intentionally do not modify scale/z_index here.

	# Reset lock overlay on display
	unlock_card()

# Locks the card, making it non-interactive and showing an overlay.
func lock_card():
	locked = true
	if lock_overlay:
		lock_overlay.visible = true
		# Apply glitch shader to overlay
		var shader = load("res://scripts/shaders/PixelPlayArea.gdshader")
		var mat = ShaderMaterial.new()
		mat.shader = shader
		lock_overlay.material = mat

# Unlocks the card, restoring interactivity.
func unlock_card():
	locked = false
	if lock_overlay:
		lock_overlay.visible = false
		lock_overlay.material = null

#-----------------------------------------------------------------------------
# Signal handling removed
#----------------------------------------------------------------------------- 

# Interaction like hover/drag should be managed by parent controllers (deck,
# player hand). This script provides only the visual/data representation of a
# card. Keep mouse_filter set so parents can receive input from this control if
# they choose to connect signals.

#-----------------------------------------------------------------------------
# UI Update Logic
#-----------------------------------------------------------------------------

# Sets up the background shader colors and properties.
func _setup_background_colors(data: CustomCardData):
	if not (moving_gradient and moving_gradient.material is ShaderMaterial):
		if debug_logging:
			print("[Card] Warning: Missing gradient material.")
		return

	# Ensure each card has its own material instance to prevent shared state.
	if not _material_instanced:
		moving_gradient.material = moving_gradient.material.duplicate()
		_material_instanced = true

	var shader_mat = moving_gradient.material as ShaderMaterial
	var varied_speed = _calculate_varied_speed(data)

	# Apply parameters from the card data resource.
	shader_mat.set_shader_parameter("color_a", data.color_a)
	shader_mat.set_shader_parameter("color_b", data.color_b)
	shader_mat.set_shader_parameter("speed", varied_speed)
	shader_mat.set_shader_parameter("intensity", data.shader_intensity)
	shader_mat.set_shader_parameter("sharpness", data.shader_sharpness)

# Sets the visibility of the front and back frames of the card.
func _setup_frame(data: CustomCardData):
	var is_back = (data.effect_type == CustomCardData.EffectType.Card_Back)

	if front_frame:
		front_frame.visible = not is_back
		if not is_back and data.card_frame:
			front_frame.texture = data.card_frame
	if back_frame:
		back_frame.visible = is_back
		if is_back and data.card_frame:
			back_frame.texture = data.card_frame

# Sets the text for the value labels.
func _setup_text_values(data: CustomCardData):
	var is_back = (data.effect_type == CustomCardData.EffectType.Card_Back)

	if values_container:
		values_container.visible = not is_back

	if not is_back:
		var value_text = data.get_effect_value()
		if top_value_label:
			top_value_label.text = value_text
		if bottom_value_label:
			bottom_value_label.text = value_text

# Sets the icon texture.
func _setup_icon(data: CustomCardData):
	if icon_node and data.icon:
		icon_node.texture = data.icon

#-----------------------------------------------------------------------------
# Utility Functions
#-----------------------------------------------------------------------------

# Calculates a varied speed for the background shader to make each card feel unique.
func _calculate_varied_speed(data: CustomCardData) -> float:
	var base_speed = data.shader_speed
	
	# 1. Consistent variation based on card name hash.
	var card_hash = hash(data.card_name)
	var variation_factor = 1.0 + (float(card_hash % 200) / 1000.0 - 0.1) # ±10%

	# 2. Systematic variation based on card value.
	var value_variation = 1.0
	if data.effect_type != CustomCardData.EffectType.Card_Back:
		match data.effect_value:
			2: value_variation = 0.8
			4: value_variation = 0.9
			6: value_variation = 1.1
			8: value_variation = 1.2
			10: value_variation = 1.3

	# 3. Systematic variation based on effect type.
	var type_variation = 1.0
	match data.effect_type:
		CustomCardData.EffectType.Draw_Card: type_variation = 1.1
		CustomCardData.EffectType.Swap_Card: type_variation = 0.9
		CustomCardData.EffectType.Card_Back: type_variation = 0.7

	# Combine variations and clamp to a reasonable range.
	var final_speed = base_speed * variation_factor * value_variation * type_variation
	return clamp(final_speed, 0.3, 2.0)


# Finds the topmost card under the global mouse position.
func _get_topmost_hovered_card() -> Control:
	var global_mouse_pos = get_global_mouse_position()
	var top_candidate: Control = null
	var top_z: int = -2147483648 # Smallest possible integer

	for node in get_tree().get_nodes_in_group("hoverable_cards"):
		if node is Control and node.visible:
			var card_control: Control = node
			# Check if the mouse is within the card's global rectangle.
			if card_control.get_global_rect().has_point(global_mouse_pos):
				# If this card is on top of the previous candidate, it becomes the new candidate.
				if card_control.z_index > top_z:
					top_z = card_control.z_index
					top_candidate = card_control
	
	return top_candidate
