import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rigmusic/data/chord_library.dart';

/// Pitch-class lookup built from the library's own aliases, so the tests stay
/// in sync with how the generator spells notes. Enharmonic double-flat /
/// double-sharp spellings (used for diminished b5 / augmented #5 tones, e.g.
/// Abb == G and C## == D) are added on top so every correct spelling resolves.
Map<String, int> _pcs() {
  final map = Map<String, int>.from(kNoteAliases);
  // Any remaining enharmonic spellings the generator may emit for chord tones
  // (e.g. E# for an augmented 5th, Abb / C## for diminished / augmented
  // intervals). `??=` keeps the library's own canonical choices where present.
  const naturals = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  for (final e in naturals.entries) {
    map['${e.key}#'] ??= (e.value + 1) % 12;
    map['${e.key}b'] ??= (e.value - 1) % 12;
    map['${e.key}##'] = (e.value + 2) % 12;
    map['${e.key}bb'] = (e.value - 2) % 12;
  }
  return map;
}

void main() {
  final pc = _pcs();

  group('chord library', () {
    test('contains 324 chords (27 qualities x 12 roots)', () {
      expect(kAllChords.length, 324);
    });

    test('covers all 12 roots', () {
      final roots = kAllChords.map((c) => c.root).toSet();
      expect(roots.length, 12);
    });

    test('files chords into exactly the 8 expected categories', () {
      final groups = kAllChords.map((c) => c.group).toSet();
      expect(groups, {...kChordGroups});
    });

    test('per-group counts match the quality breakdown', () {
      int count(String g) => kAllChords.where((c) => c.group == g).length;
      expect(count('Major'), 12);
      expect(count('Minor'), 12);
      expect(count('Diminished'), 24);
      expect(count('7th'), 108);
      expect(count('Augmented'), 12);
      expect(count('Suspended'), 36);
      expect(count('Added'), 48);
      expect(count('Extended'), 72);
    });

    test('every chord is structurally valid, theoretically correct and playable',
        () {
      for (final c in kAllChords) {
        // Shape arrays cover all six strings.
        expect(c.frets.length, 6, reason: '${c.name} frets length');
        expect(c.fingers.length, 6, reason: '${c.name} fingers length');

        // The root name resolves to the recorded pitch class.
        expect(pc[c.root], c.rootPc, reason: '${c.name} root pitch class');

        // Theory: each note equals root + formula interval (mod 12).
        final names = c.notes.split(' • ');
        expect(names.length, c.formula.length,
            reason: '${c.name} notes vs formula length');
        for (var i = 0; i < c.formula.length; i++) {
          final expected = (c.rootPc + c.formula[i]) % 12;
          expect(pc[names[i]], expected,
              reason: '${c.name} note "${names[i]}" should be pc $expected');
        }

        // Playability: fretted notes span at most 4 frets.
        final fretted = c.frets.where((f) => f > 0).toList();
        if (fretted.length > 1) {
          final span = fretted.reduce(math.max) - fretted.reduce(math.min);
          expect(span, lessThanOrEqualTo(4), reason: '${c.name} fret span');
        }

        // Playability: at most 4 distinct fingers (a barre reuses one finger).
        final usedFingers = c.fingers.where((f) => f > 0).toSet();
        expect(usedFingers.length, lessThanOrEqualTo(4),
            reason: '${c.name} distinct fingers');

        // Fret values are in range (-1 muted .. open 0 .. fretted).
        for (final f in c.frets) {
          expect(f, greaterThanOrEqualTo(-1), reason: '${c.name} fret range');
        }

        // Audio: one frequency per sounding (>= 0 fret) string.
        final sounding = c.frets.where((f) => f >= 0).length;
        expect(c.freqs.length, sounding, reason: '${c.name} freq count');

        // Audio: each frequency is the open string raised by its fret — this
        // is what makes every tile actually play the right chord.
        var k = 0;
        for (var s = 0; s < 6; s++) {
          final f = c.frets[s];
          if (f < 0) continue;
          final expected = kOpenStringFreqs[s] * math.pow(2, f / 12);
          expect((c.freqs[k] - expected).abs(), lessThan(0.6),
              reason: '${c.name} freq for string $s');
          k++;
        }
      }
    });

    test('canonical open shapes are locked in', () {
      List<int> shape(String name) =>
          kAllChords.firstWhere((c) => c.name == name).frets;
      expect(shape('C'), [-1, 3, 2, 0, 1, 0]);
      expect(shape('F'), [1, 3, 3, 2, 1, 1]);
      expect(shape('A7'), [-1, 0, 2, 0, 2, 0]);
      expect(shape('G7'), [3, 2, 0, 0, 0, 1]);
    });
  });
}
