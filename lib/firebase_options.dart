import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static bool get isConfigured => true;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'run `flutterfire configure` to add the iOS app.',
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are Web-only. '
          'Run `flutterfire configure` to add more platforms.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_WEB_API_KEY',
    authDomain: 'rigmusic-a203e.firebaseapp.com',
    projectId: 'rigmusic-a203e',
    storageBucket: 'rigmusic-a203e.firebasestorage.app',
    messagingSenderId: '721731463659',
    appId: '1:721731463659:web:ed7e8f1a0208919cb811ae',
    measurementId: 'G-6LC2WK9R1L',
  );

  // Registered in the Firebase console as package `lk.rigmusic.app`
  // (App ID 1:721731463659:android:d6dea0b50be70b1ab811ae).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_ANDROID_API_KEY',
    appId: '1:721731463659:android:d6dea0b50be70b1ab811ae',
    messagingSenderId: '721731463659',
    projectId: 'rigmusic-a203e',
    storageBucket: 'rigmusic-a203e.firebasestorage.app',
  );
}
