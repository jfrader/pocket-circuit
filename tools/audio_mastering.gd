class_name AudioMastering
extends RefCounted

## Build-time loudness mastering for the baked music loops.
##
## Mirrors the Gamestruments 0.1.3 master: measure integrated loudness with
## ITU-R BS.1770-4, apply a single static gain to reach TARGET_LUFS, then
## true-peak limit to a -1.0 dBTP ceiling. Pure GDScript, deterministic, and
## independent of Godot's mixer. Used by `tools/generate_audio.gd` and the
## audio-loudness test so the same measurement code guards both.

# --- Loudness target and true-peak ceiling ---------------------------------

const TARGET_LUFS := -14.0
const CEILING_DBTP := -1.0
const GUARD_MARGIN_DB := 0.1  # limiter targets ceiling - guard; hard clamp at ceiling

# --- ITU-R BS.1770-4 K-weighting -------------------------------------------
# Stage 1 is a high-shelf boost, stage 2 the RLB high-pass. Coefficients are
# the standard values from the spec, expressed as biquads at the sample rate.

const SHELF_F0 := 1681.974450955533
const SHELF_GAIN_DB := 3.999843853973347
const SHELF_Q := 0.7071752369554196
const RLB_F0 := 38.13547087602444
const RLB_Q := 0.5003270373238773

# --- Integrated-loudness gating (BS.1770-4) --------------------------------

const BLOCK_SECONDS := 0.4    # 400 ms gating blocks
const HOP_SECONDS := 0.1      # 100 ms hop = 75% overlap
const ABS_GATE_LUFS := -70.0  # discard blocks quieter than -70 LKFS
const REL_GATE_LU := -10.0    # discard blocks more than 10 LU below the gated mean
const LOUDNESS_OFFSET_DB := -0.691  # 10*log10 calibration for LKFS

const SILENCE_LUFS := -200.0
const LN_10 := 2.302585092994046

# --- True-peak interpolator -------------------------------------------------
# 4x polyphase windowed-sinc FIR. Linear, so the reconstructed peak is a linear
# function of the samples: bounding the interpolated envelope bounds the peak.
# Coefficients are derived once at class load from fixed constants (odd tap
# count per phase, Hann window, cutoff at the original Nyquist) and are
# identical on every run.

const UPSAMPLE := 4
const TAPS_PER_PHASE := 17  # odd

# --- True-peak limiter ------------------------------------------------------

const LOOKAHEAD_SECONDS := 0.004  # attack lookahead (input samples)
const RELEASE_SECONDS := 0.08     # gain release time constant

static var _phase_coefficients: Array[PackedFloat32Array] = []


static func _static_init() -> void:
	_phase_coefficients = _build_interpolator()


# --- Public API -------------------------------------------------------------

## Measures integrated loudness (ITU-R BS.1770-4) in LUFS of a mono signal.
static func measure_integrated_loudness(samples: PackedFloat32Array, sample_rate: int) -> float:
	if samples.size() < 2:
		return SILENCE_LUFS
	var weighted := _k_weight(samples, sample_rate)
	var block := roundi(float(sample_rate) * BLOCK_SECONDS)
	var hop := roundi(float(sample_rate) * HOP_SECONDS)
	var energies := PackedFloat32Array()
	var start := 0
	while start + block <= weighted.size():
		var sum := 0.0
		for i in range(start, start + block):
			var v := weighted[i]
			sum += v * v
		energies.append(sum / float(block))
		start += hop
	if energies.is_empty():
		return SILENCE_LUFS
	var abs_threshold := _lufs_to_energy(ABS_GATE_LUFS)
	var gated := PackedFloat32Array()
	for energy: float in energies:
		if energy > abs_threshold:
			gated.append(energy)
	if gated.is_empty():
		return SILENCE_LUFS
	var gated_mean := 0.0
	for energy: float in gated:
		gated_mean += energy
	gated_mean /= float(gated.size())
	var rel_threshold := gated_mean * pow(10.0, REL_GATE_LU / 10.0)
	var total := 0.0
	var count := 0
	for energy: float in gated:
		if energy > rel_threshold:
			total += energy
			count += 1
	if count == 0:
		return SILENCE_LUFS
	return LOUDNESS_OFFSET_DB + 10.0 * _log10(total / float(count))


## Measures the true peak (4x oversampled) of a mono signal in dBTP.
static func measure_true_peak_db(samples: PackedFloat32Array, sample_rate: int) -> float:
	var up := _upsample4(samples)
	var peak := 0.0
	for value: float in up:
		peak = maxf(peak, absf(value))
	if peak <= 0.0:
		return SILENCE_LUFS
	return 20.0 * _log10(peak)


## Masters a mono signal: static gain to TARGET_LUFS, then true-peak limit.
static func master(samples: PackedFloat32Array, sample_rate: int) -> PackedFloat32Array:
	var loudness := measure_integrated_loudness(samples, sample_rate)
	var gained := _apply_gain_db(samples, TARGET_LUFS - loudness)
	var limited := _true_peak_limit(gained, sample_rate)
	return limited


# --- K-weighting ------------------------------------------------------------

static func _k_weight(samples: PackedFloat32Array, sample_rate: int) -> PackedFloat32Array:
	var shelf := _biquad_coeffs_shelf(sample_rate)
	var highpass := _biquad_coeffs_highpass(sample_rate)
	return _apply_biquad(_apply_biquad(samples, shelf), highpass)


static func _biquad_coeffs_shelf(sample_rate: int) -> PackedFloat32Array:
	# High-shelf boost (RBJ cookbook), stage 1 of the K-weighting.
	var a := pow(10.0, SHELF_GAIN_DB / 40.0)
	var omega := TAU * SHELF_F0 / float(sample_rate)
	var sn := sin(omega)
	var cs := cos(omega)
	var alpha := sn / (2.0 * SHELF_Q)
	var beta := 2.0 * sqrt(a) * alpha
	var b0 := a * ((a + 1.0) + (a - 1.0) * cs + beta)
	var b1 := -2.0 * a * ((a - 1.0) + (a + 1.0) * cs)
	var b2 := a * ((a + 1.0) + (a - 1.0) * cs - beta)
	var a0 := (a + 1.0) - (a - 1.0) * cs + beta
	var a1 := 2.0 * ((a - 1.0) - (a + 1.0) * cs)
	var a2 := (a + 1.0) - (a - 1.0) * cs - beta
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0])


static func _biquad_coeffs_highpass(sample_rate: int) -> PackedFloat32Array:
	# RLB high-pass (RBJ cookbook), stage 2 of the K-weighting.
	var omega := TAU * RLB_F0 / float(sample_rate)
	var sn := sin(omega)
	var cs := cos(omega)
	var alpha := sn / (2.0 * RLB_Q)
	var b0 := (1.0 + cs) / 2.0
	var b1 := -(1.0 + cs)
	var b2 := (1.0 + cs) / 2.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cs
	var a2 := 1.0 - alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0])


static func _apply_biquad(samples: PackedFloat32Array, c: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in samples.size():
		var x0 := samples[i]
		var y0 := c[0] * x0 + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		out[i] = y0
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
	return out


# --- True-peak interpolator -------------------------------------------------

static func _build_interpolator() -> Array[PackedFloat32Array]:
	# Prototype lowpass: h[i] = (1/L) * sinc((i - center) / L) * Hann(i), cutoff
	# at the original Nyquist (normalized 1/(2L) of the output rate). Normalize
	# the total DC gain to L so each phase passes DC at unity.
	var total_taps := UPSAMPLE * TAPS_PER_PHASE
	var prototype := PackedFloat32Array()
	prototype.resize(total_taps)
	var center := float(total_taps - 1) * 0.5
	for i in total_taps:
		var x := (float(i) - center) / float(UPSAMPLE)
		var sinc_value := 1.0 if is_zero_approx(x) else sin(PI * x) / (PI * x)
		var window := 0.5 - 0.5 * cos(TAU * float(i) / float(total_taps - 1))
		prototype[i] = sinc_value * window / float(UPSAMPLE)
	var dc_gain := 0.0
	for value: float in prototype:
		dc_gain += value
	if dc_gain > 0.0:
		var scale := float(UPSAMPLE) / dc_gain
		for i in total_taps:
			prototype[i] *= scale
	var phases: Array[PackedFloat32Array] = []
	for p in UPSAMPLE:
		var phase := PackedFloat32Array()
		phase.resize(TAPS_PER_PHASE)
		for k in TAPS_PER_PHASE:
			phase[k] = prototype[p + UPSAMPLE * k]
		phases.append(phase)
	return phases


static func _upsample4(samples: PackedFloat32Array) -> PackedFloat32Array:
	var n := samples.size()
	var center_tap := (TAPS_PER_PHASE - 1) / 2
	var out := PackedFloat32Array()
	out.resize(n * UPSAMPLE)
	for m in out.size():
		var phase := m % UPSAMPLE
		var base := m / UPSAMPLE
		var coeffs: PackedFloat32Array = _phase_coefficients[phase]
		var acc := 0.0
		for k in TAPS_PER_PHASE:
			var index := base + center_tap - k
			if index >= 0 and index < n:
				acc += coeffs[k] * samples[index]
		out[m] = acc
	return out


# --- True-peak limiter ------------------------------------------------------

static func _true_peak_limit(samples: PackedFloat32Array, sample_rate: int) -> PackedFloat32Array:
	var ceiling := db_to_linear(CEILING_DBTP)
	var threshold := db_to_linear(CEILING_DBTP - GUARD_MARGIN_DB)
	var up := _upsample4(samples)
	var n := samples.size()
	var lookahead := maxi(1, roundi(sample_rate * LOOKAHEAD_SECONDS))
	# The interpolator's sub-filter spans center_tap samples on each side of an
	# input sample, so a peak at position p is fed by samples [p - d, p + d].
	# Looking ahead alone leaves the backward half unscaled; include both sides
	# in the window so the reduced gain covers every sample that feeds the peak.
	var group_delay := (TAPS_PER_PHASE - 1) / 2
	var release_step := 1.0 - exp(-1.0 / (RELEASE_SECONDS * float(sample_rate)))
	var out := samples.duplicate()
	var gain := 1.0
	for i in n:
		var m_start := maxi(0, (i - group_delay) * UPSAMPLE)
		var m_end := mini((i + lookahead) * UPSAMPLE, up.size())
		var window_peak := 0.0
		for m in range(m_start, m_end):
			window_peak = maxf(window_peak, absf(up[m]))
		var required := 1.0
		if window_peak > threshold:
			required = threshold / window_peak
		if required < gain:
			gain = required  # a deeper peak is approaching: attack instantly
		elif required >= 1.0:
			gain += (1.0 - gain) * release_step  # window clear: release slowly
		out[i] = samples[i] * gain
	for i in n:
		out[i] = clampf(out[i], -ceiling, ceiling)
	return out


# --- Helpers ----------------------------------------------------------------

static func _apply_gain_db(samples: PackedFloat32Array, gain_db: float) -> PackedFloat32Array:
	var linear := db_to_linear(gain_db)
	var out := samples.duplicate()
	for i in out.size():
		out[i] *= linear
	return out


static func _lufs_to_energy(lufs: float) -> float:
	return pow(10.0, (lufs - LOUDNESS_OFFSET_DB) / 10.0)


static func _log10(x: float) -> float:
	return log(x) / LN_10
