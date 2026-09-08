extends Control
class_name BreachUI

## THE WATCHABLE LAYER. Built in code so the layout is diffable and the panels
## cannot drift from the data they render.
##
##  +-------------------------------------------------+---------------------+
##  | THE BREACH                    ROUND 01   08:43   | VANTA     E 71 K -- |
##  |                                                  | KESTREL   E 58 K B  |
##  |                 ARENA VIEWPORT                   | GEMMATRON E 82 K -- |
##  |                                                  | OZONIOUS  E 44 K A  |
##  |                                                  | BRINE     E 67 K C  |
##  |                                                  +---------------------+
##  |                                                  | VAULT  ##.  2 / 3   |
##  +-------------------------------------------------+---------------------+
##  | EVENT STREAM                                                          |
##  +------------------------------------------------------------------------+
##
## EVERY STRING IN THIS FILE IS MECHANICAL. There is no place that renders an
## interpretation: an event line is actor + verb + target, a status card is
## numbers, and the inspectors show stored fields verbatim. No timeline marker
## named BETRAYAL. Not now, not later.

const VaultScript := preload("res://scripts/breach/vault.gd")

signal agent_selected(display_name: String)
signal event_selected(event_id: int)
signal camera_mode_changed(mode: String)
signal replay_speed_changed(speed: float)

const CAMERA_DIRECTOR := "DIRECTOR"
const CAMERA_AGENT := "AGENT"
const CAMERA_GOD := "GOD"

const REPLAY_SPEEDS := [0.5, 1.0, 2.0, 5.0, 10.0]

var _round_label: Label
var _clock_label: Label
var _status_rows: Dictionary = {}      ## display_name -> Dictionary of Labels
var _vault_label: Label
var _event_list: ItemList
var _inspector: RichTextLabel
var _viewport_holder: SubViewportContainer
var _camera_mode: String = CAMERA_DIRECTOR
var _replay_speed: float = 1.0
var _paused: bool = false
var _followed_agent: String = ""
var _event_ids: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_header())

	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.split_offset = 900
	root.add_child(middle)

	_viewport_holder = SubViewportContainer.new()
	_viewport_holder.stretch = true
	_viewport_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(_viewport_holder)

	middle.add_child(_build_side_panel())

	var bottom := HSplitContainer.new()
	bottom.custom_minimum_size = Vector2(0, 240)
	root.add_child(bottom)
	bottom.add_child(_build_event_stream())
	bottom.add_child(_build_inspector())

	root.add_child(_build_replay_controls())


func _build_header() -> Control:
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "THE BREACH"
	bar.add_child(title)
	bar.add_child(_spacer())
	_round_label = Label.new()
	_round_label.text = "ROUND --"
	bar.add_child(_round_label)
	_clock_label = Label.new()
	_clock_label.text = "00:00"
	bar.add_child(_clock_label)
	return bar


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _build_side_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var hdr := Label.new()
	hdr.text = "AGENTS"
	panel.add_child(hdr)
	panel.add_child(HSeparator.new())
	_status_container = VBoxContainer.new()
	panel.add_child(_status_container)
	panel.add_child(HSeparator.new())
	_vault_label = Label.new()
	_vault_label.text = "VAULT  ...  0 / 3"
	panel.add_child(_vault_label)
	return panel


var _status_container: VBoxContainer


## One status card per agent. Energy and key letters only -- the panel shows
## what another agent could see plus the observer's privilege of exact numbers.
func build_status_cards(roster: Array) -> void:
	for child in _status_container.get_children():
		child.queue_free()
	_status_rows.clear()
	for r in roster:
		var d: Dictionary = r
		var nm := str(d["display_name"])
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = nm
		btn.custom_minimum_size = Vector2(120, 0)
		btn.pressed.connect(func() -> void:
			_followed_agent = nm
			agent_selected.emit(nm))
		row.add_child(btn)
		var energy := Label.new()
		energy.text = "E --"
		energy.custom_minimum_size = Vector2(70, 0)
		row.add_child(energy)
		var keys := Label.new()
		keys.text = "K --"
		row.add_child(keys)
		_status_container.add_child(row)
		_status_rows[nm] = {"energy": energy, "keys": keys}


func _build_event_stream() -> Control:
	var box := VBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "EVENT STREAM"
	box.add_child(hdr)
	_event_list = ItemList.new()
	_event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_list.item_selected.connect(func(idx: int) -> void:
		if idx >= 0 and idx < _event_ids.size():
			event_selected.emit(int(_event_ids[idx])))
	box.add_child(_event_list)
	return box


func _build_inspector() -> Control:
	var box := VBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "INSPECTOR"
	box.add_child(hdr)
	_inspector = RichTextLabel.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.bbcode_enabled = false
	box.add_child(_inspector)
	return box


func _build_replay_controls() -> Control:
	var bar := HBoxContainer.new()
	for mode in [CAMERA_DIRECTOR, CAMERA_AGENT, CAMERA_GOD]:
		var b := Button.new()
		b.text = mode
		b.pressed.connect(func() -> void:
			_camera_mode = mode
			camera_mode_changed.emit(mode))
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	var pause := Button.new()
	pause.text = "PAUSE"
	pause.pressed.connect(func() -> void:
		_paused = not _paused
		pause.text = "PLAY" if _paused else "PAUSE")
	bar.add_child(pause)
	var step := Button.new()
	step.text = "STEP"
	bar.add_child(step)
	bar.add_child(VSeparator.new())
	for sp in REPLAY_SPEEDS:
		var b := Button.new()
		b.text = "%sx" % str(sp)
		b.pressed.connect(func() -> void:
			_replay_speed = sp
			replay_speed_changed.emit(sp))
		bar.add_child(b)
	return bar


## --- rendering, all mechanical -------------------------------------------

func update_header(round_id: String, tick: int) -> void:
	_round_label.text = "ROUND %s" % round_id
	_clock_label.text = "%02d:%02d" % [int(tick / 60), tick % 60]


func update_agents(agents: Dictionary) -> void:
	for nm in _status_rows.keys():
		if not agents.has(nm):
			continue
		var a = agents[nm]
		var row: Dictionary = _status_rows[nm]
		(row["energy"] as Label).text = "E %d" % a.energy
		var keys := a.keys_held()
		var letters := ""
		for k in keys:
			letters += str(k).replace("key_", "")
		(row["keys"] as Label).text = "K %s" % (letters if not letters.is_empty() else "--")


func update_vault(world) -> void:
	_vault_label.text = "VAULT  " + VaultScript.bar(world)


func append_event(ev_dict: Dictionary, line: String) -> void:
	_event_list.add_item(line)
	_event_ids.append(int(ev_dict.get("event_id", -1)))
	_event_list.ensure_current_is_visible()


## Agent inspector: stored fields verbatim, including the agent's own memory in
## its own words. No derived scores.
func show_agent(agent) -> void:
	var lines: Array = []
	lines.append(agent.display_name)
	lines.append("")
	lines.append("MODEL        %s" % agent.model_id)
	lines.append("SPECIES      %s" % agent.species_id)
	lines.append("INSTANCE     %s" % agent.instance_id)
	lines.append("ENERGY       %d" % agent.energy)
	lines.append("POSITION     %s" % agent.position)
	lines.append("INVENTORY    %s" % ", ".join(agent.inventory))
	lines.append("")
	lines.append("MEMORY (%d/%d)" % [agent.memory.size(), agent.memory.MAX_ENTRIES])
	for m in agent.memory.as_lines():
		var d: Dictionary = m
		lines.append("  %d. %s" % [int(d["index"]) + 1, str(d["text"])])
	_inspector.text = "\n".join(lines)


## Event inspector: the full provenance record. This is the click-through that
## makes the round falsifiable rather than merely watchable.
func show_event(ev: Dictionary) -> void:
	var lines: Array = []
	lines.append("EVENT %d" % int(ev.get("event_id", -1)))
	lines.append("")
	lines.append("TICK             %d" % int(ev.get("tick", 0)))
	lines.append("ACTOR            %s" % str(ev.get("actor", "")))
	lines.append("MODEL            %s" % str(ev.get("model_id", "")))
	lines.append("INSTANCE         %s" % str(ev.get("instance_id", "")))
	lines.append("REGIME           %s" % str(ev.get("population_regime_id", "")))
	lines.append("OPERATION        %s" % str(ev.get("operation", "")))
	lines.append("FIELDS           %s" % JSON.stringify(ev.get("fields", {})))
	lines.append("ACCEPTED         %s" % str(ev.get("accepted", false)))
	if not str(ev.get("refusal_reason", "")).is_empty():
		lines.append("REFUSED          %s" % str(ev.get("refusal_reason", "")))
	if not str(ev.get("parse_failure", "")).is_empty():
		lines.append("PARSE FAILURE    %s" % str(ev.get("parse_failure", "")))
		lines.append("PARSE DETAIL     %s" % str(ev.get("parse_detail", "")))
	lines.append("OBSERVATION HASH %s" % str(ev.get("observation_hash", "")))
	lines.append("BEFORE HASH      %s" % str(ev.get("before_state_hash", "")))
	lines.append("AFTER HASH       %s" % str(ev.get("after_state_hash", "")))
	lines.append("INITIATIVE       %s" % JSON.stringify(ev.get("initiative", {})))
	lines.append("LATENCY MS       %d" % int(ev.get("latency_ms", -1)))
	lines.append("")
	lines.append("RAW MODEL OUTPUT")
	lines.append(str(ev.get("raw_output", "")))
	_inspector.text = "\n".join(lines)


func camera_mode() -> String:
	return _camera_mode


func followed_agent() -> String:
	return _followed_agent


func replay_speed() -> float:
	return _replay_speed


func is_paused() -> bool:
	return _paused
