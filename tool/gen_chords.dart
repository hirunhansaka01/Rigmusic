// Offline generator for lib/data/chord_library.dart
//
// Brute-forces playable guitar voicings for every (chord quality x root)
// pair, verifies the pitch set against music theory, checks fingering
// feasibility (barre + max 4 fingers, span <= 4 frets) and writes the
// resulting chord database as Dart source.
//
// Run: dart run tool/gen_chords.dart

import 'dart:io';
import 'dart:math' as math;

/// Low E, A, D, G, B, high e in standard tuning (Hz).
const openFreqs = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

/// Pitch class of each open string (E A D G B E).
const stringPc = [4, 9, 2, 7, 11, 4];

const noteNames = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
];

class Quality {
  const Quality(this.suffix, this.group, this.essential, this.allowed);

  /// Suffix appended to the root name, e.g. 'maj7' -> Cmaj7.
  final String suffix;

  /// UI group ("menu") the chord belongs to.
  final String group;

  /// Tones that MUST sound for the chord to be that chord.
  final List<int> essential;

  /// Tones that MAY sound (guitar voicings often drop 5ths / 9ths).
  final List<int> allowed;
}

const qualities = <Quality>[
  // Major
  Quality('', 'Major', [0, 4, 7], [0, 4, 7]),
  // Minor
  Quality('m', 'Minor', [0, 3, 7], [0, 3, 7]),
  // Diminished
  Quality('dim', 'Diminished', [0, 3, 6], [0, 3, 6]),
  Quality('dim7', 'Diminished', [0, 3, 6, 9], [0, 3, 6, 9]),
  Quality('m7b5', '7th', [0, 3, 6, 10], [0, 3, 6, 10]),
  // Augmented
  Quality('aug', 'Augmented', [0, 4, 8], [0, 4, 8]),
  // Suspended
  Quality('sus2', 'Suspended', [0, 2, 7], [0, 2, 7]),
  Quality('sus4', 'Suspended', [0, 5, 7], [0, 5, 7]),
  Quality('7sus4', 'Suspended', [0, 5, 10], [0, 5, 7, 10]),
  // Added tone
  Quality('6', 'Added', [0, 4, 9], [0, 4, 7, 9]),
  Quality('m6', 'Added', [0, 3, 9], [0, 3, 7, 9]),
  Quality('add9', 'Added', [0, 2, 4], [0, 2, 4, 7]),
  Quality('6/9', 'Added', [0, 2, 4, 9], [0, 2, 4, 7, 9]),
  // Dominant / seventh family
  Quality('7', '7th', [0, 4, 10], [0, 4, 7, 10]),
  Quality('maj7', '7th', [0, 4, 11], [0, 4, 7, 11]),
  Quality('m7', '7th', [0, 3, 10], [0, 3, 7, 10]),
  Quality('mMaj7', '7th', [0, 3, 11], [0, 3, 7, 11]),
  Quality('7b5', '7th', [0, 4, 6, 10], [0, 4, 6, 10]),
  Quality('7#5', '7th', [0, 4, 8, 10], [0, 4, 8, 10]),
  Quality('7b9', '7th', [0, 1, 4, 10], [0, 1, 4, 7, 10]),
  Quality('7#9', '7th', [0, 3, 4, 10], [0, 3, 4, 7, 10]),
  // Extended
  Quality('9', 'Extended', [0, 2, 4, 10], [0, 2, 4, 7, 10]),
  Quality('maj9', 'Extended', [0, 2, 4, 11], [0, 2, 4, 7, 11]),
  Quality('m9', 'Extended', [0, 2, 3, 10], [0, 2, 3, 7, 10]),
  Quality('11', 'Extended', [0, 5, 10], [0, 2, 5, 7, 10]),
  Quality('m11', 'Extended', [0, 3, 5, 10], [0, 2, 3, 5, 7, 10]),
  Quality('13', 'Extended', [0, 4, 9, 10], [0, 2, 4, 7, 9, 10]),
];

/// Display order of the groups on screen.
const groupOrder = [
  'Major', 'Minor', '7th', 'Extended', 'Added', 'Suspended',
  'Diminished', 'Augmented',
];

int maskOf(Iterable<int> pcs) => pcs.fold(0, (m, p) => m | (1 << (p % 12)));

int rotate(int mask, int by) {
  var out = 0;
  for (var p = 0; p < 12; p++) {
    if ((mask >> p) & 1 == 1) out |= 1 << ((p + by) % 12);
  }
  return out;
}

int popcount(int m) {
  var c = 0;
  while (m != 0) {
    c += m & 1;
    m >>= 1;
  }
  return c;
}

class Fingering {
  const Fingering(
      this.fingers, this.barreFret, this.barreFrom, this.barreTo, this.splitRuns);

  final List<int> fingers;
  final int barreFret;
  final int barreFrom;
  final int barreTo;

  /// Extra fingers needed because one fret level spans several separate
  /// runs (e.g. G's two fret-3 E strings). Penalised, not forbidden.
  final int splitRuns;
}

/// Contiguous runs of strings sitting at exactly fret [f].
List<(int, int)> _runsAt(List<int> frets, int f) {
  final out = <(int, int)>[];
  int? start;
  for (var s = 0; s < 6; s++) {
    if (frets[s] == f) {
      start ??= s;
    } else if (start != null) {
      out.add((start, s - 1));
      start = null;
    }
  }
  if (start != null) out.add((start, 5));
  return out;
}

/// Derives a real fingering (barre + fingers 1..4) or rejects the shape.
/// One finger per contiguous run: two strings at the same fret only share a
/// finger when they sit next to each other (a mini-barre) or under a real
/// barre — otherwise the shape would need five fingers.
Fingering? fingeringOf(List<int> frets) {
  final fretted = <int>[];
  for (var s = 0; s < 6; s++) {
    if (frets[s] > 0) fretted.add(s);
  }
  if (fretted.isEmpty) return null;
  var minF = frets[fretted.first];
  var maxF = minF;
  for (final s in fretted) {
    if (frets[s] < minF) minF = frets[s];
    if (frets[s] > maxF) maxF = frets[s];
  }
  if (maxF - minF > 3) return null; // needs a 5-fret stretch

  // Barre: the span from the first to the last string pinned at the lowest
  // fret must be at least 3 strings wide, cover >= 2 sounding strings at
  // that fret, and contain nothing open or muted (Bb = x13331 works, but
  // an open string under the span means no barre is possible).
  var barreFret = -1, barreFrom = -1, barreTo = -1;
  final atMin = fretted.where((s) => frets[s] == minF).toList();
  if (atMin.length >= 2) {
    final from = atMin.first, to = atMin.last;
    var ok = to - from >= 2;
    for (var s = from; s <= to && ok; s++) {
      if (frets[s] < minF) ok = false; // open / muted string under the span
    }
    if (ok) {
      barreFret = minF;
      barreFrom = from;
      barreTo = to;
    }
  }

  // Finger assignment, low fret to high. Finger 1 belongs to the barre when
  // there is one; every other run of strings gets its own finger (a finger
  // cannot cover two runs — an open string between them would be muted).
  final fingers = List<int>.filled(6, 0);
  var splitRuns = 0;
  final used = <int>{};
  if (barreFret >= 0) {
    used.add(1);
    for (var s = barreFrom; s <= barreTo; s++) {
      if (frets[s] == barreFret) fingers[s] = 1;
    }
  }
  for (var f = (barreFret >= 0 ? barreFret + 1 : minF); f <= maxF; f++) {
    final runs = _runsAt(frets, f);
    if (runs.isNotEmpty && f != (barreFret >= 0 ? barreFret : minF)) {
      splitRuns += runs.length - 1;
    }
    for (final r in runs) {
      if (fingers[r.$1] != 0) continue; // already under the barre
      var finger = 1;
      while (used.contains(finger)) {
        finger++;
      }
      if (finger > 4) return null; // needs a fifth finger
      for (var s = r.$1; s <= r.$2; s++) {
        fingers[s] = finger;
      }
      used.add(finger);
    }
  }
  return Fingering(fingers, barreFret, barreFrom, barreTo, splitRuns);
}

/// Diatonic letters from C; accidentals are derived, never guessed.
const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const _letterNatural = [0, 2, 4, 5, 7, 9, 11];

/// Letters to walk for each interval size (0 = unison .. 11 = major 7th).
/// 6 semitones walks 4 letters (Gb from C, Eb from A) = diminished 5th;
/// 8 semitones walks 4 letters (G#) = augmented 5th, as used in aug chords.
const _letterSteps = [0, 1, 1, 2, 2, 3, 4, 4, 4, 5, 6, 6];

/// Spells the note [interval] semitones above [rootPc] correctly, e.g.
/// F# + 3 = A (not Cb-avoiding Db) and A + 6 = Eb (not D#).
String spell(int rootPc, int interval, {bool preferFlat = false}) {
  // Which letter the root itself uses. Sharp/flat roots (F#, Db, ...) have
  // no natural-letter equivalent, so fall back to the neighbouring letter
  // and let the accidental system do the work.
  var rootLetter = -1;
  for (var i = 0; i < 7; i++) {
    if ((_letterNatural[i] - rootPc) % 12 == 0) {
      rootLetter = i;
      break;
    }
  }
  if (rootLetter < 0) {
    for (var i = 0; i < 7; i++) {
      final up = (rootPc - _letterNatural[i]) % 12 == 1;
      final down = (_letterNatural[i] - rootPc) % 12 == 1;
      if (preferFlat ? down : up) {
        rootLetter = i;
        break;
      }
    }
  }
  if (rootLetter < 0) rootLetter = 0;
  final target = _letters[(rootLetter + _letterSteps[interval % 12]) % 7];
  final natural = _letterNatural[_letters.indexOf(target)];
  var acc = (rootPc + interval - natural) % 12;
  if (acc > 6) acc -= 12;
  const marks = {0: '', 1: '#', 2: '##', (-1): 'b', (-2): 'bb'};
  return target + (marks[acc] ?? '');
}

class Candidate {
  const Candidate(this.frets, this.score, this.fing);
  final List<int> frets;
  final int score;
  final Fingering fing;
}

class Chord {
  const Chord(this.root, this.quality, this.frets, this.fingers, this.barreFret,
      this.barreFrom, this.barreTo, this.startFret, this.notes, this.freqs);
  final int root;
  final Quality quality;
  final List<int> frets;
  final List<int> fingers;
  final int barreFret;
  final int barreFrom;
  final int barreTo;
  final int startFret;
  final String notes;
  final List<double> freqs;
}

/// Canonical CAGED/open shapes per quality (low E -> high e, -1 = muted).
/// Shapes containing an open string double as barre forms when transposed
/// (open E major + 3 frets = the G barre). Every shape is verified against
/// theory and playability before it is used; anything that fails simply
/// falls back to the brute-forced voicing.
/// A CAGED shape and how far up the neck it may be transposed (maxK).
/// E- and A-form shapes transpose into the standard barre chords everyone
/// uses; C/G/D-form shapes only look right in their open position, so they
/// are capped at k=0 (otherwise Ab would come out as a G-form barre).
class Tpl {
  const Tpl(this.frets, [this.maxK = 7]);
  final List<int> frets;
  final int maxK;
}

const Map<String, List<Tpl>> templates = {
  '': [ // Major
    Tpl([0, 2, 2, 1, 0, 0]), // E-form barre / open E
    Tpl([-1, 0, 2, 2, 2, 0]), // A-form barre / open A
    Tpl([-1, -1, 0, 2, 3, 2], 0), // D-form / open D
    Tpl([3, 2, 0, 0, 0, 3], 0), // open G
    Tpl([-1, 3, 2, 0, 1, 0], 0), // open C
  ],
  'm': [ // Minor
    Tpl([0, 2, 2, 0, 0, 0]),
    Tpl([-1, 0, 2, 2, 1, 0]),
    Tpl([-1, -1, 0, 2, 3, 1], 0),
  ],
  '7': [ // Dominant 7th
    Tpl([0, 2, 0, 1, 0, 0]),
    Tpl([-1, 0, 2, 0, 2, 0]),
    Tpl([-1, -1, 0, 2, 1, 2], 0),
    Tpl([3, 2, 0, 0, 0, 1], 0),
    Tpl([-1, 3, 2, 3, 1, 0], 0),
  ],
  'maj7': [
    Tpl([0, 2, 1, 1, 0, 0]),
    Tpl([-1, 0, 2, 1, 2, 0]),
    Tpl([-1, -1, 0, 2, 2, 2], 0),
    Tpl([3, 2, 0, 0, 0, 2], 0),
    Tpl([-1, 3, 2, 0, 0, 0], 0),
  ],
  'm7': [
    Tpl([0, 2, 0, 0, 0, 0]),
    Tpl([-1, 0, 2, 0, 1, 0]),
    Tpl([-1, -1, 0, 2, 1, 1], 0),
  ],
  '6': [
    Tpl([-1, 0, 2, 2, 2, 2]),
    Tpl([0, 2, 2, 1, 2, 2]),
    Tpl([-1, -1, 0, 2, 0, 0], 0),
    Tpl([3, 2, 0, 0, 0, 0], 0),
    Tpl([-1, 3, 2, 2, 1, 0], 0),
  ],
  'm6': [
    Tpl([-1, 0, 2, 2, 1, 2]),
    Tpl([0, 2, 2, 0, 2, 2]),
    Tpl([-1, -1, 0, 2, 0, 1], 0),
  ],
  'mMaj7': [
    Tpl([0, 2, 1, 0, 0, 0]),
    Tpl([-1, 0, 2, 1, 1, 0]),
  ],
  'm7b5': [
    Tpl([-1, 0, 1, 0, 1, -1]),
    Tpl([0, 1, 0, 0, -1, -1]),
  ],
  'dim': [
    Tpl([0, 1, 2, 0, -1, -1]),
    Tpl([-1, 0, 1, 2, 1, -1]),
  ],
  'dim7': [
    Tpl([-1, 0, 1, 2, 1, 2]), // symmetric: one shape covers every root at k<=7
  ],
  'aug': [
    Tpl([0, 3, 2, 1, 1, 0]),
    Tpl([-1, 0, 3, 2, 2, 1]),
    Tpl([-1, 3, 2, 1, 1, 0], 0),
  ],
  'sus2': [
    Tpl([-1, 0, 2, 2, 0, 0]),
    Tpl([0, 2, 4, 4, 0, 0]),
    Tpl([-1, -1, 0, 2, 3, 0], 0),
    Tpl([3, 0, 0, 0, 0, 3], 0),
  ],
  'sus4': [
    Tpl([-1, 0, 2, 2, 3, 0]),
    Tpl([0, 2, 2, 2, 0, 0]),
    Tpl([-1, -1, 0, 2, 3, 3], 0),
    Tpl([3, 3, 0, 0, 1, 3], 0),
    Tpl([-1, 3, 3, 3, 1, 1], 0),
  ],
  '7sus4': [
    Tpl([-1, 0, 2, 0, 3, 0]),
    Tpl([0, 2, 0, 2, 0, 0]),
  ],
  'add9': [
    Tpl([-1, 3, 2, 0, 3, 0], 0), // open C
    Tpl([3, 2, 0, 2, 3, 3], 0), // open G
    Tpl([-1, -1, 0, 2, 3, 0], 0), // open D
    Tpl([0, 2, 2, 1, 0, 2]), // open E / movable
  ],
  '9': [
    Tpl([0, 2, 0, 1, 0, 2]), // E9, movable
  ],
  '13': [
    Tpl([0, 2, 0, 1, 2, 0]), // E13, movable
    Tpl([-1, 0, 2, 0, 2, 2]), // A13, movable
  ],
  'm9': [
    Tpl([0, 2, 0, 0, 0, 2]), // Em9, movable
  ],
  '11': [
    Tpl([-1, 3, 3, 3, 3, 1]), // C11
  ],
  '6/9': [
    Tpl([-1, 3, 2, 2, 3, 3]), // C6/9
  ],
};

/// True when [frets] really sounds chord [r] of quality [q].
bool shapeValidFor(
    List<int> frets, int r, int essentialMask, int allowedMask) {
  var smask = 0;
  for (var s = 0; s < 6; s++) {
    final f = frets[s];
    if (f < 0) continue;
    smask |= 1 << ((stringPc[s] + f) % 12);
  }
  if ((rotate(essentialMask, r) & ~smask) != 0) return false;
  if ((smask & ~rotate(allowedMask, r)) != 0) return false;
  if ((smask & (1 << r)) == 0) return false;
  return true;
}

/// Best canonical (CAGED) voicing of chord [r] of quality [q], or null.
List<int>? pickTemplate(Quality q, int r, int essentialMask, int allowedMask) {
  final list = templates[q.suffix];
  if (list == null) return null;
  List<int>? bestFrets;
  var bestScore = -0x7fffffff;
  for (final t in list) {
    for (var k = 0; k <= t.maxK; k++) {
      final frets = <int>[];
      var tooHigh = false;
      for (final f in t.frets) {
        if (f < 0) {
          frets.add(-1);
          continue;
        }
        final nf = f + k;
        if (nf > 12) {
          tooHigh = true;
          break;
        }
        frets.add(nf);
      }
      if (tooHigh) continue;
      if (!shapeValidFor(frets, r, essentialMask, allowedMask)) continue;
      if (fingeringOf(List<int>.from(frets)) == null) continue;
      var minF = 99;
      for (final f in frets) {
        if (f > 0 && f < minF) minF = f;
      }
      final pos = (k == 0 && frets.contains(0)) ? 0 : (minF == 99 ? 0 : minF);
      var score = -pos * 10 + (k == 0 ? 4 : 0);
      for (final f in frets) {
        if (f == 0) score += 1; // open strings are guitar-friendly
      }
      if (score > bestScore) {
        bestScore = score;
        bestFrets = frets;
      }
    }
  }
  return bestFrets;
}

void main() {
  final sw = Stopwatch()..start();
  final chords = <Chord>[];
  final missing = <String>[];

  for (final q in qualities) {
    final allowedMask = maskOf(q.allowed);
    final essentialMask = maskOf(q.essential);
    // Pre-rotated masks per root (cheap lookup during brute force).
    final rotEss = List.generate(12, (r) => rotate(essentialMask, r));
    final rotAll = List.generate(12, (r) => rotate(allowedMask, r));
    // Best candidate per root.
    final best = List<Candidate?>.filled(12, null);

    for (var w = 0; w <= 12; w++) {
      // Fret options per string for this position window.
      final options = <int>[-1];
      for (var f = w; f <= w + 4; f++) {
        if (w == 0 && f > 4) continue; // open position: frets 1..4
        options.add(f);
      }
      final opts = options.length;

      final frets = List<int>.filled(6, 0);

      void evaluate() {
          final fing = fingeringOf(List<int>.from(frets));
          if (fing == null) return;
        var smask = 0;
        var sounding = 0, open = 0, muted = 0, fretted = 0;
        for (var s = 0; s < 6; s++) {
          final f = frets[s];
          if (f < 0) {
            muted++;
            continue;
          }
          if (f == 0) open++;
          if (f > 0) fretted++;
          sounding++;
          smask |= 1 << ((stringPc[s] + f) % 12);
        }
        if (sounding < 4 || muted > 2) return;
        // Actual position: frets 1-4 (with an open string) = open position,
        // otherwise the lowest fretted fret.
        var minFretted = 99;
        for (var s = 0; s < 6; s++) {
          final f = frets[s];
          if (f > 0 && f < minFretted) minFretted = f;
        }
        if (minFretted == 99) minFretted = 0;
        final wPos = (frets.contains(0) && minFretted <= 4) ? 0 : minFretted;
        // Must contain every essential tone of some root and nothing outside
        // the allowed tones.
        for (var r = 0; r < 12; r++) {
          final rotF = rotEss[r];
          final rotA = rotAll[r];
          if ((rotF & ~smask) != 0) continue; // missing essential tone
          if ((smask & ~rotA) != 0) continue; // foreign tone
          if ((smask & (1 << r)) == 0) continue; // root not played

          var score = -wPos * 5;
          score += sounding * 2;
          score += open * 2;
          score -= muted * 2;
          score += fretted * 2; // fuller chords first
          score -= fing.splitRuns * 7; // one finger per separate run
          score += popcount(smask & (rotA & ~rotF)) * 3; // colour tones
          // Root in the bass = the shape a chord chart actually shows.
          var bass = -1;
          for (var s = 0; s < 6; s++) {
            if (frets[s] >= 0) {
              bass = (stringPc[s] + frets[s]) % 12;
              break;
            }
          }
          if (bass == r) score += 12;
          if (fing.barreFret >= 0) score += 1;
          final cur = best[r];
          if (cur == null || score > cur.score) {
            best[r] =
                Candidate(List<int>.from(frets), score, fing);
          }
        }
      }

      void visit(int depth) {
        if (depth == 6) {
          evaluate();
          return;
        }
        for (var i = 0; i < opts; i++) {
          frets[depth] = options[i];
          visit(depth + 1);
        }
      }

      visit(0);
    }

    for (var r = 0; r < 12; r++) {
      final tFrets = pickTemplate(q, r, essentialMask, allowedMask);
      final c = tFrets ?? best[r]?.frets;
      if (c == null) {
        missing.add('${noteNames[r]}${q.suffix}');
        continue;
      }
      final fing = fingeringOf(List<int>.from(c))!;
      var startFret = 1;
      var minF = 99;
      for (final f in c) {
        if (f > 0 && f < minF) minF = f;
      }
      if (minF != 99 && minF > 1) startFret = minF;
      final notes = q.essential.toSet().union(q.allowed.toSet()).toList()
        ..sort();
      final noteStr = notes
          .map((p) => spell(r, p, preferFlat: noteNames[r].contains('b')))
          .join(' • ');
      final freqs = <double>[];
      for (var s = 0; s < 6; s++) {
        final f = c[s];
        if (f < 0) continue;
        freqs.add(double.parse(
            (openFreqs[s] * math.pow(2, f / 12)).toStringAsFixed(2)));
      }
      chords.add(Chord(r, q, List<int>.from(c), fing.fingers, fing.barreFret,
          fing.barreFrom, fing.barreTo, startFret, noteStr, freqs));
    }
  }

  sw.stop();
  stdout.writeln('Generated ${chords.length} chords in ${sw.elapsedMilliseconds}ms');
  if (missing.isNotEmpty) {
    stdout.writeln('MISSING (${missing.length}): ${missing.join(', ')}');
  }

  _write(chords);
  _selfTest(chords);
}

void _selfTest(List<Chord> chords) {
  var errors = 0;
  for (final c in chords) {
    // 1. Recompute sounding pitch classes and compare with the theory set.
    final smask = <int>{};
    for (var s = 0; s < 6; s++) {
      final f = c.frets[s];
      if (f < 0) continue;
      smask.add((stringPc[s] + f) % 12);
    }
    final root = c.root;
    final rel = smask.map((p) => (p - root) % 12).toSet();
    final allowed = c.quality.allowed.toSet();
    final essential = c.quality.essential.toSet();
    if (!allowed.containsAll(rel)) {
      stdout.writeln('FAIL ${noteNames[root]}${c.quality.suffix}: tone outside theory $rel');
      errors++;
    }
    if (!rel.containsAll(essential)) {
      stdout.writeln('FAIL ${noteNames[root]}${c.quality.suffix}: missing essential (has $rel, needs $essential)');
      errors++;
    }
    if (fingeringOf(c.frets) == null) {
      stdout.writeln('FAIL ${noteNames[root]}${c.quality.suffix}: unplayable ${c.frets}');
      errors++;
    }
    // 2. Fretboard window fits the diagram (4 frets).
    var minF = 99, maxF = 0;
    for (final f in c.frets) {
      if (f > 0) {
        if (f < minF) minF = f;
        if (f > maxF) maxF = f;
      }
    }
    if (minF != 99 && maxF - minF > 3) {
      stdout.writeln('FAIL ${noteNames[root]}${c.quality.suffix}: span ${c.frets}');
      errors++;
    }
  }
  stdout.writeln(errors == 0
      ? 'Self-test passed: every chord verified against theory + playability.'
      : 'SELF-TEST FAILED: $errors problems');
}

void _write(List<Chord> chords) {
  final b = StringBuffer();
  b.writeln('''// GENERATED FILE - do not edit by hand.
// Produced by tool/gen_chords.dart: every chord quality for all 12 roots,
// with voicings brute-forced and verified against music theory and guitar
// playability (<= 4-fret span, <= 4 fingers incl. barre).
//
// ignore_for_file: prefer_const_constructors

/// Open-string frequencies (low E, A, D, G, B, high e) in standard tuning.
const List<double> kOpenStringFreqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];

/// Pitch class of each open string (E A D G B E), C = 0.
const List<int> kOpenStringPcs = [4, 9, 2, 7, 11, 4];

/// Canonical (sharp/flat) display names for the 12 pitch classes.
const List<String> kNoteNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

/// Every spelling that should resolve to a pitch class when searching.
const Map<String, int> kNoteAliases = {
  'C': 0, 'B#': 0,
  'C#': 1, 'Db': 1,
  'D': 2,
  'D#': 3, 'Eb': 3,
  'E': 4, 'Fb': 4,
  'F': 5,
  'F#': 6, 'Gb': 6,
  'G': 7,
  'G#': 8, 'Ab': 8,
  'A': 9,
  'A#': 10, 'Bb': 10,
  'B': 11, 'Cb': 11,
};

/// Order the categories ("menus") appear in on the chords page.
const List<String> kChordGroups = [
  'Major', 'Minor', '7th', 'Extended', 'Added', 'Suspended', 'Diminished', 'Augmented',
];

/// One playable voicing of one chord.
class ChordDef {
  const ChordDef({
    required this.name,
    required this.root,
    required this.rootPc,
    required this.suffix,
    required this.group,
    required this.notes,
    required this.frets,
    required this.fingers,
    required this.rootIndex,
    required this.startFret,
    required this.barreFret,
    required this.barreFrom,
    required this.barreTo,
    required this.freqs,
    required this.formula,
  });

  /// Display name, e.g. `Bbmaj7`.
  final String name;

  /// Root display name, e.g. `Bb`.
  final String root;

  /// Root pitch class, C = 0.
  final int rootPc;

  /// Quality suffix, `''` for major, `m` for minor, ...
  final String suffix;

  /// Category this chord is filed under.
  final String group;

  /// Theory notes of the chord, e.g. `C • E • G • B`.
  final String notes;

  /// Frets low E -> high e. -1 = muted, 0 = open.
  final List<int> frets;

  /// Suggested fingers (1..4), 0 = none.
  final List<int> fingers;

  /// Index of the string carrying the root note (for highlighting).
  final int rootIndex;

  /// Topmost fret shown on the diagram (1 = open position + nut).
  final int startFret;

  /// Barre details, or -1 when the shape has no barre.
  final int barreFret;
  final int barreFrom;
  final int barreTo;

  /// Sounding string frequencies (Hz) for audio playback.
  final List<double> freqs;

  /// Semitone formula of the quality (for display / search).
  final List<int> formula;
}

/// The full chord library: every quality x every root.
const List<ChordDef> kAllChords = [''');

  for (final c in chords) {
    final name = noteNames[c.root] + c.quality.suffix;
    final root = noteNames[c.root];
    b.writeln('  ChordDef(');
    b.writeln("      name: '$name',");
    b.writeln("      root: '$root',");
    b.writeln('      rootPc: ${c.root},');
    b.writeln("      suffix: '${c.quality.suffix}',");
    b.writeln("      group: '${c.quality.group}',");
    b.writeln("      notes: '${c.notes}',");
    b.writeln('      frets: [${c.frets.join(', ')}],');
    b.writeln('      fingers: [${c.fingers.join(', ')}],');
    b.writeln('      rootIndex: ${c.rootIndexOf()},');
    b.writeln('      startFret: ${c.startFret},');
    b.writeln('      barreFret: ${c.barreFret},');
    b.writeln('      barreFrom: ${c.barreFrom},');
    b.writeln('      barreTo: ${c.barreTo},');
    b.writeln('      freqs: [${c.freqs.map((f) => f.toStringAsFixed(2)).join(', ')}],');
    final formula = (c.quality.essential.toSet().union(c.quality.allowed.toSet()).toList()..sort()).join(', ');
    b.writeln('      formula: [$formula]),');
  }
  b.writeln('];');

  File('lib/data/chord_library.dart').writeAsStringSync(b.toString());
  stdout.writeln('Wrote lib/data/chord_library.dart (${chords.length} chords)');
}

extension on Chord {
  int rootIndexOf() {
    for (var s = 0; s < 6; s++) {
      final f = frets[s];
      if (f < 0) continue;
      if ((stringPc[s] + f) % 12 == root) return s;
    }
    return 0;
  }
}
