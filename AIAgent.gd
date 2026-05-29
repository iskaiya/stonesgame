# AIAgent.gd
# ─────────────────────────────────────────────────────────────────────────
# Expectiminimax AI for the Stones board game.
# Add as AutoLoad: Project → Project Settings → AutoLoad → AIAgent.gd
#
# Algorithm (per project spec):
#   Chance node  — average over 6 equally probable die rolls
#   Max node     — AI picks direction maximising expected score
#   Min node     — opponent assumed to pick direction minimising AI score
#   Depth cutoff — search stops at DEPTH, heuristic evaluates board state
#
# Usage:
#   var direction: String = AIAgent.best_move(state, roll)  # "cw" or "ccw"
# ─────────────────────────────────────────────────────────────────────────

extends Node

const DEPTH: int = 3

# Signal so Board.gd can forward debug info to the UI log
signal ai_debug(message: String)

func _ready() -> void:
	print("=== AIAgent loaded and ready — expectiminimax depth %d ===" % DEPTH)


# ── Public entry point ────────────────────────────────────────────────────

## Returns "cw" or "ccw" — the best direction for the AI given a die roll.
func best_move(state: GameState, roll: int) -> String:
	var best_score: float = -INF
	var best_dir:   String = "cw"
	var label_cw:   String = GameState.TRACK[state.move_pos(state.ai_pos, roll, "cw")]["label"]
	var label_ccw:  String = GameState.TRACK[state.move_pos(state.ai_pos, roll, "ccw")]["label"]
	var score_cw:   float = 0.0
	var score_ccw:  float = 0.0

	for direction in ["cw", "ccw"]:
		var ns: GameState = _sim_move(state, true, roll, direction)
		var score: float  = _expectiminimax(ns, DEPTH - 1, false)
		# Small tiebreak so AI varies on equal scores
		score += randf() * 0.01

		if direction == "cw":
			score_cw = score
		else:
			score_ccw = score

		if score > best_score:
			best_score = score
			best_dir   = direction

	# Print to Godot Output AND emit for UI log
	var msg: String = "AI roll=%d | CW(%s)=%.1f CCW(%s)=%.1f | picks=%s" % [
		roll, label_cw, score_cw, label_ccw, score_ccw, best_dir
	]
	print(msg)
	emit_signal("ai_debug", msg)

	return best_dir


func _score_direction(state: GameState, roll: int, direction: String) -> float:
	var ns: GameState = _sim_move(state, true, roll, direction)
	return _expectiminimax(ns, DEPTH - 1, false)


# ── Expectiminimax ────────────────────────────────────────────────────────

func _expectiminimax(state: GameState, depth: int, is_max: bool) -> float:
	# Terminal conditions
	if depth == 0 or state.check_winner() != "":
		return _heuristic(state)

	var expected: float = 0.0

	for roll in range(1, 7):   # chance node — 6 equally probable outcomes
		if is_max:
			# MAX node — AI picks best direction
			var best: float = -INF
			for direction in ["cw", "ccw"]:
				var ns: GameState = _sim_move(state, true, roll, direction)
				var val: float    = _expectiminimax(ns, depth - 1, false)
				if val > best:
					best = val
			expected += (1.0 / 6.0) * best

		else:
			# MIN node — opponent picks worst direction for AI
			var worst: float = INF
			for direction in ["cw", "ccw"]:
				var ns: GameState = _sim_move(state, false, roll, direction)
				var val: float    = _expectiminimax(ns, depth - 1, true)
				if val < worst:
					worst = val
			expected += (1.0 / 6.0) * worst

	return expected


# ── Heuristic evaluation ──────────────────────────────────────────────────
# Matches the project spec exactly.
# Positive score = good for AI, negative = good for human.

func _heuristic(state: GameState) -> float:
	var score: float = 0.0

	var ai_on_board:  int = state.stones_on_board(true)
	var hum_on_board: int = state.stones_on_board(false)

	# ── OFFENSE ───────────────────────────────────────────────────────────
	score += 12.0 * ai_on_board          # stones placed on board
	score +=  4.0 * state.ai_hand        # stones in hand (positive — ready to place)

	# ── DEFENSE ───────────────────────────────────────────────────────────
	score -= 12.0 * hum_on_board         # opponent stones on board (bad for AI)
	score -=  3.0 * state.human_hand     # opponent stones in hand

	# ── LOCKED ROWS ───────────────────────────────────────────────────────
	score += 22.0 * state.count_locked_rows(true)   # AI locked rows = very safe
	score -= 20.0 * state.count_locked_rows(false)  # opponent locked rows = threat

	# ── SAFETY ────────────────────────────────────────────────────────────
	var ai_space:  Dictionary = state.space_at(state.ai_pos)
	var hum_space: Dictionary = state.space_at(state.human_pos)
	if ai_space["type"]  == "safe": score += 10.0
	if hum_space["type"] == "safe": score -= 10.0

	# ── WIN PROXIMITY — 6 * (16 - emptySquares) ───────────────────────────
	var ai_empty:  int = 16 - ai_on_board
	var hum_empty: int = 16 - hum_on_board
	score += 6.0 * (16 - ai_empty)   # = 6 * stonesOnBoard (closer to win)

	# ── DIRECTION BONUS ───────────────────────────────────────────────────
	# Reward landing on good spaces: +1/+2 and P1/P2 are valuable
	# Penalise landing on -1/-2
	score += _direction_bonus(state)

	# ── POWER SPACE proximity + threat ────────────────────────────────────
	score += _power_proximity(state)
	score += _power_threat(state)

	# ── TERMINAL ──────────────────────────────────────────────────────────
	if ai_on_board  >= 16: score += 5000.0
	if hum_on_board >= 16: score -= 5000.0

	return score


## Bonus for the space the AI is currently on — rewards good spaces.
func _direction_bonus(state: GameState) -> float:
	var space: Dictionary = state.space_at(state.ai_pos)
	match space["type"]:
		"plus":
			return 4.0 if space["label"] == "+2" else 2.0
		"place":
			return 5.0 if space["label"] == "P2" else 3.0
		"minus":
			return -3.0 if space["label"] == "-2" else -1.5
		"remove":
			# R1 is good if opponent has unprotected stones
			var opp_board: int = state.stones_on_board(false)
			return 4.0 if opp_board > 0 else 0.0
		"power":
			return 8.0   # landing on POWER is very valuable
		"take":
			var opp_board: int = state.stones_on_board(false)
			return 6.0 if opp_board > 0 else 0.0
		_:
			return 0.0


## Bonus for being close to the POWER space.
func _power_proximity(state: GameState) -> float:
	var pwr_idx: int = _power_index()
	var dist: int = min(
		(pwr_idx - state.ai_pos + GameState.TRACK_LEN) % GameState.TRACK_LEN,
		(state.ai_pos - pwr_idx + GameState.TRACK_LEN) % GameState.TRACK_LEN
	)
	# Closer = higher bonus, max 6 points
	return max(0.0, 6.0 - dist)


## Bonus when opponent is vulnerable to POWER (has stones on board).
func _power_threat(state: GameState) -> float:
	var opp_stones: int = state.stones_on_board(false)
	if opp_stones <= 0: return 0.0
	# More opponent stones = bigger threat value of reaching POWER
	var pwr_idx: int = _power_index()
	var dist: int = min(
		(pwr_idx - state.ai_pos + GameState.TRACK_LEN) % GameState.TRACK_LEN,
		(state.ai_pos - pwr_idx + GameState.TRACK_LEN) % GameState.TRACK_LEN
	)
	# Close to power + opponent has stones = high threat bonus
	return float(opp_stones) * max(0.0, (6.0 - dist) / 6.0) * 5.0


# ── Simulation helpers ────────────────────────────────────────────────────

## Clone state, move player, apply action. Never touches real game state.
func _sim_move(state: GameState, is_ai: bool, roll: int, direction: String) -> GameState:
	var ns: GameState = state.clone()
	if is_ai:
		ns.ai_pos = ns.move_pos(ns.ai_pos, roll, direction)
		# AI auto-places during simulation (no human input possible)
		_sim_apply(ns, true)
	else:
		ns.human_pos = ns.move_pos(ns.human_pos, roll, direction)
		_sim_apply(ns, false)
	return ns


## Simplified action resolver for simulation (no signals, no UI).
func _sim_apply(ns: GameState, is_ai: bool) -> void:
	var pos:   int        = ns.ai_pos    if is_ai else ns.human_pos
	var space: Dictionary = ns.space_at(pos)
	var stype: String     = space["type"]
	var label: String     = space["label"]

	match stype:
		"plus":
			var n: int = 1 if label == "+1" else 2
			var take: int = mini(n, ns.cache)
			if is_ai: ns.ai_hand    += take
			else:     ns.human_hand += take
			ns.cache -= take

		"minus":
			var n: int = 1 if label == "-1" else 2
			if is_ai:
				var give: int = mini(n, ns.ai_hand)
				ns.ai_hand   -= give
				ns.cache     += give
			else:
				var give: int = mini(n, ns.human_hand)
				ns.human_hand -= give
				ns.cache      += give

		"place":
			var n: int = 1 if label == "P1" else 2
			# Smart placement: pick cells that best contribute to locked rows
			for _i in range(n):
				_smart_place(ns, is_ai)

		"remove":
			var opp_is_ai: bool  = not is_ai
			var opp_pos: int     = ns.human_pos if is_ai else ns.ai_pos
			var opp_safe: bool   = ns.space_at(opp_pos)["type"] == "safe"
			var opp_locked: Dictionary = ns.locked_set(opp_is_ai)
			var opp_board: Array = ns.ai_board if opp_is_ai else ns.human_board
			if not opp_safe:
				for i in range(15, -1, -1):
					if opp_board[i] > 0 and not opp_locked.has(i):
						opp_board[i] = 0
						ns.cache    += 1
						break

		"power":
			var opp_is_ai: bool  = not is_ai
			var opp_board: Array = ns.ai_board if opp_is_ai else ns.human_board
			for i in range(15, -1, -1):
				if opp_board[i] > 0:
					opp_board[i] = 0
					ns.place_stones(is_ai, 1)
					break

		"take":
			var opp_is_ai: bool  = not is_ai
			var opp_pos: int     = ns.human_pos if is_ai else ns.ai_pos
			var opp_safe: bool   = ns.space_at(opp_pos)["type"] == "safe"
			var opp_board: Array = ns.ai_board if opp_is_ai else ns.human_board
			if not opp_safe:
				for i in range(15, -1, -1):
					if opp_board[i] > 0:
						opp_board[i] = 0
						if is_ai: ns.ai_hand    += 1
						else:     ns.human_hand += 1
						break

		"safe", _:
			pass  # no effect in simulation


# ── Smart stone placement ────────────────────────────────────────────────
## Places one stone in the cell that maximises locked-row potential.
## Tries to complete existing partial lines first.
func _smart_place(ns: GameState, is_ai: bool) -> void:
	var hand: int = ns.ai_hand if is_ai else ns.human_hand
	if hand <= 0: return
	var board: Array = (ns.ai_board if is_ai else ns.human_board).duplicate()

	var best_idx:   int   = -1
	var best_score: float = -INF

	for i in range(16):
		if board[i] != 0: continue
		# Try placing here and score the result
		board[i] = 1
		var score: float = _score_placement(board)
		board[i] = 0
		if score > best_score:
			best_score = score
			best_idx   = i

	if best_idx < 0:
		# Fallback: first empty cell
		for i in range(16):
			if board[i] == 0: best_idx = i; break

	if best_idx >= 0:
		board[best_idx] = 1
		if is_ai:
			ns.ai_board = board
			ns.ai_hand -= 1
		else:
			ns.human_board = board
			ns.human_hand -= 1


## Score a board layout based on partial line completion.
func _score_placement(board: Array) -> float:
	var score: float = 0.0
	var lines: Array = [
		[0,1,2,3],[4,5,6,7],[8,9,10,11],[12,13,14,15],
		[0,4,8,12],[1,5,9,13],[2,6,10,14],[3,7,11,15],
		[0,5,10,15],[3,6,9,12],
	]
	for line in lines:
		var filled: int = 0
		var empty:  int = 0
		for idx in line:
			if board[idx] > 0: filled += 1
			else: empty += 1
		# Complete line = huge bonus
		if empty == 0:  score += 100.0
		# 3-of-4 = big bonus (one away from locked)
		elif filled == 3: score += 30.0
		# 2-of-4 = moderate
		elif filled == 2: score += 8.0
		# 1-of-4 = small
		elif filled == 1: score += 1.0
	return score


# ── Cached POWER index ────────────────────────────────────────────────────
var _pwr_idx: int = -1

func _power_index() -> int:
	if _pwr_idx >= 0: return _pwr_idx
	for i in range(GameState.TRACK_LEN):
		if GameState.TRACK[i]["type"] == "power":
			_pwr_idx = i
			return i
	return 0
