# UIManager.gd (Final Corrected Script)

extends Node
# Singleton for managing UI overlays and popups
var detail_box: Control = null

func _ready():
	pass

func _find_detail_box_if_needed() -> void:
	if not is_instance_valid(detail_box):
		var path = "main/UILayer/detail_box"
		var root = get_tree().get_root()
		detail_box = root.get_node(path)
		if detail_box == null or not is_instance_valid(detail_box):
			print("[UIManager] detail_box not found at path: %s" % path)

func show_card_detail(card_data: CustomCardData, card_node: Node) -> void:
	_find_detail_box_if_needed()

	if is_instance_valid(detail_box):
		detail_box.show_with_card(card_data, card_node)
	else:
		print("[UIManager] Cannot show detail box: not found.")

func hide_card_detail() -> void:
	_find_detail_box_if_needed()

	if is_instance_valid(detail_box):
		detail_box.hide_box()
	else:
		print("[UIManager] Cannot hide detail box: not found.")
