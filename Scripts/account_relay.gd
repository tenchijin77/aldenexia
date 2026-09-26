# account_relay.gd — player accounts on a dedicated server. One account (name + password) holds up to MAX_CHARACTERS
# characters. The Join a Server screen logs into the account, lists its characters (portrait, name, level, class, zone)
# and enters the world with one of them. An account can be logged in on several computers at once; the only limit is
# still one connection per CHARACTER (logging a character in again takes it over, as before).
#
# Lives as a child of Net named "Accounts", created at runtime on every peer: Net's own RPC list must stay identical to
# the released build's (tools/net_rpc_released.txt), so new messages go here.
#
# The menu errands (log in / create account / delete a character / add an existing character) ride Net's errand
# connection: connect, version check, one request here, and the answer ends the errand (Net.server_request_done).
# Failures come back through Net._login_fail like every other login error. Entering the world still goes through
# Net._rpc_login, with the account name and password packed into its password field (pack()).
#
# Server files: user://server_accounts/<server>_<account>.json = {"name", "salt", "hash", "characters": [...], "created"}.
# A character that belongs to an account can only be logged in (or deleted) through that account.
#
# Moving old one-character-per-login saves into accounts: put an import file at user://server_accounts/import.json and
# (re)start the server. It is read once, then renamed with the plain-text passwords removed:
#   {"accounts": [{"account": "tenchijin", "password": "lightfall", "characters": ["zozuur", "shonuff"]},
#                 {"account": "epheo", "password_of": "epheo", "characters": ["epheo"]}]}
# "password_of" copies that character's existing password, so the player keeps the one they know.
class_name AccountRelay
extends Node

const ACCOUNT_DIR := "user://server_accounts"
const IMPORT_FILE := "user://server_accounts/import.json"
const MAX_CHARACTERS := 14   # one of each class (test 42; was 8)
const DEFAULT_ZONE := "Lumora Outskirts"  # saves from before "last_zone" was recorded

# Client: the account logged in on the Join a Server screen, kept until Log Out or quit, so coming back from character
# creation, a failed join or a camp-out reopens the character list. {} when none.
static var session: Dictionary = {}  # {"address", "port", "account", "password"}

var _owner_of: Dictionary = {}  # server: character name -> account name


# The password field Net._rpc_login receives for an account login.
static func pack(account: String, password: String) -> String:
	return JSON.stringify({"account": account, "password": password})


static func _unpack(text: String) -> Dictionary:
	if not text.begins_with("{"):
		return {}
	var data = JSON.parse_string(text)
	return data if typeof(data) == TYPE_DICTIONARY and data.has("account") else {}


# ── Client ──
# Starts an account errand; the answer arrives as Net.server_request_done(ok, kind, message, info), where info is
# the account listing ({"account", "characters": [...], "max"}) on success.
func request(address: String, port: int, action: String, args: Dictionary) -> void:
	Net._start_menu_request({"type": "account", "action": action, "args": args}, address, port)


# Net._rpc_version_accepted calls this once the errand's connection is approved.
func send_errand(errand: Dictionary) -> void:
	_rpc_request.rpc_id(1, str(errand.get("action", "")), JSON.stringify(errand.get("args", {})))


@rpc("authority", "call_remote", "reliable")
func _rpc_result(kind: String, message: String, info_json: String) -> void:
	var info = JSON.parse_string(info_json)
	Net._finish_menu_request(true, kind, message, info if typeof(info) == TYPE_DICTIONARY else {})


# ── Server ──
func server_start() -> void:
	DirAccess.make_dir_recursive_absolute(ACCOUNT_DIR)
	_load_index()
	if FileAccess.file_exists(IMPORT_FILE):
		_run_import()
	Net._slog("Accounts: %d, holding %d characters." % [_account_names().size(), _owner_of.size()])


func owner_of(character: String) -> String:
	return str(_owner_of.get(character, ""))


# Shared macros (macros.gd): the account's own list, which every character on it sees.
func shared_macros(account: String) -> Array:
	return Macros.sanitize(_read_account(account).get("shared_macros", []), Macros.SHARED_SLOTS)


func set_shared_macros(account: String, list: Array) -> bool:
	var data := _read_account(account)
	if data.is_empty():
		return false
	data["shared_macros"] = Macros.sanitize(list, Macros.SHARED_SLOTS)
	return _write_account(account, data)


func _account_path(account: String) -> String:
	return "%s/%s_%s.json" % [ACCOUNT_DIR, Net.server_name, account]


func _read_account(account: String) -> Dictionary:
	var path := _account_path(account)
	if account.is_empty() or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if typeof(data.get("characters")) != TYPE_ARRAY:
		data["characters"] = []
	return data


func _write_account(account: String, data: Dictionary) -> bool:
	return Net._write_file_atomic(_account_path(account), JSON.stringify(data, "\t"))


func _account_names() -> Array:
	var names: Array = []
	var prefix := Net.server_name + "_"
	for file in DirAccess.get_files_at(ACCOUNT_DIR):
		if file.begins_with(prefix) and file.ends_with(".json"):
			names.append(file.trim_prefix(prefix).trim_suffix(".json"))
	return names


func _load_index() -> void:
	_owner_of.clear()
	for account in _account_names():
		for character in _read_account(account).get("characters", []):
			_owner_of[str(character)] = account


func _character_key(character: String) -> String:
	return "%s_%s" % [Net.server_name, character]


# True if `password` opens `account`; otherwise the peer has been told why (locked / wrong password).
func _check_account(id: int, account: String, password: String) -> bool:
	var lock := "account:" + account
	var left := Net._lockout_seconds_left(lock)
	if left > 0:
		Net._login_fail(id, "locked", "Too many wrong passwords. Try again in %d seconds." % left)
		return false
	var data := _read_account(account)
	if data.is_empty() or Net._hash_password(password, str(data.get("salt", ""))) != str(data.get("hash", "")):
		Net._login_fail(id, "bad_password", Net._register_wrong_password(lock).replace("this character", "this account"))
		return false
	Net._login_failures.erase(lock)
	return true


# Called by Net._rpc_login. `password` is what the client sent: packed account credentials, or an old-style character
# password. Returns "" to carry on with the old per-character password, the account name when the account opened
# (and may use this character), or "!" when the login was refused (the peer has been told).
func check_login(id: int, character: String, password: String, creating: bool) -> String:
	# Every zone's server shares the account files and any of them may have added a character since: read them fresh.
	_load_index()
	var creds := _unpack(password)
	var owner := owner_of(character)
	if creds.is_empty():
		if not owner.is_empty():
			Net._login_fail(id, "account_character", "%s belongs to an account. Log in with the account instead." % character.capitalize())
			return "!"
		return ""
	var account := Net.sanitize_name(str(creds.get("account", "")))
	var data := _read_account(account)
	if data.is_empty():
		Net._login_fail(id, "no_account", "There is no account named %s on this server." % str(creds.get("account", "")))
		return "!"
	if not _check_account(id, account, str(creds.get("password", ""))):
		return "!"
	if creating:
		if (data["characters"] as Array).size() >= MAX_CHARACTERS:
			Net._login_fail(id, "account_full", "This account already has %d characters. Delete one first." % MAX_CHARACTERS)
			return "!"
	elif owner != account:
		Net._login_fail(id, "no_character", "%s isn't a character on this account." % character.capitalize())
		return "!"
	return account


# A character Net just created under `account`.
func add_character(account: String, character: String) -> void:
	var data := _read_account(account)
	if data.is_empty() or (data["characters"] as Array).has(character):
		return
	data["characters"].append(character)
	if _write_account(account, data):
		_owner_of[character] = account


# What the character list shows: one entry per character, in the order they were added.
# Online anywhere in the world (the hub knows every zone's players), not just in this server's zone.
func _is_online(character: String) -> bool:
	if Net._peer_character.values().has(_character_key(character)):
		return true
	var link := Net.get_tree().get_first_node_in_group("world_link")
	return link != null and link.has_method("online_everywhere") and link.online_everywhere().has(character.to_lower())


func _listing(account: String) -> Dictionary:
	var rows: Array = []
	for character in _read_account(account).get("characters", []):
		var key := _character_key(str(character))
		var path := Net._character_path(key)
		if not FileAccess.file_exists(path):
			continue
		var save := Net._parse_character(FileAccess.get_file_as_string(path), str(character))
		if save.is_empty():
			rows.append({"name": str(character), "level": 0, "class": "", "race": "", "sex": "", "zone": "(save unreadable)", "online": _is_online(str(character))})
			continue
		rows.append({
			"name": str(character), "display": str(save.get("player_name", character)).capitalize(),
			"level": int(save.get("player_level", 1)), "class": str(save.get("player_class", "")),
			"race": str(save.get("player_race", "")), "sex": str(save.get("player_sex", "male")),
			"zone": ZoneInfo.name_for(str(save["zone"])) if ZoneInfo.exists(str(save.get("zone", ""))) else str(save.get("last_zone", DEFAULT_ZONE)),
			"online": _is_online(str(character)),
		})
	return {"account": account, "characters": rows, "max": MAX_CHARACTERS}


func _reply(id: int, kind: String, message: String, account: String) -> void:
	Net._awaiting_login.erase(id)
	_rpc_result.rpc_id(id, kind, message, JSON.stringify(_listing(account)))
	get_tree().create_timer(0.6).timeout.connect(Net._kick.bind(id))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(action: String, args_json: String) -> void:
	if not Net.is_dedicated_server or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not Net._awaiting_login.has(id):
		return
	var args = JSON.parse_string(args_json)
	if typeof(args) != TYPE_DICTIONARY:
		Net._login_fail(id, "server_error", "The server couldn't read that request.")
		return
	var account := Net.sanitize_name(str(args.get("account", "")))
	var password := str(args.get("password", ""))
	if account.is_empty():
		Net._login_fail(id, "invalid_name", "Account names use letters and numbers only, 2 to 16 characters.")
		return
	var ip := Net.peer_ip(id)
	if action == "create":
		if FileAccess.file_exists(_account_path(account)):
			Net._login_fail(id, "name_taken", "An account named %s already exists on this server." % account)
			return
		if password.length() < Net.MIN_PASSWORD_LENGTH:
			Net._login_fail(id, "weak_password", "Passwords need at least %d characters." % Net.MIN_PASSWORD_LENGTH)
			return
		var salt := Crypto.new().generate_random_bytes(16).hex_encode()
		var data := {"name": account, "salt": salt, "hash": Net._hash_password(password, salt), "characters": [],
				"created": int(Time.get_unix_time_from_system())}
		if not _write_account(account, data):
			Net._login_fail(id, "server_error", "The server could not save your new account.")
			return
		Net._slog("Account %s created — peer %d, %s." % [account, id, ip])
		Net._audit("ACCOUNT CREATED", ip, account)
		_reply(id, "created", "Account %s created. Now create your first character." % account, account)
		return
	if not FileAccess.file_exists(_account_path(account)):
		Net._login_fail(id, "no_account", "There is no account named %s on this server." % account)
		return
	if not _check_account(id, account, password):
		return
	match action:
		"login":
			_reply(id, "listed", "", account)
		"delete":
			_delete_character(id, account, Net.sanitize_name(str(args.get("character", ""))))
		"attach":
			_attach_character(id, account, Net.sanitize_name(str(args.get("character", ""))), str(args.get("character_password", "")))
		_:
			Net._login_fail(id, "server_error", "Unknown account request.")


# Moves the character's files to deleted/ (never erased, so the server owner can undo it) and drops it from the account.
func _delete_character(id: int, account: String, character: String) -> void:
	var key := _character_key(character)
	if character.is_empty() or owner_of(character) != account:
		Net._login_fail(id, "no_character", "That character isn't on this account.")
		return
	if _is_online(character):   # in any zone
		Net._login_fail(id, "already_online", "%s is in the world right now and can't be deleted." % character.capitalize())
		return
	var stamp := int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(Net.DELETED_DIR)
	if FileAccess.file_exists(Net._character_path(key)):
		if DirAccess.rename_absolute(Net._character_path(key), "%s/%s_%d_character_stats.json" % [Net.DELETED_DIR, key, stamp]) != OK:
			Net._login_fail(id, "server_error", "The server could not delete %s." % character.capitalize())
			return
	if FileAccess.file_exists(Net._auth_path(key)):
		DirAccess.rename_absolute(Net._auth_path(key), "%s/%s_%d_auth.json" % [Net.DELETED_DIR, key, stamp])
	var data := _read_account(account)
	data["characters"].erase(character)
	_write_account(account, data)
	_owner_of.erase(character)
	Net._slog("Account %s deleted character %s (kept in deleted/) — peer %d." % [account, key, id])
	Net._audit("DELETE", Net.peer_ip(id), character.capitalize(), "account " + account)
	_reply(id, "deleted", "%s was deleted." % character.capitalize(), account)


# Brings a character made before accounts (its own name + password) into this account.
func _attach_character(id: int, account: String, character: String, character_password: String) -> void:
	var key := _character_key(character)
	if character.is_empty() or not FileAccess.file_exists(Net._character_path(key)):
		Net._login_fail(id, "no_character", "There is no character by that name on this server.")
		return
	var owner := owner_of(character)
	if owner == account:
		_reply(id, "attached", "%s is already on this account." % character.capitalize(), account)
		return
	if not owner.is_empty():
		Net._login_fail(id, "account_character", "%s already belongs to another account." % character.capitalize())
		return
	if (_read_account(account)["characters"] as Array).size() >= MAX_CHARACTERS:
		Net._login_fail(id, "account_full", "This account already has %d characters." % MAX_CHARACTERS)
		return
	if not FileAccess.file_exists(Net._auth_path(key)):
		Net._login_fail(id, "no_password", "%s has no password, so it can't be claimed. Ask the server owner to add it." % character.capitalize())
		return
	if not Net._check_access(id, key, character_password):
		return
	add_character(account, character)
	Net._slog("Account %s claimed character %s — peer %d." % [account, key, id])
	Net._audit("ACCOUNT CLAIM", Net.peer_ip(id), character.capitalize(), "account " + account)
	_reply(id, "attached", "%s was added to your account." % character.capitalize(), account)


# One-time move of old characters into accounts (see the header). Logs what it did, then renames the file with the
# plain-text passwords stripped so it never runs twice.
func _run_import() -> void:
	var plan = JSON.parse_string(FileAccess.get_file_as_string(IMPORT_FILE))
	if typeof(plan) != TYPE_DICTIONARY or typeof(plan.get("accounts")) != TYPE_ARRAY:
		Net._slog_err("Account import: %s isn't valid JSON with an \"accounts\" list — skipped." % ProjectSettings.globalize_path(IMPORT_FILE))
		return
	for entry in plan["accounts"]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var account := Net.sanitize_name(str(entry.get("account", "")))
		if account.is_empty():
			Net._slog_err("Account import: bad account name '%s' — skipped." % entry.get("account", ""))
			continue
		var data := _read_account(account)
		if data.is_empty():
			data = {"name": account, "characters": [], "created": int(Time.get_unix_time_from_system())}
			if entry.has("password_of"):
				var auth = JSON.parse_string(FileAccess.get_file_as_string(Net._auth_path(_character_key(Net.sanitize_name(str(entry["password_of"]))))))
				if typeof(auth) != TYPE_DICTIONARY:
					Net._slog_err("Account import: %s has no password file to copy for account %s — skipped." % [entry["password_of"], account])
					continue
				data["salt"] = str(auth.get("salt", ""))
				data["hash"] = str(auth.get("hash", ""))
			elif str(entry.get("password", "")).length() >= Net.MIN_PASSWORD_LENGTH:
				data["salt"] = Crypto.new().generate_random_bytes(16).hex_encode()
				data["hash"] = Net._hash_password(str(entry["password"]), data["salt"])
			else:
				Net._slog_err("Account import: account %s needs a \"password\" (%d+ characters) or \"password_of\" — skipped." % [account, Net.MIN_PASSWORD_LENGTH])
				continue
		for raw in entry.get("characters", []):
			var character := Net.sanitize_name(str(raw))
			if character.is_empty() or not FileAccess.file_exists(Net._character_path(_character_key(character))):
				Net._slog_err("Account import: no character '%s' on this server — not added to %s." % [raw, account])
				continue
			var owner := owner_of(character)
			if not owner.is_empty() and owner != account:
				Net._slog_err("Account import: %s already belongs to account %s — not added to %s." % [character, owner, account])
				continue
			if (data["characters"] as Array).size() >= MAX_CHARACTERS:
				Net._slog_err("Account import: %s is full — %s not added." % [account, character])
				continue
			if not (data["characters"] as Array).has(character):
				data["characters"].append(character)
			_owner_of[character] = account
		if _write_account(account, data):
			Net._slog("Account import: %s now holds %s." % [account, ", ".join(data["characters"])])
		entry.erase("password")
	var done := "%s/import_done_%d.json" % [ACCOUNT_DIR, int(Time.get_unix_time_from_system())]
	Net._write_file_atomic(done, JSON.stringify(plan, "\t"))
	DirAccess.remove_absolute(IMPORT_FILE)
	Net._slog("Account import finished; the plan (without passwords) is kept as %s." % done.get_file())
