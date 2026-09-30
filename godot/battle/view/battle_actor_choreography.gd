extends RefCounted

## Draw-only role choreography, using the existing immutable character art.
## No simulation position, target, clock, hit event or costume is changed.
const MELEE_ROLES := ["GUARDIAN", "VANGUARD", "MELEE_RUSH", "DEFENDER"]
const FIREARM_ROLES := ["ASSAULT", "ARTILLERY", "RANGED", "AREA"]
const SUPPORT_ROLES := ["SPECIALIST", "MEDIC", "HEALER", "BUFFER", "DEBUFFER", "SUMMONER"]

static func adapt_pose(pose: Dictionary, team: String, role: String, action: String, progress: float) -> Dictionary:
	var forward := 1.0 if team == "PLAYER" else -1.0
	if role in FIREARM_ROLES and action in ["basic_attack", "normal_skill", "ultimate"]:
		# A firearm braces, settles its aim and kicks backwards at release.  Keeping
		# the feet in the firing lane prevents rifle/artillery characters from using
		# the generic airborne sword lunge while still giving stronger skills a
		# visibly heavier recoil language.
		var power := .72 if action == "basic_attack" else (1.0 if action == "normal_skill" else 1.28)
		var release_at := .42 if action == "basic_attack" else (.48 if action == "normal_skill" else .54)
		var aim := sin(smoothstep(0.0, release_at, progress) * PI * .5)
		var recoil := sin(clampf((progress - release_at) / .26, 0.0, 1.0) * PI)
		pose.offset = Vector2(-forward * (2.5 * aim + 13.0 * recoil * power), 2.2 * recoil * power)
		pose.rotation = -forward * (.018 * aim + .042 * recoil * power)
		pose.scale = Vector2(1.0 + recoil * .018 * power, 1.0 - recoil * .012 * power)
	elif role in SUPPORT_ROLES and action in ["normal_skill", "ultimate"]:
		var channel := sin(progress * PI)
		pose.offset = Vector2(-forward * 6.0 * channel, -5.0 * channel)
		pose.rotation = -forward * .025 * channel
		pose.scale = Vector2(1.0 + .012 * channel, 1.0 + .009 * channel)
	elif role in ["GUARDIAN", "DEFENDER"] and action in ["basic_attack", "normal_skill", "ultimate"]:
		# Shield users transfer weight without the large airborne sword arc.
		pose.offset = (pose.offset as Vector2) * Vector2(.70, .28)
		pose.rotation = float(pose.rotation) * .45
		pose.scale = Vector2.ONE.lerp(pose.scale, .38)
	return pose


static func add_hit_reaction(pose: Dictionary, team: String, remaining: float, duration := .14, power := 1.0) -> Dictionary:
	## Incoming damage remains readable even while the victim's attack animation
	## is protected from interruption.  This additive layer is composed before
	## foot registration, so the stronger recoil never makes a body hover.
	if remaining <= 0.0:
		return pose
	var forward := 1.0 if team == "PLAYER" else -1.0
	var progress := 1.0 - clampf(remaining / maxf(.01, duration), 0.0, 1.0)
	var kick := sin(progress * PI)
	if not is_equal_approx(power, 1.0):
		# A damage-scaled hit slides back quickly and returns slowly.
		kick = sin(pow(progress, .62) * PI)
	var slide := clampf(power, .4, 2.6)
	pose.offset = (pose.get("offset", Vector2.ZERO) as Vector2) + Vector2(-forward * 21.0 * slide * kick, 2.4 * minf(slide, 1.6) * kick)
	pose.rotation = float(pose.get("rotation", 0.0)) - forward * .085 * minf(slide, 1.5) * kick
	var base_scale: Vector2 = pose.get("scale", Vector2.ONE)
	pose.scale = base_scale * Vector2(1.0 - .055 * minf(slide, 1.5) * kick, 1.0 + .032 * minf(slide, 1.5) * kick)
	return pose


static func afterimage_samples(role: String, action: String, team: String, progress: float) -> Array:
	## Two bounded draw-only ghosts bridge sparse atlas key poses during the actual
	## strike window.  Only melee actions receive them: ranged actors communicate
	## velocity through the projectile/trail and should keep a clean firing line.
	if role not in MELEE_ROLES or action not in ["basic_attack", "normal_skill", "ultimate"]:
		return []
	var enter := smoothstep(.30, .43, progress)
	var exit := 1.0 - smoothstep(.63, .78, progress)
	var visibility := enter * exit
	if visibility <= .01:
		return []
	var forward := 1.0 if team == "PLAYER" else -1.0
	var strength := 1.0 if action == "basic_attack" else (1.20 if action == "normal_skill" else 1.42)
	return [
		{"offset": Vector2(-forward * 15.0 * strength, 1.5), "rotation": -forward * .018, "alpha": .13 * visibility},
		{"offset": Vector2(-forward * 29.0 * strength, 3.0), "rotation": -forward * .032, "alpha": .065 * visibility},
	]


static func action_anchor(role: String, team: String, action: String, progress: float) -> Vector2:
	## Screen-space hand/weapon proxy relative to the planted foot. The body pose
	## transform is applied by BattleView, keeping the launch flash attached while
	## the actor leans, recoils or advances toward a target.
	var forward := 1.0 if team == "PLAYER" else -1.0
	var local := Vector2(46.0, -78.0)
	if role in ["GUARDIAN", "DEFENDER"]:
		local = Vector2(36.0, -63.0)
	elif role in FIREARM_ROLES:
		local = Vector2(54.0, -80.0)
	elif role in SUPPORT_ROLES:
		local = Vector2(31.0, -72.0)
	elif role in ["VANGUARD", "MELEE_RUSH"]:
		local = Vector2(48.0, -67.0)
	var release := sin(clampf((progress - .32) / .38, 0.0, 1.0) * PI)
	return Vector2(forward * (local.x + release * 4.0), local.y - release * 2.0)

static func step_offset(role: String, action: String, elapsed: float, duration: float, target_delta: Vector2) -> Vector2:
	if role not in MELEE_ROLES or action not in ["basic_attack", "normal_skill", "ultimate"]:
		return Vector2.ZERO
	var progress := clampf(elapsed / maxf(.01, duration), 0.0, 1.0)
	var approach := smoothstep(.10, .40, progress)
	var recovery := 1.0 - smoothstep(.58, 1.0, progress)
	var distance := target_delta.length()
	if distance <= 180.0: return Vector2.ZERO
	var maximum := 54.0 if role in ["GUARDIAN", "DEFENDER"] else (116.0 if action == "ultimate" else 92.0)
	return target_delta / distance * minf(maximum, distance - 180.0) * approach * recovery
