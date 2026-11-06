class_name ExpressionBox extends PanelContainer

enum ElementTypes {Paragraph, Button, Image, Header}
signal changed

# Consts kept as strings to avoid circular preloads
const EXPRESSION_SCENE_PATH = "res://Scenes/Expression.tscn"
const CASE_SCENE_PATH = "res://Scenes/Case.tscn"

var expression_type: InterpreterManager.ExpressionTypes
var is_child: bool = false

@export var expression_tabs: TabContainer

@export_group("Variable")
@export var value_edit: TextEdit
var value_expression = Expression.new()

@export_group("Array")
@export var items_box: VBoxContainer

@export_group("Event")
@export var pairs: VBoxContainer

@export_group("Function")
@export var func_options: OptionButton
@export var args_box: VBoxContainer

@export_group("Loop")
@export var for_edit: TextEdit
@export var iter_element_box: VBoxContainer
@export var do_box: VBoxContainer

@export_group("Match")
@export var match_expression: Container
@export var cases: VBoxContainer

@export_group("Element")
@export var element_tabs: TabContainer

@export_subgroup("Paragraph")
@export var paragraph_text: Container

@export_subgroup("Button")
@export var button_text: Container
@export var button_condition: Container
@export var button_finished: Container

@export_subgroup("Image")
@export var image_path: Container

@export_subgroup("Header")
@export var country1_name: Container
@export var country2_name: Container

@export_group("IdeologyDrift")
@export var drift_amount: SpinBox
@export var final_x: SpinBox
@export var final_y: SpinBox

func ToDict():
	match expression_tabs.current_tab:
		InterpreterManager.ExpressionTypes.Variable:
			if value_edit.text.is_valid_float():
				return float(value_edit.text)
			else:
				return value_edit.text
			# var error = value_expression.parse(value_edit.text)
			# if error != OK:
			# 	return value_edit.text
			#
			# var result = value_expression.execute([], self)
			# if value_expression.has_execute_failed():
			# 	return value_edit.text

		InterpreterManager.ExpressionTypes.List:
			return items_box.get_children().map(func(x): return x.ToDict())

		InterpreterManager.ExpressionTypes.Event:
			var fish = {}
			for pair in pairs.get_children():
				fish.merge(pair.ToDict())
			return fish

		InterpreterManager.ExpressionTypes.Function:
			return {
				"func": func_options.text,
				"args": args_box.get_children().map(func(x): return x.ToDict())
				}

		InterpreterManager.ExpressionTypes.Loop:
			var in_val = iter_element_box.get_children().map(func(x): return x.ToDict())
			if iter_element_box.get_child_count() == 1:
				var first = iter_element_box.get_child(0)
				if first.expression_type == InterpreterManager.ExpressionTypes.List:
					in_val = first.ToDict()
				elif first.expression_type == InterpreterManager.ExpressionTypes.Variable:
					var txt = str(first.ToDict())
					if txt.begins_with("[") and txt.ends_with("]"):
						var parsed = JSON.parse_string(txt)
						if parsed != null and typeof(parsed) == TYPE_ARRAY:
							in_val = parsed
					elif "," in txt:
						var arr = txt.split(",")
						for i in range(arr.size()):
							arr[i] = arr[i].strip_edges()
						in_val = arr
			return {
				"for": for_edit.text,
				"in": in_val,
				"do": do_box.get_children().map(func(x): return x.ToDict()),
				}

		InterpreterManager.ExpressionTypes.Match:
			var fish = {}
			if match_expression.get_child_count() > 0:
				fish["match"] = match_expression.get_child(0).ToDict()
			
			for case in cases.get_children():
				fish.merge(case.ToDict())
			return fish

		InterpreterManager.ExpressionTypes.Element:
			match element_tabs.current_tab:
				ElementTypes.Paragraph:
					return {
						"type": "paragraph",
						"text": paragraph_text.get_child(0).ToDict(),
						}

				ElementTypes.Button:
					return {
						"type": "button",
						"text": button_text.get_child(0).ToDict(),
						"condition": button_condition.get_child(0).ToDict(),
						"finished": button_finished.get_child(0).ToDict(),
						}

				ElementTypes.Image:
					return {
						"type": "image",
						"text": image_path.get_child(0).ToDict(),
						}

				ElementTypes.Header:
					return {
						"type": "country_header",
						"country1": country1_name.get_child(0).ToDict(),
						"country2": country2_name.get_child(0).ToDict(),
						}

		InterpreterManager.ExpressionTypes.IdeologyDrift:
			return {
				"drift_amount": drift_amount.value,
				"final_position": [final_x.value, final_y.value]
				}

static func FromDict(data, _is_child: bool = false) -> ExpressionBox:
	var scene = load(EXPRESSION_SCENE_PATH)
	var box: ExpressionBox = scene.instantiate()
	if not box: return null
	box.is_child = _is_child
	box.setup_ui()

	if typeof(data) == TYPE_ARRAY:
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.List
		for item in data:
			var child = FromDict(item, true)
			box.items_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		return box

	if typeof(data) != TYPE_DICTIONARY:
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Variable
		if box.value_edit: box.value_edit.text = str(data)
		return box

	if data.has("func"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Function
		var idx = -1
		for i in box.func_options.item_count:
			if box.func_options.get_item_text(i) == data["func"]:
				idx = i
				break
		if idx != -1:
			box.func_options.select(idx)
		
		var args_arr = data["args"] if typeof(data["args"]) == TYPE_ARRAY else [data["args"]]
		for arg in args_arr:
			var child = FromDict(arg, true)
			box.args_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		box._update_add_args_button()
		box._update_arg_placeholders()

	elif data.has("for"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Loop
		if box.for_edit: box.for_edit.text = data["for"]
		var child = FromDict(data["in"], true)
		if child:
			box.iter_element_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		var do_arr = data["do"] if typeof(data["do"]) == TYPE_ARRAY else [data["do"]]
		for item in do_arr:
			var _child = FromDict(item, true)
			box.do_box.add_child(_child)
			_child.changed.connect(func(): box.changed.emit())

	elif data.has("match"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Match
		var match_expr = FromDict(data["match"], true)
		box.match_expression.add_child(match_expr)
		match_expr.changed.connect(func(): box.changed.emit())
		
		for key in data.keys():
			if key == "match": continue
			var case = box._on_add_case_pressed()
			case.FromDict({key: data[key]})

	elif data.has("event"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Event
		for key in data.keys():
			var pair = box._on_add_pair_pressed()
			pair.FromDict({key: data[key]})

	elif data.has("type"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Element
		box._on_expression_type_tab_selected(InterpreterManager.ExpressionTypes.Element)
		match data["type"]:
			"paragraph":
				box.element_tabs.current_tab = box.ElementTypes.Paragraph
				FromDictInPlace(box.paragraph_text.get_child(0), data["text"])

			"button":
				box.element_tabs.current_tab = box.ElementTypes.Button
				FromDictInPlace(box.button_text.get_child(0), data["text"])
				FromDictInPlace(box.button_condition.get_child(0), data.get("condition", InterpreterManager.DUMMY_FUNC))
				FromDictInPlace(box.button_finished.get_child(0), data.get("finished", InterpreterManager.DUMMY_FUNC))

			"image":
				box.element_tabs.current_tab = box.ElementTypes.Image
				FromDictInPlace(box.image_path.get_child(0), data["text"])

			"country_header":
				box.element_tabs.current_tab = box.ElementTypes.Header
				FromDictInPlace(box.country1_name.get_child(0), data["country1"])
				FromDictInPlace(box.country2_name.get_child(0), data["country2"])

	elif data.has("drift_amount"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.IdeologyDrift
		box._on_expression_type_tab_selected(InterpreterManager.ExpressionTypes.IdeologyDrift)
		box.drift_amount.value = data["drift_amount"]
		box.final_x.value = data["final_position"][0]
		box.final_y.value = data["final_position"][1]
	
	return box


static func FromDictInPlace(box: ExpressionBox, data):
	if not box: return
	box.setup_ui()
	
	if typeof(data) == TYPE_ARRAY:
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.List
		for item in data:
			var child = FromDict(item, true)
			box.items_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		return

	if typeof(data) != TYPE_DICTIONARY:
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Variable
		if box.value_edit: box.value_edit.text = str(data)
		return

	if data.has("func"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Function
		var idx = -1
		for i in box.func_options.item_count:
			if box.func_options.get_item_text(i) == data["func"]:
				idx = i
				break
		if idx != -1:
			box.func_options.select(idx)
		
		var args_arr = data["args"] if typeof(data["args"]) == TYPE_ARRAY else [data["args"]]
		for arg in args_arr:
			var child = FromDict(arg, true)
			box.args_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		box._update_add_args_button()
		box._update_arg_placeholders()

	elif data.has("for"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Loop
		if box.for_edit: box.for_edit.text = data["for"]
		var child = FromDict(data["in"], true)
		if child:
			box.iter_element_box.add_child(child)
			child.changed.connect(func(): box.changed.emit())
		var do_arr = data["do"] if typeof(data["do"]) == TYPE_ARRAY else [data["do"]]
		for item in do_arr:
			var _child = FromDict(item, true)
			box.do_box.add_child(_child)
			_child.changed.connect(func(): box.changed.emit())

	elif data.has("match"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Match
		var match_expr = FromDict(data["match"], true)
		box.match_expression.add_child(match_expr)
		match_expr.changed.connect(func(): box.changed.emit())
		for key in data.keys():
			if key == "match": continue
			var case = box._on_add_case_pressed()
			case.FromDict({key: data[key]})

	elif data.has("event"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Event
		for key in data.keys():
			var pair = box._on_add_pair_pressed()
			pair.FromDict({key: data[key]})

	elif data.has("type"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Element
		box._on_expression_type_tab_selected(InterpreterManager.ExpressionTypes.Element)
		match data["type"]:
			"paragraph":
				box.element_tabs.current_tab = box.ElementTypes.Paragraph
				FromDictInPlace(box.paragraph_text.get_child(0), data["text"])

			"button":
				box.element_tabs.current_tab = box.ElementTypes.Button
				FromDictInPlace(box.button_text.get_child(0), data["text"])
				FromDictInPlace(box.button_condition.get_child(0), data.get("condition", InterpreterManager.DUMMY_FUNC))
				FromDictInPlace(box.button_finished.get_child(0), data.get("finished", InterpreterManager.DUMMY_FUNC))

			"image":
				box.element_tabs.current_tab = box.ElementTypes.Image
				FromDictInPlace(box.image_path.get_child(0), data["text"])

			"country_header":
				box.element_tabs.current_tab = box.ElementTypes.Header
				FromDictInPlace(box.country1_name.get_child(0), data["country1"])
				FromDictInPlace(box.country2_name.get_child(0), data["country2"])

	elif data.has("drift_amount"):
		box.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.IdeologyDrift
		box._on_expression_type_tab_selected(InterpreterManager.ExpressionTypes.IdeologyDrift)
		box.drift_amount.value = data["drift_amount"]
		box.final_x.value = data["final_position"][0]
		box.final_y.value = data["final_position"][1]


func setup_ui():
	if not func_options.item_count:
		for function in InterpreterManager.functions.keys():
			func_options.add_item(function)
	
	expression_tabs.set_tab_hidden(InterpreterManager.ExpressionTypes.Close, !is_child)


func _ready() -> void:
	setup_ui()
	
	# Connect change signals
	expression_tabs.tab_selected.connect(func(_tab): changed.emit())
	func_options.item_selected.connect(_on_func_selected)
	if value_edit: value_edit.text_changed.connect(func(): changed.emit())
	if for_edit: for_edit.text_changed.connect(func(): changed.emit())
	if args_box:
		args_box.child_entered_tree.connect(func(_node): _update_add_args_button())
		args_box.child_exiting_tree.connect(func(_node): _update_add_args_button.call_deferred())

func _update_add_args_button() -> void:
	var func_name = func_options.get_item_text(func_options.selected) if func_options.selected != -1 else ""
	var is_variadic = func_name in ["any", "all", "and", "or", "has_pids"]
	var expected_args = 0
	if InterpreterManager.functions.has(func_name):
		expected_args = InterpreterManager.functions[func_name].size()
	
	var add_args_btn = args_box.get_parent().get_node_or_null("AddArgs/AddArgsButton")
	if add_args_btn:
		add_args_btn.disabled = not is_variadic and args_box.get_child_count() >= expected_args


func _update_arg_placeholders() -> void:
	var func_name = func_options.get_item_text(func_options.selected) if func_options.selected != -1 else ""
	var index := 0
	for child in args_box.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is ExpressionBox and child.value_edit:
			child.value_edit.placeholder_text = InterpreterManager.get_param_name(func_name, index)
		index += 1


# func _process(delta: float) -> void:
# 	print(ToDict())


func _add_inital_expression(box: Container):
	if !box.get_children():
		var scene = load(EXPRESSION_SCENE_PATH)
		var expr: ExpressionBox = scene.instantiate()
		expr.expression_tabs.current_tab = InterpreterManager.ExpressionTypes.Variable
		expr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(expr)


func _on_expression_type_tab_selected(tab: int) -> void:
	match tab:
		InterpreterManager.ExpressionTypes.Close:
			queue_free()
		# ExpressionTypes.Loop:
		# 	_add_inital_expression(iter_element_box)
		# 	_add_inital_expression(do_box)
		InterpreterManager.ExpressionTypes.Match:
			_add_inital_expression(match_expression)
		InterpreterManager.ExpressionTypes.Element:
			_add_inital_expression(paragraph_text)
			_add_inital_expression(button_text)
			_add_inital_expression(button_condition)
			_add_inital_expression(button_finished)
			_add_inital_expression(country1_name)
			_add_inital_expression(country2_name)
			_add_inital_expression(image_path)
		_:
			expression_type = tab as InterpreterManager.ExpressionTypes
	changed.emit()
	

func add_expression(container: Node) -> ExpressionBox:
	var scene = load(EXPRESSION_SCENE_PATH)
	var expr: ExpressionBox = scene.instantiate()
	if !expr:
		return null
	
	expr.is_child = true
	container.add_child(expr)
	expr.changed.connect(func(): changed.emit())
	changed.emit()
	return expr


func _on_func_selected(index: int) -> void:
	var func_name = func_options.get_item_text(index)
	if InterpreterManager.functions.has(func_name):
		# Clear existing args
		for child in args_box.get_children():
			child.queue_free()
		
		# Auto-fill
		var arg_types = InterpreterManager.functions[func_name]
		for type in arg_types:
			var expr = add_expression(args_box)
			if expr:
				expr.expression_tabs.current_tab = type
				expr._on_expression_type_tab_selected(type)
	
	_update_add_args_button()
	_update_arg_placeholders()
	changed.emit()


func _on_add_args_button_pressed() -> void:
	add_expression(args_box)
	_update_arg_placeholders()


func _on_add_match_pressed() -> void:
	add_expression(match_expression)


func _on_add_iter_element_button_pressed() -> void:
	add_expression(iter_element_box)


func _on_add_do_button_pressed() -> void:
	add_expression(do_box)


func _on_add_case_pressed() -> Node:
	var scene = load(CASE_SCENE_PATH)
	var case = scene.instantiate()
	cases.add_child(case)
	case.changed.connect(func(): changed.emit())
	changed.emit()
	return case


func _on_add_pair_pressed() -> Node:
	var scene = load(CASE_SCENE_PATH)
	var pair = scene.instantiate()
	pairs.add_child(pair)
	pair.changed.connect(func(): changed.emit())
	changed.emit()
	return pair


func _on_add_item_button_pressed() -> void:
	add_expression(items_box)
