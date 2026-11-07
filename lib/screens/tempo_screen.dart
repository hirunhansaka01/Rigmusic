import 'package:flutter/material.dart';
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

  void _changeBpm(int d) => setState(() => _bpm = (_bpm + d).clamp(30, 240));

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
              onTap: () => setState(() => _bpm = 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.touch_app, size: 16, color: AppColors.secondary), SizedBox(width: 8), Text('TAP TEMPO • Avg Sync: 120.0 BPM', style: TextStyle(fontSize: 12, color: AppColors.onSurface))]),
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
                onTap: () => setState(() {
                  _timeSig = t;
                  _beats = int.tryParse(t.split('/').first) ?? 4;
                }),
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
      onTap: () => setState(() => _subdivision = label),
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
                onTap: () => setState(() { _preset = e.key; _bpm = e.value; }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: sel ? AppColors.secondary.withValues(alpha: 0.2) : AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12), border: sel ? Border.all(color: AppColors.secondary) : null), child: Text('${e.key} • ${e.value}', style: TextStyle(fontSize: 12, color: sel ? AppColors.secondary : AppColors.onSurface))),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('SESSION CLOCK • 14:22.0', style: TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant, letterSpacing: 1)), Row(children: [Icon(Icons.flashlight_on, size: 16, color: AppColors.onSurfaceVariant), SizedBox(width: 8), Icon(Icons.volume_up, size: 16, color: AppColors.secondary)])]),
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
          onPressed: () => setState(() {
            _isPlaying = !_isPlaying;
            if (_isPlaying) _currentBeat = (_currentBeat + 1) % _beats;
          }),
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          label: Text(_isPlaying ? 'STOP' : 'START'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: AppColors.onSecondary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
        ),
      ),
    );
  }
}
