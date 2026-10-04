class_name PowerNetwork
extends Node

## Manages power generators and consumers in a base.

var generators: Array[Node] = []
var consumers: Array[Node] = []

var total_generation: float = 0.0
var total_consumption: float = 0.0

func _process(_delta: float) -> void:
	_update_network()

func register_generator(gen: Node) -> void:
	if not generators.has(gen):
		generators.append(gen)

func unregister_generator(gen: Node) -> void:
	generators.erase(gen)

func register_consumer(con: Node) -> void:
	if not consumers.has(con):
		consumers.append(con)

func unregister_consumer(con: Node) -> void:
	consumers.erase(con)

func _update_network() -> void:
	total_generation = 0.0
	for gen in generators:
		if gen.has_method("get_generation_rate"):
			total_generation += gen.get_generation_rate()
			
	total_consumption = 0.0
	for con in consumers:
		if con.has_method("get_consumption_rate"):
			total_consumption += con.get_consumption_rate()
			
	var power_available = total_generation >= total_consumption
	
	for con in consumers:
		if con.has_method("set_powered"):
			con.set_powered(power_available)
