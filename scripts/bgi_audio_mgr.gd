class_name BgiAudioMgr
extends Node

## BGI 三通道音频管理器（BGM / SE / Voice）。
## 直接读取 `BgiNative` 提取的 Ogg Vorbis 数据流并按 `loop_flag` 配置循环。

signal bgm_started(bgm_name: String)

var _vfs: BgiVfs
var _cfg: ConfigManager

var bgm_player: AudioStreamPlayer
var se_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer

var current_bgm: String = ""
var current_bgm_loop: bool = false
var current_voice_entry: String = ""
var current_voice_script_vol: float = 1.0


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
	var v_mult := _cfg.get_char_voice_multiplier(current_voice_entry)
	voice_player.volume_db = _linear_to_db_safe(_cfg.voice_volume * v_mult * current_voice_script_vol)


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


func _exit_tree() -> void:
	# 退出树时主动停止并释放流引用，避免 ObjectDB 实例泄漏警告
	for p in [bgm_player, se_player, voice_player]:
		if p != null:
			p.stop()
			p.stream = null


func play_bgm(entry_name: String) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	current_bgm = entry_name
	current_bgm_loop = bool(res["loop"])
	bgm_player.stop()
	bgm_player.stream = stream
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		bgm_player.play()
	bgm_started.emit(entry_name)
	return true


func stop_bgm() -> void:
	bgm_player.stop()
	bgm_player.stream = null
	current_bgm = ""


func stop_voice() -> void:
	voice_player.stop()
	voice_player.stream = null
	current_voice_entry = ""
	current_voice_script_vol = 1.0


func play_se(entry_name: String) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	stream.loop = false
	se_player.stop()
	se_player.stream = stream
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		se_player.play()
	return true


func play_voice(entry_name: String, script_vol_ratio: float = 1.0) -> bool:
	var res := load_ogg_stream(entry_name)
	if not bool(res.get("ok", false)):
		return false
	var stream: AudioStreamOggVorbis = res["stream"]
	stream.loop = false
	current_voice_entry = entry_name
	current_voice_script_vol = clampf(script_vol_ratio, 0.0, 1.0)
	if _cfg != null:
		var v_mult := _cfg.get_char_voice_multiplier(entry_name)
		voice_player.volume_db = _linear_to_db_safe(_cfg.voice_volume * v_mult * current_voice_script_vol)
	voice_player.stop()
	voice_player.stream = stream
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		voice_player.play()
	return true


func handle_audio_command(cmd: String, args: Array) -> void:
	match cmd:
		"_PlayBGM":
			if args.size() >= 2:
				play_bgm(str(args[1]))
		"_FadeBGM", "_StopBGM":
			stop_bgm()
		"_PlaySE", "_PlayStreamSE":
			if args.size() >= 2:
				play_se(str(args[1]))
		"_FadeSE", "_FadeStreamSE", "_StopSE", "_StopStreamSE":
			se_player.stop()
		"_PlayVoice":
			# BGI _PlayVoice 参数约定：[0]=通道, [1]=语音条目名, [2]=脚本音量(0..100), [3]=-1
			var entry := ""
			var vol_ratio := 1.0
			if args.size() >= 2:
				entry = str(args[1])
				if args.size() >= 3:
					vol_ratio = clampf(float(args[2]) / 100.0, 0.0, 1.0)
			elif args.size() == 1 and typeof(args[0]) == TYPE_STRING:
				entry = str(args[0])
			if not entry.is_empty():
				play_voice(entry, vol_ratio)
		"_StopVoice":
			stop_voice()
