extends Node2D


# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================

## VISUAL SETTINGS (Colors)
const COLORS = {
	"background":      Color(0, 0, 0, 0.8),
	"text":            Color(1, 1, 1, 1),
	"border_default":  Color(0, 1, 0, 1),   # Green (Yours)
	"border_selected": Color(0.5, 0.5, 0.5), # Grey (Selected)
	"border_other":    Color(0, 0, 0, 1),    # Black (Others)
	"border_none":     Color(0, 0, 0, 0)
}

## LAYOUT SETTINGS (Base sizes in SCREEN PIXELS)
const LAYOUT = {
	"flag_width":       24.0, 
	"flag_height":      20.0,
	
	# Text Spacing Logic
	"text_padding_x":   8.0,   # Increased space so numbers breathe
	"min_text_width":   16.0,  # Minimum width for the text area (prevents tiny boxes for "1")
	
	"border_thickness": 1.0,   # Thickness for YOUR troops
	"border_other_px":  1.0,   # Thickness for ENEMY troops
	
	"font_size":        18
}

## ZOOM SCALING LIMITS
const ZOOM_LIMITS = {
	"min_scale": 0.12, 
	"max_scale": 4.0 
}

## SYSTEM SETTINGS
const GHOST_MARGIN := 10.0

# ==============================================================================
# 2. RESOURCES & STATE
# ==============================================================================

var _font: Font = preload("res://font/TTT-Regular.otf")

# External Dependencies
var map_sprite: Sprite2D
var map_width: float = 0.0

var _current_inv_zoom := 1.0
var old_cam_x = 0

func _ready() -> void:
	add_to_group("TroopRenderer")
	z_index = 20

func _process(_delta):
	var cam := get_viewport().get_camera_2d()
	
	if cam.zoom.x != old_cam_x:
		old_cam_x = cam.zoom.x
		var raw_scale = 1.0 / old_cam_x
		_current_inv_zoom = clamp(raw_scale, ZOOM_LIMITS.min_scale, ZOOM_LIMITS.max_scale)
		queue_redraw()


# ==============================================================================
# 3. DRAWING LOOP
# ==============================================================================

# New constant to define the maximum distance for troops to be considered 'stacked'
const STACKING_RADIUS := 1.0 # World units (adjust this value as needed)
const STACKING_OFFSET_Y := 20 # World units, how far apart the stacked badges are

func _draw() -> void:
	if not _can_draw():
		return

	var player_country = CountryManager.player_country.country_name
	var map_offset := map_sprite.texture.get_size() * 0.5
	
	# --- NEW: Group troops for stacking ---
	var grouped_troops = _group_troops_by_position(TroopManager.troops, STACKING_RADIUS)

	for base_pos in grouped_troops.keys():
		var stack: Array = grouped_troops[base_pos]
		var stack_size = stack.size()
		
		# Calculate the initial offset needed to center the entire stack vertically
		# NOW ACCOUNTING FOR ZOOM: scale the offset by inverse zoom
		var scaled_offset = STACKING_OFFSET_Y * _current_inv_zoom
		var start_y_offset = (stack_size - 1) * scaled_offset * 0.5

		for i in range(stack_size):
			var t = stack[i]
			# Position the bottom troop at the center of the province
			var troop_position = base_pos - map_offset
			
			# Calculate the vertical offset for the current badge in the stack
			var current_y_offset = start_y_offset - (i * scaled_offset)
			
			# Apply the offset to the base position
			var offset_pos = troop_position + Vector2(0, current_y_offset)

			# Draw Left(-1), Center(0), Right(1) for infinite scroll
			for j in [-1, 0, 1]:
				var scroll_offset = Vector2(map_width * j, 0)
				_draw_single_troop_visual(t, offset_pos + scroll_offset, player_country)


func _group_troops_by_position(troops: Array, radius: float) -> Dictionary:
	var groups = {}
	var processed_indices = []

	for i in range(troops.size()):
		if i in processed_indices:
			continue

		var t1 = troops[i]
		var group_key = t1.position # Use the first troop's position as the key for the stack
		
		# Start a new group with the current troop
		groups[group_key] = [t1]
		processed_indices.append(i)

		# Find all other troops close to t1
		for j in range(i + 1, troops.size()):
			var t2 = troops[j]
			
			# Check distance. If close enough, they belong to the same stack.
			if t1.position.distance_to(t2.position) < radius:
				groups[group_key].append(t2)
				processed_indices.append(j)

	return groups

func _can_draw() -> bool:
	return (
		not TroopManager.troops.is_empty() 
		and map_sprite != null 
		and map_sprite.texture != null 
		and map_width > 0.0
	)

# ==============================================================================
# 4. CORE RENDERING LOGIC
# ==============================================================================

func _draw_single_troop_visual(troop: TroopData, pos: Vector2, player_country: String) -> void:
	var label_text := str(troop.divisions)
	var scale_factor = _current_inv_zoom
	
	# --- Step A: Determine Styles (Border Color & Thickness) ---
	var style = _get_troop_style(troop, player_country)
	var current_border_width = max(0.25, style.width * scale_factor)

	# --- Step B: Calculate Dimensions (World Space) ---
	
	# 1. Fixed sizes
	var flag_size = Vector2(LAYOUT.flag_width, LAYOUT.flag_height) * scale_factor
	
	# 2. Text Area Calculation
	var font_size_world = LAYOUT.font_size * scale_factor
	# FIXME(pol): Must pass in alignment and width before font_size
	var raw_text_size = _font.get_string_size(label_text, LAYOUT.font_size) * scale_factor
	
	# Ensure the text area is at least the minimum width defined in config
	var min_text_w_world = LAYOUT.min_text_width * scale_factor
	var padding_world = LAYOUT.text_padding_x * scale_factor
	
	var final_text_area_width = max(raw_text_size.x + padding_world, min_text_w_world)
	
	# 3. Combine into Badge Size
	var total_width = flag_size.x + final_text_area_width
	var total_height = flag_size.y 
	
	var box_size = Vector2(total_width, total_height)
	var box_rect = Rect2(pos - box_size * 0.5, box_size)
	
	# --- Step C: Draw ---
	
	# 1. Background
	var bg_rect = box_rect.grow(-current_border_width * 0.5)
	if bg_rect.size.x > 0 and bg_rect.size.y > 0:
		draw_rect(bg_rect, COLORS.background, true)
	
	# 2. Flag (Left side)
	var flag_rect = Rect2(box_rect.position, flag_size)
	if troop.flag_texture:
		draw_texture_rect(troop.flag_texture, flag_rect, false)
	else:
		draw_rect(flag_rect, Color(0.5, 0.5, 0.5), true)
		
	# 3. Text (Right side - Centered in remaining space)
	var text_start_x = box_rect.position.x + flag_size.x
	var text_center_x = text_start_x + (final_text_area_width * 0.5)
	var draw_pos_x = text_center_x - (raw_text_size.x * 0.5)
	
	# Vertical centering
	#var font_ascent = _font.get_ascent(LAYOUT.font_size) * scale_factor
	var text_y_center = box_rect.position.y + (total_height * 0.5)
	var text_y_baseline = text_y_center + (raw_text_size.y * 0.25)
	
	draw_string(
		_font,
		Vector2(draw_pos_x, text_y_baseline),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size_world,
		COLORS.text
	)
	
	# 4. Border
	if style.color != COLORS.border_none:
		draw_rect(box_rect, style.color, false, current_border_width)

## Helper to determine border color AND thickness based on owner
func _get_troop_style(troop: TroopData, player_country: String) -> Dictionary:
	var is_owner = troop.country_name.to_lower() == player_country
	var is_selected = SelectionManager.selected_troops.has(troop)
	
	if is_owner:
		if is_selected:
			return { "color": COLORS.border_selected, "width": LAYOUT.border_thickness }
		else:
			return { "color": COLORS.border_default, "width": LAYOUT.border_thickness }
	else:
		# Enemy / Other
		return { "color": COLORS.border_other, "width": LAYOUT.border_other_px }
