/// Reference tones (tuner + chord previews).
/// Web-only: uses the WebAudio API. All other platforms throw
/// [UnsupportedError] — callers must catch and show a fallback.
export 'reference_tone_stub.dart'
    if (dart.library.html) 'reference_tone_web.dart';
