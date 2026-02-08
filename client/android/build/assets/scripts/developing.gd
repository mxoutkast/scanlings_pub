extends Control

@onready var stage_label: Label = %StageLabel
@onready var tip_label: Label = %TipLabel
@onready var spinner_label: Label = %Spinner

var http: HTTPRequest
var _animating: bool = false
var _spin_t: float = 0.0
var _tip_t: float = 0.0
var _spin_i: int = 0
var _tip_i: int = 0
var _spin_frames: Array[String] = ["⟲", "⟳", "⟲", "⟳"]
var _tips: Array[String] = [
	"Extracting silhouette…",
	"Distilling palette…",
	"Binding element…",
	"Forging rarity tint…",
	"Carving a face into the frame…",
	"Polishing card edges…",
	"Teaching it new moves…",
]

func _ready() -> void:
	AppState.apply_ui_scale(self)
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)

	tip_label.text = ""
	_animating = true
	_spin_t = 0.0
	_tip_t = 0.0
	_spin_i = 0
	_tip_i = 0
	spinner_label.text = _spin_frames[0]
	tip_label.text = _tips[0]
	set_process(true)

	await stage("Reading object…", 0.4)
	await stage("Uploading…", 0.4)
	call_scan()

func stage(text: String, seconds: float) -> void:
	stage_label.text = text
	await get_tree().create_timer(seconds).timeout

func _process(delta: float) -> void:
	if not _animating:
		set_process(false)
		return

	_spin_t += delta
	_tip_t += delta

	if _spin_t >= 0.18:
		_spin_t = 0.0
		_spin_i = (_spin_i + 1) % _spin_frames.size()
		spinner_label.text = _spin_frames[_spin_i]

	if _tip_t >= 2.2:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % _tips.size()
		tip_label.text = _tips[_tip_i]

func call_scan() -> void:
	# MVP: no real camera yet. If we have no pending dummy jpeg, generate one.
	if AppState.pending_scan_dummy_jpeg.is_empty():
		AppState.pending_scan_dummy_jpeg = _make_dummy_jpeg()

	var boundary := "----scanlings_boundary_" + str(Time.get_unix_time_from_system())
	var body: PackedByteArray = ScanUpload.build_multipart(
		boundary,
		"image",
		AppState.pending_scan_filename,
		AppState.pending_scan_content_type,
		AppState.pending_scan_dummy_jpeg
	)

	var base: String = AppState.api_base_url.strip_edges().trim_suffix("/")
	var url: String = base + "/v1/scan"
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"X-Device-Id: " + AppState.device_id
	])

	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		stage_label.text = "Upload error (%s). Falling back." % str(err)
		create_dummy_creature()
		AppState.go("res://scenes/Reveal.tscn")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_animating = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		stage_label.text = "Scan failed (%s/%d). Falling back." % [str(result), response_code]
		create_dummy_creature()
		AppState.go("res://scenes/Reveal.tscn")
		return

	var text: String = body.get_string_from_utf8()
	var parsed_v: Variant = JSON.parse_string(text)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		stage_label.text = "Bad scan JSON. Falling back."
		create_dummy_creature()
		AppState.go("res://scenes/Reveal.tscn")
		return
	var parsed: Dictionary = parsed_v
	if OS.has_feature("debug"):
		# Avoid editor output overflow by writing full JSON to a file and printing a short summary.
		var fp := "user://last_scan_response.json"
		var f := FileAccess.open(fp, FileAccess.WRITE)
		if f == null:
			print("/v1/scan debug: failed to open file for write: " + fp)
			print("user_data_dir=" + OS.get_user_data_dir())
		else:
			f.store_string(JSON.stringify(parsed, "  "))
			f.close()
			print("/v1/scan saved to " + fp + " (" + OS.get_user_data_dir() + ")")
		var creature_dbg: Variant = parsed.get("creature", null)
		if creature_dbg != null and typeof(creature_dbg) == TYPE_DICTIONARY:
			var cd: Dictionary = creature_dbg
			print("creature.name=" + str(cd.get("name","")) + ", archetype=" + str(cd.get("archetype","")) + ", silhouette_id=" + str(cd.get("silhouette_id","")))
			print("creature.essence=" + str(cd.get("essence", "")))

	# Expect: { creature: {...}, art: {art_b64_png, art_hash} }
	var creature_v: Variant = parsed.get("creature", null)
	if creature_v == null or typeof(creature_v) != TYPE_DICTIONARY:
		stage_label.text = "Missing creature. Falling back."
		create_dummy_creature()
		AppState.go("res://scenes/Reveal.tscn")
		return
	var creature: Dictionary = creature_v

	var art_v: Variant = parsed.get("art", null)
	if art_v != null and typeof(art_v) == TYPE_DICTIONARY:
		var art: Dictionary = art_v
		var b64: String = str(art.get("art_b64_png", ""))
		var art_hash: String = str(art.get("art_hash", ""))
		if b64 != "" and art_hash != "":
			var png_bytes := Marshalls.base64_to_raw(b64)
			AppState.store_art_png_bytes(art_hash, png_bytes)
			creature["art_hash"] = art_hash

	# Normalize moves (client format is name+cue)
	var moves_out: Array = []
	var moves_v: Variant = creature.get("moves", [])
	if moves_v is Array:
		for mv in moves_v:
			if typeof(mv) == TYPE_DICTIONARY:
				var md: Dictionary = mv
				moves_out.append({
					"name": str(md.get("name", md.get("move_id", "Move"))),
					"cue": str(md.get("cue", "CUE_TWO_BEAT"))
				})
	creature["moves"] = moves_out

	# Ensure local_id
	creature["local_id"] = str(creature.get("local_id", ""))
	if str(creature["local_id"]) == "":
		creature["local_id"] = str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000000)

	AppState.creatures.append(creature)
	AppState.save()
	AppState.pending_scan_dummy_jpeg = PackedByteArray()
	AppState.go("res://scenes/Reveal.tscn")

func _make_dummy_jpeg() -> PackedByteArray:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 1.0))
	for y in range(0, 64, 8):
		for x in range(0, 64, 8):
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0))
	return img.save_jpg_to_buffer(0.85)

func create_dummy_creature() -> void:
	var creature := {
		"local_id": str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000000),
		"name": "Spoon Scoopster",
		"rarity": "Common",
		"element": "Water",
		"archetype": "Cannon Critter",
		"silhouette_id": "cannon_critter_01",
		"moves": [
			{"name": "Scoop 'n Fling", "cue": "CUE_TWO_BEAT"},
			{"name": "Cutlery Clatter", "cue": "CUE_TARGET_MARK"}
		]
	}
	AppState.creatures.append(creature)
	AppState.save()
