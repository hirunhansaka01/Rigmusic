import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'riff_recorder_base.dart';

bool get riffRecorderSupported => true;

RiffRecorder createRiffRecorder() => WebRiffRecorder();

/// MediaRecorder's `dataavailable` / `stop` events, bound as Dart streams
/// (package:web doesn't pre-declare them, so we provide them here — they map
/// straight onto the real DOM events of the same names).
const web.EventStreamProvider<web.BlobEvent> _dataAvailable =
    web.EventStreamProvider<web.BlobEvent>('dataavailable');
const web.EventStreamProvider<web.Event> _recorderStop =
    web.EventStreamProvider<web.Event>('stop');

/// Mic capture via `MediaRecorder`, playback via an `<audio>` element.
class WebRiffRecorder implements RiffRecorder {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = <web.Blob>[];
  Completer<web.Blob?>? _stopCompleter;
  /// Container format the browser chose (webm / ogg / mp4). Used for both the
  /// Blob and the persisted data URL so playback mime types stay correct.
  String _mimeType = 'audio/webm';
  web.HTMLAudioElement? _audio;
  StreamSubscription<web.BlobEvent>? _dataSub;
  StreamSubscription<web.Event>? _stopSub;
  bool _isRecording = false;

  @override
  bool get isSupported => true;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> start() async {
    if (_isRecording) return;
    final mediaDevices = web.window.navigator.mediaDevices;

    final web.MediaStream stream;
    try {
      stream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
    } catch (_) {
      throw UnsupportedError('Could not access the microphone.');
    }

    final web.MediaRecorder recorder;
    try {
      recorder = web.MediaRecorder(stream);
    } catch (_) {
      stream.getTracks().toDart.forEach((track) => track.stop());
      throw UnsupportedError('Your browser does not support audio recording.');
    }

    _stream = stream;
    _recorder = recorder;
    _mimeType = recorder.mimeType.isNotEmpty ? recorder.mimeType : 'audio/webm';
    _chunks.clear();
    _stopCompleter = Completer<web.Blob?>();

    _dataSub = _dataAvailable.forTarget(recorder).listen((e) {
      final data = e.data;
      if (data.size > 0) _chunks.add(data);
    });
    _stopSub = _recorderStop.forTarget(recorder).listen((_) {
      final completer = _stopCompleter;
      if (completer == null || completer.isCompleted) return;
      if (_chunks.isEmpty) {
        completer.complete(null);
      } else {
        completer.complete(
            web.Blob(_chunks.toJS, web.BlobPropertyBag(type: _mimeType)));
      }
    });

    try {
      recorder.start();
    } catch (_) {
      _teardown();
      throw UnsupportedError('Could not start recording.');
    }
    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_isRecording) return null;
    final recorder = _recorder;
    final completer = _stopCompleter;
    web.Blob? blob;
    try {
      if (recorder != null && recorder.state != 'inactive') {
        recorder.stop();
      }
      if (completer != null) blob = await completer.future;
    } catch (_) {
      blob = null;
    }
    String? dataUrl;
    if (blob != null) {
      try {
        dataUrl = await _toDataUrl(blob);
      } catch (_) {
        dataUrl = null;
      }
    }
    _teardown();
    return dataUrl;
  }

  /// Encodes the captured audio as a base64 `data:` URL. Unlike an object URL
  /// (which dies with the page), a data URL survives a reload, so it can be
  /// persisted and played back after the app restarts.
  Future<String> _toDataUrl(web.Blob blob) async {
    final buffer = (await blob.arrayBuffer().toDart).toDart;
    final b64 = base64Encode(buffer.asUint8List());
    return 'data:$_mimeType;base64,$b64';
  }

  @override
  Future<void> play(String url) async {
    stopPlay();
    final a = web.HTMLAudioElement()..src = url;
    _audio = a;
    await a.play().toDart;
  }

  @override
  void stopPlay() {
    try {
      _audio?.pause();
    } catch (_) {}
    _audio = null;
  }

  @override
  Future<void> dispose() async {
    stopPlay();
    try {
      if (_isRecording) await stop();
    } catch (_) {}
    _teardown();
  }

  /// Stop mic tracks and clear recorder state (does not touch playback).
  void _teardown() {
    _dataSub?.cancel();
    _dataSub = null;
    _stopSub?.cancel();
    _stopSub = null;
    final stream = _stream;
    if (stream != null) {
      stream.getTracks().toDart.forEach((track) => track.stop());
    }
    _stream = null;
    _recorder = null;
    _stopCompleter = null;
    _chunks.clear();
    _isRecording = false;
  }
}
