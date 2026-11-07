import 'dart:async';

import 'pitch_source_base.dart';

PitchSource createPitchSource() => _UnsupportedPitchSource();

class _UnsupportedPitchSource implements PitchSource {
  final StreamController<double?> _controller = StreamController<double?>.broadcast();

  @override
  Stream<double?> get frequencies => _controller.stream;

  @override
  bool get isSupported => false;

  @override
  Future<void> dispose() => _controller.close();

  @override
  Future<void> start() {
    throw UnsupportedError('Live tuning is available in the web version of Rig Music.');
  }

  @override
  Future<void> stop() async {}
}
