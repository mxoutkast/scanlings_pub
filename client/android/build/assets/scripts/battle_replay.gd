extends Control

# Portrait-friendly two-row layout.

@onready var header_label: Label = $VBox/HeaderLabel
@onready var opp_front: HBoxContainer = $VBox/OpponentGrid/OppFront
@onready var opp_back: HBoxContainer = $VBox/OpponentGrid/OppBack
@onready var my_front: HBoxContainer = $VBox/MyGrid/MyFront
@onready var my_back: HBoxContainer = $VBox/MyGrid/MyBack
@onready var turn_label: Label = $VBox/TurnLabel
@onready var result_label: Label = $VBox/ResultLabel

@onready var next_turn_button: Button = $VBox/Controls/NextTurnButton
@onready var auto_button: Button = $VBox/Controls/AutoButton
@onready var reset_button: Button = $VBox/Controls/ResetButton
@onready var back_button: Button = $VBox/BackButton

@onready var auto_timer: Timer = $AutoTimer

var my_ids: Array = []
var opp_ids: Array = []

# ref (me_1/opp_3) -> {role, archetype}
var unitmeta_by_ref: Dictionary = {}

# local_id -> status label
var statuslabel_by_id: Dictionary = {}

# Each entry (API_SPEC-shaped mock):
# {turn:int, actor:String, target:String, cue:String, move_id:String, hit:bool, damage:int}
var turn_log: Array = []
var turn_index: int = -1
var auto_on: bool = false

# local_id -> card Control
var card_by_id: Dictionary = {}
# local_id -> ProgressBar
var hpbar_by_id: Dictionary = {}
# local_id -> ProgressBar
var shieldbar_by_id: Dictionary = {}
# local_id -> hp (int)
var hp_by_id: Dictionary = {}
# local_id -> hp_max (int)
var hpmax_by_id: Dictionary = {}
# local_id -> shield (int)
var shield_by_id: Dictionary = {}

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	next_turn_button.pressed.connect(_on_next_turn_pressed)
	auto_button.pressed.connect(_on_auto_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	auto_timer.timeout.connect(_on_auto_tick)

	load_from_pending_battle()
	load_result_header()
	build_cards()
	load_turn_log_from_result_or_mock()
	reset_replay()

func load_result_header() -> void:
	var br: Dictionary = AppState.pending_battle_result
	if br.is_empty():
		result_label.text = "(no result)"
		return
	var winner: String = str(br.get("winner", ""))
	var reason: String = str(br.get("winner_reason", ""))
	var end_turn: int = int(br.get("end_turn", 0))
	var delta_v: Variant = br.get("rating_delta", null)
	var delta_text := ""
	if delta_v != null and typeof(delta_v) == TYPE_DICTIONARY:
		var d: Dictionary = delta_v
		delta_text = " Δ" + str(d.get("me", ""))
	result_label.text = "Winner: %s (%s) • end_turn=%d%s" % [winner, reason, end_turn, delta_text]

func load_from_pending_battle() -> void:
	var pb: Dictionary = AppState.pending_battle
	my_ids = pb.get("my_team", [])
	opp_ids = pb.get("opponent_team", [])
	header_label.text = "Team sizes — You: %d, Opponent: %d" % [my_ids.size(), opp_ids.size()]

	_load_unit_meta_from_result()

func _load_unit_meta_from_result() -> void:
	unitmeta_by_ref.clear()
	var br: Dictionary = AppState.pending_battle_result
	if br.is_empty():
		return
	var units_v: Variant = br.get("units", null)
	if units_v == null or typeof(units_v) != TYPE_DICTIONARY:
		return
	var units: Dictionary = units_v
	for side_key in ["me", "opp"]:
		var arr_v: Variant = units.get(side_key, null)
		if not (arr_v is Array):
			continue
		var arr: Array = arr_v
		for u_v in arr:
			if typeof(u_v) != TYPE_DICTIONARY:
				continue
			var u: Dictionary = u_v
			var ref: String = str(u.get("ref", ""))
			if ref == "":
				continue
			unitmeta_by_ref[ref] = {
				"role": str(u.get("role", "")),
				"archetype": str(u.get("archetype", ""))
			}

func _init_hp_from_result_or_defaults() -> void:
	# Initialize hp/hp_max maps from server result if provided.
	# Fallback: 100 for all.
	for idv in my_ids:
		var id: String = str(idv)
		hpmax_by_id[id] = 100
		hp_by_id[id] = 100
		shield_by_id[id] = 0
	for idv in opp_ids:
		var id2: String = str(idv)
		hpmax_by_id[id2] = 100
		hp_by_id[id2] = 100
		shield_by_id[id2] = 0

	var br: Dictionary = AppState.pending_battle_result
	if br.is_empty():
		return

	# Expected shape: initial_hp: {me:[...], opp:[...]}
	var ih: Variant = br.get("initial_hp", null)
	if ih == null or typeof(ih) != TYPE_DICTIONARY:
		return
	var ihd: Dictionary = ih
	var meArrV: Variant = ihd.get("me", null)
	var oppArrV: Variant = ihd.get("opp", null)
	if meArrV is Array:
		var meArr: Array = meArrV
		for i in range(min(meArr.size(), my_ids.size())):
			var id3: String = str(my_ids[i])
			var hm: int = int(meArr[i])
			hpmax_by_id[id3] = hm
			hp_by_id[id3] = hm
	if oppArrV is Array:
		var oppArr: Array = oppArrV
		for j in range(min(oppArr.size(), opp_ids.size())):
			var id4: String = str(opp_ids[j])
			var hm2: int = int(oppArr[j])
			hpmax_by_id[id4] = hm2
			hp_by_id[id4] = hm2

func build_cards() -> void:
	# Clear existing
	for child in opp_front.get_children():
		child.queue_free()
	for child in opp_back.get_children():
		child.queue_free()
	for child in my_front.get_children():
		child.queue_free()
	for child in my_back.get_children():
		child.queue_free()
	card_by_id.clear()
	hpbar_by_id.clear()
	shieldbar_by_id.clear()
	hp_by_id.clear()
	hpmax_by_id.clear()
	shield_by_id.clear()

	# Initialize HP from pending_battle_result if available
	_init_hp_from_result_or_defaults()

	for i in range(opp_ids.size()):
		var id: String = str(opp_ids[i])
		var card := _make_card(id, AppState.creature_by_local_id(id), false)
		if i < 2:
			opp_front.add_child(card)
		else:
			opp_back.add_child(card)
		card_by_id[id] = card

	for j in range(my_ids.size()):
		var id2: String = str(my_ids[j])
		var card2 := _make_card(id2, AppState.creature_by_local_id(id2), true)
		if j < 2:
			my_front.add_child(card2)
		else:
			my_back.add_child(card2)
		card_by_id[id2] = card2

func _make_card(local_id: String, creature: Dictionary, is_me: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 130)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var name_label := Label.new()
	name_label.text = str(creature.get("name", "Unknown"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_label)

	var meta := Label.new()
	meta.text = "%s • %s" % [str(creature.get("archetype", "?")), str(creature.get("element", "?"))]
	vb.add_child(meta)

	# Role badge from backend units meta (ref is derived by side + index)
	var badge := Label.new()
	badge.text = _role_badge_text(is_me, local_id)
	vb.add_child(badge)

	var status_label := Label.new()
	status_label.text = ""
	vb.add_child(status_label)
	statuslabel_by_id[local_id] = status_label

	var shieldbar := ProgressBar.new()
	shieldbar.min_value = 0
	shieldbar.max_value = 60
	shieldbar.value = int(shield_by_id.get(local_id, 0))
	shieldbar.show_percentage = false
	shieldbar.custom_minimum_size = Vector2(0, 10)
	vb.add_child(shieldbar)
	shieldbar_by_id[local_id] = shieldbar

	var hpbar := ProgressBar.new()
	hpbar.min_value = 0
	var hm: int = int(hpmax_by_id.get(local_id, 100))
	hpbar.max_value = hm
	hpbar.value = int(hp_by_id.get(local_id, hm))
	hpbar.show_percentage = false
	hpbar.custom_minimum_size = Vector2(0, 16)
	vb.add_child(hpbar)
	hpbar_by_id[local_id] = hpbar

	var tag := Label.new()
	tag.text = "YOU" if is_me else "OPP"
	vb.add_child(tag)

	panel.modulate = Color(1, 1, 1, 1)
	return panel

func load_turn_log_from_result_or_mock() -> void:
	turn_log.clear()

	var br: Dictionary = AppState.pending_battle_result
	if not br.is_empty() and br.has("turn_log"):
		var tlv: Variant = br.get("turn_log", null)
		if tlv is Array:
			turn_log = tlv
			return

	# Fallback: local mock (should be rare now)
	if my_ids.size() == 0 or opp_ids.size() == 0:
		return

	var cues: Array[String] = ["CUE_TWO_BEAT", "CUE_TARGET_MARK", "CUE_CHARGE_SHAKE", "CUE_RING_PULSE"]
	var moves: Array[String] = ["steam_peck", "slam", "scoop_n_fling", "cutlery_clatter"]

	for t in range(1, 7):
		var me_i: int = (t - 1) % my_ids.size()
		var opp_i: int = (t - 1) % opp_ids.size()
		var actor: String = "me_%d" % (me_i + 1)
		var target: String = "opp_%d" % (opp_i + 1)
		turn_log.append({
			"turn": t,
			"actor": actor,
			"target": target,
			"cue": cues[(t - 1) % cues.size()],
			"move_id": moves[(t - 1) % moves.size()],
			"hit": true,
			"damage": 12 + (t % 7),
			"status_applied": []
		})

func reset_replay() -> void:
	auto_on = false
	auto_timer.stop()
	auto_button.text = "Auto"
	turn_index = -1
	turn_label.text = "Press Next Turn"

	# Reset HP/shield bars to initial state
	_init_hp_from_result_or_defaults()
	for k in hpbar_by_id.keys():
		var pb: ProgressBar = hpbar_by_id[k]
		var hm: int = int(hpmax_by_id.get(k, 100))
		pb.max_value = hm
		pb.value = int(hp_by_id.get(k, hm))
	for k2 in shieldbar_by_id.keys():
		var sb: ProgressBar = shieldbar_by_id[k2]
		sb.value = int(shield_by_id.get(k2, 0))

	_clear_highlights()

func step() -> void:
	if turn_log.size() == 0:
		turn_label.text = "(no turn log)"
		return

	turn_index += 1
	if turn_index >= turn_log.size():
		turn_label.text = "End of replay"
		auto_on = false
		auto_timer.stop()
		auto_button.text = "Auto"
		return

	_clear_highlights()
	var e: Dictionary = turn_log[turn_index]

	var actor_ref: String = str(e.get("actor", ""))
	var target_ref: String = str(e.get("target", ""))
	var cue_id: String = str(e.get("cue", ""))
	var move_id: String = str(e.get("move_id", ""))
	var move_name: String = str(e.get("move_name", ""))
	var misfire: bool = bool(e.get("misfire", false))
	var intercepted: bool = bool(e.get("intercepted", false))
	var target_original: String = str(e.get("target_original", ""))

	var actor_id: String = _resolve_ref_to_local_id(actor_ref)
	var target_id: String = _resolve_ref_to_local_id(target_ref)

	var move_disp: String = move_name if move_name != "" else move_id
	var _extra: String = " MISFIRE" if misfire else ""
	var _inter: String = "" 
	if intercepted and target_original != "" and target_original != target_ref:
		_inter = " (INTERCEPT %s→%s)" % [target_original, target_ref]
	turn_label.text = "Turn %d: %s → %s (%s / %s)%s%s" % [
		int(e.get("turn", turn_index + 1)),
		actor_ref,
		target_ref,
		move_disp,
		cue_id,
		_extra,
		_inter
	]

	# Base highlight
	_highlight(actor_id, Color(0.78, 1.0, 0.78, 1.0))
	_highlight(target_id, Color(1.0, 0.8, 0.8, 1.0))

	# Apply HP updates if server provided them
	_apply_hp_update_if_any(e)
	_apply_statuses_if_any(e)

	# Floating combat text
	_spawn_floating_text(e)

	# Cue animation (deterministic UI "juice")
	_play_cue(cue_id, actor_id, target_id)

func _highlight(local_id: String, col: Color) -> void:
	if not card_by_id.has(local_id):
		return
	var card: Control = card_by_id[local_id]
	card.modulate = col

func _clear_highlights() -> void:
	for k in card_by_id.keys():
		var card: Control = card_by_id[k]
		card.modulate = Color(1, 1, 1, 1)
		card.scale = Vector2.ONE
		card.rotation = 0.0

func _apply_statuses_if_any(e: Dictionary) -> void:
	var jv: Variant = e.get("jam_remaining_by_ref", null)
	if jv == null or typeof(jv) != TYPE_DICTIONARY:
		return
	var jam_by_ref: Dictionary = jv
	# For each unit, compute its ref and update label
	for i in range(my_ids.size()):
		var ref: String = "me_%d" % (i + 1)
		var id: String = str(my_ids[i])
		var rem: int = int(jam_by_ref.get(ref, 0))
		_set_status_label(id, rem)
	for j in range(opp_ids.size()):
		var ref2: String = "opp_%d" % (j + 1)
		var id2: String = str(opp_ids[j])
		var rem2: int = int(jam_by_ref.get(ref2, 0))
		_set_status_label(id2, rem2)

func _set_status_label(local_id: String, jam_rem: int) -> void:
	if not statuslabel_by_id.has(local_id):
		return
	var lbl: Label = statuslabel_by_id[local_id]
	lbl.text = "STATUS: JAM" if jam_rem > 0 else ""

func _spawn_floating_text(e: Dictionary) -> void:
	var target_ref: String = str(e.get("target", ""))
	var target_id: String = _resolve_ref_to_local_id(target_ref)
	if target_id == "" or not card_by_id.has(target_id):
		return
	var card: Control = card_by_id[target_id]

	var dmg: int = int(e.get("damage", 0))
	var heal: int = int(e.get("healing", 0))
	var sh_delta: int = int(e.get("shield_delta", 0))
	var absorbed: int = int(e.get("absorbed", 0))
	var misfire: bool = bool(e.get("misfire", false))

	var lines: Array[String] = []
	var colors: Array[Color] = []
	if misfire:
		lines.append("MISFIRE")
		colors.append(Color(0.85, 0.85, 0.85, 1.0))
	if dmg > 0:
		lines.append("-%d" % dmg)
		colors.append(Color(1.0, 0.35, 0.35, 1.0))
	if absorbed > 0:
		lines.append("ABSORB %d" % absorbed)
		colors.append(Color(0.3, 0.9, 1.0, 1.0))
	if heal > 0:
		lines.append("+%d" % heal)
		colors.append(Color(0.35, 1.0, 0.45, 1.0))
	if sh_delta > 0:
		lines.append("+%d SH" % sh_delta)
		colors.append(Color(0.45, 0.65, 1.0, 1.0))
	if sh_delta < 0:
		lines.append("%d SH" % sh_delta)
		colors.append(Color(0.45, 0.65, 1.0, 1.0))

	if lines.size() == 0:
		return

	var label := Label.new()
	label.text = "\n".join(lines)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.z_index = 50
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Use the first color as primary; MVP simplicity.
	label.modulate = colors[0]

	card.add_child(label)
	label.position = Vector2(0, 0)
	label.size = card.size

	var tw := label.create_tween()
	# rise + fade
	tw.tween_property(label, "position", Vector2(0, -18), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func(): label.queue_free())

func _apply_hp_update_if_any(e: Dictionary) -> void:
	var target_ref: String = str(e.get("target", ""))
	var target_id: String = _resolve_ref_to_local_id(target_ref)
	if target_id == "":
		return
	if not hp_by_id.has(target_id):
		return

	var thp_v: Variant = e.get("target_hp", null)
	if thp_v != null:
		var thp: int = int(thp_v)
		hp_by_id[target_id] = thp
		if hpbar_by_id.has(target_id):
			var pb: ProgressBar = hpbar_by_id[target_id]
			pb.value = thp

		# Grey-out KO units
		if thp <= 0 and card_by_id.has(target_id):
			var card: Control = card_by_id[target_id]
			card.modulate = Color(0.6, 0.6, 0.6, 1.0)

	var tsh_v: Variant = e.get("target_shield", null)
	if tsh_v != null:
		var tsh: int = int(tsh_v)
		shield_by_id[target_id] = tsh
		if shieldbar_by_id.has(target_id):
			var sb: ProgressBar = shieldbar_by_id[target_id]
			sb.value = tsh

func _play_cue(cue_id: String, actor_id: String, target_id: String) -> void:
	var actor: Control = card_by_id.get(actor_id, null)
	var target: Control = card_by_id.get(target_id, null)

	match cue_id:
		"CUE_TWO_BEAT":
			if actor: _anim_two_beat(actor)
		"CUE_CHARGE_SHAKE":
			if actor: _anim_shake(actor)
		"CUE_TARGET_MARK":
			if target: _anim_target_mark(target)
		"CUE_RING_PULSE":
			if target: _anim_pulse(target)
		_:
			# default: subtle pulse on actor
			if actor: _anim_pulse(actor)

func _anim_two_beat(card: Control) -> void:
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2(1.06, 1.06), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.06)
	tw.tween_property(card, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _anim_shake(card: Control) -> void:
	var tw := card.create_tween()
	# small deterministic shake
	tw.tween_property(card, "rotation", -0.06, 0.05)
	tw.tween_property(card, "rotation", 0.06, 0.05)
	tw.tween_property(card, "rotation", -0.04, 0.05)
	tw.tween_property(card, "rotation", 0.04, 0.05)
	tw.tween_property(card, "rotation", 0.0, 0.05)

func _anim_target_mark(card: Control) -> void:
	var tw := card.create_tween()
	# flash red-ish then settle
	tw.tween_property(card, "modulate", Color(1.0, 0.55, 0.55, 1.0), 0.07)
	tw.tween_property(card, "modulate", Color(1.0, 0.8, 0.8, 1.0), 0.18)

func _anim_pulse(card: Control) -> void:
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _resolve_ref_to_local_id(ref: String) -> String:
	# ref examples: "me_1", "opp_3" (1-based)
	if ref.begins_with("me_"):
		var idx: int = int(ref.trim_prefix("me_")) - 1
		if idx >= 0 and idx < my_ids.size():
			return str(my_ids[idx])
		return ""
	if ref.begins_with("opp_"):
		var idx2: int = int(ref.trim_prefix("opp_")) - 1
		if idx2 >= 0 and idx2 < opp_ids.size():
			return str(opp_ids[idx2])
		return ""
	return ""

func _role_badge_text(is_me: bool, local_id: String) -> String:
	var idx := -1
	var arr: Array = my_ids if is_me else opp_ids
	for i in range(arr.size()):
		if str(arr[i]) == local_id:
			idx = i
			break
	if idx == -1:
		return "ROLE: ?"
	var ref: String = ("me_%d" % (idx + 1)) if is_me else ("opp_%d" % (idx + 1))
	var meta: Dictionary = unitmeta_by_ref.get(ref, {})
	var role: String = str(meta.get("role", "?"))
	return "ROLE: %s" % role.to_upper()

func _short(local_id: String) -> String:
	if local_id.length() <= 6:
		return local_id
	return local_id.substr(local_id.length() - 6, 6)

func _on_next_turn_pressed() -> void:
	step()

func _on_auto_pressed() -> void:
	auto_on = not auto_on
	if auto_on:
		auto_button.text = "Auto: ON"
		auto_timer.start()
		# advance immediately for responsiveness
		step()
	else:
		auto_button.text = "Auto"
		auto_timer.stop()

func _on_reset_pressed() -> void:
	reset_replay()

func _on_auto_tick() -> void:
	step()

func _on_back_pressed() -> void:
	AppState.go("res://scenes/Ladder.tscn")
