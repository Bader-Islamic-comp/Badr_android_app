import 'package:flutter/material.dart';

import '../domain/companion_controller.dart';
import '../theme.dart';
import 'widgets.dart';

class LearnPage extends StatelessWidget {
  const LearnPage({
    super.key,
    required this.model,
    required this.step,
    required this.onStep,
    required this.onFinish,
  });

  final CompanionController model;
  final int? step;
  final ValueChanged<int?> onStep;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final lesson = model.orientation;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text('Room to learn', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(
            'Orientation · ${lesson.steps.length} small steps · Available offline',
            style: const TextStyle(color: muted)),
        const SizedBox(height: 20),
        Panel(
          child: step == null
              ? _intro(context, lesson.title, lesson.summary)
              : _stepper(context, lesson.steps, step!),
        ),
        const SizedBox(height: 16),
        const Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.bookmark_border, color: orange),
            SizedBox(height: 12),
            Text('Stories are still being prepared',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
                'Religious lessons and stories will appear only after qualified '
                'human review of an approved source corpus.'),
          ]),
        ),
      ],
    );
  }

  Widget _intro(BuildContext context, String title, String summary) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.menu_book_rounded, size: 36, color: teal),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(summary),
        const SizedBox(height: 20),
        _action(
          label:
              model.orientationComplete ? 'Explore again' : 'Start orientation',
          hint: 'Opens the first orientation step',
          onPressed: () => onStep(0),
        ),
      ]);

  Widget _stepper(BuildContext context, List<String> steps, int index) {
    final last = index >= steps.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel('Step ${index + 1} of ${steps.length}'),
      const SizedBox(height: 14),
      LinearProgressIndicator(
          value: (index + 1) / steps.length,
          semanticsLabel:
              'Orientation progress, step ${index + 1} of ${steps.length}'),
      const SizedBox(height: 24),
      Text(steps[index], style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 24),
      // Explicit semantics: a browser accessibility check previously found the
      // orientation controls missing from the tree.
      Wrap(spacing: 12, runSpacing: 12, children: [
        _action(
          label: last ? 'Finish exploring' : 'Next step',
          hint: last
              ? 'Completes the orientation and opens your quests'
              : 'Opens orientation step ${index + 2}',
          onPressed: model.busy
              ? null
              : () async {
                  if (last) {
                    await onFinish();
                  } else {
                    onStep(index + 1);
                  }
                },
        ),
        MergeSemantics(
          child: Semantics(
            hint: 'Leaves the orientation without losing progress',
            child: TextButton(
                onPressed: () => onStep(null),
                child: const Text('Pause for now')),
          ),
        ),
      ]),
    ]);
  }

  Widget _action({
    required String label,
    required String hint,
    required VoidCallback? onPressed,
  }) =>
      // The button supplies the role, label, enabled state and tap action; the
      // hint is merged into that same node rather than replacing it, so the
      // activation path stays intact.
      MergeSemantics(
        child: Semantics(
          hint: hint,
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        ),
      );
}
