import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_unity_host.dart';

AvatarBridge connect(FakeUnityHost host, {Duration? spacing}) => AvatarBridge(
      commands: host.commands,
      events: host.events,
      timeout: const Duration(milliseconds: 60),
      startupTimeout: const Duration(milliseconds: 60),
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

  test('Talk loops until Standing ends it, and holds back taps and faces',
      () async {
    final host = FakeUnityHost('test/talk')..install();
    final bridge = connect(host);
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();
    expect(host.plays, ['Wave'], reason: 'the greeting');

    expect(bridge.startTalking(), isTrue);
    await settle();
    expect(bridge.talking, isTrue);
    expect(host.plays, ['Wave', 'Talk']);

    // A tap or a face would cut the talk, and the face its talking mouth.
    expect(bridge.react(AvatarReaction.wave), isFalse);
    expect(bridge.express(AvatarEmotion.giggle), isFalse);
    await settle();
    expect(host.plays, ['Wave', 'Talk']);
    expect(host.faces, isEmpty);

    expect(bridge.stopTalking(), isTrue);
    await settle();
    expect(bridge.talking, isFalse);
    expect(host.plays, ['Wave', 'Talk', 'Standing']);
    expect(bridge.stopTalking(), isFalse, reason: 'nothing left to end');

    // At rest again, a face plays.
    expect(bridge.express(AvatarEmotion.curious), isTrue);
    await settle();
    expect(host.faces, ['curious']);
    expect(host.declined, isEmpty);
    expect(host.refused, isEmpty);

    bridge.dispose();
    host.remove();
  });

  for (final (label, leave) in [
    (
      'leaving the character page',
      (AvatarBridge b) => b.setOnCharacterPage(false)
    ),
    ('backgrounding', (AvatarBridge b) => b.setForeground(false)),
    ('turning motion off', (AvatarBridge b) => b.setMotionEnabled(false)),
  ]) {
    test('$label ends a talk before the room pauses', () async {
      final host = FakeUnityHost('test/talk_pause')..install();
      final bridge = connect(host);
      await bridge.initialize();
      await bridge.setOnCharacterPage(true);
      await settle();
      bridge.startTalking();
      await settle();

      await leave(bridge);
      await settle();
      // Standing reaches the room while it still accepts cues, so it comes
      // back at rest rather than still talking.
      expect(host.cues, ['resume', 'Wave', 'Talk', 'Standing', 'pause']);
      expect(bridge.talking, isFalse);
      expect(bridge.stopTalking(), isFalse,
          reason: 'the pause already ended it, so no after-talk cue belongs');
      expect(host.declined, isEmpty);

      bridge.dispose();
      host.remove();
    });
  }

  test('reduced motion sends no talk, no reactions and no faces', () async {
    final host = FakeUnityHost('test/still')..install();
    final bridge = connect(host);
    await bridge.setMotionEnabled(false);
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();

    expect(bridge.startTalking(), isFalse);
    expect(bridge.talking, isFalse);
    for (final reaction in AvatarReaction.values) {
      expect(bridge.react(reaction), isFalse);
    }
    // Faces are declined too: every one animates back to the resting blink,
    // and the room is paused under reduced motion, where it declines them.
    for (final emotion in AvatarEmotion.values) {
      expect(bridge.express(emotion), isFalse);
    }
    await settle();
    expect(host.types, ['avatar.initialize']);

    bridge.dispose();
    host.remove();
  });

  test('a reply takes precedence over queued taps', () async {
    final host = FakeUnityHost('test/precedence')..install();
    final bridge = connect(host, spacing: const Duration(seconds: 30));
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();
    for (var tap = 0; tap < 3; tap++) {
      bridge.react(AvatarReaction.nod);
    }
    await settle();
    expect(host.plays, ['Wave', 'Nod']);
    expect(bridge.queuedReactions, 2);

    expect(bridge.startTalking(), isTrue);
    await settle();
    expect(bridge.queuedReactions, 0,
        reason: 'the backlog is dropped, not played over the talk');
    expect(host.plays, ['Wave', 'Nod', 'Talk']);

    bridge.dispose();
    host.remove();
  });

  test('faces share the bounded, spaced reaction queue', () async {
    final host = FakeUnityHost('test/face_queue')..install();
    final bridge = connect(host, spacing: const Duration(seconds: 30));
    await bridge.initialize();
    await bridge.setOnCharacterPage(true);
    await settle();
    final accepted = [
      bridge.express(AvatarEmotion.giggle),
      bridge.react(AvatarReaction.wave),
      bridge.express(AvatarEmotion.wink),
      bridge.express(AvatarEmotion.joy),
      bridge.express(AvatarEmotion.starry),
    ];
    expect(accepted, [true, true, true, true, false]);
    await settle();
    expect(host.cues, ['resume', 'Wave', 'face:giggle']);
    expect(bridge.queuedReactions, AvatarBridge.reactionQueueLimit);

    bridge.dispose();
    host.remove();
  });

  test('every typed cue is inside the contract allowlists', () {
    expect({for (final emotion in AvatarEmotion.values) emotion.name},
        AvatarBridge.emotions,
        reason: 'each face the room knows has exactly one typed name');
    expect(AvatarBridge.animations,
        containsAll(['Standing', 'Talk', 'Wave', 'Nod', 'Celebrate']));
    expect(AvatarBridge.animations, isNot(contains('talk')),
        reason: 'lowercase talk is the face cycle, not a body clip');
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
