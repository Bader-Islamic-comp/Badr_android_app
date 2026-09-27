import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// A cooperative stand-in for the native host and Unity receiver.
///
/// It completes the v1 handshake, records every command envelope and
/// acknowledges the commands the real receiver acknowledges. Like the
/// receiver, it declines cues while paused and refuses names outside the
/// contract; both are recorded rather than acknowledged, because cues are
/// best-effort and Flutter never hears about them. It is a test double for
/// the Flutter side of the contract only; it proves nothing about Unity or a
/// device.
class FakeUnityHost {
  FakeUnityHost(this.name, {Set<String>? capabilities})
      : capabilities = capabilities ?? AvatarBridge.supported;

  final String name;
  final Set<String> capabilities;
  final List<Map<String, dynamic>> sent = [];

  /// Cues that arrived while the room was paused, which it would drop.
  final List<String> declined = [];

  /// Cues naming a clip or face outside the contract, which it would refuse.
  final List<String> refused = [];

  /// Whether the host reports a composited room surface.
  bool surfaceAttached = true;
  int openRoomCalls = 0;
  int disposeRoomCalls = 0;
  int _sequence = 0;
  bool installed = false;

  /// Paused until the first `app.resume`: Flutter has no business cueing a
  /// room it has not yet resumed.
  bool paused = true;

  static const _acknowledged = {'avatar.initialize', 'avatar.set_cosmetics'};

  /// The receiver's allowlists, from the bridge contract. Deliberately a copy
  /// rather than the app's own lists, so a name the app adds that the room
  /// does not know shows up in [refused].
  static const _animations = {
    'Standing', 'Idle', 'Wave', 'Talk', 'Nod', 'Celebrate', //
  };
  static const _emotions = {
    'neutral', 'happy', 'surprised', 'joy', 'giggle', 'wink', //
    'curious', 'wow', 'sleepy', 'bashful', 'starry',
  };

  MethodChannel get commands => MethodChannel('$name/commands');
  EventChannel get events => EventChannel('$name/events');
  MethodChannel get _eventChannel => MethodChannel('$name/events');

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Command types in the order the host received them.
  List<String> get types =>
      [for (final message in sent) message['type'] as String];

  /// Looks requested through `avatar.set_cosmetics`, in order.
  List<String> get looks => [
        for (final message in sent)
          if (message['type'] == 'avatar.set_cosmetics')
            (message['payload'] as Map)['cosmeticId'] as String
      ];

  /// Animations requested through `avatar.play`, in order.
  List<String> get plays => [
        for (final message in sent)
          if (message['type'] == 'avatar.play')
            (message['payload'] as Map)['animation'] as String
      ];

  /// Faces requested through `avatar.set_emotion`, in order.
  List<String> get faces => [
        for (final message in sent)
          if (message['type'] == 'avatar.set_emotion')
            (message['payload'] as Map)['emotion'] as String
      ];

  /// Every cue and pause/resume, in order, as the room saw them: a play as
  /// its clip name (`Talk`), a face as `face:<name>`, and `pause`/`resume`.
  List<String> get cues => [
        for (final message in sent)
          switch (message['type']) {
            'avatar.play' => (message['payload'] as Map)['animation'] as String,
            'avatar.set_emotion' =>
              'face:${(message['payload'] as Map)['emotion']}',
            'app.pause' => 'pause',
            'app.resume' => 'resume',
            _ => null,
          }
      ].whereType<String>().toList();

  void install() {
    installed = true;
    _messenger.setMockMethodCallHandler(_eventChannel, (_) async => null);
    _messenger.setMockMethodCallHandler(commands, (call) async {
      switch (call.method) {
        case 'openRoom':
          openRoomCalls++;
          return null;
        case 'disposeRoom':
          disposeRoomCalls++;
          return null;
        case 'roomSurface':
          return surfaceAttached;
        case 'sendMessage':
          final message =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          sent.add(message);
          final type = message['type'] as String;
          final payload = message['payload'] as Map;
          switch (type) {
            case 'app.pause':
              paused = true;
            case 'app.resume':
              paused = false;
            case 'avatar.play' || 'avatar.set_emotion':
              final cue = type == 'avatar.play'
                  ? payload['animation'] as String
                  : 'face:${payload['emotion']}';
              final known = type == 'avatar.play'
                  ? _animations.contains(payload['animation'])
                  : _emotions.contains(payload['emotion']);
              if (!known) {
                refused.add(cue);
              } else if (paused) {
                declined.add(cue);
              }
          }
          if (type == 'avatar.initialize') {
            await _emit('unity.ready', {
              'characterId': 'robert',
              'capabilities': capabilities.toList(),
            });
          }
          if (_acknowledged.contains(type)) {
            await _emit('bridge.ack', {
              'ackMessageId': message['messageId'],
              'accepted': true,
              'reason': 'ok',
            });
          }
          return null;
        default:
          return null;
      }
    });
  }

  void remove() {
    installed = false;
    _messenger.setMockMethodCallHandler(commands, null);
    _messenger.setMockMethodCallHandler(_eventChannel, null);
  }

  Future<void> _emit(String type, Map<String, dynamic> payload) {
    final handled = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
        '$name/events',
        const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode({
          'schemaVersion': 1,
          'messageId': const Uuid().v4(),
          'type': type,
          'sequence': _sequence++,
          'payload': payload,
        })),
        (_) => handled.complete());
    return handled.future;
  }
}

/// Lets queued reaction work and channel callbacks run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Hands out timers that fire only when a test says so, so talk durations are
/// checked without waiting on any clock, real or fake.
class ManualTimers {
  final List<ManualTimer> started = [];

  Timer start(Duration duration, void Function() done) {
    final timer = ManualTimer(duration, done);
    started.add(timer);
    return timer;
  }

  ManualTimer get last => started.last;

  /// Timers started and neither fired nor cancelled.
  Iterable<ManualTimer> get active => started.where((timer) => timer.isActive);
}

class ManualTimer implements Timer {
  ManualTimer(this.duration, this._done);

  final Duration duration;
  final void Function() _done;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  /// Runs the callback, unless the timer was cancelled or already fired.
  void fire() {
    if (!_active) return;
    _active = false;
    _done();
  }
}
