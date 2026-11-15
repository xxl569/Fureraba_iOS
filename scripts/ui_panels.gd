class_name UiPanels
extends Control

## 主 UI 面板集合：对白框、QuickMenu、Save/Load、Config（含无码与透视开关）、
## 历史记录 Backlog 以及 BYOA 资产缺失引导浮层。

signal advance_requested()
signal auto_toggled(enabled: bool)
signal skip_toggled(enabled: bool)
signal save_slot_requested(slot: int)
signal load_slot_requested(slot: int)
signal config_changed()
signal rescan_byoa_requested()
signal start_new_game_requested()
signal play_op_requested()
signal choice_selected(index: int)
signal nude_quick_toggled()

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 12

var _cfg: ConfigManager
var _font: Font = null

# 对白框与 QuickMenu
var dialogue_panel: PanelContainer
var speaker_label: Label
var dialogue_label: RichTextLabel
var quick_menu: HBoxContainer
var btn_auto: Button
var btn_skip: Button
var btn_nude_quick: Button

# 标题 / 启动浮层
var title_overlay: PanelContainer

# 弹窗面板
var modal_backdrop: ColorRect
var save_load_panel: PanelContainer
var config_panel: PanelContainer
var log_panel: PanelContainer
var byoa_panel: PanelContainer
var choice_panel: PanelContainer
var choice_vbox: VBoxContainer
var byoa_label: Label
var log_text: RichTextLabel

var _is_save_mode: bool = true
var _slot_buttons: Array[Button] = []
var _backlog: Array[String] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dialogue_box()
	_build_quick_menu()
	_build_title_overlay()
	_build_modals()


func setup(cfg: ConfigManager, font: Font = null) -> void:
	_cfg = cfg
	_font = font
	if _font != null:
		speaker_label.add_theme_font_override("font", _font)
		dialogue_label.add_theme_font_override("normal_font", _font)
		log_text.add_theme_font_override("normal_font", _font)
	_sync_config_ui()


func show_byoa_guide(msg: String) -> void:
	byoa_label.text = msg
	byoa_panel.visible = true
	modal_backdrop.visible = true
	title_overlay.visible = false


func hide_byoa_guide() -> void:
	byoa_panel.visible = false
	if not save_load_panel.visible and not config_panel.visible and not log_panel.visible and not choice_panel.visible:
		modal_backdrop.visible = false


func show_title_menu(has_movie: bool) -> void:
	title_overlay.visible = true
	var op_btn := title_overlay.find_child("BtnPlayOp", true, false) as Button
	if op_btn != null:
		op_btn.visible = has_movie


func hide_title_menu() -> void:
	title_overlay.visible = false


func set_dialogue(text: String, speaker: String) -> void:
	dialogue_panel.visible = true
	speaker_label.visible = not speaker.is_empty()
	speaker_label.text = speaker
	dialogue_label.text = text
	var line := ("【%s】%s" % [speaker, text]) if not speaker.is_empty() else text
	_backlog.append(line)
	if _backlog.size() > 200:
		_backlog.remove_at(0)


func toggle_dialogue_visibility() -> void:
	dialogue_panel.visible = not dialogue_panel.visible


func update_nude_indicator(enabled: bool) -> void:
	if btn_nude_quick != null:
		btn_nude_quick.text = "透视:开" if enabled else "透视:关"


func set_auto_state(enabled: bool) -> void:
	if btn_auto != null:
		btn_auto.button_pressed = enabled


func set_skip_state(enabled: bool) -> void:
	if btn_skip != null:
		btn_skip.button_pressed = enabled


func show_choices(kind: String, options: Array) -> void:
	for c in choice_vbox.get_children():
		c.queue_free()
	var title := Label.new()
	var kind_label := "请选择对话分支"
	if kind == "SelectTalk":
		kind_label = "恋爱对话窗 (TalkWindow) - 请选择话题"
	elif kind == "SelectTopic":
		kind_label = "话题选择 (Topic)"
	elif kind == "SelectMail":
		kind_label = "手机短信 (Mail) - 请选择回复"
	title.text = kind_label
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_vbox.add_child(title)
	if options.is_empty():
		options = ["继续剧情"]
	for i in range(options.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(480, 56) # >=48pt 移动端安全触控热区
		b.text = str(options[i])
		var idx := i
		b.pressed.connect(func() -> void:
			choice_panel.visible = false
			modal_backdrop.visible = false
			choice_selected.emit(idx)
		)
		choice_vbox.add_child(b)
	choice_panel.visible = true
	modal_backdrop.visible = true


func has_open_modal() -> bool:
	return modal_backdrop.visible or title_overlay.visible


func open_log_panel() -> void:
	_open_log_panel()


func save_game_to_slot(slot: int, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


func load_game_from_slot(slot: int) -> Dictionary:
	var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _build_dialogue_box() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.anchor_left = 0.04
	dialogue_panel.anchor_right = 0.96
	dialogue_panel.anchor_top = 1.0
	dialogue_panel.anchor_bottom = 1.0
	dialogue_panel.offset_top = -205.0
	dialogue_panel.offset_bottom = -20.0
	dialogue_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.11, 0.84)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	dialogue_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialogue_panel.add_child(vbox)

	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 24)
	speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	vbox.add_child(speaker_label)

	dialogue_label = RichTextLabel.new()
	dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_label.add_theme_font_size_override("normal_font_size", 26)
	dialogue_label.fit_content = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(dialogue_label)

	dialogue_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			advance_requested.emit()
	)
	add_child(dialogue_panel)


func _build_quick_menu() -> void:
	quick_menu = HBoxContainer.new()
	quick_menu.name = "QuickMenu"
	quick_menu.anchor_left = 1.0
	quick_menu.anchor_right = 1.0
	quick_menu.offset_left = -640.0
	quick_menu.offset_top = 16.0
	quick_menu.offset_right = -24.0
	quick_menu.offset_bottom = 58.0
	quick_menu.alignment = BoxContainer.ALIGNMENT_END
	quick_menu.add_theme_constant_override("separation", 8)

	btn_auto = _make_btn("Auto", true)
	btn_auto.toggled.connect(func(on: bool) -> void: auto_toggled.emit(on))
	quick_menu.add_child(btn_auto)

	btn_skip = _make_btn("Skip", true)
	btn_skip.toggled.connect(func(on: bool) -> void: skip_toggled.emit(on))
	quick_menu.add_child(btn_skip)

	var btn_log := _make_btn("Log")
	btn_log.pressed.connect(_open_log_panel)
	quick_menu.add_child(btn_log)

	var btn_save := _make_btn("Save")
	btn_save.pressed.connect(func() -> void: _open_save_load(true))
	quick_menu.add_child(btn_save)

	var btn_load := _make_btn("Load")
	btn_load.pressed.connect(func() -> void: _open_save_load(false))
	quick_menu.add_child(btn_load)

	var btn_cfg := _make_btn("设置")
	btn_cfg.pressed.connect(_open_config_panel)
	quick_menu.add_child(btn_cfg)

	btn_nude_quick = _make_btn("透视:关")
	btn_nude_quick.pressed.connect(func() -> void: nude_quick_toggled.emit())
	quick_menu.add_child(btn_nude_quick)

	add_child(quick_menu)


func _build_title_overlay() -> void:
	title_overlay = PanelContainer.new()
	title_overlay.name = "TitleOverlay"
	title_overlay.anchor_left = 0.3
	title_overlay.anchor_right = 0.7
	title_overlay.anchor_top = 0.25
	title_overlay.anchor_bottom = 0.75
	title_overlay.visible = false

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	title_overlay.add_child(vb)

	var lbl := Label.new()
	lbl.text = "フレラバ 〜Friend to Lover〜 HD"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	vb.add_child(lbl)

	var btn_start := Button.new()
	btn_start.text = "开始新游戏 (Start)"
	btn_start.custom_minimum_size = Vector2(260, 52)
	btn_start.pressed.connect(func() -> void: start_new_game_requested.emit())
	vb.add_child(btn_start)

	var btn_load := Button.new()
	btn_load.text = "读取存档 (Load)"
	btn_load.custom_minimum_size = Vector2(260, 52)
	btn_load.pressed.connect(func() -> void: _open_save_load(false))
	vb.add_child(btn_load)

	var btn_op := Button.new()
	btn_op.name = "BtnPlayOp"
	btn_op.text = "播放开场动画 (OP)"
	btn_op.custom_minimum_size = Vector2(260, 48)
	btn_op.pressed.connect(func() -> void: play_op_requested.emit())
	vb.add_child(btn_op)

	var btn_cfg := Button.new()
	btn_cfg.text = "系统设置 (Config)"
	btn_cfg.custom_minimum_size = Vector2(260, 48)
	btn_cfg.pressed.connect(_open_config_panel)
	vb.add_child(btn_cfg)

	add_child(title_overlay)


func _build_modals() -> void:
	modal_backdrop = ColorRect.new()
	modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_backdrop.color = Color(0, 0, 0, 0.65)
	modal_backdrop.visible = false
	add_child(modal_backdrop)

	# 1. Save / Load
	save_load_panel = _make_modal_box("SaveLoadPanel", Vector2(720, 480))
	var sl_vb := VBoxContainer.new()
	save_load_panel.add_child(sl_vb)
	var sl_hdr := HBoxContainer.new()
	var sl_title := Label.new()
	sl_title.name = "Title"
	sl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_hdr.add_child(sl_title)
	var sl_close := _make_btn("关闭")
	sl_close.pressed.connect(_close_all_modals)
	sl_hdr.add_child(sl_close)
	sl_vb.add_child(sl_hdr)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	sl_vb.add_child(grid)
	for i in range(MAX_SLOTS):
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(320, 52)
		var slot_id := i
		sb.pressed.connect(func() -> void:
			_close_all_modals()
			if _is_save_mode:
				save_slot_requested.emit(slot_id)
			else:
				load_slot_requested.emit(slot_id)
		)
		grid.add_child(sb)
		_slot_buttons.append(sb)
	add_child(save_load_panel)

	# 2. Config
	config_panel = _make_modal_box("ConfigPanel", Vector2(640, 460))
	var cf_vb := VBoxContainer.new()
	cf_vb.add_theme_constant_override("separation", 12)
	config_panel.add_child(cf_vb)
	var cf_hdr := HBoxContainer.new()
	var cf_title := Label.new()
	cf_title.text = "系统设置"
	cf_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cf_hdr.add_child(cf_title)
	var cf_close := _make_btn("保存并关闭")
	cf_close.pressed.connect(func() -> void:
		if _cfg != null:
			_cfg.save_config()
		config_changed.emit()
		_close_all_modals()
	)
	cf_hdr.add_child(cf_close)
	cf_vb.add_child(cf_hdr)

	var chk_uncensored := CheckButton.new()
	chk_uncensored.name = "ChkUncensored"
	chk_uncensored.text = "启用无码补丁优先挂载 (data02150.arc.bak)"
	chk_uncensored.toggled.connect(func(on: bool) -> void:
		if _cfg != null:
			_cfg.uncensored_mode = on
	)
	cf_vb.add_child(chk_uncensored)

	var chk_nude := CheckButton.new()
	chk_nude.name = "ChkNude"
	chk_nude.text = "启用透视 / 全裸差分开关 (F12 / nudeprcs)"
	chk_nude.toggled.connect(func(on: bool) -> void:
		if _cfg != null:
			_cfg.nude_mode = on
	)
	cf_vb.add_child(chk_nude)

	var chk_skip := CheckButton.new()
	chk_skip.name = "ChkSkipUnread"
	chk_skip.text = "允许快进未读文本"
	chk_skip.toggled.connect(func(on: bool) -> void:
		if _cfg != null:
			_cfg.skip_unread = on
	)
	cf_vb.add_child(chk_skip)

	add_child(config_panel)

	# 3. Log
	log_panel = _make_modal_box("LogPanel", Vector2(800, 500))
	var lg_vb := VBoxContainer.new()
	log_panel.add_child(lg_vb)
	var lg_hdr := HBoxContainer.new()
	var lg_title := Label.new()
	lg_title.text = "对话历史 (Backlog)"
	lg_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lg_hdr.add_child(lg_title)
	var lg_close := _make_btn("关闭")
	lg_close.pressed.connect(_close_all_modals)
	lg_hdr.add_child(lg_close)
	lg_vb.add_child(lg_hdr)
	log_text = RichTextLabel.new()
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 20)
	lg_vb.add_child(log_text)
	add_child(log_panel)

	# 4. BYOA
	byoa_panel = _make_modal_box("ByoaPanel", Vector2(760, 460))
	var by_vb := VBoxContainer.new()
	by_vb.add_theme_constant_override("separation", 14)
	byoa_panel.add_child(by_vb)
	byoa_label = Label.new()
	byoa_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	byoa_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	by_vb.add_child(byoa_label)
	var btn_rescan := Button.new()
	btn_rescan.text = "重新扫描资产目录"
	btn_rescan.custom_minimum_size = Vector2(220, 48)
	btn_rescan.pressed.connect(func() -> void: rescan_byoa_requested.emit())
	by_vb.add_child(btn_rescan)
	add_child(byoa_panel)

	# 5. Choice
	choice_panel = _make_modal_box("ChoicePanel", Vector2(540, 360))
	choice_vbox = VBoxContainer.new()
	choice_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_vbox.add_theme_constant_override("separation", 12)
	choice_panel.add_child(choice_vbox)
	add_child(choice_panel)


func _make_modal_box(box_name: String, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = box_name
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -sz.x * 0.5
	p.offset_right = sz.x * 0.5
	p.offset_top = -sz.y * 0.5
	p.offset_bottom = sz.y * 0.5
	p.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.11, 0.16, 0.95)
	st.corner_radius_top_left = 12
	st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12
	st.corner_radius_bottom_right = 12
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", st)
	return p


func _make_btn(txt: String, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = txt
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(72, 36)
	return b


func _open_save_load(save_mode: bool) -> void:
	_is_save_mode = save_mode
	var ttl := save_load_panel.find_child("Title", true, false) as Label
	if ttl != null:
		ttl.text = "保存进度 (Save)" if save_mode else "读取进度 (Load)"
	for i in range(_slot_buttons.size()):
		var data := load_game_from_slot(i)
		if data.is_empty():
			_slot_buttons[i].text = "存档 %02d - [空]" % [i + 1]
		else:
			var sc := str(data.get("current_script", ""))
			var txt := str(data.get("last_dialogue_text", "")).left(14)
			_slot_buttons[i].text = "存档 %02d | %s | %s" % [i + 1, sc, txt]
	_close_all_modals()
	modal_backdrop.visible = true
	save_load_panel.visible = true


func _open_config_panel() -> void:
	_sync_config_ui()
	_close_all_modals()
	modal_backdrop.visible = true
	config_panel.visible = true


func _open_log_panel() -> void:
	log_text.text = "\n".join(_backlog)
	_close_all_modals()
	modal_backdrop.visible = true
	log_panel.visible = true


func _sync_config_ui() -> void:
	if _cfg == null:
		return
	var u := config_panel.find_child("ChkUncensored", true, false) as CheckButton
	if u != null:
		u.button_pressed = _cfg.uncensored_mode
	var n := config_panel.find_child("ChkNude", true, false) as CheckButton
	if n != null:
		n.button_pressed = _cfg.nude_mode
	var s := config_panel.find_child("ChkSkipUnread", true, false) as CheckButton
	if s != null:
		s.button_pressed = _cfg.skip_unread


func _close_all_modals() -> void:
	save_load_panel.visible = false
	config_panel.visible = false
	log_panel.visible = false
	choice_panel.visible = false
	modal_backdrop.visible = byoa_panel.visible
