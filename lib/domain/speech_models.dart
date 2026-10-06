import '../data/demo_api.dart';

/// Validated views of the speech preview's payloads (the backend's
/// `features.speech` and its learn, practice, game and voice routes).
///
/// Parsing is strict and bounded like `models.dart`: a payload that breaks a
/// rule is refused whole, with a generic error that never echoes the service.
/// Nothing here judges a recitation. The service sends the outcome and the
/// feedback text, and the app only shows them.

const _unexpected = 'The service returned an unexpected response.';

Never _refuse() => throw const DemoApiException(_unexpected);

/// The four adhkar of the reviewed allowlist, and nothing else.
const adhkarIds = {'takbeer', 'tasbeeh', 'tahmeed', 'istighfar'};

/// Ids the speech service uses for duas, copy and audio
/// (`^[a-z0-9][a-z0-9_-]{0,63}$`). They appear in request paths.
final _speechId = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

/// Round and turn ids, as elsewhere in the app.
final _identifier = RegExp(r'^[a-zA-Z0-9-]{1,64}$');

/// Characters as the service counts them, so text outside the basic plane is
/// not refused for being "longer" here.
String _text(dynamic value, int limit) {
  if (value is! String || value.trim().isEmpty || value.runes.length > limit) {
    _refuse();
  }
  return value;
}

String? _optionalText(dynamic value, int limit) =>
    value == null ? null : _text(value, limit);

bool _bool(dynamic value) => value is bool ? value : _refuse();

int _int(dynamic value, int min, int max) =>
    value is int && value >= min && value <= max ? value : _refuse();

String _id(dynamic value, RegExp pattern) =>
    value is String && pattern.hasMatch(value) ? value : _refuse();

String _dhikrId(dynamic value) =>
    value is String && adhkarIds.contains(value) ? value : _refuse();

List<Map<String, dynamic>> _list(dynamic value, int max) {
  if (value is! List || value.length > max) _refuse();
  return [
    for (final item in value) item is Map<String, dynamic> ? item : _refuse(),
  ];
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : _refuse();

String _reviewStatus(dynamic value) =>
    value == 'draft' || value == 'approved' ? value as String : _refuse();

/// The bootstrap's `features.speech`: the development preview's switches.
///
/// Every switch is off unless the service's preview is on, and the app also
/// needs the build's own switch (`voiceBuilt`) before any of it shows.
class SpeechFeatures {
  const SpeechFeatures({
    this.preview = false,
    this.recitation = false,
    this.voiceQuestions = false,
    this.robertVoice = false,
    this.maxRecordingSeconds = 15,
  });

  /// A service without the preview, or one that does not mention it.
  static const off = SpeechFeatures();

  /// Hard bounds for one recording, whatever the service says: the speech
  /// service takes at most 30 s.
  static const longestRecording = 30;

  /// Parses `features.speech`. Absent means off: a service from before the
  /// preview sends nothing. Present, it must have the spec's shape exactly.
  /// A feature switch counts only while `preview` is on.
  factory SpeechFeatures.fromJson(dynamic value) {
    if (value == null) return off;
    final json = value is Map<String, dynamic> ? value : _refuse();
    final preview = _bool(json['preview']);
    final recitation = _bool(json['recitation']);
    final voiceQuestions = _bool(json['voiceQuestions']);
    final robertVoice = _bool(json['robertVoice']);
    final seconds = _int(json['maxRecordingSeconds'], 1, longestRecording);
    return SpeechFeatures(
      preview: preview,
      recitation: preview && recitation,
      voiceQuestions: preview && voiceQuestions,
      robertVoice: preview && robertVoice,
      maxRecordingSeconds: seconds,
    );
  }

  final bool preview;
  final bool recitation;
  final bool voiceQuestions;
  final bool robertVoice;
  final int maxRecordingSeconds;

  @override
  bool operator ==(Object other) =>
      other is SpeechFeatures &&
      other.preview == preview &&
      other.recitation == recitation &&
      other.voiceQuestions == voiceQuestions &&
      other.robertVoice == robertVoice &&
      other.maxRecordingSeconds == maxRecordingSeconds;

  @override
  int get hashCode => Object.hash(
      preview, recitation, voiceQuestions, robertVoice, maxRecordingSeconds);
}

/// One of the four short adhkar, from `GET /v1/adhkar`.
class Dhikr {
  const Dhikr({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.text,
    required this.audio,
    required this.practice,
    this.transliteration,
  });

  factory Dhikr.fromJson(Map<String, dynamic> json,
          {bool transliterated = true}) =>
      Dhikr(
        id: _dhikrId(json['id']),
        nameAr: _text(json['nameAr'], 60),
        nameEn: _text(json['nameEn'], 60),
        transliteration:
            transliterated ? _text(json['transliteration'], 80) : null,
        text: _text(json['text'], 120),
        audio: _bool(json['audio']),
        practice: _bool(json['practice']),
      );

  final String id;
  final String nameAr;
  final String nameEn;
  final String? transliteration;

  /// With its harakat, as the service sends it.
  final String text;

  /// Whether Robert's voice for it can be fetched.
  final bool audio;

  /// Whether the service can listen to practice of it.
  final bool practice;
}

List<Dhikr> _adhkar(dynamic items, {bool transliterated = true}) {
  final parsed = [
    for (final item in _list(items, adhkarIds.length))
      Dhikr.fromJson(item, transliterated: transliterated),
  ];
  if (parsed.map((dhikr) => dhikr.id).toSet().length != parsed.length) {
    _refuse();
  }
  return List.unmodifiable(parsed);
}

/// `GET /v1/adhkar`.
class AdhkarList {
  const AdhkarList({required this.items, required this.reviewStatus});

  factory AdhkarList.fromJson(Map<String, dynamic> json) => AdhkarList(
        items: _adhkar(json['items']),
        reviewStatus: _reviewStatus(json['reviewStatus']),
      );

  final List<Dhikr> items;
  final String reviewStatus;
  bool get draft => reviewStatus == 'draft';
}

/// A part of a dua the service can listen to practice of.
class DuaSegment {
  const DuaSegment({required this.index, required this.text});

  final int index;
  final String text;
}

/// One dua from `GET /v1/duas`.
class Dua {
  const Dua({
    required this.id,
    required this.group,
    required this.kind,
    required this.title,
    required this.recorded,
    this.childNote,
    this.repeat,
    this.occasions = const [],
    this.segments = const [],
  });

  factory Dua.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    if (group != 'adhkar' && group != 'daily_duas') _refuse();
    final kind = _id(json['kind'], _speechId);
    final audio = json['audio'];
    if (audio != null && audio != 'recorded') _refuse();
    final repeat = json['repeat'];
    final occasions = json['occasions'] ?? const [];
    if (occasions is! List || occasions.length > 8) _refuse();
    final segments = <DuaSegment>[];
    for (final segment in _list(json['segments'], 20)) {
      final index = _int(segment['index'], 0, 19);
      // In order, each once: practice is offered part by part.
      if (segments.isNotEmpty && index <= segments.last.index) _refuse();
      segments.add(DuaSegment(index: index, text: _text(segment['text'], 300)));
    }
    // Quranic text is not served here, so a Quranic item never has parts.
    if (kind.startsWith('quran') && segments.isNotEmpty) _refuse();
    return Dua(
      id: _id(json['id'], _speechId),
      group: group as String,
      kind: kind,
      title: _text(json['title'], 200),
      // A dua without a note for the child comes as an empty string.
      childNote: json['childNote'] == ''
          ? null
          : _optionalText(json['childNote'], 400),
      repeat: repeat == null ? null : _int(repeat, 1, 1000),
      occasions: List.unmodifiable(
          [for (final occasion in occasions) _id(occasion, _speechId)]),
      recorded: audio == 'recorded',
      segments: List.unmodifiable(segments),
    );
  }

  final String id;
  final String group;
  final String kind;

  /// The display title, not the dua's text.
  final String title;
  final String? childNote;
  final int? repeat;
  final List<String> occasions;

  /// True when a recorded human voice exists for it.
  final bool recorded;
  final List<DuaSegment> segments;
}

/// `GET /v1/duas`.
class DuaList {
  const DuaList({required this.items, required this.reviewStatus});

  factory DuaList.fromJson(Map<String, dynamic> json) {
    final items = [
      for (final item in _list(json['items'], 40)) Dua.fromJson(item)
    ];
    if (items.map((dua) => dua.id).toSet().length != items.length) _refuse();
    return DuaList(
        items: List.unmodifiable(items),
        reviewStatus: _reviewStatus(json['reviewStatus']));
  }

  final List<Dua> items;
  final String reviewStatus;
  bool get draft => reviewStatus == 'draft';
}

/// How one practice attempt went, as the service decided it. Practice, never
/// a verdict: `clear`, `tryAgain` (some words to practise) or `unsure` (the
/// service could not tell, so it says nothing about the words).
enum PracticeOutcome {
  clear('clear'),
  tryAgain('try_again'),
  unsure('unsure');

  const PracticeOutcome(this.wire);
  final String wire;

  static PracticeOutcome parse(dynamic value) {
    for (final outcome in values) {
      if (outcome.wire == value) return outcome;
    }
    _refuse();
  }
}

/// One word's state, for gentle highlighting.
class PracticeWord {
  const PracticeWord({required this.index, required this.state});

  final int index;
  final PracticeOutcome state;
}

/// The feedback line the service chose, from its reviewed copy.
class PracticeFeedback {
  const PracticeFeedback(
      {required this.copyId, required this.text, required this.audio});

  factory PracticeFeedback.fromJson(dynamic value) {
    final json = _map(value);
    return PracticeFeedback(
      copyId: _id(json['copyId'], _speechId),
      text: _text(json['text'], 300),
      audio: _bool(json['audio']),
    );
  }

  final String copyId;
  final String text;

  /// Whether Robert's voice for this line can be fetched.
  final bool audio;
}

/// `POST /v1/recitations/attempts`, and the `attempt` of a game attempt.
class PracticeResult {
  const PracticeResult({
    required this.outcome,
    required this.words,
    required this.showWords,
    required this.feedback,
  });

  factory PracticeResult.fromJson(dynamic value) {
    final json = _map(value);
    final showWords = _bool(json['showWords']);
    final words = <PracticeWord>[];
    for (final word in _list(json['words'], 64)) {
      final index = _int(word['index'], 0, 63);
      if (words.any((known) => known.index == index)) _refuse();
      words.add(PracticeWord(
          index: index, state: PracticeOutcome.parse(word['state'])));
    }
    // Words are only for the first tries and a scored attempt.
    if (!showWords && words.isNotEmpty) _refuse();
    return PracticeResult(
      outcome: PracticeOutcome.parse(json['outcome']),
      words: List.unmodifiable(words),
      showWords: showWords,
      feedback: PracticeFeedback.fromJson(json['feedback']),
    );
  }

  final PracticeOutcome outcome;
  final List<PracticeWord> words;
  final bool showWords;
  final PracticeFeedback feedback;
}

/// `GET /v1/games/dhikr`.
class DhikrGame {
  const DhikrGame({
    required this.items,
    required this.starsPerRound,
    required this.dailyStarCap,
    required this.starsToday,
  });

  factory DhikrGame.fromJson(Map<String, dynamic> json) {
    final cap = _int(json['dailyStarCap'], 0, 100);
    return DhikrGame(
      items: _adhkar(json['items'], transliterated: false),
      starsPerRound: _int(json['starsPerRound'], 0, 10),
      dailyStarCap: cap,
      starsToday: _int(json['starsToday'], 0, cap),
    );
  }

  final List<Dhikr> items;
  final int starsPerRound;
  final int dailyStarCap;
  final int starsToday;

  /// The game's stars for today are all given. The game still plays.
  bool get starsCollected => starsToday >= dailyStarCap;
}

/// A round of the dhikr game: three counted tries, or one clear one.
class DhikrRound {
  const DhikrRound({
    required this.roundId,
    required this.dhikrId,
    required this.attempts,
    required this.countedAttempts,
    required this.complete,
    required this.starAwarded,
  });

  static const tries = 3;

  factory DhikrRound.fromJson(dynamic value) {
    final json = _map(value);
    final attempts = _int(json['attempts'], 0, 100);
    final counted = _int(json['countedAttempts'], 0, tries);
    final complete = _bool(json['complete']);
    final starAwarded = _bool(json['starAwarded']);
    if (counted > attempts || (starAwarded && !complete)) _refuse();
    return DhikrRound(
      roundId: _id(json['roundId'], _identifier),
      dhikrId: _dhikrId(json['dhikrId']),
      attempts: attempts,
      countedAttempts: counted,
      complete: complete,
      starAwarded: starAwarded,
    );
  }

  final String roundId;
  final String dhikrId;
  final int attempts;
  final int countedAttempts;
  final bool complete;
  final bool starAwarded;
}

/// `POST /v1/games/dhikr/rounds/{roundId}/attempts`.
class DhikrAttempt {
  const DhikrAttempt(
      {required this.attempt, required this.round, required this.balance});

  factory DhikrAttempt.fromJson(Map<String, dynamic> json) => DhikrAttempt(
        attempt: PracticeResult.fromJson(json['attempt']),
        round: DhikrRound.fromJson(json['round']),
        balance: _int(json['balance'], 0, 1000000),
      );

  final PracticeResult attempt;
  final DhikrRound round;
  final int balance;
}

/// `POST /v1/speech/transcriptions`: what the service heard, for the child to
/// check in the composer, or nothing when it was not sure.
class Transcription {
  const Transcription({this.text});

  factory Transcription.fromJson(Map<String, dynamic> json) {
    switch (json['status']) {
      case 'transcribed':
        final text = _text(json['text'], 1000).trim();
        return Transcription(text: text);
      case 'unsure':
        if (json['text'] != null) _refuse();
        return const Transcription();
      default:
        _refuse();
    }
  }

  /// Null when the service was not sure what it heard.
  final String? text;
}

enum TurnSpeechStatus { pending, ready, unavailable }

/// One part of Robert's spoken reply.
class SpeechPart {
  const SpeechPart({required this.index, required this.ready});

  final int index;
  final bool ready;
}

/// `POST` and `GET /v1/turns/{turnId}/speech`. A part the service dropped
/// leaves the list, so its indices can have gaps.
class TurnSpeech {
  const TurnSpeech({required this.status, required this.parts});

  /// The service speaks a reply in at most six parts.
  static const maxParts = 6;

  factory TurnSpeech.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'pending' => TurnSpeechStatus.pending,
      'ready' => TurnSpeechStatus.ready,
      'unavailable' => TurnSpeechStatus.unavailable,
      _ => _refuse(),
    };
    final parts = <SpeechPart>[];
    for (final part in _list(json['parts'], maxParts)) {
      final index = _int(part['index'], 0, maxParts - 1);
      if (parts.any((known) => known.index == index)) _refuse();
      parts.add(SpeechPart(index: index, ready: _bool(part['ready'])));
    }
    // The reason is for operators and is never shown; it only has to be sane.
    final reason = json['reason'];
    if (reason != null && (reason is! String || reason.length > 200)) {
      _refuse();
    }
    parts.sort((a, b) => a.index.compareTo(b.index));
    return TurnSpeech(status: status, parts: List.unmodifiable(parts));
  }

  final TurnSpeechStatus status;

  /// In index order.
  final List<SpeechPart> parts;
}
