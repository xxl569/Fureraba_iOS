extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame

	if not main.vfs.is_ready():
		push_error("Main VFS not mounted")
		quit(2)
		return

	main.start_new_game()
	for _i in range(3):
		main._advance_dialogue()

	var cur_txt: String = main.vm.last_dialogue_text
	print("Main dialogue after 3 advances: ", cur_txt)
	if cur_txt.is_empty():
		push_error("Dialogue text empty")
		quit(3)
		return

	# Save/Load 往返测试（使用测试槽位 11）
	main._on_save_slot(11)
	main.vm.last_dialogue_text = ""
	main._on_load_slot(11)
	if main.vm.last_dialogue_text != cur_txt:
		push_error("Save/Load dialogue mismatch")
		quit(4)
		return

	main.queue_free()
	print("STEP4_1_MAIN_UI_SAVELOAD_OK")
	quit(0)
