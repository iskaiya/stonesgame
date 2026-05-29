# Board.gd (Phase 3 — full replacement)
# ─────────────────────────────────────────────────────────────────────────
# Changes from Phase 2:
#   - Added @export var inner_board for InnerBoard node reference
#   - state_updated signal now also calls inner_board.refresh()
#   - CORNER_FIRST_DIR removed (all corners go CW on round 1)
# ─────────────────────────────────────────────────────────────────────────

extends Node2D


# ── Signals ───────────────────────────────────────────────────────────────
signal state_updated(state: GameState)
signal human_turn_started(round_num: int, can_choose_direction: bool)
signal roll_result(player: String, roll: int, landing_space: Dictionary)
signal action_resolved(player: String, message: String)
signal game_over(winner: String)
signal request_corner_choice(available_corners: Array)
signal request_direction_choice()


# ── Inspector exports ─────────────────────────────────────────────────────
@export var trackpoints_node: Node2D
@export var player1_node:     Node2D
@export var player2_node:     Node2D
@export var inner_board:      Node2D   # drag your InnerBoard node here


# ── Internal ──────────────────────────────────────────────────────────────
var state: GameState   = null
var track_positions: Array = []

enum Phase {
	SETUP_CORNER_CHOICE,
	SETUP_FIRST_ROLL,
	HUMAN_ROLL,
	HUMAN_CHOOSE_DIRECTION,
	HUMAN_ACTION_PENDING,
	HUMAN_PLACING,        # waiting for human to click cells to place stones
	AI_TURN,
	GAME_OVER,
}
# How many stones the human still needs to place this turn
var _stones_to_place: int = 0
var current_phase: Phase = Phase.SETUP_CORNER_CHOICE

var human_chosen_direction: String = "cw"
var _pending_roll: int = 0

var _human_mover = null
var _ai_mover    = null


# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_track_positions()
	_setup_movers()
	state = GameState.new()
	# Connect inner board cell clicks
	if inner_board:
		inner_board.cell_clicked.connect(_on_cell_clicked)
	# Connect AI debug signal so scores show in game log
	AIAgent.ai_debug.connect(func(msg: String):
		emit_signal("action_resolved", "ai", msg))
	_begin_setup()


func _load_track_positions() -> void:
	track_positions.clear()
	if trackpoints_node == null:
		push_error("Board.gd: trackpoints_node not assigned!")
		return
	for i in range(1, GameState.TRACK_LEN + 1):
		var node = trackpoints_node.get_node_or_null("spc%d" % i)
		if node == null:
			push_error("Board.gd: missing spc%d" % i)
			track_positions.append(Vector2.ZERO)
		else:
			track_positions.append(node.global_position)
	print("Board.gd: Loaded %d track positions." % track_positions.size())


func _setup_movers() -> void:
	if player1_node:
		if not player1_node.get_script():
			player1_node.set_script(load("res://TokenMover.gd"))
		_human_mover = player1_node
	if player2_node:
		if not player2_node.get_script():
			player2_node.set_script(load("res://TokenMover.gd"))
		_ai_mover = player2_node


func get_track_pos(idx: int) -> Vector2:
	if track_positions.is_empty(): return Vector2.ZERO
	return track_positions[idx % GameState.TRACK_LEN]


func _emit_state() -> void:
	emit_signal("state_updated", state)
	if inner_board:
		inner_board.refresh(state)
		# Enable click-to-place when it's human's turn and they have stones
		inner_board.set_placement_mode(
			(current_phase == Phase.HUMAN_ROLL or current_phase == Phase.HUMAN_PLACING)
			and state.human_hand > 0
		)


# ── Setup ─────────────────────────────────────────────────────────────────

func _begin_setup() -> void:
	current_phase = Phase.SETUP_CORNER_CHOICE
	emit_signal("request_corner_choice", GameState.ALL_CORNERS)


func human_chose_corner(corner_idx: int) -> void:
	if current_phase != Phase.SETUP_CORNER_CHOICE: return

	state.human_start_corner = corner_idx
	state.human_pos          = corner_idx
	state.ai_start_corner    = GameState.OPPOSITE_CORNER[corner_idx]
	state.ai_pos             = state.ai_start_corner

	if _human_mover: _human_mover.snap_to(get_track_pos(state.human_pos))
	if _ai_mover:    _ai_mover.snap_to(get_track_pos(state.ai_pos))

	_emit_state()
	emit_signal("action_resolved", "system",
		"You chose %s. AI starts at %s." % [
			GameState.TRACK[corner_idx]["label"],
			GameState.TRACK[state.ai_start_corner]["label"]
		])

	await get_tree().create_timer(0.6).timeout
	_do_setup_roll()


func _do_setup_roll() -> void:
	current_phase = Phase.SETUP_FIRST_ROLL
	var h: int = randi_range(1, 6)
	var a: int = randi_range(1, 6)

	if h == a:
		emit_signal("action_resolved", "system",
			"Tie! Both rolled %d — rolling again..." % h)
		await get_tree().create_timer(0.9).timeout
		_do_setup_roll()
		return

	emit_signal("action_resolved", "system",
		"You rolled %d, AI rolled %d — %s goes first!" % [h, a, "You" if h > a else "AI"])
	await get_tree().create_timer(1.1).timeout

	if h > a: _start_human_turn()
	else:      _start_ai_turn()


# ── Human turn ────────────────────────────────────────────────────────────

func _start_human_turn() -> void:
	current_phase = Phase.HUMAN_ROLL
	_pending_roll = 0
	emit_signal("human_turn_started", state.round_number, state.human_first_done)
	emit_signal("state_updated", state)


func human_roll_dice() -> void:
	if current_phase != Phase.HUMAN_ROLL: return
	var roll: int = randi_range(1, 6)
	_pending_roll = roll   # set so place button hides immediately
	emit_signal("roll_result", "human", roll, {})
	emit_signal("state_updated", state)  # refresh UI to hide place button

	if state.human_first_done:
		current_phase = Phase.HUMAN_CHOOSE_DIRECTION
		emit_signal("request_direction_choice")
	else:
		await _resolve_human_move(roll, "cw")


func human_chose_direction(direction: String) -> void:
	if current_phase != Phase.HUMAN_CHOOSE_DIRECTION: return
	await _resolve_human_move(_pending_roll, direction)


func _resolve_human_move(roll: int, direction: String) -> void:
	current_phase    = Phase.HUMAN_ACTION_PENDING
	state.human_stones_to_place = 0   # always reset before resolving action
	var old_pos: int = state.human_pos
	var new_pos: int = state.move_pos(state.human_pos, roll, direction)
	state.human_pos  = new_pos

	if _human_mover:
		await _human_mover.move_along_track(
			old_pos, new_pos, direction, track_positions, GameState.TRACK_LEN)

	var msg: String = ActionResolver.apply_action(state, false)
	emit_signal("action_resolved", "human", msg)
	_emit_state()

	var winner: String = state.check_winner()
	if winner != "":
		current_phase = Phase.GAME_OVER
		emit_signal("game_over", winner)
		return

	# Only pause for placing if P1/P2 explicitly set stones_to_place
	if state.human_stones_to_place > 0:
		_start_human_placing()
		return

	state.human_first_done = true
	state.round_number    += 1
	await get_tree().create_timer(0.4).timeout
	_start_ai_turn()


# ── Human placing phase ──────────────────────────────────────────────────

func _start_human_placing() -> void:
	current_phase    = Phase.HUMAN_PLACING
	_stones_to_place = state.human_stones_to_place
	emit_signal("action_resolved", "human",
		"Click a cell to place your stone(s)! (%d remaining)" % _stones_to_place)
	_emit_state()


# Override cell click to handle placing phase too
func _on_cell_clicked(_is_ai: bool, cell_idx: int) -> void:
	# Allow clicks in both HUMAN_ROLL and HUMAN_PLACING phases
	if current_phase != Phase.HUMAN_ROLL and current_phase != Phase.HUMAN_PLACING:
		return
	if state.human_hand <= 0:
		emit_signal("action_resolved", "human", "No stones in hand!")
		return
	var ok: bool = state.place_stone_at(false, cell_idx)
	if ok:
		state.human_stones_to_place -= 1
		_stones_to_place = state.human_stones_to_place
		emit_signal("action_resolved", "human",
			"Stone placed!%s" % (" (%d more to place)" % _stones_to_place if _stones_to_place > 0 else ""))
		_emit_state()
		var winner: String = state.check_winner()
		if winner != "":
			current_phase = Phase.GAME_OVER
			emit_signal("game_over", winner)
			return
		# Done placing when counter hits 0
		if current_phase == Phase.HUMAN_PLACING and state.human_stones_to_place == 0:
			state.human_first_done = true
			state.round_number    += 1
			_start_ai_turn()
	else:
		emit_signal("action_resolved", "human", "That cell is already taken!")


# ── AI turn ───────────────────────────────────────────────────────────────

func _start_ai_turn() -> void:
	current_phase = Phase.AI_TURN
	emit_signal("action_resolved", "system", "AI is thinking...")
	await get_tree().create_timer(1.0).timeout

	var roll: int = randi_range(1, 6)
	emit_signal("roll_result", "ai", roll, {})

	# Round 1: follow corner arrow (CW). Round 2+: use expectiminimax.
	var direction: String = "cw" if not state.ai_first_done else AIAgent.best_move(state, roll)

	var old_pos: int = state.ai_pos
	var new_pos: int = state.move_pos(state.ai_pos, roll, direction)
	state.ai_pos     = new_pos

	if _ai_mover:
		await _ai_mover.move_along_track(
			old_pos, new_pos, direction, track_positions, GameState.TRACK_LEN)

	var msg: String = ActionResolver.apply_action(state, true)
	emit_signal("action_resolved", "ai", msg)
	_emit_state()

	var winner: String = state.check_winner()
	if winner != "":
		current_phase = Phase.GAME_OVER
		emit_signal("game_over", winner)
		return

	state.ai_first_done = true
	state.round_number += 1
	await get_tree().create_timer(0.3).timeout
	_start_human_turn()


# ── Manual stone placement ────────────────────────────────────────────────

func human_place_stone_manually() -> void:
	# Called by Place Stone button - only active during HUMAN_PLACING
	# (button is only visible after landing on P1/P2 anyway)
	if current_phase != Phase.HUMAN_PLACING: return
	# Nothing to do here - player clicks the cell directly
	emit_signal("action_resolved", "human", "Click a cell on your board!")
