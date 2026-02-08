extends Control

@onready var capture_button: Button = %CaptureButton
@onready var pick_button: Button = %PickButton
@onready var status_label: Label = %StatusLabel
@onready var file_dialog: FileDialog = $FileDialog

# MVP: no real camera yet.

func _ready() -> void:
	AppState.apply_ui_scale(self)
	capture_button.pressed.connect(_on_capture_pressed)
	pick_button.pressed.connect(_on_pick_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.files_selected.connect(_on_files_selected)

	# Only show picker in debug builds AND only on desktop.
	# On Android it will fail permissions / UX anyway.
	var is_debug := OS.has_feature("debug")
	var is_android := OS.has_feature("android")
	pick_button.visible = is_debug and not is_android
	if not pick_button.visible:
		status_label.text = ""

	if is_android:
		status_label.text = "Tip: Ensure backend URL is your PC LAN IP (not 127.0.0.1)."

func _on_pick_pressed() -> void:
	status_label.text = "Pick an image…"
	file_dialog.popup_centered_ratio(0.9)

func _on_files_selected(paths: PackedStringArray) -> void:
	if paths.size() <= 0:
		return
	_on_file_selected(paths[0])

func _on_file_selected(path: String) -> void:
	status_label.text = "Loading: " + path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		status_label.text = "Failed to open file (see console)."
		push_error("Failed to open file: " + path)
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	status_label.text = "Selected. Uploading…"
	AppState.pending_scan_dummy_jpeg = bytes
	var lower := path.to_lower()
	if lower.ends_with(".png"):
		AppState.pending_scan_content_type = "image/png"
		AppState.pending_scan_filename = "scan.png"
	else:
		AppState.pending_scan_content_type = "image/jpeg"
		AppState.pending_scan_filename = "scan.jpg"
	AppState.go("res://scenes/Developing.tscn")

func _on_capture_pressed() -> void:
	# Android native capture via plugin (fast MVP path).
	if OS.has_feature("android"):
		if not Engine.has_singleton("ScanlingsCamera"):
			status_label.text = "Camera plugin not loaded (ScanlingsCamera singleton missing)."
			return
		status_label.text = "Opening camera…"
		var cam = Engine.get_singleton("ScanlingsCamera")
		# Connect once per press.
		if not cam.is_connected("photo_captured_b64", Callable(self, "_on_photo_captured_b64")):
			cam.connect("photo_captured_b64", Callable(self, "_on_photo_captured_b64"))
		if not cam.is_connected("capture_failed", Callable(self, "_on_capture_failed")):
			cam.connect("capture_failed", Callable(self, "_on_capture_failed"))
		cam.call("capture_photo")
		return

	# Non-Android fallback: without camera, Capture uses a dummy image.
	AppState.go("res://scenes/Developing.tscn")

func _on_photo_captured_b64(b64: String) -> void:
	status_label.text = "Captured. Uploading…"
	var bytes := Marshalls.base64_to_raw(b64)
	AppState.pending_scan_dummy_jpeg = bytes
	AppState.pending_scan_content_type = "image/jpeg"
	AppState.pending_scan_filename = "scan.jpg"
	AppState.go("res://scenes/Developing.tscn")

func _on_capture_failed(message: String) -> void:
	status_label.text = "Camera failed: %s" % message
