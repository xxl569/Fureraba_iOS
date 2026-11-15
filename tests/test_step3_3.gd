extends SceneTree

func _init() -> void:
	var cfg := ConfigManager.new()
	cfg.custom_game_dir = "U:/anti/projects/game"
	cfg.custom_movie_dir = "U:/anti/temp/Fureraba_iOS/movie"
	var vfs := BgiVfs.new()
	if not vfs.auto_mount(cfg):
		push_error("VFS mount failed")
		quit(1)
		return

	var bp_vm := BgiBpVm.new(vfs)
	var cache := BgiCache.new(12 * 1024 * 1024, 16) # 12 MiB 上限用于测试 LRU 淘汰
	var stage := BgiStage.new()
	stage.setup(vfs, bp_vm, cache)
	root.add_child(stage)

	# 1. 背景 CG 加载 + LRU 淘汰验证
	var cgs := ["miev01_a01", "miev01_a02", "miev02_a01", "miev03_a01", "miev03_a02"]
	var loaded := 0
	for cg in cgs:
		if vfs.has_entry(cg):
			if stage.show_background(cg):
				loaded += 1
	print("Loaded CGs=", loaded, " cache_bytes=", cache.current_bytes, " evictions=", cache.eviction_count)
	if loaded < 3 or cache.current_bytes > cache.max_bytes:
		push_error("Stage CG or LRU budget failed")
		quit(2)
		return

	# 2. 滚动超长切片图 fl_roll_hi
	var slice_cnt := stage.show_scroll_image(1, "fl_roll_hi")
	print("Scroll slices for fl_roll_hi: ", slice_cnt)
	if slice_cnt != 3:
		push_error("Expected 3 slices for fl_roll_hi")
		quit(3)
		return

	# 3. 内存警告释放验证
	var before_warn := cache.current_bytes
	cache.on_memory_warning()
	print("Cache before warn=", before_warn, " after warn=", cache.current_bytes)
	if cache.current_bytes > int(float(cache.max_bytes) * 0.45):
		push_error("Memory warning did not free enough bytes")
		quit(4)
		return

	# 4. 3 通道音频验证
	var audio_mgr := BgiAudioMgr.new()
	audio_mgr.setup(vfs, cfg)
	root.add_child(audio_mgr)
	var bgm_res := audio_mgr.load_ogg_stream("FL_bgm_01")
	var se_res := audio_mgr.load_ogg_stream("click")
	print("BGM res=", bgm_res.get("ok"), " loop=", bgm_res.get("loop"), " SE loop=", se_res.get("loop"))
	if not bool(bgm_res.get("ok", false)) or not bool(bgm_res.get("loop", false)):
		push_error("BGM Ogg loop stream failed")
		quit(5)
		return
	if not bool(se_res.get("ok", false)) or bool(se_res.get("loop", true)):
		push_error("SE Ogg one-shot stream failed")
		quit(6)
		return

	# 5. 视频播放器加载 friendtolover.ogv
	var vplayer := BgiVideoPlayer.new()
	root.add_child(vplayer)
	var ogv := vfs.get_movie_path("friendtolover.ogv")
	if not vplayer.play_ogv(ogv):
		push_error("VideoPlayer play_ogv failed: " + ogv)
		quit(7)
		return
	vplayer.stop_video()

	# 6. 立绘 _DrawBS / _MoveBS / _FadeBS 坐标与表情合成验证
	stage.handle_stage_command("_DrawBS", [4, "GE01SW_N", "GE01_N026", 0, 2, 288, 250, 268435456, 0, 0, 0, 100, 0, -1, -1, 0, 0, -1, 200, 0, 1])
	stage.handle_stage_command("_DrawBS", [5, "MO01SW_N", "MO01_N003", 0, 2, -288, 250, 268435456, 0, 0, 0, 100, 0, -1, -1, 0, 0, -1, 200, 0, 1])
	var node_r := stage._layer_nodes.get(4) as TextureRect
	var node_l := stage._layer_nodes.get(5) as TextureRect
	if node_r == null or node_l == null:
		push_error("Dual bustshot layers missing")
		quit(8)
		return
	var face_r := node_r.get_node_or_null("FaceOverlay") as TextureRect
	if face_r == null or not face_r.visible:
		push_error("FaceOverlay missing or invisible")
		quit(9)
		return
	if absf(node_r.position.x - 288.0) > 1.0 or absf(node_l.position.x + 288.0) > 1.0 or absf(node_r.position.y - 62.5) > 1.0:
		push_error("Bustshot positions incorrect: R=%s L=%s" % [str(node_r.position), str(node_l.position)])
		quit(10)
		return
	# _MoveBS 相对 X 偏移 (+50 -> 268435506) 与绝对 Y (225)
	stage.handle_stage_command("_MoveBS", [5, 0, 0, 268435506, 225, 268435456, 0, 268435456, -1, 25, 0, 1])
	if absf(node_l.position.x - (-238.0)) > 1.0 or absf(node_l.position.y - 37.5) > 1.0:
		push_error("_MoveBS relative/absolute move incorrect: L=%s" % str(node_l.position))
		quit(11)
		return
	# _FadeBS alpha=0 清除图层
	stage.handle_stage_command("_FadeBS", [4, 0, 2, 268435456, 268435456, 268435456, 268435456, 200, 1])
	if stage._layer_nodes.has(4):
		push_error("_FadeBS alpha=0 did not clear layer 4")
		quit(12)
		return
	stage.clear_all_bustshots()

	stage.queue_free()
	audio_mgr.queue_free()
	vplayer.queue_free()
	print("STEP3_3_STAGE_AUDIO_VIDEO_OK")
	quit(0)
