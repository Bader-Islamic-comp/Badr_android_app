import 'package:flutter/foundation.dart';

import '../data/demo_api.dart';
import 'models.dart';

class CompanionController extends ChangeNotifier {
  CompanionController(this.api);

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
  bool connected = false;
  bool busy = false;
  bool orientationComplete = false;
  bool serverChallengeComplete = false;
  int? balance;
  String? notice;
  String? answer;
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
  final String _equipmentKey = DemoApi.newKey();
  bool _disposed = false;

  bool get canRetryQuestion => _pendingText != null;
  bool get hasConversation => _conversationId != null;
  Lesson get orientation =>
      lessons.isEmpty ? offlineLessons.first : lessons.first;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _operate(Future<void> Function() operation) async {
    if (busy || _disposed) return;
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
        balance = null;
        serverChallengeComplete = false;
        await api.bootstrap();
        await _refresh();
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

  Future<bool> equipDefault() async {
    var confirmed = false;
    await _operate(() async {
      if (!connected) {
        throw const DemoApiException(
            'Connect to confirm your development inventory.');
      }
      await api.equipDefault(_equipmentKey);
      confirmed = true;
      notice = 'Robert Original confirmed by the service.';
    });
    return confirmed;
  }

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
        answer = null;
      }
      // Retry preserves the original text, request key and known turn ID.
      if (_conversationId == null) {
        _conversationKey ??= DemoApi.newKey();
        final conversation = await api.request('POST', '/v1/conversations',
            body: {}, key: _conversationKey);
        _conversationId = _identifier(conversation['conversationId']);
      }
      if (_turnId == null) {
        final turn = await api.request(
            'POST', '/v1/conversations/$_conversationId/turns',
            body: {'text': _pendingText}, key: _turnKey);
        _turnId = _identifier(turn['turnId']);
      }
      final result = await api.request('GET', '/v1/turns/$_turnId');
      if (result['turnId'] != _turnId ||
          result['status'] != 'completed' ||
          result['text'] is! String ||
          (result['text'] as String).length > 4000 ||
          result['citations'] is! List ||
          (result['citations'] as List).isNotEmpty) {
        throw const DemoApiException(
            'A complete development response is not available.');
      }
      answer = result['text'] as String;
      released = true;
      _pendingText = null;
      _turnKey = null;
      _turnId = null;
    });
    return released;
  }

  String _identifier(dynamic value) {
    if (value is! String || !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(value)) {
      throw const DemoApiException(
          'The service returned an unexpected identifier.');
    }
    return value;
  }

  Future<void> clearConversation() => _operate(() async {
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
        answer = null;
        notice = 'Development conversation cleared.';
      });

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}
