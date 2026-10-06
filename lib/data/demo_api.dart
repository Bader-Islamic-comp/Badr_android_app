import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/speech_models.dart';

/// Development only. These values are embedded in builds, not secure storage.
class DemoConfig {
  const DemoConfig({this.baseUrl = '', this.token = ''});

  factory DemoConfig.environment() => const DemoConfig(
        baseUrl: String.fromEnvironment('DEMO_API_URL'),
        token: String.fromEnvironment('DEMO_API_TOKEN'),
      );

  final String baseUrl;
  final String token;

  bool get enabled {
    final uri = Uri.tryParse(baseUrl);
    return token.isNotEmpty &&
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        (uri.path.isEmpty || uri.path == '/');
  }
}

class DemoApiException implements Exception {
  const DemoApiException(this.message, {this.code});
  final String message;

  /// The service's error code, only when it is one this app knows
  /// ([DemoApi.knownErrors]). Never the service's own text.
  final String? code;
  @override
  String toString() => message;
}

class DemoApi {
  DemoApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final DemoConfig config;
  final http.Client _client;
  static String newKey() => const Uuid().v4();

  /// The largest audio body the service accepts, header included.
  static const maxAudioBytes = 1048576;

  /// The largest audio the app will take from the service: a part of Robert's
  /// reply, a dhikr or a recorded dua.
  static const maxPlaybackBytes = 8 * 1024 * 1024;

  static const _jsonTimeout = Duration(seconds: 12);

  /// Uploads wait for speech recognition, and audio reads may wait for the
  /// speech service.
  static const _audioTimeout = Duration(seconds: 30);

  static const _generic = 'The service could not finish this request.';

  /// Error codes the app knows. Each picks the app's own wording, or the
  /// generic line where the child needs nothing more; the service's text is
  /// never shown. Any other code reads the generic line and is not passed on.
  static const knownErrors = <String, String>{
    // The speech service is down, or full: the backend has already retried.
    'speech_unavailable':
        'Voice practice is resting right now. Please try again a little later.',
    'speech_busy':
        'Lots of voices at once right now. Please try again in a moment.',
    // The service's switch for this part of the preview is off.
    'speech_disabled':
        'This part of the voice preview is switched off right now.',
    'request_too_large': 'That recording was too long to send.',
    'unsupported_media_type': _generic,
    'invalid_request': _generic,
    'item_not_found': 'This one is not ready for practice yet.',
    'audio_not_found': 'This voice is not ready yet.',
    'round_complete': 'This round is already finished.',
    'round_not_found': 'This round has ended. Start a new one.',
    // The same key while its first request is still running. The app sends
    // one request at a time, so this only follows a lost answer.
    'request_in_progress':
        'Still working on the last one. Please wait a moment.',
    'turn_pending': 'Robert is still finishing this reply.',
    'not_found': _generic,
  };

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body,
      String? key,
      Map<String, String>? query}) async {
    if (!config.enabled) {
      throw const DemoApiException('The development service is not connected.');
    }
    if (method != 'GET' && key == null) {
      throw ArgumentError('Writes require a stable idempotency key.');
    }
    final request = _request(method, path, query);
    request.headers.addAll({
      'Accept': 'application/json',
      if (key != null) 'Idempotency-Key': key,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _decode(await _send(request, _jsonTimeout));
  }

  /// Sends a recording as the raw body (`audio/wav`, never multipart) and
  /// reads the JSON answer. The bytes are only in memory; once the answer is
  /// in, this side's copy of them is cleared.
  ///
  /// Practice and game attempts are writes and carry [key]. A transcription
  /// is not a write and carries none: the service keeps nothing to replay.
  Future<Map<String, dynamic>> postAudio(String path, Uint8List wav,
      {required String? key, Map<String, String>? query}) async {
    if (wav.length > maxAudioBytes) {
      throw const DemoApiException('That recording was too long to send.',
          code: 'request_too_large');
    }
    if (!_isWav(wav)) {
      throw ArgumentError('Only WAV audio is sent.');
    }
    final request = _request('POST', path, query);
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'audio/wav',
      if (key != null) 'Idempotency-Key': key,
    });
    request.bodyBytes = wav;
    try {
      return _decode(await _send(request, _audioTimeout));
    } finally {
      request.bodyBytes.fillRange(0, request.bodyBytes.length, 0);
    }
  }

  /// Reads a WAV file into memory: Robert's voice or a recorded dua. Nothing
  /// is written to storage.
  Future<Uint8List> getAudio(String path) async {
    final request = _request('GET', path, null);
    request.headers['Accept'] = 'audio/wav';
    final response = await _send(request, _audioTimeout);
    final type = response.headers['content-type'] ?? '';
    final bytes = response.bodyBytes;
    if (response.statusCode != 200 ||
        !RegExp(r'^audio/(x-)?wave?\b').hasMatch(type) ||
        bytes.length > maxPlaybackBytes ||
        !_isWav(bytes)) {
      throw const DemoApiException('The service returned unexpected audio.');
    }
    return bytes;
  }

  static bool _isWav(Uint8List bytes) =>
      bytes.length > 44 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE';

  http.Request _request(
      String method, String path, Map<String, String>? query) {
    if (!config.enabled) {
      throw const DemoApiException('The development service is not connected.');
    }
    var uri = Uri.parse(config.baseUrl).resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final request = http.Request(method, uri);
    // A redirect must not forward the development credential to another host.
    request.followRedirects = false;
    request.headers['X-Demo-Token'] = config.token;
    return request;
  }

  Future<http.Response> _send(http.Request request, Duration timeout) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } catch (_) {
      throw const DemoApiException('Connection unavailable. Please try again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Never expose or log server bodies, request text or credentials. Only
      // a known error code is read, and it picks the app's own wording.
      final code = _errorCode(response);
      throw DemoApiException(knownErrors[code] ?? _generic, code: code);
    }
    return response;
  }

  static String? _errorCode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final code = decoded is Map ? decoded['error'] : null;
      final value = code is Map ? code['code'] : null;
      return knownErrors.containsKey(value) ? value as String : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 204) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const DemoApiException(
          'The service returned an unexpected response.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DemoApiException(
          'The service returned an unexpected response.');
    }
    return decoded;
  }

  /// Confirms this is the development-only service and returns whether it has
  /// grounded answers switched on, and whether those answers come from
  /// unreviewed drafts.
  ///
  /// Grounded answers are the one feature the service may report as on, and
  /// only the service decides it: the app never turns answers on, it only
  /// learns whether they are. The one other value it accepts is the adult
  /// operator's corpus preview (`contentStatus: unreviewed_drafts`,
  /// `comp-server/doc/rag-system.md` §9.1), which the app then labels on every
  /// library reply; drafts without answers make no sense and are refused.
  /// Everything else stays as strict as before — voice on, another mode or
  /// reviewed content would each mean a service this build was not made for.
  ///
  /// The speech preview (`features.speech`) is read too. The release gate's
  /// own switch, `features.voice`, must still be false: the preview is a
  /// separate development switch, never the released voice feature.
  Future<({bool groundedAnswers, bool unreviewedDrafts, SpeechFeatures speech})>
      bootstrap() async {
    final result = await request('GET', '/v1/bootstrap');
    final features = result['features'];
    final status = result['contentStatus'];
    if (result['mode'] != 'development' ||
        result['characterId'] != 'robert' ||
        result['profileId'] != 'demo-child' ||
        (status != 'awaiting_review' && status != 'unreviewed_drafts') ||
        features is! Map ||
        features['voice'] != false ||
        features['generativeAnswers'] is! bool ||
        (status == 'unreviewed_drafts' &&
            features['generativeAnswers'] != true)) {
      throw const DemoApiException(
          'This app requires the development-only service.');
    }
    return (
      groundedAnswers: features['generativeAnswers'] as bool,
      unreviewedDrafts: status == 'unreviewed_drafts',
      speech: _speech(features['speech']),
    );
  }

  /// A preview object the app cannot read is a service it was not built for.
  static SpeechFeatures _speech(dynamic value) {
    try {
      return SpeechFeatures.fromJson(value);
    } on DemoApiException {
      throw const DemoApiException(
          'This app requires the development-only service.');
    }
  }

  Future<Map<String, dynamic>> completeLesson(String key) =>
      request('POST', '/v1/lessons/demo-learning/complete', body: {}, key: key);

  Future<Map<String, dynamic>> lessons() => request('GET', '/v1/lessons');
  Future<Map<String, dynamic>> rewards() => request('GET', '/v1/rewards');
  Future<Map<String, dynamic>> inventory() => request('GET', '/v1/inventory');
  Future<Map<String, dynamic>> challenges() =>
      request('GET', '/v1/challenges/today');

  /// Spends earned stars on a look. The service owns the price and the
  /// balance; this never sends either, so a tampered client cannot buy one.
  Future<void> claimCosmetic(String cosmeticId, String key) async {
    final result = await request('POST', '/v1/cosmetics/claim',
        body: {'cosmeticId': cosmeticId}, key: key);
    if (result['cosmeticId'] != cosmeticId || result['owned'] != true) {
      throw const DemoApiException('The service did not confirm this look.');
    }
  }

  /// Wears a look the service already records as owned. Ownership is read back
  /// first so a look is never pushed to the room on the app's say-so.
  Future<void> equipCosmetic(String cosmeticId, String key) async {
    final inventoryResult = await inventory();
    final items = inventoryResult['items'];
    if (items is! List ||
        !items.any((item) =>
            item is Map &&
            item['id'] == cosmeticId &&
            item['characterId'] == 'robert' &&
            item['owned'] == true)) {
      throw const DemoApiException('That look is not earned yet.');
    }
    final result = await request('PUT', '/v1/equipped-cosmetics',
        body: {'cosmeticId': cosmeticId}, key: key);
    if (result['cosmeticId'] != cosmeticId ||
        result['characterId'] != 'robert') {
      throw const DemoApiException(
          'The service did not confirm this appearance.');
    }
  }

  // The speech preview. Every route is the backend's; the app never talks to
  // the speech service itself.

  Future<AdhkarList> adhkar() async =>
      AdhkarList.fromJson(await request('GET', '/v1/adhkar'));

  Future<DuaList> duas() async =>
      DuaList.fromJson(await request('GET', '/v1/duas'));

  /// Robert saying one of the four adhkar.
  Future<Uint8List> dhikrAudio(String dhikrId) =>
      getAudio('/v1/audio/adhkar/${Uri.encodeComponent(dhikrId)}');

  /// A recorded human voice for a dua.
  Future<Uint8List> duaAudio(String duaId) =>
      getAudio('/v1/audio/duas/${Uri.encodeComponent(duaId)}');

  /// Robert saying a feedback line.
  Future<Uint8List> feedbackAudio(String copyId) =>
      getAudio('/v1/audio/feedback/${Uri.encodeComponent(copyId)}');

  /// Practice of a dhikr (segment 0) or a dua's part. No stars.
  Future<PracticeResult> practise(
          {required String itemId,
          required int segment,
          required int attempt,
          required Uint8List wav,
          required String key}) async =>
      PracticeResult.fromJson(
          await postAudio('/v1/recitations/attempts', wav, key: key, query: {
        'itemId': itemId,
        'segment': '$segment',
        'attempt': '$attempt',
      }));

  Future<DhikrGame> dhikrGame() async =>
      DhikrGame.fromJson(await request('GET', '/v1/games/dhikr'));

  Future<DhikrRound> startDhikrRound(String dhikrId, String key) async {
    final round = DhikrRound.fromJson(await request(
        'POST', '/v1/games/dhikr/rounds',
        body: {'dhikrId': dhikrId}, key: key));
    if (round.dhikrId != dhikrId) {
      throw const DemoApiException(
          'The service returned an unexpected response.');
    }
    return round;
  }

  Future<DhikrAttempt> dhikrAttempt(
      String roundId, Uint8List wav, String key) async {
    final result = DhikrAttempt.fromJson(await postAudio(
        '/v1/games/dhikr/rounds/${Uri.encodeComponent(roundId)}/attempts', wav,
        key: key));
    if (result.round.roundId != roundId) {
      throw const DemoApiException(
          'The service returned an unexpected response.');
    }
    return result;
  }

  /// What the service heard, for the child to check before sending. No
  /// idempotency key: the service keeps no transcript to replay.
  Future<Transcription> transcribe(Uint8List wav, {required String language}) {
    if (language != 'ar' && language != 'en') {
      throw ArgumentError.value(language, 'language');
    }
    return postAudio('/v1/speech/transcriptions', wav,
        key: null, query: {'language': language}).then(Transcription.fromJson);
  }

  /// Asks for Robert's voice for a completed reply. The service is
  /// idempotent by turn: asking again reports the job already started.
  Future<TurnSpeech> requestTurnSpeech(String turnId, String key) async =>
      TurnSpeech.fromJson(await request(
          'POST', '/v1/turns/${Uri.encodeComponent(turnId)}/speech',
          key: key));

  Future<TurnSpeech> turnSpeech(String turnId) async => TurnSpeech.fromJson(
      await request('GET', '/v1/turns/${Uri.encodeComponent(turnId)}/speech'));

  Future<Uint8List> turnSpeechPart(String turnId, int index) =>
      getAudio('/v1/turns/${Uri.encodeComponent(turnId)}/speech/parts/$index');

  void close() => _client.close();
}
