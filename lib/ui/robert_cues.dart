import 'dart:async';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../domain/models.dart';

/// Starts a one-off timer. Injectable so tests control time instead of
/// waiting on it: a real delay under the widget tester's fake clock never
/// finishes.
typedef StartTimer = Timer Function(Duration duration, void Function() done);

/// Chooses Robert's presentation cues for what just happened in the app.
///
/// Every cue is a local, deterministic flourish from the bridge's allowlists,
/// picked from something the app already knows: the kind of reply the service
/// released, a tap, a look earned or worn, an orientation finished. None of it
/// is model-generated and none of it carries text. A reply reaches this class
/// only as its answer type and its length, so its words cannot reach the room
/// even by mistake.
///
/// The tone is calm. Robert talks while a reply appears and then rests. A
/// library answer earns a nod and "not sure" a curious look, but a
/// safeguarding reply or a redirect to a grown-up gets no playful face at all.
/// Nothing here is tied to faith practice or worship, and nothing is a reward:
/// rewards are the service's, and these are only presentation.
///
/// Every cue is declined while the room is not animating, which includes
/// reduced motion, so this class needs no motion checks of its own.
class RobertCues {
  RobertCues(this.room, {StartTimer? startTimer})
      : _startTimer = startTimer ?? Timer.new;

  final AvatarRoom room;
  final StartTimer _startTimer;

  /// How long Robert talks per character of reply: about 18 characters a
  /// second, an unhurried speaking pace (roughly 180 words a minute at six
  /// characters a word), so a short reply talks for about as long as saying it
  /// aloud would take.
  static const talkPerCharacter = Duration(milliseconds: 55);

  /// The shortest talk: about a third of the 4.8-second Talk loop, so even a
  /// "Hi!" reads as Robert speaking rather than a twitch between two
  /// 0.2-second crossfades.
  static const shortestTalk = Duration(milliseconds: 1500);

  /// The longest talk: about one and a half Talk loops. A library reply runs to
  /// 1,200 characters, over a minute at speaking pace; by then the child is
  /// reading, and a figure gesturing the whole time competes with the words.
  /// So Robert says the start and then rests while the child reads. Anything
  /// over about 127 characters talks for this long.
  static const longestTalk = Duration(seconds: 7);

  /// How long Robert talks for a reply of [characters] characters, counted as
  /// the service counts them. The length is all this takes from a reply.
  static Duration talkDuration(int characters) {
    final spoken = talkPerCharacter * characters;
    if (spoken < shortestTalk) return shortestTalk;
    if (spoken > longestTalk) return longestTalk;
    return spoken;
  }

  /// Tapping Robert cycles through these, one per accepted tap.
  static const _tapCycle = [
    _Body(AvatarReaction.wave),
    _Face(AvatarEmotion.giggle),
    _Face(AvatarEmotion.wink),
  ];

  static const _lookEarned = [_Face(AvatarEmotion.starry)];
  static const _lookWorn = [_Body(AvatarReaction.celebrate)];
  static const _orientationCompleted = [
    _Body(AvatarReaction.celebrate),
    _Face(AvatarEmotion.starry),
  ];

  Timer? _talk;
  int _taps = 0;
  bool _disposed = false;

  /// A moment that happened while Robert was off screen, played the next time
  /// he is shown. Only the latest is kept: coming back to Robert brings one
  /// small celebration, not a replay of everything that happened meanwhile.
  List<_Cue>? _held;

  /// True while a talk is running and its end is still scheduled.
  bool get talking => _talk != null;

  /// A reply was released and is on screen: Robert talks for a time worked
  /// out from its length, then rests, then gives the reply type's after-talk
  /// cue. Nothing happens when the room is not animating.
  void replyShown(ReplyType type, int characters) {
    quiet();
    if (_disposed || !room.startTalking()) return;
    _talk = _startTimer(talkDuration(characters), () => _finishTalk(type));
  }

  /// Stops talking now, with no after-talk cue: the reply was cleared, a new
  /// question started or Robert is leaving the screen.
  void quiet() {
    _talk?.cancel();
    _talk = null;
    room.stopTalking();
  }

  /// The app left the foreground. A held moment is forgotten too, so Robert
  /// does not celebrate something from before the break.
  void backgrounded() {
    quiet();
    _held = null;
  }

  /// Robert is on screen again. A moment held while he was away plays now,
  /// once, and is dropped if the room cannot play it.
  void characterShown() {
    final held = _held;
    _held = null;
    if (held != null && !_disposed) _sendAll(held);
  }

  /// Robert's voice is reading a reply aloud (the speech preview's Listen):
  /// he talks for as long as it plays, with the same decorative Talk loop.
  /// No audio and no text reach the room, only the loop. A reply's own talk
  /// stops first, without its after-talk cue.
  void voiceStarted() {
    quiet();
    if (!_disposed) room.startTalking();
  }

  /// Robert's voice stopped: he rests.
  void voiceEnded() => room.stopTalking();

  /// Tapping Robert: a wave, then a giggle, then a wink, and round again. The
  /// cycle only moves on when a cue is accepted, so a tap the bounded queue
  /// refused does not skip one. Returns whether this tap was accepted.
  bool tapped() {
    if (_disposed || !_send(_tapCycle[_taps % _tapCycle.length])) return false;
    _taps++;
    return true;
  }

  /// A look was earned, confirmed by the service: starry eyes.
  void lookEarned() => _moment(_lookEarned);

  /// A look is being worn, confirmed by the service: a celebration.
  void lookWorn() => _moment(_lookWorn);

  /// The orientation was completed: a celebration, then starry eyes.
  void orientationCompleted() => _moment(_orientationCompleted);

  void dispose() {
    _disposed = true;
    _talk?.cancel();
    _talk = null;
    _held = null;
  }

  void _finishTalk(ReplyType type) {
    _talk = null;
    // False when a pause, a fallback or a rebuilt room already ended the talk:
    // an after-talk cue then belongs to nothing.
    if (_disposed || !room.stopTalking()) return;
    final after = _afterTalk(type);
    if (after != null) _send(after);
    final held = _held;
    _held = null;
    if (held != null) _sendAll(held);
  }

  /// What follows a finished talk. Only the service's answer type decides it;
  /// the text is never looked at.
  _Cue? _afterTalk(ReplyType type) {
    switch (type) {
      case ReplyType.grounded:
      case ReplyType.reviewedAnswer:
        return const _Body(AvatarReaction.nod);
      case ReplyType.abstained:
        return const _Face(AvatarEmotion.curious);
      // Casual chat gets no face either. The service's reply to "I am sad
      // today" is also `chat`, and the app may not read a reply to tell them
      // apart, so a smile here could follow a child's sad feeling. A playful
      // face after chat needs a non-text tone signal from the service first.
      case ReplyType.chat:
      // Calm and serious: a safeguarding reply and a redirect to a grown-up
      // get no playful face. Robert talks, then rests.
      case ReplyType.safety:
      case ReplyType.redirected:
      case ReplyType.unavailable:
        return null;
    }
  }

  void _moment(List<_Cue> cues) {
    if (_disposed) return;
    if (room.animating && !room.talking) {
      _sendAll(cues);
    } else {
      _held = cues;
    }
  }

  void _sendAll(List<_Cue> cues) {
    for (final cue in cues) {
      _send(cue);
    }
  }

  bool _send(_Cue cue) => switch (cue) {
        _Body(:final reaction) => room.react(reaction),
        _Face(:final emotion) => room.express(emotion),
      };
}

sealed class _Cue {
  const _Cue();
}

final class _Body extends _Cue {
  const _Body(this.reaction);
  final AvatarReaction reaction;
}

final class _Face extends _Cue {
  const _Face(this.emotion);
  final AvatarEmotion emotion;
}
