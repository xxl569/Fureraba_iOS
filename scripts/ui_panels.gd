class_name UiPanels
extends Control

## 主 UI 面板集合（1280x720 逻辑坐标系）：
## 1. 标题界面（运行时提取 sgtitle* 贴图，含 5 按钮与底部 Help 提示栏）
## 2. 对白框与右下角快捷控制（sgmsgwnd* 贴图、打字机逐字显示、AUTO/SKIP 指示角标、Q.S/Q.L/LOG/透视）
## 3. 一体化系统菜单与 100 槽位存档/读档（sgsyswnd* / sgusdtwnd*，含缩略图截图与实时设置预览）
## 4. 历史记录 Backlog（sglogwnd*，支持单句语音重播与 Quick Jump）
## 5. 原版确认弹窗（sgdialog*）、选择支（sgslctwnd* / SMEE TalkWindow）与附录 CG/BGM 鉴赏

signal advance_requested()
signal auto_toggled(enabled: bool)
signal skip_toggled(enabled: bool)
signal save_slot_requested(slot: int)
signal load_slot_requested(slot: int)
signal config_changed()
signal rescan_byoa_requested()
signal start_new_game_requested()
signal new_game_confirmed(skip_prologue: bool, family_name: String, given_name: String)
signal play_op_requested()
signal choice_selected(index: int)
signal nude_quick_toggled()
signal quick_save_requested()
signal quick_load_requested()
signal voice_replay_requested(voice_entry: String)
signal quick_jump_requested(snapshot: Dictionary)
signal return_to_title_requested()
signal quit_game_requested()
signal gallery_play_bgm_requested(bgm_entry: String)
signal gallery_stop_bgm_requested()

const _ThemeLoader := preload("res://scripts/ui_theme_loader.gd")
const _GalleryPanel := preload("res://scripts/ui_gallery_panel.gd")

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 12 # 兼容旧接口：单页内最小槽位常量，实际支持 10 页 x 10 槽位 (0..99)
const TOTAL_SLOTS := 100
const SLOTS_PER_PAGE := 10
const QUICK_SAVE_SLOT := 99

var _cfg: ConfigManager
var _font: Font = null
var _vfs: BgiVfs = null
var theme_loader: _ThemeLoader = _ThemeLoader.new()

# 对白框与快捷控制
var dialogue_panel: Control
var _msg_bg_rect: TextureRect
var _msg_fallback_bg: Panel
var _name_plate: Control
var _name_bg_rect: TextureRect
var speaker_label: Label
var dialogue_label: RichTextLabel
var quick_menu: Control
var btn_auto: BaseButton
var btn_skip: BaseButton
var btn_nude_quick: Button
var _auto_badge: TextureRect
var _skip_badge: TextureRect
var _badge_fallback: Label

# 打字机状态
var _typing_active: bool = false
var _typing_accum: float = 0.0
var _typing_total_chars: int = 0

# 标题界面
var title_overlay: Control
var _title_bg_rect: TextureRect
var _title_help_rect: TextureRect
var _title_help_label: Label
var _title_op_btn: Button

# 弹窗与系统菜单
var modal_backdrop: ColorRect
var sys_menu_panel: Control
var save_load_panel: Control
var config_panel: Control
var log_panel: Control
var byoa_panel: PanelContainer
var choice_panel: PanelContainer
var choice_vbox: VBoxContainer
var byoa_label: Label
var log_text: RichTextLabel
var gallery_panel: Control

# 系统菜单子页面与控件引用
var _sys_nav_buttons: Array[Button] = []
var _sys_pages: Dictionary = {} # page_key -> Control
var _sys_help_rect: TextureRect
var _sys_help_label: Label
var _sys_in_game: bool = false

# 存档/读档控件
var _is_save_mode: bool = true
var _current_save_page: int = 0
var _selected_slot: int = 0
var _save_bg_rect: TextureRect
var _save_page_cover: ColorRect
var _save_title_lbl: Label
var _page_buttons: Array[Button] = []
var _slot_buttons: Array[Button] = []
var _slot_thumbs: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _preview_thumb: TextureRect
var _preview_info: Label
var _preview_action_btn: Button

# 新游戏姓名输入与序章跳过弹窗
var _name_input_overlay: Control
var _family_input: LineEdit
var _given_input: LineEdit
var _prologue_skip_overlay: Control

# Config 控件引用
var _chk_uncensored: CheckButton
var _chk_nude: CheckButton
var _chk_skip_unread: CheckButton
var _chk_confirm: CheckButton
var _sld_text_speed: HSlider
var _lbl_text_speed: Label
var _sld_auto_delay: HSlider
var _lbl_auto_delay: Label
var _sld_opacity: HSlider
var _lbl_opacity: Label
var _preview_msg_box: ColorRect
var _sld_bgm: HSlider
var _lbl_bgm: Label
var _sld_se: HSlider
var _lbl_se: Label
var _sld_voice: HSlider
var _lbl_voice: Label

# Log 控件与数据
var _log_list_vbox: VBoxContainer
var _backlog: Array[Dictionary] = [] # {speaker, text, voice_entry, snapshot}

# 确认弹窗
var _confirm_overlay: Control
var _confirm_bg_rect: TextureRect
var _confirm_msg_lbl: Label
var _confirm_yes_btn: TextureButton
var _confirm_no_btn: TextureButton
var _confirm_callback: Callable = Callable()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 300 # 必须高于 BgiStage 的 256 个图元层 (z_index 0..255)
	_build_dialogue_box()
	_build_quick_menu()
	_build_title_overlay()
	_build_modals()


func _process(delta: float) -> void:
	if not _typing_active:
		return
	var speed := _cfg.text_speed if _cfg != null else 60.0
	if speed <= 0.0:
		finish_typing()
		return
	_typing_accum += delta * speed
	var vis := int(_typing_accum)
	if vis >= _typing_total_chars:
		finish_typing()
	else:
		dialogue_label.visible_characters = vis


func setup(cfg: ConfigManager, font: Font = null, vfs: BgiVfs = null) -> void:
	_cfg = cfg
	_font = font
	_vfs = vfs
	theme_loader.setup(_vfs)

	if _font != null:
		speaker_label.add_theme_font_override("font", _font)
		dialogue_label.add_theme_font_override("normal_font", _font)
		log_text.add_theme_font_override("normal_font", _font)

	_apply_runtime_textures()
	if gallery_panel != null:
		gallery_panel.setup(theme_loader, _vfs, _font)
	_sync_config_ui()
	_apply_dialogue_opacity()


func _apply_runtime_textures() -> void:
	if not theme_loader.has_vfs():
		return
	# 标题界面贴图
	var t_title_bg := theme_loader.get_tex("sgtitle990000")
	if t_title_bg != null:
		_title_bg_rect.texture = t_title_bg
	for i in range(5):
		var btn := title_overlay.find_child("TitleBtn_%d" % i, true, false) as TextureButton
		if btn != null:
			theme_loader.apply_button_textures(btn, "sgtitle000%d00" % i, "sgtitle000%d01" % i, "sgtitle000%d01" % i)
			for c in btn.get_children():
				if c is Label:
					c.visible = (btn.texture_normal == null)

	# 对白框贴图
	var t_msg := theme_loader.get_tex("sgmsgwnd990000")
	if t_msg != null:
		_msg_bg_rect.texture = t_msg
		_msg_bg_rect.visible = true
		_msg_fallback_bg.visible = false
	var t_name := theme_loader.get_tex("sgmsgwnd900000")
	if t_name != null:
		_name_bg_rect.texture = t_name
		_name_bg_rect.visible = true
	var t_auto := theme_loader.get_tex("sgmsgwnd500000")
	if t_auto != null:
		_auto_badge.texture = t_auto
	var t_skip := theme_loader.get_tex("sgmsgwnd500100")
	if t_skip != null:
		_skip_badge.texture = t_skip

	# 右下角快捷按钮贴图
	var quick_tex_map := {
		"BtnVoiceReplay": ["sgmsgwnd000200", "sgmsgwnd000201"],
		"BtnAuto": ["sgmsgwnd000000", "sgmsgwnd000001"],
		"BtnSkip": ["sgmsgwnd000100", "sgmsgwnd000101"],
		"BtnHideUi": ["sgmsgwnd000300", "sgmsgwnd000301"],
		"BtnSysCfg": ["sgmsgwnd000600", "sgmsgwnd000601"],
	}
	for k in quick_tex_map.keys():
		var qb := quick_menu.find_child(k, true, false) as TextureButton
		if qb != null:
			var pair: Array = quick_tex_map[k]
			theme_loader.apply_button_textures(qb, pair[0], pair[1], pair[1])
			for c in qb.get_children():
				if c is Label:
					c.visible = (qb.texture_normal == null)

	# Log 背景贴图
	var log_bg := log_panel.find_child("LogBgRect", true, false) as TextureRect
	if log_bg != null:
		var t_log := theme_loader.get_tex("sglogwnd990000")
		if t_log != null:
			log_bg.texture = t_log
	var log_close := log_panel.find_child("LogCloseBtn", true, false) as Button
	if log_close != null:
		pass

	# 确认弹窗 是/否 贴图
	theme_loader.apply_button_textures(_confirm_yes_btn, "sgdialog000000", "sgdialog000001", "sgdialog000001")
	theme_loader.apply_button_textures(_confirm_no_btn, "sgdialog000100", "sgdialog000101", "sgdialog000101")
	for b in [_confirm_yes_btn, _confirm_no_btn]:
		for c in b.get_children():
			if c is Label:
				c.visible = (b.texture_normal == null)


func show_byoa_guide(msg: String) -> void:
	byoa_label.text = msg
	byoa_panel.visible = true
	modal_backdrop.visible = true
	title_overlay.visible = false


func hide_byoa_guide() -> void:
	byoa_panel.visible = false
	_refresh_backdrop()


func show_title_menu(has_movie: bool) -> void:
	_sys_in_game = false
	dialogue_panel.visible = false
	quick_menu.visible = false
	_auto_badge.visible = false
	_skip_badge.visible = false
	_badge_fallback.visible = false
	title_overlay.visible = true
	if _title_op_btn != null:
		_title_op_btn.visible = has_movie


func hide_title_menu() -> void:
	title_overlay.visible = false
	_sys_in_game = true
	quick_menu.visible = true


func set_dialogue(text: String, speaker: String, voice_entry: String = "", snapshot: Dictionary = {}) -> void:
	dialogue_panel.visible = true
	quick_menu.visible = true
	_name_plate.visible = not speaker.is_empty()
	speaker_label.visible = not speaker.is_empty()
	speaker_label.text = speaker
	dialogue_label.text = text

	# 打字机初始化（无头测试或瞬间显示模式下立即显示全文）
	_typing_total_chars = dialogue_label.get_total_character_count()
	if _typing_total_chars <= 0:
		_typing_total_chars = text.length()
	var speed := _cfg.text_speed if _cfg != null else 60.0
	if DisplayServer.get_name() == "headless" or speed <= 0.0:
		dialogue_label.visible_characters = -1
		_typing_active = false
	else:
		dialogue_label.visible_characters = 0
		_typing_accum = 0.0
		_typing_active = true

	var line := ("【%s】%s" % [speaker, text]) if not speaker.is_empty() else text
	_backlog.append({
		"speaker": speaker,
		"text": text,
		"line": line,
		"voice_entry": voice_entry,
		"snapshot": snapshot.duplicate(true) if not snapshot.is_empty() else {},
	})
	if _backlog.size() > 200:
		_backlog.remove_at(0)


func is_typing() -> bool:
	return _typing_active


func finish_typing() -> void:
	_typing_active = false
	dialogue_label.visible_characters = -1


func toggle_dialogue_visibility() -> void:
	dialogue_panel.visible = not dialogue_panel.visible
	quick_menu.visible = dialogue_panel.visible


func update_nude_indicator(enabled: bool) -> void:
	if btn_nude_quick != null:
		btn_nude_quick.text = "F12 透视:开" if enabled else "F12 透视:关"
		btn_nude_quick.button_pressed = enabled
	if _chk_nude != null:
		_chk_nude.button_pressed = enabled


func set_auto_state(enabled: bool) -> void:
	if btn_auto != null:
		btn_auto.button_pressed = enabled
	_auto_badge.visible = enabled
	_update_badge_fallback()


func set_skip_state(enabled: bool) -> void:
	if btn_skip != null:
		btn_skip.button_pressed = enabled
	_skip_badge.visible = enabled
	_update_badge_fallback()


func _update_badge_fallback() -> void:
	if _auto_badge.visible and _auto_badge.texture == null:
		_badge_fallback.text = "▶ AUTO"
		_badge_fallback.visible = true
	elif _skip_badge.visible and _skip_badge.texture == null:
		_badge_fallback.text = "▶▶ SKIP"
		_badge_fallback.visible = true
	else:
		_badge_fallback.visible = false


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
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	choice_vbox.add_child(title)

	if options.is_empty():
		options = ["继续剧情"]
	var slct_tex := theme_loader.get_tex("sgslctwnd990000")
	for i in range(options.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(560, 58) # >=48pt 移动端安全触控热区
		b.text = str(options[i])
		b.add_theme_font_size_override("font_size", 22)
		if slct_tex != null and kind == "Choice":
			var st := StyleBoxTexture.new()
			st.texture = slct_tex
			b.add_theme_stylebox_override("normal", st)
			b.add_theme_stylebox_override("hover", st)
			b.add_theme_stylebox_override("pressed", st)
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			var st_flat := StyleBoxFlat.new()
			st_flat.bg_color = Color(0.16, 0.54, 0.92, 0.92)
			st_flat.border_color = Color(0.85, 0.94, 1.0, 0.95)
			st_flat.set_border_width_all(2)
			st_flat.set_corner_radius_all(14)
			b.add_theme_stylebox_override("normal", st_flat)
			var st_h := st_flat.duplicate() as StyleBoxFlat
			st_h.bg_color = Color(0.28, 0.68, 1.0, 0.98)
			b.add_theme_stylebox_override("hover", st_h)
			b.add_theme_stylebox_override("pressed", st_h)
			b.add_theme_color_override("font_color", Color.WHITE)
		var idx := i
		b.pressed.connect(func() -> void:
			choice_panel.visible = false
			_refresh_backdrop()
			choice_selected.emit(idx)
		)
		choice_vbox.add_child(b)
	choice_panel.visible = true
	modal_backdrop.visible = true


func has_open_modal() -> bool:
	return (
		modal_backdrop.visible
		or title_overlay.visible
		or sys_menu_panel.visible
		or log_panel.visible
		or gallery_panel.visible
		or _confirm_overlay.visible
		or (_name_input_overlay != null and _name_input_overlay.visible)
		or (_prologue_skip_overlay != null and _prologue_skip_overlay.visible)
	)


func open_log_panel() -> void:
	_open_log_panel()


func open_system_menu(page_key: String = "display", in_game: bool = true) -> void:
	_sys_in_game = in_game
	_close_all_modals()
	_sync_config_ui()
	_refresh_sys_nav_state()
	_switch_sys_page(page_key)
	sys_menu_panel.visible = true
	modal_backdrop.visible = true


func show_confirm(dialog_tex_entry: String, fallback_msg: String, on_yes: Callable) -> void:
	if _cfg != null and not _cfg.confirm_dialogs:
		on_yes.call()
		return
	_confirm_callback = on_yes
	var t := theme_loader.get_tex(dialog_tex_entry)
	if t != null:
		_confirm_bg_rect.texture = t
		_confirm_bg_rect.visible = true
		_confirm_msg_lbl.visible = false
	else:
		_confirm_bg_rect.visible = false
		_confirm_msg_lbl.text = fallback_msg
		_confirm_msg_lbl.visible = true
	_confirm_overlay.visible = true
	modal_backdrop.visible = true


func save_game_to_slot(slot: int, payload: Dictionary, shot_img: Image = null) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if shot_img != null:
		var thumb := shot_img.duplicate() as Image
		thumb.resize(256, 144, Image.INTERPOLATE_BILINEAR)
		var shot_path := "%s/shot_%02d.png" % [SAVE_DIR, slot]
		thumb.save_png(shot_path)
		payload["shot_path"] = shot_path
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
	dialogue_panel = Control.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.visible = false

	# 底部对白框背景图 (1280x240)
	_msg_bg_rect = TextureRect.new()
	_msg_bg_rect.position = Vector2(0, 480)
	_msg_bg_rect.size = Vector2(1280, 240)
	_msg_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_msg_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_msg_bg_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_msg_bg_rect.visible = false
	dialogue_panel.add_child(_msg_bg_rect)

	# 兜底渐变蓝框
	_msg_fallback_bg = Panel.new()
	_msg_fallback_bg.position = Vector2(24, 510)
	_msg_fallback_bg.size = Vector2(1232, 194)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.34, 0.68, 0.86)
	st.border_color = Color(0.75, 0.9, 1.0, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(18)
	_msg_fallback_bg.add_theme_stylebox_override("panel", st)
	dialogue_panel.add_child(_msg_fallback_bg)

	# 姓名栏 (270x40)
	_name_plate = Control.new()
	_name_plate.position = Vector2(54, 480)
	_name_plate.size = Vector2(270, 40)
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.add_child(_name_plate)

	_name_bg_rect = TextureRect.new()
	_name_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_name_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_name_bg_rect.visible = false
	_name_plate.add_child(_name_bg_rect)

	speaker_label = Label.new()
	speaker_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.add_theme_font_size_override("font_size", 22)
	speaker_label.add_theme_color_override("font_color", Color.WHITE)
	speaker_label.add_theme_color_override("font_outline_color", Color(0.05, 0.16, 0.38, 0.95))
	speaker_label.add_theme_constant_override("outline_size", 2)
	speaker_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.12, 0.3, 0.9))
	speaker_label.add_theme_constant_override("shadow_offset_x", 1)
	speaker_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_plate.add_child(speaker_label)

	# 对白正文区
	dialogue_label = RichTextLabel.new()
	dialogue_label.position = Vector2(86, 530)
	dialogue_label.size = Vector2(900, 168)
	dialogue_label.add_theme_font_size_override("normal_font_size", 26)
	dialogue_label.add_theme_color_override("default_color", Color.WHITE)
	dialogue_label.add_theme_color_override("font_outline_color", Color(0.04, 0.14, 0.34, 0.92))
	dialogue_label.add_theme_constant_override("outline_size", 2)
	dialogue_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.1, 0.25, 0.95))
	dialogue_label.add_theme_constant_override("shadow_offset_x", 1)
	dialogue_label.add_theme_constant_override("shadow_offset_y", 2)
	dialogue_label.fit_content = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.add_child(dialogue_label)

	var click_handler := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				advance_requested.emit()
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				toggle_dialogue_visibility()
	_msg_bg_rect.gui_input.connect(click_handler)
	_msg_fallback_bg.gui_input.connect(click_handler)

	add_child(dialogue_panel)

	# 右上角 AUTO / SKIP 模式角标
	_auto_badge = TextureRect.new()
	_auto_badge.position = Vector2(1092, 14)
	_auto_badge.size = Vector2(173, 90)
	_auto_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_auto_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_auto_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto_badge.visible = false
	add_child(_auto_badge)

	_skip_badge = TextureRect.new()
	_skip_badge.position = Vector2(1092, 14)
	_skip_badge.size = Vector2(173, 90)
	_skip_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skip_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skip_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_badge.visible = false
	add_child(_skip_badge)

	_badge_fallback = Label.new()
	_badge_fallback.position = Vector2(1110, 24)
	_badge_fallback.size = Vector2(140, 40)
	_badge_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_fallback.add_theme_font_size_override("font_size", 20)
	_badge_fallback.add_theme_color_override("font_color", Color.WHITE)
	_badge_fallback.visible = false
	add_child(_badge_fallback)


func _build_quick_menu() -> void:
	# 右下角原版两排快捷控制区
	quick_menu = Control.new()
	quick_menu.name = "QuickMenu"
	quick_menu.position = Vector2(1002, 552)
	quick_menu.size = Vector2(266, 158)
	quick_menu.visible = false
	add_child(quick_menu)

	var row1 := HBoxContainer.new()
	row1.position = Vector2(0, 0)
	row1.size = Vector2(266, 46)
	row1.alignment = BoxContainer.ALIGNMENT_END
	row1.add_theme_constant_override("separation", 6)
	quick_menu.add_child(row1)

	var btn_rep := _make_round_icon_btn("BtnVoiceReplay", "◀")
	btn_rep.tooltip_text = "重播当前语音 (R)"
	btn_rep.pressed.connect(func() -> void: voice_replay_requested.emit(""))
	row1.add_child(btn_rep)

	var b_auto := _make_round_icon_btn("BtnAuto", "▶", true)
	b_auto.tooltip_text = "自动模式 (A)"
	b_auto.toggled.connect(func(on: bool) -> void: auto_toggled.emit(on))
	row1.add_child(b_auto)
	btn_auto = b_auto

	var b_skip := _make_round_icon_btn("BtnSkip", "▶▶", true)
	b_skip.tooltip_text = "快进模式 (Space)"
	b_skip.toggled.connect(func(on: bool) -> void: skip_toggled.emit(on))
	row1.add_child(b_skip)
	btn_skip = b_skip

	var btn_hide := _make_round_icon_btn("BtnHideUi", "✕")
	btn_hide.tooltip_text = "隐藏对白框 (H / 右键)"
	btn_hide.pressed.connect(toggle_dialogue_visibility)
	row1.add_child(btn_hide)

	var btn_cfg := _make_round_icon_btn("BtnSysCfg", "⚙")
	btn_cfg.tooltip_text = "系统菜单 (Esc)"
	btn_cfg.pressed.connect(func() -> void: open_system_menu("display", _sys_in_game))
	row1.add_child(btn_cfg)

	var row2 := HBoxContainer.new()
	row2.position = Vector2(0, 54)
	row2.size = Vector2(266, 40)
	row2.alignment = BoxContainer.ALIGNMENT_END
	row2.add_theme_constant_override("separation", 8)
	quick_menu.add_child(row2)

	var btn_log := _make_pill_btn("LOG", Vector2(74, 36))
	btn_log.pressed.connect(_open_log_panel)
	row2.add_child(btn_log)

	var btn_qs := _make_pill_btn("Q.S", Vector2(68, 36))
	btn_qs.pressed.connect(func() -> void:
		show_confirm("sgdialog990005", "确定快速存档吗？", func() -> void: quick_save_requested.emit())
	)
	row2.add_child(btn_qs)

	var btn_ql := _make_pill_btn("Q.L", Vector2(68, 36))
	btn_ql.pressed.connect(func() -> void:
		show_confirm("sgdialog990006", "确定快速读档吗？", func() -> void: quick_load_requested.emit())
	)
	row2.add_child(btn_ql)

	var row3 := HBoxContainer.new()
	row3.position = Vector2(0, 102)
	row3.size = Vector2(266, 38)
	row3.alignment = BoxContainer.ALIGNMENT_END
	quick_menu.add_child(row3)

	btn_nude_quick = _make_pill_btn("F12 透视:关", Vector2(138, 34), true)
	btn_nude_quick.pressed.connect(func() -> void: nude_quick_toggled.emit())
	row3.add_child(btn_nude_quick)


func _make_round_icon_btn(node_name: String, fallback_txt: String, toggle: bool = false) -> TextureButton:
	var b := TextureButton.new()
	b.name = node_name
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(44, 44)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var lbl := Label.new()
	lbl.text = fallback_txt
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	b.add_child(lbl)
	return b


func _make_pill_btn(txt: String, sz: Vector2, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = txt
	b.toggle_mode = toggle
	b.custom_minimum_size = sz
	b.add_theme_font_size_override("font_size", 15)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.15, 0.45, 0.78, 0.85)
	st.border_color = Color(0.85, 0.95, 1.0, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", st)
	var st_h := st.duplicate() as StyleBoxFlat
	st_h.bg_color = Color(0.28, 0.65, 0.98, 0.96)
	b.add_theme_stylebox_override("hover", st_h)
	b.add_theme_stylebox_override("pressed", st_h)
	b.add_theme_color_override("font_color", Color.WHITE)
	return b


func _build_title_overlay() -> void:
	title_overlay = Control.new()
	title_overlay.name = "TitleOverlay"
	title_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_overlay.visible = false
	add_child(title_overlay)

	var fallback_bg := ColorRect.new()
	fallback_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback_bg.color = Color(0.98, 0.86, 0.91, 1.0)
	title_overlay.add_child(fallback_bg)

	_title_bg_rect = TextureRect.new()
	_title_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	title_overlay.add_child(_title_bg_rect)

	# 5 个横向主按钮 (220x70)，对齐原版位置不遮挡 HD Renewal Edition
	var btn_row := HBoxContainer.new()
	btn_row.position = Vector2(56, 348)
	btn_row.size = Vector2(1168, 74)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	title_overlay.add_child(btn_row)

	var title_items := [
		{"text": "从头开始", "help": "从头开始游戏。"},
		{"text": "继续游戏", "help": "从保存的进度继续游戏。"},
		{"text": "系统", "help": "进入系统设置画面。"},
		{"text": "附录", "help": "进入 CG・回想与音乐鉴赏。"},
		{"text": "结束游戏", "help": "结束当前游戏。"},
	]
	for i in range(title_items.size()):
		var tb := TextureButton.new()
		tb.name = "TitleBtn_%d" % i
		tb.custom_minimum_size = Vector2(220, 70)
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var lbl := Label.new()
		lbl.text = str(title_items[i]["text"])
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.45))
		tb.add_child(lbl)

		var idx := i
		var help_str := str(title_items[i]["help"])
		tb.mouse_entered.connect(func() -> void: _set_title_help(idx, help_str))
		tb.focus_entered.connect(func() -> void: _set_title_help(idx, help_str))
		tb.pressed.connect(func() -> void: _on_title_btn_pressed(idx))
		btn_row.add_child(tb)

	# 底部 Help 栏（居中圆角白底粉框）
	var help_box := PanelContainer.new()
	help_box.position = Vector2(260, 462)
	help_box.size = Vector2(760, 50)
	var hst := StyleBoxFlat.new()
	hst.bg_color = Color(1.0, 1.0, 1.0, 0.94)
	hst.border_color = Color(0.95, 0.56, 0.72, 0.95)
	hst.set_border_width_all(2)
	hst.set_corner_radius_all(22)
	help_box.add_theme_stylebox_override("panel", hst)
	title_overlay.add_child(help_box)

	var h_hb := HBoxContainer.new()
	h_hb.add_theme_constant_override("separation", 12)
	help_box.add_child(h_hb)

	var h_tag := Label.new()
	h_tag.text = "  Help: "
	h_tag.add_theme_font_size_override("font_size", 20)
	h_tag.add_theme_color_override("font_color", Color(0.92, 0.35, 0.58))
	h_hb.add_child(h_tag)

	_title_help_rect = TextureRect.new()
	_title_help_rect.custom_minimum_size = Vector2(620, 40)
	_title_help_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_help_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h_hb.add_child(_title_help_rect)

	_title_help_label = Label.new()
	_title_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_help_label.add_theme_font_size_override("font_size", 18)
	_title_help_label.add_theme_color_override("font_color", Color(0.45, 0.25, 0.35))
	_title_help_label.text = "请选择游戏模式。"
	h_hb.add_child(_title_help_label)

	# 标题右上角快捷播放 OP 入口
	_title_op_btn = _make_pill_btn("🎬 播放 OP 动画", Vector2(160, 38))
	_title_op_btn.name = "BtnPlayOp"
	_title_op_btn.position = Vector2(1096, 18)
	_title_op_btn.pressed.connect(func() -> void: play_op_requested.emit())
	title_overlay.add_child(_title_op_btn)


func _set_title_help(idx: int, fallback: String) -> void:
	var t := theme_loader.get_tex("sgtitle800%d00" % idx)
	if t != null:
		_title_help_rect.texture = t
		_title_help_rect.visible = true
		_title_help_label.visible = false
	else:
		_title_help_rect.visible = false
		_title_help_label.text = fallback
		_title_help_label.visible = true


func _on_title_btn_pressed(idx: int) -> void:
	match idx:
		0: # 从头开始（进入原版姓名输入与序章跳过流程）
			_open_new_game_flow()
		1: # 继续游戏 (读档)
			open_system_menu("load", false)
		2: # 系统
			open_system_menu("display", false)
		3: # 附录
			if gallery_panel != null:
				gallery_panel.open_gallery(_title_op_btn != null and _title_op_btn.visible)
		4: # 结束游戏
			show_confirm("sgdialog990000", "确定结束游戏?", func() -> void: quit_game_requested.emit())


func _open_new_game_flow() -> void:
	if _name_input_overlay != null:
		_name_input_overlay.visible = true
		modal_backdrop.visible = true
	else:
		start_new_game_requested.emit()


func _build_modals() -> void:
	modal_backdrop = ColorRect.new()
	modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_backdrop.color = Color(0, 0, 0, 0.55)
	modal_backdrop.visible = false
	add_child(modal_backdrop)

	_build_system_menu()
	_build_log_panel()
	_build_byoa_panel()
	_build_choice_panel()
	_build_new_game_overlays()

	gallery_panel = _GalleryPanel.new()
	gallery_panel.name = "GalleryPanel"
	gallery_panel.play_bgm_requested.connect(func(e: String) -> void: gallery_play_bgm_requested.emit(e))
	gallery_panel.stop_bgm_requested.connect(func() -> void: gallery_stop_bgm_requested.emit())
	gallery_panel.play_op_requested.connect(func() -> void: play_op_requested.emit())
	add_child(gallery_panel)

	_build_confirm_dialog()


func _build_system_menu() -> void:
	sys_menu_panel = Control.new()
	sys_menu_panel.name = "SystemMenuPanel"
	sys_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sys_menu_panel.visible = false
	add_child(sys_menu_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.88, 0.95, 1.0, 1.0)
	sys_menu_panel.add_child(bg)

	# 主内容区 (左侧 1020x620)
	var content_area := Control.new()
	content_area.position = Vector2(20, 20)
	content_area.size = Vector2(1010, 620)
	sys_menu_panel.add_child(content_area)

	_build_save_load_page(content_area)
	_build_config_pages(content_area)

	# 右侧常驻导航栏不透明底板（彻底遮盖 sgusdtwnd* 原图右侧假按钮重影）
	var nav_bg := ColorRect.new()
	nav_bg.position = Vector2(1038, 0)
	nav_bg.size = Vector2(242, 720)
	nav_bg.color = Color(0.90, 0.96, 1.0, 1.0)
	sys_menu_panel.add_child(nav_bg)

	# 右侧常驻导航栏 (210px 宽，对齐视频 00:08)
	var nav_vbox := VBoxContainer.new()
	nav_vbox.position = Vector2(1050, 56)
	nav_vbox.size = Vector2(210, 600)
	nav_vbox.add_theme_constant_override("separation", 8)
	sys_menu_panel.add_child(nav_vbox)

	var nav_items := [
		{"key": "display", "label": "画面设置"},
		{"key": "text", "label": "文本设置"},
		{"key": "sound", "label": "声音设置"},
		{"key": "system", "label": "系统设置"},
		{"key": "keys", "label": "快捷键设置"},
		{"key": "save", "label": "存档"},
		{"key": "load", "label": "读档"},
		{"key": "back_game", "label": "返回游戏"},
		{"key": "back_title", "label": "返回标题"},
		{"key": "quit", "label": "结束游戏"},
		{"key": "reset", "label": "初始化"},
	]
	for item in nav_items:
		var nb := Button.new()
		nb.text = str(item["label"])
		nb.custom_minimum_size = Vector2(202, 42)
		nb.toggle_mode = item["key"] in ["display", "text", "sound", "system", "keys", "save", "load"]
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.95, 0.98, 1.0, 0.95)
		st.border_color = Color(0.3, 0.68, 0.98, 0.95)
		st.set_border_width_all(2)
		st.set_corner_radius_all(12)
		nb.add_theme_stylebox_override("normal", st)
		var st_act := st.duplicate() as StyleBoxFlat
		st_act.bg_color = Color(0.24, 0.64, 0.98, 0.98)
		nb.add_theme_stylebox_override("hover", st_act)
		nb.add_theme_stylebox_override("pressed", st_act)
		nb.add_theme_color_override("font_color", Color(0.14, 0.35, 0.65))
		nb.add_theme_color_override("font_hover_color", Color.WHITE)
		nb.add_theme_color_override("font_pressed_color", Color.WHITE)
		nb.set_meta("nav_key", str(item["key"]))

		var key := str(item["key"])
		nb.pressed.connect(func() -> void: _on_sys_nav_pressed(key))
		nav_vbox.add_child(nb)
		_sys_nav_buttons.append(nb)

	# 底部 Help 不透明底板（彻底遮盖 sgusdtwnd* 原图底部红棕色 Help 条）
	var help_bg := ColorRect.new()
	help_bg.position = Vector2(0, 646)
	help_bg.size = Vector2(1040, 74)
	help_bg.color = Color(0.88, 0.95, 1.0, 1.0)
	sys_menu_panel.add_child(help_bg)

	# 底部 Help 栏
	var help_panel := PanelContainer.new()
	help_panel.position = Vector2(24, 654)
	help_panel.size = Vector2(1000, 48)
	var hst := StyleBoxFlat.new()
	hst.bg_color = Color(0.08, 0.28, 0.56, 0.92)
	hst.set_corner_radius_all(12)
	help_panel.add_theme_stylebox_override("panel", hst)
	sys_menu_panel.add_child(help_panel)

	_sys_help_label = Label.new()
	_sys_help_label.text = "  Help: 在此处调整画面、声音、系统设置或管理游戏存档。"
	_sys_help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sys_help_label.add_theme_font_size_override("font_size", 18)
	_sys_help_label.add_theme_color_override("font_color", Color.WHITE)
	help_panel.add_child(_sys_help_label)


func _build_save_load_page(parent: Control) -> void:
	save_load_panel = Control.new()
	save_load_panel.name = "SaveLoadPanel"
	save_load_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	save_load_panel.visible = false
	parent.add_child(save_load_panel)

	_save_bg_rect = TextureRect.new()
	_save_bg_rect.position = Vector2(-20, -20)
	_save_bg_rect.size = Vector2(1280, 720)
	_save_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_save_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_save_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_load_panel.add_child(_save_bg_rect)

	_save_title_lbl = Label.new()
	_save_title_lbl.name = "Title"
	_save_title_lbl.position = Vector2(20, 6)
	_save_title_lbl.add_theme_font_size_override("font_size", 26)
	_save_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	_save_title_lbl.add_theme_color_override("font_shadow_color", Color(0.2, 0.05, 0.1, 0.8))
	save_load_panel.add_child(_save_title_lbl)

	# 左侧 1~10 页码不透明底板（遮盖原图左侧烘焙的 1~10 假按钮）
	_save_page_cover = ColorRect.new()
	_save_page_cover.position = Vector2(4, 50)
	_save_page_cover.size = Vector2(62, 558)
	_save_page_cover.color = Color(0.95, 0.56, 0.72, 1.0)
	save_load_panel.add_child(_save_page_cover)

	# 左侧 1~10 页码按钮
	var page_vb := VBoxContainer.new()
	page_vb.position = Vector2(10, 56)
	page_vb.size = Vector2(52, 540)
	page_vb.add_theme_constant_override("separation", 6)
	save_load_panel.add_child(page_vb)
	for p in range(10):
		var pb := Button.new()
		pb.text = str(p + 1)
		pb.toggle_mode = true
		pb.custom_minimum_size = Vector2(46, 46)
		var pst_n := StyleBoxFlat.new()
		pst_n.bg_color = Color(1.0, 1.0, 1.0, 0.95)
		pst_n.border_color = Color(0.85, 0.40, 0.55, 0.9)
		pst_n.set_border_width_all(2)
		pst_n.set_corner_radius_all(8)
		pb.add_theme_stylebox_override("normal", pst_n)
		var pst_p := pst_n.duplicate() as StyleBoxFlat
		pst_p.bg_color = Color(0.92, 0.28, 0.52, 1.0)
		pst_p.border_color = Color.WHITE
		pb.add_theme_stylebox_override("pressed", pst_p)
		pb.add_theme_stylebox_override("hover", pst_p)
		pb.add_theme_color_override("font_color", Color(0.35, 0.12, 0.22))
		pb.add_theme_color_override("font_pressed_color", Color.WHITE)
		pb.add_theme_color_override("font_hover_color", Color.WHITE)
		pb.add_theme_font_size_override("font_size", 18)
		var p_idx := p
		pb.pressed.connect(func() -> void: _switch_save_page(p_idx))
		page_vb.add_child(pb)
		_page_buttons.append(pb)

	# 中间 2x5 槽位网格
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(72, 56)
	grid.size = Vector2(610, 550)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	save_load_panel.add_child(grid)

	for i in range(SLOTS_PER_PAGE):
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(292, 102)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.2, 0.12, 0.18, 0.72)
		st.border_color = Color(1, 1, 1, 0.6)
		st.set_border_width_all(2)
		st.set_corner_radius_all(10)
		sb.add_theme_stylebox_override("normal", st)

		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 8)
		sb.add_child(hb)

		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(118, 84)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(thumb)
		_slot_thumbs.append(thumb)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lbl)
		_slot_labels.append(lbl)

		var row_idx := i
		sb.pressed.connect(func() -> void: _on_save_slot_clicked(row_idx))
		grid.add_child(sb)
		_slot_buttons.append(sb)

	# 右侧预览卡片（完全不透明，遮盖原图右侧 コメント 假框）
	var prev_box := PanelContainer.new()
	prev_box.position = Vector2(700, 56)
	prev_box.size = Vector2(300, 550)
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.15, 0.1, 0.16, 0.98)
	pst.border_color = Color(1, 1, 1, 0.65)
	pst.set_border_width_all(2)
	pst.set_corner_radius_all(12)
	pst.set_content_margin_all(12)
	prev_box.add_theme_stylebox_override("panel", pst)
	save_load_panel.add_child(prev_box)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 10)
	prev_box.add_child(pvb)

	_preview_thumb = TextureRect.new()
	_preview_thumb.custom_minimum_size = Vector2(276, 160)
	_preview_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pvb.add_child(_preview_thumb)

	_preview_info = Label.new()
	_preview_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_info.add_theme_font_size_override("font_size", 16)
	_preview_info.add_theme_color_override("font_color", Color.WHITE)
	pvb.add_child(_preview_info)

	_preview_action_btn = _make_pill_btn("执行", Vector2(240, 46))
	_preview_action_btn.pressed.connect(func() -> void: _execute_selected_slot())
	pvb.add_child(_preview_action_btn)

	_sys_pages["save"] = save_load_panel
	_sys_pages["load"] = save_load_panel


func _build_config_pages(parent: Control) -> void:
	config_panel = Control.new()
	config_panel.name = "ConfigPanel"
	config_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	config_panel.visible = false
	parent.add_child(config_panel)

	# 1. 画面设置页
	var pg_disp := _make_cfg_card("画面与显示设置", config_panel)
	_sys_pages["display"] = pg_disp
	var vb_d := pg_disp.get_node("Inner") as VBoxContainer
	var r_spd := _make_slider_row("文字显示速度 (字符/秒, 0=瞬间)", 0.0, 120.0, 5.0)
	_sld_text_speed = r_spd["slider"]
	_lbl_text_speed = r_spd["value"]
	_sld_text_speed.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.text_speed = v
		_lbl_text_speed.text = "瞬间" if v <= 0.0 else "%d/秒" % int(v)
	)
	vb_d.add_child(r_spd["row"])

	var r_auto := _make_slider_row("自动模式等待时间 (秒)", 0.3, 5.0, 0.1)
	_sld_auto_delay = r_auto["slider"]
	_lbl_auto_delay = r_auto["value"]
	_sld_auto_delay.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.auto_delay = v
		_lbl_auto_delay.text = "%.1f 秒" % v
	)
	vb_d.add_child(r_auto["row"])

	# 2. 文本/窗口透明度设置页
	var pg_txt := _make_cfg_card("文本与对白框设置", config_panel)
	_sys_pages["text"] = pg_txt
	var vb_t := pg_txt.get_node("Inner") as VBoxContainer
	var r_op := _make_slider_row("对白框不透明度", 0.2, 1.0, 0.02)
	_sld_opacity = r_op["slider"]
	_lbl_opacity = r_op["value"]
	_sld_opacity.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.dialogue_opacity = v
		_lbl_opacity.text = "%d%%" % int(round(v * 100.0))
		_apply_dialogue_opacity()
		if _preview_msg_box != null:
			_preview_msg_box.color.a = v
	)
	vb_t.add_child(r_op["row"])

	_preview_msg_box = ColorRect.new()
	_preview_msg_box.custom_minimum_size = Vector2(680, 96)
	_preview_msg_box.color = Color(0.1, 0.45, 0.85, 0.92)
	var prev_lbl := Label.new()
	prev_lbl.text = "  【青葉 恭介】这就是对白框透明度实时预览效果。"
	prev_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	prev_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prev_lbl.add_theme_font_size_override("font_size", 22)
	prev_lbl.add_theme_color_override("font_color", Color.WHITE)
	_preview_msg_box.add_child(prev_lbl)
	vb_t.add_child(_preview_msg_box)

	_chk_skip_unread = _make_styled_check("ChkSkipUnread", "允许快进未读文本")
	_chk_skip_unread.toggled.connect(func(on: bool) -> void:
		if _cfg != null: _cfg.skip_unread = on
	)
	vb_t.add_child(_chk_skip_unread)

	# 3. 声音设置页
	var pg_snd := _make_cfg_card("声音与音量设置", config_panel)
	_sys_pages["sound"] = pg_snd
	var vb_s := pg_snd.get_node("Inner") as VBoxContainer
	var r_bgm := _make_slider_row("BGM 音量", 0.0, 1.0, 0.05)
	_sld_bgm = r_bgm["slider"]; _lbl_bgm = r_bgm["value"]
	_sld_bgm.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.bgm_volume = v
		_lbl_bgm.text = "%d%%" % int(round(v * 100.0))
		config_changed.emit()
	)
	vb_s.add_child(r_bgm["row"])

	var r_se := _make_slider_row("SE 音效音量", 0.0, 1.0, 0.05)
	_sld_se = r_se["slider"]; _lbl_se = r_se["value"]
	_sld_se.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.se_volume = v
		_lbl_se.text = "%d%%" % int(round(v * 100.0))
		config_changed.emit()
	)
	vb_s.add_child(r_se["row"])

	var r_vc := _make_slider_row("角色语音音量", 0.0, 1.0, 0.05)
	_sld_voice = r_vc["slider"]; _lbl_voice = r_vc["value"]
	_sld_voice.value_changed.connect(func(v: float) -> void:
		if _cfg != null: _cfg.voice_volume = v
		_lbl_voice.text = "%d%%" % int(round(v * 100.0))
		config_changed.emit()
	)
	vb_s.add_child(r_vc["row"])

	var test_vc := _make_pill_btn("🔊 测试标题语音", Vector2(200, 42))
	test_vc.pressed.connect(func() -> void: voice_replay_requested.emit("TITLE_HI"))
	vb_s.add_child(test_vc)

	# 4. 系统设置页（含无码/透视/确认弹窗）
	var pg_sys := _make_cfg_card("系统与移植增强设置", config_panel)
	_sys_pages["system"] = pg_sys
	var vb_y := pg_sys.get_node("Inner") as VBoxContainer

	_chk_uncensored = _make_styled_check("ChkUncensored", "启用无码补丁优先挂载 (data02150.arc.bak)")
	_chk_uncensored.toggled.connect(func(on: bool) -> void:
		if _cfg != null: _cfg.uncensored_mode = on
		config_changed.emit()
	)
	vb_y.add_child(_chk_uncensored)

	_chk_nude = _make_styled_check("ChkNude", "启用透视 / 全裸差分开关 (F12 / 三指轻触)")
	_chk_nude.toggled.connect(func(on: bool) -> void:
		if _cfg != null: _cfg.nude_mode = on
		config_changed.emit()
	)
	vb_y.add_child(_chk_nude)

	_chk_confirm = _make_styled_check("ChkConfirm", "快速存档/读档/返回标题前弹出确认框")
	_chk_confirm.toggled.connect(func(on: bool) -> void:
		if _cfg != null: _cfg.confirm_dialogs = on
	)
	vb_y.add_child(_chk_confirm)

	var btn_rescan := _make_pill_btn("重新扫描 BYOA 资产目录", Vector2(260, 42))
	btn_rescan.pressed.connect(func() -> void: rescan_byoa_requested.emit())
	vb_y.add_child(btn_rescan)

	# 5. 快捷键说明页
	var pg_key := _make_cfg_card("PC 快捷键 & iOS 触控手势", config_panel)
	_sys_pages["keys"] = pg_key
	var vb_k := pg_key.get_node("Inner") as VBoxContainer
	var key_lbl := Label.new()
	key_lbl.text = (
		"【PC 键盘快捷键】\n"
		+ "  • Enter / Space / 左键 : 推进剧情 / 补全当前文字\n"
		+ "  • Ctrl (按住) / S      : 快进 (Skip)\n"
		+ "  • A                    : 自动模式 (Auto)\n"
		+ "  • H / 右键             : 隐藏 / 显示对白框\n"
		+ "  • L                    : 打开历史记录 (Log)\n"
		+ "  • R                    : 重播当前句语音\n"
		+ "  • F12                  : 切换透视 / 全裸差分\n"
		+ "  • Esc                  : 打开系统菜单 / 关闭弹窗\n\n"
		+ "【iOS 触屏手势】\n"
		+ "  • 单指轻触             : 推进剧情 (Auto/Skip 激活时首次轻触仅暂停)\n"
		+ "  • 双指轻触             : 隐藏 / 显示对白框\n"
		+ "  • 三指轻触             : 快捷切换 F12 透视差分\n"
		+ "  • 单指右滑             : 打开历史记录 Backlog"
	)
	key_lbl.add_theme_font_size_override("font_size", 18)
	key_lbl.add_theme_color_override("font_color", Color(0.12, 0.25, 0.45))
	vb_k.add_child(key_lbl)


func _make_styled_check(node_name: String, label_txt: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.name = node_name
	cb.text = label_txt
	cb.add_theme_font_size_override("font_size", 19)
	var dark := Color(0.10, 0.22, 0.42)
	cb.add_theme_color_override("font_color", dark)
	cb.add_theme_color_override("font_focus_color", dark)
	cb.add_theme_color_override("font_hover_color", dark)
	cb.add_theme_color_override("font_pressed_color", dark)
	cb.add_theme_color_override("font_hover_pressed_color", dark)
	cb.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.6))
	return cb


func _make_cfg_card(title_txt: String, parent: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.99, 1.0, 0.94)
	st.border_color = Color(0.32, 0.68, 0.98, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)

	var vb := VBoxContainer.new()
	vb.name = "Inner"
	vb.add_theme_constant_override("separation", 18)
	card.add_child(vb)

	var hdr := Label.new()
	hdr.text = title_txt
	hdr.add_theme_font_size_override("font_size", 26)
	hdr.add_theme_color_override("font_color", Color(0.12, 0.42, 0.78))
	vb.add_child(hdr)
	return card


func _make_slider_row(label_txt: String, min_v: float, max_v: float, step_v: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(320, 32)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.28, 0.48))
	row.add_child(lbl)

	var sld := HSlider.new()
	sld.min_value = min_v
	sld.max_value = max_v
	sld.step = step_v
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sld.custom_minimum_size = Vector2(320, 32)
	row.add_child(sld)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(90, 32)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", Color(0.12, 0.45, 0.8))
	row.add_child(val_lbl)

	return {"row": row, "slider": sld, "value": val_lbl}


func _on_sys_nav_pressed(key: String) -> void:
	match key:
		"display", "text", "sound", "system", "keys", "save", "load":
			_switch_sys_page(key)
		"back_game":
			if _cfg != null:
				_cfg.save_config()
			config_changed.emit()
			_close_all_modals()
		"back_title":
			show_confirm("sgdialog990003", "确定回到标题？", func() -> void:
				_close_all_modals()
				return_to_title_requested.emit()
			)
		"quit":
			show_confirm("sgdialog990000", "确定结束游戏?", func() -> void: quit_game_requested.emit())
		"reset":
			if _cfg != null:
				_cfg.text_speed = 60.0
				_cfg.auto_delay = 1.6
				_cfg.dialogue_opacity = 0.92
				_cfg.bgm_volume = 0.85
				_cfg.se_volume = 0.90
				_cfg.voice_volume = 1.0
				_cfg.skip_unread = false
				_cfg.confirm_dialogs = true
				_cfg.save_config()
				_sync_config_ui()
				_apply_dialogue_opacity()
				config_changed.emit()


func _refresh_sys_nav_state() -> void:
	for nb in _sys_nav_buttons:
		var k := str(nb.get_meta("nav_key", ""))
		if k == "save" or k == "back_game":
			nb.disabled = not _sys_in_game
		if k == "back_title":
			nb.disabled = not _sys_in_game


func _switch_sys_page(key: String) -> void:
	for k in _sys_pages.keys():
		(_sys_pages[k] as Control).visible = false
	for nb in _sys_nav_buttons:
		nb.button_pressed = (str(nb.get_meta("nav_key", "")) == key)

	if key == "save" or key == "load":
		_is_save_mode = (key == "save")
		config_panel.visible = false
		save_load_panel.visible = true
		_open_save_load_internal(_is_save_mode)
	else:
		save_load_panel.visible = false
		config_panel.visible = true
		if _sys_pages.has(key):
			(_sys_pages[key] as Control).visible = true


func _open_save_load(save_mode: bool) -> void:
	open_system_menu("save" if save_mode else "load", _sys_in_game)


func _open_save_load_internal(save_mode: bool) -> void:
	_is_save_mode = save_mode
	_save_title_lbl.text = "存档 (Save)" if save_mode else "读档 (Load)"
	if _save_page_cover != null:
		_save_page_cover.color = Color(0.95, 0.56, 0.72, 1.0) if save_mode else Color(0.98, 0.68, 0.34, 1.0)
	var bg_tex := theme_loader.get_tex("sgusdtwnd990000" if save_mode else "sgusdtwnd990001")
	if bg_tex != null:
		_save_bg_rect.texture = bg_tex
		_save_title_lbl.visible = false
	else:
		_save_title_lbl.visible = true
	_switch_save_page(_current_save_page)


func _switch_save_page(page: int) -> void:
	_current_save_page = clampi(page, 0, 9)
	for i in range(_page_buttons.size()):
		_page_buttons[i].button_pressed = (i == _current_save_page)
	var base := _current_save_page * SLOTS_PER_PAGE
	for i in range(SLOTS_PER_PAGE):
		var slot := base + i
		var data := load_game_from_slot(slot)
		var tag := "Q.S" if slot == QUICK_SAVE_SLOT else "%02d" % [slot + 1]
		if data.is_empty():
			_slot_labels[i].text = "%s  [空]" % tag
			_slot_thumbs[i].texture = null
		else:
			var sc := str(data.get("current_script", ""))
			var ts := str(data.get("timestamp", "")).left(16)
			var txt := str(data.get("last_dialogue_text", "")).left(16)
			_slot_labels[i].text = "%s | %s\n%s\n%s" % [tag, sc, ts, txt]
			var sp := str(data.get("shot_path", ""))
			if not sp.is_empty() and FileAccess.file_exists(sp):
				var img := Image.load_from_file(sp)
				_slot_thumbs[i].texture = ImageTexture.create_from_image(img) if img != null else null
			else:
				_slot_thumbs[i].texture = null
	_select_slot(base)


func _on_save_slot_clicked(row_idx: int) -> void:
	var slot := _current_save_page * SLOTS_PER_PAGE + row_idx
	if slot == _selected_slot:
		_execute_selected_slot()
	else:
		_select_slot(slot)


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	var data := load_game_from_slot(slot)
	var tag := "Q.S 快速存档" if slot == QUICK_SAVE_SLOT else "槽位 %02d" % [slot + 1]
	if data.is_empty():
		_preview_thumb.texture = null
		_preview_info.text = "%s\n\n暂无存档记录" % tag
		_preview_action_btn.text = "保存到此槽位" if _is_save_mode else "空槽位"
		_preview_action_btn.disabled = not _is_save_mode
	else:
		var sp := str(data.get("shot_path", ""))
		if not sp.is_empty() and FileAccess.file_exists(sp):
			var img := Image.load_from_file(sp)
			_preview_thumb.texture = ImageTexture.create_from_image(img) if img != null else null
		else:
			_preview_thumb.texture = null
		_preview_info.text = "%s\n剧本: %s\n时间: %s\n\n%s" % [
			tag,
			str(data.get("current_script", "")),
			str(data.get("timestamp", "")),
			str(data.get("last_dialogue_text", "")),
		]
		_preview_action_btn.text = "覆盖存档" if _is_save_mode else "读取此存档"
		_preview_action_btn.disabled = false


func _execute_selected_slot() -> void:
	var slot := _selected_slot
	if _is_save_mode:
		var existing := load_game_from_slot(slot)
		if not existing.is_empty():
			show_confirm("sgdialog990001", "确定要覆盖该存档吗？", func() -> void:
				_close_all_modals()
				save_slot_requested.emit(slot)
			)
		else:
			_close_all_modals()
			save_slot_requested.emit(slot)
	else:
		var existing := load_game_from_slot(slot)
		if existing.is_empty():
			return
		_close_all_modals()
		load_slot_requested.emit(slot)


func _build_log_panel() -> void:
	log_panel = Control.new()
	log_panel.name = "LogPanel"
	log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_panel.visible = false
	add_child(log_panel)

	var log_bg := TextureRect.new()
	log_bg.name = "LogBgRect"
	log_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	log_bg.stretch_mode = TextureRect.STRETCH_SCALE
	log_panel.add_child(log_bg)

	var fallback := ColorRect.new()
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback.color = Color(0.12, 0.3, 0.58, 0.88)
	fallback.show_behind_parent = true
	log_bg.add_child(fallback)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(96, 56)
	scroll.size = Vector2(980, 610)
	log_panel.add_child(scroll)

	_log_list_vbox = VBoxContainer.new()
	_log_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(_log_list_vbox)

	# 兼容旧测试引用的 log_text
	log_text = RichTextLabel.new()
	log_text.visible = false
	log_panel.add_child(log_text)

	var close_btn := _make_pill_btn("返回游戏", Vector2(150, 44))
	close_btn.name = "LogCloseBtn"
	close_btn.position = Vector2(1098, 636)
	close_btn.pressed.connect(_close_all_modals)
	log_panel.add_child(close_btn)


func _open_log_panel() -> void:
	var lines: Array[String] = []
	for item in _backlog:
		lines.append(str(item.get("line", "")))
	log_text.text = "\n".join(lines)

	for c in _log_list_vbox.get_children():
		c.queue_free()

	var voice_tex := theme_loader.get_tex("sglogwnd000000")
	for item in _backlog:
		var card := PanelContainer.new()
		var cst := StyleBoxFlat.new()
		cst.bg_color = Color(0.08, 0.22, 0.46, 0.72)
		cst.set_corner_radius_all(10)
		cst.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", cst)
		_log_list_vbox.add_child(card)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		card.add_child(vb)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 10)
		vb.add_child(hdr)

		var snap: Dictionary = item.get("snapshot", {})
		if not snap.is_empty():
			var qj := _make_pill_btn("Quick Jump", Vector2(106, 28))
			qj.pressed.connect(func() -> void:
				_close_all_modals()
				quick_jump_requested.emit(snap)
			)
			hdr.add_child(qj)

		var spk := Label.new()
		spk.text = str(item.get("speaker", ""))
		spk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spk.add_theme_font_size_override("font_size", 19)
		spk.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		hdr.add_child(spk)

		var v_entry := str(item.get("voice_entry", ""))
		if not v_entry.is_empty():
			var vb_btn := TextureButton.new()
			vb_btn.custom_minimum_size = Vector2(34, 34)
			if voice_tex != null:
				vb_btn.texture_normal = voice_tex
			else:
				var vl := Label.new(); vl.text = "🔊"; vb_btn.add_child(vl)
			vb_btn.pressed.connect(func() -> void: voice_replay_requested.emit(v_entry))
			hdr.add_child(vb_btn)

		var txt_lbl := Label.new()
		txt_lbl.text = str(item.get("text", ""))
		txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt_lbl.add_theme_font_size_override("font_size", 20)
		txt_lbl.add_theme_color_override("font_color", Color.WHITE)
		vb.add_child(txt_lbl)

	_close_all_modals()
	modal_backdrop.visible = true
	log_panel.visible = true


func _build_byoa_panel() -> void:
	byoa_panel = _make_modal_box("ByoaPanel", Vector2(760, 460))
	var by_vb := VBoxContainer.new()
	by_vb.add_theme_constant_override("separation", 14)
	byoa_panel.add_child(by_vb)
	byoa_label = Label.new()
	byoa_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	byoa_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	by_vb.add_child(byoa_label)
	var btn_rescan := _make_pill_btn("重新扫描资产目录", Vector2(220, 48))
	btn_rescan.pressed.connect(func() -> void: rescan_byoa_requested.emit())
	by_vb.add_child(btn_rescan)
	add_child(byoa_panel)


func _build_choice_panel() -> void:
	choice_panel = _make_modal_box("ChoicePanel", Vector2(680, 420))
	choice_vbox = VBoxContainer.new()
	choice_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_vbox.add_theme_constant_override("separation", 14)
	choice_panel.add_child(choice_vbox)
	add_child(choice_panel)


func _build_new_game_overlays() -> void:
	# 1. 请输入姓名弹窗（对应 PC 原版 01:44）
	_name_input_overlay = Control.new()
	_name_input_overlay.name = "NameInputOverlay"
	_name_input_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_input_overlay.visible = false
	add_child(_name_input_overlay)

	var ncard := PanelContainer.new()
	ncard.position = Vector2(220, 120)
	ncard.size = Vector2(840, 480)
	var nst := StyleBoxFlat.new()
	nst.bg_color = Color(0.96, 0.80, 0.86, 0.98)
	nst.border_color = Color.WHITE
	nst.set_border_width_all(4)
	nst.set_corner_radius_all(20)
	nst.set_content_margin_all(32)
	ncard.add_theme_stylebox_override("panel", nst)
	_name_input_overlay.add_child(ncard)

	var nvb := VBoxContainer.new()
	nvb.alignment = BoxContainer.ALIGNMENT_CENTER
	nvb.add_theme_constant_override("separation", 24)
	ncard.add_child(nvb)

	var ntitle := Label.new()
	ntitle.text = "请输入姓名"
	ntitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ntitle.add_theme_font_size_override("font_size", 32)
	ntitle.add_theme_color_override("font_color", Color.WHITE)
	ntitle.add_theme_color_override("font_shadow_color", Color(0.6, 0.2, 0.35, 0.8))
	nvb.add_child(ntitle)

	var nhb := HBoxContainer.new()
	nhb.alignment = BoxContainer.ALIGNMENT_CENTER
	nhb.add_theme_constant_override("separation", 24)
	nvb.add_child(nhb)

	var f_lbl := Label.new()
	f_lbl.text = "姓："
	f_lbl.add_theme_font_size_override("font_size", 24)
	f_lbl.add_theme_color_override("font_color", Color(0.45, 0.15, 0.25))
	nhb.add_child(f_lbl)

	_family_input = LineEdit.new()
	_family_input.text = "青叶"
	_family_input.custom_minimum_size = Vector2(180, 48)
	_family_input.add_theme_font_size_override("font_size", 22)
	nhb.add_child(_family_input)

	var g_lbl := Label.new()
	g_lbl.text = "名："
	g_lbl.add_theme_font_size_override("font_size", 24)
	g_lbl.add_theme_color_override("font_color", Color(0.45, 0.15, 0.25))
	nhb.add_child(g_lbl)

	_given_input = LineEdit.new()
	_given_input.text = "恭介"
	_given_input.custom_minimum_size = Vector2(180, 48)
	_given_input.add_theme_font_size_override("font_size", 22)
	nhb.add_child(_given_input)

	var btn_def := _make_pill_btn("默认", Vector2(180, 46))
	btn_def.pressed.connect(func() -> void:
		_family_input.text = "青叶"
		_given_input.text = "恭介"
	)
	nvb.add_child(btn_def)

	var btn_row_ok := HBoxContainer.new()
	btn_row_ok.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row_ok.add_theme_constant_override("separation", 24)
	nvb.add_child(btn_row_ok)

	var btn_cancel := _make_pill_btn("返回标题", Vector2(180, 50))
	btn_cancel.pressed.connect(func() -> void:
		_name_input_overlay.visible = false
		_refresh_backdrop()
	)
	btn_row_ok.add_child(btn_cancel)

	var btn_done := _make_pill_btn("结束输入", Vector2(200, 50))
	btn_done.pressed.connect(func() -> void:
		_name_input_overlay.visible = false
		if _prologue_skip_overlay != null:
			_prologue_skip_overlay.visible = true
			modal_backdrop.visible = true
		else:
			_refresh_backdrop()
			new_game_confirmed.emit(false, _family_input.text, _given_input.text)
	)
	btn_row_ok.add_child(btn_done)

	# 2. 要跳过序章吗？选择弹窗（对应 PC 原版 01:51）
	_prologue_skip_overlay = Control.new()
	_prologue_skip_overlay.name = "PrologueSkipOverlay"
	_prologue_skip_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prologue_skip_overlay.visible = false
	add_child(_prologue_skip_overlay)

	var sky := ColorRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.color = Color(0.28, 0.68, 0.96, 0.96)
	_prologue_skip_overlay.add_child(sky)

	var pvb := VBoxContainer.new()
	pvb.position = Vector2(240, 180)
	pvb.size = Vector2(800, 320)
	pvb.alignment = BoxContainer.ALIGNMENT_CENTER
	pvb.add_theme_constant_override("separation", 26)
	_prologue_skip_overlay.add_child(pvb)

	var p_lbl := Label.new()
	p_lbl.text = "要跳过序章吗？"
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.add_theme_font_size_override("font_size", 32)
	p_lbl.add_theme_color_override("font_color", Color.WHITE)
	p_lbl.add_theme_color_override("font_shadow_color", Color(0.05, 0.2, 0.45, 0.85))
	pvb.add_child(p_lbl)

	var btn_pro := _make_pill_btn("从序章开始", Vector2(560, 62))
	btn_pro.add_theme_font_size_override("font_size", 24)
	btn_pro.pressed.connect(func() -> void:
		_prologue_skip_overlay.visible = false
		_refresh_backdrop()
		new_game_confirmed.emit(false, _family_input.text, _given_input.text)
	)
	pvb.add_child(btn_pro)

	var btn_daily := _make_pill_btn("从日常部分开始", Vector2(560, 62))
	btn_daily.add_theme_font_size_override("font_size", 24)
	btn_daily.pressed.connect(func() -> void:
		_prologue_skip_overlay.visible = false
		_refresh_backdrop()
		new_game_confirmed.emit(true, _family_input.text, _given_input.text)
	)
	pvb.add_child(btn_daily)


func _build_confirm_dialog() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.name = "ConfirmDialogOverlay"
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	_confirm_overlay.add_child(dim)

	_confirm_bg_rect = TextureRect.new()
	_confirm_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_confirm_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_confirm_overlay.add_child(_confirm_bg_rect)

	var fallback_card := PanelContainer.new()
	fallback_card.position = Vector2(360, 220)
	fallback_card.size = Vector2(560, 260)
	fallback_card.show_behind_parent = true
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.95, 0.93, 0.98)
	st.border_color = Color(0.45, 0.55, 0.72)
	st.set_border_width_all(2)
	st.set_corner_radius_all(16)
	fallback_card.add_theme_stylebox_override("panel", st)
	_confirm_bg_rect.add_child(fallback_card)

	_confirm_msg_lbl = Label.new()
	_confirm_msg_lbl.position = Vector2(360, 250)
	_confirm_msg_lbl.size = Vector2(560, 80)
	_confirm_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_msg_lbl.add_theme_font_size_override("font_size", 26)
	_confirm_msg_lbl.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
	_confirm_overlay.add_child(_confirm_msg_lbl)

	_confirm_yes_btn = TextureButton.new()
	_confirm_yes_btn.position = Vector2(400, 386)
	_confirm_yes_btn.custom_minimum_size = Vector2(214, 64)
	_confirm_yes_btn.ignore_texture_size = true
	_confirm_yes_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var yl := Label.new(); yl.text = "是"; yl.set_anchors_preset(Control.PRESET_FULL_RECT)
	yl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; yl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	yl.add_theme_font_size_override("font_size", 22)
	_confirm_yes_btn.add_child(yl)
	_confirm_yes_btn.pressed.connect(func() -> void:
		_confirm_overlay.visible = false
		_refresh_backdrop()
		if _confirm_callback.is_valid():
			_confirm_callback.call()
	)
	_confirm_overlay.add_child(_confirm_yes_btn)

	_confirm_no_btn = TextureButton.new()
	_confirm_no_btn.position = Vector2(666, 386)
	_confirm_no_btn.custom_minimum_size = Vector2(214, 64)
	_confirm_no_btn.ignore_texture_size = true
	_confirm_no_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var nl := Label.new(); nl.text = "否"; nl.set_anchors_preset(Control.PRESET_FULL_RECT)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 22)
	_confirm_no_btn.add_child(nl)
	_confirm_no_btn.pressed.connect(func() -> void:
		_confirm_overlay.visible = false
		_refresh_backdrop()
	)
	_confirm_overlay.add_child(_confirm_no_btn)


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
	st.bg_color = Color(0.08, 0.16, 0.32, 0.92)
	st.border_color = Color(0.55, 0.82, 1.0, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(16)
	st.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", st)
	return p


func _open_config_panel() -> void:
	open_system_menu("display", _sys_in_game)


func _sync_config_ui() -> void:
	if _cfg == null:
		return
	if _chk_uncensored != null:
		_chk_uncensored.button_pressed = _cfg.uncensored_mode
	if _chk_nude != null:
		_chk_nude.button_pressed = _cfg.nude_mode
	if _chk_skip_unread != null:
		_chk_skip_unread.button_pressed = _cfg.skip_unread
	if _chk_confirm != null:
		_chk_confirm.button_pressed = _cfg.confirm_dialogs
	if _sld_text_speed != null:
		_sld_text_speed.value = _cfg.text_speed
		_lbl_text_speed.text = "瞬间" if _cfg.text_speed <= 0.0 else "%d/秒" % int(_cfg.text_speed)
	if _sld_auto_delay != null:
		_sld_auto_delay.value = _cfg.auto_delay
		_lbl_auto_delay.text = "%.1f 秒" % _cfg.auto_delay
	if _sld_opacity != null:
		_sld_opacity.value = _cfg.dialogue_opacity
		_lbl_opacity.text = "%d%%" % int(round(_cfg.dialogue_opacity * 100.0))
	if _sld_bgm != null:
		_sld_bgm.value = _cfg.bgm_volume
		_lbl_bgm.text = "%d%%" % int(round(_cfg.bgm_volume * 100.0))
	if _sld_se != null:
		_sld_se.value = _cfg.se_volume
		_lbl_se.text = "%d%%" % int(round(_cfg.se_volume * 100.0))
	if _sld_voice != null:
		_sld_voice.value = _cfg.voice_volume
		_lbl_voice.text = "%d%%" % int(round(_cfg.voice_volume * 100.0))


func _apply_dialogue_opacity() -> void:
	if _cfg == null:
		return
	if _msg_bg_rect != null:
		_msg_bg_rect.modulate.a = _cfg.dialogue_opacity
	if _msg_fallback_bg != null:
		_msg_fallback_bg.modulate.a = _cfg.dialogue_opacity


func _close_all_modals() -> void:
	sys_menu_panel.visible = false
	save_load_panel.visible = false
	config_panel.visible = false
	log_panel.visible = false
	choice_panel.visible = false
	if gallery_panel != null:
		gallery_panel.visible = false
	_confirm_overlay.visible = false
	if _name_input_overlay != null:
		_name_input_overlay.visible = false
	if _prologue_skip_overlay != null:
		_prologue_skip_overlay.visible = false
	_refresh_backdrop()


func _refresh_backdrop() -> void:
	modal_backdrop.visible = (
		byoa_panel.visible
		or sys_menu_panel.visible
		or log_panel.visible
		or choice_panel.visible
		or _confirm_overlay.visible
		or (_name_input_overlay != null and _name_input_overlay.visible)
		or (_prologue_skip_overlay != null and _prologue_skip_overlay.visible)
	)
