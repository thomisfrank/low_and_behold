
# =====================================
# detail_box.gd
# Card detail box UI, description, and animation
# =====================================
extends Control

# Animation and box config
### Animation and box config
# jitter_duration: Duration of jitter animation for detail box
@export var jitter_duration: float = 0.3
# jitter_amount: Amount of jitter for detail box
@export var jitter_amount: float = 2.0
# box_size: Size of the detail box
@export var box_size: Vector2 = Vector2(220, 220)
# box_offset: Offset for detail box position
@export var box_offset: Vector2 = Vector2(68.0, 0)

# Internal state
var original_position: Vector2
var animation_tween: Tween

func _ready() -> void:
    # Hide box and store initial position
    hide()
    original_position = self.global_position

func show_with_card(card_data: CustomCardData, _card_node: Node) -> void:
    # Show card detail and play animation
    var desc_label = get_node_or_null("Box/CardDescription")
    if desc_label:
        desc_label.text = card_data.get_description()
    var viewport_height = get_viewport().size.y
    var y_center = viewport_height / 2.0 - box_size.y / 2.0
    var screen_position = Vector2(abs(box_offset.x), y_center)
    global_position = screen_position
    original_position = global_position
    print("Box global position:", global_position)
    show()
    _play_digitize_animation()

func hide_box():
    # Hide box and reset position
    hide()
    if animation_tween and animation_tween.is_valid():
        animation_tween.kill()
        global_position = original_position

func _play_digitize_animation():
    # Play jitter animation for box
    if animation_tween and animation_tween.is_valid():
        animation_tween.kill()
    animation_tween = create_tween()
    animation_tween.tween_method(_jitter_step, 0.0, 1.0, jitter_duration)
    animation_tween.chain().tween_callback(_reset_position)

func _jitter_step(_ignored_value: float):
    # Jitter box position for animation
    var offset = Vector2(randf_range(-jitter_amount, jitter_amount), randf_range(-jitter_amount, jitter_amount))
    global_position = original_position + offset
    print("Box global position (jitter):", global_position)

func _reset_position():
    # Reset box position after animation
    global_position = original_position
    print("Box global position (reset):", global_position)