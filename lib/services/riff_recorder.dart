/// Riff recorder (mic capture + playback).
/// Web-only: uses MediaRecorder + `<audio>`. Other platforms expose a stub
/// where [riffRecorderSupported] is false and [createRiffRecorder] throws.
export 'riff_recorder_base.dart';
export 'riff_recorder_stub.dart'
    if (dart.library.html) 'riff_recorder_web.dart';
