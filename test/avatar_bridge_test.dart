import 'dart:async';
import 'dart:convert';

import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

Future<void> emitNative(String channel, Map<String, dynamic> message) {
  final handled = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
      channel,
      const StandardMethodCodec().encodeSuccessEnvelope(jsonEncode(message)),
      (_) => handled.complete());
  return handled.future;
}

Map<String, dynamic> envelope(String type, Map<String, dynamic> payload,
        {int sequence = 1000000}) =>
    {
      'schemaVersion': 1,
      'messageId': const Uuid().v4(),
      'type': type,
      'sequence': sequence,
      'payload': payload,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disposal cancels a stalled native transport deadline',
      (tester) async {
    const commands = MethodChannel('test/stalled_commands');
    const events = EventChannel('test/stalled_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final stalled = Completer<Object?>();
    messenger.setMockMethodCallHandler(commands, (_) => stalled.future);
    messenger.setMockMethodCallHandler(
        const MethodChannel('test/stalled_events'), (_) async => null);
    final bridge = AvatarBridge(commands: commands, events: events);
    final initialization = bridge.initialize();
    await tester.pump();
    bridge.dispose();
    await initialization;
    stalled.complete(null);
    await tester.pump();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('test/stalled_events'), null);
  });

  test('missing native host fails closed to static preview', () async {
    final bridge = AvatarBridge(
        timeout: const Duration(milliseconds: 20),
        startupTimeout: const Duration(milliseconds: 20));
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.staticPreview);
    expect(await bridge.openRoom(), isFalse);
    expect(await bridge.wave(), isFalse);
    bridge.dispose();
  });

  test('native transport alone is insufficient without ready and init ack',
      () async {
    const commands = MethodChannel('test/unity_commands');
    const events = EventChannel('test/unity_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(commands, (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('test/unity_events'), (_) async => null);
    final bridge = AvatarBridge(
        commands: commands,
        events: events,
        timeout: const Duration(milliseconds: 10),
        startupTimeout: const Duration(milliseconds: 10));
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.staticPreview);
    bridge.dispose();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('test/unity_events'), null);
  });

  test('negotiation gates unsupported cues and equipment needs ack', () async {
    const commands = MethodChannel('test/ready_commands');
    const events = EventChannel('test/ready_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var sequence = 0;
    final sent = <Map<String, dynamic>>[];
    Future<void> event(String type, Map<String, dynamic> payload) async {
      await emitNative('test/ready_events', {
        'schemaVersion': 1,
        'messageId': const Uuid().v4(),
        'type': type,
        'sequence': sequence++,
        'payload': payload,
      });
    }

    messenger.setMockMethodCallHandler(
        const MethodChannel('test/ready_events'), (_) async => null);
    messenger.setMockMethodCallHandler(commands, (call) async {
      final message =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      sent.add(message);
      if (message['type'] == 'avatar.initialize') {
        await event('unity.ready', {
          'characterId': 'robert',
          'capabilities': ['avatar.set_cosmetics']
        });
        await event('bridge.ack', {
          'ackMessageId': message['messageId'],
          'accepted': true,
          'reason': 'ok'
        });
      }
      return null;
    });
    final bridge = AvatarBridge(
        commands: commands,
        events: events,
        timeout: const Duration(milliseconds: 20),
        startupTimeout: const Duration(milliseconds: 20));
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.ready);
    expect(await bridge.wave(), isFalse);
    expect(sent.length, 1);
    expect(await bridge.applyServerConfirmedCosmetic('default'), isFalse);
    expect(bridge.status, AvatarStatus.staticPreview);
    expect(sent.last['payload'], {'cosmeticId': 'default'});
    bridge.dispose();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('test/ready_events'), null);
  });

  test('invalid high-sequence events cannot poison later valid handshake',
      () async {
    const commands = MethodChannel('test/strict_commands');
    const eventName = 'test/strict_events';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(eventName), (_) async => null);
    messenger.setMockMethodCallHandler(commands, (call) async {
      final command =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      final id = command['messageId'];
      final ready = {'characterId': 'robert', 'capabilities': <String>[]};
      final ack = {'ackMessageId': id, 'accepted': true, 'reason': 'ok'};
      final invalid = [
        envelope('unknown.event', {}),
        envelope('unity.ready', {
          'characterId': 'robert',
          'capabilities': [null]
        }),
        envelope('unity.ready', {
          'characterId': 'robert',
          'capabilities': ['unknown']
        }),
        envelope('unity.ready', {
          'characterId': 'robert',
          'capabilities': ['app.pause', 'app.pause']
        }),
        envelope('unity.ready', {...ready, 'unexpected': true}),
        {...envelope('unity.ready', ready), 'unexpected': true},
        {...envelope('unity.ready', ready), 'schemaVersion': 1.0},
        {...envelope('unity.ready', ready), 'messageId': 'not-a-uuid'},
        {...envelope('unity.ready', ready), 'sequence': 9007199254740992},
        {...envelope('unity.ready', ready), 'sequence': -1},
        {...envelope('unity.ready', ready), 'sequence': 1000000.5},
        envelope('bridge.ack', {'ackMessageId': id, 'accepted': true}),
        envelope('bridge.ack', {...ack, 'reason': 'unknown'}),
        envelope('bridge.ack', {...ack, 'accepted': 'true'}),
        envelope('bridge.ack', {...ack, 'reason': 'not_initialized'}),
        envelope('bridge.ack', {...ack, 'ackMessageId': 'not-a-uuid'}),
        envelope('bridge.ack', {...ack, 'unexpected': 'data'}),
        envelope('asset.failed', {}),
        envelope('asset.failed', {'code': 'other'}),
        envelope(
            'asset.failed', {'code': 'asset_unavailable', 'unexpected': true}),
      ];
      for (final message in invalid) {
        await emitNative(eventName, message);
      }
      await emitNative(eventName, envelope('unity.ready', ready, sequence: 0));
      await emitNative(eventName, envelope('bridge.ack', ack, sequence: 1));
      return null;
    });
    final bridge = AvatarBridge(
        commands: commands,
        events: const EventChannel(eventName),
        timeout: const Duration(seconds: 1));
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.ready);
    bridge.dispose();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(const MethodChannel(eventName), null);
  });

  test('malformed acknowledgement cannot complete initialization', () async {
    const commands = MethodChannel('test/malformed_ack_commands');
    const eventName = 'test/malformed_ack_events';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(eventName), (_) async => null);
    messenger.setMockMethodCallHandler(commands, (call) async {
      final command =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      await emitNative(
          eventName,
          envelope('unity.ready',
              {'characterId': 'robert', 'capabilities': <String>[]},
              sequence: 0));
      await emitNative(
          eventName,
          envelope('bridge.ack',
              {'ackMessageId': command['messageId'], 'accepted': true},
              sequence: 1));
      return null;
    });
    final bridge = AvatarBridge(
        commands: commands,
        events: const EventChannel(eventName),
        timeout: const Duration(milliseconds: 20),
        startupTimeout: const Duration(milliseconds: 20));
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.staticPreview);
    bridge.dispose();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(const MethodChannel(eventName), null);
  });
}
