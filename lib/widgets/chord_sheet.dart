import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../theme/app_colors.dart';

/// Renders a song section with chords sitting ABOVE the lyric words.
///
/// Layout (classic chord chart):
///
///     Am                E7
///   On a dark desert highway, cool wind in my hair
///
/// - Chords: [AppColors.accent] mint, bold, slightly larger.
/// - Lyrics: soft white below. Each word is its own column so the chord
///   always sits directly over the syllable it belongs to, and words wrap
///   naturally like normal text.
class ChordSheet extends StatelessWidget {
  const ChordSheet({super.key, required this.sections});

  final List<SongSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          _SectionHeader(name: section.name),
          for (final line in section.lines) _ChordLineRow(line),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// One lyric line rendered as a wrapping row of word-columns.
class _ChordLineRow extends StatelessWidget {
  const _ChordLineRow(this.line);

  final ChordLine line;

  @override
  Widget build(BuildContext context) {
    // Keep words together so a wrapped line does not split mid-word.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 0,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final word in line.words) _WordColumn(word),
        ],
      ),
    );
  }
}

/// A single word with its optional chord label above it.
class _WordColumn extends StatelessWidget {
  const _WordColumn(this.word);

  final ChordWord word;

  @override
  Widget build(BuildContext context) {
    final chord = word.chord;

    // Chord label row (top). Empty spacer keeps the lyric baseline aligned
    // when a word has no chord of its own.
    final chordLabel = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        chord ?? '',
        style: TextStyle(
          fontSize: 15,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: AppColors.accent,
          // A touch of glow so chords pop off the lyrics.
          shadows: [
            Shadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );

    // Lyric word (bottom). Trailing space keeps words separated.
    final lyric = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '${word.text} ',
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurface,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed-height chord slot so lyrics line up even when some words
        // have chords and others do not.
        SizedBox(height: 20, child: chordLabel),
        lyric,
      ],
    );
  }
}
