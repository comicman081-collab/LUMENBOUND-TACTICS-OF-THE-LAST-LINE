class_name VfxPool
extends Node

var free_nodes: Array[Node] = []
func acquire() -> Node:
	if not free_nodes.is_empty(): return free_nodes.pop_back()
	return Node2D.new()
func release(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	free_nodes.append(node)

