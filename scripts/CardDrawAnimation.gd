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
@export var rotation_angle: float = 15.0  # Degrees to rotate during animation

# Card states
var animating_card: Control
var start_position: Vector2
var target_position: Vector2
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE

# Animation state
var current_frame: int = 0
var is_animating: bool = false
var flip_tween: Tween
var move_tween: Tween

func _ready():
	pass  # No setup needed

# Start the card draw animation
func animate_card_draw(card_data: CustomCardData, from_pos: Vector2, to_pos: Vector2, final_rotation: float = 0.0, final_scale: Vector2 = Vector2.ONE):
	if is_animating:
		print("[CardDrawAnimation] Already animating, ignoring request")
		return
	
	# Store animation parameters
	start_position = from_pos
	target_position = to_pos
	target_rotation = final_rotation
	target_scale = final_scale
	
	# Create the card instance
	animating_card = CardScene.instantiate()
	animating_card.set_script(CardScript)
	add_child(animating_card)
	
	# Position card at starting location
	animating_card.position = start_position
	animating_card.rotation_degrees = 0
	animating_card.scale = Vector2.ONE
	
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
	
	# Animate the flip effect using scale.x to simulate card flipping
	flip_tween.tween_method(_update_flip_frame, 0.0, 1.0, flip_duration)
	flip_tween.tween_callback(_on_flip_complete.bind(reveal_data)).set_delay(flip_duration)
	
	# Add slight rotation during flip for more dynamic feel
	flip_tween.tween_property(animating_card, "rotation_degrees", rotation_angle, flip_duration * 0.5)
	flip_tween.tween_property(animating_card, "rotation_degrees", 0, flip_duration * 0.5).set_delay(flip_duration * 0.5)

# Update the flip animation frame
func _update_flip_frame(progress: float):
	if not animating_card:
		return
	
	# Create flip effect by scaling x-axis (simulates card flipping)
	# Creates a "squash" effect - starts at 1, goes to 0, then back to 1
	var scale_factor: float
	if progress < 0.5:
		# First half: scale down from 1 to 0
		scale_factor = 1.0 - (progress * 2.0)
	else:
		# Second half: scale up from 0 to 1
		scale_factor = (progress - 0.5) * 2.0
		
	animating_card.scale.x = scale_factor
	
	# Halfway through the flip, switch to the revealed card
	if progress >= 0.5 and current_frame < 4:  # Use explicit number instead of division
		current_frame = 4

# Called when flip animation completes
func _on_flip_complete(reveal_data: CustomCardData):
	if animating_card:
		# Switch to the actual card data
		animating_card.call_deferred("display", reveal_data)
		# Start the movement animation
		_start_move_animation()

# Start the movement to hand slot animation
func _start_move_animation():
	move_tween = create_tween()
	move_tween.set_parallel(true)
	
	# Animate position
	move_tween.tween_property(animating_card, "position", target_position, move_duration)
	move_tween.tween_property(animating_card, "rotation_degrees", target_rotation, move_duration)
	move_tween.tween_property(animating_card, "scale", target_scale, move_duration)
	
	# Set easing for smooth motion
	move_tween.set_ease(Tween.EASE_OUT)
	move_tween.set_trans(Tween.TRANS_QUART)
	
	# Complete animation
	move_tween.tween_callback(_on_animation_complete).set_delay(move_duration)

# Called when entire animation sequence completes
func _on_animation_complete():
	is_animating = false
	emit_signal("animation_finished", animating_card)
	
	# Remove the card from this animator (it should be handled by the target now)
	if animating_card and animating_card.get_parent() == self:
		remove_child(animating_card)

# Clean up tweens
func _exit_tree():
	if flip_tween:
		flip_tween.kill()
	if move_tween:
		move_tween.kill()

# Utility function to create a card draw animation from deck to hand slot
static func create_draw_animation(parent: Node, deck_pos: Vector2, hand_pos: Vector2, card_data: CustomCardData, final_rotation: float = 0.0, final_scale: Vector2 = Vector2.ONE) -> CardDrawAnimation:
	var animator = CardDrawAnimation.new()
	parent.add_child(animator)
	animator.animate_card_draw(card_data, deck_pos, hand_pos, final_rotation, final_scale)
	return animator