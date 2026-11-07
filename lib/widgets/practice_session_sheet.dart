import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-screen-ish bottom sheet that runs a live practice timer.
///
/// Shows a big MM:SS clock counting up and a Stop button. When stopped it
/// pops itself and invokes [onStop] with the elapsed minutes (rounded to the
/// nearest minute), so the caller can log it to Firestore.
class PracticeSessionSheet extends StatefulWidget {
  const PracticeSessionSheet({super.key, required this.title, required this.onStop});

  final String title;

  /// Called after the sheet closes with the whole minutes practiced
  /// (0 if the session was shorter than 30 seconds).
  final Future<void> Function(int minutes) onStop;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Future<void> Function(int minutes) onStop,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PracticeSessionSheet(title: title, onStop: onStop),
    );
  }

  @override
  State<PracticeSessionSheet> createState() => _PracticeSessionSheetState();
}

class _PracticeSessionSheetState extends State<PracticeSessionSheet> {
  Timer? _timer;
  int _seconds = 0;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _timer?.cancel();
    final minutes = (_seconds / 60).round();
    if (mounted) Navigator.pop(context);
    try {
      await widget.onStop(minutes);
    } catch (_) {
      // The caller surfaces its own error; swallow so the timer never crashes.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.timer, size: 28, color: AppColors.accent),
            const SizedBox(height: 8),
            const Text('PRACTICE SESSION',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
            const SizedBox(height: 24),
            Text(
              _fmt(_seconds),
              style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.accent),
            ),
            const SizedBox(height: 6),
            const Text('Keep those fingers moving',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _stopping ? null : _stop,
                icon: const Icon(Icons.stop, size: 20),
                label: const Text('End Session',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Minutes are saved to your profile when you end.',
                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
