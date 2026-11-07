import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's saved/bookmarked chords so they survive restarts.
/// Backed by SharedPreferences (same mechanism as [OracleHistory]).
class FavoritesStore {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  static const _key = 'chord_favorites';

  /// Called after every local mutation so [CloudSync] can mirror the change to
  /// Firestore (set by the sync layer; null = local-only, e.g. in tests).
  static void Function(Set<String> names)? onSaved;

  /// Cached set of saved chord names, loaded once on first use.
  Set<String>? _cache;

  Future<Set<String>> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = <String>{};
      return _cache!;
    }
    try {
      final list = jsonDecode(raw) as List;
      _cache = list.map((e) => e.toString()).toSet();
    } catch (_) {
      _cache = <String>{};
    }
    return _cache!;
  }

  Future<bool> contains(String name) async => (await load()).contains(name);

  /// Adds [name] if missing (returns true when it was newly added).
  Future<bool> add(String name) async {
    final set = await load();
    if (!set.add(name)) return false;
    await _save(set);
    return true;
  }

  /// Removes [name] (returns true when it was present).
  Future<bool> remove(String name) async {
    final set = await load();
    if (!set.remove(name)) return false;
    await _save(set);
    return true;
  }

  /// Flips the saved state of [name]; returns the new saved state.
  Future<bool> toggle(String name) async {
    final set = await load();
    final nowSaved = !set.contains(name);
    if (nowSaved) {
      set.add(name);
    } else {
      set.remove(name);
    }
    await _save(set);
    return nowSaved;
  }

  /// Removes every saved chord (also clears the in-memory cache).
  Future<void> clear() async {
    _cache = <String>{};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    onSaved?.call(<String>{});
  }

  /// Replaces the whole set (used by [CloudSync] to fold in the server copy).
  Future<void> replaceAll(Set<String> names) async {
    _cache = Set<String>.from(names);
    await _save(_cache!);
  }

  Future<void> _save(Set<String> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(set.toList()));
    onSaved?.call(set);
  }
}
