import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config =
      DemoConfig(baseUrl: 'http://localhost:8000', token: 'synthetic-token');

  test('unconfigured client cannot transmit', () async {
    var sent = false;
    final api = DemoApi(const DemoConfig(), client: MockClient((_) async {
      sent = true;
      return http.Response('{}', 200);
    }));
    await expectLater(api.rewards(), throwsA(isA<DemoApiException>()));
    expect(sent, isFalse);
    api.close();
  });

  test('rejects invalid configuration and embedded credentials', () {
    expect(const DemoConfig(baseUrl: 'file:///tmp', token: 'test').enabled,
        isFalse);
    expect(
        const DemoConfig(baseUrl: 'http://user:secret@localhost', token: 'test')
            .enabled,
        isFalse);
    expect(
        const DemoConfig(baseUrl: 'http://localhost?token=x', token: 'test')
            .enabled,
        isFalse);
    expect(config.enabled, isTrue);
  });

  test('completion retry preserves idempotency key and never supplies rewards',
      () async {
    final requests = <http.Request>[];
    final api = DemoApi(config, client: MockClient((request) async {
      requests.add(request);
      return http.Response('{"completed":true}', 200);
    }));
    await api.completeLesson('stable-key-123');
    await api.completeLesson('stable-key-123');
    expect(requests.map((r) => r.headers['Idempotency-Key']),
        everyElement('stable-key-123'));
    expect(requests.first.headers['X-Demo-Token'], 'synthetic-token');
    expect(jsonDecode(requests.first.body), isEmpty);
    expect(requests.first.url.path, '/v1/lessons/demo-learning/complete');
    api.close();
  });

  test('does not equip an item without confirmed server ownership', () async {
    var writes = 0;
    final api = DemoApi(config, client: MockClient((request) async {
      if (request.method != 'GET') writes++;
      return http.Response('{"items":[{"id":"sunset","owned":false}]}', 200);
    }));
    await expectLater(api.equipCosmetic('sunset', 'equipment-key-123'),
        throwsA(isA<DemoApiException>()));
    expect(writes, 0);
    api.close();
  });

  test('a claim the service does not confirm is a failure, not a look',
      () async {
    final api = DemoApi(config,
        client: MockClient((_) async =>
            // Right shape, wrong look: answering about another id must never
            // be read as this one having been earned.
            http.Response(
                '{"cosmeticId":"dune","owned":true,"spent":0,'
                '"balance":40}',
                200)));
    await expectLater(api.claimCosmetic('sunset', 'claim-key-123'),
        throwsA(isA<DemoApiException>()));
    api.close();
  });

  group('bootstrap', () {
    Map<String, dynamic> development({Map<String, Object?>? features}) => {
          'mode': 'development',
          'characterId': 'robert',
          'profileId': 'demo-child',
          'contentStatus': 'awaiting_review',
          'features': features ??
              {'voice': false, 'generativeAnswers': false, 'unity': false},
        };

    DemoApi serving(Map<String, dynamic> payload) => DemoApi(config,
        client:
            MockClient((_) async => http.Response(jsonEncode(payload), 200)));

    test('reports whether the service has grounded answers on', () async {
      for (final grounded in [true, false]) {
        final api = serving(development(features: {
          'voice': false,
          'generativeAnswers': grounded,
          'unity': false,
        }));
        expect(await api.bootstrap(), grounded);
        api.close();
      }
    });

    final refused = <String, Map<String, dynamic>>{
      'voice switched on': development(features: {
        'voice': true,
        'generativeAnswers': true,
        'unity': false,
      }),
      'voice missing': development(features: {'generativeAnswers': true}),
      'grounded answers as a string': development(features: {
        'voice': false,
        'generativeAnswers': 'true',
        'unity': false,
      }),
      'grounded answers missing': development(features: {'voice': false}),
      'features that are not an object': {
        ...development(),
        'features': ['voice'],
      },
      'another mode': {...development(), 'mode': 'production'},
      'another character': {...development(), 'characterId': 'someone'},
      'another profile': {...development(), 'profileId': 'real-child'},
      'reviewed content': {...development(), 'contentStatus': 'published'},
    };
    for (final entry in refused.entries) {
      test('refuses a service with ${entry.key}', () async {
        final api = serving(entry.value);
        await expectLater(
            api.bootstrap(),
            throwsA(isA<DemoApiException>().having((error) => error.message,
                'message', 'This app requires the development-only service.')));
        api.close();
      });
    }
  });

  test('server error bodies are never surfaced', () async {
    final api = DemoApi(config,
        client: MockClient((_) async =>
            http.Response('private payload and credentials', 500)));
    try {
      await api.rewards();
      fail('Expected service failure');
    } on DemoApiException catch (error) {
      expect(error.message, isNot(contains('private')));
    }
    api.close();
  });
}
