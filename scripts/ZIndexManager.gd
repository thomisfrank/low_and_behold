extends Node

# Simple z-index manager for cards.
# Provides a stable base z-index per card so internal relative z stays local.

class_name ZIndexManager

const BASE_CARD_Z := 100000
const STEP := 1000

static func base_z_for_index(index: int) -> int:
    # Higher returned value = rendered on top if using positive z
    return BASE_CARD_Z - (index * STEP)

static func assign_base_z(node: Node, index: int) -> void:
    # If node is CanvasItem (Control/Node2D), set its z_index
    if node is CanvasItem:
        node.z_index = base_z_for_index(index)
