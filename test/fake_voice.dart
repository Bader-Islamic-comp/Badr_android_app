import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_mobile/speech/audio_playback.dart';
import 'package:companion_mobile/speech/voice_recorder.dart';
import 'package:companion_mobile/speech/wav.dart';
import 'package:http/http.dart' as http;

/// A microphone that hears what the test says: [speak] adds PCM bytes to the
/// open stream. It proves nothing about Android's recorder.
class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.allow = true});

  /// Whether the permission prompt is answered yes.
  bool allow;
  int permissionAsks = 0;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  StreamController<Uint8List>? _stream;

  /// Runs while the permission is being asked for, as Android's prompt
  /// would: a test makes the app inactive or takes the touch away here.
  Future<void> Function()? whileAsking;

  /// When set, a stop does not finish until this completes, like a platform
  /// stop that takes a moment.
  Completer<void>? stopGate;

  bool get recording => _stream != null;

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    await whileAsking?.call();
    return allow;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    final stream = _stream = StreamController<Uint8List>();
    return stream.stream;
  }

  /// [bytes] of PCM, all of value 1 so a cleared buffer is told apart.
  void speak(int bytes) =>
      _stream?.add(Uint8List(bytes)..fillRange(0, bytes, 1));

  void speakSeconds(num seconds) =>
      speak((seconds * recordingBytesPerSecond).round());

  @override
  Future<void> stop() async {
    stops++;
    final stream = _stream;
    _stream = null;
    unawaited(stream?.close());
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}

/// A player that notes what it was given, by the first sample of the WAV
/// (see [markedWav]). With [hold] set, each play lasts until [finish] or a
/// stop; otherwise it ends at once.
class FakePlayback implements AudioPlayback {
  FakePlayback({this.hold = false, this.fail = false});

  bool hold;
  bool fail;
  final List<int> played = [];
  int stops = 0;
  Completer<void>? _current;

  bool get playing => _current != null;

  @override
  Future<void> play(Uint8List wav) {
    if (fail) throw const AudioPlaybackException();
    played.add(wav[wavHeaderBytes]);
    if (!hold) return Future.value();
    final current = _current = Completer<void>();
    return current.future;
  }

  /// Ends the play in progress, as reaching the end of the audio would.
  void finish() {
    final current = _current;
    _current = null;
    current?.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }

  @override
  Future<void> dispose() async => finish();
}

/// A tiny WAV whose samples are all [marker], so a fake player can tell which
/// one it was given.
Uint8List markedWav(int marker) =>
    wavFromPcm16(Uint8List(64)..fillRange(0, 64, marker));

http.Response wavResponse(int marker) =>
    http.Response.bytes(markedWav(marker), 200,
        headers: {'content-type': 'audio/wav'});

http.Response jsonResponse(Object? value, {int status = 200}) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});

http.Response errorResponse(int status, String code) => jsonResponse({
      'error': {'code': code}
    }, status: status);

/// A practice result as the service sends it.
Map<String, Object?> practiceResult({
  String outcome = 'try_again',
  List<Map<String, Object?>> words = const [],
  bool showWords = true,
  String copyId = 'some_unclear',
  String text = 'جيد، بعض الكلمات تحتاج تمرين.',
  bool audio = false,
}) =>
    {
      'outcome': outcome,
      'words': words,
      'showWords': showWords,
      'feedback': {'copyId': copyId, 'text': text, 'audio': audio},
    };

const adhkarItems = [
  {
    'id': 'takbeer',
    'nameAr': 'التكبير',
    'nameEn': 'Takbeer',
    'transliteration': 'Allahu akbar',
    'text': 'اللَّهُ أَكْبَرُ',
    'audio': true,
    'practice': true,
  },
  {
    'id': 'tasbeeh',
    'nameAr': 'التسبيح',
    'nameEn': 'Tasbeeh',
    'transliteration': 'Subhan Allah',
    'text': 'سُبْحَانَ اللَّهِ',
    'audio': false,
    'practice': true,
  },
];

Map<String, Object?> round({
  String roundId = 'round-1',
  String dhikrId = 'takbeer',
  int attempts = 0,
  int counted = 0,
  bool complete = false,
  bool starAwarded = false,
}) =>
    {
      'roundId': roundId,
      'dhikrId': dhikrId,
      'attempts': attempts,
      'countedAttempts': counted,
      'complete': complete,
      'starAwarded': starAwarded,
    };
