# GameState.gd
# ─────────────────────────────────────────────────────────────────────────
# Pure data class — no Node, no scene dependencies.
# Holds the complete state of one Stones match.
# Clone cheaply for the AI expectiminimax search tree.
#
# SPC ORDER ASSUMED:
#   spc1  = first space after top-left corner (top edge, moving right)
#   spc2  = next space right...
#   ...continuing clockwise all the way around...
#   spc35 = last space before top-left corner (left edge, moving up)
#   spc36 = top-left corner itself
#
# If your layout differs, just reorder the TRACK array below to match.
# ─────────────────────────────────────────────────────────────────────────

class_name GameState
extends RefCounted


# ── Track layout ──────────────────────────────────────────────────────────
# 36 entries matching spc1..spc36 in your scene, in clockwise order.
#
# Space types:
#   "corner"  — corner position; passable mid-game, choosable at start
#   "safe"    — SAFE space: while here, opponent R1 cannot touch your board
#   "take"    — TAKE corner: steal 1 stone from opponent into your hand
#   "power"   — POWER: steal 1 opponent board stone onto your own board
#   "plus"    — collect N stones from cache (+1 or +2)
#   "minus"   — return N stones to cache (-1 or -2)
#   "place"   — place N stones from hand onto your board (P1 or P2)
#   "remove"  — R1: send 1 opponent stone back to cache

const TRACK: Array = [
	# ── Top-left corner (spc1) ───────────────────────────────────────────
	{ "type": "safe",   "label": "SAFE",  "is_corner": true  },  # 0  spc1  TL corner

	# ── Top edge, left → right (spc2..spc9) ──────────────────────────────
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 1  spc2
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 2  spc3
	{ "type": "plus",   "label": "+1",    "is_corner": false },  # 3  spc4
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 4  spc5
	{ "type": "minus",  "label": "-1",    "is_corner": false },  # 5  spc6
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 6  spc7
	{ "type": "remove", "label": "R1",    "is_corner": false },  # 7  spc8
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 8  spc9

	# ── Top-right corner (spc10) ──────────────────────────────────────────
	{ "type": "take",   "label": "TAKE",  "is_corner": true  },  # 9  spc10 TR corner

	# ── Right edge, top → bottom (spc11..spc18) ───────────────────────────
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 10 spc11 ✓
	{ "type": "minus",  "label": "-1",    "is_corner": false },  # 11 spc12
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 12 spc13
	{ "type": "minus",  "label": "-2",    "is_corner": false },  # 13 spc14
	{ "type": "plus",   "label": "+1",    "is_corner": false },  # 14 spc15
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 15 spc16
	{ "type": "place",  "label": "P2",    "is_corner": false },  # 16 spc17
	{ "type": "minus",  "label": "-1",    "is_corner": false },  # 17 spc18

	# ── Bottom-right corner (spc19) ───────────────────────────────────────
	{ "type": "safe",   "label": "SAFE",  "is_corner": true  },  # 18 spc19 BR corner

	# ── Bottom edge, right → left (spc20..spc27) ──────────────────────────
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 19 spc20
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 20 spc21
	{ "type": "plus",   "label": "+1",    "is_corner": false },  # 21 spc22
	{ "type": "power",  "label": "POWER", "is_corner": false },  # 22 spc23
	{ "type": "remove", "label": "R1",    "is_corner": false },  # 23 spc24
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 24 spc25
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 25 spc26
	{ "type": "place",  "label": "P2",    "is_corner": false },  # 26 spc27

	# ── Bottom-left corner (spc28) ────────────────────────────────────────
	{ "type": "take",   "label": "TAKE",  "is_corner": true  },  # 27 spc28 BL corner

	# ── Left edge, bottom → top (spc29..spc36) ────────────────────────────
	{ "type": "minus",  "label": "-2",    "is_corner": false },  # 28 spc29
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 29 spc30
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 30 spc31
	{ "type": "minus",  "label": "-2",    "is_corner": false },  # 31 spc32
	{ "type": "place",  "label": "P1",    "is_corner": false },  # 32 spc33
	{ "type": "minus",  "label": "-1",    "is_corner": false },  # 33 spc34
	{ "type": "place",  "label": "P2",    "is_corner": false },  # 34 spc35
	{ "type": "plus",   "label": "+2",    "is_corner": false },  # 35 spc36
]

const TRACK_LEN: int = 36

# Corner indices in TRACK array (0-based, matching spc numbers minus 1)
const CORNER_TL: int = 0   # spc1  - top-left corner
const CORNER_TR: int = 9   # spc10 - top-right corner
const CORNER_BR: int = 18  # spc19 - bottom-right corner
const CORNER_BL: int = 27  # spc28 - bottom-left corner

const ALL_CORNERS: Array = [0, 9, 18, 27]

# Opposite corner map (for AI auto-pick)
const OPPOSITE_CORNER: Dictionary = {
	0:  18,   # TL ↔ BR
	18: 0,
	9:  27,   # TR ↔ BL
	27: 9,
}

# Locked-row line definitions (indices 0–15 in a 4×4 grid)
const LOCKED_LINES: Array = [
	[0,1,2,3], [4,5,6,7], [8,9,10,11], [12,13,14,15],
	[0,4,8,12],[1,5,9,13],[2,6,10,14], [3,7,11,15],
	[0,5,10,15],[3,6,9,12],
]


# ── Mutable game data ─────────────────────────────────────────────────────

var round_number: int  = 1
var cache: int         = 64

var human_pos: int     = -1   # TRACK index; -1 = not yet placed
var human_hand: int    = 0    # stones in hand (pile)
var human_board: Array = []   # 16 ints: 0=empty, 1=stone

var ai_pos: int        = -1
var ai_hand: int       = 0
var ai_board: Array    = []

var human_start_corner: int = -1
var ai_start_corner: int    = -1

# How many stones the human still needs to place this turn (set by P1/P2 action)
var human_stones_to_place: int = 0  # set by P1/P2 action only, reset each move

# Track each player's first turn separately
var human_first_done: bool = false
var ai_first_done: bool    = false


func _init() -> void:
	human_board = []
	ai_board    = []
	for _i in range(16):
		human_board.append(0)
		ai_board.append(0)


# ── Track helpers ─────────────────────────────────────────────────────────

func space_at(idx: int) -> Dictionary:
	return TRACK[idx % TRACK_LEN]


## Move pos by `steps` in direction ("cw" or "ccw").
## Every space including corners counts as a step — all are landable.
func move_pos(current_pos: int, steps: int, direction: String) -> int:
	var delta: int = 1 if direction == "cw" else -1
	var pos: int   = current_pos
	for _i in range(steps):
		pos = (pos + delta + TRACK_LEN) % TRACK_LEN
	return pos


# ── Board helpers ─────────────────────────────────────────────────────────

func stones_on_board(is_ai: bool) -> int:
	var board: Array = ai_board if is_ai else human_board
	var n: int = 0
	for v in board:
		if v > 0: n += 1
	return n


func locked_set(is_ai: bool) -> Dictionary:
	var board: Array = ai_board if is_ai else human_board
	var locked: Dictionary = {}
	for line in LOCKED_LINES:
		var full: bool = true
		for idx in line:
			if board[idx] == 0:
				full = false
				break
		if full:
			for idx in line:
				locked[idx] = true
	return locked


func count_locked_rows(is_ai: bool) -> int:
	var board: Array = ai_board if is_ai else human_board
	var rows: int = 0
	for line in LOCKED_LINES:
		var full: bool = true
		for idx in line:
			if board[idx] == 0:
				full = false
				break
		if full: rows += 1
	return rows


## Place a stone at a specific cell index (0-15, row*4+col).
## Returns true if successful.
func place_stone_at(is_ai: bool, cell_idx: int) -> bool:
	var board: Array = ai_board if is_ai else human_board
	if cell_idx < 0 or cell_idx >= 16: return false
	if board[cell_idx] != 0: return false
	var hand: int = ai_hand if is_ai else human_hand
	if hand <= 0: return false
	board[cell_idx] = 1
	if is_ai:
		ai_hand  = hand - 1
	else:
		human_hand = hand - 1
	return true


## Auto-place n stones in the first available cells (used by AI and space actions).
## Returns actual placed count.
func place_stones(is_ai: bool, n: int) -> int:
	var board: Array = ai_board if is_ai else human_board
	var hand: int    = ai_hand  if is_ai else human_hand
	var placed: int  = 0
	for i in range(16):
		if placed >= n or hand <= 0: break
		if board[i] == 0:
			board[i] = 1
			hand    -= 1
			placed  += 1
	if is_ai:
		ai_board = board
		ai_hand  = hand
	else:
		human_board = board
		human_hand  = hand
	return placed


func is_winner(is_ai: bool) -> bool:
	return stones_on_board(is_ai) >= 16


func check_winner() -> String:
	if is_winner(false): return "human"
	if is_winner(true):  return "ai"
	return ""


# ── Deep clone for AI search ──────────────────────────────────────────────
func clone() -> GameState:
	var s: GameState     = GameState.new()
	s.round_number       = round_number
	s.cache              = cache
	s.human_pos          = human_pos
	s.human_hand         = human_hand
	s.human_board        = human_board.duplicate()
	s.ai_pos             = ai_pos
	s.ai_hand            = ai_hand
	s.ai_board           = ai_board.duplicate()
	s.human_start_corner = human_start_corner
	s.ai_start_corner    = ai_start_corner
	s.human_first_done        = human_first_done
	s.ai_first_done           = ai_first_done
	s.human_stones_to_place   = human_stones_to_place
	return s
