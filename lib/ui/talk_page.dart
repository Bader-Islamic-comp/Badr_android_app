import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../domain/companion_controller.dart';
import '../domain/models.dart';
import '../theme.dart';
import 'character_stage.dart';

/// The character-first main page.
///
/// Deliberately sparse: the character, and the one reply it last gave. With no
/// reply yet there is nothing on the page but Robert. Earlier answers are not
/// kept, the orientation prompt lives on Learn, the service connection lives on
/// Quests, Style and the parent area, and the room's own state and retry live
/// in the parent area — a page that is mostly character reads as a companion,
/// and a stack of cards does not. The composer lives in the shell so it stays
/// above the keyboard.
class TalkPage extends StatelessWidget {
  const TalkPage({
    super.key,
    required this.model,
    required this.room,
    required this.onTapCharacter,
    this.overRoom = false,
  });

  final CompanionController model;
  final AvatarRoom room;

  /// True when a room is composited behind the page.
  final bool overRoom;
  final VoidCallback onTapCharacter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          // Readable text and a reachable composer come first: below this the
          // character gives up its space entirely rather than squeezing the
          // reply into a few lines.
          final showCharacter = height >= 260;
          final replyLimit = (height * 0.42).clamp(96.0, 340.0);
          final reply = _reply(context);
          return Column(children: [
            if (showCharacter)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: CharacterStage(
                    status: room.status,
                    animating: room.bridge.animating,
                    motionEnabled: room.motionEnabled,
                    surfaceAttached: overRoom,
                    onTapCharacter: onTapCharacter,
                    onOpenRoom: room.status == AvatarStatus.ready
                        ? room.openRoom
                        : null,
                  ),
                ),
              ),
            if (showCharacter)
              ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: replyLimit),
                  child: reply)
            else
              // Keeps a short bubble against the composer when the reply has
              // the whole page.
              Expanded(
                  child:
                      Align(alignment: Alignment.bottomCenter, child: reply)),
          ]);
        },
      );

  /// What each kind of reply is called above its text, and in what colour, or
  /// null for no label at all.
  ///
  /// Only the service's own answer type decides this. The wording stays calm
  /// for every kind: not being sure, or being pointed to a grown-up, is not a
  /// mistake the child made, and the safeguarding label is deliberately in the
  /// steady ink colour rather than an alert one.
  ///
  /// Casual chat has no label. The bubble is already Robert talking to the
  /// child, and a label is there to say where a reply came from; chat claims
  /// to come from nowhere, so it says nothing. Left bare, it also cannot be
  /// mistaken for a library reply, which is always named and always sourced.
  static (String, Color)? labelFor(ReplyType type) => switch (type) {
        ReplyType.grounded || ReplyType.reviewedAnswer => (
            'From Robert’s library',
            teal
          ),
        ReplyType.chat => null,
        ReplyType.abstained => ('Robert isn’t sure', muted),
        ReplyType.redirected => ('Let’s ask a grown-up', orange),
        ReplyType.safety => ('You can talk to a grown-up you trust', ink),
        ReplyType.unavailable => ('Service response', teal),
      };

  /// The last reply and nothing else, sitting just above the composer. With no
  /// reply there is no bubble at all — an empty page is the character's.
  ///
  /// While Robert is thinking, the bubble says so in place of the old reply.
  /// A long reply scrolls from its beginning: grounded answers run to 1,200
  /// characters with their sources underneath, and a child should land on the
  /// first sentence, not on the sources.
  Widget _reply(BuildContext context) {
    final reply = model.reply;
    final waiting = model.waitingForReply;
    // Clearing stays reachable whenever a server conversation exists, not only
    // when a reply is on screen: a send that failed leaves one behind, and
    // deleting it is the whole point of the control.
    final clearable = model.hasConversation || model.canRetryQuestion;
    if (!waiting && reply == null && !clearable) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        liveRegion: waiting || reply != null,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: hairline),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                )),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _bubbleHeader(waiting ? null : reply),
                  if (waiting)
                    _thinking(context)
                  else if (reply == null)
                    // A conversation exists but its reply is gone: all this
                    // bubble is for now is the control that deletes it.
                    const Text('Nothing to show from this conversation.',
                        style: TextStyle(fontSize: 15, color: muted))
                  else ...[
                    Text(reply.text,
                        style: Theme.of(context).textTheme.bodyLarge),
                    if (reply.type.cited && reply.sources.isNotEmpty)
                      _sources(reply.sources),
                  ],
                ]),
          ),
        ),
      ),
    );
  }

  /// Says Robert is working on it, in place of the old reply.
  ///
  /// One line for every kind of reply. Which kind is coming is the service's
  /// decision and is not known yet, and a "hi" is not a trip to the library.
  /// The antennae are Robert's own: two, orange-tipped, on the model.
  Widget _thinking(BuildContext context) => Row(children: [
        SizedBox.square(
          dimension: 18,
          child: MediaQuery.disableAnimationsOf(context)
              // Animation is never needed to understand the page.
              ? const Icon(Icons.smart_toy_outlined, size: 18, color: teal)
              : const CircularProgressIndicator(strokeWidth: 2, color: teal),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Text('Robert is thinking… his antennae are wiggling',
              style: TextStyle(fontSize: 15, color: muted)),
        ),
      ]);

  /// Where a library reply came from, under its text. Plain text rather than
  /// links: there is nothing on the phone to open.
  Widget _sources(List<ReplySource> sources) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 10),
        width: double.infinity,
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: hairline))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sources',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
              for (final source in sources)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(source.title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: ink)),
                          Text(source.reference,
                              style:
                                  const TextStyle(fontSize: 13, color: muted)),
                        ]),
                  ),
                ),
            ]),
      );

  /// Clearing is the one control that belongs beside the reply: it removes the
  /// reply and asks the service to delete the conversation it came from. It
  /// stays usable while Robert is thinking, which also stops the wait. With no
  /// label, while thinking or for chat, the row carries the × alone.
  Widget _bubbleHeader(Reply? reply) {
    final label = reply == null ? null : labelFor(reply.type);
    return Row(children: [
      Expanded(
          child: label == null
              ? const SizedBox.shrink()
              : Text(label.$1,
                  style: TextStyle(
                      color: label.$2,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.2))),
      IconButton(
        tooltip: 'Clear development conversation',
        visualDensity: VisualDensity.compact,
        onPressed: model.canClear ? model.clearConversation : null,
        icon: const Icon(Icons.close_rounded, size: 20),
      ),
    ]);
  }
}
