import '../data/demo_api.dart';

/// Validated views of service payloads.
///
/// Parsing is deliberately strict and bounded. The development service only
/// publishes synthetic orientation copy, so anything else — including content
/// that claims another `kind` — is rejected rather than rendered. Reviewed
/// religious material must arrive through an approved corpus release and its
/// own contract, never by loosening these checks.
const _maxTitle = 120;
const _maxBody = 400;
const _maxSteps = 10;
const _maxItems = 20;
const _maxReward = 1000;

String _text(dynamic value, int limit, String field) {
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw DemoApiException('The service returned unexpected $field.');
  }
  return value;
}

String _identifier(dynamic value) {
  if (value is! String || !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(value)) {
    throw const DemoApiException(
        'The service returned an unexpected identifier.');
  }
  return value;
}

List<Map<String, dynamic>> _items(Map<String, dynamic> payload) {
  final items = payload['items'];
  if (items is! List || items.length > _maxItems) {
    throw const DemoApiException('The service returned an unexpected list.');
  }
  return items.map((item) {
    if (item is! Map<String, dynamic>) {
      throw const DemoApiException('The service returned an unexpected entry.');
    }
    return item;
  }).toList();
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
    required this.reward,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    // Only orientation copy is releasable at this boundary.
    if (json['kind'] != 'orientation') {
      throw const DemoApiException(
          'This app only displays reviewed orientation content.');
    }
    final steps = json['steps'];
    if (steps is! List || steps.isEmpty || steps.length > _maxSteps) {
      throw const DemoApiException('The service returned unexpected steps.');
    }
    final reward = json['reward'];
    if (reward is! int || reward < 0 || reward > _maxReward) {
      throw const DemoApiException(
          'The service returned an unexpected reward.');
    }
    return Lesson(
      id: _identifier(json['id']),
      title: _text(json['title'], _maxTitle, 'a lesson title'),
      summary: _text(json['summary'], _maxBody, 'a lesson summary'),
      steps: [
        for (final step in steps) _text(step, _maxBody, 'a lesson step'),
      ],
      reward: reward,
    );
  }

  static List<Lesson> listFrom(Map<String, dynamic> payload) =>
      [for (final item in _items(payload)) Lesson.fromJson(item)];

  final String id;
  final String title;
  final String summary;
  final List<String> steps;
  final int reward;
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.completed,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    if (json['completed'] is! bool) {
      throw const DemoApiException(
          'The service returned unexpected challenge state.');
    }
    return Challenge(
      id: _identifier(json['id']),
      title: _text(json['title'], _maxTitle, 'a challenge title'),
      description: _text(json['description'], _maxBody, 'a challenge summary'),
      completed: json['completed'] as bool,
    );
  }

  static List<Challenge> listFrom(Map<String, dynamic> payload) =>
      [for (final item in _items(payload)) Challenge.fromJson(item)];

  final String id;
  final String title;
  final String description;
  final bool completed;
}

class Cosmetic {
  const Cosmetic({
    required this.id,
    required this.characterId,
    required this.name,
    required this.owned,
    required this.equipped,
  });

  factory Cosmetic.fromJson(Map<String, dynamic> json) {
    if (json['owned'] is! bool || json['equipped'] is! bool) {
      throw const DemoApiException(
          'The service returned unexpected inventory state.');
    }
    return Cosmetic(
      id: _identifier(json['id']),
      characterId: _identifier(json['characterId']),
      name: _text(json['name'], _maxTitle, 'a cosmetic name'),
      owned: json['owned'] as bool,
      equipped: json['equipped'] as bool,
    );
  }

  static List<Cosmetic> listFrom(Map<String, dynamic> payload) =>
      [for (final item in _items(payload)) Cosmetic.fromJson(item)];

  final String id;
  final String characterId;
  final String name;
  final bool owned;
  final bool equipped;
}
