class_name BgiVm
extends RefCounted

## BGI / Ethornell `BCS1` (`BurikoCompiledScriptVer1.00`) 栈式虚拟机。
## 负责加载、反汇编并执行 `.bs5`/`.bsc` 场景与系统脚本，
## 桥接画面舞台指令、音频指令、对白输出、SMEE 交互分支与 `BGI.gdb` 已读记录。

signal dialogue_printed(text: String, speaker: String, wait_click: bool)
signal text_cleared()
signal stage_command(cmd: String, args: Array)
signal audio_command(cmd: String, args: Array)
signal choice_requested(kind: String, options: Array)
signal vm_script_changed(script_name: String)
signal vm_ended()

enum WaitState {
	NONE = 0,
	CLICK = 1,
	TIMER = 2,
	CHOICE = 3,
	ENDED = 4,
}

const BCS1_MAGIC_PREFIX := "BurikoCompiledScriptVer1.00"

var _vfs: BgiVfs
var _bp_vm: BgiBpVm
var _script_cache: Dictionary = {} # lower_name -> Dictionary
var _exports_map: Dictionary = {}  # fn_name -> {script: String, offset: int}

var _op_args: Dictionary = {}

# 运行时寄存器与内存
var current_script: String = ""
var _insns: Array = []
var _offset_to_idx: Dictionary = {}
var _strings: Dictionary = {}
var _ip: int = 0
var _sp: int = 0x10000
var _retval: Variant = 0
var _data_stack: Array = []
var _mem: Dictionary = {}
var _call_stack: Array[Dictionary] = []
var _exc_stack: Array[int] = []

var wait_state: int = WaitState.NONE
var wait_timer_sec: float = 0.0
var last_dialogue_text: String = ""
var last_speaker: String = ""
var last_voice_entry: String = ""
var last_bg: String = ""
var last_bgm: String = ""
var last_face_img: String = ""
var current_line: int = 0
var current_src_file: String = ""
var flags: Dictionary = {}
var _sys_work: Dictionary = {}
var _pending_read_script: String = ""
var _pending_read_line: int = -1
var caption: String = "フレラバ 〜Friend to Lover〜"
var player_family_name: String = "青葉"
var player_given_name: String = "恭介"
var music_telop: Dictionary = {}
var unknown_opcodes: Dictionary = {}
var unknown_externals: Dictionary = {}

const SPEAKER_JP_MAP: Dictionary = {
	"阳茉莉": "陽茉莉",
	"皆原 阳茉莉": "皆原 陽茉莉",
	"阳茉莉妈妈": "陽茉莉的妈妈",
	"阳茉莉爸爸": "陽茉莉的爸爸",
	"理奈": "理奈",
	"望月 理奈": "望月 理奈",
	"柚夕": "ゆずゆ",
	"柊 柚夕": "柊 ゆずゆ",
	"柚夕的妈妈": "ゆずゆ的妈妈",
	"柚夕的弟弟": "ゆずゆ的弟弟",
	"柚子由": "ゆずゆ",
	"柊 柚子由": "柊 ゆずゆ",
	"柚子由的妈妈": "ゆずゆ的妈妈",
	"柚子由妈妈": "ゆずゆ的妈妈",
	"柚子由的弟弟": "ゆずゆ的弟弟",
	"柚子由弟弟": "ゆずゆ的弟弟",
	"岬": "岬",
	"泽渡 岬": "沢渡 岬",
	"元气": "元気",
	"濑野 元气": "瀬野 元気",
	"智美": "智美",
	"野野村 智美": "野々村 智美",
	"真寻": "まひろ",
	"绫部 真寻": "綾部 まひろ",
	"真子": "真子",
	"水澄 真子": "水澄 真子",
	"桃": "桃",
	"须贺崎 桃": "須賀崎 桃",
	"正义": "正義",
	"近藤 正义": "近藤 正義",
	"青叶 恭介": "青葉 恭介",
	"青叶": "青葉",
	"水野 菜菜": "水野 菜々",
	"百百濑 实里": "百々瀬 みのり",
	"女子生徒Ａ": "女学生Ａ",
	"男子生徒Ａ": "男学生Ａ",
}


func _init(vfs: BgiVfs = null, bp_vm: BgiBpVm = null) -> void:
	_vfs = vfs
	_bp_vm = bp_vm
	_init_op_table()


func _init_op_table() -> void:
	for op in [0x00, 0x01, 0x02, 0x03, 0x08, 0x09, 0x0A, 0x19]:
		_op_args[op] = 1
	_op_args[0x3F] = 2
	_op_args[0x7F] = 2
	for op in [0x10, 0x11, 0x18]:
		_op_args[op] = 0
	for op in range(0x1A, 0x2C):
		_op_args[op] = 0
	for op in range(0x30, 0x3B):
		_op_args[op] = 0
	for op in range(0x80, 0x400):
		_op_args[op] = 0


func set_vfs(vfs: BgiVfs, bp_vm: BgiBpVm = null) -> void:
	_vfs = vfs
	if bp_vm != null:
		_bp_vm = bp_vm


func load_script(name: String) -> Dictionary:
	var key := name.to_lower()
	if _script_cache.has(key):
		return _script_cache[key]
	if _vfs == null or not _vfs.has_entry(name):
		return {}
	var raw := _vfs.extract_raw(name)
	if raw.size() < 36:
		return {}
	var magic_slice := raw.slice(0, 28)
	var nul := magic_slice.find(0)
	if nul >= 0:
		magic_slice = magic_slice.slice(0, nul)
	var magic := magic_slice.get_string_from_ascii()
	if not magic.begins_with(BCS1_MAGIC_PREFIX):
		return {}

	var hdr_size := raw.decode_u32(28)
	var import_count := raw.decode_u32(32)
	var code_start := 28 + hdr_size
	if code_start > raw.size():
		return {}

	var pos := 36
	var imports: Array[String] = []
	for _i in range(import_count):
		if pos >= code_start:
			break
		var r := _read_ascii_cstr(raw, pos)
		imports.append(str(r["text"]))
		pos = int(r["next"])

	var exports: Array[Dictionary] = []
	if pos + 4 <= code_start:
		var export_count := raw.decode_u32(pos)
		pos += 4
		for _i in range(export_count):
			if pos >= code_start:
				break
			var r2 := _read_ascii_cstr(raw, pos)
			var ename := str(r2["text"])
			pos = int(r2["next"])
			var off := 0
			if pos + 4 <= code_start:
				off = raw.decode_u32(pos)
				pos += 4
			exports.append({"name": ename, "offset": off})
			_exports_map[ename] = {"script": name, "offset": off}

	var total_words := (raw.size() - code_start) / 4
	var insns: Array[Dictionary] = []
	var offset_to_idx: Dictionary = {}
	var strings: Dictionary = {}
	var min_str_abs := raw.size()
	var pc := 0

	while pc < total_words and (code_start + pc * 4) < min_str_abs:
		var op := raw.decode_u32(code_start + pc * 4)
		if not _op_args.has(op):
			break
		var nargs: int = int(_op_args[op])
		if pc + 1 + nargs > total_words:
			break
		var a0 := 0
		var a1 := 0
		if nargs >= 1:
			a0 = raw.decode_s32(code_start + (pc + 1) * 4)
		if nargs >= 2:
			a1 = raw.decode_s32(code_start + (pc + 2) * 4)

		if op == 0x03 or op == 0x7F:
			var str_rel := raw.decode_u32(code_start + (pc + 1) * 4)
			var str_abs := code_start + str_rel
			if str_abs >= code_start and str_abs < raw.size():
				if str_abs < min_str_abs:
					min_str_abs = str_abs
				if not strings.has(str_rel):
					var end := str_abs
					while end < raw.size() and raw[end] != 0:
						end += 1
					var sb := raw.slice(str_abs, end)
					strings[str_rel] = GbkCodec.decode_bytes(sb, op == 0x03)

		var byte_off := pc * 4
		offset_to_idx[byte_off] = insns.size()
		insns.append({
			"offset": byte_off,
			"op": op,
			"a0": a0,
			"a1": a1,
		})
		pc += 1 + nargs

	var parsed := {
		"name": name,
		"imports": imports,
		"exports": exports,
		"insns": insns,
		"offset_to_idx": offset_to_idx,
		"strings": strings,
	}
	_script_cache[key] = parsed

	# 预加载导入模块以注册导出函数
	for imp in imports:
		if imp.to_lower() != key and _vfs.has_entry(imp):
			load_script(imp)

	return parsed


func start_script(name: String, entry_offset: int = 0, reset_state: bool = true) -> bool:
	var sc := load_script(name)
	if sc.is_empty():
		return false
	if reset_state:
		_data_stack.clear()
		_mem.clear()
		_call_stack.clear()
		_exc_stack.clear()
		_sys_work.clear()
		_pending_read_script = ""
		_pending_read_line = -1
		_sp = 0x10000
		wait_state = WaitState.NONE
		wait_timer_sec = 0.0
	elif _bp_vm != null:
		_bp_vm.save_global_read_state()
	current_script = name
	_insns = sc["insns"]
	_offset_to_idx = sc["offset_to_idx"]
	_strings = sc["strings"]
	_ip = int(_offset_to_idx.get(entry_offset, 0))
	vm_script_changed.emit(name)
	return true


func _mark_pending_line_read() -> void:
	if _bp_vm != null and not _pending_read_script.is_empty() and _pending_read_line >= 0:
		_bp_vm.mark_line_read(_pending_read_script, _pending_read_line)
	_pending_read_script = ""
	_pending_read_line = -1


func resume_from_click() -> void:
	if wait_state == WaitState.CLICK or wait_state == WaitState.TIMER:
		if wait_state == WaitState.CLICK:
			_mark_pending_line_read()
			last_voice_entry = ""
		wait_state = WaitState.NONE
		wait_timer_sec = 0.0


func resume_with_choice(choice_index: int) -> void:
	if wait_state == WaitState.CHOICE:
		_mark_pending_line_read()
		_retval = choice_index
		flags[0] = choice_index
		wait_state = WaitState.NONE


func step_until_wait(max_steps: int = 8000) -> int:
	## 连续执行指令，直到遇到对白等待、计时器、分支选择或脚本结束。
	var steps := 0
	while wait_state == WaitState.NONE and steps < max_steps:
		if _ip < 0 or _ip >= _insns.size():
			if not _pop_call_frame():
				wait_state = WaitState.ENDED
				vm_ended.emit()
				break
			continue
		steps += 1
		_exec_one()
	return wait_state


func _exec_one() -> void:
	var ins: Dictionary = _insns[_ip]
	var op: int = int(ins["op"])
	var a0: int = int(ins["a0"])
	var a1: int = int(ins["a1"])
	var off: int = int(ins["offset"])

	match op:
		0x00: # PUSH_INT
			_data_stack.append(a0)
		0x01: # PUSH_ADDR_ABS (BCS1 代码段绝对字节偏移)
			_data_stack.append(a0)
		0x02: # PUSH_OFFSET
			_data_stack.append(_sp - a0)
		0x03: # PUSH_STR
			var urel := a0 & 0xFFFFFFFF
			_data_stack.append(str(_strings.get(urel, "")))
		0x08: # READ_MEM
			var addr := _pop_int()
			_data_stack.append(_mem.get(addr, 0))
		0x09: # WRITE_MEM
			var val = _pop_any()
			var addr := _pop_int()
			_mem[addr] = val
		0x0A: # POP_VAR
			var addr := _pop_int()
			_mem[addr] = _pop_any()
		0x10: # PUSH_SP
			_data_stack.append(_sp)
		0x11: # POP_SP
			_sp = _pop_int()
		0x18: # JMP
			var target := _pop_int()
			if _offset_to_idx.has(target):
				_ip = int(_offset_to_idx[target])
				return
		0x19: # JCC
			var target := _pop_int()
			var cond := _pop_int()
			if (a0 == 0 and cond == 0) or (a0 != 0 and cond != 0):
				if _offset_to_idx.has(target):
					_ip = int(_offset_to_idx[target])
					return
		0x1A: # CALL
			var target := _pop_int()
			if _offset_to_idx.has(target):
				_push_call_frame(_ip + 1)
				_ip = int(_offset_to_idx[target])
				return
		0x1B: # RET
			if not _pop_call_frame():
				wait_state = WaitState.ENDED
				vm_ended.emit()
				return
			return
		0x1C: # CALL_EXTERNAL
			var fn_name := str(_pop_any())
			if _is_intercepted_external(fn_name):
				_handle_builtin_external(fn_name)
			elif _exports_map.has(fn_name):
				var exp: Dictionary = _exports_map[fn_name]
				var target_script := str(exp["script"])
				var target_off := int(exp["offset"])
				_push_call_frame(_ip + 1)
				start_script(target_script, target_off, false)
				return
			else:
				_handle_builtin_external(fn_name)
		0x1D: # SET_RETVAL
			_retval = _pop_any()
		0x1E: # REG_EXCEPTION
			var handler := _pop_int()
			_exc_stack.append(handler)
		0x1F: # UNREG_EXCEPTION
			if not _exc_stack.is_empty():
				_exc_stack.pop_back()
		0x20: # ADD
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a + b)
		0x21: # SUB
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a - b)
		0x22: # MUL
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a * b)
		0x23: # DIV
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a / b if b != 0 else 0)
		0x24: # MOD
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a % b if b != 0 else 0)
		0x25: # AND
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a & b)
		0x26: # OR
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a | b)
		0x27: # XOR
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(a ^ b)
		0x28: # SHL
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(_to_i32(a << clampi(b, 0, 31)))
		0x29: # BGI SHL (<<)
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(_to_i32(a << clampi(b, 0, 31)))
		0x2B: # BGI SAR (>>)
			var b := _pop_int()
			var a := _to_i32(_pop_int())
			_data_stack.append(a >> clampi(b, 0, 31))
		0x30: # CMP_EQ
			var b = _pop_any()
			var a = _pop_any()
			_data_stack.append(1 if a == b else 0)
		0x31: # CMP_NE
			var b = _pop_any()
			var a = _pop_any()
			_data_stack.append(1 if a != b else 0)
		0x32: # CMP_LE
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if a <= b else 0)
		0x33: # CMP_GE
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if a >= b else 0)
		0x34: # CMP_LT
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if a < b else 0)
		0x35: # CMP_GT
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if a > b else 0)
		0x38: # BOOL_AND
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if (a != 0 and b != 0) else 0)
		0x39: # BOOL_OR
			var b := _pop_int()
			var a := _pop_int()
			_data_stack.append(1 if (a != 0 or b != 0) else 0)
		0x3A: # BOOL_NOT
			var a := _pop_int()
			_data_stack.append(1 if a == 0 else 0)
		0x3F: # SCOPE_MARK / 宏参数消费
			var args: Array = _pop_n(a0)
			_handle_scope_mark(a1, args)
		0x7F: # DEBUG_LINE
			var urel := a0 & 0xFFFFFFFF
			current_src_file = str(_strings.get(urel, current_src_file))
			current_line = a1
		0x0F0: # CALL_SCRIPT
			var target_sc := str(_pop_any())
			if _vfs != null and _vfs.has_entry(target_sc):
				_push_call_frame(_ip + 1)
				start_script(target_sc, 0, false)
				return
		0x0F3: # JUMP_SCRIPT
			var arg0 = _pop_any()
			var target_sc := ""
			if typeof(arg0) == TYPE_INT and not _data_stack.is_empty():
				target_sc = str(_pop_any())
			else:
				target_sc = str(arg0)
			if _vfs != null and _vfs.has_entry(target_sc):
				start_script(target_sc, 0, false)
				return
		0x0F6: # CALL/JUMP_PREP（弹出参数个数 argc，保留目标脚本名给紧随其后的 0xF0/0xF3）
			var _argc := _pop_int()
			# 若存在附加参数则保留目标脚本名在栈顶
			if _argc > 0 and _data_stack.size() > _argc:
				var _script_name = _pop_any()
				_pop_n(_argc)
				_data_stack.append(_script_name)
		0x0F4: # EXIT_VM
			wait_state = WaitState.ENDED
			vm_ended.emit()
			return
		0x0F7: # CHECK_ENTRY_LABEL / 默认入口跳转到 0x000c
			var _idx := _pop_int()
			if _offset_to_idx.has(0x000c):
				_ip = int(_offset_to_idx[0x000c])
				return
			_data_stack.append(1)
		0x0F9: # ERROR_DIALOG
			var _msg := str(_pop_any())
		0x91: # STRCAT(sa, sb, dst_ptr)
			var dst := _pop_int()
			var sb := str(_pop_any())
			var sa := str(_pop_any())
			_mem[dst] = sa + sb
		0x98: # ITOA(mode, val, dst_ptr)
			var dst := _pop_int()
			var val := _pop_int()
			var _mode := _pop_int()
			_mem[dst] = str(val)
		0xE0: # SYS_WORK_SET(val, fid)
			var fid := _pop_int()
			var fval := _pop_int()
			_sys_work[fid] = fval
		0xE1: # SYS_WORK_GET(fid)
			var fid := _pop_int()
			_data_stack.append(int(_sys_work.get(fid, 0)))
		0xEB: # SET_LOCAL_SHORT_STRINGS
			_pop_n(2)
		0x128: # SYS_EFFECT_ENABLED
			_data_stack.append(1)
		0x14D: # SYS_SET_FONT(arg0..3)
			_pop_n(4)
		0x160: # SYS_SELECT_CORE(cnt, ptr)
			var _ptr := _pop_int()
			var _cnt := _pop_int()
			_data_stack.append(0)
		0x140: # SYS_TEXT_PRINT
			_mark_pending_line_read()
			var text := normalize_dialogue_text(str(_pop_any()))
			var speaker_arg = _pop_any()
			var _voice_arg = _pop_any()
			var _clear_arg = _pop_any()
			var wait_flag := _pop_int()
			var speaker := ""
			if typeof(speaker_arg) == TYPE_STRING and not str(speaker_arg).is_empty():
				speaker = normalize_speaker(str(speaker_arg))
			last_dialogue_text = text
			last_speaker = speaker
			_pending_read_script = current_script
			_pending_read_line = current_line
			dialogue_printed.emit(text, speaker, wait_flag != 0)
			if wait_flag != 0:
				wait_state = WaitState.CLICK
			else:
				_mark_pending_line_read()
		0x142: # SYS_TEXT_CLEAR_OR_WAIT
			text_cleared.emit()
		_:
			unknown_opcodes[op] = int(unknown_opcodes.get(op, 0)) + 1

	_ip += 1


func _handle_scope_mark(cmd_id: int, args: Array) -> void:
	if (cmd_id == 225 or cmd_id == 229 or cmd_id == 231) and args.size() >= 1:
		# 读取全局流程标志
		var idx := int(args[0])
		_data_stack.append(int(flags.get(idx, 0)))
	elif cmd_id == 228 and args.size() >= 2:
		# 写入全局流程标志
		var idx := int(args[0])
		flags[idx] = int(args[1])
	elif cmd_id == 392 and args.size() >= 2:
		# SetMusicTelop(id, bgm_name, ...)
		music_telop[str(args[1])] = int(args[0])
	elif cmd_id == 319 and args.size() >= 1:
		caption = str(args[0])
	elif cmd_id == 254 and args.size() >= 2:
		current_src_file = str(args[0])
		current_line = int(args[1])


func _is_intercepted_external(fn_name: String) -> bool:
	return fn_name in [
		"_DrawScene", "_DrawSceneByVirtualBG", "_FadeScene", "_DrawBG", "_EnlargeBG",
		"_DrawFilm", "_DrawFilmSx", "_FadeFilm", "_Flash",
		"_DrawBS", "_FadeBS", "_MoveBS", "_ShiftBS", "_OrderBS", "_ClearBS", "clear_bs",
		"_DrawFace", "_FadeFace",
		"_DrawSPR", "_FadeSPR", "_MoveSPR",
		"_Quake", "_QuakeEx", "StartShakingOfWindowSx", "_ScrollBG",
		"_PlayBGM", "_FadeBGM", "_StopBGM", "_ChangeVolumeOfBGM",
		"_PlaySE", "_FadeSE", "_StopSE",
		"_PlayStreamSE", "_FadeStreamSE", "_StopStreamSE", "_ChangeVolumeOfStreamSE",
		"_PlayVoice", "_StopVoice", "_WaitToFinishSE", "_Wait",
		"SoundStopAll", "SetBustshotTime", "AutoSave", "Random",
		"_Font", "_SetLocalShortStrings", "_ExecuteScheduledControl",
		"_PlayMovie", "StartEndroll", "DrawEndroll",
		"SelectTalk", "SelectTopic", "SelectMail", "_SelectEx",
	]


func _handle_builtin_external(fn_name: String) -> void:
	match fn_name:
		"_DrawScene", "_DrawSceneByVirtualBG":
			# 参数栈(9): [bg_name, ...]
			var args := _pop_all_frame_args(9)
			if args.size() >= 1:
				last_bg = str(args[0])
			stage_command.emit("_DrawScene", args)
		"_FadeScene":
			# 参数栈(3): [kind, mode, time_ms]
			var args := _pop_all_frame_args(3)
			stage_command.emit(fn_name, args)
		"_DrawBS":
			# 参数栈(21): [layer_id, body_img, face_img, ..., x(6), y(7), ..., alpha(11), ..., time(18), ...]
			var args := _pop_all_frame_args(21)
			stage_command.emit(fn_name, args)
		"_FadeBS":
			# 参数栈(9): [layer_id, alpha, ...]
			var args := _pop_all_frame_args(9)
			stage_command.emit(fn_name, args)
		"_MoveBS":
			# 参数栈(12): [layer_id, ..., x(4), y(5), ...]
			var args := _pop_all_frame_args(12)
			stage_command.emit(fn_name, args)
		"_ShiftBS", "_MoveSPR":
			var args := _pop_all_frame_args(10)
			stage_command.emit(fn_name, args)
		"_OrderBS", "_Quake":
			var args := _pop_all_frame_args(3)
			stage_command.emit(fn_name, args)
		"_DrawFace":
			var args := _pop_all_frame_args(3)
			last_face_img = ""
			for a in args:
				if typeof(a) == TYPE_STRING and not str(a).is_empty():
					last_face_img = str(a)
					break
			stage_command.emit(fn_name, args)
		"_FadeFace":
			var args := _pop_all_frame_args(2)
			last_face_img = ""
			stage_command.emit(fn_name, args)
		"_DrawSPR":
			var args := _pop_all_frame_args(19)
			stage_command.emit(fn_name, args)
		"_FadeSPR":
			var args := _pop_all_frame_args(9)
			stage_command.emit(fn_name, args)
		"_ClearBS":
			var args := _pop_all_frame_args(1)
			stage_command.emit(fn_name, args)
		"_QuakeEx":
			var args := _pop_all_frame_args(6)
			stage_command.emit(fn_name, args)
		"StartShakingOfWindowSx":
			var args := _pop_all_frame_args(4)
			stage_command.emit(fn_name, args)
		"_ScrollBG":
			var args := _pop_all_frame_args(7)
			stage_command.emit(fn_name, args)
		"_PlayBGM":
			var args := _pop_all_frame_args(6)
			if args.size() >= 2:
				last_bgm = str(args[1])
			audio_command.emit("_PlayBGM", args)
		"_FadeBGM", "_FadeStreamSE":
			var args := _pop_all_frame_args(3)
			audio_command.emit(fn_name, args)
		"_PlaySE":
			var args := _pop_all_frame_args(6)
			audio_command.emit(fn_name, args)
		"_PlayStreamSE":
			var args := _pop_all_frame_args(7)
			audio_command.emit(fn_name, args)
		"_PlayVoice":
			var args := _pop_all_frame_args(4)
			if args.size() >= 1:
				last_voice_entry = str(args[0])
			audio_command.emit(fn_name, args)
		"_FadeSE", "_WaitToFinishSE":
			var args := _pop_all_frame_args(2)
			audio_command.emit(fn_name, args)
		"_StopBGM", "_StopSE", "_StopStreamSE", "_StopVoice":
			var args := _pop_all_frame_args(1)
			audio_command.emit(fn_name, args)
		"_Wait":
			var args := _pop_all_frame_args(2)
			var ms := int(args[0]) if args.size() >= 1 else 0
			if ms > 0:
				wait_timer_sec = float(ms) / 1000.0
				wait_state = WaitState.TIMER
		"_SelectEx":
			# BGI _SelectEx 参数格式:
			# 1) [opt_count, mem_array_ptr, title_or_0]（字符串数组存于 _mem[ptr + i*4]）
			# 2) [opt_count, flag0, text0, ..., title_or_0]（直接字符串入栈兜底）
			var clean_opts: Array = []
			var title_str := ""
			if _data_stack.size() >= 3 and (_data_stack[-3] is int or _data_stack[-3] is float) and (_data_stack[-2] is int or _data_stack[-2] is float):
				var cnt_top := int(_data_stack[-3])
				var ptr_top := int(_data_stack[-2])
				if cnt_top > 0 and cnt_top <= 16 and _mem.has(ptr_top):
					var title_arg = _pop_any()
					var _p = _pop_any()
					var _c = _pop_any()
					if title_arg is String and not str(title_arg).is_empty():
						title_str = str(title_arg)
					for i in range(cnt_top):
						var s_val = _mem.get(ptr_top + i * 4, "")
						if s_val is String and not str(s_val).is_empty():
							clean_opts.append(str(s_val))
			if clean_opts.is_empty():
				var raw_args := _pop_all_frame_args(16)
				for v in raw_args:
					if v is String and not str(v).is_empty():
						clean_opts.append(str(v))
				if clean_opts.size() >= 2:
					title_str = str(clean_opts.pop_back())
			var kind_tag := "_SelectEx" if title_str.is_empty() else ("_SelectEx:" + title_str)
			choice_requested.emit(kind_tag, clean_opts)
			wait_state = WaitState.CHOICE
		"SelectTalk":
			var args := _pop_all_frame_args(6)
			var clean_opts: Array = []
			for v in args:
				if v is String and not str(v).is_empty():
					clean_opts.append(str(v))
			choice_requested.emit(fn_name, clean_opts if not clean_opts.is_empty() else args)
			wait_state = WaitState.CHOICE
		"SelectTopic":
			var args := _pop_all_frame_args(13)
			var clean_opts: Array = []
			for v in args:
				if v is String and not str(v).is_empty():
					clean_opts.append(str(v))
			choice_requested.emit(fn_name, clean_opts if not clean_opts.is_empty() else args)
			wait_state = WaitState.CHOICE
		"SelectMail":
			var args := _pop_all_frame_args(12)
			var clean_opts: Array = []
			for v in args:
				if v is String and not str(v).is_empty():
					clean_opts.append(str(v))
			choice_requested.emit(fn_name, clean_opts if not clean_opts.is_empty() else args)
			wait_state = WaitState.CHOICE
		"Random":
			var args := _pop_all_frame_args(1)
			var n := int(args[0]) if args.size() >= 1 else 1
			var r := randi() % maxi(1, n)
			_retval = r
			flags[0] = r
			_data_stack.append(r)
		"SoundStopAll":
			_pop_all_frame_args(1)
			audio_command.emit("_StopBGM", [0])
			audio_command.emit("_StopSE", [0])
			audio_command.emit("_StopStreamSE", [0])
			audio_command.emit("_StopVoice", [0])
		"clear_bs":
			_pop_all_frame_args(1)
			stage_command.emit("_ClearBS", [0])
		"SetBustshotTime", "AutoSave", "_ExecuteScheduledControl":
			_pop_all_frame_args(1)
		"_DrawFilm", "DrawEndroll":
			_pop_all_frame_args(7)
		"_DrawFilmSx":
			_pop_all_frame_args(4)
		"_FadeFilm":
			_pop_all_frame_args(2)
		"StartEndroll":
			_pop_all_frame_args(5)
		"_DrawBG":
			var args := _pop_all_frame_args(8)
			if args.size() >= 1:
				last_bg = str(args[0])
			stage_command.emit("_DrawBG", args)
		"_EnlargeBG":
			var args := _pop_all_frame_args(10)
			stage_command.emit("_EnlargeBG", args)
		"_Flash":
			var args := _pop_all_frame_args(5)
			stage_command.emit("_Flash", args)
		"_ChangeVolumeOfBGM", "_ChangeVolumeOfStreamSE":
			var args := _pop_all_frame_args(3)
			audio_command.emit(fn_name, args)
		"_PlayMovie":
			var args := _pop_all_frame_args(3)
			stage_command.emit("_PlayMovie", args)
		"_SetLocalShortStrings":
			_pop_all_frame_args(2)
		"_Font":
			_pop_all_frame_args(3)
		_:
			unknown_externals[fn_name] = int(unknown_externals.get(fn_name, 0)) + 1
			_data_stack.append(0)


func _to_i32(v: int) -> int:
	var u := v & 0xFFFFFFFF
	return u - 0x100000000 if (u & 0x80000000) != 0 else u


func _pop_all_frame_args(limit: int) -> Array:
	var n := mini(_data_stack.size(), limit)
	var out: Array = []
	out.resize(n)
	for i in range(n - 1, -1, -1):
		out[i] = _data_stack.pop_back()
	return out


func _pop_n(n: int) -> Array:
	var count := mini(_data_stack.size(), maxi(n, 0))
	var out: Array = []
	out.resize(count)
	for i in range(count - 1, -1, -1):
		out[i] = _data_stack.pop_back()
	return out


func _push_call_frame(ret_ip: int) -> void:
	_call_stack.append({
		"script": current_script,
		"insns": _insns,
		"offset_to_idx": _offset_to_idx,
		"strings": _strings,
		"ip": ret_ip,
		"sp": _sp,
		"exc_stack": _exc_stack.duplicate(),
	})


func _pop_call_frame() -> bool:
	if _call_stack.is_empty():
		return false
	var frame: Dictionary = _call_stack.pop_back()
	current_script = str(frame["script"])
	_insns = frame["insns"]
	_offset_to_idx = frame["offset_to_idx"]
	_strings = frame["strings"]
	_ip = int(frame["ip"])
	_sp = int(frame["sp"])
	_exc_stack = frame["exc_stack"]
	return true


func _pop_int() -> int:
	if _data_stack.is_empty():
		return 0
	var v = _data_stack.pop_back()
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return 1 if not str(v).is_empty() else 0


func _pop_any() -> Variant:
	if _data_stack.is_empty():
		return 0
	return _data_stack.pop_back()


func _read_ascii_cstr(raw: PackedByteArray, pos: int) -> Dictionary:
	var end := pos
	while end < raw.size() and raw[end] != 0:
		end += 1
	return {
		"text": raw.slice(pos, end).get_string_from_ascii(),
		"next": mini(end + 1, raw.size()),
	}


func export_save_state() -> Dictionary:
	return {
		"current_script": current_script,
		"ip": _ip,
		"sp": _sp,
		"flags": flags.duplicate(true),
		"last_dialogue_text": last_dialogue_text,
		"last_speaker": last_speaker,
		"last_bg": last_bg,
		"last_bgm": last_bgm,
		"current_line": current_line,
	}


func import_save_state(state: Dictionary) -> bool:
	var sname := str(state.get("current_script", ""))
	if sname.is_empty():
		return false
	if not start_script(sname, 0, true):
		return false
	_ip = clampi(int(state.get("ip", 0)), 0, maxi(_insns.size() - 1, 0))
	_sp = int(state.get("sp", 0x10000))
	var f: Variant = state.get("flags", {})
	if typeof(f) == TYPE_DICTIONARY:
		flags = f.duplicate(true)
	last_dialogue_text = str(state.get("last_dialogue_text", ""))
	last_speaker = str(state.get("last_speaker", ""))
	last_bg = str(state.get("last_bg", ""))
	last_bgm = str(state.get("last_bgm", ""))
	current_line = int(state.get("current_line", 0))
	wait_state = WaitState.CLICK if not last_dialogue_text.is_empty() else WaitState.NONE
	return true


func normalize_speaker(raw_sp: String) -> String:
	if raw_sp.is_empty():
		return ""
	var sp := raw_sp.replace("庡恖岞乮惄乯", player_family_name)
	sp = sp.replace("庡恖岞乮柤乯", player_given_name)
	sp = sp.replace("主人公（姓）", player_family_name)
	sp = sp.replace("主人公（名）", player_given_name)
	sp = sp.replace("⒗", "・")
	if SPEAKER_JP_MAP.has(sp):
		return str(SPEAKER_JP_MAP[sp])
	if sp.contains("・"):
		var parts := sp.split("・")
		for i in range(parts.size()):
			var p := parts[i]
			if SPEAKER_JP_MAP.has(p):
				parts[i] = str(SPEAKER_JP_MAP[p])
		return "・".join(parts)
	return sp


func normalize_dialogue_text(raw_t: String) -> String:
	if raw_t.is_empty():
		return ""
	var t := raw_t.replace("庡恖岞乮惄乯", player_family_name)
	t = t.replace("庡恖岞乮柤乯", player_given_name)
	t = t.replace("主人公（姓）", player_family_name)
	t = t.replace("主人公（名）", player_given_name)
	t = t.replace("⒗", "・")
	if t.ends_with("<"):
		t = t.substr(0, t.length() - 1)
	return t
