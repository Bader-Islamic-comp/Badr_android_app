import 'package:flutter/material.dart';

Future<void> showParentSheet(
  BuildContext context, {
  required bool motionEnabled,
  required ValueChanged<bool> onMotionChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ParentSheet(
        motionEnabled: motionEnabled,
        onMotionChanged: onMotionChanged,
      ),
    );

class _ParentSheet extends StatefulWidget {
  const _ParentSheet({
    required this.motionEnabled,
    required this.onMotionChanged,
  });

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
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to preview'))),
              ]),
        ),
      );
}
