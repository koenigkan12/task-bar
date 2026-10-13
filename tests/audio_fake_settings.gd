# Settings falso (só para testes de áudio).
extends Node

signal changed(key: String)

var values: Dictionary = {"audio_mode": "ambient", "master_volume": 0.8, "sound_unlocked": false}

func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)

func set_value(key: String, value: Variant) -> void:
	values[key] = value
	changed.emit(key)
