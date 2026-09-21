import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../domain/companion_controller.dart';
import '../theme.dart';
import 'character_stage.dart';
import 'widgets.dart';

/// The character-first main page: character room above, validated reply surface
/// below. The composer lives in the shell so it stays above the keyboard.
class TalkPage extends StatelessWidget {
  const TalkPage({
    super.key,
    required this.model,
    required this.room,
    required this.onTapCharacter,
    required this.onStartOrientation,
    this.overRoom = false,
  });

  final CompanionController model;
  final AvatarRoom room;

  /// True when a room is composited behind the page.
  final bool overRoom;
  final VoidCallback onTapCharacter;
  final VoidCallback onStartOrientation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // Give the character room a share of the page, but surrender it
          // entirely once the reply and controls would stop being readable.
          final height = constraints.maxHeight;
          final stage =
              height < 240 ? 0.0 : (height * 0.46).clamp(140.0, 320.0);
          return Column(children: [
            if (stage > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  height: stage,
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  if (model.answer == null)
                    _greeting(context)
                  else
                    _reply(context),
                  if (model.canRetryQuestion)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Scrim(
                            enabled: overRoom,
                            child: const Text(
                                'Retry keeps the same request so the service '
                                'never receives a duplicate submission.',
                                style: TextStyle(fontSize: 13, color: muted)))),
                  if (model.hasConversation || model.canRetryQuestion)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                            onPressed:
                                model.busy ? null : model.clearConversation,
                            icon: const Icon(Icons.delete_outline),
                            label:
                                const Text('Clear development conversation'))),
                  if (!model.connected) ...[
                    const SizedBox(height: 16),
                    ConnectionCard(
                      connected: model.connected,
                      configured: model.api.config.enabled,
                      busy: model.busy,
                      onConnect: model.connect,
                    ),
                  ],
                  if (room.canRetry) ...[
                    const SizedBox(height: 16),
                    _roomRetry(context),
                  ],
                  const SizedBox(height: 16),
                  _orientationPrompt(context),
                ],
              ),
            ),
          ]);
        },
      );

  Widget _greeting(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                Text('Hello, explorer.',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text('Small steps are a lovely place to start.'),
              ]),
        ),
      );

  Widget _reply(BuildContext context) => Semantics(
        liveRegion: true,
        child: Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Service response', color: teal),
            const SizedBox(height: 10),
            Text(model.answer!, style: Theme.of(context).textTheme.bodyLarge),
          ]),
        ),
      );

  Widget _roomRetry(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The character room stopped',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              'Robert’s static preview is shown instead. Learning and chat are '
              'unaffected. Trying again rebuilds the room from scratch.'),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: room.recreating ? null : room.retry,
              child: Text(room.recreating
                  ? 'Rebuilding the room…'
                  : 'Try the character room again')),
        ]),
      );

  Widget _orientationPrompt(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Your first little step'),
          const SizedBox(height: 10),
          Text(model.orientation.title,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(model.orientation.summary),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: onStartOrientation,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(model.orientationComplete
                  ? 'Explore again'
                  : 'Let’s explore')),
          const SizedBox(height: 14),
          const Text(
              'Religious lessons and stories appear only after qualified human '
              'review. No AI provider is enabled.',
              style: TextStyle(fontSize: 13, color: muted)),
        ]),
      );
}
