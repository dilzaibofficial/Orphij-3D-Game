extends Node
## Thin wrapper around Supabase's Auth + REST API over plain HTTP
## (Godot's built-in HTTPRequest -- no plugin needed). Autoloaded as
## "Supabase" so login state survives scene changes (Login -> Lobby
## -> the game itself).

const SUPABASE_URL := "https://ovrynthdledspeumwack.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_JvhKf0umGEfnZxEYqeRtMg_OMOU9ega"

signal sign_up_succeeded(needs_email_confirmation: bool)
signal sign_up_failed(message: String)
signal sign_in_succeeded()
signal sign_in_failed(message: String)
signal profile_updated()

var access_token := ""
var user_id := ""
var username := ""

var _http: HTTPRequest
var _pending_action := ""
var _pending_username := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func sign_up(email: String, password: String, desired_username: String) -> void:
	_pending_action = "sign_up"
	_pending_username = desired_username
	var body := JSON.stringify({"email": email, "password": password})
	var headers := ["Content-Type: application/json", "apikey: " + SUPABASE_ANON_KEY]
	_http.request(SUPABASE_URL + "/auth/v1/signup", headers, HTTPClient.METHOD_POST, body)


func sign_in(email: String, password: String) -> void:
	_pending_action = "sign_in"
	var body := JSON.stringify({"email": email, "password": password})
	var headers := ["Content-Type: application/json", "apikey: " + SUPABASE_ANON_KEY]
	_http.request(SUPABASE_URL + "/auth/v1/token?grant_type=password", headers, HTTPClient.METHOD_POST, body)


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	var action := _pending_action
	_pending_action = ""

	if action == "sign_up":
		var ok := response_code >= 200 and response_code < 300
		if ok:
			var has_token: bool = data != null and typeof(data) == TYPE_DICTIONARY and data.has("access_token")
			if data and typeof(data) == TYPE_DICTIONARY and data.has("id"):
				user_id = data["id"]
			username = _pending_username
			if has_token:
				access_token = data["access_token"]
				_update_profile_username(_pending_username)
			sign_up_succeeded.emit(not has_token)
		else:
			var message := "Sign up failed"
			if data and typeof(data) == TYPE_DICTIONARY and data.has("msg"):
				message = data["msg"]
			elif data and typeof(data) == TYPE_DICTIONARY and data.has("error_description"):
				message = data["error_description"]
			sign_up_failed.emit(message)

	elif action == "sign_in":
		var has_token: bool = data != null and typeof(data) == TYPE_DICTIONARY and data.has("access_token")
		if response_code >= 200 and response_code < 300 and has_token:
			access_token = data["access_token"]
			user_id = data["user"]["id"] if data.has("user") else ""
			sign_in_succeeded.emit()
			_fetch_profile()
		else:
			var message := "Login failed"
			if data and typeof(data) == TYPE_DICTIONARY and data.has("error_description"):
				message = data["error_description"]
			elif data and typeof(data) == TYPE_DICTIONARY and data.has("msg"):
				message = data["msg"]
			sign_in_failed.emit(message)


func _fetch_profile() -> void:
	var headers := [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + access_token,
	]
	var fetch := HTTPRequest.new()
	add_child(fetch)
	fetch.request_completed.connect(func(_r, code, _h, b):
		if code >= 200 and code < 300:
			var arr = JSON.parse_string(b.get_string_from_utf8())
			if arr and typeof(arr) == TYPE_ARRAY and arr.size() > 0:
				username = arr[0].get("username", username)
				profile_updated.emit()
		fetch.queue_free()
	)
	fetch.request(SUPABASE_URL + "/rest/v1/profiles?id=eq." + user_id + "&select=username,shirt_color,pants_color,hair_color", headers, HTTPClient.METHOD_GET)


func _update_profile_username(new_username: String) -> void:
	var headers := [
		"apikey: " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer " + access_token,
	]
	var patch := HTTPRequest.new()
	add_child(patch)
	patch.request_completed.connect(func(_r, _c, _h, _b): patch.queue_free())
	patch.request(SUPABASE_URL + "/rest/v1/profiles?id=eq." + user_id, headers, HTTPClient.METHOD_PATCH, JSON.stringify({"username": new_username}))
