class_name GameModule
extends Node
## Classe base dos módulos de gameplay independentes.
##
## Cada módulo vive em sua própria pasta em res://src/modules/<id>/ e tem a cena
## raiz estendendo esta classe. O ModuleRegistry instancia os módulos sem que o
## núcleo dependa de seus tipos concretos.

@export var module_id: String = ""


func _ready() -> void:
	module_ready()


## Sobrescreva nas subclasses. Chamado uma vez quando o módulo entra na árvore.
func module_ready() -> void:
	pass
