extends Control

## 《フレラバ 〜Friend to Lover〜》iOS 移植版主场景控制器。

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
var _auto_accum: float = 0.0
var _skip_accum: float = 0.0
var _in_game: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cfg = ConfigManager.new()
	cfg.load_config()

	cache = BgiCache.new(96 * 1024 * 1024, 128)
	vfs = BgiVfs.new()
	bp_vm = BgiBpVm.new(vfs)
	vm = BgiVm.new(vfs, bp_vm)

	stage = BgiStage.new()
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		if cache != null:
			cache.on_memory_warning()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if vfs != null and not vfs.is_ready():
			_try_mount_and_init()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == KEY_F12:
			_on_toggle_nude()
			get_viewport().set_input_as_handled()
			return
		if kc == KEY_ESCAPE:
			if ui.has_open_modal() and not ui.title_overlay.visible:
				ui._close_all_modals()
			elif _in_game:
				ui.open_system_menu("display", true)
			get_viewport().set_input_as_handled()
			return
		if _in_game and not ui.has_open_modal() and not video_player.visible:
			if kc == KEY_H:
				ui.toggle_dialogue_visibility()
				get_viewport().set_input_as_handled()
				return
			elif kc == KEY_A:
				_set_auto_mode(not _auto_mode)
				get_viewport().set_input_as_handled()
				return
			elif kc == KEY_SPACE:
				_set_skip_mode(not _skip_mode)
				get_viewport().set_input_as_handled()
				return
			elif kc == KEY_L:
				ui.open_log_panel()
				get_viewport().set_input_as_handled()
				return
			elif kc == KEY_R:
				_replay_voice("")
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


func _process(delta: float) -> void:
	if not _in_game or vm == null:
		return
	if vm.wait_state == BgiVm.WaitState.TIMER:
		vm.wait_timer_sec -= delta
		if vm.wait_timer_sec <= 0.0:
			vm.resume_from_click()
			vm.step_until_wait()
	elif vm.wait_state == BgiVm.WaitState.CLICK:
		# Ctrl 键按住时临时快进
		var ctrl_held := not ui.has_open_modal() and Input.is_key_pressed(KEY_CTRL)
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
		var snap := {}
		if DisplayServer.get_name() != "headless":
			snap = vm.export_save_state()
			snap["bustshots"] = stage.export_bustshots_state()
		ui.set_dialogue(text, speaker, vm.last_voice_entry, snap)
	)
	vm.stage_command.connect(stage.handle_stage_command)
	vm.audio_command.connect(audio_mgr.handle_audio_command)
	vm.choice_requested.connect(func(kind: String, options: Array) -> void:
		_set_auto_mode(false)
		_set_skip_mode(false)
		ui.show_choices(kind, options)
	)

	ui.advance_requested.connect(_on_user_advance)
	ui.auto_toggled.connect(_set_auto_mode)
	ui.skip_toggled.connect(_set_skip_mode)
	ui.save_slot_requested.connect(_on_save_slot)
	ui.load_slot_requested.connect(_on_load_slot)
	ui.quick_save_requested.connect(func() -> void: _on_save_slot(UiPanels.QUICK_SAVE_SLOT))
	ui.quick_load_requested.connect(func() -> void: _on_load_slot(UiPanels.QUICK_SAVE_SLOT))
	ui.voice_replay_requested.connect(_replay_voice)
	ui.quick_jump_requested.connect(_on_quick_jump)
	ui.return_to_title_requested.connect(_return_to_title)
	ui.quit_game_requested.connect(func() -> void: get_tree().quit())
	ui.gallery_play_bgm_requested.connect(func(entry: String) -> void: audio_mgr.play_bgm(entry))
	ui.gallery_stop_bgm_requested.connect(func() -> void: audio_mgr.stop_bgm())
	ui.config_changed.connect(_on_config_changed)
	ui.rescan_byoa_requested.connect(_try_mount_and_init)
	ui.start_new_game_requested.connect(start_new_game)
	ui.new_game_confirmed.connect(_on_new_game_confirmed)
	ui.play_op_requested.connect(_play_opening_movie)
	ui.choice_selected.connect(func(idx: int) -> void:
		vm.resume_with_choice(idx)
		vm.step_until_wait()
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
		audio_mgr.setup(vfs, cfg)
		bp_vm.load_gdb_from_vfs("BGI.gdb")
		bp_vm.set_nude_mode(cfg.nude_mode)
		ui.setup(cfg, vfs.loaded_font, vfs)
		ui.update_nude_indicator(cfg.nude_mode)
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
	_in_game = false
	_set_auto_mode(false)
	_set_skip_mode(false)
	stage.clear_all_bustshots()
	audio_mgr.voice_player.stop()
	audio_mgr.stop_bgm()
	_show_title_screen()


func _on_new_game_confirmed(skip_prologue: bool, _family_name: String, _given_name: String) -> void:
	if not vfs.is_ready():
		return
	ui.hide_title_menu()
	_in_game = true
	_set_auto_mode(false)
	_set_skip_mode(false)
	var entry := "b_days_0422" if (skip_prologue and vfs.has_entry("b_days_0422")) else "a_prologue01"
	vm.start_script(entry, 0, true)
	vm.step_until_wait()


func start_new_game() -> void:
	if not vfs.is_ready():
		return
	ui.hide_title_menu()
	_in_game = true
	_set_auto_mode(false)
	_set_skip_mode(false)
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
		_set_auto_mode(false)
	if _skip_mode:
		_set_skip_mode(false)
	if ui.is_typing():
		ui.finish_typing()
		return
	_advance_dialogue()


func _advance_dialogue() -> void:
	if not _in_game or vm == null:
		return
	if vm.wait_state == BgiVm.WaitState.CLICK:
		vm.resume_from_click()
		vm.step_until_wait()


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
	if vfs.is_ready() and cfg.uncensored_mode != vfs.uncensored_active:
		vfs.remount_uncensored(cfg.uncensored_mode)
		cache.clear()
		stage.refresh_nude_layers()
	if cfg.nude_mode != bp_vm.is_nude_mode():
		bp_vm.set_nude_mode(cfg.nude_mode)
		ui.update_nude_indicator(cfg.nude_mode)
		stage.refresh_nude_layers()


func _replay_voice(voice_entry: String) -> void:
	var target := voice_entry if not voice_entry.is_empty() else vm.last_voice_entry
	if not target.is_empty():
		audio_mgr.play_voice(target)


func _on_save_slot(slot: int) -> void:
	if not _in_game:
		return
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
		stage.clear_all_bustshots()
		if not vm.last_bg.is_empty():
			stage.show_background(vm.last_bg)
		var bs: Variant = payload.get("bustshots", [])
		if typeof(bs) == TYPE_ARRAY and not (bs as Array).is_empty():
			stage.import_bustshots_state(bs as Array)
		if not vm.last_bgm.is_empty():
			audio_mgr.play_bgm(vm.last_bgm)
		if not vm.last_dialogue_text.is_empty():
			ui.set_dialogue(vm.last_dialogue_text, vm.last_speaker, vm.last_voice_entry, payload)
