extends SceneTree

func _init() -> void:
	var cfg := ConfigManager.new()
	cfg.custom_game_dir = "U:/anti/projects/game"
	var vfs := BgiVfs.new()
	if not vfs.auto_mount(cfg):
		push_error("VFS mount failed")
		quit(1)
		return

	var bp_vm := BgiBpVm.new(vfs)
	var gdb_count := bp_vm.load_gdb_from_vfs("BGI.gdb")
	print("GDB entries: ", gdb_count)
	if gdb_count < 100:
		push_error("GDB entry count too small")
		quit(2)
		return

	var bp_res := bp_vm.execute_bp("nudeprcs._bp")
	print("nudeprcs._bp result: ", bp_res)
	if not bool(bp_res.get("ok", false)):
		push_error("nudeprcs._bp exec failed")
		quit(3)
		return

	bp_vm.set_nude_mode(true)
	var vm := BgiVm.new(vfs, bp_vm)
	var dialogues: Array[String] = []
	var stages: Array[String] = []
	var audios: Array[String] = []

	vm.dialogue_printed.connect(func(text: String, _spk: String, _wait: bool) -> void:
		dialogues.append(text)
	)
	vm.stage_command.connect(func(cmd: String, args: Array) -> void:
		stages.append("%s:%s" % [cmd, str(args)])
	)
	vm.audio_command.connect(func(cmd: String, args: Array) -> void:
		audios.append("%s:%s" % [cmd, str(args)])
	)

	# 1. 运行 setup 与 main
	if not vm.start_script("setup"):
		push_error("setup failed")
		quit(4)
		return
	vm.step_until_wait(5000)
	print("setup telop count=", vm.music_telop.size(), " caption=", vm.caption)

	if not vm.start_script("main"):
		push_error("main failed")
		quit(5)
		return
	vm.step_until_wait(2000)
	print("after main->flow current_script=", vm.current_script)

	# 2. 运行序章 a_prologue01 直到产出前 3 句中文对白
	if not vm.start_script("a_prologue01"):
		push_error("a_prologue01 failed")
		quit(6)
		return
	for _turn in range(5):
		var st := vm.step_until_wait(4000)
		if st == BgiVm.WaitState.CLICK:
			vm.resume_from_click()
		elif st == BgiVm.WaitState.ENDED:
			break

	print("Stages: ", stages)
	print("Audios: ", audios)
	print("Dialogues: ", dialogues)
	if dialogues.size() < 3 or stages.is_empty() or audios.is_empty():
		push_error("Prologue VM did not emit expected stage/audio/dialogue")
		quit(7)
		return

	# 3. 验证已读位图与存档往返
	if not bp_vm.is_line_read("a_prologue01", vm.current_line):
		push_error("Read bitmap not marked")
		quit(8)
		return
	var saved := vm.export_save_state()
	var vm2 := BgiVm.new(vfs, bp_vm)
	if not vm2.import_save_state(saved) or vm2.current_script != "a_prologue01":
		push_error("Save/Load VM state failed")
		quit(9)
		return

	print("STEP3_2_VM_OK")
	quit(0)
