extends Control

@onready var api_input: LineEdit = $VBox/ApiInput
@onready var help_label: Label = $VBox/HelpLabel
@onready var save_button: Button = $VBox/Buttons/SaveButton
@onready var back_button: Button = $VBox/Buttons/BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)
	api_input.text_changed.connect(_on_text_changed)

	api_input.text = AppState.api_base_url
	_validate()

func _on_text_changed(_t: String) -> void:
	_validate()

func _validate() -> void:
	var url := api_input.text.strip_edges()
	var ok := _is_allowed_url(url)
	save_button.disabled = not ok
	if ok:
		help_label.text = "OK"
	else:
		help_label.text = "Invalid. Use https:// for public hosts. http:// allowed only for localhost/127.0.0.1/private LAN."

func _is_allowed_url(url: String) -> bool:
	if url == "":
		return false
	if url.begins_with("https://"):
		return true
	if not url.begins_with("http://"):
		return false

	# http:// only for local/private ranges
	var host := url.trim_prefix("http://")
	# strip port/path
	if host.find("/") != -1:
		host = host.substr(0, host.find("/"))
	if host.find(":") != -1:
		host = host.substr(0, host.find(":"))

	if host == "localhost" or host == "127.0.0.1":
		return true
	# very small private IP check (MVP)
	if host.begins_with("10.") or host.begins_with("192.168."):
		return true
	if host.begins_with("172."):
		var parts := host.split(".")
		if parts.size() >= 2:
			var second := int(parts[1])
			if second >= 16 and second <= 31:
				return true
	return false

func _on_save_pressed() -> void:
	AppState.api_base_url = api_input.text.strip_edges()
	AppState.save_settings()
	help_label.text = "Saved."

func _on_back_pressed() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
