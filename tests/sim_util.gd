extends RefCounted
## Utilitários de teste: comparação profunda com tolerância (o parser de JSON do Godot erra 1 ulp em floats).


static func deep_close(a: Variant, b: Variant, tol: float = 1e-9, path: String = "") -> String:
	if (a is float or a is int) and (b is float or b is int):
		var x := float(a)
		var y := float(b)
		if absf(x - y) <= tol * maxf(1.0, maxf(absf(x), absf(y))):
			return ""
		return "%s: %s != %s" % [path, str(a), str(b)]
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return "%s: tamanho de dicionário %d != %d" % [path, da.size(), db.size()]
		for k in da.keys():
			var kk: Variant = k
			if not db.has(kk):
				var alt: Variant = str(k) if not (k is String) else k
				if db.has(alt):
					kk = alt
				else:
					return "%s: falta a chave %s" % [path, str(k)]
			var r := deep_close(da[k], db[kk], tol, path + "." + str(k))
			if r != "":
				return r
		return ""
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: tamanho de array %d != %d" % [path, aa.size(), ab.size()]
		for i in aa.size():
			var r2 := deep_close(aa[i], ab[i], tol, path + "[%d]" % i)
			if r2 != "":
				return r2
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]
