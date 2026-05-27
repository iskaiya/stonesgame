# UI.gd
# ─────────────────────────────────────────────────────────────────────────
# Attach this to a CanvasLayer node called "UI" that you add as a child
# of your Board node.
#
# This script builds all UI elements in code — no need to manually place
# buttons in the editor. Everything is created in _ready().
#
# The UI listens to signals from Board.gd and calls back into it.
#
# Scene structure after you add the CanvasLayer:
#   Board (Node2D)
#   ├── ... your existing nodes ...
#   └── UI (CanvasLayer)  ← attach UI.gd here
# ─────────────────────────────────────────────────────────────────────────

extends CanvasLayer

# ── Reference to Board (set automatically in _ready) ─────────────────────
var board: Node = null

# ── UI element references (built in _ready) ───────────────────────────────
var _panel:           PanelContainer
var _lbl_status:      Label
var _lbl_round:       Label
var _lbl_cache:       Label
var _lbl_human_hand:  Label
var _lbl_ai_hand:     Label
var _lbl_human_board: Label
var _lbl_ai_board:    Label
var _btn_roll:        Button
var _btn_cw:          Button
var _btn_ccw:         Button
var _btn_place:       Button
var _corner_btns:     Array = []   # Array of Button
var _log_label:       Label

# Recent log lines
var _log_lines: Array = []
const MAX_LOG: int = 6


func _ready() -> void:
	# Find the Board node (parent of the CanvasLayer)
	board = get_parent()
	if board == null:
		push_error("UI.gd: Could not find parent Board node.")
		return

	_build_ui()
	_connect_signals()
	_set_initial_state()


# ── Build all UI elements in code ─────────────────────────────────────────
func _build_ui() -> void:
	# ── Right-side panel ──────────────────────────────────────────────────
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.custom_minimum_size = Vector2(220, 0)
	_panel.offset_left  = -220
	_panel.offset_right = 0
	add_child(_panel)

	# Wrap in ScrollContainer so nothing gets cut off
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	margin.add_child(inner)

	# Status label (big, centered)
	_lbl_status = _make_label("Waiting...", 13, true)
	_lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_lbl_status)

	_add_separator(inner)

	# Round / Cache
	_lbl_round = _make_label("Round: 1")
	inner.add_child(_lbl_round)
	_lbl_cache = _make_label("Cache: 64")
	inner.add_child(_lbl_cache)

	_add_separator(inner)

	# Player stats
	inner.add_child(_make_label("YOU", 11, true))
	_lbl_human_hand  = _make_label("  Hand: 0")
	_lbl_human_board = _make_label("  Board: 0 / 16")
	inner.add_child(_lbl_human_hand)
	inner.add_child(_lbl_human_board)

	inner.add_child(_make_label("AI", 11, true))
	_lbl_ai_hand  = _make_label("  Hand: 0")
	_lbl_ai_board = _make_label("  Board: 0 / 16")
	inner.add_child(_lbl_ai_hand)
	inner.add_child(_lbl_ai_board)

	_add_separator(inner)

	# ── Corner selection buttons (shown only during setup) ────────────────
	var corner_lbl := _make_label("Choose your starting corner:", 12, false)
	corner_lbl.name = "CornerLabel"
	corner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(corner_lbl)

	var corner_names: Dictionary = {
		0:  "Top-Left (TL)",
		9:  "Top-Right (TR)",
		18: "Bottom-Right (BR)",
		27: "Bottom-Left (BL)",
	}
	for corner_idx in [0, 9, 18, 27]:
		var btn := Button.new()
		btn.text = corner_names[corner_idx]
		btn.name = "CornerBtn_%d" % corner_idx
		# Capture corner_idx in the lambda
		var ci: int = corner_idx
		btn.pressed.connect(func(): board.human_chose_corner(ci))
		inner.add_child(btn)
		_corner_btns.append(btn)

	_add_separator(inner)

	# ── Direction buttons ─────────────────────────────────────────────────
	var dir_hbox := HBoxContainer.new()
	dir_hbox.name = "DirButtons"
	inner.add_child(dir_hbox)

	_btn_cw = Button.new()
	_btn_cw.text = "↻ Clockwise"
	_btn_cw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cw.pressed.connect(func(): board.human_chose_direction("cw"))
	dir_hbox.add_child(_btn_cw)

	_btn_ccw = Button.new()
	_btn_ccw.text = "↺ Counter"
	_btn_ccw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_ccw.pressed.connect(func(): board.human_chose_direction("ccw"))
	dir_hbox.add_child(_btn_ccw)

	# ── Roll button ───────────────────────────────────────────────────────
	_btn_roll = Button.new()
	_btn_roll.text = "🎲 Roll Dice"
	_btn_roll.pressed.connect(func(): board.human_roll_dice())
	inner.add_child(_btn_roll)

	# ── Manual place stone button ─────────────────────────────────────────
	_btn_place = Button.new()
	_btn_place.text = "📥 Place Stone from Hand"
	_btn_place.pressed.connect(func(): board.human_place_stone_manually())
	_btn_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_btn_place)

	_add_separator(inner)

	# ── Log ───────────────────────────────────────────────────────────────
	inner.add_child(_make_label("Log:", 11, true))
	_log_label = _make_label("", 11, false)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_log_label)


# ── Signal connections ────────────────────────────────────────────────────
func _connect_signals() -> void:
	board.state_updated.connect(_on_state_updated)
	board.human_turn_started.connect(_on_human_turn_started)
	board.roll_result.connect(_on_roll_result)
	board.action_resolved.connect(_on_action_resolved)
	board.game_over.connect(_on_game_over)
	board.request_corner_choice.connect(_on_request_corner_choice)
	board.request_direction_choice.connect(_on_request_direction_choice)


# ── Initial visibility state ──────────────────────────────────────────────
func _set_initial_state() -> void:
	_btn_roll.visible  = false
	_btn_cw.visible    = false
	_btn_ccw.visible   = false
	_btn_place.visible = false
	# Corner buttons visible (setup phase)
	_set_corner_buttons_visible(true)


# ── Signal handlers ───────────────────────────────────────────────────────

func _on_state_updated(state: GameState) -> void:
	_lbl_round.text       = "Round: %d" % state.round_number
	_lbl_cache.text       = "Cache: %d" % state.cache
	_lbl_human_hand.text  = "  Hand: %d" % state.human_hand
	_lbl_human_board.text = "  Board: %d / 16" % state.stones_on_board(false)
	_lbl_ai_hand.text     = "  Hand: %d" % state.ai_hand
	_lbl_ai_board.text    = "  Board: %d / 16" % state.stones_on_board(true)

	# Show place button only when human has stones in hand on their turn
	_btn_place.visible = (
		state.human_hand > 0
		and board.current_phase == board.Phase.HUMAN_ROLL
	)


func _on_human_turn_started(round_num: int, can_choose_direction: bool) -> void:
	_lbl_status.text   = "Your turn! Roll the dice."
	_btn_roll.visible  = true
	_btn_cw.visible    = can_choose_direction
	_btn_ccw.visible   = can_choose_direction
	_btn_place.visible = (board.state.human_hand > 0)


func _on_roll_result(player: String, roll: int, _space: Dictionary) -> void:
	var who: String = "You" if player == "human" else "AI"
	_add_log("%s rolled %d" % [who, roll])
	if player == "human":
		_btn_roll.visible = false


func _on_action_resolved(player: String, message: String) -> void:
	_lbl_status.text = message
	_add_log(message)

	# Hide direction buttons after a move resolves
	if player == "human":
		_btn_cw.visible  = false
		_btn_ccw.visible = false


func _on_game_over(winner: String) -> void:
	_btn_roll.visible  = false
	_btn_cw.visible    = false
	_btn_ccw.visible   = false
	_btn_place.visible = false
	_set_corner_buttons_visible(false)
	if winner == "human":
		_lbl_status.text = "🎉 YOU WIN!\nYou filled the board first!"
	else:
		_lbl_status.text = "🤖 AI WINS!\nBetter luck next time."


func _on_request_corner_choice(_corners: Array) -> void:
	_lbl_status.text = "Choose your starting corner!"
	_set_corner_buttons_visible(true)
	_btn_roll.visible = false


func _on_request_direction_choice() -> void:
	_lbl_status.text  = "Choose direction, then confirm."
	_btn_cw.visible   = true
	_btn_ccw.visible  = true
	_btn_roll.visible = false
	# Show a confirm button by repurposing roll button
	_btn_roll.text    = "✅ Confirm Direction"
	_btn_roll.visible = true


# ── Helpers ───────────────────────────────────────────────────────────────

func _set_corner_buttons_visible(visible_: bool) -> void:
	for btn in _corner_btns:
		btn.visible = visible_
	# Also hide/show the corner label
	var lbl = _panel.find_child("CornerLabel", true, false)
	if lbl: lbl.visible = visible_


func _add_log(line: String) -> void:
	# Trim to keep log short
	if line.strip_edges() == "": return
	_log_lines.append(line)
	if _log_lines.size() > MAX_LOG:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG)
	_log_label.text = "\n".join(_log_lines)


func _make_label(text: String, font_size: int = 12, bold: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if font_size != 12 or bold:
		var settings := LabelSettings.new()
		settings.font_size = font_size
		lbl.label_settings = settings
	return lbl


func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
