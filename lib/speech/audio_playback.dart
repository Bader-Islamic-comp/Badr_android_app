import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a WAV that is already in memory. Tests pass a fake.
abstract class AudioPlayback {
  /// Plays [wav] and completes when it has finished or was stopped. Throws
  /// [AudioPlaybackException] when it cannot play.
  Future<void> play(Uint8List wav);

  /// Stops whatever is playing.
  Future<void> stop();

  Future<void> dispose();
}

class AudioPlaybackException implements Exception {
  const AudioPlaybackException();

  @override
  String toString() => 'This phone could not play the voice.';
}

/// [AudioPlayback] on the `audioplayers` plugin. On Android the bytes go to
/// the player as a `MediaDataSource` in memory. On iOS, macOS and Linux the
/// plugin would write them to a temporary file first, so there it refuses to
/// play rather than leave a file behind.
class AudioPlayersPlayback implements AudioPlayback {
  AudioPlayersPlayback();

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _states;
  StreamSubscription<AudioEvent>? _errors;
  Completer<void>? _done;

  static bool get _inMemory =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Made on first use, never at app start.
  AudioPlayer get _plugin {
    final existing = _player;
    if (existing != null) return existing;
    final player = _player = AudioPlayer();
    // Only the end of the audio finishes a play here. A stop finishes it
    // directly, so a late "stopped" from an earlier play cannot end this one.
    _states = player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.disposed) {
        _finish();
      }
    });
    _errors = player.eventStream.listen(null, onError: (_) => _finish());
    return player;
  }

  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> play(Uint8List wav) async {
    if (!_inMemory) throw const AudioPlaybackException();
    await stop();
    final done = _done = Completer<void>();
    try {
      await _plugin.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (_) {
      _finish();
      throw const AudioPlaybackException();
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    _finish();
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _finish();
    await _states?.cancel();
    await _errors?.cancel();
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
