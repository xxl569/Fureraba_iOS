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
		push_error("VFS not mounted")
		quit(2)
		return

	# 1. 验证运行时从 VFS 动态提取原版 UI 贴图
	var required_tex := [
		"sgtitle990000", "sgtitle000000", "sgtitle800000",
		"sgmsgwnd990000", "sgmsgwnd900000", "sgmsgwnd500000", "sgmsgwnd500100",
		"sglogwnd990000", "sgusdtwnd990000", "sgusdtwnd990001",
		"sggallery990000", "sgdialog990000", "sgslctwnd990000",
	]
	for tname in required_tex:
		var t: ImageTexture = main.ui.theme_loader.get_tex(tname)
		if t == null:
			push_error("Missing runtime UI texture: " + tname)
			quit(3)
			return

	# 2. 验证 ConfigManager 新字段边界与持久化
	main.cfg.dialogue_opacity = 0.75
	main.cfg.confirm_dialogs = false
	main.cfg.save_config()
	var cfg2 := ConfigManager.new()
	cfg2.load_config()
	if absf(cfg2.dialogue_opacity - 0.75) > 0.01 or cfg2.confirm_dialogs != false:
		push_error("ConfigManager new fields roundtrip failed")
		quit(4)
		return
	# 恢复默认值
	main.cfg.dialogue_opacity = 0.92
	main.cfg.confirm_dialogs = true
	main.cfg.save_config()

	# 3. 验证 Q.S / Q.L (slot 99) 往返与 Log 记录
	main.start_new_game()
	for _i in range(4):
		main._advance_dialogue()
	var saved_line: String = main.vm.last_dialogue_text
	main._on_save_slot(UiPanels.QUICK_SAVE_SLOT)
	main._advance_dialogue()
	main._on_load_slot(UiPanels.QUICK_SAVE_SLOT)
	if main.vm.last_dialogue_text != saved_line:
		push_error("Quick Save/Load (slot 99) mismatch")
		quit(5)
		return

	# 4. 验证 Log 面板打开与结构化记录
	main.ui.open_log_panel()
	if not main.ui.log_panel.visible or main.ui.log_text.text.is_empty():
		push_error("Log panel failed to open or empty")
		quit(6)
		return
	main.ui._close_all_modals()

	# 5. 验证确认弹窗逻辑
	var confirmed := {"ok": false}
	main.cfg.confirm_dialogs = true
	main.ui.show_confirm("sgdialog990005", "test", func() -> void: confirmed["ok"] = true)
	if not main.ui.has_open_modal():
		push_error("Confirm dialog did not open modal")
		quit(7)
		return
	main.ui._confirm_yes_btn.emit_signal("pressed")
	if not confirmed["ok"]:
		push_error("Confirm dialog yes callback failed")
		quit(8)
		return

	# 6. 验证附录 CG/BGM 鉴赏面板
	main.ui.gallery_panel.open_gallery(true)
	if not main.ui.gallery_panel.visible:
		push_error("Gallery panel failed to open")
		quit(9)
		return
	main.ui.gallery_panel.visible = false

	# 7. 验证返回标题
	main._return_to_title()
	if not main.ui.title_overlay.visible:
		push_error("Return to title failed")
		quit(10)
		return

	main.queue_free()
	print("STEP6_UI_FEATURES_OK")
	quit(0)
