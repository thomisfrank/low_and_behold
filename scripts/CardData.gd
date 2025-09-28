
# =====================================
# CardData.gd
# Card resource: display properties and effect metadata
# =====================================
extends Resource
class_name CustomCardData

# Effect types
enum EffectType {
	Swap_Card,
	Draw_Card,
	Card_Back
}

# Card visuals
@export var card_name: String = "Card Name"
@export var icon: Texture2D
@export var color_a: Color = Color.WHITE
@export var color_b: Color = Color.BLACK
@export var card_frame: Texture2D

# Shader parameters
@export var shader_speed: float = 0.8
@export var shader_intensity: float = 0.3
@export var shader_sharpness: float = 1.5

# Label padding
@export var pad_left: int = 20
@export var pad_right: int = 20
@export var pad_top: int = 20
@export var pad_bottom: int = 20

# Card effect
@export_group("Card Effect")
@export var effect_type: EffectType
@export var effect_value: int = 0

func get_description() -> String:
	# Return a description for the card's effect
	match effect_type:
		EffectType.Swap_Card:
			return "Pick a card from your opponent's hand to swap with this one."
		EffectType.Draw_Card:
			return "Draw a card from the deck to replace this one."
		EffectType.Card_Back:
			return "This card is a back card."
		_:
			return "No description available for this effect."

func get_effect_value() -> String:
	# Used by UI labels to show the card's numeric value, or empty for backs
	match effect_type:
		EffectType.Card_Back:
			return ""
		_:
			return str(effect_value)
