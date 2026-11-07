import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'riff_recorder_base.dart';

/// Persists captured riffs so they survive a reload.
///
/// Riffs are stored as base64 `data:` URLs in SharedPreferences — the same
/// device-local mechanism as [FavoritesStore] / [OracleHistory]. A data URL
/// (unlike a page-scoped object URL) keeps working after a restart, so the
/// list can be rehydrated and played back.
class RiffStore {
  RiffStore._();
  static final RiffStore instance = RiffStore._();

  static const _key = 'saved_riffs';

  /// Keep the most recent captures only — base64 audio is large, and
  /// SharedPreferences has a finite web quota.
  static const _max = 10;

  Future<List<Riff>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Riff>[];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final url = (m['u'] ?? '').toString();
        if (url.isEmpty) return null;
        final t = int.tryParse('${m['t']}') ?? 0;
        return Riff(url: url, time: DateTime.fromMillisecondsSinceEpoch(t));
      }).whereType<Riff>().toList();
    } catch (_) {
      return <Riff>[];
    }
  }

  /// Persists [riffs] (most recent first), capping at [_max]. On a storage
  /// quota error it drops the oldest half and retries once, then gives up
  /// silently — riffs still play this session, we just stop persisting.
  Future<void> save(List<Riff> riffs) async {
    final kept = riffs.length > _max ? riffs.sublist(0, _max) : riffs;
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(_key, _encode(kept));
    } catch (_) {
      try {
        await prefs.setString(_key, _encode(kept.sublist(kept.length ~/ 2)));
      } catch (_) {}
    }
  }

  String _encode(List<Riff> riffs) => jsonEncode(riffs
      .map((r) => {'u': r.url, 't': r.time.millisecondsSinceEpoch})
      .toList());
}
