extends Node3D
## Raiz da cena de boot (res://scenes/boot/main.tscn).
##
## Escopo da MISSÃO 001: provar que o projeto inicializa em modo headless e em
## Android com o renderizador Mobile. Nenhuma jogabilidade é implementada aqui —
## os módulos de gameplay são registrados e iniciados pelo ModuleRegistry
## somente após aprovação.

const _LOG_TAG := "bootstrap"

@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D


func _ready() -> void:
	# Ângulo da luz mantido em código para o .tscn permanecer simples.
	_directional_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)

	ModuleRegistry.register_builtin_modules()
	var started := ModuleRegistry.boot_all(self)
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	print("[%s] Spider-Man: New Life v%s pronta. Modulos ativos: %d." % [_LOG_TAG, version, started])
