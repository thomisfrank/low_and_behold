extends Node2D

const CardScene = preload("res://scenes/cards.tscn")

# Card key names to display
var card_keys = [
	"TwoSwap", 
	"TwoDraw", 
	"FourSwap", 
	"FourDraw", 
	"SixSwap", 
	"SixDraw", 
	"EightSwap", 
	"EightDraw", 
	"TenSwap", 
	"TenDraw", 
	"CardBack"
]

# Card scaling factor
@export var card_scale = Vector2(0.8, 0.8)

# Current card index
var current_index = 0
var current_card = null

func _ready():
	# Create a single card in the middle of the screen
	current_card = CardScene.instantiate()
	add_child(current_card)
	
	# Position and scale
	current_card.position = Vector2(960, 540)  # Center of the screen (assuming 1920x1080)
	current_card.scale = card_scale
	
	# Make the card clickable
	current_card.connect("gui_input", Callable(self, "_on_card_clicked"))
	
	# Instructions text
	var instructions = Label.new()
	add_child(instructions)
	instructions.text = "Click on the card to cycle through all cards"
	instructions.position = Vector2(960, 850)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Display the first card
	_display_current_card()
	
	print("CardTester: Card created! Click to cycle through all cards.")

# Display the card at the current index
func _display_current_card():
	var key = card_keys[current_index]
	print("CardTester: Displaying card with key: " + key)
	
	# Load resource by key
	var resource_path = "res://scripts/resources/%s.tres" % key
	var card_data = load(resource_path)
	
	if card_data:
		print("CardTester: Successfully loaded resource for: " + key)
		current_card.call_deferred("display", card_data)
	else:
		print("CardTester: Failed to load resource for: " + key)

# Handle clicking on the card
func _on_card_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Cycle to the next card
		current_index = (current_index + 1) % card_keys.size()
		_display_current_card()