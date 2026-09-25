import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/demo_api.dart';
import 'models.dart';

/// Unwinds a question whose conversation was cleared, or whose controller was
/// disposed, while Robert was still thinking. Never shown to anyone.
class _Stopped implements Exception {
  const _Stopped();
}

class CompanionController extends ChangeNotifier {
  /// [wait] and [now] exist so tests can poll without real timers: a test
  /// that waits on a real delay under the widget tester's fake clock never
  /// finishes.
  CompanionController(
    this.api, {
    Future<void> Function(Duration)? wait,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 1),
    this.replyDeadline = const Duration(seconds: 90),
  })  : _wait = wait ?? ((duration) => Future<void>.delayed(duration)),
        _now = now ?? DateTime.now;

  /// Shown when a reply outlasts [replyDeadline]. The turn is kept, so trying
  /// again picks up the same question rather than asking it twice.
  static const slowReply = 'Robert is taking longer than usual. Try again.';

  /// Offline orientation copy. It mirrors the development service's synthetic
  /// lesson so the experience stays usable with no network, and contains no
  /// religious teaching.
  static const offlineLessons = [
    Lesson(
      id: 'demo-learning',
      title: 'Meet your learning companion',
      summary: 'Practice using your learning space. This orientation is '
          'development copy; it contains no religious teaching.',
      steps: [
        'Choose a comfortable place to learn.',
        'Take your time. You can pause whenever you need.',
        'Ask a trusted adult when you need help.',
      ],
      reward: 5,
    ),
  ];

  final DemoApi api;

  /// How often a pending turn is read again.
  final Duration pollInterval;

  /// How long one attempt waits for a reply before handing control back. The
  /// service may queue a question behind others, so this is a pause, not a
  /// failure of the question: retrying resumes the same turn.
  final Duration replyDeadline;

  final Future<void> Function(Duration) _wait;
  final DateTime Function() _now;

  bool connected = false;
  bool busy = false;

  /// True while a question is out with the service, from the send until a
  /// reply is released, the attempt fails or the conversation is cleared.
  bool waitingForReply = false;

  /// Whether the connected service reported grounded answers as on. False
  /// whenever nothing is connected.
  bool groundedAnswers = false;
  bool orientationComplete = false;
  bool serverChallengeComplete = false;
  int? balance;
  String? notice;

  /// The last reply Robert gave, already validated. Earlier ones are not kept.
  Reply? reply;
  List<Lesson> lessons = offlineLessons;
  List<Challenge> challenges = const [];
  List<Cosmetic> cosmetics = const [];
  String? _conversationId;
  String? _turnId;
  String? _pendingText;
  String? _turnKey;
  String? _conversationKey;
  String? _deletionKey;
  final String _completionKey = DemoApi.newKey();

  /// One stable key per look per action. Sharing a key across looks would make
  /// the service answer a second look with the first one's recorded result, so
  /// a retry reuses its own key and nothing else does.
  final Map<String, String> _claimKeys = {};
  final Map<String, String> _equipKeys = {};
  bool _disposed = false;

  /// The operation holding [busy], so a clear can wait for a stopped question
  /// to let go of it.
  Future<void>? _inFlight;

  /// Completed to stop the question in flight from waiting any longer.
  Completer<void>? _stopWaiting;

  /// A question is held for retry: it failed or timed out, and sending again
  /// resumes it rather than asking anew. Not while it is still being waited
  /// on — that is [waitingForReply].
  bool get canRetryQuestion => _pendingText != null && !waitingForReply;
  bool get hasConversation => _conversationId != null;

  /// Clearing is allowed whenever nothing else is running, and also while
  /// Robert is thinking: a child should not have to wait out a slow answer to
  /// take the question back.
  bool get canClear => !busy || waitingForReply;
  Lesson get orientation =>
      lessons.isEmpty ? offlineLessons.first : lessons.first;

  /// The look the service last reported as worn, or null when the inventory
  /// has not been read. Never assumed from a local action.
  String? get equippedCosmeticId {
    for (final cosmetic in cosmetics) {
      if (cosmetic.equipped) return cosmetic.id;
    }
    return null;
  }

  /// True when the balance the service reported covers this look's price.
  /// A null balance is not "affordable"; it is "unknown".
  bool canAfford(Cosmetic cosmetic) =>
      balance != null && balance! >= cosmetic.cost;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _operate(Future<void> Function() operation) {
    if (busy || _disposed) return Future.value();
    return _inFlight = _run(operation);
  }

  Future<void> _run(Future<void> Function() operation) async {
    busy = true;
    notice = null;
    _changed();
    try {
      await operation();
    } on DemoApiException catch (error) {
      notice = error.message;
    } catch (_) {
      notice = 'This action is unavailable right now. Please try again.';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> connect() => _operate(() async {
        connected = false;
        groundedAnswers = false;
        balance = null;
        serverChallengeComplete = false;
        final grounded = await api.bootstrap();
        await _refresh();
        groundedAnswers = grounded;
        connected = true;
        notice = 'Connected to the adult-operated development service.';
      });

  Future<void> _refresh() async {
    final lessonResult = await api.lessons();
    final result = await api.rewards();
    final challengeResult = await api.challenges();
    final inventoryResult = await api.inventory();
    final value = result['balance'];
    if (value is! int || value < 0 || result['unit'] != 'learning_stars') {
      throw const DemoApiException('The service returned unexpected progress.');
    }
    final published = Lesson.listFrom(lessonResult);
    lessons = published.isEmpty ? offlineLessons : published;
    challenges = Challenge.listFrom(challengeResult);
    cosmetics = Cosmetic.listFrom(inventoryResult);
    balance = value;
    serverChallengeComplete =
        challenges.any((challenge) => challenge.completed);
  }

  Future<bool> completeOrientation() async {
    var celebrated = false;
    await _operate(() async {
      final alreadyDone = orientationComplete;
      orientationComplete = true;
      if (!connected) {
        celebrated = !alreadyDone;
        notice =
            'Orientation explored on this device. Connect to save demo progress.';
        return;
      }
      final result = await api.completeLesson(_completionKey);
      if (result['lessonId'] != 'demo-learning' ||
          result['completed'] != true) {
        throw const DemoApiException('The service did not confirm completion.');
      }
      // Never increment a local balance; refresh the server snapshot.
      await _refresh();
      celebrated = true;
      notice = 'Your development progress is saved by the service.';
    });
    return celebrated;
  }

  /// Earns a look by spending server-owned stars. Returns true only once the
  /// service has recorded the purchase; nothing is unlocked on this device.
  Future<bool> claimCosmetic(Cosmetic cosmetic) async {
    var confirmed = false;
    await _operate(() async {
      if (!connected) {
        throw const DemoApiException(
            'Connect to confirm your development inventory.');
      }
      final key = _claimKeys[cosmetic.id] ??= DemoApi.newKey();
      await api.claimCosmetic(cosmetic.id, key);
      // Re-read rather than adjusting a local balance: the service decides what
      // was spent and what is left.
      await _refresh();
      confirmed = true;
      notice = '${cosmetic.name} earned.';
    });
    return confirmed;
  }

  /// Wears an earned look. Returns true only after the service confirms the
  /// write, which is what allows the room to be told about it.
  Future<bool> equipCosmetic(Cosmetic cosmetic) async {
    var confirmed = false;
    await _operate(() async {
      if (!connected) {
        throw const DemoApiException(
            'Connect to confirm your development inventory.');
      }
      final key = _equipKeys[cosmetic.id] ??= DemoApi.newKey();
      await api.equipCosmetic(cosmetic.id, key);
      await _refresh();
      confirmed = true;
      notice = '${cosmetic.name} confirmed by the service.';
    });
    return confirmed;
  }

  /// Sends a question, or resumes the one held for retry, and waits for
  /// Robert's reply. Returns true only once a validated reply is released.
  Future<bool> ask(String text) async {
    var released = false;
    await _operate(() async {
      if (!connected) {
        throw const DemoApiException(
            'Connect to the development service first.');
      }
      if (_pendingText == null) {
        if (text.trim().isEmpty || text.length > 1000) {
          throw const DemoApiException(
              'Enter a synthetic question of 1 to 1,000 characters.');
        }
        _pendingText = text.trim();
        _turnKey = DemoApi.newKey();
        reply = null;
      }
      final stop = _stopWaiting = Completer<void>();
      waitingForReply = true;
      _changed();
      try {
        final found = await _awaitReply(stop);
        reply = found;
        released = true;
        _pendingText = null;
        _turnKey = null;
        _turnId = null;
      } on _Stopped {
        // Cleared or disposed mid-wait. Nothing is released, and whatever
        // stopped the wait owns what happens to the question now.
      } finally {
        waitingForReply = false;
        if (identical(_stopWaiting, stop)) _stopWaiting = null;
      }
    });
    return released;
  }

  /// One attempt at a reply, bounded by [replyDeadline] from its start.
  ///
  /// Retry preserves the original text, request keys and known turn ID, so a
  /// timed-out or failed attempt resumes polling the turn it already created
  /// instead of asking the service a second time.
  Future<Reply> _awaitReply(Completer<void> stop) async {
    final deadline = _now().add(replyDeadline);
    if (_conversationId == null) {
      _conversationKey ??= DemoApi.newKey();
      final conversation = await _unlessStopped(
          api.request('POST', '/v1/conversations',
              body: {}, key: _conversationKey),
          stop);
      _conversationId = _identifier(conversation['conversationId']);
    }
    // A turn just created as pending has nothing to read yet. A resumed turn's
    // state is unknown, so it is read straight away.
    var pause = false;
    if (_turnId == null) {
      final turn = await _unlessStopped(
          api.request('POST', '/v1/conversations/$_conversationId/turns',
              body: {'text': _pendingText}, key: _turnKey),
          stop);
      final turnId = _identifier(turn['turnId']);
      pause = switch (turn['status']) {
        'pending' => true,
        'completed' => false,
        _ => throw const DemoApiException(
            'The service returned an unexpected reply.'),
      };
      _turnId = turnId;
    }
    final turnId = _turnId!;
    while (true) {
      if (pause) {
        if (!_now().isBefore(deadline)) {
          throw const DemoApiException(slowReply);
        }
        await _unlessStopped(_wait(pollInterval), stop);
      }
      pause = true;
      final result =
          await _unlessStopped(api.request('GET', '/v1/turns/$turnId'), stop);
      final found = Reply.fromTurn(result, turnId: turnId);
      if (found != null) return found;
    }
  }

  /// Waits for [work] unless [stop] completes first. Either way, once stopped
  /// the result is discarded, so a reply that lands just after a clear cannot
  /// bring the answer back.
  Future<T> _unlessStopped<T>(Future<T> work, Completer<void> stop) async {
    final Object? value;
    try {
      value = await Future.any<Object?>([work, stop.future]);
    } catch (_) {
      if (stop.isCompleted) throw const _Stopped();
      rethrow;
    }
    if (stop.isCompleted) throw const _Stopped();
    return value as T;
  }

  /// Stops the question in flight from waiting any longer. It unwinds without
  /// releasing anything and gives up [busy].
  void _stopQuestion() {
    final stop = _stopWaiting;
    if (stop != null && !stop.isCompleted) stop.complete();
  }

  String _identifier(dynamic value) {
    if (value is! String || !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(value)) {
      throw const DemoApiException(
          'The service returned an unexpected identifier.');
    }
    return value;
  }

  /// Deletes the server conversation, then forgets it locally.
  ///
  /// While Robert is thinking this first stops the wait: the question unwinds
  /// without releasing anything, and only then is the conversation deleted, so
  /// a reply that arrives in between is dropped rather than shown after the
  /// child asked for it to go. If the delete fails, the question stays held
  /// for retry exactly as it would after any other failure.
  Future<void> clearConversation() async {
    if (waitingForReply) {
      _stopQuestion();
      waitingForReply = false;
      _changed();
      await _inFlight;
    }
    await _clear();
  }

  Future<void> _clear() => _operate(() async {
        // Creation may have succeeded before the response was lost. Recover its
        // idempotent result so clearing also removes that server conversation.
        if (_conversationId == null && _conversationKey != null) {
          final conversation = await api.request('POST', '/v1/conversations',
              body: {}, key: _conversationKey);
          _conversationId = _identifier(conversation['conversationId']);
        }
        if (_conversationId != null) {
          _deletionKey ??= DemoApi.newKey();
          await api.request('DELETE', '/v1/conversations/$_conversationId',
              key: _deletionKey);
        }
        _conversationId = null;
        _conversationKey = null;
        _turnId = null;
        _turnKey = null;
        _pendingText = null;
        _deletionKey = null;
        reply = null;
        notice = 'Development conversation cleared.';
      });

  @override
  void dispose() {
    _disposed = true;
    // A question still being waited on stops polling now rather than on its
    // next read; `_changed` keeps its unwinding from notifying anyone.
    _stopQuestion();
    api.close();
    super.dispose();
  }
}
