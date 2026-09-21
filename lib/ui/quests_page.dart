import 'package:flutter/material.dart';

import '../domain/companion_controller.dart';
import '../theme.dart';
import 'widgets.dart';

/// Challenges and the server-owned reward balance. There is no streak, ranking
/// or loss framing here, and nothing claims religious merit.
class QuestsPage extends StatelessWidget {
  const QuestsPage({super.key, required this.model});

  final CompanionController model;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Every little step counts',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
              'A record of learning effort. Take your time; there is no streak '
              'to keep.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (model.challenges.isEmpty)
            _localChallenge(context)
          else
            for (final challenge in model.challenges)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Panel(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.flag_outlined, color: teal, size: 30),
                        const SizedBox(height: 12),
                        Text(challenge.title,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(challenge.description),
                        const SizedBox(height: 14),
                        Text(
                            challenge.completed
                                ? 'Completed · confirmed by the service'
                                : model.orientationComplete
                                    ? 'Explored on this device'
                                    : 'Ready when you are',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        if (model.orientationComplete &&
                            model.connected &&
                            !challenge.completed)
                          TextButton(
                              onPressed:
                                  model.busy ? null : model.completeOrientation,
                              child: const Text('Save demo completion')),
                      ]),
                ),
              ),
          _balance(context),
          const SizedBox(height: 16),
          ConnectionCard(
            connected: model.connected,
            configured: model.api.config.enabled,
            busy: model.busy,
            onConnect: model.connect,
          ),
        ],
      );

  Widget _localChallenge(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.flag_outlined, color: teal, size: 30),
            const SizedBox(height: 12),
            Text('Explore one learning activity',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Complete the orientation with Robert.'),
            const SizedBox(height: 14),
            Text(
                model.orientationComplete
                    ? 'Explored on this device'
                    : 'Ready when you are',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _balance(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.stars_rounded, color: orange, size: 32),
          const SizedBox(height: 12),
          Text(
              model.balance == null
                  ? 'Learning stars'
                  : '${model.balance} learning stars',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(model.balance == null
              ? 'Connect to view your server-owned demo balance.'
              : 'Last confirmed by the development service. Stars represent '
                  'learning effort, never religious merit.'),
        ]),
      );
}
