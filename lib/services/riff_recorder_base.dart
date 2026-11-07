/// A single captured riff (session-only, not persisted across reloads).
class Riff {
  Riff({required this.url, required this.time});

  /// URL playable by a browser `<audio>` — a persisted base64 `data:` URL
  /// (or, on the non-persisted stub, an in-memory object URL).
  final String url;
  final DateTime time;
}

/// Records microphone audio and plays it back (web only).
abstract class RiffRecorder {
  bool get isSupported;
  bool get isRecording;

  /// Begin recording from the mic. Throws [UnsupportedError] if there is no
  /// microphone / permission denied / unsupported.
  Future<void> start();

  /// Finish recording and return a playable object [url], or null if empty.
  Future<String?> stop();

  /// Play back a previously returned [url].
  Future<void> play(String url);

  /// Stop any in-progress playback.
  void stopPlay();

  /// Release mic + playback resources.
  Future<void> dispose();
}
