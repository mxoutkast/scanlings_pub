extends Control

const TEAM_MIN := 3
const TEAM_MAX := 5

@onready var status_label: Label = $VBox/StatusLabel
@onready var active_list: ItemList = $VBox/ActiveList
@onready var roster_list: ItemList = $VBox/Scroll/RosterList
@onready var save_button: Button = $VBox/Buttons/SaveButton
@onready var back_button: Button = $VBox/Buttons/BackButton

# Active team as ordered local_ids
var active_ids: Array = []
# Roster list index -> local_id
var roster_ids: Array = []

func _ready() -> void:
	back_button.pressed.connect(_on_back)
	save_button.pressed.connect(_on_save)
	# In desktop/editor, ItemList activation is double-click/enter.
	# Use item_clicked for single-click.
	active_list.item_clicked.connect(_on_active_item_clicked)
	roster_list.item_clicked.connect(_on_roster_item_clicked)

	active_ids = []
	for idv in AppState.active_team:
		active_ids.append(str(idv))

	render()

func render() -> void:
	# Build roster ids
	roster_ids = []
	for c in AppState.creatures:
		var cid: String = str(c.get("local_id", ""))
		if cid != "":
			roster_ids.append(cid)

	active_list.clear()
	for id in active_ids:
		var cdict: Dictionary = AppState.creature_by_local_id(str(id))
		active_list.add_item(_label_for(cdict))

	roster_list.clear()
	for cid in roster_ids:
		var cdict2: Dictionary = AppState.creature_by_local_id(cid)
		var prefix := "✓ " if active_ids.has(cid) else "  "
		roster_list.add_item(prefix + _label_for(cdict2))

	_update_status()

func _label_for(cdict: Dictionary) -> String:
	var nm: String = str(cdict.get("name", "?"))
	var arch: String = str(cdict.get("archetype", "?"))
	var rarity: String = str(cdict.get("rarity", "?"))
	return "%s — %s (%s)" % [nm, arch, rarity]

func _update_status() -> void:
	var n := active_ids.size()
	status_label.text = "Active: %d (min %d, max %d)" % [n, TEAM_MIN, TEAM_MAX]
	save_button.disabled = not (n >= TEAM_MIN and n <= TEAM_MAX)

func _on_roster_item_clicked(index: int, _pos: Vector2, _button: int) -> void:
	if index < 0 or index >= roster_ids.size():
		return
	var cid: String = str(roster_ids[index])
	if active_ids.has(cid):
		return
	if active_ids.size() >= TEAM_MAX:
		status_label.text = "Team full (max %d). Remove one first." % TEAM_MAX
		return
	active_ids.append(cid)
	render()

func _on_active_item_clicked(index: int, _pos: Vector2, _button: int) -> void:
	if index < 0 or index >= active_ids.size():
		return
	active_ids.remove_at(index)
	render()

func _on_save() -> void:
	AppState.active_team = active_ids
	AppState.save()
	status_label.text = "Saved."
	render()

func _on_back() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
