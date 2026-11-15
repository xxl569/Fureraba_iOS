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

	# 1. 验证运行时从 VFS 动态提取原版全部 UI 贴图（标题、对白、5 大设置页、存读档、鉴赏、姓名输入、弹窗）
	var required_tex := [
		"sgtitle990000", "sgtitle000000", "sgtitle800000",
		"sgmsgwnd990000", "sgmsgwnd900000", "sgmsgwnd500000", "sgmsgwnd500100",
		"sgmsgwnd000000", "sgmsgwnd000100", "sgmsgwnd000200", "sgmsgwnd000300",
		"sgmsgwnd000400", "sgmsgwnd000500", "sgmsgwnd000600",
		"sgcnfgdsp990000", "sgcnfgdsp900000", "sgcnfgtxt990000",
		"sgcnfgsnd990000", "sgcnfgsnd010002", "sgcnfgsnd011002",
		"sgcnfgsys990000", "sgcnfgkey990000",
		"sgsyswnd000001", "sgsyswnd001001",
		"sglogwnd990000", "sgusdtwnd990000", "sgusdtwnd990001",
		"sggallery990000", "sgnminpt990000", "sgnminpt000000", "sgnminpt000100",
		"sgdialog990000", "sgdialog000000", "sgdialog000100", "sgslctwnd990000",
	]
	for tname in required_tex:
		var t: ImageTexture = main.ui.theme_loader.get_tex(tname)
		if t == null:
			push_error("Missing runtime UI texture: " + tname)
			quit(3)
			return

	# 2. 验证 ConfigManager 全字段持久化与默认值恢复
	main.cfg.dialogue_opacity = 0.75
	main.cfg.confirm_dialogs = false
	main.cfg.widescreen_mode = 2
	main.cfg.face_window_mode = 1
	main.cfg.bgm_telop_mode = 3
	main.cfg.screen_effect_mode = 1
	main.cfg.voice_stop_mode = 1
	main.cfg.skip_continue_mode = 2
	main.cfg.auto_click_mode = 1
	main.cfg.cursor_hide_time = 0
	main.cfg.cursor_auto_move = true
	main.cfg.right_click_action = "hide_window"
	main.cfg.wheel_up_action = "voice_replay"
	main.cfg.char_voice_volumes["hi"] = 0.5
	main.cfg.char_voice_volumes["w_other"] = 0.65
	main.cfg.key_bindings["auto"] = "Z"
	main.cfg.save_config()

	var cfg2 := ConfigManager.new()
	cfg2.load_config()
	if (
		absf(cfg2.dialogue_opacity - 0.75) > 0.01
		or cfg2.confirm_dialogs != false
		or cfg2.widescreen_mode != 2
		or cfg2.face_window_mode != 1
		or cfg2.bgm_telop_mode != 3
		or cfg2.screen_effect_mode != 1
		or cfg2.voice_stop_mode != 1
		or cfg2.skip_continue_mode != 2
		or cfg2.auto_click_mode != 1
		or cfg2.cursor_hide_time != 0
		or cfg2.cursor_auto_move != true
		or cfg2.right_click_action != "hide_window"
		or cfg2.wheel_up_action != "voice_replay"
		or absf(float(cfg2.char_voice_volumes["hi"]) - 0.5) > 0.01
		or absf(cfg2.get_char_voice_multiplier("HIMARI_INSERT02_#HI_012") - 0.5) > 0.01
		or absf(cfg2.get_char_voice_multiplier("HIMARI_INSERT01_#W14_023") - 0.65) > 0.01
		or str(cfg2.key_bindings["auto"]) != "Z"
	):
		push_error("ConfigManager extended fields roundtrip failed")
		quit(4)
		return

	# 恢复默认值
	main.cfg.reset_to_defaults()
	main.cfg.save_config()

	# 3. 验证 7 大系统子页面打开与控件生成
	for page_key in ["display", "text", "sound", "system", "keys", "save", "load"]:
		main.ui.open_system_menu(page_key, true)
		if not main.ui.sys_menu_panel.visible or main.ui._sys_content_root.get_child_count() == 0:
			push_error("System menu page failed to build: " + page_key)
			quit(5)
			return
	main.ui._close_all_modals()

	# 4. 验证 BGM 曲名简体中文横幅 (Telop Banner)
	main.cfg.bgm_telop_mode = 2
	main.ui.show_bgm_telop("FL_bgm_23")
	if not main.ui.bgm_telop_banner.visible or main.ui.bgm_telop_label.text != "♪ 23 : 描绘未来":
		push_error("BGM telop banner mismatch: " + main.ui.bgm_telop_label.text)
		quit(6)
		return

	# 5. 验证 Q.S / Q.L (slot 99) 往返、存档槽位备注持久化与 Log 记录
	main.start_new_game()
	for _i in range(4):
		main._advance_dialogue()
	var saved_line: String = main.vm.last_dialogue_text
	main._on_save_slot(UiPanels.QUICK_SAVE_SLOT)
	main.ui.set_slot_comment(UiPanels.QUICK_SAVE_SLOT, "第一话测试备注")
	if main.ui.get_slot_comment(UiPanels.QUICK_SAVE_SLOT) != "第一话测试备注":
		push_error("Slot comment persistence failed")
		quit(7)
		return
	main._advance_dialogue()
	main._on_load_slot(UiPanels.QUICK_SAVE_SLOT)
	if main.vm.last_dialogue_text != saved_line:
		push_error("Quick Save/Load (slot 99) mismatch")
		quit(8)
		return

	# 6. 验证人物日文原名还原与男主占位符替换
	if (
		main.vm.normalize_speaker("元气") != "元気"
		or main.vm.normalize_speaker("阳茉莉") != "陽茉莉"
		or main.vm.normalize_speaker("柚子由") != "ゆずゆ"
		or main.vm.normalize_speaker("真寻") != "まひろ"
		or main.vm.normalize_speaker("正义") != "正義"
		or main.vm.normalize_speaker("主人公（姓）") != "青葉"
	):
		push_error("Japanese character name normalization failed")
		quit(9)
		return
	if main.vm.normalize_dialogue_text("我是庡恖岞乮惄乯庡恖岞乮柤乯⒗") != "我是青葉恭介・":
		push_error("Protagonist placeholder substitution failed")
		quit(10)
		return

	# 7. 验证 Log 面板打开与结构化记录
	main.ui.open_log_panel()
	if not main.ui.log_panel.visible or main.ui.log_text.text.is_empty():
		push_error("Log panel failed to open or empty")
		quit(11)
		return
	main.ui._close_all_modals()

	# 8. 验证确认弹窗逻辑
	var confirmed := {"ok": false}
	main.cfg.confirm_dialogs = true
	main.ui.show_confirm("sgdialog990005", "test", func() -> void: confirmed["ok"] = true)
	if not main.ui.has_open_modal():
		push_error("Confirm dialog did not open modal")
		quit(12)
		return
	main.ui._confirm_yes_btn.emit_signal("pressed")
	if not confirmed["ok"]:
		push_error("Confirm dialog yes callback failed")
		quit(13)
		return

	# 9. 验证附录 CG/回想/BGM 鉴赏面板、默认外观/变更外观切换与回想剧本启动
	var gp = main.ui.gallery_panel
	gp.open_gallery(true)
	if not gp.visible:
		push_error("Gallery panel failed to open")
		quit(14)
		return
	if str(gp.CHAR_TABS[0]["name"]) != "皆原 陽茉莉" or str(gp.CHAR_TABS[2]["name"]) != "柊 ゆずゆ":
		push_error("Gallery char tab Japanese name mismatch")
		quit(15)
		return
	# 阳茉莉 18 CG + 4 回想 = 22 个缩略图按钮
	if gp._cg_grid.get_child_count() != 22:
		push_error("Expected 22 gallery slots for Himari, got %d" % gp._cg_grid.get_child_count())
		quit(16)
		return
	gp.set_appearance_mode(1)
	if gp._appearance_mode != 1:
		push_error("Gallery appearance mode switch failed")
		quit(17)
		return
	gp.set_appearance_mode(0)
	gp.visible = false

	# 测试回想模式启动 (R_HIMARI_H3, 外观变更=1)
	main._start_recollection("R_HIMARI_H3", 1)
	if not main._in_recollection or main.vm.current_script != "R_HIMARI_H3" or int(main.vm.flags.get(9055, 0)) != 1:
		push_error("Recollection start or flag 9055 failed")
		quit(18)
		return

	# 10. 验证返回标题与新游戏姓名输入（默认日文「青葉」「恭介」）与跳过序章流程
	main._return_to_title()
	if not main.ui.title_overlay.visible:
		push_error("Return to title failed")
		quit(19)
		return

	main.ui._on_title_btn_pressed(0)
	if not main.ui._name_input_overlay.visible:
		push_error("Name input overlay did not open")
		quit(20)
		return
	if main.ui._family_input.text != "青葉" or main.ui._given_input.text != "恭介":
		push_error("Default Japanese player name mismatch: %s %s" % [main.ui._family_input.text, main.ui._given_input.text])
		quit(21)
		return
	main.ui._name_input_overlay.visible = false
	main._on_new_game_confirmed(true, "青葉", "恭介")
	if main.vm.current_script != "b_days_0422":
		push_error("Skip prologue failed to enter b_days_0422: " + main.vm.current_script)
		quit(22)
		return

	# 11. 验证立绘快照导出与恢复
	main.stage.show_bustshot(1, "hi01wa_n", 0.0, 250.0)
	var bs_snap: Array = main.stage.export_bustshots_state()
	if bs_snap.size() != 1:
		push_error("Bustshot snapshot export failed")
		quit(23)
		return
	main.stage.clear_all_bustshots()
	main.stage.import_bustshots_state(bs_snap)
	if main.stage.export_bustshots_state().size() != 1:
		push_error("Bustshot snapshot import failed")
		quit(24)
		return

	# 12. 验证 _SelectEx (op_skip 序章跳过脚本) 正确弹出选项且无数字标志残余
	main.vm.flags[50] = 1
	var op_skip_ok: bool = bool(main.vm.start_script("op_skip"))
	if not op_skip_ok:
		push_error("Failed to load op_skip")
		quit(25)
		return
	main.vm.step_until_wait(200)
	if main.vm.wait_state != main.vm.WaitState.CHOICE:
		push_error("_SelectEx in op_skip did not trigger CHOICE wait state")
		quit(26)
		return
	if main.ui.choice_vbox.get_child_count() != 3:
		push_error("Expected title + 2 choices in op_skip, got %d" % main.ui.choice_vbox.get_child_count())
		quit(27)
		return
	var opt_title := (main.ui.choice_vbox.get_child(0) as Label).text
	var opt0 := (main.ui.choice_vbox.get_child(1) as Button).text
	var opt1 := (main.ui.choice_vbox.get_child(2) as Button).text
	if not opt_title.contains("序章") or opt0.is_valid_int() or opt1.is_valid_int():
		push_error("_SelectEx parsed invalid prompt/options: %s | %s | %s" % [opt_title, opt0, opt1])
		quit(28)
		return

	# 13. 验证 SelectTalk / SelectTopic 过滤尾部数字元数据，不把 "0"/"4" 变成选择支按钮
	main.vm._data_stack = ["话题A", "话题B", 4, 0, 1]
	main.vm._handle_builtin_external("SelectTalk")
	if main.ui.choice_vbox.get_child_count() != 3:
		push_error("SelectTalk failed to filter trailing int flags, children=%d" % main.ui.choice_vbox.get_child_count())
		quit(29)
		return
	main.ui.choice_panel.visible = false

	# 14. 验证附录 select_char 与 480x90 三态缩略图精确切片 (160x90)
	gp.open_gallery(true)
	gp.select_char(3)
	if gp._current_char_idx != 3 or gp._cg_grid.get_child_count() <= 0:
		push_error("Gallery select_char(3) failed")
		quit(30)
		return
	var first_thumb := gp._cg_grid.get_child(0) as TextureButton
	if first_thumb != null and first_thumb.texture_normal is AtlasTexture:
		var at := first_thumb.texture_normal as AtlasTexture
		if at.region.size.x > 200:
			push_error("Gallery 3-state thumbnail was not sliced to 160x90: " + str(at.region.size))
			quit(31)
			return
	gp.visible = false

	# 15. 验证画面设置 1280x720 置灰宽屏选项 & 文本设置交互式字体下拉菜单
	main.cfg.fullscreen = false
	main.ui.open_system_menu("display", true)
	var ws_btn0 := main.ui._sys_content_root.get_node_or_null("BtnWidescreen_0") as Button
	if ws_btn0 == null or not ws_btn0.disabled:
		push_error("Widescreen button should be disabled when fullscreen is false")
		quit(32)
		return
	main.cfg.fullscreen = true

	main.ui.open_system_menu("text", true)
	var btn_font_sel := main.ui._sys_content_root.get_node_or_null("BtnFontSelect") as Button
	var font_dd := main.ui._sys_content_root.get_node_or_null("FontDropdown") as Control
	if btn_font_sel == null or font_dd == null or font_dd.visible:
		push_error("FontDropdown should exist and initially be hidden")
		quit(33)
		return
	btn_font_sel.emit_signal("pressed")
	if not font_dd.visible:
		push_error("FontDropdown did not open on BtnFontSelect click")
		quit(34)
		return
	var f_opt2 := font_dd.get_node_or_null("BtnFontOption_2") as Button
	if f_opt2 == null:
		push_error("Missing BtnFontOption_2")
		quit(35)
		return
	f_opt2.emit_signal("pressed")
	if main.cfg.font_name != "经典宋体 (SimSun)":
		push_error("Font selection via dropdown did not apply/persist: " + main.cfg.font_name)
		quit(36)
		return

	# 16. 验证绑定快捷键不与旧硬编码冲突
	main.cfg.key_bindings["log"] = "B"
	if main._handle_custom_or_default_key(KEY_H, "H"):
		push_error("Unbound key H should not trigger old hardcoded log/hide fallback")
		quit(37)
		return

	# 17. 验证 normalize_speaker 替换与对白框 MOUSE_FILTER_PASS
	if main.vm.normalize_speaker("主人公（名）") != main.vm.player_given_name:
		push_error("normalize_speaker failed for 主人公（名）")
		quit(38)
		return
	if main.ui._msg_bg_rect.mouse_filter != Control.MOUSE_FILTER_PASS:
		push_error("_msg_bg_rect mouse_filter should be PASS so right-click/wheel reaches main")
		quit(39)
		return

	main.cfg.reset_to_defaults()
	main.cfg.save_config()
	main.queue_free()
	print("STEP6_UI_FEATURES_OK")
	quit(0)
