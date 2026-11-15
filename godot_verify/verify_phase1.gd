extends Control
## 阶段一 Godot 4.3 运行时最小验证脚本：
## 1. VideoStreamTheora 加载并播放 U:\anti\temp\Fureraba_iOS\movie\friendtolover.ogv
## 2. FontFile 加载 U:\anti\projects\game\字体文件\GalHei.ttf 并测量中/日文字符
## 3. nudeprcs._bp 双层立绘 (hi01wa_n + hi01wa_nh) 叠加渲染与 F12 透视切换状态机

const OGV_PATH := "U:/anti/temp/Fureraba_iOS/movie/friendtolover.ogv"
const FONT_PATH := "U:/anti/projects/game/字体文件/GalHei.ttf"
const BASE_SPRITE_PATH := "U:/anti/temp/Fureraba_iOS/samples/cbg/data02100_arc__hi01wa_n.png"
const NUDE_SPRITE_PATH := "U:/anti/temp/Fureraba_iOS/samples/cbg/data02100_arc__hi01wa_nh.png"

var _nude_mode: bool = false
var _base_rect: TextureRect
var _nude_rect: TextureRect
var _video_player: VideoStreamPlayer
var _label: Label
var _frames: int = 0
var _all_ok: bool = true


func _fail(msg: String) -> void:
	_all_ok = false
	push_error("[PHASE1_VERIFY_FAIL] " + msg)
	print("FAIL: ", msg)


func _ready() -> void:
	print("=== Fureraba Phase 1 Godot 4.3 Runtime Verification ===")
	print("Engine version: ", Engine.get_version_info().get("string", "unknown"))
	print("Rendering driver: ", RenderingServer.get_video_adapter_name())

	# 1. 验证 GalHei.ttf 动态加载与中/日文渲染度量
	var font := FontFile.new()
	var font_err := font.load_dynamic_font(FONT_PATH)
	if font_err != OK:
		_fail("GalHei.ttf 加载失败, err=%d" % font_err)
	else:
		var sz_zh := font.get_string_size("要跳过序章吗？阳茉莉", HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
		var sz_jp := font.get_string_size("フレラバ 〜Friend to Lover〜", HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
		print("PASS_FONT: GalHei.ttf loaded | zh_size=%s | jp_size=%s" % [sz_zh, sz_jp])
		if sz_zh.x <= 0.0 or sz_jp.x <= 0.0:
			_fail("GalHei.ttf 字符度量异常: zh=%s jp=%s" % [sz_zh, sz_jp])

	# 2. 验证 nudeprcs._bp 双层立绘 (name + name+"h") 加载与 F12 透视切换
	var img_base := Image.load_from_file(BASE_SPRITE_PATH)
	var img_nude := Image.load_from_file(NUDE_SPRITE_PATH)
	if img_base == null or img_base.is_empty():
		_fail("基础立绘加载失败: " + BASE_SPRITE_PATH)
	elif img_nude == null or img_nude.is_empty():
		_fail("透视立绘加载失败: " + NUDE_SPRITE_PATH)
	elif img_base.get_size() != img_nude.get_size():
		_fail("双层立绘尺寸不匹配: %s vs %s" % [img_base.get_size(), img_nude.get_size()])
	else:
		_base_rect = TextureRect.new()
		_base_rect.texture = ImageTexture.create_from_image(img_base)
		_base_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_base_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_base_rect)

		_nude_rect = TextureRect.new()
		_nude_rect.texture = ImageTexture.create_from_image(img_nude)
		_nude_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_nude_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_nude_rect.modulate.a = 0.0
		add_child(_nude_rect)

		# 模拟真实 InputEventKey(KEY_F12) 触发 _unhandled_input 状态切换 (对应 nudeprcs._bp SYS 0x9056 <-> SYS 0x9058)
		var ev_on := InputEventKey.new()
		ev_on.keycode = KEY_F12
		ev_on.pressed = true
		ev_on.echo = false
		_unhandled_input(ev_on)
		var alpha_on := _nude_rect.modulate.a
		_unhandled_input(ev_on)
		var alpha_off := _nude_rect.modulate.a
		if not is_equal_approx(alpha_on, 1.0) or not is_equal_approx(alpha_off, 0.0):
			_fail("透视切换透明度异常: on=%f off=%f" % [alpha_on, alpha_off])
		else:
			print("PASS_NUDE_PAIR: size=%s | toggle_on=%.1f | toggle_off=%.1f" % [img_base.get_size(), alpha_on, alpha_off])

	# 3. 挂载 Label 验证字体控件
	_label = Label.new()
	_label.text = "要跳过序章吗？ — フレラバ 〜Friend to Lover〜"
	if font_err == OK:
		_label.add_theme_font_override("font", font)
		_label.add_theme_font_size_override("font_size", 28)
	_label.position = Vector2(24, 24)
	add_child(_label)

	# 4. 验证 VideoStreamTheora (.ogv) 加载与播放
	_video_player = VideoStreamPlayer.new()
	_video_player.expand = true
	_video_player.size = Vector2(320, 180)
	_video_player.position = Vector2(24, 80)
	var vstream := VideoStreamTheora.new()
	vstream.file = OGV_PATH
	_video_player.stream = vstream
	add_child(_video_player)
	_video_player.play()
	print("VIDEO_START: stream_set=%s | is_playing=%s" % [
		_video_player.stream != null,
		_video_player.is_playing(),
	])
	if not _video_player.is_playing():
		_fail("VideoStreamPlayer.play() 后未进入播放状态")


func _toggle_nude_mode() -> void:
	_nude_mode = not _nude_mode
	if _nude_rect:
		_nude_rect.modulate.a = 1.0 if _nude_mode else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_toggle_nude_mode()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		var playing := _video_player.is_playing() if _video_player else false
		var pos := _video_player.stream_position if _video_player else -1.0
		var vtex := _video_player.get_video_texture() if _video_player else null
		var vtex_size := vtex.get_size() if vtex != null else Vector2.ZERO
		print("VIDEO_FRAME_5: is_playing=%s | stream_pos=%.3f | video_tex_size=%s" % [
			playing,
			pos,
			vtex_size,
		])
		if not playing or vtex == null or vtex_size != Vector2(1280, 720) or pos <= 0.0:
			_fail("VideoStreamTheora 第 5 帧解码断言失败: playing=%s pos=%.3f size=%s" % [playing, pos, vtex_size])
		if _all_ok:
			print("PHASE1_GODOT_VERIFY_OK")
			get_tree().quit(0)
		else:
			print("PHASE1_GODOT_VERIFY_FAILED")
			get_tree().quit(1)
