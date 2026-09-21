import 'package:flutter/material.dart';

import '../bridge/avatar_room.dart';
import '../domain/companion_controller.dart';
import '../theme.dart';
import 'widgets.dart';

/// Cosmetics. Ownership and equipment are server-authoritative: a look is only
/// pushed to the character room after the service confirms the write.
class StylePage extends StatelessWidget {
  const StylePage({
    super.key,
    required this.model,
    required this.room,
    required this.onEquipped,
  });

  final CompanionController model;
  final AvatarRoom room;
  final VoidCallback onEquipped;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Robert’s look',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
              'One original appearance. Looks are earned through learning and '
              'are never bought with real money or randomness.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (model.cosmetics.isEmpty)
            Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Robert Original',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'A static preview is always available. Connect the '
                        'development service to see the inventory it owns.'),
                  ]),
            )
          else
            for (final cosmetic in model.cosmetics)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Panel(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(cosmetic.name,
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          if (cosmetic.equipped)
                            const SectionLabel('In use', color: teal),
                        ]),
                        const SizedBox(height: 8),
                        Text(cosmetic.owned
                            ? 'Owned · confirmed by the service.'
                            : 'Not yet earned.'),
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: !cosmetic.owned || model.busy
                                ? null
                                : () async {
                                    final confirmed =
                                        await model.equipDefault();
                                    if (!confirmed) return;
                                    await room.applyServerConfirmedDefault();
                                    onEquipped();
                                  },
                            child: const Text('Use this look')),
                      ]),
                ),
              ),
          const SizedBox(height: 4),
          const Panel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline, color: orange),
              SizedBox(height: 12),
              Text('More looks are not available yet',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('Additional skins need an approved catalogue and an asset '
                  'integrity check before the room may display them.'),
            ]),
          ),
          const SizedBox(height: 16),
          ConnectionCard(
            connected: model.connected,
            configured: model.api.config.enabled,
            busy: model.busy,
            onConnect: model.connect,
          ),
        ],
      );
}
