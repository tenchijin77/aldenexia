# chat_channels.gd — The four chat channels (Say / Party / Zone / Tell): their commands,
# colors and line formats, in one place so the sender's local echo, the receiver's
# line (net.gd) and the dropdown in game_log_window.gd can never drift apart.
class_name ChatChannels

enum { SAY, PARTY, ZONE, TELL }

const NAMES := ["Say", "Party", "Zone", "Tell"]
const COMMANDS := ["/say", "/party", "/zone", "/tell"]
const COLORS := ["#ffe066", "#88ccff", "#ff9944", "#cc88ff"]  # yellow, blue, orange, purple

## /say is heard by players this close (meters) — a conversation, not a broadcast.
const SAY_RANGE := 10.0
const MAX_MESSAGE_LENGTH := 300


static func color(channel: int) -> Color:
	return Color.html(COLORS[channel])


# Player text goes into a RichTextLabel: escape "[" so a typed "[b]" or "[color=red]" is shown
# literally instead of being interpreted, and cap the length.
static func clean(text: String) -> String:
	return text.strip_edges().substr(0, MAX_MESSAGE_LENGTH).replace("[", "[lb]")


static func _wrap(channel: int, body: String) -> String:
	return "[color=%s]%s[/color]" % [COLORS[channel], body]


# Lines carry a language (Languages): "You say, in Khuzdul, '...'"; a received line is decoded and scrambled for whatever
# the local player doesn't understand (Languages.hear). Common gets no tag.
static func say_self(text: String, lang: String = "common") -> String:
	return _wrap(SAY, "You say%s, '%s'" % [Languages.tag(lang), text])


static func say_other(sender: String, message: String) -> String:
	var heard := _heard(message)
	return _wrap(SAY, "%s says%s, '%s'" % [sender, heard[0], heard[1]])


static func zone_self(text: String, lang: String = "common") -> String:
	return _wrap(ZONE, "You shout%s, '%s'" % [Languages.tag(lang), text])


static func zone_other(sender: String, message: String) -> String:
	var heard := _heard(message)
	return _wrap(ZONE, "%s shouts%s, '%s'" % [sender, heard[0], heard[1]])


static func party_self(text: String, lang: String = "common") -> String:
	return _wrap(PARTY, "[Party] You%s: %s" % [Languages.tag(lang), text])


static func party_other(sender: String, message: String) -> String:
	var heard := _heard(message)
	return _wrap(PARTY, "[Party] %s%s: %s" % [sender, heard[0], heard[1]])


static func tell_self(target: String, text: String, lang: String = "common") -> String:
	return _wrap(TELL, "You tell %s%s, '%s'" % [target, Languages.tag(lang), text])


static func tell_other(sender: String, message: String) -> String:
	var heard := _heard(message)
	return _wrap(TELL, "%s tells you%s, '%s'" % [sender, heard[0], heard[1]])


# [", in Khuzdul" or "", what the local player makes of it]
static func _heard(message: String) -> Array:
	var decoded := Languages.decode(message)
	return [Languages.tag(decoded[0]), Languages.hear(decoded[0], decoded[1])]
