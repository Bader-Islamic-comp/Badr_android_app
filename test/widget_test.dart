import 'dart:convert';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/ui/character_stage.dart';
import 'package:companion_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_unity_host.dart';

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
      'description': 'The appearance Robert arrives in.',
      'cost': 0,
      'owned': true,
      'equipped': true,
    },
    {
      'id': 'sunset',
      'characterId': 'robert',
      'name': 'Sunset Copper',
      'description': 'Warm copper, the colour of the room at dusk.',
      'cost': 5,
      'owned': false,
      'equipped': false,
    },
    {
      'id': 'dune',
      'characterId': 'robert',
      'name': 'Dune Walker',
      'description': 'Pale desert sand that catches the low sun.',
      'cost': 15,
      'owned': false,
      'equipped': false,
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

    // The character page carries the character and the composer, and nothing
    // else at all: no title bar, no banner, no greeting card, no room status,
    // and no orientation, connection or balance.
    expect(find.byTooltip('Send test question'), findsOneWidget);
    for (final absent in [
      'little steps',
      'Looking for the character room…',
      'Robert · static preview',
      'Hello, explorer.',
      'Let’s explore',
      'Exploring offline',
    ]) {
      expect(find.text(absent), findsNothing,
          reason: 'the character page does not carry it');
    }
    expect(find.byType(DevelopmentBanner), findsNothing);
    // Past the startup deadline: with no host the handshake waits for an
    // engine that is never going to start.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start orientation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start orientation'));
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
    // The chrome the character page gave up is still here, so the operator
    // notice and the parent entry are never more than one tap away.
    expect(find.byType(DevelopmentBanner), findsOneWidget);
    expect(find.text('little steps'), findsOneWidget);
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

    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start orientation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start orientation'));
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
    // Readable text and a reachable composer take priority over the character.
    expect(find.byTooltip('Send test question'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The content pages are the ones that have to scroll at this size.
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Parent area'));
    await tester.pumpAndSettle();
    expect(find.text('Parent area · prototype'), findsOneWidget);
    expect(find.textContaining('not an authenticated parental gate'),
        findsOneWidget);
    expect(find.text('Character motion'), findsOneWidget);
    // The room's own state moved here off the character page. Its wording
    // tracks the handshake, so assert the line that is always there.
    expect(find.textContaining('Learning and chat do not depend on the room'),
        findsOneWidget);
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

  testWidgets('the page only paints transparently when a room is behind it',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // No host at all: the page must stay opaque, or it would show through to
    // an empty window instead of a character room.
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        isNot(Colors.transparent));
    // Past the startup deadline: with no host the handshake waits for an
    // engine that is never going to start.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CharacterStage>(find.byType(CharacterStage))
            .surfaceAttached,
        isFalse,
        reason: 'no host, so the stage shows its own static card');

    // A composited surface makes the page full bleed, and the static preview
    // gives way to a transparent window onto the live room.
    final host = FakeUnityHost('test/fullbleed')..install();
    addTearDown(host.remove);
    final room = AvatarRoom(
      commands: host.commands,
      // Generous: pumpAndSettle advances fake time in 100 ms steps, which
      // would otherwise trip the deadline before the channel reply lands.
      create: () => AvatarBridge(
          commands: host.commands,
          events: host.events,
          timeout: const Duration(seconds: 30)),
    );
    addTearDown(room.dispose);
    // Unmount first: pumping another CompanionApp would reuse the existing
    // CompanionHome state, so initState would never run for this room.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(CompanionApp(room: room));
    await tester.pumpAndSettle();
    // The surface query is a platform round trip that runs alongside the
    // handshake, so let it land without advancing the clock.
    for (var flush = 0; flush < 6; flush++) {
      await tester.pump();
    }
    expect(room.surfaceAttached, isTrue);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.transparent);
    expect(
        tester
            .widget<CharacterStage>(find.byType(CharacterStage))
            .surfaceAttached,
        isTrue,
        reason: 'the live room replaces the static card');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a look reaches the character room only after the service '
      'confirms it', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var owned = false;
    var wearing = 'default';
    Map<String, Object> look(
            String id, String name, int cost, bool isOwned, bool equipped) =>
        {
          'id': id,
          'characterId': 'robert',
          'name': name,
          'description': 'A synthetic look.',
          'cost': cost,
          'owned': isOwned,
          'equipped': equipped,
        };
    final model = CompanionController(DemoApi(
      const DemoConfig(
          baseUrl: 'http://localhost:8000', token: 'synthetic-token'),
      client: MockClient((request) async {
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
                    {'balance': owned ? 0 : 5, 'unit': 'learning_stars'}),
                200);
          case '/v1/challenges/today':
            return http.Response(jsonEncode(_challenges(true)), 200);
          case '/v1/inventory':
            return http.Response(
                jsonEncode({
                  'items': [
                    look('default', 'Robert Original', 0, true,
                        wearing == 'default'),
                    look('sunset', 'Sunset Copper', 5, owned,
                        wearing == 'sunset'),
                  ]
                }),
                200);
          case '/v1/cosmetics/claim':
            owned = true;
            return http.Response(
                '{"cosmeticId":"sunset","owned":true,"spent":5,"balance":0}',
                200);
          case '/v1/equipped-cosmetics':
            wearing = 'sunset';
            return http.Response(
                '{"cosmeticId":"sunset","characterId":"robert"}', 200);
          default:
            return http.Response('{}', 404);
        }
      }),
    ));
    final host = FakeUnityHost('test/looks')..install();
    addTearDown(host.remove);
    final room = AvatarRoom(
      commands: host.commands,
      create: () => AvatarBridge(
          commands: host.commands,
          events: host.events,
          timeout: const Duration(seconds: 30)),
    );
    addTearDown(room.dispose);

    await tester.pumpWidget(CompanionApp(controller: model, room: room));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Connect development service'), 200);
    await tester.tap(find.text('Connect development service'));
    await tester.pumpAndSettle();

    // The look can only reach the room if the room negotiated one at all.
    expect(room.status, AvatarStatus.ready);

    // Connecting restores what the service says is worn, without a tap: that
    // is also what puts an earned look back on the character after a relaunch.
    expect(host.looks, ['default']);

    await tester.scrollUntilVisible(find.text('Sunset Copper'), -200);
    expect(find.text('Ready to earn for 5 stars.'), findsOneWidget);

    await tester.tap(find.text('Earn for 5 stars'));
    await tester.pumpAndSettle();
    expect(find.text('Earned · confirmed by the service.'), findsOneWidget);
    // Earning is not wearing: the room has heard nothing new.
    expect(host.looks, ['default']);

    await tester.tap(find.text('Wear this look'));
    await tester.pumpAndSettle();
    // The equip write and the acknowledgement it waits for are platform round
    // trips; flush them without advancing the clock past the bridge deadline.
    for (var flush = 0; flush < 8; flush++) {
      await tester.pump();
    }
    expect(host.looks, ['default', 'sunset']);
    expect(find.text('Robert is wearing this.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
