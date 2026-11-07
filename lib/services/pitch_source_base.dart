import 'dart:async';

abstract class PitchSource {
  /// Emits the detected pitch in Hz, or `null` after sustained silence so
  /// listeners can drop their stale reading (meter returns to rest).
  Stream<double?> get frequencies;
  bool get isSupported;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
