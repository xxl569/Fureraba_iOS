class_name MobileGestureHelper
extends Node

## iOS 移动端触控手势与防误触控制器。
## 特性：
## 1. 过滤 `InputEventMouseButton` 中的 `DEVICE_ID_EMULATION` 模拟鼠标事件，防止触屏+鼠标双发跳句；
## 2. Skip / Auto 激活时，首次轻触仅中止自动/快进并消费事件，不跳过当前对白；
## 3. 双指轻触隐藏/显示对白框，三指轻触快捷切换 F12 透视模式，右滑打开历史 Backlog。

signal tap_advance()
signal two_finger_toggle_ui()
signal three_finger_toggle_nude()
signal swipe_open_log()
signal stop_auto_or_skip()

const DEVICE_ID_EMULATION := -1

var is_auto_or_skip_active: bool = false
var block_advance: bool = false

var _touches: Dictionary = {} # finger_idx -> Vector2
var _touch_start_pos: Vector2 = Vector2.ZERO
var _max_fingers_in_gesture: int = 0
var _gesture_moved: bool = false


func handle_input_event(event: InputEvent) -> bool:
	## 处理输入事件；返回 true 表示事件已被消费，不应再穿透推进。
	if event is InputEventMouseButton:
		if event.device == DEVICE_ID_EMULATION:
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			return _handle_single_tap()
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if block_advance:
				return false
			two_finger_toggle_ui.emit()
			return true
		return false

	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			_touches[idx] = event.position
			_max_fingers_in_gesture = maxi(_max_fingers_in_gesture, _touches.size())
			if _touches.size() == 1:
				_touch_start_pos = event.position
				_gesture_moved = false
		else:
			var start_pos := _touch_start_pos
			var end_pos: Vector2 = event.position
			_touches.erase(idx)
			if _touches.is_empty():
				var fingers := _max_fingers_in_gesture
				var moved := _gesture_moved
				_max_fingers_in_gesture = 0
				_gesture_moved = false
				if fingers >= 3:
					three_finger_toggle_nude.emit()
					return true
				if fingers == 2:
					two_finger_toggle_ui.emit()
					return true
				if fingers == 1:
					var dx := end_pos.x - start_pos.x
					if moved and dx > 90.0:
						swipe_open_log.emit()
						return true
					if not moved:
						return _handle_single_tap()
		return true

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1 and event.position.distance_to(_touch_start_pos) > 36.0:
			_gesture_moved = true
		return false

	return false


func _handle_single_tap() -> bool:
	if block_advance:
		return false
	if is_auto_or_skip_active:
		stop_auto_or_skip.emit()
		return true # 消费本次点击，防止顺带跳过当前对白
	tap_advance.emit()
	return true
