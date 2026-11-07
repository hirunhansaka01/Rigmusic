import 'riff_recorder_base.dart';

bool get riffRecorderSupported => false;

RiffRecorder createRiffRecorder() => _UnsupportedRiffRecorder();

class _UnsupportedRiffRecorder implements RiffRecorder {
  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<void> start() async => throw UnsupportedError('Recording needs a browser.');

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> play(String url) async {}

  @override
  void stopPlay() {}

  @override
  Future<void> dispose() async {}
}
