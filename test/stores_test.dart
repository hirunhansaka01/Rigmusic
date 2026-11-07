import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rigmusic/services/favorites_store.dart';
import 'package:rigmusic/services/oracle_history.dart';
import 'package:rigmusic/services/riff_recorder_base.dart';
import 'package:rigmusic/services/riff_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await FavoritesStore.instance.clear();
    });

    test('starts empty', () async {
      expect(await FavoritesStore.instance.load(), isEmpty);
    });

    test('add / contains / remove round-trips', () async {
      expect(await FavoritesStore.instance.add('C'), isTrue);
      expect(await FavoritesStore.instance.contains('C'), isTrue);
      expect(await FavoritesStore.instance.add('C'), isFalse, reason: 'no dup');
      expect(await FavoritesStore.instance.remove('C'), isTrue);
      expect(await FavoritesStore.instance.contains('C'), isFalse);
    });

    test('toggle flips the saved state', () async {
      expect(await FavoritesStore.instance.toggle('Am'), isTrue);
      expect(await FavoritesStore.instance.load(), contains('Am'));
      expect(await FavoritesStore.instance.toggle('Am'), isFalse);
      expect(await FavoritesStore.instance.load(), isNot(contains('Am')));
    });

    test('persists to SharedPreferences, not just memory', () async {
      await FavoritesStore.instance.add('G');
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chord_favorites');
      expect(raw, isNotNull);
      expect(raw, contains('G'));
    });
  });

  group('OracleHistory', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OracleHistory.instance.clear();
    });

    test('starts empty', () async {
      expect(await OracleHistory.instance.load(), isEmpty);
    });

    test('add prepends the most recent entry', () async {
      await OracleHistory.instance.add('first', '{"title":"first"}');
      await OracleHistory.instance.add('second', '{"title":"second"}');
      final entries = await OracleHistory.instance.load();
      expect(entries.length, 2);
      expect(entries.first.query, 'second');
      expect(entries.last.query, 'first');
    });

    test('re-adding the same query dedupes and moves it to the front', () async {
      await OracleHistory.instance.add('a', '{}');
      await OracleHistory.instance.add('b', '{}');
      await OracleHistory.instance.add('A ', '{}'); // same query, different case
      final entries = await OracleHistory.instance.load();
      expect(entries.length, 2, reason: 'duplicate collapsed');
      expect(entries.first.query, 'A', reason: 'query is stored trimmed');
    });

    test('removeAt deletes by index and clear empties it', () async {
      await OracleHistory.instance.add('x', '{}');
      await OracleHistory.instance.add('y', '{}');
      var entries = await OracleHistory.instance.removeAt(0);
      expect(entries.length, 1);
      expect(entries.first.query, 'x');
      await OracleHistory.instance.clear();
      expect(await OracleHistory.instance.load(), isEmpty);
    });

    test('is capped at 20 entries', () async {
      for (var i = 0; i < 25; i++) {
        await OracleHistory.instance.add('song $i', '{}');
      }
      final entries = await OracleHistory.instance.load();
      expect(entries.length, 20);
      expect(entries.first.query, 'song 24', reason: 'newest kept');
    });
  });

  group('RiffStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts empty', () async {
      expect(await RiffStore.instance.load(), isEmpty);
    });

    test('round-trips saved riffs across a reload', () async {
      final riffs = [
        Riff(
            url: 'data:audio/webm;base64,AAA',
            time: DateTime.fromMillisecondsSinceEpoch(1000)),
        Riff(
            url: 'data:audio/webm;base64,BBB',
            time: DateTime.fromMillisecondsSinceEpoch(2000)),
      ];
      await RiffStore.instance.save(riffs);
      final loaded = await RiffStore.instance.load();
      expect(loaded.length, 2);
      expect(loaded[0].url, riffs[0].url);
      expect(loaded[0].time.millisecondsSinceEpoch, 1000);
      expect(loaded[1].url, riffs[1].url);
    });

    test('caps the list at the 10 most recent', () async {
      final riffs = List.generate(
          15,
          (i) => Riff(
              url: 'data:audio/webm;base64,$i',
              time: DateTime.fromMillisecondsSinceEpoch(i)));
      await RiffStore.instance.save(riffs);
      final loaded = await RiffStore.instance.load();
      expect(loaded.length, 10);
      expect(loaded.first.url, riffs.first.url, reason: 'newest kept');
    });
  });

  group('sync change callbacks (CloudSync wiring)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FavoritesStore.onSaved = null;
      OracleHistory.onSaved = null;
      await FavoritesStore.instance.clear();
      await OracleHistory.instance.clear();
    });

    tearDown(() {
      FavoritesStore.onSaved = null;
      OracleHistory.onSaved = null;
    });

    test('FavoritesStore fires onSaved with the full set', () async {
      Set<String>? seen;
      FavoritesStore.onSaved = (names) => seen = names;
      await FavoritesStore.instance.add('D');
      expect(seen, isNotNull, reason: 'mutation triggers a cloud push');
      expect(seen, contains('D'));
    });

    test('OracleHistory fires onSaved with the entries', () async {
      List<OracleHistoryEntry>? seen;
      OracleHistory.onSaved = (entries) => seen = entries;
      await OracleHistory.instance.add('q', '{}');
      expect(seen, isNotNull, reason: 'mutation triggers a cloud push');
      expect(seen!.first.query, 'q');
    });
  });
}
