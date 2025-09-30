shader_type canvas_item;

// jitter_amount: Amount of pixel jitter
uniform float jitter_amount : hint_range(0.0, 10.0) = 2.0;
// jitter_rate: Speed of jitter animation
uniform float jitter_rate : hint_range(0.0, 20.0) = 8.0;

void fragment() {
    float t = TIME * jitter_rate;
    vec2 pixel = floor(FRAGCOORD.xy / 2.0);
    float noise = fract(sin(dot(pixel, vec2(12.9898, 78.233)) + t) * 43758.5453);
    vec2 offset = vec2(noise, noise) * jitter_amount * TEXTURE_PIXEL_SIZE;

    COLOR = texture(TEXTURE, UV + offset);
}