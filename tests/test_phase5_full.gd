extends SceneTree

func _init() -> void:
	var cfg := ConfigManager.new()
	cfg.custom_game_dir = "U:/anti/projects/game"
	cfg.uncensored_mode = false
	var vfs := BgiVfs.new()
	if not vfs.auto_mount(cfg):
		push_error("VFS mount failed")
		quit(1)
		return

	var bp_vm := BgiBpVm.new(vfs)
	var vm := BgiVm.new(vfs, bp_vm)

	# 1. 全量扫描所有 BCS1 脚本并加载验证
	var all_entries := vfs.list_entries("")
	var bcs1_count := 0
	var total_insns := 0
	for ename in all_entries:
		if ename.ends_with(".ogv") or ename.ends_with(".arc") or ename.ends_with("._bp"):
			continue
		var sc := vm.load_script(ename)
		if not sc.is_empty():
			bcs1_count += 1
			total_insns += (sc["insns"] as Array).size()
	print("Loaded BCS1 scripts=", bcs1_count, " total_insns=", total_insns)
	if bcs1_count < 200:
		push_error("Expected >= 200 BCS1 scripts, got %d" % bcs1_count)
		quit(2)
		return

	# 2. 无码补丁差分对比 (1536x864 vs 2048x1152)
	var img_cens := vfs.decode_image("miev10_a05_9")
	if img_cens == null:
		push_error("Failed to decode miev10_a05_9 (censored)")
		quit(3)
		return
	var w0 := img_cens.get_width()
	var h0 := img_cens.get_height()

	vfs.remount_uncensored(true)
	var img_uncens := vfs.decode_image("miev10_a05_9")
	if img_uncens == null:
		push_error("Failed to decode miev10_a05_9 (uncensored)")
		quit(4)
		return
	var w1 := img_uncens.get_width()
	var h1 := img_uncens.get_height()
	print("miev10_a05_9 censored=%dx%d uncensored=%dx%d" % [w0, h0, w1, h1])
	if w0 != 1536 or h0 != 864 or w1 != 2048 or h1 != 1152:
		push_error("Uncensored dimension diff mismatch")
		quit(5)
		return

	# 3. 透视差分开关测试
	bp_vm.set_nude_mode(true)
	var nude_sample := ""
	for e in vfs.list_entries(""):
		if e.ends_with("h") and vfs.has_entry(e.left(e.length() - 1)):
			var base := e.left(e.length() - 1)
			if bp_vm.resolve_nude_image_name(base) == e:
				nude_sample = base + " -> " + e
				break
	print("Nude resolve sample: ", nude_sample)
	if nude_sample.is_empty():
		push_error("No nude _h pair resolved")
		quit(6)
		return

	# 4. 内存水位压测 (32 MiB 上限连续加载 25 张高分辨率 CG)
	var cache := BgiCache.new(32 * 1024 * 1024, 64)
	var stage := BgiStage.new()
	stage.setup(vfs, bp_vm, cache)
	root.add_child(stage)
	var stress_cnt := 0
	for e in vfs.list_entries("miev"):
		if stage.show_background(e):
			stress_cnt += 1
			if stress_cnt >= 25:
				break
	print("Stress CGs=", stress_cnt, " cache_bytes=", cache.current_bytes, " evictions=", cache.eviction_count)
	if stress_cnt < 20 or cache.current_bytes > cache.max_bytes or cache.eviction_count == 0:
		push_error("LRU memory stress check failed")
		quit(7)
		return

	cache.on_memory_warning()
	if cache.current_bytes > int(float(cache.max_bytes) * 0.45):
		push_error("OS memory warning shrink failed")
		quit(8)
		return

	stage.queue_free()
	print("STEP5_1_FULL_STRESS_OK")
	quit(0)
