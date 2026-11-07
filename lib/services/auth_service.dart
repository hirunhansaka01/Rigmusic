import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);

  @override
  String toString() => message;
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _msg(Object e) {
    if (e is AuthFailure) return e.message;
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Wrong email or password.';
        case 'email-already-in-use':
          return 'Account already exists. Try logging in.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        case 'network-request-failed':
          return 'No connection. Check internet and retry.';
        case 'operation-not-allowed':
          return 'Email sign-in is disabled in your Firebase project.';
        default:
          final m = e.message;
          return (m == null || m.isEmpty) ? 'Auth failed. Try again.' : m;
      }
    }
    return 'Auth failed. Try again.';
  }

  Future<UserCredential> signUpWithPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = cred.user;
      if (user != null) {
        if (displayName != null && displayName.trim().isNotEmpty) {
          await user.updateDisplayName(displayName.trim());
        }
        await _createProfileDocs(
          uid: user.uid,
          email: email.trim().toLowerCase(),
          displayName: displayName?.trim(),
        );
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e));
    } catch (e) {
      throw AuthFailure(_msg(e));
    }
  }

  Future<UserCredential> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e));
    } catch (e) {
      throw AuthFailure(_msg(e));
    }
  }

  /// True when the code means the user backed out (not a real failure).
  static bool _isCancelCode(String code) {
    return code == 'popup-closed-by-user' ||
        code == 'cancelled-popup-request' ||
        code == 'user-cancelled' ||
        code == 'web-context-canceled';
  }

  /// Friendly message for the codes social sign-in tends to throw.
  String _socialMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'This email is already linked to a different sign-in method.';
      case 'unauthorized-domain':
        return 'This website domain isn’t authorized for sign-in. '
            'Add it under Authentication → Settings in the Firebase console.';
      case 'operation-not-allowed':
        return 'This sign-in method is disabled. Enable it in the Firebase console.';
      case 'invalid-credential':
      case 'invalid-authorization-code':
        return 'Sign-in failed. Please try again.';
      case 'network-request-failed':
        return 'No connection. Check internet and retry.';
      default:
        return _msg(e);
    }
  }

  /// Signs in with Google. Returns null when the user cancels.
  ///
  /// On web this uses Firebase's own `signInWithPopup`, which needs no client
  /// ID in code — just the Google provider enabled in the Firebase console.
  /// On other platforms it falls back to the [google_sign_in] plugin.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        final cred = await _auth.signInWithPopup(provider);
        await _ensureProfileDocs(cred.user);
        return cred;
      }
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // user dismissed the flow
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      await _ensureProfileDocs(cred.user);
      return cred;
    } on FirebaseAuthException catch (e) {
      if (_isCancelCode(e.code)) return null;
      throw AuthFailure(_socialMsg(e));
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(_msg(e));
    }
  }

  /// Signs in with Apple. Returns null when the user cancels.
  ///
  /// On web this uses Firebase's `signInWithPopup` (Apple provider enabled in
  /// the Firebase console). On iOS it uses the [sign_in_with_apple] plugin and
  /// persists the first-run name Apple only returns once.
  Future<UserCredential?> signInWithApple() async {
    try {
      if (kIsWeb) {
        final provider = OAuthProvider('apple.com');
        final cred = await _auth.signInWithPopup(provider);
        await _ensureProfileDocs(cred.user);
        return cred;
      }
      final appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauth = OAuthProvider('apple.com').credential(
        idToken: appleCred.identityToken,
        accessToken: appleCred.authorizationCode,
      );
      final cred = await _auth.signInWithCredential(oauth);
      // Apple only hands back the name on the very first authorization.
      final given = appleCred.givenName;
      if (given != null && given.trim().isNotEmpty) {
        final full = [appleCred.givenName, appleCred.familyName]
            .where((p) => p != null && p.trim().isNotEmpty)
            .join(' ')
            .trim();
        if (full.isNotEmpty) await cred.user?.updateDisplayName(full);
        await _ensureProfileDocs(cred.user, displayName: full);
      } else {
        await _ensureProfileDocs(cred.user);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      if (_isCancelCode(e.code)) return null;
      throw AuthFailure(_socialMsg(e));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthFailure(_appleAuthMsg(e));
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(_msg(e));
    }
  }

  String _appleAuthMsg(SignInWithAppleAuthorizationException e) {
    switch (e.code) {
      case AuthorizationErrorCode.invalidResponse:
      case AuthorizationErrorCode.failed:
        return 'Apple sign-in failed. Please try again.';
      case AuthorizationErrorCode.notHandled:
        return 'Apple sign-in isn’t available on this device.';
      case AuthorizationErrorCode.canceled:
        return 'Sign-in canceled.';
      case AuthorizationErrorCode.unknown:
      default:
        return 'Apple sign-in failed. Please try again.';
    }
  }

  /// Creates the profile + settings docs for a social user on first sign-in,
  /// leaving any existing data untouched. Never blocks the login.
  Future<void> _ensureProfileDocs(User? user, {String? displayName}) async {
    if (user == null) return;
    try {
      final ref = _db.collection('profiles').doc(user.uid);
      final snap = await ref.get();
      if (snap.exists) return;
      final email = user.email ?? '';
      final name = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : (email.isNotEmpty ? email.split('@').first : 'Guitarist'));
      await ref.set({
        'display_name': name,
        'email': email,
        'level': 1,
        'xp': 0,
        'streak_days': 0,
        'total_practice_min': 0,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      await _db.collection('user_settings').doc(user.uid).set({
        'a4_freq': 440,
        'strobe_sensitivity': 'high',
        'metronome': {'bpm': 120, 'sound': 'celestial'},
        'ai_oracle': true,
        'haptic': true,
        'offline_mode': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Profile docs sync lazily later; never block sign-in on this.
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e));
    } catch (e) {
      throw AuthFailure(_msg(e));
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e));
    } catch (e) {
      throw AuthFailure(_msg(e));
    }
  }

  /// Creates the Firestore profile + settings docs for a new user.
  /// Firestore failures must not fail the signup itself.
  Future<void> _createProfileDocs({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    try {
      final name = (displayName == null || displayName.isEmpty)
          ? email.split('@').first
          : displayName;
      await _db.collection('profiles').doc(uid).set({
        'display_name': name,
        'email': email,
        'level': 1,
        'xp': 0,
        'streak_days': 0,
        'total_practice_min': 0,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      await _db.collection('user_settings').doc(uid).set({
        'a4_freq': 440,
        'strobe_sensitivity': 'high',
        'metronome': {'bpm': 120, 'sound': 'celestial'},
        'ai_oracle': true,
        'haptic': true,
        'offline_mode': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Profile docs sync lazily later; never block signup on this.
    }
  }
}
