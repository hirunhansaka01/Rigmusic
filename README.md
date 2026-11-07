# Rig Music

A guitarist's toolkit with a mystical twist: real-time tuning, a chord library
of real plucked-string audio, an AI song finder, metronome, riff recorder,
favorites and cross-device sync. Flutter, for **web** and **Android**.

## Features

- **Tuner** — live microphone tuning with YIN pitch detection. Presets for
  Standard 6-string, Drop D, DADGAD, Open G, 4- and 5-string bass, 12-string
  and 7-string, with a detection range that reaches 5-string bass low B
  (30.87 Hz) while still rejecting sub-audio noise.
- **Chords** — 324 chords with real audio previews and a fretboard view.
- **Songs (the Oracle)** — an AI song finder that returns only real songs,
  grounded in Google Search, with a persistent history.
- **Profile** — favorites, practice tracking, Firebase-backed sync.
- **Extras** — metronome, riff recorder, reference tones.

## Stack

- Flutter (Material 3), web + Android targets
- Firebase Authentication (email, Google, Apple) + Cloud Firestore
- Gemini with Google Search grounding for the Oracle

## Run it

```powershell
flutter pub get
flutter run -d edge        # web
flutter build apk          # Android → build/app/outputs/flutter-apk/app-release.apk
```

Firebase config lives in `lib/firebase_options.dart` (project
`rigmusic-a203e`). **The API key values are deliberately absent from this
repo** — GitHub secret scanning blocks them and the file here ships with
`YOUR_FIREBASE_*_API_KEY` placeholders. The maintainer's real file is kept
outside git; the local build scripts (`run_apk*.ps1`) copy it in before
building and restore the placeholders afterwards. If you fork the project,
run `flutterfire configure` to generate your own file.

### Android microphone

The tuner's live mic on Android is captured by the app's own Kotlin code
(`android/app/src/main/kotlin/lk/rigmusic/app/MainActivity.kt`, EventChannel
`rigmusic/mic_stream`) using the platform's `AudioRecord` — no third-party
plugin. The mic starts automatically whenever the TUNER tab is opened (and
stops when you switch away); the app requests the `RECORD_AUDIO` permission
at runtime on first use, and the native side reports the device's actual
sample rate so pitch maths stay exact. The web build uses the browser's Web
Audio API instead.

## The Oracle's Gemini API key

This repository is public, so the source ships with **no key** — `_bundledKey`
in `lib/services/gemini_service.dart` reads a build-time define instead:

```dart
static const String _bundledKey =
    String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
```

That means the key can live **inside the APK** while staying **out of
GitHub**. Pick whichever fits you:

1. **Bake the key into a build** (what the distributed APK does) — pass it at
   build time; it is compiled into the binary but never written to the
   source tree:

   ```powershell
   flutter build apk --dart-define=GEMINI_API_KEY=your-key-here
   ```

   Keep the key out of version control (this repo keeps a local copy in the
   git-ignored `.secrets/` folder). Without the flag, the app just falls
   back to option 2.

2. **Each player supplies their own key** — already built in: the app prompts
   for a key on first Oracle use and stores it on-device. Nothing to change.

3. **Key proxy (recommended for shipped builds)** — a Cloud Function holds the
   key in Firebase Secret Manager, so it never ships inside the APK/JS at
   all. See [`functions/README.md`](functions/README.md):

   ```bash
   firebase functions:secrets:set GEMINI_API_KEY
   firebase deploy --only functions
   ```

   then paste the printed URL into `_proxyUrl` in
   `lib/services/gemini_service.dart`.

## Tests

```powershell
flutter test      # pitch detection, chord library, Oracle parsing, stores
dart analyze      # static checks
```
