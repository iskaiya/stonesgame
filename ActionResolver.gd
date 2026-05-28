# ActionResolver.gd
# ─────────────────────────────────────────────────────────────────────────
# Stateless class — apply_action() takes a GameState and mutates it
# according to whichever space the active player just landed on.
#
# Works on BOTH the real game state (during play) and cloned states
# (during AI tree search) — never touches the scene tree.
#
# Usage:
#   var msg := ActionResolver.apply_action(state, is_ai)
#
# Attach this script to an AutoLoad singleton called "ActionResolver"
# (Project → Project Settings → AutoLoad → add ActionResolver.gd).
# ─────────────────────────────────────────────────────────────────────────

extends Node


## Apply the effect of landing on the current space.
## Mutates `state` in place.
## Returns a human-readable log message string.
func apply_action(state: GameState, is_ai: bool) -> String:
	var pos: int        = state.ai_pos    if is_ai else state.human_pos
	var space: Dictionary = state.space_at(pos)
	var stype: String   = space["type"]
	var label: String   = space["label"]
	var actor: String   = "AI" if is_ai else "You"
	var msg: String     = ""

	match stype:

		# ── +1 / +2 — collect stones from cache ──────────────────────────
		"plus":
			var n: int    = 1 if label == "+1" else 2
			var take: int = mini(n, state.cache)
			if is_ai:
				state.ai_hand += take
			else:
				state.human_hand += take
			state.cache -= take
			msg = "%s collected %d stone(s) from the cache." % [actor, take]

		# ── -1 / -2 — return stones to cache ─────────────────────────────
		"minus":
			var n: int    = 1 if label == "-1" else 2
			var hand: int = state.ai_hand if is_ai else state.human_hand
			var give: int = mini(n, hand)
			if is_ai:
				state.ai_hand -= give
			else:
				state.human_hand -= give
			state.cache += give
			if give > 0:
				msg = "%s returned %d stone(s) to the cache." % [actor, give]
			else:
				msg = "%s has no stones to return — turn passed." % actor

		# ── P1 / P2 ───────────────────────────────────────────────────────
		# Place N stones FROM HAND onto board.
		# If hand is empty, turn is passed (no stones to place).
		"place":
			var n: int    = 1 if label == "P1" else 2
			var hand: int = state.ai_hand if is_ai else state.human_hand
			if hand <= 0:
				msg = "%s has no stones in hand — turn passed." % actor
			elif is_ai:
				var placed: int = state.place_stones(true, n)
				msg = "%s placed %d stone(s) on their board." % [actor, placed]
			else:
				# Human: flag how many they need to place, Board.gd handles the pause
				var to_place: int = mini(n, hand)
				state.human_hand -= to_place   # reserve them
				state.human_hand += to_place   # put back — Board.gd will deduct on click
				# Just signal how many to place via a special key in state
				state.human_stones_to_place = to_place
				msg = "%s must place %d stone(s) — click your board!" % [actor, to_place]

		# ── R1 — remove 1 opponent stone (back to cache) ──────────────────
		"remove":
			var opp_pos: int     = state.human_pos if is_ai else state.ai_pos
			var opp_is_ai: bool  = not is_ai
			var opp_safe: bool   = state.space_at(opp_pos)["type"] == "safe"
			var opp_locked: Dictionary = state.locked_set(opp_is_ai)

			# Find a removable stone (not locked)
			var opp_board: Array = state.ai_board if opp_is_ai else state.human_board
			var removable: int   = _find_removable(opp_board, opp_locked)

			if opp_safe:
				msg = "R1 blocked — opponent is in SAFE!"
			elif removable < 0:
				msg = "R1 — no removable stones on opponent's board."
			else:
				opp_board[removable] = 0
				state.cache += 1
				if opp_is_ai:
					state.ai_board = opp_board
				else:
					state.human_board = opp_board
				msg = "%s removed 1 stone from opponent's board (back to cache)." % actor

		# ── POWER — steal 1 stone directly onto your own board ────────────
		# Ignores SAFE corner and locked rows (per rules)
		"power":
			var opp_is_ai: bool  = not is_ai
			var opp_board: Array = (state.ai_board if opp_is_ai else state.human_board).duplicate()
			var removable: int   = _find_any_stone(opp_board)

			if removable < 0:
				msg = "POWER — opponent has no stones on the board!"
			else:
				# Remove stone from opponent
				opp_board[removable] = 0
				if opp_is_ai:
					state.ai_board = opp_board
				else:
					state.human_board = opp_board

				if is_ai:
					# AI auto-places stolen stone
					var my_board: Array = state.ai_board.duplicate()
					for i in range(16):
						if my_board[i] == 0:
							my_board[i] = 1
							break
					state.ai_board = my_board
					msg = "AI used POWER — stole a stone onto their board!"
				else:
					# Human picks where to place the stolen stone
					state.human_stones_to_place = 1
					msg = "POWER! You stole a stone — click your board to place it!"

		# ── TAKE — steal 1 stone into your hand ───────────────────────────
		# Ignores locked rows. Blocked only if opponent is in SAFE corner.
		"take":
			var opp_pos: int     = state.human_pos if is_ai else state.ai_pos
			var opp_is_ai: bool  = not is_ai
			var opp_safe: bool   = state.space_at(opp_pos)["type"] == "safe"
			var opp_board: Array = (state.ai_board if opp_is_ai else state.human_board).duplicate()
			var removable: int   = _find_any_stone(opp_board)

			if opp_safe:
				msg = "TAKE blocked — opponent is in SAFE!"
			elif removable < 0:
				msg = "TAKE — opponent has no board stones."
			else:
				opp_board[removable] = 0
				if opp_is_ai:
					state.ai_board = opp_board
				else:
					state.human_board = opp_board
				if is_ai:
					state.ai_hand += 1
				else:
					state.human_hand += 1
				msg = "%s used TAKE — grabbed 1 stone into hand!" % actor

		# ── SAFE — landing here protects your board ───────────────────────
		"safe":
			msg = "%s is in the SAFE corner — board protected this turn!" % actor

		# ── CORNER — passing through, no action ───────────────────────────
		"corner":
			msg = "%s passed through a corner." % actor

		_:
			msg = "Unknown space type: %s" % stype

	return msg


# ── Private helpers ───────────────────────────────────────────────────────

## Find the highest-index stone that is NOT locked. Returns -1 if none.
func _find_removable(board: Array, locked: Dictionary) -> int:
	for i in range(15, -1, -1):
		if board[i] > 0 and not locked.has(i):
			return i
	return -1


## Find the highest-index stone regardless of locks. Returns -1 if none.
func _find_any_stone(board: Array) -> int:
	for i in range(15, -1, -1):
		if board[i] > 0:
			return i
	return -1
