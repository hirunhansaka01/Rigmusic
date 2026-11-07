import 'package:flutter_test/flutter_test.dart';
import 'package:rigmusic/services/gemini_service.dart';

void main() {
  group('SongChords.fromJson', () {
    test('reads the top-level metadata', () {
      final song = SongChords.fromJson({
        'title': 'Hotel California',
        'artist': 'Eagles',
        'key': 'Bm',
        'capo': '2',
        'tempo': '74',
        'tuning': 'Standard',
        'difficulty': 'Intermediate',
        'strumming': 'D DU - UDU',
        'chords': ['Bm', 'F#7', 'A', 'E'],
      });

      expect(song.title, 'Hotel California');
      expect(song.artist, 'Eagles');
      expect(song.key, 'Bm');
      expect(song.capo, 2);
      expect(song.tempo, 74);
      expect(song.tuning, 'Standard');
      expect(song.difficulty, 'Intermediate');
      expect(song.strumming, 'D DU - UDU');
      expect(song.chordsUsed, ['Bm', 'F#7', 'A', 'E']);
      expect(song.sections, isEmpty);
    });

    test('attaches an inline ChordPro chord to the word that follows it', () {
      final song = SongChords.fromJson({
        'title': 'T',
        'sections': [
          {'name': 'Verse', 'lines': ['[Am]Hello [E7]world']},
        ],
      });

      final words = song.sections.single.lines.single.words;
      expect(words.map((w) => w.text).toList(), ['Hello', 'world']);
      expect(words.map((w) => w.chord).toList(), ['Am', 'E7']);
    });

    test('words before the first chord carry no chord', () {
      final song = SongChords.fromJson({
        'title': 'T',
        'sections': [
          {'name': 'Verse', 'lines': ['On a [G]dark [D]night']},
        ],
      });

      final words = song.sections.single.lines.single.words;
      expect(words.map((w) => w.text).toList(), ['On', 'a', 'dark', 'night']);
      expect(words.map((w) => w.chord).toList(), [null, null, 'G', 'D']);
    });

    test('keeps multiple sections in order with their names', () {
      final song = SongChords.fromJson({
        'title': 'T',
        'sections': [
          {'name': 'Verse 1', 'lines': ['[C]line one']},
          {'name': 'Chorus', 'lines': ['[G]line two', '[F]line three']},
        ],
      });

      expect(song.sections.map((s) => s.name).toList(), ['Verse 1', 'Chorus']);
      expect(song.sections[1].lines.length, 2);
      expect(song.sections[1].lines.last.words.first.chord, 'F');
    });

    test('tolerates missing fields with safe defaults', () {
      final song = SongChords.fromJson(<String, dynamic>{});
      expect(song.title, 'Unknown Song');
      expect(song.artist, '');
      expect(song.key, 'C');
      expect(song.capo, 0);
      expect(song.tempo, 0);
      expect(song.chordsUsed, isEmpty);
      expect(song.sections, isEmpty);
    });
  });
}
