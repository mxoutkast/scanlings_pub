extends Control

func _ready() -> void:
	# AppState autoload initializes on startup.
	await get_tree().process_frame
	AppState.go("res://scenes/MainMenu.tscn")
