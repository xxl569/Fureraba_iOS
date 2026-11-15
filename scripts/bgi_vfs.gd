class_name BgiVfs
extends RefCounted
## BYOA 外置资产多路径探测与 BgiNative 统一封装

var _native: Object = null
var mounted_game_dir: String = ""
var mounted_movie_dir: String = ""
var entry_count: int = 0
var uncensored_active: bool = false
var has_uncensored_pack: bool = false
var last_error: String = ""
var loaded_font: Font = null


func _init() -> void:
	if ClassDB.class_exists(&"BgiNative"):
		_native = ClassDB.instantiate(&"BgiNative")
	else:
		last_error = "BgiNative GDExtension 未加载"


func is_ready() -> bool:
	return _native != null and entry_count > 0


func auto_mount(cfg: ConfigManager) -> bool:
	var game_candidates := _collect_game_candidates(cfg.custom_game_dir)
	var movie_candidates := _collect_movie_candidates(cfg.custom_movie_dir)

	mounted_movie_dir = ""
	for mdir in movie_candidates:
		if FileAccess.file_exists(mdir.path_join("friendtolover.ogv")):
			mounted_movie_dir = mdir
			break

	for gdir in game_candidates:
		if _looks_like_game_dir(gdir):
			if mount_dir(gdir, cfg.uncensored_mode):
				return true

	last_error = "未在以下目录检测到《フレラバ》原版 .arc 资产：\n" + "\n".join(game_candidates)
	return false


func mount_dir(dir_path: String, uncensored: bool) -> bool:
	if _native == null:
		last_error = "BgiNative 原生解码库未就绪"
		return false
	var norm := dir_path.replace("\\", "/").rstrip("/")
	var cnt: int = _native.mount_game_dir(norm, uncensored)
	if cnt <= 0:
		last_error = "目录挂载失败或无有效条目: %s (code=%d)" % [norm, cnt]
		return false
	mounted_game_dir = norm
	entry_count = cnt
	uncensored_active = uncensored
	has_uncensored_pack = _check_uncensored_pack_exists(norm)
	_load_game_font(norm)
	last_error = ""
	return true


func remount_uncensored(uncensored: bool) -> bool:
	if mounted_game_dir.is_empty():
		return false
	return mount_dir(mounted_game_dir, uncensored)


func has_entry(entry_name: String) -> bool:
	return _native != null and _native.has_entry(entry_name)


func list_entries(prefix: String = "") -> PackedStringArray:
	if _native == null:
		return PackedStringArray()
	return _native.list_entries(prefix)


func extract_raw(entry_name: String) -> PackedByteArray:
	if _native == null:
		return PackedByteArray()
	return _native.extract_raw(entry_name)


func decode_image(entry_name: String) -> Image:
	if _native == null:
		return null
	var d: Dictionary = _native.decode_image_info(entry_name)
	if not d.get("ok", false):
		return null
	return Image.create_from_data(int(d["width"]), int(d["height"]), false, Image.FORMAT_RGBA8, d["data"])


func decode_image_slices(entry_name: String, max_height: int = 4096) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _native == null:
		return out
	var arr: Array = _native.decode_image_slices(entry_name, max_height)
	for item in arr:
		if item is Dictionary:
			var img := Image.create_from_data(int(item["width"]), int(item["height"]), false, Image.FORMAT_RGBA8, item["data"])
			if img != null:
				out.append({
					"image": img,
					"width": int(item["width"]),
					"height": int(item["height"]),
					"y_offset": int(item["y_offset"]),
					"total_height": int(item["total_height"]),
				})
	return out


func extract_audio(entry_name: String) -> Dictionary:
	if _native == null:
		return {"ok": false}
	return _native.extract_audio_info(entry_name)


func get_movie_path(movie_name: String) -> String:
	var base := movie_name.get_file().get_basename()
	var dirs: Array[String] = []
	if not mounted_movie_dir.is_empty():
		dirs.append(mounted_movie_dir)
	if not mounted_game_dir.is_empty():
		dirs.append(mounted_game_dir.path_join("movie"))
		dirs.append(mounted_game_dir)
	dirs.append(OS.get_user_data_dir().path_join("movie"))
	for d in dirs:
		for ext in [".ogv", ".OGV"]:
			var p := d.path_join(base + ext)
			if FileAccess.file_exists(p):
				return p
	return ""


func get_byoa_guide_text() -> String:
	var user_dir := OS.get_user_data_dir()
	return (
		"未检测到《フレラバ 〜Friend to Lover〜》原版资产。\n\n"
		+ "请将 PC 原版目录中的以下文件拷贝到本应用的 Documents 目录：\n"
		+ "1. 根目录文件：sysgrp.arc、sysprg.arc、sysprg2.arc、system.arc\n"
		+ "2. Archive 文件夹：全部 data*.arc（含 data02150.arc/.bak 无码补丁）\n"
		+ "3. 字体文件/GalHei.ttf（推荐，可确保汉化字形完整）\n"
		+ "4. 转码后的过场视频：Documents/movie/friendtolover.ogv\n\n"
		+ "当前沙盒路径：\n" + user_dir
	)


func _collect_game_candidates(custom_dir: String) -> Array[String]:
	var list: Array[String] = []
	if not custom_dir.is_empty():
		list.append(custom_dir)
	var udir := OS.get_user_data_dir()
	list.append(udir)
	list.append(udir.path_join("game"))
	list.append(udir.path_join("Fureraba"))
	if OS.has_feature("ios"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if not docs.is_empty():
			list.append(docs)
			list.append(docs.path_join("game"))
	else:
		# PC 开发调试兜底路径
		list.append("U:/anti/projects/game")
	return list


func _collect_movie_candidates(custom_dir: String) -> Array[String]:
	var list: Array[String] = []
	if not custom_dir.is_empty():
		list.append(custom_dir)
	var udir := OS.get_user_data_dir()
	list.append(udir.path_join("movie"))
	list.append(udir)
	if OS.has_feature("ios"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if not docs.is_empty():
			list.append(docs.path_join("movie"))
			list.append(docs)
	else:
		list.append("U:/anti/temp/Fureraba_iOS/movie")
	return list


func _looks_like_game_dir(dir_path: String) -> bool:
	return (
		FileAccess.file_exists(dir_path.path_join("sysprg.arc"))
		and FileAccess.file_exists(dir_path.path_join("system.arc"))
	)


func _check_uncensored_pack_exists(dir_path: String) -> bool:
	var arch := dir_path.path_join("Archive")
	return (
		FileAccess.file_exists(arch.path_join("data02150.arc"))
		or FileAccess.file_exists(arch.path_join("data02150.arc.bak"))
	)


func _load_game_font(dir_path: String) -> void:
	var font_candidates := [
		dir_path.path_join("字体文件/GalHei.ttf"),
		dir_path.path_join("GalHei.ttf"),
		OS.get_user_data_dir().path_join("GalHei.ttf"),
	]
	for fp in font_candidates:
		if FileAccess.file_exists(fp):
			var ff := FontFile.new()
			if ff.load_dynamic_font(fp) == OK:
				loaded_font = ff
				return
