extends RefCounted
# Pure helpers for gaze experiments, kept free of scene state so they can be unit tested.

static func angle_deg(a: Vector3, b: Vector3) -> float:
	if a.length() < 0.000001 or b.length() < 0.000001:
		return 0.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))

static func mean_direction(directions: Array) -> Vector3:
	var sum := Vector3.ZERO
	for direction in directions:
		sum += (direction as Vector3).normalized()
	return sum.normalized() if sum.length() > 0.000001 else Vector3.ZERO

# RMS angular distance (degrees) of the samples from their own mean direction.
static func dispersion_deg(directions: Array) -> float:
	if directions.size() < 2:
		return 0.0
	var mean := mean_direction(directions)
	var total := 0.0
	for direction in directions:
		var angle := angle_deg(direction, mean)
		total += angle * angle
	return sqrt(total / directions.size())

# Yaw and pitch (degrees) of a direction in a frame where -Z is straight ahead and +Y is up.
static func yaw_pitch_deg(direction: Vector3) -> Vector2:
	var d := direction.normalized()
	return Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))

static func from_yaw_pitch_deg(angles: Vector2) -> Vector3:
	var yaw := deg_to_rad(angles.x)
	var pitch := deg_to_rad(angles.y)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

# Removes a calibration offset (yaw/pitch bias in degrees) from a head-local gaze direction.
static func apply_offset(head_local_dir: Vector3, offset: Vector2) -> Vector3:
	return from_yaw_pitch_deg(yaw_pitch_deg(head_local_dir) - offset)

static func summarize(errors: Array) -> Dictionary:
	if errors.is_empty():
		return {"count": 0, "mean": 0.0, "rms": 0.0, "max": 0.0}
	var total := 0.0
	var squares := 0.0
	var worst := 0.0
	for error in errors:
		total += error
		squares += error * error
		worst = maxf(worst, error)
	return {"count": errors.size(), "mean": total / errors.size(), "rms": sqrt(squares / errors.size()), "max": worst}
