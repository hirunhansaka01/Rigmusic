import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A single chord placement sitting above a word in the lyrics.
class ChordWord {
  const ChordWord({required this.text, this.chord});

  /// The lyric word (or partial word) shown on the bottom row.
  final String text;

  /// The chord shown in colour ABOVE [text], or null when none.
  final String? chord;
}

/// One lyric line = an ordered row of [ChordWord]s.
class ChordLine {
  const ChordLine(this.words);

  final List<ChordWord> words;
}

/// A named block of the song (Verse, Chorus, Bridge...).
class SongSection {
  const SongSection({required this.name, required this.lines});

  final String name;
  final List<ChordLine> lines;
}

/// The full structured result Gemini returned for a song.
class SongChords {
  const SongChords({
    required this.title,
    required this.artist,
    required this.key,
    required this.capo,
    required this.tempo,
    required this.tuning,
    required this.difficulty,
    required this.strumming,
    required this.sections,
    required this.chordsUsed,
  });

  final String title;
  final String artist;
  final String key;
  final int capo;
  final int tempo;
  final String tuning;
  final String difficulty;
  final String strumming;
  final List<String> chordsUsed;
  final List<SongSection> sections;

  factory SongChords.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];

    // Parse ONE line into word-tokens. Accepts the compact inline ChordPro
    // string ("[Am]On a dark [E7]desert...") as well as the older
    // word-object array format, for robustness.
    List<ChordWord> parseLine(dynamic line) {
      if (line is String) return _parseChordPro(line);
      if (line is List) {
        return line.map((w) {
          if (w is Map) {
            return ChordWord(
              text: (w['t'] ?? w['text'] ?? '').toString(),
              chord: (w['c'] ?? w['chord'])?.toString(),
            );
          }
          return ChordWord(text: w.toString());
        }).toList();
      }
      return <ChordWord>[];
    }

    List<ChordLine> parseLines(dynamic raw) {
      if (raw is! List) return <ChordLine>[];
      return raw.map((line) => ChordLine(parseLine(line))).toList();
    }

    final sections = <SongSection>[];
    if (json['sections'] is List) {
      for (final s in json['sections'] as List) {
        if (s is Map) {
          sections.add(SongSection(
            name: (s['name'] ?? 'Section').toString(),
            lines: parseLines(s['lines']),
          ));
        }
      }
    }

    return SongChords(
      title: (json['title'] ?? 'Unknown Song').toString(),
      artist: (json['artist'] ?? '').toString(),
      key: (json['key'] ?? json['k'] ?? 'C').toString(),
      capo: int.tryParse((json['capo'] ?? '0').toString()) ?? 0,
      tempo: int.tryParse((json['tempo'] ?? '0').toString()) ?? 0,
      tuning: (json['tuning'] ?? 'Standard').toString(),
      difficulty: (json['difficulty'] ?? 'Intermediate').toString(),
      strumming: (json['strumming'] ?? '').toString(),
      chordsUsed: stringList(json['chords'] ?? json['chordsUsed']),
      sections: sections,
    );
  }
}

/// The parsed song plus the raw JSON string it came from (for history).
class SongResult {
  const SongResult(this.song, this.rawJson);

  final SongChords song;

  /// The song object as a JSON string — store this to rebuild later.
  final String rawJson;
}

/// Thrown when the Oracle call fails, with a user-friendly message.
class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses one inline ChordPro line into word tokens, e.g.
/// `"[Am]On a dark [E7]desert highway"` →
/// `[(Am, On), (null, a), (null, dark), (E7, desert), (null, highway)]`.
///
/// A `[Chord]` marker attaches that chord to the FIRST word that follows it.
List<ChordWord> _parseChordPro(String raw) {
  final chordRe = RegExp(r'\[([^\]]+)\]');
  final segments = <({String chord, String text})>[];

  var currentChord = '';
  var lastEnd = 0;
  for (final m in chordRe.allMatches(raw)) {
    final textBefore = raw.substring(lastEnd, m.start);
    if (textBefore.isNotEmpty) {
      segments.add((chord: currentChord, text: textBefore));
    }
    currentChord = m.group(1)!.trim();
    lastEnd = m.end;
  }
  final tail = raw.substring(lastEnd);
  if (tail.isNotEmpty) {
    segments.add((chord: currentChord, text: tail));
  }

  // Flatten segments into words; the chord rides on the first word of its
  // own segment only.
  final words = <ChordWord>[];
  for (final seg in segments) {
    final parts = seg.text.split(' ').where((w) => w.isNotEmpty);
    var first = true;
    for (final w in parts) {
      words.add(ChordWord(
        text: w,
        chord: (first && seg.chord.isNotEmpty) ? seg.chord : null,
      ));
      first = false;
    }
  }
  return words;
}

/// Thin wrapper around the Google Gemini API for the AI Song Finder.
///
/// The user pastes their own Gemini API key once; it is stored on-device
/// with SharedPreferences. Nothing else is stored or sent anywhere else.
class GeminiService {
  GeminiService._();
  static final GeminiService instance = GeminiService._();

  static const _keyPref = 'gemini_api_key';
  static const _modelPref = 'gemini_model';

  // ── Baked-in Oracle key ────────────────────────────────────────────────
  // The Song Finder works out of the box with ZERO setup for players: this
  // constant is the key compiled into the shipped binary. It is never
  // rendered anywhere in the UI and never leaves the app except as the
  // `x-goog-api-key` header on direct calls to Google's Gemini API. A user
  // pasting their OWN key from the key sheet always takes precedence.
  //
  // ⚠️ The value is injected at BUILD time via --dart-define, so the public
  // repository never contains the key — see the README. Any value compiled
  // into a client app can, in principle, be extracted from the binary/JS by
  // a determined person; the airtight fix is a tiny backend proxy (e.g. a
  // Cloud Function) that holds the key server-side — see functions/README.md
  // and set [_proxyUrl] to route all Oracle calls through it.
  static const String _bundledKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // ── Backend proxy (recommended — key never leaves the server) ──────────
  // Deploy the Cloud Function in `functions/` (see functions/README.md), then
  // paste its URL here. When set, ALL Oracle calls route through your Cloud
  // Function, which holds the Gemini key in Firebase Secret Manager and adds
  // it server-side. The key is then NEVER shipped in the app, so it cannot be
  // extracted from the APK/JS — the airtight fix for a shipped client.
  //
  // The deployed URL looks like:
  //   https://us-central1-rigmusic-a203e.cloudfunctions.net/geminiProxy
  //
  // Leave EMPTY to call Google directly with a user-pasted key or [_bundledKey]
  // (the old behaviour) — so nothing breaks before you deploy.
  static const String _proxyUrl = '';

  /// Whether requests should go through the backend proxy instead of Google.
  bool get _useProxy => _proxyUrl.trim().isNotEmpty;

  /// Current default model (Gemini 3.8 Flash is the stable Flash model).
  static const _defaultModel = 'gemini-3.8-flash';

  /// Working models tried in order if the chosen one is unavailable/shut
  /// down. Older names like gemini-2.0-flash are deprecated, so we fall
  /// back automatically instead of erroring.
  static const _fallbackModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
  ];

  /// Models offered in the picker (all current, supported ones).
  static const List<String> availableModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
  ];

  /// Instructions that force Gemini into a compact, parseable shape.
  ///
  /// The lines use INLINE ChordPro notation (`[Am]word`) instead of a giant
  /// word-by-word JSON array — that keeps the output small so the request
  /// finishes well inside the API gateway timeout (large JSON was causing
  /// persistent 504 errors).
  ///
  /// IMPORTANT: The Oracle must ONLY return REAL songs that actually exist and
  /// were released by real artists — in BOTH English and Sinhala. It is given
  /// Google Search so it can LOOK UP the real song (artist, real lyrics, real
  /// chord progression) instead of relying on memory, which is what caused it
  /// to hallucinate invented "Sinhala" songs. It must NEVER invent a song,
  /// lyrics, chord progression, or artist. If it cannot find a real, released
  /// song, it returns `{"not_found": true}` instead of making something up.
  static const _systemPrompt = '''
You are an expert guitar chord transcriber for REAL, commercially released songs
by known professional artists. You cover BOTH English and Sinhala songs.

Sinhala artists whose real songs you may transcribe include: Sunil Edirisinghe,
Nanda Malini, Amarasiri Peiris, Sanath Nandasiri, Edward Jayakody, Bathiya and
Santhush (B&SH), Nuwan Sriwardena, Kasun Kalhara, Iraj Weeraratne, Sunil
Perera, and other well-known Sri Lankan artists.
English artists include: The Eagles, Oasis, Ed Sheeran, Queen, Nirvana, Taylor
Swift, John Mayer, and similar established acts.

You have Google Search available. ALWAYS search FIRST to find the exact real
song — its artist and its actual lyrics and chord progression — and base your
output ONLY on that real, released song. Never write from memory alone.

You NEVER invent a song, lyrics, chord progression, or artist. You are NOT a
song generator. If you cannot find a real, professionally released song matching
the request, you return not_found — you never make one up.

Return ONLY valid JSON (no markdown, no commentary, no citation markers inside
the JSON).

If the requested song is a REAL, released song and you found it, return EXACTLY
this shape:
{
  "title": "Song Name",
  "artist": "Artist",
  "key": "Bm",
  "capo": 0,
  "tempo": 74,
  "tuning": "Standard",
  "difficulty": "Beginner|Intermediate|Advanced",
  "strumming": "D - DU - UDU",
  "chords": ["Am", "E7", "G", "D"],
  "sections": [
    { "name": "Verse 1", "lines": [
      "[Am]On a dark desert [E7]highway, cool wind in my hair",
      "[G]Warm smell of colitas, [D]rising up through the air"
    ]},
    { "name": "Chorus", "lines": [
      "[Am]Welcome to the Hotel [E7]California"
    ]}
  ]
}

If the song is NOT a real, released, professionally performed song — for example
it is made up, an internet meme, a person's name, gibberish, or search finds no
real song by that exact title/artist — return EXACTLY and ONLY this, nothing
else:
{"not_found": true}

RULES:
- Search first, then only transcribe the REAL song that actually exists. Do NOT
  invent or generate any song, lyrics, or chords.
- Keep the REAL title, REAL artist, REAL lyrics and REAL chord progression of
  the actual song.
- For Sinhala songs, write the lyrics in the original Sinhala script (or the
  common transliteration when that is what the source uses). Keep chords in
  standard notation (e.g. Am, G, D, C#m).
- Each entry in "lines" is ONE string using inline ChordPro: put [Chord]
  directly BEFORE the lyric word where that chord starts.
- Put a chord ONLY where it changes (do not repeat it every word).
- Split Verse/Chorus/Bridge into their own "sections".
- Do not include citation markers, source URLs, or any text outside the JSON.
- Keep it concise: the real chord sheet only, no extra commentary.
''';

  /// The active API key: the user's own pasted key if one is set, otherwise
  /// the baked-in [_bundledKey]. Returns null only when neither exists (so the
  /// "add your key" prompt still shows if no bundled key was configured).
  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_keyPref)?.trim();
    if (user != null && user.isNotEmpty) return user;
    final bundled = _bundledKey.trim();
    return bundled.isEmpty ? null : bundled;
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPref, key.trim());
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
  }

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelPref) ?? _defaultModel;
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPref, model.trim());
  }

  /// Ask Oracle for the chords of [query] (e.g. 'Hotel California Eagles').
  ///
  /// Tries the user's chosen model first, then automatically falls back
  /// through other current models if that one is unavailable (404), so a
  /// deprecated/shut-down model name never breaks the finder.
  ///
  /// Returns both the parsed [SongChords] and the raw JSON string so the
  /// caller can cache the result in history.
  Future<SongResult> findSong(String query) async {
    // With the backend proxy in use, no on-device key is needed at all — the
    // key lives server-side. Otherwise the user's key (or the bundled one)
    // must be present.
    final apiKey = (await getApiKey()) ?? '';
    if (!_useProxy && apiKey.isEmpty) {
      throw GeminiException(
          'No API key set for Oracle. Tap the key icon to add yours.');
    }

    // Build the ordered list of models to try (chosen first, then fallbacks,
    // without duplicates).
    final chosen = await getModel();
    final toTry = <String>[chosen];
    for (final m in _fallbackModels) {
      if (!toTry.contains(m)) toTry.add(m);
    }

    String? transientSummary;
    for (final model in toTry) {
      // Try this model up to 3 times to ride out 504 / server-busy blips.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final songJson = await _generate(apiKey, model, query);

          // The Oracle refuses to invent songs. If it answered "not_found",
          // the query isn't a real, professionally released song — tell the
          // user clearly instead of building a fake chord sheet.
          if (songJson['not_found'] == true) {
            throw GeminiException(
                'Oracle only knows real songs by professional artists, '
                'and it didn\'t recognize that one. Try the exact song '
                'title — or "Title — Artist".');
          }

          if (model != chosen) {
            await setModel(model);
          }
          return SongResult(
            SongChords.fromJson(songJson),
            jsonEncode(songJson),
          );
        } on _ModelNotFound {
          break; // model gone — move to the next one (no point retrying)
        } on _TransientError catch (e) {
          transientSummary = e.code == 0
              ? 'connection timed out'
              : 'server returned ${e.code}';
          // One quick retry, then move on to the next model (keeps total
          // wait time short in the worst case).
          if (attempt < 1) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          break; // exhausted retries for this model — try the next
        }
      }
    }

    // Every model was unavailable — surface a helpful message.
    if (transientSummary != null) {
      throw GeminiException(
          'Oracle is working out right now ($transientSummary). '
          'Please tap search again in a few seconds.');
    }
    throw GeminiException(
        'Oracle could not reach the AI right now. '
        'Please check your key and try again.');
  }

  /// Runs one model, preferring a Google-Search-grounded call (which keeps the
  /// Oracle anchored to REAL songs) and falling back to a plain call for any
  /// model/key that does not allow the search tool.
  Future<Map<String, dynamic>> _generate(
      String apiKey, String model, String query) async {
    try {
      return await _callModel(apiKey, model, query, grounded: true);
    } on _GroundingUnsupported {
      return await _callModel(apiKey, model, query, grounded: false);
    }
  }

  /// Heuristic: does this 400 body complain about the search/grounding tool
  /// (rather than the API key itself)?
  bool _looksLikeToolError(String body) {
    final b = body.toLowerCase();
    return b.contains('tool') ||
        b.contains('google_search') ||
        b.contains('googlesearch') ||
        b.contains('grounding') ||
        b.contains('function_declarations');
  }

  /// Sends one generateContent request either through the backend proxy (key
  /// held server-side) or straight to Google (bundled / user key).
  ///
  /// Either way the raw Gemini status code + body is returned, so all error
  /// handling and model-fallback logic in [_callModel] behaves identically on
  /// both paths.
  Future<http.Response> _post(
      String apiKey, String model, Map<String, dynamic> payload) {
    if (_useProxy) {
      return http.post(
        Uri.parse(_proxyUrl.trim()),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'payload': payload}),
      );
    }
    return http.post(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: jsonEncode(payload),
    );
  }

  /// Performs one generateContent call and returns the parsed JSON object.
  ///
  /// When [grounded] is true, Google Search grounding is attached so the Oracle
  /// looks the song up instead of trusting memory (this is what stops it
  /// inventing songs). Forcing JSON mime type conflicts with grounding on some
  /// models, so `responseMimeType` is only applied on the ungrounded path.
  Future<Map<String, dynamic>> _callModel(
      String apiKey, String model, String query,
      {bool grounded = true}) async {
    final generationConfig = <String, dynamic>{
      'temperature': 0.2,
      // Bound generation so a request can never run long enough to hit the
      // API gateway timeout (504). A chord sheet is well under this; the
      // cap is generous so a long song never gets cut off mid-JSON.
      'maxOutputTokens': 8192,
    };
    if (!grounded) {
      generationConfig['responseMimeType'] = 'application/json';
    }

    final payload = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Chords and lyrics for: $query'}
          ],
        }
      ],
      'generationConfig': generationConfig,
    };
    if (grounded) {
      payload['tools'] = [
        {'googleSearch': <String, dynamic>{}}
      ];
    }
    final http.Response response;
    try {
      response = await _post(apiKey, model, payload)
          .timeout(const Duration(seconds: 75));
    } catch (e) {
      // Network drop / client-side timeout — worth retrying.
      throw _TransientError(0);
    }

    if (response.statusCode == 400 &&
        grounded &&
        _looksLikeToolError(response.body)) {
      // This model/key refuses the Google Search tool — the caller retries the
      // same model without grounding.
      throw _GroundingUnsupported();
    }
    if (response.statusCode == 400 || response.statusCode == 403) {
      throw GeminiException(_useProxy
          ? 'Oracle rejected that request (the server key may need updating). '
              'Please try again in a moment.'
          : 'Invalid API key. Tap the key icon and paste a valid key.');
    }
    if (response.statusCode == 404) {
      // Model missing — signal the caller to fall back to the next one.
      throw _ModelNotFound('model "$model" not found');
    }
    if (response.statusCode == 429) {
      throw GeminiException(
          'Rate limited by Oracle. Wait a moment and retry.');
    }
    // 5xx / 504 = server busy or gateway timeout — worth retrying.
    if (response.statusCode >= 500) {
      throw _TransientError(response.statusCode);
    }
    if (response.statusCode != 200) {
      throw GeminiException(
          'Oracle error (${response.statusCode}). Try again.');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw GeminiException('Oracle returned an unreadable response.');
    }

    // Pull the text out of the standard Gemini response envelope.
    String? text;
    try {
      final parts = decoded['candidates']?[0]?['content']?['parts'];
      if (parts is List && parts.isNotEmpty) {
        text = parts.map((p) => (p is Map ? p['text']?.toString() ?? '' : ''))
            .join();
      }
    } catch (_) {}

    if (text == null || text.trim().isEmpty) {
      throw GeminiException('Oracle returned no content for that song.');
    }

    // The model sometimes wraps the JSON in ``` fences or adds a sentence
    // before/after it, and a very long song can be cut off mid-JSON. Extract
    // and repair instead of blindly jsonDecode-ing the whole response.
    final parsed = _extractSongJson(text);
    if (parsed == null) {
      throw GeminiException('Could not parse the chord sheet. Try rephrasing.');
    }
    return parsed;
  }

  /// Pull a JSON object out of [text] and decode it, tolerating markdown
  /// fences, surrounding prose, and truncation. Returns null if all attempts
  /// fail.
  Map<String, dynamic>? _extractSongJson(String text) {
    // Strip ``` fences wherever they appear, and drop any grounding citation
    // markers (e.g. «1») so they can never land inside the chord JSON.
    var cleaned = text
        .replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '')
        .replaceAll(RegExp(r'«[^»]*»'), '')
        .trim();

    // Fast path: try the whole thing.
    final direct = _tryDecodeObject(cleaned);
    if (direct != null) return direct;

    // Normal path: grab from the first { to the last } (drops any prose).
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end > start) {
      final candidate = cleaned.substring(start, end + 1);
      final obj = _tryDecodeObject(candidate);
      if (obj != null) return obj;

      // Likely truncated — try closing off the dangling structure.
      final repaired = _repairTruncatedJson(candidate);
      if (repaired != null) return _tryDecodeObject(repaired);
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeObject(String s) {
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return obj;
      if (obj is Map) return Map<String, dynamic>.from(obj);
    } catch (_) {}
    return null;
  }

  /// Best-effort fix for JSON that stopped mid-way: trim the dangling tail,
  /// then close every unclosed `{`/`[`. Good enough to recover most of a
  /// truncated chord sheet.
  String? _repairTruncatedJson(String s) {
    final open = <String>[]; // closing chars to emit
    var inStr = false, esc = false;

    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (inStr) {
        if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        open.add('}');
      } else if (c == '[') {
        open.add(']');
      } else if (c == '}' || c == ']') {
        if (open.isNotEmpty) open.removeLast();
      }
    }
    if (open.isEmpty) return null; // balanced — repair wouldn't help

    // Cut back to the last safe value boundary (closing } ] or ").
    var cut = -1;
    inStr = false;
    esc = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (inStr) {
        if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
        cut = i + 1;
      } else if (c == '}' || c == ']') {
        cut = i + 1;
      }
    }
    if (cut <= 0) return null;

    var partial = s.substring(0, cut);
    // Drop a trailing dangling key/value fragment like  "Capo":  or  ,"Am"
    partial = partial.replaceFirst(RegExp(r',?\s*("[^"]*"\s*:\s*)?$'), '');
    partial = partial.replaceFirst(RegExp(r',\s*$'), '');
    if (partial.trim().isEmpty) return null;

    // Recompute which containers are still open on the trimmed text.
    final open2 = <String>[];
    inStr = false;
    esc = false;
    for (var i = 0; i < partial.length; i++) {
      final c = partial[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (inStr) {
        if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        open2.add('}');
      } else if (c == '[') {
        open2.add(']');
      } else if (c == '}' || c == ']') {
        if (open2.isNotEmpty) open2.removeLast();
      }
    }
    return partial + open2.reversed.join();
  }
}

/// Internal signal that a specific model name is unavailable (404) so the
/// caller can fall back to the next model in the list.
class _ModelNotFound implements Exception {
  _ModelNotFound(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Internal signal that the model/key refused the Google Search grounding tool
/// (HTTP 400) so the caller can retry the same model without grounding.
class _GroundingUnsupported implements Exception {}

/// Internal signal for a retriable failure (5xx / 504 gateway timeout or a
/// dropped connection, where [code] is 0). The caller retries these.
class _TransientError implements Exception {
  _TransientError(this.code);

  /// HTTP status code, or 0 for a network-level timeout/drop.
  final int code;

  @override
  String toString() => 'transient error $code';
}
