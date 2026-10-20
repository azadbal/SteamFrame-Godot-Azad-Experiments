extends Node

signal button_toggled(warm: bool)
signal grabbed(hand: int)

var cubes: Array = []
var held: Array = [null, null]
var squeezed := [false, false]
var focused := false
var warm := false
var touch_latched := false
var button_position := Vector3.ZERO
var touching := false
# Optional (hand: int, cube) -> bool; when set, a hand can only grab objects it touches.
# Without it (tests, desktop preview) the nearest object within GRAB_RADIUS of the pose is taken.
var reach_test: Callable
const GRAB_RADIUS := 0.16

func set_focused(value: bool) -> void:
	focused = value
	if not value:
		touch_latched = true
		for hand in range(2):
			if held[hand] != null:
				held[hand].release(true)
				held[hand] = null
			# Require a fresh squeeze after focus returns.
			squeezed[hand] = true

func update_hand(hand: int, tracked: bool, pose: Transform3D, grip: float, delta: float) -> void:
	if not focused or not tracked:
		if held[hand] != null:
			held[hand].release(true)
			held[hand] = null
			squeezed[hand] = true
		return
	if grip < 0.25:
		if held[hand] != null:
			held[hand].move_held(pose, delta)
			held[hand].release()
			held[hand] = null
		squeezed[hand] = false
	elif grip > 0.65 and not squeezed[hand]:
		squeezed[hand] = true
		var closest = null
		var distance := INF if reach_test.is_valid() else GRAB_RADIUS
		for cube in cubes:
			var candidate: float = cube.global_position.distance_to(pose.origin)
			if reach_test.is_valid() and not reach_test.call(hand, cube):
				continue
			if cube.held_by == -1 and candidate < distance:
				closest = cube
				distance = candidate
		if closest != null and closest.begin_grab(hand, pose):
			held[hand] = closest
			grabbed.emit(hand)
	if held[hand] != null:
		held[hand].move_held(pose, delta)

func update_touch(hand_positions: Array) -> void:
	if not focused:
		return
	touching = false
	for position in hand_positions:
		# A palm-sized contact volume around the actual button cap.
		var offset: Vector3 = position - button_position
		if absf(offset.x) < 0.10 and absf(offset.y) < 0.075 and absf(offset.z) < 0.10:
			touching = true
	if touching and not touch_latched:
		warm = not warm
		button_toggled.emit(warm)
	touch_latched = touching
