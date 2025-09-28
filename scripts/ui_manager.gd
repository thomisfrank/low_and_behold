
# =====================================
# UIManager.gd
# Manages UI overlays, popups, and detail box
# =====================================
extends Node

# Reference to the card detail box UI
var detail_box: Control = null


func _ready():

	# Setup main UI buttons and panels
	var options_btn = get_node_or_null("/root/main/SubViewport/UILayer/OptionsButton")
	var settings_btn = get_node_or_null("/root/main/SubViewport/UILayer/SettingsButton")
	var surrender_btn = get_node_or_null("/root/main/SubViewport/UILayer/SurrenderButton")
	var settings_panel = get_node_or_null("/root/main/SubViewport/UILayer/Settings Panel")

	if options_btn:
		options_btn.visible = true
		options_btn.connect("pressed", Callable(self, "_on_options_pressed"))
	if settings_btn:
		settings_btn.visible = false
		settings_btn.connect("pressed", Callable(self, "_on_settings_pressed"))
	if surrender_btn:
		surrender_btn.visible = false
	if settings_panel:
		settings_panel.visible = false



func _on_options_pressed():
	# Show settings/surrender, hide options
	var options_btn = get_node_or_null("/root/main/SubViewport/UILayer/OptionsButton")
	var settings_btn = get_node_or_null("/root/main/SubViewport/UILayer/SettingsButton")
	var surrender_btn = get_node_or_null("/root/main/SubViewport/UILayer/SurrenderButton")
	if options_btn:
		options_btn.visible = false
	if settings_btn:
		settings_btn.visible = true
	if surrender_btn:
		surrender_btn.visible = true

func _on_settings_pressed():
	# Show settings panel
	var settings_panel = get_node_or_null("/root/main/SubViewport/UILayer/Settings Panel")
	if settings_panel:
		settings_panel.visible = true

func _unhandled_input(event):
	# Handle mouse input to revert UI state
	if event is InputEventMouseButton and event.pressed:
		var options_btn = get_node_or_null("/root/main/SubViewport/UILayer/OptionsButton")
		var settings_btn = get_node_or_null("/root/main/SubViewport/UILayer/SettingsButton")
		var surrender_btn = get_node_or_null("/root/main/SubViewport/UILayer/SurrenderButton")
		var settings_panel = get_node_or_null("/root/main/SubViewport/UILayer/Settings Panel")

		var should_revert = false
		if settings_btn and settings_btn.visible and not settings_btn.get_global_rect().has_point(event.position):
			should_revert = true
		if surrender_btn and surrender_btn.visible and not surrender_btn.get_global_rect().has_point(event.position):
			should_revert = true
		if settings_panel and settings_panel.visible and not settings_panel.get_global_rect().has_point(event.position):
			should_revert = true

		if should_revert:
			if options_btn:
				options_btn.visible = true
			if settings_btn:
				settings_btn.visible = false
			if surrender_btn:
				surrender_btn.visible = false
			if settings_panel:
				settings_panel.visible = false

func _find_detail_box_if_needed() -> void:
	# Find and cache the card detail box node
	if not is_instance_valid(detail_box):
		var path = "main/UILayer/detail_box"
		var root = get_tree().get_root()
		detail_box = root.get_node(path)
		if detail_box == null or not is_instance_valid(detail_box):
			print("[UIManager] detail_box not found at path: %s" % path)

func show_card_detail(card_data: CustomCardData, card_node: Node) -> void:
	# Show card detail overlay
	_find_detail_box_if_needed()
	if is_instance_valid(detail_box):
		detail_box.show_with_card(card_data, card_node)
	else:
		print("[UIManager] Cannot show detail box: not found.")

func hide_card_detail() -> void:
	# Hide card detail overlay
	_find_detail_box_if_needed()
	if is_instance_valid(detail_box):
		detail_box.hide_box()
	else:
		print("[UIManager] Cannot hide detail box: not found.")
