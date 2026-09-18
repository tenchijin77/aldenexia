# network_widget.gd — EverQuest-style network diagnostics window (F11).
# Draggable + persistent like every other HUD window (see buff_bar.gd for the
# reference pattern this copies: WindowPosition save/load, drag via
# _on_panel_gui_input). Unlike buff_bar/player_frame/etc., this widget is NOT
# spawned by player3d.gd's _spawn_hud_frames() — it's placed directly as a
# static node in the zone scene and manages its own show/hide via F11, so it
# exists (hidden) from scene start regardless of player state.
#
# All three stats are REAL, not approximated:
# - Latency: ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME) — ENet's own
#   continuously-updated round-trip time to the relevant remote peer (the
#   server, if we're a client; ENet maintains this automatically via its
#   ACK/keepalive protocol, no custom ping/pong needed).
# - Packet loss: ENetPacketPeer.get_statistic(PEER_PACKET_LOSS), scaled by
#   ENetPacketPeer.PACKET_LOSS_SCALE per Godot's documented convention.
# - Bandwidth: ENetConnection.pop_statistic(HOST_TOTAL_SENT_DATA /
#   HOST_TOTAL_RECEIVED_DATA) — host-level counters that reset on read
#   ("pop"), sampled once per second here to get a live bytes/sec (shown as
#   bits/sec) rate. This is real traffic through this machine's ENet host,
#   not a guess.
#
# On a HOST with multiple connected clients, per-peer RTT/packet-loss is
# shown for the first connected remote peer (multiplayer.get_peers()[0]) —
# there's no single meaningful "my latency" for a host with several peers at
# once; showing one real peer's numbers beats averaging or omitting.
extends CanvasLayer
class_name NetworkWidget

const POSITION_KEY := "network_widget"
const BANDWIDTH_SAMPLE_INTERVAL := 1.0
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 180.0
const MIN_HEIGHT := 110.0

var _dragging := false
var _resizing := false
var _bandwidth_accum_time := 0.0
var _last_bits_per_sec := 0.0

@onready var panel: Panel = $Panel
@onready var latency_value: Label = $Panel/Margin/VBox/LatencyRow/Value
@onready var loss_value: Label = $Panel/Margin/VBox/LossRow/Value
@onready var bandwidth_value: Label = $Panel/Margin/VBox/BandwidthRow/Value
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_network_widget"):
		panel.visible = not panel.visible


func _process(delta: float) -> void:
	if not panel.visible:
		return

	var mp_peer := multiplayer.multiplayer_peer
	if not (mp_peer is ENetMultiplayerPeer) or mp_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		status_label.text = "Not connected (single-player)"
		status_label.visible = true
		latency_value.text = "—"
		loss_value.text = "—"
		bandwidth_value.text = "—"
		latency_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		return

	status_label.visible = false
	var enet_peer: ENetMultiplayerPeer = mp_peer

	var remote_id: int = -1
	if not multiplayer.is_server():
		remote_id = 1  # server is always peer id 1
	else:
		var connected: Array = multiplayer.get_peers()
		if not connected.is_empty():
			remote_id = connected[0]

	if remote_id != -1:
		var remote_packet_peer: ENetPacketPeer = enet_peer.get_peer(remote_id)
		if remote_packet_peer:
			var rtt_ms: float = remote_packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			var loss_raw: float = remote_packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)
			var loss_pct: float = (loss_raw / float(ENetPacketPeer.PACKET_LOSS_SCALE)) * 100.0

			latency_value.text = "%d ms" % int(rtt_ms)
			latency_value.add_theme_color_override("font_color", _latency_color(rtt_ms))
			loss_value.text = "%.1f%%" % loss_pct
	else:
		latency_value.text = "—"
		loss_value.text = "—"

	_bandwidth_accum_time += delta
	if _bandwidth_accum_time >= BANDWIDTH_SAMPLE_INTERVAL:
		var host: ENetConnection = enet_peer.get_host()
		if host:
			var sent: int = host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
			var received: int = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			_last_bits_per_sec = float(sent + received) * 8.0 / _bandwidth_accum_time
		_bandwidth_accum_time = 0.0
	bandwidth_value.text = _format_bits_per_sec(_last_bits_per_sec)


func _latency_color(rtt_ms: float) -> Color:
	if rtt_ms <= 100.0:
		return Color(0.4, 0.95, 0.4)   # green
	elif rtt_ms <= 500.0:
		return Color(0.95, 0.85, 0.3)  # yellow
	else:
		return Color(0.95, 0.3, 0.3)   # red


func _format_bits_per_sec(bps: float) -> String:
	if bps >= 1_000_000.0:
		return "%.2f Mbps" % (bps / 1_000_000.0)
	elif bps >= 1_000.0:
		return "%.1f Kbps" % (bps / 1_000.0)
	return "%d bps" % int(bps)


# ===== DRAGGABLE PANEL (same pattern as buff_bar.gd) =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			panel.offset_right  = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
		elif _dragging:
			panel.offset_left   += event.relative.x
			panel.offset_top    += event.relative.y
			panel.offset_right  += event.relative.x
			panel.offset_bottom += event.relative.y
