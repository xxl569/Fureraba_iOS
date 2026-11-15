class_name UiPanels
extends Control

## 主 UI 面板集合（1280x720 逻辑坐标系）：
## 1. 标题界面（运行时提取 sgtitle* 贴图，含 5 按钮与底部 Help 提示栏）
## 2. 对白框与右下角三层金字塔快捷控制（sgmsgwnd* 贴图、左侧表情头像框、左上角 BGM 曲名横幅、未读/已读双色、Q.S/Q.L/历史/♥透视）
## 3. 1:1 PC 还原的一体化系统窗口（画面/文本/声音/系统/快捷键/存档/读档 7 大页，全部功能文字简体中文覆盖，人物姓名保持日文原名）
## 4. 历史记录 Backlog（sglogwnd*，支持单句语音重播与 Quick Jump）
## 5. 原版姓名输入（sgnminpt*）、序章跳过、确认弹窗（sgdialog*）、选择支与附录 CG/回想/BGM 鉴赏

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
signal recollection_requested(script_name: String, appearance_mode: int)
signal test_se_requested(se_name: String)

const _ThemeLoader := preload("res://scripts/ui_theme_loader.gd")
const _GalleryPanel := preload("res://scripts/ui_gallery_panel.gd")

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 12
const TOTAL_SLOTS := 100
const SLOTS_PER_PAGE := 10
const QUICK_SAVE_SLOT := 99

const SOUND_CHAR_LIST: Array[Dictionary] = [
	{"key": "hi", "name": "皆原 陽茉莉", "sample": "HIMARI_INSERT02_#HI_012", "is_zh_cat": false},
	{"key": "ri", "name": "望月 理奈", "sample": "PROLOGUE02_#RI_060", "is_zh_cat": false},
	{"key": "yu", "name": "柊 ゆずゆ", "sample": "PROLOGUE03_#YU_020", "is_zh_cat": false},
	{"key": "mi", "name": "沢渡 岬", "sample": "MISAKI_INSERT01_#MI_035", "is_zh_cat": false},
	{"key": "to", "name": "野々村 智美", "sample": "PROLOGUE02_#TO_001", "is_zh_cat": false},
	{"key": "mh", "name": "綾部 まひろ", "sample": "RINA_INSERT02_#MH_027", "is_zh_cat": false},
	{"key": "mk", "name": "水澄 真子", "sample": "YUZUYU_INSERT01_#MK_023", "is_zh_cat": false},
	{"key": "ge", "name": "瀬野 元気", "sample": "PROLOGUE01_#GE_020", "is_zh_cat": false},
	{"key": "mo", "name": "須賀崎 桃", "sample": "HIMARI_INSERT02_#MO_003", "is_zh_cat": false},
	{"key": "se", "name": "近藤 正義", "sample": "PROLOGUE02_#SE_030", "is_zh_cat": false},
	{"key": "w_other", "name": "其他女性", "sample": "HIMARI_INSERT01_#W14_023", "is_zh_cat": true},
	{"key": "m_other", "name": "其他男性", "sample": "PROLOGUE02_#M08_001", "is_zh_cat": true},
]

const MOUSE_ASSIGN_FUNCS: Array[Dictionary] = [
	{"id": "options", "label": "选项"},
	{"id": "log", "label": "历史记录"},
	{"id": "hide_window", "label": "隐藏窗口"},
	{"id": "voice_replay", "label": "语音重播"},
	{"id": "auto", "label": "自动模式"},
	{"id": "left_click", "label": "左键单击"},
	{"id": "skip", "label": "快进模式"},
	{"id": "none", "label": "无分配"},
]

const KEY_BIND_ITEMS: Array[Dictionary] = [
	{"id": "quick_skip", "label": "简易跳读", "col": 0, "row": 0},
	{"id": "hide_window", "label": "暂时隐藏窗口", "col": 0, "row": 1},
	{"id": "log", "label": "历史", "col": 0, "row": 2},
	{"id": "auto", "label": "自动模式", "col": 0, "row": 3},
	{"id": "skip", "label": "跳读", "col": 0, "row": 4},
	{"id": "options", "label": "选项", "col": 0, "row": 5},
	{"id": "keys_menu", "label": "快捷键", "col": 1, "row": 0},
	{"id": "scene_jump", "label": "场景跳转", "col": 1, "row": 1},
	{"id": "save_menu", "label": "存档", "col": 1, "row": 2},
	{"id": "load_menu", "label": "读档", "col": 1, "row": 3},
	{"id": "title", "label": "标题", "col": 1, "row": 4},
	{"id": "quit", "label": "结束游戏", "col": 1, "row": 5},
]

var _cfg: ConfigManager
var _font: Font = null
var _font_base: Font = null
var _font_cache: Dictionary = {}
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
var face_avatar_rect: TextureRect
var bgm_telop_banner: Panel
var bgm_telop_label: Label
var _telop_tween: Tween
var _notice_banner: Panel
var _notice_label: Label
var _notice_tween: Tween
var quick_menu: Control
var btn_auto: BaseButton
var btn_skip: BaseButton
var btn_nude_quick: Button
var _auto_badge: TextureRect
var _skip_badge: TextureRect
var _badge_fallback: Label
var _last_face_img: String = ""
var _last_is_read: bool = false

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

# 系统窗口内部状态与动态容器
var _sys_bg_rect: TextureRect
var _sys_content_root: Control
var _sys_nav_buttons: Array[ BaseButton ] = []
var _sys_nav_map: Dictionary = {}
var _sys_init_btn: BaseButton
var _sys_top_help_panel: Panel
var _sys_top_help_lbl: Label
var _sys_bot_help_panel: Panel
var _sys_bot_help_lbl: Label
var _sys_in_game: bool = false
var _current_sys_page: String = "display"

# 存档/读档状态
var _is_save_mode: bool = true
var _current_save_page: int = 0
var _selected_slot: int = 0
var _save_comment_edit: TextEdit

# 文本设置调色板状态
var _color_edit_target: String = "unread" # "unread" or "read"
var _preview_sample_label: RichTextLabel
var _preview_msg_bg: Control
var _color_now_swatch: ColorRect
var _btn_unread_color: Button
var _btn_read_color: Button

# 声音设置角色独立音量状态
var _selected_sound_char_idx: int = 10 # 默认展示 10 (其他女性，对齐 PC 截图)

# 系统设置鼠标分配状态
var _selected_mouse_bind_target: String = "right_click"

# 快捷键设置状态
var _waiting_key_action: String = ""
var _key_notice_override: String = ""
var _key_notice_label: Label

# 新游戏姓名输入与序章跳过弹窗
var _name_input_overlay: Control
var _name_bg_tex_rect: TextureRect
var _family_input: LineEdit
var _given_input: LineEdit
var _btn_name_default: TextureButton
var _btn_name_done: TextureButton
var _prologue_skip_overlay: Control

# Log 控件与数据
var _log_scroll: ScrollContainer
var _log_list_vbox: VBoxContainer
var _backlog: Array[Dictionary] = []

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
	z_index = 300
	_build_dialogue_box()
	_build_bgm_telop_banner()
	_build_notice_banner()
	_build_quick_menu()
	_build_title_overlay()
	_build_modals()


func _exit_tree() -> void:
	if _telop_tween != null and _telop_tween.is_valid():
		_telop_tween.kill()
	_telop_tween = null
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = null


func _process(delta: float) -> void:
	if not _typing_active:
		return
	var speed := _cfg.text_speed if _cfg != null else 60.0
	if speed <= 0.0 or speed >= 115.0:
		finish_typing()
		return
	_typing_accum += delta * speed
	var vis := int(_typing_accum)
	if vis >= _typing_total_chars:
		finish_typing()
	else:
		dialogue_label.visible_characters = vis


func _input(event: InputEvent) -> void:
	if not _waiting_key_action.is_empty() and sys_menu_panel != null and sys_menu_panel.visible and _current_sys_page == "keys":
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			if event.keycode == KEY_ESCAPE:
				_waiting_key_action = ""
				_key_notice_override = ""
				_rebuild_sys_page()
				return
			var key_str := OS.get_keycode_string(event.keycode)
			if key_str.is_empty() or _cfg == null:
				return
			for k in _cfg.key_bindings.keys():
				if k != _waiting_key_action and str(_cfg.key_bindings[k]).to_upper() == key_str.to_upper():
					_key_notice_override = "按键 [%s] 已被其他功能占用，无法重复设置同一按键。" % key_str
					_waiting_key_action = ""
					_rebuild_sys_page()
					return
			_cfg.key_bindings[_waiting_key_action] = key_str
			_cfg.save_config()
			_waiting_key_action = ""
			_key_notice_override = ""
			config_changed.emit()
			_rebuild_sys_page()


func setup(cfg: ConfigManager, font: Font = null, vfs: BgiVfs = null) -> void:
	_cfg = cfg
	_font_base = font
	_font = font
	_vfs = vfs
	theme_loader.setup(_vfs)

	apply_text_font()

	if _cfg != null:
		if _family_input != null:
			_family_input.text = _cfg.player_family_name
		if _given_input != null:
			_given_input.text = _cfg.player_given_name

	_apply_runtime_textures()
	if gallery_panel != null:
		gallery_panel.setup(theme_loader, _vfs, _font)
	_apply_dialogue_opacity()
	if sys_menu_panel != null and sys_menu_panel.visible:
		_rebuild_sys_page()


func _resolve_active_font() -> Font:
	if _cfg == null:
		return _font_base
	var fname := _cfg.font_name
	if fname.contains("YouYuan"):
		if not _font_cache.has("youyuan"):
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["YouYuan", "幼圆", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei UI", "Microsoft YaHei"])
			_font_cache["youyuan"] = sf
		return _font_cache["youyuan"]
	elif fname.contains("SimSun"):
		if not _font_cache.has("simsun"):
			var sf2 := SystemFont.new()
			sf2.font_names = PackedStringArray(["SimSun", "宋体", "NSimSun", "Songti SC", "STSong", "Noto Serif CJK SC"])
			_font_cache["simsun"] = sf2
		return _font_cache["simsun"]
	return _font_base


func apply_text_font() -> void:
	_font = _resolve_active_font()
	if _font != null:
		if speaker_label != null:
			speaker_label.add_theme_font_override("font", _font)
		if dialogue_label != null:
			dialogue_label.add_theme_font_override("normal_font", _font)
		if log_text != null:
			log_text.add_theme_font_override("normal_font", _font)
		if bgm_telop_label != null:
			bgm_telop_label.add_theme_font_override("font", _font)
		if _family_input != null:
			_family_input.add_theme_font_override("font", _font)
		if _given_input != null:
			_given_input.add_theme_font_override("font", _font)
		if _preview_sample_label != null:
			_preview_sample_label.add_theme_font_override("normal_font", _font)
	if gallery_panel != null and _vfs != null:
		gallery_panel.setup(theme_loader, _vfs, _font)


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
		_name_bg_rect.visible = false # PC 原版直接绘制白字黑描边于对白框左上角
	var t_auto := theme_loader.get_tex("sgmsgwnd500000")
	if t_auto != null:
		_auto_badge.texture = t_auto
	var t_skip := theme_loader.get_tex("sgmsgwnd500100")
	if t_skip != null:
		_skip_badge.texture = t_skip

	# 右下角三层金字塔快捷按钮贴图
	var quick_tex_map := {
		"BtnAuto": ["sgmsgwnd000000", "sgmsgwnd000001"],
		"BtnSkip": ["sgmsgwnd000100", "sgmsgwnd000101"],
		"BtnVoiceReplay": ["sgmsgwnd000200", "sgmsgwnd000201"],
		"BtnHideUi": ["sgmsgwnd000300", "sgmsgwnd000301"],
		"BtnQuickSave": ["sgmsgwnd000400", "sgmsgwnd000401"],
		"BtnQuickLoad": ["sgmsgwnd000500", "sgmsgwnd000501"],
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

	# 系统菜单右侧常驻导航栏与初始化按钮贴图（VFS 仅含 01 高亮态，普通态由底图烘焙按钮提供）
	for k in _sys_nav_map.keys():
		var nb := _sys_nav_map[k] as TextureButton
		if nb != null:
			var idx: int = int(nb.get_meta("nav_idx", 0))
			var tex_hl := theme_loader.get_tex("sgsyswnd00%02d01" % idx)
			nb.texture_normal = null
			nb.texture_hover = tex_hl
			nb.texture_pressed = tex_hl
			for c in nb.get_children():
				if c is Label:
					c.visible = (tex_hl == null)
	if _sys_init_btn is TextureButton:
		var ib := _sys_init_btn as TextureButton
		var tex_init := theme_loader.get_tex("sgsyswnd001001")
		ib.texture_normal = null
		ib.texture_hover = tex_init
		ib.texture_pressed = tex_init
		for c in ib.get_children():
			if c is Label:
				c.visible = (tex_init == null)

	# Log 背景贴图
	var log_bg := log_panel.find_child("LogBgRect", true, false) as TextureRect
	if log_bg != null:
		var t_log := theme_loader.get_tex("sglogwnd990000")
		if t_log != null:
			log_bg.texture = t_log

	# 姓名输入贴图 (sgnminpt990000, sgnminpt000000, sgnminpt000100)
	if _name_bg_tex_rect != null:
		var t_nm := theme_loader.get_tex("sgnminpt990000")
		if t_nm != null:
			_name_bg_tex_rect.texture = t_nm
			_name_bg_tex_rect.visible = true
	if _btn_name_default != null:
		theme_loader.apply_button_textures(_btn_name_default, "sgnminpt000000", "sgnminpt000001", "sgnminpt000001")
		for c in _btn_name_default.get_children():
			if c is Label:
				c.visible = (_btn_name_default.texture_normal == null)
	if _btn_name_done != null:
		theme_loader.apply_button_textures(_btn_name_done, "sgnminpt000100", "sgnminpt000101", "sgnminpt000101")
		for c in _btn_name_done.get_children():
			if c is Label:
				c.visible = (_btn_name_done.texture_normal == null)

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
	_close_all_modals(true)
	_sys_in_game = false
	dialogue_panel.visible = false
	quick_menu.visible = false
	_auto_badge.visible = false
	_skip_badge.visible = false
	_badge_fallback.visible = false
	if bgm_telop_banner != null:
		bgm_telop_banner.visible = false
	title_overlay.visible = true
	if _title_op_btn != null:
		_title_op_btn.visible = has_movie


func hide_title_menu() -> void:
	title_overlay.visible = false
	_close_all_modals(true)
	_sys_in_game = true
	quick_menu.visible = true


func set_dialogue(
	text: String,
	speaker: String,
	voice_entry: String = "",
	snapshot: Dictionary = {},
	is_read: bool = false,
	face_img: String = ""
) -> void:
	dialogue_panel.visible = true
	quick_menu.visible = true
	_name_plate.visible = not speaker.is_empty()
	speaker_label.visible = not speaker.is_empty()
	speaker_label.text = speaker
	dialogue_label.text = text
	_last_is_read = is_read
	_last_face_img = face_img

	if _cfg != null:
		var col := _cfg.read_text_color if is_read else _cfg.text_color
		dialogue_label.add_theme_color_override("default_color", col)

	_update_face_avatar()

	# 打字机初始化
	_typing_total_chars = dialogue_label.get_total_character_count()
	if _typing_total_chars <= 0:
		_typing_total_chars = text.length()
	var speed := _cfg.text_speed if _cfg != null else 60.0
	if DisplayServer.get_name() == "headless" or speed <= 0.0 or speed >= 115.0:
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


func _update_face_avatar() -> void:
	if face_avatar_rect == null:
		return
	var show_face := (_cfg == null or _cfg.face_window_mode == 0) and not _last_face_img.is_empty()
	if show_face and theme_loader.has_vfs():
		var ftex := theme_loader.get_tex(_last_face_img)
		if ftex != null:
			face_avatar_rect.texture = ftex
			face_avatar_rect.visible = true
			return
	face_avatar_rect.visible = false


func show_bgm_telop(bgm_name: String) -> void:
	if bgm_telop_banner == null or _cfg == null:
		return
	if _cfg.bgm_telop_mode <= 0 or bgm_name.is_empty():
		bgm_telop_banner.visible = false
		return
	var title := bgm_name
	var low := bgm_name.to_lower()
	if low.begins_with("fl_bgm_"):
		var num_str := low.trim_prefix("fl_bgm_")
		if num_str.is_valid_int():
			var idx := num_str.to_int() - 1
			if idx >= 0 and idx < _GalleryPanel.BGM_TITLES_ZH.size():
				title = _GalleryPanel.BGM_TITLES_ZH[idx]
	bgm_telop_label.text = "♪ " + title
	bgm_telop_banner.visible = true
	bgm_telop_banner.modulate.a = 1.0
	if _telop_tween != null and _telop_tween.is_valid():
		_telop_tween.kill()
	if _cfg.bgm_telop_mode == 3:
		return
	var hold_sec := 2.0 if _cfg.bgm_telop_mode == 1 else 4.0
	if is_inside_tree():
		_telop_tween = create_tween()
		_telop_tween.tween_interval(hold_sec)
		_telop_tween.tween_property(bgm_telop_banner, "modulate:a", 0.0, 0.4)
		_telop_tween.tween_callback(func() -> void: bgm_telop_banner.visible = false)


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
		btn_nude_quick.button_pressed = enabled
		btn_nude_quick.modulate = Color(1.0, 0.55, 0.78, 1.0) if enabled else Color(1.0, 1.0, 1.0, 0.92)
		btn_nude_quick.tooltip_text = "F12 透视差分: 开启" if enabled else "F12 透视差分: 关闭"


func set_auto_state(enabled: bool) -> void:
	if btn_auto != null:
		btn_auto.set_pressed_no_signal(enabled)
	_auto_badge.visible = enabled
	_update_badge_fallback()


func set_skip_state(enabled: bool) -> void:
	if btn_skip != null:
		btn_skip.set_pressed_no_signal(enabled)
	_skip_badge.visible = enabled
	_update_badge_fallback()


func show_notice(msg: String, duration_sec: float = 2.4) -> void:
	## 在屏幕上方展示非阻塞状态提示（例如“仅已读模式下不可跳过未读对白”）。
	if _notice_banner == null or _notice_label == null or msg.is_empty():
		return
	_notice_label.text = msg
	_notice_banner.visible = true
	_notice_banner.modulate.a = 1.0
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	if is_inside_tree():
		_notice_tween = create_tween()
		_notice_tween.tween_interval(maxf(0.5, duration_sec))
		_notice_tween.tween_property(_notice_banner, "modulate:a", 0.0, 0.35)
		_notice_tween.tween_callback(func() -> void: _notice_banner.visible = false)


func is_point_in_quick_menu_buttons(global_pos: Vector2) -> bool:
	## 判断坐标是否落在右下角快捷按钮区域内，用于阻止触摸抬起穿透触发推进或打断跳过。
	if quick_menu == null or not quick_menu.is_visible_in_tree():
		return false
	for child in quick_menu.get_children():
		if child is BaseButton and child.visible:
			var rect := (child as Control).get_global_rect()
			if rect.has_point(global_pos):
				return true
	return false


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
		choice_vbox.remove_child(c)
		c.queue_free()
	var title := Label.new()
	var kind_label := "请选择对话分支"
	if kind.begins_with("_SelectEx:"):
		kind_label = kind.substr("_SelectEx:".length())
	elif kind == "_SelectEx":
		kind_label = "请选择"
	elif kind == "SelectTalk":
		kind_label = "恋爱对话窗 (TalkWindow) - 请选择话题"
	elif kind == "SelectTopic":
		kind_label = "话题选择 (Topic)"
	elif kind == "SelectMail":
		kind_label = "手机短信 (Mail) - 请选择回复"
	title.text = kind_label
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	choice_vbox.add_child(title)

	if options.is_empty():
		options = ["继续剧情"]
	var slct_tex := theme_loader.get_tex("sgslctwnd990000")
	for i in range(options.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(560, 58)
		b.text = str(options[i])
		if _font != null:
			b.add_theme_font_override("font", _font)
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
	if _cfg != null and _cfg.cursor_auto_move:
		var first_btn: Button = null
		for child in choice_vbox.get_children():
			if child is Button:
				first_btn = child
				break
		if first_btn != null:
			call_deferred("_auto_move_cursor_to", first_btn)


func has_open_modal() -> bool:
	return (
		modal_backdrop.visible
		or title_overlay.visible
		or sys_menu_panel.visible
		or log_panel.visible
		or gallery_panel.visible
		or (choice_panel != null and choice_panel.visible)
		or (byoa_panel != null and byoa_panel.visible)
		or _confirm_overlay.visible
		or (_name_input_overlay != null and _name_input_overlay.visible)
		or (_prologue_skip_overlay != null and _prologue_skip_overlay.visible)
	)


## 判断是否存在可通过 ESC 或返回键关闭的子弹窗（不含标题主覆盖层、缺省资源引导弹窗与剧情选项弹窗）
func has_closable_submodal() -> bool:
	return (
		sys_menu_panel.visible
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
	_waiting_key_action = ""
	_close_all_modals()
	_refresh_sys_nav_state()
	_switch_sys_page(page_key)
	sys_menu_panel.visible = true
	modal_backdrop.visible = true


func show_confirm(dialog_tex_entry: String, fallback_msg: String, on_yes: Callable, mode_type: String = "") -> void:
	if _cfg != null:
		if mode_type == "qsave" and not _cfg.confirm_qsave:
			on_yes.call()
			return
		elif mode_type == "qload" and not _cfg.confirm_qload:
			on_yes.call()
			return
		elif mode_type.is_empty() and not _cfg.confirm_dialogs:
			on_yes.call()
			return
	_confirm_callback = on_yes
	var t: ImageTexture = theme_loader.get_tex(dialog_tex_entry) if not dialog_tex_entry.is_empty() else null
	var fb := _confirm_overlay.get_node_or_null("ConfirmFallbackCard")
	if t != null:
		_confirm_bg_rect.texture = t
		_confirm_bg_rect.visible = true
		if fb != null:
			fb.visible = false
		_confirm_msg_lbl.visible = false
	else:
		_confirm_bg_rect.visible = false
		if fb != null:
			fb.visible = true
		_confirm_msg_lbl.text = fallback_msg
		_confirm_msg_lbl.visible = true
	_confirm_overlay.visible = true
	modal_backdrop.visible = true
	if _cfg != null and _cfg.cursor_auto_move and _confirm_yes_btn != null:
		call_deferred("_auto_move_cursor_to", _confirm_yes_btn)


func _auto_move_cursor_to(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
		return
	ctrl.grab_focus()
	if DisplayServer.get_name() != "headless" and get_viewport() != null:
		var target_pos := ctrl.get_global_rect().get_center()
		get_viewport().warp_mouse(target_pos)


func save_game_to_slot(slot: int, payload: Dictionary, shot_img: Image = null) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var existing := load_game_from_slot(slot)
	if not payload.has("comment") and existing.has("comment"):
		payload["comment"] = existing["comment"]
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


func get_slot_comment(slot: int) -> String:
	var data := load_game_from_slot(slot)
	return str(data.get("comment", ""))


func set_slot_comment(slot: int, comment: String) -> void:
	var data := load_game_from_slot(slot)
	if data.is_empty():
		return
	data["comment"] = comment
	var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


# ==============================================================================
# 对白框、左上角 BGM 横幅、右下角三层金字塔快捷按钮簇（对齐 QQ20261115-124219.png）
# ==============================================================================
func _build_dialogue_box() -> void:
	dialogue_panel = Control.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.visible = false

	_msg_bg_rect = TextureRect.new()
	_msg_bg_rect.position = Vector2(0, 480)
	_msg_bg_rect.size = Vector2(1280, 240)
	_msg_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_msg_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_msg_bg_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	_msg_bg_rect.visible = false
	dialogue_panel.add_child(_msg_bg_rect)

	_msg_fallback_bg = Panel.new()
	_msg_fallback_bg.position = Vector2(24, 510)
	_msg_fallback_bg.size = Vector2(1232, 194)
	_msg_fallback_bg.mouse_filter = Control.MOUSE_FILTER_PASS
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.34, 0.68, 0.86)
	st.border_color = Color(0.75, 0.9, 1.0, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(18)
	_msg_fallback_bg.add_theme_stylebox_override("panel", st)
	dialogue_panel.add_child(_msg_fallback_bg)

	# 左侧角色表情小头像（当显示文字框设为「通常」时显示）
	face_avatar_rect = TextureRect.new()
	face_avatar_rect.name = "FaceAvatar"
	face_avatar_rect.position = Vector2(165, 508)
	face_avatar_rect.size = Vector2(160, 190)
	face_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face_avatar_rect.visible = false
	dialogue_panel.add_child(face_avatar_rect)

	# 姓名栏（精确对齐 PC 截图 124219：x=412, y=508，保持日文原名，白字黑描边）
	_name_plate = Control.new()
	_name_plate.position = Vector2(412, 508)
	_name_plate.size = Vector2(360, 38)
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
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.add_theme_font_size_override("font_size", 25)
	speaker_label.add_theme_color_override("font_color", Color.WHITE)
	speaker_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.98))
	speaker_label.add_theme_constant_override("outline_size", 3)
	_name_plate.add_child(speaker_label)

	# 对白正文区（对齐 PC 截图 124219：x=380, y=556，白字黑描边）
	dialogue_label = RichTextLabel.new()
	dialogue_label.position = Vector2(380, 556)
	dialogue_label.size = Vector2(720, 146)
	dialogue_label.add_theme_font_size_override("normal_font_size", 26)
	dialogue_label.add_theme_color_override("default_color", Color.WHITE)
	dialogue_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.98))
	dialogue_label.add_theme_constant_override("outline_size", 3)
	dialogue_label.fit_content = false
	dialogue_label.scroll_active = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.add_child(dialogue_label)

	var click_handler := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			# 忽略触控模拟产生的鼠标点击，防止与 MobileGestureHelper 双发跳句或打断快进
			if ev.device == MobileGestureHelper.DEVICE_ID_EMULATION:
				return
			if ev.button_index == MOUSE_BUTTON_LEFT:
				advance_requested.emit()
				var vp := get_viewport()
				if vp != null:
					vp.set_input_as_handled()
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


func _build_bgm_telop_banner() -> void:
	bgm_telop_banner = Panel.new()
	bgm_telop_banner.name = "BgmTelopBanner"
	bgm_telop_banner.position = Vector2(20, 20)
	bgm_telop_banner.size = Vector2(420, 38)
	bgm_telop_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgm_telop_banner.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.28, 0.86)
	sb.border_color = Color(0.45, 0.72, 0.98, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	bgm_telop_banner.add_theme_stylebox_override("panel", sb)
	add_child(bgm_telop_banner)

	bgm_telop_label = Label.new()
	bgm_telop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgm_telop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bgm_telop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bgm_telop_label.add_theme_font_size_override("font_size", 18)
	bgm_telop_label.add_theme_color_override("font_color", Color.WHITE)
	bgm_telop_banner.add_child(bgm_telop_label)


func _build_notice_banner() -> void:
	_notice_banner = Panel.new()
	_notice_banner.name = "NoticeBanner"
	_notice_banner.position = Vector2(300, 18)
	_notice_banner.size = Vector2(680, 40)
	_notice_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_banner.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.20, 0.30, 0.90)
	sb.border_color = Color(0.95, 0.78, 0.36, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	_notice_banner.add_theme_stylebox_override("panel", sb)
	add_child(_notice_banner)

	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 17)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82))
	_notice_banner.add_child(_notice_label)


func _build_quick_menu() -> void:
	# 1:1 还原 PC 截图 QQ20261115-124219.png 右下角三层金字塔圆形快捷按钮簇
	quick_menu = Control.new()
	quick_menu.name = "QuickMenu"
	quick_menu.position = Vector2(1010, 540)
	quick_menu.size = Vector2(266, 176)
	quick_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quick_menu.visible = false
	add_child(quick_menu)

	# 第 1 层 (y=18): Auto (▶), Skip (▶▶)
	var b_auto := _make_round_icon_btn("BtnAuto", "▶", true)
	b_auto.position = Vector2(134, 18)
	b_auto.size = Vector2(46, 46)
	b_auto.tooltip_text = "自动模式 (A)"
	b_auto.toggled.connect(func(on: bool) -> void: auto_toggled.emit(on))
	quick_menu.add_child(b_auto)
	btn_auto = b_auto

	var b_skip := _make_round_icon_btn("BtnSkip", "▶▶", true)
	b_skip.position = Vector2(186, 18)
	b_skip.size = Vector2(46, 46)
	b_skip.tooltip_text = "快进模式 (R)"
	b_skip.toggled.connect(func(on: bool) -> void: skip_toggled.emit(on))
	quick_menu.add_child(b_skip)
	btn_skip = b_skip

	# 第 2 层 (y=70): VoiceReplay (◀◀), SysCfg (⚙), HideUi (✕)
	var btn_rep := _make_round_icon_btn("BtnVoiceReplay", "◀◀")
	btn_rep.position = Vector2(108, 70)
	btn_rep.size = Vector2(46, 46)
	btn_rep.tooltip_text = "重播当前语音"
	btn_rep.pressed.connect(func() -> void: voice_replay_requested.emit(""))
	quick_menu.add_child(btn_rep)

	var btn_cfg := _make_round_icon_btn("BtnSysCfg", "⚙")
	btn_cfg.position = Vector2(160, 70)
	btn_cfg.size = Vector2(46, 46)
	btn_cfg.tooltip_text = "系统设置菜单"
	btn_cfg.pressed.connect(func() -> void: open_system_menu("display", _sys_in_game))
	quick_menu.add_child(btn_cfg)

	var btn_hide := _make_round_icon_btn("BtnHideUi", "✕")
	btn_hide.position = Vector2(212, 70)
	btn_hide.size = Vector2(46, 46)
	btn_hide.tooltip_text = "隐藏对白框"
	btn_hide.pressed.connect(toggle_dialogue_visibility)
	quick_menu.add_child(btn_hide)

	# 第 3 层 (y=122): 历史 (LOG), ♥ (F12 透视/收藏), Q.S, Q.L
	var btn_log := _make_pill_btn("历史", Vector2(54, 38))
	btn_log.position = Vector2(12, 126)
	btn_log.focus_mode = Control.FOCUS_NONE
	btn_log.pressed.connect(_open_log_panel)
	quick_menu.add_child(btn_log)

	btn_nude_quick = Button.new()
	btn_nude_quick.name = "BtnHeartNude"
	btn_nude_quick.text = "♥"
	btn_nude_quick.toggle_mode = true
	btn_nude_quick.focus_mode = Control.FOCUS_NONE
	btn_nude_quick.position = Vector2(74, 124)
	btn_nude_quick.size = Vector2(44, 42)
	btn_nude_quick.add_theme_font_size_override("font_size", 22)
	btn_nude_quick.add_theme_color_override("font_color", Color.WHITE)
	var h_sb := StyleBoxFlat.new()
	h_sb.bg_color = Color(0.35, 0.55, 0.78, 0.45)
	h_sb.set_corner_radius_all(20)
	btn_nude_quick.add_theme_stylebox_override("normal", h_sb)
	btn_nude_quick.add_theme_stylebox_override("hover", h_sb)
	btn_nude_quick.add_theme_stylebox_override("pressed", h_sb)
	btn_nude_quick.pressed.connect(func() -> void: nude_quick_toggled.emit())
	quick_menu.add_child(btn_nude_quick)

	var btn_qs := _make_round_icon_btn("BtnQuickSave", "Q.S")
	btn_qs.position = Vector2(134, 122)
	btn_qs.size = Vector2(46, 46)
	btn_qs.tooltip_text = "快速存档 (Q.S)"
	btn_qs.pressed.connect(func() -> void:
		show_confirm("sgdialog990004", "确定快速存档吗？", func() -> void: quick_save_requested.emit(), "qsave")
	)
	quick_menu.add_child(btn_qs)

	var btn_ql := _make_round_icon_btn("BtnQuickLoad", "Q.L")
	btn_ql.position = Vector2(186, 122)
	btn_ql.size = Vector2(46, 46)
	btn_ql.tooltip_text = "快速读档 (Q.L)"
	btn_ql.pressed.connect(func() -> void:
		show_confirm("sgdialog990005", "确定快速读档吗？", func() -> void: quick_load_requested.emit(), "qload")
	)
	quick_menu.add_child(btn_ql)


func _make_round_icon_btn(node_name: String, fallback_txt: String, toggle: bool = false) -> TextureButton:
	var b := TextureButton.new()
	b.name = node_name
	b.toggle_mode = toggle
	# 禁用焦点获取，避免点击快捷按钮后按下空格/回车再次误触按钮本身
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 46)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var lbl := Label.new()
	lbl.text = fallback_txt
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	b.add_child(lbl)
	return b


func _make_pill_btn(txt: String, sz: Vector2, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = txt
	b.toggle_mode = toggle
	b.custom_minimum_size = sz
	if _font != null:
		b.add_theme_font_override("font", _font)
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


# ==============================================================================
# 标题界面 (Title Screen)
# ==============================================================================
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
		0:
			_open_new_game_flow()
		1:
			open_system_menu("load", false)
		2:
			open_system_menu("display", false)
		3:
			if gallery_panel != null:
				gallery_panel.open_gallery(_title_op_btn != null and _title_op_btn.visible)
		4:
			show_confirm("sgdialog990000", "确定结束游戏?", func() -> void: quit_game_requested.emit())


func _open_new_game_flow() -> void:
	if _name_input_overlay != null:
		if _cfg != null:
			_family_input.text = _cfg.player_family_name
			_given_input.text = _cfg.player_given_name
		_name_input_overlay.visible = true
		modal_backdrop.visible = true
	else:
		start_new_game_requested.emit()


# ==============================================================================
# 弹窗与一体化系统窗口（画面/文本/声音/系统/快捷键/存档/读档 7 大页）
# ==============================================================================
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
	gallery_panel.recollection_requested.connect(func(sc: String, app: int) -> void:
		recollection_requested.emit(sc, app)
	)
	# 从标题进入鉴赏模式点击返回后，刷新遮罩并确保标题覆盖层可见
	gallery_panel.close_requested.connect(func() -> void:
		if not _sys_in_game and title_overlay != null:
			title_overlay.visible = true
		_refresh_backdrop()
	)
	add_child(gallery_panel)

	_build_confirm_dialog()


func _build_system_menu() -> void:
	sys_menu_panel = Control.new()
	sys_menu_panel.name = "SystemMenuPanel"
	sys_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sys_menu_panel.visible = false
	add_child(sys_menu_panel)

	var fallback_bg := ColorRect.new()
	fallback_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback_bg.color = Color(0.55, 0.78, 0.96, 1.0)
	sys_menu_panel.add_child(fallback_bg)

	_sys_bg_rect = TextureRect.new()
	_sys_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sys_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sys_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	sys_menu_panel.add_child(_sys_bg_rect)

	# 兼容旧引用属性 save_load_panel / config_panel
	save_load_panel = Control.new()
	save_load_panel.name = "SaveLoadPanel"
	save_load_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	save_load_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_load_panel.visible = false
	sys_menu_panel.add_child(save_load_panel)

	config_panel = Control.new()
	config_panel.name = "ConfigPanel"
	config_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	config_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	config_panel.visible = false
	sys_menu_panel.add_child(config_panel)

	# 顶部与底部 Help 简体中文覆盖栏（精确遮盖原盘底图烘焙的「Help: + 日文说明」）
	_sys_top_help_panel = Panel.new()
	_sys_top_help_panel.name = "TopHelpPanel"
	_sys_top_help_panel.position = Vector2(474, 15)
	_sys_top_help_panel.size = Vector2(800, 30)
	var th_sb := StyleBoxFlat.new()
	th_sb.bg_color = Color8(0, 98, 178, 255)
	th_sb.set_corner_radius_all(10)
	_sys_top_help_panel.add_theme_stylebox_override("panel", th_sb)
	sys_menu_panel.add_child(_sys_top_help_panel)

	_sys_top_help_lbl = Label.new()
	_sys_top_help_lbl.position = Vector2(14, 0)
	_sys_top_help_lbl.size = Vector2(776, 30)
	_sys_top_help_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sys_top_help_lbl.add_theme_font_size_override("font_size", 17)
	_sys_top_help_lbl.add_theme_color_override("font_color", Color.WHITE)
	_sys_top_help_panel.add_child(_sys_top_help_lbl)

	_sys_bot_help_panel = Panel.new()
	_sys_bot_help_panel.name = "BotHelpPanel"
	_sys_bot_help_panel.position = Vector2(34, 658)
	_sys_bot_help_panel.size = Vector2(980, 54)
	var bh_sb := StyleBoxFlat.new()
	bh_sb.bg_color = Color(0.01, 0.30, 0.66, 1.0)
	bh_sb.set_corner_radius_all(8)
	_sys_bot_help_panel.add_theme_stylebox_override("panel", bh_sb)
	sys_menu_panel.add_child(_sys_bot_help_panel)

	_sys_bot_help_lbl = Label.new()
	_sys_bot_help_lbl.position = Vector2(18, 0)
	_sys_bot_help_lbl.size = Vector2(950, 54)
	_sys_bot_help_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sys_bot_help_lbl.add_theme_font_size_override("font_size", 18)
	_sys_bot_help_lbl.add_theme_color_override("font_color", Color.WHITE)
	_sys_bot_help_panel.add_child(_sys_bot_help_lbl)

	# 动态子页面容器
	_sys_content_root = Control.new()
	_sys_content_root.name = "SysContentRoot"
	_sys_content_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sys_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sys_menu_panel.add_child(_sys_content_root)

	# 右侧 10 个原版导航按钮 (精确对齐原盘 x=1078, w=202, h=44, y=58..548)
	var nav_defs := [
		{"key": "display", "idx": 0, "label": "画面设置", "y": 58},
		{"key": "text", "idx": 1, "label": "文本设置", "y": 108},
		{"key": "sound", "idx": 2, "label": "声音设置", "y": 158},
		{"key": "system", "idx": 3, "label": "系统设置", "y": 208},
		{"key": "keys", "idx": 4, "label": "快捷键设置", "y": 258},
		{"key": "save", "idx": 5, "label": "存档", "y": 328},
		{"key": "load", "idx": 6, "label": "读档", "y": 378},
		{"key": "back_game", "idx": 7, "label": "返回游戏", "y": 448},
		{"key": "back_title", "idx": 8, "label": "返回标题", "y": 498},
		{"key": "quit", "idx": 9, "label": "结束游戏", "y": 548},
	]
	_sys_nav_buttons.clear()
	_sys_nav_map.clear()
	for nd in nav_defs:
		var nb := TextureButton.new()
		var k := str(nd["key"])
		var idx: int = int(nd["idx"])
		nb.name = "SysNav_%s" % k
		nb.position = Vector2(1078, int(nd["y"]))
		nb.size = Vector2(202, 44)
		nb.ignore_texture_size = true
		nb.stretch_mode = TextureButton.STRETCH_SCALE
		nb.set_meta("nav_key", k)
		nb.set_meta("nav_idx", idx)
		var lbl := Label.new()
		lbl.text = str(nd["label"])
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 18)
		nb.add_child(lbl)
		nb.pressed.connect(func() -> void: _on_sys_nav_pressed(k))
		sys_menu_panel.add_child(nb)
		_sys_nav_buttons.append(nb)
		_sys_nav_map[k] = nb

	# 右下角「初始化」按钮 (精确对齐原盘 x=1078, y=648, 202x44)
	var ib := TextureButton.new()
	ib.name = "SysNav_reset"
	ib.position = Vector2(1078, 648)
	ib.size = Vector2(202, 44)
	ib.ignore_texture_size = true
	ib.stretch_mode = TextureButton.STRETCH_SCALE
	ib.set_meta("nav_key", "reset")
	var ilbl := Label.new()
	ilbl.text = "初始化"
	ilbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ilbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ilbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ilbl.add_theme_font_size_override("font_size", 18)
	ib.add_child(ilbl)
	ib.pressed.connect(func() -> void: _on_sys_nav_pressed("reset"))
	sys_menu_panel.add_child(ib)
	_sys_init_btn = ib
	_sys_nav_buttons.append(ib)


func _on_sys_nav_pressed(key: String) -> void:
	match key:
		"display", "text", "sound", "system", "keys", "save", "load":
			_switch_sys_page(key)
		"back_game":
			if _cfg != null:
				_cfg.save_config()
			config_changed.emit()
			_close_all_modals()
			# 从标题进入设置或读档时，「返回游戏」同样应安全关闭设置页并恢复标题界面
			if not _sys_in_game and title_overlay != null:
				title_overlay.visible = true
		"back_title":
			if not _sys_in_game:
				# 已经在标题界面进入设置时，直接保存配置、关闭设置页并确保标题界面可见
				if _cfg != null:
					_cfg.save_config()
				config_changed.emit()
				_close_all_modals()
				if title_overlay != null:
					title_overlay.visible = true
			else:
				show_confirm("sgdialog990001", "确定回到标题？", func() -> void:
					_close_all_modals()
					return_to_title_requested.emit()
				)
		"quit":
			show_confirm("sgdialog990000", "确定结束游戏?", func() -> void: quit_game_requested.emit())
		"reset":
			show_confirm("", "确定要将设置恢复为初始默认值吗？", func() -> void:
				if _cfg != null:
					_cfg.reset_to_defaults()
					_cfg.save_config()
					apply_text_font()
					_apply_dialogue_opacity()
					config_changed.emit()
					_rebuild_sys_page()
			)


func _refresh_sys_nav_state() -> void:
	# 未进入正文前仅禁用「存档」，确保「返回游戏」「返回标题」在标题->设置/读档路径下始终可点击
	var save_btn := _sys_nav_map.get("save") as BaseButton
	if save_btn != null:
		save_btn.disabled = not _sys_in_game
		save_btn.modulate.a = 1.0 if _sys_in_game else 0.55
	for k in ["back_game", "back_title"]:
		var nb := _sys_nav_map.get(k) as BaseButton
		if nb != null:
			nb.disabled = false
			nb.modulate.a = 1.0


func _switch_sys_page(key: String) -> void:
	_current_sys_page = key
	_waiting_key_action = ""
	_key_notice_override = ""
	_is_save_mode = (key == "save")
	save_load_panel.visible = (key == "save" or key == "load")
	config_panel.visible = not save_load_panel.visible
	_rebuild_sys_page()


func _rebuild_sys_page() -> void:
	if _sys_content_root == null:
		return
	for c in _sys_content_root.get_children():
		_sys_content_root.remove_child(c)
		c.queue_free()

	if _font != null:
		_sys_top_help_lbl.add_theme_font_override("font", _font)
		_sys_bot_help_lbl.add_theme_font_override("font", _font)

	var bg_map := {
		"display": "sgcnfgdsp990000",
		"text": "sgcnfgtxt990000",
		"sound": "sgcnfgsnd990000",
		"system": "sgcnfgsys990000",
		"keys": "sgcnfgkey990000",
		"save": "sgusdtwnd990000",
		"load": "sgusdtwnd990001",
	}
	var bg_key: String = bg_map.get(_current_sys_page, "sgcnfgdsp990000")
	var bg_tex := theme_loader.get_tex(bg_key)
	if bg_tex != null:
		_sys_bg_rect.texture = bg_tex

	var is_save_or_load := (_current_sys_page == "save" or _current_sys_page == "load")
	if _sys_init_btn != null:
		_sys_init_btn.visible = not is_save_or_load
	if _sys_top_help_panel != null:
		_sys_top_help_panel.visible = not is_save_or_load

	var bh_sb := StyleBoxFlat.new()
	bh_sb.set_corner_radius_all(8)
	if is_save_or_load:
		bh_sb.bg_color = Color8(136, 29, 29, 255)
	else:
		bh_sb.bg_color = Color8(0, 71, 157, 255)
	_sys_bot_help_panel.add_theme_stylebox_override("panel", bh_sb)

	# 更新右侧导航按钮选中态贴图（原盘底图与 VFS 贴图均已含清晰简体中文，仅无 VFS 时显示备用文本 Label）
	var has_vfs_tex := theme_loader.has_vfs()
	if _sys_init_btn != null and _sys_init_btn.get_child_count() > 0:
		var init_lbl := _sys_init_btn.get_child(0) as Control
		if init_lbl != null:
			init_lbl.visible = not has_vfs_tex
	for k in _sys_nav_map.keys():
		var nb := _sys_nav_map[k] as TextureButton
		if nb != null:
			if nb.get_child_count() > 0:
				var nb_lbl := nb.get_child(0) as Control
				if nb_lbl != null:
					nb_lbl.visible = not has_vfs_tex
			if has_vfs_tex:
				var idx: int = int(nb.get_meta("nav_idx", 0))
				nb.texture_normal = theme_loader.get_tex("sgsyswnd00%02d01" % idx) if k == _current_sys_page else null

	if _cfg == null:
		return

	match _current_sys_page:
		"display":
			_sys_top_help_lbl.text = "Help:  进行窗口透明度、头像框显示等与游戏画面相关的设置。"
			_sys_bot_help_lbl.text = "Help:  设置画面尺寸为「全屏」时的宽屏缩放方式、对话框透明度及曲名显示时间。"
			_build_tab_display()
		"text":
			_sys_top_help_lbl.text = "Help:  进行字体选择、文本颜色、快进规则等与游戏内文字显示相关的设置。"
			_sys_bot_help_lbl.text = "Help:  设置对话文字显示速度、自动模式速度、语音停止时机与调色板文字颜色。"
			_build_tab_text()
		"sound":
			_sys_top_help_lbl.text = "Help:  进行 BGM、效果音及各角色语音音量的调节设置。"
			_sys_bot_help_lbl.text = "Help:  可整体调节 BGM、效果音与语音音量，或点击右侧角色名称单独调节角色音量。"
			_build_tab_sound()
		"system":
			_sys_top_help_lbl.text = "Help:  进行鼠标按键功能分配、快速存读档确认等与系统操作相关的设置。"
			_sys_bot_help_lbl.text = "Help:  点击「右键 / 滚轮↑ / 滚轮↓」后，可在右侧「选择分配功能」框中指定对应快捷功能。"
			_build_tab_system()
		"keys":
			_sys_top_help_lbl.text = "Help:  进行键盘快捷键的查看与自定义绑定设置。"
			_sys_bot_help_lbl.text = "Help:  快捷键可更改为任意按键。请点击想要更改的蓝色按键框并按下新的键盘按键。"
			_build_tab_keys()
		"save":
			_sys_bot_help_lbl.text = "Help:  点击槽位可执行存档，点击右侧详细信息的备注框可编辑存档备注内容。"
			_build_tab_save_load(true)
		"load":
			_sys_bot_help_lbl.text = "Help:  点击槽位可读取存档，点击右侧详细信息的备注框可编辑存档备注内容。"
			_build_tab_save_load(false)


# ==============================================================================
# 1. 画面设置 (Display - QQ20261115-123928.png)
# ==============================================================================
func _build_tab_display() -> void:
	_add_sky_mask(Vector2(240, 86), Vector2(364, 424))

	# 1) 画面尺寸：全屏 / 1280 × 720
	_add_option_choice("全屏", Vector2(256, 97), _cfg.fullscreen, func() -> void:
		_cfg.fullscreen = true
		_cfg.save_config()
		_apply_window_mode()
		config_changed.emit()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(404, 97))
	_add_option_choice("1280 × 720", Vector2(436, 97), not _cfg.fullscreen, func() -> void:
		_cfg.fullscreen = false
		_cfg.save_config()
		_apply_window_mode()
		config_changed.emit()
		_rebuild_sys_page()
	)

	# 2) 宽屏：拉伸全屏 / 黑边全屏 / 原分辨率全屏（窗口模式下置灰禁用）
	var ws_labels := ["拉伸全屏", "黑边全屏", "原分辨率全屏"]
	for i in range(3):
		var mode_idx := i
		var ws_btn := _add_option_choice(ws_labels[i], Vector2(256, 156 + i * 30), _cfg.widescreen_mode == mode_idx, func() -> void:
			_cfg.widescreen_mode = mode_idx
			_cfg.save_config()
			config_changed.emit()
			_rebuild_sys_page()
		)
		ws_btn.name = "BtnWidescreen_%d" % i
		if not _cfg.fullscreen:
			ws_btn.disabled = true
			ws_btn.add_theme_color_override("font_disabled_color", Color(0.46, 0.52, 0.62, 0.90))
			ws_btn.add_theme_color_override("font_outline_color", Color(0.88, 0.94, 1.0, 0.85))
			ws_btn.add_theme_constant_override("outline_size", 3)

	# 3) 显示文字框：通常 / 分割
	_add_option_choice("通常", Vector2(256, 280), _cfg.face_window_mode == 0, func() -> void:
		_cfg.face_window_mode = 0
		_cfg.save_config()
		_update_face_avatar()
		config_changed.emit()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(324, 280))
	_add_option_choice("分割", Vector2(354, 280), _cfg.face_window_mode == 1, func() -> void:
		_cfg.face_window_mode = 1
		_cfg.save_config()
		_update_face_avatar()
		config_changed.emit()
		_rebuild_sys_page()
	)

	# 4) 窗口透明度：透明 —— 滑块 —— 不透明
	_add_static_text("透明", Vector2(262, 338))
	var sl_op := _add_styled_slider(Vector2(318, 338), Vector2(202, 28), 0.2, 1.0, 0.02, _cfg.dialogue_opacity)
	sl_op.name = "SliderOpacity"
	sl_op.value_changed.connect(func(v: float) -> void:
		_cfg.dialogue_opacity = v
		_apply_dialogue_opacity()
		if _preview_msg_bg != null:
			_preview_msg_bg.modulate.a = v
		_cfg.save_config()
	)
	_add_static_text("不透明", Vector2(532, 338))

	# 5) 曲名表示：OFF / 2秒 / 4秒 / 常时（把原盘烘焙繁体「常時」替换为简体「常时」）
	var telop_opts := [
		{"label": "OFF", "x": 256, "val": 0},
		{"label": "2秒", "x": 356, "val": 1},
		{"label": "4秒", "x": 446, "val": 2},
		{"label": "常时", "x": 536, "val": 3},
	]
	var telop_slash_xs := [320, 416, 506]
	for t_i in range(telop_opts.size()):
		var td: Dictionary = telop_opts[t_i]
		var t_val: int = int(td["val"])
		_add_option_choice(str(td["label"]), Vector2(int(td["x"]), 398), _cfg.bgm_telop_mode == t_val, func() -> void:
			_cfg.bgm_telop_mode = t_val
			_cfg.save_config()
			config_changed.emit()
			_rebuild_sys_page()
		)
		if t_i < telop_slash_xs.size():
			_add_slash_label(Vector2(telop_slash_xs[t_i], 398))

	# 6) 画面效果：美观 / 快速 / OFF
	var eff_opts := [
		{"label": "美观", "x": 256, "val": 0},
		{"label": "快速", "x": 366, "val": 1},
		{"label": "OFF", "x": 456, "val": 2},
	]
	var eff_slash_xs := [328, 426]
	for e_i in range(eff_opts.size()):
		var ed: Dictionary = eff_opts[e_i]
		var e_val: int = int(ed["val"])
		_add_option_choice(str(ed["label"]), Vector2(int(ed["x"]), 458), _cfg.screen_effect_mode == e_val, func() -> void:
			_cfg.screen_effect_mode = e_val
			_cfg.save_config()
			config_changed.emit()
			_rebuild_sys_page()
		)
		if e_i < eff_slash_xs.size():
			_add_slash_label(Vector2(eff_slash_xs[e_i], 458))

	# 右侧「设置范例」预览窗 (留出 y=322..354 底部深蓝标签)
	_build_sample_preview_box(Vector2(608, 76), Vector2(434, 246))


# ==============================================================================
# 2. 文本设置 (Text - QQ20261115-123936.png)
# ==============================================================================
func _build_tab_text() -> void:
	_add_sky_mask(Vector2(226, 86), Vector2(380, 544))

	# 1) 字体选择按钮 + 可展开下拉菜单（替代 Shift-JIS 乱码，支持三款字体直接点选）
	var fonts := ["默认黑体 (GalHei)", "圆润幼圆 (YouYuan)", "经典宋体 (SimSun)"]
	var font_dropdown := Panel.new()
	font_dropdown.name = "FontDropdown"
	font_dropdown.position = Vector2(230, 136)
	font_dropdown.size = Vector2(300, 152)
	font_dropdown.z_index = 20
	font_dropdown.visible = false
	var dd_sb := StyleBoxFlat.new()
	dd_sb.bg_color = Color(0.02, 0.36, 0.78, 0.96)
	dd_sb.border_color = Color(0.70, 0.90, 1.0, 0.95)
	dd_sb.set_border_width_all(2)
	dd_sb.set_corner_radius_all(8)
	font_dropdown.add_theme_stylebox_override("panel", dd_sb)

	var dd_tex := theme_loader.get_tex("sgcnfgtxt040000")
	if dd_tex != null:
		var dd_bg := TextureRect.new()
		dd_bg.texture = dd_tex
		dd_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		dd_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dd_bg.stretch_mode = TextureRect.STRETCH_SCALE
		dd_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		font_dropdown.add_child(dd_bg)

	for f_i in range(fonts.size()):
		var f_label: String = str(fonts[f_i])
		var f_opt := Button.new()
		f_opt.name = "BtnFontOption_%d" % f_i
		f_opt.position = Vector2(10, 8 + f_i * 46)
		f_opt.size = Vector2(280, 40)
		f_opt.text = f_label
		if _font != null:
			f_opt.add_theme_font_override("font", _font)
		f_opt.add_theme_font_size_override("font_size", 19)
		var is_cur_f: bool = (_cfg.font_name == f_label)
		f_opt.add_theme_color_override("font_color", Color(1.0, 0.96, 0.55) if is_cur_f else Color.WHITE)
		f_opt.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.70))
		var opt_sb := StyleBoxFlat.new()
		opt_sb.bg_color = Color(0.06, 0.50, 0.92, 0.85) if is_cur_f else Color(0.02, 0.25, 0.60, 0.55)
		opt_sb.set_corner_radius_all(6)
		f_opt.add_theme_stylebox_override("normal", opt_sb)
		var opt_hv := StyleBoxFlat.new()
		opt_hv.bg_color = Color(0.14, 0.62, 1.0, 0.92)
		opt_hv.set_corner_radius_all(6)
		f_opt.add_theme_stylebox_override("hover", opt_hv)
		f_opt.pressed.connect(func() -> void:
			_cfg.font_name = f_label
			_cfg.save_config()
			apply_text_font()
			config_changed.emit()
			_rebuild_sys_page()
		)
		font_dropdown.add_child(f_opt)

	var btn_font := _make_blue_box_button(_cfg.font_name + "   ▼", Vector2(230, 90), Vector2(300, 44), Color.WHITE)
	btn_font.name = "BtnFontSelect"
	btn_font.pressed.connect(func() -> void:
		font_dropdown.visible = not font_dropdown.visible
	)
	_sys_content_root.add_child(btn_font)

	# 2) 文本颜色示例按钮
	var unread_prefix := "▶ " if _color_edit_target == "unread" else ""
	_btn_unread_color = _make_blue_box_button(unread_prefix + "对话文本颜色示例", Vector2(230, 151), Vector2(300, 44), _cfg.text_color)
	_btn_unread_color.name = "BtnUnreadColor"
	_btn_unread_color.pressed.connect(func() -> void:
		_color_edit_target = "unread"
		_rebuild_sys_page()
	)
	_sys_content_root.add_child(_btn_unread_color)

	# 3) 已读文本颜色示例按钮
	var read_prefix := "▶ " if _color_edit_target == "read" else ""
	_btn_read_color = _make_blue_box_button(read_prefix + "已读文本颜色示例", Vector2(230, 211), Vector2(300, 44), _cfg.read_text_color)
	_btn_read_color.name = "BtnReadColor"
	_btn_read_color.pressed.connect(func() -> void:
		_color_edit_target = "read"
		_rebuild_sys_page()
	)
	_sys_content_root.add_child(_btn_read_color)

	# 4) 文本显示速度：慢 —— 滑块 —— 快
	_add_static_text("慢", Vector2(250, 278))
	var sl_spd := _add_styled_slider(Vector2(294, 278), Vector2(204, 28), 15.0, 120.0, 5.0, _cfg.text_speed)
	sl_spd.name = "SliderTextSpeed"
	sl_spd.value_changed.connect(func(v: float) -> void:
		_cfg.text_speed = v
		_cfg.save_config()
	)
	_add_static_text("快", Vector2(514, 278))

	# 5) 自动模式速度：慢 —— 滑块 —— 快
	_add_static_text("慢", Vector2(250, 338))
	var sl_auto := _add_styled_slider(Vector2(294, 338), Vector2(204, 28), 0.3, 4.0, 0.1, _cfg.auto_delay)
	sl_auto.name = "SliderAutoDelay"
	sl_auto.value_changed.connect(func(v: float) -> void:
		_cfg.auto_delay = v
		_cfg.save_config()
	)
	_add_static_text("快", Vector2(514, 338))

	# 6) 声音停止时间：单击时 / 播放声音时
	_add_option_choice("单击时", Vector2(240, 400), _cfg.voice_stop_mode == 0, func() -> void:
		_cfg.voice_stop_mode = 0
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(346, 400))
	_add_option_choice("播放声音时", Vector2(380, 400), _cfg.voice_stop_mode == 1, func() -> void:
		_cfg.voice_stop_mode = 1
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 7) 跳过信息：仅已读 / 全部
	_add_option_choice("仅已读", Vector2(240, 460), not _cfg.skip_unread, func() -> void:
		_cfg.skip_unread = false
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(336, 460))
	_add_option_choice("全部", Vector2(372, 460), _cfg.skip_unread, func() -> void:
		_cfg.skip_unread = true
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 8) 继续跳过：总是继续 / 选择支为止 / 一天结束时（紧凑排版防止越界到调色板区域 x>=608）
	var cont_opts := [
		{"label": "总是继续", "x": 234, "val": 0},
		{"label": "选择支为止", "x": 344, "val": 1},
		{"label": "一天结束时", "x": 480, "val": 2},
	]
	var cont_slash_xs := [322, 458]
	for c_i in range(cont_opts.size()):
		var cd: Dictionary = cont_opts[c_i]
		var c_val: int = int(cd["val"])
		var cb := _add_option_choice(str(cd["label"]), Vector2(int(cd["x"]), 520), _cfg.skip_continue_mode == c_val, func() -> void:
			_cfg.skip_continue_mode = c_val
			_cfg.save_config()
			_rebuild_sys_page()
		)
		cb.add_theme_font_size_override("font_size", 20)
		if c_i < cont_slash_xs.size():
			_add_slash_label(Vector2(cont_slash_xs[c_i], 520))

	# 9) 自动模式时的左键：结束自动模式 / 文字显示
	_add_option_choice("结束自动模式", Vector2(232, 584), _cfg.auto_click_mode == 0, func() -> void:
		_cfg.auto_click_mode = 0
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(380, 584))
	_add_option_choice("文字显示", Vector2(408, 584), _cfg.auto_click_mode == 1, func() -> void:
		_cfg.auto_click_mode = 1
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 右上角「设置范例」预览窗（留出 y=322..354 的「调色板 / 设置范例」蓝底标签）
	_build_sample_preview_box(Vector2(608, 76), Vector2(434, 246))

	# 右下角「调色板」交互式取色器 (实测精确区域 x=610, y=364, w=432, h=116) + NOW 色块 + 6 预设色块
	var pal_ctrl := Control.new()
	pal_ctrl.name = "ColorPalettePicker"
	pal_ctrl.position = Vector2(610, 364)
	pal_ctrl.size = Vector2(432, 116)
	pal_ctrl.gui_input.connect(func(ev: InputEvent) -> void:
		var pressed := false
		var lpos := Vector2.ZERO
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			pressed = true
			lpos = ev.position
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pressed = true
			lpos = ev.position
		if pressed:
			var picked: Color
			var bg_img: Image = _sys_bg_rect.texture.get_image() if (_sys_bg_rect != null and _sys_bg_rect.texture != null) else null
			if bg_img != null and bg_img.get_width() > 0 and bg_img.get_height() > 0:
				var lx := clampf(lpos.x, 0.0, 431.0)
				var ly := clampf(lpos.y, 0.0, 115.0)
				var ix := clampi(int(round((610.0 + lx) * float(bg_img.get_width()) / 1280.0)), 0, bg_img.get_width() - 1)
				var iy := clampi(int(round((364.0 + ly) * float(bg_img.get_height()) / 720.0)), 0, bg_img.get_height() - 1)
				picked = bg_img.get_pixel(ix, iy)
				picked.a = 1.0
			else:
				var h_val := clampf(lpos.x / 432.0, 0.0, 1.0)
				var v_ratio := clampf(lpos.y / 116.0, 0.0, 1.0)
				picked = Color.from_hsv(h_val, clampf(v_ratio * 1.4, 0.15, 1.0), clampf(1.3 - v_ratio * 0.9, 0.2, 1.0))
			_apply_picked_text_color(picked)
	)
	_sys_content_root.add_child(pal_ctrl)

	_color_now_swatch = ColorRect.new()
	_color_now_swatch.position = Vector2(694, 482)
	_color_now_swatch.size = Vector2(48, 29)
	_color_now_swatch.color = _cfg.text_color if _color_edit_target == "unread" else _cfg.read_text_color
	_sys_content_root.add_child(_color_now_swatch)

	var preset_colors := [
		Color(1.0, 1.0, 1.0),
		Color(0.68, 0.92, 1.0),
		Color(1.0, 0.86, 0.92),
		Color(1.0, 0.95, 0.65),
		Color(0.76, 1.0, 0.82),
		Color(0.15, 0.15, 0.18),
	]
	for p_i in range(preset_colors.size()):
		var sw := Button.new()
		sw.position = Vector2(744 + p_i * 50, 482)
		sw.size = Vector2(48, 29)
		var sw_sb := StyleBoxFlat.new()
		sw_sb.bg_color = preset_colors[p_i]
		sw_sb.border_color = Color(0.1, 0.2, 0.4, 0.8)
		sw_sb.set_border_width_all(1)
		sw.add_theme_stylebox_override("normal", sw_sb)
		sw.add_theme_stylebox_override("hover", sw_sb)
		var c_pick: Color = preset_colors[p_i]
		sw.pressed.connect(func() -> void: _apply_picked_text_color(c_pick))
		_sys_content_root.add_child(sw)

	# 字体下拉悬浮层最后添加以确保盖住下方颜色示例按钮
	_sys_content_root.add_child(font_dropdown)


func _apply_picked_text_color(col: Color) -> void:
	if _cfg == null:
		return
	if _color_edit_target == "read":
		_cfg.read_text_color = col
		if _btn_read_color != null:
			_btn_read_color.add_theme_color_override("font_color", col)
		if _last_is_read and dialogue_label != null:
			dialogue_label.add_theme_color_override("default_color", col)
	else:
		_cfg.text_color = col
		if _btn_unread_color != null:
			_btn_unread_color.add_theme_color_override("font_color", col)
		if not _last_is_read and dialogue_label != null:
			dialogue_label.add_theme_color_override("default_color", col)
	if _color_now_swatch != null:
		_color_now_swatch.color = col
	_refresh_sample_preview_text()
	_cfg.save_config()


func _refresh_sample_preview_text() -> void:
	if _preview_sample_label == null or _cfg == null:
		return
	var u_hex := _cfg.text_color.to_html(false)
	var r_hex := _cfg.read_text_color.to_html(false)
	_preview_sample_label.bbcode_enabled = true
	if _current_sys_page == "text":
		_preview_sample_label.text = "[color=#%s]未读文本：「这是对话文字颜色设置范例。」[/color]\n[color=#%s]已读文本：「这是已读文字颜色设置范例。」[/color]" % [u_hex, r_hex]
	else:
		var mode_tag := "通常（含头像框）" if _cfg.face_window_mode == 0 else "分割（隐藏头像框）"
		_preview_sample_label.text = "[color=#%s]【%s %s】%s\n「这是对话窗口透明度与文字显示范例。」[/color]" % [u_hex, _cfg.player_family_name, _cfg.player_given_name, mode_tag]


func _build_sample_preview_box(pos: Vector2, sz: Vector2) -> void:
	var box := Control.new()
	box.name = "SamplePreviewBox"
	box.position = pos
	box.size = sz
	box.clip_contents = true
	_sys_content_root.add_child(box)

	var cls_tex := theme_loader.get_tex("sgcnfgdsp900000")
	if cls_tex != null:
		var bg := TextureRect.new()
		bg.texture = cls_tex
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		box.add_child(bg)

	var msg_panel := Panel.new()
	msg_panel.position = Vector2(0, sz.y - 92)
	msg_panel.size = Vector2(sz.x, 92)
	msg_panel.modulate.a = _cfg.dialogue_opacity
	var mp_sb := StyleBoxFlat.new()
	mp_sb.bg_color = Color(0.12, 0.35, 0.62, 0.88)
	mp_sb.border_color = Color(0.65, 0.88, 1.0, 0.85)
	mp_sb.border_width_top = 2
	msg_panel.add_theme_stylebox_override("panel", mp_sb)
	box.add_child(msg_panel)
	_preview_msg_bg = msg_panel

	var text_left := 16.0
	if _cfg.face_window_mode == 0:
		var face_box := Panel.new()
		face_box.name = "SampleFaceSlot"
		face_box.position = Vector2(12, sz.y - 84)
		face_box.size = Vector2(64, 76)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(0.22, 0.52, 0.86, 0.72)
		fsb.border_color = Color(0.85, 0.95, 1.0, 0.9)
		fsb.set_border_width_all(1)
		fsb.set_corner_radius_all(8)
		face_box.add_theme_stylebox_override("panel", fsb)
		var flbl := Label.new()
		flbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		flbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		flbl.text = "头像"
		if _font != null:
			flbl.add_theme_font_override("font", _font)
		flbl.add_theme_font_size_override("font_size", 14)
		flbl.add_theme_color_override("font_color", Color.WHITE)
		face_box.add_child(flbl)
		box.add_child(face_box)
		text_left = 86.0

	_preview_sample_label = RichTextLabel.new()
	_preview_sample_label.position = Vector2(text_left, sz.y - 84)
	_preview_sample_label.size = Vector2(sz.x - text_left - 14.0, 78)
	_preview_sample_label.scroll_active = false
	_preview_sample_label.bbcode_enabled = true
	if _font != null:
		_preview_sample_label.add_theme_font_override("normal_font", _font)
	_preview_sample_label.add_theme_font_size_override("normal_font_size", 15)
	_preview_sample_label.add_theme_color_override("default_color", Color.WHITE)
	_preview_sample_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.08, 0.95))
	_preview_sample_label.add_theme_constant_override("outline_size", 3)
	box.add_child(_preview_sample_label)
	_refresh_sample_preview_text()


# ==============================================================================
# 3. 声音设置 (Sound - QQ20261115-123942.png)
# ==============================================================================
func _build_tab_sound() -> void:
	# 1) 遮盖左上角烘焙的日文「効果音」「ボイス(一括)」「無音」并绘制简体中文
	_add_sky_mask(Vector2(30, 162), Vector2(150, 130))
	_add_static_text("效果音", Vector2(38, 174))
	_add_static_text("语音 (整体)", Vector2(38, 248))

	_add_sky_mask(Vector2(294, 92), Vector2(68, 198))
	_add_static_text("静音", Vector2(298, 98))
	_add_static_text("静音", Vector2(298, 174))
	_add_static_text("静音", Vector2(298, 248))

	# 主音量 3 条滑块 + TEST 按钮
	var sl_bgm := _add_styled_slider(Vector2(358, 100), Vector2(190, 28), 0.0, 1.0, 0.02, _cfg.bgm_volume)
	sl_bgm.name = "SliderBgm"
	sl_bgm.value_changed.connect(func(v: float) -> void:
		_cfg.bgm_volume = v
		_cfg.save_config()
		config_changed.emit()
	)

	var btn_se_test := _make_test_button(Vector2(190, 174))
	btn_se_test.name = "BtnTestSe"
	btn_se_test.pressed.connect(func() -> void: test_se_requested.emit("Chime_01"))
	_sys_content_root.add_child(btn_se_test)

	var sl_se := _add_styled_slider(Vector2(358, 174), Vector2(190, 28), 0.0, 1.0, 0.02, _cfg.se_volume)
	sl_se.name = "SliderSe"
	sl_se.value_changed.connect(func(v: float) -> void:
		_cfg.se_volume = v
		_cfg.save_config()
		config_changed.emit()
	)

	var btn_vo_test := _make_test_button(Vector2(190, 248))
	btn_vo_test.name = "BtnTestVoice"
	btn_vo_test.pressed.connect(func() -> void: voice_replay_requested.emit("TITLE_HI"))
	_sys_content_root.add_child(btn_vo_test)

	var sl_vo := _add_styled_slider(Vector2(358, 250), Vector2(190, 28), 0.0, 1.0, 0.02, _cfg.voice_volume)
	sl_vo.name = "SliderVoice"
	sl_vo.value_changed.connect(func(v: float) -> void:
		_cfg.voice_volume = v
		_cfg.save_config()
		config_changed.emit()
	)

	# 2) 加宽遮盖右侧上方烘焙的完整日文提示「キャラクター名を選択すると個別に音量を変更できます。」并绘制简体中文
	_add_sky_mask(Vector2(600, 184), Vector2(430, 78))
	var char_hdr := Label.new()
	char_hdr.position = Vector2(605, 186)
	char_hdr.size = Vector2(420, 74)
	char_hdr.text = "选择角色名称可单独调整\n该角色的语音音量。"
	char_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_hdr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		char_hdr.add_theme_font_override("font", _font)
	char_hdr.add_theme_font_size_override("font_size", 19)
	char_hdr.add_theme_color_override("font_color", Color(0.02, 0.25, 0.58, 1.0))
	char_hdr.add_theme_color_override("font_outline_color", Color.WHITE)
	char_hdr.add_theme_constant_override("outline_size", 3)
	_sys_content_root.add_child(char_hdr)

	# 3) 右侧 12 个角色按钮（前 10 个保持日文角色原名，最后 2 个分类名「その他 女性/男性」改为简体「其他女性/其他男性」）
	for i in range(SOUND_CHAR_LIST.size()):
		var cinfo: Dictionary = SOUND_CHAR_LIST[i]
		var col := i % 2
		var row := i / 2
		var pos := Vector2(648 + col * 190, 268 + row * 60)
		var is_sel := (_selected_sound_char_idx == i)
		var idx_copy := i

		var n_tex := ("sgcnfgsnd01%02d01" % i) if (is_sel and not bool(cinfo["is_zh_cat"])) else ""
		var tex_obj := theme_loader.get_tex(n_tex) if not n_tex.is_empty() else null
		if tex_obj != null:
			var tb := TextureButton.new()
			tb.name = "BtnSoundChar_%d" % i
			tb.position = pos
			tb.size = Vector2(164, 44)
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_SCALE
			tb.texture_normal = tex_obj
			tb.pressed.connect(func() -> void:
				_selected_sound_char_idx = idx_copy
				_rebuild_sys_page()
			)
			_sys_content_root.add_child(tb)
		else:
			var c_btn := _make_char_pill_button(str(cinfo["name"]), pos, Vector2(164, 44), is_sel)
			c_btn.name = "BtnSoundChar_%d" % i
			c_btn.pressed.connect(func() -> void:
				_selected_sound_char_idx = idx_copy
				_rebuild_sys_page()
			)
			_sys_content_root.add_child(c_btn)

	# 4) 左下角「单独音量范例」卡片 (x=90, y=348, w=520, h=255)
	var sel_info: Dictionary = SOUND_CHAR_LIST[_selected_sound_char_idx]
	var sel_key: String = sel_info["key"]
	var cur_char_vol := float(_cfg.char_voice_volumes.get(sel_key, 1.0))

	var card_tex := theme_loader.get_tex("sgcnfgsnd01%02d02" % _selected_sound_char_idx)
	if card_tex != null:
		var card_rect := TextureRect.new()
		card_rect.texture = card_tex
		card_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_rect.stretch_mode = TextureRect.STRETCH_SCALE
		card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sys_content_root.add_child(card_rect)

	if bool(sel_info["is_zh_cat"]):
		var cat_mask := Panel.new()
		cat_mask.position = Vector2(376, 362)
		cat_mask.size = Vector2(220, 52)
		var cm_sb := StyleBoxFlat.new()
		cm_sb.bg_color = Color(0.84, 0.94, 0.99, 1.0)
		cm_sb.set_corner_radius_all(6)
		cat_mask.add_theme_stylebox_override("panel", cm_sb)
		_sys_content_root.add_child(cat_mask)

		var cat_lbl := Label.new()
		cat_lbl.position = Vector2(376, 362)
		cat_lbl.size = Vector2(220, 52)
		cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cat_lbl.text = str(sel_info["name"])
		if _font != null:
			cat_lbl.add_theme_font_override("font", _font)
		cat_lbl.add_theme_font_size_override("font_size", 32)
		cat_lbl.add_theme_color_override("font_color", Color.WHITE)
		cat_lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.56, 0.94, 1.0))
		cat_lbl.add_theme_constant_override("outline_size", 8)
		_sys_content_root.add_child(cat_lbl)

	# 遮盖卡片内「無音」为「静音」
	var card_mute_mask := Panel.new()
	card_mute_mask.position = Vector2(284, 554)
	card_mute_mask.size = Vector2(52, 32)
	var cmm_sb := StyleBoxFlat.new()
	cmm_sb.bg_color = Color(0.99, 0.99, 1.0, 1.0)
	card_mute_mask.add_theme_stylebox_override("panel", cmm_sb)
	_sys_content_root.add_child(card_mute_mask)
	_add_static_text("静音", Vector2(288, 556))

	# 遮盖卡片底部蓝色标签「個別音量サンプル」并替换为简体「单独音量范例」
	var sample_tab := Panel.new()
	sample_tab.position = Vector2(348, 603)
	sample_tab.size = Vector2(262, 32)
	var st_sb := StyleBoxFlat.new()
	st_sb.bg_color = Color(0.0, 0.27, 0.62, 1.0)
	st_sb.set_corner_radius_all(6)
	sample_tab.add_theme_stylebox_override("panel", st_sb)
	_sys_content_root.add_child(sample_tab)

	var st_lbl := Label.new()
	st_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st_lbl.text = "单独音量范例"
	if _font != null:
		st_lbl.add_theme_font_override("font", _font)
	st_lbl.add_theme_font_size_override("font_size", 18)
	st_lbl.add_theme_color_override("font_color", Color.WHITE)
	sample_tab.add_child(st_lbl)

	# 克隆卡片干净底纹遮盖原盘烘焙的「100 %」，彻底消除重影
	_add_sky_mask(Vector2(398, 428), Vector2(104, 34), 360, card_tex)

	var pct_lbl := Label.new()
	pct_lbl.position = Vector2(400, 428)
	pct_lbl.size = Vector2(98, 34)
	pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct_lbl.text = "%d %%" % int(round(cur_char_vol * 100.0))
	if _font != null:
		pct_lbl.add_theme_font_override("font", _font)
	pct_lbl.add_theme_font_size_override("font_size", 22)
	pct_lbl.add_theme_color_override("font_color", Color(0.08, 0.08, 0.12))
	pct_lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	pct_lbl.add_theme_constant_override("outline_size", 4)
	_sys_content_root.add_child(pct_lbl)

	var btn_char_test := _make_test_button(Vector2(510, 429))
	btn_char_test.size = Vector2(78, 33)
	btn_char_test.name = "BtnTestCharVoice"
	var sample_voice: String = str(sel_info["sample"])
	btn_char_test.pressed.connect(func() -> void: voice_replay_requested.emit(sample_voice))
	_sys_content_root.add_child(btn_char_test)

	var sl_char := _add_styled_slider(Vector2(342, 556), Vector2(204, 28), 0.0, 1.0, 0.05, cur_char_vol)
	sl_char.name = "SliderCharVoice"
	sl_char.value_changed.connect(func(v: float) -> void:
		_cfg.char_voice_volumes[sel_key] = v
		pct_lbl.text = "%d %%" % int(round(v * 100.0))
		_cfg.save_config()
		config_changed.emit()
	)


# ==============================================================================
# 4. 系统设置 (System - QQ20261115-123950.png)
# ==============================================================================
func _build_tab_system() -> void:
	_add_sky_mask(Vector2(252, 88), Vector2(328, 474))

	# 1) 光标隐藏时间：5秒 / 10秒 / 常驻显示（替换原盘日文「常に表示」）
	var cur_opts := [
		{"label": "5秒", "x": 262, "val": 0},
		{"label": "10秒", "x": 360, "val": 1},
		{"label": "常驻显示", "x": 456, "val": 2},
	]
	for c_i in range(cur_opts.size()):
		var cd: Dictionary = cur_opts[c_i]
		var c_val: int = int(cd["val"])
		_add_option_choice(str(cd["label"]), Vector2(int(cd["x"]), 98), _cfg.cursor_hide_time == c_val, func() -> void:
			_cfg.cursor_hide_time = c_val
			_cfg.save_config()
			config_changed.emit()
			_rebuild_sys_page()
		)
		if c_i < cur_opts.size() - 1:
			_add_slash_label(Vector2(int(cd["x"]) + 64, 98))

	# 2) 光标自动移动：ON / OFF
	_add_option_choice("ON", Vector2(262, 158), _cfg.cursor_auto_move, func() -> void:
		_cfg.cursor_auto_move = true
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(324, 158))
	_add_option_choice("OFF", Vector2(356, 158), not _cfg.cursor_auto_move, func() -> void:
		_cfg.cursor_auto_move = false
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 3) 右键 / 滚轮↑ / 滚轮↓ 当前分配功能（简体中文替换日文「オプション」「履 歴」「左クリック」）
	var mouse_targets := [
		{"target": "right_click", "val": _cfg.right_click_action, "y": 218},
		{"target": "wheel_up", "val": _cfg.wheel_up_action, "y": 278},
		{"target": "wheel_down", "val": _cfg.wheel_down_action, "y": 338},
	]
	for mt in mouse_targets:
		var t_key: String = mt["target"]
		var act_label := _get_mouse_func_label(str(mt["val"]))
		var is_editing := (_selected_mouse_bind_target == t_key)
		var disp_text := ("▶ " + act_label) if is_editing else act_label
		_add_option_choice(disp_text, Vector2(262, int(mt["y"])), true, func() -> void:
			_selected_mouse_bind_target = t_key
			_rebuild_sys_page()
		)

	# 4) 非活动时的处理行为：继续运行 / 暂停运行（替换原盘日文「動作継続 / 動作停止」）
	_add_option_choice("继续运行", Vector2(262, 400), _cfg.inactive_behavior == 0, func() -> void:
		_cfg.inactive_behavior = 0
		_cfg.save_config()
		config_changed.emit()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(366, 400))
	_add_option_choice("暂停运行", Vector2(396, 400), _cfg.inactive_behavior == 1, func() -> void:
		_cfg.inactive_behavior = 1
		_cfg.save_config()
		config_changed.emit()
		_rebuild_sys_page()
	)

	# 5) 快速存档时确认：ON / OFF
	_add_option_choice("ON", Vector2(262, 460), _cfg.confirm_qsave, func() -> void:
		_cfg.confirm_qsave = true
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(324, 460))
	_add_option_choice("OFF", Vector2(356, 460), not _cfg.confirm_qsave, func() -> void:
		_cfg.confirm_qsave = false
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 6) 快速读档时确认：ON / OFF
	_add_option_choice("ON", Vector2(262, 522), _cfg.confirm_qload, func() -> void:
		_cfg.confirm_qload = true
		_cfg.save_config()
		_rebuild_sys_page()
	)
	_add_slash_label(Vector2(324, 522))
	_add_option_choice("OFF", Vector2(356, 522), not _cfg.confirm_qload, func() -> void:
		_cfg.confirm_qload = false
		_cfg.save_config()
		_rebuild_sys_page()
	)

	# 7) 右侧「分配功能选择」8 按钮面板（严密对齐底图白框槽位）
	var assign_cur_val := _cfg.right_click_action
	var target_zh := "右键"
	if _selected_mouse_bind_target == "wheel_up":
		assign_cur_val = _cfg.wheel_up_action
		target_zh = "滚轮↑"
	elif _selected_mouse_bind_target == "wheel_down":
		assign_cur_val = _cfg.wheel_down_action
		target_zh = "滚轮↓"

	for f_i in range(MOUSE_ASSIGN_FUNCS.size()):
		var fd: Dictionary = MOUSE_ASSIGN_FUNCS[f_i]
		var col := f_i % 2
		var row := f_i / 2
		var b_pos := Vector2(628 + col * 190, 183 + row * 60)
		var fid: String = fd["id"]
		var is_act := (assign_cur_val == fid)
		var fbtn := _make_char_pill_button(str(fd["label"]), b_pos, Vector2(164, 44), is_act)
		fbtn.name = "BtnMouseAssign_%s" % fid
		fbtn.pressed.connect(func() -> void:
			if _selected_mouse_bind_target == "right_click":
				_cfg.right_click_action = fid
			elif _selected_mouse_bind_target == "wheel_up":
				_cfg.wheel_up_action = fid
			elif _selected_mouse_bind_target == "wheel_down":
				_cfg.wheel_down_action = fid
			_cfg.save_config()
			_rebuild_sys_page()
		)
		_sys_content_root.add_child(fbtn)

	# 状态提示精准落入 y=430..479 的深蓝横条正中
	var assign_status := Label.new()
	assign_status.position = Vector2(596, 430)
	assign_status.size = Vector2(418, 50)
	assign_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assign_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	assign_status.text = "当前设置对象：【%s】 → %s" % [target_zh, _get_mouse_func_label(assign_cur_val)]
	if _font != null:
		assign_status.add_theme_font_override("font", _font)
	assign_status.add_theme_font_size_override("font_size", 17)
	assign_status.add_theme_color_override("font_color", Color.WHITE)
	_sys_content_root.add_child(assign_status)

	var assign_tab := Panel.new()
	assign_tab.position = Vector2(755, 512)
	assign_tab.size = Vector2(268, 34)
	var at_sb := StyleBoxFlat.new()
	at_sb.bg_color = Color(0.0, 0.27, 0.62, 1.0)
	at_sb.set_corner_radius_all(6)
	assign_tab.add_theme_stylebox_override("panel", at_sb)
	_sys_content_root.add_child(assign_tab)

	var at_lbl := Label.new()
	at_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	at_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	at_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	at_lbl.text = "选择分配功能"
	if _font != null:
		at_lbl.add_theme_font_override("font", _font)
	at_lbl.add_theme_font_size_override("font_size", 18)
	at_lbl.add_theme_color_override("font_color", Color.WHITE)
	assign_tab.add_child(at_lbl)

	# 8) 底部移植增强开关栏（浅蓝磨砂面板 + 全状态深蓝文字，彻底消除白底白字）
	var ext_panel := PanelContainer.new()
	ext_panel.position = Vector2(34, 588)
	var ep_sb := StyleBoxFlat.new()
	ep_sb.bg_color = Color(0.90, 0.96, 1.0, 0.94)
	ep_sb.border_color = Color(0.25, 0.58, 0.92, 0.90)
	ep_sb.set_border_width_all(2)
	ep_sb.set_corner_radius_all(8)
	ext_panel.add_theme_stylebox_override("panel", ep_sb)
	_sys_content_root.add_child(ext_panel)

	var ext_margin := MarginContainer.new()
	ext_margin.add_theme_constant_override("margin_left", 14)
	ext_margin.add_theme_constant_override("margin_right", 14)
	ext_margin.add_theme_constant_override("margin_top", 4)
	ext_margin.add_theme_constant_override("margin_bottom", 4)
	ext_panel.add_child(ext_margin)

	var ext_bar := HBoxContainer.new()
	ext_bar.add_theme_constant_override("separation", 18)
	ext_margin.add_child(ext_bar)

	var navy := Color(0.05, 0.22, 0.48)
	var chk_uncen := CheckButton.new()
	chk_uncen.name = "ChkUncensored"
	chk_uncen.text = "无码补丁"
	chk_uncen.button_pressed = _cfg.uncensored_mode
	if _font != null:
		chk_uncen.add_theme_font_override("font", _font)
	chk_uncen.add_theme_font_size_override("font_size", 17)
	for ck in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		chk_uncen.add_theme_color_override(ck, navy)
	chk_uncen.toggled.connect(func(on: bool) -> void:
		_cfg.uncensored_mode = on
		_cfg.save_config()
		config_changed.emit()
	)
	ext_bar.add_child(chk_uncen)

	var chk_nude := CheckButton.new()
	chk_nude.name = "ChkNude"
	chk_nude.text = "F12 透视"
	chk_nude.button_pressed = _cfg.nude_mode
	if _font != null:
		chk_nude.add_theme_font_override("font", _font)
	chk_nude.add_theme_font_size_override("font_size", 17)
	for ck in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		chk_nude.add_theme_color_override(ck, navy)
	chk_nude.toggled.connect(func(on: bool) -> void:
		_cfg.nude_mode = on
		_cfg.save_config()
		config_changed.emit()
	)
	ext_bar.add_child(chk_nude)

	var chk_confirm := CheckButton.new()
	chk_confirm.name = "ChkConfirm"
	chk_confirm.text = "重要操作确认"
	chk_confirm.button_pressed = _cfg.confirm_dialogs
	if _font != null:
		chk_confirm.add_theme_font_override("font", _font)
	chk_confirm.add_theme_font_size_override("font_size", 17)
	for ck in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		chk_confirm.add_theme_color_override(ck, navy)
	chk_confirm.toggled.connect(func(on: bool) -> void:
		_cfg.confirm_dialogs = on
		_cfg.save_config()
	)
	ext_bar.add_child(chk_confirm)

	var btn_rescan := _make_pill_btn("重新扫描外置资产", Vector2(160, 34))
	btn_rescan.name = "BtnRescan"
	btn_rescan.pressed.connect(func() -> void: rescan_byoa_requested.emit())
	ext_bar.add_child(btn_rescan)


func _get_mouse_func_label(fid: String) -> String:
	for fd in MOUSE_ASSIGN_FUNCS:
		if fd["id"] == fid:
			return str(fd["label"])
	return "选项"


# ==============================================================================
# 5. 设置快捷键 (Shortcut Keys - QQ20261115-123957.png)
# ==============================================================================
func _build_tab_keys() -> void:
	for kd in KEY_BIND_ITEMS:
		var kid: String = kd["id"]
		var col: int = int(kd["col"])
		var row: int = int(kd["row"])
		var b_pos := Vector2(220 + col * 520, 90 + row * 60)
		var cur_key := str(_cfg.key_bindings.get(kid, ""))
		var is_wait := (_waiting_key_action == kid)
		var disp := "请按键..." if is_wait else cur_key

		var kbtn := Button.new()
		kbtn.name = "BtnKey_%s" % kid
		kbtn.position = b_pos
		kbtn.size = Vector2(160, 40)
		kbtn.text = disp
		if _font != null:
			kbtn.add_theme_font_override("font", _font)
		kbtn.add_theme_font_size_override("font_size", 20)
		kbtn.add_theme_color_override("font_color", Color.WHITE)
		var k_sb := StyleBoxFlat.new()
		k_sb.bg_color = Color(0.95, 0.45, 0.15, 1.0) if is_wait else Color(0.0, 0.56, 0.96, 1.0)
		k_sb.border_color = Color(0.0, 0.32, 0.72, 1.0)
		k_sb.set_border_width_all(2)
		k_sb.set_corner_radius_all(10)
		kbtn.add_theme_stylebox_override("normal", k_sb)
		kbtn.add_theme_stylebox_override("hover", k_sb)
		kbtn.pressed.connect(func() -> void:
			_waiting_key_action = kid
			_key_notice_override = ""
			_rebuild_sys_page()
		)
		_sys_content_root.add_child(kbtn)

	if not _waiting_key_action.is_empty() or not _key_notice_override.is_empty():
		var notice_bg := Panel.new()
		notice_bg.position = Vector2(160, 544)
		notice_bg.size = Vector2(729, 44)
		var nb_sb := StyleBoxFlat.new()
		nb_sb.bg_color = Color8(168, 38, 38, 255) if not _key_notice_override.is_empty() else Color8(0, 71, 157, 255)
		nb_sb.set_corner_radius_all(10)
		notice_bg.add_theme_stylebox_override("panel", nb_sb)
		_sys_content_root.add_child(notice_bg)

	_key_notice_label = Label.new()
	_key_notice_label.name = "KeyNoticeLabel"
	_key_notice_label.position = Vector2(160, 544)
	_key_notice_label.size = Vector2(729, 44)
	_key_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		_key_notice_label.add_theme_font_override("font", _font)
	_key_notice_label.add_theme_font_size_override("font_size", 19)
	_key_notice_label.add_theme_color_override("font_color", Color.WHITE)
	if not _key_notice_override.is_empty():
		_key_notice_label.text = _key_notice_override
	elif not _waiting_key_action.is_empty():
		_key_notice_label.text = "请按下要绑定的新按键（按 Esc 键取消更改）..."
	else:
		_key_notice_label.text = ""
	_sys_content_root.add_child(_key_notice_label)


# ==============================================================================
# 6 & 7. 存档 / 读档 (Save / Load - QQ20261115-124005.png)
# ==============================================================================
func _build_tab_save_load(save_mode: bool) -> void:
	# 1) 左侧 1..10 页码按钮 (x=32, y=82 + i*55, w=52, h=50)
	for p_i in range(10):
		var is_cur_page := (_current_save_page == p_i)
		var suffix := "02" if is_cur_page else "01"
		var p_tex := theme_loader.get_tex("sgusdtwnd00%02d%s" % [p_i, suffix])
		var page_copy := p_i
		if p_tex != null:
			var pb := TextureButton.new()
			pb.name = "BtnSavePage_%d" % (p_i + 1)
			pb.position = Vector2(32, 82 + p_i * 55)
			pb.size = Vector2(52, 50)
			pb.ignore_texture_size = true
			pb.stretch_mode = TextureButton.STRETCH_SCALE
			pb.texture_normal = p_tex
			pb.pressed.connect(func() -> void:
				_current_save_page = page_copy
				_selected_slot = _current_save_page * SLOTS_PER_PAGE
				_rebuild_sys_page()
			)
			_sys_content_root.add_child(pb)
		else:
			var pb_fb := _make_char_pill_button(str(p_i + 1), Vector2(32, 82 + p_i * 55), Vector2(52, 50), is_cur_page)
			pb_fb.name = "BtnSavePage_%d" % (p_i + 1)
			pb_fb.pressed.connect(func() -> void:
				_current_save_page = page_copy
				_selected_slot = _current_save_page * SLOTS_PER_PAGE
				_rebuild_sys_page()
			)
			_sys_content_root.add_child(pb_fb)

	# 2) 中间 2 列 x 5 行（每页 10 个槽位，对齐原盘卡片框：col 0 x=110, col 1 x=410, y=80 + r*110, w=290, h=104）
	var base_slot := _current_save_page * SLOTS_PER_PAGE
	for i in range(SLOTS_PER_PAGE):
		var slot := base_slot + i
		var col := i % 2
		var row := i / 2
		var card_pos := Vector2(110 + col * 300, 80 + row * 110)
		var card_sz := Vector2(290, 104)
		var data := load_game_from_slot(slot)
		var exists := not data.is_empty()

		var card_btn := Button.new()
		card_btn.name = "BtnSlot_%d" % slot
		card_btn.position = card_pos
		card_btn.size = card_sz
		var c_sb := StyleBoxFlat.new()
		if _selected_slot == slot:
			c_sb.bg_color = Color(1.0, 1.0, 1.0, 0.22)
			c_sb.border_color = Color(1.0, 0.95, 0.55, 0.95)
			c_sb.set_border_width_all(3)
		else:
			c_sb.bg_color = Color(0, 0, 0, 0.0)
			c_sb.border_color = Color(1, 1, 1, 0.0)
		c_sb.set_corner_radius_all(12)
		card_btn.add_theme_stylebox_override("normal", c_sb)
		card_btn.add_theme_stylebox_override("hover", c_sb)
		card_btn.mouse_entered.connect(func() -> void:
			if _save_comment_edit != null and _save_comment_edit.has_focus():
				return
			if _selected_slot != slot:
				_selected_slot = slot
				_update_save_detail_panel()
		)
		card_btn.pressed.connect(func() -> void:
			_selected_slot = slot
			_update_save_detail_panel()
			_execute_selected_slot()
		)
		_sys_content_root.add_child(card_btn)

		var thumb := TextureRect.new()
		thumb.position = Vector2(12, 18)
		thumb.size = Vector2(112, 64)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if exists:
			var sp := str(data.get("shot_path", ""))
			if not sp.is_empty() and FileAccess.file_exists(sp):
				var img := Image.load_from_file(sp)
				if img != null:
					thumb.texture = ImageTexture.create_from_image(img)
		card_btn.add_child(thumb)

		var tag := "Q.S" if slot == QUICK_SAVE_SLOT else "No.%03d" % [slot + 1]
		var num_lbl := Label.new()
		num_lbl.position = Vector2(130, 10)
		num_lbl.size = Vector2(152, 24)
		num_lbl.clip_text = true
		num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ts_clean := str(data.get("timestamp", "")).replace("T", " ").left(16)
		num_lbl.text = "%s %s" % [tag, ts_clean if exists else "----/--/--"]
		if _font != null:
			num_lbl.add_theme_font_override("font", _font)
		num_lbl.add_theme_font_size_override("font_size", 13)
		num_lbl.add_theme_color_override("font_color", Color.WHITE)
		num_lbl.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.08, 0.95))
		num_lbl.add_theme_constant_override("outline_size", 3)
		card_btn.add_child(num_lbl)

		var txt_lbl := Label.new()
		txt_lbl.position = Vector2(132, 36)
		txt_lbl.size = Vector2(148, 56)
		txt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt_lbl.clip_text = true
		if exists:
			var spk := _sanitize_save_speaker(str(data.get("last_speaker", "")))
			var tx := str(data.get("last_dialogue_text", ""))
			txt_lbl.text = ("【%s】%s" % [spk, tx]) if not spk.is_empty() else tx
		else:
			txt_lbl.text = "（空槽位）"
		if _font != null:
			txt_lbl.add_theme_font_override("font", _font)
		txt_lbl.add_theme_font_size_override("font_size", 14)
		txt_lbl.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
		card_btn.add_child(txt_lbl)

	# 3) 右侧详细预览框 (x=718, y=78, w=326, h=382) + 克隆底图纹理无缝遮盖「コメント：」为「备注：」
	_add_sky_mask(Vector2(732, 334), Vector2(116, 26), 1015)

	var cmt_lbl := Label.new()
	cmt_lbl.position = Vector2(736, 332)
	cmt_lbl.size = Vector2(120, 28)
	cmt_lbl.text = "备注："
	cmt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		cmt_lbl.add_theme_font_override("font", _font)
	cmt_lbl.add_theme_font_size_override("font_size", 18)
	cmt_lbl.add_theme_color_override("font_color", Color.WHITE)
	cmt_lbl.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.08, 0.9))
	cmt_lbl.add_theme_constant_override("outline_size", 3)
	_sys_content_root.add_child(cmt_lbl)

	var detail_root := Control.new()
	detail_root.name = "SaveDetailRoot"
	detail_root.position = Vector2(718, 78)
	detail_root.size = Vector2(326, 250)
	detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sys_content_root.add_child(detail_root)

	_save_comment_edit = TextEdit.new()
	_save_comment_edit.name = "SaveCommentEdit"
	_save_comment_edit.position = Vector2(732, 362)
	_save_comment_edit.size = Vector2(298, 86)
	_save_comment_edit.placeholder_text = "点击此处输入存档备注..."
	if _font != null:
		_save_comment_edit.add_theme_font_override("font", _font)
	_save_comment_edit.add_theme_font_size_override("font_size", 16)
	_save_comment_edit.add_theme_color_override("font_color", Color.WHITE)
	var te_sb := StyleBoxFlat.new()
	te_sb.bg_color = Color(0, 0, 0, 0.15)
	te_sb.set_corner_radius_all(6)
	_save_comment_edit.add_theme_stylebox_override("normal", te_sb)
	_save_comment_edit.text_changed.connect(func() -> void:
		if _selected_slot >= 0:
			set_slot_comment(_selected_slot, _save_comment_edit.text)
	)
	_sys_content_root.add_child(_save_comment_edit)

	_update_save_detail_panel()


func _sanitize_save_speaker(raw_spk: String) -> String:
	if raw_spk.is_empty():
		return ""
	var s := raw_spk.replace("主人公（姓）", _cfg.player_family_name)
	s = s.replace("主人公（名）", _cfg.player_given_name)
	return s


func _update_save_detail_panel() -> void:
	if _sys_content_root == null:
		return
	var detail_root := _sys_content_root.get_node_or_null("SaveDetailRoot")
	if detail_root == null:
		return
	for c in detail_root.get_children():
		c.queue_free()

	var data := load_game_from_slot(_selected_slot)
	var exists := not data.is_empty()

	var thumb := TextureRect.new()
	thumb.position = Vector2(43, 12)
	thumb.size = Vector2(240, 135)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if exists:
		var sp := str(data.get("shot_path", ""))
		if not sp.is_empty() and FileAccess.file_exists(sp):
			var img := Image.load_from_file(sp)
			if img != null:
				thumb.texture = ImageTexture.create_from_image(img)
	detail_root.add_child(thumb)

	var meta_lbl := Label.new()
	meta_lbl.position = Vector2(16, 154)
	meta_lbl.size = Vector2(294, 92)
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_lbl.clip_text = true
	if _font != null:
		meta_lbl.add_theme_font_override("font", _font)
	meta_lbl.add_theme_font_size_override("font_size", 15)
	meta_lbl.add_theme_color_override("font_color", Color.WHITE)
	meta_lbl.add_theme_color_override("font_outline_color", Color(0.32, 0.10, 0.08, 0.9))
	meta_lbl.add_theme_constant_override("outline_size", 3)
	if exists:
		var spk := _sanitize_save_speaker(str(data.get("last_speaker", "")))
		var tx := str(data.get("last_dialogue_text", ""))
		meta_lbl.text = "槽位 No.%03d  [%s]\n%s%s" % [
			_selected_slot + 1,
			str(data.get("timestamp", "")).replace("T", " "),
			("【%s】" % spk) if not spk.is_empty() else "",
			tx
		]
	else:
		meta_lbl.text = "槽位 No.%03d\n（当前槽位尚无存档数据）" % [_selected_slot + 1]
	detail_root.add_child(meta_lbl)

	if _save_comment_edit != null:
		var cmt := str(data.get("comment", "")) if exists else ""
		if _save_comment_edit.text != cmt:
			_save_comment_edit.text = cmt
		_save_comment_edit.editable = exists


func _execute_selected_slot() -> void:
	var slot := _selected_slot
	var existing := load_game_from_slot(slot)
	if _is_save_mode:
		if not existing.is_empty():
			show_confirm("sgdialog990003", "确定覆盖存档吗？", func() -> void:
				_close_all_modals()
				save_slot_requested.emit(slot)
			)
		else:
			show_confirm("sgdialog990006", "确定存档？", func() -> void:
				_close_all_modals()
				save_slot_requested.emit(slot)
			)
	else:
		if existing.is_empty():
			return
		show_confirm("sgdialog990007", "确定读档？", func() -> void:
			_close_all_modals()
			load_slot_requested.emit(slot)
		)


# ==============================================================================
# 历史记录 Backlog (sglogwnd*)
# ==============================================================================
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

	_log_scroll = ScrollContainer.new()
	_log_scroll.name = "LogScroll"
	_log_scroll.position = Vector2(104, 62)
	_log_scroll.size = Vector2(932, 594)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_panel.add_child(_log_scroll)

	_log_list_vbox = VBoxContainer.new()
	_log_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_vbox.add_theme_constant_override("separation", 12)
	_log_scroll.add_child(_log_list_vbox)

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
			var qj := _make_pill_btn("场景跳转", Vector2(106, 28))
			qj.pressed.connect(func() -> void:
				show_confirm("sgdialog990008", "确定快速跳跃？", func() -> void:
					_close_all_modals()
					quick_jump_requested.emit(snap)
				)
			)
			hdr.add_child(qj)

		var spk := Label.new()
		spk.text = str(item.get("speaker", ""))
		spk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _font != null:
			spk.add_theme_font_override("font", _font)
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
		if _font != null:
			txt_lbl.add_theme_font_override("font", _font)
		txt_lbl.add_theme_font_size_override("font_size", 20)
		txt_lbl.add_theme_color_override("font_color", Color.WHITE)
		vb.add_child(txt_lbl)

	_close_all_modals()
	modal_backdrop.visible = true
	log_panel.visible = true
	call_deferred("_scroll_log_to_bottom")


func _scroll_log_to_bottom() -> void:
	if _log_scroll == null or not is_instance_valid(_log_scroll):
		return
	var vb := _log_scroll.get_v_scroll_bar()
	if vb != null:
		_log_scroll.scroll_vertical = int(vb.max_value)
	else:
		_log_scroll.scroll_vertical = 999999


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


# ==============================================================================
# 8. 姓名输入弹窗与序章跳过弹窗 (QQ20261115-124159.png)
# ==============================================================================
func _build_new_game_overlays() -> void:
	_name_input_overlay = Control.new()
	_name_input_overlay.name = "NameInputOverlay"
	_name_input_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_input_overlay.visible = false
	add_child(_name_input_overlay)

	var fallback_bg := ColorRect.new()
	fallback_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback_bg.color = Color(0.96, 0.78, 0.85, 0.98)
	_name_input_overlay.add_child(fallback_bg)

	_name_bg_tex_rect = TextureRect.new()
	_name_bg_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_bg_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_name_bg_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_name_bg_tex_rect.visible = false
	_name_input_overlay.add_child(_name_bg_tex_rect)

	var empty_sb := StyleBoxEmpty.new()

	# 姓输入框（精确对齐 sgnminpt990000 左侧粉框「姓 …」右侧：x=290, y=290, w=320, h=70，默认保持日文「青葉」）
	_family_input = LineEdit.new()
	_family_input.name = "FamilyInput"
	_family_input.text = "青葉"
	_family_input.position = Vector2(290, 290)
	_family_input.size = Vector2(320, 70)
	_family_input.add_theme_font_size_override("font_size", 36)
	_family_input.add_theme_color_override("font_color", Color.WHITE)
	_family_input.add_theme_stylebox_override("normal", empty_sb)
	_family_input.add_theme_stylebox_override("focus", empty_sb)
	_name_input_overlay.add_child(_family_input)

	# 名输入框（精确对齐 sgnminpt990000 右侧粉框「名 …」右侧：x=745, y=290, w=320, h=70，默认保持日文「恭介」）
	_given_input = LineEdit.new()
	_given_input.name = "GivenInput"
	_given_input.text = "恭介"
	_given_input.position = Vector2(745, 290)
	_given_input.size = Vector2(320, 70)
	_given_input.add_theme_font_size_override("font_size", 36)
	_given_input.add_theme_color_override("font_color", Color.WHITE)
	_given_input.add_theme_stylebox_override("normal", empty_sb)
	_given_input.add_theme_stylebox_override("focus", empty_sb)
	_name_input_overlay.add_child(_given_input)

	# 「默认」按钮 (sgnminpt000000 / 000001, x=470, y=410, w=340, h=62)
	_btn_name_default = TextureButton.new()
	_btn_name_default.name = "BtnNameDefault"
	_btn_name_default.position = Vector2(470, 410)
	_btn_name_default.size = Vector2(340, 62)
	_btn_name_default.ignore_texture_size = true
	_btn_name_default.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var dlbl := Label.new()
	dlbl.text = "默认"
	dlbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlbl.add_theme_font_size_override("font_size", 24)
	_btn_name_default.add_child(dlbl)
	_btn_name_default.pressed.connect(func() -> void:
		_family_input.text = "青葉"
		_given_input.text = "恭介"
	)
	_name_input_overlay.add_child(_btn_name_default)

	# 「结束输入」按钮 (sgnminpt000100 / 000101, x=840, y=562, w=340, h=62)
	_btn_name_done = TextureButton.new()
	_btn_name_done.name = "BtnNameConfirm"
	_btn_name_done.position = Vector2(840, 562)
	_btn_name_done.size = Vector2(340, 62)
	_btn_name_done.ignore_texture_size = true
	_btn_name_done.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var oklbl := Label.new()
	oklbl.text = "结束输入"
	oklbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	oklbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oklbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	oklbl.add_theme_font_size_override("font_size", 24)
	_btn_name_done.add_child(oklbl)
	_btn_name_done.pressed.connect(func() -> void:
		var fam := _family_input.text.strip_edges()
		var giv := _given_input.text.strip_edges()
		if fam.is_empty():
			fam = "青葉"
		if giv.is_empty():
			giv = "恭介"
		if _cfg != null:
			_cfg.player_family_name = fam
			_cfg.player_given_name = giv
			_cfg.save_config()
		_name_input_overlay.visible = false
		if _prologue_skip_overlay != null:
			_prologue_skip_overlay.visible = true
			modal_backdrop.visible = true
		else:
			_refresh_backdrop()
			new_game_confirmed.emit(false, fam, giv)
	)
	_name_input_overlay.add_child(_btn_name_done)

	# 2. 要跳过序章吗？选择弹窗
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


# ==============================================================================
# 9. 确认弹窗 (Confirmation Dialog - QQ20261115-124231.png)
# ==============================================================================
func _build_confirm_dialog() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.name = "ConfirmDialogOverlay"
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.25)
	_confirm_overlay.add_child(dim)

	_confirm_bg_rect = TextureRect.new()
	_confirm_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_confirm_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_confirm_overlay.add_child(_confirm_bg_rect)

	var fallback_card := PanelContainer.new()
	fallback_card.name = "ConfirmFallbackCard"
	fallback_card.position = Vector2(268, 194)
	fallback_card.size = Vector2(746, 314)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.95, 0.94, 0.92, 0.98)
	st.border_color = Color(0.55, 0.55, 0.58)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	fallback_card.add_theme_stylebox_override("panel", st)
	_confirm_overlay.add_child(fallback_card)
	_confirm_overlay.move_child(fallback_card, 1)

	_confirm_msg_lbl = Label.new()
	_confirm_msg_lbl.position = Vector2(320, 240)
	_confirm_msg_lbl.size = Vector2(640, 80)
	_confirm_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_msg_lbl.add_theme_font_size_override("font_size", 32)
	_confirm_msg_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.38))
	_confirm_overlay.add_child(_confirm_msg_lbl)

	# 「是 / 否」原盘按钮（精确对齐 QQ20261115-124231.png：x=360 / x=700, y=384, 214x64）
	_confirm_yes_btn = TextureButton.new()
	_confirm_yes_btn.name = "BtnConfirmYes"
	_confirm_yes_btn.position = Vector2(360, 384)
	_confirm_yes_btn.custom_minimum_size = Vector2(214, 64)
	_confirm_yes_btn.size = Vector2(214, 64)
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
	_confirm_no_btn.name = "BtnConfirmNo"
	_confirm_no_btn.position = Vector2(700, 384)
	_confirm_no_btn.custom_minimum_size = Vector2(214, 64)
	_confirm_no_btn.size = Vector2(214, 64)
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


# ==============================================================================
# 辅助 UI 构造方法
# ==============================================================================
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


func _add_sky_mask(pos: Vector2, sz: Vector2, sample_x: int = 16, custom_tex: Texture2D = null) -> void:
	var src_tex: Texture2D = custom_tex if custom_tex != null else (_sys_bg_rect.texture if _sys_bg_rect != null else null)
	if src_tex != null:
		var img := src_tex.get_image()
		if img != null:
			var iw := img.get_width()
			var ih := img.get_height()
			var sy := clampi(int(pos.y), 0, maxi(0, ih - 2))
			var sh := clampi(int(sz.y), 1, ih - sy)
			var strip: Image
			if custom_tex == null and sample_x == 16 and iw >= 1270:
				# 蓝天设置页精确过滤纯天蓝扫线像素 (b>0.88 且 b-r>0.09)，排除白色散景圆斑与深色文字/边框
				strip = Image.create(1, sh, false, Image.FORMAT_RGBA8)
				var sample_xs := [8, 16, 28, 48, 80, 120, 160, 1048, 1268]
				var last_pure := Color(0.553, 0.827, 0.980, 1.0)
				for dy in range(sh):
					var y_abs := sy + dy
					var found := false
					for cx in sample_xs:
						var px := img.get_pixel(cx, y_abs)
						if px.b > 0.88 and (px.b - px.r) > 0.09:
							last_pure = px
							found = true
							break
					if not found:
						var alt := 0.992 if (y_abs % 2 == 0) else 1.0
						last_pure = Color(last_pure.r * alt, last_pure.g * alt, last_pure.b, 1.0)
					strip.set_pixel(0, dy, last_pure)
			else:
				var sx := clampi(sample_x, 0, maxi(0, iw - 8))
				var sw := clampi(8, 1, iw - sx)
				strip = img.get_region(Rect2i(sx, sy, sw, sh))
			var tr := TextureRect.new()
			tr.position = pos
			tr.size = sz
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.texture = ImageTexture.create_from_image(strip)
			_sys_content_root.add_child(tr)
			return
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.58, 0.84, 0.98, 1.0)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	_sys_content_root.add_child(p)


func _add_option_choice(text: String, pos: Vector2, selected: bool, on_click: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.flat = true
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 22)
	if selected:
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.0, 0.42, 0.95, 1.0))
		b.add_theme_constant_override("outline_size", 8)
	else:
		b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.12, 0.95))
		b.add_theme_color_override("font_hover_color", Color(0.0, 0.42, 0.95, 1.0))
		b.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.92))
		b.add_theme_constant_override("outline_size", 5)
	b.pressed.connect(on_click)
	_sys_content_root.add_child(b)
	return b


func _add_slash_label(pos: Vector2) -> void:
	var l := Label.new()
	l.position = pos
	l.text = "／"
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 4)
	_sys_content_root.add_child(l)


func _add_static_text(text: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.12))
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 5)
	_sys_content_root.add_child(l)
	return l


func _add_styled_slider(pos: Vector2, sz: Vector2, min_v: float, max_v: float, step_v: float, cur_v: float) -> HSlider:
	var sl := HSlider.new()
	sl.position = pos
	sl.size = sz
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = cur_v
	_sys_content_root.add_child(sl)
	return sl


func _make_blue_box_button(text: String, pos: Vector2, sz: Vector2, font_col: Color) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.text = text
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col)
	b.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.12, 0.95))
	b.add_theme_constant_override("outline_size", 5)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.36, 0.72, 1.0)
	sb.border_color = Color(0.0, 0.22, 0.50, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	return b


func _make_test_button(pos: Vector2) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(72, 26)
	b.text = "TEST"
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.42, 0.85, 1.0)
	sb.border_color = Color(0.65, 0.85, 1.0, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	return b


func _make_char_pill_button(text: String, pos: Vector2, sz: Vector2, active: bool) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.text = text
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	if active:
		sb.bg_color = Color(0.06, 0.58, 0.96, 1.0)
		sb.border_color = Color(0.02, 0.35, 0.78, 1.0)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.02, 0.18, 0.45, 0.95))
		b.add_theme_constant_override("outline_size", 4)
	else:
		sb.bg_color = Color(0.95, 0.95, 0.94, 1.0)
		sb.border_color = Color(0.75, 0.76, 0.78, 1.0)
		b.add_theme_color_override("font_color", Color(0.42, 0.41, 0.41, 1.0))
		b.add_theme_color_override("font_hover_color", Color(0.06, 0.48, 0.88, 1.0))
		b.add_theme_constant_override("outline_size", 0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	return b


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless" or _cfg == null:
		return
	if _cfg.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))


func _apply_dialogue_opacity() -> void:
	if _cfg == null:
		return
	if _msg_bg_rect != null:
		_msg_bg_rect.modulate.a = _cfg.dialogue_opacity
	if _msg_fallback_bg != null:
		_msg_fallback_bg.modulate.a = _cfg.dialogue_opacity


func _close_all_modals(include_choices: bool = false) -> void:
	sys_menu_panel.visible = false
	save_load_panel.visible = false
	config_panel.visible = false
	log_panel.visible = false
	if include_choices:
		choice_panel.visible = false
	if gallery_panel != null:
		if gallery_panel._viewer_overlay != null:
			gallery_panel._viewer_overlay.visible = false
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
