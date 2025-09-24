extends Node2D

# Card Scene - using a custom loader to avoid the problematic Card.gd script
const CardScene = preload("res://scenes/cards.tscn")

# Card script
const NewCardScript = preload("res://scripts/NewCard.gd")

# All card resources preloaded for direct instantiation
const CardResources = {
	"CardBack": preload("res://scripts/resources/CardBack.tres"),
	"TwoSwap": preload("res://scripts/resources/TwoSwap.tres"),
	"TwoDraw": preload("res://scripts/resources/TwoDraw.tres"),
	"FourSwap": preload("res://scripts/resources/FourSwap.tres"),
	"FourDraw": preload("res://scripts/resources/FourDraw.tres"),
	"SixSwap": preload("res://scripts/resources/SixSwap.tres"),
	"SixDraw": preload("res://scripts/resources/SixDraw.tres"),
	"EightSwap": preload("res://scripts/resources/EightSwap.tres"),
	"EightDraw": preload("res://scripts/resources/EightDraw.tres"),
	"TenSwap": preload("res://scripts/resources/TenSwap.tres"),
	"TenDraw": preload("res://scripts/resources/TenDraw.tres"),
}

# Card placement parameters
@export var card_scale = Vector2(0.5, 0.5)
@export var horizontal_spacing = 175

func _ready():
	# Position values
	var start_x = 150
	var y_position = 300
	
	print("Instantiating all cards...")
	
	# Create each card in a horizontal row
	var index = 0
	for key in CardResources:
		var resource = CardResources[key]
		
		# Create the card exactly as defined in the resource
		var card = CardScene.instantiate()
		
		# Replace the card script with our clean implementation
		card.set_script(NewCardScript)
		
		add_child(card)
		
		# Set card position, scale and z-index
		var x_pos = start_x + (index * horizontal_spacing)
		card.position = Vector2(x_pos, y_position)
		card.scale = card_scale
		
		# Set a decreasing z-index for each card with LARGE gaps to ensure proper stacking
		# This makes cards on the left appear on top of cards on the right
		card.z_index = 1000 - (index * 100)
		
		# Display the card directly with its resource
		print("Creating card: " + key)
		card.display(resource)
		
		index += 1