import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/ui/source_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Source references as a child reads them. The service sends
/// `<work> · <machine span>` (`comp-server` `rag/chunking.py`
/// `source_label`); these are its shapes, with placeholder titles and no
/// sacred text.

const _work = 'حزمة بدر العربية للمسابقة';
const _tanzil = 'Tanzil Quran Text (Uthmani)';

String? _plain(String reference, {String title = '', bool arabic = true}) =>
    SourceReference.parse(reference, title: title, arabic: arabic)?.plain;

http.Response _json(Object? value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

void main() {
  group('SourceReference', () {
    test('a Quran reference reads as surah:verses', () {
      expect(_plain('$_work · quran:7:19-23'), '$_work · 7:19\u201323');
      expect(_plain('$_tanzil · quran:12:87\u2013quran:12:93'),
          '$_tanzil · 12:87\u201393');
      expect(_plain('quran:2:255'), '2:255');
      expect(_plain('$_work · quran:2:286\u2013quran:3:2'),
          '$_work · 2:286\u20133:2');
      expect(_plain('$_work · quran:12:4-5\u2013quran:12:7-9'),
          '$_work · 12:4\u20139');
    });

    test('the surah is named only when the title names that surah', () {
      expect(
          _plain('$_tanzil · quran:12:87\u2013quran:12:93',
              title: 'سورة يوسف 12:85\u201398'),
          '$_tanzil · سورة يوسف 12:87\u201393');
      expect(
          _plain('$_tanzil · quran:12:87\u2013quran:12:93',
              title: 'Surah Yusuf (12:85\u201398)', arabic: false),
          '$_tanzil · Surah Yusuf 12:87\u201393');
      expect(_plain('$_tanzil · quran:12:87', title: 'سورة الإخلاص 112:1'),
          '$_tanzil · 12:87',
          reason: '112 is not surah 12');
      expect(_plain('$_work · quran:7:19-23', title: 'مشهد تجريبي 2'),
          '$_work · 7:19\u201323');
    });

    test('a hadith reference names its collection in the reply language', () {
      expect(_plain('$_work · bukhari:6324'), '$_work · البخاري 6324');
      expect(_plain('Sahih al-Bukhari · bukhari:6324', arabic: false),
          'Sahih al-Bukhari · Bukhari 6324');
      expect(_plain('$_work · muslim_abdulbaqi:591'), '$_work · مسلم 591');
      expect(_plain('muslim:591', arabic: false), 'Muslim 591');
      expect(_plain('$_work · bukhari:6324\u2013bukhari:6325'),
          '$_work · البخاري 6324\u20136325');
      expect(_plain('$_work · quran:7:23\u2013bukhari:6324'),
          '$_work · 7:23 \u2013 البخاري 6324');
    });

    test('anything else is left as the service sent it', () {
      expect(_plain('Robert\u2019s guide · part 1'), isNull);
      expect(_plain('Placeholder draft · draft:1'), isNull);
      expect(_plain('$_work · quranpedia-mushaf-hafs-text'), isNull);
      expect(_plain('$_work · quran:12'), isNull);
      expect(_plain('$_work · unknown_book:12'), isNull);
    });

    test('is drawn with every part isolated so nothing changes places', () {
      final reference =
          SourceReference.parse('$_work · quran:7:19-23', arabic: true)!;
      expect(reference.display,
          '\u2068$_work\u2069 · \u2068\u20667:19\u201323\u2069\u2069');
      final tanzil = SourceReference.parse(
          '$_tanzil · quran:12:87\u2013quran:12:93',
          title: 'سورة يوسف 12:85\u201398',
          arabic: true)!;
      expect(
          tanzil.display,
          '\u2068$_tanzil\u2069 · '
          '\u2068سورة يوسف \u206612:87\u201393\u2069\u2069');
    });
  });

  testWidgets('an Arabic answer shows its references readably, right to left',
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
              return _json({
                'turnId': 'turn-1',
                'status': 'completed',
                'answerType': 'grounded',
                'text': 'هذه إجابة تجريبية من مسودة لم تراجع بعد.',
                'citations': ['draft-scene-1#1', 'draft-surah-12#1'],
                'sources': [
                  {
                    'id': 'draft-scene-1#1',
                    'title': 'مشهد تجريبي 1',
                    'reference': '$_work · quran:7:19-23',
                  },
                  {
                    'id': 'draft-surah-12#1',
                    'title': 'سورة يوسف 12:85\u201398',
                    'reference': '$_tanzil · quran:12:87\u2013quran:12:93',
                  },
                ],
              });
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
    await tester.enterText(find.byType(TextField), 'ما هذه المسودة؟');
    await tester.tap(find.byTooltip('Send test question'));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump();
    }
    waited.complete();
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump();
    }

    Text line(String shown) => tester.widget<Text>(find.text(shown));
    final scene =
        line('\u2068$_work\u2069 · \u2068\u20667:19\u201323\u2069\u2069');
    expect(scene.textDirection, TextDirection.rtl);
    expect(scene.semanticsLabel, '$_work · 7:19\u201323');
    final surah = line('\u2068$_tanzil\u2069 · '
        '\u2068سورة يوسف \u206612:87\u201393\u2069\u2069');
    expect(surah.textDirection, TextDirection.rtl,
        reason: 'it runs with the Arabic reply, not with its English work');
    expect(surah.semanticsLabel, '$_tanzil · سورة يوسف 12:87\u201393');
    expect(find.textContaining('quran:'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
