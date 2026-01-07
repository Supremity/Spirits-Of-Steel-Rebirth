shader_type canvas_item;

// --- INPUTS ---
uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;
// NOISE TEXTURE (Generated in World.gd)
uniform sampler2D ocean_noise : filter_nearest, repeat_enable;
// ORIGINAL TEXTURE (To show the grid)
uniform sampler2D original_texture : filter_linear_mipmap; 
uniform vec2 tex_size;

// Shallow/deep don't exist just named that way
uniform vec4 water_color_deep : source_color = vec4(0.10, 0.25, 0.45, 1.0);  
uniform vec4 water_color_shallow : source_color = vec4(0.25, 0.45, 0.65, 1.0); 



uniform vec4 sun_glint_color : source_color = vec4(0.9, 0.95, 1.0, 0.3); 
uniform vec4 country_border_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);

// --- SETTINGS ---
// Extremely slow speed for "scale"
uniform float sea_speed : hint_range(0.0, 0.2) = 0.02; 
uniform float wave_scale : hint_range(0.1, 5.0) = 1.5; 
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.15; 
// How much of the original grid/map shows through the water (0.0 to 1.0)
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.3; 

uniform float sea_pixel_size = 2.0;      // 1 = native pixels, 2–4 = chunkier
uniform float sea_height_steps = 6.0;    // number of discrete wave levels
uniform float sea_time_steps = 60.0;      // animation stepping


// --- HELPER: DOMAIN WARPING (Fluid Look) ---
float get_noise(vec2 uv, float t) {
	return texture(ocean_noise, (uv * wave_scale) + vec2(t, t * 0.2)).r;
}

float get_water_height(vec2 uv, float t) {
	float n1 = get_noise(uv, t);
	vec2 distortion = vec2(n1, n1) * distortion_strength;
	float n2 = get_noise(uv + distortion, t * -0.5); 
	return mix(n1, n2, 0.5);
}

// --- ID HELPERS ---
int get_id(vec2 uv) {
	vec4 c = texture(region_id_map, uv);
	int r = int(round(c.r * 255.0));
	int g = int(round(c.g * 255.0));
	return r + g * 256;
}

vec4 get_country_color(int id) {
	if (id <= 1) return vec4(0.0);
	float u = (float(id) + 0.5) / float(textureSize(state_colors, 0).x);
	return texture(state_colors, vec2(u, 0.0));
}

void fragment() {
	vec2 pixel_size = 1.0 / tex_size;
	int id = get_id(UV);
	vec4 final_color = vec4(0.0);

if (id == 0) {
    // --- PIXEL GRID SNAP ---
    vec2 grid_uv = floor(UV * tex_size / sea_pixel_size) 
                   * sea_pixel_size / tex_size;

    // --- TIME STEP (soft, minimal stepping) ---
    float t = TIME * sea_speed; // you can leave it continuous
    // Optional: tiny stepping to keep pixel-art feel
    // t = floor(t * 20.0)/20.0;

    // --- SINGLE NOISE SAMPLE ---
    float h = texture(ocean_noise, grid_uv + vec2(t, 0.0)).r;

    // --- REDUCED QUANTIZATION ---
    // Fewer steps → smoother
    h = floor(h * sea_height_steps) / sea_height_steps;
    // Try sea_height_steps = 12–16 for very soft stepping

    // --- COLOR MIX ---
    vec3 water = mix(
        water_color_deep.rgb,
        water_color_shallow.rgb,
        h
    );

    // --- GRID OVERLAY ---
    vec3 grid = texture(original_texture, grid_uv).rgb;
    water = mix(water, grid, grid_opacity);

    final_color = vec4(water, 1.0);
}

	
	// --- 2. CLEAN LAND (Solid) ---
	else if (id > 1) {
		final_color = vec4(get_country_color(id).rgb, 1.0);
	} 
	
	// --- 3. BORDERS ---
	else if (id == 1) {
		bool hard = false;
		vec4 neighbor_color = vec4(0.0);
		vec2 dirs[4] = vec2[4](vec2(0,1), vec2(0,-1), vec2(1,0), vec2(-1,0));
		
		for (int i = 0; i < 4; i++) {
			int nid = get_id(UV + dirs[i] * pixel_size * 1.5);
			if (nid == 0) { hard = true; break; }
			if (nid > 1) {
				vec4 c = get_country_color(nid);
				if (neighbor_color.a == 0.0) neighbor_color = c;
				else if (distance(c.rgb, neighbor_color.rgb) > 0.05) { hard = true; break; }
			}
		}
		
		final_color = hard ? country_border_color : mix(neighbor_color, vec4(0,0,0,1), 0.3);
	}

	COLOR = final_color;
}
