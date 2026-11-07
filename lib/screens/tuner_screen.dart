import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/pitch_source.dart';
import '../services/reference_tone.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_message.dart';

/// Minimal tuner (guitar_tuner_minimal). Detection engine (YIN),
/// presets, string logic and mic handling unchanged — only the skin is new.
class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => TunerScreenState();
}

class TunerScreenState extends State<TunerScreen> {
  late final PitchSource _pitchSource;
  StreamSubscription<double?>? _pitchSubscription;
  var _presetIndex = 0;
  var _selectedString = 0; // set to the 1st (highest) string in initState
  var _isListening = false;
  var _starting = false;
  double? _frequency;
  String? _error;

  /// Strings confirmed in-tune this session (highlighted on the peg row).
  final Set<int> _tuned = <int>{};
  int? _streakString;
  int _streakCount = 0;
  DateTime? _cooldownUntil;

  /// Consecutive in-tune readings required before a string locks in as tuned.
  static const int _confirmStreak = 8;

  /// Playing / advance order: highest-pitched string first (1st) down to the
  /// lowest (6th for guitar, 4th for bass, etc.). Derived from the active
  /// preset so instruments of any string count advance correctly.
  List<int> get _tuneOrder =>
      [for (var i = _preset.notes.length - 1; i >= 0; i--) i];

  // Each preset lists strings from LOWEST pitch (index 0) to HIGHEST (last),
  // matching the string-number convention where the 1st string is the highest.
  static const _presets = [
    _TuningPreset('Standard', 'Guitar', ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]),
    _TuningPreset('Drop D', 'Guitar', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'], [73.42, 110.00, 146.83, 196.00, 246.94, 329.63]),
    _TuningPreset('DADGAD', 'Guitar', ['D2', 'A2', 'D3', 'G3', 'A3', 'D4'], [73.42, 110.00, 146.83, 196.00, 220.00, 293.66]),
    _TuningPreset('Open G', 'Guitar', ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'], [73.42, 98.00, 146.83, 196.00, 246.94, 293.66]),
    _TuningPreset('7-String', 'Guitar', ['B1', 'E2', 'A2', 'D3', 'G3', 'B3', 'E4'], [61.74, 82.41, 110.00, 146.83, 196.00, 246.94, 329.63]),
    _TuningPreset('12-String', 'Guitar', ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]),
    _TuningPreset('4-String Bass', 'Bass', ['E1', 'A1', 'D2', 'G2'], [41.20, 55.00, 73.42, 98.00]),
    _TuningPreset('5-String Bass', 'Bass', ['B0', 'E1', 'A1', 'D2', 'G2'], [30.87, 41.20, 55.00, 73.42, 98.00]),
  ];

  _TuningPreset get _preset => _presets[_presetIndex];
  double get _targetFrequency => _preset.frequencies[_selectedString];
  String get _targetNote => _preset.notes[_selectedString];
  double? get _cents => _frequency == null ? null : 1200 * (math.log(_frequency! / _targetFrequency) / math.ln2);
  bool get _isInTune => _cents != null && _cents!.abs() <= 5;
  bool get _allTuned => _tuned.length == _preset.notes.length;

  String get _noteLetter => _targetNote.replaceAll(RegExp(r'[0-9]'), '');
  String get _noteOctave => _targetNote.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  void initState() {
    super.initState();
    _pitchSource = createPitchSource();
    _selectedString = _tuneOrder.first; // 1st (highest) string of the default preset
  }

  @override
  void dispose() {
    _pitchSubscription?.cancel();
    _pitchSource.dispose();
    super.dispose();
  }

  /// Starts the live mic. There is no mic button: the scaffold calls this
  /// whenever the TUNER tab becomes the visible one.
  Future<void> startMic() async {
    if (_isListening || _starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      await _pitchSource.start();
      _pitchSubscription = _pitchSource.frequencies.listen(_onFrequency, onError: (Object error) async {
        // The source itself failed (mic denied / unavailable): surface a
        // friendly banner and return to the idle state. Switching away and
        // back retries automatically.
        if (mounted) {
          setState(() {
            _error = _friendlyError(error);
            _resetToIdle();
          });
        }
        await _pitchSubscription?.cancel();
        _pitchSubscription = null;
        await _pitchSource.stop();
      });
      if (mounted) setState(() => _isListening = true);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      _starting = false;
    }
  }

  /// Stops the live mic and clears the reading. Called when the user leaves
  /// the TUNER tab, and again on dispose.
  Future<void> stopMic() async {
    await _pitchSubscription?.cancel();
    _pitchSubscription = null;
    await _pitchSource.stop();
    if (mounted) setState(_resetToIdle);
  }

  /// Back to "nothing heard yet" (used when leaving the tab or on mic error).
  void _resetToIdle() {
    _isListening = false;
    _frequency = null;
    _selectedString = _tuneOrder.first;
    _tuned.clear();
    _streakString = null;
    _streakCount = 0;
    _cooldownUntil = null;
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('permission') ||
        message.contains('denied') ||
        message.contains('blocked')) {
      return 'Microphone access was blocked. Allow it for Rig Music in your '
          'browser or device settings, then try again.';
    }
    return 'Could not start the microphone. ${error.toString().replaceFirst('Exception: ', '')}';
  }

  void _onFrequency(double? frequency) {
    // Sustained silence (source emits null): drop the stale reading so the
    // meter returns to rest and the status reverts to "Listening…" instead
    // of freezing on the last pluck forever. Streaks are left untouched, so
    // a quick re-pluck doesn't punish an otherwise stable string.
    if (frequency == null) {
      if (mounted && _frequency != null) setState(() => _frequency = null);
      return;
    }

    // Ignore readings during the post-tune handoff so the newly advanced
    // target isn't immediately snapped back by the still-ringing string.
    final now = DateTime.now();
    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) return;

    var closest = 0;
    var smallestDistance = double.infinity;
    for (var index = 0; index < _preset.frequencies.length; index++) {
      final distance = (1200 * (math.log(frequency / _preset.frequencies[index]) / math.ln2)).abs();
      if (distance < smallestDistance) {
        smallestDistance = distance;
        closest = index;
      }
    }

    final targetFreq = _preset.frequencies[closest];
    final cents = 1200 * (math.log(frequency / targetFreq) / math.ln2);
    final inTune = cents.abs() <= 5;

    if (mounted) {
      setState(() {
        _frequency = frequency;
        _selectedString = closest;
        if (inTune) {
          if (_streakString == closest) {
            _streakCount++;
          } else {
            _streakString = closest;
            _streakCount = 1;
          }
        } else {
          _streakString = null;
          _streakCount = 0;
        }
      });
    }

    // Lock the string in once it has been stable in-tune for long enough.
    if (inTune && !_tuned.contains(closest) && _streakCount >= _confirmStreak) {
      _confirmTuned(closest);
    }
  }

  /// Marks [index] as tuned, plays the success chime and advances to the next
  /// untuned string in playing order (highest → lowest).
  Future<void> _confirmTuned(int index) async {
    _tuned.add(index);
    _streakString = null;
    _streakCount = 0;
    _cooldownUntil = DateTime.now().add(const Duration(milliseconds: 850));

    int? next;
    for (final i in _tuneOrder) {
      if (!_tuned.contains(i)) {
        next = i;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _frequency = null; // reset the meter for a clean handoff
        if (next != null) _selectedString = next;
      });
    }

    await _playTunedChime();

    // Release the handoff lock once it elapses so auto-detect resumes.
    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted && _cooldownUntil != null && !DateTime.now().isBefore(_cooldownUntil!)) {
        setState(() => _cooldownUntil = null);
      }
    });
  }

  /// Bright two-note ascending "ding" (like GuitarTuna) when a string locks in.
  Future<void> _playTunedChime() async {
    if (!referenceToneSupported) return;
    try {
      await playTone(880.0, seconds: 0.35); // A5
      await Future.delayed(const Duration(milliseconds: 85));
      await playTone(1318.51, seconds: 0.5); // E6 — a bright perfect fifth up
    } catch (_) {
      // Audio is best-effort; never let a chime failure break tuning.
    }
  }

  void _selectPreset(int index) {
    setState(() {
      _presetIndex = index;
      _selectedString = _tuneOrder.first; // start at the 1st string (high E)
      _frequency = null;
      _tuned.clear();
      _streakString = null;
      _streakCount = 0;
      _cooldownUntil = null;
    });
  }

  void _pickPreset() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 8),
            ...List.generate(_presets.length, (i) {
              final selected = i == _presetIndex;
              return ListTile(
                title: Text(_presets[i].name,
                    style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                subtitle: Text(_presets[i].notes.map((n) => n.replaceAll(RegExp(r'[0-9]'), '')).join(' '),
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                trailing: selected ? const Icon(Icons.check, color: AppColors.accent) : null,
                onTap: () {
                  _selectPreset(i);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _playReference() async {
    if (!referenceToneSupported) {
      showAuthMessage(context, 'Reference tones need a browser for now.', error: false);
      return;
    }
    try {
      await playTone(_targetFrequency);
    } catch (_) {
      if (mounted) showAuthMessage(context, 'Could not play reference tone.', error: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cents = _cents;
    return SafeArea(
      child: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _presetRow(),
                  const SizedBox(height: 32),
                  _status(cents),
                  const SizedBox(height: 8),
                  _heroNote(),
                  const SizedBox(height: 8),
                  Text(
                    '${(_frequency ?? _targetFrequency).toStringAsFixed(1)} Hz',
                    style: const TextStyle(fontSize: 12, letterSpacing: 1.0, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 40),
                  _meter(cents),
                  const SizedBox(height: 40),
                  _stringPegs(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppColors.error)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, size: 14, color: AppColors.onSurface),
          ),
          const SizedBox(width: 10),
          const Text('Rig Music',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
          const Spacer(),
          IconButton(
            tooltip: 'Tuning presets',
            onPressed: _pickPreset,
            icon: const Icon(Icons.tune, size: 19, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _presetRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: _pickPreset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_preset.instrument} • ${_preset.name}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                const SizedBox(width: 6),
                Text('(${_preset.shortNotes})',
                    style: const TextStyle(fontSize: 10, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more, size: 14, color: AppColors.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const Row(
          children: [
            Icon(Icons.circle, size: 6, color: AppColors.tertiary),
            SizedBox(width: 6),
            Text('A₄ = 440 Hz',
                style: TextStyle(fontSize: 11, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _status(double? cents) {
    final inTune = _isInTune;
    final allTuned = _allTuned;
    final String text;
    if (allTuned) {
      text = 'All strings in tune!';
    } else if (_frequency == null) {
      text = _isListening ? 'Listening…' : 'Starting microphone…';
    } else {
      text = inTune ? 'In Tune' : (cents! < 0 ? 'Flat — tune up' : 'Sharp — tune down');
    }
    final color = allTuned || (_frequency != null && inTune) ? AppColors.tertiary : AppColors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 6, color: color),
        const SizedBox(width: 6),
        Text(text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 2.0, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }

  Widget _heroNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_noteLetter,
            style: const TextStyle(
                fontSize: 112, height: 1, fontWeight: FontWeight.w300, color: AppColors.onSurface)),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(_noteOctave,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w400, color: AppColors.tertiary)),
        ),
      ],
    );
  }

  Widget _meter(double? cents) {
    final clamped = cents == null ? 0.0 : (cents / 50).clamp(-1.0, 1.0);
    final centerText = cents == null ? '—' : '${cents.abs().toStringAsFixed(0)} ¢';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(children: [
              Icon(Icons.west, size: 12, color: AppColors.onSurfaceVariant),
              SizedBox(width: 4),
              Text('FLAT', style: TextStyle(fontSize: 11, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
            ]),
            Text(centerText,
                style: const TextStyle(fontSize: 10, letterSpacing: 1.5, color: AppColors.tertiary)),
            const Row(children: [
              Text('SHARP', style: TextStyle(fontSize: 11, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
              SizedBox(width: 4),
              Icon(Icons.east, size: 12, color: AppColors.onSurfaceVariant),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final x = (clamped + 1) / 2 * constraints.maxWidth;
            return SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(11, (i) {
                      final tall = i % 5 == 0 || i == 2 || i == 8;
                      return Container(
                        width: 1,
                        height: tall ? 10 : 6,
                        color: AppColors.outlineVariant.withValues(alpha: tall ? 0.7 : 0.4),
                      );
                    }),
                  ),
                  Positioned(
                    left: (x - 5).clamp(0.0, constraints.maxWidth - 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.tertiary,
                            boxShadow: [
                              BoxShadow(color: AppColors.tertiary.withValues(alpha: 0.4), blurRadius: 8)
                            ],
                          ),
                        ),
                        Container(width: 2, height: 10, color: AppColors.tertiary.withValues(alpha: 0.6)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _stringPegs() {
    return Column(
      children: [
        // Progress: how many strings are locked in so far.
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('TUNED  ${_tuned.length}/${_preset.notes.length}',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w500,
                      color: _allTuned ? AppColors.tertiary : AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_tuneOrder.length, (k) {
                final i = _tuneOrder[k]; // string index (1st → 6th, left to right)
                final active = i == _selectedString && !_tuned.contains(i);
                final tuned = _tuned.contains(i);
                final letter = _preset.notes[i].replaceAll(RegExp(r'[0-9]'), '');
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedString = i;
                    _frequency = null;
                    _streakString = null;
                    _streakCount = 0;
                    _cooldownUntil = null;
                  }),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tuned ? AppColors.tertiary : AppColors.surfaceContainer,
                          border: Border.all(
                            color: tuned
                                ? AppColors.tertiary
                                : (active ? AppColors.accent : AppColors.outlineVariant.withValues(alpha: 0.4)),
                            width: active ? 1.6 : 1,
                          ),
                          boxShadow: tuned
                              ? [BoxShadow(color: AppColors.tertiary.withValues(alpha: 0.4), blurRadius: 10)]
                              : (active
                                  ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 8)]
                                  : null),
                        ),
                        child: Center(
                          child: tuned
                              ? const Icon(Icons.check_rounded, size: 18, color: AppColors.onTertiary)
                              : Text(letter,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: active ? AppColors.accent : AppColors.onSurfaceVariant)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${_preset.notes.length - i}',
                          style: TextStyle(
                              fontSize: 10,
                              color: tuned
                                  ? AppColors.tertiary
                                  : (active ? AppColors.accent : AppColors.onSurfaceVariant))),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _playReference,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_up, size: 14, color: AppColors.onSurfaceVariant),
                SizedBox(width: 6),
                Text('Play Reference Tone',
                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TuningPreset {
  const _TuningPreset(this.name, this.instrument, this.notes, this.frequencies);

  final String name;
  final String instrument; // 'Guitar' or 'Bass'
  final List<String> notes;
  final List<double> frequencies;

  String get shortNotes => notes.map((n) => n.replaceAll(RegExp(r'[0-9]'), '')).join(' ');
}
