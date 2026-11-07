import 'dart:async';

import 'package:flutter/material.dart';

import '../services/riff_recorder.dart';
import '../services/riff_store.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_message.dart';

/// Capture guitar riffs from the microphone and play them back.
/// Saved riffs persist across reloads (see [RiffStore]).
class RiffRecorderScreen extends StatefulWidget {
  const RiffRecorderScreen({super.key});

  @override
  State<RiffRecorderScreen> createState() => _RiffRecorderScreenState();
}

class _RiffRecorderScreenState extends State<RiffRecorderScreen> {
  final RiffRecorder _recorder = createRiffRecorder();
  final List<Riff> _riffs = <Riff>[];

  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  /// Rehydrate previously saved riffs (most recent first).
  Future<void> _loadSaved() async {
    final saved = await RiffStore.instance.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _riffs.addAll(saved));
  }

  Future<void> _persist() async {
    await RiffStore.instance.save(_riffs);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose().ignore();
    super.dispose();
  }

  // ── Recording ────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (!riffRecorderSupported) {
      showAuthMessage(context, 'Recording needs a browser.', error: true);
      return;
    }
    try {
      await _recorder.start();
    } catch (_) {
      if (!mounted) return;
      showAuthMessage(context, 'Could not access the microphone.', error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final url = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _seconds = 0;
      if (url != null) _riffs.insert(0, Riff(url: url, time: DateTime.now()));
    });
    if (url != null) _persist();
  }

  void _toggleRecord() {
    if (_recording) {
      _stop();
    } else {
      _start();
    }
  }

  // ── Playback ─────────────────────────────────────────────────────────

  Future<void> _togglePlay(Riff riff) async {
    if (_playingUrl == riff.url) {
      _recorder.stopPlay();
      if (mounted) setState(() => _playingUrl = null);
      return;
    }
    try {
      await _recorder.play(riff.url);
    } catch (_) {
      if (mounted) showAuthMessage(context, 'Could not play this riff.', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _playingUrl = riff.url);
  }

  void _delete(Riff riff) {
    if (_playingUrl == riff.url) {
      _recorder.stopPlay();
      _playingUrl = null;
    }
    setState(() => _riffs.removeWhere((r) => r.url == riff.url));
    _persist();
  }

  // ── Formatting ───────────────────────────────────────────────────────

  String _formatElapsed(int total) {
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _clockTime(DateTime t) {
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerLow,
                        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.arrow_back, size: 18, color: AppColors.onSurface),
                    ),
                  ),
                  const Expanded(
                    child: Text('Riff Recorder',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
          ),
        ),
      ),
      body: !riffRecorderSupported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Recording needs a browser.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant, height: 1.4)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _recordSection(),
                  const SizedBox(height: 32),
                  _riffListSection(),
                ],
              ),
            ),
    );
  }

  Widget _recordSection() {
    return Column(
      children: [
        const SizedBox(height: 24),
        GestureDetector(
          onTap: riffRecorderSupported ? _toggleRecord : null,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording ? AppColors.error : AppColors.primary,
              boxShadow: _recording
                  ? [BoxShadow(color: AppColors.error.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 4)]
                  : null,
            ),
            child: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: _recording ? 44 : 40,
              color: _recording ? AppColors.onError : AppColors.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_recording)
          Text(
            _formatElapsed(_seconds),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.error),
          )
        else
          const Text(
            'Tap to record — playing your guitar out loud.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.4),
          ),
      ],
    );
  }

  Widget _riffListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('YOUR RIFFS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_riffs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'No riffs yet — hit record to capture your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.4),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _riffs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _riffRow(_riffs[index]),
          ),
      ],
    );
  }

  Widget _riffRow(Riff riff) {
    final playing = _playingUrl == riff.url;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: playing
                ? AppColors.primary.withValues(alpha: 0.45)
                : AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _togglePlay(riff),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainerHigh,
                border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: playing ? AppColors.primary : AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_clockTime(riff.time),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                const SizedBox(height: 2),
                Text(_relative(riff.time),
                    style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(riff),
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
