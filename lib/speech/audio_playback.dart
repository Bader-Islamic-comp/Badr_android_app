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
///
/// A play ends when the audio does, when it is stopped, and also when the
/// platform stops it without saying so: Android pauses the player when
/// another app takes the audio focus for good, and the plugin sends no word
/// of it. A play still going well past its audio's own length is therefore
/// ended here, so Robert does not stay "speaking" with his talk cue running.
class AudioPlayersPlayback implements AudioPlayback {
  /// Tests pass their own [player].
  AudioPlayersPlayback({AudioPlayer Function()? player})
      : _makePlayer = player ?? AudioPlayer.new;

  final AudioPlayer Function() _makePlayer;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _states;
  StreamSubscription<AudioEvent>? _errors;
  Completer<void>? _done;
  Timer? _deadline;

  /// Room for the player to start, and for a short interruption it recovers
  /// from, past the audio's own length.
  static const _grace = Duration(seconds: 3);

  static bool get _inMemory =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Made on first use, never at app start.
  AudioPlayer get _plugin {
    final existing = _player;
    if (existing != null) return existing;
    final player = _player = _makePlayer();
    // The end of the audio finishes a play here, and so does a pause, which
    // this class never asks for. A stop finishes it directly, so a late
    // "stopped" from an earlier play cannot end this one.
    _states = player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed ||
          state == PlayerState.paused ||
          state == PlayerState.disposed) {
        _finish();
      }
    });
    _errors = player.eventStream.listen(null, onError: (_) => _finish());
    return player;
  }

  /// How long [wav] plays, from its header's byte rate.
  static Duration _length(Uint8List wav) {
    final rate = wav.length >= 32
        ? ByteData.sublistView(wav).getUint32(28, Endian.little)
        : 0;
    // The service's own format, should a header not say.
    final perSecond = rate > 0 ? rate : 32000;
    final audio = wav.length > 44 ? wav.length - 44 : 0;
    return Duration(microseconds: audio * 1000000 ~/ perSecond);
  }

  void _finish() {
    _deadline?.cancel();
    _deadline = null;
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> play(Uint8List wav) async {
    if (!_inMemory) throw const AudioPlaybackException();
    await stop();
    final done = _done = Completer<void>();
    final longest = _length(wav) + _grace;
    try {
      await _plugin.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (_) {
      _finish();
      throw const AudioPlaybackException();
    }
    if (identical(_done, done)) {
      _deadline = Timer(longest, () {
        if (!identical(_done, done)) return;
        // Paused or lost by the platform: ended, and stopped so it does not
        // carry on later by itself.
        unawaited(stop());
      });
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    _finish();
    try {
      await _player?.stop();
    } catch (_) {
      // Already stopped, or gone.
    }
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
