class_name InventoryService
extends RefCounted

static func has_items(cost: Dictionary) -> bool:
	return AppState.can_pay(cost)

static func consume(cost: Dictionary) -> GameResult:
	return GameResult.success() if AppState.pay(cost) else GameResult.failure("INSUFFICIENT_MATERIALS")

static func grant(items: Dictionary) -> void:
	for item_id in items:
		AppState.add_item(item_id, int(items[item_id]))

