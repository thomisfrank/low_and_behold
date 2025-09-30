extends Node

# CardAnimator: central service to run card draw animations.
# It wraps CardDrawAnimation and exposes an animate_draw helper that
# accepts an optional finished Callable to run when the animation completes.

signal animation_finished(animated_card: Control, card_data: CustomCardData, target_slot: Node, slot_index: int, extra: Dictionary)

const CardDrawAnimationScript = preload("res://scripts/CardDrawAnimation.gd")

var _layer: CanvasLayer = null
@export var flip_duration: float = 0.8
@export var move_duration: float = 1.2
@export var tween_ease: int = Tween.EASE_IN_OUT
@export var tween_trans: int = Tween.TRANS_CUBIC
@export var rotation_angle: float = 15.0
@export var final_scale: Vector2 = Vector2(0.8, 0.8)

func _ready() -> void:
	# Create a single CanvasLayer for animations so they render above UI
	_layer = CanvasLayer.new()
	_layer.name = "CardAnimatorLayer"
	add_child(_layer)

# finished_cb should be a Callable or null. If provided, it will be connected
# directly to CardDrawAnimation.animation_finished; otherwise CardAnimator will
# emit its own `animation_finished` signal.
func animate_draw(card_data: CustomCardData, start_pos: Vector2, target_pos: Vector2, final_rotation: float = 0.0, end_scale: Vector2 = Vector2.ONE, start_scale: Vector2 = Vector2.ONE, _suppress_reveal: bool = false, finished_cb = null, flip_dur: float = -1.0, move_dur: float = -1.0, tween_ease_override: int = -1, tween_trans_override: int = -1, rot_angle_override: float = NAN) -> CardDrawAnimation:
	# Ensure the animation layer exists (safe when used as autoload before _ready())
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.name = "CardAnimatorLayer"
		add_child(_layer)

	var parent: Node = _layer
	# Use provided overrides or fall back to CardAnimator defaults
	var use_flip = flip_dur if flip_dur > 0 else flip_duration
	var use_move = move_dur if move_dur > 0 else move_duration
	var use_ease = tween_ease_override if tween_ease_override >= 0 else tween_ease
	var use_trans = tween_trans_override if tween_trans_override >= 0 else tween_trans
	var use_rot = rot_angle_override if rot_angle_override == rot_angle_override else rotation_angle
	var use_final_scale = end_scale if end_scale != Vector2.ONE else final_scale
	var animator: CardDrawAnimation = CardDrawAnimationScript.create_draw_animation(parent, start_pos, target_pos, card_data, final_rotation, use_final_scale, start_scale, use_flip, use_move, use_ease, use_trans, use_rot)
	if animator:
		if finished_cb != null:
			animator.connect("animation_finished", finished_cb)
		else:
			animator.connect("animation_finished", Callable(self, "_on_anim_finished").bind(card_data))
	return animator

func _on_anim_finished(animated_card: Control, card_data: CustomCardData) -> void:
	emit_signal("animation_finished", animated_card, card_data, null, -1, {})
