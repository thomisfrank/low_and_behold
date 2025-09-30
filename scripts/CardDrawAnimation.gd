
# =====================================
# CardDrawAnimation.gd
# Handles card flip + move animation for card instances
# =====================================
extends Node2D
class_name CardDrawAnimation
### Debug logging toggle
@export var debug_logging: bool = false

# Emits when animation finishes
signal animation_finished(card: Control)

# Card scene and script references
const CardScene = preload("res://scenes/cards.tscn")
const CardScript = preload("res://scripts/NewCard.gd")

# Animation parameters
### Animation parameters
# flip_duration: Duration of card flip animation
@export var flip_duration: float = 0.8
# move_duration: Duration of card move animation
@export var move_duration: float = 1.2
# total_frames: Number of frames in animation
@export var total_frames: int = 8
# rotation_angle: Angle for card rotation during animation
@export var rotation_angle: float = 15.0
# final_scale: Final scale of card after animation
@export var final_scale: Vector2 = Vector2(0.8, 0.8)
# max_rotation_during_move: Maximum rotation during move
@export var max_rotation_during_move: float = 10.0

# Tween configuration
### Tween configuration
# tween_ease: Tween easing type
@export var tween_ease: int = Tween.EASE_IN_OUT
# tween_trans: Tween transition type
@export var tween_trans: int = Tween.TRANS_CUBIC

# Behavior toggles
### Behavior toggles
# auto_free: Free animator node after animation completes
@export var auto_free: bool = true
# use_canvas_layer: Render animation in a CanvasLayer above UI
@export var use_canvas_layer: bool = false

# Runtime state
var animating_card: Control
var start_position: Vector2
var target_position: Vector2
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE
var start_scale: Vector2 = Vector2.ONE
var suppress_reveal: bool = false

var current_frame: int = 0
var is_animating: bool = false
var flip_tween: Tween
var move_tween: Tween

func _ready() -> void:
	# No setup needed
	pass


func animate_card_draw(card_data: CustomCardData, from_pos: Vector2, to_pos: Vector2, final_rotation: float = 0.0, end_scale: Vector2 = Vector2.ONE, from_scale: Vector2 = Vector2.ONE, p_suppress_reveal: bool = false) -> void:
	# Animate card draw: flip + move
	if is_animating:
		return
	if debug_logging:
		print("[Anim] animate_card_draw START -> data:", card_data, " from:", from_pos, " to:", to_pos, " end_scale:", end_scale, " from_scale:", from_scale, " suppress_reveal:", p_suppress_reveal)
	start_position = from_pos
	target_position = to_pos
	target_rotation = final_rotation
	target_scale = end_scale
	start_scale = from_scale
	animating_card = CardScene.instantiate() as Control
	# Optionally parent under CanvasLayer for top rendering
	if use_canvas_layer and get_parent():
		var layer = CanvasLayer.new()
		layer.name = "CardDrawLayer"
		get_parent().add_child(layer)
		layer.add_child(animating_card)
	else:
		add_child(animating_card)
	animating_card.global_position = start_position
	animating_card.rotation_degrees = 0
	animating_card.scale = start_scale
	# Show card back, then flip to reveal
	var card_back_data = load("res://scripts/resources/CardBack.tres")
	animating_card.call_deferred("display", card_back_data)
	suppress_reveal = p_suppress_reveal
	is_animating = true
	current_frame = 0
	if debug_logging:
		print("[Anim] starting flip animation (flip_duration=", flip_duration, ", move_duration=", move_duration, ")")
	_start_flip_animation(card_data)


func _start_flip_animation(reveal_data: CustomCardData) -> void:
	flip_tween = create_tween()
	flip_tween.set_parallel(true)

	if debug_logging:
		print("[Anim] _start_flip_animation scheduled reveal_data:", reveal_data)

	var total_duration = flip_duration + move_duration
	flip_tween.tween_method(_update_flip_frame, 0.0, 1.0, total_duration)
	flip_tween.tween_callback(_on_flip_complete.bind(reveal_data)).set_delay(flip_duration * 0.5)

	# Animate global_position to avoid parent transform issues
	flip_tween.tween_property(animating_card, "global_position", target_position, total_duration)

	flip_tween.tween_property(animating_card, "rotation_degrees", rotation_angle, flip_duration * 0.5)
	flip_tween.tween_property(animating_card, "rotation_degrees", target_rotation, flip_duration * 0.5 + move_duration).set_delay(flip_duration * 0.5)

	flip_tween.set_ease(tween_ease)
	flip_tween.set_trans(tween_trans)

	flip_tween.tween_callback(_on_animation_complete).set_delay(total_duration)


func _update_flip_frame(progress: float) -> void:
	if not animating_card:
		return

	var total_duration = flip_duration + move_duration
	var flip_portion = flip_duration / total_duration

	var current_base_scale = start_scale.lerp(target_scale, progress)

	var flip_scale_factor: float
	if progress < flip_portion:
		var flip_progress = progress / flip_portion
		if flip_progress < 0.5:
			flip_scale_factor = (1.0 - (flip_progress * 2.0)) * current_base_scale.x
		else:
			flip_scale_factor = ((flip_progress - 0.5) * 2.0) * current_base_scale.x
	else:
		flip_scale_factor = current_base_scale.x

	animating_card.scale.x = flip_scale_factor
	animating_card.scale.y = current_base_scale.y

	var flip_halfway = flip_portion * 0.5
	if progress >= flip_halfway and current_frame < 4:
		current_frame = 4


func _on_flip_complete(reveal_data: CustomCardData) -> void:
	if animating_card:
		if debug_logging:
			print("[Anim] _on_flip_complete called; suppress_reveal=", suppress_reveal, " reveal_data=", reveal_data)
		# Only reveal the face if we weren't asked to suppress it.
		if not suppress_reveal:
			if debug_logging:
				print("[Anim] Revealing face via display()")
			animating_card.call_deferred("display", reveal_data)
		else:
			if debug_logging:
				print("[Anim] Suppressed reveal; keeping back visible")


func _on_animation_complete() -> void:
	is_animating = false

	# Reparent the card to the animator's parent so it survives animator deletion.
	var card_ref = animating_card
	var parent_node = get_parent()
	if card_ref and parent_node and card_ref.get_parent() != parent_node:
		var gp = card_ref.global_position
		card_ref.get_parent().remove_child(card_ref)
		parent_node.add_child(card_ref)
		card_ref.global_position = gp

	emit_signal("animation_finished", card_ref)
	if debug_logging:
		print("[Anim] _on_animation_complete emitted animation_finished for", card_ref)

	if auto_free:
		call_deferred("queue_free")


func _exit_tree() -> void:
	if flip_tween:
		flip_tween.kill()
	if move_tween:
		move_tween.kill()


static func create_draw_animation(parent: Node, deck_pos: Vector2, hand_pos: Vector2, card_data: CustomCardData, final_rotation: float = 0.0, end_scale: Vector2 = Vector2.ONE, from_scale: Vector2 = Vector2.ONE, flip_dur: float = -1.0, move_dur: float = -1.0, ease_override: int = -1, trans_override: int = -1, rot_angle_override: float = NAN) -> CardDrawAnimation:
	var animator = CardDrawAnimation.new()
	parent.add_child(animator)
	# Apply overrides if provided
	if flip_dur > 0:
		animator.flip_duration = flip_dur
	if move_dur > 0:
		animator.move_duration = move_dur
	if ease_override >= 0:
		animator.tween_ease = ease_override
	if trans_override >= 0:
		animator.tween_trans = trans_override
	if rot_angle_override == rot_angle_override:
		animator.rotation_angle = rot_angle_override
	animator.animate_card_draw(card_data, deck_pos, hand_pos, final_rotation, end_scale, from_scale)
	return animator