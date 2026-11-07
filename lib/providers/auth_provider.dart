import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync.dart';

class AuthProvider extends ChangeNotifier {
  static const _guestKey = 'is_guest';

  final AuthService _service;
  User? _user;
  bool _busy = false;
  String? _error;
  bool _guest = false;
  bool _ready = false;

  AuthProvider([AuthService? service]) : _service = service ?? AuthService() {
    _user = _service.currentUser;
    // Wire favorites/history cloud-sync callbacks (no-ops while a guest).
    CloudSync.instance.init();
    _service.authStateChanges.listen((user) {
      _user = user;
      // A real sign-in upgrades (and clears) any lingering guest session.
      if (user != null && _guest) {
        _guest = false;
        _persistGuest(false);
      }
      if (user != null) {
        // Fold local + cloud together (also migrates a guest's local data in).
        CloudSync.instance.syncNow().ignore();
      } else {
        CloudSync.instance.reset();
      }
      notifyListeners();
    });
    _bootstrap();
  }

  /// Loads the persisted guest flag once at startup so a returning guest goes
  /// straight in. [_ready] flips true when this resolves (AuthGate waits on it
  /// to avoid a login-screen flash).
  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _guest = (prefs.getBool(_guestKey) ?? false) && _user == null;
    } catch (_) {
      _guest = false;
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  User? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isGuest => _guest;
  bool get isReady => _ready;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get email => _user?.email;

  /// Human-readable sign-in provider for display (Google / Apple / Email / ...).
  String get providerLabel {
    final providers = _user?.providerData ?? const [];
    for (final p in providers) {
      switch (p.providerId) {
        case 'google.com':
          return 'Google';
        case 'apple.com':
          return 'Apple';
        case 'password':
          return 'Email';
        case 'github.com':
          return 'GitHub';
        case 'facebook.com':
          return 'Facebook';
        case 'twitter.com':
        case 'x.com':
          return 'X';
      }
    }
    return 'Email';
  }

  /// Enters guest mode: a persistent local session with no account. The flag
  /// is stored so the next launch skips the login screen entirely.
  Future<void> continueAsGuest() async {
    _guest = true;
    notifyListeners(); // AuthGate rebuilds to the app immediately.
    await _persistGuest(true);
  }

  Future<void> _persistGuest(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_guestKey, true);
      } else {
        await prefs.remove(_guestKey);
      }
    } catch (_) {
      // Best-effort persistence; never block navigation on storage errors.
    }
  }

  String displayNameFallback(String fallback) {
    if (_guest && (_user == null)) return 'Guest';
    final n = _user?.displayName;
    if (n != null && n.trim().isNotEmpty) return n;
    final e = _user?.email;
    if (e != null && e.contains('@')) return e.split('@').first;
    return fallback;
  }

  Future<bool> signUp(String email, String password, {Map<String, dynamic>? data}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final name = data?['display_name'];
      await _service.signUpWithPassword(
        email: email,
        password: password,
        displayName: name is String ? name : null,
      );
      _user = _service.currentUser;
      return true;
    } on AuthFailure catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithPassword(email: email, password: password);
      _user = _service.currentUser;
      return true;
    } on AuthFailure catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() => _socialSignIn(_service.signInWithGoogle);

  Future<bool> signInWithApple() => _socialSignIn(_service.signInWithApple);

  /// Shared handler for social sign-in. A cancel (null credential) is not an
  /// error, so [_error] is only set on real failures.
  Future<bool> _socialSignIn(Future<UserCredential?> Function() run) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final cred = await run();
      if (cred == null) return false; // user canceled — stay quiet
      _user = _service.currentUser;
      return true;
    } on AuthFailure catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.resetPassword(email);
      return true;
    } on AuthFailure catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Signs out a real user and/or exits guest mode. After this the app
  /// returns to the login screen via AuthGate.
  Future<void> signOut() async {
    if (_user != null) {
      try {
        await _service.signOut();
      } catch (_) {}
      _user = null;
      CloudSync.instance.reset();
    }
    if (_guest) {
      _guest = false;
      await _persistGuest(false);
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
