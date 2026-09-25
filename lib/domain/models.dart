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

// Bounds from the turn contract, `comp-server/doc/rag-system.md` §7.
const _maxReplyText = 1200;
const _maxSources = 4;
const _maxSourceTitle = 120;
const _maxSourceReference = 160;

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
    required this.description,
    required this.cost,
    required this.owned,
    required this.equipped,
  });

  factory Cosmetic.fromJson(Map<String, dynamic> json) {
    if (json['owned'] is! bool || json['equipped'] is! bool) {
      throw const DemoApiException(
          'The service returned unexpected inventory state.');
    }
    // A price the app cannot make sense of is a rejected payload, not a look
    // shown as free: what a look costs decides what the page offers to spend.
    final cost = json['cost'];
    if (cost is! int || cost < 0 || cost > _maxReward) {
      throw const DemoApiException(
          'The service returned an unexpected cosmetic price.');
    }
    return Cosmetic(
      id: _identifier(json['id']),
      characterId: _identifier(json['characterId']),
      name: _text(json['name'], _maxTitle, 'a cosmetic name'),
      description: _text(json['description'], _maxBody, 'a cosmetic summary'),
      cost: cost,
      owned: json['owned'] as bool,
      equipped: json['equipped'] as bool,
    );
  }

  static List<Cosmetic> listFrom(Map<String, dynamic> payload) =>
      [for (final item in _items(payload)) Cosmetic.fromJson(item)];

  final String id;
  final String characterId;
  final String name;
  final String description;

  /// Learning stars the service charges for this look. Zero means it arrives
  /// with the character, never that it can be taken without earning it.
  final int cost;
  final bool owned;
  final bool equipped;
}

/// How the service arrived at a reply, which decides how the page frames it.
///
/// The service decides this, never the app: a reply is only ever labelled as
/// coming from Robert's library because the service released it with sources.
enum ReplyType {
  /// Grounded answers are switched off on the service; the fixed notice.
  unavailable('unavailable'),

  /// Written from retrieved passages and verified against them.
  grounded('grounded'),

  /// A reviewed answer-bank entry, returned word for word.
  reviewedAnswer('reviewed_answer'),

  /// Not enough evidence, so Robert says he is not sure rather than guess.
  abstained('abstained'),

  /// Something Robert should not answer, such as a ruling or personal details.
  redirected('redirected'),

  /// A fixed safeguarding reply.
  safety('safety');

  const ReplyType(this.wire);

  /// The `answerType` value on the wire.
  final String wire;

  /// Only these two come from the library, so only they carry sources.
  bool get cited => this == grounded || this == reviewedAnswer;
}

/// Where part of a reply came from. Display data only: there is nothing to
/// open, so the page shows it as text rather than as a link.
class ReplySource {
  const ReplySource({
    required this.id,
    required this.title,
    required this.reference,
  });

  /// A chunk id such as `app-help-stars#1`.
  final String id;
  final String title;
  final String reference;
}

/// A completed reply from `GET /v1/turns/{id}` (`rag-system.md` §7).
///
/// Every rule of the contract is enforced here, because this is the text a
/// child reads and the provenance a parent relies on. A payload that breaks
/// one is refused whole rather than shown in part: a reply that claims to be
/// from the library but carries no sources, or a fixed reply that carries some,
/// is not something to render and hope. Errors are generic and never echo what
/// the service sent.
class Reply {
  const Reply(
      {required this.type, required this.text, this.sources = const []});

  static final _chunkId = RegExp(r'^[a-z0-9][a-z0-9-]{1,63}#[1-9][0-9]{0,3}$');

  /// The server strips `[n]` markers once they have been checked; one that
  /// survives means the text was not the verified release.
  static final _citationMarker = RegExp(r'\[\d+\]');

  /// Parses one read of a turn. Returns null while the turn is still pending
  /// and a [Reply] once it has completed; anything else throws.
  static Reply? fromTurn(Map<String, dynamic> json, {required String turnId}) {
    if (json['turnId'] != turnId) throw const DemoApiException(_unexpected);
    switch (json['status']) {
      case 'pending':
        // Nothing of a pending turn is shown, but a pending turn that already
        // names an answer type is not the service this app was built against.
        if (json['answerType'] != null) {
          throw const DemoApiException(_unexpected);
        }
        return null;
      case 'completed':
        break;
      default:
        throw const DemoApiException(_unexpected);
    }
    final type = _type(json['answerType']);
    final text = _bounded(json['text'], _maxReplyText);
    if (_citationMarker.hasMatch(text)) {
      throw const DemoApiException(_unexpected);
    }
    final citations = json['citations'];
    final sources = json['sources'];
    if (citations is! List ||
        sources is! List ||
        citations.length > _maxSources ||
        sources.length != citations.length ||
        // Library replies must say where they came from; nothing else may
        // borrow the library's authority by attaching sources.
        (type.cited ? citations.isEmpty : citations.isNotEmpty)) {
      throw const DemoApiException(_unexpected);
    }
    final parsed = <ReplySource>[];
    for (var index = 0; index < citations.length; index++) {
      final id = citations[index];
      final source = sources[index];
      if (id is! String ||
          !_chunkId.hasMatch(id) ||
          parsed.any((known) => known.id == id) ||
          source is! Map<String, dynamic> ||
          source['id'] != id) {
        throw const DemoApiException(_unexpected);
      }
      parsed.add(ReplySource(
        id: id,
        title: _bounded(source['title'], _maxSourceTitle),
        reference: _bounded(source['reference'], _maxSourceReference),
      ));
    }
    return Reply(type: type, text: text, sources: List.unmodifiable(parsed));
  }

  static const _unexpected = 'The service returned an unexpected reply.';

  static ReplyType _type(dynamic value) {
    for (final type in ReplyType.values) {
      if (type.wire == value) return type;
    }
    throw const DemoApiException(_unexpected);
  }

  /// Like [_text], but counted in characters as the service counts them, so a
  /// reply at the limit that uses characters outside the basic plane is not
  /// refused for being "longer" on this side.
  static String _bounded(dynamic value, int limit) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.runes.length > limit) {
      throw const DemoApiException(_unexpected);
    }
    return value;
  }

  final ReplyType type;

  /// Plain text with no citation markers.
  final String text;

  /// In citation order; empty unless `type.cited`.
  final List<ReplySource> sources;
}
