import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/reference_tone.dart';
import '../theme/app_colors.dart';

class TempoScreen extends StatefulWidget {
  const TempoScreen({super.key});

  @override
  State<TempoScreen> createState() => _TempoScreenState();
}

class _TempoScreenState extends State<TempoScreen> {
  int _bpm = 120;
  int _beats = 4;
  String _subdivision = 'Quarter';
  bool _isPlaying = false;
  bool _accentFirst = true;
  bool _haptic = true;
  int _currentBeat = 0;
  String _preset = 'Acoustic Strum';

  final _timeSigs = ['4/4', '3/4', '6/8', '2/4', '5/4', '12/8'];
  String _timeSig = '4/4';

  // ── Live metronome engine ───────────────────────────────────────────────
  // START spawns a Timer that fires one tick per subdivision; each tick
  // advances the beat, buzzes the device (Haptic Tap) and — where the
  // platform can play tones (web) — clicks a woodblock-ish pitch.
  Timer? _tickTimer;
  int _subTick = 0; // subdivisions elapsed inside the current beat
  DateTime? _runStartedAt; // when the current run began
  Duration _ranFor = Duration.zero; // elapsed from previous runs (pause keeps it)
  final List<DateTime> _taps = []; // tap-tempo samples (3 s window)
  double? _tapBpm; // last tap-computed tempo

  /// Subdivision ticks that make up one beat (♩ / ♫ / 3 / ♬).
  int get _subsPerBeat => switch (_subdivision) {
        'Eighth' => 2,
        'Triplets' => 3,
        '16th' => 4,
        _ => 1,
      };

  /// Time elapsed in the current session (frozen while stopped).
  Duration get _elapsed =>
      _ranFor +
      (_runStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_runStartedAt!));

  String get _elapsedLabel {
    final e = _elapsed;
    final m = e.inMinutes;
    final s = e.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _changeBpm(int d) {
    setState(() => _bpm = (_bpm + d).clamp(30, 240));
    if (_isPlaying) _restartTicks(); // live retune of the running pulse
  }

  /// (Re)starts the tick timer at the current bpm/subdivision.
  void _restartTicks() {
    _tickTimer?.cancel();
    _tickTimer = null;
    if (!_isPlaying) return;
    final interval =
        (60000 / _bpm / _subsPerBeat).round().clamp(20, 60000);
    _tickTimer = Timer.periodic(
        Duration(milliseconds: interval), (_) => _tick());
  }

  /// START / STOP. Starting snaps to beat 1 so the bar always opens on the
  /// downbeat; stopping freezes the session clock instead of resetting it.
  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _currentBeat = 0;
        _subTick = 0;
        _runStartedAt = DateTime.now();
      } else {
        if (_runStartedAt != null) {
          _ranFor += DateTime.now().difference(_runStartedAt!);
        }
        _runStartedAt = null;
        _tickTimer?.cancel();
        _tickTimer = null;
      }
    });
    if (_isPlaying) {
      _restartTicks();
      _tick(); // immediate downbeat instead of waiting one interval
    }
  }

  /// One subdivision step: advance the beat when due, then click/buzz.
  void _tick() {
    if (!mounted || !_isPlaying) return;
    _subTick++;
    final onBeat = _subTick % _subsPerBeat == 0;
    if (onBeat) {
      setState(() => _currentBeat = (_currentBeat + 1) % _beats);
    }
    final downbeat = onBeat && _currentBeat == 0;
    final accent = downbeat && _accentFirst;
    if (_haptic) {
      if (accent) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    // Android has no built-in click sound in this app (reference tones are
    // web-only), so there the visual pulse + haptics carry the beat; on web
    // a short high pitch doubles as the click.
    if (referenceToneSupported) {
      playTone(accent ? 1661.2 : 1108.7, seconds: 0.05).ignore();
    }
  }

  /// Real tap tempo: averages the intervals of taps made within 3 seconds
  /// and applies the result immediately (running pulse retunes live).
  void _tapTempo() {
    final now = DateTime.now();
    _taps.removeWhere((t) => now.difference(t).inMilliseconds > 3000);
    _taps.add(now);
    double? avg;
    if (_taps.length >= 2) {
      var spanMs = 0;
      for (var i = 1; i < _taps.length; i++) {
        spanMs += _taps[i].difference(_taps[i - 1]).inMilliseconds;
      }
      avg = 60000 / (spanMs / (_taps.length - 1));
    }
    if (avg == null) {
      setState(() {}); // first tap — nothing to average yet
      return;
    }
    final tapped = avg.clamp(30.0, 240.0).toDouble();
    setState(() {
      _tapBpm = tapped;
      _bpm = tapped.round();
    });
    if (_isPlaying) _restartTicks();
  }

  void _setSubdivision(String label) {
    setState(() => _subdivision = label);
    if (_isPlaying) _restartTicks();
  }

  void _setTimeSig(String t) {
    setState(() {
      _timeSig = t;
      _beats = int.tryParse(t.split('/').first) ?? 4;
      _currentBeat %= _beats; // keep the highlight inside the new bar
    });
    if (_isPlaying) _restartTicks();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            _header(context),
            const SizedBox(height: 8),
            _engineBadge(),
            const SizedBox(height: 12),
            _bpmCard(context),
            const SizedBox(height: 16),
            _pulseMatrix(context),
            const SizedBox(height: 16),
            _meterSection(context),
            const SizedBox(height: 16),
            _toggles(context),
            const SizedBox(height: 16),
            _coachCard(context),
            const SizedBox(height: 16),
            _presets(context),
            const SizedBox(height: 16),
            _startButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.music_note, color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RIG / Tempo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 15, color: AppColors.secondary, fontWeight: FontWeight.w600)),
              const Text('GUITAR TOOLKIT • 440Hz', style: TextStyle(fontSize: 8, color: AppColors.tertiaryFixedDim, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(999)),
            child: const Row(children: [Icon(Icons.speed, size: 14, color: AppColors.secondary), SizedBox(width: 4), Text('TEMPO', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontWeight: FontWeight.w700))]),
          ),
        ],
      ),
    );
  }

  Widget _engineBadge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLow.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.graphic_eq, color: AppColors.secondary)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Groove & Tempo Hub', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)), Text('Rack Unit • Engine 01 • Woodblock', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant))])),
            const Icon(Icons.expand_more, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _bpmCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLow.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 36)]),
        child: Column(
          children: [
            const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.speed, size: 14, color: AppColors.secondary), SizedBox(width: 6), Text('ALLEGRO • 120–156 BPM RANGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondary, letterSpacing: 1.2))]),
            const SizedBox(height: 12),
            Text('$_bpm', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 64, color: AppColors.onSurface, fontWeight: FontWeight.w700)),
            const Text('BPM', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant, letterSpacing: 2)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn('−5', () => _changeBpm(-5)),
                _stepBtn('−1', () => _changeBpm(-1)),
                _stepBtn('+1', () => _changeBpm(1)),
                _stepBtn('+5', () => _changeBpm(5)),
              ],
            ),
            const SizedBox(height: 12),
            // slider look
            Container(height: 6, decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(999)), child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: (_bpm - 30) / 210, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.secondary, AppColors.primary]), borderRadius: BorderRadius.circular(999))))),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _tapTempo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.touch_app, size: 16, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Text(
                      'TAP TEMPO • Avg Sync: ${_tapBpm == null ? 'tap to set' : '${_tapBpm!.toStringAsFixed(1)} BPM'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.onSurface)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)), child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary))),
      ),
    );
  }

  Widget _pulseMatrix(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surfaceContainer.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Pulse Matrix • $_timeSig Meter', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)), Text('Bar 01 : Beat ${_currentBeat + 1}', style: const TextStyle(fontSize: 10, color: AppColors.tertiary))]),
            const SizedBox(height: 12),
            Row(
              children: List.generate(_beats, (i) {
                final active = _isPlaying && i == _currentBeat;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 64,
                    decoration: BoxDecoration(color: active ? AppColors.secondary : AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), boxShadow: active ? [BoxShadow(color: AppColors.secondary.withValues(alpha: 0.5), blurRadius: 12)] : null),
                    child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: active ? AppColors.onSecondary : AppColors.onSurfaceVariant))),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(_beats > 0 ? 'Beat 1 Downbeat' : '', style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _meterSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time Signature • Meter Mode', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _timeSigs.map((t) {
              final sel = t == _timeSig;
              return GestureDetector(
                onTap: () => _setTimeSig(t),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: sel ? AppColors.secondary : AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)), child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: sel ? AppColors.onSecondary : AppColors.onSurface))),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('Note Subdivision • Grid Resolution', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              _subChip('Quarter', '♩'),
              _subChip('Eighth', '♫'),
              _subChip('Triplets', '3'),
              _subChip('16th', '♬'),
            ].map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: w))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _subChip(String label, String glyph) {
    final sel = label == _subdivision;
    return GestureDetector(
      onTap: () => _setSubdivision(label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: sel ? AppColors.tertiary.withValues(alpha: 0.2) : AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12), border: sel ? Border.all(color: AppColors.tertiary) : null),
        child: Column(children: [Text(glyph, style: TextStyle(fontSize: 16, color: sel ? AppColors.tertiary : AppColors.onSurface)), Text(label, style: TextStyle(fontSize: 9, color: sel ? AppColors.tertiary : AppColors.onSurfaceVariant))]),
      ),
    );
  }

  Widget _toggles(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(child: _switchTile(Icons.volume_up, 'Accent 1st', _accentFirst, (v) => setState(() => _accentFirst = v))),
          const SizedBox(width: 10),
          Expanded(child: _switchTile(Icons.vibration, 'Haptic Tap', _haptic, (v) => setState(() => _haptic = v))),
        ],
      ),
    );
  }

  Widget _switchTile(IconData icon, String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [Icon(icon, size: 18, color: AppColors.secondary), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))), Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.secondary)]),
    );
  }

  Widget _coachCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLow.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [const Icon(Icons.trending_up, size: 16, color: AppColors.tertiary), const SizedBox(width: 6), Text('Speed Workout Coach', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.tertiary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)), child: const Text('Drill Active', style: TextStyle(fontSize: 10, color: AppColors.tertiary, fontWeight: FontWeight.w700)))]),
            const SizedBox(height: 8),
            const Row(children: [Icon(Icons.fitness_center, size: 14, color: AppColors.onSurfaceVariant), SizedBox(width: 6), Text('Gradual Auto-Ramp • +2 BPM / 4 Bars', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))]),
            const SizedBox(height: 6),
            const Text('Start: 100 BPM • Target: 140 BPM', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: ['None', '1 Bar', '2 Bars'].map((l) => Padding(padding: const EdgeInsets.only(right: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: l == '1 Bar' ? AppColors.secondary : AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)), child: Text(l, style: TextStyle(fontSize: 11, color: l == '1 Bar' ? AppColors.onSecondary : AppColors.onSurface))))).toList()),
          ],
        ),
      ),
    );
  }

  Widget _presets(BuildContext context) {
    final presets = {'Slow Blues': 72, 'Acoustic Strum': 95, 'Rock Drive': 124, 'Speed Solo': 160};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Studio Presets', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: presets.entries.map((e) {
              final sel = _preset == e.key;
              return GestureDetector(
                onTap: () {
                  setState(() { _preset = e.key; _bpm = e.value; });
                  if (_isPlaying) _restartTicks();
                },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: sel ? AppColors.secondary.withValues(alpha: 0.2) : AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12), border: sel ? Border.all(color: AppColors.secondary) : null), child: Text('${e.key} • ${e.value}', style: TextStyle(fontSize: 12, color: sel ? AppColors.secondary : AppColors.onSurface))),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('SESSION CLOCK • $_elapsedLabel', style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant, letterSpacing: 1)), Row(children: [Icon(Icons.flashlight_on, size: 16, color: _isPlaying ? AppColors.tertiary : AppColors.onSurfaceVariant), const SizedBox(width: 8), Icon(Icons.volume_up, size: 16, color: referenceToneSupported ? AppColors.secondary : AppColors.onSurfaceVariant)])]),
        ],
      ),
    );
  }

  Widget _startButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton.icon(
          onPressed: _togglePlay,
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          label: Text(_isPlaying ? 'STOP' : 'START'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: AppColors.onSecondary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
        ),
      ),
    );
  }
}
