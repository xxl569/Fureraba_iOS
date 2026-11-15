class_name BgiVideoPlayer
extends Control

## BGI 外置 `.ogv` (Theora + Vorbis) 过场视频播放器。
## 包含跳过防误触保护：前 1.0 秒屏蔽误触，之后需点击右上角「跳过」按钮或连续长按 0.45 秒跳过。

signal video_finished()

var _player: VideoStreamPlayer
var _skip_btn: Button
var _elapsed: float = 0.0
var _hold_time: float = 0.0
var _holding: bool = false
var _is_playing: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_player = VideoStreamPlayer.new()
	_player.name = "VideoStreamPlayer"
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.finished.connect(_on_finished)
	add_child(_player)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipVideoBtn"
	_skip_btn.text = "跳过 OP"
	_skip_btn.anchor_left = 1.0
	_skip_btn.anchor_right = 1.0
	_skip_btn.offset_left = -140.0
	_skip_btn.offset_top = 24.0
	_skip_btn.offset_right = -24.0
	_skip_btn.offset_bottom = 68.0
	_skip_btn.pressed.connect(_on_skip_pressed)
	add_child(_skip_btn)


func play_ogv(ogv_path: String) -> bool:
	if ogv_path.is_empty() or not FileAccess.file_exists(ogv_path):
		return false
	var stream := ResourceLoader.load(ogv_path)
	if stream == null:
		var vstream := VideoStreamTheora.new()
		vstream.file = ogv_path
		stream = vstream
	_player.stream = stream
	_elapsed = 0.0
	_hold_time = 0.0
	_holding = false
	_is_playing = true
	visible = true
	if is_inside_tree():
		_player.play()
	return true


func stop_video() -> void:
	if _is_playing:
		_player.stop()
		_is_playing = false
		visible = false
		video_finished.emit()


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_elapsed += delta
	if _holding and _elapsed >= 1.0:
		_hold_time += delta
		if _hold_time >= 0.45:
			stop_video()


func _gui_input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if event is InputEventScreenTouch:
		_holding = event.pressed
		if not _holding:
			_hold_time = 0.0
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed
		if not _holding:
			_hold_time = 0.0


func _on_skip_pressed() -> void:
	if _elapsed >= 0.8:
		stop_video()


func _on_finished() -> void:
	_is_playing = false
	visible = false
	video_finished.emit()
