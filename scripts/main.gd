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
	if not _in_game or gesture_helper == null:
		return
	gesture_helper.block_advance = ui.has_open_modal() or video_player.visible
	gesture_helper.is_auto_or_skip_active = _auto_mode or _skip_mode
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
		if _skip_mode:
			var allow_skip := cfg.skip_unread or bp_vm.is_line_read(vm.current_script, vm.current_line)
			if allow_skip:
				_skip_accum += delta
				if _skip_accum >= 0.06:
					_skip_accum = 0.0
					_advance_dialogue()
			else:
				_set_skip_mode(false)
		elif _auto_mode:
			_auto_accum += delta
			if _auto_accum >= cfg.auto_delay:
				_auto_accum = 0.0
				_advance_dialogue()


func _connect_signals() -> void:
	vm.dialogue_printed.connect(func(text: String, speaker: String, _w: bool) -> void:
		ui.set_dialogue(text, speaker)
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
	ui.config_changed.connect(_on_config_changed)
	ui.rescan_byoa_requested.connect(_try_mount_and_init)
	ui.start_new_game_requested.connect(start_new_game)
	ui.play_op_requested.connect(_play_opening_movie)
	ui.choice_selected.connect(func(idx: int) -> void:
		vm.resume_with_choice(idx)
		vm.step_until_wait()
	)
	ui.nude_quick_toggled.connect(_on_toggle_nude)
	gesture_helper.tap_advance.connect(_advance_dialogue)
	gesture_helper.stop_auto_or_skip.connect(func() -> void:
		_set_auto_mode(false)
		_set_skip_mode(false)
	)
	gesture_helper.two_finger_toggle_ui.connect(ui.toggle_dialogue_visibility)
	gesture_helper.three_finger_toggle_nude.connect(_on_toggle_nude)
	gesture_helper.swipe_open_log.connect(ui.open_log_panel)
	video_player.video_finished.connect(func() -> void:
		if not _in_game:
			ui.show_title_menu(not vfs.get_movie_path("friendtolover.ogv").is_empty())
	)


func _try_mount_and_init() -> void:
	if vfs.auto_mount(cfg):
		ui.hide_byoa_guide()
		stage.setup(vfs, bp_vm, cache)
		audio_mgr.setup(vfs, cfg)
		bp_vm.load_gdb_from_vfs("BGI.gdb")
		bp_vm.set_nude_mode(cfg.nude_mode)
		ui.setup(cfg, vfs.loaded_font)
		ui.update_nude_indicator(cfg.nude_mode)
		vm.start_script("setup")
		vm.step_until_wait(5000)
		if not _in_game:
			ui.show_title_menu(not vfs.get_movie_path("friendtolover.ogv").is_empty())
	else:
		ui.setup(cfg, null)
		ui.show_byoa_guide(vfs.get_byoa_guide_text())


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
		ui.hide_title_menu()
		video_player.play_ogv(ogv)


func _on_user_advance() -> void:
	if _auto_mode:
		_set_auto_mode(false)
	if _skip_mode:
		_set_skip_mode(false)
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


func _on_save_slot(slot: int) -> void:
	if not _in_game:
		return
	var payload := vm.export_save_state()
	payload["read_state"] = bp_vm.export_read_state()
	payload["timestamp"] = Time.get_datetime_string_from_system()
	ui.save_game_to_slot(slot, payload)


func _on_load_slot(slot: int) -> void:
	var payload := ui.load_game_from_slot(slot)
	if payload.is_empty():
		return
	var rs: Variant = payload.get("read_state", {})
	if typeof(rs) == TYPE_DICTIONARY:
		bp_vm.import_read_state(rs)
	if vm.import_save_state(payload):
		ui.hide_title_menu()
		_in_game = true
		if not vm.last_bg.is_empty():
			stage.show_background(vm.last_bg)
		if not vm.last_bgm.is_empty():
			audio_mgr.play_bgm(vm.last_bgm)
		if not vm.last_dialogue_text.is_empty():
			ui.set_dialogue(vm.last_dialogue_text, vm.last_speaker)
