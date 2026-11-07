import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rigmusic/services/yin.dart';

/// Unit tests for the tuner's detection engine (`estimatePitch`).
///
/// Signals are synthesized the way a guitar reaches the mic: fundamental +
/// harmonic stack with an exponential decay, plus optional background noise —
/// matching the 4096-sample / 60 ms frames the web analyser feeds in.
const double _sr = 48000;
const int _frame = 4096; // analyser.fftSize in pitch_source_web.dart

/// Synthesizes one analyzer-sized frame of a guitar-like tone at [freq]:
/// a sum of harmonics (`harmAmps[k]` = amplitude of partial k+1), overall
/// level [amp], optional exponential decay (seconds) and additive white
/// background noise [noiseAmp] (not decayed).
Float32List _tone(
  double freq, {
  double sr = _sr,
  int n = _frame,
  List<double> harmAmps = const [1.0],
  double amp = 0.2,
  double decaySecs = 0,
  double noiseAmp = 0,
  int seed = 7,
}) {
  final out = Float32List(n);
  final rnd = math.Random(seed);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    var v = 0.0;
    for (var k = 0; k < harmAmps.length; k++) {
      v += harmAmps[k] * math.sin(2 * math.pi * (k + 1) * freq * t);
    }
    v *= amp;
    if (decaySecs > 0) v *= math.exp(-t / decaySecs);
    if (noiseAmp > 0) v += (rnd.nextDouble() * 2 - 1) * noiseAmp;
    out[i] = v;
  }
  return out;
}

/// Karplus–Strong plucked string — same synthesis family as the app's
/// reference tone, so this is as close to a real pluck as a unit test gets.
Float32List _ksPluck(double freq, {double sr = _sr, int n = _frame}) {
  final period = math.max(2, (sr / freq).round());
  final buf = List<double>.filled(period, 0.0);
  final rnd = math.Random(42);
  var lp = 0.0;
  for (var i = 0; i < period; i++) {
    lp += 0.6 * ((rnd.nextDouble() * 2 - 1) - lp);
    buf[i] = lp;
  }
  final out = Float32List(n);
  var idx = 0;
  for (var i = 0; i < n; i++) {
    final cur = buf[idx];
    out[i] = cur;
    final next = buf[(idx + 1) % period];
    buf[idx] = (cur + next) * 0.5 * 0.996;
    idx = (idx + 1) % period;
  }
  var peak = 0.0;
  for (final v in out) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0) {
    for (var i = 0; i < n; i++) {
      out[i] *= 0.8 / peak;
    }
  }
  return out;
}

/// Cents deviation of [a] from [b] (1200 per octave).
double _cents(double a, double b) => 1200 * (math.log(a / b) / math.ln2);

const Map<String, double> _standard = <String, double>{
  'E2': 82.41,
  'A2': 110.00,
  'D3': 146.83,
  'G3': 196.00,
  'B3': 246.94,
  'E4': 329.63,
};

void main() {
  group('estimatePitch — gates', () {
    test('pure silence is rejected (RMS gate)', () {
      expect(estimatePitch(Float32List(_frame), _sr), isNull);
    });

    test('background noise below the RMS gate is rejected', () {
      final noise = Float32List(_frame);
      final rnd = math.Random(3);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = (rnd.nextDouble() * 2 - 1) * 0.004; // RMS ≈ 0.002 < 0.008
      }
      expect(estimatePitch(noise, _sr), isNull);
    });

    test('uncorrelated noise above the gate has no pitch', () {
      final noise = Float32List(_frame);
      final rnd = math.Random(11);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = (rnd.nextDouble() * 2 - 1) * 0.3;
      }
      expect(estimatePitch(noise, _sr), isNull);
    });

    test('out-of-range sub-bass pitch (15 Hz) is rejected', () {
      expect(estimatePitch(_tone(15), _sr), isNull);
    });
  });

  group('estimatePitch — pure tones across the tuning range', () {
    final tones = <String, double>{
      ..._standard,
      'D2 (Drop D)': 73.42,
      'D4': 293.66,
      'G4': 392.00,
      'B4': 493.88,
      'E5': 659.25,
      // Bass range (4/5-string): the detector must reach ~31 Hz.
      'B0 (5-string low B)': 30.87,
      'E1 (bass low E)': 41.20,
      'A1 (bass A)': 55.00,
    };
    tones.forEach((name, freq) {
      test('$name ($freq Hz) within 5 cents', () {
        final detected = estimatePitch(_tone(freq), _sr);
        expect(detected, isNotNull, reason: '$name should be detected');
        expect(_cents(detected!, freq).abs(), lessThan(5),
            reason: '$name detected as ${detected.toStringAsFixed(2)} Hz');
      });
    });
  });

  group('estimatePitch — harmonic-rich plucks', () {
    _standard.forEach((name, freq) {
      test('$name pluck (5 partials + decay) within 10 cents', () {
        final signal =
            _tone(freq, harmAmps: const [1.0, 0.6, 0.35, 0.2, 0.1], decaySecs: 0.4);
        final detected = estimatePitch(signal, _sr);
        expect(detected, isNotNull, reason: '$name pluck should be detected');
        expect(_cents(detected!, freq).abs(), lessThan(10),
            reason: '$name detected as ${detected.toStringAsFixed(2)} Hz');
      });
    });

    test('weak fundamental with dominant 2nd harmonic keeps the octave (E2)', () {
      // Classic bass-E problem: mic comb-filtering guts the fundamental, the
      // 2nd harmonic dominates — detector must not return E3 (≈164.8 Hz).
      final signal = _tone(82.41, harmAmps: const [0.1, 1.0, 0.3, 0.1], decaySecs: 0.4);
      final detected = estimatePitch(signal, _sr);
      expect(detected, isNotNull);
      expect(_cents(detected!, 82.41).abs(), lessThan(10),
          reason: 'octave error: got ${detected.toStringAsFixed(2)} Hz');
    });

    test('moderately weak fundamental stays on the fundamental (E2)', () {
      final signal = _tone(82.41, harmAmps: const [0.18, 1.0, 0.45, 0.15], decaySecs: 0.4);
      final detected = estimatePitch(signal, _sr);
      expect(detected, isNotNull);
      expect(_cents(detected!, 82.41).abs(), lessThan(10),
          reason: 'octave error: got ${detected.toStringAsFixed(2)} Hz');
    });

    test('plucked tone over room noise still locks (G3)', () {
      final signal = _tone(196.00,
          harmAmps: const [1.0, 0.6, 0.35, 0.2], decaySecs: 0.4, noiseAmp: 0.015);
      final detected = estimatePitch(signal, _sr);
      expect(detected, isNotNull);
      expect(_cents(detected!, 196.00).abs(), lessThan(10),
          reason: 'detected as ${detected.toStringAsFixed(2)} Hz');
    });
  });

  group('estimatePitch — Karplus–Strong plucks (reference-tone family)', () {
    for (final freq in <double>[82.41, 110.00, 329.63]) {
      test('KS pluck at $freq Hz within 10 cents', () {
        final detected = estimatePitch(_ksPluck(freq), _sr);
        expect(detected, isNotNull, reason: 'KS pluck at $freq should be detected');
        expect(_cents(detected!, freq).abs(), lessThan(10),
            reason: 'detected as ${detected.toStringAsFixed(2)} Hz');
      });
    }
  });

  group('estimatePitch — levels & sample rates', () {
    test('quiet but playable level is still detected (A2)', () {
      final detected = estimatePitch(_tone(110.00, amp: 0.03), _sr);
      expect(detected, isNotNull, reason: 'quiet string gated out');
      expect(_cents(detected!, 110.00).abs(), lessThan(5));
    });

    test('works at 44.1 kHz (D2, Drop D root)', () {
      const sr44 = 44100.0;
      final detected = estimatePitch(_tone(73.42, sr: sr44), sr44);
      expect(detected, isNotNull);
      expect(_cents(detected!, 73.42).abs(), lessThan(5),
          reason: 'detected as ${detected.toStringAsFixed(2)} Hz');
    });
  });
}
