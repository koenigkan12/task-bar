class_name ClockText
extends RefCounted
## Texto de contagem regressiva do relógio único da cena (planta, obra, escavação, espera da caixa):
## >= 1 h -> "1h48"; < 1 h -> "45min"; < 1 min -> "agora".

static func of(minutes: float) -> String:
	if minutes < 1.0:
		return ScreenUtil.tr_key("time.now")
	var m: int = int(ceilf(minutes))
	if m >= 60:
		var h: int = m / 60
		var r: int = m % 60
		return ScreenUtil.tr_key("time.h", {"h": h}) if r == 0 else ScreenUtil.tr_key("time.hm", {"h": h, "m": "%02d" % r})
	return ScreenUtil.tr_key("time.min", {"m": m})
