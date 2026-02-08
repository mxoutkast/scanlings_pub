extends Control

@onready var status: Label = $VBox/Status
@onready var back_button: Button = $VBox/BackButton

@onready var spawn_all: Button = $VBox/Buttons/SpawnAll
@onready var b1: Button = $VBox/Buttons/Bulwark
@onready var b2: Button = $VBox/Buttons/Cannon
@onready var b3: Button = $VBox/Buttons/Sprout
@onready var b4: Button = $VBox/Buttons/Zoner
@onready var b5: Button = $VBox/Buttons/Pouncer
@onready var b6: Button = $VBox/Buttons/Forge
@onready var b7: Button = $VBox/Buttons/Hex
@onready var b8: Button = $VBox/Buttons/Storm

func _ready() -> void:
	back_button.pressed.connect(_on_back)
	spawn_all.pressed.connect(_on_spawn_all)
	b1.pressed.connect(func(): _spawn("Bulwark Golem", "Earth"))
	b2.pressed.connect(func(): _spawn("Cannon Critter", "Water"))
	b3.pressed.connect(func(): _spawn("Sprout Medic", "Nature"))
	b4.pressed.connect(func(): _spawn("Zoner Wisp", "Air"))
	b5.pressed.connect(func(): _spawn("Pouncer", "Shadow"))
	b6.pressed.connect(func(): _spawn("Forge Pup", "Fire"))
	b7.pressed.connect(func(): _spawn("Hex Scholar", "Arcane"))
	b8.pressed.connect(func(): _spawn("Storm Skater", "Lightning"))
	status.text = "Creatures: %d" % AppState.creatures.size()

func _on_spawn_all() -> void:
	_spawn("Bulwark Golem", "Earth")
	_spawn("Cannon Critter", "Water")
	_spawn("Sprout Medic", "Nature")
	_spawn("Zoner Wisp", "Air")
	_spawn("Pouncer", "Shadow")
	_spawn("Forge Pup", "Fire")
	_spawn("Hex Scholar", "Arcane")
	_spawn("Storm Skater", "Lightning")

func _spawn(archetype: String, element: String) -> void:
	var creature := {
		"local_id": str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000000),
		"name": archetype,
		"rarity": "Common",
		"element": element,
		"archetype": archetype,
		"silhouette_id": "dev_" + archetype.to_lower().replace(" ", "_"),
		"moves": [
			{"name": "Dev Move A", "cue": "CUE_TWO_BEAT"},
			{"name": "Dev Move B", "cue": "CUE_TARGET_MARK"}
		]
	}
	AppState.creatures.append(creature)
	AppState.save()
	status.text = "Spawned: %s (total %d)" % [archetype, AppState.creatures.size()]

func _on_back() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
