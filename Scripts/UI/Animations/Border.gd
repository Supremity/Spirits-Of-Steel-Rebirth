extends Button

var _normal_sb: StyleBoxFlat
var _hover_sb: StyleBoxFlat
var _tween: Tween

var BORDER_WIDTH := 2
const DURATION   := 0.25
const ANIMATION_PROPERTIES := ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]

func _ready() -> void:
	_normal_sb = get_theme_stylebox("normal").duplicate()
	_hover_sb  = get_theme_stylebox("hover").duplicate()
	BORDER_WIDTH = _hover_sb.border_width_left
	add_theme_stylebox_override("normal",  _normal_sb)
	add_theme_stylebox_override("hover",  _normal_sb)

	mouse_entered.connect(func(): _tween_border(BORDER_WIDTH))
	mouse_exited.connect(func():  _tween_border(0))

func _tween_border(target: int) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var first := true
	for sb in [_normal_sb, _hover_sb]:
		for prop in ANIMATION_PROPERTIES:
			if first:
				_tween.tween_property(sb, prop, target, DURATION)
				first = false
			else:
				_tween.parallel().tween_property(sb, prop, target, DURATION)
