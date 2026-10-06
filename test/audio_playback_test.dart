import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:companion_mobile/speech/audio_playback.dart';
import 'package:companion_mobile/speech/wav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_voice.dart';

/// [AudioPlayersPlayback] over a fake plugin player, on the test's fake
/// clock. It proves nothing about Android's player, only how this class
/// reads what the plugin reports and what it does not.
void main() {
  /// Not awaited: under the widget tester's fake clock, a dispose that waits
  /// on the plugin's streams finishes on the next pump.
  Future<void> dispose(WidgetTester tester, AudioPlayback playback) async {
    unawaited(playback.dispose());
    await tester.pump();
  }

  /// One second of the service's audio.
  Uint8List oneSecond() => wavFromPcm16(Uint8List(recordingBytesPerSecond));

  Future<({FakeAudioPlayer player, AudioPlayersPlayback playback})> playing(
      WidgetTester tester, void Function() onEnd) async {
    final player = FakeAudioPlayer();
    final playback = AudioPlayersPlayback(player: () => player);
    unawaited(playback.play(oneSecond()).then((_) => onEnd()));
    await tester.pump();
    expect(player.plays, 1);
    return (player: player, playback: playback);
  }

  testWidgets('a play ends with its audio', (tester) async {
    var ended = false;
    final (:player, :playback) = await playing(tester, () => ended = true);
    expect(ended, isFalse);
    player.complete();
    await tester.pump();
    expect(ended, isTrue);
    await dispose(tester, playback);
  });

  testWidgets(
      'a play the platform paused without a word ends soon after its audio '
      'would have, and is stopped', (tester) async {
    var ended = false;
    final (:player, :playback) = await playing(tester, () => ended = true);
    // Android paused it for another app's audio focus: nothing comes.
    await tester.pump(const Duration(seconds: 3));
    expect(ended, isFalse, reason: 'one second of audio, and a little room');
    await tester.pump(const Duration(seconds: 2));
    expect(ended, isTrue);
    expect(player.stops, greaterThan(0), reason: 'it does not carry on later');
    await dispose(tester, playback);
  });

  testWidgets('a pause this class never asked for ends the play',
      (tester) async {
    var ended = false;
    final (:player, :playback) = await playing(tester, () => ended = true);
    player.report(PlayerState.paused);
    await tester.pump();
    expect(ended, isTrue);
    await dispose(tester, playback);
  });

  testWidgets('the "stopped" of a stop never ends the next play',
      (tester) async {
    final player = FakeAudioPlayer();
    final playback = AudioPlayersPlayback(player: () => player);
    var first = false, second = false;
    unawaited(playback.play(oneSecond()).then((_) => first = true));
    await tester.pump();
    unawaited(playback.play(oneSecond()).then((_) => second = true));
    await tester.pump();
    expect(first, isTrue, reason: 'the second play stopped it');
    expect(player.plays, 2);
    expect(second, isFalse);
    player.complete();
    await tester.pump();
    expect(second, isTrue);
    await dispose(tester, playback);
  });
}
