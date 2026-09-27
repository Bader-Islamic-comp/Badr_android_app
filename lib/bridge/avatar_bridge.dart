import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

enum AvatarStatus { staticPreview, connecting, ready }

/// Brief one-shot body clips. The room returns to Standing on its own; Flutter
/// does not track completion because bridge v1 carries no
/// `animation.completed`.
enum AvatarReaction { wave, nod, celebrate }

/// One-shot faces. The room plays one once and then returns to its resting
/// blink by itself. These are authored expressions chosen by the app for what
/// just happened, never emotion recognition.
enum AvatarEmotion {
  neutral,
  happy,
  surprised,
  joy,
  giggle,
  wink,
  curious,
  wow,
  sleepy,
  bashful,
  starry,
}

/// Presentation commands only; no free-text payload API is exposed to callers.
class AvatarBridge extends ChangeNotifier {
  AvatarBridge({
    MethodChannel? commands,
    EventChannel? events,
    this.timeout = const Duration(seconds: 3),
    this.startupTimeout = const Duration(seconds: 30),
    this.reactionSpacing = const Duration(milliseconds: 1200),
  })  : _commands = commands ?? const MethodChannel('companion/unity_commands'),
        _events = events ?? const EventChannel('companion/unity_events');

  final MethodChannel _commands;
  final EventChannel _events;
  final Duration timeout;

  /// Deadline for the two calls that wait on the engine starting, rather than
  /// on a room that is already running: [probeSurface] and the initialization
  /// handshake.
  ///
  /// Both wait on the host constructing the Unity engine and loading the scene,
  /// which takes many seconds — around nine on the development emulator — where
  /// an ordinary bridge message takes milliseconds. Using [timeout] for them
  /// reports "no room" on exactly the devices least able to afford losing one,
  /// and it did: the handshake deadlined before the engine had finished
  /// starting on every single launch, so the room rendered and the bridge never
  /// connected.
  final Duration startupTimeout;

  /// Minimum gap between queued reactions, so a burst of taps cannot turn into
  /// continuous motion.
  final Duration reactionSpacing;

  final Map<String, Completer<bool>> _pending = {};
  final Set<VoidCallback> _cancelWaits = {};
  final Set<String> _seen = {};
  final Queue<_Cue> _reactions = Queue();
  Set<String> _capabilities = {};
  StreamSubscription<dynamic>? _subscription;
  Completer<bool>? _ready;
  Timer? _reactionTimer;
  Completer<void>? _reactionDelay;
  int _sequence = 0;
  int _incomingSequence = -1;
  bool _disposed = false;
  bool _draining = false;
  bool _greeted = false;

  /// True between [startTalking] and whatever ends the talk: [stopTalking], a
  /// pause, a fallback or disposal.
  bool _talking = false;

  /// The last policy actually delivered to the room, so repeated UI events do
  /// not resend `app.pause`/`app.resume`.
  bool _presenting = false;
  bool _onCharacterPage = false;
  bool _foreground = true;
  bool _motionEnabled = true;

  AvatarStatus status = AvatarStatus.staticPreview;

  static const supported = {
    'avatar.play',
    'avatar.set_emotion',
    'avatar.set_cosmetics',
    'app.pause',
    'app.resume',
  };

  /// Looks the room was built with.
  ///
  /// The room carries its own copy of this list and installs nothing outside
  /// it. Checking here too means an id the service invented is dropped before
  /// it reaches the native boundary, rather than tearing the room down on a
  /// rejection.
  static const cosmetics = {
    'default', 'sunset', 'dune', 'midnight', // colourways of the original model
    'casual', 'cowboy', 'astronaut', 'arab-thobe', 'explorer',
    'gardener', // outfits
  };

  /// Body clips `avatar.play` may name. Case-sensitive, and exactly the
  /// schema's list: `Talk` is a body clip here, never the lowercase face.
  ///
  /// `Standing` is the resting loop and `Talk` loops until the next play;
  /// `Idle` is an alias of Standing that the room keeps for older senders and
  /// this app never sends. The other three are one-shots.
  static const animations = {
    'Standing', 'Idle', 'Wave', 'Talk', 'Nod', 'Celebrate', //
  };

  /// Faces `avatar.set_emotion` may name, exactly the schema's list.
  static const emotions = {
    'neutral', 'happy', 'surprised', 'joy', 'giggle', 'wink', //
    'curious', 'wow', 'sleepy', 'bashful', 'starry',
  };

  /// A burst of taps must not become an animation backlog.
  static const reactionQueueLimit = 3;

  static const _standing = 'Standing';
  static const _talk = 'Talk';

  static const _clips = {
    AvatarReaction.wave: 'Wave',
    AvatarReaction.nod: 'Nod',
    AvatarReaction.celebrate: 'Celebrate',
  };

  static final _faces = {
    for (final emotion in AvatarEmotion.values) emotion: emotion.name,
  };

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static const _reasons = {
    'ok',
    'invalid_envelope',
    'message_id_conflict',
    'stale_sequence',
    'asset_unavailable',
    'already_initialized',
    'not_initialized',
    'unsupported_capability',
    'presentation_rejected',
  };

  /// True when the room should currently be animating: initialized, on the
  /// character page, in the foreground and with motion allowed.
  bool get animating =>
      status == AvatarStatus.ready &&
      _onCharacterPage &&
      _foreground &&
      _motionEnabled;

  bool get motionEnabled => _motionEnabled;

  /// True while the room has been told to loop Talk and nothing has ended it.
  bool get talking => _talking;

  @visibleForTesting
  int get queuedReactions => _reactions.length;

  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  static bool _validEvent(dynamic message) {
    if (message is! Map ||
        !_keys(message,
            {'schemaVersion', 'messageId', 'type', 'sequence', 'payload'}) ||
        message['schemaVersion'] is! int ||
        message['schemaVersion'] != 1 ||
        message['messageId'] is! String ||
        !_uuid.hasMatch(message['messageId'] as String) ||
        message['sequence'] is! int ||
        (message['sequence'] as int) < 0 ||
        (message['sequence'] as int) > 9007199254740991 ||
        message['payload'] is! Map) {
      return false;
    }
    final payload = message['payload'] as Map;
    switch (message['type']) {
      case 'unity.ready':
        if (!_keys(payload, {'characterId', 'capabilities'}) ||
            payload['characterId'] != 'robert' ||
            payload['capabilities'] is! List) {
          return false;
        }
        final capabilities = payload['capabilities'] as List;
        return capabilities.length <= supported.length &&
            capabilities.every(
                (value) => value is String && supported.contains(value)) &&
            capabilities.toSet().length == capabilities.length;
      case 'bridge.ack':
        return _keys(payload, {'ackMessageId', 'accepted', 'reason'}) &&
            payload['ackMessageId'] is String &&
            _uuid.hasMatch(payload['ackMessageId'] as String) &&
            payload['accepted'] is bool &&
            _reasons.contains(payload['reason']) &&
            ((payload['accepted'] == true) == (payload['reason'] == 'ok'));
      case 'asset.failed':
        return _keys(payload, {'code'}) &&
            payload['code'] == 'asset_unavailable';
      default:
        return false;
    }
  }

  Future<void> initialize() async {
    if (_disposed ||
        status != AvatarStatus.staticPreview ||
        _subscription != null) {
      return;
    }
    status = AvatarStatus.connecting;
    notifyListeners();
    final ready = Completer<bool>();
    _ready = ready;
    _subscription = _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object _) => _fallback(),
          onDone: _fallback,
        );
    try {
      final accepted = await _send(
          'avatar.initialize',
          {
            'characterId': 'robert',
            'capabilities': supported.toList(),
          },
          acknowledgement: true,
          deadline: startupTimeout);
      final negotiated = await _wait(ready.future, deadline: startupTimeout);
      if (!_disposed &&
          accepted &&
          negotiated &&
          status == AvatarStatus.connecting) {
        status = AvatarStatus.ready;
        notifyListeners();
        await _applyPresentationPolicy();
      } else {
        _fallback();
      }
    } catch (_) {
      _fallback();
    }
  }

  void _onEvent(dynamic event) {
    if (_disposed ||
        event is! String ||
        event.length > 16384 ||
        utf8.encode(event).length > 16384) {
      return;
    }
    try {
      final message = jsonDecode(event);
      if (!_validEvent(message)) return;
      final sequence = message['sequence'] as int;
      final id = message['messageId'] as String;
      if (sequence <= _incomingSequence || _seen.contains(id)) return;
      _incomingSequence = sequence;
      _seen.add(id);
      if (_seen.length > 128) _seen.remove(_seen.first);
      final payload = message['payload'] as Map;
      switch (message['type']) {
        case 'unity.ready':
          _capabilities =
              (payload['capabilities'] as List).cast<String>().toSet();
          if (_ready?.isCompleted == false) _ready!.complete(true);
        case 'bridge.ack':
          final completer = _pending[payload['ackMessageId']];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload['accepted'] == true);
          }
        case 'asset.failed':
          _fallback();
      }
    } catch (_) {
      // Malformed native events never affect the learning experience.
    }
  }

  /// [deadline] overrides [timeout] for the one exchange that waits on the
  /// engine starting rather than on a room that is already answering.
  Future<bool> _send(String type, Map<String, dynamic> payload,
      {bool acknowledgement = false, Duration? deadline}) async {
    if (_disposed) return false;
    if (type != 'avatar.initialize' &&
        (status != AvatarStatus.ready || !_capabilities.contains(type))) {
      return false;
    }
    final id = const Uuid().v4();
    final completer = acknowledgement ? Completer<bool>() : null;
    if (completer != null) _pending[id] = completer;
    try {
      final delivered = await _wait(
          _commands
              .invokeMethod<void>(
                  'sendMessage',
                  jsonEncode({
                    'schemaVersion': 1,
                    'messageId': id,
                    'sequence': _sequence++,
                    'type': type,
                    'payload': payload,
                  }))
              .then((_) => true),
          deadline: deadline);
      if (!delivered) {
        _fallback();
        return false;
      }
      return completer == null ||
          await _wait(completer.future, deadline: deadline);
    } catch (_) {
      _fallback();
      return false;
    } finally {
      _pending.remove(id);
    }
  }

  /// Whether the host has a room surface composited at all.
  ///
  /// Deliberately independent of [status]: the surface exists as soon as the
  /// host attaches it, long before — or entirely without — a negotiated
  /// bridge. The UI needs this to decide whether it may paint transparently,
  /// and painting transparently with nothing behind it would show through to
  /// an empty window.
  Future<bool> probeSurface() async {
    if (_disposed) return false;
    try {
      return await _wait(
          _commands
              .invokeMethod<bool>('roomSurface')
              .then((value) => value ?? false),
          requireReady: false,
          deadline: startupTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<bool> openRoom() async {
    if (status != AvatarStatus.ready) return false;
    try {
      final opened = await _wait(
          _commands.invokeMethod<void>('openRoom').then((_) => true));
      if (!opened) _fallback();
      return opened;
    } catch (_) {
      _fallback();
      return false;
    }
  }

  /// Caller must first confirm the server-owned inventory and equipment write.
  ///
  /// A look this build does not ship is refused without touching the room:
  /// the room is not broken, it simply has nothing to install.
  Future<bool> applyServerConfirmedCosmetic(String cosmeticId) async {
    if (!cosmetics.contains(cosmeticId)) return false;
    final result = await _send(
        'avatar.set_cosmetics', {'cosmeticId': cosmeticId},
        acknowledgement: true);
    if (!result) _fallback();
    return result;
  }

  Future<bool> wave() => _play(_clips[AvatarReaction.wave]!);

  /// Sends one allowlisted body clip. The last guard before the native
  /// boundary: a name outside [animations] never leaves Flutter.
  Future<bool> _play(String clip) async =>
      animations.contains(clip) &&
      await _send('avatar.play', {'animation': clip});

  /// Sends one allowlisted face, guarded like [_play].
  Future<bool> _face(String face) async =>
      emotions.contains(face) &&
      await _send('avatar.set_emotion', {'emotion': face});

  /// Starts Robert's Talk loop, which runs until something ends it.
  ///
  /// Only the cue crosses the bridge: whatever Robert is "saying" stays in
  /// Flutter, and so does the decision of how long he says it for. Returns
  /// false, sending nothing, when the room is not animating — paused, hidden,
  /// backgrounded or under reduced motion — because talking is body motion.
  ///
  /// A reply takes precedence over queued tap reactions, so any backlog is
  /// dropped rather than played over the talk.
  bool startTalking() {
    if (!animating || !_capabilities.contains('avatar.play')) return false;
    if (_talking) return true;
    _discardReactions();
    _talking = true;
    unawaited(_play(_talk));
    return true;
  }

  /// Ends a talk by returning the room to Standing, which also stops the
  /// talking mouth and brings back the resting blink.
  ///
  /// Returns true only when this call ended a live talk. False means there was
  /// nothing to end: it was never started, or a pause or fallback already ended
  /// it. Callers use that to decide whether an after-talk cue still belongs.
  bool stopTalking() {
    if (!_talking) return false;
    _talking = false;
    if (!animating) return false;
    unawaited(_play(_standing));
    return true;
  }

  /// The character page became visible or hidden. Leaving the page pauses the
  /// room; ordinary learning and chat continue without it.
  Future<void> setOnCharacterPage(bool value) async {
    if (_onCharacterPage == value) return;
    _onCharacterPage = value;
    await _applyPresentationPolicy();
  }

  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    await _applyPresentationPolicy();
  }

  /// Reduced-motion disables decorative loops and automatic reactions. It is a
  /// presentation preference only and never changes what a reply says.
  Future<void> setMotionEnabled(bool value) async {
    if (_motionEnabled == value) return;
    _motionEnabled = value;
    notifyListeners();
    await _applyPresentationPolicy();
  }

  Future<void> _applyPresentationPolicy() async {
    final desired = animating;
    if (desired == _presenting) return;
    _presenting = desired;
    if (!desired) {
      _discardReactions();
      // A paused room holds the clip it was playing and declines cues until it
      // resumes, so a talk has to end before the pause, not after it:
      // otherwise Robert comes back still talking to nobody. Dispatch is
      // synchronous, so Standing reaches the room ahead of `app.pause`.
      if (_talking) {
        _talking = false;
        unawaited(_play(_standing));
      }
    }
    final delivered = await _send(desired ? 'app.resume' : 'app.pause', {});
    if (!delivered || _disposed) return;
    if (desired && !_greeted) {
      _greeted = true;
      react(AvatarReaction.wave);
    }
  }

  /// Queues a brief body reaction. Returns false when the room is not
  /// animating, Robert is talking or the bounded queue is full; callers treat
  /// that as ordinary, not an error.
  bool react(AvatarReaction reaction) =>
      _enqueue(_Cue(face: false, name: _clips[reaction]!));

  /// Queues a one-shot face in the same bounded, spaced queue as [react].
  ///
  /// Declined whenever [react] would be. A face changing is motion too — the
  /// giggle alternates frames, and every face animates back to the resting
  /// blink — and a paused room declines it anyway. It is also declined while
  /// Robert talks: a face would cut off the talking mouth, so a talk is ended
  /// with [stopTalking] first.
  bool express(AvatarEmotion emotion) =>
      _enqueue(_Cue(face: true, name: _faces[emotion]!));

  bool _enqueue(_Cue cue) {
    if (!animating || _talking || _reactions.length >= reactionQueueLimit) {
      return false;
    }
    _reactions.add(cue);
    unawaited(_drainReactions());
    return true;
  }

  Future<void> _drainReactions() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_reactions.isNotEmpty && animating && !_disposed) {
        final cue = _reactions.removeFirst();
        await (cue.face ? _face(cue.name) : _play(cue.name));
        if (_disposed || !animating || _reactions.isEmpty) break;
        await _delay(reactionSpacing);
      }
    } finally {
      _draining = false;
      if (_disposed || !animating) _discardReactions();
    }
  }

  // Timer-based spacing rather than an `animation.completed` event: adding one
  // would expand bridge v1, and the roadmap treats animation cues as
  // best-effort. The room owns its own return to Standing.
  Future<void> _delay(Duration duration) {
    final completer = Completer<void>();
    _reactionTimer?.cancel();
    _reactionDelay = completer;
    _reactionTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _discardReactions() {
    _reactions.clear();
    _reactionTimer?.cancel();
    _reactionTimer = null;
    if (_reactionDelay?.isCompleted == false) _reactionDelay!.complete();
    _reactionDelay = null;
  }

  // Future.timeout timers cannot be cancelled when a native host disappears.
  // Own deadlines explicitly so fallback/disposal settles all pending work.
  /// [requireReady] false is for calls that are legitimate before a bridge
  /// exists, such as asking the host whether it composited a surface at all.
  /// Everything else is abandoned the moment the room is not usable.
  Future<bool> _wait(Future<bool> source,
      {bool requireReady = true, Duration? deadline}) {
    final result = Completer<bool>();
    late Timer timer;
    late VoidCallback cancel;
    void finish(bool value) {
      timer.cancel();
      _cancelWaits.remove(cancel);
      if (!result.isCompleted) result.complete(value);
    }

    cancel = () => finish(false);
    timer = Timer(deadline ?? timeout, cancel);
    _cancelWaits.add(cancel);
    source.then(finish, onError: (Object _, StackTrace __) => finish(false));
    if (_disposed || (requireReady && status == AvatarStatus.staticPreview)) {
      cancel();
    }
    return result.future;
  }

  void _cancelDeadlines() {
    for (final cancel in _cancelWaits.toList()) {
      cancel();
    }
  }

  void _fallback() {
    if (_disposed) return;
    _cancelDeadlines();
    _discardReactions();
    _talking = false;
    _capabilities = {};
    _presenting = false;
    if (_ready?.isCompleted == false) _ready!.complete(false);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    status = AvatarStatus.staticPreview;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelDeadlines();
    _discardReactions();
    _talking = false;
    if (_ready?.isCompleted == false) _ready!.complete(false);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _subscription?.cancel();
    super.dispose();
  }
}

/// One queued one-shot: a body clip or a face, by allowlisted name only.
class _Cue {
  const _Cue({required this.face, required this.name});

  /// True for `avatar.set_emotion`, false for `avatar.play`.
  final bool face;
  final String name;
}
