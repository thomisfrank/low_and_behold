extends Node2D
class_name CardDrawAnimation

# Animation system for drawing cards with flip, rotation, and scaling
# Based on the flip_animation.tscn but using actual card instances

signal animation_finished(card: Control)

const CardScene = preload("res://scenes/cards.tscn")
const CardScript = preload("res://scripts/NewCard.gd")

# Animation parameters
@export var flip_duration: float = 0.8
@export var move_duration: float = 1.2
@export var total_frames: int = 8
@export var rotation_angle: float = 15.0  # Degrees to rotate during flip
@export var final_scale: Vector2 = Vector2(0.8, 0.8)  # Scale when animation completes
@export var max_rotation_during_move: float = 10.0  # Max rotation during move to hand

# Card states
var animating_card: Control
var start_position: Vector2
var target_position: Vector2
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE
var start_scale: Vector2 = Vector2.ONE  # Store the starting scale for flip animation

# Animation state
var current_frame: int = 0
var is_animating: bool = false
var flip_tween: Tween
var move_tween: Tween

func _ready():
	pass  # No setup needed

# Start the card draw animation
func animate_card_draw(card_data: CustomCardData, from_pos: Vector2, to_pos: Vector2, final_rotation: float = 0.0, end_scale: Vector2 = Vector2.ONE, from_scale: Vector2 = Vector2.ONE):
	if is_animating:
		print("[CardDrawAnimation] Already animating, ignoring request")
		return
	
	# Store animation parameters
	start_position = from_pos
	target_position = to_pos
	target_rotation = final_rotation
	target_scale = end_scale  # Use the parameter instead of default
	start_scale = from_scale  # Store starting scale for flip animation
	
	# Create the card instance
	animating_card = CardScene.instantiate()
	animating_card.set_script(CardScript)
	add_child(animating_card)
	
	# Position card at starting location
	animating_card.position = start_position
	animating_card.rotation_degrees = 0
	# Start with the starting scale, not the target scale
	animating_card.scale = start_scale
	# No z_index needed with CanvasLayer approach
	print("[CardDrawAnimation] Card starting at scale: ", start_scale, " will animate to: ", target_scale)
	
	# Initially show card back (will flip to reveal the actual card)
	var card_back_data = load("res://scripts/resources/CardBack.tres")
	animating_card.call_deferred("display", card_back_data)
	
	# Start the animation sequence
	is_animating = true
	current_frame = 0
	_start_flip_animation(card_data)

# Start the flip portion of the animation
func _start_flip_animation(reveal_data: CustomCardData):
	# Create flip tween
	flip_tween = create_tween()
	flip_tween.set_parallel(true)  # Allow multiple properties to animate
	
	# Animate the flip effect AND scaling together using the full animation duration
	var total_duration = flip_duration + move_duration
	flip_tween.tween_method(_update_flip_frame, 0.0, 1.0, total_duration)
	flip_tween.tween_callback(_on_flip_complete.bind(reveal_data)).set_delay(flip_duration * 0.5)  # Switch card data halfway through flip
	
	# Start moving to target position immediately (during flip)
	flip_tween.tween_property(animating_card, "position", target_position, total_duration)
	
	# Rotation happens in two phases: flip wobble, then final rotation
	flip_tween.tween_property(animating_card, "rotation_degrees", rotation_angle, flip_duration * 0.5)
	flip_tween.tween_property(animating_card, "rotation_degrees", target_rotation, flip_duration * 0.5 + move_duration).set_delay(flip_duration * 0.5)
	
	# Set easing for smooth motion - use EASE_IN_OUT for smoother arrival
	flip_tween.set_ease(Tween.EASE_IN_OUT)
	flip_tween.set_trans(Tween.TRANS_CUBIC)  # Smoother than TRANS_QUART
	
	# Complete animation
	flip_tween.tween_callback(_on_animation_complete).set_delay(total_duration)

# Update the flip animation frame
func _update_flip_frame(progress: float):
	if not animating_card:
		return
	
	# progress is now 0-1 for the entire animation duration
	# Calculate what portion of this should be the flip effect
	var total_duration = flip_duration + move_duration
	var flip_portion = flip_duration / total_duration  # e.g., 0.4 if flip is 0.8s and total is 2.0s
	
	# Interpolate the base scale from start to target throughout the entire animation
	var current_base_scale = start_scale.lerp(target_scale, progress)
	
	# Create flip effect only during the first portion of the animation
	var flip_scale_factor: float
	if progress < flip_portion:
		# We're in the flip phase - scale the flip progress to 0-1
		var flip_progress = progress / flip_portion
		if flip_progress < 0.5:
			# First half of flip: scale down from current base scale to 0
			flip_scale_factor = (1.0 - (flip_progress * 2.0)) * current_base_scale.x
		else:
			# Second half of flip: scale up from 0 to current base scale
			flip_scale_factor = ((flip_progress - 0.5) * 2.0) * current_base_scale.x
	else:
		# We're past the flip phase - use normal scaling
		flip_scale_factor = current_base_scale.x
		
	# Apply the scaling
	animating_card.scale.x = flip_scale_factor
	animating_card.scale.y = current_base_scale.y
	
	# Halfway through the FLIP portion (not total animation), switch to the revealed card
	var flip_halfway = flip_portion * 0.5
	if progress >= flip_halfway and current_frame < 4:
		current_frame = 4

# Called when flip animation completes (halfway through total animation)
func _on_flip_complete(reveal_data: CustomCardData):
	print("[CardDrawAnimation] Flip complete, switching to card data")
	if animating_card:
		# Switch to the actual card data
		animating_card.call_deferred("display", reveal_data)

# Called when entire animation sequence completes
func _on_animation_complete():
	is_animating = false
	emit_signal("animation_finished", animating_card)
	
	# Don't remove the card - let the GameManager handle it
	# The card should stay visible at its final position

# Clean up tweens
func _exit_tree():
	if flip_tween:
		flip_tween.kill()
	if move_tween:
		move_tween.kill()

# Utility function to create a card draw animation from deck to hand slot
static func create_draw_animation(parent: Node, deck_pos: Vector2, hand_pos: Vector2, card_data: CustomCardData, final_rotation: float = 0.0, end_scale: Vector2 = Vector2.ONE, from_scale: Vector2 = Vector2.ONE) -> CardDrawAnimation:
	var animator = CardDrawAnimation.new()
	parent.add_child(animator)
	animator.animate_card_draw(card_data, deck_pos, hand_pos, final_rotation, end_scale, from_scale)
	return animator