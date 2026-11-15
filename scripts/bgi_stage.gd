class_name BgiStage
extends Control

## BGI 256 层图元舞台控制器。
## 支持背景/CG 归一化缩放（兼容 1536x864 与 2048x1152 无码补丁）、
## 超长滚动图切片拼接（最大 1280x11362）、立绘层、透视差分即时切换及震屏特效。

const MAX_LAYERS := 256
const LOGICAL_SIZE := Vector2(1280.0, 720.0)

var _vfs: BgiVfs
var _bp_vm: BgiBpVm
var _cache: BgiCache

var _layers_root: Control
var _layer_nodes: Dictionary = {} # layer_id (int) -> Control
var _layer_asset_names: Dictionary = {} # layer_id (int) -> String
var _quake_tween: Tween = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers_root = Control.new()
	_layers_root.name = "LayersRoot"
	_layers_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layers_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layers_root)


func setup(vfs: BgiVfs, bp_vm: BgiBpVm, cache: BgiCache) -> void:
	_vfs = vfs
	_bp_vm = bp_vm
	_cache = cache


func get_texture_cached(img_name: String) -> ImageTexture:
	if _vfs == null or img_name.is_empty():
		return null
	var resolved := img_name
	if _bp_vm != null:
		resolved = _bp_vm.resolve_nude_image_name(img_name)

	# 兼容内置颜色关键词（如 white / black）
	var lower := resolved.to_lower()
	if lower == "white" or lower == "black":
		var solid_key := "__solid_" + lower
		if _cache != null and _cache.has_key(solid_key):
			return _cache.get_item(solid_key)
		var col := Color.WHITE if lower == "white" else Color.BLACK
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(col)
		var tex := ImageTexture.create_from_image(img)
		if _cache != null:
			_cache.put_item(solid_key, tex, 64)
		return tex

	if _cache != null and _cache.has_key(resolved):
		return _cache.get_item(resolved)

	if not _vfs.has_entry(resolved):
		return null

	var img: Image = _vfs.decode_image(resolved)
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var tex := ImageTexture.create_from_image(img)
	if _cache != null:
		_cache.put_item(resolved, tex, w * h * 4)
	return tex


func load_scroll_slices(img_name: String, max_slice_h: int = 4096) -> Array[ImageTexture]:
	var out: Array[ImageTexture] = []
	if _vfs == null or not _vfs.has_entry(img_name):
		return out
	var slices := _vfs.decode_image_slices(img_name, max_slice_h)
	for sl in slices:
		var img: Image = sl.get("image", null)
		if img != null:
			out.append(ImageTexture.create_from_image(img))
	return out


func show_background(img_name: String) -> bool:
	var tex := get_texture_cached(img_name)
	if tex == null:
		return false
	var node := _ensure_texture_layer(0, 0)
	node.texture = tex
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.visible = true
	_layer_asset_names[0] = img_name
	return true


func show_bustshot(layer_id: int, img_name: String, pos_x: float = 0.0, pos_y: float = 0.0) -> bool:
	var lid := clampi(layer_id, 1, MAX_LAYERS - 1)
	var tex := get_texture_cached(img_name)
	if tex == null:
		return false
	var node := _ensure_texture_layer(lid, lid)
	node.texture = tex
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = Vector2(pos_x, pos_y)
	node.visible = true
	_layer_asset_names[lid] = img_name
	return true


func show_scroll_image(layer_id: int, img_name: String) -> int:
	var lid := clampi(layer_id, 0, MAX_LAYERS - 1)
	var slices := load_scroll_slices(img_name, 4096)
	if slices.is_empty():
		return 0
	_remove_layer(lid)
	var vbox := VBoxContainer.new()
	vbox.name = "ScrollLayer_%d" % lid
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.z_index = lid
	for tex in slices:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sz := tex.get_size()
		var scale_x := LOGICAL_SIZE.x / maxf(sz.x, 1.0)
		tr.custom_minimum_size = Vector2(LOGICAL_SIZE.x, sz.y * scale_x)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(tr)
	_layers_root.add_child(vbox)
	_layer_nodes[lid] = vbox
	_layer_asset_names[lid] = img_name
	return slices.size()


func clear_layer(layer_id: int) -> void:
	_remove_layer(layer_id)
	_layer_asset_names.erase(layer_id)


func clear_all_bustshots() -> void:
	for lid in _layer_nodes.keys().duplicate():
		if int(lid) >= 1 and int(lid) < 200:
			clear_layer(int(lid))


func refresh_nude_layers() -> void:
	for lid in _layer_asset_names.keys().duplicate():
		var asset_name := str(_layer_asset_names[lid])
		if int(lid) == 0:
			show_background(asset_name)
		else:
			var ctrl: Control = _layer_nodes.get(lid)
			if ctrl is TextureRect:
				show_bustshot(int(lid), asset_name, ctrl.position.x, ctrl.position.y)


func trigger_quake(amplitude: float = 12.0, duration: float = 0.35) -> void:
	if _quake_tween != null and _quake_tween.is_valid():
		_quake_tween.kill()
	_quake_tween = create_tween()
	var steps := 6
	var step_dt := duration / float(steps)
	for i in range(steps):
		var offset := Vector2(
			randf_range(-amplitude, amplitude),
			randf_range(-amplitude * 0.6, amplitude * 0.6)
		)
		_quake_tween.tween_property(_layers_root, "position", offset, step_dt)
	_quake_tween.tween_property(_layers_root, "position", Vector2.ZERO, 0.05)


func handle_stage_command(cmd: String, args: Array) -> void:
	match cmd:
		"_DrawScene":
			if args.size() >= 1:
				show_background(str(args[0]))
		"_FadeScene":
			clear_all_bustshots()
			show_background("black")
		"_DrawBS", "_FadeBS":
			if args.size() >= 2:
				var lid := int(args[0]) if typeof(args[0]) == TYPE_INT else 10
				var bname := str(args[1]) if typeof(args[1]) == TYPE_STRING else str(args[0])
				show_bustshot(maxi(lid, 1), bname)
		"_ClearBS":
			clear_all_bustshots()
		"_DrawSPR":
			if args.size() >= 1:
				show_bustshot(200, str(args[0]))
		"_ScrollBG":
			if args.size() >= 1:
				show_scroll_image(0, str(args[0]))
		"_QuakeEx", "StartShakingOfWindowSx":
			if is_inside_tree():
				trigger_quake()


func get_active_layer_count() -> int:
	return _layer_nodes.size()


func _ensure_texture_layer(lid: int, z: int) -> TextureRect:
	if _layer_nodes.has(lid) and _layer_nodes[lid] is TextureRect:
		return _layer_nodes[lid] as TextureRect
	_remove_layer(lid)
	var tr := TextureRect.new()
	tr.name = "Layer_%d" % lid
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = z
	_layers_root.add_child(tr)
	_layer_nodes[lid] = tr
	return tr


func _remove_layer(lid: int) -> void:
	if _layer_nodes.has(lid):
		var n: Node = _layer_nodes[lid]
		if is_instance_valid(n):
			n.queue_free()
		_layer_nodes.erase(lid)
