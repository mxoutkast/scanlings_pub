extends Control

@onready var slots_box: VBoxContainer = $VBox/Slots
@onready var status: Label = $VBox/Status
@onready var save_button: Button = $VBox/Buttons/SaveButton
@onready var back_button: Button = $VBox/Buttons/BackButton

var order: Array = [] # local_id strings

func _ready() -> void:
	back_button.pressed.connect(_on_back)
	save_button.pressed.connect(_on_save)

	# start from active_team order
	order = []
	for idv in AppState.active_team:
		order.append(str(idv))

	render()

func render() -> void:
	for c in slots_box.get_children():
		c.queue_free()

	for i in range(order.size()):
		var id: String = str(order[i])
		var cdict: Dictionary = AppState.creature_by_local_id(id)
		var nm: String = str(cdict.get("name", "?"))
		var arch: String = str(cdict.get("archetype", "?"))

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := Label.new()
		label.text = "#%d %s (%s)" % [i + 1, nm, arch]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var up := Button.new()
		up.text = "↑"
		up.disabled = i == 0
		up.pressed.connect(func(): _move(i, -1))
		row.add_child(up)

		var down := Button.new()
		down.text = "↓"
		down.disabled = i == order.size() - 1
		down.pressed.connect(func(): _move(i, +1))
		row.add_child(down)

		slots_box.add_child(row)

	status.text = "Frontline: #1–#2 | Backline: #3–#5"

func _move(i: int, delta: int) -> void:
	var j := i + delta
	if j < 0 or j >= order.size():
		return
	var tmp = order[i]
	order[i] = order[j]
	order[j] = tmp
	render()

func _on_save() -> void:
	AppState.active_team = order
	AppState.save()
	status.text = "Saved."

func _on_back() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
