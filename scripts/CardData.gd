
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
### Card visuals
# card_name: Name of the card
@export var card_name: String = "Card Name"
# icon: Icon texture for the card
@export var icon: Texture2D
# color_a: Primary color for card background/shader
@export var color_a: Color = Color.WHITE
# color_b: Secondary color for card background/shader
@export var color_b: Color = Color.BLACK
# card_frame: Texture for card frame
@export var card_frame: Texture2D

# Shader parameters
### Shader parameters
# shader_speed: Speed of card background shader animation
@export var shader_speed: float = 0.8
# shader_intensity: Intensity of shader effect
@export var shader_intensity: float = 0.3
# shader_sharpness: Sharpness of shader gradient
@export var shader_sharpness: float = 1.5

# Label padding
### Label padding
# pad_left: Padding for card label layout (left)
@export var pad_left: int = 20
# pad_right: Padding for card label layout (right)
@export var pad_right: int = 20
# pad_top: Padding for card label layout (top)
@export var pad_top: int = 20
# pad_bottom: Padding for card label layout (bottom)
@export var pad_bottom: int = 20

# Card effect
@export_group("Card Effect")
### Card effect
# effect_type: Type of card effect (enum)
@export var effect_type: EffectType
# effect_value: Value of card effect
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
