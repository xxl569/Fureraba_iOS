class_name BgiCache
extends RefCounted

## 字节级 + 条目数双维度 LRU 纹理缓存。
## 用于控制 iOS 端（含 4GB RAM 设备）显存/内存水位，防止大图（最大 2048x1152 / 1280x11362）堆积 OOM。

var max_bytes: int = 96 * 1024 * 1024 # 默认 96 MiB
var max_items: int = 128

var _entries: Dictionary = {} # key -> {value: Variant, bytes: int}
var _lru_order: Array[String] = [] # 最近访问在末尾
var current_bytes: int = 0
var eviction_count: int = 0


func _init(p_max_bytes: int = 96 * 1024 * 1024, p_max_items: int = 128) -> void:
	max_bytes = maxi(p_max_bytes, 1024 * 1024)
	max_items = maxi(p_max_items, 4)


func has_key(key: String) -> bool:
	return _entries.has(key.to_lower())


func get_item(key: String) -> Variant:
	var k := key.to_lower()
	if not _entries.has(k):
		return null
	_touch(k)
	return _entries[k]["value"]


func put_item(key: String, value: Variant, byte_size: int) -> void:
	var k := key.to_lower()
	var sz := maxi(byte_size, 0)
	if _entries.has(k):
		current_bytes -= int(_entries[k]["bytes"])
		_entries[k] = {"value": value, "bytes": sz}
		current_bytes += sz
		_touch(k)
	else:
		_entries[k] = {"value": value, "bytes": sz}
		current_bytes += sz
		_lru_order.append(k)
	_evict_if_needed()


func remove_item(key: String) -> void:
	var k := key.to_lower()
	if not _entries.has(k):
		return
	current_bytes -= int(_entries[k]["bytes"])
	_entries.erase(k)
	_lru_order.erase(k)


func clear() -> void:
	_entries.clear()
	_lru_order.clear()
	current_bytes = 0


func on_memory_warning() -> void:
	## 收到 iOS `NOTIFICATION_OS_MEMORY_WARNING` 时强制淘汰至上限的 40%。
	var target := int(float(max_bytes) * 0.4)
	while (current_bytes > target or _lru_order.size() > max_items / 2) and not _lru_order.is_empty():
		_evict_oldest()


func get_item_count() -> int:
	return _entries.size()


func _touch(k: String) -> void:
	var idx := _lru_order.find(k)
	if idx >= 0 and idx != _lru_order.size() - 1:
		_lru_order.remove_at(idx)
		_lru_order.append(k)


func _evict_if_needed() -> void:
	while (current_bytes > max_bytes or _lru_order.size() > max_items) and _lru_order.size() > 1:
		_evict_oldest()


func _evict_oldest() -> void:
	if _lru_order.is_empty():
		return
	var oldest: String = _lru_order[0]
	_lru_order.remove_at(0)
	if _entries.has(oldest):
		current_bytes -= int(_entries[oldest]["bytes"])
		_entries.erase(oldest)
		eviction_count += 1
