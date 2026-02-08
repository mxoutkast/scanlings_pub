extends Control

const TEAM_MIN := 3
const TEAM_MAX := 5

@onready var team_label: Label = $VBox/TeamLabel
@onready var status_label: Label = $VBox/StatusLabel
@onready var edit_team_button: Button = $VBox/Buttons/EditTeamButton
@onready var formation_button: Button = $VBox/Buttons/FormationButton
@onready var battle_button: Button = $VBox/Buttons/BattleButton
@onready var back_button: Button = $VBox/BackButton
@onready var http: HTTPRequest = $Http

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	edit_team_button.pressed.connect(_on_edit_team_pressed)
	formation_button.pressed.connect(_on_formation_pressed)
	battle_button.pressed.connect(_on_battle_pressed)
	http.request_completed.connect(_on_request_completed)
	refresh()

func refresh() -> void:
	var ids: Array = AppState.active_team
	var names: Array[String] = []
	for idv in ids:
		var c := AppState.creature_by_local_id(str(idv))
		if c.is_empty():
			continue
		names.append(str(c.get("name", "?")))
	team_label.text = "Team (%d): %s" % [names.size(), ", ".join(names)] if names.size() > 0 else "Team: (none)"

	var n := ids.size()
	battle_button.disabled = not (n >= TEAM_MIN and n <= TEAM_MAX)
	if battle_button.disabled:
		battle_button.text = "Battle (pick 3–5)"
	else:
		battle_button.text = "Battle"

func _on_edit_team_pressed() -> void:
	AppState.go("res://scenes/TeamBuilder.tscn")

func _on_formation_pressed() -> void:
	AppState.go("res://scenes/Formation.tscn")

func _on_back_pressed() -> void:
	AppState.go("res://scenes/MainMenu.tscn")

func _on_battle_pressed() -> void:
	status_label.text = ""
	battle_button.disabled = true

	var my_ids: Array = []
	for idv in AppState.active_team:
		my_ids.append(str(idv))
	var opp_ids: Array = _build_opponent_team(my_ids)

	AppState.pending_battle = {"my_team": my_ids, "opponent_team": opp_ids}

	var my_units: Array = _units_from_ids(my_ids)
	var opp_units: Array = _units_from_ids(opp_ids)

	# Try backend; if it fails we fall back to mock.
	var base: String = AppState.api_base_url.strip_edges().trim_suffix("/")
	var url: String = base + "/v1/ladder/battle"
	var body: Dictionary = {"my_team": my_units, "opponent_team": opp_units}
	var json_body: String = JSON.stringify(body)

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"X-Device-Id: " + AppState.device_id
	])

	var err := http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		status_label.text = "HTTP request error (%s). Using mock." % str(err)
		_make_mock_result_and_go(my_ids, opp_ids)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	refresh()

	if result != HTTPRequest.RESULT_SUCCESS:
		status_label.text = "Request failed (%s). Using mock." % str(result)
		_make_mock_result_and_go(AppState.pending_battle.get("my_team", []), AppState.pending_battle.get("opponent_team", []))
		return

	var text: String = body.get_string_from_utf8()
	var parsed_v: Variant = JSON.parse_string(text)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		status_label.text = "Bad JSON from server. Using mock."
		_make_mock_result_and_go(AppState.pending_battle.get("my_team", []), AppState.pending_battle.get("opponent_team", []))
		return

	if response_code < 200 or response_code >= 300:
		status_label.text = "Server HTTP %d. Using mock." % response_code
		_make_mock_result_and_go(AppState.pending_battle.get("my_team", []), AppState.pending_battle.get("opponent_team", []))
		return

	var parsed: Dictionary = parsed_v
	AppState.pending_battle_result = parsed
	status_label.text = "Battle loaded from server."
	AppState.go("res://scenes/BattleReplay.tscn")

func _build_opponent_team(my_team: Array) -> Array:
	var opp_team: Array = []
	for c in AppState.creatures:
		var cid: String = str(c.get("local_id", ""))
		if cid == "":
			continue
		if my_team.has(cid):
			continue
		opp_team.append(cid)
		if opp_team.size() >= my_team.size():
			break
	while opp_team.size() < my_team.size():
		opp_team.append(my_team[opp_team.size()])
	return opp_team

func _units_from_ids(ids: Array) -> Array:
	var out: Array = []
	for idv in ids:
		var id: String = str(idv)
		var c: Dictionary = AppState.creature_by_local_id(id)
		out.append({
			"local_id": id,
			"archetype": str(c.get("archetype", "Cannon Critter")),
			"element": str(c.get("element", "Water")),
			"rarity": str(c.get("rarity", "Common"))
		})
	return out

func _make_mock_result_and_go(my_team: Array, opp_team: Array) -> void:
	var turn_log: Array = []
	var cues: Array[String] = ["CUE_TWO_BEAT", "CUE_TARGET_MARK", "CUE_CHARGE_SHAKE", "CUE_RING_PULSE"]
	var moves: Array[String] = ["steam_peck", "slam", "scoop_n_fling", "cutlery_clatter"]
	for t in range(1, 9):
		var me_i: int = (t - 1) % my_team.size()
		var opp_i: int = (t - 1) % opp_team.size()
		var actor: String = "me_%d" % (me_i + 1) if (t % 2 == 1) else "opp_%d" % (opp_i + 1)
		var target: String = "opp_%d" % (opp_i + 1) if (t % 2 == 1) else "me_%d" % (me_i + 1)
		turn_log.append({
			"turn": t,
			"actor": actor,
			"target": target,
			"move_id": moves[(t - 1) % moves.size()],
			"cue": cues[(t - 1) % cues.size()],
			"hit": true,
			"damage": 10 + (t % 9),
			"status_applied": []
		})

	# Minimal units + HP for replay UI
	var units_me: Array = []
	var units_opp: Array = []
	for i in range(my_team.size()):
		var cme: Dictionary = AppState.creature_by_local_id(str(my_team[i]))
		units_me.append({
			"ref": "me_%d" % (i + 1),
			"local_id": str(my_team[i]),
			"archetype": str(cme.get("archetype", "Cannon Critter")),
			"role": "dps"
		})
	for j in range(opp_team.size()):
		var cop: Dictionary = AppState.creature_by_local_id(str(opp_team[j]))
		units_opp.append({
			"ref": "opp_%d" % (j + 1),
			"local_id": str(opp_team[j]),
			"archetype": str(cop.get("archetype", "Cannon Critter")),
			"role": "dps"
		})

	var me_init: Array = []
	for _i in range(my_team.size()):
		me_init.append(100)
	var opp_init: Array = []
	for _j in range(opp_team.size()):
		opp_init.append(100)

	AppState.pending_battle_result = {
		"battle_id": "mock_" + str(Time.get_unix_time_from_system()),
		"winner": "me",
		"winner_reason": "mock",
		"end_turn": turn_log.size(),
		"rating_delta": {"me": 12, "opp": -12},
		"essence_reward": 20,
		"seed": 123456789,
		"units": {"me": units_me, "opp": units_opp},
		"initial_hp": {"me": me_init, "opp": opp_init},
		"turn_log": turn_log
	}
	AppState.go("res://scenes/BattleReplay.tscn")
