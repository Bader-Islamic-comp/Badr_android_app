import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// A cooperative stand-in for the native host and Unity receiver.
///
/// It completes the v1 handshake, records every command envelope and
/// acknowledges the commands the real receiver acknowledges. It is a test
/// double for the Flutter side of the contract only; it proves nothing about
/// Unity or a device.
class FakeUnityHost {
  FakeUnityHost(this.name, {Set<String>? capabilities})
      : capabilities = capabilities ?? AvatarBridge.supported;

  final String name;
  final Set<String> capabilities;
  final List<Map<String, dynamic>> sent = [];
  int openRoomCalls = 0;
  int disposeRoomCalls = 0;
  int _sequence = 0;
  bool installed = false;

  static const _acknowledged = {'avatar.initialize', 'avatar.set_cosmetics'};

  MethodChannel get commands => MethodChannel('$name/commands');
  EventChannel get events => EventChannel('$name/events');
  MethodChannel get _eventChannel => MethodChannel('$name/events');

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Command types in the order the host received them.
  List<String> get types =>
      [for (final message in sent) message['type'] as String];

  /// Animations requested through `avatar.play`, in order.
  List<String> get plays => [
        for (final message in sent)
          if (message['type'] == 'avatar.play')
            (message['payload'] as Map)['animation'] as String
      ];

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
        case 'sendMessage':
          final message =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          sent.add(message);
          final type = message['type'] as String;
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
