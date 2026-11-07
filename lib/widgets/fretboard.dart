import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Minimal fretboard diagram (portrait neck, strings vertical).
/// [frets] low-E → high-e, -1 = muted, 0 = open. [fingers] same order,
/// 0 = no number shown. [rootIndex] highlights the root note.
/// [startFret] is the topmost displayed fret (1 = open position + nut).
/// [barreFret] >= 0 draws one finger barred across [barreFrom]..[barreTo].
class Fretboard extends StatelessWidget {
  final List<int> frets;
  final List<int> fingers;
  final int rootIndex;
  final int startFret;
  final int barreFret;
  final int barreFrom;
  final int barreTo;
  final List<String> strings;
  final double height;

  const Fretboard({
    super.key,
    required this.frets,
    required this.fingers,
    required this.rootIndex,
    this.startFret = 1,
    this.barreFret = -1,
    this.barreFrom = -1,
    this.barreTo = -1,
    this.strings = const ['E', 'A', 'D', 'G', 'B', 'e'],
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(6, (i) {
            final f = frets[i];
            if (f < 0) {
              return const SizedBox(
                  width: 20,
                  child: Text('✕', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)));
            }
            if (f == 0) {
              return const SizedBox(
                  width: 20,
                  child: Text('○', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)));
            }
            final rel = f - startFret + 1;
            return SizedBox(
              width: 20,
              child: Text('$rel',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
            );
          }),
        ),
        const SizedBox(height: 4),
        if (startFret == 1)
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _FretboardPainter(
              frets: frets,
              fingers: fingers,
              rootIndex: rootIndex,
              startFret: startFret,
              barreFret: barreFret,
              barreFrom: barreFrom,
              barreTo: barreTo,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(6, (i) {
            final isRoot = i == rootIndex;
            return SizedBox(
              width: 20,
              child: Text(strings[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: isRoot ? AppColors.accent : AppColors.onSurfaceVariant)),
            );
          }),
        ),
      ],
    );
  }
}

class _FretboardPainter extends CustomPainter {
  final List<int> frets;
  final List<int> fingers;
  final int rootIndex;
  final int startFret;
  final int barreFret;
  final int barreFrom;
  final int barreTo;

  _FretboardPainter({
    required this.frets,
    required this.fingers,
    required this.rootIndex,
    required this.startFret,
    this.barreFret = -1,
    this.barreFrom = -1,
    this.barreTo = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const fretSpaces = 4;
    final stringGap = size.width / 6;
    final fretGap = size.height / fretSpaces;
    final line = Paint()
      ..color = AppColors.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    // Frets (horizontal).
    for (var f = 1; f <= fretSpaces; f++) {
      canvas.drawLine(Offset(0, f * fretGap), Offset(size.width, f * fretGap), line);
    }
    // Strings (vertical, thicker toward low E).
    for (var s = 0; s < 6; s++) {
      final x = stringGap * (s + 0.5);
      final p = Paint()
        ..color = AppColors.outlineVariant
        ..strokeWidth = 1.8 - (s * 0.2);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }

    // Barre: one finger laid across several strings, drawn as a capsule.
    if (barreFret >= 0 && barreFrom >= 0 && barreTo >= barreFrom) {
      final rel = barreFret - startFret + 1;
      if (rel >= 1 && rel <= fretSpaces) {
        final x1 = stringGap * (barreFrom + 0.5);
        final x2 = stringGap * (barreTo + 0.5);
        final y = fretGap * (rel - 0.5);
        // A barre spans several strings, so it never carries the root
        // highlight (that stays on the single root dot).
        final capsule = Paint()..color = AppColors.surfaceContainerHighest;
        final rRect = RRect.fromRectAndRadius(
          Rect.fromPoints(Offset(x1 - 9, y - 9), Offset(x2 + 9, y + 9)),
          const Radius.circular(9),
        );
        canvas.drawRRect(rRect, capsule);
        // Finger number on the barre (leftmost barred string).
        final barreFinger = fingers[barreFrom] > 0 ? fingers[barreFrom] : 1;
        final tp = TextPainter(
          text: TextSpan(
              text: '$barreFinger',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x1 - tp.width / 2, y - tp.height / 2));
      }
    }

    // Finger dots.
    for (var s = 0; s < 6; s++) {
      final f = frets[s];
      if (f <= 0) continue;
      final rel = f - startFret + 1;
      if (rel < 1 || rel > fretSpaces) continue;
      // Strings already covered by the barre capsule: skip their dot.
      if (barreFret >= 0 &&
          s >= barreFrom &&
          s <= barreTo &&
          f == barreFret) {
        continue;
      }
      final x = stringGap * (s + 0.5);
      final y = fretGap * (rel - 0.5);
      final isRoot = s == rootIndex;
      final dot = Paint()..color = isRoot ? AppColors.accent : AppColors.surfaceContainerHighest;
      canvas.drawCircle(Offset(x, y), 10, dot);
      final label = fingers[s] > 0 ? '${fingers[s]}' : '';
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isRoot ? AppColors.onAccent : AppColors.onSurface)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) =>
      old.frets != frets || old.fingers != fingers || old.rootIndex != rootIndex || old.startFret != startFret ||
      old.barreFret != barreFret || old.barreFrom != barreFrom || old.barreTo != barreTo;
}
