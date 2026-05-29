# InnerBoard.gd
# ─────────────────────────────────────────────────────────────────────────
# Each player has ONE 4x4 quarter (16 cells).
# Human quarter and AI quarter are separate regions on the board image.
#
# Clicking an empty cell in YOUR quarter places a stone there (if you have
# stones in hand and it's your turn to place).
#
# Board.gd calls:
#   inner_board.refresh(state)          — redraw stones
#   inner_board.set_placement_mode(on)  — enable/disable click-to-place
# InnerBoard emits:
#   cell_clicked(is_ai, cell_index)     — when a cell is clicked
# ─────────────────────────────────────────────────────────────────────────

extends Node2D

signal cell_clicked(is_ai: bool, cell_index: int)

# ── Exports: set in Inspector to match your board image ──────────────────
## Top-left of the HUMAN player's 4x4 quarter
@export var human_quarter_origin: Vector2 = Vector2(100, 300)
## Top-left of the AI player's 4x4 quarter
@export var ai_quarter_origin: Vector2    = Vector2(500, 300)
## Size of each individual cell
@export var cell_size: Vector2            = Vector2(48, 48)
## Gap between cells
@export var cell_gap: float               = 4.0

# ── Internal ──────────────────────────────────────────────────────────────
var _stone_pink: Texture2D = null
var _stone_blue: Texture2D = null
var _state: GameState      = null
var _placement_active: bool = false   # true when human can click to place

# All stone sprites: "human_R_C" and "ai_R_C" for row R, col C (0-3)
var _sprites: Dictionary   = {}
# Hover highlight rects (drawn via _draw)
var _hovered_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_stone_pink = load("res://ASSETS/pink piece.png")
	_stone_blue = load("res://ASSETS/blue piece.png")
	if not _stone_pink:
		push_error("InnerBoard: cannot load pink piece.png")
	if not _stone_blue:
		push_error("InnerBoard: cannot load blue piece.png")
	_build_sprites()
	set_process_input(true)


# ── Build one sprite per cell per player ──────────────────────────────────
func _build_sprites() -> void:
	for player in ["human", "ai"]:
		var tex: Texture2D = _stone_pink if player == "human" else _stone_blue
		var origin: Vector2 = human_quarter_origin if player == "human" else ai_quarter_origin
		for row in range(4):
			for col in range(4):
				var key: String = "%s_%d_%d" % [player, row, col]
				var sprite := Sprite2D.new()
				sprite.texture  = tex
				sprite.position = _cell_center(origin, row, col)
				if tex:
					var s: float = min(
						(cell_size.x * 0.8) / tex.get_size().x,
						(cell_size.y * 0.8) / tex.get_size().y
					)
					sprite.scale = Vector2(s, s)
				sprite.visible = false
				add_child(sprite)
				_sprites[key] = sprite


# ── Public API ────────────────────────────────────────────────────────────

func refresh(state: GameState) -> void:
	_state = state
	for row in range(4):
		for col in range(4):
			var idx: int = row * 4 + col
			var hkey: String = "human_%d_%d" % [row, col]
			var akey: String = "ai_%d_%d"    % [row, col]
			if _sprites.has(hkey):
				_sprites[hkey].visible = state.human_board[idx] > 0
			if _sprites.has(akey):
				_sprites[akey].visible = state.ai_board[idx] > 0
	queue_redraw()


## Call with true when it's the human's turn to place a stone.
## Call with false to disable clicking.
func set_placement_mode(active: bool) -> void:
	_placement_active = active
	_hovered_cell     = Vector2i(-1, -1)
	queue_redraw()


# ── Input: detect cell clicks ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _placement_active: return
	if _state == null: return

	if event is InputEventMouseMotion:
		var new_hover := _get_cell_at(event.global_position, false)
		if new_hover != _hovered_cell:
			_hovered_cell = new_hover
			queue_redraw()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _get_cell_at(event.global_position, false)
		if cell.x >= 0:
			var idx: int = cell.x * 4 + cell.y
			# Only allow clicking empty cells
			if _state.human_board[idx] == 0:
				emit_signal("cell_clicked", false, idx)


# ── Hit-test: which cell is the mouse over? ───────────────────────────────
## Returns Vector2i(row, col) or Vector2i(-1,-1) if not over any cell.
## is_ai: which quarter to test
func _get_cell_at(global_pos: Vector2, _is_ai: bool) -> Vector2i:
	# Test human quarter (players can only click their own)
	var origin: Vector2 = human_quarter_origin
	for row in range(4):
		for col in range(4):
			var rect := _cell_rect(origin, row, col)
			# Convert global to local
			var local_pos: Vector2 = to_local(global_pos)
			if rect.has_point(local_pos):
				return Vector2i(row, col)
	return Vector2i(-1, -1)


# ── Draw: cell backgrounds + hover + locked highlights ────────────────────
func _draw() -> void:
	if _state == null: return

	var locked_human: Dictionary = _state.locked_set(false)
	var locked_ai:    Dictionary = _state.locked_set(true)

	_draw_quarter(human_quarter_origin, false, locked_human)
	_draw_quarter(ai_quarter_origin,    true,  locked_ai)


func _draw_quarter(origin: Vector2, is_ai: bool, locked: Dictionary) -> void:
	var board: Array = _state.ai_board if is_ai else _state.human_board
	# Quarter background tint
	var bg: Color = Color(0.7, 0.85, 1.0, 0.15) if is_ai else Color(1.0, 0.75, 0.75, 0.15)
	var quarter_w: float = 4 * cell_size.x + 3 * cell_gap
	var quarter_h: float = 4 * cell_size.y + 3 * cell_gap
	draw_rect(Rect2(origin, Vector2(quarter_w, quarter_h)), bg, true)

	for row in range(4):
		for col in range(4):
			var idx: int  = row * 4 + col
			var rect: Rect2 = _cell_rect(origin, row, col)
			var is_locked: bool = locked.has(idx)
			var has_stone: bool = board[idx] > 0

			# Cell fill
			var cell_color: Color
			if is_locked:
				cell_color = Color(1.0, 0.85, 0.1, 0.4)   # gold = locked
			elif _placement_active and not is_ai and not has_stone:
				# Hoverable empty cell
				if _hovered_cell == Vector2i(row, col):
					cell_color = Color(0.5, 1.0, 0.5, 0.35)  # green hover
				else:
					cell_color = Color(1.0, 1.0, 1.0, 0.12)  # normal empty
			else:
				cell_color = Color(1.0, 1.0, 1.0, 0.08)

			draw_rect(rect, cell_color, true)
			draw_rect(rect, Color(1, 1, 1, 0.25), false)  # border

			# Lock border glow
			if is_locked:
				draw_rect(rect, Color(1.0, 0.85, 0.1, 0.8), false)


# ── Geometry helpers ──────────────────────────────────────────────────────
func _cell_center(origin: Vector2, row: int, col: int) -> Vector2:
	return origin + Vector2(
		col * (cell_size.x + cell_gap) + cell_size.x * 0.5,
		row * (cell_size.y + cell_gap) + cell_size.y * 0.5
	)


func _cell_rect(origin: Vector2, row: int, col: int) -> Rect2:
	return Rect2(
		origin + Vector2(col * (cell_size.x + cell_gap), row * (cell_size.y + cell_gap)),
		cell_size
	)
