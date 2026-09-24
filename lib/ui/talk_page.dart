import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../domain/companion_controller.dart';
import '../theme.dart';
import 'character_stage.dart';
import 'widgets.dart';

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
              Expanded(child: reply),
          ]);
        },
      );

  /// The last answer and nothing else, sitting just above the composer. With no
  /// answer there is no bubble at all — an empty page is the character's.
  /// `reverse` keeps a short bubble against the composer and lets a long answer
  /// scroll from its end.
  Widget _reply(BuildContext context) {
    final answer = model.answer;
    // Clearing stays reachable whenever a server conversation exists, not only
    // when an answer is on screen: a send that failed leaves one behind, and
    // deleting it is the whole point of the control.
    final clearable = model.hasConversation || model.canRetryQuestion;
    if (answer == null && !clearable) return const SizedBox.shrink();
    return ListView(
      reverse: true,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        Semantics(
          liveRegion: answer != null,
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
                    _bubbleHeader(answer),
                    if (answer == null)
                      // A conversation exists but its answer is gone: all this
                      // bubble is for now is the control that deletes it.
                      const Text('Nothing to show from this conversation.',
                          style: TextStyle(fontSize: 15, color: muted))
                    else
                      Text(answer,
                          style: Theme.of(context).textTheme.bodyLarge),
                  ]),
            ),
          ),
        ),
      ],
    );
  }

  /// Clearing is the one control that belongs beside the reply: it removes the
  /// answer and asks the service to delete the conversation it came from.
  Widget _bubbleHeader(String? answer) => Row(children: [
        Expanded(
            child: answer == null
                ? const SizedBox.shrink()
                : const SectionLabel('Service response', color: teal)),
        IconButton(
          tooltip: 'Clear development conversation',
          visualDensity: VisualDensity.compact,
          onPressed: model.busy ? null : model.clearConversation,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ]);
}
