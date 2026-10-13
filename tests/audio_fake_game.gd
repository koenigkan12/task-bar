# Game falso só para os testes de áudio: tem os sinais do contrato (4.3) e instances()/is_night().
extends Node

signal item_placed(instance_id: int)
signal item_finished(instance_id: int, item_id: String)
signal item_removed(instance_id: int)
signal room_dug(room: int)
signal antenna_changed(level: int)
signal radio_line(line: Dictionary)
signal visit_happened(info: Dictionary)
signal plot_harvested(plot_id: int)
signal welcome_back(summary: Dictionary)
signal arrival_started()
signal game_loaded()
signal new_game_started()

var data: Array[Dictionary] = []
var night: bool = false

func instances() -> Array[Dictionary]:
	return data

func is_night() -> bool:
	return night
