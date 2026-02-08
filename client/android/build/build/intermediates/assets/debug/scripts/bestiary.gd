extends Control

@onready var list_label: RichTextLabel = %ListLabel
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	render()

func render() -> void:
	var lines: Array[String] = []
	for c in AppState.creatures:
		lines.append("• %s — %s %s (%s)" % [c.get("name","?"), c.get("rarity","?"), c.get("element","?"), c.get("archetype","?")])
	list_label.text = "\n".join(lines) if lines.size() > 0 else "(empty)"

func _on_back_pressed() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
