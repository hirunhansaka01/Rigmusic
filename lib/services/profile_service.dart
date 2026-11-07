import 'package:cloud_firestore/cloud_firestore.dart';

/// Loads and saves the editable fields of a user's `profiles/{uid}` doc.
///
/// The profile picture is stored in Firestore as a base64 `data:` URL string
/// under the `photo` field (there is no Firebase Storage dependency, and the
/// spec calls for Firestore to hold the profile picture). Images are downsized
/// by the picker before encoding so the document stays well under Firestore's
/// 1 MB per-document limit.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Returns the editable profile fields for [uid], or `{}` if none exist.
  Future<Map<String, dynamic>> loadProfile(String uid) async {
    final doc = await _db.collection('profiles').doc(uid).get();
    return doc.data() ?? <String, dynamic>{};
  }

  /// Merges [fields] into `profiles/{uid}` so existing stats (xp, streak, …)
  /// are never wiped. Adds/refreshes `updated_at`.
  Future<void> saveProfile(String uid, Map<String, dynamic> fields) async {
    await _db.collection('profiles').doc(uid).set(
      <String, dynamic>{...fields, 'updated_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Local date key (yyyy-MM-dd) used to detect day rollovers for streaks.
  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Adds [minutes] of practice to the user's stats, handling the daily
  /// rollover and streak in a single transaction:
  ///
  /// * first ever practice → streak becomes 1
  /// * last practice was yesterday → streak += 1
  /// * gap of 2+ days → streak resets to 1
  /// * same day → streak unchanged, minutes accumulate
  ///
  /// Also keeps `daily_practice_min` (today), `total_practice_min` (lifetime),
  /// `daily_goal_min`, and `last_practice_date` in sync.
  Future<void> logPractice(String uid, int minutes) async {
    if (minutes <= 0) return;
    final ref = _db.collection('profiles').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};

      final today = dateKey(DateTime.now());
      final last = data['last_practice_date'];
      final lastStr = last is String ? last : '';

      int daily = data['daily_practice_min'] is int
          ? data['daily_practice_min'] as int
          : 0;
      int streak = data['streak_days'] is int ? data['streak_days'] as int : 0;
      int total = data['total_practice_min'] is int
          ? data['total_practice_min'] as int
          : 0;
      final goal =
          data['daily_goal_min'] is int ? data['daily_goal_min'] as int : 30;

      if (lastStr != today) {
        // New day: reset today's counter and update the streak.
        daily = 0;
        final lastDate = DateTime.tryParse(lastStr);
        if (lastDate == null) {
          streak = 1; // first ever practice
        } else {
          final gap = DateTime.now()
              .difference(
                  DateTime(lastDate.year, lastDate.month, lastDate.day))
              .inDays;
          streak = gap == 1 ? streak + 1 : 1;
        }
      }

      tx.update(ref, {
        'last_practice_date': today,
        'daily_practice_min': daily + minutes,
        'total_practice_min': total + minutes,
        'streak_days': streak,
        'daily_goal_min': goal,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }
}
