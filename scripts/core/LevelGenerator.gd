extends RefCounted
class_name LevelGenerator

var config


func generate(target, cfg = null):
	config = cfg if cfg != null else config
	if target and target.has_method("_apply_config") and config:
		target._apply_config(config)
	if target and target.has_method("_generate_legacy_grid"):
		target._generate_legacy_grid()
