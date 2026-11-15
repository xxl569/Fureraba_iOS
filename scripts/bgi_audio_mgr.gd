class_name BgiAudioMgr
extends Node

## BGI 三通道音频管理器（BGM / SE / Voice）。
## 直接读取 `BgiNative` 提取的 Ogg Vorbis 数据流并按 `loop_flag` 配置循环。

var _vfs: BgiVfs
var _cfg: ConfigManager

var bgm_player: AudioStreamPlayer
var se_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer

var current_bgm: String = ""
var current_bgm_loop: bool = false


func _init() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	add_child(bgm_player)

	se_player = AudioStreamPlayer.new()
	se_player.name = "SePlayer"
	add_child(se_player)

	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	add_child(voice_player)


func setup(vfs: BgiVfs, cfg: ConfigManager) -> void:
	_vfs = vfs
	_cfg = cfg
	apply_volumes()


func apply_volumes() -> void:
	if _cfg == null:
		return
	bgm_player.volume_db = _linear_to_db_safe(_cfg.bgm_volume)
	se_player.volume_db = _linear_to_db_safe(_cfg.se_volume)
	voice_player.volume_db = _linear_to_db_safe(_cfg.voice_volume)


func _linear_to_db_safe(val: float) -> float:
	if val <= 0.001:
		return -80.0
	return linear_to_db(clampf(val, 0.0, 1.0))


func load_ogg_stream(entry_name: String) -> Dictionary:
	if _vfs == null or not _vfs.has_entry(entry_name):
		return {"ok": false}
	var info: Dictionary = _vfs.extract_audio(entry_name)
	if not bool(info.get("ok", false)):
		return {"ok": false}
	var ogg: PackedByteArray = info["ogg"]
	var stream := AudioStreamOggVorbis.load_from_buffer(ogg)
	if stream == null:
		return {"ok": false}
	var loop := int(info.get("loop_flag", 0)) == 1
	stream.loop = loop
	return {
		"ok": true,
		"stream": stream,
		"loop": loop,
		"sample_rate": int(info.get("sample_rate", 44100)),
	}


func play_bgm(entry_name: String) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	current_bgm = entry_name
	current_bgm_loop = bool(res["loop"])
	bgm_player.stream = stream
	if is_inside_tree():
		bgm_player.play()
	return true


func stop_bgm() -> void:
	bgm_player.stop()
	current_bgm = ""


func play_se(entry_name: String) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	stream.loop = false
	se_player.stream = stream
	if is_inside_tree():
		se_player.play()
	return true


func play_voice(entry_name: String) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	stream.loop = false
	voice_player.stream = stream
	if is_inside_tree():
		voice_player.play()
	return true


func handle_audio_command(cmd: String, args: Array) -> void:
	match cmd:
		"_PlayBGM":
			if args.size() >= 2:
				play_bgm(str(args[1]))
		"_FadeBGM":
			stop_bgm()
		"_PlaySE", "_PlayStreamSE":
			if args.size() >= 2:
				play_se(str(args[1]))
		"_FadeSE", "_FadeStreamSE":
			se_player.stop()
		"_PlayVoice":
			if args.size() >= 1:
				play_voice(str(args[0]))
