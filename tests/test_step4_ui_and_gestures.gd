extends SceneTree

func _init() -> void:
	var gh := MobileGestureHelper.new()
	root.add_child(gh)

	var st := {"advances": 0, "stops": 0, "two_f": 0, "three_f": 0, "swipes": 0, "chosen": -1}

	gh.tap_advance.connect(func() -> void: st["advances"] += 1)
	gh.stop_auto_or_skip.connect(func() -> void: st["stops"] += 1)
	gh.two_finger_toggle_ui.connect(func() -> void: st["two_f"] += 1)
	gh.three_finger_toggle_nude.connect(func() -> void: st["three_f"] += 1)
	gh.swipe_open_log.connect(func() -> void: st["swipes"] += 1)

	# 1. DEVICE_ID_EMULATION 过滤
	var emu := InputEventMouseButton.new()
	emu.device = MobileGestureHelper.DEVICE_ID_EMULATION
	emu.button_index = MOUSE_BUTTON_LEFT
	emu.pressed = true
	if not gh.handle_input_event(emu) or st["advances"] != 0:
		push_error("DEVICE_ID_EMULATION was not blocked")
		quit(1)
		return

	# 2. Skip/Auto 激活时首次点击只停不跳
	gh.is_auto_or_skip_active = true
	var t_down := InputEventScreenTouch.new()
	t_down.index = 0
	t_down.position = Vector2(500, 400)
	t_down.pressed = true
	gh.handle_input_event(t_down)
	var t_up := InputEventScreenTouch.new()
	t_up.index = 0
	t_up.position = Vector2(500, 400)
	t_up.pressed = false
	gh.handle_input_event(t_up)
	if st["stops"] != 1 or st["advances"] != 0:
		push_error("Skip/Auto tap protection failed")
		quit(2)
		return

	# 3. 正常单指点击推进
	gh.is_auto_or_skip_active = false
	gh.handle_input_event(t_down)
	gh.handle_input_event(t_up)
	if st["advances"] != 1:
		push_error("Normal single tap failed")
		quit(3)
		return

	# 4. 双指轻触隐藏/显示 UI
	var f0_d := InputEventScreenTouch.new(); f0_d.index = 0; f0_d.pressed = true; f0_d.position = Vector2(200, 200)
	var f1_d := InputEventScreenTouch.new(); f1_d.index = 1; f1_d.pressed = true; f1_d.position = Vector2(300, 200)
	var f0_u := InputEventScreenTouch.new(); f0_u.index = 0; f0_u.pressed = false; f0_u.position = Vector2(200, 200)
	var f1_u := InputEventScreenTouch.new(); f1_u.index = 1; f1_u.pressed = false; f1_u.position = Vector2(300, 200)
	gh.handle_input_event(f0_d); gh.handle_input_event(f1_d)
	gh.handle_input_event(f0_u); gh.handle_input_event(f1_u)
	if st["two_f"] != 1:
		push_error("Two-finger toggle UI failed")
		quit(4)
		return

	# 5. 三指轻触切换透视
	var f2_d := InputEventScreenTouch.new(); f2_d.index = 2; f2_d.pressed = true; f2_d.position = Vector2(400, 200)
	var f2_u := InputEventScreenTouch.new(); f2_u.index = 2; f2_u.pressed = false; f2_u.position = Vector2(400, 200)
	gh.handle_input_event(f0_d); gh.handle_input_event(f1_d); gh.handle_input_event(f2_d)
	gh.handle_input_event(f0_u); gh.handle_input_event(f1_u); gh.handle_input_event(f2_u)
	if st["three_f"] != 1:
		push_error("Three-finger toggle nude failed")
		quit(5)
		return

	# 6. 右滑打开 Backlog
	var sd := InputEventScreenTouch.new(); sd.index = 0; sd.pressed = true; sd.position = Vector2(100, 300)
	var sm := InputEventScreenDrag.new(); sm.index = 0; sm.position = Vector2(260, 300)
	var su := InputEventScreenTouch.new(); su.index = 0; su.pressed = false; su.position = Vector2(260, 300)
	gh.handle_input_event(sd); gh.handle_input_event(sm); gh.handle_input_event(su)
	if st["swipes"] != 1:
		push_error("Swipe open log failed")
		quit(6)
		return

	# 7. SMEE SelectTalk 触控分支按钮验证
	var ui := UiPanels.new()
	root.add_child(ui)
	ui.choice_selected.connect(func(idx: int) -> void: st["chosen"] = idx)
	ui.show_choices("SelectTalk", ["聊学校的事", "聊兴趣爱好"])
	var btns: Array[Button] = []
	for child in ui.choice_vbox.get_children():
		if child is Button:
			btns.append(child)
	if btns.size() != 2 or btns[0].custom_minimum_size.y < 48.0:
		push_error("SelectTalk buttons invalid")
		quit(7)
		return
	btns[1].emit_signal("pressed")
	if st["chosen"] != 1:
		push_error("Choice callback index mismatch")
		quit(8)
		return

	# 8. 校验鼠标模拟触控事件 (DEVICE_ID_EMULATION) 不会穿透触发 tap_advance / stop_auto_or_skip
	gh.is_auto_or_skip_active = true
	var emu_d := InputEventScreenTouch.new(); emu_d.device = MobileGestureHelper.DEVICE_ID_EMULATION; emu_d.index = 0; emu_d.pressed = true; emu_d.position = Vector2(200, 200)
	var emu_u := InputEventScreenTouch.new(); emu_u.device = MobileGestureHelper.DEVICE_ID_EMULATION; emu_u.index = 0; emu_u.pressed = false; emu_u.position = Vector2(200, 200)
	var prev_taps: int = st["advances"]
	var prev_stops: int = st["stops"]
	gh.handle_input_event(emu_d); gh.handle_input_event(emu_u)
	if st["advances"] != prev_taps or st["stops"] != prev_stops:
		push_error("Emulated ScreenTouch leaked into tap_advance or stop_auto_or_skip")
		gh.queue_free()
		ui.queue_free()
		await process_frame
		quit(9)
		return

	gh.queue_free()
	ui.queue_free()
	await process_frame
	print("STEP4_2_GESTURES_AND_SMEE_UI_OK")
	quit(0)
