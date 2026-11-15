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

	# 6. 验证附录 CG/BGM 鉴赏面板与女主名称
	main.ui.gallery_panel.open_gallery(true)
	if not main.ui.gallery_panel.visible:
		push_error("Gallery panel failed to open")
		quit(9)
		return
	if str(main.ui.gallery_panel.CHAR_TABS[0]["name"]) != "皆原 陽茉莉":
		push_error("Gallery char[0] name mismatch")
		quit(9)
		return
	main.ui.gallery_panel.visible = false

	# 7. 验证返回标题与新游戏姓名输入/跳过序章流程
	main._return_to_title()
	if not main.ui.title_overlay.visible:
		push_error("Return to title failed")
		quit(10)
		return

	main.ui._on_title_btn_pressed(0)
	if not main.ui._name_input_overlay.visible:
		push_error("Name input overlay did not open")
		quit(11)
		return
	main.ui._name_input_overlay.visible = false
	main._on_new_game_confirmed(true, "青叶", "恭介")
	if main.vm.current_script != "b_days_0422":
		push_error("Skip prologue failed to enter b_days_0422: " + main.vm.current_script)
		quit(12)
		return

	# 8. 验证立绘快照导出与恢复
	main.stage.show_bustshot(1, "hi01wa_n", 0.0, 250.0)
	var bs_snap: Array = main.stage.export_bustshots_state()
	if bs_snap.size() != 1:
		push_error("Bustshot snapshot export failed")
		quit(13)
		return
	main.stage.clear_all_bustshots()
	main.stage.import_bustshots_state(bs_snap)
	if main.stage.export_bustshots_state().size() != 1:
		push_error("Bustshot snapshot import failed")
		quit(14)
		return

	main.queue_free()
	print("STEP6_UI_FEATURES_OK")
	quit(0)
