import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/domain/models.dart';
import 'package:companion_mobile/domain/speech_models.dart';
import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/speech/robert_voice.dart';
import 'package:companion_mobile/speech/voice_capture.dart';
import 'package:companion_mobile/speech/voice_kit.dart';
import 'package:companion_mobile/speech/wav.dart';
import 'package:companion_mobile/ui/dhikr_game_page.dart';
import 'package:companion_mobile/ui/duas_page.dart';
import 'package:companion_mobile/ui/talk_page.dart';
import 'package:companion_mobile/ui/voice_widgets.dart';
import 'package:companion_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_unity_host.dart';
import 'fake_voice.dart';

/// The speech preview in the app, with a fake microphone, a fake player and
/// a scripted service. None of it proves anything about a phone's audio.

const _config =
    DemoConfig(baseUrl: 'http://localhost:8000', token: 'synthetic-token');

const _preview = SpeechFeatures(
    preview: true,
    recitation: true,
    voiceQuestions: true,
    robertVoice: true,
    maxRecordingSeconds: 15);

const _listen = 'Listen · استمع';
const _micSwitch = 'Microphone (hold to talk)';
const _writing = 'Writing down what you said…';

/// A connected controller over [handler], with the preview's switches and a
/// reply Robert can read aloud.
CompanionController _connected(
  Future<http.Response> Function(http.Request request) handler, {
  SpeechFeatures speech = _preview,
  Reply? reply = const Reply(
      type: ReplyType.chat, text: 'Hi! What shall we learn?', turnId: 'turn-1'),
}) =>
    CompanionController(DemoApi(_config, client: MockClient(handler)),
        wait: (_) => Completer<void>().future)
      ..connected = true
      ..speech = speech
      ..balance = 5
      ..reply = reply;

VoiceKit _kit({
  FakeRecorder? recorder,
  FakePlayback? playback,
  bool built = true,
  Future<void> Function(Duration)? wait,
  DateTime Function()? now,
}) {
  final mic = recorder ?? FakeRecorder();
  final player = playback ?? FakePlayback();
  return VoiceKit(
      built: built,
      recorder: () => mic,
      playback: () => player,
      wait: wait,
      now: now);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump();
  }
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// Opens the parent area from a page that has the header, and returns the
/// microphone switch, or nothing when it is not offered.
Future<Finder> _openParentArea(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Parent area'));
  await tester.pumpAndSettle();
  return find.widgetWithText(SwitchListTile, _micSwitch);
}

Future<void> _closeParentArea(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Back to preview'));
  await tester.tap(find.text('Back to preview'));
  await tester.pumpAndSettle();
}

/// A parent turns the microphone on, from Learn, and comes back to [tab].
Future<void> _microphoneOn(WidgetTester tester, {String tab = 'Talk'}) async {
  await tester.tap(_tab('Learn'));
  await tester.pumpAndSettle();
  final toggle = await _openParentArea(tester);
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  await _closeParentArea(tester);
  await tester.tap(_tab(tab));
  await tester.pumpAndSettle();
}

/// Holds the button found by [button], lets [during] run, and lets go.
Future<TestGesture> _press(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  final gesture = await tester.startGesture(tester.getCenter(button));
  await _flush(tester);
  return gesture;
}

Future<void> _say(WidgetTester tester, FakeRecorder recorder, Finder button,
    {num seconds = 1}) async {
  final gesture = await _press(tester, button);
  recorder.speakSeconds(seconds);
  await tester.pump(const Duration(seconds: 1));
  await gesture.up();
  await _flush(tester);
}

final _mic = find.byType(HoldToTalkButton);

/// The service's refresh after a star, as the controller reads it.
http.Response? _progress(http.Request request, int balance) =>
    switch (request.url.path) {
      '/v1/lessons' => jsonResponse({'items': []}),
      '/v1/rewards' =>
        jsonResponse({'balance': balance, 'unit': 'learning_stars'}),
      '/v1/challenges/today' => jsonResponse({'items': []}),
      '/v1/inventory' => jsonResponse({'items': []}),
      _ => null,
    };

void main() {
  group('switches', () {
    for (final built in [true, false]) {
      testWidgets(
          'the build switch ${built ? 'keeps' : 'removes'} every speech '
          'control', (tester) async {
        _phone(tester);
        final recorder = FakeRecorder();
        final model =
            _connected((_) async => http.Response('{}', 404), speech: _preview);
        await tester.pumpWidget(CompanionApp(
            controller: model, voice: _kit(recorder: recorder, built: built)));
        await tester.pumpAndSettle();

        expect(find.text(_listen), built ? findsOneWidget : findsNothing,
            reason: 'listening needs no parent switch');
        expect(_mic, findsNothing, reason: 'the microphone is off at start');

        await tester.tap(_tab('Learn'));
        await tester.pumpAndSettle();
        expect(
            find.text('Adhkar · أذكار'), built ? findsOneWidget : findsNothing);
        expect(
            find.text('Duas · أدعية'), built ? findsOneWidget : findsNothing);
        await tester.tap(_tab('Quests'));
        await tester.pumpAndSettle();
        expect(find.text('Dhikr game · لعبة الذكر'),
            built ? findsOneWidget : findsNothing);

        final toggle = await _openParentArea(tester);
        if (built) {
          expect(tester.widget<SwitchListTile>(toggle).value, isFalse,
              reason: 'off at every start');
          expect(find.text('Voice is off'), findsNothing);
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        } else {
          expect(toggle, findsNothing);
          expect(find.text('Voice is off'), findsOneWidget);
        }
        await _closeParentArea(tester);
        await tester.tap(_tab('Talk'));
        await tester.pumpAndSettle();
        expect(_mic, built ? findsOneWidget : findsNothing);
        expect(recorder.permissionAsks, 0,
            reason: 'showing the button asks for nothing');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      });
    }

    testWidgets('a service without the preview shows none of it',
        (tester) async {
      _phone(tester);
      final model = _connected((_) async => http.Response('{}', 404),
          speech: SpeechFeatures.off);
      await tester.pumpWidget(CompanionApp(controller: model, voice: _kit()));
      await tester.pumpAndSettle();
      expect(find.text(_listen), findsNothing);
      await tester.tap(_tab('Learn'));
      await tester.pumpAndSettle();
      expect(find.text('Adhkar · أذكار'), findsNothing);
      expect(await _openParentArea(tester), findsNothing);
      expect(find.text('Voice is off'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('the parent switch is off again after a restart',
        (tester) async {
      _phone(tester);
      for (var start = 0; start < 2; start++) {
        final model = _connected((_) async => http.Response('{}', 404));
        await tester.pumpWidget(CompanionApp(
            key: ValueKey(start), controller: model, voice: _kit()));
        await tester.pumpAndSettle();
        await tester.tap(_tab('Learn'));
        await tester.pumpAndSettle();
        final toggle = await _openParentArea(tester);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await _closeParentArea(tester);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      }
    });
  });

  group('asking out loud', () {
    testWidgets('a refused permission records and sends nothing',
        (tester) async {
      _phone(tester);
      var requests = 0;
      final recorder = FakeRecorder(allow: false);
      final model = _connected((_) async {
        requests++;
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);

      final gesture = await _press(tester, _mic);
      await gesture.up();
      await _flush(tester);
      expect(recorder.permissionAsks, 1);
      expect(recorder.starts, 0);
      expect(find.text(VoiceCapture.permissionRefused), findsOneWidget);
      expect(requests, 0);
      // Typing still works.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'holding shows Listening with the seconds, and what was heard goes '
        'into the composer to check and send', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final requests = <http.Request>[];
      final model = _connected((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/v1/speech/transcriptions' =>
            jsonResponse({'status': 'transcribed', 'text': 'كيف أكسب النجوم؟'}),
          '/v1/conversations' => jsonResponse({'conversationId': 'c-1'}),
          '/v1/conversations/c-1/turns' =>
            jsonResponse({'turnId': 'turn-2', 'status': 'pending'}),
          _ => http.Response('{}', 404),
        };
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);

      final gesture = await _press(tester, _mic);
      expect(recorder.recording, isTrue);
      expect(find.text('Listening… 0 s · أستمع'), findsOneWidget);
      recorder.speakSeconds(1);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Listening… 1 s · أستمع'), findsOneWidget);
      recorder.speakSeconds(0.5);
      await tester.pump();
      await gesture.up();
      await _flush(tester);

      expect(recorder.recording, isFalse);
      expect(find.textContaining('Listening…'), findsNothing);
      final sent = requests.single;
      expect(sent.url.path, '/v1/speech/transcriptions');
      expect(sent.url.queryParameters, {'language': 'ar'});
      expect(sent.headers['Content-Type'], 'audio/wav');
      expect(sent.bodyBytes.length, wavHeaderBytes + 48000);
      expect(ascii.decode(sent.bodyBytes.sublist(0, 4)), 'RIFF');
      // Into the composer, and nowhere else until the child sends it.
      expect(find.text('كيف أكسب النجوم؟'), findsOneWidget);
      expect(
          find.text(
              'Check the words, then send them. · تأكّد من الكلمات ثم أرسلها'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Send test question'));
      await _flush(tester);
      expect(requests.map((r) => r.url.path), [
        '/v1/speech/transcriptions',
        '/v1/conversations',
        '/v1/conversations/c-1/turns',
      ]);
      expect(jsonDecode(requests.last.body), {'text': 'كيف أكسب النجوم؟'});
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('English can be chosen before speaking', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      String? language;
      final model = _connected((request) async {
        language = request.url.queryParameters['language'];
        return jsonResponse({'status': 'transcribed', 'text': 'Hello Robert'});
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);
      await tester.tap(find.text('ع'));
      await tester.pump();
      await _say(tester, recorder, _mic);
      expect(language, 'en');
      expect(find.text('Hello Robert'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('an unsure transcript is said gently and fills nothing',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final model = _connected(
          (_) async => jsonResponse({'status': 'unsure', 'text': null}));
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);
      await _say(tester, recorder, _mic);
      expect(
          find.text('I didn’t catch that. Try again or type it. · '
              'لم أسمعك جيدًا، جرّب مرة أخرى أو اكتبها'),
          findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'a recording stops at the service’s bound, and a tap sends '
        'nothing', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final sizes = <int>[];
      final model = _connected((request) async {
        sizes.add(request.bodyBytes.length);
        return jsonResponse({'status': 'unsure', 'text': null});
      },
          speech: const SpeechFeatures(
              preview: true, voiceQuestions: true, maxRecordingSeconds: 2));
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);

      // A tap: too short to be a question.
      var gesture = await _press(tester, _mic);
      recorder.speakSeconds(0.1);
      await tester.pump();
      await gesture.up();
      await _flush(tester);
      expect(sizes, isEmpty);
      expect(find.text(VoiceCapture.holdLonger), findsOneWidget);

      // Held past the bound: it ends by itself and is sent while still held.
      gesture = await _press(tester, _mic);
      for (var second = 0; second < 3; second++) {
        recorder.speakSeconds(1);
        await tester.pump(const Duration(seconds: 1));
      }
      await _flush(tester);
      expect(recorder.recording, isFalse);
      expect(sizes, [wavHeaderBytes + 2 * recordingBytesPerSecond]);
      await gesture.up();
      await _flush(tester);
      expect(sizes, hasLength(1), reason: 'letting go sends nothing more');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('leaving the app drops the recording unsent', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var sent = 0;
      final model = _connected((_) async {
        sent++;
        return jsonResponse({'status': 'unsure', 'text': null});
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);

      final gesture = await _press(tester, _mic);
      recorder.speakSeconds(1);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _flush(tester);
      expect(recorder.recording, isFalse);
      expect(find.textContaining('Listening…'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await gesture.up();
      await _flush(tester);
      expect(sent, 0);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    for (final allow in [false, true]) {
      testWidgets(
          'Android’s permission prompt (the app inactive, the touch taken) '
          '${allow ? 'ends in "now hold to talk"' : 'still says it was refused'}',
          (tester) async {
        _phone(tester);
        final answered = Completer<void>();
        final recorder = FakeRecorder(allow: allow)
          ..whileAsking = () async {
            // The prompt is an activity of its own over the app.
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            await answered.future;
          };
        var requests = 0;
        final model = _connected((_) async {
          requests++;
          return jsonResponse({'status': 'transcribed', 'text': 'مرحبا'});
        });
        await tester.pumpWidget(
            CompanionApp(controller: model, voice: _kit(recorder: recorder)));
        await tester.pumpAndSettle();
        await _microphoneOn(tester);

        final gesture = await _press(tester, _mic);
        await gesture.cancel();
        await _flush(tester);
        answered.complete();
        await _flush(tester);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _flush(tester);

        expect(recorder.permissionAsks, 1);
        expect(recorder.starts, 0, reason: 'the finger left with the prompt');
        expect(find.text(VoiceCapture.permissionRefused),
            allow ? findsNothing : findsOneWidget);
        expect(find.text(VoiceCapture.nowHold),
            allow ? findsOneWidget : findsNothing);
        expect(requests, 0);
        if (allow) {
          recorder.whileAsking = null;
          await _say(tester, recorder, _mic);
          expect(requests, 1, reason: 'the next hold records');
          expect(find.text('مرحبا'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      });
    }

    testWidgets(
        'what is heard after leaving Talk is dropped, not put in the '
        'composer', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final heard = Completer<http.Response>();
      final model = _connected((request) async =>
          request.url.path == '/v1/speech/transcriptions'
              ? heard.future
              : http.Response('{}', 404));
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester);
      await _say(tester, recorder, _mic);
      expect(find.text(_writing), findsOneWidget);

      await tester.tap(_tab('Learn'));
      await tester.pumpAndSettle();
      heard.complete(
          jsonResponse({'status': 'transcribed', 'text': 'سؤال قديم'}));
      await _flush(tester);
      await tester.tap(_tab('Talk'));
      await tester.pumpAndSettle();

      expect(find.text('سؤال قديم'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      expect(find.text(_writing), findsNothing);
      expect(tester.widget<HoldToTalkButton>(_mic).enabled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('leaving the app while the permission is asked ends the press',
        (tester) async {
      final recorder = FakeRecorder()
        ..whileAsking = () async {
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
        };
      var sent = 0;
      final capture = VoiceCapture(
          recorder: () => recorder,
          maxSeconds: 15,
          onRecorded: (_) async => sent++);
      unawaited(capture.press());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(capture.state, CaptureState.idle);
      expect(recorder.starts, 0);
      expect(capture.problem, isNull);
      expect(sent, 0);
      capture.dispose();
    });

    testWidgets('a recording is bounded to 1 MB with its header',
        (tester) async {
      final recorder = FakeRecorder();
      Uint8List? sent;
      final capture = VoiceCapture(
          recorder: () => recorder,
          maxSeconds: 60,
          onRecorded: (wav) async => sent = Uint8List.fromList(wav));
      expect(capture.maxPcmBytes, DemoApi.maxAudioBytes - wavHeaderBytes);
      unawaited(capture.press());
      await tester.pump();
      expect(capture.listening, isTrue);
      recorder.speak(700000);
      recorder.speak(700000);
      await tester.pump();
      await tester.pump();
      expect(capture.listening, isFalse);
      expect(sent!.length, DemoApi.maxAudioBytes);
      capture.dispose();
    });
  });

  testWidgets('the composer with its microphone fits the smallest screen',
      (tester) async {
    _phone(tester);
    final recorder = FakeRecorder();
    final model = _connected((_) async => http.Response('{}', 404));
    await tester.pumpWidget(
        CompanionApp(controller: model, voice: _kit(recorder: recorder)));
    await tester.pumpAndSettle();
    await _microphoneOn(tester);
    tester.view.physicalSize = const Size(320, 380);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_mic, findsOneWidget);
    final gesture = await _press(tester, _mic);
    recorder.speakSeconds(1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Listening…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await gesture.up();
    await _flush(tester);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  group('Robert’s voice', () {
    testWidgets(
        'Listen waits while the voice is made and plays the parts in order, '
        'with the talk cue', (tester) async {
      _phone(tester);
      final host = FakeUnityHost('test/voice_listen')..install();
      addTearDown(host.remove);
      final room = AvatarRoom(
        commands: host.commands,
        create: () => AvatarBridge(
            commands: host.commands,
            events: host.events,
            timeout: const Duration(seconds: 30)),
      );
      addTearDown(room.dispose);
      final playback = FakePlayback(hold: true);
      final gates = <Completer<void>>[];
      final requests = <String>[];
      var reads = 0;
      final model = _connected((request) async {
        requests.add('${request.method} ${request.url.path}');
        switch (request.url.path) {
          case '/v1/turns/turn-1/speech':
            if (request.method == 'POST') {
              expect(request.headers['Idempotency-Key'], isNotNull);
              return jsonResponse({
                'status': 'pending',
                'parts': [
                  {'index': 0, 'ready': false},
                  {'index': 1, 'ready': false},
                ],
                'reason': null,
              }, status: 202);
            }
            reads++;
            return jsonResponse({
              'status': reads == 1 ? 'pending' : 'ready',
              'parts': [
                {'index': 0, 'ready': true},
                {'index': 1, 'ready': reads > 1},
              ],
              'reason': null,
            });
          case '/v1/turns/turn-1/speech/parts/0':
            return wavResponse(10);
          case '/v1/turns/turn-1/speech/parts/1':
            return wavResponse(11);
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(CompanionApp(
          controller: model,
          room: room,
          voice: _kit(
              playback: playback,
              wait: (_) {
                final gate = Completer<void>();
                gates.add(gate);
                return gate.future;
              })));
      await tester.pumpAndSettle();
      await _flush(tester);

      await tester.tap(find.text(_listen));
      await _flush(tester);
      expect(find.text(TalkPage.preparingCopy), findsOneWidget);
      expect(requests, ['POST /v1/turns/turn-1/speech']);
      expect(gates, hasLength(1));
      expect(host.cues.where((cue) => cue == 'Talk'), isEmpty);

      gates.first.complete();
      await _flush(tester);
      expect(playback.played, [10]);
      expect(find.text(TalkPage.speakingCopy), findsOneWidget);
      expect(host.cues.last, 'Talk', reason: 'Robert talks while it plays');

      playback.finish();
      await _flush(tester);
      expect(host.cues.last, 'Standing');
      expect(find.text(TalkPage.preparingCopy), findsOneWidget,
          reason: 'the second part is still being made');
      expect(gates, hasLength(2));

      gates.last.complete();
      await _flush(tester);
      expect(playback.played, [10, 11]);
      playback.finish();
      await _flush(tester);
      expect(requests, [
        'POST /v1/turns/turn-1/speech',
        'GET /v1/turns/turn-1/speech',
        'GET /v1/turns/turn-1/speech/parts/0',
        'GET /v1/turns/turn-1/speech',
        'GET /v1/turns/turn-1/speech/parts/1',
      ]);
      expect(find.text(_listen), findsOneWidget, reason: 'ready to replay');
      expect(host.cues.last, 'Standing');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('Listen gives up after five minutes of waiting',
        (tester) async {
      _phone(tester);
      var clock = DateTime(2026, 10, 6, 9);
      var reads = 0;
      final model = _connected((request) async {
        if (request.method == 'GET') reads++;
        return jsonResponse({'status': 'pending', 'parts': [], 'reason': null},
            status: request.method == 'POST' ? 202 : 200);
      });
      await tester.pumpWidget(CompanionApp(
          controller: model,
          voice: _kit(
              wait: (interval) async {
                expect(interval, const Duration(seconds: 2));
                clock = clock.add(interval);
              },
              now: () => clock)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_listen));
      for (var i = 0; i < 40; i++) {
        await _flush(tester);
      }
      expect(reads, 150, reason: 'every 2 s for 5 minutes');
      expect(find.text(RobertVoice.slowCopy), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('a reply with no voice says so', (tester) async {
      _phone(tester);
      final model = _connected((request) async => jsonResponse(
          {'status': 'unavailable', 'parts': [], 'reason': 'no_text'},
          status: 202));
      await tester.pumpWidget(CompanionApp(controller: model, voice: _kit()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_listen));
      await _flush(tester);
      expect(find.text(TalkPage.unavailableCopy), findsOneWidget);
      expect(find.text('no_text'), findsNothing,
          reason: 'the service’s reason is never shown');
      expect(find.text(_listen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'parts the service dropped, or lost since, are skipped and the rest '
        'play in order', (tester) async {
      _phone(tester);
      final playback = FakePlayback();
      final model = _connected((request) async => switch (request.url.path) {
            '/v1/turns/turn-1/speech' => jsonResponse({
                'status': 'ready',
                'parts': [
                  {'index': 0, 'ready': true},
                  {'index': 2, 'ready': true},
                  {'index': 4, 'ready': true},
                ],
                'reason': null,
              }, status: 202),
            '/v1/turns/turn-1/speech/parts/0' => wavResponse(20),
            '/v1/turns/turn-1/speech/parts/2' =>
              errorResponse(404, 'audio_not_found'),
            '/v1/turns/turn-1/speech/parts/4' => wavResponse(24),
            _ => http.Response('{}', 404),
          });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(playback: playback)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_listen));
      await _flush(tester);
      expect(playback.played, [20, 24]);
      expect(find.text(_listen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('a turn the service no longer knows has no voice',
        (tester) async {
      _phone(tester);
      final model = _connected((_) async => errorResponse(404, 'not_found'));
      await tester.pumpWidget(CompanionApp(controller: model, voice: _kit()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_listen));
      await _flush(tester);
      expect(find.text(TalkPage.unavailableCopy), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('a safeguarding reply is never read aloud', (tester) async {
      _phone(tester);
      final model = _connected((_) async => http.Response('{}', 404),
          reply: const Reply(
              type: ReplyType.safety,
              text: 'You can always talk to a grown-up you trust.',
              turnId: 'turn-1'));
      await tester.pumpWidget(CompanionApp(controller: model, voice: _kit()));
      await tester.pumpAndSettle();
      expect(find.text(_listen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('clearing the reply stops Robert’s voice', (tester) async {
      _phone(tester);
      final playback = FakePlayback(hold: true);
      final model = _connected((request) async {
        if (request.url.path == '/v1/turns/turn-1/speech/parts/0') {
          return wavResponse(1);
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return jsonResponse({
          'status': 'ready',
          'parts': [
            {'index': 0, 'ready': true}
          ],
          'reason': null,
        });
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(playback: playback)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_listen));
      await _flush(tester);
      expect(playback.playing, isTrue);
      await tester.tap(find.byTooltip('Clear development conversation'));
      await _flush(tester);
      expect(playback.playing, isFalse);
      expect(playback.stops, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  });

  group('Learn', () {
    testWidgets(
        'adhkar: Listen, and practice that shows the service’s words and '
        'feedback', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final playback = FakePlayback();
      final attempts = <Map<String, String>>[];
      final model = _connected((request) async {
        switch (request.url.path) {
          case '/v1/adhkar':
            return jsonResponse(
                {'items': adhkarItems, 'reviewStatus': 'draft'});
          case '/v1/audio/adhkar/takbeer':
            return wavResponse(30);
          case '/v1/audio/feedback/some_unclear':
            return wavResponse(31);
          case '/v1/recitations/attempts':
            attempts.add(request.url.queryParameters);
            expect(request.headers['Idempotency-Key'], isNotNull);
            return jsonResponse(attempts.length == 1
                ? practiceResult(audio: true, words: [
                    {'index': 0, 'state': 'clear'},
                    {'index': 1, 'state': 'try_again'},
                  ])
                : practiceResult(
                    outcome: 'unsure',
                    showWords: false,
                    copyId: 'unsure_1',
                    text: 'لم أسمع جيدًا، هيا نحاول معًا.'));
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(CompanionApp(
          controller: model,
          voice: _kit(recorder: recorder, playback: playback)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester, tab: 'Learn');
      await tester.tap(find.text('Open adhkar'));
      await tester.pumpAndSettle();

      expect(find.text('Takbeer · التكبير'), findsOneWidget);
      expect(find.byType(DraftVoiceNotice), findsOneWidget);
      // Tasbeeh has no voice yet: no Listen for it.
      expect(find.text('Listen'), findsOneWidget);
      await tester.tap(find.text('Listen'));
      await _flush(tester);
      expect(playback.played, [30]);

      await tester.tap(find.text('Practise').first);
      await tester.pumpAndSettle();
      await _say(tester, recorder, _mic);
      expect(attempts.single,
          {'itemId': 'takbeer', 'segment': '0', 'attempt': '1'});
      expect(find.text('جيد، بعض الكلمات تحتاج تمرين.'), findsOneWidget);
      expect(find.text(PracticeWords.clearLabel), findsOneWidget);
      expect(find.text(PracticeWords.practiseLabel), findsOneWidget);
      await tester.tap(find.text('Hear Robert say it'));
      await _flush(tester);
      expect(playback.played, [30, 31]);

      await _say(tester, recorder, _mic);
      expect(attempts.last['attempt'], '2');
      expect(find.text('لم أسمع جيدًا، هيا نحاول معًا.'), findsOneWidget);
      expect(find.text(PracticeWords.clearLabel), findsNothing,
          reason: 'the service hid the words this time');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    /// Opens takbeer's practice with the microphone on, over [handler]'s
    /// attempts.
    Future<CompanionController> openPractice(WidgetTester tester,
        FakeRecorder recorder, Future<http.Response> Function() attempt) async {
      final model = _connected((request) async => switch (request.url.path) {
            '/v1/adhkar' =>
              jsonResponse({'items': adhkarItems, 'reviewStatus': 'draft'}),
            '/v1/recitations/attempts' => attempt(),
            _ => http.Response('{}', 404),
          });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester, tab: 'Learn');
      await tester.tap(find.text('Open adhkar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practise').first);
      await tester.pumpAndSettle();
      return model;
    }

    testWidgets('closing the page mid-recording drops it unsent',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var sent = 0;
      final model = await openPractice(tester, recorder, () async {
        sent++;
        return jsonResponse(practiceResult());
      });
      final gesture = await _press(tester, _mic);
      recorder.speakSeconds(1);
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.recording, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PracticePanel), findsNothing);
      expect(recorder.recording, isFalse);
      await gesture.up();
      await _flush(tester);
      expect(sent, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'closing the page while the microphone is still stopping sends '
        'nothing', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var sent = 0;
      final model = await openPractice(tester, recorder, () async {
        sent++;
        return jsonResponse(practiceResult());
      });
      recorder.stopGate = Completer<void>();
      await _say(tester, recorder, _mic);
      expect(recorder.stops, 1, reason: 'let go: the stop is under way');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PracticePanel), findsNothing);

      recorder.stopGate!.complete();
      await _flush(tester);
      expect(sent, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('closing the page mid-upload drops the late answer',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final answer = Completer<http.Response>();
      final model = await openPractice(tester, recorder, () => answer.future);
      await _say(tester, recorder, _mic);
      expect(find.text(PracticePanel.sendingCopy), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      answer.complete(jsonResponse(practiceResult(text: 'متأخر')));
      await _flush(tester);
      expect(find.text('متأخر'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('an item the service cannot practise says so gently',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final model = await openPractice(
          tester, recorder, () async => errorResponse(404, 'item_not_found'));
      await _say(tester, recorder, _mic);
      expect(find.text(DemoApi.knownErrors['item_not_found']!), findsOneWidget);
      expect(tester.widget<HoldToTalkButton>(_mic).enabled, isTrue,
          reason: 'trying again stays possible');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('adhkar practice without the parent switch only listens',
        (tester) async {
      _phone(tester);
      final model = _connected((request) async =>
          request.url.path == '/v1/adhkar'
              ? jsonResponse({'items': adhkarItems, 'reviewStatus': 'draft'})
              : http.Response('{}', 404));
      final recorder = FakeRecorder();
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Learn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open adhkar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practise').first);
      await tester.pumpAndSettle();
      expect(find.text(MicrophoneOffNote.text), findsOneWidget);
      expect(_mic, findsNothing);
      expect(recorder.permissionAsks, 0);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('duas: the recorded voice slot and practice by part',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final playback = FakePlayback();
      final attempts = <Map<String, String>>[];
      final model = _connected((request) async {
        switch (request.url.path) {
          case '/v1/duas':
            return jsonResponse({
              'items': [
                {
                  'id': 'morning-by-god',
                  'group': 'adhkar',
                  'kind': 'hadith_invocation',
                  'title': 'اللهم بك أصبحنا',
                  'childNote': 'أبدأ صباحي بذكر الله.',
                  'repeat': 1,
                  'occasions': ['morning'],
                  'audio': null,
                  'segments': [
                    {'index': 0, 'text': 'اللهم بك أصبحنا'},
                    {'index': 1, 'text': 'وبك أمسينا'},
                  ],
                },
                {
                  'id': 'dua-parents',
                  'group': 'daily_duas',
                  'kind': 'quran_recitation',
                  'title': 'دعاء الرحمة للوالدين',
                  'childNote': 'أدعو لوالديّ بالرحمة.',
                  'repeat': null,
                  'occasions': ['for_parents'],
                  'audio': 'recorded',
                  'segments': [],
                },
              ],
              'reviewStatus': 'draft',
            });
          case '/v1/audio/duas/dua-parents':
            return wavResponse(40);
          case '/v1/recitations/attempts':
            attempts.add(request.url.queryParameters);
            return jsonResponse(practiceResult(outcome: 'clear', words: [
              {'index': 0, 'state': 'clear'},
            ]));
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(CompanionApp(
          controller: model,
          voice: _kit(recorder: recorder, playback: playback)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester, tab: 'Learn');
      await tester.ensureVisible(find.text('Open duas'));
      await tester.tap(find.text('Open duas'));
      await tester.pumpAndSettle();

      expect(find.text(DuasPage.voiceComing), findsOneWidget);
      expect(find.text(DuasPage.fromQuran), findsOneWidget);
      await tester.ensureVisible(find.text('Listen to the recorded voice'));
      await tester.tap(find.text('Listen to the recorded voice'));
      await _flush(tester);
      expect(playback.played, [40]);

      await tester.ensureVisible(find.text('Practise this part').last);
      await tester.tap(find.text('Practise this part').last);
      await tester.pumpAndSettle();
      await _say(tester, recorder, _mic);
      expect(attempts.single,
          {'itemId': 'morning-by-god', 'segment': '1', 'attempt': '1'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  });

  group('dhikr game', () {
    Map<String, Object?> game({int starsToday = 0}) => {
          'items': [
            {...adhkarItems.first}..remove('transliteration'),
          ],
          'starsPerRound': 1,
          'dailyStarCap': 10,
          'starsToday': starsToday,
        };

    testWidgets(
        'a round runs to three counted tries, earns a star, and the balance '
        'is read again from the service', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final playback = FakePlayback();
      var attempts = 0;
      var rewardReads = 0;
      final model = _connected((request) async {
        if (request.url.path == '/v1/rewards') rewardReads++;
        final progress = _progress(request, 6);
        if (progress != null) return progress;
        switch (request.url.path) {
          case '/v1/games/dhikr':
            return jsonResponse(game(starsToday: attempts >= 4 ? 1 : 0));
          case '/v1/games/dhikr/rounds':
            return jsonResponse(round());
          case '/v1/audio/adhkar/takbeer':
            return wavResponse(50);
          case '/v1/games/dhikr/rounds/round-1/attempts':
            attempts++;
            final counted =
                switch (attempts) { 1 => 1, 2 => 1, 3 => 2, _ => 3 };
            return jsonResponse({
              'attempt': attempts == 2
                  ? practiceResult(
                      outcome: 'unsure',
                      showWords: false,
                      copyId: 'unsure_1',
                      text: 'لم أسمع جيدًا.')
                  : practiceResult(text: 'محاولة رقم $attempts', words: [
                      {'index': 0, 'state': 'clear'}
                    ]),
              'round': round(
                  attempts: attempts,
                  counted: counted,
                  complete: counted == 3,
                  starAwarded: counted == 3),
              'balance': counted == 3 ? 6 : 5,
            });
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(CompanionApp(
          controller: model,
          voice: _kit(recorder: recorder, playback: playback)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester, tab: 'Quests');
      await tester.ensureVisible(find.text('Play the dhikr game'));
      await tester.tap(find.text('Play the dhikr game'));
      await tester.pumpAndSettle();
      expect(find.text(DhikrGamePage.intro), findsOneWidget);
      expect(find.text(DhikrGamePage.starsCollected), findsNothing);

      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      expect(playback.played, [50], reason: 'Robert says it first');
      expect(find.text('Try 1 of 3'), findsOneWidget);

      await _say(tester, recorder, _mic);
      expect(find.text('محاولة رقم 1'), findsOneWidget);
      expect(find.text('Try 2 of 3'), findsOneWidget);

      await _say(tester, recorder, _mic);
      expect(find.text('لم أسمع جيدًا.'), findsOneWidget);
      expect(find.text('Try 2 of 3'), findsOneWidget,
          reason: 'the service did not count an unsure try');

      await _say(tester, recorder, _mic);
      expect(find.text('Try 3 of 3'), findsOneWidget);
      expect(rewardReads, 0);

      await _say(tester, recorder, _mic);
      await tester.pumpAndSettle();
      expect(find.text(DhikrGamePage.starEarned), findsOneWidget);
      expect(find.text(DhikrGamePage.wellDone), findsOneWidget);
      expect(find.text('محاولة رقم 4'), findsOneWidget);
      expect(rewardReads, 1, reason: 'the balance is the service’s');
      expect(find.text('You have 6 learning stars.'), findsOneWidget);
      expect(find.text('Try 3 of 3'), findsNothing);
      expect(_mic, findsNothing);

      await tester.ensureVisible(find.text('See looks in Style'));
      await tester.tap(find.text('See looks in Style'));
      await tester.pumpAndSettle();
      expect(find.text('Robert’s looks'), findsOneWidget);
      expect(
          find.descendant(of: find.byType(StarChip), matching: find.text('6')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'a round that could not start keeps its key for that dhikr only',
        (tester) async {
      _phone(tester);
      final keys = <String, List<String>>{};
      var busy = true;
      final model = _connected((request) async {
        switch (request.url.path) {
          case '/v1/games/dhikr':
            return jsonResponse({
              ...game(),
              'items': [
                for (final item in adhkarItems)
                  {...item}..remove('transliteration'),
              ],
            });
          case '/v1/games/dhikr/rounds':
            final dhikr =
                (jsonDecode(request.body) as Map)['dhikrId'] as String;
            keys
                .putIfAbsent(dhikr, () => [])
                .add(request.headers['Idempotency-Key']!);
            if (busy) return errorResponse(503, 'speech_busy');
            return jsonResponse(round(dhikrId: dhikr));
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(CompanionApp(controller: model, voice: _kit()));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Quests'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play the dhikr game'));
      await tester.tap(find.text('Play the dhikr game'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      expect(find.text(DemoApi.knownErrors['speech_busy']!), findsOneWidget);
      await tester.tap(find.text('Choose another dhikr'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play with Tasbeeh'));
      await tester.tap(find.text('Play with Tasbeeh'));
      await _flush(tester);
      await tester.tap(find.text('Choose another dhikr'));
      await tester.pumpAndSettle();
      busy = false;
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      expect(find.text('Try 1 of 3'), findsOneWidget);
      expect(keys['takbeer'], hasLength(2));
      expect(keys['takbeer']!.toSet(), hasLength(1),
          reason: 'a retry finds the round the lost answer made');
      expect(keys['tasbeeh']!.single, isNot(keys['takbeer']!.first),
          reason: 'another dhikr is another request');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'after the day’s stars, the game says so warmly and still plays',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var rewardReads = 0;
      final model = _connected((request) async {
        if (request.url.path == '/v1/rewards') rewardReads++;
        switch (request.url.path) {
          case '/v1/games/dhikr':
            return jsonResponse(game(starsToday: 10));
          case '/v1/games/dhikr/rounds':
            return jsonResponse(round());
          case '/v1/audio/adhkar/takbeer':
            return wavResponse(50);
          case '/v1/games/dhikr/rounds/round-1/attempts':
            return jsonResponse({
              'attempt': practiceResult(
                  outcome: 'clear',
                  copyId: 'all_clear_1',
                  text: 'ما شاء الله، أحسنت!'),
              'round': round(attempts: 1, counted: 1, complete: true),
              'balance': 5,
            });
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await _microphoneOn(tester, tab: 'Quests');
      await tester.ensureVisible(find.text('Play the dhikr game'));
      await tester.tap(find.text('Play the dhikr game'));
      await tester.pumpAndSettle();
      expect(find.text(DhikrGamePage.starsCollected), findsOneWidget);

      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      await _say(tester, recorder, _mic);
      await tester.pumpAndSettle();
      expect(find.text('ما شاء الله، أحسنت!'), findsOneWidget);
      expect(find.text(DhikrGamePage.lovelyPractice), findsOneWidget);
      expect(find.text(DhikrGamePage.starEarned), findsNothing);
      expect(rewardReads, 0);
      expect(find.text('Play again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    /// Both adhkar, as the game lists them.
    Map<String, Object?> bothAdhkar() => {
          ...game(),
          'items': [
            for (final item in adhkarItems)
              {...item}..remove('transliteration'),
          ],
        };

    Future<void> openGame(WidgetTester tester) async {
      await _microphoneOn(tester, tab: 'Quests');
      await tester.ensureVisible(find.text('Play the dhikr game'));
      await tester.tap(find.text('Play the dhikr game'));
      await tester.pumpAndSettle();
    }

    final choose = find.widgetWithText(TextButton, 'Choose another dhikr');

    testWidgets(
        'a try’s answer stays with its round: choosing another dhikr waits '
        'until it is in', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final tried = <String>[];
      final takbeerAnswer = Completer<http.Response>();
      final model = _connected((request) async {
        final path = request.url.path;
        if (path == '/v1/games/dhikr') return jsonResponse(bothAdhkar());
        if (path == '/v1/games/dhikr/rounds') {
          final dhikr = (jsonDecode(request.body) as Map)['dhikrId'] as String;
          return jsonResponse(round(
              roundId: dhikr == 'takbeer' ? 'round-1' : 'round-2',
              dhikrId: dhikr));
        }
        if (path.endsWith('/attempts')) {
          tried.add(path);
          if (path == '/v1/games/dhikr/rounds/round-1/attempts') {
            return takbeerAnswer.future;
          }
          return jsonResponse({
            'attempt': practiceResult(text: 'تسبيح'),
            'round': round(
                roundId: 'round-2',
                dhikrId: 'tasbeeh',
                attempts: 1,
                counted: 1),
            'balance': 5,
          });
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);

      await _say(tester, recorder, _mic);
      expect(find.text(PracticePanel.sendingCopy), findsOneWidget);
      expect(tester.widget<TextButton>(choose).onPressed, isNull,
          reason: 'the try belongs to this round');
      await tester.tap(choose, warnIfMissed: false);
      await _flush(tester);
      expect(find.text('Try 1 of 3'), findsOneWidget);
      expect(find.text('Play with Tasbeeh'), findsNothing);

      takbeerAnswer.complete(jsonResponse({
        'attempt': practiceResult(text: 'تكبير'),
        'round': round(attempts: 1, counted: 1),
        'balance': 5,
      }));
      await _flush(tester);
      expect(find.text('Try 2 of 3'), findsOneWidget);
      expect(tester.widget<TextButton>(choose).onPressed, isNotNull);

      await tester.tap(choose);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play with Tasbeeh'));
      await tester.tap(find.text('Play with Tasbeeh'));
      await _flush(tester);
      expect(find.text('Tasbeeh · التسبيح'), findsOneWidget);
      expect(find.text('Try 1 of 3'), findsOneWidget);
      await _say(tester, recorder, _mic);
      expect(tried, [
        '/v1/games/dhikr/rounds/round-1/attempts',
        '/v1/games/dhikr/rounds/round-2/attempts',
      ]);
      expect(find.text('Try 2 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'a round that starts after the child chose another dhikr is left, '
        'and Robert does not say it', (tester) async {
      _phone(tester);
      final playback = FakePlayback();
      final started = Completer<http.Response>();
      final model = _connected((request) async => switch (request.url.path) {
            '/v1/games/dhikr' => jsonResponse(bothAdhkar()),
            '/v1/games/dhikr/rounds' => started.future,
            '/v1/audio/adhkar/takbeer' => wavResponse(50),
            _ => http.Response('{}', 404),
          });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(playback: playback)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      await tester.tap(choose);
      await _flush(tester);
      expect(find.text(DhikrGamePage.intro), findsOneWidget);

      started.complete(jsonResponse(round()));
      await _flush(tester);
      expect(playback.played, isEmpty);
      expect(find.text(DhikrGamePage.intro), findsOneWidget);
      expect(find.text('Try 1 of 3'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'a round the service already finished is shown finished, and the '
        'balance is read again', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var rewardReads = 0;
      final model = _connected((request) async {
        if (request.url.path == '/v1/rewards') rewardReads++;
        final progress = _progress(request, 6);
        if (progress != null) return progress;
        return switch (request.url.path) {
          '/v1/games/dhikr' => jsonResponse(game()),
          '/v1/games/dhikr/rounds' => jsonResponse(round()),
          '/v1/games/dhikr/rounds/round-1/attempts' =>
            errorResponse(409, 'round_complete'),
          _ => http.Response('{}', 404),
        };
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      await _say(tester, recorder, _mic);
      await tester.pumpAndSettle();

      expect(find.text(DhikrGamePage.finishedEarlier), findsOneWidget);
      expect(rewardReads, 1, reason: 'its star, if any, is the service’s');
      expect(find.text('You have 6 learning stars.'), findsOneWidget);
      expect(find.text(DhikrGamePage.starEarned), findsNothing,
          reason: 'whether this round gave one is not known here');
      expect(find.text('Play again'), findsOneWidget);
      expect(_mic, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets('a round the service no longer knows offers a new one',
        (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var rounds = 0;
      final model = _connected((request) async {
        switch (request.url.path) {
          case '/v1/games/dhikr':
            return jsonResponse(game());
          case '/v1/games/dhikr/rounds':
            rounds++;
            return jsonResponse(round(roundId: 'round-$rounds'));
          case '/v1/games/dhikr/rounds/round-1/attempts':
            return errorResponse(404, 'round_not_found');
        }
        return http.Response('{}', 404);
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      await _say(tester, recorder, _mic);
      expect(
          find.text(DemoApi.knownErrors['round_not_found']!), findsOneWidget);
      expect(_mic, findsNothing);
      await tester.tap(find.text('Start a new round'));
      await _flush(tester);
      expect(rounds, 2);
      expect(find.text('Try 1 of 3'), findsOneWidget);
      expect(_mic, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'a star’s balance is the service’s own number when the progress '
        'cannot be read again now', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      var rewardReads = 0;
      final model = _connected((request) async {
        if (request.url.path == '/v1/rewards') rewardReads++;
        return switch (request.url.path) {
          '/v1/games/dhikr' => jsonResponse(game()),
          '/v1/games/dhikr/rounds' => jsonResponse(round()),
          '/v1/games/dhikr/rounds/round-1/attempts' => jsonResponse({
              'attempt': practiceResult(outcome: 'clear', text: 'أحسنت!'),
              'round': round(
                  attempts: 1, counted: 1, complete: true, starAwarded: true),
              'balance': 6,
            }),
          _ => http.Response('{}', 404),
        };
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      // Another operation holds the controller, so a refresh does nothing.
      model.busy = true;
      await _say(tester, recorder, _mic);
      await tester.pumpAndSettle();
      expect(find.text(DhikrGamePage.starEarned), findsOneWidget);
      expect(rewardReads, 0);
      expect(find.text('You have 6 learning stars.'), findsOneWidget);
      expect(
          find.descendant(of: find.byType(StarChip), matching: find.text('6')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });

    testWidgets(
        'leaving mid-try drops the late answer, and its star is read again '
        'from the service', (tester) async {
      _phone(tester);
      final recorder = FakeRecorder();
      final answer = Completer<http.Response>();
      var rewardReads = 0;
      final model = _connected((request) async {
        if (request.url.path == '/v1/rewards') rewardReads++;
        final progress = _progress(request, 6);
        if (progress != null) return progress;
        return switch (request.url.path) {
          '/v1/games/dhikr' => jsonResponse(game()),
          '/v1/games/dhikr/rounds' => jsonResponse(round()),
          '/v1/games/dhikr/rounds/round-1/attempts' => answer.future,
          _ => http.Response('{}', 404),
        };
      });
      await tester.pumpWidget(
          CompanionApp(controller: model, voice: _kit(recorder: recorder)));
      await tester.pumpAndSettle();
      await openGame(tester);
      await tester.tap(find.text('Play with Takbeer'));
      await _flush(tester);
      await _say(tester, recorder, _mic);
      expect(find.text(PracticePanel.sendingCopy), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DhikrGamePage), findsNothing);
      answer.complete(jsonResponse({
        'attempt': practiceResult(outcome: 'clear'),
        'round':
            round(attempts: 1, counted: 1, complete: true, starAwarded: true),
        'balance': 6,
      }));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(rewardReads, 1);
      expect(
          find.descendant(of: find.byType(StarChip), matching: find.text('6')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  });
}
