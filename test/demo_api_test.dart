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
