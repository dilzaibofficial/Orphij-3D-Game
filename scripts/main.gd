extends Node3D
## Entry point. Skips straight to the Lobby if a session was
## remembered from last time (Auth.is_logged_in); otherwise opens the
## login screen. Once there's more than one game, this is also where
## a game-select menu will go.

const LOGIN_SCENE := "res://scenes/Login.tscn"
const LOBBY_SCENE := "res://scenes/Lobby.tscn"


func _ready() -> void:
	var entry_path := LOBBY_SCENE if Auth.is_logged_in else LOGIN_SCENE
	var entry_scene: PackedScene = load(entry_path)
	add_child(entry_scene.instantiate())
