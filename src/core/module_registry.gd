class_name ModuleRegistry
extends RefCounted
## Registro central dos módulos de gameplay independentes.
##
## Um módulo é uma pasta autocontida em res://src/modules/<id>/ cuja cena raiz
## estende GameModule. O boot inicia os módulos através deste registro, de modo
## que o núcleo nunca referencia um sistema de gameplay concreto. Adicionar um
## sistema novo = uma linha aqui + uma pasta nova, sem tocar nos demais módulos.

static var _registry: Dictionary = {}
static var _booted: Array[String] = []


## Registra os módulos que acompanham o build.
## Intencionalmente vazio: a MISSÃO 001 prepara apenas a infraestrutura e a
## jogabilidade depende de aprovação antes de ser implementada.
static func register_builtin_modules() -> void:
	pass


static func register_module(module_id: String, scene_path: String) -> void:
	_registry[module_id] = scene_path


static func boot_all(root: Node) -> int:
	var started := 0
	for module_id: String in _registry:
		var scene_path: String = _registry[module_id]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("ModuleRegistry: modulo '%s' nao pode ser carregado de %s" % [module_id, scene_path])
			continue
		var instance := packed.instantiate()
		instance.name = module_id
		root.add_child(instance)
		_booted.append(module_id)
		started += 1
	return started


static func booted_modules() -> Array[String]:
	return _booted.duplicate()
