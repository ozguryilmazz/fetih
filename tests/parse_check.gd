extends SceneTree
## Tüm betikleri derler; herhangi biri derlenemezse hata verir.
## godot --headless --path . -s tests/parse_check.gd


func _initialize() -> void:
	var failed: Array = []
	var count := 0
	for path in _scripts("res://scripts"):
		count += 1
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			failed.append(path)
	for f in failed:
		print("  HATA derlenemedi: ", f)
	print("%d betik kontrol edildi" % count)
	print("SONUC: ", "HATA" if failed else "TAMAM")
	quit(1 if failed else 0)


func _scripts(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
