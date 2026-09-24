import 'package:flutter/material.dart';

import '../bridge/avatar_room.dart';
import '../domain/companion_controller.dart';
import 'character_stage.dart';
import 'widgets.dart';

Future<void> showParentSheet(
  BuildContext context, {
  required CompanionController model,
  required AvatarRoom room,
  required bool motionEnabled,
  required ValueChanged<bool> onMotionChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ParentSheet(
        model: model,
        room: room,
        motionEnabled: motionEnabled,
        onMotionChanged: onMotionChanged,
      ),
    );

class _ParentSheet extends StatefulWidget {
  const _ParentSheet({
    required this.model,
    required this.room,
    required this.motionEnabled,
    required this.onMotionChanged,
  });

  final CompanionController model;
  final AvatarRoom room;
  final bool motionEnabled;
  final ValueChanged<bool> onMotionChanged;

  @override
  State<_ParentSheet> createState() => _ParentSheetState();
}

class _ParentSheetState extends State<_ParentSheet> {
  late bool motionEnabled = widget.motionEnabled;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parent area · prototype',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 14),
                const Text(
                    'This is an adult-operated development preview. This screen '
                    'is not an authenticated parental gate and does not collect '
                    'or establish guardian consent.'),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: motionEnabled,
                  onChanged: (value) {
                    setState(() => motionEnabled = value);
                    widget.onMotionChanged(value);
                  },
                  secondary: Icon(motionEnabled
                      ? Icons.motion_photos_on_outlined
                      : Icons.motion_photos_off_outlined),
                  title: const Text('Character motion'),
                  subtitle: const Text(
                      'Turn off to stop idle movement and reactions. Robert '
                      'stays visible and every reply is still readable. This '
                      'follows your device’s reduce-motion setting by default.'),
                ),
                // The room's own state used to sit on the character page, over
                // Robert's face. It is developer state: what belongs here is
                // what an adult would act on, which is whether it is running
                // and how to restart it.
                ListenableBuilder(
                  listenable: widget.room,
                  builder: (context, _) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(CharacterStage.statusLabel(
                      widget.room.status,
                      widget.room.bridge.animating,
                      widget.room.surfaceAttached,
                    )),
                    subtitle: const Text(
                        'Learning and chat do not depend on the room. Robert '
                        'falls back to a still picture if it stops.'),
                    trailing: widget.room.canRetry || widget.room.recreating
                        ? TextButton(
                            onPressed: widget.room.recreating
                                ? null
                                : widget.room.retry,
                            child: Text(widget.room.recreating
                                ? 'Rebuilding…'
                                : 'Restart'))
                        : null,
                  ),
                ),
                const Divider(height: 32),
                const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.mic_off_outlined),
                    title: Text('Voice is off'),
                    subtitle:
                        Text('No microphone access or audio collection.')),
                const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.menu_book_outlined),
                    title: Text('Content awaits review'),
                    subtitle:
                        Text('No religious curriculum or generated stories are '
                            'published, and no AI provider is enabled.')),
                const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Synthetic data only'),
                    subtitle: Text(
                        'Do not enter child information. Real accounts, '
                        'consent, export and profile deletion require further '
                        'implementation and review.')),
                const SizedBox(height: 16),
                // The service is developer-operated, so its connection belongs
                // with the other adult controls rather than on the character
                // page, which now carries only Robert and his last reply.
                ListenableBuilder(
                  listenable: widget.model,
                  builder: (context, _) => ConnectionCard(
                    connected: widget.model.connected,
                    configured: widget.model.api.config.enabled,
                    busy: widget.model.busy,
                    onConnect: widget.model.connect,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to preview'))),
              ]),
        ),
      );
}
