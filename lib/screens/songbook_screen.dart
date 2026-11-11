import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/gemini_service.dart';
import '../services/oracle_history.dart';
import '../theme/app_colors.dart';
import '../widgets/chord_sheet.dart';

/// SONGS tab = the single AI Song Finder ("Oracle").
///
/// This used to be two pages (a dummy songbook that pushed a real finder).
/// Now it is ONE page: search → Oracle returns a chord sheet with the chords
/// in mint ABOVE the lyrics. Recent searches persist across app launches.
class SongbookScreen extends StatefulWidget {
  const SongbookScreen({super.key});

  @override
  State<SongbookScreen> createState() => _SongbookScreenState();
}

class _SongbookScreenState extends State<SongbookScreen> {
  final _ctrl = TextEditingController();
  final _service = GeminiService.instance;
  final _historyStore = OracleHistory.instance;

  bool _hasKey = false;
  bool _loading = false;
  String? _error;
  SongChords? _song;
  String _query = '';
  List<OracleHistoryEntry> _history = [];

  // Key-setup state
  final _keyCtrl = TextEditingController();
  bool _savingKey = false;

  static const _suggestions = [
    'Hotel California — Eagles',
    'Blackbird — The Beatles',
    'Wonderwall — Oasis',
    'Let It Be — The Beatles',
    'Wish You Were Here — Pink Floyd',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final key = await _service.getApiKey();
    final history = await _historyStore.load();
    if (mounted) {
      setState(() {
        _hasKey = key != null && key.isNotEmpty;
        _history = history;
      });
    }
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _query = q;
      _song = null;
    });
    try {
      final result = await _service.findSong(q);
      if (!mounted) return;
      // Save to history (most recent first) and show the result.
      final updated = await _historyStore.add(q, result.rawJson);
      if (!mounted) return;
      setState(() {
        _song = result.song;
        _history = updated;
      });
    } on GeminiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Load a cached result from history instantly (no API call).
  void _openHistory(OracleHistoryEntry entry) {
    try {
      final decoded = _decodeMap(entry.rawJson);
      final song = SongChords.fromJson(decoded);
      setState(() {
        _song = song;
        _query = entry.query;
        _ctrl.text = entry.query;
        _error = null;
      });
      FocusScope.of(context).unfocus();
    } catch (_) {
      setState(() => _error = 'Could not open that saved search.');
    }
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final obj = jsonDecode(raw);
    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) return Map<String, dynamic>.from(obj);
    throw const FormatException('not an object');
  }

  Future<void> _removeHistory(int index) async {
    final updated = await _historyStore.removeAt(index);
    if (mounted) setState(() => _history = updated);
  }

  Future<void> _clearHistory() async {
    await _historyStore.clear();
    if (mounted) setState(() => _history = []);
  }

  void _newSearch() {
    setState(() {
      _song = null;
      _error = null;
      _query = '';
      _ctrl.clear();
    });
  }

  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your API key first.');
      return;
    }
    setState(() {
      _savingKey = true;
      _error = null;
    });
    await _service.setApiKey(key);
    if (!mounted) return;
    setState(() {
      _savingKey = false;
      _hasKey = true;
      _keyCtrl.clear();
    });
  }

  void _openKeySheet() {
    _keyCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: _buildKeySheetBody(ctx),
      ),
    );
  }

  Widget _buildKeySheetBody(BuildContext ctx) {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.vpn_key, size: 18, color: AppColors.accent),
                SizedBox(width: 8),
                Text('Oracle API Key',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'How to get your free key:\n'
              '1. Go to aistudio.google.com\n'
              '2. Sign in with Google\n'
              '3. Click "Get API key" → "Create API key"\n'
              '4. Copy it and paste below',
              style: TextStyle(
                  fontSize: 12, height: 1.6, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: TextField(
                controller: _keyCtrl,
                obscureText: true,
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                decoration: const InputDecoration(
                  hintText: 'Paste your API key here',
                  hintStyle: TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _savingKey
                    ? null
                    : () async {
                        await _saveKey();
                        if (!ctx.mounted) return;
                        setSheetState(() {});
                        if (_hasKey && mounted) {
                          Navigator.pop(ctx);
                          if (_ctrl.text.trim().isNotEmpty) {
                            _search(_ctrl.text);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _savingKey
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onAccent))
                    : const Text('Save Key',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.displayNameFallback('Guitarist');

    return SafeArea(
      child: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_song == null) ...[
                    _introCard(name),
                    const SizedBox(height: 14),
                    _suggestionChips(),
                    const SizedBox(height: 14),
                  ],
                  if (!_hasKey) ...[
                    _setupCard(),
                    const SizedBox(height: 14),
                  ],
                  if (_loading) ...[
                    _loadingCard(),
                    const SizedBox(height: 14),
                  ],
                  if (_error != null) ...[
                    _errorCard(),
                    const SizedBox(height: 14),
                  ],
                  if (_song != null) ...[
                    _resultHeader(),
                    const SizedBox(height: 10),
                    _resultCard(_song!),
                    const SizedBox(height: 14),
                  ],
                  if (_song == null && !_loading && _error == null && _hasKey && _history.isEmpty)
                    _idleCard(),
                  if (_history.isNotEmpty && !_loading) _recentSection(),
                ],
              ),
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
          const Text('Song Oracle',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
          const Spacer(),
          if (_song != null)
            IconButton(
              tooltip: 'New search',
              onPressed: _newSearch,
              icon: const Icon(Icons.add, size: 20, color: AppColors.onSurfaceVariant),
            ),
          IconButton(
            tooltip: 'Oracle API key',
            onPressed: _openKeySheet,
            icon: Icon(
              _hasKey ? Icons.vpn_key : Icons.vpn_key_off,
              size: 18,
              color: _hasKey ? AppColors.accent : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _introCard(String name) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_fix_high, size: 18, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hey $name! Type any song and I\'ll pull up its chords with the '
                  'lyrics. Chords sit right above the words they belong to.',
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _suggestions.map((s) {
        return GestureDetector(
          onTap: () {
            _ctrl.text = s;
            _search(s);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child:
                Text(s, style: const TextStyle(fontSize: 11, color: AppColors.onSurface)),
          ),
        );
      }).toList(),
    );
  }

  Widget _setupCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.key, size: 16, color: AppColors.error),
              SizedBox(width: 8),
              Text('Add your Oracle API key',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Oracle needs your free key to work. It\'s stored only on your device.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _openKeySheet,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add API Key',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _idleCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.music_note, size: 32, color: AppColors.onSurfaceVariant),
            SizedBox(height: 10),
            Text('Search for a song to see its chords',
                style:
                    TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Column(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.accent),
            ),
            SizedBox(height: 14),
            Text('Oracle is working out...',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface)),
            SizedBox(height: 4),
            Text('Finding the chords for you',
                style:
                    TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: AppColors.onSurface)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close, size: 16, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _resultHeader() {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 14, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(
          _query.isEmpty ? 'RESULT' : '“$_query”',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _resultCard(SongChords song) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface)),
                    if (song.artist.isNotEmpty)
                      Text(song.artist,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Key: ${song.key}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (song.capo > 0) _metaChip(Icons.album, 'Capo ${song.capo}'),
              if (song.tempo > 0) _metaChip(Icons.speed, '${song.tempo} BPM'),
              _metaChip(Icons.tune, song.tuning),
              _metaChip(Icons.bar_chart, song.difficulty),
            ],
          ),
          if (song.strumming.isNotEmpty) ...[
            const SizedBox(height: 10),
            _metaChip(Icons.swap_vert, 'Strum: ${song.strumming}'),
          ],
          if (song.chordsUsed.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('CHORDS USED',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: song.chordsUsed.map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(c,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: AppColors.outlineVariant, height: 1),
          const SizedBox(height: 8),
          ChordSheet(sections: song.sections),
          const SizedBox(height: 8),
          const Center(
            child: Text('Generated by Oracle • Chords in mint, lyrics below',
                style: TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.onSurface)),
        ],
      ),
    );
  }

  Widget _recentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RECENT SEARCHES',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant)),
            GestureDetector(
              onTap: _clearHistory,
              child: const Text('Clear',
                  style: TextStyle(fontSize: 11, color: AppColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _history.length; i++) _historyRow(i),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _historyRow(int index) {
    final e = _history[index];
    final isLast = index == _history.length - 1;
    return Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3))),
            ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _openHistory(e),
            icon: const Icon(Icons.history, size: 16, color: AppColors.onSurfaceVariant),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openHistory(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.onSurface)),
                    Text(_formatTime(e.time),
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _removeHistory(index),
            icon: const Icon(Icons.close, size: 15, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.search, size: 20, color: AppColors.onSurfaceVariant),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: !_loading,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                decoration: const InputDecoration(
                  hintText: 'Song name — Artist',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                  border: InputBorder.none,
                ),
              ),
            ),
            GestureDetector(
              onTap: _loading ? null : () => _search(_ctrl.text),
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.accent),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onAccent))
                    : const Icon(Icons.auto_awesome,
                        size: 16, color: AppColors.onAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
