import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

void main() {
  group('DemoConfig', () {
    bool enabled(String url) => DemoConfig(baseUrl: url, token: 't').enabled;

    test('plain http only reaches this device or a private network', () {
      for (final url in [
        'http://localhost:8000',
        'http://127.0.0.1:8000',
        'http://10.0.2.2:8000',
        'http://192.168.1.20:8000',
        'http://172.16.0.5:8000/',
        'http://172.31.255.255:8000',
      ]) {
        expect(enabled(url), isTrue, reason: url);
      }
      for (final url in [
        'http://8.8.8.8:8000',
        'http://172.32.0.1:8000',
        'http://172.15.0.1:8000',
        'http://192.169.0.1:8000',
        'http://example.com:8000',
        'http://192.168.1.20.example.com',
        'http://010.0.0.1:8000',
        'http://192.168.1:8000',
        'http://[::1]:8000',
      ]) {
        expect(enabled(url), isFalse, reason: url);
      }
    });

    test('https reaches any host', () {
      expect(enabled('https://demo.example.org'), isTrue);
    });

    test('a token is required and the address carries nothing else', () {
      expect(
          const DemoConfig(baseUrl: 'http://10.0.0.2:8000').enabled, isFalse);
      expect(enabled('http://user@10.0.0.2:8000'), isFalse);
      expect(enabled('http://10.0.0.2:8000/api'), isFalse);
      expect(enabled('http://10.0.0.2:8000/?token=x'), isFalse);
      expect(enabled('ftp://10.0.0.2'), isFalse);
    });
  });

  group('connectTo', () {
    const bootstrap = {
      'mode': 'development',
      'characterId': 'robert',
      'profileId': 'demo-child',
      'contentStatus': 'awaiting_review',
      'features': {'voice': false, 'generativeAnswers': false, 'unity': false},
    };

    test('an entered service is used for every request', () async {
      final seen = <Uri>[];
      final tokens = <String?>{};
      final api =
          DemoApi(const DemoConfig(), client: MockClient((request) async {
        seen.add(request.url);
        tokens.add(request.headers['X-Demo-Token']);
        return switch (request.url.path) {
          '/v1/bootstrap' => _json(bootstrap),
          '/v1/rewards' => _json({'balance': 0, 'unit': 'learning_stars'}),
          _ => _json({'items': []}),
        };
      }));
      final model = CompanionController(api);
      await model.connectTo(const DemoConfig(
          baseUrl: 'http://192.168.1.20:8000', token: 'entered-token'));
      expect(model.connected, isTrue);
      expect(seen, isNotEmpty);
      expect(seen.every((uri) => uri.host == '192.168.1.20'), isTrue);
      expect(tokens, {'entered-token'});
      model.dispose();
    });

    test('a public http address is refused before any request', () async {
      var requests = 0;
      final api = DemoApi(const DemoConfig(), client: MockClient((_) async {
        requests++;
        return _json(bootstrap);
      }));
      final model = CompanionController(api);
      await model.connectTo(
          const DemoConfig(baseUrl: 'http://8.8.8.8:8000', token: 'token'));
      expect(requests, 0);
      expect(model.connected, isFalse);
      expect(model.api.config.enabled, isFalse);
      expect(model.notice, contains('private network'));
      model.dispose();
    });
  });

  testWidgets('the parent area connects to an entered service', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hosts = <String>{};
    final model = CompanionController(
        DemoApi(const DemoConfig(), client: MockClient((request) async {
      hosts.add(request.url.host);
      return switch (request.url.path) {
        '/v1/bootstrap' => _json({
            'mode': 'development',
            'characterId': 'robert',
            'profileId': 'demo-child',
            'contentStatus': 'awaiting_review',
            'features': {
              'voice': false,
              'generativeAnswers': false,
              'unity': false
            },
          }),
        '/v1/rewards' => _json({'balance': 0, 'unit': 'learning_stars'}),
        _ => _json({'items': []}),
      };
    })));
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Parent area'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('service-address')), 'http://192.168.1.20:8000');
    await tester.enterText(
        find.byKey(const Key('service-token')), 'entered-token');
    await tester.ensureVisible(find.byKey(const Key('service-connect')));
    await tester.tap(find.byKey(const Key('service-connect')));
    await tester.pumpAndSettle();

    expect(model.connected, isTrue);
    expect(hosts, {'192.168.1.20'});
    // Once connected the form goes; switching services needs a relaunch.
    expect(find.byKey(const Key('service-address')), findsNothing);
    expect(find.text('Development service connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
