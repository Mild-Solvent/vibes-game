extends RefCounted
## Voice codec helpers: 8-bit mu-law (one byte per 16 kHz sample = 16 KB/s) and frame loudness.

const MU := 255.0
const ENC_STEPS := 16384  # encode lookup resolution (14-bit linear in)

static var _enc := PackedByteArray()
static var _dec := PackedFloat32Array()


static func _tables() -> void:
	if not _dec.is_empty():
		return
	var log_mu := log(1.0 + MU)
	_enc.resize(ENC_STEPS)
	var half := (ENC_STEPS - 1) * 0.5
	for i in ENC_STEPS:
		var x := i / half - 1.0
		var y := signf(x) * log(1.0 + MU * absf(x)) / log_mu
		_enc[i] = clampi(roundi((y + 1.0) * 127.5), 0, 255)
	_dec.resize(256)
	for b in 256:
		var y := b / 127.5 - 1.0
		_dec[b] = signf(y) * (pow(1.0 + MU, absf(y)) - 1.0) / MU


## Floats (-1..1) to mu-law bytes.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	_tables()
	var half := (ENC_STEPS - 1) * 0.5
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = _enc[clampi(int((samples[i] + 1.0) * half), 0, ENC_STEPS - 1)]
	return out


## Mu-law bytes from `offset` on back to floats.
static func decode(data: PackedByteArray, offset := 0) -> PackedFloat32Array:
	_tables()
	var out := PackedFloat32Array()
	out.resize(maxi(data.size() - offset, 0))
	for i in out.size():
		out[i] = _dec[data[offset + i]]
	return out


## Root-mean-square level of a frame (0..1).
static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for s in samples:
		sum += s * s
	return sqrt(sum / samples.size())
