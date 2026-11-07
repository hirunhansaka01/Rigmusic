import 'dart:math' as math;
import 'dart:typed_data';

/// YIN pitch estimator (de Cheveigné & Kawahara): difference function with
/// cumulative-mean normalization, first sub-threshold dip, and parabolic
/// refinement.
///
/// Extracted from the web mic source as a pure function so the detection
/// math can be unit-tested with synthesized signals (see `test/yin_test.dart`).
///
/// The difference function is summed over a FIXED analysis window
/// (`length - maxLag`) for every lag, which is the canonical form. The older
/// `length - tau` window changed size per-lag, biasing where the minimum
/// landed and making the detector settle on the wrong note and jitter.
double? estimatePitch(Float32List samples, num sampleRate) {
  final length = samples.length;
  final double sr = sampleRate.toDouble();

  // RMS gate — ignore silence / quiet background noise. Kept low so thin or
  // quieter strings (1st E, B) still get analyzed instead of being gated out
  // to a dead "no reading".
  var energy = 0.0;
  for (var i = 0; i < length; i++) {
    energy += samples[i] * samples[i];
  }
  if (math.sqrt(energy / length) < 0.008) return null;

  // Practical plucked-string range: ~B0 (31 Hz, 5-string bass low B) up to
  // ~800 Hz (guitar/bass open strings and harmonics). A fixed window keeps
  // every lag comparable; the floor is low enough to reach 4/5-string bass.
  final minLag = math.max(2, (sr / 800).floor());
  final maxLag = math.min((sr / 30).floor(), length ~/ 2);
  if (maxLag <= minLag + 2) return null;

  final window = length - maxLag;

  // Difference function + cumulative-mean normalized difference.
  final yin = List<double>.filled(maxLag + 1, 0.0);
  var runningSum = 0.0;
  for (var tau = 1; tau <= maxLag; tau++) {
    var diff = 0.0;
    for (var j = 0; j < window; j++) {
      final d = samples[j] - samples[j + tau];
      diff += d * d;
    }
    runningSum += diff;
    yin[tau] = runningSum == 0 ? 1.0 : diff * tau / runningSum;
  }

  // First dip below threshold, walked down to its local minimum. The
  // threshold is deliberately a touch loose (0.15) so thin/quiet strings
  // whose periodicity dip is borderline still register instead of reading as
  // "nothing" — the median filter downstream rejects the extra noise.
  const threshold = 0.15;
  var tau = -1;
  for (var t = minLag; t <= maxLag; t++) {
    if (yin[t] < threshold) {
      while (t + 1 <= maxLag && yin[t + 1] < yin[t]) {
        t++;
      }
      tau = t;
      break;
    }
  }
  if (tau <= 0) return null;
  // Reject a shallow, noisy "dip" that barely cleared the bar — showing a
  // wrong note is worse than showing nothing.
  if (yin[tau] > threshold) return null;

  // Octave (harmonic) correction — but ONLY when the first dip was shallow
  // (not a confident lock on the fundamental). A weak fundamental (very
  // common on the bass E string) lets first-dip stop on a strong harmonic
  // first, locking the wrong string; in that case a lower octave is a much
  // deeper, confident dip and is the real pitch.
  //
  // A clean, confident fundamental (deep first dip, < 0.05) is never touched,
  // so a correctly detected 1st E / B / G / D / A can't be pushed down an
  // octave or turned into a null reading.
  if (yin[tau] > 0.05) {
    var bestTau = tau;
    var bestVal = yin[tau];
    for (var k = 2; k <= 4; k++) {
      final cand = tau * k; // always a multiple of the first dip
      if (cand > maxLag) break;
      final lo = math.max(minLag, cand - 2);
      final hi = math.min(maxLag, cand + 2);
      var loc = -1;
      var locVal = double.infinity;
      for (var t = lo; t <= hi; t++) {
        if (yin[t] < locVal) {
          locVal = yin[t];
          loc = t;
        }
      }
      if (loc > 0 && locVal < bestVal) {
        bestVal = locVal;
        bestTau = loc;
      }
    }
    // Only adopt the lower octave if it is a confident dip in its own right
    // AND at least 2x deeper than the first dip. The relative test is what
    // keeps a correct-but-shallow fundamental (common on Karplus–Strong /
    // decayed plucks) from being pushed down a period-multiple to the wrong
    // octave: a real weak-fundamental case has the fundamental far deeper
    // than the harmonic first dip, while a period-multiple artifact is only
    // marginally deeper (ratio ~0.54), so it is rejected here.
    if (bestTau != tau && bestVal < 0.10 && bestVal < yin[tau] * 0.5) {
      tau = bestTau;
    }
  }

  // Parabolic interpolation around the minimum.
  var refined = tau.toDouble();
  if (tau > 1 && tau < maxLag) {
    final before = yin[tau - 1];
    final after = yin[tau + 1];
    final denom = before - 2 * yin[tau] + after;
    if (denom.abs() > 1e-9) {
      refined = tau + 0.5 * (before - after) / denom;
    }
  }
  if (refined <= 0) return null;
  final freq = sr / refined;
  if (freq < 28 || freq > 750) return null; // sanity clamp (28 Hz covers B0)
  return freq;
}
