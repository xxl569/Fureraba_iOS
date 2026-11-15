extends SceneTree
## 步骤 3.1 验收测试：GBK/CP932 混合解码 + ConfigManager + BgiVfs BYOA 自动挂载

func _init() -> void:
	# 1. GBK 与 CP932 混合解码验证
	var gbk_bytes := PackedByteArray([0xD2, 0xAA, 0xCC, 0xF8, 0xB9, 0xFD, 0xD0, 0xF2, 0xD5, 0xC2, 0xC2, 0xF0, 0xA3, 0xBF]) # "要跳过序章吗？"
	var gbk_str := GbkCodec.decode_bytes(gbk_bytes, true)
	print("GBK decoded: ", gbk_str)
	assert(gbk_str == "要跳过序章吗？", "GBK 解码不匹配: " + gbk_str)

	var cp932_bytes := PackedByteArray([0x83, 0x74, 0x83, 0x8C, 0x83, 0x89, 0x83, 0x6F]) # "フレラバ"
	var cp932_str := GbkCodec.decode_bytes(cp932_bytes, true)
	print("CP932 decoded: ", cp932_str)
	assert(cp932_str == "フレラバ", "CP932 假名自动消歧不匹配: " + cp932_str)

	# 2. ConfigManager & BgiVfs BYOA 自动挂载
	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := BgiVfs.new()
	var ok := vfs.auto_mount(cfg)
	assert(ok, "auto_mount 失败: " + vfs.last_error)
	assert(vfs.entry_count == 27811, "条目数异常")
	assert(vfs.has_uncensored_pack, "应检测到 data02150 无码包")
	assert(vfs.loaded_font != null, "GalHei.ttf 应自动加载")

	var ogv := vfs.get_movie_path("friendtolover.mpg")
	print("Movie resolved: ", ogv)
	assert(FileAccess.file_exists(ogv), "未能定位转码后的 friendtolover.ogv")

	print("STEP3_1_VFS_GBK_OK")
	quit(0)
