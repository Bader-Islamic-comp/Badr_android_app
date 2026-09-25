import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/domain/models.dart';
import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/theme.dart';
import 'package:companion_mobile/ui/character_stage.dart';
import 'package:companion_mobile/ui/talk_page.dart';
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

/// JSON as the service sends it; `http` reads `application/json` as UTF-8.
http.Response _json(Object? value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

const _grounded = {
  'turnId': 'turn-1',
  'status': 'completed',
  'answerType': 'grounded',
  'text': 'You earn learning stars by finishing lessons.',
  'citations': ['app-help-stars#1'],
  'sources': [
    {
      'id': 'app-help-stars#1',
      'title': 'How learning stars work',
      'reference': 'Robert’s guide · part 1',
    }
  ],
};

const _chatText = 'Hi! I’m happy, thank you. What would you like to learn?';

/// Casual chat: Robert talking, so no citations and no sources.
const _chat = {
  'turnId': 'turn-1',
  'status': 'completed',
  'answerType': 'chat',
  'text': _chatText,
  'citations': [],
  'sources': [],
};

/// The thinking line, the same whatever kind of reply is coming.
const _thinking = 'Robert is thinking… his antennae are wiggling';

/// The composer's hint once the development service is connected.
const _hint = 'Say hi or ask (test text only)';

final _liveRegion = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.liveRegion == true);

/// A controller already holding a reply, to check how each kind is framed
/// without a service.
class _ReplyingController extends CompanionController {
  _ReplyingController(Reply value) : super(DemoApi(const DemoConfig())) {
    reply = value;
  }
}

/// Lets pending work finish without advancing the fake clock.
/// `pumpAndSettle` never settles while the thinking indicator spins.
Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump();
  }
}

void main() {
  testWidgets(
      'Robert shows he is thinking, then answers from his library with '
      'sources', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    var reads = 0;
    final waited = Completer<void>();
    final model = CompanionController(
      DemoApi(
        const DemoConfig(
            baseUrl: 'http://localhost:8000', token: 'synthetic-token'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/v1/conversations':
              return _json({'conversationId': 'conversation-1'});
            case '/v1/conversations/conversation-1/turns':
              return _json({'turnId': 'turn-1', 'status': 'pending'});
            case '/v1/turns/turn-1':
              reads++;
              return _json(_grounded);
            default:
              return http.Response('{}', 404);
          }
        }),
      ),
      // Held open by the test, never a real delay: under the tester's fake
      // clock a real one would never finish.
      wait: (_) => waited.future,
    )
      // Connection itself is covered by the controller tests.
      ..connected = true
      ..groundedAnswers = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'How do I earn stars?');
    await tester.tap(find.byTooltip('Send test question'));
    await _flush(tester);

    expect(find.text(_thinking), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.ancestor(of: find.text(_thinking), matching: _liveRegion),
        findsOneWidget,
        reason: 'a screen reader hears that Robert is thinking');
    // The bubble says it; a bar over Robert's page would say it twice.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    IconButton button(String tooltip) =>
        tester.widget<IconButton>(find.ancestor(
            of: find.byTooltip(tooltip), matching: find.byType(IconButton)));
    expect(button('Send test question').onPressed, isNull,
        reason: 'nothing more can be sent while Robert is thinking');
    expect(button('Clear development conversation').onPressed, isNotNull,
        reason: 'but the question can always be taken back');
    expect(reads, 0);

    waited.complete();
    await _flush(tester);
    expect(reads, 1);
    expect(find.text(_thinking), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('From Robert’s library'), findsOneWidget);
    expect(find.text('You earn learning stars by finishing lessons.'),
        findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('How learning stars work'), findsOneWidget);
    expect(find.text('Robert’s guide · part 1'), findsOneWidget);
    expect(tester.getSemantics(find.text('How learning stars work')),
        isSemantics(label: 'How learning stars work\nRobert’s guide · part 1'),
        reason: 'each source is read as one item, and it is not a link');
    expect(tester.takeException(), isNull);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('clearing while Robert thinks takes the question back for good',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reads = 0;
    var deletes = 0;
    final waited = Completer<void>();
    final model = CompanionController(
      DemoApi(
        const DemoConfig(
            baseUrl: 'http://localhost:8000', token: 'synthetic-token'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/v1/conversations':
              return _json({'conversationId': 'conversation-1'});
            case '/v1/conversations/conversation-1':
              deletes++;
              return http.Response('', 204);
            case '/v1/conversations/conversation-1/turns':
              return _json({'turnId': 'turn-1', 'status': 'pending'});
            case '/v1/turns/turn-1':
              reads++;
              return _json(_grounded);
            default:
              return http.Response('{}', 404);
          }
        }),
      ),
      wait: (_) => waited.future,
    )..connected = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'How do I earn stars?');
    await tester.tap(find.byTooltip('Send test question'));
    await _flush(tester);
    // Grounded answers are off here and on in the test above: the line is the
    // same either way, because it never says what kind of reply is coming.
    expect(find.text(_thinking), findsOneWidget);

    await tester.tap(find.byTooltip('Clear development conversation'));
    await _flush(tester);
    expect(deletes, 1);
    expect(find.text(_thinking), findsNothing);
    expect(find.byTooltip('Clear development conversation'), findsNothing,
        reason: 'nothing is left to clear, so the bubble is gone');
    expect(find.text('Development conversation cleared.'), findsOneWidget);

    // The wait ending afterwards neither reads the turn nor shows a reply.
    waited.complete();
    await _flush(tester);
    expect(reads, 0);
    expect(find.text('From Robert’s library'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  for (final (type, label, colour) in [
    (ReplyType.abstained, 'Robert isn’t sure', muted),
    (ReplyType.redirected, 'Let’s ask a grown-up', orange),
    (ReplyType.safety, 'You can talk to a grown-up you trust', ink),
    (ReplyType.unavailable, 'Service response', teal),
  ]) {
    testWidgets('a ${type.wire} reply is labelled calmly and lists no sources',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = _ReplyingController(Reply(
          type: type, text: 'A fixed development reply for ${type.wire}.'));
      await tester.pumpWidget(CompanionApp(controller: model));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(tester.widget<Text>(find.text(label)).style?.color, colour);
      expect(find.text('A fixed development reply for ${type.wire}.'),
          findsOneWidget);
      expect(find.text('From Robert’s library'), findsNothing);
      expect(find.text('Sources'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  }

  testWidgets(
      'Robert says hi back with no label and no sources, and thinks without '
      'a spinner under reduced motion', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final handle = tester.ensureSemantics();
    final waited = Completer<void>();
    final model = CompanionController(
      DemoApi(
        const DemoConfig(
            baseUrl: 'http://localhost:8000', token: 'synthetic-token'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/v1/conversations':
              return _json({'conversationId': 'conversation-1'});
            case '/v1/conversations/conversation-1/turns':
              return _json({'turnId': 'turn-1', 'status': 'pending'});
            case '/v1/turns/turn-1':
              return _json(_chat);
            default:
              return http.Response('{}', 404);
          }
        }),
      ),
      wait: (_) => waited.future,
    )
      ..connected = true
      ..groundedAnswers = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    // The composer invites a hello as well as a question, and still says the
    // text is only for testing.
    expect(find.text(_hint), findsOneWidget);
    expect(find.text('Type a synthetic test question'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Hi, how are you?');
    await tester.tap(find.byTooltip('Send test question'));
    await _flush(tester);
    expect(find.text(_thinking), findsOneWidget);
    expect(find.ancestor(of: find.text(_thinking), matching: _liveRegion),
        findsOneWidget);
    // Reduced motion: a still robot beside the line instead of a spinner, and
    // no library book, because a hello is not a trip to the library.
    final thinkingRow =
        find.ancestor(of: find.text(_thinking), matching: find.byType(Row));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        find.descendant(
            of: thinkingRow, matching: find.byIcon(Icons.smart_toy_outlined)),
        findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);

    waited.complete();
    await _flush(tester);
    expect(find.text(_thinking), findsNothing);
    expect(find.text(_chatText), findsOneWidget);
    // Chat is Robert talking to the child, so the bubble carries his words and
    // nothing that says where they came from: no label and no sources.
    expect(TalkPage.labelFor(ReplyType.chat), isNull);
    final bubble = find.ancestor(
        of: find.text(_chatText), matching: find.byType(SingleChildScrollView));
    expect(find.descendant(of: bubble, matching: find.byType(Text)),
        findsOneWidget,
        reason: 'the reply is the only text in the bubble');
    for (final type in ReplyType.values) {
      final label = TalkPage.labelFor(type);
      if (label != null) expect(find.text(label.$1), findsNothing);
    }
    expect(find.text('Sources'), findsNothing);
    // The header row still carries the one control that belongs beside a
    // reply, and a screen reader still hears the reply arrive.
    final clear = find.descendant(
        of: bubble, matching: find.byTooltip('Clear development conversation'));
    expect(clear, findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.ancestor(of: clear, matching: find.byType(IconButton)))
            .onPressed,
        isNotNull);
    expect(find.ancestor(of: find.text(_chatText), matching: _liveRegion),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('the parent area says chat replies carry no sources',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model =
        _ReplyingController(const Reply(type: ReplyType.chat, text: _chatText))
          ..connected = true
          ..groundedAnswers = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Parent area'));
    await tester.pumpAndSettle();
    expect(
        find.text('Grounded answers: on · development corpus'), findsOneWidget);
    // The provenance a parent reads must not claim every reply is sourced.
    expect(
        find.text('Questions are answered only from the service’s development '
            'library, with their sources. Casual chat, like a hello, gets a '
            'friendly reply without sources. The model runs on the service, '
            'never on this phone.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('a chat reply on the smallest screen stays in reach',
      (tester) async {
    // The size where the composer's hint already wraps and leaves the reply
    // little room. The friendlier hint must not make that worse.
    tester.view.physicalSize = const Size(320, 380);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final model =
        _ReplyingController(const Reply(type: ReplyType.chat, text: _chatText))
          ..connected = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CharacterStage), findsNothing);
    expect(find.text(_hint), findsOneWidget);
    expect(find.byTooltip('Send test question'), findsOneWidget);
    final scrollView = find.ancestor(
        of: find.text(_chatText), matching: find.byType(SingleChildScrollView));
    expect(tester.getSize(scrollView).height, greaterThan(0),
        reason: 'the composer leaves the reply some room');
    // However little room is left, the words can be scrolled into view.
    await tester.ensureVisible(find.text(_chatText));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(scrollView);
    final words = tester.getRect(find.text(_chatText));
    expect(words.top, lessThan(viewport.bottom));
    expect(words.bottom, greaterThan(viewport.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('a long library reply on a small screen starts at its beginning',
      (tester) async {
    // Short enough that the reply takes the whole page instead of Robert.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final text = 'Stars are for learning. ${'Keep going. ' * 90}'.trim();
    final model = _ReplyingController(Reply(
      type: ReplyType.grounded,
      text: text,
      sources: [
        for (var part = 1; part <= 4; part++)
          ReplySource(
              id: 'app-help-stars#$part',
              title: 'How learning stars work, part $part',
              reference: 'Robert’s guide · part $part'),
      ],
    ));
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CharacterStage), findsNothing);
    final scrollView = find.ancestor(
        of: find.text(text), matching: find.byType(SingleChildScrollView));
    final position = tester
        .state<ScrollableState>(
            find.descendant(of: scrollView, matching: find.byType(Scrollable)))
        .position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'the reply is longer than the space it has');
    expect(position.pixels, 0);
    // The top of the bubble is on screen, not scrolled away above the sources.
    final viewport = tester.getRect(scrollView);
    final start = tester.getRect(find.text('From Robert’s library'));
    expect(start.top, greaterThanOrEqualTo(viewport.top));
    expect(start.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(
        tester.getRect(find.text('Sources')).top, greaterThan(viewport.bottom),
        reason: 'the sources are below, reached by scrolling');
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

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
    // Not connected, so the composer says how to connect rather than invite a
    // hello nobody will answer.
    expect(find.text('Connect the development service to ask'), findsOneWidget);
    expect(find.text(_hint), findsNothing);
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
