import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get referenceToneSupported => true;

web.AudioContext? _ctx;
final math.Random _rng = math.Random();

Future<web.AudioContext> _ensure() async {
  _ctx ??= web.AudioContext();
  await _ctx!.resume().toDart;
  return _ctx!;
}

/// Karplus-Strong plucked-string synthesis: a noise burst through a tuned
/// feedback delay line. The loop's low-pass makes high harmonics die first,
/// exactly like a real string, so each note sounds like a pluck — not a beep.
///
/// [brightness] 0..1 (higher = brighter pick), [decay] 0..1 (lower = faster
/// fade), [duration] seconds of audio to render.
Float32List _pluck(double freq, double duration,
    {double brightness = 0.55, double decay = 0.996}) {
  final sampleRate = _ctx!.sampleRate;
  final total = math.max(1, (duration * sampleRate).round());
  final out = Float32List(total);
  // Delay-line length sets the pitch.
  final period = math.max(2, (sampleRate / freq).round());
  final buf = List<double>.filled(period, 0.0);

  // Excitation: white noise shaped by a one-pole low-pass. Brightness controls
  // how much high-frequency content the "pick" injects into the string.
  var lpState = 0.0;
  final lpCoeff = 0.25 + 0.7 * brightness;
  for (var i = 0; i < period; i++) {
    final white = _rng.nextDouble() * 2 - 1;
    lpState += lpCoeff * (white - lpState);
    buf[i] = lpState;
  }

  // Loop: read a sample, then replace it with the average of itself and its
  // neighbour, damped. Averaging is the low-pass that models string loss.
  var idx = 0;
  for (var i = 0; i < total; i++) {
    final cur = buf[idx];
    out[i] = cur;
    final next = buf[(idx + 1) % period];
    buf[idx] = (cur + next) * 0.5 * decay;
    idx = (idx + 1) % period;
  }

  // Normalize to a comfortable level and add a fast release so the sample
  // never clicks when the source node stops.
  var peak = 0.0;
  for (final v in out) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  if (peak > 0) {
    final scale = 0.8 / peak;
    for (var i = 0; i < total; i++) {
      out[i] *= scale;
    }
  }
  final release = math.min(total, (0.03 * sampleRate).round());
  for (var i = 0; i < release; i++) {
    out[total - 1 - i] *= i / release;
  }
  return out;
}

/// Plays one rendered pluck at [startAt] (seconds on the AudioContext clock).
void _play(Float32List samples, double startAt, double gainValue) {
  final ctx = _ctx!;
  final buffer = ctx.createBuffer(1, samples.length, ctx.sampleRate);
  buffer.getChannelData(0).toDart.setRange(0, samples.length, samples);
  final src = ctx.createBufferSource();
  src.buffer = buffer;
  final gain = ctx.createGain();
  gain.gain.setValueAtTime(gainValue, startAt);
  src.connect(gain);
  gain.connect(ctx.destination);
  src.start(startAt);
}

Future<void> playTone(double freq, {double seconds = 1.2}) async {
  final ctx = await _ensure();
  final samples = _pluck(freq, seconds);
  _play(samples, ctx.currentTime + 0.01, 0.5);
}

/// Strums the strings low-to-high with a short, pick-like spread.
Future<void> playStrum(List<double> freqs) async {
  final ctx = await _ensure();
  final start = ctx.currentTime + 0.01;
  for (var i = 0; i < freqs.length; i++) {
    _play(_pluck(freqs[i], 2.4), start + i * 0.028, 0.42);
  }
}

/// Picks each string in turn so the notes ring out one by one.
Future<void> playArpeggio(List<double> freqs) async {
  final ctx = await _ensure();
  final start = ctx.currentTime + 0.01;
  for (var i = 0; i < freqs.length; i++) {
    _play(_pluck(freqs[i], 1.6), start + i * 0.16, 0.46);
  }
}
