import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favorites_store.dart';
import 'oracle_history.dart';

/// Two-way sync of favorites + Oracle history to Firestore for signed-in
/// users, so they follow you across devices. Guests have no account to sync
/// to, so their data stays device-local — but it is folded into the account
/// automatically the first time they sign in (see [syncNow]).
///
/// The local stores remain the source of truth for reads (fast + offline).
/// This service mirrors them to the cloud:
///
///  * [syncNow] runs at app start / sign-in. It reads the cloud copy FIRST,
///    merges it with local (union for favorites, recency-merge for history),
///    stores the merged result locally, then pushes it back. Capturing the
///    server copy before any push guarantees pre-merge local-only data never
///    overwrites it.
///  * Once synced, local mutations push the full current set directly. If a
///    change happens before the first successful sync (offline, say), the push
///    instead triggers [syncNow], which folds that change in via the merge.
///
/// Everything is best-effort and silent: offline, permission, quota, or
/// not-initialized errors are swallowed — sync must never surface a popup or
/// block the UI (and must stay inert in unit tests, where Firebase isn't
/// wired up).
class CloudSync {
  CloudSync._() {
    // Mirror local changes to the cloud as they happen. The stores stay
    // cloud-agnostic (they only fire this callback), so there's no import cycle.
    FavoritesStore.onSaved = pushFavorites;
    OracleHistory.onSaved = pushHistory;
  }

  static final CloudSync instance = CloudSync._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// True once the cloud copy has been captured & merged for this account.
  /// Until then, local mutations do NOT blind-write — they wait for (or run)
  /// a sync, so local-only data can never clobber the server copy.
  bool _synced = false;
  String? _syncedUid;

  /// Re-entrancy guard: a store's `onSaved` fires from inside [syncNow]'s
  /// merge step, which must not kick off another sync.
  bool _syncing = false;

  /// Current uid, or null when signed out / Firebase isn't initialized
  /// (unit tests). Never throws.
  String? get _uidOrNull {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Registers the store callbacks and, if a user is already signed in, kicks
  /// off the initial sync. Safe to call at startup for everyone (guests no-op).
  void init() {
    if (_uidOrNull != null) {
      syncNow().ignore();
    }
  }

  /// Clears the synced state on sign-out so the next account starts fresh.
  void reset() {
    _synced = false;
    _syncedUid = null;
  }

  /// Shared key with PROFILE ▸ Offline Mode: while it is on, no cloud
  /// traffic leaves the device (favorites/history stay device-local).
  static const _offlineKey = 'pref_offline';

  Future<bool> _offlineMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_offlineKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Captures the server copy, merges it with local, stores the result
  /// locally, then pushes it back. Idempotent and silent.
  Future<void> syncNow() async {
    if (await _offlineMode()) return; // Offline Mode — keep everything local
    final uid = _uidOrNull;
    if (uid == null || _syncing) return;
    if (_synced && _syncedUid == uid) return; // already captured this session
    _syncing = true;
    try {
      // 1. Read the server copy BEFORE any push. A read failure (offline,
      //    permissions) throws and aborts — we must not treat it as "empty"
      //    or we'd later push local-only data over the real server copy.
      final cloudFav = await _readFavorites(uid);
      final cloudHist = await _readHistory(uid);

      // 2. Fold server + local together and store locally. Pushes stay blocked
      //    here (_synced is still false), so nothing writes mid-merge.
      final mergedFav = {...await FavoritesStore.instance.load(), ...cloudFav};
      await FavoritesStore.instance.replaceAll(mergedFav);
      final mergedHist =
          _mergeHistory(await OracleHistory.instance.load(), cloudHist);
      await OracleHistory.instance.replaceAll(mergedHist);

      // 3. Server copy is captured — open the gates, then push the result.
      _synced = true;
      _syncedUid = uid;
      try {
        await _writeFavorites(uid, mergedFav);
      } catch (_) {}
      try {
        await _writeHistory(uid, mergedHist);
      } catch (_) {}
    } catch (_) {
      // Stay unsynced so we retry on the next opportunity and never clobber
      // the server with pre-merge local data.
      _synced = false;
      _syncedUid = null;
    } finally {
      _syncing = false;
    }
  }

  /// Called on every local favorites change (wired in the constructor).
  Future<void> pushFavorites(Set<String> names) async {
    try {
      if (await _offlineMode()) return; // Offline Mode — device-local only
      final uid = _uidOrNull;
      if (uid == null) return; // signed out / tests — local-only
      if (!_synced || _syncedUid != uid) {
        await syncNow(); // folds this change in via the merge
        return;
      }
      await _writeFavorites(uid, names);
    } catch (_) {
      // Silent: sync is best-effort.
    }
  }

  /// Called on every local history change (wired in the constructor).
  Future<void> pushHistory(List<OracleHistoryEntry> entries) async {
    try {
      if (await _offlineMode()) return; // Offline Mode — device-local only
      final uid = _uidOrNull;
      if (uid == null) return;
      if (!_synced || _syncedUid != uid) {
        await syncNow();
        return;
      }
      await _writeHistory(uid, entries);
    } catch (_) {
      // Silent.
    }
  }

  // ── Firestore paths (owner-only, allowed by users/{uid}/{document=**}) ──

  Future<Set<String>> _readFavorites(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('sync')
        .doc('favorites')
        .get();
    if (!doc.exists) return <String>{};
    final names = (doc.data()?['names'] as List?) ?? const [];
    return names.map((e) => e.toString()).toSet();
  }

  Future<List<OracleHistoryEntry>> _readHistory(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('sync')
        .doc('history')
        .get();
    if (!doc.exists) return const <OracleHistoryEntry>[];
    final entries = (doc.data()?['entries'] as List?) ?? const [];
    return entries
        .whereType<Map>()
        .map((e) => OracleHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _writeFavorites(String uid, Set<String> names) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('sync')
        .doc('favorites')
        .set(<String, dynamic>{
      'names': names.toList(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _writeHistory(
      String uid, List<OracleHistoryEntry> entries) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('sync')
        .doc('history')
        .set(<String, dynamic>{
      'entries': entries.map((e) => e.toJson()).toList(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Union by trimmed-lowercase query (keeping whichever side is newer),
  /// most recent first. [OracleHistory.replaceAll] re-applies the count cap.
  List<OracleHistoryEntry> _mergeHistory(
      List<OracleHistoryEntry> local, List<OracleHistoryEntry> cloud) {
    final byQuery = <String, OracleHistoryEntry>{};
    for (final e in <OracleHistoryEntry>[...local, ...cloud]) {
      final key = e.query.trim().toLowerCase();
      if (key.isEmpty) continue;
      final existing = byQuery[key];
      if (existing == null || e.timeMs > existing.timeMs) {
        byQuery[key] = e;
      }
    }
    final merged = byQuery.values.toList()
      ..sort((a, b) => b.timeMs.compareTo(a.timeMs));
    return merged;
  }
}
