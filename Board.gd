# Board.gd  (Phase 2 — full replacement)
# ─────────────────────────────────────────────────────────────────────────
# Attach to your root Board node.
#
# Changes from Phase 1:
#   - Token movement now calls TokenMover for smooth animation
#   - await is used so UI waits for movement to finish before resolving action
#   - Direction choice properly updates before resolving move
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
signal token_move(player: String, from_pos: Vector2, to_pos: Vector2)


# ── Inspector exports ─────────────────────────────────────────────────────
@export var trackpoints_node: Node2D
@export var player1_node:     Node2D   # human token
@export var player2_node:     Node2D   # AI token


# Each corner's forced direction for Round 1 (follows the arrow printed on that corner)
const CORNER_FIRST_DIR: Dictionary = {
	0:  "cw",   # TL → move right along top edge
	9:  "cw",   # TR → move down along right edge
	18: "ccw",  # BR → move left along bottom edge
	27: "ccw",  # BL → move up along left edge
}

# ── Internal ──────────────────────────────────────────────────────────────
var state: GameState = null
var track_positions: Array = []

enum Phase {
	SETUP_CORNER_CHOICE,
	SETUP_FIRST_ROLL,
	HUMAN_ROLL,
	HUMAN_CHOOSE_DIRECTION,
	HUMAN_ACTION_PENDING,
	AI_TURN,
	GAME_OVER,
}
var current_phase: Phase = Phase.SETUP_CORNER_CHOICE

var human_chosen_direction: String = "cw"
var _pending_roll: int = 0
var _human_setup_roll: int = 0
var _ai_setup_roll:    int = 0

# TokenMover components — added dynamically if not already on the token nodes
var _human_mover: TokenMover = null
var _ai_mover:    TokenMover = null


# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_track_positions()
	_setup_movers()
	state = GameState.new()
	_begin_setup()


func _load_track_positions() -> void:
	track_positions.clear()
	if trackpoints_node == null:
		push_error("Board.gd: trackpoints_node is not assigned!")
		return
	for i in range(1, GameState.TRACK_LEN + 1):
		var node = trackpoints_node.get_node_or_null("spc%d" % i)
		if node == null:
			push_error("Board.gd: missing trackpoint spc%d" % i)
			track_positions.append(Vector2.ZERO)
		else:
			track_positions.append(node.global_position)
	print("Board.gd: Loaded %d track positions." % track_positions.size())


func _setup_movers() -> void:
	# Add TokenMover script to each player node if not already present
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


# ── Setup ─────────────────────────────────────────────────────────────────

func _begin_setup() -> void:
	current_phase = Phase.SETUP_CORNER_CHOICE
	emit_signal("request_corner_choice", GameState.ALL_CORNERS)


func human_chose_corner(corner_idx: int) -> void:
	if current_phase != Phase.SETUP_CORNER_CHOICE: return

	state.human_start_corner = corner_idx
	state.human_pos          = corner_idx

	# AI takes the diagonally opposite corner
	state.ai_start_corner = GameState.OPPOSITE_CORNER[corner_idx]
	state.ai_pos          = state.ai_start_corner

	# Snap tokens to starting positions immediately
	if _human_mover:
		_human_mover.snap_to(get_track_pos(state.human_pos))
	if _ai_mover:
		_ai_mover.snap_to(get_track_pos(state.ai_pos))

	emit_signal("state_updated", state)
	emit_signal("action_resolved", "system",
		"You chose corner %s. AI starts at %s." % [
			GameState.TRACK[corner_idx]["label"],
			GameState.TRACK[state.ai_start_corner]["label"]
		])

	await get_tree().create_timer(0.6).timeout
	_do_setup_roll()


func _do_setup_roll() -> void:
	current_phase      = Phase.SETUP_FIRST_ROLL
	_human_setup_roll  = randi_range(1, 6)
	_ai_setup_roll     = randi_range(1, 6)

	if _human_setup_roll == _ai_setup_roll:
		emit_signal("action_resolved", "system",
			"Tie! Both rolled %d — rolling again..." % _human_setup_roll)
		await get_tree().create_timer(0.9).timeout
		_do_setup_roll()
		return

	var human_first: bool = _human_setup_roll > _ai_setup_roll
	emit_signal("action_resolved", "system",
		"You rolled %d, AI rolled %d — %s goes first!" % [
			_human_setup_roll, _ai_setup_roll,
			"You" if human_first else "AI"
		])

	await get_tree().create_timer(1.1).timeout

	if human_first:
		_start_human_turn()
	else:
		_start_ai_turn()


# ── Human turn ────────────────────────────────────────────────────────────

func _start_human_turn() -> void:
	current_phase = Phase.HUMAN_ROLL
	emit_signal("human_turn_started", state.round_number, state.human_first_done)


func human_roll_dice() -> void:
	if current_phase != Phase.HUMAN_ROLL: return

	var roll: int = randi_range(1, 6)
	emit_signal("roll_result", "human", roll, {})

	if state.human_first_done:
		# Round 2+: wait for direction choice
		_pending_roll = roll
		current_phase = Phase.HUMAN_CHOOSE_DIRECTION
		emit_signal("request_direction_choice")
	else:
		# Round 1: direction is forced by the arrow on the chosen corner
		await _resolve_human_move(roll, CORNER_FIRST_DIR[state.human_start_corner])


func human_chose_direction(direction: String) -> void:
	if current_phase != Phase.HUMAN_CHOOSE_DIRECTION: return
	human_chosen_direction = direction
	await _resolve_human_move(_pending_roll, direction)


func _resolve_human_move(roll: int, direction: String) -> void:
	current_phase = Phase.HUMAN_ACTION_PENDING

	var old_pos: int = state.human_pos
	var new_pos: int = state.move_pos(state.human_pos, roll, direction)
	state.human_pos  = new_pos

	# Animate the token
	if _human_mover:
		await _human_mover.move_along_track(
			old_pos, new_pos, direction, track_positions, GameState.TRACK_LEN)

	# Resolve space action
	var msg: String = ActionResolver.apply_action(state, false)
	emit_signal("action_resolved", "human", msg)
	emit_signal("state_updated", state)

	var winner: String = state.check_winner()
	if winner != "":
		current_phase = Phase.GAME_OVER
		emit_signal("game_over", winner)
		return

	state.human_first_done = true
	state.round_number    += 1

	await get_tree().create_timer(0.4).timeout
	_start_ai_turn()


# ── AI turn ───────────────────────────────────────────────────────────────

func _start_ai_turn() -> void:
	current_phase = Phase.AI_TURN
	emit_signal("action_resolved", "system", "AI is thinking...")
	await get_tree().create_timer(0.8).timeout

	var roll: int = randi_range(1, 6)
	emit_signal("roll_result", "ai", roll, {})

	# Phase 5 will replace the round 2+ direction with AIAgent.best_move(state, roll)
	# Round 1: AI follows its corner's forced direction. Round 2+: clockwise for now.
	var direction: String = CORNER_FIRST_DIR[state.ai_start_corner] if not state.ai_first_done else "cw"

	var old_pos: int = state.ai_pos
	var new_pos: int = state.move_pos(state.ai_pos, roll, direction)
	state.ai_pos     = new_pos

	if _ai_mover:
		await _ai_mover.move_along_track(
			old_pos, new_pos, direction, track_positions, GameState.TRACK_LEN)

	var msg: String = ActionResolver.apply_action(state, true)
	emit_signal("action_resolved", "ai", msg)
	emit_signal("state_updated", state)

	var winner: String = state.check_winner()
	if winner != "":
		current_phase = Phase.GAME_OVER
		emit_signal("game_over", winner)
		return

	state.ai_first_done = true
	state.round_number  += 1

	await get_tree().create_timer(0.3).timeout
	_start_human_turn()


# ── Manual stone placement ────────────────────────────────────────────────

func human_place_stone_manually() -> void:
	if current_phase != Phase.HUMAN_ROLL: return
	if state.human_hand <= 0:
		emit_signal("action_resolved", "human", "No stones in hand to place.")
		return
	var placed: int = state.place_stones(false, 1)
	if placed > 0:
		emit_signal("action_resolved", "human", "You placed 1 stone on your board.")
		emit_signal("state_updated", state)
	var winner: String = state.check_winner()
	if winner != "":
		current_phase = Phase.GAME_OVER
		emit_signal("game_over", winner)
