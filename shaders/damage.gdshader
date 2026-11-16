shader_type canvas_item;
uniform sampler2D NOISE_PATTERN;
uniform float upper;
uniform float lower;
uniform float dirt;
uniform vec3 color;

void fragment(){
	vec2 uhh = UV - 0.5;
	float ooo = (uhh.x * uhh.x + uhh.y * uhh.y);
	float gradient = (2.0 - UV.x - UV.y) / 2.0;
	vec4 newColor = COLOR;
	newColor.rgb *= 2.0*(upper*gradient + lower*(1.0 - gradient));
	newColor.rgb -= dirt * vec3(texture(NOISE_PATTERN, SCREEN_UV).x * ooo);
	newColor.rgb += (color);
	COLOR.rgb = newColor.rgb;
}