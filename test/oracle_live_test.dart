/// LIVE Oracle check — proves the app's REAL request path works end-to-end
/// against Google with a real key: model selection + fallback, the
/// grounded-429 → ungrounded recovery, JSON parsing, and history-ready
/// output. This is the same code the Song Finder screen calls.
///
/// Skipped automatically when no key is supplied. To run:
///   flutter test --dart-define=GEMINI_API_KEY=... test/oracle_live_test.dart
/// (or use .secrets/run_live_check.ps1, which feeds the key for you).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rigmusic/services/gemini_service.dart';

void main() {
  const key = String.fromEnvironment('GEMINI_API_KEY');

  test(
    'LIVE: findSong returns a real parsed song through the app code path',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = GeminiService.instance;
      await service.setApiKey(key);

      final sw = Stopwatch()..start();
      final result = await service.findSong('Hotel California Eagles');
      sw.stop();

      final song = result.song;
      expect(result.rawJson, isNotEmpty,
          reason: 'findSong must return cacheable raw JSON for history');
      expect(song.sections, isNotEmpty,
          reason: 'parser must produce at least one section');

      // ignore: avoid_print
      print('LIVE OK in ${sw.elapsed.inSeconds}s — '
          'sections=${song.sections.length} '
          'rawBytes=${result.rawJson.length}');

      expect(song.title.toLowerCase(), contains('hotel california'),
          reason: 'the song that came back must match the query');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: key.isEmpty
        ? 'Pass --dart-define=GEMINI_API_KEY=... to run the live check'
        : false,
  );
}
