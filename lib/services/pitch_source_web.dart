import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pitch_source_base.dart';
import 'yin.dart';

PitchSource createPitchSource() => WebPitchSource();

class WebPitchSource implements PitchSource {
  final StreamController<double?> _controller = StreamController<double?>.broadcast();
  web.AudioContext? _context;
  web.MediaStream? _stream;
  web.MediaStreamAudioSourceNode? _source;
  web.AnalyserNode? _analyser;
  // Persistent JS-side FFT scratch buffer. `getFloatTimeDomainData` writes
  // straight into it; `.toDart` returns a Float32List VIEW over the same
  // memory, so the pitch estimator reads the freshly captured frame with no copy.
  JSFloat32Array? _jsBuffer;
  Timer? _timer;
  double? _smoothedFrequency;

  // Rolling buffer of the last few valid raw detections, used to take a median
  // that rejects single-frame outliers (the main cause of "wrong note" flashes
  // on a harmonic-rich guitar signal).
  final List<double> _recent = <double>[];
  DateTime? _lastValidAt;
  static const int _medianWindow = 5;

  @override
  Stream<double?> get frequencies => _controller.stream;

  @override
  bool get isSupported => true;

  @override
  Future<void> start() async {
    if (_analyser != null) return;
    final mediaDevices = web.window.navigator.mediaDevices;
    // Turn off the browser's automatic mic processing so the raw guitar signal
    // reaches the detector untouched.
    final stream = await mediaDevices
        .getUserMedia(web.MediaStreamConstraints(
          audio: <String, dynamic>{
            'autoGainControl': false,
            'echoCancellation': false,
            'noiseSuppression': false,
          }.jsify()!,
        ))
        .toDart;
    final context = web.AudioContext();
    await context.resume().toDart;
    final source = context.createMediaStreamSource(stream);
    // Analyser tap: the mic is NEVER routed to the speakers, so there is
    // no feedback loop corrupting the measurement.
    final analyser = context.createAnalyser();
    analyser.fftSize = 4096;
    source.connect(analyser);
    final jsBuffer = Float32List(analyser.fftSize).toJS;

    _stream = stream;
    _context = context;
    _source = source;
    _analyser = analyser;
    _jsBuffer = jsBuffer;

    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final a = _analyser;
      final c = _context;
      final buf = _jsBuffer;
      if (a == null || c == null || buf == null) return;
      a.getFloatTimeDomainData(buf);
      final buffer = buf.toDart; // view over the just-filled JS array
      final frequency = estimatePitch(buffer, c.sampleRate);
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
      _controller.add(_smoothedFrequency!);
    });
  }

  /// Keeps continuity across brief gaps, but fully resets after sustained
  /// silence so the next pluck starts clean instead of blending with the
  /// previous string.
  void _handleSilence() {
    final last = _lastValidAt;
    if (last == null) return;
    if (DateTime.now().difference(last) > const Duration(milliseconds: 300)) {
      _recent.clear();
      _smoothedFrequency = null;
      _lastValidAt = null;
      // Tell listeners to drop the stale reading. The `_lastValidAt == null`
      // guard above makes this fire exactly once per silence episode, so the
      // meter returns to rest instead of freezing on the last pluck forever.
      _controller.add(null);
    }
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _source?.disconnect();
    _analyser?.disconnect();
    _analyser = null;
    _source = null;
    _jsBuffer = null;
    final stream = _stream;
    if (stream != null) {
      stream.getTracks().toDart.forEach((track) => track.stop());
    }
    _stream = null;
    final context = _context;
    if (context != null) await context.close().toDart;
    _context = null;
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
