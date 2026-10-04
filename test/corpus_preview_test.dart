import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/domain/models.dart';
import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/theme.dart';
import 'package:companion_mobile/ui/talk_page.dart';
import 'package:companion_mobile/ui/text_direction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An adult operator's corpus preview (`comp-server/doc/rag-system.md` §9.1):
/// the service answers from unreviewed Arabic drafts, and the app says so and
/// lays Arabic out right to left. Placeholder Arabic only, no sacred text.

const _arabicAnswer = 'هذه إجابة تجريبية من مسودة لم تراجع بعد.';
const _arabicTitle = 'مسودة تجريبية 1';
const _reference = 'Placeholder draft · draft:1';

const _draftReply = {
  'turnId': 'turn-1',
  'status': 'completed',
  'answerType': 'grounded',
  'text': _arabicAnswer,
  'citations': ['draft-placeholder-1#1'],
  'sources': [
    {
      'id': 'draft-placeholder-1#1',
      'title': _arabicTitle,
      'reference': _reference
    }
  ],
};

const _previewNotice = 'Corpus preview: answers come from unreviewed drafts. '
    'For adult testing only, not for children.';

http.Response _json(Object? value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump();
  }
}

TextDirection? _directionOfText(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).textDirection;

void main() {
  group('directionOf', () {
    test('reads the first strong letter, as the bidi algorithm does', () {
      expect(directionOf(_arabicAnswer), TextDirection.rtl);
      expect(directionOf('How do I earn stars?'), TextDirection.ltr);
      expect(directionOf('12, «$_arabicTitle»'), TextDirection.rtl,
          reason: 'digits and punctuation are neutral');
      expect(
          directionOf('Sahih al-Bukhari · $_arabicTitle'), TextDirection.ltr);
      expect(directionOf(''), TextDirection.ltr);
      expect(directionOf('123 ...'), TextDirection.ltr);
    });
  });

  group('isolateNumberRanges', () {
    test('keeps a verse range in its written order inside Arabic text', () {
      const title = 'سورة يوسف 12:36\u201342';
      expect(isolateNumberRanges(title), 'سورة يوسف \u206612:36\u201342\u2069');
      expect(isolateNumberRanges('الحديث رقم 13'), 'الحديث رقم 13',
          reason: 'a single number needs no isolate');
      expect(isolateNumberRanges('quran:2:255 and 1/3'),
          '\u2066quran:2:255\u2069 and \u20661/3\u2069',
          reason: 'a tag written onto the numbers is isolated with them');
      expect(isolateNumberRanges('حزمة · quran:7:19-23'),
          'حزمة · \u2066quran:7:19-23\u2069',
          reason: 'or it would read 7:19-23:quran');
      expect(isolateNumberRanges('مسودة · quran:12:87\u2013quran:12:93'),
          'مسودة · \u2066quran:12:87\u2013quran:12:93\u2069');
    });

    testWidgets(
        'a right-to-left source title shows its range isolated; English is untouched',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Column(children: [
        directionalText('سورة يوسف 12:36\u201342'),
        directionalText('Sura 12:36\u201342'),
      ])));
      expect(find.text('سورة يوسف \u206612:36\u201342\u2069'), findsOneWidget);
      expect(find.text('Sura 12:36\u201342'), findsOneWidget);
    });
  });

  test('a library reply in a corpus preview is labelled as an unreviewed draft',
      () {
    for (final type in [ReplyType.grounded, ReplyType.reviewedAnswer]) {
      expect(TalkPage.labelFor(type, drafts: true),
          ('Unreviewed draft · adult testing only', orange));
      expect(TalkPage.labelFor(type), ('From Robert’s library', teal));
    }
    expect(TalkPage.labelFor(ReplyType.chat, drafts: true), isNull);
    expect(TalkPage.labelFor(ReplyType.abstained, drafts: true),
        TalkPage.labelFor(ReplyType.abstained));
  });

  testWidgets(
      'a corpus preview says it is unreviewed and lays Arabic out right to left',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              return _json(_draftReply);
            default:
              return http.Response('{}', 404);
          }
        }),
      ),
      wait: (_) => waited.future,
    )
      ..connected = true
      ..groundedAnswers = true
      ..unreviewedDrafts = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();

    expect(find.text(_previewNotice), findsOneWidget,
        reason: 'the notice is on the page before anything is asked');
    expect(find.text('Ask the draft corpus (adults only)'), findsOneWidget);
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().textDirection, TextDirection.ltr);
    await tester.enterText(find.byType(TextField), 'ما هذه المسودة؟');
    await tester.pump();
    expect(field().textDirection, TextDirection.rtl,
        reason: 'an Arabic question is typed right to left');

    await tester.tap(find.byTooltip('Send test question'));
    await _flush(tester);
    waited.complete();
    await _flush(tester);

    expect(find.text('Unreviewed draft · adult testing only'), findsOneWidget);
    expect(find.text('From Robert’s library'), findsNothing);
    expect(_directionOfText(tester, _arabicAnswer), TextDirection.rtl);
    expect(_directionOfText(tester, _arabicTitle), TextDirection.rtl);
    expect(_directionOfText(tester, _reference), TextDirection.ltr);
    // A short Arabic line starts at the bubble's right edge, not its left.
    final answer = tester.getRect(find.text(_arabicAnswer));
    final bubble = tester.getRect(find
        .ancestor(
            of: find.text(_arabicAnswer), matching: find.byType(Container))
        .first);
    expect(bubble.right - answer.right, lessThan(bubble.width / 4));
    expect(find.text(_previewNotice), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('without a preview the page shows no notice', (tester) async {
    final model = CompanionController(DemoApi(const DemoConfig()))
      ..connected = true
      ..groundedAnswers = true;
    await tester.pumpWidget(CompanionApp(controller: model));
    await tester.pumpAndSettle();
    expect(find.text(_previewNotice), findsNothing);
    expect(find.text('Say hi or ask (test text only)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
