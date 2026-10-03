extends Node
## Autoload "Voice": proximity voice chat, walkie-talkies, and the voice tricks the forest plays.
##
## Capture: the mic plays on a muted "VoiceMic" bus whose AudioEffectCapture is drained every
## frame, box-filtered down to 16 kHz mono, noise-gated (silence is never sent) and cut into
## 20 ms frames of 8-bit mu-law (~16 KB/s per talker). Frames go to every peer as unreliable_ordered
## RPCs on their own channel; a client's frames are relayed by the host, which also turns every
## talker's loudness into Noise for the monsters.
## Playback: an AudioStreamPlayer3D + generator on each friend's Head (audible to ~28 m), and, for
## walkie owners, a non-positional radio player per friend on the "Walkie" bus.
##
## Keys: M toggles the mic, hold V to talk on the walkie (needs a "walkie" in Team inventory;
## works even while muted). Hooks: level_of(), is_talking(), play_mimic(), play_whisper(),
## mimic_all.rpc(); signals mute_changed / walkie_changed for the HUD.
## Debug: `-- --fake-mic` feeds a synthetic voice instead of the mic, `--fake-walkie` also keys
## the walkie on and off every two seconds and pretends everyone owns one.

signal mute_changed(muted: bool)
signal walkie_changed(transmitting: bool)

const Codec := preload("res://scripts/voice/codec.gd")
const Synth := preload("res://scripts/voice/synth.gd")

const RATE := 16000
const FRAME := 320  # samples per packet: 20 ms, 50 packets/s (smaller = less delay)
const GATE_DB := -40.0  # frames quieter than this are silence
# Latency budget on the receiving end. Every queued sample is delay, so keep the queue short:
const JITTER_START_S := 0.04  # cushion at the start of a burst (or after running dry)
const JITTER_HIGH_S := 0.10  # above this, incoming frames are skipped until it drains back
const JITTER_MAX_S := 0.20  # above this, the queue is thrown away
const AGC_TARGET := 0.35  # incoming voice is levelled towards this RMS...
const AGC_MAX_GAIN := 6.0  # ...but quiet mics are boosted at most this much
const GATE_HOLD := 0.35  # keep sending this long after the voice drops (word endings)
const HEAR_RANGE := 30.0
const TALK_TIMEOUT := 0.25
const WALKIE_CLEAR := 150.0
const WALKIE_CRACKLE := 350.0
const WALKIE_MAX := 500.0
const WALKIE_NOISE := 12.0
const NOISE_INTERVAL := 0.25
const RING := RATE * 8  # mimicry memory: 8 s of speech per friend
const FLAG_WALKIE := 1

var muted := false
var transmitting := false  ## this peer is holding the walkie button

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _beep_down: AudioStreamWAV
var _beep_up: AudioStreamWAV
var _rng := RandomNumberGenerator.new()

var _fake_mic := false
var _fake_walkie := false
var _fake_t := 0.0
var _fake_acc := 0.0

var _rs_ratio := 3.0  # mix rate / RATE
var _rs_pos := 0.0
var _rs_acc := 0.0
var _rs_n := 0
var _pending := PackedFloat32Array()  # captured 16 kHz samples not yet framed
var _gate_until := 0.0

## peer id -> {"target", "level", "peak", "last", "rec" (recent speech), "agc",
##   "p3d", "p3d_last", "wk", "wk_last", "wk_open", "wk_heard", "wk_dist"}
var _peers := {}
var _map := {}
var _map_frame := -1
var _noise_timer := 0.0
var _debug_timer := 0.0
var _stats := {"sent": 0, "recv": 0, "noise": 0, "walkie": 0, "skipped": 0, "cleared": 0,
	"queued_ms": 0.0, "age_ms": 0.0, "mic_ms": 0.0}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_fake_walkie = args.has("--fake-walkie")
	_fake_mic = args.has("--fake-mic") or _fake_walkie
	_bind("voice_mute", KEY_M)
	_bind("walkie", KEY_V)
	_bind("voice_ptt", KEY_C)  # push-to-talk key, when Settings.push_to_talk is on
	_setup_buses()
	_beep_down = Synth.beep_down()
	_beep_up = Synth.beep_up()
	_hiss = AudioStreamPlayer.new()
	_hiss.stream = Synth.hiss()
	_hiss.bus = "Walkie"
	_hiss.volume_db = -80.0
	add_child(_hiss)
	multiplayer.peer_disconnected.connect(_forget)


# --- public API -------------------------------------------------------------------


## Any peer: how loud this friend is talking right now (0..1, smoothed).
func level_of(peer_id: int) -> float:
	return _peers[peer_id]["level"] if _peers.has(peer_id) else 0.0


## Any peer: is this friend's voice coming through right now (for a speaking indicator)?
func is_talking(peer_id: int) -> bool:
	return _peers.has(peer_id) and _now() - _peers[peer_id]["last"] < TALK_TIMEOUT


## This peer only: play a few seconds of a friend's recent speech from `pos`, a bit lower and
## echoey (the hag mimicking them). Falls back to a whisper if we never heard them talk.
func play_mimic(peer_id: int, pos: Vector3) -> void:
	var clip := PackedFloat32Array()
	if _peers.has(peer_id) and (_peers[peer_id]["rec"] as PackedFloat32Array).size() >= RATE * 1.5:
		clip = _ring_chunk(_peers[peer_id], _rng.randf_range(1.5, 4.0))
	if clip.is_empty():
		play_whisper(pos)
		return
	clip = Synth.faded(Synth.normalized(clip, 0.8))
	_spatial_one_shot(Synth.wav(clip), pos, _rng.randf_range(0.86, 0.94), 2.0)


## This peer only: an unintelligible whisper from `pos` (sanity hallucinations).
func play_whisper(pos: Vector3) -> void:
	_spatial_one_shot(Synth.whisper(_rng), pos, _rng.randf_range(0.85, 1.1), 0.0)


## Host: `Voice.mimic_all.rpc(peer_id, pos)` makes everyone hear that friend's voice from `pos`.
@rpc("authority", "call_local", "reliable")
func mimic_all(peer_id: int, pos: Vector3) -> void:
	play_mimic(peer_id, pos)


# --- main loop --------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("voice_mute") and not event.is_echo():
		muted = not muted
		mute_changed.emit(muted)


func _process(delta: float) -> void:
	if not _connected():
		if _mic_player != null or not _peers.is_empty() or transmitting:
			_shutdown()
		return
	var now := _now()
	var me := multiplayer.get_unique_id()
	var players := _players()
	_sample_ping()
	_start_mic()
	_update_ptt(players, me)
	_read_input(delta)
	_send_frames(me, now)
	_update_playback(players, me, now, delta)
	_noise_timer += delta
	if _noise_timer >= NOISE_INTERVAL:
		_noise_timer = 0.0
		_emit_noises(players, me, now)
	if _fake_mic:
		_debug_timer += delta
		if _debug_timer >= 5.0:
			_debug_timer = 0.0
			print("[voice] me=%d sent=%d recv=%d noise=%d walkie_rx=%d queue=%.0fms age=%.0fms skip=%d clear=%d" % [
				me, _stats["sent"], _stats["recv"], _stats["noise"], _stats["walkie"], _stats["queued_ms"],
				_stats["age_ms"], _stats["skipped"], _stats["cleared"]
			])


# --- capture and sending ----------------------------------------------------------


func _start_mic() -> void:
	if _mic_player != null or _fake_mic or DisplayServer.get_name() == "headless":
		return
	_rs_ratio = AudioServer.get_mix_rate() / RATE
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VoiceMic"
	add_child(_mic_player)
	_mic_player.play()


## Android: the mic permission arrived after the mic was started, so start it again.
func restart_mic() -> void:
	if _mic_player == null:
		return
	_mic_player.stop()
	_mic_player.play()


func _read_input(delta: float) -> void:
	if _fake_mic:
		_fake_acc += delta * RATE
		var n := int(_fake_acc)
		_fake_acc -= n
		for i in n:
			_fake_t += 1.0 / RATE
			_pending.append(_fake_sample(_fake_t))
		return
	if _capture == null or _mic_player == null:
		return
	var avail := _capture.get_frames_available()
	_stats["mic_ms"] = 1000.0 * avail / AudioServer.get_mix_rate()
	if avail <= 0:
		return
	for f in _capture.get_buffer(avail):
		_rs_acc += (f.x + f.y) * 0.5
		_rs_n += 1
		_rs_pos += 1.0
		if _rs_pos >= _rs_ratio:
			_rs_pos -= _rs_ratio
			_pending.append(_rs_acc / _rs_n)
			_rs_acc = 0.0
			_rs_n = 0
	if _pending.size() > RATE:  # we hitched badly; drop the backlog rather than lag forever
		_pending = _pending.slice(_pending.size() - FRAME * 2)


func _send_frames(me: int, now: float) -> void:
	while _pending.size() >= FRAME:
		var frame := _pending.slice(0, FRAME)
		_pending = _pending.slice(FRAME)
		var db := linear_to_db(maxf(Codec.rms(frame), 0.00001))
		if db > GATE_DB:
			_gate_until = now + GATE_HOLD
		var ptt_ok: bool = not Settings.push_to_talk or Input.is_action_pressed("voice_ptt")
		var speaking := now < _gate_until and not muted and ptt_ok
		if not (speaking or transmitting):
			continue
		var level := _db_to_level(db)
		_note_level(me, level, now)
		if db > GATE_DB:
			_record(me, frame)
		if multiplayer.get_peers().is_empty():
			continue
		var stamp := _wall_ms() & 0xFFFF
		var packet := PackedByteArray([FLAG_WALKIE if transmitting else 0, int(level * 255.0),
			stamp & 0xFF, stamp >> 8])
		packet.append_array(Codec.encode(frame))
		_voice_frame.rpc(packet)
		_stats["sent"] += 1


func _update_ptt(players: Dictionary, me: int) -> void:
	var want := false
	if players.has(me) and _has_walkie(me) and Team.is_alive(me):
		if _fake_walkie:
			want = fmod(_now(), 4.0) < 2.0
		else:
			want = Input.is_action_pressed("walkie") and not _typing()
	if want == transmitting:
		return
	transmitting = want
	walkie_changed.emit(want)
	_one_shot(_beep_down if want else _beep_up, -10.0)  # our own handset
	if not multiplayer.get_peers().is_empty():
		_walkie_key.rpc(want)


## Synthetic speech for --fake-mic: 2.6 s of babble, a pause, alternating quiet and shouting.
func _fake_sample(t: float) -> float:
	var cycle := fmod(t, 4.0)
	if cycle > 2.6:
		return randf_range(-0.002, 0.002)
	var loud := 0.06 if int(t / 4.0) % 2 == 0 else 0.5
	var syl := absf(sin(cycle * PI * 3.0))
	var ph := TAU * 170.0 * t
	return loud * syl * (sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.1)


# --- receiving --------------------------------------------------------------------


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_frame(packet: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if packet.size() < 5 or packet.size() > FRAME + 4 or sender == multiplayer.get_unique_id():
		return
	_stats["recv"] += 1
	# Sender's clock: only meaningful when both run on one machine (the latency test).
	var age := ((_wall_ms() & 0xFFFF) - (packet[2] | packet[3] << 8)) & 0xFFFF
	_stats["age_ms"] = lerpf(_stats["age_ms"], float(age), 0.1)
	var now := _now()
	var samples := Codec.decode(packet, 4)
	_note_level(sender, packet[1] / 255.0, now)
	samples = _level_up(sender, samples)
	if Codec.rms(samples) > db_to_linear(GATE_DB):
		_record(sender, samples)
	var players := _players()
	_play_proximity(sender, samples, players, now)
	if packet[0] & FLAG_WALKIE:
		_play_walkie(sender, samples, players, now)


@rpc("any_peer", "call_remote", "reliable")
func _walkie_key(down: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var st := _state(sender)
	st["wk_open"] = down
	var players := _players()
	if not _can_hear_walkie(sender, players):
		return
	var d := _walkie_distance(sender, players)
	if d > WALKIE_MAX:
		return
	st["wk_heard"] = _now()
	st["wk_dist"] = d
	_one_shot(_beep_down if down else _beep_up, -2.0)


func _play_proximity(sender: int, samples: PackedFloat32Array, players: Dictionary, now: float) -> void:
	var head := _head_of(players.get(sender))
	if head == null or _listener_pos().distance_to(head.global_position) > HEAR_RANGE:
		return
	var st := _state(sender)
	var p3d: AudioStreamPlayer3D = null
	if is_instance_valid(st["p3d"]):
		p3d = st["p3d"]
	if p3d == null or p3d.get_parent() != head:
		if p3d != null:
			p3d.queue_free()
		p3d = AudioStreamPlayer3D.new()
		p3d.name = "VoicePlayer"
		p3d.stream = _generator()
		p3d.bus = "Voice"
		p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # _update_playback fades it
		p3d.max_distance = HEAR_RANGE
		p3d.attenuation_filter_cutoff_hz = 20500.0
		head.add_child(p3d)
		st["p3d"] = p3d
		st["p3d_last"] = -10.0
	_push(p3d, samples, st, "p3d_last", now)


func _play_walkie(sender: int, samples: PackedFloat32Array, players: Dictionary, now: float) -> void:
	if not _can_hear_walkie(sender, players):
		return
	var d := _walkie_distance(sender, players)
	if d > WALKIE_MAX:
		return
	var st := _state(sender)
	st["wk_open"] = true
	st["wk_heard"] = now
	st["wk_dist"] = d
	_stats["walkie"] += 1
	var out := _degrade(samples, d)
	if out.is_empty():
		return
	var wk: AudioStreamPlayer = null
	if is_instance_valid(st["wk"]):
		wk = st["wk"]
	else:
		wk = AudioStreamPlayer.new()
		wk.stream = _generator()
		wk.bus = "Walkie"
		add_child(wk)
		st["wk"] = wk
		st["wk_last"] = -10.0
	_push(wk, out, st, "wk_last", now)


## Radio damage by distance: louder and squashed, then hiss, crackle and bit-crush, then dropouts.
func _degrade(samples: PackedFloat32Array, d: float) -> PackedFloat32Array:
	if d > WALKIE_CRACKLE:
		var lost := (d - WALKIE_CRACKLE) / (WALKIE_MAX - WALKIE_CRACKLE)
		if _rng.randf() < 0.15 + lost * 0.7:
			return PackedFloat32Array()
	var bad := 1.0 - _quality(d)
	var hiss := bad * 0.08
	var crackle := bad * bad * 0.01
	var steps := lerpf(128.0, 8.0, bad)
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		var s := roundf(clampf(samples[i] * 1.6, -1.0, 1.0) * steps) / steps
		s += _rng.randf_range(-hiss, hiss)
		if _rng.randf() < crackle:
			s += _rng.randf_range(-0.7, 0.7)
		out[i] = clampf(s, -1.0, 1.0)
	return out


## 1 = clear, falls through the crackly band, ~0.1 at the edge of range.
func _quality(d: float) -> float:
	if d <= WALKIE_CLEAR:
		return 1.0
	if d <= WALKIE_CRACKLE:
		return lerpf(1.0, 0.55, (d - WALKIE_CLEAR) / (WALKIE_CRACKLE - WALKIE_CLEAR))
	return lerpf(0.55, 0.1, clampf((d - WALKIE_CRACKLE) / (WALKIE_MAX - WALKIE_CRACKLE), 0.0, 1.0))


func _push(player: Node, samples: PackedFloat32Array, st: Dictionary, key: String, now: float) -> void:
	if not player.is_inside_tree():
		return
	if not bool(player.get("playing")):
		player.call("play")
	var pb := player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if pb == null:
		return
	# Godot rounds the generator's buffer up to a power of two, so measure its real size once
	# (while it's empty) instead of trusting buffer_length.
	var cap_key := key + "_cap"
	if not st.has(cap_key):
		st[cap_key] = pb.get_frames_available()
	var queued: int = int(st[cap_key]) - pb.get_frames_available()
	_stats["queued_ms"] = 1000.0 * queued / RATE
	if queued > int(RATE * JITTER_MAX_S):
		pb.clear_buffer()  # way behind (a hitch): jump back to live
		queued = 0
		_stats["cleared"] += 1
	elif queued > int(RATE * JITTER_HIGH_S):
		_stats["skipped"] += 1  # a bit behind (clock drift, a burst): drop this 20 ms to catch up
		st[key] = now
		return
	if queued < FRAME / 2:  # a new burst, or we ran dry: a small cushion against jitter
		var gap := PackedVector2Array()
		gap.resize(int(RATE * JITTER_START_S))
		if pb.can_push_buffer(gap.size()):
			pb.push_buffer(gap)
	st[key] = now
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		frames[i] = Vector2(samples[i], samples[i])
	if pb.can_push_buffer(frames.size()):
		pb.push_buffer(frames)


## Connection and voice numbers for the F3 overlay and the session log.
func net_stats() -> Dictionary:
	var lo := 0
	var hi := 0
	var avg := 0
	if not _pings.is_empty():
		lo = _pings.min()
		hi = _pings.max()
		for v in _pings:
			avg += v
		avg /= _pings.size()
	var bw: Vector2 = Net.bandwidth()
	return {
		"ping": _ping, "ping_min": lo, "ping_avg": avg, "ping_max": hi,
		"out_kbs": bw.x / 1024.0, "in_kbs": bw.y / 1024.0,
		"mic_ms": int(_stats["mic_ms"]), "queue_ms": int(_stats["queued_ms"]),
		"sent": _stats["sent"], "recv": _stats["recv"], "skip": _stats["skipped"], "clear": _stats["cleared"],
	}


## Two lines for the debug overlay (F3): where the delay sits.
func debug_line() -> String:
	var n := net_stats()
	var net := "ping %d ms (10 s: min %d avg %d max %d) · net out %.0f KB/s in %.0f KB/s" % [
		n["ping"], n["ping_min"], n["ping_avg"], n["ping_max"], n["out_kbs"], n["in_kbs"]]
	var voice := "voice: mic backlog %d ms · play queue %d ms · sent %d recv %d · skip %d clear %d" % [
		n["mic_ms"], n["queue_ms"], n["sent"], n["recv"], n["skip"], n["clear"]]
	return net + "\n" + voice


var _ping := -1
var _pings: Array[int] = []  # the last ~10 s of round-trip times, one per frame


## Every frame while connected: the round trip to the host (or, on the host, to the first client).
func _sample_ping() -> void:
	_ping = -1
	var mp := multiplayer.multiplayer_peer
	if not mp is ENetMultiplayerPeer:
		return
	var peers := multiplayer.get_peers()
	var target := 1 if not multiplayer.is_server() else (peers[0] if not peers.is_empty() else 0)
	if target == 0:
		return
	var pr := (mp as ENetMultiplayerPeer).get_peer(target)
	if pr == null:
		return
	_ping = int(pr.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	_pings.append(_ping)
	if _pings.size() > 600:
		_pings = _pings.slice(_pings.size() - 600)


# --- per-frame playback and noise -------------------------------------------------


func _update_playback(players: Dictionary, me: int, now: float, delta: float) -> void:
	var listener := _listener_pos()
	var hiss_q := -1.0
	var k := 1.0 - exp(-delta * 10.0)
	for peer in _peers:
		var st: Dictionary = _peers[peer]
		var talking := now - float(st["last"]) < TALK_TIMEOUT
		st["level"] = lerpf(st["level"], st["target"] if talking else 0.0, k)
		var pitch := _pitch_of(peer, now)
		if is_instance_valid(st["p3d"]):
			var p3d: AudioStreamPlayer3D = st["p3d"]
			p3d.pitch_scale = pitch
			p3d.volume_db = _proximity_db(listener.distance_to(p3d.global_position))
		if is_instance_valid(st["wk"]):
			var wk: AudioStreamPlayer = st["wk"]
			wk.pitch_scale = pitch
		if st["wk_open"] and now - float(st["wk_heard"]) > 1.0:
			st["wk_open"] = false  # lost the key-up, or walked out of range
		if st["wk_open"] and peer != me and _can_hear_walkie(peer, players):
			hiss_q = maxf(hiss_q, _quality(st["wk_dist"]))
	if hiss_q < 0.0:
		if _hiss.playing:
			_hiss.stop()
		return
	_hiss.volume_db = lerpf(-30.0, -14.0, 1.0 - hiss_q)
	if not _hiss.playing:
		_hiss.play()


## Tripping or passed-out friends sound warped to everyone: a wobbling pitch, 0.7..1.3.
func _pitch_of(peer: int, now: float) -> float:
	var s := Team.status_of(peer)
	if s != Team.Status.TRIPPING and s != Team.Status.PASSED_OUT:
		return 1.0
	var wobble := sin(now * 2.3 + peer) * 0.7 + sin(now * 0.9 + peer * 2.0) * 0.3
	return clampf(1.0 + 0.3 * wobble, 0.7, 1.3)


## Full volume within 6 m, fading to silence by ~30 m.
func _proximity_db(d: float) -> float:
	var g := pow(clampf(1.0 - (d - 6.0) / (HEAR_RANGE - 6.0), 0.0, 1.0), 1.3)
	return linear_to_db(maxf(g, 0.0001))


## Host: every talker is a noise at their body; every peer: an incoming walkie is a noise at us.
func _emit_noises(players: Dictionary, me: int, now: float) -> void:
	var walkie_heard := false
	for peer in _peers:
		var st: Dictionary = _peers[peer]
		if multiplayer.is_server() and now - float(st["last"]) < TALK_TIMEOUT + NOISE_INTERVAL \
				and players.has(peer):
			_noise(players[peer].global_position, _metres(st["peak"]), peer)
		st["peak"] = 0.0
		if peer != me and st["wk_open"] and now - float(st["wk_heard"]) < 0.5:
			walkie_heard = true
	if walkie_heard and players.has(me):
		_noise(players[me].global_position, WALKIE_NOISE, me)


func _noise(pos: Vector3, loudness: float, peer: int) -> void:
	_stats["noise"] += 1
	# Through the tree: the autoload's name "Noise" is shadowed by Godot's built-in Noise class.
	var noise := get_node_or_null("/root/Hearing")
	if noise != null:
		noise.call("emit", pos, loudness, peer)


## Voice level 0..1 to how far a monster hears it: quiet talk 8 m, normal 15 m, shouting 35 m.
func _metres(level: float) -> float:
	if level < 0.5:
		return lerpf(8.0, 15.0, level / 0.5)
	return lerpf(15.0, 35.0, (level - 0.5) / 0.5)


func _db_to_level(db: float) -> float:
	return clampf((db + 45.0) / 36.0, 0.0, 1.0)  # -45 dBFS = 0, -9 dBFS = 1


## Automatic gain: quiet mics get boosted (up to AGC_MAX_GAIN), loud ones left alone, and a soft
## clip stops the boost from distorting. The gain moves slowly so it doesn't pump.
func _level_up(peer: int, samples: PackedFloat32Array) -> PackedFloat32Array:
	var st := _state(peer)
	var r := Codec.rms(samples)
	if r > db_to_linear(GATE_DB):
		var want := clampf(AGC_TARGET / maxf(r, 0.0001), 1.0, AGC_MAX_GAIN)
		st["agc"] = lerpf(float(st["agc"]), want, 0.15)
	var g: float = st["agc"]
	if g <= 1.01:
		return samples
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		var x := samples[i] * g
		out[i] = x / (1.0 + absf(x) * 0.6)  # soft clip
	return out


func _note_level(peer: int, level: float, now: float) -> void:
	var st := _state(peer)
	st["target"] = level
	st["last"] = now
	st["peak"] = maxf(st["peak"], level)


# --- mimicry memory ---------------------------------------------------------------


func _record(peer: int, samples: PackedFloat32Array) -> void:
	# A plain append-and-trim buffer: native array ops only, trimmed in big steps.
	var st := _state(peer)
	var buf: PackedFloat32Array = st["rec"]
	buf.append_array(samples)
	if buf.size() > RING + RATE * 2:
		buf = buf.slice(buf.size() - RING)
	st["rec"] = buf


func _ring_chunk(st: Dictionary, seconds: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = st["rec"]
	var n := mini(int(seconds * RATE), buf.size())
	var start := _rng.randi_range(0, buf.size() - n)
	return buf.slice(start, start + n)


# --- helpers ----------------------------------------------------------------------


func _spatial_one_shot(stream: AudioStream, pos: Vector3, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "VoiceFx"
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 5.0
	p.max_distance = 40.0
	add_child(p)
	p.global_position = pos
	p.play()
	_free_later(p, stream.get_length() / pitch + 0.5)


func _one_shot(stream: AudioStream, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Walkie"
	p.volume_db = db
	add_child(p)
	p.play()
	_free_later(p, stream.get_length() + 0.3)


func _free_later(node: Node, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)


func _generator() -> AudioStreamGenerator:
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = JITTER_MAX_S * 1.5
	return g


func _state(peer: int) -> Dictionary:
	if not _peers.has(peer):
		_peers[peer] = {
			"target": 0.0, "level": 0.0, "peak": 0.0, "last": -10.0,
			"rec": PackedFloat32Array(), "agc": 1.0,
			"p3d": null, "p3d_last": -10.0,
			"wk": null, "wk_last": -10.0, "wk_open": false, "wk_heard": -10.0, "wk_dist": 0.0,
		}
	return _peers[peer]


## peer id -> player body, rebuilt at most once per frame.
func _players() -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame == _map_frame:
		return _map
	_map_frame = frame
	_map = {}
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D and not p.is_queued_for_deletion():
			_map[int(p.get("peer_id"))] = p
	return _map


func _head_of(body: Variant) -> Node3D:
	if body == null or not is_instance_valid(body):
		return null
	var head: Variant = body.get("head")
	return head if head is Node3D and is_instance_valid(head) else null


func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	var me: Variant = _players().get(multiplayer.get_unique_id())
	return me.global_position if me != null else Vector3.ZERO


func _walkie_distance(sender: int, players: Dictionary) -> float:
	return players[sender].global_position.distance_to(players[multiplayer.get_unique_id()].global_position)


func _can_hear_walkie(sender: int, players: Dictionary) -> bool:
	var me := multiplayer.get_unique_id()
	return sender != me and players.has(sender) and players.has(me) and _has_walkie(me) \
			and _has_walkie(sender)


func _has_walkie(peer: int) -> bool:
	return _fake_walkie or Team.count(peer, "walkie") > 0


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _connected() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) \
			and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _forget(peer: int) -> void:
	if not _peers.has(peer):
		return
	for key in ["p3d", "wk"]:
		if is_instance_valid(_peers[peer][key]):
			_peers[peer][key].queue_free()
	_peers.erase(peer)


func _shutdown() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _capture != null:
		_capture.clear_buffer()
	for peer in _peers.keys():
		_forget(peer)
	_pending.clear()
	_gate_until = 0.0
	_hiss.stop()
	if transmitting:
		transmitting = false
		walkie_changed.emit(false)


func _bind(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


## Runtime buses: VoiceMic (muted, capture), Voice (proximity), Walkie (radio), VoiceFx (reverb).
func _setup_buses() -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.2  # drained every frame; only a long hitch fills it
	var mic := _bus("VoiceMic", [capture])
	AudioServer.set_bus_mute(mic, true)
	for i in AudioServer.get_bus_effect_count(mic):
		if AudioServer.get_bus_effect(mic, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(mic, i)
	_bus("Voice", [])
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 400.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 2800.0
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.45
	dist.pre_gain = 6.0
	dist.post_gain = -4.0
	_bus("Walkie", [hp, lp, dist])
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.7
	reverb.damping = 0.6
	reverb.wet = 0.3
	_bus("VoiceFx", [reverb])


func _bus(bus_name: String, effects: Array) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	for fx in effects:
		AudioServer.add_bus_effect(i, fx)
	return i


## Wall-clock milliseconds: comparable between two copies of the game on one machine.
func _wall_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
