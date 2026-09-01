extends PanelContainer
class_name ArenaBuilderPanel

signal apply_requested
signal save_requested
signal refresh_models_requested
signal template_gallery_requested
signal test_requested(request: Dictionary)
signal close_requested

const MAX_SLOTS := 5

var _preset_label: Label
var _status_label: Label
var _slot_rows: Array = []
var _event_rows: Array = []
var _loaded_models: Array = []

var _rules_edit: TextEdit
var _topics_edit: TextEdit
var _angles_edit: TextEdit
var _global_script_edit: TextEdit
var _turn_script_edit: TextEdit

var _turn_interval_spin: SpinBox
var _stall_timeout_spin: SpinBox
var _request_wait_buffer_spin: SpinBox
var _max_tokens_spin: SpinBox
var _temperature_spin: SpinBox
var _reasoner_timeout_spin: SpinBox
var _failure_limit_spin: SpinBox
var _failure_cooldown_spin: SpinBox
var _event_min_spin: SpinBox
var _event_max_spin: SpinBox
var _doom_enabled_check: CheckBox

var _test_model_picker: OptionButton
var _test_model_edit: LineEdit
var _test_prompt_edit: TextEdit
var _test_response_edit: TextEdit
var _test_status_label: Label
var _loaded_models_list: ItemList

func _init():
    _build_ui()

func _build_ui() -> void:
    visible = false
    mouse_filter = Control.MOUSE_FILTER_STOP
    z_index = 20
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    offset_left = 140.0
    offset_top = 28.0
    offset_right = -270.0
    offset_bottom = -28.0

    var panel_style = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.03, 0.05, 0.08, 0.96)
    panel_style.border_color = Color(0.26, 0.73, 0.95, 0.9)
    panel_style.set_border_width_all(2)
    panel_style.corner_radius_top_left = 14
    panel_style.corner_radius_top_right = 14
    panel_style.corner_radius_bottom_left = 14
    panel_style.corner_radius_bottom_right = 14
    panel_style.content_margin_left = 16
    panel_style.content_margin_right = 16
    panel_style.content_margin_top = 16
    panel_style.content_margin_bottom = 16
    add_theme_stylebox_override("panel", panel_style)

    var root = VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 10)
    add_child(root)

    var header = HBoxContainer.new()
    header.add_theme_constant_override("separation", 10)
    root.add_child(header)

    var title_block = VBoxContainer.new()
    title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title_block)

    var title = Label.new()
    title.text = "ARENA BUILDER"
    title.add_theme_font_size_override("font_size", 28)
    title.add_theme_color_override("font_color", Color(0.98, 0.89, 0.42))
    title_block.add_child(title)

    var subtitle = Label.new()
    subtitle.text = "Tune the roster, prompt scripts, chaos engine, and live LM Studio probes."
    subtitle.add_theme_color_override("font_color", Color(0.72, 0.81, 0.92))
    title_block.add_child(subtitle)

    _preset_label = Label.new()
    _preset_label.text = "Preset 1"
    _preset_label.add_theme_color_override("font_color", Color(0.33, 0.85, 0.67))
    title_block.add_child(_preset_label)

    var button_row = HBoxContainer.new()
    button_row.alignment = BoxContainer.ALIGNMENT_END
    button_row.add_theme_constant_override("separation", 8)
    header.add_child(button_row)

    button_row.add_child(_make_header_button("Refresh Models", Color(0.16, 0.58, 0.86), func():
        refresh_models_requested.emit()
    ))
    button_row.add_child(_make_header_button("Templates", Color(0.55, 0.22, 0.96), func():
        # This will be handled by main.gd via a new signal
        template_gallery_requested.emit()
    ))
    button_row.add_child(_make_header_button("Apply Live", Color(0.17, 0.67, 0.43), func():
        apply_requested.emit()
    ))
    button_row.add_child(_make_header_button("Save Config", Color(0.96, 0.55, 0.22), func():
        save_requested.emit()
    ))
    button_row.add_child(_make_header_button("Close", Color(0.77, 0.23, 0.23), func():
        close_requested.emit()
    ))

    _status_label = Label.new()
    _status_label.text = "Builder ready."
    _status_label.add_theme_color_override("font_color", Color(0.67, 0.78, 0.90))
    root.add_child(_status_label)

    var tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.add_child(tabs)

    tabs.add_child(_build_roster_tab())
    tabs.add_child(_build_rules_tab())
    tabs.add_child(_build_prompts_tab())
    tabs.add_child(_build_events_tab())
    tabs.add_child(_build_test_tab())

func _make_header_button(text: String, color: Color, callback: Callable) -> Button:
    var button = Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(118, 36)
    var style_normal = StyleBoxFlat.new()
    style_normal.bg_color = color
    style_normal.corner_radius_top_left = 8
    style_normal.corner_radius_top_right = 8
    style_normal.corner_radius_bottom_left = 8
    style_normal.corner_radius_bottom_right = 8
    var style_hover = style_normal.duplicate()
    style_hover.bg_color = color.lightened(0.12)
    var style_pressed = style_normal.duplicate()
    style_pressed.bg_color = color.darkened(0.12)
    button.add_theme_stylebox_override("normal", style_normal)
    button.add_theme_stylebox_override("hover", style_hover)
    button.add_theme_stylebox_override("pressed", style_pressed)
    button.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
    button.pressed.connect(callback)
    return button

func _make_card() -> PanelContainer:
    var panel = PanelContainer.new()
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.07, 0.10, 0.15, 0.94)
    style.border_color = Color(0.18, 0.27, 0.37, 0.9)
    style.set_border_width_all(1)
    style.corner_radius_top_left = 10
    style.corner_radius_top_right = 10
    style.corner_radius_bottom_left = 10
    style.corner_radius_bottom_right = 10
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 10
    style.content_margin_bottom = 10
    panel.add_theme_stylebox_override("panel", style)
    return panel

func _make_field_label(text: String, accent: Color = Color(0.60, 0.74, 0.89)) -> Label:
    var label = Label.new()
    label.text = text
    label.add_theme_color_override("font_color", accent)
    return label

func _build_roster_tab() -> Control:
    var scroll = ScrollContainer.new()
    scroll.name = "Roster"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    scroll.add_child(content)

    var intro = Label.new()
    intro.text = "Edit the active preset. Slot scripts append directly to the system prompt, and timeout overrides let you baby heavy reasoners."
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.add_theme_color_override("font_color", Color(0.73, 0.81, 0.91))
    content.add_child(intro)

    for i in range(MAX_SLOTS):
        var card = _make_card()
        content.add_child(card)

        var box = VBoxContainer.new()
        box.add_theme_constant_override("separation", 6)
        card.add_child(box)

        var top = HBoxContainer.new()
        top.add_theme_constant_override("separation", 8)
        box.add_child(top)

        var enabled = CheckBox.new()
        enabled.text = "Slot %d Active" % (i + 1)
        enabled.button_pressed = true
        top.add_child(enabled)

        var timeout_label = _make_field_label("Timeout")
        top.add_child(timeout_label)

        var timeout_spin = SpinBox.new()
        timeout_spin.min_value = 0
        timeout_spin.max_value = 180
        timeout_spin.step = 5
        timeout_spin.custom_minimum_size.x = 90
        timeout_spin.prefix = "sec "
        top.add_child(timeout_spin)

        var middle = HBoxContainer.new()
        middle.add_theme_constant_override("separation", 8)
        box.add_child(middle)

        var name_label = _make_field_label("Name")
        middle.add_child(name_label)

        var name_edit = LineEdit.new()
        name_edit.placeholder_text = "Display name"
        name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        middle.add_child(name_edit)

        var color_label = _make_field_label("Color")
        middle.add_child(color_label)

        var color_button = ColorPickerButton.new()
        color_button.custom_minimum_size = Vector2(48, 28)
        middle.add_child(color_button)

        var model_row = HBoxContainer.new()
        model_row.add_theme_constant_override("separation", 8)
        box.add_child(model_row)

        var model_label = _make_field_label("Model")
        model_row.add_child(model_label)

        var model_edit = LineEdit.new()
        model_edit.placeholder_text = "LM Studio model id"
        model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        model_row.add_child(model_edit)

        var picker = OptionButton.new()
        picker.custom_minimum_size.x = 220
        picker.item_selected.connect(_on_slot_model_picked.bind(model_edit))
        model_row.add_child(picker)

        var script_label = _make_field_label("Slot Script", Color(0.95, 0.72, 0.33))
        box.add_child(script_label)

        var script_edit = TextEdit.new()
        script_edit.custom_minimum_size.y = 84
        script_edit.placeholder_text = "Optional slot-level instructions. Example: attack anyone who hedges, keep the tone savage, cite concrete failure modes."
        box.add_child(script_edit)

        _slot_rows.append({
            "enabled": enabled,
            "name": name_edit,
            "color": color_button,
            "model": model_edit,
            "picker": picker,
            "timeout": timeout_spin,
            "script": script_edit,
        })

    return scroll

func _build_rules_tab() -> Control:
    var scroll = ScrollContainer.new()
    scroll.name = "Rules"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    scroll.add_child(content)

    var timing_card = _make_card()
    content.add_child(timing_card)
    var timing_box = VBoxContainer.new()
    timing_box.add_theme_constant_override("separation", 6)
    timing_card.add_child(timing_box)
    timing_box.add_child(_make_field_label("Arena Tempo", Color(0.95, 0.72, 0.33)))

    var timing_grid = GridContainer.new()
    timing_grid.columns = 4
    timing_grid.add_theme_constant_override("h_separation", 8)
    timing_grid.add_theme_constant_override("v_separation", 6)
    timing_box.add_child(timing_grid)

    _turn_interval_spin = _make_spin_field(timing_grid, "Turn Interval", 1, 30, 0.5, "sec ")
    _stall_timeout_spin = _make_spin_field(timing_grid, "Base Stall Limit", 5, 120, 1, "sec ")
    _request_wait_buffer_spin = _make_spin_field(timing_grid, "Wait Buffer", 0, 30, 1, "sec ")
    _max_tokens_spin = _make_spin_field(timing_grid, "Max Tokens", 32, 1024, 16, "tok ")
    _temperature_spin = _make_spin_field(timing_grid, "Temperature", 0, 2, 0.05, "tmp ")
    _reasoner_timeout_spin = _make_spin_field(timing_grid, "Reasoner Timeout", 10, 180, 5, "sec ")
    _failure_limit_spin = _make_spin_field(timing_grid, "Failure Limit", 1, 6, 1, "x ")
    _failure_cooldown_spin = _make_spin_field(timing_grid, "Cooldown", 1, 120, 1, "sec ")

    var rules_card = _make_card()
    content.add_child(rules_card)
    var rules_box = VBoxContainer.new()
    rules_box.add_theme_constant_override("separation", 6)
    rules_card.add_child(rules_box)
    rules_box.add_child(_make_field_label("Debate Rules", Color(0.33, 0.85, 0.67)))
    _rules_edit = TextEdit.new()
    _rules_edit.custom_minimum_size.y = 120
    _rules_edit.placeholder_text = "One rule per line."
    rules_box.add_child(_rules_edit)

    var topics_card = _make_card()
    content.add_child(topics_card)
    var topics_box = VBoxContainer.new()
    topics_box.add_theme_constant_override("separation", 6)
    topics_card.add_child(topics_box)
    topics_box.add_child(_make_field_label("Round Topics", Color(0.47, 0.76, 0.98)))
    _topics_edit = TextEdit.new()
    _topics_edit.custom_minimum_size.y = 160
    _topics_edit.placeholder_text = "One topic per line."
    topics_box.add_child(_topics_edit)

    return scroll

func _build_prompts_tab() -> Control:
    var scroll = ScrollContainer.new()
    scroll.name = "Prompts"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    scroll.add_child(content)

    var intro = Label.new()
    intro.text = "Global scripts layer on top of the baked arena prompt. Angle shifts are one per line and rotate automatically."
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.add_theme_color_override("font_color", Color(0.73, 0.81, 0.91))
    content.add_child(intro)

    var global_card = _make_card()
    content.add_child(global_card)
    var global_box = VBoxContainer.new()
    global_box.add_theme_constant_override("separation", 6)
    global_card.add_child(global_box)
    global_box.add_child(_make_field_label("Global System Script", Color(0.95, 0.72, 0.33)))
    _global_script_edit = TextEdit.new()
    _global_script_edit.custom_minimum_size.y = 140
    _global_script_edit.placeholder_text = "Extra system-level instructions applied to every debater."
    global_box.add_child(_global_script_edit)

    var turn_card = _make_card()
    content.add_child(turn_card)
    var turn_box = VBoxContainer.new()
    turn_box.add_theme_constant_override("separation", 6)
    turn_card.add_child(turn_box)
    turn_box.add_child(_make_field_label("Turn Cue Script", Color(0.33, 0.85, 0.67)))
    _turn_script_edit = TextEdit.new()
    _turn_script_edit.custom_minimum_size.y = 120
    _turn_script_edit.placeholder_text = "Extra instructions appended to the user turn cue."
    turn_box.add_child(_turn_script_edit)

    var angles_card = _make_card()
    content.add_child(angles_card)
    var angles_box = VBoxContainer.new()
    angles_box.add_theme_constant_override("separation", 6)
    angles_card.add_child(angles_box)
    angles_box.add_child(_make_field_label("Angle Shift Rotation", Color(0.47, 0.76, 0.98)))
    _angles_edit = TextEdit.new()
    _angles_edit.custom_minimum_size.y = 180
    _angles_edit.placeholder_text = "One angle shift per line."
    angles_box.add_child(_angles_edit)

    return scroll

func _build_events_tab() -> Control:
    var scroll = ScrollContainer.new()
    scroll.name = "Events"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    scroll.add_child(content)

    var meta_card = _make_card()
    content.add_child(meta_card)
    var meta_box = VBoxContainer.new()
    meta_box.add_theme_constant_override("separation", 6)
    meta_card.add_child(meta_box)
    meta_box.add_child(_make_field_label("Chaos Engine", Color(0.95, 0.72, 0.33)))

    var meta_grid = GridContainer.new()
    meta_grid.columns = 4
    meta_grid.add_theme_constant_override("h_separation", 8)
    meta_grid.add_theme_constant_override("v_separation", 6)
    meta_box.add_child(meta_grid)

    _event_min_spin = _make_spin_field(meta_grid, "Event Min", 5, 300, 1, "sec ")
    _event_max_spin = _make_spin_field(meta_grid, "Event Max", 5, 300, 1, "sec ")

    _doom_enabled_check = CheckBox.new()
    _doom_enabled_check.text = "Enable Doom Meter"
    _doom_enabled_check.button_pressed = true
    meta_box.add_child(_doom_enabled_check)

    for event_type in ["new_topic", "memory_wipe", "speed_boost", "opinion_flip", "confidence_surge", "agape_override", "brain_fog", "truth_spike", "gravity_well", "parasite_bloom"]:
        var card = _make_card()
        content.add_child(card)
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        card.add_child(row)

        var enabled = CheckBox.new()
        enabled.text = event_type.replace("_", " ").to_upper()
        enabled.button_pressed = true
        row.add_child(enabled)

        row.add_child(_make_field_label("Banner Label"))

        var label_edit = LineEdit.new()
        label_edit.placeholder_text = "Event banner text"
        label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label_edit)

        _event_rows.append({
            "type": event_type,
            "enabled": enabled,
            "label": label_edit,
        })

    return scroll

func _build_test_tab() -> Control:
    var root = VBoxContainer.new()
    root.name = "Test"
    root.add_theme_constant_override("separation", 8)

    var top_card = _make_card()
    root.add_child(top_card)
    var top_box = VBoxContainer.new()
    top_box.add_theme_constant_override("separation", 6)
    top_card.add_child(top_box)
    top_box.add_child(_make_field_label("LM Studio Probe", Color(0.95, 0.72, 0.33)))

    var model_row = HBoxContainer.new()
    model_row.add_theme_constant_override("separation", 8)
    top_box.add_child(model_row)

    _test_model_picker = OptionButton.new()
    _test_model_picker.custom_minimum_size.x = 280
    _test_model_picker.item_selected.connect(_on_test_model_picked)
    model_row.add_child(_test_model_picker)

    _test_model_edit = LineEdit.new()
    _test_model_edit.placeholder_text = "Custom model id"
    _test_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    model_row.add_child(_test_model_edit)

    var run_button = _make_header_button("Run Probe", Color(0.16, 0.58, 0.86), func():
        test_requested.emit({
            "model": _test_model_edit.text.strip_edges(),
            "prompt": _test_prompt_edit.text,
        })
    )
    model_row.add_child(run_button)

    _test_prompt_edit = TextEdit.new()
    _test_prompt_edit.custom_minimum_size.y = 120
    _test_prompt_edit.placeholder_text = "Prompt to send to LM Studio."
    _test_prompt_edit.text = "Reply in one punchy sentence explaining why your model belongs in Silicon Arena."
    top_box.add_child(_test_prompt_edit)

    _test_status_label = Label.new()
    _test_status_label.text = "No probe running."
    _test_status_label.add_theme_color_override("font_color", Color(0.67, 0.78, 0.90))
    top_box.add_child(_test_status_label)

    var bottom = HSplitContainer.new()
    bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(bottom)

    var models_card = _make_card()
    bottom.add_child(models_card)
    var models_box = VBoxContainer.new()
    models_box.add_theme_constant_override("separation", 6)
    models_card.add_child(models_box)
    models_box.add_child(_make_field_label("Loaded Models", Color(0.33, 0.85, 0.67)))
    _loaded_models_list = ItemList.new()
    _loaded_models_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _loaded_models_list.item_selected.connect(_on_loaded_model_selected)
    models_box.add_child(_loaded_models_list)

    var response_card = _make_card()
    bottom.add_child(response_card)
    var response_box = VBoxContainer.new()
    response_box.add_theme_constant_override("separation", 6)
    response_card.add_child(response_box)
    response_box.add_child(_make_field_label("Probe Output", Color(0.47, 0.76, 0.98)))
    _test_response_edit = TextEdit.new()
    _test_response_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _test_response_edit.editable = false
    _test_response_edit.placeholder_text = "Response output and diagnostics appear here."
    response_box.add_child(_test_response_edit)

    return root

func _make_spin_field(parent: GridContainer, label_text: String, min_value: float, max_value: float, step: float, prefix: String) -> SpinBox:
    var label = _make_field_label(label_text)
    parent.add_child(label)
    var spin = SpinBox.new()
    spin.min_value = min_value
    spin.max_value = max_value
    spin.step = step
    spin.prefix = prefix
    spin.custom_minimum_size.x = 90
    parent.add_child(spin)
    return spin

func _on_slot_model_picked(index: int, target_edit: LineEdit) -> void:
    if index <= 0:
        return
    var model_index = index - 1
    if model_index >= 0 and model_index < _loaded_models.size():
        target_edit.text = str(_loaded_models[model_index])

func _on_test_model_picked(index: int) -> void:
    if index <= 0:
        return
    var model_index = index - 1
    if model_index >= 0 and model_index < _loaded_models.size():
        _test_model_edit.text = str(_loaded_models[model_index])

func _on_loaded_model_selected(index: int) -> void:
    if index >= 0 and index < _loaded_models.size():
        _test_model_edit.text = str(_loaded_models[index])

func set_status(text: String, success: bool = true) -> void:
    _status_label.text = text
    _status_label.add_theme_color_override("font_color", Color(0.33, 0.85, 0.67) if success else Color(0.98, 0.52, 0.44))

func set_preset_summary(index: int, total: int) -> void:
    _preset_label.text = "Editing Preset %d of %d" % [index + 1, maxi(total, 1)]

func set_loaded_models(models: Array) -> void:
    _loaded_models = models.duplicate()
    for row in _slot_rows:
        var picker: OptionButton = row["picker"]
        picker.clear()
        picker.add_item("Loaded models...")
        for model in _loaded_models:
            picker.add_item(str(model))
    _test_model_picker.clear()
    _test_model_picker.add_item("Loaded models...")
    _loaded_models_list.clear()
    for model in _loaded_models:
        var model_text = str(model)
        _test_model_picker.add_item(model_text)
        _loaded_models_list.add_item(model_text)

func load_state(state: Dictionary) -> void:
    set_preset_summary(int(state.get("preset_index", 0)), int(state.get("preset_count", 1)))
    var roster: Array = state.get("roster", [])
    for i in range(MAX_SLOTS):
        var row = _slot_rows[i]
        var slot_data: Dictionary = roster[i] if i < roster.size() else {}
        row["enabled"].button_pressed = bool(slot_data.get("enabled", i < roster.size()))
        row["name"].text = str(slot_data.get("name", "Slot%d" % (i + 1)))
        row["color"].color = slot_data.get("color", Color.WHITE)
        row["model"].text = str(slot_data.get("model", ""))
        row["timeout"].value = float(slot_data.get("timeout_sec", 0.0))
        row["script"].text = str(slot_data.get("script", ""))

    _rules_edit.text = _join_lines(state.get("rules_lines", []))
    _topics_edit.text = _join_lines(state.get("topic_lines", []))
    _angles_edit.text = _join_lines(state.get("angle_lines", []))
    _global_script_edit.text = str(state.get("global_script", ""))
    _turn_script_edit.text = str(state.get("turn_script", ""))

    _turn_interval_spin.value = float(state.get("turn_interval_sec", 5.0))
    _stall_timeout_spin.value = float(state.get("stall_timeout_sec", 30.0))
    _request_wait_buffer_spin.value = float(state.get("request_wait_buffer_sec", 10.0))
    _max_tokens_spin.value = int(state.get("max_tokens", 200))
    _temperature_spin.value = float(state.get("temperature", 0.75))
    _reasoner_timeout_spin.value = float(state.get("reasoner_timeout_sec", 60.0))
    _failure_limit_spin.value = int(state.get("failure_limit", 2))
    _failure_cooldown_spin.value = float(state.get("failure_cooldown_sec", 10.0))

    _event_min_spin.value = float(state.get("event_interval_min_sec", 45.0))
    _event_max_spin.value = float(state.get("event_interval_max_sec", 90.0))
    _doom_enabled_check.button_pressed = bool(state.get("doom_enabled", true))

    var event_map := {}
    for event_data in state.get("events", []):
        if typeof(event_data) == TYPE_DICTIONARY:
            event_map[str(event_data.get("type", ""))] = event_data
    for row in _event_rows:
        var event_data: Dictionary = event_map.get(row["type"], {})
        row["enabled"].button_pressed = bool(event_data.get("enabled", true))
        row["label"].text = str(event_data.get("label", str(row["type"]).replace("_", " ").to_upper()))

func build_payload() -> Dictionary:
    var roster := []
    for row in _slot_rows:
        roster.append({
            "enabled": row["enabled"].button_pressed,
            "name": row["name"].text.strip_edges(),
            "color": row["color"].color,
            "model": row["model"].text.strip_edges(),
            "timeout_sec": float(row["timeout"].value),
            "script": row["script"].text.strip_edges(),
        })

    var events := []
    for row in _event_rows:
        events.append({
            "type": row["type"],
            "enabled": row["enabled"].button_pressed,
            "label": row["label"].text.strip_edges(),
        })

    return {
        "roster": roster,
        "rules_lines": _split_lines(_rules_edit.text),
        "topic_lines": _split_lines(_topics_edit.text),
        "angle_lines": _split_lines(_angles_edit.text),
        "global_script": _global_script_edit.text.strip_edges(),
        "turn_script": _turn_script_edit.text.strip_edges(),
        "turn_interval_sec": float(_turn_interval_spin.value),
        "stall_timeout_sec": float(_stall_timeout_spin.value),
        "request_wait_buffer_sec": float(_request_wait_buffer_spin.value),
        "max_tokens": int(_max_tokens_spin.value),
        "temperature": float(_temperature_spin.value),
        "reasoner_timeout_sec": float(_reasoner_timeout_spin.value),
        "failure_limit": int(_failure_limit_spin.value),
        "failure_cooldown_sec": float(_failure_cooldown_spin.value),
        "event_interval_min_sec": float(_event_min_spin.value),
        "event_interval_max_sec": float(_event_max_spin.value),
        "doom_enabled": _doom_enabled_check.button_pressed,
        "events": events,
    }

func set_test_result(summary: String, response_text: String, success: bool = true) -> void:
    _test_status_label.text = summary
    _test_status_label.add_theme_color_override("font_color", Color(0.33, 0.85, 0.67) if success else Color(0.98, 0.52, 0.44))
    _test_response_edit.text = response_text

func _split_lines(text: String) -> Array:
    var lines := []
    for line in text.split("\n"):
        var cleaned = line.strip_edges()
        if not cleaned.is_empty():
            lines.append(cleaned)
    return lines

func _join_lines(lines: Array) -> String:
    var cleaned := []
    for line in lines:
        cleaned.append(str(line))
    return "\n".join(cleaned)
