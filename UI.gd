# UI.gd  (Redesigned — matches teammate's mockup)
# ─────────────────────────────────────────────────────────────────────────
# Layout:
#   Left panel  — YOUR PIECES + OPPONENT stats cards
#   Center top  — Round label
#   Right panel — Cache count + dice + roll/direction buttons
#   Bottom bar  — Status message
#   Top-right   — Quit + Restart icon buttons
#
# Designer notes:
#   - Set _bg_panel_texture, _btn_roll_texture etc. in Inspector
#     to skin buttons/panels with images
#   - All dynamic numbers are Labels updated via signals
#   - Keyboard: Left/Right arrows = CW/CCW, Space/Enter = Roll
# ─────────────────────────────────────────────────────────────────────────

extends CanvasLayer

# ── Texture exports — drag images from FileSystem into these ──────────────
@export var panel_texture:       Texture2D   ## background for stat cards
@export var btn_roll_texture:    Texture2D   ## Roll button background
@export var btn_dir_texture:     Texture2D   ## CW/CCW button background
@export var btn_quit_texture:    Texture2D   ## Quit icon (top-right)
@export var btn_restart_texture: Texture2D   ## Restart icon (top-right)
@export var cache_bowl_texture:  Texture2D   ## Bowl image above cache count
@export var dice_texture:        Texture2D   ## Dice background image

# ── Internal references ───────────────────────────────────────────────────
var board: Node = null

# Left panel — player stats
var _lbl_human_hand:  Label
var _lbl_human_board: Label
var _lbl_ai_hand:     Label
var _lbl_ai_board:    Label

# Center top
var _lbl_round: Label

# Right panel
var _lbl_cache:  Label
var _lbl_dice:   Label   # animated dice face
var _btn_roll:   Button
var _btn_cw:     Button
var _btn_ccw:    Button

# Bottom bar
var _lbl_status: Label

# Corner selection (setup only)
var _corner_container: VBoxContainer
var _corner_btns: Array = []

# Win overlay
var _win_overlay:  ColorRect
var _win_title:    Label
var _win_sub:      Label
var _btn_restart_win: Button

# Dice animation
var _dice_faces: Array = ["⚀","⚁","⚂","⚃","⚄","⚅"]


func _ready() -> void:
	board = get_parent()
	if not board:
		push_error("UI.gd: no parent Board found")
		return
	_build_ui()
	_connect_signals()
	_set_initial_visibility()


# ── BUILD UI ──────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_build_left_panel(root)
	_build_top_bar(root)
	_build_right_panel(root)
	_build_bottom_bar(root)
	_build_top_right_buttons(root)
	_build_corner_chooser(root)
	_build_win_overlay(root)


# ── LEFT PANEL — YOUR PIECES + OPPONENT ───────────────────────────────────
func _build_left_panel(root: Control) -> void:
	var panel := _make_panel(root, Vector2(0,0), Vector2(170, 1.0), true)
	panel.offset_right = 0

	var vbox := _make_vbox(panel, 12)

	# YOUR PIECES card
	var your_card := _make_card(vbox, "YOUR PIECES")
	var you_row := _make_hbox(your_card)
	_make_dot(you_row, Color(0.85, 0.25, 0.2))
	_make_bold_label(you_row, "YOU")
	_lbl_human_hand  = _make_stat_row(your_card, "In Hand",  "0")
	_lbl_human_board = _make_stat_row(your_card, "On Board", "0 / 16")
	_make_progress_bar(your_card, Color(0.85, 0.25, 0.2), "human")

	# OPPONENT card
	var opp_card := _make_card(vbox, "OPPONENT")
	var ai_row := _make_hbox(opp_card)
	_make_dot(ai_row, Color(0.2, 0.45, 0.85))
	_make_bold_label(ai_row, "AI")
	_lbl_ai_hand  = _make_stat_row(opp_card, "In Hand",  "0")
	_lbl_ai_board = _make_stat_row(opp_card, "On Board", "0 / 16")
	_make_progress_bar(opp_card, Color(0.2, 0.45, 0.85), "ai")


# ── TOP BAR — Round number ─────────────────────────────────────────────────
func _build_top_bar(root: Control) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.55, 0.35, 0.1, 0.85)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 36)
	root.add_child(bar)

	_lbl_round = Label.new()
	_lbl_round.text = "Round 1"
	_lbl_round.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_round.offset_top  = 6
	_lbl_round.offset_left = -60
	_lbl_round.offset_right = 60
	var rs := LabelSettings.new()
	rs.font_size  = 16
	rs.font_color = Color(1, 0.95, 0.8)
	_lbl_round.label_settings = rs
	_lbl_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_lbl_round)


# ── RIGHT PANEL — Cache + Dice + Buttons ──────────────────────────────────
func _build_right_panel(root: Control) -> void:
	var panel := _make_panel(root, Vector2(1.0, 0), Vector2(0, 1.0), true)
	panel.offset_left  = -190
	panel.offset_right = 0

	var vbox := _make_vbox(panel, 10)

	# Cache section
	_make_section_label(vbox, "CACHE OF STONES")

	# Optional bowl image
	if cache_bowl_texture:
		var img := TextureRect.new()
		img.texture = cache_bowl_texture
		img.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		img.custom_minimum_size = Vector2(0, 60)
		vbox.add_child(img)

	_lbl_cache = Label.new()
	_lbl_cache.text = "64"
	var cs := LabelSettings.new()
	cs.font_size  = 36
	cs.font_color = Color(0.3, 0.15, 0.0)
	_lbl_cache.label_settings = cs
	_lbl_cache.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_lbl_cache)
	_make_muted_label(vbox, "STONES AVAILABLE")

	vbox.add_child(HSeparator.new())

	# Dice section
	_make_section_label(vbox, "ROLL THE DICE")

	# Dice face display
	var dice_wrap := CenterContainer.new()
	vbox.add_child(dice_wrap)
	_lbl_dice = Label.new()
	_lbl_dice.text = "⚄"
	var ds := LabelSettings.new()
	ds.font_size = 52
	_lbl_dice.label_settings = ds
	dice_wrap.add_child(_lbl_dice)

	# "Click to roll" hint
	_make_muted_label(vbox, "Click to\nroll")

	# Roll button
	_btn_roll = _make_button(vbox, "↻ Clockwise")   # text set dynamically
	_btn_roll.text = "🎲  Roll"
	_btn_roll.pressed.connect(func(): board.human_roll_dice())
	if btn_roll_texture:
		_btn_roll.icon = btn_roll_texture

	# Direction buttons side by side
	var dir_hbox := HBoxContainer.new()
	dir_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(dir_hbox)

	_btn_cw = _make_button(dir_hbox, "↻ Clockwise")
	_btn_cw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cw.pressed.connect(func(): board.human_chose_direction("cw"))
	if btn_dir_texture: _btn_cw.icon = btn_dir_texture

	_btn_ccw = _make_button(dir_hbox, "↺ Counter")
	_btn_ccw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_ccw.pressed.connect(func(): board.human_chose_direction("ccw"))
	if btn_dir_texture: _btn_ccw.icon = btn_dir_texture

	vbox.add_child(HSeparator.new())
	_make_muted_label(vbox, "Tip: C=Clockwise  W=Counter\nSpace or Enter to Roll")


# ── BOTTOM BAR — Status message ───────────────────────────────────────────
func _build_bottom_bar(root: Control) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.45, 0.28, 0.05, 0.9)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.custom_minimum_size = Vector2(0, 38)
	bar.offset_top = -38
	root.add_child(bar)

	_lbl_status = Label.new()
	_lbl_status.text = "Choose your starting corner!"
	_lbl_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl_status.offset_top    = -34
	_lbl_status.offset_bottom = 0
	var ss := LabelSettings.new()
	ss.font_size  = 14
	ss.font_color = Color(1, 0.95, 0.8)
	_lbl_status.label_settings = ss
	_lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_status.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	root.add_child(_lbl_status)


# ── TOP-RIGHT — Quit + Restart ────────────────────────────────────────────
func _build_top_right_buttons(root: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.offset_left   = -100
	hbox.offset_top    = 4
	hbox.offset_right  = -4
	hbox.offset_bottom = 36
	root.add_child(hbox)

	# Restart
	var btn_r := _make_icon_btn(btn_restart_texture, "↺")
	btn_r.pressed.connect(func(): get_tree().reload_current_scene())
	hbox.add_child(btn_r)

	# Quit
	var btn_q := _make_icon_btn(btn_quit_texture, "✕")
	btn_q.pressed.connect(func(): get_tree().quit())
	hbox.add_child(btn_q)


# ── CORNER CHOOSER — setup phase only ────────────────────────────────────
func _build_corner_chooser(root: Control) -> void:
	_corner_container = VBoxContainer.new()
	_corner_container.set_anchors_preset(Control.PRESET_CENTER)
	_corner_container.offset_left   = -120
	_corner_container.offset_right  =  120
	_corner_container.offset_top    = -110
	_corner_container.offset_bottom =  110
	_corner_container.add_theme_constant_override("separation", 8)
	root.add_child(_corner_container)

	var title := Label.new()
	title.text = "Choose your starting corner"
	var ts := LabelSettings.new()
	ts.font_size = 14
	title.label_settings = ts
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_corner_container.add_child(title)

	var corner_names := {0:"Top-Left (SAFE)", 9:"Top-Right (TAKE)",
						 18:"Bottom-Right (SAFE)", 27:"Bottom-Left (TAKE)"}
	for ci in [0, 9, 18, 27]:
		var btn := Button.new()
		btn.text = corner_names[ci]
		btn.custom_minimum_size = Vector2(220, 36)
		var idx: int = ci
		btn.pressed.connect(func(): _on_corner_picked(idx))
		_corner_container.add_child(btn)
		_corner_btns.append(btn)


# ── WIN OVERLAY ───────────────────────────────────────────────────────────
func _build_win_overlay(root: Control) -> void:
	_win_overlay = ColorRect.new()
	_win_overlay.color = Color(0, 0, 0, 0.72)
	_win_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_overlay.visible = false
	root.add_child(_win_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(340, 0)
	center.add_child(vbox)

	_win_title = Label.new()
	_win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wts := LabelSettings.new()
	wts.font_size = 38
	_win_title.label_settings = wts
	vbox.add_child(_win_title)

	_win_sub = Label.new()
	_win_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_win_sub)

	_btn_restart_win = Button.new()
	_btn_restart_win.text = "↺  Play Again"
	_btn_restart_win.custom_minimum_size = Vector2(180, 48)
	_btn_restart_win.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(_btn_restart_win)


# ── SIGNALS ───────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	board.state_updated.connect(_on_state_updated)
	board.human_turn_started.connect(_on_human_turn_started)
	board.roll_result.connect(_on_roll_result)
	board.action_resolved.connect(_on_action_resolved)
	board.game_over.connect(_on_game_over)
	board.request_corner_choice.connect(_on_request_corner_choice)
	board.request_direction_choice.connect(_on_request_direction_choice)
	AIAgent.ai_debug.connect(func(msg): _lbl_status.text = msg)


func _set_initial_visibility() -> void:
	_btn_roll.visible = false
	_btn_cw.visible   = false
	_btn_ccw.visible  = false


# ── SIGNAL HANDLERS ───────────────────────────────────────────────────────

func _on_state_updated(state: GameState) -> void:
	_lbl_round.text       = "Round %d" % state.round_number
	_lbl_cache.text       = str(state.cache)
	_lbl_human_hand.text  = str(state.human_hand)
	_lbl_human_board.text = "%d / 16" % state.stones_on_board(false)
	_lbl_ai_hand.text     = str(state.ai_hand)
	_lbl_ai_board.text    = "%d / 16" % state.stones_on_board(true)
	# Hide corners once game starts
	if state.human_pos >= 0:
		_corner_container.visible = false


func _on_human_turn_started(_round_num: int, can_choose: bool) -> void:
	_lbl_status.text  = "Your turn! Roll the dice."
	_btn_roll.visible = true
	_btn_cw.visible   = can_choose
	_btn_ccw.visible  = can_choose


func _on_roll_result(player: String, roll: int, _s: Dictionary) -> void:
	_animate_dice(roll)
	if player == "human":
		_btn_roll.visible = false
		_btn_cw.visible   = false
		_btn_ccw.visible  = false


func _on_action_resolved(_player: String, message: String) -> void:
	_lbl_status.text = message


func _on_game_over(winner: String) -> void:
	_btn_roll.visible = false
	_btn_cw.visible   = false
	_btn_ccw.visible  = false
	if winner == "human":
		_win_title.text = "🎉  YOU WIN!"
		_win_title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		_win_sub.text   = "You filled your board first!"
	else:
		_win_title.text = "🤖  AI WINS!"
		_win_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		_win_sub.text   = "The AI filled its board first.\nBetter luck next time!"
	_win_overlay.visible = true


func _on_request_corner_choice(_c: Array) -> void:
	_corner_container.visible = true
	_lbl_status.text = "Choose your starting corner!"


func _on_request_direction_choice() -> void:
	_lbl_status.text  = "Pick a direction, then roll!"
	_btn_cw.visible   = true
	_btn_ccw.visible  = true
	_btn_roll.visible = true


func _on_corner_picked(idx: int) -> void:
	_corner_container.visible = false
	board.human_chose_corner(idx)


# ── KEYBOARD INPUT ────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE, KEY_ENTER:
				if _btn_roll.visible:
					board.human_roll_dice()
			KEY_C:
				if _btn_cw.visible:
					board.human_chose_direction("cw")
					_highlight_dir_btn(_btn_cw)
			KEY_W:
				if _btn_ccw.visible:
					board.human_chose_direction("ccw")
					_highlight_dir_btn(_btn_ccw)


func _highlight_dir_btn(btn: Button) -> void:
	# Brief flash to show which was selected
	btn.modulate = Color(1.5, 1.5, 0.5)
	var t := create_tween()
	t.tween_property(btn, "modulate", Color(1,1,1), 0.3)


# ── DICE ANIMATION ────────────────────────────────────────────────────────
func _animate_dice(final_roll: int) -> void:
	var final_face: String = _dice_faces[final_roll - 1]
	var tween := create_tween()
	for i in range(10):
		var face: String = _dice_faces[randi() % 6]
		tween.tween_callback(func(): _lbl_dice.text = face)
		tween.tween_interval(0.05 + i * 0.018)
	tween.tween_callback(func(): _lbl_dice.text = final_face)


# ── WIDGET HELPERS ────────────────────────────────────────────────────────

func _make_panel(parent: Control, anchor_pos: Vector2, anchor_size: Vector2, full_height: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(170, 0)
	if full_height:
		pc.set_anchors_preset(
			Control.PRESET_LEFT_WIDE if anchor_pos.x == 0 else Control.PRESET_RIGHT_WIDE)
	if panel_texture:
		var sb := StyleBoxTexture.new()
		sb.texture = panel_texture
		pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	return pc


func _make_vbox(parent: Control, sep: int = 8) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", sep)
	var m := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(s, 10)
	parent.add_child(m)
	m.add_child(vb)
	return vb


func _make_hbox(parent: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	parent.add_child(hb)
	return hb


func _make_card(parent: Control, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_constant_override("margin_bottom", 6)
	parent.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)
	var m := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(s, 8)
	inner.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)
	_make_section_label(vb, title)
	return vb


func _make_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	var ls := LabelSettings.new()
	ls.font_size  = 10
	ls.font_color = Color(0.5, 0.35, 0.1)
	lbl.label_settings = ls
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)


func _make_bold_label(parent: Control, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	var ls := LabelSettings.new()
	ls.font_size = 13
	lbl.label_settings = ls
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(lbl)
	return lbl


func _make_muted_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	var ls := LabelSettings.new()
	ls.font_size  = 10
	ls.font_color = Color(0.5, 0.5, 0.5)
	lbl.label_settings = ls
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)


func _make_stat_row(parent: Control, label: String, default_val: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	var ls := LabelSettings.new()
	ls.font_size  = 12
	ls.font_color = Color(0.4, 0.3, 0.1)
	lbl.label_settings = ls
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val := Label.new()
	val.text = default_val
	var vs := LabelSettings.new()
	vs.font_size = 12
	val.label_settings = vs
	row.add_child(val)
	return val


func _make_progress_bar(parent: Control, color: Color, _who: String) -> void:
	# Simple thin colored line as visual progress (not functional bar — driven by label)
	var bar := ColorRect.new()
	bar.color = Color(color.r, color.g, color.b, 0.25)
	bar.custom_minimum_size = Vector2(0, 3)
	parent.add_child(bar)


func _make_dot(parent: Control, color: Color) -> void:
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(10, 10)
	# Make it round-ish via min size
	parent.add_child(dot)


func _make_button(parent: Control, text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	parent.add_child(btn)
	return btn


func _make_icon_btn(tex: Texture2D, fallback_text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(36, 28)
	if tex:
		btn.icon = tex
		btn.text = ""
	else:
		btn.text = fallback_text
	return btn
