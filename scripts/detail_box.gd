extends Control


# You can now control the animation from the Inspector
@export var jitter_duration: float = 0.3  # How long the effect lasts
@export var jitter_amount: float = 2.0    # How intense the shaking is
@export var box_size: Vector2 = Vector2(220, 220) # Set to your box's actual size
@export var box_offset: Vector2 = Vector2(-220, 0) # Offset from card position, editable in inspector

var original_position: Vector2
var animation_tween: Tween

func _ready() -> void:
	hide()
	# We store the box's starting position so we can return to it after the animation.
	original_position = self.position

func show_with_card(card_data: CustomCardData, card_node: Node) -> void:
	# Set the description label text
	var desc_label = get_node_or_null("Box/CardDescription")
	if desc_label:
		desc_label.text = card_data.get_description()

	# Align to the left of the card, flush with top
	var card_pos = card_node.get_global_position()
	original_position = card_pos + box_offset
	global_position = original_position

	show()
	_play_digitize_animation()

func hide_box():
	hide()
	# If we hide the box mid-animation, kill the tween to prevent issues.
	if animation_tween and animation_tween.is_valid():
		animation_tween.kill()
		position = original_position # Also reset its position

# This function sets up and runs the jitter animation.
func _play_digitize_animation():
	# Kill any old tween that might still be running.
	if animation_tween and animation_tween.is_valid():
		animation_tween.kill()

	animation_tween = create_tween()
	# For the duration of the effect, call the _jitter_step function on every frame.
	animation_tween.tween_method(_jitter_step, 0.0, 1.0, jitter_duration)
	# When the jittering is done, call the _reset_position function once.
	animation_tween.chain().tween_callback(_reset_position)

# This function is called every frame during the animation to move the box.
func _jitter_step(_ignored_value: float):
	var offset = Vector2(randf_range(-jitter_amount, jitter_amount), randf_range(-jitter_amount, jitter_amount))
	position = original_position + offset

# This function is called once at the end to snap the box back to its original spot.
func _reset_position():
	position = original_position
