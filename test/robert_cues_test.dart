import 'package:companion_mobile/bridge/avatar_bridge.dart';
import 'package:companion_mobile/bridge/avatar_room.dart';
import 'package:companion_mobile/domain/models.dart';
import 'package:companion_mobile/ui/robert_cues.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_unity_host.dart';

/// A ready room on the character page, with the greeting already sent and
/// forgotten, driven by cues whose talk timers only fire when told to.
class Stage {
  Stage._(this.host, this.room, this.timers, this.cues);

  static Future<Stage> open(String name,
      {bool motion = true, Duration spacing = Duration.zero}) async {
    final host = FakeUnityHost(name)..install();
    final room = AvatarRoom(
      commands: host.commands,
      create: () => AvatarBridge(
        commands: host.commands,
        events: host.events,
        timeout: const Duration(milliseconds: 60),
        startupTimeout: const Duration(milliseconds: 60),
        reactionSpacing: spacing,
      ),
    );
    await room.start();
    await room.setMotionEnabled(motion);
    await room.setOnCharacterPage(true);
    await settle();
    expect(room.status, AvatarStatus.ready);
    host.sent.clear();
    final timers = ManualTimers();
    return Stage._(
        host, room, timers, RobertCues(room, startTimer: timers.start));
  }

  final FakeUnityHost host;
  final AvatarRoom room;
  final ManualTimers timers;
  final RobertCues cues;

  /// Shows a reply, lets its talk run to the end, and returns what the room
  /// was sent for it.
  Future<List<String>> talkThrough(ReplyType type, int characters) async {
    final before = host.cues.length;
    cues.replyShown(type, characters);
    await settle();
    timers.last.fire();
    await settle();
    return host.cues.sublist(before);
  }

  Future<void> close() async {
    expect(host.declined, isEmpty,
        reason: 'no cue was sent that a paused room would drop');
    expect(host.refused, isEmpty, reason: 'every name is in the contract');
    cues.dispose();
    room.dispose();
    host.remove();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('talk time comes from the reply length, within bounds', () {
    expect(RobertCues.talkDuration(0), const Duration(milliseconds: 1500));
    expect(RobertCues.talkDuration(3), const Duration(milliseconds: 1500),
        reason: 'even "Hi!" reads as talking');
    expect(RobertCues.talkDuration(45), const Duration(milliseconds: 2475));
    expect(RobertCues.talkDuration(100), const Duration(milliseconds: 5500));
    expect(RobertCues.talkDuration(127), const Duration(milliseconds: 6985));
    expect(RobertCues.talkDuration(1200), const Duration(seconds: 7),
        reason: 'a long reply is not a minute of gesturing');
  });

  test('Robert talks while a reply appears, then rests and nods', () async {
    final stage = await Stage.open('test/cues_talk');
    stage.cues.replyShown(ReplyType.grounded, 45);
    await settle();
    expect(stage.host.cues, ['Talk']);
    expect(stage.cues.talking, isTrue);
    expect(stage.timers.last.duration, const Duration(milliseconds: 2475));

    stage.timers.last.fire();
    await settle();
    // Standing first: it ends the talking mouth before anything else plays.
    expect(stage.host.cues, ['Talk', 'Standing', 'Nod']);
    expect(stage.cues.talking, isFalse);
    await stage.close();
  });

  for (final (type, after) in [
    (ReplyType.grounded, ['Nod']),
    (ReplyType.reviewedAnswer, ['Nod']),
    (ReplyType.abstained, ['face:curious']),
    (ReplyType.chat, <String>[]),
    // Calm and serious: talk, then rest, with nothing playful after.
    (ReplyType.safety, <String>[]),
    (ReplyType.redirected, <String>[]),
    (ReplyType.unavailable, <String>[]),
  ]) {
    test(
        'a ${type.wire} reply is followed by ${after.isEmpty ? 'rest alone' : after.single}',
        () async {
      final stage = await Stage.open('test/cues_${type.wire}');
      expect(await stage.talkThrough(type, 80), ['Talk', 'Standing', ...after]);
      await stage.close();
    });
  }

  test('safeguarding and redirect replies never get a playful face', () async {
    final stage = await Stage.open('test/cues_serious');
    for (var reply = 0; reply < 4; reply++) {
      await stage.talkThrough(ReplyType.safety, 200);
      await stage.talkThrough(ReplyType.redirected, 200);
    }
    expect(stage.host.faces, isEmpty);
    expect(stage.host.plays.toSet(), {'Talk', 'Standing'});
    await stage.close();
  });

  test('chat never gets a face: a reply to a sad feeling is chat too',
      () async {
    final stage = await Stage.open('test/cues_chat');
    for (var reply = 0; reply < 4; reply++) {
      expect(await stage.talkThrough(ReplyType.chat, 40), ['Talk', 'Standing']);
    }
    expect(stage.host.faces, isEmpty);
    await stage.close();
  });

  test('quiet stops the talk at once, with no after-talk cue', () async {
    final stage = await Stage.open('test/cues_quiet');
    stage.cues.replyShown(ReplyType.grounded, 80);
    await settle();
    final timer = stage.timers.last;

    stage.cues.quiet();
    await settle();
    expect(stage.host.cues, ['Talk', 'Standing']);
    expect(timer.isActive, isFalse, reason: 'the scheduled end is cancelled');
    timer.fire();
    await settle();
    expect(stage.host.cues, ['Talk', 'Standing'], reason: 'no late nod');
    await stage.close();
  });

  test('a pause mid-talk ends it, and drops the after-talk cue', () async {
    final stage = await Stage.open('test/cues_pause');
    stage.cues.replyShown(ReplyType.grounded, 80);
    await settle();
    await stage.room.setOnCharacterPage(false);
    await settle();
    expect(stage.host.cues, ['Talk', 'Standing', 'pause']);

    // The talk's scheduled end still runs, but finds nothing to end.
    stage.timers.last.fire();
    await stage.room.setOnCharacterPage(true);
    await settle();
    expect(stage.host.cues, ['Talk', 'Standing', 'pause', 'resume']);
    await stage.close();
  });

  test('a new reply restarts the talk rather than stacking a second one',
      () async {
    final stage = await Stage.open('test/cues_restart');
    stage.cues.replyShown(ReplyType.grounded, 80);
    final first = stage.timers.last;
    stage.cues.replyShown(ReplyType.abstained, 20);
    await settle();
    expect(first.isActive, isFalse);
    expect(stage.timers.active, hasLength(1));
    stage.timers.last.fire();
    await settle();
    expect(stage.host.cues,
        ['Talk', 'Standing', 'Talk', 'Standing', 'face:curious']);
    await stage.close();
  });

  test('tapping cycles a wave, a giggle and a wink', () async {
    final stage = await Stage.open('test/cues_tap');
    for (var tap = 0; tap < 4; tap++) {
      expect(stage.cues.tapped(), isTrue);
      await settle();
    }
    expect(stage.host.cues, ['Wave', 'face:giggle', 'face:wink', 'Wave']);
    await stage.close();
  });

  test('a declined tap does not skip a step of the cycle', () async {
    final stage = await Stage.open('test/cues_tap_bound',
        spacing: const Duration(seconds: 30));
    final accepted = [for (var tap = 0; tap < 5; tap++) stage.cues.tapped()];
    // The queue's bound applies to taps exactly as before.
    expect(accepted, [true, true, true, true, false]);
    await settle();
    expect(stage.host.cues, ['Wave'], reason: 'the rest wait their spacing');

    // While talking, a tap is declined and the cycle stays where it was.
    final talk = await Stage.open('test/cues_tap_talk');
    talk.cues.replyShown(ReplyType.chat, 10);
    expect(talk.cues.tapped(), isFalse);
    talk.timers.last.fire();
    await settle();
    expect(talk.cues.tapped(), isTrue);
    await settle();
    expect(talk.host.cues, ['Talk', 'Standing', 'Wave']);
    await stage.close();
    await talk.close();
  });

  test('a look earned off screen brings starry eyes when Robert is next shown',
      () async {
    final stage = await Stage.open('test/cues_earned');
    await stage.room.setOnCharacterPage(false);
    stage.cues.lookEarned();
    await settle();
    expect(stage.host.faces, isEmpty, reason: 'Robert is not on screen');

    await stage.room.setOnCharacterPage(true);
    stage.cues.characterShown();
    await settle();
    expect(stage.host.faces, ['starry']);

    // Once only.
    await stage.room.setOnCharacterPage(false);
    await stage.room.setOnCharacterPage(true);
    stage.cues.characterShown();
    await settle();
    expect(stage.host.faces, ['starry']);

    // With Robert on screen, it plays straight away.
    stage.cues.lookEarned();
    await settle();
    expect(stage.host.faces, ['starry', 'starry']);
    await stage.close();
  });

  test('wearing a look celebrates; finishing orientation celebrates twice over',
      () async {
    final stage = await Stage.open('test/cues_moments');
    stage.cues.lookWorn();
    await settle();
    expect(stage.host.cues, ['Celebrate']);

    stage.host.sent.clear();
    stage.cues.orientationCompleted();
    await settle();
    expect(stage.host.cues, ['Celebrate', 'face:starry']);
    await stage.close();
  });

  test('only the latest moment is held, and backgrounding forgets it',
      () async {
    final stage = await Stage.open('test/cues_held');
    await stage.room.setOnCharacterPage(false);
    stage.cues.lookEarned();
    stage.cues.lookWorn();
    await stage.room.setOnCharacterPage(true);
    stage.cues.characterShown();
    await settle();
    expect(stage.host.cues, ['pause', 'resume', 'Celebrate'],
        reason: 'one celebration on return, not a replay');

    await stage.room.setOnCharacterPage(false);
    stage.cues.orientationCompleted();
    stage.cues.backgrounded();
    await stage.room.setOnCharacterPage(true);
    stage.cues.characterShown();
    await settle();
    expect(stage.host.cues.skip(3), ['pause', 'resume']);
    await stage.close();
  });

  test('reduced motion: no talk, no reactions and no faces', () async {
    final stage = await Stage.open('test/cues_still', motion: false);
    stage.cues.replyShown(ReplyType.grounded, 80);
    expect(stage.timers.started, isEmpty, reason: 'no talk to time');
    expect(stage.cues.tapped(), isFalse);
    stage.cues.lookEarned();
    stage.cues.characterShown();
    await settle();
    expect(stage.host.sent, isEmpty);
    await stage.close();
  });

  test('only cue names cross the bridge', () async {
    final stage = await Stage.open('test/cues_payloads');
    await stage.talkThrough(ReplyType.grounded, 300);
    await stage.talkThrough(ReplyType.abstained, 30);
    stage.cues.tapped();
    stage.cues.lookEarned();
    await settle();
    for (final message in stage.host.sent) {
      final payload = message['payload'] as Map;
      expect(payload.keys.toList(),
          anyOf(equals(['animation']), equals(['emotion'])));
      expect(
          AvatarBridge.animations.contains(payload['animation']) ||
              AvatarBridge.emotions.contains(payload['emotion']),
          isTrue);
    }
    await stage.close();
  });
}
