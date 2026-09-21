import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _lessons = {
  'items': [
    {
      'id': 'demo-learning',
      'title': 'Meet your learning companion',
      'summary': 'Practice using your learning space.',
      'kind': 'orientation',
      'steps': [
        'Choose a comfortable place to learn.',
        'Take your time. You can pause whenever you need.',
        'Ask a trusted adult when you need help.',
      ],
      'reward': 5,
    }
  ]
};

Map<String, dynamic> _challenges(bool completed) => {
      'items': [
        {
          'id': 'demo-practice',
          'title': 'Explore one learning activity',
          'description': 'Complete the orientation with Robert.',
          'completed': completed,
          'verification': 'lesson_completion',
        }
      ]
    };

const _inventory = {
  'items': [
    {
      'id': 'default',
      'characterId': 'robert',
      'name': 'Robert Original',
      'owned': true,
      'equipped': true,
    }
  ]
};

void main() {
  testWidgets(
      'missing Unity host preserves offline orientation and honest rewards',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();

    // Character-first main page with no native host: the handshake is honest
    // about looking for a room, then falls back for good once it deadlines.
    expect(find.text('Looking for the character room…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Robert · static preview'), findsOneWidget);
    expect(find.text('Hello, explorer.'), findsOneWidget);
    expect(find.byTooltip('Send test question'), findsOneWidget);

    await tester.ensureVisible(find.text('Let’s explore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Let’s explore'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a comfortable place to learn.'), findsOneWidget);
    // The composer belongs to the character page only.
    expect(find.byTooltip('Send test question'), findsNothing);

    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Finish exploring'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish exploring'));
    await tester.pumpAndSettle();

    expect(find.text('Explored on this device'), findsOneWidget);
    expect(find.text('Connect to view your server-owned demo balance.'),
        findsOneWidget);
    expect(find.text('5 learning stars'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orientation controls expose activatable button semantics',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();

    expect(
        tester.getSemantics(find.bySemanticsLabel('Say hello to Robert')),
        isSemantics(
            isButton: true,
            hasTapAction: true,
            label: 'Say hello to Robert',
            hint: 'Robert gives a short wave or nod'));

    await tester.ensureVisible(find.text('Let’s explore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Let’s explore'));
    await tester.pumpAndSettle();

    // A previous browser check found these controls missing from the
    // accessibility tree; assert role, label, hint and the activation path.
    expect(
        tester.getSemantics(find.text('Next step')),
        isSemantics(
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            label: 'Next step',
            hint: 'Opens orientation step 2'));
    expect(
        tester.getSemantics(find.text('Pause for now')),
        isSemantics(
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            label: 'Pause for now',
            hint: 'Leaves the orientation without losing progress'));
    handle.dispose();
  });

  testWidgets(
      'small viewport and large text remain scrollable without exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    // Readable text and a reachable composer take priority over the character.
    expect(find.byTooltip('Send test question'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Parent area'));
    await tester.pumpAndSettle();
    expect(find.text('Parent area · prototype'), findsOneWidget);
    expect(find.textContaining('not an authenticated parental gate'),
        findsOneWidget);
    expect(find.text('Character motion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit connection displays server stars and saves orientation',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reads = 0;
    var completed = false;
    final model = CompanionController(DemoApi(
      const DemoConfig(
          baseUrl: 'http://localhost:8000', token: 'synthetic-token'),
      client: MockClient((request) async {
        reads++;
        switch (request.url.path) {
          case '/v1/bootstrap':
            return http.Response(
                jsonEncode({
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
                200);
          case '/v1/lessons':
            return http.Response(jsonEncode(_lessons), 200);
          case '/v1/rewards':
            return http.Response(
                jsonEncode(
                    {'balance': completed ? 16 : 11, 'unit': 'learning_stars'}),
                200);
          case '/v1/challenges/today':
            return http.Response(jsonEncode(_challenges(completed)), 200);
          case '/v1/inventory':
            return http.Response(jsonEncode(_inventory), 200);
          case '/v1/lessons/demo-learning/complete':
            completed = true;
            return http.Response(
                '{"lessonId":"demo-learning","completed":true,"balance":16,"earned":5}',
                200);
          default:
            return http.Response('{}', 404);
        }
      }),
    ));
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    expect(reads, 0, reason: 'Even configured builds must connect explicitly.');

    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Connect development service'), 150);
    await tester.tap(find.text('Connect development service'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('11 learning stars'), -150);
    expect(find.text('11 learning stars'), findsOneWidget);

    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start orientation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start orientation'));
    await tester.pumpAndSettle();
    for (var step = 0; step < 2; step++) {
      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Finish exploring'));
    await tester.pumpAndSettle();
    expect(find.text('16 learning stars'), findsOneWidget);
    expect(find.text('Completed · confirmed by the service'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
