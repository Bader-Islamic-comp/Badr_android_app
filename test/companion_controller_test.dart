import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config = DemoConfig(baseUrl: 'http://localhost:8000', token: 'test');
  const bootstrap = {
    'mode': 'development',
    'characterId': 'robert',
    'profileId': 'demo-child',
    'contentStatus': 'awaiting_review',
    'features': {'voice': false, 'generativeAnswers': false, 'unity': false},
  };
  const lessons = {
    'items': [
      {
        'id': 'demo-learning',
        'title': 'Meet your learning companion',
        'summary': 'Practice using your learning space.',
        'kind': 'orientation',
        'steps': ['Choose a comfortable place to learn.'],
        'reward': 5,
      }
    ]
  };
  const inventory = {'items': <Map<String, Object>>[]};

  test('offline orientation cannot invent a balance or server progress',
      () async {
    final model = CompanionController(DemoApi(const DemoConfig()));
    await model.completeOrientation();
    expect(model.orientationComplete, isTrue);
    expect(model.balance, isNull);
    expect(model.serverChallengeComplete, isFalse);
    model.dispose();
  });

  test('question retry resumes known turn and does not submit twice', () async {
    var submissions = 0;
    var reads = 0;
    final api = DemoApi(config, client: MockClient((request) async {
      final Object result;
      switch (request.url.path) {
        case '/v1/bootstrap':
          result = bootstrap;
        case '/v1/lessons':
          result = lessons;
        case '/v1/inventory':
          result = inventory;
        case '/v1/rewards':
          result = {'balance': 0, 'unit': 'learning_stars'};
        case '/v1/challenges/today':
          result = {'items': []};
        case '/v1/conversations':
          result = {'conversationId': 'conversation-1'};
        case '/v1/conversations/conversation-1/turns':
          submissions++;
          result = {'turnId': 'turn-1', 'status': 'completed'};
        case '/v1/turns/turn-1':
          reads++;
          if (reads == 1) return http.Response('{}', 503);
          result = {
            'turnId': 'turn-1',
            'status': 'completed',
            'text': 'Service unavailable.',
            'citations': []
          };
        default:
          return http.Response('{}', 404);
      }
      return http.Response(jsonEncode(result), 200);
    }));
    final model = CompanionController(api);
    await model.connect();
    await model.ask('Synthetic test');
    expect(model.canRetryQuestion, isTrue);
    await model.ask('Ignored replacement');
    expect(submissions, 1);
    expect(reads, 2);
    expect(model.canRetryQuestion, isFalse);
    expect(model.answer, 'Service unavailable.');
    model.dispose();
  });

  test('connected completion uses refreshed server balance, never local grant',
      () async {
    var completed = false;
    final model =
        CompanionController(DemoApi(config, client: MockClient((request) async {
      if (request.url.path.endsWith('/complete')) {
        completed = true;
        return http.Response(
            '{"lessonId":"demo-learning","completed":true,"earned":5,"balance":5}',
            200);
      }
      if (request.url.path == '/v1/bootstrap') {
        return http.Response(jsonEncode(bootstrap), 200);
      }
      if (request.url.path == '/v1/lessons') {
        return http.Response(jsonEncode(lessons), 200);
      }
      if (request.url.path == '/v1/inventory') {
        return http.Response(jsonEncode(inventory), 200);
      }
      if (request.url.path == '/v1/rewards') {
        return http.Response(
            jsonEncode(
                {'balance': completed ? 17 : 12, 'unit': 'learning_stars'}),
            200);
      }
      return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'demo-practice',
                'title': 'Explore one learning activity',
                'description': 'Complete the orientation with Robert.',
                'completed': completed,
              }
            ]
          }),
          200);
    })));
    await model.connect();
    await model.completeOrientation();
    expect(model.balance, 17);
    expect(model.serverChallengeComplete, isTrue);
    model.dispose();
  });

  test('double completion taps share one in-flight write and failure retry key',
      () async {
    var completions = 0;
    final keys = <String?>[];
    final firstWrite = Completer<http.Response>();
    final firstWriteStarted = Completer<void>();
    final model =
        CompanionController(DemoApi(config, client: MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return http.Response(jsonEncode(bootstrap), 200);
        case '/v1/lessons':
          return http.Response(jsonEncode(lessons), 200);
        case '/v1/inventory':
          return http.Response(jsonEncode(inventory), 200);
        case '/v1/rewards':
          return http.Response('{"balance":0,"unit":"learning_stars"}', 200);
        case '/v1/challenges/today':
          return http.Response('{"items":[]}', 200);
        case '/v1/lessons/demo-learning/complete':
          completions++;
          keys.add(request.headers['Idempotency-Key']);
          if (completions == 1) {
            firstWriteStarted.complete();
            return firstWrite.future;
          }
          return http.Response(
              '{"lessonId":"demo-learning","completed":true}', 200);
        default:
          return http.Response('{}', 404);
      }
    })));
    await model.connect();
    final completion = model.completeOrientation();
    await firstWriteStarted.future;
    await model.completeOrientation();
    expect(completions, 1);
    expect(model.busy, isTrue);
    firstWrite.complete(http.Response('{}', 503));
    await completion;
    expect(model.balance, 0);
    expect(model.serverChallengeComplete, isFalse);
    expect(model.notice, isNotNull);
    await model.completeOrientation();
    expect(completions, 2);
    expect(keys.first, isNotEmpty);
    expect(keys.last, keys.first);
    model.dispose();
  });

  test(
      'failed conversation creation is recovered and deleted before local reset',
      () async {
    var creates = 0;
    var deletes = 0;
    final creationKeys = <String?>[];
    final model =
        CompanionController(DemoApi(config, client: MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return http.Response(jsonEncode(bootstrap), 200);
        case '/v1/lessons':
          return http.Response(jsonEncode(lessons), 200);
        case '/v1/inventory':
          return http.Response(jsonEncode(inventory), 200);
        case '/v1/rewards':
          return http.Response('{"balance":0,"unit":"learning_stars"}', 200);
        case '/v1/challenges/today':
          return http.Response('{"items":[]}', 200);
        case '/v1/conversations':
          creates++;
          creationKeys.add(request.headers['Idempotency-Key']);
          return creates == 1
              ? http.Response('{}', 503)
              : http.Response(
                  '{"conversationId":"recovered-conversation"}', 200);
        case '/v1/conversations/recovered-conversation':
          expect(request.method, 'DELETE');
          deletes++;
          return http.Response('', 204);
        default:
          return http.Response('{}', 404);
      }
    })));
    await model.connect();
    await model.ask('Synthetic test');
    expect(model.canRetryQuestion, isTrue);
    await model.clearConversation();
    expect(creationKeys.last, creationKeys.first);
    expect(deletes, 1);
    expect(model.hasConversation, isFalse);
    expect(model.canRetryQuestion, isFalse);
    model.dispose();
  });
}
