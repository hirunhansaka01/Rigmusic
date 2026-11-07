import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/chord_library.dart';
import '../providers/auth_provider.dart';
import '../services/favorites_store.dart';
import '../services/oracle_history.dart';
import '../services/profile_service.dart';
import '../services/reference_tone.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_message.dart';
import '../widgets/fretboard.dart';
import '../widgets/practice_session_sheet.dart';
import 'riff_recorder_screen.dart';
import 'tempo_screen.dart';

/// HOME tab. Live dashboard: stats, daily practice session, essentials,
/// chord of the day, and songs pulled from your real Oracle history.
///
/// Everything here is real: stats/session stream from `profiles/{uid}`,
/// songs come from the persisted Oracle history, and the chord of the day
/// rotates daily and plays its actual voicing.
class HomeScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<OracleHistoryEntry> _history = <OracleHistoryEntry>[];
  Set<String> _favs = <String>{};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Reloads persisted history + saved chords. Called on init and whenever
  /// the user returns to this tab, so newly searched songs show up.
  Future<void> refresh() async {
    final history = await OracleHistory.instance.load();
    final favs = await FavoritesStore.instance.load();
    if (!mounted) return;
    setState(() {
      _history = history;
      _favs = favs;
    });
  }

  String _daypart() {
    final h = DateTime.now().hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  // ---- profile stat helpers (all read the live Firestore doc) ------------

  int _goal(Map<String, dynamic> p) =>
      p['daily_goal_min'] is int ? p['daily_goal_min'] as int : 30;

  int _streak(Map<String, dynamic> p) =>
      p['streak_days'] is int ? p['streak_days'] as int : 0;

  /// Today's practice minutes (0 if the stored value is from a past day).
  int _dailyToday(Map<String, dynamic> p) {
    final today = ProfileService.dateKey(DateTime.now());
    final last = p['last_practice_date'];
    if (last is String && last == today && p['daily_practice_min'] is int) {
      return p['daily_practice_min'] as int;
    }
    return 0;
  }

  String _tuning(Map<String, dynamic> p) {
    final t = p['default_tuning'];
    return (t is String && t.trim().isNotEmpty) ? t.trim() : 'Standard';
  }

  // ---- chord of the day (deterministic daily rotation) -------------------

  ChordDef get _chordOfDay {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return kAllChords[dayOfYear % kAllChords.length];
  }

  // ---- actions ------------------------------------------------------------

  void _goTab(int index) => widget.onNavigate?.call(index);

  Future<void> _startSession() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      showAuthMessage(context, 'Sign in to track practice.', error: true);
      return;
    }
    await PracticeSessionSheet.show(
      context,
      title: 'Daily Practice',
      onStop: (minutes) async {
        if (minutes <= 0) return;
        try {
          await ProfileService.instance.logPractice(uid, minutes);
        } catch (_) {
          if (mounted) {
            showAuthMessage(context, 'Could not save practice time.', error: true);
          }
        }
      },
    );
  }

  Future<void> _playChordPreview() async {
    if (!referenceToneSupported) {
      showAuthMessage(context, 'Audio preview needs a browser for now.', error: false);
      return;
    }
    try {
      await playStrum(_chordOfDay.freqs);
    } catch (_) {
      if (mounted) showAuthMessage(context, 'Audio preview failed.', error: true);
    }
  }

  void _showActivity() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
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
              const Text('ACTIVITY',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (_favs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text('${_favs.length} saved chord${_favs.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 13, color: AppColors.onSurface)),
                    ],
                  ),
                ),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No activity yet. Search a song in SONGS to get started.',
                      style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                )
              else
                ..._history.take(6).map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 15,
                              color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Searched "${e.query}"',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.onSurface)),
                          ),
                          Text(_ago(e.time),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    )),
              const SizedBox(height: 8),
              if (_history.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _goTab(3);
                    },
                    child: const Text('Open Song Finder',
                        style: TextStyle(fontSize: 13, color: AppColors.accent)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  // ---- song history parsing ---------------------------------------------

  (String, String, String) _songInfo(OracleHistoryEntry e) {
    try {
      final decoded = jsonDecode(e.rawJson);
      if (decoded is Map) {
        final title = '${decoded['title'] ?? e.query}';
        final artist = '${decoded['artist'] ?? ''}';
        final key = '${decoded['key'] ?? ''}';
        final tempo = decoded['tempo'];
        final parts = <String>[
          if (key.isNotEmpty) 'Key of $key',
          if (tempo is int && tempo > 0) '$tempo BPM',
        ];
        final meta = parts.isEmpty ? e.query : parts.join(' • ');
        return (title, artist, meta);
      }
    } catch (_) {}
    return (e.query, '', 'Saved search');
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;
    final fallback = auth.displayNameFallback('Minstrel');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid != null
          ? FirebaseFirestore.instance.collection('profiles').doc(uid).snapshots()
          : null,
      builder: (context, snap) {
        final profile = snap.data?.data() ?? <String, dynamic>{};
        final rawName = profile['display_name'];
        final name = (rawName is String && rawName.trim().isNotEmpty)
            ? rawName.trim()
            : fallback;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 20),
                _greeting(name),
                const SizedBox(height: 16),
                _stats(profile),
                const SizedBox(height: 16),
                _dailySession(profile),
                const SizedBox(height: 20),
                _essentials(),
                const SizedBox(height: 20),
                _chordOfDayCard(),
                const SizedBox(height: 20),
                _songs(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: const Icon(Icons.music_note, size: 16, color: AppColors.onSurface),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rig Music',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            Text('ACOUSTIC STUDIO',
                style: TextStyle(
                    fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w500, color: AppColors.accent)),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: _showActivity,
          icon: const Icon(Icons.notifications_none, size: 20, color: AppColors.onSurfaceVariant),
        ),
        GestureDetector(
          onTap: () => _goTab(4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceContainerHigh,
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: const Icon(Icons.person, size: 18, color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _greeting(String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_daypart(),
            style: const TextStyle(
                fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppColors.accent)),
        const SizedBox(height: 4),
        Text(name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
        const SizedBox(height: 4),
        const Text("Ready for today's acoustic practice session.",
            style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  Widget _stats(Map<String, dynamic> profile) {
    final streak = _streak(profile);
    final daily = _dailyToday(profile);
    final goal = _goal(profile);
    final tuning = _tuning(profile);

    return Row(
      children: [
        _statCard('Daily Streak', Text.rich(TextSpan(children: [
          TextSpan(text: '$streak Day${streak == 1 ? '' : 's'} ',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.secondary)),
          const TextSpan(text: '🔥', style: TextStyle(fontSize: 14)),
        ]))),
        const SizedBox(width: 10),
        _statCard('Practice Time',
            Text('$daily / ${goal}m',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface))),
        const SizedBox(width: 10),
        _statCard('Tuning',
            Row(children: [
              const Icon(Icons.circle, size: 8, color: AppColors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(tuning,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.accent)),
              ),
            ])),
      ],
    );
  }

  Widget _statCard(String label, Widget value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 4),
            value,
          ],
        ),
      ),
    );
  }

  Widget _dailySession(Map<String, dynamic> profile) {
    final daily = _dailyToday(profile);
    final goal = _goal(profile);
    final progress = goal <= 0 ? 0.0 : (daily / goal).clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DAILY SESSION',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant)),
              Text('$percent% Complete',
                  style: const TextStyle(fontSize: 12, color: AppColors.accent)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: AppColors.outlineVariant,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                    Text('${daily}m',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(daily > 0 ? 'Keep the streak alive' : 'Start your practice',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    const SizedBox(height: 2),
                    Text('Goal: $goal minutes today • $daily done',
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(daily > 0 ? 'Continue Session' : 'Start Session',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _essentials() {
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ESSENTIALS',
                style: TextStyle(
                    fontSize: 12, letterSpacing: 1.0, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
            Text('Quick Access', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            _toolTile(Icons.graphic_eq, 'Tuner', '440Hz Standard E',
                badge: const Icon(Icons.circle, size: 8, color: AppColors.accent),
                onTap: () => _goTab(1)),
            _toolTile(Icons.speed, 'Metronome', '4/4 Allegro',
                badge: const Text('120 BPM',
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const TempoScreen()))),
            _toolTile(Icons.grid_on, 'Chord Library', 'Voicings & Scales',
                badge: const Text('1.2k+',
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                onTap: () => _goTab(2)),
            _toolTile(Icons.mic, 'Riff Recorder', 'Capture a lick',
                badge: const Text('REC',
                    style: TextStyle(
                        fontSize: 10, letterSpacing: 0.8, color: AppColors.accent)),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const RiffRecorderScreen()))),
          ],
        ),
      ],
    );
  }

  Widget _toolTile(IconData icon, String title, String subtitle,
      {required Widget badge, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.accent),
                ),
                badge,
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chordOfDayCard() {
    final chord = _chordOfDay;
    final fretLabel = chord.startFret > 1 ? 'Fret ${chord.startFret}' : 'Open';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHORD OF THE DAY',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent)),
                    const SizedBox(height: 4),
                    Text(chord.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    Text('${chord.root} • ${chord.group} • ${chord.notes}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Text(fretLabel,
                    style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(chord.startFret > 1 ? '${chord.startFret}th Fret' : 'Open Position',
                        style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                    Text(chord.barreFret >= 0 ? 'BARRE' : chord.group.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Fretboard(
                  frets: chord.frets,
                  fingers: chord.fingers,
                  rootIndex: chord.rootIndex,
                  startFret: chord.startFret,
                  barreFret: chord.barreFret,
                  barreFrom: chord.barreFrom,
                  barreTo: chord.barreTo,
                  height: 130,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Text('Root: ',
                      style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  Text(chord.root,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  const SizedBox(width: 12),
                  Text('Notes: ${chord.notes}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _playChordPreview,
              icon: const Icon(Icons.volume_up, size: 18, color: AppColors.accent),
              label: const Text('Play Chord Preview',
                  style: TextStyle(fontSize: 13, color: AppColors.onSurface)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _songs() {
    final count = _history.length;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RECENT SONGS',
                style: TextStyle(
                    fontSize: 12, letterSpacing: 1.0, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
            GestureDetector(
              onTap: () => _goTab(3),
              child: Text('View All${count > 0 ? ' ($count)' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (count == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                const Icon(Icons.library_music, size: 28, color: AppColors.onSurfaceVariant),
                const SizedBox(height: 8),
                const Text('No songs yet',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                const SizedBox(height: 2),
                const Text('Find chords for any song in the Song Finder.',
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _goTab(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Open Song Finder',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onAccent)),
                  ),
                ),
              ],
            ),
          )
        else
          ..._history.take(2).map((e) {
            final (title, artist, meta) = _songInfo(e);
            final sub = artist.isEmpty ? meta : '$artist • $meta';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _songRow(title, sub),
            );
          }),
      ],
    );
  }

  Widget _songRow(String title, String meta) {
    return GestureDetector(
      onTap: () => _goTab(3),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note, size: 18, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
