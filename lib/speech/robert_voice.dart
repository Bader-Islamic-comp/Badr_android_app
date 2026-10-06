import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/demo_api.dart';
import '../domain/speech_models.dart';
import 'audio_playback.dart';
import 'voice_kit.dart';

enum RobertVoiceStatus {
  /// Nothing asked, or the last reply was spoken to the end.
  idle,

  /// The service is making the voice; parts play as they are ready.
  preparing,

  /// A part is playing.
  playing,

  /// The service has no voice for this reply.
  unavailable,

  /// Waiting took longer than [VoiceKit.voiceDeadline].
  slow,

  /// A request or the player did not work.
  problem,
}

/// Robert reading his reply aloud, on request.
///
/// "Listen" asks the service for the voice of one completed reply, then reads
/// its state every [VoiceKit.pollInterval] for at most
/// [VoiceKit.voiceDeadline], and plays the parts in order as each is ready.
/// A part the service gave up on is skipped. The audio is only in memory,
/// and Robert's talk cue runs while it plays ([onSpeaking]). Stopping, a new
/// reply, leaving Talk and leaving the app all end it.
class RobertVoice extends ChangeNotifier {
  RobertVoice(this.api, this.kit, {required this.onSpeaking});

  static const slowCopy =
      'Robert’s voice is taking a long time. You can try Listen again later.';
  static const couldNotPlay = 'This phone could not play Robert’s voice.';

  final DemoApi api;
  final VoiceKit kit;

  /// True while a part plays, false when it stops: drives the talk cue.
  final ValueChanged<bool> onSpeaking;

  AudioPlayback? _playback;
  int _generation = 0;
  bool _speaking = false;
  bool _disposed = false;

  RobertVoiceStatus status = RobertVoiceStatus.idle;

  /// The reply the status is about.
  String? turnId;

  /// What to say for [RobertVoiceStatus.problem].
  String? problem;

  bool get active =>
      status == RobertVoiceStatus.preparing ||
      status == RobertVoiceStatus.playing;

  void _set(RobertVoiceStatus value, {String? message}) {
    status = value;
    problem = message;
    if (!_disposed) notifyListeners();
  }

  void _speak(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    onSpeaking(value);
  }

  Future<void> listen(String turnId) async {
    await stop();
    if (_disposed) return;
    final generation = ++_generation;
    bool current() => generation == _generation && !_disposed;
    this.turnId = turnId;
    _set(RobertVoiceStatus.preparing);
    final deadline = kit.clock().add(kit.voiceDeadline);
    try {
      // A fresh key for each Listen: the service is idempotent by turn, and a
      // key still in flight from a stopped Listen would be refused.
      var speech = await api.requestTurnSpeech(turnId, DemoApi.newKey());
      var next = 0;
      var played = 0;
      while (current()) {
        // Every part that is ready now, in order. A part not ready yet holds
        // the line while the voice is still being made, and is skipped once
        // the service has finished without it.
        for (final part in speech.parts) {
          if (part.index < next) continue;
          if (!part.ready) {
            if (speech.status == TurnSpeechStatus.pending) break;
            next = part.index + 1;
            continue;
          }
          final Uint8List bytes;
          try {
            bytes = await api.turnSpeechPart(turnId, part.index);
          } on DemoApiException catch (error) {
            // Gone since it was listed (parts are kept for 15 minutes):
            // skipped, like a part the service dropped.
            if (error.code != 'audio_not_found') rethrow;
            next = part.index + 1;
            continue;
          }
          if (!current()) return;
          _set(RobertVoiceStatus.playing);
          _speak(true);
          try {
            await (_playback ??= kit.playback()).play(bytes);
          } finally {
            bytes.fillRange(0, bytes.length, 0);
            if (current()) _speak(false);
          }
          if (!current()) return;
          next = part.index + 1;
          played++;
        }
        if (speech.status != TurnSpeechStatus.pending) {
          _set(played > 0
              ? RobertVoiceStatus.idle
              : RobertVoiceStatus.unavailable);
          return;
        }
        if (!kit.clock().isBefore(deadline)) {
          _set(RobertVoiceStatus.slow);
          return;
        }
        _set(RobertVoiceStatus.preparing);
        await kit.pause(kit.pollInterval);
        if (!current()) return;
        speech = await api.turnSpeech(turnId);
      }
    } on DemoApiException catch (error) {
      if (!current()) return;
      // An unknown turn, or Robert's voice switched off since connecting:
      // there is simply no voice for this reply.
      if (error.code == 'not_found' || error.code == 'speech_disabled') {
        _set(RobertVoiceStatus.unavailable);
      } else {
        _set(RobertVoiceStatus.problem, message: error.message);
      }
    } on AudioPlaybackException {
      if (current()) _set(RobertVoiceStatus.problem, message: couldNotPlay);
    }
  }

  /// Stops listening now: polling ends and the audio stops.
  Future<void> stop() async {
    _generation++;
    _speak(false);
    if (status != RobertVoiceStatus.idle || turnId != null) {
      turnId = null;
      _set(RobertVoiceStatus.idle);
    }
    await _playback?.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _speak(false);
    final playback = _playback;
    _playback = null;
    unawaited(playback?.dispose());
    super.dispose();
  }
}
