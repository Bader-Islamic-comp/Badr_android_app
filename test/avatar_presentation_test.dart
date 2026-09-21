import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_unity_host.dart';

AvatarBridge connect(FakeUnityHost host, {Duration? spacing}) => AvatarBridge(
      commands: host.commands,
      events: host.events,
      timeout: const Duration(milliseconds: 60),
      reactionSpacing: spacing ?? Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a ready room stays paused until the character page is visible',
      () async {
    final host = FakeUnityHost('test/visibility')..install();
    final bridge = connect(host);
    await bridge.initialize();
    expect(bridge.status, AvatarStatus.ready);

    // Initialization alone must not start motion or a greeting.
    expect(bridge.animating, isFalse);
    expect(bridge.react(AvatarReaction.nod), isFalse);
    expect(host.types, ['avatar.initialize']);

    await bridge.setOnCharacterPage(true);
    await settle();
    expect(bridge.animating, isTrue);
    expect(host.types, ['avatar.initialize', 'app.resume', 'avatar.play']);
    expect(host.plays, ['Wave']);

    // Leaving the character page pauses the room and drops queued motion.
    await bridge.setOnCharacterPage(false);
    await settle();
    expect(bridge.animating, isFalse);
    expect(host.types.last, 'app.pause');
    expect(bridge.react(AvatarReaction.celebrate), isFalse);

    // Returning resumes, but the greeting wave runs once per room.
    await bridge.setOnCharacterPage(true);
    await settle();
    expect(host.types.last, 'app.resume');
    expect(host.plays, ['Wave']);

    bridge.dispose();
    host.remove();
  });

  test('backgrounding pauses the room and resuming restores it', () async {
    final host = FakeUnityHost('test/lifecycle')..install();
    final bridge = connect(host);
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();

    await bridge.setForeground(false);
    await settle();
    expect(bridge.animating, isFalse);
    expect(host.types.last, 'app.pause');
    expect(bridge.react(AvatarReaction.nod), isFalse);

    await bridge.setForeground(true);
    await settle();
    expect(bridge.animating, isTrue);
    expect(host.types.last, 'app.resume');
    expect(bridge.react(AvatarReaction.nod), isTrue);

    bridge.dispose();
    host.remove();
  });

  test('reduced motion stops decorative loops and automatic reactions',
      () async {
    final host = FakeUnityHost('test/motion')..install();
    final bridge = connect(host);
    await bridge.setMotionEnabled(false);
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();

    // No resume, no greeting: the room is initialized but deliberately still.
    expect(bridge.status, AvatarStatus.ready);
    expect(bridge.animating, isFalse);
    expect(host.types, ['avatar.initialize']);
    expect(bridge.react(AvatarReaction.wave), isFalse);

    await bridge.setMotionEnabled(true);
    await settle();
    expect(bridge.animating, isTrue);
    expect(host.plays, ['Wave']);

    bridge.dispose();
    host.remove();
  });

  test('a burst of taps cannot grow an unbounded animation backlog', () async {
    final host = FakeUnityHost('test/queue')..install();
    final bridge = connect(host, spacing: const Duration(seconds: 30));
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();
    expect(host.plays, ['Wave']);

    final accepted = [
      for (var tap = 0; tap < 5; tap++) bridge.react(AvatarReaction.nod)
    ];
    // One reaction leaves for the room immediately; the rest fill the bounded
    // queue and anything beyond it is refused rather than buffered.
    expect(accepted, [true, true, true, true, false],
        reason: 'the queue is bounded at ${AvatarBridge.reactionQueueLimit}');
    await settle();
    expect(host.plays, ['Wave', 'Nod']);
    expect(bridge.queuedReactions, AvatarBridge.reactionQueueLimit);

    // Pausing discards the backlog instead of replaying it later.
    await bridge.setOnCharacterPage(false);
    await settle();
    expect(bridge.queuedReactions, 0);

    bridge.dispose();
    host.remove();
  });

  test('a missing host leaves the room retryable and recreates both sides',
      () async {
    final host = FakeUnityHost('test/recreate');
    var created = 0;
    final room = AvatarRoom(
      commands: host.commands,
      create: () {
        created++;
        return connect(host);
      },
      maxAttempts: 2,
    );
    await room.start();
    expect(created, 1);
    expect(room.status, AvatarStatus.staticPreview);
    expect(room.canRetry, isTrue);

    // The operator restores the host, then the coordinator rebuilds the room.
    host.install();
    await room.setMotionEnabled(true);
    await room.setOnCharacterPage(true);
    await room.retry();
    await settle();

    expect(created, 2, reason: 'a fresh bridge, never the failed instance');
    expect(host.disposeRoomCalls, 1,
        reason: 'the native receiver is recreated with it');
    expect(room.status, AvatarStatus.ready);
    // Page and motion state are re-applied to the replacement bridge.
    expect(room.bridge.animating, isTrue);
    expect(host.plays, ['Wave']);
    expect(room.canRetry, isFalse);

    room.dispose();
    host.remove();
  });

  test('room recreation is bounded', () async {
    final host = FakeUnityHost('test/bounded');
    final room = AvatarRoom(
      commands: host.commands,
      create: () => connect(host),
      maxAttempts: 2,
    );
    await room.start();
    expect(room.canRetry, isTrue);
    await room.retry();
    expect(room.status, AvatarStatus.staticPreview);
    expect(room.canRetry, isFalse,
        reason: 'a host that never recovers must not be retried in a loop');
    room.dispose();
  });
}
