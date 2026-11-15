class_name GbkCodec
extends RefCounted
## 静态查表 GBK / CP932 混合编码解码器（支持 BGI 脚本与系统模块的汉化/日文混合字符串）。

const TABLE_GBK_PATH := "res://assets/tables/gbk_table.bin"
const TABLE_CP932_PATH := "res://assets/tables/cp932_table.bin"

static var _gbk_map: PackedInt32Array
static var _cp932_map: PackedInt32Array
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_gbk_map = _load_table(TABLE_GBK_PATH)
	_cp932_map = _load_table(TABLE_CP932_PATH)
	_loaded = true


static func _load_table(path: String) -> PackedInt32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GbkCodec: 无法打开码表文件: " + path)
		return PackedInt32Array()
	var bytes := f.get_buffer(f.get_length())
	return bytes.to_int32_array()


static func decode_bytes(raw: PackedByteArray, prefer_gbk: bool = true) -> String:
	ensure_loaded()
	if raw.is_empty():
		return ""
	# 纯 ASCII 快速通道
	var has_high := false
	for b in raw:
		if b >= 0x80:
			has_high = true
			break
	if not has_high:
		return raw.get_string_from_ascii()

	var gbk_score := _score_table(raw, _gbk_map, true)
	var cp932_score := _score_table(raw, _cp932_map, false)

	var use_gbk := prefer_gbk
	if cp932_score > gbk_score + 2:
		use_gbk = false
	elif gbk_score > cp932_score:
		use_gbk = true

	var table := _gbk_map if use_gbk else _cp932_map
	return _decode_with_table(raw, table, not use_gbk)


static func _score_table(raw: PackedByteArray, table: PackedInt32Array, is_gbk: bool) -> int:
	if table.is_empty():
		return -9999
	var n := raw.size()
	var i := 0
	var score := 0
	while i < n:
		var b0 := raw[i]
		if b0 < 0x80:
			i += 1
			continue
		if not is_gbk and b0 >= 0xA1 and b0 <= 0xDF:
			# CP932 半角片假名
			score += 1
			i += 1
			continue
		if i + 1 >= n:
			score -= 10
			break
		var b1 := raw[i + 1]
		if b0 >= 0x81 and b0 <= 0xFE and b1 >= 0x40 and b1 <= 0xFF and b1 != 0x7F:
			var idx := (b0 - 0x81) * 192 + (b1 - 0x40)
			var cp := table[idx] if idx < table.size() else 0
			if cp > 0:
				score += 2
				# 简体中文常用区 (GB2312 0xB0..0xF7, 0xA1..0xFE) 加权
				if is_gbk and b0 >= 0xB0 and b0 <= 0xF7 and b1 >= 0xA1 and b1 <= 0xFE:
					score += 2
				# 日文平假名/片假名 (0x829F..0x8396) 加权
				elif (not is_gbk) and ((b0 == 0x82 and b1 >= 0x9F) or b0 == 0x83):
					score += 3
				i += 2
				continue
		score -= 10
		i += 1
	return score


static func _decode_with_table(raw: PackedByteArray, table: PackedInt32Array, allow_halfwidth_kana: bool) -> String:
	var n := raw.size()
	var i := 0
	var out := ""
	while i < n:
		var b0 := raw[i]
		if b0 < 0x80:
			out += String.chr(b0)
			i += 1
			continue
		if allow_halfwidth_kana and b0 >= 0xA1 and b0 <= 0xDF:
			out += String.chr(0xFF61 + (b0 - 0xA1))
			i += 1
			continue
		if i + 1 < n and b0 >= 0x81 and b0 <= 0xFE:
			var b1 := raw[i + 1]
			if b1 >= 0x40 and b1 <= 0xFF and b1 != 0x7F:
				var idx := (b0 - 0x81) * 192 + (b1 - 0x40)
				if idx < table.size() and table[idx] > 0:
					out += String.chr(table[idx])
					i += 2
					continue
		out += "?"
		i += 1
	return out
