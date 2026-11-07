import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved Oracle search: the query typed by the user and the raw chord
/// sheet JSON returned for it, so it can be shown again offline.
class OracleHistoryEntry {
  const OracleHistoryEntry({
    required this.query,
    required this.rawJson,
    required this.timeMs,
  });

  final String query;
  final String rawJson;
  final int timeMs;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timeMs);

  Map<String, dynamic> toJson() =>
      {'q': query, 'r': rawJson, 't': timeMs};

  factory OracleHistoryEntry.fromJson(Map<String, dynamic> j) =>
      OracleHistoryEntry(
        query: (j['q'] ?? '').toString(),
        rawJson: (j['r'] ?? '{}').toString(),
        timeMs: int.tryParse('${j['t']}') ?? 0,
      );
}

/// Persists Oracle search history on-device (SharedPreferences) so past
/// searches and their chord sheets are still there when the app reopens.
class OracleHistory {
  OracleHistory._();
  static final OracleHistory instance = OracleHistory._();

  static const _key = 'oracle_history';
  static const _max = 20;

  /// Called after every local mutation so [CloudSync] can mirror the change
  /// to Firestore (set by the sync layer; null = local-only, e.g. in tests).
  static void Function(List<OracleHistoryEntry> entries)? onSaved;

  Future<List<OracleHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) =>
              OracleHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Prepends a new entry (most recent first), dropping any older duplicate
  /// of the same query and capping the list at [_max].
  Future<List<OracleHistoryEntry>> add(String query, String rawJson) async {
    final entries = await load();
    entries.removeWhere(
        (e) => e.query.trim().toLowerCase() == query.trim().toLowerCase());
    entries.insert(
      0,
      OracleHistoryEntry(
        query: query.trim(),
        rawJson: rawJson,
        timeMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (entries.length > _max) {
      entries.removeRange(_max, entries.length);
    }
    await _save(entries);
    return entries;
  }

  Future<List<OracleHistoryEntry>> removeAt(int index) async {
    final entries = await load();
    if (index >= 0 && index < entries.length) {
      entries.removeAt(index);
      await _save(entries);
    }
    return entries;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    onSaved?.call(const <OracleHistoryEntry>[]);
  }

  /// Replaces the whole history (used by [CloudSync] to fold in the server
  /// copy); re-applies the [_max] cap before saving.
  Future<void> replaceAll(List<OracleHistoryEntry> entries) async {
    final capped = entries.length > _max
        ? entries.sublist(0, _max)
        : <OracleHistoryEntry>[...entries];
    await _save(capped);
  }

  Future<void> _save(List<OracleHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(entries.map((e) => e.toJson()).toList()));
    onSaved?.call(entries);
  }
}
