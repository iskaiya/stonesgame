# TitleScreen.gd
# ─────────────────────────────────────────────────────────────────────────
# Attach to the root node of your title screen scene.
#
# Setup:
#   1. Create a new scene: Scene → New Scene → choose Node2D or Control
#   2. Rename root node to "TitleScreen"
#   3. Attach this script to it
#   4. Add a TextureRect child, set it to your title screen image
#      (the one with STONES logo + START button already in the image)
#   5. Add a plain Button child — position it over the START button in
#      your image, make it invisible (uncheck Visible) so only the
#      image shows but the click area still works
#   6. In Project Settings → Application → Run → Main Scene,
#      set this scene as the main scene
#   7. Your board scene path goes in BOARD_SCENE below
# ─────────────────────────────────────────────────────────────────────────

extends Node

# ── Change this to your actual board scene path ───────────────────────────
const BOARD_SCENE: String = "res://board.tscn"

# ── Export: drag your Start button node here in the Inspector ─────────────
@export var start_button: Button


func _ready() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	else:
		# Fallback: clicking anywhere on screen starts the game
		set_process_input(true)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(BOARD_SCENE)


func _input(event: InputEvent) -> void:
	# If no button assigned, any click or Space/Enter starts game
	if event is InputEventMouseButton and event.pressed:
		get_tree().change_scene_to_file(BOARD_SCENE)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			get_tree().change_scene_to_file(BOARD_SCENE)
