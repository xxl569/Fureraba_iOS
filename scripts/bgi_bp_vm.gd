class_name BgiBpVm
extends RefCounted

## BGI `._bp` 字节码模块虚拟机与 `BGI.gdb` 已读状态管理器。
## 负责加载 `environ._bp`、`nudeprcs._bp` 等系统字节码模块，
## 并桥接 F12 透视/无码差分开关（`0x9056` / `0x9058`）及 `BURIKO GDB 3.00` 已读位图。

const BP_IMM_BYTES := {
	0x00: 1, 0x08: 1, 0x09: 1, 0x0A: 1, 0x15: 1, 0x19: 1,
	0x01: 2, 0x04: 2, 0x05: 2, 0x06: 2, 0x0C: 2,
	0x02: 4,
}

var _vfs: BgiVfs
var _modules: Dictionary = {} # name_lower -> Dictionary
var _nude_flag: bool = false
var _global_flags: Dictionary = {} # int -> int
var _read_bits: Dictionary = {} # script_lower -> PackedByteArray
var _gdb_entries: Array[String] = []


func _init(vfs: BgiVfs = null) -> void:
	_vfs = vfs


func set_vfs(vfs: BgiVfs) -> void:
	_vfs = vfs


func set_nude_mode(enabled: bool) -> void:
	_nude_flag = enabled
	_global_flags[9056] = 1 if enabled else 0


func is_nude_mode() -> bool:
	return _nude_flag


func toggle_nude_mode() -> bool:
	set_nude_mode(not _nude_flag)
	return _nude_flag


func resolve_nude_image_name(base_name: String) -> String:
	## 当透视/全裸差分开关开启且 VFS 中存在对应 `_h` / `h` 资源时，返回差分资源名。
	if not _nude_flag or _vfs == null:
		return base_name
	var candidates := [base_name + "h", base_name + "_h"]
	for cand in candidates:
		if _vfs.has_entry(cand):
			return cand
	return base_name


func set_global_flag(idx: int, val: int) -> void:
	_global_flags[idx] = val


func get_global_flag(idx: int, default_val: int = 0) -> int:
	return int(_global_flags.get(idx, default_val))


func load_bp_module(name: String) -> Dictionary:
	var key := name.to_lower()
	if _modules.has(key):
		return _modules[key]
	if _vfs == null or not _vfs.has_entry(name):
		return {}
	var raw := _vfs.extract_raw(name)
	if raw.size() < 16:
		return {}
	var hdr_size := raw.decode_u32(0)
	var payload_size := raw.decode_u32(4)
	if hdr_size < 16 or hdr_size + payload_size > raw.size():
		return {}
	var payload := raw.slice(hdr_size, hdr_size + payload_size)
	var parsed := _disassemble_bp(payload)
	parsed["name"] = name
	parsed["header_size"] = hdr_size
	parsed["payload"] = payload
	_modules[key] = parsed
	return parsed


func _disassemble_bp(payload: PackedByteArray) -> Dictionary:
	var pc := 0
	var min_str_off := payload.size()
	var insns: Array[Dictionary] = []
	var strings: Dictionary = {}
	var syscalls: Array[int] = []

	while pc < min_str_off:
		if (min_str_off - pc) <= 16:
			var all_zero := true
			for i in range(pc, min_str_off):
				if payload[i] != 0:
					all_zero = false
					break
			if all_zero:
				break
		var op := payload[pc]
		if BP_IMM_BYTES.has(op):
			var n: int = int(BP_IMM_BYTES[op])
			if pc + 1 + n > payload.size():
				break
			var signed := op in [0x01, 0x02, 0x04, 0x05, 0x06, 0x0C]
			var val := _read_int_le(payload, pc + 1, n, signed)
			if op == 0x05:
				var target := pc + val
				if target >= 0 and target < payload.size():
					if target > pc and target < min_str_off:
						min_str_off = target
					if not strings.has(target):
						strings[target] = _read_cstr_decoded(payload, target)
			insns.append({"offset": pc, "op": op, "arg": val, "size": 1 + n})
			pc += 1 + n
		elif op >= 0x80:
			if pc + 2 > payload.size():
				break
			var sid := (op << 8) | payload[pc + 1]
			syscalls.append(sid)
			insns.append({"offset": pc, "op": op, "syscall_id": sid, "size": 2})
			pc += 2
		else:
			insns.append({"offset": pc, "op": op, "size": 1})
			pc += 1

	return {
		"code_end": pc,
		"instructions": insns,
		"strings": strings,
		"syscalls": syscalls,
	}


func execute_bp(name: String, max_steps: int = 2000) -> Dictionary:
	## 轻量执行 `._bp` 模块（处理压栈、字符串、跳转与 `0x8000+` 系统调用，含 F12 透视切换）。
	var mod := load_bp_module(name)
	if mod.is_empty():
		return {"ok": false, "error": "missing_module"}
	var insns: Array = mod.get("instructions", [])
	var strings: Dictionary = mod.get("strings", {})
	var offset_to_idx: Dictionary = {}
	for i in range(insns.size()):
		offset_to_idx[int(insns[i]["offset"])] = i

	var stack: Array = []
	var mem: Dictionary = {}
	var call_stack: Array[int] = []
	var ip := 0
	var steps := 0
	var executed_syscalls: Array[int] = []

	while ip >= 0 and ip < insns.size() and steps < max_steps:
		steps += 1
		var ins: Dictionary = insns[ip]
		var op: int = int(ins["op"])
		if op == 0x00 or op == 0x01 or op == 0x02:
			stack.append(int(ins.get("arg", 0)))
		elif op == 0x05:
			var target: int = int(ins["offset"]) + int(ins.get("arg", 0))
			stack.append(str(strings.get(target, "")))
		elif op == 0x06:
			var jtarget: int = int(ins["offset"]) + int(ins.get("arg", 0))
			if offset_to_idx.has(jtarget):
				ip = int(offset_to_idx[jtarget])
				continue
		elif op == 0x04 or op == 0x0C:
			# 条件跳转：若栈顶为 0 则跳转
			var cond := _pop_int(stack)
			if cond == 0:
				var ctarget: int = int(ins["offset"]) + int(ins.get("arg", 0))
				if offset_to_idx.has(ctarget):
					ip = int(offset_to_idx[ctarget])
					continue
		elif op == 0x08 or op == 0x09 or op == 0x0A:
			var idx: int = int(ins.get("arg", 0))
			if op == 0x08:
				stack.append(mem.get(idx, 0))
			elif op == 0x09:
				mem[idx] = _pop_any(stack, 0)
			else:
				if not stack.is_empty():
					stack.pop_back()
		elif op == 0x17:
			if call_stack.is_empty():
				break
			ip = call_stack.pop_back()
			continue
		elif op >= 0x80:
			var sid: int = int(ins.get("syscall_id", 0))
			executed_syscalls.append(sid)
			if sid == 0x9056 or sid == 0x9058:
				# F12 透视/差分模式切换调用
				var arg_val := _pop_int(stack)
				if sid == 0x9056:
					set_nude_mode(arg_val != 0 or not _nude_flag)
				stack.append(1 if _nude_flag else 0)
			else:
				stack.append(0)
		ip += 1

	return {
		"ok": true,
		"steps": steps,
		"syscalls": executed_syscalls,
		"nude_mode": _nude_flag,
	}


func load_gdb_from_vfs(gdb_name: String = "BGI.gdb") -> int:
	## 解析游戏目录下的 `BGI.gdb` (`SDC FORMAT 1.00` + `BURIKO GDB 3.00`) 已读位图。
	var raw := PackedByteArray()
	if _vfs != null and _vfs.has_entry(gdb_name):
		raw = _vfs.extract_raw(gdb_name)
	elif _vfs != null and not _vfs.mounted_game_dir.is_empty():
		var phys := _vfs.mounted_game_dir.path_join(gdb_name)
		if FileAccess.file_exists(phys):
			raw = FileAccess.get_file_as_bytes(phys)
	if raw.size() < 32:
		return 0

	if raw.slice(0, 15).get_string_from_ascii() == "SDC FORMAT 1.00":
		raw = _decode_sdc(raw)
	if raw.size() < 0x100428:
		return 0
	if raw.slice(0, 15).get_string_from_ascii() != "BURIKO GDB 3.00":
		return 0

	var res_count := raw.decode_u32(0x100424)
	var p := 0x100428
	for _i in range(res_count):
		var nul := raw.find(0, p)
		if nul < 0:
			return 0
		p = nul + 1
	if p + 4 > raw.size():
		return 0

	var script_count := raw.decode_u32(p)
	p += 4
	_gdb_entries.clear()
	for _i in range(script_count):
		var nul := raw.find(0, p)
		if nul < 0 or nul + 5 > raw.size():
			break
		var sname := raw.slice(p, nul).get_string_from_ascii().to_lower()
		var bit_count := raw.decode_u32(nul + 1)
		var bitmap_bytes := (bit_count + 7) >> 3
		p = nul + 5 + bitmap_bytes
		if p > raw.size():
			break
		_gdb_entries.append(sname)
		if not _read_bits.has(sname):
			var init_bits := PackedByteArray()
			init_bits.resize(bitmap_bytes) # 默认未读 (0)，不直接使用出厂全 0xFF 位图
			_read_bits[sname] = init_bits
	return _gdb_entries.size()


func _decode_sdc(raw: PackedByteArray) -> PackedByteArray:
	var key := raw.decode_u32(16)
	var comp_size := raw.decode_u32(20)
	var uncomp_size := raw.decode_u32(24)
	if 32 + comp_size > raw.size() or uncomp_size == 0:
		return PackedByteArray()

	var dec := PackedByteArray()
	dec.resize(comp_size)
	for i in range(comp_size):
		var v0 := 20021 * (key & 0xFFFF)
		var v1 := 20021 * (key >> 16) + 346 * (key & 0xFFFF) + (v0 >> 16)
		key = (((v1 & 0xFFFF) << 16) + (v0 & 0xFFFF) + 1) & 0xFFFFFFFF
		var kb := v1 & 0xFF
		dec[i] = (raw[32 + i] - kb) & 0xFF

	var out := PackedByteArray()
	out.resize(uncomp_size)
	var src := 0
	var dst := 0
	while src < comp_size and dst < uncomp_size:
		var b0 := dec[src]
		src += 1
		if b0 < 0x80:
			var lit_len := b0 + 1
			for _j in range(lit_len):
				if src >= comp_size or dst >= uncomp_size:
					break
				out[dst] = dec[src]
				dst += 1
				src += 1
		else:
			if src >= comp_size:
				break
			var b1 := dec[src]
			src += 1
			var length := ((b0 >> 3) & 0x0F) + 2
			var dist := (((b0 & 0x07) << 8) | b1) + 2
			var start := dst - dist
			for j in range(length):
				if dst >= uncomp_size:
					break
				out[dst] = out[start + j] if start + j >= 0 else 0
				dst += 1
	return out


func mark_line_read(script_name: String, line_no: int) -> void:
	if line_no < 0:
		return
	var key := script_name.to_lower()
	var bits: PackedByteArray = _read_bits.get(key, PackedByteArray())
	var byte_idx := line_no >> 3
	if bits.size() <= byte_idx:
		bits.resize(byte_idx + 64)
	bits[byte_idx] = bits[byte_idx] | (1 << (line_no & 7))
	_read_bits[key] = bits


func is_line_read(script_name: String, line_no: int) -> bool:
	if line_no < 0:
		return false
	var key := script_name.to_lower()
	if not _read_bits.has(key):
		return false
	var bits: PackedByteArray = _read_bits[key]
	var byte_idx := line_no >> 3
	if byte_idx >= bits.size():
		return false
	return (bits[byte_idx] & (1 << (line_no & 7))) != 0


func export_read_state() -> Dictionary:
	var out: Dictionary = {}
	for k in _read_bits.keys():
		var arr: PackedByteArray = _read_bits[k]
		if arr.size() > 0:
			out[k] = Marshalls.raw_to_base64(arr)
	return out


func import_read_state(data: Dictionary) -> void:
	for k in data.keys():
		var b64 := str(data[k])
		_read_bits[str(k).to_lower()] = Marshalls.base64_to_raw(b64)


func _read_int_le(buf: PackedByteArray, pos: int, n: int, signed: bool) -> int:
	var val := 0
	for i in range(n):
		val |= int(buf[pos + i]) << (8 * i)
	if signed:
		var sign_bit := 1 << (8 * n - 1)
		if (val & sign_bit) != 0:
			val -= (1 << (8 * n))
	return val


func _read_cstr_decoded(buf: PackedByteArray, pos: int) -> String:
	var end := pos
	while end < buf.size() and buf[end] != 0:
		end += 1
	return GbkCodec.decode_bytes(buf.slice(pos, end), true)


func _pop_int(stack: Array) -> int:
	if stack.is_empty():
		return 0
	var v = stack.pop_back()
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return 1 if not str(v).is_empty() else 0


func _pop_any(stack: Array, fallback = 0):
	if stack.is_empty():
		return fallback
	return stack.pop_back()
