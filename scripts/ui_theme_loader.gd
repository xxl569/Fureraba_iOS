class_name UiThemeLoader
extends RefCounted

## 运行时从 BYOA VFS 动态提取并缓存《フレラバ》原版系统 UI 贴图（sg*）。
## 严禁将任何版权贴图写入仓库，所有界面贴图均在挂载 VFS 后按需解码。

var _vfs: BgiVfs = null
var _tex_cache: Dictionary = {} # entry_name -> ImageTexture


func setup(vfs: BgiVfs) -> void:
	_vfs = vfs
	_tex_cache.clear()


func has_vfs() -> bool:
	return _vfs != null and _vfs.is_ready()


func get_tex(entry_name: String) -> ImageTexture:
	if entry_name.is_empty():
		return null
	if _tex_cache.has(entry_name):
		return _tex_cache[entry_name] as ImageTexture
	if not has_vfs() or not _vfs.has_entry(entry_name):
		return null
	var img := _vfs.decode_image(entry_name)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[entry_name] = tex
	return tex


func make_tex_button(
	normal_entry: String,
	hover_entry: String = "",
	pressed_entry: String = "",
	fallback_text: String = "",
	min_size: Vector2 = Vector2.ZERO
) -> TextureButton:
	var btn := TextureButton.new()
	btn.ignore_texture_size = false
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var t_norm := get_tex(normal_entry)
	var t_hov := get_tex(hover_entry) if not hover_entry.is_empty() else null
	var t_prs := get_tex(pressed_entry) if not pressed_entry.is_empty() else null
	if t_norm != null:
		btn.texture_normal = t_norm
		if t_hov != null:
			btn.texture_hover = t_hov
			btn.texture_focused = t_hov
		if t_prs != null:
			btn.texture_pressed = t_prs
		elif t_hov != null:
			btn.texture_pressed = t_hov
		if min_size != Vector2.ZERO:
			btn.custom_minimum_size = min_size
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_SCALE
	else:
		# 无 VFS 兜底占位文本
		btn.custom_minimum_size = min_size if min_size != Vector2.ZERO else Vector2(120, 44)
		var lbl := Label.new()
		lbl.text = fallback_text
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.add_child(lbl)
	return btn


func apply_button_textures(
	btn: TextureButton,
	normal_entry: String,
	hover_entry: String = "",
	pressed_entry: String = ""
) -> void:
	var t_norm := get_tex(normal_entry)
	if t_norm != null:
		btn.texture_normal = t_norm
	var t_hov := get_tex(hover_entry) if not hover_entry.is_empty() else null
	if t_hov != null:
		btn.texture_hover = t_hov
		btn.texture_focused = t_hov
	var t_prs := get_tex(pressed_entry) if not pressed_entry.is_empty() else null
	if t_prs != null:
		btn.texture_pressed = t_prs
	elif t_hov != null:
		btn.texture_pressed = t_hov
