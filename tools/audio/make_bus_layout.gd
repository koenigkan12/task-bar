# Gera assets/audio/bus_layout.tres (Master, Radio, Ambient, UI).
# Uso: godot --headless --path . --script res://tools/audio/make_bus_layout.gd
extends SceneTree

func _init() -> void:
	AudioServer.set_bus_count(1)
	AudioServer.set_bus_name(0, "Master")
	AudioServer.set_bus_volume_db(0, 0.0)
	# limitador na saída: vários loops somados nunca estouram
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	lim.threshold_db = -3.0
	AudioServer.add_bus_effect(0, lim)

	# Radio: banda de rádio de bateria (chiado já está nos arquivos) + distorção leve
	var radio := _add_bus("Radio", -2.0)
	var hpf := AudioEffectHighPassFilter.new()
	hpf.cutoff_hz = 250.0
	AudioServer.add_bus_effect(radio, hpf)
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = 3500.0
	AudioServer.add_bus_effect(radio, lpf)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_ATAN
	dist.pre_gain = 0.0
	dist.keep_hf_hz = 3000.0
	dist.drive = 0.12
	dist.post_gain = 0.0
	AudioServer.add_bus_effect(radio, dist)

	# Ambient: mundo (máquinas, ambiente, obras); só um low-pass de segurança
	var amb := _add_bus("Ambient", 0.0)
	var alp := AudioEffectLowPassFilter.new()
	alp.cutoff_hz = 5000.0
	AudioServer.add_bus_effect(amb, alp)

	# UI: cliques; sem efeitos
	_add_bus("UI", 0.0)

	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, "res://assets/audio/bus_layout.tres")
	print("bus_layout salvo: ", error_string(err))
	quit(0 if err == OK else 1)


func _add_bus(bus_name: String, vol_db: float) -> int:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, vol_db)
	return i
