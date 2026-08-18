class_name MapTransitionController
extends RefCounted

const MIN_DURATION := 0.18
const FULL_DURATION := 0.62

static func duration(reduced_motion: bool) -> float:
	return MIN_DURATION if reduced_motion else FULL_DURATION
