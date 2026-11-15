class_name UiGalleryPanel
extends Control

## 附录：CG 鉴赏与 BGM 音乐鉴赏界面（运行时从 VFS 动态提取 sggallery* / sgmusic* / sgtelop*）。

signal close_requested()
signal play_bgm_requested(bgm_entry: String)
signal stop_bgm_requested()
signal play_op_requested()

const CHAR_TABS := [
	{"name": "皆原 陽茉莉", "prefix": "hiev", "btn": "sggallery100001"},
	{"name": "望月 理奈", "prefix": "riev", "btn": "sggallery100101"},
	{"name": "柊 ゆずゆ", "prefix": "yuev", "btn": "sggallery100201"},
	{"name": "沢渡 岬", "prefix": "miev", "btn": "sggallery100301"},
]

const BGM_COUNT := 27
const PAGE_SIZE := 18

var _theme = null
var _vfs: BgiVfs
var _font: Font = null

var _bg_rect: TextureRect
var _cg_grid: GridContainer
var _char_buttons: Array[Button] = []
var _page_label: Label
var _bgm_buttons: Array[Button] = []
var _bgm_telop_rect: TextureRect
var _bgm_fallback_lbl: Label
var _btn_op: Button

var _viewer_overlay: Control
var _viewer_tex: TextureRect
var _viewer_info: Label

var _current_char_idx: int = 0
var _current_page: int = 0
var _current_cg_list: Array[String] = []
var _viewer_idx: int = -1
var _current_bgm_idx: int = 0
var _cg_cache: Dictionary = {} # prefix -> Array[String]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()


func setup(theme_loader, vfs: BgiVfs, font: Font = null) -> void:
	_theme = theme_loader
	_vfs = vfs
	_font = font
	if _theme != null:
		var bg_t: ImageTexture = _theme.get_tex("sggallery990000")
		if bg_t != null:
			_bg_rect.texture = bg_t
	_update_bgm_telop(_current_bgm_idx)


func open_gallery(has_movie: bool) -> void:
	_btn_op.visible = has_movie
	_select_char(_current_char_idx)
	visible = true


func _build_ui() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_rect)

	# 无贴图时的淡蓝渐变兜底底色
	var fallback_bg := ColorRect.new()
	fallback_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback_bg.color = Color(0.84, 0.94, 1.0, 1.0)
	fallback_bg.show_behind_parent = true
	_bg_rect.add_child(fallback_bg)

	# 右上角功能按钮底板（遮盖原图日文假按钮）
	var top_bg := Panel.new()
	top_bg.position = Vector2(676, 40)
	top_bg.size = Vector2(566, 56)
	var top_st := StyleBoxFlat.new()
	top_st.bg_color = Color(0.55, 0.78, 0.98, 0.92)
	top_st.set_corner_radius_all(12)
	top_bg.add_theme_stylebox_override("panel", top_st)
	add_child(top_bg)

	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(684, 46)
	top_bar.size = Vector2(550, 44)
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	top_bar.add_theme_constant_override("separation", 10)
	add_child(top_bar)

	_btn_op = _make_pill_btn("播放 OP 动画")
	_btn_op.pressed.connect(func() -> void: play_op_requested.emit())
	top_bar.add_child(_btn_op)

	var btn_prev_pg := _make_pill_btn("◀ 上一页")
	btn_prev_pg.pressed.connect(func() -> void: _change_page(-1))
	top_bar.add_child(btn_prev_pg)

	_page_label = Label.new()
	_page_label.text = "1 / 1"
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_color_override("font_color", Color(0.12, 0.35, 0.65))
	_page_label.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(_page_label)

	var btn_next_pg := _make_pill_btn("下一页 ▶")
	btn_next_pg.pressed.connect(func() -> void: _change_page(1))
	top_bar.add_child(btn_next_pg)

	var btn_back := _make_pill_btn("返回标题")
	btn_back.pressed.connect(func() -> void:
		visible = false
		close_requested.emit()
	)
	top_bar.add_child(btn_back)

	# 中间 6x3 CG 缩略图网格 (对齐原版 sggallery990000 中央区域)
	_cg_grid = GridContainer.new()
	_cg_grid.columns = 6
	_cg_grid.position = Vector2(120, 128)
	_cg_grid.size = Vector2(1040, 294)
	_cg_grid.add_theme_constant_override("h_separation", 14)
	_cg_grid.add_theme_constant_override("v_separation", 10)
	add_child(_cg_grid)

	# 底部角色切换与 BGM 播放器整洁底板（完全不透明，彻底遮盖原图底部假按钮）
	var bottom_bg := Panel.new()
	bottom_bg.position = Vector2(44, 434)
	bottom_bg.size = Vector2(1192, 260)
	var btm_st := StyleBoxFlat.new()
	btm_st.bg_color = Color(0.84, 0.94, 1.0, 1.0)
	btm_st.border_color = Color(1, 1, 1, 0.95)
	btm_st.set_border_width_all(2)
	btm_st.set_corner_radius_all(16)
	bottom_bg.add_theme_stylebox_override("panel", btm_st)
	add_child(bottom_bg)

	# 角色切换标签栏 (y ≈ 446)
	var char_bar := HBoxContainer.new()
	char_bar.position = Vector2(64, 446)
	char_bar.size = Vector2(680, 40)
	char_bar.add_theme_constant_override("separation", 10)
	add_child(char_bar)
	for i in range(CHAR_TABS.size()):
		var cb := _make_pill_btn(str(CHAR_TABS[i]["name"]), true)
		cb.custom_minimum_size = Vector2(146, 36)
		var idx := i
		cb.pressed.connect(func() -> void: _select_char(idx))
		char_bar.add_child(cb)
		_char_buttons.append(cb)

	# 底部 BGM 播放器区域 (y ≈ 502 ~ 680)
	var bgm_grid := GridContainer.new()
	bgm_grid.columns = 14
	bgm_grid.position = Vector2(64, 502)
	bgm_grid.size = Vector2(670, 96)
	bgm_grid.add_theme_constant_override("h_separation", 6)
	bgm_grid.add_theme_constant_override("v_separation", 6)
	add_child(bgm_grid)

	for i in range(BGM_COUNT):
		var bb := _make_pill_btn("%02d" % [i + 1], true)
		bb.custom_minimum_size = Vector2(40, 38)
		var idx := i
		bb.pressed.connect(func() -> void: _play_bgm(idx))
		bgm_grid.add_child(bb)
		_bgm_buttons.append(bb)

	# 右下角 BGM 曲名与控制按钮
	var telop_box := PanelContainer.new()
	telop_box.position = Vector2(748, 496)
	telop_box.size = Vector2(472, 46)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.56, 0.92, 0.92)
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	telop_box.add_theme_stylebox_override("panel", st)
	add_child(telop_box)

	_bgm_telop_rect = TextureRect.new()
	_bgm_telop_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bgm_telop_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bgm_telop_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	telop_box.add_child(_bgm_telop_rect)

	_bgm_fallback_lbl = Label.new()
	_bgm_fallback_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bgm_fallback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bgm_fallback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bgm_fallback_lbl.add_theme_color_override("font_color", Color.WHITE)
	telop_box.add_child(_bgm_fallback_lbl)

	var ctrl_bar := HBoxContainer.new()
	ctrl_bar.position = Vector2(748, 550)
	ctrl_bar.size = Vector2(472, 44)
	ctrl_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_bar.add_theme_constant_override("separation", 12)
	add_child(ctrl_bar)

	var btn_prev_bgm := _make_pill_btn("◀◀ 上一首")
	btn_prev_bgm.pressed.connect(func() -> void: _play_bgm((_current_bgm_idx - 1 + BGM_COUNT) % BGM_COUNT))
	ctrl_bar.add_child(btn_prev_bgm)

	var btn_play_bgm := _make_pill_btn("▶ 播放")
	btn_play_bgm.pressed.connect(func() -> void: _play_bgm(_current_bgm_idx))
	ctrl_bar.add_child(btn_play_bgm)

	var btn_stop_bgm := _make_pill_btn("■ 停止")
	btn_stop_bgm.pressed.connect(func() -> void: stop_bgm_requested.emit())
	ctrl_bar.add_child(btn_stop_bgm)

	var btn_next_bgm := _make_pill_btn("下一首 ▶▶")
	btn_next_bgm.pressed.connect(func() -> void: _play_bgm((_current_bgm_idx + 1) % BGM_COUNT))
	ctrl_bar.add_child(btn_next_bgm)

	# 全屏 CG 鉴赏查看器
	_viewer_overlay = Control.new()
	_viewer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer_overlay.visible = false
	add_child(_viewer_overlay)

	var vbg := ColorRect.new()
	vbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbg.color = Color(0, 0, 0, 0.96)
	_viewer_overlay.add_child(vbg)

	_viewer_tex = TextureRect.new()
	_viewer_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewer_overlay.add_child(_viewer_tex)

	_viewer_info = Label.new()
	_viewer_info.position = Vector2(20, 16)
	_viewer_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_viewer_info.add_theme_font_size_override("font_size", 18)
	_viewer_overlay.add_child(_viewer_info)

	_viewer_overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_RIGHT:
				_viewer_overlay.visible = false
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if _current_cg_list.is_empty():
					_viewer_overlay.visible = false
				else:
					_open_cg_viewer((_viewer_idx + 1) % _current_cg_list.size())
	)


func _make_pill_btn(txt: String, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = txt
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(96, 36)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.98, 1.0, 0.92)
	st.border_color = Color(0.28, 0.65, 0.95, 0.95)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 10
	b.add_theme_stylebox_override("normal", st)
	var st_hov := st.duplicate() as StyleBoxFlat
	st_hov.bg_color = Color(0.32, 0.68, 0.98, 0.96)
	b.add_theme_stylebox_override("hover", st_hov)
	b.add_theme_stylebox_override("pressed", st_hov)
	b.add_theme_color_override("font_color", Color(0.14, 0.36, 0.68))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


func _select_char(idx: int) -> void:
	_current_char_idx = clampi(idx, 0, CHAR_TABS.size() - 1)
	for i in range(_char_buttons.size()):
		_char_buttons[i].button_pressed = (i == _current_char_idx)
	var prefix := str(CHAR_TABS[_current_char_idx]["prefix"])
	_current_cg_list = _collect_cgs(prefix)
	_current_page = 0
	_render_cg_page()


func _collect_cgs(prefix: String) -> Array[String]:
	if _cg_cache.has(prefix):
		return _cg_cache[prefix]
	var out: Array[String] = []
	if _vfs != null and _vfs.is_ready():
		var all := _vfs.list_entries(prefix)
		var arr: Array[String] = []
		for e in all:
			var low := e.to_lower()
			if low.ends_with(".ogg") or low.ends_with("h"):
				continue
			arr.append(e)
		arr.sort()
		out = arr
	_cg_cache[prefix] = out
	return out


func _change_page(delta: int) -> void:
	var total_pages := maxi(1, int(ceili(float(_current_cg_list.size()) / float(PAGE_SIZE))))
	_current_page = (_current_page + delta + total_pages) % total_pages
	_render_cg_page()


func _render_cg_page() -> void:
	for c in _cg_grid.get_children():
		c.queue_free()
	var total_pages := maxi(1, int(ceili(float(_current_cg_list.size()) / float(PAGE_SIZE))))
	_page_label.text = "%d / %d" % [_current_page + 1, total_pages]
	var start := _current_page * PAGE_SIZE
	var end := mini(start + PAGE_SIZE, _current_cg_list.size())
	for i in range(start, end):
		var cg_name := _current_cg_list[i]
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(160, 90)
		btn.ignore_texture_size = true
		var img := _vfs.decode_image(cg_name) if _vfs != null else null
		if img != null:
			var iw := img.get_width()
			var ih := img.get_height()
			var aspect := float(maxi(iw, ih)) / float(maxi(mini(iw, ih), 1))
			# 等比缩放到合适缩略图尺寸，严禁破坏宽高比
			if iw > 320 or ih > 320:
				var sc := 320.0 / float(maxi(iw, ih))
				img.resize(maxi(1, int(round(iw * sc))), maxi(1, int(round(ih * sc))), Image.INTERPOLATE_BILINEAR)
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED if aspect > 2.2 else TextureButton.STRETCH_KEEP_ASPECT_COVERED
			btn.texture_normal = ImageTexture.create_from_image(img)
		else:
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		var cg_idx := i
		btn.pressed.connect(func() -> void: _open_cg_viewer(cg_idx))
		_cg_grid.add_child(btn)


func _open_cg_viewer(idx: int) -> void:
	if idx < 0 or idx >= _current_cg_list.size() or _vfs == null:
		return
	_viewer_idx = idx
	var cg_name := _current_cg_list[idx]
	var img := _vfs.decode_image(cg_name)
	if img != null:
		_viewer_tex.texture = ImageTexture.create_from_image(img)
	_viewer_info.text = "%s (%d / %d)  [左键下一张 / 右键关闭]" % [cg_name, idx + 1, _current_cg_list.size()]
	_viewer_overlay.visible = true


func _play_bgm(idx: int) -> void:
	_current_bgm_idx = clampi(idx, 0, BGM_COUNT - 1)
	for i in range(_bgm_buttons.size()):
		_bgm_buttons[i].button_pressed = (i == _current_bgm_idx)
	_update_bgm_telop(_current_bgm_idx)
	var bgm_entry := "FL_bgm_%02d" % [_current_bgm_idx + 1]
	play_bgm_requested.emit(bgm_entry)


func _update_bgm_telop(idx: int) -> void:
	var entry := "sgtelop10%02d00" % idx
	var t: ImageTexture = _theme.get_tex(entry) if _theme != null else null
	if t != null:
		_bgm_telop_rect.texture = t
		_bgm_telop_rect.visible = true
		_bgm_fallback_lbl.visible = false
	else:
		_bgm_telop_rect.visible = false
		_bgm_fallback_lbl.visible = true
		_bgm_fallback_lbl.text = "%02d : FL_bgm_%02d" % [idx + 1, idx + 1]
