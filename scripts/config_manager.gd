class_name ConfigManager
extends RefCounted
## 全局设置与命令行调试参数管理（user://config.json）

const CONFIG_PATH := "user://config.json"

# 1. 画面设置 (Display)
var fullscreen: bool = false
var widescreen_mode: int = 1 # 0: 拉伸全屏, 1: 黑边全屏, 2: 原分辨率全屏
var face_window_mode: int = 0 # 0: 通常(显示头像), 1: 分割(不显示头像)
var dialogue_opacity: float = 0.92
var bgm_telop_mode: int = 0 # 0: OFF, 1: 2秒, 2: 4秒, 3: 常时
var screen_effect_mode: int = 0 # 0: 美观, 1: 快速, 2: OFF

# 2. 文本设置 (Text)
var font_name: String = "默认黑体 (GalHei)"
var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var read_text_color: Color = Color(0.68, 0.92, 1.0, 1.0)
var text_speed: float = 60.0 # 每秒字符数（<=0 或 >=115 表示极速显示）
var auto_delay: float = 1.6
var voice_stop_mode: int = 1 # 0: 单击时停止, 1: 播放下一句声音时停止
var skip_unread: bool = true # false: 仅已读, true: 全部
var skip_continue_mode: int = 0 # 0: 总是继续, 1: 选择支为止, 2: 一天结束时
var auto_click_mode: int = 1 # 0: 结束自动模式, 1: 文字显示

# 3. 声音设置 (Sound)
var bgm_volume: float = 0.85
var se_volume: float = 0.90
var voice_volume: float = 1.00
var char_voice_volumes: Dictionary = {
	"hi": 1.0,
	"ri": 1.0,
	"yu": 1.0,
	"mi": 1.0,
	"to": 1.0,
	"mh": 1.0,
	"mk": 1.0,
	"ge": 1.0,
	"mo": 1.0,
	"se": 1.0,
	"w_other": 1.0,
	"m_other": 1.0,
}

# 4. 系统设置 (System)
var cursor_hide_time: int = 2 # 0: 5秒, 1: 10秒, 2: 常驻显示
var cursor_auto_move: bool = true # true: ON, false: OFF
var right_click_action: String = "options" # options, log, hide_window, voice_replay, auto, left_click, skip, none
var wheel_up_action: String = "log"
var wheel_down_action: String = "left_click"
var inactive_behavior: int = 0 # 0: 继续运行, 1: 暂停运行
var confirm_qsave: bool = true
var confirm_qload: bool = true
var confirm_dialogs: bool = true
var uncensored_mode: bool = true
var nude_mode: bool = false

# 5. 快捷键设置 (Shortcut Keys)
var key_bindings: Dictionary = {
	"quick_skip": "Ctrl",
	"hide_window": "Space",
	"log": "H",
	"auto": "A",
	"skip": "R",
	"options": "O",
	"keys_menu": "K",
	"scene_jump": "J",
	"save_menu": "S",
	"load_menu": "L",
	"title": "T",
	"quit": "E",
}

# 6. 主人公姓名 (Name Input - 默认日文写法：青葉 恭介)
var player_family_name: String = "青葉"
var player_given_name: String = "恭介"

# 7. 外置资产与调试参数
var custom_game_dir: String = ""
var custom_movie_dir: String = ""
var debug_script: String = ""


func reset_to_defaults() -> void:
	fullscreen = false
	widescreen_mode = 1
	face_window_mode = 0
	dialogue_opacity = 0.92
	bgm_telop_mode = 0
	screen_effect_mode = 0

	font_name = "默认黑体 (GalHei)"
	text_color = Color(1.0, 1.0, 1.0, 1.0)
	read_text_color = Color(0.68, 0.92, 1.0, 1.0)
	text_speed = 60.0
	auto_delay = 1.6
	voice_stop_mode = 1
	skip_unread = true
	skip_continue_mode = 0
	auto_click_mode = 1

	bgm_volume = 0.85
	se_volume = 0.90
	voice_volume = 1.00
	for k in char_voice_volumes.keys():
		char_voice_volumes[k] = 1.0

	cursor_hide_time = 2
	cursor_auto_move = true
	right_click_action = "options"
	wheel_up_action = "log"
	wheel_down_action = "left_click"
	inactive_behavior = 0
	confirm_qsave = true
	confirm_qload = true
	confirm_dialogs = true

	key_bindings = {
		"quick_skip": "Ctrl",
		"hide_window": "Space",
		"log": "H",
		"auto": "A",
		"skip": "R",
		"options": "O",
		"keys_menu": "K",
		"scene_jump": "J",
		"save_menu": "S",
		"load_menu": "L",
		"title": "T",
		"quit": "E",
	}
	player_family_name = "青葉"
	player_given_name = "恭介"


func get_char_voice_multiplier(voice_name: String) -> float:
	var u := voice_name.to_upper()
	var key := ""
	if u.contains("#HI_") or u.begins_with("TITLE_HI"):
		key = "hi"
	elif u.contains("#RI_") or u.begins_with("TITLE_RI"):
		key = "ri"
	elif u.contains("#YU_") or u.begins_with("TITLE_YU"):
		key = "yu"
	elif u.contains("#MI_") or u.begins_with("TITLE_MI"):
		key = "mi"
	elif u.contains("#TO_"):
		key = "to"
	elif u.contains("#MH_"):
		key = "mh"
	elif u.contains("#MK_"):
		key = "mk"
	elif u.contains("#GE_"):
		key = "ge"
	elif u.contains("#MO_"):
		key = "mo"
	elif u.contains("#SE_"):
		key = "se"
	elif u.contains("#W"):
		key = "w_other"
	elif u.contains("#M"):
		key = "m_other"
	if key.is_empty():
		return 1.0
	return clampf(float(char_voice_volumes.get(key, 1.0)), 0.0, 1.0)


func load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				fullscreen = bool(parsed.get("fullscreen", fullscreen))
				widescreen_mode = clampi(int(parsed.get("widescreen_mode", widescreen_mode)), 0, 2)
				face_window_mode = clampi(int(parsed.get("face_window_mode", face_window_mode)), 0, 1)
				dialogue_opacity = clampf(float(parsed.get("dialogue_opacity", dialogue_opacity)), 0.2, 1.0)
				bgm_telop_mode = clampi(int(parsed.get("bgm_telop_mode", bgm_telop_mode)), 0, 3)
				screen_effect_mode = clampi(int(parsed.get("screen_effect_mode", screen_effect_mode)), 0, 2)

				font_name = str(parsed.get("font_name", font_name))
				if parsed.has("text_color"):
					text_color = Color.from_string(str(parsed.get("text_color")), text_color)
				if parsed.has("read_text_color"):
					read_text_color = Color.from_string(str(parsed.get("read_text_color")), read_text_color)
				text_speed = float(parsed.get("text_speed", text_speed))
				auto_delay = clampf(float(parsed.get("auto_delay", auto_delay)), 0.3, 5.0)
				voice_stop_mode = clampi(int(parsed.get("voice_stop_mode", voice_stop_mode)), 0, 1)
				skip_unread = bool(parsed.get("skip_unread", skip_unread))
				skip_continue_mode = clampi(int(parsed.get("skip_continue_mode", skip_continue_mode)), 0, 2)
				auto_click_mode = clampi(int(parsed.get("auto_click_mode", auto_click_mode)), 0, 1)

				bgm_volume = clampf(float(parsed.get("bgm_volume", bgm_volume)), 0.0, 1.0)
				se_volume = clampf(float(parsed.get("se_volume", se_volume)), 0.0, 1.0)
				voice_volume = clampf(float(parsed.get("voice_volume", voice_volume)), 0.0, 1.0)
				var cv = parsed.get("char_voice_volumes", {})
				if cv is Dictionary:
					for k in char_voice_volumes.keys():
						if cv.has(k):
							char_voice_volumes[k] = clampf(float(cv[k]), 0.0, 1.0)

				cursor_hide_time = clampi(int(parsed.get("cursor_hide_time", cursor_hide_time)), 0, 2)
				cursor_auto_move = bool(parsed.get("cursor_auto_move", cursor_auto_move))
				right_click_action = str(parsed.get("right_click_action", right_click_action))
				wheel_up_action = str(parsed.get("wheel_up_action", wheel_up_action))
				wheel_down_action = str(parsed.get("wheel_down_action", wheel_down_action))
				inactive_behavior = clampi(int(parsed.get("inactive_behavior", inactive_behavior)), 0, 1)
				confirm_qsave = bool(parsed.get("confirm_qsave", confirm_qsave))
				confirm_qload = bool(parsed.get("confirm_qload", confirm_qload))
				confirm_dialogs = bool(parsed.get("confirm_dialogs", confirm_dialogs))
				uncensored_mode = bool(parsed.get("uncensored_mode", uncensored_mode))
				nude_mode = bool(parsed.get("nude_mode", nude_mode))

				var kb = parsed.get("key_bindings", {})
				if kb is Dictionary:
					for k in key_bindings.keys():
						if kb.has(k):
							key_bindings[k] = str(kb[k])

				player_family_name = str(parsed.get("player_family_name", player_family_name))
				player_given_name = str(parsed.get("player_given_name", player_given_name))
				custom_game_dir = str(parsed.get("custom_game_dir", ""))
				custom_movie_dir = str(parsed.get("custom_movie_dir", ""))
	_apply_cmdline_args()


func save_config() -> void:
	var data := {
		"fullscreen": fullscreen,
		"widescreen_mode": widescreen_mode,
		"face_window_mode": face_window_mode,
		"dialogue_opacity": dialogue_opacity,
		"bgm_telop_mode": bgm_telop_mode,
		"screen_effect_mode": screen_effect_mode,
		"font_name": font_name,
		"text_color": text_color.to_html(),
		"read_text_color": read_text_color.to_html(),
		"text_speed": text_speed,
		"auto_delay": auto_delay,
		"voice_stop_mode": voice_stop_mode,
		"skip_unread": skip_unread,
		"skip_continue_mode": skip_continue_mode,
		"auto_click_mode": auto_click_mode,
		"bgm_volume": bgm_volume,
		"se_volume": se_volume,
		"voice_volume": voice_volume,
		"char_voice_volumes": char_voice_volumes.duplicate(),
		"cursor_hide_time": cursor_hide_time,
		"cursor_auto_move": cursor_auto_move,
		"right_click_action": right_click_action,
		"wheel_up_action": wheel_up_action,
		"wheel_down_action": wheel_down_action,
		"inactive_behavior": inactive_behavior,
		"confirm_qsave": confirm_qsave,
		"confirm_qload": confirm_qload,
		"confirm_dialogs": confirm_dialogs,
		"uncensored_mode": uncensored_mode,
		"nude_mode": nude_mode,
		"key_bindings": key_bindings.duplicate(),
		"player_family_name": player_family_name,
		"player_given_name": player_given_name,
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
