extends Node
## Local, offline account system -- no external service, no account
## to connect. Mirrors the same signal-based API a cloud backend
## would (sign_up/sign_in + succeeded/failed signals) so the rest of
## the game doesn't care which backend is behind Auth, and this can
## be swapped for a real cloud backend later without touching
## login.gd/lobby.gd. Accounts are stored locally in
## user://accounts.json; the last logged-in account is remembered in
## user://session.json so the app doesn't ask to log in every launch.

const SAVE_PATH := "user://accounts.json"
const SESSION_PATH := "user://session.json"

const DEFAULT_CUSTOMIZATION := {
	"skin": "#E0AC69",
	"shirt": "#F0CC26",
	"pants": "#D2661A",
	"hair": "#4D2B1A",
}

signal sign_up_succeeded(needs_email_confirmation: bool)
signal sign_up_failed(message: String)
signal sign_in_succeeded()
signal sign_in_failed(message: String)
signal signed_out()
signal customization_changed()

var username := ""
var user_id := ""
var is_logged_in := false
var customization := DEFAULT_CUSTOMIZATION.duplicate()

var _accounts := {}


func _ready() -> void:
	_load_accounts()
	_try_restore_session()


func sign_up(email: String, password: String, desired_username: String) -> void:
	var key := email.strip_edges().to_lower()
	if _accounts.has(key):
		sign_up_failed.emit("This email is already registered -- try Log In instead.")
		return
	_accounts[key] = {
		"username": desired_username,
		"password_hash": password.sha256_text(),
		"customization": DEFAULT_CUSTOMIZATION.duplicate(),
	}
	_save_accounts()
	_apply_session(key)
	_save_session()
	sign_up_succeeded.emit(false)


func sign_in(email: String, password: String) -> void:
	var key := email.strip_edges().to_lower()
	if not _accounts.has(key):
		sign_in_failed.emit("No account found -- please Sign Up first.")
		return
	var record: Dictionary = _accounts[key]
	if record.get("password_hash", "") != password.sha256_text():
		sign_in_failed.emit("Incorrect password.")
		return
	_apply_session(key)
	_save_session()
	sign_in_succeeded.emit()


func sign_out() -> void:
	username = ""
	user_id = ""
	is_logged_in = false
	customization = DEFAULT_CUSTOMIZATION.duplicate()
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
	signed_out.emit()


## Updates and persists one customization color ("skin", "shirt",
## "pants", or "hair") for the currently logged-in account.
func set_customization_color(part: String, hex_color: String) -> void:
	customization[part] = hex_color
	if is_logged_in and _accounts.has(user_id):
		_accounts[user_id]["customization"] = customization.duplicate()
		_save_accounts()
	customization_changed.emit()


func _apply_session(key: String) -> void:
	var record: Dictionary = _accounts[key]
	username = record.get("username", "Player")
	user_id = key
	is_logged_in = true
	var saved_customization: Dictionary = record.get("customization", {})
	customization = DEFAULT_CUSTOMIZATION.duplicate()
	for part in saved_customization:
		customization[part] = saved_customization[part]


func _try_restore_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data and typeof(data) == TYPE_DICTIONARY and data.has("email"):
		var key: String = data["email"]
		if _accounts.has(key):
			_apply_session(key)


func _save_session() -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Auth: could not save session (error %d)." % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"email": user_id}))
	file.close()


func _load_accounts() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Auth: could not open %s for reading (error %d) -- accounts will look empty this run." % [SAVE_PATH, FileAccess.get_open_error()])
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data and typeof(data) == TYPE_DICTIONARY:
		_accounts = data
	else:
		push_error("Auth: %s did not contain valid account data -- starting empty." % SAVE_PATH)


func _save_accounts() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Auth: could not open %s for writing (error %d) -- this account was NOT saved." % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(_accounts))
	file.close()
