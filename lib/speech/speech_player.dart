import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/demo_api.dart';
import 'audio_playback.dart';

/// Plays one voice at a time on a page: Robert saying a dhikr or a feedback
/// line, or a recorded dua. The audio is read into memory, played and
/// dropped. It stops when another starts, when the page closes and when the
/// app leaves the screen.
class SpeechPlayer extends ChangeNotifier with WidgetsBindingObserver {
  SpeechPlayer(AudioPlayback Function() playback) : _makePlayback = playback {
    WidgetsBinding.instance.addObserver(this);
  }

  static const couldNotPlay = 'This phone could not play the voice.';

  final AudioPlayback Function() _makePlayback;
  AudioPlayback? _playback;
  int _generation = 0;
  bool _disposed = false;

  /// What is being fetched, by the caller's id.
  String? loading;

  /// What is playing, by the caller's id.
  String? playing;

  /// The id the last problem belongs to, and what to say about it.
  String? problemId;
  String? problem;

  bool busyWith(String id) => loading == id || playing == id;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Fetches the voice with [fetch] and plays it, as [id].
  Future<void> play(String id, Future<Uint8List> Function() fetch) async {
    await stop();
    final generation = ++_generation;
    loading = id;
    problemId = null;
    problem = null;
    _changed();
    try {
      final bytes = await fetch();
      if (generation != _generation || _disposed) return;
      loading = null;
      playing = id;
      _changed();
      try {
        await (_playback ??= _makePlayback()).play(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } on DemoApiException catch (error) {
      if (generation == _generation) {
        problemId = id;
        problem = error.message;
      }
    } on AudioPlaybackException {
      if (generation == _generation) {
        problemId = id;
        problem = couldNotPlay;
      }
    } finally {
      if (generation == _generation) {
        loading = null;
        playing = null;
        _changed();
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    final wasBusy = loading != null || playing != null;
    loading = null;
    playing = null;
    if (wasBusy) _changed();
    await _playback?.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final playback = _playback;
    _playback = null;
    unawaited(playback?.dispose());
    super.dispose();
  }
}
