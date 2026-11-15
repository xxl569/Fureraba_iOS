class_name ConfigManager
extends RefCounted
## 全局设置与命令行调试参数管理（user://config.json）

const CONFIG_PATH := "user://config.json"

var uncensored_mode: bool = true
var nude_mode: bool = false
var bgm_volume: float = 0.85
var se_volume: float = 0.90
var voice_volume: float = 1.00
var text_speed: float = 60.0 # 每秒字符数（<=0 表示瞬间显示）
var auto_delay: float = 1.6
var skip_unread: bool = false

var custom_game_dir: String = ""
var custom_movie_dir: String = ""
var debug_script: String = ""


func load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				uncensored_mode = bool(parsed.get("uncensored_mode", uncensored_mode))
				nude_mode = bool(parsed.get("nude_mode", nude_mode))
				bgm_volume = clampf(float(parsed.get("bgm_volume", bgm_volume)), 0.0, 1.0)
				se_volume = clampf(float(parsed.get("se_volume", se_volume)), 0.0, 1.0)
				voice_volume = clampf(float(parsed.get("voice_volume", voice_volume)), 0.0, 1.0)
				text_speed = float(parsed.get("text_speed", text_speed))
				auto_delay = clampf(float(parsed.get("auto_delay", auto_delay)), 0.3, 5.0)
				skip_unread = bool(parsed.get("skip_unread", skip_unread))
				custom_game_dir = str(parsed.get("custom_game_dir", ""))
				custom_movie_dir = str(parsed.get("custom_movie_dir", ""))
	_apply_cmdline_args()


func save_config() -> void:
	var data := {
		"uncensored_mode": uncensored_mode,
		"nude_mode": nude_mode,
		"bgm_volume": bgm_volume,
		"se_volume": se_volume,
		"voice_volume": voice_volume,
		"text_speed": text_speed,
		"auto_delay": auto_delay,
		"skip_unread": skip_unread,
		"custom_game_dir": custom_game_dir,
		"custom_movie_dir": custom_movie_dir,
	}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


func _apply_cmdline_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-dir="):
			custom_game_dir = arg.substr(11).strip_edges()
		elif arg.begins_with("--movie-dir="):
			custom_movie_dir = arg.substr(12).strip_edges()
		elif arg.begins_with("--script="):
			debug_script = arg.substr(9).strip_edges()
		elif arg == "--uncensored":
			uncensored_mode = true
		elif arg == "--censored":
			uncensored_mode = false
		elif arg == "--nude":
			nude_mode = true
