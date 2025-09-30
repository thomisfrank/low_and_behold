shader_type canvas_item;

// color_a: Inner color for radial gradient
uniform vec4 color_a : source_color = vec4(0.149, 0.682, 0.373, 1.0); // Inner color (#26ae5f)
// color_b: Outer color for radial gradient
uniform vec4 color_b : source_color = vec4(0.161, 0.686, 0.380, 1.0); // Outer color (#29AF61)

// speed: How fast the blob wanders
uniform float speed = 0.3;
// intensity: How far the blob's center moves from the card's center
uniform float intensity = 0.3;
// sharpness: How soft or sharp the gradient's edge is
uniform float sharpness = 1.5;

void fragment() {
	// 1. Create a moving center point for our radial gradient.
	// We use two different sin/cos waves to make it wander in a circle/oval pattern.
	vec2 moving_center = vec2(
		0.5 + sin(TIME * speed) * intensity,
		0.5 + cos(TIME * speed * 0.7) * intensity // Slightly different frequency for a more natural path
	);

	// 2. Calculate the distance from the current pixel (UV) to the moving center.
	// This creates the base for our radial gradient.
	float dist = distance(UV, moving_center);

	// 3. Apply sharpness and clamp the result.
	// Multiplying by sharpness makes the gradient smaller/larger.
	// clamp() ensures the value stays between 0.0 and 1.0 for the mix function.
	float gradient_factor = clamp(dist * sharpness, 0.0, 1.0);
	
	// 4. Mix the two colors based on the final gradient factor.
	// 'color_a' will be at the center, 'color_b' will be at the edges.
	COLOR = mix(color_a, color_b, gradient_factor);
}