extends Control

## 《フレラバ 〜Friend to Lover〜》iOS/PC 移植版主场景控制器。

var cfg: ConfigManager
var vfs: BgiVfs
var cache: BgiCache
var bp_vm: BgiBpVm
var vm: BgiVm

var stage: BgiStage
var audio_mgr: BgiAudioMgr
var video_player: BgiVideoPlayer
var ui: UiPanels
var gesture_helper: MobileGestureHelper

var _auto_mode: bool = false
var _skip_mode: bool = false
var _resume_skip_after_choice: bool = false
var _last_script_for_skip: String = ""
var _auto_accum: float = 0.0
var _skip_accum: float = 0.0
var _in_game: bool = false
var _in_recollection: bool = false
var _cursor_idle_accum: float = 0.0
var _app_paused_by_focus: bool = false
var _last_bgm_telop_mode: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cfg = ConfigManager.new()
	cfg.load_config()

	cache = BgiCache.new(96 * 1024 * 1024, 128)
	vfs = BgiVfs.new()
	bp_vm = BgiBpVm.new(vfs)
	vm = BgiVm.new(vfs, bp_vm)
	vm.player_family_name = cfg.player_family_name
	vm.player_given_name = cfg.player_given_name

	stage = BgiStage.new()
	stage.screen_effect_mode = cfg.screen_effect_mode
	add_child(stage)

	audio_mgr = BgiAudioMgr.new()
	add_child(audio_mgr)

	ui = UiPanels.new()
	add_child(ui)

	video_player = BgiVideoPlayer.new()
	add_child(video_player)

	gesture_helper = MobileGestureHelper.new()
	add_child(gesture_helper)

	_connect_signals()
	_try_mount_and_init()
	_apply_aspect_mode()


func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		if cache != null:
			cache.on_memory_warning()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if cfg != null and cfg.inactive_behavior == 1:
			_app_paused_by_focus = true
			if DisplayServer.get_name() != "headless":
				AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _app_paused_by_focus:
			_app_paused_by_focus = false
			if DisplayServer.get_name() != "headless":
				AudioServer.set_bus_mute(0, false)
		if vfs != null and not vfs.is_ready():
			_try_mount_and_init()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_cursor_idle_accum = 0.0
		if DisplayServer.get_name() != "headless" and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		var key_str := OS.get_keycode_string(kc).to_upper()
		if kc == KEY_F12:
			_on_toggle_nude()
			get_viewport().set_input_as_handled()
			return
		if kc == KEY_ESCAPE:
			if ui.has_open_modal() and not ui.title_overlay.visible:
				ui._close_all_modals()
			elif _in_recollection:
				ui.show_confirm("sgdialog990010", "确定回到CG模式？", _end_recollection_to_gallery)
			elif _in_game:
				ui.open_system_menu("display", true)
			get_viewport().set_input_as_handled()
			return
		if _in_game and not ui.has_open_modal() and not video_player.visible:
			if _handle_custom_or_default_key(kc, key_str):
				get_viewport().set_input_as_handled()
				return

	# 鼠标右键 / 滚轮↑ / 滚轮↓ 自定义分配功能
	if _in_game and not ui.has_open_modal() and not video_player.visible and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if _in_recollection:
				ui.show_confirm("sgdialog990010", "确定回到CG模式？", _end_recollection_to_gallery)
			else:
				_execute_mouse_assigned_action(cfg.right_click_action)
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_execute_mouse_assigned_action(cfg.wheel_up_action)
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_execute_mouse_assigned_action(cfg.wheel_down_action)
			get_viewport().set_input_as_handled()
			return

	if not _in_game or gesture_helper == null:
		return
	gesture_helper.block_advance = ui.has_open_modal() or video_player.visible
	gesture_helper.is_auto_or_skip_active = _auto_mode or _skip_mode
	if not gesture_helper.block_advance and event.is_action_pressed("ui_accept"):
		_on_user_advance()
		get_viewport().set_input_as_handled()
		return
	if gesture_helper.handle_input_event(event):
		get_viewport().set_input_as_handled()


func _is_key_name_pressed(key_name: String) -> bool:
	var k := key_name.strip_edges().to_upper()
	if k.is_empty():
		return false
	match k:
		"CTRL", "CONTROL":
			return Input.is_key_pressed(KEY_CTRL)
		"SHIFT":
			return Input.is_key_pressed(KEY_SHIFT)
		"ALT":
			return Input.is_key_pressed(KEY_ALT)
		"SPACE":
			return Input.is_key_pressed(KEY_SPACE)
		"ENTER", "RETURN":
			return Input.is_key_pressed(KEY_ENTER)
		_:
			var kc := OS.find_keycode_from_string(k)
			return kc != KEY_NONE and Input.is_key_pressed(kc)


func _handle_custom_or_default_key(kc: int, key_str: String) -> bool:
	if cfg != null:
		for act in cfg.key_bindings.keys():
			if act == "quick_skip":
				continue
			var bound := str(cfg.key_bindings[act]).to_upper()
			if not bound.is_empty() and bound == key_str:
				_execute_shortcut_action(act)
				return true
		return false
	if kc == KEY_H:
		ui.open_log_panel()
		return true
	elif kc == KEY_A:
		_set_auto_mode(not _auto_mode)
		return true
	elif kc == KEY_SPACE:
		ui.toggle_dialogue_visibility()
		return true
	elif kc == KEY_L:
		ui.open_system_menu("load", true)
		return true
	elif kc == KEY_R:
		_set_skip_mode(not _skip_mode)
		return true
	return false


func _execute_shortcut_action(act: String) -> void:
	match act:
		"hide_window":
			ui.toggle_dialogue_visibility()
		"log":
			ui.open_log_panel()
		"auto":
			_set_auto_mode(not _auto_mode)
		"skip":
			_set_skip_mode(not _skip_mode)
		"options":
			ui.open_system_menu("display", true)
		"keys_menu":
			ui.open_system_menu("keys", true)
		"scene_jump":
			if ui._backlog.size() >= 2:
				var prev_item: Dictionary = ui._backlog[ui._backlog.size() - 2]
				var snap: Dictionary = prev_item.get("snapshot", {})
				if not snap.is_empty():
					ui.show_confirm("sgdialog990008", "确定快速跳跃？", func() -> void: _on_quick_jump(snap))
			elif not ui._backlog.is_empty():
				var last_item: Dictionary = ui._backlog[ui._backlog.size() - 1]
				var snap: Dictionary = last_item.get("snapshot", {})
				if not snap.is_empty():
					ui.show_confirm("sgdialog990008", "确定快速跳跃？", func() -> void: _on_quick_jump(snap))
		"save_menu":
			if not _in_recollection:
				ui.open_system_menu("save", true)
		"load_menu":
			ui.open_system_menu("load", true)
		"title":
			ui.show_confirm("sgdialog990001", "确定回到标题？", _return_to_title)
		"quit":
			ui.show_confirm("sgdialog990000", "确定结束游戏?", func() -> void: get_tree().quit())


func _execute_mouse_assigned_action(func_id: String) -> void:
	match func_id:
		"options":
			ui.open_system_menu("display", true)
		"log":
			ui.open_log_panel()
		"hide_window":
			ui.toggle_dialogue_visibility()
		"voice_replay":
			_replay_voice("")
		"auto":
			_set_auto_mode(not _auto_mode)
		"left_click":
			_on_user_advance()
		"skip":
			_set_skip_mode(not _skip_mode)
		"none":
			pass


func _process(delta: float) -> void:
	if _app_paused_by_focus:
		return

	# 光标自动隐藏处理
	if DisplayServer.get_name() != "headless" and cfg != null and cfg.cursor_hide_time in [0, 1]:
		var limit_sec := 5.0 if cfg.cursor_hide_time == 0 else 10.0
		_cursor_idle_accum += delta
		if _cursor_idle_accum >= limit_sec and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if not _in_game or vm == null:
		return

	# 回想剧本播放完毕后自动返回 CG 鉴赏界面
	if _in_recollection and vm.wait_state == BgiVm.WaitState.ENDED:
		_end_recollection_to_gallery()
		return

	if vm.wait_state == BgiVm.WaitState.TIMER:
		vm.wait_timer_sec -= delta
		if vm.wait_timer_sec <= 0.0:
			vm.resume_from_click()
			vm.step_until_wait()
	elif vm.wait_state == BgiVm.WaitState.CLICK:
		var qkey := str(cfg.key_bindings.get("quick_skip", "Ctrl")) if cfg != null else "Ctrl"
		var ctrl_held := not ui.has_open_modal() and _is_key_name_pressed(qkey)
		if _skip_mode or ctrl_held:
			var allow_skip := cfg.skip_unread or bp_vm.is_line_read(vm.current_script, vm.current_line)
			if allow_skip or ctrl_held:
				_skip_accum += delta
				if _skip_accum >= 0.06:
					_skip_accum = 0.0
					_advance_dialogue()
			else:
				_set_skip_mode(false)
		elif _auto_mode and not ui.is_typing():
			_auto_accum += delta
			if _auto_accum >= cfg.auto_delay:
				_auto_accum = 0.0
				_advance_dialogue()


func _connect_signals() -> void:
	vm.dialogue_printed.connect(func(text: String, speaker: String, _w: bool) -> void:
		var snap := vm.export_save_state()
		snap["bustshots"] = stage.export_bustshots_state()
		var is_read := bp_vm.is_line_read(vm.current_script, vm.current_line)
		ui.set_dialogue(text, speaker, vm.last_voice_entry, snap, is_read, vm.last_face_img)
	)
	vm.stage_command.connect(func(cmd: String, args: Array) -> void:
		if cmd == "_PlayMovie":
			_play_opening_movie()
		else:
			stage.handle_stage_command(cmd, args)
	)
	vm.audio_command.connect(audio_mgr.handle_audio_command)
	vm.choice_requested.connect(func(kind: String, options: Array) -> void:
		_set_auto_mode(false)
		# skip_continue_mode: 0=总是继续（选择后自动恢复快进），1=选择支为止，2=一天结束时
		if cfg != null and cfg.skip_continue_mode == 0 and _skip_mode:
			_resume_skip_after_choice = true
		else:
			_resume_skip_after_choice = false
		_set_skip_mode(false)
		ui.show_choices(kind, options)
	)
	vm.vm_script_changed.connect(func(sname: String) -> void:
		if _in_game and _skip_mode and cfg != null and cfg.skip_continue_mode == 2:
			if not _last_script_for_skip.is_empty() and sname != _last_script_for_skip:
				# 跨天/章节剧本切换时停止快进
				if sname.begins_with("b_days_") or sname.begins_with("c_"):
					_set_skip_mode(false)
		_last_script_for_skip = sname
	)

	audio_mgr.bgm_started.connect(ui.show_bgm_telop)

	ui.advance_requested.connect(_on_user_advance)
	ui.auto_toggled.connect(_set_auto_mode)
	ui.skip_toggled.connect(_set_skip_mode)
	ui.save_slot_requested.connect(_on_save_slot)
	ui.load_slot_requested.connect(_on_load_slot)
	ui.quick_save_requested.connect(func() -> void: _on_save_slot(UiPanels.QUICK_SAVE_SLOT))
	ui.quick_load_requested.connect(func() -> void: _on_load_slot(UiPanels.QUICK_SAVE_SLOT))
	ui.voice_replay_requested.connect(_replay_voice)
	ui.test_se_requested.connect(func(se_name: String) -> void: audio_mgr.play_se(se_name))
	ui.quick_jump_requested.connect(_on_quick_jump)
	ui.return_to_title_requested.connect(_return_to_title)
	ui.quit_game_requested.connect(func() -> void: get_tree().quit())
	ui.gallery_play_bgm_requested.connect(func(entry: String) -> void: audio_mgr.play_bgm(entry))
	ui.gallery_stop_bgm_requested.connect(func() -> void: audio_mgr.stop_bgm())
	ui.recollection_requested.connect(_start_recollection)
	ui.config_changed.connect(_on_config_changed)
	ui.rescan_byoa_requested.connect(_try_mount_and_init)
	ui.start_new_game_requested.connect(start_new_game)
	ui.new_game_confirmed.connect(_on_new_game_confirmed)
	ui.play_op_requested.connect(_play_opening_movie)
	ui.choice_selected.connect(func(idx: int) -> void:
		var resume_skip := _resume_skip_after_choice
		_resume_skip_after_choice = false
		vm.resume_with_choice(idx)
		vm.step_until_wait()
		if resume_skip and cfg != null and cfg.skip_continue_mode == 0:
			_set_skip_mode(true)
	)
	ui.nude_quick_toggled.connect(_on_toggle_nude)
	gesture_helper.tap_advance.connect(_on_user_advance)
	gesture_helper.stop_auto_or_skip.connect(func() -> void:
		_set_auto_mode(false)
		_set_skip_mode(false)
	)
	gesture_helper.two_finger_toggle_ui.connect(ui.toggle_dialogue_visibility)
	gesture_helper.three_finger_toggle_nude.connect(_on_toggle_nude)
	gesture_helper.swipe_open_log.connect(ui.open_log_panel)
	video_player.video_finished.connect(func() -> void:
		if not _in_game:
			_show_title_screen()
	)


func _try_mount_and_init() -> void:
	if vfs.auto_mount(cfg):
		ui.hide_byoa_guide()
		stage.setup(vfs, bp_vm, cache)
		stage.screen_effect_mode = cfg.screen_effect_mode
		audio_mgr.setup(vfs, cfg)
		bp_vm.load_gdb_from_vfs("BGI.gdb")
		bp_vm.load_global_read_state()
		bp_vm.set_nude_mode(cfg.nude_mode)
		ui.setup(cfg, vfs.loaded_font, vfs)
		if ui.gallery_panel != null:
			ui.gallery_panel.set_bp_vm(bp_vm)
		_last_bgm_telop_mode = cfg.bgm_telop_mode
		ui.update_nude_indicator(cfg.nude_mode)
		vm.player_family_name = cfg.player_family_name
		vm.player_given_name = cfg.player_given_name
		vm.start_script("setup")
		vm.step_until_wait(5000)
		if not _in_game:
			_show_title_screen()
	else:
		ui.setup(cfg, null, null)
		ui.show_byoa_guide(vfs.get_byoa_guide_text())


func _show_title_screen() -> void:
	ui.show_title_menu(not vfs.get_movie_path("friendtolover.ogv").is_empty())
	if DisplayServer.get_name() != "headless":
		if audio_mgr.current_bgm.is_empty():
			audio_mgr.play_bgm("FL_bgm_01")
		var voices := ["TITLE_HI", "TITLE_MI", "TITLE_RI", "TITLE_YU"]
		audio_mgr.play_voice(voices[randi() % voices.size()])


func _return_to_title() -> void:
	if bp_vm != null:
		bp_vm.save_global_read_state()
	_in_game = false
	_in_recollection = false
	_set_auto_mode(false)
	_set_skip_mode(false)
	stage.clear_all_bustshots()
	audio_mgr.stop_voice()
	audio_mgr.stop_bgm()
	_show_title_screen()


func _exit_tree() -> void:
	if bp_vm != null:
		bp_vm.save_global_read_state()


func _start_recollection(script_name: String, appearance_mode: int) -> void:
	if not vfs.is_ready() or not vfs.has_entry(script_name):
		return
	ui.hide_title_menu()
	if ui.gallery_panel != null:
		ui.gallery_panel.visible = false
	_in_game = true
	_in_recollection = true
	_set_auto_mode(false)
	_set_skip_mode(false)
	vm.player_family_name = cfg.player_family_name
	vm.player_given_name = cfg.player_given_name
	vm.start_script(script_name, 0, true)
	vm.flags[9055] = appearance_mode
	vm.step_until_wait()


func _end_recollection_to_gallery() -> void:
	_in_game = false
	_in_recollection = false
	_set_auto_mode(false)
	_set_skip_mode(false)
	stage.clear_all_bustshots()
	audio_mgr.stop_voice()
	ui.dialogue_panel.visible = false
	ui.quick_menu.visible = false
	ui.show_title_menu(not vfs.get_movie_path("friendtolover.ogv").is_empty())
	if ui.gallery_panel != null:
		ui.gallery_panel.open_gallery(not vfs.get_movie_path("friendtolover.ogv").is_empty())


func _on_new_game_confirmed(skip_prologue: bool, family_name: String, given_name: String) -> void:
	if not vfs.is_ready():
		return
	if not family_name.strip_edges().is_empty():
		cfg.player_family_name = family_name.strip_edges()
	if not given_name.strip_edges().is_empty():
		cfg.player_given_name = given_name.strip_edges()
	cfg.save_config()
	vm.player_family_name = cfg.player_family_name
	vm.player_given_name = cfg.player_given_name

	ui.hide_title_menu()
	_in_game = true
	_in_recollection = false
	_set_auto_mode(false)
	_set_skip_mode(false)
	stage.clear_all_bustshots()
	var entry := "b_days_0422" if (skip_prologue and vfs.has_entry("b_days_0422")) else "a_prologue01"
	vm.start_script(entry, 0, true)
	vm.step_until_wait()


func start_new_game() -> void:
	if not vfs.is_ready():
		return
	vm.player_family_name = cfg.player_family_name
	vm.player_given_name = cfg.player_given_name
	ui.hide_title_menu()
	_in_game = true
	_in_recollection = false
	_set_auto_mode(false)
	_set_skip_mode(false)
	stage.clear_all_bustshots()
	vm.start_script("a_prologue01", 0, true)
	vm.step_until_wait()


func _play_opening_movie() -> void:
	var ogv := vfs.get_movie_path("friendtolover.ogv")
	if not ogv.is_empty():
		audio_mgr.stop_bgm()
		ui.hide_title_menu()
		video_player.play_ogv(ogv)


func _on_user_advance() -> void:
	if _auto_mode:
		if cfg == null or cfg.auto_click_mode == 0:
			_set_auto_mode(false)
		else:
			_auto_accum = 0.0
	if _skip_mode:
		_set_skip_mode(false)
	if ui.is_typing():
		ui.finish_typing()
		return
	if cfg != null and cfg.voice_stop_mode == 0:
		audio_mgr.stop_voice()
	_advance_dialogue()


func _advance_dialogue() -> void:
	if not _in_game or vm == null:
		return
	if vm.wait_state == BgiVm.WaitState.CLICK or vm.wait_state == BgiVm.WaitState.TIMER:
		vm.wait_timer_sec = 0.0
		vm.resume_from_click()
		vm.step_until_wait()
		if _in_recollection and vm.wait_state == BgiVm.WaitState.ENDED:
			_end_recollection_to_gallery()


func _set_auto_mode(on: bool) -> void:
	_auto_mode = on
	_auto_accum = 0.0
	ui.set_auto_state(on)


func _set_skip_mode(on: bool) -> void:
	_skip_mode = on
	_skip_accum = 0.0
	ui.set_skip_state(on)


func _on_toggle_nude() -> void:
	cfg.nude_mode = bp_vm.toggle_nude_mode()
	cfg.save_config()
	ui.update_nude_indicator(cfg.nude_mode)
	stage.refresh_nude_layers()


func _on_config_changed() -> void:
	audio_mgr.apply_volumes()
	stage.screen_effect_mode = cfg.screen_effect_mode
	vm.player_family_name = cfg.player_family_name
	vm.player_given_name = cfg.player_given_name
	ui.apply_text_font()
	_apply_aspect_mode()
	if vfs.is_ready() and cfg.uncensored_mode != vfs.uncensored_active:
		vfs.remount_uncensored(cfg.uncensored_mode)
		cache.clear()
		stage.refresh_nude_layers()
	if cfg.nude_mode != bp_vm.is_nude_mode():
		bp_vm.set_nude_mode(cfg.nude_mode)
		ui.update_nude_indicator(cfg.nude_mode)
		stage.refresh_nude_layers()
	if _last_bgm_telop_mode != cfg.bgm_telop_mode:
		_last_bgm_telop_mode = cfg.bgm_telop_mode
		if not audio_mgr.current_bgm.is_empty():
			ui.show_bgm_telop(audio_mgr.current_bgm)


func _apply_aspect_mode() -> void:
	if get_tree() == null or get_tree().root == null or cfg == null:
		return
	if DisplayServer.get_name() != "headless" and not OS.has_feature("ios"):
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if cfg.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)
	if not cfg.fullscreen:
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		return
	match cfg.widescreen_mode:
		0:
			get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		1:
			get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		2:
			get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH


func _replay_voice(voice_entry: String) -> void:
	var target := voice_entry if not voice_entry.is_empty() else vm.last_voice_entry
	if not target.is_empty():
		audio_mgr.play_voice(target)


func _on_save_slot(slot: int) -> void:
	if not _in_game or _in_recollection:
		return
	if bp_vm != null:
		bp_vm.save_global_read_state()
	var payload := vm.export_save_state()
	payload["read_state"] = bp_vm.export_read_state()
	payload["bustshots"] = stage.export_bustshots_state()
	payload["timestamp"] = Time.get_datetime_string_from_system()
	var shot: Image = null
	if DisplayServer.get_name() != "headless" and get_viewport() != null:
		var tex := get_viewport().get_texture()
		if tex != null:
			shot = tex.get_image()
	ui.save_game_to_slot(slot, payload, shot)


func _on_load_slot(slot: int) -> void:
	var payload := ui.load_game_from_slot(slot)
	if payload.is_empty():
		return
	_restore_from_snapshot(payload)


func _on_quick_jump(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_restore_from_snapshot(snapshot)


func _restore_from_snapshot(payload: Dictionary) -> void:
	var rs: Variant = payload.get("read_state", {})
	if typeof(rs) == TYPE_DICTIONARY:
		bp_vm.import_read_state(rs)
	if vm.import_save_state(payload):
		ui.hide_title_menu()
		_in_game = true
		_in_recollection = false
		stage.clear_all_bustshots()
		if not vm.last_bg.is_empty():
			stage.show_background(vm.last_bg)
		var bs: Variant = payload.get("bustshots", [])
		if typeof(bs) == TYPE_ARRAY and not (bs as Array).is_empty():
			stage.import_bustshots_state(bs as Array)
		if not vm.last_bgm.is_empty():
			audio_mgr.play_bgm(vm.last_bgm)
		if not vm.last_dialogue_text.is_empty():
			var is_read := bp_vm.is_line_read(vm.current_script, vm.current_line)
			ui.set_dialogue(vm.last_dialogue_text, vm.last_speaker, vm.last_voice_entry, payload, is_read, vm.last_face_img)
