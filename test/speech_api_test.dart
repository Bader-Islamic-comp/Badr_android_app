import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/speech_models.dart';
import 'package:companion_mobile/speech/wav.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_voice.dart';

/// The speech preview's WAV, payload parsing and requests.
void main() {
  const config =
      DemoConfig(baseUrl: 'http://localhost:8000', token: 'synthetic-token');

  group('WAV header', () {
    test('wraps PCM16 mono 16 kHz with correct RIFF sizes', () {
      final pcm = Uint8List.fromList(List.generate(3200, (i) => i % 256));
      final wav = wavFromPcm16(pcm);
      final header = ByteData.sublistView(wav);
      String tag(int at) => ascii.decode(wav.sublist(at, at + 4));
      expect(wav.length, 44 + 3200);
      expect(tag(0), 'RIFF');
      expect(header.getUint32(4, Endian.little), 36 + 3200);
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(header.getUint32(16, Endian.little), 16);
      expect(header.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(header.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000, reason: 'byte rate');
      expect(header.getUint16(32, Endian.little), 2, reason: 'block align');
      expect(header.getUint16(34, Endian.little), 16, reason: '16-bit');
      expect(tag(36), 'data');
      expect(header.getUint32(40, Endian.little), 3200);
      expect(wav.sublist(44), pcm);
    });

    test('leaves out half a sample', () {
      final wav = wavFromPcm16(Uint8List(5));
      expect(wav.length, 44 + 4);
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 4);
      expect(ByteData.sublistView(wav).getUint32(4, Endian.little), 40);
    });

    test('an empty recording is a valid empty WAV', () {
      final wav = wavFromPcm16(Uint8List(0));
      expect(wav.length, 44);
      expect(ByteData.sublistView(wav).getUint32(4, Endian.little), 36);
    });
  });

  group('features.speech', () {
    Map<String, Object?> speech(
            {bool preview = true,
            bool recitation = true,
            bool voiceQuestions = true,
            bool robertVoice = true,
            Object? seconds = 15}) =>
        {
          'preview': preview,
          'recitation': recitation,
          'voiceQuestions': voiceQuestions,
          'robertVoice': robertVoice,
          'maxRecordingSeconds': seconds,
        };

    test('absent is off', () {
      expect(SpeechFeatures.fromJson(null), SpeechFeatures.off);
    });

    test('reads every switch', () {
      expect(
          SpeechFeatures.fromJson(speech(robertVoice: false)),
          const SpeechFeatures(
              preview: true,
              recitation: true,
              voiceQuestions: true,
              maxRecordingSeconds: 15));
    });

    test('no feature counts while the preview is off', () {
      final off = SpeechFeatures.fromJson(speech(preview: false));
      expect(off.recitation || off.voiceQuestions || off.robertVoice, isFalse);
    });

    for (final (name, value) in [
      ('a string switch', {...speech(), 'preview': 'true'}),
      ('a missing switch', {...speech()}..remove('robertVoice')),
      ('no recording bound', speech(seconds: null)),
      ('a recording over 30 s', speech(seconds: 31)),
      ('a zero recording bound', speech(seconds: 0)),
      ('a list', ['preview']),
    ]) {
      test('refuses $name', () {
        expect(() => SpeechFeatures.fromJson(value),
            throwsA(isA<DemoApiException>()));
      });
    }

    test('the bootstrap reads it, and still needs voice off', () async {
      Map<String, Object?> bootstrap(Map<String, Object?> features) => {
            'mode': 'development',
            'characterId': 'robert',
            'profileId': 'demo-child',
            'contentStatus': 'awaiting_review',
            'features': features,
          };
      DemoApi serving(Map<String, Object?> payload) => DemoApi(config,
          client: MockClient((_) async => jsonResponse(payload)));

      final on = serving(bootstrap(
          {'voice': false, 'generativeAnswers': false, 'speech': speech()}));
      expect((await on.bootstrap()).speech.recitation, isTrue);

      for (final features in [
        {'voice': true, 'generativeAnswers': false, 'speech': speech()},
        {
          'voice': false,
          'generativeAnswers': false,
          'speech': speech(seconds: 'fifteen'),
        },
      ]) {
        await expectLater(
            serving(bootstrap(features)).bootstrap(),
            throwsA(isA<DemoApiException>().having((e) => e.message, 'message',
                'This app requires the development-only service.')));
      }
    });
  });

  group('learn content', () {
    test('adhkar: the allowlist only, each once', () {
      final list =
          AdhkarList.fromJson({'items': adhkarItems, 'reviewStatus': 'draft'});
      expect(list.items.map((d) => d.id), ['takbeer', 'tasbeeh']);
      expect(list.items.first.audio, isTrue);
      expect(list.items.first.transliteration, 'Allahu akbar');
      expect(list.draft, isTrue);
      for (final items in [
        [
          {...adhkarItems.first, 'id': 'ayat-al-kursi'}
        ],
        [adhkarItems.first, adhkarItems.first],
        [
          {...adhkarItems.first, 'audio': 'yes'}
        ],
        [
          {...adhkarItems.first, 'text': ''}
        ],
        [
          {...adhkarItems.first}..remove('transliteration')
        ],
      ]) {
        expect(
            () =>
                AdhkarList.fromJson({'items': items, 'reviewStatus': 'draft'}),
            throwsA(isA<DemoApiException>()));
      }
      expect(
          () => AdhkarList.fromJson(
              {'items': adhkarItems, 'reviewStatus': 'published'}),
          throwsA(isA<DemoApiException>()));
    });

    Map<String, Object?> dua({
      String id = 'morning-by-god',
      String kind = 'hadith_invocation',
      Object? audio,
      List<Map<String, Object?>> segments = const [
        {'index': 0, 'text': 'اللهم بك أصبحنا'},
        {'index': 1, 'text': 'وبك أمسينا'},
      ],
    }) =>
        {
          'id': id,
          'group': 'adhkar',
          'kind': kind,
          'title': 'اللهم بك أصبحنا',
          'childNote': 'أبدأ صباحي بذكر الله.',
          'repeat': 1,
          'occasions': ['morning'],
          'audio': audio,
          'segments': segments,
        };

    test('duas: the recorded slot and parts', () {
      final list = DuaList.fromJson({
        'items': [
          dua(),
          dua(
              id: 'dua-parents',
              kind: 'quran_recitation',
              audio: 'recorded',
              segments: const []),
        ],
        'reviewStatus': 'draft',
      });
      expect(list.items.first.recorded, isFalse);
      expect(list.items.first.segments.map((s) => s.index), [0, 1]);
      expect(list.items.last.recorded, isTrue);
      expect(list.items.last.segments, isEmpty);
      expect(Dua.fromJson({...dua(), 'childNote': ''}).childNote, isNull,
          reason: 'a dua without a note for the child');
    });

    for (final (name, value) in [
      ('a Quranic dua with parts', dua(kind: 'quran_recitation')),
      (
        'parts out of order',
        dua(segments: const [
          {'index': 1, 'text': 'وبك أمسينا'},
          {'index': 0, 'text': 'اللهم بك أصبحنا'},
        ])
      ),
      ('a computer voice', dua(audio: 'tts')),
      ('an id with a slash', dua(id: '../secret')),
      ('another group', {...dua(), 'group': 'stories'}),
    ]) {
      test('duas: refuses $name', () {
        expect(
            () => DuaList.fromJson({
                  'items': [value],
                  'reviewStatus': 'draft',
                }),
            throwsA(isA<DemoApiException>()));
      });
    }
  });

  group('practice and the game', () {
    test('a practice result with words', () {
      final result = PracticeResult.fromJson(practiceResult(words: [
        {'index': 0, 'state': 'clear'},
        {'index': 1, 'state': 'try_again'},
      ]));
      expect(result.outcome, PracticeOutcome.tryAgain);
      expect(result.words.map((w) => w.state),
          [PracticeOutcome.clear, PracticeOutcome.tryAgain]);
      expect(result.feedback.copyId, 'some_unclear');
    });

    for (final (name, value) in [
      ('an outcome that is a verdict', practiceResult(outcome: 'wrong')),
      (
        'words while they are hidden',
        practiceResult(showWords: false, words: [
          {'index': 0, 'state': 'clear'}
        ])
      ),
      (
        'a word twice',
        practiceResult(words: [
          {'index': 0, 'state': 'clear'},
          {'index': 0, 'state': 'unsure'},
        ])
      ),
      ('a copy id with spaces', practiceResult(copyId: 'all clear')),
      ('no feedback text', practiceResult(text: ' ')),
    ]) {
      test('refuses $name', () {
        expect(() => PracticeResult.fromJson(value),
            throwsA(isA<DemoApiException>()));
      });
    }

    test('the game and its rounds', () {
      final game = DhikrGame.fromJson({
        'items': [
          {...adhkarItems.first}..remove('transliteration')
        ],
        'starsPerRound': 1,
        'dailyStarCap': 10,
        'starsToday': 10,
      });
      expect(game.starsCollected, isTrue);
      final done = DhikrRound.fromJson(
          round(attempts: 4, counted: 3, complete: true, starAwarded: true));
      expect(done.starAwarded, isTrue);
      for (final bad in [
        round(counted: 4, attempts: 4),
        round(counted: 2, attempts: 1),
        round(starAwarded: true),
        round(roundId: 'round 1'),
        round(dhikrId: 'other'),
      ]) {
        expect(
            () => DhikrRound.fromJson(bad), throwsA(isA<DemoApiException>()));
      }
      expect(
          () => DhikrGame.fromJson({
                'items': [],
                'starsPerRound': 1,
                'dailyStarCap': 10,
                'starsToday': 11,
              }),
          throwsA(isA<DemoApiException>()));
    });

    test('a round may have any number of tries; three of them count', () {
      // Tries that do not count still add up on the service, with no limit.
      final long = DhikrRound.fromJson(round(attempts: 150, counted: 2));
      expect(long.attempts, 150);
      expect(long.countedAttempts, 2);
      expect(
          DhikrRound.fromJson(round(attempts: DhikrRound.maxAttempts)).attempts,
          DhikrRound.maxAttempts);
      for (final bad in [
        round(attempts: DhikrRound.maxAttempts + 1),
        round(attempts: -1),
        round(attempts: 150, counted: 4),
      ]) {
        expect(
            () => DhikrRound.fromJson(bad), throwsA(isA<DemoApiException>()));
      }
    });

    test('a scored try can be unsure with its words shown, as sent', () {
      // The service decides the outcome; the app never works it out from the
      // words.
      final result = PracticeResult.fromJson(practiceResult(
          outcome: 'unsure',
          words: [
            {'index': 0, 'state': 'clear'},
            {'index': 1, 'state': 'unsure'},
          ],
          text: 'لنحاول مرة أخرى معًا.'));
      expect(result.outcome, PracticeOutcome.unsure);
      expect(result.showWords, isTrue);
      expect(result.words.map((word) => word.state),
          [PracticeOutcome.clear, PracticeOutcome.unsure]);
      expect(result.feedback.text, 'لنحاول مرة أخرى معًا.');
    });
  });

  group('voice', () {
    test('a transcription, or nothing when unsure', () {
      expect(
          Transcription.fromJson({'status': 'transcribed', 'text': ' مرحبا '})
              .text,
          'مرحبا');
      expect(Transcription.fromJson({'status': 'unsure', 'text': null}).text,
          isNull);
      for (final bad in [
        {'status': 'transcribed', 'text': null},
        {'status': 'transcribed', 'text': 'x' * 1001},
        {'status': 'unsure', 'text': 'a guess'},
        {'status': 'abstained', 'text': null},
      ]) {
        expect(() => Transcription.fromJson(bad),
            throwsA(isA<DemoApiException>()));
      }
    });

    test('Robert’s voice: parts in order, at most six', () {
      final speech = TurnSpeech.fromJson({
        'status': 'pending',
        'parts': [
          {'index': 1, 'ready': false},
          {'index': 0, 'ready': true},
        ],
        'reason': null,
      });
      expect(speech.parts.map((p) => p.index), [0, 1]);
      // A dropped part leaves the list: gaps are fine.
      expect(
          TurnSpeech.fromJson({
            'status': 'ready',
            'parts': [
              {'index': 3, 'ready': true},
              {'index': 0, 'ready': true},
            ],
          }).parts.map((p) => p.index),
          [0, 3]);
      for (final bad in [
        {'status': 'done', 'parts': [], 'reason': null},
        {
          'status': 'ready',
          'parts': [
            for (var i = 0; i < 7; i++) {'index': i, 'ready': true}
          ],
          'reason': null,
        },
        {
          'status': 'ready',
          'parts': [
            {'index': 0, 'ready': true},
            {'index': 0, 'ready': true},
          ],
          'reason': null,
        },
        {'status': 'ready', 'parts': [], 'reason': 42},
      ]) {
        expect(
            () => TurnSpeech.fromJson(bad), throwsA(isA<DemoApiException>()));
      }
    });
  });

  group('requests', () {
    test('an attempt is raw WAV with the token, a key and its query', () async {
      late http.Request sent;
      final api = DemoApi(config, client: MockClient((request) async {
        sent = request;
        return jsonResponse(practiceResult());
      }));
      final wav = markedWav(7);
      await api.practise(
          itemId: 'takbeer', segment: 0, attempt: 2, wav: wav, key: 'key-1');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/v1/recitations/attempts');
      expect(sent.url.queryParameters,
          {'itemId': 'takbeer', 'segment': '0', 'attempt': '2'});
      expect(sent.headers['Content-Type'], 'audio/wav');
      expect(sent.headers['X-Demo-Token'], 'synthetic-token');
      expect(sent.headers['Idempotency-Key'], 'key-1');
      expect(sent.bodyBytes, markedWav(7), reason: 'raw bytes, not multipart');
      expect(wav.every((byte) => byte == 0), isTrue,
          reason: 'the app’s copy is cleared once the answer is in');
      api.close();
    });

    test('a transcription carries no key: nothing is kept to replay', () async {
      final requests = <http.Request>[];
      final api = DemoApi(config, client: MockClient((request) async {
        requests.add(request);
        return jsonResponse({'status': 'unsure', 'text': null});
      }));
      await api.transcribe(markedWav(1), language: 'en');
      final sent = requests.single;
      expect(sent.url.path, '/v1/speech/transcriptions');
      expect(sent.url.queryParameters, {'language': 'en'});
      expect(sent.headers.containsKey('Idempotency-Key'), isFalse);
      expect(sent.headers['Content-Type'], 'audio/wav');
      expect(() => api.transcribe(markedWav(1), language: 'fr'),
          throwsArgumentError);
      api.close();
    });

    // A widget test only for its fake clock: no real time passes.
    testWidgets(
        'an upload waits 75 s for the backend’s worst case, an audio read '
        '40 s and a JSON read 12 s', (tester) async {
      final api = DemoApi(config,
          client: MockClient((_) => Completer<http.Response>().future));
      const lost = 'Connection unavailable. Please try again.';
      String? upload, audio, json;
      String said(Object error) =>
          error is DemoApiException ? error.message : '$error';
      unawaited(api
          .practise(
              itemId: 'takbeer',
              segment: 0,
              attempt: 1,
              wav: markedWav(1),
              key: 'k')
          .then((_) => upload = 'answered',
              onError: (Object error) => upload = said(error)));
      unawaited(api.dhikrAudio('takbeer').then((_) => audio = 'answered',
          onError: (Object error) => audio = said(error)));
      unawaited(api.adhkar().then((_) => json = 'answered',
          onError: (Object error) => json = said(error)));

      await tester.pump(const Duration(seconds: 11));
      expect(json, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(json, lost);
      await tester.pump(const Duration(seconds: 26)); // 39 s
      expect(audio, isNull);
      expect(upload, isNull);
      await tester.pump(const Duration(seconds: 2)); // 41 s
      expect(audio, lost);
      await tester.pump(const Duration(seconds: 33)); // 74 s
      expect(upload, isNull, reason: 'the service may still be working on it');
      await tester.pump(const Duration(seconds: 2)); // 76 s
      expect(upload, lost);
      api.close();
    });

    test('audio over 1 MB is never sent', () async {
      var sent = false;
      final api = DemoApi(config, client: MockClient((_) async {
        sent = true;
        return jsonResponse({});
      }));
      final big = wavFromPcm16(Uint8List(DemoApi.maxAudioBytes));
      await expectLater(
          api.practise(
              itemId: 'takbeer', segment: 0, attempt: 1, wav: big, key: 'k'),
          throwsA(isA<DemoApiException>()));
      expect(sent, isFalse);
      api.close();
    });

    test('audio comes back as checked WAV bytes', () async {
      final api = DemoApi(config, client: MockClient((request) async {
        expect(request.headers['Accept'], 'audio/wav');
        return switch (request.url.path) {
          '/v1/audio/adhkar/takbeer' => wavResponse(3),
          '/v1/turns/turn-1/speech/parts/2' => wavResponse(4),
          '/v1/audio/duas/dua-sleep' => http.Response('not audio', 200,
              headers: {'content-type': 'audio/wav'}),
          _ => http.Response.bytes(markedWav(5), 200,
              headers: {'content-type': 'application/json'}),
        };
      }));
      expect((await api.dhikrAudio('takbeer'))[44], 3);
      expect((await api.turnSpeechPart('turn-1', 2))[44], 4);
      await expectLater(
          api.duaAudio('dua-sleep'), throwsA(isA<DemoApiException>()));
      await expectLater(
          api.feedbackAudio('all_clear_1'), throwsA(isA<DemoApiException>()));
      api.close();
    });

    test('speech outages read gently, and other errors stay generic', () async {
      const generic = 'The service could not finish this request.';
      for (final (status, code, message, passed) in [
        (
          503,
          'speech_unavailable',
          DemoApi.knownErrors['speech_unavailable'],
          true
        ),
        (503, 'speech_busy', DemoApi.knownErrors['speech_busy'], true),
        (404, 'speech_disabled', DemoApi.knownErrors['speech_disabled'], true),
        (404, 'item_not_found', DemoApi.knownErrors['item_not_found'], true),
        (
          409,
          'request_in_progress',
          DemoApi.knownErrors['request_in_progress'],
          true
        ),
        (422, 'invalid_request', generic, true),
        (503, 'something_private', generic, false),
      ]) {
        final api = DemoApi(config,
            client: MockClient((_) async => errorResponse(status, code)));
        await expectLater(
            api.practise(
                itemId: 'takbeer',
                segment: 0,
                attempt: 1,
                wav: markedWav(1),
                key: 'k'),
            throwsA(isA<DemoApiException>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.code, 'code', passed ? code : isNull)));
        api.close();
      }
    });

    test('the game: a round, then an attempt on it', () async {
      final requests = <http.Request>[];
      final api = DemoApi(config, client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/v1/games/dhikr/rounds') {
          return jsonResponse(round());
        }
        return jsonResponse({
          'attempt': practiceResult(outcome: 'clear'),
          'round':
              round(attempts: 1, counted: 1, complete: true, starAwarded: true),
          'balance': 6,
        });
      }));
      final started = await api.startDhikrRound('takbeer', 'round-key');
      expect(jsonDecode(requests.first.body), {'dhikrId': 'takbeer'});
      expect(requests.first.headers['Idempotency-Key'], 'round-key');
      final attempt =
          await api.dhikrAttempt(started.roundId, markedWav(1), 'attempt-key');
      expect(requests.last.url.path, '/v1/games/dhikr/rounds/round-1/attempts');
      expect(requests.last.headers['Content-Type'], 'audio/wav');
      expect(attempt.round.starAwarded, isTrue);
      expect(attempt.balance, 6);
      await expectLater(api.startDhikrRound('tasbeeh', 'other-key'),
          throwsA(isA<DemoApiException>()),
          reason: 'a round for another dhikr is not this one');
      api.close();
    });

    test('Robert’s voice is asked for with a key and read back', () async {
      final requests = <http.Request>[];
      final api = DemoApi(config, client: MockClient((request) async {
        requests.add(request);
        return jsonResponse({'status': 'pending', 'parts': [], 'reason': null},
            status: request.method == 'POST' ? 202 : 200);
      }));
      await api.requestTurnSpeech('turn-1', 'speech-key');
      await api.turnSpeech('turn-1');
      expect(requests.map((r) => '${r.method} ${r.url.path}'),
          ['POST /v1/turns/turn-1/speech', 'GET /v1/turns/turn-1/speech']);
      expect(requests.first.headers['Idempotency-Key'], 'speech-key');
      expect(requests.first.bodyBytes, isEmpty,
          reason: 'the route has no body');
      api.close();
    });
  });
}
