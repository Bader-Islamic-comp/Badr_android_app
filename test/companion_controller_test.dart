import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// JSON as the service sends it. `http` reads `application/json` as UTF-8,
/// which the typographic characters in source references need.
http.Response _json(Object? value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});

/// Lets anything a finished test step set off run to completion, so a read or
/// a notification that should not happen has had every chance to.
Future<void> _settle() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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
            'answerType': 'unavailable',
            'text': 'Service unavailable.',
            'citations': [],
            'sources': [],
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
    expect(model.reply?.text, 'Service unavailable.');
    expect(model.reply?.type, ReplyType.unavailable);
    expect(model.reply?.sources, isEmpty);
    model.dispose();
  });

  group('grounded answers', () {
    const turnPath = '/v1/turns/turn-1';

    Map<String, Object?> pending() => {
          'turnId': 'turn-1',
          'status': 'pending',
          'answerType': null,
          'text': '',
          'citations': [],
          'sources': [],
        };

    Map<String, Object?> grounded() => {
          'turnId': 'turn-1',
          'status': 'completed',
          'answerType': 'grounded',
          'text': 'You earn learning stars by finishing lessons.',
          'citations': ['app-help-stars#1', 'app-help-rewards#2'],
          'sources': [
            {
              'id': 'app-help-stars#1',
              'title': 'How learning stars work',
              'reference': 'Robert’s guide · part 1',
            },
            {
              'id': 'app-help-rewards#2',
              'title': 'What stars are for',
              'reference': 'Robert’s guide · part 4',
            },
          ],
        };

    /// The service as the app sees it with grounded answers on. [turn] answers
    /// the turn creation and [read] each read of the turn; both default to a
    /// turn that is pending and then completes.
    DemoApi service({
      Map<String, Object?> Function()? turn,
      FutureOr<http.Response> Function(int read)? read,
      void Function(http.Request request)? onRequest,
    }) {
      var reads = 0;
      return DemoApi(config, client: MockClient((request) async {
        onRequest?.call(request);
        final Object? result;
        switch (request.url.path) {
          case '/v1/bootstrap':
            result = {
              ...bootstrap,
              'features': {
                'voice': false,
                'generativeAnswers': true,
                'unity': false
              },
            };
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
          case '/v1/conversations/conversation-1':
            return http.Response('', 204);
          case '/v1/conversations/conversation-1/turns':
            result = turn?.call() ?? {'turnId': 'turn-1', 'status': 'pending'};
          case turnPath:
            reads++;
            if (read != null) return read(reads);
            result = reads < 3 ? pending() : grounded();
          default:
            return http.Response('{}', 404);
        }
        return _json(result);
      }));
    }

    test('bootstrap records that the service has grounded answers on',
        () async {
      final model = CompanionController(service());
      expect(model.groundedAnswers, isFalse);
      await model.connect();
      expect(model.connected, isTrue);
      expect(model.groundedAnswers, isTrue);
      model.dispose();
    });

    test('a turn completed at creation is read once, with no waiting',
        () async {
      var waits = 0;
      var reads = 0;
      final model = CompanionController(
        service(
          turn: () => {'turnId': 'turn-1', 'status': 'completed'},
          read: (read) {
            reads = read;
            return _json(grounded());
          },
        ),
        wait: (_) async {
          waits++;
        },
      );
      await model.connect();
      expect(await model.ask('How do I earn stars?'), isTrue);
      expect(waits, 0);
      expect(reads, 1);
      final reply = model.reply!;
      expect(reply.type, ReplyType.grounded);
      expect(reply.text, 'You earn learning stars by finishing lessons.');
      expect(reply.sources.map((source) => source.id),
          ['app-help-stars#1', 'app-help-rewards#2']);
      expect(reply.sources.first.title, 'How learning stars work');
      expect(reply.sources.first.reference, 'Robert’s guide · part 1');
      expect(model.canRetryQuestion, isFalse);
      expect(model.waitingForReply, isFalse);
      model.dispose();
    });

    test('a pending turn is polled every interval until it completes',
        () async {
      final waits = <Duration>[];
      var submissions = 0;
      final model = CompanionController(
        service(onRequest: (request) {
          if (request.url.path.endsWith('/turns')) submissions++;
        }),
        wait: (duration) async => waits.add(duration),
      );
      await model.connect();
      final seen = <bool>[];
      model.addListener(() => seen.add(model.waitingForReply));
      expect(await model.ask('How do I earn stars?'), isTrue);
      expect(submissions, 1);
      // Created pending, so it waits before every read: pending, pending,
      // completed.
      expect(waits, List.filled(3, const Duration(seconds: 1)));
      expect(model.reply?.type, ReplyType.grounded);
      expect(seen, contains(true), reason: 'the page is told Robert is busy');
      expect(model.waitingForReply, isFalse);
      model.dispose();
    });

    test(
        'the deadline keeps the turn, and retry resumes it without asking '
        'twice', () async {
      var clock = DateTime(2026, 9, 25, 12);
      var submissions = 0;
      var reads = 0;
      var ready = false;
      final model = CompanionController(
        service(
          onRequest: (request) {
            if (request.url.path.endsWith('/turns')) submissions++;
          },
          read: (read) {
            reads = read;
            return _json(ready ? grounded() : pending());
          },
        ),
        wait: (duration) async {
          clock = clock.add(duration);
        },
        now: () => clock,
      );
      await model.connect();
      expect(await model.ask('How do I earn stars?'), isFalse);
      expect(model.notice, CompanionController.slowReply);
      expect(reads, 90, reason: 'one read per second for 90 seconds');
      expect(model.canRetryQuestion, isTrue);
      expect(model.waitingForReply, isFalse);
      expect(model.reply, isNull);

      ready = true;
      // The composer is locked while a question is held, but even a different
      // text must not become a second question.
      expect(await model.ask('Something else'), isTrue);
      expect(submissions, 1);
      expect(reads, 91, reason: 'a resumed turn is read at once');
      expect(model.reply?.type, ReplyType.grounded);
      expect(model.canRetryQuestion, isFalse);
      model.dispose();
    });

    test('a completed turn that breaks the contract is refused, not shown',
        () async {
      final model = CompanionController(service(
        turn: () => {'turnId': 'turn-1', 'status': 'completed'},
        read: (_) => _json({
          ...grounded(),
          'answerType': 'abstained',
          'text': 'Private server text that must not be echoed.',
        }),
      ));
      await model.connect();
      expect(await model.ask('How do I earn stars?'), isFalse);
      expect(model.reply, isNull);
      expect(model.notice, 'The service returned an unexpected reply.');
      expect(model.notice, isNot(contains('Private')));
      expect(model.canRetryQuestion, isTrue);
      model.dispose();
    });

    test('an unknown turn status at creation is refused', () async {
      final model = CompanionController(
          service(turn: () => {'turnId': 'turn-1', 'status': 'streaming'}));
      await model.connect();
      expect(await model.ask('How do I earn stars?'), isFalse);
      expect(model.notice, 'The service returned an unexpected reply.');
      expect(model.canRetryQuestion, isTrue);
      model.dispose();
    });

    test('clearing while Robert waits stops polling before the next read',
        () async {
      var reads = 0;
      var deletes = 0;
      final waitStarted = Completer<void>();
      final waitDone = Completer<void>();
      final model = CompanionController(
        service(
          onRequest: (request) {
            if (request.method == 'DELETE') deletes++;
          },
          read: (read) {
            reads = read;
            return _json(pending());
          },
        ),
        wait: (_) {
          if (!waitStarted.isCompleted) waitStarted.complete();
          return waitDone.future;
        },
      );
      await model.connect();
      final asking = model.ask('How do I earn stars?');
      await waitStarted.future;
      expect(model.waitingForReply, isTrue);
      expect(model.canClear, isTrue);

      await model.clearConversation();
      expect(deletes, 1);
      expect(model.waitingForReply, isFalse);
      expect(model.hasConversation, isFalse);
      expect(model.canRetryQuestion, isFalse);
      expect(model.notice, 'Development conversation cleared.');

      // The wait ending late must not start another read.
      waitDone.complete();
      expect(await asking, isFalse);
      await _settle();
      expect(reads, 0);
      expect(model.reply, isNull);
      model.dispose();
    });

    test('a reply that lands after clearing is dropped, not resurrected',
        () async {
      final readStarted = Completer<void>();
      final readResult = Completer<http.Response>();
      final model = CompanionController(
        service(read: (_) {
          readStarted.complete();
          return readResult.future;
        }),
        wait: (_) async {},
      );
      await model.connect();
      final asking = model.ask('How do I earn stars?');
      await readStarted.future;

      await model.clearConversation();
      expect(model.hasConversation, isFalse);
      // The read that was in flight completes with a perfectly good answer.
      readResult.complete(_json(grounded()));
      expect(await asking, isFalse);
      await _settle();
      expect(model.reply, isNull);
      expect(model.canRetryQuestion, isFalse);
      model.dispose();
    });

    test('disposing while Robert waits stops polling and notifies nobody',
        () async {
      var reads = 0;
      final waitStarted = Completer<void>();
      final waitDone = Completer<void>();
      final model = CompanionController(
        service(read: (read) {
          reads = read;
          return _json(pending());
        }),
        wait: (_) {
          if (!waitStarted.isCompleted) waitStarted.complete();
          return waitDone.future;
        },
      );
      await model.connect();
      final asking = model.ask('How do I earn stars?');
      await waitStarted.future;
      var notified = 0;
      model.addListener(() => notified++);

      model.dispose();
      waitDone.complete();
      // A notification after disposal would throw from ChangeNotifier here.
      expect(await asking, isFalse);
      await _settle();
      expect(notified, 0);
      expect(reads, 0);
    });
  });

  group('a completed turn is parsed strictly', () {
    Map<String, dynamic> valid() => {
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

    Map<String, dynamic> source(String id) =>
        {'id': id, 'title': 'A title', 'reference': 'A reference'};

    test('a valid grounded turn parses, and a pending one is not a reply', () {
      final reply = Reply.fromTurn(valid(), turnId: 'turn-1')!;
      expect(reply.type, ReplyType.grounded);
      expect(reply.sources.single.id, 'app-help-stars#1');
      for (final type in ['unavailable', 'abstained', 'redirected', 'safety']) {
        final fixed = Reply.fromTurn(
            {...valid(), 'answerType': type, 'citations': [], 'sources': []},
            turnId: 'turn-1')!;
        expect(fixed.type.wire, type);
        expect(fixed.sources, isEmpty);
      }
      expect(
          Reply.fromTurn({...valid(), 'answerType': 'reviewed_answer'},
                  turnId: 'turn-1')!
              .type,
          ReplyType.reviewedAnswer);
      expect(
          Reply.fromTurn({
            'turnId': 'turn-1',
            'status': 'pending',
            'answerType': null,
            'text': '',
            'citations': [],
            'sources': [],
          }, turnId: 'turn-1'),
          isNull);
    });

    final rejected =
        <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
      'a chunk id that breaks the pattern': (turn) => turn
        ..['citations'] = ['App-Help-Stars#1']
        ..['sources'] = [source('App-Help-Stars#1')],
      'a chunk id with part zero': (turn) => turn
        ..['citations'] = ['app-help-stars#0']
        ..['sources'] = [source('app-help-stars#0')],
      'sources that name different ids from the citations': (turn) =>
          turn..['sources'] = [source('app-help-other#1')],
      'sources in a different order from the citations': (turn) => turn
        ..['citations'] = ['app-help-stars#1', 'app-help-stars#2']
        ..['sources'] = [
          source('app-help-stars#2'),
          source('app-help-stars#1')
        ],
      'more citations than sources': (turn) =>
          turn..['citations'] = ['app-help-stars#1', 'app-help-stars#2'],
      'the same source twice': (turn) => turn
        ..['citations'] = ['app-help-stars#1', 'app-help-stars#1']
        ..['sources'] = [
          source('app-help-stars#1'),
          source('app-help-stars#1')
        ],
      'sources on an abstained reply': (turn) =>
          turn..['answerType'] = 'abstained',
      'sources on a safety reply': (turn) => turn..['answerType'] = 'safety',
      'a library reply with no sources': (turn) => turn
        ..['citations'] = []
        ..['sources'] = [],
      'more than four sources': (turn) {
        final ids = [for (var n = 1; n <= 5; n++) 'app-help-stars#$n'];
        return turn
          ..['citations'] = ids
          ..['sources'] = [for (final id in ids) source(id)];
      },
      'an unknown answer type': (turn) => turn..['answerType'] = 'opinion',
      'a missing answer type': (turn) => turn..remove('answerType'),
      'text over 1,200 characters': (turn) => turn..['text'] = 'a' * 1201,
      'blank text': (turn) => turn..['text'] = '   ',
      'a citation marker left in the text': (turn) =>
          turn..['text'] = 'You earn stars by finishing lessons [1].',
      'a source title over 120 characters': (turn) => turn
        ..['sources'] = [
          {...source('app-help-stars#1'), 'title': 't' * 121}
        ],
      'a source reference over 160 characters': (turn) => turn
        ..['sources'] = [
          {...source('app-help-stars#1'), 'reference': 'r' * 161}
        ],
      'another turn': (turn) => turn..['turnId'] = 'turn-2',
      'an unknown status': (turn) => turn..['status'] = 'failed',
      'a pending turn that already names an answer type': (turn) =>
          turn..['status'] = 'pending',
    };
    for (final entry in rejected.entries) {
      test('rejects ${entry.key}', () {
        expect(
            () => Reply.fromTurn(entry.value(valid()), turnId: 'turn-1'),
            throwsA(isA<DemoApiException>().having((error) => error.message,
                'message', 'The service returned an unexpected reply.')));
      });
    }

    test('counts characters as the service does, not UTF-16 units', () {
      // 1,200 characters outside the basic plane are 2,400 UTF-16 units.
      final reply =
          Reply.fromTurn({...valid(), 'text': '🌙' * 1200}, turnId: 'turn-1')!;
      expect(reply.text.runes.length, 1200);
    });
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

  test('a look is earned from the service, never granted on the device',
      () async {
    var owned = false;
    var claims = 0;
    var equips = 0;
    Map<String, Object> look(
            String id, int cost, bool isOwned, bool equipped) =>
        {
          'id': id,
          'characterId': 'robert',
          'name': id,
          'description': 'A synthetic look.',
          'cost': cost,
          'owned': isOwned,
          'equipped': equipped,
        };
    final api = DemoApi(config, client: MockClient((request) async {
      final Object result;
      switch (request.url.path) {
        case '/v1/bootstrap':
          result = bootstrap;
        case '/v1/lessons':
          result = lessons;
        case '/v1/rewards':
          // The balance only ever comes from here, so spending shows up as the
          // service reporting less, not as the app subtracting.
          result = {'balance': owned ? 0 : 5, 'unit': 'learning_stars'};
        case '/v1/challenges/today':
          result = {'items': []};
        case '/v1/inventory':
          result = {
            'items': [
              look('default', 0, true, !owned),
              look('sunset', 5, owned, owned),
            ]
          };
        case '/v1/cosmetics/claim':
          claims++;
          owned = true;
          result = {
            'cosmeticId': 'sunset',
            'owned': true,
            'spent': 5,
            'balance': 0
          };
        case '/v1/equipped-cosmetics':
          equips++;
          result = {'cosmeticId': 'sunset', 'characterId': 'robert'};
        default:
          return http.Response('{}', 404);
      }
      return http.Response(jsonEncode(result), 200);
    }));
    final model = CompanionController(api);

    const locked = Cosmetic(
        id: 'sunset',
        characterId: 'robert',
        name: 'sunset',
        description: 'A synthetic look.',
        cost: 5,
        owned: false,
        equipped: false);

    // Offline, nothing is earned and nothing is written.
    expect(await model.claimCosmetic(locked), isFalse);
    expect(claims, 0);

    await model.connect();
    expect(model.canAfford(locked), isTrue);
    expect(model.equippedCosmeticId, 'default');

    expect(await model.claimCosmetic(locked), isTrue);
    expect(claims, 1);
    // Re-read rather than adjusted: the service decides what is left.
    expect(model.balance, 0);
    expect(model.cosmetics.firstWhere((c) => c.id == 'sunset').owned, isTrue);

    expect(await model.equipCosmetic(locked), isTrue);
    expect(equips, 1);
    expect(model.equippedCosmeticId, 'sunset');
    model.dispose();
  });

  test('a look the service refuses is not worn and does not spend twice',
      () async {
    var claims = 0;
    final api = DemoApi(config, client: MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return http.Response(jsonEncode(bootstrap), 200);
        case '/v1/lessons':
          return http.Response(jsonEncode(lessons), 200);
        case '/v1/rewards':
          return http.Response('{"balance":0,"unit":"learning_stars"}', 200);
        case '/v1/challenges/today':
          return http.Response('{"items":[]}', 200);
        case '/v1/inventory':
          return http.Response(jsonEncode(inventory), 200);
        case '/v1/cosmetics/claim':
          claims++;
          // Not enough stars: the service is the only thing that decides.
          return http.Response('{"error":{"code":"insufficient_stars"}}', 403);
        default:
          return http.Response('{}', 404);
      }
    }));
    final model = CompanionController(api);
    await model.connect();

    const dear = Cosmetic(
        id: 'midnight',
        characterId: 'robert',
        name: 'midnight',
        description: 'A synthetic look.',
        cost: 30,
        owned: false,
        equipped: false);
    expect(model.canAfford(dear), isFalse);
    expect(await model.claimCosmetic(dear), isFalse);
    expect(claims, 1);
    expect(model.cosmetics.any((c) => c.id == 'midnight'), isFalse);
    expect(model.notice, isNotNull);
    model.dispose();
  });
}
