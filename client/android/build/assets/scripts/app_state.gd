extends Node

func ui_scale() -> float:
	# Portrait phone UI scale. Keep conservative to avoid clipping.
	if OS.has_feature("android"):
		return 1.25
	return 1.0

func apply_ui_scale(root_node: CanvasItem) -> void:
	var s: float = ui_scale()
	root_node.scale = Vector2(s, s)

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const ART_DIR := "user://art"

# Backend base URL (settings override). Allow http only for localhost/private LAN.
var api_base_url: String = "http://127.0.0.1:8787"

# Temporary scan payload (until we have real camera capture)
var pending_scan_dummy_jpeg: PackedByteArray = PackedByteArray()
var pending_scan_content_type: String = "image/jpeg"
var pending_scan_filename: String = "scan.jpg"

var device_id: String = ""
var aether_charges: int = 5
var essence: int = 0
var fusion_cores: int = 1

# Stored as dictionaries for MVP. Later we can strongly-type.
var creatures: Array = []

# MVP: store active team as list of creature local_ids
var active_team: Array = []

# Last prepared battle payload (mock until backend exists)
var pending_battle: Dictionary = {}

# Last battle result (API_SPEC-shaped mock)
var pending_battle_result: Dictionary = {}

func creature_by_local_id(local_id: String) -> Dictionary:
	for c in creatures:
		if str(c.get("local_id", "")) == local_id:
			return c
	return {}

func _ready() -> void:
	ensure_device_id()
	ensure_dirs()
	load_settings()
	load_save()

func ensure_dirs() -> void:
	if not DirAccess.dir_exists_absolute(ART_DIR):
		DirAccess.make_dir_recursive_absolute(ART_DIR)

func ensure_device_id() -> void:
	# Lazy init; persisted in save
	if device_id == "":
		device_id = new_device_id()

func new_device_id() -> String:
	# Godot 4.x does not provide a built-in UUID helper in all builds.
	# Use Crypto random bytes and hex-encode.
	var c := Crypto.new()
	var bytes: PackedByteArray = c.generate_random_bytes(16)
	return bytes.hex_encode()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		save_settings()
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed_v: Variant = JSON.parse_string(text)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return
	var parsed: Dictionary = parsed_v
	api_base_url = str(parsed.get("api_base_url", api_base_url))

func save_settings() -> void:
	var data := {"api_base_url": api_base_url}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return
	var data: Dictionary = json.data
	device_id = data.get("device_id", device_id)
	aether_charges = int(data.get("aether_charges", aether_charges))
	essence = int(data.get("essence", essence))
	fusion_cores = int(data.get("fusion_cores", fusion_cores))
	creatures = data.get("creatures", creatures)
	active_team = data.get("active_team", active_team)

func save() -> void:
	var data := {
		"device_id": device_id,
		"aether_charges": aether_charges,
		"essence": essence,
		"fusion_cores": fusion_cores,
		"creatures": creatures,
		"active_team": active_team
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func go(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Failed to change scene to %s (err=%s)" % [scene_path, str(err)])

# --- Art cache ---
func art_path(art_hash: String) -> String:
	return "%s/%s.png" % [ART_DIR, art_hash]

func store_art_png_bytes(art_hash: String, png_bytes: PackedByteArray) -> void:
	var p := art_path(art_hash)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(png_bytes)
	f.close()

func load_art_texture(art_hash: String) -> Texture2D:
	var p := art_path(art_hash)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	var err := img.load(p)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)
