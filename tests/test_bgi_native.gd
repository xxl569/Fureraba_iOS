extends SceneTree
## 步骤 2.2 验收测试：验证 C GDExtension 原生库 BgiNative 在 Godot 4.3 中加载、挂载、解码与切图一致性

func _init() -> void:
	var native = ClassDB.instantiate(&"BgiNative")
	assert(native != null, "BgiNative 类注册失败")

	var game_dir := "U:/anti/projects/game"
	# 1. 有码模式挂载
	var cnt_censored: int = native.mount_game_dir(game_dir, false)
	print("mount(censored) count = ", cnt_censored)
	assert(cnt_censored > 27000, "有码模式挂载条目数异常")
	assert(native.has_entry("a_prologue01"), "缺少 a_prologue01")
	assert(native.has_entry("nudeprcs._bp"), "缺少 nudeprcs._bp")

	# 2. 无码模式挂载（自动识别 data02150.arc.bak）
	var cnt_uncensored: int = native.mount_game_dir(game_dir, true)
	print("mount(uncensored) count = ", cnt_uncensored)
	assert(cnt_uncensored == cnt_censored, "无码模式挂载条目数应一致")

	# 3. DSC 1.00 脚本解压头验证
	var raw_script: PackedByteArray = native.extract_raw("a_prologue01")
	assert(raw_script.size() > 1000, "a_prologue01 解压失败")
	var hdr_str := raw_script.slice(0, 27).get_string_from_ascii()
	assert(hdr_str == "BurikoCompiledScriptVer1.00", "BCS1 头不匹配: " + hdr_str)

	# 4. CBG v1 解码 (32bpp 立绘 + 8bpp 遮罩 + 24bpp 背景 + 无码 CG)
	for img_name in ["hi01wa_n", "effect01", "fl_bg_01a", "hiev08_a01"]:
		var d: Dictionary = native.decode_image_info(img_name)
		assert(d.get("ok", false), "CBG 解码失败: " + img_name)
		var w: int = d["width"]
		var h: int = d["height"]
		var rgba: PackedByteArray = d["data"]
		assert(rgba.size() == w * h * 4, "RGBA 字节数不匹配: " + img_name)
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
		assert(img != null and not img.is_empty(), "Image 创建失败: " + img_name)
		print("CBG OK: ", img_name, " ", w, "x", h)

	# 5. DSC 内嵌 BMP 解码 (sysgrp + data02810)
	for bmp_name in ["sgusdtwnd990001", "talkwindow"]:
		var bd: Dictionary = native.decode_image_info(bmp_name)
		assert(bd.get("ok", false), "DSC BMP 解码失败: " + bmp_name)
		print("DSC BMP OK: ", bmp_name, " ", bd["width"], "x", bd["height"])

	# 6. 超长卷轴图自动分片 (1280x11362 -> 3 片 <=4096)
	var slices: Array = native.decode_image_slices("fl_roll_hi", 4096)
	assert(slices.size() == 3, "fl_roll_hi 分片数量应为 3，实际为 " + str(slices.size()))
	assert(slices[0]["height"] == 4096 and slices[2]["y_offset"] == 8192, "分片偏移异常")
	print("Scroll slices OK: count=", slices.size(), " total_h=", slices[0]["total_height"])

	# 7. bw+Ogg 与 system.arc DSC+bw 音频提取
	for aud_name in ["fl_bgm_01", "click"]:
		var ad: Dictionary = native.extract_audio_info(aud_name)
		assert(ad.get("ok", false), "音频提取失败: " + aud_name)
		var ogg: PackedByteArray = ad["ogg"]
		assert(ogg.slice(0, 4).get_string_from_ascii() == "OggS", "OggS 魔数异常: " + aud_name)
		print("Audio OK: ", aud_name, " sr=", ad["sample_rate"], " loop=", ad["loop_flag"], " bytes=", ogg.size())

	print("STEP2_2_BGI_NATIVE_OK")
	quit(0)
