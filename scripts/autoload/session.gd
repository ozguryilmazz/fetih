extends Node
## Ekranlar arası taşınan geçici bilgiler (hangi bölüm oynanacak vb.).

var mode := "solo"
var level := 1


func go(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)
