# TokenMover.gd
# ─────────────────────────────────────────────────────────────────────────
# Attach to each player token node (Player1, Player2).
#
# Moves the token smoothly along the track, stopping at each space
# so the player can see exactly where it lands.
#
# Usage from Board.gd:
#   await player1_mover.move_to_pos(new_track_idx, track_positions)
# ─────────────────────────────────────────────────────────────────────────

class_name TokenMover
extends Node2D

# Speed of movement between spaces (seconds per space)
@export var step_duration: float = 0.13

# Emitted when the full move is complete
signal move_finished

# Internal tween reference
var _tween: Tween = null


## Move this token to a new track position.
## Animates through every intermediate space so the path is visible.
##
## Parameters:
##   from_idx      : track index the token is currently on
##   to_idx        : destination track index
##   direction     : "cw" or "ccw"
##   track_positions : Array of Vector2 from Board.gd
##   track_len     : total number of track spaces (36)
func move_along_track(
		from_idx: int,
		to_idx: int,
		direction: String,
		track_positions: Array,
		track_len: int) -> void:

	# Build the list of indices we pass through
	var path: Array = _build_path(from_idx, to_idx, direction, track_len)

	for idx in path:
		var target: Vector2 = track_positions[idx]
		_tween = create_tween()
		_tween.tween_property(self, "global_position", target, step_duration) \
			.set_ease(Tween.EASE_IN_OUT) \
			.set_trans(Tween.TRANS_SINE)
		await _tween.finished

	emit_signal("move_finished")


## Instantly snap token to a position (used during setup)
func snap_to(pos: Vector2) -> void:
	global_position = pos


# ── Private ───────────────────────────────────────────────────────────────

func _build_path(from_idx: int, to_idx: int, direction: String, track_len: int) -> Array:
	var path: Array = []
	var delta: int  = 1 if direction == "cw" else -1
	var pos: int    = from_idx

	# Walk step by step until we reach to_idx
	# (mirrors exactly how GameState.move_pos works)
	while pos != to_idx:
		pos = (pos + delta + track_len) % track_len
		path.append(pos)
		# Safety: if somehow we loop forever, break
		if path.size() > track_len:
			break

	return path
