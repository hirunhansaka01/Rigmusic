import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'pitch_source_base.dart';
import 'yin.dart';

PitchSource createPitchSource() => NativePitchSource();

/// Live mic source for Android.
///
/// Samples come from the app's own Kotlin capture (see `MainActivity.kt`,
/// EventChannel `rigmusic/mic_stream`): the first event carries the device's
/// actual sample rate, followed by raw PCM16 little-endian mono chunks.
///
/// Everything downstream — the rolling 4096-sample window, the shared YIN
/// estimator and the median / EMA / silence handling — mirrors
/// `pitch_source_web.dart`, so both platforms feel identical to tune against.
class NativePitchSource implements PitchSource {
  NativePitchSource();

  static const EventChannel _channel = EventChannel('rigmusic/mic_stream');

  final StreamController<double?> _controller =
      StreamController<double?>.broadcast();

  StreamSubscription<dynamic>? _micSubscription;
  Timer? _timer;

  // Rolling analysis window (the same frame size the web analyser uses).
  static const int _frameSize = 4096;
  final Float32List _window = Float32List(_frameSize);
  int _writePos = 0;
  int _filled = 0;

  /// Actual capture rate announced by the native side (48 k or 44.1 k).
  int? _sampleRate;

  double? _smoothedFrequency;

  // Rolling buffer of the last few valid raw detections → median rejects
  // single-frame outliers (the main cause of "wrong note" flashes).
  final List<double> _recent = <double>[];
  DateTime? _lastValidAt;
  static const int _medianWindow = 5;

  @override
  Stream<double?> get frequencies => _controller.stream;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<void> start() async {
    if (_micSubscription != null) return;

    // Subscribing triggers the platform side: it requests RECORD_AUDIO if
    // needed, then starts capturing. Failures (permission denied, no mic)
    // arrive as errors on this same stream and are forwarded below.
    _micSubscription = _channel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        if (!_controller.isClosed) _controller.addError(error);
      },
    );

    // Poll the rolling window at the same cadence as the web build.
    _timer = Timer.periodic(const Duration(milliseconds: 60), _process);
  }

  void _onEvent(dynamic event) {
    if (event is Map) {
      final rate = event['sampleRate'];
      if (rate is num) _sampleRate = rate.toInt();
      return;
    }
    if (event is Uint8List) _onChunk(event);
  }

  void _onChunk(Uint8List bytes) {
    // PCM16 little-endian mono: two bytes per sample.
    final samples =
        bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
    for (final s in samples) {
      _window[_writePos] = s / 32768.0;
      _writePos = (_writePos + 1) % _frameSize;
      if (_filled < _frameSize) _filled++;
    }
  }

  void _process(_) {
    if (_filled < _frameSize) return;
    final rate = _sampleRate;
    if (rate == null) return;

    // Rebuild the frame in chronological order (oldest sample first); once
    // the window is full the write position points at the oldest entry.
    final frame = Float32List(_frameSize);
    for (var i = 0; i < _frameSize; i++) {
      frame[i] = _window[(_writePos + i) % _frameSize];
    }

    final frequency = estimatePitch(frame, rate);
    if (frequency == null) {
      _handleSilence();
      return;
    }
    _lastValidAt = DateTime.now();

    // Median of the last few frames: rejects a single bad reading without
    // adding much lag, so the note stops jittering between competing values.
    _recent.add(frequency);
    if (_recent.length > _medianWindow) _recent.removeAt(0);
    final sorted = List<double>.from(_recent)..sort();
    final median = sorted[sorted.length ~/ 2];

    // Light EMA only to smooth the needle between already-stable frames.
    _smoothedFrequency = _smoothedFrequency == null
        ? median
        : (_smoothedFrequency! * 0.6) + (median * 0.4);
    if (!_controller.isClosed) _controller.add(_smoothedFrequency!);
  }

  /// Keeps continuity across brief gaps, but fully resets after sustained
  /// silence so the next pluck starts clean (identical to the web source).
  void _handleSilence() {
    final last = _lastValidAt;
    if (last == null) return;
    if (DateTime.now().difference(last) > const Duration(milliseconds: 300)) {
      _recent.clear();
      _smoothedFrequency = null;
      _lastValidAt = null;
      // Tell listeners to drop the stale reading; `_lastValidAt == null`
      // makes this fire exactly once per silence episode.
      if (!_controller.isClosed) _controller.add(null);
    }
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    // Cancelling triggers the platform side's onCancel → stops the recorder.
    await _micSubscription?.cancel();
    _micSubscription = null;
    _writePos = 0;
    _filled = 0;
    _sampleRate = null;
    _smoothedFrequency = null;
    _recent.clear();
    _lastValidAt = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
